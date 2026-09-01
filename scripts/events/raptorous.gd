class_name Raptorous
extends Node3D
## A giant raptor that charges the island — the first of a second "many
## silly bosses" batch, from the same CC0 collection Monster/Kraken/
## Crabylon/Titanoboo/Giraffaxon already draw from (assets/CREDITS.md).
## Same "gigant" contract as Monster: one object, sim-clock advance()/
## render(alpha), stomps/gets shot/falls and stays down. Fast and fragile —
## a predator wins by reaching the crowd quickly, not by outlasting it.
##
## The one twist this file adds: it is not one constant SPEED like every
## other giant here — inside LUNGE_RANGE of wherever it is headed it breaks
## into a sprint, the last stretch of a real charge rather than a steady
## walk the whole way there.

## Uniform scale off the model's own longest axis (nose to tail) — measured,
## not guessed, the same reasoning Crabylon/Titanoboo scale off their own
## widest/longest axis instead of height.
const MODEL_PATH := "res://assets/models/016_Raptorous_Art.glb"
const MODEL_LENGTH_UNITS := 1.299397
const LENGTH := 58.0

## Steady speed while it is still closing the distance.
const SPEED := 11.0
## Once within this of its target, it lunges — the last stretch of a charge,
## not the whole approach.
const LUNGE_RANGE := 45.0
const LUNGE_SPEED_MULTIPLIER := 2.0

const ARRIVAL_RADIUS := 7.5
const RETARGET_SECONDS := 4.0
const TARGET_ATTEMPTS := 6

## Fast and fragile, the same design as Titanoboo: a predator this quick is
## meant to be dangerous in a rush, not a wall to grind through.
const MAX_HEALTH := 5000.0
const ARCHER_DAMAGE_PER_SECOND := 1.0
const MELEE_DAMAGE_PER_SECOND := 4.0
const MAX_EFFECTIVE_ARCHERS := 35
const MAX_EFFECTIVE_MELEE := 18
const ATTACK_RANGE := 68.0
const STOMP_RADIUS := 21.0
const MELEE_RANGE := 32.0
const PANIC_RADIUS := 73.0
const FLEE_DISTANCE := 77.0
const SWEEP_SECONDS := 0.2

## Quick and abrupt on purpose: a stumbling predator falling mid-charge, not
## a slow ceremonial keel-over like the tankier giants.
const FALL_SECONDS := 1.2

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
var _health := MAX_HEALTH
var _max_health := MAX_HEALTH
var _stomped := 0
var _previous := Vector3.ZERO
var _current := Vector3.ZERO


static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable) -> Raptorous:
	if world == null or bots == null:
		push_error("Raptorous: needs a world and a crowd.")
		return null
	if health <= 0.0:
		push_error("Raptorous: needs positive health, got %f." % health)
		return null
	if rng == null:
		push_error("Raptorous: needs a generator.")
		return null

	var raptor := Raptorous.new()
	raptor._world = world
	raptor._bots = bots
	raptor._rng = rng
	raptor._health = health
	raptor._max_health = health
	raptor._on_report = on_report
	raptor._on_shake = on_shake
	raptor._target = at
	raptor.position = Vector3(at.x, world.get_height(at.x, at.y), at.y)
	raptor._previous = raptor.position
	raptor._current = raptor.position
	raptor._build()
	if on_shake.is_valid():
		on_shake.call(raptor.position, 0.4)
	return raptor


func advance(delta: float) -> bool:
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


func render(alpha: float) -> void:
	if _phase == _Phase.ALIVE:
		position = _previous.lerp(_current, clampf(alpha, 0.0, 1.0))


## Identical to Monster's own _move() except for the speed: within
## LUNGE_RANGE of the target it multiplies SPEED instead of holding it
## constant the whole approach — see the class doc.
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
	var speed := SPEED * LUNGE_SPEED_MULTIPLIER if length <= LUNGE_RANGE else SPEED
	var step := minf(speed * delta, length)
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
	_health = maxf(0.0, _health - damage * elapsed)

	_report("Raptorous: %d/%d health, %d archers + %d melee attacking, %d stomped"
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
		_report("Raptorous stumbles and falls: %d stomped before archers brought it down" % _stomped)


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


func _build() -> void:
	var body: Node3D = load(MODEL_PATH).instantiate()
	body.scale = Vector3.ONE * (LENGTH / MODEL_LENGTH_UNITS)
	add_child(body)
