extends Node
## Checks the boss arena (scenes/boss_arena.tscn): the ground is flat, no
## forest grows on it, both giants are registered and callable, neither
## starts on its own, and the level-switch buttons point the right way.

## How much flatter than the ordinary island this has to be to count as
## "flat". Dropping the relief/ridge noise (see IslandGenerator's `flat`
## flag) does not just remove hills — the shore rescale denominator still
## assumes the noise's own contribution to the elevation budget, so a flat
## island's real peak lands far under GameConfig.TERRAIN_HEIGHT (measured:
## ~20 m, not 140 m). A gentle dome under 4% grade across the whole island
## is exactly what "flat" was for, so this checks against the real number
## rather than the ordinary island's own noisy range.
const MAX_FLAT_SPREAD := 25.0


func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/boss_arena.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var world: World = main.get_node("World")
	var bots: BotManager = main.get_node("Bots")
	var events: EventManager = main.get_node("Events")
	var menu: PauseMenu = main.get_node("PauseMenu")

	print("--- the ground ---")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var lo := INF
	var hi := -INF
	for i in 200:
		var p := world.random_land_point(rng)
		var h := world.get_height(p.x, p.y)
		lo = minf(lo, h)
		hi = maxf(hi, h)
	print("  land height spread: %.2f .. %.2f m (%.2f m)" % [lo, hi, hi - lo])
	failures += _check("the arena is flat (spread %.2f m < %.2f m)" % [hi - lo, MAX_FLAT_SPREAD],
		hi - lo < MAX_FLAT_SPREAD)
	failures += _check("there is still land to stand on", world.land_fraction() > 0.05)

	print("--- no forest ---")
	failures += _check("Main has no vegetation wired up on this map", main.vegetation == null)

	print("--- the registry ---")
	print("  known events   : ", events.known())
	failures += _check("the monster is registered", events.has_event(&"monster"))
	failures += _check("the kraken is registered", events.has_event(&"kraken"))
	failures += _check("the volcano is not registered (no mountain here)",
		not events.has_event(&"volcano"))

	print("--- nothing starts on its own ---")
	bots.spawn(500, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	var step := GameConfig.SIMULATION_TICK_SECONDS
	for t in 20:
		bots.tick(step, t)
		events.advance(step)
	var giants := 0
	for child in events.get_children():
		if child is Monster or child is Kraken:
			giants += 1
	failures += _check("no boss appeared without being called (%d found)" % giants, giants == 0)

	print("--- both bosses are callable ---")
	failures += _check("the monster can be summoned", events.trigger(&"monster"))
	failures += _check("a monster is actually standing there", _find_monster(events) != null)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	failures += _check("the kraken can be summoned", events.trigger(&"kraken"))
	failures += _check("a kraken is actually swimming there", _find_kraken(events) != null)

	print("--- the way out ---")
	failures += _check("the menu leads back to the island",
		menu.back_scene_path == "res://scenes/main.tscn")
	failures += _check("and to the volcano too",
		menu.volcano_scene_path == "res://scenes/volcano.tscn")
	failures += _check("but not to itself", menu.arena_scene_path == "")

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _find_monster(events: EventManager) -> Monster:
	for child in events.get_children():
		if child is Monster:
			return child
	return null


func _find_kraken(events: EventManager) -> Kraken:
	for child in events.get_children():
		if child is Kraken:
			return child
	return null


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
