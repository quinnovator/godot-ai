class_name PixiballSim
extends RefCounted

## Deterministic, presentation-free arcade baseball rules and plate simulator.
##
## The class deliberately owns no Nodes, resources, timers, or input state. A
## caller supplies semantic actions, commits the result beat, and decides when
## to advance. This keeps gameplay replayable in editor, headless, and agent
## sessions with the same seed and action sequence.

const PHASE_PITCH := "pitch"
const PHASE_LIVE_PLAY := "live_play"
const PHASE_RESULT := "result"
const PHASE_GAME_OVER := "game_over"

const SIDE_AWAY := "away"
const SIDE_HOME := "home"

const STRIKE_HALF_WIDTH_FT := 17.0 / 24.0
const STRIKE_BOTTOM_FT := 1.5
const STRIKE_TOP_FT := 3.5
const RELEASE_DISTANCE_FT := 54.5
const MPH_TO_FPS := 1.4666666667
const GRAVITY_FPS2 := 32.174
const EVENT_LIMIT := 64
const PitchModelScript = preload("res://core/model/pitch_model.gd")
const PixRngScript = preload("res://core/model/pix_rng.gd")
const StaminaConfigScript = preload("res://gameplay/stamina_config.gd")
const PitcherConditionScript = preload("res://gameplay/pitcher_condition.gd")
const PitcherDisplayScript = preload("res://gameplay/pitcher_display.gd")
const TeamsScript = preload("res://gameplay/teams.gd")
const BullpenScript = preload("res://gameplay/bullpen.gd")
const SemanticDefenseScript = preload("res://core/fielding/semantic_defense.gd")

# Fictional, deliberately generic pitch profiles. They encode gameplay feel,
# not player likenesses or licensed statistics.
const PITCH_LIBRARY := {
	"four_seam": {
		"label": "Four-Seam",
		"velocity": 95.0,
		"velocity_jitter": 1.4,
		"break_x": 0.10,
		"break_z": 0.78,
		"command": 0.24,
		"whiff": 0.23,
		"usage": 0.34,
	},
	"sinker": {
		"label": "Sinker",
		"velocity": 92.0,
		"velocity_jitter": 1.5,
		"break_x": -0.58,
		"break_z": 0.18,
		"command": 0.28,
		"whiff": 0.14,
		"usage": 0.20,
	},
	"slider": {
		"label": "Slider",
		"velocity": 86.0,
		"velocity_jitter": 1.8,
		"break_x": 0.82,
		"break_z": -0.22,
		"command": 0.34,
		"whiff": 0.34,
		"usage": 0.19,
	},
	"curveball": {
		"label": "Curveball",
		"velocity": 80.0,
		"velocity_jitter": 1.7,
		"break_x": 0.22,
		"break_z": -1.08,
		"command": 0.38,
		"whiff": 0.29,
		"usage": 0.13,
	},
	"changeup": {
		"label": "Changeup",
		"velocity": 84.0,
		"velocity_jitter": 1.6,
		"break_x": -0.42,
		"break_z": 0.12,
		"command": 0.31,
		"whiff": 0.27,
		"usage": 0.14,
	},
}

var _seed: int = 1
var _rng_state: int = 1
var _epoch: int = 0
var _innings: int = 3
var _difficulty: float = 0.5

var _inning: int = 1
var _half: String = "top"
var _balls: int = 0
var _strikes: int = 0
var _outs: int = 0
var _bases: Array[bool] = [false, false, false]
var _score := {SIDE_AWAY: 0, SIDE_HOME: 0}
var _hits := {SIDE_AWAY: 0, SIDE_HOME: 0}
var _line_score := {SIDE_AWAY: [0], SIDE_HOME: [0]}
var _batter_index := {SIDE_AWAY: 0, SIDE_HOME: 0}
var _batters_faced := {SIDE_AWAY: 0, SIDE_HOME: 0}
var _pitch_number: int = 1

var _phase: String = PHASE_PITCH
var _pitch_serial: int = 0
var _active_pitch: Dictionary = {}
var _active_play: Dictionary = {}
var _last_result: Dictionary = {}
var _pending_half_end: bool = false
var _pending_game_over: bool = false
var _game_over: bool = false
var _winner: String = ""

var _event_serial: int = 0
var _recent_events: Array[Dictionary] = []

# Optional replica-fidelity services. Unit tests and downstream games can keep
# using the compact fallback library; the shipped Pixiball scene configures the
# authorized original arsenals and native four-booster model.
var _pitch_model: Variant
var _user_pitcher: Dictionary = {}
var _cpu_pitcher: Dictionary = {}
var _user_arsenal: Dictionary = {}
var _cpu_arsenal: Dictionary = {}
var _previous_by_owner := {"user": {}, "cpu": {}}
var _last_pitch_report: Dictionary = {}
var _replica_enabled := false

# Full-replica condition, team, and staff state. The compact quick-game path
# uses the same fresh condition math once a replica arsenal is configured.
var _mode := "quick"
var _stamina_config: Dictionary = StaminaConfigScript.defaults()
var _pitcher_cards: Dictionary = {}
var _home_team: Dictionary = {}
var _away_team: Dictionary = {}
var _home_bat_quality := 0.0
var _away_bat_quality := 0.0
var _home_staff: Array[Dictionary] = []
var _away_staff: Array[Dictionary] = []
var _home_bullpen: Dictionary = BullpenScript.fresh_state()
var _away_bullpen: Dictionary = BullpenScript.fresh_state()
var _pitcher_conditions: Dictionary = {}
var _manager_events: Array[Dictionary] = []
var _lineups := {SIDE_AWAY: [], SIDE_HOME: []}
var _batter_archetypes: Array = []


func _init(seed_value: int = 1, innings_value: int = 3, difficulty_value: float = 0.5) -> void:
	reset(seed_value, innings_value, difficulty_value)


func reset(seed_value: int = 1, innings_value: int = 3, difficulty_value: float = 0.5) -> Dictionary:
	# A direct reset is a new epoch-zero session and therefore retains the
	# existing golden behavior for a visible seed. Rematches use restart().
	_epoch = 0
	return _reset_match_state(seed_value, innings_value, difficulty_value)


func restart() -> Dictionary:
	# GameSim.cpp::Restart advances FPixStreams::Epoch while preserving the
	# visible seed/configuration. All keyed domains read _stream_epoch(), while
	# the compact fallback RNG receives a separately derived epoch seed.
	_epoch = (_epoch + 1) & 0xffffffff
	return _reset_match_state(_seed, _innings, _difficulty)


func _reset_match_state(seed_value: int, innings_value: int, difficulty_value: float) -> Dictionary:
	_seed = seed_value & 0xffffffff
	if _epoch == 0:
		# Frozen legacy path: do not alter epoch-zero quick-game golden behavior.
		_rng_state = _seed if _seed != 0 else 0x6d2b79f5
	else:
		_rng_state = PixRngScript.stream_seed(_seed, _epoch, 0, 0)
		if _rng_state == 0:
			_rng_state = 0x6d2b79f5
	_innings = maxi(1, innings_value)
	_difficulty = clampf(difficulty_value, 0.0, 1.0)
	_inning = 1
	_half = "top"
	_balls = 0
	_strikes = 0
	_outs = 0
	_bases = [false, false, false]
	_score = {SIDE_AWAY: 0, SIDE_HOME: 0}
	_hits = {SIDE_AWAY: 0, SIDE_HOME: 0}
	_line_score = {SIDE_AWAY: [0], SIDE_HOME: [0]}
	_batter_index = {SIDE_AWAY: 0, SIDE_HOME: 0}
	_batters_faced = {SIDE_AWAY: 0, SIDE_HOME: 0}
	_pitch_number = 1
	_phase = PHASE_PITCH
	_pitch_serial = 0
	_active_pitch.clear()
	_active_play.clear()
	_last_result.clear()
	_pending_half_end = false
	_pending_game_over = false
	_game_over = false
	_winner = ""
	_event_serial = 0
	_recent_events.clear()
	_previous_by_owner = {"user": {}, "cpu": {}}
	_last_pitch_report.clear()
	_reset_conditions_and_bullpens()
	_rebuild_versus_lineups()
	_emit("game_reset", {"seed": _seed, "epoch": _epoch, "innings": _innings, "difficulty": _difficulty})
	return snapshot()


func configure_replica(user_pitcher: Dictionary, cpu_pitcher: Dictionary, model: Variant) -> Dictionary:
	_mode = "quick"
	_home_team.clear()
	_away_team.clear()
	_home_bat_quality = 0.0
	_away_bat_quality = 0.0
	_home_staff = [user_pitcher.duplicate(true)]
	_away_staff = [cpu_pitcher.duplicate(true)]
	_pitcher_cards = PitcherDisplayScript.build_cache(_home_staff + _away_staff)
	_lineups = {SIDE_AWAY: [], SIDE_HOME: []}
	_batter_archetypes = []
	return _configure_active_pitchers(user_pitcher, cpu_pitcher, model, true)


