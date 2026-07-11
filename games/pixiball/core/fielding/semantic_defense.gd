class_name PixiballSemanticDefense
extends RefCounted

## Deterministic, presentation-free defense for semantic/headless play.
##
## This is the Godot counterpart to PixCore's coarse AutoPlay resolver. It is
## intentionally separate from `live_play_controller.gd`: interactive games
## retain physical fielders, runner commands, throws, and tags, while tests and
## agents that do not tick a scene can still turn a trajectory into a bounded
## baseball result. The input RNG is a keyed stream owned by the caller.

const Ball = preload("res://core/fielding/batted_ball_physics.gd")
const Park = preload("res://core/fielding/park_geometry.gd")

const AIR_REACTION_SEC := 0.65
const AIR_ROUTE_FACTOR := 0.68
const GROUND_REACTION_SEC := 0.40
const GROUND_ROUTE_FACTOR := 0.62
const CATCH_MAX_Z_FT := 11.0
const INFIELD_THROW_FPS := 115.0
const OUTFIELD_THROW_FPS := 130.0
const TRANSFER_SEC := 0.70
const INFIELD_RADIUS_FT := 145.0
const CATCH_LOGISTIC_SCALE := 0.22
const MUFF_BASE_PROBABILITY := 0.015
const MUFF_DEFENSE_PROBABILITY := 0.020
const RELAY_THRESHOLD_FT := 200.0
const RELAY_EXTRA_SEC := 0.60
const TRIPLE_MIN_SPRAY_DEG := 18.0
const TRIPLE_MIN_DEPTH_FT := 280.0
const OUTFIELD_GATHER_SEC := 0.35
const DOUBLE_STRETCH_MARGIN_SEC := 0.75
const TRIPLE_STRETCH_MARGIN_SEC := 0.40

const INFIELDERS := ["P", "1B", "2B", "SS", "3B"]
const OUTFIELDERS := ["LF", "CF", "RF"]


## Returns a legacy PixiballSim live-play result. It never mutates game state.
## `trajectory` accepts the normal sim spellings: exit_velocity_mph,
## launch_angle_deg, and spray_angle_deg. Defense is clamped to 0..1 and
## batter speed to the plausible lineup envelope used by PixiballSim.
static func resolve(trajectory: Dictionary, batter_speed_fps: float, defense: float, rng: Variant) -> Dictionary:
	if rng == null or typeof(rng) != TYPE_OBJECT or not rng.has_method("next"):
		return {"ok": false, "error": "rng_required", "message": "Semantic defense requires a deterministic RNG stream"}
	var launch_speed := float(trajectory.get("exit_velocity_mph", trajectory.get("launch_speed_mph", 0.0)))
	var launch_angle := float(trajectory.get("launch_angle_deg", 0.0))
	var spray := float(trajectory.get("spray_angle_deg", trajectory.get("spray_deg", 0.0)))
	if not is_finite(launch_speed) or not is_finite(launch_angle) or not is_finite(spray) or launch_speed <= 0.0:
		return {"ok": false, "error": "invalid_trajectory", "message": "Semantic defense requires a finite positive launch"}

	var bounded_speed := clampf(batter_speed_fps, 23.0, 30.0)
	var bounded_defense := clampf(defense, 0.0, 1.0)
	var state := Ball.launch({
		"launch_speed_mph": launch_speed,
		"launch_angle_deg": launch_angle,
		"spray_deg": spray,
	})
	var path: Array = Ball.predict_path(state, 14.0)
	var path_classification: Dictionary = Ball.classify_path(path, spray)
	if bool(path_classification.get("home_run", false)):
		return _result("home_run", "over_fence", path, {})

	var landing: Dictionary = Ball.landing_of(path)
	var air := _best_air_intercept(path)
	if not air.is_empty() and float(air.slack) > -0.60:
		var skill := 0.80 + 0.40 * bounded_defense
		var catch_probability := clampf(_logistic((float(air.slack) * skill) / CATCH_LOGISTIC_SCALE), 0.02, 0.995)
		if float(rng.next()) < catch_probability:
			return _result("fly_out", "air_intercept", path, {
				"fielder": String(air.fielder),
				"intercept_slack_sec": float(air.slack),
				"catch_probability": catch_probability,
			})

	var landing_radius := _hypot(float(landing.get("x", 0.0)), float(landing.get("y", 0.0)))
	var grounder := launch_angle < 10.0 or landing_radius < 120.0
	if grounder and not bool(landing.get("wall", false)):
		var ground := _ground_intercept(path)
		if not ground.is_empty() and float(ground.slack) > -0.25:
			var at: Dictionary = ground.at
			var throw_time := Park.dist_2d([float(at.x), float(at.y)], Park.BASES[1]) / INFIELD_THROW_FPS + TRANSFER_SEC
			var knockdown_penalty := 0.50 if float(ground.slack) < 0.0 else 0.0
			var margin := _batter_time(1, bounded_speed) - (float(ground.t) + knockdown_penalty + throw_time)
			# Match the original fixed draw contract: the muff draw occurs before
			# the throw/race result can short-circuit.
			var muff_probability := MUFF_BASE_PROBABILITY + MUFF_DEFENSE_PROBABILITY * (1.0 - bounded_defense)
			var muff := float(rng.next()) < muff_probability
			if margin > 0.05 and not muff:
				return _result("ground_out", "infield_race", path, {
					"fielder": String(ground.fielder),
					"intercept_slack_sec": float(ground.slack),
					"throw_margin_sec": margin,
				})
			return _result("single", "beat_throw" if not muff else "fielding_error", path, {
				"fielder": String(ground.fielder),
				"intercept_slack_sec": float(ground.slack),
				"throw_margin_sec": margin,
				"muff_probability": muff_probability,
			})

	return _chase_and_race(path, spray, bounded_speed)


