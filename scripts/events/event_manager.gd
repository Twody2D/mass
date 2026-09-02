class_name EventManager
extends Node3D
## The only way anything happens to the world from outside.
##
## Events are not wired into BotManager, and BotManager does not know they
## exist. Everything goes through trigger("meteor"), whether it comes from a
## keypress or from the pause menu. That is what keeps the crowd code from
## growing a branch per event.
##
## Director (28) reacts to whatever this fires — shook, in particular — to
## decide what the camera does next, but never calls trigger() itself:
## deciding when a meteor falls stays the owner's call, not something this
## hands to a camera system.
##
## A Node3D because one shot visual effects are parented to it, which also means
## a restart clears them by freeing children rather than by tracking each one.

## Emitted after an event has run, with the line it wants shown.
signal fired(id: StringName, description: String)

## Something went off hard enough to be felt. Carries where and how big rather
## than how much to shake: the camera is the only thing that knows how far away
## it is, so it is the only thing that can decide. Nothing here knows a camera
## exists — Main connects the two.
signal shook(at: Vector3, radius: float, strength: float)

## Assigned by Main, which owns the wiring.
var bots: BotManager
var world: World

## Whether VolcanoEvent is worth registering at all. False on the ordinary
## island (scenes/main.tscn), which no longer bakes a mountain into its
## heightmap (World.bake_volcano) — triggering an eruption there would only
## grow lava puddles on whatever flat ground happened to be at the map
## centre, exactly the "puddles on a random hill" look this project already
## fixed once. True on the dedicated volcano map (scenes/volcano.tscn),
## which does have the mountain to erupt from. Checked at _ready(), which
## runs before Main wires world to this node — a scene property, not
## something world state can gate itself.
@export var volcano_enabled := true

## Whether TeamWarEvent is worth registering. False everywhere except the
## dedicated war island (scenes/war_island.tscn): `BotManager.war_side` is
## only meaningful where every bot was actually assigned a side at spawn,
## and the ordinary crowd has no "two sides" to fight over since class
## replaced team. Same reasoning and same checked-at-_ready() timing as
## volcano_enabled above.
@export var war_enabled := false

## What happened last, for the overlay to read.
var last_id := &""
var last_description := ""

## Registered events, by id.
var _events := {}

## Things that have been set in motion and are not finished. Both lists hold
## nodes with advance(delta) -> bool; they differ only in which clock drives
## them.
##
## _in_flight runs on the simulation tick, because where a falling meteor is
## decides who dies, and that has to be reproducible from the seed rather than
## from the frame rate. _visuals run on frame time, because a flash stepping at
## 20 Hz next to a crowd moving at 55 FPS is exactly the stutter this project
## already fixed once.
var _in_flight: Array[Node] = []
var _visuals: Array[Node] = []

## Set by Main every frame: zero while paused, the simulation speed otherwise.
## It is what lets the camera be flown around a frozen explosion.
var time_scale := 1.0

## Seeded from the map seed, so an event fired on the same tick of the same seed
## lands in the same place. Kept apart from the bots' streams: triggering an
## event must not shift what everyone who was not hit would have done.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_register(MeteorEvent.new())
	_register(FloodEvent.new())
	if volcano_enabled:
		_register(VolcanoEvent.new())
	_register(MonsterEvent.new())
	_register(KrakenEvent.new())
	_register(EarthquakeEvent.new())
	_register(TornadoSwarm.new())
	_register(GiantBirdEvent.new())
	_register(CreeperSwarm.new())
	if war_enabled:
		_register(TeamWarEvent.new())
	_register(SafeZoneEvent.new())
	_register(SupplyDropEvent.new())
	_register(CrabylonEvent.new())
	_register(TitanobooEvent.new())
	_register(GiraffaxonEvent.new())
	_register(RaptorousEvent.new())
	_register(ScorpyEvent.new())
	_register(WhormbusEvent.new())
	_register(HorselyEvent.new())
	_register(RhombolionEvent.new())
	_register(RombophantEvent.new())
	_register(RandomBossEvent.new())
	# War, Zone and Drop are the three events the owner pulled from the
	# roster on 2026-08-30 for lacking a real spectacle — see TODO.md,
	# "Отключено и на пересмотре". All three have since rejoined it with a
	# real redesign: BotManager.war_side/war_enabled above, SafeZone's
	# jumping boundary, and SupplyScramble's winner/TrophyWeapon.


