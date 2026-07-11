class_name PixiballHUD
extends CanvasLayer

const C = preload("res://gameplay/game_constants.gd")
const StrikeZone = preload("res://ui/strike_zone.gd")
const PitcherDisplay = preload("res://gameplay/pitcher_display.gd")
const S = preload("res://ui/pixiball_style.gd")

# UE palette (spec 2a), routed through the shared style module so the shell and
# Pitch Intel share one source of truth. Legacy names are remapped to their UE
# roles to keep the ~200 existing references intact.
const INK := S.INK             # borders / frames / the "black"
const DEEP_INK := S.SCOREBOARD # HUD panel inner surface
const PAPER := S.CHALK         # primary "white" text
const CHALK := S.STEEL         # secondary label text
const GOLD := S.GOLD
const TEAL := S.TEAL
const RED := S.STITCH
const BLUE := S.SKY
const SHADOW_BLUE := S.SHADOW_BLUE
const SLATE := S.SLATE
const NIGHT := S.NIGHT
const NIGHT2 := S.NIGHT2
const GRASS := S.GRASS
const CLAY_LIGHT := S.CLAY_LIGHT
const STITCH := S.STITCH

var title_layer: Control
var landing_layer: Control
var pitcher_layer: Control
var team_layer: Control
var final_layer: Control
var game_layer: Control

var landing_cards: Array[PanelContainer] = []
var landing_card_titles: Array[Label] = []
var landing_prompt: Label
var landing_stats: Label
var pitcher_cards: Array[PanelContainer] = []
var pitcher_card_labels: Array[Label] = []
var pitcher_detail_name: Label
var pitcher_detail_metrics: Label
var pitcher_detail_arsenal: Label
var pitcher_stamina: ProgressBar
var team_cards: Array[PanelContainer] = []
var team_card_labels: Array[Label] = []
var team_card_chips: Array[Label] = []
var difficulty_panel: PanelContainer
var difficulty_label: Label
var innings_panel: PanelContainer
var innings_label: Label
var play_ball_panel: PanelContainer
var play_ball_label: Label
var matchup_label: Label
var final_title: Label
var final_score: Label
var final_stats: Label
var final_actions: Array[PanelContainer] = []
var final_action_labels: Array[Label] = []

var score_label: Label
var inning_label: Label
var count_label: Label
var outs_label: Label
var out_lamps: Array[Panel] = []
var bases: Array[Panel] = []
var phase_label: Label
var result_panel: PanelContainer
var result_label: Label
var detail_label: Label
var help_label: Label
var pitch_row: HBoxContainer
var pitch_cards: Array[PanelContainer] = []
var pitch_labels: Array[Label] = []
var title_matchup_label: Label
var strike_zone: PixiballStrikeZone
var identity_label: Label
var field_meter: ProgressBar
var event_feed: VBoxContainer
var event_feed_back: PanelContainer
var stamina_panel: PanelContainer
var stamina_label: Label
var stamina_bar: ProgressBar

var _home_team: Dictionary = C.HOME_TEAM.duplicate(true)
var _away_team: Dictionary = C.AWAY_TEAM.duplicate(true)
var _banner_tween: Tween
var _blink_time := 0.0
var _final_focus := 0
var _stamina_gassed := false


func _ready() -> void:
	layer = 20
	_build_shell()
	_build_game_hud()
	show_landing({}, 0)


func _process(delta: float) -> void:
	_blink_time = fmod(_blink_time + delta, 1.2)
	if landing_prompt != null:
		landing_prompt.modulate.a = 1.0 if _blink_time < 0.6 else 0.28
	if final_layer != null and final_layer.visible:
		for index in range(final_actions.size()):
			final_actions[index].modulate.a = (1.0 if _blink_time < 0.6 else 0.68) if index == _final_focus else 1.0
	if stamina_label != null and stamina_bar != null:
		var stamina_alpha := (1.0 if _blink_time < 0.6 else 0.24) if _stamina_gassed else 1.0
		stamina_label.modulate.a = stamina_alpha
		stamina_bar.modulate.a = stamina_alpha


func _build_shell() -> void:
	title_layer = Control.new()
	title_layer.name = "AppShell"
	title_layer.theme = S.ui_theme()
	title_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title_layer)
	_build_landing()
	_build_pitcher_select()
	_build_team_select()
	_build_final()


func _build_shell_backdrop(layer_node: Control, opacity := 0.82) -> void:
	var wash := ColorRect.new()
	wash.color = Color(DEEP_INK, opacity)
	wash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	wash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_node.add_child(wash)
	var top_rail := ColorRect.new()
	top_rail.color = TEAL
	top_rail.position = Vector2(0, 0)
	top_rail.size = Vector2(1280, 7)
	top_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_node.add_child(top_rail)
	var gold_rail := ColorRect.new()
	gold_rail.color = GOLD
	gold_rail.position = Vector2(0, 7)
	gold_rail.size = Vector2(1280, 3)
	gold_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_node.add_child(gold_rail)


func _build_gradient_band(layer_node: Control, at: Vector2, dimensions: Vector2, color: Color) -> void:
	var band := ColorRect.new()
	band.color = color
	band.position = at
	band.size = dimensions
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer_node.add_child(band)


