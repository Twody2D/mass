class_name SupplyDropEvent
extends WorldEvent
## Crates fall out of the sky, the crowd runs for them, and whoever ends up in
## the crush might get shoved out of it.
##
## Unlike every other event here, more than one of these is meant to be in
## flight at once — "mass" is in the name, and unlike a water level or a
## closing wall, there is no shared piece of state for two crates to disagree
## about. Each crate owns its own patch of crowd and its own crush,
## independent of any other drop still going.

const DEFAULT_COUNT := 3
const MAX_COUNT := 8


func id() -> StringName:
	return &"drop"


## params: "count" for how many crates land at once (default 3, capped at 8),
## or "x"/"z" together to place a single crate by hand instead.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var bots := events.bots

	if params.has("x") != params.has("z"):
		push_error("SupplyDropEvent: x and z must be given together, or not at all.")
		return ""

	var points: Array[Vector2] = []
	if params.has("x"):
		points.append(Vector2(float(params["x"]), float(params["z"])))
	else:
		var count := int(params.get("count", DEFAULT_COUNT))
		if count <= 0 or count > MAX_COUNT:
			push_error("SupplyDropEvent: count must be between 1 and %d, got %d."
				% [MAX_COUNT, count])
			return ""
		for i in count:
			points.append(world.random_land_point(events.rng()))

	for point in points:
		var at := Vector3(point.x, world.get_height(point.x, point.y), point.y)
		events.adopt_visual(CrateDrop.create(at, events.rng()))
		var scramble := SupplyScramble.start(bots, point, events.rng(),
			func(line: String) -> void: events.report(&"drop", line))
		if scramble != null:
			events.adopt(scramble)

	return "Supply drop: %d crate%s incoming" % [points.size(), "" if points.size() == 1 else "s"]
