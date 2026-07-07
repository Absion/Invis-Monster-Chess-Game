extends Node3D
class_name GimbalCamera

## Custom 3D Gimbal Camera simulating an isometric perspective.
##
## This script dynamically builds its camera hierarchy. Attach this to an empty Node3D.
## The camera is static, orthographic, and centered on the board.

var inner_gimbal: Node3D
var camera: Camera3D

func _ready() -> void:
	_setup_camera_hierarchy()
	# Center the camera on the 12x12 grid (which spans 0 to 22, so center is 11.0)
	global_position = Vector3(11.0, 0.0, 11.0)

## Programmatically creates the Inner Gimbal and Orthogonal Camera
## to prevent the need for manual scene tree setup.
func _setup_camera_hierarchy() -> void:
	inner_gimbal = Node3D.new()
	inner_gimbal.name = "InnerGimbal"
	add_child(inner_gimbal)
	
	camera = Camera3D.new()
	camera.name = "IsometricCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	# A size of 35 is enough to fit a 10x10 board with a 2.0 cell size comfortably
	camera.size = 35.0
	# Push the camera back so it doesn't clip with the origin
	camera.position.z = 100.0
	inner_gimbal.add_child(camera)
	
	# Initial isometric rotation
	rotation_degrees.y = 45.0
	inner_gimbal.rotation_degrees.x = -45.0 # Tilted higher for a better view of the board

var _shake_tween: Tween

## Shakes the camera screen to indicate an impact or stun.
func shake(intensity: float = 0.5, duration: float = 0.4) -> void:
	if not is_instance_valid(camera): return
	
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
		
	_shake_tween = create_tween()
	var shake_steps = 10
	var step_duration = duration / shake_steps
	
	var original_pos = Vector3(0, 0, 100.0) # Matches _setup_camera_hierarchy
	
	for i in range(shake_steps):
		var rand_offset = Vector3(
			randf_range(-intensity, intensity),
			randf_range(-intensity, intensity),
			0.0
		)
		_shake_tween.tween_property(camera, "position", original_pos + rand_offset, step_duration)
		
	# End by snapping back to original position
	_shake_tween.tween_property(camera, "position", original_pos, step_duration)
