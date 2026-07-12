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
const IDENTITY_LABEL_NAMES := ["TeamMark", "JerseyNumberFront", "JerseyNameBack", "JerseyNumberBack"]

const KNIT_NORMAL_MAP := preload("res://assets/textures/surface/cotton_jersey_nor_gl_1k.jpg")
const IDENTITY_FONT := preload("res://assets/fonts/graduate/Graduate-Regular.ttf")
const IDENTITY_FONT_SIZE := 128
const IDENTITY_PIXEL_SIZE := 0.001
const IDENTITY_CURVE_STEP := 0.30
const IDENTITY_BORDER_SCALE := 1.10
const IDENTITY_BORDER_DEPTH := 0.0024
const IDENTITY_FILL_DEPTH := 0.0038

## Placement of each tackle-twill piece in the actor's neutral space: the
## lettering is curved around the measured torso barrel (parabolic sagitta
## approximation of the chest ellipse) and stands a few millimetres proud of
## the cloth like real stitched applique. The back number spans ~22 cm of
## character height and stays the dominant uniform read from the mound
## camera.
const IDENTITY_SPECS := {
	"TeamMark": {"kind": "mark", "cap_height": 0.100, "max_width": 0.105, "letter_gap": 0.08, "center": Vector2(0.095, 1.315), "standoff": 0.164, "side": 0.264, "forward": -1.0},
	"JerseyNumberFront": {"kind": "number", "cap_height": 0.092, "max_width": 0.125, "letter_gap": 0.08, "center": Vector2(-0.095, 1.245), "standoff": 0.164, "side": 0.264, "forward": -1.0},
	"JerseyNameBack": {"kind": "name", "cap_height": 0.044, "max_width": 0.390, "letter_gap": 0.03, "center": Vector2(0.0, 1.410), "standoff": 0.165, "side": 0.260, "forward": 1.0},
	"JerseyNumberBack": {"kind": "number", "cap_height": 0.190, "max_width": 0.225, "letter_gap": 0.07, "center": Vector2(0.0, 1.265), "standoff": 0.165, "side": 0.260, "forward": 1.0},
}

var _pieces: Dictionary = {}
var _materials: Dictionary = {}
var _role := "fielder"
var _mark := ""
var _number := 0
var _player_name := ""
var _primary := Color("173f73")
var _secondary := Color("f1ead9")
var _accent := Color("e2b447")
var _highlighted := false


func configure(actor: Node3D, spec: Dictionary, primary: Color, secondary: Color, accent: Color) -> void:
	_clear_pieces()
	_role = String(spec.get("role", "fielder")).to_lower()
	_mark = String(spec.get("mark", "")).to_upper().left(1)
	_number = posmod(int(spec.get("number", 0)), 100)
	_player_name = _jersey_surname(String(spec.get("player_name", spec.get("name", ""))))
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
	_set_material_color("identity_fill", primary)
	_set_material_color("identity_border", secondary)
	_refresh_identity()
	if _highlighted:
		set_highlighted(true)


func set_identity(mark: String, number: int, player_name := "") -> void:
	_mark = mark.to_upper().left(1)
	_number = posmod(number, 100)
	_player_name = _jersey_surname(player_name)
	_refresh_identity()


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
		"player_name": _player_name,
		"pieces": PackedStringArray(_pieces.keys()),
	}


func get_piece(piece_name: String) -> Node3D:
	return _pieces.get(piece_name) as Node3D


## Keeps bone-attached identity glyphs readable when BallplayerActor changes
## the imported model's X scale between batting and throwing handedness. The
## initial keep-global attachment bakes the current sign into each local basis;
## a later sign change would otherwise reflect the glyphs.
func sync_identity_orientation() -> void:
	for piece_name in IDENTITY_LABEL_NAMES:
		var glyphs := _pieces.get(piece_name) as Node3D
		if not is_instance_valid(glyphs):
			continue
		if glyphs.global_transform.basis.determinant() < 0.0:
			var corrected := glyphs.transform
			corrected.basis.x = -corrected.basis.x
			glyphs.transform = corrected


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
		"identity_fill": _twill_material("Equipment_TwillFill", _primary),
		"identity_border": _twill_material("Equipment_TwillBorder", _secondary),
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