func _build_hero_title(layer_node: Control, text: String, at: Vector2) -> void:
	# Chunky hard drop-shadow (not ghosting). GeistPixel-Line is an outline/hollow
	# face — stacking three copies of it interleaves strokes and reads as glitchy
	# red/gold ghosting, so the hero uses the SOLID Square face. Tight offsets,
	# solid gold face on top of near-opaque ink/stitch shadow copies (farthest
	# first) give one clean layered drop-shadow.
	var stack := [
		{"offset": Vector2(8, 8), "color": Color(S.INK, 0.6)},
		{"offset": Vector2(4, 4), "color": Color(S.STITCH, 0.9)},
		{"offset": Vector2(0, 0), "color": S.GOLD},
	]
	var hero_font := S.tracked(S.FONT_DISPLAY, 4)
	for spec in stack:
		var copy := _label(text, 84, spec.color)
		copy.add_theme_font_override("font", hero_font)
		copy.position = at + spec.offset
		copy.size = Vector2(700, 100)
		layer_node.add_child(copy)


func _build_landing() -> void:
	landing_layer = Control.new()
	landing_layer.name = "Landing"
	landing_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_layer.add_child(landing_layer)
	# UE landing: 3-band hard gradient (Ink 52% / Night 26% / GrassDeep 22%),
	# three stacked fills with no blend (spec 3j).
	_build_gradient_band(landing_layer, Vector2(0, 0), Vector2(1280, 375), S.INK)
	_build_gradient_band(landing_layer, Vector2(0, 375), Vector2(1280, 187), S.NIGHT)
	_build_gradient_band(landing_layer, Vector2(0, 562), Vector2(1280, 158), S.GRASS_DEEP)
	var top_rail := ColorRect.new()
	top_rail.color = TEAL
	top_rail.size = Vector2(1280, 7)
	top_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	landing_layer.add_child(top_rail)
	var gold_rail := ColorRect.new()
	gold_rail.color = GOLD
	gold_rail.position = Vector2(0, 7)
	gold_rail.size = Vector2(1280, 3)
	gold_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	landing_layer.add_child(gold_rail)
	var eyebrow := _placed_label(landing_layer, "GODOT AI ORIGINAL  /  HARBOR LEAGUE", 17, GOLD, Vector2(72, 43), Vector2(760, 28))
	eyebrow.add_theme_constant_override("outline_size", 5)
	eyebrow.add_theme_color_override("font_outline_color", DEEP_INK)
	# Triple-stacked hero "PIXIBALL" using the Line hero face: ink@0.6 (+12),
	# stitch@0.9 (+6), gold on top (spec 3j).
	_build_hero_title(landing_layer, "PIXIBALL", Vector2(68, 64))
	_placed_label(landing_layer, "PAINT THE BLACK. OWN THE HARBOR.", 22, TEAL, Vector2(75, 162), Vector2(680, 36))
	landing_stats = _placed_label(landing_layer, "BEST ENDLESS  0 K     •     VERSUS  0–0", 18, CHALK, Vector2(740, 78), Vector2(465, 38))
	landing_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var specs := [
		{"title": "ENDLESS PITCH", "kicker": "ONE ARM. THREE RUNS.", "copy": "Choose a starter and survive as long as command,\nsequencing and tunneling can carry you.", "color": GOLD},
		{"title": "VERSUS", "kicker": "FULL HARBOR SHOWDOWN", "copy": "Pick clubs, set the stakes, then pitch, hit, field\nand manage a complete 3 / 6 / 9 inning game.", "color": TEAL},
	]
	for index in range(2):
		var spec: Dictionary = specs[index]
		var card := PanelContainer.new()
		card.position = Vector2(72 + index * 574, 235)
		card.size = Vector2(535, 255)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		landing_layer.add_child(card)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 10)
		card.add_child(stack)
		var number := _label("0%d" % (index + 1), 16, Color(spec.color, 0.8))
		stack.add_child(number)
		var title := _label(String(spec.title), 34, PAPER)
		stack.add_child(title)
		landing_card_titles.append(title)
		stack.add_child(_label(String(spec.kicker), 14, spec.color))
		var copy := _label(String(spec.copy), 17, CHALK)
		copy.add_theme_constant_override("line_spacing", 6)
		stack.add_child(copy)
		stack.add_child(_label("CONFIRM  →", 16, spec.color))
		landing_cards.append(card)
	landing_prompt = _placed_label(landing_layer, "INSERT COIN  —  PRESS START", 22, GOLD, Vector2(390, 548), Vector2(500, 45))
	landing_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_placed_label(landing_layer, "D-PAD / WASD  SELECT     •     A / ENTER / SPACE  CONFIRM", 14, Color(CHALK, 0.84), Vector2(285, 630), Vector2(710, 34)).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


