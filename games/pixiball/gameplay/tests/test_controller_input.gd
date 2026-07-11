extends SceneTree

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_movement_bindings()
	_test_gameplay_bindings()
	if _failures.is_empty():
		print("PIXIBALL_CONTROLLER_INPUT_OK actions=14 keyboard=true gamepad=true menus=true")
		quit(0)
	else:
		for failure in _failures:
			push_error("PIXIBALL_CONTROLLER_INPUT: %s" % failure)
		quit(1)


func _test_movement_bindings() -> void:
	var expected := {
		"pix_up": {"key": KEY_W, "axis": JOY_AXIS_LEFT_Y, "axis_value": -1.0, "dpad": JOY_BUTTON_DPAD_UP},
		"pix_down": {"key": KEY_S, "axis": JOY_AXIS_LEFT_Y, "axis_value": 1.0, "dpad": JOY_BUTTON_DPAD_DOWN},
		"pix_left": {"key": KEY_A, "axis": JOY_AXIS_LEFT_X, "axis_value": -1.0, "dpad": JOY_BUTTON_DPAD_LEFT},
		"pix_right": {"key": KEY_D, "axis": JOY_AXIS_LEFT_X, "axis_value": 1.0, "dpad": JOY_BUTTON_DPAD_RIGHT},
	}
	for action_value in expected:
		var action := StringName(action_value)
		var spec: Dictionary = expected[action_value]
		_check(InputMap.has_action(action), "%s must exist in project settings" % action)
		_check(_has_key(action, int(spec.key)), "%s must preserve its physical keyboard binding" % action)
		var arrows := {"pix_up": KEY_UP, "pix_down": KEY_DOWN, "pix_left": KEY_LEFT, "pix_right": KEY_RIGHT}
		_check(_has_key(action, int(arrows[action_value])), "%s must support keyboard arrow navigation" % action)
		_check(_has_axis(action, int(spec.axis), float(spec.axis_value)), "%s must support the left stick" % action)
		_check(_has_button(action, int(spec.dpad)), "%s must support the d-pad" % action)
		_check(is_equal_approx(InputMap.action_get_deadzone(action), 0.22), "%s must use the precision aim deadzone" % action)


func _test_gameplay_bindings() -> void:
	var expected_buttons := {
		"pix_start": [JOY_BUTTON_START, JOY_BUTTON_A],
		"pix_pitch_1": [JOY_BUTTON_A],
		"pix_pitch_2": [JOY_BUTTON_B],
		"pix_pitch_3": [JOY_BUTTON_Y],
		"pix_pitch_4": [JOY_BUTTON_X],
		"pix_pitch_5": [JOY_BUTTON_RIGHT_SHOULDER],
		"pix_cycle": [JOY_BUTTON_LEFT_SHOULDER],
		"pix_restart": [JOY_BUTTON_BACK],
		"pix_mood": [JOY_BUTTON_RIGHT_STICK],
		"pix_back": [JOY_BUTTON_B],
	}
	for action_value in expected_buttons:
		var action := StringName(action_value)
		_check(InputMap.has_action(action), "%s must exist in project settings" % action)
		for button in expected_buttons[action_value]:
			_check(_has_button(action, int(button)), "%s must include joypad button %d" % [action, button])

	var keyboard := {
		"pix_primary": KEY_SPACE,
		"pix_start": KEY_ENTER,
		"pix_pitch_1": KEY_1,
		"pix_pitch_2": KEY_2,
		"pix_pitch_3": KEY_3,
		"pix_pitch_4": KEY_4,
		"pix_pitch_5": KEY_5,
		"pix_cycle": KEY_Q,
		"pix_restart": KEY_R,
		"pix_mood": KEY_M,
		"pix_back": KEY_ESCAPE,
	}
	for action_value in keyboard:
		_check(_has_key(StringName(action_value), int(keyboard[action_value])),
			"%s must preserve its keyboard binding" % action_value)

	_check(_has_axis(&"pix_primary", JOY_AXIS_TRIGGER_RIGHT, 1.0),
		"pitch, swing, and confirm must use the analog right trigger")
	_check(_button_count(&"pix_primary") == 0,
		"primary must not share a face button with pitch selection and accidentally auto-throw")


func _has_key(action: StringName, physical_keycode: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and int(event.physical_keycode) == physical_keycode:
			return true
	return false


func _has_axis(action: StringName, axis: int, value: float) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion and int(event.axis) == axis and is_equal_approx(float(event.axis_value), value):
			return true
	return false


func _has_button(action: StringName, button: int) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and int(event.button_index) == button:
			return true
	return false


func _button_count(action: StringName) -> int:
	var result := 0
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton:
			result += 1
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
