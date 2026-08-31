class_name TornadoEvent
extends WorldEvent
## A funnel touches down somewhere on the island and wanders it unpredictably
## until it blows itself out.
##
## Owns no state itself. Triggering it hands a Tornado to the event manager,
## and the tornado is what wanders, frightens and throws on the simulation
## clock.

func id() -> StringName:
	return &"tornado"


## params: "x"/"z" to place where it touches down. Optional, so
## trigger("tornado") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	# Two funnels tossing bots independently would be confusing to read as
	# one event and to credit a report to — the same reasoning MonsterEvent
	# and KrakenEvent already refuse a second giant for.
	for child in events.get_children():
		if child is Tornado and not child.is_queued_for_deletion():
			push_error("TornadoEvent: a tornado is already loose.")
			return ""

	var tornado := Tornado.start(world, events.bots, at, rng,
		func(line: String) -> void: events.report(&"tornado", line))
	if tornado == null:
		return ""
	events.adopt(tornado)

	return "A tornado touches down at (%d, %d)" % [roundi(at.x), roundi(at.y)]
