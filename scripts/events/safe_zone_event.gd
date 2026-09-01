class_name SafeZoneEvent
extends WorldEvent
## A safe circle that jumps to a fresh spot every so often, tightening a
## little each time, instead of one wall shrinking toward a fixed centre.
##
## The redesign this project's third catastrophe needed once Volcano's own
## advancing lava front took over the "boundary closes in on a centre" shot —
## mechanically that was indistinguishable from Flood. A jumping zone asks a
## different question of the crowd each time it moves: not "how much closer
## is safe getting" but "where did it go this time."
##
## Owns no state. Triggering it hands a SafeZone to the event manager, and
## the zone is what jumps and hurts on the simulation clock.

## Where the wall starts and finishes, as shares of the map, so the zone
## keeps its proportions whatever MAP_SIZE becomes. Generous at first — the
## opening position is a grace period, not a threat — and tight by the last
## jump, small enough that a crowd caught outside it truly has nowhere close.
const START_SHARE_OF_MAP := 0.32
const FINAL_SHARE_OF_MAP := 0.07

## How many positions the zone is ever safe at, including the first. Four
## jumps after the opening one: enough for the crowd to feel the pattern
## ("it's going to move again") without the event outlasting its welcome.
const JUMP_COUNT := 5
## How long the wall stays at each position before jumping again, in
## simulation seconds.
const JUMP_INTERVAL_SECONDS := 14.0

## Health per second lost outside the wall. At full health that is twelve
## seconds outside before dying, so being caught is a problem rather than a
## verdict, and a bot that turns and runs can still make it in.
const DAMAGE_PER_SECOND := 8.0

## Candidate centres tried for the opening position when nobody says where to
## put it. High ground wins, the same reasoning the old shrinking wall's own
## opening position used: guaranteed land, and a dramatic place to start.
## Every jump after the first is a plain random land point — by then the
## crowd is reacting to where the wall went, not to the summit it started on.
const CENTRE_CANDIDATES := 12


func id() -> StringName:
	return &"zone"


## params: "x"/"z" for the opening centre, "radius"/"final" for the start and
## end sizes, "jumps" for how many positions, "interval" for how long each one
## lasts, "damage" for the rate outside. All optional, so trigger("zone") on
## its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var radius_start := float(params.get("radius", GameConfig.MAP_SIZE * START_SHARE_OF_MAP))
	var radius_end := float(params.get("final", GameConfig.MAP_SIZE * FINAL_SHARE_OF_MAP))
	var jumps := int(params.get("jumps", JUMP_COUNT))
	var interval := float(params.get("interval", JUMP_INTERVAL_SECONDS))
	var damage := float(params.get("damage", DAMAGE_PER_SECOND))

	var centre: Vector2
	if params.has("x") and params.has("z"):
		centre = Vector2(float(params["x"]), float(params["z"]))
	else:
		centre = _high_ground(world, rng)

	# Two zones at once would each be hurting people for crossing a line the
	# other one does not have.
	for child in events.get_children():
		if child is SafeZone and not child.is_queued_for_deletion():
			push_error("SafeZoneEvent: a zone is already active.")
			return ""

	var zone := SafeZone.start(world, events.bots, rng, centre, radius_start, radius_end,
		jumps, interval, damage,
		func(line: String) -> void: events.report(&"zone", line),
		func(at: Vector3, strength: float) -> void: events.shake(at, radius_start, strength))
	if zone == null:
		# start() has already said which argument was wrong.
		return ""
	events.adopt(zone)

	return "Zone opens at (%d, %d), r%dm, jumping %d times" \
		% [roundi(centre.x), roundi(centre.y), roundi(radius_start), jumps - 1]


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
