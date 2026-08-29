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
@export var events_path: NodePath = ^"Events"
@export var hud_path: NodePath = ^"DebugHUD"
@export var menu_path: NodePath = ^"PauseMenu"
@export var game_hud_path: NodePath = ^"GameHUD"
@export var camera_path: NodePath = ^"Camera3D"

var world: World
var bots: BotManager
var crowd: CrowdRenderer
var events: EventManager
var hud: DebugHUD
var menu: PauseMenu
var game_hud: GameHUD
var camera: CameraRig
var director: Director

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
	events = get_node_or_null(events_path) as EventManager
	if events == null:
		push_error("Main: events_path does not point at an EventManager node (%s)." % events_path)
		return
	hud = get_node_or_null(hud_path) as DebugHUD
	menu = get_node_or_null(menu_path) as PauseMenu
	game_hud = get_node_or_null(game_hud_path) as GameHUD
	camera = get_node_or_null(camera_path) as CameraRig
	bots.world = world
	crowd.bots = bots
	crowd.camera = camera
	# The renderer follows the crowd rather than being told twice. Anything that
	# repopulates the bots, including a verification tool, gets a MultiMesh the
	# right size without having to know the renderer exists.
	bots.spawned.connect(_on_bots_spawned)
	events.bots = bots
	events.world = world
	if camera != null:
		# So the rig can keep itself above the ground no matter which mode is
		# driving — see CameraRig._clamp_above_ground().
		camera.world = world
		# The only wire between events and the camera, and it runs one way. An
		# event says what happened and where; the camera works out how hard that
		# felt from where it is standing.
		events.shook.connect(camera.shake_from)
		director = camera.mode(&"director") as Director
		if director != null:
			director.wire(bots, events)
	if hud != null:
		hud.main = self
	if menu != null:
		menu.main = self
		menu.camera = camera
	if game_hud != null:
		game_hud.main = self
	rebuild(GameConfig.map_seed, GameConfig.bot_count)
	# Pays the meteor's one-time shader compile cost here, at start-up deep
	# underground, rather than the first real impact paying it mid-shot.
	ShaderWarmup.run(self)


## Rendering is decoupled from the tick: every frame draws the crowd wherever it
## is between the last two ticks, so motion is smooth at any frame rate.
func _process(_delta: float) -> void:
	if crowd == null:
		return
	var alpha := clampf(_accumulator / GameConfig.SIMULATION_TICK_SECONDS, 0.0, 1.0)
	crowd.update_transforms(alpha)
	if events != null:
		# Anything in flight is drawn between the same two ticks the crowd is.
		events.interpolate(alpha)
		# Explosions are decoration and run on frame time, but they still stop
		# when the world does, so the camera can be flown around a frozen one.
		events.time_scale = 0.0 if paused else sim_speed


func _physics_process(delta: float) -> void:
	if paused or bots == null or crowd == null:
		return

	_accumulator += delta * sim_speed
	var step := GameConfig.SIMULATION_TICK_SECONDS
	var ticks := 0
	while _accumulator >= step and ticks < GameConfig.MAX_TICKS_PER_FRAME:
		bots.tick(step, tick_count)
		# Events run on the same clock as the crowd. A meteor in mid air is part
		# of the simulation, not an animation playing next to it.
		events.advance(step)
		tick_count += 1
		sim_time += step
		_accumulator -= step
		ticks += 1

	# Spiral of death guard: if the frame could not keep up, drop the backlog
	# instead of trying to catch up forever and making the next frame worse.
	if _accumulator > step * GameConfig.MAX_TICKS_PER_FRAME:
		_accumulator = 0.0


func _on_bots_spawned(_count: int) -> void:
	crowd.rebuild()


## Rebuilds from whatever GameConfig currently holds. This is what the debug UI
## calls, and what makes bot count and seed restart-scoped rather than fixed.
func restart() -> void:
	rebuild(GameConfig.map_seed, GameConfig.bot_count)


## Regenerates the island and repopulates it. Same seed, same result.
func rebuild(map_seed: int, bot_count: int) -> void:
	world.generate(map_seed)
	bots.spawn(bot_count, map_seed)
	events.reset(map_seed)
	if director != null:
		director.reseed(map_seed)
	tick_count = 0
	sim_time = 0.0
	_accumulator = 0.0
