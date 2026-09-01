class_name Horsely
extends Node3D
## A giant horse that gallops across the island — the first of a third
## batch of bosses, chosen after the second batch's own lesson (see
## ARCHITECTURE.md, "Not silhouette-legible from every angle"): a
## quadruped's body is long front-to-back, so it reads as a recognisable
## creature from a side profile as reliably as from the front, unlike a
## radially-symmetric single-eye design. Same "gigant" contract as Monster:
## one object, sim-clock advance()/render(alpha), stomps/gets shot/falls
## and stays down. The fastest and most fragile of the whole roster — a
## horse has no armour, only speed.
##
## The one twist this file adds: it rears onto its hind legs for an instant
## whenever something is actually underfoot at a sweep, a purely cosmetic
## pitch that decays back to standing over REAR_KICK_SECONDS — the same
## "cosmetic flourish tied to a real game moment" reasoning Titanoboo's
## constant wiggle does NOT use (that one runs continuously, unrelated to
## combat); this one only fires when there was something to trample. Gated
## on STOMP_RADIUS actually finding someone, not on the sweep timer itself
## (which fires every SWEEP_SECONDS regardless of contact) — otherwise it
## would rear on a fixed metronome even walking over empty ground.

## Uniform scale off the model's own longest axis — measured, not guessed,
## the same reasoning Titanoboo/Raptorous/Whormbus scale off length instead
## of height.
const MODEL_PATH := "res://assets/models/057_Horsely_Art.glb"
const MODEL_LENGTH_UNITS := 2.676
const LENGTH := 55.0

const SPEED := 15.0
const ARRIVAL_RADIUS := 7.0
const RETARGET_SECONDS := 4.0
const TARGET_ATTEMPTS := 6

## The purely cosmetic rear-up kick — see the class doc. Peak pitch and how
## long it takes to settle back to standing.
const REAR_KICK_ANGLE := 0.32
const REAR_KICK_SECONDS := 0.3

## Fast and fragile: no armour, the whole point is that it is hard to pin
## down and dangerous specifically because it keeps moving.
const MAX_HEALTH := 4500.0
const ARCHER_DAMAGE_PER_SECOND := 1.0
const MELEE_DAMAGE_PER_SECOND := 4.0
const MAX_EFFECTIVE_ARCHERS := 30
const MAX_EFFECTIVE_MELEE := 15
const ATTACK_RANGE := 64.0
const STOMP_RADIUS := 20.0
const MELEE_RANGE := 30.0
const PANIC_RADIUS := 69.0
const FLEE_DISTANCE := 73.0
const SWEEP_SECONDS := 0.2

const FALL_SECONDS := 1.3

enum _Phase { ALIVE, FALLING, DEAD }

var _world: World
var _bots: BotManager
var _rng: RandomNumberGenerator
var _on_report := Callable()
var _on_shake := Callable()

var _phase := _Phase.ALIVE
var _target := Vector2.ZERO
var _retarget_timer := 0.0
var _sweep_timer := 0.0
var _fall_elapsed := 0.0
## Real time since start, advanced every tick — read by render() to decay
## the rear-kick pitch. Not the same clock as _sweep_timer, which resets
## every sweep; this one only ever grows, the same role Titanoboo's own
## _elapsed plays for its wiggle.
var _elapsed := 0.0
## The _elapsed value at the last stomp, far enough in the past at start
## that the horse begins settled rather than rearing on its first frame.
var _rear_trigger := -1000.0
var _health := MAX_HEALTH
var _max_health := MAX_HEALTH
var _stomped := 0
var _previous := Vector3.ZERO
var _current := Vector3.ZERO


static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable) -> Horsely:
	if world == null or bots == null:
		push_error("Horsely: needs a world and a crowd.")
		return null
	if health <= 0.0:
		push_error("Horsely: needs positive health, got %f." % health)
		return null
	if rng == null:
		push_error("Horsely: needs a generator.")
		return null

	var horse := Horsely.new()
	horse._world = world
	horse._bots = bots
	horse._rng = rng
	horse._health = health
	horse._max_health = health
	horse._on_report = on_report
	horse._on_shake = on_shake
	horse._target = at
	horse.position = Vector3(at.x, world.get_height(at.x, at.y), at.y)
	horse._previous = horse.position
	horse._current = horse.position
	horse._build()
	if on_shake.is_valid():
		on_shake.call(horse.position, 0.4)
	return horse


func advance(delta: float) -> bool:
	_elapsed += delta
	match _phase:
		_Phase.ALIVE:
			_previous = _current
			_move(delta)
			_current = position

			_sweep_timer += delta
			if _sweep_timer >= SWEEP_SECONDS:
				_sweep(_sweep_timer)
				_sweep_timer = 0.0

			if _health <= 0.0:
				_begin_fall()
		_Phase.FALLING:
			_advance_fall(delta)
		_Phase.DEAD:
			pass
	return true


## The interpolated position plus the decaying rear-kick pitch — see the
## class doc. Cosmetic only: _sweep() never reads rotation, so this cannot
## change who gets hit.
func render(alpha: float) -> void:
	if _phase != _Phase.ALIVE:
		return
	position = _previous.lerp(_current, clampf(alpha, 0.0, 1.0))
	var t := clampf((_elapsed - _rear_trigger) / REAR_KICK_SECONDS, 0.0, 1.0)
	var settle := 1.0 - t
	rotation.x = REAR_KICK_ANGLE * settle * settle


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


func _sweep(elapsed: float) -> void:
	var here := Vector2(position.x, position.z)

	var underfoot := _bots.bots_within(here.x, here.y, STOMP_RADIUS)
	if not underfoot.is_empty():
		_rear_trigger = _elapsed
	for i in underfoot:
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
	_health = maxf(0.0, _health - damage * elapsed)

	_report("Horsely: %d/%d health, %d archers + %d melee attacking, %d stomped"
		% [ceili(_health), int(_max_health), archers, melee_fighters, _stomped])


func _begin_fall() -> void:
	_phase = _Phase.FALLING
	_fall_elapsed = 0.0
	if _on_shake.is_valid():
		_on_shake.call(position, 0.6)


func _advance_fall(delta: float) -> void:
	_fall_elapsed += delta
	var t := clampf(_fall_elapsed / FALL_SECONDS, 0.0, 1.0)
	rotation.x = lerpf(0.0, PI * 0.5, t * t)
	if t >= 1.0:
		_phase = _Phase.DEAD
		_report("Horsely stumbles and falls: %d stomped before archers brought it down" % _stomped)


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


func _build() -> void:
	var body: Node3D = load(MODEL_PATH).instantiate()
	body.scale = Vector3.ONE * (LENGTH / MODEL_LENGTH_UNITS)
	add_child(body)
