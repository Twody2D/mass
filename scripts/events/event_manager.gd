class_name EventManager
extends Node3D
## The only way anything happens to the world from outside.
##
## Events are not wired into BotManager, and BotManager does not know they
## exist. Everything goes through trigger("meteor"), whether it comes from a
## keypress, from the pause menu or, later, from a director deciding the video
## needs something to happen. That is what keeps the crowd code from growing a
## branch per event.
##
## A Node3D because one shot visual effects are parented to it, which also means
## a restart clears them by freeing children rather than by tracking each one.

## Emitted after an event has run, with the line it wants shown.
signal fired(id: StringName, description: String)

## Assigned by Main, which owns the wiring.
var bots: BotManager
var world: World

## What happened last, for the overlay to read.
var last_id := &""
var last_description := ""

## Registered events, by id.
var _events := {}

## Seeded from the map seed, so an event fired on the same tick of the same seed
## lands in the same place. Kept apart from the bots' streams: triggering an
## event must not shift what everyone who was not hit would have done.
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_register(MeteorEvent.new())


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


## Clears the record and any effects still on screen, and re-seeds. Called by
## Main when the world is rebuilt.
func reset(map_seed: int) -> void:
	_rng.seed = map_seed ^ 0x27d4eb2f
	last_id = &""
	last_description = ""
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
