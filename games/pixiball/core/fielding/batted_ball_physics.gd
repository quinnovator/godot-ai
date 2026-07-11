class_name PixiballBattedBallPhysics
extends RefCounted

## Deterministic, presentation-free port of PixCore's batted-ball integrator.
##
## State and samples use scalar feet/seconds so they can be snapshotted,
## compared, and replayed without scene-space transforms:
##
##     var state = PixiballBattedBallPhysics.launch({
##         "launch_speed_mph": 106.0,
##         "launch_angle_deg": 24.0,
##         "spray_deg": 22.0,
##     })
##     PixiballBattedBallPhysics.step_ball(state) # mutates at 60 Hz
##     var report = PixiballBattedBallPhysics.predict(state)
##
## `predict_path` is pure: it integrates a snapshot and never mutates its input.

const ParkGeometry = preload("res://core/fielding/park_geometry.gd")

const MODE_AIR := 0
const MODE_ROLL := 1
const MODE_STOPPED := 2

const MPH_TO_FPS := 1.467
const BALL_DT := 1.0 / 60.0

const GRAVITY_FPS2 := 32.2
const QUADRATIC_DRAG := 0.00265
const BACKSPIN_LIFT := 0.14
const BOUNCE_VERTICAL := 0.42
const BOUNCE_HORIZONTAL := 0.72
const ROLL_VERTICAL_THRESHOLD_FPS := 4.0
const ROLL_DECEL_FPS2 := 14.0
const STOP_SPEED_FPS := 1.5

const CONTACT_X_FT := 0.0
const CONTACT_Y_FT := 2.0
const CONTACT_Z_FT := 3.0


## Launches a ball from the frozen bat-contact point. Accepted spellings
## include the GDScript contract and the original FBattedBallSpec fields.
static func launch(spec: Dictionary) -> Dictionary:
	var launch_speed_mph := _number(spec,
		["launch_speed_mph", "launch_speed", "launchSpeed", "LaunchSpeed"], 0.0)
	var launch_angle_deg := _number(spec,
		["launch_angle_deg", "launch_angle", "launchAngle", "LaunchAngle"], 0.0)
	var spray_deg := _number(spec, ["spray_deg", "spray", "sprayDeg", "SprayDeg"], 0.0)
	var speed := launch_speed_mph * MPH_TO_FPS
	var launch_angle := launch_angle_deg * ParkGeometry.RAD_PER_DEG
	var spray := spray_deg * ParkGeometry.RAD_PER_DEG
	var horizontal := speed * cos(launch_angle)
	return {
		"x": CONTACT_X_FT,
		"y": CONTACT_Y_FT,
		"z": CONTACT_Z_FT,
		"vx": horizontal * sin(spray),
		"vy": horizontal * cos(spray),
		"vz": speed * sin(launch_angle),
		"mode": MODE_AIR,
		"bounces": 0,
		"lift": lift_factor(launch_angle_deg),
		"t": 0.0,
		"wall": false,
		"launch_speed_mph": launch_speed_mph,
		"launch_angle_deg": launch_angle_deg,
		"spray_deg": spray_deg,
	}


static func lift_factor(launch_angle_deg: float) -> float:
	var base := maxf(0.0, minf(1.0, launch_angle_deg / 30.0))
	var taper := maxf(0.0, (90.0 - launch_angle_deg) / 45.0) if launch_angle_deg > 45.0 else 1.0
	return base * taper


## Mutates one canonical state by one fixed step unless a different positive
## `dt` is supplied. Arithmetic order mirrors PixBall::StepBall.
static func step_ball(state: Dictionary, dt: float = BALL_DT) -> void:
	if int(state.get("mode", MODE_STOPPED)) == MODE_STOPPED:
		return
	if dt <= 0.0:
		push_error("PixiballBattedBallPhysics.step_ball requires dt > 0")
		return

	state["t"] = float(state.get("t", 0.0)) + dt
	if int(state.get("mode", MODE_AIR)) == MODE_ROLL:
		_step_roll(state, dt)
		return
	_step_air(state, dt)


## One integration tick plus a serializable state/sample/classification packet.
## This is the intended live-game wiring point when callers do not need the
## complete predicted path.
static func advance(state: Dictionary, dt: float = BALL_DT) -> Dictionary:
	step_ball(state, dt)
	var classification := classify_state(state)
	return {
		"state": snapshot(state),
		"sample": sample_of(state),
		"classification": String(classification.get("classification", "unknown")),
		"classification_detail": classification,
	}


