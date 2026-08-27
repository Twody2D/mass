class_name TeamWarEvent
extends WorldEvent
## Two of the five teams stop wandering and walk at each other until only one
## side is left standing.
##
## Two committed rather than a free-for-all: five armies smearing into one
## ball would look exactly like the panic every other event already causes,
## and nothing on screen would say "war" specifically. Two clumps of colour
## converging read as a battle even from directly overhead, which is the
## reason the crowd is coloured by team at all.
##
## Owns no state itself. Triggering it hands a WarBattle to the event manager,
## and the battle is what fights it out on the simulation clock.

const DAMAGE_PER_SECOND := 20.0


func id() -> StringName:
	return &"war"


## params: "team_a" and "team_b" to name the fight, "damage" for how hard.
## Missing teams default to the two with the most survivors, so trigger("war")
## on its own always finds a fight worth watching instead of two skirmishers.
func fire(events: EventManager, params: Dictionary) -> String:
	var bots := events.bots

	# Two wars would both march the same bots and fight over the same state.
	for child in events.get_children():
		if child is WarBattle and not child.is_queued_for_deletion():
			push_error("TeamWarEvent: a war is already being fought.")
			return ""

	if GameConfig.team_count() < 2:
		push_error("TeamWarEvent: needs at least two teams, there is %d."
			% GameConfig.team_count())
		return ""

	if params.has("team_a") != params.has("team_b"):
		push_error("TeamWarEvent: team_a and team_b must be given together, or not at all.")
		return ""

	var team_a: int
	var team_b: int
	if params.has("team_a"):
		team_a = int(params["team_a"])
		team_b = int(params["team_b"])
	else:
		var pair := _biggest_two(bots)
		team_a = pair[0]
		team_b = pair[1]

	if team_a == team_b:
		push_error("TeamWarEvent: needs two different teams, got %d twice." % team_a)
		return ""

	var damage := float(params.get("damage", DAMAGE_PER_SECOND))
	if damage <= 0.0:
		push_error("TeamWarEvent: damage must be positive, got %f." % damage)
		return ""

	var war := WarBattle.start(bots, team_a, team_b, damage,
		func(line: String) -> void: events.report(&"war", line))
	if war == null:
		return ""
	events.adopt(war)

	return "War: team %d (%d) v team %d (%d)" % [
		team_a, _alive_on(bots, team_a), team_b, _alive_on(bots, team_b)]


## The two teams with the most living members, largest first. Ties break on
## team index, so the same crowd always picks the same fight.
func _biggest_two(bots: BotManager) -> Array:
	var teams := GameConfig.team_count()
	var counts := []
	counts.resize(teams)
	counts.fill(0)
	for i in bots.count:
		if bots.alive[i] == 1:
			counts[bots.team[i]] += 1
	var order := range(teams)
	order.sort_custom(func(a: int, b: int) -> bool:
		if counts[a] != counts[b]:
			return counts[a] > counts[b]
		return a < b)
	return [order[0], order[1]]


func _alive_on(bots: BotManager, team_id: int) -> int:
	var n := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.team[i] == team_id:
			n += 1
	return n
