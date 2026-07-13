extends SceneTree

const ShellModel = preload("res://ui/pixiball_shell_model.gd")
const SaveRepository = preload("res://ui/pixiball_save_repository.gd")
const Catalog = preload("res://core/content/content_catalog.gd")
const HUD = preload("res://ui/pixiball_hud.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_shell_state()
	_test_save_repository()
	await _test_hud_contract()
	if failures.is_empty():
		print("PIXIBALL_SHELL_SAVE_OK screens=5 pitchers=10 teams=8")
		quit(0)
	else:
		for failure in failures:
			push_error("PIXIBALL_SHELL_SAVE: %s" % failure)
		quit(1)


func _test_shell_state() -> void:
	var shell := ShellModel.new()
	_check(shell.screen == "landing" and shell.landing_focus == 0, "shell must boot on focused Endless card")
	_check(is_equal_approx(shell.difficulty_value(), 0.50), "Pro must use frozen simulation difficulty 0.50")
	_check(is_equal_approx(float(ShellModel.DIFFICULTIES[0].value), 0.25) and is_equal_approx(float(ShellModel.DIFFICULTIES[2].value), 0.80), "Rookie/All-Star must pin frozen 0.25/0.80 values")
	shell.navigate(1, 0)
	_check(shell.landing_focus == 1, "landing navigation must focus Versus")
	_check(String(shell.confirm().command) == "open_teams", "Versus confirm must open Team Select")
	_check(not shell.can_play(), "Play Ball must start disabled")
	shell.team_focus = 1
	shell.navigate(0, 1)
	_check(shell.team_focus == 5, "team grid down navigation must move to the second row")
	shell.navigate(0, -1)
	_check(shell.team_focus == 1, "team grid up navigation must return to the first row")
	shell.team_focus = 2
	shell.confirm()
	_check(shell.player_team_index == 2 and shell.cpu_team_index == -1, "first team pick must belong to P1")
	shell.team_focus = 2
	shell.confirm()
	_check(shell.cpu_team_index == -1, "CPU pick must reject the P1 club")
	shell.team_focus = 6
	shell.confirm()
	_check(shell.cpu_team_index == 6 and shell.can_play(), "distinct CPU club must unlock Play Ball")
	shell.team_focus = 8
	var prior_difficulty := shell.difficulty_name()
	shell.cycle_option(1)
	_check(shell.difficulty_name() != prior_difficulty, "left/right must cycle difficulty")
	shell.team_focus = 9
	shell.cycle_option(1)
	_check(shell.innings_value() == 6, "left/right must cycle innings 3/6/9")
	shell.team_focus = 10
	var start: Dictionary = shell.confirm()
	_check(String(start.command) == "start_versus" and int(start.player_team_index) == 2 and int(start.cpu_team_index) == 6, "valid Play Ball must emit deterministic matchup")
	shell.show_pitchers(9)
	shell.navigate(1, 0)
	_check(shell.pitcher_index == 0, "pitcher grid navigation must wrap all ten cards")
	_check(String(shell.confirm().command) == "start_endless", "pitcher confirm must emit Endless start")
	shell.show_final()
	_check(String(shell.confirm().command) == "rematch", "Final must focus Rematch first")
	shell.navigate(1, 0)
	_check(String(shell.confirm().command) == "exit_to_menu", "Final second action must exit to menu")


func _test_save_repository() -> void:
	var test_path := "user://pixiball_shell_test_%d.cfg" % OS.get_process_id()
	var absolute := ProjectSettings.globalize_path(test_path)
	DirAccess.remove_absolute(absolute)
	var repository := SaveRepository.new(test_path)
	var defaults: Dictionary = repository.load_profile()
	_check(int(defaults.best_endless_strikeouts) == 0 and int(defaults.versus_wins) == 0, "missing save must use safe defaults")
	var first: Dictionary = repository.record_endless(7)
	_check(bool(first.new_best) and int(first.best_endless_strikeouts) == 7, "higher Endless score must persist as a new best")
	var second: Dictionary = repository.record_endless(4)
	_check(not bool(second.new_best) and int(second.best_endless_strikeouts) == 7, "lower Endless score must not replace best")
	repository.record_versus(true)
	repository.record_versus(false)
	var reloaded := SaveRepository.new(test_path)
	var persisted: Dictionary = reloaded.load_profile()
	_check(int(persisted.best_endless_strikeouts) == 7 and int(persisted.versus_wins) == 1 and int(persisted.versus_losses) == 1, "versioned save must round-trip all records")
	var corrupt := ConfigFile.new()
	corrupt.set_value("profile", "version", SaveRepository.CURRENT_VERSION)
	corrupt.set_value("records", "best_endless_strikeouts", "not-a-number")
	corrupt.set_value("records", "versus_wins", INF)
	corrupt.set_value("records", "versus_losses", -99)
	corrupt.save(test_path)
	var recovered := SaveRepository.new(test_path)
	var safe: Dictionary = recovered.load_profile()
	_check(int(safe.best_endless_strikeouts) == 0 and int(safe.versus_wins) == 0 and int(safe.versus_losses) == 0, "corrupt counters must recover independently to safe defaults")
	DirAccess.remove_absolute(absolute)


func _test_hud_contract() -> void:
	var catalog := Catalog.new()
	_check(catalog.load_all(), "catalog must load for shell HUD test")
	var hud := HUD.new()
	root.add_child(hud)
	await process_frame
	hud.show_landing({"best_endless_strikeouts": 12, "versus_wins": 3, "versus_losses": 2}, 1)
	_check(hud.landing_layer.visible and not hud.pitcher_layer.visible, "Landing must be a dedicated visible shell layer")
	var harbor_backdrop := hud.landing_layer.get_node_or_null("HarborBackdrop") as TextureRect
	_check(harbor_backdrop != null and harbor_backdrop.texture != null, "Landing must paint the shared production harbor panorama")
	_check(hud.landing_layer.has_node("PixelAtmosphere"), "Landing must retain the deterministic pixel-atmosphere overlay")
	_check(hud.game_layer.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "Native game HUD must preserve crisp nearest-filtered pixel chrome")
	_check("12 K" in hud.landing_stat_lines[0].text and "3–2" in hud.landing_stat_lines[1].text, "Landing mode cards must display saved records")
	_check("PRESS START" in hud.landing_prompt.text, "Landing must retain the reference insert-coin footer")
	_check((hud.landing_card_ctas[1].get_theme_stylebox("panel") as StyleBoxFlat).bg_color == Color("e64539"), "Landing CTA stitch must follow focused mode")
	hud.set_batting_layout(true)
	_check(not hud.pitch_row.visible, "batting HUD must hide the pitching selector")
	var projected_zone := Rect2(548, 224, 184, 272)
	hud.set_strike_zone_rect(projected_zone)
	_check(hud.strike_zone.position == projected_zone.position and hud.strike_zone.size == projected_zone.size, "HUD must accept the camera-projected strike zone rectangle")
	hud.set_batting_layout(false)
	_check(hud.strike_zone.size == projected_zone.size, "layout changes must not replace physical camera projection with a fake zone size")
	hud.push_event("previous play")
	_check(hud.event_feed_back.visible and hud.event_feed.visible, "event feed must remain visible outside pitch selection")
	hud.set_pitch_selector(true, 0)
	_check(not hud.event_feed_back.visible and not hud.event_feed.visible, "pitch selector must suppress overlapping event messages")
	hud.set_pitch_selector(false)
	_check(hud.event_feed_back.visible and hud.event_feed.visible, "event feed must return after pitch selection")
	hud.clear_events()
	_check(not hud.event_feed_back.visible and not hud.event_feed.visible, "clearing events must hide the event feed")
	hud.show_pitcher_select(catalog.pitchers, 9)
	_check(hud.pitcher_cards.size() == 10 and hud.pitcher_layer.visible, "Pitcher Select must render all ten cards")
	var metrics: Dictionary = HUD.derive_pitcher_metrics(catalog.pitchers[0])
	_check(int(metrics.ovr) >= 60 and float(metrics.era) > 0.0 and float(metrics.k9) > 0.0 and float(metrics.stamina) >= 0.58, "pitcher detail metrics must be derived and bounded")
	var shell := ShellModel.new()
	shell.show_teams()
	hud.show_team_select(catalog.teams, shell.snapshot())
	_check(hud.team_cards.size() == 8 and hud.play_ball_panel.modulate.a == 0.5, "Team Select must render eight clubs and dim invalid Play Ball")
	hud.show_final("versus", {"winner": "home", "innings": 3, "score": {"home": 2, "away": 1}, "hits": {"home": 4, "away": 3}, "line_score": {"home": [2], "away": [1, 0, 0]}}, {"versus_wins": 1, "versus_losses": 0}, false, 0)
	_check("—" in hud.final_stats.text, "Final line score must mark skipped innings with an em dash")
	_check(_count_buttons(hud) == 0, "shell must not depend on mouse Button controls")
	hud.queue_free()
	await process_frame


func _count_buttons(node: Node) -> int:
	var count := 1 if node is BaseButton else 0
	for child in node.get_children():
		count += _count_buttons(child)
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
