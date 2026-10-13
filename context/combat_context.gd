extends Context
class_name CombatContext

## The Context managing the combat game state and continuous Roguelite loop.
##
## Manages Turn Order, grid logic, player mouse interactions via math-based raycasting,
## round scaling, continuous game-to-game progression, and Hades / Vampire Survivors style
## 3-choice power-up blessing upgrades.

@export var old_man_data: ActorData
@export var girl_data: ActorData
@export var monster_data: ActorData

var grid_manager: GridManager
var turn_manager: TurnManager
var monster_ai: MonsterAIController
var girl_ai: GirlAIController
var combat_ui: CombatUI
var roguelite_manager: RogueliteManager

## The actor currently being controlled by the player this turn.
var active_actor: Actor

## Node container holding the spawned Actor instances.
var actors_node: Node3D

## Active monsters tracked in the current round
var current_round_monsters: Array[Actor] = []

## Flag to block user input while animations/tweens are resolving.
var is_acting: bool = false

## Flag to enforce 1 movement action per turn.
var has_moved_this_turn: bool = false

## Combo system variables
var combo_count: int = 0
var combo_timer: float = 0.0
var combo_active: bool = false
var hit_monsters_this_turn: Array[Actor] = []
var can_heal: bool = true
var heals_remaining_this_turn: int = 1

# ⚡ Bolt Optimization: Pre-calculate special attack directions to avoid array allocations at runtime
const SPECIAL_ATTACK_DIRS: Array[Vector2i] = [
	Vector2i(-2, -2), Vector2i(-2, -1), Vector2i(-2, 0), Vector2i(-2, 1), Vector2i(-2, 2),
	Vector2i(-1, -2), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(-1, 2),
	Vector2i(0, -2), Vector2i(0, -1), Vector2i(0, 1), Vector2i(0, 2),
	Vector2i(1, -2), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1), Vector2i(1, 2),
	Vector2i(2, -2), Vector2i(2, -1), Vector2i(2, 0), Vector2i(2, 1), Vector2i(2, 2)
]

## Visual mesh that hovers over valid target squares
var hover_indicator: MeshInstance3D

# ⚡ Bolt Optimization: Cache hovered cell to prevent O(1) rendering tree updates on mouse motion
var _last_hovered_cell: Vector2i = Vector2i(-1, -1)

## Builds and registers the child Service nodes required for Combat.
func build_services() -> void:
	grid_manager = GridManager.new()
	register_service(grid_manager)
	
	turn_manager = TurnManager.new()
	register_service(turn_manager)
	
	monster_ai = MonsterAIController.new()
	register_service(monster_ai)
	
	girl_ai = GirlAIController.new()
	register_service(girl_ai)
	
	combat_ui = CombatUI.new()
	register_service(combat_ui)
	
	roguelite_manager = RogueliteManager.new()
	register_service(roguelite_manager)

## Connects dependent services together.
func bind_services() -> void:
	pass

## Initializes the combat state, draws the grid, and spawns the initial run wave.
func setup() -> void:
	if Global.has_method("play_combat_music"):
		Global.play_combat_music()
	grid_manager.setup()
	turn_manager.setup()
	monster_ai.setup(grid_manager, turn_manager)
	girl_ai.setup(grid_manager, turn_manager)
	combat_ui.setup(turn_manager, grid_manager)
	roguelite_manager.setup()
	
	# Listen for turn changes to update player controls and UI
	turn_manager.turn_started.connect(_on_turn_started)
	
	_draw_visual_grid()
	_init_run_actors()

## Called automatically when the TurnManager cycles to a new phase.
## Configures the active actor, highlights the grid, and toggles monster visibility.
func _on_turn_started(phase: TurnManager.TurnPhase) -> void:
	active_actor = null
	is_acting = false
	has_moved_this_turn = false
	combo_count = 0
	combo_active = false
	hit_monsters_this_turn.clear()
	
	var req_combo = 2 if roguelite_manager.has_perk("adrenaline_flow") else 3
	if combat_ui:
		combat_ui.update_combo(0, 0.0, req_combo)
	grid_manager.clear_highlights()
	
	# 1. Determine the active player actor
	if phase == TurnManager.TurnPhase.MAN:
		active_actor = _find_actor_by_name("Old Man")
		heals_remaining_this_turn = 2 if roguelite_manager.has_perk("guardian_medic") else 1
		can_heal = true
		if combat_ui:
			var heal_range = 3 if roguelite_manager.has_perk("guardian_medic") else 1
			combat_ui.update_heal_ui(heals_remaining_this_turn, heal_range)
		
	# 2. Toggle Monster Visibility (Invis Monster Mechanic)
	# Monsters are ONLY visible during the Girl's turn.
	# ⚡ Bolt Optimization: Iterate dictionary keys natively to avoid .values() Array allocation
	for pos in grid_manager.grid:
		var actor = grid_manager.grid[pos]
		if is_instance_valid(actor) and actor.is_monster():
			var should_be_visible = (phase == TurnManager.TurnPhase.GIRL)
			if actor.model:
				actor.model.visible = should_be_visible
		
	# 3. If a player turn started but their character is dead, auto-skip
	if phase == TurnManager.TurnPhase.MAN:
		if active_actor == null:
			print("CombatContext: Skipping turn because active_actor is null for phase ", turn_manager.get_phase_name(phase))
			turn_manager.end_turn()
			return
		else:
			print("CombatContext: Active actor is ", active_actor.get_actor_name())
		
	# 4. Highlight the walkable/attackable grid for the player
	if active_actor:
		grid_manager.highlight_attack_range(active_actor)
		print("CombatContext: Highlighted attack range for ", active_actor.get_actor_name())

