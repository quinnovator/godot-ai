extends SceneTree

const MAIN_SCENE := preload("res://main.tscn")
const NATIVE_SIZE := Vector2i(2560, 1440)
const NATIVE_CANVAS := Rect2(Vector2.ZERO, Vector2(NATIVE_SIZE))
const EPSILON := 0.001

var _failures: Array[String] = []
var _visible_controls_checked := 0


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_project_contract()
	var game: Node = MAIN_SCENE.instantiate()
	root.add_child(game)
	for unused in range(3):
		await process_frame

	var hud := game.get_node_or_null("PixiballHUD") as PixiballHUD
	_check(hud != null, "main scene must own PixiballHUD")
	if hud == null:
		_finish(game, 0)
		return
	_check_art_roots(game, hud)

	var states_checked := 0
	hud.show_landing({"best_endless_strikeouts": 12, "versus_wins": 3, "versus_losses": 2}, 0)
	await process_frame
	_check_shell_state(hud.landing_layer, "landing")
	states_checked += 1

	var pitchers: Array[Dictionary] = []
	var teams: Array[Dictionary] = []
	var catalog: Variant = game.get("content_catalog")
	if catalog != null:
		for pitcher_value in catalog.pitchers:
			pitchers.append(pitcher_value as Dictionary)
		for team_value in catalog.teams:
			teams.append(team_value as Dictionary)
	_check(pitchers.size() >= 10, "native pitcher screen requires the ten-card catalog")
	_check(teams.size() >= 8, "native team screen requires the eight-club catalog")

	hud.show_pitcher_select(pitchers, 4)
	await process_frame
	_check_shell_state(hud.pitcher_layer, "pitcher")
	for index in range(hud.pitcher_card_labels.size()):
		var card_label := hud.pitcher_card_labels[index]
		_check(card_label.size.is_equal_approx(Vector2(448, 280)), "pitcher card %d label must own a native 448x280 content rect, got %s" % [index, card_label.size])
		_check(not card_label.text.is_empty(), "pitcher card %d must render its starter name" % index)
	states_checked += 1

	hud.show_team_select(teams, {
		"team_focus": 6,
		"player_team_index": 1,
		"cpu_team_index": 6,
		"difficulty_name": "PRO",
		"innings": 3,
		"can_play": true,
	})
	await process_frame
	_check_shell_state(hud.team_layer, "team")
	states_checked += 1

	hud.show_game()
	hud.set_batting_layout(false)
	hud.set_pitch_selector(true, 2)
	hud.set_help("1-5 SELECT / WASD AIM / SPACE THROW")
	hud.set_strike_zone_rect(Rect2(968, 496, 624, 576))
	hud.update_state({
		"away_score": 2,
		"home_score": 1,
		"inning": 3,
		"top": false,
		"balls": 3,
		"strikes": 2,
		"outs": 2,
		"bases": [true, false, true],
		"phase_label": "YOU'RE PITCHING",
		"pitcher_name": "RIVER VALE",
		"pitcher_throws": "R",
	})
	hud.set_stamina(0.41, "tiring")
	await process_frame
	_check_visible_controls(hud.game_layer, "game")
	_check(hud.help_panel.get_global_rect().end.y <= hud.pitch_row.get_global_rect().position.y, "help band must end above the pitch-selector cards")
	_check(hud.help_panel.position.is_equal_approx(Vector2(32, 1192)) and hud.help_panel.size.y <= 64.0, "help band must use the native y=1192 band, got position=%s size=%s" % [hud.help_panel.position, hud.help_panel.size])
	_check(hud.field_meter.position.is_equal_approx(Vector2(840, 1208)) and is_equal_approx(hud.field_meter.size.x, 880.0), "field meter placement must retain its dense-grid placement, got position=%s size=%s" % [hud.field_meter.position, hud.field_meter.size])
	hud.set_field_meter(true, 0.5)
	_check(hud.field_meter.visible and is_equal_approx(hud.field_meter.value, 0.5), "field meter must retain its visibility and value behavior")
	hud.set_field_meter(false)
	_check_native_typography(hud)
	states_checked += 1

	hud.show_final("versus", {
		"winner": "home",
		"innings": 3,
		"score": {"home": 4, "away": 3},
		"hits": {"home": 7, "away": 5},
		"line_score": {"home": [1, 1, 2], "away": [0, 2, 1]},
	}, {"versus_wins": 4, "versus_losses": 2}, false, 0)
	await process_frame
	_check_shell_state(hud.final_layer, "final")
	states_checked += 1

	var intel := game.get_node_or_null("PitchIntelLayer/PitchIntelPanel") as PixiballPitchIntelPanel
	_check(intel != null, "main scene must own the reusable Pitch Intel card")
	if intel != null:
		var minimum := intel.get_combined_minimum_size()
		_check(minimum.x <= 384.0 and minimum.y <= 432.0, "Pitch Intel minimum exceeds 384x432: %s" % minimum)
		_check(intel.size.x <= 384.0 and intel.size.y <= 432.0, "Pitch Intel instance exceeds 384x432: %s" % intel.size)
		intel.present({
			"code": "SL",
			"name": "Slider",
			"velocity_mph": 87.6,
			"erv": -0.084,
			"erv_actual": -0.112,
			"sequence": {"tunnel_in": 2.1, "plate_sep_in": 8.4, "ratio": 4.0},
			"options": [{"rank": 1, "code": "CH", "erv": -0.128}],
		})
		await process_frame
		_check_visible_controls(intel, "pitch-intel")
		_check(intel.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Pitch Intel art root must use nearest filtering")
		intel.clear()

	_finish(game, states_checked)


func _check_project_contract() -> void:
	var width := int(ProjectSettings.get_setting("display/window/size/viewport_width", 0))
	var height := int(ProjectSettings.get_setting("display/window/size/viewport_height", 0))
	_check(Vector2i(width, height) == NATIVE_SIZE, "project framebuffer must be native 2560x1440, got %dx%d" % [width, height])
	_check(String(ProjectSettings.get_setting("display/window/stretch/mode", "")) == "viewport", "native UI requires viewport stretch mode")
	_check(String(ProjectSettings.get_setting("display/window/stretch/scale_mode", "")) == "integer", "native UI requires integer stretch scaling")


func _check_art_roots(game: Node, hud: PixiballHUD) -> void:
	var pixel_scene := game.get_node_or_null("PixelScene") as CanvasItem
	_check(pixel_scene != null, "main scene must expose the native PixelScene art root")
	if pixel_scene != null:
		_check(pixel_scene.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "PixelScene must force nearest filtering")
	_check(hud.title_layer.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "shell art root must force nearest filtering")
	_check(hud.game_layer.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "game HUD art root must force nearest filtering")


func _check_shell_state(active_screen: Control, context: String) -> void:
	_check(active_screen != null and active_screen.is_visible_in_tree(), "%s shell screen must be active" % context)
	if active_screen == null:
		return
	_check_visible_controls(active_screen, context)
	_check_no_photo_or_gradient(active_screen, context)


func _check_visible_controls(node: Node, context: String) -> void:
	if node is Control:
		var control := node as Control
		if control.is_visible_in_tree():
			_visible_controls_checked += 1
			var rect := control.get_global_rect()
			_check(_rect_inside_canvas(rect), "%s/%s leaves the 2560x1440 canvas: %s" % [context, control.name, rect])
			_check(_rect_is_integer(rect), "%s/%s uses fractional layout coordinates: %s" % [context, control.name, rect])
			_check(control.scale.is_equal_approx(Vector2.ONE), "%s/%s must not use a Control scale: %s" % [context, control.name, control.scale])
	for child in node.get_children():
		_check_visible_controls(child, context)


func _check_no_photo_or_gradient(node: Node, context: String) -> void:
	for property_info in node.get_property_list():
		var usage := int(property_info.get("usage", 0))
		if (usage & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var property_name := StringName(property_info.get("name", ""))
		if property_name.is_empty():
			continue
		var resource_value: Variant = node.get(property_name)
		_check(
			not (resource_value is GradientTexture1D) and not (resource_value is GradientTexture2D),
			"%s/%s.%s must not use a GradientTexture" % [context, node.name, property_name],
		)
	if node is TextureRect:
		var texture_rect := node as TextureRect
		var texture := texture_rect.texture
		if texture != null:
			# A generated 1x1 solid fill is equivalent to a ColorRect. Imported or
			# nontrivial images would reintroduce the removed painterly backdrop.
			var image_backed := not texture.resource_path.is_empty() or texture.get_width() > 1 or texture.get_height() > 1
			_check(not image_backed, "%s/%s must not use a photo/image TextureRect" % [context, texture_rect.name])
			_check(not (texture is GradientTexture1D) and not (texture is GradientTexture2D), "%s/%s must not use a GradientTexture" % [context, texture_rect.name])
	for child in node.get_children():
		_check_no_photo_or_gradient(child, context)


func _rect_inside_canvas(rect: Rect2) -> bool:
	return (
		rect.position.x >= -EPSILON
		and rect.position.y >= -EPSILON
		and rect.end.x <= NATIVE_CANVAS.end.x + EPSILON
		and rect.end.y <= NATIVE_CANVAS.end.y + EPSILON
	)


func _check_native_typography(hud: PixiballHUD) -> void:
	_check(hud.score_label.get_theme_font_size("font_size") == 72, "scoreboard digits must rasterize natively at 72px")
	_check(hud.phase_label.get_theme_font_size("font_size") == 32, "game phase label must rasterize natively at 32px")
	_check(hud.phase_label.position.is_equal_approx(Vector2(1680, 16)) and hud.phase_label.size.is_equal_approx(Vector2(528, 72)), "phase label must occupy the native scoreboard gap")
	_check(not hud.phase_label.get_global_rect().intersects(hud.out_lamps[-1].get_global_rect()), "phase label must clear the final out lamp")
	_check(not hud.phase_label.get_global_rect().intersects(hud.bases[0].get_global_rect()), "phase label must clear the first base lamp")
	_check(hud.landing_prompt.get_theme_font_size("font_size") == 56, "landing prompt must rasterize natively at 56px")
	_check(_on_four_pixel_grid(hud.score_label.position) and _on_four_pixel_grid(hud.score_label.size), "scoreboard geometry must use the native 4px grid")
	_check(_on_four_pixel_grid(hud.pitch_row.position) and _on_four_pixel_grid(hud.pitch_row.size), "pitch-selector focus geometry must use the native 4px grid")


func _on_four_pixel_grid(value: Vector2) -> bool:
	return is_zero_approx(fmod(value.x, 4.0)) and is_zero_approx(fmod(value.y, 4.0))


func _rect_is_integer(rect: Rect2) -> bool:
	return (
		_is_integer(rect.position.x)
		and _is_integer(rect.position.y)
		and _is_integer(rect.size.x)
		and _is_integer(rect.size.y)
	)


func _is_integer(value: float) -> bool:
	return absf(value - roundf(value)) <= EPSILON


func _finish(game: Node, states_checked: int) -> void:
	var exit_code := 0
	if _failures.is_empty():
		print("PIXIBALL_NATIVE_2D_LAYOUT_OK states=%d controls=%d canvas=2560x1440 intel=768x864" % [states_checked, _visible_controls_checked])
	else:
		for failure in _failures:
			push_error("PIXIBALL_NATIVE_2D_LAYOUT: %s" % failure)
		exit_code = 1
	game.queue_free()
	for unused in range(3):
		await process_frame
	quit(exit_code)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
