class_name MushroomCloud
extends Node3D
## The column that stands up out of a big impact, built to the shape a real one
## has: a turbulent stem that widens as it climbs, a cap that rolls outwards and
## flattens as it rises, and a base surge running along the ground.
##
## Made of soft blobs rather than particles. A particle system that read at this
## size would need thousands of billboards and a tuning pass of its own; forty
## blobs on a rising rig give the same silhouette, cost nothing, and hold up
## from any angle, which matters because the whole point is to fly the camera
## around it.
##
## The first version was a cylinder with nine boulders balanced on top and
## looked exactly like that. What fixed it was not more geometry: it was fading
## every blob out towards its own rim, in smoke.gdshader, so they stop cutting
## into each other and merge into one mass.
##
## It is decoration and never touches a bot. It runs on frame time so it stays
## smooth, scaled by EventManager so that pausing holds it still for the camera.

const DURATION := 14.0

## Everything is a share of the blast radius.
const CAP_HEIGHT := 2.3
const CAP_RADIUS := 0.8
## A cap is wider than it is tall, and gets more so as it spreads out.
const CAP_FLATTEN_EARLY := 0.85
const CAP_FLATTEN_LATE := 0.5
const STEM_BOTTOM := 0.15
const STEM_TOP := 0.32
## The base surge is built as concentric rings. They have to be dense enough
## that neighbours overlap, or the surge reads as a circle of separate lumps
## scattered around the crater instead of one rolling bank of dust. Reach, how
## many puffs, and how big they are, from the crater outwards.
const SKIRT_RINGS := [0.3, 0.6, 0.85, 1.0]
const SKIRT_COUNTS := [9, 15, 20, 24]
const SKIRT_SIZES := [0.3, 0.28, 0.24, 0.2]
const SKIRT_REACH := 1.2

const CAP_RING := 9
const CAP_INNER := 5
const STEM_PUFFS := 13

## Blob shape for smoke: rounder and smoother than the meteor, which wants to
## look like a rock.
const SMOKE_SIDES := 14
const SMOKE_RINGS := 9
const SMOKE_JITTER := 0.22

## How many distinct blobs exist. Every puff in every cloud picks one of these
## and turns it to a random angle, which is indistinguishable from ninety unique
## ones and is the difference between a thirty millisecond impact and a four
## millisecond one. Shape is what a blob is for; a blob seen twice at different
## angles and sizes is not a blob seen twice.
const SMOKE_VARIANTS := 8
## Fixed, so the shapes are the same in every run and every seed. They are not
## part of the simulation and must not draw from anything that is.
const SMOKE_MESH_SEED := 0x5eed

## Hot for the first moment, then cold. The top of the column is lighter than
## its base, which is most of what makes it read as smoke and not as stone.
const FIRE := Color(1.0, 0.45, 0.12)
const SMOKE := Color(0.30, 0.29, 0.30)
const COOLING := 0.16

## Built once for the whole process and shared by every cloud. Meshes are
## resources, so this is eight of them, not eight per explosion.
static var _blobs: Array[ArrayMesh] = []

var _radius := 1.0
var _elapsed := 0.0
var _material: ShaderMaterial

var _cap: Node3D
var _skirt: Node3D
## Stem puffs with the fraction of the stem each one sits at, and its width
## there. Positioned every frame rather than scaled as a group: stretching the
## group would smear round puffs into ellipsoids.
var _stem: Array[MeshInstance3D] = []
var _stem_at := PackedFloat32Array()
var _stem_width := PackedFloat32Array()


## Builds a cloud at ground level. Not parented here: EventManager adopts it, so
## one place decides what is on screen and what drives it.
static func create(at: Vector3, radius: float, rng: RandomNumberGenerator) -> MushroomCloud:
	if radius <= 0.0 or rng == null:
		push_error("MushroomCloud: needs a positive radius and a generator, got %f." % radius)
		return null

	var cloud := MushroomCloud.new()
	cloud._radius = radius
	cloud.position = at
	cloud._build(rng)
	cloud.advance(0.0)
	return cloud


## One frame of billowing. Returns false once it has faded out.
func advance(delta: float) -> bool:
	_elapsed += delta
	var t := _elapsed / DURATION
	if t > 1.0:
		queue_free()
		return false

	# Fast off the ground and slowing as it goes, which is what makes it read as
	# something heavy being pushed up rather than something floating.
	var climb := 1.0 - pow(1.0 - t, 2.4)
	var height := _radius * CAP_HEIGHT * climb

	# The cap keeps growing and flattening long after it has stopped rising, and
	# turns over slowly the whole time.
	var spread := lerpf(0.3, 1.0, 1.0 - pow(1.0 - minf(t * 1.5, 1.0), 2.0))
	var flatten := lerpf(CAP_FLATTEN_EARLY, CAP_FLATTEN_LATE, t)
	_cap.position.y = height
	_cap.scale = Vector3(spread, spread * flatten, spread)
	_cap.rotate_y(0.1 * delta)

	# The stem is drawn out under the cap, thin at the bottom and thick at the
	# top, so the two look like one thing.
	for i in _stem.size():
		var at := _stem_at[i]
		var puff := _stem[i]
		puff.position.y = height * at
		puff.scale = Vector3.ONE * _stem_width[i] * lerpf(0.45, 1.0, climb)

	# The base surge runs out along the ground and thins as it goes.
	var surge := 1.0 - pow(1.0 - minf(t * 2.0, 1.0), 2.0)
	_skirt.scale = Vector3(lerpf(0.12, 1.0, surge), lerpf(0.12, 0.6, surge),
		lerpf(0.12, 1.0, surge))

	# Hot for the first moments, then cold smoke that thins out and goes.
	var cooled := clampf(t / COOLING, 0.0, 1.0)
	var fade := clampf((1.0 - t) / 0.4, 0.0, 1.0)
	var tint := FIRE.lerp(SMOKE, cooled)
	_material.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	_material.set_shader_parameter("alpha", fade)
	_material.set_shader_parameter("glow", 3.0 * (1.0 - cooled))
	return true


