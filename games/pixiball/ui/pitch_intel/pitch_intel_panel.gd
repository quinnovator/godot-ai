class_name PixiballPitchIntelPanel
extends Control

## Reusable post-pitch model report, composed as a Lantern Wharf slate board
## (art bible §10.1 "Slate board" + §10.7): an opaque slate plank with an ink
## frame and hard offset shadow, a chalk Header/Numerals/Body hierarchy, the
## finished chalk diagram (tallies, tunnel overlay, lantern-gold target) as its
## centerpiece, and the gold BEST-call line as the recommendation readout.
##
## This scene deliberately knows nothing about the match controller or current
## HUD. Call `present(report)` with semantic model output, and `clear()` (or the
## built-in `hide()`) when the next pitch is selected. Both snake_case and the
## original PixCore camel-case field spellings are accepted at the boundary.

const S := preload("res://ui/pixiball_style.gd")

# UE palette (spec 2a) via the shared style module — same source as the HUD.
const CHALK := S.CHALK
const STEEL := S.STEEL
const SLATE := S.SLATE
const GOLD := S.GOLD
const TEAL := S.TEAL
const GRASS := S.GRASS
const STITCH := S.STITCH

const STAGE1_FIELDS := {
	"Ball": ["ball", "p_ball", "pBall", "PBall"],
	"Called": ["called_strike", "called", "p_called_strike", "pCalledStrike", "PCalledStrike"],
	"Whiff": ["swinging_strike", "whiff", "p_swinging_strike", "pSwingingStrike", "PSwingingStrike"],
	"Foul": ["foul", "p_foul", "pFoul", "PFoul"],
	"InPlay": ["in_play", "contact", "p_in_play", "pInPlay", "PInPlay"],
}

const CONTACT_FIELDS := {
	"Out": ["out", "p_out", "pOut", "POut"],
	"Single": ["single", "p_single", "pSingle", "PSingle"],
	"Double": ["double", "p_double", "pDouble", "PDouble"],
	"Triple": ["triple", "p_triple", "pTriple", "PTriple"],
	"Homer": ["home_run", "homer", "p_home_run", "pHomeRun", "PHomeRun"],
}

@onready var _frame: Panel = $Frame
@onready var _title: Label = $Frame/Title
@onready var _rule: ColorRect = $Frame/Rule
@onready var _data: Control = $Data
@onready var _rank_label: Label = %Rank
@onready var _tag_label: Label = %Tag
@onready var _code_label: Label = %PitchCode
@onready var _name_label: Label = %PitchName
@onready var _velocity_label: Label = %Velocity
@onready var _erv_label: Label = %Erv
@onready var _location_label: Label = %Location
@onready var _tunnel_label: Label = %Tunnel
@onready var _separation_label: Label = %Separation
@onready var _ratio_label: Label = %Ratio
@onready var _diagram: PixiballPitchIntelDiagram = %Diagram
@onready var _stage1_box: VBoxContainer = %Stage1
@onready var _contact_box: VBoxContainer = %Contact
@onready var _options_box: VBoxContainer = %Options
@onready var _card_rank: Label = $Frame/CardRank
@onready var _card_code: Label = $Frame/CardCode
@onready var _card_name: Label = $Frame/CardName
@onready var _card_velocity: Label = $Frame/CardVelocity
@onready var _card_tag: Label = $Frame/CardTag
@onready var _card_erv: Label = $Frame/CardErv
@onready var _card_location: Label = $Frame/CardLocation
@onready var _card_shape: Label = $Frame/CardShape
@onready var _card_ratio: Label = $Frame/CardRatio
@onready var _card_best: Label = $Frame/CardBest