static func _best_air_intercept(path: Array) -> Dictionary:
	var best: Dictionary = {}
	for sample_value in path:
		if sample_value is not Dictionary:
			continue
		var sample: Dictionary = sample_value
		if int(sample.get("mode", Ball.MODE_AIR)) != Ball.MODE_AIR \
				or int(sample.get("bounces", 0)) > 0 \
				or bool(sample.get("wall", false)) \
				or float(sample.get("z", 0.0)) > CATCH_MAX_Z_FT \
				or float(sample.get("t", 0.0)) < 0.35:
			continue
		for fielder_value in Park.FIELDER_IDS:
			var fielder := String(fielder_value)
			var slack := float(sample.t) - _air_time(fielder, [float(sample.x), float(sample.y)])
			if best.is_empty() or slack > float(best.slack):
				best = {"fielder": fielder, "slack": slack, "t": float(sample.t), "at": sample.duplicate(true)}
	return best


static func _ground_intercept(path: Array) -> Dictionary:
	var knockdown: Dictionary = {}
	for sample_value in path:
		if sample_value is not Dictionary:
			continue
		var sample: Dictionary = sample_value
		if (int(sample.get("bounces", 0)) == 0 and int(sample.get("mode", Ball.MODE_AIR)) == Ball.MODE_AIR) \
				or float(sample.get("t", 0.0)) > 2.60:
			continue
		if _hypot(float(sample.get("x", 0.0)), float(sample.get("y", 0.0))) > INFIELD_RADIUS_FT:
			continue
		for fielder_value in INFIELDERS:
			var fielder := String(fielder_value)
			var need := GROUND_REACTION_SEC + Park.dist_2d(Park.fielder_post(fielder), [float(sample.x), float(sample.y)]) / (Park.fielder_speed(fielder) * GROUND_ROUTE_FACTOR)
			var slack := float(sample.t) - need
			var intercept := {"fielder": fielder, "slack": slack, "t": float(sample.t), "at": sample.duplicate(true)}
			if slack >= 0.0:
				return intercept
			if knockdown.is_empty() or slack > float(knockdown.slack):
				knockdown = intercept
	return knockdown


static func _chase_and_race(path: Array, spray: float, batter_speed: float) -> Dictionary:
	var last: Dictionary = path[-1] if not path.is_empty() and path[-1] is Dictionary else {}
	var pickup_at := [float(last.get("x", 0.0)), float(last.get("y", 0.0))]
	var pickup_time := float(last.get("t", 0.0)) + OUTFIELD_GATHER_SEC
	var wall_ball := false
	for sample_value in path:
		if sample_value is not Dictionary:
			continue
		var sample: Dictionary = sample_value
		wall_ball = wall_ball or bool(sample.get("wall", false))
		if int(sample.get("mode", Ball.MODE_AIR)) == Ball.MODE_AIR \
				and int(sample.get("bounces", 0)) == 0 \
				and not bool(sample.get("wall", false)):
			continue
		var wall_penalty := 0.50 if bool(sample.get("wall", false)) else 0.0
		var reached := false
		for fielder_value in OUTFIELDERS:
			if _air_time(String(fielder_value), [float(sample.x), float(sample.y)]) + wall_penalty <= float(sample.t):
				reached = true
				break
		if reached:
			pickup_at = [float(sample.x), float(sample.y)]
			pickup_time = float(sample.t) + OUTFIELD_GATHER_SEC
			break

	var throw_second := _outfield_throw_time(pickup_at, Park.BASES[2])
	var takes_two := wall_ball or pickup_time + throw_second > _batter_time(2, batter_speed) - DOUBLE_STRETCH_MARGIN_SEC
	if not takes_two:
		return _result("single", "outfield_hold", path, {"pickup_time_sec": pickup_time})

	var throw_third := _outfield_throw_time(pickup_at, Park.BASES[3])
	var triple_room := absf(spray) > TRIPLE_MIN_SPRAY_DEG and _hypot(float(pickup_at[0]), float(pickup_at[1])) > TRIPLE_MIN_DEPTH_FT
	if triple_room and pickup_time + throw_third > _batter_time(3, batter_speed) - TRIPLE_STRETCH_MARGIN_SEC:
		return _result("triple", "gap_race", path, {"pickup_time_sec": pickup_time})
	return _result("double", "outfield_race", path, {"pickup_time_sec": pickup_time})


static func _result(classification: String, source: String, path: Array, detail: Dictionary) -> Dictionary:
	var result := {
		"ok": true,
		"classification": classification,
		"rule_classification": classification,
		"semantic_source": source,
		"physics_samples": path.size(),
	}
	result.merge(detail, true)
	return result


static func _air_time(fielder: String, point: Variant) -> float:
	return AIR_REACTION_SEC + Park.dist_2d(Park.fielder_post(fielder), point) / (Park.fielder_speed(fielder) * AIR_ROUTE_FACTOR)


static func _batter_time(base_count: int, speed: float) -> float:
	return 0.50 + (90.0 * float(base_count)) / speed + 0.15 * float(base_count)


static func _outfield_throw_time(from: Variant, to: Variant) -> float:
	var distance := Park.dist_2d(from, to)
	return distance / OUTFIELD_THROW_FPS + TRANSFER_SEC + (RELAY_EXTRA_SEC if distance > RELAY_THRESHOLD_FT else 0.0)


static func _logistic(value: float) -> float:
	return 1.0 / (1.0 + exp(-value))


static func _hypot(x: float, y: float) -> float:
	return sqrt(x * x + y * y)
