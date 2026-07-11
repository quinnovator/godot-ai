class_name PixiballPitchFeedback
extends RefCounted

## Canonical semantic input to the pitch haptics system.
##
## Predictive models and gameplay code communicate through this bounded
## dictionary instead of writing actuator amplitudes directly. Horizontal
## values are in the player's screen space: -1 is left and +1 is right.

const RELEASE := &"release"
const TUNNEL := &"tunnel"
const FRONTDOOR := &"frontdoor"
const BACKDOOR := &"backdoor"
const CORNER_PAINT := &"corner_paint"
const CALLED_K := &"called_k"
const SWINGING_K := &"swinging_k"

const TYPES: Array[StringName] = [
	RELEASE,
	TUNNEL,
	FRONTDOOR,
	BACKDOOR,
	CORNER_PAINT,
	CALLED_K,
	SWINGING_K,
]

const _ALIASES := {
	"paint": CORNER_PAINT,
	"corner": CORNER_PAINT,
	"called_strikeout": CALLED_K,
	"strikeout_called": CALLED_K,
	"swinging_strikeout": SWINGING_K,
	"strikeout_swinging": SWINGING_K,
}


static func make(kind_value: Variant, values := {}) -> Dictionary:
	var kind := StringName(String(kind_value).strip_edges().to_lower())
	if _ALIASES.has(String(kind)):
		kind = _ALIASES[String(kind)]
	if kind not in TYPES:
		return {
			"ok": false,
			"error": "unknown pitch feedback kind: %s" % kind,
			"kind": kind,
		}

	var source: Dictionary = values if values is Dictionary else {}
	var model: Dictionary = source.get("model", {})
	if not model is Dictionary:
		model = {}

	var plate_x := _finite_float(source.get("plate_x", model.get("plate_x", 0.0)), 0.0)
	var plate_side := _unit_direction(source.get("plate_side", 0.0))
	if is_zero_approx(plate_side):
		plate_side = _unit_direction(plate_x)

	var screen_direction := _unit_direction(source.get(
		"screen_direction",
		source.get("direction", model.get("tunnel_direction", 0.0)),
	))
	if is_zero_approx(screen_direction):
		if kind in [FRONTDOOR, CORNER_PAINT]:
			screen_direction = plate_side
		elif kind == BACKDOOR:
			screen_direction = -plate_side

	var event := {
		"ok": true,
		"kind": kind,
		"pitch_serial": maxi(0, int(source.get("pitch_serial", 0))),
		"event_time_sec": maxf(0.0, _finite_float(source.get("event_time_sec", source.get("time_sec", 0.0)), 0.0)),
		"screen_direction": screen_direction,
		"plate_x": plate_x,
		"plate_side": plate_side,
		"batter_inside_side": _unit_direction(source.get("batter_inside_side", 0.0)),
		"confidence": _probability(source.get("confidence", model.get("confidence", 1.0))),
		"tunnel_score": _probability(source.get("tunnel_score", model.get("tunnel_score", 0.5))),
		"corner_proximity": _probability(source.get("corner_proximity", model.get("corner_proximity", 0.0))),
		"zone_probability": _probability(source.get("zone_probability", model.get("zone_probability", 0.5))),
		"called_strike_probability": _probability(source.get("called_strike_probability", model.get("called_strike_probability", 0.0))),
		"whiff_probability": _probability(source.get("whiff_probability", model.get("whiff_probability", 0.0))),
		"outcome_confirmed": bool(source.get("outcome_confirmed", false)),
		"metadata": _metadata(source),
	}
	return event


static func describe_schema() -> Dictionary:
	return {
		"kinds": TYPES.duplicate(),
		"coordinates": "player_screen_space: -1 left, +1 right",
		"probability_fields": [
			"confidence",
			"tunnel_score",
			"corner_proximity",
			"zone_probability",
			"called_strike_probability",
			"whiff_probability",
		],
		"required": ["kind"],
		"hardware_values_allowed": false,
	}


static func _metadata(source: Dictionary) -> Dictionary:
	var metadata: Variant = source.get("metadata", {})
	if metadata is Dictionary:
		return metadata.duplicate(true)
	return {}


static func _probability(value: Variant) -> float:
	return clampf(_finite_float(value, 0.0), 0.0, 1.0)


static func _unit_direction(value: Variant) -> float:
	return clampf(_finite_float(value, 0.0), -1.0, 1.0)


static func _finite_float(value: Variant, fallback: float) -> float:
	var number := float(value)
	if is_nan(number) or is_inf(number):
		return fallback
	return number