func _build_pitcher_select() -> void:
	pitcher_layer = Control.new()
	pitcher_layer.name = "PitcherSelect"
	pitcher_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_layer.add_child(pitcher_layer)
	_build_shell_backdrop(pitcher_layer)
	_placed_label(pitcher_layer, "ENDLESS PITCH", 15, GOLD, Vector2(48, 29), Vector2(300, 24))
	_placed_label(pitcher_layer, "CHOOSE YOUR ARM", 39, PAPER, Vector2(45, 50), Vector2(650, 52))
	_placed_label(pitcher_layer, "TEN REAL ARSENALS  •  EVERY SHAPE MATTERS", 14, TEAL, Vector2(48, 104), Vector2(650, 24))

	for index in range(10):
		var card := PanelContainer.new()
		card.position = Vector2(46 + (index % 5) * 148, 154 + (index / 5) * 204)
		card.size = Vector2(136, 188)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pitcher_layer.add_child(card)
		var stack := VBoxContainer.new()
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		stack.add_theme_constant_override("separation", 6)
		card.add_child(stack)
		var portrait := _label("◢\nPXL\n◣", 24, Color(TEAL, 0.7))
		portrait.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(portrait)
		var label := _label("STARTER", 14, PAPER)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		stack.add_child(label)
		pitcher_cards.append(card)
		pitcher_card_labels.append(label)

	var detail := PanelContainer.new()
	detail.position = Vector2(805, 80)
	detail.size = Vector2(430, 535)
	detail.add_theme_stylebox_override("panel", _style(Color(0.025, 0.05, 0.1, 0.97), TEAL, 2, 10))
	detail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pitcher_layer.add_child(detail)
	var detail_stack := VBoxContainer.new()
	detail_stack.add_theme_constant_override("separation", 12)
	detail.add_child(detail_stack)
	detail_stack.add_child(_label("SCOUTING CARD", 14, GOLD))
	pitcher_detail_name = _label("STARTER", 29, PAPER)
	detail_stack.add_child(pitcher_detail_name)
	pitcher_detail_metrics = _label("OVR --   ERA --   K/9 --", 17, TEAL)
	detail_stack.add_child(pitcher_detail_metrics)
	detail_stack.add_child(_label("ARSENAL / MIX", 14, GOLD))
	pitcher_detail_arsenal = _label("LOADING", 15, CHALK)
	pitcher_detail_arsenal.add_theme_constant_override("line_spacing", 5)
	detail_stack.add_child(pitcher_detail_arsenal)
	detail_stack.add_child(_label("STARTING STAMINA", 13, CHALK))
	pitcher_stamina = ProgressBar.new()
	pitcher_stamina.custom_minimum_size = Vector2(390, 25)
	pitcher_stamina.min_value = 0.0
	pitcher_stamina.max_value = 1.0
	pitcher_stamina.show_percentage = false
	detail_stack.add_child(pitcher_stamina)
	var cta := _label("A / ENTER  TAKE THE MOUND", 17, INK)
	cta.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cta.custom_minimum_size = Vector2(390, 48)
	cta.add_theme_stylebox_override("normal", _style(GOLD, GOLD, 2, 7))
	detail_stack.add_child(cta)
	title_matchup_label = pitcher_detail_metrics
	_placed_label(pitcher_layer, "← / →  BROWSE     ↑ / ↓  JUMP ROW     •     B / ESC  BACK", 14, Color(CHALK, 0.84), Vector2(45, 665), Vector2(800, 28))


func _build_team_select() -> void:
	team_layer = Control.new()
	team_layer.name = "TeamSelect"
	team_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_layer.add_child(team_layer)
	_build_shell_backdrop(team_layer)
	_placed_label(team_layer, "VERSUS", 15, TEAL, Vector2(48, 28), Vector2(300, 24))
	_placed_label(team_layer, "BUILD THE MATCHUP", 39, PAPER, Vector2(45, 49), Vector2(650, 52))
	matchup_label = _placed_label(team_layer, "P1: PICK A CLUB", 16, GOLD, Vector2(48, 104), Vector2(720, 28))

	for index in range(8):
		var card := PanelContainer.new()
		card.position = Vector2(46 + (index % 4) * 190, 156 + (index / 4) * 190)
		card.size = Vector2(176, 174)
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		team_layer.add_child(card)
		var stack := VBoxContainer.new()
		stack.alignment = BoxContainer.ALIGNMENT_CENTER
		card.add_child(stack)
		var monogram := _label("PXL", 28, PAPER)
		monogram.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(monogram)
		var label := _label("HARBOR\nCLUB", 15, PAPER)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(label)
		var chip := _label("", 12, GOLD)
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(chip)
		team_cards.append(card)
		team_card_labels.append(label)
		team_card_chips.append(chip)

	difficulty_panel = _option_panel(team_layer, Vector2(46, 559), "DIFFICULTY")
	difficulty_label = difficulty_panel.get_node("Stack/Value") as Label
	innings_panel = _option_panel(team_layer, Vector2(294, 559), "INNINGS")
	innings_label = innings_panel.get_node("Stack/Value") as Label
	play_ball_panel = PanelContainer.new()
	play_ball_panel.position = Vector2(542, 559)
	play_ball_panel.size = Vector2(264, 82)
	play_ball_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	team_layer.add_child(play_ball_panel)
	play_ball_label = _label("PLAY BALL", 25, INK)
	play_ball_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_ball_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	play_ball_panel.add_child(play_ball_label)

	var right := PanelContainer.new()
	right.position = Vector2(850, 97)
	right.size = Vector2(382, 544)
	right.add_theme_stylebox_override("panel", _style(Color(0.025, 0.05, 0.1, 0.96), Color(BLUE, 0.6), 2, 10))
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	team_layer.add_child(right)
	var guide := VBoxContainer.new()
	guide.add_theme_constant_override("separation", 16)
	right.add_child(guide)
	guide.add_child(_label("MATCH COMMISSIONER", 14, GOLD))
	guide.add_child(_label("1. PICK YOUR CLUB", 21, PAPER))
	guide.add_child(_label("The first confirmed card becomes P1.\nIts colors, badge and lineup drive the home HUD.", 15, CHALK))
	guide.add_child(_label("2. PICK THE CPU", 21, PAPER))
	guide.add_child(_label("Choose a different rival. Team batting and\npitching ratings feed the versus simulation.", 15, CHALK))
	guide.add_child(_label("3. SET THE STAKES", 21, PAPER))
	guide.add_child(_label("Focus Difficulty or Innings, then use left / right.\nPLAY BALL unlocks only for a valid matchup.", 15, CHALK))
	guide.add_child(_label("NO MOUSE REQUIRED", 14, TEAL))
	_placed_label(team_layer, "D-PAD / WASD  NAVIGATE     •     A / ENTER  PICK     •     B / ESC  BACK", 14, Color(CHALK, 0.84), Vector2(47, 667), Vector2(840, 28))