## Helper to locate a specific actor instance by their base name.
func _find_actor_by_name(actor_name: String) -> Actor:
	# ⚡ Bolt Optimization: Iterate dictionary keys natively to avoid .values() Array allocation
	for pos in grid_manager.grid:
		var actor = grid_manager.grid[pos]
		if actor.get_actor_name() == actor_name:
			return actor
	return null

## Intercepts mouse and keyboard inputs for combat actions.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_H:
			if turn_manager.current_phase == TurnManager.TurnPhase.MAN and not is_acting:
				_handle_heal()
		return
		
	if event is InputEventMouseMotion or (event is InputEventMouseButton and (event.button_index == MOUSE_BUTTON_LEFT or event.button_index == MOUSE_BUTTON_RIGHT) and event.pressed):
		var camera = get_viewport().get_camera_3d()
		if not camera: return
		
		var mouse_pos = event.position
		var ray_origin = camera.project_ray_origin(mouse_pos)
		var ray_normal = camera.project_ray_normal(mouse_pos)
		
		if ray_normal.y == 0: return 
		var t = -ray_origin.y / ray_normal.y
		if t < 0: return 
		
		var intersection = ray_origin + ray_normal * t
		var grid_x = floor(intersection.x / GridManager.CELL_SIZE)
		var grid_z = floor(intersection.z / GridManager.CELL_SIZE)
		
		if event is InputEventMouseMotion:
			var current_cell = Vector2i(grid_x, grid_z)
			if current_cell != _last_hovered_cell:
				_last_hovered_cell = current_cell
				if grid_manager.is_in_bounds(grid_x, grid_z):
					hover_indicator.show()
					var wpos = grid_manager.get_world_position(grid_x, grid_z)
					wpos.y = 0.02
					hover_indicator.position = wpos
				elif hover_indicator:
					hover_indicator.hide()

			if grid_manager.is_in_bounds(grid_x, grid_z):
				return
			
		elif event is InputEventMouseButton:
			if turn_manager.current_phase == TurnManager.TurnPhase.MONSTERS or is_acting:
				return 
				
			if active_actor == null:
				return
				
			if event.button_index == MOUSE_BUTTON_RIGHT:
				var req_combo = 2 if roguelite_manager.has_perk("adrenaline_flow") else 3
				if active_actor.get_actor_name() == "Old Man" and combo_count >= req_combo:
					_handle_special_attack()
				elif active_actor.get_actor_name() == "Old Man":
					print("Special attack not ready! Need Combo ", req_combo, "+")
				return
				
			_handle_grid_click(grid_x, grid_z)

## Processes the logical intent of clicking a grid cell.
func _handle_grid_click(x: int, z: int) -> void:
	if not active_actor or active_actor.get_actor_name() != "Old Man": return
	
	var target_pos = Vector2i(x, z)
	if not grid_manager.visual_cells.has(target_pos): return
	
	var mesh = grid_manager.visual_cells[target_pos] as MeshInstance3D
	var mat = mesh.material_override as StandardMaterial3D
	
	# Verify that the cell is currently highlighted for attack
	var is_red = mat and mat.albedo_color == Color(0.8, 0.2, 0.2, 1.0)
	var is_highlighted = grid_manager._highlighted_cells.has(target_pos)
	
	if not is_red and not is_highlighted:
		# If highlights were inadvertently cleared during Old Man's turn, restore them
		if grid_manager._highlighted_cells.is_empty():
			grid_manager.highlight_attack_range(active_actor)
		print("Click a red square to attack!")
		return
		
	is_acting = true
	await _execute_blind_attack(active_actor, x, z)
	is_acting = false

