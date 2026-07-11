extends Node

const DRIVER_GROUP := &"godot_ai_gameplay_driver"

var applied_intent_count := 0
var last_intent := ""


func _enter_tree() -> void:
	add_to_group(DRIVER_GROUP)


func _godot_ai_describe() -> Dictionary:
	return {
		"name": "Agent Smoke Gameplay Driver",
		"version": 1,
		"intents": {
			"set_mover_speed": {
				"description": "Set the smoke actor's movement speed through a semantic game intent.",
				"params": {
					"speed": {"type": "number", "minimum": 0.0, "maximum": 10.0},
				},
				"required": ["speed"],
			},
		},
	}


func _godot_ai_state() -> Dictionary:
	var mover := _mover()
	return {
		"applied_intent_count": applied_intent_count,
		"last_intent": last_intent,
		"mover_position": mover.position if mover != null else Vector3.ZERO,
		"mover_speed": mover.get("speed") if mover != null else 0.0,
	}


func _godot_ai_apply_intent(name: String, params: Dictionary) -> Dictionary:
	if name != "set_mover_speed":
		return {"accepted": false, "reason": "unsupported_intent"}
	var speed: Variant = params.get("speed")
	if (
		typeof(speed) != TYPE_FLOAT
		and typeof(speed) != TYPE_INT
		or not is_finite(float(speed))
		or float(speed) < 0.0
		or float(speed) > 10.0
	):
		return {"accepted": false, "reason": "speed_out_of_range"}
	var mover := _mover()
	if mover == null:
		return {"accepted": false, "reason": "mover_not_found"}
	mover.set("speed", float(speed))
	applied_intent_count += 1
	last_intent = name
	return {"accepted": true, "speed": mover.get("speed")}


func _mover() -> Node3D:
	return get_parent().get_node_or_null("AgentMover") as Node3D
