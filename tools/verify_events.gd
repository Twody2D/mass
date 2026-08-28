extends Node
## Checks the event system: that the registry refuses nonsense, that a meteor
## takes time to arrive and kills exactly who it should when it does, that the
## same seed drops it in the same place, and that the effects clean themselves
## up.

const BOTS := 2000
const BLAST := 60.0
const FRAME_LIMIT := 400
## Enough steps to cover the fall with room to spare, so a stuck meteor shows up
## as a failure rather than as a hang.
const MAX_STEPS := 200


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

	print("--- the fall ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	# A point with somebody standing on it, so the test is not measuring an
	# empty stretch of beach.
	var at := Vector2(bots.pos_x[0], bots.pos_z[0])
	var kill_radius := BLAST * MeteorEvent.KILL_SHARE

	# What should happen, worked out the slow way over every bot. This is the
	# O(N) check the grid exists to avoid at run time; in a test it is the point.
	var should_die := 0
	for i in bots.count:
		if Vector2(bots.pos_x[i] - at.x, bots.pos_z[i] - at.y).length() <= kill_radius:
			should_die += 1
	print("  inside the kill radius : %d" % should_die)

	var living_before := bots.alive_count
	var ok := events.trigger(&"meteor", {"x": at.x, "z": at.y, "radius": BLAST})
	failures += _check("the meteor fired", ok)
	print("  announced      : %s" % events.last_description)
	failures += _check("it announces itself first",
		events.last_description.contains("incoming"))
	failures += _check("nobody has died yet", bots.alive_count == living_before)

	var falling := 0
	for child in events.get_children():
		if child is MeteorProjectile:
			falling += 1
	failures += _check("a rock is in the air (%d)" % falling, falling == 1)

	# Only the events are advanced, not the crowd: nobody moves during the fall,
	# so the casualty list can be checked against positions measured before it.
	var step := GameConfig.SIMULATION_TICK_SECONDS
	var height_before := _rock_height(events)
	events.advance(step)
	events.advance(step)
	failures += _check("it is coming down", _rock_height(events) < height_before)
	failures += _check("still nobody dead", bots.alive_count == living_before)

	# Waiting on the report rather than on a body count: a meteor that lands on
	# an empty field still lands, and the test must not hang because of it.
	var steps := 2
	while steps < MAX_STEPS and not events.last_description.contains("killed"):
		events.advance(step)
		steps += 1
	var fell_for := steps * step
	print("  landed after   : %.2f s of simulation time" % fell_for)
	failures += _check("it lands rather than hanging in the air", steps < MAX_STEPS)
	failures += _check("the fall takes about as long as it says",
		absf(fell_for - MeteorProjectile.FALL_SECONDS) < 0.3)

	print("--- the impact ---")
	print("  description    : %s" % events.last_description)
	failures += _check("it reported what it did", events.last_description.contains("killed"))
	failures += _check("it was recorded", events.last_id == &"meteor")

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
	failures += _check("at least the centre is gone",
		living_before - bots.alive_count >= should_die)

	var flagged := 0
	for i in bots.count:
		if bots.alive[i] == 1:
			flagged += 1
	failures += _check("alive_count matches the flags", flagged == bots.alive_count)

	print("--- what it leaves behind ---")
	var blasts := 0
	var waves := 0
	var clouds := 0
	var ejecta := 0
	var craters := 0
	var rocks := 0
	var burst: GroundEjecta = null
	var crater: Crater = null
	for child in events.get_children():
		if child is BlastEffect:
			blasts += 1
		elif child is ShockwaveEffect:
			waves += 1
		elif child is MushroomCloud:
			clouds += 1
		elif child is GroundEjecta:
			ejecta += 1
			burst = child
		elif child is Crater:
			craters += 1
			crater = child
		elif child is MeteorProjectile and not child.is_queued_for_deletion():
			rocks += 1
	failures += _check("a flash (%d)" % blasts, blasts == 1)
	failures += _check("a shockwave (%d)" % waves, waves == 1)
	failures += _check("a mushroom cloud (%d)" % clouds, clouds == 1)
	failures += _check("a burst of ground ejecta (%d)" % ejecta, ejecta == 1)
	failures += _check("a crater (%d)" % craters, craters == 1)
	failures += _check("and no rock left over (%d)" % rocks, rocks == 0)

	print("--- the crater outlives everything else ---")
	# Not part of the "every effect ends" sweep below on purpose: a crater is
	# the one thing here that never reports itself finished.
	failures += _check("cooling glow starts hot", crater._floor_material.get_shader_parameter("glow") \
		== Crater.GLOW_START)
	for i in 70:
		crater.advance(0.1)
	failures += _check("it cools all the way to nothing",
		is_equal_approx(crater._floor_material.get_shader_parameter("glow"), 0.0))
	failures += _check("but a crater never says it is finished", crater.advance(30.0))
	failures += _check("and is never queued for deletion",
		is_instance_valid(crater) and not crater.is_queued_for_deletion())

	print("--- rings and the crater settle on the water, not the seabed ---")
	# A ground function that always answers deep seabed, so the clamp is the
	# only thing standing between these points and a cliff off the shoreline.
	var deep_ground := func(_x: float, _z: float) -> float: return -50.0
	var ring_origin := Vector3(0.0, 5.0, 0.0)
	var test_water := 0.0

	var test_wave := ShockwaveEffect.create(ring_origin, 40.0, Color.WHITE, deep_ground, test_water)
	var wave_point := test_wave._on_ground(Vector3(40.0, 0.0, 0.0))
	failures += _check("the shockwave never dips below the water line",
		wave_point.y + ring_origin.y >= test_water - 0.01)
	test_wave.queue_free()

	var test_crater := Crater.create(ring_origin, 100.0, events.rng(), deep_ground, test_water)
	var crater_point: Vector3 = test_crater._ground_point(
		test_crater._radius, 0.0, Crater.LIFT, deep_ground)
	failures += _check("the crater rim never dips below the water line",
		crater_point.y + ring_origin.y >= test_water - 0.01)
	test_crater.queue_free()

	print("--- ground ejecta settles on the terrain ---")
	# Stepped short of its own DURATION on purpose: advance() frees itself once
	# that runs out, and the forced-completion sweep below still needs a live
	# instance to call advance(30.0) on.
	for i in 18:
		burst.advance(0.1)
	var settled := 0
	for i in GroundEjecta.CHUNK_COUNT:
		if burst._landed[i] == 1:
			settled += 1
	failures += _check("every chunk found the ground (%d of %d)" % [settled, GroundEjecta.CHUNK_COUNT],
		settled == GroundEjecta.CHUNK_COUNT)

	# Run each one past the end of its own life rather than sitting through
	# eleven seconds of cloud in real time.
	var ended := 0
	var effects := 0
	for child in events.get_children():
		if child is BlastEffect or child is ShockwaveEffect or child is MushroomCloud \
				or child is GroundEjecta:
			effects += 1
			if not child.advance(30.0):
				ended += 1
	failures += _check("every effect ends when its time is up (%d of %d)" % [ended, effects],
		ended == effects and effects == 4)

	var frames := 0
	while frames < FRAME_LIMIT and _leftovers(events) > 0:
		await get_tree().process_frame
		frames += 1
	failures += _check("both free themselves (%d frames)" % frames, _leftovers(events) == 0)

	# Nothing is left to advance, so a further step must be harmless.
	events.advance(step)
	failures += _check("advancing an empty manager is fine", true)

	print("--- a bad radius ---")
	failures += _check("a zero radius is refused",
		not events.trigger(&"meteor", {"x": at.x, "z": at.y, "radius": 0.0}))

	print("--- determinism ---")
	var first := _drop_and_land(bots, events, step)
	var second := _drop_and_land(bots, events, step)
	print("  same seed      : %s | %s" % [first, second])
	failures += _check("the same seed lands the same meteor", first == second)

	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED + 1)
	events.trigger(&"meteor")
	var third := _land(bots, events, step)
	failures += _check("a different seed lands it elsewhere", first != third)

	print("--- cost at ten thousand ---")
	bots.spawn(10000, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	# Full size, because the quarter of the map it covers is what it really costs.
	events.trigger(&"meteor", {"x": bots.pos_x[0], "z": bots.pos_z[0]})
	# Every step but the last is a rock falling; the last one is the impact,
	# which is the only one that touches the crowd.
	var carry := PackedFloat32Array()
	var impact := 0.0
	for i in MAX_STEPS:
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		var us := float(Time.get_ticks_usec() - t0)
		if events.last_description.contains("killed"):
			impact = us
			break
		carry.append(us)
	print("  falling        : %.3f ms median, %.3f ms worst per tick"
		% [_median_ms(carry), _worst_ms(carry)])
	print("  impact         : %.3f ms, %s" % [impact / 1000.0, events.last_description])
	# Loose bounds: a long check run heats the laptop and every later measurement
	# reads high. See tools/profile_tick.gd for numbers that mean something.
	failures += _check("carrying a meteor costs almost nothing (%.3f ms)" % _median_ms(carry),
		_median_ms(carry) < 5.0)
	failures += _check("the impact has not gone quadratic (%.2f ms)" % (impact / 1000.0),
		impact < 200000.0)

	failures += _check("the world survived it", world.land_fraction() > 0.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Height of the rock that is currently in the air, or -1 if there is none.
func _rock_height(events: EventManager) -> float:
	for child in events.get_children():
		if child is MeteorProjectile:
			return (child as MeteorProjectile).position.y
	return -1.0


func _leftovers(events: EventManager) -> int:
	var n := 0
	for child in events.get_children():
		if (child is BlastEffect or child is ShockwaveEffect or child is MushroomCloud
				or child is GroundEjecta) and not child.is_queued_for_deletion():
			n += 1
	return n


## A fresh crowd, a fresh seed and one meteor carried all the way down. Returns
## the line it reported, which covers both where it landed and what it did.
func _drop_and_land(bots: BotManager, events: EventManager, step: float) -> String:
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	events.trigger(&"meteor")
	return _land(bots, events, step)


func _land(_bots: BotManager, events: EventManager, step: float) -> String:
	var steps := 0
	while steps < MAX_STEPS and not events.last_description.contains("killed"):
		events.advance(step)
		steps += 1
	return events.last_description



## Median of a set of microsecond samples, in milliseconds.
##
## Never the mean and never the worst. The same deterministic tick measures 15 ms
## on one run of this tool and 43 ms on the next, with the crowd in a
## bit-identical state, because the machine has other things to do. A worst-case
## assertion measures the operating system; a median measures the code.
func _median_ms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sorted := samples.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var middle := sorted.size() / 2
	return sorted[middle] / 1000.0


func _worst_ms(samples: PackedFloat32Array) -> float:
	var top := 0.0
	for v in samples:
		top = maxf(top, v)
	return top / 1000.0


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
