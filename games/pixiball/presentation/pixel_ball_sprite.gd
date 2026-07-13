class_name PixiballPixelBallSprite
extends Node2D

## Drawn with the 320x180 composition vocabulary, expanded onto the 640x360
## dense grid beneath PixelScene's exact 4x transform. Each dense primitive
## becomes a crisp 4x4 block in the native 1440p root; no ball texture or
## low-resolution viewport is involved.
##
## Lantern Wharf effects language (art bible §9.1–9.4): LOD ball with a spin
## tick and an always-rendered ground shadow, an effort-coded chain of opaque
## afterimage ghosts bent along the deterministic flight path, the 6-tick
## contact burst, landing dust, the mound rosin puff, persistent mound scuffs,
## and the night high-ball halo. Every mark is an opaque authored cluster on
## whole cells; "fade" steps through authored colors, never alpha.

const Style := preload("res://presentation/pixel_art_style.gd")

# Identity roles (bible §3.1), mood-invariant. Local until the pass-01 palette
# rename lands the shared identity table.
const BALL_WHITE := Color("f8f4e6")
const STITCH_RED := Color("d94a3d")
const INK := Color("0e1220")
const LANTERN_GOLD := Color("ffc65a")
const CHALK_PAPER := Color("efe9d4")

# Effects are tick-quantized (§11.8) so any paused frame is a legal still.
const TICKS_PER_SECOND := 10.0
# ParkGeometry fence posts top out at 10.5 ft x VERTICAL_WORLD_PER_FOOT 0.3048;
# the night halo only lights above the wall top (§9.1).
const WALL_TOP_WORLD := 10.5 * 0.3048
# Design-grid horizon rows per view (§6): ghosts above read against sky/sea,
# ghosts below read against turf, so the trail pre-mixes toward that band.
const HORIZON_ROWS := {"pitching": 46, "batting": 42, "fielding": 60, "intro": 58, "dugout": 40}
const TRAIL_SPACING := [2, 5, 8, 12]
const TRAIL_SPACING_FAST := [1, 3, 5, 8]
const FAST_TRAIL_CELLS_PER_FRAME := 3.0
# Pitch-view trail keeps more history so the plate lane reads as a bent path.
const RAY_DIRS := [Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1)]
# Three authored clay puffs per landing (§9.4): base seat, hop direction, and
# the 2–3 cell cluster shape.
const DUST_PUFFS := [
	{"base": Vector2i(-3, 0), "out": Vector2i(-1, -1), "cells": [Vector2i(0, 0), Vector2i(1, 0)]},
	{"base": Vector2i(-1, -1), "out": Vector2i(0, -1), "cells": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, -1)]},
	{"base": Vector2i(2, 0), "out": Vector2i(1, -1), "cells": [Vector2i(0, 0), Vector2i(1, 0)]},
]

var host: Node
var projector: Node

var _time := 0.0
var _seen_contact := 0
var _seen_release := 0
var _seen_landing := 0
var _burst := {}
var _rosin := {}
var _dust := {}


func bind(ball_host: Node) -> void:
	host = ball_host
	name = "BaseballPixels"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_as_relative = false
	z_index = 500
	set_process(true)


func _process(delta: float) -> void:
	_time += delta
	visible = is_instance_valid(host) and bool(host.is_active())
	if not visible:
		return
	if not is_instance_valid(projector):
		projector = get_tree().get_first_node_in_group("pixiball_pixel_projector")
	_poll_events()
	queue_redraw()


func _poll_events() -> void:
	var tick := _tick()
	var contact: Dictionary = host.get_contact_event()
	if int(contact.get("serial", 0)) != _seen_contact:
		_seen_contact = int(contact.get("serial", 0))
		_burst = {"tick": tick, "world": contact.get("world", Vector3.ZERO)}
	var release: Dictionary = host.get_release_event()
	if int(release.get("serial", 0)) != _seen_release:
		_seen_release = int(release.get("serial", 0))
		_rosin = {"tick": tick, "world": release.get("world", Vector3.ZERO)}
	var landing: Dictionary = host.get_landing_event()
	if int(landing.get("serial", 0)) != _seen_landing:
		_seen_landing = int(landing.get("serial", 0))
		_dust = {"tick": tick, "world": landing.get("world", Vector3.ZERO)}


