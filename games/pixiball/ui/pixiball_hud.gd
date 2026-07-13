class_name PixiballHUD
extends CanvasLayer

## Native 1280x720 shell and gameplay HUD.
##
## Every Control owns direct 720p coordinates and every font is rasterized at
## its native output size. The small design-grid values in the construction
## helpers are converted into 4px layout units; no parent Control, texture, or
## intermediate viewport is enlarged.
##
## The game layer follows the Painted Signage system (art bible §10): an
## enamel-lightboard scoreline strip up top, a chalk rail along the bottom,
## and pennant-tab pitch cards hung from the rail.

const C = preload("res://gameplay/game_constants.gd")
const StrikeZone = preload("res://ui/strike_zone.gd")
const PitcherDisplay = preload("res://gameplay/pitcher_display.gd")
const S = preload("res://ui/pixiball_style.gd")
const PixelOverlay = preload("res://ui/pixiball_pixel_overlay.gd")

const UI_SIZE := S.NATIVE_SIZE

const INK := S.INK
const DEEP_INK := S.SCOREBOARD
const PAPER := S.CHALK
const CHALK := S.STEEL
const STEEL := S.STEEL
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
# Enamel-lightboard bezel (bible §10.1). The hex is bible-specified; fold it
# into a PixiballStyle role when the palette-foundation pass reworks S.
const BEZEL := Color("1b2138")
# Night-only value steps (bible §11.1/§11.6): the night world compresses into
# the same V0-V2 rungs as the enamel furniture, so the bezel rim and the
# hollow/unlit glyph rings each step one authored rung lighter at night to
# keep figure-ground separation. Day/golden keep the base values exactly.
const BEZEL_NIGHT := S.PANEL_RAISED

var title_layer: Control
var landing_layer: Control
var pitcher_layer: Control
var team_layer: Control
var final_layer: Control
var game_layer: Control

var landing_cards: Array[PanelContainer] = []
var landing_card_titles: Array[Label] = []
var landing_card_ctas: Array[PanelContainer] = []
var landing_stat_lines: Array[Label] = []
var landing_prompt: Label
var pitcher_cards: Array[PanelContainer] = []
var pitcher_card_labels: Array[Label] = []
var pitcher_detail_name: Label
var pitcher_detail_metrics: Label
var pitcher_detail_arsenal: Label
var pitcher_stamina: ProgressBar
var _pitcher_stamina_track: ColorRect
var _pitcher_stamina_fill: ColorRect
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
var pitcher_label: Label
var count_label: Label
var outs_label: Label
var out_lamps: Array[Panel] = []
var bases: Array[Panel] = []
var _base_cells: Array[DiamondCell] = []
var _inning_chevron: ChevronCell
var _count_pips: CountPips
var _pitch_flags: Array[PennantTab] = []
var phase_label: Label
var result_panel: PanelContainer
var result_label: Label
var detail_label: Label
var help_label: Label
var help_panel: PanelContainer
var pitch_row: Control
var pitch_cards: Array[Panel] = []
var pitch_labels: Array[Label] = []
var title_matchup_label: Label
var strike_zone: PixiballStrikeZone
var identity_label: Label
var identity_detail_label: Label
var field_meter: ProgressBar
var event_feed: VBoxContainer
var event_feed_back: PanelContainer
var stamina_label: Label
var stamina_bar: ProgressBar
var _stamina_track: ColorRect
var _stamina_fill: ColorRect

var _pitch_selector_active := false
var _hud_mood := "day"
var _outs_shown := 0
var _top_board: PanelContainer
var _identity_board: PanelContainer
var _arm_board: PanelContainer
var _home_team: Dictionary = C.HOME_TEAM.duplicate(true)
var _away_team: Dictionary = C.AWAY_TEAM.duplicate(true)
var _banner_tween: Tween
var _blink_time := 0.0
var _final_focus := 0
var _stamina_gassed := false
var _batting_layout := false


func _ready() -> void:
	layer = 20
	_build_shell()
	_build_game_hud()
	show_landing({}, 0)


func _process(delta: float) -> void:
	_blink_time = fmod(_blink_time + delta, 1.2)
	var mood := _world_mood()
	if mood != _hud_mood:
		_hud_mood = mood
		_apply_hud_mood()
	if landing_prompt != null:
		landing_prompt.modulate.a = 1.0 if _blink_time < 0.6 else 0.35
	if final_layer != null and final_layer.visible:
		for index in range(final_actions.size()):
			final_actions[index].modulate.a = (1.0 if _blink_time < 0.6 else 0.62) if index == _final_focus else 1.0
	if stamina_label != null and stamina_bar != null:
		var alpha := (1.0 if _blink_time < 0.6 else 0.24) if _stamina_gassed else 1.0
		stamina_label.modulate.a = alpha
		stamina_bar.modulate.a = alpha


func _build_shell() -> void:
	title_layer = _root_control("AppShell")
	title_layer.theme = S.ui_theme()
	add_child(title_layer)
	landing_layer = _screen("Landing")
	pitcher_layer = _screen("PitcherSelect")
	team_layer = _screen("TeamSelect")
	final_layer = _screen("Final")
	_build_landing()
	_build_pitcher_select()
	_build_team_select()
	_build_final()


func _screen(node_name: String) -> Control:
	var screen := _root_control(node_name)
	title_layer.add_child(screen)
	var backdrop := TextureRect.new()
	backdrop.name = "HarborBackdrop"
	backdrop.position = Vector2.ZERO
	backdrop.size = UI_SIZE
	var solid := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	solid.fill(DEEP_INK)
	backdrop.texture = ImageTexture.create_from_image(solid)
	backdrop.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	backdrop.stretch_mode = TextureRect.STRETCH_SCALE
	backdrop.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.add_child(backdrop)
	# Graphic harbor blocks, not an illustration: three hard value bands and a
	# few one-pixel lights establish place without competing with menu text.
	_add_rect(screen, Vector2(0, 0), Vector2(320, 3), TEAL)
	_add_rect(screen, Vector2(0, 3), Vector2(320, 1), GOLD)
	_add_rect(screen, Vector2(0, 112), Vector2(320, 68), Color("131a2d"))
	_add_rect(screen, Vector2(0, 112), Vector2(320, 1), SHADOW_BLUE)
	var atmosphere := PixelOverlay.new().configure(0.8, true)
	atmosphere.name = "PixelAtmosphere"
	screen.add_child(atmosphere)
	return screen


