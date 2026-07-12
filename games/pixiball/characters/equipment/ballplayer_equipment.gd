@tool
class_name BallplayerEquipment
extends Node

## Selects Blender-authored role equipment and paints roster identity onto the
## jersey's authored UV surfaces. This node never creates character geometry.

const PLAYER_ROLES := ["pitcher", "batter", "hitter", "slugger", "catcher", "fielder"]
const IDENTITY_LABEL_NAMES := ["TeamMark", "JerseyNumberFront", "JerseyNameBack", "JerseyNumberBack"]
const IDENTITY_FONT := preload("res://assets/fonts/graduate/Graduate-Regular.ttf")
const IDENTITY_VIEWPORT_SIZE := Vector2i(512, 512)

const GEAR_MESHES := {
	"BattingHelmet": "Gear_BattingHelmet",
	"CatcherMask": "Gear_CatcherMask",
	"CatcherChestProtector": "Gear_CatcherChest",
	"CatcherShinGuardL": "Gear_CatcherShinL",
	"CatcherShinGuardR": "Gear_CatcherShinR",
	"UmpireMask": "Gear_UmpireMask",
	"UmpireProtector": "Gear_UmpireChest",
}

var _actor: BallplayerActor
var _pieces: Dictionary = {}
var _identity_handles: Dictionary = {}
var _identity_materials: Array[StandardMaterial3D] = []
var _front_viewport: SubViewport
var _back_viewport: SubViewport
var _mark_label: Label
var _front_number_label: Label
var _name_label: Label
var _back_number_label: Label

var _role := "fielder"
var _mark := ""
var _number := 0
var _player_name := ""
var _primary := Color("173f73")
var _secondary := Color("f1ead9")
var _accent := Color("e2b447")
var _highlighted := false


func configure(actor: Node3D, spec: Dictionary, primary: Color, secondary: Color, accent: Color) -> void:
	_clear_runtime_nodes()
	_actor = actor as BallplayerActor
	_role = String(spec.get("role", "fielder")).to_lower()
	_mark = String(spec.get("mark", "")).to_upper().left(1)
	_number = posmod(int(spec.get("number", 0)), 100)
	_player_name = _jersey_surname(String(spec.get("player_name", spec.get("name", ""))))
	_primary = primary
	_secondary = secondary
	_accent = accent

	_hide_all_gear()
	var helmet_default := _role in ["batter", "hitter", "slugger"]
	if bool(spec.get("helmet", helmet_default)):
		_show_piece("BattingHelmet")
	if _role == "catcher":
		for piece_name in ["CatcherMask", "CatcherChestProtector", "CatcherShinGuardL", "CatcherShinGuardR"]:
			_show_piece(piece_name)
	elif _role == "umpire":
		_show_piece("UmpireMask")
		_show_piece("UmpireProtector")

	if _role in PLAYER_ROLES:
		_install_identity_handles()
		_install_identity_surfaces()
		_refresh_identity()
	set_highlighted(_highlighted)


func set_palette(primary: Color, secondary: Color, accent: Color) -> void:
	_primary = primary
	_secondary = secondary
	_accent = accent
	_refresh_identity_style()
	_request_identity_redraw()


func set_identity(mark: String, number: int, player_name := "") -> void:
	_mark = mark.to_upper().left(1)
	_number = posmod(number, 100)
	_player_name = _jersey_surname(player_name)
	_refresh_identity()


func set_highlighted(enabled: bool) -> void:
	_highlighted = enabled
	for material in _identity_materials:
		material.emission_enabled = enabled
		material.emission = Color.WHITE
		material.emission_energy_multiplier = 0.24 if enabled else 0.0


func get_profile() -> Dictionary:
	return {
		"role": _role,
		"mark": _mark,
		"number": _number,
		"player_name": _player_name,
		"pieces": PackedStringArray(_pieces.keys()),
	}


func get_piece(piece_name: String) -> Node3D:
	return _pieces.get(piece_name) as Node3D


## A left-handed action mirrors the complete imported model. Flipping only the
## identity materials' U coordinate keeps names and numbers readable while the
## authored skinned surfaces continue to follow the jersey.
func sync_identity_orientation(mirrored := false) -> void:
	for material in _identity_materials:
		material.uv1_scale = Vector3(-1.0 if mirrored else 1.0, 1.0, 1.0)
		material.uv1_offset = Vector3(1.0 if mirrored else 0.0, 0.0, 0.0)


func _clear_runtime_nodes() -> void:
	for child in get_children():
		child.free()
	_pieces.clear()
	_identity_handles.clear()
	_identity_materials.clear()
	_front_viewport = null
	_back_viewport = null
	_mark_label = null
	_front_number_label = null
	_name_label = null
	_back_number_label = null


func _hide_all_gear() -> void:
	if not is_instance_valid(_actor):
		return
	for mesh_name in GEAR_MESHES.values():
		var mesh := _actor.get_imported_mesh(String(mesh_name))
		if is_instance_valid(mesh):
			mesh.visible = false


func _show_piece(piece_name: String) -> void:
	if not is_instance_valid(_actor) or not GEAR_MESHES.has(piece_name):
		return
	var mesh := _actor.get_imported_mesh(String(GEAR_MESHES[piece_name]))
	if not is_instance_valid(mesh):
		push_warning("BallplayerEquipment: Blender mesh '%s' is missing" % GEAR_MESHES[piece_name])
		return
	mesh.visible = true
	_pieces[piece_name] = mesh


