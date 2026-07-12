class_name VoxelStadium
extends Node3D

const C = preload("res://gameplay/game_constants.gd")
const ParkGeometry = preload("res://core/fielding/park_geometry.gd")
const PIXEL_GRASS_SHADER = preload("res://world/shaders/pixel_grass.gdshader")

# Crowd sprite scale contract: a crowd texture is tiled so one on-screen fan is
# roughly life-size (~2.5 ft) no matter how large the strip quad is. One texture
# tile is ~17 fans across (measured) spanning CROWD_TILE_WORLD world units, so at
# 6.5 each fan is ~0.38 world ≈ 2.5 ft; CROWD_ROW_WORLD is one seated row ≈ 2.7 ft.
# _add_crowd_strip derives uv1_scale from the quad size against these.
const CROWD_TILE_WORLD := 6.5
const CROWD_ROW_WORLD := 0.82

# Side-bowl spectators are real low-poly geometry rather than edge-on sprite
# cards. All pieces are batched by mesh, then colored and posed per instance.
const SPECTATOR_ROWS_PER_TIER := 4
const SPECTATOR_SEATS_PER_ROW := 42
const PLATE_SPECTATOR_ROWS := 5
const PLATE_SPECTATOR_SEATS_PER_ROW := 68
const PLATE_SPECTATOR_SCALE := 0.80
const CROWD_MOTION_STEP := 1.0 / 12.0
const SPECTATOR_SHIRTS := [
	Color("ef665b"), Color("41b8a6"), Color("f2bd4f"), Color("4f75b8"),
	Color("f3eee0"), Color("6c8d55"), Color("c65c83"), Color("536273"),
]
const SPECTATOR_SKINS := [
	Color("f0c29a"), Color("dda06b"), Color("bd7747"),
	Color("955735"), Color("704027"), Color("4b2a20"),
]
const SPECTATOR_HAIR := [
	Color("17191c"), Color("30231e"), Color("4a3023"),
	Color("75482d"), Color("b1793f"), Color("8d8a82"),
]

# Presentation-only responses. Gameplay sends a semantic outcome and the
# stadium owns its crowd/LED/bell choreography; none of this state is read by
# the deterministic simulation.
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

## Single auditable table for every mood-driven value: environment, sun, fog,
## the pixel-grass shader palette, lamp emission, and local light energies.
const MOODS := {
	"day": {
		"background": Color("4f88ad"),
		"ambient_color": Color("c2d6df"),
		"ambient_energy": 0.42,
		"sun_color": Color("fff0cf"),
		"sun_energy": 0.82,
		"fog_color": Color("aec2d4"),
		"fog_energy": 0.14,
		"fog_density": 0.0011,
		"grass_a": Color("4f914a"),
		"grass_b": Color("3f7f3d"),
		"grass_far": Color("315f3b"),
		"lamp_color": Color("fff3c0"),
		"lamp_energy": 0.06,
		"spot_energy": 0.0,
		"fill_energy": 0.0,
		"wash_energy": 0.28,
		"sun_rotation": Vector3(-58.0, -22.0, 0.0),
		"sky_top": Color("2f6ea8"),
		"sky_horizon": Color("b8d6ea"),
		"ground_horizon": Color("74909f"),
		"ground_bottom": Color("3a5068"),
		"sky_energy": 1.0,
		"harbor_tint": Color("cfe0ea"),
		"scorestrip_energy": 0.6,
		"grass_tex_mix": 0.18,
		"glow_intensity": 0.10,
		"glow_bloom": 0.02,
		"tonemap_exposure": 0.92,
		"crowd_tint": Color("edf4f2"),
	},
	"golden": {
		"background": Color("482340"),
		"ambient_color": Color("cf9166"),
		"ambient_energy": 0.40,
		"sun_color": Color("ffb060"),
		"sun_energy": 0.76,
		"fog_color": Color("c79363"),
		"fog_energy": 0.16,
		"fog_density": 0.0015,
		"grass_a": Color("77813f"),
		"grass_b": Color("646d34"),
		"grass_far": Color("4b5433"),
		"lamp_color": Color("fff0b8"),
		"lamp_energy": 0.42,
		"spot_energy": 0.55,
		"fill_energy": 0.25,
		"wash_energy": 0.38,
		# Flagship rig: low ~19deg sun swung in from the 1B (+x) side so shadows
		# rake toward 3B, matching the baked UE "PP_Golden" look.
		"sun_rotation": Vector3(-19.0, 55.0, 0.0),
		"sky_top": Color("4c3a68"),
		"sky_horizon": Color("e6a45c"),
		"ground_horizon": Color("7a5a42"),
		"ground_bottom": Color("2c2334"),
		"sky_energy": 1.0,
		"harbor_tint": Color("ffffff"),
		"scorestrip_energy": 1.4,
		"grass_tex_mix": 0.24,
		"glow_intensity": 0.16,
		"glow_bloom": 0.03,
		"tonemap_exposure": 0.90,
		"crowd_tint": Color("ffd3a0"),
	},
	"night": {
		"background": Color("081226"),
		"ambient_color": Color("3d4f85"),
		"ambient_energy": 0.54,
		"sun_color": Color("8fa6d6"),
		"sun_energy": 0.30,
		"fog_color": Color("16223d"),
		"fog_energy": 0.14,
		"fog_density": 0.0022,
		"grass_a": Color("34503b"),
		"grass_b": Color("2a4132"),
		"grass_far": Color("1c2c2c"),
		"lamp_color": Color("ffedb0"),
		"lamp_energy": 0.92,
		"spot_energy": 2.35,
		"fill_energy": 1.10,
		"wash_energy": 1.65,
		# Floodlit park: cool, low fill from the sky/moon and the towers carry
		# the scene (see spot/fill/wash energies above).
		"sun_rotation": Vector3(-46.0, -16.0, 0.0),
		"sky_top": Color("05070f"),
		"sky_horizon": Color("122036"),
		"ground_horizon": Color("0b1220"),
		"ground_bottom": Color("04060c"),
		"sky_energy": 0.6,
		"harbor_tint": Color("2a3350"),
		"scorestrip_energy": 2.6,
		"grass_tex_mix": 0.20,
		"glow_intensity": 0.24,
		"glow_bloom": 0.04,
		"tonemap_exposure": 0.92,
		"crowd_tint": Color("9aadd5"),
	},
}

var _materials: Dictionary = {}
var _sun: DirectionalLight3D
var _world_environment: WorldEnvironment
var _mood := "day"
var _mood_materials: Array[Dictionary] = []
var _grass_material: ShaderMaterial
var _lamp_material: StandardMaterial3D
var _shadow_spots: Array[SpotLight3D] = []
var _fill_spots: Array[SpotLight3D] = []
var _wash_lights: Array[OmniLight3D] = []
var _sky_material: ProceduralSkyMaterial
var _harbor_material: StandardMaterial3D
var _home_harbor_material: StandardMaterial3D
var _scorestrip_material: StandardMaterial3D
var _spectator_materials: Array[Dictionary] = []
var _animated_spectator_batches: Array[Dictionary] = []

# --- Animated dressing state (all driven from _process) ---
var _anim_time := 0.0
# Textured crowd strips: seeded idle/excited flips. The low-poly spectators use
# the same reaction envelope but retain deterministic per-person phase.
var _crowd_strips: Array[Dictionary] = []
var _crowd_calm: Array[Texture2D] = []
var _crowd_excited: Array[Texture2D] = []
var _crowd_excited_timer := 0.0
var _crowd_reaction_duration := 0.0
var _crowd_reaction_strength := 0.0
var _crowd_reaction_serial := 0
var _crowd_motion_accumulator := 0.0
var _crowd_motion_tick := 0
var _crowd_motion_sample := Vector3.ZERO
# One shared LED material rings the bowl; result flashes swap its emission map.
var _led_material: StandardMaterial3D
var _led_idle_texture: Texture2D
var _led_flash_texture: Texture2D
var _led_flash_timer := 0.0
const LED_IDLE_ENERGY := 1.8
# Liberty Bell pendulum pivot.
var _bell_pivot: Node3D
var _bell_timer := 0.0


func _ready() -> void:
	if get_child_count() == 0:
		build()
	set_process(true)


func build() -> void:
	_build_environment()
	_build_harbor_backdrop()
	_build_field()
	_build_ballpark()
	_build_home_backstop()
	_build_lighting()
	_apply_mood()


func _process(delta: float) -> void:
	_anim_time += delta
	_animate_crowd(delta)
	_animate_led(delta)
	_animate_bell(delta)


## Start or extend a presentation-only audience response. This animates the
## low-poly MultiMesh fans even when the legacy crowd textures are unavailable.
func set_crowd_excited(seconds: float, strength := 1.0) -> void:
	var requested_seconds := maxf(seconds, 0.0)
	if requested_seconds <= 0.0:
		return
	_crowd_excited_timer = maxf(_crowd_excited_timer, requested_seconds)
	_crowd_reaction_duration = maxf(_crowd_reaction_duration, _crowd_excited_timer)
	_crowd_reaction_strength = maxf(_crowd_reaction_strength, clampf(strength, 0.0, 1.0))
	_crowd_reaction_serial += 1
	_update_spectator_motion()


## One semantic entry point for gameplay presentation. It deliberately owns all
## stadium dressing so call sites cannot desynchronize crowd, ribbon, and bell.
func react_to_play(outcome: String) -> void:
	var normalized := outcome.strip_edges().to_lower().replace(" ", "_")
	var reaction: Dictionary = CROWD_REACTIONS.get(normalized, {})
	if reaction.is_empty():
		return
	set_crowd_excited(float(reaction.seconds), float(reaction.strength))
	flash_led(String(reaction.led))
	if bool(reaction.get("bell", false)):
		swing_bell()


## Small read-only presentation snapshot used by focused tests and visual QA.
func crowd_state() -> Dictionary:
	var section_counts := {}
	for path in ["SpectatorCrowdLeft", "SpectatorCrowdRight", "HomeBackstop/SpectatorCrowdPlate"]:
		var section := get_node_or_null(path)
		if section != null:
			section_counts[path] = int(section.get_meta("spectator_count", 0))
	return {
		"sections": section_counts,
		"total_spectators": int(section_counts.values().reduce(func(total: int, value: Variant) -> int: return total + int(value), 0)),
		"animated_batches": _animated_spectator_batches.size(),
		"strip_count": _crowd_strips.size(),
		"reaction_timer": _crowd_excited_timer,
		"reaction_duration": _crowd_reaction_duration,
		"reaction_strength": _crowd_reaction_strength,
		"reaction_level": _crowd_reaction_level(),
		"reaction_serial": _crowd_reaction_serial,
		"motion_tick": _crowd_motion_tick,
		"motion_sample": _crowd_motion_sample,
		"led_timer": _led_flash_timer,
		"bell_timer": _bell_timer,
	}


## Flash the LED ribbon with a result texture (K/WALK/BALL/STRIKE/FOUL/OUT/
## SINGLE/DOUBLE/TRIPLE/HOMERUN) for 1.5s of blinking, then return to idle.
## Safe no-op if the ribbon or outcome texture is missing.
func flash_led(outcome: String) -> void:
	if _led_material == null:
		return
	var path := "res://content/legacy/field/T_led_%s.png" % outcome.strip_edges().to_upper()
	if not ResourceLoader.exists(path):
		return
	_led_flash_texture = load(path) as Texture2D
	if _led_flash_texture == null:
		return
	_led_flash_timer = 1.5


## Swing the Liberty Bell on a decaying pendulum (~5s), matching the UE HR
## celebration. Safe no-op if the bell billboard is absent.
func swing_bell() -> void:
	if _bell_pivot == null:
		return
	_bell_timer = 5.0


func set_mood(mood: String) -> void:
	# Safe to call before build(): the mood is stored here and build() ends
	# with _apply_mood(), so an early call simply selects the starting mood.
	_mood = mood if MOODS.has(mood) else "day"
	for entry in _mood_materials:
		var material: StandardMaterial3D = entry.material
		material.albedo_texture = _mood_texture(String(entry.kind), _mood)
	_apply_mood()


