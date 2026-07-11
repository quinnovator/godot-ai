class_name PixPitchModel
extends RefCounted

## Exact GDScript feature packer for the original four-model pitch pipeline.
## Tree evaluation is delegated to the fork's native `AITreeModel` module.

const PixRngScript = preload("res://core/model/pix_rng.gd")

const STAGE1_LABELS := ["ball", "called_strike", "swinging_strike", "foul", "in_play"]
const CONTACT_LABELS := ["out", "single", "double", "triple", "home_run"]
const FEATURE_NAMES := [
	"release_speed", "effective_speed", "release_spin_rate", "spin_axis",
	"pfx_x_sym", "pfx_z", "release_pos_x_sym", "release_pos_z",
	"release_extension", "arm_angle", "vaa", "haa_sym", "vaa_resid",
	"haa_resid", "late_break_x", "late_break_z", "late_break_total",
	"plate_x", "plate_z", "zone", "balls", "strikes", "outs_when_up",
	"pitch_number", "n_thruorder_pitcher", "platoon", "archetype_encoded",
	"velo_delta", "shape_dist", "same_shape", "location_change",
	"tunnel_diff_in", "break_diff_in", "break_tunnel_ratio",
	"late_break_diff", "vaa_delta", "haa_delta",
]

const SZ_TOP := 3.5
const SZ_BOTTOM := 1.5
const PLATE_HALF := 17.0 / 24.0
const MIN_IN_PLAY_P := 0.001
const TUNNEL_T_FRAC := 0.52
const TUNNEL_PFX_SHIFT := 0.3
const SHAPE_DIST_SCALE := 5.0
const MIN_TUNNEL_DIFF_IN := 0.5

var _stage1: Variant
var _stage2: Variant
var _launch_speed: Variant
var _launch_angle: Variant
var _meta: Dictionary = {}
var _columns: Dictionary = {}
var _valid := false
var last_error := ""


func load_from_directory(data_dir := "res://content/data") -> bool:
	_valid = false
	last_error = ""
	if not ClassDB.class_exists("AITreeModel"):
		last_error = "This build does not include the godot_ai_model module (AITreeModel)"
		return false
	var meta_path := "%s/modelMeta.json" % data_dir.trim_suffix("/")
	if not FileAccess.file_exists(meta_path):
		last_error = "Missing model metadata: %s" % meta_path
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(meta_path))
	if not parsed is Dictionary:
		last_error = "Invalid model metadata: %s" % meta_path
		return false
	_meta = parsed
	var feature_columns: Array = _meta.get("featureColumns", [])
	if feature_columns.size() != FEATURE_NAMES.size():
		last_error = "Pitch model metadata must define exactly 37 features"
		return false
	_columns.clear()
	for index in range(feature_columns.size()):
		_columns[String(feature_columns[index])] = index
	for feature in FEATURE_NAMES:
		if not _columns.has(feature):
			last_error = "Pitch model metadata is missing feature: %s" % feature
			return false

	_stage1 = _load_tree("%s/models/stage1.xgb.bin" % data_dir.trim_suffix("/"))
	_stage2 = _load_tree("%s/models/stage2.xgb.bin" % data_dir.trim_suffix("/"))
	_launch_speed = _load_tree("%s/models/launch_speed.xgb.bin" % data_dir.trim_suffix("/"))
	_launch_angle = _load_tree("%s/models/launch_angle.xgb.bin" % data_dir.trim_suffix("/"))
	if _stage1 == null or _stage2 == null or _launch_speed == null or _launch_angle == null:
		return false
	if int(_stage1.get_num_features()) != 37 or int(_stage2.get_num_features()) != 39:
		last_error = "Pitch model feature counts do not match the frozen contract"
		return false
	_valid = true
	return true


func is_valid() -> bool:
	return _valid


func metadata() -> Dictionary:
	return _meta.duplicate(true)


