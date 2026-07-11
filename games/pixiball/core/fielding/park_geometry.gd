class_name PixiballParkGeometry
extends RefCounted

## Frozen Citizens Bank Park geometry from the original PixCore simulation.
##
## All values are feet in field coordinates: +x points toward first base,
## +y points from home toward center field, and +z is up. Presentation code is
## expected to perform its own field-to-world transform. Fence segments are
## straight in field XY; they are deliberately not interpolated as radial arcs.

const PI_VALUE := 3.141592653589793
const RAD_PER_DEG := PI_VALUE / 180.0

const BASE_PATH_FT := 90.0
const DIAMOND_LEG_FT := 90.0 / 1.4142135623730951
# Shared presentation boundary. Keeping these factors with the authoritative
# fence profile prevents the rendered wall and live-ball classifier drifting.
const HORIZONTAL_WORLD_PER_FOOT := 0.155
const VERTICAL_WORLD_PER_FOOT := 0.3048
const BASES := [
	[0.0, 0.0],
	[DIAMOND_LEG_FT, DIAMOND_LEG_FT],
	[0.0, 2.0 * DIAMOND_LEG_FT],
	[-DIAMOND_LEG_FT, DIAMOND_LEG_FT],
]
const MOUND := [0.0, 60.5]

## Each row is [spray degrees, ray distance feet, wall-top feet].
const FENCE_POSTS := [
	[-45.0, 329.0, 10.5],
	[-26.0, 374.0, 10.5],
	[-15.5, 385.0, 10.5],
	[-14.0, 381.0, 12.7],
	[-8.0, 409.0, 19.0],
	[-3.5, 402.0, 6.0],
	[0.0, 401.0, 6.0],
	[4.5, 399.0, 6.0],
	[21.0, 369.0, 13.25],
	[45.0, 330.0, 13.25],
]

## Frozen EFielderId order and standard defensive posts/sprint speeds.
const FIELDER_IDS := ["P", "C", "1B", "2B", "SS", "3B", "LF", "CF", "RF"]
const FIELDER_POSTS := [
	[0.0, 60.5],
	[0.0, -5.0],
	[62.0, 84.0],
	[34.0, 138.0],
	[-34.0, 138.0],
	[-62.0, 84.0],
	[-134.0, 263.0],
	[0.0, 315.0],
	[134.0, 263.0],
]
const FIELDER_SPEED_FPS := [22.0, 21.0, 24.0, 26.0, 26.0, 24.0, 27.0, 27.5, 27.0]


## Where a ray from home at `spray_deg` intersects the straight fence
## polyline. Angles outside fair territory clamp to the foul poles, matching
## PixPark::FenceDist.
static func fence_distance(spray_deg: float) -> float:
	var spray := _clamped_spray(spray_deg)
	var segment := _fence_segment(spray)
	var a: Array = FENCE_POSTS[segment]
	var b: Array = FENCE_POSTS[segment + 1]
	var a_angle := float(a[0]) * RAD_PER_DEG
	var b_angle := float(b[0]) * RAD_PER_DEG
	var ax := sin(a_angle) * float(a[1])
	var ay := cos(a_angle) * float(a[1])
	var bx := sin(b_angle) * float(b[1])
	var by := cos(b_angle) * float(b[1])
	var ex := bx - ax
	var ey := by - ay
	var direction_angle := spray * RAD_PER_DEG
	var dx := sin(direction_angle)
	var dy := cos(direction_angle)
	return (ax * ey - ay * ex) / (dx * ey - dy * ex)


## PixCore compatibility spelling.
static func fence_dist(spray_deg: float) -> float:
	return fence_distance(spray_deg)


## Wall-top height, linearly interpolated between the two posts spanning the
## requested spray angle.
static func fence_height(spray_deg: float) -> float:
	var spray := _clamped_spray(spray_deg)
	var segment := _fence_segment(spray)
	var a: Array = FENCE_POSTS[segment]
	var b: Array = FENCE_POSTS[segment + 1]
	var u := (spray - float(a[0])) / (float(b[0]) - float(a[0]))
	return float(a[2]) + (float(b[2]) - float(a[2])) * u


