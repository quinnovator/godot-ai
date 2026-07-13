extends SceneTree

const BALLPLAYER_SCENE := preload("res://characters/ballplayer_actor.tscn")
const REQUIRED_ACTIONS := [
	"idle", "run", "pitch", "swing", "catch",
	"field_ready", "field_throw", "throw", "celebrate", "slide",
]
const ACTION_DURATIONS := {
	"idle": 0.8,
	"run": 0.4,
	"pitch": 1.42,
	"swing": 0.36,
	"catch": 0.68,
	"field_ready": 0.8,
	"field_throw": 0.86,
	"throw": 0.86,
	"celebrate": 1.55,
	"slide": 1.20,
}
const REQUIRED_MARKERS := [
	"pitch:ball_release",
	"swing:bat_contact",
	"catch:glove_contact",
	"field_throw:ball_release",
	"throw:ball_release",
	"celebrate:celebration_peak",
	"slide:base_contact",
]
const REQUIRED_SOCKETS := [
	"head", "chest", "left_hand", "right_hand", "glove", "catch",
	"throw_hand", "ball_release", "bat_grip", "bat_tip",
	"left_foot", "right_foot", "feet",
]
const SPECS := [
	{"seed": 101, "role": "pitcher", "mark": "H", "number": 41, "player_name": "Amara Stone", "throws": "right", "bats": "right", "primary_color": Color("245347"), "secondary_color": Color("f4f0dd"), "accent_color": Color("e1a72f")},
	{"seed": 202, "role": "batter", "mark": "P", "number": 27, "player_name": "Maya Rodriguez", "throws": "right", "bats": "left", "primary_color": Color("813348"), "secondary_color": Color("e8dfcb"), "accent_color": Color("dfad3e")},
	{"seed": 303, "role": "catcher", "mark": "C", "number": 8, "player_name": "Jun Park", "throws": "right", "bats": "right", "primary_color": Color("185f73"), "secondary_color": Color("f4e8cf"), "accent_color": Color("e45858")},
	{"seed": 404, "role": "umpire", "mark": "", "number": 0, "player_name": "Crew Chief", "throws": "right", "bats": "right", "primary_color": Color("252f3d"), "secondary_color": Color("d8e2e8"), "accent_color": Color("84a0af")},
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pixel_scene := Node2D.new()
	pixel_scene.name = "TemporarySmokePixelScene"
	root.add_child(pixel_scene)
	pixel_scene.add_to_group("pixiball_pixel_scene")

	var actors: Array[BallplayerActor] = []
	var signatures: Array[String] = []
	var observed_markers: Array[String] = []
	var started_actions: Array[String] = []
	for index in range(SPECS.size()):
		var actor := BALLPLAYER_SCENE.instantiate() as BallplayerActor
		actor.name = "SmokeActor%d" % index
		actor.configure(SPECS[index])
		actor.global_position = Vector3(float(index) * 2.5, 0.0, -float(index))
		actor.action_marker.connect(func(action_name: String, marker_name: String) -> void:
			observed_markers.append("%s:%s" % [action_name, marker_name])
		)
		actor.action_started.connect(func(action_name: String) -> void:
			started_actions.append(action_name)
		)
		actors.append(actor)
		root.add_child(actor)
	await process_frame
	await process_frame

	for actor in actors:
		actor.set_physics_process(false)
		_expect(actor.get_model_kind() == "native_pixel_sprite", "%s is not using the native pixel model" % actor.name)
		_expect(_count_3d_nodes(actor) == 0, "%s has a 3D descendant" % actor.name)
		_expect(is_instance_valid(actor.get_pixel_sprite()), "%s did not attach a pixel presenter" % actor.name)
		if is_instance_valid(actor.get_pixel_sprite()):
			_expect(actor.get_pixel_sprite().get_parent() == pixel_scene, "%s presenter attached outside pixiball_pixel_scene" % actor.name)
		var available := actor.get_available_actions()
		_expect(available.size() == REQUIRED_ACTIONS.size(), "%s action coverage changed" % actor.name)
		for action in REQUIRED_ACTIONS:
			_expect(action in available, "%s is missing action %s" % [actor.name, action])
		for socket_name in REQUIRED_SOCKETS:
			_expect(_is_finite_vector(actor.get_socket_position(socket_name)), "%s socket %s is not finite" % [actor.name, socket_name])
		_expect(String(actor.get_equipment_profile().pipeline) == "native_pixel_layers", "%s has the wrong equipment pipeline" % actor.name)
		_expect(actor.get_pixel_palette().primary is Color, "%s primary palette entry is invalid" % actor.name)
		_expect(actor.get_team_mark() == String(SPECS[actors.find(actor)].mark), "%s team identity changed" % actor.name)
		signatures.append(actor.get_generation_signature())

	_expect(_unique_count(signatures) == signatures.size(), "distinct role specs produced duplicate signatures")
	var timing_actor := actors[0]
	for action in REQUIRED_ACTIONS:
		timing_actor.play_action(action)
		timing_actor._physics_process(float(ACTION_DURATIONS[action]) + 0.01)
	_expect(_unique_count(started_actions) == REQUIRED_ACTIONS.size(), "smoke pass did not start every native action")
	for event in REQUIRED_MARKERS:
		_expect(event in observed_markers, "smoke pass missed action marker %s" % event)

	timing_actor.play_action("run")
	timing_actor._physics_process(0.11)
	_expect(int(timing_actor.get_pixel_pose().frame) == 1, "smoke animation did not advance at 10fps")

	var duplicate := BALLPLAYER_SCENE.instantiate() as BallplayerActor
	duplicate.configure(SPECS[0].duplicate(true))
	_expect(duplicate.get_generation_signature() == signatures[0], "same smoke spec produced a different signature")
	duplicate.free()

	_expect(_count_3d_nodes(pixel_scene) == 0, "smoke pixel scene contains a 3D descendant")
	for actor in actors:
		actor.queue_free()
	await process_frame
	pixel_scene.queue_free()
	await process_frame
	_finish()


func _unique_count(values: Array[String]) -> int:
	var unique := {}
	for value in values:
		unique[value] = true
	return unique.size()


func _count_3d_nodes(node: Node) -> int:
	var count := 1 if node is Node3D else 0
	for child in node.get_children():
		count += _count_3d_nodes(child)
	return count


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PIXIBALL_CHARACTER_SMOKE_OK actors=4 model=native_pixel_sprite actions=10 markers=7")
		quit(0)
		return
	for failure in _failures:
		push_error("PIXIBALL_CHARACTER_SMOKE: %s" % failure)
	quit(1)