## Executes the AOE Whirlwind Special Attack for the Old Man.
func _handle_special_attack() -> void:
	if Global.has_method("play_special_attack"): Global.play_special_attack()
	is_acting = true
	combo_count = 0
	combo_active = false
	var req_combo = 2 if roguelite_manager.has_perk("adrenaline_flow") else 3
	if combat_ui:
		combat_ui.update_combo(0, 0.0, req_combo)
	
	print("SPECIAL AOE ATTACK ACTIVATED!")
	
	var actor = active_actor
	var tween = actor.create_tween()
	var original_pos = actor.model.position
	
	var base_dmg = actor.get_damage()
	if roguelite_manager.has_perk("whirlwind_tempest"):
		base_dmg += 6
		
	var apR: AnimationPlayer = actor.axe_right_ap
	var apL: AnimationPlayer = actor.axe_left_ap

	# ⚡ Bolt Optimization: Use the pre-calculated constant array
	for dir in SPECIAL_ATTACK_DIRS:
		var nx = actor.grid_x + dir.x
		var nz = actor.grid_z + dir.y
		if not grid_manager.is_in_bounds(nx, nz):
			continue
			
		var target_wpos = grid_manager.get_world_position(nx, nz)
		var local_target = target_wpos - actor.global_position
		local_target.y = original_pos.y
		
		# Rotate to face target then dash
		tween.tween_callback(func():
			var look_pos = target_wpos
			look_pos.y = actor.model.global_position.y
			if actor.model.global_position.distance_squared_to(look_pos) > 0.001:
				actor.model.look_at(look_pos, Vector3.UP, true)
		)
		tween.tween_property(actor.model, "position", local_target, 0.04)
		
		# Apply damage at peak
		tween.tween_callback(func():
			if apR:
				apR.stop()
				apR.play("Axe10_001Action")
			if apL:
				apL.stop()
				apL.play("AtkAxe01")
					
			var target = grid_manager.get_actor_at(nx, nz)
			if target and target.is_monster():
				print("Whirlwind Hit on ", target.name, " for ", base_dmg, " damage!")
				if is_instance_valid(target) and is_instance_valid(target.model):
					target.model.visible = true
					var t = target.create_tween()
					t.tween_interval(0.5)
					t.tween_callback(func(): if is_instance_valid(target) and is_instance_valid(target.model): target.model.visible = false)
				target.take_damage(base_dmg)
				if Global.has_method("play_monster_wounded"): Global.play_monster_wounded()
				
				# Tempest Fury: blast hit enemies backward
				if roguelite_manager.has_perk("whirlwind_tempest") and is_instance_valid(target) and target.current_health > 0:
					var blast_dir = Vector2i(sign(target.grid_x - actor.grid_x), sign(target.grid_z - actor.grid_z))
					if blast_dir == Vector2i.ZERO: blast_dir = Vector2i(0, 1)
					var kx = target.grid_x + blast_dir.x
					var kz = target.grid_z + blast_dir.y
					if grid_manager.is_cell_walkable(kx, kz):
						grid_manager.move_actor(target, kx, kz)
		)
		
		# Dash back
		tween.tween_property(actor.model, "position", original_pos, 0.04)
		
	tween.tween_callback(func():
		actor.model.position = original_pos
		is_acting = false
		print("Special Attack Finished! Turn ends.")
		turn_manager.end_turn()
	)

## Executes the heal ability on the Little Girl.
func _handle_heal() -> void:
	if not can_heal or heals_remaining_this_turn <= 0: return
	
	var girl = _find_actor_by_name("Little Girl")
	var old_man = _find_actor_by_name("Old Man")
	if not girl or not is_instance_valid(girl) or girl.current_health <= 0 or not old_man: return
	
	var max_range = 3 if roguelite_manager.has_perk("guardian_medic") else 1
	var dist = abs(old_man.grid_x - girl.grid_x) + abs(old_man.grid_z - girl.grid_z)
	
	if dist > max_range:
		print("Little Girl is too far to heal! (Distance: ", dist, ", Max Range: ", max_range, ")")
		return
		
	heals_remaining_this_turn -= 1
	if heals_remaining_this_turn <= 0:
		can_heal = false
		
	var heal_amt = 10 if roguelite_manager.has_perk("guardian_medic") else 5
	if Global.has_method("play_heal_sound"): Global.play_heal_sound()
	girl.current_health = min(girl.current_health + heal_amt, girl.get_max_health())
	print("Little Girl healed for ", heal_amt, " HP! Current HP: ", girl.current_health)
	
	# Flash green
	if is_instance_valid(girl.model):
		var mat = girl.model.material_override as StandardMaterial3D
		if mat:
			var orig_color = mat.albedo_color
			mat.albedo_color = Color(0.2, 1.0, 0.4)
			var t = get_tree().create_tween()
			t.tween_interval(0.3)
			t.tween_callback(func(): if is_instance_valid(girl.model) and mat: mat.albedo_color = orig_color)
			
	# Update UI
	if combat_ui:
		if heals_remaining_this_turn > 0:
			combat_ui.update_heal_ui(heals_remaining_this_turn, max_range)
		else:
			combat_ui.clear_heal_ui()

