extends Node
## Checks Orbit mode's own behaviour: it centres on a target and keeps
## tracking it live, it holds its last centre once a target stops resolving,
## the wheel zooms within bounds, the mouse turns it within bounds, and the
## auto-rotate drift advances at the rate it claims.
##
## Rig-level concerns (switching into Orbit, blending, that it is registered)
## are verify_camera_rig.gd's job, the same split verify_camera.gd already
## uses for Free. This one is reached through the rig the way the game
## actually drives it.

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var cam: CameraRig = main.get_node("Camera3D")
	var bots: BotManager = main.get_node("Bots")

	cam._process(0.0)  ## settles Free at wherever the scene placed it
	var start := cam.transform.origin
	failures += _check("orbit switches in", cam.set_mode(&"orbit"))
	var mode := cam.active_mode() as OrbitCameraMode
	failures += _check("the active mode is Orbit", mode != null)

	print("--- entering with no target ---")
	failures += _check("with nothing to orbit it picks a centre ahead of the switch",
		is_equal_approx(mode._distance, OrbitCameraMode.DEFAULT_DISTANCE))
	failures += _check("that centre is not on top of the camera",
		mode._center.distance_to(start) > 1.0)

	print("--- auto-rotate ---")
	var before_yaw: float = mode._yaw
	var steps := 100
	var step_delta := 0.05
	for i in steps:
		cam._process(step_delta)
	var expected_drift := OrbitCameraMode.AUTO_ROTATE_SPEED * steps * step_delta
	print("  yaw drift      : %.3f rad (expected %.3f)" % [mode._yaw - before_yaw, expected_drift])
	failures += _check("yaw drifts at the advertised rate",
		is_equal_approx(mode._yaw - before_yaw, expected_drift))

	print("--- zoom ---")
	mode._distance = OrbitCameraMode.DEFAULT_DISTANCE
	_scroll(mode, cam, MOUSE_BUTTON_WHEEL_UP)
	failures += _check("wheel up zooms in", mode._distance < OrbitCameraMode.DEFAULT_DISTANCE)
	_scroll(mode, cam, MOUSE_BUTTON_WHEEL_DOWN)
	_scroll(mode, cam, MOUSE_BUTTON_WHEEL_DOWN)
	failures += _check("wheel down zooms out", mode._distance > OrbitCameraMode.DEFAULT_DISTANCE)
	for i in 300:
		_scroll(mode, cam, MOUSE_BUTTON_WHEEL_UP)
	failures += _check("distance floored at minimum",
		is_equal_approx(mode._distance, OrbitCameraMode.MIN_DISTANCE))
	for i in 300:
		_scroll(mode, cam, MOUSE_BUTTON_WHEEL_DOWN)
	failures += _check("distance capped at maximum",
		is_equal_approx(mode._distance, OrbitCameraMode.MAX_DISTANCE))
	mode._distance = OrbitCameraMode.DEFAULT_DISTANCE

	print("--- mouse angle ---")
	mode._pitch = 0.0
	var yaw_before: float = mode._yaw
	_look(mode, cam, 100.0, 0.0)
	failures += _check("mouse turns the yaw", mode._yaw != yaw_before)
	_look(mode, cam, 0.0, 100.0)
	failures += _check("mouse pitches down", mode._pitch < 0.0)
	for i in 300:
		_look(mode, cam, 0.0, -100.0)
	failures += _check("pitch stops short of straight up (%.2f)" % mode._pitch,
		is_equal_approx(mode._pitch, OrbitCameraMode.MAX_PITCH))
	for i in 300:
		_look(mode, cam, 0.0, 100.0)
	failures += _check("pitch stops short of straight down (%.2f)" % mode._pitch,
		is_equal_approx(mode._pitch, OrbitCameraMode.MIN_PITCH))
	mode._pitch = 0.0

	print("--- shape ---")
	var wanted := mode.process(0.0, cam)
	var offset := wanted.origin - mode._center
	failures += _check("the camera sits at the orbit's own distance",
		is_equal_approx(offset.length(), mode._distance))
	var to_center := (mode._center - wanted.origin).normalized()
	failures += _check("and looks back at the centre",
		to_center.dot(-wanted.basis.z) > 0.99)
	failures += _check("wants the mouse", mode.wants_mouse_capture())

	print("--- tracking a live target ---")
	bots.spawn(20, GameConfig.DEFAULT_MAP_SEED)
	var index := 3
	cam.set_target(CameraTarget.on_bot(bots, index))
	cam._process(0.016)
	var expected := Vector3(bots.pos_x[index], bots.pos_y[index], bots.pos_z[index])
	failures += _check("centres on the bot", mode._center.is_equal_approx(expected))
	bots.pos_x[index] += 40.0
	cam._process(0.016)
	var moved := Vector3(bots.pos_x[index], bots.pos_y[index], bots.pos_z[index])
	failures += _check("keeps tracking it as it moves", mode._center.is_equal_approx(moved))

	print("--- a target that stops resolving ---")
	var last_center := mode._center
	bots.spawn(2, GameConfig.DEFAULT_MAP_SEED)  ## shrinks the crowd out from under index 3
	cam._process(0.016)
	failures += _check("holds the last known centre instead of snapping to nothing",
		mode._center.is_equal_approx(last_center))

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _look(mode: OrbitCameraMode, cam: CameraRig, dx: float, dy: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(dx, dy)
	mode.unhandled_input(event, cam)


func _scroll(mode: OrbitCameraMode, cam: CameraRig, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	mode.unhandled_input(event, cam)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
