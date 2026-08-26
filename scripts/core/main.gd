extends Node3D
## Owns the order in which the simulation is built, and the clock that drives
## it afterwards.
##
## World and BotManager deliberately do not build themselves in _ready. Bots can
## only be placed once the island exists, and leaning on sibling _ready order to
## guarantee that is a hidden dependency that breaks the first time somebody
## reorders the scene tree. Restarting later means calling rebuild() again, in
## one place, rather than reloading the scene.

@export var world_path: NodePath = ^"World"
@export var bots_path: NodePath = ^"Bots"
@export var crowd_path: NodePath = ^"Crowd"
@export var hud_path: NodePath = ^"DebugHUD"

var world: World
var bots: BotManager
var crowd: CrowdRenderer
var hud: DebugHUD

## Simulation clock. Rendering runs at whatever FPS it can; the simulation runs
## at a fixed step, so behaviour does not change with frame rate.
var paused := false
var sim_speed := GameConfig.DEFAULT_SIM_SPEED
var tick_count := 0
var sim_time := 0.0

var _accumulator := 0.0


func _ready() -> void:
	world = get_node_or_null(world_path) as World
	bots = get_node_or_null(bots_path) as BotManager
	if world == null:
		push_error("Main: world_path does not point at a World node (%s)." % world_path)
		return
	crowd = get_node_or_null(crowd_path) as CrowdRenderer
	if bots == null:
		push_error("Main: bots_path does not point at a BotManager node (%s)." % bots_path)
		return
	if crowd == null:
		push_error("Main: crowd_path does not point at a CrowdRenderer node (%s)." % crowd_path)
		return
	hud = get_node_or_null(hud_path) as DebugHUD
	bots.world = world
	crowd.bots = bots
	if hud != null:
		hud.main = self
	rebuild(GameConfig.map_seed, GameConfig.bot_count)


func _physics_process(delta: float) -> void:
	if paused or bots == null or crowd == null:
		return

	_accumulator += delta * sim_speed
	var step := GameConfig.SIMULATION_TICK_SECONDS
	var ticks := 0
	while _accumulator >= step and ticks < GameConfig.MAX_TICKS_PER_FRAME:
		bots.tick(step, tick_count)
		tick_count += 1
		sim_time += step
		_accumulator -= step
		ticks += 1

	# The buffer upload is the expensive part, so it happens once per frame no
	# matter how many ticks that frame ran.
	if ticks > 0:
		crowd.update_transforms()

	# Spiral of death guard: if the frame could not keep up, drop the backlog
	# instead of trying to catch up forever and making the next frame worse.
	if _accumulator > step * GameConfig.MAX_TICKS_PER_FRAME:
		_accumulator = 0.0


## Rebuilds from whatever GameConfig currently holds. This is what the debug UI
## calls, and what makes bot count and seed restart-scoped rather than fixed.
func restart() -> void:
	rebuild(GameConfig.map_seed, GameConfig.bot_count)


## Regenerates the island and repopulates it. Same seed, same result.
func rebuild(map_seed: int, bot_count: int) -> void:
	world.generate(map_seed)
	bots.spawn(bot_count, map_seed)
	crowd.rebuild()
	tick_count = 0
	sim_time = 0.0
	_accumulator = 0.0