## Pure look-ahead. Like PixBall::PredictPath, samples are post-step and the
## final state is appended once more after the loop.
static func predict_path(state: Dictionary, max_t: float = 12.0, dt: float = BALL_DT) -> Array[Dictionary]:
	var path: Array[Dictionary] = []
	if dt <= 0.0 or max_t < 0.0:
		push_error("PixiballBattedBallPhysics.predict_path requires dt > 0 and max_t >= 0")
		return path
	var copy := from_snapshot(snapshot(state))
	var start_t := float(copy["t"])
	while float(copy["t"]) - start_t < max_t and int(copy["mode"]) != MODE_STOPPED:
		step_ball(copy, dt)
		path.append(sample_of(copy))
	path.append(sample_of(copy))
	return path


## First grass touch, wall bang, or transition out of flight.
static func landing_of(path: Array) -> Dictionary:
	for sample_value in path:
		if sample_value is not Dictionary:
			continue
		var sample: Dictionary = sample_value
		if int(sample.get("bounces", 0)) > 0 or bool(sample.get("wall", false)) \
				or int(sample.get("mode", MODE_AIR)) != MODE_AIR:
			return sample.duplicate(true)
	if path.is_empty() or path[-1] is not Dictionary:
		return {}
	return (path[-1] as Dictionary).duplicate(true)


static func predicted_landing(state: Dictionary, max_t: float = 12.0, dt: float = BALL_DT) -> Dictionary:
	return landing_of(predict_path(state, max_t, dt))


## Integration-friendly aggregate containing the immutable launch state, full
## path, first landing/wall sample, carry, and terminal classification.
static func predict(source: Dictionary, max_t: float = 12.0, dt: float = BALL_DT) -> Dictionary:
	var initial := launch(source) if not is_state(source) else from_snapshot(snapshot(source))
	var path := predict_path(initial, max_t, dt)
	var landing := landing_of(path)
	var classification := classify_path(path, float(initial.get("spray_deg", 0.0)))
	var landing_x := float(landing.get("x", initial["x"]))
	var landing_y := float(landing.get("y", initial["y"]))
	var carry := _hypot2(landing_x, landing_y)
	return {
		"initial_state": snapshot(initial),
		"path": path,
		"landing": landing,
		"predicted_landing_ft": [landing_x, landing_y, float(landing.get("z", 0.0))],
		"carry_ft": carry,
		"hang_time_sec": float(landing.get("t", 0.0)),
		"classification": String(classification.get("classification", "unknown")),
		"classification_detail": classification,
	}


## Current-tick classification for a live fixed-step loop. Historical home
## runs should terminate play on the tick this returns `home_run`; use
## `classify_path` when inspecting a completed prediction after the fact.
static func classify_state(state: Dictionary) -> Dictionary:
	if not is_state(state):
		return {
			"classification": "unknown",
			"fair": false,
			"home_run": false,
			"wall": false,
		}
	var x := float(state.get("x", 0.0))
	var y := float(state.get("y", 0.0))
	var current_spray := ParkGeometry.spray_degrees(x, y)
	var launch_spray := float(state.get("spray_deg", current_spray))
	var fair := absf(launch_spray) <= 45.0
	var wall := bool(state.get("wall", false))
	var fence := ParkGeometry.fence_distance(current_spray)
	var home_run := (
		fair
		and int(state.get("mode", MODE_AIR)) == MODE_AIR
		and int(state.get("bounces", 0)) == 0
		and not wall
		and _hypot2(x, y) >= fence
	)
	var classification := "fair_ball"
	if not fair:
		classification = "foul"
	elif home_run:
		classification = "home_run"
	elif wall:
		classification = "wall"
	elif int(state.get("mode", MODE_AIR)) == MODE_AIR:
		classification = "airborne"
	return {
		"classification": classification,
		"fair": fair,
		"home_run": home_run,
		"wall": wall,
		"spray_deg": launch_spray,
		"current_spray_deg": current_spray,
		"fence_distance_ft": fence,
		"wall_height_ft": ParkGeometry.fence_height(current_spray),
	}