func _draw() -> void:
	if not is_instance_valid(host) or not is_instance_valid(projector):
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * Style.DENSITY_SCALE)
	var mode := String(projector.get("mode"))
	var mood := _world_mood()
	var palette: Dictionary = Style.palette(mood)
	var tick := _tick()
	var strength := float(host.get_contact_event().get("strength", 0.0))
	var burst_age := -1
	if not _burst.is_empty():
		burst_age = tick - int(_burst["tick"])
	_draw_scuffs(palette)
	_draw_dust(palette, tick)
	_draw_rosin(palette, tick)
	_draw_trail(palette, mode)
	_draw_ball(palette, mood, mode, tick, burst_age == 0 and strength > 0.75)
	_draw_burst(palette, burst_age, strength)


## §9.1 — Pitching/batting: 3x3 ball_white core with ink shade and stitch tick.
## Diamond: 1-cell ball_white. Ground shadow always separates with height;
## night adds a 1-ring lamp_glow halo above wall height.
func _draw_ball(palette: Dictionary, mood: String, mode: String, tick: int, flash: bool) -> void:
	var world: Vector3 = host.global_position
	var pitch_flight := not bool(host.is_play_ball()) and mode in ["pitching", "batting"]
	var screen: Vector2 = _project_ball(world, pitch_flight)
	var ground: Vector2 = _project_composition(Vector3(world.x, 0.08, world.z))
	var x := roundi(screen.x)
	var y := roundi(screen.y)
	var battery := mode in ["pitching", "batting", "dugout"]
	var halo := mood == "night" and world.y > WALL_TOP_WORLD
	if battery:
		# A pitch is airborne for its entire battery-view life; a field shadow
		# would detach from the enlarged zone mapping and imply a ground ball.
		if not pitch_flight:
			_cell(roundi(ground.x) - 1, roundi(ground.y), 3, 1, INK)
		if halo:
			_cell(x - 2, y - 2, 4, 1, palette.lamp_glow)
			_cell(x - 2, y + 2, 4, 1, palette.lamp_glow)
			_cell(x - 2, y - 1, 1, 3, palette.lamp_glow)
			_cell(x + 2, y - 1, 1, 3, palette.lamp_glow)
		_cell(x - 1, y - 1, 3, 3, BALL_WHITE)
		if flash:
			return
		_dense_cell(x, y + 1.5, 1.0, 0.5, INK)
		_dense_cell(x - 1 if posmod(tick, 4) < 2 else x + 1.5, y - 1, 0.5, 0.5, STITCH_RED)
	else:
		_cell(roundi(ground.x), roundi(ground.y), 1, 1, INK)
		if halo:
			_cell(x, y - 1, 1, 1, palette.lamp_glow)
			_cell(x, y + 1, 1, 1, palette.lamp_glow)
			_cell(x - 1, y, 1, 1, palette.lamp_glow)
			_cell(x + 1, y, 1, 1, palette.lamp_glow)
		_cell(x, y, 1, 1, BALL_WHITE)


