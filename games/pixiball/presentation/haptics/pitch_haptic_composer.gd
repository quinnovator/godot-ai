class_name PixiballPitchHapticComposer
extends RefCounted

## Deterministically compiles semantic pitch feedback into a bounded timeline.
##
## Segments use semantic left/right handle amplitudes. Backends decide how
## those values map onto the connected hardware. No model output reaches a
## motor without normalization and the limits enforced by `_finalize`.

const Feedback = preload("res://presentation/haptics/pitch_feedback.gd")

const MAX_DURATION_SEC := 0.60
const MAX_SEGMENT_SEC := 0.18
const MAX_AMPLITUDE := 0.95
const MAX_ENERGY := 0.34


func compose(raw_feedback: Dictionary) -> Dictionary:
	var feedback := Feedback.make(raw_feedback.get("kind", ""), raw_feedback)
	if not bool(feedback.get("ok", false)):
		return feedback

	var segments: Array[Dictionary] = []
	var kind: StringName = feedback["kind"]
	match kind:
		Feedback.RELEASE:
			_compose_release(segments, feedback)
		Feedback.TUNNEL:
			_compose_tunnel(segments, feedback)
		Feedback.FRONTDOOR:
			_compose_frontdoor(segments, feedback)
		Feedback.BACKDOOR:
			_compose_backdoor(segments, feedback)
		Feedback.CORNER_PAINT:
			_compose_corner_paint(segments, feedback)
		Feedback.CALLED_K:
			_compose_called_k(segments, feedback)
		Feedback.SWINGING_K:
			_compose_swinging_k(segments, feedback)

	return _finalize(feedback, segments)


func compose_kind(kind: Variant, values := {}) -> Dictionary:
	var feedback := Feedback.make(kind, values)
	if not bool(feedback.get("ok", false)):
		return feedback
	return compose(feedback)


func _compose_release(segments: Array[Dictionary], feedback: Dictionary) -> void:
	var confidence := float(feedback["confidence"])
	var direction := float(feedback["screen_direction"])
	_add(segments, 0.000, 0.026, 0.12, 0.12, "set")
	_add_pan(segments, 0.030, 0.050, direction, 0.26 + confidence * 0.18, 0.05, "release")


func _compose_tunnel(segments: Array[Dictionary], feedback: Dictionary) -> void:
	var score := float(feedback["tunnel_score"])
	var confidence := float(feedback["confidence"])
	var amplitude := (0.16 + score * 0.28) * lerpf(0.55, 1.0, confidence)
	_append_sweep(segments, 0.000, 4, 0.034, 0.014, float(feedback["screen_direction"]), amplitude, 0.025, "tunnel")


func _compose_frontdoor(segments: Array[Dictionary], feedback: Dictionary) -> void:
	var direction := _nonzero_direction(float(feedback["screen_direction"]), float(feedback["plate_side"]), 1.0)
	var strength := (0.34 + 0.22 * float(feedback["tunnel_score"])) * lerpf(0.6, 1.0, float(feedback["confidence"]))
	_append_sweep(segments, 0.000, 4, 0.040, 0.012, direction, strength, 0.035, "frontdoor")
	_add_pan(segments, 0.205, 0.042, direction, strength * 1.15, 0.04, "frontdoor_catch")


func _compose_backdoor(segments: Array[Dictionary], feedback: Dictionary) -> void:
	var direction := _nonzero_direction(float(feedback["screen_direction"]), -float(feedback["plate_side"]), -1.0)
	var strength := (0.25 + 0.25 * float(feedback["tunnel_score"])) * lerpf(0.6, 1.0, float(feedback["confidence"]))
	_append_sweep(segments, 0.000, 5, 0.030, 0.013, direction, strength, 0.018, "backdoor")
	_add_pan(segments, 0.216, 0.034, direction, strength * 1.25, 0.025, "backdoor_catch")


func _compose_corner_paint(segments: Array[Dictionary], feedback: Dictionary) -> void:
	var side := _nonzero_direction(float(feedback["plate_side"]), float(feedback["screen_direction"]), 1.0)
	var precision := float(feedback["corner_proximity"])
	var confidence := float(feedback["confidence"])
	var strength := (0.38 + precision * 0.44) * lerpf(0.6, 1.0, confidence)
	_add_pan(segments, 0.000, 0.030, side, strength * 0.70, 0.025, "seam")
	_add_pan(segments, 0.038, 0.060, side, strength, 0.035, "corner_impact")
	_add_pan(segments, 0.104, 0.026, side, strength * 0.48, 0.015, "frame")


func _compose_called_k(segments: Array[Dictionary], feedback: Dictionary) -> void:
	var side := _nonzero_direction(float(feedback["plate_side"]), float(feedback["screen_direction"]), 1.0)
	var prediction := maxf(float(feedback["called_strike_probability"]), float(feedback["confidence"]))
	var strength := lerpf(0.58, 0.88, prediction)
	_add(segments, 0.000, 0.072, strength * 0.72, strength * 0.72, "call")
	_add_pan(segments, 0.082, 0.040, side, strength, 0.045, "edge_snap")
	_add(segments, 0.140, 0.105, strength * 0.73, strength * 0.86, "strikeout")


