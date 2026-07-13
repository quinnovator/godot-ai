extends RefCounted

## Pixel ballpark stage bound to PixelBallparkCanvas.

const Style = preload("res://presentation/pixel_art_style.gd")
const Landmarks = preload("res://world/view_landmarks.gd")

var host: PixelBallparkCanvas


func _init(canvas: PixelBallparkCanvas) -> void:
	host = canvas

func draw_intro(palette: Dictionary) -> void:
	var bands: Dictionary = Landmarks.BAND_DATUMS.intro
	var horizon: int = bands.horizon
	host.atmosphere.draw_sky_band(palette, 0, 320, 0, horizon)
	host.skyline.draw_skyline_row(palette, horizon, palette.town_far, false, [
		["hill", -8, 60], ["hill", 40, 44], ["sheds", 92, 3], ["crane", 132, 0],
		["hill", 152, 52], ["masts", 198, 4], ["sheds", 238, 2], ["hill", 264, 48],
	])
	host.atmosphere.draw_sea_band(palette, 0, 320, horizon, bands.sea_bottom, 40)
	host.skyline.draw_skyline_row(palette, horizon + 3, palette.town_near, true, [
		["cannery", 6, 1], ["warehouse", 24, 0], ["traps", 46, 0], ["masts", 54, 3],
		["warehouse", 240, 0], ["sheds", 262, 2],
	])
	host.skyline.stamp_lighthouse(palette, 294, horizon + 2)
	host.skyline.draw_lighthouse_beam(palette, Vector2(296, horizon - 13))
	host.atmosphere.draw_ferry(palette, 84)
	host.skyline.draw_breakwater(palette, 108, 108, 102)
	host.atmosphere.draw_mist_veil(palette, 0, 320, horizon - 14, 92)
	host.stands.draw_fireworks(palette, 0, 320, horizon)

	# Two-deck grandstands flank the open harbor window (§7.3); the harbor
	# bell tower rises from the left facade at the canonical (72, 88) anchor.
	host.stands.draw_grandstand(palette, Rect2i(0, 82, 108, 32), 100)
	host.stands.draw_grandstand(palette, Rect2i(212, 82, 108, 32), 160)
	host.stands.draw_bell_tower(palette, Landmarks.BELL_TOWER_ANCHOR, 22)
	host.atmosphere.draw_gulls(palette, [Vector2(88, 76), Vector2(96, 79), Vector2(230, 74), Vector2(238, 77)])

	# Low wall ring closes the harbor window and the seam under both stands.
	Style.pixel_rect(host, Rect2(0, bands.wall_top, 320, 4), palette.wall_pad)
	Style.pixel_rect(host, Rect2(0, bands.wall_top, 320, 1), palette.seat_board)

	# Playfield (bible §6.1, §7.4): the same organic field treatment as the
	# gameplay views, compressed into the postcard band between the wall ring
	# and the foreground dugout roof. Landmarks keep the legacy diamond
	# anchors: plate (160, 161), bags (198/160/122, 143/125/143).
	var field_top: int = bands.field_top
	var plate: Vector2 = Landmarks.plate("intro")
	Style.pixel_rect(host, Rect2(0, field_top, 320, 166 - field_top), palette.turf_main)
	host.playfield.draw_turf_mow_arcs(palette, plate, 0.5, Rect2i(0, field_top, 320, 166 - field_top), [
		Vector2(16, 28), Vector2(40, 54), Vector2(66, 82), Vector2(94, 112),
		Vector2(124, 144), Vector2(156, 178),
	])
	host.playfield.draw_warning_track(palette, 0, 320, field_top, 2, 2311)
	if host.mood == "night":
		# Night: the postcard field lifts only inside authored lamp pools
		# under the lit lightbank (§7.4); base night values elsewhere.
		host.playfield.draw_lamp_pool(palette, Vector2(208, 134), Vector2(30, 10))
		host.playfield.draw_lamp_pool(palette, Vector2(100, 144), Vector2(26, 9))
	else:
		# Stand shadow off the left grandstand; golden stretches it into the
		# long 2:1 stepped evening shadow (§7.4).
		host.playfield.draw_stand_shadow_stairs(palette, field_top + 2, 104 if host.mood == "golden" else 52, 8, 4)
	# Foul lines run from the plate to the wall base with their shadow-side
	# turf seat (§5.2); the on-clay stretches re-chalk after the dirt.
	host.playfield.chalk_seated_line(palette, plate, Vector2(69, field_top), palette.turf_shade)
	host.playfield.chalk_seated_line(palette, plate, Vector2(251, field_top), palette.turf_shade)
	# Irregular infield cutout around the bags, then the plate-area shade
	# crescent so the clay never reads as one flat wedge (§5.4).
	var clay_edge: Array[Vector2] = [
		Vector2(160, 167), Vector2(173, 163), Vector2(185, 158), Vector2(196, 152),
		Vector2(203, 147), Vector2(206, 141), Vector2(203, 135), Vector2(196, 130),
		Vector2(187, 126), Vector2(176, 122), Vector2(166, 120), Vector2(154, 120),
		Vector2(144, 122), Vector2(133, 126), Vector2(124, 130), Vector2(117, 135),
		Vector2(114, 141), Vector2(117, 147), Vector2(124, 152), Vector2(135, 158),
		Vector2(147, 163),
	]
	host.playfield.fill_organic(clay_edge, Vector2(160, 143), palette.clay_main)
	Style.pixel_ellipse(host, Vector2(160, 163), Vector2(7, 2), palette.clay_shade)
	var infield_grass: Array[Vector2] = [
		Vector2(160, 157), Vector2(175, 150), Vector2(189, 143), Vector2(175, 136),
		Vector2(160, 129), Vector2(145, 136), Vector2(131, 143), Vector2(145, 150),
	]
	host.playfield.fill_organic(infield_grass, Vector2(160, 143), palette.turf_shade)
	# 1-cell lit rim on the outfield-side edges plus mow ridges so the infield
	# grass never reads as one flat region (§5.2, §5.4).
	Style.pixel_line(host, Vector2(131, 143), Vector2(145, 136), palette.turf_main)
	Style.pixel_line(host, Vector2(145, 136), Vector2(160, 129), palette.turf_main)
	Style.pixel_line(host, Vector2(160, 129), Vector2(175, 136), palette.turf_main)
	Style.pixel_line(host, Vector2(175, 136), Vector2(189, 143), palette.turf_main)
	for ridge in [Vector2(146, 139), Vector2(171, 140), Vector2(139, 146), Vector2(176, 146), Vector2(158, 154)]:
		Style.pixel_rect(host, Rect2(ridge.x, ridge.y, 4, 1), palette.turf_shade)
	host.playfield.draw_rake_clusters(palette, clay_edge.slice(3, 19), Vector2(160, 143), [0.9, 0.8], 3541)
	# Chalk crossing clay takes its clay-side seat (§5.2).
	host.playfield.chalk_seated_line(palette, Vector2(166, 158), Vector2(204, 140), palette.clay_shade)
	host.playfield.chalk_seated_line(palette, Vector2(154, 158), Vector2(116, 140), palette.clay_shade)
	host.playfield.draw_chalk_box(palette, Rect2(151, 158, 5, 5))
	host.playfield.draw_chalk_box(palette, Rect2(165, 158, 5, 5))
	host.playfield.draw_mound(palette, Vector2(160, 146), Vector2(7, 3), Rect2(158, 145, 5, 1))
	host.playfield.draw_home_plate(palette, plate)
	host.playfield.draw_field_bag(palette, Vector2(198, 143))
	host.playfield.draw_field_bag(palette, Vector2(160, 125))
	host.playfield.draw_field_bag(palette, Vector2(122, 143))
	host.stands.draw_led_board(Vector2(134, 64), palette)
	# The lit lightbank tower is the intro's single warm pool (§6.1).
	host.stands.draw_lightbank(palette, 208, 44, 96)
	host.atmosphere.draw_leaf_drift(palette)
	# Foreground dugout-roof band anchors the bottom of the postcard.
	Style.pixel_rect(host, Rect2(0, 166, 320, 14), palette.ink)
	Style.pixel_rect(host, Rect2(0, 166, 320, 1), palette.ink_mid)
	for x in range(6, 320, 24):
		Style.pixel_rect(host, Rect2(x, 170, 10, 1), palette.ink_mid)