## §9.2 — Up to four opaque afterimage clusters behind the flight path. Effort
## codes ghost count; fast flight tightens spacing. Pitching mode uses 2x2
## clusters so the plate corridor trail survives mow arcs and clay. The chain
## walks the projected polyline so breaking balls bend it — no continuous lines.
func _draw_trail(palette: Dictionary, mode: String) -> void:
	var points: Array = host.get_trail_world_points()
	if points.is_empty():
		return
	var path: Array[Vector2] = []
	var pitch_flight := not bool(host.is_play_ball()) and mode in ["pitching", "batting"]
	path.append(_project_ball(host.global_position, pitch_flight))
	for point in points:
		if point is Vector3:
			path.append(_project_ball(point, pitch_flight))
	if path.size() < 2:
		return
	var effort := float(host.get_flight_effort())
	var ghost_count := 2
	if effort >= 0.67:
		ghost_count = 4
	elif effort >= 0.34:
		ghost_count = 3
	var speed := path[0].distance_to(path[1])
	var spacings: Array = TRAIL_SPACING_FAST if speed >= FAST_TRAIL_CELLS_PER_FRAME else TRAIL_SPACING
	var ball_cell := Vector2i(roundi(path[0].x), roundi(path[0].y))
	var pitch_view := mode == "pitching"
	var trail_tint: Color = host.get_trail_color() if host.has_method("get_trail_color") else BALL_WHITE
	for ghost in range(mini(ghost_count, spacings.size())):
		var at := _point_along(path, float(spacings[ghost]))
		var cell := Vector2i(roundi(at.x), roundi(at.y))
		if cell == ball_cell:
			continue
		var fill := _ghost_color(palette, mode, cell.y, ghost)
		if pitch_view and ghost == 0:
			# Nearest ghost carries a pulse of the pitch-slot color so the lane
			# reads as *this* pitch, not a generic chalk dash.
			fill = fill.lerp(trail_tint, 0.45)
			fill.a = 1.0
		if pitch_view and ghost <= 1:
			_cell(cell.x, cell.y, 2, 2, fill)
		else:
			_cell(cell.x, cell.y, 1, 1, fill)


## §9.3 — 6-tick contact starburst: ticks 1–2 a lantern_gold diamond, ticks
## 3–4 four 2-cell chalk rays, ticks 5–6 ray tips stepped toward the field.
## Perfect contact lengthens the rays (plus the 1-tick ball flash handled in
## _draw_ball); weak contact drops the ray phase. Never a screen flash.
func _draw_burst(palette: Dictionary, age: int, strength: float) -> void:
	if _burst.is_empty() or age < 0:
		return
	if age >= 6:
		_burst = {}
		return
	var screen: Vector2 = _project_composition(_burst["world"])
	var x := roundi(screen.x)
	var y := roundi(screen.y)
	if age <= 1:
		_cell(x, y, 1, 1, LANTERN_GOLD)
		_cell(x - 1, y, 1, 1, LANTERN_GOLD)
		_cell(x + 1, y, 1, 1, LANTERN_GOLD)
		_cell(x, y - 1, 1, 1, LANTERN_GOLD)
		_cell(x, y + 1, 1, 1, LANTERN_GOLD)
		return
	if strength < 0.3:
		_burst = {}
		return
	var ray_reach := 4 if strength > 0.75 else 3
	if age <= 3:
		for dir in RAY_DIRS:
			for step in range(2, ray_reach + 1):
				_cell(x + dir.x * step, y + dir.y * step, 1, 1, CHALK_PAPER)
	else:
		for dir in RAY_DIRS:
			_cell(x + dir.x * ray_reach, y + dir.y * ray_reach, 1, 1, palette.clay_lit)


## §9.4 — Landing dust: three clay puffs hop one cell up-and-out over four
## ticks, then step to the turf shadow color and vanish.
func _draw_dust(palette: Dictionary, tick: int) -> void:
	if _dust.is_empty():
		return
	var age := tick - int(_dust["tick"])
	if age < 0:
		return
	if age >= 5:
		_dust = {}
		return
	var world: Vector3 = _dust["world"]
	var screen: Vector2 = _project_composition(world)
	var anchor := Vector2i(roundi(screen.x), roundi(screen.y))
	for puff_value in DUST_PUFFS:
		var puff: Dictionary = puff_value
		var origin: Vector2i = anchor + puff["base"]
		if age >= 2:
			origin += puff["out"]
		if age >= 4:
			_cell(origin.x, origin.y, 1, 1, palette.turf_shade)
			continue
		var cells: Array = puff["cells"]
		for cell_index in range(cells.size()):
			var offset: Vector2i = cells[cell_index]
			var color: Color = palette.clay_lit if age <= 1 and cell_index == 0 else palette.clay_main
			_cell(origin.x + offset.x, origin.y + offset.y, 1, 1, color)


