extends Node

## Pixiball: Harbor League
##
## A complete, deterministic three-inning baseball game whose presentation,
## actors, field, cameras, audio, and agent-control contract are all authored
## as inspectable Godot source. Simulation never reads animation state.

const C = preload("res://gameplay/game_constants.gd")
const SimScript = preload("res://gameplay/pixiball_sim.gd")
const BallplayerScene = preload("res://characters/ballplayer_actor.tscn")
const CatalogScript = preload("res://core/content/content_catalog.gd")
const PitchModelScript = preload("res://core/model/pitch_model.gd")
const ParkGeometry = preload("res://core/fielding/park_geometry.gd")
const ShellModelScript = preload("res://ui/pixiball_shell_model.gd")
const SaveRepositoryScript = preload("res://ui/pixiball_save_repository.gd")
const ENDLESS_SIM_PATH := "res://gameplay/pixiball_endless_sim.gd"

const DRIVER_GROUP := &"godot_ai_gameplay_driver"
const DEFAULT_PITCH_FLIGHT_SECONDS := 0.46
const WINDUP_RELEASE_FALLBACK_SECONDS := 0.90
const SWING_CONTACT_LEAD_SECONDS := 0.23
const PLATE_WORLD_PER_FOOT := ParkGeometry.VERTICAL_WORLD_PER_FOOT
const PITCH_PLANE_Z_OFFSET := -0.55
const PITCH_ARC_LIFT_FT := 2.2
const AIM_LATERAL_FT := 1.35
const AIM_VERTICAL_FT := 1.55
const AIM_CENTER_HEIGHT_FT := 2.5
const NATIVE_FRAMEBUFFER_SIZE := Vector2i(1280, 720)
const PIXEL_GRID_SIZE := 4

var sim: PixiballSim
var stadium: VoxelStadium
var hud: PixiballHUD
var broadcast_camera: PixiballBroadcastCamera
var ball: BaseballVisual
var audio_director: PixiballAudioDirector
var live_play: PixiballLivePlayController
var haptic_director: PixiballHapticDirector
var cast_root: Node
var content_catalog: PixiballContentCatalog
var pitch_model: PixPitchModel
var pitch_intel_panel: PixiballPitchIntelPanel

var defenders: Dictionary = {}
var batter: BallplayerActor
var runners: Array[BallplayerActor] = []
var umpire: BallplayerActor

var flow := "landing"
var flow_time := 0.0
var selected_pitch := 0
var selected_pitcher_index := 0
var aim := Vector2.ZERO
var active_pitch: Dictionary = {}
var pending_plate_result: Dictionary = {}
var pitch_elapsed := 0.0
var pitch_release_world := Vector3.ZERO
var pitch_release_captured := false
var swing_started := false
var swing_started_at := -1.0
var cpu_swing_animated := false
var previous_half := "top"
var _intent_queue: Array[Dictionary] = []
var _autoplay := false
var _mood_index := 0
var _last_published_event_seq := 0
var _visual_rng := RandomNumberGenerator.new()
var headless_fast_forward := false
var _semantic_field_move := Vector2.ZERO
var _semantic_field_move_ticks := 0
var shell: PixiballShellModel
var save_repository: PixiballSaveRepository
var match_mode := "versus"
var home_team: Dictionary = C.HOME_TEAM.duplicate(true)
var away_team: Dictionary = C.AWAY_TEAM.duplicate(true)
var _last_match_config := {"mode": "versus", "seed": 20260710, "innings": 3, "difficulty": 0.55, "home_team_index": -1, "away_team_index": -1}
var _final_recorded := false
var _endless_strikeouts := 0
var _final_state: Dictionary = {}
var _final_new_best := false
var _hud_pitcher_id := -1
var _pitcher_visual_signature := ""
var _batter_visual_signature := ""
var _current_batter_identity: Dictionary = {}
var _pending_pitch_report: Dictionary = {}


func _enter_tree() -> void:
	_configure_native_framebuffer()
	add_to_group(DRIVER_GROUP)


func _configure_native_framebuffer() -> void:
	# The game renders straight into a 720p root. PixelScene's 4x CanvasItem
	# transform expands one authored design unit into one 4x4 native pixel block;
	# there is deliberately no 320x180 SubViewport or sampled intermediate.
	var game_window := get_window()
	game_window.content_scale_size = NATIVE_FRAMEBUFFER_SIZE
	game_window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	game_window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_KEEP
	game_window.content_scale_stretch = Window.CONTENT_SCALE_STRETCH_INTEGER
	game_window.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST


func _ready() -> void:
	_visual_rng.seed = 0x50cce5
	_configure_pixel_scene_grid()
	_ensure_input_actions()
	_build_world()
	sim = SimScript.new(20260710, 3, 0.55)
	_configure_replica_gameplay()
	shell = ShellModelScript.new()
	save_repository = SaveRepositoryScript.new()
	save_repository.load_profile()
	_build_cast()
	_configure_half(true)
	_show_landing()
	if "--autoplay" in OS.get_cmdline_user_args():
		call_deferred("_start_command_line_autoplay")


func _configure_pixel_scene_grid() -> void:
	var pixel_scene := get_node_or_null("PixelScene") as Node2D
	if pixel_scene == null:
		push_error("Pixiball native renderer requires the PixelScene CanvasItem host.")
		return
	pixel_scene.position = Vector2.ZERO
	pixel_scene.scale = Vector2.ONE * PIXEL_GRID_SIZE
	pixel_scene.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _start_command_line_autoplay() -> void:
	var innings := 1
	var batting_demo := false
	var endless_demo := false
	var autoplay_delay := 0.0
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--innings="):
			innings = clampi(int(argument.trim_prefix("--innings=")), 1, 9)
		elif argument.begins_with("--autoplay-delay="):
			autoplay_delay = clampf(float(argument.trim_prefix("--autoplay-delay=")), 0.0, 60.0)
		elif argument == "--scenario=batting":
			batting_demo = true
		elif argument == "--scenario=endless":
			endless_demo = true
	if endless_demo:
		_start_endless(4242, 0)
		if autoplay_delay > 0.0:
			await get_tree().create_timer(autoplay_delay).timeout
		_autoplay = true
		return
	_start_match(4242, innings, 0.72)
	if batting_demo:
		_advance_to_bottom_for_capture()
	if autoplay_delay > 0.0:
		await get_tree().create_timer(autoplay_delay).timeout
	_autoplay = true


func _advance_to_bottom_for_capture() -> void:
	# Deterministic visual-QA shortcut used only by the command-line movie path.
	# It exercises the public sim commit sequence rather than mutating counters.
	for batter_out in range(3):
		for strike in range(3):
			var pitch: Dictionary = sim.create_user_pitch("four_seam", Vector2(0.0, 2.5))
			sim.commit_plate_result({"outcome": "called_strike", "pitch_serial": pitch.serial})
			sim.advance_after_result()
	_configure_half(true)
	_set_ready()


func _build_world() -> void:
	stadium = get_node("World/Stadium") as VoxelStadium
	cast_root = get_node("Actors/Ballplayers") as Node
	ball = get_node("Presentation/Baseball") as BaseballVisual
	broadcast_camera = get_node("Presentation/CameraDirector") as PixiballBroadcastCamera
	live_play = get_node("Systems/LivePlayController") as PixiballLivePlayController
	audio_director = get_node("Systems/AudioDirector") as PixiballAudioDirector
	haptic_director = get_node("Systems/HapticDirector") as PixiballHapticDirector
	hud = get_node("PixiballHUD") as PixiballHUD
	pitch_intel_panel = get_node("PitchIntelLayer/PitchIntelPanel") as PixiballPitchIntelPanel
	stadium.set_mood("day")
	if not live_play.completed.is_connected(_on_live_play_completed):
		live_play.completed.connect(_on_live_play_completed)
	if not live_play.phase_changed.is_connected(_on_live_play_phase_changed):
		live_play.phase_changed.connect(_on_live_play_phase_changed)


func _configure_replica_gameplay() -> void:
	if content_catalog == null:
		content_catalog = CatalogScript.new()
		if not content_catalog.load_all():
			push_error("Pixiball content catalog failed: %s" % content_catalog.last_error)
			return
	if pitch_model == null:
		pitch_model = PitchModelScript.new()
		if not pitch_model.load_from_directory():
			push_error("Pixiball trained model failed: %s" % pitch_model.last_error)
			return
	selected_pitcher_index = posmod(selected_pitcher_index, content_catalog.pitchers.size())
	var cpu_index := (selected_pitcher_index + 1) % content_catalog.pitchers.size()
	var user_pitcher := content_catalog.pitcher_at(selected_pitcher_index)
	var configured: Dictionary
	if match_mode == "endless" and sim.has_method("configure_endless"):
		configured = sim.configure_endless(user_pitcher, pitch_model, content_catalog)
	else:
		configured = sim.configure_replica(user_pitcher, content_catalog.pitcher_at(cpu_index), pitch_model)
	if not bool(configured.get("ok", false)):
		push_error("Pixiball replica gameplay failed: %s" % String(configured.get("message", configured.get("error", "unknown"))))
		return
	hud.set_arsenal(user_pitcher.get("pitches", []))
	hud.set_title_matchup(user_pitcher, selected_pitcher_index, content_catalog.pitchers.size())


func _cycle_pitcher(direction: int) -> void:
	if content_catalog == null or content_catalog.pitchers.is_empty() or flow != "pitcher_select":
		return
	selected_pitcher_index = posmod(selected_pitcher_index + direction, content_catalog.pitchers.size())
	shell.pitcher_index = selected_pitcher_index
	_configure_replica_gameplay()
	selected_pitch = 0
	hud.show_pitcher_select(content_catalog.pitchers, selected_pitcher_index)
	audio_director.play_event("select", -7.0, 1.0 + float(selected_pitcher_index % 4) * 0.03)


func _select_pitcher_index(index: int) -> void:
	if content_catalog == null or content_catalog.pitchers.is_empty() or flow not in ["landing", "pitcher_select"]:
		return
	selected_pitcher_index = clampi(index, 0, content_catalog.pitchers.size() - 1)
	if shell != null:
		shell.pitcher_index = selected_pitcher_index
	_configure_replica_gameplay()
	selected_pitch = 0


