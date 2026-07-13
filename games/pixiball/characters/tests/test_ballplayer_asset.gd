extends SceneTree

const ACTOR_SCENE_PATH := "res://characters/ballplayer_actor.tscn"
const REQUIRED_ACTIONS := [
	"idle", "run", "pitch", "swing", "catch",
	"field_ready", "field_throw", "throw", "celebrate", "slide",
]
const ACTION_FRAME_COUNTS := {
	"idle": 2,
	"run": 4,
	"pitch": 7,
	"swing": 4,
	"catch": 4,
	"field_ready": 2,
	"field_throw": 5,
	"throw": 5,
	"celebrate": 3,
	"slide": 3,
}
const MARKER_CASES := [
	{"action": "pitch", "marker": "ball_release", "duration": 1.42, "fraction": 27.0 / 44.0},
	{"action": "swing", "marker": "bat_contact", "duration": 0.36, "fraction": 19.0 / 29.0},
	{"action": "catch", "marker": "glove_contact", "duration": 0.68, "fraction": 14.0 / 25.0},
	{"action": "field_throw", "marker": "ball_release", "duration": 0.86, "fraction": 18.0 / 31.0},
	{"action": "throw", "marker": "ball_release", "duration": 0.86, "fraction": 18.0 / 31.0},
	{"action": "celebrate", "marker": "celebration_peak", "duration": 1.55, "fraction": 24.0 / 49.0},
	{"action": "slide", "marker": "base_contact", "duration": 1.20, "fraction": 22.0 / 39.0},
]
const REQUIRED_SOCKETS := [
	"head", "chest", "left_hand", "right_hand", "glove", "catch",
	"throw_hand", "ball_release", "bat_grip", "bat_tip",
	"left_foot", "right_foot", "feet",
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(ACTOR_SCENE_PATH) as PackedScene
	_expect(packed != null, "native actor scene did not load")
	if packed == null:
		_finish()
		return

	for dependency in ResourceLoader.get_dependencies(ACTOR_SCENE_PATH):
		_expect(String(dependency).contains(".gd"), "actor scene has a non-script presentation dependency: %s" % dependency)

	var pixel_scene := Node2D.new()
	pixel_scene.name = "TemporaryPixelScene"
	root.add_child(pixel_scene)
	pixel_scene.add_to_group("pixiball_pixel_scene")

	var spec := {
		"seed": 20260712,
		"role": "batter",
		"number": 27,
		"mark": "h",
		"player_name": "Maya Rodriguez",
		"bats": "left",
		"throws": "right",
		"primary_color": Color("813348"),
		"secondary_color": Color("e8dfcb"),
		"accent_color": Color("dfad3e"),
		"pants_color": Color("f1eee5"),
	}
	var actor := packed.instantiate() as BallplayerActor
	_expect(actor != null, "actor scene root is not BallplayerActor")
	if actor == null:
		pixel_scene.queue_free()
		_finish()
		return
	actor.name = "NativeBatter"
	actor.configure(spec)
	actor.global_position = Vector3(4.5, 0.0, -7.25)
	root.add_child(actor)
	await process_frame
	await process_frame

	_expect(actor.get_model_kind() == "native_pixel_sprite", "actor reported the wrong model kind")
	_expect(not actor.is_using_fallback(), "native actor reported a fallback path")
	_expect(_count_3d_nodes(actor) == 0, "actor contains a 3D descendant")
	_expect(_count_3d_nodes(pixel_scene) == 0, "native pixel scene contains a 3D descendant")

	var sprite := actor.get_pixel_sprite()
	_expect(is_instance_valid(sprite), "actor did not attach its native pixel sprite")
	if is_instance_valid(sprite):
		_expect(sprite is Node2D, "pixel presenter is not a Node2D")
		_expect(sprite.get_parent() == pixel_scene, "pixel presenter did not attach to pixiball_pixel_scene")
		_expect(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "pixel presenter is not nearest-filtered")

	_validate_action_coverage(actor)
	_validate_ten_fps_frames(packed, spec)
	_validate_marker_timing(packed, spec)
	_validate_sockets(actor)
	_validate_signature(packed, spec, actor.get_generation_signature())
	_validate_palette(actor)

	actor.queue_free()
	await process_frame
	pixel_scene.queue_free()
	await process_frame
	_finish()


func _validate_action_coverage(actor: BallplayerActor) -> void:
	var available := actor.get_available_actions()
	_expect(available.size() == REQUIRED_ACTIONS.size(), "native action count changed: %d" % available.size())
	for action in REQUIRED_ACTIONS:
		_expect(action in available, "native actor is missing action %s" % action)
	for action in available:
		_expect(String(action) in REQUIRED_ACTIONS, "native actor exposes unexpected action %s" % action)

	for action in REQUIRED_ACTIONS:
		actor.hold_action_pose(action, 0.5)
		var pose := actor.get_pixel_pose()
		var frame_count := int(ACTION_FRAME_COUNTS[action])
		_expect(String(pose.get("action", "")) == action, "held pose normalized %s incorrectly" % action)
		_expect(is_equal_approx(float(pose.get("phase", -1.0)), 0.5), "%s held pose lost normalized phase" % action)
		_expect(int(pose.get("frame", -1)) >= 0 and int(pose.get("frame", -1)) < frame_count, "%s held pose exceeded its stepped frame range" % action)
	actor.play_action("not_an_action")
	_expect(actor.get_current_action() == "idle", "unknown actions must normalize to idle")


func _validate_ten_fps_frames(packed: PackedScene, spec: Dictionary) -> void:
	var actor := packed.instantiate() as BallplayerActor
	actor.configure(spec)
	actor.play_action("run")
	_expect(int(actor.get_pixel_pose().frame) == 0, "run did not start on frame zero")
	actor._physics_process(0.099)
	_expect(int(actor.get_pixel_pose().frame) == 0, "frame advanced before the 10fps boundary")
	actor._physics_process(0.002)
	_expect(int(actor.get_pixel_pose().frame) == 1, "frame did not advance at the 10fps boundary")
	actor._physics_process(0.098)
	_expect(int(actor.get_pixel_pose().frame) == 1, "stepped frame changed between 10fps boundaries")
	actor._physics_process(0.002)
	_expect(int(actor.get_pixel_pose().frame) == 2, "second 10fps frame boundary was missed")
	actor.free()


func _validate_marker_timing(packed: PackedScene, spec: Dictionary) -> void:
	var actor := packed.instantiate() as BallplayerActor
	actor.configure(spec)
	var events: Array[String] = []
	actor.action_marker.connect(func(action_name: String, marker_name: String) -> void:
		events.append("%s:%s" % [action_name, marker_name])
	)
	for marker_case in MARKER_CASES:
		var action := String(marker_case.action)
		var marker := String(marker_case.marker)
		var event := "%s:%s" % [action, marker]
		var marker_time := float(marker_case.duration) * float(marker_case.fraction)
		var before_count := events.count(event)
		actor.play_action(action)
		actor._physics_process(marker_time - 0.002)
		_expect(events.count(event) == before_count, "%s fired before its authored time" % event)
		actor._physics_process(0.004)
		_expect(events.count(event) == before_count + 1, "%s did not fire across its authored time" % event)
		actor._physics_process(0.05)
		_expect(events.count(event) == before_count + 1, "%s fired more than once" % event)
	actor.free()


func _validate_sockets(actor: BallplayerActor) -> void:
	for socket_name in REQUIRED_SOCKETS:
		var position: Vector3 = actor.get_socket_position(socket_name)
		_expect(_is_finite_vector(position), "simulation socket %s is not finite" % socket_name)
	_expect(actor.get_socket_position("bat_tip").distance_to(actor.get_socket_position("bat_grip")) > 0.5, "bat simulation sockets are not separated")
	_expect(actor.get_socket_position("left_hand").distance_to(actor.get_socket_position("right_hand")) > 0.5, "hand simulation sockets are not separated")
	_expect(actor.get_socket_position("head").y > actor.get_socket_position("chest").y, "head socket is not above chest")
	_expect(actor.get_socket_position("feet").y < actor.get_socket_position("chest").y, "feet socket is not below chest")


func _validate_signature(packed: PackedScene, spec: Dictionary, signature: String) -> void:
	_expect(signature.begins_with("pixel-v1/"), "native signature has the wrong pipeline prefix")
	var duplicate := packed.instantiate() as BallplayerActor
	duplicate.configure(spec.duplicate(true))
	_expect(duplicate.get_generation_signature() == signature, "same actor spec produced a different signature")
	var changed_spec := spec.duplicate(true)
	changed_spec.seed = int(spec.seed) + 1
	var changed := packed.instantiate() as BallplayerActor
	changed.configure(changed_spec)
	_expect(changed.get_generation_signature() != signature, "identity seed did not affect the deterministic signature")
	duplicate.free()
	changed.free()


func _validate_palette(actor: BallplayerActor) -> void:
	var palette := actor.get_pixel_palette()
	for key in ["primary", "primary_shadow", "secondary", "accent", "pants", "pants_shadow", "skin", "skin_shadow", "hair"]:
		_expect(palette.get(key) is Color, "pixel palette entry %s is not a Color" % key)
	_expect((palette.primary as Color).is_equal_approx(Color("813348")), "configured primary palette color was lost")
	_expect((palette.secondary as Color).is_equal_approx(Color("e8dfcb")), "configured secondary palette color was lost")
	_expect(actor.get_team_mark() == "H", "team mark was not normalized")
	_expect(actor.get_player_name() == "Maya Rodriguez", "player identity name was not retained")
	_expect(actor.get_jersey_number() == 27, "jersey identity number was not retained")


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
		print("PIXIBALL_NATIVE_PIXEL_ASSET_OK model=native_pixel_sprite actions=10 fps=10 markers=7")
		quit(0)
		return
	for failure in _failures:
		push_error("PIXIBALL_NATIVE_PIXEL_ASSET: %s" % failure)
	quit(1)
