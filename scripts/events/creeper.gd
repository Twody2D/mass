class_name Creeper
extends Node3D
## Sneaks up on the crowd and explodes — TODO.md item 54's second joke, "1-в-1
## как в Minecraft": walk toward someone, stop and hiss once close, then go
## off in a small blast. A green blocky silhouette built from BoxMesh, the
## project's own take on the shape rather than any imported or referenced
## asset — there is no licensable "creeper model" to reuse, and this project
## already builds every other actor from primitives or an unrelated CC0 mesh.
##
## Bot-scale, not giant-scale: several of these spawn at once (see
## CreeperSwarm), and a swarm of Monster-sized things would be a second
## Monster event, not a joke. Each one is its own Node3D and its own
## advance()/render(alpha) pair adopted independently by EventManager — a
## handful of nodes for one event, nowhere near the "no nodes per bot" rule,
## which is about the ten-thousand-strong crowd, not a handful of one-off
## actors.
##
## The explosion itself is BotManager.fling()/kill() plus BlastEffect and
## GroundEjecta at a small radius — the same primitives Meteor's blast and
## Tornado's toss already reuse, just scaled down, not a new kind of harm.

const HEIGHT := 4.2
const SPEED := 4.5
const ARRIVAL_RADIUS := 6.0
const RETARGET_SECONDS := 2.5
const TARGET_ATTEMPTS := 6

## Close enough to start hissing. Deliberately tighter than the blast radius
## below it — the fuse is time to react, the same as the real thing.
const IGNITE_RADIUS := 7.0
const FUSE_SECONDS := 1.4
## How fast it pulses while fusing, purely cosmetic — the same "cheap,
## periodic, not a real simulation" trick already trusted for camera shake,
## the meteor's sparks and Tornado's own spin.
const PULSE_RATE := 9.0
const PULSE_AMOUNT := 0.12

const KILL_RADIUS := 6.0
const BLAST_RADIUS := 14.0
const TOSS_HORIZONTAL := 16.0
const TOSS_VERTICAL := 14.0
const BLAST_COLOR := Color(0.35, 0.85, 0.30)

## Safety valve: on a big enough island a creeper aimed at a bot that keeps
## moving away could in principle wander for a long time. Rather than chase
## forever it just fizzles out quietly once this much time has passed —
## nothing on screen loses anything by one creeper out of a swarm giving up.
const MAX_LIFETIME := 45.0

const BODY_DARK := Color(0.18, 0.46, 0.16)
const BODY_LIGHT := Color(0.30, 0.62, 0.24)
const FACE_DARK := Color(0.07, 0.10, 0.07)

enum _Phase { WALKING, FUSING }

var _world: World
var _bots: BotManager
var _rng: RandomNumberGenerator
var _on_report := Callable()
var _on_explode := Callable()
var _on_fuse := Callable()

var _phase := _Phase.WALKING
var _target := Vector2.ZERO
var _retarget_timer := 0.0
var _fuse_elapsed := 0.0
var _elapsed := 0.0
var _body: Node3D
var _previous := Vector3.ZERO
var _current := Vector3.ZERO


## Builds a creeper walking in from `at`. `on_report` gets a line for the
## overlay; `on_explode` is called `(at: Vector3, radius: float)` when it
## goes off, so CreeperSwarm can spawn the shared blast visuals without this
## file needing to know about EventManager at all — the same separation
## Monster/Kraken already keep with `on_shake`; `on_fuse` is called `(at:
## Vector3)` the instant it starts hissing, the same split for the sound
## that starts a beat earlier than the explosion itself.
static func start(world: World, bots: BotManager, at: Vector2,
		rng: RandomNumberGenerator, on_report: Callable, on_explode: Callable,
		on_fuse: Callable = Callable()) -> Creeper:
	if world == null or bots == null:
		push_error("Creeper: needs a world and a crowd.")
		return null
	if rng == null:
		push_error("Creeper: needs a generator.")
		return null

	var creeper := Creeper.new()
	creeper._world = world
	creeper._bots = bots
	creeper._rng = rng
	creeper._on_report = on_report
	creeper._on_explode = on_explode
	creeper._on_fuse = on_fuse
	creeper._target = at
	creeper.position = Vector3(at.x, world.get_height(at.x, at.y), at.y)
	creeper._previous = creeper.position
	creeper._current = creeper.position
	creeper._build()
	return creeper


## One simulation step. Returns false and frees itself once it has exploded
## (or given up) — the same finite-lifetime contract Tornado already uses,
## not Monster's "stay forever" landmark.
func advance(delta: float) -> bool:
	_elapsed += delta
	if _elapsed >= MAX_LIFETIME:
		queue_free()
		return false

	match _phase:
		_Phase.WALKING:
			_previous = _current
			_move(delta)
			_current = position
			if not _bots.bots_within(position.x, position.z, IGNITE_RADIUS).is_empty():
				_phase = _Phase.FUSING
				_fuse_elapsed = 0.0
				_report("A creeper hisses at (%d, %d)" % [roundi(position.x), roundi(position.z)])
				if _on_fuse.is_valid():
					_on_fuse.call(position)
		_Phase.FUSING:
			_previous = _current
			_current = position
			_fuse_elapsed += delta
			var pulse := 1.0 + sin(_fuse_elapsed * PULSE_RATE) * PULSE_AMOUNT
			_body.scale = Vector3.ONE * pulse
			if _fuse_elapsed >= FUSE_SECONDS:
				_explode()
				return false
	return true