## Executes the fast-paced blind attack mechanic with perk synergies.
func _execute_blind_attack(actor: Actor, target_x: int, target_z: int) -> void:
	var path = grid_manager.get_naive_path(actor.grid_x, actor.grid_z, target_x, target_z)
	
	if path.is_empty():
		turn_manager.end_turn()
		return
		
	var walk_path = path.slice(1, path.size() - 1)
	
	for step in walk_path:
		var obstacle = grid_manager.get_actor_at(step.x, step.y)
		if obstacle and obstacle.is_monster():
			_play_ghost_blink(obstacle)
			
		await grid_manager.move_actor(actor, step.x, step.y)
		
	# Arrived safely! Rotate and swing.
	var target_wpos = grid_manager.get_world_position(target_x, target_z)
	var look_pos = target_wpos
	look_pos.y = actor.model.global_position.y
	if actor.model.global_position.distance_squared_to(look_pos) > 0.001:
		actor.model.look_at(look_pos, Vector3.UP, true)
		
	var target = grid_manager.get_actor_at(target_x, target_z)
	
	if Global.has_method("play_old_man_attack"): Global.play_old_man_attack()
	if actor.axe_right_ap:
		actor.axe_right_ap.play("Axe10_001Action")
	if actor.axe_left_ap:
		actor.axe_left_ap.play("AtkAxe01")
			
	if target and target.is_monster():
		if hit_monsters_this_turn.has(target):
			print("Already hit this monster! Red X appears.")
			_show_wrong_target_feedback(target)
			return

		print("HIT! The Old Man struck a monster!")
		var dmg = actor.get_damage()
		if roguelite_manager.has_perk("heavy_cleaver"):
			dmg += 3
		target.take_damage(dmg)
		if Global.has_method("play_monster_wounded"): Global.play_monster_wounded()
		
		# Sweeping Cleave: Hit adjacent enemies
		if roguelite_manager.has_perk("heavy_cleaver"):
			_trigger_cleave(target_x, target_z, 4)
		
		# Reveal temporarily
		if is_instance_valid(target) and is_instance_valid(target.model):
			target.model.visible = true
			var t = target.create_tween()
			t.tween_interval(0.5)
			t.tween_callback(func(): if is_instance_valid(target) and is_instance_valid(target.model): target.model.visible = false)
		
		# Knockback with Super Impact logic
		if is_instance_valid(target) and target.current_health > 0:
			var girl = _find_actor_by_name("Little Girl")
			if girl:
				var max_kb_steps = 3 if roguelite_manager.has_perk("super_knockback") else 1
				var gx = girl.grid_x
				var gz = girl.grid_z
				var slammed = false
				
				for _s in range(max_kb_steps):
					if not is_instance_valid(target) or target.current_health <= 0: break
					var mx = target.grid_x
					var mz = target.grid_z
					var current_dist = abs(mx - gx) + abs(mz - gz)
					var candidates: Array[Vector2i] = []
					for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
						var nx = mx + dir.x
						var nz = mz + dir.y
						if grid_manager.is_cell_walkable(nx, nz):
							var new_dist = abs(nx - gx) + abs(nz - gz)
							if new_dist > current_dist:
								candidates.append(Vector2i(nx, nz))
					if candidates.size() > 0:
						var kb = candidates[randi() % candidates.size()]
						await grid_manager.move_actor(target, kb.x, kb.y)
					else:
						# Blocked! If Thunder Impact is active, deal Wall Slam damage
						if roguelite_manager.has_perk("super_knockback") and not slammed:
							slammed = true
							print("WALL SLAM! Monster collided into obstacle for 4 damage!")
							target.take_damage(4)
							if Global.has_method("play_monster_wounded"): Global.play_monster_wounded()
						break
					
		hit_monsters_this_turn.append(target)
		combo_count += 1
		combo_timer = 4.0 if roguelite_manager.has_perk("adrenaline_flow") else 2.4
		combo_active = true
		
		var unhit_monsters = 0
		for a in grid_manager.get_all_actors():
			if a and a.is_monster() and a.current_health > 0:
				if not hit_monsters_this_turn.has(a):
					unhit_monsters += 1
					
		var req_combo = 2 if roguelite_manager.has_perk("adrenaline_flow") else 3
		if unhit_monsters == 0:
			if combo_count < req_combo:
				print("Hit all monsters but lack combo ", req_combo, ". Ending turn.")
				combo_active = false
				turn_manager.end_turn()
				return
			else:
				print("Hit all monsters! Waiting for combo timeout or special attack.")
			
		grid_manager.highlight_attack_range(actor)
		return
	else:
		print("SWISH! The Old Man swung at the air.")
		# Echo Radar: Reveal nearby monsters on miss
		if roguelite_manager.has_perk("echo_pulse"):
			_trigger_echo_pulse(actor.grid_x, actor.grid_z)
		
	turn_manager.end_turn()