func _option_panel(parent: Control, at: Vector2, heading: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = heading.capitalize()
	panel.position = at
	panel.size = Vector2(224, 82)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(panel)
	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(stack)
	var title := _label(heading, 12, CHALK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(title)
	var value := _label("◀  --  ▶", 18, PAPER)
	value.name = "Value"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(value)
	return panel


func _build_final() -> void:
	final_layer = Control.new()
	final_layer.name = "Final"
	final_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_layer.add_child(final_layer)
	_build_shell_backdrop(final_layer, 0.78)
	var panel := PanelContainer.new()
	panel.position = Vector2(230, 75)
	panel.size = Vector2(820, 555)
	panel.add_theme_stylebox_override("panel", _style(Color(0.025, 0.05, 0.1, 0.98), GOLD, 3, 12))
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	final_layer.add_child(panel)
	var stack := VBoxContainer.new()
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 14)
	panel.add_child(stack)
	var kicker := _label("HARBOR LEAGUE  /  FINAL", 15, TEAL)
	kicker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(kicker)
	final_title = _label("FINAL", 46, PAPER)
	final_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(final_title)
	final_score = _score_label("0 – 0", 62, GOLD)
	final_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(final_score)
	final_stats = _label("", 18, CHALK)
	final_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(final_stats)
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 18)
	stack.add_child(actions)
	for text in ["REMATCH", "EXIT TO MENU"]:
		var action := PanelContainer.new()
		action.custom_minimum_size = Vector2(240, 64)
		action.mouse_filter = Control.MOUSE_FILTER_IGNORE
		actions.add_child(action)
		var label := _label(text, 18, PAPER)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		action.add_child(label)
		final_actions.append(action)
		final_action_labels.append(label)
	var hint := _label("← / →  SELECT     •     A / ENTER  CONFIRM     •     ESC  MENU", 14, Color(CHALK, 0.82))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	stack.add_child(hint)


