class_name MeteorProjectile
extends Node3D
## The rock on its way down: a spinning boulder with a burning halo and a tail,
## which calls back when it lands.
##
## The meteor takes time to arrive on purpose. An event that kills the instant
## it is triggered has nothing to look at and nothing to react to; a rock
## falling out of the sky is the shot, and later it is also the warning that
## lets the crowd run.
##
## It advances on **simulation** time, not on frame time, because where it is
## decides when people die, and that has to follow from the seed rather than
## from the frame rate. Pausing freezes it in the air and the speed ladder
## carries it along with everything else.
##
## Which is why it is drawn the same way the crowd is: the tick decides where it
## is, and render(alpha) puts it between the last two ticks for this frame.
## Without that it crosses the sky in twenty steps a second while the knights
## underneath it move smoothly, which is precisely the stutter that made the
## crowd look wrong before interpolation was added.

## How long the fall takes, in simulation seconds. Slow enough to watch, and
## slow enough to be a warning once the crowd learns to run.
const FALL_SECONDS := 3.2
## Entry height as a share of the blast radius, with a floor for small meteors,
## and how far the entry point is pushed sideways as a share of that height.
## Straight down reads as a lift, not as a meteor.
const ENTRY_HEIGHT_SHARE := 3.2
const MIN_ENTRY_HEIGHT := 340.0
const ENTRY_TILT := 0.55

## Rock radius as a share of the blast radius, and the halo as a share of the
## rock. The rock has to stay a clear solid ball at the centre of the fire.
const ROCK_SHARE := 0.17
const HALO_START := 1.35
const HALO_END := 1.9
## Faint on purpose. A bright halo the size of the rock swallows it, and the
## rock is the thing that has to stay a clear solid ball at the centre.
const HALO_STRENGTH := 0.45
const TAIL_STRENGTH := 0.4

## Tail length in rock radii, at the start and at the end of the fall. It grows
## as the thing gets faster.
const TAIL_START := 4.0
const TAIL_END := 11.0

const SPIN := 2.4

const FIRE_COLOR := Color(1.0, 0.55, 0.16)

var _from := Vector3.ZERO
var _to := Vector3.ZERO
var _elapsed := 0.0
## Where the last two ticks put it, so a frame can be drawn between them.
var _previous := Vector3.ZERO
var _current := Vector3.ZERO
var _rock_radius := 1.0
var _spin_axis := Vector3.UP
var _on_impact := Callable()

var _rock: MeshInstance3D
var _halo: MeshInstance3D
var _tail: MeshInstance3D


## Builds a meteor aimed at `at`, ready to be adopted by the event manager.
## `on_impact` is called once, the moment it lands.
static func launch(at: Vector3, blast_radius: float, rng: RandomNumberGenerator,
		on_impact: Callable) -> MeteorProjectile:
	if blast_radius <= 0.0 or not on_impact.is_valid():
		push_error("MeteorProjectile: needs a positive radius and a valid impact callback.")
		return null

	var meteor := MeteorProjectile.new()
	meteor._to = at
	meteor._rock_radius = blast_radius * ROCK_SHARE
	meteor._on_impact = on_impact

	# Comes in at an angle, from a direction picked per meteor.
	var bearing := rng.randf() * TAU
	var height := maxf(MIN_ENTRY_HEIGHT, blast_radius * ENTRY_HEIGHT_SHARE)
	var reach := height * ENTRY_TILT
	meteor._from = at + Vector3(sin(bearing) * reach, height, cos(bearing) * reach)
	meteor._spin_axis = Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
		rng.randf_range(-1.0, 1.0)).normalized()

	meteor._build(rng)
	meteor._previous = meteor._from
	meteor._current = meteor._from
	meteor.position = meteor._from
	meteor._aim()
	return meteor


## One simulation step. Returns false once it has landed and is finished with.
func advance(delta: float) -> bool:
	_elapsed += delta
	var t := _elapsed / FALL_SECONDS
	_previous = _current
	if t >= 1.0:
		_current = _to
		position = _to
		var impact := _on_impact
		# Cleared first: a callback that triggers something else must not be able
		# to reach a meteor that has already landed.
		_on_impact = Callable()
		queue_free()
		if impact.is_valid():
			impact.call()
		return false

	# Squared, which is what constant acceleration looks like: it leaves slowly
	# and arrives fast, instead of drifting down at one speed.
	_current = _from.lerp(_to, t * t)
	position = _current
	_rock.rotate(_spin_axis, SPIN * delta)
	# It heats up and its tail draws out as it comes in.
	_halo.scale = Vector3.ONE * _rock_radius * lerpf(HALO_START, HALO_END, t)
	# The cone is modelled one tail long, so stretching it means scaling its own
	# axis and pushing it back by half of what it grew, to keep its wide end on
	# the rock rather than out in front of it.
	var tail := _rock_radius * lerpf(TAIL_START, TAIL_END, t)
	_tail.scale = Vector3(1.0, tail / (_rock_radius * TAIL_START), 1.0)
	_tail.position = Vector3(0.0, 0.0, tail * 0.5)
	return true


## Draws this frame between the last two ticks. See the note at the top: the
## tick owns where it is, this owns how it looks getting there.
func render(alpha: float) -> void:
	position = _previous.lerp(_current, clampf(alpha, 0.0, 1.0))


## Points the whole thing along its own flight, so the tail trails behind rather
## than sticking out sideways.
func _aim() -> void:
	var direction := (_to - _from).normalized()
	if direction.length_squared() < 0.0001:
		return
	# looking_at needs an up vector that is not the direction itself. A meteor is
	# never quite vertical, but a caller could still aim one straight down.
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.BACK
	basis = Basis.looking_at(direction, up)


func _build(rng: RandomNumberGenerator) -> void:
	_rock = MeshInstance3D.new()
	_rock.mesh = BlobMesh.build(_rock_radius, rng.randi())
	var stone := StandardMaterial3D.new()
	stone.vertex_color_use_as_albedo = true
	stone.roughness = 1.0
	stone.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Faintly glowing from the inside, so it is not a black dot against the sky.
	stone.emission_enabled = true
	stone.emission = FIRE_COLOR
	stone.emission_energy_multiplier = 0.35
	_rock.material_override = stone
	add_child(_rock)

	_halo = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 1.0
	ball.height = 2.0
	ball.radial_segments = 14
	ball.rings = 7
	_halo.mesh = ball
	_halo.material_override = _fire_material(HALO_STRENGTH)
	_halo.scale = Vector3.ONE * _rock_radius * HALO_START
	add_child(_halo)

	# A cone whose base sits on the rock and whose point trails behind it. The
	# mesh is built along Y, so it is turned to lie along +Z, which is backwards
	# once the projectile is aimed.
	_tail = MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = _rock_radius * 1.25
	cone.height = _rock_radius * TAIL_START
	cone.radial_segments = 12
	cone.rings = 1
	_tail.mesh = cone
	_tail.material_override = _fire_material(TAIL_STRENGTH)
	_tail.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	_tail.position = Vector3(0.0, 0.0, cone.height * 0.5)
	add_child(_tail)


## The same additive shader the blast uses: bright in the middle, gone at the
## silhouette, which is what stops a sphere reading as a painted ball.
func _fire_material(strength: float) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/materials/blast.gdshader")
	material.set_shader_parameter("core_color", Vector3(FIRE_COLOR.r, FIRE_COLOR.g, FIRE_COLOR.b))
	material.set_shader_parameter("strength", strength)
	return material
