extends SceneTree

const PitchModelScript = preload("res://core/model/pitch_model.gd")
const PixRngScript = preload("res://core/model/pix_rng.gd")

const EPSILON := 0.000002


func _init() -> void:
	_test_boosters()
	_test_pitch_queries()
	print("PIXIBALL_PITCH_MODEL_OK boosters=48 queries=20")
	quit(0)


func _test_boosters() -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://content/data/golden/booster_vectors.json"))
	var specifications := [
		["stage1", "stage1.xgb.bin", "features"],
		["launchSpeed", "launch_speed.xgb.bin", "features"],
		["launchAngle", "launch_angle.xgb.bin", "features"],
		["stage2", "stage2.xgb.bin", "launch"],
	]
	for specification in specifications:
		var output_key := String(specification[0])
		var model = ClassDB.instantiate("AITreeModel")
		assert(model != null)
		assert(int(model.load_model("res://content/data/models/%s" % String(specification[1]))) == OK)
		var feature_rows: Array = fixture[String(specification[2])]
		var expected_rows: Array = fixture[output_key]
		assert(feature_rows.size() == expected_rows.size())
		for index in range(feature_rows.size()):
			var input_values: Array = feature_rows[index]
			if output_key == "stage2":
				input_values = (fixture.features[index] as Array).duplicate()
				input_values.append_array(feature_rows[index])
			var actual: PackedFloat64Array = model.predict(PackedFloat32Array(input_values))
			var expected: Variant = expected_rows[index]
			if expected is Array:
				assert(actual.size() == expected.size())
				for class_index in range(actual.size()):
					_assert_close(actual[class_index], float(expected[class_index]), "%s[%d][%d]" % [output_key, index, class_index], 0.0001)
			else:
				assert(actual.size() == 1)
				_assert_close(actual[0], float(expected), "%s[%d]" % [output_key, index], 0.0001)


func _test_pitch_queries() -> void:
	var model = PitchModelScript.new()
	assert(model.load_from_directory())
	var fixtures: Array = JSON.parse_string(FileAccess.get_file_as_string("res://content/data/golden/pitchmodel_vectors.json"))
	assert(fixtures.size() == 20)
	var fields := {
		"pBall": ["probabilities", "ball"],
		"pCalledStrike": ["probabilities", "called_strike"],
		"pSwingingStrike": ["probabilities", "swinging_strike"],
		"pFoul": ["probabilities", "foul"],
		"pInPlay": ["probabilities", "in_play"],
		"pOut": ["probabilities", "out"],
		"pSingle": ["probabilities", "single"],
		"pDouble": ["probabilities", "double"],
		"pTriple": ["probabilities", "triple"],
		"pHomeRun": ["probabilities", "home_run"],
		"sampledLaunchSpeed": ["sampled_launch_speed"],
		"sampledLaunchAngle": ["sampled_launch_angle"],
		"expectedRunValue": ["expected_run_value"],
		"actualX": ["actual_x"],
		"actualZ": ["actual_z"],
		"tunnelDiffIn": ["tunnel_diff_in"],
		"breakDiffIn": ["break_diff_in"],
		"breakTunnelRatio": ["break_tunnel_ratio"],
		"shapeDist": ["shape_dist"],
	}
	for fixture_value in fixtures:
		var fixture: Dictionary = fixture_value
		var rng = PixRngScript.new(int(fixture.seedState))
		var actual: Dictionary = model.query(fixture.query, rng)
		assert(bool(actual.ok))
		var expected: Dictionary = fixture.result
		for expected_key in fields:
			var path: Array = fields[expected_key]
			var actual_value: Variant = actual
			for part in path:
				actual_value = (actual_value as Dictionary)[part]
			_assert_close(float(actual_value), float(expected[expected_key]), "query %d %s" % [int(fixture.id), expected_key])
		assert(int(actual.zone) == int(expected.zone))
		assert(bool(actual.in_zone) == bool(expected.inZone))
		var previous: Dictionary = actual.as_prev
		var expected_previous: Dictionary = expected.asPrev
		var previous_fields := {
			"velocity": "velocity", "plateX": "plate_x", "plateZ": "plate_z",
			"pfxX": "pfx_x", "pfxZ": "pfx_z", "vaa": "vaa", "haa": "haa",
			"xTunnel": "x_tunnel", "zTunnel": "z_tunnel",
			"lateBreakX": "late_break_x", "lateBreakZ": "late_break_z",
		}
		for expected_key in previous_fields:
			_assert_close(float(previous[previous_fields[expected_key]]), float(expected_previous[expected_key]), "query %d asPrev.%s" % [int(fixture.id), expected_key])


func _assert_close(actual: float, expected: float, context: String, epsilon := EPSILON) -> void:
	var tolerance := epsilon * maxf(1.0, absf(expected))
	assert(absf(actual - expected) <= tolerance, "%s expected %s got %s delta %s" % [context, str(expected), str(actual), str(actual - expected)])
