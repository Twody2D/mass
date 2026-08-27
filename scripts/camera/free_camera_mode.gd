class_name FreeCameraMode
extends CameraMode
## Free flying observer camera, controlled the way creative flight works in
## Minecraft.
##
## The cursor is captured and the mouse always looks around, with no button to
## hold. A click takes the pointer back after something else has released it,
## and the camera stops flying whenever it does not hold the pointer. Escape
## belongs to the pause menu, not here.
##
## Movement is horizontal relative to where the camera is facing, and altitude
## is on its own keys. Looking up while pressing forward does not make the
## camera climb, which is what makes flying over a map predictable rather than
## a wrestling match with the pitch.
##
## Keys are polled by physical position, so WASD stays where it is on non-QWERTY
## layouts. Tuning lives here rather than in GameConfig: none of it means
## anything to any other system.

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

var _position := Vector3.ZERO
var _velocity := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0


func id() -> StringName:
	return &"free"


## Adopts wherever the switch left the camera rather than snapping to a fixed
## start: the same reasoning the old FreeCamera._ready() used for the scene's
## placed orientation, generalised to "whatever the rig was doing a moment
## ago", which after a mode switch is the outgoing mode's own transform.
func enter(_rig: CameraRig, from: Transform3D) -> void:
	_position = from.origin
	var euler := from.basis.get_euler(EULER_ORDER_YXZ)
	_pitch = clampf(euler.x, -MAX_PITCH, MAX_PITCH)
	_yaw = euler.y
	_velocity = Vector3.ZERO


func process(delta: float, rig: CameraRig) -> Transform3D:
	# No pointer, no flying. That keeps the camera still while the pause menu
	# is open without the menu having to reach in and disable it.
	if rig.is_mouse_captured():
		var target := _input_direction() * speed
		if Input.is_physical_key_pressed(KEY_CTRL):
			target *= BOOST_MULTIPLIER
		# Exponential smoothing, frame rate independent.
		_velocity = _velocity.lerp(target, 1.0 - exp(-ACCELERATION * delta))
		_position = _clamp_to_world(_position + _velocity * delta)
	else:
		_velocity = Vector3.ZERO
	return Transform3D(Basis.from_euler(Vector3(_pitch, _yaw, 0.0)), _position)


func unhandled_input(event: InputEvent, rig: CameraRig) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				speed = minf(speed * SPEED_STEP, MAX_SPEED)
			MOUSE_BUTTON_WHEEL_DOWN:
				speed = maxf(speed / SPEED_STEP, MIN_SPEED)
			_:
				# Any click takes the pointer back after Escape released it.
				rig.capture_mouse(true)
	elif event is InputEventMouseMotion and rig.is_mouse_captured():
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, -MAX_PITCH, MAX_PITCH)


func wants_mouse_capture() -> bool:
	return true


## Where forward is on the ground plane, ignoring pitch. Taken from the yaw
## directly rather than by flattening the basis, which degenerates to nothing
## when the camera looks straight down.
func horizontal_forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func horizontal_right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


## Horizontal movement follows the yaw only, and altitude is on its own keys.
func _input_direction() -> Vector3:
	var forward := horizontal_forward()
	var right := horizontal_right()
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W):
		direction += forward
	if Input.is_physical_key_pressed(KEY_S):
		direction -= forward
	if Input.is_physical_key_pressed(KEY_D):
		direction += right
	if Input.is_physical_key_pressed(KEY_A):
		direction -= right
	if Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_E):
		direction += Vector3.UP
	if Input.is_physical_key_pressed(KEY_SHIFT) or Input.is_physical_key_pressed(KEY_Q):
		direction -= Vector3.UP
	return direction.normalized()


func _clamp_to_world(p: Vector3) -> Vector3:
	var limit := GameConfig.MAP_SIZE * 0.5 + HORIZONTAL_MARGIN
	return Vector3(
		clampf(p.x, -limit, limit),
		clampf(p.y, MIN_ALTITUDE, MAX_ALTITUDE),
		clampf(p.z, -limit, limit))
