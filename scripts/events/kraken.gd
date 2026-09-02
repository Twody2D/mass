class_name Kraken
extends Node3D
## A giant that patrols the coastline, not the island — the same "one
## object, sim-clock, falls once and stays" contract Monster (50) already
## established, reoriented to the sea per TODO.md item 51: it never comes
## ashore, it drags under whoever stands close enough to the water, and only
## archers can ever hurt it back — nobody swims out to meet it in melee.
##
## Body is another import from the same CC0 collection Monster's Octozilla
## came from (assets/models/002_Squaresquid_Art.glb, see assets/CREDITS.md):
## the same low-poly, vertex-coloured toy style, and the same lesson TODO.md
## already recorded for the next giant after Octozilla — check the CC0
## market for a ready silhouette before reaching for BlobMesh primitives.
##
## Advances and draws itself the same two-part way Monster and
## MeteorProjectile do: advance(delta) on the simulation tick decides where
## it is now, render(alpha) only draws the frame between the last two ticks.
##
## **Eleventh boss on Crabylon's procedural rig, and the cleanest axis this
## whole series has measured.** Monster's own rig (the last pilot before
## this one) already corrected the belief that this shared model family had
## no discrete per-limb bones — the same throwaway inspector
## (tools/inspect_model_tmp.gd, built/run/deleted) run against this file
## found a real `Skeleton3D` with five distinct tentacles: two four-segment
## `LargeTentacle.L/R`, two three-segment `ShortTentacle.L/R`, and one
## unpaired three-segment `MiddleTentacle` — seventeen bones in total, and
## every single one of them has a rest-pose local X axis with a world-Y
## component of exactly zero, not just close to it. Rotating around it
## bends each segment within its own roughly-vertical plane, the same
## mechanism Titanoboo's spine and Whormbus's arch both used — found here
## bone by bone rather than once for a whole straight chain, because a real
## tentacle is not straight, so no single shared plane could have been
## assumed for all seventeen at once the way it was for those two.
##
## **A travelling wave down every tentacle, each with its own phase, not a
## metronome.** Each of the seventeen bones gets `sin(_elapsed * WAVE_RATE +
## group_index * TENTACLE_PHASE_STEP + segment_index * SEGMENT_PHASE_STEP)`
## — a phase offset per tentacle so the five do not all wave in lockstep
## (which would read as one animation replayed five times, not five
## independent limbs), stacked with the same per-segment offset within each
## tentacle Titanoboo's own spine already established, so the bend still
## travels from base to tip along each one individually.
##
## **Continuous, unlike Scorpy's own tail — a deliberate difference, not an
## oversight.** Scorpy's tail curl is gated on landing a real hit because a
## static tail that snaps only when it strikes is how a scorpion reads;
## a giant sea creature's tentacles drifting even when nothing is
## happening is the more natural default, so this wave just runs the whole
## time `_phase == ALIVE`, the first bone rig on this project's roster with
## no gameplay state feeding into it at all. `_dragged`/`TENTACLE_RANGE`
## are untouched — the wave is exactly as cosmetic as Titanoboo's own
## slither, deciding nothing about who actually gets pulled under.

## Full scaled height of the imported body. Bigger than Monster's 128 m on
## purpose: most of it sits below the waterline (see SUBMERGE_DEPTH), so the
## visible portion still has to read as a giant breaking the surface, not a
## large fish.
const HEIGHT := 150.0
const MODEL_PATH := "res://assets/models/002_Squaresquid_Art.glb"
## The model's own Y extent in the units the glTF ships in, measured once
## from the file itself — see Monster.MODEL_HEIGHT_UNITS for the same idea.
const MODEL_HEIGHT_UNITS := 1.284095

