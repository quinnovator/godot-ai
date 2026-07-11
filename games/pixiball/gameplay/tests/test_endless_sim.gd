extends SceneTree

const EndlessScript = preload("../pixiball_endless_sim.gd")
const CatalogScript = preload("../../core/content/content_catalog.gd")
const PitchModelScript = preload("../../core/model/pitch_model.gd")


func _init() -> void:
	var passed := _test_outs_do_not_flip_sides()
	passed = _test_third_run_is_immediately_final_and_retry_resets() and passed
	passed = _test_epoch_replay_contract() and passed
	if passed:
		print("PIXIBALL_ENDLESS_OK limit=3 retry_epoch=true")
	quit(0 if passed else 1)


func _test_outs_do_not_flip_sides() -> bool:
	var sim = EndlessScript.new(111, 99, 0.6)
	for unused in 3:
		for strike in 3:
			_commit_plate(sim, "called_strike")
	var state: Dictionary = sim.snapshot()
	assert(state.mode == "endless")
	assert(state.half == "top" and int(state.inning) == 1)
	assert(int(state.outs) == 0)
	assert(not state.bases.first and not state.bases.second and not state.bases.third)
	assert(int(state.endless.strikeouts) == 3)
	assert(int(state.endless.score) == 3)
	assert(int(state.endless.batters_faced) == 3)
	assert(int(state.endless.pitch_count) == 9)
	assert(sim.is_user_pitching() and not sim.is_user_batting())
	return true


func _test_third_run_is_immediately_final_and_retry_resets() -> bool:
	var sim = EndlessScript.new(222, 99, 0.6)
	for run in 3:
		_commit_home_run(sim, run < 2)
	var final: Dictionary = sim.snapshot()
	assert(final.game_over and final.phase == "game_over")
	assert(int(final.endless.runs_allowed) == 3)
	assert(int(final.endless.batters_faced) == 3)
	assert(int(final.endless.pitch_count) == 3)
	assert(final.legal_actions == ["retry", "reset"])
	var retried: Dictionary = sim.retry()
	assert(not retried.game_over and retried.phase == "pitch")
	assert(int(retried.endless.strikeouts) == 0)
	assert(int(retried.endless.runs_allowed) == 0)
	assert(int(retried.endless.batters_faced) == 0)
	assert(int(retried.endless.pitch_count) == 0)
	assert(int(retried.epoch) == 1)
	return true


func _test_epoch_replay_contract() -> bool:
	var catalog = CatalogScript.new()
	assert(catalog.load_all())
	var model = PitchModelScript.new()
	assert(model.load_from_directory())
	var left = EndlessScript.new(333, catalog.pitcher_at(0), model)
	var right = EndlessScript.new(333, catalog.pitcher_at(0), model)
	var first_left: Dictionary = left.create_user_pitch("kc", Vector2(-0.4, 1.8))
	var first_right: Dictionary = right.create_user_pitch("kc", Vector2(-0.4, 1.8))
	assert(first_left == first_right)
	left.retry()
	var retried: Dictionary = left.create_user_pitch("kc", Vector2(-0.4, 1.8))
	assert(int(left.snapshot().epoch) == 1)
	assert(retried.model_result != first_left.model_result)
	# Two independent runs at epoch zero remain replay-identical.
	assert(int(right.snapshot().epoch) == 0)
	return true


func _commit_plate(sim, outcome: String) -> void:
	var pitch: Dictionary = sim.create_user_pitch("four_seam", Vector2(0.0, 2.5))
	var state: Dictionary = sim.commit_plate_result({"outcome": outcome, "pitch_serial": pitch.serial})
	if state.phase == "result":
		sim.advance_after_result()


func _commit_home_run(sim, advance: bool) -> void:
	var pitch: Dictionary = sim.create_user_pitch("four_seam", Vector2(0.0, 2.5))
	sim.commit_plate_result({
		"outcome": "in_play",
		"pitch_serial": pitch.serial,
		"trajectory": {"exit_velocity_mph": 100.0, "launch_angle_deg": 25.0, "spray_angle_deg": 0.0, "carry_ft": 400.0},
	})
	var state: Dictionary = sim.commit_live_play({"classification": "home_run"})
	if advance and state.phase == "result":
		sim.advance_after_result()
