class_name Monster
extends Node3D
## A giant that walks the island, stomps whoever is underfoot, and falls only
## once archers have worn it down — the boss fight this project's classes
## (48) exist to make possible: warriors and spearmen can only run from it,
## an archer standing off at range is the one class that actually hurts it.
##
## One object, not ten thousand, so none of the crowd's own budget applies:
## the body is built once from a handful of BlobMesh lumps and plain
## cylinders, the same low-poly language the meteor's rock and the crowd's
## own knights already speak, just with nothing to share across instances
## because there is only one.
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

const HEIGHT := 32.0
const SPEED := 4.5
const ARRIVAL_RADIUS := 4.0
## How often it aims itself at somewhere new: a living bot's own position
## most of the time, so the walk actually crosses paths with the crowd
## instead of touring empty terrain. Re-aimed periodically rather than once
## a bot dies or wanders off, the same reasoning WarBattle's REGROUP_SECONDS
## already uses for a moving target that cannot be tracked exactly.
const RETARGET_SECONDS := 6.0
const TARGET_ATTEMPTS := 6

const MAX_HEALTH := 4000.0
## Damage per archer per second, applied to every living archer within
## ATTACK_RANGE regardless of what it is otherwise doing — an archer that
## panics and runs is still shooting over its shoulder. Keeping this
## stateless avoids a dedicated "is attacking" state on ten thousand bots
## for the sake of one event.
const ARCHER_DAMAGE_PER_SECOND := 3.0
const ATTACK_RANGE := 90.0
## Small next to ATTACK_RANGE on purpose: this is "directly underfoot," not
## the same radius an arrow can reach from.
const STOMP_RADIUS := 10.0
const PANIC_RADIUS := 40.0
const FLEE_DISTANCE := 45.0
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
	monster._build(rng)
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


## Built once, standing on its own origin facing -Z (see _move()'s own
## reasoning for that choice) — legs from the ground up, everything else
## stacked above them, the same "origin is the feet" convention KnightMesh
## already uses so a fall needs no translation fix-up.
func _build(rng: RandomNumberGenerator) -> void:
	var h := HEIGHT
	var leg_top := h * 0.4
	var torso_radius := h * 0.22
	var torso_y := leg_top + torso_radius * 0.7

	var dark := Color(0.14, 0.12, 0.17)
	var light := Color(0.24, 0.20, 0.28)

	var leg_radius := h * 0.05
	for side: float in [-1.0, 1.0]:
		for front: float in [-1.0, 1.0]:
			var leg := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = leg_radius
			cyl.bottom_radius = leg_radius * 1.2
			cyl.height = leg_top
			cyl.radial_segments = 8
			leg.mesh = cyl
			leg.position = Vector3(side * torso_radius * 0.7, leg_top * 0.5,
				front * torso_radius * 0.55)
			_add_flat(leg, dark)

	var torso := MeshInstance3D.new()
	torso.mesh = BlobMesh.build(torso_radius, rng.randi(), dark, light, 10, 7, 0.35)
	torso.position = Vector3(0.0, torso_y, 0.0)
	torso.scale = Vector3(1.0, 1.25, 0.85)
	_add_blob(torso)

	var head_radius := h * 0.13
	var head := MeshInstance3D.new()
	head.mesh = BlobMesh.build(head_radius, rng.randi(), dark, light, 8, 6, 0.35)
	head.position = Vector3(0.0, torso_y + torso_radius * 1.05, -torso_radius * 0.5)
	_add_blob(head)

	var arm_radius := h * 0.045
	var arm_length := h * 0.32
	for side: float in [-1.0, 1.0]:
		var arm := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = arm_radius
		cyl.bottom_radius = arm_radius
		cyl.height = arm_length
		cyl.radial_segments = 7
		arm.mesh = cyl
		arm.position = Vector3(side * (torso_radius + arm_radius), torso_y + torso_radius * 0.3, 0.0)
		arm.rotation = Vector3(0.0, 0.0, side * 0.35)
		_add_flat(arm, light)


func _add_blob(instance: MeshInstance3D) -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	instance.material_override = material
	add_child(instance)


func _add_flat(instance: MeshInstance3D, color: Color) -> void:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	instance.material_override = material
	add_child(instance)