func render(alpha: float) -> void:
	position = _previous.lerp(_current, clampf(alpha, 0.0, 1.0))


func _move(delta: float) -> void:
	_retarget_timer -= delta
	var here := Vector2(position.x, position.z)
	if _retarget_timer <= 0.0 or here.distance_to(_target) <= ARRIVAL_RADIUS:
		_pick_target()

	var to_target := _target - here
	var length := to_target.length()
	if length < 0.0001:
		return
	var dir := to_target / length
	var step := minf(SPEED * delta, length)
	var nx := position.x + dir.x * step
	var nz := position.z + dir.y * step
	position = Vector3(nx, _world.get_height(nx, nz), nz)
	basis = Basis.looking_at(Vector3(dir.x, 0.0, dir.y), Vector3.UP)


func _pick_target() -> void:
	_retarget_timer = RETARGET_SECONDS
	for _attempt in TARGET_ATTEMPTS:
		if _bots.count == 0:
			break
		var i := _rng.randi() % _bots.count
		if _bots.alive[i] == 1:
			_target = Vector2(_bots.pos_x[i], _bots.pos_z[i])
			return
	_target = _world.random_land_point(_rng)


## Kills within KILL_RADIUS, throws whoever survives further out through
## BotManager.fling() — the same call Meteor's blast and Tornado's toss
## already use — and hands the blast point up to CreeperSwarm to draw.
func _explode() -> void:
	var here := Vector2(position.x, position.z)
	var killed := 0
	var thrown := 0
	for i in _bots.bots_within(here.x, here.y, BLAST_RADIUS):
		if _bots.alive[i] == 0:
			continue
		var dx := _bots.pos_x[i] - here.x
		var dz := _bots.pos_z[i] - here.y
		if dx * dx + dz * dz <= KILL_RADIUS * KILL_RADIUS:
			if _bots.kill(i):
				killed += 1
			continue
		if _bots.fling(i, here.x, here.y, TOSS_HORIZONTAL, TOSS_VERTICAL):
			thrown += 1

	if _on_explode.is_valid():
		_on_explode.call(Vector3(here.x, position.y, here.y), BLAST_RADIUS)
	_report("A creeper detonates at (%d, %d): %d killed, %d thrown"
		% [roundi(here.x), roundi(here.y), killed, thrown])
	queue_free()


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


## A green blocky body and a slightly darker blocky head with two dark
## squares for a face — the whole silhouette in five BoxMesh parts, standing
## on its own origin.
func _build() -> void:
	_body = Node3D.new()
	add_child(_body)

	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = BODY_LIGHT
	body_material.roughness = 1.0

	var torso := MeshInstance3D.new()
	torso.mesh = BoxMesh.new()
	(torso.mesh as BoxMesh).size = Vector3(HEIGHT * 0.34, HEIGHT * 0.62, HEIGHT * 0.22)
	torso.position = Vector3(0.0, HEIGHT * 0.31, 0.0)
	torso.material_override = body_material
	_body.add_child(torso)

	var head_material := StandardMaterial3D.new()
	head_material.albedo_color = BODY_DARK
	head_material.roughness = 1.0
	var head := MeshInstance3D.new()
	head.mesh = BoxMesh.new()
	(head.mesh as BoxMesh).size = Vector3(HEIGHT * 0.30, HEIGHT * 0.30, HEIGHT * 0.30)
	head.position = Vector3(0.0, HEIGHT * 0.77, 0.0)
	head.material_override = head_material
	_body.add_child(head)

	var face_material := StandardMaterial3D.new()
	face_material.albedo_color = FACE_DARK
	face_material.roughness = 1.0
	for side: float in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		eye.mesh = BoxMesh.new()
		(eye.mesh as BoxMesh).size = Vector3(HEIGHT * 0.07, HEIGHT * 0.09, HEIGHT * 0.02)
		eye.position = Vector3(side * HEIGHT * 0.08, HEIGHT * 0.80, HEIGHT * 0.15)
		eye.material_override = face_material
		_body.add_child(eye)

	var mouth := MeshInstance3D.new()
	mouth.mesh = BoxMesh.new()
	(mouth.mesh as BoxMesh).size = Vector3(HEIGHT * 0.10, HEIGHT * 0.14, HEIGHT * 0.02)
	mouth.position = Vector3(0.0, HEIGHT * 0.70, HEIGHT * 0.15)
	mouth.material_override = face_material
	_body.add_child(mouth)

	for side: float in [-1.0, 1.0]:
		var leg := MeshInstance3D.new()
		leg.mesh = BoxMesh.new()
		(leg.mesh as BoxMesh).size = Vector3(HEIGHT * 0.13, HEIGHT * 0.22, HEIGHT * 0.13)
		leg.position = Vector3(side * HEIGHT * 0.11, HEIGHT * 0.11, 0.0)
		leg.material_override = head_material
		_body.add_child(leg)
