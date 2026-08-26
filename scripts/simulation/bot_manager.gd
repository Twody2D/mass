class_name BotManager
extends Node
## Owns the bots. All of them, as parallel arrays rather than as objects.
##
## A bot is an index, not a node. Ten thousand GDScript objects would mean ten
## thousand allocations, refcounts and slow field lookups; packed arrays sit
## densely in memory and produce no garbage. The arrays are public on purpose:
## the renderer reads them directly, because a getter call per bot per tick is
## exactly the cost this layout exists to avoid.
##
## Knows nothing about meshes, events or the camera. Asks World for ground, and
## World never asks it anything.

enum State {
	IDLE,
	MOVING,
	FLEEING,
	FIGHTING,
	GATHERING,
	DEAD,
}

## How many nearby spots a bot tries before giving up and staying idle for
## another AI tick. Bounded on purpose: an unbounded search for land would be
## a loop with no guaranteed end near a coastline.
const TARGET_ATTEMPTS := 4
const MIN_TARGET_DISTANCE := 15.0
const MAX_TARGET_DISTANCE := 90.0

## Emitted after a spawn, so the renderer can size its buffers.
signal spawned(count: int)

## Assigned by Main, which owns the wiring. Not exported: one place decides how
## the scene is put together, so there is no question of who resolves what first.
var world: World

## Number of bot slots. Dead bots keep their slot; alive_count tracks the rest.
var count := 0
var alive_count := 0

var pos_x := PackedFloat32Array()
var pos_z := PackedFloat32Array()
## Position at the end of the previous tick. The renderer interpolates between
## this and the current position, so the crowd moves at the frame rate instead
## of stepping twenty times a second. Only bots that move need updating: an idle
## bot already has prev equal to pos and stays that way.
var prev_x := PackedFloat32Array()
var prev_y := PackedFloat32Array()
var prev_z := PackedFloat32Array()

## Ground height under the bot, refreshed whenever it moves. Cached rather than
## sampled on demand: the renderer would otherwise re-sample the terrain for
## every bot every frame, which is far more expensive than keeping 40 KB in sync.
var pos_y := PackedFloat32Array()
var vel_x := PackedFloat32Array()
var vel_z := PackedFloat32Array()
var target_x := PackedFloat32Array()
var target_z := PackedFloat32Array()
var health := PackedFloat32Array()
## Per-bot speed, jittered at spawn so the crowd does not move in lockstep.
var speed := PackedFloat32Array()

var team := PackedByteArray()
var state := PackedByteArray()
var alive := PackedByteArray()

## Drives AI decisions. Seeded from the map seed, so a given seed always plays
## out the same way for a given sequence of ticks.
var _rng := RandomNumberGenerator.new()


## Fills every slot with a fresh bot standing on land. Deterministic: the same
## seed and count always produce the same crowd.
func spawn(bot_count: int, map_seed: int) -> void:
	if world == null:
		push_error("BotManager: no world assigned, cannot spawn.")
		return
	if bot_count < 0:
		push_error("BotManager: bot_count must not be negative, got %d." % bot_count)
		return

	count = bot_count
	_resize(count)

	# A generator of its own, so changing the bot count cannot shift the map.
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	# A separate stream for decisions, so placement and behaviour do not
	# perturb each other.
	_rng.seed = map_seed ^ 0x9e3779b9

	var teams := GameConfig.team_count()
	var base_speed := GameConfig.BOT_MOVE_SPEED
	var variation := GameConfig.BOT_SPEED_VARIATION
	var max_health := GameConfig.BOT_MAX_HEALTH

	for i in count:
		var point := world.random_land_point(rng)
		pos_x[i] = point.x
		pos_z[i] = point.y
		pos_y[i] = world.get_height(point.x, point.y)
		prev_x[i] = pos_x[i]
		prev_y[i] = pos_y[i]
		prev_z[i] = pos_z[i]
		vel_x[i] = 0.0
		vel_z[i] = 0.0
		# No destination yet; movement lands in the next commit.
		target_x[i] = point.x
		target_z[i] = point.y
		health[i] = max_health
		speed[i] = base_speed * (1.0 + rng.randf_range(-variation, variation))
		# Round robin rather than random, so teams are exactly balanced.
		team[i] = i % teams
		state[i] = State.IDLE
		alive[i] = 1

	alive_count = count
	spawned.emit(count)


