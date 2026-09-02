class_name SoundEffect
extends Node3D
## One-shot positional sound, adopted the same way BlastEffect/GroundEjecta
## are: a Node with advance(delta) -> bool, freeing itself once its own
## known clip length has elapsed. Timed by its own _elapsed against a
## duration handed in at create() time, not by polling
## AudioStreamPlayer3D.playing — the audio driver's own real-time playback
## state has nothing to do with the simulation's delta (and headless runs
## on a dummy driver with no real output at all), the same reason every
## other _visuals effect here (GroundEjecta, Crater's fade) times itself
## off _elapsed rather than off anything physical actually settling.
##
## See ProceduralAudio for where the clip itself comes from — this file
## only ever plays whatever AudioStreamWAV it is handed, it does not know
## or care that the clip was synthesized rather than recorded.

var _player: AudioStreamPlayer3D
var _elapsed := 0.0
var _duration := 0.0
var _started := false


## Builds a sound at `at` playing `stream`, ready to be handed to
## EventManager.adopt_visual(). `duration_s` should be the clip's own real
## length — every ProceduralAudio caller already knows it, having just
## built the clip from that same duration.
static func create(at: Vector3, stream: AudioStreamWAV, duration_s: float,
		volume_db: float = 0.0) -> SoundEffect:
	if stream == null:
		push_error("SoundEffect: needs a stream to play.")
		return null
	if duration_s <= 0.0:
		push_error("SoundEffect: needs a positive duration, got %f." % duration_s)
		return null

	var effect := SoundEffect.new()
	effect.position = at
	effect._duration = duration_s
	effect._player = AudioStreamPlayer3D.new()
	effect._player.stream = stream
	effect._player.volume_db = volume_db
	effect.add_child(effect._player)
	return effect


## Playback starts on the first advance() rather than in create(): by the
## time this first runs, EventManager.adopt_visual() has already
## add_child()-ed this into the live tree, which AudioStreamPlayer3D needs
## before play() actually reaches an audio bus.
func advance(delta: float) -> bool:
	if not _started:
		_started = true
		_player.play()
	_elapsed += delta
	if _elapsed >= _duration:
		queue_free()
		return false
	return true