var _stage1_rows: Dictionary = {}
var _contact_rows: Dictionary = {}
var _option_rows: Array[HBoxContainer] = []
var _report: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Match the Unreal report hierarchy: readable body telemetry by default,
	# with score digits promoted separately below.
	var panel_theme := Theme.new()
	panel_theme.set_font("font", "Label", S.FONT_BODY)
	panel_theme.set_font_size("font_size", "Label", 24)
	theme = panel_theme
	_stage1_rows = _collect_probability_rows(_stage1_box, STAGE1_FIELDS.keys())
	_contact_rows = _collect_probability_rows(_contact_box, CONTACT_FIELDS.keys())
	for index in range(5):
		_option_rows.append(_options_box.get_node("Option%d" % index))
	_apply_digit_faces()
	_build_slate_board()
	_reset_content()
	hide()


## Route numeric readouts through the reference score face.
func _apply_digit_faces() -> void:
	for label in [_velocity_label, _erv_label]:
		label.add_theme_font_override("font", S.FONT_SCORE)
	for row_value in _stage1_rows.values():
		(row_value as HBoxContainer).get_node("Value").add_theme_font_override("font", S.FONT_SCORE)
	for row_value in _contact_rows.values():
		(row_value as HBoxContainer).get_node("Value").add_theme_font_override("font", S.FONT_SCORE)
	for row in _option_rows:
		row.get_node("Rank").add_theme_font_override("font", S.FONT_SCORE)
		row.get_node("Erv").add_theme_font_override("font", S.FONT_SCORE)


## Lantern Wharf slate composition, built over the untouched scene: the same slate
## face the diagram authors (HARBOR_WASH) so the whole board reads as one
## chalked surface, an ink frame, and the §10.2 Header/Numerals/Body tiers.
## Gold appears only on the recommendation readouts — the BEST-call line here
## and the diagram's own target ticks.
func _build_slate_board() -> void:
	# 368x416 board inside the clipped 384x432 root leaves room for the hard
	# 16px down-right ink shadow (§10.3) that the old edge-to-edge frame lost.
	_frame.size = Vector2(368, 416)
	_frame.add_theme_stylebox_override(
		"panel", S.panel(S.HARBOR_WASH, S.INK, S.BORDER_PANEL, S.SHADOW_PANEL, 16, 16))

	# Header band: chalk title, quiet steel call-rank, engraved slate rule.
	_style_card(_title, S.FONT_DISPLAY, 24, CHALK, Rect2(16, 16, 208, 32))
	_style_card(_card_rank, S.FONT_BODY, 16, STEEL, Rect2(216, 16, 136, 32))
	_rule.color = S.SHADOW_BLUE
	_rule.position = Vector2(16, 52)
	_rule.size = Vector2(336, 4)

	# Identity row: Numerals tier (VT323 40/28) for code and velocity, Header
	# tier for the pitch name, teal Body tag for the deception/door read.
	_style_card(_card_code, S.FONT_SCORE, 40, CHALK, Rect2(16, 60, 76, 44))
	_style_card(_card_name, S.FONT_DISPLAY, 24, CHALK, Rect2(96, 60, 160, 44))
	_style_card(_card_velocity, S.FONT_SCORE, 28, STEEL, Rect2(256, 60, 96, 44))
	_style_card(_card_tag, S.FONT_BODY, 16, TEAL, Rect2(16, 104, 336, 20))

	# Body telemetry rows under the diagram; the BEST-call line carries the
	# lantern-gold recommended focus (§10.7).
	_style_card(_card_erv, S.FONT_BODY, 16, CHALK, Rect2(16, 320, 192, 20))
	_style_card(_card_location, S.FONT_BODY, 16, STEEL, Rect2(208, 320, 144, 20))
	_card_location.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_card(_card_shape, S.FONT_BODY, 16, STEEL, Rect2(16, 344, 192, 20))
	_style_card(_card_ratio, S.FONT_BODY, 16, TEAL, Rect2(208, 344, 144, 20))
	_card_ratio.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_style_card(_card_best, S.FONT_BODY, 20, GOLD, Rect2(16, 368, 336, 24))

	# Reveal only the finished chalk diagram from the hidden data surface and
	# host it mid-board; every other legacy dashboard node stays a non-drawn
	# data/test contract. Node paths, ownership, and unique names are untouched.
	_data.show()
	for child in _data.get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = child == _diagram
	_diagram.custom_minimum_size = Vector2(336, 180)
	_diagram.position = Vector2(16, 132)
	_diagram.size = Vector2(336, 180)