## Triggers an acoustic shockwave revealing invisible monsters within 3 tiles.
func _trigger_echo_pulse(center_x: int, center_z: int) -> void:
	print("ECHO RADAR: Scanning for invisible monsters...")
	if Global.has_method("play_special_attack"): Global.play_special_attack()
	
	var camera = get_viewport().get_camera_3d()
	if camera and camera.get_parent() and camera.get_parent().get_parent() is GimbalCamera:
		camera.get_parent().get_parent().shake(0.6, 0.25)
		
	for pos in grid_manager.grid:
		var actor = grid_manager.grid[pos]
		if is_instance_valid(actor) and actor.is_monster():
			var dist = abs(actor.grid_x - center_x) + abs(actor.grid_z - center_z)
			if dist <= 3:
				if is_instance_valid(actor) and is_instance_valid(actor.model):
					actor.model.visible = true
					
					var old_marker = actor.get_node_or_null("EchoMarker")
					if old_marker:
						old_marker.queue_free()
					
					var marker = Label3D.new()
					marker.name = "EchoMarker"
					marker.text = "📡 ECHO DETECTED"
					marker.pixel_size = 0.04
					marker.billboard = BaseMaterial3D.BILLBOARD_ENABLED
					marker.modulate = Color(0.25, 0.85, 1.0)
					marker.position.y = 2.4
					actor.add_child(marker)
					
					var old_tween = actor.get_meta("echo_tween", null)
					if old_tween and old_tween is Tween and old_tween.is_valid():
						old_tween.kill()
						
					var t = actor.create_tween()
					actor.set_meta("echo_tween", t)
					t.tween_interval(2.0)
					t.tween_callback(func():
						if is_instance_valid(actor) and is_instance_valid(actor.model):
							if turn_manager.current_phase != TurnManager.TurnPhase.GIRL:
								actor.model.visible = false
						var m = actor.get_node_or_null("EchoMarker")
						if is_instance_valid(m):
							m.queue_free()
					)

## Cleaves damage to all enemy units adjacent to the primary target square.
func _trigger_cleave(center_x: int, center_z: int, cleave_dmg: int) -> void:
	for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var nx = center_x + dir.x
		var nz = center_z + dir.y
		if not grid_manager.is_in_bounds(nx, nz): continue
		var neighbor = grid_manager.get_actor_at(nx, nz)
		if neighbor and neighbor.is_monster() and neighbor.current_health > 0:
			print("Cleave strike on ", neighbor.name, " for ", cleave_dmg, " damage!")
			neighbor.take_damage(cleave_dmg)
			if is_instance_valid(neighbor) and is_instance_valid(neighbor.model):
				neighbor.model.visible = true
				var t = neighbor.create_tween()
				t.tween_interval(0.4)
				t.tween_callback(func():
					if is_instance_valid(neighbor) and is_instance_valid(neighbor.model):
						if turn_manager.current_phase != TurnManager.TurnPhase.GIRL:
							neighbor.model.visible = false
				)


func _process(delta: float) -> void:
	if combo_active:
		if not is_acting:
			combo_timer -= delta
			
		var req_combo = 2 if roguelite_manager.has_perk("adrenaline_flow") else 3
		if combat_ui:
			combat_ui.update_combo(combo_count, max(0.0, combo_timer), req_combo)
		
		if combo_timer <= 0.0:
			if turn_manager.current_phase == TurnManager.TurnPhase.MAN and not is_acting:
				combo_active = false
				print("Combo time ran out!")
				turn_manager.end_turn()

func _show_wrong_target_feedback(actor: Actor) -> void:
	var label = Label3D.new()
	label.text = "X"
	label.pixel_size = 0.05
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color.RED
	label.outline_render_priority = 1
	label.font_size = 150
	
	actor.add_child(label)
	label.position.y = 2.5
	
	var tween = get_tree().create_tween()
	tween.tween_property(label, "position:y", 3.5, 0.5)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)

func _play_ghost_blink(actor: Actor) -> void:
	if not is_instance_valid(actor) or not is_instance_valid(actor.model): return
	
	var tween = actor.create_tween()
	actor.model.visible = true
	tween.tween_interval(0.15)
	tween.tween_callback(func(): actor.model.visible = false)
	tween.tween_interval(0.15)
	tween.tween_callback(func(): actor.model.visible = true)
	tween.tween_interval(0.15)
	tween.tween_callback(func(): actor.model.visible = false)

