class_name KnightMesh
extends RefCounted
## Builds the little knight as a single flat shaded mesh.
##
## One mesh, because MultiMesh draws one mesh. Every part is welded into the
## same surface: separate nodes per limb would mean separate draw calls, which
## is the one thing ten thousand instances cannot afford.
##
## Vertex colours carry two things at once. RGB is the shade of the part, and
## alpha is a team mask: 0 keeps that shade, 1 multiplies it by the team colour
## of the bot. That is how steel stays steel while the helmet and shield take
## the team colour, with a single material for the whole crowd.

## Proportions as fractions of the height. The brief asks for roughly 40%
## helmet, 35% body, 25% limbs: the helmet is meant to look too big.
const LEG_TOP := 0.22
const BODY_TOP := 0.56
const HELMET_TOP := 1.0

## Sides per prism. Measured on this machine, ten thousand instances cost
## 109 FPS at 12 triangles each, 103 at 72, 84 at 144 and 44 at 252: the curve
## turns sharply past about 150, so every ring is rationed. The helmet keeps six
## sides because it carries the silhouette; everything else makes do with four.
const HELMET_SIDES := 6
const BODY_SIDES := 4

# Shades. RGB is the colour of the part, A is the team mask.
const STEEL := Color(0.72, 0.74, 0.78, 0.0)
const DARK_STEEL := Color(0.5, 0.53, 0.58, 0.0)
const LEATHER := Color(0.34, 0.24, 0.18, 0.0)
const VISOR := Color(0.06, 0.06, 0.08, 0.0)
## White with the mask on: pure team colour.
const TEAM := Color(1.0, 1.0, 1.0, 1.0)
## The same team colour a shade darker, for the body under the helmet.
const TEAM_DARK := Color(0.74, 0.74, 0.74, 1.0)

var _vertices := PackedVector3Array()
var _normals := PackedVector3Array()
var _colors := PackedColorArray()


## Builds the knight standing on the origin, facing +Z, scaled to `height`.
static func build(height: float) -> ArrayMesh:
	var builder := KnightMesh.new()
	builder._compose(height)
	return builder._to_mesh()


func _compose(h: float) -> void:
	var leg_top := LEG_TOP * h
	# The body skirt reaches below the hips, so the joint is never on show.
	var body_bottom := leg_top - 0.06 * h
	var body_top := BODY_TOP * h
	var helmet_top := HELMET_TOP * h

	# Very short legs, ending in boots that are mostly boot. Kept narrow and
	# close to the centre line so the hips stay inside the body: legs wider than
	# the waist read as limbs poking out through the torso.
	for side: float in [-1.0, 1.0]:
		var x := side * 0.085 * h
		_box(Vector3(x, leg_top * 0.5, 0.0), Vector3(0.11, leg_top, 0.13) * h, DARK_STEEL)
		_box(Vector3(x, 0.035 * h, 0.02 * h), Vector3(0.14, 0.07, 0.19) * h, LEATHER)

	# Egg shaped body: narrow at the waist, widest at the chest, tucked back in
	# under the helmet.
	_prism([
		[body_bottom, 0.28 * h],
		[lerpf(body_bottom, body_top, 0.45), 0.31 * h],
		[body_top, 0.25 * h],
	], BODY_SIDES, TEAM_DARK, true, true)

	# Stubby arms, hanging almost straight down. No separate gloves: at the
	# distance the crowd is actually viewed from, they cost 24 triangles and
	# show nothing.
	for side: float in [-1.0, 1.0]:
		var x := side * 0.31 * h
		_box(Vector3(x, body_top - 0.21 * h, 0.0), Vector3(0.12, 0.34, 0.13) * h, DARK_STEEL)

	# The helmet: a slightly rounded metal bucket, wider than the shoulders.
	_prism([
		[body_top + 0.01 * h, 0.24 * h],
		[lerpf(body_top, helmet_top, 0.45), 0.31 * h],
		[helmet_top, 0.23 * h],
	], HELMET_SIDES, TEAM, true, true)

	# The eye slit is the only face the knight gets, and it is a dark rectangle.
	# It has to stand proud of the helmet: sunk flush it disappears inside the
	# hull and the knight loses the one feature that reads as a face.
	var eye_y := lerpf(body_top, helmet_top, 0.42)
	_box(Vector3(0.0, eye_y, 0.29 * h), Vector3(0.30, 0.08, 0.08) * h, VISOR)

	_sword(h, body_top)
	_shield(h, body_top)


## Deliberately a size too big for its owner. That is the joke. The crossguard
## alone reads as a hilt, so there is no separate grip.
func _sword(h: float, body_top: float) -> void:
	var x := 0.4 * h
	var guard_y := body_top - 0.22 * h
	_box(Vector3(x, guard_y, 0.0), Vector3(0.26, 0.06, 0.09) * h, DARK_STEEL)
	_box(Vector3(x, guard_y + 0.5 * h, 0.0), Vector3(0.07, 0.94, 0.11) * h, STEEL)


