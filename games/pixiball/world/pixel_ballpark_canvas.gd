class_name PixelBallparkCanvas
extends Node2D

const Style = preload("res://presentation/pixel_art_style.gd")
const Landmarks = preload("res://world/view_landmarks.gd")
const AtmosphereStage = preload("res://world/stages/atmosphere.gd")
const MaterialDetailStage = preload("res://world/stages/material_detail.gd")
const SkylineStage = preload("res://world/stages/skyline.gd")
const PlayfieldStage = preload("res://world/stages/playfield.gd")
const StandsStage = preload("res://world/stages/stands.gd")
const ViewsStage = preload("res://world/stages/views.gd")

const ART_SIZE := Style.ART_SIZE
const DESIGN_SIZE := Style.DESIGN_SIZE
const OUTPUT_SIZE := Style.OUTPUT_SIZE
const GRID_PIXEL_SIZE := Style.GRID_PIXEL_SIZE
const CROWD_STEP := 1.0 / 12.0
const VIEW_CROWD_COUNTS := {
	"intro": 288,
	"pitching": 240,
	"batting": 192,
	"fielding": 320,
	"dugout": 128,
}
const CROWD_REACTIONS := {
	"ball": {"seconds": 0.55, "strength": 0.16, "led": "BALL"},
	"called_strike": {"seconds": 0.85, "strength": 0.32, "led": "STRIKE"},
	"swinging_strike": {"seconds": 0.95, "strength": 0.40, "led": "STRIKE"},
	"strikeout": {"seconds": 1.75, "strength": 0.82, "led": "K"},
	"walk": {"seconds": 1.15, "strength": 0.42, "led": "WALK"},
	"foul": {"seconds": 0.70, "strength": 0.24, "led": "FOUL"},
	"single": {"seconds": 1.35, "strength": 0.55, "led": "SINGLE"},
	"double": {"seconds": 1.80, "strength": 0.72, "led": "DOUBLE"},
	"triple": {"seconds": 2.25, "strength": 0.88, "led": "TRIPLE"},
	"home_run": {"seconds": 3.20, "strength": 1.00, "led": "HOMERUN", "bell": true},
	"ground_out": {"seconds": 1.00, "strength": 0.34, "led": "OUT"},
	"fly_out": {"seconds": 1.00, "strength": 0.34, "led": "OUT"},
	"fielders_choice": {"seconds": 1.05, "strength": 0.38, "led": "OUT"},
	"out": {"seconds": 1.00, "strength": 0.34, "led": "OUT"},
}

const CROWD_CLUMP_STAMPS := [
	{"body": [[0, 1, 4, 1]], "heads": [[1, 0], [3, 0]], "arms": [[0, -1], [2, -1]]},
	{"body": [[0, 1, 3, 1], [1, 2, 2, 1]], "heads": [[1, 0]], "arms": [[0, -1], [2, -1]]},
	{"body": [[0, 2, 4, 1]], "heads": [[0, 1], [2, 1]], "arms": [[1, 0], [3, 0]]},
	{"body": [[0, 2, 3, 1], [2, 1, 1, 1]], "heads": [[1, 1]], "flag": [3, 0], "arms": [[0, 0], [2, 0]]},
	{"body": [[0, 2, 3, 1], [1, 1, 1, 1]], "heads": [[1, 0]], "arms": [[0, -1], [2, -1]]},
	{"body": [[0, 2, 2, 1], [2, 1, 2, 1]], "heads": [[0, 1], [3, 0]], "arms": [[1, 0], [2, -1]]},
	{"body": [[0, 1, 4, 1]], "heads": [[0, 0], [2, 0]], "arms": [[1, -1], [3, -1]]},
	{"body": [[1, 2, 3, 1], [2, 1, 1, 1]], "heads": [[1, 1]], "arms": [[0, 0], [3, 0]]},
]
const CROWD_WARM_RATIO := {"day": 5, "golden": 3, "night": 10}
const WINDOW_DENSITY := {"day": 0.10, "golden": 0.45, "night": 0.90}
const BELL_DURATION := 5.0
const WAVE_SPEED := 3
const WAVE_BAND := 9
const CAP_TOSS_STRENGTH := 0.7
const BIG_PLAY_STRENGTH := 0.55

var mood := "day"
var view_mode := "intro"
var _field_focus := Vector3.ZERO

var anim_time := 0.0
var reaction_timer := 0.0
var reaction_duration := 0.0
var reaction_strength := 0.0
var reaction_serial := 0
var led_text := "PIXIBALL"
var led_timer := 0.0
var bell_timer := 0.0
var crowd_motion_tick := 0

