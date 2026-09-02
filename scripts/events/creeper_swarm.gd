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
##
## This is also this project's first sound: a rising hiss while a creeper
## fuses, a boom when it goes off — both ProceduralAudio.rising_whistle_
## hiss()/impact_boom() (see that file's own doc on why synthesized, not
## recorded), wrapped in SoundEffect and adopted the same way BlastEffect
## already is. HISS_SECONDS matches Creeper.FUSE_SECONDS exactly: the sound
## has to run out right as the blast replaces it, not fade out early or cut
## off late.

const COUNT := 6
const HISS_SECONDS := Creeper.FUSE_SECONDS
const HISS_START_HZ := 500.0
const HISS_END_HZ := 1400.0
const BOOM_SECONDS := 0.6


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

	var hiss_stream := ProceduralAudio.rising_whistle_hiss(HISS_SECONDS, HISS_START_HZ, HISS_END_HZ)
	var boom_stream := ProceduralAudio.impact_boom(BOOM_SECONDS)

	var spawned := 0
	for _i in count:
		var at := world.random_land_point(rng)
		var creeper := Creeper.start(world, events.bots, at, rng,
			func(line: String) -> void: events.report(&"creepers", line),
			func(at3: Vector3, radius: float) -> void:
				events.shake(at3, radius, 0.3)
				events.adopt_visual(BlastEffect.create(at3, radius, Creeper.BLAST_COLOR))
				events.adopt_visual(GroundEjecta.create(at3, radius, events.rng(), world.get_height))
				events.adopt_visual(SoundEffect.create(at3, boom_stream, BOOM_SECONDS)),
			func(at2: Vector3) -> void:
				events.adopt_visual(SoundEffect.create(at2, hiss_stream, HISS_SECONDS)))
		if creeper == null:
			continue
		events.adopt(creeper)
		spawned += 1

	if spawned == 0:
		return ""
	return "%d creepers slip into the crowd" % spawned
