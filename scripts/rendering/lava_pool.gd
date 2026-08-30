class_name LavaPool
extends MeshInstance3D
## One growing puddle of lava, radiating from a single vent. A volcano lights
## several of these at once (VolcanoEruption owns the radius, not this), and
## where they overlap is exactly the picture "lava spreads from every rift at
## once" asks for — no shared field, no distance-to-nearest-vent geometry,
## just several of the simplest possible growing circles.
##
## Same shape as ZoneRing: a ground-following disc rebuilt only when the
## radius has moved far enough to be worth the terrain lookups, driven by
## whoever owns the radius rather than by _process. Flat rather than a wall,
## because lava is something the crowd runs from before ever standing in it,
## not something meant to be seen looming from a distance the way the zone's
## wall was — and cheaper besides, one vertex column per angle instead of two.
##
## Reuses crater_floor.gdshader as-is: a hot, coloured, ground-following disc
## with a glow uniform is already exactly what a molten patch looks like, and
## the shader was written general enough to need nothing new for it.
##
## Never frees itself, the same contract Crater has and for the same reason:
## cooled lava is still there. VolcanoEruption stops growing it and then lets
## go; EventManager keeps it on screen until the session resets.
##
## Grows as uneven fingers, not a perfect circle. A single smooth disc read
## as "a puddle appeared and got bigger" — the owner watched a real eruption
## and called it lava "dripping from a nozzle" — not as flow. Real lava does
## not advance on a uniform front: some tongues race ahead along whatever
## the terrain favours while the rest of the rim barely creeps. Each of
## SEGMENTS angles now has its own growth speed and its own final reach, so
## the edge arrives at different distances at different times instead of
## one ring expanding in lockstep.

const SEGMENTS := 24
## Higher than Crater's own 0.5 m: a pool grows across a real mountainside
## now, not flat ground, and a vertical lift buys far less clearance on a
## slope than it does on the level — the same lift that hid Crater's seam
## let the mesh peek through the terrain on the volcano's flank instead.
const LIFT := 2.0
## Growth below this is not worth rebuilding the mesh for, in metres.
const REDRAW_EPSILON := 1.0

## How far each radial edge wobbles from a perfect circle, as a share of its
## own radius — the same three-sine-lobe wobble Crater uses instead of an
## independent draw per segment, smooth by construction so it stays an
## uneven edge rather than a needle spike whatever SEGMENTS happens to be.
const EDGE_JITTER_SHARE := 0.12

## Per-angle growth rate, as a multiple of the nominal radius VolcanoEruption
## is driving. Above 1 that finger is out ahead of the pack; below 1 it is
## lagging. Wide range on purpose — the fastest tongues should look like
## they are visibly racing ahead of the rest of the front.
const FINGER_SPEED_MIN := 0.55
const FINGER_SPEED_MAX := 1.6
## Per-angle final reach, as a share of the eruption's own final radius, so
## fast fingers do not just arrive early — they also end up longer, the way
## a real flow's fastest channel outruns its own edges rather than the
## whole rim simply catching up to it later.
const FINGER_REACH_MIN := 0.6
const FINGER_REACH_MAX := 1.15

const LAVA_COLOR := Color(0.55, 0.09, 0.02)
const GLOW := 1.4

var _centre := Vector2.ZERO
## The nominal radius VolcanoEruption is driving — not what any single
## finger has actually reached, just the shared clock every finger's own
## speed and cap are measured against.
var _radius := 0.0
var _final_radius := 1.0
var _drawn_radius := -1.0
## Returns ground height at (x, z). Passed in rather than looked up, so a
## rendering effect does not acquire an opinion about the World.
var _ground := Callable()
var _material: ShaderMaterial
var _edge_scale := PackedFloat32Array()
var _finger_speed := PackedFloat32Array()
var _finger_reach := PackedFloat32Array()


## Builds a pool with zero radius at a vent, due to eventually reach
## `final_radius`. Not parented here: EventManager adopts it, so one place
## decides what is on screen and what drives it.
static func create(centre: Vector2, final_radius: float, rng: RandomNumberGenerator,
		ground: Callable) -> LavaPool:
	if final_radius <= 0.0 or rng == null or not ground.is_valid():
		push_error("LavaPool: needs a positive final radius, a generator and a ground function.")
		return null

	var pool := LavaPool.new()
	pool._centre = centre
	pool._final_radius = final_radius
	pool._ground = ground
	pool._build_edge_scale(rng)
	pool._build_fingers(rng)

	pool._material = ShaderMaterial.new()
	pool._material.shader = load("res://assets/materials/crater_floor.gdshader")
	pool._material.set_shader_parameter("fire_color",
		Vector3(LAVA_COLOR.r, LAVA_COLOR.g, LAVA_COLOR.b))
	pool._material.set_shader_parameter("glow", GLOW)
	pool.material_override = pool._material
	pool.position = Vector3(centre.x, 0.0, centre.y)
	return pool


