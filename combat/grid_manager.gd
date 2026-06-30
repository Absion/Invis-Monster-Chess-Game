extends Node
class_name GridManager

## Manages the grid for the combat context.
## 
## Handles mapping between grid coordinates (x, z) and world coordinates,
## tracks actors on the grid, and calculates movement using [AStarGrid2D].

## The total number of columns on the grid (X-axis).
const GRID_SIZE_X: int = 10
const GRID_SIZE_Z: int = 10
## The physical size in Godot world units of a single grid cell.
const CELL_SIZE: float = 2.0

## Dictionary mapping logical coordinates `Vector2i(x, z)` to the `Actor` instance at that location.
var grid: Dictionary = {}

## The A* Pathfinding object that calculates the shortest path while avoiding obstacles.
var astar: AStarGrid2D

## Stores the MeshInstance3Ds for the visual grid so we can alter their colors to highlight ranges.
var visual_cells: Dictionary = {}

## Initializes the pathfinding system. Should be called after the node enters the tree.
func setup() -> void:
	print("GridManager initialized. Size: %dx%d" % [GRID_SIZE_X, GRID_SIZE_Z])
	_setup_astar()

## Configures the internal Godot [AStarGrid2D] object to match our game's grid size and rules.
func _setup_astar() -> void:
	astar = AStarGrid2D.new()
	# Set the bounds of the pathfinding grid
	astar.region = Rect2i(0, 0, GRID_SIZE_X, GRID_SIZE_Z)
	astar.cell_size = Vector2(CELL_SIZE, CELL_SIZE)
	# Manhattan distance matches standard grid movement without diagonals (like a chess rook)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER
	astar.update()

## Called after moving actors or changing grid state to refresh pathfinding obstacles.
## Clears all solid points and then iterates through the [member grid] dictionary to mark occupied cells.
func update_obstacles() -> void:
	astar.fill_solid_region(astar.region, false) # Clear all obstacles
	for pos in grid.keys():
		astar.set_point_solid(pos, true) # Mark cells with actors as solid

## Checks if the logical coordinates are within the defined grid size.
func is_in_bounds(x: int, z: int) -> bool:
	return x >= 0 and x < GRID_SIZE_X and z >= 0 and z < GRID_SIZE_Z

## Checks if a cell is within bounds and has no actor currently standing on it.
func is_cell_walkable(x: int, z: int) -> bool:
	if not is_in_bounds(x, z):
		return false
	return not grid.has(Vector2i(x, z))

## Retrieves the actor currently standing at the given logical coordinates.
## Returns `null` if the cell is empty.
func get_actor_at(x: int, z: int) -> Actor:
	var pos = Vector2i(x, z)
	if grid.has(pos):
		return grid[pos]
	return null

## Places an actor precisely at the logical coordinates.
## If [param instant] is true (default), the actor snaps to the new world position immediately.
## If false, the caller is responsible for animating the actor (or awaiting the move_actor method).
func place_actor(actor: Actor, x: int, z: int, instant: bool = true) -> bool:
	if not is_in_bounds(x, z):
		push_warning("Attempted to place actor out of bounds: ", x, ", ", z)
		return false
		
	var pos = Vector2i(x, z)
	if grid.has(pos):
		push_warning("Cell already occupied at: ", x, ", ", z)
		return false
		
	# Store the actor in our dictionary
	grid[pos] = actor
	actor.setup(x, z)
	
	if instant:
		actor.global_position = get_world_position(x, z)
		
	# ⚡ Bolt Optimization: Use O(1) incremental AStar update instead of O(N) full grid rebuild
	astar.set_point_solid(pos, true)
	return true

## Removes an actor from the grid. Used primarily when an actor dies.
func remove_actor(actor: Actor) -> void:
	var pos = Vector2i(actor.grid_x, actor.grid_z)
	if grid.has(pos) and grid[pos] == actor:
		grid.erase(pos)
		# ⚡ Bolt Optimization: Use O(1) incremental AStar update instead of O(N) full grid rebuild
		astar.set_point_solid(pos, false)

## Attempts to move an actor from its current cell to a new cell.
## This is an asynchronous coroutine. You should `await` it so the game logic pauses while the actor slides.
func move_actor(actor: Actor, to_x: int, to_z: int) -> bool:
	if not is_cell_walkable(to_x, to_z):
		return false
		
	# Check distance using AStar to ensure we aren't moving through walls/other actors
	var path = get_grid_path(actor.grid_x, actor.grid_z, to_x, to_z)
	if path.is_empty():
		return false
		
	# Path length - 1 because the returned path includes the starting cell
	if path.size() - 1 > actor.get_movement_range():
		return false
		
	# 1. Remove from old logical position
	var old_pos = Vector2i(actor.grid_x, actor.grid_z)
	grid.erase(old_pos)
	# ⚡ Bolt Optimization: Clear the old obstacle immediately so place_actor works cleanly
	astar.set_point_solid(old_pos, false)
	
	# 2. Place in new logical position without snapping the visual model
	var placement_successful = place_actor(actor, to_x, to_z, false)
	
	if placement_successful:
		# 3. Create the smooth sliding animation and pause execution until it finishes
		var target_world_pos = get_world_position(to_x, to_z)
		await actor.move_to(target_world_pos).finished
		return true
		
	return false