func _build_game_hud() -> void:
	game_layer = Control.new()
	game_layer.name = "GameHUD"
	game_layer.theme = S.ui_theme()
	game_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_layer.visible = false
	game_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(game_layer)

	var top_bar := PanelContainer.new()
	top_bar.position = Vector2(24, 20)
	top_bar.size = Vector2(700, 92)
	top_bar.add_theme_stylebox_override("panel", _style(Color(0.03, 0.055, 0.105, 0.94), TEAL, 2, 9))
	game_layer.add_child(top_bar)
	var score_row := HBoxContainer.new()
	score_row.add_theme_constant_override("separation", 20)
	top_bar.add_child(score_row)
	var brand := _label("PXL", 25, TEAL)
	brand.custom_minimum_size.x = 58
	brand.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_row.add_child(brand)
	score_label = _score_label("FOX  0     PUL  0", 26, PAPER)
	score_label.custom_minimum_size.x = 245
	score_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_row.add_child(score_label)
	inning_label = _label("▲ 1ST", 19, GOLD)
	inning_label.custom_minimum_size.x = 85
	inning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_row.add_child(inning_label)
	count_label = _score_label("0–0", 56, PAPER)
	count_label.custom_minimum_size.x = 96
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	score_row.add_child(count_label)
	var outs_group := HBoxContainer.new()
	outs_group.add_theme_constant_override("separation", 6)
	outs_group.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_child(outs_group)
	outs_label = _label("OUTS", 14, CHALK)
	outs_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	outs_group.add_child(outs_label)
	for _i in range(2):
		var lamp := Panel.new()
		lamp.custom_minimum_size = Vector2(16, 16)
		lamp.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		lamp.add_theme_stylebox_override("panel", _style(SHADOW_BLUE, INK, 2, 0))
		outs_group.add_child(lamp)
		out_lamps.append(lamp)

	var diamond := Control.new()
	diamond.custom_minimum_size = Vector2(82, 70)
	score_row.add_child(diamond)
	for pos in [Vector2(42, 6), Vector2(64, 29), Vector2(42, 52)]:
		var base := Panel.new()
		base.position = pos
		base.size = Vector2(17, 17)
		base.rotation = PI / 4.0
		base.pivot_offset = Vector2(8.5, 8.5)
		base.add_theme_stylebox_override("panel", _style(SHADOW_BLUE, SLATE, 1, 2))
		diamond.add_child(base)
		bases.append(base)

	var phase_panel := PanelContainer.new()
	phase_panel.position = Vector2(24, 124)
	phase_panel.size = Vector2(375, 48)
	phase_panel.add_theme_stylebox_override("panel", _style(Color(0.03, 0.055, 0.105, 0.9), Color(0.3, 0.5, 0.7, 0.45), 1, 7))
	game_layer.add_child(phase_panel)
	phase_label = _label("AT BAT", 17, CHALK)
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	phase_panel.add_child(phase_label)

	stamina_panel = PanelContainer.new()
	stamina_panel.position = Vector2(411, 124)
	stamina_panel.size = Vector2(313, 48)
	stamina_panel.add_theme_stylebox_override("panel", _style(Color(0.03, 0.055, 0.105, 0.9), Color(TEAL, 0.5), 1, 7))
	game_layer.add_child(stamina_panel)
	var stamina_stack := HBoxContainer.new()
	stamina_stack.add_theme_constant_override("separation", 10)
	stamina_panel.add_child(stamina_stack)
	stamina_label = _label("ARM 100%", 13, TEAL)
	stamina_label.custom_minimum_size.x = 86
	stamina_stack.add_child(stamina_label)
	stamina_bar = ProgressBar.new()
	stamina_bar.custom_minimum_size = Vector2(185, 20)
	stamina_bar.min_value = 0
	stamina_bar.max_value = 1
	stamina_bar.value = 1
	stamina_bar.show_percentage = false
	stamina_stack.add_child(stamina_bar)
	set_stamina(1.0)

	identity_label = _placed_label(game_layer, "", 16, PAPER, Vector2(25, 184), Vector2(500, 35))
	identity_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.75))
	identity_label.add_theme_constant_override("shadow_offset_x", 2)
	identity_label.add_theme_constant_override("shadow_offset_y", 2)

	strike_zone = StrikeZone.new()
	strike_zone.position = Vector2(1030, 165)
	strike_zone.size = Vector2(220, 220)
	game_layer.add_child(strike_zone)

	result_panel = PanelContainer.new()
	result_panel.position = Vector2(430, 170)
	result_panel.size = Vector2(420, 118)
	result_panel.modulate.a = 0.0
	result_panel.add_theme_stylebox_override("panel", _style(Color(0.025, 0.05, 0.1, 0.96), GOLD, 3, 10))
	game_layer.add_child(result_panel)
	var result_stack := VBoxContainer.new()
	result_stack.alignment = BoxContainer.ALIGNMENT_CENTER
	result_panel.add_child(result_stack)
	result_label = _label("PLAY BALL", 34, GOLD)
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_stack.add_child(result_label)
	detail_label = _label("", 16, CHALK)
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_stack.add_child(detail_label)

	pitch_row = HBoxContainer.new()
	pitch_row.position = Vector2(24, 620)
	pitch_row.size = Vector2(795, 76)
	pitch_row.add_theme_constant_override("separation", 8)
	game_layer.add_child(pitch_row)
	for i in range(C.PITCHES.size()):
		var card := PanelContainer.new()
		card.custom_minimum_size = Vector2(151, 62)
		card.add_theme_stylebox_override("panel", _style(Color(0.03, 0.055, 0.105, 0.92), C.PITCHES[i]["color"], 2, 7))
		var card_label := _label("%d  %s" % [i + 1, C.PITCHES[i]["name"]], 12, PAPER)
		card_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		card_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.add_child(card_label)
		pitch_row.add_child(card)
		pitch_cards.append(card)
		pitch_labels.append(card_label)

	help_label = _placed_label(game_layer, "", 16, PAPER, Vector2(815, 635), Vector2(435, 55))
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	help_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	help_label.add_theme_constant_override("shadow_offset_x", 2)
	help_label.add_theme_constant_override("shadow_offset_y", 2)

	field_meter = ProgressBar.new()
	field_meter.position = Vector2(465, 580)
	field_meter.size = Vector2(350, 24)
	field_meter.min_value = 0
	field_meter.max_value = 1
	field_meter.show_percentage = false
	field_meter.visible = false
	field_meter.add_theme_stylebox_override("background", _style(INK, PAPER, 2, 4))
	field_meter.add_theme_stylebox_override("fill", _style(TEAL, Color("a7ffe9"), 1, 4))
	game_layer.add_child(field_meter)

	event_feed_back = PanelContainer.new()
	event_feed_back.position = Vector2(995, 398)
	event_feed_back.size = Vector2(265, 180)
	event_feed_back.visible = false
	event_feed_back.add_theme_stylebox_override("panel", _style(Color(0.03, 0.055, 0.105, 0.76), Color(0.3, 0.5, 0.7, 0.4), 1, 7))
	game_layer.add_child(event_feed_back)
	event_feed = VBoxContainer.new()
	event_feed.position = Vector2(1010, 420)
	event_feed.size = Vector2(240, 150)
	event_feed.alignment = BoxContainer.ALIGNMENT_END
	game_layer.add_child(event_feed)


func show_landing(stats: Dictionary, focus: int) -> void:
	_show_shell_layer(landing_layer)
	landing_prompt.text = "INSERT COIN  —  %s" % ("ENDLESS" if focus == 0 else "VERSUS")
	landing_stats.text = "BEST ENDLESS  %d K     •     VERSUS  %d–%d" % [
		int(stats.get("best_endless_strikeouts", 0)),
		int(stats.get("versus_wins", 0)),
		int(stats.get("versus_losses", 0)),
	]
	for index in range(landing_cards.size()):
		var active := index == focus
		landing_cards[index].add_theme_stylebox_override("panel", _style(Color(0.03, 0.055, 0.105, 0.96), GOLD if active else SHADOW_BLUE, 4 if active else 2, 11))
		landing_card_titles[index].add_theme_color_override("font_color", GOLD if active else PAPER)