func query(request: Dictionary, rng: Variant) -> Dictionary:
	if not _valid:
		return {"ok": false, "error": last_error}
	if rng == null:
		rng = PixRngScript.new(0)
	var shape: Dictionary = request.get("shape", {})
	var batter: Dictionary = request.get("batter", {})
	var at_bat: Dictionary = request.get("ab", {})
	var previous_value: Variant = request.get("prev", null)
	var throws_left := String(request.get("p_throws", request.get("pThrows", "R"))).to_upper() == "L"
	var batter_left := String(batter.get("stand", "R")).to_upper() == "L"
	var target_x := float(request.get("target_x", request.get("targetX", 0.0)))
	var target_z := float(request.get("target_z", request.get("targetZ", 2.5)))

	var actual_x: float = target_x + float(rng.gauss(0.0, _shape_value(shape, "control_x_std", "controlXStd")))
	var actual_z: float = target_z + float(rng.gauss(0.0, _shape_value(shape, "control_z_std", "controlZStd")))
	var velocity: float = _shape_value(shape, "velocity", "velocity")
	var effective_speed: float = _shape_value(shape, "effective_speed", "effectiveSpeed")
	var pfx_x: float = _shape_value(shape, "pfx_x", "pfxX")
	var pfx_z: float = _shape_value(shape, "pfx_z", "pfxZ")
	var release_x: float = _shape_value(shape, "release_x", "releaseX")
	var release_z: float = _shape_value(shape, "release_z", "releaseZ")
	var pfx_x_sym: float = -pfx_x if throws_left else pfx_x
	var plate_x_sym: float = -actual_x if throws_left else actual_x
	var release_x_sym: float = -release_x if throws_left else release_x
	var platoon := (2 if throws_left else 0) + (1 if batter_left else 0)

	var approach: Dictionary = _meta.get("approachAngle", {})
	var vaa_meta: Dictionary = approach.get("vaa", {})
	var haa_meta: Dictionary = approach.get("haa", {})
	var vaa_coef: Array = vaa_meta.get("coef", [0.0, 0.0])
	var haa_coef: Array = haa_meta.get("coef", [0.0, 0.0])
	var expected_vaa: float = float(vaa_meta.get("intercept", 0.0)) + float(vaa_coef[0]) * velocity + float(vaa_coef[1]) * actual_z
	var expected_haa: float = float(haa_meta.get("intercept", 0.0)) + float(haa_coef[0]) * velocity + float(haa_coef[1]) * plate_x_sym
	var vaa: float = expected_vaa - pfx_z * 12.0 * 0.02
	var haa_resid_term: float = (-pfx_x if not throws_left else pfx_x) * 12.0 * 0.01
	var haa: float = expected_haa + haa_resid_term
	var haa_sym: float = -haa if throws_left else haa
	var vaa_resid: float = vaa - expected_vaa
	var haa_resid: float = haa_sym - expected_haa

	var tunnel: Vector2 = tunnel_position(shape, actual_x, actual_z)
	var late_break_x: float = (actual_x - tunnel.x) * 12.0
	var late_break_z: float = (actual_z - tunnel.y) * 12.0
	var late_break_total: float = Vector2(late_break_x, late_break_z).length()
	var velocity_delta := 0.0
	var shape_distance := 0.0
	var same_shape := 0.0
	var location_change := 0.0
	var tunnel_diff := 0.0
	var break_diff := 0.0
	var break_tunnel_ratio := 1.0
	var late_break_diff := 0.0
	var vaa_delta := 0.0
	var haa_delta := 0.0
	if previous_value is Dictionary and not previous_value.is_empty():
		var previous: Dictionary = previous_value
		var previous_left := String(previous.get("p_throws", previous.get("pThrows", "R"))).to_upper() == "L"
		var previous_pfx_x := float(previous.get("pfx_x", previous.get("pfxX", 0.0)))
		var previous_pfx_x_sym: float = -previous_pfx_x if previous_left else previous_pfx_x
		var previous_haa := float(previous.get("haa", 0.0))
		var previous_haa_sym: float = -previous_haa if previous_left else previous_haa
		velocity_delta = velocity - float(previous.get("velocity", 0.0))
		location_change = Vector2(
			actual_x - float(previous.get("plate_x", previous.get("plateX", 0.0))),
			actual_z - float(previous.get("plate_z", previous.get("plateZ", 0.0)))
		).length()
		var d_pfx_x: float = (pfx_x_sym - previous_pfx_x_sym) / SHAPE_DIST_SCALE
		var d_pfx_z: float = (pfx_z - float(previous.get("pfx_z", previous.get("pfxZ", 0.0)))) / SHAPE_DIST_SCALE
		var d_velocity: float = velocity_delta / SHAPE_DIST_SCALE
		var d_vaa: float = vaa - float(previous.get("vaa", 0.0))
		var d_haa: float = haa_sym - previous_haa_sym
		shape_distance = sqrt(d_pfx_x * d_pfx_x + d_pfx_z * d_pfx_z + d_velocity * d_velocity + d_vaa * d_vaa + d_haa * d_haa)
		same_shape = 1.0 if shape_distance < 1.0 else 0.0
		tunnel_diff = Vector2(
			tunnel.x - float(previous.get("x_tunnel", previous.get("xTunnel", 0.0))),
			tunnel.y - float(previous.get("z_tunnel", previous.get("zTunnel", 0.0)))
		).length() * 12.0
		break_diff = location_change * 12.0
		break_tunnel_ratio = break_diff / tunnel_diff if tunnel_diff > MIN_TUNNEL_DIFF_IN else 1.0
		late_break_diff = Vector2(
			late_break_x - float(previous.get("late_break_x", previous.get("lateBreakX", 0.0))),
			late_break_z - float(previous.get("late_break_z", previous.get("lateBreakZ", 0.0)))
		).length()
		vaa_delta = d_vaa
		haa_delta = d_haa

	var feature_values := {
		"release_speed": velocity,
		"effective_speed": effective_speed,
		"release_spin_rate": _shape_value(shape, "spin_rate", "spinRate"),
		"spin_axis": _shape_value(shape, "spin_axis", "spinAxis"),
		"pfx_x_sym": pfx_x_sym,
		"pfx_z": pfx_z,
		"release_pos_x_sym": release_x_sym,
		"release_pos_z": release_z,
		"release_extension": _shape_value(shape, "extension", "extension"),
		"arm_angle": _shape_value(shape, "arm_angle", "armAngle"),
		"vaa": vaa,
		"haa_sym": haa_sym,
		"vaa_resid": vaa_resid,
		"haa_resid": haa_resid,
		"late_break_x": late_break_x,
		"late_break_z": late_break_z,
		"late_break_total": late_break_total,
		"plate_x": actual_x,
		"plate_z": actual_z,
		"zone": map_zone(actual_x, actual_z),
		"balls": int(at_bat.get("balls", 0)),
		"strikes": int(at_bat.get("strikes", 0)),
		"outs_when_up": int(at_bat.get("outs", 0)),
		"pitch_number": int(at_bat.get("pitch_number", at_bat.get("pitchNumber", 1))),
		"n_thruorder_pitcher": int(at_bat.get("times_through_order", at_bat.get("timesThroughOrder", 1))),
		"platoon": platoon,
		"archetype_encoded": int(batter.get("archetype_encoded", batter.get("archetypeEncoded", 0))),
		"velo_delta": velocity_delta,
		"shape_dist": shape_distance,
		"same_shape": same_shape,
		"location_change": location_change,
		"tunnel_diff_in": tunnel_diff,
		"break_diff_in": break_diff,
		"break_tunnel_ratio": break_tunnel_ratio,
		"late_break_diff": late_break_diff,
		"vaa_delta": vaa_delta,
		"haa_delta": haa_delta,
	}
	var features := PackedFloat32Array()
	features.resize(FEATURE_NAMES.size() + 2)
	for feature in FEATURE_NAMES:
		features[int(_columns[feature])] = float(feature_values[feature])
	var stage1: PackedFloat64Array = _stage1.predict(features.slice(0, FEATURE_NAMES.size()))
	if stage1.size() != 5:
		return {"ok": false, "error": "Stage-one pitch model returned an invalid result"}

	var contact := PackedFloat64Array([0.0, 0.0, 0.0, 0.0, 0.0])
	var sampled_launch_speed := 0.0
	var sampled_launch_angle := 0.0
	if stage1[4] > MIN_IN_PLAY_P:
		var shared := features.slice(0, FEATURE_NAMES.size())
		var launch_speed_prediction: PackedFloat64Array = _launch_speed.predict(shared)
		var launch_angle_prediction: PackedFloat64Array = _launch_angle.predict(shared)
		var sampler: Dictionary = _meta.get("launchSampler", {})
		var z1: float = rng.gauss()
		var z2: float = rng.gauss()
		var speed_std := float(sampler.get("launchSpeedStd", 0.0))
		var angle_std := float(sampler.get("launchAngleStd", 0.0))
		var correlation := float(sampler.get("residualCorrelation", 0.0))
		sampled_launch_speed = clampf(launch_speed_prediction[0] + speed_std * z1, 30.0, 120.0)
		sampled_launch_angle = clampf(
			launch_angle_prediction[0] + correlation * angle_std * z1 + angle_std * sqrt(1.0 - correlation * correlation) * z2,
			-90.0,
			90.0
		)
		features[FEATURE_NAMES.size()] = sampled_launch_speed
		features[FEATURE_NAMES.size() + 1] = sampled_launch_angle
		var stage2: PackedFloat64Array = _stage2.predict(features)
		for index in range(5):
			contact[index] = stage1[4] * stage2[index]

	var run_values: Dictionary = _meta.get("runValues", {})
	var expected_run_value := (
		stage1[0] * float(run_values.get("ball", 0.0))
		+ stage1[1] * float(run_values.get("calledStrike", 0.0))
		+ stage1[2] * float(run_values.get("swingingStrike", 0.0))
		+ stage1[3] * float(run_values.get("foul", 0.0))
		+ contact[0] * float(run_values.get("inPlayOut", 0.0))
		+ contact[1] * float(run_values.get("single", 0.0))
		+ contact[2] * float(run_values.get("double", 0.0))
		+ contact[3] * float(run_values.get("triple", 0.0))
		+ contact[4] * float(run_values.get("homeRun", 0.0))
	)
	var probabilities := {}
	for index in range(5):
		probabilities[STAGE1_LABELS[index]] = stage1[index]
		probabilities[CONTACT_LABELS[index]] = contact[index]
	var previous_state := {
		"velocity": velocity,
		"plate_x": actual_x,
		"plate_z": actual_z,
		"pfx_x": pfx_x,
		"pfx_z": pfx_z,
		"vaa": vaa,
		"haa": haa,
		"p_throws": "L" if throws_left else "R",
		"x_tunnel": tunnel.x,
		"z_tunnel": tunnel.y,
		"late_break_x": late_break_x,
		"late_break_z": late_break_z,
	}
	return {
		"ok": true,
		"probabilities": probabilities,
		"stage1": stage1,
		"contact": contact,
		"sampled_launch_speed": sampled_launch_speed,
		"sampled_launch_angle": sampled_launch_angle,
		"expected_run_value": expected_run_value,
		"actual_x": actual_x,
		"actual_z": actual_z,
		"target_x": target_x,
		"target_z": target_z,
		"zone": map_zone(actual_x, actual_z),
		"in_zone": is_in_zone(actual_x, actual_z),
		"tunnel_x": tunnel.x,
		"tunnel_z": tunnel.y,
		"tunnel_diff_in": tunnel_diff,
		"break_diff_in": break_diff,
		"break_tunnel_ratio": break_tunnel_ratio,
		"shape_dist": shape_distance,
		"late_break_x": late_break_x,
		"late_break_z": late_break_z,
		"as_prev": previous_state,
		"features": features.slice(0, FEATURE_NAMES.size()),
	}


