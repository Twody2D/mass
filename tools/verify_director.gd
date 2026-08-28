extends Node
## Checks Director's own behaviour: it delegates to a real registered mode
## rather than answering itself, it hands that mode a living bot or an
## event's location depending on why it cut, it holds a shot for a bounded
## random duration and then cuts again, a shake reacts promptly but does not
## spam multiple cuts out of one impact, and switching away and back starts
## clean rather than resuming stale state.
##
## Rig-level concerns (registration, blending into and out of Director as a
## mode) are verify_camera_rig.gd's job, the same split every other mode's
## suite already uses.

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var cam: CameraRig = main.get_node("Camera3D")
	var bots: BotManager = main.get_node("Bots")
	var events: EventManager = main.get_node("Events")

	bots.spawn(50, GameConfig.DEFAULT_MAP_SEED)
	cam._process(0.0)  ## settles Free at wherever the scene placed it

	var director := cam.mode(&"director") as Director
	failures += _check("director is registered by default", director != null)
	director.wire(bots, events)
	director.reseed(GameConfig.DEFAULT_MAP_SEED)

	print("--- delegates rather than answering itself ---")
	failures += _check("director switches in", cam.set_mode(&"director"))
	cam._process(0.0)
	var delegate_mode := cam.mode(director._last_shot_id)
	failures += _check("picked a shot from the idle pool",
		Director.IDLE_SHOTS.has(director._last_shot_id))
	failures += _check("delegated to the real registered instance of that shot",
		director._delegate == delegate_mode)
	failures += _check("holds a duration inside the advertised range",
		director._hold_duration >= Director.MIN_HOLD_SECONDS
		and director._hold_duration <= Director.MAX_HOLD_SECONDS)
	failures += _check("a bot target got set on the rig",
		cam.target().resolve() != null)

	print("--- cutting on the idle clock ---")
	var first_shot := director._last_shot_id
	var cuts := 0
	for i in 400:
		cam._process(1.0)
		if director._last_shot_id != first_shot:
			cuts += 1
			first_shot = director._last_shot_id
			if cuts >= 2:
				break
	failures += _check("cut at least twice over the idle clock", cuts >= 2)

	print("--- reacting to a shake ---")
	director._delegate = null  ## forces a clean idle cut before the shake test
	cam._process(0.0)
	director._hold_elapsed = 5.0  ## past the debounce window
	director._hold_duration = 999.0  ## nothing else should cut on its own here
	events.shook.emit(Vector3(300.0, 0.0, -150.0), 40.0, 1.0)
	cam._process(0.0)
	failures += _check("an event shot took over", Director.EVENT_SHOTS.has(director._last_shot_id))
	failures += _check("target moved to the event's own spot",
		(cam.target().resolve() as Vector3).is_equal_approx(Vector3(300.0, 0.0, -150.0)))

	print("--- does not spam-cut a second shake in the same moment ---")
	var reacted_shot := director._last_shot_id
	var reacted_elapsed := director._hold_elapsed
	events.shook.emit(Vector3(-999.0, 0.0, -999.0), 40.0, 1.0)
	cam._process(0.1)
	failures += _check("the immediate second shake did not force another cut",
		director._last_shot_id == reacted_shot and director._hold_elapsed > reacted_elapsed)

	print("--- following a launched meteor ---")
	director._delegate = null  ## forces a clean idle cut before the launch
	cam._process(0.0)
	director._hold_elapsed = 5.0
	director._hold_duration = 999.0  ## nothing else should cut on its own here
	var step := GameConfig.SIMULATION_TICK_SECONDS
	failures += _check("the meteor launches",
		events.trigger(&"meteor", {"x": 200.0, "z": 200.0, "radius": 40.0}))
	cam._process(0.0)
	failures += _check("cuts to Follow the instant it launches",
		director._last_shot_id == &"follow")
	var first_position: Variant = cam.target().resolve()
	failures += _check("target resolves to the rock's live position, not null",
		first_position != null)

	events.advance(step)
	cam._process(step)
	events.advance(step)
	cam._process(step)
	var second_position: Variant = cam.target().resolve()
	failures += _check("keeps tracking the rock as it falls, not a snapshot",
		second_position != null
		and not (second_position as Vector3).is_equal_approx(first_position as Vector3))

	var steps := 2
	while steps < 200 and not events.last_description.contains("killed"):
		events.advance(step)
		cam._process(step)
		steps += 1
	failures += _check("it actually lands rather than hanging in the air", steps < 200)
	failures += _check("impact hands off cleanly to the event shot",
		Director.EVENT_SHOTS.has(director._last_shot_id))

	print("--- switching away and back starts clean ---")
	cam.set_mode(&"free")
	cam._process(0.0)
	events.shook.emit(Vector3(1.0, 0.0, 1.0), 40.0, 1.0)  ## nobody is watching
	cam.set_mode(&"director")
	failures += _check("re-entering does not resume the last delegate", director._delegate == null)
	cam._process(0.0)
	failures += _check("and does not react to the stale shake either",
		not (cam.target().resolve() as Vector3).is_equal_approx(Vector3(1.0, 0.0, 1.0)))

	print("--- input passthrough and mouse capture mirror the delegate ---")
	var delegate_after: CameraMode = director._delegate
	failures += _check("wants the mouse only if the current shot does",
		director.wants_mouse_capture() == delegate_after.wants_mouse_capture())

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
