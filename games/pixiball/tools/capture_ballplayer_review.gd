extends SceneTree
## Captures deterministic in-engine review renders of the production
## ballplayer, including the per-team PBR palette and viewport-rendered roster
## identity that only exist at runtime (the Blender QA renders cannot show
## either). Run WITHOUT --headless so the viewport renders:
##
##   godot --path games/pixiball \
##     --script res://tools/capture_ballplayer_review.gd -- --output-dir DIR

const REVIEW_SHOTS := [
	{"name": "engine_rest_front", "camera": Vector3(0.0, 1.45, -3.6), "target": Vector3(0.0, 1.02, 0.0)},
	{"name": "engine_rest_three_quarter", "camera": Vector3(-2.5, 1.7, -2.7), "target": Vector3(0.0, 1.02, 0.0)},
	{"name": "engine_rest_back", "camera": Vector3(0.0, 1.45, 3.6), "target": Vector3(0.0, 1.02, 0.0)},
	{"name": "engine_back_number_closeup", "camera": Vector3(0.0, 1.42, 1.7), "target": Vector3(0.0, 1.30, 0.0)},
	{"name": "engine_face_closeup", "camera": Vector3(0.0, 1.74, -1.0), "target": Vector3(0.0, 1.71, 0.0)},
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_dir := _parse_output_dir()
	DirAccess.make_dir_recursive_absolute(output_dir)
	root.size = Vector2i(768, 768)

	var stage := Node3D.new()
	root.add_child(stage)

	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("343841")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("b8bfcc")
	environment.ambient_light_energy = 0.58
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	stage.add_child(world_environment)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35.0, 28.0, 0.0)
	sun.light_energy = 0.75
	stage.add_child(sun)

	var camera := Camera3D.new()
	camera.fov = 32.0
	stage.add_child(camera)
	camera.make_current()

	var actor := (load("res://characters/ballplayer_actor.tscn") as PackedScene).instantiate()
	actor.configure({
		"seed": 2,
		"role": "pitcher",
		"number": 27,
		"player_name": "Maya Rodriguez",
		"mark": "P",
		"build": "balanced",
		"throws": "right",
		"skin_tone": Color("de8b50"),
		"hair_color": Color("3e1a0b"),
		"primary_color": Color("3a7c8b"),
		"secondary_color": Color("d84936"),
		"accent_color": Color("e8a03c"),
		"pants_color": Color("ead8c3"),
	})
	stage.add_child(actor)
	if actor.get_model_kind() != "rigged_glb":
		_failures.append("authored Blender actor did not load; nothing to review")

	for shot in REVIEW_SHOTS:
		camera.position = shot["camera"] as Vector3
		camera.look_at_from_position(camera.position, shot["target"] as Vector3, Vector3.UP)
		# Key the viewed side: aim the sun from just above and beside the
		# camera so every shot reviews lit surfaces instead of ambient fill.
		var camera_yaw := rad_to_deg(atan2(camera.position.x, camera.position.z))
		sun.rotation_degrees = Vector3(-40.0, camera_yaw + 22.0, 0.0)
		for frame in range(6):
			await process_frame
		var image := root.get_viewport().get_texture().get_image()
		if image == null or image.is_empty():
			_failures.append("%s produced no image" % shot["name"])
			continue
		var path := output_dir.path_join(String(shot["name"]) + ".png")
		if image.save_png(path) != OK:
			_failures.append("%s could not be saved" % shot["name"])

	if _failures.is_empty():
		print("PIXIBALL_BALLPLAYER_REVIEW_OK shots=%d dir=%s" % [REVIEW_SHOTS.size(), output_dir])
		quit(0)
		return
	for failure in _failures:
		push_error("PIXIBALL_BALLPLAYER_REVIEW: %s" % failure)
	quit(1)


func _parse_output_dir() -> String:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--output-dir":
			return args[index + 1]
	return ProjectSettings.globalize_path("user://ballplayer_review")
