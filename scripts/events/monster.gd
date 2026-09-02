class_name Monster
extends Node3D
## A giant that walks the island, stomps whoever is underfoot, and falls only
## once the whole crowd has worn it down — the boss fight this project's
## classes (48) exist to make possible. Archers hurt it from range; warriors
## and spearmen close enough to swing stand their ground and hurt it too,
## at real risk (the monster's next step can still reach them) — the owner
## watched a real run end with the fight over in a few seconds and asked
## for the crowd to actually unite against it, not just snipe a mini-boss.
##
## One object, not ten thousand, so none of the crowd's own budget applies:
## the body is a single imported model (assets/models/020_Octozilla_Art.glb,
## see assets/CREDITS.md), not hand-built primitives — the owner watched the
## first version's BlobMesh-and-cylinder body on a real run and called it
## unreadable, and getting a coherent creature silhouette from primitives is
## exactly the kind of job a sculpted asset wins at outright, the case
## CLAUDE.md's external-resources rule exists for. Rigged but not
## animated — no clip ships with the model (checked all eleven boss models
## the same way; none of them do), so there is no bind pose to play. What
## moves instead is the whole body at once: a walking bob and lean, a
## squash-and-stretch on every stomp that actually lands, and a backward
## flinch scaled to how hard it is currently being hit, all in
## _animate_body() — the same class of trick (BOB_RATE/LEAN_AMOUNT etc.)
## that already gives the meteor's crack pattern and Rhombolion's roar their
## motion without a single bone. A ring of additive spark blobs
## (_build_sparks()) flickers in step with _spark_intensity so getting shot
## and stabbed has something to look at besides the health line in the
## overlay, and GroundEjecta (34's own effect, unchanged) throws dirt at
## every stomp and a bigger burst under the fall.
##
## Runs on the **simulation** clock, like every other thing here that decides
## who lives: stomping and being shot both depend on where it is right now,
## not on the frame rate. Advances and draws itself the same two-part way
## MeteorProjectile does — advance(delta) is where the tick decides its new
## position, render(alpha) is only how that gets drawn between two ticks —
## for the same reason: a giant stepping in twenty discrete hops a second
## next to a smoothly moving crowd would be the stutter interpolation
## already fixed once for the crowd itself. The cosmetic motion follows the
## same split: _sweep() (sim clock) only ever sets a trigger time or an
## intensity number, _animate_body() (render, called from render(alpha))
## is the only place that reads _elapsed and actually moves anything.
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

## Raised sharply from the first real balance pass (4000): at ATTACK_RANGE
## 320 a dense crowd could put several hundred archers in range at once,
## which burned even 4000 HP in a few seconds — the owner watched it happen
## and asked for a real fight, not a sniped mini-boss. Health, ranges and
## the per-attacker caps below are all part of the same fix and were tuned
## together against MAX_EFFECTIVE_ARCHERS/MAX_EFFECTIVE_MELEE's worst case.
const MAX_HEALTH := 12000.0
## Damage per archer per second, applied to every living archer within
## ATTACK_RANGE regardless of what it is otherwise doing — an archer that
## panics and runs is still shooting over its shoulder. Keeping this
## stateless avoids a dedicated "is attacking" state on ten thousand bots
## for the sake of one event.
const ARCHER_DAMAGE_PER_SECOND := 1.0
## Melee is riskier than shooting from range — anyone this close is also
## inside stomping distance the instant the monster takes its next step —
## so it is worth more per attacker than an arrow.
const MELEE_DAMAGE_PER_SECOND := 4.0
## Capped rather than left to scale with however dense the crowd is where
## the monster happens to be standing: without a cap, health only means
## anything relative to one particular crowd density, and 10 000 bots
## packed close can put thousands within ATTACK_RANGE at once. A real
## battle line only has room for so many attackers regardless of how many
## more are pressing in behind them.
const MAX_EFFECTIVE_ARCHERS := 60
const MAX_EFFECTIVE_MELEE := 30
## Cut from 320 for the same reason MAX_HEALTH went up: a smaller range
## keeps the archer count (and therefore the fight) sane before the cap
## above even has to do any work.
const ATTACK_RANGE := 150.0
## Small next to ATTACK_RANGE on purpose: this is "directly underfoot," not
## the same radius an arrow can reach from.
const STOMP_RADIUS := 45.0
## Warriors and spearmen inside this ring stand their ground and swing
## instead of fleeing — wider than STOMP_RADIUS so melee is a real choice
## with real risk (the monster's next step can still reach them) rather
## than a radius that overlaps instant death exactly.
const MELEE_RANGE := 70.0
const PANIC_RADIUS := 160.0
const FLEE_DISTANCE := 170.0
const SWEEP_SECONDS := 0.2

