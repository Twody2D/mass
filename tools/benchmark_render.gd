extends Node
## Measures what the crowd actually costs on this machine, at every target
## scale. Must run windowed: headless renders nothing, so headless FPS is a lie.

const WARMUP_FRAMES := 30
const MEASURED_FRAMES := 120


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var bots: BotManager = main.get_node("Bots")
	var crowd: CrowdRenderer = main.get_node("Crowd")

	print("--- crowd rendering, %d frames per measurement ---" % MEASURED_FRAMES)
	for n in [100, 1000, 5000, 10000]:
		main.rebuild(GameConfig.DEFAULT_MAP_SEED, n)

		# Cost of one buffer upload, which the simulation tick will pay.
		var t0 := Time.get_ticks_usec()
		for i in 10:
			crowd.update_transforms()
		var upload_us := (Time.get_ticks_usec() - t0) / 10.0

		for i in WARMUP_FRAMES:
			await RenderingServer.frame_post_draw
		var start := Time.get_ticks_usec()
		for i in MEASURED_FRAMES:
			await RenderingServer.frame_post_draw
		var frame_us := float(Time.get_ticks_usec() - start) / MEASURED_FRAMES

		print("  %6d bots : %6.1f FPS, frame %5.2f ms, buffer upload %5.2f ms"
			% [bots.count, 1000000.0 / frame_us, frame_us / 1000.0, upload_us / 1000.0])

	print("triangles/bot  : ", crowd.multimesh.mesh.get_faces().size() / 3)
	get_tree().quit()
