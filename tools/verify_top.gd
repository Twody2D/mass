extends Node
## Checks Top's own behaviour: it sits directly above its target at a fixed,
## wheel-controlled altitude, looks straight down with a locked north-up
## orientation that never turns, tracks a live target's ground position
## without touching altitude, and falls back to a point ahead of the switch
## when there is nothing to track — the same fallback Ground and Approach
## already use.
##
## Rig-level concerns are verify_camera_rig.gd's job, the same split every
## other mode's suite already uses.

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var cam: CameraRig = main.get_node("Camera3D")
	var bots: BotManager = main.get_node("Bots")

	bots.spawn(20, GameConfig.DEFAULT_MAP_SEED)
	var index := 4
	bots.pos_x[index] = 100.0
	bots.pos_y[index] = 20.0
	bots.pos_z[index] = 100.0
	cam.set_target(CameraTarget.on_bot(bots, index))

	cam._process(0.0)  ## settles Free at wherever the scene placed it
	failures += _check("top switches in", cam.set_mode(&"top"))
	var mode := cam.active_mode() as TopCameraMode
	failures += _check("the active mode is Top", mode != null)
	failures += _check("wants no mouse: it never turns, there is nothing to look with",
		not mode.wants_mouse_capture())

	print("--- shape: directly above the target, straight down, north-up ---")
	var subject := Vector3(bots.pos_x[index], bots.pos_y[index], bots.pos_z[index])
	var wanted := mode.process(0.0, cam)
	print("  camera at      : %s (subject at %s)" % [wanted.origin, subject])
	failures += _check("centred over the subject's ground position",
		is_equal_approx(wanted.origin.x, subject.x)
		and is_equal_approx(wanted.origin.z, subject.z))
	failures += _check("altitude is independent of the subject's own height",
		wanted.origin.y > subject.y + MIN_ALTITUDE_MARGIN)
	failures += _check("looks straight down",
		(-wanted.basis.z).is_equal_approx(Vector3.DOWN))
	failures += _check("screen-up faces world north",
		wanted.basis.y.is_equal_approx(Vector3(0.0, 0.0, -1.0)))
	failures += _check("screen-right faces world east",
		wanted.basis.x.is_equal_approx(Vector3.RIGHT))

	print("--- zoom ---")
	mode._altitude = TopCameraMode.DEFAULT_ALTITUDE
	_scroll(mode, cam, MOUSE_BUTTON_WHEEL_UP)
	failures += _check("wheel up descends", mode._altitude < TopCameraMode.DEFAULT_ALTITUDE)
	_scroll(mode, cam, MOUSE_BUTTON_WHEEL_DOWN)
	_scroll(mode, cam, MOUSE_BUTTON_WHEEL_DOWN)
	failures += _check("wheel down climbs", mode._altitude > TopCameraMode.DEFAULT_ALTITUDE)
	for i in 300:
		_scroll(mode, cam, MOUSE_BUTTON_WHEEL_UP)
	failures += _check("altitude floored at minimum",
		is_equal_approx(mode._altitude, TopCameraMode.MIN_ALTITUDE))
	for i in 300:
		_scroll(mode, cam, MOUSE_BUTTON_WHEEL_DOWN)
	failures += _check("altitude capped at maximum",
		is_equal_approx(mode._altitude, TopCameraMode.MAX_ALTITUDE))
	mode._altitude = TopCameraMode.DEFAULT_ALTITUDE

	print("--- tracking a live target, on the ground plane only ---")
	bots.pos_x[index] += 40.0
	bots.pos_y[index] += 5.0
	cam._process(0.016)
	var moved := Vector3(bots.pos_x[index], bots.pos_y[index], bots.pos_z[index])
	failures += _check("keeps tracking the ground position as it moves",
		is_equal_approx(mode._center.x, moved.x) and is_equal_approx(mode._center.z, moved.z))
	failures += _check("the target climbing does not change the camera's own altitude",
		is_equal_approx(mode._altitude, TopCameraMode.DEFAULT_ALTITUDE))

	print("--- no target ---")
	cam.set_target(null)
	cam.set_mode(&"fpv_drone")
	cam._process(0.0)
	var before_switch := cam.transform
	failures += _check("re-entering top with no target succeeds", cam.set_mode(&"top"))
	var untargeted := cam.active_mode() as TopCameraMode
	var ahead := before_switch.origin + (-before_switch.basis.z) * TopCameraMode.FALLBACK_LOOK_DISTANCE
	failures += _check("centres on a point ahead of the switch, not the map origin",
		is_equal_approx(untargeted._center.x, ahead.x)
		and is_equal_approx(untargeted._center.z, ahead.z))

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Just needs to clear the subject's own height comfortably; not a precise
## bound, only guards against the altitude collapsing onto the target.
const MIN_ALTITUDE_MARGIN := 50.0


func _scroll(mode: TopCameraMode, cam: CameraRig, button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = true
	mode.unhandled_input(event, cam)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
