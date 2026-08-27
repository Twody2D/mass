class_name ShockwaveEffect
extends MeshInstance3D
## The ring that races outwards along the ground after an impact, and frees
## itself once it has passed.
##
## It follows the terrain instead of lying flat. A flat disc across a 55 m
## crater on a hillside is half buried and reads as a bug; a ring that samples
## the ground at every vertex hugs the slope for the price of rebuilding
## 48 vertices a frame, which is nothing when there is one of them on screen.
##
## Built with ImmediateMesh because that is exactly what it is for: geometry
## that changes every frame and is thrown away at the end of it.

const DURATION := 1.4
const SEGMENTS := 48
## Thickness of the ring as a share of its current radius.
const THICKNESS := 0.22
## Lifted off the ground, or it fights the terrain for the same pixels.
const LIFT := 0.6
const PEAK_ALPHA := 0.9

var _radius := 1.0
var _elapsed := 0.0
var _origin := Vector3.ZERO
var _color := Color.WHITE
## Returns ground height at (x, z). Passed in rather than looked up, so a
## rendering effect does not acquire an opinion about the World.
var _ground := Callable()
var _immediate: ImmediateMesh
var _material: StandardMaterial3D


## Builds a ring at a point. Not parented here: EventManager adopts it, so one
## place decides what is on screen and what drives it.
static func create(at: Vector3, radius: float, color: Color,
		ground: Callable) -> ShockwaveEffect:
	if radius <= 0.0 or not ground.is_valid():
		push_error("ShockwaveEffect: needs a positive radius and a ground function.")
		return null

	var wave := ShockwaveEffect.new()
	wave._radius = radius
	wave._origin = at
	wave._color = color
	wave._ground = ground

	wave._immediate = ImmediateMesh.new()
	wave.mesh = wave._immediate

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.vertex_color_use_as_albedo = true
	wave._material = material
	wave.material_override = material

	wave.position = at
	wave._redraw(0.0)
	return wave


## One frame of the ring racing outwards. Returns false once it has passed.
func advance(delta: float) -> bool:
	_elapsed += delta
	var t := _elapsed / DURATION
	if t >= 1.0:
		queue_free()
		return false
	_redraw(t)
	return true


func _redraw(t: float) -> void:
	# Fast at first and slowing, like something losing to the air it is pushing.
	var eased := 1.0 - pow(1.0 - t, 2.5)
	var outer := _radius * lerpf(0.08, 1.0, eased)
	var inner := outer * (1.0 - THICKNESS)
	var fade := 1.0 - t
	# The edges of the ring are transparent and the middle is not, so it has no
	# hard border in either direction.
	var edge := Color(_color.r, _color.g, _color.b, 0.0)
	var core := Color(_color.r, _color.g, _color.b, PEAK_ALPHA * fade * fade)

	# Two bands rather than one: transparent inside, solid through the middle,
	# transparent again outside. A single band would fade in one direction and
	# end in a hard edge in the other.
	var middle := (inner + outer) * 0.5
	_immediate.clear_surfaces()
	_band(inner, edge, middle, core)
	_band(middle, core, outer, edge)


func _band(inner_radius: float, inner_color: Color, outer_radius: float,
		outer_color: Color) -> void:
	_immediate.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _material)
	for i in SEGMENTS + 1:
		var angle := TAU * float(i) / float(SEGMENTS)
		var direction := Vector3(sin(angle), 0.0, cos(angle))
		_immediate.surface_set_color(inner_color)
		_immediate.surface_add_vertex(_on_ground(direction * inner_radius))
		_immediate.surface_set_color(outer_color)
		_immediate.surface_add_vertex(_on_ground(direction * outer_radius))
	_immediate.surface_end()


## Puts a point of the ring on the terrain, in the effect's own local space.
func _on_ground(offset: Vector3) -> Vector3:
	var x := _origin.x + offset.x
	var z := _origin.z + offset.z
	var height: float = _ground.call(x, z)
	return Vector3(offset.x, height + LIFT - _origin.y, offset.z)
