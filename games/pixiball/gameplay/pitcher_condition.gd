class_name PixiballPitcherCondition
extends RefCounted

## Pure pitcher-condition math ported from:
##   ../pixiball-ue/Source/PixCore/Sim/PitcherCondition.{h,cpp}
##   ../pixiball-ue/Source/PixCore/Sim/AtBat.cpp::DegradeShape
## All functions mutate only caller-owned dictionaries and consume no global
## RNG. This makes condition transitions independently replayable and testable.

const PLATE_HALF_WIDTH_FT := 17.0 / 24.0
const ZONE_Z_MIN := 1.5
const ZONE_Z_MAX := 3.5
const BUCKET_AXIS_LEN := 3


static func fresh_condition(profile: Dictionary, config: Dictionary) -> Dictionary:
	var stamina_rating := float(profile.get("stamina_rating", 1.0))
	var cost_mul := float(profile.get("stamina_cost_mul", 1.0))
	var max_stamina := float(config.get("base_max_stamina", 240.0)) * stamina_rating
	var short_history: Array[Dictionary] = []
	for unused in int(config.get("short_window_len", 6)):
		short_history.append({"slot": -1, "loc_bucket": 0})
	var long_history: Array[int] = []
	for unused in int(config.get("long_window_slots", 24)):
		long_history.append(0)
	return {
		"stamina": max_stamina,
		"max_stamina": max_stamina,
		"cost_mul": cost_mul,
		"pitches_thrown": 0,
		"short_history": short_history,
		"short_len": 0,
		"short_head": 0,
		"long_history": long_history,
		"appearance": {"at_bats_faced": 0, "entered_inning": 1},
	}


static func fatigue_factors(condition: Dictionary, config: Dictionary) -> Dictionary:
	var maximum := float(condition.get("max_stamina", 1.0))
	var fraction := clampf(float(condition.get("stamina", 0.0)) / maximum, 0.0, 1.0) if maximum > 0.0 else 0.0
	var fatigue := 1.0 - fraction
	var degradation := 0.0 if fatigue <= 0.0 else (1.0 if fatigue >= 1.0 else pow(fatigue, float(config.get("fatigue_exponent", 1.4))))
	var thresholds: Dictionary = config.get("tier_thresholds", {})
	var tier := "gassed"
	# Boundaries are more-fatigued-inclusive, exactly as the original.
	if fraction > float(thresholds.get("tiring", 0.65)):
		tier = "fresh"
	elif fraction > float(thresholds.get("tired", 0.4)):
		tier = "tiring"
	elif fraction > float(thresholds.get("gassed", 0.2)):
		tier = "tired"
	return {
		"stamina_fraction": fraction,
		"fatigue": fatigue,
		"degradation": degradation,
		"velocity_mul": 1.0 - degradation * (1.0 - float(config.get("velocity_floor_mul", 0.92))),
		"movement_mul": 1.0 - degradation * (1.0 - float(config.get("movement_floor_mul", 0.8))),
		"command_std_add": degradation * float(config.get("command_std_max", 0.35)),
		"tier": tier,
	}


static func bucket_location(target_x: float, target_z: float) -> int:
	var col := _bucket_axis(target_x, -PLATE_HALF_WIDTH_FT, PLATE_HALF_WIDTH_FT)
	var row_from_bottom := _bucket_axis(target_z, ZONE_Z_MIN, ZONE_Z_MAX)
	var row_from_top := BUCKET_AXIS_LEN - 1 - row_from_bottom
	return row_from_top * BUCKET_AXIS_LEN + col


static func record_pitch(condition: Dictionary, slot: int, loc_bucket: int, config: Dictionary) -> void:
	var window := int(config.get("short_window_len", 6))
	var history: Array = condition.get("short_history", [])
	if history.size() != window:
		history.clear()
		for unused in window:
			history.append({"slot": -1, "loc_bucket": 0})
	var write_index := int(condition.get("short_head", 0)) % window
	history[write_index] = {"slot": slot, "loc_bucket": loc_bucket}
	condition["short_history"] = history
	condition["short_head"] = (write_index + 1) % window
	condition["short_len"] = mini(window, int(condition.get("short_len", 0)) + 1)
	var long_history: Array = condition.get("long_history", [])
	if slot >= 0 and slot < long_history.size():
		long_history[slot] = int(long_history[slot]) + 1
		condition["long_history"] = long_history


