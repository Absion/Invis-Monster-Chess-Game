extends Node3D
class_name GimbalCamera

## Custom 3D Gimbal Camera simulating an isometric perspective.
##
## This script dynamically builds its camera hierarchy. Attach this to an empty Node3D.
## Handles WASD panning, edge-panning, scroll-wheel zooming,
## and middle-mouse-drag rotation around the Y axis.

@export_group("Movement")
@export var max_pan_speed: float = 15.0
@export var pan_acceleration_curve: Curve
@export var enable_edge_pan: bool = false
@export var edge_pan_margin: float = 20.0
@export var max_edge_pan_speed: float = 15.0

@export_group("Rotation & Zoom")
@export var rotation_speed: float = 0.005
@export var zoom_speed: float = 50.0
@export var min_zoom: float = 5.0
@export var max_zoom: float = 60.0

var inner_gimbal: Node3D
var camera: Camera3D

var _target_zoom: float = 35.0

# Tracks how long the pan keys have been held down for curve evaluation
var _pan_time: float = 0.0
var _edge_pan_time: float = 0.0

func _ready() -> void:
	# Provide a default curve if none is assigned in the inspector
	if pan_acceleration_curve == null:
		pan_acceleration_curve = Curve.new()
		pan_acceleration_curve.add_point(Vector2(0, 0.2)) # Start at 20% speed
		pan_acceleration_curve.add_point(Vector2(0.5, 1.0)) # Reach max speed at 0.5 seconds
		
	_setup_camera_hierarchy()
	# Center the camera on the 8x8 grid (which spans 0 to 14, so center is 7.0)
	global_position = Vector3(7.0, 0.0, 7.0)

## Programmatically creates the Inner Gimbal and Orthogonal Camera
## to prevent the need for manual scene tree setup.
func _setup_camera_hierarchy() -> void:
	inner_gimbal = Node3D.new()
	inner_gimbal.name = "InnerGimbal"
	add_child(inner_gimbal)
	
	camera = Camera3D.new()
	camera.name = "IsometricCamera"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _target_zoom
	# Push the camera back so it doesn't clip with the origin
	camera.position.z = 100.0
	inner_gimbal.add_child(camera)
	
	# Initial isometric rotation
	rotation_degrees.y = 45.0
	inner_gimbal.rotation_degrees.x = -45.0 # Tilted higher for a better view of the board

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		# Zooming
		if event.is_pressed():
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				_target_zoom -= zoom_speed * 0.1
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_target_zoom += zoom_speed * 0.1
			
			_target_zoom = clamp(_target_zoom, min_zoom, max_zoom)

func _process(delta: float) -> void:
	_handle_panning(delta)
	_smooth_zoom(delta)

func _handle_panning(delta: float) -> void:
	var keyboard_pan_dir := Vector3.ZERO
	var edge_pan_dir := Vector3.ZERO
	
	# Keyboard Panning
	if Input.is_physical_key_pressed(KEY_W):
		keyboard_pan_dir.z -= 1
	if Input.is_physical_key_pressed(KEY_S):
		keyboard_pan_dir.z += 1
	if Input.is_physical_key_pressed(KEY_A):
		keyboard_pan_dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D):
		keyboard_pan_dir.x += 1
		
	# Edge Panning
	if enable_edge_pan and keyboard_pan_dir == Vector3.ZERO:
		var mouse_pos = get_viewport().get_mouse_position()
		var viewport_size = get_viewport().get_visible_rect().size
		
		if mouse_pos.x < edge_pan_margin:
			edge_pan_dir.x -= 1
		elif mouse_pos.x > viewport_size.x - edge_pan_margin:
			edge_pan_dir.x += 1
			
		if mouse_pos.y < edge_pan_margin:
			edge_pan_dir.z -= 1
		elif mouse_pos.y > viewport_size.y - edge_pan_margin:
			edge_pan_dir.z += 1

	var final_move := Vector3.ZERO
	
	# Process Keyboard Pan
	if keyboard_pan_dir != Vector3.ZERO:
		_pan_time += delta
		var curve_multiplier = pan_acceleration_curve.sample(_pan_time)
		var move_vector = _transform_dir(keyboard_pan_dir)
		final_move = move_vector * (max_pan_speed * curve_multiplier)
		# Reset edge pan
		_edge_pan_time = 0.0
	else:
		_pan_time = 0.0
		
	# Process Edge Pan if no keyboard input
	if final_move == Vector3.ZERO and edge_pan_dir != Vector3.ZERO:
		_edge_pan_time += delta
		var curve_multiplier = pan_acceleration_curve.sample(_edge_pan_time)
		var move_vector = _transform_dir(edge_pan_dir)
		final_move = move_vector * (max_edge_pan_speed * curve_multiplier)
	elif final_move == Vector3.ZERO:
		_edge_pan_time = 0.0

	if final_move != Vector3.ZERO:
		global_position += final_move * delta

func _transform_dir(dir: Vector3) -> Vector3:
	dir = dir.normalized()
	# Move the camera relative to its current Y rotation
	var forward = global_transform.basis.z
	var right = global_transform.basis.x
	
	# Flatten vectors
	forward.y = 0
	right.y = 0
	forward = forward.normalized()
	right = right.normalized()
	
	return (right * dir.x + forward * dir.z)

func _smooth_zoom(delta: float) -> void:
	if not is_instance_valid(camera): return
	# Smoothly interpolate orthogonal size
	camera.size = lerp(camera.size, _target_zoom, 10.0 * delta)

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