## Decoration only. Kept off the simulation clock on purpose; see _visuals.
func _process(delta: float) -> void:
	if not _visuals.is_empty():
		_step(_visuals, delta * time_scale)


## Every registered event id, sorted. Useful for a menu and for verification.
func known() -> Array:
	var ids := _events.keys()
	ids.sort()
	return ids


func has_event(id: StringName) -> bool:
	return _events.has(id)


## Fires a registered event directly and hands back its own raw description
## ("" if it refused), without wrapping it in a second report or a second
## `fired` signal the way trigger() does. For RandomBossEvent, which picks
## one of several boss ids and wants that pick to read as if it had been
## triggered directly — one real event, one description, one signal — not
## as "boss" nested around whichever giant actually showed up.
func fire_event(target_id: StringName, params: Dictionary) -> String:
	if not _events.has(target_id):
		return ""
	return (_events[target_id] as WorldEvent).fire(self, params)


## Makes an event happen. Returns false and says why rather than failing
## quietly: a mistyped event name that does nothing is the kind of bug that
## survives a whole recording session.
func trigger(id: StringName, params: Dictionary = {}) -> bool:
	if bots == null or world == null:
		push_error("EventManager: not wired to a world and a crowd, cannot trigger '%s'." % id)
		return false
	if not _events.has(id):
		push_error("EventManager: no event named '%s'. Known events: %s." % [id, known()])
		return false

	var event: WorldEvent = _events[id]
	var description: String = event.fire(self, params)
	if description == "":
		# An empty description is how an event says it refused its parameters.
		# It has already said why; what matters here is not recording a thing
		# that did not happen as the last thing that happened.
		return false

	last_id = id
	last_description = description
	fired.emit(id, description)
	return true


## Takes ownership of something that is still happening, and advances it on
## every simulation tick until it says it is finished.
func adopt(effect: Node) -> void:
	if effect == null:
		push_error("EventManager: adopt() was given nothing to adopt.")
		return
	if not effect.has_method("advance"):
		push_error("EventManager: %s has no advance(delta) and cannot be adopted."
			% effect.get_class())
		return
	add_child(effect)
	_in_flight.append(effect)


## Takes ownership of something that only has to look right: a flash, a ring, a
## column of smoke. Nothing here may touch a bot.
func adopt_visual(effect: Node) -> void:
	if effect == null:
		# create() already said what was wrong with its arguments.
		return
	if not effect.has_method("advance"):
		push_error("EventManager: %s has no advance(delta) and cannot be adopted."
			% effect.get_class())
		return
	add_child(effect)
	_visuals.append(effect)


## Whatever is still in flight right now — a falling meteor, most likely.
## Read-only and generic on purpose: this exists for Director (35) to find
## something worth pointing a camera at without EventManager ever having to
## know which event that is, the same separation it already keeps between
## itself and the camera for shook.
func in_flight() -> Array[Node]:
	return _in_flight.duplicate()


## One simulation step for everything in flight. Driven by Main's tick loop
## rather than by _process, because where a falling meteor is decides when
## people die: pausing has to freeze it in the air, and the speed ladder has to
## carry it along with the rest of the simulation.
func advance(delta: float) -> void:
	_step(_in_flight, delta)
	_separate_giants()


## Places everything in flight where it should be for this frame, between the
## last simulation tick and the next one. Same alpha the crowd is drawn with,
## and for the same reason: without it a meteor crosses the sky in twenty steps
## a second while everything around it moves smoothly.
func interpolate(alpha: float) -> void:
	for effect in _in_flight:
		if is_instance_valid(effect) and effect.has_method("render"):
			effect.render(alpha)


func _step(list: Array[Node], delta: float) -> void:
	var i := list.size() - 1
	while i >= 0:
		var effect := list[i]
		if not is_instance_valid(effect) or not effect.advance(delta):
			list.remove_at(i)
		i -= 1


