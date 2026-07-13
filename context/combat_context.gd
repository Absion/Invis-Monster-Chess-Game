extends Context
class_name CombatContext

## The Context managing the combat game state.
##
## Manages Turn Order, grid logic, and handles player mouse interactions
## via math-based raycasting. Connects the UI to the underlying services.

@export var old_man_data: ActorData
@export var girl_data: ActorData
@export var monster_data: ActorData

var grid_manager: GridManager
var turn_manager: TurnManager
var monster_ai: MonsterAIController
var girl_ai: GirlAIController
var combat_ui: CombatUI

## The actor currently being controlled by the player this turn.
var active_actor: Actor

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

## Connects dependent services together. (Currently handled in setup)
func bind_services() -> void:
	pass

## Initializes the combat state, draws the grid, and spawns the actors.
func setup() -> void:
	grid_manager.setup()
	turn_manager.setup()
	monster_ai.setup(grid_manager, turn_manager)
	girl_ai.setup(grid_manager, turn_manager)
	combat_ui.setup(turn_manager, grid_manager)
	
	# Listen for turn changes to update player controls and UI
	turn_manager.turn_started.connect(_on_turn_started)
	
	_draw_visual_grid()
	_spawn_test_actors()

## Called automatically when the TurnManager cycles to a new phase.
## Configures the active actor, highlights the grid, and toggles monster visibility.
func _on_turn_started(phase: TurnManager.TurnPhase) -> void:
	active_actor = null
	is_acting = false
	has_moved_this_turn = false
	combo_count = 0
	combo_active = false
	hit_monsters_this_turn.clear()
	if combat_ui:
		combat_ui.update_combo(0, 0.0)
	grid_manager.clear_highlights()
	
	# 1. Determine the active player actor
	if phase == TurnManager.TurnPhase.MAN:
		active_actor = _find_actor_by_name("Old Man")
		
	# 2. Toggle Monster Visibility (Invis Monster Mechanic)
	# Monsters are ONLY visible during the Girl's turn.
	# ⚡ Bolt Optimization: Use native .values() to avoid GDScript VM overhead and slow hash lookups
	for actor in grid_manager.grid.values():
		if "Monster" in actor.name:
			var should_be_visible = (phase == TurnManager.TurnPhase.GIRL)
			# Only hide if alive
			if is_instance_valid(actor) and actor.model:
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
	# ⚡ Bolt Optimization: Use native .values() to avoid GDScript VM overhead and slow hash lookups
	for actor in grid_manager.grid.values():
		if actor.get_actor_name() == actor_name:
			return actor
	return null

## Godot's built-in input interceptor. We use this to detect mouse clicks on the 3D grid.
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
					wpos.y = 0.01
					hover_indicator.position = wpos
				elif hover_indicator:
					hover_indicator.hide()

			if grid_manager.is_in_bounds(grid_x, grid_z):
				return
			
		elif event is InputEventMouseButton:
			# Block clicks if it's the AI's turn or a tween is playing
			if turn_manager.current_phase == TurnManager.TurnPhase.MONSTERS or is_acting:
				return 
				
			if active_actor == null:
				return
				
			if event.button_index == MOUSE_BUTTON_RIGHT:
				if active_actor.get_actor_name() == "Old Man" and combo_count >= 3:
					_handle_special_attack()
				elif active_actor.get_actor_name() == "Old Man":
					print("Special attack not ready! Need Combo 3+")
				return
				
			_handle_grid_click(grid_x, grid_z)

## Processes the logical intent of the player clicking on a specific grid cell.
func _handle_grid_click(x: int, z: int) -> void:
	if not active_actor or active_actor.get_actor_name() != "Old Man": return
	
	var target_pos = Vector2i(x, z)
	if not grid_manager.visual_cells.has(target_pos): return
	
	var mesh = grid_manager.visual_cells[target_pos] as MeshInstance3D
	var mat = mesh.material_override as StandardMaterial3D
	
	# Only allow interacting with RED highlighted squares
	if mat.albedo_color != Color(0.8, 0.2, 0.2, 1.0):
		print("Click a red square to attack!")
		return
		
	is_acting = true
	await _execute_blind_attack(active_actor, x, z)
	is_acting = false
		