func show_pitcher_select(pitchers: Array[Dictionary], index: int) -> void:
	_show_shell_layer(pitcher_layer)
	if pitchers.is_empty():
		return
	var selected := clampi(index, 0, pitchers.size() - 1)
	for card_index in range(pitcher_cards.size()):
		if card_index >= pitchers.size():
			pitcher_cards[card_index].visible = false
			continue
		pitcher_cards[card_index].visible = true
		var pitcher: Dictionary = pitchers[card_index]
		var active := card_index == selected
		var metrics := derive_pitcher_metrics(pitcher, pitchers)
		pitcher_card_labels[card_index].text = "%s\n#%02d  %s\nOVR %d" % [String(pitcher.get("name", "UNKNOWN")).to_upper(), int(pitcher.get("number", 0)), String(pitcher.get("throws", "R")), int(metrics.ovr)]
		pitcher_card_labels[card_index].add_theme_color_override("font_color", GOLD if active else PAPER)
		pitcher_cards[card_index].add_theme_stylebox_override("panel", _style(NIGHT if active else Color(0.03, 0.055, 0.105, 0.96), GOLD if active else SHADOW_BLUE, 4 if active else 1, 8))
	var pitcher: Dictionary = pitchers[selected]
	var metrics := derive_pitcher_metrics(pitcher, pitchers)
	pitcher_detail_name.text = "%s  #%02d" % [String(pitcher.get("name", "UNKNOWN")).to_upper(), int(pitcher.get("number", 0))]
	pitcher_detail_metrics.text = "OVR %d   •   ERA %.2f   •   K/9 %.1f\n%s   •   %s   •   %.1f MPH" % [int(metrics.ovr), float(metrics.era), float(metrics.k9), String(metrics.archetype), String(pitcher.get("throws", "R")) + "HP", float(metrics.velocity)]
	var arsenal_lines: Array[String] = []
	for pitch_value in pitcher.get("pitches", []):
		var pitch: Dictionary = pitch_value
		var usage := clampf(float(pitch.get("usage", 0.0)), 0.0, 1.0)
		var blocks := maxi(1, roundi(usage * 18.0))
		arsenal_lines.append("%-3s %5.1f  %s %2d%%" % [String(pitch.get("code", "--")), float(pitch.get("velocity", 0.0)), "▰".repeat(blocks), roundi(usage * 100.0)])
	pitcher_detail_arsenal.text = "\n".join(arsenal_lines)
	var stamina := float(metrics.stamina)
	pitcher_stamina.value = stamina
	var stamina_color := S.meter_color(stamina)
	pitcher_stamina.add_theme_stylebox_override("background", _style(INK, SHADOW_BLUE, 1, 4))
	pitcher_stamina.add_theme_stylebox_override("fill", _style(stamina_color, stamina_color.lightened(0.18), 1, 4))


func show_team_select(teams: Array[Dictionary], state: Dictionary) -> void:
	_show_shell_layer(team_layer)
	var focus := int(state.get("team_focus", 0))
	var player_index := int(state.get("player_team_index", -1))
	var cpu_index := int(state.get("cpu_team_index", -1))
	for index in range(team_cards.size()):
		if index >= teams.size():
			team_cards[index].visible = false
			continue
		team_cards[index].visible = true
		var team: Dictionary = teams[index]
		var team_color := _team_color(team)
		var active := focus == index
		var selected := index == player_index or index == cpu_index
		team_card_labels[index].text = "%s\n%s  •  BAT %d\nPIT %d" % [String(team.get("city", "HARBOR")).to_upper(), String(team.get("name", "CLUB")).to_upper(), int(team.get("bat", 0)), int(team.get("pit", 0))]
		team_card_chips[index].text = "P1" if index == player_index else ("CPU" if index == cpu_index else "")
		team_card_chips[index].add_theme_color_override("font_color", GOLD if index == player_index else TEAL)
		var border := TEAL if active else (GOLD if selected else SHADOW_BLUE)
		team_cards[index].add_theme_stylebox_override("panel", _style(Color(team_color, 0.24 if active else 0.14), border, 4 if active else (3 if selected else 1), 8))
	difficulty_label.text = "◀  %s  ▶" % String(state.get("difficulty_name", "PRO"))
	innings_label.text = "◀  %d  ▶" % int(state.get("innings", 3))
	_set_option_focus(difficulty_panel, focus == 8)
	_set_option_focus(innings_panel, focus == 9)
	var can_play := bool(state.get("can_play", false))
	play_ball_panel.modulate.a = 1.0 if can_play else 0.5
	play_ball_panel.add_theme_stylebox_override("panel", _style(GOLD if can_play else SLATE, TEAL if focus == 10 else GOLD, 4 if focus == 10 else 2, 8))
	if player_index < 0:
		matchup_label.text = "P1: PICK A CLUB"
	elif cpu_index < 0:
		matchup_label.text = "P1  %s     •     CPU: PICK A DIFFERENT CLUB" % String(teams[player_index].get("abbr", "P1"))
	else:
		matchup_label.text = "P1  %s     VS     %s  CPU" % [String(teams[player_index].get("abbr", "P1")), String(teams[cpu_index].get("abbr", "CPU"))]


