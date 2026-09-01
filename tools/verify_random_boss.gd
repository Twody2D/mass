extends Node
## Checks the random-boss button: that it actually summons something from
## the roster, that it reports as if that boss's own id had fired directly
## rather than wrapping "boss" around it, that it skips a boss already loose
## in favour of another rather than just refusing, and that it genuinely
## refuses once every boss in the roster is busy.

const ROSTER_IDS: Array[StringName] = [&"monster", &"kraken", &"chicken", &"crab", &"snake", &"giraffe"]
const BOTS := 200


func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var events: EventManager = main.get_node("Events")
	var bots: BotManager = main.get_node("Bots")

	print("--- the registry ---")
	print("  known events   : ", events.known())
	failures += _check("the random boss button is registered", events.has_event(&"boss"))
	for boss_id in ROSTER_IDS:
		failures += _check("the roster's own %s is registered" % boss_id,
			events.has_event(boss_id))

	print("--- it actually summons something ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	failures += _check("it fired", events.trigger(&"boss", {"health": 40.0}))
	print("  announced      : %s" % events.last_description)
	var summoned := _find_any_giant(events)
	failures += _check("something from the roster is actually standing there", summoned != "")
	print("  summoned       : %s" % summoned)
	var expected_word := _expected_word(summoned)
	var mentions_it := events.last_description.contains(expected_word)
	failures += _check("the report reads as that giant's own line (mentions %s), not boss wrapped around it"
		% expected_word, mentions_it)
	failures += _check("last_id is boss even though the description is the real giant's own",
		events.last_id == &"boss")

	print("--- it skips a busy one rather than refusing outright ---")
	# Whichever one just got summoned is loose; firing again must not retry
	# that same one and fail — it should find a different giant, since five
	# others are still free.
	var second_ok := events.trigger(&"boss", {"health": 40.0})
	failures += _check("a second summon still succeeds while the first is loose", second_ok)
	if second_ok:
		var second := _find_any_giant(events)
		print("  second         : %s" % second)

	print("--- it genuinely refuses once the whole roster is busy ---")
	# Fill every slot by hand, deterministically, rather than trusting
	# random picks to eventually cover all six within a reasonable number
	# of tries.
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	for boss_id in ROSTER_IDS:
		events.trigger(boss_id, {"health": 40.0})
	failures += _check("every roster member accepted its own direct trigger",
		_count_giants(events) == ROSTER_IDS.size())
	failures += _check("with everything busy, the random button refuses",
		not events.trigger(&"boss", {"health": 40.0}))

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _expected_word(class_name_string: String) -> String:
	match class_name_string:
		"Monster":
			return "monster"
		"Kraken":
			return "kraken"
		"GiantBird":
			return "chicken"
		"Crabylon":
			return "crab"
		"Titanoboo":
			return "snake"
		"Giraffaxon":
			return "giraffe"
	return "an impossible word nothing will ever contain"


## The name of whichever giant class is currently adopted, or "" if none is.
func _find_any_giant(events: EventManager) -> String:
	for child in events.get_children():
		if child.is_queued_for_deletion():
			continue
		if child is Monster:
			return "Monster"
		if child is Kraken:
			return "Kraken"
		if child is GiantBird:
			return "GiantBird"
		if child is Crabylon:
			return "Crabylon"
		if child is Titanoboo:
			return "Titanoboo"
		if child is Giraffaxon:
			return "Giraffaxon"
	return ""


func _count_giants(events: EventManager) -> int:
	var n := 0
	for child in events.get_children():
		if (child is Monster or child is Kraken or child is GiantBird or child is Crabylon
				or child is Titanoboo or child is Giraffaxon) and not child.is_queued_for_deletion():
			n += 1
	return n


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
