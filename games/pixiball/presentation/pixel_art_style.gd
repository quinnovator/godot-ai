class_name PixiballPixelArtStyle
extends RefCounted

## Shared native-1440p pixel drawing rules. Composition retains the original
## 320x180 coordinate vocabulary, then a 2x density transform authors it onto
## a 640x360 design grid. PixelScene maps each dense design unit to an exact
## 4x4 block while CanvasItems rasterize directly into the 2560x1440 root. There is
## no low-resolution viewport, texture upscale, or filtered sampling. A single
## world-only dense-pixel compositor may grade the direct native framebuffer;
## HUD CanvasLayers are drawn afterward and remain unprocessed.

const COMPOSITION_SIZE := Vector2i(320, 180)
const DENSITY_SCALE := 2
const DESIGN_SIZE := COMPOSITION_SIZE * DENSITY_SCALE
const OUTPUT_SIZE := Vector2i(2560, 1440)
const GRID_PIXEL_SIZE := 4
# Compatibility name for legacy composition code. Drawing stages are expanded
# by DENSITY_SCALE before the unchanged 4px native raster grid.
const ART_SIZE := COMPOSITION_SIZE
const VIEW_MODES := ["intro", "pitching", "batting", "fielding", "dugout"]

# Lantern Wharf environment + structure roles (art bible §3.2 + renderer
# structure). Single palette API: every world CanvasItem reads colors through
# these names so the whole park re-grades per mood. No view file may hardcode a
# hex. Veils are separate (translucent) via veil_role().
const MOOD_PALETTES := {
	"day": {
		"sky_high": Color("3a79b4"),
		"sky_low": Color("a3ccd9"),
		"cloud_lit": Color("ecf4ef"),
		"cloud_shade": Color("b7d3d9"),
		"sea_far": Color("2e6c95"),
		"sea_near": Color("57a1b3"),
		"sea_glint": Color("cdeae3"),
		"haze": Color("9ec4cc"),
		"town_far": Color("4d6c8a"),
		"town_near": Color("35526d"),
		"roof_accent": Color("ad5346"),
		"window_lit": Color("f4d98d"),
		"stand_shell": Color("2b4359"),
		"seat_board": Color("3f6278"),
		"crowd_shadow": Color("203449"),
		"crowd_warm": Color("d9976b"),
		"crowd_cool": Color("6e88a1"),
		"turf_lit": Color("5f9d54"),
		"turf_main": Color("49834c"),
		"turf_shade": Color("346141"),
		"clay_main": Color("c17b4f"),
		"clay_lit": Color("dea16c"),
		"clay_shade": Color("8a5638"),
		"chalk_line": Color("f2ead2"),
		"wall_pad": Color("1e4b45"),
		"lamp_glow": Color("ffeaae"),
		"ink": Color("0e1220"),
		"ink_mid": Color("1a2438"),
		"wood": Color("7c5a3e"),
		"wood_dark": Color("57402e"),
		"lantern_gold": Color("ffc65a"),
		"stitch_red": Color("d94a3d"),
		"signal_teal": Color("55d6c4"),
	},
	"golden": {
		"sky_high": Color("5a3a68"),
		"sky_low": Color("ec9a5e"),
		"cloud_lit": Color("f9cd8a"),
		"cloud_shade": Color("cf8f6f"),
		"sea_far": Color("6b4a69"),
		"sea_near": Color("c78468"),
		"sea_glint": Color("ffdca3"),
		"haze": Color("dca47b"),
		"town_far": Color("745a7d"),
		"town_near": Color("574261"),
		"roof_accent": Color("c2694d"),
		"window_lit": Color("ffcf7e"),
		"stand_shell": Color("4b3753"),
		"seat_board": Color("72576a"),
		"crowd_shadow": Color("392c46"),
		"crowd_warm": Color("ea9d63"),
		"crowd_cool": Color("8c6f87"),
		"turf_lit": Color("89874b"),
		"turf_main": Color("6f7142"),
		"turf_shade": Color("4f5536"),
		"clay_main": Color("cb7c51"),
		"clay_lit": Color("efa46a"),
		"clay_shade": Color("8f5238"),
		"chalk_line": Color("ffeac1"),
		"wall_pad": Color("3e4b3f"),
		"lamp_glow": Color("ffda90"),
		"ink": Color("0e1220"),
		"ink_mid": Color("241a2c"),
		"wood": Color("7c5136"),
		"wood_dark": Color("543527"),
		"lantern_gold": Color("ffc65a"),
		"stitch_red": Color("d94a3d"),
		"signal_teal": Color("55d6c4"),
	},
	"night": {
		"sky_high": Color("0b1330"),
		"sky_low": Color("223760"),
		"cloud_lit": Color("42537c"),
		"cloud_shade": Color("2b3a62"),
		"sea_far": Color("0e2442"),
		"sea_near": Color("1a3a5e"),
		"sea_glint": Color("7ea9d2"),
		"haze": Color("20365c"),
		"town_far": Color("1b2a4a"),
		"town_near": Color("12203c"),
		"roof_accent": Color("463250"),
		"window_lit": Color("ffd98a"),
		"stand_shell": Color("16213c"),
		"seat_board": Color("263252"),
		"crowd_shadow": Color("0c152a"),
		"crowd_warm": Color("cd8d51"),
		"crowd_cool": Color("3c4e72"),
		"turf_lit": Color("2d5349"),
		"turf_main": Color("204139"),
		"turf_shade": Color("16312f"),
		"clay_main": Color("6d4b45"),
		"clay_lit": Color("8c6253"),
		"clay_shade": Color("4a3228"),
		"chalk_line": Color("cacde0"),
		"wall_pad": Color("102b2d"),
		"lamp_glow": Color("ffe3a2"),
		"ink": Color("0e1220"),
		"ink_mid": Color("101a2c"),
		"wood": Color("453325"),
		"wood_dark": Color("2c2019"),
		"lantern_gold": Color("ffc65a"),
		"stitch_red": Color("e0563f"),
		"signal_teal": Color("55d6c4"),
	},
}