## A pool never ends by itself — see the class doc.
func advance(_delta: float) -> bool:
	return true


## Grows the pool. Cheap to call every sweep with a radius barely different
## from the last one drawn: the disc is only rebuilt once it has grown enough
## to be worth the terrain lookups.
func set_radius(radius: float) -> void:
	if radius <= 0.0:
		return
	_radius = radius
	if _radius - _drawn_radius >= REDRAW_EPSILON:
		_redraw()


## The nominal (shared-clock) radius VolcanoEruption is driving, not any one
## finger's own reach — callers that need "has the lava gotten here yet"
## (VolcanoEruption's own _sweep()) already treat this as one shared circle,
## and fingers only ever extend past it, never fall inside it, so it stays
## the conservative answer.
func radius() -> float:
	return _radius


func _build_edge_scale(rng: RandomNumberGenerator) -> void:
	var phase_a := rng.randf() * TAU
	var phase_b := rng.randf() * TAU
	var phase_c := rng.randf() * TAU
	_edge_scale.resize(SEGMENTS + 1)
	for i in SEGMENTS + 1:
		var angle := TAU * float(i) / float(SEGMENTS)
		var wobble := sin(angle * 3.0 + phase_a) * 0.5 + sin(angle * 5.0 + phase_b) * 0.3 \
			+ sin(angle * 7.0 + phase_c) * 0.2
		_edge_scale[i] = 1.0 + wobble * EDGE_JITTER_SHARE


func _build_fingers(rng: RandomNumberGenerator) -> void:
	_finger_speed.resize(SEGMENTS + 1)
	_finger_reach.resize(SEGMENTS + 1)
	for i in SEGMENTS + 1:
		_finger_speed[i] = rng.randf_range(FINGER_SPEED_MIN, FINGER_SPEED_MAX)
		_finger_reach[i] = rng.randf_range(FINGER_REACH_MIN, FINGER_REACH_MAX)
	# The seam at angle 0 / TAU has to match, the same reasoning
	# _build_edge_scale() already follows for its own wobble.
	_finger_speed[SEGMENTS] = _finger_speed[0]
	_finger_reach[SEGMENTS] = _finger_reach[0]


## How far this one angle has actually reached, given the nominal radius —
## its own speed ahead of or behind the shared clock, capped at its own
## share of the eruption's final radius.
func _finger_radius(i: int) -> float:
	return minf(_radius * _finger_speed[i], _final_radius * _finger_reach[i]) * _edge_scale[i]


func _redraw() -> void:
	_drawn_radius = _radius
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var color := Color(LAVA_COLOR.r, LAVA_COLOR.g, LAVA_COLOR.b, 1.0)
	var center := _point(0.0, 0.0)
	for i in SEGMENTS:
		var angle_a := TAU * float(i) / float(SEGMENTS)
		var angle_b := TAU * float(i + 1) / float(SEGMENTS)
		var a := _point(_finger_radius(i), angle_a)
		var b := _point(_finger_radius(i + 1), angle_b)
		_triangle(vertices, normals, colors, center, a, b, color)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var array_mesh := ArrayMesh.new()
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = array_mesh


## A point on a circle of `radius` at `angle`, sampled onto the real terrain
## and lifted above it, in this node's own local space.
func _point(radius: float, angle: float) -> Vector3:
	var x := sin(angle) * radius
	var z := cos(angle) * radius
	var y: float = _ground.call(_centre.x + x, _centre.y + z) + LIFT
	return Vector3(x, y, z)


## Wound so the face is front facing seen from straight up — the same rule
## Crater uses. The normal written is the triangle's own, not a fixed up, so
## real terrain under the pool still shades like real terrain.
func _triangle(vertices: PackedVector3Array, normals: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var cross := (b - a).cross(c - a)
	if cross.dot(Vector3.UP) > 0.0:
		var swap := b
		b = c
		c = swap
		cross = -cross
	var length := cross.length()
	var normal := cross / length if length > 0.0001 else Vector3.UP
	for v in [a, b, c]:
		vertices.append(v)
		normals.append(normal)
		colors.append(color)
