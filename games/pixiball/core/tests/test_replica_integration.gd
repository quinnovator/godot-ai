extends SceneTree

const SimScript = preload("res://gameplay/pixiball_sim.gd")
const CatalogScript = preload("res://core/content/content_catalog.gd")
const PitchModelScript = preload("res://core/model/pitch_model.gd")


func _init() -> void:
	var catalog = CatalogScript.new()
	assert(catalog.load_all())
	var model = PitchModelScript.new()
	assert(model.load_from_directory())
	var sim = SimScript.new(20260710, 1, 0.55)
	var configured := sim.configure_replica(catalog.pitcher_at(0), catalog.pitcher_at(1), model)
	assert(bool(configured.ok))
	assert(int(configured.pitch_slots) == 5)

	var first: Dictionary = sim.create_user_pitch("kc", Vector2(-0.58, 1.65))
	assert(bool(first.ok))
	assert(String(first.code) == "KC")
	assert(first.has("model_result"))
	_assert_probability_contract(first.model_result)
	var first_commit := sim.commit_plate_result({"outcome": "called_strike", "pitch_serial": first.serial})
	assert(String(first_commit.phase) == "result")
	var first_report := sim.last_pitch_report()
	assert((first_report.options as Array).size() == 5)
	assert(int(first_report.rank) >= 1 and int(first_report.rank) <= 5)
	assert(first_report.has("probabilities"))
	sim.advance_after_result()

	var second: Dictionary = sim.create_user_pitch("ff", Vector2(0.62, 3.32))
	assert(bool(second.ok))
	assert(String(second.code) == "FF")
	assert(float(second.model_result.tunnel_diff_in) > 0.0)
	assert(float(second.model_result.break_diff_in) > 0.0)
	assert(second.feedback.has("door"))
	_assert_probability_contract(second.model_result)
	sim.commit_plate_result({"outcome": "called_strike", "pitch_serial": second.serial})
	var second_report := sim.last_pitch_report()
	assert(float(second_report.tunnel_diff_in) > 0.0)
	assert(second_report.feedback.has("probabilities"))
	assert((second_report.options as Array).size() == 5)

	print("PIXIBALL_REPLICA_INTEGRATION_OK pitcher=%s pitches=5 reports=2" % String(sim.user_pitcher().name))
	quit(0)


func _assert_probability_contract(result: Dictionary) -> void:
	var probabilities: Dictionary = result.probabilities
	var stage_sum := 0.0
	for key in ["ball", "called_strike", "swinging_strike", "foul", "in_play"]:
		var value := float(probabilities[key])
		assert(value >= 0.0 and value <= 1.0)
		stage_sum += value
	assert(absf(stage_sum - 1.0) < 0.000001)
	var contact_sum := 0.0
	for key in ["out", "single", "double", "triple", "home_run"]:
		var value := float(probabilities[key])
		assert(value >= 0.0 and value <= 1.0)
		contact_sum += value
	assert(absf(contact_sum - float(probabilities.in_play)) < 0.000001)