func _twill_material(name: String, color: Color) -> StandardMaterial3D:
	var value := _material(name, color, 0.82)
	value.normal_enabled = true
	value.normal_texture = KNIT_NORMAL_MAP
	value.normal_scale = 0.48
	value.uv1_triplanar = true
	value.uv1_scale = Vector3(30.0, 30.0, 30.0)
	return value


func _set_material_color(key: String, color: Color) -> void:
	var material := _materials.get(key) as StandardMaterial3D
	if material != null:
		material.albedo_color = color


func _install_batting_helmet(actor: Node3D, batting_side: String) -> void:
	var root := Node3D.new()
	root.name = "BattingHelmet"
	_sphere(root, "HelmetDome", 0.105, 0.135, Vector3(0.0, 0.030, 0.007), "primary", 24, 12)
	_box(root, "HelmetRear", Vector3(0.155, 0.068, 0.034), Vector3(0.0, -0.016, 0.058), "primary_dark", Vector3(8.0, 0.0, 0.0))
	_box(root, "HelmetBrim", Vector3(0.150, 0.015, 0.082), Vector3(0.0, 0.008, -0.080), "primary_dark", Vector3(-6.0, 0.0, 0.0))
	var ear_sign := 1.0 if batting_side.to_lower().begins_with("r") else -1.0
	_box(root, "HelmetEarFlap", Vector3(0.034, 0.076, 0.064), Vector3(ear_sign * 0.082, -0.030, 0.011), "primary", Vector3.ZERO)
	_box(root, "HelmetEarPad", Vector3(0.037, 0.038, 0.032), Vector3(ear_sign * 0.084, -0.030, -0.014), "padding", Vector3.ZERO)
	_box(root, "HelmetStripe", Vector3(0.015, 0.016, 0.135), Vector3(0.0, 0.063, 0.007), "accent", Vector3.ZERO)
	_install(actor, root, "head", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.766, 0.0)))


func _install_catcher_gear(actor: Node3D) -> void:
	var mask := _mask("CatcherMask", "metal", "primary_dark", 0.085, 0.150)
	_install(actor, mask, "head", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.700, -0.150)))

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
	var mask := _mask("UmpireMask", "metal", "umpire", 0.090, 0.158)
	_install(actor, mask, "head", Transform3D(Basis.IDENTITY, Vector3(0.0, 1.700, -0.155)))

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
	for piece_name in IDENTITY_LABEL_NAMES:
		var piece := Node3D.new()
		piece.name = piece_name
		_apply_identity_visual(piece, IDENTITY_SPECS[piece_name] as Dictionary)
		_install(actor, piece, "chest", Transform3D.IDENTITY)


func _refresh_identity() -> void:
	for piece_name in IDENTITY_LABEL_NAMES:
		var piece := _pieces.get(piece_name) as Node3D
		if is_instance_valid(piece):
			_apply_identity_visual(piece, IDENTITY_SPECS[piece_name] as Dictionary)


func _identity_text(kind: String) -> String:
	if kind == "mark":
		return _mark
	if kind == "name":
		return _player_name
	return str(_number)


## Rebuilds a piece from vector font contours so a runtime identity change
## keeps the same physical tackle-twill depth, palette, and chest attachment.
## Each glyph receives its own torso tangent instead of floating as one flat
## billboard across the curved jersey barrel.
func _apply_identity_visual(piece: Node3D, spec: Dictionary) -> void:
	var text := _identity_text(String(spec["kind"]))
	for child in piece.get_children():
		child.free()
	_build_curved_twill(piece, text, spec)
	piece.set_meta("identity_text", text)
	piece.set_meta("identity_height", float(spec["cap_height"]))
	piece.set_meta("identity_max_width", float(spec["max_width"]))
	piece.set_meta("identity_style", "graduate_vector_twill")


