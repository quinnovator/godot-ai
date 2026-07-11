extends SceneTree

const SimScript = preload("../pixiball_sim.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	_run()
	if _failures.is_empty():
		print("PixiballSim: all deterministic gameplay tests passed")
		quit(0)
	else:
		for failure in _failures:
			push_error(failure)
		quit(1)


func _run() -> void:
	_test_seed_replay()
	_test_restart_epoch()
	_test_count_and_half_flow()
	_test_hits_extras_and_walkoff()
	_test_resolution_contracts()
	_test_authoritative_live_rules()


func _test_restart_epoch() -> void:
	var left = SimScript.new(7070, 3, 0.5)
	var right = SimScript.new(7070, 3, 0.5)
	var first_left: Dictionary = left.create_user_pitch("slider", Vector2(-0.3, 2.1))
	var first_right: Dictionary = right.create_user_pitch("slider", Vector2(-0.3, 2.1))
	_check(first_left == first_right, "independent epoch-zero sessions must replay identically")
	_check(int(left.snapshot().epoch) == 0, "a new visible-seed session must begin at epoch zero")
	var restarted_left: Dictionary = left.restart()
	var restarted_right: Dictionary = right.restart()
	_check(int(restarted_left.epoch) == 1 and int(restarted_right.epoch) == 1,
		"restart must advance the deterministic session epoch")
	_check(int(restarted_left.seed) == 7070 and int(restarted_left.innings) == 3,
		"restart must preserve the visible seed and game configuration")
	var second_left: Dictionary = left.create_user_pitch("slider", Vector2(-0.3, 2.1))
	var second_right: Dictionary = right.create_user_pitch("slider", Vector2(-0.3, 2.1))
	_check(second_left == second_right, "same seed and epoch-one action sequence must replay identically")
	_check(second_left != first_left, "epoch-one fallback outcomes must differ from epoch zero")
	left.reset(7070, 3, 0.5)
	var reset_pitch: Dictionary = left.create_user_pitch("slider", Vector2(-0.3, 2.1))
	_check(int(left.snapshot().epoch) == 0 and reset_pitch == first_left,
		"direct reset must restore the epoch-zero golden path")


func _test_seed_replay() -> void:
	var left = SimScript.new(90210, 3, 0.65)
	var right = SimScript.new(90210, 3, 0.65)
	for index in 6:
		var kind: String = ["four_seam", "slider", "changeup"][index % 3]
		var aim := Vector2(-0.4 + index * 0.13, 1.8 + index * 0.17)
		var left_pitch: Dictionary = left.create_user_pitch(kind, aim)
		var right_pitch: Dictionary = right.create_user_pitch(kind, aim)
		_check(left_pitch == right_pitch, "same seed/action sequence must create identical pitches")
		var left_result: Dictionary = left.resolve_cpu_batter(left_pitch)
		var right_result: Dictionary = right.resolve_cpu_batter(right_pitch)
		_check(left_result == right_result, "same seed/action sequence must resolve identically")
		# Use a controlled call so this test is independent of whether contact
		# entered live play on this particular pitch.
		left.commit_plate_result({"outcome": "called_strike", "pitch_serial": left_pitch.serial})
		right.commit_plate_result({"outcome": "called_strike", "pitch_serial": right_pitch.serial})
		left.advance_after_result()
		right.advance_after_result()
	_check(left.snapshot() == right.snapshot(), "complete snapshots must replay exactly")


func _test_count_and_half_flow() -> void:
	var sim = SimScript.new(77, 3, 0.5)
	# A two-strike foul cannot strike out the hitter.
	_commit_plate(sim, "called_strike")
	_commit_plate(sim, "called_strike")
	_commit_plate(sim, "foul")
	var state: Dictionary = sim.snapshot()
	_check(state.count.strikes == 2 and state.outs == 0, "two-strike foul must preserve the count")
	_commit_plate(sim, "swinging_strike")
	_check(sim.snapshot().outs == 1, "third strike must record one out")
	# Two more strikeouts end the top half.
	for unused in 2:
		for strike in 3:
			_commit_plate(sim, "called_strike")
	state = sim.snapshot()
	_check(state.half == "bottom" and state.inning == 1, "three outs must advance top to bottom")
	_check(state.outs == 0 and not state.bases.first, "half transition must clear outs and bases")
	_check(sim.is_user_batting(), "user must bat in the bottom half")


func _test_hits_extras_and_walkoff() -> void:
	var sim = SimScript.new(1234, 1, 0.5)
	# Away: walk, then home run, then three outs. This checks forced runners,
	# hit scoring, and the top-to-bottom regulation transition.
	for ball in 4:
		_commit_plate(sim, "ball")
	_check(sim.snapshot().bases.first, "walk must put the batter on first")
	_commit_play(sim, "home_run")
	_check(sim.snapshot().score.away == 2, "home run must score the batter and occupied bases")
	for unused in 3:
		for strike in 3:
			_commit_plate(sim, "called_strike")
	_check(sim.snapshot().half == "bottom", "home side must receive its regulation bottom half while trailing")

	# Home: triple + homer ties the game; another homer is a walk-off.
	_commit_play(sim, "triple")
	_check(sim.snapshot().bases.third, "triple must place the batter on third")
	_commit_play(sim, "home_run")
	_check(sim.snapshot().score.home == 2, "home run after a triple must score two")
	_commit_play(sim, "home_run")
	var pending: Dictionary = sim.snapshot()
	_check(pending.score.home == 3 and _event_seen(pending.recent_events, "walk_off"),
		"late home lead must emit a walk-off")
	# _commit_play advances the result, so the game is now final.
	_check(pending.game_over and pending.winner == "home", "walk-off must finish with the home winner")

	# A tied regulation game must enter an extra inning instead of ending.
	var extras = SimScript.new(55, 1, 0.4)
	for half in 2:
		for unused in 3:
			for strike in 3:
				_commit_plate(extras, "called_strike")
	var extra_state: Dictionary = extras.snapshot()
	_check(extra_state.inning == 2 and extra_state.half == "top" and not extra_state.game_over,
		"tied regulation score must advance to extras")


func _test_resolution_contracts() -> void:
	var defense = SimScript.new(888, 3, 0.8)
	var no_launch_model := {
		"probabilities": {"ball": 0.0, "called_strike": 0.0, "swinging_strike": 0.0, "foul": 0.0, "in_play": 1.0},
		"sampled_launch_speed": 0.0,
		"sampled_launch_angle": 0.0,
	}
	var threshold_result: Dictionary = defense._resolve_model_cpu_batter({
		"serial": 0,
		"kind": "four_seam",
		"model_result": no_launch_model,
		"outcome_model_result": no_launch_model,
	})
	_check(threshold_result.outcome == "foul" and threshold_result.swung,
		"a sampled sub-threshold in-play bucket must become a foul, never a zero-mph live ball")
	_check(not threshold_result.has("trajectory"), "sub-threshold model contact must not create a trajectory")
	var user_pitch: Dictionary = defense.create_user_pitch("slider", {"x": 0.2, "z": 2.2})
	defense._active_pitch["model_context"] = {"catalog_arsenal": [{"internal": true}]}
	var active_snapshot: Dictionary = defense.snapshot().active_pitch
	_check(not active_snapshot.has("model_context") and not active_snapshot.has("catalog_arsenal"),
		"semantic snapshots must not expose oversized internal model context")
	var cpu_result: Dictionary = defense.resolve_cpu_batter(user_pitch)
	_check(cpu_result.ok and cpu_result.has("outcome"), "CPU batter resolution must be structured")

	# Reach the bottom half to inspect CPU pitch and user swing contracts.
	for unused in 3:
		for strike in 3:
			_commit_plate(defense, "called_strike")
	var cpu_pitch: Dictionary = defense.create_cpu_pitch()
	var user_result: Dictionary = defense.resolve_user_batter(cpu_pitch, {
		"did_swing": true,
		"reticle": cpu_pitch.actual,
		"timing_error_sec": 0.0,
	})
	_check(cpu_pitch.owner == "cpu" and cpu_pitch.has("path"), "CPU pitch must expose semantic path data")
	_check(user_result.ok and user_result.has("quality"), "user swing must report timing/location quality")
	if user_result.outcome == "in_play":
		var trajectory: Dictionary = user_result.trajectory
		_check(trajectory.carry_ft > 0.0 and trajectory.has("landing_ft"),
			"contact must expose a usable batted-ball trajectory")


func _test_authoritative_live_rules() -> void:
	var sim = SimScript.new(40404, 3, 0.65)
	sim._bases[0] = true
	var pitch: Dictionary = sim.create_user_pitch("four_seam", Vector2(0.0, 2.5))
	sim.commit_plate_result({
		"outcome": "in_play",
		"pitch_serial": pitch.serial,
		"trajectory": {"exit_velocity_mph": 91.0, "launch_angle_deg": 3.0, "spray_angle_deg": 4.0},
	})
	var choice: Dictionary = sim.commit_live_play({
		"classification": "ground_out",
		"rule_classification": "fielders_choice",
		"outs_recorded": 1,
		"final_bases": {"first": true, "second": false, "third": false},
		"runs": 0,
		"batter_bases": 1,
	})
	_check(choice.outs == 1 and choice.bases.first, "authoritative force at second must retire the lead runner and leave the batter safe")
	_check(choice.hits.away == 0 and choice.last_result.classification == "fielders_choice", "fielder's choice must not be scored as a hit or collapsed to a first-base groundout")
	sim.advance_after_result()
	pitch = sim.create_user_pitch("four_seam", Vector2(0.0, 2.5))
	sim.commit_plate_result({
		"outcome": "in_play",
		"pitch_serial": pitch.serial,
		"trajectory": {"exit_velocity_mph": 88.0, "launch_angle_deg": 1.0, "spray_angle_deg": -2.0},
	})
	var double_play: Dictionary = sim.commit_live_play({
		"classification": "ground_out",
		"rule_classification": "ground_out",
		"outs_recorded": 2,
		"double_play": true,
		"final_bases": {"first": false, "second": false, "third": false},
		"runs": 0,
	})
	_check(double_play.outs == 3 and bool(double_play.last_result.double_play), "authoritative 4-6-3 result must record both outs and end the half")


func _commit_plate(sim, outcome: String) -> void:
	var pitch: Dictionary
	if sim.is_user_pitching():
		pitch = sim.create_user_pitch("four_seam", Vector2(0.0, 2.5))
	else:
		pitch = sim.create_cpu_pitch()
	var committed: Dictionary = sim.commit_plate_result({"outcome": outcome, "pitch_serial": pitch.serial})
	_check(not committed.has("ok") or committed.get("ok", true), "plate result should commit")
	var advanced: Dictionary = sim.advance_after_result()
	_check(not advanced.has("ok") or advanced.get("ok", true), "plate result should advance")


func _commit_play(sim, classification: String) -> void:
	var pitch: Dictionary
	if sim.is_user_pitching():
		pitch = sim.create_user_pitch("four_seam", Vector2(0.0, 2.5))
	else:
		pitch = sim.create_cpu_pitch()
	var trajectory := {
		"exit_velocity_mph": 96.0,
		"launch_angle_deg": 24.0,
		"spray_angle_deg": 3.0,
		"carry_ft": 300.0,
	}
	sim.commit_plate_result({
		"outcome": "in_play",
		"pitch_serial": pitch.serial,
		"trajectory": trajectory,
	})
	var committed: Dictionary = sim.commit_live_play({"classification": classification})
	_check(committed.phase == "result", "live play should commit into a result beat")
	var advanced: Dictionary = sim.advance_after_result()
	_check(not advanced.has("ok") or advanced.get("ok", true), "live play result should advance")


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _event_seen(events: Array, type: String) -> bool:
	for event in events:
		if event is Dictionary and event.get("type", "") == type:
			return true
	return false