func _configure_active_pitchers(user_pitcher: Dictionary, cpu_pitcher: Dictionary, model: Variant, rebuild_conditions: bool) -> Dictionary:
	if model == null or not bool(model.is_valid()):
		_replica_enabled = false
		return _error("model_unavailable", "The trained pitch model is not available")
	if (user_pitcher.get("pitches", []) as Array).size() != 5 or (cpu_pitcher.get("pitches", []) as Array).size() != 5:
		_replica_enabled = false
		return _error("invalid_arsenal", "Replica pitchers require exactly five pitches")
	_pitch_model = model
	_user_pitcher = user_pitcher.duplicate(true)
	_cpu_pitcher = cpu_pitcher.duplicate(true)
	_user_arsenal = _index_arsenal(_user_pitcher)
	_cpu_arsenal = _index_arsenal(_cpu_pitcher)
	_previous_by_owner = {"user": {}, "cpu": {}}
	_last_pitch_report.clear()
	_replica_enabled = true
	if rebuild_conditions:
		_build_pitcher_conditions()
	return {
		"ok": true,
		"user_pitcher": String(_user_pitcher.get("name", "")),
		"cpu_pitcher": String(_cpu_pitcher.get("name", "")),
		"pitch_slots": (_user_pitcher.get("pitches", []) as Array).size(),
	}


func configure_versus(home_team: Dictionary, away_team: Dictionary, catalog: Variant, model: Variant = null) -> Dictionary:
	var all_pitchers: Array = _catalog_array(catalog, "pitchers")
	var archetypes: Array = _catalog_array(catalog, "batter_archetypes")
	if home_team.is_empty() or away_team.is_empty():
		return _error("invalid_team", "Versus mode requires home and away teams")
	if all_pitchers.size() < 2:
		return _error("invalid_catalog", "Versus mode requires at least two catalog pitchers")
	var use_model: Variant = model if model != null else _pitch_model
	if use_model == null or not bool(use_model.is_valid()):
		return _error("model_unavailable", "The trained pitch model is not available")

	# Exact ranking and alternating draft from the original Teams.cpp. The
	# higher-PIT team picks first; home wins a tie.
	_pitcher_cards = PitcherDisplayScript.build_cache(all_pitchers)
	var drafted := TeamsScript.build_versus_rosters(all_pitchers, _pitcher_cards, home_team, away_team)
	_home_staff.assign(drafted.home)
	_away_staff.assign(drafted.away)
	if _home_staff.is_empty() or _away_staff.is_empty():
		return _error("invalid_roster", "Versus draft produced an empty pitching staff")
	_mode = "versus"
	_home_team = home_team.duplicate(true)
	_away_team = away_team.duplicate(true)
	_home_bat_quality = TeamsScript.bat_quality(_home_team)
	_away_bat_quality = TeamsScript.bat_quality(_away_team)
	_batter_archetypes = archetypes.duplicate(true)
	_rebuild_versus_lineups()
	var configured := _configure_active_pitchers(_home_staff[0], _away_staff[0], use_model, true)
	if not bool(configured.get("ok", false)):
		return configured
	_emit("versus_configured", {
		"home_team": String(_home_team.get("id", "")),
		"away_team": String(_away_team.get("id", "")),
		"home_staff": _home_staff.size(),
		"away_staff": _away_staff.size(),
	})
	return {
		"ok": true,
		"mode": _mode,
		"home_team": _home_team.duplicate(true),
		"away_team": _away_team.duplicate(true),
		"home_staff": _staff_snapshot(_home_staff),
		"away_staff": _staff_snapshot(_away_staff),
	}


func set_stamina_config(config: Dictionary) -> Dictionary:
	if not StaminaConfigScript.validate(config):
		return _error("invalid_stamina_config", "The stamina configuration is invalid")
	_stamina_config = config.duplicate(true)
	_build_pitcher_conditions()
	return {"ok": true, "config": _stamina_config.duplicate(true)}


func stamina_config() -> Dictionary:
	return _stamina_config.duplicate(true)


func replica_enabled() -> bool:
	return _replica_enabled


func user_pitcher() -> Dictionary:
	return _user_pitcher.duplicate(true)


func cpu_pitcher() -> Dictionary:
	return _cpu_pitcher.duplicate(true)


func last_pitch_report() -> Dictionary:
	return _last_pitch_report.duplicate(true)


# -- Side and phase queries -------------------------------------------------

func batting_side() -> String:
	return SIDE_AWAY if _half == "top" else SIDE_HOME


func fielding_side() -> String:
	return SIDE_HOME if _half == "top" else SIDE_AWAY


func is_user_pitching() -> bool:
	return not _game_over and _half == "top"


func is_user_batting() -> bool:
	return not _game_over and _half == "bottom"


func is_user_fielding() -> bool:
	return is_user_pitching() and _phase == PHASE_LIVE_PLAY


func is_user_running() -> bool:
	return is_user_batting() and _phase == PHASE_LIVE_PLAY


func is_pitch_phase() -> bool:
	return _phase == PHASE_PITCH


func is_live_play() -> bool:
	return _phase == PHASE_LIVE_PLAY


func is_result_phase() -> bool:
	return _phase == PHASE_RESULT


func is_game_over() -> bool:
	return _game_over


func phase() -> String:
	return _phase


# -- Pitch creation --------------------------------------------------------

func create_cpu_pitch() -> Dictionary:
	if not is_user_batting():
		return _error("wrong_side", "CPU pitches only while the user is batting")
	if _phase != PHASE_PITCH:
		return _error("wrong_phase", "A pitch can only be created in the pitch phase")
	if not _active_pitch.is_empty():
		return _active_pitch.duplicate(true)
	_last_pitch_report.clear()

	var kind := _choose_cpu_pitch_kind()
	var aim := _choose_cpu_aim()
	var effort := _choose_cpu_effort()
	# Higher difficulty improves command without becoming mechanically perfect.
	var command_scale := lerpf(1.35, 0.62, _difficulty)
	_active_pitch = _build_pitch(kind, aim, command_scale, "cpu", effort)
	_emit("pitch_created", _pitch_event_payload(_active_pitch))
	return _active_pitch.duplicate(true)


func create_user_pitch(kind_value: String, aim_value: Variant, effort_value: String = "normal") -> Dictionary:
	if not is_user_pitching():
		return _error("wrong_side", "The user pitches only in the top half")
	if _phase != PHASE_PITCH:
		return _error("wrong_phase", "A pitch can only be created in the pitch phase")
	if not _active_pitch.is_empty():
		return _active_pitch.duplicate(true)
	_last_pitch_report.clear()

	var kind := _normalize_pitch_kind(kind_value)
	if _profile_for_kind(kind, "user").is_empty():
		return _error("unknown_pitch", "Unknown pitch kind: %s" % kind_value)
	var aim := _read_point(aim_value, Vector2(0.0, 2.5))
	aim.x = clampf(aim.x, -1.6, 1.6)
	aim.y = clampf(aim.y, 0.8, 4.2)
	var effort := _normalize_effort(effort_value)
	if effort.is_empty():
		return _error("unknown_effort", "Pitch effort must be cruise, normal, or high")
	_active_pitch = _build_pitch(kind, aim, 1.0, "user", effort)
	_emit("pitch_created", _pitch_event_payload(_active_pitch))
	return _active_pitch.duplicate(true)


func _build_pitch(kind: String, aim: Vector2, command_scale: float, owner: String, effort: String = "normal") -> Dictionary:
	var profile := _profile_for_kind(kind, owner)
	if profile.is_empty():
		return _error("unknown_pitch", "Unknown pitch kind: %s" % kind)
	_pitch_serial += 1
	if _replica_enabled and profile.has("shape"):
		return _build_replica_pitch(kind, profile, aim, command_scale, owner, effort)
	var velocity := clampf(
		float(profile.velocity) + _gaussian() * float(profile.velocity_jitter),
		68.0,
		103.0
	)
	var command := float(profile.command) * command_scale
	var actual := Vector2(
		aim.x + _gaussian() * command,
		aim.y + _gaussian() * command
	)
	var flight_sec := RELEASE_DISTANCE_FT / (velocity * MPH_TO_FPS)
	return {
		"ok": true,
		"serial": _pitch_serial,
		"owner": owner,
		"effort": effort,
		"kind": kind,
		"label": profile.label,
		"target": [aim.x, aim.y],
		"actual": [actual.x, actual.y],
		"velocity_mph": velocity,
		"flight_sec": flight_sec,
		"break_ft": [float(profile.break_x), float(profile.break_z)],
		"whiff_rating": float(profile.whiff),
		"in_zone": _is_in_zone(actual.x, actual.y),
		"path": {
			"release_ft": [0.0, RELEASE_DISTANCE_FT, 6.0],
			"plate_ft": [actual.x, 0.0, actual.y],
			"flight_sec": flight_sec,
			"break_ft": [float(profile.break_x), float(profile.break_z)],
		},
	}


