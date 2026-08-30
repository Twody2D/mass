class_name Monster
extends Node3D
## A giant that walks the island, stomps whoever is underfoot, and falls only
## once archers have worn it down — the boss fight this project's classes
## (48) exist to make possible: warriors and spearmen can only run from it,
## an archer standing off at range is the one class that actually hurts it.
##
## One object, not ten thousand, so none of the crowd's own budget applies:
## the body is a single imported model (assets/models/020_Octozilla_Art.glb,
## see assets/CREDITS.md), not hand-built primitives — the owner watched the
## first version's BlobMesh-and-cylinder body on a real run and called it
## unreadable, and getting a coherent creature silhouette from primitives is
## exactly the kind of job a sculpted asset wins at outright, the case
## CLAUDE.md's external-resources rule exists for. Rigged but not
## animated — no clip ships with the model, so it stands in its bind pose,
## the same static-body contract the rest of this class already assumes.
##
## Runs on the **simulation** clock, like every other thing here that decides
## who lives: stomping and being shot both depend on where it is right now,
## not on the frame rate. Advances and draws itself the same two-part way
## MeteorProjectile does — advance(delta) is where the tick decides its new
## position, render(alpha) is only how that gets drawn between two ticks —
## for the same reason: a giant stepping in twenty discrete hops a second
## next to a smoothly moving crowd would be the stutter interpolation
## already fixed once for the crowd itself.
##
## Falls once and stays down, permanently, the same contract Crater has: a
## defeated boss is a landmark for the rest of the session, not a moment
## that cleans up after itself.

## Genuinely gigantic — four times the primitive body's own 32 m, the size
## the owner asked for after the first version read as a pile of shapes, not
## a giant.
const HEIGHT := 128.0

## Where the body model lives, and its own resting height in the units the
## file ships in (the POSITION accessor's Y extent, measured once from the
## glTF itself) — the ratio of the two is the uniform scale that makes the
## imported model actually stand HEIGHT metres tall. Built on its own origin
## already (min.y is ~0), the same "origin is the feet" convention KnightMesh
## uses, so no vertical offset is needed once scaled.
const MODEL_PATH := "res://assets/models/020_Octozilla_Art.glb"
const MODEL_HEIGHT_UNITS := 1.4679207229564781

## Faster than the primitive body's own 4.5, and re-aimed more often: the
## first version at HEIGHT 32 read as a giant that mostly just walked around
## — after it grew to HEIGHT 128 the owner watched a real run and asked for
## it to actually be aggressive, and a giant that arrives at the crowd
## faster and picks a new living target more often is doing more of its
## stomping and less of its touring.
const SPEED := 9.0
## Scales with HEIGHT (x4 from the original body's own 4.0), the same as
## every other distance below — see STOMP_RADIUS's own note.
const ARRIVAL_RADIUS := 16.0
## How often it aims itself at somewhere new: a living bot's own position
## most of the time, so the walk actually crosses paths with the crowd
## instead of touring empty terrain. Re-aimed periodically rather than once
## a bot dies or wanders off, the same reasoning WarBattle's REGROUP_SECONDS
## already uses for a moving target that cannot be tracked exactly.
const RETARGET_SECONDS := 4.0
const TARGET_ATTEMPTS := 6

const MAX_HEALTH := 4000.0
## Damage per archer per second, applied to every living archer within
## ATTACK_RANGE regardless of what it is otherwise doing — an archer that
## panics and runs is still shooting over its shoulder. Keeping this
## stateless avoids a dedicated "is attacking" state on ten thousand bots
## for the sake of one event.
const ARCHER_DAMAGE_PER_SECOND := 3.0
## STOMP_RADIUS, PANIC_RADIUS, FLEE_DISTANCE and ATTACK_RANGE below were
## never rescaled when HEIGHT grew from the primitive body's 32 m to the
## imported model's 128 m — a real bug, not a balance choice: a giant four
## times taller stomping with the same 10 m foot as before is a person's
## stride under a skyscraper. All four now scale with HEIGHT the same way
## the body itself does, so the giant that reads as huge on screen also
## reaches and flattens a proportionally huge patch of the crowd.
const ATTACK_RANGE := 320.0
## Small next to ATTACK_RANGE on purpose: this is "directly underfoot," not
## the same radius an arrow can reach from.
const STOMP_RADIUS := 45.0
const PANIC_RADIUS := 160.0
const FLEE_DISTANCE := 170.0
const SWEEP_SECONDS := 0.2

## How long the fall takes once health reaches zero. Slower than a knight's
## own 0.6 s (CrowdRenderer.FALL_SECONDS): there is a lot more of this
## falling over, and a boss that drops instantly reads as switched off
## rather than beaten.
const FALL_SECONDS := 1.8

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
## Where the last two ticks put it, so a frame can be drawn between them —
## see the class doc.
var _previous := Vector3.ZERO
var _current := Vector3.ZERO


