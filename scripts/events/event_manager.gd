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
	_register(TeamWarEvent.new())
	# SafeZoneEvent and SupplyDropEvent are pulled from the roster, not
	# deleted: mechanically both read as "boundary tightens, run inward,"
	# indistinguishable from FloodEvent on screen, and neither earned its
	# keep as a spectacle. Owner's call, 2026-08-30 — see TODO.md. Re-register
	# here to bring either back once it has a real redesign.


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
	for child in get_children():
		child.queue_free()


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
