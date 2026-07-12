@tool
class_name BallplayerActor
extends Node3D

## Production ballplayer facade.
##
## The imported, rigged GLB is the primary implementation. The procedural
## VoxelBallplayer is instantiated only when the model cannot be loaded. This
## class preserves the gameplay-facing API and adds stable attachment nodes so
## presentation code never needs to know the imported scene hierarchy.

signal action_started(action_name: String)
signal action_marker(action_name: String, marker_name: String)
signal action_finished(action_name: String)

const MODEL_SCENE_PATH := "res://assets/models/ballplayer/ballplayer.glb"
const FALLBACK_SCRIPT = preload("res://characters/voxel_ballplayer.gd")
const EQUIPMENT_SCENE = preload("res://characters/equipment/ballplayer_equipment.tscn")
const CHARACTER_RENDER_LAYER := 1 << 1
const BROADCAST_HEAD_SCALE := 1.08

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

const FALLBACK_ACTION_CLIPS := {
	"field_ready": "idle",
	"field_throw": "throw",
	"throw": "throw",
	"celebrate": "celebrate",
	"slide": "run",
}

const ACTION_DURATIONS := {
	# Preserve the authored gather, stride, release, and balanced recovery. The
	# old 1.20 s override compressed the release pop and made the head/arm path
	# difficult to read from the mound camera.
	"pitch": 1.42,
	# A major-league swing reaches contact in roughly 0.23 seconds. The source
	# marker is 18/28 through the clip, so 0.36 seconds total aligns that beat.
	"swing": 0.36,
	"catch": 0.68,
	"field_throw": 0.86,
	"throw": 0.86,
	"celebrate": 1.55,
	"slide": 1.20,
}

const ACTION_MARKERS := {
	# Blender actions begin on frame 1; normalized playback therefore uses
	# (marker - 1) / (end - 1), not marker / end.
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

## Physically based surface shader with per-family procedural micro-detail.
## Burley diffuse and GGX specular carry the realistic light response; the
## detail pass layers pore-scale skin variation, a triplanar cloth weave,
## leather grain, hair strand anisotropy hints, and wood grain so close-up
## surfaces read as material rather than smooth vinyl.  Skin additionally
## gets a faint warm fresnel term approximating subsurface scattering.
const SURFACE_SHADER_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.72;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.32;
uniform float detail_scale : hint_range(1.0, 64.0) = 10.0;
uniform float detail_strength : hint_range(0.0, 0.12) = 0.025;
uniform int surface_profile = 0;
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.0;
// Real scanned micro-surface (CC0 photogrammetry maps) sampled triplanar in
// object space, so the untextured procedural meshes still get true knit,
// leather grain, and wood figure instead of synthetic noise alone.
uniform bool detail_maps_enabled = false;
uniform sampler2D detail_normal_map : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D detail_rough_map : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform float detail_map_scale = 8.0;
uniform float detail_map_normal_strength = 0.4;
uniform float detail_map_rough_strength = 0.25;

varying vec3 model_position;
varying vec3 model_normal;

void vertex() {
	model_position = VERTEX;
	model_normal = NORMAL;
}

float hash31(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453);
}

float noise3(vec3 p) {
	vec3 cell = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash31(cell);
	float n100 = hash31(cell + vec3(1.0, 0.0, 0.0));
	float n010 = hash31(cell + vec3(0.0, 1.0, 0.0));
	float n110 = hash31(cell + vec3(1.0, 1.0, 0.0));
	float n001 = hash31(cell + vec3(0.0, 0.0, 1.0));
	float n101 = hash31(cell + vec3(1.0, 0.0, 1.0));
	float n011 = hash31(cell + vec3(0.0, 1.0, 1.0));
	float n111 = hash31(cell + vec3(1.0, 1.0, 1.0));
	float lower = mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y);
	float upper = mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y);
	return mix(lower, upper, f.z);
}

float weave2(vec2 p) {
	float warp = sin(p.x * 6.2831853 * 2.0);
	float weft = sin(p.y * 6.2831853 * 2.0);
	return warp * weft;
}

float triplanar_weave(vec3 p, vec3 normal_value) {
	vec3 weights = pow(abs(normal_value), vec3(5.0));
	weights /= max(weights.x + weights.y + weights.z, 0.0001);
	return weave2(p.yz) * weights.x + weave2(p.xz) * weights.y + weave2(p.xy) * weights.z;
}

