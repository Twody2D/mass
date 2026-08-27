class_name FPVDroneMode
extends CameraMode
## Free flight again, but heavier: the shot is meant to look like it was
## actually filmed by something with mass, not nudged around by a mouse.
##
## Three things do that job, all layered on top of the same acceleration
## model FreeCameraMode already uses:
##
## - Inertia is softer (a lower ACCELERATION than Free), so the drone keeps
##   sliding for a moment after input stops instead of settling immediately.
## - The camera banks into a turn: how far _yaw has pulled ahead of a lagged
##   copy of itself feeds a smoothed roll, the same way a quad visibly leans
##   into the direction it is steering rather than turning flat. That gap,
##   not a per-frame turn rate, is what banks it — see LAG_RATE below for why.
## - A small constant wobble rides on top of pitch, roll and position even at
##   a dead stop. Free is deliberately still when idle; this is deliberately
##   not — a hovering drone never is either.
##
## Movement and looking are otherwise identical to Free: same keys, same
## mouse-always-looks feel. What changes here is how the camera responds, not
## how it is driven.

const BASE_SPEED := 60.0
const MIN_SPEED := 2.0
const MAX_SPEED := 800.0
const SPEED_STEP := 1.15
const BOOST_MULTIPLIER := 3.0
const MOUSE_SENSITIVITY := 0.0025
const MAX_PITCH := 1.5533  ## 89 degrees, short of gimbal flip

## Markedly lower than Free's 10.0. That is the entire "inertia" effect: the
## same exponential smoothing, converging slower.
const ACCELERATION := 3.0

## Banking reads off how far _yaw has pulled away from _lagged_yaw, a copy of
## it that only ever catches up at LAG_RATE. That gap is proportional to how
## fast and how long the turn has been going, and it moves as smoothly as the
## turn itself — unlike a per-frame rate (delta-yaw / delta-time), which
## mouse input makes noisy: motion arrives in bursts that do not line up
## with frame boundaries, so a naive rate swings between the extremes on
## consecutive frames instead of tracking the turn.
const LAG_RATE := 4.0
const BANK_PER_LAG := 1.0
const BANK_RATE := 3.5
const MAX_BANK := 0.5  ## ~29 degrees, enough to read without looking broken

## Constant idle motion. Amplitudes are in metres (position) and radians
## (rotation) — small enough to read as an unsteady hover, not a shake.
const WOBBLE_POSITION := 0.12
const WOBBLE_ROTATION := 0.008
const WOBBLE_FREQUENCY := 1.7

const MIN_ALTITUDE := 1.0
const MAX_ALTITUDE := 2000.0
const HORIZONTAL_MARGIN := 400.0

var speed := BASE_SPEED

var _position := Vector3.ZERO
var _velocity := Vector3.ZERO
var _yaw := 0.0
var _pitch := 0.0

var _bank := 0.0
var _lagged_yaw := 0.0

var _wobble_time := 0.0


func id() -> StringName:
	return &"fpv_drone"


func enter(_rig: CameraRig, from: Transform3D) -> void:
	_position = from.origin
	var euler := from.basis.get_euler(EULER_ORDER_YXZ)
	_pitch = clampf(euler.x, -MAX_PITCH, MAX_PITCH)
	_yaw = euler.y
	_velocity = Vector3.ZERO
	_bank = 0.0
	_lagged_yaw = _yaw


func process(delta: float, rig: CameraRig) -> Transform3D:
	if rig.is_mouse_captured():
		var target := _input_direction() * speed
		if Input.is_physical_key_pressed(KEY_CTRL):
			target *= BOOST_MULTIPLIER
		_velocity = _velocity.lerp(target, 1.0 - exp(-ACCELERATION * delta))
		_position = _clamp_to_world(_position + _velocity * delta)
	else:
		_velocity = Vector3.ZERO

	_lagged_yaw = lerpf(_lagged_yaw, _yaw, 1.0 - exp(-LAG_RATE * delta))
	var target_bank := clampf((_yaw - _lagged_yaw) * BANK_PER_LAG, -MAX_BANK, MAX_BANK)
	_bank = lerpf(_bank, target_bank, 1.0 - exp(-BANK_RATE * delta))

	_wobble_time += delta
	var wobble_pitch := sin(_wobble_time * WOBBLE_FREQUENCY * 1.13) * WOBBLE_ROTATION
	var wobble_roll := sin(_wobble_time * WOBBLE_FREQUENCY * 0.79 + 1.7) * WOBBLE_ROTATION
	var basis := Basis.from_euler(Vector3(_pitch + wobble_pitch, _yaw, _bank + wobble_roll))

	var wobble_offset := (
		basis.y * sin(_wobble_time * WOBBLE_FREQUENCY) * WOBBLE_POSITION
		+ basis.x * sin(_wobble_time * WOBBLE_FREQUENCY * 0.61 + 0.9) * WOBBLE_POSITION * 0.6)

	return Transform3D(basis, _position + wobble_offset)


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
				rig.capture_mouse(true)
	elif event is InputEventMouseMotion and rig.is_mouse_captured():
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, -MAX_PITCH, MAX_PITCH)


func wants_mouse_capture() -> bool:
	return true


func horizontal_forward() -> Vector3:
	return Vector3(-sin(_yaw), 0.0, -cos(_yaw))


func horizontal_right() -> Vector3:
	return Vector3(cos(_yaw), 0.0, -sin(_yaw))


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
