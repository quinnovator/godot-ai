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
	game._start_endless(81173, 4)
	game._autoplay = true
	var ticks := 0
	var saw_live_play := false
	var changed_sides := false
	# Exercise several real presentation pitches and at least one batted ball.
	# The EndlessSim suite pins the full three-run outcome; this suite then
	# forces that already-tested boundary to keep the shell gate fast.
	while ticks < 6_000:
		game._physics_process(1.0 / 60.0)
		if game.live_play.active:
			game.live_play._physics_process(1.0 / 60.0)
		var state: Dictionary = game.sim.snapshot()
		saw_live_play = saw_live_play or String(state.phase) == "live_play"
		changed_sides = changed_sides or String(state.half) != "top"
		ticks += 1
		if saw_live_play and not game.live_play.active and int(state.pitch_serial) >= 4:
			break
	game.live_play.reset()
	game.sim._score["away"] = 3
	game.sim._finalize_if_limit_reached()
	game.flow = "result"
	game._advance_result()
	var final_state: Dictionary = game.sim.snapshot()
	var endless: Dictionary = final_state.get("endless", {})
	_check(game.flow == "game_over", "Endless presentation must reach its Final screen")
	_check(int(endless.get("runs_allowed", -1)) == 3, "Endless must end exactly at the three-run limit")
	_check(int(endless.get("pitch_count", 0)) > 0, "Endless Final must expose mode stats")
	_check(saw_live_play, "Endless must exercise real live-ball fielding")
	_check(not changed_sides, "Endless must never switch the user to batting")
	_check(game.hud.final_layer.visible, "Endless completion must switch HUD to Final")
	var exit_code := 0
	if failures.is_empty():
		print("PIXIBALL_ENDLESS_PRESENTATION_OK ticks=%d k=%d pitches=%d" % [ticks, int(endless.get("strikeouts", 0)), int(endless.get("pitch_count", 0))])
	else:
		for failure in failures:
			push_error("PIXIBALL_ENDLESS_PRESENTATION: %s" % failure)
		exit_code = 1
	game.queue_free()
	for frame in range(3):
		await process_frame
	quit(exit_code)


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