func _build_cast() -> void:
	for key_value in C.DEFENSIVE_POSITIONS:
		var key := String(key_value)
		var player := BallplayerScene.instantiate() as BallplayerActor
		player.name = key.capitalize()
		player.configure(_make_player_spec(C.HOME_TEAM, defenders.size(), key))
		cast_root.add_child(player)
		defenders[key] = player
		if key == "pitcher":
			player.action_marker.connect(_on_pitcher_action_marker)

	batter = BallplayerScene.instantiate() as BallplayerActor
	batter.name = "Batter"
	batter.configure(_make_player_spec(C.AWAY_TEAM, 9, "batter"))
	cast_root.add_child(batter)

	for i in range(3):
		var runner := BallplayerScene.instantiate() as BallplayerActor
		runner.name = "Runner%d" % (i + 1)
		runner.configure(_make_player_spec(C.AWAY_TEAM, 10 + i, "fielder"))
		runner.visible = false
		cast_root.add_child(runner)
		runners.append(runner)

	umpire = BallplayerScene.instantiate() as BallplayerActor
	umpire.name = "Umpire"
	umpire.configure({
		"seed": 9001,
		"role": "umpire",
		"number": 0,
		"mark": "",
		"build": "power",
		"primary_color": Color("151922"),
		"secondary_color": Color("252c38"),
		"accent_color": Color("d9e2ea"),
		"pants_color": Color("282d35"),
		"glove": false,
	})
	cast_root.add_child(umpire)


func _make_player_spec(team: Dictionary, roster_index: int, role: String) -> Dictionary:
	var seed := 1013 + roster_index * 7919 + (0 if team == C.HOME_TEAM else 41011)
	var builds := ["balanced", "speed", "power", "balanced", "speed"]
	var role_name := role
	if role not in ["pitcher", "catcher", "batter"]:
		role_name = "fielder"
	return {
		"seed": seed,
		"role": role_name,
		"number": 2 + posmod(roster_index * 11 + seed, 88),
		"mark": String(team["abbr"]).left(1),
		"build": builds[roster_index % builds.size()],
		"throws": "left" if roster_index % 7 == 4 else "right",
		"bats": "left" if roster_index % 3 == 1 else "right",
		"primary_color": team["primary"],
		"secondary_color": team["trim"],
		"accent_color": team["secondary"],
		"pants_color": Color("e9e6da"),
		"helmet": role_name == "batter",
		"bat": role_name == "batter",
	}


func _configure_half(force := false) -> void:
	var state := sim.snapshot()
	if not force and previous_half == String(state.half):
		_reset_cast_positions()
		return
	previous_half = String(state.half)
	var defense_team: Dictionary = home_team if state.half == "top" else away_team
	var offense_team: Dictionary = away_team if state.half == "top" else home_team
	_configure_live_matchup_visuals(state, defense_team, offense_team)
	for key_value in defenders:
		var key := String(key_value)
		var player: BallplayerActor = defenders[key]
		_apply_team_uniform(player, defense_team)
	_apply_team_uniform(batter, offense_team)
	for runner in runners:
		_apply_team_uniform(runner, offense_team)
	_reset_cast_positions()
	_set_gameplay_view(state.half == "bottom")


func _set_gameplay_view(user_batting: bool) -> void:
	# The plate camera sits in the catcher/umpire corridor. Those two actors are
	# hidden only for zone hitting; the batter, pitcher, and pitch remain live.
	broadcast_camera.set_mode("batting" if user_batting else "pitching")
	if defenders.has("catcher"):
		(defenders["catcher"] as BallplayerActor).visible = not user_batting
	if umpire != null:
		umpire.visible = not user_batting
	if hud != null:
		hud.set_batting_layout(user_batting)
	_sync_strike_zone_projection()


func _sync_strike_zone_projection() -> void:
	if hud == null or broadcast_camera == null:
		return
	# HUD controls live directly in the native 1280x720 root rather than under
	# PixelScene, so hand off the projector's explicitly converted native rect.
	var projected := broadcast_camera.projected_strike_zone_native()
	if projected.size.x > 1.0 and projected.size.y > 1.0:
		hud.set_strike_zone_rect(projected)
		hud.set_strike_zone_lateral_sign(broadcast_camera.plate_lateral_screen_sign())


func _apply_team_uniform(player: BallplayerActor, team: Dictionary) -> void:
	player.set_uniform_colors(team.primary, team.trim, team.secondary, Color("e9e6da"))
	player.set_team_mark(String(team.abbr).left(1))


func _configure_live_matchup_visuals(state: Dictionary, defense_team: Dictionary, offense_team: Dictionary) -> void:
	_configure_live_pitcher_visual(state, defense_team)
	_configure_live_batter_visual(state, offense_team)


func _configure_live_pitcher_visual(state: Dictionary, team: Dictionary) -> void:
	if not defenders.has("pitcher") or content_catalog == null:
		return
	var fielding_side := String(state.get("fielding_side", "home"))
	var active_pitchers: Dictionary = state.get("active_pitchers", {})
	var live_pitcher: Dictionary = active_pitchers.get(fielding_side, {}).duplicate(true)
	if live_pitcher.is_empty() and sim != null and sim.replica_enabled():
		live_pitcher = sim.user_pitcher().duplicate(true)
	if live_pitcher.is_empty():
		return
	var catalog_pitcher := content_catalog.pitcher_by_id(int(live_pitcher.get("id", -1)))
	if not catalog_pitcher.is_empty():
		catalog_pitcher.merge(live_pitcher, true)
		live_pitcher = catalog_pitcher
	var signature := "%s/%s/%s/%s/%d/%s" % [
		fielding_side,
		String(team.get("abbr", "")),
		int(live_pitcher.get("id", -1)),
		String(live_pitcher.get("throws", "R")),
		int(live_pitcher.get("number", 0)),
		String(live_pitcher.get("name", "")),
	]
	if signature == _pitcher_visual_signature:
		return
	_pitcher_visual_signature = signature
	var card: Dictionary = live_pitcher.get("card", {})
	var velocity := int(card.get("velo", 92))
	var build := "power" if velocity >= 96 else ("speed" if velocity <= 90 else "balanced")
	var number := int(live_pitcher.get("number", 0))
	if number <= 0:
		number = 2 + posmod(int(live_pitcher.get("id", 1)), 88)
	var player: BallplayerActor = defenders["pitcher"]
	player.configure({
		"seed": maxi(1, int(live_pitcher.get("id", 1))),
		"role": "pitcher",
		"player_name": String(live_pitcher.get("name", "")),
		"number": number,
		"mark": String(team.get("abbr", "")).left(1),
		"build": build,
		"throws": String(live_pitcher.get("throws", "R")),
		"bats": String(live_pitcher.get("throws", "R")),
		"primary_color": team.get("primary", Color("44d7b6")),
		"secondary_color": team.get("trim", Color("f8f3dc")),
		"accent_color": team.get("secondary", Color("102a43")),
		"pants_color": Color("e9e6da"),
		"glove": true,
		"bat": false,
		"helmet": false,
	})


func _configure_live_batter_visual(state: Dictionary, team: Dictionary) -> void:
	if batter == null or content_catalog == null:
		return
	var batting_side := String(state.get("batting_side", "away"))
	var batter_indices: Dictionary = state.get("batter_index", {})
	var lineup_index := int(batter_indices.get(batting_side, 0))
	var lineups: Dictionary = state.get("lineups", {})
	var lineup: Array = lineups.get(batting_side, [])
	var hitter: Dictionary = lineup[lineup_index % lineup.size()].duplicate(true) if not lineup.is_empty() else {}
	var stand := String(hitter.get("stand", "R"))
	var archetype := String(hitter.get("archetype", "Balanced Hitter"))
	var team_token := String(team.get("id", team.get("abbr", batting_side)))
	var identity_seed := _stable_text_seed(team_token) + lineup_index * 7919
	var name: String = C.PLAYER_NAMES[posmod(identity_seed, C.PLAYER_NAMES.size())]
	if not content_catalog.batter_names.is_empty():
		name = content_catalog.batter_names[posmod(identity_seed, content_catalog.batter_names.size())].to_upper()
	var number := 2 + posmod(identity_seed * 17, 88)
	var build := "balanced"
	if archetype.to_lower().contains("power") or archetype.to_lower().contains("free swinger"):
		build = "power"
	elif float(hitter.get("speed", 0.0)) >= 27.5 or archetype.to_lower().contains("contact"):
		build = "speed"
	var signature := "%s/%s/%d/%s/%s/%s/%d" % [batting_side, team_token, lineup_index, stand, archetype, name, number]
	_current_batter_identity = {
		"name": name,
		"number": number,
		"bats": "left" if stand.to_lower().begins_with("l") else "right",
		"archetype": archetype,
		"team": String(team.get("abbr", "")),
	}
	if signature == _batter_visual_signature:
		return
	_batter_visual_signature = signature
	batter.configure({
		"seed": maxi(1, identity_seed),
		"role": "batter",
		"player_name": name,
		"number": number,
		"mark": String(team.get("abbr", "")).left(1),
		"build": build,
		"throws": "right",
		"bats": stand,
		"primary_color": team.get("primary", Color("ff6b5e")),
		"secondary_color": team.get("trim", Color("ffd166")),
		"accent_color": team.get("secondary", Color("41152d")),
		"pants_color": Color("e9e6da"),
		"glove": false,
		"bat": true,
		"helmet": true,
	})


func _stable_text_seed(value: String) -> int:
	var result := 5381
	for index in range(value.length()):
		result = posmod(result * 33 + value.unicode_at(index), 2147483647)
	return maxi(1, result)


