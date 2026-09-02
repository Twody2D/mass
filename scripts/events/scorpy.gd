class_name Scorpy
extends Node3D
## A giant scorpion that stalks the island — the second of a second "many
## silly bosses" batch, from the same CC0 collection Monster/Kraken/
## Crabylon/Titanoboo/Giraffaxon/Raptorous already draw from (assets/
## CREDITS.md). Same "gigant" contract as Monster: one object, sim-clock
## advance()/render(alpha), stomps/gets shot/falls and stays down. Slow and
## armoured — a scorpion wins by grinding, not by chasing.
##
## The one twist this file adds: its attack is centred behind its own body,
## not on itself or out in front of it — a tail curled forward over its own
## back to strike, the mirror image of Giraffaxon's own forward neck reach.
##
## **Seventh boss on Crabylon's procedural rig, and the first with only one
## bone per leg.** The model's own Skeleton3D (measured with the same
## throwaway inspector every prior pilot used, tools/inspect_model_tmp.gd,
## built/run/deleted) has just `leg.R`/`leg.L` — no thigh/shin split to fold
## the way every four- and two-legged rig so far has had. Their rest-pose
## local X sits close to horizontal (a few degrees off, same family as
## Horsely/Rombophant/Giraffaxon/Raptorous's own `leg.NNN.L/R` bones,
## measured fresh here too rather than assumed from the shared naming), so
## the swing is one rotation per leg, alternating, no fold.
##
## The model also carries `middletail.001-003` — a single central chain,
## unlike the legs — whose local X lines up with world X *exactly* (zero
## tilt, cleaner than any leg bone measured for any boss so far). That is
## this boss's real tail, and it curls on this axis for the strike itself
## rather than idling on a blind metronome: `_tail_strike_timer` only resets
## to full when `_sweep()` actually kills someone within `STOMP_RADIUS`
## (the tail's own reach point), the same "don't animate what nothing
## proves happened" restraint Horsely's rear-kick already established, then
## decays back to rest over `TAIL_STRIKE_SECONDS`.
##
## There are two more chains, `tail.001-003.R`/`tail.001-003.L` — paired
## left/right, unlike the single tail, positioned along the body's flanks
## and reaching down near ground level like a leg would. Whether they are
## more legs this model simply did not merge into `leg.R`/`leg.L`, or a
## decorative fringe, could not be pinned down from name or position alone.
## What *did* settle it: unlike every other bone animated by any rig this
## project has, their rest-pose basis has no near-horizontal local axis at
## all (measured, not assumed — the same inspector dumped their full basis)
## — posing them on any single axis the way every other joint here works
## would risk a visible twist this project cannot currently see to catch
## (the same headless screenshot hang blocking a look at every rig since
## Crabylon's). Left at rest rather than guessed, per this file's own rule
## 2. Sign of "forward" on both the legs and the tail is unverified for the
## same reason.

## Uniform scale off the model's own widest axis (claw span, side to side) —
## measured, not guessed, the same reasoning Crabylon scales off width
## instead of height.
const MODEL_PATH := "res://assets/models/054_Scorpy_Art.glb"
const MODEL_WIDTH_UNITS := 1.749441
const WIDTH := 66.0

## How far behind its own body the attack is centred — the tail's reach. A
## fraction of WIDTH: a bigger scorpion has a longer tail.
const TAIL_REACH := WIDTH * 0.5

const SPEED := 6.0
const ARRIVAL_RADIUS := 8.5
const RETARGET_SECONDS := 4.0
const TARGET_ATTEMPTS := 6

## Slow and heavily armoured — a scorpion is meant to be a wall to grind
## through, the opposite trade-off from Raptorous.
const MAX_HEALTH := 9000.0
const ARCHER_DAMAGE_PER_SECOND := 1.0
const MELEE_DAMAGE_PER_SECOND := 4.0
const MAX_EFFECTIVE_ARCHERS := 45
const MAX_EFFECTIVE_MELEE := 22
const ATTACK_RANGE := 77.0
const STOMP_RADIUS := 24.0
const MELEE_RANGE := 36.0
const PANIC_RADIUS := 83.0
const FLEE_DISTANCE := 88.0
const SWEEP_SECONDS := 0.2

const FALL_SECONDS := 1.6

## Single-bone legs — see the class doc. One rotation per leg, no fold.
const LEG_R := "leg.R"
const LEG_L := "leg.L"
const STEP_RATE := 4.0
const LEG_SWING := 0.3

## The tail, a separate three-bone chain from the legs — see the class doc.
const TAIL := ["middletail.001", "middletail.002", "middletail.003"]
const TAIL_CURL := [0.9, 0.6, 0.4]
const TAIL_STRIKE_SECONDS := 0.6

enum _Phase { ALIVE, FALLING, DEAD }

var _world: World
var _bots: BotManager
var _rng: RandomNumberGenerator
var _on_report := Callable()
var _on_shake := Callable()

var _phase := _Phase.ALIVE
var _target := Vector2.ZERO
var _facing := Vector2(0.0, 1.0)
var _retarget_timer := 0.0
var _sweep_timer := 0.0
var _fall_elapsed := 0.0
var _health := MAX_HEALTH
var _max_health := MAX_HEALTH
var _stomped := 0
var _previous := Vector3.ZERO
var _current := Vector3.ZERO

