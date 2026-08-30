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

## Subdivisions across the ocean plane. ocean.gdshader displaces VERTEX.y to
## fake waves; a flat, unsubdivided PlaneMesh has no vertices in the middle
## for that displacement to move, only the four corners. Built once at
## generate() and animated entirely by the shader afterwards — no per-frame
## cost on this side at all, unlike the meteor's own ImmediateMesh effects.
const OCEAN_SUBDIVISIONS := 96

## How many samples random_land_point() tries before settling for the last one.
const LAND_POINT_ATTEMPTS := 8

## Side of one region cell, in metres, for the coarse routing graph
## route_waypoint() searches. Only long-distance sends use it — a Team War
## march, a supply drop's runners — never the everyday wander, which already
## stays local enough not to need it.
const REGION_CELL_SIZE := 64.0

## How far apart the samples are when checking whether a straight line
## between two points crosses water, and how many of them one check will take
## at most, so a full-map diagonal costs a bounded number of height lookups
## instead of growing with the distance.
const LINE_CHECK_STEP := 32.0
const LINE_CHECK_MAX_STEPS := 64

## Four-connected: a region graph does not need diagonals to find a route
## around a bay, and skipping them halves the branching factor of the search.
const NEIGHBOR_OFFSETS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
]

## How far apart, in heightmap cells, the two samples that define "uphill" are
## taken. At four metres a cell this measures the slope over sixty-four metres,
## which is the point: a knight running from the sea should head for the
## mountain, not for the nearest molehill. A one-cell difference would send it
## up every bump, and every bump floods.
const UPHILL_STENCIL := 8

const COLOR_SEABED := Color(0.42, 0.42, 0.36)
const COLOR_SAND := Color(0.85, 0.78, 0.55)
const COLOR_GRASS := Color(0.35, 0.55, 0.28)
const COLOR_HIGHLAND := Color(0.28, 0.42, 0.24)
const COLOR_ROCK := Color(0.48, 0.46, 0.44)

## Where one band of the terrain palette gives way to the next, as a share of
## TERRAIN_HEIGHT. Shares rather than metres, so raising the peak height moves
## the treeline with it instead of turning the whole island to rock.
const SAND_SHARE := 0.042
const GRASS_SHARE := 0.37
const HIGHLAND_SHARE := 0.70

## Emitted after the island has been rebuilt, so dependent systems can respawn.
signal generated(map_seed: int)

## Where the sea is now, in metres. Runtime state rather than a constant,
## because Flood raises it: the ocean plane, what counts as land, what a bot may
## walk on and who drowns all follow from this one number. GameConfig.WATER_LEVEL
## is the level a fresh island starts at, not the level it always has.
##
## Read once per tick by the simulation, never per bot, so making it a variable
## costs nothing in the hot loops.
var water_level := GameConfig.WATER_LEVEL

var _heights := PackedFloat32Array()
var _resolution := 0
var _cell_size := 0.0
var _half_extent := 0.0
## Indices into _heights of every cell a bot may stand on. Precomputed so that
## random_land_point() is O(1) and can never loop forever looking for land.
var _land_cells := PackedInt32Array()
## Unit vector pointing uphill at each heightmap cell, split into two arrays for
## the same reason the bots are: packed floats, no per-cell object. Zero where
## the ground is flat enough that no direction is better than another.
var _uphill_x := PackedFloat32Array()
var _uphill_z := PackedFloat32Array()

## Coarse walkability grid for route_waypoint(), independent of the heightmap
## resolution: a region is a whole shorthand for "roughly walkable here", not
## a terrain sample.
var _region_resolution := 0
var _region_cell := 0.0
var _region_walkable := PackedByteArray()

var _terrain: MeshInstance3D
var _ocean: MeshInstance3D

## Where the volcano's crater sits, in world metres. Deterministic from the
## seed alone (IslandGenerator.volcano_center()) — stored here rather than
## recomputed by every caller so VolcanoEvent can ask for it without knowing
## anything about how the terrain got its shape.
var _volcano_center := Vector2.ZERO


