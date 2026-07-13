class_name VoxelStadium
extends Node

## Compatibility facade for the native-720p ballpark canvas. Gameplay retains
## the established stadium API while every visual is drawn by one Node2D under
## the 4x design-grid transform in the shared `pixiball_pixel_scene` host.

const PixelStyle = preload("res://presentation/pixel_art_style.gd")
const PixelCanvas = preload("res://world/pixel_ballpark_canvas.gd")

const ART_SIZE := PixelStyle.ART_SIZE
const OUTPUT_SIZE := PixelStyle.OUTPUT_SIZE
const GRID_PIXEL_SIZE := PixelStyle.GRID_PIXEL_SIZE
const MOODS := PixelStyle.MOOD_PALETTES
const SIDE_SPECTATOR_SCALE := 0.86
const PLATE_SPECTATOR_SCALE := 0.70
const SPECTATOR_ROWS_PER_TIER := 4
const SPECTATOR_SEATS_PER_ROW := 42
const PLATE_SPECTATOR_ROWS := 5
const PLATE_SPECTATOR_SEATS_PER_ROW := 68

var _canvas: PixelBallparkCanvas
var _mood := "day"
var _view_mode := "intro"
var _field_focus := Vector3.ZERO
var _build_requested := false


func _ready() -> void:
	add_to_group(&"pixiball_pixel_world")
	build()


func build() -> void:
	if is_instance_valid(_canvas):
		return
	_build_requested = true
	_attach_canvas()
	if not is_instance_valid(_canvas) and is_inside_tree():
		call_deferred("_attach_canvas")


func set_mood(mood: String) -> void:
	_mood = PixelStyle.normalized_mood(mood)
	if is_instance_valid(_canvas):
		_canvas.set_mood(_mood)


func set_view_mode(mode: String) -> void:
	_view_mode = PixelStyle.normalized_view(mode)
	if is_instance_valid(_canvas):
		_canvas.set_view_mode(_view_mode)


func set_field_focus(value: Vector3) -> void:
	_field_focus = value
	if is_instance_valid(_canvas):
		_canvas.set_field_focus(value)


func react_to_play(outcome: String) -> void:
	_ensure_canvas()
	if is_instance_valid(_canvas):
		_canvas.react_to_play(outcome)


func flash_led(outcome: String) -> void:
	_ensure_canvas()
	if is_instance_valid(_canvas):
		_canvas.flash_led(outcome)


func swing_bell() -> void:
	_ensure_canvas()
	if is_instance_valid(_canvas):
		_canvas.swing_bell()


func burst(at: Vector3, color: Color, count: int) -> void:
	_ensure_canvas()
	if is_instance_valid(_canvas):
		_canvas.burst(at, color, count)


func crowd_state() -> Dictionary:
	if is_instance_valid(_canvas):
		return _canvas.crowd_state()
	return {
		"sections": {},
		"total_spectators": 0,
		"animated_batches": 0,
		"strip_count": 0,
		"reaction_timer": 0.0,
		"reaction_duration": 0.0,
		"reaction_strength": 0.0,
		"reaction_level": 0.0,
		"reaction_serial": 0,
		"motion_tick": 0,
		"motion_sample": Vector3.ZERO,
		"led_timer": 0.0,
		"bell_timer": 0.0,
		"mood": _mood,
		"view_mode": _view_mode,
		"art_size": ART_SIZE,
		"design_size": ART_SIZE,
		"output_size": OUTPUT_SIZE,
		"grid_pixel_size": GRID_PIXEL_SIZE,
	}


func get_canvas() -> Node2D:
	return _canvas


func _ensure_canvas() -> void:
	if not is_instance_valid(_canvas):
		build()


func _attach_canvas() -> void:
	if is_instance_valid(_canvas):
		return
	var host := _pixel_scene_host()
	if host == null:
		# Standalone/unit-test fallback.  In the production scene PixelScene is
		# present before this node becomes ready, so the canvas always takes the
		# grouped path above.
		host = self
	_canvas = PixelCanvas.new() as PixelBallparkCanvas
	_canvas.name = "PixelBallparkCanvas"
	host.add_child(_canvas)
	_canvas.set_mood(_mood)
	_canvas.set_view_mode(_view_mode)
	_canvas.set_field_focus(_field_focus)
	_canvas.build()


func _pixel_scene_host() -> Node:
	if not is_inside_tree():
		return null
	for candidate in get_tree().get_nodes_in_group(&"pixiball_pixel_scene"):
		if candidate is Node and candidate != self:
			return candidate as Node
	return null


func _exit_tree() -> void:
	# The production canvas is reparented beneath PixelScene, so explicitly own
	# its lifetime when this facade is removed or a session is torn down.
	if is_instance_valid(_canvas) and _canvas.get_parent() != self:
		_canvas.queue_free()
	_canvas = null