## Whole-body motion: a stride bounce plus a small roll, applied to the
## model, not the root Node3D that _move()/_advance_fall() steer — the same
## split KnightMesh's animated corpses use, just at giant scale. The only
## motion a rig with no shipped clip (see class doc) can offer without
## touching bones.
const BOB_RATE := 3.2
const BOB_AMPLITUDE := HEIGHT * 0.02
const LEAN_AMOUNT := 0.05

## Squash-and-stretch fired once per sweep that actually lands a stomp (not
## every sweep — only when _stomped goes up), the same "does it read as an
## impact" problem GroundEjecta already solves for the meteor, applied here
## to the body itself instead of to debris.
const STOMP_SQUASH_SECONDS := 0.35
const STOMP_SQUASH_AMOUNT := 0.16

## Recoils backward in proportion to how hard it is being hit this sweep,
## scaled against the worst a single sweep can ever deal (both caps at
## once) so a lone arrow barely nods it and a full volley staggers it.
const FLINCH_SECONDS := 0.4
const FLINCH_MAX_ANGLE := 0.09
const FLINCH_REFERENCE_RATE := MAX_EFFECTIVE_ARCHERS * ARCHER_DAMAGE_PER_SECOND \
	+ MAX_EFFECTIVE_MELEE * MELEE_DAMAGE_PER_SECOND

## Sparks scattered over the body, flickering in step with how hard it is
## currently being hit — the same additive blast.gdshader and per-spark
## phase MeteorProjectile's own tail sparks already use, just driven by
## combat intensity instead of a flame's reach. Parented to the root, not
## the body — see _build_sparks()'s own note on why.
const SPARK_COUNT := 10
const SPARK_SPREAD_SHARE := 0.16
const SPARK_SIZE_SHARE := 0.03
const SPARK_STRENGTH := 1.3
const SPARK_FLICKER_RATE := 11.0
const SPARK_COLOR := Color(1.0, 0.85, 0.5)

## Dirt thrown up at the exact spot of each stomp, and a bigger burst under
## the fall itself — GroundEjecta unchanged, the same class the meteor's own
## impact already uses, just handed a smaller radius.
const STOMP_EJECTA_RADIUS_SHARE := 0.6
const FALL_EJECTA_RADIUS_SHARE := 1.1
const STOMP_SHAKE_STRENGTH := 0.15

## Every ARROW_SAMPLE_STRIDE-th archer found in the ATTACK_RANGE sweep fires
## a visible arrow instead of every single one — see ArrowSwarm's own note.
## At MAX_EFFECTIVE_ARCHERS this is ~7 new arrows per sweep (0.2 s), well
## under ArrowSwarm's own sustainable rate at its pool size.
const ARROW_SAMPLE_STRIDE := 8

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
var _on_effect := Callable()

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

## Sim-clock seconds since spawn, only ticking while ALIVE — drives every
## cosmetic wobble below the same way Rhombolion's own _elapsed drives its
## roar cycle. Deliberately not real-time: a giant's stride should slow down
## with the rest of the sim if the speed ladder ever does.
var _elapsed := 0.0
var _body: Node3D
var _body_base_scale := Vector3.ONE
## Sentinels far in the past, the same trick Horsely's _rear_trigger uses,
## so the very first render() call settles to "nothing happening" instead
## of a spurious animation at t=0.
var _stomp_trigger := -1000.0
var _flinch_trigger := -1000.0
var _flinch_peak := 0.0
var _spark_intensity := 0.0
var _sparks: Array[MeshInstance3D] = []
var _spark_phase := PackedFloat32Array()
var _arrows: ArrowSwarm


