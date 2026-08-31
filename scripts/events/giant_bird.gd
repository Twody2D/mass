class_name GiantBird
extends Node3D
## A giant chicken drops out of the sky, tramples whoever is underfoot, and
## gets fought off by the crowd — TODO.md item 54, the first of the
## "absurdly silly, not epic" series the owner asked for by name. Everything
## about it is Monster's own shape (49) at a fraction of the scale and the
## stakes: it falls, it walks, it stomps, archers and melee hurt it, it
## tips over once beaten. The joke is entirely in what it looks like and how
## quickly the crowd sends it packing, not in a new mechanic.
##
## Built from primitives (BlobMesh blobs plus a couple of BoxMesh parts)
## rather than an imported model, unlike Monster/Kraken. TODO.md's own
## lesson from the first Monster attempt was "primitives lose to a sculpted
## asset for a coherent kaiju silhouette" — but a giant chicken is supposed
## to look like a silly toy, in the same boxy, vertex-coloured language the
## knights and every other primitive-built part of this project already
## speak, not like a creature. The lesson does not apply to a joke.
##
## Runs on the simulation clock, the same advance(delta)/render(alpha) split
## as Monster and Kraken, for the same reason: where it is decides who gets
## stomped, which has to be reproducible from the seed.

## A fraction of Monster's 128 m — big enough to loom over the crowd, nowhere
## near epic. "Не эпичные" was the owner's own wording for this whole series.
const HEIGHT := 40.0

## Falls in from directly overhead rather than an angled meteor-style arc: a
## chicken dropping straight out of a clear sky reads as more absurd than a
## trajectory would, and it is one less thing to compute.
const DROP_HEIGHT := 220.0
const FALL_GRAVITY := 60.0

const SPEED := 10.0
const ARRIVAL_RADIUS := 14.0
const RETARGET_SECONDS := 3.5
const TARGET_ATTEMPTS := 6

## Quick and silly rather than a real boss fight: a few dozen archers or a
## knot of melee fighters bring it down in well under a minute. See
## Monster's own MAX_HEALTH note for why a per-attacker cap matters at all —
## the same reasoning applies here, just tuned for a much shorter fight.
const MAX_HEALTH := 900.0
const ARCHER_DAMAGE_PER_SECOND := 3.0
const MELEE_DAMAGE_PER_SECOND := 8.0
const MAX_EFFECTIVE_ARCHERS := 20
const MAX_EFFECTIVE_MELEE := 12
const ATTACK_RANGE := 70.0
const STOMP_RADIUS := 16.0
const MELEE_RANGE := 24.0
const PANIC_RADIUS := 55.0
const FLEE_DISTANCE := 60.0
const SWEEP_SECONDS := 0.2

const FALL_SECONDS := 1.0

const BODY_LIGHT := Color(0.94, 0.90, 0.78)
const BODY_DARK := Color(0.80, 0.74, 0.58)
const BEAK_COLOR := Color(0.95, 0.62, 0.08)

enum _Phase { DROPPING, ALIVE, TOPPLING, DEAD }

var _world: World
var _bots: BotManager
var _rng: RandomNumberGenerator
var _on_report := Callable()
var _on_shake := Callable()

var _phase := _Phase.DROPPING
var _fall_vy := 0.0
var _ground_y := 0.0
var _target := Vector2.ZERO
var _retarget_timer := 0.0
var _sweep_timer := 0.0
var _fall_elapsed := 0.0
var _health := MAX_HEALTH
var _max_health := MAX_HEALTH
var _stomped := 0
## Where the last two ticks put it, so a frame can be drawn between them —
## see Monster's own class doc.
var _previous := Vector3.ZERO
var _current := Vector3.ZERO


