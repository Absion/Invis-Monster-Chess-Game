extends Node
class_name GirlAIController

var grid_manager: GridManager
var turn_manager: TurnManager

## Injects necessary services and connects to the TurnManager.
func setup(grid: GridManager, turn: TurnManager) -> void:
	grid_manager = grid
	turn_manager = turn
	turn_manager.turn_started.connect(_on_turn_started)

## Handles turn progression specifically for the Girl.
func _on_turn_started(phase: TurnManager.TurnPhase) -> void:
	# Check if it is currently the girl's turn to act
	if phase == TurnManager.TurnPhase.GIRL:
		# Use call_deferred to avoid blocking the signal emission
		call_deferred("_process_girl_turn")

## Core logic for the girl's turn: calculates best escape route.
func _process_girl_turn() -> void:
	# Ensure the node is safely in the tree before executing deferred logic
	if not is_inside_tree(): return
	
	var start_time = Time.get_ticks_msec()
	
	var girl: Actor = null
	var monsters: Array[Actor] = []
	
	# ⚡ Bolt Optimization: Use native .values() to avoid GDScript VM overhead and slow hash lookups
	for actor in grid_manager.grid.values():
		if actor.get_actor_name() == "Little Girl":
			girl = actor
		elif "Monster" in actor.name:
			monsters.append(actor)
			
	for actor in grid_manager.stacked_actors.values():
		if actor.get_actor_name() == "Little Girl":
			girl = actor
		elif "Monster" in actor.name:
			monsters.append(actor)
			
	# End the turn immediately if the girl is missing or dead
	if girl == null or girl.current_health <= 0:
		turn_manager.end_turn()
		return
		
	# If there are no monsters, she doesn't need to flee, but we still wait
	if monsters.is_empty():
		var elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
		if 1.0 - elapsed > 0:
			await get_tree().create_timer(1.0 - elapsed).timeout
		turn_manager.end_turn()
		return
		
	var best_move: Vector2i = Vector2i(girl.grid_x, girl.grid_z)
	var max_distance_score = -1.0
	
	var range_limit = girl.get_movement_range()
	var start = Vector2i(girl.grid_x, girl.grid_z)
	
	# ⚡ Bolt Optimization: Extract start cell clearing outside the nested loops
	# Avoid redundant AStar state mutations (O(R^2)) for the same start position
	var start_was_solid = grid_manager.astar.is_point_solid(start)
	if start_was_solid:
		grid_manager.astar.set_point_solid(start, false)

	for x in range(start.x - range_limit, start.x + range_limit + 1):
		for z in range(start.y - range_limit, start.y + range_limit + 1):
			# ⚡ Bolt Optimization: Early O(1) prune based on Manhattan distance to avoid expensive A* calculations
			if abs(x - start.x) + abs(z - start.y) > range_limit: continue

			# Exclude out-of-bounds tiles immediately
			if not grid_manager.is_in_bounds(x, z): continue
			
			var end = Vector2i(x, z)
			
			# Ensure the cell is actually walkable (unless it's our starting cell)
			if not grid_manager.is_cell_walkable(x, z) and end != start:
				continue
				
			# ⚡ Bolt Optimization: Use get_id_path directly instead of get_grid_path
			# We already know 'end' is not solid because of is_cell_walkable, and 'start' is cleared
			var path = grid_manager.astar.get_id_path(start, end)
			
			# Only consider this tile if it's reachable within our movement limit
			if not path.is_empty() and path.size() - 1 <= range_limit:
				# Calculate minimum distance to any monster from this tile
				var min_dist_to_monster = 9999.0
				for monster in monsters:
					var dist = abs(x - monster.grid_x) + abs(z - monster.grid_z)
					if dist < min_dist_to_monster:
						min_dist_to_monster = dist
						
				if min_dist_to_monster > max_distance_score:
					max_distance_score = min_dist_to_monster
					best_move = end
					
	# Restore start solid state
	if start_was_solid:
		grid_manager.astar.set_point_solid(start, true)

	# Execute the movement to the safest tile found
	if best_move != start:
		await grid_manager.move_actor(girl, best_move.x, best_move.y)
		
	# Guarantee the turn lasts at least 1 second
	var total_elapsed = (Time.get_ticks_msec() - start_time) / 1000.0
	var time_to_wait = 1.0 - total_elapsed
	if time_to_wait > 0:
		await get_tree().create_timer(time_to_wait).timeout
		
	turn_manager.end_turn()