## Procedurally generates the 3D meshes for the 25x25 checkerboard floor.
func _draw_visual_grid() -> void:
	var visual_grid = Node3D.new()
	visual_grid.name = "VisualGrid"
	add_child(visual_grid)
	
	var white_mat = StandardMaterial3D.new()
	white_mat.albedo_color = Color(0.85, 0.85, 0.88) # Crisp light marble
	
	var black_mat = StandardMaterial3D.new()
	black_mat.albedo_color = Color(0.18, 0.2, 0.24) # Dark slate
	
	# ⚡ Bolt Optimization: Share these materials with the grid_manager so it can restore them without allocating new ones
	grid_manager.white_mat = white_mat
	grid_manager.black_mat = black_mat

	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(GridManager.CELL_SIZE, 0.1, GridManager.CELL_SIZE)
	
	for x in range(GridManager.GRID_SIZE_X):
		for z in range(GridManager.GRID_SIZE_Z):
			var cell = MeshInstance3D.new()
			cell.mesh = box_mesh
			# ⚡ Bolt Optimization: Removed material duplication to enable Godot renderer batching
			# By sharing exact same material instance, Godot draws all matching tiles in 1 draw call instead of O(N).
			if (x + z) % 2 == 0:
				cell.material_override = white_mat
			else:
				cell.material_override = black_mat
				
			var pos = grid_manager.get_world_position(x, z)
			pos.y = -0.05 # Sink the floor slightly so 0 is surface level
			cell.position = pos
			visual_grid.add_child(cell)
			grid_manager.register_visual_cell(x, z, cell)
			
	# Hover indicator
	hover_indicator = MeshInstance3D.new()
	var hover_mesh = BoxMesh.new()
	# Make it slightly smaller than the cell so it looks like an inner border/highlight
	hover_mesh.size = Vector3(GridManager.CELL_SIZE * 0.92, 0.02, GridManager.CELL_SIZE * 0.92)
	var hover_mat = StandardMaterial3D.new()
	hover_mat.albedo_color = Color(1.0, 1.0, 0.45, 0.45) # Transparent bright yellow
	hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover_indicator.mesh = hover_mesh
	hover_indicator.material_override = hover_mat
	hover_indicator.hide()
	visual_grid.add_child(hover_indicator)


## Sets up the permanent player actors (Old Man & Little Girl) and spawns round 1 monsters.
func _init_run_actors() -> void:
	actors_node = Node3D.new()
	actors_node.name = "Actors"
	add_child(actors_node)
	
	if not old_man_data:
		old_man_data = load("res://actors/playerActors/old_man.tres")
	if not girl_data:
		girl_data = load("res://actors/playerActors/girl.tres")
	if not monster_data:
		monster_data = load("res://actors/monsters/monster.tres")
		
	if old_man_data:
		var old_man = _create_actor("OldMan", old_man_data, Color(0.2, 0.5, 1.0))
		actors_node.add_child(old_man)
		grid_manager.place_actor(old_man, 1, 1)
	
	if girl_data:
		var girl = _create_actor("LittleGirl", girl_data, Color(1.0, 0.6, 0.8))
		actors_node.add_child(girl)
		grid_manager.place_actor(girl, 1, 2)
		
	_spawn_monsters_for_round()
	
	combat_ui.update_round_display(roguelite_manager.current_round, roguelite_manager.get_all_active_perk_data())
	combat_ui.show_round_banner(roguelite_manager.current_round)

## Spawns the monster wave scaled to the active round.
func _spawn_monsters_for_round() -> void:
	if not monster_data:
		monster_data = load("res://actors/monsters/monster.tres")
	if not monster_data: return
	
	current_round_monsters.clear()
	
	var monster_count = roguelite_manager.get_monster_count_for_round(roguelite_manager.current_round, Global.current_difficulty)
	var hp_bonus = roguelite_manager.get_monster_hp_bonus(roguelite_manager.current_round)
	
	var colors = [
		Color(0.9, 0.2, 0.2), 
		Color(0.7, 0.1, 0.3), 
		Color(1.0, 0.45, 0.1), 
		Color(0.85, 0.7, 0.1), 
		Color(0.65, 0.2, 0.85), 
		Color(0.2, 0.4, 0.8)
	]
	
	var girl = _find_actor_by_name("Little Girl")
	var girl_x = girl.grid_x if girl else 1
	var girl_z = girl.grid_z if girl else 2
	
	for i in range(monster_count):
		var flavor_name = roguelite_manager.get_monster_flavor_name(i + 1, roguelite_manager.current_round)
		var color = colors[i % colors.size()]
		var m = _create_actor(flavor_name, monster_data, color)
		m.max_health_bonus = hp_bonus
		m.current_health = m.get_max_health()
		actors_node.add_child(m)
		
		# Find unoccupied position at least 6 tiles from girl
		var pos = _get_random_spawn(girl_x, girl_z, 6)
		var placed = grid_manager.place_actor(m, pos.x, pos.y)
		if not placed:
			# Fallback scan for any walkable empty tile
			for fx in range(GridManager.GRID_SIZE_X):
				if placed: break
				for fz in range(GridManager.GRID_SIZE_Z):
					if grid_manager.is_cell_walkable(fx, fz):
						if grid_manager.place_actor(m, fx, fz):
							placed = true
							break
		current_round_monsters.append(m)

	# Register newly spawned round monsters with the UI Health Status panel
	if combat_ui:
		combat_ui.register_round_monsters(current_round_monsters)