## One simulation step. Called at a fixed rate by Main, never per rendered
## frame. AI decisions come first so a bot that just arrived can set off again
## in the same tick.
func tick(delta: float, tick_index: int) -> void:
	if world == null or count == 0:
		return
	_decide(tick_index)
	_move(delta)


## Expensive decisions are spread across AI_BUCKET_COUNT ticks: on tick t only
## the bots with i % buckets == t % buckets re-decide. Same average cost as
## deciding for everyone every eighth tick, but without the spike.
func _decide(tick_index: int) -> void:
	var buckets := GameConfig.AI_BUCKET_COUNT
	var i := tick_index % buckets
	while i < count:
		if alive[i] == 1 and state[i] == State.IDLE:
			_choose_target(i)
		i += buckets


func _choose_target(index: int) -> void:
	var x := pos_x[index]
	var z := pos_z[index]
	for attempt in TARGET_ATTEMPTS:
		var angle := _rng.randf() * TAU
		var distance := _rng.randf_range(MIN_TARGET_DISTANCE, MAX_TARGET_DISTANCE)
		var tx := x + cos(angle) * distance
		var tz := z + sin(angle) * distance
		# Targets are picked nearby and on land, which keeps bots off the water
		# without anything as expensive as pathfinding.
		if world.is_walkable(tx, tz):
			target_x[index] = tx
			target_z[index] = tz
			state[index] = State.MOVING
			return
	# Boxed in this time. Stay idle and try again on the next AI tick.


func _move(delta: float) -> void:
	var arrival := GameConfig.BOT_ARRIVAL_RADIUS
	var arrival_squared := arrival * arrival
	var water := GameConfig.WATER_LEVEL
	for i in count:
		if state[i] != State.MOVING:
			continue
		var dx := target_x[i] - pos_x[i]
		var dz := target_z[i] - pos_z[i]
		var distance_squared := dx * dx + dz * dz
		if distance_squared <= arrival_squared:
			state[i] = State.IDLE
			vel_x[i] = 0.0
			vel_z[i] = 0.0
			# Stopping has to collapse the interpolation window too, or the
			# knight keeps sliding towards a position it has already left.
			prev_x[i] = pos_x[i]
			prev_y[i] = pos_y[i]
			prev_z[i] = pos_z[i]
			continue
		# One square root per moving bot, reused as both the direction and the
		# speed scale.
		var step := speed[i] / sqrt(distance_squared)
		var vx := dx * step
		var vz := dz * step
		vel_x[i] = vx
		vel_z[i] = vz
		prev_x[i] = pos_x[i]
		prev_y[i] = pos_y[i]
		prev_z[i] = pos_z[i]
		var nx := pos_x[i] + vx * delta
		var nz := pos_z[i] + vz * delta
		pos_x[i] = nx
		pos_z[i] = nz
		# Never below the waterline: a straight line to a nearby target can
		# still clip a bay, and a bot on the seabed reads as a bug.
		pos_y[i] = maxf(world.get_height(nx, nz), water)


func is_valid_index(index: int) -> bool:
	return index >= 0 and index < count


## Bytes held by the bot arrays. Useful when judging whether the layout scales.
func memory_bytes() -> int:
	return count * (9 * 4 + 3)


func _resize(n: int) -> void:
	pos_x.resize(n)
	pos_z.resize(n)
	pos_y.resize(n)
	prev_x.resize(n)
	prev_y.resize(n)
	prev_z.resize(n)
	vel_x.resize(n)
	vel_z.resize(n)
	target_x.resize(n)
	target_z.resize(n)
	health.resize(n)
	speed.resize(n)
	team.resize(n)
	state.resize(n)
	alive.resize(n)
