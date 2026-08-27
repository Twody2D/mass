class_name BlastEffect
extends MeshInstance3D
## A single expanding flash where something hit the world, which frees itself
## once it has finished.
##
## Creating nodes at run time is fine here and nowhere near the crowd: there is
## one blast on screen at a time, not ten thousand. Unshaded and additive, so it
## costs no lighting work, and faded out towards its own silhouette by
## blast.gdshader, which is what makes it read as light instead of as a ball.

const DURATION := 1.1
## Where the flash starts and stops, as a share of the blast radius. Not zero at
## the start: a sphere that grows from nothing looks like it arrived late. Short
## of one at the end because the crowd is the shot — a flash that swallows the
## knights it is killing hides the only thing worth looking at.
const START_SHARE := 0.12
const END_SHARE := 0.8
## How bright the core gets. The shader fades the rim away on its own, so this
## is the middle of the flash rather than the whole of it, and it is over one on
## purpose: the middle should blow out to white while the edge is still colour.
const PEAK_ALPHA := 1.7

var _radius := 1.0
var _elapsed := 0.0
var _material: ShaderMaterial


## Builds a flash at a point. Not parented here: EventManager adopts it, so one
## place decides what is on screen and what drives it.
static func create(at: Vector3, radius: float, color: Color) -> BlastEffect:
	if radius <= 0.0:
		push_error("BlastEffect: needs a positive radius, got %f." % radius)
		return null

	var effect := BlastEffect.new()
	effect._radius = radius

	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	# Coarse on purpose: it is on screen for about a second and always softened
	# by its own transparency.
	sphere.radial_segments = 20
	sphere.rings = 10
	effect.mesh = sphere

	var material := ShaderMaterial.new()
	material.shader = load("res://assets/materials/blast.gdshader")
	material.set_shader_parameter("core_color", Vector3(color.r, color.g, color.b))
	material.set_shader_parameter("strength", PEAK_ALPHA)
	effect._material = material
	effect.material_override = material

	effect.position = at
	effect.scale = Vector3.ONE * radius * START_SHARE
	return effect


## One frame of the flash. Returns false once it has burned out.
func advance(delta: float) -> bool:
	_elapsed += delta
	var t := _elapsed / DURATION
	if t >= 1.0:
		queue_free()
		return false

	# Fast out of the gate and slowing down, the way a shockwave loses to the air.
	var eased := 1.0 - pow(1.0 - t, 3.0)
	scale = Vector3.ONE * _radius * lerpf(START_SHARE, END_SHARE, eased)
	# Squared, so it is brightest while it is still small and is nearly gone by
	# the time it is wide enough to cover anybody.
	var fade := 1.0 - t
	_material.set_shader_parameter("strength", PEAK_ALPHA * fade * fade)
	return true
