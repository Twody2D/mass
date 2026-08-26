class_name World
extends Node3D
## The island: heightmap, terrain mesh, ocean, and the queries other systems run
## against them.
##
## Holds no simulation state. Bots ask it for heights and spawn points; it never
## asks bots anything. Regenerating the world does not touch the bots.

## Land must rise at least this far above the water level before bots may stand
## on it, so nobody spawns ankle-deep in the surf. Distinct from is_land(), which
## answers the geometric question instead of the spawnable one.
const SPAWN_MIN_HEIGHT := 0.6

## The ocean plane is drawn wider than the map so the horizon stays water.
const OCEAN_OVERSIZE := 3.0

const COLOR_SEABED := Color(0.42, 0.42, 0.36)
const COLOR_SAND := Color(0.85, 0.78, 0.55)
const COLOR_GRASS := Color(0.35, 0.55, 0.28)
const COLOR_HIGHLAND := Color(0.28, 0.42, 0.24)
const COLOR_ROCK := Color(0.48, 0.46, 0.44)
const COLOR_OCEAN := Color(0.06, 0.22, 0.38)

const SAND_TOP := 2.5
const GRASS_TOP := 22.0
const HIGHLAND_TOP := 42.0

## Emitted after the island has been rebuilt, so dependent systems can respawn.
signal generated(map_seed: int)

var _heights := PackedFloat32Array()
var _resolution := 0
var _cell_size := 0.0
var _half_extent := 0.0
## Indices into _heights of every cell a bot may stand on. Precomputed so that
## random_land_point() is O(1) and can never loop forever looking for land.
var _land_cells := PackedInt32Array()

var _terrain: MeshInstance3D
var _ocean: MeshInstance3D


## Not generated in _ready on purpose: Main decides when the island is built, so
## that bots are never placed before there is ground under them.
##
## Rebuilds the island from a seed. The same seed always produces the same map.
func generate(map_seed: int) -> void:
	_resolution = GameConfig.HEIGHTMAP_RESOLUTION
	_half_extent = GameConfig.MAP_SIZE * 0.5
	_cell_size = GameConfig.MAP_SIZE / float(_resolution - 1)

	_heights = IslandGenerator.generate_heightmap(
		map_seed, _resolution, GameConfig.TERRAIN_HEIGHT)
	if _heights.is_empty():
		push_error("World: island generation failed for seed %d." % map_seed)
		return

	_collect_land_cells()
	_build_terrain()
	_build_ocean()
	generated.emit(map_seed)


## Terrain height in metres at a world position. Bilinear, O(1), no raycast.
func get_height(x: float, z: float) -> float:
	if _heights.is_empty():
		return 0.0
	var last := _resolution - 1
	var fx := clampf((x + _half_extent) / _cell_size, 0.0, float(last))
	var fz := clampf((z + _half_extent) / _cell_size, 0.0, float(last))
	var x0 := int(fx)
	var z0 := int(fz)
	var x1 := mini(x0 + 1, last)
	var z1 := mini(z0 + 1, last)
	var tx := fx - x0
	var tz := fz - z0
	var row0 := z0 * _resolution
	var row1 := z1 * _resolution
	var top := lerpf(_heights[row0 + x0], _heights[row0 + x1], tx)
	var bottom := lerpf(_heights[row1 + x0], _heights[row1 + x1], tx)
	return lerpf(top, bottom, tz)


## True where the terrain rises above the water line.
func is_land(x: float, z: float) -> bool:
	return get_height(x, z) > GameConfig.WATER_LEVEL


## Uniformly random point on walkable land, picked from the precomputed cell
## list so it costs one lookup regardless of how much of the map is ocean.
func random_land_point(rng: RandomNumberGenerator) -> Vector2:
	if _land_cells.is_empty():
		push_error("World: no walkable land; falling back to the map centre.")
		return Vector2.ZERO
	var cell := _land_cells[rng.randi_range(0, _land_cells.size() - 1)]
	@warning_ignore("integer_division")
	var gz := cell / _resolution
	var gx := cell % _resolution
	var grid_x := -_half_extent + gx * _cell_size
	var grid_z := -_half_extent + gz * _cell_size
	# Jitter around the sample so points are not visibly snapped to the grid.
	var x := grid_x + (rng.randf() - 0.5) * _cell_size
	var z := grid_z + (rng.randf() - 0.5) * _cell_size
	# Jitter can cross into a neighbouring water cell near the coast; the grid
	# sample itself is land by construction, so fall back to it.
	if get_height(x, z) <= GameConfig.WATER_LEVEL:
		return Vector2(grid_x, grid_z)
	return Vector2(x, z)