## Executes the AOE Special Attack for the Old Man
func _handle_special_attack() -> void:
	is_acting = true
	combo_count = 0
	combo_active = false
	if combat_ui:
		combat_ui.update_combo(0, 0.0)
	
	print("SPECIAL AOE ATTACK ACTIVATED!")
	
	var actor = active_actor
	var dirs = [
		Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)
	]
	
	var tween = actor.create_tween()
	var original_pos = actor.model.position
	var damage = actor.data.damage
	
	for dir in dirs:
		var nx = actor.grid_x + dir.x
		var nz = actor.grid_z + dir.y
		if not grid_manager.is_in_bounds(nx, nz):
			continue
			
		var target_wpos = grid_manager.get_world_position(nx, nz)
		var local_target = target_wpos - actor.global_position
		local_target.y = original_pos.y
		
		# Dash out
		tween.tween_property(actor.model, "position", local_target, 0.04)
		
		# Apply damage at peak
		tween.tween_callback(func():
			var target = grid_manager.get_actor_at(nx, nz)
			if target and "Monster" in target.name:
				print("AOE Hit on ", target.name, "!")
				if is_instance_valid(target) and is_instance_valid(target.model):
					target.model.visible = true
					var t = target.create_tween()
					t.tween_interval(0.5)
					t.tween_callback(func(): if is_instance_valid(target) and is_instance_valid(target.model): target.model.visible = false)
				target.take_damage(damage)
		)
		
		# Dash back
		tween.tween_property(actor.model, "position", original_pos, 0.04)
		
	tween.tween_callback(func():
		actor.model.position = original_pos
		is_acting = false
		print("Special Attack Finished! Combo reset to 0.")
	)

## Executes the heal ability on the Little Girl
func _handle_heal() -> void:
	if not can_heal: return
	
	var girl = _find_actor_by_name("Little Girl")
	if girl and is_instance_valid(girl) and girl.current_health > 0:
		can_heal = false
		girl.current_health = min(girl.current_health + 5, girl.data.max_health)
		print("Little Girl healed for 5 HP! Current HP: ", girl.current_health)
		
		# Flash green
		if is_instance_valid(girl.model):
			var mat = girl.model.material_override as StandardMaterial3D
			if mat:
				var orig_color = mat.albedo_color
				mat.albedo_color = Color.GREEN
				var t = get_tree().create_tween()
				t.tween_interval(0.3)
				t.tween_callback(func(): if is_instance_valid(girl.model): mat.albedo_color = orig_color)
				
		# Clear UI
		if combat_ui:
			combat_ui.clear_heal_ui()

## Executes the fast-paced blind attack mechanic.
func _execute_blind_attack(actor: Actor, target_x: int, target_z: int) -> void:
	# Calculate a naive path that ignores invisible monsters
	var path = grid_manager.get_naive_path(actor.grid_x, actor.grid_z, target_x, target_z)
	
	if path.is_empty():
		turn_manager.end_turn()
		return
		
	# The path includes the starting tile (index 0) and the target tile (index size-1).
	# We only want to WALK up to the tile adjacent to the target (index size-2).
	var walk_path = path.slice(1, path.size() - 1)
	
	for step in walk_path:
		var obstacle = grid_manager.get_actor_at(step.x, step.y)
		if obstacle and "Monster" in obstacle.name:
			_play_ghost_blink(obstacle)
			
		# Safe to move
		await grid_manager.move_actor(actor, step.x, step.y)
		
	# Arrived safely! Execute the attack on the target tile.
	var target = grid_manager.get_actor_at(target_x, target_z)
	if target and "Monster" in target.name:
		if hit_monsters_this_turn.has(target):
			print("Already hit this monster! Red X appears.")
			_show_wrong_target_feedback(target)
			# Let the combo timer continue, do not end turn
			return

		print("HIT! The Old Man struck a monster!")
		target.take_damage(actor.data.damage)
		
		# Reveal the monster temporarily so the player can see it get knocked back
		if is_instance_valid(target) and is_instance_valid(target.model):
			target.model.visible = true
			var t = target.create_tween()
			t.tween_interval(0.5)
			t.tween_callback(func(): target.model.visible = false)
		
		# Knockback logic (if it survived)
		if is_instance_valid(target) and target.current_health > 0:
			var girl = _find_actor_by_name("Little Girl")
			if girl:
				var mx = target.grid_x
				var mz = target.grid_z
				var gx = girl.grid_x
				var gz = girl.grid_z
				var current_dist = abs(mx - gx) + abs(mz - gz)
				var candidates = []
				for dir in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
					var nx = mx + dir.x
					var nz = mz + dir.y
					if grid_manager.is_cell_walkable(nx, nz):
						var new_dist = abs(nx - gx) + abs(nz - gz)
						if new_dist > current_dist:
							candidates.append(Vector2i(nx, nz))
				if candidates.size() > 0:
					var kb = candidates[randi() % candidates.size()]
					grid_manager.move_actor(target, kb.x, kb.y)
					
		hit_monsters_this_turn.append(target)
		combo_count += 1
		combo_timer = 2.4
		combo_active = true
		
		var unhit_monsters = 0
		for a in grid_manager.get_all_actors():
			if a and "Monster" in a.name and a.current_health > 0:
				if not hit_monsters_this_turn.has(a):
					unhit_monsters += 1
					
		if unhit_monsters == 0:
			print("Hit all monsters! Ending turn.")
			combo_active = false
			turn_manager.end_turn()
		else:
			# Refresh highlights from his new location so he can combo again
			grid_manager.highlight_attack_range(actor)
		return
	else:
		print("SWISH! The Old Man swung at the air.")
		
	turn_manager.end_turn()

