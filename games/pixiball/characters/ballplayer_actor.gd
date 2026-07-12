@tool
class_name BallplayerActor
extends Node3D

## Gameplay facade for the authored Blender ballplayer.
##
## Geometry, skinning, uniform pieces, role equipment, materials, and native
## actions all come from the checked-in Blender/GLB asset. Runtime code only
## selects authored meshes, applies per-instance palette overrides, and renders
## roster identity into the jersey's Blender-authored UV surfaces.

signal action_started(action_name: String)
signal action_marker(action_name: String, marker_name: String)
signal action_finished(action_name: String)

const MODEL_SCENE_PATH := "res://assets/models/ballplayer/ballplayer.glb"
const EQUIPMENT_SCENE = preload("res://characters/equipment/ballplayer_equipment.tscn")
const CHARACTER_RENDER_LAYER := 1 << 1
const NOMINAL_HEIGHT_METERS := 1.84

const ACTION_CLIPS := {
	"idle": "idle",
	"run": "run",
	"pitch": "pitch",
	"swing": "swing",
	"catch": "catch",
	"field_ready": "field_ready",
	"field_throw": "field_throw",
	"throw": "field_throw",
	"celebrate": "celebrate",
	"slide": "slide",
}

const ACTION_DURATIONS := {
	"pitch": 1.42,
	"swing": 0.36,
	"catch": 0.68,
	"field_throw": 0.86,
	"throw": 0.86,
	"celebrate": 1.55,
	"slide": 1.20,
}

const ACTION_MARKERS := {
	"pitch": {"ball_release": 27.0 / 44.0},
	"swing": {"bat_contact": 19.0 / 29.0},
	"catch": {"glove_contact": 14.0 / 25.0},
	"field_throw": {"ball_release": 18.0 / 31.0},
	"throw": {"ball_release": 18.0 / 31.0},
	"celebrate": {"celebration_peak": 24.0 / 49.0},
	"slide": {"base_contact": 22.0 / 39.0},
}

const SOCKET_BONES := {
	"head": "socket_head",
	"chest": "socket_chest",
	"left_hand": "hand.L",
	"right_hand": "hand.R",
	"glove": "socket_glove",
	"catch": "socket_catch",
	"throw_hand": "socket_ball",
	"ball_release": "socket_ball",
	"bat_grip": "socket_bat",
	"bat_tip": "socket_bat_tip",
	"left_foot": "socket_foot.L",
	"right_foot": "socket_foot.R",
	"left_shin": "shin.L",
	"right_shin": "shin.R",
}

const SKIN_TONES := [
	Color("f0c29a"),
	Color("dda06b"),
	Color("bd7747"),
	Color("955735"),
	Color("704027"),
	Color("4b2a20"),
]

const HAIR_TONES := [
	Color("211715"),
	Color("49301f"),
	Color("744526"),
	Color("a87838"),
	Color("b7b2a8"),
	Color("7d2e20"),
]

@export_file("*.glb") var model_scene_path := MODEL_SCENE_PATH

var _spec: Dictionary = {}
var _configured := false
var _visual_ready := false
var _model_root: Node3D
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _meshes: Array[MeshInstance3D] = []
var _material_overrides: Array[Dictionary] = []
var _sockets: Dictionary = {}
var _equipment: BallplayerEquipment
var _equipment_pending := false

var _current_action := "idle"
var _emitted_markers: Dictionary = {}
var _motion_velocity := Vector3.ZERO
var _target_yaw := 0.0
var _highlighted := false
var _role := "fielder"
var _throwing_hand := "right"
var _batting_side := "right"
var _team_mark := ""
var _player_name := ""
var _primary_color := Color("173f73")
var _secondary_color := Color("f1ead9")
var _accent_color := Color("e2b447")
var _pants_color := Color("e9e6da")


func _ready() -> void:
	if not _configured:
		configure({})
	elif _equipment_pending and _visual_ready:
		_configure_modular_equipment()
	set_physics_process(true)


