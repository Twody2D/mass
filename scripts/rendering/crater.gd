class_name Crater
extends Node3D
## The permanent mark a meteor leaves once everything else about the impact
## has already faded: a flat, dark floor ringed by a raised lip of thrown-up
## earth, glowing for a few seconds and then just sitting there, part of the
## ground, for the rest of the run.
##
## Two meshes, not one, because they behave differently. The floor
## (crater_floor.gdshader) carries the hot centre and never needs to blend
## into anything — it never reaches the crater's own edge. The rim does the
## opposite: it has to melt into the real terrain at its outer edge, so it
## is built with ordinary vertex-alpha transparency instead, fading to
## nothing right where it meets ground this class never touches.
##
## Follows the terrain the same way ShockwaveEffect already does — every
## vertex samples world.get_height() rather than assuming the ground is
## flat under it — for the same reason: a crater sitting flat across a
## sloped impact is half buried on one side and floating on the other, and
## reads as a bug from any camera not looking straight down.
##
## Never frees itself. Everything else about an impact is a moment; this is
## what is left once the moment is over, so it stays adopted (adopt_visual)
## and advance() simply stops doing anything once it has cooled, rather
## than ever reporting itself finished.

## Crater radius as a share of the blast radius — a hole this deep does not
## reach the whole blast's own kill radius. Raised from 0.55 at the owner's
## request: the crater read as too small against the rest of the impact.
const RADIUS_SHARE := 0.75
## Raised from 32 now that the floor is a banded ring rather than one fan
## from a shared centre (see FLOOR_CAP_SHARE): the wider each wedge, the
## more the crater reads as a stamped polygon instead of torn ground.
const SEGMENTS := 40
## Share of the crater radius where the flat floor ends and the climb to
## the rim begins, and where the rim itself peaks.
const RIM_INNER_SHARE := 0.6
const RIM_PEAK_SHARE := 0.82

## Clears the real terrain so the decal never fights it for the same
## pixels — the same reasoning, and the same name, ShockwaveEffect's own
## LIFT already uses.
const LIFT := 0.5
## Rim peak height above LIFT, as a share of the crater radius.
const RIM_HEIGHT_SHARE := 0.05

const COOL_DURATION := 6.0
## Fire strength at the moment of impact, fading to nothing over
## COOL_DURATION — the same "grows then goes" shape MushroomCloud's own
## cooling already uses, just running the other direction from the start.
## Kept under 2: fire_color's own channels already peak near 1, so anything
## much higher just clips every channel to white instead of reading hot.
const GLOW_START := 1.6

## How many angles to check for open water before the floor and rim are
## built, and how many bisection steps to narrow down the safe radius along
## whichever of those angles found any.
const COAST_PROBES := 16
const COAST_STEPS := 8

## Darker and more saturated than the first pass: (0.12, 0.1, 0.08) and
## (0.17, 0.14, 0.1) are so close to neutral that against the map's vivid
## grass and water they read as a flat grey stamp, not scorched ground —
## the "странный круг" the owner kept seeing was this, not the exposure or
## the water crossing those two fixed separately.
const FLOOR_DARK := Color(0.05, 0.035, 0.028)
const FLOOR_LIGHT := Color(0.11, 0.07, 0.05)
const RIM_COLOR := Color(0.22, 0.15, 0.09)
const FIRE_COLOR := Color(1.0, 0.5, 0.15)

## How far each radial edge wobbles from a perfect circle, as a share of its
## own radius. The same lesson BlobMesh already proved for the meteor's rock
## and smoke: a mathematically perfect circle reads as a decal stamped onto
## the terrain, not a hole torn into it. Applied to the whole radial profile
## at once per angle — floor edge, rim peak and outer edge all scale
## together — so the wobble reads as one uneven crater, not rings drifting
## out of step with each other.
const EDGE_JITTER_SHARE := 0.15

var _radius := 1.0
var _origin := Vector3.ZERO
var _elapsed := 0.0
var _cooled := false
var _floor_material: ShaderMaterial
## Snapshotted at creation: a permanent decal outliving a flood by a wide
## margin is not worth a second Callable to track a sea that keeps moving.
var _water := 0.0
## One radial scale per angle index, SEGMENTS + 1 long so index 0 and index
## SEGMENTS (the same angle, TAU apart) share a value and the fan closes
## without a seam. Built once in _build(), read by both meshes.
var _edge_scale := PackedFloat32Array()


## Builds a crater at a point. Not parented here: EventManager adopts it, so
## one place decides what is on screen and what drives it.
static func create(at: Vector3, blast_radius: float, rng: RandomNumberGenerator,
		ground: Callable, water: float = -INF) -> Crater:
	if blast_radius <= 0.0 or rng == null or not ground.is_valid():
		push_error("Crater: needs a positive radius, a generator and a ground function.")
		return null

	var crater := Crater.new()
	crater._radius = blast_radius * RADIUS_SHARE
	crater._origin = at
	crater._water = water
	crater.position = at
	crater._shrink_to_coast(ground)
	crater._build(rng, ground)
	return crater