func _build_replica_pitch(kind: String, profile: Dictionary, aim: Vector2, command_scale: float, owner: String, effort: String) -> Dictionary:
	var base_shape: Dictionary = (profile.shape as Dictionary).duplicate(true)
	var condition := _active_condition(owner)
	var fatigue := PitcherConditionScript.fatigue_factors(condition, _stamina_config) if not condition.is_empty() else {
		"velocity_mul": 1.0,
		"movement_mul": 1.0,
		"command_std_add": 0.0,
		"tier": "fresh",
		"stamina_fraction": 1.0,
	}
	var velocity_add := float((_stamina_config.get("effort_velocity_add", {}) as Dictionary).get(effort, 0.0))
	var shape: Dictionary = PitcherConditionScript.degrade_shape(base_shape, velocity_add, fatigue, _stamina_config) if bool(_stamina_config.get("enabled", true)) else base_shape
	shape["controlXStd"] = float(shape.get("controlXStd", 0.0)) * command_scale
	shape["controlZStd"] = float(shape.get("controlZStd", 0.0)) * command_scale
	var pitcher := _user_pitcher if owner == "user" else _cpu_pitcher
	var batter_index := int(_batter_index[batting_side()])
	var batter_profile := _batter_profile(batting_side(), batter_index)
	var previous: Dictionary = _previous_by_owner.get(owner, {})
	var effective_aim := aim
	var recognition_score := 0.0
	var bucket := PitcherConditionScript.bucket_location(effective_aim.x, effective_aim.y)
	if bool(_stamina_config.get("enabled", true)) and not condition.is_empty():
		# Command wobble has its own keyed stream. It cannot perturb model or
		# outcome streams, and at full stamina its zero deviation preserves the
		# original first-pitch result exactly.
		# ERngDomain::Command is ordinal 5 in the original keyed-stream table.
		var command_rng = PixRngScript.new(PixRngScript.stream_seed(_seed, _stream_epoch(), 5, _pitch_serial))
		effective_aim.x += command_rng.gauss(0.0, float(fatigue.command_std_add))
		effective_aim.y += command_rng.gauss(0.0, float(fatigue.command_std_add))
		bucket = PitcherConditionScript.bucket_location(effective_aim.x, effective_aim.y)
		recognition_score = PitcherConditionScript.repetitiveness_score(condition, int(profile.get("slot", 0)), bucket, _stamina_config)
		PitcherConditionScript.deplete_stamina(condition, String(profile.get("code", kind.to_upper())), effort, {
			"runners_in_scoring_position": _bases[1] or _bases[2],
			"two_strike": _strikes == 2,
			"three_ball": _balls == 3,
		}, _stamina_config)
		PitcherConditionScript.record_pitch(condition, int(profile.get("slot", 0)), bucket, _stamina_config)
	var request := {
		"shape": shape,
		"p_throws": String(pitcher.get("throws", "R")),
		"batter": {
			"archetype_encoded": int(batter_profile.get("archetype_encoded", batter_index % 5)),
			"stand": String(batter_profile.get("stand", "L" if batter_index % 3 == 1 else "R")),
		},
		"ab": {
			"balls": _balls,
			"strikes": _strikes,
			"outs": _outs,
			# Rules.cpp keeps a true 1-based delivered-pitch counter. Deriving this
			# from the count loses every two-strike foul and corrupts model features.
			"pitch_number": _pitch_number,
			"times_through_order": int(int(_batters_faced[batting_side()]) / 9) + 1,
		},
		"prev": previous if not previous.is_empty() else null,
		"target_x": effective_aim.x,
		"target_z": effective_aim.y,
	}
	var model_rng = PixRngScript.new(PixRngScript.stream_seed(_seed, _stream_epoch(), 6, _pitch_serial))
	var model_result: Dictionary = _pitch_model.query(request, model_rng)
	if not bool(model_result.get("ok", false)):
		return _error("model_query_failed", String(model_result.get("error", "Pitch model query failed")))
	var actual := Vector2(float(model_result.actual_x), float(model_result.actual_z))
	var velocity := float(shape.get("velocity", 90.0))
	var flight_sec := RELEASE_DISTANCE_FT / (velocity * MPH_TO_FPS)
	var location_class := PitchModelScript.classify_location(model_result, String(request.batter.stand))
	var slot := int(profile.get("slot", 0))
	var outcome_model_result := PitcherConditionScript.apply_recognition(model_result, recognition_score, _stamina_config) if owner == "user" and bool(_stamina_config.get("enabled", true)) else model_result.duplicate(true)
	var context := request.duplicate(true)
	context["slot"] = slot
	var catalog_arsenal: Array = (_user_pitcher.get("pitches", []) as Array).duplicate(true) if owner == "user" else (_cpu_pitcher.get("pitches", []) as Array).duplicate(true)
	# AtBat.cpp builds every counterfactual option from the same pre-pitch
	# fatigue/effort snapshot as the thrown pitch, then PitchModel.build_report
	# zeroes control scatter at the aim point. Feeding fresh catalog shapes here
	# would overstate tired arms and produce unrealistic ERV/rank advice.
	context["catalog_arsenal"] = catalog_arsenal.duplicate(true)
	context["arsenal"] = _report_option_arsenal(catalog_arsenal, velocity_add, fatigue)
	context["report_condition"] = {
		"effort": effort,
		"velocity_add": velocity_add,
		"fatigue": fatigue.duplicate(true),
	}
	context["seed"] = PixRngScript.stream_seed(_seed, _stream_epoch(), 6, _pitch_serial ^ 0x504958)
	return {
		"ok": true,
		"serial": _pitch_serial,
		"owner": owner,
		"effort": effort,
		"kind": kind,
		"code": String(profile.get("code", kind.to_upper())),
		"label": String(profile.get("name", kind.to_upper())),
		"name": String(profile.get("name", kind.to_upper())),
		"slot": slot,
		"target": [aim.x, aim.y],
		"commanded_target": [effective_aim.x, effective_aim.y],
		"actual": [actual.x, actual.y],
		"velocity_mph": velocity,
		"flight_sec": flight_sec,
		"break_ft": [float(shape.get("pfxX", 0.0)), float(shape.get("pfxZ", 0.0))],
		"whiff_rating": float(profile.get("whiffRate", 0.2)),
		"in_zone": bool(model_result.in_zone),
		"shape": shape,
		"model_result": model_result,
		"outcome_model_result": outcome_model_result,
		"model_context": context,
		"recognition_score": recognition_score,
		"fatigue": fatigue.duplicate(true),
		"condition_after": PitcherConditionScript.describe(condition, _stamina_config, 5) if not condition.is_empty() else {},
		"feedback": location_class,
		"path": {
			"release_ft": [float(shape.get("releaseX", 0.0)), RELEASE_DISTANCE_FT, float(shape.get("releaseZ", 6.0))],
			"plate_ft": [actual.x, 0.0, actual.y],
			"tunnel_ft": [float(model_result.tunnel_x), 0.0, float(model_result.tunnel_z)],
			"flight_sec": flight_sec,
			"break_ft": [float(shape.get("pfxX", 0.0)), float(shape.get("pfxZ", 0.0))],
		},
	}


func _report_option_arsenal(catalog_arsenal: Array, velocity_add: float, fatigue: Dictionary) -> Array[Dictionary]:
	var options: Array[Dictionary] = []
	for pitch_value in catalog_arsenal:
		var pitch: Dictionary = pitch_value
		if bool(_stamina_config.get("enabled", true)):
			options.append(PitcherConditionScript.degrade_shape(pitch, velocity_add, fatigue, _stamina_config))
		else:
			options.append(pitch.duplicate(true))
	return options


func _choose_cpu_pitch_kind() -> String:
	var kinds: Array[String] = []
	var weights: Array[float] = []
	var behind := _balls >= 2 and _balls > _strikes
	var ahead := _strikes == 2 and _balls < 3
	var source: Dictionary = _cpu_arsenal if _replica_enabled else PITCH_LIBRARY
	var condition := _active_condition("cpu")
	var recent_bucket := -1
	if _replica_enabled and not condition.is_empty() and int(condition.get("short_len", 0)) > 0:
		var history: Array = condition.get("short_history", [])
		if not history.is_empty():
			var latest: Dictionary = history[posmod(int(condition.get("short_head", 0)) - 1, history.size())]
			recent_bucket = int(latest.get("loc_bucket", -1))
	for kind_value in source.keys():
		var kind := String(kind_value)
		var profile: Dictionary = source[kind]
		var weight := float(profile.get("usage", 0.2))
		if behind and float(profile.velocity) >= 91.0:
			weight *= 1.8
		if ahead:
			weight *= 1.0 + float(profile.get("whiff", profile.get("whiffRate", 0.2))) * 2.2
		# Keep the CPU from spamming its previous pitch in agent play sessions.
		if not _last_result.is_empty() and _last_result.get("pitch_kind", "") == kind:
			weight *= 0.62
		if recent_bucket >= 0:
			var repetition := PitcherConditionScript.repetitiveness_score(condition, int(profile.get("slot", kinds.size())), recent_bucket, _stamina_config)
			weight *= maxf(0.0, 1.0 - float(_stamina_config.get("anti_rep_penalty", 0.25)) * repetition)
		kinds.append(kind)
		weights.append(weight)
	return kinds[_weighted_index(weights)]


func _choose_cpu_effort() -> String:
	if not _replica_enabled or not bool(_stamina_config.get("enabled", true)):
		return "normal"
	var condition := _active_condition("cpu")
	if condition.is_empty():
		return "normal"
	var tier := String(PitcherConditionScript.fatigue_factors(condition, _stamina_config).tier)
	# Exact effort decision from CpuPitcher.cpp::ChooseEffort.
	if tier in ["tired", "gassed"]:
		return "cruise"
	if (_strikes == 2 or _bases[1] or _bases[2]) and tier in ["fresh", "tiring"]:
		return "high"
	var cpu_side := SIDE_AWAY
	var score_diff := int(_score[cpu_side]) - int(_score[SIDE_HOME])
	if absi(score_diff) >= 4:
		return "cruise"
	return "normal"


func _profile_for_kind(kind: String, owner: String) -> Dictionary:
	if _replica_enabled:
		var source: Dictionary = _user_arsenal if owner == "user" else _cpu_arsenal
		if source.has(kind):
			return source[kind]
	if PITCH_LIBRARY.has(kind):
		return PITCH_LIBRARY[kind]
	return {}


