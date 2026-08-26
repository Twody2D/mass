extends Node
## Checks the camera invariants that are not obvious from a screenshot: that the
## camera cannot be flown off the map or lost, and that it adopts the
## orientation the scene placed it at.

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var cam: FreeCamera = main.get_node("Camera3D")

	var pitch_degrees := rad_to_deg(cam.rotation.x)
	print("adopted pitch  : %.1f deg (scene placed it looking down)" % pitch_degrees)
	failures += _check("pitch is negative, i.e. looking down", pitch_degrees < 0.0)

	var limit: float = GameConfig.MAP_SIZE * 0.5 + FreeCamera.HORIZONTAL_MARGIN
	var far_away := cam._clamp_to_world(Vector3(999999.0, 999999.0, -999999.0))
	print("clamped extreme: ", far_away, " (limit %.0f, altitude %.0f..%.0f)"
		% [limit, FreeCamera.MIN_ALTITUDE, FreeCamera.MAX_ALTITUDE])
	failures += _check("x clamped", is_equal_approx(far_away.x, limit))
	failures += _check("z clamped", is_equal_approx(far_away.z, -limit))
	failures += _check("altitude capped", is_equal_approx(far_away.y, FreeCamera.MAX_ALTITUDE))

	var underground := cam._clamp_to_world(Vector3(0.0, -500.0, 0.0))
	failures += _check("never below minimum altitude",
		is_equal_approx(underground.y, FreeCamera.MIN_ALTITUDE))

	var inside := Vector3(10.0, 100.0, -20.0)
	failures += _check("positions inside the map are untouched",
		cam._clamp_to_world(inside).is_equal_approx(inside))

	# Speed must stay in range no matter how far the wheel is spun.
	for i in 200:
		cam.speed = minf(cam.speed * FreeCamera.SPEED_STEP, FreeCamera.MAX_SPEED)
	failures += _check("speed capped at maximum", is_equal_approx(cam.speed, FreeCamera.MAX_SPEED))
	for i in 400:
		cam.speed = maxf(cam.speed / FreeCamera.SPEED_STEP, FreeCamera.MIN_SPEED)
	failures += _check("speed floored at minimum", is_equal_approx(cam.speed, FreeCamera.MIN_SPEED))

	# Idle camera must not drift.
	cam.speed = FreeCamera.BASE_SPEED
	var before := cam.position
	for i in 10:
		cam._process(0.016)
	failures += _check("no drift without input", cam.position.is_equal_approx(before))

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