func _build_curved_twill(root: Node3D, text: String, spec: Dictionary) -> void:
	if text.is_empty():
		return
	var cap_height := float(spec["cap_height"])
	var gap := cap_height * float(spec.get("letter_gap", 0.06))
	var glyphs: Array[Dictionary] = []
	var natural_width := 0.0
	for index in range(text.length()):
		var character := text.substr(index, 1)
		var fill_mesh := _text_mesh(character, IDENTITY_FILL_DEPTH, _materials["identity_fill"])
		var border_mesh := _text_mesh(character, IDENTITY_BORDER_DEPTH, _materials["identity_border"])
		var bounds := fill_mesh.get_aabb()
		var glyph_scale := cap_height / maxf(bounds.size.y, 0.0001)
		var glyph_width := bounds.size.x * glyph_scale
		glyphs.append({
			"character": character,
			"fill": fill_mesh,
			"border": border_mesh,
			"scale": glyph_scale,
			"width": glyph_width,
		})
		natural_width += glyph_width
	if glyphs.size() > 1:
		natural_width += gap * float(glyphs.size() - 1)
	var max_width := float(spec["max_width"])
	var width_scale := minf(1.0, max_width / maxf(natural_width, 0.0001))
	var rendered_width := natural_width * width_scale
	var cursor := -rendered_width * 0.5
	var center: Vector2 = spec["center"]
	var side := float(spec["side"])
	var forward := float(spec["forward"])
	for index in range(glyphs.size()):
		var glyph: Dictionary = glyphs[index]
		var glyph_width := float(glyph["width"]) * width_scale
		var local_x := cursor + glyph_width * 0.5
		var surface := _wrap_point(local_x, 0.0, 0.0, center, float(spec["standoff"]), side, forward)
		var slope_angle := asin(clampf(surface.x / side, -0.92, 0.92))
		var outward_angle := slope_angle if forward > 0.0 else PI - slope_angle
		var glyph_root := Node3D.new()
		glyph_root.name = "Glyph_%02d_%s" % [index, String(glyph["character"])]
		glyph_root.position = surface
		glyph_root.rotation.y = outward_angle
		root.add_child(glyph_root)

		var base_scale := float(glyph["scale"])
		var border := MeshInstance3D.new()
		border.name = "TwillBorder"
		border.mesh = glyph["border"] as TextMesh
		border.scale = Vector3(base_scale * width_scale * IDENTITY_BORDER_SCALE, base_scale * IDENTITY_BORDER_SCALE, 1.0)
		glyph_root.add_child(border)

		var fill := MeshInstance3D.new()
		fill.name = "TwillFill"
		fill.mesh = glyph["fill"] as TextMesh
		fill.scale = Vector3(base_scale * width_scale, base_scale, 1.0)
		fill.position.z = 0.0017
		glyph_root.add_child(fill)
		cursor += glyph_width + gap * width_scale
	root.set_meta("identity_glyph_count", glyphs.size())
	root.set_meta("identity_rendered_width", rendered_width)


func _text_mesh(text: String, depth: float, material: Material) -> TextMesh:
	var mesh := TextMesh.new()
	mesh.text = text
	mesh.font = IDENTITY_FONT
	mesh.font_size = IDENTITY_FONT_SIZE
	mesh.pixel_size = IDENTITY_PIXEL_SIZE
	mesh.curve_step = IDENTITY_CURVE_STEP
	mesh.depth = depth
	mesh.material = material
	return mesh


func _jersey_surname(value: String) -> String:
	var words := value.to_upper().strip_edges().split(" ", false)
	if words.is_empty():
		return ""
	return String(words[words.size() - 1]).left(14)


## Curves a local lettering point around the torso: em-x advance runs toward
## the viewer's right for the piece's facing, and depth follows the measured
## elliptical chest/back cross-section (half-width ``side``) offset a few
## millimetres outward, so the applique hugs the cloth across its full span.
func _wrap_point(lx: float, ly: float, height: float, center: Vector2, standoff: float, side: float, forward: float) -> Vector3:
	var wx := center.x + forward * lx
	var ratio := clampf(1.0 - (wx * wx) / (side * side), 0.12, 1.0)
	return Vector3(wx, center.y + ly, forward * (standoff + height) * sqrt(ratio))


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