func draw_pitching(palette: Dictionary) -> void:
	var bands: Dictionary = Landmarks.BAND_DATUMS.pitching
	var horizon: int = bands.horizon
	host.atmosphere.draw_sky_band(palette, 0, 320, 0, horizon)
	host.skyline.draw_skyline_row(palette, horizon, palette.town_far, false, [
		["hill", -10, 56], ["crane", 44, 0], ["sheds", 96, 3], ["hill", 128, 46],
		["masts", 180, 5], ["hill", 246, 50], ["sheds", 284, 2],
	])
	host.atmosphere.draw_sea_band(palette, 0, 320, horizon, bands.sea_bottom, 90)
	# The near skyline stays lowest behind the mound so the pitcher reads
	# against water, not roofline clutter (§7.2).
	host.skyline.draw_skyline_row(palette, horizon + 3, palette.town_near, true, [
		["cannery", 18, 1], ["traps", 42, 0], ["masts", 190, 4], ["sheds", 262, 3],
	])
	host.skyline.stamp_lighthouse(palette, 312, horizon + 2)
	host.skyline.draw_breakwater(palette, 196, 44, horizon + 6)
	host.atmosphere.draw_mist_veil(palette, 0, 320, horizon - 14, bands.sea_bottom)
	host.stands.draw_fireworks(palette, 0, 320, horizon)

	# Two-deck grandstand ring in three sections; the quay-wall gaps keep the
	# harbor visible so the stands never form one unbroken wall (§6.2).
	Style.pixel_rect(host, Rect2(72, 70, 24, 2), palette.town_near)
	Style.pixel_rect(host, Rect2(208, 70, 24, 2), palette.town_near)
	host.stands.draw_grandstand(palette, Rect2i(0, 56, 72, 16), 210)
	host.stands.draw_grandstand(palette, Rect2i(96, 56, 112, 16), 220)
	host.stands.draw_grandstand(palette, Rect2i(232, 56, 88, 16), 230)
	host.stands.draw_bell_tower(palette, Vector2i(60, 64), 20)
	host.atmosphere.draw_gulls(palette, [Vector2(56, 50), Vector2(64, 53), Vector2(250, 48), Vector2(258, 51)])
	host.stands.draw_led_board(Vector2(126, 36), palette)

	# Outfield wall pad strip (pass 04 adds signage).
	Style.pixel_rect(host, Rect2(0, bands.wall_top, 320, bands.field_top - bands.wall_top), palette.wall_pad)
	Style.pixel_rect(host, Rect2(0, bands.wall_top, 320, 1), palette.seat_board)
	Style.pixel_rect(host, Rect2(0, bands.field_top - 1, 320, 1), palette.ink_mid)

	# Center-field pitching room: plate, mound, and second base share one clear
	# depth axis. First and third mirror around it, so the ground reads as a
	# baseball diamond before decoration or actors are added.
	var field_top: int = bands.field_top
	var diamond: Dictionary = Landmarks.diamond("pitching")
	var plate: Vector2 = diamond.plate
	var mound: Vector2 = diamond.mound
	var first: Vector2 = diamond.first
	var second: Vector2 = diamond.second
	var third: Vector2 = diamond.third
	Style.pixel_rect(host, Rect2(0, field_top, 320, 180 - field_top), palette.turf_main)
	host.playfield.draw_turf_mow_arcs(palette, plate, 0.5, Rect2i(0, field_top, 320, 180 - field_top), [
		Vector2(36, 50), Vector2(68, 82), Vector2(100, 116), Vector2(136, 150),
		Vector2(170, 186), Vector2(206, 222), Vector2(244, 262), Vector2(284, 302),
	])
	host.playfield.draw_warning_track(palette, 0, 320, field_top, 3, 1733)
	if host.mood == "night":
		host.playfield.draw_lamp_pool(palette, Vector2(160, 126), Vector2(52, 18))
		host.playfield.draw_lamp_pool(palette, plate, Vector2(26, 10))
	else:
		host.playfield.draw_stand_shadow_stairs(palette, field_top + 3, 116 if host.mood == "golden" else 60, 8, 4)

	# Foul lines open symmetrically from home plate. A clean outer clay kite and
	# inset grass kite create recognizable base paths; the mound remains its own
	# visible island rather than disappearing inside an amorphous dirt mass.
	host.playfield.chalk_seated_line(palette, plate, Vector2(34, 180), palette.turf_shade)
	host.playfield.chalk_seated_line(palette, plate, Vector2(286, 180), palette.turf_shade)
	var outer_diamond: Array[Vector2] = [
		plate + Vector2(0, -2),
		first + Vector2(8, 0),
		second + Vector2(0, 7),
		third + Vector2(-8, 0),
	]
	host.playfield.fill_organic(outer_diamond, mound, palette.clay_shade)
	var clay_diamond: Array[Vector2] = [plate, first, second, third]
	host.playfield.fill_organic(clay_diamond, mound, palette.clay_main)
	var infield_grass: Array[Vector2] = [
		plate + Vector2(0, 9),
		first + Vector2(-9, 0),
		second + Vector2(0, -9),
		third + Vector2(9, 0),
	]
	host.playfield.fill_organic(infield_grass, mound, palette.turf_main)
	for index in range(infield_grass.size()):
		Style.pixel_line(host, infield_grass[index], infield_grass[(index + 1) % infield_grass.size()], palette.turf_shade)

	Style.pixel_ellipse(host, plate + Vector2(0, 1), Vector2(13, 6), palette.clay_shade)
	Style.pixel_ellipse(host, plate, Vector2(12, 5), palette.clay_main)
	for bag: Vector2 in [first, second, third]:
		Style.pixel_ellipse(host, bag + Vector2(0, 1), Vector2(5, 3), palette.clay_shade)
		Style.pixel_ellipse(host, bag, Vector2(4, 2), palette.clay_main)
	# Re-seat the two base paths most visible from center field.
	host.playfield.chalk_seated_line(palette, plate, first, palette.clay_shade)
	host.playfield.chalk_seated_line(palette, plate, third, palette.clay_shade)
	host.playfield.draw_chalk_box(palette, Rect2(plate.x - 15, plate.y - 5, 7, 9))
	host.playfield.draw_chalk_box(palette, Rect2(plate.x + 8, plate.y - 5, 7, 9))
	host.playfield.draw_mound(palette, mound, Vector2(16, 7), Rect2(mound.x - 5, mound.y - 1, 10, 1))
	host.playfield.draw_home_plate(palette, plate)
	host.playfield.draw_field_bag(palette, first)
	host.playfield.draw_field_bag(palette, second)
	host.playfield.draw_field_bag(palette, third)
	host.atmosphere.draw_leaf_drift(palette)


