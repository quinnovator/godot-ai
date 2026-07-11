extends Node

## Runtime-only, debugger-mediated probe for Godot AI.
##
## The probe deliberately exposes a small command surface. It never evaluates
## code, invokes caller-selected methods, loads resources, or accepts arbitrary
## filesystem paths.

const PROTOCOL_VERSION := 1
const ADDON_VERSION := "0.2.0"
const DEBUGGER_PREFIX := &"godot_ai"
const MESSAGE_HELLO := "godot_ai:hello"
const MESSAGE_RESPONSE := "godot_ai:response"
const GAMEPLAY_DRIVER_GROUP := &"godot_ai_gameplay_driver"
const GAMEPLAY_DESCRIBE_METHOD := &"_godot_ai_describe"
const GAMEPLAY_STATE_METHOD := &"_godot_ai_state"
const GAMEPLAY_APPLY_INTENT_METHOD := &"_godot_ai_apply_intent"

const DEFAULT_TREE_DEPTH := 8
const MAX_TREE_DEPTH := 32
const MAX_TREE_NODES := 4_096
const MAX_REQUESTED_PROPERTIES := 128
const MAX_RETURNED_PROPERTIES := 256
const MAX_PENDING_COMMANDS := 256
const MAX_COMMAND_BYTES := 1_048_576
const MAX_RESPONSE_BYTES := 2_097_152
const MAX_CONTAINER_ITEMS := 1_024
const MAX_VALUE_DEPTH := 8
const MAX_STRING_LENGTH := 16_384
const MAX_PHYSICS_FRAMES := 600
const MAX_RAY_EXCLUDES := 128
const MAX_NAVIGATION_POINTS := 4_096
const MAX_PATH_LENGTH := 1_024
const MAX_CAPTURE_PATH_LENGTH := 240
const MAX_CAPTURE_WAIT_PROCESS_FRAMES := 30
const MAX_CAPTURE_PIXELS := 33_554_432
const MAX_GAMEPLAY_INTENTS := 256
const MAX_GAMEPLAY_VALUE_BYTES := 1_048_576
const CAPTURE_DIRECTORY := "res://.godot/agent/captures"

signal _physics_advance_completed
signal _frame_post_draw_wait_completed

const CAPABILITIES := [
	"runtime.health",
	"scene.get_tree",
	"node.get_properties",
	"node.set_property",
	"input.action_press",
	"input.action_release",
	"gameplay.describe",
	"gameplay.state",
	"gameplay.intent",
	"time.set_paused",
	"time.advance_physics_frames",
	"viewport.capture",
	"physics.raycast",
	"navigation.map_path",
]

const BLOCKED_SET_PROPERTIES := {
	"owner": true,
	"scene_file_path": true,
	"script": true,
}

var _capture_registered := false
var _hello_sent := false
var _processing_commands := false
var _command_queue: Array[Dictionary] = []
var _inflight_ids: Dictionary = {}
var _completed_command_queue: Array[Dictionary] = []
var _snapshot_node_count := 0
var _snapshot_truncated := false
var _frame_post_draw_seen := false
var _frame_post_draw_waiting := false
var _frame_post_draw_wait_process_frames := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	if EngineDebugger.has_capture(DEBUGGER_PREFIX):
		push_error("Godot AI Runtime could not register the '%s' debugger capture because it is already in use." % DEBUGGER_PREFIX)
		return
	EngineDebugger.register_message_capture(DEBUGGER_PREFIX, _capture_debugger_message)
	_capture_registered = true
	_send_hello_if_possible()


func _exit_tree() -> void:
	if _capture_registered and EngineDebugger.has_capture(DEBUGGER_PREFIX):
		EngineDebugger.unregister_message_capture(DEBUGGER_PREFIX)
	_capture_registered = false


func _process(_delta: float) -> void:
	_publish_completed_commands()
	if _frame_post_draw_waiting:
		_frame_post_draw_wait_process_frames += 1
		if _frame_post_draw_seen or _frame_post_draw_wait_process_frames >= MAX_CAPTURE_WAIT_PROCESS_FRAMES:
			_frame_post_draw_waiting = false
			_frame_post_draw_wait_completed.emit()
	if not EngineDebugger.is_active():
		_hello_sent = false
		return
	_send_hello_if_possible()


func _publish_completed_commands() -> void:
	var process_frame := Engine.get_process_frames()
	while (
		not _completed_command_queue.is_empty()
		and int(_completed_command_queue[0]["ready_process_frame"]) <= process_frame
	):
		var completed: Dictionary = _completed_command_queue.pop_front()
		_send_response(completed["id"], completed["result"])
		_inflight_ids.erase(completed["id"])


func _send_hello_if_possible() -> void:
	if _hello_sent or not _capture_registered or not EngineDebugger.is_active():
		return
	var scene_root := get_tree().current_scene
	var hello := {
		"protocol_version": PROTOCOL_VERSION,
		"addon_version": ADDON_VERSION,
		"engine": Engine.get_version_info(),
		"project_name": str(ProjectSettings.get_setting("application/config/name", "")),
		"scene_path": scene_root.scene_file_path if scene_root != null else "",
		"capabilities": CAPABILITIES.duplicate(),
	}
	EngineDebugger.send_message(MESSAGE_HELLO, [hello])
	_hello_sent = true


func _capture_debugger_message(message: String, data: Array) -> bool:
	if message != "command":
		return false

	var envelope_error := _validate_command_envelope(data)
	if not envelope_error.is_empty():
		_send_response(envelope_error.get("id"), envelope_error["result"])
		return true

	var command: Dictionary = data[0].duplicate(true)
	var request_id: Variant = command["id"]
	if _inflight_ids.has(request_id):
		_send_response(request_id, _failure("duplicate_id", "A command with this id is already pending."))
		return true
	if _inflight_ids.size() >= MAX_PENDING_COMMANDS:
		_send_response(request_id, _failure("queue_full", "The runtime command queue is full.", {"maximum": MAX_PENDING_COMMANDS}))
		return true

	_inflight_ids[request_id] = true
	_command_queue.push_back(command)
	if not _processing_commands:
		_processing_commands = true
		call_deferred("_drain_command_queue")
	return true