func _apply_mood() -> void:
	var settings: Dictionary = MOODS[_mood if MOODS.has(_mood) else "day"]
	if _world_environment != null:
		var env := _world_environment.environment
		env.background_color = settings.background
		env.ambient_light_color = settings.ambient_color
		env.ambient_light_energy = settings.ambient_energy
		env.fog_light_color = settings.fog_color
		env.fog_light_energy = settings.fog_energy
		env.fog_density = settings.fog_density
		env.glow_intensity = settings.glow_intensity
		env.glow_bloom = settings.glow_bloom
		env.tonemap_exposure = settings.tonemap_exposure
	if _sky_material != null:
		_sky_material.sky_top_color = settings.sky_top
		_sky_material.sky_horizon_color = settings.sky_horizon
		_sky_material.ground_horizon_color = settings.ground_horizon
		_sky_material.ground_bottom_color = settings.ground_bottom
		_sky_material.energy_multiplier = settings.sky_energy
		_sky_material.sun_angle_max = 24.0 if _mood == "golden" else 12.0
	if _sun != null:
		_sun.light_color = settings.sun_color
		_sun.light_energy = settings.sun_energy
		_sun.rotation_degrees = settings.sun_rotation
	if _harbor_material != null:
		_harbor_material.albedo_color = settings.harbor_tint
	if _home_harbor_material != null:
		_home_harbor_material.albedo_color = (settings.harbor_tint as Color).darkened(0.34)
	if _grass_material != null:
		_grass_material.set_shader_parameter("color_a", settings.grass_a)
		_grass_material.set_shader_parameter("color_b", settings.grass_b)
		_grass_material.set_shader_parameter("color_far", settings.grass_far)
		var grass_tex := _mood_texture("grass", _mood)
		_grass_material.set_shader_parameter("grass_tex", grass_tex)
		_grass_material.set_shader_parameter("grass_tex_mix", float(settings.grass_tex_mix) if grass_tex != null else 0.0)
	if _scorestrip_material != null:
		_scorestrip_material.emission_energy_multiplier = settings.scorestrip_energy
	for entry in _spectator_materials:
		var spectator_material: StandardMaterial3D = entry.material
		var tint_strength := float(entry.tint_strength)
		var value_scale := float(entry.get("value_scale", 1.0))
		var crowd_color: Color = Color.WHITE.lerp(settings.crowd_tint, tint_strength)
		crowd_color.r *= value_scale
		crowd_color.g *= value_scale
		crowd_color.b *= value_scale
		spectator_material.albedo_color = crowd_color
	_refresh_crowd_textures()
	if _lamp_material != null:
		_lamp_material.emission = settings.lamp_color
		_lamp_material.emission_energy_multiplier = settings.lamp_energy
	for spot in _shadow_spots:
		spot.light_energy = settings.spot_energy
		spot.visible = settings.spot_energy > 0.005
	for spot in _fill_spots:
		spot.light_energy = settings.fill_energy
		spot.visible = settings.fill_energy > 0.005
	for wash in _wash_lights:
		wash.light_energy = settings.wash_energy
		wash.visible = settings.wash_energy > 0.005


func _build_environment() -> void:
	_world_environment = WorldEnvironment.new()
	_world_environment.name = "WorldEnvironment"
	var env := Environment.new()
	# A procedural sky gives each mood a real gradient (day blue, golden warm,
	# night dark) instead of a flat clear color; _apply_mood tunes its stops.
	_sky_material = ProceduralSkyMaterial.new()
	_sky_material.sky_top_color = Color("2f6ea8")
	_sky_material.sky_horizon_color = Color("b8d6ea")
	_sky_material.ground_horizon_color = Color("74909f")
	_sky_material.ground_bottom_color = Color("3a5068")
	_sky_material.sun_angle_max = 12.0
	_sky_material.energy_multiplier = 1.0
	var sky := Sky.new()
	sky.sky_material = _sky_material
	env.sky = sky
	env.background_mode = Environment.BG_SKY
	env.background_color = Color("4f88ad")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("b8dcff")
	env.ambient_light_energy = 0.48
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.34
	env.glow_bloom = 0.06
	# Forward+ ambient occlusion supplies the contact depth that primitive stands
	# and batched spectators otherwise lack. Compatibility safely ignores this.
	env.ssao_enabled = RenderingServer.get_current_rendering_method() != "gl_compatibility"
	env.ssao_radius = 0.72
	env.ssao_intensity = 1.55
	env.ssao_power = 1.25
	env.ssao_detail = 0.9
	env.ssao_horizon = 0.08
	env.ssao_sharpness = 0.78
	env.ssao_light_affect = 0.22
	env.fog_enabled = true
	env.fog_light_color = Color("bfd4e5")
	env.fog_light_energy = 0.22
	env.fog_density = 0.0025
	env.fog_sky_affect = 0.04
	_world_environment.environment = env
	add_child(_world_environment)


func _build_harbor_backdrop() -> void:
	var texture := load("res://content/art/environment/harbor_city_dusk.png") as Texture2D
	if texture == null:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2(150.0, 84.375)
	var material := StandardMaterial3D.new()
	material.albedo_texture = texture
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	# Per-mood modulate so the shipped dusk photo doesn't read raw in day/night.
	_harbor_material = material
	quad.material = material
	var backdrop := MeshInstance3D.new()
	backdrop.name = "HarborCityBackdrop"
	backdrop.mesh = quad
	backdrop.position = Vector3(0.0, 30.0, -116.0)
	backdrop.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(backdrop)

	# The center-field pitching lens looks back toward home plate. A second face
	# of the same authored harbor panorama turns the plate grandstand into a
	# waterfront terrace instead of a full-frame wall of spectators. The low
	# backstop and 3D crowd hide the image's dark lower apron; water, skyline,
	# and sky remain as quiet negative space behind the live battery.
	_home_harbor_material = material.duplicate(true) as StandardMaterial3D
	# This face is viewed from the opposite side of the outfield panorama. Flip
	# V explicitly so the upper opening shows sky/city instead of sampling the
	# source image's dark lower field apron.
	_home_harbor_material.uv1_scale = Vector3(1.0, -1.0, 1.0)
	# Bias the narrow overlook toward the working-city half of the panorama so
	# cranes and lit buildings, not an anonymous patch of open water, sit behind
	# the catcher and batter.
	_home_harbor_material.uv1_offset = Vector3(0.18, 1.0, 0.0)
	_textured_quad(
		"HomeHarborBackdrop",
		Vector2(112.0, 63.0),
		Vector3(0.0, 2.0, 72.0),
		Vector3(0.0, 0.0, -1.0),
		_home_harbor_material,
		self,
	)


func _build_lighting() -> void:
	_sun = DirectionalLight3D.new()
	_sun.name = "BallparkSun"
	_sun.rotation_degrees = Vector3(-52.0, -28.0, 0.0)
	_sun.light_color = Color("fff0ce")
	_sun.light_energy = 0.72
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 150.0
	add_child(_sun)

	var tower_index := 0
	for x in [-47.0, 47.0]:
		for z in [-18.0, -52.0]:
			var tower := Node3D.new()
			tower.name = "LightTower%d" % tower_index
			tower.position = Vector3(x, 0.0, z)
			add_child(tower)
			_box("Mast", Vector3(0.55, 20.0, 0.55), Vector3(0, 10, 0), Color("26324e"), tower)
			_box("Crossbar", Vector3(7.0, 0.45, 0.45), Vector3(0, 20, 0), Color("26324e"), tower)
			for lamp_x in [-2.7, -1.35, 0.0, 1.35, 2.7]:
				var lamp := _box("Lamp", Vector3(0.9, 0.7, 0.38), Vector3(lamp_x, 19.9, -0.25), Color("fff6c4"), tower)
				lamp.material_override = _get_lamp_material()
				lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			# Exactly two shadowed spots (the infield towers) plus two
			# unshadowed outfield fills; every energy comes from MOODS.
			var near_infield: bool = z > -30.0
			var spot := SpotLight3D.new()
			spot.name = "TowerSpot%d" % tower_index
			spot.position = Vector3(0.0, 19.4, 0.0)
			spot.spot_range = 85.0
			spot.spot_angle = 34.0 if near_infield else 44.0
			spot.light_color = Color("fff2cc")
			spot.light_energy = 0.0
			spot.shadow_enabled = near_infield
			# Aim with pure transform math: look_at() needs the node inside the
			# tree, and build() must also work on a detached stadium.
			var aim: Vector3 = Vector3(0.0, 0.0, 6.0) if near_infield else Vector3(0.0, 0.0, -24.0)
			var aim_dir := ((aim - tower.position) - spot.position).normalized()
			spot.transform = Transform3D(Basis.looking_at(aim_dir, Vector3.UP), spot.position)
			tower.add_child(spot)
			if near_infield:
				_shadow_spots.append(spot)
			else:
				_fill_spots.append(spot)
			tower_index += 1

	# Exactly two bounded, unshadowed plate washes: one pools warm light on
	# the home-plate action, the other grazes the backstop facade so the
	# authored layers stay readable at night. Energy comes from MOODS, so
	# day renders identically with them at zero.
	for wash_spec in [[Vector3(0.0, 4.6, 19.5), 15.0], [Vector3(0.0, 3.4, 29.2), 11.0]]:
		var wash := OmniLight3D.new()
		wash.name = "PlateWash%d" % _wash_lights.size()
		wash.position = wash_spec[0]
		wash.omni_range = wash_spec[1]
		wash.light_color = Color("ffe2a8")
		wash.light_energy = 0.0
		wash.shadow_enabled = false
		add_child(wash)
		_wash_lights.append(wash)


func _build_field() -> void:
	# One plane carries the pixel-grass shader: straight mowing lanes, a faint
	# crosshatch and clustered grain are generated in world space, so no macro
	# checker texture or hovering stripe overlays are needed.
	_grass_material = ShaderMaterial.new()
	_grass_material.shader = PIXEL_GRASS_SHADER
	_grass_material.set_shader_parameter("fan_origin", Vector2(C.HOME_PLATE.x, C.HOME_PLATE.z))
	var grass := MeshInstance3D.new()
	grass.name = "Grass"
	var grass_mesh := PlaneMesh.new()
	grass_mesh.size = Vector2(118.0, 126.0)
	grass.mesh = grass_mesh
	grass.position = Vector3(0.0, 0.0, -22.0)
	grass.material_override = _grass_material
	add_child(grass)

	_build_diamond_surface()
	_build_infield_detail()
	# Base paths and foul lines.
	for pair in [[C.HOME_PLATE, C.FIRST_BASE], [C.FIRST_BASE, C.SECOND_BASE], [C.SECOND_BASE, C.THIRD_BASE], [C.THIRD_BASE, C.HOME_PLATE]]:
		_beam_between("BasePath", pair[0] + Vector3.UP * 0.035, pair[1] + Vector3.UP * 0.035, 0.55, 0.035, Color("8a6a52"))
	var fence_profile := ParkGeometry.fence_profile()
	# Foul lines carry the shipped chalk texture so their tone tracks the mood.
	var chalk_mat := _mood_material("chalk", Color("f4f0e1"), 0.9, Vector3(2.0, 2.0, 40.0))
	var right_line := _beam_between("RightFoulLine", C.HOME_PLATE + Vector3.UP * 0.07, _fence_post_world(fence_profile[-1], false) + Vector3.UP * 0.07, 0.18, 0.04, Color("f8f3dc"))
	var left_line := _beam_between("LeftFoulLine", C.HOME_PLATE + Vector3.UP * 0.07, _fence_post_world(fence_profile[0], false) + Vector3.UP * 0.07, 0.18, 0.04, Color("f8f3dc"))
	right_line.material_override = chalk_mat
	left_line.material_override = chalk_mat

	for i in range(1, 4):
		var base := _box("Base%d" % i, Vector3(1.35, 0.16, 1.35), C.base_position(i) + Vector3.UP * 0.1, Color("fff9df"), self)
		base.rotation.y = PI / 4.0
	_box("PitchingRubber", Vector3(1.35, 0.11, 0.38), C.PITCHER_MOUND + Vector3.UP * 0.15, Color("fff9df"), self)
	# A layered plate reads as a pentagon from the broadcast camera.
	_box("HomePlate", Vector3(1.45, 0.12, 1.0), C.HOME_PLATE + Vector3(0, 0.11, -0.1), Color("fff9df"), self)

	# Batter boxes and chalk marks.
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		for dz in [-1.45, 1.45]:
			_box("Chalk", Vector3(0.09, 0.035, 3.0), C.HOME_PLATE + Vector3(side * 1.75, 0.08, 0), Color("f3e7cc"), self)
			_box("Chalk", Vector3(1.45, 0.035, 0.09), C.HOME_PLATE + Vector3(side * 1.75, 0.08, dz), Color("f3e7cc"), self)


