extends Node
## Every event, at every reference crowd size, triggered exactly the way a
## keypress would: no shortened durations, no hand-picked worst case. Item 19
## is not re-deriving what each event's own verify suite already proved about
## its worst moment at ten thousand — it is the number nobody has taken yet:
## how the same real event scales from 100 to 10 000.
##
## **Measure one thing per process.** This machine throttles: a pure
## arithmetic loop that touches nothing measures 66 ms at the start of a
## process and 219 ms after three hundred rendered frames, for identical work.
## Run with both --event and --count for one honest number in a cold process:
##
##   godot --headless --path . res://tools/profile_events.gd --event=zone --count=10000
##
## Without them this sweeps every event at every size in one process, which is
## useful for a first look but reads high wherever it runs later — recheck any
## number that looks wrong with a cold, single-purpose run.
##
## --total times bots.tick() together with events.advance(), instead of just
## the event's own logic. The default (event-only) matches every verify_*
## suite's "cost at ten thousand" section, and answers "what does this event
## add on top of the simulation". It does not answer "is the simulation
## itself more expensive while this event is redirecting the crowd" — a zone,
## a war and a drop all end with everyone packed into one small patch of
## ground, and separation cost grows with how packed the crowd gets. --total
## is how that got caught for the zone in the first place (see ARCHITECTURE.md):
## the event's own sweep cost nothing, the crowd jammed into the last few
## metres of it was what cost 19 ms.

const COUNTS := [100, 1000, 5000, 10000]
const EVENTS := ["meteor", "flood", "zone", "war", "drop"]

## Ticks run before triggering, so the crowd is walking rather than standing
## where it spawned. Dwell is staggered up to MAX_DWELL, so this has to cover it.
const WARMUP := 20

## Real event durations, in ticks, read from the constants each event actually
## runs on rather than re-guessed here — if one of those changes, this sweep
## keeps measuring the real thing instead of a stale copy of it.
const METEOR_TICKS := 120                                       ## fall + a beat after
const WAR_TICKS := 300                                          ## war has no fixed end


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var bots: BotManager = main.get_node("Bots")
	var events: EventManager = main.get_node("Events")
	var step: float = GameConfig.SIMULATION_TICK_SECONDS

	var wanted_counts := COUNTS
	var wanted_events := EVENTS
	var total := false
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			wanted_counts = [arg.substr(8).to_int()]
		elif arg.begins_with("--event="):
			wanted_events = [arg.substr(8)]
		elif arg == "--total":
			total = true

	if wanted_counts.size() > 1 or wanted_events.size() > 1:
		print("note: sweeping several things in one process. Whatever is measured")
		print("      later reads high on this machine — recheck a surprising number")
		print("      with --event=X --count=N alone in a cold process.")

	var flood_ticks := int((FloodEvent.RISE_SECONDS + 2.0) / step)
	var zone_ticks := int((SafeZoneEvent.SHRINK_SECONDS + 2.0) / step)
	var drop_ticks := int((SupplyScramble.FALL_SECONDS + SupplyScramble.SCRUM_SECONDS + 2.0) / step)

	for event_id in wanted_events:
		for n in wanted_counts:
			main.rebuild(GameConfig.DEFAULT_MAP_SEED, n)
			for t in WARMUP:
				bots.tick(step, t)

			match event_id:
				"meteor":
					_profile(bots, events, step, n, "meteor", {}, METEOR_TICKS, total)
				"flood":
					_profile(bots, events, step, n, "flood", {}, flood_ticks, total)
				"zone":
					_profile(bots, events, step, n, "zone", {}, zone_ticks, total)
				"war":
					_profile(bots, events, step, n, "war", {}, WAR_TICKS, total)
				"drop":
					_profile(bots, events, step, n, "drop", {}, drop_ticks, total)
				_:
					push_error("profile_events: unknown event '%s'." % event_id)

	get_tree().quit()


## Triggers one event with the parameters a keypress would use and measures
## every tick of its real run, the same way Main actually drives one: tick the
## crowd, then advance the events on top of it. `total` decides whether
## bots.tick() is timed along with events.advance() or left out — see the
## note on --total at the top of the file.
func _profile(bots: BotManager, events: EventManager, step: float, n: int,
		event_id: String, params: Dictionary, ticks: int, total: bool) -> void:
	if not events.trigger(event_id, params):
		push_error("profile_events: '%s' refused to fire at %d bots." % [event_id, n])
		return

	var samples := PackedFloat32Array()
	var start_alive := bots.alive_count
	for t in ticks:
		if total:
			var t0 := Time.get_ticks_usec()
			bots.tick(step, t)
			events.advance(step)
			samples.append(float(Time.get_ticks_usec() - t0))
		else:
			bots.tick(step, t)
			var t0 := Time.get_ticks_usec()
			events.advance(step)
			samples.append(float(Time.get_ticks_usec() - t0))

	print("%-6s %6d bots%s: %6.3f ms median, %7.3f ms worst over %d ticks, %d dead, %.1f%% of budget"
		% [event_id, n, " (total)" if total else "", _median(samples), _worst(samples), ticks,
			start_alive - bots.alive_count, _median(samples) / 50.0 * 100.0])


func _median(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sorted := samples.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var middle := sorted.size() / 2
	return sorted[middle] / 1000.0


func _worst(samples: PackedFloat32Array) -> float:
	var top := 0.0
	for v in samples:
		top = maxf(top, v)
	return top / 1000.0