# Canonical role discovery: opaque mood roles in bible/renderer order.
const ENVIRONMENT_ROLE_NAMES := [
	"sky_high",
	"sky_low",
	"cloud_lit",
	"cloud_shade",
	"sea_far",
	"sea_near",
	"sea_glint",
	"haze",
	"town_far",
	"town_near",
	"roof_accent",
	"window_lit",
	"stand_shell",
	"seat_board",
	"crowd_shadow",
	"crowd_warm",
	"crowd_cool",
	"turf_lit",
	"turf_main",
	"turf_shade",
	"clay_main",
	"clay_lit",
	"clay_shade",
	"chalk_line",
	"wall_pad",
	"lamp_glow",
	"ink",
	"ink_mid",
	"wood",
	"wood_dark",
	"lantern_gold",
	"stitch_red",
	"signal_teal",
]

# The only two sanctioned translucent draws in the world renderer (§7.8).
const VEIL_PALETTES := {
	"day": {
		"mist_veil": Color(Color("9ec4cc"), 0.2),
		"vignette_veil": Color(Color("0e1220"), 0.1),
	},
	"golden": {
		"mist_veil": Color(Color("dca47b"), 0.26),
		"vignette_veil": Color(Color("26182e"), 0.16),
	},
	"night": {
		"mist_veil": Color(Color("20365c"), 0.34),
		"vignette_veil": Color(Color("0b1330"), 0.24),
	},
}
const VEIL_ROLE_NAMES := ["mist_veil", "vignette_veil"]

# Value ladder (§4.1): ten luminance steps, V0 (~6%) to V9 (~95%).
const VALUE_LADDER := [0.06, 0.159, 0.258, 0.357, 0.456, 0.554, 0.653, 0.752, 0.851, 0.95]

# Haze pre-blend strengths: background bands veiled toward mood haze with
# authored opaque results — never runtime alpha.
const HAZE_FAR := 0.60
const HAZE_MID := 0.35
const HAZE_NEAR := 0.15

