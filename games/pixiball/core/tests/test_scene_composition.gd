extends SceneTree

const MAIN_SCENE_PATH := "res://main.tscn"
const FRAMEBUFFER_SIZE := Vector2i(2560, 1440)
const DESIGN_SIZE := Vector2i(640, 360)
const GRID_PIXEL_SIZE := 4

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_validate_project_settings()
	var packed := load(MAIN_SCENE_PATH) as PackedScene
	_expect(packed != null, "main scene did not load")
	if packed == null:
		_finish()
		return

	var session := packed.instantiate()
	root.add_child(session)
	await process_frame
	await process_frame

	for path in [
		"PixelScene",
		"World/Stadium",
		"Actors/Ballplayers",
		"Presentation/Baseball",
		"Presentation/CameraDirector",
		"Systems/LivePlayController",
		"Systems/AudioDirector",
		"Systems/HapticDirector",
		"PixiballHUD",
		"PitchIntelLayer/PitchIntelPanel",
	]:
		_expect(session.has_node(path), "main scene is missing %s" % path)

	var pixel_scene := session.get_node_or_null("PixelScene") as Node2D
	_expect(pixel_scene != null, "PixelScene is not a Node2D")
	if pixel_scene != null:
		_expect(pixel_scene.is_in_group("pixiball_pixel_scene"), "PixelScene is missing its presenter group")
		_expect(pixel_scene.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "PixelScene is not nearest-filtered")
		_expect(pixel_scene.position == pixel_scene.position.round(), "PixelScene is not positioned on the integer grid")
		_expect(pixel_scene.scale == Vector2(GRID_PIXEL_SIZE, GRID_PIXEL_SIZE), "PixelScene must map design units directly to 4px native blocks")

	var camera_director = session.get_node_or_null("Presentation/CameraDirector")
	_expect(camera_director != null and camera_director.logical_vertical_pixels == 1440, "world projector does not expose the native 1440-line root")
	_expect(camera_director != null and camera_director.DESIGN_SIZE == Vector2(DESIGN_SIZE), "world projector lost its 640x360 design grid")
	_expect(camera_director != null and camera_director.FRAMEBUFFER_SIZE == Vector2(FRAMEBUFFER_SIZE), "world projector lost its native framebuffer contract")
	_expect(camera_director != null and camera_director.is_in_group("pixiball_pixel_projector"), "world projector group was not installed")

	var stadium = session.get_node_or_null("World/Stadium")
	var stadium_canvas: Node2D = stadium.get_canvas() if stadium != null else null
	_expect(is_instance_valid(stadium_canvas), "stadium did not attach its native canvas")
	if is_instance_valid(stadium_canvas) and pixel_scene != null:
		_expect(stadium_canvas.get_parent() == pixel_scene, "stadium canvas is outside PixelScene")
		_expect(stadium_canvas.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "stadium canvas is not nearest-filtered")
		_expect(stadium_canvas.global_transform.get_scale() == Vector2(4, 4), "stadium canvas does not rasterize directly on the native 4px grid")

	var baseball = session.get_node_or_null("Presentation/Baseball")
	var ball_sprite: Node2D = baseball.get_pixel_sprite() if baseball != null else null
	_expect(is_instance_valid(ball_sprite), "baseball did not attach its pixel presenter")
	if is_instance_valid(ball_sprite) and pixel_scene != null:
		_expect(ball_sprite.get_parent() == pixel_scene, "baseball presenter is outside PixelScene")
		_expect(ball_sprite.global_transform.get_scale() == Vector2(4, 4), "baseball presenter does not rasterize directly on the native 4px grid")

	_validate_native_tree(session)
	session.queue_free()
	await process_frame
	_finish()


func _validate_project_settings() -> void:
	var framebuffer := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)),
	)
	var window := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/window_width_override", 0)),
		int(ProjectSettings.get_setting("display/window/size/window_height_override", 0)),
	)
	_expect(framebuffer == FRAMEBUFFER_SIZE, "root framebuffer must be native 2560x1440, got %s" % framebuffer)
	_expect(window == FRAMEBUFFER_SIZE, "debug window override must be 2560x1440, got %s" % window)
	_expect(window == framebuffer, "debug window must present native pixels one-to-one")
	_expect(framebuffer != DESIGN_SIZE, "640x360 design space must never become the root framebuffer")
	_expect(String(ProjectSettings.get_setting("display/window/stretch/mode", "")) == "viewport", "stretch mode must preserve the native root viewport")
	_expect(String(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "keep", "stretch aspect must preserve 16:9")
	_expect(String(ProjectSettings.get_setting("display/window/stretch/scale_mode", "")) == "integer", "stretch scale mode must be integer")
	_expect(bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_transforms_to_pixel", false)), "2D transforms are not snapped to pixels")
	_expect(bool(ProjectSettings.get_setting("rendering/2d/snap/snap_2d_vertices_to_pixel", false)), "2D vertices are not snapped to pixels")


func _validate_native_tree(node: Node) -> void:
	_expect(not (node is Node3D), "runtime contains Node3D at %s" % node.get_path())
	_expect(not (node is VisualInstance3D), "runtime contains VisualInstance3D at %s" % node.get_path())
	_expect(not (node is Camera3D), "runtime contains Camera3D at %s" % node.get_path())
	_expect(not (node is SubViewport), "runtime contains SubViewport at %s" % node.get_path())
	if node is CanvasItem:
		_expect(not ((node as CanvasItem).material is ShaderMaterial), "runtime contains ShaderMaterial at %s" % node.get_path())
	for child in node.get_children():
		_validate_native_tree(child)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PIXIBALL_SCENE_CONTRACT_OK framebuffer=2560x1440 design_grid=640x360 density=2x cell=4px direct_canvas=true no_subviewport=true")
		quit(0)
		return
	for failure in _failures:
		push_error("PIXIBALL_SCENE_CONTRACT: %s" % failure)
	quit(1)
