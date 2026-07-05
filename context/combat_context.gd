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
	grid_manager.clear_highlights()
	
	# 1. Determine the active player actor
	if phase == TurnManager.TurnPhase.MAN:
		active_actor = _find_actor_by_name("Old Man")
		
	# 2. Toggle Monster Visibility (Invis Monster Mechanic)
	# Monsters are ONLY visible during the Girl's turn.
	# ⚡ Bolt Optimization: Iterate directly on the dictionary to avoid allocating an Array from .values()
	for key in grid_manager.grid:
		var actor = grid_manager.grid[key]
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
	# ⚡ Bolt Optimization: Iterate directly on the dictionary to avoid allocating an Array from .values()
	for key in grid_manager.grid:
		var actor = grid_manager.grid[key]
		if actor.get_actor_name() == actor_name:
			return actor
	return null

## Godot's built-in input interceptor. We use this to detect mouse clicks on the 3D grid.
func _unhandled_input(event: InputEvent) -> void:
	# Only care about left-click presses
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		
		# Block input if it's the AI's turn or a tween is currently playing
		if turn_manager.current_phase == TurnManager.TurnPhase.MONSTERS or is_acting:
			return 
			
		if active_actor == null:
			return
			
		# ---- MATHEMATICAL RAYCASTING ----
		# Instead of using Physics bodies, we use pure math to intersect the mouse
		# with the Y=0 floor plane. This is perfectly accurate for a flat grid game.
		
		var camera = get_viewport().get_camera_3d()
		if not camera: return
		
		var mouse_pos = event.position
		var ray_origin = camera.project_ray_origin(mouse_pos)
		var ray_normal = camera.project_ray_normal(mouse_pos)
		
		if ray_normal.y == 0: return # Parallel to ground, no intersection possible
		
		# Solve for t in: ray_origin.y + ray_normal.y * t = 0 (Ground Plane)
		var t = -ray_origin.y / ray_normal.y
		if t < 0: return # The click is behind the camera
		
		# Calculate the exact 3D world coordinate of the click
		var intersection = ray_origin + ray_normal * t
		
		# Convert world physical coordinates back into logical Grid (x, z) indexes
		var grid_x = floor(intersection.x / GridManager.CELL_SIZE)
		var grid_z = floor(intersection.z / GridManager.CELL_SIZE)
		
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
			print("STUNNED! The Old Man bumped into an invisible monster at ", step.x, ", ", step.y)
			_show_stun_feedback(actor)
			turn_manager.end_turn()
			return
			
		# Safe to move
		await grid_manager.move_actor(actor, step.x, step.y)
		
	# Arrived safely! Execute the attack on the target tile.
	var target = grid_manager.get_actor_at(target_x, target_z)
	if target and "Monster" in target.name:
		print("HIT! The Old Man struck a monster!")
		target.take_damage(actor.data.damage)
	else:
		print("SWISH! The Old Man swung at the air.")
		
	turn_manager.end_turn()

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
		var monster1 = _create_actor("Monster1", monster_data, Color.RED)
		actors_node.add_child(monster1)
		var pos1 = _get_random_spawn(1, 2, 6)
		grid_manager.place_actor(monster1, pos1.x, pos1.y)
		
		var monster2 = _create_actor("Monster2", monster_data, Color.DARK_RED)
		actors_node.add_child(monster2)
		var pos2 = _get_random_spawn(pos1.x, pos1.y, 5) # Second monster spawns away from the first monster
		# Ensure it's also far from the girl
		var fallback_attempts = 0
		while abs(pos2.x - 1) + abs(pos2.y - 2) < 6 and fallback_attempts < 10:
			pos2 = _get_random_spawn(pos1.x, pos1.y, 5)
			fallback_attempts += 1
		grid_manager.place_actor(monster2, pos2.x, pos2.y)

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
	# ⚡ Bolt Optimization: Iterate directly on the dictionary to avoid allocating an Array from .values()
	for key in grid_manager.grid:
		var a = grid_manager.grid[key]
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