# --- Band 5: playfield helpers (pass 04) --------------------------------------

func draw_batting(palette: Dictionary) -> void:
	var bands: Dictionary = Landmarks.BAND_DATUMS.batting
	var horizon: int = bands.horizon
	host.atmosphere.draw_sky_band(palette, 0, 320, 0, horizon)
	host.skyline.draw_skyline_row(palette, horizon, palette.town_far, false, [
		["hill", -12, 54], ["sheds", 30, 2], ["crane", 62, 0], ["hill", 252, 58], ["masts", 288, 3],
	])
	host.atmosphere.draw_sea_band(palette, 0, 320, horizon, bands.sea_bottom, 140)
	# This camera faces open water: breakwater, moored trawler, and the quiet
	# lighthouse read above the center-field wall (§6.3).
	host.atmosphere.draw_trawler(palette, 138, 47)
	host.skyline.draw_breakwater(palette, 96, 128, 48)
	host.skyline.stamp_lighthouse(palette, 224, 50)
	host.skyline.draw_skyline_row(palette, horizon + 3, palette.town_near, true, [
		["traps", 8, 0], ["masts", 16, 3], ["sheds", 278, 2],
	])
	host.atmosphere.draw_mist_veil(palette, 0, 320, horizon - 14, bands.sea_bottom)
	host.stands.draw_fireworks(palette, 0, 320, horizon)

	Style.pixel_rect(host, Rect2(0, bands.wall_top, 320, 6), palette.wall_pad)
	Style.pixel_rect(host, Rect2(0, bands.wall_top, 320, 1), palette.seat_board)
	Style.pixel_rect(host, Rect2(0, bands.field_top - 1, 320, 1), palette.ink_mid)

	# Field surface (bible §6.3, §7.4): full-width turf so foul ground runs
	# beneath the corner stands, with mow-band arcs concentric on the
	# PixiballBroadcastCamera._project_batting plate anchor. The stands and
	# their skirts repaint on top so the foul corners stay theirs.
	var field_top: int = bands.field_top
	var plate: Vector2 = Landmarks.plate("batting")
	Style.pixel_rect(host, Rect2(0, field_top, 320, 180 - field_top), palette.turf_main)
	host.playfield.draw_turf_mow_arcs(palette, plate, 0.42, Rect2i(0, field_top, 320, 180 - field_top), [
		Vector2(30, 44), Vector2(62, 76), Vector2(96, 110), Vector2(130, 146),
		Vector2(166, 182), Vector2(202, 220), Vector2(238, 258),
	])
	if host.mood == "night":
		# Night: the field lifts only inside authored elliptical lamp pools
		# with stepped edges; base night values elsewhere (§7.4).
		host.playfield.draw_lamp_pool(palette, Vector2(160, 122), Vector2(50, 18))
		host.playfield.draw_lamp_pool(palette, Vector2(84, 106), Vector2(24, 8))
		host.playfield.draw_lamp_pool(palette, Vector2(240, 106), Vector2(24, 8))
	else:
		# Stand shadow off the left corner deck; golden stretches it into the
		# long 2:1 stepped evening shadow (§7.4).
		host.playfield.draw_stand_shadow_stairs(palette, field_top + 2, 148 if host.mood == "golden" else 72, 8, 4)

	# Two-deck corner stands frame the pitch corridor and their crowds thin
	# toward center so the corridor stays visually quiet (§6.3).
	host.stands.draw_grandstand(palette, Rect2i(0, 42, 72, 46), 310, 1)
	host.stands.draw_grandstand(palette, Rect2i(248, 42, 72, 46), 360, -1)
	# Under-deck walkway skirts slope the corner stands into foul ground.
	host._colored_polygon([Vector2(0, 88), Vector2(72, 88), Vector2(0, 103)], palette.ink_mid)
	host._colored_polygon([Vector2(320, 88), Vector2(248, 88), Vector2(320, 103)], palette.ink_mid)
	host.atmosphere.draw_gulls(palette, [Vector2(84, 36), Vector2(92, 39), Vector2(206, 34), Vector2(214, 37)])

	# Foul lines run through the first/third-base anchors ((191/129, 93)) to
	# the wall base with a turf seat on the shadow side (§5.2); the on-clay
	# stretches re-chalk after the dirt goes down.
	host.playfield.chalk_seated_line(palette, plate, Vector2(208, 60), palette.turf_shade)
	host.playfield.chalk_seated_line(palette, plate, Vector2(112, 60), palette.turf_shade)
	# Plate dirt circle with a shade crescent, then the organic infield cutout
	# sweeping around the base anchors and the clamped mound lane (160, 76).
	Style.pixel_ellipse(host, Vector2(160, 156), Vector2(15, 7), palette.clay_shade)
	Style.pixel_ellipse(host, Vector2(160, 155), Vector2(15, 7), palette.clay_main)
	var clay_edge: Array[Vector2] = [
		Vector2(166, 147), Vector2(172, 139), Vector2(177, 130), Vector2(182, 121),
		Vector2(187, 112), Vector2(192, 104), Vector2(197, 97), Vector2(199, 90),
		Vector2(196, 83), Vector2(188, 77), Vector2(176, 72), Vector2(160, 69),
		Vector2(144, 72), Vector2(132, 77), Vector2(124, 83), Vector2(121, 90),
		Vector2(123, 97), Vector2(128, 104), Vector2(133, 112), Vector2(138, 121),
		Vector2(143, 130), Vector2(148, 139), Vector2(154, 147),
	]
	host.playfield.fill_organic(clay_edge, Vector2(160, 104), palette.clay_main)
	var infield_grass: Array[Vector2] = [
		Vector2(160, 138), Vector2(171, 116), Vector2(184, 95), Vector2(172, 86),
		Vector2(160, 80), Vector2(148, 87), Vector2(136, 95), Vector2(149, 118),
	]
	host.playfield.fill_organic(infield_grass, Vector2(160, 106), palette.turf_shade)
	# 1-cell lit rim on the mound-side edges plus mow ridges so the infield
	# grass never reads as one flat region (§5.2, §5.4).
	Style.pixel_line(host, Vector2(136, 95), Vector2(148, 87), palette.turf_main)
	Style.pixel_line(host, Vector2(148, 87), Vector2(160, 80), palette.turf_main)
	Style.pixel_line(host, Vector2(160, 80), Vector2(172, 86), palette.turf_main)
	Style.pixel_line(host, Vector2(172, 86), Vector2(184, 95), palette.turf_main)
	for ridge in [Vector2(150, 112), Vector2(160, 105), Vector2(170, 112), Vector2(153, 124), Vector2(167, 124)]:
		Style.pixel_rect(host, Rect2(ridge.x, ridge.y, 4, 1), palette.turf_shade)
	host.playfield.draw_rake_clusters(palette, clay_edge.slice(6, 17), Vector2(160, 100), [0.88, 0.78], 6131)
	# Chalk crossing clay takes its clay-side seat (§5.2).
	host.playfield.chalk_seated_line(palette, Vector2(166, 143), Vector2(189, 98), palette.clay_shade)
	host.playfield.chalk_seated_line(palette, Vector2(154, 143), Vector2(131, 98), palette.clay_shade)
	host.playfield.draw_chalk_box(palette, Rect2(148, 148, 8, 8))
	host.playfield.draw_chalk_box(palette, Rect2(164, 148, 8, 8))
	host.playfield.draw_mound(palette, Vector2(160, 76), Vector2(10, 4), Rect2(157, 74, 7, 1))
	host.playfield.draw_home_plate(palette, plate)
	host.playfield.draw_field_bag(palette, Vector2(191, 93))
	host.playfield.draw_field_bag(palette, Vector2(129, 93))
	host.playfield.draw_field_bag(palette, Vector2(160, 71))
	host.stands.draw_led_board(Vector2(258, 25), palette)
	host.atmosphere.draw_leaf_drift(palette)

