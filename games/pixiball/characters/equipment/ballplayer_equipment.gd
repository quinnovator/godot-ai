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
const IDENTITY_LABEL_NAMES := ["TeamMark", "JerseyNumberFront", "JerseyNumberBack"]

const KNIT_NORMAL_MAP := preload("res://assets/textures/surface/cotton_jersey_nor_gl_1k.jpg")

## Authored varsity block glyph outlines in a 100x140 em box, each entry a
## list of quads (a 2-point entry is an axis-aligned rect [min, max]; a
## 4-point entry is a free quad). These are cut into two-layer tackle-twill
## applique geometry -- a contrasting border layer under a raised fill layer
## -- exactly like stitched pro uniform lettering, so no font rendering is
## involved anywhere in jersey identity.
const BLOCK_GLYPHS := {
	"0": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 0), Vector2(100, 26)], [Vector2(0, 26), Vector2(26, 114)], [Vector2(74, 26), Vector2(100, 114)]],
	"1": [[Vector2(37, 0), Vector2(63, 140)], [Vector2(10, 114), Vector2(37, 140)], [Vector2(14, 0), Vector2(86, 26)]],
	"2": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(74, 88), Vector2(100, 114)], [Vector2(0, 62), Vector2(100, 88)], [Vector2(0, 26), Vector2(26, 62)], [Vector2(0, 0), Vector2(100, 26)]],
	"3": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(74, 88), Vector2(100, 114)], [Vector2(26, 62), Vector2(100, 88)], [Vector2(74, 26), Vector2(100, 62)], [Vector2(0, 0), Vector2(100, 26)]],
	"4": [[Vector2(0, 62), Vector2(26, 140)], [Vector2(0, 62), Vector2(100, 88)], [Vector2(58, 0), Vector2(84, 140)]],
	"5": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 88), Vector2(26, 114)], [Vector2(0, 62), Vector2(100, 88)], [Vector2(74, 26), Vector2(100, 62)], [Vector2(0, 0), Vector2(100, 26)]],
	"6": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 26), Vector2(26, 114)], [Vector2(26, 62), Vector2(100, 88)], [Vector2(74, 26), Vector2(100, 62)], [Vector2(0, 0), Vector2(100, 26)]],
	"7": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(52, 0), Vector2(78, 0), Vector2(96, 114), Vector2(70, 114)]],
	"8": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 0), Vector2(100, 26)], [Vector2(0, 26), Vector2(26, 114)], [Vector2(74, 26), Vector2(100, 114)], [Vector2(26, 62), Vector2(74, 88)]],
	"9": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(74, 26), Vector2(100, 114)], [Vector2(0, 52), Vector2(74, 78)], [Vector2(0, 78), Vector2(26, 114)], [Vector2(0, 0), Vector2(100, 26)]],
	"A": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 0), Vector2(26, 114)], [Vector2(74, 0), Vector2(100, 114)], [Vector2(26, 52), Vector2(74, 78)]],
	"B": [[Vector2(0, 0), Vector2(26, 140)], [Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 57), Vector2(100, 83)], [Vector2(0, 0), Vector2(100, 26)], [Vector2(74, 83), Vector2(100, 114)], [Vector2(74, 26), Vector2(100, 57)]],
	"C": [[Vector2(0, 26), Vector2(26, 114)], [Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 0), Vector2(100, 26)]],
	"D": [[Vector2(0, 0), Vector2(26, 140)], [Vector2(0, 114), Vector2(88, 140)], [Vector2(0, 0), Vector2(88, 26)], [Vector2(62, 26), Vector2(88, 114)]],
	"E": [[Vector2(0, 0), Vector2(26, 140)], [Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 57), Vector2(78, 83)], [Vector2(0, 0), Vector2(100, 26)]],
	"F": [[Vector2(0, 0), Vector2(26, 140)], [Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 57), Vector2(78, 83)]],
	"G": [[Vector2(0, 26), Vector2(26, 114)], [Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 0), Vector2(100, 26)], [Vector2(74, 26), Vector2(100, 62)], [Vector2(52, 62), Vector2(100, 88)]],
	"H": [[Vector2(0, 0), Vector2(26, 140)], [Vector2(74, 0), Vector2(100, 140)], [Vector2(26, 57), Vector2(74, 83)]],
	"I": [[Vector2(37, 0), Vector2(63, 140)], [Vector2(10, 114), Vector2(90, 140)], [Vector2(10, 0), Vector2(90, 26)]],
	"J": [[Vector2(74, 26), Vector2(100, 140)], [Vector2(0, 0), Vector2(100, 26)], [Vector2(0, 26), Vector2(26, 62)]],
	"K": [[Vector2(0, 0), Vector2(26, 140)], [Vector2(26, 62), Vector2(26, 88), Vector2(100, 140), Vector2(74, 140)], [Vector2(26, 78), Vector2(26, 52), Vector2(74, 0), Vector2(100, 0)]],
	"L": [[Vector2(0, 0), Vector2(26, 140)], [Vector2(0, 0), Vector2(100, 26)]],
	"M": [[Vector2(0, 0), Vector2(26, 140)], [Vector2(74, 0), Vector2(100, 140)], [Vector2(0, 140), Vector2(26, 140), Vector2(63, 52), Vector2(37, 52)], [Vector2(100, 140), Vector2(74, 140), Vector2(37, 52), Vector2(63, 52)]],
	"N": [[Vector2(0, 0), Vector2(26, 140)], [Vector2(74, 0), Vector2(100, 140)], [Vector2(0, 140), Vector2(26, 140), Vector2(100, 0), Vector2(74, 0)]],
	"O": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 0), Vector2(100, 26)], [Vector2(0, 26), Vector2(26, 114)], [Vector2(74, 26), Vector2(100, 114)]],
	"P": [[Vector2(0, 0), Vector2(26, 140)], [Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 57), Vector2(100, 83)], [Vector2(74, 83), Vector2(100, 114)]],
	"Q": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 0), Vector2(100, 26)], [Vector2(0, 26), Vector2(26, 114)], [Vector2(74, 26), Vector2(100, 114)], [Vector2(52, 42), Vector2(74, 64), Vector2(100, 22), Vector2(78, 0)]],
	"R": [[Vector2(0, 0), Vector2(26, 140)], [Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 57), Vector2(100, 83)], [Vector2(74, 83), Vector2(100, 114)], [Vector2(38, 57), Vector2(64, 57), Vector2(100, 0), Vector2(74, 0)]],
	"S": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 88), Vector2(26, 114)], [Vector2(0, 57), Vector2(100, 83)], [Vector2(74, 26), Vector2(100, 57)], [Vector2(0, 0), Vector2(100, 26)]],
	"T": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(37, 0), Vector2(63, 114)]],
	"U": [[Vector2(0, 26), Vector2(26, 140)], [Vector2(74, 26), Vector2(100, 140)], [Vector2(0, 0), Vector2(100, 26)]],
	"V": [[Vector2(0, 140), Vector2(26, 140), Vector2(63, 0), Vector2(37, 0)], [Vector2(100, 140), Vector2(74, 140), Vector2(37, 0), Vector2(63, 0)]],
	"W": [[Vector2(0, 0), Vector2(26, 140)], [Vector2(74, 0), Vector2(100, 140)], [Vector2(0, 0), Vector2(26, 0), Vector2(63, 88), Vector2(37, 88)], [Vector2(100, 0), Vector2(74, 0), Vector2(37, 88), Vector2(63, 88)]],
	"X": [[Vector2(0, 140), Vector2(26, 140), Vector2(100, 0), Vector2(74, 0)], [Vector2(74, 140), Vector2(100, 140), Vector2(26, 0), Vector2(0, 0)]],
	"Y": [[Vector2(0, 140), Vector2(26, 140), Vector2(63, 70), Vector2(37, 70)], [Vector2(100, 140), Vector2(74, 140), Vector2(37, 70), Vector2(63, 70)], [Vector2(37, 0), Vector2(63, 70)]],
	"Z": [[Vector2(0, 114), Vector2(100, 140)], [Vector2(0, 0), Vector2(100, 26)], [Vector2(74, 114), Vector2(100, 114), Vector2(26, 26), Vector2(0, 26)]],
}

