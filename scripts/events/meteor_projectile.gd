class_name MeteorProjectile
extends Node3D
## The rock on its way down: a spinning boulder with a burning halo and a
## layered tail, which calls back when it lands.
##
## The meteor takes time to arrive on purpose. An event that kills the instant
## it is triggered has nothing to look at and nothing to react to; a rock
## falling out of the sky is the shot, and later it is also the warning that
## lets the crowd run.
##
## The tail is four things, not one cone: a bright white-yellow core wrapped
## in wider, dimmer orange flame (the same two-layer trick a rocket exhaust
## or a comet's own coma already show — a single-colour cone reads as a
## painted wedge, not fire), a few soft blobs of dark smoke trailing further
## back where the flame has already thinned, and a scatter of small bright
## sparks flickering through it. Nothing here is a GPUParticles3D: this is
## one object for the whole video, so the crowd's no-nodes-per-bot budget
## does not even apply, but the project's own "no particle system" habit —
## see MushroomCloud — is kept anyway, because a handful of modelled meshes
## already do the job and hold up from any angle a camera might fly to.
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

## Flame is the outer cone, at the same radius and length the tail always
## had. Core is a second, smaller cone nested inside it — a share of the
## flame's own radius and length, not a size of its own, so it always reads
## as "inside the flame" whatever the flame currently measures.
const FLAME_STRENGTH := 0.4
const CORE_STRENGTH := 0.85
const CORE_SHARE := 0.4
const CORE_COLOR := Color(1.0, 0.95, 0.8)

## Tail length in rock radii, at the start and at the end of the fall. It grows
## as the thing gets faster.
const TAIL_START := 4.0
const TAIL_END := 11.0

## Smoke trails past where the flame cone ends, thinning out further back.
## Both spacing and size are shares of the flame's own current length, so
## the smoke stretches out with it rather than staying a fixed length while
## the flame around it grows.
const SMOKE_PUFFS := 4
const SMOKE_START_SHARE := 0.9
const SMOKE_SPACING_SHARE := 0.5
const SMOKE_SIZE_SHARE := 0.55
const SMOKE_WANDER_SHARE := 0.3
const SMOKE_FADE_PER_PUFF := 0.22
const SMOKE_COLOR := Color(0.15, 0.14, 0.14)

## Sparks scatter loosely through the flame rather than trailing behind it —
## real ones are thrown sideways off a tumbling, breaking-up surface, not
## carried straight back the way smoke is. Reach and spread are shares of
## the flame's current length and the rock's own radius.
const SPARK_COUNT := 7
const SPARK_REACH_SHARE := 0.85
const SPARK_SPREAD_SHARE := 0.9
const SPARK_SIZE_SHARE := 0.09
const SPARK_STRENGTH := 1.1
const SPARK_FLICKER_RATE := 9.0
const SPARK_COLOR := Color(1.0, 0.82, 0.4)

const SPIN := 2.4

const FIRE_COLOR := Color(1.0, 0.55, 0.16)

## Rock emission strength at entry and at impact — a hot leading face from
## the moment it appears, brighter still by the time it lands, the same
## "grows as it comes in" shape the halo and tail already use.
const HEAT_START := 1.5
const HEAT_END := 5.0
## Constant for the whole fall: cracks are a feature of the rock, not a
## sign of how close it is to landing.
const CRACK_STRENGTH := 1.8

var _from := Vector3.ZERO
var _to := Vector3.ZERO
## Direction of travel, world space, fixed for the whole fall — the path is
## a straight line, so this is computed once rather than every tick.
var _heading := Vector3.DOWN
var _elapsed := 0.0
## Where the last two ticks put it, so a frame can be drawn between them.
var _previous := Vector3.ZERO
var _current := Vector3.ZERO
var _rock_radius := 1.0
var _spin_axis := Vector3.UP
var _on_impact := Callable()

