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
	## Thrown by a blast. Ballistic until it lands: no steering, no target and no
	## separation. Appended rather than inserted so the existing values keep the
	## numbers anything already stored on disk was written with.
	FLUNG,
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

## Downward acceleration for a bot that has been thrown, in metres per second
## squared. Twice the real thing on purpose: at 9.8 a knight thrown hard enough
## to be worth watching hangs in the air like a balloon. These are toy figures
## being flicked across a table, and heavy gravity is what sells that.
const GRAVITY := 22.0

## How long a bot lies where it landed before the AI picks it up again.
const GET_UP_SECONDS := 1.2

## How much faster than a walk a frightened bot runs. Panic has to be visible
## from altitude, where a knight is a few pixels and only the speed of the
## crowd reads at all.
const PANIC_SPEED := 2.2

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

## Vertical speed, and the only thing that is nonzero for a bot in the air.
## There is no separate height: while a bot is FLUNG, pos_y is its real world
## height instead of the ground under it, so the renderer needs no branch and
## interpolation works exactly as it does for a walking knight.
var air_vy := PackedFloat32Array()
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

## Which of GameConfig's three classes (warrior/spearman/archer) a bot is.
## Replaces what used to be a "team" axis: every bot's colour and weapon
## silhouette follow this instead of a side to fight for.
var bot_class := PackedByteArray()

## 0 or 1, purely spatial — whichever half of the map a bot spawned on
## (pos_x sign). Not a rendered attribute, and not related to bot_class at
## all: class is a role every crowd has, war_side is only meaningful on the
## dedicated war island, where WarBattle uses it as "which army." Left as a
## clean split by spawn position rather than a random coin flip so the two
## sides read as two clumps from the moment the map loads, without any
## change to CrowdRenderer — the same "two clumps converging" shot the old
## team colouring used to sell, done through geography instead of a colour
## channel nothing else needs.
var war_side := PackedByteArray()
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