func show_final(mode: String, state: Dictionary, stats: Dictionary, new_best: bool, focus: int) -> void:
	_show_shell_layer(final_layer)
	_final_focus = clampi(focus, 0, 1)
	if mode == "endless":
		var endless: Dictionary = state.get("endless", {})
		var strikeouts := int(endless.get("strikeouts", state.get("strikeouts", 0)))
		final_title.text = "NEW BEST!" if new_best else "ARM RETIRED"
		final_score.text = "%d K" % strikeouts
		final_stats.text = "BATTERS FACED  %d     •     PITCHES  %d     •     RUNS ALLOWED  %d\nCAREER BEST  %d K" % [int(endless.get("batters_faced", 0)), int(endless.get("pitch_count", state.get("pitch_serial", 0))), int(endless.get("runs_allowed", state.get("score", {}).get("away", 0))), int(stats.get("best_endless_strikeouts", strikeouts))]
	else:
		var score: Dictionary = state.get("score", {})
		var winner := String(state.get("winner", ""))
		var p1_won := winner == "home"
		final_title.text = "HARBOR CHAMPIONS" if p1_won else "FINAL OUT"
		final_score.text = "%s %d  —  %d %s" % [String(_home_team.get("abbr", "P1")), int(score.get("home", 0)), int(score.get("away", 0)), String(_away_team.get("abbr", "CPU"))]
		var line_score: Dictionary = state.get("line_score", {})
		var innings := int(state.get("innings", 3))
		final_stats.text = "%d INNINGS     •     HITS %d–%d\nVERSUS RECORD  %d–%d     •     LINE  %s / %s" % [innings, int(state.get("hits", {}).get("home", 0)), int(state.get("hits", {}).get("away", 0)), int(stats.get("versus_wins", 0)), int(stats.get("versus_losses", 0)), _line_score_text(line_score.get("home", []), innings), _line_score_text(line_score.get("away", []), innings)]
	for index in range(final_actions.size()):
		var active := index == focus
		final_actions[index].add_theme_stylebox_override("panel", _style(GOLD if active else NIGHT, TEAL if active else SHADOW_BLUE, 3 if active else 1, 8))
		final_action_labels[index].add_theme_color_override("font_color", INK if active else PAPER)


func show_game() -> void:
	title_layer.visible = false
	game_layer.visible = true


func show_title() -> void:
	show_landing({}, 0)


func _show_shell_layer(target: Control) -> void:
	title_layer.visible = true
	game_layer.visible = false
	for child in [landing_layer, pitcher_layer, team_layer, final_layer]:
		child.visible = child == target


func set_match_teams(home_team: Dictionary, away_team: Dictionary) -> void:
	_home_team = home_team.duplicate(true)
	_away_team = away_team.duplicate(true)


func set_title_matchup(pitcher: Dictionary, index: int, total: int) -> void:
	if title_matchup_label == null:
		return
	var metrics := derive_pitcher_metrics(pitcher)
	title_matchup_label.text = "STARTER %d/%d  •  OVR %d  •  %s" % [index + 1, total, int(metrics.ovr), String(metrics.archetype)]


func set_arsenal(pitches: Array) -> void:
	for index in range(pitch_labels.size()):
		if index >= pitches.size():
			pitch_cards[index].visible = false
			continue
		pitch_cards[index].visible = true
		var pitch: Dictionary = pitches[index]
		pitch_labels[index].text = "%d  %s" % [index + 1, String(pitch.get("name", pitch.get("code", "PITCH"))).to_upper()]


func update_state(state: Dictionary) -> void:
	var away_score := int(state.get("away_score", 0))
	var home_score := int(state.get("home_score", 0))
	score_label.text = "%s  %d     %s  %d" % [String(_away_team.get("abbr", "AWY")), away_score, String(_home_team.get("abbr", "HME")), home_score]
	var half_mark := "▲" if bool(state.get("top", true)) else "▼"
	inning_label.text = "%s %s" % [half_mark, _ordinal(int(state.get("inning", 1)))]
	count_label.text = "%d–%d" % [int(state.get("balls", 0)), int(state.get("strikes", 0))]
	var outs := int(state.get("outs", 0))
	for i in range(out_lamps.size()):
		var lit := outs > i
		out_lamps[i].add_theme_stylebox_override("panel", _style(STITCH if lit else SHADOW_BLUE, INK, 2, 0))
	var occupied: Array = state.get("bases", [false, false, false])
	for i in range(mini(3, occupied.size())):
		bases[i].add_theme_stylebox_override("panel", _style(GOLD if occupied[i] else SHADOW_BLUE, GOLD if occupied[i] else SLATE, 1, 2))
	phase_label.text = str(state.get("phase_label", state.get("phase", "PLAY BALL"))).to_upper()


func set_stamina(value: float, status: String = "") -> void:
	if stamina_bar == null:
		return
	var stamina := clampf(value, 0.0, 1.0)
	# UE stamina tiers (spec 3f): FRESH Grass / TIRING Gold / TIRED ClayLight /
	# GASSED Stitch (+blink handled in _process).
	var tier := S.stamina_tier(stamina)
	var color: Color = tier.color
	var suffix := "  " + String(tier.label)
	if not status.is_empty():
		suffix = "  " + status.to_upper()
	_stamina_gassed = bool(tier.gassed) or status.to_lower() == "gassed"
	stamina_label.text = "ARM %d%%%s" % [roundi(stamina * 100.0), suffix]
	stamina_label.add_theme_color_override("font_color", color)
	stamina_bar.value = stamina
	stamina_bar.add_theme_stylebox_override("background", _style(INK, SHADOW_BLUE, 1, 3))
	stamina_bar.add_theme_stylebox_override("fill", _style(color, color.lightened(0.15), 1, 3))


func set_identity(text: String) -> void:
	identity_label.text = text


func set_help(text: String) -> void:
	help_label.text = text


func set_aim(value: Vector2, accent := TEAL) -> void:
	strike_zone.accent = accent
	strike_zone.set_aim(value)


func set_pitch_marker(value: Vector2, visible: bool) -> void:
	strike_zone.set_pitch(value, visible)


func set_strike_zone_visible(visible: bool) -> void:
	strike_zone.visible = visible


