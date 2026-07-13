extends SceneTree

const BALLPLAYER_SCENE := preload("res://characters/ballplayer_actor.tscn")
const ALL_LAYERS := [
	"TeamMark", "JerseyNumberFront", "BattingHelmet", "Bat",
	"CatcherMask", "CatcherChestProtector", "CatcherShinGuardL",
	"CatcherShinGuardR", "UmpireMask", "UmpireProtector", "Glove",
]
const ROLE_LAYERS := {
	"batter": ["TeamMark", "JerseyNumberFront", "BattingHelmet", "Bat"],
	"catcher": ["TeamMark", "JerseyNumberFront", "CatcherMask", "CatcherChestProtector", "CatcherShinGuardL", "CatcherShinGuardR", "Glove"],
	"umpire": ["UmpireMask", "UmpireProtector"],
	"pitcher": ["TeamMark", "JerseyNumberFront", "Glove"],
	"fielder": ["TeamMark", "JerseyNumberFront", "Glove"],
}

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pixel_scene := Node2D.new()
	pixel_scene.name = "TemporaryEquipmentPixelScene"
	root.add_child(pixel_scene)
	pixel_scene.add_to_group("pixiball_pixel_scene")

	var specs := {
		"batter": _spec("batter", 11, "H", 27, "Maya Rodriguez", Color("813348"), Color("e8dfcb"), Color("dfad3e")),
		"catcher": _spec("catcher", 22, "C", 8, "Jun Park", Color("185f73"), Color("f4e8cf"), Color("e45858")),
		"umpire": _spec("umpire", 33, "U", 0, "Crew Chief", Color("252f3d"), Color("d8e2e8"), Color("84a0af")),
		"pitcher": _spec("pitcher", 44, "P", 41, "Amara Stone", Color("245347"), Color("f4f0dd"), Color("e1a72f")),
		"fielder": _spec("fielder", 55, "F", 12, "Niko Bell", Color("5d275d"), Color("efe5d2"), Color("55c9b8")),
	}
	var actors: Dictionary = {}
	for role in ROLE_LAYERS:
		var actor := BALLPLAYER_SCENE.instantiate() as BallplayerActor
		actor.name = "%sActor" % String(role).capitalize()
		actor.configure(specs[role])
		actors[role] = actor
		root.add_child(actor)
	await process_frame
	await process_frame

	for role in ROLE_LAYERS:
		var actor: BallplayerActor = actors[role]
		_validate_profile(actor, String(role), ROLE_LAYERS[role])
		_validate_attachment(actor, pixel_scene)
		_expect(_count_3d_nodes(actor) == 0, "%s actor contains a 3D descendant" % role)

	var batter: BallplayerActor = actors.batter
	var original_signature := batter.get_generation_signature()
	var duplicate := BALLPLAYER_SCENE.instantiate() as BallplayerActor
	duplicate.configure(specs.batter.duplicate(true))
	_expect(duplicate.get_generation_signature() == original_signature, "same equipment spec produced a different signature")
	_expect((duplicate.get_pixel_palette().skin as Color).is_equal_approx(batter.get_pixel_palette().skin), "same seed produced a different skin palette")
	_expect((duplicate.get_pixel_palette().hair as Color).is_equal_approx(batter.get_pixel_palette().hair), "same seed produced a different hair palette")
	duplicate.free()

	_validate_recoloring(batter)
	_validate_identity(batter)
	_validate_umpire_identity(actors.umpire)

	_expect(_count_3d_nodes(pixel_scene) == 0, "equipment pixel scene contains a 3D descendant")
	for actor_value in actors.values():
		(actor_value as BallplayerActor).queue_free()
	await process_frame
	pixel_scene.queue_free()
	await process_frame
	_finish()


func _spec(role: String, seed_value: int, mark: String, number: int, player_name: String, primary: Color, secondary: Color, accent: Color) -> Dictionary:
	return {
		"role": role,
		"seed": seed_value,
		"mark": mark,
		"number": number,
		"player_name": player_name,
		"throws": "right",
		"bats": "left" if role == "batter" else "right",
		"primary_color": primary,
		"secondary_color": secondary,
		"accent_color": accent,
		"pants_color": Color("eee9dc"),
	}