# Three-bit rows for a deliberately compact 3x5 stadium-board font.
const FONT_3X5 := {
	"A": [2, 5, 7, 5, 5], "B": [6, 5, 6, 5, 6],
	"C": [3, 4, 4, 4, 3], "D": [6, 5, 5, 5, 6],
	"E": [7, 4, 6, 4, 7], "F": [7, 4, 6, 4, 4],
	"G": [3, 4, 5, 5, 3], "H": [5, 5, 7, 5, 5],
	"I": [7, 2, 2, 2, 7], "J": [1, 1, 1, 5, 2],
	"K": [5, 5, 6, 5, 5], "L": [4, 4, 4, 4, 7],
	"M": [5, 7, 7, 5, 5], "N": [5, 7, 7, 7, 5],
	"O": [2, 5, 5, 5, 2], "P": [6, 5, 6, 4, 4],
	"Q": [2, 5, 5, 3, 1], "R": [6, 5, 6, 5, 5],
	"S": [3, 4, 2, 1, 6], "T": [7, 2, 2, 2, 2],
	"U": [5, 5, 5, 5, 7], "V": [5, 5, 5, 5, 2],
	"W": [5, 5, 7, 7, 5], "X": [5, 5, 2, 5, 5],
	"Y": [5, 5, 2, 2, 2], "Z": [7, 1, 2, 4, 7],
	"0": [7, 5, 5, 5, 7], "1": [2, 6, 2, 2, 7],
	"2": [6, 1, 2, 4, 7], "3": [6, 1, 2, 1, 6],
	"4": [5, 5, 7, 1, 1], "5": [7, 4, 6, 1, 6],
	"6": [3, 4, 7, 5, 7], "7": [7, 1, 2, 2, 2],
	"8": [7, 5, 7, 5, 7], "9": [7, 5, 7, 1, 6],
	"-": [0, 0, 7, 0, 0], ".": [0, 0, 0, 0, 2],
}


static func normalized_mood(value: String) -> String:
	var key := value.strip_edges().to_lower()
	return key if MOOD_PALETTES.has(key) else "day"


static func normalized_view(value: String) -> String:
	var key := value.strip_edges().to_lower()
	return key if key in VIEW_MODES else "intro"


## Opaque mood palette for the Lantern Wharf world renderer.
static func palette(mood: String) -> Dictionary:
	return MOOD_PALETTES[normalized_mood(mood)]


## Alias retained for call sites that say "environment".
static func environment_palette(mood: String) -> Dictionary:
	return palette(mood)


## Role lookup. Unknown roles stay loud: error + magenta.
static func role(role_name: String, mood := "day") -> Color:
	var roles: Dictionary = palette(mood)
	if roles.has(role_name):
		return roles[role_name] as Color
	var veils: Dictionary = VEIL_PALETTES[normalized_mood(mood)]
	if veils.has(role_name):
		return veils[role_name] as Color
	push_error("Unknown Lantern Wharf role \"%s\" (mood \"%s\")." % [role_name, mood])
	return Color.MAGENTA


static func environment_role(role_name: String, mood := "day") -> Color:
	return role(role_name, mood)


static func has_environment_role(role_name: String) -> bool:
	return MOOD_PALETTES["day"].has(role_name) or VEIL_PALETTES["day"].has(role_name)


static func veil_role(role_name: String, mood := "day") -> Color:
	var veils: Dictionary = VEIL_PALETTES[normalized_mood(mood)]
	if not veils.has(role_name):
		push_error("Unknown veil role \"%s\" (mood \"%s\")." % [role_name, mood])
		return Color.MAGENTA
	return veils[role_name] as Color


static func luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


static func value_step(color: Color) -> int:
	var level := luminance(color)
	var best := 0
	var best_distance := absf(level - float(VALUE_LADDER[0]))
	for step in range(1, VALUE_LADDER.size()):
		var distance := absf(level - float(VALUE_LADDER[step]))
		if distance < best_distance:
			best_distance = distance
			best = step
	return best


static func value_steps_between(a: Color, b: Color) -> int:
	return absi(value_step(a) - value_step(b))