## Keeps two giants that wandered close from visibly walking through each
## other — a real bug seen on a real run (RandomBossEvent only refuses a
## second copy of the SAME kind, so a jackal, a crab and a giraffe can all
## be loose at once with nothing between them). Only ever a handful of
## giants can be in flight together (the whole roster is a dozen, and
## nothing spawns two of a kind), so an O(M^2) pairwise check here is
## nowhere near the O(N^2) rule this project holds bot code to — M is the
## giant count, not the crowd. Soft, not a hard wall: every tick nudges each
## overlapping pair half the overlap apart, the same "keep correcting every
## tick rather than solve it once" shape BotManager's own flee()/scare()
## already use, rather than a one-shot separation that would only need to be
## fought again as soon as both keep walking toward the same spot.
func _separate_giants() -> void:
	var giants: Array[Node3D] = []
	for child in _in_flight:
		if _giant_radius(child) > 0.0:
			giants.append(child as Node3D)

	for i in giants.size():
		for j in range(i + 1, giants.size()):
			var a := giants[i]
			var b := giants[j]
			var min_distance: float = _giant_radius(a) + _giant_radius(b)
			var offset := Vector2(a.position.x, a.position.z) - Vector2(b.position.x, b.position.z)
			var distance := offset.length()
			if distance >= min_distance or distance < 0.0001:
				continue
			var push_dir := offset / distance
			var correction := push_dir * (min_distance - distance) * 0.5
			a.push(correction)
			b.push(-correction)


## Half the ground each giant type needs kept clear of another, off its own
## scale constant — an approximation, not a precise mesh radius, the same
## "good enough, not exact" reasoning Crater/GroundEjecta's own geometry
## already uses. 0.0 for anything in _in_flight that is not a giant at all
## (a falling meteor, an earthquake, a tornado...), so _separate_giants()
## can build its own list by checking this is positive, without a second
## type list to keep in sync with the roster.
func _giant_radius(node: Node) -> float:
	if node is Monster:
		return Monster.HEIGHT * 0.5
	if node is Kraken:
		return Kraken.HEIGHT * 0.5
	if node is GiantBird:
		return GiantBird.HEIGHT * 0.5
	if node is Crabylon:
		return Crabylon.WIDTH * 0.5
	if node is Titanoboo:
		return Titanoboo.LENGTH * 0.5
	if node is Giraffaxon:
		return Giraffaxon.HEIGHT * 0.5
	if node is Raptorous:
		return Raptorous.LENGTH * 0.5
	if node is Scorpy:
		return Scorpy.WIDTH * 0.5
	if node is Whormbus:
		return Whormbus.LENGTH * 0.5
	if node is Horsely:
		return Horsely.LENGTH * 0.5
	if node is Rhombolion:
		return Rhombolion.LENGTH * 0.5
	if node is Rombophant:
		return Rombophant.LENGTH * 0.5
	return 0.0


## Announces an impact at `at` with a blast radius of `radius`. `strength` is
## how violent it was at the centre, 0 to 1.
func shake(at: Vector3, radius: float, strength: float) -> void:
	if radius <= 0.0:
		push_error("EventManager: shake() expects a positive radius, got %f." % radius)
		return
	shook.emit(at, radius, clampf(strength, 0.0, 1.0))


## Records the outcome of something that finished later than it was triggered.
## A meteor announces that it is coming, then says what it did when it lands; a
## flood keeps saying how high it is and how many it has taken.
func report(id: StringName, description: String) -> void:
	if description == "":
		return
	last_id = id
	last_description = description
	fired.emit(id, description)


## Clears the record and any effects still on screen, and re-seeds. Called by
## Main when the world is rebuilt.
func reset(map_seed: int) -> void:
	_rng.seed = map_seed ^ 0x27d4eb2f
	last_id = &""
	last_description = ""
	_in_flight.clear()
	_visuals.clear()
	# free(), not queue_free(): a caller re-triggering right after reset() (a
	# restart on a level whose auto_trigger_event fires again, or a test
	# doing the same) has to see a clean slate on the very next line, not
	# after a deferred deletion nobody here waits for. Safe immediately —
	# these effects are driven by advance(delta) from outside, never from
	# their own signal or notification handlers, so nothing is freeing
	# itself out from under a callback still on the stack.
	for child in get_children():
		child.free()


## The event stream. Events take their randomness from here, so two runs of the
## same seed put the meteor in the same crater.
func rng() -> RandomNumberGenerator:
	return _rng


func _register(event: WorldEvent) -> void:
	var id := event.id()
	if _events.has(id):
		push_error("EventManager: two events claim the id '%s'." % id)
		return
	_events[id] = event
