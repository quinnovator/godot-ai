extends SceneTree

const Feedback = preload("res://presentation/haptics/pitch_feedback.gd")
const ComposerScript = preload("res://presentation/haptics/pitch_haptic_composer.gd")
const Backends = preload("res://presentation/haptics/haptic_backends.gd")
const DirectorScript = preload("res://presentation/haptics/haptic_director.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_semantic_boundary()
	_test_determinism_and_bounds()
	_test_direction_and_timing()
	_test_portable_backend_contract()
	await _test_director_recording_and_cleanup()

	if _failures.is_empty():
		print("PIXIBALL_HAPTICS_OK cues=7 backends=3")
		quit(0)
	else:
		for failure in _failures:
			push_error("PIXIBALL_HAPTICS: %s" % failure)
		quit(1)


func _test_semantic_boundary() -> void:
	var invalid := Feedback.make("laser_controller_packet", {"confidence": 9.0})
	_check(not bool(invalid.ok), "unknown semantic event kinds must be rejected")
	var normalized := Feedback.make("paint", {
		"confidence": 4.0,
		"corner_proximity": -2.0,
		"plate_x": -0.72,
		"model": {"whiff_probability": 1.7},
	})
	_check(normalized.kind == Feedback.CORNER_PAINT, "semantic aliases must normalize")
	_check(is_equal_approx(float(normalized.confidence), 1.0), "confidence must clamp to probability range")
	_check(is_equal_approx(float(normalized.corner_proximity), 0.0), "corner proximity must clamp to probability range")
	_check(float(normalized.plate_side) < 0.0, "plate side should derive from signed plate location")
	_check(not bool(Feedback.describe_schema().hardware_values_allowed), "model boundary must forbid direct hardware values")


func _test_determinism_and_bounds() -> void:
	var composer = ComposerScript.new()
	var kinds := [
		Feedback.RELEASE,
		Feedback.TUNNEL,
		Feedback.FRONTDOOR,
		Feedback.BACKDOOR,
		Feedback.CORNER_PAINT,
		Feedback.CALLED_K,
		Feedback.SWINGING_K,
	]
	for kind in kinds:
		var raw := {
			"kind": kind,
			"pitch_serial": 41,
			"event_time_sec": 0.375,
			"screen_direction": 1.0,
			"plate_side": 1.0,
			"confidence": 1.0,
			"tunnel_score": 1.0,
			"corner_proximity": 1.0,
			"called_strike_probability": 1.0,
			"whiff_probability": 1.0,
		}
		var first: Dictionary = composer.compose(raw)
		var second: Dictionary = composer.compose(raw)
		_check(first == second, "%s cue must be deterministic" % kind)
		_check(bool(first.ok), "%s cue must compose" % kind)
		_check(float(first.duration_sec) > 0.0 and float(first.duration_sec) <= ComposerScript.MAX_DURATION_SEC + 0.0001,
			"%s duration must be bounded" % kind)
		_check(float(first.energy) <= ComposerScript.MAX_ENERGY + 0.0001, "%s energy must be bounded" % kind)
		_check(float(first.peak) <= ComposerScript.MAX_AMPLITUDE + 0.0001, "%s peak must be bounded" % kind)
		for segment_value in first.segments:
			var segment: Dictionary = segment_value
			_check(float(segment.left) >= 0.0 and float(segment.left) <= ComposerScript.MAX_AMPLITUDE,
				"%s left segment amplitude must be bounded" % kind)
			_check(float(segment.right) >= 0.0 and float(segment.right) <= ComposerScript.MAX_AMPLITUDE,
				"%s right segment amplitude must be bounded" % kind)
			_check(float(segment.start_sec) + float(segment.duration_sec) <= float(first.duration_sec) + 0.0001,
				"%s segments must remain within the cue" % kind)


func _test_direction_and_timing() -> void:
	var composer = ComposerScript.new()
	var frontdoor: Dictionary = composer.compose_kind(Feedback.FRONTDOOR, {
		"screen_direction": 1.0,
		"plate_side": 1.0,
		"confidence": 0.9,
		"tunnel_score": 0.8,
	})
	var backdoor: Dictionary = composer.compose_kind(Feedback.BACKDOOR, {
		"screen_direction": -1.0,
		"plate_side": -1.0,
		"confidence": 0.9,
		"tunnel_score": 0.8,
	})
	_check(float(frontdoor.travel) > 0.35, "frontdoor cue must travel toward screen right when requested")
	_check(float(backdoor.travel) < -0.35, "backdoor cue must travel toward screen left when requested")

	var left_paint: Dictionary = composer.compose_kind(Feedback.CORNER_PAINT, {
		"plate_side": -1.0,
		"corner_proximity": 1.0,
		"confidence": 1.0,
	})
	var left_energy := 0.0
	var right_energy := 0.0
	for segment_value in left_paint.segments:
		var segment: Dictionary = segment_value
		left_energy += float(segment.left) * float(segment.duration_sec)
		right_energy += float(segment.right) * float(segment.duration_sec)
	_check(left_energy > right_energy * 2.0, "left corner paint must emphasize the left semantic handle")

	var called_k: Dictionary = composer.compose_kind(Feedback.CALLED_K, {
		"plate_side": 1.0,
		"called_strike_probability": 1.0,
	})
	_check(String(called_k.segments[0].tag) == "call" and float(called_k.segments[0].start_sec) == 0.0,
		"called strikeout must begin with the call beat")
	_check(String(called_k.segments[-1].tag) == "strikeout" and float(called_k.segments[-1].start_sec) >= 0.14,
		"strikeout payoff must follow, not precede, the plate call")
	_check(is_equal_approx(float(called_k.feedback_time_sec), 0.0), "cue local time should remain separate from feedback event time")


func _test_portable_backend_contract() -> void:
	var centered := Backends.GodotRumbleBackend.map_semantic_to_rumble(0.6, 0.6)
	_check(is_equal_approx(float(centered.weak), float(centered.strong)),
		"centered semantic output must remain balanced across frequency channels")
	var left := Backends.GodotRumbleBackend.map_semantic_to_rumble(1.0, 0.0)
	var right := Backends.GodotRumbleBackend.map_semantic_to_rumble(0.0, 1.0)
	_check(float(left.strong) > float(left.weak) * 4.0,
		"player-left cues must be strong/low-frequency dominant")
	_check(float(right.weak) > float(right.strong) * 4.0,
		"player-right cues must be weak/high-frequency dominant")
	var bounded := Backends.GodotRumbleBackend.map_semantic_to_rumble(9.0, -4.0)
	_check(
		float(bounded.weak) >= 0.0 and float(bounded.weak) <= 1.0
		and float(bounded.strong) >= 0.0 and float(bounded.strong) <= 1.0,
		"portable motor conversion must clamp malformed values")

	var adaptive_left := Backends.GodotRumbleBackend.map_semantic_to_adaptive(0.9, 0.05)
	var adaptive_right := Backends.GodotRumbleBackend.map_semantic_to_adaptive(0.05, 0.9)
	var adaptive_center := Backends.GodotRumbleBackend.map_semantic_to_adaptive(0.7, 0.7)
	_check(bool(adaptive_left.active) and int(adaptive_left.side) == Backends.GodotRumbleBackend.ADAPTIVE_TRIGGER_LEFT,
		"left-dominant semantic output must select the physical L2 locality")
	_check(bool(adaptive_right.active) and int(adaptive_right.side) == Backends.GodotRumbleBackend.ADAPTIVE_TRIGGER_RIGHT,
		"right-dominant semantic output must select the physical R2 locality")
	_check(not bool(adaptive_center.active),
		"centered output must not invent an adaptive-trigger direction")
	for adaptive in [adaptive_left, adaptive_right]:
		_check(
			int(adaptive.position) >= 0 and int(adaptive.position) <= 9
			and int(adaptive.amplitude) >= 1 and int(adaptive.amplitude) <= 8
			and int(adaptive.frequency_hz) >= 1 and int(adaptive.frequency_hz) <= 255,
			"adaptive-trigger conversion must remain inside the native API's validated ranges",
		)

	var edge := Backends.GodotRumbleBackend.describe_controller({
		"vendor_id": "0x054c",
		"product_id": "0x0df2",
	}, "Wireless Controller")
	_check(bool(edge.dualsense) and bool(edge.dualsense_edge),
		"DualSense Edge identity must accept numeric IDs serialized as hexadecimal strings")
	var name_fallback := Backends.GodotRumbleBackend.describe_controller({}, "DualSense Edge Wireless Controller")
	_check(bool(name_fallback.dualsense_edge),
		"DualSense detection must fall back to the mapped controller name when driver IDs are absent")

	var unavailable = Backends.GodotRumbleBackend.new()
	var caps: Dictionary = unavailable.capabilities(-1)
	_check(not bool(caps.available) and not bool(caps.true_spatial_direction),
		"portable backend must report unavailable hardware and never claim true spatial output")
	var rejected: Dictionary = unavailable.apply(-1, 1.0, 0.0, 0.05, 0.0, ["probe"])
	var diagnostic: Dictionary = unavailable.diagnostic(-1)
	_check(not bool(rejected.accepted) and int(diagnostic.rejected_count) == 1,
		"portable backend must reject and diagnose output sent without a rumble-capable controller")


func _test_director_recording_and_cleanup() -> void:
	var director = DirectorScript.new()
	director.name = "HapticDirectorTest"
	director.set_process(false)
	var recorder = Backends.RecordingBackend.new()
	director.set_backend(recorder)
	director.device_id = 0
	root.add_child(director)
	await process_frame

	director.set_accessibility_gain(0.5)
	var started: Dictionary = director.play_kind(Feedback.FRONTDOOR, {
		"pitch_serial": 19,
		"event_time_sec": 0.42,
		"screen_direction": 1.0,
		"plate_side": 1.0,
		"confidence": 1.0,
		"tunnel_score": 1.0,
	})
	_check(bool(started.accepted) and started.type == "cue_started", "director must return an accepted start event")
	_check(is_equal_approx(float(started.feedback_time_sec), 0.42), "director must preserve semantic event timing")

	var finished_seen := false
	for tick in range(90):
		var emitted: Array[Dictionary] = director.advance(1.0 / 120.0)
		for event in emitted:
			finished_seen = finished_seen or String(event.type) == "cue_finished"
	_check(not recorder.entries.is_empty(), "recording backend must receive sampled output")
	var maximum_recorded := 0.0
	for entry in recorder.entries:
		if entry.type == "output":
			maximum_recorded = maxf(maximum_recorded, maxf(float(entry.left), float(entry.right)))
	_check(maximum_recorded <= ComposerScript.MAX_AMPLITUDE * 0.5 + 0.0001,
		"accessibility gain must scale every hardware sample")
	_check(finished_seen, "director must emit cue_finished after the bounded timeline")
	_check(recorder.stop_count >= 1 and recorder.last_output == Vector2.ZERO,
		"director must stop hardware after the cue falls silent")

	var restarted: Dictionary = director.play_kind(Feedback.SWINGING_K, {
		"screen_direction": -1.0,
		"whiff_probability": 1.0,
	})
	_check(bool(restarted.accepted), "director should accept a cue after prior completion")
	director.advance(1.0 / 120.0)
	var disabled: Dictionary = director.set_haptics_enabled(false)
	_check(disabled.reason == "accessibility_disabled", "disabling haptics must report its cleanup reason")
	_check(director.diagnostic_state().active_cues.is_empty(), "disabling haptics must clear active cues")
	_check(recorder.last_output == Vector2.ZERO, "disabling haptics must stop backend output")
	var rejected: Dictionary = director.play_kind(Feedback.RELEASE)
	_check(not bool(rejected.accepted) and rejected.reason == "haptics_disabled",
		"disabled accessibility setting must reject new cues")

	director.set_haptics_enabled(true)
	director.set_accessibility_gain(1.0)
	director.play_kind(Feedback.RELEASE, {"screen_direction": 1.0})
	director.advance(1.0 / 120.0)
	director._on_joy_connection_changed(0, false)
	_check(director.diagnostic_state().active_cues.is_empty() and recorder.last_output == Vector2.ZERO,
		"selected-device disconnect must synchronously stop active haptics")
	director.play_kind(Feedback.RELEASE, {"screen_direction": 1.0})
	director.advance(1.0 / 120.0)
	var stops_before_free: int = recorder.stop_count
	director.queue_free()
	await process_frame
	_check(recorder.stop_count > stops_before_free and recorder.last_output == Vector2.ZERO,
		"leaving the tree must synchronously stop haptic output")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