static func clear_short_history(condition: Dictionary) -> void:
	condition["short_len"] = 0
	condition["short_head"] = 0


static func repetitiveness_score(condition: Dictionary, next_slot: int, next_loc_bucket: int, config: Dictionary) -> float:
	var window := int(config.get("short_window_len", 6))
	var history: Array = condition.get("short_history", [])
	var length := mini(int(condition.get("short_len", 0)), window)
	if length <= 0 or history.size() < window:
		return 0.0
	var head := int(condition.get("short_head", 0))
	var oldest := posmod(head - length, window)
	var slot_matches := 0
	var bucket_matches := 0
	for offset in length:
		var entry: Dictionary = history[(oldest + offset) % window]
		if int(entry.get("slot", -1)) == next_slot:
			slot_matches += 1
		if int(entry.get("loc_bucket", 0)) == next_loc_bucket:
			bucket_matches += 1
	var last: Dictionary = history[posmod(head - 1, window)]
	var immediate := 1.0 if int(last.get("slot", -1)) == next_slot and int(last.get("loc_bucket", 0)) == next_loc_bucket else 0.0
	return clampf(0.5 * float(slot_matches) / length + 0.3 * float(bucket_matches) / length + 0.2 * immediate, 0.0, 1.0)


static func pitch_mix_entropy(condition: Dictionary, slot_count: int) -> float:
	var history: Array = condition.get("long_history", [])
	var tracked := maxi(0, mini(history.size(), slot_count))
	if tracked < 2:
		return 1.0
	var total := 0
	for index in tracked:
		total += int(history[index])
	if total < 2:
		return 1.0
	var entropy := 0.0
	for index in tracked:
		var count := int(history[index])
		if count > 0:
			var probability := float(count) / total
			entropy -= probability * log(probability) / log(2.0)
	return clampf(entropy / (log(float(tracked)) / log(2.0)), 0.0, 1.0)


static func apply_recognition(model_result: Dictionary, score: float, config: Dictionary) -> Dictionary:
	var shifted := model_result.duplicate(true)
	var probabilities: Dictionary = shifted.get("probabilities", {}).duplicate(true)
	if probabilities.is_empty():
		return shifted
	var finite_score := score if is_finite(score) else (INF if score == INF else 0.0)
	var fraction := clampf(minf(float(config.get("recognition_max_shift", 0.12)), maxf(0.0, finite_score * float(config.get("recognition_scale", 1.0)))), 0.0, 1.0)
	var swinging := float(probabilities.get("swinging_strike", 0.0))
	var amount := fraction * swinging
	if amount <= 0.0:
		return shifted
	var has_stage_two := is_finite(float(shifted.get("sampled_launch_speed", NAN))) and is_finite(float(shifted.get("sampled_launch_angle", NAN))) and float(shifted.get("sampled_launch_speed", 0.0)) > 0.0 and float(probabilities.get("in_play", 0.0)) > 0.000001
	probabilities["swinging_strike"] = clampf(swinging - amount, 0.0, 1.0)
	probabilities["foul"] = clampf(float(probabilities.get("foul", 0.0)) + amount * (0.6 if has_stage_two else 1.0), 0.0, 1.0)
	probabilities["in_play"] = clampf(float(probabilities.get("in_play", 0.0)) + amount * (0.4 if has_stage_two else 0.0), 0.0, 1.0)
	shifted["probabilities"] = probabilities
	return shifted


