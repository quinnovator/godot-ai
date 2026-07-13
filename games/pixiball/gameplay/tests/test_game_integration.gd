extends SceneTree

const MainScene = preload("res://main.tscn")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = MainScene.instantiate()
	root.add_child(game)
	# Let the complete generated hierarchy enter the tree and receive _ready.
	await process_frame
	await process_frame
	var pixel_scene := game.get_node_or_null("PixelScene") as Node2D
	_check(pixel_scene != null, "game must expose the native PixelScene")
	if pixel_scene != null:
		_check(pixel_scene.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "game PixelScene must use nearest filtering")
	var sample_aim := Vector2(0.62, -0.37)
	_check(game._plate_feet_to_aim(game._aim_to_plate_feet(sample_aim)).is_equal_approx(sample_aim), "aim and plate-feet presentation mapping must round-trip")
	_check(game._plate_pitch_world(Vector2(0.0, 1.5)).is_equal_approx(game.broadcast_camera.plate_location_world(0.0, 1.5)), "pitch endpoint and projected strike zone must share one world mapping")
	_check(game.batter is BallplayerActor, "playable batter should use BallplayerActor")
	_check(game.batter.get_model_kind() == "native_pixel_sprite", "playable batter should use the native pixel model")
	_check(not game.batter.is_using_fallback(), "playable batter reported a fallback model")
	_check(is_instance_valid(game.batter.get_pixel_sprite()) and game.batter.get_pixel_sprite().get_parent() == pixel_scene, "playable batter did not attach to PixelScene")
	var batter_grip: Vector3 = game.batter.get_socket_position("bat_grip")
	_check(is_finite(batter_grip.x) and is_finite(batter_grip.y) and is_finite(batter_grip.z), "playable batter should expose a finite simulation bat socket")
	for defender_value in game.defenders.values():
		var defender := defender_value as BallplayerActor
		_check(defender != null, "every playable defender should use BallplayerActor")
		if defender != null:
			_check(defender.get_model_kind() == "native_pixel_sprite", "playable defender should use the native pixel model")
			_check(not defender.is_using_fallback(), "playable defender reported a fallback model")
			_check(is_instance_valid(defender.get_pixel_sprite()) and defender.get_pixel_sprite().get_parent() == pixel_scene, "playable defender did not attach to PixelScene")
			var defender_socket: Vector3 = defender.get_socket_position("throw_hand")
			_check(is_finite(defender_socket.x) and is_finite(defender_socket.y) and is_finite(defender_socket.z), "playable defender should expose a finite simulation throw socket")
	_check(is_instance_valid(game.ball.get_pixel_sprite()) and game.ball.get_pixel_sprite().get_parent() == pixel_scene, "playable baseball did not attach to PixelScene")
	_check(game._validate_agent_intent("start_match", {"seed": 4242.0, "innings": 1.0}).is_empty(), "JSON-RPC integral floats should satisfy integer fields")
	_check(game._validate_agent_intent("select_pitcher", {"index": 1.0}).is_empty(), "JSON-RPC integral pitcher index should be accepted")
	_check(game._validate_agent_intent("select_pitch", {"slot": 5.0}).is_empty(), "JSON-RPC integral pitch slot should be accepted")
	_check(game._validate_agent_intent("throw_base", {"base": 0.0}).is_empty(), "JSON-RPC integral base index should be accepted")
	_check(game._validate_agent_intent("start_match", {"seed": 42.5}) == "seed_must_be_a_32_bit_integer", "fractional seed should be rejected")
	_check(game._validate_agent_intent("start_match", {"seed": INF}) == "seed_must_be_a_32_bit_integer", "non-finite seed should be rejected")
	_check(game._validate_agent_intent("select_pitch", {"slot": 1.5}) == "slot_out_of_range", "fractional pitch slot should be rejected")
	game.set_physics_process(false)
	game.live_play.set_physics_process(false)
	game.headless_fast_forward = true
	game.audio_director.muted = true
	game._start_match(4242, 1, 0.72)
	game._autoplay = true

	var saw_bottom := false
	var saw_live_play := false
	var saw_batting_camera := false
	var saw_fielding_camera := false
	var ready_camera_valid := true
	var ticks := 0
	# The presentation state machines are deterministic and fixed-step. Driving
	# them directly makes this full-game test finish in seconds instead of
	# waiting for wall-clock animation time in CI.
	while ticks < 24_000 and game.flow != "game_over":
		game._physics_process(1.0 / 60.0)
		if game.live_play.active:
			game.live_play._physics_process(1.0 / 60.0)
		var state: Dictionary = game.sim.snapshot()
		saw_bottom = saw_bottom or state.half == "bottom"
		saw_live_play = saw_live_play or state.phase == "live_play"
		saw_batting_camera = saw_batting_camera or game.broadcast_camera.mode == "batting"
		saw_fielding_camera = saw_fielding_camera or game.broadcast_camera.mode == "fielding"
		if game.flow == "ready":
			var expected_camera := "pitching" if state.half == "top" else "batting"
			ready_camera_valid = ready_camera_valid and game.broadcast_camera.mode == expected_camera
		ticks += 1

	var final_state: Dictionary = game.sim.snapshot()
	_check(int(final_state.pitch_serial) >= 6, "a quick game should exercise multiple pitches")
	_check(saw_bottom, "the integration game should exercise user batting")
	_check(saw_live_play, "the integration game should exercise a live batted ball")
	_check(saw_batting_camera and saw_fielding_camera, "the integration game should exercise distinct batting and fielding cameras")
	_check(ready_camera_valid, "every ready phase must restore its role camera after live play")
	_check(game.flow == "game_over", "deterministic autoplay should finish the game")
	_check(String(final_state.winner) in ["home", "away"], "a completed game should name a winner")
	_check(game._godot_ai_describe().intents.has("autoplay"), "semantic gameplay contract should advertise autoplay")
	_check(not bool(game._godot_ai_apply_intent("set_mood", {"mood": "rainbow"}).accepted), "semantic driver should reject invalid declared-intent params")
	_check(not bool(game._godot_ai_apply_intent("primary", {"unexpected": true}).accepted), "zero-param intents should reject unknown fields")
	var observed: Dictionary = game._godot_ai_state()
	_check(observed.has("presentation") and observed.presentation.has("live_play"), "agent observation should include presentation and live-play state")
	game.pitch_intel_panel.clear()
	game._queue_pitch_report({"code": "FF", "name": "Four Seam", "options": []})
	game.flow_time = 0.29
	game._reveal_pending_pitch_report()
	_check(not game.pitch_intel_panel.has_report(), "pitch intelligence must wait for the source 0.3-second reveal beat")
	game.flow_time = 0.31
	game._reveal_pending_pitch_report()
	_check(game.pitch_intel_panel.has_report(), "pitch intelligence must reveal after the 0.3-second beat")
	game._last_published_event_seq = 0
	for index in range(70):
		game.sim._emit("manager_warm", {"pitcher_name": "ARM %d" % index})
	game._publish_new_events()
	var published_before_roll: int = game._last_published_event_seq
	game.sim._emit("manager_substitute", {"pitcher_name": "LATE ARM"})
	game._publish_new_events()
	_check(game._last_published_event_seq > published_before_roll, "HUD publishing must follow event sequence after the bounded history rolls past 64")
	for index in range(10):
		game.hud.push_event("event %d" % index)
	_check(game.hud.event_feed.get_child_count() == 5, "event feed must evict old rows without waiting for a frame")
	game.hud.clear_events()
	game.hud.set_help("TRACK THE RELEASE")
	game.hud.set_field_meter(true, 0.5)
	game.hud.push_event("FIELD IT — PICK A BASE")
	game.hud.push_event("SINGLE")
	game._prepare_result_hud()
	_check(game.hud.help_label.text.is_empty(), "result presentation must clear pitch and fielding controls")
	_check(not game.hud.field_meter.visible, "result presentation must hide the fielding throw meter")
	_check(game.hud.event_feed.get_child_count() == 1 and String(game.hud.event_feed.get_child(0).text) == "SINGLE", "result presentation must remove only the transient fielding prompt")

	var exit_code := 0
	if failures.is_empty():
		print("PIXIBALL_INTEGRATION_OK ticks=%d pitches=%d score=%d-%d winner=%s" % [
			ticks,
			int(final_state.pitch_serial),
			int(final_state.score.home),
			int(final_state.score.away),
			String(final_state.winner),
		])
	else:
		for failure in failures:
			push_error(failure)
		exit_code = 1
	game.queue_free()
	# AudioServer releases active generated WAV playbacks on the following mix
	# turns after their players leave the tree.
	for cleanup_frame in range(3):
		await process_frame
	quit(exit_code)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