func _build_landing() -> void:
	# Landing per bible 6.1/10.6: the production intro postcard is the
	# backdrop, so the shell fill and banner bands are retired on this screen
	# only. The HarborBackdrop and PixelAtmosphere contract nodes stay in the
	# tree; all shell furniture holds the left 45% and the harbor reads right.
	for child in landing_layer.get_children():
		if child is ColorRect or child.name == "HarborBackdrop":
			(child as CanvasItem).visible = false

	# Rope-hung enamel title sign (bible 10.6): GeistPixel-Square at the native
	# 48px Display tier with +8 tracking, over the ink board face.
	var sign := EnamelSign.new()
	sign.position = _native(Vector2(16, 0))
	sign.size = _native(Vector2(116, 46))
	sign.ink = INK
	sign.face = DEEP_INK
	sign.bezel = BEZEL
	sign.rivet = SLATE
	sign.rope = S.CLAY
	sign.rope_lit = CLAY_LIGHT
	sign.glow = S.WINDOW_GLOW
	sign.gold = GOLD
	landing_layer.add_child(sign)
	var display_font: Font = load("res://assets/fonts/geist_pixel/GeistPixel-Square.ttf")
	var title := _placed_label(sign, "PIXIBALL", 12, GOLD, Vector2(0, 14), Vector2(112, 14))
	title.add_theme_font_override("font", S.tracked(display_font, 8))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var subtitle := _placed_label(sign, "HARBOR LEAGUE", 6, TEAL, Vector2(0, 29), Vector2(112, 7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var card_specs := [
		{"y": 52, "title": "ENDLESS", "detail": "PROTECT THE HARBOR", "cta": "CHOOSE ARM", "trim": STITCH, "emblem": "ball"},
		{"y": 95, "title": "VERSUS", "detail": "THREE-INNING DUEL", "cta": "CHOOSE CLUBS", "trim": TEAL, "emblem": "duel"},
	]
	for spec in card_specs:
		var card := PlankCard.new()
		card.position = _native(Vector2(12, spec.y))
		card.size = _native(Vector2(120, 37))
		card.rest_top = card.position.y
		card.ink = INK
		card.tick = GOLD
		card.trim = spec.trim
		card.chalk = PAPER
		card.stitch = STITCH
		card.teal = TEAL
		card.emblem = spec.emblem
		landing_layer.add_child(card)
		landing_cards.append(card)
		var content := _panel_content(card)
		var card_title := _placed_label(content, spec.title, 8, PAPER, Vector2(26, 4), Vector2(88, 9))
		landing_card_titles.append(card_title)
		var detail := _body_label(spec.detail, 4, STEEL)
		detail.position = _native(Vector2(26, 13))
		detail.size = _native(Vector2(88, 5))
		content.add_child(detail)
		var stat := _score_label("--", 7, GOLD)
		stat.position = _native(Vector2(26, 18))
		stat.size = _native(Vector2(88, 7))
		content.add_child(stat)
		landing_stat_lines.append(stat)
		var cta := _panel(content, Vector2(26, 26), Vector2(88, 8), NIGHT2, INK, 1)
		landing_card_ctas.append(cta)
		var cta_label := _label(spec.cta, 6, PAPER)
		cta_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cta_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cta.add_child(cta_label)

	# Prompt rides an opaque chalk rail plate; the shell blink becomes a
	# chalk->steel value step inside LandingPrompt, never a translucent fade.
	_add_rect(landing_layer, Vector2(12, 162), Vector2(120, 10), INK)
	_add_rect(landing_layer, Vector2(16, 166), Vector2.ONE, PAPER)
	_add_rect(landing_layer, Vector2(127, 166), Vector2.ONE, PAPER)
	var prompt := LandingPrompt.new()
	prompt.lit_color = PAPER
	prompt.dim_color = STEEL
	prompt.text = "INSERT COIN - PRESS START"
	prompt.position = _native(Vector2(12, 162))
	prompt.size = _native(Vector2(120, 10))
	prompt.clip_text = true
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	prompt.add_theme_font_override("font", S.FONT_SCORE)
	prompt.add_theme_font_size_override("font_size", 7 * S.NATIVE_UNIT)
	prompt.add_theme_color_override("font_color", PAPER)
	landing_layer.add_child(prompt)
	landing_prompt = prompt


func _build_pitcher_select() -> void:
	# Pitcher select per bible 6.1/10.6: the production intro postcard is the
	# backdrop, so the generated shell fill and banner bands are retired on
	# this screen only. The HarborBackdrop and PixelAtmosphere contract nodes
	# stay in the tree; all signage holds the left 45% and the harbor reads on
	# the right.
	for child in pitcher_layer.get_children():
		if child is ColorRect or child.name == "HarborBackdrop":
			(child as CanvasItem).visible = false

	# Header plank (bible 10.1/10.2): one clear Header-32 title with the
	# roster position line beneath it.
	var header := ScoutPlank.new()
	header.position = _native(Vector2(8, 8))
	header.size = _native(Vector2(132, 24))
	header.ink = INK
	header.board = PlankCard.BOARD
	header.grain = PlankCard.GRAIN
	header.trim = STITCH
	header.shadow_drop = S.SHADOW_PANEL
	pitcher_layer.add_child(header)
	var heading := _placed_label(header, "SELECT STARTER", 8, PAPER, Vector2(6, 2), Vector2(120, 11))
	heading.add_theme_font_override("font", S.FONT_DISPLAY)
	title_matchup_label = _placed_label(header, "STARTER 1/10", 6, STEEL, Vector2(6, 14), Vector2(120, 8))

	# Roster rail: ten plank slats keep every arm physically on the board; the
	# focused slat carries the screen's only lantern-gold corner ticks plus
	# the 4px lift/value change (bible 10.4). Navigation and wrap semantics
	# stay in the shell model.
	var rail := RosterRail.new()
	rail.name = "RosterRail"
	rail.position = _native(Vector2(8, 36))
	rail.size = _native(Vector2(44, 128))
	rail.ink = INK
	rail.board = PlankCard.BOARD
	rail.raised = S.PANEL_RAISED
	rail.grain = PlankCard.GRAIN
	rail.trim = SLATE
	rail.tick = GOLD
	pitcher_layer.add_child(rail)
	for index in range(10):
		var slat_label := _body_label("", 5, STEEL)
		slat_label.position = Vector2(16, index * RosterRail.SLAT_STEP + 8)
		slat_label.size = Vector2(152, 28)
		slat_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		rail.add_child(slat_label)

	# Scouting board: one painted plank carries the focused identity card, the
	# Marquee portrait chip, and every derived metric readout.
	var scout_board := ScoutPlank.new()
	scout_board.position = _native(Vector2(60, 36))
	scout_board.size = _native(Vector2(80, 136))
	scout_board.ink = INK
	scout_board.board = PlankCard.BOARD
	scout_board.grain = PlankCard.GRAIN
	scout_board.trim = STITCH
	scout_board.shadow_drop = S.SHADOW_SMALL
	pitcher_layer.add_child(scout_board)

	# All ten physical cards share the identity-plate slot; the focus-centered
	# window shows exactly one while the rail keeps the full roster navigable.
	# The hard 8px slot shadow is a static opaque ink plate.
	_add_rect(pitcher_layer, Vector2(70, 44), Vector2(64, 39), INK)
	for index in range(10):
		var card := _panel(pitcher_layer, Vector2(68, 42), Vector2(64, 39), PlankCard.BOARD, INK, 1)
		card.visible = index == 0
		pitcher_cards.append(card)
		var face := ScoutPlank.new()
		face.ink = INK
		face.board = PlankCard.BOARD
		face.grain = PlankCard.GRAIN
		face.trim = STITCH
		face.shadow_drop = 0
		card.add_child(face)
		var content := _panel_content(card)
		var label := _label("PITCHER", 6, PAPER)
		label.position = _native(Vector2(2, 2))
		label.size = _native(Vector2(56, 35))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		content.add_child(label)
		pitcher_card_labels.append(label)

	# Marquee-cue portrait chip on a plank chip with a team-trim rim, plus an
	# enamel number tag so identity survives at chip size.
	var chip := PitcherPortraitChip.new()
	chip.name = "PortraitChip"
	chip.position = _native(Vector2(68, 85))
	chip.size = _native(Vector2(24, 28))
	chip.ink = INK
	chip.backdrop = PlankCard.GRAIN
	chip.trim = STITCH
	chip.skin = CLAY_LIGHT
	chip.skin_shade = S.CLAY
	chip.cloth = PAPER
	chip.glove = S.CLAY
	chip.glove_lit = CLAY_LIGHT
	chip.white = PAPER
	pitcher_layer.add_child(chip)
	_add_rect(pitcher_layer, Vector2(68, 115), Vector2(24, 8), INK)
	var chip_number := _score_label("#00", 7, PAPER)
	chip_number.name = "PortraitNumber"
	chip_number.position = _native(Vector2(68, 115))
	chip_number.size = _native(Vector2(24, 8))
	chip_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pitcher_layer.add_child(chip_number)

	pitcher_detail_name = _placed_label(pitcher_layer, "STARTER", 6, PAPER, Vector2(96, 85), Vector2(40, 26))
	pitcher_detail_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitcher_detail_metrics = _body_label("OVR --  ERA --  K/9 --", 5, PAPER)
	pitcher_detail_metrics.position = _native(Vector2(68, 127))
	pitcher_detail_metrics.size = _native(Vector2(64, 12))
	pitcher_detail_metrics.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitcher_layer.add_child(pitcher_detail_metrics)
	pitcher_detail_arsenal = _score_label("ARSENAL --", 7, PAPER)
	pitcher_detail_arsenal.position = _native(Vector2(68, 143))
	pitcher_detail_arsenal.size = _native(Vector2(64, 22))
	pitcher_detail_arsenal.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	pitcher_layer.add_child(pitcher_detail_arsenal)
	pitcher_stamina = ProgressBar.new()
	pitcher_stamina.position = Vector2.ZERO
	pitcher_stamina.size = _native(Vector2.ONE)
	pitcher_stamina.min_value = 0.0
	pitcher_stamina.max_value = 1.0
	pitcher_stamina.show_percentage = false
	pitcher_stamina.visible = false
	pitcher_layer.add_child(pitcher_stamina)
	_pitcher_stamina_track = _add_rect(pitcher_layer, Vector2(68, 166), Vector2(64, 3), INK)
	_pitcher_stamina_fill = _add_rect(pitcher_layer, Vector2(68, 166), Vector2(32, 3), GOLD)


func _build_team_select() -> void:
	# Team select per bible 6.1/10.6: the production intro postcard is the
	# backdrop, so the generated shell fill and banner bands are retired on
	# this screen only. The HarborBackdrop and PixelAtmosphere contract nodes
	# stay in the tree; all signage holds the left 45% and the harbor's
	# ferry/lightbank/lighthouse composition reads on the right.
	for child in team_layer.get_children():
		if child is ColorRect or child.name == "HarborBackdrop":
			(child as CanvasItem).visible = false

	# Header plank (bible 10.1/10.2): one Header-32 title on the club board.
	var header := ScoutPlank.new()
	header.position = _native(Vector2(8, 8))
	header.size = _native(Vector2(130, 16))
	header.ink = INK
	header.board = PlankCard.BOARD
	header.grain = PlankCard.GRAIN
	header.trim = TEAL
	header.shadow_drop = S.SHADOW_SMALL
	team_layer.add_child(header)
	var heading := _placed_label(header, "SELECT CLUBS", 8, PAPER, Vector2(6, 2), Vector2(118, 12))
	heading.add_theme_font_override("font", S.FONT_DISPLAY)

	# Eight pennant-on-plank club cards on the shell model's 4x2 grid. The
	# club color appears only as the bounded pennant flag and edge stripe over
	# the stable ink/plank material; focus and P1/CPU state live in the card.
	for index in range(8):
		var column := index % 4
		var row := index / 4
		var card := ClubPlankCard.new()
		card.position = _native(Vector2(8 + column * 33, 28 + row * 42))
		card.size = _native(Vector2(31, 38))
		card.rest_top = card.position.y
		card.ink = INK
		card.board = PlankCard.BOARD
		card.board_lit = S.PANEL_RAISED
		card.grain = PlankCard.GRAIN
		card.tick = GOLD
		card.trim = TEAL
		card.badge_fill = STITCH
		card.badge_line = TEAL
		card.grain_seed = index
		team_layer.add_child(card)
		team_cards.append(card)
		var content := _panel_content(card)
		var name_label := _label("CLUB", 6, PAPER)
		name_label.position = _native(Vector2(2, 9))
		name_label.size = _native(Vector2(28, 7))
		content.add_child(name_label)
		team_card_labels.append(name_label)
		card.city_label = _body_label("HARBOR", 4, STEEL)
		card.city_label.position = _native(Vector2(2, 17))
		card.city_label.size = _native(Vector2(28, 5))
		content.add_child(card.city_label)
		card.stats_label = _body_label("BAT -- PIT --", 4, PAPER)
		card.stats_label.position = _native(Vector2(2, 23))
		card.stats_label.size = _native(Vector2(28, 5))
		content.add_child(card.stats_label)
		var chip := _body_label("", 4, PAPER)
		chip.position = _native(Vector2(18, 2))
		chip.size = _native(Vector2(11, 6))
		chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		content.add_child(chip)
		team_card_chips.append(chip)

	# Matchup readout as an enamel fixture (bible 10.1): ink face, raised
	# bezel, rivets, VT323 Numerals-28 readout in signal teal.
	var matchup := MatchupBoard.new()
	matchup.position = _native(Vector2(8, 112))
	matchup.size = _native(Vector2(130, 14))
	matchup.ink = INK
	matchup.face = DEEP_INK
	matchup.bezel = BEZEL
	matchup.rivet = SLATE
	team_layer.add_child(matchup)
	matchup_label = _score_label("P1: PICK A CLUB", 7, TEAL)
	matchup_label.position = _native(Vector2(4, 3))
	matchup_label.size = _native(Vector2(122, 8))
	matchup_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	matchup_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	matchup.add_child(matchup_label)

	# Physical option planks: Body-16 caption over a Header-24 / Numerals-28
	# value. Focus treatment is owned by the fixture (bible 10.4).
	var difficulty_fixture := OptionFixture.new()
	difficulty_fixture.position = _native(Vector2(8, 130))
	difficulty_fixture.size = _native(Vector2(40, 38))
	difficulty_fixture.rest_top = difficulty_fixture.position.y
	difficulty_fixture.ink = INK
	difficulty_fixture.board = PlankCard.BOARD
	difficulty_fixture.board_lit = S.PANEL_RAISED
	difficulty_fixture.grain = PlankCard.GRAIN
	difficulty_fixture.trim = SLATE
	difficulty_fixture.tick = GOLD
	team_layer.add_child(difficulty_fixture)
	difficulty_panel = difficulty_fixture
	var difficulty_content := _panel_content(difficulty_panel)
	var difficulty_caption := _body_label("DIFFICULTY", 4, STEEL)
	difficulty_caption.position = _native(Vector2(2, 3))
	difficulty_caption.size = _native(Vector2(36, 5))
	difficulty_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	difficulty_content.add_child(difficulty_caption)
	difficulty_label = _label("< PRO >", 6, PAPER)
	difficulty_label.position = _native(Vector2(2, 12))
	difficulty_label.size = _native(Vector2(36, 20))
	difficulty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	difficulty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	difficulty_content.add_child(difficulty_label)

	var innings_fixture := OptionFixture.new()
	innings_fixture.position = _native(Vector2(50, 130))
	innings_fixture.size = _native(Vector2(40, 38))
	innings_fixture.rest_top = innings_fixture.position.y
	innings_fixture.ink = INK
	innings_fixture.board = PlankCard.BOARD
	innings_fixture.board_lit = S.PANEL_RAISED
	innings_fixture.grain = PlankCard.GRAIN
	innings_fixture.trim = SLATE
	innings_fixture.tick = GOLD
	team_layer.add_child(innings_fixture)
	innings_panel = innings_fixture
	var innings_content := _panel_content(innings_panel)
	var innings_caption := _body_label("INNINGS", 4, STEEL)
	innings_caption.position = _native(Vector2(2, 3))
	innings_caption.size = _native(Vector2(36, 5))
	innings_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	innings_content.add_child(innings_caption)
	innings_label = _score_label("< 3 >", 7, PAPER)
	innings_label.position = _native(Vector2(2, 12))
	innings_label.size = _native(Vector2(36, 20))
	innings_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	innings_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	innings_content.add_child(innings_label)

	# Visible Play Ball control: an opaque enamel plate whose disabled state
	# steps toward ink/slate and drops its shadow (bible 10.4).
	var play_fixture := PlayBallFixture.new()
	play_fixture.name = "PlayBallFixture"
	play_fixture.position = _native(Vector2(92, 130))
	play_fixture.size = _native(Vector2(46, 38))
	play_fixture.rest_top = play_fixture.position.y
	play_fixture.ink = INK
	play_fixture.face = DEEP_INK
	play_fixture.bezel = BEZEL
	play_fixture.disabled_fill = S.PANEL
	play_fixture.rivet = SLATE
	play_fixture.rivet_off = SHADOW_BLUE
	play_fixture.lamp = TEAL
	play_fixture.tick = GOLD
	play_fixture.lit_text = PAPER
	play_fixture.dim_text = SLATE
	team_layer.add_child(play_fixture)
	var play_text := _placed_label(play_fixture, "PLAY BALL", 6, PAPER, Vector2(8, 12), Vector2(34, 14))
	play_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	play_fixture.label = play_text
	play_fixture.set_state(false, false)

	# Test-pinned compatibility surface: external readers gate on
	# play_ball_panel.modulate.a, so that property lives on this non-drawing
	# hidden panel while PlayBallFixture renders the visible opaque control.
	play_ball_panel = PanelContainer.new()
	play_ball_panel.position = _native(Vector2(92, 130))
	play_ball_panel.size = _native(Vector2(46, 38))
	play_ball_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	play_ball_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	play_ball_panel.visible = false
	team_layer.add_child(play_ball_panel)
	play_ball_label = _label("PLAY BALL", 6, PAPER)
	play_ball_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	play_ball_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	play_ball_panel.add_child(play_ball_label)


func _option_panel(parent: Control, at: Vector2, heading: String) -> PanelContainer:
	var panel := _panel(parent, at, Vector2(76, 42), S.PANEL, SHADOW_BLUE, 1)
	var content := _panel_content(panel)
	var caption := _placed_label(content, heading, 5, STEEL, Vector2(2, 3), Vector2(72, 8))
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var value := _placed_label(content, "-", 7, PAPER, Vector2(2, 14), Vector2(72, 20))
	value.name = "Value"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return panel


func _build_final() -> void:
	# Final per bible 10.6: physical result signage over the night harbor. The
	# generated shell fill is retired on this screen only; the HarborBackdrop
	# and PixelAtmosphere contract nodes stay in the tree. main.gd holds the
	# world camera in dugout and is read-only, so a final-only opaque panorama
	# helper paints the five-band night harbor from shared night palette roles.
	for child in final_layer.get_children():
		if child is ColorRect or child.name == "HarborBackdrop":
			(child as CanvasItem).visible = false

	var panorama := FinalNightPanorama.new()
	panorama.name = "FinalNightPanorama"
	panorama.position = Vector2.ZERO
	panorama.size = UI_SIZE
	panorama.sky_high = S.world_role("sky_high", "night")
	panorama.sky_low = S.world_role("sky_low", "night")
	panorama.cloud_lit = S.world_role("cloud_lit", "night")
	panorama.cloud_shade = S.world_role("cloud_shade", "night")
	panorama.sea_deep = S.world_role("sea_deep", "night")
	panorama.sea_mid = S.world_role("sea_mid", "night")
	panorama.sea_light = S.world_role("sea_light", "night")
	panorama.foam = S.world_role("foam", "night")
	panorama.skyline_far = S.world_role("skyline_far", "night")
	panorama.skyline_near = S.world_role("skyline_near", "night")
	panorama.structure = S.world_role("structure", "night")
	panorama.structure_light = S.world_role("structure_light", "night")
	panorama.seat_a = S.world_role("seat_a", "night")
	panorama.seat_b = S.world_role("seat_b", "night")
	panorama.crowd_shade = S.world_role("crowd_shade", "night")
	panorama.turf = S.world_role("turf", "night")
	panorama.turf_shadow = S.world_role("turf_shadow", "night")
	panorama.turf_dark = S.world_role("turf_dark", "night")
	panorama.clay_shadow = S.world_role("clay_shadow", "night")
	panorama.lamp_core = S.world_role("lamp_core", "night")
	panorama.lamp_glow = S.world_role("lamp_glow", "night")
	panorama.chalk = S.world_role("chalk", "night")
	panorama.ink0 = S.world_role("ink0", "night")
	panorama.gold = S.world_role("team_gold", "night")
	panorama.trim_red = S.world_role("stitch", "night")
	panorama.trim_teal = S.world_role("team_teal", "night")
	final_layer.add_child(panorama)

	# One dominant rope-hung enamel result sign (bible 10.1/10.6). Win/new-best
	# re-grades the fixture into the screen's single warm pool inside the sign.
	var sign := FinalResultSign.new()
	sign.name = "FinalResultSign"
	sign.position = _native(Vector2(72, 0))
	sign.size = _native(Vector2(176, 96))
	sign.ink = INK
	sign.face = DEEP_INK
	sign.bezel = BEZEL
	sign.rivet = SLATE
	sign.rope = S.CLAY
	sign.rope_lit = CLAY_LIGHT
	sign.glow = S.WINDOW_GLOW
	sign.gold = GOLD
	final_layer.add_child(sign)

	final_title = _placed_label(final_layer, "FINAL OUT", 8, PAPER, Vector2(80, 24), Vector2(160, 10))
	final_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Display-tier score (bible 10.2): GeistPixel-Square at native 48px, the
	# only Display-48 mark on this screen. Untracked so the widest versus line
	# (two abbreviations plus runs) stays whole inside the board face.
	var display_font: Font = load("res://assets/fonts/geist_pixel/GeistPixel-Square.ttf")
	final_score = _label("0 - 0", 12, PAPER)
	final_score.add_theme_font_override("font", display_font)
	final_score.position = _native(Vector2(76, 38))
	final_score.size = _native(Vector2(168, 16))
	final_score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_score.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	final_layer.add_child(final_score)
	final_stats = _body_label("", 5, STEEL)
	final_stats.position = _native(Vector2(84, 58))
	final_stats.size = _native(Vector2(152, 24))
	final_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	final_stats.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	final_stats.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	final_layer.add_child(final_stats)
	# REMATCH/EXIT as painted-plank fixtures (bible 10.1/10.4): array order,
	# labels, and controller navigation are unchanged; only presentation moves.
	for index in range(2):
		var action := FinalActionFixture.new()
		action.position = _native(Vector2(84 + index * 88, 136))
		action.size = _native(Vector2(64, 24))
		action.rest_top = action.position.y
		action.ink = INK
		action.board = PlankCard.BOARD
		action.board_lit = S.PANEL_RAISED
		action.grain = PlankCard.GRAIN
		action.trim = STITCH if index == 0 else SLATE
		action.tick = GOLD
		action.grain_seed = index
		final_layer.add_child(action)
		final_actions.append(action)
		var label := _label("REMATCH" if index == 0 else "EXIT", 8, PAPER)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		action.add_child(label)
		final_action_labels.append(label)


func _build_game_hud() -> void:
	game_layer = _root_control("GameHUD")
	game_layer.theme = S.ui_theme()
	game_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(game_layer)

	# Enamel lightboard (bible §10.1/§10.5): the only full-bleed top strip, an
	# opaque ink face inside a raised bezel with rivet cells in the corners.
	_top_board = _panel(game_layer, Vector2(0, 0), Vector2(320, 14), DEEP_INK, BEZEL, 1)
	var top_content := _panel_content(_top_board)
	for corner in [Vector2(0, 0), Vector2(317, 0), Vector2(0, 11), Vector2(317, 11)]:
		_add_rect(top_content, corner, Vector2.ONE, SLATE)
	score_label = _score_label("AWY 0 - 0 HME", 9, GOLD)
	score_label.position = _native(Vector2(2, 0))
	score_label.size = _native(Vector2(94, 12))
	top_content.add_child(score_label)
	_inning_chevron = ChevronCell.new()
	_inning_chevron.position = _native(Vector2(98, 5))
	_inning_chevron.size = _native(Vector2(4, 2))
	_inning_chevron.color = PAPER
	top_content.add_child(_inning_chevron)
	inning_label = _placed_label(top_content, "1ST", 6, PAPER, Vector2(103, 2), Vector2(34, 9))
	# The raw count string keeps feeding external readers; the visible count is
	# the shaped pip row (balls round, strikes square — bible §10.5/§11.3).
	count_label = _score_label("0-0", 8, PAPER)
	count_label.position = _native(Vector2(139, 1))
	count_label.size = _native(Vector2(28, 10))
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.visible = false
	top_content.add_child(count_label)
	_count_pips = CountPips.new()
	_count_pips.position = _native(Vector2(137, 5))
	_count_pips.size = _native(Vector2(25, 3))
	_count_pips.fill = PAPER
	_count_pips.hollow = SLATE
	_count_pips.backdrop = DEEP_INK
	top_content.add_child(_count_pips)
	outs_label = _placed_label(top_content, "OUT", 4, STEEL, Vector2(171, 4), Vector2(17, 7))
	for index in range(3):
		var lamp := Panel.new()
		lamp.position = _native(Vector2(190 + index * 6, 4))
		lamp.size = _native(Vector2(4, 4))
		lamp.add_theme_stylebox_override("panel", _style(DEEP_INK, SHADOW_BLUE, 1, 0))
		top_content.add_child(lamp)
		out_lamps.append(lamp)
	# Baserunner diamond (bible §10.5): rotated-square cells whose corners
	# touch — first right, second top, third left — with a chalk plate cell
	# closing the bottom vertex.
	var base_offsets := [Vector2(292, 5), Vector2(289, 2), Vector2(286, 5)]
	for index in range(3):
		var cell := DiamondCell.new()
		cell.position = _native(base_offsets[index])
		cell.size = _native(Vector2(3, 3))
		cell.fill = GOLD
		cell.hollow = SLATE
		cell.backdrop = DEEP_INK
		top_content.add_child(cell)
		bases.append(cell)
		_base_cells.append(cell)
	var plate := DiamondCell.new()
	plate.position = _native(Vector2(289, 8))
	plate.size = _native(Vector2(3, 3))
	plate.fill = PAPER
	plate.occupied = true
	top_content.add_child(plate)

	_identity_board = _panel(game_layer, Vector2(3, 15), Vector2(123, 12), DEEP_INK, BEZEL, 1)
	var identity_content := _panel_content(_identity_board)
	identity_label = _placed_label(identity_content, "BATTER", 5, PAPER, Vector2(2, 1), Vector2(65, 8))
	identity_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	identity_detail_label = _placed_label(identity_content, "", 4, STEEL, Vector2(69, 1), Vector2(51, 8))
	identity_detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	# Keep the right 96-pixel rail clear for the post-pitch Intel card.
	_arm_board = _panel(game_layer, Vector2(128, 15), Vector2(87, 12), DEEP_INK, BEZEL, 1)
	var arm_content := _panel_content(_arm_board)
	pitcher_label = _placed_label(arm_content, "STARTER (RHP)", 4, PAPER, Vector2(2, 1), Vector2(40, 7))
	pitcher_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	stamina_label = _placed_label(arm_content, "ARM 100%", 4, GRASS, Vector2(44, 1), Vector2(40, 7))
	stamina_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stamina_bar = ProgressBar.new()
	stamina_bar.position = Vector2.ZERO
	stamina_bar.size = _native(Vector2.ONE)
	stamina_bar.min_value = 0.0
	stamina_bar.max_value = 1.0
	stamina_bar.value = 1.0
	stamina_bar.show_percentage = false
	stamina_bar.visible = false
	arm_content.add_child(stamina_bar)
	_stamina_track = _add_rect(arm_content, Vector2(2, 8), Vector2(82, 2), SHADOW_BLUE)
	_stamina_fill = _add_rect(arm_content, Vector2(2, 8), Vector2(82, 2), GRASS)

	# Situation text rides the lightboard right-aligned in team trim; gold on
	# this board is reserved for the score digits (bible §10.2).
	phase_label = _placed_label(top_content, "PLAY BALL", 4, TEAL, Vector2(210, 2), Vector2(66, 9))
	phase_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	strike_zone = StrikeZone.new()
	strike_zone.name = "StrikeZone"
	strike_zone.position = _native(Vector2(121, 62))
	strike_zone.size = _native(Vector2(78, 72))
	strike_zone.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_layer.add_child(strike_zone)

	result_panel = _panel(game_layer, Vector2(90, 67), Vector2(140, 40), DEEP_INK, GOLD, 2)
	var result_content := _panel_content(result_panel)
	result_label = _placed_label(result_content, "PLAY BALL", 12, GOLD, Vector2(3, 3), Vector2(134, 16))
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	detail_label = _body_label("", 6, PAPER)
	detail_label.position = _native(Vector2(3, 20))
	detail_label.size = _native(Vector2(134, 14))
	detail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_content.add_child(detail_label)
	result_panel.modulate.a = 0.0

	# Chalk rail (bible §10.5): the bottom full-bleed ink strip with chalk-dust
	# bookend ticks. Help verbs sit directly on the rail, so the help panel
	# itself stays unpainted inside the test-pinned y=596 band.
	_add_rect(game_layer, Vector2(0, 149), Vector2(320, 10), INK)
	_add_rect(game_layer, Vector2(8, 153), Vector2.ONE, PAPER)
	_add_rect(game_layer, Vector2(311, 153), Vector2.ONE, PAPER)
	help_panel = _panel(game_layer, Vector2(4, 149), Vector2(312, 8), INK, INK, 0)
	# The rail itself supplies the material. An empty panel style removes the
	# generic panel's content margins so native 20px chalk type stays inside
	# the test-pinned 32px band without overlapping the pennants.
	help_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	help_label = _body_label("", 5, PAPER)
	help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	help_panel.add_child(help_label)
	help_panel.visible = false

	field_meter = ProgressBar.new()
	field_meter.position = _native(Vector2(105, 151))
	field_meter.size = _native(Vector2(110, 4))
	field_meter.min_value = 0.0
	field_meter.max_value = 1.0
	field_meter.show_percentage = false
	field_meter.visible = false
	field_meter.add_theme_stylebox_override("background", _style(INK, PAPER, 1, 0))
	field_meter.add_theme_stylebox_override("fill", _style(TEAL, GRASS, 1, 0))
	game_layer.add_child(field_meter)

	pitch_row = Control.new()
	pitch_row.name = "PitchRow"
	pitch_row.position = _native(Vector2(70, 157))
	pitch_row.size = _native(Vector2(180, 18))
	pitch_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_layer.add_child(pitch_row)
	# Pennant tabs (bible §10.1/§10.5): triangle-tail flags in the pitch-slot
	# hues with an ink contour. The focused pennant hoists 4 native px and
	# takes a gold hoist bar; unfocused cloth and lettering dim to steel.
	for index in range(5):
		var card := PennantTab.new()
		card.position = _native(Vector2(index * 36, 1))
		card.size = _native(Vector2(33, 17))
		card.cloth = C.PITCHES[index].color
		card.ink = INK
		card.hoist = GOLD
		card.dim = SHADOW_BLUE
		pitch_row.add_child(card)
		pitch_cards.append(card)
		_pitch_flags.append(card)
		var label := _score_label("%d %s" % [index + 1, C.PITCHES[index].code], 7, STEEL)
		label.position = _native(Vector2(1, 1))
		label.size = _native(Vector2(31, 9))
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		card.add_child(label)
		pitch_labels.append(label)

	event_feed_back = _panel(game_layer, Vector2(218, 61), Vector2(98, 51), DEEP_INK, BEZEL, 1)
	event_feed = VBoxContainer.new()
	event_feed.position = _native(Vector2(221, 64))
	event_feed.size = _native(Vector2(92, 45))
	event_feed.alignment = BoxContainer.ALIGNMENT_END
	event_feed.add_theme_constant_override("separation", 0)
	game_layer.add_child(event_feed)
	event_feed_back.visible = false
	event_feed.visible = false
	game_layer.visible = false


func show_landing(stats: Dictionary, focus: int) -> void:
	_show_shell_layer(landing_layer)
	landing_prompt.text = "INSERT COIN - PRESS START"
	landing_stat_lines[0].text = "BEST RUN %d K" % int(stats.get("best_endless_strikeouts", 0))
	landing_stat_lines[1].text = "RECORD %d–%d" % [int(stats.get("versus_wins", 0)), int(stats.get("versus_losses", 0))]
	for index in range(landing_cards.size()):
		var active := index == focus
		var card := landing_cards[index] as PlankCard
		if card != null:
			card.set_focused(active)
		landing_card_titles[index].add_theme_color_override("font_color", GOLD if active else PAPER)
		landing_card_ctas[index].add_theme_stylebox_override("panel", _style(STITCH if active else NIGHT2, INK, 1, 0))


func show_pitcher_select(pitchers: Array[Dictionary], index: int) -> void:
	_show_shell_layer(pitcher_layer)
	if pitchers.is_empty():
		return
	var selected := clampi(index, 0, pitchers.size() - 1)
	var rail := pitcher_layer.get_node_or_null("RosterRail") as RosterRail
	if rail != null:
		rail.count = mini(pitchers.size(), pitcher_cards.size())
		rail.focus_index = selected
		rail.queue_redraw()
	for card_index in range(pitcher_cards.size()):
		var slat_label: Label = null
		if rail != null and card_index < rail.get_child_count():
			slat_label = rail.get_child(card_index) as Label
		if card_index >= pitchers.size():
			pitcher_cards[card_index].visible = false
			if slat_label != null:
				slat_label.visible = false
			continue
		var pitcher: Dictionary = pitchers[card_index]
		var active := card_index == selected
		var metrics := derive_pitcher_metrics(pitcher, pitchers)
		var surname := String(pitcher.get("name", "UNKNOWN")).to_upper().left(10)
		# Focus-centered window: the focused card is the visible identity
		# plate; the roster rail keeps every arm on screen and navigable.
		pitcher_cards[card_index].visible = active
		pitcher_card_labels[card_index].text = "%s\n#%02d %s\nOVR %d" % [surname, int(pitcher.get("number", 0)), String(pitcher.get("throws", "R")), int(metrics.ovr)]
		if slat_label != null:
			slat_label.visible = true
			slat_label.text = "#%02d %s" % [int(pitcher.get("number", 0)), surname]
			slat_label.add_theme_color_override("font_color", PAPER if active else STEEL)
			slat_label.position.y = card_index * RosterRail.SLAT_STEP + 8 - (4 if active else 0)
	var pitcher: Dictionary = pitchers[selected]
	var metrics := derive_pitcher_metrics(pitcher, pitchers)
	pitcher_detail_name.text = "%s #%02d" % [String(pitcher.get("name", "UNKNOWN")).to_upper(), int(pitcher.get("number", 0))]
	pitcher_detail_metrics.text = "OVR %d  ERA %.2f  K/9 %.1f\n%s  %sHP  %.1f MPH" % [int(metrics.ovr), float(metrics.era), float(metrics.k9), String(metrics.archetype), String(pitcher.get("throws", "R")), float(metrics.velocity)]
	var arsenal: Array[String] = []
	for pitch_value in pitcher.get("pitches", []):
		var pitch: Dictionary = pitch_value
		arsenal.append("%s %.0f" % [String(pitch.get("code", "--")), float(pitch.get("velocity", 0.0))])
	pitcher_detail_arsenal.text = "ARSENAL\n" + "  ".join(arsenal)
	var chip := pitcher_layer.get_node_or_null("PortraitChip") as PitcherPortraitChip
	if chip != null:
		chip.throws = String(pitcher.get("throws", "R"))
		chip.queue_redraw()
	var chip_number := pitcher_layer.get_node_or_null("PortraitNumber") as Label
	if chip_number != null:
		chip_number.text = "#%02d" % int(pitcher.get("number", 0))
	var stamina := float(metrics.stamina)
	pitcher_stamina.value = stamina
	var stamina_color := S.meter_color(stamina)
	pitcher_stamina.add_theme_stylebox_override("background", _style(INK, SHADOW_BLUE, 1, 0))
	pitcher_stamina.add_theme_stylebox_override("fill", _style(stamina_color, stamina_color, 0, 0))
	if _pitcher_stamina_fill != null:
		_pitcher_stamina_fill.color = stamina_color
		# Fill snaps to the 4px rhythm across the 256px track.
		_pitcher_stamina_fill.size.x = roundi(S.native_scalar(16.0) * stamina) * 4


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
		team_card_labels[index].text = String(team.get("name", "CLUB")).to_upper()
		team_card_chips[index].text = "P1" if index == player_index else ("CPU" if index == cpu_index else "")
		# P1 reads as ink on the filled stitch tag, CPU as teal on the hollow
		# tag — shape plus text differentiated, and quieter than gold focus.
		team_card_chips[index].add_theme_color_override("font_color", INK if index == player_index else TEAL)
		var card := team_cards[index] as ClubPlankCard
		if card != null:
			card.trim = _team_color(team)
			if card.city_label != null:
				card.city_label.text = String(team.get("city", "HARBOR")).to_upper()
			if card.stats_label != null:
				card.stats_label.text = "BAT %d PIT %d" % [int(team.get("bat", 0)), int(team.get("pit", 0))]
			card.set_state(focus == index, index == player_index, index == cpu_index)
	difficulty_label.text = "< %s >" % String(state.get("difficulty_name", "PRO"))
	innings_label.text = "< %d >" % int(state.get("innings", 3))
	var difficulty_fixture := difficulty_panel as OptionFixture
	if difficulty_fixture != null:
		difficulty_fixture.set_focused(focus == 8)
	var innings_fixture := innings_panel as OptionFixture
	if innings_fixture != null:
		innings_fixture.set_focused(focus == 9)
	var can_play := bool(state.get("can_play", false))
	# Test-pinned compatibility property: the alpha stays on the non-drawing
	# panel while PlayBallFixture renders the same state as opaque material.
	play_ball_panel.modulate.a = 1.0 if can_play else 0.5
	var play_fixture := team_layer.get_node_or_null("PlayBallFixture") as PlayBallFixture
	if play_fixture != null:
		play_fixture.set_state(can_play, focus == 10)
	if player_index < 0:
		matchup_label.text = "P1: PICK A CLUB"
	elif cpu_index < 0:
		matchup_label.text = "P1 %s / CPU: PICK ANOTHER" % String(teams[player_index].get("abbr", "P1"))
	else:
		matchup_label.text = "P1 %s VS %s CPU" % [String(teams[player_index].get("abbr", "P1")), String(teams[cpu_index].get("abbr", "CPU"))]


func show_final(mode: String, state: Dictionary, stats: Dictionary, new_best: bool, focus: int) -> void:
	_show_shell_layer(final_layer)
	_final_focus = clampi(focus, 0, 1)
	var celebrate := false
	if mode == "endless":
		var endless: Dictionary = state.get("endless", {})
		var strikeouts := int(endless.get("strikeouts", state.get("strikeouts", 0)))
		final_title.text = "NEW BEST!" if new_best else "ARM RETIRED"
		final_score.text = "%d K" % strikeouts
		final_stats.text = "FACED %d  /  PITCHES %d  /  RUNS %d\nCAREER BEST %d K" % [int(endless.get("batters_faced", 0)), int(endless.get("pitch_count", state.get("pitch_serial", 0))), int(endless.get("runs_allowed", state.get("score", {}).get("away", 0))), int(stats.get("best_endless_strikeouts", strikeouts))]
		celebrate = new_best
	else:
		var score: Dictionary = state.get("score", {})
		var p1_won := String(state.get("winner", "")) == "home"
		final_title.text = "HARBOR CHAMPIONS" if p1_won else "FINAL OUT"
		final_score.text = "%s %d - %d %s" % [String(_home_team.get("abbr", "P1")), int(score.get("home", 0)), int(score.get("away", 0)), String(_away_team.get("abbr", "CPU"))]
		var line_score: Dictionary = state.get("line_score", {})
		var innings := int(state.get("innings", 3))
		final_stats.text = "%d INN  /  HITS %d-%d  /  RECORD %d-%d\nLINE %s / %s" % [innings, int(state.get("hits", {}).get("home", 0)), int(state.get("hits", {}).get("away", 0)), int(stats.get("versus_wins", 0)), int(stats.get("versus_losses", 0)), _line_score_text(line_score.get("home", []), innings), _line_score_text(line_score.get("away", []), innings)]
		celebrate = p1_won
	# Winner/new-best hierarchy (bible 6.1 lantern logic, 9.7): a win makes the
	# result sign the single warm pool and arms the bounded celebration; a loss
	# stays cool chalk/steel with gold reserved for the focused action ticks.
	final_title.add_theme_color_override("font_color", GOLD if celebrate else PAPER)
	final_score.add_theme_color_override("font_color", GOLD if celebrate else PAPER)
	var sign := final_layer.get_node_or_null("FinalResultSign") as FinalResultSign
	if sign != null:
		sign.set_celebration(celebrate)
	var panorama := final_layer.get_node_or_null("FinalNightPanorama") as FinalNightPanorama
	if panorama != null:
		panorama.set_celebration(celebrate)
	for index in range(final_actions.size()):
		var active := index == _final_focus
		var fixture := final_actions[index] as FinalActionFixture
		if fixture != null:
			fixture.set_focused(active)
		final_action_labels[index].add_theme_color_override("font_color", PAPER if active else STEEL)


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
	title_matchup_label.text = "STARTER %d/%d / OVR %d / %s" % [index + 1, total, int(metrics.ovr), String(metrics.archetype)]


func set_arsenal(pitches: Array) -> void:
	for index in range(pitch_labels.size()):
		if index >= pitches.size():
			pitch_cards[index].visible = false
			pitch_labels[index].visible = false
			continue
		var pitch: Dictionary = pitches[index]
		pitch_cards[index].visible = true
		pitch_labels[index].visible = true
		pitch_labels[index].text = "%d %s" % [index + 1, String(pitch.get("code", pitch.get("name", "--"))).to_upper()]


func update_state(state: Dictionary) -> void:
	var away_score := int(state.get("away_score", 0))
	var home_score := int(state.get("home_score", 0))
	score_label.text = "%s %d - %d %s" % [String(_away_team.get("abbr", "AWY")), away_score, home_score, String(_home_team.get("abbr", "HME"))]
	inning_label.text = _ordinal(int(state.get("inning", 1)))
	_inning_chevron.points_up = bool(state.get("top", true))
	_inning_chevron.queue_redraw()
	var throws := String(state.get("pitcher_throws", "R")).left(1).to_upper()
	pitcher_label.text = "%s (%sHP)" % [String(state.get("pitcher_name", "STARTER")).to_upper(), throws]
	count_label.text = "%d-%d" % [int(state.get("balls", 0)), int(state.get("strikes", 0))]
	_count_pips.balls = int(state.get("balls", 0))
	_count_pips.strikes = int(state.get("strikes", 0))
	_count_pips.queue_redraw()
	_outs_shown = int(state.get("outs", 0))
	_restyle_out_lamps()
	var occupied: Array = state.get("bases", [false, false, false])
	for index in range(mini(3, occupied.size())):
		_base_cells[index].occupied = bool(occupied[index])
		_base_cells[index].queue_redraw()
	phase_label.text = String(state.get("phase_label", state.get("phase", "PLAY BALL"))).to_upper()


func set_stamina(value: float, status: String = "") -> void:
	if stamina_bar == null:
		return
	var stamina := clampf(value, 0.0, 1.0)
	var tier := S.stamina_tier(stamina)
	var color: Color = tier.color
	_stamina_gassed = bool(tier.gassed) or status.to_lower() == "gassed"
	stamina_label.text = "ARM %d%%" % roundi(stamina * 100.0)
	stamina_label.add_theme_color_override("font_color", color)
	stamina_bar.value = stamina
	stamina_bar.add_theme_stylebox_override("background", _style(INK, SHADOW_BLUE, 1, 0))
	stamina_bar.add_theme_stylebox_override("fill", _style(color, color, 0, 0))
	if _stamina_fill != null:
		_stamina_fill.color = color
		_stamina_fill.size.x = roundi(S.native_scalar(82.0) * stamina)


func set_identity(text: String) -> void:
	var parts := text.split("•")
	identity_label.text = parts[0].strip_edges() if not parts.is_empty() else text
	var details: Array[String] = []
	for index in range(1, parts.size()):
		details.append(parts[index].strip_edges())
	identity_detail_label.text = " / ".join(details)


func set_help(text: String) -> void:
	help_label.text = text.replace(" / ", "  ·  ")
	help_panel.visible = not text.is_empty()


func set_batting_layout(enabled: bool) -> void:
	_batting_layout = enabled
	if enabled:
		pitch_row.visible = false
	strike_zone.queue_redraw()


func set_strike_zone_rect(screen_rect: Rect2) -> void:
	if screen_rect.size.x <= 1.0 or screen_rect.size.y <= 1.0:
		return
	strike_zone.position = screen_rect.position.round()
	strike_zone.size = screen_rect.size.round()
	strike_zone.queue_redraw()


func set_strike_zone_lateral_sign(value: float) -> void:
	strike_zone.set_lateral_screen_sign(value)


func set_aim(value: Vector2, accent := TEAL) -> void:
	strike_zone.accent = accent
	strike_zone.set_aim(value)


func set_pitch_marker(value: Vector2, visible: bool) -> void:
	strike_zone.set_pitch(value, visible)


func set_strike_zone_visible(visible: bool) -> void:
	strike_zone.visible = visible


func set_pitch_selector(visible: bool, selected := -1) -> void:
	_pitch_selector_active = visible and not _batting_layout
	pitch_row.visible = _pitch_selector_active
	_sync_event_feed_visibility()
	for index in range(_pitch_flags.size()):
		var active := index == selected
		_pitch_flags[index].focused = active
		_pitch_flags[index].position.y = 0.0 if active else float(S.NATIVE_UNIT)
		_pitch_flags[index].queue_redraw()
		pitch_labels[index].add_theme_color_override("font_color", INK if active else _pennant_rest_color())


func set_field_meter(visible: bool, value := 0.0) -> void:
	field_meter.visible = visible
	field_meter.value = value


func banner(title: String, detail := "", accent := GOLD, hold := 1.25) -> void:
	result_label.text = title.to_upper()
	result_label.add_theme_color_override("font_color", accent)
	detail_label.text = detail
	if _banner_tween != null and _banner_tween.is_valid():
		_banner_tween.kill()
	result_panel.modulate.a = 1.0
	_banner_tween = create_tween()
	_banner_tween.tween_interval(hold)
	_banner_tween.tween_property(result_panel, "modulate:a", 0.0, 0.16)


func push_event(text: String, color := CHALK) -> void:
	var line := _body_label(text.to_upper(), 5, color)
	line.custom_minimum_size = _native(Vector2(92, 8))
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	event_feed.add_child(line)
	while event_feed.get_child_count() > 5:
		var oldest := event_feed.get_child(0)
		event_feed.remove_child(oldest)
		oldest.free()
	_layout_event_feed()
	_sync_event_feed_visibility()


func remove_event(text: String) -> void:
	var normalized := text.to_upper()
	for child in event_feed.get_children():
		if child is Label and String((child as Label).text).to_upper() == normalized:
			event_feed.remove_child(child)
			child.free()
	_layout_event_feed()
	_sync_event_feed_visibility()


func clear_events() -> void:
	for child in event_feed.get_children():
		event_feed.remove_child(child)
		child.free()
	_sync_event_feed_visibility()


func _sync_event_feed_visibility() -> void:
	var show := event_feed.get_child_count() > 0 and not _pitch_selector_active
	event_feed_back.visible = show
	event_feed.visible = show


## The world mood published by the stadium facade (group pixiball_pixel_world,
## canvas `mood`). The HUD only reads it; shell/tests without a stadium stay
## on the day grade.
func _world_mood() -> String:
	if not is_inside_tree():
		return _hud_mood
	var world := get_tree().get_first_node_in_group(&"pixiball_pixel_world")
	if world == null or not world.has_method("get_canvas"):
		return "day"
	var canvas: Variant = world.call("get_canvas")
	if canvas == null or not (canvas is Node):
		return "day"
	var mood_value: Variant = (canvas as Node).get("mood")
	return String(mood_value) if mood_value is String else "day"


## Night readability grade (bible §11.1/§11.6): at night the world compresses
## into the furniture's own V0-V2 rungs, so the bezel rims and every hollow or
## unlit glyph ring step one authored rung lighter to hold the one-second
## paused-frame read. All values are opaque authored roles; geometry, day and
## golden output, and the single gold focal system are untouched.
func _apply_hud_mood() -> void:
	var night := _hud_mood == "night"
	var bezel := BEZEL_NIGHT if night else BEZEL
	for board in [_top_board, _identity_board, _arm_board, event_feed_back]:
		if board != null:
			board.add_theme_stylebox_override("panel", _style(DEEP_INK, bezel, 1, 0))
	if _count_pips != null:
		_count_pips.hollow = STEEL if night else SLATE
		_count_pips.queue_redraw()
	for cell in _base_cells:
		cell.hollow = STEEL if night else SLATE
		cell.queue_redraw()
	_restyle_out_lamps()
	for index in range(_pitch_flags.size()):
		if not _pitch_flags[index].focused:
			pitch_labels[index].add_theme_color_override("font_color", _pennant_rest_color())


func _restyle_out_lamps() -> void:
	var ring_off := SLATE if _hud_mood == "night" else SHADOW_BLUE
	for index in range(out_lamps.size()):
		var lit := _outs_shown > index
		out_lamps[index].add_theme_stylebox_override("panel", _style(STITCH if lit else DEEP_INK, INK if lit else ring_off, 1, 0))


## Rest-state pennant lettering: steel by day/golden, chalk at night so the
## verb survives over the shadow-dimmed cloth; the focused tab keeps its ink
## lettering, full cloth, and gold hoist as the only loud pennant.
func _pennant_rest_color() -> Color:
	return PAPER if _hud_mood == "night" else STEEL


func _layout_event_feed() -> void:
	var rows := event_feed.get_child_count()
	var height := clampi(6 + rows * 8, 14, 48)
	event_feed_back.position = _native(Vector2(218, 112 - height))
	event_feed_back.size = _native(Vector2(98, height))
	event_feed.position = _native(Vector2(221, 109 - height))
	event_feed.size = _native(Vector2(92, height - 4))


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
	panel.add_theme_stylebox_override("panel", _style(S.PANEL_RAISED if active else S.PANEL, TEAL if active else SHADOW_BLUE, 2 if active else 1, 0))


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


func _root_control(node_name: String) -> Control:
	var control := Control.new()
	control.name = node_name
	control.position = Vector2.ZERO
	control.size = UI_SIZE
	control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	control.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return control


func _panel(parent: Control, at: Vector2, dimensions: Vector2, fill: Color, border: Color, border_width := 1) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.position = _native(at)
	panel.size = _native(dimensions)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style(fill, border, border_width, 0))
	parent.add_child(panel)
	return panel


func _panel_content(panel: PanelContainer) -> Control:
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)
	return content