func _build_diamond_surface() -> void:
	var mesh := ImmediateMesh.new()
	var points := [
		C.HOME_PLATE + Vector3(0, 0.02, 2.6),
		C.FIRST_BASE + Vector3(3.0, 0.02, 0),
		C.SECOND_BASE + Vector3(0, 0.02, -3.0),
		C.THIRD_BASE + Vector3(-3.0, 0.02, 0),
	]
	# Kept desaturated: under the low golden sun the overhead PlayCam sees this
	# quad across the whole frame, and a warmer tint reads as a red slab there.
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _mood_material("dirt", Color("857260"), 1.0, Vector3(14.0, 14.0, 14.0)))
	for idx in [0, 1, 2, 0, 2, 3]:
		mesh.surface_set_normal(Vector3.UP)
		mesh.surface_add_vertex(points[idx])
	mesh.surface_end()
	var dirt := MeshInstance3D.new()
	dirt.name = "InfieldDirt"
	dirt.mesh = mesh
	add_child(dirt)


func _build_infield_detail() -> void:
	# Visual-only layers stacked in the 0.03..0.07 band: everything stays
	# below actor foot height (0.08), shares a handful of materials, and has
	# no collision. Layer order (low to high): apron, cutout, keyhole, home
	# circle, mound skirt, crown.
	var dirt := _mood_material("dirt", Color("857260"), 1.0, Vector3(12.0, 12.0, 12.0))
	dirt.cull_mode = BaseMaterial3D.CULL_DISABLED
	var dirt_light := _mood_material("dirt", Color("93826d"), 1.0, Vector3(12.0, 12.0, 12.0))
	dirt_light.cull_mode = BaseMaterial3D.CULL_DISABLED
	var track := _mood_material("dirt", Color("7b6752"), 1.0, Vector3(12.0, 12.0, 12.0))
	track.cull_mode = BaseMaterial3D.CULL_DISABLED

	# Rounded dirt apron behind the base paths, centered on the mound; with
	# the diamond quad underneath it reads as the classic infield perimeter.
	_ring_sector("InfieldDirtApron", Vector3(C.PITCHER_MOUND.x, 0.03, C.PITCHER_MOUND.z), 0.0, 13.8, -1.95, 1.95, dirt, 36)

	# Grass cutout inside the base paths reuses the field shader so the mow
	# pattern flows through, leaving only a dirt rim along each path.
	var cutout_mesh := ImmediateMesh.new()
	var diamond_center := Vector3(0.0, 0.05, 4.25)
	var cutout_points: Array[Vector3] = []
	for corner_value in [C.HOME_PLATE, C.FIRST_BASE, C.SECOND_BASE, C.THIRD_BASE]:
		var corner: Vector3 = corner_value
		var flat := Vector3(corner.x, 0.05, corner.z)
		cutout_points.append(flat + (diamond_center - flat).normalized() * 2.8)
	cutout_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _grass_material)
	for idx in [0, 1, 2, 0, 2, 3]:
		cutout_mesh.surface_set_normal(Vector3.UP)
		cutout_mesh.surface_add_vertex(cutout_points[idx])
	cutout_mesh.surface_end()
	var cutout := MeshInstance3D.new()
	cutout.name = "InfieldGrassCutout"
	cutout.mesh = cutout_mesh
	cutout.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(cutout)

	# Keyhole path from the mound skirt to the home-plate circle.
	var keyhole := _box("KeyholePath", Vector3(0.68, 0.02, 12.8), Vector3(0.0, 0.055, 8.8), Color("c99a6a"), self)
	keyhole.material_override = dirt
	keyhole.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	_disk("HomeCircle", Vector3(C.HOME_PLATE.x, 0.06, C.HOME_PLATE.z), 2.9, dirt)
	# Flat skirt and lighter crown fake mound height while leaving the
	# actual actor standing height untouched.
	_disk("MoundSkirt", Vector3(C.PITCHER_MOUND.x, 0.062, C.PITCHER_MOUND.z), 2.6, dirt)
	_disk("MoundCrown", Vector3(C.PITCHER_MOUND.x, 0.07, C.PITCHER_MOUND.z), 1.5, dirt_light)
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		_disk("OnDeckCircle", Vector3(side * 7.5, 0.03, C.HOME_PLATE.z + 5.0), 1.15, dirt_light)
		_box("CatcherChalk", Vector3(0.09, 0.02, 1.6), C.HOME_PLATE + Vector3(side * 0.95, 0.0, 2.6), Color("f3e7cc"), self)

	_build_warning_track(track)


func _build_warning_track(material: Material) -> void:
	var profile := ParkGeometry.fence_profile()
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for i in range(profile.size() - 1):
		var a := _fence_post_world(profile[i], false) + Vector3.UP * 0.028
		var b := _fence_post_world(profile[i + 1], false) + Vector3.UP * 0.028
		var a_inner := a + _toward_home(a) * 2.4
		var b_inner := b + _toward_home(b) * 2.4
		for vertex in [a, b, b_inner, a, b_inner, a_inner]:
			mesh.surface_set_normal(Vector3.UP)
			mesh.surface_add_vertex(vertex)
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = "WarningTrack"
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)


func _toward_home(from_point: Vector3) -> Vector3:
	return Vector3(C.HOME_PLATE.x - from_point.x, 0.0, C.HOME_PLATE.z - from_point.z).normalized()


func _disk(label: String, center: Vector3, radius: float, material: Material, segments := 28) -> MeshInstance3D:
	return _ring_sector(label, center, 0.0, radius, -PI, PI, material, segments)


func _ring_sector(label: String, center: Vector3, inner_radius: float, outer_radius: float, angle_from: float, angle_to: float, material: Material, segments := 28) -> MeshInstance3D:
	# Flat annulus sector in the XZ plane; angle 0 faces the outfield (-z).
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	for i in range(segments):
		var a0 := lerpf(angle_from, angle_to, float(i) / float(segments))
		var a1 := lerpf(angle_from, angle_to, float(i + 1) / float(segments))
		var dir0 := Vector3(sin(a0), 0.0, -cos(a0))
		var dir1 := Vector3(sin(a1), 0.0, -cos(a1))
		var quad := [
			center + dir0 * inner_radius,
			center + dir0 * outer_radius,
			center + dir1 * outer_radius,
			center + dir1 * inner_radius,
		]
		for idx in [0, 1, 2, 0, 2, 3]:
			mesh.surface_set_normal(Vector3.UP)
			mesh.surface_add_vertex(quad[idx])
	mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	return instance


func _build_ballpark() -> void:
	# Render the exact straight-segment Citizens Bank profile used by live-ball
	# classification. Each top edge follows its two endpoint heights, including
	# the 19-foot Angle and the low six-foot center wall.
	var fence_profile := ParkGeometry.fence_profile()
	for i in range(fence_profile.size() - 1):
		_build_fence_segment(i, fence_profile[i], fence_profile[i + 1])
	for i in range(fence_profile.size()):
		var post: Dictionary = fence_profile[i]
		var height := float(post.height_ft) * ParkGeometry.VERTICAL_WORLD_PER_FOOT
		_box("FencePost%02d" % i, Vector3(0.34, height, 0.34), _fence_post_world(post, false) + Vector3.UP * height * 0.5, Color("163f4b"), self)

	# Tiered stands and a seeded-looking crowd made of low-cost voxel blocks.
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		for tier in range(3):
			var stand_pos := Vector3(side * (34.0 + tier * 4.0), 1.2 + tier * 1.8, -9.0 - tier * 4.0)
			var stand := _box("Stand", Vector3(10.0, 2.2, 55.0), stand_pos, Color("26324e") if tier % 2 == 0 else Color("303e5c"), self)
			stand.material_override = _mood_material("seats", Color("7d8da9") if tier % 2 == 0 else Color("899ab4"), 0.9, Vector3(5.0, 12.0, 5.0))
			stand.rotation.z = side * 0.045
		_build_crowd_side(side)
		# Grandstand canopy: one roof slab plus three posts per side gives the
		# stands a stepped skyline silhouette instead of a bare slab top.
		_box("StandCanopy", Vector3(13.0, 0.35, 57.0), Vector3(side * 40.0, 8.4, -13.0), Color("1f3a33"), self)
		# Downward fascia along the field-facing edge so the roof has depth from
		# the broadcast angle instead of reading as a floating slab.
		_box("StandCanopyFascia", Vector3(0.4, 1.35, 57.0), Vector3(side * 33.6, 7.75, -13.0), Color("172a3a"), self)
		for post_z in [-38.0, -13.0, 12.0]:
			_box("CanopyTruss", Vector3(0.4, 2.6, 0.4), Vector3(side * 44.5, 7.0, post_z), Color("26324e"), self)

	# Dugouts and roof trims.
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		var dugout := Vector3(side * 23.0, 1.25, 13.0)
		var dugout_body := _box("Dugout", Vector3(13.0, 2.5, 4.0), dugout, Color("151e36"), self)
		dugout_body.material_override = _mood_material("brick", Color("c78c71"), 0.94, Vector3(4.0, 2.0, 4.0))
		# Muted, team-tinted dark roofs (were over-saturated gold/teal from above).
		_box("DugoutRoof", Vector3(14.0, 0.35, 5.0), dugout + Vector3.UP * 1.55, Color("6f5629") if side < 0 else Color("285f53"), self)

	# Center-field video board with raised pixel-like lettering.
	var board_root := Node3D.new()
	board_root.name = "CenterFieldScoreboard"
	board_root.position = Vector3(0.0, 10.0, -52.5)
	add_child(board_root)
	_box("Board", Vector3(23.0, 11.0, 1.2), Vector3.ZERO, Color("10172b"), board_root)
	_box("Screen", Vector3(19.5, 7.5, 0.25), Vector3(0, 0.4, 0.72), Color("122f47"), board_root)
	# Line-score strip across the board face, emissive so it glows at night.
	var scorestrip_tex := load("res://content/legacy/field/T_scorestrip.png") as Texture2D
	if scorestrip_tex != null:
		_scorestrip_material = StandardMaterial3D.new()
		_scorestrip_material.albedo_color = Color("0b1220")
		_scorestrip_material.albedo_texture = scorestrip_tex
		_scorestrip_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_scorestrip_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_scorestrip_material.emission_enabled = true
		_scorestrip_material.emission = Color("ffffff")
		_scorestrip_material.emission_texture = scorestrip_tex
		_scorestrip_material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
		_scorestrip_material.emission_energy_multiplier = 0.6
		var strip := _box("ScoreStrip", Vector3(19.5, 1.35, 0.2), Vector3(0.0, -3.15, 0.86), Color.WHITE, board_root)
		strip.material_override = _scorestrip_material
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var title := Label3D.new()
	title.name = "LeagueMark"
	title.text = "PIXIBALL\nHARBOR LEAGUE"
	title.font_size = 58
	title.modulate = Color("f8f3dc")
	title.outline_modulate = Color("ff4d6d")
	title.outline_size = 10
	title.position = Vector3(0, 0.4, 0.9)
	title.pixel_size = 0.018
	# Depth-tested: with no_depth_test the lettering bled through stands and
	# players from every camera angle.
	title.no_depth_test = false
	board_root.add_child(title)
	for x in [-9.8, 9.8]:
		for y in [-4.0, 4.0]:
			var board_light := _box("BoardLight", Vector3(0.7, 0.7, 0.35), Vector3(x, y, 0.9), Color("ffd166"), board_root)
			board_light.material_override = _get_lamp_material()
	# Truss legs, a cross brace and a roof cap turn the floating slab into a
	# grounded harbor-park scoreboard silhouette.
	for x in [-8.0, 8.0]:
		_box("BoardLeg", Vector3(0.6, 4.5, 0.6), Vector3(x, -7.75, 0.0), Color("1f3a33"), board_root)
	_box("BoardBrace", Vector3(16.6, 0.4, 0.4), Vector3(0.0, -6.6, 0.0), Color("1f3a33"), board_root)
	_box("BoardRoof", Vector3(24.0, 0.5, 1.8), Vector3(0.0, 5.9, 0.0), Color("1f3a33"), board_root)

	# Landmark buildings beyond the wall make fly balls and tracking shots legible.
	for i in range(10):
		var h := 10.0 + float((i * 7) % 13)
		var x := -53.0 + float(i) * 11.5
		var z := -77.0 - float((i * 5) % 9)
		var building := _box("Skyline", Vector3(7.5, h, 6.5), Vector3(x, h * 0.5, z), Color("344968") if i % 2 == 0 else Color("40597a"), self)
		for wy in range(2, int(h) - 1, 3):
			for wx in [-2.0, 0.0, 2.0]:
				_box("Window", Vector3(0.75, 0.65, 0.12), building.position + Vector3(wx, -h * 0.5 + wy, 3.31), Color("ffd166"), self)

	# Harbor silhouettes behind the skyline sell the waterfront: two gantry
	# cranes, a low pier on posts, and a tug hull. All flat-lit distant blocks.
	for crane_value in [[-34.0, -88.0, 1.0], [36.0, -90.0, -1.0]]:
		var crane: Array = crane_value
		var base := Vector3(crane[0], 0.0, crane[1])
		var lean: float = crane[2]
		_box("CraneMast", Vector3(1.0, 15.0, 1.0), base + Vector3(0, 7.5, 0), Color("223047"), self)
		_box("CraneJib", Vector3(11.0, 0.6, 0.8), base + Vector3(lean * 4.5, 14.6, 0), Color("223047"), self)
		_box("CraneWeight", Vector3(2.2, 1.5, 1.2), base + Vector3(-lean * 3.6, 13.6, 0), Color("1b2638"), self)
		_box("CraneCable", Vector3(0.18, 5.0, 0.18), base + Vector3(lean * 9.2, 12.0, 0), Color("1b2638"), self)
	_box("HarborPier", Vector3(24.0, 1.0, 4.0), Vector3(6.0, 1.6, -90.0), Color("3a2f26"), self)
	for post_x in [-4.0, 4.0, 12.0, 16.0]:
		_box("PierPost", Vector3(0.7, 2.4, 0.7), Vector3(6.0 + post_x, 0.4, -88.4), Color("2b241d"), self)
	_box("TugHull", Vector3(8.0, 1.6, 3.0), Vector3(-12.0, 0.9, -92.0), Color("30405c"), self)
	_box("TugCabin", Vector3(2.6, 1.6, 2.0), Vector3(-13.0, 2.5, -92.0), Color("223047"), self)

	# Textured dressing that leans on the shipped legacy texture library.
	_build_led_ring()
	_build_wall_ads()
	_build_batters_eye()
	_build_liberty_bell(board_root)


