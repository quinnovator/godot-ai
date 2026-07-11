class_name PixiballEndlessSim
extends PixiballSim

## Endless Pitch challenge ported from:
##   ../pixiball-ue/Source/PixCore/Sim/EndlessSim.{h,cpp}
##
## The user never changes sides: every pitch is user-thrown and every live ball
## is user-fielded. Three outs clear the bases instead of flipping a half, and
## the run is final as soon as the third allowed run is booked.

const RUNS_LIMIT := 3
const AT_BAT_RECOVERY := 3.0
const ENDLESS_DIFFICULTY := 0.6

var _endless_strikeouts := 0
var _endless_batters_faced := 0
var _endless_epoch := 0
var _endless_archetypes: Array = []


func _init(seed_value: int = 1, pitcher_or_innings: Variant = 99, model_or_difficulty: Variant = ENDLESS_DIFFICULTY) -> void:
	var innings_value := 99
	var difficulty_value := ENDLESS_DIFFICULTY
	var pitcher: Dictionary = {}
	var model: Variant = null
	if pitcher_or_innings is Dictionary:
		pitcher = pitcher_or_innings
		model = model_or_difficulty
	else:
		innings_value = int(pitcher_or_innings)
		difficulty_value = float(model_or_difficulty)
	super(seed_value, innings_value, difficulty_value)
	_mode = "endless"
	_innings = 99
	_half = "top"
	if not pitcher.is_empty() and model != null:
		configure_endless(pitcher, model)


func reset(seed_value: int = 1, innings_value: int = 99, difficulty_value: float = ENDLESS_DIFFICULTY) -> Dictionary:
	_endless_epoch = 0
	_endless_strikeouts = 0
	_endless_batters_faced = 0
	var state := super(seed_value, 99, difficulty_value)
	_mode = "endless"
	_inning = 1
	_half = "top"
	if not _endless_archetypes.is_empty():
		_lineups[SIDE_AWAY] = _build_lineup(_endless_archetypes, 0.0, 3, 0)
	return snapshot()


func retry() -> Dictionary:
	# EndlessSim.cpp::Restart advances the keyed-stream epoch: retry keeps the
	# visible seed and pitcher but intentionally produces a fresh replay.
	_endless_epoch = (_endless_epoch + 1) & 0xffffffff
	_endless_strikeouts = 0
	_endless_batters_faced = 0
	super.reset(_seed, 99, _difficulty)
	_mode = "endless"
	_inning = 1
	_half = "top"
	if not _endless_archetypes.is_empty():
		_lineups[SIDE_AWAY] = _build_lineup(_endless_archetypes, 0.0, 3, 0)
	return snapshot()


func restart() -> Dictionary:
	return retry()


func _stream_epoch() -> int:
	return _endless_epoch


func configure_endless(pitcher: Dictionary, model: Variant, catalog: Variant = null) -> Dictionary:
	var profile := pitcher.duplicate(true)
	var pool: Array = _catalog_array(catalog, "pitchers") if catalog != null else [pitcher]
	_endless_archetypes = _catalog_array(catalog, "batter_archetypes") if catalog != null else []
	var cards := PitcherDisplayScript.build_cache(pool)
	var card: Dictionary = cards.get(int(pitcher.get("id", -1)), {})
	if not card.is_empty():
		# EndlessSim.cpp is the one original mode that turns card stamina into a
		# live max-tank multiplier: display 0.35..0.90 -> 0.85..1.25x.
		profile["stamina_rating"] = 0.6 + 0.72 * float(card.get("stamina", 0.625))
	_home_staff = [profile.duplicate(true)]
	_away_staff = []
	_pitcher_cards = cards
	var configured := _configure_active_pitchers(profile, profile, model, true)
	if not bool(configured.get("ok", false)):
		return configured
	_mode = "endless"
	if not _endless_archetypes.is_empty():
		_lineups[SIDE_AWAY] = _build_lineup(_endless_archetypes, 0.0, 3, 0)
	return {
		"ok": true,
		"mode": _mode,
		"user_pitcher": String(profile.get("name", "")),
		"pitch_slots": (profile.get("pitches", []) as Array).size(),
		"stamina_rating": float(profile.get("stamina_rating", 1.0)),
	}


