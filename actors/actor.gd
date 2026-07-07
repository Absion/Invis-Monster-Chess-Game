extends Node3D
class_name Actor

## Base class for actors (Old Man, Girl, Monsters) in the game.
## 
## Actors rely on an [ActorData] resource for their base statistics.
## This class manages the actor's grid position, visuals, health, and smooth movement.

## Emitted when health reaches 0, signaling managers to clean up this actor.
signal died(actor: Actor)

## The resource containing the base stats (health, damage, movement range) for this actor.
@export var data: ActorData

## Current X position on the logical grid.
var grid_x: int = 0
## Current Z position on the logical grid.
var grid_z: int = 0

## The visual 3D model representing the actor.
var model: Node3D

## Current health pool of the actor.
var current_health: int = 0

## Initializes the actor's health based on its resource data.
func _ready() -> void:
	# Ensure data is provided before setting up health
	if data == null:
		push_warning("Actor initialized without ActorData resource: " + name)
	else:
		current_health = data.max_health
		
## Called by [GridManager] to initialize the actor's logical coordinates.
##
## [param start_x]: The starting X grid coordinate.
## [param start_z]: The starting Z grid coordinate.
func setup(start_x: int, start_z: int) -> void:
	grid_x = start_x
	grid_z = start_z

## Smoothly animates the actor from its current world position to a new target position.
##
## [param target_pos]: The world space Vector3 to slide towards.
## Returns a [Tween] object so the caller can `await` its completion.
func move_to(target_pos: Vector3) -> Tween:
	var tween = create_tween()
	# Smoothly interpolate global_position to target_pos over 0.3 seconds
	tween.tween_property(self, "global_position", target_pos, 0.3).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween

## Deducts health and handles death logic if health hits 0.
##
## [param amount]: The amount of damage to subtract from [member current_health].
func take_damage(amount: int) -> void:
	current_health -= amount
	print(get_actor_name(), " takes ", amount, " damage! Remaining HP: ", current_health)
	
	_play_hit_feedback()
	
	# Trigger death logic if health drops below or equals zero
	if current_health <= 0:
		die()

## Spawns a floating damage text ('O' for monsters, 'X' for girl) and shakes the screen
func _play_hit_feedback() -> void:
	var label = Label3D.new()
	label.pixel_size = 0.05
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.outline_render_priority = 1
	label.font_size = 150
	
	# Display a red 'X' for the Little Girl, or a green 'O' for monsters
	if get_actor_name() == "Little Girl":
		label.text = "X"
		label.modulate = Color.RED
	else:
		label.text = "O"
		label.modulate = Color.GREEN
		
	add_child(label)
	label.position.y = 2.5
	
	var tween = get_tree().create_tween()
	tween.tween_property(label, "position:y", 3.5, 0.5)
	tween.parallel().tween_property(label, "modulate:a", 0.0, 0.5)
	tween.tween_callback(label.queue_free)
	
	var camera = get_viewport().get_camera_3d()
	if camera and camera.get_parent() and camera.get_parent().get_parent() is GimbalCamera:
		if get_actor_name() == "Little Girl":
			camera.get_parent().get_parent().shake(1.5, 0.4)
		elif "Monster" in get_actor_name() or "Monster" in name:
			camera.get_parent().get_parent().shake(0.75, 0.4)

## Executes the death sequence, emitting the signal for managers to clean up.
func die() -> void:
	print(get_actor_name(), " has died!")
	died.emit(self)
	# Remove this node from the scene tree safely at the end of the frame
	queue_free()
	
## Helper to safely retrieve the movement range from the resource.
func get_movement_range() -> int:
	return data.movement_range if data else 0

## Helper to safely retrieve the actor's name from the resource.
func get_actor_name() -> String:
	return data.name if data else String(name)
