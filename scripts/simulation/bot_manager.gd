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

## How quickly velocity converges on what the bot wants, per second. Snapping
## straight to the desired velocity is what made the crowd look like it was on
## rails: full speed on the first tick, dead straight lines, instant turns.
## Smoothing gives acceleration, braking and rounded corners from one term.
const STEERING_RESPONSE := 2.5

## Below this speed a stopping bot is parked outright, so idle knights cost
## nothing and do not creep.
const REST_SPEED := 0.05

## How quickly a bot turns to face where it is going, per second. Facing is kept
## separately from velocity because velocity is zero when a bot stops, and a
## direction derived from it would snap the knight round to face north the
## instant it stood still.
const TURN_RESPONSE := 6.0

## How long a bot loiters after arriving before it wants to be somewhere else.
const MIN_DWELL := 0.4
const MAX_DWELL := 5.0

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

## Simulation time at which this bot is willing to pick a new destination.
var dwell_until := PackedFloat32Array()

## Unit vector the bot is facing. Survives stopping and turns at a limited rate,
## so knights pivot rather than snapping to a new heading.
var face_x := PackedFloat32Array()
var face_z := PackedFloat32Array()

var team := PackedByteArray()
var state := PackedByteArray()
var alive := PackedByteArray()

## Neighbour lookups for separation. Rebuilt every tick, because a stale grid is
## worse than none.
var _grid := SpatialGrid.new()
var _grid_resolution := 1
var _grid_inverse_cell := 1.0
var _grid_half := 0.0

## Drives AI decisions. Seeded from the map seed, so a given seed always plays
## out the same way for a given sequence of ticks.
var _rng := RandomNumberGenerator.new()

## Separate stream for killing bots. Kept apart from the AI stream so that a
## death cannot shift the decisions of everyone who survived it.
var _cull_rng := RandomNumberGenerator.new()

## Simulation time in seconds, advanced by tick(). Dwell is stored as a deadline
## against this rather than as a countdown, so idle bots need no per-tick work.
var _time := 0.0


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
	_grid.configure(GameConfig.MAP_SIZE,
		SpatialGrid.cell_size_for_radius(GameConfig.SEPARATION_RADIUS))

	# A generator of its own, so changing the bot count cannot shift the map.
	var rng := RandomNumberGenerator.new()
	rng.seed = map_seed
	# A separate stream for decisions, so placement and behaviour do not
	# perturb each other.
	_rng.seed = map_seed ^ 0x9e3779b9
	_cull_rng.seed = map_seed ^ 0x85ebca6b

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
		# Staggered, so the crowd does not all set off on the same tick.
		dwell_until[i] = rng.randf() * MAX_DWELL
		var facing := rng.randf() * TAU
		face_x[i] = sin(facing)
		face_z[i] = cos(facing)

	alive_count = count
	_time = 0.0
	# Fill the grid straight away, so a query that arrives before the first tick
	# gets the truth instead of an empty map.
	_grid.rebuild(pos_x, pos_z, count, alive)
	_grid_resolution = _grid.resolution
	_grid_inverse_cell = _grid.inverse_cell_size()
	_grid_half = _grid.half_extent()
	spawned.emit(count)


## One simulation step. Called at a fixed rate by Main, never per rendered
## frame. AI decisions come first so a bot that just arrived can set off again
## in the same tick.
func tick(delta: float, tick_index: int) -> void:
	if world == null or count == 0:
		return
	_time += delta
	_decide(tick_index)
	_move(delta)
	# Overlaps are resolved after everybody has moved, against a grid built from
	# where they actually ended up.
	_grid.rebuild(pos_x, pos_z, count, alive)
	_grid_resolution = _grid.resolution
	_grid_inverse_cell = _grid.inverse_cell_size()
	_grid_half = _grid.half_extent()
	_resolve_overlaps()