## Important keys are seed, role, number, mark, height, build, player_name,
## skin_tone, hair_color, throws, bats, primary_color, secondary_color,
## accent_color, pants_color, glove, bat, and helmet.
func configure(spec: Dictionary) -> void:
	_spec = spec.duplicate(true)
	_role = String(_spec.get("role", "fielder")).to_lower()
	_throwing_hand = _normalized_hand(String(_spec.get("throws", "right")))
	_batting_side = _normalized_hand(String(_spec.get("bats", _throwing_hand)))
	_team_mark = String(_spec.get("mark", "")).to_upper().left(1)
	_player_name = String(_spec.get("player_name", _spec.get("name", ""))).strip_edges()
	_primary_color = _as_color(_spec.get("primary_color", _primary_color), _primary_color)
	_secondary_color = _as_color(_spec.get("secondary_color", _secondary_color), _secondary_color)
	_accent_color = _as_color(_spec.get("accent_color", _accent_color), _accent_color)
	_pants_color = _as_color(_spec.get("pants_color", _pants_color), _pants_color)

	_ensure_visual()
	if not _visual_ready:
		_configured = true
		return

	_apply_dimensions_and_handedness()
	_apply_equipment_visibility()
	_apply_character_palette()
	set_uniform_colors(_primary_color, _secondary_color, _accent_color, _pants_color)
	if is_inside_tree():
		_configure_modular_equipment()
	else:
		_equipment_pending = true
	set_team_mark(_team_mark)
	set_highlighted(_highlighted)
	_assign_character_render_layer(self)
	_current_action = "idle"
	_emitted_markers.clear()
	_play_imported_clip("idle", false)
	_configured = true


func play_action(name: String) -> void:
	var requested := name.to_lower().strip_edges()
	if not _visual_ready:
		return
	if not ACTION_CLIPS.has(requested):
		push_warning("BallplayerActor: unknown action '%s'" % name)
		return
	if requested == _current_action and requested in ["idle", "run", "field_ready"]:
		return
	_current_action = requested
	_emitted_markers.clear()
	_play_imported_clip(requested, true)


func hold_action_pose(name: String, normalized_time := 0.0) -> void:
	var requested := name.to_lower().strip_edges()
	if not ACTION_CLIPS.has(requested) or not is_instance_valid(_animation_player):
		return
	_apply_action_handedness(requested)
	var clip_name := String(ACTION_CLIPS[requested])
	if not _animation_player.has_animation(clip_name):
		return
	_animation_player.play(clip_name, 0.0, 1.0)
	var animation := _animation_player.get_animation(clip_name)
	_animation_player.seek(animation.length * clampf(normalized_time, 0.0, 1.0), true)
	_animation_player.pause()
	_current_action = "idle"
	_emitted_markers.clear()


func set_motion(velocity: Vector3) -> void:
	_motion_velocity = velocity
	if not _visual_ready:
		return
	var moving := Vector2(velocity.x, velocity.z).length() > 0.12
	if _current_action in ["idle", "run"]:
		var wanted := "run" if moving else "idle"
		if wanted != _current_action:
			play_action(wanted)
	elif _current_action == "field_ready" and moving:
		play_action("run")
	if _current_action == "run" and is_instance_valid(_animation_player):
		_animation_player.speed_scale = clampf(Vector2(velocity.x, velocity.z).length() / 3.2, 0.72, 1.65)


func set_facing(direction: Vector3) -> void:
	var planar := Vector3(direction.x, 0.0, direction.z)
	if planar.length_squared() < 0.000001:
		return
	planar = planar.normalized()
	_target_yaw = atan2(-planar.x, -planar.z)


func get_socket_position(name: String) -> Vector3:
	var key := name.to_lower().strip_edges()
	if key == "feet":
		var left := get_socket_node("left_foot")
		var right := get_socket_node("right_foot")
		if is_instance_valid(left) and is_instance_valid(right):
			return (left.global_position + right.global_position) * 0.5
	var socket := get_socket_node(key)
	if is_instance_valid(socket):
		return socket.global_position
	return global_position


func get_socket_node(name: String) -> Node3D:
	return _sockets.get(name.to_lower().strip_edges()) as Node3D


func attach_to_socket(node: Node3D, socket_name: String, keep_global := false) -> bool:
	var socket := get_socket_node(socket_name)
	if not is_instance_valid(socket) or not is_instance_valid(node):
		return false
	var previous_transform := node.global_transform
	if node.get_parent() != null:
		node.reparent(socket, keep_global)
	else:
		socket.add_child(node)
		if keep_global:
			node.global_transform = previous_transform
	if not keep_global:
		node.transform = Transform3D.IDENTITY
	return true


