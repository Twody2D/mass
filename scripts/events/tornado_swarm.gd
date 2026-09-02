class_name TornadoSwarm
extends WorldEvent
## Tears open several independent funnels at once rather than one — the
## owner's own complaint about the old TornadoEvent: "не одно торнадо, а это
## было прям мировое испытание из множества воронок, которые движутся сами по
## себе". Each funnel is still exactly the Tornado this project already had —
## its own retarget timer, its own panic/pickup sweep, its own fade-out — this
## file just calls Tornado.start() more than once and lets EventManager run
## them side by side, the same "adopt() already supports several live things
## at once" shape CreeperSwarm proved out first.
##
## What used to refuse a second tornado while one was loose is gone: several
## funnels loose together, each retargeting on its own short timer with a
## shared but independently-consumed rng, is now the whole point — a crowd
## member near two funnels' overlapping PANIC_RADIUS gets scared away from
## whichever swept them most recently and can flee straight from one funnel
## toward another, the same "no path-planning, just react to the nearest
## threat" approximation the rest of this project's flee code already leans
## on rather than anything that deserves to be called AI.

const COUNT := 4
## Each funnel gets its own random size in this range — see Tornado's own
## `_size` doc for what that scales. A uniform swarm of identical clones would
## read as one funnel copy-pasted; a family of differently sized ones reads
## as weather.
const SIZE_MIN := 0.7
const SIZE_MAX := 1.35


func id() -> StringName:
	return &"tornado"


## params: "count" for how many funnels touch down, "x"/"z" to place the
## first one exactly (the rest still pick their own random point) — enough
## for a test to plant a guaranteed victim without pinning every funnel to
## the same spot, which would defeat the point of a swarm.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var count := int(params.get("count", COUNT))
	if count <= 0:
		push_error("TornadoSwarm: count must be positive, got %d." % count)
		return ""

	var spawned := 0
	for i in count:
		var at: Vector2
		if i == 0 and params.has("x") and params.has("z"):
			at = Vector2(float(params["x"]), float(params["z"]))
		else:
			at = world.random_land_point(rng)
		var size_mult := rng.randf_range(SIZE_MIN, SIZE_MAX)

		var tornado := Tornado.start(world, events.bots, at, rng,
			func(line: String) -> void: events.report(&"tornado", line), size_mult)
		if tornado == null:
			continue
		events.adopt(tornado)
		spawned += 1

	if spawned == 0:
		return ""
	return "%d tornadoes tear across the island" % spawned
