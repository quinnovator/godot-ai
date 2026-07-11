class_name PixiballHapticDirector
extends Node

## Schedules, mixes, and safely stops semantic pitch haptic cues.
##
## `advance()` is public and deterministic so agent scenarios and headless tests
## can drive this component without wall-clock time. Runtime users can leave
## processing enabled and call `play_feedback()` as pitch events occur.

signal haptic_event(event: Dictionary)

const ComposerScript = preload("res://presentation/haptics/pitch_haptic_composer.gd")
const Backends = preload("res://presentation/haptics/haptic_backends.gd")

const MAX_ACTIVE_CUES := 8
const OUTPUT_HOLD_MIN_SEC := 0.025
const OUTPUT_HOLD_MAX_SEC := 0.100

var haptics_enabled := true
var accessibility_gain := 1.0
var device_id := -1

var _composer = ComposerScript.new()
var _backend = null
var _clock_sec := 0.0
var _active: Array[Dictionary] = []
var _events: Array[Dictionary] = []
var _last_output := Vector2.ZERO # x = left, y = right.
var _next_instance_id := 1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if _backend == null:
		_backend = Backends.GodotRumbleBackend.new()
	if not Input.joy_connection_changed.is_connected(_on_joy_connection_changed):
		Input.joy_connection_changed.connect(_on_joy_connection_changed)


func _process(delta: float) -> void:
	advance(delta)


func _exit_tree() -> void:
	stop_all("exit_tree")


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		stop_all("focus_lost")


func set_backend(backend: Variant) -> Dictionary:
	if backend == null or not backend.has_method("apply") or not backend.has_method("stop"):
		return {"accepted": false, "reason": "invalid_backend"}
	if _backend != null:
		_backend.stop(_resolved_device_id(), _clock_sec, "backend_changed")
	_backend = backend
	_last_output = Vector2.ZERO
	return {
		"accepted": true,
		"backend": String(_backend.backend_name),
		"capabilities": _backend.capabilities(_resolved_device_id()),
	}


func use_null_backend() -> Dictionary:
	return set_backend(Backends.NullBackend.new())


func use_recording_backend(capability_overrides := {}) -> Variant:
	var backend = Backends.RecordingBackend.new(capability_overrides)
	set_backend(backend)
	return backend


func use_godot_rumble_backend() -> Dictionary:
	return set_backend(Backends.GodotRumbleBackend.new())


func play_kind(kind: Variant, values := {}) -> Dictionary:
	var feedback: Dictionary = values.duplicate(true) if values is Dictionary else {}
	feedback["kind"] = kind
	return play_feedback(feedback)


func play_feedback(feedback: Dictionary) -> Dictionary:
	var cue: Dictionary = _composer.compose(feedback)
	if not bool(cue.get("ok", false)):
		return _emit({
			"type": "cue_rejected",
			"accepted": false,
			"at_sec": _clock_sec,
			"reason": String(cue.get("error", "composition_failed")),
		})
	return play_cue(cue)


func play_cue(cue: Dictionary) -> Dictionary:
	if not haptics_enabled or accessibility_gain <= 0.0:
		return _emit({
			"type": "cue_rejected",
			"accepted": false,
			"at_sec": _clock_sec,
			"cue_id": String(cue.get("cue_id", "unknown")),
			"reason": "haptics_disabled",
		})
	if not bool(cue.get("ok", false)) or float(cue.get("duration_sec", 0.0)) <= 0.0:
		return _emit({
			"type": "cue_rejected",
			"accepted": false,
			"at_sec": _clock_sec,
			"reason": "invalid_cue",
		})

	if _active.size() >= MAX_ACTIVE_CUES:
		var evicted: Dictionary = _active.pop_front()
		_emit({
			"type": "cue_cancelled",
			"accepted": true,
			"at_sec": _clock_sec,
			"instance_id": evicted["instance_id"],
			"cue_id": evicted["cue"]["cue_id"],
			"reason": "active_limit",
		})

	var instance_id := _next_instance_id
	_next_instance_id += 1
	var instance := {
		"instance_id": instance_id,
		"started_at": _clock_sec,
		"cue": cue.duplicate(true),
	}
	_active.append(instance)
	var resolved_device := _resolved_device_id()
	var capabilities: Dictionary = _backend_or_default().capabilities(resolved_device)
	return _emit({
		"type": "cue_started",
		"accepted": true,
		"at_sec": _clock_sec,
		"feedback_time_sec": float(cue.get("feedback_time_sec", 0.0)),
		"instance_id": instance_id,
		"cue_id": String(cue["cue_id"]),
		"kind": cue["kind"],
		"pitch_serial": int(cue.get("pitch_serial", 0)),
		"duration_sec": float(cue["duration_sec"]),
		"direction": float(cue.get("direction", 0.0)),
		"backend": String(_backend_or_default().backend_name),
		"device_id": resolved_device,
		"output_available": bool(capabilities.get("available", false)),
	})


