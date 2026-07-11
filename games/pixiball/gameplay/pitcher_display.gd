class_name PixiballPitcherDisplay
extends RefCounted

## Exact card-rating port from:
##   ../pixiball-ue/Source/PixCore/Sim/PitcherDisplay.cpp
## OVR is gameplay data: PixiballTeams uses it to rank the versus draft.

const FASTBALL_CODES := ["FF", "SI", "FC", "FA"]
const BREAKING_CODES := ["SL", "ST", "SV", "CU", "KC", "KN", "SW", "CS"]


static func build_cache(pool: Array) -> Dictionary:
	if pool.is_empty():
		return {}
	var metrics: Array[Dictionary] = []
	for pitcher_value in pool:
		metrics.append(_raw_metrics(pitcher_value as Dictionary))
	var ranges := {
		"velo": _metric_range(metrics, "velo"),
		"whiff": _metric_range(metrics, "whiff"),
		"cmd": _metric_range(metrics, "cmd"),
		"fastball_share": _metric_range(metrics, "fastball_share"),
	}
	var cache := {}
	for index in pool.size():
		var pitcher: Dictionary = pool[index]
		var metric: Dictionary = metrics[index]
		var n_velo := _norm(float(metric.velo), ranges.velo)
		var n_whiff := _norm(float(metric.whiff), ranges.whiff)
		var n_cmd := _norm(float(metric.cmd), ranges.cmd)
		var card := {
			"ovr": _round_half_up_fast(70.0 + 29.0 * (0.4 * n_velo + 0.4 * n_whiff + 0.2 * n_cmd)),
			"era": "%.2f" % (4.6 - 2.2 * n_cmd),
			"k9": "%.1f" % (7.5 + 4.0 * n_whiff),
			"velo": _round_half_up_fast(float(metric.velo)),
			"stamina": 0.35 + 0.55 * (1.0 - _norm(float(metric.fastball_share), ranges.fastball_share)),
			"archetype": "POWER" if float(metric.velo) >= 96.0 else ("CRAFTY" if float(metric.breaking_share) >= 0.5 else "CONTROL"),
		}
		cache[int(pitcher.get("id", -1))] = card
	return cache


static func card_for(cache: Dictionary, pitcher_id: int) -> Dictionary:
	return (cache.get(pitcher_id, {}) as Dictionary).duplicate(true)


static func _raw_metrics(pitcher: Dictionary) -> Dictionary:
	var velo := 0.0
	var whiff := 0.0
	var scatter := 0.0
	var fastball := 0.0
	var breaking := 0.0
	var usage_sum := 0.0
	for pitch_value in pitcher.get("pitches", []) as Array:
		var pitch: Dictionary = pitch_value
		var shape: Dictionary = pitch.get("shape", pitch)
		var usage := float(pitch.get("usage", 0.0))
		var code := String(pitch.get("code", ""))
		velo = maxf(velo, float(shape.get("velocity", pitch.get("velocity", 0.0))))
		whiff += usage * float(pitch.get("whiffRate", 0.0))
		scatter += usage * (float(shape.get("controlXStd", pitch.get("controlXStd", 0.0))) + float(shape.get("controlZStd", pitch.get("controlZStd", 0.0))))
		if code in FASTBALL_CODES:
			fastball += usage
		if code in BREAKING_CODES:
			breaking += usage
		usage_sum += usage
	var divisor := usage_sum if usage_sum != 0.0 else 1.0
	return {
		"velo": velo,
		"whiff": whiff / divisor,
		"cmd": -scatter / divisor,
		"fastball_share": fastball / divisor,
		"breaking_share": breaking / divisor,
	}


static func _metric_range(metrics: Array[Dictionary], key: String) -> Dictionary:
	var low := INF
	var high := -INF
	for metric in metrics:
		low = minf(low, float(metric[key]))
		high = maxf(high, float(metric[key]))
	return {"lo": low, "hi": high}


static func _norm(value: float, metric_range: Dictionary) -> float:
	var low := float(metric_range.lo)
	var high := float(metric_range.hi)
	if high == low:
		return 0.5
	return clampf((value - low) / (high - low), 0.0, 1.0)


static func _round_half_up_fast(value: float) -> int:
	return int(floor(value + 0.5))