func _process(delta: float) -> void:
	if combo_active:
		# Freeze the timer while animations/movements are happening
		if not is_acting:
			combo_timer -= delta
			
		if combat_ui:
			combat_ui.update_combo(combo_count, max(0.0, combo_timer))
		
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
	
	# Bind the tween to the actor so it aborts automatically if the actor dies
	var tween = actor.create_tween()
	actor.model.visible = true
	tween.tween_interval(0.15)
	tween.tween_callback(func(): actor.model.visible = false)
	tween.tween_interval(0.15)
	tween.tween_callback(func(): actor.model.visible = true)
	tween.tween_interval(0.15)
	tween.tween_callback(func(): actor.model.visible = false)

## Spawns a floating '!' above the actor and shakes the screen.
func _show_stun_feedback(actor: Actor) -> void:
	var label = Label3D.new()
	label.text = "!"
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
	
	var camera = get_viewport().get_camera_3d()
	if camera and camera.get_parent() and camera.get_parent().get_parent() is GimbalCamera:
		camera.get_parent().get_parent().shake(1.0, 0.4)

## Procedurally generates the 3D meshes for the 25x25 checkerboard floor.
func _draw_visual_grid() -> void:
	var visual_grid = Node3D.new()
	visual_grid.name = "VisualGrid"
	add_child(visual_grid)
	
	var white_mat = StandardMaterial3D.new()
	white_mat.albedo_color = Color(0.8, 0.8, 0.8)
	var black_mat = StandardMaterial3D.new()
	black_mat.albedo_color = Color(0.2, 0.2, 0.2)
	
	var box_mesh = BoxMesh.new()
	box_mesh.size = Vector3(GridManager.CELL_SIZE, 0.1, GridManager.CELL_SIZE)
	
	for x in range(GridManager.GRID_SIZE_X):
		for z in range(GridManager.GRID_SIZE_Z):
			var cell = MeshInstance3D.new()
			cell.mesh = box_mesh
			# Duplicate the material so we can tint individual cells later (highlighting)
			if (x + z) % 2 == 0:
				cell.material_override = white_mat.duplicate()
			else:
				cell.material_override = black_mat.duplicate()
				
			var pos = grid_manager.get_world_position(x, z)
			pos.y = -0.05 # Sink the floor slightly so 0 is surface level
			cell.position = pos
			visual_grid.add_child(cell)
			grid_manager.register_visual_cell(x, z, cell)
			
	# Create hover indicator
	hover_indicator = MeshInstance3D.new()
	var hover_mesh = BoxMesh.new()
	# Make it slightly smaller than the cell so it looks like an inner border/highlight
	hover_mesh.size = Vector3(GridManager.CELL_SIZE * 0.9, 0.02, GridManager.CELL_SIZE * 0.9)
	var hover_mat = StandardMaterial3D.new()
	hover_mat.albedo_color = Color(1.0, 1.0, 0.5, 0.4) # Transparent bright yellow
	hover_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hover_indicator.mesh = hover_mesh
	hover_indicator.material_override = hover_mat
	hover_indicator.hide()
	visual_grid.add_child(hover_indicator)

