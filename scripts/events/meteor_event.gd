class_name MeteorEvent
extends WorldEvent
## A rock falls out of the sky and everything close to where it lands stops
## existing.
##
## The fall is not decoration. Triggering the event only launches the meteor;
## nobody dies until it arrives, roughly 1.7 simulation seconds later. That is
## what gives the shot something to watch, and later it is what will give the
## crowd time to run.
##
## Kills through BotManager.damage() and kill() like anything else would, and
## finds who is close through the spatial grid rather than by asking ten
## thousand bots how far away they are.

## Everything inside this dies outright; out to the blast radius the damage
## falls off linearly, so the rim of the crater is a ring of survivors rather
## than a hard line. Expressed as a share of the blast radius, so a bigger
## meteor scales both.
const KILL_SHARE := 0.45

## Blast radius as a share of the map, so the meteor stays the same size
## relative to the island whatever MAP_SIZE becomes. A quarter of the map is a
## deliberate choice, not a physical one: this is the set piece of the video, so
## it is scaled to be seen from anywhere and to change the run it lands in.
## Pass "radius" to trigger() for a smaller one.
const BLAST_SHARE_OF_MAP := 0.25

const FLASH_COLOR := Color(1.0, 0.52, 0.18)


func id() -> StringName:
	return &"meteor"


## params: "x" and "z" for the impact point, "radius" for the blast. Anything
## missing is chosen at random on land, so trigger("meteor") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world

	var blast := float(params.get("radius", GameConfig.MAP_SIZE * BLAST_SHARE_OF_MAP))
	if blast <= 0.0:
		push_error("MeteorEvent: radius must be positive, got %f." % blast)
		return ""

	var point: Vector2
	if params.has("x") and params.has("z"):
		point = Vector2(float(params["x"]), float(params["z"]))
	else:
		point = world.random_land_point(events.rng())

	var target := Vector3(point.x, world.get_height(point.x, point.y), point.y)
	var meteor := MeteorProjectile.launch(target, blast, events.rng(),
		func() -> void: _land(events, point, blast))
	if meteor == null:
		return ""
	events.adopt(meteor)

	return "Meteor incoming (%d, %d)" % [roundi(point.x), roundi(point.y)]


## Runs the moment the rock touches down, against wherever the crowd has walked
## to by then. The grid was rebuilt by the tick that just ran, so it is exact.
func _land(events: EventManager, point: Vector2, blast: float) -> void:
	var bots := events.bots
	var world := events.world
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
	var at := Vector3(point.x, ground, point.y)
	# Three separate things, because they behave differently: the flash is over
	# in a second, the ring runs along the ground, and the column stands there
	# for ten seconds afterwards being the thing the camera flies around.
	events.adopt_visual(BlastEffect.create(at, blast, FLASH_COLOR))
	events.adopt_visual(ShockwaveEffect.create(at, blast, FLASH_COLOR, world.get_height))
	events.adopt_visual(MushroomCloud.create(at, blast, events.rng()))

	events.report(&"meteor", "Meteor (%d, %d) r%d: %d killed, %d hurt" % [
		roundi(point.x), roundi(point.y), roundi(blast), killed, hurt])