## How far below the waterline the body's own origin sits. HEIGHT minus this
## is roughly how much shows above the waves. Raised from 55 after a real
## run: the model is a single skinned mesh (Skeleton3D, no separate
## head/tentacle nodes to query), and its tentacle fan splays outward, not
## just down, from somewhere around the lower third of its own bounding
## box — at HEIGHT's scale that splay was tens of metres wide, wide enough
## to lie flat across the beach right next to the water like a loose card
## instead of trailing believably into the sea. Sinking the whole body
## deeper keeps that fan submerged and leaves only the narrower head above
## the surface.
const SUBMERGE_DEPTH := 75.0
## Radius of the churning-water disc at the waterline — the one place this
## reuses ocean.gdshader rather than inventing a new "water" look, so the
## sea itself visibly disturbs where the kraken is, not just around it.
## Small on purpose: the kraken patrols close to the coast, so anything
## much wider than the body itself would reach onto the beach next to it.
const WAKE_RADIUS := 22.0
## How far below the true waterline the disc actually sits. A flat plane
## exactly at water_level relies on real terrain being strictly taller to
## get hidden by ordinary depth testing — true almost everywhere, but a
## shallow beach only centimetres above the water is enough for the two to
## fight, and the coast is exactly where this disc spends all its time.
const WAKE_SINK := 1.5

## How far out from the raw coastline a patrol point is pushed before the
## kraken swims to it — see _pick_target(). World.random_coast_point()
## returns a cell that is *just* underwater, touching land by definition;
## planting a HEIGHT-scale body exactly there left even its narrower head
## resting on the sand instead of breaking the surface offshore. Found on
## the same real run as SUBMERGE_DEPTH's own note, and fixed the same way
## that note's problem was not fixed — by giving the giant room, rather
## than by shrinking it until it happened to fit.
const SHORE_CLEARANCE := 35.0

const SPEED := 6.0
const ARRIVAL_RADIUS := 20.0
## How often it moves to a new stretch of coast. Longer than Monster's own
## 4 s: a coastline patrol reads as a slow, patient hunt, not a charge.
const RETARGET_SECONDS := 6.0

## Balanced against a single damage source (archers only — see class doc),
## unlike Monster's archer-plus-melee mix, so a comparable fight length
## needs neither Monster's health nor its per-archer rate.
const MAX_HEALTH := 6000.0
const ARCHER_DAMAGE_PER_SECOND := 1.5
## Same reasoning as Monster.MAX_EFFECTIVE_ARCHERS: capped so damage means
## something regardless of how densely the crowd happens to be packed along
## whatever stretch of coast the kraken is currently patrolling.
const MAX_EFFECTIVE_ARCHERS := 50
## Reaches further inland than Monster's own ATTACK_RANGE (150) because the
## kraken itself never comes ashore — archers need room to stand back from
## the water and still be in range, not just the ones already at the tideline.
const ATTACK_RANGE := 220.0

## Instant kill, the same contract drowning and lava already share: anyone
## this close to a thrashing giant is not swimming away from it.
const TENTACLE_RANGE := 55.0
const PANIC_RADIUS := 150.0
const FLEE_DISTANCE := 160.0
const SWEEP_SECONDS := 0.2

## How long it takes to sink out of sight once health reaches zero.
const SINK_SECONDS := 3.0
## How much further it sinks below its already-submerged resting depth —
## comfortably past HEIGHT so nothing is left poking out of the water.
const SINK_DEPTH := 200.0

## Tentacle wave — see the class doc.
const LARGE_L := ["LargeTentacle.001.L", "LargeTentacle.002.L", "LargeTentacle.003.L", "LargeTentacle.004.L"]
const LARGE_R := ["LargeTentacle.001.R", "LargeTentacle.002.R", "LargeTentacle.003.R", "LargeTentacle.004.R"]
const SHORT_L := ["ShortTentacle.001.L", "ShortTentacle.002.L", "ShortTentacle.003.L"]
const SHORT_R := ["ShortTentacle.001.R", "ShortTentacle.002.R", "ShortTentacle.003.R"]
const MIDDLE := ["MiddleTentacle.001", "MiddleTentacle.002", "MiddleTentacle.003"]
const WAVE_RATE := 1.6
const WAVE_AMPLITUDE := 0.3
const SEGMENT_PHASE_STEP := 0.8
const TENTACLE_PHASE_STEP := 1.8

