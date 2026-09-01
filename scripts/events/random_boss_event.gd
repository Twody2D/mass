class_name RandomBossEvent
extends WorldEvent
## One button, one of several giants. Picks a random boss from the roster
## and fires it directly through EventManager.fire_event(), so the result
## reads exactly as if that giant's own id had been triggered — one real
## event, one description, one `fired` signal, not "boss" wrapped around
## whichever one actually showed up.
##
## Owns no state. Every boss in the roster already refuses a second copy of
## itself inside its own fire() (see Monster/Kraken/Crabylon/Titanoboo/
## Giraffaxon/GiantBird), so a busy one is skipped in favour of the next
## rather than treated as a hard failure — the button should summon
## *something* whenever anything at all is free to be summoned.

## Every single-giant boss this project has. Deliberately not Tornado,
## Earthquake or CreeperSwarm — those are not "a giant that walks up, gets
## shot and falls," the shape this roster and this button are both built
## around.
const ROSTER: Array[StringName] = [
	&"monster", &"kraken", &"chicken", &"crab", &"snake", &"giraffe",
	&"raptor", &"scorpion", &"worm",
]


func id() -> StringName:
	return &"boss"


## params are forwarded as-is to whichever boss gets picked ("health" works
## for all six; "x"/"z" would place any of them). There is no way to name
## which one from here — that is the entire point of this event.
func fire(events: EventManager, params: Dictionary) -> String:
	var candidates: Array[StringName] = []
	for boss_id in ROSTER:
		if events.has_event(boss_id):
			candidates.append(boss_id)
	if candidates.is_empty():
		push_error("RandomBossEvent: no bosses are registered on this map.")
		return ""

	# A random starting point into the roster, then a full lap looking for
	# one not already loose — deterministic (events.rng()), not Array.
	# shuffle()'s own unseeded global RNG, which this project never uses.
	var start := events.rng().randi() % candidates.size()
	for offset in candidates.size():
		var picked: StringName = candidates[(start + offset) % candidates.size()]
		var description := events.fire_event(picked, params)
		if description != "":
			return description

	push_error("RandomBossEvent: every boss in the roster is already loose.")
	return ""
