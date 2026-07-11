@tool
class_name VoxelBallplayer
extends Node3D

## Deterministic, procedural 3D baseball character built from engine primitives.
##
## The rig intentionally uses articulated Node3D pivots instead of imported skinning.
## This keeps the source text-first, preserves hard voxel joints, and makes every pose
## inspectable and editable by an agent without Blender or binary resources.

signal action_started(action_name: String)
signal action_marker(action_name: String, marker_name: String)
signal action_finished(action_name: String)

const ACTIONS := {
	"idle": 0.0,
	"run": 0.0,
	"pitch": 1.20,
	"swing": 0.82,
	"catch": 0.68,
	"throw": 0.86,
	"celebrate": 1.55,
}

const ACTION_MARKERS := {
	"pitch": {"ball_release": 0.72},
	"swing": {"bat_contact": 0.64},
	"catch": {"glove_contact": 0.58},
	"throw": {"ball_release": 0.61},
}

const SKIN_TONES := [
	Color("f2c9a2"),
	Color("dfa66e"),
	Color("bd7d4b"),
	Color("965b36"),
	Color("704129"),
	Color("4d2b20"),
]

const HAIR_TONES := [
	Color("241b18"),
	Color("49301f"),
	Color("75472a"),
	Color("b18142"),
	Color("c7c1b6"),
	Color("8a3522"),
]

const GLYPHS := {
	"0": ["111", "101", "101", "101", "111"],
	"1": ["010", "110", "010", "010", "111"],
	"2": ["111", "001", "111", "100", "111"],
	"3": ["111", "001", "111", "001", "111"],
	"4": ["101", "101", "111", "001", "001"],
	"5": ["111", "100", "111", "001", "111"],
	"6": ["111", "100", "111", "101", "111"],
	"7": ["111", "001", "001", "001", "001"],
	"8": ["111", "101", "111", "101", "111"],
	"9": ["111", "101", "111", "001", "111"],
	"A": ["010", "101", "111", "101", "101"],
	"B": ["110", "101", "110", "101", "110"],
	"C": ["111", "100", "100", "100", "111"],
	"D": ["110", "101", "101", "101", "110"],
	"F": ["111", "100", "110", "100", "100"],
	"G": ["111", "100", "101", "101", "111"],
	"H": ["101", "101", "111", "101", "101"],
	"K": ["101", "101", "110", "101", "101"],
	"L": ["100", "100", "100", "100", "111"],
	"M": ["101", "111", "111", "101", "101"],
	"N": ["101", "111", "111", "111", "101"],
	"P": ["110", "101", "110", "100", "100"],
	"R": ["110", "101", "110", "101", "101"],
	"S": ["111", "100", "111", "001", "111"],
	"T": ["111", "010", "010", "010", "010"],
	"V": ["101", "101", "101", "101", "010"],
	"X": ["101", "101", "010", "101", "101"],
	"Y": ["101", "101", "010", "010", "010"],
}

const VOXEL_SHADER_CODE := """
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(1.0);
uniform float roughness_value : hint_range(0.0, 1.0) = 0.82;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float highlight_strength : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	ALBEDO = base_color.rgb;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	EMISSION = base_color.rgb * highlight_strength * 0.38;
}

void light() {
	float ndl = max(dot(NORMAL, LIGHT), 0.0);
	float band = ndl > 0.68 ? 1.0 : (ndl > 0.28 ? 0.72 : 0.48);
	vec3 warm_light = LIGHT_COLOR * vec3(1.02, 1.0, 0.96);
	DIFFUSE_LIGHT += ALBEDO * warm_light * ATTENUATION * band;
	float rim = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0) * 0.10;
	DIFFUSE_LIGHT += ALBEDO * rim * ATTENUATION;
}
"""

var _spec: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _shader: Shader
var _model_root: Node3D
var _joints: Dictionary = {}
var _rest_rotations: Dictionary = {}
var _sockets: Dictionary = {}
var _materials: Dictionary = {}
var _face_parts: Dictionary = {}
var _dimensions: Dictionary = {}

var _configured := false
var _current_action := "idle"
var _action_time := 0.0
var _emitted_markers: Dictionary = {}
var _motion_velocity := Vector3.ZERO
var _target_yaw := 0.0
var _highlighted := false
var _hips_base_y := 0.92
var _role := "fielder"
var _throwing_hand := "right"
var _batting_side := "right"


func _ready() -> void:
	if not _configured:
		configure({})
	set_physics_process(not Engine.is_editor_hint())


## Rebuilds the player deterministically from a text-friendly Dictionary.
## Supported keys include seed, role, number, mark, height, build, skin_tone,
## hair_color, hair_style, facial_hair, throws, bats, primary_color,
## secondary_color, accent_color, pants_color, helmet, glove, and bat.
func configure(spec: Dictionary) -> void:
	_spec = spec.duplicate(true)
	var seed := int(_spec.get("seed", 1))
	_rng.seed = seed
	_role = String(_spec.get("role", "fielder")).to_lower()
	_throwing_hand = _normalized_hand(String(_spec.get("throws", "right")))
	_batting_side = _normalized_hand(String(_spec.get("bats", _throwing_hand)))

	_clear_generated_model()
	_materials.clear()
	_joints.clear()
	_rest_rotations.clear()
	_sockets.clear()
	_face_parts.clear()
	_emitted_markers.clear()

	_shader = Shader.new()
	_shader.code = VOXEL_SHADER_CODE
	_resolve_dimensions()
	_create_palette()
	_build_character()
	_current_action = "idle"
	_action_time = 0.0
	_configured = true
	set_highlighted(_highlighted)


## Starts a named procedural action. One-shot actions return to idle/run.
func play_action(name: String) -> void:
	var action := name.to_lower().strip_edges()
	if not ACTIONS.has(action):
		push_warning("VoxelBallplayer: unknown action '%s'" % name)
		return
	if _current_action == action and action in ["idle", "run"]:
		return
	_current_action = action
	_action_time = 0.0
	_emitted_markers.clear()
	action_started.emit(action)


## Supplies world-space motion for locomotion cadence and automatic idle/run.
func set_motion(velocity: Vector3) -> void:
	_motion_velocity = velocity
	if _current_action in ["idle", "run"]:
		var wanted := "run" if Vector2(velocity.x, velocity.z).length() > 0.12 else "idle"
		if wanted != _current_action:
			play_action(wanted)


## Rotates the model toward a world-space direction while keeping it upright.
func set_facing(direction: Vector3) -> void:
	var planar := Vector3(direction.x, 0.0, direction.z)
	if planar.length_squared() < 0.000001:
		return
	planar = planar.normalized()
	_target_yaw = atan2(-planar.x, -planar.z)


## Returns a world-space socket position. Stable sockets include head, chest,
## left_hand, right_hand, glove, catch, throw_hand, ball_release, bat_grip,
## bat_tip, left_foot, right_foot, and feet.
func get_socket_position(name: String) -> Vector3:
	var key := name.to_lower().strip_edges()
	var socket: Node3D = _sockets.get(key)
	if is_instance_valid(socket):
		return socket.global_position
	push_warning("VoxelBallplayer: unknown socket '%s'" % name)
	return global_position