var _rock: MeshInstance3D
var _halo: MeshInstance3D
var _tail_flame: MeshInstance3D
var _tail_core: MeshInstance3D
var _tail_smoke: Array[MeshInstance3D] = []
## Fixed sideways wander per puff, picked once at build time — only the
## distance back along the tail moves every tick.
var _smoke_wander: Array[Vector3] = []
var _tail_sparks: Array[MeshInstance3D] = []
## Each spark's own fixed spot within the scatter volume (as a share of the
## flame's current reach and the rock's own radius) and its own flicker
## phase, both picked once at build time.
var _spark_offset: Array[Vector3] = []
var _spark_phase := PackedFloat32Array()


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
	# The hot face has to track world-space "forward" as the rock tumbles, so
	# it is recomputed in the rock's own current (spinning) local space every
	# tick rather than set once — see meteor_rock.gdshader for why that space
	# is what the shader actually compares against.
	var rock_material := _rock.material_override as ShaderMaterial
	rock_material.set_shader_parameter("local_heading",
		_rock.global_transform.basis.inverse() * _heading)
	rock_material.set_shader_parameter("heat_intensity", lerpf(HEAT_START, HEAT_END, t))
	# It heats up and its tail draws out as it comes in.
	_halo.scale = Vector3.ONE * _rock_radius * lerpf(HALO_START, HALO_END, t)
	var flame_length := _rock_radius * lerpf(TAIL_START, TAIL_END, t)
	_scale_cone(_tail_flame, flame_length, _rock_radius * TAIL_START)
	_scale_cone(_tail_core, flame_length * CORE_SHARE, _rock_radius * TAIL_START * CORE_SHARE)
	_update_smoke(flame_length)
	_update_sparks(flame_length)
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
	_heading = direction
	# looking_at needs an up vector that is not the direction itself. A meteor is
	# never quite vertical, but a caller could still aim one straight down.
	var up := Vector3.UP if absf(direction.y) < 0.99 else Vector3.BACK
	basis = Basis.looking_at(direction, up)


func _build(rng: RandomNumberGenerator) -> void:
	_rock = MeshInstance3D.new()
	_rock.mesh = BlobMesh.build(_rock_radius, rng.randi())
	# A custom shader rather than StandardMaterial3D: ALBEDO/ROUGHNESS/SPECULAR
	# still go through Godot's normal lighting exactly like before (COLOR is
	# still the same dark/light facet variation BlobMesh always built), but
	# EMISSION now has to answer "is this fragment facing the way we are
	# falling" every frame, which a fixed emission colour cannot do at all.
	var stone := ShaderMaterial.new()
	stone.shader = load("res://assets/materials/meteor_rock.gdshader")
	stone.set_shader_parameter("fire_color", Vector3(FIRE_COLOR.r, FIRE_COLOR.g, FIRE_COLOR.b))
	stone.set_shader_parameter("crack_strength", CRACK_STRENGTH)
	# Offsets the crack pattern so every meteor's rock cracks differently, the
	# same reasoning the mesh itself is seeded per meteor for.
	stone.set_shader_parameter("crack_seed", rng.randf() * 100.0)
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

	_build_tail(rng)


## Flame, core, smoke and sparks, in that order — flame first so the core
## sits visibly nested inside it rather than the other way round.
func _build_tail(rng: RandomNumberGenerator) -> void:
	_tail_flame = _build_cone(_rock_radius * 1.25, _rock_radius * TAIL_START, FIRE_COLOR,
		FLAME_STRENGTH)
	add_child(_tail_flame)
	_tail_core = _build_cone(_rock_radius * 1.25 * CORE_SHARE, _rock_radius * TAIL_START * CORE_SHARE,
		CORE_COLOR, CORE_STRENGTH)
	add_child(_tail_core)

	for i in SMOKE_PUFFS:
		var puff := MeshInstance3D.new()
		puff.mesh = BlobMesh.build(_rock_radius * SMOKE_SIZE_SHARE, rng.randi(),
			Color.WHITE, Color.WHITE, 10, 6, 0.3, true)
		var material := ShaderMaterial.new()
		material.shader = load("res://assets/materials/smoke.gdshader")
		material.set_shader_parameter("tint", Vector3(SMOKE_COLOR.r, SMOKE_COLOR.g, SMOKE_COLOR.b))
		material.set_shader_parameter("alpha", 1.0)
		material.set_shader_parameter("glow", 0.0)
		puff.material_override = material
		add_child(puff)
		_tail_smoke.append(puff)
		var wander := _rock_radius * SMOKE_WANDER_SHARE
		_smoke_wander.append(Vector3(rng.randf_range(-wander, wander), rng.randf_range(-wander, wander), 0.0))

	for i in SPARK_COUNT:
		var spark := MeshInstance3D.new()
		spark.mesh = BlobMesh.build(_rock_radius * SPARK_SIZE_SHARE, rng.randi(),
			Color.WHITE, Color.WHITE, 6, 4, 0.25, true)
		spark.material_override = _fire_material(SPARK_STRENGTH, SPARK_COLOR)
		add_child(spark)
		_tail_sparks.append(spark)
		var spread := _rock_radius * SPARK_SPREAD_SHARE
		_spark_offset.append(Vector3(rng.randf_range(-spread, spread), rng.randf_range(-spread, spread),
			rng.randf_range(0.15, SPARK_REACH_SHARE)))
		_spark_phase.append(rng.randf() * TAU)


