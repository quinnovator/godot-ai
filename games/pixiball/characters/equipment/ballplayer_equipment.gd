@tool
class_name BallplayerEquipment
extends Node

## Modular role and identity presentation for the production ballplayer.
##
## Every top-level piece is authored in the actor's neutral coordinate space,
## then reparented to a semantic BoneAttachment3D while preserving its global
## transform. This keeps the geometry independent from GLB hierarchy details
## while making masks, protectors, labels, and shin guards follow animation.

const PLAYER_ROLES := ["pitcher", "batter", "hitter", "slugger", "catcher", "fielder"]

var _pieces: Dictionary = {}
var _materials: Dictionary = {}
var _role := "fielder"
var _mark := ""
var _number := 0
var _primary := Color("173f73")
var _secondary := Color("f1ead9")
var _accent := Color("e2b447")
var _highlighted := false


func configure(actor: Node3D, spec: Dictionary, primary: Color, secondary: Color, accent: Color) -> void:
	_clear_pieces()
	_role = String(spec.get("role", "fielder")).to_lower()
	_mark = String(spec.get("mark", "")).to_upper().left(1)
	_number = posmod(int(spec.get("number", 0)), 100)
	_primary = primary
	_secondary = secondary
	_accent = accent
	_build_materials()

	var helmet_default := _role in ["batter", "hitter", "slugger"]
	if bool(spec.get("helmet", helmet_default)):
		_install_batting_helmet(actor, String(spec.get("bats", "right")))
	if _role == "catcher":
		_install_catcher_gear(actor)
	elif _role == "umpire":
		_install_umpire_gear(actor)
	if _role in PLAYER_ROLES:
		_install_identity(actor)
	set_highlighted(_highlighted)


func set_palette(primary: Color, secondary: Color, accent: Color) -> void:
	_primary = primary
	_secondary = secondary
	_accent = accent
	_set_material_color("primary", primary)
	_set_material_color("secondary", secondary)
	_set_material_color("accent", accent)
	_set_material_color("primary_dark", primary.darkened(0.42))
	var mark := _pieces.get("TeamMark") as Label3D
	if is_instance_valid(mark):
		mark.modulate = accent
		mark.outline_modulate = primary.darkened(0.55)
	for piece_name in ["JerseyNumberFront", "JerseyNumberBack"]:
		var label := _pieces.get(piece_name) as Label3D
		if is_instance_valid(label):
			label.modulate = secondary
			label.outline_modulate = primary.darkened(0.55)
	if _highlighted:
		set_highlighted(true)


func set_identity(mark: String, number: int) -> void:
	_mark = mark.to_upper().left(1)
	_number = posmod(number, 100)
	var mark_label := _pieces.get("TeamMark") as Label3D
	if is_instance_valid(mark_label):
		mark_label.text = _mark
	var number_text := str(_number)
	for piece_name in ["JerseyNumberFront", "JerseyNumberBack"]:
		var label := _pieces.get(piece_name) as Label3D
		if is_instance_valid(label):
			label.text = number_text


func set_highlighted(enabled: bool) -> void:
	_highlighted = enabled
	for material_value in _materials.values():
		var material := material_value as StandardMaterial3D
		if material == null:
			continue
		material.emission_enabled = enabled
		material.emission = material.albedo_color
		material.emission_energy_multiplier = 0.26 if enabled else 0.0


func get_profile() -> Dictionary:
	return {
		"role": _role,
		"mark": _mark,
		"number": _number,
		"pieces": PackedStringArray(_pieces.keys()),
	}


func get_piece(piece_name: String) -> Node3D:
	return _pieces.get(piece_name) as Node3D


func _clear_pieces() -> void:
	for value in _pieces.values():
		var node := value as Node
		if is_instance_valid(node):
			node.free()
	_pieces.clear()
	_materials.clear()


func _build_materials() -> void:
	_materials = {
		"primary": _material("Equipment_Primary", _primary, 0.67),
		"primary_dark": _material("Equipment_PrimaryDark", _primary.darkened(0.42), 0.73),
		"secondary": _material("Equipment_Secondary", _secondary, 0.72),
		"accent": _material("Equipment_Accent", _accent, 0.58),
		"padding": _material("Equipment_Padding", Color("151922"), 0.88),
		"metal": _material("Equipment_Metal", Color("84909a"), 0.34, 0.72),
		"umpire": _material("Equipment_Umpire", Color("151922"), 0.79),
	}


func _material(name: String, color: Color, roughness: float, metallic := 0.0) -> StandardMaterial3D:
	var value := StandardMaterial3D.new()
	value.resource_name = name
	value.albedo_color = color
	value.roughness = roughness
	value.metallic = metallic
	return value