func build_report(context: Dictionary, thrown: Dictionary, samples := 4) -> Dictionary:
	var arsenal: Array = context.get("arsenal", [])
	var selected_slot := int(context.get("slot", 0))
	var options: Array[Dictionary] = []
	for slot in range(arsenal.size()):
		var shape: Dictionary = (arsenal[slot] as Dictionary).duplicate(true)
		shape["controlXStd"] = 0.0
		shape["controlZStd"] = 0.0
		shape["control_x_std"] = 0.0
		shape["control_z_std"] = 0.0
		var mixed_seed := int(context.get("seed", 0)) ^ (((slot + 1) * 0x9e3779b9) & 0xffffffff)
		var report_rng := PixRngScript.new(mixed_seed)
		var sum := 0.0
		for _sample in range(maxi(1, samples)):
			var request := context.duplicate(true)
			request["shape"] = shape
			var result := query(request, report_rng)
			sum += float(result.get("expected_run_value", 0.0))
		var pitch: Dictionary = arsenal[slot]
		options.append({
			"slot": slot,
			"code": String(pitch.get("code", "P%d" % (slot + 1))),
			"name": String(pitch.get("name", pitch.get("code", "Pitch"))),
			"erv": sum / float(maxi(1, samples)),
		})
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.erv) < float(b.erv))
	var rank := 0
	var called_erv := 0.0
	for index in range(options.size()):
		if int(options[index].slot) == selected_slot:
			rank = index + 1
			called_erv = float(options[index].erv)
			break
	var actual_result: Dictionary = thrown.get("model_result", thrown)
	var thrown_shape: Dictionary = thrown.get("shape", context.get("shape", {}))
	var miss_inches := Vector2(
		float(actual_result.get("actual_x", 0.0)) - float(context.get("target_x", context.get("targetX", 0.0))),
		float(actual_result.get("actual_z", 2.5)) - float(context.get("target_z", context.get("targetZ", 2.5)))
	).length() * 12.0
	return {
		"ok": true,
		"slot": selected_slot,
		"code": String(thrown.get("code", "")),
		"name": String(thrown.get("name", thrown.get("label", "Pitch"))),
		"velocity_mph": float(thrown.get("velocity_mph", 0.0)),
		"outcome": String(thrown.get("outcome", "")),
		"ended_at_bat": String(thrown.get("ended_at_bat", "")),
		"in_zone": bool(actual_result.get("in_zone", false)),
		"miss_in": miss_inches,
		"tunnel_in": float(actual_result.get("tunnel_diff_in", 0.0)),
		"tunnel_diff_in": float(actual_result.get("tunnel_diff_in", 0.0)),
		"plate_separation_in": float(actual_result.get("break_diff_in", 0.0)),
		"break_diff_in": float(actual_result.get("break_diff_in", 0.0)),
		"break_tunnel_ratio": float(actual_result.get("break_tunnel_ratio", 1.0)),
		"options": options,
		"rank": rank,
		"erv": called_erv,
		"erv_actual": float(actual_result.get("expected_run_value", 0.0)),
		"probabilities": actual_result.get("probabilities", {}).duplicate(true),
		"sampled_launch_speed": float(actual_result.get("sampled_launch_speed", 0.0)),
		"sampled_launch_angle": float(actual_result.get("sampled_launch_angle", 0.0)),
		"actual_x": float(actual_result.get("actual_x", 0.0)),
		"actual_z": float(actual_result.get("actual_z", 2.5)),
		"target_x": float(actual_result.get("target_x", 0.0)),
		"target_z": float(actual_result.get("target_z", 2.5)),
		"tunnel_x": float(actual_result.get("tunnel_x", 0.0)),
		"tunnel_z": float(actual_result.get("tunnel_z", 2.5)),
		"release": [
			float(thrown_shape.get("release_x", thrown_shape.get("releaseX", 0.0))),
			float(thrown_shape.get("release_z", thrown_shape.get("releaseZ", 6.0))),
		],
		"target": [float(actual_result.get("target_x", 0.0)), float(actual_result.get("target_z", 2.5))],
		"actual": [float(actual_result.get("actual_x", 0.0)), float(actual_result.get("actual_z", 2.5))],
		"tunnel": [float(actual_result.get("tunnel_x", 0.0)), float(actual_result.get("tunnel_z", 2.5))],
		"previous": (context.get("prev", {}) as Dictionary).duplicate(true) if context.get("prev", null) is Dictionary else {},
	}