const GLYPH_EM_WIDTH := 100.0
const GLYPH_EM_HEIGHT := 140.0
const GLYPH_EM_GAP := 24.0
const TWILL_BORDER_EM := 9.0
const TWILL_BORDER_HEIGHT := 0.0022
const TWILL_FILL_HEIGHT := 0.0042

## Placement of each tackle-twill piece in the actor's neutral space: the
## lettering is curved around the measured torso barrel (parabolic sagitta
## approximation of the chest ellipse) and stands a few millimetres proud of
## the cloth like real stitched applique. The back number spans ~22 cm of
## character height and stays the dominant uniform read from the mound
## camera.
const IDENTITY_SPECS := {
	"TeamMark": {"kind": "mark", "cap_height": 0.098, "center": Vector2(0.095, 1.315), "standoff": 0.163, "side": 0.264, "forward": -1.0},
	"JerseyNumberFront": {"kind": "number", "cap_height": 0.090, "center": Vector2(-0.095, 1.245), "standoff": 0.163, "side": 0.264, "forward": -1.0},
	"JerseyNumberBack": {"kind": "number", "cap_height": 0.195, "center": Vector2(0.0, 1.260), "standoff": 0.164, "side": 0.260, "forward": 1.0},
}

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
	_refresh_identity()
	if _highlighted:
		set_highlighted(true)