var _crowd_accumulator := 0.0
var _crowd_motion_sample := Vector3.ZERO
var _burst_serial := 0
var _bursts: Array[Dictionary] = []

var atmosphere
var material_detail
var skyline
var playfield
var stands
var views


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = -100
	atmosphere = AtmosphereStage.new(self)
	material_detail = MaterialDetailStage.new(self)
	skyline = SkylineStage.new(self)
	playfield = PlayfieldStage.new(self)
	stands = StandsStage.new(self)
	views = ViewsStage.new(self)
	set_process(true)
	queue_redraw()


func build() -> void:
	queue_redraw()


func set_mood(next_mood: String) -> void:
	var normalized := Style.normalized_mood(next_mood)
	if mood == normalized:
		return
	mood = normalized
	queue_redraw()


func set_view_mode(next_mode: String) -> void:
	var normalized := Style.normalized_view(next_mode)
	if view_mode == normalized:
		return
	view_mode = normalized
	_sync_field_offset()
	queue_redraw()


func set_field_focus(value: Vector3) -> void:
	if _field_focus.is_equal_approx(value):
		return
	_field_focus = value
	_sync_field_offset()


func react_to_play(outcome: String) -> void:
	var normalized := outcome.strip_edges().to_lower().replace(" ", "_")
	var reaction: Dictionary = CROWD_REACTIONS.get(normalized, {})
	if reaction.is_empty():
		return
	reaction_duration = float(reaction.get("seconds", 0.8))
	reaction_timer = reaction_duration
	reaction_strength = clampf(float(reaction.get("strength", 0.3)), 0.0, 1.0)
	reaction_serial += 1
	flash_led(String(reaction.get("led", "PLAY")))
	if bool(reaction.get("bell", false)):
		swing_bell()
	queue_redraw()


func flash_led(message: String) -> void:
	led_text = message.strip_edges().to_upper().left(9)
	if led_text.is_empty():
		led_text = "PIXIBALL"
	led_timer = 1.5
	queue_redraw()


func swing_bell() -> void:
	bell_timer = BELL_DURATION
	queue_redraw()


func burst(at: Vector3, color: Color, count: int) -> void:
	var origin := _project_world(at)
	var limited := clampi(count, 0, 64)
	for index in range(limited):
		var seed := 104729 + _burst_serial * 8191 + index * 131
		var angle := Style.hash01(seed) * TAU
		var speed := lerpf(10.0, 31.0, Style.hash01(seed + 17))
		_bursts.append({
			"origin": origin,
			"velocity": Vector2(cos(angle), sin(angle) - 0.32) * speed,
			"age": 0.0,
			"duration": lerpf(0.34, 0.68, Style.hash01(seed + 31)),
			"size": 1 + int(Style.hash01(seed + 47) > 0.72),
			"color": color,
		})
	_burst_serial += 1
	queue_redraw()


func crowd_state() -> Dictionary:
	var count := int(VIEW_CROWD_COUNTS.get(view_mode, 0))
	return {
		"sections": {"PixelCrowd/%s" % view_mode: count},
		"total_spectators": count,
		"animated_batches": 1,
		"strip_count": 0,
		"reaction_timer": reaction_timer,
		"reaction_duration": reaction_duration,
		"reaction_strength": reaction_strength,
		"reaction_level": _reaction_level(),
		"reaction_serial": reaction_serial,
		"motion_tick": crowd_motion_tick,
		"motion_sample": _crowd_motion_sample,
		"led_timer": led_timer,
		"bell_timer": bell_timer,
		"mood": mood,
		"view_mode": view_mode,
		"art_size": DESIGN_SIZE,
		"design_size": DESIGN_SIZE,
		"output_size": OUTPUT_SIZE,
		"grid_pixel_size": GRID_PIXEL_SIZE,
	}


