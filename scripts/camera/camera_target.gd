class_name CameraTarget
extends RefCounted
## What a mode should be looking at, once one exists that looks at anything.
## Free ignores this entirely — it has no target, the operator is the target.
## Orbit, Follow and Approach (items 22, 24, 25) are what this is for.
##
## A tagged union rather than one optional field per kind on CameraRig: the
## kinds are mutually exclusive by construction, so "a bot target with a
## stale point left over from before" cannot happen.

enum Kind { NONE, POINT, BOT, EVENT, CALLABLE }

var kind := Kind.NONE

var _point := Vector3.ZERO
var _bots: BotManager
var _bot_index := -1
var _resolver := Callable()


static func none() -> CameraTarget:
	return CameraTarget.new()


static func at_point(point: Vector3) -> CameraTarget:
	var target := CameraTarget.new()
	target.kind = Kind.POINT
	target._point = point
	return target


## Tracks a living bot's position every time it is resolved, not a snapshot
## taken now — a Follow-style mode needs the bot's *current* spot, not where
## it stood when the target was set.
static func on_bot(bots: BotManager, index: int) -> CameraTarget:
	if bots == null or not bots.is_valid_index(index):
		push_error("CameraTarget: on_bot() got index %d, outside the crowd." % index)
		return CameraTarget.none()
	var target := CameraTarget.new()
	target.kind = Kind.BOT
	target._bots = bots
	target._bot_index = index
	return target


## A snapshot of where an event was, taken once by whoever set the target
## rather than tracked live: unlike a bot, most events here have no position
## that keeps meaning anything after the moment passes — a flood has none at
## all, and a closed zone's wall is gone. Kept as its own kind rather than
## folded into POINT so a future Director can tell "aimed at a place" apart
## from "aimed at what last happened" when it decides where to look next.
static func at_event(point: Vector3) -> CameraTarget:
	var target := CameraTarget.new()
	target.kind = Kind.EVENT
	target._point = point
	return target


## Any live, moving, non-bot position a mode might need to track — a
## meteor mid-flight (35) being the first, but not the only future one.
## `resolver` is called with no arguments every time this resolves and must
## answer a Vector3 or null itself; the same "hand over a Callable rather
## than a reference" shape world.get_height already travels through
## ShockwaveEffect and GroundEjecta, here used so CameraTarget never has to
## know what a MeteorProjectile is, only that something can be asked where
## it currently is.
static func at_callable(resolver: Callable) -> CameraTarget:
	if not resolver.is_valid():
		push_error("CameraTarget: at_callable() needs a valid Callable.")
		return CameraTarget.none()
	var target := CameraTarget.new()
	target.kind = Kind.CALLABLE
	target._resolver = resolver
	return target


## Resolves to a position right now, or null if there is nothing to look at —
## no target set, or a bot target whose index has gone out of range (a crowd
## rebuild, most likely). Godot has no Optional; null is the honest way to say
## "nothing" without a sentinel coordinate a real point could collide with.
## A bot's position is returned whether or not it is still alive: the corpse
## is still lying there, and it is a mode's call whether that still matters.
func resolve() -> Variant:
	match kind:
		Kind.POINT, Kind.EVENT:
			return _point
		Kind.BOT:
			if not _bots.is_valid_index(_bot_index):
				return null
			return Vector3(_bots.pos_x[_bot_index], _bots.pos_y[_bot_index], _bots.pos_z[_bot_index])
		Kind.CALLABLE:
			return _resolver.call() if _resolver.is_valid() else null
		_:
			return null


## The direction a bot target is facing, or null for anything else — a
## point or an event has no facing to speak of, and only Follow (item 25)
## needs this at all. Read live, same as resolve(): a bot turns as it walks.
func resolve_facing() -> Variant:
	if kind != Kind.BOT or not _bots.is_valid_index(_bot_index):
		return null
	return Vector3(_bots.face_x[_bot_index], 0.0, _bots.face_z[_bot_index])


func is_set() -> bool:
	return kind != Kind.NONE