func _build_crowd_side(side: float) -> void:
	var root := Node3D.new()
	root.name = "SpectatorCrowdLeft" if side < 0.0 else "SpectatorCrowdRight"
	add_child(root)
	var batches := {
		"torsos": [],
		"necks": [],
		"heads": [],
		"hair": [],
		"caps": [],
		"cap_brims": [],
		"upper_arms": [],
		"forearms": [],
		"eyes": [],
		"mouths": [],
	}
	var spectator_count := 0
	var layout_min := Vector3(INF, INF, INF)
	var layout_max := Vector3(-INF, -INF, -INF)
	var min_face_clearance := INF
	var layout_samples: Array[Dictionary] = []
	for tier in range(3):
		var stand_center := Vector3(side * (34.0 + float(tier) * 4.0), 1.2 + float(tier) * 1.8, -9.0 - float(tier) * 4.0)
		var stand_roll := side * 0.045
		for crowd_row in range(SPECTATOR_ROWS_PER_TIER):
			# Follow the rotated top plane and step backward/up through the stand.
			# The old first row sat exactly on the stand's vertical face; every new
			# origin is above the top surface with an explicit clearance.
			var x := side * (29.7 + float(tier) * 4.0 + float(crowd_row) * 1.32)
			var local_x := x - stand_center.x
			var surface_y := stand_center.y + sin(stand_roll) * local_x + cos(stand_roll) * 1.1
			var base_y := surface_y + 0.06 + float(crowd_row) * 0.08
			var z_min := stand_center.z - 25.0
			var z_max := stand_center.z + 25.0
			for seat in range(SPECTATOR_SEATS_PER_ROW):
				# Regular gaps read as aisles and prevent an undifferentiated wall.
				if posmod(seat + crowd_row * 3 + tier * 5, 11) == 0:
					continue
				var seed := (100000 if side > 0.0 else 0) + tier * 10000 + crowd_row * 1000 + seat
				var z_lerp := (float(seat) + 0.5) / float(SPECTATOR_SEATS_PER_ROW)
				var stagger := 0.42 if crowd_row % 2 == 1 else 0.0
				var jitter := (_hash01(seed * 17 + 9) - 0.5) * 0.18
				var z := clampf(lerpf(z_min, z_max, z_lerp) + stagger + jitter, z_min + 0.35, z_max - 0.35)
				var base := Vector3(x, base_y, z)
				var face_direction := Vector3(0.0, base.y, 8.0) - base
				face_direction.y = 0.0
				var facing := Basis.looking_at(face_direction.normalized(), Vector3.UP)
				var depth := float(tier * SPECTATOR_ROWS_PER_TIER + crowd_row) / float(3 * SPECTATOR_ROWS_PER_TIER - 1)
				var shirt: Color = SPECTATOR_SHIRTS[int(_hash01(seed * 5 + 1) * float(SPECTATOR_SHIRTS.size())) % SPECTATOR_SHIRTS.size()]
				var skin: Color = SPECTATOR_SKINS[int(_hash01(seed * 7 + 3) * float(SPECTATOR_SKINS.size())) % SPECTATOR_SKINS.size()]
				shirt = shirt.lerp(Color("39465c"), depth * 0.16)
				skin = skin.darkened(depth * 0.07)
				_append_spectator(batches, base, facing, shirt, skin, seed)
				layout_min = layout_min.min(base)
				layout_max = layout_max.max(base)
				min_face_clearance = minf(min_face_clearance, absf(absf(base.x) - (29.0 + float(tier) * 4.0)))
				if layout_samples.size() < 8:
					layout_samples.append({"base": base, "shirt": shirt, "skin": skin, "seed": seed})
				spectator_count += 1
	root.set_meta("spectator_count", spectator_count)
	root.set_meta("layout_bounds", AABB(layout_min, layout_max - layout_min))
	root.set_meta("minimum_face_clearance", min_face_clearance)
	root.set_meta("layout_samples", layout_samples)
	_build_spectator_batches(root, batches)


func _append_spectator(batches: Dictionary, base: Vector3, facing: Basis, shirt: Color, skin: Color, seed: int, size_scale := 1.0) -> void:
	var height_scale := 0.90 + _hash01(seed * 13 + 7) * 0.20
	var body_yaw := (_hash01(seed * 67 + 17) - 0.5) * 0.15
	var head_yaw := body_yaw + (_hash01(seed * 71 + 19) - 0.5) * 0.32
	var body_facing := facing * Basis(Vector3.UP, body_yaw)
	var head_facing := facing * Basis(Vector3.UP, head_yaw)
	var body_scale := Basis.from_scale(Vector3(
		(0.86 + _hash01(seed * 19 + 5) * 0.22) * size_scale,
		height_scale * size_scale,
		(0.90 + _hash01(seed * 23 + 11) * 0.16) * size_scale
	))
	var torso_basis := body_facing * body_scale
	var head_scale := 0.92 + _hash01(seed * 29 + 13) * 0.14
	var head_basis := head_facing * Basis.from_scale(Vector3(
		head_scale * (0.94 + _hash01(seed * 73 + 23) * 0.12) * size_scale,
		head_scale * (0.96 + _hash01(seed * 79 + 29) * 0.10) * size_scale,
		head_scale * size_scale
	))
	(batches.torsos as Array).append({"transform": Transform3D(torso_basis, base + body_facing * (Vector3(0.0, 0.34, 0.0) * size_scale)), "color": shirt, "seed": seed})
	(batches.necks as Array).append({"transform": Transform3D(body_facing * Basis.from_scale(Vector3(size_scale, height_scale * size_scale, size_scale)), base + body_facing * (Vector3(0.0, 0.61, 0.0) * size_scale)), "color": skin, "seed": seed})
	(batches.heads as Array).append({"transform": Transform3D(head_basis, base + head_facing * (Vector3(0.0, 0.77, -0.01) * size_scale)), "color": skin, "seed": seed})
	var hair: Color = SPECTATOR_HAIR[int(_hash01(seed * 41 + 23) * float(SPECTATOR_HAIR.size())) % SPECTATOR_HAIR.size()]
	var hair_basis := head_facing * Basis.from_scale(Vector3(head_scale * size_scale, head_scale * 0.46 * size_scale, head_scale * size_scale))
	(batches.hair as Array).append({"transform": Transform3D(hair_basis, base + head_facing * (Vector3(0.0, 0.845, -0.014) * size_scale)), "color": hair, "seed": seed})
	if _hash01(seed * 83 + 31) < 0.30:
		var cap_color := shirt.lerp(SPECTATOR_SHIRTS[(seed + 3) % SPECTATOR_SHIRTS.size()], 0.42)
		var cap_basis := head_facing * Basis.from_scale(Vector3(head_scale * size_scale, head_scale * size_scale, head_scale * size_scale))
		(batches.caps as Array).append({"transform": Transform3D(cap_basis, base + head_facing * (Vector3(0.0, 0.895, -0.012) * size_scale)), "color": cap_color, "seed": seed})
		(batches.cap_brims as Array).append({"transform": Transform3D(head_facing * Basis.from_scale(Vector3.ONE * size_scale), base + head_facing * (Vector3(0.0, 0.875, -0.118) * size_scale)), "color": cap_color.darkened(0.12), "seed": seed})

	# Most spectators sit or converse at idle; a smaller visible minority keeps
	# one or both arms raised. This leaves semantic play reactions somewhere to
	# go instead of making every ordinary pitch look like a celebration.
	var pose_roll := _hash01(seed * 31 + 17)
	var pose := 0
	if pose_roll >= 0.45 and pose_roll < 0.63:
		pose = 4
	elif pose_roll >= 0.63 and pose_roll < 0.78:
		pose = 5
	elif pose_roll >= 0.78 and pose_roll < 0.84:
		pose = 1
	elif pose_roll >= 0.84 and pose_roll < 0.90:
		pose = 2
	elif pose_roll >= 0.90 and pose_roll < 0.96:
		pose = 3
	elif pose_roll >= 0.96:
		pose = 6
	var left_shoulder := Vector3(-0.18, 0.49, -0.005)
	var right_shoulder := Vector3(0.18, 0.49, -0.005)
	var left_elbow := Vector3(-0.21, 0.35, -0.01)
	var right_elbow := Vector3(0.21, 0.35, -0.01)
	var left_hand := Vector3(-0.15, 0.21, -0.035)
	var right_hand := Vector3(0.15, 0.21, -0.035)
	if pose == 1:
		left_elbow = Vector3(-0.25, 0.65, -0.01)
		left_hand = Vector3(-0.15, 0.84, -0.025)
	elif pose == 2:
		right_elbow = Vector3(0.25, 0.65, -0.01)
		right_hand = Vector3(0.15, 0.84, -0.025)
	elif pose == 3:
		left_elbow = Vector3(-0.26, 0.64, -0.01)
		right_elbow = Vector3(0.26, 0.64, -0.01)
		left_hand = Vector3(-0.34, 0.82, -0.025)
		right_hand = Vector3(0.34, 0.82, -0.025)
	elif pose == 4:
		left_elbow = Vector3(-0.23, 0.49, -0.015)
		right_elbow = Vector3(0.23, 0.49, -0.015)
		left_hand = Vector3(-0.045, 0.62, -0.08)
		right_hand = Vector3(0.045, 0.62, -0.08)
	elif pose == 5:
		left_elbow = Vector3(-0.24, 0.35, -0.015)
		right_elbow = Vector3(0.24, 0.35, -0.015)
		left_hand = Vector3(-0.07, 0.25, -0.08)
		right_hand = Vector3(0.07, 0.25, -0.08)
	elif pose == 6:
		left_elbow = Vector3(-0.29, 0.62, -0.015)
		left_hand = Vector3(-0.36, 0.79, -0.035)
	var sleeve := shirt.darkened(0.06)
	left_shoulder *= size_scale
	right_shoulder *= size_scale
	left_elbow *= size_scale
	right_elbow *= size_scale
	left_hand *= size_scale
	right_hand *= size_scale
	(batches.upper_arms as Array).append({"transform": _limb_transform(base, body_facing, left_shoulder, left_elbow, size_scale), "color": sleeve, "seed": seed})
	(batches.upper_arms as Array).append({"transform": _limb_transform(base, body_facing, right_shoulder, right_elbow, size_scale), "color": sleeve, "seed": seed})
	(batches.forearms as Array).append({"transform": _limb_transform(base, body_facing, left_elbow, left_hand, size_scale), "color": skin, "seed": seed})
	(batches.forearms as Array).append({"transform": _limb_transform(base, body_facing, right_elbow, right_hand, size_scale), "color": skin, "seed": seed})

	var face_color := Color("17202b")
	for eye_x in [-0.043, 0.043]:
		(batches.eyes as Array).append({"transform": Transform3D(head_facing * Basis.from_scale(Vector3.ONE * size_scale), base + head_facing * (Vector3(eye_x, 0.79, -0.128) * size_scale)), "color": face_color, "seed": seed})
	var expression_angle: float = [-0.12, 0.0, 0.12][int(_hash01(seed * 37 + 19) * 3.0) % 3]
	var mouth_basis := head_facing * Basis(Vector3(0.0, 0.0, 1.0), expression_angle) * Basis.from_scale(Vector3.ONE * size_scale)
	(batches.mouths as Array).append({"transform": Transform3D(mouth_basis, base + head_facing * (Vector3(0.0, 0.735, -0.132) * size_scale)), "color": face_color, "seed": seed})


