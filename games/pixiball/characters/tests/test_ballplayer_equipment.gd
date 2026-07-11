extends SceneTree

const BALLPLAYER_SCENE = preload("res://characters/ballplayer_actor.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var batter := _actor({
		"seed": 7,
		"role": "batter",
		"number": 7,
		"mark": "H",
		"bats": "left",
		"helmet": true,
		"bat": true,
		"glove": false,
		"primary_color": Color("813348"),
		"secondary_color": Color("e8dfcb"),
		"accent_color": Color("dfad3e"),
	})
	await process_frame
	_expect_pieces(batter, ["BattingHelmet", "TeamMark", "JerseyNumberFront", "JerseyNumberBack"])
	_expect(_label_text(batter, "TeamMark") == "H", "batter team mark was not installed")
	_expect(_label_text(batter, "JerseyNumberFront") == "7", "one-digit jersey number was not preserved")
	_expect(_mesh_visible(batter, "Bat_Skinned"), "batter lost imported bat visibility")
	_expect(not _mesh_visible(batter, "Glove_Skinned"), "batter unexpectedly shows imported glove")
	_expect(not _mesh_visible(batter, "Cap_Skinned"), "batting helmet did not replace imported cap")
	_expect(_piece_is_bone_attached(batter, "BattingHelmet"), "batting helmet is not bone-attached")

	var recolor := Color("245ca8")
	batter.set_uniform_colors(recolor, Color("f5eee0"), Color("e5a333"))
	_expect(_piece_material_color(batter, "BattingHelmet", "Equipment_Primary").is_equal_approx(recolor), "helmet did not follow the team palette")
	batter.set_team_mark("R")
	_expect(_label_text(batter, "TeamMark") == "R", "live team-mark update did not reach equipment")

	var catcher := _actor({
		"seed": 12,
		"role": "catcher",
		"number": 12,
		"mark": "C",
		"primary_color": Color("17604e"),
		"secondary_color": Color("e7debc"),
		"accent_color": Color("e46c35"),
	})
	await process_frame
	_expect_pieces(catcher, ["CatcherMask", "CatcherChestProtector", "CatcherShinGuardL", "CatcherShinGuardR", "TeamMark", "JerseyNumberFront", "JerseyNumberBack"])
	_expect(_label_text(catcher, "JerseyNumberBack") == "12", "two-digit jersey number was not preserved")
	_expect(_mesh_visible(catcher, "Glove_Skinned"), "catcher lost imported mitt visibility")
	_expect(not _mesh_visible(catcher, "Bat_Skinned"), "catcher unexpectedly shows imported bat")
	for piece_name in ["CatcherMask", "CatcherChestProtector", "CatcherShinGuardL", "CatcherShinGuardR"]:
		_expect(_piece_is_bone_attached(catcher, piece_name), "%s is not bone-attached" % piece_name)

	var mask := catcher.get_equipment_piece("CatcherMask")
	var mask_local := mask.transform
	var mask_before := mask.global_transform
	catcher.play_action("catch")
	var catcher_player := _first_animation_player(catcher)
	_expect(catcher_player != null, "catcher has no imported AnimationPlayer")
	if catcher_player != null:
		catcher_player.advance(0.42)
		catcher._physics_process(0.42)
	await process_frame
	_expect(mask.transform.is_equal_approx(mask_local), "catcher mask drifted from its attachment")
	_expect(not mask.global_transform.is_equal_approx(mask_before), "catcher mask did not follow the animated head")

	var umpire := _actor({
		"seed": 9001,
		"role": "umpire",
		"number": 0,
		"mark": "",
		"primary_color": Color("151922"),
		"secondary_color": Color("252c38"),
		"accent_color": Color("d9e2ea"),
		"glove": false,
	})
	await process_frame
	_expect_pieces(umpire, ["UmpireMask", "UmpireProtector"])
	_expect(umpire.get_equipment_piece("TeamMark") == null, "umpire unexpectedly received player identity")
	_expect(not _mesh_visible(umpire, "Bat_Skinned"), "umpire unexpectedly shows imported bat")
	_expect(not _mesh_visible(umpire, "Glove_Skinned"), "umpire unexpectedly shows imported glove")
	_expect(not _mesh_visible(umpire, "Cap_Skinned"), "umpire mask did not replace imported cap")

	var fielder := _actor({"seed": 18, "role": "fielder", "number": 18, "mark": "F"})
	await process_frame
	_expect_pieces(fielder, ["TeamMark", "JerseyNumberFront", "JerseyNumberBack"])
	_expect(fielder.get_equipment_piece("BattingHelmet") == null, "fielder unexpectedly received a helmet")
	_expect(fielder.get_equipment_piece("CatcherMask") == null, "fielder unexpectedly received catcher gear")
	_expect(_mesh_visible(fielder, "Glove_Skinned"), "fielder lost imported glove visibility")
	_expect(_mesh_visible(fielder, "Cap_Skinned"), "fielder lost imported cap visibility")

	if _failures.is_empty():
		print("PIXIBALL_EQUIPMENT_OK batter=helmet catcher=4 umpire=2 identity=mark+number animated=verified")
		quit(0)
		return
	for failure in _failures:
		push_error("PIXIBALL_EQUIPMENT: %s" % failure)
	quit(1)


func _actor(spec: Dictionary) -> BallplayerActor:
	var actor := BALLPLAYER_SCENE.instantiate() as BallplayerActor
	actor.configure(spec)
	root.add_child(actor)
	return actor


func _expect_pieces(actor: BallplayerActor, expected: Array[String]) -> void:
	var profile := actor.get_equipment_profile()
	var pieces: PackedStringArray = profile.get("pieces", PackedStringArray())
	for piece_name in expected:
		_expect(piece_name in pieces, "%s is missing %s" % [actor.name, piece_name])


func _label_text(actor: BallplayerActor, piece_name: String) -> String:
	var label := actor.get_equipment_piece(piece_name) as Label3D
	return label.text if is_instance_valid(label) else ""


func _piece_is_bone_attached(actor: BallplayerActor, piece_name: String) -> bool:
	var piece := actor.get_equipment_piece(piece_name)
	return is_instance_valid(piece) and piece.get_parent() is BoneAttachment3D


func _piece_material_color(actor: BallplayerActor, piece_name: String, material_name: String) -> Color:
	var piece := actor.get_equipment_piece(piece_name)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(piece, meshes)
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.mesh.surface_get_material(surface) as BaseMaterial3D
			if material != null and material.resource_name == material_name:
				return material.albedo_color
	return Color.TRANSPARENT


func _mesh_visible(actor: BallplayerActor, mesh_name: String) -> bool:
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(actor, meshes)
	for mesh_instance in meshes:
		if mesh_instance.name == mesh_name:
			return mesh_instance.visible
	return false


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node == null:
		return
	if node is MeshInstance3D:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, output)


func _first_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _first_animation_player(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