func _add_rect(parent: Control, at: Vector2, dimensions: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = _native(at)
	rect.size = _native(dimensions)
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(rect)
	return rect


func _placed_label(parent: Control, text: String, font_size: int, color: Color, at: Vector2, dimensions: Vector2) -> Label:
	var label := _label(text, font_size, color)
	label.position = _native(at)
	label.size = _native(dimensions)
	parent.add_child(label)
	return label


func _label(text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	label.clip_text = true
	label.add_theme_font_size_override("font_size", font_size * S.NATIVE_UNIT)
	label.add_theme_color_override("font_color", color)
	return label


func _body_label(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, font_size, color)
	label.add_theme_font_override("font", S.FONT_BODY)
	return label


func _score_label(text: String, font_size: int, color: Color) -> Label:
	var label := _label(text, font_size, color)
	label.add_theme_font_override("font", S.FONT_SCORE)
	return label


func _style(fill: Color, border: Color, border_width: int, _radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(maxi(border_width * S.NATIVE_UNIT, 0))
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.border_blend = false
	style.content_margin_left = S.NATIVE_UNIT
	style.content_margin_right = S.NATIVE_UNIT
	style.content_margin_top = S.NATIVE_UNIT
	style.content_margin_bottom = S.NATIVE_UNIT
	return style


func _native(value: Vector2) -> Vector2:
	return S.native_vector(value)


class ChevronCell extends Control:
	## Inning-half chevron on the lightboard (bible §10.5): a stepped chalk
	## chevron cell that points up for the top half, down for the bottom.
	var points_up := true
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if points_up:
			draw_rect(Rect2(4, 0, 8, 4), color)
			draw_rect(Rect2(0, 4, 4, 4), color)
			draw_rect(Rect2(12, 4, 4, 4), color)
		else:
			draw_rect(Rect2(0, 0, 4, 4), color)
			draw_rect(Rect2(12, 0, 4, 4), color)
			draw_rect(Rect2(4, 4, 8, 4), color)


class CountPips extends Control:
	## Shaped count pips (bible §10.5/§11.3): balls are round cells, strikes
	## square cells, so the count never reads by hue alone. Filled pips are
	## chalk; empty pips are slate rings over the board face.
	var balls := 0
	var strikes := 0
	var fill := Color.WHITE
	var hollow := Color.GRAY
	var backdrop := Color.BLACK

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for index in range(3):
			_draw_round(index * 20, index < balls)
		for index in range(2):
			_draw_square(68 + index * 20, index < strikes)

	func _draw_round(x: int, filled: bool) -> void:
		var color := fill if filled else hollow
		draw_rect(Rect2(x + 4, 0, 4, 4), color)
		draw_rect(Rect2(x, 4, 12, 4), color)
		draw_rect(Rect2(x + 4, 8, 4, 4), color)
		if not filled:
			draw_rect(Rect2(x + 4, 4, 4, 4), backdrop)

	func _draw_square(x: int, filled: bool) -> void:
		draw_rect(Rect2(x, 0, 12, 12), fill if filled else hollow)
		if not filled:
			draw_rect(Rect2(x + 4, 4, 4, 4), backdrop)


class DiamondCell extends Panel:
	## One rotated-square cell of the baserunner diamond (bible §10.5). Stays a
	## Panel so the public `bases` array keeps its type; the square face is
	## replaced by a stepped diamond draw.
	var occupied := false
	var fill := Color.WHITE
	var hollow := Color.GRAY
	var backdrop := Color.BLACK

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	func _draw() -> void:
		var color := fill if occupied else hollow
		draw_rect(Rect2(4, 0, 4, 4), color)
		draw_rect(Rect2(0, 4, 12, 4), color)
		draw_rect(Rect2(4, 8, 4, 4), color)
		if not occupied:
			draw_rect(Rect2(4, 4, 4, 4), backdrop)


class PennantTab extends Panel:
	## Pitch-selector pennant (bible §10.1/§10.5): a triangle-tail flag with a
	## one-cell ink contour, drawn as whole 4px rows. Focus swaps the cloth to
	## its full hue and hangs a gold hoist bar along the top edge; unfocused
	## cloth pre-blends toward the cool shadow so only one tab is loud.
	const INK_ROWS := [
		[0, 0, 132, 40],
		[12, 40, 108, 4],
		[28, 44, 76, 4],
		[44, 48, 44, 4],
		[56, 52, 20, 4],
		[60, 56, 12, 4],
	]
	const CLOTH_ROWS := [
		[4, 4, 124, 36],
		[16, 40, 100, 4],
		[32, 44, 68, 4],
		[48, 48, 36, 4],
		[60, 52, 12, 4],
	]

	var cloth := Color.WHITE
	var focused := false
	var ink := Color.BLACK
	var hoist := Color.YELLOW
	var dim := Color.DIM_GRAY

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	func _draw() -> void:
		for row in INK_ROWS:
			draw_rect(Rect2(row[0], row[1], row[2], row[3]), ink)
		var color := cloth if focused else cloth.lerp(dim, 0.55)
		for row in CLOTH_ROWS:
			draw_rect(Rect2(row[0], row[1], row[2], row[3]), color)
		if focused:
			draw_rect(Rect2(0, 0, 132, 4), hoist)


class EnamelSign extends Control:
	## Landing title sign (bible 10.6): an enamel board rope-hung from the top
	## frame with a hard offset ink shadow, corner rivets, and two stepped
	## opaque cage-lamp cues. Halo steps pre-blend toward the board face —
	## never alpha, never a gradient. All marks are whole 4px cells.

	var ink := Color.BLACK
	var face := Color.BLACK
	var bezel := Color.MIDNIGHT_BLUE
	var rivet := Color.GRAY
	var rope := Color.SADDLE_BROWN
	var rope_lit := Color.BURLYWOOD
	var glow := Color.LIGHT_YELLOW
	var gold := Color.YELLOW

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for rope_x in [64, 380]:
			draw_rect(Rect2(rope_x, 0, 4, 40), rope)
			draw_rect(Rect2(rope_x, 8, 4, 4), rope_lit)
			draw_rect(Rect2(rope_x, 24, 4, 4), rope_lit)
			draw_rect(Rect2(rope_x - 4, 32, 12, 8), rope)
			draw_rect(Rect2(rope_x - 4, 32, 4, 4), rope_lit)
		draw_rect(Rect2(16, 56, 448, 120), ink)
		draw_rect(Rect2(0, 40, 448, 120), bezel)
		draw_rect(Rect2(4, 44, 440, 112), face)
		for corner in [Vector2(8, 48), Vector2(436, 48), Vector2(8, 148), Vector2(436, 148)]:
			draw_rect(Rect2(corner, Vector2(4, 4)), rivet)
		for lamp_x in [72, 348]:
			_draw_cage_lamp(lamp_x, 116)

	func _draw_cage_lamp(x: int, y: int) -> void:
		draw_rect(Rect2(x - 8, y - 8, 44, 40), gold.lerp(face, 0.78))
		draw_rect(Rect2(x - 4, y - 4, 36, 32), gold.lerp(face, 0.55))
		draw_rect(Rect2(x + 12, y - 12, 4, 4), ink)
		draw_rect(Rect2(x, y, 28, 24), ink)
		draw_rect(Rect2(x + 4, y + 4, 20, 16), glow)
		draw_rect(Rect2(x + 8, y + 4, 4, 16), ink)
		draw_rect(Rect2(x + 16, y + 4, 4, 16), ink)


class PlankCard extends PanelContainer:
	## Landing mode card (bible 10.1/10.6): a painted plank with wood-grain
	## dashes, a team-trim edge stripe, a Marquee-compatible plank-chip emblem,
	## and a hard offset ink shadow. Focus is lantern-gold corner ticks plus a
	## 4px lift with a matching 4px shadow grow (bible 10.4).

	# Plank material hexes are bible-specified (10.1); fold them into
	# PixiballStyle roles when the palette-foundation pass reworks S.
	const BOARD := Color("2c3a55")
	const GRAIN := Color("374763")
	# Deterministic authored grain dashes [x, y, w]; each dash is one 4px row.
	const GRAIN_DASHES := [
		[120, 20, 16], [280, 16, 20], [396, 20, 16],
		[120, 36, 24], [220, 40, 16], [320, 36, 20], [404, 40, 24],
		[116, 84, 16], [244, 88, 24], [356, 84, 20],
		[28, 116, 20], [64, 120, 16],
	]
	const TICK_ARM := 16
	const TICK_THICK := 4

	var ink := Color.BLACK
	var tick := Color.YELLOW
	var trim := Color.RED
	var chalk := Color.WHITE
	var stitch := Color.RED
	var teal := Color.CYAN
	var emblem := "ball"
	var focused := false
	var rest_top := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	func set_focused(active: bool) -> void:
		focused = active
		position.y = rest_top - (4.0 if active else 0.0)
		queue_redraw()

	func _draw() -> void:
		var drop := 20.0 if focused else 16.0
		draw_rect(Rect2(Vector2(drop, drop), size), ink)
		draw_rect(Rect2(Vector2.ZERO, size), ink)
		draw_rect(Rect2(8, 8, size.x - 16, size.y - 16), BOARD)
		var seam := BOARD.lerp(ink, 0.4)
		draw_rect(Rect2(16, 48, size.x - 24, 4), seam)
		draw_rect(Rect2(16, 100, size.x - 24, 4), seam)
		for dash in GRAIN_DASHES:
			draw_rect(Rect2(dash[0], dash[1], dash[2], 4), GRAIN)
		draw_rect(Rect2(8, 8, 8, size.y - 16), trim)
		_draw_chip()
		if focused:
			_draw_ticks()

	func _draw_chip() -> void:
		draw_rect(Rect2(24, 24, 72, 80), ink)
		draw_rect(Rect2(28, 28, 64, 72), trim)
		draw_rect(Rect2(32, 32, 56, 64), GRAIN)
		if emblem == "ball":
			draw_rect(Rect2(52, 52, 16, 4), chalk)
			draw_rect(Rect2(48, 56, 24, 16), chalk)
			draw_rect(Rect2(52, 72, 16, 4), chalk)
			draw_rect(Rect2(64, 68, 4, 4), ink)
			draw_rect(Rect2(56, 56, 4, 4), stitch)
			draw_rect(Rect2(60, 64, 4, 4), stitch)
		else:
			draw_rect(Rect2(44, 40, 4, 40), ink)
			draw_rect(Rect2(48, 40, 16, 4), stitch)
			draw_rect(Rect2(48, 44, 12, 4), stitch)
			draw_rect(Rect2(48, 48, 8, 4), stitch)
			draw_rect(Rect2(72, 52, 4, 40), ink)
			draw_rect(Rect2(56, 52, 16, 4), teal)
			draw_rect(Rect2(60, 56, 12, 4), teal)
			draw_rect(Rect2(64, 60, 8, 4), teal)

	func _draw_ticks() -> void:
		draw_rect(Rect2(0, 0, TICK_ARM, TICK_THICK), tick)
		draw_rect(Rect2(0, 0, TICK_THICK, TICK_ARM), tick)
		draw_rect(Rect2(size.x - TICK_ARM, 0, TICK_ARM, TICK_THICK), tick)
		draw_rect(Rect2(size.x - TICK_THICK, 0, TICK_THICK, TICK_ARM), tick)
		draw_rect(Rect2(0, size.y - TICK_THICK, TICK_ARM, TICK_THICK), tick)
		draw_rect(Rect2(0, size.y - TICK_ARM, TICK_THICK, TICK_ARM), tick)
		draw_rect(Rect2(size.x - TICK_ARM, size.y - TICK_THICK, TICK_ARM, TICK_THICK), tick)
		draw_rect(Rect2(size.x - TICK_THICK, size.y - TICK_ARM, TICK_THICK, TICK_ARM), tick)


class LandingPrompt extends Label:
	## Landing-only opaque prompt treatment (bible 5.4/10.6): the shell blink
	## drives this label's modulate alpha; every frame the label converts that
	## signal into an opaque chalk->steel value step over its ink rail plate,
	## so the landing never composites translucent text.

	var lit_color := Color.WHITE
	var dim_color := Color.GRAY

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST

	func _process(_delta: float) -> void:
		var lit := modulate.a > 0.6
		if not is_equal_approx(modulate.a, 1.0):
			modulate.a = 1.0
		add_theme_color_override("font_color", lit_color if lit else dim_color)


class ScoutPlank extends Control:
	## Pitcher-select painted plank (bible 10.1): an opaque board fill inside a
	## square ink frame with a team-trim edge stripe, deterministic authored
	## grain dashes, and a hard offset ink shadow. All marks are whole 4px
	## cells; pass shadow_drop 0 when the plank is a card face.

	var ink := Color.BLACK
	var board := Color.DARK_SLATE_BLUE
	var grain := Color.DIM_GRAY
	var trim := Color.RED
	var shadow_drop := 8

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if shadow_drop > 0:
			draw_rect(Rect2(Vector2(shadow_drop, shadow_drop), size), ink)
		draw_rect(Rect2(Vector2.ZERO, size), ink)
		draw_rect(Rect2(8, 8, size.x - 16, size.y - 16), board)
		draw_rect(Rect2(8, 8, 8, size.y - 16), trim)
		# Deterministic grain: one dash per 24px row, walking a fixed 44px
		# stride so no two neighboring rows repeat (bible 5.1).
		var row := 0
		var y := 24.0
		while y < size.y - 16.0:
			var span := size.x - 88.0
			if span >= 4.0:
				var dash_x := 24.0 + fmod(row * 44.0, span)
				var dash_w := minf(16.0 + (row % 3) * 8.0, size.x - 8.0 - dash_x)
				if dash_w >= 8.0:
					draw_rect(Rect2(dash_x, y, dash_w, 4), grain)
			row += 1
			y += 24.0


class RosterRail extends Control:
	## Pitcher-select roster rail (bible 10.4/10.6): ten painted plank slats
	## keep the full staff physically present inside the left 45%. The focused
	## slat takes the screen's only lantern-gold 4px corner ticks, a 4px lift
	## with a 4px shadow grow, and a one-step value lift; inactive slats stay
	## chalk/steel so the state survives grayscale. Slat name labels are added
	## as children by the build code, one per slat, in roster order.

	const SLAT_STEP := 52
	const SLAT_H := 44
	const SLAT_W := 176
	const TICK_ARM := 12
	const TICK_THICK := 4

	var ink := Color.BLACK
	var board := Color.DARK_SLATE_BLUE
	var raised := Color.SLATE_BLUE
	var grain := Color.DIM_GRAY
	var trim := Color.GRAY
	var tick := Color.YELLOW
	var count := 10
	var focus_index := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		for index in range(count):
			var focused := index == focus_index
			var top := index * SLAT_STEP - (4 if focused else 0)
			var drop := 12 if focused else 8
			draw_rect(Rect2(drop, top + drop, SLAT_W, SLAT_H), ink)
			draw_rect(Rect2(0, top, SLAT_W, SLAT_H), ink)
			draw_rect(Rect2(4, top + 4, SLAT_W - 8, SLAT_H - 8), raised if focused else board)
			draw_rect(Rect2(4, top + 4, 8, SLAT_H - 8), trim)
			draw_rect(Rect2(20 + (index % 3) * 24, top + SLAT_H - 12, 16 + (index % 2) * 8, 4), grain)
			draw_rect(Rect2(96 + (index % 2) * 20, top + 8, 20, 4), grain)
			if focused:
				draw_rect(Rect2(0, top, TICK_ARM, TICK_THICK), tick)
				draw_rect(Rect2(0, top, TICK_THICK, TICK_ARM), tick)
				draw_rect(Rect2(SLAT_W - TICK_ARM, top, TICK_ARM, TICK_THICK), tick)
				draw_rect(Rect2(SLAT_W - TICK_THICK, top, TICK_THICK, TICK_ARM), tick)
				draw_rect(Rect2(0, top + SLAT_H - TICK_THICK, TICK_ARM, TICK_THICK), tick)
				draw_rect(Rect2(0, top + SLAT_H - TICK_ARM, TICK_THICK, TICK_ARM), tick)
				draw_rect(Rect2(SLAT_W - TICK_ARM, top + SLAT_H - TICK_THICK, TICK_ARM, TICK_THICK), tick)
				draw_rect(Rect2(SLAT_W - TICK_THICK, top + SLAT_H - TICK_ARM, TICK_THICK, TICK_ARM), tick)


class PitcherPortraitChip extends Control:
	## Marquee-cue pitcher bust on a plank chip with a team-trim rim (bible
	## 8.1-8.3/10.6): forward-tilted cap with a brim-shadow band, 2x2 ink eyes
	## with single-cell catch-lights, 2-cell brows, chest trim band, and the
	## oversized glove breaking the contour on the glove-hand side. The base
	## map wears the glove on the right hand (viewer left, a lefty); right-
	## handed throwers mirror. Every mark is one opaque 4px cell.

	const BUST := [
		"....................",
		"......iiiiiiii......",
		".....icccccccci.....",
		".....icccccccci.....",
		"...iccccccccccccci..",
		"...iiiiiiiiiiiiiii..",
		".....iSSSSSSSSi.....",
		".....isiissiisi.....",
		".....isiwssiwsi.....",
		".....isiissiisi.....",
		".....issssssssi.....",
		".....isssiisssi.....",
		".....issssssssi.....",
		"......iiiiiiii......",
		"....ijjjjjjjjjji....",
		"..ijjjjjjjjjjjjjji..",
		"iGGGijjjjjjjjjjjji..",
		"iGggijjjjjjjjjjjji..",
		"igggijjjjjjjjjjjji..",
		"igggicccccccccccci..",
		"iiiiicccccccccccci..",
		"....ijjjjjjjjjjjji..",
		"....ijjjjjjjjjjjji..",
		"....ijjjjjjjjjjjji..",
	]

	var ink := Color.BLACK
	var backdrop := Color.DIM_GRAY
	var trim := Color.RED
	var skin := Color.BURLYWOOD
	var skin_shade := Color.SADDLE_BROWN
	var cloth := Color.WHITE
	var glove := Color.SADDLE_BROWN
	var glove_lit := Color.BURLYWOOD
	var white := Color.WHITE
	var throws := "R"

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), ink)
		draw_rect(Rect2(4, 4, size.x - 8, size.y - 8), trim)
		draw_rect(Rect2(8, 8, size.x - 16, size.y - 16), backdrop)
		var flip := throws.to_upper().begins_with("R")
		for row in range(BUST.size()):
			var line: String = BUST[row]
			for col in range(line.length()):
				var ch := line[col]
				if ch == ".":
					continue
				var cell := (19 - col) if flip else col
				draw_rect(Rect2(8 + cell * 4, 8 + row * 4, 4, 4), _cell_color(ch))

	func _cell_color(ch: String) -> Color:
		match ch:
			"c": return trim
			"s": return skin
			"S": return skin_shade
			"j": return cloth
			"g": return glove
			"G": return glove_lit
			"w": return white
		return ink


class ClubPlankCard extends PanelContainer:
	## Team-select club card (bible 10.1/10.6): a pennant-on-plank fixture. The
	## plank keeps the stable ink/board material; the dynamic club color appears
	## only as the bounded pennant flag and edge stripe. Focus is the screen's
	## only lantern-gold corner-tick system plus a 4px lift and a one-step board
	## value change (bible 10.4); P1/CPU picks read as quieter stitch/teal
	## enamel tags, filled versus hollow, so state survives grayscale (11.3).

	const TICK_ARM := 16
	const TICK_THICK := 4

	var ink := Color.BLACK
	var board := Color.DARK_SLATE_BLUE
	var board_lit := Color.SLATE_BLUE
	var grain := Color.DIM_GRAY
	var trim := Color.CYAN
	var tick := Color.YELLOW
	var badge_fill := Color.RED
	var badge_line := Color.CYAN
	var grain_seed := 0
	var focused := false
	var picked_p1 := false
	var picked_cpu := false
	var rest_top := 0.0
	var city_label: Label
	var stats_label: Label

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	func set_state(has_focus: bool, p1: bool, cpu: bool) -> void:
		focused = has_focus
		picked_p1 = p1
		picked_cpu = cpu
		position.y = rest_top - (4.0 if has_focus else 0.0)
		queue_redraw()

	func _draw() -> void:
		var drop := 12.0 if focused else 8.0
		draw_rect(Rect2(Vector2(drop, drop), size), ink)
		draw_rect(Rect2(Vector2.ZERO, size), ink)
		draw_rect(Rect2(4, 4, size.x - 8, size.y - 8), board_lit if focused else board)
		draw_rect(Rect2(4, 4, 4, size.y - 8), trim)
		# Deterministic authored grain so no plank matches its neighbor.
		draw_rect(Rect2(16 + (grain_seed % 3) * 12, size.y - 24, 20, 4), grain)
		draw_rect(Rect2(52 + (grain_seed % 2) * 16, size.y - 12, 16, 4), grain)
		draw_rect(Rect2(56 + (grain_seed % 4) * 8, 28, 12, 4), grain)
		# Club pennant: ink pole with the bounded club-color flag.
		draw_rect(Rect2(12, 8, 4, 24), ink)
		draw_rect(Rect2(16, 8, 32, 4), trim)
		draw_rect(Rect2(16, 12, 24, 4), trim)
		draw_rect(Rect2(16, 16, 16, 4), trim)
		draw_rect(Rect2(16, 20, 8, 4), trim)
		if picked_p1:
			draw_rect(Rect2(72, 8, 44, 24), ink)
			draw_rect(Rect2(76, 12, 36, 16), badge_fill)
		elif picked_cpu:
			draw_rect(Rect2(72, 8, 44, 24), badge_line)
			draw_rect(Rect2(76, 12, 36, 16), ink)
		if focused:
			draw_rect(Rect2(0, 0, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(0, 0, TICK_THICK, TICK_ARM), tick)
			draw_rect(Rect2(size.x - TICK_ARM, 0, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(size.x - TICK_THICK, 0, TICK_THICK, TICK_ARM), tick)
			draw_rect(Rect2(0, size.y - TICK_THICK, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(0, size.y - TICK_ARM, TICK_THICK, TICK_ARM), tick)
			draw_rect(Rect2(size.x - TICK_ARM, size.y - TICK_THICK, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(size.x - TICK_THICK, size.y - TICK_ARM, TICK_THICK, TICK_ARM), tick)


class OptionFixture extends PanelContainer:
	## Team-select difficulty/innings plank control (bible 10.1/10.4): stable
	## board material with a slate trim stripe and authored grain. Focus takes
	## the lantern-gold corner ticks plus the 4px lift, shadow grow, and board
	## value step; caption/value labels are added by the build code.

	const TICK_ARM := 16
	const TICK_THICK := 4

	var ink := Color.BLACK
	var board := Color.DARK_SLATE_BLUE
	var board_lit := Color.SLATE_BLUE
	var grain := Color.DIM_GRAY
	var trim := Color.GRAY
	var tick := Color.YELLOW
	var focused := false
	var rest_top := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	func set_focused(active: bool) -> void:
		focused = active
		position.y = rest_top - (4.0 if active else 0.0)
		queue_redraw()

	func _draw() -> void:
		var drop := 12.0 if focused else 8.0
		draw_rect(Rect2(Vector2(drop, drop), size), ink)
		draw_rect(Rect2(Vector2.ZERO, size), ink)
		draw_rect(Rect2(4, 4, size.x - 8, size.y - 8), board_lit if focused else board)
		draw_rect(Rect2(4, 4, 4, size.y - 8), trim)
		draw_rect(Rect2(124, 16, 20, 4), grain)
		draw_rect(Rect2(16, size.y - 24, 24, 4), grain)
		draw_rect(Rect2(64, size.y - 12, 20, 4), grain)
		if focused:
			draw_rect(Rect2(0, 0, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(0, 0, TICK_THICK, TICK_ARM), tick)
			draw_rect(Rect2(size.x - TICK_ARM, 0, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(size.x - TICK_THICK, 0, TICK_THICK, TICK_ARM), tick)
			draw_rect(Rect2(0, size.y - TICK_THICK, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(0, size.y - TICK_ARM, TICK_THICK, TICK_ARM), tick)
			draw_rect(Rect2(size.x - TICK_ARM, size.y - TICK_THICK, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(size.x - TICK_THICK, size.y - TICK_ARM, TICK_THICK, TICK_ARM), tick)


class MatchupBoard extends Control:
	## Team-select matchup readout fixture (bible 10.1): an enamel lightboard
	## strip — ink face inside a raised bezel with corner rivets and a hard
	## offset ink shadow. The shell matchup label rides the face.

	var ink := Color.BLACK
	var face := Color.BLACK
	var bezel := Color.MIDNIGHT_BLUE
	var rivet := Color.GRAY

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		draw_rect(Rect2(Vector2(8, 8), size), ink)
		draw_rect(Rect2(Vector2.ZERO, size), bezel)
		draw_rect(Rect2(4, 4, size.x - 8, size.y - 8), face)
		for corner in [Vector2(8, 8), Vector2(size.x - 12, 8), Vector2(8, size.y - 12), Vector2(size.x - 12, size.y - 12)]:
			draw_rect(Rect2(corner, Vector2(4, 4)), rivet)


class PlayBallFixture extends Control:
	## The visible team-select Play Ball control (bible 10.1/10.4): an opaque
	## enamel plate. Disabled steps the fill toward ink, drops the shadow, dims
	## the verb to slate, and unlights the teal ready lamp while staying
	## legible; enabled lights the lamp and chalk verb without competing with
	## the single gold focus system. Focus adds the lantern-gold corner ticks
	## and the 4px lift even while disabled, so focus is always visible (11.6).
	## The test-pinned play_ball_panel.modulate.a contract lives on a separate
	## non-drawing panel; this fixture never composites translucency.

	const TICK_ARM := 16
	const TICK_THICK := 4

	var ink := Color.BLACK
	var face := Color.BLACK
	var bezel := Color.MIDNIGHT_BLUE
	var disabled_fill := Color.DARK_SLATE_GRAY
	var rivet := Color.GRAY
	var rivet_off := Color.DIM_GRAY
	var lamp := Color.CYAN
	var tick := Color.YELLOW
	var lit_text := Color.WHITE
	var dim_text := Color.GRAY
	var label: Label
	var enabled := false
	var focused := false
	var rest_top := 0.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_state(can_play: bool, has_focus: bool) -> void:
		enabled = can_play
		focused = has_focus
		position.y = rest_top - (4.0 if has_focus else 0.0)
		if label != null:
			label.add_theme_color_override("font_color", lit_text if can_play else dim_text)
		queue_redraw()

	func _draw() -> void:
		if enabled:
			var drop := 12.0 if focused else 8.0
			draw_rect(Rect2(Vector2(drop, drop), size), ink)
		draw_rect(Rect2(Vector2.ZERO, size), bezel if enabled else ink)
		draw_rect(Rect2(4, 4, size.x - 8, size.y - 8), face if enabled else disabled_fill)
		for corner in [Vector2(8, 8), Vector2(size.x - 12, 8), Vector2(8, size.y - 12), Vector2(size.x - 12, size.y - 12)]:
			draw_rect(Rect2(corner, Vector2(4, 4)), rivet if enabled else rivet_off)
		# Ready lamp: the shape stays put and only its value changes, so the
		# enabled state never reads by hue alone.
		draw_rect(Rect2(12, 64, 20, 20), ink)
		draw_rect(Rect2(16, 68, 12, 12), lamp if enabled else rivet_off)
		if focused:
			draw_rect(Rect2(0, 0, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(0, 0, TICK_THICK, TICK_ARM), tick)
			draw_rect(Rect2(size.x - TICK_ARM, 0, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(size.x - TICK_THICK, 0, TICK_THICK, TICK_ARM), tick)
			draw_rect(Rect2(0, size.y - TICK_THICK, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(0, size.y - TICK_ARM, TICK_THICK, TICK_ARM), tick)
			draw_rect(Rect2(size.x - TICK_ARM, size.y - TICK_THICK, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(size.x - TICK_THICK, size.y - TICK_ARM, TICK_THICK, TICK_ARM), tick)


class FinalNightPanorama extends Control:
	## Final-only night harbor panorama (bible 6.1/10.6): the five harbor bands
	## — sky, skyline+water, grandstand ring, field wall, playfield with a
	## foreground dugout-roof ink band — painted as opaque authored 4px cell
	## clusters from the shared night palette roles passed in by the build
	## code. Every color arrives pre-blended; there is no image, gradient, or
	## alpha wash. The panorama stays subordinate to the result sign: values
	## hold the compressed night rungs and every light pool is small and
	## deliberate. Celebration (bible 9.7) adds at most two stepped fireworks,
	## two authored streamer ribbons, and a one-value-step window pulse, all
	## tick-quantized well under the 3 Hz motion cap.

	const CELL := 4

	var sky_high := Color.BLACK
	var sky_low := Color.BLACK
	var cloud_lit := Color.BLACK
	var cloud_shade := Color.BLACK
	var sea_deep := Color.BLACK
	var sea_mid := Color.BLACK
	var sea_light := Color.BLACK
	var foam := Color.BLACK
	var skyline_far := Color.BLACK
	var skyline_near := Color.BLACK
	var structure := Color.BLACK
	var structure_light := Color.BLACK
	var seat_a := Color.BLACK
	var seat_b := Color.BLACK
	var crowd_shade := Color.BLACK
	var turf := Color.BLACK
	var turf_shadow := Color.BLACK
	var turf_dark := Color.BLACK
	var clay_shadow := Color.BLACK
	var lamp_core := Color.BLACK
	var lamp_glow := Color.BLACK
	var chalk := Color.BLACK
	var ink0 := Color.BLACK
	var gold := Color.BLACK
	var trim_red := Color.BLACK
	var trim_teal := Color.BLACK
	var celebrating := false
	var _time := 0.0
	var _tick := 0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		set_process(false)

	func set_celebration(active: bool) -> void:
		celebrating = active
		set_process(active)
		queue_redraw()

	func _process(delta: float) -> void:
		_time += delta
		# One celebration tick per 0.4 s (2.5 Hz): firework phases advance and
		# the window pulse steps; the frame is fully readable when paused.
		var tick := int(_time / 0.4)
		if tick != _tick:
			_tick = tick
			queue_redraw()

	func _cell(x: int, y: int, w: int, h: int, color: Color) -> void:
		draw_rect(Rect2(x * CELL, y * CELL, w * CELL, h * CELL), color)

	func _draw() -> void:
		_draw_sky()
		_draw_water()
		_draw_skyline()
		_draw_stands()
		_draw_field()
		_cell(0, 166, 320, 14, ink0)
		for i in range(24):
			_cell(i * 13 + (i % 4), 165, 5, 1, ink0)
		for i in range(7):
			_cell(i * 44 + 12, 169, 8, 1, structure)
		if celebrating:
			_draw_firework(36, 22, _tick % 4, trim_teal)
			_draw_firework(272, 28, (_tick + 2) % 4, trim_red)
			_draw_streamer(60, 88, trim_red)
			_draw_streamer(252, 88, trim_teal)

	func _draw_sky() -> void:
		_cell(0, 0, 320, 46, sky_high)
		# Static star field: 34 single accent cells, authored-list exception.
		for i in range(34):
			_cell((i * 67 + 13) % 316, (i * 29 + 3) % 38, 1, 1, foam if i % 7 == 0 else cloud_lit)
		# Stepped moon disc, upper right, feeding the water path below.
		_cell(281, 8, 2, 1, chalk)
		_cell(280, 9, 4, 2, chalk)
		_cell(281, 11, 2, 1, chalk)
		_cell(280, 9, 1, 2, foam)
		# Two cloud masses with lit tops and shaded bellies.
		_cell(20, 26, 22, 3, cloud_shade)
		_cell(26, 24, 12, 2, cloud_shade)
		_cell(28, 23, 8, 1, cloud_lit)
		_cell(22, 25, 4, 1, cloud_lit)
		_cell(252, 18, 26, 3, cloud_shade)
		_cell(258, 16, 12, 2, cloud_shade)
		_cell(260, 15, 8, 1, cloud_lit)
		# Permitted 2x1 checker at the sky_high -> sky_low seam, 2 rows deep.
		for row in range(2):
			for x in range(0, 320, 4):
				_cell(x + row * 2, 44 + row, 2, 1, sky_low)
		_cell(0, 46, 320, 12, sky_low)

	func _draw_water() -> void:
		_cell(0, 58, 320, 14, sea_deep)
		_cell(0, 72, 320, 14, sea_mid)
		# Permitted 2x1 checker at the sea_deep -> sea_mid seam.
		for x in range(0, 320, 4):
			_cell(x, 71, 2, 1, sea_mid)
			_cell(x + 2, 72, 2, 1, sea_deep)

	func _draw_skyline() -> void:
		# Far row: pure silhouette teeth and masts on its own value rung.
		_cell(0, 48, 320, 10, skyline_far)
		for i in range(13):
			var bh := 3 + (i * 5) % 6
			_cell(i * 25 + (i % 3) * 3, 48 - bh, 16 - (i % 3) * 4, bh, skyline_far)
		for i in range(6):
			_cell(i * 51 + 24, 40 + (i % 3) * 2, 1, 8, skyline_far)
		# Near row: continuous wharf front with gabled blocks over the water.
		_cell(0, 54, 320, 12, skyline_near)
		for i in range(10):
			var bh := 3 + (i * 7) % 7
			var bx := i * 33 + (i % 4) * 2
			_cell(bx, 54 - bh, 12 + (i % 3) * 6, bh, skyline_near)
			_cell(bx + 4, 54 - bh - 2, 4, 2, skyline_near)
		# Lighthouse at the right skyline edge, lamp room quietly lit.
		_cell(294, 38, 5, 16, skyline_near)
		_cell(295, 44, 3, 2, foam)
		_cell(294, 36, 5, 2, ink0)
		_cell(295, 34, 3, 2, lamp_glow)
		# Lit windows across the wharf; celebration pulses one value step.
		var pulse := celebrating and _tick % 5 == 0
		for i in range(36):
			_cell(4 + (i * 26 + (i * i) % 7) % 310, 56 + (i * 11) % 8, 1, 1, lamp_core if pulse else lamp_glow)
		# Directional wave grain and the moonlight path, drawn over the wharf
		# base so the chop laps the pilings.
		for i in range(22):
			var wy := 67 + (i * 29) % 17
			_cell((i * 53 + 7) % 314, wy, 2, 1, sea_light if wy >= 74 else sea_mid)
		for i in range(7):
			_cell(274 + ((i * 5) % 3) * 4, 66 + i * 3, 2, 1, foam if i % 3 == 0 else sea_light)

	func _draw_stands() -> void:
		_cell(0, 86, 320, 32, structure)
		for i in range(13):
			_cell(8 + i * 24, 87, 6, 1, trim_red if i % 2 == 0 else trim_teal)
		_cell(0, 89, 320, 1, ink0)
		for row in range(6):
			_cell(0, 92 + row * 2, 320, 1, seat_a if row % 2 == 0 else seat_b)
		for i in range(32):
			_cell(2 + i * 10, 90, 1, 14, structure)
		# Sparse crowd clumps silhouetted over the under-deck dark band.
		for i in range(38):
			var ch := 2 + (i * 3) % 3
			_cell((i * 17 + (i % 5) * 3) % 314, 104 - ch, 4 + (i % 3) * 2, ch, crowd_shade)
		_cell(0, 104, 320, 14, crowd_shade)
		# Two lit lamp towers on the flanks with stepped pre-blended halos.
		for tower_x in [40, 280]:
			_cell(tower_x - 7, 55, 16, 10, lamp_glow.lerp(skyline_near, 0.75))
			_cell(tower_x - 5, 57, 12, 6, lamp_glow.lerp(skyline_near, 0.5))
			_cell(tower_x - 5, 58, 12, 4, ink0)
			for head in range(3):
				_cell(tower_x - 4 + head * 4, 59, 3, 2, lamp_core)
			_cell(tower_x - 5, 62, 12, 2, structure_light)
			_cell(tower_x, 64, 2, 22, structure_light)

	func _draw_field() -> void:
		# Outfield wall band with a lit top rail and distance markers.
		_cell(0, 118, 320, 6, skyline_near)
		_cell(0, 118, 320, 1, structure_light)
		_cell(0, 123, 320, 1, ink0)
		_cell(56, 120, 6, 2, sea_light)
		_cell(262, 120, 6, 2, sea_light)
		# Night playfield: dark base, warning-track seam, drifting mow bands.
		_cell(0, 124, 320, 42, turf_dark)
		_cell(0, 124, 320, 2, clay_shadow)
		for band in range(3):
			var y := 130 + band * 12
			_cell(0, y, 320, 8, turf_shadow)
			for i in range(11):
				_cell(i * 29 + band * 7, y - 1, 6, 1, turf_shadow)
				_cell(i * 29 + 14 + band * 5, y + 8, 6, 1, turf_shadow)
		# The field lifts inside two stepped lamp pools under the towers.
		for pool_x in [40, 280]:
			var widths := [12, 20, 26, 28, 26, 20, 12]
			for r in range(widths.size()):
				_cell(pool_x - widths[r] / 2, 134 + r * 2, widths[r], 2, turf_shadow)
			var inner := [10, 16, 18, 16, 10]
			for r in range(inner.size()):
				_cell(pool_x - inner[r] / 2, 136 + r * 2, inner[r], 2, turf)

	func _draw_firework(cx: int, cy: int, phase: int, tone: Color) -> void:
		# Stepped 8-spoke burst (bible 9.7): bloom, spokes, tips, dark — four
		# ticks; the two bursts run offset so at most two are ever alive.
		match phase:
			0:
				_cell(cx - 1, cy - 1, 2, 2, gold)
			1:
				_cell(cx, cy, 1, 1, lamp_core)
				_cell(cx - 3, cy, 2, 1, gold)
				_cell(cx + 2, cy, 2, 1, gold)
				_cell(cx, cy - 3, 1, 2, gold)
				_cell(cx, cy + 2, 1, 2, gold)
				_cell(cx - 2, cy - 2, 1, 1, tone)
				_cell(cx + 2, cy - 2, 1, 1, tone)
				_cell(cx - 2, cy + 2, 1, 1, tone)
				_cell(cx + 2, cy + 2, 1, 1, tone)
			2:
				_cell(cx - 4, cy, 1, 1, tone)
				_cell(cx + 4, cy, 1, 1, tone)
				_cell(cx, cy - 4, 1, 1, tone)
				_cell(cx, cy + 4, 1, 1, tone)
				_cell(cx - 3, cy - 3, 1, 1, tone)
				_cell(cx + 3, cy - 3, 1, 1, tone)
				_cell(cx - 3, cy + 3, 1, 1, tone)
				_cell(cx + 3, cy + 3, 1, 1, tone)

	func _draw_streamer(x: int, y: int, tone: Color) -> void:
		# One authored 6-cell team-trim ribbon hung from the upper deck.
		_cell(x, y, 1, 2, tone)
		_cell(x + 1, y + 2, 1, 2, tone)
		_cell(x, y + 4, 1, 2, tone)


class FinalResultSign extends Control:
	## Final result signage (bible 10.1/10.6): one dominant enamel lightboard
	## rope-hung from the top frame with a hard 16px offset ink shadow, raised
	## bezel, corner rivets, and seam rows breaking the enamel field. A win or
	## new best re-grades the fixture into the screen's single warm pool: a
	## gold header band and two lit cage lamps whose stepped halos pre-blend
	## toward the face color — never alpha. A loss keeps the board cool with
	## the cage lamps as unlit metal. All marks are opaque whole 4px cells.

	var ink := Color.BLACK
	var face := Color.BLACK
	var bezel := Color.MIDNIGHT_BLUE
	var rivet := Color.GRAY
	var rope := Color.SADDLE_BROWN
	var rope_lit := Color.BURLYWOOD
	var glow := Color.LIGHT_YELLOW
	var gold := Color.YELLOW
	var celebrating := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func set_celebration(active: bool) -> void:
		celebrating = active
		queue_redraw()

	func _draw() -> void:
		for rope_x in [128, 560]:
			draw_rect(Rect2(rope_x, 0, 4, 72), rope)
			draw_rect(Rect2(rope_x, 12, 4, 4), rope_lit)
			draw_rect(Rect2(rope_x, 40, 4, 4), rope_lit)
			draw_rect(Rect2(rope_x - 4, 60, 12, 12), rope)
			draw_rect(Rect2(rope_x - 4, 60, 4, 4), rope_lit)
		draw_rect(Rect2(16, 88, 704, 296), ink)
		draw_rect(Rect2(0, 72, 704, 296), ink)
		draw_rect(Rect2(4, 76, 696, 288), bezel)
		draw_rect(Rect2(8, 80, 688, 280), face)
		var seam := face.lerp(bezel, 0.6)
		draw_rect(Rect2(16, 216, 672, 4), seam)
		draw_rect(Rect2(16, 312, 672, 4), seam)
		for corner in [Vector2(12, 84), Vector2(684, 84), Vector2(12, 352), Vector2(684, 352)]:
			draw_rect(Rect2(corner, Vector2(4, 4)), rivet)
		if celebrating:
			draw_rect(Rect2(8, 80, 688, 8), gold)
			_draw_cage_lamp(24, 100)
			_draw_cage_lamp(652, 100)
		else:
			_draw_dead_lamp(24, 100)
			_draw_dead_lamp(652, 100)

	func _draw_cage_lamp(x: int, y: int) -> void:
		draw_rect(Rect2(x - 8, y - 8, 44, 40), gold.lerp(face, 0.78))
		draw_rect(Rect2(x - 4, y - 4, 36, 32), gold.lerp(face, 0.55))
		draw_rect(Rect2(x + 12, y - 12, 4, 4), ink)
		draw_rect(Rect2(x, y, 28, 24), ink)
		draw_rect(Rect2(x + 4, y + 4, 20, 16), glow)
		draw_rect(Rect2(x + 8, y + 4, 4, 16), ink)
		draw_rect(Rect2(x + 16, y + 4, 4, 16), ink)

	func _draw_dead_lamp(x: int, y: int) -> void:
		draw_rect(Rect2(x + 12, y - 12, 4, 4), ink)
		draw_rect(Rect2(x, y, 28, 24), ink)
		draw_rect(Rect2(x + 4, y + 4, 20, 16), rivet)
		draw_rect(Rect2(x + 8, y + 4, 4, 16), ink)
		draw_rect(Rect2(x + 16, y + 4, 4, 16), ink)


class FinalActionFixture extends PanelContainer:
	## Final-screen REMATCH/EXIT plank (bible 10.1/10.4): an opaque painted
	## plank with authored grain, a hard 8px ink shadow growing 4px with the
	## 4px focus lift, and lantern-gold corner ticks on the single focused
	## action. The legacy shell blink still writes modulate.a from the HUD
	## _process; every frame this fixture converts that signal into an opaque
	## one-step board value pulse and restores full opacity, so the final
	## never composites translucent signage.

	const TICK_ARM := 16
	const TICK_THICK := 4

	var ink := Color.BLACK
	var board := Color.DARK_SLATE_BLUE
	var board_lit := Color.SLATE_BLUE
	var grain := Color.DIM_GRAY
	var trim := Color.RED
	var tick := Color.YELLOW
	var grain_seed := 0
	var focused := false
	var rest_top := 0.0
	var _blink_dim := false

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())

	func set_focused(active: bool) -> void:
		focused = active
		position.y = rest_top - (4.0 if active else 0.0)
		queue_redraw()

	func _process(_delta: float) -> void:
		var dimmed := modulate.a < 0.8
		if not is_equal_approx(modulate.a, 1.0):
			modulate.a = 1.0
		if dimmed != _blink_dim:
			_blink_dim = dimmed
			queue_redraw()

	func _draw() -> void:
		var drop := 12.0 if focused else 8.0
		draw_rect(Rect2(Vector2(drop, drop), size), ink)
		draw_rect(Rect2(Vector2.ZERO, size), ink)
		draw_rect(Rect2(4, 4, size.x - 8, size.y - 8), board_lit if focused and not _blink_dim else board)
		draw_rect(Rect2(4, 4, 4, size.y - 8), trim)
		draw_rect(Rect2(16 + (grain_seed % 3) * 20, size.y - 12, 24, 4), grain)
		draw_rect(Rect2(size.x - 60 + (grain_seed % 2) * 12, 8, 20, 4), grain)
		if focused:
			draw_rect(Rect2(0, 0, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(0, 0, TICK_THICK, TICK_ARM), tick)
			draw_rect(Rect2(size.x - TICK_ARM, 0, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(size.x - TICK_THICK, 0, TICK_THICK, TICK_ARM), tick)
			draw_rect(Rect2(0, size.y - TICK_THICK, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(0, size.y - TICK_ARM, TICK_THICK, TICK_ARM), tick)
			draw_rect(Rect2(size.x - TICK_ARM, size.y - TICK_THICK, TICK_ARM, TICK_THICK), tick)
			draw_rect(Rect2(size.x - TICK_THICK, size.y - TICK_ARM, TICK_THICK, TICK_ARM), tick)
