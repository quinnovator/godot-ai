class_name PixiballStrikeZone
extends Control

const S := preload("res://ui/pixiball_style.gd")

var aim := Vector2.ZERO
var pitch_marker := Vector2.ZERO
var show_pitch := false
var accent := S.TEAL
var active := true
var lateral_screen_sign := 1.0

const AIM_LATERAL_FT := 1.35
const AIM_VERTICAL_FT := 1.55
const ZONE_HALF_WIDTH_FT := 17.0 / 24.0
const ZONE_HALF_HEIGHT_FT := 1.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2.ZERO


func set_aim(value: Vector2) -> void:
	aim = value.clamp(Vector2(-1, -1), Vector2(1, 1))
	queue_redraw()


func set_pitch(value: Vector2, visible: bool) -> void:
	pitch_marker = value
	show_pitch = visible
	queue_redraw()


func set_lateral_screen_sign(value: float) -> void:
	lateral_screen_sign = -1.0 if value < 0.0 else 1.0
	queue_redraw()


func _draw() -> void:
	if size.x <= 1.0 or size.y <= 1.0:
		return
	var frame_width := clampf(minf(size.x, size.y) * 0.018, 1.5, 4.0)
	var zone := Rect2(Vector2.ONE * frame_width * 0.5, size - Vector2.ONE * frame_width)
	var center := zone.get_center()
	draw_rect(zone, Color(S.SCOREBOARD, 0.18), true)
	draw_rect(zone, Color(S.CHALK, 0.78), false, frame_width)
	for i in [1, 2]:
		var vx := zone.position.x + zone.size.x * float(i) / 3.0
		var hy := zone.position.y + zone.size.y * float(i) / 3.0
		draw_line(Vector2(vx, zone.position.y), Vector2(vx, zone.end.y), Color(1, 1, 1, 0.2), 1.0)
		draw_line(Vector2(zone.position.x, hy), Vector2(zone.end.x, hy), Color(1, 1, 1, 0.2), 1.0)
	# Aim is simulation-normalized, so map it through the same feet contract as
	# gameplay. The command envelope intentionally extends beyond the zone.
	var aim_extent := Vector2(
		zone.size.x * 0.5 * AIM_LATERAL_FT / ZONE_HALF_WIDTH_FT,
		zone.size.y * 0.5 * AIM_VERTICAL_FT / ZONE_HALF_HEIGHT_FT
	)
	var reticle := center + Vector2(aim.x * lateral_screen_sign, aim.y) * aim_extent
	var reticle_radius := clampf(minf(size.x, size.y) * 0.11, 7.0, 24.0)
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.08 if active else 1.0
	var cross_inner := reticle_radius * 0.5
	var cross_outer := reticle_radius * 1.5
	draw_arc(reticle, reticle_radius * pulse, 0, TAU, 32, accent if active else S.SLATE, 3.0)
	draw_line(reticle - Vector2(cross_outer, 0), reticle - Vector2(cross_inner, 0), accent, 2.0)
	draw_line(reticle + Vector2(cross_inner, 0), reticle + Vector2(cross_outer, 0), accent, 2.0)
	draw_line(reticle - Vector2(0, cross_outer), reticle - Vector2(0, cross_inner), accent, 2.0)
	draw_line(reticle + Vector2(0, cross_inner), reticle + Vector2(0, cross_outer), accent, 2.0)
	if show_pitch:
		var marker := center + Vector2(pitch_marker.x * lateral_screen_sign, pitch_marker.y) * aim_extent
		var marker_radius := reticle_radius * 0.5
		draw_circle(marker, marker_radius, S.STITCH)
		draw_arc(marker, marker_radius * 1.6, 0, TAU, 24, Color(S.GOLD, 0.85), 2.0)
	queue_redraw()