## How far a world position may travel from the origin before leaving the map.
func half_extent() -> float:
	return _half_extent


## Fraction of the map that is walkable land. Used by tooling and diagnostics.
func land_fraction() -> float:
	if _heights.is_empty():
		return 0.0
	return float(_land_cells.size()) / float(_heights.size())


func _collect_land_cells() -> void:
	_land_cells = PackedInt32Array()
	for i in _heights.size():
		if _heights[i] > SPAWN_MIN_HEIGHT:
			_land_cells.push_back(i)


func _build_terrain() -> void:
	var r := _resolution
	var vertex_count := r * r

	var verts := PackedVector3Array()
	verts.resize(vertex_count)
	var normals := PackedVector3Array()
	normals.resize(vertex_count)
	var colors := PackedColorArray()
	colors.resize(vertex_count)

	var two_cells := 2.0 * _cell_size
	for gz in r:
		var row := gz * r
		var row_up := mini(gz + 1, r - 1) * r
		var row_down := maxi(gz - 1, 0) * r
		for gx in r:
			var i := row + gx
			var height := _heights[i]
			verts[i] = Vector3(
				-_half_extent + gx * _cell_size,
				height,
				-_half_extent + gz * _cell_size)
			colors[i] = _terrain_color(height)
			# Central differences on the heightmap: exact and far cheaper than
			# averaging face normals after the fact.
			var left := _heights[row + maxi(gx - 1, 0)]
			var right := _heights[row + mini(gx + 1, r - 1)]
			var down := _heights[row_down + gx]
			var up := _heights[row_up + gx]
			normals[i] = Vector3(left - right, two_cells, down - up).normalized()

	var quads := (r - 1) * (r - 1)
	var indices := PackedInt32Array()
	indices.resize(quads * 6)
	var w := 0
	for gz in r - 1:
		for gx in r - 1:
			var i := gz * r + gx
			# Clockwise seen from above, which is what Godot treats as front
			# facing; the other winding renders the island inside out and it
			# vanishes under back-face culling.
			indices[w] = i
			indices[w + 1] = i + 1
			indices[w + 2] = i + r
			indices[w + 3] = i + 1
			indices[w + 4] = i + r + 1
			indices[w + 5] = i + r
			w += 6

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	mesh.surface_set_material(0, material)

	if _terrain == null:
		_terrain = MeshInstance3D.new()
		_terrain.name = "Terrain"
		add_child(_terrain)
	_terrain.mesh = mesh


func _build_ocean() -> void:
	if _ocean != null:
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * GameConfig.MAP_SIZE * OCEAN_OVERSIZE

	var material := StandardMaterial3D.new()
	material.albedo_color = COLOR_OCEAN
	material.roughness = 0.15
	material.metallic = 0.2
	plane.material = material

	_ocean = MeshInstance3D.new()
	_ocean.name = "Ocean"
	_ocean.mesh = plane
	_ocean.position.y = GameConfig.WATER_LEVEL
	add_child(_ocean)


## Palette entries are authored in sRGB, the way colours are picked by eye, but
## vertex colours reach the shader as linear values. StandardMaterial3D converts
## albedo_color for us; ARRAY_COLOR gets no such treatment, so without this the
## terrain renders washed out while the ocean looks correct.
func _terrain_color(height: float) -> Color:
	return _ramp_color(height).srgb_to_linear()


func _ramp_color(height: float) -> Color:
	if height <= GameConfig.WATER_LEVEL:
		return COLOR_SEABED
	if height < SAND_TOP:
		return COLOR_SAND.lerp(COLOR_GRASS, height / SAND_TOP)
	if height < GRASS_TOP:
		return COLOR_GRASS.lerp(COLOR_HIGHLAND, (height - SAND_TOP) / (GRASS_TOP - SAND_TOP))
	if height < HIGHLAND_TOP:
		return COLOR_HIGHLAND.lerp(COLOR_ROCK, (height - GRASS_TOP) / (HIGHLAND_TOP - GRASS_TOP))
	return COLOR_ROCK
