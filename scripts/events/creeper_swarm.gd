class_name CreeperSwarm
extends WorldEvent
## Spawns a handful of creepers across the island, each one on its own —
## TODO.md item 54's "определённое число криперов спавнится в мире и
## взрывается 1-в-1 как в Minecraft."
##
## Unlike Monster/Kraken/GiantBird/Tornado this does not adopt one thing: it
## adopts `count` independent Creeper instances in one call and hands each
## one back to whoever asks "is anything still going" as just another
## in-flight object. EventManager.adopt() already supports more than one
## live thing at once (the meteor's own blast leaves several adopted visuals
## running side by side) — a swarm needed no new plumbing, just calling it
## more than once.

const COUNT := 6


func id() -> StringName:
	return &"creepers"


## params: "count" for how many to spawn. Optional, so trigger("creepers")
## on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var count := int(params.get("count", COUNT))
	if count <= 0:
		push_error("CreeperSwarm: count must be positive, got %d." % count)
		return ""

	var spawned := 0
	for _i in count:
		var at := world.random_land_point(rng)
		var creeper := Creeper.start(world, events.bots, at, rng,
			func(line: String) -> void: events.report(&"creepers", line),
			func(at3: Vector3, radius: float) -> void:
				events.shake(at3, radius, 0.3)
				events.adopt_visual(BlastEffect.create(at3, radius, Creeper.BLAST_COLOR))
				events.adopt_visual(GroundEjecta.create(at3, radius, events.rng(), world.get_height)))
		if creeper == null:
			continue
		events.adopt(creeper)
		spawned += 1

	if spawned == 0:
		return ""
	return "%d creepers slip into the crowd" % spawned
