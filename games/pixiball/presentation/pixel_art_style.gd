class_name PixiballPixelArtStyle
extends RefCounted

## Shared native-720p pixel drawing rules. Art is described on a 320x180 design
## grid, then PixelScene maps each design unit to an exact 4x4 block while the
## CanvasItems rasterize directly into the 1280x720 root framebuffer. There is
## no low-resolution viewport, texture upscale, filtering, or post-process.

const DESIGN_SIZE := Vector2i(320, 180)
const OUTPUT_SIZE := Vector2i(1280, 720)
const GRID_PIXEL_SIZE := 4
# Compatibility name for drawing code. ART_SIZE is a count of design cells,
# not a framebuffer size.
const ART_SIZE := DESIGN_SIZE
const VIEW_MODES := ["intro", "pitching", "batting", "fielding", "dugout"]

# SALTLIGHT role table (art bible §3.1): 42 roles x 3 moods. Roles are the
# palette API; every world CanvasItem reads colors through these names so the
# whole park re-grades per mood. No view file may hardcode a hex.
const MOOD_PALETTES := {
	"day": {
		"ink0": Color("0e1a22"),
		"ink1": Color("1d3340"),
		"shadow_cool": Color("2c4a52"),
		"sky_high": Color("85b7cd"),
		"sky_low": Color("b9dbd9"),
		"cloud_lit": Color("f0f6ec"),
		"cloud_shade": Color("a9c8ca"),
		"haze": Color("97bfc4"),
		"sea_deep": Color("2f6b85"),
		"sea_mid": Color("4f93a6"),
		"sea_light": Color("8ec4c4"),
		"foam": Color("e2f0e6"),
		"skyline_far": Color("7d9aa9"),
		"skyline_mid": Color("5b7b8c"),
		"skyline_near": Color("3f5d6e"),
		"structure": Color("35505f"),
		"structure_light": Color("64828e"),
		"brick_warm": Color("9d5a41"),
		"brick_light": Color("bd7f58"),
		"wood": Color("7c5a3e"),
		"wood_dark": Color("57402e"),
		"turf_light": Color("74a058"),
		"turf": Color("5a8749"),
		"turf_shadow": Color("416a41"),
		"turf_dark": Color("2f5138"),
		"clay_light": Color("d29a63"),
		"clay": Color("b0764a"),
		"clay_shadow": Color("7d5138"),
		"chalk": Color("f4eeda"),
		"seat_a": Color("4e7183"),
		"seat_b": Color("415c6d"),
		"crowd_shade": Color("263a49"),
		"lamp_core": Color("ffe9a8"),
		"lamp_glow": Color("f3c065"),
		"saltlight": Color("ff9e4a"),
		"stitch": Color("d84f3d"),
		"team_teal": Color("3ba189"),
		"team_gold": Color("e3b551"),
		"ui_ink": Color("0c141d"),
		"ui_slate": Color("16242f"),
		"ui_paper": Color("ece6d3"),
		"ui_steel": Color("90a5ac"),
	},
	"golden": {
		"ink0": Color("180f1e"),
		"ink1": Color("2c1f33"),
		"shadow_cool": Color("453049"),
		"sky_high": Color("6f4a75"),
		"sky_low": Color("e08a55"),
		"cloud_lit": Color("ffcf7e"),
		"cloud_shade": Color("b06a63"),
		"haze": Color("c07a66"),
		"sea_deep": Color("5b3f5e"),
		"sea_mid": Color("8a5a6a"),
		"sea_light": Color("d1926c"),
		"foam": Color("ffd9a0"),
		"skyline_far": Color("8a5f78"),
		"skyline_mid": Color("64465f"),
		"skyline_near": Color("47324a"),
		"structure": Color("3c2c44"),
		"structure_light": Color("6f5468"),
		"brick_warm": Color("a05a40"),
		"brick_light": Color("cd8156"),
		"wood": Color("7c5136"),
		"wood_dark": Color("543527"),
		"turf_light": Color("8a8748"),
		"turf": Color("6c6f3d"),
		"turf_shadow": Color("4d5334"),
		"turf_dark": Color("37402c"),
		"clay_light": Color("dd9557"),
		"clay": Color("b06e42"),
		"clay_shadow": Color("774631"),
		"chalk": Color("ffe9c0"),
		"seat_a": Color("6b4f68"),
		"seat_b": Color("574056"),
		"crowd_shade": Color("33253c"),
		"lamp_core": Color("ffedae"),
		"lamp_glow": Color("ffc063"),
		"saltlight": Color("ff9440"),
		"stitch": Color("e2543c"),
		"team_teal": Color("3f9a82"),
		"team_gold": Color("ecb64f"),
		"ui_ink": Color("140d1a"),
		"ui_slate": Color("241a2c"),
		"ui_paper": Color("f5e2c4"),
		"ui_steel": Color("a08d95"),
	},
	"night": {
		"ink0": Color("060b16"),
		"ink1": Color("101a2c"),
		"shadow_cool": Color("1a2a40"),
		"sky_high": Color("131f38"),
		"sky_low": Color("23395c"),
		"cloud_lit": Color("3e5578"),
		"cloud_shade": Color("263650"),
		"haze": Color("2c4260"),
		"sea_deep": Color("0c2138"),
		"sea_mid": Color("1c3d55"),
		"sea_light": Color("35617a"),
		"foam": Color("7fa8b0"),
		"skyline_far": Color("2a3f58"),
		"skyline_mid": Color("1f3147"),
		"skyline_near": Color("16253a"),
		"structure": Color("13202f"),
		"structure_light": Color("33495c"),
		"brick_warm": Color("4f3230"),
		"brick_light": Color("6e4a3c"),
		"wood": Color("453325"),
		"wood_dark": Color("2c2019"),
		"turf_light": Color("3d6a4c"),
		"turf": Color("2f5540"),
		"turf_shadow": Color("234233"),
		"turf_dark": Color("182f26"),
		"clay_light": Color("8f6142"),
		"clay": Color("6e4832"),
		"clay_shadow": Color("4a3125"),
		"chalk": Color("d9e4d8"),
		"seat_a": Color("2c4356"),
		"seat_b": Color("223447"),
		"crowd_shade": Color("131f2d"),
		"lamp_core": Color("fff1b8"),
		"lamp_glow": Color("ffca5f"),
		"saltlight": Color("ffa348"),
		"stitch": Color("e0563f"),
		"team_teal": Color("46b096"),
		"team_gold": Color("f0be55"),
		"ui_ink": Color("050a12"),
		"ui_slate": Color("0e1927"),
		"ui_paper": Color("e3ddca"),
		"ui_steel": Color("7e93a3"),
	},
}

