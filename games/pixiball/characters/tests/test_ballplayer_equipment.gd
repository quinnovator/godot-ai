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
		"player_name": "Maya Okafor",
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
	_expect_pieces(batter, ["BattingHelmet", "TeamMark", "JerseyNumberFront", "JerseyNameBack", "JerseyNumberBack"])
	_expect(_label_text(batter, "TeamMark") == "H", "batter team mark was not installed")
	_expect(_label_text(batter, "JerseyNumberFront") == "7", "one-digit jersey number was not preserved")
	_expect(_label_text(batter, "JerseyNumberBack") == "7", "one-digit back number was not preserved")
	_expect(_label_text(batter, "JerseyNameBack") == "OKAFOR", "surname was not extracted for the back nameplate")
	_expect_identity_label(batter, "TeamMark", Vector3.FORWARD)
	_expect_identity_label(batter, "JerseyNumberFront", Vector3.FORWARD, 0.085, 0.105)
	_expect_identity_label(batter, "JerseyNumberBack", Vector3.BACK, 0.18, 0.21)
	_expect_identity_label(batter, "JerseyNameBack", Vector3.BACK, 0.04, 0.06)
	_expect(_mesh_visible(batter, "Bat_Skinned"), "batter lost imported bat visibility")
	_expect(not _mesh_visible(batter, "Glove_Skinned"), "batter unexpectedly shows imported glove")
	_expect(not _mesh_visible(batter, "Cap_Skinned"), "batting helmet did not replace imported cap")
	_expect(_piece_is_bone_attached(batter, "BattingHelmet"), "batting helmet is not bone-attached")

	var recolor := Color("245ca8")
	batter.set_uniform_colors(recolor, Color("f5eee0"), Color("e5a333"))
	_expect(_piece_material_color(batter, "BattingHelmet", "Equipment_Primary").is_equal_approx(recolor), "helmet did not follow the team palette")
	batter.set_team_mark("R")
	_expect(_label_text(batter, "TeamMark") == "R", "live team-mark update did not reach equipment")
	batter.set_player_name("Nia Rodriguez")
	batter.set_jersey_number(27)
	_expect(_label_text(batter, "JerseyNameBack") == "RODRIGUEZ", "live player-name update did not reach equipment")
	_expect(_label_text(batter, "JerseyNumberBack") == "27", "live jersey-number update did not reach equipment")

	var catcher := _actor({
		"seed": 12,
		"role": "catcher",
		"number": 12,
		"player_name": "Luis Chen",
		"mark": "C",
		"primary_color": Color("17604e"),
		"secondary_color": Color("e7debc"),
		"accent_color": Color("e46c35"),
	})
	await process_frame
	_expect_pieces(catcher, ["CatcherMask", "CatcherChestProtector", "CatcherShinGuardL", "CatcherShinGuardR", "TeamMark", "JerseyNumberFront", "JerseyNameBack", "JerseyNumberBack"])
	_expect(_label_text(catcher, "JerseyNumberFront") == "12", "two-digit front number was not preserved")
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

	var fielder := _actor({"seed": 18, "role": "fielder", "number": 18, "mark": "F", "player_name": "Ari Vega"})
	await process_frame
	_expect_pieces(fielder, ["TeamMark", "JerseyNumberFront", "JerseyNameBack", "JerseyNumberBack"])
	_expect(fielder.get_equipment_piece("BattingHelmet") == null, "fielder unexpectedly received a helmet")
	_expect(fielder.get_equipment_piece("CatcherMask") == null, "fielder unexpectedly received catcher gear")
	_expect(_mesh_visible(fielder, "Glove_Skinned"), "fielder lost imported glove visibility")
	_expect(_mesh_visible(fielder, "Cap_Skinned"), "fielder lost imported cap visibility")

	# Batters can bat and throw from opposite sides. Those actions change the
	# imported model root's X sign, but must never reflect attached identity.
	var switch_hitter := _actor({
		"seed": 42,
		"role": "batter",
		"number": 42,
		"player_name": "Sam Rivera",
		"mark": "S",
		"bats": "left",
		"throws": "right",
	})
	await process_frame
	var switch_root := switch_hitter.get_node_or_null("RiggedBallplayer") as Node3D
	_expect(is_instance_valid(switch_root) and switch_root.scale.x < 0.0, "mixed-hand batter did not start in its left batting orientation")
	_expect_identity_handedness(switch_hitter, "left-handed idle")
	switch_hitter.play_action("field_throw")
	_expect(is_instance_valid(switch_root) and switch_root.scale.x > 0.0, "mixed-hand batter did not enter its right throwing orientation")
	_expect_identity_handedness(switch_hitter, "right-handed throw")
	switch_hitter.play_action("swing")
	_expect(is_instance_valid(switch_root) and switch_root.scale.x < 0.0, "mixed-hand batter did not restore its left batting orientation")
	_expect_identity_handedness(switch_hitter, "left-handed swing")
	_expect(_label_text(switch_hitter, "JerseyNumberFront") == "42", "hand switch changed the front jersey number")
	_expect(_label_text(switch_hitter, "JerseyNumberBack") == "42", "hand switch changed the back jersey number")
	_expect(_label_text(switch_hitter, "JerseyNameBack") == "RIVERA", "hand switch changed the back jersey name")

	if _failures.is_empty():
		print("PIXIBALL_EQUIPMENT_OK batter=helmet catcher=4 umpire=2 identity=mark+name+number vector_twill=verified")
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
	var piece := actor.get_equipment_piece(piece_name) as Node3D
	if not is_instance_valid(piece):
		return ""
	return String(piece.get_meta("identity_text", ""))


