extends SceneTree

const Park = preload("res://core/fielding/park_geometry.gd")

var _failures: Array[String] = []


func _init() -> void:
	_check(Park.FENCE_POSTS.size() == 10, "Citizens Bank Park must retain all ten fence posts")
	for index in range(Park.FENCE_POSTS.size()):
		var post: Array = Park.FENCE_POSTS[index]
		var spray := float(post[0])
		var distance := float(post[1])
		var height := float(post[2])
		_check(_near(Park.fence_distance(spray), distance, 0.000000000001),
			"fence ray should meet post %d at its frozen distance" % index)
		_check(_near(Park.fence_height(spray), height, 0.000000000001),
			"post %d should retain its frozen wall height" % index)

	_check(_near(Park.fence_distance(-90.0), 329.0, 0.000000000001),
		"left-of-pole fence queries should clamp to -45 degrees")
	_check(_near(Park.fence_distance(90.0), 330.0, 0.000000000001),
		"right-of-pole fence queries should clamp to +45 degrees")
	_check(_near(Park.fence_height(-8.0), 19.0, 0.000000000001),
		"The Angle should retain its 19-foot wall peak")
	_check(_near(Park.fence_height(0.0), 6.0, 0.000000000001),
		"dead center should retain the low six-foot wall")
	_check(Park.is_fair(40.0, 40.0), "the foul line itself is fair")
	_check(Park.is_fair(-40.0, 40.0), "both foul lines should use the same inclusive boundary")
	_check(not Park.is_fair(40.01, 40.0), "a point beyond the first-base line is foul")
	_check(not Park.is_fair(0.0, 0.0), "home plate is not in forward fair territory")

	var first := Park.base_position(1)
	var second := Park.base_position(2)
	_check(_near(first[0], Park.DIAMOND_LEG_FT, 0.0) and _near(first[1], Park.DIAMOND_LEG_FT, 0.0),
		"first base should preserve the exact 90/sqrt(2) geometry")
	_check(_near(second[1], 2.0 * Park.DIAMOND_LEG_FT, 0.0),
		"second base should preserve the exact diamond diagonal")
	_check(Park.is_outfield("LF") and Park.is_outfield(7) and not Park.is_outfield("SS"),
		"fielder IDs should preserve the original outfield partition")
	_check(_near(Park.fielder_speed("CF"), 27.5, 0.0),
		"center-field sprint speed should retain the original value")
	_check(Park.fence_profile().size() == 10, "agent-facing fence profile should serialize every post")
	_check(_near(Park.HORIZONTAL_WORLD_PER_FOOT, 0.155, 0.0), "rendered fence and live-ball physics must share horizontal scale")
	_check(_near(Park.VERTICAL_WORLD_PER_FOOT, 0.3048, 0.0), "rendered fence and live-ball physics must share vertical scale")

	var exit_code := 0
	if _failures.is_empty():
		print("PIXIBALL_PARK_GEOMETRY_OK posts=10")
	else:
		for failure in _failures:
			push_error(failure)
		exit_code = 1
	quit(exit_code)


func _near(actual: float, expected: float, tolerance: float) -> bool:
	return absf(actual - expected) <= tolerance


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