## Applies a restrained emissive selection treatment to every generated material.
func set_highlighted(enabled: bool) -> void:
	_highlighted = enabled
	var strength := 0.52 if enabled else 0.0
	for material in _materials.values():
		if material is ShaderMaterial:
			material.set_shader_parameter("highlight_strength", strength)


## Recolors a compiled player without rebuilding its several hundred geometry
## nodes. Half-inning uniform swaps are therefore instant and hitch-free.
func set_uniform_colors(primary: Color, secondary: Color, accent: Color, pants := Color("e9e6da")) -> void:
	_set_material_color("primary", primary)
	_set_material_color("primary_dark", primary.darkened(0.27))
	_set_material_color("secondary", secondary)
	_set_material_color("secondary_shadow", secondary.darkened(0.14))
	_set_material_color("accent", accent)
	_set_material_color("pants", pants)
	_set_material_color("pants_shadow", pants.darkened(0.16))


## Rebuilds only the tiny raised chest monogram; body, rig, equipment, face,
## and back number remain untouched.
func set_team_mark(mark: String) -> void:
	var normalized := mark.to_upper().left(1)
	if normalized.is_empty() or not GLYPHS.has(normalized):
		return
	var spine: Node3D = _joints.get("spine")
	if not is_instance_valid(spine):
		return
	for child in spine.get_children():
		if String(child.name).begins_with("Glyph") and child.position.z < 0.0:
			child.free()
	var torso_h := float(_dimensions.torso_h)
	var torso_depth := float(_dimensions.torso_depth)
	var chest_size := Vector3(float(_dimensions.shoulder_width) * 0.84, torso_h * 0.72, torso_depth)
	_add_glyph(spine, normalized, Vector3(-chest_size.x * 0.22, chest_size.y * 0.60, -torso_depth * 0.515), chest_size.y * 0.052, "primary", false)
	_spec["mark"] = normalized


func _set_material_color(key: String, color: Color) -> void:
	var material: ShaderMaterial = _materials.get(key)
	if material != null:
		material.set_shader_parameter("base_color", color)


func get_current_action() -> String:
	return _current_action


func get_generation_signature() -> String:
	return "%s:%s:%s:%s:%s" % [
		int(_spec.get("seed", 1)),
		_role,
		_throwing_hand,
		_dimensions.get("build", "balanced"),
		int(_spec.get("number", 0)),
	]


func _physics_process(delta: float) -> void:
	if not _configured or not is_instance_valid(_model_root):
		return
	rotation.y = lerp_angle(rotation.y, _target_yaw, minf(1.0, delta * 10.0))
	_advance_action(delta)
	_apply_current_pose(delta)


func _advance_action(delta: float) -> void:
	var previous_time := _action_time
	_action_time += delta
	var duration := float(ACTIONS.get(_current_action, 0.0))
	if duration > 0.0:
		var previous_u := clampf(previous_time / duration, 0.0, 1.0)
		var current_u := clampf(_action_time / duration, 0.0, 1.0)
		var markers: Dictionary = ACTION_MARKERS.get(_current_action, {})
		for marker in markers:
			var marker_u := float(markers[marker])
			if previous_u < marker_u and current_u >= marker_u and not _emitted_markers.has(marker):
				_emitted_markers[marker] = true
				action_marker.emit(_current_action, String(marker))
		if _action_time >= duration:
			var finished := _current_action
			action_finished.emit(finished)
			var next := "run" if Vector2(_motion_velocity.x, _motion_velocity.z).length() > 0.12 else "idle"
			_current_action = next
			_action_time = 0.0
			_emitted_markers.clear()


func _apply_current_pose(delta: float) -> void:
	var pose := _evaluate_pose(_current_action, _action_time)
	var rotations: Dictionary = pose.get("rotations", {})
	var blend_speed := 18.0 if _current_action in ["pitch", "swing", "throw"] else 12.0
	var weight := clampf(delta * blend_speed, 0.0, 1.0)
	for key in _joints:
		var joint: Node3D = _joints[key]
		var rest: Vector3 = _rest_rotations.get(key, Vector3.ZERO)
		var offset: Vector3 = rotations.get(key, Vector3.ZERO)
		var target := Quaternion.from_euler(rest + offset)
		joint.quaternion = joint.quaternion.slerp(target, weight).normalized()

	var hips: Node3D = _joints.get("hips")
	if is_instance_valid(hips):
		var desired := hips.position
		desired.y = _hips_base_y + float(pose.get("bob", 0.0))
		desired.x = float(pose.get("shift_x", 0.0))
		desired.z = float(pose.get("shift_z", 0.0))
		hips.position = hips.position.lerp(desired, weight)

	_update_face(String(pose.get("expression", "neutral")), weight)


func _evaluate_pose(action: String, time: float) -> Dictionary:
	match action:
		"run":
			return _pose_run(time)
		"pitch":
			return _pose_pitch(time / float(ACTIONS.pitch))
		"swing":
			return _pose_swing(time / float(ACTIONS.swing))
		"catch":
			return _pose_catch(time / float(ACTIONS.catch))
		"throw":
			return _pose_throw(time / float(ACTIONS.throw))
		"celebrate":
			return _pose_celebrate(time / float(ACTIONS.celebrate))
		_:
			return _pose_idle(time)


func _pose_idle(time: float) -> Dictionary:
	var breath := sin(time * TAU / 2.8)
	var settle := sin(time * TAU / 4.7 + 0.8)
	return {
		"bob": breath * 0.006,
		"rotations": {
			"spine": Vector3(_rad(breath * 1.4), _rad(settle * 1.3), 0.0),
			"head": Vector3(_rad(-breath * 0.8), _rad(settle * 2.4), 0.0),
			"left_upper_arm": Vector3(_rad(2.0 + breath * 1.5), 0.0, 0.0),
			"right_upper_arm": Vector3(_rad(2.0 - breath * 1.5), 0.0, 0.0),
		},
		"expression": "neutral",
	}


func _pose_run(time: float) -> Dictionary:
	var speed := clampf(Vector2(_motion_velocity.x, _motion_velocity.z).length(), 0.8, 7.0)
	var phase := time * (4.5 + speed * 0.7)
	var stride := sin(phase)
	var opposite := sin(phase + PI)
	var left_knee := maxf(0.0, -stride) * 55.0
	var right_knee := maxf(0.0, -opposite) * 55.0
	return {
		"bob": absf(cos(phase)) * 0.035,
		"rotations": {
			"hips": Vector3(_rad(-5.0), _rad(stride * 4.0), _rad(stride * 2.0)),
			"spine": Vector3(_rad(8.0), _rad(-stride * 7.0), 0.0),
			"head": Vector3(_rad(-4.0), 0.0, 0.0),
			"left_thigh": Vector3(_rad(stride * 39.0), 0.0, 0.0),
			"right_thigh": Vector3(_rad(opposite * 39.0), 0.0, 0.0),
			"left_knee": Vector3(_rad(left_knee), 0.0, 0.0),
			"right_knee": Vector3(_rad(right_knee), 0.0, 0.0),
			"left_ankle": Vector3(_rad(-stride * 13.0), 0.0, 0.0),
			"right_ankle": Vector3(_rad(-opposite * 13.0), 0.0, 0.0),
			"left_upper_arm": Vector3(_rad(opposite * 31.0), 0.0, _rad(-3.0)),
			"right_upper_arm": Vector3(_rad(stride * 31.0), 0.0, _rad(3.0)),
			"left_elbow": Vector3(_rad(18.0 + maxf(0.0, stride) * 28.0), 0.0, 0.0),
			"right_elbow": Vector3(_rad(18.0 + maxf(0.0, opposite) * 28.0), 0.0, 0.0),
		},
		"expression": "grit",
	}