## Fair territory is in front of the plate and between the 45-degree lines.
static func is_fair(x_ft: float, y_ft: float) -> bool:
	return y_ft > 0.0 and absf(x_ft) <= y_ft


static func spray_degrees(x_ft: float, y_ft: float) -> float:
	return atan2(x_ft, y_ft) / RAD_PER_DEG


static func fence_point(spray_deg: float) -> PackedFloat64Array:
	var spray := _clamped_spray(spray_deg)
	var distance := fence_distance(spray)
	var angle := spray * RAD_PER_DEG
	return PackedFloat64Array([sin(angle) * distance, cos(angle) * distance])


## Serializable profile for tools, scene builders, and agent inspection.
static func fence_profile() -> Array[Dictionary]:
	var profile: Array[Dictionary] = []
	for post_value in FENCE_POSTS:
		var post: Array = post_value
		var angle := float(post[0]) * RAD_PER_DEG
		profile.append({
			"spray_deg": float(post[0]),
			"distance_ft": float(post[1]),
			"height_ft": float(post[2]),
			"x_ft": sin(angle) * float(post[1]),
			"y_ft": cos(angle) * float(post[1]),
		})
	return profile


static func base_position(index: int) -> PackedFloat64Array:
	var point: Array = BASES[clampi(index, 0, BASES.size() - 1)]
	return PackedFloat64Array([float(point[0]), float(point[1])])


static func fielder_post(id: Variant) -> PackedFloat64Array:
	var index := _fielder_index(id)
	var point: Array = FIELDER_POSTS[index]
	return PackedFloat64Array([float(point[0]), float(point[1])])


static func fielder_speed(id: Variant) -> float:
	return float(FIELDER_SPEED_FPS[_fielder_index(id)])


static func is_outfield(id: Variant) -> bool:
	return _fielder_index(id) >= 6


static func dist_2d(a: Variant, b: Variant) -> float:
	var pa := _xy(a)
	var pb := _xy(b)
	var dx := pa[0] - pb[0]
	var dy := pa[1] - pb[1]
	return sqrt(dx * dx + dy * dy)


static func _clamped_spray(spray_deg: float) -> float:
	return maxf(-45.0, minf(45.0, spray_deg))


static func _fence_segment(spray_deg: float) -> int:
	for index in range(FENCE_POSTS.size() - 2):
		var next_post: Array = FENCE_POSTS[index + 1]
		if spray_deg <= float(next_post[0]):
			return index
	return FENCE_POSTS.size() - 2


static func _fielder_index(id: Variant) -> int:
	if typeof(id) == TYPE_INT or typeof(id) == TYPE_FLOAT:
		return clampi(int(id), 0, FIELDER_IDS.size() - 1)
	var normalized := String(id).strip_edges().to_upper()
	match normalized:
		"P", "PITCHER":
			return 0
		"C", "CATCHER":
			return 1
		"1B", "B1", "FIRST", "FIRST_BASE":
			return 2
		"2B", "B2", "SECOND", "SECOND_BASE":
			return 3
		"SS", "SHORT", "SHORTSTOP":
			return 4
		"3B", "B3", "THIRD", "THIRD_BASE":
			return 5
		"LF", "LEFT", "LEFT_FIELD":
			return 6
		"CF", "CENTER", "CENTER_FIELD":
			return 7
		"RF", "RIGHT", "RIGHT_FIELD":
			return 8
	return 0


static func _xy(value: Variant) -> PackedFloat64Array:
	if value is Vector2:
		return PackedFloat64Array([float(value.x), float(value.y)])
	if value is Vector3:
		return PackedFloat64Array([float(value.x), float(value.y)])
	if value is Array or value is PackedFloat64Array or value is PackedFloat32Array:
		if value.size() >= 2:
			return PackedFloat64Array([float(value[0]), float(value[1])])
	if value is Dictionary:
		return PackedFloat64Array([float(value.get("x", 0.0)), float(value.get("y", 0.0))])
	return PackedFloat64Array([0.0, 0.0])
