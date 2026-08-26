class_name FreeCamera
extends Camera3D
## Free flying observer camera, controlled the way creative flight works in
## Minecraft.
##
## The cursor is captured and the mouse always looks around, with no button to
## hold. Escape releases it when the pointer is needed elsewhere, and a click
## takes it back.
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

var _velocity := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0
## The camera's own intent, not a query of Input.mouse_mode. A display server
## may ignore a capture request, and whether the camera turns should not depend
## on that.
var _mouse_captured := false


func _ready() -> void:
	# Adopt whatever orientation the scene placed us at instead of snapping.
	_yaw = rotation.y
	_pitch = clampf(rotation.x, -MAX_PITCH, MAX_PITCH)
	capture_mouse(true)


func _notification(what: int) -> void:
	# Losing focus while captured would trap the cursor in a window the user has
	# already left.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		capture_mouse(false)


## Grabs or releases the pointer. Public so the UI can free it when it needs to.
func capture_mouse(active: bool) -> void:
	_mouse_captured = active
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if active else Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	return _mouse_captured


func _unhandled_input(event: InputEvent) -> void:
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
				capture_mouse(true)
	elif event is InputEventMouseMotion and is_mouse_captured():
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, -MAX_PITCH, MAX_PITCH)
		rotation = Vector3(_pitch, _yaw, 0.0)
	elif event is InputEventKey and event.is_pressed():
		if (event as InputEventKey).physical_keycode == KEY_ESCAPE:
			capture_mouse(false)


func _process(delta: float) -> void:
	var target := _input_direction() * speed
	if Input.is_physical_key_pressed(KEY_CTRL):
		target *= BOOST_MULTIPLIER
	# Exponential smoothing, frame rate independent.
	_velocity = _velocity.lerp(target, 1.0 - exp(-ACCELERATION * delta))
	position = _clamp_to_world(position + _velocity * delta)


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