func _pose_pitch(u: float) -> Dictionary:
	u = clampf(u, 0.0, 1.0)
	var mirror := -1.0 if _throwing_hand == "left" else 1.0
	var lift := _sample_scalar([[0.0, 0.0], [0.18, 0.0], [0.37, 68.0], [0.52, 76.0], [0.72, -18.0], [1.0, -8.0]], u)
	var knee := _sample_scalar([[0.0, 0.0], [0.28, 0.0], [0.43, -86.0], [0.58, -58.0], [0.78, 18.0], [1.0, 8.0]], u)
	var drive_leg := _sample_scalar([[0.0, 0.0], [0.45, -8.0], [0.72, 22.0], [1.0, 14.0]], u)
	var twist := _sample_scalar([[0.0, 0.0], [0.42, -34.0], [0.69, 20.0], [0.82, 38.0], [1.0, 16.0]], u) * mirror
	var throwing_arm_x := _sample_scalar([[0.0, 0.0], [0.32, -18.0], [0.50, -58.0], [0.67, 82.0], [0.74, 116.0], [1.0, 52.0]], u)
	var throwing_arm_z := _sample_scalar([[0.0, 0.0], [0.45, 64.0], [0.67, 82.0], [0.76, 18.0], [1.0, -10.0]], u) * mirror
	var throwing_elbow := _sample_scalar([[0.0, 8.0], [0.50, 104.0], [0.68, 82.0], [0.75, 12.0], [1.0, 32.0]], u)
	var glove_arm_x := _sample_scalar([[0.0, 0.0], [0.35, 58.0], [0.62, 84.0], [0.78, 36.0], [1.0, 12.0]], u)
	var front_leg := "left_thigh" if _throwing_hand == "right" else "right_thigh"
	var front_knee := "left_knee" if _throwing_hand == "right" else "right_knee"
	var back_leg := "right_thigh" if _throwing_hand == "right" else "left_thigh"
	var throw_arm := "right_upper_arm" if _throwing_hand == "right" else "left_upper_arm"
	var throw_elbow := "right_elbow" if _throwing_hand == "right" else "left_elbow"
	var glove_arm := "left_upper_arm" if _throwing_hand == "right" else "right_upper_arm"
	var glove_elbow := "left_elbow" if _throwing_hand == "right" else "right_elbow"
	var rotations := {
		"hips": Vector3(_rad(-6.0 + absf(twist) * 0.08), _rad(twist * 0.52), _rad(-mirror * lift * 0.05)),
		"spine": Vector3(_rad(-5.0 + maxf(0.0, u - 0.68) * 48.0), _rad(twist), _rad(-mirror * 5.0)),
		"head": Vector3(_rad(4.0), _rad(-twist * 0.38), _rad(mirror * 2.0)),
		front_leg: Vector3(_rad(lift), 0.0, _rad(-mirror * 4.0)),
		front_knee: Vector3(_rad(knee), 0.0, 0.0),
		back_leg: Vector3(_rad(drive_leg), 0.0, _rad(mirror * 3.0)),
		throw_arm: Vector3(_rad(throwing_arm_x), _rad(-mirror * 18.0), _rad(throwing_arm_z)),
		throw_elbow: Vector3(_rad(throwing_elbow), 0.0, 0.0),
		glove_arm: Vector3(_rad(glove_arm_x), _rad(mirror * 8.0), _rad(-mirror * 18.0)),
		glove_elbow: Vector3(_rad(48.0), 0.0, 0.0),
	}
	return {
		"bob": _sample_scalar([[0.0, 0.0], [0.45, 0.09], [0.73, 0.015], [1.0, 0.0]], u),
		"shift_z": _sample_scalar([[0.0, 0.0], [0.50, 0.0], [0.78, -0.16], [1.0, -0.10]], u),
		"rotations": rotations,
		"expression": "grit",
	}


func _pose_swing(u: float) -> Dictionary:
	u = clampf(u, 0.0, 1.0)
	var mirror := -1.0 if _batting_side == "left" else 1.0
	var twist := _sample_scalar([[0.0, -20.0], [0.30, -34.0], [0.52, -18.0], [0.64, 18.0], [0.82, 46.0], [1.0, 58.0]], u) * mirror
	var lead_leg := "right_thigh" if _batting_side == "right" else "left_thigh"
	var trail_leg := "left_thigh" if _batting_side == "right" else "right_thigh"
	var arm_x := _sample_scalar([[0.0, 44.0], [0.35, 58.0], [0.55, 78.0], [0.68, 96.0], [1.0, 64.0]], u)
	var arm_z := _sample_scalar([[0.0, 18.0], [0.45, 34.0], [0.65, -16.0], [1.0, -42.0]], u) * mirror
	var bat_roll := _sample_scalar([[0.0, -16.0], [0.38, -34.0], [0.64, 74.0], [0.80, 132.0], [1.0, 168.0]], u) * mirror
	return {
		"bob": _sample_scalar([[0.0, 0.0], [0.45, -0.035], [0.67, 0.018], [1.0, 0.0]], u),
		"shift_x": _sample_scalar([[0.0, 0.0], [0.55, mirror * 0.02], [0.78, -mirror * 0.08], [1.0, -mirror * 0.05]], u),
		"rotations": {
			"hips": Vector3(_rad(8.0), _rad(twist * 0.65), _rad(-mirror * 3.0)),
			"spine": Vector3(_rad(4.0), _rad(twist), _rad(mirror * 4.0)),
			"head": Vector3(_rad(-2.0), _rad(-twist * 0.72), 0.0),
			lead_leg: Vector3(_rad(-8.0), _rad(-mirror * 7.0), _rad(-mirror * 4.0)),
			trail_leg: Vector3(_rad(10.0), _rad(mirror * 5.0), _rad(mirror * 3.0)),
			"left_upper_arm": Vector3(_rad(arm_x), _rad(-mirror * 18.0), _rad(-arm_z)),
			"right_upper_arm": Vector3(_rad(arm_x + 8.0), _rad(mirror * 12.0), _rad(arm_z)),
			"left_elbow": Vector3(_rad(34.0 - u * 20.0), _rad(-mirror * 8.0), 0.0),
			"right_elbow": Vector3(_rad(54.0 - u * 34.0), _rad(mirror * 8.0), 0.0),
			"bat": Vector3(_rad(8.0), _rad(bat_roll), _rad(mirror * -18.0)),
		},
		"expression": "grit",
	}


