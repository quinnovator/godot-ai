extends SceneTree

## GPU-backed visual QA for the pixel-art rebuild.
##
## Run without --headless so the native 2560x1440 framebuffer is read back:
##   godot --path games/pixiball --script res://tools/capture_visual_rebuild.gd \
##     -- --screen=game-batting-golden \
##     --output=res://.godot/visual-qa/game-batting-golden.png

const MAIN_SCENE := preload("res://main.tscn")
const SCREENS := [
	"landing", "pitcher", "team",
	# Original gameplay names remain pitching-view aliases.
	"game-day", "game-golden", "game-night",
	"game-pitching-day", "game-pitching-golden", "game-pitching-night",
	"game-batting-day", "game-batting-golden", "game-batting-night",
	"game-fielding-day", "game-fielding-golden", "game-fielding-night",
	"game-dugout-day", "game-dugout-golden", "game-dugout-night",
	"final",
]


func _initialize() -> void:
	call_deferred("_capture")


func _capture() -> void:
	var options := _options()
	var screen := String(options.get("screen", "landing"))
	if screen not in SCREENS:
		push_error("Unknown visual QA screen '%s'. Expected one of %s." % [screen, SCREENS])
		quit(2)
		return
	var output := String(options.get("output", "res://.godot/visual-qa/%s.png" % screen))
	root.size = Vector2i(2560, 1440)
	var game := MAIN_SCENE.instantiate()
	root.add_child(game)
	for unused in range(8):
		await process_frame
	var pixel_scene := game.get_node_or_null("PixelScene") as Node2D
	if pixel_scene == null or pixel_scene.scale != Vector2(4, 4):
		push_error("Visual QA requires a direct 4x PixelScene in the native root framebuffer.")
		quit(7)
		return
	var nested_viewport := _find_subviewport(game)
	if nested_viewport != null:
		push_error("Visual QA refuses an intermediate SubViewport at %s." % nested_viewport.get_path())
		quit(8)
		return

	match screen:
		"pitcher":
			game._show_pitcher_select()
		"team":
			game._show_team_select()
		"final":
			game.hud.show_final("versus", {
				"away_name": "HARBOR FOXES",
				"home_name": "PIER LIGHTS",
				"away_runs": 4,
				"home_runs": 5,
			}, {"hits": 9, "strikeouts": 8, "walks": 2}, true, 0)
		_:
			if screen.begins_with("game-"):
				_configure_gameplay_capture(game, screen)

	# Let fonts and the native pixel presenters settle before frame readback.
	for unused in range(120):
		await process_frame
	_hide_transient_banner(game, screen)
	# A process frame can finish before the render thread uploads late font
	# glyphs and viewport textures. Reading after two completed draw frames keeps
	# the QA capture deterministic across sequential GPU-backed runs.
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var image := root.get_viewport().get_texture().get_image()
	if image == null or image.is_empty():
		push_error("Visual QA viewport did not produce an image. Run without --headless.")
		quit(3)
		return
	if image.get_size() != Vector2i(2560, 1440):
		push_error("Visual QA must capture the native 2560x1440 framebuffer, got %s." % image.get_size())
		quit(6)
		return
	var absolute := ProjectSettings.globalize_path(output)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if directory_error != OK:
		push_error("Could not create visual QA directory: %s" % error_string(directory_error))
		quit(4)
		return
	var save_error := image.save_png(absolute)
	if save_error != OK:
		push_error("Could not save visual QA image: %s" % error_string(save_error))
		quit(5)
		return
	print("PIXIBALL_VISUAL_QA_OK screen=%s path=%s size=%dx%d" % [screen, output, image.get_width(), image.get_height()])
	quit()


func _configure_gameplay_capture(game: Node, screen: String) -> void:
	var spec := _gameplay_capture_spec(screen)
	var view := String(spec.get("view", "pitching"))
	var mood := String(spec.get("mood", "day"))
	game._start_match(4242, 1, 0.72)
	game._mood_index = ["day", "golden", "night"].find(mood)
	game._set_visual_mood(mood)

	match view:
		"batting":
			# This owns catcher/umpire visibility and the batting HUD layout. Set
			# the camera again explicitly so the capture contract is unambiguous.
			game._set_gameplay_view(true)
			game.broadcast_camera.set_mode("batting")
		"fielding":
			var outfield_focus := Vector3(14.0, 2.2, -25.0)
			game.ball.set_active(true)
			game.ball.use_play_ball()
			game.ball.set_ball_position(outfield_focus)
			game.broadcast_camera.set_mode("fielding", game.ball)
			game.stadium.set_field_focus(outfield_focus)
			game.hud.set_strike_zone_visible(false)
			# The camera is forced into live fielding without advancing the sim, so
			# explicitly remove the ready/pitch-selector HUD left by _start_match().
			game.hud.set_pitch_selector(false)
			game.hud.set_help("")
			game.hud.phase_label.text = "LIVE BALL"
		"dugout":
			# The dugout view otherwise only appears behind the final overlay, so
			# drive the camera mode directly for a clean bench-interior capture.
			game.broadcast_camera.set_mode("dugout")
			game.hud.set_strike_zone_visible(false)
			game.hud.set_pitch_selector(false)
			game.hud.set_help("")
			game.hud.phase_label.text = "IN THE DUGOUT"
		_:
			game._set_gameplay_view(false)
			game.broadcast_camera.set_mode("pitching")
	_hide_transient_banner(game, screen)


func _gameplay_capture_spec(screen: String) -> Dictionary:
	if screen in ["game-day", "game-golden", "game-night"]:
		return {"view": "pitching", "mood": screen.trim_prefix("game-")}
	var parts: PackedStringArray = screen.split("-", false)
	if parts.size() == 3:
		return {"view": String(parts[1]), "mood": String(parts[2])}
	return {"view": "pitching", "mood": "day"}


func _hide_transient_banner(game: Node, screen: String) -> void:
	if not screen.begins_with("game-") or game.hud == null:
		return
	# Freeze simulation publication before applying final forced-view labels.
	# Rendering continues, but a ready-state physics tick cannot overwrite them.
	game.set_physics_process(false)
	if game.live_play != null:
		game.live_play.set_physics_process(false)
	if is_instance_valid(game.hud.result_panel):
		game.hud.result_panel.visible = false
	# Apply forced-view labels after the settling frames; the live game process
	# otherwise republishes the ready-state HUD while this QA shortcut waits.
	if "fielding" in screen:
		game.hud.set_pitch_selector(false)
		game.hud.set_help("")
		game.hud.phase_label.text = "LIVE BALL"
	elif "dugout" in screen:
		game.hud.set_pitch_selector(false)
		game.hud.set_help("")
		game.hud.phase_label.text = "IN THE DUGOUT"
	elif "batting" in screen:
		game.hud.set_pitch_selector(false)
		game.hud.set_help("WASD AIM  •  SPACE SWING")
		game.hud.phase_label.text = "YOU'RE BATTING"


func _find_subviewport(node: Node) -> SubViewport:
	if node is SubViewport:
		return node as SubViewport
	for child in node.get_children():
		var found := _find_subviewport(child)
		if found != null:
			return found
	return null


func _options() -> Dictionary:
	var parsed := {}
	for argument in OS.get_cmdline_user_args():
		if not argument.begins_with("--") or "=" not in argument:
			continue
		var parts := argument.trim_prefix("--").split("=", true, 1)
		parsed[String(parts[0])] = String(parts[1])
	return parsed
