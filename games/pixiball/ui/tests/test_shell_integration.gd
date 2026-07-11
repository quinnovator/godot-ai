extends SceneTree

const MainScene = preload("res://main.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MainScene.instantiate()
	root.add_child(game)
	await process_frame
	game.set_physics_process(false)
	game.live_play.set_physics_process(false)
	game.audio_director.muted = true
	game.headless_fast_forward = true
	game.hud.set_stamina(0.02, "gassed")
	game.hud._process(0.70)
	_check(game.hud.stamina_label.modulate.a < 1.0, "GASSED stamina state must visibly blink")
	game.hud.set_stamina(1.0, "fresh")
	game.hud._process(0.01)
	_check(is_equal_approx(game.hud.stamina_label.modulate.a, 1.0), "fresh stamina must restore full HUD opacity")
	_check(game.flow == "landing", "main must boot into Landing")
	_check(game.hud.landing_layer.visible, "Landing layer must be visible at boot")
	var intents: Dictionary = game._godot_ai_describe().intents
	for name in ["start_match", "start_endless", "start_versus", "rematch", "exit_to_menu"]:
		_check(intents.has(name), "agent contract must advertise %s" % name)
	_check(game._validate_agent_intent("start_versus", {"player_team": 1.0, "cpu_team": 1.0}) == "teams_must_be_distinct", "agent bypass must reject identical teams")

	var endless_accept: Dictionary = game._godot_ai_apply_intent("start_endless", {"seed": 7001.0, "pitcher": 3.0})
	_check(bool(endless_accept.accepted), "integral JSON numbers must start Endless")
	game._drain_intents()
	var endless_state: Dictionary = game.sim.snapshot()
	_check(game.match_mode == "endless" and String(endless_state.get("mode", "")) == "endless", "Endless bypass must instantiate dedicated sim")
	_check(int(game.selected_pitcher_index) == 2 and game.flow == "ready", "Endless bypass must choose requested pitcher and reach Game")
	var endless_pitcher := game.defenders.get("pitcher") as BallplayerActor
	_check(endless_pitcher.get_throwing_hand() == "left", "Cole Ragans must render as a left-handed pitcher")
	_check(endless_pitcher.get_jersey_number() == 55, "selected pitcher must carry the live roster number")
	var endless_lineup: Array = endless_state.lineups.away
	var expected_batter_hand := "left" if String(endless_lineup[0].stand).begins_with("L") else "right"
	_check(game.batter.get_batting_side() == expected_batter_hand, "batter visual must follow lineup handedness")
	_check(game._validate_agent_intent("select_pitcher", {"index": 1.0}) == "pitcher_selection_not_available", "pitcher selection must not reconfigure a live at-bat")
	_check(not bool(game._godot_ai_apply_intent("throw_base", {"base": 1}).accepted), "phase-inappropriate intents must be rejected instead of queued as no-ops")
	_check("primary" in game._godot_ai_state().legal_actions, "agent state must expose declared presentation intents instead of internal sim methods")
	_check("create_user_pitch" in game._godot_ai_state().simulation_legal_actions, "agent state should retain internal sim actions under an explicit diagnostic key")
	game.flow = "windup"
	_check("aim" not in game._godot_ai_state().legal_actions, "a released user pitch must not advertise no-op aim intents")
	game.flow = "ready"
	var condition_probe := {"pitcher_conditions": {"home": {"stamina_fraction": 0.8}, "away": {"stamina_fraction": 0.3}}}
	condition_probe["half"] = "top"
	_check(is_equal_approx(float(game._hud_pitcher_condition(condition_probe).stamina_fraction), 0.8), "top half HUD must display the home pitcher condition")
	condition_probe["half"] = "bottom"
	_check(is_equal_approx(float(game._hud_pitcher_condition(condition_probe).stamina_fraction), 0.3), "bottom half HUD must display the away pitcher condition")
	var endless_sim_before: PixiballSim = game.sim
	var epoch_before := int(game.sim.snapshot().get("epoch", 0))
	game._rematch()
	_check(game.sim == endless_sim_before and String(game.sim.snapshot().get("mode", "")) == "endless", "Endless rematch must use the sim retry path instead of recreating the run")
	_check(int(game.sim.snapshot().get("epoch", 0)) == epoch_before + 1, "Endless rematch must advance the retry epoch")

	game._godot_ai_apply_intent("exit_to_menu", {})
	game._drain_intents()
	_check(game.flow == "landing" and game.hud.landing_layer.visible, "exit_to_menu must safely restore Landing")

	var versus_accept: Dictionary = game._godot_ai_apply_intent("start_versus", {"seed": 7002.0, "innings": 6.0, "difficulty": 0.80, "player_team": 2.0, "cpu_team": 7.0})
	_check(bool(versus_accept.accepted), "valid Versus bypass must be accepted")
	game._drain_intents()
	var versus_state: Dictionary = game.sim.snapshot()
	_check(game.match_mode == "versus" and String(versus_state.get("mode", "")) == "versus", "Versus bypass must configure full sim")
	_check(int(versus_state.innings) == 6 and String(versus_state.teams.home.id) == "tigers" and String(versus_state.teams.away.id) == "pennants", "Versus bypass must preserve innings and selected teams")
	_check(String(game.home_team.abbr) == "TIG" and String(game.away_team.abbr) == "PEN", "presentation must use selected team abbreviations")
	var live_home_pitcher: Dictionary = versus_state.active_pitchers.home
	_check(game.defenders.pitcher.get_throwing_hand() == ("left" if String(live_home_pitcher.throws).begins_with("L") else "right"), "versus pitcher visual must follow the drafted live arm")
	_check(String(game._godot_ai_state().presentation.cast.batter.team) == "PEN", "agent state must expose the live visual batter identity")
	var versus_sim_before: PixiballSim = game.sim
	var versus_epoch_before := int(versus_state.epoch)
	game._rematch()
	_check(game.sim == versus_sim_before, "Versus rematch must preserve the configured sim instead of reconstructing epoch zero")
	_check(int(game.sim.snapshot().epoch) == versus_epoch_before + 1, "Versus rematch must advance the deterministic session epoch")

	var exit_code := 0
	if failures.is_empty():
		print("PIXIBALL_SHELL_INTEGRATION_OK endless=true versus=true agent=true")
	else:
		for failure in failures:
			push_error("PIXIBALL_SHELL_INTEGRATION: %s" % failure)
		exit_code = 1
	game.queue_free()
	for frame in range(3):
		await process_frame
	quit(exit_code)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