func _index_arsenal(pitcher: Dictionary) -> Dictionary:
	var indexed := {}
	var pitches: Array = pitcher.get("pitches", [])
	for slot in range(pitches.size()):
		var pitch: Dictionary = pitches[slot]
		var kind := String(pitch.get("code", "P%d" % slot)).to_lower()
		indexed[kind] = {
			"slot": slot,
			"code": String(pitch.get("code", kind.to_upper())),
			"name": String(pitch.get("name", kind.to_upper())),
			"label": String(pitch.get("name", kind.to_upper())),
			"velocity": float(pitch.get("velocity", 90.0)),
			"usage": float(pitch.get("usage", 0.2)),
			"whiffRate": float(pitch.get("whiffRate", 0.2)),
			"shape": pitch.duplicate(true),
		}
	return indexed


func _choose_cpu_aim() -> Vector2:
	var behind := _balls >= 2 and _balls > _strikes
	var ahead := _strikes == 2 and _balls < 3
	var pool: Array[Vector2]
	if behind:
		pool = [Vector2(0.0, 2.5), Vector2(-0.55, 2.0), Vector2(0.55, 3.0)]
	elif ahead:
		pool = [Vector2(-0.92, 1.3), Vector2(0.92, 1.3), Vector2(0.0, 3.85), Vector2(0.68, 2.5)]
	else:
		pool = [
			Vector2(0.0, 2.5),
			Vector2(-0.62, 1.85),
			Vector2(0.62, 3.15),
			Vector2(-0.82, 2.55),
			Vector2(0.0, 1.25),
		]
	var chosen := pool[_randi_range(0, pool.size() - 1)]
	var intent_wobble := 0.20 * (1.0 - _difficulty)
	return Vector2(
		chosen.x + _gaussian() * intent_wobble,
		chosen.y + _gaussian() * intent_wobble
	)


# -- Plate resolution ------------------------------------------------------

func resolve_cpu_batter(pitch: Dictionary) -> Dictionary:
	var validation := _validate_pitch_for_resolution(pitch, "user")
	if not validation.is_empty():
		return validation
	if pitch.has("model_result"):
		return _resolve_model_cpu_batter(pitch)

	var actual := _pitch_actual(pitch)
	var in_zone := _is_in_zone(actual.x, actual.y)
	var edge := _is_edge_pitch(actual.x, actual.y)
	var two_strikes := _strikes == 2
	var swing_probability := lerpf(0.57, 0.76, _difficulty) if in_zone else lerpf(0.14, 0.34, _difficulty)
	if two_strikes:
		swing_probability += 0.12
	if edge:
		swing_probability -= 0.06
	swing_probability = clampf(swing_probability, 0.04, 0.94)
	if _randf() >= swing_probability:
		return _taken_pitch_result(pitch, actual, "cpu")

	var recognition_error := lerpf(0.42, 0.16, _difficulty)
	var barrel := Vector2(
		actual.x + _gaussian() * recognition_error,
		actual.y + _gaussian() * recognition_error
	)
	var timing_error := _gaussian() * lerpf(0.115, 0.052, _difficulty)
	return _resolve_swing(pitch, barrel, timing_error, "cpu")


func _resolve_model_cpu_batter(pitch: Dictionary) -> Dictionary:
	# The report keeps the raw model result, while the CPU's swing/contact draw
	# uses the recognition-shifted copy just like AtBat.cpp.
	var model_result: Dictionary = pitch.get("outcome_model_result", pitch.model_result)
	var probabilities: Dictionary = model_result.get("probabilities", {})
	var weights: Array[float] = [
		float(probabilities.get("ball", 0.0)),
		float(probabilities.get("called_strike", 0.0)),
		float(probabilities.get("swinging_strike", 0.0)),
		float(probabilities.get("foul", 0.0)),
		float(probabilities.get("in_play", 0.0)),
	]
	var selection := _weighted_index(weights)
	var outcomes := ["ball", "called_strike", "swinging_strike", "foul", "in_play"]
	var outcome := String(outcomes[selection])
	var result := {
		"ok": true,
		"outcome": outcome,
		"actor": "cpu",
		"pitch_serial": int(pitch.serial),
		"pitch_kind": String(pitch.kind),
		"model_result": model_result.duplicate(true),
	}
	if outcome != "in_play":
		result["swung"] = outcome in ["swinging_strike", "foul"]
		return result
	# The model intentionally omits stage-two and launch sampling when its raw
	# in-play probability is below the trained threshold. If the categorical
	# draw still lands in that tiny bucket, the original AtBat contract records
	# a foul rather than creating an impossible zero-mph live ball.
	if float(model_result.get("sampled_launch_speed", 0.0)) <= 0.0:
		result["outcome"] = "foul"
		result["swung"] = true
		result["model_in_play_without_launch"] = true
		return result
	var batter_index := int(_batter_index[batting_side()])
	var pull_sign := -1.0 if batter_index % 2 == 0 else 1.0
	var spray := clampf(pull_sign * _gaussian() * 14.0, -44.0, 44.0)
	result["swung"] = true
	result["quality"] = "model_contact"
	result["contact_quality"] = clampf((float(model_result.sampled_launch_speed) - 30.0) / 90.0, 0.0, 1.0)
	result["trajectory"] = _make_batted_ball(
		float(model_result.sampled_launch_speed),
		float(model_result.sampled_launch_angle),
		spray,
		float(result.contact_quality)
	)
	return result


func resolve_user_batter(pitch: Dictionary, swing: Dictionary) -> Dictionary:
	var validation := _validate_pitch_for_resolution(pitch, "cpu")
	if not validation.is_empty():
		return validation
	var actual := _pitch_actual(pitch)
	if not bool(swing.get("did_swing", swing.get("swing", true))):
		return _taken_pitch_result(pitch, actual, "user")

	var barrel_value: Variant = swing.get("reticle", swing.get("barrel", [0.0, 2.5]))
	var barrel := _read_point(barrel_value, Vector2(0.0, 2.5))
	var timing_error: float
	if swing.has("timing_error_sec"):
		timing_error = float(swing.timing_error_sec)
	elif swing.has("timing_ms"):
		timing_error = float(swing.timing_ms) / 1000.0
	else:
		var pressed_at := float(swing.get("pressed_at_sec", swing.get("timing_sec", float(pitch.flight_sec) - 0.15)))
		# The input commits a swing whose barrel arrives 150 ms after the press.
		timing_error = pressed_at + 0.15 - float(pitch.flight_sec)
	return _resolve_swing(pitch, barrel, timing_error, "user")


func _resolve_swing(pitch: Dictionary, barrel: Vector2, timing_error: float, actor: String) -> Dictionary:
	var actual := _pitch_actual(pitch)
	var location_error := actual.distance_to(barrel) / 0.9
	var timing_window := 0.13
	if actor == "user":
		# Rookie adds a small accessibility cushion without changing the display
		# timing supplied by the caller.
		timing_window += (1.0 - _difficulty) * 0.025
		# Repeated CPU sequencing is easier for a human hitter to time, matching
		# AtBat.cpp's recognition-derived HumanTimingToleranceMax allowance.
		if bool(_stamina_config.get("enabled", true)):
			timing_window += float(pitch.get("recognition_score", 0.0)) * float(_stamina_config.get("human_timing_tolerance_max", 0.08))
	var timing_norm := absf(timing_error) / timing_window
	var miss_metric := sqrt(0.55 * location_error * location_error + 0.45 * timing_norm * timing_norm)
	var quality := _swing_quality(miss_metric, location_error, timing_error)
	var pitch_whiff := float(pitch.get("whiff_rating", 0.22))
	var model_result: Dictionary = pitch.get("model_result", {})
	if not model_result.is_empty():
		var probabilities: Dictionary = model_result.get("probabilities", {})
		var swing_total := (
			float(probabilities.get("swinging_strike", 0.0))
			+ float(probabilities.get("foul", 0.0))
			+ float(probabilities.get("in_play", 0.0))
		)
		if swing_total > 0.0:
			pitch_whiff = float(probabilities.get("swinging_strike", 0.0)) / swing_total
	var whiff_probability := 1.0 if miss_metric >= 1.0 else clampf(
		0.12 * pitch_whiff + 0.88 * _smoothstep(0.36, 1.0, miss_metric),
		0.0,
		1.0
	)
	if _randf() < whiff_probability:
		return {
			"ok": true,
			"outcome": "swinging_strike",
			"actor": actor,
			"pitch_serial": int(pitch.serial),
			"pitch_kind": String(pitch.kind),
			"swung": true,
			"quality": "miss",
			"timing_ms": roundi(timing_error * 1000.0),
			"location_error_ft": actual.distance_to(barrel),
		}

	var contact_quality := 1.0 - _smoothstep(0.0, 1.0, miss_metric)
	var foul_probability := clampf(0.10 + 0.72 * _smoothstep(0.28, 0.95, miss_metric), 0.0, 0.9)
	var pull_sign := -1.0 if (int(_batter_index[batting_side()]) % 2 == 0) else 1.0
	var spray := pull_sign * clampf(-timing_error / 0.075, -1.0, 1.0) * 27.0 + _gaussian() * 7.0
	if absf(spray) > 45.0 or _randf() < foul_probability:
		return {
			"ok": true,
			"outcome": "foul",
			"actor": actor,
			"pitch_serial": int(pitch.serial),
			"pitch_kind": String(pitch.kind),
			"swung": true,
			"quality": quality,
			"timing_ms": roundi(timing_error * 1000.0),
			"location_error_ft": actual.distance_to(barrel),
		}

	var model_exit_velocity := float(model_result.get("sampled_launch_speed", 82.0))
	var model_launch_angle := float(model_result.get("sampled_launch_angle", 12.0))
	var exit_velocity := clampf(model_exit_velocity + 20.0 * (contact_quality - 0.45) + _gaussian() * 4.0, 30.0, 118.0)
	var launch_angle := clampf(
		model_launch_angle + (actual.y - barrel.y) * 24.5 + timing_error * 32.0 + _gaussian() * 5.0,
		-35.0,
		62.0
	)
	var trajectory := _make_batted_ball(exit_velocity, launch_angle, clampf(spray, -44.0, 44.0), contact_quality)
	return {
		"ok": true,
		"outcome": "in_play",
		"actor": actor,
		"pitch_serial": int(pitch.serial),
		"pitch_kind": String(pitch.kind),
		"swung": true,
		"quality": quality,
		"timing_ms": roundi(timing_error * 1000.0),
		"location_error_ft": actual.distance_to(barrel),
		"contact_quality": contact_quality,
		"trajectory": trajectory,
		"model_result": model_result.duplicate(true),
	}