func _style_card(label: Label, font: Font, font_size: int, color: Color, rect: Rect2) -> void:
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.position = rect.position
	label.size = rect.size


func present(report: Dictionary) -> void:
	_report = report.duplicate(true)
	_apply_identity(report)
	_apply_probabilities(report)
	_apply_erv(report)
	_apply_sequence(report)
	_apply_options(report)
	_apply_classification(report)
	_diagram.present(_diagram_report(report))
	_sync_compact_card(report)
	show()


func clear() -> void:
	_report.clear()
	_reset_content()
	_diagram.clear_data()
	_sync_compact_card({})
	hide()


func has_report() -> bool:
	return not _report.is_empty()


## Mirror the complete semantic report into the visible slate card. The former
## dashboard nodes (all but the hosted diagram) remain hidden as a data/test
## surface, so callers keep the same API while gameplay receives only the
## decisive read.
func _sync_compact_card(report: Dictionary) -> void:
	if report.is_empty():
		_card_rank.text = "--/--"
		_card_code.text = "--"
		_card_name.text = "AWAITING"
		_card_velocity.text = "-- MPH"
		_card_tag.text = "MODEL READY"
		_card_erv.text = "xRV -- / --"
		_card_location.text = "MISS --"
		_card_shape.text = "TUN --  SEP --"
		_card_ratio.text = "BREAK:TUN --"
		_card_best.text = "BEST CALL --"
		return

	_card_rank.text = _rank_label.text.trim_prefix("CALL ")
	_card_code.text = _code_label.text
	_card_name.text = _name_label.text.left(11)
	_card_velocity.text = _velocity_label.text
	_card_tag.text = _tag_label.text
	var called: Variant = _read_number_deep(report, ["erv", "erv_called", "called_erv", "intent_erv", "Erv"])
	var actual: Variant = _read_number_deep(report, ["erv_actual", "actual_erv", "expected_run_value", "expectedRunValue", "ErvActual"])
	_card_erv.text = "xRV %s / %s" % [_format_signed(called), _format_signed(actual)]
	_card_location.text = _location_label.text
	var sequence := _find_dictionary(report, ["sequence", "seq", "Seq", "tunneling"])
	var tunnel: Variant = _read_number_in(sequence, ["tunnel_in", "tunnel_inches", "tunnelIn", "TunnelIn"])
	var separation: Variant = _read_number_in(sequence, ["plate_sep_in", "plate_separation_in", "plateSepIn", "PlateSepIn"])
	_card_shape.text = "TUN %s  SEP %s" % [_compact_number(tunnel), _compact_number(separation)]
	_card_ratio.text = _ratio_label.text.replace("BREAK:TUNNEL", "BREAK:TUN")
	var options := _read_options(report)
	if options.is_empty():
		_card_best.text = "BEST CALL --"
	else:
		var best: Dictionary = options[0]
		_card_best.text = "BEST %s  xRV %s" % [
			_read_string(best, ["code", "pitch_code", "Code"], "--").to_upper(),
			_format_signed(_read_number_in(best, ["erv", "Erv"])),
		]


func _compact_number(value: Variant) -> String:
	return "--" if value == null else "%.1f" % float(value)


func _reset_content() -> void:
	_rank_label.text = "CALL —/—"
	_tag_label.text = "MODEL READY"
	_tag_label.add_theme_color_override("font_color", SLATE)
	_code_label.text = "--"
	_name_label.text = "AWAITING PITCH"
	_velocity_label.text = "— MPH"
	_erv_label.text = "CALL xRV —     ACTUAL xRV —"
	_location_label.text = "MISS —"
	_tunnel_label.text = "TUNNEL Δ —"
	_separation_label.text = "PLATE SEP —"
	_ratio_label.text = "BREAK:TUNNEL —"
	for row_value in _stage1_rows.values():
		_set_probability_row(row_value, null)
	for row_value in _contact_rows.values():
		_set_probability_row(row_value, null)
	for row in _option_rows:
		row.visible = false
		row.get_node("Rank").text = "—"
		row.get_node("Code").text = "--"
		row.get_node("Bar").value = 0.0
		row.get_node("Erv").text = "—"


