@tool
class_name BallplayerActor
extends Node

## Simulation-space proxy with a native 2D pixel presenter.
##
## The legacy Vector3 is deliberately retained as baseball field data. It is
## never submitted to Godot's 3D renderer; the detached presenter maps it onto
## a 320x180 composition grid expanded 2x onto a 640x360 design grid whose 4px
## units render directly into native 2560x1440.

signal action_started(action_name: String)
signal action_marker(action_name: String, marker_name: String)
signal action_finished(action_name: String)

const PixelSprite = preload("res://characters/pixel_actor_sprite.gd")
const PIXEL_ANIMATION_FPS := 10.0

const ACTION_DURATIONS := {
	"idle": 0.8,
	"run": 0.4,
	"pitch": 1.42,
	"swing": 0.36,
	"catch": 0.68,
	"field_ready": 0.8,
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

const ACTION_FRAME_COUNTS := {
	"idle": 2,
	"run": 4,
	"pitch": 7,
	"swing": 4,
	"catch": 4,
	"field_ready": 2,
	"field_throw": 5,
	"throw": 5,
	"celebrate": 3,
	"slide": 3,
}

# Pocket Giants roster ramps (art bible §8.2): four skin tones and six
# two-color hair ramps, each with an authored cool-shifted shade step. They
# are mood-invariant by design — characters re-grade only through the world
# light around them — and are distributed across rosters by the content seed.
const SKIN_RAMPS := [
	{"main": Color("8a4b32"), "shade": Color("69403a")},
	{"main": Color("b06e44"), "shade": Color("815646")},
	{"main": Color("d29061"), "shade": Color("976c59")},
	{"main": Color("ecb98a"), "shade": Color("a88774")},
]
const HAIR_RAMPS := [
	{"main": Color("2a3040"), "shade": Color("161a26")},
	{"main": Color("6b4a2e"), "shade": Color("46301f")},
	{"main": Color("9c5233"), "shade": Color("6b3626")},
	{"main": Color("d9a95c"), "shade": Color("a1793f")},
	{"main": Color("aab3ba"), "shade": Color("737e88")},
	{"main": Color("3fa693"), "shade": Color("2b6f66")},
]

# Uniform cloth resolves to exactly two bible values (§8.4): chalk-paper
# home whites for bright low-saturation team cloth, steel-text road grays
# otherwise. Trim snaps to the two league families when recognizable.
const CLOTH_HOME := Color("efe9d4")
const CLOTH_HOME_SHADOW := Color("b4b0aa")
const CLOTH_ROAD := Color("9db2c4")
const CLOTH_ROAD_SHADOW := Color("7b8a9f")
const TRIM_FOX := Color("d94a3d")
const TRIM_PIER := Color("55d6c4")
const COOL_SHADE_ANCHOR := Color("2c2a4a")

# §8.6 game-state expression channel. Momentary outcome states decay back to
# the sustained base after this hold; the base is neutral, or "gassed" for a
# pitcher whose stamina falls below the fatigue line. States are fed from the
# existing sim event stream (plate_result/play_result payloads) through
# apply_sim_event() or set directly — no new gameplay signals exist.
const EXPRESSION_HOLD_SEC := 2.4
const GASSED_STAMINA_FRACTION := 0.34

var global_position := Vector3.ZERO
var visible := true:
	set(value):
		visible = value
		if is_instance_valid(_pixel_sprite):
			_pixel_sprite.visible = value

var _spec: Dictionary = {}
var _configured := false
var _pixel_sprite: PixiballPixelActorSprite
var _current_action := "idle"
var _action_elapsed := 0.0
var _held_pose := false
var _emitted_markers: Dictionary = {}
var _motion_velocity := Vector3.ZERO
var _facing_direction := Vector3(0, 0, 1)
var _highlighted := false
var _role := "fielder"
var _throwing_hand := "right"
var _batting_side := "right"
var _team_mark := ""
var _player_name := ""
var _jersey_number := 0
var _primary_color := Color("173f73")
var _secondary_color := Color("f1ead9")
var _accent_color := Color("e2b447")
var _pants_color := Color("e9e6da")
var _skin_color: Color = SKIN_RAMPS[1].main
var _skin_shadow: Color = SKIN_RAMPS[1].shade
var _hair_color: Color = HAIR_RAMPS[0].main
var _hair_shadow: Color = HAIR_RAMPS[0].shade
var _role_variant_override := ""
var _expression_state := ""
var _expression_hold := 0.0
var _stamina_fraction := 1.0


func _ready() -> void:
	if not _configured:
		configure({})
	call_deferred("_attach_pixel_sprite")
	set_physics_process(true)


func configure(spec: Dictionary) -> void:
	_spec = spec.duplicate(true)
	var seed_value := maxi(1, int(_spec.get("seed", 1)))
	_role = String(_spec.get("role", "fielder")).to_lower()
	_throwing_hand = _normalized_hand(String(_spec.get("throws", "right")))
	_batting_side = _normalized_hand(String(_spec.get("bats", _throwing_hand)))
	_team_mark = String(_spec.get("mark", "")).to_upper().left(1)
	_player_name = String(_spec.get("player_name", _spec.get("name", ""))).strip_edges()
	_jersey_number = int(_spec.get("number", 0))
	_primary_color = _as_color(_spec.get("primary_color", _primary_color), _primary_color)
	_secondary_color = _as_color(_spec.get("secondary_color", _secondary_color), _secondary_color)
	_accent_color = _as_color(_spec.get("accent_color", _accent_color), _accent_color)
	_pants_color = _as_color(_spec.get("pants_color", _pants_color), _pants_color)
	var skin_ramp: Dictionary = SKIN_RAMPS[seed_value % SKIN_RAMPS.size()]
	var hair_ramp: Dictionary = HAIR_RAMPS[(seed_value / 7) % HAIR_RAMPS.size()]
	_skin_color = _as_color(_spec.get("skin_tone", skin_ramp.main), skin_ramp.main)
	_skin_shadow = skin_ramp.shade if _skin_color.is_equal_approx(skin_ramp.main) else _cool_shade(_skin_color)
	_hair_color = _as_color(_spec.get("hair_color", hair_ramp.main), hair_ramp.main)
	_hair_shadow = hair_ramp.shade if _hair_color.is_equal_approx(hair_ramp.main) else _cool_shade(_hair_color)
	_configured = true
	_current_action = "idle"
	_action_elapsed = 0.0
	_held_pose = false
	_emitted_markers.clear()
	_expression_state = ""
	_expression_hold = 0.0
	_stamina_fraction = 1.0
	if is_inside_tree():
		_attach_pixel_sprite()
	_refresh_sprite()


func _attach_pixel_sprite() -> void:
	if is_instance_valid(_pixel_sprite):
		return
	var canvas_root := get_tree().get_first_node_in_group("pixiball_pixel_scene")
	if canvas_root == null:
		if is_inside_tree():
			get_tree().process_frame.connect(_attach_pixel_sprite, CONNECT_ONE_SHOT)
		return
	_pixel_sprite = PixelSprite.new()
	canvas_root.add_child(_pixel_sprite)
	_pixel_sprite.bind(self)
	_pixel_sprite.visible = visible


func _exit_tree() -> void:
	if is_instance_valid(_pixel_sprite):
		_pixel_sprite.queue_free()


func play_action(action_name: String) -> void:
	var normalized := _normalized_action(action_name)
	_current_action = normalized
	_action_elapsed = 0.0
	_held_pose = false
	_emitted_markers.clear()
	action_started.emit(normalized)
	_refresh_sprite()


func hold_action_pose(action_name: String, normalized_time := 0.0) -> void:
	var normalized := _normalized_action(action_name)
	_current_action = normalized
	_action_elapsed = clampf(normalized_time, 0.0, 1.0) * float(ACTION_DURATIONS.get(normalized, 0.8))
	_held_pose = true
	_emitted_markers.clear()
	_refresh_sprite()


func set_motion(velocity: Vector3) -> void:
	_motion_velocity = velocity
	if velocity.length() > 0.2:
		set_facing(velocity)
		if _current_action in ["idle", "field_ready", "run"] and not _held_pose:
			if _current_action != "run":
				play_action("run")
	elif _current_action == "run":
		play_action("idle")


func set_facing(direction: Vector3) -> void:
	var flat := Vector3(direction.x, 0.0, direction.z)
	if flat.length_squared() > 0.0001:
		_facing_direction = flat.normalized()
	_refresh_sprite()


func get_socket_position(socket_name: String) -> Vector3:
	var side := -1.0 if _hand_for_action(_current_action) == "left" else 1.0
	var height := 1.0
	var offset := Vector3.ZERO
	match socket_name:
		"head":
			height = 1.72
		"chest":
			height = 1.18
		"left_hand":
			height = 1.12
			offset.x = -0.32
		"right_hand":
			height = 1.12
			offset.x = 0.32
		"glove", "catch":
			height = 1.12
			offset.x = -0.40 if _throwing_hand == "right" else 0.40
		"throw_hand", "ball_release":
			height = 1.56
			offset.x = 0.46 * side
			offset.z = 0.12 * _facing_direction.z
		"bat_grip":
			height = 1.12
			offset.x = 0.28 * (-1.0 if _batting_side == "left" else 1.0)
		"bat_tip":
			height = 1.82
			offset.x = 0.85 * (-1.0 if _batting_side == "left" else 1.0)
		"left_foot":
			height = 0.05
			offset.x = -0.16
		"right_foot":
			height = 0.05
			offset.x = 0.16
		"feet":
			height = 0.02
		_:
			height = 1.0
	offset.y = height
	return global_position + offset


func get_socket_node(_socket_name: String) -> Node:
	return null


func attach_to_socket(_node: Node, _socket_name: String, _keep_global := false) -> bool:
	return false


func set_highlighted(enabled: bool) -> void:
	_highlighted = enabled
	_refresh_sprite()


func set_uniform_colors(primary: Color, secondary: Color, accent: Color, pants := Color("e9e6da")) -> void:
	_primary_color = primary
	_secondary_color = secondary
	_accent_color = accent
	_pants_color = pants
	_refresh_sprite()


func set_team_mark(mark: String) -> void:
	_team_mark = mark.to_upper().left(1)
	_refresh_sprite()


func set_jersey_number(number: int) -> void:
	_jersey_number = number
	_spec["number"] = number
	_refresh_sprite()


func set_player_name(player_name: String) -> void:
	_player_name = player_name.strip_edges()
	_spec["player_name"] = _player_name
	_refresh_sprite()


func get_team_mark() -> String:
	return _team_mark


func get_jersey_number() -> int:
	return _jersey_number


func get_player_name() -> String:
	return _player_name


func get_throwing_hand() -> String:
	return _throwing_hand


func get_batting_side() -> String:
	return _batting_side


func get_role() -> String:
	return _role


func get_equipment_profile() -> Dictionary:
	var pieces := PackedStringArray()
	if _role != "umpire":
		pieces.append_array(["TeamMark", "JerseyNumberFront"])
	if _role == "batter":
		pieces.append_array(["BattingHelmet", "Bat"])
	elif _role == "catcher":
		pieces.append_array(["CatcherMask", "CatcherChestProtector", "CatcherShinGuardL", "CatcherShinGuardR", "Glove"])
	elif _role == "umpire":
		pieces.append_array(["UmpireMask", "UmpireProtector"])
	else:
		pieces.append("Glove")
	return {
		"role": _role,
		"pieces": pieces,
		"pipeline": "native_pixel_layers",
		"helmet": _role == "batter",
		"bat": _role == "batter",
		"glove": _role in ["pitcher", "catcher", "fielder"],
	}


func get_equipment_piece(piece_name: String) -> Node:
	return _pixel_sprite if piece_name in get_equipment_profile().pieces else null


func get_imported_mesh(_mesh_name: String) -> Variant:
	return null


func get_external_prop(_prop_name: String) -> Node:
	return null


func is_model_mirrored() -> bool:
	return _hand_for_action(_current_action) == "left"


func get_current_action() -> String:
	return _current_action


func get_generation_signature() -> String:
	return "pixel-v1/%s/%s/%s/%d/%s/%s" % [
		_role, _throwing_hand, _batting_side, int(_spec.get("seed", 1)),
		_primary_color.to_html(false), _secondary_color.to_html(false),
	]


func is_using_fallback() -> bool:
	return false


func get_model_kind() -> String:
	return "native_pixel_sprite"


func get_available_actions() -> PackedStringArray:
	return PackedStringArray(ACTION_DURATIONS.keys())


func get_pixel_pose() -> Dictionary:
	var duration := float(ACTION_DURATIONS.get(_current_action, 0.8))
	var phase := clampf(_action_elapsed / maxf(duration, 0.001), 0.0, 1.0)
	var frame_count := int(ACTION_FRAME_COUNTS.get(_current_action, 2))
	var stepped := mini(frame_count - 1, int(floor(_action_elapsed * PIXEL_ANIMATION_FPS)) % frame_count)
	if _held_pose:
		stepped = mini(frame_count - 1, int(floor(phase * float(frame_count))))
	var accents := _motion_accents()
	return {
		"action": _current_action,
		"phase": phase,
		"frame": stepped,
		"facing": _facing_sign(),
		"highlighted": _highlighted,
		"pose_key": pose_key_for(_current_action, phase),
		"role_variant": get_role_variant(),
		"expression": get_expression_state(),
		"smear": accents.smear,
		"reception": accents.reception,
		"brim_pop": accents.brim_pop,
	}


## §8.5 motion accents, quantized to the authored 10 fps tick containing each
## action's existing marker time so they never shift action timing:
##   smear     — the single arm/bat-arc smear frame at pitch release and bat
##               contact (1 frame only, by contract).
##   reception — the single catch frame where the mitt doubles.
##   brim_pop  — the 2-tick cap-brim pop right after pitch release snaps back.
func _motion_accents() -> Dictionary:
	var accents := {"smear": false, "reception": false, "brim_pop": false}
	var markers: Dictionary = ACTION_MARKERS.get(_current_action, {})
	if markers.is_empty():
		return accents
	var duration := float(ACTION_DURATIONS.get(_current_action, 0.8))
	var marker_tick := int(floor(float(markers.values()[0]) * duration * PIXEL_ANIMATION_FPS))
	var current_tick := int(floor(_action_elapsed * PIXEL_ANIMATION_FPS))
	match _current_action:
		"pitch":
			accents.smear = current_tick == marker_tick
			accents.brim_pop = current_tick > marker_tick and current_tick <= marker_tick + 2
		"swing":
			accents.smear = current_tick == marker_tick
		"catch":
			accents.reception = current_tick == marker_tick
	return accents


## Three-pose animation keys (bible §8.5): anticipation / action / settle,
## pivoting on each action's authored marker time. The squash/stretch keys and
## the _motion_accents() smear ticks pivot on the same boundaries, so key
## selection lives here rather than the drawer.
static func pose_key_for(action: String, phase: float) -> String:
	if action in ["idle", "run", "field_ready"]:
		return "action"
	var markers: Dictionary = ACTION_MARKERS.get(action, {})
	var pivot := 0.55
	if not markers.is_empty():
		pivot = float(markers.values()[0])
	if phase < pivot * 0.6:
		return "anticipation"
	if phase < minf(pivot + 0.2, 0.85):
		return "action"
	return "settle"


## Silhouette variant (bible §8.3). Fielders resolve to infielder/outfielder
## by field position and to runner when cast as a baserunner; other roles map
## to themselves. Pass 06/10 can pin a variant explicitly via the setter.
func get_role_variant() -> String:
	if not _role_variant_override.is_empty():
		return _role_variant_override
	if _role != "fielder":
		return _role
	if String(name).begins_with("Runner"):
		return "runner"
	if Vector2(global_position.x, global_position.z).length() > 20.0:
		return "outfielder"
	return "infielder"


func set_role_variant(variant: String) -> void:
	_role_variant_override = variant.strip_edges().to_lower()
	_refresh_sprite()


## §8.6 expression channel. States come from the drawer's canonical vocabulary
## (PixiballPixelActorSprite.EXPRESSION_STATES); anything else clears back to
## the sustained base. hold_sec <= 0 makes the state sustained until replaced.
func set_expression_state(state: String, hold_sec := EXPRESSION_HOLD_SEC) -> void:
	var normalized := state.strip_edges().to_lower()
	if normalized.is_empty() or normalized not in PixelSprite.EXPRESSION_STATES:
		_expression_state = ""
		_expression_hold = 0.0
	else:
		_expression_state = normalized
		_expression_hold = hold_sec if hold_sec > 0.0 else -1.0
	_refresh_sprite()


func get_expression_state() -> String:
	if not _expression_state.is_empty():
		return _expression_state
	if _role == "pitcher" and _stamina_fraction < GASSED_STAMINA_FRACTION:
		return "gassed"
	return ""


## Sustained fatigue read for the gassed-pitcher base state (§8.6). Fed from
## the pitcher condition already exposed in the sim snapshot.
func set_stamina(fraction: float) -> void:
	_stamina_fraction = clampf(fraction, 0.0, 1.0)
	_refresh_sprite()


## Maps the sim's existing event stream onto §8.6 expression states from this
## actor's perspective (batter/runner read as offense; pitcher/catcher and
## fielders as defense; the umpire stays impartial). Accepts the payloads
## PixiballSim already emits for plate_result and play_result unchanged, so
## presentation wiring never needs a new gameplay signal.
func apply_sim_event(type: String, payload: Dictionary = {}) -> void:
	if _role == "umpire":
		return
	var offense := _role in ["batter", "runner"] or String(name).begins_with("Runner")
	match type:
		"pitch_created":
			set_expression_state("focus", -1.0)
		"plate_result":
			match String(payload.get("outcome", "")):
				"called_strike", "swinging_strike":
					set_expression_state("miss" if offense else "good_play")
				"strikeout":
					set_expression_state("dejected" if offense else "good_play")
				"ball":
					set_expression_state("neutral" if offense else "miss")
				"walk":
					set_expression_state("good_play" if offense else "miss")
				"foul":
					set_expression_state("miss" if offense else "neutral")
		"play_result":
			match String(payload.get("classification", "")):
				"home_run":
					set_expression_state("hero" if offense else ("conceded" if _role == "pitcher" else "miss"))
				"single", "double", "triple":
					set_expression_state("good_play" if offense else "miss")
				"fly_out", "ground_out", "fielders_choice":
					set_expression_state("miss" if offense else "good_play")
		"home_run", "walk_off":
			set_expression_state("hero" if offense else ("conceded" if _role == "pitcher" else "miss"))
		"overthrow", "error":
			set_expression_state("good_play" if offense else "dejected")


func get_pixel_palette() -> Dictionary:
	var trim := _trim_family_color(_primary_color)
	return {
		"primary": _primary_color,
		"primary_shadow": _quantized_shadow(_primary_color),
		"secondary": _secondary_color,
		"accent": _accent_color,
		"pants": _pants_color,
		"pants_shadow": _quantized_shadow(_pants_color),
		"skin": _skin_color,
		"skin_shadow": _skin_shadow,
		"hair": _hair_color,
		"hair_shadow": _hair_shadow,
		"trim": trim,
		"trim_shadow": _cool_shade(trim),
		"trim_family": _trim_family_name(_primary_color),
		"cloth": CLOTH_HOME if _is_home_cloth(_secondary_color) else CLOTH_ROAD,
		"cloth_shadow": CLOTH_HOME_SHADOW if _is_home_cloth(_secondary_color) else CLOTH_ROAD_SHADOW,
	}


## §8.4: base cloth is chalk-paper home whites or steel-text road grays. Team
## cloth from content is bright and near-neutral for the home set, so that is
## the deterministic discriminator.
func _is_home_cloth(cloth: Color) -> bool:
	return cloth.s < 0.28 and cloth.v > 0.62


func _trim_family_name(color: Color) -> String:
	if color.s < 0.25:
		return "neutral"
	var hue := color.h
	if hue >= 0.93 or hue <= 0.09:
		return "fox"
	if hue >= 0.38 and hue <= 0.55:
		return "pier"
	return "neutral"


func _trim_family_color(color: Color) -> Color:
	match _trim_family_name(color):
		"fox":
			return TRIM_FOX
		"pier":
			return TRIM_PIER
		_:
			return color


func _cool_shade(color: Color) -> Color:
	# Shadow steps shift cool toward the night-indigo family (§3.3), never
	# merely darker.
	var shaded := color.lerp(COOL_SHADE_ANCHOR, 0.35)
	shaded.a = 1.0
	return shaded


func get_pixel_sprite() -> Node2D:
	return _pixel_sprite


func _physics_process(delta: float) -> void:
	if _expression_hold > 0.0:
		_expression_hold -= delta
		if _expression_hold <= 0.0:
			_expression_hold = 0.0
			_expression_state = ""
			_refresh_sprite()
	if _held_pose:
		return
	var previous := _action_elapsed
	_action_elapsed += delta
	_update_action_markers(previous, _action_elapsed)
	var duration := float(ACTION_DURATIONS.get(_current_action, 0.8))
	if _current_action in ["idle", "run", "field_ready"]:
		_action_elapsed = fmod(_action_elapsed, duration)
		if _action_elapsed < previous:
			_emitted_markers.clear()
	elif _action_elapsed >= duration:
		var completed := _current_action
		_action_elapsed = duration
		action_finished.emit(completed)
		_current_action = "idle"
		_action_elapsed = 0.0
		_emitted_markers.clear()
	_refresh_sprite()


func _update_action_markers(previous: float, current: float) -> void:
	var markers: Dictionary = ACTION_MARKERS.get(_current_action, {})
	var duration := float(ACTION_DURATIONS.get(_current_action, 0.8))
	for marker_value in markers:
		var marker := String(marker_value)
		var marker_time := float(markers[marker]) * duration
		if previous < marker_time and current >= marker_time and not _emitted_markers.has(marker):
			_emitted_markers[marker] = true
			action_marker.emit(_current_action, marker)


func _refresh_sprite() -> void:
	if is_instance_valid(_pixel_sprite):
		_pixel_sprite.queue_redraw()


func _normalized_action(value: String) -> String:
	var normalized := value.to_lower()
	if normalized == "throw":
		return "throw"
	return normalized if ACTION_DURATIONS.has(normalized) else "idle"


func _hand_for_action(action: String) -> String:
	return _batting_side if action == "swing" else _throwing_hand


func _facing_sign() -> int:
	if absf(_facing_direction.x) > 0.08:
		return 1 if _facing_direction.x >= 0.0 else -1
	return -1 if _hand_for_action(_current_action) == "left" else 1


func _normalized_hand(value: String) -> String:
	return "left" if value.strip_edges().to_lower().begins_with("l") else "right"


func _as_color(value: Variant, fallback: Color) -> Color:
	if value is Color:
		return value
	return Color.from_string(String(value), fallback)


func _quantized_shadow(color: Color) -> Color:
	return Color(
		floor(color.r * 4.0) / 4.0,
		floor(color.g * 4.0) / 4.0,
		floor(color.b * 4.0) / 4.0,
		color.a,
	).darkened(0.22)