## Not generated in _ready on purpose: Main decides when the island is built, so
## that bots are never placed before there is ground under them.
##
## Rebuilds the island from a seed. The same seed always produces the same map.
func generate(map_seed: int) -> void:
	# Before anything reads it: a rebuild puts the sea back where it started, or
	# a restart after a flood would drown the new island as it was born.
	water_level = GameConfig.WATER_LEVEL
	_resolution = GameConfig.HEIGHTMAP_RESOLUTION
	_half_extent = GameConfig.MAP_SIZE * 0.5
	_cell_size = GameConfig.MAP_SIZE / float(_resolution - 1)
	_region_resolution = maxi(4, int(round(GameConfig.MAP_SIZE / REGION_CELL_SIZE)))
	_region_cell = GameConfig.MAP_SIZE / float(_region_resolution)

	_heights = IslandGenerator.generate_heightmap(
		map_seed, _resolution, GameConfig.TERRAIN_HEIGHT, GameConfig.MAP_SIZE)
	_volcano_center = IslandGenerator.volcano_center(map_seed)
	if _heights.is_empty():
		push_error("World: island generation failed for seed %d." % map_seed)
		return

	_collect_land_cells()
	_build_regions()
	_build_uphill()
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


## Raises or lowers the sea. Moves the plane that is drawn and the line every
## other system measures against, so there is exactly one answer to where the
## water is.
##
## The terrain palette and the land cell list are **not** rebuilt: both cost a
## pass over 65 536 samples, and this is called every tick of a flood. What is
## under the water is hidden by the water, and random_land_point() checks the
## current level itself.
func set_water_level(level: float) -> void:
	water_level = level
	if _ocean != null:
		_ocean.position.y = level


## True where the terrain rises above the water line.
func is_land(x: float, z: float) -> bool:
	return get_height(x, z) > water_level


## Land a bot may stand on: above the water line by enough that it is not
## wading. Distinct from is_land(), which answers the geometric question.
func is_walkable(x: float, z: float) -> bool:
	return get_height(x, z) > water_level + SPAWN_MIN_HEIGHT


## Uniformly random point on walkable land, picked from the precomputed cell
## list so it costs one lookup regardless of how much of the map is ocean.
## The cell list is built once, against the coastline the island was generated
## with. After a flood some of those cells are under water, so a few attempts
## are made before giving up rather than rebuilding the list, which costs a pass
## over the whole heightmap. Bounded on purpose: an unbounded search for land on
## a drowned island is a loop with no end.
func random_land_point(rng: RandomNumberGenerator) -> Vector2:
	if _land_cells.is_empty():
		push_error("World: no walkable land; falling back to the map centre.")
		return Vector2.ZERO
	var line := water_level + SPAWN_MIN_HEIGHT
	var grid_x := 0.0
	var grid_z := 0.0
	for attempt in LAND_POINT_ATTEMPTS:
		var cell := _land_cells[rng.randi_range(0, _land_cells.size() - 1)]
		@warning_ignore("integer_division")
		var gz := cell / _resolution
		var gx := cell % _resolution
		grid_x = -_half_extent + gx * _cell_size
		grid_z = -_half_extent + gz * _cell_size
		if _heights[cell] <= line:
			# Drowned since the island was built. Try somewhere else.
			continue
		# Jitter around the sample so points are not visibly snapped to the grid.
		var x := grid_x + (rng.randf() - 0.5) * _cell_size
		var z := grid_z + (rng.randf() - 0.5) * _cell_size
		# Jitter can cross into a neighbouring water cell near the coast; the
		# grid sample itself is land, so fall back to it.
		if get_height(x, z) <= water_level:
			return Vector2(grid_x, grid_z)
		return Vector2(x, z)
	# Everything sampled was under water. The last grid point is still the best
	# answer available, and the caller gets a point rather than a crash.
	return Vector2(grid_x, grid_z)


## Which way is up from here, as a unit vector on the ground plane, or zero
## where the ground is flat. Precomputed at generation, so asking costs one
## lookup: a flood asks this for thousands of bots several times a second, and
## sampling the terrain a few times per bot instead would cost more than the
## flood does.
##
## This exists because "run inland" is not the same thing as "run uphill". The
## radial falloff that makes the island an island is flat inside a fifth of its
## radius, so the middle of the map is pure noise and can perfectly well be a
## lake — which is exactly where bots ran when the direction was guessed from
## the centre instead of measured from the ground.
func uphill(x: float, z: float) -> Vector2:
	if _uphill_x.is_empty():
		return Vector2.ZERO
	var last := _resolution - 1
	var gx := clampi(int(round((x + _half_extent) / _cell_size)), 0, last)
	var gz := clampi(int(round((z + _half_extent) / _cell_size)), 0, last)
	var cell := gz * _resolution + gx
	return Vector2(_uphill_x[cell], _uphill_z[cell])