enum _Phase { ALIVE, SINKING, DEAD }

var _world: World
var _bots: BotManager
var _rng: RandomNumberGenerator
var _on_report := Callable()
var _on_shake := Callable()

var _phase := _Phase.ALIVE
var _target := Vector2.ZERO
var _retarget_timer := 0.0
var _sweep_timer := 0.0
var _sink_elapsed := 0.0
var _sink_start_y := 0.0
var _health := MAX_HEALTH
var _max_health := MAX_HEALTH
var _dragged := 0
## Where the last two ticks put it, so a frame can be drawn between them —
## see the class doc.
var _previous := Vector3.ZERO
var _current := Vector3.ZERO

## Sim-clock seconds since spawn — drives the tentacle wave's phase.
var _elapsed := 0.0
## Bone rig — see the class doc. -1 for any name find_bone() could not
## resolve; _build() push_error()s once up front if that happens rather
## than animating nothing silently. One Array[int] per tentacle group, in
## LARGE_L/LARGE_R/SHORT_L/SHORT_R/MIDDLE order.
var _skeleton: Skeleton3D
var _tentacles: Array = []


## Builds a kraken surfacing at `at` (a coastal point — see
## World.random_coast_point()) with `health` to take before it sinks, ready
## to be adopted by the event manager.
static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable) -> Kraken:
	if world == null or bots == null:
		push_error("Kraken: needs a world and a crowd.")
		return null
	if health <= 0.0:
		push_error("Kraken: needs positive health, got %f." % health)
		return null
	if rng == null:
		push_error("Kraken: needs a generator.")
		return null

	var kraken := Kraken.new()
	kraken._world = world
	kraken._bots = bots
	kraken._rng = rng
	kraken._health = health
	kraken._max_health = health
	kraken._on_report = on_report
	kraken._on_shake = on_shake
	kraken._target = at
	kraken.position = Vector3(at.x, world.water_level - SUBMERGE_DEPTH, at.y)
	kraken._previous = kraken.position
	kraken._current = kraken.position
	kraken._build()
	if on_shake.is_valid():
		on_shake.call(kraken.position, 0.4)
	return kraken


## One simulation step. Always returns true: like Crater and Monster, this
## never says it is finished, it just stops doing anything once it sinks.
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
				_begin_sink()
		_Phase.SINKING:
			_advance_sink(delta)
		_Phase.DEAD:
			pass
	return true


## Draws this frame between the last two ticks. Once it is sinking there is
## nothing to interpolate: _advance_sink() sets the depth directly on the
## simulation clock, the same trade Monster's own fall makes once nothing
## needs to look fast any more.
func render(alpha: float) -> void:
	if _phase == _Phase.ALIVE:
		position = _previous.lerp(_current, clampf(alpha, 0.0, 1.0))
		_animate_rig()


## Render-clock only, purely cosmetic — see the class doc. No tentacle bone
## being posed ever changes who gets dragged under; that is still _sweep()
## on the sim clock regardless of whether this ever runs.
func _animate_rig() -> void:
	if _skeleton == null:
		return
	for g in _tentacles.size():
		var group: Array = _tentacles[g]
		var base_phase := _elapsed * WAVE_RATE + g * TENTACLE_PHASE_STEP
		for i in group.size():
			var bone: int = group[i]
			if bone < 0:
				continue
			var bend := sin(base_phase + i * SEGMENT_PHASE_STEP) * WAVE_AMPLITUDE
			_skeleton.set_bone_pose_rotation(bone, Quaternion(Vector3(1.0, 0.0, 0.0), bend))


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
	# Depth stays fixed relative to the waterline, not to the seabed under
	# it: a real body of water is flat on top regardless of how the bottom
	# undulates, unlike Monster, which follows the terrain because it walks
	# on top of it.
	position = Vector3(nx, _world.water_level - SUBMERGE_DEPTH, nz)
	basis = Basis.looking_at(Vector3(dir.x, 0.0, dir.y), Vector3.UP)


