extends SceneTree

## Native 2560x1440 action/role review for the model-free actor pipeline.
## Run without --headless so the canvas can be read back.

const ACTOR_SCENE := preload("res://characters/ballplayer_actor.tscn")
const VIEW_DIRECTOR := preload("res://presentation/broadcast_camera.gd")


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	root.size = Vector2i(2560, 1440)
	var scene := Node.new()
	root.add_child(scene)

	var pixel_scene := Node2D.new()
	pixel_scene.name = "PixelScene"
	pixel_scene.add_to_group("pixiball_pixel_scene")
	pixel_scene.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pixel_scene.scale = Vector2(4, 4)
	scene.add_child(pixel_scene)
	var background := ColorRect.new()
	background.position = Vector2.ZERO
	background.size = Vector2(640, 360)
	background.color = Color("101827")
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pixel_scene.add_child(background)
	for y in [88, 178, 268]:
		var rail := ColorRect.new()
		rail.position = Vector2(0, y)
		rail.size = Vector2(640, 2)
		rail.color = Color("263a4b")
		pixel_scene.add_child(rail)

	var director := VIEW_DIRECTOR.new()
	scene.add_child(director)
	director.set_mode("dugout")

	var actors := Node.new()
	scene.add_child(actors)
	var specs := [
		{"role": "pitcher", "action": "pitch", "x": -42.0, "seed": 11, "mark": "P"},
		{"role": "batter", "action": "swing", "x": -21.0, "seed": 23, "mark": "B", "bats": "left"},
		{"role": "catcher", "action": "catch", "x": 0.0, "seed": 37, "mark": "C"},
		{"role": "fielder", "action": "field_ready", "x": 21.0, "seed": 51, "mark": "F"},
		{"role": "umpire", "action": "field_ready", "x": 42.0, "seed": 71, "mark": ""},
	]
	for index in range(specs.size()):
		var spec: Dictionary = specs[index]
		var actor := ACTOR_SCENE.instantiate() as BallplayerActor
		actor.name = String(spec.role).capitalize()
		actor.configure({
			"role": spec.role,
			"seed": spec.seed,
			"mark": spec.mark,
			"number": 10 + index,
			"bats": spec.get("bats", "right"),
			"primary_color": [Color("44d7b6"), Color("ff6b5e"), Color("4d78b9"), Color("d2a64b"), Color("202a38")][index],
			"secondary_color": Color("f5ead7"),
			"accent_color": Color("ffd166"),
		})
		actor.global_position = Vector3(float(spec.x), 0.08, 10.0)
		actors.add_child(actor)
		actor.hold_action_pose(String(spec.action), 0.55)

	var labels := Node2D.new()
	labels.name = "ReviewLabels"
	labels.scale = Vector2(4, 4)
	labels.z_index = 4096
	labels.z_as_relative = false
	scene.add_child(labels)
	var title := Label.new()
	title.text = "NATIVE PIXEL CAST  /  10 FPS POSES"
	title.position = Vector2(12, 8)
	title.size = Vector2(616, 24)
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color("ffd166"))
	labels.add_child(title)
	for index in range(specs.size()):
		var label := Label.new()
		label.text = String((specs[index] as Dictionary).role).to_upper()
		label.position = Vector2(6 + index * 126, 314)
		label.size = Vector2(124, 20)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 10)
		label.add_theme_color_override("font_color", Color("d7e4ee"))
		labels.add_child(label)

	for unused in range(12):
		await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != Vector2i(2560, 1440):
		push_error("Native actor review did not produce a 2560x1440 image")
		quit(2)
		return
	var output := _output_path()
	var absolute := ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := image.save_png(absolute)
	if error != OK:
		push_error("Could not save native actor review: %s" % error_string(error))
		quit(3)
		return
	print("PIXIBALL_PIXEL_ACTOR_REVIEW_OK path=%s size=2560x1440 density=2x grid=4px roles=5" % output)
	quit()


func _output_path() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			return argument.trim_prefix("--output=")
	return "res://.godot/visual-qa/native-1440/actor-review.png"
