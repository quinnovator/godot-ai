extends SceneTree

const SimScript = preload("../pixiball_sim.gd")
const DisplayScript = preload("../pitcher_display.gd")
const TeamsScript = preload("../teams.gd")
const BullpenScript = preload("../bullpen.gd")
const ConditionScript = preload("../pitcher_condition.gd")
const ConfigScript = preload("../stamina_config.gd")
const CatalogScript = preload("../../core/content/content_catalog.gd")
const PitchModelScript = preload("../../core/model/pitch_model.gd")


func _init() -> void:
	var catalog = CatalogScript.new()
	assert(catalog.load_all())
	var model = PitchModelScript.new()
	assert(model.load_from_directory())
	var passed := _test_card_and_draft_contract(catalog)
	passed = _test_manager_threshold_contract() and passed
	passed = _test_versus_snapshot_replay_and_bat_quality(catalog, model) and passed
	passed = _test_manager_warm_and_substitution(catalog, model) and passed
	if passed:
		print("PIXIBALL_VERSUS_OK cards=10 staffs=5x5 manager=warm+sub")
	quit(0 if passed else 1)


func _test_card_and_draft_contract(catalog) -> bool:
	var cards := DisplayScript.build_cache(catalog.pitchers)
	# Field-for-field card pins copied from PixMathRoundTests.cpp. OVR controls
	# the staff draft, so these are gameplay golden values, not cosmetic tests.
	var pins := [
		[605400, 81, "2.40", "8.9", 93, 0.64682306118187172, "CONTROL"],
		[554430, 88, "3.00", "9.8", 95, 0.35, "CONTROL"],
		[666142, 89, "4.39", "11.1", 95, 0.71813749429662743, "CONTROL"],
		[607625, 71, "4.22", "7.5", 92, 0.69771549112484377, "CONTROL"],
		[669302, 92, "4.60", "11.5", 97, 0.9, "POWER"],
		[640455, 76, "4.27", "9.2", 92, 0.48972740030297079, "CONTROL"],
		[669203, 92, "3.18", "9.9", 97, 0.70720789592874855, "POWER"],
		[641154, 89, "2.83", "10.1", 95, 0.79996782059471516, "CONTROL"],
		[669923, 88, "3.07", "9.3", 96, 0.64234749489556342, "POWER"],
		[605135, 73, "3.64", "7.5", 93, 0.44833876041077619, "CONTROL"],
	]
	for pin in pins:
		var card: Dictionary = cards[int(pin[0])]
		assert(int(card.ovr) == int(pin[1]))
		assert(String(card.era) == String(pin[2]) and String(card.k9) == String(pin[3]))
		assert(int(card.velo) == int(pin[4]))
		assert(absf(float(card.stamina) - float(pin[5])) < 0.000000000000001)
		assert(String(card.archetype) == String(pin[6]))
	var drafted := TeamsScript.build_versus_rosters(catalog.pitchers, cards, catalog.team_by_id("comets"), catalog.team_by_id("tigers"))
	assert(bool(drafted.home_first))
	assert(_ids(drafted.home) == [669203, 641154, 554430, 605400, 605135])
	assert(_ids(drafted.away) == [669302, 666142, 669923, 640455, 607625])
	assert(absf(TeamsScript.bat_quality(catalog.team_by_id("pennants")) - 1.0) < 0.000001)
	assert(absf(TeamsScript.bat_quality(catalog.team_by_id("drifters")) + 5.0 / 9.0) < 0.000001)
	return true


func _test_manager_threshold_contract() -> bool:
	var config := ConfigScript.defaults()
	var bullpen := BullpenScript.fresh_state()
	var condition := ConditionScript.fresh_condition({}, config)
	assert(BullpenScript.decide_manager(bullpen, condition, 5, config) == "none")
	condition.pitches_thrown = int(config.pitch_count_warm_threshold)
	assert(BullpenScript.decide_manager(bullpen, condition, 5, config) == "warm")
	condition.pitches_thrown = 0
	condition.stamina = 0.0
	assert(BullpenScript.decide_manager(bullpen, condition, 5, config) == "substitute")
	assert(BullpenScript.decide_manager(bullpen, condition, 1, config) == "none")
	BullpenScript.start_warming(bullpen, 1)
	for unused in int(config.warmup_at_bats_required):
		BullpenScript.advance_warmup(bullpen)
	assert(BullpenScript.is_reliever_ready(bullpen, config))
	BullpenScript.start_warming(bullpen, 1)
	assert(BullpenScript.is_reliever_ready(bullpen, config))
	return true