func _pose_catch(u: float) -> Dictionary:
	u = clampf(u, 0.0, 1.0)
	var glove_left := _throwing_hand == "right"
	var glove_arm := "left_upper_arm" if glove_left else "right_upper_arm"
	var glove_elbow := "left_elbow" if glove_left else "right_elbow"
	var other_arm := "right_upper_arm" if glove_left else "left_upper_arm"
	var mirror := -1.0 if glove_left else 1.0
	var reach := _sample_scalar([[0.0, 18.0], [0.32, 72.0], [0.58, 116.0], [0.76, 94.0], [1.0, 42.0]], u)
	return {
		"bob": _sample_scalar([[0.0, 0.0], [0.52, -0.10], [0.78, -0.06], [1.0, 0.0]], u),
		"rotations": {
			"hips": Vector3(_rad(20.0), 0.0, _rad(mirror * 4.0)),
			"spine": Vector3(_rad(-18.0), _rad(mirror * 8.0), _rad(mirror * 5.0)),
			"head": Vector3(_rad(-16.0), _rad(-mirror * 6.0), 0.0),
			glove_arm: Vector3(_rad(reach), _rad(-mirror * 8.0), _rad(-mirror * 22.0)),
			glove_elbow: Vector3(_rad(18.0), 0.0, 0.0),
			other_arm: Vector3(_rad(42.0), 0.0, _rad(mirror * 12.0)),
			"left_thigh": Vector3(_rad(-22.0), 0.0, _rad(-4.0)),
			"right_thigh": Vector3(_rad(-22.0), 0.0, _rad(4.0)),
			"left_knee": Vector3(_rad(42.0), 0.0, 0.0),
			"right_knee": Vector3(_rad(42.0), 0.0, 0.0),
		},
		"expression": "surprised" if u < 0.66 else "happy",
	}


func _pose_throw(u: float) -> Dictionary:
	u = clampf(u, 0.0, 1.0)
	var mirror := -1.0 if _throwing_hand == "left" else 1.0
	var throw_arm := "left_upper_arm" if _throwing_hand == "left" else "right_upper_arm"
	var throw_elbow := "left_elbow" if _throwing_hand == "left" else "right_elbow"
	var glove_arm := "right_upper_arm" if _throwing_hand == "left" else "left_upper_arm"
	var wind := _sample_scalar([[0.0, 18.0], [0.35, -62.0], [0.52, -78.0], [0.64, 108.0], [0.78, 126.0], [1.0, 54.0]], u)
	var elbow := _sample_scalar([[0.0, 18.0], [0.42, 108.0], [0.58, 72.0], [0.66, 8.0], [1.0, 34.0]], u)
	var twist := _sample_scalar([[0.0, -10.0], [0.44, -38.0], [0.65, 16.0], [0.82, 42.0], [1.0, 18.0]], u) * mirror
	return {
		"rotations": {
			"hips": Vector3(_rad(7.0), _rad(twist * 0.55), 0.0),
			"spine": Vector3(_rad(5.0 + u * 8.0), _rad(twist), _rad(-mirror * 4.0)),
			"head": Vector3(_rad(-2.0), _rad(-twist * 0.45), 0.0),
			throw_arm: Vector3(_rad(wind), _rad(-mirror * 14.0), _rad(mirror * 62.0)),
			throw_elbow: Vector3(_rad(elbow), 0.0, 0.0),
			glove_arm: Vector3(_rad(58.0), 0.0, _rad(-mirror * 20.0)),
			"left_thigh": Vector3(_rad(-u * 10.0), 0.0, 0.0),
			"right_thigh": Vector3(_rad(u * 10.0), 0.0, 0.0),
		},
		"expression": "grit",
	}


func _pose_celebrate(u: float) -> Dictionary:
	u = clampf(u, 0.0, 1.0)
	var rise := sin(clampf(u / 0.28, 0.0, 1.0) * PI * 0.5)
	var bounce := absf(sin(u * TAU * 2.0)) * (1.0 - u) * 0.08
	return {
		"bob": rise * 0.05 + bounce,
		"rotations": {
			"hips": Vector3(_rad(-5.0), _rad(sin(u * TAU) * 12.0), 0.0),
			"spine": Vector3(_rad(-10.0 * rise), 0.0, 0.0),
			"head": Vector3(_rad(-12.0 * rise), 0.0, 0.0),
			"left_upper_arm": Vector3(_rad(155.0 * rise), 0.0, _rad(-24.0 * rise)),
			"right_upper_arm": Vector3(_rad(155.0 * rise), 0.0, _rad(24.0 * rise)),
			"left_elbow": Vector3(_rad(12.0), 0.0, 0.0),
			"right_elbow": Vector3(_rad(12.0), 0.0, 0.0),
			"left_thigh": Vector3(_rad(-bounce * 180.0), 0.0, 0.0),
			"right_thigh": Vector3(_rad(-bounce * 180.0), 0.0, 0.0),
		},
		"expression": "happy",
	}


func _sample_scalar(keys: Array, u: float) -> float:
	if keys.is_empty():
		return 0.0
	if u <= float(keys[0][0]):
		return float(keys[0][1])
	for index in range(1, keys.size()):
		var right: Array = keys[index]
		if u <= float(right[0]):
			var left: Array = keys[index - 1]
			var span := maxf(0.000001, float(right[0]) - float(left[0]))
			var t := clampf((u - float(left[0])) / span, 0.0, 1.0)
			t = t * t * (3.0 - 2.0 * t)
			return lerpf(float(left[1]), float(right[1]), t)
	return float(keys[-1][1])


func _resolve_dimensions() -> void:
	var build_names := ["speed", "balanced", "power"]
	var build := String(_spec.get("build", build_names[int(_rng.randi() % build_names.size())])).to_lower()
	if build not in build_names:
		build = "balanced"
	var height := clampf(float(_spec.get("height", _rng.randf_range(1.68, 1.91))), 1.55, 2.05)
	var build_width: float = {"speed": 0.90, "balanced": 1.0, "power": 1.14}[build]
	var torso_h := height * 0.285
	var upper_leg := height * 0.245
	var lower_leg := height * 0.225
	var upper_arm := height * 0.158
	var forearm := height * 0.145
	var head_h := height * 0.145
	var shoe_h := height * 0.055
	_hips_base_y = shoe_h + lower_leg + upper_leg
	_dimensions = {
		"build": build,
		"height": height,
		"width_scale": build_width,
		"hip_width": height * 0.16 * build_width,
		"shoulder_width": height * 0.235 * build_width,
		"torso_h": torso_h,
		"torso_depth": height * 0.13 * (0.96 + (build_width - 1.0) * 0.55),
		"upper_leg": upper_leg,
		"lower_leg": lower_leg,
		"upper_arm": upper_arm,
		"forearm": forearm,
		"head_h": head_h,
		"head_w": height * 0.13 * (0.98 + (build_width - 1.0) * 0.20),
		"head_d": height * 0.125,
		"shoe_h": shoe_h,
	}


