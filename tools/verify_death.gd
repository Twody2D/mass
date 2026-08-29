extends Node
## Checks that bots can die: that the bookkeeping stays consistent, that a
## corpse stops taking part in the simulation, and that the renderer keeps
## drawing it lying down instead of making it disappear.

const CULL_FRACTION := 0.3
const TICKS := 20


func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var world: World = main.get_node("World")
	var bots: BotManager = main.get_node("Bots")
	var crowd: CrowdRenderer = main.get_node("Crowd")

	# Spawning is enough: Main keeps the renderer sized to the crowd.
	bots.spawn(1000, GameConfig.DEFAULT_MAP_SEED)

	print("--- one bot ---")
	var before := bots.alive_count
	failures += _check("kill() reports the kill", bots.kill(0))
	failures += _check("the bot is flagged dead", bots.alive[0] == 0)
	failures += _check("the bot is in state DEAD", bots.state[0] == BotManager.State.DEAD)
	failures += _check("alive_count went down by one", bots.alive_count == before - 1)
	failures += _check("killing a corpse changes nothing", not bots.kill(0))
	failures += _check("alive_count did not move again", bots.alive_count == before - 1)
	failures += _check("an index outside the crowd is refused", not bots.kill(bots.count))

	print("--- damage ---")
	var half := GameConfig.BOT_MAX_HEALTH * 0.5
	failures += _check("half health does not kill", not bots.damage(1, half))
	failures += _check("the bot is still alive", bots.alive[1] == 1)
	failures += _check("health went down", is_equal_approx(bots.health[1], half))
	failures += _check("the second half kills", bots.damage(1, half))
	failures += _check("damaging a corpse does nothing", not bots.damage(1, half))
	failures += _check("negative damage is refused", not bots.damage(2, -10.0))
	failures += _check("the target of a refused hit is untouched",
		is_equal_approx(bots.health[2], GameConfig.BOT_MAX_HEALTH))

	print("--- a cull of %d%% ---" % roundi(CULL_FRACTION * 100.0))
	var living := bots.alive_count
	var killed := bots.kill_random(CULL_FRACTION)
	print("  killed         : %d of %d" % [killed, living])
	failures += _check("roughly the requested share died",
		absf(float(killed) / living - CULL_FRACTION) < 0.05)
	failures += _check("alive_count follows the kills", bots.alive_count == living - killed)

	var counted := 0
	var dead_with_health := 0
	var dead_moving := 0
	for i in bots.count:
		if bots.alive[i] == 1:
			counted += 1
			continue
		if bots.health[i] > 0.0:
			dead_with_health += 1
		if bots.vel_x[i] != 0.0 or bots.vel_z[i] != 0.0:
			dead_moving += 1
	failures += _check("alive_count matches the flags (%d)" % counted, counted == bots.alive_count)
	failures += _check("no corpse has health left (%d do)" % dead_with_health, dead_with_health == 0)
	failures += _check("no corpse has velocity (%d do)" % dead_moving, dead_moving == 0)

	print("--- corpses stay out of the way ---")
	var frozen_x := bots.pos_x.duplicate()
	var frozen_z := bots.pos_z.duplicate()
	for t in TICKS:
		bots.tick(GameConfig.SIMULATION_TICK_SECONDS, t)

	var moved_corpses := 0
	var moved_living := 0
	for i in bots.count:
		var still := bots.pos_x[i] == frozen_x[i] and bots.pos_z[i] == frozen_z[i]
		if bots.alive[i] == 0:
			if not still:
				moved_corpses += 1
		elif not still:
			moved_living += 1
	failures += _check("no corpse moved (%d did)" % moved_corpses, moved_corpses == 0)
	failures += _check("the living still move (%d did)" % moved_living, moved_living > 0)

	# The grid is what everything asks about neighbours, so a corpse left in it
	# would go on shoving the living and answering queries for nobody.
	var dead_in_grid := 0
	var sampled := 0
	for i in range(0, bots.count, 37):
		for other in bots.bots_within(bots.pos_x[i], bots.pos_z[i], 12.0):
			sampled += 1
			if bots.alive[other] == 0:
				dead_in_grid += 1
	print("  grid answers   : %d neighbours over %d samples" % [sampled, bots.count / 37])
	failures += _check("no corpse is in the grid (%d are)" % dead_in_grid, dead_in_grid == 0)
	failures += _check("the grid still answers", sampled > 0)

	print("--- the renderer ---")
	crowd.update_transforms()
	# visible_bots() abstracts away which LOD tier a bot currently sits in —
	# this suite cares whether a bot is drawn, not which MultiMesh drew it.
	var visible := crowd.visible_bots()
	var hidden_corpses := 0
	var hidden_living := 0
	for i in bots.count:
		if bots.alive[i] == 0 and visible[i] == 0:
			hidden_corpses += 1
		elif bots.alive[i] == 1 and visible[i] == 0:
			hidden_living += 1
	failures += _check("every corpse is still drawn (%d are not)" % hidden_corpses,
		hidden_corpses == 0)
	failures += _check("every living bot is drawn (%d are not)" % hidden_living, hidden_living == 0)
	failures += _check("instance count still covers every slot, across every tier",
		crowd.rendered_instance_count() == bots.count)

	print("--- falling over, not disappearing ---")
	var faller := -1
	for i in bots.count:
		if bots.alive[i] == 1:
			faller = i
			break
	bots.kill(faller)
	crowd.update_transforms()
	var fresh_up := crowd.local_up_of(faller)
	failures += _check("the instant it dies, a corpse still reads as standing (up.y %.3f)"
		% fresh_up.y, fresh_up.y > 0.9)

	while bots.time_now() - bots.dwell_until[faller] < CrowdRenderer.FALL_SECONDS:
		bots.tick(GameConfig.SIMULATION_TICK_SECONDS, 0)
	crowd.update_transforms()
	var settled_up := crowd.local_up_of(faller)
	failures += _check("once it has had time to fall, it reads as lying down (up.y %.3f)"
		% settled_up.y, absf(settled_up.y) < 0.1)

	print("--- a respawn clears the dead ---")
	bots.spawn(1000, GameConfig.DEFAULT_MAP_SEED)
	failures += _check("everybody is alive again", bots.alive_count == bots.count)
	failures += _check("world is still there", world != null)

	print("--- cost at ten thousand, half of them dead ---")
	bots.spawn(10000, GameConfig.DEFAULT_MAP_SEED)
	var samples := PackedFloat64Array()
	for t in TICKS:
		bots.tick(GameConfig.SIMULATION_TICK_SECONDS, t)
	bots.kill_random(0.5)
	for t in TICKS:
		var t0 := Time.get_ticks_usec()
		bots.tick(GameConfig.SIMULATION_TICK_SECONDS, t)
		samples.append((Time.get_ticks_usec() - t0) / 1000.0)
	samples.sort()
	var median := samples[samples.size() / 2]
	print("  tick median    : %.3f ms with %d of %d alive"
		% [median, bots.alive_count, bots.count])
	failures += _check("half a crowd ticks inside the 50 ms budget", median < 50.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
