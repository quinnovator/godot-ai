class_name PixiballPixelOverlay
extends Control

## Sparse painted-signage shell marks: passive corner-tick L-marks at the safe
## frame (bible 10.3) and lit wharf-window cells over the harbor band (5.1
## sanctioned window accents). Every mark is an opaque authored 4px cluster;
## `intensity` steps through palette roles instead of alpha so the overlay
## never reads as a translucent engine layer.

const S := preload("res://ui/pixiball_style.gd")
const COMPOSITION_SIZE := Vector2(1280, 720)

const SAFE_FRAME := 24
const TICK_ARM := 12
const TICK_THICK := 4
const SHADOW_STEP := 4

var intensity := 1.0
var warm := false


func configure(amount := 1.0, warm_light := false) -> PixiballPixelOverlay:
	intensity = amount
	warm = warm_light
	return self


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = S.NATIVE_SIZE
	queue_redraw()


func _draw() -> void:
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * S.DENSITY_SCALE)
	_draw_corner_ticks()
	_draw_wharf_windows()


## Chalk registration ticks with a hard ink offset shadow. Passive marks stay
## chalk/steel/slate: lantern_gold corner ticks are reserved for focus (10.4).
func _draw_corner_ticks() -> void:
	var chalk := _stepped(S.CHALK, S.STEEL, S.SLATE)
	var far_x := COMPOSITION_SIZE.x - SAFE_FRAME
	var far_y := COMPOSITION_SIZE.y - SAFE_FRAME
	for origin in [
		Vector2(SAFE_FRAME, SAFE_FRAME), Vector2(far_x, SAFE_FRAME),
		Vector2(SAFE_FRAME, far_y), Vector2(far_x, far_y),
	]:
		var point: Vector2 = origin
		var left: bool = point.x < COMPOSITION_SIZE.x * 0.5
		var top: bool = point.y < COMPOSITION_SIZE.y * 0.5
		var horizontal: Vector2 = point + Vector2(0 if left else -TICK_ARM, 0 if top else -TICK_THICK)
		var vertical: Vector2 = point + Vector2(0 if left else -TICK_THICK, 0 if top else -TICK_ARM)
		var shadow := Vector2(SHADOW_STEP, SHADOW_STEP)
		draw_rect(Rect2(horizontal + shadow, Vector2(TICK_ARM, TICK_THICK)), S.INK, true)
		draw_rect(Rect2(vertical + shadow, Vector2(TICK_THICK, TICK_ARM)), S.INK, true)
		draw_rect(Rect2(horizontal, Vector2(TICK_ARM, TICK_THICK)), chalk, true)
		draw_rect(Rect2(vertical, Vector2(TICK_THICK, TICK_ARM)), chalk, true)


## Paired lit-window cells on the harbor band: warm lamplight kept below the
## screen's focal pool, cool foam glints otherwise.
func _draw_wharf_windows() -> void:
	var light := _stepped(S.WINDOW_GLOW, S.GOLD, S.CLAY) if warm else _stepped(S.FOAM, S.STEEL, S.SLATE)
	for anchor in [Vector2(72, 464), Vector2(172, 480), Vector2(1104, 472), Vector2(1204, 492)]:
		var point: Vector2 = anchor
		draw_rect(Rect2(point, Vector2(4, 8)), light, true)
		draw_rect(Rect2(point + Vector2(8, 0), Vector2(4, 8)), light, true)


## Fade is a palette-role step, never an alpha ramp.
func _stepped(bright: Color, mid: Color, dim: Color) -> Color:
	if intensity >= 0.95:
		return bright
	if intensity >= 0.6:
		return mid
	return dim
