class_name GroundCameraMode
extends CameraMode
## A tripod planted at roughly a knight's own height, close enough that
## scale reads: everywhere else the crowd is watched from hundreds of
## metres up, where ten thousand toy figures are ten thousand dots. Down
## here a single one fills the frame.
##
## Unpiloted like Approach and Follow — no mouse, no wheel. Unlike Follow
## it does not dolly after its subject: the tripod plants once in enter()
## and holds, the same "fixed position, live look" split Approach uses
## once it has arrived. The contrast is the point — this is meant to be a
## shot the subject walks through, not a shot that chases it.

## Camera altitude above the subject's own ground contact. Not the full
## BOT_HEIGHT (a knight's actual height) but close to it — near eye level
## looking slightly up, rather than planted at the very top of its head.
const EYE_HEIGHT := 2.0

## How close the tripod sits. Close enough for the scale contrast to read,
## far enough not to clip through the subject.
const GROUND_DISTANCE := 5.0

## Aims a little above the subject's own base rather than dead at its feet.
const LOOK_HEIGHT := 1.0

## Used only when entering with no target resolvable yet, the same fallback
## Orbit and Approach use: a point ahead of wherever the switch left the
## camera.
const FALLBACK_LOOK_DISTANCE := 40.0

var _position := Vector3.ZERO

## What to look at once the live target stops resolving — the target's last
## known spot, or the fallback point if there was never a target at all.
var _look_fallback := Vector3.ZERO


func id() -> StringName:
	return &"ground"


func enter(rig: CameraRig, from: Transform3D) -> void:
	var resolved: Variant = rig.target().resolve()
	var subject: Vector3
	if resolved != null:
		subject = resolved
	else:
		subject = from.origin + (-from.basis.z) * FALLBACK_LOOK_DISTANCE
	_look_fallback = subject

	var flat := Vector3(from.origin.x - subject.x, 0.0, from.origin.z - subject.z)
	var away := flat.normalized() if flat.length() > 0.001 else Vector3.BACK

	_position = subject + away * GROUND_DISTANCE
	_position.y = subject.y + EYE_HEIGHT


func process(_delta: float, rig: CameraRig) -> Transform3D:
	var resolved: Variant = rig.target().resolve()
	var subject: Vector3 = resolved if resolved != null else _look_fallback
	var look_point := subject + Vector3.UP * LOOK_HEIGHT

	var direction := look_point - _position
	var basis := Basis.looking_at(direction, Vector3.UP) if direction.length() > 0.001 else Basis.IDENTITY
	return Transform3D(basis, _position)


func wants_mouse_capture() -> bool:
	return false
