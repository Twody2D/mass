extends Node
## Checks CameraRig itself: mode registration and switching, that a switch
## actually blends instead of cutting, that cycling wraps and no-ops with
## only one mode, that a target resolves for a point/a bot/an event, and that
## mouse capture asks the active mode rather than assuming one.
##
## Free mode's own movement is verify_camera.gd's job. This suite never
## checks what Free does — only what the rig around it does, using two throw-
## away stub modes so the checks do not depend on any real mode existing.

## Two minimal modes that stand still exactly where they are told, used only
## to prove the rig's own mechanics without depending on Free or on any mode
## that has not been built yet.
class _StubMode extends CameraMode:
	var _id: StringName
	var _at: Vector3
	var _captures: bool

	func _init(mode_id: StringName, at: Vector3, captures: bool = false) -> void:
		_id = mode_id
		_at = at
		_captures = captures

	func id() -> StringName:
		return _id

	func process(_delta: float, _rig: CameraRig) -> Transform3D:
		return Transform3D(Basis.IDENTITY, _at)

	func wants_mouse_capture() -> bool:
		return _captures


## A rig that skips its own default registration, so a test can start from
## truly empty and check next_mode()'s single-mode no-op without CameraRig's
## own built-in modes getting in the way.
class _SoloRig extends CameraRig:
	func _ready() -> void:
		pass