func _taken_pitch_result(pitch: Dictionary, actual: Vector2, actor: String) -> Dictionary:
	var in_zone := _is_in_zone(actual.x, actual.y)
	var called_strike := in_zone
	# A small deterministic edge-call imperfection keeps takes from being a
	# perfectly transparent strike-zone oracle.
	if _is_edge_pitch(actual.x, actual.y) and _randf() < 0.25:
		called_strike = not called_strike
	return {
		"ok": true,
		"outcome": "called_strike" if called_strike else "ball",
		"actor": actor,
		"pitch_serial": int(pitch.serial),
		"pitch_kind": String(pitch.kind),
		"swung": false,
		"model_result": (pitch.get("model_result", {}) as Dictionary).duplicate(true),
	}


# -- Rule commits ----------------------------------------------------------

func commit_plate_result(result: Dictionary) -> Dictionary:
	if _phase != PHASE_PITCH or _active_pitch.is_empty():
		return _error("wrong_phase", "No active pitch is available to commit")
	if not bool(result.get("ok", true)):
		return _error("invalid_result", "Cannot commit an error result")
	if result.has("pitch_serial") and int(result.pitch_serial) != int(_active_pitch.serial):
		return _error("stale_pitch", "Result does not belong to the active pitch")

	var outcome := String(result.get("outcome", ""))
	if outcome == "in_play":
		if not result.has("trajectory"):
			return _error("missing_trajectory", "An in-play result requires a trajectory")
		_record_pitch_intel(result, "in_play", true)
		_active_play = result.duplicate(true)
		_active_pitch.clear()
		_phase = PHASE_LIVE_PLAY
		_emit("ball_in_play", {
			"pitch_serial": int(result.get("pitch_serial", _pitch_serial)),
			"trajectory": result.trajectory,
		})
		return snapshot()

	var at_bat_over := false
	match outcome:
		"ball":
			_balls += 1
			if _balls >= 4:
				_force_walk()
				at_bat_over = true
				outcome = "walk"
		"called_strike", "swinging_strike":
			_strikes += 1
			if _strikes >= 3:
				_outs += 1
				at_bat_over = true
				outcome = "strikeout"
		"foul":
			if _strikes < 2:
				_strikes += 1
		_:
			return _error("unknown_outcome", "Unsupported plate outcome: %s" % outcome)

	if at_bat_over:
		_finish_at_bat()
	else:
		_pitch_number += 1
	_pending_half_end = _outs >= 3
	_record_pitch_intel(result, outcome, at_bat_over)
	_last_result = result.duplicate(true)
	_last_result["outcome"] = outcome
	_last_result["at_bat_over"] = at_bat_over
	_last_result["pitch_kind"] = String(_active_pitch.kind)
	_active_pitch.clear()
	_phase = PHASE_RESULT
	_emit("plate_result", {
		"outcome": outcome,
		"at_bat_over": at_bat_over,
		"count": {"balls": _balls, "strikes": _strikes},
		"outs": _outs,
	})
	return snapshot()


func _record_pitch_intel(result: Dictionary, resolved_outcome: String, at_bat_over: bool) -> void:
	if not _replica_enabled or _active_pitch.is_empty() or not _active_pitch.has("model_result"):
		return
	var owner := String(_active_pitch.get("owner", "user"))
	var model_result: Dictionary = _active_pitch.model_result
	if owner == "user":
		var thrown := _active_pitch.duplicate(true)
		thrown["outcome"] = resolved_outcome
		thrown["ended_at_bat"] = "strikeout" if resolved_outcome == "strikeout" else ("walk" if resolved_outcome == "walk" else "")
		thrown["model_result"] = model_result
		_last_pitch_report = _pitch_model.build_report(_active_pitch.model_context, thrown)
		var feedback: Dictionary = _active_pitch.get("feedback", {}).duplicate(true)
		feedback["outcome"] = resolved_outcome
		feedback["strikeout"] = resolved_outcome == "strikeout"
		feedback["swinging"] = String(result.get("outcome", "")) == "swinging_strike"
		feedback["velocity_mph"] = float(_active_pitch.get("velocity_mph", 0.0))
		feedback["tunnel_diff_in"] = float(model_result.get("tunnel_diff_in", 0.0))
		feedback["break_diff_in"] = float(model_result.get("break_diff_in", 0.0))
		feedback["break_tunnel_ratio"] = float(model_result.get("break_tunnel_ratio", 1.0))
		feedback["probabilities"] = (model_result.get("probabilities", {}) as Dictionary).duplicate(true)
		_last_pitch_report["feedback"] = feedback
		_last_pitch_report["classification"] = String(feedback.get("door", "none"))
		_last_pitch_report["corner_paint"] = bool(feedback.get("corner_paint", false))
		_last_pitch_report["corner_margin_in"] = float(feedback.get("corner_margin_in", 999.0))
		_last_pitch_report["door"] = String(feedback.get("door", "none"))
		_emit("pitch_intel", {
			"serial": int(_active_pitch.get("serial", 0)),
			"report": _last_pitch_report.duplicate(true),
		})
	_previous_by_owner[owner] = {} if at_bat_over else (model_result.get("as_prev", {}) as Dictionary).duplicate(true)


func commit_live_play(result: Dictionary) -> Dictionary:
	if _phase != PHASE_LIVE_PLAY or _active_play.is_empty():
		return _error("wrong_phase", "No live ball is available to commit")
	var classification := _normalize_play_classification(String(result.get("rule_classification", result.get("classification", result.get("outcome", "")))))
	var runs_before := int(_score[batting_side()])
	var outs_before := _outs
	var is_hit := false
	var authoritative_rules := result.get("final_bases", null) is Dictionary and result.has("outs_recorded")
	if authoritative_rules:
		if classification not in ["single", "double", "triple", "home_run", "fly_out", "ground_out", "fielders_choice"]:
			return _error("unknown_play", "Unsupported live-play classification: %s" % classification)
		is_hit = classification in ["single", "double", "triple", "home_run"]
		_outs = mini(3, _outs + clampi(int(result.get("outs_recorded", 0)), 0, 3 - _outs))
		var final_bases: Dictionary = result.final_bases
		_bases = [bool(final_bases.get("first", false)), bool(final_bases.get("second", false)), bool(final_bases.get("third", false))]
		var authoritative_runs := maxi(0, int(result.get("runs", 0)))
		_score[batting_side()] = int(_score[batting_side()]) + authoritative_runs
		_ensure_line_score_inning()
		_line_score[batting_side()][_inning - 1] = int(_line_score[batting_side()][_inning - 1]) + authoritative_runs
	else:
		match classification:
			"single":
				is_hit = true
				_advance_hit(1, int(result.get("runner_bonus_bases", 0)))
			"double":
				is_hit = true
				_advance_hit(2, int(result.get("runner_bonus_bases", 0)))
			"triple":
				is_hit = true
				_advance_hit(3, 0)
			"home_run":
				is_hit = true
				_advance_hit(4, 0)
			"fly_out":
				_outs += 1
				if bool(result.get("sacrifice", result.get("deep", false))) and _outs < 3:
					_advance_existing_runners(1)
			"ground_out":
				var double_play := bool(result.get("double_play", false)) and _bases[0] and outs_before <= 1
				_outs += 2 if double_play else 1
				if double_play:
					_bases[0] = false
				elif bool(result.get("advance_runners", result.get("productive", false))) and _outs < 3:
					_advance_existing_runners(1)
			_:
				return _error("unknown_play", "Unsupported live-play classification: %s" % classification)

	if is_hit:
		_hits[batting_side()] = int(_hits[batting_side()]) + 1
	_finish_at_bat()
	_pending_half_end = _outs >= 3
	var runs_scored := int(_score[batting_side()]) - runs_before
	_last_result = result.duplicate(true)
	_last_result["outcome"] = classification
	_last_result["classification"] = classification
	_last_result["at_bat_over"] = true
	_last_result["runs"] = runs_scored
	_last_result["outs_recorded"] = _outs - outs_before
	_last_result["trajectory"] = _active_play.get("trajectory", {})
	_active_play.clear()
	_phase = PHASE_RESULT
	_emit("play_result", {
		"classification": classification,
		"runs": runs_scored,
		"outs_recorded": _outs - outs_before,
		"outs": _outs,
		"bases": _base_snapshot(),
	})
	return snapshot()