func configure_replica(user_pitcher: Dictionary, _cpu_pitcher_value: Dictionary, model: Variant) -> Dictionary:
	return configure_endless(user_pitcher, model)


func is_user_batting() -> bool:
	return false


func is_user_running() -> bool:
	return false


func commit_plate_result(result: Dictionary) -> Dictionary:
	var previous_phase := _phase
	var state := super(result)
	if not bool(state.get("ok", true)) or previous_phase != PHASE_PITCH:
		return state
	if not _last_result.is_empty() and String(_last_result.get("outcome", "")) == "strikeout":
		_endless_strikeouts += 1
	_finalize_if_limit_reached()
	return snapshot()


func commit_live_play(result: Dictionary) -> Dictionary:
	var state := super(result)
	if not bool(state.get("ok", true)):
		return state
	_finalize_if_limit_reached()
	return snapshot()


func advance_after_result() -> Dictionary:
	if _game_over:
		return snapshot()
	return super()


func _score_runs(amount: int) -> void:
	var remaining := maxi(0, RUNS_LIMIT - int(_score[SIDE_AWAY]))
	if remaining <= 0:
		return
	super(mini(amount, remaining))


func _finish_at_bat() -> void:
	super()
	_endless_batters_faced += 1
	if not _endless_archetypes.is_empty() and _endless_batters_faced % 9 == 0:
		# ERngDomain::LineupEndless is ordinal 3; the completed batter count
		# (9, 18, 27...) is the event key, exactly as EndlessSim.cpp.
		_lineups[SIDE_AWAY] = _build_lineup(_endless_archetypes, 0.0, 3, _endless_batters_faced)
	var condition := _active_condition("user")
	if bool(_stamina_config.get("enabled", true)) and not condition.is_empty():
		PitcherConditionScript.recover_between_at_bats(condition, AT_BAT_RECOVERY)


func _advance_half_inning() -> void:
	# EndlessSim.cpp::ResetSide: no inning increment and no side change.
	_pending_half_end = false
	_previous_by_owner = {"user": {}, "cpu": {}}
	_balls = 0
	_strikes = 0
	_outs = 0
	_pitch_number = 1
	_bases = [false, false, false]
	_half = "top"
	_phase = PHASE_PITCH
	_emit("endless_outs_cleared", {"batters_faced": _endless_batters_faced})


func _finalize_if_limit_reached() -> void:
	if int(_score[SIDE_AWAY]) < RUNS_LIMIT or _game_over:
		return
	_pending_half_end = false
	_pending_game_over = false
	_game_over = true
	_phase = PHASE_GAME_OVER
	_winner = ""
	_emit("endless_run_over", {"stats": _endless_stats()})


func snapshot() -> Dictionary:
	var state := super()
	state["mode"] = "endless"
	state["inning"] = 1
	state["half"] = "top"
	state["batting_side"] = SIDE_AWAY
	state["fielding_side"] = SIDE_HOME
	state["user_role"] = "spectating" if _game_over else ("fielding" if _phase == PHASE_LIVE_PLAY else "pitching")
	state["endless"] = _endless_stats()
	state["legal_actions"] = legal_actions()
	return state


func legal_actions() -> Array[String]:
	if _game_over:
		return ["retry", "reset"]
	return super()


func _endless_stats() -> Dictionary:
	return {
		"score": _endless_strikeouts,
		"strikeouts": _endless_strikeouts,
		"runs_allowed": int(_score[SIDE_AWAY]),
		"batters_faced": _endless_batters_faced,
		"pitch_count": _pitch_serial,
		"runs_limit": RUNS_LIMIT,
	}
