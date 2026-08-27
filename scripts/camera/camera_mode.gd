class_name CameraMode
extends RefCounted
## One way of pointing the camera. CameraRig owns exactly one Camera3D and
## asks whichever mode is active for a transform every frame; switching modes
## blends between whatever the two of them last said rather than cutting.
##
## A mode is a plain object, not a node: it holds its own movement state
## (position, velocity, whatever it needs) but never touches the Camera3D
## directly. It only ever has to answer "where do you want the camera", not
## worry about how it got there or whether the rig is still easing in from
## wherever the last mode left off — the rig freezes that as a snapshot and
## blends into this mode's answer on its own.

## The name a mode is registered and switched to by. Unique across the rig.
func id() -> StringName:
	push_error("CameraMode: a mode did not override id().")
	return &""


## Called once when this mode becomes active, immediately before its first
## process() this switch. `from` is the transform the camera physically sat
## at the moment of the switch — normally the outgoing mode's last transform,
## but also what an external override (a tool positioning the camera by hand)
## left behind. A mode that cares where it starts (Free adopts a heading
## rather than snapping to one) reads it here.
func enter(_rig: CameraRig, _from: Transform3D) -> void:
	pass


## Called once when this mode stops being active, before the next mode's
## enter(). Exists for symmetry with enter(); nothing here needs it yet.
func exit(_rig: CameraRig) -> void:
	pass


## Advances the mode by delta and returns the transform it wants the camera
## at. The rig moves the camera there directly once a switch has finished
## blending, or partway there while one is still resolving.
func process(_delta: float, _rig: CameraRig) -> Transform3D:
	push_error("CameraMode: a mode did not override process().")
	return Transform3D()


## Raw input, forwarded only while this mode is the active one. Free camera
## mouse-look and the speed wheel live here rather than on the rig, which
## knows nothing about what any given mode wants from the keyboard or mouse.
func unhandled_input(_event: InputEvent, _rig: CameraRig) -> void:
	pass


## Whether this mode wants the mouse captured for looking around. The rig
## reads this after every switch and whenever something asks it to restore
## capture, so callers like the pause menu stay mode-agnostic: they release
## the pointer and ask for it back without needing to know what is active.
func wants_mouse_capture() -> bool:
	return false
