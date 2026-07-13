extends RefCounted

## Pixel ballpark stage bound to PixelBallparkCanvas.

const Style = preload("res://presentation/pixel_art_style.gd")
const Landmarks = preload("res://world/view_landmarks.gd")

var host: PixelBallparkCanvas


func _init(canvas: PixelBallparkCanvas) -> void:
	host = canvas

func draw_skyline_row(palette: Dictionary, base_y: int, fill: Color, detailed: bool, stamps: Array) -> void:
	# Two-row silhouette grammar (§7.2): the far row is pure shape; the near
	# row adds lit windows and sparse warm roof notes only.
	for stamp in stamps:
		var kind := String(stamp[0])
		var x := int(stamp[1])
		var param := int(stamp[2])
		match kind:
			"hill":
				stamp_hill(x, base_y, param, fill)
			"cannery":
				stamp_cannery(palette, x, base_y, fill, detailed, param == 1)
			"warehouse":
				stamp_warehouse(palette, x, base_y, fill, detailed)
			"sheds":
				stamp_sheds(palette, x, base_y, fill, detailed, param)
			"crane":
				stamp_crane(x, base_y, fill)
			"masts":
				stamp_masts(x, base_y, fill, param)
			"traps":
				stamp_traps(x, base_y, fill)

func stamp_hill(x: int, base_y: int, width: int, fill: Color) -> void:
	var height := maxi(3, int(width / 5.0))
	var half := int(width / 2.0)
	for row in range(height):
		var inset := int(float(half) * float(row) / float(height))
		Style.pixel_rect(host, Rect2(x + inset, base_y - height + row, width - inset * 2, 1), fill)

func stamp_cannery(palette: Dictionary, x: int, base_y: int, fill: Color, detailed: bool, steaming: bool) -> void:
	# Gabled cannery with roof monitor and steam stack (§7.1).
	Style.pixel_rect(host, Rect2(x, base_y - 8, 14, 8), fill)
	for row in range(4):
		Style.pixel_rect(host, Rect2(x + 1 + row, base_y - 9 - row, 12 - row * 2, 1), fill)
	Style.pixel_rect(host, Rect2(x + 5, base_y - 14, 4, 3), fill)
	Style.pixel_rect(host, Rect2(x + 11, base_y - 15, 2, 6), fill)
	if detailed:
		Style.pixel_rect(host, Rect2(x + 5, base_y - 12, 3, 1), palette.roof_accent)
		scatter_windows(x + 1, base_y - 6, 12, 2, x + 3)
		if steaming:
			host.atmosphere.draw_steam(palette, x + 12, base_y - 16)

func stamp_warehouse(palette: Dictionary, x: int, base_y: int, fill: Color, detailed: bool) -> void:
	Style.pixel_rect(host, Rect2(x, base_y - 6, 18, 6), fill)
	Style.pixel_rect(host, Rect2(x + 1, base_y - 7, 16, 1), fill)
	if detailed:
		Style.pixel_rect(host, Rect2(x + 3, base_y - 8, 4, 1), palette.roof_accent)
		scatter_windows(x + 1, base_y - 5, 16, 2, x)

func stamp_sheds(palette: Dictionary, x: int, base_y: int, fill: Color, detailed: bool, count: int) -> void:
	# Fish-shed rows: low gable teeth along the quay (§7.1).
	for index in range(maxi(1, count)):
		var sx := x + index * 7
		Style.pixel_rect(host, Rect2(sx, base_y - 4, 6, 4), fill)
		Style.pixel_rect(host, Rect2(sx + 1, base_y - 5, 4, 1), fill)
		Style.pixel_rect(host, Rect2(sx + 2, base_y - 6, 2, 1), fill)
		if detailed:
			if index % 2 == 0:
				Style.pixel_rect(host, Rect2(sx + 2, base_y - 6, 2, 1), palette.roof_accent)
			scatter_windows(sx + 1, base_y - 3, 4, 1, x + index * 5)

func stamp_crane(x: int, base_y: int, fill: Color) -> void:
	# Gantry crane: paired legs, deck, jib, counterweight, hanging cable.
	Style.pixel_rect(host, Rect2(x, base_y - 10, 1, 10), fill)
	Style.pixel_rect(host, Rect2(x + 5, base_y - 10, 1, 10), fill)
	Style.pixel_rect(host, Rect2(x - 1, base_y - 11, 8, 1), fill)
	Style.pixel_rect(host, Rect2(x + 2, base_y - 13, 14, 1), fill)
	Style.pixel_rect(host, Rect2(x + 1, base_y - 13, 3, 2), fill)
	Style.pixel_rect(host, Rect2(x - 3, base_y - 12, 3, 2), fill)
	Style.pixel_rect(host, Rect2(x + 14, base_y - 12, 1, 4), fill)
	Style.pixel_rect(host, Rect2(x + 13, base_y - 8, 2, 1), fill)

