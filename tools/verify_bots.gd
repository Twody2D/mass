extends Node
## Checks the bot data model: that spawning scales, that every bot lands on
## solid ground, that teams come out balanced and that the same seed always
## produces the same crowd.

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var world: World = main.get_node("World")
	var bots: BotManager = main.get_node("Bots")

	print("--- spawn scaling ---")
	for n in [100, 1000, 5000, 10000]:
		var t0 := Time.get_ticks_usec()
		bots.spawn(n, GameConfig.DEFAULT_MAP_SEED)
		var us := Time.get_ticks_usec() - t0
		print("  %6d bots : %6.1f ms spawn, %6.1f KB, %.1f us/bot"
			% [n, us / 1000.0, bots.memory_bytes() / 1024.0, float(us) / n])

	print("--- placement at %d bots ---" % bots.count)
	var in_water := 0
	var off_map := 0
	var limit := world.half_extent()
	for i in bots.count:
		if world.get_height(bots.pos_x[i], bots.pos_z[i]) <= GameConfig.WATER_LEVEL:
			in_water += 1
		if absf(bots.pos_x[i]) > limit or absf(bots.pos_z[i]) > limit:
			off_map += 1
	failures += _check("every bot stands on land (%d in water)" % in_water, in_water == 0)
	failures += _check("every bot is inside the map (%d outside)" % off_map, off_map == 0)

	var counts := PackedInt32Array()
	counts.resize(GameConfig.team_count())
	var idle := 0
	var alive := 0
	for i in bots.count:
		counts[bots.team[i]] += 1
		if bots.state[i] == BotManager.State.IDLE:
			idle += 1
		if bots.alive[i] == 1:
			alive += 1
	print("  teams          : ", counts)
	var most := 0
	var fewest := 0x7fffffff
	for c in counts:
		most = maxi(most, c)
		fewest = mini(fewest, c)
	var spread := most - fewest
	failures += _check("teams balanced within one bot (spread %d)" % spread, spread <= 1)
	failures += _check("all bots start IDLE", idle == bots.count)
	failures += _check("alive_count matches the alive flags", alive == bots.alive_count)

	var lo := 1e9
	var hi := -1e9
	for i in bots.count:
		lo = minf(lo, bots.speed[i])
		hi = maxf(hi, bots.speed[i])
	print("  speed spread   : %.2f .. %.2f m/s (base %.2f)" % [lo, hi, GameConfig.BOT_MOVE_SPEED])
	failures += _check("speeds vary between bots", hi > lo)

	# Determinism: same seed twice, then a different seed.
	var first_x := bots.pos_x.duplicate()
	bots.spawn(bots.count, GameConfig.DEFAULT_MAP_SEED)
	failures += _check("same seed spawns the same crowd", first_x == bots.pos_x)
	bots.spawn(bots.count, GameConfig.DEFAULT_MAP_SEED + 1)
	failures += _check("a different seed spawns a different crowd", first_x != bots.pos_x)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