func _reset_cast_positions() -> void:
	for key_value in defenders:
		var key := String(key_value)
		var player: BallplayerActor = defenders[key]
		player.global_position = C.DEFENSIVE_POSITIONS[key]
		var facing := C.HOME_PLATE - player.global_position
		if key == "pitcher":
			facing = C.HOME_PLATE - C.PITCHER_MOUND
		elif key == "catcher":
			facing = C.PITCHER_MOUND - C.HOME_PLATE
		player.set_facing(facing)
		player.set_motion(Vector3.ZERO)
		if key == "pitcher":
			player.hold_action_pose("pitch", 0.0)
		else:
			player.play_action("field_ready")
	var batter_x := 1.35 if String(_current_batter_identity.get("bats", "right")) == "left" else -1.35
	batter.global_position = C.HOME_PLATE + Vector3(batter_x, 0.0, -0.25)
	batter.visible = true
	batter.set_facing(C.PITCHER_MOUND - C.HOME_PLATE)
	batter.set_motion(Vector3.ZERO)
	batter.hold_action_pose("swing", 0.25)
	umpire.global_position = C.HOME_PLATE + Vector3(0.0, 0.0, 3.1)
	umpire.set_facing(C.PITCHER_MOUND - C.HOME_PLATE)
	umpire.set_motion(Vector3.ZERO)
	umpire.play_action("field_ready")
	_sync_runner_visuals()


func _show_landing() -> void:
	flow = "landing"
	flow_time = 0.0
	if shell != null:
		shell.show_landing()
	hud.show_landing(save_repository.snapshot() if save_repository != null else {}, shell.landing_focus if shell != null else 0)
	broadcast_camera.set_mode("intro")
	if defenders.has("catcher"):
		(defenders["catcher"] as BallplayerActor).visible = true
	if umpire != null:
		umpire.visible = true
	ball.set_active(false)
	live_play.reset()
	if pitch_intel_panel != null:
		pitch_intel_panel.clear()
	_pending_pitch_report.clear()
	for player in defenders.values():
		player.play_action("idle")


func _show_title() -> void:
	# Compatibility alias retained for scenarios and old agent scripts.
	_show_landing()


func _show_pitcher_select() -> void:
	flow = "pitcher_select"
	flow_time = 0.0
	shell.show_pitchers(selected_pitcher_index)
	hud.show_pitcher_select(content_catalog.pitchers, selected_pitcher_index)
	broadcast_camera.set_mode("intro")
	ball.set_active(false)


func _show_team_select() -> void:
	flow = "team_select"
	flow_time = 0.0
	shell.show_teams()
	hud.show_team_select(content_catalog.teams, shell.snapshot())
	broadcast_camera.set_mode("intro")
	ball.set_active(false)


func _start_match(seed := 20260710, innings := 3, difficulty := 0.55) -> void:
	_start_versus(seed, innings, difficulty)


func _start_endless(seed := 20260710, pitcher_index := -1) -> void:
	if pitcher_index >= 0:
		selected_pitcher_index = clampi(pitcher_index, 0, content_catalog.pitchers.size() - 1)
		if shell != null:
			shell.pitcher_index = selected_pitcher_index
	match_mode = "endless"
	home_team = C.HOME_TEAM.duplicate(true)
	away_team = C.AWAY_TEAM.duplicate(true)
	var pitcher := content_catalog.pitcher_at(selected_pitcher_index)
	if ResourceLoader.exists(ENDLESS_SIM_PATH):
		var endless_script: Script = load(ENDLESS_SIM_PATH)
		sim = endless_script.new(seed, pitcher, pitch_model) as PixiballSim
	else:
		# Isolated compatibility path for editor boot while the dedicated sim is
		# absent; production builds include PixiballEndlessSim.
		sim = SimScript.new(seed, 1, 0.62)
	_configure_replica_gameplay()
	_last_match_config = {"mode": "endless", "seed": seed, "pitcher_index": selected_pitcher_index}
	_begin_match_presentation("THREE RUNS. HOW MANY CAN YOU K?")


func _start_versus(seed := 20260710, innings := 3, difficulty := 0.55, home_index := -1, away_index := -1) -> void:
	match_mode = "versus"
	if home_index >= 0 and away_index >= 0 and home_index != away_index:
		home_team = _team_spec(content_catalog.teams[clampi(home_index, 0, content_catalog.teams.size() - 1)], true)
		away_team = _team_spec(content_catalog.teams[clampi(away_index, 0, content_catalog.teams.size() - 1)], false)
	else:
		home_team = C.HOME_TEAM.duplicate(true)
		away_team = C.AWAY_TEAM.duplicate(true)
	sim = SimScript.new(seed, clampi(innings, 1, 9), clampf(difficulty, 0.0, 1.0))
	_configure_replica_gameplay()
	if sim.has_method("configure_versus") and home_index >= 0 and away_index >= 0:
		var versus_result: Dictionary = sim.configure_versus(content_catalog.teams[home_index], content_catalog.teams[away_index], content_catalog, pitch_model)
		if not bool(versus_result.get("ok", true)):
			push_error("Pixiball versus configuration failed: %s" % String(versus_result.get("message", "unknown")))
	hud.set_arsenal(sim.user_pitcher().get("pitches", []))
	_last_match_config = {"mode": "versus", "seed": seed, "innings": clampi(innings, 1, 9), "difficulty": clampf(difficulty, 0.0, 1.0), "home_team_index": home_index, "away_team_index": away_index}
	_begin_match_presentation("%d INNINGS. EVERY PITCH COUNTS." % clampi(innings, 1, 9))


func _begin_match_presentation(detail: String) -> void:
	previous_half = ""
	selected_pitch = 0
	aim = Vector2.ZERO
	_autoplay = false
	_last_published_event_seq = 0
	_hud_pitcher_id = int(sim.user_pitcher().get("id", -1)) if sim.replica_enabled() else -1
	_endless_strikeouts = 0
	_final_recorded = false
	shell.show_game()
	hud.set_match_teams(home_team, away_team)
	hud.clear_events()
	hud.show_game()
	_configure_half(true)
	audio_director.play_event("crowd", -8.0)
	hud.banner("PLAY BALL", detail, Color("44d7b6"), 1.5)
	_set_ready()


func _rematch() -> void:
	if String(_last_match_config.get("mode", "versus")) == "endless":
		if sim.has_method("retry"):
			sim.retry()
			_begin_match_presentation("THREE RUNS. HOW MANY CAN YOU K?")
		else:
			_start_endless(int(_last_match_config.get("seed", 20260710)), int(_last_match_config.get("pitcher_index", selected_pitcher_index)))
	else:
		if sim.has_method("restart"):
			sim.restart()
			_begin_match_presentation("%d INNINGS. EVERY PITCH COUNTS." % int(_last_match_config.get("innings", 3)))
		else:
			_start_versus(int(_last_match_config.get("seed", 20260710)), int(_last_match_config.get("innings", 3)), float(_last_match_config.get("difficulty", 0.55)), int(_last_match_config.get("home_team_index", -1)), int(_last_match_config.get("away_team_index", -1)))


func _exit_to_menu() -> void:
	_autoplay = false
	_intent_queue.clear()
	_show_landing()


func _team_spec(source: Dictionary, is_home: bool) -> Dictionary:
	var primary := Color.from_string(String(source.get("color", "#44d7b6")), Color("44d7b6"))
	var text := Color.from_string(String(source.get("textOn", "#f8f3dc")), Color("f8f3dc"))
	return {
		"id": String(source.get("id", "home" if is_home else "away")),
		"city": String(source.get("city", "HARBOR CITY")),
		"name": String(source.get("name", "CLUB")),
		"abbr": String(source.get("abbr", "HME" if is_home else "AWY")),
		"primary": primary,
		"secondary": primary.darkened(0.62),
		"trim": text,
	}


func _set_ready() -> void:
	flow = "ready"
	flow_time = 0.0
	active_pitch.clear()
	pending_plate_result.clear()
	swing_started = false
	swing_started_at = -1.0
	cpu_swing_animated = false
	ball.set_active(false)
	live_play.reset()
	if pitch_intel_panel != null:
		pitch_intel_panel.clear()
	_pending_pitch_report.clear()
	var state := sim.snapshot()
	var offense_team: Dictionary = away_team if state.half == "top" else home_team
	var defense_team: Dictionary = home_team if state.half == "top" else away_team
	_configure_live_matchup_visuals(state, defense_team, offense_team)
	_reset_cast_positions()
	_set_gameplay_view(sim.is_user_batting())
	var batter_index := int(state.batter_index[state.batting_side])
	var player_name := String(_current_batter_identity.get("name", C.PLAYER_NAMES[batter_index % C.PLAYER_NAMES.size()]))
	var player_number := int(_current_batter_identity.get("number", 2 + posmod(batter_index * 17, 88)))
	var batter_hand := "L" if String(_current_batter_identity.get("bats", "right")) == "left" else "R"
	var batter_archetype := String(_current_batter_identity.get("archetype", "BALANCED HITTER")).to_upper().trim_suffix(" HITTER")
	hud.set_identity("%s  #%02d   •   %s   •   %s BAT   •   %s" % [player_name, player_number, offense_team.name, batter_hand, batter_archetype])
	hud.set_pitch_selector(sim.is_user_pitching(), selected_pitch)
	hud.set_strike_zone_visible(true)
	hud.set_pitch_marker(Vector2.ZERO, false)
	hud.set_aim(aim, Color("ff6b5e") if sim.is_user_pitching() else Color("44d7b6"))
	hud.set_help("1–5 SELECT  •  WASD AIM  •  SPACE THROW" if sim.is_user_pitching() else "WASD BARREL  •  SPACE SWING")
	_refresh_hud()


func _physics_process(delta: float) -> void:
	flow_time += delta
	_drain_intents()
	_handle_global_controls()
	match flow:
		"landing", "pitcher_select", "team_select", "game_over":
			_update_shell_input()
		"ready":
			_update_ready(delta)
		"windup":
			_update_windup(delta)
		"pitch_flight":
			_update_pitch_flight(delta)
		"live_play":
			_update_live_play(delta)
		"result":
			_reveal_pending_pitch_report()
			if flow_time >= 1.55:
				_advance_result()
	if not headless_fast_forward:
		_sync_strike_zone_projection()
		_refresh_hud()
		_publish_new_events()


