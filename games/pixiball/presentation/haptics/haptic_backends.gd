class_name PixiballHapticBackends
extends RefCounted

## Hardware adapters for PixiballHapticDirector.
##
## The director speaks semantic player-left/player-right amplitudes. Godot's
## portable API exposes weak/high-frequency and strong/low-frequency channels.
## The fallback frequency-encodes direction with a small crossfeed. This fork's
## typed Input extension can additionally localize bounded pulses to L2 or R2 on
## an official DualSense/Edge; it does not expose arbitrary HID writes or claim
## support for audio-driven body haptics.
## RecordingBackend is the source of truth for headless tests.


class Backend extends RefCounted:
	var backend_name := "backend"

	func capabilities(_device_id: int) -> Dictionary:
		return {
			"backend": backend_name,
			"available": false,
			"rumble": false,
			"directional_mode": "none",
			"adaptive_triggers": false,
			"rich_localities": false,
		}

	func apply(
			_device_id: int,
			_left: float,
			_right: float,
			_duration_sec: float,
			_clock_sec: float,
			_cue_ids: Array,
		) -> Dictionary:
		return {"accepted": false, "backend": backend_name}

	func stop(_device_id: int, _clock_sec: float, _reason: String) -> Dictionary:
		return {"accepted": true, "backend": backend_name}

	func diagnostic(device_id: int) -> Dictionary:
		return {
			"backend": backend_name,
			"device_id": device_id,
			"capabilities": capabilities(device_id),
		}


class NullBackend extends Backend:
	func _init() -> void:
		backend_name = "null"

	func apply(
			_device_id: int,
			_left: float,
			_right: float,
			_duration_sec: float,
			_clock_sec: float,
			_cue_ids: Array,
		) -> Dictionary:
		return {"accepted": true, "backend": backend_name, "audible": false}


class RecordingBackend extends Backend:
	var entries: Array[Dictionary] = []
	var stop_count := 0
	var last_output := Vector2.ZERO # x = left, y = right.
	var capability_overrides: Dictionary = {}

	func _init(overrides := {}) -> void:
		backend_name = "recording"
		if overrides is Dictionary:
			capability_overrides = overrides.duplicate(true)

	func capabilities(_device_id: int) -> Dictionary:
		var result := {
			"backend": backend_name,
			"available": true,
			"rumble": true,
			"directional_mode": "recorded_left_right",
			"adaptive_triggers": false,
			"rich_localities": true,
		}
		result.merge(capability_overrides, true)
		return result

	func apply(
			device_id: int,
			left: float,
			right: float,
			duration_sec: float,
			clock_sec: float,
			cue_ids: Array,
		) -> Dictionary:
		last_output = Vector2(left, right)
		var entry := {
			"type": "output",
			"device_id": device_id,
			"left": left,
			"right": right,
			"duration_sec": duration_sec,
			"at_sec": clock_sec,
			"cue_ids": cue_ids.duplicate(),
		}
		entries.append(entry)
		return {"accepted": true, "backend": backend_name, "entry": entry}

	func stop(device_id: int, clock_sec: float, reason: String) -> Dictionary:
		last_output = Vector2.ZERO
		stop_count += 1
		var entry := {
			"type": "stop",
			"device_id": device_id,
			"left": 0.0,
			"right": 0.0,
			"at_sec": clock_sec,
			"reason": reason,
		}
		entries.append(entry)
		return {"accepted": true, "backend": backend_name, "entry": entry}

	func clear() -> void:
		entries.clear()
		stop_count = 0
		last_output = Vector2.ZERO

	func diagnostic(device_id: int) -> Dictionary:
		var result := super.diagnostic(device_id)
		result["entry_count"] = entries.size()
		result["stop_count"] = stop_count
		result["last_output"] = {"left": last_output.x, "right": last_output.y}
		return result


