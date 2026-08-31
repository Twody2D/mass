class_name Fissure
extends Node3D
## The permanent scar an earthquake tears into the ground (TODO.md item 52):
## a jagged strip along a path rather than Crater's circle. Purely a decal —
## the same "never touches the heightmap" contract Crater keeps — but unlike
## Crater it is also a real obstacle: EarthquakeEvent calls
## World.add_rift_barrier() along the same path, which is what actually
## splits the crowd. Nothing here needs to know that; a bot already rerolls
## a wander target that fails is_walkable(), the same way it already avoids
## stepping into the sea.
##
## Follows the terrain the same way Crater/ShockwaveEffect do — every vertex
## samples world.get_height() — for the same reason a flat decal across
## broken, sloped ground would float on one side of it.
##
## Never frees itself, the same permanence Crater already has: an earthquake
## does not heal, it just stops being new. advance() always returns true and
## does nothing at all — there is no glow to cool here, only a mark.

## Clears the real terrain the same way Crater's own LIFT does, and for the
## same reason: a decal sitting exactly at ground level fights the terrain
## for the same pixels.
const LIFT := 0.4

## Two dark tones swapped per segment — the same "not one dead-flat tone"
## trick Crater's floor and BlobMesh's facets already use, at a fraction of
## the detail: one flat colour per whole cross-section rather than a
## chequered fan, because a narrow ribbon has no room for a visible pattern
## anyway.
const DARK_A := Color(0.05, 0.04, 0.035)
const DARK_B := Color(0.08, 0.065, 0.05)

## Kept only for start_point() — the geometry itself is baked into the mesh
## once in _build() and never read back from here again.
var _path := PackedVector2Array()


## Builds a fissure along `path` (world-space points, at least two), each
## cross-section `half_width` wide. Not parented here: EventManager adopts
## it, so one place decides what is on screen.
static func create(path: PackedVector2Array, half_width: float, ground: Callable,
		rng: RandomNumberGenerator) -> Fissure:
	if path.size() < 2:
		push_error("Fissure: needs a path of at least two points, got %d." % path.size())
		return null
	if half_width <= 0.0 or not ground.is_valid() or rng == null:
		push_error("Fissure: needs a positive width, a ground function and a generator.")
		return null

	var fissure := Fissure.new()
	fissure._build(path, half_width, ground, rng)
	return fissure


## A mark does not change once torn. advance() exists only so EventManager
## can adopt this the same way it adopts every other visual.
func advance(_delta: float) -> bool:
	return true


## Where this rift starts, for anything that wants to point a camera at it
## without knowing the rest of its path — screenshot.gd, in particular,
## which has no coordinate to frame otherwise since this node's own
## transform stays at the identity (see _build()'s own note).
func start_point() -> Vector2:
	return _path[0] if not _path.is_empty() else Vector2.ZERO


## Vertices are already in world space (each cross-section comes straight
## from the path EarthquakeEvent built), so this node's own transform stays
## at the identity — simpler than Crater's local-origin offset, and correct
## for the same reason: nothing here ever needs to move relative to a single
## centre point the way a circular decal does.
func _build(path: PackedVector2Array, half_width: float, ground: Callable,
		rng: RandomNumberGenerator) -> void:
	_path = path
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()

	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		var along := (b - a).normalized()
		if along == Vector2.ZERO:
			continue
		var side := Vector2(-along.y, along.x) * half_width

		var a_left := _ground_point(a - side, ground)
		var a_right := _ground_point(a + side, ground)
		var b_left := _ground_point(b - side, ground)
		var b_right := _ground_point(b + side, ground)

		var color := DARK_A if (rng.randi() % 2) == 0 else DARK_B
		_quad(vertices, normals, colors, a_left, a_right, b_right, b_left, color)

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	# Winding is not tracked per quad here (see _quad's own note), so both
	# faces have to shade — cheap next to a handful of short ribbons, and
	# simpler than carrying Crater's own winding-safe triangle builder over
	# for a shape this small.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)


## A point offset from the path's centreline, sampled onto the real terrain
## and lifted by LIFT above it — Crater's own _ground_point(), minus the
## water clamp and the local-origin offset neither apply here: a fissure
## does not reach the coast the way a wide blast radius can, and there is no
## single origin to measure from.
func _ground_point(p: Vector2, ground: Callable) -> Vector3:
	var y: float = ground.call(p.x, p.y) + LIFT
	return Vector3(p.x, y, p.y)


## One cross-section's worth of ground: a flat-shaded quad with a fixed
## up-facing normal rather than one following the real slope — Crater's
## floor earns a sloped normal because it is large enough to show the
## difference; a ribbon a few metres wide is not. Two triangles, winding
## unchecked (see cull_mode above), so this needs neither the outward
## parameter nor the swap Crater's own _triangle() carries for exactly that.
func _quad(vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray,
		a: Vector3, b: Vector3, c: Vector3, d: Vector3, color: Color) -> void:
	for v in [a, b, c, a, c, d]:
		vertices.append(v)
		normals.append(Vector3.UP)
		colors.append(color)
