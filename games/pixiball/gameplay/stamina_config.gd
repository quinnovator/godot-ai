class_name PixiballStaminaConfig
extends RefCounted

## Frozen default stamina table from the original Pixiball simulation.
##
## Fidelity source:
##   ../pixiball-ue/Source/PixCore/Sim/StaminaConfig.{h,cpp}
## Keeping the complete table in one reviewable dictionary makes it possible
## for agent-authored modes to tune a copy without hiding magic numbers in the
## pitch or bullpen code.


static func defaults() -> Dictionary:
	return {
		"enabled": true,
		"base_max_stamina": 240.0,
		"base_pitch_cost": 1.0,
		"pitch_type_cost_mul": {
			"FF": 1.15,
			"SI": 1.15,
			"FC": 1.10,
			"SL": 1.00,
			"ST": 1.00,
			"CU": 1.00,
			"KC": 1.00,
			"SV": 1.00,
			"CH": 0.90,
			"FS": 0.90,
		},
		"effort_cost_mul": {"cruise": 0.8, "normal": 1.0, "high": 1.35},
		"effort_velocity_add": {"cruise": -1.0, "normal": 0.0, "high": 1.5},
		"situation_cost_mul": {
			"runners_in_scoring_position": 1.12,
			"two_strike": 1.08,
			"three_ball": 1.08,
		},
		"fatigue_exponent": 1.4,
		"velocity_floor_mul": 0.92,
		"movement_floor_mul": 0.80,
		"command_std_max": 0.35,
		"degraded_shape_clamps": {
			"min_velocity": 68.0,
			"max_velocity": 103.0,
			"min_effective_speed": 68.0,
			"max_effective_speed": 105.0,
			"min_pfx_x": -1.8,
			"max_pfx_x": 1.8,
			"min_pfx_z": -1.4,
			"max_pfx_z": 1.8,
		},
		"tier_thresholds": {"tiring": 0.65, "tired": 0.40, "gassed": 0.20},
		"short_window_len": 6,
		"long_window_slots": 24,
		"recognition_max_shift": 0.12,
		"recognition_scale": 1.0,
		"human_timing_tolerance_max": 0.08,
		"entropy_floor": 0.55,
		"anti_rep_penalty": 0.25,
		"warmup_at_bats_required": 3,
		"warm_at_tier": "tiring",
		"substitute_at_tier": "gassed",
		"pitch_count_warm_threshold": 75,
		"emergency_stamina_fraction": 0.12,
		"half_inning_recovery": 8.0,
		"per_game_reset": true,
	}


static func validate(config: Dictionary) -> bool:
	if not bool(config.get("enabled", false)):
		return true
	if float(config.get("base_max_stamina", 0.0)) <= 0.0:
		return false
	if float(config.get("base_pitch_cost", 0.0)) <= 0.0:
		return false
	if int(config.get("short_window_len", 0)) <= 0 or int(config.get("long_window_slots", 0)) <= 0:
		return false
	var thresholds: Dictionary = config.get("tier_thresholds", {})
	var tiring := float(thresholds.get("tiring", 0.0))
	var tired := float(thresholds.get("tired", 0.0))
	var gassed := float(thresholds.get("gassed", 0.0))
	if not (tiring > tired and tired > gassed and gassed > 0.0 and tiring < 1.0):
		return false
	for key in ["velocity_floor_mul", "movement_floor_mul"]:
		var value := float(config.get(key, 0.0))
		if value <= 0.0 or value > 1.0:
			return false
	return true