## Separate stream for everything that happens *to* bots: culling, and the
## direction a bot is thrown when it is standing exactly on an impact point.
## Kept apart from the AI stream so that a death cannot shift the decisions of
## everyone who survived it.
var _harm_rng := RandomNumberGenerator.new()

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
	_harm_rng.seed = map_seed ^ 0x85ebca6b

	var classes := GameConfig.class_count()
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
		air_vy[i] = 0.0
		# No destination yet; movement lands in the next commit.
		target_x[i] = point.x
		target_z[i] = point.y
		health[i] = max_health
		speed[i] = base_speed * (1.0 + rng.randf_range(-variation, variation))
		# Round robin rather than random, so classes are exactly balanced.
		bot_class[i] = i % classes
		war_side[i] = 0 if point.x < 0.0 else 1
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
	# Once per tick, not once per bot: the sea moves during a flood, but never
	# inside a tick.
	var water := world.water_level
	# Exponential convergence, computed once rather than per bot, and framed so
	# the result does not change with the tick rate.
	var response := 1.0 - exp(-STEERING_RESPONSE * delta)
	var turn := 1.0 - exp(-TURN_RESPONSE * delta)
	var rest_squared := REST_SPEED * REST_SPEED

	for i in count:
		if alive[i] == 0:
			continue

		var bot_state := state[i]
		if bot_state == State.FLUNG:
			_fly(i, delta, water)
			continue

		# What the bot would like to be doing. Idle means it wants to be still,
		# which is handled by the same steering as wanting to move.
		var desired_vx := 0.0
		var desired_vz := 0.0

		if bot_state == State.MOVING or bot_state == State.FLEEING or bot_state == State.GATHERING:
			var dx := target_x[i] - pos_x[i]
			var dz := target_z[i] - pos_z[i]
			var distance_squared := dx * dx + dz * dz
			if distance_squared <= arrival_squared:
				# GATHERING arrives the same way MOVING does: back to IDLE with a
				# dwell. There is no separate "standing in the crowd" state — once
				# a bot is there, milling about near a crate is what an idle bot
				# already looks like, and the AI simply has not sent it anywhere
				# yet.
				state[i] = State.IDLE
				dwell_until[i] = _time + _rng.randf_range(MIN_DWELL, MAX_DWELL)
			else:
				# One square root, reused as both the direction and the scale.
				# Running away is the same steering as walking, only faster: a
				# separate flee path would be a second copy of this loop.
				var want := speed[i]
				if bot_state == State.FLEEING:
					want *= PANIC_SPEED
				var step := want / sqrt(distance_squared)
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
	# Reused like dwell_until below: health means nothing once alive == 0.
	# CrowdRenderer needs one more number to make a fall look right on a
	# slope — cos() of the pitch the body should settle at, so its far end
	# (the head, once lying down) lands on the real ground there instead of
	# clipping into a hillside or hanging over a drop. 1.0 means "flat,"
	# which is also what a kill with no world wired falls back to.
	health[index] = 1.0
	if world != null:
		var reach := GameConfig.BOT_HEIGHT
		# Falls forward or back relative to facing, picked from the bot's own
		# index rather than a random draw — a corpse's fall direction is
		# otherwise not stored anywhere, and a fresh RNG pull here would be
		# one more thing to keep off the event stream for no real benefit.
		var direction := 1.0 if index % 2 == 0 else -1.0
		var far_x := pos_x[index] + face_x[index] * direction * reach
		var far_z := pos_z[index] + face_z[index] * direction * reach
		var drop := world.get_height(far_x, far_z) - pos_y[index]
		health[index] = clampf(drop / reach, -1.0, 1.0)
	vel_x[index] = 0.0
	vel_z[index] = 0.0
	air_vy[index] = 0.0
	# Collapse the interpolation window, or the renderer would spend one more
	# frame sliding a body it has already stopped drawing.
	prev_x[index] = pos_x[index]
	prev_y[index] = pos_y[index]
	prev_z[index] = pos_z[index]
	# Reused, not a new array: dwell_until only means anything for a bot that
	# might still act on it, and a corpse never does — the one read of it
	# (deciding when an IDLE bot picks a new wander target) is gated on
	# alive == 1. CrowdRenderer reads it back as a timestamp to animate the
	# fall, through time_now() below.
	dwell_until[index] = _time
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
		if alive[i] == 1 and _harm_rng.randf() < share and kill(i):
			killed += 1
	return killed


## Throws a bot away from a point: outward at `horizontal` metres per second and
## upward at `vertical`. It is ballistic from here until it lands, which is what
## _fly() does.
##
## This is the visual half of a blast, and it is deliberately exaggerated. The
## contrast the whole project is built on is tiny knights against an enormous
## catastrophe, and knights being flicked across the island like toys is that
## contrast in one line.
##
## Returns false if there is nobody alive in that slot to throw.
func fling(index: int, from_x: float, from_z: float,
		horizontal: float, vertical: float) -> bool:
	if not is_valid_index(index):
		push_error("BotManager: fling() got index %d, outside 0..%d." % [index, count - 1])
		return false
	if horizontal < 0.0 or vertical < 0.0:
		push_error("BotManager: fling() expects non-negative speeds, got %f and %f."
			% [horizontal, vertical])
		return false
	if alive[index] == 0:
		return false

	var dx := pos_x[index] - from_x
	var dz := pos_z[index] - from_z
	var length := sqrt(dx * dx + dz * dz)
	if length < 0.001:
		# Standing exactly on the impact point. It still needs a direction, or it
		# would go straight up and come straight back down on the same spot.
		var angle := _harm_rng.randf() * TAU
		dx = sin(angle)
		dz = cos(angle)
		length = 1.0

	var scale := horizontal / length
	vel_x[index] = dx * scale
	vel_z[index] = dz * scale
	air_vy[index] = vertical
	state[index] = State.FLUNG
	return true