## Almost as tall as the knight, and one of the two big team coloured surfaces.
func _shield(h: float, body_top: float) -> void:
	var x := -0.4 * h
	var y := body_top - 0.24 * h
	# A hexagonal plate lying in the YZ plane, so it faces out from the arm.
	var plate := PackedVector3Array()
	for i in BODY_SIDES:
		var angle := TAU * (float(i) / BODY_SIDES) + PI / 4.0
		plate.append(Vector3(0.0, sin(angle) * 0.36 * h, cos(angle) * 0.32 * h))
	_plate(plate, Vector3(x, y, 0.0), Vector3(-1.0, 0.0, 0.0), 0.05 * h, TEAM)


# --- geometry helpers ---------------------------------------------------------

## Axis aligned box, six quads.
func _box(center: Vector3, size: Vector3, color: Color) -> void:
	var e := size * 0.5
	var c := [
		center + Vector3(-e.x, -e.y, -e.z), center + Vector3(e.x, -e.y, -e.z),
		center + Vector3(e.x, e.y, -e.z), center + Vector3(-e.x, e.y, -e.z),
		center + Vector3(-e.x, -e.y, e.z), center + Vector3(e.x, -e.y, e.z),
		center + Vector3(e.x, e.y, e.z), center + Vector3(-e.x, e.y, e.z),
	]
	_quad(c[4], c[5], c[6], c[7], Vector3.BACK, color)
	_quad(c[1], c[0], c[3], c[2], Vector3.FORWARD, color)
	_quad(c[5], c[1], c[2], c[6], Vector3.RIGHT, color)
	_quad(c[0], c[4], c[7], c[3], Vector3.LEFT, color)
	_quad(c[7], c[6], c[2], c[3], Vector3.UP, color)
	_quad(c[0], c[1], c[5], c[4], Vector3.DOWN, color)


## Stack of rings, each pair joined by a band of quads.
func _prism(rings: Array, sides: int, color: Color, cap_bottom: bool, cap_top: bool) -> void:
	var offset := PI / sides
	var loops := []
	for ring in rings:
		var y: float = ring[0]
		var radius: float = ring[1]
		var loop := PackedVector3Array()
		for i in sides:
			var angle := TAU * (float(i) / sides) + offset
			loop.append(Vector3(sin(angle) * radius, y, cos(angle) * radius))
		loops.append(loop)

	for level in loops.size() - 1:
		var lower: PackedVector3Array = loops[level]
		var upper: PackedVector3Array = loops[level + 1]
		for i in sides:
			var j := (i + 1) % sides
			var outward := (lower[i] + lower[j] + upper[i] + upper[j]) * 0.25
			outward.y = 0.0
			_quad(lower[i], lower[j], upper[j], upper[i], outward.normalized(), color)

	if cap_bottom:
		_fan(loops[0], Vector3.DOWN, color)
	if cap_top:
		_fan(loops[loops.size() - 1], Vector3.UP, color)


## Flat polygon extruded a little along `outward`, used for the shield.
func _plate(outline: PackedVector3Array, offset: Vector3, outward: Vector3,
		thickness: float, color: Color) -> void:
	var front := PackedVector3Array()
	var back := PackedVector3Array()
	for point in outline:
		front.append(point + offset + outward * thickness * 0.5)
		back.append(point + offset - outward * thickness * 0.5)
	_fan(front, outward, color)
	_fan(back, -outward, color)
	for i in outline.size():
		var j := (i + 1) % outline.size()
		var rim := (front[i] + front[j]) * 0.5 - offset
		_quad(back[i], back[j], front[j], front[i], rim.normalized(), color)


## Triangle fan across a convex loop, facing `outward`.
func _fan(loop: PackedVector3Array, outward: Vector3, color: Color) -> void:
	for i in range(1, loop.size() - 1):
		_triangle(loop[0], loop[i], loop[i + 1], outward, color)


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, outward: Vector3, color: Color) -> void:
	_triangle(a, b, c, outward, color)
	_triangle(a, c, d, outward, color)


## Emits one triangle, wound so that the face is front facing when seen from
## `outward`.
##
## Godot treats a face as front facing when its vertices run clockwise as seen
## from outside, which is the winding whose cross product points **into** the
## surface, not out of it. Getting that backwards does not make the model
## disappear, which is what makes it easy to miss: the silhouette and the
## shading stay right, but every near face is culled and the viewer sees the
## inside of the far ones, along with whatever is inside the body. That is what
## made the legs show through the torso.
func _triangle(a: Vector3, b: Vector3, c: Vector3, outward: Vector3, color: Color) -> void:
	var cross := (b - a).cross(c - a)
	if cross.length_squared() < 0.000000000001:
		return
	if cross.dot(outward) > 0.0:
		var swap := b
		b = c
		c = swap
		cross = -cross
	# The shading normal still points outward, whichever way the winding went.
	var normal := (-cross).normalized()
	# Flat shading: every face keeps its own vertices and its own normal.
	for vertex: Vector3 in [a, b, c]:
		_vertices.append(vertex)
		_normals.append(normal)
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
