class_name PixiballPitchIntelDiagram
extends Control

## Slate-board chalk diagram for a pitch and the pitch it tunneled from
## (art bible §10.1 "Slate board" + §10.7): a catcher-view drawing in opaque,
## integer-aligned chalk geometry. Break paths are stepped 4px cells along the
## deterministic flight (never smooth curves), pitch locations are 8px cluster
## dots, the release carries grip dots, the tunnel window is signal-teal, and
## the recommended target wears the lantern-gold focal ticks — the diagram's
## only gold.
##
## Coordinates are semantic baseball feet: +x is catcher's left, z is height.
## The accepted dictionary is intentionally engine/presentation neutral:
##
##     {
##       "release": [x, z], "tunnel": [x, z], "plate": [x, z],
##       "target": [x, z],
##       "previous_tunnel": [x, z], "previous_plate": [x, z],
##       "classification": "frontdoor" | "backdoor" | "corner_paint",
##       "confidence": 0.0-1.0,   # optional; renders as chalk tally marks
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
const SLATE_FACE := S.HARBOR_WASH
const SLATE_LIFT := S.SHADOW_BLUE
const SMUDGE := S.NIGHT
const CHALK := S.CHALK
const STEEL := S.STEEL
const TEAL := S.TEAL
const GOLD := S.GOLD
const STITCH := S.STITCH
const PREVIOUS := S.SLATE

## One stepped-path cell in native px; chalk strokes are 2px, frames 4px.
const CELL := 4

var _report: Dictionary = {}


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(352.0, 288.0)


func present(report: Dictionary) -> void:
	_report = report.duplicate(true)
	queue_redraw()


func clear_data() -> void:
	_report.clear()
	queue_redraw()


func has_pitch_data() -> bool:
	return _point(["plate", "actual", "actual_plate"]) != null


func _draw() -> void:
	var plot := Rect2(
		Vector2(16.0, 16.0),
		Vector2(floorf((size.x - 32.0) / 4.0) * 4.0, floorf((size.y - 32.0) / 4.0) * 4.0)
	)
	if plot.size.x <= 8.0 or plot.size.y <= 8.0:
		return

	draw_rect(plot, SLATE_FACE, true)
	_draw_eraser_smudge(plot)
	_draw_reference_grid(plot)
	draw_rect(plot, INK, false, 4.0)

	var zone_top_left := _map_point(Vector2(-PLATE_HALF_FT, ZONE_TOP_FT), plot)
	var zone_bottom_right := _map_point(Vector2(PLATE_HALF_FT, ZONE_BOTTOM_FT), plot)
	var zone := Rect2(zone_top_left, zone_bottom_right - zone_top_left)
	draw_rect(zone, SLATE_LIFT, true)
	for division in [1.0 / 3.0, 2.0 / 3.0]:
		var vx := _snap2(lerpf(zone.position.x, zone.end.x, division))
		var hy := _snap2(lerpf(zone.position.y, zone.end.y, division))
		draw_rect(Rect2(Vector2(vx, zone.position.y), Vector2(2.0, zone.size.y)), STEEL, true)
		draw_rect(Rect2(Vector2(zone.position.x, hy), Vector2(zone.size.x, 2.0)), STEEL, true)
	draw_rect(zone, CHALK, false, 4.0)

	var previous_tunnel: Variant = _point(["previous_tunnel", "prev_tunnel"])
	var previous_plate: Variant = _point(["previous_plate", "prev_plate"])
	if previous_tunnel != null and previous_plate != null:
		_draw_stepped_segment(_map_point(previous_tunnel, plot), _map_point(previous_plate, plot), PREVIOUS, true)
		_draw_hollow_square(_map_point(previous_tunnel, plot), PREVIOUS, 6)
		draw_rect(Rect2(_map_point(previous_plate, plot) - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), PREVIOUS, true)

	var release: Variant = _point(["release"])
	var tunnel: Variant = _point(["tunnel", "tunnel_point"])
	var plate: Variant = _point(["plate", "actual", "actual_plate"])
	var path: Array[Vector2] = []
	for point_value in [release, tunnel, plate]:
		if point_value != null:
			path.append(_map_point(point_value, plot))
	var accent := _classification_color()
	for index in range(path.size() - 1):
		# Only the final leg — the break to the plate — takes the accent; the
		# approach is quiet chalk so the two-tone read marks the tunnel point.
		var leg_color := accent if index == path.size() - 2 else STEEL
		_draw_stepped_segment(path[index], path[index + 1], leg_color)
	if tunnel != null:
		_draw_hollow_square(_map_point(tunnel, plot), TEAL, 8)
	if release != null:
		_draw_grip_ball(_map_point(release, plot))
	if plate != null:
		_draw_cluster_dot(_map_point(plate, plot), accent)

	var target: Variant = _point(["target", "aim"])
	if target != null:
		_draw_target_focus(_map_point(target, plot))

	_draw_confidence_tallies(plot)


