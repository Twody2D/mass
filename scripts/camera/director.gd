class_name Director
extends CameraMode
## The automatic cinematographer: picks a shot and a target, holds it for a
## while, and cuts — never blends — to the next one. "Режет" is the word the
## plan itself uses, and a cut is exactly what film editing means by it: a
## director does not ease between angles the way a human hand on Tab does.
##
## Not a shot of its own. Every frame Director asks whichever of Orbit,
## Approach, Follow, Ground or Top it is currently pointed at for a
## transform, the same question CameraRig asks whichever mode is active — it
## never computes one itself. Delegates are looked up on the rig by id and
## never owned or duplicated, so a shot Director leaves mid-orbit keeps
## whatever state it had if the player later switches to that same mode by
## hand. That is what "built on top of all the previous, so it is last"
## means in practice, and it is also the reason this finally gives
## Orbit/Approach/Follow/Ground/Top the in-game target they never had —
## exactly the gap TODO's "Открытые вопросы" left for this mode to close.
##
## Reacts to EventManager.shook — the one existing signal that already means
## "something just happened here, this hard" — and otherwise keeps the crowd
## itself watchable: a fresh living bot, a fresh shot, every so often.
## Deliberately never calls EventManager.trigger(): deciding when a meteor
## falls stays the owner's call, not something this mode hands itself.
##
## Also reacts to EventManager.fired: when the event that just launched is
## the meteor, it cuts to Follow with the falling rock itself as the target
## (35) — the first live, moving, non-bot subject a mode here has ever had.
## CameraTarget.at_callable() is what makes that possible: a Callable handed
## to it rather than a MeteorProjectile reference, so this file, same as
## CameraTarget itself, never has to know that class exists — only that
## EventManager.in_flight() holds something with a position while a meteor
## is on its way down. Impact still hands off cleanly: shook fires moments
## later and cuts away to the blast the same way it always has.
##
## Free and FPV Drone are left out of the rotation on purpose. Both are
## piloted with no notion of a target; there is nothing for an automatic
## director to decide with either beyond faking mouse input, which would not
## be a camera decision, only a puppet.

## How long a shot holds before the idle clock cuts to the next one. Picked
## fresh within this range on every cut, not a fixed interval, so the rhythm
## does not read as a metronome.
const MIN_HOLD_SECONDS := 6.0
const MAX_HOLD_SECONDS := 14.0

## A shake this soon after the last cut is folded into the shot already
## running rather than treated as a second reason to cut — a meteor's own
## impact shakes more than once in quick succession, and that is one moment,
## not several.
const MIN_EVENT_REACT_SECONDS := 1.5

## Shots handed a living bot to watch. Top is left out on purpose — its
## whole point is reading the crowd's shape from far above, and one knight
## from that height is exactly the "dot among dots" every other mode here
## already exists to avoid.
const IDLE_SHOTS: Array[StringName] = [&"orbit", &"approach", &"follow", &"ground"]

## Shots handed an event's location instead. Both read a blast's shape from
## a distance; Follow and Ground plant relative to a bot's facing, which a
## bare point does not have.
const EVENT_SHOTS: Array[StringName] = [&"top", &"orbit"]

## Bounded search for a living index rather than building a live list of
## survivors every cut — the crowd only gets emptier between attempts within
## one call, so a handful of tries is enough. The same reasoning
## BotManager.kill_random() already uses for a harder version of this.
const ALIVE_SEARCH_ATTEMPTS := 20

var _bots: BotManager
var _events: EventManager
var _delegate: CameraMode
var _last_shot_id := &""
var _hold_elapsed := 0.0
var _hold_duration := 0.0
var _pending_event: Variant = null
## Set by _on_fired() the moment a meteor launches; consumed by the very
## next process(). Not a StringName/Vector3 pair like _pending_event —
## Follow needs the live subject itself, not a snapshot of where it was.
var _pending_subject: Node3D = null
var _rng := RandomNumberGenerator.new()


func id() -> StringName:
	return &"director"


## Wired once by Main, the same way EventManager and BotManager are handed to
## each other rather than looking themselves up. Safe to call again after a
## restart — the signal only ever needs the one connection.
func wire(bots: BotManager, events: EventManager) -> void:
	_bots = bots
	_events = events
	if events != null and not events.shook.is_connected(_on_shook):
		events.shook.connect(_on_shook)
	if events != null and not events.fired.is_connected(_on_fired):
		events.fired.connect(_on_fired)


