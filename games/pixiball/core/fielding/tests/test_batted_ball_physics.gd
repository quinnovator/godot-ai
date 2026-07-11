extends SceneTree

const Ball = preload("res://core/fielding/batted_ball_physics.gd")

const PIN_TOLERANCE := 0.000000000001
const LANDING_SPECS := [
	[110.0, 28.0, 0.0],
	[105.0, 25.0, -15.0],
	[95.0, 15.0, 20.0],
	[100.0, 50.0, 0.0],
	[75.0, 8.0, 0.0],
	[60.0, 70.0, 0.0],
]
const LANDING_PINS := [
	[5.4333333333333194, 0.0, 401.0],
	[4.7666666666666551, -96.833738368840017, 363.38843147934239],
	[2.6166666666666623, 84.431479731934303, 233.97358405463024],
	[7.0666666666666469, 0.0, 344.20814178809655],
	[1.2000000000000006, 0.0, 113.89729108761377],
	[4.9333333333333211, 0.0, 112.35010931604592],
]
const WALL_PIN := [
	4.4833333333333227,
	136.48859823838868,
	339.81830851051956,
	5.5896250149502631,
]

var _failures: Array[String] = []


func _init() -> void:
	_test_landing_pins()
	_test_wall_carom_pin()
	_test_bounce_roll_stop()
	_test_prediction_is_exact_lookahead()
	_test_snapshot_and_report_contract()
	_test_classification()
	_test_live_advance_contract()
	_test_acceptance_monotonicity()

	var exit_code := 0
	if _failures.is_empty():
		print("PIXIBALL_BATTED_BALL_PHYSICS_OK pins=%d" % LANDING_PINS.size())
	else:
		for failure in _failures:
			push_error(failure)
		exit_code = 1
	quit(exit_code)


func _test_landing_pins() -> void:
	for index in range(LANDING_SPECS.size()):
		var spec: Array = LANDING_SPECS[index]
		var path := Ball.predict_path(Ball.launch(_spec(spec[0], spec[1], spec[2])))
		var landing := Ball.landing_of(path)
		var pin: Array = LANDING_PINS[index]
		_check(_near(float(landing.t), float(pin[0])), "landing pin %d time changed" % index)
		_check(_near(float(landing.x), float(pin[1])), "landing pin %d x changed" % index)
		_check(_near(float(landing.y), float(pin[2])), "landing pin %d y changed" % index)


func _test_wall_carom_pin() -> void:
	var path := Ball.predict_path(Ball.launch(_spec(106.0, 24.0, 22.0)))
	var wall: Dictionary = {}
	for sample in path:
		if bool(sample.wall):
			wall = sample
			break
	_check(not wall.is_empty(), "the pulled 106 mph drive should bang the right-field wall")
	if wall.is_empty():
		return
	_check(int(wall.mode) == Ball.MODE_AIR and int(wall.bounces) == 0,
		"the pinned wall carom should happen on the fly")
	_check(_near(float(wall.t), WALL_PIN[0]), "wall pin time changed")
	_check(_near(float(wall.x), WALL_PIN[1]), "wall pin x changed")
	_check(_near(float(wall.y), WALL_PIN[2]), "wall pin y changed")
	_check(_near(float(wall.z), WALL_PIN[3]), "wall pin z changed")


func _test_bounce_roll_stop() -> void:
	var state := Ball.launch(_spec(90.0, -5.0, 0.0))
	var bounced := false
	var saw_roll := false
	var previous_t := float(state.t)
	for step in range(30 * 60):
		if int(state.mode) == Ball.MODE_STOPPED:
			break
		Ball.step_ball(state)
		_check(float(state.t) > previous_t, "moving ball time must advance at step %d" % step)
		previous_t = float(state.t)
		_check(_finite_state(state), "ball state must remain finite at step %d" % step)
		if int(state.bounces) > 0:
			bounced = true
			_check(float(state.lift) == 0.0, "spin lift must be spent after the first bounce")
		saw_roll = saw_roll or int(state.mode) == Ball.MODE_ROLL
	_check(bounced, "the pinned chopper should bounce")
	_check(saw_roll, "the pinned chopper should transition through roll")
	_check(int(state.mode) == Ball.MODE_STOPPED, "the pinned chopper should stop inside 30 seconds")


