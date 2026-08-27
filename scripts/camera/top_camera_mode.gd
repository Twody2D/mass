class_name TopCameraMode
extends CameraMode
## A high, fixed, straight-down shot — the one place a shockwave's ring or the
## crowd's flow around an obstacle reads as a shape rather than as a cloud of
## dots seen at an angle.
##
## Not a literal orthographic projection (Camera3D.projection is untouched,
## the same restraint every other mode already keeps: a mode only ever
## answers "where", never reaches into the rig's own properties, and an
## instant projection swap would pop rather than blend the way BLEND_SECONDS
## blends position). "Почти" is altitude doing the work instead: far enough
## up that the perspective the crowd is seen through goes shallow on its own,
## without needing the real thing.
##
## Orientation never turns to face the target and never auto-rotates the way
## Orbit does — it stays locked north-up, screen-right-is-east, the whole
## time. A top-down shot that spins is a shot nobody can read a direction
## off of frame to frame; holding it still is what makes "which way is the
## crowd moving" answerable at all.
##
## Tracks CameraTarget.resolve() live, the same as Orbit — only the ground
## position, never the altitude, which stays under the wheel's own control.
## With nothing to resolve it holds a point ahead of wherever the switch
## left the camera, the same fallback Ground and Approach already use.

## Where the wheel starts and returns to after a fresh switch-in with no
## prior altitude worth keeping. Chosen so the default field of view frames
## roughly the whole island at once.
const DEFAULT_ALTITUDE := 700.0

## Low enough to still read as a considered top-down shot, not a regular
## high shot that happens to look down.
const MIN_ALTITUDE := 150.0
const MAX_ALTITUDE := 1500.0

## Multiplicative, so one wheel notch feels the same at every altitude.
const ZOOM_STEP := 1.15

## Used only when entering with no target resolvable yet, the same fallback
## Ground and Approach use: a point ahead of wherever the switch left the
## camera.
const FALLBACK_LOOK_DISTANCE := 40.0

## Ground position only; y is unused, altitude is tracked separately so the
## wheel controls it independently of whatever the target's own height is.
var _center := Vector3.ZERO
var _altitude := DEFAULT_ALTITUDE


func id() -> StringName:
	return &"top"


func enter(rig: CameraRig, from: Transform3D) -> void:
	var resolved: Variant = rig.target().resolve()
	if resolved != null:
		var subject: Vector3 = resolved
		_center = Vector3(subject.x, 0.0, subject.z)
	else:
		var ahead := from.origin + (-from.basis.z) * FALLBACK_LOOK_DISTANCE
		_center = Vector3(ahead.x, 0.0, ahead.z)
	_altitude = clampf(from.origin.y, MIN_ALTITUDE, MAX_ALTITUDE)


func process(_delta: float, rig: CameraRig) -> Transform3D:
	var resolved: Variant = rig.target().resolve()
	if resolved != null:
		var subject: Vector3 = resolved
		_center = Vector3(subject.x, 0.0, subject.z)
	var position := Vector3(_center.x, _altitude, _center.z)
	# Rotate -90 degrees about world X: local forward (-Z) ends up pointing
	# straight down, local up (+Y) ends up pointing at world north (-Z), so
	# the frame reads north-up and never has to look_at() a moving target.
	var basis := Basis(Vector3.RIGHT, -PI / 2.0)
	return Transform3D(basis, position)


func unhandled_input(event: InputEvent, _rig: CameraRig) -> void:
	if event is InputEventMouseButton:
		var button := event as InputEventMouseButton
		if not button.pressed:
			return
		match button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_altitude = clampf(_altitude / ZOOM_STEP, MIN_ALTITUDE, MAX_ALTITUDE)
			MOUSE_BUTTON_WHEEL_DOWN:
				_altitude = clampf(_altitude * ZOOM_STEP, MIN_ALTITUDE, MAX_ALTITUDE)


## No mouse-look: the shot never turns, so there is nothing for the mouse to
## drive besides the wheel, which unhandled_input() already reads regardless
## of capture — the same split Free and Orbit use between wheel and look.
func wants_mouse_capture() -> bool:
	return false
