extends Node
## Answers one question: how much geometry can ten thousand instances afford on
## this machine? Swaps the crowd mesh for candidates of increasing complexity
## and measures the same scene each time, so the only variable is the mesh.

const WARMUP_FRAMES := 30
const MEASURED_FRAMES := 90
const BOTS := 10000


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var crowd: CrowdRenderer = main.get_node("Crowd")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)

	# This tool compares mesh candidates on a level field: the whole crowd
	# through one mesh, not split across LOD tiers by distance from whatever
	# the scene's default camera happens to be, and not split across classes
	# either. No camera means every bot lands on the nearest LOD level, which
	# near_tier_nodes() returns one node per class of — all of them need the
	# candidate mesh, or only the bots of class 0 would actually be measured.
	crowd.camera = null
	crowd.rebuild()

	var near_nodes := crowd.near_tier_nodes()
	var material: Material = near_nodes[0].multimesh.mesh.surface_get_material(0)
	var candidates := {
		"box": _primitive(BoxMesh.new(), material),
		"capsule 6x1": _capsule(6, 1, material),
		"capsule 8x2": _capsule(8, 2, material),
		"knight": near_nodes[0].multimesh.mesh,
	}

	print("--- crowd mesh budget at %d bots, %d frames each ---" % [BOTS, MEASURED_FRAMES])
	for name in candidates:
		var mesh: Mesh = candidates[name]
		for node in near_nodes:
			node.multimesh.mesh = mesh
		for i in WARMUP_FRAMES:
			await RenderingServer.frame_post_draw
		var start := Time.get_ticks_usec()
		for i in MEASURED_FRAMES:
			await RenderingServer.frame_post_draw
		var frame_us := float(Time.get_ticks_usec() - start) / MEASURED_FRAMES
		var faces := mesh.get_faces().size() / 3
		print("  %-12s %4d tris : %6.1f FPS, frame %6.2f ms"
			% [name, faces, 1000000.0 / frame_us, frame_us / 1000.0])

	get_tree().quit()


func _primitive(mesh: PrimitiveMesh, material: Material) -> Mesh:
	mesh.material = material
	return mesh


func _capsule(segments: int, rings: int, material: Material) -> Mesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = GameConfig.BOT_RADIUS
	mesh.height = GameConfig.BOT_HEIGHT
	mesh.radial_segments = segments
	mesh.rings = rings
	mesh.material = material
	return mesh