## Where a long-distance send should aim right now: the destination itself
## when a straight line there does not cross water, otherwise the next region
## along the shortest region-to-region route. Meant for events that re-aim
## periodically (WarBattle regroups every few seconds) — a straggler that
## makes no direct progress this call is simply closer next time, without
## this or the bot needing to remember a path.
##
## Not real pathfinding: regions are a coarse grid, so a strait narrower than
## one region can still fool the straight-line check, and the "next region"
## returned is a rough waypoint, not a precise route. Good enough to stop a
## march from cutting across open water; the everyday wander stays local and
## never calls this.
func route_waypoint(from: Vector2, to: Vector2) -> Vector2:
	if _line_clear(from, to):
		return to
	var path := _region_path(_region_of(from.x, from.y), _region_of(to.x, to.y))
	if path.size() < 2:
		# No route at all, or already in the destination's region: nothing
		# closer to offer than the destination itself.
		return to
	return _region_centroid(path[1])


## How far a world position may travel from the origin before leaving the map.
func half_extent() -> float:
	return _half_extent


## Where the volcano's crater sits, in world metres. The real summit — the
## rim, not this point — is a ring VolcanoEvent already knows the radius of
## (IslandGenerator.VOLCANO_CRATER_RADIUS), not a single spot, so this hands
## back the centre of that ring rather than a height.
func volcano_center() -> Vector2:
	return _volcano_center


## Fraction of the map that is walkable land. Used by tooling and diagnostics.
func land_fraction() -> float:
	if _heights.is_empty():
		return 0.0
	return float(_land_cells.size()) / float(_heights.size())


## One pass over the heightmap, taking the slope across UPHILL_STENCIL cells
## rather than across one. The wide stencil is the smoothing: it costs nothing
## extra and it ignores anything smaller than the feature a bot should be
## running towards.
func _build_uphill() -> void:
	var r := _resolution
	_uphill_x.resize(r * r)
	_uphill_z.resize(r * r)
	var last := r - 1
	for gz in r:
		var row := gz * r
		var row_back := maxi(gz - UPHILL_STENCIL, 0) * r
		var row_ahead := mini(gz + UPHILL_STENCIL, last) * r
		for gx in r:
			var i := row + gx
			var behind := _heights[row + maxi(gx - UPHILL_STENCIL, 0)]
			var ahead := _heights[row + mini(gx + UPHILL_STENCIL, last)]
			var dx := ahead - behind
			var dz := _heights[row_ahead + gx] - _heights[row_back + gx]
			var length := sqrt(dx * dx + dz * dz)
			if length < 0.0001:
				# Flat. Saying so is more useful than inventing a direction the
				# caller cannot tell apart from a measured one.
				_uphill_x[i] = 0.0
				_uphill_z[i] = 0.0
				continue
			_uphill_x[i] = dx / length
			_uphill_z[i] = dz / length


func _collect_land_cells() -> void:
	_land_cells = PackedInt32Array()
	for i in _heights.size():
		if _heights[i] > SPAWN_MIN_HEIGHT:
			_land_cells.push_back(i)


## One pass over the coarse grid, sampling each region's centre the same way
## random_land_point() samples the fine one. Region walkability is a rough
## label for routing, not the precise "may a bot stand here" answer
## is_walkable() gives — no bot is ever placed by this.
func _build_regions() -> void:
	var r := _region_resolution
	_region_walkable.resize(r * r)
	var line := water_level + SPAWN_MIN_HEIGHT
	for gz in r:
		var cz := -_half_extent + (gz + 0.5) * _region_cell
		var row := gz * r
		for gx in r:
			var cx := -_half_extent + (gx + 0.5) * _region_cell
			_region_walkable[row + gx] = 1 if get_height(cx, cz) > line else 0


func _region_of(x: float, z: float) -> int:
	var gx := clampi(int((x + _half_extent) / _region_cell), 0, _region_resolution - 1)
	var gz := clampi(int((z + _half_extent) / _region_cell), 0, _region_resolution - 1)
	return gz * _region_resolution + gx


func _region_centroid(cell: int) -> Vector2:
	var r := _region_resolution
	var gx := cell % r
	@warning_ignore("integer_division")
	var gz := cell / r
	return Vector2(
		-_half_extent + (gx + 0.5) * _region_cell,
		-_half_extent + (gz + 0.5) * _region_cell)


