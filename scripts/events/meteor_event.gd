class_name MeteorEvent
extends WorldEvent
## A rock lands on the island and everything close to it stops existing.
##
## Kills through BotManager.damage() and kill() like anything else would, and
## finds who is close through the spatial grid rather than by asking ten
## thousand bots how far away they are.

## Everything inside this dies outright; out to the blast radius the damage
## falls off linearly, so the rim of the crater is a ring of survivors rather
## than a hard line. Expressed as a share of the blast radius, so a bigger
## meteor scales both.
const KILL_SHARE := 0.45
const DEFAULT_BLAST_RADIUS := 55.0

const FLASH_COLOR := Color(1.0, 0.52, 0.18)


func id() -> StringName:
	return &"meteor"


## params: "x" and "z" for the impact point, "radius" for the blast. Anything
## missing is chosen at random on land, so trigger("meteor") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var bots := events.bots
	var world := events.world

	var blast := float(params.get("radius", DEFAULT_BLAST_RADIUS))
	if blast <= 0.0:
		push_error("MeteorEvent: radius must be positive, got %f." % blast)
		return ""

	var point: Vector2
	if params.has("x") and params.has("z"):
		point = Vector2(float(params["x"]), float(params["z"]))
	else:
		point = world.random_land_point(events.rng())

	var kill_radius := blast * KILL_SHARE
	var falloff := blast - kill_radius
	var max_health := GameConfig.BOT_MAX_HEALTH

	var killed := 0
	var hurt := 0
	for i in bots.bots_within(point.x, point.y, blast):
		var dx := bots.pos_x[i] - point.x
		var dz := bots.pos_z[i] - point.y
		var distance := sqrt(dx * dx + dz * dz)
		if distance <= kill_radius:
			if bots.kill(i):
				killed += 1
			continue
		var share := 1.0 - (distance - kill_radius) / falloff
		if share <= 0.0:
			continue
		if bots.damage(i, max_health * share):
			killed += 1
		else:
			hurt += 1

	var ground := world.get_height(point.x, point.y)
	BlastEffect.spawn(events, Vector3(point.x, ground, point.y), blast, FLASH_COLOR)

	return "Meteor (%d, %d) r%d: %d killed, %d hurt" % [
		roundi(point.x), roundi(point.y), roundi(blast), killed, hurt]
