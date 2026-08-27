class_name CameraRig
extends Camera3D
## The one Camera3D in the scene. Owns a registry of modes and asks whichever
## one is active where the camera should be; everything else — blending a
## switch, screen shake, mouse capture, cycling modes from the keyboard — is
## mode-agnostic and lives here rather than being duplicated in every mode.
##
## Modes are plain objects (see CameraMode), not nodes: they never touch this
## Camera3D directly, only answer "where do you want to be" when asked.

## How long a switch takes to blend, in seconds. A hard cut reads as a mistake
## on camera; this is long enough to see as a deliberate move and short enough
## not to feel like a delay.
const BLEND_SECONDS := 0.5

## Impact shake. Rotation only, including roll: it is the cheapest thing that
## reads as being hit, and it cannot drift, because it is layered on top of
## whatever the active mode already set rotation to this frame rather than
## accumulating into a stored orientation of its own.
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

## Registered modes, in registration order. The order is what "next mode" (TAB)
## cycles through, so it is kept as a list rather than trusting a Dictionary's
## iteration order.
var _modes := {}
var _mode_order: Array[StringName] = []
var _active: CameraMode
var _active_id := &""

var _blend_from := Transform3D.IDENTITY
var _blend_elapsed := 0.0
var _blending := false

var _target := CameraTarget.none()

## The camera's own intent, not a query of Input.mouse_mode. A display server
## may ignore a capture request, and whether a mode turns should not depend
## on that.
var _mouse_captured := false

## Current shake strength, 0 to 1, and the clock that drives its wobble.
var _shake := 0.0
var _shake_time := 0.0


func _ready() -> void:
	register_mode(FreeCameraMode.new())
	register_mode(OrbitCameraMode.new())
	register_mode(FPVDroneMode.new())
	register_mode(ApproachCameraMode.new())
	register_mode(FollowCameraMode.new())
	register_mode(GroundCameraMode.new())
	register_mode(TopCameraMode.new())


func _notification(what: int) -> void:
	# Losing focus while captured would trap the cursor in a window the user
	# has already left. Mode-agnostic: whatever is active loses the pointer.
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		capture_mouse(false)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.is_echo() and key.physical_keycode == KEY_TAB:
			next_mode()
			get_viewport().set_input_as_handled()
			return
	if _active != null:
		_active.unhandled_input(event, self)


func _process(delta: float) -> void:
	if _active == null:
		return
	var wanted := _active.process(delta, self)
	if _blending:
		_blend_elapsed += delta
		var t := clampf(_blend_elapsed / BLEND_SECONDS, 0.0, 1.0)
		wanted = _blend_from.interpolate_with(wanted, t)
		if t >= 1.0:
			_blending = false
	transform = wanted
	_apply_shake(delta)


## Adds a mode to the registry. The first one registered becomes active
## immediately, adopting whatever transform the scene placed the camera at —
## the same reasoning the old free camera used for its starting orientation.
func register_mode(mode: CameraMode) -> void:
	if mode == null:
		push_error("CameraRig: register_mode() got null.")
		return
	var mode_id := mode.id()
	if _modes.has(mode_id):
		push_error("CameraRig: two modes claim the id '%s'." % mode_id)
		return
	_modes[mode_id] = mode
	_mode_order.append(mode_id)
	if _active == null:
		_activate(mode_id, transform)


## Switches to a registered mode, blending from wherever the camera currently
## sits. Returns false and says why rather than silently doing nothing, so a
## typo in a future Director's mode name is not a camera that quietly never
## moves.
func set_mode(mode_id: StringName) -> bool:
	if not _modes.has(mode_id):
		push_error("CameraRig: no mode named '%s'. Known modes: %s." % [mode_id, _mode_order])
		return false
	if mode_id != _active_id:
		_activate(mode_id, transform)
	return true


## Steps to the next registered mode, in registration order, wrapping around.
## A no-op with only one mode registered — cycling has nothing to cycle to
## yet, not a bug.
func next_mode() -> void:
	if _mode_order.size() < 2:
		return
	var i := _mode_order.find(_active_id)
	set_mode(_mode_order[(i + 1) % _mode_order.size()])


func active_mode_id() -> StringName:
	return _active_id


func active_mode() -> CameraMode:
	return _active


func known_modes() -> Array[StringName]:
	return _mode_order.duplicate()


## Tells the active mode to adopt wherever the camera physically sits right
## now, without a blend. For something outside the rig that moved the camera
## directly — a screenshot tool placing it by hand — and does not want that
## undone by the mode recomputing from stale internal state next frame.
func sync_active_mode() -> void:
	if _active == null:
		return
	_active.enter(self, transform)
	_blending = false


func set_target(target: CameraTarget) -> void:
	_target = target if target != null else CameraTarget.none()


func target() -> CameraTarget:
	return _target


## Grabs or releases the pointer. Releasing always works; capturing only
## takes if the active mode actually wants a captured mouse, so a caller like
## the pause menu can ask for the pointer back without knowing what mode is
## running. Public so the UI can free it when it needs to.
func capture_mouse(active: bool) -> void:
	var wants := active and _active != null and _active.wants_mouse_capture()
	_mouse_captured = wants
	if wants:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif active:
		# Something asked for capture, but the active mode does not want the
		# mouse at all — Approach, Follow. No menu is open in this case, so
		# there is nothing to point at; hide the cursor instead of leaving it
		# floating over what is meant to play like a cut, not a UI.
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	else:
		# Explicitly released — the pause menu opening, or the window losing
		# focus. The player needs the pointer back to click anything.
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func is_mouse_captured() -> bool:
	return _mouse_captured


## Shakes the view because something went off at `at`. The camera works out
## how hard from its own distance, which is the one thing an event has no
## business knowing: events say what happened and where, the camera decides
## how it felt. Mode-agnostic: whatever is active gets shaken the same way.
func shake_from(at: Vector3, radius: float, strength: float) -> void:
	if radius <= 0.0:
		push_error("CameraRig: shake_from() expects a positive radius, got %f." % radius)
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
## is already running rather than adding: two events in the same second must
## not stack into footage nobody can watch.
func shake(strength: float) -> void:
	_shake = maxf(_shake, clampf(strength, 0.0, 1.0))


## True while an impact is still being felt. Exists so a test can watch a
## shake start and stop without reading private state.
func is_shaking() -> bool:
	return _shake > 0.0


func _apply_shake(delta: float) -> void:
	if _shake <= 0.0:
		return
	_shake *= exp(-SHAKE_DECAY * delta)
	if _shake < SHAKE_FLOOR:
		# Nothing to reset: rotation is already this frame's clean value from
		# the active mode, set by _process() before this ever runs.
		_shake = 0.0
		return
	_shake_time += delta
	# Three sines at unrelated rates rather than noise. It costs nothing, does
	# not repeat within the second a shake lasts, and a fresh random offset
	# every frame would flicker instead of shake.
	var t := _shake_time * SHAKE_FREQUENCY
	var base := rotation
	rotation = Vector3(
		base.x + sin(t * 1.13) * SHAKE_ANGLE * _shake,
		base.y + sin(t * 0.79 + 1.7) * SHAKE_ANGLE * _shake,
		base.z + sin(t * 1.37 + 3.1) * SHAKE_ROLL * _shake)


func _activate(mode_id: StringName, from: Transform3D) -> void:
	if _active != null:
		_active.exit(self)
	_active_id = mode_id
	_active = _modes[mode_id]
	_active.enter(self, from)
	_blend_from = from
	_blend_elapsed = 0.0
	_blending = true
	capture_mouse(true)
