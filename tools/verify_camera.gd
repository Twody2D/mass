extends Node
## Checks the camera invariants that are not obvious from a screenshot: that
## the camera cannot be flown off the map or lost, and that Free mode adopts
## the orientation the scene placed it at rather than snapping to one.
##
## Rig-level concerns (mode switching, blending, targets, shake) have their
## own suite: verify_camera_rig.gd. This one is Free mode's own behaviour,
## reached through the rig the way the game actually drives it.

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var cam: CameraRig = main.get_node("Camera3D")
	var mode := cam.active_mode() as FreeCameraMode
	failures += _check("the rig starts on Free", mode != null)

	# One tick with no time passing applies enter()'s adoption to the rig's
	# actual transform without letting movement input (there is none, this is
	# headless) change anything else.
	cam._process(0.0)

	var pitch_degrees := rad_to_deg(cam.rotation.x)
	print("adopted pitch  : %.1f deg (scene placed it looking down)" % pitch_degrees)
	failures += _check("pitch is negative, i.e. looking down", pitch_degrees < 0.0)

	var limit: float = GameConfig.MAP_SIZE * 0.5 + FreeCameraMode.HORIZONTAL_MARGIN
	var far_away := mode._clamp_to_world(Vector3(999999.0, 999999.0, -999999.0))
	print("clamped extreme: ", far_away, " (limit %.0f, altitude %.0f..%.0f)"
		% [limit, FreeCameraMode.MIN_ALTITUDE, FreeCameraMode.MAX_ALTITUDE])
	failures += _check("x clamped", is_equal_approx(far_away.x, limit))
	failures += _check("z clamped", is_equal_approx(far_away.z, -limit))
	failures += _check("altitude capped", is_equal_approx(far_away.y, FreeCameraMode.MAX_ALTITUDE))

	var underground := mode._clamp_to_world(Vector3(0.0, -500.0, 0.0))
	failures += _check("never below minimum altitude",
		is_equal_approx(underground.y, FreeCameraMode.MIN_ALTITUDE))

	var inside := Vector3(10.0, 100.0, -20.0)
	failures += _check("positions inside the map are untouched",
		mode._clamp_to_world(inside).is_equal_approx(inside))

	# Speed must stay in range no matter how far the wheel is spun.
	for i in 200:
		mode.speed = minf(mode.speed * FreeCameraMode.SPEED_STEP, FreeCameraMode.MAX_SPEED)
	failures += _check("speed capped at maximum",
		is_equal_approx(mode.speed, FreeCameraMode.MAX_SPEED))
	for i in 400:
		mode.speed = maxf(mode.speed / FreeCameraMode.SPEED_STEP, FreeCameraMode.MIN_SPEED)
	failures += _check("speed floored at minimum",
		is_equal_approx(mode.speed, FreeCameraMode.MIN_SPEED))

	# Idle camera must not drift.
	mode.speed = FreeCameraMode.BASE_SPEED
	var before := cam.position
	for i in 10:
		cam._process(0.016)
	failures += _check("no drift without input", cam.position.is_equal_approx(before))

	# Looking around, the part that used to need a held button.
	mode._yaw = 0.0
	mode._pitch = 0.0
	_look(cam, mode, 100.0, 0.0)
	failures += _check("mouse turns the camera (yaw %.3f)" % mode._yaw, mode._yaw < 0.0)
	_look(cam, mode, 0.0, 100.0)
	failures += _check("mouse pitches the camera (%.3f)" % mode._pitch, mode._pitch < 0.0)
	for i in 200:
		_look(cam, mode, 0.0, -100.0)
	failures += _check("pitch stops short of straight up (%.1f deg)" % rad_to_deg(mode._pitch),
		is_equal_approx(mode._pitch, FreeCameraMode.MAX_PITCH))
	for i in 400:
		_look(cam, mode, 0.0, 100.0)
	failures += _check("pitch stops short of straight down (%.1f deg)" % rad_to_deg(mode._pitch),
		is_equal_approx(mode._pitch, -FreeCameraMode.MAX_PITCH))

	# Movement must stay level however far the camera is pitched.
	for yaw in [0.0, PI * 0.5, PI, -PI * 0.25]:
		mode._yaw = yaw
		failures += _check("forward is level at yaw %.2f" % yaw,
			is_zero_approx(mode.horizontal_forward().y))
	mode._yaw = 0.0
	failures += _check("yaw 0 faces -Z", mode.horizontal_forward().is_equal_approx(Vector3(0, 0, -1)))
	mode._yaw = PI * 0.5
	failures += _check("yaw 90 faces -X",
		mode.horizontal_forward().is_equal_approx(Vector3(-1, 0, 0)))
	failures += _check("right is perpendicular to forward",
		is_zero_approx(mode.horizontal_forward().dot(mode.horizontal_right())))

	# The pointer must be releasable, or the window becomes a trap. Escape
	# itself belongs to the pause menu now and is covered by verify_menu; the
	# camera only knows how to take and give back.
	cam.capture_mouse(true)
	failures += _check("mouse starts captured", cam.is_mouse_captured())
	cam.capture_mouse(false)
	failures += _check("the pointer can be released", not cam.is_mouse_captured())
	mode._yaw = 0.0
	_look(cam, mode, 100.0, 0.0)
	failures += _check("a released pointer does not turn the camera", is_zero_approx(mode._yaw))
	var idle := cam.position
	for i in 10:
		cam._process(0.016)
	failures += _check("a released pointer grounds the camera", cam.position.is_equal_approx(idle))
	_click(cam, mode, MOUSE_BUTTON_LEFT)
	failures += _check("a click takes the pointer back", cam.is_mouse_captured())
	cam.capture_mouse(false)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _look(cam: CameraRig, mode: FreeCameraMode, dx: float, dy: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(dx, dy)
	mode.unhandled_input(event, cam)


func _click(cam: CameraRig, mode: FreeCameraMode, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	mode.unhandled_input(event, cam)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
