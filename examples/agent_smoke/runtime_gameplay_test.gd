extends SceneTree

const RuntimeProbe := preload("res://addons/godot_ai_runtime/godot_ai_runtime.gd")
const DRIVER_GROUP := &"godot_ai_gameplay_driver"


class ValidDriver:
	extends Node

	var applied := 0

	func _enter_tree() -> void:
		add_to_group(&"godot_ai_gameplay_driver")

	func _godot_ai_describe() -> Dictionary:
		return {"name": "test", "intents": {"advance": {"params": {}}}}

	func _godot_ai_state() -> Dictionary:
		return {"applied": applied, "position": Vector3(1.0, 2.0, 3.0)}

	func _godot_ai_apply_intent(name: String, params: Dictionary) -> Dictionary:
		applied += 1
		return {"accepted": name == "advance", "params": params}


class MissingCallbackDriver:
	extends Node

	func _enter_tree() -> void:
		add_to_group(&"godot_ai_gameplay_driver")


class WrongSignatureDriver:
	extends Node

	func _enter_tree() -> void:
		add_to_group(&"godot_ai_gameplay_driver")

	func _godot_ai_describe(unexpected: Dictionary) -> Dictionary:
		return {"intents": unexpected}

	func _godot_ai_state() -> Dictionary:
		return {}

	func _godot_ai_apply_intent(name: String, params: Dictionary) -> Dictionary:
		return {"name": name, "params": params}


class UnsafeStateDriver:
	extends ValidDriver

	func _godot_ai_state() -> Dictionary:
		return {"unsafe_object": self}


class TooManyIntentsDriver:
	extends ValidDriver

	func _godot_ai_describe() -> Dictionary:
		var intents := {}
		for index in range(257):
			intents["intent_%d" % index] = {}
		return {"intents": intents}


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var scene := Node.new()
	scene.name = "RuntimeGameplayTest"
	root.add_child(scene)
	current_scene = scene
	var runtime: Node = root.get_node_or_null("GodotAIRuntime")
	var owns_runtime := runtime == null
	if owns_runtime:
		runtime = RuntimeProbe.new()
		scene.add_child(runtime)

	_expect_error(runtime.call("_command_gameplay_describe", {}), "gameplay_driver_not_found", "missing driver")

	var driver := ValidDriver.new()
	driver.name = "Driver"
	scene.add_child(driver)
	var described: Dictionary = runtime.call("_command_gameplay_describe", {})
	_expect(described.get("ok") == true, "valid driver description was rejected: %s" % described)
	_expect(
		described.get("data", {}).get("description", {}).get("intents", {}).has("advance"),
		"declared intent was absent from gameplay.describe",
	)
	var intent: Dictionary = runtime.call(
		"_command_gameplay_intent",
		{"name": "advance", "params": {"ticks": 3}},
	)
	_expect(intent.get("ok") == true, "declared gameplay intent was rejected: %s" % intent)
	var state: Dictionary = runtime.call("_command_gameplay_state", {})
	_expect(state.get("data", {}).get("state", {}).get("applied") == 1, "gameplay state did not observe the intent")
	_expect_error(
		runtime.call("_command_gameplay_intent", {"name": "missing", "params": {}}),
		"intent_not_declared",
		"undeclared intent",
	)
	var oversized_values: Array[int] = []
	oversized_values.resize(1_025)
	_expect_error(
		runtime.call(
			"_command_gameplay_intent",
			{"name": "advance", "params": {"values": oversized_values}},
		),
		"unsafe_gameplay_value",
		"oversized intent parameters",
	)

	var duplicate := ValidDriver.new()
	scene.add_child(duplicate)
	_expect_error(runtime.call("_command_gameplay_describe", {}), "gameplay_driver_ambiguous", "duplicate drivers")
	duplicate.free()
	driver.free()

	var missing_callback := MissingCallbackDriver.new()
	scene.add_child(missing_callback)
	_expect_error(runtime.call("_command_gameplay_describe", {}), "gameplay_driver_invalid", "missing callback")
	missing_callback.free()

	var wrong_signature := WrongSignatureDriver.new()
	scene.add_child(wrong_signature)
	_expect_error(runtime.call("_command_gameplay_describe", {}), "gameplay_driver_invalid", "wrong callback signature")
	wrong_signature.free()

	var unsafe_state := UnsafeStateDriver.new()
	scene.add_child(unsafe_state)
	_expect_error(runtime.call("_command_gameplay_state", {}), "unsafe_gameplay_value", "unsafe state")
	unsafe_state.free()

	var excessive_description := TooManyIntentsDriver.new()
	scene.add_child(excessive_description)
	_expect_error(
		runtime.call("_command_gameplay_describe", {}),
		"gameplay_driver_limit_exceeded",
		"excessive intent declarations",
	)
	excessive_description.free()
	if owns_runtime:
		runtime.free()
	scene.free()

	if _failures.is_empty():
		print("Godot AI gameplay driver runtime tests passed")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _expect_error(result: Dictionary, code: String, label: String) -> void:
	var actual := str(result.get("error", {}).get("code", ""))
	_expect(not result.get("ok", false) and actual == code, "%s returned '%s', expected '%s': %s" % [label, actual, code, result])


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.push_back(message)
