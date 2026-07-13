extends RefCounted

## Pixel ballpark stage bound to PixelBallparkCanvas.

const Style = preload("res://presentation/pixel_art_style.gd")
const Landmarks = preload("res://world/view_landmarks.gd")

var host: PixelBallparkCanvas


func _init(canvas: PixelBallparkCanvas) -> void:
	host = canvas

func draw_turf_mow_arcs(palette: Dictionary, focus: Vector2, squash: float, region: Rect2i, arcs: Array) -> void:
	# Alternating turf_light arcs concentric on home plate (§7.4). Radii live
	# in ground space; squash foreshortens them into the view's perspective.
	# Seams wobble +/-1 cell on a 4-row rhythm so no band edge runs
	# mathematically straight (§5.1).
	var left := region.position.x
	var right := region.position.x + region.size.x
	for y in range(region.position.y, region.position.y + region.size.y):
		var dy := (float(y) - focus.y) / squash
		for index in range(arcs.size()):
			var band: Vector2 = arcs[index]
			var wobble := floorf(Style.hash01((y >> 2) * 53 + index * 19) * 2.0)
			var outer := band.y + wobble
			if absf(dy) >= outer:
				continue
			var inner := band.x + wobble
			var half_outer := sqrt(outer * outer - dy * dy)
			var half_inner := sqrt(maxf(0.0, inner * inner - dy * dy))
			if half_inner <= 0.0:
				mow_row(y, focus.x - half_outer, focus.x + half_outer, left, right, palette.turf_lit)
			else:
				mow_row(y, focus.x - half_outer, focus.x - half_inner, left, right, palette.turf_lit)
				mow_row(y, focus.x + half_inner, focus.x + half_outer, left, right, palette.turf_lit)

func mow_row(y: int, from_x: float, to_x: float, left: int, right: int, color: Color) -> void:
	var seg_left := clampi(roundi(from_x), left, right)
	var seg_right := clampi(roundi(to_x), left, right)
	if seg_right > seg_left:
		Style.pixel_rect(host, Rect2(seg_left, y, seg_right - seg_left, 1), color)

func draw_warning_track(palette: Dictionary, left: int, right: int, top: int, depth: int, seed: int) -> void:
	# Clay strip under the wall pads (§6.4) with 1-cell drip overhangs every
	# 6-14 cells so the grass seam never runs straight (§5.1).
	Style.pixel_rect(host, Rect2(left, top, right - left, depth), palette.clay_main)
	Style.pixel_rect(host, Rect2(left, top, right - left, 1), palette.clay_shade)
	var x := left + 4
	while x < right - 2:
		Style.pixel_rect(host, Rect2(x, top + depth, 2, 1), palette.clay_main)
		x += 6 + int(Style.hash01(seed + x) * 9.0)

func draw_stand_shadow_stairs(palette: Dictionary, top: int, reach: int, run: int, rise: int) -> void:
	# Left-anchored stepped stand shadow (§6.2/§7.4); run:rise = 2:1 at the
	# golden defaults.
	var width := reach
	var y := top
	while width > 0 and y < 180:
		Style.pixel_rect(host, Rect2(0, y, width, rise), palette.turf_shade)
		width -= run
		y += rise

func draw_lamp_pool(palette: Dictionary, center: Vector2, radius: Vector2) -> void:
	# Authored elliptical night lamp pool with a stepped stair edge (§7.4):
	# turf rim, turf_light body, and a one-rung lift at the core.
	Style.pixel_ellipse(host, center, radius + Vector2(4, 2), palette.turf_main)
	Style.pixel_ellipse(host, center, radius, palette.turf_lit)
	Style.pixel_ellipse(
		host,
		center,
		Vector2(maxf(2.0, radius.x - 6.0), maxf(1.0, radius.y - 3.0)),
		Style.shift_value(palette.turf_lit, 1),
	)