func _validate_command_envelope(data: Array) -> Dictionary:
	if data.size() != 1 or typeof(data[0]) != TYPE_DICTIONARY:
		return {
			"id": null,
			"result": _failure("invalid_envelope", "Command data must contain exactly one Dictionary."),
		}

	var command: Dictionary = data[0]
	if not command.has("id"):
		return {"id": null, "result": _failure("missing_id", "The command must contain an id.")}
	var request_id: Variant = command["id"]
	if typeof(request_id) != TYPE_INT and typeof(request_id) != TYPE_STRING:
		return {"id": null, "result": _failure("invalid_id", "Command id must be an integer or string.")}
	if typeof(request_id) == TYPE_STRING and (request_id.is_empty() or request_id.length() > 128):
		return {"id": null, "result": _failure("invalid_id", "String command ids must contain 1 to 128 characters.")}
	var unknown := _unknown_keys(command, ["id", "method", "params", "protocol_version"])
	if not unknown.is_empty():
		return {
			"id": request_id,
			"result": _failure("unknown_field", "The command contains unsupported fields.", {"fields": unknown}),
		}
	if command.has("protocol_version") and (typeof(command["protocol_version"]) != TYPE_INT or command["protocol_version"] != PROTOCOL_VERSION):
		return {
			"id": request_id,
			"result": _failure(
				"protocol_mismatch",
				"Unsupported runtime protocol version.",
				{"expected": PROTOCOL_VERSION, "received_type": type_string(typeof(command["protocol_version"]))},
			),
		}
	if typeof(command.get("method")) != TYPE_STRING or not _is_method_name_valid(command["method"]):
		return {"id": request_id, "result": _failure("invalid_method", "Command method must be a valid non-empty method name.")}
	if not command.has("params"):
		return {"id": request_id, "result": _failure("missing_params", "The command must contain a params Dictionary.")}
	if typeof(command["params"]) != TYPE_DICTIONARY:
		return {"id": request_id, "result": _failure("invalid_params", "Command params must be a Dictionary.")}
	var command_size := _serialized_size(command)
	if command_size > MAX_COMMAND_BYTES:
		return {
			"id": request_id,
			"result": _failure(
				"request_too_large",
				"The serialized runtime command exceeds the request limit.",
				{"maximum_bytes": MAX_COMMAND_BYTES, "actual_bytes": command_size},
			),
		}
	return {}


func _drain_command_queue() -> void:
	while not _command_queue.is_empty():
		var command: Dictionary = _command_queue.pop_front()
		var request_id: Variant = command["id"]
		var result: Dictionary = await _execute_command(command)
		# Publish after two full process turns, once this async stack and its
		# caller states have unwound. The editor may stop the game immediately
		# after receiving a response.
		_completed_command_queue.push_back({
			"id": request_id,
			"result": result,
			"ready_process_frame": Engine.get_process_frames() + 2,
		})
	_processing_commands = false


func _execute_command(command: Dictionary) -> Dictionary:
	var method: String = command["method"]
	var params: Dictionary = command.get("params", {})
	match method:
		"runtime.health":
			return _command_runtime_health(params)
		"scene.get_tree":
			return _command_scene_get_tree(params)
		"node.get_properties":
			return _command_node_get_properties(params)
		"node.set_property":
			return _command_node_set_property(params)
		"input.action_press":
			return _command_input_action_press(params)
		"input.action_release":
			return _command_input_action_release(params)
		"gameplay.describe":
			return _command_gameplay_describe(params)
		"gameplay.state":
			return _command_gameplay_state(params)
		"gameplay.intent":
			return _command_gameplay_intent(params)
		"time.set_paused":
			return await _command_time_set_paused(params)
		"time.advance_physics_frames":
			return await _command_time_advance_physics_frames(params)
		"viewport.capture":
			return await _command_viewport_capture(params)
		"physics.raycast":
			return await _command_physics_raycast(params)
		"navigation.map_path":
			return _command_navigation_map_path(params)
		_:
			return _failure("method_not_found", "The runtime method is not supported.", {"method": method})