func _apply_identity(report: Dictionary) -> void:
	var code := _read_string(report, ["code", "pitch_code", "pitchCode", "Code"], "--").to_upper()
	var name := _read_string(report, ["name", "pitch_name", "pitchName", "Name"], "MODEL PITCH").to_upper()
	var velocity: Variant = _read_number_in(report, ["velocity_mph", "velocity", "Velocity"])
	_code_label.text = code
	_name_label.text = name
	_velocity_label.text = "%.1f MPH" % velocity if velocity != null else "— MPH"


func _apply_probabilities(report: Dictionary) -> void:
	for row_name in STAGE1_FIELDS:
		var value: Variant = _read_probability(report, ["probabilities", "stage1", "stage_1", "plate_outcomes"], STAGE1_FIELDS[row_name])
		_set_probability_row(_stage1_rows[row_name], value)
	for row_name in CONTACT_FIELDS:
		var value: Variant = _read_probability(report, ["probabilities", "contact", "stage2", "stage_2", "contact_outcomes"], CONTACT_FIELDS[row_name])
		_set_probability_row(_contact_rows[row_name], value)


func _apply_erv(report: Dictionary) -> void:
	var called: Variant = _read_number_deep(report, ["erv", "erv_called", "called_erv", "intent_erv", "Erv"])
	var actual: Variant = _read_number_deep(report, ["erv_actual", "actual_erv", "expected_run_value", "expectedRunValue", "ErvActual"])
	_erv_label.text = "CALL xRV %s     ACTUAL xRV %s" % [_format_signed(called), _format_signed(actual)]
	if called != null and actual != null:
		_erv_label.add_theme_color_override("font_color", GRASS if float(actual) <= float(called) else GOLD)
	else:
		_erv_label.add_theme_color_override("font_color", STEEL)


func _apply_sequence(report: Dictionary) -> void:
	var sequence := _find_dictionary(report, ["sequence", "seq", "Seq", "tunneling"])
	var miss: Variant = _read_number_deep(report, ["miss_in", "miss_inches", "missIn", "MissIn"])
	var tunnel: Variant = _read_number_in(sequence, ["tunnel_in", "tunnel_inches", "tunnelIn", "TunnelIn"])
	if tunnel == null:
		tunnel = _read_number_deep(report, ["tunnel_diff_in", "tunnelDiffIn", "TunnelDiffIn"])
	var separation: Variant = _read_number_in(sequence, ["plate_sep_in", "plate_separation_in", "plateSepIn", "PlateSepIn"])
	if separation == null:
		separation = _read_number_deep(report, ["break_diff_in", "breakDiffIn", "BreakDiffIn"])
	var ratio: Variant = _read_number_in(sequence, ["ratio", "break_tunnel_ratio", "breakTunnelRatio", "Ratio"])
	if ratio == null:
		ratio = _read_number_deep(report, ["break_tunnel_ratio", "breakTunnelRatio", "BreakTunnelRatio"])

	_location_label.text = "MISS %s" % _format_inches(miss)
	_tunnel_label.text = "TUNNEL Δ %s" % _format_inches(tunnel)
	_separation_label.text = "PLATE SEP %s" % _format_inches(separation)
	_ratio_label.text = "BREAK:TUNNEL ×%.2f" % ratio if ratio != null else "BREAK:TUNNEL —"
	_ratio_label.add_theme_color_override("font_color", TEAL if ratio != null and float(ratio) >= 3.0 else STEEL)