func _create_palette() -> void:
	var skin_default: Color = SKIN_TONES[int(_rng.randi() % SKIN_TONES.size())]
	var hair_default: Color = HAIR_TONES[int(_rng.randi() % HAIR_TONES.size())]
	var primary := _as_color(_spec.get("primary_color", Color("1d4f9c")), Color("1d4f9c"))
	var secondary := _as_color(_spec.get("secondary_color", Color("f0eee6")), Color("f0eee6"))
	var accent := _as_color(_spec.get("accent_color", Color("cf3341")), Color("cf3341"))
	var pants := _as_color(_spec.get("pants_color", Color("e4e3dc")), Color("e4e3dc"))
	var skin := _as_color(_spec.get("skin_tone", skin_default), skin_default)
	var hair := _as_color(_spec.get("hair_color", hair_default), hair_default)
	_register_material("skin", skin, 0.88)
	_register_material("skin_shadow", skin.darkened(0.18), 0.90)
	_register_material("hair", hair, 0.94)
	_register_material("primary", primary, 0.82)
	_register_material("primary_dark", primary.darkened(0.27), 0.86)
	_register_material("secondary", secondary, 0.86)
	_register_material("secondary_shadow", secondary.darkened(0.14), 0.88)
	_register_material("accent", accent, 0.80)
	_register_material("pants", pants, 0.87)
	_register_material("pants_shadow", pants.darkened(0.16), 0.89)
	_register_material("ink", Color("171a22"), 0.78)
	_register_material("eye", Color("f7f3df"), 0.72)
	_register_material("leather", _as_color(_spec.get("glove_color", Color("75451f")), Color("75451f")), 0.94)
	_register_material("leather_dark", _as_color(_spec.get("glove_color", Color("75451f")), Color("75451f")).darkened(0.25), 0.96)
	_register_material("wood", _as_color(_spec.get("bat_color", Color("c58a3a")), Color("c58a3a")), 0.68)
	_register_material("wood_dark", _as_color(_spec.get("bat_color", Color("c58a3a")), Color("c58a3a")).darkened(0.25), 0.76)
	_register_material("metal", Color("9baab5"), 0.34, 0.55)


func _register_material(key: String, color: Color, roughness: float, metallic := 0.0) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.resource_name = "Voxel_%s" % key
	material.resource_local_to_scene = true
	material.shader = _shader
	material.set_shader_parameter("base_color", color)
	material.set_shader_parameter("roughness_value", roughness)
	material.set_shader_parameter("metallic_value", metallic)
	material.set_shader_parameter("highlight_strength", 0.52 if _highlighted else 0.0)
	_materials[key] = material
	return material


func _build_character() -> void:
	_model_root = Node3D.new()
	_model_root.name = "GeneratedVoxelRig"
	add_child(_model_root)

	var hip_width := float(_dimensions.hip_width)
	var shoulder_width := float(_dimensions.shoulder_width)
	var torso_h := float(_dimensions.torso_h)
	var torso_depth := float(_dimensions.torso_depth)
	var upper_leg := float(_dimensions.upper_leg)
	var lower_leg := float(_dimensions.lower_leg)
	var upper_arm := float(_dimensions.upper_arm)
	var forearm := float(_dimensions.forearm)
	var shoe_h := float(_dimensions.shoe_h)
	var width_scale := float(_dimensions.width_scale)

	var hips := _joint("hips", _model_root, Vector3(0.0, _hips_base_y, 0.0))
	var pelvis_size := Vector3(hip_width * 0.92, torso_h * 0.19, torso_depth * 0.92)
	_box(hips, "Pelvis", pelvis_size, Vector3(0.0, pelvis_size.y * 0.18, 0.0), "pants_shadow")
	_box(hips, "Belt", Vector3(hip_width * 0.96, torso_h * 0.055, torso_depth * 0.96), Vector3(0.0, torso_h * 0.15, 0.0), "primary_dark")
	_box(hips, "Buckle", Vector3(torso_h * 0.06, torso_h * 0.045, 0.018), Vector3(0.0, torso_h * 0.15, -torso_depth * 0.50), "accent")

	var spine := _joint("spine", hips, Vector3(0.0, torso_h * 0.13, 0.0))
	var waist_w := shoulder_width * 0.67
	var chest_size := Vector3(shoulder_width * 0.84, torso_h * 0.72, torso_depth)
	_box(spine, "JerseyTorso", chest_size, Vector3(0.0, chest_size.y * 0.52, 0.0), "secondary")
	_box(spine, "JerseyShoulders", Vector3(shoulder_width, torso_h * 0.18, torso_depth * 1.03), Vector3(0.0, torso_h * 0.72, 0.0), "primary")
	_box(spine, "JerseyWaist", Vector3(waist_w, torso_h * 0.11, torso_depth * 0.93), Vector3(0.0, torso_h * 0.13, 0.0), "secondary_shadow")
	_box(spine, "Collar", Vector3(torso_h * 0.19, torso_h * 0.045, torso_depth * 1.02), Vector3(0.0, torso_h * 0.78, 0.0), "primary_dark")
	_add_jersey_details(spine, chest_size, torso_depth)

	var chest := _joint("chest", spine, Vector3(0.0, torso_h * 0.72, 0.0))
	_sockets["chest"] = chest
	var neck_h := float(_dimensions.height) * 0.055
	_cylinder(chest, "Neck", neck_h * 0.39, neck_h * 0.42, neck_h, Vector3(0.0, neck_h * 0.52, 0.0), "skin", 8)
	var head := _joint("head", chest, Vector3(0.0, neck_h, 0.0))
	_build_head(head)
	_sockets["head"] = head

	_build_arm("left", chest, -shoulder_width * 0.49, upper_arm, forearm, width_scale)
	_build_arm("right", chest, shoulder_width * 0.49, upper_arm, forearm, width_scale)
	_build_leg("left", hips, -hip_width * 0.29, upper_leg, lower_leg, shoe_h, width_scale)
	_build_leg("right", hips, hip_width * 0.29, upper_leg, lower_leg, shoe_h, width_scale)

	var throw_hand: Node3D = _joints["%s_hand" % _throwing_hand]
	var glove_side := "left" if _throwing_hand == "right" else "right"
	var glove_hand: Node3D = _joints["%s_hand" % glove_side]
	_sockets["throw_hand"] = throw_hand
	_sockets["ball_release"] = throw_hand
	_build_glove(glove_hand, glove_side)

	var wants_bat := bool(_spec.get("bat", _role in ["batter", "hitter", "slugger"]))
	if wants_bat:
		var bat_hand_side := "right" if _batting_side == "right" else "left"
		_build_bat(_joints["%s_hand" % bat_hand_side], bat_hand_side)
	if _role == "catcher":
		_build_catcher_gear(spine, head)
	elif _role == "umpire":
		_build_umpire_gear(spine, head)

	var feet_socket := Node3D.new()
	feet_socket.name = "FeetSocket"
	feet_socket.position = Vector3.ZERO
	_model_root.add_child(feet_socket)
	_sockets["feet"] = feet_socket


func _build_arm(side: String, chest: Node3D, x: float, upper_len: float, forearm_len: float, width_scale: float) -> void:
	var sign_x := -1.0 if side == "left" else 1.0
	var rest_z := _rad(-7.0 * sign_x)
	var upper := _joint("%s_upper_arm" % side, chest, Vector3(x, -0.015, 0.0), Vector3(0.0, 0.0, rest_z))
	var arm_w := float(_dimensions.height) * 0.075 * (0.94 + (width_scale - 1.0) * 0.6)
	_sphere(upper, "%sShoulder" % side.capitalize(), arm_w * 0.58, Vector3(0.0, -arm_w * 0.15, 0.0), "primary", 8, 5)
	_box(upper, "%sSleeve" % side.capitalize(), Vector3(arm_w * 1.08, upper_len * 0.38, arm_w), Vector3(0.0, -upper_len * 0.19, 0.0), "primary")
	_box(upper, "%sUpperArm" % side.capitalize(), Vector3(arm_w * 0.78, upper_len * 0.67, arm_w * 0.74), Vector3(0.0, -upper_len * 0.60, 0.0), "skin")
	var elbow := _joint("%s_elbow" % side, upper, Vector3(0.0, -upper_len, 0.0))
	_sphere(elbow, "%sElbow" % side.capitalize(), arm_w * 0.38, Vector3.ZERO, "skin_shadow", 8, 4)
	_box(elbow, "%sForearm" % side.capitalize(), Vector3(arm_w * 0.70, forearm_len * 0.86, arm_w * 0.66), Vector3(0.0, -forearm_len * 0.47, 0.0), "skin")
	var hand := _joint("%s_hand" % side, elbow, Vector3(0.0, -forearm_len, 0.0))
	_box(hand, "%sHand" % side.capitalize(), Vector3(arm_w * 0.72, arm_w * 0.76, arm_w * 0.70), Vector3(0.0, -arm_w * 0.24, -arm_w * 0.04), "skin")
	_sockets["%s_hand" % side] = hand


