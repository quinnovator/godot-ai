class_name BaseballVisual
extends Node

## Simulation-facing host for the direct native-1440p CanvasItem ball presenter.
##
## The sim drives this node through the same public API as before; it now also
## keeps deterministic effect bookkeeping (flight effort, contact, release,
## landing, mound scuffs) that the pixel sprite reads. Flight stays owned by
## the deterministic sim path: the trail and effects only observe positions,
## they never influence them.

const PixelBallSprite = preload("res://presentation/pixel_ball_sprite.gd")
const Style = preload("res://presentation/pixel_art_style.gd")
const SLOT_COLORS := [
	Color("b88cff"), Color("79f28f"), Color("5de0d2"),
	Color("ffd94a"), Color("ff6b6b"),
]

# Mound scuffs persist for the half-inning, capped at five marks (bible §9.4).
const SCUFF_LIMIT := 5
# A batted ball "lands" when it drops from above the fall line to the settle
# line between two sim samples; the sprite answers with clay dust.
const LANDING_FALL_FROM := 0.45
const LANDING_SETTLE_BELOW := 0.25
# Contact strength inferred from the first post-contact sim steps, in world
# units per update (~90 mph exit velocity saturates it).
const CONTACT_SPEED_FLOOR := 0.12
const CONTACT_SPEED_SPAN := 0.28

var global_position := Vector3.ZERO
var _active := false
var _play_ball := false
var _trail_color := SLOT_COLORS[1]
var _trail_points: Array[Vector3] = []
var _spin_rpm := 0.0
var _spin_axis := 0.0
var _batting_view := false
var _release_pending := false
var _release_serial := 0
var _release_world := Vector3.ZERO
var _contact_serial := 0
var _contact_world := Vector3.ZERO
var _contact_strength := 0.0
var _contact_samples := 0
var _landing_serial := 0
var _landing_world := Vector3.ZERO
var _scuff_marks: Array[Vector3] = []
var _pixel_sprite: PixiballPixelBallSprite


func _ready() -> void:
	call_deferred("_attach_pixel_sprite")


func _attach_pixel_sprite() -> void:
	if is_instance_valid(_pixel_sprite):
		return
	var canvas_root := get_tree().get_first_node_in_group("pixiball_pixel_scene")
	if canvas_root == null:
		if is_inside_tree():
			get_tree().process_frame.connect(_attach_pixel_sprite, CONNECT_ONE_SHOT)
		return
	_pixel_sprite = PixelBallSprite.new()
	canvas_root.add_child(_pixel_sprite)
	_pixel_sprite.bind(self)
	_pixel_sprite.visible = _active


func _exit_tree() -> void:
	if is_instance_valid(_pixel_sprite):
		_pixel_sprite.queue_free()


func set_trail_slot(slot: int) -> void:
	_trail_color = SLOT_COLORS[clampi(slot, 0, SLOT_COLORS.size() - 1)]
	_refresh()


func use_pitch_ball() -> void:
	_play_ball = false
	_trail_points.clear()
	_refresh()


func use_play_ball() -> void:
	_play_ball = true
	_trail_points.clear()
	# This call happens exactly at bat-ball contact, so it anchors the 6-tick
	# contact burst (§9.3); strength refines over the first post-contact steps.
	_contact_serial += 1
	_contact_world = global_position
	_contact_strength = 0.0
	_contact_samples = 0
	_refresh()


func begin_pitch_motion(spin_rate_rpm: float, spin_axis_degrees: float, batting_view: bool) -> void:
	_spin_rpm = maxf(0.0, spin_rate_rpm)
	_spin_axis = spin_axis_degrees
	_trail_points.clear()
	_release_pending = true
	if batting_view != _batting_view:
		# The pitching side flipped, so the half-inning turned over and the
		# mound scuff history resets (§9.4).
		_batting_view = batting_view
		_scuff_marks.clear()


func set_visual_scale(multiplier: float) -> void:
	_play_ball = multiplier > 1.0
	_refresh()


func set_active(value: bool) -> void:
	_active = value
	if not value:
		_trail_points.clear()
	if is_instance_valid(_pixel_sprite):
		_pixel_sprite.visible = value
	_refresh()


func set_ball_position(value: Vector3, _delta := 0.0) -> void:
	if _active and not global_position.is_equal_approx(value):
		if _release_pending and not _play_ball:
			_release_pending = false
			_release_serial += 1
			_release_world = value
			_add_scuff(value)
		if _play_ball:
			if _contact_samples < 4:
				_contact_samples += 1
				var step_speed := (value - global_position).length()
				_contact_strength = maxf(
					_contact_strength,
					clampf((step_speed - CONTACT_SPEED_FLOOR) / CONTACT_SPEED_SPAN, 0.0, 1.0)
				)
			if global_position.y > LANDING_FALL_FROM and value.y <= LANDING_SETTLE_BELOW:
				_landing_serial += 1
				_landing_world = Vector3(value.x, 0.0, value.z)
		_trail_points.push_front(global_position)
		# Pitch flight keeps a longer stepped history so the plate corridor
		# trail can bend; live batted balls stay short (2) for readability.
		while _trail_points.size() > (2 if _play_ball else 10):
			_trail_points.pop_back()
	global_position = value
	_refresh()


func is_active() -> bool:
	return _active


func is_play_ball() -> bool:
	return _play_ball


func get_trail_world_points() -> Array:
	return _trail_points.duplicate()


func get_trail_color() -> Color:
	return _trail_color


## Trail length codes effort (§9.2): spin rate stands in for pitch effort, and
## observed contact strength stands in for batted-ball effort.
func get_flight_effort() -> float:
	if _play_ball:
		return maxf(_contact_strength, 0.34)
	return clampf((_spin_rpm - 1400.0) / 1200.0, 0.0, 1.0)


func get_contact_event() -> Dictionary:
	return {"serial": _contact_serial, "world": _contact_world, "strength": _contact_strength}


func get_release_event() -> Dictionary:
	return {"serial": _release_serial, "world": _release_world}


func get_landing_event() -> Dictionary:
	return {"serial": _landing_serial, "world": _landing_world}


func get_scuff_marks() -> Array:
	return _scuff_marks.duplicate()


func get_spin_contract() -> Dictionary:
	return {"rpm": _spin_rpm, "axis_degrees": _spin_axis}


func get_pixel_sprite() -> Node2D:
	return _pixel_sprite


func _add_scuff(release: Vector3) -> void:
	var jitter := Style.hash01(_release_serial * 7 + 3) - 0.5
	_scuff_marks.append(Vector3(release.x + jitter * 0.6, 0.0, release.z + absf(jitter) * 0.4))
	while _scuff_marks.size() > SCUFF_LIMIT:
		_scuff_marks.pop_front()


func _refresh() -> void:
	if is_instance_valid(_pixel_sprite):
		_pixel_sprite.queue_redraw()
