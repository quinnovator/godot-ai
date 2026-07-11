class_name PixiballBullpen
extends RefCounted

## Pure bullpen manager state ported from:
##   ../pixiball-ue/Source/PixCore/Sim/Bullpen.{h,cpp}


static func fresh_state(active_index: int = 0) -> Dictionary:
	return {"active_index": maxi(0, active_index), "warming": {}}


static func start_warming(bullpen: Dictionary, index: int) -> void:
	if index < 0:
		return
	var warming: Dictionary = bullpen.get("warming", {})
	if not warming.is_empty() and int(warming.get("index", -1)) == index:
		return
	bullpen["warming"] = {"index": index, "readiness": 0}


static func advance_warmup(bullpen: Dictionary) -> void:
	var warming: Dictionary = bullpen.get("warming", {})
	if warming.is_empty():
		return
	warming["readiness"] = int(warming.get("readiness", 0)) + 1
	bullpen["warming"] = warming


static func is_reliever_ready(bullpen: Dictionary, config: Dictionary) -> bool:
	var warming: Dictionary = bullpen.get("warming", {})
	return not warming.is_empty() and int(warming.get("readiness", 0)) >= int(config.get("warmup_at_bats_required", 3))


static func decide_manager(bullpen: Dictionary, current_condition: Dictionary, roster_size: int, config: Dictionary) -> String:
	if not bool(config.get("enabled", false)):
		return "none"
	if int(bullpen.get("active_index", 0)) + 1 >= roster_size:
		return "none"
	var factors := PixiballPitcherCondition.fatigue_factors(current_condition, config)
	var maximum := float(current_condition.get("max_stamina", 1.0))
	# The original intentionally uses the raw fraction here.
	var fraction := float(current_condition.get("stamina", 0.0)) / maximum if maximum != 0.0 else 0.0
	if fraction < float(config.get("emergency_stamina_fraction", 0.12)):
		return "substitute"
	var warming: Dictionary = bullpen.get("warming", {})
	var warming_is_rostered := not warming.is_empty() and int(warming.get("index", -1)) >= 0 and int(warming.get("index", -1)) < roster_size
	if String(factors.tier) == "gassed" and warming_is_rostered and int(warming.get("readiness", 0)) >= int(config.get("warmup_at_bats_required", 3)):
		return "substitute"
	# Fidelity detail: Bullpen.cpp hard-codes tired/gassed and does not consult
	# warm_at_tier/substitute_at_tier despite retaining those config fields.
	if warming.is_empty() and (String(factors.tier) in ["tired", "gassed"] or int(current_condition.get("pitches_thrown", 0)) >= int(config.get("pitch_count_warm_threshold", 75))):
		return "warm"
	return "none"


static func substitution_target(bullpen: Dictionary, roster_size: int) -> int:
	var active := int(bullpen.get("active_index", 0))
	var warming: Dictionary = bullpen.get("warming", {})
	if not warming.is_empty():
		var warming_index := int(warming.get("index", -1))
		if warming_index > active and warming_index < roster_size:
			return warming_index
	var next := active + 1
	return next if next < roster_size else -1