void fragment() {
	vec3 p = model_position * detail_scale;
	vec3 n = normalize(model_normal);
	float broad = noise3(p * 0.38) - 0.5;
	float micro = noise3(p * 2.7 + vec3(7.1, 3.7, 11.9)) - 0.5;
	float tonal = broad * detail_strength;
	float rough_delta = micro * detail_strength * 1.7;
	vec3 sss = vec3(0.0);

	if (surface_profile == 1) {
		// Skin: low-frequency tonal mottling, restrained pore roughness, and
		// a faint warm fresnel standing in for subsurface scattering.
		tonal = broad * detail_strength + micro * detail_strength * 0.22;
		rough_delta = micro * detail_strength * 1.25;
		float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
		sss = base_color.rgb * vec3(1.0, 0.42, 0.30) * rim * 0.045;
	} else if (surface_profile == 2) {
		// Cloth: object-space triplanar double-knit weave.
		float weave = triplanar_weave(p, n);
		tonal = weave * detail_strength * 0.42 + broad * detail_strength * 0.30;
		rough_delta = abs(weave) * detail_strength * 1.8 + micro * detail_strength * 0.35;
	} else if (surface_profile == 3) {
		// Leather: broad mottling with finer, uneven grain.
		float grain = noise3(p * 5.2 + vec3(2.0, 19.0, 5.0)) - 0.5;
		tonal = broad * detail_strength * 0.75 + grain * detail_strength * 0.35;
		rough_delta = grain * detail_strength * 1.65;
	} else if (surface_profile == 4) {
		// Hair: directional strand banding with a glossy break.
		float strand = sin((model_position.y + model_position.z * 0.34) * detail_scale * 5.0);
		tonal = strand * detail_strength * 0.30 + broad * detail_strength * 0.40;
		rough_delta = strand * detail_strength * 1.4 + micro * detail_strength * 0.5;
	} else if (surface_profile == 5) {
		// Lacquered maple: long grain lines under a clear coat.
		float grain = sin((model_position.y + broad * 0.08) * detail_scale * 7.0);
		tonal = grain * detail_strength * 0.35 + broad * detail_strength * 0.50;
		rough_delta = micro * detail_strength * 0.75;
	}

	if (detail_maps_enabled) {
		vec3 uvp = model_position * detail_map_scale;
		vec3 blend_w = pow(abs(n), vec3(4.0));
		blend_w /= max(blend_w.x + blend_w.y + blend_w.z, 0.0001);
		vec3 tx = texture(detail_normal_map, uvp.zy).xyz * 2.0 - 1.0;
		vec3 ty = texture(detail_normal_map, uvp.xz).xyz * 2.0 - 1.0;
		vec3 tz = texture(detail_normal_map, uvp.xy).xyz * 2.0 - 1.0;
		vec3 offset =
			vec3(0.0, tx.y, tx.x) * blend_w.x +
			vec3(ty.x, 0.0, ty.y) * blend_w.y +
			vec3(tz.x, tz.y, 0.0) * blend_w.z;
		vec3 detailed = normalize(n + offset * detail_map_normal_strength);
		NORMAL = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(detailed, 0.0)).xyz);
		float rough_sample =
			texture(detail_rough_map, uvp.zy).r * blend_w.x +
			texture(detail_rough_map, uvp.xz).r * blend_w.y +
			texture(detail_rough_map, uvp.xy).r * blend_w.z;
		rough_delta += (rough_sample - 0.5) * detail_map_rough_strength;
	}

	ALBEDO = clamp(base_color.rgb * (1.0 + tonal), vec3(0.0), vec3(1.0));
	ROUGHNESS = clamp(roughness_value + rough_delta, 0.05, 0.98);
	METALLIC = metallic_value;
	SPECULAR = specular_value;
	EMISSION = base_color.rgb * highlight_strength * 0.30 + sss;
}
"""

const DETAIL_MAPS := {
	"cloth": {
		"normal": preload("res://assets/textures/surface/cotton_jersey_nor_gl_1k.jpg"),
		"rough": preload("res://assets/textures/surface/cotton_jersey_rough_1k.jpg"),
		"scale": 9.0,
		"normal_strength": 0.5,
		"rough_strength": 0.22,
	},
	"leather": {
		"normal": preload("res://assets/textures/surface/brown_leather_nor_gl_1k.jpg"),
		"rough": preload("res://assets/textures/surface/brown_leather_rough_1k.jpg"),
		"scale": 6.0,
		"normal_strength": 0.55,
		"rough_strength": 0.30,
	},
	"wood": {
		"normal": preload("res://assets/textures/surface/fine_grained_wood_nor_gl_1k.jpg"),
		"rough": preload("res://assets/textures/surface/fine_grained_wood_rough_1k.jpg"),
		"scale": 4.0,
		"normal_strength": 0.30,
		"rough_strength": 0.28,
	},
}

@export_file("*.glb") var model_scene_path := MODEL_SCENE_PATH
@export var allow_voxel_fallback := true

var _spec: Dictionary = {}
var _configured := false
var _using_fallback := false
var _fallback: Node3D
var _model_root: Node3D
var _skeleton: Skeleton3D
var _animation_player: AnimationPlayer
var _meshes: Array[MeshInstance3D] = []
var _material_overrides: Array[Dictionary] = []
var _surface_shader: Shader
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
var _primary_color := Color("173f73")
var _secondary_color := Color("f1ead9")
var _accent_color := Color("e2b447")
var _pants_color := Color("e9e6da")


func _ready() -> void:
	if not _configured:
		configure({})
	elif _equipment_pending and not _using_fallback:
		_configure_modular_equipment()
	set_physics_process(true)


## Configures appearance and handedness using the same Dictionary accepted by
## VoxelBallplayer. Important keys are seed, role, number, mark, height, build,
## skin_tone, hair_color, throws, bats, primary_color, secondary_color,
## accent_color, pants_color, glove, bat, and helmet.
func configure(spec: Dictionary) -> void:
	_spec = spec.duplicate(true)
	_role = String(_spec.get("role", "fielder")).to_lower()
	_throwing_hand = _normalized_hand(String(_spec.get("throws", "right")))
	_batting_side = _normalized_hand(String(_spec.get("bats", _throwing_hand)))
	_team_mark = String(_spec.get("mark", "")).to_upper().left(1)
	_primary_color = _as_color(_spec.get("primary_color", _primary_color), _primary_color)
	_secondary_color = _as_color(_spec.get("secondary_color", _secondary_color), _secondary_color)
	_accent_color = _as_color(_spec.get("accent_color", _accent_color), _accent_color)
	_pants_color = _as_color(_spec.get("pants_color", _pants_color), _pants_color)

	_ensure_visual()
	if _using_fallback:
		_fallback.call("configure", _spec)
		_assign_character_render_layer(_fallback)
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


## Starts an authored action. `throw` is a compatibility alias for the native
## `field_throw` clip; every other listed action maps one-to-one to the GLB.
func play_action(name: String) -> void:
	var requested := name.to_lower().strip_edges()
	if _using_fallback:
		_fallback.call("play_action", String(FALLBACK_ACTION_CLIPS.get(requested, requested)))
		return
	if not ACTION_CLIPS.has(requested):
		push_warning("BallplayerActor: unknown action '%s'" % name)
		return
	if requested == _current_action and requested in ["idle", "run", "field_ready"]:
		return
	_current_action = requested
	_emitted_markers.clear()
	_play_imported_clip(requested, true)


## Holds an authored clip at one reviewed pose for broadcast staging. Gameplay
## actions still restart normally through play_action(); no simulation state or
## action marker is advanced while a pose is held.
func hold_action_pose(name: String, normalized_time := 0.0) -> void:
	var requested := name.to_lower().strip_edges()
	if _using_fallback:
		_fallback.call("play_action", String(FALLBACK_ACTION_CLIPS.get(requested, requested)))
		return
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


## Supplies world-space motion for locomotion cadence and idle/run selection.
func set_motion(velocity: Vector3) -> void:
	_motion_velocity = velocity
	if _using_fallback:
		_fallback.call("set_motion", velocity)
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


## Turns the actor toward a world-space direction while keeping it upright.
func set_facing(direction: Vector3) -> void:
	if _using_fallback:
		_fallback.call("set_facing", direction)
		return
	var planar := Vector3(direction.x, 0.0, direction.z)
	if planar.length_squared() < 0.000001:
		return
	planar = planar.normalized()
	_target_yaw = atan2(-planar.x, -planar.z)


## Returns a world-space gameplay socket. Stable names are head, chest,
## left_hand, right_hand, glove, catch, throw_hand, ball_release, bat_grip,
## bat_tip, left_foot, right_foot, and feet.
func get_socket_position(name: String) -> Vector3:
	if _using_fallback:
		return _fallback.call("get_socket_position", name) as Vector3
	var key := name.to_lower().strip_edges()
	if key == "feet":
		var left := get_socket_node("left_foot")
		var right := get_socket_node("right_foot")
		if is_instance_valid(left) and is_instance_valid(right):
			return (left.global_position + right.global_position) * 0.5
	var socket := get_socket_node(key)
	if is_instance_valid(socket):
		return socket.global_position
	push_warning("BallplayerActor: unknown socket '%s'" % name)
	return global_position


## Returns the live BoneAttachment3D for attaching props, particles, or IK
## targets. The fallback actor exposes positions only and therefore returns null.
func get_socket_node(name: String) -> Node3D:
	if _using_fallback:
		return null
	return _sockets.get(name.to_lower().strip_edges()) as Node3D


## Parents a node to a semantic socket and returns whether the attachment was
## made. By default the node snaps to the socket's local origin.
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


## Applies a restrained emissive selection treatment without mutating the GLB's
## shared embedded materials.
func set_highlighted(enabled: bool) -> void:
	_highlighted = enabled
	if _using_fallback:
		_fallback.call("set_highlighted", enabled)
		return
	for entry in _material_overrides:
		var value := entry.get("material") as Material
		if value is ShaderMaterial:
			(value as ShaderMaterial).set_shader_parameter("highlight_strength", 0.34 if enabled else 0.0)
		elif value is BaseMaterial3D:
			var pbr := value as BaseMaterial3D
			pbr.emission_enabled = enabled
			pbr.emission = pbr.albedo_color
			pbr.emission_energy_multiplier = 0.34 if enabled else 0.0
	if is_instance_valid(_equipment):
		_equipment.set_highlighted(enabled)


## Recolors stable team slots. No mesh or animation is rebuilt.
func set_uniform_colors(primary: Color, secondary: Color, accent: Color, pants := Color("e9e6da")) -> void:
	_primary_color = primary
	_secondary_color = secondary
	_accent_color = accent
	_pants_color = pants
	if _using_fallback:
		_fallback.call("set_uniform_colors", primary, secondary, accent, pants)
		return
	_apply_material_color("TEAM_Primary", primary)
	_apply_material_color("TEAM_Secondary", secondary)
	_apply_material_color("TEAM_Accent", accent)
	_apply_material_color("MAT_Pants", pants)
	_apply_material_color("MAT_PantsShadow", pants.darkened(0.22))
	if is_instance_valid(_equipment):
		_equipment.set_palette(primary, secondary, accent)
	if _highlighted:
		set_highlighted(true)


## Updates the semantic one-character team mark and its bone-attached front
## glyph without changing the base character mesh.
func set_team_mark(mark: String) -> void:
	_team_mark = mark.to_upper().left(1)
	if _using_fallback:
		_fallback.call("set_team_mark", _team_mark)
	elif is_instance_valid(_equipment):
		_equipment.set_identity(_team_mark, int(_spec.get("number", 0)))


func get_team_mark() -> String:
	return _team_mark


func get_jersey_number() -> int:
	return posmod(int(_spec.get("number", 0)), 100)


func get_throwing_hand() -> String:
	return _throwing_hand


func get_batting_side() -> String:
	return _batting_side


func get_role() -> String:
	return _role


func get_equipment_profile() -> Dictionary:
	if not is_instance_valid(_equipment):
		return {"role": _role, "mark": _team_mark, "number": get_jersey_number(), "pieces": PackedStringArray()}
	return _equipment.get_profile()


func get_equipment_piece(piece_name: String) -> Node3D:
	if not is_instance_valid(_equipment):
		return null
	return _equipment.get_piece(piece_name)


func get_current_action() -> String:
	if _using_fallback:
		return String(_fallback.call("get_current_action"))
	return _current_action


func get_generation_signature() -> String:
	if _using_fallback:
		return String(_fallback.call("get_generation_signature"))
	return "rigged-v4:%s:%s:%s:%s:%s" % [
		int(_spec.get("seed", 1)),
		_role,
		_throwing_hand,
		String(_spec.get("build", "balanced")),
		int(_spec.get("number", 0)),
	]


func is_using_fallback() -> bool:
	return _using_fallback


func get_model_kind() -> String:
	return "voxel_fallback" if _using_fallback else "rigged_glb"


func get_available_actions() -> PackedStringArray:
	return PackedStringArray(ACTION_CLIPS.keys())


func _physics_process(delta: float) -> void:
	if not _configured or _using_fallback:
		return
	rotation.y = lerp_angle(rotation.y, _target_yaw, minf(1.0, delta * 10.0))
	_update_action_markers()


func _ensure_visual() -> void:
	if is_instance_valid(_model_root) or is_instance_valid(_fallback):
		return
	if ResourceLoader.exists(model_scene_path, "PackedScene"):
		var packed := ResourceLoader.load(model_scene_path, "PackedScene") as PackedScene
		if packed != null:
			_model_root = packed.instantiate() as Node3D
			if _model_root != null:
				_model_root.name = "RiggedBallplayer"
				add_child(_model_root)
				_collect_imported_nodes(_model_root)
				if is_instance_valid(_skeleton) and is_instance_valid(_animation_player) and not _meshes.is_empty():
					_install_material_overrides()
					_install_sockets()
					_configure_animation_library()
					_animation_player.animation_finished.connect(_on_animation_finished)
					_using_fallback = false
					return
				_model_root.free()
				_model_root = null
	_install_fallback("rigged model was unavailable or missing its skeleton, meshes, or animations")


func _collect_imported_nodes(node: Node) -> void:
	if node is Skeleton3D and not is_instance_valid(_skeleton):
		_skeleton = node as Skeleton3D
	elif node is AnimationPlayer and not is_instance_valid(_animation_player):
		_animation_player = node as AnimationPlayer
	elif node is MeshInstance3D:
		_meshes.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_imported_nodes(child)


func _install_material_overrides() -> void:
	_material_overrides.clear()
	if _surface_shader == null:
		_surface_shader = Shader.new()
		_surface_shader.code = SURFACE_SHADER_CODE
	for mesh_instance in _meshes:
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var source := mesh_instance.mesh.surface_get_material(surface)
			if source == null:
				continue
			var local: Material
			if source is BaseMaterial3D and (source as BaseMaterial3D).albedo_texture != null:
				# Authored pixel-art decals (face, cap mark) keep their
				# imported nearest-filtered texture material; the cel shader
				# path would discard the texel art.
				local = source.duplicate(true) as Material
			elif source is BaseMaterial3D:
				var source_pbr := source as BaseMaterial3D
				var procedural := ShaderMaterial.new()
				procedural.shader = _surface_shader
				procedural.set_shader_parameter("base_color", source_pbr.albedo_color)
				procedural.set_shader_parameter("roughness_value", source_pbr.roughness)
				procedural.set_shader_parameter("metallic_value", source_pbr.metallic)
				var profile := _surface_profile(source.resource_name)
				procedural.set_shader_parameter("specular_value", float(profile.specular))
				procedural.set_shader_parameter("surface_profile", int(profile.profile))
				procedural.set_shader_parameter("detail_scale", float(profile.scale))
				procedural.set_shader_parameter("detail_strength", float(profile.strength))
				var family := String(profile.get("maps", ""))
				if DETAIL_MAPS.has(family):
					var maps: Dictionary = DETAIL_MAPS[family]
					procedural.set_shader_parameter("detail_maps_enabled", true)
					procedural.set_shader_parameter("detail_normal_map", maps.normal)
					procedural.set_shader_parameter("detail_rough_map", maps.rough)
					procedural.set_shader_parameter("detail_map_scale", float(maps.scale))
					procedural.set_shader_parameter("detail_map_normal_strength", float(maps.normal_strength))
					procedural.set_shader_parameter("detail_map_rough_strength", float(maps.rough_strength))
				local = procedural
			else:
				local = source.duplicate(true) as Material
			local.resource_name = source.resource_name
			local.resource_local_to_scene = true
			mesh_instance.set_surface_override_material(surface, local)
			_material_overrides.append({
				"name": source.resource_name,
				"material": local,
			})


func _surface_profile(material_name: String) -> Dictionary:
	if material_name in ["MAT_Skin", "MAT_SkinLight", "MAT_Lip"]:
		return {"profile": 1, "scale": 7.0, "strength": 0.020, "specular": 0.22}
	if material_name.begins_with("TEAM_") or material_name in ["MAT_Pants", "MAT_PantsShadow"]:
		return {"profile": 2, "scale": 13.0, "strength": 0.022, "specular": 0.18, "maps": "cloth"}
	if material_name.begins_with("MAT_Leather") or material_name in ["MAT_Belt", "MAT_Cleat"]:
		return {"profile": 3, "scale": 8.0, "strength": 0.042, "specular": 0.30, "maps": "leather"}
	if material_name.begins_with("MAT_Hair"):
		return {"profile": 4, "scale": 11.0, "strength": 0.030, "specular": 0.20}
	if material_name == "MAT_Bat":
		return {"profile": 5, "scale": 7.0, "strength": 0.032, "specular": 0.36, "maps": "wood"}
	return {"profile": 0, "scale": 9.0, "strength": 0.018, "specular": 0.26}


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


func _install_fallback(reason: String) -> void:
	if not allow_voxel_fallback:
		push_error("BallplayerActor: %s and fallback is disabled" % reason)
		return
	_using_fallback = true
	_fallback = FALLBACK_SCRIPT.new() as Node3D
	_fallback.name = "VoxelFallback"
	add_child(_fallback)
	_fallback.connect("action_started", Callable(self, "_on_fallback_action_started"))
	_fallback.connect("action_marker", Callable(self, "_on_fallback_action_marker"))
	_fallback.connect("action_finished", Callable(self, "_on_fallback_action_finished"))
	push_warning("BallplayerActor: %s; using VoxelBallplayer" % reason)


func _apply_dimensions_and_handedness() -> void:
	var seed := int(_spec.get("seed", 1))
	# Keep roster variety without letting the telephoto mound view turn shorter
	# power builds into toy-like, shoulder-dominant figures. The authored mesh
	# retains its musculature; these presentation scales only tune the range of
	# silhouettes seen during play.
	var sampled_height := 1.76 + float(posmod(seed * 48271, 1000)) / 1000.0 * 0.18
	var height := clampf(float(_spec.get("height", sampled_height)), 1.55, 2.05)
	var build := String(_spec.get("build", "balanced")).to_lower()
	var width_scale: float = {"speed": 0.91, "balanced": 0.96, "power": 1.02}.get(build, 0.96)
	var mirror := -1.0 if _hand_for_action("idle") == "left" else 1.0
	# 1.89 m is the authored nominal height of the realistic v11 asset.
	_model_root.scale = Vector3(width_scale * mirror, height / 1.89, width_scale)
	var head_index := _skeleton.find_bone("head") if is_instance_valid(_skeleton) else -1
	if head_index >= 0:
		_skeleton.set_bone_pose_scale(head_index, Vector3.ONE * BROADCAST_HEAD_SCALE)


func _apply_equipment_visibility() -> void:
	var show_bat := bool(_spec.get("bat", _role == "batter"))
	var show_glove := bool(_spec.get("glove", _role not in ["batter", "umpire"]))
	var helmet_default := _role in ["batter", "hitter", "slugger"]
	var hide_cap := bool(_spec.get("helmet", helmet_default)) or _role in ["catcher", "umpire"]
	for mesh_instance in _meshes:
		if mesh_instance.name == "Bat_Skinned":
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
	_equipment.sync_identity_orientation()
	_assign_character_render_layer(_equipment)
	_equipment_pending = false


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
	_apply_material_color("MAT_SkinLight", skin.lightened(0.18))
	_apply_material_color("MAT_SkinShadow", skin.darkened(0.30))
	_apply_material_color("MAT_Hair", hair)
	_apply_material_color("MAT_HairHighlight", hair.lightened(0.18))


func _apply_material_color(material_name: String, color: Color) -> void:
	for entry in _material_overrides:
		if String(entry.get("name", "")) != material_name:
			continue
		var value := entry.get("material") as Material
		if value is ShaderMaterial:
			(value as ShaderMaterial).set_shader_parameter("base_color", color)
		elif value is BaseMaterial3D:
			(value as BaseMaterial3D).albedo_color = color


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
	var blend_time := 0.10
	if action == "pitch" or String(_animation_player.current_animation) == "pitch":
		blend_time = 0.18
	_animation_player.play(clip_name, blend_time, speed)
	if emit_started:
		action_started.emit(action)


func _apply_action_handedness(action: String) -> void:
	if not is_instance_valid(_model_root):
		return
	var magnitude := absf(_model_root.scale.x)
	_model_root.scale.x = -magnitude if _hand_for_action(action) == "left" else magnitude
	if is_instance_valid(_equipment):
		_equipment.sync_identity_orientation()


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


func _on_fallback_action_started(action_name: String) -> void:
	action_started.emit(action_name)


func _on_fallback_action_marker(action_name: String, marker_name: String) -> void:
	action_marker.emit(action_name, marker_name)


func _on_fallback_action_finished(action_name: String) -> void:
	action_finished.emit(action_name)


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
