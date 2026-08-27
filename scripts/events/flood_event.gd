class_name FloodEvent
extends WorldEvent
## The sea rises and the island shrinks.
##
## The opposite of the meteor in every way that matters, which is the point of
## having both: no impact, no point on the map, nothing to aim at. It takes half
## a minute, it takes the coast first, and there is no cover from it — the only
## answer is higher ground, so the crowd is squeezed into the peaks and the
## island slowly disappears underneath it.
##
## Owns no state itself. Triggering it hands a FloodTide to the event manager,
## and the tide is what moves the water on the simulation clock.

## How far the sea rises, as a share of the peak terrain height, so the flood
## keeps the same bite whatever TERRAIN_HEIGHT becomes. At 0.45 the island loses
## most of its coast and keeps its high ground.
const RISE_SHARE := 0.45

## How long the rise takes, in simulation seconds. Slow on purpose: a flood that
## is over in three seconds is a wave, and the shot here is the crowd being
## pushed uphill for half a minute.
const RISE_SECONDS := 30.0


func id() -> StringName:
	return &"flood"


## params: "rise" for the height in metres, "seconds" for how long it takes.
## Both optional, so trigger("flood") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world

	var rise := float(params.get("rise", GameConfig.TERRAIN_HEIGHT * RISE_SHARE))
	var seconds := float(params.get("seconds", RISE_SECONDS))
	if rise <= 0.0:
		push_error("FloodEvent: rise must be positive, got %f." % rise)
		return ""
	if seconds <= 0.0:
		push_error("FloodEvent: seconds must be positive, got %f." % seconds)
		return ""

	# Two tides at once would fight over the water line, each lerping from a
	# different starting level. Refusing is better than the sea flickering.
	for child in events.get_children():
		if child is FloodTide and not child.is_queued_for_deletion():
			push_error("FloodEvent: the sea is already rising.")
			return ""

	var tide := FloodTide.start(world, events.bots, world.water_level + rise, seconds,
		func(line: String) -> void: events.report(&"flood", line))
	if tide == null:
		return ""
	events.adopt(tide)

	return "Flood rising +%dm over %ds" % [roundi(rise), roundi(seconds)]