func draw_fielding(palette: Dictionary) -> void:
	# High harbor-balcony camera; margins extend past the design frame so the
	# quantized follow offset never exposes raw backing (§6.4).
	var bands: Dictionary = Landmarks.BAND_DATUMS.fielding
	var left := -32
	var right := 352
	var horizon: int = bands.horizon
	host.atmosphere.draw_sky_band(palette, left, right, -20, horizon)
	host.skyline.draw_skyline_row(palette, horizon, palette.town_far, false, [
		["hill", -28, 60], ["crane", 20, 0], ["sheds", 64, 3], ["hill", 120, 48],
		["masts", 170, 4], ["hill", 230, 52], ["sheds", 282, 2], ["hill", 318, 44],
	])
	host.atmosphere.draw_sea_band(palette, left, right, horizon, bands.sea_bottom, 190)
	host.skyline.draw_skyline_row(palette, horizon + 3, palette.town_near, true, [
		["cannery", 0, 1], ["masts", 96, 3], ["traps", 150, 0], ["sheds", 208, 3], ["cannery", 298, 0],
	])
	host.skyline.stamp_lighthouse(palette, 340, horizon + 2)
	host.skyline.draw_breakwater(palette, 118, 60, horizon + 6)
	host.atmosphere.draw_mist_veil(palette, left, right, horizon - 14, bands.sea_bottom)
	host.stands.draw_fireworks(palette, left, right, horizon)

	# Single-deck harbor strip in sections; quay walls fill the gaps so the
	# ring never reads as one unbroken wall (§7.3).
	for gap_x in [56, 168, 280]:
		Style.pixel_rect(host, Rect2(gap_x, bands.sea_bottom, 16, bands.wall_top - bands.sea_bottom), palette.town_near)
		Style.pixel_rect(host, Rect2(gap_x, bands.sea_bottom, 16, 1), palette.seat_board)
	host.stands.draw_grandstand(palette, Rect2i(left, bands.stands_top, 56 - left, bands.wall_top - bands.stands_top), 410)
	host.stands.draw_grandstand(palette, Rect2i(72, bands.stands_top, 96, bands.wall_top - bands.stands_top), 420)
	host.stands.draw_grandstand(palette, Rect2i(184, bands.stands_top, 96, bands.wall_top - bands.stands_top), 430)
	host.stands.draw_grandstand(palette, Rect2i(296, bands.stands_top, right - 296, bands.wall_top - bands.stands_top), 440)
	host.stands.draw_bell_tower(palette, Vector2i(300, 54), 16)
	Style.pixel_rect(host, Rect2(left, bands.wall_top - 1, right - left, 1), palette.ink_mid)
	Style.pixel_rect(host, Rect2(left, bands.wall_top, right - left, bands.field_top - bands.wall_top), palette.wall_pad)
	Style.pixel_rect(host, Rect2(left, bands.field_top - 1, right - left, 1), palette.ink_mid)
	host.atmosphere.draw_gulls(palette, [Vector2(30, 30), Vector2(38, 33), Vector2(276, 26), Vector2(284, 29)])
	host.stands.draw_led_board(Vector2(8, 30), palette)

	# Field surface (bible §6.4, §7.4): foul-ground apron, elliptical outfield
	# with mow arcs concentric on the plate anchor, a 3-cell clay warning
	# track, and the landmark diamond on the existing
	# PixiballBroadcastCamera._project_fielding anchors (plate (160, 155),
	# bases (201/160/119), mound (160, 119)).
	var field_top: int = bands.field_top
	var plate: Vector2 = Landmarks.plate("fielding")
	var field_center: Vector2 = Landmarks.diamond("fielding").field_center
	Style.pixel_rect(host, Rect2(left, field_top, right - left, 200 - field_top), palette.turf_shade)
	Style.pixel_ellipse(host, field_center, Vector2(141, 48), palette.turf_main)
	host.playfield.draw_turf_mow_arcs(palette, plate, 0.64, Rect2i(19, 70, 283, 97), [
		Vector2(14, 24), Vector2(34, 45), Vector2(56, 68), Vector2(80, 93),
		Vector2(106, 120), Vector2(134, 150),
	])
	if host.mood == "night":
		# Night: authored elliptical lamp pools with stair edges; base night
		# values everywhere else (§7.4).
		host.playfield.draw_lamp_pool(palette, Vector2(104, 96), Vector2(34, 12))
		host.playfield.draw_lamp_pool(palette, Vector2(216, 96), Vector2(34, 12))
		host.playfield.draw_lamp_pool(palette, Vector2(160, 140), Vector2(44, 14))
	else:
		# Stand shadow off the left ring; golden stretches the 2:1 stairs
		# across the outfield (§7.4).
		host.playfield.draw_stand_shadow_stairs(palette, field_top + 4, 150 if host.mood == "golden" else 64, 8, 4)
	# Warning-track ring and foul-ground clip, rasterized per row so the clay
	# band stays 3 cells deep with a ±1 organic grass seam (§5.1) while
	# cropping the mow arcs that spill past the outfield curve.
	for y in range(field_top + 4, 170):
		var dy := float(y - field_center.y)
		var rim_norm := 1.0 - dy * dy / (52.0 * 52.0)
		if rim_norm <= 0.0:
			continue
		var half_rim := sqrt(rim_norm) * 145.0
		var half_track := sqrt(maxf(0.0, 1.0 - dy * dy / (51.0 * 51.0))) * 144.0
		var wobble := floorf(Style.hash01(y * 47 + 9) * 2.0)
		var half_grass := maxf(0.0, sqrt(maxf(0.0, 1.0 - dy * dy / (48.0 * 48.0))) * 141.0 - wobble)
		host.playfield.mow_row(y, left, field_center.x - half_rim, left, right, palette.turf_shade)
		host.playfield.mow_row(y, field_center.x + half_rim, right, left, right, palette.turf_shade)
		host.playfield.mow_row(y, field_center.x - half_rim, field_center.x - half_track, left, right, palette.clay_shade)
		host.playfield.mow_row(y, field_center.x + half_track, field_center.x + half_rim, left, right, palette.clay_shade)
		host.playfield.mow_row(y, field_center.x - half_track, field_center.x - half_grass, left, right, palette.clay_main)
		host.playfield.mow_row(y, field_center.x + half_grass, field_center.x + half_track, left, right, palette.clay_main)
	# Foul-apron drift clusters keep the out-of-play grass from reading as one
	# flat region (§5.4): 2-4-cell horizontal dashes on deterministic jitter,
	# rejected anywhere inside the warning-track rim.
	var drift_x := left + 2
	while drift_x < right - 6:
		var drift_seed := 9001 + drift_x * 29
		for lane in range(2):
			var drift_y := field_top + 3 + int(Style.hash01(drift_seed + lane * 53) * 128.0)
			var nx := float(drift_x - field_center.x) / 146.0
			var ny := float(drift_y - field_center.y) / 53.0
			if nx * nx + ny * ny > 1.0:
				var dash := 2 + int(Style.hash01(drift_seed + 3 + lane) * 3.0)
				Style.pixel_rect(host, Rect2(drift_x, drift_y, dash, 1), palette.turf_shade)
		drift_x += 4 + int(Style.hash01(drift_seed + 7) * 7.0)
	# Foul lines run through the base anchors to the foul poles on the track,
	# seated on the shadow side (§5.2); on-clay stretches re-chalk after the
	# dirt, and 1-cell chalk poles mark the corners.
	host.playfield.chalk_seated_line(palette, plate, Vector2(266, 82), palette.turf_shade)
	host.playfield.chalk_seated_line(palette, plate, Vector2(54, 82), palette.turf_shade)
	Style.pixel_rect(host, Rect2(266, 78, 1, 4), palette.chalk_line)
	Style.pixel_rect(host, Rect2(54, 78, 1, 4), palette.chalk_line)
	# Plate dirt circle with a shade crescent, then the organic infield cutout.
	Style.pixel_ellipse(host, Vector2(160, 156), Vector2(9, 4), palette.clay_shade)
	Style.pixel_ellipse(host, Vector2(160, 155), Vector2(9, 4), palette.clay_main)
	var clay_edge: Array[Vector2] = [
		Vector2(160, 159), Vector2(172, 153), Vector2(182, 145), Vector2(192, 137),
		Vector2(202, 132), Vector2(207, 128), Vector2(205, 121), Vector2(196, 113),
		Vector2(186, 105), Vector2(175, 99), Vector2(166, 95), Vector2(160, 93),
		Vector2(154, 95), Vector2(145, 99), Vector2(134, 105), Vector2(124, 113),
		Vector2(115, 121), Vector2(113, 128), Vector2(118, 132), Vector2(128, 137),
		Vector2(138, 145), Vector2(148, 153),
	]
	host.playfield.fill_organic(clay_edge, Vector2(160, 127), palette.clay_main)
	var infield_grass: Array[Vector2] = [
		Vector2(160, 147), Vector2(178, 137), Vector2(193, 127), Vector2(177, 117),
		Vector2(160, 108), Vector2(143, 117), Vector2(127, 127), Vector2(142, 137),
	]
	host.playfield.fill_organic(infield_grass, Vector2(160, 127), palette.turf_shade)
	# 1-cell lit rim on the outfield-side edges plus mow ridges (§5.2, §5.4).
	Style.pixel_line(host, Vector2(127, 127), Vector2(143, 117), palette.turf_main)
	Style.pixel_line(host, Vector2(143, 117), Vector2(160, 108), palette.turf_main)
	Style.pixel_line(host, Vector2(160, 108), Vector2(177, 117), palette.turf_main)
	Style.pixel_line(host, Vector2(177, 117), Vector2(193, 127), palette.turf_main)
	for ridge in [Vector2(146, 127), Vector2(156, 132), Vector2(168, 127), Vector2(150, 120), Vector2(168, 121)]:
		Style.pixel_rect(host, Rect2(ridge.x, ridge.y, 4, 1), palette.turf_shade)
	host.playfield.draw_rake_clusters(palette, clay_edge.slice(5, 18), Vector2(160, 127), [0.9, 0.8], 7213)
	# Chalk crossing clay takes its clay-side seat (§5.2).
	host.playfield.chalk_seated_line(palette, Vector2(166, 151), Vector2(207, 123), palette.clay_shade)
	host.playfield.chalk_seated_line(palette, Vector2(154, 151), Vector2(113, 123), palette.clay_shade)
	host.playfield.draw_chalk_box(palette, Rect2(151, 151, 6, 6))
	host.playfield.draw_chalk_box(palette, Rect2(163, 151, 6, 6))
	host.playfield.draw_mound(palette, Vector2(160, 119), Vector2(6, 3), Rect2(158, 118, 4, 1))
	host.playfield.draw_home_plate(palette, plate)
	host.playfield.draw_field_bag(palette, Vector2(201, 127))
	host.playfield.draw_field_bag(palette, Vector2(160, 101))
	host.playfield.draw_field_bag(palette, Vector2(119, 127))
	host.atmosphere.draw_leaf_drift(palette)

