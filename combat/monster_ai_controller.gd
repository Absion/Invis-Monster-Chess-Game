extends Node
class_name MonsterAIController

## AI Controller that manages monster turns.
##
## Listens for the TurnManager's phase changes.
## On the MONSTERS phase, it iterates over all alive monsters, making them
## pathfind towards the girl and attack her if they reach her.

var grid_manager: GridManager
var turn_manager: TurnManager

## Injects the necessary services and hooks into the TurnManager signal.
func setup(grid: GridManager, turn: TurnManager) -> void:
	grid_manager = grid
	turn_manager = turn
	turn_manager.turn_started.connect(_on_turn_started)

## Callback for when the TurnManager changes phases.
## Callback for when the TurnManager changes phases.
func _on_turn_started(phase: TurnManager.TurnPhase) -> void:
	# Trigger the monster logic only when it's their phase
	if phase == TurnManager.TurnPhase.MONSTERS:
		_process_monsters()

## Orchestrates the monster turn. Asynchronously processes each monster one by one,
## then ends the turn.
func _process_monsters() -> void:
	# 1. Identify all active monsters and their target (the Little Girl)
	var monsters: Array[Actor] = []
	var girl: Actor = null
	
	# ⚡ Bolt Optimization: Iterate directly on the dictionary to avoid allocating an Array from .values()
	for pos in grid_manager.grid:
		var actor = grid_manager.grid[pos]
		# Categorize actors into monsters array or identify the target girl
		if "Monster" in actor.name:
			monsters.append(actor)
		elif actor.get_actor_name() == "Little Girl":
			girl = actor
			
	# Skip turn entirely if the girl is not on the board or already defeated
	if girl == null or girl.current_health <= 0:
		print("Monster AI: Girl not found on the grid or is dead.")
		turn_manager.end_turn()
		return
		
	# 2. Process each monster sequentially (awaiting their movement tweens)
	# 2. Process each monster sequentially (awaiting their movement tweens)
	for monster in monsters:
		# Double-check validity as an earlier monster's action might have triggered events
		if is_instance_valid(monster) and monster.current_health > 0:
			if is_instance_valid(girl) and not girl.is_queued_for_deletion():
				await _process_single_monster(monster, girl)
			else:
				# The girl was killed by a previous monster this turn, stop processing
				break
		
	# 3. End the turn once all monsters have acted
	turn_manager.end_turn()

## Executes the logic for a single monster.
## Calculates the A* path to the target, moves the monster along the path up to its max range,
## and then checks if it can execute an attack.
func _process_single_monster(monster: Actor, target: Actor) -> void:
	var path = grid_manager.get_grid_path(monster.grid_x, monster.grid_z, target.grid_x, target.grid_z)
	
	# Abort movement if there is absolutely no valid path to the target
	if path.is_empty():
		return # No path found (blocked)
		
	var max_movement = monster.get_movement_range()
	
	# Find the furthest valid cell along the path up to the monster's max movement range
	# Find the furthest valid cell along the path up to the monster's max movement range
	var move_target_index = 0
	for i in range(1, path.size()):
		# Do not process steps that exceed the monster's permitted movement range
		if i > max_movement:
			break
			
		var check_pos = path[i]
		
		# Prevent moving into the exact cell occupied by the target
		if check_pos == Vector2i(target.grid_x, target.grid_z):
			break
			
		# Record the furthest walkable cell we encounter
		if grid_manager.is_cell_walkable(check_pos.x, check_pos.y):
			move_target_index = i
			
	# If a valid move exists, execute it and wait for the Tween to finish
	# If a valid move exists, execute it and wait for the Tween to finish
	if move_target_index > 0:
		var dest = path[move_target_index]
		await grid_manager.move_actor(monster, dest.x, dest.y)
		print(monster.name, " moved to ", dest)
		
	# Verify adjacency to the target before attempting a strike
	var distance = abs(monster.grid_x - target.grid_x) + abs(monster.grid_z - target.grid_z)
	if distance == 1:
		target.take_damage(monster.data.damage)
