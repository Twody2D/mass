class_name MeteorEvent
extends WorldEvent
## A rock falls out of the sky and everything close to where it lands stops
## existing.
##
## The fall is not decoration. Triggering the event only launches the meteor;
## nobody dies until it arrives, MeteorProjectile.FALL_SECONDS later. That is
## what gives the shot something to watch, and it is the warning the crowd will
## eventually learn to act on.
##
## Landing does four things, in rings outward from the point: kills, wounds,
## throws whoever survived, and frightens everyone further out. The last two are
## what turn a hole appearing in a field into an event — a crater full of dead
## knights is a statistic, and a crater with the crowd sprinting away from it is
## a shot.
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

## Survivors inside the blast are thrown outward and up, in metres per second at
## the inner edge of the ring, falling to nothing at the rim. Chosen to look
## like toys being flicked off a table rather than like people being pushed:
## at BotManager.GRAVITY this is roughly a second and a half in the air.
const KNOCKBACK_SPEED := 34.0
const KNOCKBACK_LIFT := 16.0
## Below this share of the blast, nobody is thrown. A knight tossed 20 cm is a
## state transition nothing can see, and it would cost a tick of ballistics to
## put it back exactly where it started.
const KNOCKBACK_MIN_SHARE := 0.15

## Everybody out to this many blast radii runs, and how far they run, as a share
## of the blast. The crowd fleeing is most of what makes the impact read as an
## event rather than as a hole appearing in a field.
##
## The flee distance is short on purpose. At 0.7 of the blast every survivor ran
## a hundred and eighty metres straight outwards, most of them reached the coast
## and the shore guard stopped them all in the same place: a crowd crushed
## against the beach, and separation costs go up with the square of how tightly
## packed the crowd is. Measured at ten thousand, the tick after an impact went
## from 45 ms back to 15 by letting them run a shorter way.
const PANIC_SHARE := 1.8
const FLEE_DISTANCE_SHARE := 0.3

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
	var meteor := MeteorProjectile.launch(target, blast, events.rng(), world.get_height,
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
			# Whoever lived through it gets thrown. Doing this after the damage
			# means the dead are not launched, which would cost work on bodies
			# nothing draws.
			if share > KNOCKBACK_MIN_SHARE:
				bots.fling(i, point.x, point.y,
					KNOCKBACK_SPEED * share, KNOCKBACK_LIFT * share)

	# A second, wider sweep for everyone the blast missed. Scaring costs no
	# terrain lookups on purpose (see BotManager.scare), so this stays cheap even
	# when the ring covers most of the island.
	var flee := blast * FLEE_DISTANCE_SHARE
	var scared := 0
	for i in bots.bots_within(point.x, point.y, blast * PANIC_SHARE):
		if bots.scare(i, point.x, point.y, flee):
			scared += 1

	var ground := world.get_height(point.x, point.y)
	var at := Vector3(point.x, ground, point.y)
	# Felt before it is seen: the camera decides how hard from its own distance.
	events.shake(at, blast, 1.0)
	# Five separate things, because they behave differently: the flash is over
	# in a second, the burst of dirt is gone in two, the ring runs along the
	# ground, the column stands there for ten seconds afterwards being the
	# thing the camera flies around, and the crater outlives all four of them,
	# never freeing itself once the others are long gone.
	events.adopt_visual(BlastEffect.create(at, blast, FLASH_COLOR))
	events.adopt_visual(GroundEjecta.create(at, blast, events.rng(), world.get_height))
	events.adopt_visual(ShockwaveEffect.create(at, blast, FLASH_COLOR, world.get_height,
		world.water_level))
	events.adopt_visual(MushroomCloud.create(at, blast, events.rng()))
	events.adopt_visual(Crater.create(at, blast, events.rng(), world.get_height, world.water_level))

	events.report(&"meteor", "Meteor (%d, %d) r%d: %d killed, %d hurt, %d fleeing" % [
		roundi(point.x), roundi(point.y), roundi(blast), killed, hurt, scared])
