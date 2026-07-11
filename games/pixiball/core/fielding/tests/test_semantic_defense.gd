extends SceneTree

const Defense = preload("res://core/fielding/semantic_defense.gd")
const PixRngScript = preload("res://core/model/pix_rng.gd")
const SimScript = preload("res://gameplay/pixiball_sim.gd")

var _failures: Array[String] = []


func _init() -> void:
	_test_trajectory_classes()
	_test_determinism_and_validation()
	_test_sim_integration_is_non_mutating()
	if _failures.is_empty():
		print("PIXIBALL_SEMANTIC_DEFENSE_OK physics=intercept+races deterministic=verified")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _test_trajectory_classes() -> void:
	var homer := Defense.resolve(_trajectory(110.0, 28.0, 0.0), 26.0, 0.5, PixRngScript.new(1))
	_check(String(homer.get("classification", "")) == "home_run", "an over-fence flight must remain a home run")
	_check(String(homer.get("semantic_source", "")) == "over_fence", "home run should report its physical source")

	var grounder := Defense.resolve(_trajectory(75.0, 0.0, 0.0), 26.0, 0.5, PixRngScript.new(2))
	_check(String(grounder.get("classification", "")) == "ground_out", "a routine grounder should produce a throw-race out")
	_check(String(grounder.get("semantic_source", "")) == "infield_race", "routine grounder should use the infield intercept path")

	var lazy_fly := Defense.resolve(_trajectory(75.0, 35.0, 0.0), 26.0, 0.5, PixRngScript.new(3))
	_check(String(lazy_fly.get("classification", "")) == "fly_out", "a catchable lazy fly should be converted into an out")
	_check(float(lazy_fly.get("catch_probability", 0.0)) >= 0.5, "a routine fly should expose a defensible catch probability")

	var gap_ball := Defense.resolve(_trajectory(106.0, 24.0, 22.0), 27.0, 0.5, PixRngScript.new(4))
	_check(String(gap_ball.get("classification", "")) in ["double", "triple"], "a deep wall/gap ball should yield extra bases without becoming an automatic homer")


func _test_determinism_and_validation() -> void:
	var trajectory := _trajectory(94.0, 12.0, -9.0)
	var left := Defense.resolve(trajectory, 25.5, 0.65, PixRngScript.new(0xB411))
	var right := Defense.resolve(trajectory, 25.5, 0.65, PixRngScript.new(0xB411))
	_check(left == right, "the same trajectory, skill, and stream must replay exactly")
	var invalid := Defense.resolve({}, 26.0, 0.5, PixRngScript.new(1))
	_check(not bool(invalid.get("ok", true)) and String(invalid.get("error", "")) == "invalid_trajectory", "invalid launches must fail structurally")
	var missing_rng := Defense.resolve(trajectory, 26.0, 0.5, 7)
	_check(not bool(missing_rng.get("ok", true)) and String(missing_rng.get("error", "")) == "rng_required", "non-RNG inputs must fail structurally")


func _test_sim_integration_is_non_mutating() -> void:
	var sim = SimScript.new(404, 3, 0.55)
	var pitch: Dictionary = sim.create_user_pitch("four_seam", Vector2(0.0, 2.5))
	sim.commit_plate_result({
		"outcome": "in_play",
		"pitch_serial": pitch.serial,
		"trajectory": _trajectory(75.0, 0.0, 0.0),
	})
	var before: Dictionary = sim.snapshot()
	var first: Dictionary = sim.resolve_semantic_live_play()
	var second: Dictionary = sim.resolve_semantic_live_play()
	_check(first == second, "keyed semantic resolution must replay without consuming mutable pitch RNG")
	_check(sim.snapshot() == before, "resolving a semantic trajectory must not commit or mutate the sim")
	_check(int(first.get("pitch_serial", -1)) == int(pitch.serial), "semantic result must retain its pitch identity")
	var committed: Dictionary = sim.commit_live_play(first)
	_check(String(committed.last_result.classification) == String(first.classification), "semantic result must enter the existing live-play commit contract")


func _trajectory(exit_velocity: float, launch_angle: float, spray: float) -> Dictionary:
	return {
		"exit_velocity_mph": exit_velocity,
		"launch_angle_deg": launch_angle,
		"spray_angle_deg": spray,
		"contact_quality": 0.5,
	}


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