func _handle_global_controls() -> void:
	if Input.is_action_just_pressed("pix_restart") and flow in ["ready", "windup", "pitch_flight", "live_play", "result"]:
		_rematch()
	if Input.is_action_just_pressed("pix_mood"):
		_cycle_mood()


func _update_shell_input() -> void:
	if shell == null:
		return
	var left := Input.is_action_just_pressed("pix_left")
	var right := Input.is_action_just_pressed("pix_right")
	var up := Input.is_action_just_pressed("pix_up")
	var down := Input.is_action_just_pressed("pix_down")
	if flow == "team_select" and (left or right) and shell.team_focus in [8, 9]:
		shell.cycle_option(-1 if left else 1)
		_refresh_shell_screen()
		audio_director.play_event("select", -8.0)
	elif left or right or up or down:
		var x := -1 if left else (1 if right else 0)
		var y := -1 if up else (1 if down else 0)
		shell.navigate(x, y)
		if flow == "pitcher_select":
			_select_pitcher_index(shell.pitcher_index)
		_refresh_shell_screen()
		audio_director.play_event("select", -8.0, 0.98 + float(posmod(x + y, 3)) * 0.025)
	if Input.is_action_just_pressed("pix_cycle") and flow == "team_select" and shell.team_focus >= 8:
		shell.navigate(1, 0)
		_refresh_shell_screen()
	if Input.is_action_just_pressed("pix_back"):
		if flow == "game_over":
			_exit_to_menu()
		elif flow in ["pitcher_select", "team_select"]:
			_exit_to_menu()
	if Input.is_action_just_pressed("pix_start") or Input.is_action_just_pressed("pix_primary"):
		_apply_shell_command(shell.confirm())


func _apply_shell_command(command: Dictionary) -> void:
	match String(command.get("command", "none")):
		"open_pitchers":
			_show_pitcher_select()
		"open_teams":
			_show_team_select()
		"team_changed", "option_changed", "disabled":
			_refresh_shell_screen()
		"start_endless":
			_start_endless(20260710, int(command.get("pitcher_index", selected_pitcher_index)))
		"start_versus":
			_start_versus(20260710, int(command.get("innings", 3)), float(command.get("difficulty", 0.55)), int(command.get("player_team_index", 0)), int(command.get("cpu_team_index", 1)))
		"rematch":
			_rematch()
		"exit_to_menu":
			_exit_to_menu()


func _refresh_shell_screen() -> void:
	match flow:
		"landing":
			hud.show_landing(save_repository.snapshot(), shell.landing_focus)
		"pitcher_select":
			hud.show_pitcher_select(content_catalog.pitchers, shell.pitcher_index)
		"team_select":
			hud.show_team_select(content_catalog.teams, shell.snapshot())
		"game_over":
			hud.show_final(match_mode, _final_state, save_repository.snapshot(), _final_new_best, shell.final_focus)


func _update_ready(delta: float) -> void:
	_update_aim(delta)
	if sim.is_user_pitching():
		for i in range(C.PITCHES.size()):
			if Input.is_action_just_pressed("pix_pitch_%d" % (i + 1)):
				_select_pitch(i)
		if Input.is_action_just_pressed("pix_primary"):
			_begin_pitch()
		elif _autoplay and flow_time >= 0.28:
			_select_pitch(int(sim.snapshot().pitch_serial) % C.PITCHES.size())
			_begin_pitch()
	else:
		if flow_time >= 0.72:
			_begin_pitch()


func _update_windup(delta: float) -> void:
	if sim.is_user_batting():
		_update_aim(delta)
	# The imported animation marker owns normal release timing. This fallback is
	# only for a missing/corrupt clip so gameplay can never deadlock in windup.
	if flow_time >= WINDUP_RELEASE_FALLBACK_SECONDS:
		pitch_release_world = defenders["pitcher"].get_socket_position("ball_release")
		pitch_release_captured = true
		_launch_pitch()


func _update_pitch_flight(delta: float) -> void:
	pitch_elapsed += delta
	if sim.is_user_batting():
		_update_aim(delta)
	var flight_seconds := _pitch_flight_seconds()
	var ideal_press := maxf(0.0, flight_seconds - SWING_CONTACT_LEAD_SECONDS)
	if not sim.is_user_batting() and not cpu_swing_animated and bool(pending_plate_result.get("swung", false)) and pitch_elapsed >= ideal_press:
		cpu_swing_animated = true
		batter.play_action("swing")
	if sim.is_user_batting() and not swing_started:
		if Input.is_action_just_pressed("pix_primary"):
			_trigger_swing()
		elif _autoplay and pitch_elapsed >= ideal_press:
			var actual := _pitch_actual_to_aim(active_pitch)
			aim = actual
			_trigger_swing()
	var u := clampf(pitch_elapsed / flight_seconds, 0.0, 1.0)
	var actual_point := _array_vec2(active_pitch.get("actual", [0.0, 2.5]))
	var break_point := _array_vec2(active_pitch.get("break_ft", [0.0, 0.0]))
	var start := pitch_release_world
	var end := _plate_pitch_world(actual_point)
	var position := start.lerp(end, u)
	var bulge := u * (1.0 - u)
	position.x -= break_point.x * PLATE_WORLD_PER_FOOT * bulge
	position.y += (-break_point.y + PITCH_ARC_LIFT_FT) * PLATE_WORLD_PER_FOOT * bulge
	ball.set_ball_position(position, delta)
	if not headless_fast_forward:
		hud.set_pitch_marker(_plate_feet_to_aim(actual_point), u > 0.74)
	if u >= 1.0:
		_finish_pitch()


func _plate_pitch_world(plate_feet: Vector2) -> Vector3:
	return C.HOME_PLATE + Vector3(
		plate_feet.x * PLATE_WORLD_PER_FOOT,
		plate_feet.y * PLATE_WORLD_PER_FOOT,
		PITCH_PLANE_Z_OFFSET
	)


func _pitch_flight_seconds() -> float:
	return clampf(float(active_pitch.get("flight_sec", DEFAULT_PITCH_FLIGHT_SECONDS)), 0.32, 0.68)


func _aim_to_plate_feet(normalized_aim: Vector2) -> Vector2:
	return Vector2(
		normalized_aim.x * AIM_LATERAL_FT,
		AIM_CENTER_HEIGHT_FT - normalized_aim.y * AIM_VERTICAL_FT
	)


func _plate_feet_to_aim(plate_feet: Vector2) -> Vector2:
	return Vector2(
		plate_feet.x / AIM_LATERAL_FT,
		(AIM_CENTER_HEIGHT_FT - plate_feet.y) / AIM_VERTICAL_FT
	)


func _update_live_play(_delta: float) -> void:
	var move := Input.get_vector("pix_left", "pix_right", "pix_up", "pix_down")
	if _semantic_field_move_ticks > 0:
		move = _semantic_field_move
		_semantic_field_move_ticks -= 1
	live_play.set_move_input(move if sim.is_user_fielding() else Vector2.ZERO)
	if Input.is_action_just_pressed("pix_cycle"):
		if sim.is_user_fielding():
			live_play.cycle_fielder()
		else:
			live_play.cycle_runner(1)
	for base_index in range(4):
		var action := "pix_pitch_%d" % (base_index + 1)
		if sim.is_user_fielding():
			if Input.is_action_just_pressed(action):
				live_play.press_throw(base_index)
			if Input.is_action_just_released(action):
				live_play.release_throw(base_index)
		elif Input.is_action_just_pressed(action):
			live_play.command_selected_runner(base_index)
	_update_offense_running(_delta)
	var live_state := live_play.state()
	if not headless_fast_forward:
		hud.set_field_meter(bool(live_state.get("throw_charging", false)), float(live_state.throw_meter))
		if sim.is_user_fielding():
			hud.set_help("WASD FIELD  •  Q CYCLE  •  HOLD 1–4, RELEASE IN GOLD")
		else:
			hud.set_help("Q CYCLE RUNNER  •  1 HOME  2 FIRST  3 SECOND  4 THIRD")


func _update_aim(delta: float) -> void:
	var move := Input.get_vector("pix_left", "pix_right", "pix_up", "pix_down")
	if move.length() > 0.05:
		aim += move * delta * 1.45
		aim = aim.clamp(Vector2(-1, -1), Vector2(1, 1))
	if not headless_fast_forward:
		hud.set_aim(aim, Color("ff6b5e") if sim.is_user_pitching() else Color("44d7b6"))


func _select_pitch(index: int) -> void:
	selected_pitch = clampi(index, 0, C.PITCHES.size() - 1)
	hud.set_pitch_selector(true, selected_pitch)
	audio_director.play_event("select", -7.0, 0.94 + float(selected_pitch) * 0.04)


func _begin_pitch() -> void:
	if flow != "ready" or not sim.is_pitch_phase():
		return
	if sim.is_user_pitching():
		var sim_aim := _aim_to_plate_feet(aim)
		active_pitch = sim.create_user_pitch(_selected_pitch_kind(), sim_aim)
	else:
		active_pitch = sim.create_cpu_pitch()
	if not bool(active_pitch.get("ok", false)):
		hud.banner("CAN'T PITCH", String(active_pitch.get("message", "Invalid pitch")), Color("ff6b5e"))
		return
	flow = "windup"
	flow_time = 0.0
	pitch_release_world = Vector3.ZERO
	pitch_release_captured = false
	defenders["pitcher"].play_action("pitch")
	hud.set_pitch_selector(false)
	hud.set_pitch_marker(Vector2.ZERO, false)
	hud.set_help("TRACK THE RELEASE" if sim.is_user_pitching() else "READ THE PITCH  •  TIME YOUR SWING")


func _on_pitcher_action_marker(action_name: String, marker_name: String) -> void:
	if flow != "windup" or action_name != "pitch" or marker_name != "ball_release":
		return
	pitch_release_world = defenders["pitcher"].get_socket_position("ball_release")
	pitch_release_captured = true
	_launch_pitch()


func _selected_pitch_kind() -> String:
	if sim != null and sim.replica_enabled():
		var pitcher := sim.user_pitcher()
		var pitches: Array = pitcher.get("pitches", [])
		if selected_pitch >= 0 and selected_pitch < pitches.size():
			return String((pitches[selected_pitch] as Dictionary).get("code", "FF")).to_lower()
	return String(C.PITCHES[selected_pitch].id)


