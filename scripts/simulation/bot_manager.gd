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

	var teams := GameConfig.team_count()
	var base_speed := GameConfig.BOT_MOVE_SPEED
	var variation := GameConfig.BOT_SPEED_VARIATION
	var max_health := GameConfig.BOT_MAX_HEALTH

	for i in count:
		var point := world.random_land_point(rng)
		pos_x[i] = point.x
		pos_z[i] = point.y
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


## Ground height under a bot. Bots do not store y: keeping a third coordinate in
## sync with the terrain costs more than sampling it when needed.
func ground_y(index: int) -> float:
	if not is_valid_index(index):
		push_error("BotManager: invalid bot index %d (count %d)." % [index, count])
		return 0.0
	return world.get_height(pos_x[index], pos_z[index])


func is_valid_index(index: int) -> bool:
	return index >= 0 and index < count


## Bytes held by the bot arrays. Useful when judging whether the layout scales.
func memory_bytes() -> int:
	return count * (8 * 4 + 3)


func _resize(n: int) -> void:
	pos_x.resize(n)
	pos_z.resize(n)
	vel_x.resize(n)
	vel_z.resize(n)
	target_x.resize(n)
	target_z.resize(n)
	health.resize(n)
	speed.resize(n)
	team.resize(n)
	state.resize(n)
	alive.resize(n)