## Sends a bot running `distance` metres in a direction. The primitive the other
## two panics are built on: away from a blast is a direction, and uphill out of
## a rising sea is a direction, and neither needs its own copy of this.
##
## Deliberately does not check that the destination is on land. The shore guard
## already lives in _move(): a bot that runs out of island stops at the water
## and goes back to idling. Checking here would mean up to four terrain lookups
## per bot, and one event panics thousands at once.
##
## Returns false if there is nobody there to frighten, if it is already in the
## air where it has no say in the matter, or if the direction is nothing.
func flee(index: int, dir_x: float, dir_z: float, distance: float) -> bool:
	if not is_valid_index(index):
		push_error("BotManager: flee() got index %d, outside 0..%d." % [index, count - 1])
		return false
	if distance <= 0.0:
		push_error("BotManager: flee() expects a positive distance, got %f." % distance)
		return false
	if alive[index] == 0 or state[index] == State.FLUNG:
		return false

	var length := sqrt(dir_x * dir_x + dir_z * dir_z)
	if length < 0.0001:
		return false

	var scale := distance / length
	target_x[index] = pos_x[index] + dir_x * scale
	target_z[index] = pos_z[index] + dir_z * scale
	state[index] = State.FLEEING
	return true


## Sends a bot running away from a point. What a blast does: there is a place
## nobody wants to be, and away from it is the whole of the decision.
func scare(index: int, from_x: float, from_z: float, distance: float) -> bool:
	if not is_valid_index(index):
		push_error("BotManager: scare() got index %d, outside 0..%d." % [index, count - 1])
		return false
	if alive[index] == 0 or state[index] == State.FLUNG:
		return false

	var dx := pos_x[index] - from_x
	var dz := pos_z[index] - from_z
	if dx * dx + dz * dz < 0.000001:
		# Standing exactly on it. Any direction will do, but it has to be one.
		var angle := _harm_rng.randf() * TAU
		dx = sin(angle)
		dz = cos(angle)

	return flee(index, dx, dz, distance)


## Sends a bot walking to an absolute point chosen by whatever called this,
## rather than by the bot's own AI picking a random one. What Team War uses to
## march a bot at the enemy: the same MOVING state and steering a bot walking
## on its own decides between, only the destination comes from outside.
##
## Takes `x, z` exactly as given, no routing of its own: a caller sending a
## whole army through here one bot at a time is expected to have already
## routed the shared destination itself (see WarBattle._send_marchers()) —
## asking World.route_waypoint() again per bot was tried and cost thousands
## of independent region searches in a single tick for what is, every time,
## the same handful of destinations.
##
## Refuses a bot already fighting: it has an opponent to resolve first, and a
## march order arriving mid-swing would pull it out of a fight it is standing
## in the middle of.
func send_to(index: int, x: float, z: float) -> bool:
	if not is_valid_index(index):
		push_error("BotManager: send_to() got index %d, outside 0..%d." % [index, count - 1])
		return false
	if alive[index] == 0 or state[index] == State.FLUNG or state[index] == State.FIGHTING:
		return false

	target_x[index] = x
	target_z[index] = z
	state[index] = State.MOVING
	return true


## The same as send_to(), only marked GATHERING rather than MOVING. What Mass
## Supply Drop uses to send the crowd at a crate: mechanically identical
## movement, kept as its own state so a HUD or a future camera director can
## tell "walking toward an event" apart from ordinary wandering, the way
## FLEEING already stands apart from MOVING.
func gather_at(index: int, x: float, z: float) -> bool:
	if not is_valid_index(index):
		push_error("BotManager: gather_at() got index %d, outside 0..%d." % [index, count - 1])
		return false
	if alive[index] == 0 or state[index] == State.FLUNG or state[index] == State.FIGHTING:
		return false

	target_x[index] = x
	target_z[index] = z
	state[index] = State.GATHERING
	return true


## Kills everyone standing at or below the current water line, and returns how
## many that was. What a rising sea does, expressed once over the arrays rather
## than as a call per bot: a flood asks this a few times a second, and at ten
## thousand a method call each would cost more than the drowning.
##
## Anything in the air is skipped. Its pos_y is a flight altitude rather than
## the ground beneath it, and _fly() already drowns whatever comes down in the
## sea.
func drown() -> int:
	if world == null:
		push_error("BotManager: no world assigned, cannot drown anyone.")
		return 0
	var line := world.water_level
	var lost := 0
	for i in count:
		if alive[i] == 0 or state[i] == State.FLUNG:
			continue
		if pos_y[i] <= line and kill(i):
			lost += 1
	return lost


