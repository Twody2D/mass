class_name SafeZoneEvent
extends WorldEvent
## The survivable part of the island shrinks until there is almost none of it.
##
## The third shape of catastrophe this project has, and deliberately the slowest
## of the three: the meteor is one instant, the flood is a direction, and this
## is a deadline. Nobody is killed by the boundary arriving — they are killed by
## being too slow, which is the first event here that separates the crowd by
## something the crowd itself does.
##
## Owns no state. Triggering it hands a SafeZone to the event manager, and the
## zone is what moves the wall on the simulation clock.

## Where the wall starts and finishes, as shares of the map, so the zone keeps
## its proportions whatever MAP_SIZE becomes. It starts out at the coast and
## ends on a patch big enough to hold a crowd without turning it into a heap.
const START_SHARE_OF_MAP := 0.42
const FINAL_SHARE_OF_MAP := 0.09

## How long the wall takes to close, in simulation seconds. Set against the
## crowd rather than against the clock: over a minute the boundary comes in at
## about 5.6 m/s, a panicked knight runs at 7.7, and the slowest tenth of them
## run at 5.4. So an average bot that starts running keeps ahead of it and the
## stragglers do not, which is the whole event.
const SHRINK_SECONDS := 60.0

## Health per second lost outside the wall. At full health that is twelve
## seconds outside before dying, so being caught is a problem rather than a
## verdict, and a bot that turns and runs can still make it in.
const DAMAGE_PER_SECOND := 8.0

## Candidate centres tried when nobody says where to put it. High ground wins:
## it is guaranteed to be land, it is surrounded by land rather than by a
## coastline the crowd would pile up against, and a last stand on a peak is the
## shot worth having.
const CENTRE_CANDIDATES := 12


func id() -> StringName:
	return &"zone"


## params: "x" and "z" for the centre, "radius" and "final" for where the wall
## starts and stops, "seconds" for how long it takes, "damage" for the rate
## outside. All optional, so trigger("zone") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world

	var from_radius := float(params.get("radius", GameConfig.MAP_SIZE * START_SHARE_OF_MAP))
	var to_radius := float(params.get("final", GameConfig.MAP_SIZE * FINAL_SHARE_OF_MAP))
	var seconds := float(params.get("seconds", SHRINK_SECONDS))
	var damage := float(params.get("damage", DAMAGE_PER_SECOND))

	var centre: Vector2
	if params.has("x") and params.has("z"):
		centre = Vector2(float(params["x"]), float(params["z"]))
	else:
		centre = _high_ground(world, events.rng())

	## Two zones at once would each be hurting people for crossing a line the
	## other one does not have. Refusing is better than a crowd dying to a wall
	## that is not on screen.
	for child in events.get_children():
		if child is SafeZone and not child.is_queued_for_deletion():
			push_error("SafeZoneEvent: a zone is already closing.")
			return ""

	var zone := SafeZone.start(world, events.bots, centre, from_radius, to_radius,
		seconds, damage, func(line: String) -> void: events.report(&"zone", line))
	if zone == null:
		## start() has already said which argument was wrong.
		return ""
	events.adopt(zone)

	return "Zone closing to r%dm over %ds" % [roundi(to_radius), roundi(seconds)]


## The highest of a handful of random land points. Cheap on purpose: this is a
## dozen height lookups picking somewhere good, not a search for the summit.
func _high_ground(world: World, rng: RandomNumberGenerator) -> Vector2:
	var best := world.random_land_point(rng)
	var best_height := world.get_height(best.x, best.y)
	for i in CENTRE_CANDIDATES - 1:
		var point := world.random_land_point(rng)
		var height := world.get_height(point.x, point.y)
		if height > best_height:
			best = point
			best_height = height
	return best
