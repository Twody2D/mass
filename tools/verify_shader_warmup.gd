extends Node
## Checks ShaderWarmup's mechanics: whether the compile stall it exists to
## avoid actually shrinks is not something headless can answer — the same
## limitation every shader-visual check in this project already accepts (see
## verify_events.gd's own note on the meteor's cracks). What this can check
## is that it builds one of everything, cleans up after itself, and does not
## perturb the real event stream's determinism.

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var events: EventManager = main.get_node("Events")

	print("--- determinism: warm-up must not touch the real event stream ---")
	# events.reset() always starts _rng from a known point regardless of what
	# ran before it, which would hide a warm-up quietly drawing from the real
	# stream. Comparing RandomNumberGenerator.state before and after — the
	# same "did calling this change anything observable" check .state exists
	# for — catches that directly instead.
	var state_before: int = events.rng().state
	ShaderWarmup.run(main)
	for i in ShaderWarmup.WARMUP_FRAMES + 2:
		await get_tree().process_frame
	failures += _check("the real event stream's RNG state is untouched by a warm-up",
		events.rng().state == state_before)

	print("--- the warm-up itself ---")
	var probe := Node3D.new()
	add_child(probe)
	var before := probe.get_child_count()
	# run() executes _spawn() synchronously before its first await, so the
	# children already exist the instant this call returns — no need to wait
	# a frame just to observe that it built something.
	ShaderWarmup.run(probe)
	var during := probe.get_child_count()
	failures += _check("it builds something while it runs (%d children)" % during,
		during > before)

	var waited := 0
	while probe.get_child_count() > before and waited < 30:
		await get_tree().process_frame
		waited += 1
	failures += _check("and frees all of it again on its own (%d frames)" % waited,
		probe.get_child_count() == before)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
