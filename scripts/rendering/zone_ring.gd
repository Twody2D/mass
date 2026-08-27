class_name ZoneRing
extends MeshInstance3D
## The wall of the safe zone: a ring of light standing on the ground where the
## boundary currently is.
##
## A wall rather than a ring painted on the terrain, which is what the shockwave
## uses. A flat ring is invisible from anywhere near the crowd's own height, and
## the point of this boundary is that it can be seen coming — from the air, and
## from a camera down among the knights running away from it. It costs the same
## either way: the same points around the circle, each with a second vertex
## above it.
##
## Follows the terrain at its base, for the same reason the shockwave does: a
## ring at a constant height cuts through a hillside and reads as a bug.
##
## Redrawn only when the boundary has actually moved, and driven from whatever
## owns the radius rather than from _process. The radius is simulation state —
## it decides who is taking damage — so the wall must not have an opinion of its
## own about where it is.

const SEGMENTS := 64
## How tall the wall stands, in metres. Ten knights: tall enough to read from
## altitude against a 140 m island, short enough not to hide what is behind it.
const HEIGHT := 24.0
## Lifted off the ground, or it fights the terrain for the same pixels.
const LIFT := 0.4
const BASE_ALPHA := 0.5
## Boundary movement below this is not worth 65 terrain lookups, in metres.
const REDRAW_EPSILON := 0.25

var _centre := Vector2.ZERO
var _radius := 0.0
var _drawn_radius := -1.0
var _color := Color.WHITE
## Returns ground height at (x, z). Passed in rather than looked up, so a
## rendering effect does not acquire an opinion about the World.
var _ground := Callable()
var _immediate: ImmediateMesh
var _material: StandardMaterial3D


## Builds the wall at a radius around a point on the map. Not parented here:
## whoever owns the boundary owns the node.
static func create(centre: Vector2, radius: float, color: Color,
			ground: Callable) -> ZoneRing:
	if radius <= 0.0 or not ground.is_valid():
		push_error("ZoneRing: needs a positive radius and a ground function.")
		return null

	var ring := ZoneRing.new()
	ring._centre = centre
	ring._radius = radius
	ring._color = color
	ring._ground = ground

	ring._immediate = ImmediateMesh.new()
	ring.mesh = ring._immediate

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	## Seen from both sides: the crowd inside looks at the back of it.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	ring._material = material
	ring.material_override = material

	ring.position = Vector3(centre.x, 0.0, centre.y)
	ring._redraw()
	return ring


## Moves the boundary. Cheap to call every tick with a radius that has barely
## changed: the geometry is only rebuilt once the wall has moved far enough to
## be worth the terrain lookups.
func set_radius(radius: float) -> void:
	if radius <= 0.0:
		push_error("ZoneRing: set_radius() expects a positive radius, got %f." % radius)
		return
	_radius = radius
	if absf(_radius - _drawn_radius) >= REDRAW_EPSILON:
		_redraw()


func radius() -> float:
	return _radius


func _redraw() -> void:
	_drawn_radius = _radius
	var base := Color(_color.r, _color.g, _color.b, BASE_ALPHA)
	## Transparent at the top, so the wall has no hard edge against the sky.
	var top := Color(_color.r, _color.g, _color.b, 0.0)

	_immediate.clear_surfaces()
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	for i in SEGMENTS + 1:
		var angle := TAU * float(i) / float(SEGMENTS)
		var x := sin(angle) * _radius
		var z := cos(angle) * _radius
		var y: float = _ground.call(_centre.x + x, _centre.y + z) + LIFT
		_immediate.surface_set_color(base)
		_immediate.surface_add_vertex(Vector3(x, y, z))
		_immediate.surface_set_color(top)
		_immediate.surface_add_vertex(Vector3(x, y + HEIGHT, z))
	_immediate.surface_end()
