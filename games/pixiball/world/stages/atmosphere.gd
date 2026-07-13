extends RefCounted

## Pixel ballpark stage bound to PixelBallparkCanvas.

const Style = preload("res://presentation/pixel_art_style.gd")
const Landmarks = preload("res://world/view_landmarks.gd")

var host: PixelBallparkCanvas


func _init(canvas: PixelBallparkCanvas) -> void:
	host = canvas

func draw_sky_band(palette: Dictionary, left: int, right: int, top: int, horizon: int, clip_weather := false) -> void:
	var glow := clampi(int(float(horizon - top) * 0.3), 4, 14)
	var glow_top := horizon - glow
	Style.pixel_rect(host, Rect2(left, top, right - left, horizon - top), palette.sky_high)
	Style.pixel_rect(host, Rect2(left, glow_top, right - left, glow), palette.sky_low)
	# Drip-and-drift seam (§5.1): the horizon glow undulates with overhangs so
	# no straight atmospheric seam runs longer than 24 cells.
	var x := left
	while x < right:
		var seed := 71 + x * 13 + horizon * 7
		var run := mini(6 + int(Style.hash01(seed) * 9.0), right - x)
		var lift := int(Style.hash01(seed + 5) * 3.0) - 1
		if lift > 0:
			Style.pixel_rect(host, Rect2(x, glow_top - lift, run, lift), palette.sky_low)
		elif lift < 0:
			Style.pixel_rect(host, Rect2(x, glow_top, run, -lift), palette.sky_high)
		x += run
	# 2x1 checker dither, two rows, at the one permitted sky seam (§5.3).
	dither_row(left, right, glow_top - 3, palette.sky_low, 0)
	dither_row(left, right, glow_top + 2, palette.sky_high, 1)
	if host.mood == "night":
		draw_stars(palette, left, right, top, glow_top - 2)
	else:
		draw_clouds(palette, left, right, top, glow_top, clip_weather)

func dither_row(left: int, right: int, y: int, color: Color, phase: int) -> void:
	var x := left + posmod(y + phase, 2) * 2
	while x < right:
		Style.pixel_rect(host, Rect2(x, y, mini(2, right - x), 1), color)
		x += 4

func draw_stars(palette: Dictionary, left: int, right: int, top: int, bottom: int) -> void:
	if bottom <= top + 3:
		return
	# Static field of single-cell stars, capped under 40 (§7.7); singles are on
	# the sanctioned accent list (§5.1).
	var count := clampi(int((right - left) * 38.0 / 320.0), 8, 38)
	for index in range(count):
		var x := left + 1 + int(Style.hash01(900 + index * 13) * float(right - left - 3))
		var y := top + 2 + int(Style.hash01(1200 + index * 17) * float(bottom - top - 3))
		var color: Color = palette.window_lit if index % 7 == 0 else palette.cloud_lit
		Style.pixel_rect(host, Rect2(x, y, 1, 1), color)

func draw_clouds(palette: Dictionary, left: int, right: int, top: int, bottom: int, clip := false) -> void:
	var count := 3 if host.mood == "day" else 2
	var drift := int(host.anim_time * 0.5)
	var span := (right - left - 22) if clip else (right - left + 48)
	span = maxi(span, 24)
	for index in range(count):
		var base := int(Style.hash01(3100 + index * 97) * float(span))
		var x := (left if clip else left - 24) + posmod(base - drift, span)
		var y := top + 3 + int(Style.hash01(3400 + index * 61) * float(maxi(2, bottom - top - 10)))
		draw_cloud_stamp(x, y, index % 3, palette)

