class_name EarthquakeEvent
extends WorldEvent
## The ground rips open and keeps ripping for Earthquake.DURATION seconds —
## TODO.md item 52, redesigned from a single instant tear into a continuous
## one after the owner watched a real run and asked for it to actually last
## and to leave real pits, not marks.
##
## Owns nothing itself: triggering it hands an Earthquake to the event
## manager (the same shape MonsterEvent/KrakenEvent already use for their
## own ongoing objects), and the quake is what keeps tearing new rifts open
## on the simulation clock.


func id() -> StringName:
	return &"earthquake"


## params: "x"/"z" to force the first rift's starting point (every later
## strike, and the rest of the first rift's own path, still comes from the
## seeded stream). Both optional, so trigger("earthquake") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	var quake := Earthquake.start(world, events.bots, at, rng,
		func(line: String) -> void: events.report(&"earthquake", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, Earthquake.SEGMENT_LENGTH * Earthquake.SEGMENTS_PER_RIFT, strength),
		func(effect: Node) -> void: events.adopt_visual(effect))
	if quake == null:
		return ""
	events.adopt(quake)

	return "Earthquake at (%d, %d): the ground keeps tearing for %d s" \
		% [roundi(at.x), roundi(at.y), int(Earthquake.DURATION)]