static func deplete_stamina(condition: Dictionary, pitch_code: String, effort: String, situation: Dictionary, config: Dictionary) -> float:
	var pitch_multipliers: Dictionary = config.get("pitch_type_cost_mul", {})
	var effort_multipliers: Dictionary = config.get("effort_cost_mul", {})
	var situation_multipliers: Dictionary = config.get("situation_cost_mul", {})
	var multiplier := float(pitch_multipliers.get(pitch_code.to_upper(), 1.0))
	multiplier *= float(effort_multipliers.get(effort, effort_multipliers.get("normal", 1.0)))
	if bool(situation.get("runners_in_scoring_position", false)):
		multiplier *= float(situation_multipliers.get("runners_in_scoring_position", 1.0))
	if bool(situation.get("two_strike", false)):
		multiplier *= float(situation_multipliers.get("two_strike", 1.0))
	if bool(situation.get("three_ball", false)):
		multiplier *= float(situation_multipliers.get("three_ball", 1.0))
	var cost := float(config.get("base_pitch_cost", 1.0)) * multiplier * float(condition.get("cost_mul", 1.0))
	condition["stamina"] = maxf(0.0, float(condition.get("stamina", 0.0)) - cost)
	condition["pitches_thrown"] = int(condition.get("pitches_thrown", 0)) + 1
	return cost


static func recover_between_halves(condition: Dictionary, config: Dictionary) -> void:
	recover_between_at_bats(condition, float(config.get("half_inning_recovery", 8.0)))


static func recover_between_at_bats(condition: Dictionary, amount: float) -> void:
	condition["stamina"] = minf(float(condition.get("max_stamina", 0.0)), float(condition.get("stamina", 0.0)) + amount)


static func reset_for_new_game(condition: Dictionary, config: Dictionary) -> void:
	condition["stamina"] = float(condition.get("max_stamina", float(config.get("base_max_stamina", 240.0))))
	condition["pitches_thrown"] = 0
	condition["short_len"] = 0
	condition["short_head"] = 0
	var short_history: Array = condition.get("short_history", [])
	for index in short_history.size():
		short_history[index] = {"slot": -1, "loc_bucket": 0}
	condition["short_history"] = short_history
	var long_history: Array = condition.get("long_history", [])
	for index in long_history.size():
		long_history[index] = 0
	condition["long_history"] = long_history
	condition["appearance"] = {"at_bats_faced": 0, "entered_inning": 1}


static func degrade_shape(base_shape: Dictionary, velocity_add: float, factors: Dictionary, config: Dictionary) -> Dictionary:
	var shape := base_shape.duplicate(true)
	var clamps: Dictionary = config.get("degraded_shape_clamps", {})
	shape["velocity"] = clampf((float(base_shape.get("velocity", 90.0)) + velocity_add) * float(factors.get("velocity_mul", 1.0)), float(clamps.get("min_velocity", 68.0)), float(clamps.get("max_velocity", 103.0)))
	shape["effectiveSpeed"] = clampf((float(base_shape.get("effectiveSpeed", base_shape.get("velocity", 90.0))) + velocity_add) * float(factors.get("velocity_mul", 1.0)), float(clamps.get("min_effective_speed", 68.0)), float(clamps.get("max_effective_speed", 105.0)))
	shape["pfxX"] = clampf(float(base_shape.get("pfxX", 0.0)) * float(factors.get("movement_mul", 1.0)), float(clamps.get("min_pfx_x", -1.8)), float(clamps.get("max_pfx_x", 1.8)))
	shape["pfxZ"] = clampf(float(base_shape.get("pfxZ", 0.0)) * float(factors.get("movement_mul", 1.0)), float(clamps.get("min_pfx_z", -1.4)), float(clamps.get("max_pfx_z", 1.8)))
	return shape


static func describe(condition: Dictionary, config: Dictionary, slot_count: int = 5) -> Dictionary:
	var factors := fatigue_factors(condition, config)
	return {
		"stamina": float(condition.get("stamina", 0.0)),
		"max_stamina": float(condition.get("max_stamina", 0.0)),
		"stamina_fraction": float(factors.stamina_fraction),
		"tier": String(factors.tier),
		"pitches_thrown": int(condition.get("pitches_thrown", 0)),
		"at_bats_faced": int((condition.get("appearance", {}) as Dictionary).get("at_bats_faced", 0)),
		"pitch_mix_entropy": pitch_mix_entropy(condition, slot_count),
		"short_history_count": int(condition.get("short_len", 0)),
		"fatigue_factors": factors,
	}


static func _bucket_axis(value: float, minimum: float, maximum: float) -> int:
	var clamped := clampf(value, minimum, maximum)
	if clamped == maximum:
		return BUCKET_AXIS_LEN - 1
	return int(floor(((clamped - minimum) / (maximum - minimum)) * BUCKET_AXIS_LEN))