func set_identity(mark: String, number: int) -> void:
	_mark = mark.to_upper().left(1)
	_number = posmod(number, 100)
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
		var piece := MeshInstance3D.new()
		piece.name = piece_name
		_apply_identity_visual(piece, IDENTITY_SPECS[piece_name] as Dictionary)
		_install(actor, piece, "chest", Transform3D.IDENTITY)


func _refresh_identity() -> void:
	for piece_name in IDENTITY_LABEL_NAMES:
		var piece := _pieces.get(piece_name) as MeshInstance3D
		if is_instance_valid(piece):
			_apply_identity_visual(piece, IDENTITY_SPECS[piece_name] as Dictionary)


func _identity_text(kind: String) -> String:
	return _mark if kind == "mark" else str(_number)


## Rebuilds the piece's tackle-twill mesh in place so bone attachment and
## handedness correction survive every identity or palette change.
func _apply_identity_visual(piece: MeshInstance3D, spec: Dictionary) -> void:
	var text := _identity_text(String(spec["kind"]))
	piece.mesh = _twill_mesh(text, spec)
	piece.set_meta("identity_text", text)


## Builds stitched two-layer tackle-twill lettering as real geometry: a
## contrasting border layer under a raised fill layer, both extruded from the
## authored block glyph outlines, wrapped around the torso barrel, and shaded
## with the knit fabric normal map. Reads exactly like sewn-on pro uniform
## numbers instead of rendered text.
func _twill_mesh(text: String, spec: Dictionary) -> ArrayMesh:
	var cap_height := float(spec["cap_height"])
	var center: Vector2 = spec["center"]
	var standoff := float(spec["standoff"])
	var side := float(spec["side"])
	var forward := float(spec["forward"])
	var scale := cap_height / GLYPH_EM_HEIGHT
	var glyphs: Array = []
	for index in range(text.length()):
		var glyph: Array = BLOCK_GLYPHS.get(text[index], []) as Array
		if not glyph.is_empty():
			glyphs.append(glyph)
	var total_em := glyphs.size() * GLYPH_EM_WIDTH + maxi(0, glyphs.size() - 1) * GLYPH_EM_GAP
	var mesh := ArrayMesh.new()
	# Umpires intentionally carry an empty team mark. Leave that attachment as
	# an empty mesh instead of asking ArrayMesh to material an absent surface.
	if glyphs.is_empty():
		return mesh
	for layer in [
		{"expand": TWILL_BORDER_EM, "top": TWILL_BORDER_HEIGHT, "color": _secondary},
		{"expand": 0.0, "top": TWILL_FILL_HEIGHT, "color": _primary},
	]:
		var tool := SurfaceTool.new()
		tool.begin(Mesh.PRIMITIVE_TRIANGLES)
		for glyph_index in range(glyphs.size()):
			var origin_em := -total_em * 0.5 + glyph_index * (GLYPH_EM_WIDTH + GLYPH_EM_GAP)
			for quad in glyphs[glyph_index]:
				var corners := _quad_corners(quad as Array, float(layer["expand"]))
				var top_ring: Array[Vector3] = []
				var base_ring: Array[Vector3] = []
				for corner_value in corners:
					var corner: Vector2 = corner_value
					var lx := (origin_em + corner.x) * scale
					var ly := (corner.y - GLYPH_EM_HEIGHT * 0.5) * scale
					top_ring.append(_wrap_point(lx, ly, float(layer["top"]), center, standoff, side, forward))
					base_ring.append(_wrap_point(lx, ly, 0.0004, center, standoff, side, forward))
				_add_quad(tool, top_ring[0], top_ring[1], top_ring[2], top_ring[3])
				for edge in range(4):
					var next_edge := (edge + 1) % 4
					_add_quad(tool, base_ring[edge], base_ring[next_edge], top_ring[next_edge], top_ring[edge])
		tool.generate_normals()
		tool.commit(mesh)
		var material := StandardMaterial3D.new()
		material.resource_name = "Equipment_Twill"
		material.albedo_color = layer["color"]
		material.roughness = 0.82
		material.normal_enabled = true
		material.normal_texture = KNIT_NORMAL_MAP
		material.normal_scale = 0.5
		material.uv1_triplanar = true
		material.uv1_scale = Vector3(30.0, 30.0, 30.0)
		mesh.surface_set_material(mesh.get_surface_count() - 1, material)
	return mesh