func _apply_options(report: Dictionary) -> void:
	var options := _read_options(report)
	var visible_count := mini(options.size(), _option_rows.size())
	var thrown_rank := _read_integer(report, ["rank", "call_rank", "callRank", "Rank"], 0)
	var best: Variant = null
	var worst: Variant = null
	for option in options:
		var erv: Variant = _read_number_in(option, ["erv", "Erv"])
		if erv != null:
			best = erv if best == null else minf(float(best), float(erv))
			worst = erv if worst == null else maxf(float(worst), float(erv))

	for index in range(_option_rows.size()):
		var row := _option_rows[index]
		row.visible = index < visible_count
		if index >= visible_count:
			continue
		var option: Dictionary = options[index]
		var rank := _read_integer(option, ["rank", "Rank"], index + 1)
		var code := _read_string(option, ["code", "pitch_code", "Code"], "--").to_upper()
		var erv: Variant = _read_number_in(option, ["erv", "Erv"])
		var quality := 0.5
		if erv != null and best != null and worst != null:
			quality = (float(worst) - float(erv)) / maxf(float(worst) - float(best), 0.000001)
		var grade := _read_string(option, ["grade", "Grade"], _grade(quality))
		row.get_node("Rank").text = "#%d" % rank
		row.get_node("Code").text = code
		# Retain the source HUD's 12% legibility floor for the lowest option.
		row.get_node("Bar").value = maxf(0.12, quality)
		row.get_node("Erv").text = "%s %s" % [grade, _format_signed(erv)]
		var thrown := bool(option.get("thrown", option.get("selected", false)))
		if not thrown and thrown_rank > 0:
			thrown = rank == thrown_rank
		row.modulate = Color.WHITE if thrown else Color(0.78, 0.84, 0.91, 0.82)

	var total := options.size()
	if thrown_rank <= 0:
		for index in range(visible_count):
			if bool(options[index].get("thrown", options[index].get("selected", false))):
				thrown_rank = index + 1
				break
	_rank_label.text = "CALL #%d/%d" % [thrown_rank, total] if thrown_rank > 0 and total > 0 else "CALL —/%d" % total


func _apply_classification(report: Dictionary) -> void:
	var tags: Array[String] = []
	var classification := _read_string(report, ["classification", "door", "pitch_classification"], "")
	var normalized := classification.to_lower().replace("_", " ").replace("-", " ")
	if "frontdoor" in normalized or "front door" in normalized or bool(report.get("frontdoor", false)):
		tags.append("FRONTDOOR")
	if "backdoor" in normalized or "back door" in normalized or bool(report.get("backdoor", false)):
		tags.append("BACKDOOR")
	var corner := (
		"corner" in normalized
		or "paint" in normalized
		or bool(report.get("corner_paint", report.get("painted_corner", false)))
	)
	var corner_margin: Variant = _read_number_deep(report, ["corner_margin_in", "zone_margin_in", "cornerMarginIn"])
	var in_zone := bool(report.get("in_zone", report.get("bInZone", false)))
	if not corner and in_zone and corner_margin != null:
		corner = float(corner_margin) >= 0.0 and float(corner_margin) <= 1.5
	if corner:
		tags.append("PAINTED")

	var ratio: Variant = _read_number_deep(report, ["break_tunnel_ratio", "breakTunnelRatio", "BreakTunnelRatio"])
	if ratio == null:
		var sequence := _find_dictionary(report, ["sequence", "seq", "Seq", "tunneling"])
		ratio = _read_number_in(sequence, ["ratio", "break_tunnel_ratio", "breakTunnelRatio"])
	if ratio != null and float(ratio) >= 3.0:
		tags.append("DECEPTIVE")
	if tags.is_empty() and not classification.is_empty():
		tags.append(classification.to_upper())
	_tag_label.text = " • ".join(tags) if not tags.is_empty() else "MODEL READ"
	_tag_label.add_theme_color_override("font_color", GOLD if corner else (TEAL if not tags.is_empty() else SLATE))