func draw_cloud_stamp(x: int, y: int, kind: int, palette: Dictionary) -> void:
	# Hand-authored cumulus clusters: lit crowns over shaded bellies, every
	# blob at least two cells (§5.1).
	match kind:
		0:
			Style.pixel_rect(host, Rect2(x + 2, y + 3, 16, 2), palette.cloud_shade)
			Style.pixel_rect(host, Rect2(x, y + 4, 20, 1), palette.cloud_shade)
			Style.pixel_rect(host, Rect2(x + 4, y, 7, 3), palette.cloud_lit)
			Style.pixel_rect(host, Rect2(x + 11, y + 1, 5, 2), palette.cloud_lit)
			Style.pixel_rect(host, Rect2(x + 2, y + 2, 3, 2), palette.cloud_lit)
		1:
			Style.pixel_rect(host, Rect2(x + 1, y + 2, 11, 2), palette.cloud_shade)
			Style.pixel_rect(host, Rect2(x, y + 3, 14, 1), palette.cloud_shade)
			Style.pixel_rect(host, Rect2(x + 3, y, 6, 3), palette.cloud_lit)
			Style.pixel_rect(host, Rect2(x + 9, y + 1, 3, 2), palette.cloud_lit)
		_:
			Style.pixel_rect(host, Rect2(x + 2, y + 1, 8, 2), palette.cloud_shade)
			Style.pixel_rect(host, Rect2(x, y + 2, 12, 2), palette.cloud_shade)
			Style.pixel_rect(host, Rect2(x + 4, y, 5, 2), palette.cloud_lit)


# --- Band 2: sea -------------------------------------------------------------

func draw_sea_band(palette: Dictionary, left: int, right: int, horizon: int, bottom: int, seed_base: int) -> void:
	var span := right - left
	var mid := horizon + maxi(2, int(float(bottom - horizon) * 0.42))
	Style.pixel_rect(host, Rect2(left, horizon, span, mid - horizon), palette.sea_far)
	Style.pixel_rect(host, Rect2(left, mid, span, bottom - mid), palette.sea_near)
	# Swell clusters break the horizon seam (§5.1: no straight seam > 24 cells).
	var x := left
	while x < right:
		var seed := seed_base + x * 11
		if Style.hash01(seed + 3) > 0.45:
			Style.pixel_rect(host, Rect2(x, horizon - 1, mini(3, right - x), 1), palette.sea_far)
		x += 8 + int(Style.hash01(seed) * 7.0)
	# Far->near plane seam: overhang drift plus the permitted 2-row checker.
	x = left
	while x < right:
		var seed := seed_base + 51 + x * 17
		var run := mini(6 + int(Style.hash01(seed) * 9.0), right - x)
		if Style.hash01(seed + 7) > 0.5:
			Style.pixel_rect(host, Rect2(x, mid - 1, run, 1), palette.sea_near)
		x += run
	dither_row(left, right, mid, palette.sea_far, 1)
	# Directional wave grain: horizontal cluster dashes drifting one cell per
	# second, clumped rather than uniform (§5.1).
	var drift := int(host.anim_time)
	var far_count := maxi(4, int(span / 20.0))
	for index in range(far_count):
		var seed := seed_base + 200 + index * 31
		var wx := left + posmod(int(Style.hash01(seed) * float(span)) + drift, span)
		var wy := horizon + 1 + posmod(index * 3 + int(Style.hash01(seed + 1) * 7.0), maxi(1, mid - horizon - 1))
		Style.pixel_rect(host, Rect2(wx, wy, mini(2 + index % 2, right - wx), 1), palette.sea_near)
		if Style.hash01(seed + 2) > 0.55 and wx + 5 < right:
			Style.pixel_rect(host, Rect2(wx + 3, wy + 1, 2, 1), palette.sea_near)
	var near_count := maxi(3, int(span / 26.0))
	for index in range(near_count):
		var seed := seed_base + 300 + index * 37
		var wx := left + posmod(int(Style.hash01(seed) * float(span)) + drift, span)
		var wy := mid + 1 + posmod(index * 2 + int(Style.hash01(seed + 1) * 5.0), maxi(1, bottom - mid - 1))
		Style.pixel_rect(host, Rect2(wx, wy, mini(3 + index % 3, right - wx), 1), palette.sea_glint)
	# Clustered glints: a few anchors each catching 2-4 sparks (§7.2). Singles
	# are sanctioned sea-glint accents.
	var anchor_count := 2 if host.mood == "night" else 5
	for anchor in range(anchor_count):
		var seed := seed_base + 700 + anchor * 53
		var ax := left + 6 + int(Style.hash01(seed) * float(maxi(1, span - 14)))
		var ay := mid + 1 + int(Style.hash01(seed + 1) * float(maxi(1, bottom - mid - 3)))
		for j in range(2 + int(Style.hash01(seed + 2) * 3.0)):
			var gx := ax + int(Style.hash01(seed + 3 + j * 7) * 7.0) - 3
			var gy := ay + int(Style.hash01(seed + 4 + j * 7) * 3.0) - 1
			var gw := 1 + int(Style.hash01(seed + 5 + j * 7) > 0.5)
			if gx >= left and gx + gw <= right and gy < bottom:
				Style.pixel_rect(host, Rect2(gx, gy, gw, 1), palette.sea_glint)
	if host.mood == "night":
		# Moonlight path widening toward the viewer, plus one blinking buoy
		# light (§3.4 night, §7.7).
		var moon_x := left + int(float(span) * 0.68)
		var y := horizon + 1
		var row := 0
		while y < bottom - 1:
			var seed := seed_base + 400 + row * 23
			var sway := int(Style.hash01(seed) * 5.0) - 2
			var w := 2 + int(Style.hash01(seed + 1) * 2.0) + int(row / 4.0)
			var px := moon_x + sway - int(row / 3.0)
			Style.pixel_rect(host, Rect2(px, y, mini(w, right - px), 1), palette.sea_glint)
			y += 2
			row += 1
		if int(host.anim_time * 1.2) % 2 == 0:
			Style.pixel_rect(host, Rect2(left + int(float(span) * 0.22), mid + 2, 1, 1), palette.stitch_red)


