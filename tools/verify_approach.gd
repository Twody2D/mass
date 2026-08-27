extends Node
## Checks Approach's own behaviour: the path is a curve rather than a
## straight cut, progress eases in and out instead of moving at constant
## speed, it arrives and then holds, it keeps looking at a live target while
## flying a fixed path, and it does not want the mouse — this is a played
## shot, not a driven one.
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
	var index := 5
	cam.set_target(CameraTarget.on_bot(bots, index))

	cam._process(0.0)
	failures += _check("approach switches in", cam.set_mode(&"approach"))
	var mode := cam.active_mode() as ApproachCameraMode
	failures += _check("the active mode is ApproachCameraMode", mode != null)
	failures += _check("wants no mouse: this is played, not driven",
		not mode.wants_mouse_capture())
	failures += _check("has not arrived the instant it starts",
		not mode.is_arrived())

	print("--- shape: a curve, not a straight cut ---")
	var start := mode._start
	var end := mode._end
	var straight_mid := (start + end) * 0.5
	failures += _check("the control point bulges away from the straight line",
		mode._control.distance_to(straight_mid) > 1.0)
	var on_curve_mid := mode._bezier(start, mode._control, end, 0.5)
	failures += _check("the midpoint of the flight is off the straight line too",
		on_curve_mid.distance_to(straight_mid) > 0.5)

	print("--- easing: slow-fast-slow, not constant speed ---")
	var step := 0.05
	var early := mode._bezier(start, mode._control, end, mode._smoothstep(step)).distance_to(
		mode._bezier(start, mode._control, end, 0.0))
	var mid_a := mode._bezier(start, mode._control, end, mode._smoothstep(0.475))
	var mid_b := mode._bezier(start, mode._control, end, mode._smoothstep(0.525))
	var mid_speed := mid_a.distance_to(mid_b)
	var late := mode._bezier(start, mode._control, end, 1.0).distance_to(
		mode._bezier(start, mode._control, end, mode._smoothstep(1.0 - step)))
	print("  edge step      : %.3f m, %.3f m | middle step: %.3f m" % [early, late, mid_speed])
	failures += _check("covers less ground right at the start than in the middle",
		early < mid_speed)
	failures += _check("covers less ground right at the end than in the middle",
		late < mid_speed)

	print("--- flying the path ---")
	var duration: float = mode._duration
	var half_steps := 40
	var half_delta := (duration * 0.5) / half_steps
	for i in half_steps:
		cam._process(half_delta)
	failures += _check("partway through, still airborne", not mode.is_arrived())
	var midflight := mode.process(0.0, cam).origin
	failures += _check("partway through, off both endpoints",
		midflight.distance_to(start) > 1.0 and midflight.distance_to(end) > 1.0)

	for i in half_steps + 5:
		cam._process(half_delta)
	failures += _check("after its full duration, it has arrived", mode.is_arrived())
	var arrived_transform := mode.process(0.0, cam)
	failures += _check("arrival lands on the computed endpoint",
		arrived_transform.origin.is_equal_approx(end))

	for i in 10:
		cam._process(0.1)
	failures += _check("holds at the endpoint rather than overshooting",
		mode.process(0.0, cam).origin.is_equal_approx(end))

	print("--- looking at a live target while the path stays fixed ---")
	var expected: Vector3 = Vector3(bots.pos_x[index], bots.pos_y[index], bots.pos_z[index])
	var to_target := (expected - mode.process(0.0, cam).origin).normalized()
	var forward := -mode.process(0.0, cam).basis.z
	failures += _check("faces the target at rest", forward.dot(to_target) > 0.99)

	bots.pos_x[index] += 30.0
	var moved := Vector3(bots.pos_x[index], bots.pos_y[index], bots.pos_z[index])
	var position_after_move := mode.process(0.016, cam).origin
	failures += _check("the path itself does not move when the target does",
		position_after_move.is_equal_approx(end))
	var to_moved := (moved - position_after_move).normalized()
	var forward_after_move := -mode.process(0.0, cam).basis.z
	failures += _check("but the look direction follows the target that moved",
		forward_after_move.dot(to_moved) > 0.99)

	print("--- no target ---")
	cam.set_target(null)
	cam.set_mode(&"fpv_drone")
	cam._process(0.0)
	failures += _check("re-entering approach with no target succeeds",
		cam.set_mode(&"approach"))
	var untargeted := cam.active_mode() as ApproachCameraMode
	failures += _check("still produces a real destination ahead of the switch",
		untargeted._end.distance_to(untargeted._start) > 1.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
