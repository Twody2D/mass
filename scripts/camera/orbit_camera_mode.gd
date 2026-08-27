class_name OrbitCameraMode
extends CameraMode
## Circles a target: distance on the wheel, angle on the mouse, plus a slow
## constant drift so the shot keeps moving even with nobody touching either.
##
## The mouse is captured and always active, the same feel Free uses — no
## button to hold, since this project already settled that question once.
## Auto-rotation and the mouse both drive the same yaw rather than fighting
## over it: the mouse nudges it, the drift keeps adding on top, exactly the
## way Free's velocity and input coexist.
##
## Tracks CameraTarget.resolve() every frame rather than once at enter(), so
## a bot target keeps the shot centred on it as it walks. If nothing is
## resolvable — no target set, or a bot target that has gone out of range —
## it holds the last centre it had rather than snapping to the map origin.

## Angular drift, always on. Slow enough to read as ambient rather than as
## the camera visibly spinning.
const AUTO_ROTATE_SPEED := 0.12

const MOUSE_SENSITIVITY := 0.0025
## Short of straight up/down: Basis.looking_at() degenerates once the eye-to-
## centre direction lines up with the up vector.
const MAX_PITCH := 1.5
const MIN_PITCH := -1.5

## Multiplicative, so one wheel notch feels the same at every distance.
const ZOOM_STEP := 1.15
const MIN_DISTANCE := 5.0
const MAX_DISTANCE := 1200.0
## Used only when entering with no target resolvable yet, to place a centre
## a sensible distance ahead of the camera rather than right on top of it.
const DEFAULT_DISTANCE := 60.0

var _center := Vector3.ZERO
var _distance := DEFAULT_DISTANCE
var _yaw := 0.0
var _pitch := 0.0


func id() -> StringName:
	return &"orbit"


## Picks up the target's centre if one is set, otherwise a point straight
## ahead of wherever the switch left the camera. Either way, yaw/pitch/
## distance are read back out of `from` relative to that centre, so entering
## Orbit does not jump — the same reasoning Free uses for its own heading.
func enter(rig: CameraRig, from: Transform3D) -> void:
	var resolved: Variant = rig.target().resolve()
	if resolved != null:
		_center = resolved
	else:
		_center = from.origin + (-from.basis.z) * DEFAULT_DISTANCE

	var offset := from.origin - _center
	var length := offset.length()
	if length < 0.001:
		_distance = DEFAULT_DISTANCE
		return
	_distance = clampf(length, MIN_DISTANCE, MAX_DISTANCE)
	_yaw = atan2(offset.x, offset.z)
	_pitch = clampf(asin(clampf(offset.y / length, -1.0, 1.0)), MIN_PITCH, MAX_PITCH)


func process(delta: float, rig: CameraRig) -> Transform3D:
	var resolved: Variant = rig.target().resolve()
	if resolved != null:
		_center = resolved
	_yaw += AUTO_ROTATE_SPEED * delta

	var horizontal := cos(_pitch)
	var offset := Vector3(sin(_yaw) * horizontal, sin(_pitch), cos(_yaw) * horizontal) * _distance
	var position := _center + offset
	var direction := (_center - position).normalized()
	return Transform3D(Basis.looking_at(direction, Vector3.UP), position)


func unhandled_input(event: InputEvent, rig: CameraRig) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_distance = clampf(_distance / ZOOM_STEP, MIN_DISTANCE, MAX_DISTANCE)
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = clampf(_distance * ZOOM_STEP, MIN_DISTANCE, MAX_DISTANCE)
			_:
				# Any click takes the pointer back after Escape released it.
				rig.capture_mouse(true)
	elif event is InputEventMouseMotion and rig.is_mouse_captured():
		var motion := event as InputEventMouseMotion
		_yaw -= motion.relative.x * MOUSE_SENSITIVITY
		_pitch = clampf(_pitch - motion.relative.y * MOUSE_SENSITIVITY, MIN_PITCH, MAX_PITCH)


func wants_mouse_capture() -> bool:
	return true