func _launch_pitch() -> void:
	if flow != "windup":
		return
	if not pitch_release_captured:
		pitch_release_world = defenders["pitcher"].get_socket_position("ball_release")
		pitch_release_captured = true
	flow = "pitch_flight"
	flow_time = 0.0
	pitch_elapsed = 0.0
	swing_started = false
	swing_started_at = -1.0
	cpu_swing_animated = false
	ball.set_active(true)
	ball.use_pitch_ball()
	ball.set_trail_slot(int(active_pitch.get("slot", selected_pitch)))
	var pitch_shape: Dictionary = active_pitch.get("shape", {})
	ball.begin_pitch_motion(
		float(pitch_shape.get("spinRate", pitch_shape.get("spin_rate", 2200.0))),
		float(pitch_shape.get("spinAxis", pitch_shape.get("spin_axis", 180.0))),
		sim.is_user_batting()
	)
	ball.set_ball_position(pitch_release_world)
	audio_director.play_event("pitch", -5.0, clampf(float(active_pitch.get("velocity_mph", 90.0)) / 92.0, 0.86, 1.13))
	_play_release_haptic()
	if sim.is_user_pitching():
		pending_plate_result = sim.resolve_cpu_batter(active_pitch)


func _trigger_swing() -> void:
	if flow != "pitch_flight" or swing_started:
		return
	swing_started = true
	swing_started_at = pitch_elapsed
	batter.play_action("swing")
	audio_director.play_event("select", -11.0, 0.72)


func _finish_pitch() -> void:
	if flow != "pitch_flight":
		return
	if sim.is_user_batting():
		var timing_error := 99.0
		if swing_started:
			var ideal_press := maxf(0.0, _pitch_flight_seconds() - SWING_CONTACT_LEAD_SECONDS)
			timing_error = swing_started_at - ideal_press
		pending_plate_result = sim.resolve_user_batter(active_pitch, {
			"did_swing": swing_started,
			"reticle": _aim_to_plate_feet(aim),
			"timing_error_sec": timing_error,
		})
	var outcome := String(pending_plate_result.get("outcome", "ball"))
	var commit := sim.commit_plate_result(pending_plate_result)
	var resolved_outcome := String(commit.get("last_result", {}).get("outcome", outcome))
	_play_pitch_result_haptics(outcome, resolved_outcome)
	var pitch_report := sim.last_pitch_report()
	if not pitch_report.is_empty() and outcome != "in_play":
		_queue_pitch_report(pitch_report)
	if outcome == "in_play" and sim.is_live_play():
		_start_live_play(pending_plate_result.trajectory)
		return
	ball.set_active(false)
	defenders["catcher"].play_action("catch")
	flow = "result"
	flow_time = 0.0
	_prepare_result_hud()
	_show_plate_result(resolved_outcome, commit)


func _play_release_haptic() -> void:
	if haptic_director == null:
		return
	var model_result: Dictionary = active_pitch.get("model_result", {})
	var probabilities: Dictionary = model_result.get("probabilities", {})
	haptic_director.play_kind("release", {
		"pitch_serial": int(active_pitch.get("serial", 0)),
		"screen_direction": -signf(float(model_result.get("actual_x", 0.0)) - float(model_result.get("tunnel_x", 0.0))),
		"confidence": _prediction_confidence(probabilities),
	})


func _play_pitch_result_haptics(plate_outcome: String, resolved_outcome: String) -> void:
	if haptic_director == null or not sim.is_user_pitching():
		return
	var report := sim.last_pitch_report()
	if report.is_empty():
		return
	var feedback: Dictionary = report.get("feedback", {})
	var probabilities: Dictionary = report.get("probabilities", {})
	var plate_x := float(report.get("actual_x", 0.0))
	var screen_direction := -float(feedback.get("direction", 0.0))
	var margin := float(feedback.get("corner_margin_in", 1.5))
	var values := {
		"pitch_serial": int(active_pitch.get("serial", 0)),
		"plate_x": plate_x,
		"plate_side": -signf(plate_x),
		"screen_direction": screen_direction,
		"confidence": _prediction_confidence(probabilities),
		"tunnel_score": clampf(1.0 - float(report.get("tunnel_in", 12.0)) / 12.0, 0.0, 1.0),
		"corner_proximity": clampf(1.0 - margin / 1.5, 0.0, 1.0),
		"zone_probability": 1.0 if bool(report.get("in_zone", false)) else 0.0,
		"called_strike_probability": float(probabilities.get("called_strike", 0.0)),
		"whiff_probability": float(probabilities.get("swinging_strike", 0.0)),
		"outcome_confirmed": true,
		"metadata": {
			"outcome": resolved_outcome,
			"break_tunnel_ratio": float(report.get("break_tunnel_ratio", 1.0)),
		},
	}
	if float(report.get("tunnel_in", 0.0)) > 0.0:
		haptic_director.play_kind("tunnel", values)
	var door := String(feedback.get("door", "none"))
	if door in ["frontdoor", "backdoor"]:
		haptic_director.play_kind(door, values)
	if bool(feedback.get("corner_paint", false)) and plate_outcome == "called_strike":
		haptic_director.play_kind("corner_paint", values)
	if resolved_outcome == "strikeout":
		haptic_director.play_kind("swinging_k" if plate_outcome == "swinging_strike" else "called_k", values)


func _prediction_confidence(probabilities: Dictionary) -> float:
	var strongest := 0.0
	for key in ["ball", "called_strike", "swinging_strike", "foul", "in_play"]:
		strongest = maxf(strongest, float(probabilities.get(key, 0.0)))
	return clampf(strongest, 0.0, 1.0)


func _start_live_play(trajectory: Dictionary) -> void:
	flow = "live_play"
	flow_time = 0.0
	ball.set_active(true)
	ball.use_play_ball()
	# Preserve the physical plate endpoint from pitch flight. Re-centering here
	# caused a visible jump before the fielding-camera cut.
	var contact_position := ball.global_position
	ball.set_ball_position(contact_position)
	audio_director.play_event("bat", -1.5, 0.92 + float(trajectory.get("contact_quality", 0.5)) * 0.15)
	broadcast_camera.contact_juice(float(trajectory.get("exit_velocity_mph", 90.0)))
	_burst(contact_position, Color("ffd166"), 10)
	if defenders.has("catcher"):
		(defenders["catcher"] as BallplayerActor).visible = true
	if umpire != null:
		umpire.visible = true
	broadcast_camera.set_mode("fielding", ball)
	hud.set_strike_zone_visible(false)
	var play_state := sim.snapshot()
	var play_seed := int(play_state.get("seed", 1)) ^ (int(active_pitch.get("serial", play_state.get("pitch_serial", 0))) * 0x9e3779b1) ^ int(play_state.get("epoch", 0))
	live_play.begin(trajectory, ball, defenders, sim.is_user_fielding(), {
		"bases": play_state.get("bases", {}),
		"difficulty": play_state.get("difficulty", 0.5),
		"outs_before": play_state.get("outs", 0),
		"seed": play_seed,
		"user_runner_control": not sim.is_user_fielding(),
		"visual_contact_world": contact_position,
	})
	_prepare_offense_running()
	hud.banner("BALL IN PLAY", _contact_detail(trajectory), Color("ffd166"), 0.7)


func _show_plate_result(outcome: String, state: Dictionary) -> void:
	var title := outcome.replace("_", " ").to_upper()
	var detail := ""
	var accent := Color("d7e4ee")
	if stadium != null:
		stadium.react_to_play(outcome)
	match outcome:
		"called_strike", "swinging_strike":
			accent = Color("ff6b5e")
			audio_director.play_event("strike", -4.0)
		"strikeout":
			title = "STRIKE THREE"
			accent = Color("ff4d6d")
			detail = "BATTER RETIRED"
			audio_director.play_event("out", -2.0)
		"ball":
			accent = Color("67b7ff")
			audio_director.play_event("ball", -6.0)
		"walk":
			title = "BALL FOUR"
			detail = "TAKE YOUR BASE"
			accent = Color("44d7b6")
		"foul":
			accent = Color("ffd166")
	if pending_plate_result.has("timing_ms"):
		detail = "%+d MS  •  %s CONTACT" % [int(pending_plate_result.timing_ms), String(pending_plate_result.get("quality", "" )).to_upper()]
	hud.banner(title, detail, accent, 1.05)


func _on_live_play_completed(result: Dictionary) -> void:
	if flow != "live_play":
		return
	var committed := sim.commit_live_play(result)
	var pitch_report := sim.last_pitch_report()
	if not pitch_report.is_empty():
		_queue_pitch_report(pitch_report)
	flow = "result"
	flow_time = 0.0
	ball.set_active(false)
	_prepare_result_hud()
	var classification := String(result.get("rule_classification", result.get("classification", "single")))
	var runs := int(committed.get("last_result", {}).get("runs", 0))
	var detail := "%d RUN%s SCORE" % [runs, "" if runs == 1 else "S"] if runs > 0 else ""
	var accent := Color("44d7b6") if classification in ["single", "double", "triple", "home_run"] else Color("ff6b5e")
	if stadium != null:
		stadium.react_to_play(classification)
	hud.banner(String(result.get("label", classification.replace("_", " "))), detail, accent, 1.3)
	if classification == "home_run":
		audio_director.play_event("score", -1.0)
		_fireworks()
		batter.play_action("celebrate")
	elif classification in ["single", "double", "triple"]:
		audio_director.play_event("crowd", -6.0)
	else:
		audio_director.play_event("out", -3.0)
	_sync_runner_visuals()


func _prepare_result_hud() -> void:
	# Contextual controls must reflect the current presentation phase. In
	# particular, do not leave pitch-flight or fielding instructions visible
	# after the semantic play has committed its result.
	hud.set_help("")
	hud.set_field_meter(false)
	hud.remove_event("FIELD IT — PICK A BASE")


func _queue_pitch_report(report: Dictionary) -> void:
	_pending_pitch_report = report.duplicate(true)
	if pitch_intel_panel != null:
		pitch_intel_panel.clear()