## Builds a monster standing at `at` with `health` to take before it falls,
## ready to be adopted by the event manager. `on_report` is called with a
## line for the overlay; `on_shake` with `(at, strength)` for the moments
## worth feeling on camera: the landing and the fall; `on_effect` with a
## built visual (a GroundEjecta burst) for the caller to adopt_visual() —
## Monster can build the effect itself (it already holds world/rng), it
## just cannot decide who owns advancing it.
static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable,
		on_effect: Callable) -> Monster:
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
	monster._on_effect = on_effect
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
			_elapsed += delta
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
## speed" once nothing needs to look fast any more. The body's own bob,
## squash and sparks are cosmetic and redrawn from _elapsed the same way —
## see _animate_body().
func render(alpha: float) -> void:
	if _phase == _Phase.ALIVE:
		position = _previous.lerp(_current, clampf(alpha, 0.0, 1.0))
		_animate_body()


## Whole-body bob/lean/squash/flinch, all on the imported model rather than
## the root Node3D (see _body's own doc), plus the spark pool's flicker.
## None of this reads combat state directly — _sweep() already reduced it
## to three small numbers (_stomp_trigger, _flinch_trigger/_peak,
## _spark_intensity), the same "sim decides, render only draws" split as
## everything else in this class.
func _animate_body() -> void:
	var bob := sin(_elapsed * BOB_RATE) * BOB_AMPLITUDE
	var lean := cos(_elapsed * BOB_RATE) * LEAN_AMOUNT

	var stomp_t := clampf((_elapsed - _stomp_trigger) / STOMP_SQUASH_SECONDS, 0.0, 1.0)
	var bump := sin(stomp_t * PI)
	var squash_y := 1.0 - STOMP_SQUASH_AMOUNT * bump
	var squash_side := 1.0 + STOMP_SQUASH_AMOUNT * 0.5 * bump

	var flinch_t := clampf((_elapsed - _flinch_trigger) / FLINCH_SECONDS, 0.0, 1.0)
	var flinch_settle := 1.0 - flinch_t
	var flinch := -_flinch_peak * flinch_settle * flinch_settle

	_body.position = Vector3(0.0, bob, 0.0)
	_body.rotation = Vector3(flinch, 0.0, lean)
	_body.scale = _body_base_scale * Vector3(squash_side, squash_y, squash_side)

	for i in _sparks.size():
		var flicker := 0.5 + 0.5 * sin(_elapsed * SPARK_FLICKER_RATE + _spark_phase[i])
		var material := _sparks[i].material_override as ShaderMaterial
		material.set_shader_parameter("strength", SPARK_STRENGTH * flicker * _spark_intensity)


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


## Stomps whoever is underfoot, frightens whoever is close enough to worry
## (unless they are a melee class standing their ground, see below), and
## takes whatever damage archers and melee fighters in range have earned it
## this sweep. `elapsed` is the real time since the last sweep, the same
## reasoning SafeZone's own _sweep() takes it as a parameter rather than
## assuming SWEEP_SECONDS: the last sweep before a phase change may be
## shorter.
func _sweep(elapsed: float) -> void:
	var here := Vector2(position.x, position.z)

	var stomped_before := _stomped
	for i in _bots.bots_within(here.x, here.y, STOMP_RADIUS):
		if _bots.kill(i):
			_stomped += 1
	if _stomped > stomped_before:
		_stomp_trigger = _elapsed
		_spawn_ejecta(STOMP_RADIUS * STOMP_EJECTA_RADIUS_SHARE)
		if _on_shake.is_valid():
			_on_shake.call(position, STOMP_SHAKE_STRENGTH)

	var idle := BotManager.State.IDLE
	var moving := BotManager.State.MOVING
	var fighting := BotManager.State.FIGHTING
	var warrior := GameConfig.CLASS_WARRIOR
	var spearman := GameConfig.CLASS_SPEARMAN
	var melee_range_squared := MELEE_RANGE * MELEE_RANGE
	var melee_fighters := 0

	# One pass over PANIC_RADIUS decides three different fates at once: a
	# melee class already close enough to swing stands and fights instead of
	# fleeing (and is counted for damage below); one that was fighting but
	# has fallen out of range stands down, the same "no enemy left in range"
	# transition BotManager.resolve_combat() already gives a bot-vs-bot
	# fight; everyone else still gets frightened exactly as before.
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
		var state: int = _bots.state[i]
		if state != idle and state != moving:
			continue
		_bots.scare(i, here.x, here.y, FLEE_DISTANCE)

	var archers := 0
	for i in _bots.bots_within(here.x, here.y, ATTACK_RANGE):
		if _bots.alive[i] == 1 and _bots.bot_class[i] == GameConfig.CLASS_ARCHER:
			archers += 1
			# A sampled fraction, not one arrow per archer per sweep — see
			# ArrowSwarm's own note on why that would be both too many draws
			# and a lie about the abstract per-second damage rate anyway.
			if _arrows != null and archers % ARROW_SAMPLE_STRIDE == 0:
				_arrows.fire(Vector3(_bots.pos_x[i], _bots.pos_y[i], _bots.pos_z[i]), position)

	var effective_archers := mini(archers, MAX_EFFECTIVE_ARCHERS)
	var effective_melee := mini(melee_fighters, MAX_EFFECTIVE_MELEE)
	var damage := effective_archers * ARCHER_DAMAGE_PER_SECOND \
		+ effective_melee * MELEE_DAMAGE_PER_SECOND
	_health = maxf(0.0, _health - damage * elapsed)

	_spark_intensity = clampf(damage / FLINCH_REFERENCE_RATE, 0.0, 1.0)
	if damage > 0.0:
		_flinch_trigger = _elapsed
		_flinch_peak = FLINCH_MAX_ANGLE * _spark_intensity

	_report("Monster: %d/%d health, %d archers + %d melee attacking, %d stomped"
		% [ceili(_health), int(_max_health), archers, melee_fighters, _stomped])