## Initializes the characters into the world based on the @export resources.
func _spawn_test_actors() -> void:
	var actors_node = Node3D.new()
	actors_node.name = "Actors"
	add_child(actors_node)
	
	if not old_man_data:
		old_man_data = load("res://actors/playerActors/old_man.tres")
	if not girl_data:
		girl_data = load("res://actors/playerActors/girl.tres")
	if not monster_data:
		monster_data = load("res://actors/monsters/monster.tres")
		
	if old_man_data:
		var old_man = _create_actor("OldMan", old_man_data, Color.BLUE)
		actors_node.add_child(old_man)
		grid_manager.place_actor(old_man, 1, 1)
	
	if girl_data:
		var girl = _create_actor("LittleGirl", girl_data, Color.PINK)
		actors_node.add_child(girl)
		grid_manager.place_actor(girl, 1, 2)
	
	if monster_data:
		var colors = [Color.RED, Color.DARK_RED, Color.ORANGE, Color.YELLOW, Color.PURPLE, Color.BLUE]
		var last_pos = Vector2i(1, 2)
		for i in range(6):
			var m = _create_actor("Monster" + str(i + 1), monster_data, colors[i])
			actors_node.add_child(m)
			var pos = _get_random_spawn(last_pos.x, last_pos.y, 5 if i > 0 else 6)
			var fallback = 0
			while abs(pos.x - 1) + abs(pos.y - 2) < 6 and fallback < 10:
				pos = _get_random_spawn(last_pos.x, last_pos.y, 5 if i > 0 else 6)
				fallback += 1
			grid_manager.place_actor(m, pos.x, pos.y)
			last_pos = pos

## Calculates a random, unoccupied grid coordinate that is at least `min_dist`
## Manhattan distance away from the specified `girl_x` and `girl_z` coordinates.
## Returns a default corner coordinate if no valid spots are available.
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

## Helper to construct an Actor node dynamically with a capsule mesh.
func _create_actor(actor_name: String, actor_data: ActorData, color: Color) -> Actor:
	var actor = Actor.new()
	actor.name = actor_name
	actor.data = actor_data
	
	# Connect to the died signal so GridManager cleans them up from pathfinding
	actor.died.connect(_on_actor_died)
	
	# Generate a dummy visual representation
	var model = MeshInstance3D.new()
	var mesh = CapsuleMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.8
	var mat = StandardMaterial3D.new()
	mat.albedo_color = color
	model.mesh = mesh
	model.material_override = mat
	# Offset model so it stands perfectly on the Y=0 ground plane
	model.position.y = mesh.height / 2.0
	
	actor.add_child(model)
	# Save a reference to the model so we can easily toggle its visibility later
	actor.model = model 
	return actor

## Callback triggered when an actor's health reaches 0.
func _on_actor_died(actor: Actor) -> void:
	# Free up the grid tile they were standing on
	grid_manager.remove_actor(actor)
	
	if actor.get_actor_name() == "Little Girl":
		print("The Little Girl has died! Game Over.")
		_end_game(false)
		return
		
	var monsters_alive = 0
	# ⚡ Bolt Optimization: Use native .values() to avoid GDScript VM overhead and slow hash lookups
	for a in grid_manager.grid.values():
		if a and "Monster" in a.name:
			monsters_alive += 1
			
	if monsters_alive == 0:
		print("All monsters defeated! You Win! Restarting...")
		_end_game(true)
		return
		
	# Re-highlight grid in case the active player can now walk through that tile
	if active_actor and active_actor != actor and active_actor.get_actor_name() == "Old Man":
		grid_manager.highlight_attack_range(active_actor)

## Stops all turns, blocks player input, and displays the Game Over / You Win
## UI overlay before automatically reloading the scene after a short delay.
func _end_game(is_win: bool) -> void:
	is_acting = true # Block player input
	turn_manager.process_mode = Node.PROCESS_MODE_DISABLED # Pause turns
	
	if combat_ui and combat_ui.end_turn_button:
		combat_ui.end_turn_button.disabled = true
		combat_ui.end_turn_button.release_focus()
	
	var canvas = CanvasLayer.new()
	add_child(canvas)
	
	var bg = ColorRect.new()
	bg.color = Color(0, 0, 0, 0.7)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(bg)
	
	var label = Label.new()
	label.text = "YOU WIN!" if is_win else "YOU LOSE!"
	label.set_anchors_preset(Control.PRESET_CENTER)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 120)
	label.add_theme_color_override("font_color", Color.GREEN if is_win else Color.RED)
	
	# Add a slight shadow for readability
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 4)
	label.add_theme_constant_override("shadow_offset_y", 4)
	
	canvas.add_child(label)
	
	# Ensure the timer is processed even if other things are disabled
	await get_tree().create_timer(3.0, true, false, true).timeout
	get_tree().call_deferred("reload_current_scene")