func _test_prediction_is_exact_lookahead() -> void:
	var state := Ball.launch(_spec(102.0, 22.0, -10.0))
	var before := Ball.snapshot(state)
	var path := Ball.predict_path(state)
	_check(state == before, "predict_path must not mutate the supplied state")
	_check(path.size() >= 2, "prediction should contain post-step samples")
	var stepped := Ball.from_snapshot(before)
	for index in range(path.size() - 1):
		Ball.step_ball(stepped)
		_check(Ball.sample_of(stepped) == path[index],
			"predict_path and step_ball diverged at sample %d" % index)
	_check(Ball.sample_of(stepped) == path[-1],
		"the trailing prediction sample should duplicate the final state")


func _test_snapshot_and_report_contract() -> void:
	var state := Ball.launch({"LaunchSpeed": 96.0, "LaunchAngle": 18.0, "SprayDeg": -7.0})
	for unused in range(60):
		Ball.step_ball(state)
	_check(_near(float(state.t), 1.0), "sixty default steps should represent one second")
	var saved := Ball.snapshot(state)
	_check(saved == Ball.from_snapshot(saved), "state snapshots should round-trip exactly")
	var report := Ball.predict(_spec(95.0, 15.0, 20.0))
	_check(report.has("path") and report.has("landing") and report.has("classification_detail"),
		"aggregate prediction should expose the integration contract")
	_check((report.predicted_landing_ft as Array).size() == 3,
		"aggregate prediction should expose a three-coordinate landing")
	_check(float(report.carry_ft) > 0.0 and float(report.hang_time_sec) > 0.0,
		"aggregate prediction should expose carry and hang time")


func _test_classification() -> void:
	var homer := Ball.predict(_spec(110.0, 28.0, 0.0))
	_check(String(homer.classification) == "home_run", "an airborne center-field fence crossing should be a home run")
	_check(bool(homer.classification_detail.wall),
		"a full look-ahead may later clamp the home-run path to the wall without erasing the crossing")
	var carom := Ball.predict(_spec(106.0, 24.0, 22.0))
	_check(String(carom.classification) == "wall",
		"a below-wall-top fence strike should be a wall carom, got %s" % String(carom.classification))
	var foul := Ball.predict(_spec(90.0, 20.0, 50.0))
	_check(String(foul.classification) == "foul" and not bool(foul.classification_detail.fair),
		"a trajectory beyond the foul line should classify foul")
	var deep_foul := Ball.predict(_spec(115.0, 30.0, -55.0))
	_check(String(deep_foul.classification) == "foul",
		"a deep foul must not become fair when fence clamping changes its final coordinates")
	var fair := Ball.predict(_spec(75.0, 8.0, 0.0))
	_check(String(fair.classification) == "fair_ball", "an ordinary ball landing on grass should remain fair")


func _test_live_advance_contract() -> void:
	var state := Ball.launch(_spec(110.0, 28.0, 0.0))
	var saw_home_run := false
	for unused in range(12 * 60):
		var tick := Ball.advance(state)
		_check(tick.state == Ball.snapshot(state), "advance should return the exact post-step snapshot")
		if String(tick.classification) == "home_run":
			saw_home_run = true
			_check(not bool(tick.classification_detail.wall),
				"live home-run classification must occur before any later wall clamp")
			break
	_check(saw_home_run, "the live integration API should surface an over-fence event")

	state = Ball.launch(_spec(106.0, 24.0, 22.0))
	var saw_wall := false
	for unused in range(12 * 60):
		var tick := Ball.advance(state)
		if String(tick.classification) == "wall":
			saw_wall = true
			break
	_check(saw_wall, "the live integration API should surface a wall-carom event")


func _test_acceptance_monotonicity() -> void:
	var previous_carry := 0.0
	for exit_velocity in [80.0, 95.0, 110.0]:
		var landing := Ball.predicted_landing(Ball.launch(_spec(exit_velocity, 28.0, 0.0)))
		var carry := sqrt(float(landing.x) * float(landing.x) + float(landing.y) * float(landing.y))
		_check(carry > previous_carry, "carry should increase with exit velocity")
		previous_carry = carry
	var previous_time := 0.0
	for launch_angle in [10.0, 20.0, 30.0]:
		var landing := Ball.predicted_landing(Ball.launch(_spec(100.0, launch_angle, 0.0)))
		_check(float(landing.t) > previous_time, "hang time should increase with launch angle")
		previous_time = float(landing.t)


func _spec(exit_velocity: Variant, launch_angle: Variant, spray: Variant) -> Dictionary:
	return {
		"launch_speed_mph": float(exit_velocity),
		"launch_angle_deg": float(launch_angle),
		"spray_deg": float(spray),
	}


func _finite_state(state: Dictionary) -> bool:
	for key in ["x", "y", "z", "vx", "vy", "vz"]:
		if not is_finite(float(state[key])):
			return false
	return true


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) <= PIN_TOLERANCE


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
