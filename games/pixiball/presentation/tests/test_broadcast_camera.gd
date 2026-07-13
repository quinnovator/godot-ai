extends SceneTree

const BroadcastCamera := preload("res://presentation/broadcast_camera.gd")

class FocusNode extends Node:
	var global_position := Vector3.ZERO

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var director := BroadcastCamera.new()
	root.add_child(director)
	await process_frame
	director.set_process(false)

	_check(director.DESIGN_SIZE == Vector2(320, 180), "projector design grid must remain 320x180 cells")
	_check(director.FRAMEBUFFER_SIZE == Vector2(1280, 720), "projector framebuffer must be native 1280x720")
	_check(director.LOGICAL_SIZE == Vector2(1280, 720), "projector logical root must be native 1280x720")
	_check(director.GRID_PIXEL_SIZE == 4, "projector design cells must map to 4px native blocks")
	_check(director.logical_vertical_pixels == 720, "projector must expose 720 logical root lines")
	_check(director.GAMEPLAY_MODES == ["pitching", "fielding", "batting"], "projector must expose the three gameplay views")
	_check(director.is_in_group("pixiball_pixel_projector"), "projector group was not installed")
	_validate_native_tree(director)

	director.set_mode("pitching")
	_check(director.mode == "pitching", "pitching view was not selected")
	_check(director.plate_lateral_screen_sign() == -1.0, "pitching view must mirror plate lateral coordinates")
	_check(director.projected_strike_zone() == Rect2(82, 62, 30, 38), "pitching strike zone moved off its authored pixels")
	_check(director.projected_strike_zone_native() == Rect2(328, 248, 120, 152), "pitching strike zone lost its exact native-grid mapping")
	_check(director.project_world(Vector3(0.0, 0.08, 0.0)) == Vector2(201, 133), "pitching mound projection changed")
	_check(director.project_world(Vector3(0.0, 0.08, 18.0)) == Vector2(113, 91), "pitching plate projection changed")
	_check(director.project_world_native(Vector3(0.0, 0.08, 0.0)) == Vector2(804, 532), "pitching mound did not map to native 720p coordinates")
	_check(director.project_world_native(Vector3(0.0, 0.08, 18.0)) == Vector2(452, 364), "pitching plate did not map to native 720p coordinates")
	_check(director.actor_lod(Vector3(0, 0, 0)) == "large", "near pitching actor must use large pixels")
	_check(director.actor_lod(Vector3(0, 0, 12)) == "small", "middle pitching actor must use small pixels")
	_check(director.actor_lod(Vector3(0, 0, 30)) == "tiny", "distant pitching actor must use tiny pixels")
	for role in ["pitcher", "batter", "catcher", "umpire"]:
		_check(director.actor_visible(Vector3.ZERO, role), "pitching view hid required role %s" % role)
	_check(not director.actor_visible(Vector3.ZERO, "fielder"), "pitching view exposed a distant fielder")
	_check(director.actor_screen_offset(Vector3.ZERO, "batter") == Vector2(-8, 1), "pitching batter offset changed")
	_check(director.actor_screen_offset(Vector3.ZERO, "catcher") == Vector2(3, 3), "pitching catcher offset changed")
	_check(director.actor_screen_offset(Vector3.ZERO, "umpire") == Vector2(10, 1), "pitching umpire offset changed")

	director.set_mode("batting")
	_check(director.mode == "batting", "batting view was not selected")
	_check(director.plate_lateral_screen_sign() == 1.0, "batting view must preserve plate lateral coordinates")
	_check(director.projected_strike_zone() == Rect2(137, 91, 46, 56), "batting strike zone moved off its authored pixels")
	_check(director.projected_strike_zone_native() == Rect2(548, 364, 184, 224), "batting strike zone lost its exact native-grid mapping")
	_check(director.project_world(Vector3(0.0, 0.08, 18.0)) == Vector2(160, 154), "batting plate projection changed")
	_check(director.project_world(Vector3(0.0, 0.08, 0.0)) == Vector2(160, 76), "batting mound projection changed")
	_check(director.actor_lod(Vector3(0, 0, 18)) == "large", "batting foreground actor must use large pixels")
	_check(director.actor_lod(Vector3(0, 0, 0)) == "small", "batting pitcher must use small pixels")
	_check(director.actor_visible(Vector3.ZERO, "pitcher") and director.actor_visible(Vector3.ZERO, "batter"), "batting view lost a required role")
	_check(not director.actor_visible(Vector3.ZERO, "catcher"), "batting view exposed the catcher corridor")
	_check(director.actor_screen_offset(Vector3.ZERO, "batter") == Vector2(-22, -1), "batting actor offset changed")

	var focus := FocusNode.new()
	focus.global_position = Vector3(7.0, 4.0, -9.0)
	root.add_child(focus)
	director.set_mode("fielding", focus)
	_check(director.mode == "fielding" and director.target_node == focus, "fielding view did not retain its logic focus")
	_check(director.projected_strike_zone() == Rect2(), "fielding view unexpectedly exposes a strike zone")
	_check(director.actor_lod(Vector3.ZERO) == "tiny", "fielding actors must use tiny pixels")
	_check(director.actor_visible(Vector3.ZERO, "fielder"), "fielding view hid a fielder")
	var focused_projection := director.project_world(Vector3(5.25, 1.4, -12.5))
	_check(focused_projection == focused_projection.round(), "fielding projection is not integer-aligned")
	_check(focused_projection == director.project_world(Vector3(5.25, 1.4, -12.5)), "fielding projection is not deterministic")
	_check(director.depth_order(Vector3(5.25, 1.4, -12.5)) == int(director.depth_order(Vector3(5.25, 1.4, -12.5))), "fielding depth order is not discrete")

	director.set_mode("dugout")
	_check(director.actor_lod(Vector3.ZERO) == "large", "dugout actor must use large pixels")
	_check(director.actor_visible(Vector3(0, 0, 10), "fielder"), "dugout foreground actor should be visible")
	_check(not director.actor_visible(Vector3(0, 0, 8), "fielder"), "dugout background actor should be culled")
	_validate_integer_projection(director, [
		Vector3.ZERO,
		Vector3(4.5, 1.8, -7.25),
		Vector3(-13.0, 0.08, 4.0),
		Vector3(0.0, 2.5, 18.0),
	])

	var plate_point := director.plate_location_world(0.5, 2.5)
	_check(_is_finite_vector(plate_point), "plate mapping produced a non-finite world point")

	var exit_code := 0
	if _failures.is_empty():
		print("PIXIBALL_CAMERA_OK framebuffer=1280x720 design_grid=320x180 cell=4px projection=integer lod=deterministic")
	else:
		for failure in _failures:
			push_error("PIXIBALL_CAMERA: %s" % failure)
		exit_code = 1
	focus.queue_free()
	director.queue_free()
	await process_frame
	quit(exit_code)


func _validate_integer_projection(director: Node, samples: Array) -> void:
	for sample_value in samples:
		var sample: Vector3 = sample_value
		var first: Vector2 = director.call("project_world", sample)
		var second: Vector2 = director.call("project_world", sample)
		_check(first == first.round(), "projection is not integer-aligned for %s" % sample)
		_check(first == second, "projection is not deterministic for %s" % sample)
		var native: Vector2 = director.call("project_world_native", sample)
		_check(int(native.x) % 4 == 0 and int(native.y) % 4 == 0, "native projection left the 4px grid for %s" % sample)


func _validate_native_tree(node: Node) -> void:
	_check(not (node is Node3D), "projector tree contains Node3D at %s" % node.get_path())
	_check(not (node is VisualInstance3D), "projector tree contains VisualInstance3D at %s" % node.get_path())
	_check(not (node is Camera3D), "projector tree contains Camera3D at %s" % node.get_path())
	_check(not (node is SubViewport), "projector tree contains SubViewport at %s" % node.get_path())
	if node is CanvasItem:
		_check(not ((node as CanvasItem).material is ShaderMaterial), "projector tree contains ShaderMaterial at %s" % node.get_path())
	for child in node.get_children():
		_validate_native_tree(child)


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