func set_highlighted(enabled: bool) -> void:
	_highlighted = enabled
	for entry in _material_overrides:
		var value := entry.get("material") as BaseMaterial3D
		if value == null:
			continue
		value.emission_enabled = enabled
		value.emission = value.albedo_color
		value.emission_energy_multiplier = 0.30 if enabled else 0.0
	if is_instance_valid(_equipment):
		_equipment.set_highlighted(enabled)


## Recolors the authored material slots without changing geometry or UVs.
func set_uniform_colors(primary: Color, secondary: Color, accent: Color, pants := Color("e9e6da")) -> void:
	_primary_color = primary
	_secondary_color = secondary
	_accent_color = accent
	_pants_color = pants
	_apply_material_color("TEAM_Primary", primary)
	_apply_material_color("TEAM_Secondary", secondary)
	_apply_material_color("TEAM_Accent", accent)
	_apply_material_color("MAT_Jersey", primary)
	_apply_material_color("MAT_Pants", pants)
	if is_instance_valid(_equipment):
		_equipment.set_palette(primary, secondary, accent)
	if _highlighted:
		set_highlighted(true)


func set_team_mark(mark: String) -> void:
	_team_mark = mark.to_upper().left(1)
	_spec["mark"] = _team_mark
	_refresh_identity()


func set_jersey_number(number: int) -> void:
	_spec["number"] = posmod(number, 100)
	_refresh_identity()


func set_player_name(player_name: String) -> void:
	_player_name = player_name.strip_edges()
	_spec["player_name"] = _player_name
	_refresh_identity()


func get_team_mark() -> String:
	return _team_mark


func get_jersey_number() -> int:
	return posmod(int(_spec.get("number", 0)), 100)


func get_player_name() -> String:
	return _player_name


func get_throwing_hand() -> String:
	return _throwing_hand


func get_batting_side() -> String:
	return _batting_side


func get_role() -> String:
	return _role


func get_equipment_profile() -> Dictionary:
	if not is_instance_valid(_equipment):
		return {"role": _role, "mark": _team_mark, "number": get_jersey_number(), "player_name": _player_name, "pieces": PackedStringArray()}
	return _equipment.get_profile()


func get_equipment_piece(piece_name: String) -> Node3D:
	if not is_instance_valid(_equipment):
		return null
	return _equipment.get_piece(piece_name)


func get_imported_mesh(mesh_name: String) -> MeshInstance3D:
	for mesh_instance in _meshes:
		if mesh_instance.name == mesh_name:
			return mesh_instance
	return null


func is_model_mirrored() -> bool:
	return is_instance_valid(_model_root) and _model_root.scale.x < 0.0


func get_current_action() -> String:
	return _current_action


func get_generation_signature() -> String:
	return "blender-v1:%s:%s:%s:%s:%s:%s:%s:%s" % [
		int(_spec.get("seed", 1)),
		_role,
		_throwing_hand,
		_batting_side,
		String(_spec.get("build", "balanced")),
		_team_mark,
		get_jersey_number(),
		_player_name,
	]


func is_using_fallback() -> bool:
	return false


func get_model_kind() -> String:
	return "rigged_glb" if _visual_ready else "missing_model"


func get_available_actions() -> PackedStringArray:
	return PackedStringArray(ACTION_CLIPS.keys())


func _physics_process(delta: float) -> void:
	if not _configured or not _visual_ready:
		return
	rotation.y = lerp_angle(rotation.y, _target_yaw, minf(1.0, delta * 10.0))
	_update_action_markers()


func _ensure_visual() -> void:
	if is_instance_valid(_model_root):
		return
	if not ResourceLoader.exists(model_scene_path, "PackedScene"):
		push_error("BallplayerActor: authored Blender model is unavailable: %s" % model_scene_path)
		return
	var packed := ResourceLoader.load(model_scene_path, "PackedScene") as PackedScene
	if packed == null:
		push_error("BallplayerActor: authored Blender model failed to load: %s" % model_scene_path)
		return
	_model_root = packed.instantiate() as Node3D
	if _model_root == null:
		push_error("BallplayerActor: authored Blender scene has no Node3D root")
		return
	_model_root.name = "RiggedBallplayer"
	add_child(_model_root)
	_collect_imported_nodes(_model_root)
	if not is_instance_valid(_skeleton) or not is_instance_valid(_animation_player) or _meshes.is_empty():
		push_error("BallplayerActor: authored Blender model is missing its rig, meshes, or actions")
		_model_root.free()
		_model_root = null
		return
	_install_material_overrides()
	_install_sockets()
	_configure_animation_library()
	_animation_player.animation_finished.connect(_on_animation_finished)
	_visual_ready = true


