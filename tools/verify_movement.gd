extends Node
## Checks that the simulation tick actually moves bots, keeps them on the
## island, and stays deterministic. Also measures what one tick costs at every
## target scale, which is the number the whole design has to live inside.

const TICKS := 200


func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var world: World = main.get_node("World")
	var bots: BotManager = main.get_node("Bots")
	var step: float = GameConfig.SIMULATION_TICK_SECONDS

	print("--- tick cost, averaged over %d ticks ---" % TICKS)
	for n in [100, 1000, 5000, 10000]:
		main.rebuild(GameConfig.DEFAULT_MAP_SEED, n)
		var t0 := Time.get_ticks_usec()
		for t in TICKS:
			bots.tick(step, t)
		var us := float(Time.get_ticks_usec() - t0) / TICKS
		var budget := 100.0 * us / (step * 1000000.0)
		print("  %6d bots : %6.3f ms/tick, %5.1f%% of the 20 Hz tick budget"
			% [n, us / 1000.0, budget])

	print("--- behaviour at %d bots after %d ticks (%.1f s) ---"
		% [bots.count, TICKS, TICKS * step])

	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	var start_x := bots.pos_x.duplicate()
	var start_z := bots.pos_z.duplicate()
	for t in TICKS:
		bots.tick(step, t)

	var moved := 0
	var over_water := 0
	var off_map := 0
	var bad_state := 0
	var moving := 0
	var travelled := 0.0
	var limit := world.half_extent()
	for i in bots.count:
		var dx: float = bots.pos_x[i] - start_x[i]
		var dz: float = bots.pos_z[i] - start_z[i]
		var distance := sqrt(dx * dx + dz * dz)
		travelled += distance
		if distance > 0.5:
			moved += 1
		if world.get_height(bots.pos_x[i], bots.pos_z[i]) <= GameConfig.WATER_LEVEL:
			over_water += 1
		if absf(bots.pos_x[i]) > limit or absf(bots.pos_z[i]) > limit:
			off_map += 1
		if bots.state[i] != BotManager.State.IDLE and bots.state[i] != BotManager.State.MOVING:
			bad_state += 1
		if bots.state[i] == BotManager.State.MOVING:
			moving += 1

	print("  moved          : %d of %d, average %.1f m travelled"
		% [moved, bots.count, travelled / bots.count])
	print("  moving now     : %d, idle %d" % [moving, bots.count - moving])
	print("  over water     : %d (%.2f%%)" % [over_water, 100.0 * over_water / bots.count])
	failures += _check("almost every bot has moved", moved > bots.count * 0.95)
	failures += _check("nobody left the map (%d)" % off_map, off_map == 0)
	failures += _check("only IDLE and MOVING are used (%d others)" % bad_state, bad_state == 0)
	failures += _check("under 1%% of bots stand over water", over_water < bots.count * 0.01)
	failures += _check("bots are spread across both states", moving > 0 and moving < bots.count)

	# Determinism: same seed, same number of ticks, same result.
	var after_x := bots.pos_x.duplicate()
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	for t in TICKS:
		bots.tick(step, t)
	failures += _check("same seed and ticks reproduce the run exactly", after_x == bots.pos_x)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