## Expensive decisions are spread across AI_BUCKET_COUNT ticks: on tick t only
## the bots with i % buckets == t % buckets re-decide. Same average cost as
## deciding for everyone every eighth tick, but without the spike.
func _decide(tick_index: int) -> void:
	var buckets := GameConfig.AI_BUCKET_COUNT
	var i := tick_index % buckets
	while i < count:
		if alive[i] == 1 and state[i] == State.IDLE and _time >= dwell_until[i]:
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
	var arrival_squared := GameConfig.BOT_ARRIVAL_RADIUS * GameConfig.BOT_ARRIVAL_RADIUS
	var water := GameConfig.WATER_LEVEL
	# Exponential convergence, computed once rather than per bot, and framed so
	# the result does not change with the tick rate.
	var response := 1.0 - exp(-STEERING_RESPONSE * delta)
	var turn := 1.0 - exp(-TURN_RESPONSE * delta)
	var rest_squared := REST_SPEED * REST_SPEED

	for i in count:
		if alive[i] == 0:
			continue

		# What the bot would like to be doing. Idle means it wants to be still,
		# which is handled by the same steering as wanting to move.
		var desired_vx := 0.0
		var desired_vz := 0.0

		if state[i] == State.MOVING:
			var dx := target_x[i] - pos_x[i]
			var dz := target_z[i] - pos_z[i]
			var distance_squared := dx * dx + dz * dz
			if distance_squared <= arrival_squared:
				state[i] = State.IDLE
				dwell_until[i] = _time + _rng.randf_range(MIN_DWELL, MAX_DWELL)
			else:
				# One square root, reused as both the direction and the scale.
				var step := speed[i] / sqrt(distance_squared)
				desired_vx = dx * step
				desired_vz = dz * step

		var vx := vel_x[i] + (desired_vx - vel_x[i]) * response
		var vz := vel_z[i] + (desired_vz - vel_z[i]) * response

		# Turn towards the direction of travel at a limited rate. A bot that is
		# not moving keeps the heading it had.
		var moving_squared := vx * vx + vz * vz
		if moving_squared > rest_squared:
			var inverse := 1.0 / sqrt(moving_squared)
			var fx := face_x[i] + (vx * inverse - face_x[i]) * turn
			var fz := face_z[i] + (vz * inverse - face_z[i]) * turn
			var length := sqrt(fx * fx + fz * fz)
			if length > 0.0001:
				face_x[i] = fx / length
				face_z[i] = fz / length

		if vx * vx + vz * vz < rest_squared and desired_vx == 0.0 and desired_vz == 0.0:
			# Parked. Collapse the interpolation window, or the knight keeps
			# sliding towards a position it has already left.
			vel_x[i] = 0.0
			vel_z[i] = 0.0
			prev_x[i] = pos_x[i]
			prev_y[i] = pos_y[i]
			prev_z[i] = pos_z[i]
			continue

		prev_x[i] = pos_x[i]
		prev_y[i] = pos_y[i]
		prev_z[i] = pos_z[i]
		var nx := pos_x[i] + vx * delta
		var nz := pos_z[i] + vz * delta
		var ground := world.get_height(nx, nz)
		if ground <= water:
			# The shore is solid. Being shoved into the sea by a crowd is worse
			# than being stuck for a moment, so the step is refused and the bot
			# looks for somewhere else to be.
			state[i] = State.IDLE
			dwell_until[i] = _time + MIN_DWELL
			vel_x[i] = 0.0
			vel_z[i] = 0.0
			continue
		vel_x[i] = vx
		vel_z[i] = vz
		pos_x[i] = nx
		pos_z[i] = nz
		pos_y[i] = ground


## Removes a bot from the simulation. The slot stays where it is: a bot is its
## index, and compacting the arrays would hand every survivor a new identity
## while events, the camera and the renderer were still holding the old one.
##
## Returns true only if this call is what killed it. Killing a corpse is not an
## error and changes nothing, which matters when two events land on the same bot
## in the same tick.
func kill(index: int) -> bool:
	if not is_valid_index(index):
		push_error("BotManager: kill() got index %d, outside 0..%d." % [index, count - 1])
		return false
	if alive[index] == 0:
		return false

	alive[index] = 0
	state[index] = State.DEAD
	health[index] = 0.0
	vel_x[index] = 0.0
	vel_z[index] = 0.0
	# Collapse the interpolation window, or the renderer would spend one more
	# frame sliding a body it has already stopped drawing.
	prev_x[index] = pos_x[index]
	prev_y[index] = pos_y[index]
	prev_z[index] = pos_z[index]
	alive_count -= 1
	return true


## Applies damage and kills the bot if it runs out of health. Returns true if
## this is the blow that killed it, so a caller can count its own kills without
## reading the arrays back.
func damage(index: int, amount: float) -> bool:
	if not is_valid_index(index):
		push_error("BotManager: damage() got index %d, outside 0..%d." % [index, count - 1])
		return false
	if amount <= 0.0:
		# Healing is not this function's job. Refusing beats quietly turning a
		# sign mistake into a heal that nobody asked for.
		push_error("BotManager: damage() expects a positive amount, got %f." % amount)
		return false
	if alive[index] == 0:
		return false

	health[index] -= amount
	if health[index] > 0.0:
		return false
	return kill(index)


