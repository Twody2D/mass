class_name GroundEjecta
extends Node3D
## Clods of earth and stone thrown up by the impact itself, all at once and
## scattered in every direction — the one part of the impact that is dirt
## and rock rather than light. The flash burns out in a second, the
## shockwave races outward along the ground, the mushroom cloud stands
## there for ten seconds after; this is what makes the very instant of the
## hit look like it hit something solid.
##
## One MultiMesh for every chunk, the same reasoning MeteorProjectile's own
## debris already uses — one draw call rather than a node each. Chunks fall
## under BotManager.GRAVITY and settle on the terrain, which makes this the
## second place in the whole meteor spectacle that has to know where the
## ground actually is. Passed in as a Callable (world.get_height), the same
## shape every other rendering effect here already takes it in — a
## rendering-side effect has no business forming an opinion about World.
##
## Short-lived on purpose: this is the moment of the hit, not a lasting
## scar. A crater that stays is a later, separate point (34); this frees
## itself well before that would need to hand anything off.

## Long enough to cover a chunk landing well below where it started, not
## just above it: the volcano is now the centre of every island's geography
## (IslandGenerator.volcano_center()) rather than a landform tucked off to
## one side, so a meteor lands next to a serious drop far more often than
## it used to, and a chunk thrown outward over the edge needs time to fall
## the whole way down, not just the ~1.3 s a chunk landing near its own
## launch height would need (see KICK_SPEED_MAX's own note). Raised twice
## by real failures, not derived: 2.0 -> 3.5 s when the mountain first
## existed, then 3.5 -> 5.0 s once it grew into the island's centrepiece
## and got taller doing it.
const DURATION := 5.0
const CHUNK_COUNT := 16
const SIZE_SHARE := 0.035

## Speed a chunk is thrown at, in metres per second, along a direction
## mixed between straight up and straight outward — enough upward that the
## burst reads as thrown into the air, not sprayed flat along the ground.
## Kept low enough that even the fastest, most vertical chunk is back on
## the ground well inside DURATION: at UPWARD_SHARE and KICK_SPEED_MAX this
## peaks at 1.3s of flight, not the 2s budget, so a chunk landing on lower
## ground still has room rather than getting cut off mid-fall.
const KICK_SPEED_MIN := 9.0
const KICK_SPEED_MAX := 18.0
const UPWARD_SHARE := 0.55
const SPIN_RATE := 4.0

## Each chunk starts a little off the exact centre, out to this share of
## the blast radius — a crater's worth of dirt does not all come from one
## point.
const START_SPREAD_SHARE := 0.5

const EJECTA_DARK := Color(0.22, 0.18, 0.14)
const EJECTA_LIGHT := Color(0.33, 0.27, 0.2)

var _radius := 1.0
var _elapsed := 0.0
var _origin := Vector3.ZERO
## Returns ground height at (x, z). See the class doc for why this is a
## Callable rather than a World reference.
var _ground := Callable()

var _multimesh: MultiMeshInstance3D
## Local to this node (which sits at `at` and never itself moves), one row
## per chunk — Structure of Arrays for the same reason it always is here.
var _position := PackedVector3Array()
var _velocity := PackedVector3Array()
var _spin: Array[Basis] = []
var _spin_axis: Array[Vector3] = []
var _landed := PackedByteArray()


## Builds a burst at a point. Not parented here: EventManager adopts it, so
## one place decides what is on screen and what drives it.
static func create(at: Vector3, radius: float, rng: RandomNumberGenerator,
		ground: Callable) -> GroundEjecta:
	if radius <= 0.0 or rng == null or not ground.is_valid():
		push_error("GroundEjecta: needs a positive radius, a generator and a ground function.")
		return null

	var burst := GroundEjecta.new()
	burst._radius = radius
	burst._origin = at
	burst._ground = ground
	burst.position = at
	burst._build(rng)
	return burst


## One frame of the burst. Returns false once it is done.
func advance(delta: float) -> bool:
	_elapsed += delta
	if _elapsed >= DURATION:
		queue_free()
		return false

	var mm := _multimesh.multimesh
	for i in CHUNK_COUNT:
		if _landed[i] == 1:
			continue
		_velocity[i].y -= BotManager.GRAVITY * delta
		_position[i] += _velocity[i] * delta
		_spin[i] = _spin[i].rotated(_spin_axis[i], SPIN_RATE * delta)

		var ground_y: float = _ground.call(_origin.x + _position[i].x, _origin.z + _position[i].z)
		var local_ground := ground_y - _origin.y
		if _position[i].y <= local_ground:
			_position[i].y = local_ground
			_landed[i] = 1

		mm.set_instance_transform(i, Transform3D(_spin[i], _position[i]))
	return true


func _build(rng: RandomNumberGenerator) -> void:
	_multimesh = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = BlobMesh.build(_radius * SIZE_SHARE, rng.randi(), EJECTA_DARK, EJECTA_LIGHT)
	mm.instance_count = CHUNK_COUNT
	var stone := StandardMaterial3D.new()
	stone.vertex_color_use_as_albedo = true
	stone.roughness = 1.0
	_multimesh.multimesh = mm
	_multimesh.material_override = stone
	add_child(_multimesh)

	_position.resize(CHUNK_COUNT)
	_velocity.resize(CHUNK_COUNT)
	_landed.resize(CHUNK_COUNT)
	for i in CHUNK_COUNT:
		var angle := rng.randf() * TAU
		var reach := rng.randf_range(0.0, 1.0) * _radius * START_SPREAD_SHARE
		var start := Vector3(cos(angle) * reach, 0.0, sin(angle) * reach)
		_position[i] = start

		var outward := Vector3(cos(angle), 0.0, sin(angle))
		var speed := rng.randf_range(KICK_SPEED_MIN, KICK_SPEED_MAX)
		var direction := (outward * (1.0 - UPWARD_SHARE) + Vector3.UP * UPWARD_SHARE).normalized()
		_velocity[i] = direction * speed

		_spin.append(Basis.IDENTITY)
		_spin_axis.append(Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(-1.0, 1.0),
			rng.randf_range(-1.0, 1.0)).normalized())

		mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, start))