## Calculates a random, unoccupied grid coordinate at least min_dist away from the girl.
func _get_random_spawn(girl_x: int, girl_z: int, min_dist: int) -> Vector2i:
	var valid_positions: Array[Vector2i] = []
	for x in range(GridManager.GRID_SIZE_X):
		for z in range(GridManager.GRID_SIZE_Z):
			if grid_manager.get_actor_at(x, z) != null:
				continue
			var dist = abs(x - girl_x) + abs(z - girl_z)
			if dist >= min_dist:
				valid_positions.append(Vector2i(x, z))
				
	if valid_positions.is_empty():
		return Vector2i(GridManager.GRID_SIZE_X - 1, GridManager.GRID_SIZE_Z - 1)
		
	return valid_positions.pick_random()

## Helper to construct an Actor node dynamically with visuals and weapons.
func _create_actor(actor_name: String, actor_data: ActorData, color: Color) -> Actor:
	var actor = Actor.new()
	actor.name = actor_name
	actor.data = actor_data
	actor.died.connect(_on_actor_died)
	
	if actor_data == monster_data or "Monster" in actor_name:
		actor.add_to_group("monsters")
	
	var model = MeshInstance3D.new()
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.8
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	model.mesh = mesh
	model.material_override = mat
	model.position.y = mesh.height / 2.0
	
	actor.add_child(model)
	actor.model = model 
	
	if actor_name == "OldMan" or actor_name == "Old Man":
		var axe_scene = load("res://scenes/low_poly_combat_axes.tscn")
		if not axe_scene:
			axe_scene = load("res://resources/weapons/Low poly combat axes.glb")
			
		if axe_scene:
			var pivot = Node3D.new()
			pivot.name = "Pivot"
			model.add_child(pivot)
			
			var axe_right = axe_scene.instantiate()
			axe_right.name = "AxeWeaponRight"
			axe_right.scale = Vector3(1.5, 1.5, 1.5)
			axe_right.position = Vector3.ZERO
			axe_right.rotation.y = PI 
			_hide_unwanted_meshes(axe_right, "Axe10_001")
			pivot.add_child(axe_right)
			
			var axe_left = axe_scene.instantiate()
			axe_left.name = "AxeWeaponLeft"
			axe_left.scale = Vector3(1.5, 1.5, 1.5)
			axe_left.position = Vector3.ZERO
			axe_left.rotation.y = PI 
			_hide_unwanted_meshes(axe_left, "Axe10_002")
			pivot.add_child(axe_left)
			
			var apR = axe_right.get_node_or_null("AnimationPlayer")
			if apR:
				apR.play("Axe10_001Action")
				actor.axe_right_ap = apR
			var apL = axe_left.get_node_or_null("AnimationPlayer")
			if apL:
				apL.play("AtkAxe01")
				actor.axe_left_ap = apL
			
	return actor

func _hide_unwanted_meshes(node: Node, target_mesh: String) -> void:
	for child in node.get_children():
		if child is Node3D or child is VisualInstance3D:
			if target_mesh in child.name or "Animation" in child.name:
				child.visible = true
			else:
				child.visible = false
		_hide_unwanted_meshes(child, target_mesh)

## Callback triggered when an actor's health reaches 0.
func _on_actor_died(actor: Actor) -> void:
	grid_manager.remove_actor(actor)
	
	if actor.get_actor_name() == "Little Girl" or actor.get_actor_name() == "Old Man":
		print("Defeat! The run has ended.")
		_on_run_defeat(actor.get_actor_name() == "Little Girl")
		return
		
	if actor.is_monster():
		roguelite_manager.monsters_slain_run += 1
	
	var monsters_alive = 0
	for pos in grid_manager.grid:
		var a = grid_manager.grid[pos]
		if is_instance_valid(a) and a.is_monster() and a.current_health > 0:
			monsters_alive += 1
	for pos in grid_manager.stacked_actors:
		var a = grid_manager.stacked_actors[pos]
		if is_instance_valid(a) and a.is_monster() and a.current_health > 0:
			monsters_alive += 1
			
	if monsters_alive == 0:
		print("All monsters defeated! Round ", roguelite_manager.current_round, " Cleared!")
		_on_round_completed()
		return
		
	# Re-highlight grid for active actor
	if active_actor and active_actor != actor and active_actor.get_actor_name() == "Old Man":
		grid_manager.highlight_attack_range(active_actor)

## Triggered when all monsters in the current round are defeated.
func _on_round_completed() -> void:
	is_acting = true
	turn_manager.process_mode = Node.PROCESS_MODE_DISABLED
	
	if Global.has_method("play_win_sound"): Global.play_win_sound()
	
	if roguelite_manager.current_round > roguelite_manager.highest_round:
		roguelite_manager.highest_round = roguelite_manager.current_round
		
	var choices = roguelite_manager.get_random_perk_choices(3)
	combat_ui.show_power_up_selection(roguelite_manager.current_round, choices, _on_power_up_selected)

