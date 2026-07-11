extends SceneTree

const LivePlay = preload("res://gameplay/live_play_controller.gd")
const BallPhysics = preload("res://core/fielding/batted_ball_physics.gd")
const ParkGeometry = preload("res://core/fielding/park_geometry.gd")


class FakeBall extends Node3D:
	var active := false
	var last_position := Vector3.ZERO

	func set_active(value: bool) -> void:
		active = value

	func set_ball_position(value: Vector3) -> void:
		last_position = value
		global_position = value


class FakePlayer extends Node3D:
	var highlighted := false
	var action := "idle"
	var motion := Vector3.ZERO

	func set_highlighted(value: bool) -> void:
		highlighted = value

	func set_motion(value: Vector3) -> void:
		motion = value

	func set_facing(_value: Vector3) -> void:
		pass

	func play_action(value: String) -> void:
		action = value

	func get_socket_position(_socket_name: String) -> Vector3:
		return global_position + Vector3.UP * 1.2


var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_prediction_contract_uses_exact_park()
	_test_live_ticks_match_pure_physics()
	_test_substeps_preserve_fixed_tick_state()
	_test_wall_carom_stays_live()
	_test_home_run_completes_on_crossing_tick()
	_test_reset_clears_previous_play_state()
	_test_non_controlled_fielder_can_pick_up()
	_test_throw_meter_and_deterministic_overthrow()
	_test_force_at_second_and_double_play()
	_test_fielders_choice_preserves_batter()
	_test_cpu_throw_reads_runner_state()
	_test_manual_runner_advancement_api()
	_test_difficulty_changes_cpu_route()
	_test_cpu_ground_play_runs_end_to_end()

	var exit_code := 0
	if _failures.is_empty():
		print("PIXIBALL_LIVE_PLAY_FIDELITY_OK exact_ticks=60 wall=verified force=verified double_play=verified overthrow=verified")
	else:
		for failure in _failures:
			push_error(failure)
		exit_code = 1
	quit(exit_code)


func _test_prediction_contract_uses_exact_park() -> void:
	var expected := BallPhysics.predict(_spec(106.0, 24.0, 22.0))
	# The simulation currently emits these two legacy spellings. Keep this
	# boundary covered so exact flight cannot silently fall back to a zero-speed,
	# dead-centre launch when the pure physics API stays canonical.
	var contact := {
		"exit_velocity_mph": 106.0,
		"launch_angle_deg": 24.0,
		"spray_angle_deg": 22.0,
	}
	var fixture := _make_controller(contact)
	var controller: PixiballLivePlayController = fixture.controller
	_check(String(controller.trajectory.classification_hint) == String(expected.classification),
		"begin must replace the arcade classification hint with the exact path classification")
	_check(_near(float(controller.trajectory.carry_ft), float(expected.carry_ft)),
		"begin must expose exact predicted carry")
	_check(_near(float(controller.trajectory.hang_time_sec), float(expected.hang_time_sec)),
		"begin must expose exact predicted hang time")
	_check(_near(float(controller.trajectory.fence_distance_ft), ParkGeometry.fence_distance(22.0)),
		"begin must query the ported park fence instead of the old radial approximation")
	_check(_near(float(controller.trajectory.fence_height_ft), ParkGeometry.fence_height(22.0)),
		"begin must expose the park wall height used by the integrator")
	_cleanup(fixture)


func _test_live_ticks_match_pure_physics() -> void:
	var spec := _spec(96.0, 18.0, -7.0)
	var expected := BallPhysics.launch(spec)
	var fixture := _make_controller(spec)
	var controller: PixiballLivePlayController = fixture.controller
	for unused in range(60):
		BallPhysics.step_ball(expected)
		controller._physics_process(BallPhysics.BALL_DT)
	_check(controller.state().ball_physics == BallPhysics.snapshot(expected),
		"sixty live controller ticks must equal sixty pure batted-ball ticks exactly")
	_cleanup(fixture)


func _test_substeps_preserve_fixed_tick_state() -> void:
	var spec := _spec(90.0, -5.0, 0.0)
	var fixed_fixture := _make_controller(spec)
	var split_fixture := _make_controller(spec)
	var fixed: PixiballLivePlayController = fixed_fixture.controller
	var split: PixiballLivePlayController = split_fixture.controller
	for unused in range(60):
		fixed._physics_process(BallPhysics.BALL_DT)
	for unused in range(120):
		split._physics_process(BallPhysics.BALL_DT * 0.5)
	_check(fixed.state().ball_physics == split.state().ball_physics,
		"render substeps must accumulate into the same frozen 60 Hz physics state")
	_cleanup(fixed_fixture)
	_cleanup(split_fixture)


func _test_wall_carom_stays_live() -> void:
	var fixture := _make_controller(_spec(106.0, 24.0, 22.0))
	var controller: PixiballLivePlayController = fixture.controller
	var results: Array[Dictionary] = []
	controller.completed.connect(func(result: Dictionary) -> void: results.append(result))
	for unused in range(12 * 60):
		controller._physics_process(BallPhysics.BALL_DT)
		if bool(controller.state().wall_seen):
			break
	_check(bool(controller.state().wall_seen), "the exact live path must surface a wall carom")
	_check(String(controller.state().ball_classification) == "wall",
		"the wall-crossing tick must retain the ported wall classification")
	_check(results.is_empty() and controller.active,
		"a below-wall-top carom must remain a live ball instead of becoming a home run")
	_cleanup(fixture)


func _test_home_run_completes_on_crossing_tick() -> void:
	var spec := _spec(110.0, 28.0, 0.0)
	var expected := BallPhysics.launch(spec)
	var expected_ticks := 0
	for unused in range(12 * 60):
		expected_ticks += 1
		var tick := BallPhysics.advance(expected)
		if String(tick.classification) == "home_run":
			break

	var fixture := _make_controller(spec)
	var controller: PixiballLivePlayController = fixture.controller
	var results: Array[Dictionary] = []
	controller.completed.connect(func(result: Dictionary) -> void: results.append(result))
	var actual_ticks := 0
	while actual_ticks < 12 * 60 and results.is_empty():
		actual_ticks += 1
		controller._physics_process(BallPhysics.BALL_DT)
	_check(results.size() == 1, "an over-fence path must complete exactly once")
	if not results.is_empty():
		_check(String(results[0].classification) == "home_run", "over-fence completion must report home_run")
	_check(actual_ticks == expected_ticks,
		"live home-run completion must happen on the pure integrator's crossing tick")
	_check(controller.state().ball_physics == BallPhysics.snapshot(expected),
		"home-run completion must preserve the exact crossing state for presentation and agents")
	_cleanup(fixture)


func _test_reset_clears_previous_play_state() -> void:
	var fixture := _make_controller(_spec(96.0, 18.0, 0.0))
	var controller: PixiballLivePlayController = fixture.controller
	for unused in range(12):
		controller._physics_process(BallPhysics.BALL_DT)
	controller.reset()
	var state: Dictionary = controller.state()
	_check(not bool(state.active) and String(state.phase) == "idle", "reset must return to an inactive idle state")
	_check(float(state.elapsed) == 0.0 and (state.ball_physics as Dictionary).is_empty(),
		"reset must not leak elapsed time or exact ball state into the next play")
	_check(controller.trajectory.is_empty() and controller.bounce_count == 0 and not controller.landed,
		"reset must clear cached prediction and contact state")
	_cleanup(fixture)


func _test_non_controlled_fielder_can_pick_up() -> void:
	var fixture := _make_defense_fixture(
		_spec(76.0, -8.0, 0.0),
		{
			"center": Vector3(30.0, 0.08, -30.0),
			"first": Vector3(2.0, 0.08, 2.0),
		},
		true,
	)
	var controller: PixiballLivePlayController = fixture.controller
	var first: FakePlayer = fixture.players.first
	controller._set_controlled("center")
	controller._ball_state["mode"] = BallPhysics.MODE_ROLL
	controller._ball_state["bounces"] = 1
	controller._ball_state["z"] = 0.0
	controller.ball_position = first.global_position + Vector3.UP * 0.35
	controller._check_fielding()
	_check(controller._pickup_candidate == first,
		"a non-controlled defender in range must begin the ground-ball pickup")
	controller._update_pickup(controller.PICKUP_SEC + 0.001)
	_check(controller.holder == first and controller.holder_key == "first",
		"the non-controlled defender must complete pickup and become the carrier")
	_check(String(controller.state().phase) == "possession",
		"a CPU teammate pickup must advance the play to possession")
	_cleanup(fixture)


func _test_throw_meter_and_deterministic_overthrow() -> void:
	var positions := {
		"short": Vector3(-7.5, 0.08, -8.5),
		"first": PixiballConstants.FIRST_BASE,
	}
	var clean_fixture := _make_defense_fixture(_spec(80.0, -5.0, 0.0), positions, true, {"seed": 771})
	var clean: PixiballLivePlayController = clean_fixture.controller
	clean.holder = clean_fixture.players.short
	clean.holder_key = "short"
	clean.phase = "possession"
	_check(clean.press_throw(1), "press_throw must begin a held throw from possession")
	clean._update_possession(clean.THROW_METER_SEC * 0.5)
	_check(_near(clean.throw_meter_position, 0.5), "the throw meter must sweep by held time")
	_check(clean.release_throw(1), "release_throw must launch the charged throw")
	_check(clean.throw_error_ft < clean.THROW_CLEAN_ERROR_FT,
		"a centre-green release must produce a catchable deterministic error")
	clean._update_throw(clean.throw_duration)
	_check(clean.holder == clean_fixture.players.first and String(clean.phase) == "possession",
		"a covered, accurate throw must transfer possession to the fielder at the bag")
	_check(_event_count(clean.state().events, "throw") == 1,
		"one meter release must emit exactly one throw event")
	_cleanup(clean_fixture)

	var wild_fixture := _make_defense_fixture(_spec(80.0, -5.0, 0.0), positions, true, {"seed": 771})
	var wild: PixiballLivePlayController = wild_fixture.controller
	wild.holder = wild_fixture.players.short
	wild.holder_key = "short"
	wild.phase = "possession"
	wild.press_throw(1)
	wild._update_possession(wild.THROW_METER_SEC)
	# The full sweep auto-releases at the red edge.
	_check(String(wild.phase) == "throw" and wild.throw_error_ft > wild.THROW_CLEAN_ERROR_FT,
		"holding through the meter must deterministically sail the throw")
	wild._update_throw(wild.throw_duration)
	_check(String(wild.phase) == "rolling" and not is_instance_valid(wild.holder),
		"an inaccurate throw must become a loose live ball instead of an inferred hit")
	_check(_has_event(wild.state().events, "overthrow"),
		"the live state must expose an overthrow event for presentation and agents")
	_check(_event_count(wild.state().events, "throw") == 1,
		"the red-edge auto-release must still emit exactly one throw event")
	_cleanup(wild_fixture)


func _test_force_at_second_and_double_play() -> void:
	var fixture := _make_defense_fixture(
		_spec(82.0, -7.0, 0.0),
		{"second": PixiballConstants.SECOND_BASE, "first": PixiballConstants.FIRST_BASE},
		false,
		{"bases": {"first": true}, "seed": 91},
	)
	var controller: PixiballLivePlayController = fixture.controller
	var lead_index := _runner_index(controller, "runner_1")
	var batter_index := controller._batter_runner_index()
	controller._runners[lead_index]["state"] = "advance"
	controller._runners[lead_index]["frac"] = 0.45
	controller._runners[lead_index]["forced"] = true
	controller._runners[batter_index]["state"] = "advance"
	controller._runners[batter_index]["frac"] = 0.28
	controller.holder = fixture.players.second
	controller.holder_key = "second"
	controller.phase = "possession"
	controller._resolve_outs()
	_check(controller._outs.size() == 1 and String(controller._outs[0].how) == "force" and int(controller._outs[0].base) == 2,
		"touching second must retire the forced lead runner, not automatically the batter")
	_check(not controller._batter_out,
		"a non-1B force out must leave the batter-runner live for a fielder's choice")
	controller.holder = fixture.players.first
	controller.holder_key = "first"
	controller._resolve_outs()
	_check(controller._outs.size() == 2 and controller._batter_out,
		"a relay to first before the batter must complete the double play")
	var results: Array[Dictionary] = []
	controller.completed.connect(func(result: Dictionary) -> void: results.append(result))
	controller._finish_settled()
	_check(results.size() == 1 and bool(results[0].double_play),
		"the settled result must report both outs as a double play")
	_cleanup(fixture)


func _test_fielders_choice_preserves_batter() -> void:
	var fixture := _make_defense_fixture(
		_spec(82.0, -7.0, 0.0),
		{"second": PixiballConstants.SECOND_BASE, "first": PixiballConstants.FIRST_BASE},
		false,
		{"bases": {"first": true}, "seed": 92},
	)
	var controller: PixiballLivePlayController = fixture.controller
	var lead_index := _runner_index(controller, "runner_1")
	var batter_index := controller._batter_runner_index()
	controller._runners[lead_index]["state"] = "advance"
	controller._runners[lead_index]["frac"] = 0.55
	controller._runners[lead_index]["forced"] = true
	controller._runners[batter_index]["state"] = "advance"
	controller._runners[batter_index]["frac"] = 0.9
	controller.holder = fixture.players.second
	controller.holder_key = "second"
	controller.phase = "possession"
	controller._resolve_outs()
	controller._runner_arrived(batter_index, 1)
	var results: Array[Dictionary] = []
	controller.completed.connect(func(result: Dictionary) -> void: results.append(result))
	controller._finish_settled()
	_check(results.size() == 1 and String(results[0].rule_classification) == "fielders_choice",
		"a force on the lead runner with the batter safe must classify as fielder's choice")
	if not results.is_empty():
		_check(not bool(results[0].batter_out) and bool(results[0].final_bases.first),
			"fielder's-choice final bases must retain the safe batter at first")
	_cleanup(fixture)


func _test_cpu_throw_reads_runner_state() -> void:
	var fixture := _make_defense_fixture(
		_spec(70.0, -10.0, 0.0),
		{"short": Vector3(-6.0, 0.08, -3.0), "second": PixiballConstants.SECOND_BASE},
		false,
		{"bases": {"first": true}, "seed": 101},
	)
	var controller: PixiballLivePlayController = fixture.controller
	var lead_index := _runner_index(controller, "runner_1")
	controller._runners[lead_index]["state"] = "advance"
	controller._runners[lead_index]["frac"] = 0.05
	controller._runners[lead_index]["forced"] = true
	controller.holder = fixture.players.short
	controller.holder_key = "short"
	controller.phase = "possession"
	controller.trajectory["carry_ft"] = 20.0
	var shallow_choice := controller._best_cpu_throw()
	controller.trajectory["carry_ft"] = 390.0
	var deep_choice := controller._best_cpu_throw()
	_check(shallow_choice == 2 and deep_choice == 2,
		"CPU throws must target the live force at second independent of carry thresholds")
	_cleanup(fixture)


func _test_manual_runner_advancement_api() -> void:
	var fixture := _make_defense_fixture(
		_spec(92.0, 5.0, 5.0),
		{"center": Vector3(1000.0, 0.08, 1000.0)},
		false,
		{"bases": {"first": true}, "user_runner_control": true, "seed": 202},
	)
	var controller: PixiballLivePlayController = fixture.controller
	_check(controller.command_selected_runner(2),
		"offense must be able to command its selected lead runner toward second")
	for unused in range(240):
		controller._update_runners(1.0 / 60.0)
	var lead_index := _runner_index(controller, "runner_1")
	var batter_index := controller._batter_runner_index()
	_check(int(controller._runners[lead_index].from_base) == 2 and String(controller._runners[lead_index].state) == "hold",
		"the commanded runner must advance to and settle on second")
	_check(int(controller._runners[batter_index].from_base) == 1,
		"the forced batter-runner must independently reach first")
	var bounded: Dictionary = controller.runner_state()
	_check(bounded.has("runners") and bounded.has("bases") and bool(bounded.bases.first) and bool(bounded.bases.second),
		"runner_state must expose a bounded, serializable first-and-second base snapshot")
	_cleanup(fixture)


func _test_difficulty_changes_cpu_route() -> void:
	var positions := {"center": Vector3(0.0, 0.08, 20.0)}
	var easy_fixture := _make_defense_fixture(_spec(96.0, 16.0, 0.0), positions, false, {"difficulty": 0.0})
	var hard_fixture := _make_defense_fixture(_spec(96.0, 16.0, 0.0), positions, false, {"difficulty": 1.0})
	var easy: PixiballLivePlayController = easy_fixture.controller
	var hard: PixiballLivePlayController = hard_fixture.controller
	var easy_start: Vector3 = easy_fixture.players.center.global_position
	var hard_start: Vector3 = hard_fixture.players.center.global_position
	easy._update_fielders(0.5)
	hard._update_fielders(0.5)
	var easy_distance := easy_start.distance_to(easy_fixture.players.center.global_position)
	var hard_distance := hard_start.distance_to(hard_fixture.players.center.global_position)
	_check(hard_distance > easy_distance + 0.2,
		"higher difficulty must deterministically improve CPU route pace")
	_cleanup(easy_fixture)
	_cleanup(hard_fixture)


func _test_cpu_ground_play_runs_end_to_end() -> void:
	var fixture := _make_defense_fixture(
		_spec(84.0, -7.0, 0.0),
		{
			"pitcher": PixiballConstants.PITCHER_MOUND,
			"catcher": PixiballConstants.DEFENSIVE_POSITIONS.catcher,
			"first": PixiballConstants.DEFENSIVE_POSITIONS.first,
			"second": PixiballConstants.DEFENSIVE_POSITIONS.second,
			"short": PixiballConstants.DEFENSIVE_POSITIONS.short,
			"third": PixiballConstants.DEFENSIVE_POSITIONS.third,
			"left": PixiballConstants.DEFENSIVE_POSITIONS.left,
			"center": PixiballConstants.DEFENSIVE_POSITIONS.center,
			"right": PixiballConstants.DEFENSIVE_POSITIONS.right,
		},
		false,
		{"difficulty": 0.8, "seed": 303},
	)
	var controller: PixiballLivePlayController = fixture.controller
	var results: Array[Dictionary] = []
	controller.completed.connect(func(result: Dictionary) -> void: results.append(result))
	for unused in range(12 * 60):
		controller._physics_process(1.0 / 60.0)
		if not results.is_empty():
			break
	_check(results.size() == 1,
		"a complete CPU defense must field and settle a routine ground ball without a carry heuristic")
	_check(_has_event(controller.state().events, "pickup"),
		"the end-to-end CPU ground play must include a physical pickup")
	_check(_has_event(controller.state().events, "throw"),
		"the end-to-end CPU ground play must include a runner-aware throw")
	if not results.is_empty():
		_check(String(results[0].rule_classification) in ["ground_out", "single"],
			"the physical race must settle as a ground out or safe single")
	_cleanup(fixture)


func _make_controller(spec: Dictionary) -> Dictionary:
	var controller := LivePlay.new() as PixiballLivePlayController
	var ball := FakeBall.new()
	var player := FakePlayer.new()
	player.position = Vector3(1000.0, 0.0, 1000.0)
	root.add_child(controller)
	root.add_child(ball)
	root.add_child(player)
	controller.set_physics_process(false)
	controller.begin(spec, ball, {"center": player}, true)
	return {"controller": controller, "ball": ball, "player": player}


func _make_defense_fixture(
	spec: Dictionary,
	positions: Dictionary,
	user_fielding: bool,
	context: Dictionary = {},
) -> Dictionary:
	var controller := LivePlay.new() as PixiballLivePlayController
	var ball := FakeBall.new()
	var players := {}
	root.add_child(controller)
	root.add_child(ball)
	for key_value in positions:
		var key := String(key_value)
		var player := FakePlayer.new()
		player.position = positions[key]
		root.add_child(player)
		players[key] = player
	controller.set_physics_process(false)
	controller.begin(spec, ball, players, user_fielding, context)
	return {"controller": controller, "ball": ball, "players": players}


func _cleanup(fixture: Dictionary) -> void:
	for key in ["controller", "ball", "player"]:
		if not fixture.has(key):
			continue
		var node: Node = fixture[key]
		if is_instance_valid(node):
			node.free()
	if fixture.has("players"):
		for player_value in (fixture.players as Dictionary).values():
			var player: Node = player_value
			if is_instance_valid(player):
				player.free()


func _spec(exit_velocity: float, launch_angle: float, spray: float) -> Dictionary:
	return {
		"launch_speed_mph": exit_velocity,
		"launch_angle_deg": launch_angle,
		"spray_deg": spray,
	}


func _near(actual: float, expected: float) -> bool:
	return absf(actual - expected) <= 0.000000000001


func _runner_index(controller: PixiballLivePlayController, slot: String) -> int:
	for index in range(controller._runners.size()):
		if String(controller._runners[index].get("slot", "")) == slot:
			return index
	return -1


func _has_event(events: Array, type: String) -> bool:
	for event_value in events:
		if event_value is Dictionary and String((event_value as Dictionary).get("type", "")) == type:
			return true
	return false


func _event_count(events: Array, type: String) -> int:
	var count := 0
	for event_value in events:
		if event_value is Dictionary and String((event_value as Dictionary).get("type", "")) == type:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