## Classifies foul territory first, then over-the-fence flight, then a wall
## carom. Home-run detection intentionally scans only pristine airborne
## samples; a later wall clamp in a long prediction cannot erase an earlier
## over-the-wall crossing. Supplying `launch_spray_deg` preserves foul status
## even if a long foul path eventually clamps against a foul-pole wall plane.
static func classify_path(path: Array, launch_spray_deg: Variant = null) -> Dictionary:
	if path.is_empty() or path[-1] is not Dictionary:
		return {
			"classification": "unknown",
			"fair": false,
			"home_run": false,
			"wall": false,
		}
	var last: Dictionary = path[-1]
	var final_x := float(last.get("x", 0.0))
	var final_y := float(last.get("y", 0.0))
	var final_spray := ParkGeometry.spray_degrees(final_x, final_y)
	var classification_spray := float(launch_spray_deg) if launch_spray_deg != null else final_spray
	var fair := absf(classification_spray) <= 45.0 if launch_spray_deg != null \
		else ParkGeometry.is_fair(final_x, final_y)
	var touched_wall := false
	var home_run := false
	for sample_value in path:
		if sample_value is not Dictionary:
			continue
		var sample: Dictionary = sample_value
		var wall := bool(sample.get("wall", false))
		touched_wall = touched_wall or wall
		if int(sample.get("mode", MODE_AIR)) != MODE_AIR \
				or int(sample.get("bounces", 0)) > 0 or wall:
			break
		var x := float(sample.get("x", 0.0))
		var y := float(sample.get("y", 0.0))
		if not ParkGeometry.is_fair(x, y):
			continue
		var spray := ParkGeometry.spray_degrees(x, y)
		# WallCheck has already run for this sample: a pristine ball at or
		# beyond the actual fence arc necessarily crossed above the wall top.
		if _hypot2(x, y) >= ParkGeometry.fence_distance(spray):
			home_run = true
			break

	# Preserve wall knowledge even when it occurs after an over-fence sample.
	if not touched_wall:
		for sample_value in path:
			if sample_value is Dictionary and bool(sample_value.get("wall", false)):
				touched_wall = true
				break

	var classification := "fair_ball"
	if not fair:
		classification = "foul"
		home_run = false
	elif home_run:
		classification = "home_run"
	elif touched_wall:
		classification = "wall"
	elif int(last.get("mode", MODE_AIR)) == MODE_AIR and int(last.get("bounces", 0)) == 0:
		classification = "airborne"

	return {
		"classification": classification,
		"fair": fair,
		"home_run": home_run,
		"wall": touched_wall,
		"spray_deg": classification_spray,
		"fence_distance_ft": ParkGeometry.fence_distance(classification_spray),
		"wall_height_ft": ParkGeometry.fence_height(classification_spray),
	}


static func is_home_run(path: Array) -> bool:
	return bool(classify_path(path).get("home_run", false))


static func sample_of(state: Dictionary) -> Dictionary:
	return {
		"t": float(state.get("t", 0.0)),
		"x": float(state.get("x", 0.0)),
		"y": float(state.get("y", 0.0)),
		"z": float(state.get("z", 0.0)),
		"mode": int(state.get("mode", MODE_AIR)),
		"bounces": int(state.get("bounces", 0)),
		"wall": bool(state.get("wall", false)),
	}


## Canonical serializable state. This is the save/replay boundary.
static func snapshot(state: Dictionary) -> Dictionary:
	return {
		"x": float(state.get("x", CONTACT_X_FT)),
		"y": float(state.get("y", CONTACT_Y_FT)),
		"z": float(state.get("z", CONTACT_Z_FT)),
		"vx": float(state.get("vx", 0.0)),
		"vy": float(state.get("vy", 0.0)),
		"vz": float(state.get("vz", 0.0)),
		"mode": int(state.get("mode", MODE_AIR)),
		"bounces": int(state.get("bounces", 0)),
		"lift": float(state.get("lift", 0.0)),
		"t": float(state.get("t", 0.0)),
		"wall": bool(state.get("wall", false)),
		"launch_speed_mph": float(state.get("launch_speed_mph", 0.0)),
		"launch_angle_deg": float(state.get("launch_angle_deg", 0.0)),
		"spray_deg": float(state.get("spray_deg", 0.0)),
	}