func chalk_seated_line(palette: Dictionary, from: Vector2, to: Vector2, seat: Color) -> void:
	# Chalk with its 1-cell shadow-side seat so it never halates into the
	# field (§5.2); pass turf_shadow over grass and clay_shadow over clay.
	Style.pixel_line(host, from + Vector2(0, 1), to + Vector2(0, 1), seat)
	Style.pixel_line(host, from, to, palette.chalk_line)

func fill_organic(points: Array[Vector2], pivot: Vector2, color: Color) -> void:
	# Fan-fill an irregular authored outline from an interior pivot so
	# concave drip edges rasterize correctly.
	for index in range(points.size()):
		var triangle: Array[Vector2] = [pivot, points[index], points[(index + 1) % points.size()]]
		host._colored_polygon(triangle, color)

func draw_rake_clusters(palette: Dictionary, arc: Array, pivot: Vector2, scales: Array, seed: int) -> void:
	# 2-cell clay_lit rake dashes following the infield arc (§7.4), placed on
	# inward-scaled copies of the arc chain with deterministic gaps (§5.1).
	for scale_index in range(scales.size()):
		var inset := float(scales[scale_index])
		for index in range(arc.size() - 1):
			var from: Vector2 = pivot + (arc[index] - pivot) * inset
			var to: Vector2 = pivot + (arc[index + 1] - pivot) * inset
			var steps := maxi(1, int(from.distance_to(to) / 7.0))
			for step in range(steps):
				var salt := seed + scale_index * 977 + index * 131 + step * 17
				if Style.hash01(salt) < 0.4:
					continue
				var at := from.lerp(to, (float(step) + 0.5) / float(steps)).round()
				Style.pixel_rect(host, Rect2(at.x, at.y, 2, 1), palette.clay_lit)

func draw_chalk_box(palette: Dictionary, rect: Rect2) -> void:
	# 1-cell chalk batter's box frame with its clay seat under the bottom rail.
	Style.pixel_rect(host, Rect2(rect.position.x, rect.end.y, rect.size.x, 1), palette.clay_shade)
	Style.pixel_rect(host, Rect2(rect.position.x, rect.position.y, rect.size.x, 1), palette.chalk_line)
	Style.pixel_rect(host, Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), palette.chalk_line)
	Style.pixel_rect(host, Rect2(rect.position.x, rect.position.y, 1, rect.size.y), palette.chalk_line)
	Style.pixel_rect(host, Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y), palette.chalk_line)

func draw_mound(palette: Dictionary, center: Vector2, radius: Vector2, rubber: Rect2) -> void:
	# Clay_lit crown over a shade crescent that bottoms out in ink, with the
	# chalk rubber seated on the crown (§7.4).
	Style.pixel_ellipse(host, center + Vector2(0, 1), radius, palette.ink_mid)
	Style.pixel_ellipse(host, center, radius, palette.clay_shade)
	Style.pixel_ellipse(host, center - Vector2(0, 1), radius - Vector2(1, 1), palette.clay_main)
	Style.pixel_ellipse(host, center - Vector2(0, 2), Vector2(radius.x - 4, radius.y - 2), palette.clay_lit)
	Style.pixel_rect(host, Rect2(rubber.position + Vector2(0, 1), rubber.size), palette.clay_shade)
	Style.pixel_rect(host, rubber, palette.chalk_line)

func draw_home_plate(palette: Dictionary, center: Vector2) -> void:
	# Proper 5-sided plate, point toward the catcher, seated on its shadow
	# side (§7.4, §5.2).
	Style.pixel_rect(host, Rect2(center.x - 1, center.y + 1, 3, 1), palette.clay_shade)
	Style.pixel_rect(host, Rect2(center.x - 1, center.y - 1, 3, 2), palette.chalk_line)
	Style.pixel_rect(host, Rect2(center.x, center.y - 2, 1, 1), palette.chalk_line)

func draw_field_bag(palette: Dictionary, center: Vector2) -> void:
	# 2x2 chalk bag with a 1-cell ink ground-contact shade (§7.4).
	Style.pixel_rect(host, Rect2(center.x - 1, center.y + 1, 1, 1), palette.ink)
	Style.pixel_rect(host, Rect2(center.x - 1, center.y - 1, 2, 2), palette.chalk_line)