func _build_leg(side: String, hips: Node3D, x: float, upper_len: float, lower_len: float, shoe_h: float, width_scale: float) -> void:
	var sign_x := -1.0 if side == "left" else 1.0
	var thigh := _joint("%s_thigh" % side, hips, Vector3(x, 0.0, 0.0), Vector3(0.0, 0.0, _rad(-1.5 * sign_x)))
	var leg_w := float(_dimensions.height) * 0.105 * (0.95 + (width_scale - 1.0) * 0.72)
	_box(thigh, "%sPantsUpper" % side.capitalize(), Vector3(leg_w, upper_len * 0.55, leg_w * 0.90), Vector3(0.0, -upper_len * 0.27, 0.0), "pants")
	_box(thigh, "%sPantsLower" % side.capitalize(), Vector3(leg_w * 0.83, upper_len * 0.47, leg_w * 0.82), Vector3(0.0, -upper_len * 0.76, 0.0), "pants_shadow")
	var knee := _joint("%s_knee" % side, thigh, Vector3(0.0, -upper_len, 0.0))
	_sphere(knee, "%sKnee" % side.capitalize(), leg_w * 0.42, Vector3.ZERO, "pants_shadow", 8, 4)
	_box(knee, "%sSock" % side.capitalize(), Vector3(leg_w * 0.72, lower_len * 0.78, leg_w * 0.72), Vector3(0.0, -lower_len * 0.42, 0.0), "secondary")
	_box(knee, "%sSockStripe" % side.capitalize(), Vector3(leg_w * 0.76, lower_len * 0.09, leg_w * 0.75), Vector3(0.0, -lower_len * 0.19, 0.0), "primary")
	var ankle := _joint("%s_ankle" % side, knee, Vector3(0.0, -lower_len, 0.0))
	var foot_size := Vector3(leg_w * 0.86, shoe_h, leg_w * 1.52)
	_box(ankle, "%sCleat" % side.capitalize(), foot_size, Vector3(0.0, -shoe_h * 0.32, -foot_size.z * 0.24), "primary_dark")
	_box(ankle, "%sToe" % side.capitalize(), Vector3(foot_size.x * 0.92, shoe_h * 0.46, foot_size.z * 0.45), Vector3(0.0, -shoe_h * 0.25, -foot_size.z * 0.70), "accent")
	for stud_x in [-0.25, 0.25]:
		for stud_z in [-0.15, 0.35]:
			_box(ankle, "%sStud" % side.capitalize(), Vector3(foot_size.x * 0.15, shoe_h * 0.18, foot_size.z * 0.12), Vector3(foot_size.x * stud_x, -shoe_h * 0.62, foot_size.z * stud_z), "ink")
	_sockets["%s_foot" % side] = ankle


func _build_head(head: Node3D) -> void:
	var head_h := float(_dimensions.head_h)
	var head_w := float(_dimensions.head_w)
	var head_d := float(_dimensions.head_d)
	_box(head, "Head", Vector3(head_w, head_h * 0.78, head_d), Vector3(0.0, head_h * 0.47, 0.0), "skin")
	_box(head, "Jaw", Vector3(head_w * 0.82, head_h * 0.28, head_d * 0.90), Vector3(0.0, head_h * 0.17, -head_d * 0.03), "skin_shadow")
	_box(head, "LeftEar", Vector3(head_w * 0.13, head_h * 0.24, head_d * 0.26), Vector3(-head_w * 0.55, head_h * 0.47, 0.0), "skin_shadow")
	_box(head, "RightEar", Vector3(head_w * 0.13, head_h * 0.24, head_d * 0.26), Vector3(head_w * 0.55, head_h * 0.47, 0.0), "skin_shadow")

	var face_z := -head_d * 0.515
	var eye_y := head_h * 0.54
	var eye_x := head_w * 0.22
	for side in [-1.0, 1.0]:
		_box(head, "EyeWhite", Vector3(head_w * 0.18, head_h * 0.10, 0.015), Vector3(side * eye_x, eye_y, face_z - 0.005), "eye")
		var pupil := _box(head, "Pupil", Vector3(head_w * 0.075, head_h * 0.072, 0.012), Vector3(side * (eye_x + head_w * 0.015), eye_y, face_z - 0.016), "ink")
		_face_parts["pupil_%s" % side] = pupil
		var brow := _box(head, "Brow", Vector3(head_w * 0.23, head_h * 0.038, 0.016), Vector3(side * eye_x, eye_y + head_h * 0.105, face_z - 0.018), "hair")
		_face_parts["brow_%s" % side] = brow
	_box(head, "Nose", Vector3(head_w * 0.13, head_h * 0.16, head_d * 0.12), Vector3(0.0, head_h * 0.42, face_z - head_d * 0.035), "skin_shadow")
	var mouth := _box(head, "Mouth", Vector3(head_w * 0.25, head_h * 0.045, 0.016), Vector3(0.0, head_h * 0.25, face_z - 0.018), "ink")
	_face_parts["mouth"] = mouth

	_build_hair(head, head_w, head_h, head_d)
	var helmet_default := _role in ["batter", "hitter", "slugger", "catcher"]
	if bool(_spec.get("helmet", helmet_default)):
		_build_helmet(head, head_w, head_h, head_d)
	else:
		_build_cap(head, head_w, head_h, head_d)