## Builds a GroundEjecta burst at the monster's current position and hands
## it off via _on_effect — Monster owns building it (world/rng are already
## here), the caller owns advancing it, the same split _on_report/_on_shake
## already use.
func _spawn_ejecta(radius: float) -> void:
	if not _on_effect.is_valid():
		return
	var burst := GroundEjecta.create(position, radius, _rng, _world.get_height)
	if burst != null:
		_on_effect.call(burst)


func _begin_fall() -> void:
	_phase = _Phase.FALLING
	_fall_elapsed = 0.0
	_spawn_ejecta(STOMP_RADIUS * FALL_EJECTA_RADIUS_SHARE)
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
## deliberately made to match), and scales it uniformly up to HEIGHT. Stored
## as _body rather than a local var: _animate_body() has to keep reaching it
## every frame to bob, lean and squash it.
func _build() -> void:
	_body = load(MODEL_PATH).instantiate()
	_body_base_scale = Vector3.ONE * (HEIGHT / MODEL_HEIGHT_UNITS)
	_body.scale = _body_base_scale
	add_child(_body)
	_build_sparks()
	_build_arrows()


## One ArrowSwarm for this boss's whole fight, built once and handed to
## _on_effect immediately — see ArrowSwarm's own note on why it has to live
## as a sibling (through adopt_visual()) rather than a child of the boss.
## Kept in _arrows so _sweep() can keep firing into the same pool for as
## long as this boss is alive.
func _build_arrows() -> void:
	if not _on_effect.is_valid():
		return
	_arrows = ArrowSwarm.create()
	_on_effect.call(_arrows)


## A small pool of additive spark blobs parented to the root, not the body —
## the body carries a uniform ~HEIGHT/MODEL_HEIGHT_UNITS scale that would
## otherwise have to be divided back out of both the blob radius and every
## offset below. Scattered once at spawn and left alone after that: only
## their flicker strength moves, in _animate_body(), driven by
## _spark_intensity rather than by relocating them. Riding the small bob
## amplitude is not worth the scale math it would cost.
func _build_sparks() -> void:
	var spread := HEIGHT * SPARK_SPREAD_SHARE
	for i in SPARK_COUNT:
		var spark := MeshInstance3D.new()
		spark.mesh = BlobMesh.build(HEIGHT * SPARK_SIZE_SHARE, _rng.randi(), Color.WHITE, Color.WHITE,
			6, 4, 0.25, true)
		var material := ShaderMaterial.new()
		material.shader = load("res://assets/materials/blast.gdshader")
		material.set_shader_parameter("core_color", Vector3(SPARK_COLOR.r, SPARK_COLOR.g, SPARK_COLOR.b))
		material.set_shader_parameter("strength", 0.0)
		spark.material_override = material
		spark.position = Vector3(_rng.randf_range(-spread, spread),
			_rng.randf_range(HEIGHT * 0.25, HEIGHT * 0.85),
			_rng.randf_range(-spread, spread))
		add_child(spark)
		_sparks.append(spark)
		_spark_phase.append(_rng.randf() * TAU)
