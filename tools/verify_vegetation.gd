extends Node
## Checks the forest: that trees land on ordinary ground (never in the sea,
## never above the band they are allowed in), that the same seed grows the
## same forest, and that scattering it costs nothing worth worrying about
## even at ten thousand bots on the same island.

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var world: World = main.get_node("World")
	var vegetation: VegetationRenderer = main.get_node("Vegetation")

	print("--- placement ---")
	print("  trees placed   : %d (of %d requested)"
		% [vegetation.tree_count(), VegetationRenderer.COUNT])
	failures += _check("most of the requested trees actually landed",
		vegetation.tree_count() > VegetationRenderer.COUNT * 0.9)

	var peak := GameConfig.TERRAIN_HEIGHT
	var min_height := peak * VegetationRenderer.MIN_HEIGHT_SHARE
	var max_height := peak * VegetationRenderer.MAX_HEIGHT_SHARE
	var in_water := 0
	var out_of_band := 0
	var positions := vegetation.placed_positions()
	for origin in positions:
		var ground := world.get_height(origin.x, origin.z)
		if ground <= world.water_level:
			in_water += 1
		if ground < min_height - 0.5 or ground > max_height + 0.5:
			out_of_band += 1
	print("  checked        : %d trees" % positions.size())
	failures += _check("no tree stands in the sea (%d do)" % in_water, in_water == 0)
	failures += _check("every tree stayed inside its height band (%d did not)" % out_of_band,
		out_of_band == 0)

	print("--- determinism ---")
	var first := _first_tree_positions(world, vegetation)
	var second := _first_tree_positions(world, vegetation)
	failures += _check("the same seed grows the same forest", first == second)
	var third := _first_tree_positions(world, vegetation, GameConfig.DEFAULT_MAP_SEED + 1)
	failures += _check("a different seed grows a different forest", first != third)

	print("--- cost ---")
	var samples := PackedFloat32Array()
	for i in 5:
		var t0 := Time.get_ticks_usec()
		vegetation.populate(world, GameConfig.DEFAULT_MAP_SEED + i)
		samples.append(float(Time.get_ticks_usec() - t0))
	print("  populate()     : %.2f ms median, %.2f ms worst over %d islands"
		% [_median_ms(samples), _worst_ms(samples), samples.size()])
	failures += _check("scattering the forest is not a real cost (%.2f ms worst)"
		% _worst_ms(samples), _worst_ms(samples) < 200.0)

	print("--- alongside ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	var step := GameConfig.SIMULATION_TICK_SECONDS
	var tick_cost := PackedFloat32Array()
	for i in 30:
		var t0 := Time.get_ticks_usec()
		(main.get_node("Bots") as BotManager).tick(step, i)
		tick_cost.append(float(Time.get_ticks_usec() - t0))
	print("  tick with forest standing: %.3f ms median over %d ticks"
		% [_median_ms(tick_cost), tick_cost.size()])
	failures += _check("the forest adds nothing to the per-tick cost (%.2f ms)"
		% _median_ms(tick_cost), _median_ms(tick_cost) < 50.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Every placed tree position, concatenated into one string — cheap,
## order-sensitive fingerprint of a whole forest.
func _first_tree_positions(world: World, vegetation: VegetationRenderer,
		map_seed: int = GameConfig.DEFAULT_MAP_SEED) -> String:
	vegetation.populate(world, map_seed)
	var text := ""
	for origin in vegetation.placed_positions():
		text += str(origin) + "|"
	return text


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
