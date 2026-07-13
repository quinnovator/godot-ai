extends RefCounted

## Authored half-composition-cell material pass.
##
## The structural stage still composes in the readable 320x180 vocabulary.
## These marks land at 0.5-cell increments, which are genuine 640x360 design
## cells and therefore 4x4 native pixels after PixelScene's direct transform.

const Style = preload("res://presentation/pixel_art_style.gd")
const Landmarks = preload("res://world/view_landmarks.gd")

var host: PixelBallparkCanvas


func _init(canvas: PixelBallparkCanvas) -> void:
	host = canvas


func draw(palette: Dictionary) -> void:
	match host.view_mode:
		"pitching":
			_draw_pitching(palette)
		"batting":
			_draw_batting(palette)
		"fielding":
			_draw_fielding(palette)
		"dugout":
			_draw_dugout(palette)
		_:
			_draw_intro(palette)


func _draw_pitching(palette: Dictionary) -> void:
	var bands: Dictionary = Landmarks.BAND_DATUMS.pitching
	_draw_brick_pores(palette, Rect2(0, 25, 320, 51), 1907)
	_draw_crowd_spark(palette, Rect2(8, 42, 304, 31), 2609, 0.72)
	_draw_turf_fibers(palette, Rect2(0, bands.field_top, 320, 180 - bands.field_top), 3109, "pitching")
	var diamond: Dictionary = Landmarks.diamond("pitching")
	_draw_clay_grain(palette, diamond.plate + Vector2(0, 1), Vector2(16, 7), 4013)
	_draw_clay_grain(palette, diamond.mound, Vector2(18, 8), 4517)


func _draw_batting(palette: Dictionary) -> void:
	var top := int(Landmarks.BAND_DATUMS.batting.field_top)
	_draw_crowd_spark(palette, Rect2(0, 42, 72, 46), 5209, 0.55)
	_draw_crowd_spark(palette, Rect2(248, 42, 72, 46), 5501, 0.55)
	_draw_turf_fibers(palette, Rect2(0, top, 320, 180 - top), 6113, "batting")
	_draw_clay_grain(palette, Vector2(160, 155), Vector2(15, 7), 6701)
	_draw_clay_grain(palette, Vector2(160, 76), Vector2(10, 4), 6823)


func _draw_fielding(palette: Dictionary) -> void:
	var top := int(Landmarks.BAND_DATUMS.fielding.field_top)
	_draw_crowd_spark(palette, Rect2(-20, 48, 380, 13), 7103, 0.45)
	_draw_turf_fibers(palette, Rect2(-24, top, 368, 118), 7607, "fielding")
	_draw_clay_grain(palette, Vector2(160, 155), Vector2(9, 4), 8209)
	_draw_clay_grain(palette, Vector2(160, 119), Vector2(6, 3), 8317)


func _draw_intro(palette: Dictionary) -> void:
	var top := int(Landmarks.BAND_DATUMS.intro.field_top)
	_draw_crowd_spark(palette, Rect2(0, 82, 320, 32), 9001, 0.42)
	_draw_turf_fibers(palette, Rect2(0, top, 320, 48), 9311, "intro")
	_draw_clay_grain(palette, Vector2(160, 163), Vector2(7, 2), 9901)
	_draw_clay_grain(palette, Vector2(160, 146), Vector2(7, 3), 10037)


func _draw_dugout(palette: Dictionary) -> void:
	var wood_lit: Color = Style.shift_value(palette.wood, 1)
	var wall_lit: Color = Style.shift_value(palette.ink_mid, 1)
	for y2 in range(75, 196, 5):
		for x2 in range(4 + posmod(y2, 9), 344, 11):
			_detail_rect(float(x2) * 0.5, float(y2) * 0.5, 1.0, 0.5, wall_lit)
	for x2 in range(35, 608, 13):
		var y2 := 234 + posmod(x2 * 7, 8)
		_detail_rect(float(x2) * 0.5, float(y2) * 0.5, 1.5, 0.5, wood_lit)
	_draw_crowd_spark(palette, Rect2(180, 63, 120, 10), 10427, 0.35)