func _reveal_pending_pitch_report() -> void:
	if _pending_pitch_report.is_empty() or flow_time < 0.30:
		return
	hud.set_strike_zone_visible(false)
	if pitch_intel_panel != null:
		pitch_intel_panel.present(_pending_pitch_report)
	_pending_pitch_report.clear()


func _on_live_play_phase_changed(next_phase: String) -> void:
	if next_phase == "possession" and sim.is_user_fielding():
		hud.push_event("FIELD IT — PICK A BASE", Color("ffd166"))


func _advance_result() -> void:
	if sim.is_game_over():
		_show_game_over(sim.snapshot())
		return
	if not sim.is_result_phase():
		return
	var before := sim.snapshot()
	var after := sim.advance_after_result()
	if bool(after.get("game_over", false)):
		_show_game_over(after)
		return
	var changed_half := String(after.half) != String(before.half)
	if changed_half:
		_configure_half(true)
		var half_label := "TOP" if after.half == "top" else "BOTTOM"
		hud.banner("%s %s" % [half_label, _ordinal(int(after.inning))], "SIDES CHANGE", Color("67b7ff"), 1.25)
	_set_ready()


func _show_game_over(state: Dictionary) -> void:
	flow = "game_over"
	flow_time = 0.0
	broadcast_camera.set_mode("dugout")
	_final_state = state.duplicate(true)
	_final_new_best = false
	if not _final_recorded and not headless_fast_forward:
		if match_mode == "endless":
			var endless: Dictionary = state.get("endless", {})
			var strikeouts := int(endless.get("strikeouts", _endless_strikeouts))
			var result := save_repository.record_endless(strikeouts)
			_final_new_best = bool(result.get("new_best", false))
		else:
			save_repository.record_versus(String(state.get("winner", "")) == "home")
		_final_recorded = true
	shell.show_final()
	hud.show_final(match_mode, state, save_repository.snapshot(), _final_new_best, shell.final_focus)
	audio_director.play_event("score", 0.0, 0.92)
	for player in defenders.values():
		player.play_action("celebrate")


func _refresh_hud() -> void:
	if sim == null or hud == null or flow in ["landing", "pitcher_select", "team_select", "game_over"]:
		return
	var state := sim.snapshot()
	var base_state: Dictionary = state.bases
	var active_pitchers: Dictionary = state.get("active_pitchers", {})
	var pitcher_side := String(state.get("fielding_side", "home" if state.half == "top" else "away"))
	var active_pitcher: Dictionary = active_pitchers.get(pitcher_side, {})
	if active_pitcher.is_empty() and sim.replica_enabled():
		active_pitcher = sim.user_pitcher()
	hud.update_state({
		"away_score": state.score.away,
		"home_score": state.score.home,
		"inning": state.inning,
		"top": state.half == "top",
		"balls": state.count.balls,
		"strikes": state.count.strikes,
		"outs": state.outs,
		"bases": [base_state.first, base_state.second, base_state.third],
		"phase_label": _phase_label(),
		"pitcher_name": active_pitcher.get("name", "STARTER"),
		"pitcher_throws": active_pitcher.get("throws", "R"),
	})
	var condition := _hud_pitcher_condition(state)
	var stamina_fraction := 1.0
	var stamina_tier := ""
	if not condition.is_empty():
		stamina_fraction = float(condition.get("stamina_fraction", condition.get("energy", 1.0)))
		stamina_tier = String(condition.get("tier", condition.get("status", "")))
	elif state.has("stamina"):
		stamina_fraction = float(state.get("stamina", 1.0))
	hud.set_stamina(stamina_fraction, stamina_tier)
	if defenders.has("pitcher"):
		(defenders["pitcher"] as BallplayerActor).set_stamina(stamina_fraction)
	if sim.replica_enabled():
		var current_pitcher := sim.user_pitcher()
		var current_id := int(current_pitcher.get("id", -1))
		if current_id != _hud_pitcher_id:
			_hud_pitcher_id = current_id
			hud.set_arsenal(current_pitcher.get("pitches", []))
			hud.push_event("NOW PITCHING  %s" % String(current_pitcher.get("name", "RELIEVER")), Color("44d7b6"))


func _hud_pitcher_condition(state: Dictionary) -> Dictionary:
	var conditions: Dictionary = state.get("pitcher_conditions", {})
	var condition_side := "home" if String(state.get("half", "top")) == "top" else "away"
	var value: Variant = conditions.get(condition_side, conditions.get("user", {}))
	return value if value is Dictionary else {}


func _phase_label() -> String:
	match flow:
		"ready": return "YOU'RE PITCHING" if sim.is_user_pitching() else "YOU'RE BATTING"
		"windup": return "WINDUP"
		"pitch_flight": return "%s  •  %d MPH" % [String(active_pitch.get("label", "PITCH")), roundi(float(active_pitch.get("velocity_mph", 0.0)))]
		"live_play": return "LIVE BALL  •  %s" % String(live_play.controlled_key).to_upper()
		"result": return "PLAY COMPLETE"
		"game_over": return "FINAL"
	return "PLAY BALL"


func _publish_new_events() -> void:
	if sim == null:
		return
	var events: Array = sim.recent_events()
	for event_value in events:
		var event: Dictionary = event_value
		var sequence := int(event.get("seq", 0))
		if sequence <= _last_published_event_seq:
			continue
		var type := String(event.get("type", "event"))
		_apply_cast_presentation_event(type, event)
		if type == "play_result":
			hud.push_event(String(event.get("classification", "play")).replace("_", " "), Color("9fb4c5"))
		elif type == "plate_result" and String(event.get("outcome", "")) == "strikeout" and match_mode == "endless":
			_endless_strikeouts += 1
			hud.push_event("K  %d" % _endless_strikeouts, Color("ffd166"))
		elif type == "walk_off":
			hud.push_event("walk off", Color("ffd166"))
		elif type == "half_started":
			hud.push_event("%s %s" % [String(event.get("half", "")).to_upper(), _ordinal(int(event.get("inning", 1)))], Color("67b7ff"))
		elif type == "manager_warm":
			hud.push_event("BULLPEN: %s WARMING" % String(event.get("pitcher_name", event.get("name", "RELIEVER"))), Color("ffd166"))
		elif type == "manager_substitute":
			hud.push_event("PITCHING CHANGE: %s" % String(event.get("pitcher_name", event.get("name", "RELIEVER"))), Color("44d7b6"))
		_last_published_event_seq = maxi(_last_published_event_seq, sequence)


func _apply_cast_presentation_event(type: String, payload: Dictionary) -> void:
	# Pocket Giants consume the simulator's existing event stream strictly as a
	# presentation channel. This does not add gameplay signals or mutate state.
	for actor_value in defenders.values():
		var actor := actor_value as BallplayerActor
		if actor != null:
			actor.apply_sim_event(type, payload)
	if batter != null:
		batter.apply_sim_event(type, payload)
	for runner in runners:
		if runner != null:
			runner.apply_sim_event(type, payload)


func _prepare_offense_running() -> void:
	_sync_live_runner_visuals()


func _update_offense_running(_delta: float) -> void:
	_sync_live_runner_visuals()


func _sync_live_runner_visuals() -> void:
	if live_play == null or not live_play.active:
		return
	for runner in runners:
		runner.visible = false
	var live_runners: Array = live_play.runner_state().get("runners", [])
	for runner_value in live_runners:
		var runner_state: Dictionary = runner_value
		var actor := _actor_for_live_runner(String(runner_state.get("slot", "")))
		if actor == null:
			continue
		var status := String(runner_state.get("state", "hold"))
		actor.visible = status not in ["out", "scored"]
		if not actor.visible:
			actor.set_motion(Vector3.ZERO)
			continue
		var position_value: Array = runner_state.get("position", [])
		if position_value.size() >= 3:
			actor.global_position = Vector3(float(position_value[0]), float(position_value[1]), float(position_value[2]))
		var target_base := int(runner_state.get("to_base", int(runner_state.get("from_base", 0)) + 1)) % 4
		var direction := C.base_position(target_base) - actor.global_position
		if status == "return":
			direction = C.base_position(int(runner_state.get("from_base", 0))) - actor.global_position
		direction.y = 0.0
		var moving := status in ["advance", "return"] and direction.length() > 0.05
		actor.set_motion(direction.normalized() * 7.6 if moving else Vector3.ZERO)
		if moving:
			actor.set_facing(direction)


func _actor_for_live_runner(slot: String) -> BallplayerActor:
	if slot == "batter":
		return batter
	if slot.begins_with("runner_"):
		var base_index := int(slot.trim_prefix("runner_"))
		if base_index >= 1 and base_index <= runners.size():
			return runners[base_index - 1]
	return null


func _sync_runner_visuals() -> void:
	if sim == null:
		return
	var bases: Dictionary = sim.snapshot().bases
	var occupied := [bool(bases.first), bool(bases.second), bool(bases.third)]
	for i in range(3):
		var runner := runners[i]
		runner.visible = occupied[i]
		runner.global_position = C.base_position(i + 1) + Vector3(0.0, 0.0, -0.25)
		runner.set_facing(C.base_position((i + 2) % 4) - runner.global_position)
		runner.set_motion(Vector3.ZERO)


func _cycle_mood() -> void:
	_mood_index = (_mood_index + 1) % 3
	var moods := ["day", "golden", "night"]
	_set_visual_mood(moods[_mood_index])
	hud.push_event("STADIUM MOOD: %s" % moods[_mood_index], Color("ffd166"))


func _set_visual_mood(mood: String) -> void:
	stadium.set_mood(mood)


func _contact_detail(trajectory: Dictionary) -> String:
	return "%d MPH  •  %d°  •  %d FT" % [
		roundi(float(trajectory.get("exit_velocity_mph", 0.0))),
		roundi(float(trajectory.get("launch_angle_deg", 0.0))),
		roundi(float(trajectory.get("carry_ft", 0.0))),
	]


func _pitch_actual_to_aim(pitch: Dictionary) -> Vector2:
	var actual := _array_vec2(pitch.get("actual", [0.0, 2.5]))
	return _plate_feet_to_aim(actual).clamp(Vector2(-1, -1), Vector2(1, 1))