static func from_snapshot(saved: Dictionary) -> Dictionary:
	return snapshot(saved)


static func is_state(value: Dictionary) -> bool:
	return value.has("vx") and value.has("vy") and value.has("vz") and value.has("mode")


static func mode_name(mode: int) -> String:
	match mode:
		MODE_AIR:
			return "air"
		MODE_ROLL:
			return "roll"
		MODE_STOPPED:
			return "stopped"
	return "unknown"


static func _step_roll(state: Dictionary, dt: float) -> void:
	var vx := float(state.get("vx", 0.0))
	var vy := float(state.get("vy", 0.0))
	var speed := _hypot2(vx, vy)
	if speed <= STOP_SPEED_FPS:
		state["vx"] = 0.0
		state["vy"] = 0.0
		state["mode"] = MODE_STOPPED
		return
	var factor := maxf(0.0, 1.0 - (ROLL_DECEL_FPS2 * dt) / speed)
	vx *= factor
	vy *= factor
	state["vx"] = vx
	state["vy"] = vy
	state["x"] = float(state.get("x", 0.0)) + vx * dt
	state["y"] = float(state.get("y", 0.0)) + vy * dt
	_wall_check(state)


static func _step_air(state: Dictionary, dt: float) -> void:
	var vx := float(state.get("vx", 0.0))
	var vy := float(state.get("vy", 0.0))
	var vz := float(state.get("vz", 0.0))
	var speed := _hypot3(vx, vy, vz)
	var drag := QUADRATIC_DRAG * speed
	vx -= drag * vx * dt
	vy -= drag * vy * dt
	vz -= (GRAVITY_FPS2 + drag * vz - float(state.get("lift", 0.0)) * BACKSPIN_LIFT * speed) * dt
	state["vx"] = vx
	state["vy"] = vy
	state["vz"] = vz
	state["x"] = float(state.get("x", 0.0)) + vx * dt
	state["y"] = float(state.get("y", 0.0)) + vy * dt
	state["z"] = float(state.get("z", 0.0)) + vz * dt
	_wall_check(state)

	var z := float(state["z"])
	vz = float(state["vz"])
	if z <= 0.0 and vz < 0.0:
		state["z"] = 0.0
		if -vz > ROLL_VERTICAL_THRESHOLD_FPS:
			state["vz"] = -vz * BOUNCE_VERTICAL
			state["vx"] = float(state["vx"]) * BOUNCE_HORIZONTAL
			state["vy"] = float(state["vy"]) * BOUNCE_HORIZONTAL
			state["bounces"] = int(state.get("bounces", 0)) + 1
			state["lift"] = 0.0
		else:
			state["vz"] = 0.0
			state["mode"] = MODE_ROLL


static func _wall_check(state: Dictionary) -> void:
	var x := float(state.get("x", 0.0))
	var y := float(state.get("y", 0.0))
	var radius := _hypot2(x, y)
	if radius < 1.0:
		return
	var spray := ParkGeometry.spray_degrees(x, y)
	var fence := ParkGeometry.fence_distance(spray)
	if radius < fence or float(state.get("z", 0.0)) > ParkGeometry.fence_height(spray):
		return
	var clamp_factor := fence / radius
	x *= clamp_factor
	y *= clamp_factor
	state["x"] = x
	state["y"] = y
	var nx := x / fence
	var ny := y / fence
	var vx := float(state.get("vx", 0.0))
	var vy := float(state.get("vy", 0.0))
	var radial_velocity := vx * nx + vy * ny
	if radial_velocity > 0.0:
		state["vx"] = vx - 1.35 * radial_velocity * nx
		state["vy"] = vy - 1.35 * radial_velocity * ny
		state["vz"] = minf(float(state.get("vz", 0.0)), 0.0) * 0.4
		state["wall"] = true
		state["lift"] = 0.0


static func _number(source: Dictionary, keys: Array, fallback: float) -> float:
	for key in keys:
		if source.has(key) and (typeof(source[key]) == TYPE_INT or typeof(source[key]) == TYPE_FLOAT):
			return float(source[key])
	return fallback


static func _hypot2(x: float, y: float) -> float:
	return sqrt(x * x + y * y)


static func _hypot3(x: float, y: float, z: float) -> float:
	return sqrt(x * x + y * y + z * z)