func _expect_identity_label(actor: BallplayerActor, piece_name: String, _outward: Vector3, minimum_height := 0.0, maximum_height := INF) -> void:
	var piece := actor.get_equipment_piece(piece_name) as Node3D
	_expect(is_instance_valid(piece), "%s identity lettering is missing" % piece_name)
	if not is_instance_valid(piece):
		return
	_expect(String(piece.get_meta("identity_style", "")) == "graduate_vector_twill", "%s did not use the vector twill system" % piece_name)
	var meshes: Array[MeshInstance3D] = []
	_collect_meshes(piece, meshes)
	_expect(meshes.size() >= 2, "%s is not layered tackle-twill (border + fill)" % piece_name)
	var has_border := false
	var has_fill := false
	for mesh_instance in meshes:
		has_border = has_border or mesh_instance.name == "TwillBorder"
		has_fill = has_fill or mesh_instance.name == "TwillFill"
		if mesh_instance.mesh != null:
			var material := mesh_instance.mesh.surface_get_material(0) as StandardMaterial3D
			_expect(material != null and material.normal_texture != null, "%s twill layer lacks the stitched fabric response" % piece_name)
	_expect(has_border and has_fill, "%s lacks a fill or contrast border layer" % piece_name)
	_expect(piece.global_transform.basis.determinant() > 0.0, "%s basis reflects its lettering" % piece_name)
	var height := float(piece.get_meta("identity_height", 0.0))
	_expect(height >= minimum_height and height <= maximum_height, "%s height %.4fm is outside %.2f-%.2fm" % [piece_name, height, minimum_height, maximum_height])


func _expect_identity_handedness(actor: BallplayerActor, context: String) -> void:
	for piece_name in ["TeamMark", "JerseyNumberFront", "JerseyNameBack", "JerseyNumberBack"]:
		var piece := actor.get_equipment_piece(piece_name) as Node3D
		_expect(is_instance_valid(piece), "%s lost %s" % [context, piece_name])
		if is_instance_valid(piece):
			_expect(piece.global_transform.basis.determinant() > 0.0, "%s reflected %s" % [context, piece_name])


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