func _array_vec2(value: Variant) -> Vector2:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2:
		return Vector2(float(value[0]), float(value[1]))
	return Vector2.ZERO


func _ordinal(value: int) -> String:
	match value:
		1: return "1ST"
		2: return "2ND"
		3: return "3RD"
		_: return "%dTH" % value


func _burst(at: Vector3, color: Color, count: int) -> void:
	if headless_fast_forward:
		return
	if stadium != null and stadium.has_method("burst"):
		stadium.burst(at, color, count)


func _fireworks() -> void:
	for offset in [Vector3(-16, 13, -43), Vector3(0, 17, -48), Vector3(17, 12, -42)]:
		_burst(offset, [Color("44d7b6"), Color("ffd166"), Color("ff6b5e")][_visual_rng.randi_range(0, 2)], 22)


# -- Typed semantic gameplay driver ---------------------------------------

func _godot_ai_describe() -> Dictionary:
	return {
		"name": "Pixiball: Harbor League",
		"version": 3,
		"intents": {
			"start_match": {
				"description": "Start a deterministic quick game.",
				"params": {
					"seed": {"type": "integer"},
					"innings": {"type": "integer", "minimum": 1, "maximum": 9},
					"difficulty": {"type": "number", "minimum": 0.0, "maximum": 1.0},
				},
			},
			"start_endless": {"description": "Bypass menus and start deterministic Endless Pitch.", "params": {"seed": {"type": "integer"}, "pitcher": {"type": "integer", "minimum": 1, "maximum": 10}}},
			"start_versus": {"description": "Bypass menus and start a deterministic versus game.", "params": {"seed": {"type": "integer"}, "innings": {"type": "integer", "enum": [3, 6, 9]}, "difficulty": {"type": "number", "minimum": 0.0, "maximum": 1.0}, "player_team": {"type": "integer", "minimum": 1, "maximum": 8}, "cpu_team": {"type": "integer", "minimum": 1, "maximum": 8}}},
			"rematch": {"description": "Restart the current mode with a fresh deterministic epoch.", "params": {}},
			"exit_to_menu": {"description": "Cleanly tear down the current session and return to Landing.", "params": {}},
			"select_pitcher": {"description": "Choose one of the ten real-data pitcher arsenals.", "params": {"index": {"type": "integer", "minimum": 1, "maximum": 10}}, "required": ["index"]},
			"select_pitch": {"description": "Select one of the pitcher's five real arsenal slots.", "params": {"slot": {"type": "integer", "minimum": 1, "maximum": 5}}, "required": ["slot"]},
			"aim": {"description": "Set normalized screen-space aim.", "params": {"x": {"type": "number", "minimum": -1.0, "maximum": 1.0}, "y": {"type": "number", "minimum": -1.0, "maximum": 1.0}}, "required": ["x", "y"]},
			"primary": {"description": "Throw or swing according to the current legal phase.", "params": {}},
			"move_fielder": {"description": "Set normalized fielder movement for the next control tick.", "params": {"x": {"type": "number", "minimum": -1.0, "maximum": 1.0}, "y": {"type": "number", "minimum": -1.0, "maximum": 1.0}}, "required": ["x", "y"]},
			"throw_base": {"description": "Throw to home, first, second, or third (0 through 3).", "params": {"base": {"type": "integer", "minimum": 0, "maximum": 3}}, "required": ["base"]},
			"press_throw": {"description": "Begin charging a throw to base 0 through 3.", "params": {"base": {"type": "integer", "minimum": 0, "maximum": 3}}, "required": ["base"]},
			"release_throw": {"description": "Release the charged throw to its selected base.", "params": {"base": {"type": "integer", "minimum": 0, "maximum": 3}}, "required": ["base"]},
			"cycle_fielder": {"description": "Cycle the selected defender.", "params": {}},
			"cycle_runner": {"description": "Cycle the selected offensive runner.", "params": {"direction": {"type": "integer", "enum": [-1, 1]}}, "required": ["direction"]},
			"command_runner": {"description": "Send or return the selected runner toward base 0 through 3.", "params": {"base": {"type": "integer", "minimum": 0, "maximum": 3}}, "required": ["base"]},
			"autoplay": {"description": "Enable or disable deterministic agent autoplay.", "params": {"enabled": {"type": "boolean"}}, "required": ["enabled"]},
			"set_mood": {"description": "Set stadium lighting to day, golden, or night.", "params": {"mood": {"type": "string"}}, "required": ["mood"]},
		},
	}


func _godot_ai_state() -> Dictionary:
	var full_state := sim.snapshot() if sim != null else {}
	var state := _compact_agent_sim_state(full_state)
	state["simulation_legal_actions"] = state.get("legal_actions", [])
	state["legal_actions"] = _legal_agent_intents()
	state["legal_intents"] = state["legal_actions"]
	state["presentation"] = {
		"flow": flow,
		"match_mode": match_mode,
		"shell": shell.snapshot() if shell != null else {},
		"records": save_repository.snapshot() if save_repository != null else {},
		"flow_time": flow_time,
		"selected_pitch": selected_pitch + 1,
		"selected_pitcher": selected_pitcher_index + 1,
		"pitcher": sim.user_pitcher() if sim != null and sim.replica_enabled() else {},
		"aim": [aim.x, aim.y],
		"pitch_progress": clampf(pitch_elapsed / _pitch_flight_seconds(), 0.0, 1.0) if flow == "pitch_flight" else 0.0,
		"swing_started": swing_started,
		"autoplay": _autoplay,
		"mood": ["day", "golden", "night"][_mood_index],
		"camera_mode": broadcast_camera.mode if broadcast_camera != null else "",
		"cast": {
			"pitcher": {
				"throws": (defenders.get("pitcher") as BallplayerActor).get_throwing_hand() if defenders.has("pitcher") else "",
				"number": (defenders.get("pitcher") as BallplayerActor).get_jersey_number() if defenders.has("pitcher") else 0,
			},
			"batter": _current_batter_identity.duplicate(true),
		},
		"live_play": live_play.state() if live_play != null else {},
		"haptics": haptic_director.diagnostic_state() if haptic_director != null else {},
	}
	return state


func _compact_agent_sim_state(full_state: Dictionary) -> Dictionary:
	var state := full_state.duplicate(true)
	var raw_staffs: Dictionary = full_state.get("staffs", {})
	var staff_summary := {}
	for side in ["away", "home"]:
		var pitchers: Array = raw_staffs.get(side, [])
		var compact_pitchers: Array[Dictionary] = []
		for pitcher_value in pitchers:
			var pitcher: Dictionary = pitcher_value
			compact_pitchers.append({
				"id": int(pitcher.get("id", -1)),
				"name": String(pitcher.get("name", "")),
				"throws": String(pitcher.get("throws", "R")),
			})
		staff_summary[side] = compact_pitchers
	state["staffs"] = staff_summary

	var raw_lineups: Dictionary = full_state.get("lineups", {})
	var batter_indices: Dictionary = full_state.get("batter_index", {})
	var lineup_summary := {}
	for side in ["away", "home"]:
		var lineup: Array = raw_lineups.get(side, [])
		var current := {}
		if not lineup.is_empty():
			current = (lineup[posmod(int(batter_indices.get(side, 0)), lineup.size())] as Dictionary).duplicate(true)
		lineup_summary[side] = {"size": lineup.size(), "current": current}
	state["lineups"] = lineup_summary

	var raw_conditions: Dictionary = full_state.get("pitcher_conditions", {})
	state["pitcher_conditions"] = {
		"away": (raw_conditions.get("away", {}) as Dictionary).duplicate(true),
		"home": (raw_conditions.get("home", {}) as Dictionary).duplicate(true),
	}
	state["recent_events"] = _compact_agent_events(full_state.get("recent_events", []), 8)
	state["manager_events"] = _compact_agent_events(full_state.get("manager_events", []), 8)
	var last_result: Dictionary = full_state.get("last_result", {}).duplicate(true)
	last_result.erase("model_result")
	if last_result.get("trajectory", null) is Dictionary:
		var trajectory: Dictionary = last_result.trajectory
		last_result["trajectory"] = {
			"exit_velocity_mph": float(trajectory.get("exit_velocity_mph", 0.0)),
			"launch_angle_deg": float(trajectory.get("launch_angle_deg", 0.0)),
			"spray_angle_deg": float(trajectory.get("spray_angle_deg", 0.0)),
			"carry_ft": float(trajectory.get("carry_ft", 0.0)),
			"classification_hint": String(trajectory.get("classification_hint", "")),
		}
	state["last_result"] = last_result
	state["semantic_compaction"] = {
		"staffs": int((raw_staffs.get("away", []) as Array).size() + (raw_staffs.get("home", []) as Array).size()),
		"lineups": int((raw_lineups.get("away", []) as Array).size() + (raw_lineups.get("home", []) as Array).size()),
		"recent_event_limit": 8,
	}
	return state


func _compact_agent_events(value: Variant, limit: int) -> Array[Dictionary]:
	var source: Array = value if value is Array else []
	var result: Array[Dictionary] = []
	var first := maxi(0, source.size() - limit)
	for index in range(first, source.size()):
		var event: Dictionary = source[index]
		var compact := {}
		for key in ["seq", "type", "inning", "half", "phase", "pitch_serial", "outcome", "classification", "runs", "outs_recorded", "pitcher_id", "pitcher_name", "name"]:
			if event.has(key):
				compact[key] = event[key]
		result.append(compact)
	return result