func _limb_transform(base: Vector3, facing: Basis, from: Vector3, to: Vector3, thickness_scale := 1.0) -> Transform3D:
	var delta := to - from
	var direction := delta.normalized()
	var dot := clampf(Vector3.UP.dot(direction), -1.0, 1.0)
	var rotation := Basis.IDENTITY
	if dot < 0.9999:
		var axis := Vector3.UP.cross(direction)
		if axis.length_squared() < 0.0001:
			axis = Vector3.RIGHT
		rotation = Basis(axis.normalized(), acos(dot))
	var segment_scale := Basis.from_scale(Vector3(thickness_scale, delta.length() / 0.24, thickness_scale))
	return Transform3D(facing * rotation * segment_scale, base + facing * ((from + to) * 0.5))


func _build_spectator_batches(root: Node3D, batches: Dictionary, value_scale := 1.0) -> void:
	var torso_mesh := CylinderMesh.new()
	torso_mesh.top_radius = 0.20
	torso_mesh.bottom_radius = 0.15
	torso_mesh.height = 0.46
	torso_mesh.radial_segments = 6
	torso_mesh.rings = 1
	_add_spectator_batch(root, "Torsos", torso_mesh, batches.torsos, 0.88, 0.35, true, value_scale)

	var neck_mesh := CylinderMesh.new()
	neck_mesh.top_radius = 0.055
	neck_mesh.bottom_radius = 0.065
	neck_mesh.height = 0.11
	neck_mesh.radial_segments = 6
	neck_mesh.rings = 1
	_add_spectator_batch(root, "Necks", neck_mesh, batches.necks, 0.86, 0.22, true, value_scale)

	var head_mesh := SphereMesh.new()
	head_mesh.radius = 0.12
	head_mesh.height = 0.24
	head_mesh.radial_segments = 8
	head_mesh.rings = 4
	_add_spectator_batch(root, "Heads", head_mesh, batches.heads, 0.84, 0.22, true, value_scale)

	var hair_mesh := SphereMesh.new()
	hair_mesh.radius = 0.125
	hair_mesh.height = 0.25
	hair_mesh.radial_segments = 8
	hair_mesh.rings = 4
	_add_spectator_batch(root, "Hair", hair_mesh, batches.hair, 0.92, 0.12, true, value_scale)

	var cap_mesh := CylinderMesh.new()
	cap_mesh.top_radius = 0.128
	cap_mesh.bottom_radius = 0.132
	cap_mesh.height = 0.078
	cap_mesh.radial_segments = 8
	cap_mesh.rings = 1
	_add_spectator_batch(root, "Caps", cap_mesh, batches.caps, 0.86, 0.22, true, value_scale)

	var brim_mesh := BoxMesh.new()
	brim_mesh.size = Vector3(0.17, 0.025, 0.11)
	_add_spectator_batch(root, "CapBrims", brim_mesh, batches.cap_brims, 0.88, 0.22, true, value_scale)

	var arm_mesh := CapsuleMesh.new()
	arm_mesh.radius = 0.038
	arm_mesh.height = 0.24
	arm_mesh.radial_segments = 6
	arm_mesh.rings = 2
	_add_spectator_batch(root, "UpperArms", arm_mesh, batches.upper_arms, 0.88, 0.32, true, value_scale)
	_add_spectator_batch(root, "Forearms", arm_mesh, batches.forearms, 0.86, 0.22, true, value_scale)

	var eye_mesh := BoxMesh.new()
	eye_mesh.size = Vector3(0.022, 0.018, 0.014)
	_add_spectator_batch(root, "Eyes", eye_mesh, batches.eyes, 0.72, 0.08, false, value_scale)

	var mouth_mesh := BoxMesh.new()
	mouth_mesh.size = Vector3(0.052, 0.011, 0.014)
	_add_spectator_batch(root, "Mouths", mouth_mesh, batches.mouths, 0.76, 0.08, false, value_scale)
	root.set_meta("part_counts", {
		"Caps": (batches.caps as Array).size(),
		"CapBrims": (batches.cap_brims as Array).size(),
	})


func _add_spectator_batch(root: Node3D, label: String, mesh: PrimitiveMesh, instances: Array, roughness: float, tint_strength: float, cast_shadow: bool, value_scale := 1.0) -> void:
	var material := StandardMaterial3D.new()
	material.resource_name = "Spectator%s" % label
	material.vertex_color_use_as_albedo = true
	material.albedo_color = Color(value_scale, value_scale, value_scale)
	material.roughness = roughness
	material.metallic = 0.0
	mesh.material = material
	_spectator_materials.append({"material": material, "tint_strength": tint_strength, "value_scale": value_scale})

	var multimesh := MultiMesh.new()
	multimesh.mesh = mesh
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_colors = true
	multimesh.use_custom_data = true
	multimesh.instance_count = instances.size()
	var rest_transforms: Array = []
	var motion_data: Array = []
	for index in range(instances.size()):
		var entry: Dictionary = instances[index]
		var rest: Transform3D = entry.transform
		var seed := int(entry.get("seed", index))
		# RGBA = idle phase, speed, amplitude, and reaction affinity. The values
		# remain deterministic and inspectable even though the actual transforms
		# are stepped at 12 Hz to avoid per-frame work for thousands of fans.
		var custom := Color(
			_hash01(seed * 43 + 5),
			0.55 + _hash01(seed * 47 + 7) * 0.45,
			0.55 + _hash01(seed * 53 + 11) * 0.45,
			0.18 + _hash01(seed * 59 + 13) * 0.82
		)
		rest_transforms.append(rest)
		motion_data.append(custom)
		multimesh.set_instance_transform(index, rest)
		multimesh.set_instance_color(index, entry.color)
		multimesh.set_instance_custom_data(index, custom)

	var batch := MultiMeshInstance3D.new()
	batch.name = label
	batch.multimesh = multimesh
	batch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Dummy/headless rendering does not round-trip MultiMesh custom buffers, so a
	# bounded metadata mirror keeps determinism auditable in CI.
	batch.set_meta("motion_samples", motion_data.slice(0, mini(16, motion_data.size())))
	root.add_child(batch)
	_animated_spectator_batches.append({
		"multimesh": multimesh,
		"rest_transforms": rest_transforms,
		"motion_data": motion_data,
		"part": label,
	})