func _collect_imported_nodes(node: Node) -> void:
	if node is Skeleton3D and not is_instance_valid(_skeleton):
		_skeleton = node as Skeleton3D
	elif node is AnimationPlayer and not is_instance_valid(_animation_player):
		_animation_player = node as AnimationPlayer
	elif node is MeshInstance3D:
		_meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_imported_nodes(child)


## Keep the GLB's authored PBR materials and UV textures; only duplicate them
## per instance so team palettes never mutate the imported shared resources.
func _install_material_overrides() -> void:
	_material_overrides.clear()
	for mesh_instance in _meshes:
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.mesh.surface_get_material(surface)
			if source == null:
				continue
			var local := source.duplicate(true) as Material
			local.resource_name = source.resource_name
			local.resource_local_to_scene = true
			mesh_instance.set_surface_override_material(surface, local)
			_material_overrides.append({"name": source.resource_name, "material": local})


func _install_sockets() -> void:
	_sockets.clear()
	for semantic_name in SOCKET_BONES:
		var bone_name := String(SOCKET_BONES[semantic_name])
		if _skeleton.find_bone(bone_name) < 0:
			push_warning("BallplayerActor: imported rig is missing bone '%s'" % bone_name)
			continue
		var attachment := BoneAttachment3D.new()
		attachment.name = "Socket_%s" % String(semantic_name).to_pascal_case()
		attachment.bone_name = StringName(bone_name)
		_skeleton.add_child(attachment)
		_sockets[semantic_name] = attachment


func _configure_animation_library() -> void:
	for action in ACTION_CLIPS.values():
		var clip_name := String(action)
		if not _animation_player.has_animation(clip_name):
			continue
		var animation := _animation_player.get_animation(clip_name)
		animation.loop_mode = Animation.LOOP_LINEAR if clip_name in ["idle", "run", "field_ready"] else Animation.LOOP_NONE


func _apply_dimensions_and_handedness() -> void:
	var seed := int(_spec.get("seed", 1))
	var sampled_height := 1.76 + float(posmod(seed * 48271, 1000)) / 1000.0 * 0.18
	var height := clampf(float(_spec.get("height", sampled_height)), 1.55, 2.05)
	var build := String(_spec.get("build", "balanced")).to_lower()
	var width_scale: float = {"speed": 0.93, "balanced": 0.98, "power": 1.04}.get(build, 0.98)
	var mirror := -1.0 if _hand_for_action("idle") == "left" else 1.0
	_model_root.scale = Vector3(width_scale * mirror, height / NOMINAL_HEIGHT_METERS, width_scale)


func _apply_equipment_visibility() -> void:
	var show_bat := bool(_spec.get("bat", _role == "batter"))
	var show_glove := bool(_spec.get("glove", _role not in ["batter", "umpire"]))
	var helmet_default := _role in ["batter", "hitter", "slugger"]
	var hide_cap := bool(_spec.get("helmet", helmet_default)) or _role in ["catcher", "umpire"]
	for mesh_instance in _meshes:
		if mesh_instance.name.begins_with("Gear_"):
			mesh_instance.visible = false
		elif mesh_instance.name == "Bat_Skinned":
			mesh_instance.visible = show_bat
		elif mesh_instance.name == "Glove_Skinned":
			mesh_instance.visible = show_glove
		elif mesh_instance.name == "Cap_Skinned":
			mesh_instance.visible = not hide_cap


func _configure_modular_equipment() -> void:
	if not is_instance_valid(_equipment):
		_equipment = EQUIPMENT_SCENE.instantiate() as BallplayerEquipment
		_equipment.name = "Equipment"
		add_child(_equipment)
	_equipment.configure(self, _spec, _primary_color, _secondary_color, _accent_color)
	_equipment.sync_identity_orientation(is_model_mirrored())
	_assign_character_render_layer(_equipment)
	_equipment_pending = false


