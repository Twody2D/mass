extends Node
## Checks the event system: that the registry refuses nonsense, that the meteor
## kills exactly who it should, that the same seed drops it in the same place,
## and that the flash cleans itself up.

const BOTS := 2000
const BLAST := 60.0
const FRAME_LIMIT := 400


func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var world: World = main.get_node("World")
	var bots: BotManager = main.get_node("Bots")
	var events: EventManager = main.get_node("Events")

	print("--- the registry ---")
	print("  known events   : ", events.known())
	failures += _check("the meteor is registered", events.has_event(&"meteor"))
	failures += _check("an unknown event is refused", not events.trigger(&"tsunami"))
	failures += _check("nothing was recorded for it", events.last_id != &"tsunami")

	var bare := EventManager.new()
	add_child(bare)
	failures += _check("an unwired manager refuses to fire", not bare.trigger(&"meteor"))
	bare.queue_free()

	print("--- the meteor ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	# A point with somebody standing on it, so the test is not measuring an
	# empty stretch of beach.
	var at := Vector2(bots.pos_x[0], bots.pos_z[0])
	var kill_radius := BLAST * MeteorEvent.KILL_SHARE

	# What should happen, worked out the slow way over every bot. This is the
	# O(N) check the grid exists to avoid at run time; in a test it is the point.
	var should_die := 0
	var should_survive_untouched := 0
	for i in bots.count:
		var d := Vector2(bots.pos_x[i] - at.x, bots.pos_z[i] - at.y).length()
		if d <= kill_radius:
			should_die += 1
		elif d > BLAST:
			should_survive_untouched += 1
	print("  inside the kill radius : %d" % should_die)

	var living_before := bots.alive_count
	var ok := events.trigger(&"meteor", {"x": at.x, "z": at.y, "radius": BLAST})
	failures += _check("the meteor fired", ok)
	print("  description    : %s" % events.last_description)
	failures += _check("it was recorded", events.last_id == &"meteor")
	failures += _check("it said something", events.last_description != "")

	var survivors_inside := 0
	var hurt_outside := 0
	var hurt_in_the_ring := 0
	for i in bots.count:
		var d := Vector2(bots.pos_x[i] - at.x, bots.pos_z[i] - at.y).length()
		if d <= kill_radius and bots.alive[i] == 1:
			survivors_inside += 1
		elif d > BLAST and bots.health[i] < GameConfig.BOT_MAX_HEALTH:
			hurt_outside += 1
		elif d > kill_radius and d <= BLAST and bots.alive[i] == 1 \
				and bots.health[i] < GameConfig.BOT_MAX_HEALTH:
			hurt_in_the_ring += 1

	failures += _check("everybody at the centre died (%d lived)" % survivors_inside,
		survivors_inside == 0)
	failures += _check("nobody outside the blast was touched (%d was)" % hurt_outside,
		hurt_outside == 0)
	failures += _check("the rim is wounded rather than flattened (%d hurt)" % hurt_in_the_ring,
		hurt_in_the_ring > 0)
	failures += _check("alive_count fell", bots.alive_count < living_before)
	failures += _check("at least the centre is gone",
		living_before - bots.alive_count >= should_die)

	var flagged := 0
	for i in bots.count:
		if bots.alive[i] == 1:
			flagged += 1
	failures += _check("alive_count matches the flags", flagged == bots.alive_count)

	print("--- the flash ---")
	var effects := 0
	for child in events.get_children():
		if child is BlastEffect:
			effects += 1
	failures += _check("a blast was left on screen (%d)" % effects, effects == 1)

	var frames := 0
	while frames < FRAME_LIMIT and _blasts(events) > 0:
		await get_tree().process_frame
		frames += 1
	failures += _check("it frees itself (%d frames)" % frames, _blasts(events) == 0)

	print("--- a bad radius ---")
	failures += _check("a zero radius is refused",
		not events.trigger(&"meteor", {"x": at.x, "z": at.y, "radius": 0.0}))

	print("--- determinism ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	events.trigger(&"meteor")
	var first := events.last_description
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	events.trigger(&"meteor")
	print("  same seed      : %s | %s" % [first, events.last_description])
	failures += _check("the same seed lands the same meteor", first == events.last_description)

	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED + 1)
	events.trigger(&"meteor")
	failures += _check("a different seed lands it elsewhere", first != events.last_description)

	print("--- cost at ten thousand ---")
	bots.spawn(10000, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	var t0 := Time.get_ticks_usec()
	events.trigger(&"meteor", {"x": bots.pos_x[0], "z": bots.pos_z[0], "radius": BLAST})
	var us := Time.get_ticks_usec() - t0
	print("  meteor         : %.3f ms, %s" % [us / 1000.0, events.last_description])
	failures += _check("a meteor costs less than one tick budget", us < 50000)

	failures += _check("the world survived it", world.land_fraction() > 0.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _blasts(events: EventManager) -> int:
	var n := 0
	for child in events.get_children():
		if child is BlastEffect and not child.is_queued_for_deletion():
			n += 1
	return n


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
