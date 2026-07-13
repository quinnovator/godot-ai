class_name PixiballStrikeZone
extends Control

## Chalk-tick strike zone (bible §10.5): chalk corner ticks + a dashed steel
## 3x3 interior grid over the live world, a signal-teal aim reticle, a
## lantern-gold flash on the called cell, and a stepped chalk trail behind the
## pitch marker. Every mark is an opaque authored cell on the native 4px
## rhythm — no alpha fills, no arcs, no anti-aliased lines.

const S := preload("res://ui/pixiball_style.gd")

var aim := Vector2.ZERO
var pitch_marker := Vector2.ZERO
var show_pitch := false
var accent := S.TEAL
var active := true
var lateral_screen_sign := 1.0

const AIM_LATERAL_FT := 1.35
const AIM_VERTICAL_FT := 1.55
const ZONE_HALF_WIDTH_FT := 17.0 / 24.0
const ZONE_HALF_HEIGHT_FT := 1.0

# One authored design cell is 4 native px (SHARED_CONTEXT 4px grid).
const CELL := 4
# Called-strike lamp alternates at 2 Hz, under the 3 Hz blink cap (bible §11.5).
const FLASH_MS := 250
# Stepped chalk trajectory: at most 3 opaque afterimage cells (bible §9.2).
const TRAIL_GHOSTS := 3
# Minimum aim-space gap between recorded chalk steps.
const TRAIL_STEP := 0.14

var _trail: PackedVector2Array = PackedVector2Array()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ZERO


func set_aim(value: Vector2) -> void:
	aim = value.clamp(Vector2(-1, -1), Vector2(1, 1))
	queue_redraw()


func set_pitch(value: Vector2, visible: bool) -> void:
	if visible:
		if not show_pitch:
			_trail.clear()
		if _trail.is_empty() or _trail[_trail.size() - 1].distance_to(value) >= TRAIL_STEP:
			_trail.append(value)
			while _trail.size() > TRAIL_GHOSTS + 1:
				_trail.remove_at(0)
	else:
		_trail.clear()
	pitch_marker = value
	show_pitch = visible
	queue_redraw()


func set_lateral_screen_sign(value: float) -> void:
	lateral_screen_sign = -1.0 if value < 0.0 else 1.0
	queue_redraw()


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var zone_w := int(size.x) - int(size.x) % CELL
	var zone_h := int(size.y) - int(size.y) % CELL
	if zone_w < CELL * 6 or zone_h < CELL * 6:
		return
	var cols: Array[int] = [0, _snap(zone_w / 3.0), _snap(zone_w * 2.0 / 3.0), zone_w]
	var rows: Array[int] = [0, _snap(zone_h / 3.0), _snap(zone_h * 2.0 / 3.0), zone_h]
	var center := Vector2(zone_w, zone_h) * 0.5
	# Aim is simulation-normalized, so map it through the same feet contract as
	# gameplay. The command envelope intentionally extends beyond the zone.
	var aim_extent := Vector2(
		zone_w * 0.5 * AIM_LATERAL_FT / ZONE_HALF_WIDTH_FT,
		zone_h * 0.5 * AIM_VERTICAL_FT / ZONE_HALF_HEIGHT_FT
	)
	if show_pitch:
		_draw_called_cell(cols, rows, center, aim_extent)
	_draw_corner_ticks(zone_w, zone_h)
	_draw_dashed_grid(cols, rows)
	# While aiming the reticle is topmost; once a pitch is shown the live ball
	# marker owns the top of the stack (§4.1 lantern contract).
	_draw_reticle(center, aim_extent)
	if show_pitch:
		_draw_trajectory(center, aim_extent)
		_draw_pitch_marker(zone_w, zone_h, center, aim_extent)
	if active or show_pitch:
		queue_redraw()