## Kept apart from the bots' and events' own streams, the same reasoning
## both already use for each other.
func reseed(map_seed: int) -> void:
	_rng.seed = map_seed ^ 0x6a09e667


func enter(_rig: CameraRig, _from: Transform3D) -> void:
	# Never resumes whatever shot was running before Director was last
	# active, and never reacts to something that shook or launched while
	# nobody was watching — all three would be cutting to a moment that,
	# from here, has already gone stale.
	_delegate = null
	_pending_event = null
	_pending_subject = null


func process(delta: float, rig: CameraRig) -> Transform3D:
	_hold_elapsed += delta
	if _pending_subject != null:
		var subject := _pending_subject
		_pending_subject = null
		if is_instance_valid(subject):
			_cut(rig, &"follow", CameraTarget.at_callable(
				func() -> Variant: return subject.position if is_instance_valid(subject) else null))
	elif _pending_event != null and _hold_elapsed >= MIN_EVENT_REACT_SECONDS:
		var at: Vector3 = _pending_event
		_pending_event = null
		_cut(rig, _pick(EVENT_SHOTS), CameraTarget.at_event(at))
	elif _delegate == null or _hold_elapsed >= _hold_duration:
		_cut(rig, _pick(IDLE_SHOTS), _pick_bot_target())
	return _delegate.process(delta, rig)


func unhandled_input(event: InputEvent, rig: CameraRig) -> void:
	if _delegate != null:
		_delegate.unhandled_input(event, rig)


## Mirrors whatever the current shot wants — Orbit still takes the mouse for
## its own zoom and angle mid-shot, the others do not — rather than claiming
## an answer of its own.
func wants_mouse_capture() -> bool:
	return _delegate != null and _delegate.wants_mouse_capture()


func _cut(rig: CameraRig, shot_id: StringName, target: CameraTarget) -> void:
	var next := rig.mode(shot_id)
	if next == null:
		push_error("Director: no mode registered as '%s'." % shot_id)
		return
	rig.set_target(target)
	next.enter(rig, rig.transform)
	_delegate = next
	_last_shot_id = shot_id
	_hold_elapsed = 0.0
	_hold_duration = _rng.randf_range(MIN_HOLD_SECONDS, MAX_HOLD_SECONDS)


## Avoids repeating the last shot when the pool has somewhere else to go —
## two cuts to the same mode back to back reads as though the cut did not
## happen at all.
func _pick(pool: Array[StringName]) -> StringName:
	if pool.size() <= 1:
		return pool[0]
	var choice: StringName = pool[_rng.randi() % pool.size()]
	var attempts := 0
	while choice == _last_shot_id and attempts < pool.size():
		choice = pool[_rng.randi() % pool.size()]
		attempts += 1
	return choice


func _pick_bot_target() -> CameraTarget:
	if _bots == null or _bots.count <= 0:
		return CameraTarget.none()
	for _attempt in ALIVE_SEARCH_ATTEMPTS:
		var index := _rng.randi() % _bots.count
		if _bots.alive[index] == 1:
			return CameraTarget.on_bot(_bots, index)
	return CameraTarget.none()


func _on_shook(at: Vector3, _radius: float, _strength: float) -> void:
	_pending_event = at


## EventManager.report() fires this same signal again at impact, with the
## meteor still technically in_flight() for the rest of this same call —
## queue_free() only marks it, the loop that actually drops it from
## _in_flight has not run yet. Reacting to that second firing would cut
## straight back to a rock already gone. "incoming" is what tells the two
## apart: it is only ever in the description fire() itself returns at
## launch, the same string verify_events.gd already keys off of.
##
## Only the meteor currently has anything in flight worth following — a
## flood, a shrinking zone, a battle and a supply scramble all adopt() too,
## but none of them is a single point a camera could chase. Checked by the
## event's own id rather than by what EventManager.in_flight() holds, so
## this depends on the string "meteor" the same way the debug keybinding
## already does, never on a class only meteor_event.gd needs to know about.
func _on_fired(id: StringName, description: String) -> void:
	if id != &"meteor" or not description.contains("incoming"):
		return
	for effect in _events.in_flight():
		var subject := effect as Node3D
		if subject != null:
			_pending_subject = subject
			return
