extends Node
## Checks CrowdRenderer's LOD split: every bot lands in exactly one tier, the
## right tier for its distance from the camera, tiers actually carry fewer
## triangles the coarser they get, a dead bot stays drawn (lying down, not
## vanished) on whichever tier holds it, and reassignment is throttled
## rather than happening every frame.
##
## Whether a specific bot's transform/visibility is correct within its tier is
## verify_death.gd's job already, through visible_bots() — this suite is about
## which tier a bot ends up on, not the per-instance math once it is there.

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var bots: BotManager = main.get_node("Bots")
	var crowd: CrowdRenderer = main.get_node("Crowd")
	var cam: CameraRig = main.get_node("Camera3D")

	bots.spawn(40, GameConfig.DEFAULT_MAP_SEED)

	print("--- no camera wired: everyone stays on the nearest tier ---")
	crowd.camera = null
	crowd.rebuild()
	var all_near := true
	for i in bots.count:
		if crowd.tier_of(i) != &"lod_near":
			all_near = false
			break
	failures += _check("every bot is on lod_near", all_near)
	failures += _check("instance count covers every bot",
		crowd.rendered_instance_count() == bots.count)

	print("--- distance bands ---")
	crowd.camera = cam
	cam.position = Vector3.ZERO
	# Four bots placed at known distances straddling each threshold, the rest
	# left wherever spawn put them — this only checks that these four land
	# where their distance says they should.
	var near_bot := 0
	var medium_bot := 1
	var far_bot := 2
	var very_far_bot := 3
	_place(bots, near_bot, Vector3(0.0, 0.0, 30.0))
	_place(bots, medium_bot, Vector3(0.0, 0.0, 100.0))
	_place(bots, far_bot, Vector3(0.0, 0.0, 300.0))
	_place(bots, very_far_bot, Vector3(0.0, 0.0, 600.0))
	crowd.rebuild()

	failures += _check("30 m away is lod_near", crowd.tier_of(near_bot) == &"lod_near")
	failures += _check("100 m away is lod_medium", crowd.tier_of(medium_bot) == &"lod_medium")
	failures += _check("300 m away is lod_far", crowd.tier_of(far_bot) == &"lod_far")
	failures += _check("600 m away is lod_very_far", crowd.tier_of(very_far_bot) == &"lod_very_far")
	failures += _check("instance count still covers every bot",
		crowd.rendered_instance_count() == bots.count)

	print("--- coarser tiers really do carry fewer triangles ---")
	var report := crowd.tier_report()
	failures += _check("four tiers reported", report.size() == 4)
	var strictly_decreasing := true
	for i in report.size() - 1:
		if report[i].triangles <= report[i + 1].triangles:
			strictly_decreasing = false
	failures += _check("near > medium > far > very_far in triangle cost", strictly_decreasing)
	for entry in report:
		print("  %-13s %5d bots, %3d tris/instance" % [entry.id, entry.instances, entry.triangles])

	print("--- a corpse stays drawn on whichever tier holds it ---")
	bots.kill(far_bot)
	crowd.update_transforms()
	var visible := crowd.visible_bots()
	failures += _check("the far corpse is still drawn", visible[far_bot] == 1)
	failures += _check("its living neighbour on the same tier still is",
		visible[near_bot] == 1)

	print("--- reassignment is throttled, not instant ---")
	# near_bot currently sits on lod_near, with cam at the origin. Moving the
	# camera away should not change that on the very next frame — only once
	# LOD_REFRESH_FRAMES frames have passed.
	cam.position = Vector3(0.0, 0.0, 1000.0)
	crowd.update_transforms()
	failures += _check("one frame after the camera moves, still stale",
		crowd.tier_of(near_bot) == &"lod_near")
	for i in CrowdRenderer.LOD_REFRESH_FRAMES:
		crowd.update_transforms()
	failures += _check("after a full refresh cycle, caught up",
		crowd.tier_of(near_bot) == &"lod_very_far")

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _place(bots: BotManager, index: int, at: Vector3) -> void:
	bots.pos_x[index] = at.x
	bots.pos_y[index] = at.y
	bots.pos_z[index] = at.z


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
