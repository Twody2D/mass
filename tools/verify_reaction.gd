extends Node
## Checks how the crowd reacts to a blast: that a thrown bot actually flies and
## comes down where the ground is, that a frightened one runs away from what
## frightened it and runs faster than it walks, that the guards refuse nonsense,
## and that none of it costs a tick budget at ten thousand.
##
## Also checks the camera shake, because it is the third half of the same
## feature and there is nowhere better for it to live.

const BOTS := 2000
const BLAST := 60.0
const MAX_STEPS := 200
## Long enough for anything thrown at these speeds to be back on the ground.
const FLIGHT_STEPS := 80


func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var world: World = main.get_node("World")
	var bots: BotManager = main.get_node("Bots")
	var events: EventManager = main.get_node("Events")
	var camera: FreeCamera = main.get_node("Camera3D")
	var step := GameConfig.SIMULATION_TICK_SECONDS

	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)

	print("--- being thrown ---")
	var who := 0
	var from_x := bots.pos_x[who] - 5.0
	var from_z := bots.pos_z[who]
	var start_x := bots.pos_x[who]
	var start_z := bots.pos_z[who]
	var ground_at_start := world.get_height(start_x, start_z)

	failures += _check("a live bot can be thrown", bots.fling(who, from_x, from_z, 20.0, 14.0))
	failures += _check("and is airborne straight away", bots.state[who] == BotManager.State.FLUNG)

	# One tick is enough to leave the ground; the arc is checked over the rest.
	bots.tick(step, 0)
	failures += _check("it leaves the ground (%.2f m up)" % (bots.pos_y[who] - ground_at_start),
		bots.pos_y[who] > ground_at_start)

	var peak := bots.pos_y[who]
	var landed := false
	var flew := 1
	while flew < FLIGHT_STEPS:
		bots.tick(step, flew)
		peak = maxf(peak, bots.pos_y[who])
		flew += 1
		if bots.state[who] != BotManager.State.FLUNG:
			landed = true
			break
	print("  apex           : %.2f m above where it started" % (peak - ground_at_start))
	print("  airborne for   : %.2f s" % (flew * step))
	failures += _check("it comes down again", landed)
	failures += _check("it rose before it fell", peak > ground_at_start + 1.0)

	var moved := Vector2(bots.pos_x[who] - start_x, bots.pos_z[who] - start_z).length()
	print("  thrown         : %.1f m" % moved)
	failures += _check("it was thrown some distance (%.1f m)" % moved, moved > 5.0)
	failures += _check("it was thrown away from the blast, not towards it",
		bots.pos_x[who] > start_x)
	failures += _check("it ends up standing on the ground",
		absf(bots.pos_y[who] - world.get_height(bots.pos_x[who], bots.pos_z[who])) < 0.01)
	failures += _check("and stops moving when it lands",
		bots.vel_x[who] == 0.0 and bots.vel_z[who] == 0.0 and bots.air_vy[who] == 0.0)
	failures += _check("it is alive and idle afterwards",
		bots.alive[who] == 1 and bots.state[who] == BotManager.State.IDLE)

	print("--- thrown into the sea ---")
	# Straight out to sea from the middle of the map, hard enough to clear the
	# island: the shore is solid for anyone walking, but not for anyone flying.
	var drowned := -1
	for i in bots.count:
		if bots.alive[i] == 1:
			drowned = i
			break
	var living_before := bots.alive_count
	bots.fling(drowned, 0.0, 0.0, 600.0, 4.0)
	var sank := 0
	while sank < FLIGHT_STEPS and bots.state[drowned] == BotManager.State.FLUNG:
		bots.tick(step, sank)
		sank += 1
	failures += _check("a knight thrown into the water drowns", bots.alive[drowned] == 0)
	failures += _check("and the count follows it down", bots.alive_count == living_before - 1)

	print("--- the guards ---")
	failures += _check("throwing a corpse does nothing",
		not bots.fling(drowned, 0.0, 0.0, 10.0, 10.0))
	failures += _check("scaring a corpse does nothing",
		not bots.scare(drowned, 0.0, 0.0, 10.0))
	failures += _check("a bad index is refused", not bots.fling(bots.count, 0.0, 0.0, 1.0, 1.0))
	failures += _check("a negative speed is refused", not bots.fling(1, 0.0, 0.0, -1.0, 1.0))
	failures += _check("a zero flee distance is refused", not bots.scare(1, 0.0, 0.0, 0.0))
	failures += _check("a bad index is refused by scare too",
		not bots.scare(-1, 0.0, 0.0, 10.0))

	print("--- running away ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	var runner := 0
	var scare_x := bots.pos_x[runner] - 1.0
	var scare_z := bots.pos_z[runner]
	var before := Vector2(bots.pos_x[runner] - scare_x, bots.pos_z[runner] - scare_z).length()
	failures += _check("a bot can be frightened", bots.scare(runner, scare_x, scare_z, 40.0))
	failures += _check("it is fleeing", bots.state[runner] == BotManager.State.FLEEING)

	var t := 0
	while t < 10:
		bots.tick(step, t)
		t += 1
	var after := Vector2(bots.pos_x[runner] - scare_x, bots.pos_z[runner] - scare_z).length()
	print("  distance       : %.1f m -> %.1f m" % [before, after])
	failures += _check("it is further away than it was", after > before + 1.0)

	# Same crowd, same seed, one bot walking and one running: panic has to be
	# visibly faster or it does not read from altitude.
	var walker := 1
	bots.state[walker] = BotManager.State.MOVING
	bots.target_x[walker] = bots.pos_x[walker] + 200.0
	bots.target_z[walker] = bots.pos_z[walker]
	var walker_from := bots.pos_x[walker]
	bots.scare(2, bots.pos_x[2] + 1.0, bots.pos_z[2], 200.0)
	var runner_from := bots.pos_x[2]
	t = 0
	while t < 20:
		bots.tick(step, t)
		t += 1
	var walked := absf(bots.pos_x[walker] - walker_from)
	var ran := absf(bots.pos_x[2] - runner_from)
	print("  walked %.1f m, ran %.1f m in the same second" % [walked, ran])
	failures += _check("panic is faster than a walk", ran > walked * 1.5)

	print("--- separation ignores anything in the air ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	bots.tick(step, 0)
	# Park two bots on top of each other, then throw one of them. The one left
	# standing must not be pushed by a knight that is no longer there.
	var a := 0
	var b := 1
	bots.pos_x[b] = bots.pos_x[a]
	bots.pos_z[b] = bots.pos_z[a]
	bots.pos_y[b] = bots.pos_y[a]
	bots.fling(b, bots.pos_x[a], bots.pos_z[a], 0.0, 30.0)
	var settled_x := bots.pos_x[a]
	var settled_z := bots.pos_z[a]
	bots.tick(step, 1)
	var shoved := Vector2(bots.pos_x[a] - settled_x, bots.pos_z[a] - settled_z).length()
	print("  pushed         : %.4f m by a knight overhead" % shoved)
	failures += _check("nobody is shoved by a shadow (%.4f m)" % shoved, shoved < 0.01)

	print("--- camera shake ---")
	camera.global_position = Vector3(0.0, 50.0, 0.0)
	failures += _check("the camera starts still", not camera.is_shaking())
	camera.shake_from(Vector3.ZERO, BLAST, 1.0)
	failures += _check("a blast underfoot shakes it", camera.is_shaking())
	var frames := 0
	while frames < 400 and camera.is_shaking():
		await get_tree().process_frame
		frames += 1
	print("  settled after  : %d frames" % frames)
	failures += _check("and it settles again", not camera.is_shaking())
	failures += _check("the roll is back to level", absf(camera.rotation.z) < 0.0001)

	camera.shake_from(Vector3(5000.0, 0.0, 5000.0), BLAST, 1.0)
	failures += _check("a blast on the far side is not felt", not camera.is_shaking())
	camera.shake_from(Vector3.ZERO, 0.0, 1.0)
	failures += _check("a zero radius is refused", not camera.is_shaking())

	print("--- a whole meteor, at ten thousand ---")
	# Twice, and the second one is the number that matters. The first meteor in
	# a process also pays for the shared smoke blobs, the shaders and the script
	# loads behind them, none of which happen again.
	var impact_us := 0.0
	for round_index in 2:
		bots.spawn(10000, GameConfig.DEFAULT_MAP_SEED)
		events.reset(GameConfig.DEFAULT_MAP_SEED)
		events.trigger(&"meteor", {"x": bots.pos_x[0], "z": bots.pos_z[0]})
		var steps := 0
		while steps < MAX_STEPS:
			var t0 := Time.get_ticks_usec()
			events.advance(step)
			var us := float(Time.get_ticks_usec() - t0)
			steps += 1
			if events.last_description.contains("killed"):
				impact_us = us
				break
		print("  impact %d       : %.2f ms" % [round_index, impact_us / 1000.0])
	print("  reported       : %s" % events.last_description)
	failures += _check("the impact still fits inside one tick", impact_us < 50000.0)

	var flying := 0
	var fleeing := 0
	for i in bots.count:
		if bots.state[i] == BotManager.State.FLUNG:
			flying += 1
		elif bots.state[i] == BotManager.State.FLEEING:
			fleeing += 1
	print("  in the air     : %d" % flying)
	print("  running        : %d" % fleeing)
	failures += _check("knights were thrown (%d)" % flying, flying > 0)
	failures += _check("and the rest ran (%d)" % fleeing, fleeing > 0)
	failures += _check("the report says so", events.last_description.contains("fleeing"))

	# The tick after an impact is the expensive one: thousands of ballistic bots
	# and thousands more re-steering at once.
	var worst := 0.0
	var total := 0.0
	var ticks := 40
	for i in ticks:
		var t0 := Time.get_ticks_usec()
		bots.tick(step, i)
		var us := float(Time.get_ticks_usec() - t0)
		worst = maxf(worst, us)
		total += us
	print("  tick after     : %.2f ms worst, %.2f ms mean over %d ticks"
		% [worst / 1000.0, total / float(ticks) / 1000.0, ticks])
	failures += _check("the tick still fits its budget", worst < 50000.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