## §9.4 — Release rosin: a single 2-cell chalk puff at the release point for
## three ticks, plus the persistent mound scuff marks (host caps them at 5).
func _draw_rosin(palette: Dictionary, tick: int) -> void:
	if _rosin.is_empty():
		return
	var age := tick - int(_rosin["tick"])
	if age < 0:
		return
	if age >= 3:
		_rosin = {}
		return
	var screen: Vector2 = _project_composition(_rosin["world"])
	_cell(roundi(screen.x), roundi(screen.y), 1, 1, palette.chalk_line)
	if age <= 1:
		_cell(roundi(screen.x) + 1, roundi(screen.y) - 1, 1, 1, palette.chalk_line)


func _draw_scuffs(palette: Dictionary) -> void:
	var marks: Array = host.get_scuff_marks()
	for index in range(marks.size()):
		var mark: Variant = marks[index]
		if not mark is Vector3:
			continue
		var screen: Vector2 = _project_composition(mark)
		var x := roundi(screen.x)
		var y := roundi(screen.y)
		_cell(x, y, 1, 1, palette.clay_shade)
		if Style.hash01(index * 13 + 5) > 0.5:
			_cell(x + 1, y, 1, 1, palette.clay_shade)


## Ghost fill pre-mixed toward the band it flies over: sea-glint family above
## the view's horizon row, turf-lit family over grass — brightest step nearest
## the ball, stepping down toward the background (§9.2).
func _ghost_color(palette: Dictionary, mode: String, ghost_y: int, ghost: int) -> Color:
	if ghost_y < int(HORIZON_ROWS.get(mode, 58)):
		var sky: Array = [palette.sea_glint, palette.sea_glint, palette.sea_near]
		return sky[clampi(ghost, 0, 2)]
	return Style.shift_value(palette.turf_lit, 2 - clampi(ghost, 0, 2))


func _project_ball(world: Vector3, pitch_flight: bool) -> Vector2:
	if pitch_flight and projector.has_method("project_pitch_world"):
		return (projector.call("project_pitch_world", world) as Vector2) / Style.DENSITY_SCALE
	return _project_composition(world)


func _project_composition(world: Vector3) -> Vector2:
	return (projector.call("project_world", world) as Vector2) / Style.DENSITY_SCALE


## Arc-length walk along the projected trail polyline; short histories
## extrapolate along the final segment so early flight still shows the full
## effort-coded chain.
func _point_along(path: Array[Vector2], distance: float) -> Vector2:
	var remaining := distance
	for index in range(path.size() - 1):
		var segment := path[index].distance_to(path[index + 1])
		if segment <= 0.001:
			continue
		if remaining <= segment:
			return path[index].lerp(path[index + 1], remaining / segment)
		remaining -= segment
	var tail := path[path.size() - 1]
	var tail_dir := tail - path[path.size() - 2]
	if tail_dir.length() > 0.001:
		return tail + tail_dir.normalized() * remaining
	return tail


func _world_mood() -> String:
	if not is_inside_tree():
		return "day"
	for world in get_tree().get_nodes_in_group("pixiball_pixel_world"):
		var direct: Variant = world.get("mood")
		if direct is String:
			return Style.normalized_mood(direct)
		var facade: Variant = world.get("_mood")
		if facade is String:
			return Style.normalized_mood(facade)
	return "day"


func _tick() -> int:
	return int(floor(_time * TICKS_PER_SECOND))


func _cell(x: int, y: int, w: int, h: int, color: Color) -> void:
	draw_rect(Rect2(x, y, w, h), color, true)


func _dense_cell(x: float, y: float, w: float, h: float, color: Color) -> void:
	# Half-composition cells are the new 640x360 design-grid primitive. Ball
	# seams and shading use them so the ball gains detail at the same screen size.
	draw_rect(Rect2(x, y, maxf(0.5, w), maxf(0.5, h)), color, true)
