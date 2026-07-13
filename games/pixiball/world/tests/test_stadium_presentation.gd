extends SceneTree

const Stadium = preload("res://world/voxel_stadium.gd")
const PixelCanvas = preload("res://world/pixel_ballpark_canvas.gd")
const Style = preload("res://presentation/pixel_art_style.gd")

const EXPECTED_VIEWS := ["intro", "pitching", "batting", "fielding", "dugout"]
const EXPECTED_CROWD_COUNTS := {
	"intro": 288,
	"pitching": 240,
	"batting": 192,
	"fielding": 320,
	"dugout": 128,
}

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var pixel_scene := Node2D.new()
	pixel_scene.name = "PixelScene"
	pixel_scene.scale = Vector2(4, 4)
	pixel_scene.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	pixel_scene.add_to_group(&"pixiball_pixel_scene")
	root.add_child(pixel_scene)

	var first = Stadium.new()
	first.name = "FirstStadium"
	root.add_child(first)
	var first_canvas := first.get_canvas() as PixelBallparkCanvas
	_check(first is Node and not first is Node2D, "stadium facade must be a plain Node")
	_check(first_canvas is Node2D, "stadium must create a native Node2D canvas")
	_check(is_instance_valid(first_canvas), "stadium did not build its pixel canvas on ready")
	if not is_instance_valid(first_canvas):
		_finish()
		return

	_check(first_canvas.get_parent() == pixel_scene, "canvas must attach beneath the pixiball_pixel_scene host")
	_check(first.is_in_group(&"pixiball_pixel_world"), "facade must register with the pixel camera world group")
	_check(not first_canvas.is_in_group(&"pixiball_pixel_scene"), "canvas must not impersonate the shared PixelScene host")
	_check(get_nodes_in_group(&"pixiball_pixel_scene").size() == 1, "test scene must retain exactly one pixel-scene host")
	_check(_direct_pixel_canvas_count(pixel_scene) == 1, "build must attach exactly one ballpark canvas")
	first.build()
	first.build()
	_check(_direct_pixel_canvas_count(pixel_scene) == 1, "build must remain idempotent")
	_check(not _has_3d_descendant(first), "facade subtree contains a forbidden 3D node")
	_check(not _has_3d_descendant(first_canvas), "pixel canvas contains a forbidden 3D descendant")
	_check(first_canvas.get_child_count() == 0, "ballpark must draw on one canvas rather than allocating scene geometry")

	_check(Stadium.ART_SIZE == Vector2i(320, 180), "facade composition vocabulary must remain exactly 320x180 cells")
	_check(PixelCanvas.ART_SIZE == Vector2i(320, 180), "canvas composition vocabulary must remain exactly 320x180 cells")
	_check(Style.DESIGN_SIZE == Vector2i(640, 360), "shared pixel style must expose the 640x360 dense design grid")
	_check(Style.OUTPUT_SIZE == Vector2i(2560, 1440), "shared pixel style output must be native 2560x1440")
	_check(Style.DENSITY_SCALE == 2, "shared pixel style must retain the 2x linear density transform")
	_check(Style.GRID_PIXEL_SIZE == 4, "shared pixel style must map each design cell to 4px")
	_check(pixel_scene.scale == Vector2(4, 4), "world host must apply the exact direct-render 4x CanvasItem transform")
	_check(pixel_scene.texture_filter == CanvasItem.TEXTURE_FILTER_NEAREST, "world host must prohibit filtered sampling")
	_check(Style.VIEW_MODES == EXPECTED_VIEWS, "pixel style must expose the five authored broadcast views")
	for api in ["build", "set_mood", "set_view_mode", "set_field_focus", "react_to_play", "crowd_state", "flash_led", "swing_bell", "burst"]:
		_check(first.has_method(api), "stadium facade lost public API %s" % api)

	# A second facade must produce the same deterministic state while attaching
	# another canvas to the one shared host, never nesting under the first canvas.
	var second = Stadium.new()
	second.name = "SecondStadium"
	root.add_child(second)
	var second_canvas := second.get_canvas() as PixelBallparkCanvas
	_check(is_instance_valid(second_canvas), "second deterministic canvas did not build")
	if not is_instance_valid(second_canvas):
		_finish()
		return
	_check(second_canvas.get_parent() == pixel_scene, "second canvas attached to the wrong host")
	_check(_direct_pixel_canvas_count(pixel_scene) == 2, "each facade must own exactly one direct canvas")
	first_canvas.set_process(false)
	second_canvas.set_process(false)

	for mode in EXPECTED_VIEWS:
		first.set_view_mode(mode)
		second.set_view_mode(mode)
		var first_state: Dictionary = first.crowd_state()
		var second_state: Dictionary = second.crowd_state()
		var expected_count := int(EXPECTED_CROWD_COUNTS[mode])
		_check(String(first_state.view_mode) == mode, "%s view mode was not retained" % mode)
		_check(first_state.design_size == Vector2i(640, 360), "%s state lost the authored dense design-grid size" % mode)
		_check(first_state.output_size == Vector2i(2560, 1440), "%s state lost the native framebuffer size" % mode)
		_check(int(first_state.grid_pixel_size) == 4, "%s state lost the 4px authoring-grid scale" % mode)
		_check(int(first_state.total_spectators) == expected_count, "%s crowd count changed: %s" % [mode, first_state.total_spectators])
		_check(int(second_state.total_spectators) == expected_count, "%s second crowd count changed" % mode)
		_check(first_state.sections == second_state.sections, "%s crowd section layout is nondeterministic" % mode)
		_check(int((first_state.sections as Dictionary).values()[0]) == expected_count, "%s section count does not match total" % mode)

	_check(is_equal_approx(PixelCanvas.CROWD_STEP, 1.0 / 12.0), "crowd cadence must be fixed at 12 fps")
	first.react_to_play("single")
	second.react_to_play("single")
	var first_tick := int(first.crowd_state().motion_tick)
	var second_tick := int(second.crowd_state().motion_tick)
	first_canvas._process(PixelCanvas.CROWD_STEP * 0.99)
	second_canvas._process(PixelCanvas.CROWD_STEP * 0.99)
	_check(int(first.crowd_state().motion_tick) == first_tick, "crowd advanced before one complete 12 fps step")
	_check(int(second.crowd_state().motion_tick) == second_tick, "second crowd advanced before one complete step")
	first_canvas._process(PixelCanvas.CROWD_STEP * 0.02)
	second_canvas._process(PixelCanvas.CROWD_STEP * 0.02)
	var stepped_first: Dictionary = first.crowd_state()
	var stepped_second: Dictionary = second.crowd_state()
	_check(int(stepped_first.motion_tick) == first_tick + 1, "crowd did not advance exactly once at 12 fps")
	_check(int(stepped_second.motion_tick) == second_tick + 1, "second crowd cadence diverged")
	_check(stepped_first.motion_sample == stepped_second.motion_sample, "crowd motion samples are nondeterministic")
	_check(stepped_first.motion_sample != Vector3.ZERO, "excited crowd must produce a quantized motion sample")
	first_canvas._process(PixelCanvas.CROWD_STEP * 2.4)
	second_canvas._process(PixelCanvas.CROWD_STEP * 2.4)
	_check(int(first.crowd_state().motion_tick) == first_tick + 3, "multi-step crowd update did not preserve fixed cadence")
	_check(first.crowd_state().motion_sample == second.crowd_state().motion_sample, "multi-step crowd motion lost determinism")

	# Semantic reactions drive only stateful pixel animation. Home runs exercise
	# all three independent envelopes: crowd, LED board, and bell.
	var serial_before := int(first.crowd_state().reaction_serial)
	first.react_to_play("home_run")
	var excited: Dictionary = first.crowd_state()
	_check(int(excited.reaction_serial) == serial_before + 1, "reaction serial did not advance once")
	_check(is_equal_approx(float(excited.reaction_duration), 3.2), "home-run crowd duration changed")
	_check(is_equal_approx(float(excited.reaction_strength), 1.0), "home-run crowd strength changed")
	_check(float(excited.reaction_timer) > 0.0 and float(excited.reaction_level) > 0.0, "crowd reaction did not start")
	_check(float(excited.led_timer) > 0.0, "home run did not start the LED envelope")
	_check(float(excited.bell_timer) > 0.0, "home run did not start the bell envelope")
	first_canvas._process(0.5)
	var decaying: Dictionary = first.crowd_state()
	_check(float(decaying.reaction_timer) < float(excited.reaction_timer), "crowd reaction did not decay")
	_check(float(decaying.led_timer) < float(excited.led_timer), "LED timer did not decay")
	_check(float(decaying.bell_timer) < float(excited.bell_timer), "bell timer did not decay")
	first_canvas._process(6.0)
	var settled: Dictionary = first.crowd_state()
	_check(is_zero_approx(float(settled.reaction_timer)) and is_zero_approx(float(settled.reaction_level)), "crowd reaction did not settle")
	_check(is_zero_approx(float(settled.led_timer)), "LED envelope did not settle")
	_check(is_zero_approx(float(settled.bell_timer)), "bell envelope did not settle")
	first.flash_led("STRIKE")
	_check(float(first.crowd_state().led_timer) > 0.0, "direct LED flash did not start")
	first_canvas._process(2.0)
	_check(is_zero_approx(float(first.crowd_state().led_timer)), "direct LED flash did not expire")
	first.swing_bell()
	_check(float(first.crowd_state().bell_timer) > 0.0, "direct bell swing did not start")
	first_canvas._process(5.1)
	_check(is_zero_approx(float(first.crowd_state().bell_timer)), "direct bell swing did not expire")

	first.set_view_mode("fielding")
	first.set_field_focus(Vector3(40.0, 0.0, -40.0))
	_check(first_canvas.position == Vector2(-14, 6), "field focus did not apply the authored quantized follow offset: %s" % first_canvas.position)
	first.set_field_focus(Vector3(1000.0, 0.0, 1000.0))
	_check(first_canvas.position == Vector2(-22, -14), "field focus did not clamp to the pixel-stage limits")
	first.set_view_mode("pitching")
	_check(first_canvas.position == Vector2.ZERO, "leaving fielding mode did not clear the follow offset")

	var particle_count_before := (first_canvas.get("_bursts") as Array).size()
	first.burst(Vector3(0.0, 2.0, 18.0), Color("ffd166"), 7)
	var particles: Array = first_canvas.get("_bursts")
	_check(particles.size() == particle_count_before + 7, "pixel burst did not create the requested deterministic clusters")
	_check(first_canvas.get_child_count() == 0, "burst must remain canvas data rather than allocating child nodes")
	first_canvas._process(1.0)
	_check((first_canvas.get("_bursts") as Array).is_empty(), "expired burst pixels were not reclaimed")

	_check(Stadium.MOODS.keys().size() == 3, "stadium must expose exactly three mood palettes")
	var role_names: Array = (Stadium.MOODS.day as Dictionary).keys()
	_check(role_names.size() == Style.ENVIRONMENT_ROLE_NAMES.size(), "Lantern Wharf role table size drifted: got %d" % role_names.size())
	for role in Style.ENVIRONMENT_ROLE_NAMES:
		_check(role_names.has(role), "Lantern Wharf role %s is missing from the palette API" % role)
	for mood in ["day", "golden", "night"]:
		_check(Stadium.MOODS.has(mood), "missing flat %s palette" % mood)
		var palette: Dictionary = Stadium.MOODS[mood]
		_check(palette.keys().size() == role_names.size(), "%s palette role count diverged from day" % mood)
		for key in role_names:
			_check(palette.get(key) is Color, "%s palette entry %s is not a flat color" % [mood, key])
			if palette.get(key) is Color:
				_check(is_equal_approx((palette[key] as Color).a, 1.0), "%s/%s must remain opaque" % [mood, key])
		_check(Style.veil_role("mist_veil", mood).a < 1.0, "%s mist veil must be translucent" % mood)
	first.set_mood("day")
	var day_state: Dictionary = first.crowd_state()
	first.set_mood("golden")
	var golden_state: Dictionary = first.crowd_state()
	first.set_mood("night")
	var night_state: Dictionary = first.crowd_state()
	_check(day_state.mood == "day" and golden_state.mood == "golden" and night_state.mood == "night", "facade did not retain all mood selections")
	_check(Stadium.MOODS.day.sky_high != Stadium.MOODS.golden.sky_high and Stadium.MOODS.golden.sky_high != Stadium.MOODS.night.sky_high, "mood skies are not visually distinct")
	_check(Stadium.MOODS.day.turf_main != Stadium.MOODS.golden.turf_main and Stadium.MOODS.golden.turf_main != Stadium.MOODS.night.turf_main, "mood fields are not visually distinct")
	_check(Style.value_step(Stadium.MOODS.day.chalk_line) > Style.value_step(Stadium.MOODS.day.turf_main), "chalk must sit above turf on the value ladder")
	_check(Style.value_steps_between(Stadium.MOODS.night.chalk_line, Stadium.MOODS.night.turf_main) >= 4, "night chalk must keep >=4 value steps of field contrast")
	_check(Style.haze_veil(Stadium.MOODS.day.town_far, "day", Style.HAZE_FAR).a == 1.0, "haze pre-blend must author opaque colors")

	var first_canvas_ref: WeakRef = weakref(first_canvas)
	var second_canvas_ref: WeakRef = weakref(second_canvas)
	first.queue_free()
	second.queue_free()
	await process_frame
	await process_frame
	_check(first_canvas_ref.get_ref() == null and second_canvas_ref.get_ref() == null, "reparented canvases outlived their facade owners")
	_check(_direct_pixel_canvas_count(pixel_scene) == 0, "pixel scene retained orphaned ballpark canvases")
	pixel_scene.queue_free()
	_finish()


func _direct_pixel_canvas_count(parent: Node) -> int:
	var count := 0
	for child in parent.get_children():
		if child is PixelBallparkCanvas:
			count += 1
	return count


func _has_3d_descendant(node: Node) -> bool:
	if node is Node3D:
		return true
	for child in node.get_children():
		if _has_3d_descendant(child):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PIXIBALL_STADIUM_PRESENTATION_OK native_canvas=2560x1440 design_grid=640x360 density=2x cell=4px views=5 crowd=12fps no_3d=verified")
		quit(0)
		return
	for failure in _failures:
		push_error("PIXIBALL_STADIUM_PRESENTATION: %s" % failure)
	quit(1)