## Compact chalk corner ticks. Short arms keep the plate battery readable —
## long L-brackets used to smear through catcher/batter heads (§5.2 seat intent).
func _draw_corner_ticks(zone_w: int, zone_h: int) -> void:
	var arm := clampi(_snap(minf(zone_w, zone_h) / 8.0), CELL * 2, CELL * 4)
	var arms: Array[Rect2] = [
		Rect2(0, 0, arm, CELL), Rect2(0, 0, CELL, arm),
		Rect2(zone_w - arm, 0, arm, CELL), Rect2(zone_w - CELL, 0, CELL, arm),
		Rect2(0, zone_h - CELL, arm, CELL), Rect2(0, zone_h - arm, CELL, arm),
		Rect2(zone_w - arm, zone_h - CELL, arm, CELL), Rect2(zone_w - CELL, zone_h - arm, CELL, arm),
	]
	for rect in arms:
		draw_rect(rect.grow(1), S.INK)
	for rect in arms:
		draw_rect(rect, S.CHALK)


## Quiet 3x3 guide: only the two interior crosses while aiming. The full dashed
## grid appears once a pitch is live so the zone does not fight the battery.
func _draw_dashed_grid(cols: Array[int], rows: Array[int]) -> void:
	var inset := CELL * 3
	var dashes: Array[Rect2] = []
	if show_pitch:
		for x in [cols[1], cols[2]]:
			var y := rows[0] + inset
			while y + CELL * 2 <= rows[3] - inset:
				dashes.append(Rect2(x, y, CELL, CELL * 2))
				y += CELL * 4
		for y in [rows[1], rows[2]]:
			var x := cols[0] + inset
			while x + CELL * 2 <= cols[3] - inset:
				dashes.append(Rect2(x, y, CELL * 2, CELL))
				x += CELL * 4
	else:
		# Aiming: four short mid-edge ticks only — enough to aim, not a cage.
		var mx := _snap(float(cols[3]) * 0.5)
		var my := _snap(float(rows[3]) * 0.5)
		dashes.append(Rect2(mx, rows[0] + inset, CELL, CELL * 2))
		dashes.append(Rect2(mx, rows[3] - inset - CELL * 2, CELL, CELL * 2))
		dashes.append(Rect2(cols[0] + inset, my, CELL * 2, CELL))
		dashes.append(Rect2(cols[3] - inset - CELL * 2, my, CELL * 2, CELL))
	for dash in dashes:
		draw_rect(Rect2(dash.position + Vector2(1, 1), dash.size), S.INK)
	for dash in dashes:
		draw_rect(dash, S.STEEL)


## Lantern-gold called-strike cell: when the pitch lands inside the zone, the
## containing grid cell frames in gold, lamp-flashing at 2 Hz. The unlit phase
## keeps a dimmed gold frame so any paused frame still reads (§11.8).
func _draw_called_cell(cols: Array[int], rows: Array[int], center: Vector2, aim_extent: Vector2) -> void:
	var marker := _plate_point(pitch_marker, center, aim_extent)
	if marker.x < cols[0] or marker.x >= cols[3] or marker.y < rows[0] or marker.y >= rows[3]:
		return
	var column := 2 if marker.x >= cols[2] else (1 if marker.x >= cols[1] else 0)
	var row := 2 if marker.y >= rows[2] else (1 if marker.y >= rows[1] else 0)
	var cell := Rect2(
		cols[column] + CELL, rows[row] + CELL,
		cols[column + 1] - cols[column] - CELL * 2, rows[row + 1] - rows[row] - CELL * 2
	)
	if cell.size.x <= CELL * 4 or cell.size.y <= CELL * 4:
		return
	var lit := int(Time.get_ticks_msec() / FLASH_MS) % 2 == 0
	var frame := S.GOLD if lit else Color(S.GOLD).darkened(0.35)
	draw_rect(Rect2(cell.position, Vector2(cell.size.x, CELL)), frame)
	draw_rect(Rect2(Vector2(cell.position.x, cell.end.y - CELL), Vector2(cell.size.x, CELL)), frame)
	draw_rect(Rect2(cell.position, Vector2(CELL, cell.size.y)), frame)
	draw_rect(Rect2(Vector2(cell.end.x - CELL, cell.position.y), Vector2(CELL, cell.size.y)), frame)
	for corner in [
		cell.position,
		Vector2(cell.end.x - CELL * 2, cell.position.y),
		Vector2(cell.position.x, cell.end.y - CELL * 2),
		cell.end - Vector2(CELL * 2, CELL * 2),
	]:
		draw_rect(Rect2(corner, Vector2(CELL * 2, CELL * 2)), S.GOLD)