static func with_value_step(color: Color, step: int) -> Color:
	var target := float(VALUE_LADDER[clampi(step, 0, VALUE_LADDER.size() - 1)])
	var current := luminance(color)
	var result: Color
	if current <= 0.0005:
		result = Color(target, target, target)
	elif target <= current:
		var ratio := target / current
		result = Color(color.r * ratio, color.g * ratio, color.b * ratio)
	else:
		result = color.lerp(Color.WHITE, (target - current) / maxf(0.0005, 1.0 - current))
	result.a = 1.0
	return result


static func shift_value(color: Color, steps: int) -> Color:
	return with_value_step(color, value_step(color) + steps)


static func haze_veil(color: Color, mood: String, strength: float) -> Color:
	var haze_color: Color = palette(mood).haze
	var veiled := color.lerp(haze_color, clampf(strength, 0.0, 1.0))
	veiled.a = 1.0
	return veiled


static func hash01(seed: int) -> float:
	var value := sin(float(seed) * 12.9898 + 78.233) * 43758.5453
	return value - floor(value)


static func pick(values: Array, seed: int) -> Variant:
	if values.is_empty():
		return null
	return values[posmod(int(floor(hash01(seed) * float(values.size()))), values.size())]


static func design_to_native(value: Vector2) -> Vector2:
	return value * float(GRID_PIXEL_SIZE)


static func composition_to_design(value: Vector2) -> Vector2:
	return value * float(DENSITY_SCALE)


static func design_rect_to_native(rect: Rect2) -> Rect2:
	return Rect2(design_to_native(rect.position), design_to_native(rect.size))


static func pixel_rect(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var snapped := Rect2(rect.position.floor(), rect.size.ceil())
	if snapped.size.x > 0.0 and snapped.size.y > 0.0:
		canvas.draw_rect(snapped, color, true)


static func detail_rect(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	# Half-composition increments are one true cell on the 640x360 design grid.
	# This deliberately avoids pixel_rect's legacy whole-cell floor/ceil step.
	var snapped_position := (rect.position * float(DENSITY_SCALE)).floor() / float(DENSITY_SCALE)
	var snapped_size := (rect.size * float(DENSITY_SCALE)).ceil() / float(DENSITY_SCALE)
	if snapped_size.x > 0.0 and snapped_size.y > 0.0:
		canvas.draw_rect(Rect2(snapped_position, snapped_size), color, true)


static func pixel_line(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color, width := 1.0) -> void:
	# Line weight participates in the density migration independently from
	# composition geometry: a legacy one-cell line becomes one dense cell, not
	# two. Under the caller's 2x density transform this is still pixel-aligned.
	var dense_width := maxf(1.0 / float(DENSITY_SCALE), roundf(width) / float(DENSITY_SCALE))
	canvas.draw_line(from.round(), to.round(), color, dense_width, false)


static func pixel_ellipse(canvas: CanvasItem, center: Vector2, radius: Vector2, color: Color) -> void:
	var rx := maxi(1, roundi(radius.x))
	var ry := maxi(1, roundi(radius.y))
	for y in range(-ry, ry + 1):
		var normalized := float(y * y) / float(ry * ry)
		var half_width := roundi(float(rx) * sqrt(maxf(0.0, 1.0 - normalized)))
		pixel_rect(canvas, Rect2(center + Vector2(-half_width, y), Vector2(half_width * 2 + 1, 1)), color)


static func pixel_text(canvas: CanvasItem, text: String, at: Vector2, color: Color, pixel_scale := 1) -> void:
	var scale_value := maxi(1, pixel_scale)
	var cursor := at.floor()
	for character in text.to_upper():
		if character == " ":
			cursor.x += 4 * scale_value
			continue
		var rows: Array = FONT_3X5.get(character, [])
		if rows.is_empty():
			cursor.x += 4 * scale_value
			continue
		for row in range(5):
			var mask := int(rows[row])
			for column in range(3):
				if mask & (1 << (2 - column)):
					pixel_rect(
						canvas,
						Rect2(cursor + Vector2(column, row) * scale_value, Vector2.ONE * scale_value),
						color,
					)
		cursor.x += 4 * scale_value
