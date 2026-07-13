class_name PixelBallparkCanvas
extends Node2D

const Style = preload("res://presentation/pixel_art_style.gd")

const ART_SIZE := Style.ART_SIZE
const OUTPUT_SIZE := Style.OUTPUT_SIZE
const GRID_PIXEL_SIZE := Style.GRID_PIXEL_SIZE
const CROWD_STEP := 1.0 / 12.0
const VIEW_CROWD_COUNTS := {
	"intro": 288,
	"pitching": 240,
	"batting": 192,
	"fielding": 320,
	"dugout": 128,
}
const CROWD_REACTIONS := {
	"ball": {"seconds": 0.55, "strength": 0.16, "led": "BALL"},
	"called_strike": {"seconds": 0.85, "strength": 0.32, "led": "STRIKE"},
	"swinging_strike": {"seconds": 0.95, "strength": 0.40, "led": "STRIKE"},
	"strikeout": {"seconds": 1.75, "strength": 0.82, "led": "K"},
	"walk": {"seconds": 1.15, "strength": 0.42, "led": "WALK"},
	"foul": {"seconds": 0.70, "strength": 0.24, "led": "FOUL"},
	"single": {"seconds": 1.35, "strength": 0.55, "led": "SINGLE"},
	"double": {"seconds": 1.80, "strength": 0.72, "led": "DOUBLE"},
	"triple": {"seconds": 2.25, "strength": 0.88, "led": "TRIPLE"},
	"home_run": {"seconds": 3.20, "strength": 1.00, "led": "HOMERUN", "bell": true},
	"ground_out": {"seconds": 1.00, "strength": 0.34, "led": "OUT"},
	"fly_out": {"seconds": 1.00, "strength": 0.34, "led": "OUT"},
	"fielders_choice": {"seconds": 1.05, "strength": 0.38, "led": "OUT"},
	"out": {"seconds": 1.00, "strength": 0.34, "led": "OUT"},
}

# Five-horizon band datums per view in design-grid y (art bible §6). This
# table is the layout contract for the stands rebuild (pass 03) and the field
# rebuild (pass 04): sky owns 0..horizon, the two sea planes run
# horizon..sea_bottom (water slides behind the stands wherever the two bands
# overlap), the grandstand owns stands_top..wall_top, the outfield wall strip
# runs wall_top..field_top, and the playfield owns field_top..180. The dugout
# entry describes the harbor postcard framed by the dugout opening.
const BAND_DATUMS := {
	"intro": {"horizon": 58, "sea_bottom": 114, "stands_top": 82, "wall_top": 114, "field_top": 118},
	"pitching": {"horizon": 46, "sea_bottom": 72, "stands_top": 56, "wall_top": 72, "field_top": 78},
	"batting": {"horizon": 42, "sea_bottom": 56, "stands_top": 42, "wall_top": 54, "field_top": 60},
	"fielding": {"horizon": 36, "sea_bottom": 50, "stands_top": 48, "wall_top": 58, "field_top": 62},
	"dugout": {"horizon": 56, "sea_bottom": 63, "stands_top": 63, "wall_top": 73, "field_top": 75},
}

# The only two sanctioned translucent draws in the world renderer (bible
# §7.8): one mist rect over the far band and one stepped corner vignette.
const MIST_VEIL_ALPHA := {"day": 0.20, "golden": 0.26, "night": 0.34}
const VIGNETTE_ALPHA := {"day": 0.10, "golden": 0.16, "night": 0.24}

# Lit-window probability per candidate skyline cell; density scales with mood
# (bible §7.6: sparse by day, dense at night).
const WINDOW_DENSITY := {"day": 0.10, "golden": 0.45, "night": 0.90}

# Eight authored crowd clump stamps (bible §7.5), 3-6 cells each, anchored at
# their top-left inside a 4x3-cell footprint. "body" entries are
# [x, y, w, h] rects in the dark crowd mass tone; "heads" are single cells
# that read warm on the mood-rationed warm clumps; the optional "flag" cell
# extends a waver's arm with a muted team-trim tick. Heights are deliberately
# staggered (seated pairs low, standing fans tall) so runs of adjacent clumps
# aggregate into an undulating silhouette instead of a level stripe (§5.1).
# During reactions the traveling wave swaps each clump to its 1-cell-raised
# "arms up" variant (§9.5): heads lift one cell and the "arms" cells draw in
# the body tone. Indices are stable; the raise amplitude is exactly 1 cell.
const CROWD_CLUMP_STAMPS := [
	{"body": [[0, 1, 4, 1]], "heads": [[1, 0], [3, 0]], "arms": [[0, -1], [2, -1]]},
	{"body": [[0, 1, 3, 1], [1, 2, 2, 1]], "heads": [[1, 0]], "arms": [[0, -1], [2, -1]]},
	{"body": [[0, 2, 4, 1]], "heads": [[0, 1], [2, 1]], "arms": [[1, 0], [3, 0]]},
	{"body": [[0, 2, 3, 1], [2, 1, 1, 1]], "heads": [[1, 1]], "flag": [3, 0], "arms": [[0, 0], [2, 0]]},
	{"body": [[0, 2, 3, 1], [1, 1, 1, 1]], "heads": [[1, 0]], "arms": [[0, -1], [2, -1]]},
	{"body": [[0, 2, 2, 1], [2, 1, 2, 1]], "heads": [[0, 1], [3, 0]], "arms": [[1, 0], [2, -1]]},
	{"body": [[0, 1, 4, 1]], "heads": [[0, 0], [2, 0]], "arms": [[1, -1], [3, -1]]},
	{"body": [[1, 2, 3, 1], [2, 1, 1, 1]], "heads": [[1, 1]], "arms": [[0, 0], [3, 0]]},
]

# Reaction choreography tuning (§9.5-9.7): every value below is expressed in
# 12 fps crowd ticks or whole design cells so the presentation stays
# tick-quantized and deterministic. The wave front travels WAVE_SPEED cells
# per tick with a WAVE_BAND-cell raised band behind it; strength maps to the
# number of simultaneous fronts crossing each stand section.
const BELL_DURATION := 5.0
const WAVE_SPEED := 3
const WAVE_BAND := 9
const CAP_TOSS_STRENGTH := 0.7
const BIG_PLAY_STRENGTH := 0.55

# At most one warm-face clump per N clumps (bible §7.5 mood density ratios).
const CROWD_WARM_RATIO := {"day": 5, "golden": 3, "night": 8}

# Canonical harbor bell tower base on the intro view's left facade (bible
# §7.3/§9.6). Pass 08 consumes this anchor to stage the home-run rock and its
# stepped arc rings; the pitching/fielding towers scale from their own stands.
const BELL_TOWER_ANCHOR := Vector2i(72, 88)

var mood := "day"
var view_mode := "intro"
var _field_focus := Vector3.ZERO

var _anim_time := 0.0
var _crowd_accumulator := 0.0
var _crowd_motion_tick := 0
var _crowd_motion_sample := Vector3.ZERO
var _reaction_timer := 0.0
var _reaction_duration := 0.0
var _reaction_strength := 0.0
var _reaction_serial := 0
var _led_text := "PIXIBALL"
var _led_timer := 0.0
var _bell_timer := 0.0
var _burst_serial := 0
var _bursts: Array[Dictionary] = []


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -100
	set_process(true)
	queue_redraw()


func build() -> void:
	queue_redraw()


func set_mood(next_mood: String) -> void:
	var normalized := Style.normalized_mood(next_mood)
	if mood == normalized:
		return
	mood = normalized
	queue_redraw()


func set_view_mode(next_mode: String) -> void:
	var normalized := Style.normalized_view(next_mode)
	if view_mode == normalized:
		return
	view_mode = normalized
	_sync_field_offset()
	queue_redraw()


func set_field_focus(value: Vector3) -> void:
	if _field_focus.is_equal_approx(value):
		return
	_field_focus = value
	_sync_field_offset()


func react_to_play(outcome: String) -> void:
	var normalized := outcome.strip_edges().to_lower().replace(" ", "_")
	var reaction: Dictionary = CROWD_REACTIONS.get(normalized, {})
	if reaction.is_empty():
		return
	_reaction_duration = float(reaction.get("seconds", 0.8))
	_reaction_timer = _reaction_duration
	_reaction_strength = clampf(float(reaction.get("strength", 0.3)), 0.0, 1.0)
	_reaction_serial += 1
	flash_led(String(reaction.get("led", "PLAY")))
	if bool(reaction.get("bell", false)):
		swing_bell()
	queue_redraw()


func flash_led(message: String) -> void:
	_led_text = message.strip_edges().to_upper().left(9)
	if _led_text.is_empty():
		_led_text = "PIXIBALL"
	_led_timer = 1.5
	queue_redraw()


func swing_bell() -> void:
	_bell_timer = BELL_DURATION
	queue_redraw()


func burst(at: Vector3, color: Color, count: int) -> void:
	var origin := _project_world(at)
	var limited := clampi(count, 0, 64)
	for index in range(limited):
		var seed := 104729 + _burst_serial * 8191 + index * 131
		var angle := Style.hash01(seed) * TAU
		var speed := lerpf(10.0, 31.0, Style.hash01(seed + 17))
		_bursts.append({
			"origin": origin,
			"velocity": Vector2(cos(angle), sin(angle) - 0.32) * speed,
			"age": 0.0,
			"duration": lerpf(0.34, 0.68, Style.hash01(seed + 31)),
			"size": 1 + int(Style.hash01(seed + 47) > 0.72),
			"color": color,
		})
	_burst_serial += 1
	queue_redraw()


func crowd_state() -> Dictionary:
	var count := int(VIEW_CROWD_COUNTS.get(view_mode, 0))
	return {
		"sections": {"PixelCrowd/%s" % view_mode: count},
		"total_spectators": count,
		"animated_batches": 1,
		"strip_count": 0,
		"reaction_timer": _reaction_timer,
		"reaction_duration": _reaction_duration,
		"reaction_strength": _reaction_strength,
		"reaction_level": _reaction_level(),
		"reaction_serial": _reaction_serial,
		"motion_tick": _crowd_motion_tick,
		"motion_sample": _crowd_motion_sample,
		"led_timer": _led_timer,
		"bell_timer": _bell_timer,
		"mood": mood,
		"view_mode": view_mode,
		"art_size": ART_SIZE,
		"design_size": ART_SIZE,
		"output_size": OUTPUT_SIZE,
		"grid_pixel_size": GRID_PIXEL_SIZE,
	}


