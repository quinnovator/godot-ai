extends SceneTree

const PixRngScript = preload("res://core/model/pix_rng.gd")
const CatalogScript = preload("res://core/content/content_catalog.gd")


func _init() -> void:
	var rng = PixRngScript.new(12648430)
	var expected := PackedFloat64Array([
		0.021141508361324668,
		0.6661099966149777,
		0.7799714196007699,
		0.7395844468846917,
	])
	for value in expected:
		assert(is_equal_approx(rng.next(), value))
	var catalog = CatalogScript.new()
	assert(catalog.load_all())
	var description := catalog.describe()
	assert(int(description.pitchers) == 10)
	assert(int(description.teams) == 8)
	assert(int(description.batter_archetypes) == 5)
	assert(int(description.feature_columns) == 37)
	assert((catalog.pitcher_at(0).pitches as Array).size() == 5)
	print("PIXIBALL_CONTENT_MODEL_OK pitchers=%d teams=%d features=%d" % [
		int(description.pitchers),
		int(description.teams),
		int(description.feature_columns),
	])
	quit(0)
