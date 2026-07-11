extends SceneTree

const ConfigScript = preload("../stamina_config.gd")
const ConditionScript = preload("../pitcher_condition.gd")
const SimScript = preload("../pixiball_sim.gd")
const CatalogScript = preload("../../core/content/content_catalog.gd")
const PitchModelScript = preload("../../core/model/pitch_model.gd")


func _init() -> void:
	var passed := _run()
	quit(0 if passed else 1)


func _run() -> bool:
	var config := ConfigScript.defaults()
	assert(ConfigScript.validate(config))
	assert(float(config.base_max_stamina) == 240.0)
	assert(float(config.pitch_type_cost_mul.FF) == 1.15)
	assert(int(config.short_window_len) == 6)

	var condition := ConditionScript.fresh_condition({"stamina_rating": 1.25, "stamina_cost_mul": 0.8}, config)
	assert(float(condition.max_stamina) == 300.0)
	assert(float(condition.stamina) == 300.0)
	assert(float(condition.cost_mul) == 0.8)
	var fresh := ConditionScript.fatigue_factors(condition, config)
	_assert_close(float(fresh.velocity_mul), 1.0)
	_assert_close(float(fresh.movement_mul), 1.0)
	_assert_close(float(fresh.command_std_add), 0.0)
	assert(String(fresh.tier) == "fresh")

	condition.stamina = 0.0
	var empty := ConditionScript.fatigue_factors(condition, config)
	_assert_close(float(empty.velocity_mul), 0.92)
	_assert_close(float(empty.movement_mul), 0.80)
	_assert_close(float(empty.command_std_add), 0.35)
	assert(String(empty.tier) == "gassed")
	condition.stamina = float(condition.max_stamina) * 0.65
	assert(String(ConditionScript.fatigue_factors(condition, config).tier) == "tiring")
	condition.stamina = float(condition.max_stamina) * 0.40
	assert(String(ConditionScript.fatigue_factors(condition, config).tier) == "tired")
	condition.stamina = float(condition.max_stamina) * 0.20
	assert(String(ConditionScript.fatigue_factors(condition, config).tier) == "gassed")

	assert(ConditionScript.bucket_location(-100.0, 100.0) == 0)
	assert(ConditionScript.bucket_location(0.0, 2.5) == 4)
	assert(ConditionScript.bucket_location(100.0, -100.0) == 8)

	condition = ConditionScript.fresh_condition({}, config)
	var expected_cost := 1.15 * 1.35 * 1.12 * 1.08 * 1.08
	var cost := ConditionScript.deplete_stamina(condition, "FF", "high", {
		"runners_in_scoring_position": true,
		"two_strike": true,
		"three_ball": true,
	}, config)
	_assert_close(cost, expected_cost)
	_assert_close(float(condition.stamina), 240.0 - expected_cost)
	assert(int(condition.pitches_thrown) == 1)

	# Ring order, immediate repetition, and long-window entropy are independent.
	ConditionScript.clear_short_history(condition)
	for index in 7:
		ConditionScript.record_pitch(condition, index % 2, 4 if index % 2 == 0 else 3, config)
	assert(int(condition.short_len) == 6)
	assert(int(condition.short_head) == 1)
	var repeat := ConditionScript.repetitiveness_score(condition, 0, 4, config)
	_assert_close(repeat, 0.6) # 3/6 slot + 3/6 bucket + immediate exact repeat.
	var entropy := ConditionScript.pitch_mix_entropy(condition, 2)
	assert(entropy > 0.98 and entropy <= 1.0)
	var mono := ConditionScript.fresh_condition({}, config)
	ConditionScript.record_pitch(mono, 0, 0, config)
	ConditionScript.record_pitch(mono, 0, 1, config)
	_assert_close(ConditionScript.pitch_mix_entropy(mono, 5), 0.0)

	var degraded := ConditionScript.degrade_shape({
		"velocity": 100.0,
		"effectiveSpeed": 101.0,
		"pfxX": 1.5,
		"pfxZ": -1.0,
	}, -1.0, empty, config)
	_assert_close(float(degraded.velocity), 91.08)
	_assert_close(float(degraded.effectiveSpeed), 92.0)
	_assert_close(float(degraded.pfxX), 1.2)
	_assert_close(float(degraded.pfxZ), -0.8)

	var recognition := ConditionScript.apply_recognition({
		"sampled_launch_speed": 90.0,
		"sampled_launch_angle": 15.0,
		"probabilities": {"swinging_strike": 0.25, "foul": 0.15, "in_play": 0.20},
	}, 1.0, config)
	# 12% of swinging-strike mass moves 60/40 to foul/in-play.
	_assert_close(float(recognition.probabilities.swinging_strike), 0.22)
	_assert_close(float(recognition.probabilities.foul), 0.168)
	_assert_close(float(recognition.probabilities.in_play), 0.212)

	# Full stamina + normal effort must preserve the exact first replica pitch.
	var catalog = CatalogScript.new()
	assert(catalog.load_all())
	var model = PitchModelScript.new()
	assert(model.load_from_directory())
	var enabled = SimScript.new(6060, 3, 0.5)
	var disabled = SimScript.new(6060, 3, 0.5)
	assert(enabled.configure_replica(catalog.pitcher_at(0), catalog.pitcher_at(1), model).ok)
	var disabled_config := ConfigScript.defaults()
	disabled_config.enabled = false
	assert(disabled.set_stamina_config(disabled_config).ok)
	assert(disabled.configure_replica(catalog.pitcher_at(0), catalog.pitcher_at(1), model).ok)
	var enabled_first: Dictionary = enabled.create_user_pitch("kc", Vector2(-0.5, 1.7))
	var disabled_first: Dictionary = disabled.create_user_pitch("kc", Vector2(-0.5, 1.7))
	assert(enabled_first.actual == disabled_first.actual)
	assert(enabled_first.shape == disabled_first.shape)
	assert(enabled_first.model_result == disabled_first.model_result)
	assert(enabled_first.model_context.arsenal == enabled_first.model_context.catalog_arsenal)
	assert(float(enabled.snapshot().pitcher_conditions.home.stamina) < float(enabled.snapshot().pitcher_conditions.home.max_stamina))

	# Tired/gassed report recommendations must use the same pre-pitch fatigue
	# and high-effort transform as the selected pitch. This seed/spot is a rank
	# regression: degraded Nola KC ranks fourth; the old fresh-option bug ranked
	# it third and recommended a materially different ordering.
	var tired = SimScript.new(1, 3, 0.5)
	var tired_pitcher: Dictionary = catalog.pitcher_at(0)
	assert(tired.configure_replica(tired_pitcher, catalog.pitcher_at(1), model).ok)
	var tired_condition: Dictionary = tired._active_condition("user")
	tired_condition.stamina = float(tired_condition.max_stamina) * 0.05
	var pre_pitch_fatigue: Dictionary = ConditionScript.fatigue_factors(tired_condition, config)
	assert(String(pre_pitch_fatigue.tier) == "gassed")
	var tired_pitch: Dictionary = tired.create_user_pitch("kc", Vector2(0.8, 1.7), "high")
	var report_context: Dictionary = tired_pitch.model_context
	var degraded_arsenal: Array = report_context.arsenal
	var catalog_arsenal: Array = report_context.catalog_arsenal
	assert(degraded_arsenal.size() == 5 and catalog_arsenal.size() == 5)
	for slot in 5:
		var expected_shape := ConditionScript.degrade_shape(catalog_arsenal[slot], 1.5, pre_pitch_fatigue, config)
		var option_shape: Dictionary = degraded_arsenal[slot]
		_assert_close(float(option_shape.velocity), float(expected_shape.velocity))
		_assert_close(float(option_shape.effectiveSpeed), float(expected_shape.effectiveSpeed))
		_assert_close(float(option_shape.pfxX), float(expected_shape.pfxX))
		_assert_close(float(option_shape.pfxZ), float(expected_shape.pfxZ))
		# Identity/control metadata remains intact; build_report zeroes control on
		# its per-option copy after receiving these degraded shapes.
		assert(String(option_shape.code) == String((catalog_arsenal[slot] as Dictionary).code))
		_assert_close(float(option_shape.controlXStd), float((catalog_arsenal[slot] as Dictionary).controlXStd))
	tired.commit_plate_result({"outcome": "called_strike", "pitch_serial": tired_pitch.serial})
	var tired_report: Dictionary = tired.last_pitch_report()
	assert(int(tired_report.rank) == 4)
	assert(_option_slots(tired_report.options) == [3, 4, 2, 0, 1])
	var fresh_context := report_context.duplicate(true)
	fresh_context.arsenal = catalog_arsenal.duplicate(true)
	var thrown := tired_pitch.duplicate(true)
	thrown.outcome = "called_strike"
	thrown.ended_at_bat = ""
	var stale_fresh_report: Dictionary = model.build_report(fresh_context, thrown)
	assert(int(stale_fresh_report.rank) == 3)
	assert(_option_slots(stale_fresh_report.options) == [3, 4, 0, 2, 1])
	assert(tired_report.options != stale_fresh_report.options)

	# Model at-bat features use delivered pitches, not the visible count. Two
	# strikes followed by repeated fouls must produce pitch numbers 3, 4, 5.
	var feature_sim = SimScript.new(31337, 3, 0.5)
	assert(feature_sim.configure_replica(catalog.pitcher_at(0), catalog.pitcher_at(1), model).ok)
	var feature_outcomes := ["called_strike", "called_strike", "foul", "foul"]
	for index in feature_outcomes.size():
		var feature_pitch: Dictionary = feature_sim.create_user_pitch("kc", Vector2(0.0, 2.5))
		assert(int(feature_pitch.model_context.ab.pitch_number) == index + 1)
		feature_sim.commit_plate_result({"outcome": feature_outcomes[index], "pitch_serial": feature_pitch.serial})
		feature_sim.advance_after_result()
	var fifth_pitch: Dictionary = feature_sim.create_user_pitch("kc", Vector2(0.0, 2.5))
	assert(int(fifth_pitch.model_context.ab.pitch_number) == 5)
	assert(int(feature_sim.snapshot().pitch_number) == 5)

	# Times-through-order is side-local durable batter progression. Completing
	# nine away batters wraps the lineup index but advances TTO to two.
	var order_sim = SimScript.new(2718, 3, 0.5)
	assert(order_sim.configure_replica(catalog.pitcher_at(0), catalog.pitcher_at(1), model).ok)
	for unused in 9:
		order_sim._finish_at_bat()
	var order_state: Dictionary = order_sim.snapshot()
	assert(int(order_state.batter_index.away) == 0)
	assert(int(order_state.batters_faced.away) == 9 and int(order_state.batters_faced.home) == 0)
	var second_time_pitch: Dictionary = order_sim.create_user_pitch("kc", Vector2(0.0, 2.5))
	assert(int(second_time_pitch.model_context.ab.times_through_order) == 2)

	print("PIXIBALL_CONDITION_OK cost=%.6f entropy=%.6f first_pitch_preserved=true fatigued_report_rank=4 pitch_number=5 tto=2" % [cost, entropy])
	return true


func _assert_close(actual: float, expected: float, tolerance := 0.000001) -> void:
	assert(absf(actual - expected) <= tolerance, "expected %.9f, got %.9f" % [expected, actual])


func _option_slots(options: Array) -> Array:
	var result := []
	for option_value in options:
		result.append(int((option_value as Dictionary).slot))
	return result