func advance(delta_sec: float) -> Array[Dictionary]:
	var emitted: Array[Dictionary] = []
	if delta_sec <= 0.0:
		return emitted
	_clock_sec += delta_sec

	var left := 0.0
	var right := 0.0
	var cue_ids: Array[String] = []
	var survivors: Array[Dictionary] = []
	for instance in _active:
		var cue: Dictionary = instance["cue"]
		var local_time := _clock_sec - float(instance["started_at"])
		if local_time >= float(cue["duration_sec"]):
			var finished := {
				"type": "cue_finished",
				"accepted": true,
				"at_sec": _clock_sec,
				"instance_id": instance["instance_id"],
				"cue_id": String(cue["cue_id"]),
				"kind": cue["kind"],
			}
			emitted.append(_emit(finished))
			continue
		survivors.append(instance)
		var sample := _sample(cue, local_time)
		left = maxf(left, float(sample.x))
		right = maxf(right, float(sample.y))
		if sample != Vector2.ZERO:
			cue_ids.append(String(cue["cue_id"]))
	_active = survivors

	left = clampf(left * accessibility_gain, 0.0, 1.0)
	right = clampf(right * accessibility_gain, 0.0, 1.0)
	var output := Vector2(left, right)
	if output != Vector2.ZERO:
		var hold_sec := clampf(delta_sec * 2.5, OUTPUT_HOLD_MIN_SEC, OUTPUT_HOLD_MAX_SEC)
		_backend_or_default().apply(_resolved_device_id(), left, right, hold_sec, _clock_sec, cue_ids)
	elif _last_output != Vector2.ZERO:
		_backend_or_default().stop(_resolved_device_id(), _clock_sec, "cue_silence")
	_last_output = output
	return emitted


func stop_all(reason := "manual") -> Dictionary:
	var stopped := _active.size()
	_active.clear()
	if _backend != null:
		_backend.stop(_resolved_device_id(), _clock_sec, reason)
	_last_output = Vector2.ZERO
	return _emit({
		"type": "all_stopped",
		"accepted": true,
		"at_sec": _clock_sec,
		"stopped_cues": stopped,
		"reason": reason,
	})


func set_haptics_enabled(value: bool) -> Dictionary:
	haptics_enabled = value
	if not value:
		return stop_all("accessibility_disabled")
	return _emit({
		"type": "settings_changed",
		"accepted": true,
		"at_sec": _clock_sec,
		"haptics_enabled": true,
		"accessibility_gain": accessibility_gain,
	})


func set_accessibility_gain(value: float) -> Dictionary:
	accessibility_gain = clampf(value, 0.0, 1.0)
	if accessibility_gain <= 0.0:
		return stop_all("accessibility_gain_zero")
	return _emit({
		"type": "settings_changed",
		"accepted": true,
		"at_sec": _clock_sec,
		"haptics_enabled": haptics_enabled,
		"accessibility_gain": accessibility_gain,
	})


func select_device(value: int) -> Dictionary:
	if _backend != null:
		_backend.stop(_resolved_device_id(), _clock_sec, "device_changed")
	device_id = value
	_last_output = Vector2.ZERO
	return _emit({
		"type": "device_changed",
		"accepted": true,
		"at_sec": _clock_sec,
		"device_id": _resolved_device_id(),
		"capabilities": _backend_or_default().capabilities(_resolved_device_id()),
	})


func diagnostic_state() -> Dictionary:
	var active_cues: Array[Dictionary] = []
	for instance in _active:
		active_cues.append({
			"instance_id": instance["instance_id"],
			"cue_id": instance["cue"]["cue_id"],
			"started_at": instance["started_at"],
			"remaining_sec": maxf(
				0.0,
				float(instance["cue"]["duration_sec"]) - (_clock_sec - float(instance["started_at"])),
			),
		})
	var resolved_device := _resolved_device_id()
	return {
		"enabled": haptics_enabled,
		"accessibility_gain": accessibility_gain,
		"clock_sec": _clock_sec,
		"requested_device_id": device_id,
		"device_id": resolved_device,
		"backend": String(_backend_or_default().backend_name),
		"capabilities": _backend_or_default().capabilities(resolved_device),
		"backend_diagnostic": _backend_or_default().diagnostic(resolved_device),
		"active_cues": active_cues,
		"last_output": {"left": _last_output.x, "right": _last_output.y},
		"pending_event_count": _events.size(),
	}


func drain_events() -> Array[Dictionary]:
	var result := _events.duplicate(true)
	_events.clear()
	return result


func get_clock_sec() -> float:
	return _clock_sec


func _sample(cue: Dictionary, local_time: float) -> Vector2:
	var result := Vector2.ZERO
	for segment_value in cue["segments"]:
		var segment: Dictionary = segment_value
		var start_sec := float(segment["start_sec"])
		var end_sec := start_sec + float(segment["duration_sec"])
		if local_time >= start_sec and local_time < end_sec:
			result.x = maxf(result.x, float(segment["left"]))
			result.y = maxf(result.y, float(segment["right"]))
	return result


func _resolved_device_id() -> int:
	if device_id >= 0:
		return device_id
	var connected := Input.get_connected_joypads()
	# Prefer a controller that can actually play the active backend's portable
	# output. This matters on desktops with multiple virtual/input-only devices.
	var backend: Variant = _backend_or_default()
	for connected_id in connected:
		if bool(backend.capabilities(int(connected_id)).get("available", false)):
			return int(connected_id)
	if not connected.is_empty():
		return int(connected[0])
	return -1


func _on_joy_connection_changed(changed_device_id: int, connected: bool) -> void:
	if connected:
		return
	# In auto-select mode SDL has already removed the disconnected ID by the
	# time this signal arrives, so conservatively stop on any disconnect.
	if device_id == changed_device_id or device_id < 0:
		stop_all("device_disconnected")


func _backend_or_default() -> Variant:
	if _backend == null:
		_backend = Backends.GodotRumbleBackend.new()
	return _backend


func _emit(event: Dictionary) -> Dictionary:
	var copy := event.duplicate(true)
	_events.append(copy)
	haptic_event.emit(copy)
	return copy
