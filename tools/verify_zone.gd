extends Node
## Checks the jumping safe zone: that each position hurts whoever is outside
## it and leaves whoever is inside it alone, that the crowd runs toward
## wherever the wall currently is, that it actually jumps as many times as
## asked before vanishing, and that none of it grows out of proportion at
## ten thousand.
##
## Timings printed by this tool are **information, not a budget**. A long check
## run heats the laptop, and a throttled core makes every later measurement read
## high: a pure arithmetic loop touching nothing at all measures 66 ms at the
## start of a process and 219 ms after three hundred rendered frames, for
## identical work. The assertions below are loose enough to catch an algorithm
## that has gone quadratic and nothing finer than that. Real numbers come from
## tools/profile_tick.gd, in its own short process.


const BOTS := 2000
## The real event, at the real speed, just fewer/shorter positions than the
## default so the whole thing finishes inside a check — see verify_war's own
## note on why a compressed-duration event proves nothing about the real one.
const FROM := 380.0
const TO := 90.0
const JUMPS := 4
const INTERVAL := 8.0
const DAMAGE := 8.0
## How far inside the wall a bot has to be to count as safely inside while the
## boundary is being checked. Wider than anything can travel in the eight ticks
## the census runs over: a panicked knight covers 3 m and the wall covers 0 m
## between jumps — this event's wall does not move except at a jump.
const SAFE_MARGIN := 12.0
const MAX_TICKS := 4000


