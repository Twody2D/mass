extends Node
## Checks what makes FPVDroneMode read as filmed rather than mouse-nudged:
## inertia carries motion past the moment input stops, a turn banks the
## camera and eases back out of it, idle still wobbles instead of freezing
## dead, and everything shares Free's bounds (world clamp, pitch, speed).
##
## Rig-level concerns are verify_camera_rig.gd's job, the same split
## verify_camera.gd and verify_orbit.gd already use.

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var cam: CameraRig = main.get_node("Camera3D")

	cam._process(0.0)
	failures += _check("fpv_drone switches in", cam.set_mode(&"fpv_drone"))
	var mode := cam.active_mode() as FPVDroneMode
	failures += _check("the active mode is FPVDroneMode", mode != null)

	print("--- world bounds, shared with Free ---")
	var limit: float = GameConfig.MAP_SIZE * 0.5 + FPVDroneMode.HORIZONTAL_MARGIN
	var far_away := mode._clamp_to_world(Vector3(999999.0, 999999.0, -999999.0))
	failures += _check("x clamped", is_equal_approx(far_away.x, limit))
	failures += _check("altitude capped", is_equal_approx(far_away.y, FPVDroneMode.MAX_ALTITUDE))
	var underground := mode._clamp_to_world(Vector3(0.0, -500.0, 0.0))
	failures += _check("never below minimum altitude",
		is_equal_approx(underground.y, FPVDroneMode.MIN_ALTITUDE))

	print("--- inertia: motion outlasts input ---")
	mode._yaw = 0.0
	mode._pitch = 0.0
	mode._position = Vector3.ZERO
	# Physical-key polling cannot be faked without a display server, so push
	# velocity directly the way one tick of held W would have left it, then
	# process with no input held and confirm the drone keeps sliding instead
	# of stopping on the spot the way Free does.
	mode._velocity = Vector3(0.0, 0.0, -mode.speed)
	var before := mode._position
	cam._process(0.05)
	var after_one_tick := mode._position
	failures += _check("still moving one tick after input stops",
		after_one_tick.distance_to(before) > 0.1)
	for i in 80:
		cam._process(0.05)
	failures += _check("velocity has decayed back towards zero",
		mode._velocity.length() < 0.5)

	print("--- banking into a turn ---")
	mode._bank = 0.0
	mode._lagged_yaw = mode._yaw
	for i in 20:
		_look(mode, cam, 80.0, 0.0)
		cam._process(0.016)
	print("  bank after turn: %.3f rad" % mode._bank)
	failures += _check("turning right banks the camera", mode._bank != 0.0)
	var bank_while_turning := mode._bank
	for i in 60:
		cam._process(0.016)  ## no more mouse motion
	failures += _check("bank eases back towards level once the turn stops",
		absf(mode._bank) < absf(bank_while_turning))

	print("--- idle wobble ---")
	mode._velocity = Vector3.ZERO
	mode._position = Vector3(50.0, 60.0, 50.0)
	var base := mode._position
	var farthest := 0.0
	var sum := Vector3.ZERO
	for i in 40:
		var origin := mode.process(0.05, cam).origin
		farthest = maxf(farthest, origin.distance_to(base))
		sum += origin
	var average := sum / 40.0
	print("  furthest wobble: %.3f m from base" % farthest)
	failures += _check("idle position wobbles rather than freezing dead", farthest > 0.01)
	failures += _check("but stays small, not a drift", farthest < 2.0)
	failures += _check("wobble stays centred near where it was left, not carried away",
		average.distance_to(base) < 1.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _look(mode: FPVDroneMode, cam: CameraRig, dx: float, dy: float) -> void:
	var event := InputEventMouseMotion.new()
	event.relative = Vector2(dx, dy)
	mode.unhandled_input(event, cam)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
