extends Node

func _ready() -> void:
	var res: int = GameConfig.HEIGHTMAP_RESOLUTION
	var peak: float = GameConfig.TERRAIN_HEIGHT
	var map_seed: int = GameConfig.DEFAULT_MAP_SEED

	var t0 := Time.get_ticks_usec()
	var a := IslandGenerator.generate_heightmap(map_seed, res, peak)
	var gen_us := Time.get_ticks_usec() - t0
	var a2 := IslandGenerator.generate_heightmap(map_seed, res, peak)
	var b := IslandGenerator.generate_heightmap(map_seed + 1, res, peak)

	print("heightmap gen  : %.1f ms for %d samples" % [gen_us / 1000.0, a.size()])
	print("determinism    : same seed identical = %s | other seed differs = %s" % [a == a2, a != b])

	var lo := 1e9
	var hi := -1e9
	var land := 0
	for h in a:
		lo = minf(lo, h)
		hi = maxf(hi, h)
		if h > 0.0:
			land += 1
	print("height range   : %.2f .. %.2f m (peak cap %.0f)" % [lo, hi, peak])
	print("land cells     : %d / %d = %.1f%%" % [land, a.size(), 100.0 * land / a.size()])

	var edge_max := -1e9
	for i in res:
		edge_max = maxf(edge_max, a[i])
		edge_max = maxf(edge_max, a[(res - 1) * res + i])
		edge_max = maxf(edge_max, a[i * res])
		edge_max = maxf(edge_max, a[i * res + res - 1])
	print("max edge height: %.2f m (must be <= 0)" % edge_max)

	var t1 := Time.get_ticks_usec()
	var world := World.new()
	add_child(world)
	var build_us := Time.get_ticks_usec() - t1
	print("world build    : %.1f ms (heightmap + mesh + ocean)" % (build_us / 1000.0))
	print("land_fraction  : %.1f%% walkable" % (world.land_fraction() * 100.0))
	print("centre height  : %.2f m" % world.get_height(0.0, 0.0))
	print("corner height  : %.2f m" % world.get_height(-511.0, -511.0))

	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var t2 := Time.get_ticks_usec()
	var in_water := 0
	for i in 10000:
		var p: Vector2 = world.random_land_point(rng)
		if world.get_height(p.x, p.y) <= 0.0:
			in_water += 1
	var pick_us := Time.get_ticks_usec() - t2
	print("10000 spawns   : %.1f ms, %d landed in water" % [pick_us / 1000.0, in_water])

	DirAccess.make_dir_recursive_absolute("res://tools/output")
	var img := Image.create_empty(res, res, false, Image.FORMAT_RGB8)
	for gz in res:
		for gx in res:
			var h: float = a[gz * res + gx]
			img.set_pixel(gx, gz, Color(0.06, 0.22, 0.38) if h <= 0.0 else world._ramp_color(h))
	img.save_png("res://tools/output/heightmap_preview.png")
	print("preview saved")
	get_tree().quit()
