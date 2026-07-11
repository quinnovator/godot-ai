class_name PixiballSaveRepository
extends RefCounted

## Tiny, versioned persistence boundary for shell statistics.
##
## Keeping this separate from the simulation makes corrupt or future save files
## harmless to deterministic gameplay. Tests can inject a user:// path without
## touching a player's real profile.

const CURRENT_VERSION := 1
const DEFAULT_PATH := "user://pixiball_profile.cfg"

var path := DEFAULT_PATH
var best_endless_strikeouts := 0
var versus_wins := 0
var versus_losses := 0


func _init(path_override := DEFAULT_PATH) -> void:
	path = String(path_override) if not String(path_override).is_empty() else DEFAULT_PATH


func load_profile() -> Dictionary:
	_reset_defaults()
	var config := ConfigFile.new()
	var error := config.load(path)
	if error == ERR_FILE_NOT_FOUND:
		return snapshot()
	if error != OK:
		return snapshot()
	if int(config.get_value("profile", "version", -1)) != CURRENT_VERSION:
		return snapshot()
	best_endless_strikeouts = _safe_counter(config.get_value("records", "best_endless_strikeouts", 0))
	versus_wins = _safe_counter(config.get_value("records", "versus_wins", 0))
	versus_losses = _safe_counter(config.get_value("records", "versus_losses", 0))
	return snapshot()


func record_endless(strikeouts: int) -> Dictionary:
	var prior := best_endless_strikeouts
	best_endless_strikeouts = maxi(best_endless_strikeouts, maxi(0, strikeouts))
	_save()
	var result := snapshot()
	result["new_best"] = best_endless_strikeouts > prior
	result["previous_best"] = prior
	return result


func record_versus(won: bool) -> Dictionary:
	if won:
		versus_wins += 1
	else:
		versus_losses += 1
	_save()
	return snapshot()


func snapshot() -> Dictionary:
	return {
		"version": CURRENT_VERSION,
		"best_endless_strikeouts": best_endless_strikeouts,
		"versus_wins": versus_wins,
		"versus_losses": versus_losses,
	}


func _save() -> bool:
	var config := ConfigFile.new()
	config.set_value("profile", "version", CURRENT_VERSION)
	config.set_value("records", "best_endless_strikeouts", best_endless_strikeouts)
	config.set_value("records", "versus_wins", versus_wins)
	config.set_value("records", "versus_losses", versus_losses)
	return config.save(path) == OK


func _reset_defaults() -> void:
	best_endless_strikeouts = 0
	versus_wins = 0
	versus_losses = 0


func _safe_counter(value: Variant) -> int:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return 0
	var number := float(value)
	if not is_finite(number) or floor(number) != number:
		return 0
	return clampi(int(number), 0, 1_000_000_000)