## Heads for a new stretch of coastline, not for a bot: unlike Monster, which
## chases the crowd across open land, a kraken cannot leave the water to
## follow anyone. It patrols; whoever happens to be close to the tideline
## when it passes is who is actually at risk — that is the whole point of
## "reaches for those near the shore" rather than "hunts the crowd".
func _pick_target() -> void:
	_retarget_timer = RETARGET_SECONDS
	_target = _world.random_coast_point(_rng, SHORE_CLEARANCE)


## Drags under whoever is within tentacle reach, frightens whoever is close
## enough to worry, and takes whatever damage the archers in range have
## earned it this sweep. No melee counterpart to Monster's — nobody is close
## enough to swing a sword at something that never leaves the water.
func _sweep(elapsed: float) -> void:
	var here := Vector2(position.x, position.z)

	for i in _bots.bots_within(here.x, here.y, TENTACLE_RANGE):
		if _bots.kill(i):
			_dragged += 1

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

	var effective_archers := mini(archers, MAX_EFFECTIVE_ARCHERS)
	var damage := effective_archers * ARCHER_DAMAGE_PER_SECOND
	_health = maxf(0.0, _health - damage * elapsed)

	_report("Kraken: %d/%d health, %d archers firing, %d dragged under"
		% [ceili(_health), int(_max_health), archers, _dragged])


func _begin_sink() -> void:
	_phase = _Phase.SINKING
	_sink_elapsed = 0.0
	_sink_start_y = position.y
	if _on_shake.is_valid():
		_on_shake.call(position, 0.6)


func _advance_sink(delta: float) -> void:
	_sink_elapsed += delta
	var t := clampf(_sink_elapsed / SINK_SECONDS, 0.0, 1.0)
	position.y = lerpf(_sink_start_y, _sink_start_y - SINK_DEPTH, t * t)
	if t >= 1.0:
		_phase = _Phase.DEAD
		_report("Kraken sinks beneath the waves: %d dragged under before archers drove it down"
			% _dragged)


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


## Instances the imported model once, standing on its own origin facing -Z
## (the same convention Monster's body and _move()'s Basis.looking_at()
## already assume), scaled up to HEIGHT, plus one flat disc at the waterline
## using ocean.gdshader as-is — see WAKE_RADIUS.
func _build() -> void:
	var body: Node3D = load(MODEL_PATH).instantiate()
	body.scale = Vector3.ONE * (HEIGHT / MODEL_HEIGHT_UNITS)
	add_child(body)
	_skeleton = _find_skeleton(body)
	if _skeleton == null:
		push_error("Kraken: model has no Skeleton3D, tentacles will not animate.")
	else:
		_cache_bones()

	var wake := MeshInstance3D.new()
	var disc := PlaneMesh.new()
	disc.size = Vector2.ONE * WAKE_RADIUS * 2.0
	disc.subdivide_width = 12
	disc.subdivide_depth = 12
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/materials/ocean.gdshader")
	disc.material = material
	wake.mesh = disc
	# Local space: the node's own origin sits SUBMERGE_DEPTH below the
	# waterline, so this lifts the disc back up to just under it — see
	# WAKE_SINK.
	wake.position.y = SUBMERGE_DEPTH - WAKE_SINK
	add_child(wake)


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _cache_bones() -> void:
	var groups := [LARGE_L, LARGE_R, SHORT_L, SHORT_R, MIDDLE]
	_tentacles = []
	for group_names in groups:
		var bones: Array = []
		for bone_name in group_names:
			bones.append(_skeleton.find_bone(bone_name))
		_tentacles.append(bones)

	var missing := 0
	for group in _tentacles:
		for bone in group:
			if bone < 0:
				missing += 1
	if missing > 0:
		push_error("Kraken: %d expected rig bones were not found; some animation will be missing."
			% missing)