## Every living bot within `radius` of a point. The one spatial query offered to
## the rest of the project: events ask this instead of walking the arrays, and
## the grid keeps the cost proportional to how many are actually there.
##
## The answer is as fresh as the last tick, which is the point at which the grid
## is rebuilt. Nothing moves between ticks, so that is exact rather than stale.
##
## Wide queries do not use the grid at all. It is sized for separation, so its
## cells are 2.6 m across, and a 460 m panic radius spans a third of a million
## of them with almost nothing in any one. Walking the crowd once is cheaper
## than walking the map, and the crossover is simply "more cells than bots".
## Measured at ten thousand: a meteor impact went from 36 ms to 9 ms.
func bots_within(x: float, z: float, radius: float) -> PackedInt32Array:
	if radius <= 0.0 or count == 0:
		return PackedInt32Array()
	# Cells the query would cover, plus a cell of slop each way for straddling.
	var span := radius * 2.0 * _grid_inverse_cell + 2.0
	if span * span > float(count):
		return _bots_within_linear(x, z, radius)
	return _grid.query_circle(pos_x, pos_z, x, z, radius)


## The wide half of bots_within. Still O(N) rather than O(N squared): one pass
## over the crowd per query, and queries this wide happen when an event lands,
## not per bot per tick.
func _bots_within_linear(x: float, z: float, radius: float) -> PackedInt32Array:
	var found := PackedInt32Array()
	var radius_squared := radius * radius
	for i in count:
		if alive[i] == 0:
			continue
		var dx := pos_x[i] - x
		var dz := pos_z[i] - z
		if dx * dx + dz * dz <= radius_squared:
			found.append(i)
	return found


## Resolves melee between two sides for one tick. Anyone alive on `side_a` or
## `side_b` standing within `melee_range` of a living enemy takes
## damage_per_second times however many enemies are in range at once, and is
## marked FIGHTING; anyone who no longer has an enemy in range goes back to
## IDLE, free to be sent marching again. Returns how many that damage killed.
##
## Walks the same grid separation already rebuilt this tick, the way
## _resolve_overlaps does below, so asking "who is fighting" costs nothing
## beyond what the tick already pays for movement — no second grid, no query
## allocated per bot.
##
## Counting every enemy in range rather than stopping at the first is what
## makes being surrounded worse than a fair fight: the cost is the same
## neighbour scan _resolve_overlaps already pays, just tallied instead of
## broken out of early.
##
## `side_a`/`side_b` are read against `war_side`, not `bot_class` — a
## warrior and an archer on the same half of the war island are allies here,
## exactly the redesign TODO.md asked for once class replaced team as the
## crowd's only per-bot grouping. `side_a`/`side_b` are always 0/1 in
## practice (war_side only ever holds those two values), taken as
## parameters rather than hardcoded so a test can still ask for an empty or
## a one-sided fight without needing real spatial data.
func resolve_combat(side_a: int, side_b: int, melee_range: float,
		damage_per_second: float, delta: float) -> int:
	if melee_range <= 0.0 or damage_per_second <= 0.0 or delta <= 0.0:
		return 0

	var range_squared := melee_range * melee_range
	var resolution := _grid_resolution
	var last := resolution - 1
	var inverse_cell := _grid_inverse_cell
	var half := _grid_half
	var head := _grid.cell_head
	var links := _grid.next_index
	var amount := damage_per_second * delta
	var killed := 0

	for i in count:
		if alive[i] == 0 or state[i] == State.FLUNG:
			continue
		var my_side := war_side[i]
		if my_side != side_a and my_side != side_b:
			continue
		var enemy_side := side_b if my_side == side_a else side_a

		var x := pos_x[i]
		var z := pos_z[i]
		var first_x := clampi(int((x - melee_range + half) * inverse_cell), 0, last)
		var end_x := clampi(int((x + melee_range + half) * inverse_cell), 0, last)
		var first_z := clampi(int((z - melee_range + half) * inverse_cell), 0, last)
		var end_z := clampi(int((z + melee_range + half) * inverse_cell), 0, last)

		var enemies_near := 0
		var gz := first_z
		while gz <= end_z:
			var row := gz * resolution
			var gx := first_x
			while gx <= end_x:
				var other := head[row + gx]
				while other != -1:
					# alive[other] is checked despite the grid already being built
					# from living bots only: this loop can itself kill an enemy
					# through damage() a few iterations back, and its stale entry
					# stays in the linked list until the grid rebuilds next tick.
					# Without the check a bot could count a corpse as cover.
					if other != i and war_side[other] == enemy_side and alive[other] == 1 \
							and state[other] != State.FLUNG:
						var dx := x - pos_x[other]
						var dz := z - pos_z[other]
						if dx * dx + dz * dz <= range_squared:
							enemies_near += 1
					other = links[other]
				gx += 1
			gz += 1

		if enemies_near == 0:
			if state[i] == State.FIGHTING:
				state[i] = State.IDLE
				dwell_until[i] = _time
			continue

		state[i] = State.FIGHTING
		if damage(i, amount * enemies_near):
			killed += 1

	return killed