func _build_plate_crowd() -> void:
	# Capped plate-side grandstand the CF broadcast cam frames head-on. Vertical
	# stack, low->high: lower crowd rows -> ShadowBlue structural fascia -> brick
	# suite band with lit windows -> upper crowd rows -> roof + fascia lip. Heights
	# stay modest so the roof line lands in the upper frame with SKY above it,
	# rather than crowd filling edge-to-edge. Every row is one seated tier of
	# life-size fans (see CROWD_ROW_WORLD / CROWD_TILE_WORLD).
	var root := get_node("HomeBackstop")
	var half_w := 18.5
	var y := 1.95
	# Put real spectators well behind the knee wall. The telephoto pitching lens
	# otherwise renders them almost as large as the battery and turns five rows
	# into a flat wall. Extra depth lets individual silhouettes and the harbor
	# panorama coexist in the same frame.
	var z := 38.6
	var spectator_root := Node3D.new()
	spectator_root.name = "SpectatorCrowdPlate"
	root.add_child(spectator_root)
	var spectator_batches := {
		"torsos": [],
		"necks": [],
		"heads": [],
		"hair": [],
		"caps": [],
		"cap_brims": [],
		"upper_arms": [],
		"forearms": [],
		"eyes": [],
		"mouths": [],
	}
	var spectator_count := 0
	var layout_min := Vector3(INF, INF, INF)
	var layout_max := Vector3(-INF, -INF, -INF)
	var layout_samples: Array[Dictionary] = []
	# Lower bowl: three seated rows rising back, dark seat-gap line under each.
	# The rake is deliberately shallow (rise < row depth) so the whole bowl stays
	# short enough to leave sky above the roofline in the CF broadcast framing.
	for r in range(3):
		var row_layout := _append_plate_spectator_row(spectator_batches, y, z, half_w, r)
		spectator_count += int(row_layout.count)
		layout_min = layout_min.min(row_layout.minimum)
		layout_max = layout_max.max(row_layout.maximum)
		for sample in row_layout.samples:
			if layout_samples.size() < 8:
				layout_samples.append(sample)
		_box("SeatGapLo%d" % r, Vector3(half_w * 2.0, 0.1, 0.14), Vector3(0.0, y - 0.5, z - 0.03), Color("333c57"), root)
		y += 0.78
		z += 0.85
	# Split the fascia and suite into two wings. The open center is the park's
	# signature harbor overlook and gives the battery a calm background value.
	var overlook_half_width := 4.3
	var wing_width := half_w - overlook_half_width + 1.0
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		var wing_x := side * (overlook_half_width + wing_width * 0.5)
		_box("BowlFasciaLoL" if side < 0.0 else "BowlFasciaLoR", Vector3(wing_width, 0.45, 0.5), Vector3(wing_x, y - 0.05, z), Color("333c57"), root)
		var suite := _box("SuiteBandL" if side < 0.0 else "SuiteBandR", Vector3(wing_width, 1.1, 1.2), Vector3(wing_x, y + 0.65, z + 0.35), Color("9a6a52"), root)
		suite.material_override = _mood_material("brick", Color("9a6a52"), 0.94, Vector3(4.0, 2.0, 2.0))
		suite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for k in range(9):
		var window_x := -16.0 + float(k) * 4.0
		if absf(window_x) < overlook_half_width + 1.0:
			continue
		_suite_window("SuiteWindow%d" % k, Vector3(window_x, y + 0.68, z - 0.28), root)
	y += 1.5
	z += 1.3
	# Upper tier: two more real 3D rows, not just texture fill. Sharing the same
	# MultiMesh batches keeps the foreground bowl dense without per-fan nodes.
	for r in range(2):
		var upper_layout := _append_plate_spectator_row(spectator_batches, y, z, half_w - 1.0, r + 3)
		spectator_count += int(upper_layout.count)
		layout_min = layout_min.min(upper_layout.minimum)
		layout_max = layout_max.max(upper_layout.maximum)
		for sample in upper_layout.samples:
			if layout_samples.size() < 12:
				layout_samples.append(sample)
		_box("SeatGapUp%d" % r, Vector3((half_w - 1.0) * 2.0, 0.1, 0.14), Vector3(0.0, y - 0.5, z - 0.03), Color("333c57"), root)
		y += 0.78
		z += 0.85
	# Roof wings cap the seating blocks without bridging across the harbor view.
	# The previous full-width slab read as a black rectangle from center field.
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		var roof_width := half_w - overlook_half_width + 2.5
		_box("PressRoofL" if side < 0.0 else "PressRoofR", Vector3(roof_width, 0.45, 3.4), Vector3(side * (overlook_half_width + roof_width * 0.5), y + 0.35, z + 0.7), Color("1f3a33"), root)
		var fascia_width := half_w - overlook_half_width + 2.5
		_box("PressFasciaL" if side < 0.0 else "PressFasciaR", Vector3(fascia_width, 0.7, 0.3), Vector3(side * (overlook_half_width + fascia_width * 0.5), y, z - 1.0), Color("172a3a"), root)
	spectator_root.set_meta("spectator_count", spectator_count)
	spectator_root.set_meta("row_count", PLATE_SPECTATOR_ROWS)
	spectator_root.set_meta("strip_recess", 0.0)
	spectator_root.set_meta("layout_bounds", AABB(layout_min, layout_max - layout_min))
	spectator_root.set_meta("layout_samples", layout_samples)
	_build_spectator_batches(spectator_root, spectator_batches, 0.70)


func _append_plate_spectator_row(batches: Dictionary, y: float, z: float, half_width: float, row: int) -> Dictionary:
	var seat_count := PLATE_SPECTATOR_SEATS_PER_ROW
	var minimum := Vector3(INF, INF, INF)
	var maximum := Vector3(-INF, -INF, -INF)
	var samples: Array[Dictionary] = []
	var count := 0
	var facing := Basis.looking_at(Vector3(0.0, 0.0, -1.0), Vector3.UP)
	for seat in range(seat_count):
		# Side aisles and a broad central overlook turn the rows into seating
		# blocks. The open middle preserves the harbor behind the live battery.
		if seat in [14, 15, 52, 53] or seat in range(29, 39):
			continue
		var seed := 300000 + row * 1000 + seat
		var step := (half_width * 2.0) / float(seat_count)
		var stagger := step * 0.5 if row % 2 == 1 else 0.0
		var jitter := (_hash01(seed * 17 + 9) - 0.5) * 0.08
		var x := clampf(-half_width + step * (float(seat) + 0.5) + stagger + jitter, -half_width + 0.24, half_width - 0.24)
		var base := Vector3(x, y - 0.42, z - 0.20)
		var depth := float(row) / 3.0
		var shirt: Color = SPECTATOR_SHIRTS[int(_hash01(seed * 5 + 1) * float(SPECTATOR_SHIRTS.size())) % SPECTATOR_SHIRTS.size()]
		var skin: Color = SPECTATOR_SKINS[int(_hash01(seed * 7 + 3) * float(SPECTATOR_SKINS.size())) % SPECTATOR_SKINS.size()]
		shirt = shirt.lerp(Color("39465c"), depth * 0.10)
		skin = skin.darkened(depth * 0.04)
		_append_spectator(batches, base, facing, shirt, skin, seed, PLATE_SPECTATOR_SCALE)
		minimum = minimum.min(base)
		maximum = maximum.max(base)
		if samples.size() < 3:
			samples.append({"base": base, "shirt": shirt, "skin": skin, "seed": seed})
		count += 1
	return {"count": count, "minimum": minimum, "maximum": maximum, "samples": samples}


func _add_crowd_row(y: float, z: float, half_width: float, seg_count: int) -> void:
	# One seated crowd row split into segments (so parts flip independently),
	# each a single row tall and facing the outfield (-z) toward the CF cam.
	var seg_w := (half_width * 2.0) / float(seg_count)
	for i in range(seg_count):
		var x := -half_width + seg_w * (float(i) + 0.5)
		_add_crowd_strip(Vector2(seg_w * 1.02, CROWD_ROW_WORLD), Vector3(x, y, z), Vector3(0.0, 0.0, -1.0), 0.0)


func _add_crowd_strip(size: Vector2, at: Vector3, face_dir: Vector3, roll: float) -> void:
	# One seeded, self-animating crowd quad. Deterministic per index so the bowl
	# is identical every build; textures are seated by _refresh_crowd_textures.
	var seed := _crowd_strips.size()
	var mat := _flat_texture_material(null, false, true)
	# Crowd quads are viewed at steep, changing angles in PlayCam. Mipmapped
	# anisotropic sampling plus blended alpha lets distant fans converge into
	# color clusters instead of re-thresholding them into red/white sparkles.
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_DEPTH_PRE_PASS
	mat.alpha_antialiasing_mode = BaseMaterial3D.ALPHA_ANTIALIASING_OFF
	# This is only a recessed density bed behind the articulated 3D fans. A low
	# alpha preserves dark seat gaps and aisle breaks so the audience reads as
	# people instead of a second crowd texture painted through their bodies.
	mat.albedo_color = Color(0.56, 0.60, 0.67, 0.18)
	mat.roughness = 1.0
	# Tile the strip so fans stay life-size: more, smaller fans on bigger quads
	# (fixes the ~30 ft giant-fan read), and multiple stacked seated rows appear
	# on taller strips.
	mat.texture_repeat = true
	mat.uv1_scale = Vector3(maxf(size.x / CROWD_TILE_WORLD, 1.0), maxf(size.y / CROWD_ROW_WORLD, 1.0), 1.0)
	var strip := _textured_quad("CrowdStrip%03d" % seed, size, at, face_dir, mat, self)
	if not is_zero_approx(roll):
		strip.rotation.z += roll
	var r1 := _hash01(seed * 3 + 1)
	var r2 := _hash01(seed * 7 + 3)
	var r3 := _hash01(seed * 11 + 5)
	var frame_a := int(r1 * 3.0) % 3
	var frame_b := (frame_a + 1 + int(r2 * 2.0)) % 3
	_crowd_strips.append({
		"material": mat,
		"frame_a": frame_a,
		"frame_b": frame_b,
		"period": 1.4 + r2 * 2.8,  # personal flip cycle 1.4..4.2s
		"phase": r3 * 8.0,
	})


func _refresh_crowd_textures() -> void:
	_crowd_calm.clear()
	for suffix in ["c0", "c1", "c2"]:
		var t := _crowd_texture_named(suffix)
		if t != null:
			_crowd_calm.append(t)
	_crowd_excited.clear()
	for suffix in ["x0", "x1"]:
		var t := _crowd_texture_named(suffix)
		if t != null:
			_crowd_excited.append(t)
	if _crowd_calm.is_empty():
		return
	# Re-seat every strip on its idle frame so a mood swap shows immediately.
	for strip in _crowd_strips:
		var mat: StandardMaterial3D = strip.material
		mat.albedo_texture = _crowd_calm[int(strip.frame_a) % _crowd_calm.size()]


func _crowd_texture_named(suffix: String) -> Texture2D:
	var path := "res://content/legacy/field/T_crowd_%s_%s.png" % [_mood, suffix]
	return load(path) as Texture2D if ResourceLoader.exists(path) else null


func _animate_crowd(delta: float) -> void:
	if _crowd_excited_timer > 0.0:
		_crowd_excited_timer = maxf(_crowd_excited_timer - delta, 0.0)
		if _crowd_excited_timer <= 0.0:
			_crowd_reaction_duration = 0.0
			_crowd_reaction_strength = 0.0

	# Thousands of connected body pieces update in batches at a stable 12 Hz.
	# Their wave is sampled from absolute animation time, so frame partitioning
	# cannot synchronize or drift individual fans.
	_crowd_motion_accumulator += maxf(delta, 0.0)
	if _crowd_motion_accumulator >= CROWD_MOTION_STEP:
		var elapsed_steps := maxi(1, int(floor(_crowd_motion_accumulator / CROWD_MOTION_STEP)))
		_crowd_motion_accumulator -= float(elapsed_steps) * CROWD_MOTION_STEP
		_crowd_motion_tick += elapsed_steps
		_update_spectator_motion()

	if _crowd_strips.is_empty():
		return
	if _crowd_excited_timer > 0.0 and not _crowd_excited.is_empty():
		for strip in _crowd_strips:
			# Excited cards retain their personal phase rather than flipping as one
			# disorienting stadium-wide sheet.
			var local_time := _anim_time + float(strip.phase) * 0.19
			var frame := int(local_time / 0.21) % _crowd_excited.size()
			(strip.material as StandardMaterial3D).albedo_texture = _crowd_excited[frame]
		return
	if _crowd_calm.is_empty():
		return
	for strip in _crowd_strips:
		var t := _anim_time + float(strip.phase)
		var half := maxf(float(strip.period) * 0.5, 0.05)
		var state := int(t / half) % 2
		var idx: int = int(strip.frame_a) if state == 0 else int(strip.frame_b)
		(strip.material as StandardMaterial3D).albedo_texture = _crowd_calm[idx % _crowd_calm.size()]


func _crowd_reaction_level() -> float:
	if _crowd_excited_timer <= 0.0 or _crowd_reaction_duration <= 0.0:
		return 0.0
	var remaining := clampf(_crowd_excited_timer / _crowd_reaction_duration, 0.0, 1.0)
	# Smooth decay prevents the audience from snapping back to seated idle.
	var eased := remaining * remaining * (3.0 - 2.0 * remaining)
	return _crowd_reaction_strength * eased


