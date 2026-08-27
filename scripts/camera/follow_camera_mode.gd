class_name FollowCameraMode
extends CameraMode
## Trails one knight from behind and slightly above, the way a third-person
## chase camera does. Not driven — like Approach, no mouse or wheel here;
## Follow's whole job is staying attached to its subject, not being steered.
##
## Both the camera's position and where it looks are their own smoothed
## values (_position, _look_at), each chasing an "ideal" spot computed fresh
## every frame from the target's live position and facing — a spot behind
## the knight's heading, not behind wherever the camera itself happens to be
## sitting. That distinction matters: deriving the offset from the camera's
## own position would make the offset self-referential and never settle,
## the same way it would if Free's velocity target depended on Free's own
## smoothed velocity instead of raw input.

const FOLLOW_DISTANCE := 9.0
const FOLLOW_HEIGHT := 4.5
const LOOK_HEIGHT := 2.0

## How fast the camera's actual position/look catch up to their ideal spot.
## Position lags a little more than look: the frame settling in a beat after
## the eye has already found the subject reads as intentional, not sluggish.
const POSITION_SMOOTHING := 3.0
const LOOK_SMOOTHING := 5.0

var _position := Vector3.ZERO
var _look_at := Vector3.ZERO


func id() -> StringName:
	return &"follow"


func enter(rig: CameraRig, from: Transform3D) -> void:
	_position = from.origin
	var resolved: Variant = rig.target().resolve()
	if resolved != null:
		_look_at = (resolved as Vector3) + Vector3.UP * LOOK_HEIGHT
	else:
		_look_at = from.origin + (-from.basis.z) * FOLLOW_DISTANCE


func process(delta: float, rig: CameraRig) -> Transform3D:
	var target := rig.target()
	var resolved: Variant = target.resolve()
	if resolved == null:
		# Nothing to follow right now — hold rather than chase a target that
		# is not there. Chasing "wherever the camera currently is" would be
		# self-referential and never converge; holding is the honest answer.
		return _look_transform()

	var subject: Vector3 = resolved
	var facing: Variant = target.resolve_facing()
	var behind: Vector3
	if facing != null and (facing as Vector3).length() > 0.001:
		behind = -(facing as Vector3)
	else:
		# No facing to read (a point/event target, or a bot standing dead
		# still) — keep whatever relative angle the camera already has
		# rather than snapping to an arbitrary default every frame.
		var current_offset := _position - subject
		behind = current_offset.normalized() if current_offset.length() > 0.01 else Vector3.BACK

	var ideal_position := subject + behind * FOLLOW_DISTANCE + Vector3.UP * FOLLOW_HEIGHT
	var ideal_look := subject + Vector3.UP * LOOK_HEIGHT

	_position = _position.lerp(ideal_position, 1.0 - exp(-POSITION_SMOOTHING * delta))
	_look_at = _look_at.lerp(ideal_look, 1.0 - exp(-LOOK_SMOOTHING * delta))

	return _look_transform()


func wants_mouse_capture() -> bool:
	return false


func _look_transform() -> Transform3D:
	var direction := _look_at - _position
	var basis := Basis.looking_at(direction, Vector3.UP) if direction.length() > 0.001 else Basis.IDENTITY
	return Transform3D(basis, _position)