## Curves a local lettering point around the torso: em-x advance runs toward
## the viewer's right for the piece's facing, and depth follows the measured
## elliptical chest/back cross-section (half-width ``side``) offset a few
## millimetres outward, so the applique hugs the cloth across its full span.
func _wrap_point(lx: float, ly: float, height: float, center: Vector2, standoff: float, side: float, forward: float) -> Vector3:
	var wx := center.x + forward * lx
	var ratio := clampf(1.0 - (wx * wx) / (side * side), 0.12, 1.0)
	return Vector3(wx, center.y + ly, forward * (standoff + height) * sqrt(ratio))


func _quad_corners(quad: Array, expand: float) -> Array:
	var corners: Array = []
	if quad.size() == 2:
		var lo: Vector2 = quad[0]
		var hi: Vector2 = quad[1]
		corners = [Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(hi.x, hi.y), Vector2(lo.x, hi.y)]
	else:
		corners = quad.duplicate()
	var area := 0.0
	for index in range(corners.size()):
		var a: Vector2 = corners[index]
		var b: Vector2 = corners[(index + 1) % corners.size()]
		area += a.x * b.y - b.x * a.y
	if area < 0.0:
		corners.reverse()
	if expand > 0.0:
		var centroid := Vector2.ZERO
		for corner in corners:
			centroid += corner
		centroid /= corners.size()
		for index in range(corners.size()):
			var offset: Vector2 = corners[index] - centroid
			corners[index] = corners[index] + Vector2(signf(offset.x), signf(offset.y)) * expand
	return corners


func _add_quad(tool: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	# Godot front faces wind clockwise.
	for vertex in [a, c, b, a, d, c]:
		tool.add_vertex(vertex)


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