## Applied when the player picks one of the three Hades-style power-up cards.
func _on_power_up_selected(perk_id: String) -> void:
	roguelite_manager.add_perk(perk_id)
	
	# Apply stat adjustments for acquired perks
	var old_man = _find_actor_by_name("Old Man")
	var girl = _find_actor_by_name("Little Girl")
	
	if perk_id == "swift_stride" and old_man:
		old_man.movement_range_bonus += 2
		
	if perk_id == "aegis_barrier" and girl:
		girl.max_health_bonus += 10
		girl.current_health = girl.get_max_health()
		
	if perk_id == "retribution_spikes" and girl:
		girl.set_meta("has_retribution_spikes", true)
		
	_start_next_round()

## Progresses to the next round with fresh enemies and repositioned characters.
func _start_next_round() -> void:
	roguelite_manager.advance_round()
		
	grid_manager.clear_highlights()
	
	# 1. Clean up all monster state from GridManager
	grid_manager.clear_all_monsters()
	
	# 2. Immediately detach and free leftover monster nodes from actors_node
	if actors_node:
		var monsters_to_free: Array[Node] = []
		for child in actors_node.get_children():
			if child is Actor and child.is_monster():
				monsters_to_free.append(child)
		for child in monsters_to_free:
			actors_node.remove_child(child)
			child.queue_free()
				
	# 3. Reset player positions
	var old_man = _find_actor_by_name("Old Man")
	var girl = _find_actor_by_name("Little Girl")
	
	if old_man:
		grid_manager.remove_actor(old_man)
		grid_manager.place_actor(old_man, 1, 1)
	if girl:
		grid_manager.remove_actor(girl)
		grid_manager.place_actor(girl, 1, 2)
		# Recover some HP between rounds
		girl.current_health = min(girl.current_health + 10, girl.get_max_health())
		# Re-apply Aegis divine shield
		if roguelite_manager.has_perk("aegis_barrier"):
			girl.has_shield = true
		if roguelite_manager.has_perk("retribution_spikes"):
			girl.set_meta("has_retribution_spikes", true)

	# 4. Spawn new wave of monsters
	_spawn_monsters_for_round()
	
	# 5. Update UI
	combat_ui.update_round_display(roguelite_manager.current_round, roguelite_manager.get_all_active_perk_data())
	combat_ui.show_round_banner(roguelite_manager.current_round)
	
	# 6. Girl goes first! Monsters will be visible on her turn so player sees their positions
	is_acting = false
	turn_manager.process_mode = Node.PROCESS_MODE_INHERIT
	turn_manager.current_phase = TurnManager.TurnPhase.GIRL
	turn_manager.call_deferred("_start_current_phase")

## Triggered when the Little Girl or Old Man dies.
func _on_run_defeat(_is_girl: bool) -> void:
	is_acting = true
	turn_manager.process_mode = Node.PROCESS_MODE_DISABLED
	
	if Global.has_method("play_lose_sound"): Global.play_lose_sound()
	
	combat_ui.show_game_over(
		roguelite_manager.current_round,
		roguelite_manager.monsters_slain_run,
		roguelite_manager.get_all_active_perk_data(),
		_restart_run_from_beginning,
		_exit_to_main_menu
	)

## Resets run progression and restarts from Round 1.
func _restart_run_from_beginning() -> void:
	roguelite_manager.reset_run()
	grid_manager.clear_highlights()
	
	# 1. Clean up all monster state from GridManager
	grid_manager.clear_all_monsters()
	
	# 2. Immediately detach and free leftover monster nodes from actors_node
	if actors_node:
		var monsters_to_free: Array[Node] = []
		for child in actors_node.get_children():
			if child is Actor and child.is_monster():
				monsters_to_free.append(child)
		for child in monsters_to_free:
			actors_node.remove_child(child)
			child.queue_free()
	
	# 3. Reset player positions and modifiers
	var old_man = _find_actor_by_name("Old Man")
	var girl = _find_actor_by_name("Little Girl")
	
	if old_man:
		old_man.movement_range_bonus = 0
		old_man.damage_bonus = 0
		old_man.current_health = old_man.get_max_health()
		grid_manager.remove_actor(old_man)
		grid_manager.place_actor(old_man, 1, 1)
		
	if girl:
		girl.max_health_bonus = 0
		girl.has_shield = false
		if girl.has_meta("has_retribution_spikes"):
			girl.remove_meta("has_retribution_spikes")
		girl.current_health = girl.get_max_health()
		grid_manager.remove_actor(girl)
		grid_manager.place_actor(girl, 1, 2)
				
	# 4. Spawn wave for round 1
	_spawn_monsters_for_round()
	
	combat_ui.update_round_display(roguelite_manager.current_round, roguelite_manager.get_all_active_perk_data())
	combat_ui.show_round_banner(roguelite_manager.current_round)
	
	# 5. Girl goes first!
	is_acting = false
	turn_manager.process_mode = Node.PROCESS_MODE_INHERIT
	turn_manager.current_phase = TurnManager.TurnPhase.GIRL
	turn_manager.call_deferred("_start_current_phase")

## Transitions back to the main menu.
func _exit_to_main_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