## Whether a straight line from `from` to `to` ever leaves walkable land,
## sampled rather than swept exactly: cheap, and a region is coarse enough
## that exactness would be false precision anyway.
func _line_clear(from: Vector2, to: Vector2) -> bool:
	var distance := from.distance_to(to)
	if distance < 0.001:
		return true
	var steps := clampi(int(ceil(distance / LINE_CHECK_STEP)), 1, LINE_CHECK_MAX_STEPS)
	for i in steps + 1:
		var p := from.lerp(to, float(i) / steps)
		if not is_walkable(p.x, p.y):
			return false
	return true


## Breadth-first shortest hop path over the region grid, walkable cells only.
## Two hundred and fifty-odd nodes at the default REGION_CELL_SIZE: cheap
## enough to search fresh on every call rather than caching a route that
## would go stale the moment the destination — a team's centroid, most of the
## time — moves.
##
## Empty when there is no path, including "already the same region". Both
## ends are allowed through even if their own region reads as water: a
## region is only one coarse sample, and a real point near the coast — most
## points bots actually stand on or aim at — can be walkable while the
## centre that labelled its region is not. Only cells crossed in between have
## to be walkable.
func _region_path(from_cell: int, to_cell: int) -> PackedInt32Array:
	if from_cell == to_cell:
		return PackedInt32Array()

	var r := _region_resolution
	var total := r * r
	var visited := PackedByteArray()
	visited.resize(total)
	var parent := PackedInt32Array()
	parent.resize(total)
	parent.fill(-1)

	var queue := PackedInt32Array()
	queue.push_back(from_cell)
	visited[from_cell] = 1
	var head := 0
	var found := false
	while head < queue.size():
		var current := queue[head]
		head += 1
		if current == to_cell:
			found = true
			break
		var gx := current % r
		@warning_ignore("integer_division")
		var gz := current / r
		for offset: Vector2i in NEIGHBOR_OFFSETS:
			var nx := gx + offset.x
			var nz := gz + offset.y
			if nx < 0 or nx >= r or nz < 0 or nz >= r:
				continue
			var next := nz * r + nx
			if visited[next] == 1:
				continue
			# Every cell crossed has to be walkable, except the destination
			# itself — its own region can read as water for the same reason
			# the start's can, and refusing it there would strand every send
			# whose target sits near a shoreline.
			if _region_walkable[next] == 0 and next != to_cell:
				continue
			visited[next] = 1
			parent[next] = current
			queue.push_back(next)

	if not found:
		return PackedInt32Array()

	var path := PackedInt32Array()
	var step := to_cell
	while step != -1:
		path.push_back(step)
		step = parent[step]
	path.reverse()
	return path


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
		# Already built, but generate() has just put the sea back to its starting
		# level and the plane has to follow it.
		_ocean.position.y = water_level
		return
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * GameConfig.MAP_SIZE * OCEAN_OVERSIZE
	plane.subdivide_width = OCEAN_SUBDIVISIONS
	plane.subdivide_depth = OCEAN_SUBDIVISIONS

	var material := ShaderMaterial.new()
	material.shader = load("res://assets/materials/ocean.gdshader")
	plane.material = material

	_ocean = MeshInstance3D.new()
	_ocean.name = "Ocean"
	_ocean.mesh = plane
	add_child(_ocean)
	_ocean.position.y = water_level


## Palette entries are authored in sRGB, the way colours are picked by eye, but
## vertex colours reach the shader as linear values. StandardMaterial3D converts
## albedo_color for us; ARRAY_COLOR gets no such treatment, so without this the
## terrain renders washed out while the ocean looks correct.
func _terrain_color(height: float) -> Color:
	return _ramp_color(height).srgb_to_linear()


## Baked into the mesh at generation, against the starting coastline. A flood
## does not repaint the terrain, because the terrain it would repaint is under
## the sea by then.
func _ramp_color(height: float) -> Color:
	if height <= water_level:
		return COLOR_SEABED
	var peak := GameConfig.TERRAIN_HEIGHT
	var sand_top := peak * SAND_SHARE
	var grass_top := peak * GRASS_SHARE
	var highland_top := peak * HIGHLAND_SHARE
	if height < sand_top:
		return COLOR_SAND.lerp(COLOR_GRASS, height / sand_top)
	if height < grass_top:
		return COLOR_GRASS.lerp(COLOR_HIGHLAND, (height - sand_top) / (grass_top - sand_top))
	if height < highland_top:
		return COLOR_HIGHLAND.lerp(COLOR_ROCK,
			(height - grass_top) / (highland_top - grass_top))
	return COLOR_ROCK
