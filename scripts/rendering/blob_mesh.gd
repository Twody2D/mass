class_name BlobMesh
extends RefCounted
## A lumpy low poly ball: a sphere whose vertices have been pushed in and out at
## random, flat shaded.
##
## One shape, two jobs. It is the meteor, where a smooth sphere would read as a
## marble rather than as a rock, and it is every billow of the mushroom cloud,
## where a smooth sphere would read as a balloon. Faceting and an uneven radius
## are the whole trick, and both are free: these are built one at a time and
## thrown away, not ten thousand at once.
##
## Same winding rule as the knight, and for the same reason: Godot treats a face
## as front facing when its cross product points into the surface.

## Default shape: coarse and lumpy, which is what a rock wants. Smoke asks for
## rounder and smoother, so all three are arguments.
const SIDES := 9
const RINGS := 6
## How far a vertex may move in or out, as a share of the radius.
const JITTER := 0.3

## Dark stone, so the fire around a meteor has something to be brighter than.
const ROCK := Color(0.20, 0.18, 0.17)
const ROCK_LIGHT := Color(0.31, 0.28, 0.25)

var _smooth := false
var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()


## Builds a blob of roughly `radius`, centred on the origin. The same seed
## always carves the same one.
##  shades from the centre outwards instead of per facet. Flat is what
## makes a rock look carved; smooth is what stops a puff of smoke looking like
## one, and it is the single change that turned the mushroom cloud from a pile
## of boulders into something soft.
static func build(radius: float, mesh_seed: int, dark := ROCK, light := ROCK_LIGHT,
		sides := SIDES, rings := RINGS, jitter := JITTER, smooth := false) -> ArrayMesh:
	var builder := BlobMesh.new()
	builder._smooth = smooth
	builder._carve(radius, mesh_seed, dark, light, maxi(3, sides), maxi(2, rings), jitter)
	return builder._to_mesh()


func _carve(radius: float, mesh_seed: int, dark: Color, light: Color,
		sides_count: int, rings_count: int, jitter: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = mesh_seed

	# Vertices on a sphere grid, each pushed in or out on its own. The poles are
	# single points, shared by every triangle of the top and bottom ring.
	var points := PackedVector3Array()
	points.resize((rings_count + 1) * sides_count)
	for ring in rings_count + 1:
		var phi := PI * float(ring) / float(rings_count)
		var y := cos(phi)
		var ring_radius := sin(phi)
		var pole_scale := 1.0 + rng.randf_range(-jitter, jitter)
		for side in sides_count:
			var scale := pole_scale
			if ring > 0 and ring < rings_count:
				scale = 1.0 + rng.randf_range(-jitter, jitter)
			var theta := TAU * float(side) / float(sides_count)
			points[ring * sides_count + side] = radius * scale * Vector3(
				sin(theta) * ring_radius, y, cos(theta) * ring_radius)

	for ring in rings_count:
		for side in sides_count:
			var next := (side + 1) % sides_count
			var a := points[ring * sides_count + side]
			var b := points[ring * sides_count + next]
			var c := points[(ring + 1) * sides_count + next]
			var d := points[(ring + 1) * sides_count + side]
			# Slight shade variation between facets, so the silhouette is not the
			# only thing telling the shapes apart.
			var color := dark if (ring + side) % 3 == 0 else light
			if ring == 0:
				_triangle(a, c, d, (a + c + d) / 3.0, color)
			elif ring == rings_count - 1:
				_triangle(a, b, c, (a + b + c) / 3.0, color)
			else:
				_quad(a, b, c, d, (a + b + c + d) / 4.0, color)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color) -> void:
	_triangle(a, b, c, outward, color)
	_triangle(a, c, d, outward, color)


## Wound so the face is front facing seen from `outward`. See KnightMesh for why
## that is the winding whose cross product points into the surface.
func _triangle(a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	var cross := (b - a).cross(c - a)
	if cross.length_squared() < 0.000000000001:
		return
	if cross.dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
		cross = -cross
	var normal := (-cross).normalized()
	for vertex: Vector3 in [a, b, c]:
		_vertices.append(vertex)
		# Smooth blobs are centred on the origin, so the direction out from the
		# centre is the normal, and the facets stop showing.
		_normals.append(vertex.normalized() if _smooth else normal)
		_colors.append(color)


func _to_mesh() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _vertices
	arrays[Mesh.ARRAY_NORMAL] = _normals
	arrays[Mesh.ARRAY_COLOR] = _colors
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh
