class_name PixiballLivePlayController
extends Node

signal completed(result: Dictionary)
signal phase_changed(phase: String)

const C = preload("res://gameplay/game_constants.gd")
const BattedBallPhysics = preload("res://core/fielding/batted_ball_physics.gd")
const ParkGeometry = preload("res://core/fielding/park_geometry.gd")

# The authoritative ball stays in feet. Only the presentation boundary uses
# world units, so batted-ball ticks remain byte-for-byte comparable with the
# pure PixCore port.
const FEET_TO_WORLD := ParkGeometry.HORIZONTAL_WORLD_PER_FOOT
const VERTICAL_FEET_TO_WORLD := ParkGeometry.VERTICAL_WORLD_PER_FOOT

const THROW_METER_SEC := 0.8
const THROW_METER_GREEN_LO := 0.38
const THROW_METER_GREEN_HI := 0.62
const THROW_CLEAN_ERROR_FT := 4.5
const THROW_WINDUP_SEC := 0.32
const THROW_IF_FPS := 118.0
const THROW_OF_FPS := 132.0
const OVERTHROW_SKIP_FPS := 28.0
const PICKUP_SEC := 0.28
const DEAD_HOLD_SEC := 0.5
const MAX_PLAY_SEC := 30.0
const VISUAL_CONTACT_BLEND_SEC := 0.08
const BASE_TOUCH_WORLD := 0.72
const TAG_RADIUS_WORLD := 0.92
const COVER_RADIUS_WORLD := 1.4
const DEFAULT_RUNNER_SPEED_WORLD := 7.6

var active := false
var user_fielding := false
var phase := "idle"
var ball: Node3D
var defenders: Dictionary = {}
var controlled_key := ""
var controlled_player: Node3D
var trajectory: Dictionary = {}
var start_position := Vector3.ZERO
var landing_position := Vector3.ZERO
var ball_position := Vector3.ZERO
var ball_velocity := Vector3.ZERO
var _visual_launch_offset := Vector3.ZERO
var elapsed := 0.0
var hang_time := 1.5
var landed := false
var bounce_count := 0
var holder: Node3D
var holder_key := ""
var throw_base := -1
var throw_elapsed := 0.0
var throw_duration := 0.6
var throw_start := Vector3.ZERO
var throw_end := Vector3.ZERO
var throw_error_ft := 0.0
var throw_accuracy := "idle"
var throw_charging := false
var throw_charge_time := 0.0
var throw_meter_position := 0.0
var pickup_wait := 0.0

var _input_vector := Vector2.ZERO
var _completion_sent := false
var _ball_state: Dictionary = {}
var _ball_prediction: Dictionary = {}
var _ball_accumulator := 0.0
var _ball_classification := "unknown"
var _wall_seen := false
var _play_context: Dictionary = {}
var _next_play_context: Dictionary = {}
var _difficulty := 0.5
var _outs_before := 0
var _play_seed := 1
var _rng := RandomNumberGenerator.new()
var _throw_count := 0
var _auto_release_throw := false
var _possession_elapsed := 0.0
var _dead_timer := 0.0
var _pickup_candidate: Node3D
var _pickup_candidate_key := ""
var _pickup_elapsed := 0.0
var _fielder_home: Dictionary = {}
var _runners: Array[Dictionary] = []
var _selected_runner := 0
var _manual_runner_control := false
var _outs: Array[Dictionary] = []
var _scored_slots: Array = []
var _batter_base := 0
var _batter_out := false
var _fly_caught := false
var _runs_voided := false
var _events: Array[Dictionary] = []


## Supplies the runner/rule context for the next begin() without changing the
## original four-argument call site. Values are copied and bounded at begin.
## Supported keys: bases, difficulty, outs_before, seed, runner_speed,
## runner_slots, and user_runner_control.
func configure_play_state(context: Dictionary) -> void:
	_next_play_context = context.duplicate(true)


## The optional context is additive; existing callers can keep the original
## begin(contact, ball, defense, user_controls) contract.
func begin(
	contact: Dictionary,
	ball_visual: Node3D,
	defense: Dictionary,
	user_controls: bool,
	context: Dictionary = {},
) -> void:
	var queued_context := _next_play_context.duplicate(true)
	reset()
	active = true
	phase = "flight"
	trajectory = contact.duplicate(true)
	ball = ball_visual
	# Keep our own container: reset() must never clear the game's cast registry.
	defenders = defense.duplicate()
	user_fielding = user_controls
	_configure_context(contact, queued_context, context)
	_ball_state = BattedBallPhysics.launch(_launch_spec(contact))
	_ball_prediction = BattedBallPhysics.predict(_ball_state)
	_apply_prediction_to_trajectory()
	start_position = _field_state_to_world(_ball_state)
	landing_position = _field_sample_to_world(_ball_prediction.get("landing", {}))
	hang_time = maxf(BattedBallPhysics.BALL_DT, float(_ball_prediction.get("hang_time_sec", 0.0)))
	ball_velocity = _field_velocity_to_world(_ball_state)
	ball_position = start_position
	var visual_contact: Variant = context.get("visual_contact_world", start_position)
	_visual_launch_offset = (visual_contact as Vector3) - start_position if visual_contact is Vector3 else Vector3.ZERO
	if is_instance_valid(ball):
		ball.call("set_active", true)
		ball.call("set_ball_position", _visual_ball_position())
	_cache_fielder_home()
	_build_runners()
	_select_best_fielder()
	phase_changed.emit(phase)


func reset() -> void:
	if is_instance_valid(controlled_player) and controlled_player.has_method("set_highlighted"):
		controlled_player.call("set_highlighted", false)
	active = false
	phase = "idle"
	ball = null
	defenders = {}
	controlled_key = ""
	controlled_player = null
	trajectory = {}
	start_position = Vector3.ZERO
	landing_position = Vector3.ZERO
	ball_position = Vector3.ZERO
	ball_velocity = Vector3.ZERO
	_visual_launch_offset = Vector3.ZERO
	elapsed = 0.0
	hang_time = 0.0
	landed = false
	bounce_count = 0
	holder = null
	holder_key = ""
	throw_base = -1
	throw_elapsed = 0.0
	throw_duration = 0.6
	throw_start = Vector3.ZERO
	throw_end = Vector3.ZERO
	throw_error_ft = 0.0
	throw_accuracy = "idle"
	throw_charging = false
	throw_charge_time = 0.0
	throw_meter_position = 0.0
	pickup_wait = 0.0
	_input_vector = Vector2.ZERO
	_completion_sent = false
	_ball_state = {}
	_ball_prediction = {}
	_ball_accumulator = 0.0
	_ball_classification = "unknown"
	_wall_seen = false
	_play_context = {}
	_next_play_context = {}
	_difficulty = 0.5
	_outs_before = 0
	_play_seed = 1
	_throw_count = 0
	_auto_release_throw = false
	_possession_elapsed = 0.0
	_dead_timer = 0.0
	_pickup_candidate = null
	_pickup_candidate_key = ""
	_pickup_elapsed = 0.0
	_fielder_home = {}
	_runners = []
	_selected_runner = 0
	_manual_runner_control = false
	_outs = []
	_scored_slots = []
	_batter_base = 0
	_batter_out = false
	_fly_caught = false
	_runs_voided = false
	_events = []


func set_move_input(value: Vector2) -> void:
	_input_vector = value.limit_length(1.0)


## Backwards-compatible tap throw. It enters the same hold/release meter as a
## real input, then releases automatically at its exact centre. Main can wire
## press_throw()/release_throw() to expose the complete skill mechanic.
func request_throw(base_index: int) -> void:
	if press_throw(base_index):
		_auto_release_throw = true


func press_throw(base_index: int) -> bool:
	if not active or phase != "possession" or not is_instance_valid(holder):
		return false
	if base_index < 0 or base_index > 3 or throw_charging:
		return false
	throw_base = base_index
	throw_charging = true
	throw_charge_time = 0.0
	throw_meter_position = 0.0
	throw_accuracy = "charging"
	_auto_release_throw = false
	_possession_elapsed = 0.0
	if holder.has_method("play_action"):
		holder.call("play_action", "throw")
	return true


func release_throw(base_index: int = -1) -> bool:
	if not throw_charging or phase != "possession":
		return false
	if base_index >= 0 and base_index != throw_base:
		return false
	var error_ft := _meter_error_ft(throw_meter_position)
	throw_charging = false
	_auto_release_throw = false
	_start_throw(error_ft)
	return true


func cycle_fielder() -> void:
	if not active or defenders.is_empty():
		return
	var ranked := _ranked_fielder_keys(_playable_target())
	if ranked.is_empty():
		return
	var current := ranked.find(controlled_key)
	_set_controlled(String(ranked[(current + 1) % ranked.size()]))


## Offense runner controls mirror the original pad-diamond contract. Home is
## index 0, then first/second/third. Calling this opts the play into manual
## runner control; untouched games retain bounded CPU assistance.
func command_selected_runner(base_index: int) -> bool:
	if not active or user_fielding or base_index < 0 or base_index > 3:
		return false
	var live := _commandable_runner_indices()
	if live.is_empty():
		return false
	_manual_runner_control = true
	_selected_runner = clampi(_selected_runner, 0, live.size() - 1)
	_command_runner(int(live[_selected_runner]), base_index)
	return true


func command_runner(base_index: int) -> bool:
	return command_selected_runner(base_index)


func cycle_runner(direction: int = 1) -> bool:
	if not active or user_fielding:
		return false
	var live := _commandable_runner_indices()
	if live.is_empty():
		return false
	_manual_runner_control = true
	var step := -1 if direction < 0 else 1
	_selected_runner = posmod(_selected_runner + step, live.size())
	return true


func select_runner(index: int) -> bool:
	var live := _commandable_runner_indices()
	if user_fielding or index < 0 or index >= live.size():
		return false
	_manual_runner_control = true
	_selected_runner = index
	return true


func runner_state() -> Dictionary:
	var snapshots: Array[Dictionary] = []
	for runner in _runners:
		var entry := runner.duplicate(true)
		var position := _runner_position(runner)
		entry["position"] = [position.x, position.y, position.z]
		snapshots.append(entry)
	return {
		"manual_control": _manual_runner_control,
		"selected": _selected_runner,
		"runners": snapshots,
		"bases": _final_bases_snapshot(),
		"outs": _outs.duplicate(true),
		"runs": 0 if _runs_voided else _scored_slots.size(),
	}


func state() -> Dictionary:
	return {
		"active": active,
		"phase": phase,
		"elapsed": elapsed,
		"ball_position": [ball_position.x, ball_position.y, ball_position.z],
		"landing_position": [landing_position.x, landing_position.y, landing_position.z],
		"ball_physics": BattedBallPhysics.snapshot(_ball_state) if not _ball_state.is_empty() else {},
		"ball_classification": _ball_classification,
		"wall_seen": _wall_seen,
		"controlled_fielder": controlled_key,
		"holder": holder_key,
		"pickup_fielder": _pickup_candidate_key,
		"throw_base": throw_base,
		"throw_charging": throw_charging,
		"throw_meter": throw_meter_position if throw_charging else 0.0,
		"throw_error_ft": throw_error_ft,
		"throw_accuracy": throw_accuracy,
		"difficulty": _difficulty,
		"runner_state": runner_state(),
		"events": _events.duplicate(true),
	}


func _physics_process(delta: float) -> void:
	if not active:
		return
	elapsed += delta
	match phase:
		"flight", "rolling":
			_update_ball(delta)
			if not active:
				return
			_update_fielders(delta)
			_update_pickup(delta)
			_check_fielding()
		"possession":
			_update_fielders(delta)
			_update_possession(delta)
		"throw":
			_update_fielders(delta)
			_update_throw(delta)
	if not active:
		return
	_update_runners(delta)
	if not active:
		return
	_resolve_outs()
	if active:
		_check_dead(delta)


func _update_ball(delta: float) -> void:
	if _ball_state.is_empty():
		return
	_ball_accumulator += delta
	while _ball_accumulator + 0.000000001 >= BattedBallPhysics.BALL_DT:
		_ball_accumulator -= BattedBallPhysics.BALL_DT
		var previous_bounces := int(_ball_state.get("bounces", 0))
		var tick: Dictionary = BattedBallPhysics.advance(_ball_state)
		_ball_classification = String(tick.get("classification", "unknown"))
		bounce_count = int(_ball_state.get("bounces", 0))
		if not _wall_seen and bool(_ball_state.get("wall", false)):
			_wall_seen = true
			landed = true
			_events.append({"type": "wall", "position": _field_xy_snapshot(_ball_state)})
			landing_position = _field_sample_to_world(BattedBallPhysics.predicted_landing(_ball_state))
			_on_ball_grounded()
		if not landed and (
			bounce_count > previous_bounces
			or int(_ball_state.get("mode", BattedBallPhysics.MODE_AIR)) != BattedBallPhysics.MODE_AIR
		):
			landed = true
			phase = "rolling"
			_events.append({"type": "bounce", "position": _field_xy_snapshot(_ball_state)})
			_on_ball_grounded()
			phase_changed.emit(phase)
		if _ball_classification == "home_run":
			ball_position = _field_state_to_world(_ball_state)
			if is_instance_valid(ball):
				ball.call("set_ball_position", _visual_ball_position())
			_home_run()
			return
	ball_position = _field_state_to_world(_ball_state)
	ball_velocity = _field_velocity_to_world(_ball_state)
	if is_instance_valid(ball):
		ball.call("set_ball_position", _visual_ball_position())


func _visual_ball_position() -> Vector3:
	var remaining := 1.0 - clampf(elapsed / VISUAL_CONTACT_BLEND_SEC, 0.0, 1.0)
	return ball_position + _visual_launch_offset * remaining


func _update_fielders(delta: float) -> void:
	if defenders.is_empty():
		return
	var pursuit_target := _playable_target()
	var ranked := _ranked_fielder_keys(pursuit_target)
	var primary := holder_key if phase in ["possession", "throw"] and not holder_key.is_empty() else (String(ranked[0]) if not ranked.is_empty() else "")
	var covers := _cover_assignments(primary)
	for key_value in defenders:
		var key := String(key_value)
		var player: Node3D = defenders[key]
		if not is_instance_valid(player):
			continue
		if player == holder or player == _pickup_candidate:
			_stop_fielder(player)
			continue
		var desired := Vector3.ZERO
		var motion_target := player.global_position
		var speed := _fielder_speed_world(key)
		var is_controlled := player == controlled_player and user_fielding
		if is_controlled and _input_vector.length() > 0.08:
			var assisted := _flat_direction(player.global_position, pursuit_target)
			var user_direction := Vector3(_input_vector.x, 0.0, _input_vector.y)
			desired = (user_direction * 0.82 + assisted * 0.18).normalized()
			motion_target = player.global_position + desired * 1000.0
			speed *= 1.05
		elif key == primary or (is_controlled and phase in ["flight", "rolling"]):
			desired = _flat_direction(player.global_position, pursuit_target)
			motion_target = pursuit_target
			var cpu_pace := lerpf(0.70, 0.94, _difficulty) if not user_fielding else 0.82
			speed *= cpu_pace
		elif key in covers.values():
			var cover_base := _base_for_coverer(covers, key)
			motion_target = C.base_position(cover_base)
			desired = _flat_direction(player.global_position, motion_target)
			speed *= 0.9
		elif ranked.find(key) == 1 and phase in ["flight", "rolling"]:
			# A second defender shades the play and can make a catch/pickup if the
			# primary misses; the rest retain shape instead of dogpiling.
			desired = _flat_direction(player.global_position, pursuit_target)
			motion_target = pursuit_target
			speed *= 0.58
		else:
			motion_target = _fielder_home.get(key, player.global_position)
			desired = _flat_direction(player.global_position, motion_target)
			speed *= 0.45
		var distance := _flat_distance(player.global_position, motion_target)
		var step := minf(speed * delta, distance) if distance > 0.0 else 0.0
		var motion := desired * (step / delta) if delta > 0.0 else Vector3.ZERO
		player.global_position += desired * step
		if player.has_method("set_motion"):
			player.call("set_motion", motion)
		if desired.length() > 0.1 and player.has_method("set_facing"):
			player.call("set_facing", desired)

func _update_pickup(delta: float) -> void:
	if not is_instance_valid(_pickup_candidate):
		return
	_pickup_elapsed += delta
	if _pickup_elapsed < PICKUP_SEC:
		return
	holder = _pickup_candidate
	holder_key = _pickup_candidate_key
	_pickup_candidate = null
	_pickup_candidate_key = ""
	_pickup_elapsed = 0.0
	phase = "possession"
	_possession_elapsed = 0.0
	pickup_wait = 0.0
	if is_instance_valid(ball):
		ball.call("set_active", false)
	if is_instance_valid(holder) and holder.has_method("play_action"):
		holder.call("play_action", "catch")
	_events.append({"type": "pickup", "fielder": holder_key})
	if user_fielding:
		_set_controlled(holder_key)
	phase_changed.emit(phase)


func _check_fielding() -> void:
	if is_instance_valid(holder) or is_instance_valid(_pickup_candidate):
		return
	var pristine_fly := (
		int(_ball_state.get("mode", BattedBallPhysics.MODE_STOPPED)) == BattedBallPhysics.MODE_AIR
		and int(_ball_state.get("bounces", 0)) == 0
		and not bool(_ball_state.get("wall", false))
	)
	var height_ft := float(_ball_state.get("z", 0.0))
	var best_player: Node3D
	var best_key := ""
	var best_distance := INF
	for key_value in defenders:
		var key := String(key_value)
		var player: Node3D = defenders[key]
		if not is_instance_valid(player):
			continue
		var target_height := 1.2 if pristine_fly else 0.45
		var target_3d := player.global_position + Vector3.UP * target_height
		var distance := target_3d.distance_to(ball_position)
		var cpu_scale := lerpf(0.82, 1.08, _difficulty) if not user_fielding else 1.0
		var radius := (1.65 if pristine_fly else 1.35) * cpu_scale
		if distance < radius and distance < best_distance:
			best_distance = distance
			best_player = player
			best_key = key
	if not is_instance_valid(best_player):
		return
	if pristine_fly and height_ft < 10.0 and float(_ball_state.get("t", 0.0)) > 0.3:
		_catch_fly(best_player, best_key, best_distance > 0.98)
	elif not pristine_fly and height_ft < 3.0:
		_pickup_candidate = best_player
		_pickup_candidate_key = best_key
		_pickup_elapsed = 0.0
		_stop_fielder(best_player)


func _catch_fly(player: Node3D, key: String, diving: bool) -> void:
	holder = player
	holder_key = key
	_fly_caught = true
	phase = "possession"
	_possession_elapsed = 0.0
	if is_instance_valid(ball):
		ball.call("set_active", false)
	if player.has_method("play_action"):
		player.call("play_action", "catch")
	_events.append({"type": "catch", "fielder": key, "diving": diving})
	var batter_index := _batter_runner_index()
	if batter_index >= 0:
		_record_out(batter_index, "flyout", -1)
	if not active:
		return
	_on_fly_caught()
	if user_fielding:
		_set_controlled(key)
	phase_changed.emit(phase)


func _update_possession(delta: float) -> void:
	pickup_wait += delta
	if throw_charging:
		throw_charge_time += delta
		throw_meter_position = minf(1.0, throw_charge_time / THROW_METER_SEC)
		if (_auto_release_throw and throw_meter_position >= 0.5) or throw_meter_position >= 1.0:
			release_throw()
		return
	_possession_elapsed += delta
	var target_base := _best_cpu_throw()
	if not user_fielding:
		if target_base >= 0 and _possession_elapsed >= THROW_WINDUP_SEC:
			throw_base = target_base
			_start_throw(_cpu_throw_error_ft(target_base))
	elif target_base >= 0 and _possession_elapsed >= 1.25:
		# Current main versions expose a tap button and autoplay. This bound keeps
		# those call sites live until press/release is wired by the shell.
		throw_base = target_base
		_start_throw(_cpu_throw_error_ft(target_base) * 0.65)


func _start_throw(error_ft: float) -> void:
	if not is_instance_valid(holder) or throw_base < 0 or throw_base > 3:
		return
	phase = "throw"
	throw_elapsed = 0.0
	throw_error_ft = maxf(0.0, error_ft)
	throw_accuracy = _throw_accuracy_label(throw_error_ft)
	throw_start = holder.call("get_socket_position", "throw_hand") if holder.has_method("get_socket_position") else holder.global_position + Vector3.UP * 1.6
	throw_end = C.base_position(throw_base) + Vector3.UP * 1.1
	var distance_world := _flat_distance(throw_start, throw_end)
	var throw_fps := THROW_OF_FPS if _is_outfielder(holder_key) else THROW_IF_FPS
	throw_duration = maxf(0.18, distance_world / (throw_fps * FEET_TO_WORLD))
	throw_duration = clampf(throw_duration, 0.18, 1.2)
	if holder.has_method("play_action"):
		holder.call("play_action", "throw")
	if is_instance_valid(ball):
		ball.call("set_active", true)
	_events.append({
		"type": "throw",
		"fielder": holder_key,
		"base": throw_base,
		"error_ft": throw_error_ft,
		"meter": throw_meter_position,
	})
	throw_charging = false
	throw_charge_time = 0.0
	throw_meter_position = 0.0
	_throw_count += 1
	phase_changed.emit(phase)


func _update_throw(delta: float) -> void:
	throw_elapsed += delta
	var u := clampf(throw_elapsed / throw_duration, 0.0, 1.0)
	var arc := sin(u * PI) * minf(5.0, throw_start.distance_to(throw_end) * 0.13)
	ball_position = throw_start.lerp(throw_end, u) + Vector3.UP * arc
	if is_instance_valid(ball):
		ball.call("set_ball_position", ball_position)
	if u >= 1.0:
		_arrive_throw()


func _arrive_throw() -> void:
	var target_base := throw_base
	var receiver := _coverer_at(target_base)
	var clean := throw_error_ft < THROW_CLEAN_ERROR_FT and is_instance_valid(receiver)
	var previous_holder := holder
	holder = null
	holder_key = ""
	if clean:
		holder = receiver
		holder_key = _key_for_player(receiver)
		phase = "possession"
		_possession_elapsed = 0.0
		pickup_wait = 0.0
		if is_instance_valid(ball):
			ball.call("set_active", false)
		_events.append({"type": "ball_at_base", "base": target_base, "caught": true, "fielder": holder_key})
		if user_fielding:
			_set_controlled(holder_key)
		_resolve_outs()
		if active:
			phase_changed.emit(phase)
		return
	_events.append({"type": "overthrow", "base": target_base, "error_ft": throw_error_ft})
	_make_overthrow_live(previous_holder, target_base)


func _make_overthrow_live(previous_holder: Node3D, base_index: int) -> void:
	var at := C.base_position(base_index)
	var from := throw_start
	if is_instance_valid(previous_holder):
		from = previous_holder.global_position
	var skip_direction := _flat_direction(from, at)
	if skip_direction.is_zero_approx():
		skip_direction = Vector3(0.0, 0.0, -1.0)
	var loose_world := at + skip_direction * maxf(0.15, throw_error_ft * FEET_TO_WORLD * 0.18)
	var loose_velocity := skip_direction * OVERTHROW_SKIP_FPS * FEET_TO_WORLD
	_ball_state = {
		"x": (loose_world.x - C.HOME_PLATE.x) / FEET_TO_WORLD,
		"y": -(loose_world.z - C.HOME_PLATE.z) / FEET_TO_WORLD,
		"z": 0.0,
		"vx": loose_velocity.x / FEET_TO_WORLD,
		"vy": -loose_velocity.z / FEET_TO_WORLD,
		"vz": 0.0,
		"mode": BattedBallPhysics.MODE_ROLL,
		"bounces": maxi(1, bounce_count),
		"lift": 0.0,
		"t": elapsed,
		"wall": false,
		"launch_speed_mph": float(trajectory.get("launch_speed_mph", trajectory.get("exit_velocity_mph", 0.0))),
		"launch_angle_deg": float(trajectory.get("launch_angle_deg", 0.0)),
		"spray_deg": float(trajectory.get("spray_deg", trajectory.get("spray_angle_deg", 0.0))),
	}
	_ball_prediction = BattedBallPhysics.predict(_ball_state)
	landing_position = _field_sample_to_world(_ball_prediction.get("landing", {}))
	ball_position = loose_world
	ball_velocity = loose_velocity
	landed = true
	phase = "rolling"
	_pickup_candidate = null
	_pickup_candidate_key = ""
	_pickup_elapsed = 0.0
	if is_instance_valid(ball):
		ball.call("set_active", true)
		ball.call("set_ball_position", ball_position)
	for runner in _runners:
		runner["cap_frac"] = -1.0
		if _cpu_controls_runner() and String(runner.get("state", "")) == "hold" and _cpu_should_advance(runner):
			_send_runner(runner)
	phase_changed.emit(phase)


func _best_cpu_throw() -> int:
	if not is_instance_valid(holder):
		return -1
	var best_base := -1
	var best_priority := -INF
	for runner in _runners:
		var runner_state_value := String(runner.get("state", "hold"))
		if runner_state_value not in ["advance", "return"]:
			continue
		var target_base := int(runner.get("to_base", 1)) % 4
		if runner_state_value == "return":
			target_base = int(runner.get("from_base", 0))
		var remaining_fraction := float(runner.get("frac", 0.0)) if runner_state_value == "return" else 1.0 - float(runner.get("frac", 0.0))
		var runner_time := maxf(0.0, float(runner.get("delay", 0.0))) + _base_leg_length(int(runner.get("from_base", 0))) * remaining_fraction / maxf(0.1, float(runner.get("speed", DEFAULT_RUNNER_SPEED_WORLD)))
		var throw_time := THROW_WINDUP_SEC + _flat_distance(holder.global_position, C.base_position(target_base)) / (THROW_IF_FPS * FEET_TO_WORLD)
		var margin := runner_time - throw_time
		var force_bonus := 4.0 if bool(runner.get("forced", false)) and not _fly_caught else 0.0
		var lead_position := 4 if target_base == 0 else target_base
		var priority := force_bonus + float(lead_position) + margin
		if margin > 0.08 and priority > best_priority:
			best_priority = priority
			best_base = target_base
	return best_base


func _configure_context(contact: Dictionary, queued: Dictionary, direct: Dictionary) -> void:
	var embedded: Dictionary = {}
	if contact.get("live_play_context", {}) is Dictionary:
		embedded = (contact.get("live_play_context", {}) as Dictionary).duplicate(true)
	_play_context = embedded
	_play_context.merge(queued, true)
	_play_context.merge(direct, true)
	# Allow compact callers to place the common fields beside trajectory data.
	for key in ["bases", "difficulty", "outs_before", "seed", "runner_speed", "runner_slots", "user_runner_control"]:
		if contact.has(key) and not _play_context.has(key):
			_play_context[key] = contact[key]
	_difficulty = clampf(float(_play_context.get("difficulty", 0.5)), 0.0, 1.0)
	_outs_before = clampi(int(_play_context.get("outs_before", 0)), 0, 2)
	_manual_runner_control = bool(_play_context.get("user_runner_control", false))
	_play_seed = int(_play_context.get("seed", _trajectory_seed(contact)))
	_rng.seed = _play_seed


func _cache_fielder_home() -> void:
	for key_value in defenders:
		var key := String(key_value)
		var player: Node3D = defenders[key]
		if is_instance_valid(player):
			_fielder_home[key] = player.global_position


func _build_runners() -> void:
	var occupied := _occupied_bases(_play_context.get("bases", {}))
	var slots: Dictionary = _play_context.get("runner_slots", {}) if _play_context.get("runner_slots", {}) is Dictionary else {}
	var speed := clampf(float(_play_context.get("runner_speed", DEFAULT_RUNNER_SPEED_WORLD)), 4.0, 12.0)
	for base in [3, 2, 1]:
		if not bool(occupied[base - 1]):
			continue
		var forced := bool(occupied[0]) if base == 2 else (bool(occupied[0]) and bool(occupied[1]) if base == 3 else true)
		_runners.append(_make_runner(String(slots.get(_base_name(base), "runner_%d" % base)), base, forced, false, speed))
	_runners.append(_make_runner(String(slots.get("batter", "batter")), 0, true, true, speed))
	var catchable_fly := _likely_catchable_fly()
	for runner in _runners:
		if bool(runner.get("is_batter", false)):
			runner["delay"] = 0.45
			_send_runner(runner)
		elif bool(runner.get("forced", false)):
			_send_runner(runner, 0.45 if catchable_fly else -1.0)
		elif not catchable_fly and _cpu_should_advance(runner):
			_send_runner(runner)


func _make_runner(slot: String, base: int, forced: bool, is_batter: bool, speed: float) -> Dictionary:
	return {
		"slot": slot,
		"is_batter": is_batter,
		"speed": speed,
		"from_base": base,
		"to_base": base + 1,
		"frac": 0.0,
		"state": "hold",
		"forced": forced,
		"tag_base": base,
		"delay": 0.25,
		"cap_frac": -1.0,
		"goal": base + 1,
	}


func _update_runners(delta: float) -> void:
	for index in range(_runners.size()):
		var runner: Dictionary = _runners[index]
		var runner_state_value := String(runner.get("state", "hold"))
		if runner_state_value not in ["advance", "return"]:
			continue
		var delay := float(runner.get("delay", 0.0))
		if delay > 0.0:
			runner["delay"] = delay - delta
			if float(runner["delay"]) > 0.0:
				continue
		var segment_speed := float(runner.get("speed", DEFAULT_RUNNER_SPEED_WORLD)) / _base_leg_length(int(runner.get("from_base", 0)))
		if runner_state_value == "advance":
			var cap := float(runner.get("cap_frac", -1.0))
			if cap >= 0.0 and float(runner.get("frac", 0.0)) >= cap:
				continue
			runner["frac"] = float(runner.get("frac", 0.0)) + segment_speed * delta
			if float(runner["frac"]) >= 1.0:
				_runner_arrived(index, int(runner.get("to_base", 1)))
		else:
			runner["frac"] = float(runner.get("frac", 0.0)) - segment_speed * delta
			if float(runner["frac"]) <= 0.0:
				runner["frac"] = 0.0
				runner["state"] = "hold"
				runner["tag_base"] = int(runner.get("from_base", 0))


func _runner_arrived(index: int, arrived: int) -> void:
	var runner: Dictionary = _runners[index]
	runner["forced"] = false
	runner["frac"] = 0.0
	if arrived == 4:
		_score_runner(index)
		return
	runner["from_base"] = arrived
	runner["to_base"] = arrived + 1
	runner["tag_base"] = arrived
	runner["state"] = "hold"
	if bool(runner.get("is_batter", false)):
		_batter_base = maxi(_batter_base, arrived)
	_events.append({"type": "safe", "base": arrived, "slot": runner.get("slot", "")})
	if not _manual_runner_control and _cpu_should_advance(runner):
		_send_runner(runner)
	elif _manual_runner_control and int(runner.get("goal", arrived)) > arrived:
		_send_runner(runner)


func _send_runner(runner: Dictionary, cap_frac: float = -1.0) -> void:
	if String(runner.get("state", "")) in ["out", "scored"]:
		return
	runner["state"] = "advance"
	runner["cap_frac"] = cap_frac


func _return_runner(runner: Dictionary) -> void:
	if String(runner.get("state", "")) not in ["advance", "hold"]:
		return
	if float(runner.get("frac", 0.0)) <= 0.0:
		runner["state"] = "hold"
		return
	runner["state"] = "return"


func _command_runner(index: int, base_index: int) -> void:
	var runner: Dictionary = _runners[index]
	var target := 4 if base_index == 0 else base_index
	var current := float(runner.get("from_base", 0))
	if String(runner.get("state", "hold")) in ["advance", "return"]:
		current += float(runner.get("frac", 0.0))
	if float(target) > current:
		runner["goal"] = target
		runner["cap_frac"] = -1.0
		_send_runner(runner)
	elif target < ceili(current) or (target == int(runner.get("from_base", 0)) and float(runner.get("frac", 0.0)) > 0.0):
		runner["goal"] = target
		_return_runner(runner)


func _on_ball_grounded() -> void:
	for runner in _runners:
		runner["cap_frac"] = -1.0
		if String(runner.get("state", "")) == "hold" and float(runner.get("frac", 0.0)) > 0.0:
			_send_runner(runner)
		elif _cpu_controls_runner() and String(runner.get("state", "")) == "hold" and _cpu_should_advance(runner):
			_send_runner(runner)


func _on_fly_caught() -> void:
	var catch_depth := _flat_distance(C.HOME_PLATE, holder.global_position) / FEET_TO_WORLD if is_instance_valid(holder) else 0.0
	for runner in _runners:
		if bool(runner.get("is_batter", false)) or String(runner.get("state", "")) in ["out", "scored"]:
			continue
		runner["forced"] = false
		runner["cap_frac"] = -1.0
		if float(runner.get("frac", 0.0)) > 0.0:
			_return_runner(runner)
		elif catch_depth > 235.0 and int(runner.get("from_base", 0)) == 3:
			runner["delay"] = 0.3
			_send_runner(runner)
		elif catch_depth > 275.0 and int(runner.get("from_base", 0)) == 2:
			runner["delay"] = 0.3
			_send_runner(runner)


func _cpu_should_advance(runner: Dictionary) -> bool:
	if String(runner.get("state", "")) in ["out", "scored"]:
		return false
	var next_base := int(runner.get("to_base", 1)) % 4
	var current_fraction := float(runner.get("frac", 0.0)) if String(runner.get("state", "")) == "advance" else 0.0
	var remaining := _base_leg_length(int(runner.get("from_base", 0))) * (1.0 - current_fraction)
	var runner_time := maxf(float(runner.get("delay", 0.0)), 0.15) + remaining / maxf(0.1, float(runner.get("speed", DEFAULT_RUNNER_SPEED_WORLD)))
	var margin := lerpf(0.75, 0.25, _difficulty) + (0.25 if next_base == 0 else 0.0)
	return runner_time + margin < _defense_time_to(next_base)


func _defense_time_to(base_index: int) -> float:
	var target := C.base_position(base_index)
	if is_instance_valid(holder):
		return THROW_WINDUP_SEC + _flat_distance(holder.global_position, target) / (THROW_IF_FPS * FEET_TO_WORLD)
	if phase == "throw":
		var left := maxf(0.0, throw_duration - throw_elapsed)
		return left if throw_base == base_index else left + THROW_WINDUP_SEC + _flat_distance(throw_end, target) / (THROW_IF_FPS * FEET_TO_WORLD)
	var best := INF
	var target_ball := _playable_target()
	for key_value in defenders:
		var key := String(key_value)
		var player: Node3D = defenders[key]
		if not is_instance_valid(player):
			continue
		var pursuit := _flat_distance(player.global_position, target_ball) / maxf(0.1, _fielder_speed_world(key) * lerpf(0.70, 0.94, _difficulty))
		var throw_time := THROW_WINDUP_SEC + _flat_distance(target_ball, target) / ((THROW_OF_FPS if _is_outfielder(key) else THROW_IF_FPS) * FEET_TO_WORLD)
		best = minf(best, pursuit + PICKUP_SEC + throw_time)
	return best


func _resolve_outs() -> void:
	if not is_instance_valid(holder) or not active:
		return
	for index in range(_runners.size()):
		var runner: Dictionary = _runners[index]
		var runner_state_value := String(runner.get("state", "hold"))
		if runner_state_value in ["out", "scored"]:
			continue
		if runner_state_value == "advance" and bool(runner.get("forced", false)) and not _fly_caught:
			var force_base := int(runner.get("to_base", 1)) % 4
			if _flat_distance(holder.global_position, C.base_position(force_base)) < BASE_TOUCH_WORLD:
				_record_out(index, "force", force_base)
				if not active:
					return
				continue
		if runner_state_value == "return":
			var return_base := int(runner.get("from_base", 0))
			if _flat_distance(holder.global_position, C.base_position(return_base)) < BASE_TOUCH_WORLD:
				_record_out(index, "doubled_off", return_base)
				if not active:
					return
				continue
		if _runner_off_base(runner) and _flat_distance(holder.global_position, _runner_position(runner)) < TAG_RADIUS_WORLD:
			_record_out(index, "tag", -1)
			if not active:
				return


func _record_out(index: int, how: String, base_index: int) -> void:
	var runner: Dictionary = _runners[index]
	if String(runner.get("state", "")) in ["out", "scored"]:
		return
	runner["state"] = "out"
	if bool(runner.get("is_batter", false)):
		_batter_out = true
	var out := {"slot": runner.get("slot", ""), "how": how, "base": base_index, "batter": bool(runner.get("is_batter", false))}
	_outs.append(out)
	_events.append({"type": "out", "slot": out.slot, "how": how, "base": base_index})
	if _outs_before + _outs.size() >= 3:
		if how == "force" or bool(runner.get("is_batter", false)):
			_runs_voided = true
		_finish_settled()


func _score_runner(index: int) -> void:
	var runner: Dictionary = _runners[index]
	if String(runner.get("state", "")) in ["out", "scored"]:
		return
	runner["state"] = "scored"
	if bool(runner.get("is_batter", false)):
		_batter_base = 4
	_scored_slots.append(runner.get("slot", ""))
	_events.append({"type": "run", "slot": runner.get("slot", "")})


func _home_run() -> void:
	_events.append({"type": "home_run"})
	for index in range(_runners.size()):
		_score_runner(index)
	_batter_base = 4
	_complete(_result_packet("home_run"))


func _check_dead(delta: float) -> void:
	if elapsed >= MAX_PLAY_SEC:
		_finish_settled()
		return
	var runners_settled := true
	for runner in _runners:
		var runner_state_value := String(runner.get("state", "hold"))
		if runner_state_value not in ["out", "scored"] and not (runner_state_value == "hold" and float(runner.get("frac", 0.0)) == 0.0):
			runners_settled = false
			break
	if is_instance_valid(holder) and runners_settled and phase == "possession" and not throw_charging:
		_dead_timer += delta
		if _dead_timer >= DEAD_HOLD_SEC:
			_finish_settled()
	else:
		_dead_timer = 0.0


func _finish_settled() -> void:
	if not active:
		return
	for runner in _runners:
		if String(runner.get("state", "")) in ["advance", "return"]:
			runner["state"] = "hold"
			runner["frac"] = 0.0
	var rule_classification := _rule_classification()
	_complete(_result_packet(rule_classification))


func _rule_classification() -> String:
	if _batter_out:
		for out in _outs:
			if bool(out.get("batter", false)) and String(out.get("how", "")) == "flyout":
				return "fly_out"
		return "ground_out"
	if _batter_base >= 4:
		return "home_run"
	if not _outs.is_empty() and _batter_base <= 1:
		return "fielders_choice"
	if _batter_base >= 3:
		return "triple"
	if _batter_base == 2:
		return "double"
	return "single"


## Completion result contract:
## - classification: legacy PixiballSim spelling (FC is ground_out until the
##   rules layer consumes the rich fields below)
## - rule_classification: out/fielders_choice/single/double/triple/home_run
## - outs: ordered {slot, how, base, batter} records; double_play is derived
## - final_bases: bounded first/second/third occupancy plus stable slot ids
## - runs/scored_slots/batter_bases: the physical play result, with force-out
##   third-run cancellation already applied
## - events: ordered physical catch/pickup/throw/overthrow/out/safe/run stream
func _result_packet(rule_classification: String) -> Dictionary:
	# PixiballSim's legacy commit surface does not yet accept fielders_choice.
	# Keep its classification compatible while exposing the exact rule result
	# separately so the sim can consume final_bases/outs without inference.
	var compatibility_classification := "ground_out" if rule_classification == "fielders_choice" else rule_classification
	var double_play := _outs.size() >= 2
	var label := rule_classification.replace("_", " ").to_upper()
	if double_play:
		label = "DOUBLE PLAY"
	elif rule_classification == "fielders_choice":
		label = "FIELDER'S CHOICE"
	elif rule_classification == "single":
		label = "BASE HIT"
	return {
		"classification": compatibility_classification,
		"rule_classification": rule_classification,
		"fielders_choice": rule_classification == "fielders_choice",
		"label": label,
		"outs": _outs.duplicate(true),
		"outs_recorded": _outs.size(),
		"double_play": double_play,
		"runs": 0 if _runs_voided else _scored_slots.size(),
		"scored_slots": [] if _runs_voided else _scored_slots.duplicate(),
		"final_bases": _final_bases_snapshot(),
		"batter_bases": 0 if _batter_out else _batter_base,
		"batter_out": _batter_out,
		"advance_runners": rule_classification == "fly_out" and bool(trajectory.get("carry_ft", 0.0) > 235.0),
		"sacrifice": rule_classification == "fly_out" and not _scored_slots.is_empty() and not _runs_voided,
		"deep": float(trajectory.get("carry_ft", 0.0)) > 220.0,
		"events": _events.duplicate(true),
	}


func _final_bases_snapshot() -> Dictionary:
	var occupied := [false, false, false]
	var occupants := {"first": "", "second": "", "third": ""}
	for runner in _runners:
		if String(runner.get("state", "")) not in ["hold", "advance", "return"]:
			continue
		var base := int(runner.get("from_base", 0))
		if base < 1 or base > 3:
			continue
		occupied[base - 1] = true
		occupants[_base_name(base)] = String(runner.get("slot", ""))
	return {
		"first": occupied[0],
		"second": occupied[1],
		"third": occupied[2],
		"occupants": occupants,
	}


func _meter_error_ft(position: float) -> float:
	var meter_position := clampf(position, 0.0, 1.0)
	if meter_position >= THROW_METER_GREEN_LO and meter_position <= THROW_METER_GREEN_HI:
		var half_green := (THROW_METER_GREEN_HI - THROW_METER_GREEN_LO) * 0.5
		var off := absf(meter_position - 0.5) / half_green
		return off * 2.6 + absf(_rng.randfn(0.0, 0.5))
	var over := (THROW_METER_GREEN_LO - meter_position) / THROW_METER_GREEN_LO if meter_position < THROW_METER_GREEN_LO else (meter_position - THROW_METER_GREEN_HI) / (1.0 - THROW_METER_GREEN_HI)
	return 5.5 + over * 8.0


func _cpu_throw_error_ft(base_index: int) -> float:
	var distance_ft := _flat_distance(holder.global_position, C.base_position(base_index)) / FEET_TO_WORLD if is_instance_valid(holder) else 0.0
	var sigma := (0.9 + 0.02 * distance_ft) * lerpf(1.45, 0.55, _difficulty)
	return absf(_rng.randfn(0.0, sigma))


func _throw_accuracy_label(error_ft: float) -> String:
	if error_ft < 2.0:
		return "perfect"
	if error_ft < THROW_CLEAN_ERROR_FT:
		return "clean"
	return "overthrow"


func _coverer_at(base_index: int) -> Node3D:
	var best: Node3D
	var best_distance := COVER_RADIUS_WORLD
	for player_value in defenders.values():
		var player: Node3D = player_value
		if not is_instance_valid(player) or player == holder:
			continue
		var distance := _flat_distance(player.global_position, C.base_position(base_index))
		if distance < best_distance:
			best_distance = distance
			best = player
	return best


func _cover_assignments(pursuer: String) -> Dictionary:
	var covers := {0: "catcher", 1: "first", 2: "second", 3: "third"}
	if pursuer == "catcher" or not defenders.has("catcher"):
		covers[0] = "pitcher"
	if pursuer == "first" or not defenders.has("first"):
		covers[1] = "second"
	if pursuer == "second" or not defenders.has("second"):
		covers[2] = "short"
	if pursuer == "third" or not defenders.has("third"):
		covers[3] = "short"
	if pursuer == "short":
		covers[3] = "third"
	return covers


func _base_for_coverer(covers: Dictionary, key: String) -> int:
	for base_value in covers:
		if String(covers[base_value]) == key:
			return int(base_value)
	return 0


func _ranked_fielder_keys(target: Vector3) -> Array:
	var ranked: Array = []
	for key_value in defenders:
		var key := String(key_value)
		var player: Node3D = defenders[key]
		if not is_instance_valid(player):
			continue
		var inserted := false
		var distance := _flat_distance(player.global_position, target)
		for index in range(ranked.size()):
			var other: Node3D = defenders[String(ranked[index])]
			if distance < _flat_distance(other.global_position, target):
				ranked.insert(index, key)
				inserted = true
				break
		if not inserted:
			ranked.append(key)
	return ranked


func _playable_target() -> Vector3:
	if phase in ["rolling", "possession", "throw"] or landed or _wall_seen:
		return Vector3(ball_position.x, 0.08, ball_position.z)
	return Vector3(landing_position.x, 0.08, landing_position.z)


func _select_best_fielder() -> void:
	var ranked := _ranked_fielder_keys(landing_position)
	_set_controlled(String(ranked[0]) if not ranked.is_empty() else "")


func _set_controlled(key: String) -> void:
	if is_instance_valid(controlled_player) and controlled_player.has_method("set_highlighted"):
		controlled_player.call("set_highlighted", false)
	controlled_key = key
	controlled_player = defenders.get(key)
	if is_instance_valid(controlled_player) and controlled_player.has_method("set_highlighted"):
		controlled_player.call("set_highlighted", user_fielding)


func _fielder_speed_world(key: String) -> float:
	return ParkGeometry.fielder_speed(key) * FEET_TO_WORLD


func _is_outfielder(key: String) -> bool:
	return key in ["left", "center", "right", "lf", "cf", "rf"]


func _likely_catchable_fly() -> bool:
	return (
		float(trajectory.get("launch_angle_deg", trajectory.get("launch_angle", 0.0))) >= 12.0
		and float(trajectory.get("hang_time_sec", 0.0)) >= 1.2
		and String(trajectory.get("classification_hint", "")) != "home_run"
	)


func _occupied_bases(value: Variant) -> Array[bool]:
	var occupied: Array[bool] = [false, false, false]
	if value is Dictionary:
		var bases: Dictionary = value
		occupied[0] = bool(bases.get("first", bases.get(1, false)))
		occupied[1] = bool(bases.get("second", bases.get(2, false)))
		occupied[2] = bool(bases.get("third", bases.get(3, false)))
	elif value is Array:
		var bases_array: Array = value
		for index in range(mini(3, bases_array.size())):
			occupied[index] = bool(bases_array[index])
	return occupied


func _commandable_runner_indices() -> Array[int]:
	var live: Array[int] = []
	for index in range(_runners.size()):
		if String(_runners[index].get("state", "")) not in ["out", "scored"]:
			live.append(index)
	return live


func _batter_runner_index() -> int:
	for index in range(_runners.size()):
		if bool(_runners[index].get("is_batter", false)):
			return index
	return -1


func _runner_position(runner: Dictionary) -> Vector3:
	var from := C.base_position(int(runner.get("from_base", 0)))
	var to := C.base_position(int(runner.get("to_base", 1)) % 4)
	return from.lerp(to, clampf(float(runner.get("frac", 0.0)), 0.0, 1.0))


func _runner_off_base(runner: Dictionary) -> bool:
	return String(runner.get("state", "")) in ["advance", "return"] and float(runner.get("frac", 0.0)) > 0.02 and float(runner.get("frac", 0.0)) < 0.985


func _base_leg_length(from_base: int) -> float:
	return maxf(1.0, _flat_distance(C.base_position(from_base), C.base_position((from_base + 1) % 4)))


func _cpu_controls_runner() -> bool:
	return user_fielding or not _manual_runner_control


func _base_name(base_index: int) -> String:
	return ["home", "first", "second", "third"][clampi(base_index, 0, 3)]


func _key_for_player(player: Node3D) -> String:
	for key_value in defenders:
		var key := String(key_value)
		if defenders[key] == player:
			return key
	return ""


func _stop_fielder(player: Node3D) -> void:
	if player.has_method("set_motion"):
		player.call("set_motion", Vector3.ZERO)


func _flat_direction(from: Vector3, to: Vector3) -> Vector3:
	var result := to - from
	result.y = 0.0
	return result.normalized() if result.length() > 0.001 else Vector3.ZERO


func _flat_distance(a: Vector3, b: Vector3) -> float:
	var delta := b - a
	delta.y = 0.0
	return delta.length()


func _trajectory_seed(contact: Dictionary) -> int:
	var speed := int(round(float(contact.get("launch_speed_mph", contact.get("exit_velocity_mph", 0.0))) * 100.0))
	var angle := int(round(float(contact.get("launch_angle_deg", 0.0)) * 100.0))
	var spray := int(round(float(contact.get("spray_deg", contact.get("spray_angle_deg", 0.0))) * 100.0))
	return speed * 73856093 ^ angle * 19349663 ^ spray * 83492791


func _launch_spec(contact: Dictionary) -> Dictionary:
	return {
		"launch_speed_mph": float(contact.get(
			"launch_speed_mph",
			contact.get("exit_velocity_mph", contact.get("launch_speed", contact.get("LaunchSpeed", 0.0))),
		)),
		"launch_angle_deg": float(contact.get(
			"launch_angle_deg",
			contact.get("launch_angle", contact.get("LaunchAngle", 0.0)),
		)),
		"spray_deg": float(contact.get(
			"spray_deg",
			contact.get("spray_angle_deg", contact.get("spray_angle", contact.get("SprayDeg", 0.0))),
		)),
	}


func _apply_prediction_to_trajectory() -> void:
	var landing: Dictionary = _ball_prediction.get("landing", {})
	var spray := float(_ball_state.get("spray_deg", 0.0))
	trajectory["landing_ft"] = [
		float(landing.get("x", 0.0)),
		float(landing.get("y", 0.0)),
		float(landing.get("z", 0.0)),
	]
	trajectory["carry_ft"] = float(_ball_prediction.get("carry_ft", 0.0))
	trajectory["hang_time_sec"] = float(_ball_prediction.get("hang_time_sec", 0.0))
	trajectory["fence_distance_ft"] = ParkGeometry.fence_distance(spray)
	trajectory["fence_height_ft"] = ParkGeometry.fence_height(spray)
	trajectory["classification_hint"] = String(_ball_prediction.get("classification", "fair_ball"))
	trajectory["physics_prediction"] = _ball_prediction.duplicate(true)


func _field_state_to_world(state_value: Dictionary) -> Vector3:
	return C.HOME_PLATE + Vector3(
		float(state_value.get("x", 0.0)) * FEET_TO_WORLD,
		float(state_value.get("z", 0.0)) * VERTICAL_FEET_TO_WORLD,
		-float(state_value.get("y", 0.0)) * FEET_TO_WORLD,
	)


func _field_sample_to_world(sample: Dictionary) -> Vector3:
	return _field_state_to_world(sample)


func _field_velocity_to_world(state_value: Dictionary) -> Vector3:
	return Vector3(
		float(state_value.get("vx", 0.0)) * FEET_TO_WORLD,
		float(state_value.get("vz", 0.0)) * VERTICAL_FEET_TO_WORLD,
		-float(state_value.get("vy", 0.0)) * FEET_TO_WORLD,
	)


func _field_xy_snapshot(state_value: Dictionary) -> Array:
	return [float(state_value.get("x", 0.0)), float(state_value.get("y", 0.0))]


func _complete(result: Dictionary) -> void:
	if _completion_sent:
		return
	_completion_sent = true
	active = false
	phase = "complete"
	if is_instance_valid(controlled_player) and controlled_player.has_method("set_highlighted"):
		controlled_player.call("set_highlighted", false)
	for player_value in defenders.values():
		var player: Node3D = player_value
		if is_instance_valid(player) and player.has_method("set_motion"):
			player.call("set_motion", Vector3.ZERO)
	phase_changed.emit(phase)
	completed.emit(result)