## One frame while the centre is still hot. Always returns true: a crater
## does not end, it just stops changing once it has cooled.
func advance(delta: float) -> bool:
	if _cooled:
		return true
	_elapsed += delta
	var t := clampf(_elapsed / COOL_DURATION, 0.0, 1.0)
	_floor_material.set_shader_parameter("glow", GLOW_START * (1.0 - t))
	if t >= 1.0:
		_cooled = true
	return true


func _build(rng: RandomNumberGenerator, ground: Callable) -> void:
	_floor_material = ShaderMaterial.new()
	_floor_material.shader = load("res://assets/materials/crater_floor.gdshader")
	_floor_material.set_shader_parameter("fire_color", Vector3(FIRE_COLOR.r, FIRE_COLOR.g, FIRE_COLOR.b))
	_floor_material.set_shader_parameter("glow", GLOW_START)
	_build_edge_scale(rng)

	var floor_mesh := MeshInstance3D.new()
	floor_mesh.mesh = _build_floor_mesh(rng, ground)
	floor_mesh.material_override = _floor_material
	add_child(floor_mesh)

	var rim_material := StandardMaterial3D.new()
	rim_material.vertex_color_use_as_albedo = true
	rim_material.roughness = 1.0
	rim_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var rim_mesh := MeshInstance3D.new()
	rim_mesh.mesh = _build_rim_mesh(ground)
	rim_mesh.material_override = rim_material
	add_child(rim_mesh)


## One radial scale factor per angle index, shared by the floor and the rim
## so every ring wobbles together instead of drifting apart into crossing,
## self-intersecting edges. Index SEGMENTS mirrors index 0, closing the fan
## without a seam.
func _build_edge_scale(rng: RandomNumberGenerator) -> void:
	_edge_scale.resize(SEGMENTS + 1)
	for i in SEGMENTS:
		_edge_scale[i] = 1.0 + rng.randf_range(-EDGE_JITTER_SHARE, EDGE_JITTER_SHARE)
	_edge_scale[SEGMENTS] = _edge_scale[0]


## Share of inner_radius given to the small centre cap — the only part of
## the floor that still fans out of one shared point. Kept small on purpose:
## a fan spanning the whole floor is exactly what read as an artificial
## pinwheel of dead-straight spokes instead of torn ground (found on a real
## screenshot, not guessed). Confining the fan to a quarter of the radius
## keeps the spokes short and near the centre, where the hot glow already
## draws the eye; the rest of the floor is a band with no shared apex at
## all, so it has none of that seam to show in the first place.
const FLOOR_CAP_SHARE := 0.25

## Disc from the centre out to where the rim begins, built as a small
## fanned cap plus a banded ring rather than one fan spanning the whole
## radius — see FLOOR_CAP_SHARE. Chequered facet colour, the same trick
## BlobMesh already uses, so the floor is not one dead-flat tone, and a
## jittered edge so the disc is not a perfect circle.
func _build_floor_mesh(rng: RandomNumberGenerator, ground: Callable) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	var inner_radius := _radius * RIM_INNER_SHARE
	var cap_radius := inner_radius * FLOOR_CAP_SHARE
	var center := Vector3(0.0, LIFT, 0.0)

	for i in SEGMENTS:
		var angle_a := TAU * float(i) / float(SEGMENTS)
		var angle_b := TAU * float(i + 1) / float(SEGMENTS)
		var scale_a := _edge_scale[i]
		var scale_b := _edge_scale[i + 1]

		var cap_color := FLOOR_DARK if (rng.randi() % 3) == 0 else FLOOR_LIGHT
		var cap_a := _ground_point(cap_radius * scale_a, angle_a, LIFT, ground)
		var cap_b := _ground_point(cap_radius * scale_b, angle_b, LIFT, ground)
		_triangle(vertices, normals, colors, center, cap_a, cap_b, Vector3.UP, cap_color)

		var edge_a := _ground_point(inner_radius * scale_a, angle_a, LIFT, ground)
		var edge_b := _ground_point(inner_radius * scale_b, angle_b, LIFT, ground)
		var band_color_a := FLOOR_DARK if (rng.randi() % 3) == 0 else FLOOR_LIGHT
		var band_color_b := FLOOR_DARK if (rng.randi() % 3) == 0 else FLOOR_LIGHT
		_quad(vertices, normals, colors, cap_a, cap_b, edge_b, edge_a, Vector3.UP,
			band_color_a, band_color_b, band_color_b, band_color_a)
	return _to_mesh(vertices, normals, colors)