func _process(delta: float) -> void:
	var dt := maxf(delta, 0.0)
	anim_time += dt
	var redraw := false

	_crowd_accumulator += dt
	if _crowd_accumulator >= CROWD_STEP:
		var steps := maxi(1, int(floor(_crowd_accumulator / CROWD_STEP)))
		_crowd_accumulator -= float(steps) * CROWD_STEP
		crowd_motion_tick += steps
		var response := _reaction_level()
		_crowd_motion_sample = Vector3(
			roundf(sin(float(crowd_motion_tick) * 0.43) * response),
			roundf(maxf(0.0, sin(float(crowd_motion_tick) * 0.71)) * response * 2.0),
			0.0,
		)
		redraw = true

	if reaction_timer > 0.0:
		reaction_timer = maxf(0.0, reaction_timer - dt)
		if reaction_timer == 0.0:
			reaction_duration = 0.0
			reaction_strength = 0.0
		redraw = true
	if led_timer > 0.0:
		led_timer = maxf(0.0, led_timer - dt)
		redraw = true
	if bell_timer > 0.0:
		bell_timer = maxf(0.0, bell_timer - dt)
		redraw = true

	for index in range(_bursts.size() - 1, -1, -1):
		_bursts[index]["age"] = float(_bursts[index].age) + dt
		if float(_bursts[index].age) >= float(_bursts[index].duration):
			_bursts.remove_at(index)
		redraw = true

	if redraw:
		queue_redraw()


func _draw() -> void:
	if views == null:
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE * Style.DENSITY_SCALE)
	var palette := Style.palette(mood)
	Style.pixel_rect(self, Rect2(-32, -20, ART_SIZE.x + 64, ART_SIZE.y + 40), palette.ink)
	match view_mode:
		"pitching":
			views.draw_pitching(palette)
		"batting":
			views.draw_batting(palette)
		"fielding":
			views.draw_fielding(palette)
		"dugout":
			views.draw_dugout(palette)
		_:
			views.draw_intro(palette)
	material_detail.draw(palette)
	_draw_bursts()
	atmosphere.draw_vignette(palette)


func _draw_bursts() -> void:
	for particle in _bursts:
		var age := float(particle.age)
		var duration := float(particle.duration)
		var velocity: Vector2 = particle.velocity
		var at: Vector2 = particle.origin + velocity * age + Vector2(0.0, 24.0 * age * age)
		var size := int(particle.size)
		if age > duration * 0.55:
			size = 1
		Style.pixel_rect(self, Rect2(at.round(), Vector2.ONE * size), particle.color)


func _project_world(world: Vector3) -> Vector2:
	match view_mode:
		"pitching":
			return Vector2(151.0 + world.x * 3.2, 168.0 - (18.0 - world.z) * 0.72 - world.y * 5.0)
		"batting":
			return Vector2(160.0 - world.x * 3.2, 168.0 - (18.0 - world.z) * 1.25 - world.y * 4.0)
		"fielding":
			return Vector2(160.0 + world.x * 2.25, 166.0 - (18.0 - world.z) * 1.65 - world.y * 0.5)
		"dugout":
			return Vector2(160.0 + world.x * 2.0, 143.0 - world.y * 3.0 - (18.0 - world.z) * 0.18)
		_:
			return Vector2(160.0 + world.x * 2.0, 165.0 - (18.0 - world.z) * 0.82 - world.y * 2.8)


func _reaction_level() -> float:
	if reaction_timer <= 0.0 or reaction_duration <= 0.0:
		return 0.0
	var remaining := clampf(reaction_timer / reaction_duration, 0.0, 1.0)
	return reaction_strength * remaining * remaining


func _reaction_ticks() -> int:
	if reaction_timer <= 0.0 or reaction_duration <= 0.0:
		return 0
	return maxi(0, int(round((reaction_duration - reaction_timer) / CROWD_STEP)))


func _bell_ticks() -> int:
	if bell_timer <= 0.0:
		return 0
	return maxi(0, int(round((BELL_DURATION - bell_timer) / CROWD_STEP)))


func _celebrating() -> bool:
	return reaction_timer > 0.0 and bell_timer > 0.0


func _wave_front_count() -> int:
	if reaction_timer <= 0.0:
		return 0
	return clampi(1 + int(reaction_strength * 2.2), 1, 3)


func _wave_raised(x: int, left: int, width: int, fronts: int) -> bool:
	if fronts <= 0 or width <= 0:
		return false
	var head := posmod(_reaction_ticks() * WAVE_SPEED, width)
	for front in range(fronts):
		var front_x := posmod(head + int(float(width * front) / float(fronts)), width)
		if posmod(front_x - (x - left), width) < WAVE_BAND:
			return true
	return false


func _sync_field_offset() -> void:
	if view_mode != "fielding":
		position = Vector2.ZERO
		return
	position = Vector2(
		roundi(clampf(_field_focus.x * -0.35, -22.0, 22.0)),
		roundi(clampf((_field_focus.z + 4.0) * -0.18, -14.0, 14.0)),
	)


func _colored_polygon(points: Array[Vector2], color: Color) -> void:
	draw_colored_polygon(PackedVector2Array(points), color)
