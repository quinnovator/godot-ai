extends SceneTree

const BroadcastCamera = preload("res://presentation/broadcast_camera.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var director := BroadcastCamera.new()
	root.add_child(director)
	await process_frame
	director.set_process(false)

	_check(director.GAMEPLAY_MODES == ["pitching", "fielding", "batting"], "camera director must expose exactly three gameplay modes")

	director.set_mode("pitching")
	_check(director.mode == "pitching", "pitching mode must be selected")
	_check(director.global_position.is_equal_approx(Vector3(3.2, 1.9, -28.0)), "pitching mode must hard-cut to the broadcast lens")
	_check(is_equal_approx(director.camera.fov, 8.0), "pitching lens must retain the telephoto FOV")
	_check(director.get_node_or_null("BroadcastFill") is DirectionalLight3D, "broadcast lens must carry a restrained readability fill")
	_check(director.plate_lateral_screen_sign() < 0.0, "center-field broadcast projection must mirror plate lateral coordinates")

	director.set_mode("batting")
	_check(director.mode == "batting", "batting mode must be distinct from pitching")
	_check(director.global_position.is_equal_approx(Vector3(0.0, 2.4, 27.0)), "batting mode must use the behind-plate corridor")
	_check(director.desired_target.is_equal_approx(director.plate_location_world(0.0, 4.15)), "batting mode must look above the zone to retain the pitcher")
	_check(is_equal_approx(director.camera.fov, 15.0), "batting mode must use the competitive zone-hitting FOV")
	_check(director.plate_lateral_screen_sign() > 0.0, "behind-plate projection must preserve plate lateral coordinates")
	var projected_zone := director.projected_strike_zone()
	var viewport_center := director.camera.get_viewport().get_visible_rect().size * 0.5
	_check(projected_zone.size.x > 80.0 and projected_zone.size.y > 120.0, "batting lens must make the physical zone large enough to read")
	_check(absf(projected_zone.get_center().x - viewport_center.x) < 3.0, "batting lens must center the physical zone laterally")
	_check(projected_zone.get_center().y > viewport_center.y and projected_zone.end.y < viewport_center.y * 1.82, "batting lens must keep the zone above the help rail")
	var pitcher_release_screen := director.camera.unproject_position(Vector3(0.0, 1.8, 0.0))
	_check(pitcher_release_screen.y > viewport_center.y * 0.18 and pitcher_release_screen.y < viewport_center.y, "batting lens must retain the pitcher's delivery above the zone")

	var ball := Node3D.new()
	ball.position = Vector3(7.0, 4.0, -9.0)
	root.add_child(ball)
	director.set_mode("fielding", ball)
	_check(director.mode == "fielding" and director.target_node == ball, "fielding mode must follow the live baseball")
	_check(director.global_position.is_equal_approx(director.desired_position), "fielding mode must hard-cut before beginning its dynamic follow")
	_check(is_equal_approx(director.camera.fov, 52.0), "fielding mode must retain the PlayCam FOV")

	var exit_code := 0
	if failures.is_empty():
		print("PIXIBALL_CAMERA_OK modes=3 batting_zone=true hard_cuts=true")
	else:
		for failure in failures:
			push_error("PIXIBALL_CAMERA: %s" % failure)
		exit_code = 1
	ball.queue_free()
	director.queue_free()
	await process_frame
	quit(exit_code)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