## Sim-clock seconds since spawn — drives the leg cycle's phase.
var _elapsed := 0.0
## Seconds left of the tail's post-strike curl — see the class doc.
var _tail_strike_timer := 0.0
## Bone rig — see the class doc. -1 for any name find_bone() could not
## resolve; _build() push_error()s once up front if that happens rather
## than animating nothing silently.
var _skeleton: Skeleton3D
var _leg_r := -1
var _leg_l := -1
var _tail: Array = []


static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable) -> Scorpy:
	if world == null or bots == null:
		push_error("Scorpy: needs a world and a crowd.")
		return null
	if health <= 0.0:
		push_error("Scorpy: needs positive health, got %f." % health)
		return null
	if rng == null:
		push_error("Scorpy: needs a generator.")
		return null

	var scorpion := Scorpy.new()
	scorpion._world = world
	scorpion._bots = bots
	scorpion._rng = rng
	scorpion._health = health
	scorpion._max_health = health
	scorpion._on_report = on_report
	scorpion._on_shake = on_shake
	scorpion._target = at
	scorpion.position = Vector3(at.x, world.get_height(at.x, at.y), at.y)
	scorpion._previous = scorpion.position
	scorpion._current = scorpion.position
	scorpion._build()
	if on_shake.is_valid():
		on_shake.call(scorpion.position, 0.4)
	return scorpion


func advance(delta: float) -> bool:
	_elapsed += delta
	_tail_strike_timer = maxf(0.0, _tail_strike_timer - delta)
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
		_animate_rig()


## Render-clock only, purely cosmetic — see the class doc. No leg or tail
## bone being posed ever changes who gets stomped; that is still _sweep()
## on the sim clock regardless of whether this ever runs.
func _animate_rig() -> void:
	if _skeleton == null:
		return
	var phase := _elapsed * STEP_RATE
	if _leg_r >= 0:
		_skeleton.set_bone_pose_rotation(_leg_r, Quaternion(Vector3(1.0, 0.0, 0.0), sin(phase) * LEG_SWING))
	if _leg_l >= 0:
		_skeleton.set_bone_pose_rotation(_leg_l, Quaternion(Vector3(1.0, 0.0, 0.0), sin(phase + PI) * LEG_SWING))

	var curl := _tail_strike_timer / TAIL_STRIKE_SECONDS
	for i in _tail.size():
		var bone: int = _tail[i]
		if bone >= 0:
			_skeleton.set_bone_pose_rotation(bone, Quaternion(Vector3(1.0, 0.0, 0.0), curl * TAIL_CURL[i]))


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
	_facing = dir
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


## Every radius below is centred on `here` — a point TAIL_REACH behind the
## body, opposite however it is currently facing — rather than on Scorpy's
## own position or out in front of it, the one thing that differs from
## Giraffaxon's own _sweep(). ATTACK_RANGE for archers stays on the body:
## the tail is a melee weapon, an arrow does not care which way it is
## curled.
func _sweep(elapsed: float) -> void:
	var body := Vector2(position.x, position.z)
	var here := body - _facing * TAIL_REACH

	for i in _bots.bots_within(here.x, here.y, STOMP_RADIUS):
		if _bots.kill(i):
			_stomped += 1
			_tail_strike_timer = TAIL_STRIKE_SECONDS

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
	for i in _bots.bots_within(body.x, body.y, ATTACK_RANGE):
		if _bots.alive[i] == 1 and _bots.bot_class[i] == GameConfig.CLASS_ARCHER:
			archers += 1

	var effective_archers := mini(archers, MAX_EFFECTIVE_ARCHERS)
	var effective_melee := mini(melee_fighters, MAX_EFFECTIVE_MELEE)
	var damage := effective_archers * ARCHER_DAMAGE_PER_SECOND \
		+ effective_melee * MELEE_DAMAGE_PER_SECOND
	_health = maxf(0.0, _health - damage * elapsed)

	_report("Scorpy: %d/%d health, %d archers + %d melee attacking, %d stomped"
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
		_report("Scorpy keels over: %d stomped before archers brought it down" % _stomped)


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


func _build() -> void:
	var body: Node3D = load(MODEL_PATH).instantiate()
	body.scale = Vector3.ONE * (WIDTH / MODEL_WIDTH_UNITS)
	add_child(body)
	_skeleton = _find_skeleton(body)
	if _skeleton == null:
		push_error("Scorpy: model has no Skeleton3D, legs and tail will not animate.")
		return
	_cache_bones()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _cache_bones() -> void:
	_leg_r = _skeleton.find_bone(LEG_R)
	_leg_l = _skeleton.find_bone(LEG_L)
	_tail = []
	for name in TAIL:
		_tail.append(_skeleton.find_bone(name))

	var missing := 0
	if _leg_r < 0 or _leg_l < 0:
		missing += 1
	for bone in _tail:
		if bone < 0:
			missing += 1
	if missing > 0:
		push_error("Scorpy: %d expected rig bones were not found; some animation will be missing."
			% missing)
