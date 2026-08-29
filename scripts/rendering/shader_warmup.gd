class_name ShaderWarmup
extends Node3D
## Builds one throwaway instance of every meteor visual, deep underground,
## purely so Godot compiles their render pipelines now rather than at the
## first real impact.
##
## Forward+ compiles a full pipeline the first time it sees a given
## shader/mesh-format/blend-state combination, synchronously, on whichever
## frame first asks for it. A meteor is the single biggest one-time
## introduction of new materials in the whole run — meteor_rock, smoke,
## three different uses of blast (flame, core, sparks), crater_floor, plus
## GroundEjecta's and ShockwaveEffect's own StandardMaterial3D blend states —
## and the first real impact was paying the compile cost for all of them at
## once, in the middle of the shot it is supposed to be.
##
## Not verified by this file: whether it actually removes the stutter is a
## real-frame question, the same as the meteor light's own shadow cost —
## headless has no render context to measure a compile stall against. Moving
## the one-time cost to start-up rather than mid-impact is the best this can
## do without a real loading screen, which nothing here has.
##
## Uses its own RandomNumberGenerator rather than EventManager.rng(): this
## must not consume a single number from the real event stream, or a meteor
## fired later on the same seed would land somewhere different than it used
## to.

## Deep enough that no camera mode's own terrain clamp or altitude range
## could ever bring it into view, on this island or a taller one.
const DEPTH := -5000.0

## One frame is enough for the renderer to see everything and start
## compiling; a second gives it room to actually finish before this frees
## itself and takes the pipelines' one reason to exist along with it —
## though the compiled pipelines themselves outlive the objects that
## triggered them for the rest of the process.
const WARMUP_FRAMES := 2

const BLAST_COLOR := Color(1.0, 0.52, 0.18)
const RADIUS := 40.0


## Fires the warm-up and frees itself once it has run. `parent` only needs to
## be somewhere in the live scene tree; nothing about where matters, since
## everything it builds sits far below the map.
static func run(parent: Node) -> void:
	var warmup := ShaderWarmup.new()
	parent.add_child(warmup)
	warmup._spawn()
	for i in WARMUP_FRAMES:
		await warmup.get_tree().process_frame
	warmup.queue_free()


func _spawn() -> void:
	var rng := RandomNumberGenerator.new()
	var at := Vector3(0.0, DEPTH, 0.0)
	var ground := func(_x: float, _z: float) -> float: return DEPTH - 10.0

	add_child(BlastEffect.create(at, RADIUS, BLAST_COLOR))
	add_child(GroundEjecta.create(at, RADIUS, rng, ground))
	add_child(ShockwaveEffect.create(at, RADIUS, BLAST_COLOR, ground, DEPTH - 20.0))
	add_child(MushroomCloud.create(at, RADIUS, rng))
	add_child(Crater.create(at, RADIUS, rng, ground, DEPTH - 20.0))

	# Never advanced, only built: launch() constructs the rock, its tail and
	# its light in full, which is everything that needed compiling. It just
	# has to sit in the tree for a frame, not actually fall.
	var meteor := MeteorProjectile.launch(at, RADIUS, rng, ground, func() -> void: pass)
	if meteor != null:
		add_child(meteor)