## Faint engraved graph grid under the chalk, 2px strokes one step above slate.
func _draw_reference_grid(plot: Rect2) -> void:
	for x_ft in [-1.5, 0.0, 1.5]:
		var a := _map_point(Vector2(x_ft, VIEW_Z.y), plot)
		draw_rect(Rect2(Vector2(a.x, plot.position.y + 4.0), Vector2(2.0, plot.size.y - 8.0)), SLATE_LIFT, true)
	for z_ft in [1.0, 2.5, 4.0, 5.5]:
		var a := _map_point(Vector2(VIEW_X.x, z_ft), plot)
		draw_rect(Rect2(Vector2(plot.position.x + 4.0, a.y), Vector2(plot.size.x - 8.0, 2.0)), SLATE_LIFT, true)


## Stepped chalk path: Bresenham over 4px cells so diagonals are stair runs,
## never smooth lines. Dashed variant (2 cells on / 2 off) marks the ghost of
## the previous pitch.
func _draw_stepped_segment(from: Vector2, to: Vector2, color: Color, dashed := false) -> void:
	var cell := Vector2i(int(floorf(from.x / CELL)), int(floorf(from.y / CELL)))
	var goal := Vector2i(int(floorf(to.x / CELL)), int(floorf(to.y / CELL)))
	var dx: int = absi(goal.x - cell.x)
	var dy: int = -absi(goal.y - cell.y)
	var sx: int = 1 if cell.x < goal.x else -1
	var sy: int = 1 if cell.y < goal.y else -1
	var err: int = dx + dy
	var index := 0
	while true:
		if not dashed or index % 4 < 2:
			draw_rect(Rect2(Vector2(cell * CELL), Vector2(CELL, CELL)), color, true)
		if cell == goal:
			return
		var doubled := err * 2
		if doubled >= dy:
			err += dy
			cell.x += sx
		if doubled <= dx:
			err += dx
			cell.y += sy
		index += 1


## 8px cluster pitch dot: ink seat, accent core, single chalk catch-light,
## and four chalk ring ticks replacing the old anti-aliased arc.
func _draw_cluster_dot(center: Vector2, accent: Color) -> void:
	draw_rect(Rect2(center - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), INK, true)
	draw_rect(Rect2(center - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), accent, true)
	draw_rect(Rect2(center - Vector2(4.0, 4.0), Vector2(2.0, 2.0)), CHALK, true)
	draw_rect(Rect2(center + Vector2(-2.0, -14.0), Vector2(4.0, 2.0)), CHALK, true)
	draw_rect(Rect2(center + Vector2(-2.0, 12.0), Vector2(4.0, 2.0)), CHALK, true)
	draw_rect(Rect2(center + Vector2(-14.0, -2.0), Vector2(2.0, 4.0)), CHALK, true)
	draw_rect(Rect2(center + Vector2(12.0, -2.0), Vector2(2.0, 4.0)), CHALK, true)


## Release mark: a chalk ball with two stitch-red grip dots.
func _draw_grip_ball(center: Vector2) -> void:
	draw_rect(Rect2(center - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), INK, true)
	draw_rect(Rect2(center - Vector2(4.0, 4.0), Vector2(8.0, 8.0)), CHALK, true)
	draw_rect(Rect2(center + Vector2(-2.0, -2.0), Vector2(2.0, 2.0)), STITCH, true)
	draw_rect(Rect2(center, Vector2(2.0, 2.0)), STITCH, true)


## Hollow chalk window (tunnel overlay at 8, previous-tunnel ghost at 6).
func _draw_hollow_square(center: Vector2, color: Color, half: int) -> void:
	var span := float(half * 2)
	draw_rect(Rect2(center - Vector2(half, half), Vector2(span, 2.0)), color, true)
	draw_rect(Rect2(center + Vector2(-half, half - 2), Vector2(span, 2.0)), color, true)
	draw_rect(Rect2(center + Vector2(-half, -half + 2), Vector2(2.0, span - 4.0)), color, true)
	draw_rect(Rect2(center + Vector2(half - 2, -half + 2), Vector2(2.0, span - 4.0)), color, true)


