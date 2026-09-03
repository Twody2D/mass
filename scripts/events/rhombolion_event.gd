class_name RhombolionEvent
extends WorldEvent
## A giant lion stalks the island, roaring on a cycle to panic a wider ring
## than its claws actually reach, until archers drive it back.
##
## Owns no state itself. Triggering it hands a Rhombolion to the event
## manager, and the lion is what walks, roars, stomps and falls on the
## simulation clock.

func id() -> StringName:
	return &"lion"


## params: "x"/"z" to place it, "health" for how much it takes to bring down.
## All optional, so trigger("lion") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	var health := float(params.get("health", Rhombolion.MAX_HEALTH))
	if health <= 0.0:
		push_error("RhombolionEvent: health must be positive, got %f." % health)
		return ""

	for child in events.get_children():
		if child is Rhombolion and not child.is_queued_for_deletion():
			push_error("RhombolionEvent: a lion is already loose.")
			return ""

	var lion := Rhombolion.start(world, events.bots, at, health, rng,
		func(line: String) -> void: events.report(&"lion", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, Rhombolion.ATTACK_RANGE, strength),
		func(from: Vector3, to: Vector3) -> void: events.archer_shot(from, to))
	if lion == null:
		return ""
	events.adopt(lion)

	return "A giant lion prowls ashore at (%d, %d)" % [roundi(at.x), roundi(at.y)]