func _set_probability_row(row: HBoxContainer, value: Variant) -> void:
	var bar: ProgressBar = row.get_node("Bar")
	var label: Label = row.get_node("Value")
	if value == null:
		bar.value = 0.0
		label.text = "—"
		return
	var probability := float(value)
	if probability > 1.0 and probability <= 100.0:
		probability /= 100.0
	probability = clampf(probability, 0.0, 1.0)
	bar.value = probability
	label.text = "%4.1f%%" % (probability * 100.0)


func _collect_probability_rows(parent: VBoxContainer, names: Array) -> Dictionary:
	var rows := {}
	for row_name in names:
		rows[row_name] = parent.get_node(String(row_name))
	return rows


func _read_probability(report: Dictionary, group_keys: Array, value_keys: Array) -> Variant:
	var sources: Array[Dictionary] = []
	for root_value in [report, report.get("result", {}), report.get("Result", {})]:
		if root_value is not Dictionary:
			continue
		var root_dict: Dictionary = root_value
		for group_key in group_keys:
			var group_value: Variant = root_dict.get(group_key)
			if root_dict.has(group_key) and group_value is Dictionary:
				sources.append(group_value)
		sources.append(root_dict)
	for source in sources:
		var value: Variant = _read_number_in(source, value_keys)
		if value != null:
			return value
	return null


func _read_options(report: Dictionary) -> Array[Dictionary]:
	var raw: Variant = report.get("options", report.get("Options",
		report.get("counterfactuals", report.get("Counterfactuals", []))))
	if raw is not Array:
		var arsenal: Variant = report.get("arsenal", report.get("Arsenal", {}))
		raw = arsenal.get("options", arsenal.get("Options", [])) if arsenal is Dictionary else []
	var options: Array[Dictionary] = []
	for value in raw:
		if value is Dictionary:
			options.append(value.duplicate(true))
	options.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var ar := _read_integer(a, ["rank", "Rank"], 0)
		var br := _read_integer(b, ["rank", "Rank"], 0)
		if ar > 0 or br > 0:
			return (ar if ar > 0 else 999) < (br if br > 0 else 999)
		var ae: Variant = _read_number_in(a, ["erv", "Erv"])
		var be: Variant = _read_number_in(b, ["erv", "Erv"])
		return float(ae if ae != null else INF) < float(be if be != null else INF)
	)
	return options


func _diagram_report(report: Dictionary) -> Dictionary:
	var diagram_value: Variant = report.get("diagram", {})
	var diagram: Dictionary = diagram_value.duplicate(true) if diagram_value is Dictionary else {}
	var result := _find_dictionary(report, ["result", "Result"])
	var as_prev := _find_dictionary(report, ["as_prev", "asPrev", "AsPrev"])
	var previous := _find_dictionary(report, ["previous", "prev", "Prev"])

	_copy_point(report, diagram, "release", ["release"])
	if not diagram.has("release"):
		var release: Variant = _components_point(report, ["release_x", "releaseX"], ["release_z", "releaseZ"])
		if release != null:
			diagram.release = release
	_copy_point(report, diagram, "target", ["target", "aim"])
	_copy_point(report, diagram, "tunnel", ["tunnel", "tunnel_point"])
	if not diagram.has("tunnel"):
		var tunnel: Variant = _components_point(as_prev, ["x_tunnel", "xTunnel", "XTunnel"], ["z_tunnel", "zTunnel", "ZTunnel"])
		if tunnel != null:
			diagram.tunnel = tunnel
	_copy_point(report, diagram, "plate", ["plate", "actual", "actual_plate"])
	if not diagram.has("plate"):
		var plate: Variant = _components_point(result if not result.is_empty() else report,
			["actual_x", "actualX", "ActualX"], ["actual_z", "actualZ", "ActualZ"])
		if plate != null:
			diagram.plate = plate
	_copy_point(report, diagram, "previous_tunnel", ["previous_tunnel", "prev_tunnel"])
	if not diagram.has("previous_tunnel"):
		var prev_tunnel: Variant = _components_point(previous, ["x_tunnel", "xTunnel", "XTunnel"], ["z_tunnel", "zTunnel", "ZTunnel"])
		if prev_tunnel != null:
			diagram.previous_tunnel = prev_tunnel
	_copy_point(report, diagram, "previous_plate", ["previous_plate", "prev_plate"])
	if not diagram.has("previous_plate"):
		var prev_plate: Variant = _components_point(previous, ["plate_x", "plateX", "PlateX"], ["plate_z", "plateZ", "PlateZ"])
		if prev_plate != null:
			diagram.previous_plate = prev_plate
	diagram.classification = _read_string(report, ["classification", "door", "pitch_classification"], "")
	if not diagram.has("confidence"):
		var confidence: Variant = _read_number_deep(report, ["confidence", "conf", "Confidence"])
		if confidence == null:
			# House confidence definition (main.gd _prediction_confidence): the
			# strongest stage-one call, so the chalk tallies always render.
			for field_aliases in STAGE1_FIELDS.values():
				var probability: Variant = _read_probability(
					report, ["probabilities", "stage1", "stage_1", "plate_outcomes"], field_aliases)
				if probability == null:
					continue
				var normalized := float(probability)
				if normalized > 1.0 and normalized <= 100.0:
					normalized /= 100.0
				confidence = maxf(float(confidence) if confidence != null else 0.0, normalized)
		if confidence != null:
			diagram.confidence = confidence
	return diagram