func _process(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	_anim_time += dt
	var redraw := false

	_crowd_accumulator += dt
	if _crowd_accumulator >= CROWD_STEP:
		var steps := maxi(1, int(floor(_crowd_accumulator / CROWD_STEP)))
		_crowd_accumulator -= float(steps) * CROWD_STEP
		_crowd_motion_tick += steps
		var response := _reaction_level()
		_crowd_motion_sample = Vector3(
			roundf(sin(float(_crowd_motion_tick) * 0.43) * response),
			roundf(maxf(0.0, sin(float(_crowd_motion_tick) * 0.71)) * response * 2.0),
			0.0,
		)
		redraw = true

	if _reaction_timer > 0.0:
		_reaction_timer = maxf(0.0, _reaction_timer - dt)
		if _reaction_timer == 0.0:
			_reaction_duration = 0.0
			_reaction_strength = 0.0
		redraw = true
	if _led_timer > 0.0:
		_led_timer = maxf(0.0, _led_timer - dt)
		redraw = true
	if _bell_timer > 0.0:
		_bell_timer = maxf(0.0, _bell_timer - dt)
		redraw = true

	for index in range(_bursts.size() - 1, -1, -1):
		_bursts[index]["age"] = float(_bursts[index].age) + dt
		if float(_bursts[index].age) >= float(_bursts[index].duration):
			_bursts.remove_at(index)
		redraw = true

	if redraw:
		queue_redraw()


func _draw() -> void:
	var palette := Style.palette(mood)
	Style.pixel_rect(self, Rect2(-32, -20, ART_SIZE.x + 64, ART_SIZE.y + 40), palette.ink0)
	match view_mode:
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
	_draw_bursts()
	_draw_vignette(palette)


# --- Band 1: sky -------------------------------------------------------------


func _draw_sky_band(palette: Dictionary, left: int, right: int, top: int, horizon: int, clip_weather := false) -> void:
	var glow := clampi(int(float(horizon - top) * 0.3), 4, 14)
	var glow_top := horizon - glow
	Style.pixel_rect(self, Rect2(left, top, right - left, horizon - top), palette.sky_high)
	Style.pixel_rect(self, Rect2(left, glow_top, right - left, glow), palette.sky_low)
	# Drip-and-drift seam (§5.1): the horizon glow undulates with overhangs so
	# no straight atmospheric seam runs longer than 24 cells.
	var x := left
	while x < right:
		var seed := 71 + x * 13 + horizon * 7
		var run := mini(6 + int(Style.hash01(seed) * 9.0), right - x)
		var lift := int(Style.hash01(seed + 5) * 3.0) - 1
		if lift > 0:
			Style.pixel_rect(self, Rect2(x, glow_top - lift, run, lift), palette.sky_low)
		elif lift < 0:
			Style.pixel_rect(self, Rect2(x, glow_top, run, -lift), palette.sky_high)
		x += run
	# 2x1 checker dither, two rows, at the one permitted sky seam (§5.3).
	_dither_row(left, right, glow_top - 3, palette.sky_low, 0)
	_dither_row(left, right, glow_top + 2, palette.sky_high, 1)
	if mood == "night":
		_draw_stars(palette, left, right, top, glow_top - 2)
	else:
		_draw_clouds(palette, left, right, top, glow_top, clip_weather)


func _dither_row(left: int, right: int, y: int, color: Color, phase: int) -> void:
	var x := left + posmod(y + phase, 2) * 2
	while x < right:
		Style.pixel_rect(self, Rect2(x, y, mini(2, right - x), 1), color)
		x += 4


func _draw_stars(palette: Dictionary, left: int, right: int, top: int, bottom: int) -> void:
	if bottom <= top + 3:
		return
	# Static field of single-cell stars, capped under 40 (§7.7); singles are on
	# the sanctioned accent list (§5.1).
	var count := clampi(int((right - left) * 38.0 / 320.0), 8, 38)
	for index in range(count):
		var x := left + 1 + int(Style.hash01(900 + index * 13) * float(right - left - 3))
		var y := top + 2 + int(Style.hash01(1200 + index * 17) * float(bottom - top - 3))
		var color: Color = palette.lamp_core if index % 7 == 0 else palette.cloud_lit
		Style.pixel_rect(self, Rect2(x, y, 1, 1), color)


func _draw_clouds(palette: Dictionary, left: int, right: int, top: int, bottom: int, clip := false) -> void:
	var count := 3 if mood == "day" else 2
	var drift := int(_anim_time * 0.5)
	var span := (right - left - 22) if clip else (right - left + 48)
	span = maxi(span, 24)
	for index in range(count):
		var base := int(Style.hash01(3100 + index * 97) * float(span))
		var x := (left if clip else left - 24) + posmod(base - drift, span)
		var y := top + 3 + int(Style.hash01(3400 + index * 61) * float(maxi(2, bottom - top - 10)))
		_draw_cloud_stamp(x, y, index % 3, palette)


func _draw_cloud_stamp(x: int, y: int, kind: int, palette: Dictionary) -> void:
	# Hand-authored cumulus clusters: lit crowns over shaded bellies, every
	# blob at least two cells (§5.1).
	match kind:
		0:
			Style.pixel_rect(self, Rect2(x + 2, y + 3, 16, 2), palette.cloud_shade)
			Style.pixel_rect(self, Rect2(x, y + 4, 20, 1), palette.cloud_shade)
			Style.pixel_rect(self, Rect2(x + 4, y, 7, 3), palette.cloud_lit)
			Style.pixel_rect(self, Rect2(x + 11, y + 1, 5, 2), palette.cloud_lit)
			Style.pixel_rect(self, Rect2(x + 2, y + 2, 3, 2), palette.cloud_lit)
		1:
			Style.pixel_rect(self, Rect2(x + 1, y + 2, 11, 2), palette.cloud_shade)
			Style.pixel_rect(self, Rect2(x, y + 3, 14, 1), palette.cloud_shade)
			Style.pixel_rect(self, Rect2(x + 3, y, 6, 3), palette.cloud_lit)
			Style.pixel_rect(self, Rect2(x + 9, y + 1, 3, 2), palette.cloud_lit)
		_:
			Style.pixel_rect(self, Rect2(x + 2, y + 1, 8, 2), palette.cloud_shade)
			Style.pixel_rect(self, Rect2(x, y + 2, 12, 2), palette.cloud_shade)
			Style.pixel_rect(self, Rect2(x + 4, y, 5, 2), palette.cloud_lit)


# --- Band 2: sea -------------------------------------------------------------


func _draw_sea_band(palette: Dictionary, left: int, right: int, horizon: int, bottom: int, seed_base: int) -> void:
	var span := right - left
	var mid := horizon + maxi(2, int(float(bottom - horizon) * 0.42))
	Style.pixel_rect(self, Rect2(left, horizon, span, mid - horizon), palette.sea_deep)
	Style.pixel_rect(self, Rect2(left, mid, span, bottom - mid), palette.sea_mid)
	# Swell clusters break the horizon seam (§5.1: no straight seam > 24 cells).
	var x := left
	while x < right:
		var seed := seed_base + x * 11
		if Style.hash01(seed + 3) > 0.45:
			Style.pixel_rect(self, Rect2(x, horizon - 1, mini(3, right - x), 1), palette.sea_deep)
		x += 8 + int(Style.hash01(seed) * 7.0)
	# Far->near plane seam: overhang drift plus the permitted 2-row checker.
	x = left
	while x < right:
		var seed := seed_base + 51 + x * 17
		var run := mini(6 + int(Style.hash01(seed) * 9.0), right - x)
		if Style.hash01(seed + 7) > 0.5:
			Style.pixel_rect(self, Rect2(x, mid - 1, run, 1), palette.sea_mid)
		x += run
	_dither_row(left, right, mid, palette.sea_deep, 1)
	# Directional wave grain: horizontal cluster dashes drifting one cell per
	# second, clumped rather than uniform (§5.1).
	var drift := int(_anim_time)
	var far_count := maxi(4, int(span / 20.0))
	for index in range(far_count):
		var seed := seed_base + 200 + index * 31
		var wx := left + posmod(int(Style.hash01(seed) * float(span)) + drift, span)
		var wy := horizon + 1 + posmod(index * 3 + int(Style.hash01(seed + 1) * 7.0), maxi(1, mid - horizon - 1))
		Style.pixel_rect(self, Rect2(wx, wy, mini(2 + index % 2, right - wx), 1), palette.sea_mid)
		if Style.hash01(seed + 2) > 0.55 and wx + 5 < right:
			Style.pixel_rect(self, Rect2(wx + 3, wy + 1, 2, 1), palette.sea_mid)
	var near_count := maxi(3, int(span / 26.0))
	for index in range(near_count):
		var seed := seed_base + 300 + index * 37
		var wx := left + posmod(int(Style.hash01(seed) * float(span)) + drift, span)
		var wy := mid + 1 + posmod(index * 2 + int(Style.hash01(seed + 1) * 5.0), maxi(1, bottom - mid - 1))
		Style.pixel_rect(self, Rect2(wx, wy, mini(3 + index % 3, right - wx), 1), palette.sea_light)
	# Clustered glints: a few anchors each catching 2-4 sparks (§7.2). Singles
	# are sanctioned sea-glint accents.
	var anchor_count := 2 if mood == "night" else 5
	for anchor in range(anchor_count):
		var seed := seed_base + 700 + anchor * 53
		var ax := left + 6 + int(Style.hash01(seed) * float(maxi(1, span - 14)))
		var ay := mid + 1 + int(Style.hash01(seed + 1) * float(maxi(1, bottom - mid - 3)))
		for j in range(2 + int(Style.hash01(seed + 2) * 3.0)):
			var gx := ax + int(Style.hash01(seed + 3 + j * 7) * 7.0) - 3
			var gy := ay + int(Style.hash01(seed + 4 + j * 7) * 3.0) - 1
			var gw := 1 + int(Style.hash01(seed + 5 + j * 7) > 0.5)
			if gx >= left and gx + gw <= right and gy < bottom:
				Style.pixel_rect(self, Rect2(gx, gy, gw, 1), palette.foam)
	if mood == "night":
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
			Style.pixel_rect(self, Rect2(px, y, mini(w, right - px), 1), palette.foam)
			y += 2
			row += 1
		if int(_anim_time * 1.2) % 2 == 0:
			Style.pixel_rect(self, Rect2(left + int(float(span) * 0.22), mid + 2, 1, 1), palette.stitch)


# --- Band 3: wharf skyline ---------------------------------------------------


func _draw_skyline_row(palette: Dictionary, base_y: int, fill: Color, detailed: bool, stamps: Array) -> void:
	# Two-row silhouette grammar (§7.2): the far row is pure shape; the near
	# row adds lit windows and sparse warm roof notes only.
	for stamp in stamps:
		var kind := String(stamp[0])
		var x := int(stamp[1])
		var param := int(stamp[2])
		match kind:
			"hill":
				_stamp_hill(x, base_y, param, fill)
			"cannery":
				_stamp_cannery(palette, x, base_y, fill, detailed, param == 1)
			"warehouse":
				_stamp_warehouse(palette, x, base_y, fill, detailed)
			"sheds":
				_stamp_sheds(palette, x, base_y, fill, detailed, param)
			"crane":
				_stamp_crane(x, base_y, fill)
			"masts":
				_stamp_masts(x, base_y, fill, param)
			"traps":
				_stamp_traps(x, base_y, fill)


func _stamp_hill(x: int, base_y: int, width: int, fill: Color) -> void:
	var height := maxi(3, int(width / 5.0))
	var half := int(width / 2.0)
	for row in range(height):
		var inset := int(float(half) * float(row) / float(height))
		Style.pixel_rect(self, Rect2(x + inset, base_y - height + row, width - inset * 2, 1), fill)


func _stamp_cannery(palette: Dictionary, x: int, base_y: int, fill: Color, detailed: bool, steaming: bool) -> void:
	# Gabled cannery with roof monitor and steam stack (§7.1).
	Style.pixel_rect(self, Rect2(x, base_y - 8, 14, 8), fill)
	for row in range(4):
		Style.pixel_rect(self, Rect2(x + 1 + row, base_y - 9 - row, 12 - row * 2, 1), fill)
	Style.pixel_rect(self, Rect2(x + 5, base_y - 14, 4, 3), fill)
	Style.pixel_rect(self, Rect2(x + 11, base_y - 15, 2, 6), fill)
	if detailed:
		Style.pixel_rect(self, Rect2(x + 5, base_y - 12, 3, 1), palette.brick_warm)
		_scatter_windows(x + 1, base_y - 6, 12, 2, x + 3)
		if steaming:
			_draw_steam(palette, x + 12, base_y - 16)


func _stamp_warehouse(palette: Dictionary, x: int, base_y: int, fill: Color, detailed: bool) -> void:
	Style.pixel_rect(self, Rect2(x, base_y - 6, 18, 6), fill)
	Style.pixel_rect(self, Rect2(x + 1, base_y - 7, 16, 1), fill)
	if detailed:
		Style.pixel_rect(self, Rect2(x + 3, base_y - 8, 4, 1), palette.brick_warm)
		_scatter_windows(x + 1, base_y - 5, 16, 2, x)


func _stamp_sheds(palette: Dictionary, x: int, base_y: int, fill: Color, detailed: bool, count: int) -> void:
	# Fish-shed rows: low gable teeth along the quay (§7.1).
	for index in range(maxi(1, count)):
		var sx := x + index * 7
		Style.pixel_rect(self, Rect2(sx, base_y - 4, 6, 4), fill)
		Style.pixel_rect(self, Rect2(sx + 1, base_y - 5, 4, 1), fill)
		Style.pixel_rect(self, Rect2(sx + 2, base_y - 6, 2, 1), fill)
		if detailed:
			if index % 2 == 0:
				Style.pixel_rect(self, Rect2(sx + 2, base_y - 6, 2, 1), palette.brick_warm)
			_scatter_windows(sx + 1, base_y - 3, 4, 1, x + index * 5)


func _stamp_crane(x: int, base_y: int, fill: Color) -> void:
	# Gantry crane: paired legs, deck, jib, counterweight, hanging cable.
	Style.pixel_rect(self, Rect2(x, base_y - 10, 1, 10), fill)
	Style.pixel_rect(self, Rect2(x + 5, base_y - 10, 1, 10), fill)
	Style.pixel_rect(self, Rect2(x - 1, base_y - 11, 8, 1), fill)
	Style.pixel_rect(self, Rect2(x + 2, base_y - 13, 14, 1), fill)
	Style.pixel_rect(self, Rect2(x + 1, base_y - 13, 3, 2), fill)
	Style.pixel_rect(self, Rect2(x - 3, base_y - 12, 3, 2), fill)
	Style.pixel_rect(self, Rect2(x + 14, base_y - 12, 1, 4), fill)
	Style.pixel_rect(self, Rect2(x + 13, base_y - 8, 2, 1), fill)


func _stamp_masts(x: int, base_y: int, fill: Color, count: int) -> void:
	# Irregular mast forest with 1-3 cell stair rigging runs (§7.2).
	for index in range(maxi(1, count)):
		var seed := 4700 + x * 3 + index * 41
		var mx := x + index * 4 + int(Style.hash01(seed) * 3.0)
		var height := 6 + int(Style.hash01(seed + 5) * 6.0)
		Style.pixel_rect(self, Rect2(mx, base_y - height, 1, height), fill)
		Style.pixel_rect(self, Rect2(mx - 1, base_y - height + 2, 3, 1), fill)
		var ry := base_y - height + 3
		var rx := mx + 1
		var run := 1 + (index % 3)
		while ry < base_y - 1 and rx < mx + 4:
			Style.pixel_rect(self, Rect2(rx, ry, 1, mini(run, base_y - 1 - ry)), fill)
			ry += run
			rx += 1
			run = 1 + ((run + 1) % 3)
	Style.pixel_rect(self, Rect2(x - 2, base_y - 2, maxi(1, count) * 4 + 5, 2), fill)


func _stamp_traps(x: int, base_y: int, fill: Color) -> void:
	# Stacked lobster traps by the quay edge (§7.1).
	Style.pixel_rect(self, Rect2(x, base_y - 2, 3, 2), fill)
	Style.pixel_rect(self, Rect2(x + 3, base_y - 2, 3, 2), fill)
	Style.pixel_rect(self, Rect2(x + 1, base_y - 4, 3, 2), fill)


func _stamp_lighthouse(palette: Dictionary, x: int, base_y: int) -> void:
	# Round banded lighthouse with a lamp room at the right skyline edge
	# (§7.1). The lamp stays a quiet lamp_glow note, never the focal warm.
	Style.pixel_rect(self, Rect2(x, base_y - 12, 4, 12), palette.skyline_near)
	Style.pixel_rect(self, Rect2(x, base_y - 9, 4, 2), palette.structure_light)
	Style.pixel_rect(self, Rect2(x, base_y - 5, 4, 2), palette.structure_light)
	Style.pixel_rect(self, Rect2(x - 1, base_y - 13, 6, 1), palette.skyline_near)
	var lamp: Color = palette.structure_light if mood == "day" else palette.lamp_glow
	Style.pixel_rect(self, Rect2(x + 1, base_y - 15, 2, 2), lamp)
	Style.pixel_rect(self, Rect2(x + 1, base_y - 16, 2, 1), palette.skyline_near)


func _draw_lighthouse_beam(palette: Dictionary, lamp: Vector2) -> void:
	# Stepped beam sweep every six seconds in golden/night (§6.1).
	if mood == "day":
		return
	var cycle := fmod(_anim_time, 6.0)
	if cycle >= 1.5:
		return
	var directions := [Vector2(-3, -1), Vector2(-3, 0), Vector2(-3, 1)]
	var direction: Vector2 = directions[clampi(int(cycle / 0.5), 0, 2)]
	for reach in range(1, 4):
		var at := lamp + direction * float(reach * 2)
		Style.pixel_rect(self, Rect2(at.round(), Vector2(2, 1)), palette.lamp_glow)


func _draw_breakwater(palette: Dictionary, x: int, width: int, y: int) -> void:
	# Stone breakwater with an irregular cap and a foam seam (§7.1); night fog
	# laps it with the permitted checker dither (§5.3).
	Style.pixel_rect(self, Rect2(x, y, width, 2), palette.skyline_near)
	var bx := x
	while bx < x + width:
		var seed := 6100 + bx * 19
		if Style.hash01(seed + 3) > 0.5:
			Style.pixel_rect(self, Rect2(bx, y - 1, mini(3, x + width - bx), 1), palette.skyline_near)
		if Style.hash01(seed + 9) > 0.35 and bx + 1 < x + width:
			Style.pixel_rect(self, Rect2(bx + 1, y + 2, mini(3, x + width - bx - 1), 1), palette.foam)
		bx += 6 + int(Style.hash01(seed) * 5.0)
	if mood == "night":
		_dither_row(x - 4, x + width + 4, y - 3, palette.haze, 0)
		_dither_row(x - 4, x + width + 4, y - 2, palette.haze, 1)


func _scatter_windows(x: int, y: int, width: int, rows: int, salt: int) -> void:
	# Lit-window notes; single cells are sanctioned window accents (§5.1) and
	# density follows the mood (§7.6).
	var palette := Style.palette(mood)
	var density := float(WINDOW_DENSITY.get(mood, 0.2))
	# Celebration (§9.7): every lit window pulses one value step for two ticks
	# of each 12-tick cycle while the town joins the party.
	var window: Color = palette.lamp_core
	if _celebrating() and posmod(_crowd_motion_tick, 12) < 2:
		window = Style.shift_value(window, 1)
	for row in range(rows):
		var wx := x
		while wx < x + width - 1:
			if Style.hash01(salt * 131 + wx * 7 + row * 57) < density:
				Style.pixel_rect(self, Rect2(wx, y + row * 2, 1, 1), window)
			wx += 3


# --- Weather notes (§7.7) ----------------------------------------------------


func _draw_steam(palette: Dictionary, x: int, y: int) -> void:
	# Cannery steam loop: three puffs rising on whole cells; golden re-grades
	# the plume to cloud_shade, night skips it.
	if mood == "night":
		return
	var color: Color = palette.cloud_lit if mood == "day" else palette.cloud_shade
	var tick := int(_crowd_motion_tick / 8.0)
	for k in range(3):
		var phase := posmod(tick + k * 4, 12)
		var px := x + (int(phase / 4.0) % 2)
		var w := 3 if phase < 5 else 2
		var h := 2 if phase < 9 else 1
		Style.pixel_rect(self, Rect2(px - int(w / 2.0), y - phase, w, h), color)


func _draw_gulls(palette: Dictionary, positions: Array) -> void:
	# Gull pairs holding station, bobbing one cell at most (day only). When
	# the harbor bell rings they scatter from the roofline once (§9.6),
	# climbing away on whole-cell tick steps until they leave the frame.
	if mood != "day":
		return
	if _bell_timer > 0.0:
		var flight := _bell_ticks()
		if flight > 26:
			return
		for index in range(positions.size()):
			var at: Vector2 = positions[index]
			var direction := -1 if index % 2 == 0 else 1
			var gx := int(at.x) + direction * (int(flight / 2.0) + index % 3)
			var gy := int(at.y) - int(flight / 3.0) - index % 2
			var flap := (int(flight / 2.0) + index) % 2
			Style.pixel_rect(self, Rect2(gx, gy, 2, 1), palette.skyline_near)
			Style.pixel_rect(self, Rect2(gx + 2, gy - 1 + flap, 2, 1), palette.skyline_near)
		return
	var bob := int(_crowd_motion_tick / 14.0) % 2
	for index in range(positions.size()):
		var at: Vector2 = positions[index]
		var y := int(at.y) - ((bob + index) % 2)
		Style.pixel_rect(self, Rect2(at.x, y, 2, 1), palette.skyline_near)
		Style.pixel_rect(self, Rect2(at.x + 2, y - 1, 2, 1), palette.skyline_near)


func _draw_leaf_drift(palette: Dictionary) -> void:
	# Golden-only slow leaf drift, capped well under 12 particles (§7.7).
	if mood != "golden":
		return
	for index in range(10):
		var seed := 8200 + index * 67
		var speed := 2 + index % 2
		var x := posmod(int(Style.hash01(seed) * 352.0) - int(_anim_time * float(speed)), 352) - 16
		var y := 48 + int(Style.hash01(seed + 3) * 92.0) + (int(_crowd_motion_tick / 10.0) + index) % 3 - 1
		Style.pixel_rect(self, Rect2(x, y, 1, 1), palette.brick_light)


func _draw_ferry(palette: Dictionary, y: int) -> void:
	# Intro ferry crossing the near water on a slow one-cell-per-second loop
	# (§6.1), windows lit in every mood.
	var x := 356 - posmod(int(_anim_time), 420)
	if x < -24 or x > 336:
		return
	Style.pixel_rect(self, Rect2(x, y - 2, 15, 3), palette.skyline_near)
	Style.pixel_rect(self, Rect2(x + 3, y - 5, 8, 3), palette.structure_light)
	Style.pixel_rect(self, Rect2(x + 12, y - 6, 2, 2), palette.skyline_near)
	for w in range(3):
		Style.pixel_rect(self, Rect2(x + 4 + w * 3, y - 4, 1, 1), palette.lamp_core)
	Style.pixel_rect(self, Rect2(x + 16, y, 3, 1), palette.foam)


func _draw_trawler(palette: Dictionary, x: int, y: int) -> void:
	# Moored trawler off the center-field wall (§6.3), one-cell harbor bob.
	var bob := int(_crowd_motion_tick / 30.0) % 2
	var base := y - bob
	Style.pixel_rect(self, Rect2(x, base - 2, 11, 2), palette.skyline_near)
	Style.pixel_rect(self, Rect2(x + 6, base - 5, 4, 3), palette.skyline_near)
	Style.pixel_rect(self, Rect2(x + 2, base - 9, 1, 7), palette.skyline_near)
	Style.pixel_rect(self, Rect2(x + 1, base - 9, 3, 1), palette.skyline_near)
	if mood != "day":
		Style.pixel_rect(self, Rect2(x + 7, base - 4, 1, 1), palette.lamp_core)
	Style.pixel_rect(self, Rect2(x - 3, base, 2, 1), palette.foam)
	Style.pixel_rect(self, Rect2(x + 12, base, 2, 1), palette.foam)


# --- Atmospheric veils (§7.8) ------------------------------------------------


func _draw_mist_veil(palette: Dictionary, left: int, right: int, top: int, bottom: int) -> void:
	# The single sanctioned translucent mist rect over the far band.
	var veil: Color = palette.haze
	veil.a = float(MIST_VEIL_ALPHA.get(mood, 0.2))
	Style.pixel_rect(self, Rect2(left, top, right - left, bottom - top), veil)


func _draw_vignette(palette: Dictionary) -> void:
	# Stepped corner darkening: three overlapping translucent rects per corner
	# accumulate discrete steps toward each corner. Anchored to the screen so
	# the fielding follow offset never exposes an untreated corner.
	var veil: Color = palette.ink0
	veil.a = float(VIGNETTE_ALPHA.get(mood, 0.12))
	var origin := -position
	for corner in range(4):
		var sx := 1.0 if corner % 2 == 0 else -1.0
		var sy := 1.0 if corner < 2 else -1.0
		var cx := origin.x if corner % 2 == 0 else origin.x + float(ART_SIZE.x)
		var cy := origin.y if corner < 2 else origin.y + float(ART_SIZE.y)
		for step in [Vector2(44, 4), Vector2(28, 9), Vector2(14, 15)]:
			var rx: float = cx if sx > 0.0 else cx - step.x
			var ry: float = cy if sy > 0.0 else cy - step.y
			Style.pixel_rect(self, Rect2(rx, ry, step.x, step.y), veil)


# --- Views -------------------------------------------------------------------


func _draw_intro(palette: Dictionary) -> void:
	var bands: Dictionary = BAND_DATUMS.intro
	var horizon: int = bands.horizon
	_draw_sky_band(palette, 0, 320, 0, horizon)
	_draw_skyline_row(palette, horizon, palette.skyline_far, false, [
		["hill", -8, 60], ["hill", 40, 44], ["sheds", 92, 3], ["crane", 132, 0],
		["hill", 152, 52], ["masts", 198, 4], ["sheds", 238, 2], ["hill", 264, 48],
	])
	_draw_sea_band(palette, 0, 320, horizon, bands.sea_bottom, 40)
	_draw_skyline_row(palette, horizon + 3, palette.skyline_near, true, [
		["cannery", 6, 1], ["warehouse", 24, 0], ["traps", 46, 0], ["masts", 54, 3],
		["warehouse", 240, 0], ["sheds", 262, 2],
	])
	_stamp_lighthouse(palette, 294, horizon + 2)
	_draw_lighthouse_beam(palette, Vector2(296, horizon - 13))
	_draw_ferry(palette, 84)
	_draw_breakwater(palette, 108, 108, 102)
	_draw_mist_veil(palette, 0, 320, horizon - 14, 92)
	_draw_fireworks(palette, 0, 320, horizon)

	# Two-deck grandstands flank the open harbor window (§7.3); the harbor
	# bell tower rises from the left facade at the canonical (72, 88) anchor.
	_draw_grandstand(palette, Rect2i(0, 82, 108, 32), 100)
	_draw_grandstand(palette, Rect2i(212, 82, 108, 32), 160)
	_draw_bell_tower(palette, BELL_TOWER_ANCHOR, 22)
	_draw_gulls(palette, [Vector2(88, 76), Vector2(96, 79), Vector2(230, 74), Vector2(238, 77)])

	# Low wall ring closes the harbor window and the seam under both stands.
	Style.pixel_rect(self, Rect2(0, bands.wall_top, 320, 4), palette.shadow_cool)
	Style.pixel_rect(self, Rect2(0, bands.wall_top, 320, 1), palette.structure_light)

	# Playfield (bible §6.1, §7.4): the same organic field treatment as the
	# gameplay views, compressed into the postcard band between the wall ring
	# and the foreground dugout roof. Landmarks keep the legacy diamond
	# anchors: plate (160, 161), bags (198/160/122, 143/125/143).
	var field_top: int = bands.field_top
	var plate := Vector2(160, 161)
	Style.pixel_rect(self, Rect2(0, field_top, 320, 166 - field_top), palette.turf)
	_draw_turf_mow_arcs(palette, plate, 0.5, Rect2i(0, field_top, 320, 166 - field_top), [
		Vector2(16, 28), Vector2(40, 54), Vector2(66, 82), Vector2(94, 112),
		Vector2(124, 144), Vector2(156, 178),
	])
	_draw_warning_track(palette, 0, 320, field_top, 2, 2311)
	if mood == "night":
		# Night: the postcard field lifts only inside authored lamp pools
		# under the lit lightbank (§7.4); base night values elsewhere.
		_draw_lamp_pool(palette, Vector2(208, 134), Vector2(30, 10))
		_draw_lamp_pool(palette, Vector2(100, 144), Vector2(26, 9))
	else:
		# Stand shadow off the left grandstand; golden stretches it into the
		# long 2:1 stepped evening shadow (§7.4).
		_draw_stand_shadow_stairs(palette, field_top + 2, 104 if mood == "golden" else 52, 8, 4)
	# Foul lines run from the plate to the wall base with their shadow-side
	# turf seat (§5.2); the on-clay stretches re-chalk after the dirt.
	_chalk_seated_line(palette, plate, Vector2(69, field_top), palette.turf_shadow)
	_chalk_seated_line(palette, plate, Vector2(251, field_top), palette.turf_shadow)
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
	_fill_organic(clay_edge, Vector2(160, 143), palette.clay)
	Style.pixel_ellipse(self, Vector2(160, 163), Vector2(7, 2), palette.clay_shadow)
	var infield_grass: Array[Vector2] = [
		Vector2(160, 157), Vector2(175, 150), Vector2(189, 143), Vector2(175, 136),
		Vector2(160, 129), Vector2(145, 136), Vector2(131, 143), Vector2(145, 150),
	]
	_fill_organic(infield_grass, Vector2(160, 143), palette.turf_shadow)
	# 1-cell lit rim on the outfield-side edges plus mow ridges so the infield
	# grass never reads as one flat region (§5.2, §5.4).
	Style.pixel_line(self, Vector2(131, 143), Vector2(145, 136), palette.turf)
	Style.pixel_line(self, Vector2(145, 136), Vector2(160, 129), palette.turf)
	Style.pixel_line(self, Vector2(160, 129), Vector2(175, 136), palette.turf)
	Style.pixel_line(self, Vector2(175, 136), Vector2(189, 143), palette.turf)
	for ridge in [Vector2(146, 139), Vector2(171, 140), Vector2(139, 146), Vector2(176, 146), Vector2(158, 154)]:
		Style.pixel_rect(self, Rect2(ridge.x, ridge.y, 4, 1), palette.turf_dark)
	_draw_rake_clusters(palette, clay_edge.slice(3, 19), Vector2(160, 143), [0.9, 0.8], 3541)
	# Chalk crossing clay takes its clay-side seat (§5.2).
	_chalk_seated_line(palette, Vector2(166, 158), Vector2(204, 140), palette.clay_shadow)
	_chalk_seated_line(palette, Vector2(154, 158), Vector2(116, 140), palette.clay_shadow)
	_draw_chalk_box(palette, Rect2(151, 158, 5, 5))
	_draw_chalk_box(palette, Rect2(165, 158, 5, 5))
	_draw_mound(palette, Vector2(160, 146), Vector2(7, 3), Rect2(158, 145, 5, 1))
	_draw_home_plate(palette, plate)
	_draw_field_bag(palette, Vector2(198, 143))
	_draw_field_bag(palette, Vector2(160, 125))
	_draw_field_bag(palette, Vector2(122, 143))
	_draw_led_board(Vector2(134, 64), palette)
	# The lit lightbank tower is the intro's single warm pool (§6.1).
	_draw_lightbank(palette, 208, 44, 96)
	_draw_leaf_drift(palette)
	# Foreground dugout-roof band anchors the bottom of the postcard.
	Style.pixel_rect(self, Rect2(0, 166, 320, 14), palette.ink0)
	Style.pixel_rect(self, Rect2(0, 166, 320, 1), palette.ink1)
	for x in range(6, 320, 24):
		Style.pixel_rect(self, Rect2(x, 170, 10, 1), palette.ink1)


func _draw_lightbank(palette: Dictionary, x: int, top: int, base: int) -> void:
	Style.pixel_rect(self, Rect2(x + 6, top + 10, 4, base - top - 10), palette.structure)
	Style.pixel_rect(self, Rect2(x + 7, top + 10, 1, base - top - 10), palette.structure_light)
	Style.pixel_rect(self, Rect2(x + 4, base - 2, 8, 2), palette.structure)
	Style.pixel_rect(self, Rect2(x, top, 16, 10), palette.structure)
	Style.pixel_rect(self, Rect2(x, top, 16, 1), palette.structure_light)
	# Night bell rock: the floodlight heads pulse one value step for two ticks
	# of every four-tick rock (§9.6).
	var head: Color = palette.lamp_core
	if mood == "night" and _bell_timer > 0.0 and posmod(_bell_ticks(), 4) < 2:
		head = Style.shift_value(head, 1)
	for row in range(2):
		for col in range(4):
			Style.pixel_rect(self, Rect2(x + 1 + col * 4, top + 2 + row * 4, 3, 3), head)
	# Stepped bloom above the head: 2 rings by day/golden, 3 at night (§7.6).
	var rings := 3 if mood == "night" else 2
	for ring in range(1, rings + 1):
		var span := 16 - ring * 4
		Style.pixel_rect(self, Rect2(x + int((16 - span) / 2.0), top - ring * 2, span, 1), palette.lamp_glow)
	Style.pixel_rect(self, Rect2(x + 2, top + 10, 12, 1), palette.lamp_glow)


func _draw_pitching(palette: Dictionary) -> void:
	var bands: Dictionary = BAND_DATUMS.pitching
	var horizon: int = bands.horizon
	_draw_sky_band(palette, 0, 320, 0, horizon)
	_draw_skyline_row(palette, horizon, palette.skyline_far, false, [
		["hill", -10, 56], ["crane", 44, 0], ["sheds", 96, 3], ["hill", 128, 46],
		["masts", 180, 5], ["hill", 246, 50], ["sheds", 284, 2],
	])
	_draw_sea_band(palette, 0, 320, horizon, bands.sea_bottom, 90)
	# The near skyline stays lowest behind the mound so the pitcher reads
	# against water, not roofline clutter (§7.2).
	_draw_skyline_row(palette, horizon + 3, palette.skyline_near, true, [
		["cannery", 18, 1], ["traps", 42, 0], ["masts", 190, 4], ["sheds", 262, 3],
	])
	_stamp_lighthouse(palette, 312, horizon + 2)
	_draw_breakwater(palette, 196, 44, horizon + 6)
	_draw_mist_veil(palette, 0, 320, horizon - 14, bands.sea_bottom)
	_draw_fireworks(palette, 0, 320, horizon)

	# Two-deck grandstand ring in three sections; the quay-wall gaps keep the
	# harbor visible so the stands never form one unbroken wall (§6.2).
	Style.pixel_rect(self, Rect2(72, 70, 24, 2), palette.skyline_near)
	Style.pixel_rect(self, Rect2(208, 70, 24, 2), palette.skyline_near)
	_draw_grandstand(palette, Rect2i(0, 56, 72, 16), 210)
	_draw_grandstand(palette, Rect2i(96, 56, 112, 16), 220)
	_draw_grandstand(palette, Rect2i(232, 56, 88, 16), 230)
	_draw_bell_tower(palette, Vector2i(60, 64), 20)
	_draw_gulls(palette, [Vector2(56, 50), Vector2(64, 53), Vector2(250, 48), Vector2(258, 51)])
	_draw_led_board(Vector2(126, 36), palette)

	# Outfield wall pad strip (pass 04 adds signage).
	Style.pixel_rect(self, Rect2(0, bands.wall_top, 320, bands.field_top - bands.wall_top), palette.shadow_cool)
	Style.pixel_rect(self, Rect2(0, bands.wall_top, 320, 1), palette.structure_light)
	Style.pixel_rect(self, Rect2(0, bands.field_top - 1, 320, 1), palette.ink1)

	# Field surface (bible §5, §6.2, §7.4): mow-band arcs concentric on home
	# plate, an organic clay cutout with rake clusters, seated chalk, and the
	# landmark set on the existing PixiballBroadcastCamera._project_pitching
	# anchors (plate group high-left, mound lower-right through the long lens).
	var field_top: int = bands.field_top
	var plate := Vector2(113, 92)
	Style.pixel_rect(self, Rect2(0, field_top, 320, 180 - field_top), palette.turf)
	_draw_turf_mow_arcs(palette, plate, 0.5, Rect2i(0, field_top, 320, 180 - field_top), [
		Vector2(36, 50), Vector2(68, 82), Vector2(100, 116), Vector2(136, 150),
		Vector2(170, 186), Vector2(206, 222), Vector2(244, 262), Vector2(284, 302),
	])
	_draw_warning_track(palette, 0, 320, field_top, 3, 1733)
	if mood == "night":
		# Night: the field lifts only inside authored elliptical lamp pools
		# with stepped edges; everything else keeps base night values (§7.4).
		_draw_lamp_pool(palette, Vector2(150, 134), Vector2(52, 18))
		_draw_lamp_pool(palette, Vector2(48, 118), Vector2(30, 11))
		_draw_lamp_pool(palette, Vector2(268, 97), Vector2(32, 11))
	else:
		# Stand shadow anchors depth over left foul territory (§6.2); golden
		# stretches it into the long 2:1 stepped evening shadow (§7.4).
		_draw_stand_shadow_stairs(palette, field_top + 3, 152 if mood == "golden" else 76, 8, 4)
	# Foul lines run full length beneath the cutout with a turf seat on the
	# shadow side (§5.2); the on-clay stretches are re-chalked after the dirt.
	_chalk_seated_line(palette, plate, Vector2(0, 166), palette.turf_shadow)
	_chalk_seated_line(palette, plate, Vector2(320, 180), palette.turf_shadow)
	# Plate dirt circle with a shade crescent, then the irregular infield
	# cutout whose near arc sweeps (60,150) -> (280,130) per §6.2; the near
	# edge lifts through mid-frame so quiet turf separates clay from the rail.
	Style.pixel_ellipse(self, Vector2(113, 94), Vector2(11, 5), palette.clay_shadow)
	Style.pixel_ellipse(self, Vector2(113, 93), Vector2(11, 5), palette.clay)
	var clay_edge: Array[Vector2] = [
		Vector2(109, 94), Vector2(100, 101), Vector2(90, 109), Vector2(79, 119),
		Vector2(68, 131), Vector2(61, 141), Vector2(60, 150), Vector2(77, 155),
		Vector2(97, 159), Vector2(121, 161), Vector2(149, 162), Vector2(177, 161),
		Vector2(203, 158), Vector2(230, 154), Vector2(252, 147), Vector2(268, 139),
		Vector2(280, 130), Vector2(263, 126), Vector2(243, 122), Vector2(221, 117),
		Vector2(198, 112), Vector2(174, 107), Vector2(150, 102), Vector2(132, 98),
		Vector2(120, 95),
	]
	_fill_organic(clay_edge, Vector2(170, 132), palette.clay)
	# Large turf intrusion hollows the wedge into a basepath band; the mound
	# rises through its right edge as a clay island (§5.4, §6.2).
	var turf_cut: Array[Vector2] = [
		Vector2(118, 104), Vector2(136, 109), Vector2(156, 115), Vector2(174, 121),
		Vector2(186, 128), Vector2(190, 137), Vector2(184, 145), Vector2(168, 150),
		Vector2(146, 152), Vector2(122, 150), Vector2(102, 144), Vector2(90, 136),
		Vector2(86, 127), Vector2(94, 116), Vector2(105, 108),
	]
	_fill_organic(turf_cut, Vector2(140, 130), palette.turf)
	# 1-cell lit rim on the intrusion's sun side, a turf_shade seat along its
	# shadow side, and sparse mow sheen/ridge dashes so the grass never reads
	# as one flat region (§5.2, §5.4).
	for index in [13, 14, 0, 1, 2, 3]:
		Style.pixel_line(self, turf_cut[index], turf_cut[(index + 1) % turf_cut.size()], palette.turf_light)
	for index in range(5, 10):
		Style.pixel_line(self, turf_cut[index], turf_cut[index + 1], palette.turf_shadow)
	for sheen in [Vector2(108, 118), Vector2(122, 121), Vector2(136, 124), Vector2(150, 128), Vector2(164, 132), Vector2(176, 137)]:
		Style.pixel_rect(self, Rect2(sheen.x, sheen.y, 3, 1), palette.turf_light)
	for ridge in [Vector2(100, 133), Vector2(114, 137), Vector2(128, 141), Vector2(142, 144), Vector2(158, 147)]:
		Style.pixel_rect(self, Rect2(ridge.x, ridge.y, 3, 1), palette.turf_dark)
	# Damp shadow-clay drifts hug the near arc and far basepath; lit raked
	# patches sit on the mound approach and third-base wing so the band breaks
	# into cool/warm sub-clusters instead of one value (§3.3, §5.4).
	var damp_left: Array[Vector2] = [
		Vector2(94, 147), Vector2(112, 152), Vector2(126, 155), Vector2(120, 158),
		Vector2(102, 156), Vector2(90, 151),
	]
	_fill_organic(damp_left, Vector2(106, 153), palette.clay_shadow)
	var damp_mid: Array[Vector2] = [
		Vector2(146, 154), Vector2(166, 156), Vector2(180, 154), Vector2(172, 159),
		Vector2(152, 159),
	]
	_fill_organic(damp_mid, Vector2(162, 157), palette.clay_shadow)
	var damp_path: Array[Vector2] = [
		Vector2(216, 118), Vector2(234, 122), Vector2(228, 126), Vector2(212, 122),
	]
	_fill_organic(damp_path, Vector2(222, 122), palette.clay_shadow)
	var raked_gate: Array[Vector2] = [
		Vector2(194, 146), Vector2(212, 148), Vector2(206, 152), Vector2(192, 150),
	]
	_fill_organic(raked_gate, Vector2(202, 149), palette.clay_light)
	var raked_wing: Array[Vector2] = [
		Vector2(70, 137), Vector2(84, 141), Vector2(80, 146), Vector2(66, 142),
	]
	_fill_organic(raked_wing, Vector2(75, 141), palette.clay_light)
	# Each bag keeps a small dirt pad so the cutout bag sits on clay, not turf.
	Style.pixel_ellipse(self, Vector2(150, 125), Vector2(5, 2), palette.clay_shadow)
	Style.pixel_ellipse(self, Vector2(150, 124), Vector2(5, 2), palette.clay)
	Style.pixel_ellipse(self, Vector2(150, 124), Vector2(3, 1), palette.clay_light)
	Style.pixel_ellipse(self, Vector2(213, 125), Vector2(4, 2), palette.clay_shadow)
	Style.pixel_ellipse(self, Vector2(213, 124), Vector2(4, 2), palette.clay_light)
	Style.pixel_ellipse(self, Vector2(226, 146), Vector2(4, 2), palette.clay_shadow)
	Style.pixel_ellipse(self, Vector2(226, 145), Vector2(4, 2), palette.clay_light)
	_draw_rake_clusters(palette, clay_edge.slice(6, 17), Vector2(150, 135), [0.94, 0.86], 5407)
	_draw_rake_clusters(palette, clay_edge.slice(16, 25), Vector2(150, 135), [0.88], 5417)
	# Chalk crossing clay takes its clay-side seat (§5.2).
	_chalk_seated_line(palette, plate, Vector2(95, 104), palette.clay_shadow)
	_chalk_seated_line(palette, plate, Vector2(132, 100), palette.clay_shadow)
	_chalk_seated_line(palette, Vector2(218, 137), Vector2(246, 148), palette.clay_shadow)
	_draw_chalk_box(palette, Rect2(102, 89, 6, 7))
	_draw_chalk_box(palette, Rect2(119, 89, 6, 7))
	_draw_mound(palette, Vector2(201, 133), Vector2(12, 5), Rect2(197, 132, 8, 1))
	_draw_home_plate(palette, plate)
	_draw_field_bag(palette, Vector2(213, 124))
	_draw_field_bag(palette, Vector2(226, 145))
	_draw_field_bag(palette, Vector2(150, 124))
	_draw_leaf_drift(palette)


# --- Band 5: playfield helpers (pass 04) --------------------------------------


func _draw_turf_mow_arcs(palette: Dictionary, focus: Vector2, squash: float, region: Rect2i, arcs: Array) -> void:
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
				_mow_row(y, focus.x - half_outer, focus.x + half_outer, left, right, palette.turf_light)
			else:
				_mow_row(y, focus.x - half_outer, focus.x - half_inner, left, right, palette.turf_light)
				_mow_row(y, focus.x + half_inner, focus.x + half_outer, left, right, palette.turf_light)


func _mow_row(y: int, from_x: float, to_x: float, left: int, right: int, color: Color) -> void:
	var seg_left := clampi(roundi(from_x), left, right)
	var seg_right := clampi(roundi(to_x), left, right)
	if seg_right > seg_left:
		Style.pixel_rect(self, Rect2(seg_left, y, seg_right - seg_left, 1), color)


func _draw_warning_track(palette: Dictionary, left: int, right: int, top: int, depth: int, seed: int) -> void:
	# Clay strip under the wall pads (§6.4) with 1-cell drip overhangs every
	# 6-14 cells so the grass seam never runs straight (§5.1).
	Style.pixel_rect(self, Rect2(left, top, right - left, depth), palette.clay)
	Style.pixel_rect(self, Rect2(left, top, right - left, 1), palette.clay_shadow)
	var x := left + 4
	while x < right - 2:
		Style.pixel_rect(self, Rect2(x, top + depth, 2, 1), palette.clay)
		x += 6 + int(Style.hash01(seed + x) * 9.0)


func _draw_stand_shadow_stairs(palette: Dictionary, top: int, reach: int, run: int, rise: int) -> void:
	# Left-anchored stepped stand shadow (§6.2/§7.4); run:rise = 2:1 at the
	# golden defaults.
	var width := reach
	var y := top
	while width > 0 and y < 180:
		Style.pixel_rect(self, Rect2(0, y, width, rise), palette.turf_shadow)
		width -= run
		y += rise


func _draw_lamp_pool(palette: Dictionary, center: Vector2, radius: Vector2) -> void:
	# Authored elliptical night lamp pool with a stepped stair edge (§7.4):
	# turf rim, turf_light body, and a one-rung lift at the core.
	Style.pixel_ellipse(self, center, radius + Vector2(4, 2), palette.turf)
	Style.pixel_ellipse(self, center, radius, palette.turf_light)
	Style.pixel_ellipse(
		self,
		center,
		Vector2(maxf(2.0, radius.x - 6.0), maxf(1.0, radius.y - 3.0)),
		Style.shift_value(palette.turf_light, 1),
	)


func _chalk_seated_line(palette: Dictionary, from: Vector2, to: Vector2, seat: Color) -> void:
	# Chalk with its 1-cell shadow-side seat so it never halates into the
	# field (§5.2); pass turf_shadow over grass and clay_shadow over clay.
	Style.pixel_line(self, from + Vector2(0, 1), to + Vector2(0, 1), seat)
	Style.pixel_line(self, from, to, palette.chalk)


func _fill_organic(points: Array[Vector2], pivot: Vector2, color: Color) -> void:
	# Fan-fill an irregular authored outline from an interior pivot so
	# concave drip edges rasterize correctly.
	for index in range(points.size()):
		var triangle: Array[Vector2] = [pivot, points[index], points[(index + 1) % points.size()]]
		_colored_polygon(triangle, color)


func _draw_rake_clusters(palette: Dictionary, arc: Array, pivot: Vector2, scales: Array, seed: int) -> void:
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
				Style.pixel_rect(self, Rect2(at.x, at.y, 2, 1), palette.clay_light)


func _draw_chalk_box(palette: Dictionary, rect: Rect2) -> void:
	# 1-cell chalk batter's box frame with its clay seat under the bottom rail.
	Style.pixel_rect(self, Rect2(rect.position.x, rect.end.y, rect.size.x, 1), palette.clay_shadow)
	Style.pixel_rect(self, Rect2(rect.position.x, rect.position.y, rect.size.x, 1), palette.chalk)
	Style.pixel_rect(self, Rect2(rect.position.x, rect.end.y - 1, rect.size.x, 1), palette.chalk)
	Style.pixel_rect(self, Rect2(rect.position.x, rect.position.y, 1, rect.size.y), palette.chalk)
	Style.pixel_rect(self, Rect2(rect.end.x - 1, rect.position.y, 1, rect.size.y), palette.chalk)


func _draw_mound(palette: Dictionary, center: Vector2, radius: Vector2, rubber: Rect2) -> void:
	# Clay_lit crown over a shade crescent that bottoms out in ink, with the
	# chalk rubber seated on the crown (§7.4).
	Style.pixel_ellipse(self, center + Vector2(0, 1), radius, palette.ink1)
	Style.pixel_ellipse(self, center, radius, palette.clay_shadow)
	Style.pixel_ellipse(self, center - Vector2(0, 1), radius - Vector2(1, 1), palette.clay)
	Style.pixel_ellipse(self, center - Vector2(0, 2), Vector2(radius.x - 4, radius.y - 2), palette.clay_light)
	Style.pixel_rect(self, Rect2(rubber.position + Vector2(0, 1), rubber.size), palette.clay_shadow)
	Style.pixel_rect(self, rubber, palette.chalk)


func _draw_home_plate(palette: Dictionary, center: Vector2) -> void:
	# Proper 5-sided plate, point toward the catcher, seated on its shadow
	# side (§7.4, §5.2).
	Style.pixel_rect(self, Rect2(center.x - 1, center.y + 1, 3, 1), palette.clay_shadow)
	Style.pixel_rect(self, Rect2(center.x - 1, center.y - 1, 3, 2), palette.chalk)
	Style.pixel_rect(self, Rect2(center.x, center.y - 2, 1, 1), palette.chalk)


func _draw_field_bag(palette: Dictionary, center: Vector2) -> void:
	# 2x2 chalk bag with a 1-cell ink ground-contact shade (§7.4).
	Style.pixel_rect(self, Rect2(center.x - 1, center.y + 1, 1, 1), palette.ink0)
	Style.pixel_rect(self, Rect2(center.x - 1, center.y - 1, 2, 2), palette.chalk)


func _draw_batting(palette: Dictionary) -> void:
	var bands: Dictionary = BAND_DATUMS.batting
	var horizon: int = bands.horizon
	_draw_sky_band(palette, 0, 320, 0, horizon)
	_draw_skyline_row(palette, horizon, palette.skyline_far, false, [
		["hill", -12, 54], ["sheds", 30, 2], ["crane", 62, 0], ["hill", 252, 58], ["masts", 288, 3],
	])
	_draw_sea_band(palette, 0, 320, horizon, bands.sea_bottom, 140)
	# This camera faces open water: breakwater, moored trawler, and the quiet
	# lighthouse read above the center-field wall (§6.3).
	_draw_trawler(palette, 138, 47)
	_draw_breakwater(palette, 96, 128, 48)
	_stamp_lighthouse(palette, 224, 50)
	_draw_skyline_row(palette, horizon + 3, palette.skyline_near, true, [
		["traps", 8, 0], ["masts", 16, 3], ["sheds", 278, 2],
	])
	_draw_mist_veil(palette, 0, 320, horizon - 14, bands.sea_bottom)
	_draw_fireworks(palette, 0, 320, horizon)

	Style.pixel_rect(self, Rect2(0, bands.wall_top, 320, 6), palette.shadow_cool)
	Style.pixel_rect(self, Rect2(0, bands.wall_top, 320, 1), palette.structure_light)
	Style.pixel_rect(self, Rect2(0, bands.field_top - 1, 320, 1), palette.ink1)

	# Field surface (bible §6.3, §7.4): full-width turf so foul ground runs
	# beneath the corner stands, with mow-band arcs concentric on the
	# PixiballBroadcastCamera._project_batting plate anchor. The stands and
	# their skirts repaint on top so the foul corners stay theirs.
	var field_top: int = bands.field_top
	var plate := Vector2(160, 154)
	Style.pixel_rect(self, Rect2(0, field_top, 320, 180 - field_top), palette.turf)
	_draw_turf_mow_arcs(palette, plate, 0.42, Rect2i(0, field_top, 320, 180 - field_top), [
		Vector2(30, 44), Vector2(62, 76), Vector2(96, 110), Vector2(130, 146),
		Vector2(166, 182), Vector2(202, 220), Vector2(238, 258),
	])
	if mood == "night":
		# Night: the field lifts only inside authored elliptical lamp pools
		# with stepped edges; base night values elsewhere (§7.4).
		_draw_lamp_pool(palette, Vector2(160, 122), Vector2(50, 18))
		_draw_lamp_pool(palette, Vector2(84, 106), Vector2(24, 8))
		_draw_lamp_pool(palette, Vector2(240, 106), Vector2(24, 8))
	else:
		# Stand shadow off the left corner deck; golden stretches it into the
		# long 2:1 stepped evening shadow (§7.4).
		_draw_stand_shadow_stairs(palette, field_top + 2, 148 if mood == "golden" else 72, 8, 4)

	# Two-deck corner stands frame the pitch corridor and their crowds thin
	# toward center so the corridor stays visually quiet (§6.3).
	_draw_grandstand(palette, Rect2i(0, 42, 72, 46), 310, 1)
	_draw_grandstand(palette, Rect2i(248, 42, 72, 46), 360, -1)
	# Under-deck walkway skirts slope the corner stands into foul ground.
	_colored_polygon([Vector2(0, 88), Vector2(72, 88), Vector2(0, 103)], palette.ink1)
	_colored_polygon([Vector2(320, 88), Vector2(248, 88), Vector2(320, 103)], palette.ink1)
	_draw_gulls(palette, [Vector2(84, 36), Vector2(92, 39), Vector2(206, 34), Vector2(214, 37)])

	# Foul lines run through the first/third-base anchors ((191/129, 93)) to
	# the wall base with a turf seat on the shadow side (§5.2); the on-clay
	# stretches re-chalk after the dirt goes down.
	_chalk_seated_line(palette, plate, Vector2(208, 60), palette.turf_shadow)
	_chalk_seated_line(palette, plate, Vector2(112, 60), palette.turf_shadow)
	# Plate dirt circle with a shade crescent, then the organic infield cutout
	# sweeping around the base anchors and the clamped mound lane (160, 76).
	Style.pixel_ellipse(self, Vector2(160, 156), Vector2(15, 7), palette.clay_shadow)
	Style.pixel_ellipse(self, Vector2(160, 155), Vector2(15, 7), palette.clay)
	var clay_edge: Array[Vector2] = [
		Vector2(166, 147), Vector2(172, 139), Vector2(177, 130), Vector2(182, 121),
		Vector2(187, 112), Vector2(192, 104), Vector2(197, 97), Vector2(199, 90),
		Vector2(196, 83), Vector2(188, 77), Vector2(176, 72), Vector2(160, 69),
		Vector2(144, 72), Vector2(132, 77), Vector2(124, 83), Vector2(121, 90),
		Vector2(123, 97), Vector2(128, 104), Vector2(133, 112), Vector2(138, 121),
		Vector2(143, 130), Vector2(148, 139), Vector2(154, 147),
	]
	_fill_organic(clay_edge, Vector2(160, 104), palette.clay)
	var infield_grass: Array[Vector2] = [
		Vector2(160, 138), Vector2(171, 116), Vector2(184, 95), Vector2(172, 86),
		Vector2(160, 80), Vector2(148, 87), Vector2(136, 95), Vector2(149, 118),
	]
	_fill_organic(infield_grass, Vector2(160, 106), palette.turf_shadow)
	# 1-cell lit rim on the mound-side edges plus mow ridges so the infield
	# grass never reads as one flat region (§5.2, §5.4).
	Style.pixel_line(self, Vector2(136, 95), Vector2(148, 87), palette.turf)
	Style.pixel_line(self, Vector2(148, 87), Vector2(160, 80), palette.turf)
	Style.pixel_line(self, Vector2(160, 80), Vector2(172, 86), palette.turf)
	Style.pixel_line(self, Vector2(172, 86), Vector2(184, 95), palette.turf)
	for ridge in [Vector2(150, 112), Vector2(160, 105), Vector2(170, 112), Vector2(153, 124), Vector2(167, 124)]:
		Style.pixel_rect(self, Rect2(ridge.x, ridge.y, 4, 1), palette.turf_dark)
	_draw_rake_clusters(palette, clay_edge.slice(6, 17), Vector2(160, 100), [0.88, 0.78], 6131)
	# Chalk crossing clay takes its clay-side seat (§5.2).
	_chalk_seated_line(palette, Vector2(166, 143), Vector2(189, 98), palette.clay_shadow)
	_chalk_seated_line(palette, Vector2(154, 143), Vector2(131, 98), palette.clay_shadow)
	_draw_chalk_box(palette, Rect2(148, 148, 8, 8))
	_draw_chalk_box(palette, Rect2(164, 148, 8, 8))
	_draw_mound(palette, Vector2(160, 76), Vector2(10, 4), Rect2(157, 74, 7, 1))
	_draw_home_plate(palette, plate)
	_draw_field_bag(palette, Vector2(191, 93))
	_draw_field_bag(palette, Vector2(129, 93))
	_draw_field_bag(palette, Vector2(160, 71))
	_draw_led_board(Vector2(258, 25), palette)
	_draw_leaf_drift(palette)


func _draw_fielding(palette: Dictionary) -> void:
	# High harbor-balcony camera; margins extend past the design frame so the
	# quantized follow offset never exposes raw backing (§6.4).
	var bands: Dictionary = BAND_DATUMS.fielding
	var left := -32
	var right := 352
	var horizon: int = bands.horizon
	_draw_sky_band(palette, left, right, -20, horizon)
	_draw_skyline_row(palette, horizon, palette.skyline_far, false, [
		["hill", -28, 60], ["crane", 20, 0], ["sheds", 64, 3], ["hill", 120, 48],
		["masts", 170, 4], ["hill", 230, 52], ["sheds", 282, 2], ["hill", 318, 44],
	])
	_draw_sea_band(palette, left, right, horizon, bands.sea_bottom, 190)
	_draw_skyline_row(palette, horizon + 3, palette.skyline_near, true, [
		["cannery", 0, 1], ["masts", 96, 3], ["traps", 150, 0], ["sheds", 208, 3], ["cannery", 298, 0],
	])
	_stamp_lighthouse(palette, 340, horizon + 2)
	_draw_breakwater(palette, 118, 60, horizon + 6)
	_draw_mist_veil(palette, left, right, horizon - 14, bands.sea_bottom)
	_draw_fireworks(palette, left, right, horizon)

	# Single-deck harbor strip in sections; quay walls fill the gaps so the
	# ring never reads as one unbroken wall (§7.3).
	for gap_x in [56, 168, 280]:
		Style.pixel_rect(self, Rect2(gap_x, bands.sea_bottom, 16, bands.wall_top - bands.sea_bottom), palette.skyline_near)
		Style.pixel_rect(self, Rect2(gap_x, bands.sea_bottom, 16, 1), palette.structure_light)
	_draw_grandstand(palette, Rect2i(left, bands.stands_top, 56 - left, bands.wall_top - bands.stands_top), 410)
	_draw_grandstand(palette, Rect2i(72, bands.stands_top, 96, bands.wall_top - bands.stands_top), 420)
	_draw_grandstand(palette, Rect2i(184, bands.stands_top, 96, bands.wall_top - bands.stands_top), 430)
	_draw_grandstand(palette, Rect2i(296, bands.stands_top, right - 296, bands.wall_top - bands.stands_top), 440)
	_draw_bell_tower(palette, Vector2i(300, 54), 16)
	Style.pixel_rect(self, Rect2(left, bands.wall_top - 1, right - left, 1), palette.ink1)
	Style.pixel_rect(self, Rect2(left, bands.wall_top, right - left, bands.field_top - bands.wall_top), palette.shadow_cool)
	Style.pixel_rect(self, Rect2(left, bands.field_top - 1, right - left, 1), palette.ink1)
	_draw_gulls(palette, [Vector2(30, 30), Vector2(38, 33), Vector2(276, 26), Vector2(284, 29)])
	_draw_led_board(Vector2(8, 30), palette)

	# Field surface (bible §6.4, §7.4): foul-ground apron, elliptical outfield
	# with mow arcs concentric on the plate anchor, a 3-cell clay warning
	# track, and the landmark diamond on the existing
	# PixiballBroadcastCamera._project_fielding anchors (plate (160, 155),
	# bases (201/160/119), mound (160, 119)).
	var field_top: int = bands.field_top
	var plate := Vector2(160, 155)
	var field_center := Vector2(160, 118)
	Style.pixel_rect(self, Rect2(left, field_top, right - left, 200 - field_top), palette.turf_shadow)
	Style.pixel_ellipse(self, field_center, Vector2(141, 48), palette.turf)
	_draw_turf_mow_arcs(palette, plate, 0.64, Rect2i(19, 70, 283, 97), [
		Vector2(14, 24), Vector2(34, 45), Vector2(56, 68), Vector2(80, 93),
		Vector2(106, 120), Vector2(134, 150),
	])
	if mood == "night":
		# Night: authored elliptical lamp pools with stair edges; base night
		# values everywhere else (§7.4).
		_draw_lamp_pool(palette, Vector2(104, 96), Vector2(34, 12))
		_draw_lamp_pool(palette, Vector2(216, 96), Vector2(34, 12))
		_draw_lamp_pool(palette, Vector2(160, 140), Vector2(44, 14))
	else:
		# Stand shadow off the left ring; golden stretches the 2:1 stairs
		# across the outfield (§7.4).
		_draw_stand_shadow_stairs(palette, field_top + 4, 150 if mood == "golden" else 64, 8, 4)
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
		_mow_row(y, left, field_center.x - half_rim, left, right, palette.turf_shadow)
		_mow_row(y, field_center.x + half_rim, right, left, right, palette.turf_shadow)
		_mow_row(y, field_center.x - half_rim, field_center.x - half_track, left, right, palette.clay_shadow)
		_mow_row(y, field_center.x + half_track, field_center.x + half_rim, left, right, palette.clay_shadow)
		_mow_row(y, field_center.x - half_track, field_center.x - half_grass, left, right, palette.clay)
		_mow_row(y, field_center.x + half_grass, field_center.x + half_track, left, right, palette.clay)
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
				Style.pixel_rect(self, Rect2(drift_x, drift_y, dash, 1), palette.turf_dark)
		drift_x += 4 + int(Style.hash01(drift_seed + 7) * 7.0)
	# Foul lines run through the base anchors to the foul poles on the track,
	# seated on the shadow side (§5.2); on-clay stretches re-chalk after the
	# dirt, and 1-cell chalk poles mark the corners.
	_chalk_seated_line(palette, plate, Vector2(266, 82), palette.turf_shadow)
	_chalk_seated_line(palette, plate, Vector2(54, 82), palette.turf_shadow)
	Style.pixel_rect(self, Rect2(266, 78, 1, 4), palette.chalk)
	Style.pixel_rect(self, Rect2(54, 78, 1, 4), palette.chalk)
	# Plate dirt circle with a shade crescent, then the organic infield cutout.
	Style.pixel_ellipse(self, Vector2(160, 156), Vector2(9, 4), palette.clay_shadow)
	Style.pixel_ellipse(self, Vector2(160, 155), Vector2(9, 4), palette.clay)
	var clay_edge: Array[Vector2] = [
		Vector2(160, 159), Vector2(172, 153), Vector2(182, 145), Vector2(192, 137),
		Vector2(202, 132), Vector2(207, 128), Vector2(205, 121), Vector2(196, 113),
		Vector2(186, 105), Vector2(175, 99), Vector2(166, 95), Vector2(160, 93),
		Vector2(154, 95), Vector2(145, 99), Vector2(134, 105), Vector2(124, 113),
		Vector2(115, 121), Vector2(113, 128), Vector2(118, 132), Vector2(128, 137),
		Vector2(138, 145), Vector2(148, 153),
	]
	_fill_organic(clay_edge, Vector2(160, 127), palette.clay)
	var infield_grass: Array[Vector2] = [
		Vector2(160, 147), Vector2(178, 137), Vector2(193, 127), Vector2(177, 117),
		Vector2(160, 108), Vector2(143, 117), Vector2(127, 127), Vector2(142, 137),
	]
	_fill_organic(infield_grass, Vector2(160, 127), palette.turf_shadow)
	# 1-cell lit rim on the outfield-side edges plus mow ridges (§5.2, §5.4).
	Style.pixel_line(self, Vector2(127, 127), Vector2(143, 117), palette.turf)
	Style.pixel_line(self, Vector2(143, 117), Vector2(160, 108), palette.turf)
	Style.pixel_line(self, Vector2(160, 108), Vector2(177, 117), palette.turf)
	Style.pixel_line(self, Vector2(177, 117), Vector2(193, 127), palette.turf)
	for ridge in [Vector2(146, 127), Vector2(156, 132), Vector2(168, 127), Vector2(150, 120), Vector2(168, 121)]:
		Style.pixel_rect(self, Rect2(ridge.x, ridge.y, 4, 1), palette.turf_dark)
	_draw_rake_clusters(palette, clay_edge.slice(5, 18), Vector2(160, 127), [0.9, 0.8], 7213)
	# Chalk crossing clay takes its clay-side seat (§5.2).
	_chalk_seated_line(palette, Vector2(166, 151), Vector2(207, 123), palette.clay_shadow)
	_chalk_seated_line(palette, Vector2(154, 151), Vector2(113, 123), palette.clay_shadow)
	_draw_chalk_box(palette, Rect2(151, 151, 6, 6))
	_draw_chalk_box(palette, Rect2(163, 151, 6, 6))
	_draw_mound(palette, Vector2(160, 119), Vector2(6, 3), Rect2(158, 118, 4, 1))
	_draw_home_plate(palette, plate)
	_draw_field_bag(palette, Vector2(201, 127))
	_draw_field_bag(palette, Vector2(160, 101))
	_draw_field_bag(palette, Vector2(119, 127))
	_draw_leaf_drift(palette)


func _draw_dugout(palette: Dictionary) -> void:
	var bands: Dictionary = BAND_DATUMS.dugout
	# Interior stays cool and dark; the framed field is the warm pool the
	# bench longs for (§6.5).
	Style.pixel_rect(self, Rect2(0, 0, 320, 28), palette.ink1)
	for x in range(8, 320, 40):
		Style.pixel_rect(self, Rect2(x, 8, 2, 20), palette.structure)
	# Roof beam crosses y=28..36 as an ink + stand-shell frame.
	Style.pixel_rect(self, Rect2(0, 28, 320, 8), palette.structure)
	Style.pixel_rect(self, Rect2(0, 28, 320, 1), palette.structure_light)
	Style.pixel_rect(self, Rect2(0, 34, 320, 2), palette.ink0)
	# Plank back wall and floor.
	Style.pixel_rect(self, Rect2(0, 36, 320, 144), palette.ink1)
	for y in range(40, 98, 5):
		for x in range((int(y / 5.0) % 2) * 11, 320, 22):
			Style.pixel_rect(self, Rect2(x, y, 12, 1), palette.structure)
	Style.pixel_rect(self, Rect2(16, 102, 288, 3), palette.wood_dark)
	Style.pixel_rect(self, Rect2(16, 116, 288, 6), palette.wood)
	for x in range(24, 300, 36):
		Style.pixel_rect(self, Rect2(x, 122, 3, 26), palette.wood_dark)
	Style.pixel_rect(self, Rect2(0, 148, 320, 2), palette.ink0)
	for x in range(10, 320, 26):
		Style.pixel_rect(self, Rect2(x, 158, 12, 1), palette.structure)

	# The dugout opening frames the harbor postcard (§6.5): five mini-bands.
	Style.pixel_rect(self, Rect2(176, 36, 128, 60), palette.ink0)
	_draw_sky_band(palette, 180, 300, 40, bands.horizon, true)
	_draw_skyline_row(palette, bands.horizon, palette.skyline_far, false, [
		["hill", 178, 44], ["masts", 216, 3], ["sheds", 252, 2],
	])
	_draw_sea_band(palette, 180, 300, bands.horizon, bands.sea_bottom, 240)
	_stamp_lighthouse(palette, 290, bands.horizon + 2)
	_draw_mist_veil(palette, 180, 300, bands.horizon - 8, bands.sea_bottom)
	_draw_grandstand(palette, Rect2i(180, bands.stands_top, 120, bands.wall_top - bands.stands_top), 520)
	Style.pixel_rect(self, Rect2(180, bands.wall_top - 1, 120, 1), palette.ink1)
	Style.pixel_rect(self, Rect2(180, bands.wall_top, 120, bands.field_top - bands.wall_top), palette.shadow_cool)
	# Playfield through the opening (bible §6.5, §7.4): the same organic turf,
	# clay cutout, seated chalk, and landmark treatment as the gameplay views,
	# compressed into the framed postcard. The plate holds the legacy
	# convergence point; bags stay on (214/236/258, 83/77/83).
	var field_top: int = bands.field_top
	var plate := Vector2(236, 89)
	Style.pixel_rect(self, Rect2(180, field_top, 120, 92 - field_top), palette.turf)
	_draw_turf_mow_arcs(palette, plate, 0.45, Rect2i(180, field_top, 120, 92 - field_top), [
		Vector2(8, 14), Vector2(21, 29), Vector2(37, 46), Vector2(55, 66), Vector2(76, 88),
	])
	_draw_warning_track(palette, 180, 300, field_top, 2, 8117)
	if mood == "night":
		# Night: the framed field lifts inside one authored lamp pool (§7.4).
		_draw_lamp_pool(palette, Vector2(240, 84), Vector2(26, 6))
	# Foul lines through the bag anchors with their shadow-side turf seat
	# (§5.2); the on-clay stretches re-chalk after the dirt.
	_chalk_seated_line(palette, plate, Vector2(185, field_top), palette.turf_shadow)
	_chalk_seated_line(palette, plate, Vector2(287, field_top), palette.turf_shadow)
	# Irregular infield cutout around the bags, then the plate-area shade
	# crescent so the clay never reads as one flat wedge (§5.4).
	var clay_edge: Array[Vector2] = [
		Vector2(236, 91), Vector2(245, 89), Vector2(254, 87), Vector2(261, 85),
		Vector2(264, 83), Vector2(261, 81), Vector2(254, 79), Vector2(245, 77),
		Vector2(236, 76), Vector2(227, 77), Vector2(218, 79), Vector2(211, 81),
		Vector2(208, 83), Vector2(211, 85), Vector2(218, 87), Vector2(227, 89),
	]
	_fill_organic(clay_edge, Vector2(236, 83), palette.clay)
	Style.pixel_ellipse(self, Vector2(236, 90), Vector2(4, 1), palette.clay_shadow)
	var infield_grass: Array[Vector2] = [
		Vector2(236, 87), Vector2(244, 85), Vector2(251, 83), Vector2(244, 81),
		Vector2(236, 79), Vector2(228, 81), Vector2(221, 83), Vector2(228, 85),
	]
	_fill_organic(infield_grass, Vector2(236, 83), palette.turf_shadow)
	# 1-cell lit rim on the outfield-side edges plus mow ridges (§5.2, §5.4).
	Style.pixel_line(self, Vector2(221, 83), Vector2(228, 81), palette.turf)
	Style.pixel_line(self, Vector2(228, 81), Vector2(236, 79), palette.turf)
	Style.pixel_line(self, Vector2(236, 79), Vector2(244, 81), palette.turf)
	Style.pixel_line(self, Vector2(244, 81), Vector2(251, 83), palette.turf)
	for ridge in [Vector2(226, 83), Vector2(243, 84), Vector2(232, 86)]:
		Style.pixel_rect(self, Rect2(ridge.x, ridge.y, 3, 1), palette.turf_dark)
	_draw_rake_clusters(palette, clay_edge.slice(2, 15), Vector2(236, 83), [0.85], 8317)
	# Chalk crossing clay takes its clay-side seat (§5.2).
	_chalk_seated_line(palette, Vector2(240, 88), Vector2(261, 82), palette.clay_shadow)
	_chalk_seated_line(palette, Vector2(232, 88), Vector2(211, 82), palette.clay_shadow)
	_draw_chalk_box(palette, Rect2(230, 87, 4, 4))
	_draw_chalk_box(palette, Rect2(239, 87, 4, 4))
	_draw_mound(palette, Vector2(236, 82), Vector2(3, 1), Rect2(235, 81, 3, 1))
	_draw_home_plate(palette, plate)
	_draw_field_bag(palette, Vector2(258, 83))
	_draw_field_bag(palette, Vector2(236, 77))
	_draw_field_bag(palette, Vector2(214, 83))
	# Light spill from the opening onto the dugout floor.
	Style.pixel_rect(self, Rect2(186, 150, 108, 5), palette.structure)

	# Wall-mounted cage lamp: the quiet secondary beacon (§6.5).
	_draw_cage_lamp(palette, Vector2(56, 44))
	_draw_bunting(Vector2(100, 38), palette, 0)
	_draw_bunting(Vector2(148, 38), palette, 1)


func _draw_cage_lamp(palette: Dictionary, at: Vector2) -> void:
	Style.pixel_rect(self, Rect2(at.x - 3, at.y - 6, 6, 2), palette.structure)
	Style.pixel_rect(self, Rect2(at.x - 2, at.y - 4, 4, 5), palette.lamp_glow)
	Style.pixel_rect(self, Rect2(at.x - 1, at.y - 3, 2, 3), palette.lamp_core)
	Style.pixel_rect(self, Rect2(at.x - 2, at.y - 4, 1, 5), palette.structure)
	Style.pixel_rect(self, Rect2(at.x + 1, at.y - 4, 1, 5), palette.structure)
	Style.pixel_rect(self, Rect2(at.x - 3, at.y + 2, 6, 1), palette.lamp_glow)


# --- Grandstand, crowd, bell tower, LED board (§7.3, §7.5) --------------------


func _crowd_palette(palette: Dictionary) -> Dictionary:
	# Bible crowd roles mapped onto the shared MOOD_PALETTES API (§7.5). The
	# crowd mass must read against the seat boards by value, not hue: bodies
	# sit two-plus rungs below seat_a/seat_b as dark clustered silhouettes
	# (crowd_shade with ink1 variation), heads carry a skyline_far catch-light,
	# and the mood-rationed warm faces ride the lit-clay ramp. Saturation stays
	# under the §4.2 crowd cap in every mood.
	return {
		"body": palette.crowd_shade,
		"body_alt": palette.ink1,
		"head": palette.skyline_far,
		"warm": palette.clay_light,
		"shadow": palette.crowd_shade,
		"flag_a": palette.team_teal,
		"flag_b": palette.stitch,
	}


func _draw_grandstand(palette: Dictionary, rect: Rect2i, seed: int, thin := 0) -> void:
	# Two-deck timber-and-brick ring section (§7.3): stand_shell structure,
	# seat rows on a 2-cell rhythm with empty-seat division ticks, a brick base
	# course, ink shadow under each deck lip, irregular aisle cuts, post rhythm
	# every 10 cells, and drape-variant bunting swags on a drifting ~24-cell
	# facade rhythm in all moods. Shallow strips (fielding, dugout window)
	# collapse to a single deck.
	var left := rect.position.x
	var right := rect.position.x + rect.size.x
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y
	var brick_rows := 3 if rect.size.y >= 14 else 2
	var brick_top := bottom - brick_rows
	var body_height := brick_top - top
	var decks := 2 if body_height >= 12 else 1
	Style.pixel_rect(self, Rect2(rect), palette.structure)

	# Irregular aisle cuts every 9-13 columns, deterministic per seed.
	var aisles: Array[int] = []
	var aisle_x := left + 4 + int(Style.hash01(seed + 11) * 6.0)
	while aisle_x < right - 4:
		aisles.append(aisle_x)
		aisle_x += 9 + int(Style.hash01(seed + aisle_x * 13) * 5.0)

	var deck_height := int(body_height / float(decks))
	for deck in range(decks):
		var deck_top := top + deck * deck_height
		var deck_bottom := brick_top if deck == decks - 1 else deck_top + deck_height
		Style.pixel_rect(self, Rect2(left, deck_top, rect.size.x, 1), palette.structure_light)
		var crowd_rect := Rect2i(left, deck_top + 1, rect.size.x, deck_bottom - deck_top - 3)
		# Seat boards on the 2-cell rhythm; empty seats stay visible through
		# the 55-80% clump occupancy.
		Style.pixel_rect(self, Rect2(crowd_rect), palette.seat_b)
		var seat_y := crowd_rect.position.y + 1
		while seat_y < crowd_rect.position.y + crowd_rect.size.y:
			Style.pixel_rect(self, Rect2(left, seat_y, rect.size.x, 1), palette.seat_a)
			# Empty-seat cadence: seat-division ticks on a drifting 4-6 cell
			# rhythm so vacant stretches read as seating, never blank rail.
			var tick_x := left + 1 + posmod(seed + seat_y * 13, 4)
			while tick_x < right - 1:
				Style.pixel_rect(self, Rect2(tick_x, seat_y, 1, 1), palette.seat_b)
				tick_x += 4 + int(Style.hash01(seed + tick_x * 11 + seat_y) * 3.0)
			seat_y += 2
		for aisle in aisles:
			Style.pixel_rect(self, Rect2(aisle, crowd_rect.position.y, 2, crowd_rect.size.y), palette.structure)
			var step_y := crowd_rect.position.y + 2
			while step_y < crowd_rect.position.y + crowd_rect.size.y:
				Style.pixel_rect(self, Rect2(aisle, step_y, 2, 1), palette.ink1)
				step_y += 3
		# The top deck of a two-deck stand is silhouette-only clumps (§7.5);
		# the crest row of the topmost deck may break the rail line so the
		# aggregate crowd silhouette undulates against the harbor (§5.1).
		_draw_crowd_clumps(crowd_rect, seed + 900 + deck * 77, aisles, thin, decks == 2 and deck == 0, deck == 0)
		# Deck lip with its ink shadow underneath.
		Style.pixel_rect(self, Rect2(left, deck_bottom - 2, rect.size.x, 1), palette.structure_light)
		Style.pixel_rect(self, Rect2(left, deck_bottom - 1, rect.size.x, 1), palette.ink0)

	# Brick base course with staggered header dashes (§7.3).
	Style.pixel_rect(self, Rect2(left, brick_top, rect.size.x, brick_rows), palette.brick_warm)
	var dash_x := left + posmod(seed, 3)
	while dash_x < right:
		Style.pixel_rect(self, Rect2(dash_x, brick_top + brick_rows - 2, mini(2, right - dash_x), 1), palette.brick_light)
		dash_x += 4 + int(Style.hash01(seed + dash_x * 7) * 3.0)

	# Facade post rhythm every 10 cells, full height, lit at the rail.
	var post_x := left + 5
	while post_x < right:
		Style.pixel_rect(self, Rect2(post_x, top, 1, rect.size.y), palette.ink1)
		Style.pixel_rect(self, Rect2(post_x, top, 1, 1), palette.structure_light)
		post_x += 10

	# Bunting swags hung off the lower lip on a drifting ~24-cell rhythm with
	# alternating drape variants, so the facade never reads as one repeated
	# triangle row (§7.3).
	var bunt_index := 0
	var bunt_x := left + 10 + posmod(seed, 7)
	while bunt_x < right - 6:
		_draw_bunting(Vector2(bunt_x, brick_top - 1), palette, seed + bunt_index)
		bunt_x += 24 + int(Style.hash01(seed + bunt_index * 31) * 9.0)
		bunt_index += 1

	# Reaction overlays ride each stand section (§9.5, §9.7): cap-toss arcs on
	# the biggest plays and celebration streamers off the upper deck lip.
	_draw_cap_toss(palette, rect, seed)
	_draw_streamers(palette, rect, seed)


func _draw_cap_toss(palette: Dictionary, rect: Rect2i, seed: int) -> void:
	# §9.5: at strength >= 0.7 caps arc over the crowd. Two 2x1 caps per wide
	# section, and no view draws more than three wide sections, so the global
	# alive count stays at or under 8. Flights are whole-cell parabolas keyed
	# to the reaction clock and re-seeded per play through the serial.
	if _reaction_timer <= 0.0 or _reaction_strength < CAP_TOSS_STRENGTH or rect.size.x < 72:
		return
	var ticks := _reaction_ticks()
	for cap in range(2):
		var salt := seed * 13 + _reaction_serial * 101 + cap * 47
		var phase := posmod(ticks - cap * 7, 24)
		if phase >= 16:
			continue
		var start_x := rect.position.x + 8 + int(Style.hash01(salt) * float(rect.size.x - 20))
		var direction := -1 if Style.hash01(salt + 3) < 0.5 else 1
		var cx := start_x + direction * int(phase / 3.0)
		var cy := rect.position.y - 1 - int(float(phase * (16 - phase)) / 8.0)
		var cap_color: Color = palette.team_teal if cap == 0 else palette.stitch
		Style.pixel_rect(self, Rect2(cx, cy, 2, 1), cap_color)


func _draw_streamers(palette: Dictionary, rect: Rect2i, seed: int) -> void:
	# §9.7: team-trim 6-cell ribbons drifting from the upper deck during the
	# celebration — two per wide section, at most three wide sections per
	# view, so the alive count stays under the 8-ribbon cap. Ribbons fall one
	# cell per two ticks and sway one cell on a 3-tick cadence.
	if not _celebrating() or rect.size.x < 72:
		return
	var ticks := _reaction_ticks()
	for streamer in range(2):
		var salt := seed * 17 + _reaction_serial * 59 + streamer * 71
		var x := rect.position.x + 12 + int(Style.hash01(salt) * float(rect.size.x - 24))
		var top := rect.position.y + 2 + int(ticks / 2.0)
		var ribbon: Color = palette.stitch if posmod(seed + streamer, 2) == 0 else palette.team_teal
		for link in range(6):
			var cy := top + link
			if cy >= rect.position.y + rect.size.y - 2:
				break
			var cx := x + posmod(int(ticks / 3.0) + int(link / 2.0), 2)
			Style.pixel_rect(self, Rect2(cx, cy, 1, 1), ribbon)


func _draw_crowd_clumps(region: Rect2i, seed: int, aisles: Array, thin: int, silhouette: bool, crest := false) -> void:
	# Clump-stamped crowd (§7.5): row-runs of 2-5 clumps with irregular gaps,
	# anchored to the seat rows, deterministic per seed. Warm faces are
	# rationed by the mood table; silhouette rows drop all accents. On the
	# crest row of the topmost deck, clumps jitter 0-2 cells upward so heads
	# and flags overhang the rail and the aggregate silhouette undulates
	# instead of running level (§5.1).
	if region.size.y < 3 or region.size.x < 4:
		return
	var palette := Style.palette(mood)
	var colors := _crowd_palette(palette)
	var warm_ratio := int(CROWD_WARM_RATIO.get(mood, 5))
	var warm_salt := posmod(seed, warm_ratio)
	var left := region.position.x
	var right := region.position.x + region.size.x
	var fronts := _wave_front_count()
	var row_count := int(region.size.y / 3.0)
	var start_y := region.position.y + region.size.y - row_count * 3
	var clump_serial := 0
	for row in range(row_count):
		var row_y := start_y + row * 3
		var x := left + posmod(seed + row_y * 31, 3)
		while x + 4 <= right:
			var run := 2 + int(Style.hash01(seed + x * 17 + row_y * 101) * 4.0)
			for index in range(run):
				if x + 4 > right:
					break
				if not _blocked_by_aisle(x, aisles) and not _thinned(x, left, right, thin, seed + x * 29 + row_y * 7):
					var stamp_index := posmod(int(Style.hash01(seed + x * 43 + row_y * 13) * 8.0), CROWD_CLUMP_STAMPS.size())
					var warm := not silhouette and posmod(clump_serial + warm_salt, warm_ratio) == 0
					var lift := 0
					if crest and row == 0:
						var roll := Style.hash01(seed + x * 59 + 7)
						lift = 2 if roll < 0.18 else (1 if roll < 0.55 else 0)
					var raised := _wave_raised(x, left, region.size.x, fronts)
					_draw_crowd_clump(Vector2i(x, row_y - lift), stamp_index, colors, warm, silhouette, raised, seed + x * 3 + row_y)
					clump_serial += 1
				x += 4
			x += 3 + int(Style.hash01(seed + x * 23 + row_y * 47) * 5.0)
	# Night phone lights (§9.5): sparse lantern-gold cells held up over the lit
	# decks while a reaction runs. Three per deck region; silhouette decks stay
	# dark, which keeps every view at or under the 12-cell cap.
	if mood == "night" and _reaction_timer > 0.0 and not silhouette:
		for phone in range(3):
			var salt := seed + 5077 + phone * 97
			var px := left + 1 + int(Style.hash01(salt) * float(maxi(1, region.size.x - 3)))
			var py := region.position.y + int(Style.hash01(salt + 1) * float(maxi(1, region.size.y - 1)))
			Style.pixel_rect(self, Rect2(px, py, 1, 1), palette.lamp_core)


func _draw_crowd_clump(at: Vector2i, stamp_index: int, colors: Dictionary, warm: bool, silhouette: bool, raised: bool, seed: int) -> void:
	var stamp: Dictionary = CROWD_CLUMP_STAMPS[stamp_index]
	# Bodies alternate between the two dark mass tones so long runs read as a
	# textured cluster instead of one flat stripe (§7.5).
	var body_color: Color = colors.shadow if silhouette else (colors.body_alt if Style.hash01(seed + 2) < 0.35 else colors.body)
	for cell in stamp.body:
		Style.pixel_rect(self, Rect2(at.x + cell[0], at.y + cell[1], cell[2], cell[3]), body_color)
	# The traveling wave swaps in the arms-up variant (§9.5): heads lift one
	# cell and the raised arm cells draw in the body tone — 1-cell amplitude.
	if raised:
		for arm in stamp.arms:
			Style.pixel_rect(self, Rect2(at.x + arm[0], at.y + arm[1], 1, 1), body_color)
	var head_lift := 1 if raised else 0
	var head_color: Color = colors.shadow if silhouette else (colors.warm if warm else colors.head)
	for head in stamp.heads:
		Style.pixel_rect(self, Rect2(at.x + head[0], at.y + head[1] - head_lift, 1, 1), head_color)
	# Muted team-trim flag tick, capped around one per 40 spectators (§7.5).
	# Big plays surface a few more wavers and extend each flag by 2 cells.
	var big_play := _reaction_timer > 0.0 and _reaction_strength >= BIG_PLAY_STRENGTH
	var flag_chance := 0.10 if big_play else 0.05
	if stamp.has("flag") and not silhouette and Style.hash01(seed + 5) < flag_chance:
		var flag: Array = stamp.flag
		var flag_color: Color = colors.flag_a if Style.hash01(seed + 9) < 0.5 else colors.flag_b
		Style.pixel_rect(self, Rect2(at.x + flag[0], at.y + flag[1], 1, 1), flag_color)
		if big_play:
			Style.pixel_rect(self, Rect2(at.x + flag[0] - 1, at.y + flag[1] - 1, 2, 1), flag_color)


func _blocked_by_aisle(x: int, aisles: Array) -> bool:
	for aisle in aisles:
		var aisle_x := int(aisle)
		if x + 4 > aisle_x and x < aisle_x + 2:
			return true
	return false


func _thinned(x: int, left: int, right: int, thin: int, seed: int) -> bool:
	# Occupancy falloff toward one edge (§6.3: batting crowds thin toward the
	# pitch corridor). thin=+1 empties toward the right edge, -1 the left.
	if thin == 0:
		return false
	var t := float(x - left) / maxf(1.0, float(right - left))
	if thin < 0:
		t = 1.0 - t
	return Style.hash01(seed) < t * 0.85


func _draw_bell_tower(palette: Dictionary, base: Vector2i, height: int) -> void:
	# Harbor bell tower (§7.3, §9.6): plank shaft rising out of the stand
	# bowl, a dark belfry opening holding the bell, and a stepped roof cap.
	# `base` is the tower foot on the facade; pass 08 rocks the bell and
	# radiates its stepped arc rings from the belfry.
	var top := base.y - height
	Style.pixel_rect(self, Rect2(base.x - 6, top + 12, 12, height - 12), palette.structure)
	Style.pixel_rect(self, Rect2(base.x - 6, top + 12, 1, height - 12), palette.structure_light)
	Style.pixel_rect(self, Rect2(base.x + 5, top + 12, 1, height - 12), palette.ink1)
	Style.pixel_rect(self, Rect2(base.x - 6, base.y - 3, 12, 3), palette.brick_warm)
	# Belfry frame and opening.
	Style.pixel_rect(self, Rect2(base.x - 6, top + 2, 12, 10), palette.structure)
	Style.pixel_rect(self, Rect2(base.x - 6, top + 2, 1, 10), palette.structure_light)
	Style.pixel_rect(self, Rect2(base.x - 5, top + 3, 10, 9), palette.ink0)
	_draw_bell(Vector2(base.x, top + 4), palette)
	# Stepped roof cap with a finial that lights after dark (§7.6).
	Style.pixel_rect(self, Rect2(base.x - 7, top + 1, 14, 1), palette.structure_light)
	Style.pixel_rect(self, Rect2(base.x - 4, top, 8, 1), palette.structure)
	Style.pixel_rect(self, Rect2(base.x - 2, top - 1, 4, 1), palette.structure_light)
	var finial: Color = palette.structure_light if mood == "day" else palette.lamp_core
	Style.pixel_rect(self, Rect2(base.x - 1, top - 3, 2, 2), finial)
	# While the bell rocks, its stepped arc rings radiate over the roofline.
	if _bell_timer > 0.0:
		_draw_bell_rings(palette, Vector2i(base.x, top + 7))


func _draw_led_board(at: Vector2, palette: Dictionary) -> void:
	# Enamel lightboard face (§10.1 material, §7.3 placement): raised bezel,
	# ink face, corner rivets, and the reaction word in lantern gold (§9.5).
	Style.pixel_rect(self, Rect2(at, Vector2(52, 17)), palette.structure)
	Style.pixel_rect(self, Rect2(at, Vector2(52, 1)), palette.structure_light)
	Style.pixel_rect(self, Rect2(at + Vector2(0, 16), Vector2(52, 1)), palette.ink1)
	Style.pixel_rect(self, Rect2(at + Vector2(2, 2), Vector2(48, 13)), palette.ink1)
	Style.pixel_rect(self, Rect2(at + Vector2(3, 3), Vector2(46, 11)), palette.ink0)
	for rivet in [Vector2(1, 1), Vector2(50, 1), Vector2(1, 15), Vector2(50, 15)]:
		Style.pixel_rect(self, Rect2(at + rivet, Vector2(1, 1)), palette.structure_light)
	var text := _led_text if _led_timer > 0.0 else "PIXIBALL"
	var width := text.length() * 4 - 1
	var text_x: float = at.x + floor((52.0 - float(width)) * 0.5)
	# The reaction word blinks on the 12 fps crowd clock (§9.5): four ticks on,
	# four off — a 1.5 Hz cycle, comfortably under the 3 Hz cap (§11.5).
	var blink_on := _led_timer <= 0.0 or posmod(int(_crowd_motion_tick / 4.0), 2) == 0
	if blink_on:
		Style.pixel_text(self, text, Vector2(text_x, at.y + 6), palette.lamp_glow, 1)
	Style.pixel_rect(self, Rect2(at.x + 8, at.y + 17, 3, 6), palette.structure)
	Style.pixel_rect(self, Rect2(at.x + 41, at.y + 17, 3, 6), palette.structure)
	Style.pixel_rect(self, Rect2(at.x + 8, at.y + 17, 1, 6), palette.ink1)
	Style.pixel_rect(self, Rect2(at.x + 41, at.y + 17, 1, 6), palette.ink1)


func _draw_bell(pivot: Vector2, palette: Dictionary) -> void:
	# Compact 9-cell-wide bell sized for the belfry opening. While the bell
	# envelope runs it rocks exactly one cell left/right every four ticks with
	# a counter-swinging clapper (§9.6) — whole cells, no rotation.
	var sway := 0
	if _bell_timer > 0.0:
		sway = 1 if posmod(int(_bell_ticks() / 4.0), 2) == 0 else -1
	var x := int(pivot.x) + sway
	var y := int(pivot.y)
	Style.pixel_line(self, Vector2(pivot.x, y - 2), Vector2(pivot.x, y), palette.structure_light, 1)
	Style.pixel_rect(self, Rect2(x - 2, y, 5, 2), palette.lamp_core)
	Style.pixel_rect(self, Rect2(x - 3, y + 2, 7, 3), palette.lamp_core)
	Style.pixel_rect(self, Rect2(x - 4, y + 5, 9, 2), palette.lamp_glow)
	Style.pixel_rect(self, Rect2(x - sway * 2, y + 7, 1, 1), palette.lamp_glow)


func _draw_bell_rings(palette: Dictionary, center: Vector2i) -> void:
	# Stepped lamp_glow arc rings radiate from the belfry, one per rock and at
	# most three alive (§9.6): each ring lives 12 ticks and rocks come every
	# 4, so the alive set can never exceed three.
	var ticks := _bell_ticks()
	var latest := int(ticks / 4.0)
	for spawn in range(maxi(0, latest - 2), latest + 1):
		var age := ticks - spawn * 4
		if age < 0 or age >= 12:
			continue
		var radius := 5 + int(age / 2.0)
		var side := int(round(float(radius) * 0.7))
		Style.pixel_rect(self, Rect2(center.x - 1, center.y - radius, 3, 1), palette.lamp_glow)
		Style.pixel_rect(self, Rect2(center.x - side - 1, center.y - side, 2, 1), palette.lamp_glow)
		Style.pixel_rect(self, Rect2(center.x + side, center.y - side, 2, 1), palette.lamp_glow)
		Style.pixel_rect(self, Rect2(center.x - radius, center.y - 1, 1, 2), palette.lamp_glow)
		Style.pixel_rect(self, Rect2(center.x + radius, center.y - 1, 1, 2), palette.lamp_glow)


func _draw_bunting(center: Vector2, palette: Dictionary, variant := 0) -> void:
	# Bunting swag (§7.3): one stepped tri-band drape sagging between two rope
	# ticks, in stitch/chalk/team_teal. The variant flips the band order so
	# neighboring swags never repeat exactly — the old triple-triangle rhythm
	# is dead.
	var bands: Array = [palette.chalk, palette.stitch, palette.team_teal]
	if posmod(variant, 2) == 1:
		bands = [palette.chalk, palette.team_teal, palette.stitch]
	Style.pixel_rect(self, Rect2(center.x - 5, center.y - 1, 2, 1), palette.ink1)
	Style.pixel_rect(self, Rect2(center.x + 4, center.y - 1, 2, 1), palette.ink1)
	Style.pixel_rect(self, Rect2(center.x - 4, center.y, 8, 1), bands[0])
	Style.pixel_rect(self, Rect2(center.x - 3, center.y + 1, 6, 1), bands[1])
	Style.pixel_rect(self, Rect2(center.x - 2, center.y + 2, 4, 1), bands[2])


func _draw_fireworks(palette: Dictionary, left: int, right: int, horizon: int) -> void:
	# Walk-off fireworks (§9.7): only full-strength celebrations earn them.
	# Two burst slots alternate on the reaction clock, each living 4 ticks, so
	# at most two are ever simultaneous. Every spoke is a stepped 2-cell dash:
	# a lamp_glow inner cell under a team-trim tip.
	if not _celebrating() or _reaction_strength < 0.999:
		return
	var ticks := _reaction_ticks()
	var span := right - left
	for slot in range(2):
		var phase := posmod(ticks - 6 - slot * 10, 20)
		if phase >= 4:
			continue
		var salt := _reaction_serial * 37 + slot * 91 + (ticks - phase) * 7
		var cx := left + int(float(span) * (0.30 + 0.36 * float(slot))) + int(Style.hash01(salt) * 12.0) - 6
		var cy := horizon - 18 + int(Style.hash01(salt + 1) * 6.0)
		var trim: Color = palette.team_teal if posmod(slot + _reaction_serial, 2) == 0 else palette.stitch
		if phase == 0:
			Style.pixel_rect(self, Rect2(cx - 1, cy - 1, 2, 2), palette.lamp_glow)
			continue
		var radius := 1 + phase
		for direction: Vector2i in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
		]:
			var reach := radius if direction.x == 0 or direction.y == 0 else maxi(1, int(float(radius) * 0.75))
			var tip := Vector2i(cx, cy) + direction * reach
			var inner := Vector2i(cx, cy) + direction * maxi(1, reach - 1)
			Style.pixel_rect(self, Rect2(inner.x, inner.y, 1, 1), palette.lamp_glow)
			Style.pixel_rect(self, Rect2(tip.x, tip.y, 1, 1), trim)
		if phase < 2:
			Style.pixel_rect(self, Rect2(cx, cy, 1, 1), palette.lamp_glow)