# --- Band 3: wharf skyline ---------------------------------------------------

func draw_steam(palette: Dictionary, x: int, y: int) -> void:
	# Cannery steam loop: three puffs rising on whole cells; golden re-grades
	# the plume to cloud_shade, night skips it.
	if host.mood == "night":
		return
	var color: Color = palette.cloud_lit if host.mood == "day" else palette.cloud_shade
	var tick := int(host.crowd_motion_tick / 8.0)
	for k in range(3):
		var phase := posmod(tick + k * 4, 12)
		var px := x + (int(phase / 4.0) % 2)
		var w := 3 if phase < 5 else 2
		var h := 2 if phase < 9 else 1
		Style.pixel_rect(host, Rect2(px - int(w / 2.0), y - phase, w, h), color)

func draw_gulls(palette: Dictionary, positions: Array) -> void:
	# Gull pairs holding station, bobbing one cell at most (day only). When
	# the harbor bell rings they scatter from the roofline once (§9.6),
	# climbing away on whole-cell tick steps until they leave the frame.
	if host.mood != "day":
		return
	if host.bell_timer > 0.0:
		var flight := host._bell_ticks()
		if flight > 26:
			return
		for index in range(positions.size()):
			var at: Vector2 = positions[index]
			var direction := -1 if index % 2 == 0 else 1
			var gx := int(at.x) + direction * (int(flight / 2.0) + index % 3)
			var gy := int(at.y) - int(flight / 3.0) - index % 2
			var flap := (int(flight / 2.0) + index) % 2
			Style.pixel_rect(host, Rect2(gx, gy, 2, 1), palette.town_near)
			Style.pixel_rect(host, Rect2(gx + 2, gy - 1 + flap, 2, 1), palette.town_near)
		return
	var bob := int(host.crowd_motion_tick / 14.0) % 2
	for index in range(positions.size()):
		var at: Vector2 = positions[index]
		var y := int(at.y) - ((bob + index) % 2)
		Style.pixel_rect(host, Rect2(at.x, y, 2, 1), palette.town_near)
		Style.pixel_rect(host, Rect2(at.x + 2, y - 1, 2, 1), palette.town_near)