# Lantern Wharf canonical environment roles (art bible v2.0 §3.2): 26 roles x
# 3 moods carrying the exact bible values. This table is the canonical palette
# contract for the greenfield rebuild; the SALTLIGHT `MOOD_PALETTES` above is
# retained verbatim as the legacy lookup that every current drawing path still
# renders through. Five role names exist in both tables with different values
# (`sky_high`, `sky_low`, `cloud_lit`, `cloud_shade`, `lamp_glow`):
# `palette()`/`world_role()` keep serving the legacy value while
# `environment_role()` serves the canonical one, so call sites migrate
# deliberately instead of being silently recolored. The two `*_veil` roles are
# the only translucent entries (§7.8); every other canonical color is opaque.
const CANONICAL_ENVIRONMENT_PALETTES := {
	"day": {
		"sky_high": Color("3a79b4"),
		"sky_low": Color("a3ccd9"),
		"cloud_lit": Color("ecf4ef"),
		"cloud_shade": Color("b7d3d9"),
		"sea_far": Color("2e6c95"),
		"sea_near": Color("57a1b3"),
		"sea_glint": Color("cdeae3"),
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
		"chalk_line": Color("f2ead2"),
		"wall_pad": Color("1e4b45"),
		"lamp_glow": Color("ffeaae"),
		"mist_veil": Color(Color("9ec4cc"), 0.20),
		"vignette_veil": Color(Color("0e1220"), 0.10),
	},
	"golden": {
		"sky_high": Color("5a3a68"),
		"sky_low": Color("ec9a5e"),
		"cloud_lit": Color("f9cd8a"),
		"cloud_shade": Color("cf8f6f"),
		"sea_far": Color("6b4a69"),
		"sea_near": Color("c78468"),
		"sea_glint": Color("ffdca3"),
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
		"chalk_line": Color("ffeac1"),
		"wall_pad": Color("3e4b3f"),
		"lamp_glow": Color("ffda90"),
		"mist_veil": Color(Color("dca47b"), 0.26),
		"vignette_veil": Color(Color("26182e"), 0.16),
	},
	"night": {
		"sky_high": Color("0b1330"),
		"sky_low": Color("223760"),
		"cloud_lit": Color("42537c"),
		"cloud_shade": Color("2b3a62"),
		"sea_far": Color("0e2442"),
		"sea_near": Color("1a3a5e"),
		"sea_glint": Color("7ea9d2"),
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
		"chalk_line": Color("cacde0"),
		"wall_pad": Color("102b2d"),
		"lamp_glow": Color("ffe3a2"),
		"mist_veil": Color(Color("20365c"), 0.34),
		"vignette_veil": Color(Color("0b1330"), 0.24),
	},
}