func _set_material_color(key: String, color: Color) -> void:
	var material := _materials.get(key) as StandardMaterial3D
	if material != null:
		material.albedo_color = color


func _install_batting_helmet(actor: Node3D, batting_side: String) -> void:
	var root := Node3D.new()
	root.name = "BattingHelmet"
	_sphere(root, "HelmetDome", 0.184, 0.235, Vector3(0.0, 0.055, 0.012), "primary", 24, 12)
	_box(root, "HelmetRear", Vector3(0.285, 0.125, 0.060), Vector3(0.0, -0.030, 0.105), "primary_dark", Vector3(8.0, 0.0, 0.0))
	_box(root, "HelmetBrim", Vector3(0.270, 0.026, 0.145), Vector3(0.0, 0.015, -0.142), "primary_dark", Vector3(-6.0, 0.0, 0.0))
	var ear_sign := 1.0 if batting_side.to_lower().begins_with("r") else -1.0
	_box(root, "HelmetEarFlap", Vector3(0.060, 0.138, 0.116), Vector3(ear_sign * 0.145, -0.055, 0.020), "primary", Vector3.ZERO)
	_box(root, "HelmetEarPad", Vector3(0.067, 0.070, 0.058), Vector3(ear_sign * 0.148, -0.055, -0.025), "padding", Vector3.ZERO)
	_box(root, "HelmetStripe", Vector3(0.027, 0.028, 0.245), Vector3(0.0, 0.115, 0.012), "accent", Vector3.ZERO)
	_install(actor, root, "head", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.820, 0.0)))


func _install_catcher_gear(actor: Node3D) -> void:
	var mask := _mask("CatcherMask", "metal", "primary_dark", 0.155, 0.265)
	_install(actor, mask, "head", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.715, -0.205)))

	var chest := Node3D.new()
	chest.name = "CatcherChestProtector"
	_box(chest, "CatcherBib", Vector3(0.430, 0.315, 0.058), Vector3.ZERO, "primary_dark", Vector3.ZERO, 0.025)
	for row in range(3):
		_box(chest, "CatcherPlate%d" % row, Vector3(0.375 - row * 0.035, 0.068, 0.034), Vector3(0.0, 0.092 - row * 0.092, -0.040), "accent" if row == 0 else "primary", Vector3.ZERO, 0.014)
	_box(chest, "CatcherShoulderL", Vector3(0.155, 0.095, 0.060), Vector3(-0.205, 0.115, 0.0), "primary", Vector3(0.0, 0.0, -10.0), 0.025)
	_box(chest, "CatcherShoulderR", Vector3(0.155, 0.095, 0.060), Vector3(0.205, 0.115, 0.0), "primary", Vector3(0.0, 0.0, 10.0), 0.025)
	_install(actor, chest, "chest", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.315, -0.205)))

	_install_shin_guard(actor, "L", -0.140)
	_install_shin_guard(actor, "R", 0.140)


func _install_shin_guard(actor: Node3D, side: String, x: float) -> void:
	var root := Node3D.new()
	root.name = "CatcherShinGuard" + side
	_box(root, "ShinShell", Vector3(0.145, 0.340, 0.058), Vector3(0.0, -0.040, 0.0), "primary_dark", Vector3.ZERO, 0.023)
	_sphere(root, "KneeCap", 0.085, 0.080, Vector3(0.0, 0.166, -0.010), "primary", 16, 8)
	for row in range(3):
		_box(root, "ShinPlate%d" % row, Vector3(0.125, 0.052, 0.030), Vector3(0.0, 0.060 - row * 0.105, -0.038), "accent" if row == 0 else "primary", Vector3.ZERO, 0.012)
		_box(root, "ShinStrap%d" % row, Vector3(0.175, 0.021, 0.024), Vector3(0.0, 0.060 - row * 0.105, 0.025), "padding", Vector3.ZERO, 0.008)
	_install(actor, root, "left_shin" if side == "L" else "right_shin", Transform3D(Basis.IDENTITY, Vector3(x, 0.405, -0.105)))


func _install_umpire_gear(actor: Node3D) -> void:
	var mask := _mask("UmpireMask", "metal", "umpire", 0.166, 0.280)
	_install(actor, mask, "head", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.710, -0.215)))

	var chest := Node3D.new()
	chest.name = "UmpireProtector"
	_box(chest, "UmpireVest", Vector3(0.465, 0.330, 0.065), Vector3.ZERO, "umpire", Vector3.ZERO, 0.028)
	_box(chest, "UmpireCenterPad", Vector3(0.185, 0.275, 0.035), Vector3(0.0, -0.005, -0.048), "padding", Vector3.ZERO, 0.021)
	_box(chest, "UmpireShoulderL", Vector3(0.180, 0.105, 0.072), Vector3(-0.220, 0.115, 0.0), "umpire", Vector3(0.0, 0.0, -12.0), 0.028)
	_box(chest, "UmpireShoulderR", Vector3(0.180, 0.105, 0.072), Vector3(0.220, 0.115, 0.0), "umpire", Vector3(0.0, 0.0, 12.0), 0.028)
	_box(chest, "UmpireTrim", Vector3(0.410, 0.026, 0.030), Vector3(0.0, 0.145, -0.055), "accent", Vector3.ZERO, 0.008)
	_install(actor, chest, "chest", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.315, -0.205)))