func _build_hair(head: Node3D, head_w: float, head_h: float, head_d: float) -> void:
	var style := String(_spec.get("hair_style", ["crop", "fade", "waves", "long"][int(_rng.randi() % 4)])).to_lower()
	_box(head, "HairTop", Vector3(head_w * 0.93, head_h * 0.15, head_d * 0.92), Vector3(0.0, head_h * 0.88, head_d * 0.02), "hair")
	_box(head, "HairBack", Vector3(head_w * 0.90, head_h * (0.28 if style == "fade" else 0.40), head_d * 0.13), Vector3(0.0, head_h * 0.66, head_d * 0.50), "hair")
	if style == "waves":
		for x in [-0.31, 0.0, 0.31]:
			_box(head, "HairWave", Vector3(head_w * 0.24, head_h * 0.12, head_d * 0.23), Vector3(head_w * x, head_h * 0.94, -head_d * 0.10), "hair")
	elif style == "long":
		_box(head, "HairLeft", Vector3(head_w * 0.17, head_h * 0.51, head_d * 0.24), Vector3(-head_w * 0.48, head_h * 0.56, head_d * 0.33), "hair")
		_box(head, "HairRight", Vector3(head_w * 0.17, head_h * 0.51, head_d * 0.24), Vector3(head_w * 0.48, head_h * 0.56, head_d * 0.33), "hair")

	var facial_hair := String(_spec.get("facial_hair", ["none", "none", "mustache", "goatee", "beard"][int(_rng.randi() % 5)])).to_lower()
	var face_z := -head_d * 0.54
	if facial_hair in ["mustache", "beard"]:
		_box(head, "Mustache", Vector3(head_w * 0.34, head_h * 0.07, 0.018), Vector3(0.0, head_h * 0.32, face_z), "hair")
	if facial_hair in ["goatee", "beard"]:
		_box(head, "Goatee", Vector3(head_w * 0.25, head_h * 0.13, 0.018), Vector3(0.0, head_h * 0.15, face_z), "hair")
	if facial_hair == "beard":
		_box(head, "BeardLeft", Vector3(head_w * 0.14, head_h * 0.28, 0.018), Vector3(-head_w * 0.38, head_h * 0.20, face_z), "hair")
		_box(head, "BeardRight", Vector3(head_w * 0.14, head_h * 0.28, 0.018), Vector3(head_w * 0.38, head_h * 0.20, face_z), "hair")


func _build_cap(head: Node3D, head_w: float, head_h: float, head_d: float) -> void:
	_box(head, "CapCrown", Vector3(head_w * 1.08, head_h * 0.25, head_d * 1.04), Vector3(0.0, head_h * 0.98, 0.0), "primary")
	_box(head, "CapFront", Vector3(head_w * 0.74, head_h * 0.23, head_d * 0.14), Vector3(0.0, head_h * 0.91, -head_d * 0.54), "primary_dark")
	_box(head, "CapBrim", Vector3(head_w * 0.86, head_h * 0.055, head_d * 0.48), Vector3(0.0, head_h * 0.87, -head_d * 0.69), "primary_dark", Vector3(_rad(-5.0), 0.0, 0.0))
	_box(head, "CapButton", Vector3(head_w * 0.10, head_h * 0.055, head_d * 0.10), Vector3(0.0, head_h * 1.13, 0.0), "accent")


func _build_helmet(head: Node3D, head_w: float, head_h: float, head_d: float) -> void:
	_box(head, "HelmetCrown", Vector3(head_w * 1.15, head_h * 0.36, head_d * 1.14), Vector3(0.0, head_h * 0.92, head_d * 0.03), "primary")
	_box(head, "HelmetBack", Vector3(head_w * 1.09, head_h * 0.30, head_d * 0.20), Vector3(0.0, head_h * 0.76, head_d * 0.55), "primary_dark")
	_box(head, "HelmetBrim", Vector3(head_w * 0.92, head_h * 0.06, head_d * 0.42), Vector3(0.0, head_h * 0.84, -head_d * 0.67), "primary_dark")
	var ear_side := 1.0 if _batting_side == "right" else -1.0
	_box(head, "EarFlap", Vector3(head_w * 0.19, head_h * 0.36, head_d * 0.48), Vector3(ear_side * head_w * 0.53, head_h * 0.59, head_d * 0.12), "primary")


func _add_jersey_details(spine: Node3D, chest_size: Vector3, torso_depth: float) -> void:
	var mark := String(_spec.get("mark", "P")).to_upper()
	if mark.length() > 0 and GLYPHS.has(mark.left(1)):
		_add_glyph(spine, mark.left(1), Vector3(-chest_size.x * 0.22, chest_size.y * 0.60, -torso_depth * 0.515), chest_size.y * 0.052, "primary", false)
	var number := posmod(int(_spec.get("number", 27)), 100)
	var digits := str(number).pad_zeros(2)
	var block := chest_size.y * 0.043
	var gap := block * 4.0
	_add_glyph(spine, digits[0], Vector3(-gap * 0.52, chest_size.y * 0.56, torso_depth * 0.515), block, "primary", true)
	_add_glyph(spine, digits[1], Vector3(gap * 0.52, chest_size.y * 0.56, torso_depth * 0.515), block, "primary", true)
	# Three-dimensional piping reads at gameplay distance without a texture.
	_box(spine, "JerseyPlacket", Vector3(chest_size.x * 0.025, chest_size.y * 0.62, 0.014), Vector3(0.0, chest_size.y * 0.45, -torso_depth * 0.525), "primary_dark")


func _add_glyph(parent: Node3D, glyph: String, center: Vector3, block: float, material_key: String, mirror_x: bool) -> void:
	if not GLYPHS.has(glyph):
		return
	var rows: Array = GLYPHS[glyph]
	for row in range(rows.size()):
		var bits: String = rows[row]
		for column in range(bits.length()):
			if bits[column] != "1":
				continue
			var x := (float(column) - 1.0) * block * 1.08
			if mirror_x:
				x = -x
			var y := (2.0 - float(row)) * block * 1.08
			_box(parent, "Glyph%s" % glyph, Vector3(block, block, block * 0.34), center + Vector3(x, y, 0.0), material_key)


func _build_glove(hand: Node3D, side: String) -> void:
	if not bool(_spec.get("glove", _role != "umpire")):
		return
	var glove := _joint("glove", hand, Vector3(0.0, -0.055, -0.025), Vector3(_rad(8.0), 0.0, _rad(-12.0 if side == "left" else 12.0)))
	var scale := float(_dimensions.height) * (0.095 if _role == "catcher" else 0.078)
	_box(glove, "GlovePalm", Vector3(scale * 0.82, scale * 0.85, scale * 0.46), Vector3(0.0, -scale * 0.25, -scale * 0.12), "leather")
	for finger in range(4):
		var x := (float(finger) - 1.5) * scale * 0.19
		var finger_h := scale * (0.60 - absf(float(finger) - 1.5) * 0.05)
		_box(glove, "GloveFinger", Vector3(scale * 0.16, finger_h, scale * 0.26), Vector3(x, -scale * 0.68, -scale * 0.08), "leather")
	_box(glove, "GloveThumb", Vector3(scale * 0.24, scale * 0.56, scale * 0.30), Vector3((-1.0 if side == "left" else 1.0) * scale * 0.47, -scale * 0.42, -scale * 0.05), "leather_dark", Vector3(0.0, 0.0, _rad(24.0 if side == "left" else -24.0)))
	_box(glove, "GlovePocket", Vector3(scale * 0.44, scale * 0.40, scale * 0.08), Vector3(0.0, -scale * 0.38, -scale * 0.38), "leather_dark")
	var catch_socket := Node3D.new()
	catch_socket.name = "CatchSocket"
	catch_socket.position = Vector3(0.0, -scale * 0.38, -scale * 0.47)
	glove.add_child(catch_socket)
	_sockets["glove"] = glove
	_sockets["catch"] = catch_socket