## Stepped chalk trajectory: up to 3 opaque afterimage cells stepping from
## chalk toward the cool background — never a ribbon or continuous line (§9.2).
func _draw_trajectory(center: Vector2, aim_extent: Vector2) -> void:
	var steps: Array[Color] = [S.CHALK, S.STEEL, S.SLATE]
	var ghosts := mini(_trail.size() - 1, TRAIL_GHOSTS)
	for index in range(ghosts):
		var point := _plate_point(_trail[_trail.size() - 2 - index], center, aim_extent)
		draw_rect(Rect2(_snap(point.x), _snap(point.y), CELL, CELL), steps[index])


## Pitch marker follows the ball grammar (§9.1): a 2x2-cell chalk-white core
## with a 1-cell ink shade; a pitch outside the zone takes a stitch-red seat.
func _draw_pitch_marker(zone_w: int, zone_h: int, center: Vector2, aim_extent: Vector2) -> void:
	var point := _plate_point(pitch_marker, center, aim_extent)
	var origin := Vector2(_snap(point.x) - CELL, _snap(point.y) - CELL)
	var inside := point.x >= 0.0 and point.x < zone_w and point.y >= 0.0 and point.y < zone_h
	if not inside:
		draw_rect(Rect2(origin - Vector2(CELL, CELL), Vector2(CELL * 4, CELL * 4)), S.STITCH)
	draw_rect(Rect2(origin + Vector2(CELL, CELL), Vector2(CELL * 2, CELL * 2)), S.INK)
	draw_rect(Rect2(origin, Vector2(CELL * 2, CELL * 2)), S.CHALK)


## Signal-teal aim reticle (§10.5): an open 5x5-cell target ring around an
## ink moat and the accent core cell, plus four solid 1-cell cross arms. Every
## teal mark sits inside a full 1-cell ink surround so the beacon separates by
## value from bright day clay and the ink-contoured battery cluster alike —
## paused-frame read comes from opaque mass, never glow or motion. The arm
## tips extend 1 cell at 1 Hz while aiming, under the 3 Hz cap (§11.5); the
## whole beacon stays cool so it never rivals the warm focal pool.
func _draw_reticle(center: Vector2, aim_extent: Vector2) -> void:
	var point := center + Vector2(aim.x * lateral_screen_sign, aim.y) * aim_extent
	var px := _snap(point.x)
	var py := _snap(point.y)
	var arm_color := S.TEAL if active else S.SLATE
	var core_color := accent if active else S.SLATE
	var breathe := CELL if active and int(Time.get_ticks_msec() / 500) % 2 == 0 else 0
	var ring := Rect2(px - CELL * 2, py - CELL * 2, CELL * 5, CELL * 5)
	var arm_len := CELL * 3 + breathe
	var arm_gap := CELL * 3
	var arms: Array[Rect2] = [
		Rect2(px + arm_gap, py, arm_len, CELL),
		Rect2(px - arm_gap - arm_len + CELL, py, arm_len, CELL),
		Rect2(px, py + arm_gap, CELL, arm_len),
		Rect2(px, py - arm_gap - arm_len + CELL, CELL, arm_len),
	]
	for arm in arms:
		draw_rect(arm.grow(CELL), S.INK)
	draw_rect(ring.grow(CELL), S.INK)
	for arm in arms:
		draw_rect(arm, arm_color)
	draw_rect(ring, arm_color)
	draw_rect(Rect2(px - CELL, py - CELL, CELL * 3, CELL * 3), S.INK)
	draw_rect(Rect2(px, py, CELL, CELL), core_color)


func _plate_point(value: Vector2, center: Vector2, aim_extent: Vector2) -> Vector2:
	return center + Vector2(value.x * lateral_screen_sign, value.y) * aim_extent


func _snap(value: float) -> int:
	return int(roundf(value / float(CELL))) * CELL
