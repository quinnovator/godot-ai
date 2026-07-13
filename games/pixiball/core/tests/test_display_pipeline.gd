extends SceneTree

const FRAMEBUFFER_SIZE := Vector2i(1280, 720)
const DESIGN_SIZE := Vector2i(320, 180)
const GRID_PIXEL_SIZE := 4

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	_check_project_contract()
	_check_root_window_contract()
	_finish()


func _check_project_contract() -> void:
	var framebuffer := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/viewport_width", 0)),
		int(ProjectSettings.get_setting("display/window/size/viewport_height", 0)),
	)
	var output := Vector2i(
		int(ProjectSettings.get_setting("display/window/size/window_width_override", 0)),
		int(ProjectSettings.get_setting("display/window/size/window_height_override", 0)),
	)
	_expect(framebuffer == FRAMEBUFFER_SIZE, "root framebuffer must be native 1280x720, got %s" % framebuffer)
	_expect(output == FRAMEBUFFER_SIZE, "default output must be 1280x720, got %s" % output)
	_expect(framebuffer == output, "default window must not upscale a lower-resolution root framebuffer")
	_expect(framebuffer != DESIGN_SIZE, "320x180 design space must never become the root framebuffer")
	_expect(framebuffer == DESIGN_SIZE * GRID_PIXEL_SIZE, "native framebuffer must contain the exact 4px design grid")
	_expect(String(ProjectSettings.get_setting("display/window/stretch/mode", "")) == "viewport", "stretch mode must target the native root viewport")
	_expect(String(ProjectSettings.get_setting("display/window/stretch/aspect", "")) == "keep", "stretch aspect must letterbox instead of distorting")
	_expect(String(ProjectSettings.get_setting("display/window/stretch/scale_mode", "")) == "integer", "stretch scale must reject fractional presentation")
	_expect(bool(ProjectSettings.get_setting("display/window/dpi/allow_hidpi", false)), "HiDPI must remain enabled so Windows does not bitmap-scale the game")
	_expect(int(ProjectSettings.get_setting("rendering/textures/canvas_textures/default_texture_filter", -1)) == 0, "root canvas texture filter must be Nearest")


func _check_root_window_contract() -> void:
	# Headless display drivers expose a 64x64 dummy OS surface, so the stable
	# rendering contract is the root content scale configured for real windows.
	_expect(root.content_scale_size == FRAMEBUFFER_SIZE, "root content scale size must be native 1280x720, got %s" % root.content_scale_size)
	_expect(root.content_scale_size != DESIGN_SIZE, "root content scale must not use the 320x180 design grid")
	_expect(root.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT, "root window did not apply viewport stretch mode")
	_expect(root.content_scale_aspect == Window.CONTENT_SCALE_ASPECT_KEEP, "root window did not apply keep-aspect letterboxing")
	_expect(root.content_scale_stretch == Window.CONTENT_SCALE_STRETCH_INTEGER, "root window did not apply integer stretch")
	_expect(root.canvas_item_default_texture_filter == Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST, "root viewport did not apply nearest texture filtering")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PIXIBALL_DISPLAY_PIPELINE_OK framebuffer=1280x720 design_grid=320x180 cell=4px direct=true filter=nearest hidpi=true")
		quit(0)
		return
	for failure in _failures:
		push_error("PIXIBALL_DISPLAY_PIPELINE: %s" % failure)
	quit(1)