func _compose_swinging_k(segments: Array[Dictionary], feedback: Dictionary) -> void:
	var direction := _nonzero_direction(float(feedback["screen_direction"]), float(feedback["plate_side"]), 1.0)
	var prediction := maxf(float(feedback["whiff_probability"]), float(feedback["confidence"]))
	var strength := lerpf(0.56, 0.90, prediction)
	_add_pan(segments, 0.000, 0.030, -direction, strength * 0.74, 0.02, "miss_one")
	_add_pan(segments, 0.038, 0.032, direction, strength * 0.92, 0.02, "miss_two")
	_add_pan(segments, 0.078, 0.036, -direction, strength, 0.02, "miss_three")
	_add(segments, 0.140, 0.110, strength * 0.88, strength * 0.76, "strikeout")


func _append_sweep(
		segments: Array[Dictionary],
		start_sec: float,
		count: int,
		duration_sec: float,
		gap_sec: float,
		direction: float,
		amplitude: float,
		center: float,
		tag: String,
	) -> void:
	var signed_direction := _nonzero_direction(direction, 0.0, 1.0)
	for index in range(count):
		var progress := float(index) / maxf(1.0, float(count - 1))
		var pan := lerpf(-signed_direction, signed_direction, progress)
		var pulse_amplitude := amplitude * lerpf(0.72, 1.0, progress)
		_add_pan(
			segments,
			start_sec + index * (duration_sec + gap_sec),
			duration_sec,
			pan,
			pulse_amplitude,
			center,
			"%s_%d" % [tag, index],
		)


func _add_pan(
		segments: Array[Dictionary],
		start_sec: float,
		duration_sec: float,
		pan: float,
		amplitude: float,
		center: float,
		tag: String,
	) -> void:
	var normalized_pan := clampf(pan, -1.0, 1.0)
	var left := center + amplitude * (1.0 - normalized_pan) * 0.5
	var right := center + amplitude * (1.0 + normalized_pan) * 0.5
	_add(segments, start_sec, duration_sec, left, right, tag)


func _add(
		segments: Array[Dictionary],
		start_sec: float,
		duration_sec: float,
		left: float,
		right: float,
		tag: String,
	) -> void:
	segments.append({
		"start_sec": start_sec,
		"duration_sec": duration_sec,
		"left": left,
		"right": right,
		"tag": tag,
	})


func _finalize(feedback: Dictionary, source_segments: Array[Dictionary]) -> Dictionary:
	var segments: Array[Dictionary] = []
	for source in source_segments:
		var start_sec := clampf(float(source.get("start_sec", 0.0)), 0.0, MAX_DURATION_SEC)
		var duration_sec := clampf(float(source.get("duration_sec", 0.0)), 0.0, MAX_SEGMENT_SEC)
		duration_sec = minf(duration_sec, MAX_DURATION_SEC - start_sec)
		if duration_sec <= 0.0:
			continue
		segments.append({
			"start_sec": start_sec,
			"duration_sec": duration_sec,
			"left": clampf(float(source.get("left", 0.0)), 0.0, MAX_AMPLITUDE),
			"right": clampf(float(source.get("right", 0.0)), 0.0, MAX_AMPLITUDE),
			"tag": String(source.get("tag", "pulse")),
		})
	segments.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return float(a["start_sec"]) < float(b["start_sec"])
	)

	var energy := _energy(segments)
	if energy > MAX_ENERGY and energy > 0.0:
		var scale := MAX_ENERGY / energy
		for segment in segments:
			segment["left"] = float(segment["left"]) * scale
			segment["right"] = float(segment["right"]) * scale
		energy = _energy(segments)

	var duration_sec := 0.0
	var peak := 0.0
	for segment in segments:
		duration_sec = maxf(duration_sec, float(segment["start_sec"]) + float(segment["duration_sec"]))
		peak = maxf(peak, maxf(float(segment["left"]), float(segment["right"])))

	var travel := _travel(segments)
	return {
		"ok": true,
		"cue_id": String(feedback["kind"]),
		"kind": feedback["kind"],
		"pitch_serial": feedback["pitch_serial"],
		"feedback_time_sec": feedback["event_time_sec"],
		"direction": feedback["screen_direction"],
		"duration_sec": minf(duration_sec, MAX_DURATION_SEC),
		"energy": energy,
		"peak": peak,
		"travel": travel,
		"segments": segments,
		"semantic": feedback.duplicate(true),
	}


func _energy(segments: Array[Dictionary]) -> float:
	var total := 0.0
	for segment in segments:
		total += float(segment["duration_sec"]) * (float(segment["left"]) + float(segment["right"])) * 0.5
	return total


func _travel(segments: Array[Dictionary]) -> float:
	if segments.is_empty():
		return 0.0
	var first_pan := _pan(segments.front())
	var last_pan := _pan(segments.back())
	var travel := last_pan - first_pan
	if absf(travel) > 0.05:
		return clampf(travel * 0.5, -1.0, 1.0)
	var weighted_pan := 0.0
	var weight := 0.0
	for segment in segments:
		var segment_weight := float(segment["duration_sec"]) * (float(segment["left"]) + float(segment["right"]))
		weighted_pan += _pan(segment) * segment_weight
		weight += segment_weight
	return clampf(weighted_pan / maxf(weight, 0.0001), -1.0, 1.0)


func _pan(segment: Dictionary) -> float:
	var left := float(segment["left"])
	var right := float(segment["right"])
	return (right - left) / maxf(left + right, 0.0001)


func _nonzero_direction(primary: float, secondary: float, fallback: float) -> float:
	if absf(primary) > 0.001:
		return signf(primary)
	if absf(secondary) > 0.001:
		return signf(secondary)
	return signf(fallback)