func _mask(piece_name: String, bar_material: String, pad_material: String, half_width: float, height: float) -> Node3D:
	var root := Node3D.new()
	root.name = piece_name
	for index in range(4):
		var x := lerpf(-half_width * 0.72, half_width * 0.72, float(index) / 3.0)
		_box(root, "MaskVertical%d" % index, Vector3(0.014, height, 0.014), Vector3(x, 0.0, 0.0), bar_material, Vector3.ZERO, 0.005)
	for index in range(4):
		var y := lerpf(-height * 0.40, height * 0.40, float(index) / 3.0)
		_box(root, "MaskHorizontal%d" % index, Vector3(half_width * 2.0, 0.014, 0.014), Vector3(0.0, y, 0.0), bar_material, Vector3.ZERO, 0.005)
	_box(root, "MaskBrowPad", Vector3(half_width * 1.72, 0.038, 0.045), Vector3(0.0, height * 0.48, 0.025), pad_material, Vector3.ZERO, 0.012)
	_box(root, "MaskChinPad", Vector3(half_width * 1.45, 0.046, 0.055), Vector3(0.0, -height * 0.48, 0.025), pad_material, Vector3.ZERO, 0.014)
	_box(root, "MaskSidePadL", Vector3(0.040, height * 0.68, 0.045), Vector3(-half_width, 0.0, 0.025), pad_material, Vector3.ZERO, 0.012)
	_box(root, "MaskSidePadR", Vector3(0.040, height * 0.68, 0.045), Vector3(half_width, 0.0, 0.025), pad_material, Vector3.ZERO, 0.012)
	return root


func _install_identity(actor: Node3D) -> void:
	var mark := _label("TeamMark", _mark, 104, 0.00095, _accent, _primary.darkened(0.55), 18)
	_install(actor, mark, "chest", Transform3D(Basis.IDENTITY, Vector3(0.105, 1.365, -0.270)))

	var number_text := str(_number)
	var number_front := _label("JerseyNumberFront", number_text, 86, 0.00082, _secondary, _primary.darkened(0.55), 16)
	_install(actor, number_front, "chest", Transform3D(Basis.IDENTITY, Vector3(-0.105, 1.305, -0.270)))

	var back_basis := Basis.from_euler(Vector3(0.0, PI, 0.0))
	var number_back := _label("JerseyNumberBack", number_text, 126, 0.00105, _secondary, _primary.darkened(0.58), 18)
	_install(actor, number_back, "chest", Transform3D(back_basis, Vector3(0.0, 1.345, 0.175)))


func _label(name: String, text: String, font_size: int, pixel_size: float, color: Color, outline: Color, outline_size: int) -> Label3D:
	var label := Label3D.new()
	label.name = name
	label.text = text
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.modulate = color
	label.outline_modulate = outline
	label.outline_size = outline_size
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.double_sided = true
	label.alpha_cut = Label3D.ALPHA_CUT_DISCARD
	label.alpha_scissor_threshold = 0.34
	return label


func _install(actor: Node3D, node: Node3D, socket_name: String, actor_transform: Transform3D) -> void:
	actor.add_child(node)
	node.transform = actor_transform
	if not bool(actor.call("attach_to_socket", node, socket_name, true)):
		push_warning("BallplayerEquipment: socket '%s' was unavailable for %s" % [socket_name, node.name])
	_pieces[node.name] = node


func _box(parent: Node3D, name: String, size: Vector3, position: Vector3, material_key: String, rotation_degrees: Vector3, bevel := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	if bevel > 0.0:
		mesh.subdivide_width = 2
		mesh.subdivide_height = 2
		mesh.subdivide_depth = 2
	mesh.material = _materials[material_key]
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.position = position
	instance.rotation_degrees = rotation_degrees
	parent.add_child(instance)
	return instance


func _sphere(parent: Node3D, name: String, radius: float, height: float, position: Vector3, material_key: String, radial_segments: int, rings: int) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = height
	mesh.radial_segments = radial_segments
	mesh.rings = rings
	mesh.material = _materials[material_key]
	var instance := MeshInstance3D.new()
	instance.name = name
	instance.mesh = mesh
	instance.position = position
	parent.add_child(instance)
	return instance
