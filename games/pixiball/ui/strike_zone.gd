class_name PixiballStrikeZone
extends Control

const S := preload("res://ui/pixiball_style.gd")

var aim := Vector2.ZERO
var pitch_marker := Vector2.ZERO
var show_pitch := false
var accent := S.TEAL
var active := true


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(210, 210)


func set_aim(value: Vector2) -> void:
	aim = value.clamp(Vector2(-1, -1), Vector2(1, 1))
	queue_redraw()


func set_pitch(value: Vector2, visible: bool) -> void:
	pitch_marker = value
	show_pitch = visible
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var zone := Rect2(center - Vector2(64, 78), Vector2(128, 156))
	draw_rect(zone, Color(S.SCOREBOARD, 0.18), true)
	draw_rect(zone, Color(S.CHALK, 0.72), false, 3.0)
	for i in [1, 2]:
		var vx := zone.position.x + zone.size.x * float(i) / 3.0
		var hy := zone.position.y + zone.size.y * float(i) / 3.0
		draw_line(Vector2(vx, zone.position.y), Vector2(vx, zone.end.y), Color(1, 1, 1, 0.18), 1.0)
		draw_line(Vector2(zone.position.x, hy), Vector2(zone.end.x, hy), Color(1, 1, 1, 0.18), 1.0)
	var reticle := center + Vector2(aim.x * 72.0, aim.y * 88.0)
	var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.006) * 0.08 if active else 1.0
	draw_arc(reticle, 16.0 * pulse, 0, TAU, 24, accent if active else S.SLATE, 3.0)
	draw_line(reticle - Vector2(24, 0), reticle - Vector2(8, 0), accent, 2.0)
	draw_line(reticle + Vector2(8, 0), reticle + Vector2(24, 0), accent, 2.0)
	draw_line(reticle - Vector2(0, 24), reticle - Vector2(0, 8), accent, 2.0)
	draw_line(reticle + Vector2(0, 8), reticle + Vector2(0, 24), accent, 2.0)
	if show_pitch:
		var marker := center + Vector2(pitch_marker.x * 72.0, pitch_marker.y * 88.0)
		draw_circle(marker, 8.0, S.STITCH)
		draw_arc(marker, 13.0, 0, TAU, 18, Color(S.GOLD, 0.85), 2.0)
	queue_redraw()