## Builds a monster standing at `at` with `health` to take before it falls,
## ready to be adopted by the event manager. `on_report` is called with a
## line for the overlay; `on_shake` with `(at, strength)` for the moments
## worth feeling on camera: the landing and the fall.
static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable) -> Monster:
	if world == null or bots == null:
		push_error("Monster: needs a world and a crowd.")
		return null
	if health <= 0.0:
		push_error("Monster: needs positive health, got %f." % health)
		return null
	if rng == null:
		push_error("Monster: needs a generator.")
		return null

	var monster := Monster.new()
	monster._world = world
	monster._bots = bots
	monster._rng = rng
	monster._health = health
	monster._max_health = health
	monster._on_report = on_report
	monster._on_shake = on_shake
	monster._target = at
	monster.position = Vector3(at.x, world.get_height(at.x, at.y), at.y)
	monster._previous = monster.position
	monster._current = monster.position
	monster._build()
	if on_shake.is_valid():
		on_shake.call(monster.position, 0.4)
	return monster


## One simulation step. Always returns true: like Crater, this never says it
## is finished, it just stops doing anything once it has fallen.
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


## Draws this frame between the last two ticks. Once it has fallen there is
## nothing left to interpolate: rotation carries the fall instead, set
## directly by _advance_fall() on the simulation clock, exactly like every
## other slow-moving boundary in this project (ZoneRing, LavaPool) that
## trades frame-smooth motion for "redrawn on the tick, good enough at this
## speed" once nothing needs to look fast any more.
func render(alpha: float) -> void:
	if _phase == _Phase.ALIVE:
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
	# Built facing -Z, the same convention Basis.looking_at() itself uses, so
	# the body turns to face wherever it is actually walking.
	basis = Basis.looking_at(Vector3(dir.x, 0.0, dir.y), Vector3.UP)


## Heads for a living bot's own position most of the time — walking at the
## crowd rather than touring the map empty is the whole point of a stomping
## boss. Falls back to a random land point if the crowd has been wiped out
## by whatever else is happening at the same time.
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


## Stomps whoever is underfoot, frightens whoever is close enough to worry,
## and takes whatever damage the archers in range have earned it this sweep.
## `elapsed` is the real time since the last sweep, the same reasoning
## SafeZone's own _sweep() takes it as a parameter rather than assuming
## SWEEP_SECONDS: the last sweep before a phase change may be shorter.
func _sweep(elapsed: float) -> void:
	var here := Vector2(position.x, position.z)

	for i in _bots.bots_within(here.x, here.y, STOMP_RADIUS):
		if _bots.kill(i):
			_stomped += 1

	var idle := BotManager.State.IDLE
	var moving := BotManager.State.MOVING
	for i in _bots.bots_within(here.x, here.y, PANIC_RADIUS):
		if _bots.alive[i] == 0:
			continue
		var state: int = _bots.state[i]
		if state != idle and state != moving:
			continue
		_bots.scare(i, here.x, here.y, FLEE_DISTANCE)

	var archers := 0
	for i in _bots.bots_within(here.x, here.y, ATTACK_RANGE):
		if _bots.alive[i] == 1 and _bots.bot_class[i] == GameConfig.CLASS_ARCHER:
			archers += 1
	_health = maxf(0.0, _health - archers * ARCHER_DAMAGE_PER_SECOND * elapsed)

	_report("Monster: %d/%d health, %d archers firing, %d stomped"
		% [ceili(_health), int(_max_health), archers, _stomped])


func _begin_fall() -> void:
	_phase = _Phase.FALLING
	_fall_elapsed = 0.0
	if _on_shake.is_valid():
		_on_shake.call(position, 0.7)


## Toppling around its own local X axis, pivoting at the origin — the same
## trick CrowdRenderer's own corpses use, and for the same reason: the body
## is built standing on its own origin (see _build()), so no position
## correction is needed, the feet simply stay where they were. A single
## object does not need the sin/cos-avoiding trick the crowd's ten thousand
## corpses earn their keep with; one real cos()/sin() a tick is nothing.
func _advance_fall(delta: float) -> void:
	_fall_elapsed += delta
	var t := clampf(_fall_elapsed / FALL_SECONDS, 0.0, 1.0)
	rotation.x = lerpf(0.0, PI * 0.5, t * t)
	if t >= 1.0:
		_phase = _Phase.DEAD
		_report("Monster falls: %d stomped before archers brought it down" % _stomped)


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


## Instances the imported model once, standing on its own origin facing -Z
## (glTF's own forward axis, the same convention _move()'s
## Basis.looking_at() already assumes and KnightMesh's hand-built bodies were
## deliberately made to match), and scales it uniformly up to HEIGHT.
func _build() -> void:
	var body: Node3D = load(MODEL_PATH).instantiate()
	body.scale = Vector3.ONE * (HEIGHT / MODEL_HEIGHT_UNITS)
	add_child(body)