func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var rig: CameraRig = main.get_node("Camera3D")
	var bots: BotManager = main.get_node("Bots")
	var world: World = main.get_node("World")

	print("--- registration ---")
	failures += _check(
		"free, orbit, fpv_drone, approach, follow, ground, top and director are registered by default",
		rig.known_modes() == ([
			&"free", &"orbit", &"fpv_drone", &"approach", &"follow", &"ground", &"top", &"director",
		] as Array[StringName]))
	failures += _check("free is active on start", rig.active_mode_id() == &"free")

	# Y well above anything the island's own terrain clamp (CameraRig's own
	# GROUND_CLEARANCE above the real heightmap, peaking under 110 m) could
	# ever touch — these checks are about the rig's switching and blending,
	# not about terrain collision, which has its own section further down.
	var a := _StubMode.new(&"stub_a", Vector3(100.0, 500.0, 0.0))
	var b := _StubMode.new(&"stub_b", Vector3(0.0, 500.0, 200.0), true)
	rig.register_mode(a)
	rig.register_mode(b)
	failures += _check("registering does not steal the active mode",
		rig.active_mode_id() == &"free")
	failures += _check("known modes list all ten in order",
		rig.known_modes() == ([
			&"free", &"orbit", &"fpv_drone", &"approach", &"follow", &"ground", &"top", &"director",
			&"stub_a", &"stub_b",
		] as Array[StringName]))

	# register_mode() returns nothing; refusal is checked by the registry
	# staying the size it was rather than by a return value.
	rig.register_mode(_StubMode.new(&"stub_a", Vector3.ZERO))
	failures += _check("a duplicate id does not get added twice",
		rig.known_modes().size() == 10)

	print("--- lookup by id ---")
	failures += _check("mode() finds a registered mode without activating it",
		rig.mode(&"stub_b") == b and rig.active_mode_id() == &"free")
	failures += _check("mode() answers null for an id nothing claims",
		rig.mode(&"nope") == null)

	print("--- switching and blending ---")
	failures += _check("switching to an unknown mode is refused", not rig.set_mode(&"nope"))
	failures += _check("and does not change the active mode", rig.active_mode_id() == &"free")

	rig._process(0.0)  ## settles Free at wherever the scene placed it
	var before_switch := rig.transform.origin
	failures += _check("switching to a known mode succeeds", rig.set_mode(&"stub_a"))
	failures += _check("the active mode changed", rig.active_mode_id() == &"stub_a")

	rig._process(0.0)
	failures += _check("at the instant of a switch the camera has not jumped yet",
		rig.transform.origin.is_equal_approx(before_switch))

	var halfway := before_switch.lerp(Vector3(100.0, 500.0, 0.0), 0.5)
	rig._process(CameraRig.BLEND_SECONDS * 0.5)
	print("  halfway        : %s (expected near %s)" % [rig.transform.origin, halfway])
	failures += _check("partway through a switch the camera is partway there",
		rig.transform.origin.distance_to(halfway) < 5.0)

	rig._process(CameraRig.BLEND_SECONDS)
	failures += _check("a finished switch lands exactly on the new mode's spot",
		rig.transform.origin.is_equal_approx(Vector3(100.0, 500.0, 0.0)))

	print("--- cycling ---")
	failures += _check("next_mode steps forward", rig.set_mode(&"stub_a") and true)
	rig.next_mode()
	failures += _check("cycling from stub_a goes to stub_b", rig.active_mode_id() == &"stub_b")
	rig.next_mode()
	failures += _check("cycling wraps back to free", rig.active_mode_id() == &"free")

	# CameraRig always registers its own defaults in _ready(), so a real rig
	# never actually has just one mode any more. _SoloRig skips that to test
	# next_mode()'s "nothing to cycle to yet" branch in isolation.
	var solo := _SoloRig.new()
	add_child(solo)
	solo.register_mode(_StubMode.new(&"only", Vector3.ZERO))
	failures += _check("a rig with one mode registered has just that one",
		solo.known_modes() == ([&"only"] as Array[StringName]))
	solo.next_mode()
	failures += _check("cycling with one mode is a no-op", solo.active_mode_id() == &"only")
	solo.queue_free()

	print("--- mouse capture asks the active mode ---")
	# Input.mouse_mode itself is not checked here: headless has no display
	# server, and setting/reading it is not meaningful without one — the same
	# limitation screenshot.gd hit needing a real run. is_mouse_captured() is
	# the part of this that headless can actually observe.
	rig.set_mode(&"stub_a")  ## does not want capture
	rig._process(CameraRig.BLEND_SECONDS)
	rig.capture_mouse(true)
	failures += _check("a mode that does not want capture does not get it",
		not rig.is_mouse_captured())
	rig.set_mode(&"stub_b")  ## wants capture
	rig._process(CameraRig.BLEND_SECONDS)
	rig.capture_mouse(true)
	failures += _check("a mode that wants capture gets it", rig.is_mouse_captured())
	rig.capture_mouse(false)
	failures += _check("release always works regardless of the mode",
		not rig.is_mouse_captured())

	print("--- sync_active_mode ---")
	rig.set_mode(&"free")
	rig._process(CameraRig.BLEND_SECONDS)
	rig.transform = Transform3D(Basis.IDENTITY, Vector3(500.0, 40.0, -300.0))
	rig.sync_active_mode()
	rig._process(0.0)
	failures += _check("after a sync, one more tick does not undo an external move",
		rig.transform.origin.is_equal_approx(Vector3(500.0, 40.0, -300.0)))

	print("--- targets ---")
	failures += _check("no target resolves to nothing", CameraTarget.none().resolve() == null)
	failures += _check("not set reads as not set", not CameraTarget.none().is_set())

	var point_target := CameraTarget.at_point(Vector3(12.0, 3.0, 4.0))
	failures += _check("a point target resolves to that point",
		point_target.resolve() == Vector3(12.0, 3.0, 4.0))
	failures += _check("a point target is set", point_target.is_set())

	var event_target := CameraTarget.at_event(Vector3(1.0, 2.0, 3.0))
	failures += _check("an event target resolves to its snapshot",
		event_target.resolve() == Vector3(1.0, 2.0, 3.0))

	# An Array rather than a plain Vector3: GDScript lambdas capture a local
	# value type by value at creation, so reassigning a captured Vector3
	# afterward would not prove anything about resolve() calling live — the
	# resolver has to close over something mutable, the same way a real one
	# closes over a Node reference and reads its current position.
	var live := [Vector3(5.0, 5.0, 5.0)]
	var callable_target := CameraTarget.at_callable(func() -> Variant: return live[0])
	failures += _check("a callable target resolves to whatever it currently returns",
		callable_target.resolve() == live[0])
	live[0] = Vector3(9.0, 9.0, 9.0)
	failures += _check("and keeps calling it rather than a snapshot",
		callable_target.resolve() == live[0])
	var gone_target := CameraTarget.at_callable(func() -> Variant: return null)
	failures += _check("a callable that has nothing to say resolves to nothing",
		gone_target.resolve() == null)
	failures += _check("an invalid callable is refused",
		not CameraTarget.at_callable(Callable()).is_set())

	bots.spawn(50, GameConfig.DEFAULT_MAP_SEED)
	var bot_target := CameraTarget.on_bot(bots, 3)
	var expected := Vector3(bots.pos_x[3], bots.pos_y[3], bots.pos_z[3])
	failures += _check("a bot target resolves to that bot's live position",
		bot_target.resolve() == expected)
	bots.pos_x[3] += 15.0
	failures += _check("and keeps tracking it rather than a snapshot",
		bot_target.resolve() == Vector3(bots.pos_x[3], bots.pos_y[3], bots.pos_z[3]))

	failures += _check("an out-of-range bot index is refused",
		not CameraTarget.on_bot(bots, 99999).is_set())
	var stale := CameraTarget.on_bot(bots, bots.count - 1)
	bots.spawn(10, GameConfig.DEFAULT_MAP_SEED)  ## shrinks the crowd out from under it
	failures += _check("a target whose bot no longer exists resolves to nothing",
		stale.resolve() == null)

	rig.set_target(point_target)
	failures += _check("the rig remembers a target it was given",
		rig.target().resolve() == Vector3(12.0, 3.0, 4.0))
	rig.set_target(null)
	failures += _check("setting a null target clears it rather than crashing",
		not rig.target().is_set())

	print("--- the rig does not sink under the terrain ---")
	failures += _check("Main wires a world into the rig", rig.world == world)

	rig.set_mode(&"free")
	rig._process(CameraRig.BLEND_SECONDS)
	var deep := Vector3(300.0, -50.0, 300.0)
	rig.transform = Transform3D(Basis.IDENTITY, deep)
	rig.sync_active_mode()
	rig._process(0.0)
	var floor_y := world.get_height(deep.x, deep.z) + CameraRig.GROUND_CLEARANCE
	failures += _check("dropped far below the ground, it is lifted back to the terrain",
		rig.position.y >= floor_y - 0.01)
	rig._process(0.016)
	failures += _check("and stays lifted on the next frame too",
		rig.position.y >= floor_y - 0.01)

	var comfortable := Vector3(300.0, floor_y + 500.0, 300.0)
	rig.transform = Transform3D(Basis.IDENTITY, comfortable)
	rig.sync_active_mode()
	rig._process(0.0)
	failures += _check("well clear of the ground, nothing pushes it around",
		is_equal_approx(rig.position.y, comfortable.y))

	rig.world = null
	rig.transform = Transform3D(Basis.IDENTITY, deep)
	rig.sync_active_mode()
	rig._process(0.0)
	# Free clamps its own altitude to a flat floor regardless (MIN_ALTITUDE) —
	# what this checks is that with no world wired, the rig adds nothing
	# past that, the same optional-dependency fallback CrowdRenderer's own
	# `camera` field already uses.
	failures += _check("no world wired means no additional terrain lift",
		is_equal_approx(rig.position.y, FreeCameraMode.MIN_ALTITUDE))
	rig.world = world

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
