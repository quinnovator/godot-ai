class_name PixiballContentCatalog
extends RefCounted

## Read-only catalog for the authorized data port from the original game.

const DEFAULT_DATA_DIR := "res://content/data"

var data_dir := DEFAULT_DATA_DIR
var pitchers: Array[Dictionary] = []
var batter_archetypes: Array[Dictionary] = []
var batter_names: Array[String] = []
var teams: Array[Dictionary] = []
var choreography: Dictionary = {}
var model_meta: Dictionary = {}
var last_error := ""


func load_all(path := DEFAULT_DATA_DIR) -> bool:
	data_dir = path.trim_suffix("/")
	last_error = ""
	var pitcher_value: Variant = _load_json("pitchers.json")
	var batter_value: Variant = _load_json("batters.json")
	var name_value: Variant = _load_json("batterNames.json")
	var team_value: Variant = _load_json("teams.json")
	var choreography_value: Variant = _load_json("choreography.json")
	var meta_value: Variant = _load_json("modelMeta.json")
	if not last_error.is_empty():
		return false
	if not pitcher_value is Array or not batter_value is Array or not name_value is Array or not team_value is Array:
		last_error = "Pixiball catalog arrays have an invalid schema"
		return false
	if not choreography_value is Dictionary or not meta_value is Dictionary:
		last_error = "Pixiball catalog objects have an invalid schema"
		return false

	pitchers.assign(pitcher_value)
	batter_archetypes.assign(batter_value)
	batter_names.clear()
	for value in name_value:
		batter_names.append(String(value))
	teams.assign(team_value)
	choreography = choreography_value
	model_meta = meta_value
	return _validate()


func pitcher_by_id(id_value: int) -> Dictionary:
	for pitcher in pitchers:
		if int(pitcher.get("id", -1)) == id_value:
			return pitcher.duplicate(true)
	return {}


func pitcher_at(index: int) -> Dictionary:
	if index < 0 or index >= pitchers.size():
		return {}
	return pitchers[index].duplicate(true)


func team_by_id(id_value: String) -> Dictionary:
	for team in teams:
		if String(team.get("id", "")) == id_value:
			return team.duplicate(true)
	return {}


func archetype_by_encoded(encoded: int) -> Dictionary:
	for archetype in batter_archetypes:
		if int(archetype.get("encoded", -1)) == encoded:
			return archetype.duplicate(true)
	return {}


func describe() -> Dictionary:
	return {
		"ok": last_error.is_empty(),
		"data_dir": data_dir,
		"pitchers": pitchers.size(),
		"teams": teams.size(),
		"batter_archetypes": batter_archetypes.size(),
		"batter_names": batter_names.size(),
		"feature_columns": (model_meta.get("featureColumns", []) as Array).size(),
	}


func _load_json(file_name: String) -> Variant:
	var path := "%s/%s" % [data_dir, file_name]
	if not FileAccess.file_exists(path):
		last_error = "Missing Pixiball data file: %s" % path
		return null
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed == null:
		last_error = "Invalid JSON in Pixiball data file: %s" % path
	return parsed


func _validate() -> bool:
	if pitchers.is_empty() or teams.is_empty() or batter_archetypes.is_empty():
		last_error = "Pixiball data catalog is empty"
		return false
	for index in range(pitchers.size()):
		var pitcher := pitchers[index]
		var pitches: Array = pitcher.get("pitches", [])
		if pitches.size() != 5:
			last_error = "Pitcher %d must contain exactly five pitches" % index
			return false
	var columns: Array = model_meta.get("featureColumns", [])
	if columns.size() != 37:
		last_error = "Pitch model metadata must contain 37 feature columns"
		return false
	return true
