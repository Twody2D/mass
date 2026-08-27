class_name FreeCamera
extends Camera3D
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

## Impact shake. Rotation only, including roll: it is the cheapest thing that
## reads as being hit, and it cannot drift, because the true orientation lives
## in _pitch and _yaw and every frame rewrites rotation from them.
const SHAKE_DECAY := 2.8
const SHAKE_ANGLE := 0.05     ## radians of pitch and yaw at full strength
const SHAKE_ROLL := 0.09      ## radians of roll, deliberately the loudest axis
const SHAKE_FREQUENCY := 21.0
## How far a blast is felt, in blast radii. Past this the camera does not move
## at all, so a meteor on the far side of the island is not felt through rock.
const SHAKE_RANGE_IN_RADII := 3.0
## Below this the shake is over. Exponential decay never actually reaches zero,
## and a camera that trembles imperceptibly forever is a bug.
const SHAKE_FLOOR := 0.002

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

## Current shake strength, 0 to 1, and the clock that drives its wobble.
var _shake := 0.0
var _shake_time := 0.0


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


func _process(delta: float) -> void:
	# No pointer, no flying. That keeps the camera still while the pause menu is
	# open without the menu having to reach in and disable it. A shake already
	# running still plays out: it is the world hitting the camera, not the user
	# driving it.
	if _mouse_captured:
		var target := _input_direction() * speed
		if Input.is_physical_key_pressed(KEY_CTRL):
			target *= BOOST_MULTIPLIER
		# Exponential smoothing, frame rate independent.
		_velocity = _velocity.lerp(target, 1.0 - exp(-ACCELERATION * delta))
		position = _clamp_to_world(position + _velocity * delta)
	else:
		_velocity = Vector3.ZERO
	_apply_shake(delta)


## Shakes the view because something went off at `at`. The camera works out how
## hard from its own distance, which is the one thing an event has no business
## knowing: events say what happened and where, the camera decides how it felt.
func shake_from(at: Vector3, radius: float, strength: float) -> void:
	if radius <= 0.0:
		push_error("FreeCamera: shake_from() expects a positive radius, got %f." % radius)
		return
	var reach := radius * SHAKE_RANGE_IN_RADII
	var distance := global_position.distance_to(at)
	if distance >= reach:
		return
	# Squared falloff: standing in it throws the frame around, standing well
	# back is a tremor, and the middle is not a straight line between the two.
	var fall := 1.0 - distance / reach
	shake(strength * fall * fall)


## Starts a shake at `strength`, 0 to 1. Takes the louder of this and whatever
## is already running rather than adding: two events in the same second must not
## stack into footage nobody can watch.
func shake(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength, 0.0, 1.0))


func _apply_shake(delta: float) -> void:
	if _shake <= 0.0:
		return
	_shake *= exp(-SHAKE_DECAY * delta)
	if _shake < SHAKE_FLOOR:
		_shake = 0.0
		rotation = Vector3(_pitch, _yaw, 0.0)
		return
	_shake_time += delta
	# Three sines at unrelated rates rather than noise. It costs nothing, does
	# not repeat within the second a shake lasts, and a fresh random offset
	# every frame would flicker instead of shake.
	var t := _shake_time * SHAKE_FREQUENCY
	rotation = Vector3(
		_pitch + sin(t * 1.13) * SHAKE_ANGLE * _shake,
		_yaw + sin(t * 0.79 + 1.7) * SHAKE_ANGLE * _shake,
		sin(t * 1.37 + 3.1) * SHAKE_ROLL * _shake)


## True while an impact is still being felt. Exists so a test can watch a shake
## start and stop without reading private state.
func is_shaking() -> bool:
	return _shake > 0.0


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