func draw_dugout(palette: Dictionary) -> void:
	var bands: Dictionary = Landmarks.BAND_DATUMS.dugout
	# Interior stays cool and dark; the framed field is the warm pool the
	# bench longs for (§6.5).
	Style.pixel_rect(host, Rect2(0, 0, 320, 28), palette.ink_mid)
	for x in range(8, 320, 40):
		Style.pixel_rect(host, Rect2(x, 8, 2, 20), palette.stand_shell)
	# Roof beam crosses y=28..36 as an ink + stand-shell frame.
	Style.pixel_rect(host, Rect2(0, 28, 320, 8), palette.stand_shell)
	Style.pixel_rect(host, Rect2(0, 28, 320, 1), palette.seat_board)
	Style.pixel_rect(host, Rect2(0, 34, 320, 2), palette.ink)
	# Plank back wall and floor.
	Style.pixel_rect(host, Rect2(0, 36, 320, 144), palette.ink_mid)
	for y in range(40, 98, 5):
		for x in range((int(y / 5.0) % 2) * 11, 320, 22):
			Style.pixel_rect(host, Rect2(x, y, 12, 1), palette.stand_shell)
	Style.pixel_rect(host, Rect2(16, 102, 288, 3), palette.wood_dark)
	Style.pixel_rect(host, Rect2(16, 116, 288, 6), palette.wood)
	for x in range(24, 300, 36):
		Style.pixel_rect(host, Rect2(x, 122, 3, 26), palette.wood_dark)
	Style.pixel_rect(host, Rect2(0, 148, 320, 2), palette.ink)
	for x in range(10, 320, 26):
		Style.pixel_rect(host, Rect2(x, 158, 12, 1), palette.stand_shell)

	# The dugout opening frames the harbor postcard (§6.5): five mini-bands.
	Style.pixel_rect(host, Rect2(176, 36, 128, 60), palette.ink)
	host.atmosphere.draw_sky_band(palette, 180, 300, 40, bands.horizon, true)
	host.skyline.draw_skyline_row(palette, bands.horizon, palette.town_far, false, [
		["hill", 178, 44], ["masts", 216, 3], ["sheds", 252, 2],
	])
	host.atmosphere.draw_sea_band(palette, 180, 300, bands.horizon, bands.sea_bottom, 240)
	host.skyline.stamp_lighthouse(palette, 290, bands.horizon + 2)
	host.atmosphere.draw_mist_veil(palette, 180, 300, bands.horizon - 8, bands.sea_bottom)
	host.stands.draw_grandstand(palette, Rect2i(180, bands.stands_top, 120, bands.wall_top - bands.stands_top), 520)
	Style.pixel_rect(host, Rect2(180, bands.wall_top - 1, 120, 1), palette.ink_mid)
	Style.pixel_rect(host, Rect2(180, bands.wall_top, 120, bands.field_top - bands.wall_top), palette.wall_pad)
	# Playfield through the opening (bible §6.5, §7.4): the same organic turf,
	# clay cutout, seated chalk, and landmark treatment as the gameplay views,
	# compressed into the framed postcard. The plate holds the legacy
	# convergence point; bags stay on (214/236/258, 83/77/83).
	var field_top: int = bands.field_top
	var plate: Vector2 = Landmarks.plate("dugout")
	Style.pixel_rect(host, Rect2(180, field_top, 120, 92 - field_top), palette.turf_main)
	host.playfield.draw_turf_mow_arcs(palette, plate, 0.45, Rect2i(180, field_top, 120, 92 - field_top), [
		Vector2(8, 14), Vector2(21, 29), Vector2(37, 46), Vector2(55, 66), Vector2(76, 88),
	])
	host.playfield.draw_warning_track(palette, 180, 300, field_top, 2, 8117)
	if host.mood == "night":
		# Night: the framed field lifts inside one authored lamp pool (§7.4).
		host.playfield.draw_lamp_pool(palette, Vector2(240, 84), Vector2(26, 6))
	# Foul lines through the bag anchors with their shadow-side turf seat
	# (§5.2); the on-clay stretches re-chalk after the dirt.
	host.playfield.chalk_seated_line(palette, plate, Vector2(185, field_top), palette.turf_shade)
	host.playfield.chalk_seated_line(palette, plate, Vector2(287, field_top), palette.turf_shade)
	# Irregular infield cutout around the bags, then the plate-area shade
	# crescent so the clay never reads as one flat wedge (§5.4).
	var clay_edge: Array[Vector2] = [
		Vector2(236, 91), Vector2(245, 89), Vector2(254, 87), Vector2(261, 85),
		Vector2(264, 83), Vector2(261, 81), Vector2(254, 79), Vector2(245, 77),
		Vector2(236, 76), Vector2(227, 77), Vector2(218, 79), Vector2(211, 81),
		Vector2(208, 83), Vector2(211, 85), Vector2(218, 87), Vector2(227, 89),
	]
	host.playfield.fill_organic(clay_edge, Vector2(236, 83), palette.clay_main)
	Style.pixel_ellipse(host, Vector2(236, 90), Vector2(4, 1), palette.clay_shade)
	var infield_grass: Array[Vector2] = [
		Vector2(236, 87), Vector2(244, 85), Vector2(251, 83), Vector2(244, 81),
		Vector2(236, 79), Vector2(228, 81), Vector2(221, 83), Vector2(228, 85),
	]
	host.playfield.fill_organic(infield_grass, Vector2(236, 83), palette.turf_shade)
	# 1-cell lit rim on the outfield-side edges plus mow ridges (§5.2, §5.4).
	Style.pixel_line(host, Vector2(221, 83), Vector2(228, 81), palette.turf_main)
	Style.pixel_line(host, Vector2(228, 81), Vector2(236, 79), palette.turf_main)
	Style.pixel_line(host, Vector2(236, 79), Vector2(244, 81), palette.turf_main)
	Style.pixel_line(host, Vector2(244, 81), Vector2(251, 83), palette.turf_main)
	for ridge in [Vector2(226, 83), Vector2(243, 84), Vector2(232, 86)]:
		Style.pixel_rect(host, Rect2(ridge.x, ridge.y, 3, 1), palette.turf_shade)
	host.playfield.draw_rake_clusters(palette, clay_edge.slice(2, 15), Vector2(236, 83), [0.85], 8317)
	# Chalk crossing clay takes its clay-side seat (§5.2).
	host.playfield.chalk_seated_line(palette, Vector2(240, 88), Vector2(261, 82), palette.clay_shade)
	host.playfield.chalk_seated_line(palette, Vector2(232, 88), Vector2(211, 82), palette.clay_shade)
	host.playfield.draw_chalk_box(palette, Rect2(230, 87, 4, 4))
	host.playfield.draw_chalk_box(palette, Rect2(239, 87, 4, 4))
	host.playfield.draw_mound(palette, Vector2(236, 82), Vector2(3, 1), Rect2(235, 81, 3, 1))
	host.playfield.draw_home_plate(palette, plate)
	host.playfield.draw_field_bag(palette, Vector2(258, 83))
	host.playfield.draw_field_bag(palette, Vector2(236, 77))
	host.playfield.draw_field_bag(palette, Vector2(214, 83))
	# Light spill from the opening onto the dugout floor.
	Style.pixel_rect(host, Rect2(186, 150, 108, 5), palette.stand_shell)

	# Wall-mounted cage lamp: the quiet secondary beacon (§6.5).
	draw_cage_lamp(palette, Vector2(56, 44))
	host.stands.draw_bunting(Vector2(100, 38), palette, 0)
	host.stands.draw_bunting(Vector2(148, 38), palette, 1)

func draw_cage_lamp(palette: Dictionary, at: Vector2) -> void:
	Style.pixel_rect(host, Rect2(at.x - 3, at.y - 6, 6, 2), palette.stand_shell)
	Style.pixel_rect(host, Rect2(at.x - 2, at.y - 4, 4, 5), palette.lamp_glow)
	Style.pixel_rect(host, Rect2(at.x - 1, at.y - 3, 2, 3), palette.window_lit)
	Style.pixel_rect(host, Rect2(at.x - 2, at.y - 4, 1, 5), palette.stand_shell)
	Style.pixel_rect(host, Rect2(at.x + 1, at.y - 4, 1, 5), palette.stand_shell)
	Style.pixel_rect(host, Rect2(at.x - 3, at.y + 2, 6, 1), palette.lamp_glow)


# --- Grandstand, crowd, bell tower, LED board (§7.3, §7.5) --------------------