## Kills a share of the living, chosen at random, and returns how many died.
## Exists so death can be seen and measured before there is an event to cause
## it; events kill through damage() and kill() like everything else.
func kill_random(fraction: float) -> int:
	var share := clampf(fraction, 0.0, 1.0)
	if share <= 0.0:
		return 0
	var killed := 0
	for i in count:
		if alive[i] == 1 and _cull_rng.randf() < share and kill(i):
			killed += 1
	return killed


## Every living bot within `radius` of a point. The one spatial query offered to
## the rest of the project: events ask this instead of walking the arrays, and
## the grid keeps the cost proportional to how many are actually there.
##
## The answer is as fresh as the last tick, which is the point at which the grid
## is rebuilt. Nothing moves between ticks, so that is exact rather than stale.
func bots_within(x: float, z: float, radius: float) -> PackedInt32Array:
	return _grid.query_circle(pos_x, pos_z, x, z, radius)


func is_valid_index(index: int) -> bool:
	return index >= 0 and index < count


## Bytes held by the bot arrays. Useful when judging whether the layout scales.
func memory_bytes() -> int:
	return count * (15 * 4 + 3)


## Pushes apart any two bots standing inside each other, in position rather than
## in velocity.
##
## Steering them apart was tried first and does not work: the push is smoothed
## by the same steering that pulls a bot towards its target, so it arrives too
## late. Measured at ten thousand bots, raising the steering push until it
## distorted the walk still left 390 knights overlapping and a closest pair
## 0.41 m apart. Correcting position is the only version that actually holds.
##
## Cost is proportional to the number of close neighbours, not to the size of
## the crowd: checking every pair would be O(N squared).
##
## Each of a pair gives up half the overlap, so one pass settles most contacts.
## Bots are corrected in index order and read each other's updated positions,
## which is deterministic but not symmetric; the asymmetry is smaller than a
## tick of movement and costs a second pair of arrays to remove.
func _resolve_overlaps() -> void:
	var radius := GameConfig.SEPARATION_RADIUS
	var radius_squared := radius * radius
	var relaxation := GameConfig.SEPARATION_RELAXATION
	var water := GameConfig.WATER_LEVEL
	var resolution := _grid_resolution
	var last := resolution - 1
	var inverse_cell := _grid_inverse_cell
	var half := _grid_half
	var head := _grid.cell_head
	var links := _grid.next_index

	for i in count:
		if alive[i] == 0:
			continue
		var x := pos_x[i]
		var z := pos_z[i]

		# Bounding box of the query circle, in cells. With cells sized at twice
		# the radius this is at most two by two.
		var first_x := clampi(int((x - radius + half) * inverse_cell), 0, last)
		var end_x := clampi(int((x + radius + half) * inverse_cell), 0, last)
		var first_z := clampi(int((z - radius + half) * inverse_cell), 0, last)
		var end_z := clampi(int((z + radius + half) * inverse_cell), 0, last)

		var push_x := 0.0
		var push_z := 0.0
		var gz := first_z
		while gz <= end_z:
			var row := gz * resolution
			var gx := first_x
			while gx <= end_x:
				var other := head[row + gx]
				while other != -1:
					if other != i:
						var dx := x - pos_x[other]
						var dz := z - pos_z[other]
						var distance_squared := dx * dx + dz * dz
						if distance_squared < radius_squared and distance_squared > 0.000001:
							var distance := sqrt(distance_squared)
							var overlap := (radius - distance) * relaxation / distance
							push_x += dx * overlap
							push_z += dz * overlap
					other = links[other]
				gx += 1
			gz += 1

		if push_x == 0.0 and push_z == 0.0:
			continue
		var nx := x + push_x
		var nz := z + push_z
		var ground := world.get_height(nx, nz)
		# Being shoved into the sea by a crowd is worse than staying jammed.
		if ground <= water:
			continue
		pos_x[i] = nx
		pos_z[i] = nz
		pos_y[i] = ground


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
	dwell_until.resize(n)
	face_x.resize(n)
	face_z.resize(n)
	team.resize(n)
	state.resize(n)
	alive.resize(n)
