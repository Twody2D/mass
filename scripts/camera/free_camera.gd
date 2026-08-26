class_name FreeCamera
extends Camera3D
## Free flying observer camera, in the style of the Godot editor's own flycam.
##
## Mouse look is bound to holding the right button rather than permanently
## capturing the cursor, because the debug UI needs the pointer. Keys are polled
## by physical position, so WASD stays where it is on non-QWERTY layouts.
##
## Tuning lives here rather than in GameConfig: none of it means anything to any
## other system.

const BASE_SPEED := 80.0
const MIN_SPEED := 2.0
const MAX_SPEED := 1200.0
## Multiplicative, so one wheel notch feels the same at every speed.
const SPEED_STEP := 1.15
const BOOST_MULTIPLIER := 4.0
const MOUSE_SENSITIVITY := 0.0025
const MAX_PITCH := 1.5533  ## 89 degrees, short of gimbal flip
## Higher converges faster. Some smoothing keeps recorded footage watchable.
const ACCELERATION := 10.0

## Vertical limits in metres, and a horizontal margin beyond the map edge, so
## the camera cannot be flown off into empty space and lost.
const MIN_ALTITUDE := 1.0
const MAX_ALTITUDE := 2000.0
const HORIZONTAL_MARGIN := 400.0

var speed := BASE_SPEED

var _velocity := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
var _looking := false


func _ready() -> void:
	# Adopt whatever orientation the scene placed us at instead of snapping.
	_yaw = rotation.y
	_pitch = clampf(rotation.x, -MAX_PITCH, MAX_PITCH)


func _notification(what: int) -> void:
	# Losing focus mid-drag would otherwise leave the cursor captured.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_set_looking(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		match button.button_index:
			MOUSE_BUTTON_RIGHT:
				_set_looking(button.pressed)
			MOUSE_BUTTON_WHEEL_UP:
				if button.pressed:
					speed = minf(speed * SPEED_STEP, MAX_SPEED)
			MOUSE_BUTTON_WHEEL_DOWN:
				if button.pressed:
					speed = maxf(speed / SPEED_STEP, MIN_SPEED)
	elif event is InputEventMouseMotion and _looking:
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, -MAX_PITCH, MAX_PITCH)
		rotation = Vector3(_pitch, _yaw, 0.0)


func _process(delta: float) -> void:
	var target := _input_direction() * speed
	if Input.is_physical_key_pressed(KEY_SHIFT):
		target *= BOOST_MULTIPLIER
	# Exponential smoothing, frame rate independent.
	_velocity = _velocity.lerp(target, 1.0 - exp(-ACCELERATION * delta))
	position = _clamp_to_world(position + _velocity * delta)


## Movement is relative to where the camera is pointing, except for the vertical
## axis, which stays world aligned so climbing does not depend on the pitch.
func _input_direction() -> Vector3:
	var forward := -global_transform.basis.z
	var right := global_transform.basis.x
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		direction += forward
	if Input.is_physical_key_pressed(KEY_S):
		direction -= forward
	if Input.is_physical_key_pressed(KEY_D):
		direction += right
	if Input.is_physical_key_pressed(KEY_A):
		direction -= right
	if Input.is_physical_key_pressed(KEY_E) or Input.is_physical_key_pressed(KEY_SPACE):
		direction += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q) or Input.is_physical_key_pressed(KEY_CTRL):
		direction -= Vector3.UP
	return direction.normalized()


func _clamp_to_world(p: Vector3) -> Vector3:
	var limit := GameConfig.MAP_SIZE * 0.5 + HORIZONTAL_MARGIN
	return Vector3(
		clampf(p.x, -limit, limit),
		clampf(p.y, MIN_ALTITUDE, MAX_ALTITUDE),
		clampf(p.z, -limit, limit))


func _set_looking(active: bool) -> void:
	if _looking == active:
		return
	_looking = active
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE
