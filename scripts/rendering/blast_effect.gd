class_name BlastEffect
extends MeshInstance3D
## A single expanding flash where something hit the world, which frees itself
## once it has finished.
##
## Creating nodes at run time is fine here and nowhere near the crowd: there is
## one blast on screen at a time, not ten thousand. Unshaded and additive, so it
## reads as light rather than as a grey ball, and so it costs no lighting work.

const DURATION := 0.9
## Where the flash starts, as a share of its final radius. Not zero: a sphere
## that grows from nothing looks like it arrived late.
const START_SHARE := 0.18
const PEAK_ALPHA := 0.5

var _radius := 1.0
var _elapsed := 0.0
var _material: StandardMaterial3D


## Puts a blast at a point and hands it back, in case a caller wants to keep it.
static func spawn(parent: Node, at: Vector3, radius: float, color: Color) -> BlastEffect:
	if parent == null or radius <= 0.0:
		push_error("BlastEffect: needs a parent and a positive radius, got %f." % radius)
		return null

	var effect := BlastEffect.new()
	effect._radius = radius

	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	# Coarse on purpose: it is on screen for under a second and always softened
	# by its own transparency.
	sphere.radial_segments = 16
	sphere.rings = 8
	effect.mesh = sphere

	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.albedo_color = Color(color.r, color.g, color.b, PEAK_ALPHA)
	effect._material = material
	effect.material_override = material

	effect.position = at
	effect.scale = Vector3.ONE * radius * START_SHARE
	parent.add_child(effect)
	return effect


func _process(delta: float) -> void:
	_elapsed += delta
	var t := _elapsed / DURATION
	if t >= 1.0:
		queue_free()
		return

	# Fast out of the gate and slowing down, the way a shockwave loses to the air.
	var eased := 1.0 - pow(1.0 - t, 3.0)
	scale = Vector3.ONE * _radius * lerpf(START_SHARE, 1.0, eased)
	_material.albedo_color.a = PEAK_ALPHA * (1.0 - t)