func _validate_profile(actor: BallplayerActor, role: String, expected_layers: Array) -> void:
	var profile := actor.get_equipment_profile()
	_expect(String(profile.get("role", "")) == role, "%s profile reported the wrong role" % role)
	_expect(String(profile.get("pipeline", "")) == "native_pixel_layers", "%s profile is not using native pixel layers" % role)
	var layers: PackedStringArray = profile.get("pieces", PackedStringArray())
	_expect(layers.size() == expected_layers.size(), "%s profile layer count changed: %d" % [role, layers.size()])
	for layer in expected_layers:
		_expect(String(layer) in layers, "%s profile is missing layer %s" % [role, layer])
		_expect(actor.get_equipment_piece(String(layer)) == actor.get_pixel_sprite(), "%s layer %s is not owned by the pixel presenter" % [role, layer])
	for layer in ALL_LAYERS:
		if layer not in expected_layers:
			_expect(actor.get_equipment_piece(layer) == null, "%s unexpectedly exposes layer %s" % [role, layer])
	_expect(bool(profile.get("helmet", false)) == (role == "batter"), "%s helmet profile flag is wrong" % role)
	_expect(bool(profile.get("bat", false)) == (role == "batter"), "%s bat profile flag is wrong" % role)
	_expect(bool(profile.get("glove", false)) == (role in ["pitcher", "catcher", "fielder"]), "%s glove profile flag is wrong" % role)


func _validate_attachment(actor: BallplayerActor, pixel_scene: Node2D) -> void:
	var sprite := actor.get_pixel_sprite()
	_expect(is_instance_valid(sprite), "%s did not attach a pixel presenter" % actor.get_role())
	if is_instance_valid(sprite):
		_expect(sprite is Node2D, "%s presenter is not a Node2D" % actor.get_role())
		_expect(sprite.get_parent() == pixel_scene, "%s presenter is outside pixiball_pixel_scene" % actor.get_role())
		_expect(sprite.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "%s presenter is not nearest-filtered" % actor.get_role())


func _validate_recoloring(actor: BallplayerActor) -> void:
	var primary := Color("146c94")
	var secondary := Color("f6f1db")
	var accent := Color("ffb703")
	var pants := Color("264653")
	var before := actor.get_pixel_palette()
	actor.set_uniform_colors(primary, secondary, accent, pants)
	var after := actor.get_pixel_palette()
	_expect((after.primary as Color).is_equal_approx(primary), "primary palette recolor failed")
	_expect((after.secondary as Color).is_equal_approx(secondary), "secondary palette recolor failed")
	_expect((after.accent as Color).is_equal_approx(accent), "accent palette recolor failed")
	_expect((after.pants as Color).is_equal_approx(pants), "pants palette recolor failed")
	_expect(not (after.primary_shadow as Color).is_equal_approx(before.primary_shadow), "primary shadow did not follow recoloring")
	_expect(not (after.pants_shadow as Color).is_equal_approx(before.pants_shadow), "pants shadow did not follow recoloring")
	actor.set_highlighted(true)
	_expect(bool(actor.get_pixel_pose().highlighted), "highlight state did not reach the pixel pose")
	actor.set_highlighted(false)
	_expect(not bool(actor.get_pixel_pose().highlighted), "highlight state did not clear")


func _validate_identity(actor: BallplayerActor) -> void:
	_expect(actor.get_team_mark() == "H", "configured team mark was not retained")
	_expect(actor.get_jersey_number() == 27, "configured jersey number was not retained")
	_expect(actor.get_player_name() == "Maya Rodriguez", "configured player name was not retained")
	actor.set_team_mark("river")
	actor.set_jersey_number(68)
	actor.set_player_name("  River Stone  ")
	_expect(actor.get_team_mark() == "R", "live team mark was not normalized")
	_expect(actor.get_jersey_number() == 68, "live jersey number update failed")
	_expect(actor.get_player_name() == "River Stone", "live player name was not normalized")
	var layers: PackedStringArray = actor.get_equipment_profile().pieces
	_expect("TeamMark" in layers and "JerseyNumberFront" in layers, "player identity layers disappeared")


func _validate_umpire_identity(actor: BallplayerActor) -> void:
	var layers: PackedStringArray = actor.get_equipment_profile().pieces
	_expect("TeamMark" not in layers, "umpire unexpectedly exposes a team-mark layer")
	_expect("JerseyNumberFront" not in layers, "umpire unexpectedly exposes a jersey-number layer")


func _count_3d_nodes(node: Node) -> int:
	var count := 1 if node is Node3D else 0
	for child in node.get_children():
		count += _count_3d_nodes(child)
	return count


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PIXIBALL_NATIVE_PIXEL_EQUIPMENT_OK roles=5 layers=verified palette=live identity=live")
		quit(0)
		return
	for failure in _failures:
		push_error("PIXIBALL_NATIVE_PIXEL_EQUIPMENT: %s" % failure)
	quit(1)