## Builds a chicken plummeting toward `at`, ready to be adopted by the event
## manager. `on_report` is called with a line for the overlay; `on_shake`
## with `(at, strength)` for the landing and the fall.
static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable) -> GiantBird:
	if world == null or bots == null:
		push_error("GiantBird: needs a world and a crowd.")
		return null
	if health <= 0.0:
		push_error("GiantBird: needs positive health, got %f." % health)
		return null
	if rng == null:
		push_error("GiantBird: needs a generator.")
		return null

	var bird := GiantBird.new()
	bird._world = world
	bird._bots = bots
	bird._rng = rng
	bird._health = health
	bird._max_health = health
	bird._on_report = on_report
	bird._on_shake = on_shake
	bird._target = at
	bird._ground_y = world.get_height(at.x, at.y)
	bird.position = Vector3(at.x, bird._ground_y + DROP_HEIGHT, at.y)
	bird._previous = bird.position
	bird._current = bird.position
	bird._build()
	return bird


## One simulation step. Always returns true, the same "never says it is
## finished, just stops doing anything" contract as Monster's own advance().
func advance(delta: float) -> bool:
	match _phase:
		_Phase.DROPPING:
			_previous = _current
			_fall_vy -= FALL_GRAVITY * delta
			position.y += _fall_vy * delta
			if position.y <= _ground_y:
				position.y = _ground_y
				_phase = _Phase.ALIVE
				if _on_shake.is_valid():
					_on_shake.call(position, 0.5)
				_report("A chicken the size of a house lands at (%d, %d)"
					% [roundi(position.x), roundi(position.z)])
			_current = position
		_Phase.ALIVE:
			_previous = _current
			_move(delta)
			_current = position

			_sweep_timer += delta
			if _sweep_timer >= SWEEP_SECONDS:
				_sweep()
				_sweep_timer = 0.0

			if _health <= 0.0:
				_begin_fall()
		_Phase.TOPPLING:
			_advance_fall(delta)
		_Phase.DEAD:
			pass
	return true


## Draws this frame between the last two ticks. See Monster's own render().
func render(alpha: float) -> void:
	if _phase == _Phase.DROPPING or _phase == _Phase.ALIVE:
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


## Heads for a living bot's own position most of the time, the same reasoning
## Monster's own _pick_target() already has: touring empty terrain is not the
## joke, walking straight at the crowd is.
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


## Stomps whoever is underfoot, frightens whoever is close, lets warriors and
## spearmen already at MELEE_RANGE stand and fight instead of fleeing, and
## takes whatever damage archers and melee fighters in range have earned it —
## the same shape as Monster's own _sweep(), just with smaller radii and a
## much shorter fight.
func _sweep() -> void:
	var here := Vector2(position.x, position.z)

	for i in _bots.bots_within(here.x, here.y, STOMP_RADIUS):
		if _bots.kill(i):
			_stomped += 1

	var idle := BotManager.State.IDLE
	var moving := BotManager.State.MOVING
	var fighting := BotManager.State.FIGHTING
	var warrior := GameConfig.CLASS_WARRIOR
	var spearman := GameConfig.CLASS_SPEARMAN
	var melee_range_squared := MELEE_RANGE * MELEE_RANGE
	var melee_fighters := 0

	for i in _bots.bots_within(here.x, here.y, PANIC_RADIUS):
		if _bots.alive[i] == 0:
			continue
		var cls: int = _bots.bot_class[i]
		if cls == warrior or cls == spearman:
			var dx := _bots.pos_x[i] - here.x
			var dz := _bots.pos_z[i] - here.y
			if dx * dx + dz * dz <= melee_range_squared:
				_bots.state[i] = fighting
				melee_fighters += 1
				continue
			if _bots.state[i] == fighting:
				_bots.state[i] = idle
				continue
		var bot_state: int = _bots.state[i]
		if bot_state != idle and bot_state != moving:
			continue
		_bots.scare(i, here.x, here.y, FLEE_DISTANCE)

	var archers := 0
	for i in _bots.bots_within(here.x, here.y, ATTACK_RANGE):
		if _bots.alive[i] == 1 and _bots.bot_class[i] == GameConfig.CLASS_ARCHER:
			archers += 1

	var effective_archers := mini(archers, MAX_EFFECTIVE_ARCHERS)
	var effective_melee := mini(melee_fighters, MAX_EFFECTIVE_MELEE)
	var damage := effective_archers * ARCHER_DAMAGE_PER_SECOND \
		+ effective_melee * MELEE_DAMAGE_PER_SECOND
	_health = maxf(0.0, _health - damage * SWEEP_SECONDS)

	_report("Chicken: %d/%d health, %d archers + %d melee attacking, %d stomped"
		% [ceili(_health), int(_max_health), archers, melee_fighters, _stomped])