func _test_versus_snapshot_replay_and_bat_quality(catalog, model) -> bool:
	var left = SimScript.new(444, 3, 0.5)
	var right = SimScript.new(444, 3, 0.5)
	var home: Dictionary = catalog.team_by_id("pennants")
	var away: Dictionary = catalog.team_by_id("drifters")
	assert(left.configure_versus(home, away, catalog, model).ok)
	assert(right.configure_versus(home, away, catalog, model).ok)
	var state: Dictionary = left.snapshot()
	assert(state.mode == "versus")
	assert(int((state.staffs.home as Array).size()) == 5 and int((state.staffs.away as Array).size()) == 5)
	assert(String(state.teams.home.id) == "pennants" and String(state.teams.away.id) == "drifters")
	assert(float(state.teams.home_bat_quality) == 1.0)
	assert(float(state.teams.away_bat_quality) < 0.0)
	assert((state.lineups.home as Array).size() == 9 and (state.lineups.away as Array).size() == 9)
	assert(_average_speed(state.lineups.home) > _average_speed(state.lineups.away))
	assert(state == right.snapshot())
	var left_pitch: Dictionary = left.create_user_pitch("ff", Vector2(0.1, 2.7))
	var right_pitch: Dictionary = right.create_user_pitch("ff", Vector2(0.1, 2.7))
	assert(left_pitch == right_pitch)
	assert(float(left.snapshot().pitcher_conditions.home.stamina) < float(left.snapshot().pitcher_conditions.home.max_stamina))
	var epoch_zero_lineups: Dictionary = state.lineups.duplicate(true)
	var restarted_left: Dictionary = left.restart()
	var restarted_right: Dictionary = right.restart()
	assert(int(restarted_left.epoch) == 1 and int(restarted_right.epoch) == 1)
	assert(int(restarted_left.seed) == 444 and int(restarted_left.innings) == 3)
	assert(restarted_left.teams == state.teams and restarted_left.staffs == state.staffs)
	assert(restarted_left.lineups == restarted_right.lineups)
	assert(restarted_left.lineups != epoch_zero_lineups)
	assert(String(restarted_left.pitcher_conditions.home.tier) == "fresh")
	var epoch_one_left: Dictionary = left.create_user_pitch("ff", Vector2(0.1, 2.7))
	var epoch_one_right: Dictionary = right.create_user_pitch("ff", Vector2(0.1, 2.7))
	assert(epoch_one_left == epoch_one_right)
	assert(epoch_one_left.model_result != left_pitch.model_result)
	return true


func _test_manager_warm_and_substitution(catalog, model) -> bool:
	var sim = SimScript.new(555, 3, 0.5)
	assert(sim.configure_versus(catalog.team_by_id("comets"), catalog.team_by_id("tigers"), catalog, model).ok)
	var starter_id := int(sim.snapshot().active_pitchers.home.id)
	var condition: Dictionary = sim._pitcher_conditions[starter_id]
	condition.stamina = float(condition.max_stamina) * 0.35
	# Internal boundary invocation avoids manufacturing nine unrelated pitches;
	# it still exercises the exact production warmup/decision/substitution path.
	sim._finish_at_bat()
	var warming: Dictionary = sim.snapshot().bullpens.home.warming
	assert(int(warming.index) == 1 and int(warming.readiness) == 0)
	assert(String(sim.snapshot().manager_events[0].type) == "warm")
	condition.stamina = float(condition.max_stamina) * 0.19
	for unused in 3:
		sim._finish_at_bat()
	var state: Dictionary = sim.snapshot()
	assert(int(state.bullpens.home.active_index) == 1)
	assert((state.bullpens.home.warming as Dictionary).is_empty())
	assert(int(state.active_pitchers.home.id) != starter_id)
	assert(String(state.manager_events[-1].type) == "substitute")
	assert(int(state.manager_events[-1].for_id) == starter_id)
	assert(_event_seen(state.recent_events, "manager_warm"))
	assert(_event_seen(state.recent_events, "manager_substitute"))
	var reset_state: Dictionary = sim.reset(555, 3, 0.5)
	assert(int(reset_state.bullpens.home.active_index) == 0)
	assert(int(reset_state.active_pitchers.home.id) == starter_id)
	assert((reset_state.manager_events as Array).is_empty())
	assert(String(reset_state.pitcher_conditions.home.tier) == "fresh")
	return true


func _ids(roster: Array) -> Array:
	var result := []
	for pitcher_value in roster:
		result.append(int((pitcher_value as Dictionary).get("id", -1)))
	return result


func _average_speed(lineup: Array) -> float:
	var total := 0.0
	for batter_value in lineup:
		total += float((batter_value as Dictionary).get("speed", 0.0))
	return total / lineup.size()


func _event_seen(events: Array, type: String) -> bool:
	for event_value in events:
		if String((event_value as Dictionary).get("type", "")) == type:
			return true
	return false
