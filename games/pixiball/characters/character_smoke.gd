extends SceneTree

const BALLPLAYER_SCENE = preload("res://characters/ballplayer_actor.tscn")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	stage.name = "CharacterSmokeStage"
	root.add_child(stage)

	var specs := [
		{"seed": 44, "role": "pitcher", "number": 34, "throws": "right"},
		{"seed": 91, "role": "batter", "number": 7, "bats": "left", "bat": true},
		{"seed": 151, "role": "catcher", "number": 12, "throws": "left"},
	]
	var actions := [
		"idle", "field_ready", "run", "pitch", "swing", "catch",
		"field_throw", "throw", "celebrate", "slide",
	]
	var signatures: Array[String] = []
	var observed_markers: Array[String] = []
	for index in range(specs.size()):
		var player := BALLPLAYER_SCENE.instantiate() as BallplayerActor
		stage.add_child(player)
		player.action_marker.connect(func(action_name: String, marker_name: String) -> void:
			observed_markers.append("%s:%s" % [action_name, marker_name])
		)
		player.position.x = float(index) * 2.0
		player.configure(specs[index])
		_expect(not player.is_using_fallback(), "player %d did not load the Blender model" % index)
		_expect(player.get_model_kind() == "rigged_glb", "player %d did not load the rigged GLB" % index)
		player.set_facing(Vector3(0.4, 0.0, -1.0))
		player.set_motion(Vector3(0.0, 0.0, -3.2))
		player.set_highlighted(index == 1)
		signatures.append(player.get_generation_signature())
		_expect(player.get_child_count() > 0, "player %d generated no model" % index)
		for socket_name in ["head", "chest", "left_hand", "right_hand", "throw_hand", "left_foot", "right_foot", "feet"]:
			_expect(_is_finite_vector(player.get_socket_position(socket_name)), "socket %s is not finite" % socket_name)
		if String(specs[index].role) != "batter":
			_expect(player.get_socket_position("catch").distance_to(player.global_position) > 0.1, "glove catch socket was not built")
		if String(specs[index].role) == "batter":
			_expect(player.get_socket_position("bat_tip").distance_to(player.get_socket_position("bat_grip")) > 0.5, "bat sockets are not separated")
		for action in actions:
			player.play_action(action)
			for tick in range(4):
				player._physics_process(1.0 / 60.0)
			_expect(player.get_current_action() == action or action == "idle", "action %s did not activate" % action)
		player.play_action("pitch")
		var imported_player := _first_animation_player(player)
		_expect(imported_player != null, "player %d has no imported AnimationPlayer" % index)
		if imported_player != null:
			imported_player.advance(0.90)
			player._physics_process(0.90)
			player.play_action("field_throw")
			imported_player.advance(0.60)
			player._physics_process(0.60)
			player.play_action("celebrate")
			imported_player.advance(0.86)
			player._physics_process(0.86)
			player.play_action("slide")
			imported_player.advance(0.78)
			player._physics_process(0.78)

	var duplicate := BALLPLAYER_SCENE.instantiate() as BallplayerActor
	stage.add_child(duplicate)
	duplicate.configure(specs[0])
	_expect(duplicate.get_generation_signature() == signatures[0], "same spec produced a different signature")
	_expect("pitch:ball_release" in observed_markers, "pitch release marker was not emitted")
	_expect("field_throw:ball_release" in observed_markers, "field throw release marker was not emitted")
	_expect("celebrate:celebration_peak" in observed_markers, "celebration peak marker was not emitted")
	_expect("slide:base_contact" in observed_markers, "slide base-contact marker was not emitted")

	if _failures.is_empty():
		print("PIXIBALL_CHARACTER_SMOKE_OK players=%d actions=%d" % [specs.size(), actions.size()])
		quit(0)
	else:
		for failure in _failures:
			push_error("PIXIBALL_CHARACTER_SMOKE: %s" % failure)
		quit(1)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _first_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _first_animation_player(child)
		if found != null:
			return found
	return null
