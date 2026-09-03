class_name TeamWarEvent
extends WorldEvent
## Two armies, one on each half of the war island, march at each other and
## fight until one side is gone.
##
## Only registered on the dedicated war island (see `EventManager.
## war_enabled`) — the ordinary crowd has no "two sides" to fight over any
## more (class replaced team), and `BotManager.war_side` is only meaningful
## where every bot was actually assigned one at spawn. Firing this anywhere
## else would march a jumble of leftover war_side values that happen to be
## on disk, which is not a battle, just noise.
##
## Owns no state itself. Triggering it hands a WarBattle to the event
## manager, and the battle is what fights it out on the simulation clock.

const DAMAGE_PER_SECOND := 20.0
## war_side only ever holds these two values (BotManager.spawn() assigns by
## which half of the map a bot landed on) — unlike the old team axis there
## is no roster to pick "the two biggest" from, there are just the two
## sides that exist.
const SIDE_A := 0
const SIDE_B := 1


func id() -> StringName:
	return &"war"


## params: "damage" for how hard. Nothing else to name — see SIDE_A/SIDE_B —
## so trigger("war") on its own always fights the whole island's two halves.
func fire(events: EventManager, params: Dictionary) -> String:
	var bots := events.bots
	var world := events.world

	# Two wars would both march the same bots and fight over the same state.
	for child in events.get_children():
		if child is WarBattle and not child.is_queued_for_deletion():
			push_error("TeamWarEvent: a war is already being fought.")
			return ""

	var damage := float(params.get("damage", DAMAGE_PER_SECOND))
	if damage <= 0.0:
		push_error("TeamWarEvent: damage must be positive, got %f." % damage)
		return ""

	var war := WarBattle.start(bots, world, SIDE_A, SIDE_B, damage,
		func(line: String) -> void: events.report(&"war", line),
		func(from: Vector3, to: Vector3) -> void: events.archer_shot(from, to),
		func(at: Vector3) -> void: events.archer_kill(at))
	if war == null:
		return ""
	events.adopt(war)

	return "War: west (%d) v east (%d)" % [_alive_on(bots, SIDE_A), _alive_on(bots, SIDE_B)]


func _alive_on(bots: BotManager, side_id: int) -> int:
	var n := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.war_side[i] == side_id:
			n += 1
	return n
