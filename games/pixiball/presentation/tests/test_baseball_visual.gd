extends SceneTree

const BaseballVisualScript := preload("res://presentation/baseball_visual.gd")
const BroadcastCamera := preload("res://presentation/broadcast_camera.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pixel_scene := Node2D.new()
	pixel_scene.name = "TemporaryBallPixelScene"
	pixel_scene.scale = Vector2(4, 4)
	pixel_scene.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root.add_child(pixel_scene)
	pixel_scene.add_to_group("pixiball_pixel_scene")

	var projector := BroadcastCamera.new()
	root.add_child(projector)
	var ball := BaseballVisualScript.new()
	root.add_child(ball)
	await process_frame
	await process_frame
	projector.set_process(false)

	var sprite := ball.get_pixel_sprite()
	_check(is_instance_valid(sprite), "baseball did not attach its pixel presenter")
	if is_instance_valid(sprite):
		_check(sprite is Node2D, "baseball presenter is not a Node2D")
		_check(sprite.get_parent() == pixel_scene, "baseball presenter is outside pixiball_pixel_scene")
		_check(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "baseball presenter is not nearest-filtered")
		_check((sprite as Node2D).global_transform.get_scale() == Vector2(4, 4), "baseball presenter does not rasterize on the native 4px grid")
	_validate_native_tree(ball)
	_validate_native_tree(pixel_scene)
	_validate_native_tree(projector)

	projector.set_mode("pitching")
	ball.set_trail_slot(3)
	_check(ball.get_trail_color().is_equal_approx(Color("ffd94a")), "pitch slot did not select its authored trail color")
	ball.set_active(true)
	ball.use_pitch_ball()
	ball.begin_pitch_motion(2400.0, 180.0, false)
	_check(ball.get_spin_contract() == {"rpm": 2400.0, "axis_degrees": 180.0}, "spin contract changed")
	for index in range(1, 8):
		ball.set_ball_position(Vector3(float(index), float(index % 2), float(index) * -0.5))
	var pitch_trail: Array = ball.get_trail_world_points()
	_check(pitch_trail.size() == 5, "pitch trail must be bounded to five discrete points")
	_check(pitch_trail[0] == Vector3(6.0, 0.0, -3.0), "pitch trail did not keep newest point first")
	_check(pitch_trail[4] == Vector3(2.0, 0.0, -1.0), "pitch trail did not evict its oldest point")
	_validate_trail_points(pitch_trail, "pitch")
	var unchanged_size := pitch_trail.size()
	ball.set_ball_position(ball.global_position)
	_check(ball.get_trail_world_points().size() == unchanged_size, "stationary baseball added a duplicate trail point")

	ball.use_play_ball()
	_check(ball.is_play_ball(), "play-ball scale was not selected")
	_check(ball.get_trail_world_points().is_empty(), "switching ball modes did not clear the trail")
	for index in range(8, 12):
		ball.set_ball_position(Vector3(float(index), 0.2, -float(index)))
	var play_trail: Array = ball.get_trail_world_points()
	_check(play_trail.size() == 2, "fielding trail must be bounded to two discrete points")
	_check(play_trail[0] == Vector3(10.0, 0.2, -10.0) and play_trail[1] == Vector3(9.0, 0.2, -9.0), "fielding trail ordering changed")
	_validate_trail_points(play_trail, "fielding")

	if is_instance_valid(sprite):
		sprite._process(0.0)
		_check(sprite.visible, "active baseball presenter is hidden")
		_check(sprite.projector == projector, "baseball presenter did not bind the integer projector")
	ball.set_active(false)
	_check(not ball.is_active(), "baseball did not become inactive")
	_check(ball.get_trail_world_points().is_empty(), "inactive baseball retained trail points")
	if is_instance_valid(sprite):
		_check(not sprite.visible, "inactive baseball presenter remained visible")

	ball.begin_pitch_motion(-20.0, 275.0, false)
	_check(ball.get_spin_contract() == {"rpm": 0.0, "axis_degrees": 275.0}, "spin contract did not bound negative RPM")

	var exit_code := 0
	if _failures.is_empty():
		print("PIXIBALL_BASEBALL_VISUAL_OK presenter=native_720p grid=4px trail=5/2 spin=bounded")
	else:
		for failure in _failures:
			push_error("PIXIBALL_BASEBALL_VISUAL: %s" % failure)
		exit_code = 1
	ball.queue_free()
	projector.queue_free()
	await process_frame
	pixel_scene.queue_free()
	await process_frame
	quit(exit_code)


func _validate_trail_points(points: Array, context: String) -> void:
	for point in points:
		_check(point is Vector3, "%s trail contains a non-Vector3 sample" % context)
		if point is Vector3:
			_check(_is_finite_vector(point), "%s trail contains a non-finite sample" % context)


func _validate_native_tree(node: Node) -> void:
	_check(not (node is Node3D), "baseball runtime contains Node3D at %s" % node.get_path())
	_check(not (node is VisualInstance3D), "baseball runtime contains VisualInstance3D at %s" % node.get_path())
	_check(not (node is Camera3D), "baseball runtime contains Camera3D at %s" % node.get_path())
	_check(not (node is SubViewport), "baseball runtime contains SubViewport at %s" % node.get_path())
	if node is CanvasItem:
		_check(not ((node as CanvasItem).material is ShaderMaterial), "baseball runtime contains ShaderMaterial at %s" % node.get_path())
	for child in node.get_children():
		_validate_native_tree(child)


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