## Presentation-free trajectory resolution for tests, batch simulations, and
## agents that do not tick LivePlayController. It uses the original coarse
## intercept/throw-race model on an independent keyed Play stream, so calling
## it cannot perturb pitch-model, swing, or future pitch outcomes. Interactive
## games continue to commit the richer physical live-play result instead.
func resolve_semantic_live_play(defense: float = -1.0, batter_speed_fps: float = -1.0) -> Dictionary:
	if _phase != PHASE_LIVE_PLAY or _active_play.is_empty():
		return _error("wrong_phase", "No live ball is available to resolve")
	var batting := batting_side()
	var profile := _batter_profile(batting, int(_batter_index[batting]))
	var resolved_speed := batter_speed_fps if batter_speed_fps > 0.0 else float(profile.get("speed", 26.0))
	var resolved_defense := _difficulty if defense < 0.0 else defense
	# ERngDomain::Play is ordinal 11 in the original keyed-stream table.
	var play_rng = PixRngScript.new(PixRngScript.stream_seed(_seed, _stream_epoch(), 11, int(_active_play.get("pitch_serial", _pitch_serial))))
	var result: Dictionary = SemanticDefenseScript.resolve(
		_active_play.get("trajectory", {}), resolved_speed, resolved_defense, play_rng)
	if bool(result.get("ok", false)):
		result["pitch_serial"] = int(_active_play.get("pitch_serial", _pitch_serial))
		result["batter_speed_fps"] = clampf(resolved_speed, 23.0, 30.0)
		result["defense"] = clampf(resolved_defense, 0.0, 1.0)
	return result


func advance_after_result() -> Dictionary:
	if _phase != PHASE_RESULT:
		return _error("wrong_phase", "Only a committed result can be advanced")
	if _pending_game_over:
		_pending_game_over = false
		_game_over = true
		_phase = PHASE_GAME_OVER
		_emit("game_over", {"winner": _winner, "score": _score.duplicate(true)})
		return snapshot()
	if _pending_half_end:
		_advance_half_inning()
	else:
		_phase = PHASE_PITCH
	_last_result.clear()
	return snapshot()


func _advance_half_inning() -> void:
	if bool(_stamina_config.get("enabled", true)) and _replica_enabled:
		# The side that did not pitch in the completed half gets the original
		# eight-point recovery: away after a top half, home after a bottom.
		var rested_owner := "cpu" if _half == "top" else "user"
		var rested_condition := _active_condition(rested_owner)
		if not rested_condition.is_empty():
			PitcherConditionScript.recover_between_halves(rested_condition, _stamina_config)
	_pending_half_end = false
	_previous_by_owner = {"user": {}, "cpu": {}}
	_balls = 0
	_strikes = 0
	_outs = 0
	_pitch_number = 1
	_bases = [false, false, false]
	if _half == "top":
		# In regulation or extras, a home lead after the top means no bottom is
		# required.
		if _inning >= _innings and int(_score[SIDE_HOME]) > int(_score[SIDE_AWAY]):
			_winner = SIDE_HOME
			_game_over = true
			_phase = PHASE_GAME_OVER
			_emit("game_over", {"winner": _winner, "score": _score.duplicate(true)})
			return
		_half = "bottom"
		_phase = PHASE_PITCH
		_emit("half_started", {"inning": _inning, "half": _half})
		return

	if _inning >= _innings and int(_score[SIDE_HOME]) != int(_score[SIDE_AWAY]):
		_winner = SIDE_HOME if int(_score[SIDE_HOME]) > int(_score[SIDE_AWAY]) else SIDE_AWAY
		_game_over = true
		_phase = PHASE_GAME_OVER
		_emit("game_over", {"winner": _winner, "score": _score.duplicate(true)})
		return
	_half = "top"
	_inning += 1
	_ensure_line_score_inning()
	_phase = PHASE_PITCH
	_emit("half_started", {"inning": _inning, "half": _half})


func _force_walk() -> void:
	var old := _bases.duplicate()
	if old[0] and old[1] and old[2]:
		_score_runs(1)
	_bases[0] = true
	_bases[1] = old[0] or old[1]
	_bases[2] = (old[0] and old[1]) or old[2]


func _advance_hit(bases_gained: int, runner_bonus_bases: int) -> void:
	var old := _bases.duplicate()
	var next: Array[bool] = [false, false, false]
	for index in range(2, -1, -1):
		if not old[index]:
			continue
		var destination := index + 1 + bases_gained + maxi(0, runner_bonus_bases)
		if destination >= 4:
			_score_runs(1)
		else:
			next[destination - 1] = true
	if bases_gained >= 4:
		_score_runs(1)
	else:
		next[bases_gained - 1] = true
	_bases = next


func _advance_existing_runners(bases_gained: int) -> void:
	var old := _bases.duplicate()
	var next: Array[bool] = [false, false, false]
	for index in range(2, -1, -1):
		if not old[index]:
			continue
		var destination := index + 1 + bases_gained
		if destination >= 4:
			_score_runs(1)
		else:
			next[destination - 1] = true
	_bases = next


func _score_runs(amount: int) -> void:
	if amount <= 0:
		return
	var side := batting_side()
	_score[side] = int(_score[side]) + amount
	_ensure_line_score_inning()
	var line: Array = _line_score[side]
	line[_inning - 1] = int(line[_inning - 1]) + amount
	if side == SIDE_HOME and _inning >= _innings and int(_score[SIDE_HOME]) > int(_score[SIDE_AWAY]):
		if not _pending_game_over:
			_emit("walk_off", {"inning": _inning, "score": _score.duplicate(true)})
		_pending_game_over = true
		_winner = SIDE_HOME


func _finish_at_bat() -> void:
	var side := batting_side()
	_batters_faced[side] = int(_batters_faced[side]) + 1
	_batter_index[side] = (int(_batter_index[side]) + 1) % 9
	_balls = 0
	_strikes = 0
	_pitch_number = 1
	if _replica_enabled and bool(_stamina_config.get("enabled", true)):
		var owner := "user" if _half == "top" else "cpu"
		var condition := _active_condition(owner)
		if not condition.is_empty():
			PitcherConditionScript.clear_short_history(condition)
			var appearance: Dictionary = condition.get("appearance", {})
			appearance["at_bats_faced"] = int(appearance.get("at_bats_faced", 0)) + 1
			condition["appearance"] = appearance
		_handle_manager_boundary(owner)


func _handle_manager_boundary(owner: String) -> void:
	var bullpen := _home_bullpen if owner == "user" else _away_bullpen
	var roster: Array[Dictionary] = _home_staff if owner == "user" else _away_staff
	if roster.size() <= 1:
		return
	# Bullpen.cpp credits the just-completed batter to a warming reliever before
	# checking readiness. This order is a pinned gameplay contract.
	BullpenScript.advance_warmup(bullpen)
	var condition := _active_condition(owner)
	var decision := BullpenScript.decide_manager(bullpen, condition, roster.size(), _stamina_config)
	if decision == "warm":
		var index := int(bullpen.get("active_index", 0)) + 1
		if index >= roster.size():
			return
		BullpenScript.start_warming(bullpen, index)
		var event := {
			"type": "warm",
			"team": SIDE_HOME if owner == "user" else SIDE_AWAY,
			"pitcher_id": int(roster[index].get("id", -1)),
			"pitcher_name": String(roster[index].get("name", "")),
			"inning": _inning,
		}
		_record_manager_event(event)
		var event_payload := event.duplicate(true)
		event_payload.erase("type")
		_emit("manager_warm", event_payload)
		return
	if decision != "substitute":
		return
	var target := BullpenScript.substitution_target(bullpen, roster.size())
	if target < 0:
		return
	var old_index := int(bullpen.get("active_index", 0))
	bullpen["active_index"] = target
	bullpen["warming"] = {}
	var new_pitcher: Dictionary = roster[target]
	var old_pitcher: Dictionary = roster[old_index]
	var new_condition: Dictionary = _pitcher_conditions.get(int(new_pitcher.get("id", -1)), {})
	if not new_condition.is_empty():
		var appearance: Dictionary = new_condition.get("appearance", {})
		appearance["entered_inning"] = _inning
		new_condition["appearance"] = appearance
	if owner == "user":
		_user_pitcher = new_pitcher.duplicate(true)
		_user_arsenal = _index_arsenal(_user_pitcher)
	else:
		_cpu_pitcher = new_pitcher.duplicate(true)
		_cpu_arsenal = _index_arsenal(_cpu_pitcher)
	_previous_by_owner[owner] = {}
	var event := {
		"type": "substitute",
		"team": SIDE_HOME if owner == "user" else SIDE_AWAY,
		"pitcher_id": int(new_pitcher.get("id", -1)),
		"pitcher_name": String(new_pitcher.get("name", "")),
		"for_id": int(old_pitcher.get("id", -1)),
		"for_name": String(old_pitcher.get("name", "")),
		"inning": _inning,
	}
	_record_manager_event(event)
	var event_payload := event.duplicate(true)
	event_payload.erase("type")
	_emit("manager_substitute", event_payload)


func _record_manager_event(event: Dictionary) -> void:
	_manager_events.append(event.duplicate(true))
	if _manager_events.size() > EVENT_LIMIT:
		_manager_events.pop_front()