func is_valid_index(index: int) -> bool:
	return index >= 0 and index < count


## The simulation clock, for CrowdRenderer to measure how long ago a corpse's
## dwell_until (repurposed as its death timestamp) was set, without a second
## copy of the same value.
func time_now() -> float:
	return _time


## Bytes held by the bot arrays. Useful when judging whether the layout scales.
func memory_bytes() -> int:
	return count * (16 * 4 + 3)


## One ballistic step for a bot that has been thrown. While it is in the air it
## is a projectile and nothing else: no steering, no target, no separation, and
## no share of the crowd it is flying over.
##
## Its horizontal velocity is the impulse it was thrown with, kept in the same
## vel_x/vel_z the steering normally owns rather than in two more arrays; while
## a bot is FLUNG nothing else is writing to them.
func _fly(index: int, delta: float, water: float) -> void:
	prev_x[index] = pos_x[index]
	prev_y[index] = pos_y[index]
	prev_z[index] = pos_z[index]

	air_vy[index] -= GRAVITY * delta
	var nx := pos_x[index] + vel_x[index] * delta
	var nz := pos_z[index] + vel_z[index] * delta
	var ny := pos_y[index] + air_vy[index] * delta
	var ground := world.get_height(nx, nz)

	pos_x[index] = nx
	pos_z[index] = nz
	if ny > ground:
		pos_y[index] = ny
		return

	# Landed. Everything it was thrown with is spent.
	pos_y[index] = ground
	air_vy[index] = 0.0
	vel_x[index] = 0.0
	vel_z[index] = 0.0
	if ground <= water:
		# Thrown into the sea. A knight treading water would look worse than one
		# that drowned, and the shore is solid for everyone who walked there.
		kill(index)
		return
	state[index] = State.IDLE
	dwell_until[index] = _time + GET_UP_SECONDS


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
	var water := world.water_level
	var resolution := _grid_resolution
	var last := resolution - 1
	var inverse_cell := _grid_inverse_cell
	var half := _grid_half
	var head := _grid.cell_head
	var links := _grid.next_index

	for i in count:
		# Nothing in the air takes part: it is not standing on anyone, and the
		# crowd underneath must not shove itself apart around a shadow. The
		# neighbour loop checks the same thing, which costs one array read per
		# pair and is the only honest place to put it — the grid is rebuilt once
		# and knows nothing about states.
		if alive[i] == 0 or state[i] == State.FLUNG:
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
					if other != i and state[other] != State.FLUNG:
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
	air_vy.resize(n)
	target_x.resize(n)
	target_z.resize(n)
	health.resize(n)
	speed.resize(n)
	dwell_until.resize(n)
	face_x.resize(n)
	face_z.resize(n)
	bot_class.resize(n)
	war_side.resize(n)
	state.resize(n)
	alive.resize(n)