func _update_spectator_motion() -> void:
	var reaction := _crowd_reaction_level()
	var captured_sample := false
	for batch_value in _animated_spectator_batches:
		var batch: Dictionary = batch_value
		var multimesh: MultiMesh = batch.multimesh
		if multimesh == null:
			continue
		var rest_transforms: Array = batch.rest_transforms
		var motion_data: Array = batch.motion_data
		var part := String(batch.part)
		var count := mini(multimesh.instance_count, mini(rest_transforms.size(), motion_data.size()))
		for index in range(count):
			var rest: Transform3D = rest_transforms[index]
			var motion: Color = motion_data[index]
			var phase := motion.r * TAU
			var idle_rate := lerpf(0.15, 0.27, motion.g)
			var idle_wave := sin(phase + _anim_time * TAU * idle_rate)
			var side_wave := cos(phase * 0.73 + _anim_time * TAU * idle_rate * 0.61)
			var cheer_wave := maxf(0.0, sin(phase + _anim_time * TAU * (1.75 + motion.g * 0.65)))
			# Affinity deliberately spans quiet observers through exuberant jumpers.
			# A semantic reaction is therefore visible as many individual choices,
			# not a synchronized vertical sheet.
			var response := reaction * motion.a
			var jumpiness := clampf((motion.a - 0.35) / 0.65, 0.0, 1.0)
			var lift := idle_wave * 0.007 * motion.b + response * (0.012 + cheer_wave * lerpf(0.035, 0.125, jumpiness))
			if part in ["UpperArms", "Forearms"]:
				lift += response * cheer_wave * (0.032 if part == "UpperArms" else 0.050)
			var sway := side_wave * 0.008 * motion.b + response * sin(phase * 1.37 + _anim_time * TAU * 1.2) * lerpf(0.014, 0.034, jumpiness)
			var lean := idle_wave * 0.007 + response * (cheer_wave - 0.35) * lerpf(0.012, 0.032, jumpiness)
			if not captured_sample:
				_crowd_motion_sample = Vector3(sway, lift, lean)
				captured_sample = true
			var animated := rest
			animated.origin += Vector3(sway, lift, 0.0)
			animated.basis = rest.basis * Basis(Vector3.FORWARD, lean)
			multimesh.set_instance_transform(index, animated)


func _build_led_ring() -> void:
	# One emissive ribbon material rings the lower bowl behind/around the plate
	# plus a short outfield run; flash_led swaps its emission map on a result.
	_led_idle_texture = load("res://content/legacy/field/T_led_ribbon.png") as Texture2D
	if _led_idle_texture == null:
		return
	_led_material = StandardMaterial3D.new()
	# The board face carries the (dark, bright-pixel) LED texture as albedo so it
	# reads even unlit; emission uses MULTIPLY so it can NEVER blow out to white
	# (ADD + white emission was the blank-slab bug), only the lit pixels glow.
	_led_material.albedo_texture = _led_idle_texture
	_led_material.albedo_color = Color("ffffff")
	_led_material.roughness = 0.7
	_led_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_led_material.emission_enabled = true
	_led_material.emission = Color("ffffff")
	_led_material.emission_texture = _led_idle_texture
	_led_material.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	_led_material.emission_energy_multiplier = LED_IDLE_ENERGY

	# Long, thin ribbon strips (UE aspect ~7.6:1) on the backstop fascia and down
	# each line, ringing the lower bowl behind the plate.
	for side in [-1.0, 1.0]:
		for seg in range(5):
			var z := 12.0 - float(seg) * 7.0
			_textured_quad(
				"LedRibbon_%d_%d" % [int(side), seg],
				Vector2(6.6, 0.4),
				Vector3(side * 29.0, 2.7, z),
				Vector3(-side, 0.0, 0.15),
				_led_material, self)
	# Backstop ring behind the plate.
	for k in range(5):
		_textured_quad(
			"LedBackstop_%d" % k,
			Vector2(6.6, 0.4),
			Vector3((float(k) - 2.0) * 7.0, 1.72, 29.6),
			Vector3(0.0, 0.0, -1.0),
			_led_material, self)
	# Outfield ribbon run in front of the batter's-eye / scoreboard.
	for k in range(3):
		_textured_quad(
			"LedOutfield_%d" % k,
			Vector2(9.0, 0.42),
			Vector3((float(k) - 1.0) * 11.0, 3.2, -42.5),
			Vector3(0.0, 0.0, 1.0),
			_led_material, self)


func _animate_led(_delta: float) -> void:
	if _led_material == null:
		return
	if _led_flash_timer > 0.0:
		_led_flash_timer -= _delta
		if _led_material.emission_texture != _led_flash_texture:
			_led_material.emission_texture = _led_flash_texture
			_led_material.albedo_texture = _led_flash_texture
		var on := (int(_anim_time / 0.2) % 2) == 0
		_led_material.emission_energy_multiplier = 3.0 if on else 0.4
		if _led_flash_timer <= 0.0:
			_led_material.emission_texture = _led_idle_texture
			_led_material.albedo_texture = _led_idle_texture
			_led_material.emission_energy_multiplier = LED_IDLE_ENERGY
	else:
		_led_material.emission_energy_multiplier = LED_IDLE_ENERGY


func _build_wall_ads() -> void:
	# Advertising boards spaced along the outfield wall face, one per straight
	# segment, sized to that segment and canted to face the plate.
	var signs := ["center", "harryk", "navy", "red", "script", "vision"]
	var profile := ParkGeometry.fence_profile()
	for i in range(profile.size() - 1):
		var tex := load("res://content/legacy/field/T_sign_%s.png" % signs[i % signs.size()]) as Texture2D
		if tex == null:
			continue
		var a := _fence_post_world(profile[i], false)
		var b := _fence_post_world(profile[i + 1], false)
		var mid := (a + b) * 0.5
		var inward := _toward_home(mid)
		var seg_len := a.distance_to(b)
		var wall_h := (float(profile[i].height_ft) + float(profile[i + 1].height_ft)) * 0.5 * ParkGeometry.VERTICAL_WORLD_PER_FOOT
		# Size to the texture's own aspect so the artwork stays legible instead of
		# squashing into a color block.
		var tsize := tex.get_size()
		var aspect := tsize.x / maxf(tsize.y, 1.0)
		var ad_w: float = clampf(seg_len * 0.78, 3.0, 8.0)
		var ad_h: float = clampf(ad_w / aspect, 0.55, 2.2)
		var center := mid + inward * 0.18 + Vector3.UP * clampf(wall_h * 0.5, 0.9, 2.2)
		# Unshaded so the boards read clearly in day, golden, and night alike.
		var mat := _flat_texture_material(tex, true, false)
		# The quad's width axis lands along the wall tangent automatically: with
		# world up + a horizontal inward facing, the local X is the wall run.
		_textured_quad("WallAd%02d" % i, Vector2(ad_w, ad_h), center, inward, mat, self)


func _build_batters_eye() -> void:
	# Dark hitter's backdrop plus a row of evergreens on the center-field berm.
	var eye := _box("BattersEye", Vector3(18.0, 6.0, 1.2), Vector3(0.0, 3.0, -45.0), Color("0e1a14"), self)
	eye.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# T_evergreen is an opaque tile rather than a cutout, so a flat quad reads
	# as a green slab; tiered voxel pines keep a tree silhouette from every
	# camera. Just in front of the dark backdrop (toward home) so they read
	# against it instead of being occluded.
	for k in range(5):
		var x := -7.0 + float(k) * 3.5
		_build_eye_tree(k, Vector3(x, 0.0, -44.3))


func _build_eye_tree(index: int, base: Vector3) -> void:
	var tree := Node3D.new()
	tree.name = "EyeTree%d" % index
	tree.position = base
	add_child(tree)
	var grow := 0.88 + 0.24 * _hash01(index * 7 + 3)
	var trunk := _box("Trunk", Vector3(0.5, 1.2, 0.5), Vector3(0.0, 0.6, 0.0), Color("4a3524"), tree)
	trunk.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var tiers := [
		[Vector3(2.9, 1.7, 2.9), 1.85, Color("1d3a26")],
		[Vector3(2.1, 1.6, 2.1), 3.05, Color("24482e")],
		[Vector3(1.3, 1.5, 1.3), 4.15, Color("2b5636")],
	]
	for t in range(tiers.size()):
		var spec: Array = tiers[t]
		var size: Vector3 = spec[0] * grow
		var tier := _box("Tier%d" % t, size, Vector3(0.0, float(spec[1]) * grow, 0.0), spec[2], tree)
		tier.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _build_liberty_bell(board_root: Node3D) -> void:
	# Neon Liberty Bell above the scoreboard; swing_bell() drives the pendulum.
	var tex := load("res://content/legacy/field/T_bell_neon.png") as Texture2D
	if tex == null:
		return
	_bell_pivot = Node3D.new()
	_bell_pivot.name = "LibertyBellPivot"
	_bell_pivot.position = Vector3(8.0, 7.6, 0.9)
	board_root.add_child(_bell_pivot)
	var mat := _flat_texture_material(tex, true, true)
	mat.emission_enabled = true
	mat.emission = Color("ffffff")
	mat.emission_texture = tex
	mat.emission_operator = BaseMaterial3D.EMISSION_OP_MULTIPLY
	mat.emission_energy_multiplier = 2.0
	# Hang the bell below the pivot so roll reads as a pendulum swing.
	_textured_quad("LibertyBell", Vector2(1.5, 1.75), Vector3(0.0, -0.95, 0.0), Vector3(0.0, 0.0, 1.0), mat, _bell_pivot)


func _animate_bell(_delta: float) -> void:
	if _bell_pivot == null:
		return
	if _bell_timer > 0.0:
		_bell_timer -= _delta
		var t := 5.0 - _bell_timer
		_bell_pivot.rotation.z = deg_to_rad(16.0) * exp(-t * 0.7) * sin(t * TAU * 1.3)
		if _bell_timer <= 0.0:
			_bell_pivot.rotation.z = 0.0


func _hash01(n: int) -> float:
	# Deterministic integer hash -> [0,1); stable per strip so the bowl looks
	# identical every build (no Math.random, matching the seeded UE crowd).
	var h := n * 374761393 + 668265263
	h = (h ^ (h >> 13)) * 1274126177
	h = h ^ (h >> 16)
	return float(h & 0xffffff) / float(0x1000000)


func _flat_texture_material(tex: Texture2D, unshaded: bool, alpha_scissor: bool) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_texture = tex
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	if unshaded:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if alpha_scissor:
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		material.alpha_scissor_threshold = 0.5
	return material


func _textured_quad(label: String, size: Vector2, at: Vector3, face_dir: Vector3, material: Material, parent: Node) -> MeshInstance3D:
	var quad := QuadMesh.new()
	quad.size = size
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = quad
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var dir := face_dir.normalized()
	if dir.length() < 0.001:
		dir = Vector3(0.0, 0.0, 1.0)
	# QuadMesh faces +Z; looking_at aims -Z at the target, so aim at -dir to put
	# the visible face along face_dir. Transform math (not look_at()) keeps this
	# working when the stadium is built before entering the tree.
	instance.transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), at)
	parent.add_child(instance)
	return instance