## Recommended target: lantern-gold corner ticks + core, the focal treatment
## (§10.4) and the only gold this diagram may author itself.
func _draw_target_focus(center: Vector2) -> void:
	draw_rect(Rect2(center - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), GOLD, true)
	draw_rect(Rect2(center + Vector2(-12.0, -12.0), Vector2(8.0, 2.0)), GOLD, true)
	draw_rect(Rect2(center + Vector2(4.0, -12.0), Vector2(8.0, 2.0)), GOLD, true)
	draw_rect(Rect2(center + Vector2(-12.0, 10.0), Vector2(8.0, 2.0)), GOLD, true)
	draw_rect(Rect2(center + Vector2(4.0, 10.0), Vector2(8.0, 2.0)), GOLD, true)
	draw_rect(Rect2(center + Vector2(-12.0, -10.0), Vector2(2.0, 6.0)), GOLD, true)
	draw_rect(Rect2(center + Vector2(10.0, -10.0), Vector2(2.0, 6.0)), GOLD, true)
	draw_rect(Rect2(center + Vector2(-12.0, 4.0), Vector2(2.0, 6.0)), GOLD, true)
	draw_rect(Rect2(center + Vector2(10.0, 4.0), Vector2(2.0, 6.0)), GOLD, true)


## Model confidence as chalk tally marks, top-right: four uprights and a
## stepped cross-stroke for five. Silent when the report omits confidence.
func _draw_confidence_tallies(plot: Rect2) -> void:
	var confidence: Variant = _confidence()
	if confidence == null:
		return
	var count := clampi(int(roundf(clampf(float(confidence), 0.0, 1.0) * 5.0)), 0, 5)
	if count <= 0:
		return
	var origin := Vector2(plot.end.x - 36.0, plot.position.y + 8.0)
	for index in range(mini(count, 4)):
		draw_rect(Rect2(origin + Vector2(index * 6.0, 0.0), Vector2(2.0, 12.0)), CHALK, true)
	if count >= 5:
		draw_rect(Rect2(origin + Vector2(-2.0, 8.0), Vector2(8.0, 2.0)), CHALK, true)
		draw_rect(Rect2(origin + Vector2(6.0, 4.0), Vector2(8.0, 2.0)), CHALK, true)
		draw_rect(Rect2(origin + Vector2(14.0, 0.0), Vector2(8.0, 2.0)), CHALK, true)


## Slate material tell (§10.1): a lighter eraser-smudge cluster in the corner.
func _draw_eraser_smudge(plot: Rect2) -> void:
	draw_rect(Rect2(plot.end - Vector2(48.0, 20.0), Vector2(28.0, 8.0)), SMUDGE, true)
	draw_rect(Rect2(plot.end - Vector2(36.0, 26.0), Vector2(20.0, 6.0)), SMUDGE, true)
	draw_rect(Rect2(plot.end - Vector2(44.0, 18.0), Vector2(12.0, 4.0)), SLATE_LIFT, true)


func _map_point(point: Vector2, plot: Rect2) -> Vector2:
	var nx := inverse_lerp(VIEW_X.x, VIEW_X.y, clampf(point.x, VIEW_X.x, VIEW_X.y))
	var nz := inverse_lerp(VIEW_Z.x, VIEW_Z.y, clampf(point.y, VIEW_Z.x, VIEW_Z.y))
	return Vector2(
		_snap2(lerpf(plot.position.x, plot.end.x, nx)),
		_snap2(lerpf(plot.end.y, plot.position.y, nz))
	)


## Chalk marks land on a 2px unit so every rect edge is a whole native pixel.
func _snap2(value: float) -> float:
	return roundf(value / 2.0) * 2.0


func _confidence() -> Variant:
	for source_value in [_report, _report.get("current", {})]:
		if source_value is not Dictionary:
			continue
		var source: Dictionary = source_value
		for key in ["confidence", "conf", "Confidence"]:
			if source.has(key) and _is_number(source[key]):
				var value := float(source[key])
				return value / 100.0 if value > 1.0 else value
	return null


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