func _active_condition(owner: String) -> Dictionary:
	var pitcher := _user_pitcher if owner == "user" else _cpu_pitcher
	return _pitcher_conditions.get(int(pitcher.get("id", -1)), {})


func _build_pitcher_conditions() -> void:
	_pitcher_conditions.clear()
	for roster in [_home_staff, _away_staff]:
		for pitcher_value in roster:
			var pitcher: Dictionary = pitcher_value
			var id := int(pitcher.get("id", -1))
			if id < 0 or _pitcher_conditions.has(id):
				continue
			_pitcher_conditions[id] = PitcherConditionScript.fresh_condition(pitcher, _stamina_config)
	_home_bullpen = BullpenScript.fresh_state()
	_away_bullpen = BullpenScript.fresh_state()
	_manager_events.clear()


func _reset_conditions_and_bullpens() -> void:
	for condition_value in _pitcher_conditions.values():
		PitcherConditionScript.reset_for_new_game(condition_value as Dictionary, _stamina_config)
	_home_bullpen = BullpenScript.fresh_state()
	_away_bullpen = BullpenScript.fresh_state()
	_manager_events.clear()
	if not _home_staff.is_empty():
		_user_pitcher = _home_staff[0].duplicate(true)
		_user_arsenal = _index_arsenal(_user_pitcher)
	if not _away_staff.is_empty():
		_cpu_pitcher = _away_staff[0].duplicate(true)
		_cpu_arsenal = _index_arsenal(_cpu_pitcher)


