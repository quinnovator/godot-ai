extends SceneTree

const Trajectory = preload("res://presentation/pitch_trajectory.gd")

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var feet := Trajectory.FEET_TO_WORLD
	var start := Vector3(0.46, 1.56, 0.0)
	var finish := Vector3(0.25 * feet, 0.08 + 2.4 * feet, 18.0)
	var path := {
		"plate_ft": [0.25, 0.0, 2.4],
		"tunnel_ft": [-0.10, 0.0, 3.8],
		"break_ft": [-0.6, 0.4],
	}
	_check(Trajectory.sample(start, finish, path, 0.0) == start, "trajectory moved its release endpoint")
	_check(Trajectory.sample(start, finish, path, 1.0) == finish, "trajectory moved its plate endpoint")
	var tunnel := Trajectory.sample(start, finish, path, Trajectory.TUNNEL_FRACTION)
	_check(tunnel.is_equal_approx(Vector3(-0.10 * feet, 0.08 + 3.8 * feet, lerpf(start.z, finish.z, Trajectory.TUNNEL_FRACTION))), "trajectory missed its semantic tunnel point: %s" % tunnel)

	var previous_z := start.z
	for index in range(1, 21):
		var point := Trajectory.sample(start, finish, path, float(index) / 20.0)
		_check(point.z > previous_z, "trajectory reversed field depth at sample %d" % index)
		_check(_finite(point), "trajectory produced a non-finite sample at %d" % index)
		previous_z = point.z

	var linear_path := {"plate_ft": [0.25, 0.0, 2.4], "break_ft": [0.0, 0.0]}
	for progress in [0.2, 0.5, 0.8]:
		_check(
			Trajectory.sample(start, finish, linear_path, progress).is_equal_approx(start.lerp(finish, progress)),
			"zero-break trajectory introduced an artificial arc at %.1f" % progress
		)

	if _failures.is_empty():
		print("PIXIBALL_PITCH_TRAJECTORY_OK release=tunnel=plate depth=monotonic artificial_arc=absent")
		quit(0)
		return
	for failure in _failures:
		push_error("PIXIBALL_PITCH_TRAJECTORY: %s" % failure)
	quit(1)


func _finite(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
