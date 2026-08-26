extends Node

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)

	var cam := main.get_node("Camera3D") as Camera3D
	var world: Node3D = main.get_node("World")
	print("camera current : ", cam.current, " at ", cam.global_position)
	print("camera forward : ", -cam.global_transform.basis.z)
	var sun: DirectionalLight3D = main.get_node("DirectionalLight3D")
	print("sun direction  : ", -sun.global_transform.basis.z)
	var terrain := world.get_node_or_null("Terrain") as MeshInstance3D
	var ocean := world.get_node_or_null("Ocean") as MeshInstance3D
	print("terrain node   : ", terrain, " mesh=", terrain.mesh if terrain else null)
	if terrain and terrain.mesh:
		print("terrain aabb   : ", terrain.mesh.get_aabb())
		print("terrain surfs  : ", terrain.mesh.get_surface_count())
	print("ocean node     : ", ocean)

	for i in 8:
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tools/output")
	var img := get_viewport().get_texture().get_image()
	img.save_png("res://tools/output/screenshot.png")
	get_tree().quit()