# Canonical role discovery: every §3.2 role name, in bible order. Later passes
# assert coverage against this list instead of re-deriving it.
const ENVIRONMENT_ROLE_NAMES := [
	"sky_high", "sky_low", "cloud_lit", "cloud_shade",
	"sea_far", "sea_near", "sea_glint",
	"town_far", "town_near", "roof_accent", "window_lit",
	"stand_shell", "seat_board", "crowd_shadow", "crowd_warm", "crowd_cool",
	"turf_lit", "turf_main", "turf_shade",
	"clay_main", "clay_lit", "chalk_line", "wall_pad", "lamp_glow",
	"mist_veil", "vignette_veil",
]

# The only two sanctioned translucent draws in the world renderer (§7.8).
const VEIL_ROLE_NAMES := ["mist_veil", "vignette_veil"]

# Interim spectator wardrobe: muted per §4.2 (crowd saturation <=45%, value
# span <=3 steps) so the placeholder crowd sits inside the WET SLATE world
# until the P05 clumped-crowd rebuild replaces the drawing itself.
const CROWD_SHIRTS := [
	Color("5c7a72"), Color("77685a"), Color("6d5f70"), Color("55677a"),
	Color("7d6353"), Color("5e7258"), Color("7a7266"), Color("4e5f6d"),
]
const CROWD_SKINS := [
	Color("f0c29a"), Color("dda06b"), Color("bd7747"),
	Color("955735"), Color("704027"), Color("4b2a20"),
]

# SALTLIGHT value ladder (§4.1): ten luminance steps, V0 (~6%) to V9 (~95%).
# Every palette role is pinned to a band per mood; depth must survive a
# grayscale flatten, so drawing code reasons in steps rather than raw hexes.
const VALUE_LADDER := [0.06, 0.159, 0.258, 0.357, 0.456, 0.554, 0.653, 0.752, 0.851, 0.95]

# Haze pre-blend strengths (§6.9): background bands are veiled toward the
# mood's `haze` role with authored opaque result colors, computed when a layer
# builds its colors — never with runtime alpha.
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


static func palette(mood: String) -> Dictionary:
	return MOOD_PALETTES[normalized_mood(mood)]


## Canonical Lantern Wharf role table for a mood (§3.2). Legacy callers keep
## `palette()`; canonical consumers resolve through here.
static func environment_palette(mood: String) -> Dictionary:
	return CANONICAL_ENVIRONMENT_PALETTES[normalized_mood(mood)]


## Canonical environment role lookup. Unknown roles stay loud: they report an
## error and return magenta so a bad name is visible in captures, never hidden.
static func environment_role(role: String, mood := "day") -> Color:
	var roles: Dictionary = environment_palette(mood)
	if not roles.has(role):
		push_error("Unknown Lantern Wharf environment role \"%s\" (mood \"%s\")." % [role, mood])
		return Color.MAGENTA
	return roles[role] as Color


static func has_environment_role(role: String) -> bool:
	return CANONICAL_ENVIRONMENT_PALETTES["day"].has(role)


static func luminance(color: Color) -> float:
	return color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722


## Nearest rung of the ten-step SALTLIGHT value ladder (§4.1).
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


## Re-pin a color's luminance to a ladder rung, preserving hue. Always opaque.
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


## Move a color up (+) or down (-) the value ladder by whole steps.
static func shift_value(color: Color, steps: int) -> Color:
	return with_value_step(color, value_step(color) + steps)


## Atmospheric veil (§6.9): pre-blend a layer color toward the mood's haze
## role. Returns an authored opaque color; callers cache it at build time.
static func haze_veil(color: Color, mood: String, strength: float) -> Color:
	var haze_color: Color = palette(mood).haze
	var veiled := color.lerp(haze_color, clampf(strength, 0.0, 1.0))
	veiled.a = 1.0
	return veiled


static func hash01(seed: int) -> float:
	# Arithmetic-only hash: stable across runs and independent of RNG state.
	var value := sin(float(seed) * 12.9898 + 78.233) * 43758.5453
	return value - floor(value)


static func pick(values: Array, seed: int) -> Variant:
	if values.is_empty():
		return null
	return values[posmod(int(floor(hash01(seed) * float(values.size()))), values.size())]


static func design_to_native(value: Vector2) -> Vector2:
	return value * float(GRID_PIXEL_SIZE)


static func design_rect_to_native(rect: Rect2) -> Rect2:
	return Rect2(design_to_native(rect.position), design_to_native(rect.size))


static func pixel_rect(canvas: CanvasItem, rect: Rect2, color: Color) -> void:
	var snapped := Rect2(rect.position.floor(), rect.size.ceil())
	if snapped.size.x > 0.0 and snapped.size.y > 0.0:
		canvas.draw_rect(snapped, color, true)


static func pixel_line(canvas: CanvasItem, from: Vector2, to: Vector2, color: Color, width := 1.0) -> void:
	canvas.draw_line(from.round(), to.round(), color, maxf(1.0, roundf(width)), false)


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
