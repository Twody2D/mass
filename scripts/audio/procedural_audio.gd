class_name ProceduralAudio
extends RefCounted
## Every sound effect in this project is synthesized once into a cached
## AudioStreamWAV, never a recorded sample. CLAUDE.md's external-resources
## rule only lets a licensed asset in when it clearly wins on look, price or
## speed of development — for a two-second hiss or thump, writing raw PCM
## in a screenful of GDScript is faster than sourcing, downloading, and
## crediting a CC0 sample, and it needs no new entry in assets/CREDITS.md
## at all. The same "build once, reuse the instance" discipline BlobMesh's
## own static pool already established for geometry: every generator below
## caches by its own parameters, so the same call twice returns the same
## clip rather than resynthesizing it.
##
## Deliberately simple synthesis: white noise and a single sine/square tone,
## each shaped by a plain power-curve envelope ((1 - t)^decay_power) — no
## filters, no additive synthesis, nothing a real DSP chain would give you.
## The same "cheap and periodic, not a real simulation" restraint camera
## shake and every shader's sparks already lean on, just in the audio
## domain instead of the visual one. noise_burst()/tone() are generic
## primitives meant for future events to reuse directly; rising_whistle_
## hiss()/impact_boom() are the two composites this pilot (Creeper, see its
## own class doc) actually needed, kept general enough — general noise+tone
## shapes, not "creeper sounds" — for any future boss's own fuse or impact
## to reach for the same way.

const SAMPLE_RATE := 22050

static var _cache: Dictionary = {}


## A burst of white noise shaped by (1 - t)^decay_power — a low decay_power
## (near 0) reads as a steady hiss, a high one (3+) reads as a sharp crack.
## `noise_seed` only has to be deterministic and cache-stable; it has
## nothing to do with the map seed, this is decoration, not simulation.
static func noise_burst(duration_s: float, decay_power: float = 3.0,
		noise_seed: int = 0) -> AudioStreamWAV:
	var key := "noise:%f:%f:%d" % [duration_s, decay_power, noise_seed]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var frame_count := maxi(1, roundi(duration_s * SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	for i in frame_count:
		var t := float(i) / float(frame_count)
		var envelope := pow(1.0 - t, decay_power)
		_write_sample(data, i, rng.randf_range(-1.0, 1.0) * envelope)
	var stream := _build_stream(data)
	_cache[key] = stream
	return stream


## A single tone — sine, or a squarer "8-bit" wave when `square` is true —
## sweeping linearly from `start_hz` to `end_hz` over the clip, shaped by
## the same (1 - t)^decay_power envelope as noise_burst(). A flat pitch is
## just start_hz == end_hz.
static func tone(duration_s: float, start_hz: float, end_hz: float,
		decay_power: float = 2.0, square: bool = false) -> AudioStreamWAV:
	var key := "tone:%f:%f:%f:%f:%s" % [duration_s, start_hz, end_hz, decay_power, square]
	if _cache.has(key):
		return _cache[key]
	var frame_count := maxi(1, roundi(duration_s * SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	var phase := 0.0
	for i in frame_count:
		var t := float(i) / float(frame_count)
		var freq := lerpf(start_hz, end_hz, t)
		phase += freq / float(SAMPLE_RATE)
		var wave := sin(phase * TAU)
		if square:
			wave = 1.0 if wave >= 0.0 else -1.0
		var envelope := pow(1.0 - t, decay_power)
		_write_sample(data, i, wave * envelope)
	var stream := _build_stream(data)
	_cache[key] = stream
	return stream


## Noise for texture plus a rising square-wave whistle on top, envelope
## nearly flat until a fade near the very end — a fuse counting down to
## something, not an impact. One clip, not two AudioStreamPlayer3D layered:
## SoundEffect only ever plays one stream at a time (see its own doc on why
## that is enough).
static func rising_whistle_hiss(duration_s: float, start_hz: float, end_hz: float,
		noise_seed: int = 0) -> AudioStreamWAV:
	var key := "hiss:%f:%f:%f:%d" % [duration_s, start_hz, end_hz, noise_seed]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var frame_count := maxi(1, roundi(duration_s * SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	var phase := 0.0
	for i in frame_count:
		var t := float(i) / float(frame_count)
		var freq := lerpf(start_hz, end_hz, t)
		phase += freq / float(SAMPLE_RATE)
		var whistle := 1.0 if sin(phase * TAU) >= 0.0 else -1.0
		var noise := rng.randf_range(-1.0, 1.0)
		var envelope := pow(1.0 - t, 0.4)
		_write_sample(data, i, (noise * 0.5 + whistle * 0.5) * envelope)
	var stream := _build_stream(data)
	_cache[key] = stream
	return stream


## A sharp noise crack over a low tone thump underneath for weight — an
## explosion, a heavy footstep, an impact. Noise and thump decay at
## different rates on purpose (the crack fades faster than the thump) so
## the tail reads as a low rumble rather than the whole thing cutting out
## at once.
static func impact_boom(duration_s: float, thump_hz: float = 80.0,
		noise_seed: int = 0) -> AudioStreamWAV:
	var key := "boom:%f:%f:%d" % [duration_s, thump_hz, noise_seed]
	if _cache.has(key):
		return _cache[key]
	var rng := RandomNumberGenerator.new()
	rng.seed = noise_seed
	var frame_count := maxi(1, roundi(duration_s * SAMPLE_RATE))
	var data := PackedByteArray()
	data.resize(frame_count * 2)
	for i in frame_count:
		var t := float(i) / float(frame_count)
		var noise := rng.randf_range(-1.0, 1.0) * pow(1.0 - t, 4.0)
		var thump := sin(TAU * thump_hz * (float(i) / float(SAMPLE_RATE))) * pow(1.0 - t, 2.5)
		_write_sample(data, i, noise * 0.6 + thump * 0.6)
	var stream := _build_stream(data)
	_cache[key] = stream
	return stream


static func _write_sample(data: PackedByteArray, index: int, sample: float) -> void:
	var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
	data.encode_s16(index * 2, value)


static func _build_stream(data: PackedByteArray) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.data = data
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	return stream
