extends SceneTree

const BaseballVisualScript = preload("res://presentation/baseball_visual.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var ball := BaseballVisualScript.new()
	stage.add_child(ball)
	await process_frame
	await process_frame

	ball.set_active(true)
	ball.use_pitch_ball()
	ball.begin_pitch_motion(2400.0, 180.0, false)
	ball.set_ball_position(Vector3.ZERO)
	ball.set_ball_position(Vector3(0.0, 0.0, 1.0), 1.0 / 60.0)
	var length_60 := _trail_length(ball)
	_check(ball.trail.size() == 4, "motion blur must use four tapered segments")
	_check(length_60 > 0.0 and length_60 <= ball.MAX_TRAIL_LENGTH + 0.001, "motion blur must stay within its shutter-length cap")
	for index in range(ball.trail.size()):
		var segment := ball.trail[index] as MeshInstance3D
		_check(segment.visible and segment.mesh is CylinderMesh, "active blur segments must be visible cylinders")
		if index > 0:
			var prior := (ball.trail[index - 1] as MeshInstance3D).mesh as CylinderMesh
			var current := segment.mesh as CylinderMesh
			_check(current.top_radius < prior.top_radius, "motion blur must taper away from the baseball")

	ball.begin_pitch_motion(2400.0, 180.0, false)
	ball.set_ball_position(Vector3.ZERO)
	ball.set_ball_position(Vector3(0.0, 0.0, 2.0), 1.0 / 30.0)
	var length_30 := _trail_length(ball)
	_check(is_equal_approx(length_60, length_30), "equal velocity must produce equal blur length at different frame rates")

	ball.use_play_ball()
	_check(_all_trail_hidden(ball), "fielding view must disable the pitch streak")
	ball.set_active(false)
	_check(not ball.shadow.visible and _all_trail_hidden(ball), "inactive baseball must clear shadow and streak state")

	var exit_code := 0
	if failures.is_empty():
		print("PIXIBALL_BASEBALL_VISUAL_OK shutter=stable trail=tapered spin=time_based")
	else:
		for failure in failures:
			push_error("PIXIBALL_BASEBALL_VISUAL: %s" % failure)
		exit_code = 1
	stage.queue_free()
	await process_frame
	quit(exit_code)


func _trail_length(ball) -> float:
	var total := 0.0
	for segment in ball.trail:
		total += ((segment as MeshInstance3D).mesh as CylinderMesh).height
	return total


func _all_trail_hidden(ball) -> bool:
	for segment in ball.trail:
		if (segment as MeshInstance3D).visible:
			return false
	return true


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