func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var world: World = main.get_node("World")
	var bots: BotManager = main.get_node("Bots")
	var events: EventManager = main.get_node("Events")
	var step := GameConfig.SIMULATION_TICK_SECONDS

	print("--- the registry ---")
	print("  known events   : ", events.known())
	failures += _check("the zone is registered", events.has_event(&"zone"))

	print("--- it opens ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	## A few ticks so the crowd is walking rather than standing where it spawned.
	for t in 20:
		bots.tick(step, t)

	var start_alive := bots.alive_count
	failures += _check("the zone fired", events.trigger(&"zone",
		{"radius": FROM, "final": TO, "jumps": JUMPS, "interval": INTERVAL, "damage": DAMAGE}))
	print("  announced      : %s" % events.last_description)
	failures += _check("it announces how many times it will jump",
		events.last_description.contains("jumping %d times" % (JUMPS - 1)))
	failures += _check("nobody is hurt yet", bots.alive_count == start_alive)
	failures += _check("a second zone is refused while one is active",
		not events.trigger(&"zone"))

	var zone := _find_zone(events)
	failures += _check("the zone is in flight", zone != null)
	var ring := _find_ring(zone)
	failures += _check("it put a wall on the map", ring != null)
	failures += _check("the wall belongs to the zone", ring != null and ring.get_parent() == zone)
	var centre := Vector2(ring.position.x, ring.position.z) if ring != null else Vector2.ZERO
	print("  centre         : (%d, %d) at %.1f m"
		% [roundi(centre.x), roundi(centre.y), world.get_height(centre.x, centre.y)])
	failures += _check("the opening centre is on land it can stand on",
		world.is_walkable(centre.x, centre.y))
	failures += _check("and on high ground (%.1f m)" % world.get_height(centre.x, centre.y),
		world.get_height(centre.x, centre.y) > GameConfig.TERRAIN_HEIGHT * 0.15)

	print("--- the first position, before it ever jumps ---")
	var ticks_per_position := int(INTERVAL / step) + 4
	var midpoint_inward := 0.0
	var midpoint_running := 0
	var hurt_inside := 0
	var watched_total := 0
	var t := 0
	while t < ticks_per_position / 2:
		bots.tick(step, t)
		events.advance(step)
		t += 1
	midpoint_inward = _inward_share(bots, centre)
	midpoint_running = _count_state(bots, BotManager.State.FLEEING)
	## Health is a history, not a place — see verify_war's own note on the same
	## shape of mistake. What has to hold is that nobody is hurt *while*
	## inside, so take a census of the ones well inside, run two sweeps, and
	## see whether any of them lost anything, all before the wall has any
	## chance to have jumped out from under them.
	var wall: float = ring.radius() if ring != null else 0.0
	var watched := _well_inside(bots, centre, wall - SAFE_MARGIN)
	var before := PackedFloat32Array()
	for i in watched:
		before.append(bots.health[i])
	for extra in 8:
		bots.tick(step, t)
		events.advance(step)
		t += 1
	wall = ring.radius() if ring != null else 0.0
	for k in watched.size():
		var who := watched[k]
		if not _within(bots, who, centre, wall - SAFE_MARGIN):
			continue
		watched_total += 1
		if bots.health[who] < before[k] - 0.0001:
			hurt_inside += 1

	print("  running        : %d at the midpoint" % midpoint_running)
	print("  running inward : %.1f%%" % (midpoint_inward * 100.0))
	failures += _check("the ones outside ran (%d)" % midpoint_running, midpoint_running > 0)
	failures += _check("and they ran toward the current wall (%.1f%%)" % (midpoint_inward * 100.0),
		midpoint_inward > 0.95)
	print("  watched inside : %d over two sweeps" % watched_total)
	failures += _check("nobody was hurt while inside the wall (%d of %d were)"
		% [hurt_inside, watched_total], hurt_inside == 0 and watched_total > 0)

	print("--- it jumps, and eventually vanishes ---")
	var jumps_seen := 0
	var last_centre := centre
	while t < MAX_TICKS and is_instance_valid(zone) and not zone.is_queued_for_deletion():
		bots.tick(step, t)
		events.advance(step)
		if is_instance_valid(ring):
			var now := Vector2(ring.position.x, ring.position.z)
			if now.distance_to(last_centre) > 1.0:
				jumps_seen += 1
				last_centre = now
		t += 1

	print("  reported       : %s" % events.last_description)
	print("  jumps seen     : %d (of %d expected)" % [jumps_seen, JUMPS - 1])
	print("  ended at tick  : %d" % t)
	failures += _check("it jumped as many times as asked", jumps_seen == JUMPS - 1)
	failures += _check("it finished inside the tick budget", t < MAX_TICKS)
	failures += _check("it reported vanishing", events.last_description.contains("vanishes"))
	failures += _check("the zone freed itself", _find_zone(events) == null)
	failures += _check("people died (%d)" % (start_alive - bots.alive_count),
		bots.alive_count < start_alive)
	failures += _check("but not all of them (%d left)" % bots.alive_count, bots.alive_count > 0)

	print("--- bad parameters ---")
	failures += _check("a zone that grows is refused",
		not events.trigger(&"zone", {"radius": 100.0, "final": 200.0}))
	failures += _check("a zero final radius is refused",
		not events.trigger(&"zone", {"final": 0.0}))
	failures += _check("zero jumps is refused", not events.trigger(&"zone", {"jumps": 0}))
	failures += _check("a zero interval is refused", not events.trigger(&"zone", {"interval": 0.0}))
	failures += _check("zero damage is refused", not events.trigger(&"zone", {"damage": 0.0}))
	failures += _check("negative damage is refused", not events.trigger(&"zone", {"damage": -3.0}))
	failures += _check("and none of that started a zone", _find_zone(events) == null)

	print("--- determinism ---")
	var first := _run_and_count(main, bots, events, step)
	var second := _run_and_count(main, bots, events, step)
	print("  same seed      : %d | %d survivors" % [first, second])
	failures += _check("the same seed kills the same people", first == second)

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"zone",
		{"radius": FROM, "final": TO, "jumps": JUMPS, "interval": INTERVAL, "damage": DAMAGE})
	var sweep := PackedFloat32Array()
	for t2 in ticks_per_position * JUMPS:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		sweep.append(float(Time.get_ticks_usec() - t0))
	print("  zone           : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(sweep), _worst_ms(sweep), sweep.size()])
	print("  dead           : %d of 10000" % (10000 - bots.alive_count))
	failures += _check("the zone has not gone quadratic (%.2f ms worst)" % _worst_ms(sweep),
		_worst_ms(sweep) < 200.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _find_zone(events: EventManager) -> SafeZone:
	for child in events.get_children():
		if child is SafeZone and not child.is_queued_for_deletion():
			return child
	return null


func _find_ring(zone: SafeZone) -> ZoneRing:
	if zone == null:
		return null
	for child in zone.get_children():
		if child is ZoneRing:
			return child
	return null


## Share of the bots currently running whose destination is closer to the centre
## than they are. The one thing the event has to get right.
func _inward_share(bots: BotManager, centre: Vector2) -> float:
	var inward := 0
	var total := 0
	for i in bots.count:
		if bots.alive[i] == 0 or bots.state[i] != BotManager.State.FLEEING:
			continue
		total += 1
		var here := Vector2(bots.pos_x[i], bots.pos_z[i]).distance_to(centre)
		var there := Vector2(bots.target_x[i], bots.target_z[i]).distance_to(centre)
		if there < here:
			inward += 1
	return float(inward) / float(total) if total > 0 else 0.0


## Everyone alive and comfortably inside a radius, by index.
func _well_inside(bots: BotManager, centre: Vector2, radius: float) -> PackedInt32Array:
	var found := PackedInt32Array()
	for i in bots.count:
		if _within(bots, i, centre, radius):
			found.append(i)
	return found


func _within(bots: BotManager, index: int, centre: Vector2, radius: float) -> bool:
	if bots.alive[index] == 0 or radius <= 0.0:
		return false
	var dx := bots.pos_x[index] - centre.x
	var dz := bots.pos_z[index] - centre.y
	return dx * dx + dz * dz <= radius * radius


func _count_state(bots: BotManager, state: int) -> int:
	var n := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.state[i] == state:
			n += 1
	return n


## A fresh island, a fresh crowd and one zone carried all the way to
## vanishing. Returns how many were left standing.
func _run_and_count(main: Node3D, bots: BotManager, events: EventManager, step: float) -> int:
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	events.trigger(&"zone",
		{"radius": FROM, "final": TO, "jumps": JUMPS, "interval": INTERVAL, "damage": DAMAGE})
	var zone := _find_zone(events)
	var t := 0
	while t < MAX_TICKS and is_instance_valid(zone) and not zone.is_queued_for_deletion():
		bots.tick(step, t)
		events.advance(step)
		t += 1
	return bots.alive_count


## Median of a set of microsecond samples, in milliseconds.
##
## Never the mean and never the worst. The same deterministic tick measures 15 ms
## on one run of this tool and 43 ms on the next, with the crowd in a
## bit-identical state, because the machine has other things to do. A worst-case
## assertion measures the operating system; a median measures the code.
func _median_ms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sorted := samples.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var middle := sorted.size() / 2
	return sorted[middle] / 1000.0


func _worst_ms(samples: PackedFloat32Array) -> float:
	var top := 0.0
	for v in samples:
		top = maxf(top, v)
	return top / 1000.0


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
