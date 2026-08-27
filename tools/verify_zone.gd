extends Node
## Checks the shrinking safe zone: that the wall closes to the radius it said,
## that being outside it hurts and being inside it does not, that the crowd runs
## inwards rather than anywhere else, that the boundary on screen is where the
## damage is, and that none of it grows out of proportion at ten thousand.
##
## Timings printed by this tool are **information, not a budget**. A long check
## run heats the laptop, and a throttled core makes every later measurement read
## high: a pure arithmetic loop touching nothing at all measures 66 ms at the
## start of a process and 219 ms after three hundred rendered frames, for
## identical work. The assertions below are loose enough to catch an algorithm
## that has gone quadratic and nothing finer than that. Real numbers come from
## tools/profile_tick.gd, in its own short process.


const BOTS := 2000
## The real event, at the real speed. An earlier version of this check squeezed
## the same distance into six seconds to keep the run short, and every single
## assertion about the crowd became meaningless: a wall closing at 48 m/s is not
## something anyone can run from, and six seconds of damage at the real rate
## cannot kill anybody, so it measured nobody dying and everybody left outside.
## The wall has to move at a speed a knight can be measured against.
const FROM := 380.0
const TO := 90.0
const SECONDS := 55.0
const DAMAGE := 8.0
## How far inside the wall a bot has to be to count as safely inside while the
## boundary is being checked. Wider than anything can travel in the eight ticks
## the census runs over: a panicked knight covers 3 m and the wall covers 2.
const SAFE_MARGIN := 12.0


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

	print("--- closing in ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	## A few ticks so the crowd is walking rather than standing where it spawned.
	for t in 20:
		bots.tick(step, t)

	var start_alive := bots.alive_count
	failures += _check("the zone fired", events.trigger(&"zone",
		{"radius": FROM, "final": TO, "seconds": SECONDS, "damage": DAMAGE}))
	print("  announced      : %s" % events.last_description)
	failures += _check("it announces where it stops", events.last_description.contains("r%d" % roundi(TO)))
	failures += _check("nobody is hurt yet", bots.alive_count == start_alive)
	failures += _check("a second zone is refused while one is closing",
		not events.trigger(&"zone"))

	var zone := _find_zone(events)
	failures += _check("the zone is in flight", zone != null)
	var ring := _find_ring(zone)
	failures += _check("it put a wall on the map", ring != null)
	## Ownership, not decoration: the wall is a child of the zone, so it cannot
	## outlive the boundary it is drawing.
	failures += _check("the wall belongs to the zone", ring != null and ring.get_parent() == zone)
	var centre := Vector2(ring.position.x, ring.position.z) if ring != null else Vector2.ZERO
	print("  centre         : (%d, %d) at %.1f m"
		% [roundi(centre.x), roundi(centre.y), world.get_height(centre.x, centre.y)])
	failures += _check("the centre is on land it can stand on",
		world.is_walkable(centre.x, centre.y))
	## The centre is picked as the highest of a dozen land points, so it should be
	## well above the average of them rather than merely dry.
	failures += _check("and on high ground (%.1f m)" % world.get_height(centre.x, centre.y),
		world.get_height(centre.x, centre.y) > GameConfig.TERRAIN_HEIGHT * 0.15)

	var ticks := int(SECONDS / step) + 4
	var midpoint_inward := 0.0
	var midpoint_running := 0
	var hurt_inside := 0
	var watched_total := 0
	for t in ticks:
		bots.tick(step, t)
		events.advance(step)
		if t == ticks / 2:
			midpoint_inward = _inward_share(bots, centre)
			midpoint_running = _count_state(bots, BotManager.State.FLEEING)
			## Health is a history, not a place. Counting hurt bots standing inside
			## the wall proved nothing: a bot that took damage outside and then ran
			## in is exactly that, and it is the event working. What has to hold is
			## that nobody is hurt *while* inside, so take a census of the ones well
			## inside, run two sweeps, and see whether any of them lost anything.
			var wall: float = ring.radius() if ring != null else 0.0
			var watched := _well_inside(bots, centre, wall - SAFE_MARGIN)
			var before := PackedFloat32Array()
			for i in watched:
				before.append(bots.health[i])
			for extra in 8:
				bots.tick(step, t + 1 + extra)
				events.advance(step)
			wall = ring.radius() if ring != null else 0.0
			for k in watched.size():
				var who := watched[k]
				if not _within(bots, who, centre, wall - SAFE_MARGIN):
					continue
				watched_total += 1
				if bots.health[who] < before[k] - 0.0001:
					hurt_inside += 1

	print("  reported       : %s" % events.last_description)
	print("  alive          : %d of %d" % [bots.alive_count, start_alive])
	failures += _check("it reported closing", events.last_description.contains("closed"))
	failures += _check("people died (%d)" % (start_alive - bots.alive_count),
		bots.alive_count < start_alive)
	failures += _check("but not all of them (%d left)" % bots.alive_count, bots.alive_count > 0)

	print("--- who ran and where ---")
	print("  running        : %d at the midpoint" % midpoint_running)
	print("  running inward : %.1f%%" % (midpoint_inward * 100.0))
	failures += _check("the ones outside ran (%d)" % midpoint_running, midpoint_running > 0)
	failures += _check("and they ran inwards (%.1f%%)" % (midpoint_inward * 100.0),
		midpoint_inward > 0.95)
	## The whole shape of the event: the wall is the only thing that hurts, so
	## standing inside it has to be completely safe.
	print("  watched inside : %d over two sweeps" % watched_total)
	failures += _check("nobody was hurt while inside the wall (%d of %d were)"
		% [hurt_inside, watched_total], hurt_inside == 0 and watched_total > 0)

	print("--- where everyone ended up ---")
	var outside := 0
	for i in bots.count:
		if bots.alive[i] == 0:
			continue
		var dx := bots.pos_x[i] - centre.x
		var dz := bots.pos_z[i] - centre.y
		if sqrt(dx * dx + dz * dz) > TO:
			outside += 1
	print("  left outside   : %d of %d survivors" % [outside, bots.alive_count])
	## Not zero: a bot can be alive outside the final wall, it just cannot have
	## been there long. Most of the survivors should be inside it.
	failures += _check("most survivors made it inside (%d of %d outside)"
		% [outside, bots.alive_count], outside < bots.alive_count / 2)

	failures += _check("the zone freed itself", _find_zone(events) == null)

	print("--- bad parameters ---")
	failures += _check("a zone that grows is refused",
		not events.trigger(&"zone", {"radius": 100.0, "final": 200.0}))
	failures += _check("a zero final radius is refused",
		not events.trigger(&"zone", {"final": 0.0}))
	failures += _check("a zero duration is refused",
		not events.trigger(&"zone", {"seconds": 0.0}))
	failures += _check("zero damage is refused", not events.trigger(&"zone", {"damage": 0.0}))
	failures += _check("negative damage is refused", not events.trigger(&"zone", {"damage": -3.0}))
	failures += _check("and none of that started a zone", _find_zone(events) == null)

	print("--- determinism ---")
	var first := _close_and_count(main, bots, events, step, ticks)
	var second := _close_and_count(main, bots, events, step, ticks)
	print("  same seed      : %d | %d survivors" % [first, second])
	failures += _check("the same seed kills the same people", first == second)

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"zone", {"radius": FROM, "final": TO, "seconds": SECONDS, "damage": DAMAGE})
	var sweep := PackedFloat32Array()
	for t in ticks:
		bots.tick(step, t)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		sweep.append(float(Time.get_ticks_usec() - t0))
	print("  zone           : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(sweep), _worst_ms(sweep), sweep.size()])
	print("  dead           : %d of 10000" % (10000 - bots.alive_count))
	failures += _check("the zone has not gone quadratic (%.2f ms worst)" % _worst_ms(sweep),
		_worst_ms(sweep) < 200.0)

	## The sweep is not where this event could get expensive. Squeezing the
	## survivors into a 90 m circle is: separation cost goes up with the square
	## of how tightly packed the crowd is, and that shows up in the tick rather
	## than in anything the zone does. Informational, like every timing here.
	var packed_tick := PackedFloat32Array()
	for t in 60:
		var t0 := Time.get_ticks_usec()
		bots.tick(step, t)
		packed_tick.append(float(Time.get_ticks_usec() - t0))
	print("  tick, packed   : %.2f ms median, %.2f ms worst, %d alive in r%d"
		% [_median_ms(packed_tick), _worst_ms(packed_tick), bots.alive_count, roundi(TO)])
	failures += _check("the packed crowd has not gone quadratic (%.2f ms)"
		% _median_ms(packed_tick), _median_ms(packed_tick) < 200.0)

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


## A fresh island, a fresh crowd and one zone carried to the end. Returns how
## many were left standing.
func _close_and_count(main: Node3D, bots: BotManager, events: EventManager,
			step: float, ticks: int) -> int:
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	events.trigger(&"zone", {"radius": FROM, "final": TO, "seconds": SECONDS, "damage": DAMAGE})
	for t in ticks:
		bots.tick(step, t)
		events.advance(step)
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