## Returns an array of Vector2i coordinates representing the shortest path from start to end.
## Temporarily unmarks the destination if it was solid so that AI can calculate a path 
## right up to an enemy's face to attack them.
func get_grid_path(start_x: int, start_z: int, end_x: int, end_z: int) -> Array[Vector2i]:
	var start = Vector2i(start_x, start_z)
	var end = Vector2i(end_x, end_z)
	
	var start_was_solid = astar.is_point_solid(start)
	var end_was_solid = astar.is_point_solid(end)
	
	if start_was_solid:
		astar.set_point_solid(start, false)
	if end_was_solid:
		astar.set_point_solid(end, false)
		
	var path = astar.get_id_path(start, end)
	
	if start_was_solid:
		astar.set_point_solid(start, true)
	if end_was_solid:
		astar.set_point_solid(end, true)
		
	return path

## Returns a naive path that ignores invisible monsters.
func get_naive_path(start_x: int, start_z: int, end_x: int, end_z: int) -> Array[Vector2i]:
	var start = Vector2i(start_x, start_z)
	var end = Vector2i(end_x, end_z)
	
	# Temporarily clear all monster obstacles
	var monster_positions: Array[Vector2i] = []
	for pos in grid.keys():
		var actor = grid[pos]
		if actor and "Monster" in actor.name:
			if astar.is_point_solid(pos):
				astar.set_point_solid(pos, false)
				monster_positions.append(pos)
				
	var start_was_solid = astar.is_point_solid(start)
	var end_was_solid = astar.is_point_solid(end)
	
	if start_was_solid:
		astar.set_point_solid(start, false)
	if end_was_solid:
		astar.set_point_solid(end, false)
		
	var path = astar.get_id_path(start, end)
	
	if start_was_solid:
		astar.set_point_solid(start, true)
	if end_was_solid:
		astar.set_point_solid(end, true)
		
	# Restore monster obstacles
	for pos in monster_positions:
		astar.set_point_solid(pos, true)
		
	return path

## Converts logical grid coordinates (x, z) into world-space physical coordinates.
func get_world_position(x: int, z: int) -> Vector3:
	# Multiply by CELL_SIZE to spread them out
	# Add CELL_SIZE / 2.0 so the coordinate represents the CENTER of the cell
	var world_x = (x * CELL_SIZE) + (CELL_SIZE / 2.0)
	var world_z = (z * CELL_SIZE) + (CELL_SIZE / 2.0)
	return Vector3(world_x, 0.0, world_z)

## Links a logical grid coordinate to the physical 3D box mesh representing the floor tile.
func register_visual_cell(x: int, z: int, mesh: MeshInstance3D) -> void:
	visual_cells[Vector2i(x, z)] = mesh

## Colors the floor tiles to indicate where the provided actor can attack.
func highlight_attack_range(actor: Actor) -> void:
	clear_highlights()
	if actor == null:
		return
		
	# Attack range is movement range + 1
	var range_limit = actor.get_movement_range() + 1
	var start = Vector2i(actor.grid_x, actor.grid_z)
	
	# Temporarily clear all monster obstacles for batched pathfinding
	# ⚡ Bolt Optimization: Extract monster obstacle clearing outside the loop
	# Temporarily clear all monster obstacles once, instead of doing it inside get_naive_path for every cell
	var monster_positions: Array[Vector2i] = []
	for pos in grid.keys():
		var grid_actor = grid[pos]
		if grid_actor and "Monster" in grid_actor.name:
			if astar.is_point_solid(pos):
				astar.set_point_solid(pos, false)
				monster_positions.append(pos)

	var start_was_solid = astar.is_point_solid(start)
	if start_was_solid:
		astar.set_point_solid(start, false)

	# Loop through a square area around the actor
	for x in range(start.x - range_limit, start.x + range_limit + 1):
		for z in range(start.y - range_limit, start.y + range_limit + 1):
			var end = Vector2i(x, z)
			if not is_in_bounds(x, z): continue
			
			if end == start: continue # Don't highlight own square
			
			var target_actor = get_actor_at(x, z)
			if target_actor and target_actor.get_actor_name() == "Little Girl":
				continue # Don't highlight friendly squares
				
			var end_was_solid = astar.is_point_solid(end)
			if end_was_solid:
				astar.set_point_solid(end, false)

			# ⚡ Bolt Optimization: Removed duplicate pathfinding call get_grid_path
			var path = astar.get_id_path(start, end)

			if end_was_solid:
				astar.set_point_solid(end, true)
			
			# If a valid path exists and it's within the actor's range
			if not path.is_empty() and path.size() - 1 <= range_limit:
				_set_cell_highlight(x, z, Color(0.8, 0.2, 0.2, 1.0)) # Red for attack

	# Restore start and monster obstacles
	if start_was_solid:
		astar.set_point_solid(start, true)
	# Restore monster obstacles
	for pos in monster_positions:
		astar.set_point_solid(pos, true)

## Resets all floor tiles back to their default checkerboard pattern.
func clear_highlights() -> void:
	for pos in visual_cells.keys():
		var mesh = visual_cells[pos] as MeshInstance3D
		var mat = mesh.material_override as StandardMaterial3D
		if (pos.x + pos.y) % 2 == 0:
			mat.albedo_color = Color(0.8, 0.8, 0.8) # Light grey
		else:
			mat.albedo_color = Color(0.2, 0.2, 0.2) # Dark grey

## Internal helper to change the material color of a specific tile.
func _set_cell_highlight(x: int, z: int, color: Color) -> void:
	var pos = Vector2i(x, z)
	if visual_cells.has(pos):
		var mesh = visual_cells[pos] as MeshInstance3D
		var mat = mesh.material_override as StandardMaterial3D
		mat.albedo_color = color
