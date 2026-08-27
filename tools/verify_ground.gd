extends Node
## Checks Ground's own behaviour: it plants close to the subject at roughly
## a knight's own height, it holds that position rather than dollying after
## a moving target, it keeps looking at a live target while planted, and it
## does not want the mouse — a played shot, the same as Approach and Follow.
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

	cam._process(0.0)
	failures += _check("ground switches in", cam.set_mode(&"ground"))
	var mode := cam.active_mode() as GroundCameraMode
	failures += _check("the active mode is GroundCameraMode", mode != null)
	failures += _check("wants no mouse: this is played, not driven",
		not mode.wants_mouse_capture())

	print("--- plants close, at roughly a knight's own height ---")
	var subject := Vector3(bots.pos_x[index], bots.pos_y[index], bots.pos_z[index])
	var planted := mode.process(0.0, cam)
	print("  planted at     : %s (subject at %s)" % [planted.origin, subject])
	failures += _check("altitude sits near the subject's ground contact, not far above it",
		is_equal_approx(planted.origin.y, subject.y + GroundCameraMode.EYE_HEIGHT))
	failures += _check("horizontal distance is close, for the scale contrast to read",
		is_equal_approx(
			Vector3(planted.origin.x, 0.0, planted.origin.z).distance_to(
				Vector3(subject.x, 0.0, subject.z)),
			GroundCameraMode.GROUND_DISTANCE))
	var to_subject := (subject - planted.origin).normalized()
	failures += _check("looking roughly at the subject",
		(-planted.basis.z).dot(to_subject) > 0.9)

	print("--- holds still rather than dollying after a moving target ---")
	var before := mode.process(0.0, cam).origin
	for i in 60:
		bots.pos_x[index] += 2.0
		cam._process(0.05)
	var after := mode.process(0.0, cam).origin
	failures += _check("the tripod did not move even though the subject walked off",
		after.is_equal_approx(before))

	print("--- but keeps looking at the target that moved ---")
	var moved_subject := Vector3(bots.pos_x[index], bots.pos_y[index], bots.pos_z[index])
	var forward := -mode.process(0.0, cam).basis.z
	var to_moved := (moved_subject - after).normalized()
	failures += _check("the look direction followed the target, the position did not",
		forward.dot(to_moved) > 0.99)

	print("--- no target ---")
	cam.set_target(null)
	cam.set_mode(&"fpv_drone")
	cam._process(0.0)
	failures += _check("re-entering ground with no target succeeds",
		cam.set_mode(&"ground"))
	var untargeted := cam.active_mode() as GroundCameraMode
	failures += _check("still plants somewhere real, not on top of the switch point",
		untargeted.process(0.0, cam).origin.distance_to(cam.transform.origin) > 0.1)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
