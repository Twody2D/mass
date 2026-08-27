extends Node
## Checks Follow's own behaviour: it settles behind a bot's facing, it
## keeps up as the bot moves and turns, it holds still rather than chasing
## itself when there is nothing to follow, and it wants no mouse — this is
## a played shot, not a driven one, the same as Approach.
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
	var index := 7
	bots.pos_x[index] = 0.0
	bots.pos_y[index] = 0.0
	bots.pos_z[index] = 0.0
	bots.face_x[index] = 0.0
	bots.face_z[index] = 1.0  ## facing +Z

	cam.set_target(CameraTarget.on_bot(bots, index))
	cam._process(0.0)
	failures += _check("follow switches in", cam.set_mode(&"follow"))
	var mode := cam.active_mode() as FollowCameraMode
	failures += _check("the active mode is FollowCameraMode", mode != null)
	failures += _check("wants no mouse: this is played, not driven",
		not mode.wants_mouse_capture())

	print("--- settles in behind the knight's facing ---")
	for i in 200:
		cam._process(0.05)  ## plenty of time to converge, well past both time constants
	var settled := mode.process(0.0, cam)
	var subject := Vector3(bots.pos_x[index], bots.pos_y[index], bots.pos_z[index])
	print("  settled at     : %s (subject at %s)" % [settled.origin, subject])
	failures += _check("stands roughly FOLLOW_DISTANCE behind the knight",
		is_equal_approx(
			Vector3(settled.origin.x, 0.0, settled.origin.z).distance_to(
				Vector3(subject.x, 0.0, subject.z)),
			FollowCameraMode.FOLLOW_DISTANCE))
	failures += _check("behind means opposite the facing (+Z), so camera z is negative",
		settled.origin.z < subject.z)
	failures += _check("above the knight, not level with its feet",
		settled.origin.y > subject.y + 1.0)
	var to_subject := (subject - settled.origin).normalized()
	failures += _check("looking roughly at the knight",
		(-settled.basis.z).dot(to_subject) > 0.95)

	print("--- keeps up as the knight walks ---")
	for i in 60:
		bots.pos_x[index] += 1.0
		cam._process(0.05)
	var moved_subject := Vector3(bots.pos_x[index], bots.pos_y[index], bots.pos_z[index])
	var after_walk := mode.process(0.0, cam)
	print("  gap after walk : %.2f m" % after_walk.origin.distance_to(moved_subject))
	failures += _check("camera followed, not left behind",
		after_walk.origin.distance_to(moved_subject) < FollowCameraMode.FOLLOW_DISTANCE * 2.0)

	print("--- turning: behind tracks the new facing ---")
	bots.face_x[index] = 1.0
	bots.face_z[index] = 0.0  ## now facing +X
	for i in 200:
		cam._process(0.05)
	var turned := mode.process(0.0, cam)
	var turned_subject := Vector3(bots.pos_x[index], bots.pos_y[index], bots.pos_z[index])
	failures += _check("camera swung round to stay behind the new heading",
		turned.origin.x < turned_subject.x)

	print("--- nothing to follow ---")
	cam.set_target(null)
	var before_none := mode.process(0.0, cam).origin
	for i in 20:
		cam._process(0.05)
	var after_none := mode.process(0.0, cam).origin
	failures += _check("holds still instead of chasing a target that is not there",
		after_none.is_equal_approx(before_none))

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