func set_pitch_selector(visible: bool, selected := -1) -> void:
	pitch_row.visible = visible
	for i in range(pitch_cards.size()):
		var color: Color = C.PITCHES[i]["color"]
		pitch_cards[i].modulate = Color.WHITE if i == selected else Color(0.72, 0.76, 0.82, 0.82)
		# Active tile frame is Grass per spec 3m; idle tiles keep their slot color.
		var frame := GRASS if i == selected else color
		pitch_cards[i].add_theme_stylebox_override("panel", _style(NIGHT if i == selected else Color(0.03, 0.055, 0.105, 0.92), frame, 4 if i == selected else 2, 7))


func set_field_meter(visible: bool, value := 0.0) -> void:
	field_meter.visible = visible
	field_meter.value = value


func banner(title: String, detail := "", accent := GOLD, hold := 1.25) -> void:
	result_label.text = title.to_upper()
	result_label.add_theme_color_override("font_color", accent)
	detail_label.text = detail
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	result_panel.modulate.a = 0.0
	result_panel.scale = Vector2(0.92, 0.92)
	result_panel.pivot_offset = result_panel.size * 0.5
	_banner_tween = create_tween().set_parallel(true)
	_banner_tween.tween_property(result_panel, "modulate:a", 1.0, 0.14)
	_banner_tween.tween_property(result_panel, "scale", Vector2.ONE, 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_banner_tween.chain().tween_interval(hold)
	_banner_tween.chain().tween_property(result_panel, "modulate:a", 0.0, 0.25)


func push_event(text: String, color := CHALK) -> void:
	event_feed_back.visible = true
	var line := _label(text.to_upper(), 13, color)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	event_feed.add_child(line)
	while event_feed.get_child_count() > 5:
		var oldest := event_feed.get_child(0)
		event_feed.remove_child(oldest)
		oldest.free()
	_layout_event_feed()
	var tween := create_tween()
	line.modulate.a = 0.0
	tween.tween_property(line, "modulate:a", 1.0, 0.12)


func remove_event(text: String) -> void:
	var normalized := text.to_upper()
	for child in event_feed.get_children():
		if child is Label and String((child as Label).text).to_upper() == normalized:
			event_feed.remove_child(child)
			child.free()
	if event_feed.get_child_count() == 0:
		event_feed_back.visible = false
	else:
		_layout_event_feed()


func clear_events() -> void:
	for child in event_feed.get_children():
		event_feed.remove_child(child)
		child.free()
	event_feed_back.visible = false


func _layout_event_feed() -> void:
	var rows := event_feed.get_child_count()
	var height := 24.0 + float(rows) * 24.0
	event_feed_back.position.y = 590.0 - height
	event_feed_back.size.y = height
	event_feed.position.y = event_feed_back.position.y + 10.0
	event_feed.size.y = maxf(24.0, height - 20.0)


static func derive_pitcher_metrics(pitcher: Dictionary, pool: Array = []) -> Dictionary:
	if (pitcher.get("pitches", []) as Array).is_empty():
		return {"ovr": 50, "era": 5.50, "k9": 5.0, "velocity": 80.0, "stamina": 0.5, "archetype": "UNKNOWN"}
	var source_pool: Array = pool if not pool.is_empty() else [pitcher]
	var cache: Dictionary = PitcherDisplay.build_cache(source_pool)
	var card: Dictionary = PitcherDisplay.card_for(cache, int(pitcher.get("id", -1)))
	return {
		"ovr": int(card.get("ovr", 50)),
		"era": float(card.get("era", "5.50")),
		"k9": float(card.get("k9", "5.0")),
		"velocity": float(card.get("velo", 80)),
		"stamina": float(card.get("stamina", 0.5)),
		"archetype": String(card.get("archetype", "UNKNOWN")),
	}


func _set_option_focus(panel: PanelContainer, active: bool) -> void:
	panel.add_theme_stylebox_override("panel", _style(NIGHT if active else Color(0.03, 0.055, 0.105, 0.96), TEAL if active else SHADOW_BLUE, 4 if active else 1, 8))


func _team_color(team: Dictionary) -> Color:
	var value: Variant = team.get("color", team.get("primary", TEAL))
	if value is Color:
		return value
	return Color.from_string(String(value), TEAL)


func _line_score_text(value: Variant, innings := 0) -> String:
	if not value is Array:
		return "—"
	var parts: Array[String] = []
	for run_value in value:
		parts.append(str(int(run_value)))
	while parts.size() < innings:
		parts.append("—")
	return " ".join(parts) if not parts.is_empty() else "—"


func _ordinal(value: int) -> String:
	match value:
		1: return "1ST"
		2: return "2ND"
		3: return "3RD"
		_: return "%dTH" % value


func _placed_label(parent: Control, text: String, size: int, color: Color, position: Vector2, dimensions: Vector2) -> Label:
	var label := _label(text, size, color)
	label.position = position
	label.size = dimensions
	parent.add_child(label)
	return label


func _label(text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label


## Numeric readouts (count, scores, velo, K totals) use the Score face (Grid),
## which reads best as monospaced pixel digits.
func _score_label(text: String, size: int, color: Color) -> Label:
	var label := _label(text, size, color)
	label.add_theme_font_override("font", S.FONT_SCORE)
	return label


func _style(fill: Color, border: Color, border_width: int, _radius: int) -> StyleBoxFlat:
	# UE chrome: flat rect, ink border, square corners, hard pixel drop-shadow.
	# The legacy `radius` argument is ignored (no rounded corners in the UE look).
	# Panels/cards (border >= 3) cast the 4px shadow; bars/lamps/badges do not.
	var shadow := S.SHADOW_PANEL if border_width >= 3 else 0
	return S.panel(fill, border, border_width, shadow)