func _draw_turf_fibers(palette: Dictionary, area: Rect2, seed: int, view: String) -> void:
	var fiber_dark: Color = palette.turf_shade.lerp(palette.turf_main, 0.56)
	var fiber_lit: Color = palette.turf_lit.lerp(palette.turf_main, 0.64)
	var start_y2 := roundi(area.position.y * 2.0) + 1
	var end_y2 := roundi(area.end.y * 2.0)
	var start_x2 := roundi(area.position.x * 2.0)
	var end_x2 := roundi(area.end.x * 2.0)
	for y2 in range(start_y2, end_y2, 5):
		var x2 := start_x2 + posmod(seed + y2 * 17, 7)
		while x2 < end_x2:
			var x := float(x2) * 0.5
			var y := float(y2) * 0.5
			if _turf_detail_allowed(view, x, y):
				var salt := seed + x2 * 31 + y2 * 47
				var lit := Style.hash01(salt) > 0.56
				var width := 1.0 if Style.hash01(salt + 3) > 0.72 else 0.5
				_detail_rect(x, y, width, 0.5, fiber_lit if lit else fiber_dark)
				if Style.hash01(salt + 9) > 0.92:
					_detail_rect(x + 0.5, y - 0.5, 0.5, 0.5, fiber_lit)
			x2 += 8 + posmod(seed + x2 * 3 + y2, 8)


func _turf_detail_allowed(view: String, x: float, y: float) -> bool:
	match view:
		"pitching":
			var plate_delta := Vector2((x - 160.0) / 19.0, (y - 93.0) / 10.0)
			var mound_delta := Vector2((x - 138.0) / 21.0, (y - 141.0) / 10.0)
			return plate_delta.length_squared() > 1.0 and mound_delta.length_squared() > 1.0
		"batting":
			return not (x > 116.0 and x < 204.0 and y > 66.0 and y < 162.0)
		"fielding":
			var field_delta := Vector2((x - 160.0) / 144.0, (y - 118.0) / 50.0)
			var infield_delta := Vector2((x - 160.0) / 52.0, (y - 127.0) / 40.0)
			return field_delta.length_squared() < 1.0 and infield_delta.length_squared() > 1.0
		"intro":
			return not (x > 110.0 and x < 210.0 and y > 119.0 and y < 168.0)
	return true


func _draw_clay_grain(palette: Dictionary, center: Vector2, radius: Vector2, seed: int) -> void:
	var grain_lit: Color = palette.clay_lit.lerp(palette.clay_main, 0.55)
	var grain_dark: Color = palette.clay_shade.lerp(palette.clay_main, 0.52)
	var left2 := roundi((center.x - radius.x) * 2.0)
	var right2 := roundi((center.x + radius.x) * 2.0)
	var top2 := roundi((center.y - radius.y) * 2.0)
	var bottom2 := roundi((center.y + radius.y) * 2.0)
	for y2 in range(top2, bottom2, 4):
		var x2 := left2 + posmod(seed + y2 * 19, 7)
		while x2 < right2:
			var x := float(x2) * 0.5
			var y := float(y2) * 0.5
			var normalized := Vector2((x - center.x) / maxf(1.0, radius.x), (y - center.y) / maxf(1.0, radius.y))
			if normalized.length_squared() < 0.88:
				var salt := seed + x2 * 37 + y2 * 23
				_detail_rect(x, y, 0.5 if Style.hash01(salt + 4) < 0.78 else 1.0, 0.5, grain_lit if Style.hash01(salt) > 0.52 else grain_dark)
			x2 += 5 + posmod(seed + x2 + y2 * 3, 6)


func _draw_brick_pores(palette: Dictionary, area: Rect2, seed: int) -> void:
	var pore: Color = palette.wood_dark.lerp(palette.roof_accent, 0.35)
	var edge: Color = palette.clay_lit.lerp(palette.roof_accent, 0.72)
	for y2 in range(roundi(area.position.y * 2.0) + 1, roundi(area.end.y * 2.0), 7):
		var x2 := roundi(area.position.x * 2.0) + posmod(seed + y2 * 11, 13)
		while x2 < roundi(area.end.x * 2.0):
			var salt := seed + x2 * 29 + y2 * 41
			_detail_rect(float(x2) * 0.5, float(y2) * 0.5, 0.5, 0.5, edge if Style.hash01(salt) > 0.78 else pore)
			x2 += 17 + posmod(salt, 15)


func _draw_crowd_spark(palette: Dictionary, area: Rect2, seed: int, density: float) -> void:
	var cool: Color = Style.shift_value(palette.crowd_cool, 1)
	var warm: Color = palette.window_lit.lerp(palette.crowd_warm, 0.48)
	var count := roundi(area.size.x * area.size.y * density * 0.055)
	for index in range(count):
		var salt := seed + index * 97
		var x := area.position.x + floorf(Style.hash01(salt) * area.size.x * 2.0) * 0.5
		var y := area.position.y + floorf(Style.hash01(salt + 17) * area.size.y * 2.0) * 0.5
		_detail_rect(x, y, 0.5, 0.5, warm if Style.hash01(salt + 31) > 0.84 else cool)


func _detail_rect(x: float, y: float, width: float, height: float, color: Color) -> void:
	Style.detail_rect(host, Rect2(x, y, width, height), color)