## Builds one cone, base on the rock and point trailing behind it. The mesh
## is built along Y, so it is turned to lie along +Z, which is backwards once
## the projectile itself is aimed.
func _build_cone(radius: float, length: float, color: Color, strength: float) -> MeshInstance3D:
	var cone_mesh := CylinderMesh.new()
	cone_mesh.top_radius = 0.0
	cone_mesh.bottom_radius = radius
	cone_mesh.height = length
	cone_mesh.radial_segments = 12
	cone_mesh.rings = 1
	var cone := MeshInstance3D.new()
	cone.mesh = cone_mesh
	cone.material_override = _fire_material(strength, color)
	cone.rotation = Vector3(PI * 0.5, 0.0, 0.0)
	cone.position = Vector3(0.0, 0.0, length * 0.5)
	return cone


## Stretches a cone built at `base_length` to `length`: scaling its own axis
## and pushing it back by half of what it grew, to keep its wide end on the
## rock rather than out in front of it.
func _scale_cone(cone: MeshInstance3D, length: float, base_length: float) -> void:
	cone.scale = Vector3(1.0, length / base_length, 1.0)
	cone.position = Vector3(0.0, 0.0, length * 0.5)


## Each puff sits further back than the last, at a share of the flame's own
## current reach, and fades the further back it is — smoke that has drifted
## clear of the flame has nothing left lighting it.
func _update_smoke(flame_length: float) -> void:
	for i in _tail_smoke.size():
		var reach := flame_length * (SMOKE_START_SHARE + float(i) * SMOKE_SPACING_SHARE)
		var wander: Vector3 = _smoke_wander[i]
		_tail_smoke[i].position = Vector3(wander.x, wander.y, reach)
		var material := _tail_smoke[i].material_override as ShaderMaterial
		material.set_shader_parameter("alpha", clampf(1.0 - float(i) * SMOKE_FADE_PER_PUFF, 0.0, 1.0))


## Each spark keeps its own fixed spot within the scatter volume, scaled by
## how far the flame currently reaches, and flickers on its own phase rather
## than moving — real embers thrown off a tumbling rock do not travel in
## lockstep, but they do not need to visibly relocate to read as sparks.
func _update_sparks(flame_length: float) -> void:
	for i in _tail_sparks.size():
		var offset: Vector3 = _spark_offset[i]
		_tail_sparks[i].position = Vector3(offset.x, offset.y, offset.z * flame_length)
		var flicker := 0.55 + 0.45 * sin(_elapsed * SPARK_FLICKER_RATE + _spark_phase[i])
		var material := _tail_sparks[i].material_override as ShaderMaterial
		material.set_shader_parameter("strength", SPARK_STRENGTH * flicker)


## The same additive shader the blast uses: bright in the middle, gone at the
## silhouette, which is what stops a sphere reading as a painted ball.
func _fire_material(strength: float, color: Color = FIRE_COLOR) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/materials/blast.gdshader")
	material.set_shader_parameter("core_color", Vector3(color.r, color.g, color.b))
	material.set_shader_parameter("strength", strength)
	return material