func _build_bat(hand: Node3D, side: String) -> void:
	var bat := _joint("bat", hand, Vector3(0.0, -0.035, -0.025), Vector3(_rad(4.0), 0.0, _rad(-12.0 if side == "right" else 12.0)))
	var bat_len := float(_dimensions.height) * 0.51
	var radius := float(_dimensions.height) * 0.022
	_cylinder(bat, "BatHandle", radius * 0.45, radius * 0.54, bat_len * 0.38, Vector3(0.0, bat_len * 0.19, 0.0), "wood_dark", 8)
	_cylinder(bat, "BatTaper", radius * 0.54, radius * 1.18, bat_len * 0.24, Vector3(0.0, bat_len * 0.50, 0.0), "wood", 8)
	_cylinder(bat, "BatBarrel", radius * 1.18, radius * 1.12, bat_len * 0.39, Vector3(0.0, bat_len * 0.815, 0.0), "wood", 8)
	_cylinder(bat, "BatKnob", radius * 0.72, radius * 0.72, radius * 0.52, Vector3(0.0, -radius * 0.18, 0.0), "wood_dark", 8)
	_box(bat, "BatBrand", Vector3(radius * 1.7, bat_len * 0.035, radius * 0.08), Vector3(0.0, bat_len * 0.67, -radius * 1.15), "accent")
	var tip := Node3D.new()
	tip.name = "BatTipSocket"
	tip.position = Vector3(0.0, bat_len, 0.0)
	bat.add_child(tip)
	_sockets["bat_grip"] = bat
	_sockets["bat_tip"] = tip


func _build_catcher_gear(spine: Node3D, head: Node3D) -> void:
	var torso_h := float(_dimensions.torso_h)
	var torso_d := float(_dimensions.torso_depth)
	var shoulder_w := float(_dimensions.shoulder_width)
	_box(spine, "CatcherChest", Vector3(shoulder_w * 0.65, torso_h * 0.52, torso_d * 0.10), Vector3(0.0, torso_h * 0.44, -torso_d * 0.57), "primary_dark")
	for row in range(3):
		_box(spine, "CatcherPlate", Vector3(shoulder_w * (0.56 - row * 0.05), torso_h * 0.09, torso_d * 0.055), Vector3(0.0, torso_h * (0.61 - row * 0.13), -torso_d * 0.64), "accent" if row == 0 else "primary")
	for side in ["left", "right"]:
		var knee: Node3D = _joints["%s_knee" % side]
		var lower_leg := float(_dimensions.lower_leg)
		var x_sign := -1.0 if side == "left" else 1.0
		for row in range(3):
			_box(knee, "ShinGuard", Vector3(float(_dimensions.height) * 0.075, lower_leg * 0.18, float(_dimensions.height) * 0.032), Vector3(x_sign * 0.002, -lower_leg * (0.22 + row * 0.23), -float(_dimensions.height) * 0.055), "primary_dark")
	_build_mask(head, "metal")


func _build_umpire_gear(spine: Node3D, head: Node3D) -> void:
	var torso_h := float(_dimensions.torso_h)
	var torso_d := float(_dimensions.torso_depth)
	var shoulder_w := float(_dimensions.shoulder_width)
	_box(spine, "UmpireProtector", Vector3(shoulder_w * 0.72, torso_h * 0.48, torso_d * 0.08), Vector3(0.0, torso_h * 0.43, -torso_d * 0.56), "ink")
	_build_mask(head, "ink")


func _build_mask(head: Node3D, material_key: String) -> void:
	var head_w := float(_dimensions.head_w)
	var head_h := float(_dimensions.head_h)
	var head_d := float(_dimensions.head_d)
	var z := -head_d * 0.68
	for x in [-0.39, -0.13, 0.13, 0.39]:
		_box(head, "MaskVertical", Vector3(head_w * 0.055, head_h * 0.61, head_d * 0.045), Vector3(head_w * x, head_h * 0.47, z), material_key)
	for y in [0.23, 0.43, 0.63, 0.78]:
		_box(head, "MaskHorizontal", Vector3(head_w * 0.91, head_h * 0.045, head_d * 0.045), Vector3(0.0, head_h * y, z), material_key)
	_box(head, "MaskChin", Vector3(head_w * 0.73, head_h * 0.10, head_d * 0.11), Vector3(0.0, head_h * 0.13, z + head_d * 0.02), material_key)


func _update_face(expression: String, weight: float) -> void:
	var mouth: MeshInstance3D = _face_parts.get("mouth")
	if not is_instance_valid(mouth):
		return
	var mouth_scale := Vector3.ONE
	var mouth_rotation := 0.0
	match expression:
		"happy":
			mouth_scale = Vector3(1.15, 1.8, 1.0)
			mouth_rotation = _rad(5.0)
		"surprised":
			mouth_scale = Vector3(0.45, 2.8, 1.0)
		"grit":
			mouth_scale = Vector3(1.25, 0.72, 1.0)
			mouth_rotation = _rad(-3.0)
	mouth.scale = mouth.scale.lerp(mouth_scale, weight)
	mouth.rotation.z = lerp_angle(mouth.rotation.z, mouth_rotation, weight)
	for side in [-1.0, 1.0]:
		var brow: MeshInstance3D = _face_parts.get("brow_%s" % side)
		if is_instance_valid(brow):
			var brow_angle := 0.0
			if expression == "grit":
				brow_angle = _rad(12.0 * side)
			elif expression == "surprised":
				brow_angle = _rad(-4.0 * side)
			brow.rotation.z = lerp_angle(brow.rotation.z, brow_angle, weight)


func _joint(key: String, parent: Node3D, position_value: Vector3, rest_rotation := Vector3.ZERO) -> Node3D:
	var joint := Node3D.new()
	joint.name = key.to_pascal_case()
	joint.position = position_value
	joint.rotation = rest_rotation
	parent.add_child(joint)
	_joints[key] = joint
	_rest_rotations[key] = rest_rotation
	return joint


func _box(parent: Node3D, node_name: String, size: Vector3, position_value: Vector3, material_key: String, rotation_value := Vector3.ZERO) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(maxf(size.x, 0.002), maxf(size.y, 0.002), maxf(size.z, 0.002))
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position_value
	instance.rotation = rotation_value
	instance.material_override = _materials[material_key]
	parent.add_child(instance)
	return instance


func _cylinder(parent: Node3D, node_name: String, top_radius: float, bottom_radius: float, height: float, position_value: Vector3, material_key: String, sides := 8, rotation_value := Vector3.ZERO) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = maxf(top_radius, 0.001)
	mesh.bottom_radius = maxf(bottom_radius, 0.001)
	mesh.height = maxf(height, 0.002)
	mesh.radial_segments = maxi(sides, 3)
	mesh.rings = 1
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position_value
	instance.rotation = rotation_value
	instance.material_override = _materials[material_key]
	parent.add_child(instance)
	return instance


func _sphere(parent: Node3D, node_name: String, radius: float, position_value: Vector3, material_key: String, radial_segments := 8, rings := 5) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = maxf(radius, 0.001)
	mesh.height = maxf(radius * 2.0, 0.002)
	mesh.radial_segments = maxi(radial_segments, 4)
	mesh.rings = maxi(rings, 2)
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.position = position_value
	instance.material_override = _materials[material_key]
	parent.add_child(instance)
	return instance


func _clear_generated_model() -> void:
	if is_instance_valid(_model_root):
		if _model_root.get_parent() == self:
			remove_child(_model_root)
		_model_root.free()
	_model_root = null


func _as_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	if value is String:
		return Color.from_string(value, fallback)
	return fallback


func _normalized_hand(value: String) -> String:
	var lower := value.to_lower().strip_edges()
	return "left" if lower in ["l", "left"] else "right"


func _rad(degrees: float) -> float:
	return deg_to_rad(degrees)