func _install_identity_handles() -> void:
	for piece_name in IDENTITY_LABEL_NAMES:
		var handle := Node3D.new()
		handle.name = piece_name
		handle.set_meta("identity_style", "screen_printed_viewport_texture")
		add_child(handle)
		_identity_handles[piece_name] = handle
		_pieces[piece_name] = handle


func _install_identity_surfaces() -> void:
	if not is_instance_valid(_actor):
		return
	_front_viewport = _make_viewport("JerseyIdentityFrontViewport")
	_back_viewport = _make_viewport("JerseyIdentityBackViewport")

	var front_root := Control.new()
	front_root.name = "FrontIdentityCanvas"
	_front_viewport.add_child(front_root)
	front_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_mark_label = _make_label(front_root, "TeamMarkLabel", Rect2(12, 146, 220, 250), 148, 14)
	_front_number_label = _make_label(front_root, "FrontNumberLabel", Rect2(270, 146, 230, 250), 148, 14)

	var back_root := Control.new()
	back_root.name = "BackIdentityCanvas"
	_back_viewport.add_child(back_root)
	back_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_name_label = _make_label(back_root, "SurnameLabel", Rect2(16, 34, 480, 108), 66, 10)
	_back_number_label = _make_label(back_root, "BackNumberLabel", Rect2(52, 116, 408, 382), 282, 24)

	var front_mesh := _actor.get_imported_mesh("JerseyIdentityFront")
	var back_mesh := _actor.get_imported_mesh("JerseyIdentityBack")
	if not is_instance_valid(front_mesh) or not is_instance_valid(back_mesh):
		push_warning("BallplayerEquipment: Blender jersey identity surfaces are missing")
		return
	front_mesh.visible = true
	back_mesh.visible = true
	var front_material := _identity_material("JerseyIdentityFrontRuntime", _front_viewport.get_texture())
	var back_material := _identity_material("JerseyIdentityBackRuntime", _back_viewport.get_texture())
	front_mesh.set_surface_override_material(0, front_material)
	back_mesh.set_surface_override_material(0, back_material)
	_identity_materials.assign([front_material, back_material])


func _make_viewport(viewport_name: String) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = viewport_name
	viewport.size = IDENTITY_VIEWPORT_SIZE
	viewport.transparent_bg = true
	viewport.disable_3d = true
	viewport.gui_disable_input = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	return viewport


func _make_label(parent: Control, label_name: String, bounds: Rect2, font_size: int, outline_size: int) -> Label:
	var label := Label.new()
	label.name = label_name
	label.position = bounds.position
	label.size = bounds.size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	label.add_theme_font_override("font", IDENTITY_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_constant_override("outline_size", outline_size)
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 4)
	parent.add_child(label)
	return label


func _identity_material(material_name: String, texture: Texture2D) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.resource_name = material_name
	material.resource_local_to_scene = true
	material.albedo_texture = texture
	material.albedo_color = Color.WHITE
	material.roughness = 0.74
	material.metallic = 0.0
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	material.cull_mode = BaseMaterial3D.CULL_BACK
	return material


func _refresh_identity() -> void:
	if is_instance_valid(_mark_label):
		_mark_label.text = _mark
	if is_instance_valid(_front_number_label):
		_front_number_label.text = str(_number)
	if is_instance_valid(_name_label):
		_name_label.text = _player_name
		var name_size := 66 if _player_name.length() <= 8 else (56 if _player_name.length() <= 11 else 48)
		_name_label.add_theme_font_size_override("font_size", name_size)
	if is_instance_valid(_back_number_label):
		_back_number_label.text = str(_number)
	_set_handle_text("TeamMark", _mark, "front")
	_set_handle_text("JerseyNumberFront", str(_number), "front")
	_set_handle_text("JerseyNameBack", _player_name, "back")
	_set_handle_text("JerseyNumberBack", str(_number), "back")
	_refresh_identity_style()
	_request_identity_redraw()


func _refresh_identity_style() -> void:
	var fill := _accent.lightened(0.28)
	var outline := _primary.darkened(0.30)
	var shadow := _primary.darkened(0.68)
	shadow.a = 0.72
	for label in [_mark_label, _front_number_label, _name_label, _back_number_label]:
		if not is_instance_valid(label):
			continue
		label.add_theme_color_override("font_color", fill)
		label.add_theme_color_override("font_outline_color", outline)
		label.add_theme_color_override("font_shadow_color", shadow)


func _request_identity_redraw() -> void:
	if is_instance_valid(_front_viewport):
		_front_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	if is_instance_valid(_back_viewport):
		_back_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _set_handle_text(piece_name: String, text: String, surface: String) -> void:
	var handle := _identity_handles.get(piece_name) as Node3D
	if not is_instance_valid(handle):
		return
	handle.set_meta("identity_text", text)
	handle.set_meta("identity_surface", surface)


func _jersey_surname(value: String) -> String:
	var words := value.to_upper().strip_edges().split(" ", false)
	if words.is_empty():
		return ""
	return String(words[words.size() - 1]).left(14)
