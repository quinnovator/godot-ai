@tool
extends EditorPlugin

const AUTOLOAD_NAME := "GodotAIRuntime"
const AUTOLOAD_PATH := "res://addons/godot_ai_runtime/godot_ai_runtime.gd"
const AUTOLOAD_SETTING := "autoload/%s" % AUTOLOAD_NAME

var _owns_autoload := false


func _enter_tree() -> void:
	if ProjectSettings.has_setting(AUTOLOAD_SETTING):
		var configured: Variant = ProjectSettings.get_setting(AUTOLOAD_SETTING)
		if not _autoload_points_to_runtime(configured):
			push_error(
				"Godot AI Runtime did not install its autoload because '%s' is already configured for a different resource."
				% AUTOLOAD_NAME
			)
			return
		# The plug-in may be entering after an editor restart. Treat the exact
		# bundled autoload as managed so disabling the plug-in removes it.
		_owns_autoload = true
		return

	add_autoload_singleton(AUTOLOAD_NAME, AUTOLOAD_PATH)
	_owns_autoload = (
		ProjectSettings.has_setting(AUTOLOAD_SETTING)
		and _autoload_points_to_runtime(ProjectSettings.get_setting(AUTOLOAD_SETTING))
	)
	if not _owns_autoload:
		push_error("Godot AI Runtime could not install its autoload.")


func _exit_tree() -> void:
	if not _owns_autoload:
		return
	if not ProjectSettings.has_setting(AUTOLOAD_SETTING):
		_owns_autoload = false
		return
	if not _autoload_points_to_runtime(ProjectSettings.get_setting(AUTOLOAD_SETTING)):
		push_warning(
			"Godot AI Runtime left '%s' untouched because its autoload configuration changed after installation."
			% AUTOLOAD_NAME
		)
		_owns_autoload = false
		return
	remove_autoload_singleton(AUTOLOAD_NAME)
	_owns_autoload = false


func _autoload_points_to_runtime(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var configured := str(value)
	if not configured.begins_with("*"):
		return false
	return ResourceUID.ensure_path(configured.trim_prefix("*")) == AUTOLOAD_PATH