static func tunnel_position(shape: Dictionary, actual_x: float, actual_z: float) -> Vector2:
	var release_x := _shape_value_static(shape, "release_x", "releaseX")
	var release_z := _shape_value_static(shape, "release_z", "releaseZ")
	var pfx_x := _shape_value_static(shape, "pfx_x", "pfxX")
	var pfx_z := _shape_value_static(shape, "pfx_z", "pfxZ")
	return Vector2(
		release_x + (actual_x - release_x) * TUNNEL_T_FRAC + pfx_x * TUNNEL_PFX_SHIFT,
		release_z + (actual_z - release_z) * TUNNEL_T_FRAC + pfx_z * TUNNEL_PFX_SHIFT
	)


static func classify_location(result: Dictionary, batter_stand := "R") -> Dictionary:
	var plate_x := float(result.get("actual_x", 0.0))
	var plate_z := float(result.get("actual_z", 2.5))
	var tunnel_x := float(result.get("tunnel_x", plate_x))
	var inside_sign := -1.0 if batter_stand.to_upper() == "R" else 1.0
	var inside_plate := inside_sign * plate_x
	var inside_tunnel := inside_sign * tunnel_x
	var lateral_margin_in := (PLATE_HALF - absf(plate_x)) * 12.0
	var vertical_margin_in := minf(plate_z - SZ_BOTTOM, SZ_TOP - plate_z) * 12.0
	var corner_margin_in := minf(lateral_margin_in, vertical_margin_in)
	var painted := bool(result.get("in_zone", is_in_zone(plate_x, plate_z))) and corner_margin_in >= 0.0 and corner_margin_in <= 1.5
	var door := "none"
	if painted and absf(plate_x) >= PLATE_HALF - 0.125:
		if inside_plate > 0.0 and inside_tunnel > PLATE_HALF:
			door = "frontdoor"
		elif inside_plate < 0.0 and inside_tunnel < -PLATE_HALF:
			door = "backdoor"
	return {
		"door": door,
		"corner_paint": painted,
		"corner_margin_in": corner_margin_in,
		"lateral_margin_in": lateral_margin_in,
		"vertical_margin_in": vertical_margin_in,
		"direction": signf(plate_x - tunnel_x),
	}