## Ring strip from the floor's own edge up to the rim's peak, then back
## down to nothing at the crater's true edge — where it fades to
## transparent and the real terrain takes over.
func _build_rim_mesh(ground: Callable) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	var inner_radius := _radius * RIM_INNER_SHARE
	var peak_radius := _radius * RIM_PEAK_SHARE
	var rim_height := LIFT + _radius * RIM_HEIGHT_SHARE
	var opaque := Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, 1.0)
	var faded := Color(RIM_COLOR.r, RIM_COLOR.g, RIM_COLOR.b, 0.0)

	for i in SEGMENTS:
		var angle_a := TAU * float(i) / float(SEGMENTS)
		var angle_b := TAU * float(i + 1) / float(SEGMENTS)
		var scale_a := _edge_scale[i]
		var scale_b := _edge_scale[i + 1]

		var inner_a := _ground_point(inner_radius * scale_a, angle_a, LIFT, ground)
		var inner_b := _ground_point(inner_radius * scale_b, angle_b, LIFT, ground)
		var peak_a := _ground_point(peak_radius * scale_a, angle_a, rim_height, ground)
		var peak_b := _ground_point(peak_radius * scale_b, angle_b, rim_height, ground)
		_quad(vertices, normals, colors, inner_a, inner_b, peak_b, peak_a, Vector3.UP,
			opaque, opaque, opaque, opaque)

		var outer_a := _ground_point(_radius * scale_a, angle_a, LIFT, ground)
		var outer_b := _ground_point(_radius * scale_b, angle_b, LIFT, ground)
		_quad(vertices, normals, colors, peak_a, peak_b, outer_b, outer_a, Vector3.UP,
			opaque, opaque, faded, faded)
	return _to_mesh(vertices, normals, colors)


## Pulls the whole crater in, isotropically, if its blast radius would reach
## open water in any direction. The vertical clamp in _ground_point() already
## keeps every vertex at or above the water line, but that still draws a flat
## disc floating on top of the sea wherever the true seabed is deeper — this
## stops the shape itself at the shore instead. One shared radius rather than
## a per-angle one: an irregular coastline-hugging blob is not worth a second
## dimension of cheap when a slightly smaller circle already reads fine from
## any camera in this project.
func _shrink_to_coast(ground: Callable) -> void:
	var safe := _radius
	for i in COAST_PROBES:
		var angle := TAU * float(i) / float(COAST_PROBES)
		var dir := Vector3(sin(angle), 0.0, cos(angle))
		if ground.call(_origin.x + dir.x * _radius, _origin.z + dir.z * _radius) >= _water:
			continue
		var lo := 0.0
		var hi := _radius
		for _s in COAST_STEPS:
			var mid := (lo + hi) * 0.5
			if ground.call(_origin.x + dir.x * mid, _origin.z + dir.z * mid) >= _water:
				lo = mid
			else:
				hi = mid
		safe = minf(safe, lo)
	_radius = safe


## A point on a circle of `radius` at `angle`, sampled onto the real terrain
## and lifted by `height` above it, in this node's own local space. Clamped
## to the water line the same way ShockwaveEffect's own _on_ground() is: a
## crater wide enough to reach the coast should not dive to the seabed on
## that side, it should settle at the water's own surface.
func _ground_point(radius: float, angle: float, height: float, ground: Callable) -> Vector3:
	var x := sin(angle) * radius
	var z := cos(angle) * radius
	var world_y: float = maxf(ground.call(_origin.x + x, _origin.z + z), _water)
	return Vector3(x, world_y - _origin.y + height, z)


## Wound so the face is front facing seen from `outward` — the same rule
## BlobMesh already uses: Godot treats a face as front facing when its
## cross product points into the surface, so a triangle whose cross product
## points toward `outward` instead has its last two vertices swapped.
##
## The normal written is the triangle's own, not `outward` — every vertex
## here already came from _ground_point(), which samples the real, possibly
## sloped terrain, so a flat-shaded facet whose normal is always straight up
## throws that away and paints the whole floor as one dead-flat tone no
## matter how uneven the ground under it actually is. `outward` still
## decides winding, and is the fallback for the one case an honest cross
## product cannot answer: three points so close to collinear that the floor
## briefly turns level under them.
func _triangle(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	var cross := (b - a).cross(c - a)
	if cross.dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
		cross = -cross
	var length := cross.length()
	var normal := cross / length if length > 0.0001 else outward
	for v in [a, b, c]:
		vertices.append(v)
		normals.append(normal)
		colors.append(color)


func _quad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3,
		color_a: Color, color_b: Color, color_c: Color, color_d: Color) -> void:
	_colored_triangle(vertices, normals, colors, a, b, c, outward, color_a, color_b, color_c)
	_colored_triangle(vertices, normals, colors, a, c, d, outward, color_a, color_c, color_d)


## _triangle() with one shared colour; a quad's two triangles need one
## colour per corner instead, for the rim's own fade to transparent. Same
## real-normal reasoning as _triangle(): the rim follows the real terrain
## too, so its facets should shade like it, not like a flat disc.
func _colored_triangle(vertices: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, outward: Vector3,
		color_a: Color, color_b: Color, color_c: Color) -> void:
	var cross := (b - a).cross(c - a)
	var verts := [a, b, c]
	var cols := [color_a, color_b, color_c]
	if cross.dot(outward) > 0.0:
		verts = [a, c, b]
		cols = [color_a, color_c, color_b]
		cross = -cross
	var length := cross.length()
	var normal := cross / length if length > 0.0001 else outward
	for i in 3:
		vertices.append(verts[i])
		normals.append(normal)
		colors.append(cols[i])


func _to_mesh(vertices: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