func stamp_masts(x: int, base_y: int, fill: Color, count: int) -> void:
	# Irregular mast forest with 1-3 cell stair rigging runs (§7.2).
	for index in range(maxi(1, count)):
		var seed := 4700 + x * 3 + index * 41
		var mx := x + index * 4 + int(Style.hash01(seed) * 3.0)
		var height := 6 + int(Style.hash01(seed + 5) * 6.0)
		Style.pixel_rect(host, Rect2(mx, base_y - height, 1, height), fill)
		Style.pixel_rect(host, Rect2(mx - 1, base_y - height + 2, 3, 1), fill)
		var ry := base_y - height + 3
		var rx := mx + 1
		var run := 1 + (index % 3)
		while ry < base_y - 1 and rx < mx + 4:
			Style.pixel_rect(host, Rect2(rx, ry, 1, mini(run, base_y - 1 - ry)), fill)
			ry += run
			rx += 1
			run = 1 + ((run + 1) % 3)
	Style.pixel_rect(host, Rect2(x - 2, base_y - 2, maxi(1, count) * 4 + 5, 2), fill)

func stamp_traps(x: int, base_y: int, fill: Color) -> void:
	# Stacked lobster traps by the quay edge (§7.1).
	Style.pixel_rect(host, Rect2(x, base_y - 2, 3, 2), fill)
	Style.pixel_rect(host, Rect2(x + 3, base_y - 2, 3, 2), fill)
	Style.pixel_rect(host, Rect2(x + 1, base_y - 4, 3, 2), fill)

func stamp_lighthouse(palette: Dictionary, x: int, base_y: int) -> void:
	# Round banded lighthouse with a lamp room at the right skyline edge
	# (§7.1). The lamp stays a quiet lamp_glow note, never the focal warm.
	Style.pixel_rect(host, Rect2(x, base_y - 12, 4, 12), palette.town_near)
	Style.pixel_rect(host, Rect2(x, base_y - 9, 4, 2), palette.seat_board)
	Style.pixel_rect(host, Rect2(x, base_y - 5, 4, 2), palette.seat_board)
	Style.pixel_rect(host, Rect2(x - 1, base_y - 13, 6, 1), palette.town_near)
	var lamp: Color = palette.seat_board if host.mood == "day" else palette.lamp_glow
	Style.pixel_rect(host, Rect2(x + 1, base_y - 15, 2, 2), lamp)
	Style.pixel_rect(host, Rect2(x + 1, base_y - 16, 2, 1), palette.town_near)

func draw_lighthouse_beam(palette: Dictionary, lamp: Vector2) -> void:
	# Stepped beam sweep every six seconds in golden/night (§6.1).
	if host.mood == "day":
		return
	var cycle := fmod(host.anim_time, 6.0)
	if cycle >= 1.5:
		return
	var directions := [Vector2(-3, -1), Vector2(-3, 0), Vector2(-3, 1)]
	var direction: Vector2 = directions[clampi(int(cycle / 0.5), 0, 2)]
	for reach in range(1, 4):
		var at := lamp + direction * float(reach * 2)
		Style.pixel_rect(host, Rect2(at.round(), Vector2(2, 1)), palette.lamp_glow)

func draw_breakwater(palette: Dictionary, x: int, width: int, y: int) -> void:
	# Stone breakwater with an irregular cap and a foam seam (§7.1); night fog
	# laps it with the permitted checker dither (§5.3).
	Style.pixel_rect(host, Rect2(x, y, width, 2), palette.town_near)
	var bx := x
	while bx < x + width:
		var seed := 6100 + bx * 19
		if Style.hash01(seed + 3) > 0.5:
			Style.pixel_rect(host, Rect2(bx, y - 1, mini(3, x + width - bx), 1), palette.town_near)
		if Style.hash01(seed + 9) > 0.35 and bx + 1 < x + width:
			Style.pixel_rect(host, Rect2(bx + 1, y + 2, mini(3, x + width - bx - 1), 1), palette.sea_glint)
		bx += 6 + int(Style.hash01(seed) * 5.0)
	if host.mood == "night":
		host.atmosphere.dither_row(x - 4, x + width + 4, y - 3, palette.haze, 0)
		host.atmosphere.dither_row(x - 4, x + width + 4, y - 2, palette.haze, 1)

func scatter_windows(x: int, y: int, width: int, rows: int, salt: int) -> void:
	# Lit-window notes; single cells are sanctioned window accents (§5.1) and
	# density follows the host.mood (§7.6).
	var palette := Style.palette(host.mood)
	var density := float(host.WINDOW_DENSITY.get(host.mood, 0.2))
	# Celebration (§9.7): every lit window pulses one value step for two ticks
	# of each 12-tick cycle while the town joins the party.
	var window: Color = palette.window_lit
	if host._celebrating() and posmod(host.crowd_motion_tick, 12) < 2:
		window = Style.shift_value(window, 1)
	for row in range(rows):
		var wx := x
		while wx < x + width - 1:
			if Style.hash01(salt * 131 + wx * 7 + row * 57) < density:
				Style.pixel_rect(host, Rect2(wx, y + row * 2, 1, 1), window)
			wx += 3


# --- Weather notes (§7.7) ----------------------------------------------------