func draw_leaf_drift(palette: Dictionary) -> void:
	# Golden-only slow leaf drift, capped well under 12 particles (§7.7).
	if host.mood != "golden":
		return
	for index in range(10):
		var seed := 8200 + index * 67
		var speed := 2 + index % 2
		var x := posmod(int(Style.hash01(seed) * 352.0) - int(host.anim_time * float(speed)), 352) - 16
		var y := 48 + int(Style.hash01(seed + 3) * 92.0) + (int(host.crowd_motion_tick / 10.0) + index) % 3 - 1
		Style.pixel_rect(host, Rect2(x, y, 1, 1), palette.clay_lit)

func draw_ferry(palette: Dictionary, y: int) -> void:
	# Intro ferry crossing the near water on a slow one-cell-per-second loop
	# (§6.1), windows lit in every host.mood.
	var x := 356 - posmod(int(host.anim_time), 420)
	if x < -24 or x > 336:
		return
	Style.pixel_rect(host, Rect2(x, y - 2, 15, 3), palette.town_near)
	Style.pixel_rect(host, Rect2(x + 3, y - 5, 8, 3), palette.seat_board)
	Style.pixel_rect(host, Rect2(x + 12, y - 6, 2, 2), palette.town_near)
	for w in range(3):
		Style.pixel_rect(host, Rect2(x + 4 + w * 3, y - 4, 1, 1), palette.window_lit)
	Style.pixel_rect(host, Rect2(x + 16, y, 3, 1), palette.sea_glint)

func draw_trawler(palette: Dictionary, x: int, y: int) -> void:
	# Moored trawler off the center-field wall (§6.3), one-cell harbor bob.
	var bob := int(host.crowd_motion_tick / 30.0) % 2
	var base := y - bob
	Style.pixel_rect(host, Rect2(x, base - 2, 11, 2), palette.town_near)
	Style.pixel_rect(host, Rect2(x + 6, base - 5, 4, 3), palette.town_near)
	Style.pixel_rect(host, Rect2(x + 2, base - 9, 1, 7), palette.town_near)
	Style.pixel_rect(host, Rect2(x + 1, base - 9, 3, 1), palette.town_near)
	if host.mood != "day":
		Style.pixel_rect(host, Rect2(x + 7, base - 4, 1, 1), palette.window_lit)
	Style.pixel_rect(host, Rect2(x - 3, base, 2, 1), palette.sea_glint)
	Style.pixel_rect(host, Rect2(x + 12, base, 2, 1), palette.sea_glint)


# --- Atmospheric veils (§7.8) ------------------------------------------------

func draw_mist_veil(palette: Dictionary, left: int, right: int, top: int, bottom: int) -> void:
	# The single sanctioned translucent mist rect over the far band (§7.8).
	var veil: Color = Style.veil_role("mist_veil", host.mood)
	Style.pixel_rect(host, Rect2(left, top, right - left, bottom - top), veil)

func draw_vignette(palette: Dictionary) -> void:
	# Stepped corner darkening (§7.8). Anchored to the screen so the fielding
	# follow offset never exposes an untreated corner.
	var veil: Color = Style.veil_role("vignette_veil", host.mood)
	var origin := -host.position
	for corner in range(4):
		var sx := 1.0 if corner % 2 == 0 else -1.0
		var sy := 1.0 if corner < 2 else -1.0
		var cx := origin.x if corner % 2 == 0 else origin.x + float(Style.ART_SIZE.x)
		var cy := origin.y if corner < 2 else origin.y + float(Style.ART_SIZE.y)
		for step in [Vector2(44, 4), Vector2(28, 9), Vector2(14, 15)]:
			var rx: float = cx if sx > 0.0 else cx - step.x
			var ry: float = cy if sy > 0.0 else cy - step.y
			Style.pixel_rect(host, Rect2(rx, ry, step.x, step.y), veil)


# --- Views -------------------------------------------------------------------