func _legal_agent_intents() -> Array[String]:
	var legal: Array[String] = ["start_match", "start_endless", "start_versus", "exit_to_menu", "autoplay", "set_mood"]
	if flow in ["landing", "pitcher_select"]:
		legal.append("select_pitcher")
	if flow in ["landing", "pitcher_select", "team_select", "game_over"]:
		legal.append("primary")
	if flow == "ready" or (flow in ["windup", "pitch_flight"] and sim != null and sim.is_user_batting()):
		legal.append("aim")
	if flow == "ready" and sim != null and sim.is_user_pitching():
		legal.append("select_pitch")
		legal.append("primary")
	elif flow == "pitch_flight" and sim != null and sim.is_user_batting():
		legal.append("primary")
	if flow == "live_play" and sim != null and sim.is_user_fielding():
		legal.append("move_fielder")
		legal.append("cycle_fielder")
		var live_state := live_play.state()
		if String(live_state.get("phase", "")) == "possession":
			if bool(live_state.get("throw_charging", false)):
				legal.append("release_throw")
			else:
				legal.append("throw_base")
				legal.append("press_throw")
	elif flow == "live_play" and sim != null and sim.is_user_batting():
		legal.append("cycle_runner")
		legal.append("command_runner")
	if flow == "game_over":
		legal.append("rematch")
	return legal


func _godot_ai_apply_intent(name: String, params: Dictionary) -> Dictionary:
	var allowed: Dictionary = _godot_ai_describe().intents
	if not allowed.has(name):
		return {"accepted": false, "reason": "unsupported_intent"}
	var params_error := _validate_agent_intent(name, params)
	if not params_error.is_empty():
		return {"accepted": false, "reason": params_error}
	var legal_intents := _legal_agent_intents()
	if name not in legal_intents:
		return {"accepted": false, "reason": "intent_not_legal_in_current_state", "flow": flow, "legal_intents": legal_intents}
	if _intent_queue.size() >= 64:
		return {"accepted": false, "reason": "intent_queue_full"}
	_intent_queue.append({"name": name, "params": params.duplicate(true)})
	return {"accepted": true, "queued": _intent_queue.size(), "flow": flow}


func _validate_agent_intent(intent: String, params: Dictionary) -> String:
	var allowed_keys: Array[String] = []
	var required_keys: Array[String] = []
	match intent:
		"start_match":
			allowed_keys = ["seed", "innings", "difficulty"]
			if params.has("seed") and (not _is_integral_int32(params.seed) or absf(float(params.seed)) > 2147483647.0):
				return "seed_must_be_a_32_bit_integer"
			if params.has("innings") and (not _is_integral_int32(params.innings) or int(params.innings) < 1 or int(params.innings) > 9):
				return "innings_out_of_range"
			if params.has("difficulty") and not _number_in_range(params.difficulty, 0.0, 1.0):
				return "difficulty_out_of_range"
		"start_endless":
			allowed_keys = ["seed", "pitcher"]
			if params.has("seed") and not _is_integral_int32(params.seed):
				return "seed_must_be_a_32_bit_integer"
			if params.has("pitcher") and (not _is_integral_int32(params.pitcher) or int(params.pitcher) < 1 or int(params.pitcher) > 10):
				return "pitcher_index_out_of_range"
		"start_versus":
			allowed_keys = ["seed", "innings", "difficulty", "player_team", "cpu_team"]
			if params.has("seed") and not _is_integral_int32(params.seed):
				return "seed_must_be_a_32_bit_integer"
			if params.has("innings") and (not _is_integral_int32(params.innings) or int(params.innings) not in [3, 6, 9]):
				return "innings_must_be_3_6_or_9"
			if params.has("difficulty") and not _number_in_range(params.difficulty, 0.0, 1.0):
				return "difficulty_out_of_range"
			for team_key in ["player_team", "cpu_team"]:
				if params.has(team_key) and (not _is_integral_int32(params[team_key]) or int(params[team_key]) < 1 or int(params[team_key]) > 8):
					return "team_index_out_of_range"
			if params.has("player_team") != params.has("cpu_team"):
				return "both_team_indices_required"
			if params.has("player_team") and int(params.player_team) == int(params.cpu_team):
				return "teams_must_be_distinct"
		"select_pitcher":
			allowed_keys = ["index"]
			required_keys = ["index"]
			if not _is_integral_int32(params.get("index")) or int(params.get("index", 0)) < 1 or int(params.get("index", 0)) > 10:
				return "pitcher_index_out_of_range"
			if flow not in ["landing", "pitcher_select"]:
				return "pitcher_selection_not_available"
		"select_pitch":
			allowed_keys = ["slot"]
			required_keys = ["slot"]
			if not _is_integral_int32(params.get("slot")) or int(params.get("slot", 0)) < 1 or int(params.get("slot", 0)) > 5:
				return "slot_out_of_range"
		"aim", "move_fielder":
			allowed_keys = ["x", "y"]
			required_keys = ["x", "y"]
			if not _number_in_range(params.get("x"), -1.0, 1.0) or not _number_in_range(params.get("y"), -1.0, 1.0):
				return "axis_out_of_range"
		"primary", "cycle_fielder", "rematch", "exit_to_menu":
			if not params.is_empty():
				return "intent_takes_no_params"
		"throw_base", "press_throw", "release_throw", "command_runner":
			allowed_keys = ["base"]
			required_keys = ["base"]
			if not _is_integral_int32(params.get("base")) or int(params.get("base", -1)) < 0 or int(params.get("base", -1)) > 3:
				return "base_out_of_range"
		"cycle_runner":
			allowed_keys = ["direction"]
			required_keys = ["direction"]
			if not _is_integral_int32(params.get("direction")) or int(params.get("direction", 0)) not in [-1, 1]:
				return "runner_direction_must_be_minus_or_plus_one"
		"autoplay":
			allowed_keys = ["enabled"]
			required_keys = ["enabled"]
			if typeof(params.get("enabled")) != TYPE_BOOL:
				return "enabled_must_be_boolean"
		"set_mood":
			allowed_keys = ["mood"]
			required_keys = ["mood"]
			if typeof(params.get("mood")) != TYPE_STRING or String(params.get("mood", "")) not in ["day", "golden", "night"]:
				return "unsupported_mood"
	for key in params:
		if String(key) not in allowed_keys:
			return "unknown_param"
	for key in required_keys:
		if not params.has(key):
			return "missing_param"
	return ""


func _number_in_range(value: Variant, minimum: float, maximum: float) -> bool:
	return (
		(typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT)
		and is_finite(float(value))
		and float(value) >= minimum
		and float(value) <= maximum
	)


func _is_integral_int32(value: Variant) -> bool:
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		return false
	var number := float(value)
	return (
		is_finite(number)
		and floor(number) == number
		and number >= -2147483648.0
		and number <= 2147483647.0
	)


func _drain_intents() -> void:
	while not _intent_queue.is_empty():
		var intent: Dictionary = _intent_queue.pop_front()
		var name := String(intent.name)
		var params: Dictionary = intent.params
		match name:
			"start_match":
				_start_match(int(params.get("seed", 20260710)), int(params.get("innings", 3)), float(params.get("difficulty", 0.55)))
			"start_endless":
				_start_endless(int(params.get("seed", 20260710)), int(params.get("pitcher", selected_pitcher_index + 1)) - 1)
			"start_versus":
				_start_versus(int(params.get("seed", 20260710)), int(params.get("innings", 3)), float(params.get("difficulty", 0.55)), int(params.get("player_team", 1)) - 1, int(params.get("cpu_team", 2)) - 1)
			"rematch":
				_rematch()
			"exit_to_menu":
				_exit_to_menu()
			"select_pitcher":
				_select_pitcher_index(int(params.get("index", 1)) - 1)
			"select_pitch":
				_select_pitch(clampi(int(params.get("slot", 1)) - 1, 0, C.PITCHES.size() - 1))
			"aim":
				aim = Vector2(clampf(float(params.get("x", 0.0)), -1, 1), clampf(float(params.get("y", 0.0)), -1, 1))
			"primary":
				if flow in ["landing", "pitcher_select", "team_select", "game_over"]: _apply_shell_command(shell.confirm())
				elif flow == "ready" and sim.is_user_pitching(): _begin_pitch()
				elif flow == "pitch_flight" and sim.is_user_batting(): _trigger_swing()
			"move_fielder":
				_semantic_field_move = Vector2(float(params.get("x", 0.0)), float(params.get("y", 0.0)))
				_semantic_field_move_ticks = 1
			"throw_base":
				live_play.request_throw(clampi(int(params.get("base", 1)), 0, 3))
			"press_throw":
				live_play.press_throw(clampi(int(params.get("base", 1)), 0, 3))
			"release_throw":
				live_play.release_throw(clampi(int(params.get("base", 1)), 0, 3))
			"cycle_fielder":
				live_play.cycle_fielder()
			"cycle_runner":
				live_play.cycle_runner(int(params.get("direction", 1)))
			"command_runner":
				live_play.command_selected_runner(clampi(int(params.get("base", 1)), 0, 3))
			"autoplay":
				_autoplay = bool(params.get("enabled", true))
				if _autoplay and flow in ["landing", "pitcher_select", "team_select"]: _start_match()
			"set_mood":
				var mood := String(params.get("mood", "day"))
				if mood in ["day", "golden", "night"]:
					_mood_index = ["day", "golden", "night"].find(mood)
					_set_visual_mood(mood)


func _ensure_input_actions() -> void:
	var bindings := {
		"pix_up": KEY_W,
		"pix_down": KEY_S,
		"pix_left": KEY_A,
		"pix_right": KEY_D,
		"pix_primary": KEY_SPACE,
		"pix_start": KEY_ENTER,
		"pix_pitch_1": KEY_1,
		"pix_pitch_2": KEY_2,
		"pix_pitch_3": KEY_3,
		"pix_pitch_4": KEY_4,
		"pix_pitch_5": KEY_5,
		"pix_cycle": KEY_Q,
		"pix_restart": KEY_R,
		"pix_mood": KEY_M,
		"pix_back": KEY_ESCAPE,
	}
	for action_value in bindings:
		var action := StringName(action_value)
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		var event := InputEventKey.new()
		event.physical_keycode = bindings[action_value]
		InputMap.action_add_event(action, event)
	var navigation_bindings := {
		"pix_up": KEY_UP,
		"pix_down": KEY_DOWN,
		"pix_left": KEY_LEFT,
		"pix_right": KEY_RIGHT,
	}
	for action_value in navigation_bindings:
		var event := InputEventKey.new()
		event.physical_keycode = navigation_bindings[action_value]
		InputMap.action_add_event(StringName(action_value), event)