func _build(rng: RandomNumberGenerator) -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://assets/materials/smoke.gdshader")
	_material.set_shader_parameter("tint", Vector3(SMOKE.r, SMOKE.g, SMOKE.b))
	_material.set_shader_parameter("alpha", 1.0)
	_material.set_shader_parameter("glow", 3.0)

	_build_stem(rng)
	_build_cap(rng)
	_build_skirt(rng)


func _build_stem(rng: RandomNumberGenerator) -> void:
	for i in STEM_PUFFS:
		var at := float(i) / float(STEM_PUFFS - 1)
		# Wider towards the top, so the column flares into the cap instead of
		# ending in it.
		var width := _radius * lerpf(STEM_BOTTOM, STEM_TOP, pow(at, 0.7))
		var puff := _puff(rng, 1.0, _shade(at))
		# A little sideways wander, which is what stops it looking machined.
		var wander := width * 0.35
		puff.position = Vector3(rng.randf_range(-wander, wander), 0.0,
			rng.randf_range(-wander, wander))
		add_child(puff)
		_stem.append(puff)
		_stem_at.append(at)
		_stem_width.append(width)


func _build_cap(rng: RandomNumberGenerator) -> void:
	_cap = Node3D.new()
	add_child(_cap)

	# An outer ring that rolls over, an inner ring that fills it, and one on top,
	# which between them give the flattened dome a real cap has.
	for i in CAP_RING:
		var angle := TAU * float(i) / float(CAP_RING)
		var reach := _radius * CAP_RADIUS * rng.randf_range(0.88, 1.0)
		var puff := _puff(rng, _radius * 0.3 * rng.randf_range(0.8, 1.2), _shade(0.75))
		# Sitting a little low, so the outside of the cap curls under.
		puff.position = Vector3(sin(angle) * reach, _radius * rng.randf_range(-0.14, 0.0),
			cos(angle) * reach)
		_cap.add_child(puff)

	for i in CAP_INNER:
		var angle := TAU * float(i) / float(CAP_INNER) + 0.4
		var reach := _radius * CAP_RADIUS * 0.45
		var puff := _puff(rng, _radius * 0.32 * rng.randf_range(0.85, 1.15), _shade(0.95))
		puff.position = Vector3(sin(angle) * reach, _radius * rng.randf_range(0.06, 0.18),
			cos(angle) * reach)
		_cap.add_child(puff)

	var crown := _puff(rng, _radius * 0.34, _shade(1.0))
	crown.position = Vector3(0.0, _radius * 0.14, 0.0)
	_cap.add_child(crown)


func _build_skirt(rng: RandomNumberGenerator) -> void:
	_skirt = Node3D.new()
	add_child(_skirt)
	for ring in SKIRT_RINGS.size():
		var share: float = SKIRT_RINGS[ring]
		var count: int = SKIRT_COUNTS[ring]
		var size: float = SKIRT_SIZES[ring]
		# Offset ring to ring, so the seams of one sit behind the middle of the
		# next and the whole thing closes up.
		var twist := TAU * float(ring) * 0.37
		for i in count:
			var angle := TAU * float(i) / float(count) + twist
			# Small jitter only: enough to break the circle, not enough to open
			# gaps between neighbours.
			var reach := _radius * SKIRT_REACH * share * rng.randf_range(0.94, 1.06)
			var puff := _puff(rng, _radius * size * rng.randf_range(0.85, 1.15), _shade(0.15))
			puff.position = Vector3(sin(angle) * reach, _radius * rng.randf_range(0.0, 0.06),
				cos(angle) * reach)
			_skirt.add_child(puff)


## One blob of smoke: a shared shape, turned to its own angle, scaled to its own
## size and given its own brightness through an instance uniform.
func _puff(rng: RandomNumberGenerator, size: float, shade: Color) -> MeshInstance3D:
	var pool := _pool()
	var puff := MeshInstance3D.new()
	puff.mesh = pool[rng.randi() % pool.size()]
	puff.material_override = _material
	# Turned in all three axes. Eight shapes at a random attitude read as many
	# more, and a lumpy ball has no orientation to get wrong.
	puff.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	puff.scale = Vector3.ONE * size
	puff.set_instance_shader_parameter("shade", Vector3(shade.r, shade.g, shade.b))
	return puff


## The shared blobs, carved the first time a cloud is built. Unit radius: size
## is a scale on the instance, so one shape serves a stem puff and a cap.
static func _pool() -> Array[ArrayMesh]:
	if not _blobs.is_empty():
		return _blobs
	for i in SMOKE_VARIANTS:
		# White, because brightness now arrives per instance. The vertex colours
		# BlobMesh writes are ignored by smoke.gdshader.
		_blobs.append(BlobMesh.build(1.0, SMOKE_MESH_SEED + i, Color.WHITE, Color.WHITE,
			SMOKE_SIDES, SMOKE_RINGS, SMOKE_JITTER, true))
	return _blobs


## Smoke is dirty at the bottom and light at the top, where it is thinner and
## catches the sky.
func _shade(height: float) -> Color:
	var value := lerpf(0.42, 1.2, clampf(height, 0.0, 1.0))
	return Color(value, value * 0.98, value * 0.96)
