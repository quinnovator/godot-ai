extends SceneTree

const MainScene := preload("res://main.tscn")
const Style := preload("res://presentation/pixel_art_style.gd")

const NATIVE_SIZE := Vector2i(1280, 720)
const DESIGN_SIZE := Vector2i(320, 180)
const GRID_PIXEL_SIZE := 4

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var configured_size := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)),
	)
	_check(configured_size == NATIVE_SIZE, "project root is not a native 1280x720 framebuffer: %s" % configured_size)
	_check(configured_size != DESIGN_SIZE, "project root regressed to the 320x180 design canvas")
	_check(root.content_scale_size == NATIVE_SIZE, "root content scale regressed to a non-native size: %s" % root.content_scale_size)
	_check(Style.DESIGN_SIZE == DESIGN_SIZE, "style design-grid dimensions changed")
	_check(Style.OUTPUT_SIZE == NATIVE_SIZE, "style native output dimensions changed")
	_check(Style.GRID_PIXEL_SIZE == GRID_PIXEL_SIZE, "style no longer maps one design cell to four native pixels")

	var game := MainScene.instantiate()
	root.add_child(game)
	await process_frame
	await process_frame
	var pixel_scene := game.get_node_or_null("PixelScene") as Node2D
	_check(pixel_scene != null, "main scene lost the direct CanvasItem art host")
	if pixel_scene != null:
		_check(pixel_scene.scale == Vector2(4, 4), "PixelScene does not use the exact 4x direct-render transform")
		_check(pixel_scene.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "PixelScene does not force nearest source-texture sampling")
	_validate_direct_tree(game)
	game.queue_free()
	await process_frame
	_finish()


func _validate_direct_tree(node: Node) -> void:
	_check(not (node is SubViewport), "forbidden offscreen SubViewport at %s" % node.get_path())
	_check(not (node is SubViewportContainer), "forbidden SubViewportContainer at %s" % node.get_path())
	if node is CanvasItem:
		_check(not ((node as CanvasItem).material is ShaderMaterial), "forbidden postprocess ShaderMaterial at %s" % node.get_path())
	for child in node.get_children():
		_validate_direct_tree(child)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PIXIBALL_NATIVE_720_PIPELINE_OK root=1280x720 design=320x180 grid=4px subviewports=0 postprocess=0")
		quit(0)
		return
	for failure in _failures:
		push_error("PIXIBALL_NATIVE_720_PIPELINE: %s" % failure)
	quit(1)
