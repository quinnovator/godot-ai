class_name PixiballStyle
extends RefCounted

## Shared harbor-pixel visual language for the Pixiball shell + HUD.
##
## The chunky display type, compact score face, bounded palette, and hard-offset
## frames form one original arcade treatment across menus and live play. All
## values are authored directly against the game's native 1280x720 canvas.

const NATIVE_UNIT := 4
const NATIVE_SIZE := Vector2(1280, 720)

# --- Pixel font roles ------------------------------------------------------
# Pixelify Sans carries display chrome, DotGothic16 keeps body copy open and
# readable, and VT323 gives scores the reference broadcast-board cadence.
const FONT_DISPLAY := preload("res://assets/fonts/unreal_ui/PixelifySans-Regular.ttf")
const FONT_SCORE := preload("res://assets/fonts/unreal_ui/VT323-Regular.ttf")
const FONT_BODY := preload("res://assets/fonts/unreal_ui/DotGothic16-Regular.ttf")
const FONT_HERO := preload("res://assets/fonts/unreal_ui/PixelifySans-Regular.ttf")

# --- Core arcade palette ---------------------------------------------------
# Values follow the SALTLIGHT role table (art bible §3.1); role names noted so
# P10+ can migrate call sites onto the mood-aware world roles below. Constant
# names stay stable for existing consumers.
const INK := Color("0c141d")           # ui_ink: every border/frame + deepest shadow
const NIGHT := Color("16242f")         # ui_slate: menu screen background fill
const NIGHT2 := Color("2c4a52")        # shadow_cool: default (unfocused) button fill
const STEEL := Color("90a5ac")         # ui_steel: secondary label text
const SLATE := Color("64828e")         # structure_light: tertiary / dim text
const SHADOW_BLUE := Color("1d3340")   # ink1: divider rules, unlit lamp/track, bar empty track
const GRASS := Color("3ba189")         # team_teal: active / good
const GRASS_DEEP := Color("2d7a67")    # team_teal shade: landing gradient bottom band
const CLAY := Color("b0764a")          # clay
const CLAY_LIGHT := Color("d29a63")    # clay_light: stamina TIRED tier; grade D
const CHALK := Color("ece6d3")         # ui_paper: primary "white" text
const WHITE := Color("ffffff")         # PERFECT swing chip
const STITCH := Color("e64539")        # the "red": CTA focus, danger, GASSED, grade F (test-pinned)
const STITCH_DEEP := Color("a52639")
const GOLD := Color("e3b551")          # team_gold: hero accent, score digits, grade C
const SALTLIGHT := Color("ff9e4a")     # THE focal warm; exactly one on screen (§9.4)
const SKY := Color("4f93a6")           # sea_mid: LHP badge, ball/warn
const TEAL := Color("8ec4c4")          # sea_light: tunnel/deceptive, active matchup slot
const VIOLET := Color("453049")        # shadow_cool (golden)
const SCOREBOARD := Color("050a12")    # ui_ink (night): HUD panel inner surface (darker than Ink)
const INSET_CREAM := Color("e3ddca")   # ui_paper (night): matchup-slot cream inset

# --- Harbor dusk support palette ------------------------------------------
# These hues are reserved for environmental framing and translucent surfaces;
# the gameplay-semantic colors above stay stable (especially STITCH).
const HARBOR_WASH := Color("101a2c")   # ink1 (night)
const PANEL := Color("0e1927")         # ui_slate (night)
const PANEL_RAISED := Color("23395c")  # sky_low (night)
const SEA_DEEP := Color("1c3d55")      # sea_mid (night)
const SEA := Color("2f6b85")           # sea_deep (day)
const SUNSET := Color("e08a55")        # sky_low (golden)
const FOAM := Color("e2f0e6")          # foam (day)
const WINDOW_GLOW := Color("ffe9a8")   # lamp_core (day)

