class_name PixiballPitchIntelDiagram
extends Control

## Compact catcher-view diagram for a pitch and the pitch it tunneled from.
##
## Coordinates are semantic baseball feet: +x is catcher's left, z is height.
## The accepted dictionary is intentionally engine/presentation neutral:
##
##     {
##       "release": [x, z], "tunnel": [x, z], "plate": [x, z],
##       "target": [x, z],
##       "previous_tunnel": [x, z], "previous_plate": [x, z],
##       "classification": "frontdoor" | "backdoor" | "corner_paint"
##     }
##
## Points may also be Vector2 or {"x": ..., "z": ...}. Missing points are
## simply omitted, which keeps the widget useful for first-pitch reports.

const PLATE_HALF_FT := 17.0 / 24.0
const ZONE_BOTTOM_FT := 1.5
const ZONE_TOP_FT := 3.5
const VIEW_X := Vector2(-2.35, 2.35)
const VIEW_Z := Vector2(0.65, 6.15)

const S := preload("res://ui/pixiball_style.gd")

const INK := S.SCOREBOARD
const GRID := S.SHADOW_BLUE
const CHALK := S.CHALK
const STEEL := S.STEEL
const TEAL := S.TEAL
const GOLD := S.GOLD
const STITCH := S.STITCH
const PREVIOUS := S.SLATE

var _report: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(132.0, 76.0)


func present(report: Dictionary) -> void:
	_report = report.duplicate(true)
	queue_redraw()


func clear_data() -> void:
	_report.clear()
	queue_redraw()


func has_pitch_data() -> bool:
	return _point(["plate", "actual", "actual_plate"]) != null


func _draw() -> void:
	var plot := Rect2(Vector2(5.0, 4.0), size - Vector2(10.0, 8.0))
	if plot.size.x <= 2.0 or plot.size.y <= 2.0:
		return

	draw_rect(plot, INK, true)
	draw_rect(plot, GRID, false, 1.0)
	_draw_reference_grid(plot)

	var zone_top_left := _map_point(Vector2(-PLATE_HALF_FT, ZONE_TOP_FT), plot)
	var zone_bottom_right := _map_point(Vector2(PLATE_HALF_FT, ZONE_BOTTOM_FT), plot)
	var zone := Rect2(zone_top_left, zone_bottom_right - zone_top_left)
	draw_rect(zone, Color(0.12, 0.25, 0.32, 0.46), true)
	draw_rect(zone, Color(CHALK, 0.76), false, 1.0)
	for division in [1.0 / 3.0, 2.0 / 3.0]:
		var vx := lerpf(zone.position.x, zone.end.x, division)
		var hy := lerpf(zone.position.y, zone.end.y, division)
		draw_line(Vector2(vx, zone.position.y), Vector2(vx, zone.end.y), Color(CHALK, 0.14), 1.0)
		draw_line(Vector2(zone.position.x, hy), Vector2(zone.end.x, hy), Color(CHALK, 0.14), 1.0)

	var previous_tunnel: Variant = _point(["previous_tunnel", "prev_tunnel"])
	var previous_plate: Variant = _point(["previous_plate", "prev_plate"])
	if previous_tunnel != null and previous_plate != null:
		_draw_dashed(_map_point(previous_tunnel, plot), _map_point(previous_plate, plot), PREVIOUS, 1.25)
		draw_circle(_map_point(previous_tunnel, plot), 2.0, PREVIOUS)
		draw_circle(_map_point(previous_plate, plot), 2.5, Color(PREVIOUS, 0.88))

	var target: Variant = _point(["target", "aim"])
	if target != null:
		var tp := _map_point(target, plot)
		draw_line(tp - Vector2(3.0, 0.0), tp + Vector2(3.0, 0.0), GOLD, 1.0)
		draw_line(tp - Vector2(0.0, 3.0), tp + Vector2(0.0, 3.0), GOLD, 1.0)

	var release: Variant = _point(["release"])
	var tunnel: Variant = _point(["tunnel", "tunnel_point"])
	var plate: Variant = _point(["plate", "actual", "actual_plate"])
	var path: Array[Vector2] = []
	for point_value in [release, tunnel, plate]:
		if point_value != null:
			path.append(_map_point(point_value, plot))
	var accent := _classification_color()
	if path.size() >= 2:
		for index in range(path.size() - 1):
			draw_line(path[index], path[index + 1], accent, 1.8, true)
	if tunnel != null:
		draw_circle(_map_point(tunnel, plot), 2.3, TEAL)
	if release != null:
		draw_circle(_map_point(release, plot), 1.8, Color(CHALK, 0.72))
	if plate != null:
		var pp := _map_point(plate, plot)
		draw_circle(pp, 3.6, Color(INK, 0.96))
		draw_circle(pp, 2.7, accent)
		draw_arc(pp, 4.4, 0.0, TAU, 12, CHALK, 1.0)


func _draw_reference_grid(plot: Rect2) -> void:
	for x_ft in [-1.5, 0.0, 1.5]:
		var a := _map_point(Vector2(x_ft, VIEW_Z.x), plot)
		var b := _map_point(Vector2(x_ft, VIEW_Z.y), plot)
		draw_line(a, b, Color(GRID, 0.42), 1.0)
	for z_ft in [1.0, 2.5, 4.0, 5.5]:
		var a := _map_point(Vector2(VIEW_X.x, z_ft), plot)
		var b := _map_point(Vector2(VIEW_X.y, z_ft), plot)
		draw_line(a, b, Color(GRID, 0.42), 1.0)


func _draw_dashed(from: Vector2, to: Vector2, color: Color, width: float) -> void:
	var distance := from.distance_to(to)
	if distance <= 0.01:
		return
	var direction := (to - from) / distance
	var cursor := 0.0
	while cursor < distance:
		var segment_end := minf(cursor + 3.0, distance)
		draw_line(from + direction * cursor, from + direction * segment_end, color, width)
		cursor += 5.0


func _map_point(point: Vector2, plot: Rect2) -> Vector2:
	var nx := inverse_lerp(VIEW_X.x, VIEW_X.y, clampf(point.x, VIEW_X.x, VIEW_X.y))
	var nz := inverse_lerp(VIEW_Z.x, VIEW_Z.y, clampf(point.y, VIEW_Z.x, VIEW_Z.y))
	return Vector2(
		lerpf(plot.position.x, plot.end.x, nx),
		lerpf(plot.end.y, plot.position.y, nz)
	)


func _point(keys: Array[String]) -> Variant:
	for key in keys:
		if _report.has(key):
			var parsed: Variant = _parse_point(_report[key])
			if parsed != null:
				return parsed
	var current: Variant = _report.get("current", {})
	if current is Dictionary:
		for key in keys:
			if current.has(key):
				var parsed: Variant = _parse_point(current[key])
				if parsed != null:
					return parsed
	return null


func _parse_point(value: Variant) -> Variant:
	if value is Vector2:
		return value
	if value is Array and value.size() >= 2 and _is_number(value[0]) and _is_number(value[1]):
		return Vector2(float(value[0]), float(value[1]))
	if value is Dictionary and value.has("x"):
		var z_value: Variant = value.get("z", value.get("y"))
		if _is_number(value.x) and _is_number(z_value):
			return Vector2(float(value.x), float(z_value))
	return null


func _classification_color() -> Color:
	var classification := String(_report.get("classification", _report.get("door", ""))).to_lower()
	if "front" in classification:
		return STITCH
	if "back" in classification:
		return TEAL
	if "corner" in classification or "paint" in classification:
		return GOLD
	return TEAL


func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