func _command_runtime_health(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(params, [])
	if not params_error.is_empty():
		return params_error
	var scene_root := get_tree().current_scene
	var viewport := get_viewport()
	return _success({
		"protocol_version": PROTOCOL_VERSION,
		"addon_version": ADDON_VERSION,
		"engine": Engine.get_version_info(),
		"debugger_active": EngineDebugger.is_active(),
		"paused": get_tree().paused,
		"physics_frames": Engine.get_physics_frames(),
		"process_frames": Engine.get_process_frames(),
		"scene_path": scene_root.scene_file_path if scene_root != null else "",
		"scene_root": str(scene_root.name) if scene_root != null else "",
		"viewport_size": viewport.get_visible_rect().size if viewport != null else Vector2.ZERO,
		"capabilities": CAPABILITIES.duplicate(),
	})


func _command_scene_get_tree(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(params, ["max_depth", "include_internal"])
	if not params_error.is_empty():
		return params_error
	var max_depth_result := _coerce_integer(params.get("max_depth", DEFAULT_TREE_DEPTH), 0, MAX_TREE_DEPTH, "max_depth")
	if not max_depth_result["ok"]:
		return max_depth_result
	var max_depth: int = max_depth_result["value"]
	var include_internal: Variant = params.get("include_internal", false)
	if typeof(include_internal) != TYPE_BOOL:
		return _failure("invalid_params", "include_internal must be a boolean.")

	var scene_root := get_tree().current_scene
	if scene_root == null:
		return _failure("no_scene", "There is no current runtime scene.")
	_snapshot_node_count = 0
	_snapshot_truncated = false
	var root_description := _describe_tree_node(scene_root, scene_root, 0, max_depth, include_internal)
	return _success({
		"scene_path": scene_root.scene_file_path,
		"root": root_description,
		"node_count": _snapshot_node_count,
		"truncated": _snapshot_truncated,
		"max_depth": max_depth,
	})


func _command_node_get_properties(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(params, ["node_path", "properties"])
	if not params_error.is_empty():
		return params_error
	var node_result := _resolve_required_node(params.get("node_path"))
	if not node_result["ok"]:
		return node_result
	var node: Node = node_result["node"]

	var requested_names: Array[String] = []
	if params.has("properties"):
		var requested: Variant = params["properties"]
		if typeof(requested) != TYPE_ARRAY and typeof(requested) != TYPE_PACKED_STRING_ARRAY:
			return _failure("invalid_params", "properties must be an Array of property names.")
		if requested.size() > MAX_REQUESTED_PROPERTIES:
			return _failure("limit_exceeded", "Too many properties were requested.", {"maximum": MAX_REQUESTED_PROPERTIES})
		var seen: Dictionary = {}
		for property_name in requested:
			if typeof(property_name) != TYPE_STRING and typeof(property_name) != TYPE_STRING_NAME:
				return _failure("invalid_params", "Every requested property name must be a String.")
			var normalized_name := str(property_name)
			if not _is_property_name_valid(normalized_name):
				return _failure("invalid_property", "A requested property name is invalid.", {"property": _bounded_string(normalized_name, 128)})
			if not seen.has(normalized_name):
				seen[normalized_name] = true
				requested_names.push_back(normalized_name)

	var property_infos: Dictionary = {}
	for info in node.get_property_list():
		var property_name := str(info.get("name", ""))
		if not property_infos.has(property_name):
			property_infos[property_name] = info

	var output: Dictionary = {}
	if not requested_names.is_empty():
		for property_name in requested_names:
			if not property_infos.has(property_name):
				return _failure("property_not_found", "The node does not expose the requested property.", {"property": property_name})
			var info: Dictionary = property_infos[property_name]
			if _is_property_hidden(info):
				return _failure("property_unavailable", "The requested property is internal or secret.", {"property": property_name})
			output[property_name] = _describe_property(node, info)
	else:
		for property_name in property_infos:
			if output.size() >= MAX_RETURNED_PROPERTIES:
				break
			var info: Dictionary = property_infos[property_name]
			if not _is_property_name_valid(property_name) or _is_property_hidden(info) or not _is_property_inspectable(info):
				continue
			output[property_name] = _describe_property(node, info)

	return _success({
		"node_path": _relative_node_path(node),
		"type": node.get_class(),
		"properties": output,
		"truncated": requested_names.is_empty() and output.size() >= MAX_RETURNED_PROPERTIES,
	})


func _command_node_set_property(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(params, ["node_path", "property", "value"], ["node_path", "property", "value"])
	if not params_error.is_empty():
		return params_error
	var node_result := _resolve_required_node(params["node_path"])
	if not node_result["ok"]:
		return node_result
	var node: Node = node_result["node"]
	if typeof(params["property"]) != TYPE_STRING and typeof(params["property"]) != TYPE_STRING_NAME:
		return _failure("invalid_property", "property must be a String.")
	var property_name := str(params["property"])
	if not _is_property_name_valid(property_name):
		return _failure("invalid_property", "The property name is invalid.", {"property": _bounded_string(property_name, 128)})
	if BLOCKED_SET_PROPERTIES.has(property_name):
		return _failure("property_blocked", "This property cannot be changed through the runtime probe.", {"property": property_name})

	var property_info: Dictionary = {}
	for info in node.get_property_list():
		if str(info.get("name", "")) == property_name:
			property_info = info
			break
	if property_info.is_empty():
		return _failure("property_not_found", "The node does not expose this property.", {"property": property_name})
	if _is_property_hidden(property_info) or not _is_property_inspectable(property_info):
		return _failure("property_unavailable", "The property is not part of the editable runtime property surface.", {"property": property_name})
	var usage := int(property_info.get("usage", 0))
	if (usage & PROPERTY_USAGE_READ_ONLY) != 0:
		return _failure("property_read_only", "The property is read-only.", {"property": property_name})

	var value_result := _coerce_property_value(params["value"], property_info)
	if not value_result["ok"]:
		return value_result
	var value: Variant = value_result["value"]
	if not _is_safe_mutation_value(value):
		return _failure("unsafe_value", "The property value contains an unsupported or oversized value.")

	node.set(property_name, value)
	return _success({
		"node_path": _relative_node_path(node),
		"property": property_name,
		"value": _encode_value(node.get(property_name)),
	})


func _command_input_action_press(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(params, ["action", "strength"], ["action"])
	if not params_error.is_empty():
		return params_error
	var action_result := _validate_input_action(params["action"])
	if not action_result["ok"]:
		return action_result
	var strength: Variant = params.get("strength", 1.0)
	if (typeof(strength) != TYPE_FLOAT and typeof(strength) != TYPE_INT) or not is_finite(float(strength)) or strength < 0.0 or strength > 1.0:
		return _failure("invalid_params", "strength must be a finite number from 0.0 to 1.0.")
	var action: StringName = action_result["action"]
	Input.action_press(action, float(strength))
	return _success({"action": str(action), "pressed": true, "strength": float(strength)})


func _command_input_action_release(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(params, ["action"], ["action"])
	if not params_error.is_empty():
		return params_error
	var action_result := _validate_input_action(params["action"])
	if not action_result["ok"]:
		return action_result
	var action: StringName = action_result["action"]
	Input.action_release(action)
	return _success({"action": str(action), "pressed": false})


func _command_gameplay_describe(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(params, [])
	if not params_error.is_empty():
		return params_error
	var driver_result := _resolve_gameplay_driver()
	if not driver_result["ok"]:
		return driver_result
	var driver: Node = driver_result["driver"]
	var driver_path := _gameplay_driver_path(driver)
	var description_result := _read_gameplay_description(driver)
	if not description_result["ok"]:
		return description_result
	return _success({
		"driver_path": driver_path,
		"description": _encode_value(description_result["description"]),
	})


func _command_gameplay_state(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(params, [])
	if not params_error.is_empty():
		return params_error
	var driver_result := _resolve_gameplay_driver()
	if not driver_result["ok"]:
		return driver_result
	var driver: Node = driver_result["driver"]
	var driver_path := _gameplay_driver_path(driver)
	var state: Variant = driver.call(GAMEPLAY_STATE_METHOD)
	var state_error := _validate_gameplay_callback_value(state, "state")
	if not state_error.is_empty():
		return state_error
	return _success({
		"driver_path": driver_path,
		"state": _encode_value(state),
	})


func _command_gameplay_intent(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(params, ["name", "params"], ["name"])
	if not params_error.is_empty():
		return params_error
	if typeof(params["name"]) != TYPE_STRING and typeof(params["name"]) != TYPE_STRING_NAME:
		return _failure("invalid_intent", "name must be a String.")
	var intent_name := str(params["name"])
	if not _is_method_name_valid(intent_name):
		return _failure("invalid_intent", "The intent name is invalid.", {"name": _bounded_string(intent_name, 128)})
	var intent_params: Variant = params.get("params", {})
	if typeof(intent_params) != TYPE_DICTIONARY:
		return _failure("invalid_params", "params must be a Dictionary.")
	var intent_params_error := _validate_gameplay_value(intent_params, "intent parameters")
	if not intent_params_error.is_empty():
		return intent_params_error

	var driver_result := _resolve_gameplay_driver()
	if not driver_result["ok"]:
		return driver_result
	var driver: Node = driver_result["driver"]
	var driver_path := _gameplay_driver_path(driver)
	var description_result := _read_gameplay_description(driver)
	if not description_result["ok"]:
		return description_result
	var declared_intents: Dictionary = description_result["declared_intents"]
	if not declared_intents.has(intent_name):
		return _failure(
			"intent_not_declared",
			"The gameplay driver did not declare this intent.",
			{"name": intent_name},
		)
	if not is_instance_valid(driver) or not driver.is_inside_tree():
		return _failure(
			"gameplay_driver_unavailable",
			"The gameplay driver left the runtime tree before the intent could be applied.",
		)

	var intent_result: Variant = driver.call(GAMEPLAY_APPLY_INTENT_METHOD, intent_name, intent_params)
	var result_error := _validate_gameplay_callback_value(intent_result, "intent result")
	if not result_error.is_empty():
		return result_error
	return _success({
		"driver_path": driver_path,
		"name": intent_name,
		"result": _encode_value(intent_result),
	})


func _command_time_set_paused(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(params, ["paused"], ["paused"])
	if not params_error.is_empty():
		return params_error
	if typeof(params["paused"]) != TYPE_BOOL:
		return _failure("invalid_params", "paused must be a boolean.")
	var previous := get_tree().paused
	var requested: bool = params["paused"]
	if previous != requested:
		# Debugger messages can be dispatched from a mid-physics message-queue
		# flush. Reactivating the physics server there skips that tick's query
		# flush and can enqueue a rigid-body state callback twice. Process-frame
		# callbacks run after the full physics loop, so the next tick always gets
		# a clean sync/flush boundary before stepping.
		await get_tree().process_frame
		get_tree().paused = requested
	return _success({"previous": previous, "paused": get_tree().paused})


func _command_time_advance_physics_frames(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(params, ["frames"], ["frames"])
	if not params_error.is_empty():
		return params_error
	var frames_result := _coerce_integer(params["frames"], 1, MAX_PHYSICS_FRAMES, "frames")
	if not frames_result["ok"]:
		return frames_result
	var frames: int = frames_result["value"]

	var was_paused := get_tree().paused
	if not get_tree().has_signal("physics_frame_finished"):
		return _failure(
			"engine_capability_missing",
			"This engine does not expose the post-server physics_frame_finished signal required for exact stepping.",
		)
	# Re-awaiting the same synchronous signal from inside its callback can leave
	# nested GDScript function states behind. One persistent callback counts the
	# boundaries, while this command awaits a private completion signal once.
	var tree := get_tree()
	var advance_state := {
		"phase": 0,
		"remaining": frames,
		"start_frame": 0,
		"end_frame": 0,
	}
	var on_physics_finished := func() -> void:
		match int(advance_state["phase"]):
			0:
				# A debugger command can arrive partway through a physics tick. The
				# first boundary only aligns the counter before unpausing.
				advance_state["start_frame"] = Engine.get_physics_frames()
				advance_state["phase"] = 1
				tree.paused = false
			1:
				advance_state["remaining"] = int(advance_state["remaining"]) - 1
				if int(advance_state["remaining"]) == 0:
					advance_state["end_frame"] = Engine.get_physics_frames()
					advance_state["phase"] = 2
					# Keep the physics server paused for one sync boundary so Node3D
					# observations include the final requested step.
					tree.paused = true
			2:
				_physics_advance_completed.emit()

	tree.physics_frame_finished.connect(on_physics_finished)
	await _physics_advance_completed
	tree.physics_frame_finished.disconnect(on_physics_finished)
	tree.paused = was_paused
	return _success({
		"frames": frames,
		"start_physics_frame": advance_state["start_frame"],
		"end_physics_frame": advance_state["end_frame"],
		"paused": get_tree().paused,
	})


func _command_viewport_capture(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(params, ["path", "viewport_path"])
	if not params_error.is_empty():
		return params_error
	var capture_path: Variant = params.get("path", _default_capture_path())
	if typeof(capture_path) != TYPE_STRING or not _is_capture_path_valid(capture_path):
		return _failure(
			"invalid_path",
			"Capture path must be a PNG directly inside %s." % CAPTURE_DIRECTORY,
			{"directory": CAPTURE_DIRECTORY},
		)

	var viewport: Viewport = get_viewport()
	var viewport_path := ""
	if params.has("viewport_path"):
		var viewport_result := _resolve_required_node(params["viewport_path"])
		if not viewport_result["ok"]:
			return viewport_result
		if not viewport_result["node"] is Viewport:
			return _failure("invalid_viewport", "viewport_path must resolve to a Viewport node.")
		viewport = viewport_result["node"]
		viewport_path = _relative_node_path(viewport)
	if viewport == null:
		return _failure("no_viewport", "No runtime viewport is available.")
	var viewport_size := viewport.get_visible_rect().size
	var viewport_pixels := int(ceil(viewport_size.x)) * int(ceil(viewport_size.y))
	if viewport_size.x <= 0.0 or viewport_size.y <= 0.0 or viewport_pixels > MAX_CAPTURE_PIXELS:
		return _failure(
			"capture_size_unsupported",
			"The viewport dimensions are empty or exceed the runtime capture pixel limit.",
			{"size": viewport_size, "maximum_pixels": MAX_CAPTURE_PIXELS},
		)

	if _capture_path_contains_symlink(capture_path):
		return _failure(
			"invalid_path",
			"Capture paths cannot traverse symbolic links below the project root.",
			{"directory": CAPTURE_DIRECTORY},
		)
	var directory_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIRECTORY))
	if directory_error != OK:
		return _failure("capture_failed", "The capture directory could not be created.", {"error": error_string(directory_error)})
	# Check again after creation so a replaced directory is never trusted.
	if _capture_path_contains_symlink(capture_path):
		return _failure(
			"invalid_path",
			"Capture paths cannot traverse symbolic links below the project root.",
			{"directory": CAPTURE_DIRECTORY},
		)
	_frame_post_draw_seen = false
	_frame_post_draw_wait_process_frames = 0
	_frame_post_draw_waiting = true
	var frame_post_draw_callback := Callable(self, "_mark_frame_post_draw")
	RenderingServer.frame_post_draw.connect(frame_post_draw_callback, CONNECT_ONE_SHOT)
	await _frame_post_draw_wait_completed
	if RenderingServer.frame_post_draw.is_connected(frame_post_draw_callback):
		RenderingServer.frame_post_draw.disconnect(frame_post_draw_callback)
	if not _frame_post_draw_seen:
		return _failure(
			"capture_unavailable",
			"The rendering backend did not complete a frame; viewport capture may be unavailable in headless or disabled-render-loop runs.",
		)
	if not is_instance_valid(viewport):
		return _failure("viewport_freed", "The selected viewport was freed before capture completed.")
	var image := viewport.get_texture().get_image()
	if image == null or image.is_empty():
		return _failure("capture_failed", "The viewport did not produce an image.")
	if image.get_width() * image.get_height() > MAX_CAPTURE_PIXELS:
		return _failure("capture_size_unsupported", "The rendered image exceeds the runtime capture pixel limit.", {"maximum_pixels": MAX_CAPTURE_PIXELS})
	var save_error := image.save_png(ProjectSettings.globalize_path(capture_path))
	if save_error != OK:
		return _failure("capture_failed", "The viewport PNG could not be saved.", {"error": error_string(save_error)})
	return _success({
		"path": capture_path,
		"viewport_path": viewport_path,
		"width": image.get_width(),
		"height": image.get_height(),
	})


func _mark_frame_post_draw() -> void:
	_frame_post_draw_seen = true


func _command_physics_raycast(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(
		params,
		["from", "to", "collision_mask", "exclude", "collide_with_areas", "collide_with_bodies"],
		["from", "to"],
	)
	if not params_error.is_empty():
		return params_error
	if typeof(params["from"]) != TYPE_VECTOR3 or not params["from"].is_finite():
		return _failure("invalid_params", "from must be a finite Vector3.")
	if typeof(params["to"]) != TYPE_VECTOR3 or not params["to"].is_finite():
		return _failure("invalid_params", "to must be a finite Vector3.")
	if params["from"].is_equal_approx(params["to"]):
		return _failure("invalid_params", "from and to must describe a non-zero ray.")
	var collision_mask_result := _coerce_integer(params.get("collision_mask", 0xffffffff), 0, 0xffffffff, "collision_mask")
	if not collision_mask_result["ok"]:
		return collision_mask_result
	var collision_mask: int = collision_mask_result["value"]
	var collide_with_areas: Variant = params.get("collide_with_areas", false)
	var collide_with_bodies: Variant = params.get("collide_with_bodies", true)
	if typeof(collide_with_areas) != TYPE_BOOL or typeof(collide_with_bodies) != TYPE_BOOL:
		return _failure("invalid_params", "collide_with_areas and collide_with_bodies must be booleans.")

	var exclude_rids: Array[RID] = []
	if params.has("exclude"):
		var exclude: Variant = params["exclude"]
		if typeof(exclude) != TYPE_ARRAY and typeof(exclude) != TYPE_PACKED_STRING_ARRAY:
			return _failure("invalid_params", "exclude must be an Array of relative CollisionObject3D node paths.")
		if exclude.size() > MAX_RAY_EXCLUDES:
			return _failure("limit_exceeded", "Too many raycast exclusions were supplied.", {"maximum": MAX_RAY_EXCLUDES})
		for excluded_path in exclude:
			var excluded_result := _resolve_required_node(excluded_path)
			if not excluded_result["ok"]:
				return excluded_result
			if not excluded_result["node"] is CollisionObject3D:
				return _failure("invalid_exclude", "Every excluded node must be a CollisionObject3D.", {"node_path": _bounded_string(str(excluded_path), 256)})
			exclude_rids.push_back(excluded_result["node"].get_rid())

	var viewport := get_viewport()
	if viewport == null or viewport.world_3d == null:
		return _failure("no_world_3d", "The runtime viewport has no World3D.")
	# Direct physics state is guaranteed available while resuming this coroutine
	# from SceneTree.physics_frame, including with threaded physics enabled.
	await get_tree().physics_frame
	var query := PhysicsRayQueryParameters3D.create(params["from"], params["to"], collision_mask, exclude_rids)
	query.collide_with_areas = collide_with_areas
	query.collide_with_bodies = collide_with_bodies
	var hit := viewport.world_3d.direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return _success({"hit": false})
	var collider: Variant = hit.get("collider")
	var collider_path := ""
	var collider_type := ""
	if collider is Node and _is_node_in_current_scene(collider):
		collider_path = _relative_node_path(collider)
		collider_type = collider.get_class()
	return _success({
		"hit": true,
		"position": hit.get("position", Vector3.ZERO),
		"normal": hit.get("normal", Vector3.ZERO),
		"face_index": int(hit.get("face_index", -1)),
		"shape": int(hit.get("shape", -1)),
		"collider_id": int(hit.get("collider_id", 0)),
		"collider_path": collider_path,
		"collider_type": collider_type,
	})


func _command_navigation_map_path(params: Dictionary) -> Dictionary:
	var params_error := _validate_params(params, ["origin", "target", "optimize", "navigation_layers"], ["origin", "target"])
	if not params_error.is_empty():
		return params_error
	if typeof(params["origin"]) != TYPE_VECTOR3 or not params["origin"].is_finite():
		return _failure("invalid_params", "origin must be a finite Vector3.")
	if typeof(params["target"]) != TYPE_VECTOR3 or not params["target"].is_finite():
		return _failure("invalid_params", "target must be a finite Vector3.")
	var optimize: Variant = params.get("optimize", true)
	if typeof(optimize) != TYPE_BOOL:
		return _failure("invalid_params", "optimize must be a boolean.")
	var navigation_layers_result := _coerce_integer(params.get("navigation_layers", 1), 1, 0xffffffff, "navigation_layers")
	if not navigation_layers_result["ok"]:
		return navigation_layers_result
	var navigation_layers: int = navigation_layers_result["value"]
	var viewport := get_viewport()
	if viewport == null or viewport.world_3d == null:
		return _failure("no_world_3d", "The runtime viewport has no World3D.")
	var navigation_map := viewport.world_3d.navigation_map
	if not navigation_map.is_valid():
		return _failure("no_navigation_map", "The current World3D has no navigation map.")
	var points := NavigationServer3D.map_get_path(navigation_map, params["origin"], params["target"], optimize, navigation_layers)
	var truncated := points.size() > MAX_NAVIGATION_POINTS
	if truncated:
		points = points.slice(0, MAX_NAVIGATION_POINTS)
	return _success({
		"points": points,
		"point_count": points.size(),
		"truncated": truncated,
	})


func _describe_tree_node(node: Node, scene_root: Node, depth: int, max_depth: int, include_internal: bool) -> Dictionary:
	_snapshot_node_count += 1
	var description := {
		"path": "." if node == scene_root else str(scene_root.get_path_to(node)),
		"name": str(node.name),
		"type": node.get_class(),
		"instance_id": node.get_instance_id(),
		"process_mode": node.process_mode,
		"groups": _bounded_groups(node.get_groups()),
	}

	if node is Node3D:
		var node_3d := node as Node3D
		description["transform"] = node_3d.transform
		description["global_transform"] = node_3d.global_transform
		description["visible"] = node_3d.visible
		description["visible_in_tree"] = node_3d.is_visible_in_tree()
	elif node is CanvasItem:
		var canvas_item := node as CanvasItem
		description["transform"] = canvas_item.get_transform()
		description["global_transform"] = canvas_item.get_global_transform()
		description["visible"] = canvas_item.visible
		description["visible_in_tree"] = canvas_item.is_visible_in_tree()

	if node is VisualInstance3D:
		var visual_instance := node as VisualInstance3D
		var local_aabb := visual_instance.get_aabb()
		description["aabb"] = local_aabb
		description["global_aabb"] = visual_instance.global_transform * local_aabb
	if node is Control:
		var control := node as Control
		description["rect"] = Rect2(control.global_position, control.size)
	if node is Skeleton3D:
		description["bone_count"] = (node as Skeleton3D).get_bone_count()

	var children := node.get_children(include_internal)
	description["child_count"] = children.size()
	var child_descriptions: Array[Dictionary] = []
	if depth < max_depth:
		for child in children:
			if _snapshot_node_count >= MAX_TREE_NODES:
				_snapshot_truncated = true
				break
			child_descriptions.push_back(_describe_tree_node(child, scene_root, depth + 1, max_depth, include_internal))
	elif not children.is_empty():
		description["children_truncated"] = true
		_snapshot_truncated = true
	description["children"] = child_descriptions
	return description


func _describe_property(node: Node, info: Dictionary) -> Dictionary:
	var property_name := str(info.get("name", ""))
	var usage := int(info.get("usage", 0))
	return {
		"type": type_string(int(info.get("type", TYPE_NIL))),
		"hint": int(info.get("hint", PROPERTY_HINT_NONE)),
		"hint_string": _bounded_string(str(info.get("hint_string", ""))),
		"usage": usage,
		"read_only": (usage & PROPERTY_USAGE_READ_ONLY) != 0,
		"value": _encode_value(node.get(property_name)),
	}


func _encode_value(value: Variant, depth: int = 0) -> Variant:
	if depth >= MAX_VALUE_DEPTH:
		return {"@type": type_string(typeof(value)), "truncated": true}
	var value_type := typeof(value)
	match value_type:
		TYPE_STRING, TYPE_STRING_NAME:
			var string_value := str(value)
			if string_value.length() <= MAX_STRING_LENGTH:
				return value
			return {
				"@type": type_string(value_type),
				"length": string_value.length(),
				"preview": string_value.substr(0, MAX_STRING_LENGTH),
				"truncated": true,
			}
		TYPE_ARRAY:
			var encoded_array: Array = []
			var array_limit: int = mini(value.size(), MAX_CONTAINER_ITEMS)
			for index in range(array_limit):
				encoded_array.push_back(_encode_value(value[index], depth + 1))
			if value.size() > array_limit:
				encoded_array.push_back({"@truncated": value.size() - array_limit})
			return encoded_array
		TYPE_DICTIONARY:
			var encoded_dictionary: Dictionary = {}
			var dictionary_count := 0
			for key in value:
				if dictionary_count >= MAX_CONTAINER_ITEMS:
					encoded_dictionary["@truncated"] = value.size() - dictionary_count
					break
				var encoded_key: Variant = key
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME and typeof(key) != TYPE_INT:
					encoded_key = str(key)
				encoded_dictionary[encoded_key] = _encode_value(value[key], depth + 1)
				dictionary_count += 1
			return encoded_dictionary
		TYPE_OBJECT:
			if value == null:
				return null
			var object_value: Object = value
			var object_description := {
				"@type": "Object",
				"class": object_value.get_class(),
				"instance_id": object_value.get_instance_id(),
			}
			if object_value is Resource:
				object_description["resource_path"] = (object_value as Resource).resource_path
			if object_value is Node and _is_node_in_current_scene(object_value):
				object_description["node_path"] = _relative_node_path(object_value)
			return object_description
		TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return {"@type": type_string(value_type), "opaque": true}
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_STRING_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			if value.size() <= MAX_CONTAINER_ITEMS:
				return value
			return {"@type": type_string(value_type), "size": value.size(), "truncated": true}
		_:
			return value


func _coerce_property_value(value: Variant, info: Dictionary) -> Dictionary:
	var expected_type := int(info.get("type", TYPE_NIL))
	var received_type := typeof(value)
	if expected_type == TYPE_NIL and (int(info.get("usage", 0)) & PROPERTY_USAGE_NIL_IS_VARIANT) != 0:
		return {"ok": true, "value": value}
	if expected_type == received_type:
		return {"ok": true, "value": value}
	if expected_type == TYPE_FLOAT and received_type == TYPE_INT:
		return {"ok": true, "value": float(value)}
	if expected_type == TYPE_INT and received_type == TYPE_FLOAT and is_finite(value) and value == floor(value):
		return {"ok": true, "value": int(value)}
	if expected_type == TYPE_STRING and received_type == TYPE_STRING_NAME:
		return {"ok": true, "value": str(value)}
	if expected_type == TYPE_STRING_NAME and received_type == TYPE_STRING:
		return {"ok": true, "value": StringName(value)}
	if expected_type == TYPE_NODE_PATH and received_type == TYPE_STRING and _is_node_path_valid(value):
		return {"ok": true, "value": NodePath(value)}
	return _failure(
		"type_mismatch",
		"The value type does not match the property type.",
		{"expected": type_string(expected_type), "received": type_string(received_type)},
	)


func _is_safe_mutation_value(value: Variant, depth: int = 0) -> bool:
	if depth >= MAX_VALUE_DEPTH:
		return false
	var value_type := typeof(value)
	match value_type:
		TYPE_OBJECT, TYPE_CALLABLE, TYPE_SIGNAL, TYPE_RID:
			return false
		TYPE_STRING, TYPE_STRING_NAME:
			return str(value).length() <= MAX_STRING_LENGTH
		TYPE_FLOAT:
			return is_finite(value)
		TYPE_VECTOR2:
			return value.is_finite()
		TYPE_VECTOR3:
			return value.is_finite()
		TYPE_VECTOR4:
			return value.is_finite()
		TYPE_QUATERNION:
			return value.is_finite()
		TYPE_TRANSFORM2D:
			return value.is_finite()
		TYPE_TRANSFORM3D:
			return value.is_finite()
		TYPE_RECT2:
			return value.is_finite()
		TYPE_PLANE:
			return value.is_finite()
		TYPE_AABB:
			return value.is_finite()
		TYPE_BASIS:
			return value.is_finite()
		TYPE_PROJECTION:
			return value.x.is_finite() and value.y.is_finite() and value.z.is_finite() and value.w.is_finite()
		TYPE_COLOR:
			return is_finite(value.r) and is_finite(value.g) and is_finite(value.b) and is_finite(value.a)
		TYPE_ARRAY:
			if value.size() > MAX_CONTAINER_ITEMS:
				return false
			for item in value:
				if not _is_safe_mutation_value(item, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			if value.size() > MAX_CONTAINER_ITEMS:
				return false
			for key in value:
				if not _is_safe_mutation_value(key, depth + 1) or not _is_safe_mutation_value(value[key], depth + 1):
					return false
			return true
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY:
			return value.size() <= MAX_CONTAINER_ITEMS
		TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
			if value.size() > MAX_CONTAINER_ITEMS:
				return false
			for item in value:
				if not is_finite(item):
					return false
			return true
		TYPE_PACKED_STRING_ARRAY:
			if value.size() > MAX_CONTAINER_ITEMS:
				return false
			for item in value:
				if item.length() > MAX_STRING_LENGTH:
					return false
			return true
		TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			if value.size() > MAX_CONTAINER_ITEMS:
				return false
			for item in value:
				if not item.is_finite():
					return false
			return true
		TYPE_PACKED_COLOR_ARRAY:
			if value.size() > MAX_CONTAINER_ITEMS:
				return false
			for item in value:
				if not is_finite(item.r) or not is_finite(item.g) or not is_finite(item.b) or not is_finite(item.a):
					return false
			return true
		_:
			return true


func _resolve_gameplay_driver() -> Dictionary:
	var drivers: Array[Node] = []
	for candidate in get_tree().get_nodes_in_group(GAMEPLAY_DRIVER_GROUP):
		if candidate is Node and is_instance_valid(candidate) and candidate.is_inside_tree():
			drivers.push_back(candidate)
	if drivers.is_empty():
		return _failure(
			"gameplay_driver_not_found",
			"No runtime node opted in to the gameplay driver contract.",
			{"group": str(GAMEPLAY_DRIVER_GROUP)},
		)
	if drivers.size() > 1:
		return _failure(
			"gameplay_driver_ambiguous",
			"Exactly one runtime node may opt in to the gameplay driver contract.",
			{"group": str(GAMEPLAY_DRIVER_GROUP), "count": drivers.size()},
		)

	var driver := drivers[0]
	var invalid_callbacks: Array[String] = []
	var callbacks := {
		GAMEPLAY_DESCRIBE_METHOD: 0,
		GAMEPLAY_STATE_METHOD: 0,
		GAMEPLAY_APPLY_INTENT_METHOD: 2,
	}
	for callback in callbacks:
		if not driver.has_method(callback) or driver.get_method_argument_count(callback) != callbacks[callback]:
			invalid_callbacks.push_back(str(callback))
	if not invalid_callbacks.is_empty():
		return _failure(
			"gameplay_driver_invalid",
			"The gameplay driver does not implement the fixed callback contract.",
			{"callbacks": invalid_callbacks},
		)
	return {"ok": true, "driver": driver}


func _read_gameplay_description(driver: Node) -> Dictionary:
	var description: Variant = driver.call(GAMEPLAY_DESCRIBE_METHOD)
	var description_error := _validate_gameplay_callback_value(description, "description")
	if not description_error.is_empty():
		return description_error
	if not description.has("intents") or typeof(description["intents"]) != TYPE_DICTIONARY:
		return _failure(
			"gameplay_driver_invalid_description",
			"The gameplay description must contain an intents Dictionary.",
		)
	var intents: Dictionary = description["intents"]
	if intents.size() > MAX_GAMEPLAY_INTENTS:
		return _failure(
			"gameplay_driver_limit_exceeded",
			"The gameplay driver declared too many intents.",
			{"maximum": MAX_GAMEPLAY_INTENTS, "actual": intents.size()},
		)

	var declared_intents: Dictionary = {}
	for raw_name in intents:
		if typeof(raw_name) != TYPE_STRING and typeof(raw_name) != TYPE_STRING_NAME:
			return _failure(
				"gameplay_driver_invalid_description",
				"Every declared intent name must be a String.",
			)
		var intent_name := str(raw_name)
		if not _is_method_name_valid(intent_name):
			return _failure(
				"gameplay_driver_invalid_description",
				"A declared intent name is invalid.",
				{"name": _bounded_string(intent_name, 128)},
			)
		if declared_intents.has(intent_name):
			return _failure(
				"gameplay_driver_invalid_description",
				"Declared intent names must be unique after normalization.",
				{"name": intent_name},
			)
		if typeof(intents[raw_name]) != TYPE_DICTIONARY:
			return _failure(
				"gameplay_driver_invalid_description",
				"Every declared intent descriptor must be a Dictionary.",
				{"name": intent_name},
			)
		declared_intents[intent_name] = intents[raw_name]

	var normalized_description: Dictionary = description.duplicate(true)
	normalized_description["intents"] = declared_intents
	return {
		"ok": true,
		"description": normalized_description,
		"declared_intents": declared_intents,
	}


func _validate_gameplay_callback_value(value: Variant, label: String) -> Dictionary:
	if typeof(value) != TYPE_DICTIONARY:
		return _failure(
			"gameplay_driver_invalid_response",
			"The gameplay driver %s must be a Dictionary." % label,
			{"received": type_string(typeof(value))},
		)
	return _validate_gameplay_value(value, "gameplay driver %s" % label)


func _validate_gameplay_value(value: Variant, label: String) -> Dictionary:
	if not _is_safe_gameplay_value(value):
		return _failure(
			"unsafe_gameplay_value",
			"The %s contains an unsupported, non-finite, or oversized value." % label,
		)
	var value_size := _serialized_size(value)
	if value_size > MAX_GAMEPLAY_VALUE_BYTES:
		return _failure(
			"gameplay_value_too_large",
			"The serialized %s exceeds the gameplay value limit." % label,
			{"maximum_bytes": MAX_GAMEPLAY_VALUE_BYTES, "actual_bytes": value_size},
		)
	return {}


func _is_safe_gameplay_value(value: Variant) -> bool:
	var budget := {"items": 0, "string_bytes": 0}
	return _is_safe_gameplay_value_recursive(value, 0, budget)


func _is_safe_gameplay_value_recursive(value: Variant, depth: int, budget: Dictionary) -> bool:
	if depth >= MAX_VALUE_DEPTH:
		return false
	match typeof(value):
		TYPE_STRING, TYPE_STRING_NAME:
			var string_value := str(value)
			if string_value.length() > MAX_STRING_LENGTH:
				return false
			budget["string_bytes"] = int(budget["string_bytes"]) + string_value.to_utf8_buffer().size()
			return int(budget["string_bytes"]) <= MAX_GAMEPLAY_VALUE_BYTES
		TYPE_ARRAY:
			if not _consume_gameplay_items(budget, value.size()):
				return false
			for item in value:
				if not _is_safe_gameplay_value_recursive(item, depth + 1, budget):
					return false
			return true
		TYPE_DICTIONARY:
			if not _consume_gameplay_items(budget, value.size()):
				return false
			for key in value:
				if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
					return false
				var key_string := str(key)
				if key_string.length() > MAX_STRING_LENGTH:
					return false
				budget["string_bytes"] = int(budget["string_bytes"]) + key_string.to_utf8_buffer().size()
				if int(budget["string_bytes"]) > MAX_GAMEPLAY_VALUE_BYTES:
					return false
				if not _is_safe_gameplay_value_recursive(value[key], depth + 1, budget):
					return false
			return true
		TYPE_PACKED_STRING_ARRAY:
			if not _consume_gameplay_items(budget, value.size()):
				return false
			for item in value:
				budget["string_bytes"] = int(budget["string_bytes"]) + item.to_utf8_buffer().size()
				if int(budget["string_bytes"]) > MAX_GAMEPLAY_VALUE_BYTES:
					return false
			return _is_safe_mutation_value(value, depth)
		TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY, TYPE_PACKED_VECTOR2_ARRAY, TYPE_PACKED_VECTOR3_ARRAY, TYPE_PACKED_COLOR_ARRAY, TYPE_PACKED_VECTOR4_ARRAY:
			return _consume_gameplay_items(budget, value.size()) and _is_safe_mutation_value(value, depth)
		_:
			return _is_safe_mutation_value(value, depth)


func _consume_gameplay_items(budget: Dictionary, count: int) -> bool:
	budget["items"] = int(budget["items"]) + count
	return int(budget["items"]) <= MAX_CONTAINER_ITEMS


func _gameplay_driver_path(driver: Node) -> String:
	if _is_node_in_current_scene(driver):
		return _relative_node_path(driver)
	return str(driver.get_path())


func _resolve_required_node(path_value: Variant) -> Dictionary:
	if typeof(path_value) != TYPE_STRING and typeof(path_value) != TYPE_STRING_NAME and typeof(path_value) != TYPE_NODE_PATH:
		return _failure("invalid_node_path", "node_path must be a relative String or NodePath.")
	var path := str(path_value)
	if not _is_node_path_valid(path):
		return _failure("invalid_node_path", "node_path must be a safe path relative to the current scene root.", {"node_path": _bounded_string(path, 256)})
	var scene_root := get_tree().current_scene
	if scene_root == null:
		return _failure("no_scene", "There is no current runtime scene.")
	var node := scene_root if path == "." else scene_root.get_node_or_null(NodePath(path))
	if node == null or (node != scene_root and not scene_root.is_ancestor_of(node)):
		return _failure("node_not_found", "No node exists at this current-scene-relative path.", {"node_path": path})
	return {"ok": true, "node": node}


func _relative_node_path(node: Node) -> String:
	var scene_root := get_tree().current_scene
	if node == scene_root:
		return "."
	return str(scene_root.get_path_to(node))


func _is_node_in_current_scene(node: Node) -> bool:
	var scene_root := get_tree().current_scene
	return scene_root != null and (node == scene_root or scene_root.is_ancestor_of(node))


func _is_node_path_valid(path: String) -> bool:
	if path.is_empty() or path.length() > MAX_PATH_LENGTH or path.begins_with("/") or path.contains("\\") or path.contains(":"):
		return false
	if path == ".":
		return true
	for segment in path.split("/", true):
		if segment.is_empty() or segment == "." or segment == ".." or segment.begins_with("%"):
			return false
	return true


func _is_capture_path_valid(path: String) -> bool:
	if path.length() > MAX_CAPTURE_PATH_LENGTH or not path.begins_with(CAPTURE_DIRECTORY + "/") or path.contains("\\"):
		return false
	var filename := path.trim_prefix(CAPTURE_DIRECTORY + "/")
	return (
		not filename.is_empty()
		and not filename.contains("/")
		and not filename.contains(":")
		and filename != "."
		and filename != ".."
		and filename.is_valid_filename()
		and not filename.get_basename().is_empty()
		and filename.get_extension().to_lower() == "png"
	)


func _capture_path_contains_symlink(path: String) -> bool:
	var project_root := ProjectSettings.globalize_path("res://").simplify_path()
	var access := DirAccess.open(project_root)
	if access == null:
		return true
	var relative_path := path.trim_prefix("res://")
	var candidate := project_root
	for segment in relative_path.split("/", false):
		candidate = candidate.path_join(segment)
		if access.is_link(candidate):
			return true
	return false


func _default_capture_path() -> String:
	return "%s/capture-%d-%d.png" % [CAPTURE_DIRECTORY, int(Time.get_unix_time_from_system()), Time.get_ticks_usec()]


func _is_method_name_valid(method: String) -> bool:
	if method.is_empty() or method.length() > 128 or method.begins_with(".") or method.ends_with("."):
		return false
	for segment in method.split("."):
		if not segment.is_valid_ascii_identifier():
			return false
	return true


func _is_property_name_valid(property_name: String) -> bool:
	return not property_name.is_empty() and property_name.length() <= 128 and property_name.is_valid_ascii_identifier()


func _is_property_hidden(info: Dictionary) -> bool:
	var usage := int(info.get("usage", 0))
	return (
		(usage & PROPERTY_USAGE_INTERNAL) != 0
		or (usage & PROPERTY_USAGE_SECRET) != 0
		or (usage & PROPERTY_USAGE_GROUP) != 0
		or (usage & PROPERTY_USAGE_SUBGROUP) != 0
		or (usage & PROPERTY_USAGE_CATEGORY) != 0
	)


func _is_property_inspectable(info: Dictionary) -> bool:
	var usage := int(info.get("usage", 0))
	return (usage & (PROPERTY_USAGE_EDITOR | PROPERTY_USAGE_SCRIPT_VARIABLE)) != 0


func _validate_input_action(action_value: Variant) -> Dictionary:
	if typeof(action_value) != TYPE_STRING and typeof(action_value) != TYPE_STRING_NAME:
		return _failure("invalid_action", "action must be a String.")
	var action_string := str(action_value)
	if action_string.is_empty() or action_string.length() > 128 or action_string != action_string.strip_edges() or "\n" in action_string or "\r" in action_string:
		return _failure("invalid_action", "The input action name is invalid.")
	var action := StringName(action_string)
	if not InputMap.has_action(action):
		return _failure("action_not_found", "The project Input Map does not define this action.", {"action": action_string})
	return {"ok": true, "action": action}


func _coerce_integer(value: Variant, minimum: int, maximum: int, parameter_name: String) -> Dictionary:
	var integer_value: int
	if typeof(value) == TYPE_INT:
		integer_value = value
	elif typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value):
		integer_value = int(value)
	else:
		return _failure(
			"invalid_params",
			"%s must be an integer in the supported range." % parameter_name,
			{"minimum": minimum, "maximum": maximum},
		)
	if integer_value < minimum or integer_value > maximum:
		return _failure(
			"invalid_params",
			"%s must be an integer in the supported range." % parameter_name,
			{"minimum": minimum, "maximum": maximum},
		)
	return {"ok": true, "value": integer_value}


func _bounded_groups(groups: Array[StringName]) -> Array[String]:
	var result: Array[String] = []
	var group_limit: int = mini(groups.size(), 128)
	for index in range(group_limit):
		result.push_back(_bounded_string(str(groups[index]), 256))
	return result


func _bounded_string(value: String, maximum: int = MAX_STRING_LENGTH) -> String:
	return value if value.length() <= maximum else value.substr(0, maximum)


func _validate_params(params: Dictionary, allowed: Array[String], required: Array[String] = []) -> Dictionary:
	var unknown := _unknown_keys(params, allowed)
	if not unknown.is_empty():
		return _failure("unknown_param", "The command contains unsupported parameters.", {"parameters": unknown})
	var missing: Array[String] = []
	for key in required:
		if not params.has(key):
			missing.push_back(key)
	if not missing.is_empty():
		return _failure("missing_param", "The command is missing required parameters.", {"parameters": missing})
	return {}


func _unknown_keys(dictionary: Dictionary, allowed: Array[String]) -> Array[String]:
	var unknown: Array[String] = []
	for key in dictionary:
		if typeof(key) != TYPE_STRING and typeof(key) != TYPE_STRING_NAME:
			unknown.push_back(_bounded_string(str(key), 128))
		elif not allowed.has(str(key)):
			unknown.push_back(_bounded_string(str(key), 128))
	return unknown


func _success(data: Variant) -> Dictionary:
	return {"ok": true, "data": data}


func _failure(code: String, message: String, details: Dictionary = {}) -> Dictionary:
	var error := {"code": code, "message": message}
	if not details.is_empty():
		error["details"] = details
	return {"ok": false, "error": error}


func _serialized_size(value: Variant) -> int:
	return JSON.stringify(JSON.from_native(value)).to_utf8_buffer().size()


func _send_response(request_id: Variant, result: Dictionary) -> void:
	if not EngineDebugger.is_active():
		return
	var response := {"id": request_id, "ok": result.get("ok", false)}
	if response["ok"]:
		response["data"] = result.get("data")
	else:
		response["error"] = result.get("error", {"code": "internal_error", "message": "The command failed without an error payload."})
	var response_size := _serialized_size(response)
	if response_size > MAX_RESPONSE_BYTES:
		response = {
			"id": request_id,
			"ok": false,
			"error": {
				"code": "response_too_large",
				"message": "The serialized runtime response exceeds the response limit.",
				"details": {"maximum_bytes": MAX_RESPONSE_BYTES, "actual_bytes": response_size},
			},
		}
	EngineDebugger.send_message(MESSAGE_RESPONSE, [response])