static func map_zone(x: float, z: float) -> int:
	var column_width := 17.0 / 12.0 / 3.0
	var column := 0 if x < -column_width else (1 if x < column_width else 2)
	var height := SZ_TOP - SZ_BOTTOM
	var row: int
	if z < SZ_BOTTOM:
		row = 0
	elif z < SZ_BOTTOM + height / 3.0:
		row = 1
	elif z < SZ_BOTTOM + 2.0 * height / 3.0:
		row = 2
	elif z <= SZ_TOP:
		row = 3
	else:
		row = 4
	if row >= 1 and row <= 3:
		return (3 - row) * 3 + column + 1
	return 11 + column


static func is_in_zone(x: float, z: float) -> bool:
	return absf(x) <= PLATE_HALF and z >= SZ_BOTTOM and z <= SZ_TOP


func _load_tree(path: String) -> Variant:
	var model: Variant = ClassDB.instantiate("AITreeModel")
	if model == null:
		last_error = "Could not instantiate AITreeModel"
		return null
	var error := int(model.load_model(path))
	if error != OK:
		last_error = "Could not load %s: %s" % [path, String(model.get_last_error())]
		return null
	return model


func _shape_value(shape: Dictionary, snake_name: String, camel_name: String) -> float:
	return _shape_value_static(shape, snake_name, camel_name)


static func _shape_value_static(shape: Dictionary, snake_name: String, camel_name: String) -> float:
	return float(shape.get(snake_name, shape.get(camel_name, 0.0)))