class GodotRumbleBackend extends Backend:
	const SONY_VENDOR_ID := 0x054C
	const DUALSENSE_PRODUCT_ID := 0x0CE6
	const DUALSENSE_EDGE_PRODUCT_ID := 0x0DF2
	const CHANNEL_CROSSFEED := 0.14
	const ADAPTIVE_DIRECTION_DEADZONE := 0.16
	const ADAPTIVE_TRIGGER_LEFT := 0
	const ADAPTIVE_TRIGGER_RIGHT := 1
	const ADAPTIVE_EFFECT_OFF := 0
	const ADAPTIVE_EFFECT_VIBRATION := 3

	var apply_count := 0
	var rejected_count := 0
	var stop_count := 0
	var last_device_id := -1
	var last_semantic := Vector2.ZERO # x = player-left, y = player-right.
	var last_rumble := Vector2.ZERO # x = weak/high-frequency, y = strong/low-frequency.
	var last_duration_sec := 0.0
	var last_cue_ids: Array = []
	var last_error := ""
	var adaptive_apply_count := 0
	var adaptive_failure_count := 0
	var adaptive_stop_count := 0
	var last_adaptive_side := -1
	var last_adaptive_signature := ""
	var last_adaptive_command: Dictionary = {"active": false}
	var last_advanced_error := ""

	func _init() -> void:
		backend_name = "godot_rumble"

	static func map_semantic_to_rumble(left: float, right: float) -> Dictionary:
		var safe_left := clampf(left, 0.0, 1.0)
		var safe_right := clampf(right, 0.0, 1.0)
		return {
			# Godot/SDL names the channels by motor frequency, not controller side.
			"weak": clampf(safe_right + safe_left * CHANNEL_CROSSFEED, 0.0, 1.0),
			"strong": clampf(safe_left + safe_right * CHANNEL_CROSSFEED, 0.0, 1.0),
		}

	static func map_semantic_to_adaptive(left: float, right: float) -> Dictionary:
		var safe_left := clampf(left, 0.0, 1.0)
		var safe_right := clampf(right, 0.0, 1.0)
		var total := safe_left + safe_right
		var peak := maxf(safe_left, safe_right)
		var pan := (safe_right - safe_left) / maxf(total, 0.0001)
		if peak <= 0.0 or absf(pan) < ADAPTIVE_DIRECTION_DEADZONE:
			return {
				"active": false,
				"side": -1,
				"pan": pan,
				"position": 0,
				"amplitude": 0,
				"frequency_hz": 0,
			}
		return {
			"active": true,
			"side": ADAPTIVE_TRIGGER_RIGHT if pan > 0.0 else ADAPTIVE_TRIGGER_LEFT,
			"pan": pan,
			# Stronger samples engage earlier in the pull and with greater amplitude.
			"position": clampi(int(round(lerpf(6.0, 2.0, peak))), 2, 6),
			"amplitude": clampi(int(round(lerpf(1.0, 8.0, peak))), 1, 8),
			"frequency_hz": clampi(int(round(lerpf(55.0, 145.0, peak))), 55, 145),
		}

	static func describe_controller(info: Dictionary, name: String) -> Dictionary:
		var vendor_id := _parse_usb_id(info.get("vendor_id", 0))
		var product_id := _parse_usb_id(info.get("product_id", 0))
		var normalized_name := name.to_lower()
		var sony_ids := vendor_id == SONY_VENDOR_ID
		var name_is_dualsense := "dualsense" in normalized_name or "ps5 controller" in normalized_name
		var edge := (
			(sony_ids and product_id == DUALSENSE_EDGE_PRODUCT_ID)
			or (name_is_dualsense and "edge" in normalized_name)
		)
		var dualsense := edge or (sony_ids and product_id == DUALSENSE_PRODUCT_ID) or name_is_dualsense
		return {
			"vendor_id": vendor_id,
			"product_id": product_id,
			"dualsense": dualsense,
			"dualsense_edge": edge,
		}

	static func _parse_usb_id(value: Variant) -> int:
		if value is String or value is StringName:
			var text := String(value).strip_edges().to_lower()
			if text.begins_with("0x"):
				return text.hex_to_int()
			return text.to_int()
		return int(value)

	func capabilities(device_id: int) -> Dictionary:
		var connected := device_id in Input.get_connected_joypads()
		var info: Dictionary = Input.get_joy_info(device_id) if connected else {}
		var name := Input.get_joy_name(device_id) if connected else ""
		var identity := describe_controller(info, name)
		var dualsense := bool(identity.dualsense)
		var rumble := connected and Input.has_joy_vibration(device_id)
		var adaptive := connected and _has_adaptive_api() and bool(Input.call("has_joy_adaptive_triggers", device_id))
		return {
			"backend": backend_name,
			"available": rumble or adaptive,
			"connected": connected,
			"rumble": rumble,
			"directional_mode": "adaptive_trigger_locality" if adaptive else "frequency_encoded_hint",
			"true_spatial_direction": adaptive,
			"spatial_scope": "left_right_triggers" if adaptive else "none",
			"adaptive_triggers": adaptive,
			"rich_localities": adaptive,
			"advanced_body_haptics": false,
			"dualsense": dualsense,
			"dualsense_edge": bool(identity.dualsense_edge),
			"advanced_backend_required": dualsense and not adaptive,
			"portable_channels": ["weak_high_frequency", "strong_low_frequency"],
			"name": name,
			"info": info,
		}

	func apply(
			device_id: int,
			left: float,
			right: float,
			duration_sec: float,
			_clock_sec: float,
			cue_ids: Array,
		) -> Dictionary:
		var caps := capabilities(device_id)
		if not bool(caps["available"]):
			rejected_count += 1
			last_error = "rumble_unavailable"
			return {"accepted": false, "backend": backend_name, "reason": "rumble_unavailable"}
		var safe_left := clampf(left, 0.0, 1.0)
		var safe_right := clampf(right, 0.0, 1.0)
		var safe_duration := clampf(duration_sec, 0.001, 1.0)
		var rumble := map_semantic_to_rumble(safe_left, safe_right)
		var adaptive_result := {
			"attempted": false,
			"accepted": false,
			"active": false,
		}
		last_device_id = device_id
		last_semantic = Vector2(safe_left, safe_right)
		last_rumble = Vector2(float(rumble.weak), float(rumble.strong))
		last_duration_sec = safe_duration
		last_cue_ids = cue_ids.duplicate()
		last_error = ""
		apply_count += 1
		if bool(caps.rumble):
			Input.start_joy_vibration(
				device_id,
				float(rumble.weak),
				float(rumble.strong),
				safe_duration,
			)
		if bool(caps.adaptive_triggers):
			adaptive_result = _apply_adaptive_direction(device_id, safe_left, safe_right)
		return {
			"accepted": true,
			"backend": backend_name,
			"left": safe_left,
			"right": safe_right,
			"weak": float(rumble.weak),
			"strong": float(rumble.strong),
			"duration_sec": safe_duration,
			"adaptive": adaptive_result,
		}

	func stop(device_id: int, _clock_sec: float, reason: String) -> Dictionary:
		if device_id in Input.get_connected_joypads():
			Input.stop_joy_vibration(device_id)
			_stop_adaptive(device_id)
		last_device_id = device_id
		last_semantic = Vector2.ZERO
		last_rumble = Vector2.ZERO
		last_duration_sec = 0.0
		last_cue_ids.clear()
		stop_count += 1
		return {"accepted": true, "backend": backend_name, "reason": reason}

	func diagnostic(device_id: int) -> Dictionary:
		var result := super.diagnostic(device_id)
		result["connected_joypads"] = Array(Input.get_connected_joypads())
		result["mapping"] = {
			"semantic_left": "strong_low_frequency_dominant",
			"semantic_right": "weak_high_frequency_dominant",
			"crossfeed": CHANNEL_CROSSFEED,
			"spatial_guarantee": "triggers_only_when_supported",
			"body_haptics_guarantee": false,
		}
		result["apply_count"] = apply_count
		result["rejected_count"] = rejected_count
		result["stop_count"] = stop_count
		result["last_device_id"] = last_device_id
		result["last_semantic"] = {"left": last_semantic.x, "right": last_semantic.y}
		result["last_rumble"] = {"weak": last_rumble.x, "strong": last_rumble.y}
		result["last_duration_sec"] = last_duration_sec
		result["last_cue_ids"] = last_cue_ids.duplicate()
		result["last_error"] = last_error
		result["adaptive_apply_count"] = adaptive_apply_count
		result["adaptive_failure_count"] = adaptive_failure_count
		result["adaptive_stop_count"] = adaptive_stop_count
		result["last_adaptive_command"] = last_adaptive_command.duplicate(true)
		result["last_advanced_error"] = last_advanced_error
		return result

	func _has_adaptive_api() -> bool:
		return (
			Input.has_method("has_joy_adaptive_triggers")
			and Input.has_method("set_joy_adaptive_trigger_effect")
			and Input.has_method("stop_joy_adaptive_triggers")
		)

	func _apply_adaptive_direction(device_id: int, left: float, right: float) -> Dictionary:
		var command := map_semantic_to_adaptive(left, right)
		last_adaptive_command = command.duplicate(true)
		if not bool(command.active):
			var stopped := _stop_adaptive(device_id)
			return {
				"attempted": bool(stopped.attempted),
				"accepted": bool(stopped.accepted),
				"active": false,
				"command": command,
			}

		var side := int(command.side)
		var signature := "%d:%d:%d:%d" % [
			side,
			int(command.position),
			int(command.amplitude),
			int(command.frequency_hz),
		]
		if signature == last_adaptive_signature:
			return {
				"attempted": false,
				"accepted": true,
				"active": true,
				"reused": true,
				"command": command,
			}

		if last_adaptive_side >= 0 and last_adaptive_side != side:
			Input.call(
				"set_joy_adaptive_trigger_effect",
				device_id,
				last_adaptive_side,
				ADAPTIVE_EFFECT_OFF,
				0,
				0,
				0,
				0,
			)

		var accepted := bool(Input.call(
			"set_joy_adaptive_trigger_effect",
			device_id,
			side,
			ADAPTIVE_EFFECT_VIBRATION,
			int(command.position),
			0,
			int(command.amplitude),
			int(command.frequency_hz),
		))
		if accepted:
			adaptive_apply_count += 1
			last_adaptive_side = side
			last_adaptive_signature = signature
			last_advanced_error = ""
		else:
			adaptive_failure_count += 1
			last_adaptive_side = -1
			last_adaptive_signature = ""
			last_advanced_error = "adaptive_trigger_send_failed"
		return {
			"attempted": true,
			"accepted": accepted,
			"active": accepted,
			"command": command,
		}

	func _stop_adaptive(device_id: int) -> Dictionary:
		if last_adaptive_side < 0 or not _has_adaptive_api():
			last_adaptive_side = -1
			last_adaptive_signature = ""
			return {"attempted": false, "accepted": true}
		var accepted := bool(Input.call("stop_joy_adaptive_triggers", device_id))
		adaptive_stop_count += 1
		if not accepted:
			adaptive_failure_count += 1
			last_advanced_error = "adaptive_trigger_stop_failed"
		else:
			last_advanced_error = ""
		last_adaptive_side = -1
		last_adaptive_signature = ""
		last_adaptive_command = {"active": false}
		return {"attempted": true, "accepted": accepted}
