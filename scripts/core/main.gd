extends Node3D
## Owns the order in which the simulation is built.
##
## World and BotManager deliberately do not build themselves in _ready. Bots can
## only be placed once the island exists, and leaning on sibling _ready order to
## guarantee that is a hidden dependency that breaks the first time somebody
## reorders the scene tree. Restarting later means calling rebuild() again, in
## one place, rather than reloading the scene.

@export var world_path: NodePath = ^"World"
@export var bots_path: NodePath = ^"Bots"

var world: World
var bots: BotManager


func _ready() -> void:
	world = get_node_or_null(world_path) as World
	bots = get_node_or_null(bots_path) as BotManager
	if world == null:
		push_error("Main: world_path does not point at a World node (%s)." % world_path)
		return
	if bots == null:
		push_error("Main: bots_path does not point at a BotManager node (%s)." % bots_path)
		return
	bots.world = world
	rebuild(GameConfig.map_seed, GameConfig.bot_count)


## Regenerates the island and repopulates it. Same seed, same result.
func rebuild(map_seed: int, bot_count: int) -> void:
	world.generate(map_seed)
	bots.spawn(bot_count, map_seed)
