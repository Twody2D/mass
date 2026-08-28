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
const SEGMENTS := 32
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
const GLOW_START := 4.0

const FLOOR_DARK := Color(0.12, 0.1, 0.08)
const FLOOR_LIGHT := Color(0.17, 0.14, 0.1)
const RIM_COLOR := Color(0.3, 0.24, 0.16)
const FIRE_COLOR := Color(1.0, 0.5, 0.15)

var _radius := 1.0
var _origin := Vector3.ZERO
var _elapsed := 0.0
var _cooled := false
var _floor_material: ShaderMaterial
## Snapshotted at creation: a permanent decal outliving a flood by a wide
## margin is not worth a second Callable to track a sea that keeps moving.
var _water := 0.0


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


## Flat disc from the centre out to where the rim begins. Chequered facet
## colour, the same trick BlobMesh already uses, so the floor is not one
## dead-flat tone.
func _build_floor_mesh(rng: RandomNumberGenerator, ground: Callable) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	var inner_radius := _radius * RIM_INNER_SHARE
	var center := Vector3(0.0, LIFT, 0.0)
	for i in SEGMENTS:
		var color := FLOOR_DARK if (rng.randi() % 3) == 0 else FLOOR_LIGHT
		var a := _ground_point(inner_radius, TAU * float(i) / float(SEGMENTS), LIFT, ground)
		var b := _ground_point(inner_radius, TAU * float(i + 1) / float(SEGMENTS), LIFT, ground)
		_triangle(vertices, normals, colors, center, a, b, Vector3.UP, color)
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

		var inner_a := _ground_point(inner_radius, angle_a, LIFT, ground)
		var inner_b := _ground_point(inner_radius, angle_b, LIFT, ground)
		var peak_a := _ground_point(peak_radius, angle_a, rim_height, ground)
		var peak_b := _ground_point(peak_radius, angle_b, rim_height, ground)
		_quad(vertices, normals, colors, inner_a, inner_b, peak_b, peak_a, Vector3.UP,
			opaque, opaque, opaque, opaque)

		var outer_a := _ground_point(_radius, angle_a, LIFT, ground)
		var outer_b := _ground_point(_radius, angle_b, LIFT, ground)
		_quad(vertices, normals, colors, peak_a, peak_b, outer_b, outer_a, Vector3.UP,
			opaque, opaque, faded, faded)
	return _to_mesh(vertices, normals, colors)


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
func _triangle(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	var cross := (b - a).cross(c - a)
	if cross.dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
	for v in [a, b, c]:
		vertices.append(v)
		normals.append(outward)
		colors.append(color)


func _quad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3,
		color_a: Color, color_b: Color, color_c: Color, color_d: Color) -> void:
	_colored_triangle(vertices, normals, colors, a, b, c, outward, color_a, color_b, color_c)
	_colored_triangle(vertices, normals, colors, a, c, d, outward, color_a, color_c, color_d)


## _triangle() with one shared colour; a quad's two triangles need one
## colour per corner instead, for the rim's own fade to transparent.
func _colored_triangle(vertices: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, outward: Vector3,
		color_a: Color, color_b: Color, color_c: Color) -> void:
	var cross := (b - a).cross(c - a)
	var verts := [a, b, c]
	var cols := [color_a, color_b, color_c]
	if cross.dot(outward) > 0.0:
		verts = [a, c, b]
		cols = [color_a, color_c, color_b]
	for i in 3:
		vertices.append(verts[i])
		normals.append(outward)
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
