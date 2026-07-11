class_name PixiballStyle
extends RefCounted

## Shared UE-derived visual language for the Pixiball shell + HUD.
##
## Single source of truth for the pixel-UI restyle. Replaces the two divergent
## palettes (HUD vs Pitch Intel) and centralises the Geist Pixel font roles and
## the flat-rect / ink-border / hard-pixel-drop-shadow chrome from the Unreal
## original. All px values are UE 1080p reference sizes used directly as Godot
## font sizes (the game already authors UI at 1280x720 absolute coords).

# --- Fonts (Geist Pixel family) --------------------------------------------
# Role mapping (UE -> Geist Pixel):
#   Display = GeistPixel-Square  (all-caps labels, names, titles, buttons, badges)
#   Score   = GeistPixel-Grid    (numeric readouts: count, scores, velo, K totals)
#   Body    = GeistPixel-Square   (smaller sizes; Geist Pixel is display-oriented)
#   Hero    = GeistPixel-Line     (landing PIXIBALL flair)
const FONT_DISPLAY := preload("res://assets/fonts/geist_pixel/GeistPixel-Square.ttf")
const FONT_SCORE := preload("res://assets/fonts/geist_pixel/GeistPixel-Grid.ttf")
const FONT_BODY := preload("res://assets/fonts/geist_pixel/GeistPixel-Square.ttf")
const FONT_HERO := preload("res://assets/fonts/geist_pixel/GeistPixel-Line.ttf")

# --- UE core palette (spec 2a) ---------------------------------------------
const INK := Color("1a1c2c")           # the "black": every border/frame + deepest shadow
const NIGHT := Color("29366f")         # menu screen background fill
const NIGHT2 := Color("3b4a8c")        # default (unfocused) button fill
const STEEL := Color("94b0c2")         # secondary label text
const SLATE := Color("566c86")         # tertiary / dim text
const SHADOW_BLUE := Color("333c57")   # divider rules, unlit lamp/track, bar empty track
const GRASS := Color("38b764")         # active / good
const GRASS_DEEP := Color("257953")    # landing gradient bottom band
const CLAY := Color("b86f50")
const CLAY_LIGHT := Color("e39764")    # stamina TIRED tier; grade D
const CHALK := Color("f4f0e1")         # primary "white" text
const WHITE := Color("ffffff")         # PERFECT swing chip
const STITCH := Color("e64539")        # the "red": CTA focus, danger, GASSED, grade F
const STITCH_DEEP := Color("a52639")
const GOLD := Color("ffcd75")          # hero accent: focus frames, score digits, grade C
const SKY := Color("41a6f6")           # LHP badge, ball/warn
const TEAL := Color("73eff7")          # tunnel/deceptive, active matchup slot, landing footer
const VIOLET := Color("5d275d")
const SCOREBOARD := Color("10121d")    # HUD panel inner surface (darker than Ink)
const INSET_CREAM := Color("e6e0cb")   # matchup-slot cream inset

# --- Swing-quality chips (spec 2e) -----------------------------------------
const SWING_MISS := Color("ff6b6b")
const SWING_GOOD := Color("8fe08f")
const SWING_EARLY := Color("8fd0ff")
const SWING_LATE := Color("ff9a6a")

# --- Arsenal pitch-slot colors (spec 2b) A/B/X/Y/RT ------------------------
const PITCH_SLOTS := [
	Color("6ee76e"), Color("ff6b6b"), Color("67b7ff"), Color("ffd94a"), Color("c78bff"),
]

# --- Chrome constants (spec 3a) --------------------------------------------
const BORDER_PANEL := 3     # thick ink border: panels, cards, buttons
const BORDER_FRAME := 2     # thin ink frame: lamps, bars, badges
const SHADOW_PANEL := 4     # default panel/button drop-shadow
const SHADOW_HERO := 6      # hero panels

static var _theme: Theme


## Flat UE surface: solid fill + ink border + optional hard pixel drop-shadow,
## square corners, no anti-aliasing. Pass shadow<=0 for bars/lamps/badges.
static func panel(fill: Color, border: Color, border_width := BORDER_PANEL, shadow := SHADOW_PANEL, margin_h := 12, margin_v := 8) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.content_margin_left = margin_h
	style.content_margin_right = margin_h
	style.content_margin_top = margin_v
	style.content_margin_bottom = margin_v
	if shadow > 0:
		style.shadow_color = Color(INK, 0.45)
		style.shadow_size = shadow
		style.shadow_offset = Vector2(shadow, shadow)
	return style


## Cached theme injecting Display (Square) as the default Label font. Applied to
## the shell + game Control roots so every code-built label inherits the pixel
## face; numeric readouts opt into FONT_SCORE via add_theme_font_override.
static func ui_theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.set_font("font", "Label", FONT_DISPLAY)
	return _theme


## Approximate UE letter-tracking (spec 1c) via glyph spacing. Used sparingly on
## large caps/hero labels where the extra width is free.
static func tracked(base: Font, glyph_spacing: int) -> FontVariation:
	var variation := FontVariation.new()
	variation.base_font = base
	variation.set_spacing(TextServer.SPACING_GLYPH, glyph_spacing)
	return variation


## Letter-grade -> color (spec 2g).
static func grade_color(letter: String) -> Color:
	match letter.to_upper():
		"A": return GRASS
		"B": return TEAL
		"C": return GOLD
		"D": return CLAY_LIGHT
		_: return STITCH


## Stamina tier {color, label} from a 0..1 fraction (spec 3f).
static func stamina_tier(fraction: float) -> Dictionary:
	if fraction <= 0.05:
		return {"color": STITCH, "label": "GASSED", "gassed": true}
	if fraction < 0.33:
		return {"color": CLAY_LIGHT, "label": "TIRED", "gassed": false}
	if fraction < 0.66:
		return {"color": GOLD, "label": "TIRING", "gassed": false}
	return {"color": GRASS, "label": "FRESH", "gassed": false}


## Raw-threshold meter color (spec 3f note): pitcher-select stamina meter.
static func meter_color(fraction: float) -> Color:
	if fraction >= 0.66:
		return GRASS
	if fraction >= 0.33:
		return GOLD
	return STITCH
