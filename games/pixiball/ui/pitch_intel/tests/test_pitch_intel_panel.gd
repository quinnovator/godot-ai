extends SceneTree

const PANEL_SCENE := preload("res://ui/pitch_intel/pitch_intel_panel.tscn")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var panel := PANEL_SCENE.instantiate()
	root.add_child(panel)
	await process_frame

	_check(not panel.visible, "the reusable panel should start hidden")
	_check(panel.get_combined_minimum_size().x <= 320.0, "panel must fit one half of a 640-wide viewport")
	_check(panel.get_combined_minimum_size().y <= 360.0, "panel must fit a 360-high viewport")

	panel.present({
		"code": "SL",
		"name": "Slider",
		"velocity_mph": 87.6,
		"stage1": {
			"ball": 0.22,
			"called_strike": 0.38,
			"swinging_strike": 0.27,
			"foul": 0.08,
			"in_play": 0.05,
		},
		"contact": {
			"out": 0.70,
			"single": 0.18,
			"double": 0.08,
			"triple": 0.03,
			"home_run": 0.01,
		},
		"erv": -0.084,
		"erv_actual": -0.112,
		"miss_in": 1.2,
		"sequence": {
			"tunnel_in": 2.1,
			"plate_sep_in": 8.4,
			"ratio": 4.0,
		},
		"classification": "frontdoor_corner_paint",
		"in_zone": true,
		"corner_margin_in": 0.4,
		"rank": 2,
		"options": [
			{"rank": 1, "code": "CH", "erv": -0.128},
			{"rank": 2, "code": "SL", "erv": -0.084, "thrown": true},
			{"rank": 3, "code": "FF", "erv": -0.031},
			{"rank": 4, "code": "CT", "erv": 0.014},
			{"rank": 5, "code": "CB", "erv": 0.067},
		],
		"diagram": {
			"release": [-1.8, 5.2],
			"tunnel": [-0.95, 3.0],
			"plate": [-0.68, 2.0],
			"target": [-0.70, 2.0],
			"previous_tunnel": [-0.92, 3.02],
			"previous_plate": [0.25, 2.8],
		},
	})
	# Exercise the custom diagram draw path, not only its data contract.
	await process_frame

	_check(panel.visible, "present(report) should reveal the panel")
	_check(panel.has_report(), "present(report) should retain semantic report state")
	_check(_label(panel, "%PitchCode").text == "SL", "pitch code should render")
	_check(_label(panel, "%PitchName").text == "SLIDER", "pitch name should render")
	_check(_label(panel, "%Velocity").text == "87.6 MPH", "velocity should render")
	_check(_label(panel, "%Rank").text == "CALL #2/5", "arsenal call rank should render")
	_check(_label(panel, "%Tag").text == "FRONTDOOR • PAINTED • DECEPTIVE",
		"door, corner-paint, and deceptive classifications should compose")
	_check(_label(panel, "%Erv").text == "CALL xRV -0.084     ACTUAL xRV -0.112",
		"called and actual expected run value should render together")
	_check(_label(panel, "%Tunnel").text == "TUNNEL Δ 2.1″", "tunnel distance should render")
	_check(_label(panel, "%Separation").text == "PLATE SEP 8.4″", "plate separation should render")
	_check(_label(panel, "%Ratio").text == "BREAK:TUNNEL ×4.00", "break-to-tunnel ratio should render")
	_check(is_equal_approx(float(panel.get_node("%Stage1/Ball/Bar").value), 0.22),
		"stage-one probabilities should drive bars")
	_check(panel.get_node("%Stage1/Ball/Value").text == "22.0%", "stage-one percentages should render")
	_check(is_equal_approx(float(panel.get_node("%Contact/Homer/Bar").value), 0.01),
		"contact probabilities should drive bars")
	_check(panel.get_node("%Options/Option0/Code").text == "CH", "arsenal rows should preserve model rank order")
	_check(panel.get_node("%Options/Option1/Code").text == "SL", "selected arsenal pitch should render")
	_check(float(panel.get_node("%Options/Option4/Bar").value) >= 0.12,
		"lowest-ranked xRV option should retain the source HUD's visible 12% floor")
	_check(panel.get_node("%Diagram").has_pitch_data(), "diagram should accept semantic pitch coordinates")

	panel.hide()
	_check(not panel.visible, "callers should be able to hide without destroying the report")
	_check(panel.has_report(), "hide() should preserve report state for presentation transitions")
	panel.show()
	panel.clear()
	_check(not panel.visible, "clear() should hide the panel")
	_check(not panel.has_report(), "clear() should release report state")
	_check(_label(panel, "%PitchCode").text == "--", "clear() should reset labels")
	_check(is_zero_approx(float(panel.get_node("%Stage1/Ball/Bar").value)), "clear() should reset bars")
	_check(not panel.get_node("%Options/Option0").visible, "clear() should hide arsenal rows")
	_check(not panel.get_node("%Diagram").has_pitch_data(), "clear() should reset the diagram")

	# The original PixCore C++ structs serialize with PascalCase fields. Keep
	# that contract at the presentation boundary so a port does not need a
	# UI-specific translation object.
	panel.present({
		"Code": "FF",
		"Name": "Four Seam",
		"Velocity": 96.25,
		"Rank": 1,
		"Erv": -0.141,
		"ErvActual": -0.155,
		"MissIn": 0.5,
		"Seq": {"TunnelIn": 1.8, "PlateSepIn": 6.2, "Ratio": 3.44},
		"Options": [
			{"Slot": 0, "Code": "FF", "Erv": -0.141},
			{"Slot": 1, "Code": "SL", "Erv": -0.072},
		],
		"Result": {
			"PBall": 0.10,
			"PCalledStrike": 0.32,
			"PSwingingStrike": 0.36,
			"PFoul": 0.12,
			"PInPlay": 0.10,
			"POut": 0.07,
			"PSingle": 0.015,
			"PDouble": 0.008,
			"PTriple": 0.002,
			"PHomeRun": 0.005,
			"ActualX": -0.65,
			"ActualZ": 1.55,
			"AsPrev": {"XTunnel": -0.72, "ZTunnel": 2.9},
		},
	})
	_check(_label(panel, "%PitchCode").text == "FF", "PixCore Code should render without translation")
	_check(_label(panel, "%PitchName").text == "FOUR SEAM", "PixCore Name should render without translation")
	_check(_label(panel, "%Ratio").text == "BREAK:TUNNEL ×3.44", "PixCore Seq should render without translation")
	_check(is_equal_approx(float(panel.get_node("%Stage1/Whiff/Bar").value), 0.36),
		"PixCore Result stage-one probabilities should render")
	_check(is_equal_approx(float(panel.get_node("%Contact/Homer/Bar").value), 0.005),
		"PixCore Result contact probabilities should render")
	_check(panel.get_node("%Diagram").has_pitch_data(), "PixCore Result plate coordinates should feed the diagram")

	var exit_code := 0
	if _failures.is_empty():
		print("PIXIBALL_PITCH_INTEL_SMOKE_OK")
	else:
		for failure in _failures:
			push_error(failure)
		exit_code = 1
	panel.queue_free()
	await process_frame
	quit(exit_code)


func _label(panel: Control, path: String) -> Label:
	return panel.get_node(path) as Label


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