func _copy_point(source: Dictionary, destination: Dictionary, destination_key: String, aliases: Array) -> void:
	if destination.has(destination_key):
		return
	for alias in aliases:
		if source.has(alias):
			destination[destination_key] = source[alias]
			return


func _components_point(source: Dictionary, x_keys: Array, z_keys: Array) -> Variant:
	var x: Variant = _read_number_in(source, x_keys)
	var z: Variant = _read_number_in(source, z_keys)
	return [x, z] if x != null and z != null else null


func _find_dictionary(source: Dictionary, keys: Array) -> Dictionary:
	for key in keys:
		var value: Variant = source.get(key)
		if source.has(key) and value is Dictionary:
			return value
	for result_key in ["result", "Result"]:
		var result: Variant = source.get(result_key)
		if source.has(result_key) and result is Dictionary:
			for key in keys:
				var nested: Variant = result.get(key)
				if result.has(key) and nested is Dictionary:
					return nested
	return {}


func _read_number_deep(source: Dictionary, keys: Array) -> Variant:
	var direct: Variant = _read_number_in(source, keys)
	if direct != null:
		return direct
	for result_key in ["result", "Result"]:
		var result: Variant = source.get(result_key, {})
		if result is Dictionary:
			var nested: Variant = _read_number_in(result, keys)
			if nested != null:
				return nested
	return null


func _read_number_in(source: Dictionary, keys: Array) -> Variant:
	for key in keys:
		if source.has(key) and _is_number(source[key]):
			return float(source[key])
	return null


func _read_integer(source: Dictionary, keys: Array, fallback: int) -> int:
	var value: Variant = _read_number_in(source, keys)
	return int(value) if value != null else fallback


func _read_string(source: Dictionary, keys: Array, fallback: String) -> String:
	for key in keys:
		if source.has(key) and (typeof(source[key]) == TYPE_STRING or typeof(source[key]) == TYPE_STRING_NAME):
			return String(source[key])
	for result_key in ["result", "Result"]:
		var result: Variant = source.get(result_key, {})
		if result is Dictionary:
			for key in keys:
				if result.has(key) and (typeof(result[key]) == TYPE_STRING or typeof(result[key]) == TYPE_STRING_NAME):
					return String(result[key])
	return fallback


func _format_signed(value: Variant) -> String:
	return "%+.3f" % float(value) if value != null else "—"


func _format_inches(value: Variant) -> String:
	return "%.1f″" % float(value) if value != null else "—"


func _grade(quality: float) -> String:
	if quality >= 0.85:
		return "A"
	if quality >= 0.60:
		return "B"
	if quality >= 0.35:
		return "C"
	if quality >= 0.15:
		return "D"
	return "F"


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