func _begin_fall() -> void:
	_phase = _Phase.TOPPLING
	_fall_elapsed = 0.0
	if _on_shake.is_valid():
		_on_shake.call(position, 0.6)


## Toppling around its own local X axis, the same trick Monster's own
## _advance_fall() and a knight's own corpse already use.
func _advance_fall(delta: float) -> void:
	_fall_elapsed += delta
	var t := clampf(_fall_elapsed / FALL_SECONDS, 0.0, 1.0)
	rotation.x = lerpf(0.0, PI * 0.5, t * t)
	if t >= 1.0:
		_phase = _Phase.DEAD
		_report("The chicken keels over: %d stomped before the crowd ran it off" % _stomped)


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


## A round body, a smaller round head, a wedge of a beak, two stubby wings
## and two legs — every part a BlobMesh or a plain BoxMesh, the same
## primitive language the rest of the project already builds with. Standing
## on its own origin, facing -Z, the same convention KnightMesh and Monster
## both already assume.
func _build() -> void:
	var body_material := StandardMaterial3D.new()
	body_material.albedo_color = BODY_LIGHT
	body_material.roughness = 1.0

	var torso := MeshInstance3D.new()
	torso.mesh = BlobMesh.build(HEIGHT * 0.30, _rng.randi(), BODY_DARK, BODY_LIGHT, 10, 7, 0.2)
	torso.position = Vector3(0.0, HEIGHT * 0.42, 0.0)
	torso.scale = Vector3(1.0, 1.3, 0.95)
	torso.material_override = body_material
	add_child(torso)

	var head := MeshInstance3D.new()
	head.mesh = BlobMesh.build(HEIGHT * 0.15, _rng.randi() + 1, BODY_DARK, BODY_LIGHT, 8, 5, 0.18)
	head.position = Vector3(0.0, HEIGHT * 0.74, HEIGHT * 0.12)
	head.material_override = body_material
	add_child(head)

	var beak_material := StandardMaterial3D.new()
	beak_material.albedo_color = BEAK_COLOR
	beak_material.roughness = 1.0
	var beak := MeshInstance3D.new()
	beak.mesh = BoxMesh.new()
	(beak.mesh as BoxMesh).size = Vector3(HEIGHT * 0.06, HEIGHT * 0.05, HEIGHT * 0.12)
	beak.position = Vector3(0.0, HEIGHT * 0.72, HEIGHT * 0.24)
	beak.material_override = beak_material
	add_child(beak)

	for side: float in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		wing.mesh = BoxMesh.new()
		(wing.mesh as BoxMesh).size = Vector3(HEIGHT * 0.08, HEIGHT * 0.28, HEIGHT * 0.22)
		wing.position = Vector3(side * HEIGHT * 0.28, HEIGHT * 0.42, 0.0)
		wing.rotation.z = side * 0.35
		wing.material_override = body_material
		add_child(wing)

		var leg := MeshInstance3D.new()
		leg.mesh = BoxMesh.new()
		(leg.mesh as BoxMesh).size = Vector3(HEIGHT * 0.07, HEIGHT * 0.22, HEIGHT * 0.07)
		leg.position = Vector3(side * HEIGHT * 0.09, HEIGHT * 0.11, 0.0)
		leg.material_override = beak_material
		add_child(leg)