# --- Lantern Wharf fixed identity roles (art bible v2.0 §3.1) ---------------
# The canonical mood-invariant identity contract, exact bible values. The
# legacy arcade constants above keep their current values so every existing
# call path renders unchanged; where a legacy constant approximates an
# identity role (INK vs `ink`, CHALK vs `chalk_paper`, STEEL vs `steel_text`,
# STITCH vs `stitch_red`), both lookups stay explicit and call sites migrate
# deliberately, never by silent recolor.
const IDENTITY_ROLES := {
	"ink": Color("0e1220"),
	"ball_white": Color("f8f4e6"),
	"stitch_red": Color("d94a3d"),
	"lantern_gold": Color("ffc65a"),
	"signal_teal": Color("55d6c4"),
	"chalk_paper": Color("efe9d4"),
	"steel_text": Color("9db2c4"),
	"slate_text": Color("5f7189"),
	"good_green": Color("46bd6e"),
	"warn_amber": Color("f2a13c"),
}

# Canonical role discovery: every §3.1 role name, in bible order.
const IDENTITY_ROLE_NAMES := [
	"ink", "ball_white", "stitch_red", "lantern_gold", "signal_teal",
	"chalk_paper", "steel_text", "slate_text", "good_green", "warn_amber",
]

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
const BORDER_PANEL := 12    # thick ink border: panels, cards, buttons
const BORDER_FRAME := 8     # thin ink frame: lamps, bars, badges
const SHADOW_SMALL := 8     # badges and small chips
const SHADOW_PANEL := 16    # default panel/button drop-shadow
const SHADOW_HERO := 24     # hero panels

const WorldStyle = preload("res://presentation/pixel_art_style.gd")

static var _theme: Theme


## Mood-aware SALTLIGHT world role (ui_ink, ui_paper, saltlight, ...). UI
## chrome that must re-grade with the park reads roles through here instead of
## duplicating hexes.
static func world_role(role: String, mood := "day") -> Color:
	var value: Variant = WorldStyle.palette(mood).get(role, Color.MAGENTA)
	return value as Color


## Canonical mood-invariant identity role (art bible v2.0 §3.1). Unknown roles
## stay loud: they report an error and return magenta, never a quiet fallback.
static func identity_role(role: String) -> Color:
	if not IDENTITY_ROLES.has(role):
		push_error("Unknown Lantern Wharf identity role \"%s\"." % role)
		return Color.MAGENTA
	return IDENTITY_ROLES[role] as Color


## Canonical Lantern Wharf environment role (art bible v2.0 §3.2), delegated
## to the world style table. `world_role()` above stays on the legacy SALTLIGHT
## table; this is the canonical lookup path for UI code.
static func environment_role(role: String, mood := "day") -> Color:
	return WorldStyle.environment_role(role, mood)


## Flat pixel surface: solid fill + optional accent frame + hard offset depth,
## square corners, no anti-aliasing. Pass shadow<=0 for bars/lamps/badges.
static func panel(fill: Color, border: Color, border_width := BORDER_PANEL, shadow := SHADOW_PANEL, margin_h := 48, margin_v := 32) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(0)
	style.anti_aliasing = false
	style.border_blend = false
	style.content_margin_left = margin_h
	style.content_margin_right = margin_h
	style.content_margin_top = margin_v
	style.content_margin_bottom = margin_v
	if shadow > 0:
		style.shadow_color = Color(SCOREBOARD, 0.86)
		style.shadow_size = shadow
		style.shadow_offset = Vector2(shadow, shadow)
	return style


## Convert a legacy pixel-design vector into a native 720p layout vector. The
## returned value is assigned directly to Controls; no parent Control or
## intermediate viewport is scaled.
static func native_vector(value: Vector2) -> Vector2:
	return (value * float(NATIVE_UNIT)).round()


static func native_scalar(value: float) -> float:
	return roundf(value * float(NATIVE_UNIT))


## Cached theme injecting the reference display face as the default. Body copy
## and numeric readouts opt into their explicit roles at construction sites.
static func ui_theme() -> Theme:
	if _theme == null:
		_theme = Theme.new()
		_theme.set_font("font", "Label", FONT_DISPLAY)
	return _theme


## Chunky letter-tracking via glyph spacing. Used sparingly on large caps and
## hero labels where the extra width is free.
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