func _refresh_identity() -> void:
	if is_instance_valid(_equipment):
		_equipment.set_identity(_team_mark, get_jersey_number(), _player_name)


func _assign_character_render_layer(node: Node) -> void:
	if node is VisualInstance3D:
		(node as VisualInstance3D).layers = CHARACTER_RENDER_LAYER
	for child in node.get_children():
		_assign_character_render_layer(child)


func _apply_character_palette() -> void:
	var seed := int(_spec.get("seed", 1))
	var default_skin: Color = SKIN_TONES[posmod(seed * 17 + 3, SKIN_TONES.size())]
	var default_hair: Color = HAIR_TONES[posmod(seed * 29 + 1, HAIR_TONES.size())]
	var skin := _as_color(_spec.get("skin_tone", default_skin), default_skin)
	var hair := _as_color(_spec.get("hair_color", default_hair), default_hair)
	_apply_material_color("MAT_Skin", skin)
	_apply_material_color("MAT_Hair", hair)
	_apply_material_color("MAT_HairHighlight", hair.lightened(0.18))


func _apply_material_color(material_name: String, color: Color) -> void:
	for entry in _material_overrides:
		if String(entry.get("name", "")) != material_name:
			continue
		var value := entry.get("material") as BaseMaterial3D
		if value != null:
			value.albedo_color = color


func _play_imported_clip(action: String, emit_started: bool) -> void:
	if not is_instance_valid(_animation_player):
		return
	_apply_action_handedness(action)
	var clip_name := String(ACTION_CLIPS.get(action, "idle"))
	if not _animation_player.has_animation(clip_name):
		push_warning("BallplayerActor: imported model is missing animation '%s'" % clip_name)
		return
	var speed := 1.0
	if ACTION_DURATIONS.has(action):
		var animation := _animation_player.get_animation(clip_name)
		speed = animation.length / float(ACTION_DURATIONS[action])
	elif action == "run":
		speed = clampf(Vector2(_motion_velocity.x, _motion_velocity.z).length() / 3.2, 0.72, 1.65)
	var blend_time := 0.18 if action == "pitch" or String(_animation_player.current_animation) == "pitch" else 0.10
	_animation_player.play(clip_name, blend_time, speed)
	if emit_started:
		action_started.emit(action)


func _apply_action_handedness(action: String) -> void:
	if not is_instance_valid(_model_root):
		return
	var magnitude := absf(_model_root.scale.x)
	_model_root.scale.x = -magnitude if _hand_for_action(action) == "left" else magnitude
	if is_instance_valid(_equipment):
		_equipment.sync_identity_orientation(_model_root.scale.x < 0.0)


func _hand_for_action(action: String) -> String:
	if action == "swing":
		return _batting_side
	if action in ["pitch", "catch", "field_ready", "field_throw", "throw"]:
		return _throwing_hand
	return _batting_side if _role == "batter" else _throwing_hand


func _update_action_markers() -> void:
	if not ACTION_MARKERS.has(_current_action) or not is_instance_valid(_animation_player):
		return
	var length := _animation_player.current_animation_length
	if length <= 0.0:
		return
	var progress := clampf(_animation_player.current_animation_position / length, 0.0, 1.0)
	var markers: Dictionary = ACTION_MARKERS[_current_action]
	for marker_name in markers:
		if progress >= float(markers[marker_name]) and not _emitted_markers.has(marker_name):
			_emitted_markers[marker_name] = true
			action_marker.emit(_current_action, String(marker_name))


func _on_animation_finished(_animation_name: StringName) -> void:
	if _current_action in ["idle", "run", "field_ready"]:
		return
	var finished := _current_action
	action_finished.emit(finished)
	_current_action = "run" if Vector2(_motion_velocity.x, _motion_velocity.z).length() > 0.12 else "idle"
	_emitted_markers.clear()
	_play_imported_clip(_current_action, false)


func _normalized_hand(value: String) -> String:
	return "left" if value.to_lower().begins_with("l") else "right"


func _as_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String:
		return Color.from_string(value, fallback)
	if value is int:
		return SKIN_TONES[posmod(int(value), SKIN_TONES.size())]
	return fallback