func _build_home_backstop() -> void:
	# Depth band behind home plate, kept clear of the cameras: the batting
	# camera parks at z = 27 (ortho, ~11 world units wide around x = 6), so
	# the central wall sits behind that plane at z = 30.5, the flank pieces
	# stay outside |x| = 12.5, and the z = 26..28 central corridor is empty.
	var root := Node3D.new()
	root.name = "HomeBackstop"
	add_child(root)
	var brick := _mood_material("brick", Color("96543e"), 0.96, Vector3(6.0, 3.0, 6.0))
	var seats_mat := _mood_material("seats", Color("8ea0bd"), 0.9, Vector3(7.0, 2.0, 1.0))
	var wall_specs := [
		[Vector3(0.0, 0.6, 30.5), Vector3(40.0, 1.2, 0.8)],
		[Vector3(-19.25, 0.6, 24.5), Vector3(13.5, 1.2, 0.8)],
		[Vector3(19.25, 0.6, 24.5), Vector3(13.5, 1.2, 0.8)],
		[Vector3(-12.9, 0.6, 27.5), Vector3(0.8, 1.2, 6.8)],
		[Vector3(12.9, 0.6, 27.5), Vector3(0.8, 1.2, 6.8)],
	]
	for i in range(wall_specs.size()):
		var spec: Array = wall_specs[i]
		var wall := _box("BackstopWall%d" % i, spec[1], spec[0], Color("96543e"), root)
		wall.material_override = brick

	# Oxidized-steel rail along each flank knee wall top; the central band
	# carries a mustard-and-cream trim cap instead.
	var rail_color := Color("1f3a33")
	_box("BackstopRail1", Vector3(13.5, 0.14, 0.16), Vector3(-19.25, 1.32, 24.5), rail_color, root)
	_box("BackstopRail2", Vector3(13.5, 0.14, 0.16), Vector3(19.25, 1.32, 24.5), rail_color, root)

	# Layered concourse facade on the central band. The pitching camera is a
	# shallow downward ortho: at z = 30..34 it only crops roughly y 0..2.1, so
	# every authored layer lives inside that window. Front-to-back stacking
	# keeps each layer proud of the surface behind it (no coplanar z-fights):
	# bunting 29.72, pilasters/lamps 29.9, opening panels 29.96, wall face
	# 30.1, trim atop the wall, pennants and stepped rows behind.
	_box("BackstopTrim", Vector3(40.0, 0.26, 0.6), Vector3(0.0, 1.32, 30.45), Color("ffca52"), root)
	_box("BackstopCap", Vector3(40.0, 0.14, 0.72), Vector3(0.0, 1.51, 30.45), Color("f3e7cc"), root)
	for k in range(7):
		var opening_x := (float(k) - 3.0) * 4.4
		_box("ConcourseOpening%d" % k, Vector3(2.2, 0.85, 0.2), Vector3(opening_x, 0.52, 29.96), Color("101a2e"), root)
	for k in range(8):
		var post_x := -15.4 + float(k) * 4.4
		_box("ConcoursePost%d" % k, Vector3(0.5, 1.3, 0.26), Vector3(post_x, 0.65, 29.9), rail_color, root)
		var wall_lamp := _box("WallLamp%d" % k, Vector3(0.34, 0.2, 0.3), Vector3(post_x, 1.42, 29.86), Color("fff6c4"), root)
		wall_lamp.material_override = _get_lamp_material()
		wall_lamp.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Team-color pennants along the wall top read just under the crop ceiling.
	var pennant_palette := [Color("ff6b5e"), Color("44d7b6"), Color("ffd166")]
	for k in range(5):
		var pole_x := -12.0 + float(k) * 6.0
		_box("PennantPole%d" % k, Vector3(0.09, 0.85, 0.09), Vector3(pole_x, 1.9, 30.45), Color("26324e"), root)
		_box("Pennant%d" % k, Vector3(0.85, 0.34, 0.1), Vector3(pole_x + 0.5, 2.05, 30.4), pennant_palette[k % 3], root)

	# Stepped front seating rows just behind the wall, carrying the seats texture
	# with steel rail lines.
	for step in range(3):
		var row_y := 1.28 + float(step) * 0.3
		var row_z := 31.4 + float(step) * 1.1
		var row := _box("BackstopRow%d" % step, Vector3(33.0, 0.4, 1.0), Vector3(0.0, row_y, row_z), Color("8ea0bd"), root)
		row.material_override = seats_mat
		row.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_box("BackstopRowRail%d" % step, Vector3(33.0, 0.07, 0.1), Vector3(0.0, row_y + 0.26, row_z - 0.45), Color("9fb4c4"), root)

	# The capped, layered crowd bowl the CF broadcast cam actually frames.
	_build_plate_crowd()

	# Tricolor bunting hangs proud of the field-facing wall faces: swags over
	# each central concourse opening plus three per flank knee wall.
	var slot := 0
	for k in range(7):
		_bunting("Bunting%02d" % slot, Vector3((float(k) - 3.0) * 4.4, 0.95, 29.72), 2.7, 0.70, root)
		slot += 1
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		for k in range(3):
			_bunting("Bunting%02d" % slot, Vector3(side * (14.5 + 4.0 * float(k)), 0.85, 23.95), 2.6, 0.65, root)
			slot += 1

	# Stepped home-stand silhouettes with a canopy on each flank.
	for side_value in [-1.0, 1.0]:
		var side: float = side_value
		for step in range(4):
			var seat := _box(
				"HomeStand", Vector3(8.0 + float(step) * 1.2, 0.9, 9.5),
				Vector3(side * (17.0 + float(step) * 0.9), 0.55 + float(step) * 0.85, 31.0 + float(step) * 1.7),
				Color("8ea0bd"), root)
			seat.material_override = seats_mat
			seat.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_box("HomeCanopy", Vector3(12.0, 0.3, 11.0), Vector3(side * 19.5, 4.4, 33.5), rail_color, root)
		# Fascia lip so the canopy reads as a roof over the stand, not a slab.
		_box("HomeCanopyFascia", Vector3(12.0, 0.55, 0.3), Vector3(side * 19.5, 4.15, 28.15), Color("172a3a"), root)
		_box("CanopyPost", Vector3(0.4, 3.4, 0.4), Vector3(side * 14.0, 2.6, 36.5), Color("26324e"), root)


func _get_lamp_material() -> StandardMaterial3D:
	if _lamp_material == null:
		_lamp_material = StandardMaterial3D.new()
		# Dark housing so the lamp banks read as structure (not blank white slabs)
		# in day/golden; the warm emission — driven bright only at night by the
		# MOODS lamp_energy — is what makes them glow after dark.
		_lamp_material.albedo_color = Color("2a251b")
		_lamp_material.roughness = 0.55
		_lamp_material.emission_enabled = true
		_lamp_material.emission = Color("fff3c0")
		_lamp_material.emission_energy_multiplier = 0.25
	return _lamp_material


func _suite_window(label: String, at: Vector3, parent: Node) -> Node3D:
	var root := Node3D.new()
	root.name = label
	root.position = at
	parent.add_child(root)
	var frame := _box("Frame", Vector3(2.4, 0.55, 0.18), Vector3.ZERO, Color("172536"), root)
	frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var pane_material := StandardMaterial3D.new()
	pane_material.albedo_color = Color("78909a")
	pane_material.roughness = 0.52
	pane_material.emission_enabled = true
	pane_material.emission = Color("9fb6ae")
	pane_material.emission_energy_multiplier = 0.10
	for pane_index in range(3):
		var pane := _box(
			"Pane%d" % pane_index,
			Vector3(0.62, 0.34, 0.07),
			Vector3(-0.74 + float(pane_index) * 0.74, 0.0, -0.115),
			Color("78909a"),
			root,
		)
		pane.material_override = pane_material
		pane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


func _bunting(label: String, at: Vector3, width: float, height: float, parent: Node) -> MeshInstance3D:
	# Faceted half-round patriotic bunting: a red outer scallop, cream middle,
	# and navy gathered center. Twelve segments retain deliberate pixel planes
	# while removing the blank rectangular-panel read of the old placeholders.
	var mesh := ImmediateMesh.new()
	var bands := [
		{"outer": 1.0, "inner": 0.70, "color": Color("c94f4b")},
		{"outer": 0.70, "inner": 0.40, "color": Color("eee4cf")},
		{"outer": 0.40, "inner": 0.0, "color": Color("354f80")},
	]
	var segments := 12
	for band_value in bands:
		var band: Dictionary = band_value
		var material := StandardMaterial3D.new()
		material.albedo_color = band.color
		material.roughness = 0.88
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
		for segment in range(segments):
			var a0 := lerpf(PI, TAU, float(segment) / float(segments))
			var a1 := lerpf(PI, TAU, float(segment + 1) / float(segments))
			var outer0 := Vector3(cos(a0) * width * 0.5 * float(band.outer), height * 0.5 + sin(a0) * height * float(band.outer), 0.0)
			var outer1 := Vector3(cos(a1) * width * 0.5 * float(band.outer), height * 0.5 + sin(a1) * height * float(band.outer), 0.0)
			var inner0 := Vector3(cos(a0) * width * 0.5 * float(band.inner), height * 0.5 + sin(a0) * height * float(band.inner), -0.006)
			var inner1 := Vector3(cos(a1) * width * 0.5 * float(band.inner), height * 0.5 + sin(a1) * height * float(band.inner), -0.006)
			for vertex in [outer0, outer1, inner1, outer0, inner1, inner0]:
				mesh.surface_set_normal(Vector3(0.0, 0.0, -1.0))
				mesh.surface_add_vertex(vertex)
		mesh.surface_end()
	var instance := MeshInstance3D.new()
	instance.name = label
	instance.mesh = mesh
	instance.position = at
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
	return instance


func _beam_between(label: String, a: Vector3, b: Vector3, width: float, height: float, color: Color) -> MeshInstance3D:
	var midpoint := (a + b) * 0.5
	var length := a.distance_to(b)
	var beam := _box(label, Vector3(width, height, length), midpoint, color, self)
	# Orient with transform math rather than look_at(), which errors when the
	# stadium is built before entering the scene tree.
	beam.transform = Transform3D(Basis.looking_at((b - a).normalized(), Vector3.UP), midpoint)
	return beam


func _build_fence_segment(index: int, a_post: Dictionary, b_post: Dictionary) -> void:
	var a_bottom := _fence_post_world(a_post, false)
	var b_bottom := _fence_post_world(b_post, false)
	var a_top := _fence_post_world(a_post, true)
	var b_top := _fence_post_world(b_post, true)
	var mesh := ImmediateMesh.new()
	var material := _mood_material(
		"wallpad",
		Color("7fbfb1") if index % 2 == 0 else Color("6aa99f"),
		0.85,
		Vector3(2.0, 2.0, 2.0),
	)
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES, material)
	var normal := (b_bottom - a_bottom).cross(Vector3.UP).normalized()
	var length := a_bottom.distance_to(b_bottom)
	var vertices := [a_bottom, b_bottom, b_top, a_bottom, b_top, a_top]
	var uvs := [Vector2(0, 1), Vector2(length * 0.2, 1), Vector2(length * 0.2, 0), Vector2(0, 1), Vector2(length * 0.2, 0), Vector2(0, 0)]
	for vertex_index in range(vertices.size()):
		mesh.surface_set_normal(normal)
		mesh.surface_set_uv(uvs[vertex_index])
		mesh.surface_add_vertex(vertices[vertex_index])
	mesh.surface_end()
	var wall := MeshInstance3D.new()
	wall.name = "Wall%02d" % index
	wall.mesh = mesh
	add_child(wall)
	_beam_between("WallCap%02d" % index, a_top, b_top, 0.48, 0.22, Color("ffca52"))


func _fence_post_world(post: Dictionary, include_height: bool) -> Vector3:
	return C.HOME_PLATE + Vector3(
		float(post.x_ft) * ParkGeometry.HORIZONTAL_WORLD_PER_FOOT,
		float(post.height_ft) * ParkGeometry.VERTICAL_WORLD_PER_FOOT if include_height else 0.0,
		-float(post.y_ft) * ParkGeometry.HORIZONTAL_WORLD_PER_FOOT,
	)


func _box(label: String, size: Vector3, at: Vector3, color: Color, parent: Node) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.name = label
	var mesh := BoxMesh.new()
	mesh.size = size
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _material(color)
	parent.add_child(instance)
	return instance


func _material(color: Color, roughness := 0.88, emission := Color.TRANSPARENT) -> StandardMaterial3D:
	var key := "%s/%0.2f/%s" % [color.to_html(), roughness, emission.to_html()]
	if _materials.has(key):
		return _materials[key]
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	material.metallic = 0.0
	if emission.a > 0.0:
		material.emission_enabled = true
		material.emission = emission
		material.emission_energy_multiplier = 1.7
	_materials[key] = material
	return material


func _mood_material(kind: String, tint: Color, roughness: float, uv_scale: Vector3) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = tint
	material.albedo_texture = _mood_texture(kind, _mood)
	material.roughness = roughness
	material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
	material.texture_repeat = true
	material.uv1_scale = uv_scale
	_mood_materials.append({"kind": kind, "material": material})
	return material


func _mood_texture(kind: String, mood: String) -> Texture2D:
	var path := "res://content/legacy/field/T_%s_%s.png" % [kind, mood]
	return load(path) as Texture2D if ResourceLoader.exists(path) else null