func _draw_bursts() -> void:
	# Opaque stepped decay (§9): sparks stay authored colors and shrink to a
	# single cell over the back half of their life — never an alpha fade.
	for particle in _bursts:
		var age := float(particle.age)
		var duration := float(particle.duration)
		var velocity: Vector2 = particle.velocity
		var at: Vector2 = particle.origin + velocity * age + Vector2(0.0, 24.0 * age * age)
		var size := int(particle.size)
		if age > duration * 0.55:
			size = 1
		Style.pixel_rect(self, Rect2(at.round(), Vector2.ONE * size), particle.color)


func _project_world(world: Vector3) -> Vector2:
	match view_mode:
		"pitching":
			return Vector2(151.0 + world.x * 3.2, 168.0 - (18.0 - world.z) * 0.72 - world.y * 5.0)
		"batting":
			return Vector2(160.0 - world.x * 3.2, 168.0 - (18.0 - world.z) * 1.25 - world.y * 4.0)
		"fielding":
			return Vector2(160.0 + world.x * 2.25, 166.0 - (18.0 - world.z) * 1.65 - world.y * 0.5)
		"dugout":
			return Vector2(160.0 + world.x * 2.0, 143.0 - world.y * 3.0 - (18.0 - world.z) * 0.18)
		_:
			return Vector2(160.0 + world.x * 2.0, 165.0 - (18.0 - world.z) * 0.82 - world.y * 2.8)