func _staff_snapshot(staff: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for pitcher in staff:
		var id := int(pitcher.get("id", -1))
		result.append({
			"id": id,
			"name": String(pitcher.get("name", "")),
			"throws": String(pitcher.get("throws", "R")),
			"card": (PitcherDisplayScript.card_for(_pitcher_cards, id) as Dictionary),
		})
	return result


func _active_pitcher_snapshot(owner: String) -> Dictionary:
	var pitcher := _user_pitcher if owner == "user" else _cpu_pitcher
	var id := int(pitcher.get("id", -1))
	return {
		"id": id,
		"name": String(pitcher.get("name", "")),
		"throws": String(pitcher.get("throws", "R")),
		"card": PitcherDisplayScript.card_for(_pitcher_cards, id),
	}


func _condition_snapshot(owner: String) -> Dictionary:
	var condition := _active_condition(owner)
	return PitcherConditionScript.describe(condition, _stamina_config, 5) if not condition.is_empty() else {}


func _all_conditions_snapshot() -> Dictionary:
	var result := {}
	for id_value in _pitcher_conditions.keys():
		result[str(id_value)] = PitcherConditionScript.describe(_pitcher_conditions[id_value], _stamina_config, 5)
	return result


func _catalog_array(catalog: Variant, property: String) -> Array:
	if catalog is Dictionary:
		var dictionary: Dictionary = catalog
		var value: Variant = dictionary.get(property, [])
		return value if value is Array else []
	if catalog is Object:
		var value: Variant = catalog.get(property)
		return value if value is Array else []
	return []


func _batter_profile(side: String, index: int) -> Dictionary:
	var lineup: Array = _lineups.get(side, [])
	if lineup.is_empty():
		return {"archetype_encoded": index % 5, "stand": "L" if index % 3 == 1 else "R"}
	return (lineup[index % lineup.size()] as Dictionary).duplicate(true)


func _rebuild_versus_lineups() -> void:
	if _mode != "versus" or _batter_archetypes.is_empty():
		return
	# ERngDomain::LineupAway / LineupHome are ordinals 1 and 2. Since
	# _build_lineup reads _stream_epoch(), rematches produce a fresh but fully
	# replayable lineup without changing the visible seed or team configuration.
	_lineups[SIDE_AWAY] = _build_lineup(_batter_archetypes, _away_bat_quality, 1)
	_lineups[SIDE_HOME] = _build_lineup(_batter_archetypes, _home_bat_quality, 2)


func _build_lineup(archetypes: Array, quality: float, domain: int, event_id: int = 0) -> Array[Dictionary]:
	if archetypes.is_empty():
		return []
	# Bounded BAT influence follows Lineup.cpp: exp(1.2*q*quality_score),
	# where quality_score combines contact and launch-speed population z-scores.
	var scores := _lineup_quality_scores(archetypes)
	var weights := PackedFloat64Array()
	for index in archetypes.size():
		var archetype: Dictionary = archetypes[index]
		weights.append(float(archetype.get("nBatters", 1.0)) * exp(1.2 * quality * scores[index]))
	var rng = PixRngScript.new(PixRngScript.stream_seed(_seed, _stream_epoch(), domain, event_id))
	var lineup: Array[Dictionary] = []
	for slot in 9:
		var archetype: Dictionary = archetypes[rng.categorical(weights)]
		rng.next() # original name-index draw (identity is presentation-owned here)
		var stand := "L" if rng.next() < 0.4 else "R"
		var speed := clampf(24.0 + rng.next() * 5.0 + quality * 1.5, 23.0, 30.0)
		lineup.append({
			"slot": slot,
			"archetype_encoded": int(archetype.get("encoded", 0)),
			"archetype": String(archetype.get("archetype", "Balanced Hitter")),
			"stand": stand,
			"speed": speed,
		})
	return lineup


func _lineup_quality_scores(archetypes: Array) -> Array[float]:
	var contact: Array[float] = []
	var power: Array[float] = []
	for archetype_value in archetypes:
		var archetype: Dictionary = archetype_value
		contact.append(float(archetype.get("contactRate", 0.0)))
		power.append(float(archetype.get("avgLaunchSpeed", 0.0)))
	var contact_z := _z_scores(contact)
	var power_z := _z_scores(power)
	var combined: Array[float] = []
	var maximum := 0.0
	for index in archetypes.size():
		var value := contact_z[index] + power_z[index]
		combined.append(value)
		maximum = maxf(maximum, absf(value))
	if maximum == 0.0:
		maximum = 1.0
	for index in combined.size():
		combined[index] /= maximum
	return combined


func _z_scores(values: Array[float]) -> Array[float]:
	var mean := 0.0
	for value in values:
		mean += value
	mean /= values.size()
	var variance := 0.0
	for value in values:
		variance += (value - mean) * (value - mean)
	var deviation := sqrt(variance / values.size())
	if deviation == 0.0:
		deviation = 1.0
	var result: Array[float] = []
	for value in values:
		result.append((value - mean) / deviation)
	return result


# -- Structured state ------------------------------------------------------

func snapshot() -> Dictionary:
	return {
		"mode": _mode,
		"epoch": _stream_epoch(),
		"seed": _seed,
		"rng_state": _rng_state,
		"innings": _innings,
		"difficulty": _difficulty,
		"inning": _inning,
		"half": _half,
		"batting_side": batting_side(),
		"fielding_side": fielding_side(),
		"user_role": "pitching" if is_user_pitching() else ("batting" if is_user_batting() else "spectating"),
		"phase": _phase,
		"count": {"balls": _balls, "strikes": _strikes},
		"outs": _outs,
		"bases": _base_snapshot(),
		"score": _score.duplicate(true),
		"hits": _hits.duplicate(true),
		"line_score": _line_score.duplicate(true),
		"batter_index": _batter_index.duplicate(true),
		"batters_faced": _batters_faced.duplicate(true),
		"pitch_number": _pitch_number,
		"pitch_serial": _pitch_serial,
		"active_pitch": _active_pitch_snapshot(),
		"active_play": _active_play_snapshot(),
		"last_result": _last_result.duplicate(true),
		"pitch_report": _last_pitch_report.duplicate(true),
		"replica_model": _replica_enabled,
		"user_pitcher": String(_user_pitcher.get("name", "")),
		"cpu_pitcher": String(_cpu_pitcher.get("name", "")),
		"teams": {
			"home": _home_team.duplicate(true),
			"away": _away_team.duplicate(true),
			"home_bat_quality": _home_bat_quality,
			"away_bat_quality": _away_bat_quality,
		},
		"lineups": {
			"home": (_lineups.get(SIDE_HOME, []) as Array).duplicate(true),
			"away": (_lineups.get(SIDE_AWAY, []) as Array).duplicate(true),
		},
		"staffs": {
			"home": _staff_snapshot(_home_staff),
			"away": _staff_snapshot(_away_staff),
		},
		"bullpens": {
			"home": _home_bullpen.duplicate(true),
			"away": _away_bullpen.duplicate(true),
		},
		"active_pitchers": {
			"home": _active_pitcher_snapshot("user"),
			"away": _active_pitcher_snapshot("cpu"),
		},
		"pitcher_conditions": {
			"home": _condition_snapshot("user"),
			"away": _condition_snapshot("cpu"),
			"by_id": _all_conditions_snapshot(),
		},
		"manager_events": _manager_events.duplicate(true),
		"pending_half_end": _pending_half_end,
		"pending_game_over": _pending_game_over,
		"game_over": _game_over,
		"winner": _winner,
		"legal_actions": legal_actions(),
		"recent_events": _recent_events.duplicate(true),
	}


func legal_actions() -> Array[String]:
	if _game_over:
		return ["reset"]
	match _phase:
		PHASE_PITCH:
			return ["create_user_pitch"] if is_user_pitching() else ["create_cpu_pitch"]
		PHASE_LIVE_PLAY:
			return ["commit_live_play"]
		PHASE_RESULT:
			return ["advance_after_result"]
	return []


func recent_events() -> Array[Dictionary]:
	return _recent_events.duplicate(true)


func _stream_epoch() -> int:
	return _epoch


# -- Deterministic helpers -------------------------------------------------

func _rand_u32() -> int:
	var value := _rng_state & 0xffffffff
	value ^= (value << 13) & 0xffffffff
	value ^= value >> 17
	value ^= (value << 5) & 0xffffffff
	_rng_state = value & 0xffffffff
	return _rng_state


func _randf() -> float:
	return float(_rand_u32()) / 4294967296.0


func _randi_range(low: int, high: int) -> int:
	if high <= low:
		return low
	return low + int(floor(_randf() * float(high - low + 1)))


func _gaussian() -> float:
	var u1 := maxf(_randf(), 0.0000001)
	var u2 := _randf()
	return sqrt(-2.0 * log(u1)) * cos(TAU * u2)


func _weighted_index(weights: Array[float]) -> int:
	var total := 0.0
	for weight in weights:
		total += maxf(0.0, weight)
	if total <= 0.0:
		return 0
	var draw := _randf() * total
	for index in weights.size():
		draw -= maxf(0.0, weights[index])
		if draw <= 0.0:
			return index
	return weights.size() - 1


func _make_batted_ball(exit_velocity: float, launch_angle: float, spray_angle: float, quality: float) -> Dictionary:
	var speed := exit_velocity * MPH_TO_FPS
	var launch_rad := deg_to_rad(launch_angle)
	var spray_rad := deg_to_rad(spray_angle)
	var horizontal_speed := maxf(0.0, speed * cos(launch_rad))
	var vertical_speed := speed * sin(launch_rad)
	var discriminant := maxf(0.0, vertical_speed * vertical_speed + 2.0 * GRAVITY_FPS2 * 3.0)
	var hang_time := maxf(0.15, (vertical_speed + sqrt(discriminant)) / GRAVITY_FPS2)
	# A compact arcade drag/lift approximation. The output is a trajectory
	# contract for presentation/live-play systems, not a pre-booked outcome.
	var carry_factor := clampf(0.68 + launch_angle * 0.006 + quality * 0.12, 0.54, 1.02)
	var carry := maxf(4.0, horizontal_speed * hang_time * carry_factor)
	var apex := 3.0
	if vertical_speed > 0.0:
		apex += vertical_speed * vertical_speed / (2.0 * GRAVITY_FPS2)
	var landing_x := sin(spray_rad) * carry
	var landing_y := cos(spray_rad) * carry
	var fence_distance := 326.0 + 42.0 * (1.0 - absf(spray_angle) / 44.0)
	var hint := "ground_ball"
	if launch_angle >= 45.0:
		hint = "popup"
	elif launch_angle >= 18.0:
		hint = "home_run" if carry >= fence_distance else "fly_ball"
	elif launch_angle >= 7.0:
		hint = "line_drive"
	return {
		"exit_velocity_mph": exit_velocity,
		"launch_angle_deg": launch_angle,
		"spray_angle_deg": spray_angle,
		"hang_time_sec": hang_time,
		"carry_ft": carry,
		"apex_ft": apex,
		"landing_ft": [landing_x, landing_y, 0.0],
		"fence_distance_ft": fence_distance,
		"classification_hint": hint,
		"contact_quality": quality,
	}


func _emit(type: String, payload: Dictionary = {}) -> void:
	_event_serial += 1
	var event := {
		"seq": _event_serial,
		"type": type,
		"inning": _inning,
		"half": _half,
		"phase": _phase,
	}
	event.merge(payload, true)
	_recent_events.append(event)
	if _recent_events.size() > EVENT_LIMIT:
		_recent_events.pop_front()


func _validate_pitch_for_resolution(pitch: Dictionary, expected_owner: String) -> Dictionary:
	if _phase != PHASE_PITCH or _active_pitch.is_empty():
		return _error("wrong_phase", "No active pitch is available to resolve")
	if int(pitch.get("serial", -1)) != int(_active_pitch.serial):
		return _error("stale_pitch", "Pitch does not match the active pitch")
	if String(pitch.get("owner", "")) != expected_owner:
		return _error("wrong_pitch_owner", "Pitch owner does not match the batting side")
	return {}


func _base_snapshot() -> Dictionary:
	return {"first": _bases[0], "second": _bases[1], "third": _bases[2]}


func _active_pitch_snapshot() -> Dictionary:
	if _active_pitch.is_empty():
		return {}
	var result := _pitch_event_payload(_active_pitch)
	for key in ["code", "label", "flight_sec", "break_ft", "path", "effort"]:
		if _active_pitch.has(key):
			result[key] = _active_pitch[key]
	var model_result: Dictionary = _active_pitch.get("model_result", {})
	if not model_result.is_empty():
		result["model"] = {
			"probabilities": (model_result.get("probabilities", {}) as Dictionary).duplicate(true),
			"actual_x": float(model_result.get("actual_x", 0.0)),
			"actual_z": float(model_result.get("actual_z", 0.0)),
			"tunnel_x": float(model_result.get("tunnel_x", 0.0)),
			"tunnel_z": float(model_result.get("tunnel_z", 0.0)),
			"tunnel_diff_in": float(model_result.get("tunnel_diff_in", 0.0)),
			"break_diff_in": float(model_result.get("break_diff_in", 0.0)),
		}
	return result


func _active_play_snapshot() -> Dictionary:
	if _active_play.is_empty():
		return {}
	var result := {}
	for key in ["outcome", "actor", "pitch_serial", "pitch_kind", "swung", "quality", "contact_quality", "trajectory"]:
		if _active_play.has(key):
			result[key] = _active_play[key]
	return result


func _ensure_line_score_inning() -> void:
	for side in [SIDE_AWAY, SIDE_HOME]:
		var line: Array = _line_score[side]
		while line.size() < _inning:
			line.append(0)


func _pitch_actual(pitch: Dictionary) -> Vector2:
	return _read_point(pitch.get("actual", [0.0, 2.5]), Vector2(0.0, 2.5))


func _pitch_event_payload(pitch: Dictionary) -> Dictionary:
	return {
		"serial": int(pitch.serial),
		"owner": String(pitch.owner),
		"kind": String(pitch.kind),
		"target": pitch.target,
		"actual": pitch.actual,
		"velocity_mph": float(pitch.velocity_mph),
	}


func _read_point(value: Variant, fallback: Vector2) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary:
		return Vector2(float(value.get("x", fallback.x)), float(value.get("z", value.get("y", fallback.y))))
	return fallback


func _is_in_zone(x: float, z: float) -> bool:
	return absf(x) <= STRIKE_HALF_WIDTH_FT and z >= STRIKE_BOTTOM_FT and z <= STRIKE_TOP_FT


func _is_edge_pitch(x: float, z: float) -> bool:
	return (
		absf(absf(x) - STRIKE_HALF_WIDTH_FT) <= 0.14
		or absf(z - STRIKE_BOTTOM_FT) <= 0.14
		or absf(z - STRIKE_TOP_FT) <= 0.14
	)


func _swing_quality(metric: float, location_error: float, timing_error: float) -> String:
	if metric >= 1.0:
		return "miss"
	if absf(timing_error) < 0.025 and location_error < 0.45:
		return "perfect"
	if absf(timing_error) < 0.060 and location_error < 0.80:
		return "good"
	return "early" if timing_error < 0.0 else "late"


func _smoothstep(edge_a: float, edge_b: float, value: float) -> float:
	if is_equal_approx(edge_a, edge_b):
		return 0.0
	var t := clampf((value - edge_a) / (edge_b - edge_a), 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)


func _normalize_pitch_kind(value: String) -> String:
	var normalized := value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	match normalized:
		"fastball", "four_seam_fastball", "4_seam", "4seam", "ff":
			return "ff" if _replica_enabled else "four_seam"
		"si":
			return "si" if _replica_enabled else "sinker"
		"sl", "sweeper", "st":
			return "slider"
		"curve", "cu", "cb", "knuckle_curve", "kc":
			if _replica_enabled and _user_arsenal.has("kc"):
				return "kc"
			if _replica_enabled and _user_arsenal.has("cu"):
				return "cu"
			return "curveball"
		"change", "ch":
			return "ch" if _replica_enabled else "changeup"
		"cutter", "fc":
			return "fc"
		"sinker":
			return "si" if _replica_enabled else "sinker"
		"slider":
			if _replica_enabled and _user_arsenal.has("sl"):
				return "sl"
			if _replica_enabled and _user_arsenal.has("st"):
				return "st"
			return "slider"
		"changeup":
			return "ch" if _replica_enabled else "changeup"
	return normalized


func _normalize_effort(value: String) -> String:
	var normalized := value.strip_edges().to_lower()
	return normalized if normalized in ["cruise", "normal", "high"] else ""


func _normalize_play_classification(value: String) -> String:
	var normalized := value.strip_edges().to_lower().replace("-", "_").replace(" ", "_")
	match normalized:
		"1b": return "single"
		"2b": return "double"
		"3b": return "triple"
		"hr", "homerun": return "home_run"
		"fly", "flyout", "pop_out", "popup_out": return "fly_out"
		"ground", "groundout": return "ground_out"
		"fc", "fielderschoice", "fielder_choice": return "fielders_choice"
	return normalized


func _error(code: String, message: String) -> Dictionary:
	return {"ok": false, "error": code, "message": message}