func _reaction_level() -> float:
	if _reaction_timer <= 0.0 or _reaction_duration <= 0.0:
		return 0.0
	var remaining := clampf(_reaction_timer / _reaction_duration, 0.0, 1.0)
	return _reaction_strength * remaining * remaining


# --- Reaction choreography clocks (§9.5-9.7) -----------------------------------
# All celebration presentation derives from the existing timer envelopes and
# the reaction serial, quantized to 12 fps crowd ticks, so two canvases fed
# the same events stay cell-for-cell identical.


func _reaction_ticks() -> int:
	if _reaction_timer <= 0.0 or _reaction_duration <= 0.0:
		return 0
	return maxi(0, int(round((_reaction_duration - _reaction_timer) / CROWD_STEP)))


func _bell_ticks() -> int:
	if _bell_timer <= 0.0:
		return 0
	return maxi(0, int(round((BELL_DURATION - _bell_timer) / CROWD_STEP)))


func _celebrating() -> bool:
	# The celebration sequence (§9.7) runs while the bell reaction's crowd
	# envelope is live: only bell-flagged reactions overlap both timers.
	return _reaction_timer > 0.0 and _bell_timer > 0.0


func _wave_front_count() -> int:
	# Strength maps to the number of traveling wave fronts (§9.5).
	if _reaction_timer <= 0.0:
		return 0
	return clampi(1 + int(_reaction_strength * 2.2), 1, 3)


func _wave_raised(x: int, left: int, width: int, fronts: int) -> bool:
	# A clump raises while a front's trailing WAVE_BAND passes over it. Fronts
	# travel WAVE_SPEED cells per tick and space evenly across the section.
	if fronts <= 0 or width <= 0:
		return false
	var head := posmod(_reaction_ticks() * WAVE_SPEED, width)
	for front in range(fronts):
		var front_x := posmod(head + int(float(width * front) / float(fronts)), width)
		if posmod(front_x - (x - left), width) < WAVE_BAND:
			return true
	return false


func _sync_field_offset() -> void:
	if view_mode != "fielding":
		position = Vector2.ZERO
		return
	position = Vector2(
		roundi(clampf(_field_focus.x * -0.35, -22.0, 22.0)),
		roundi(clampf((_field_focus.z + 4.0) * -0.18, -14.0, 14.0)),
	)


func _colored_polygon(points: Array[Vector2], color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)
