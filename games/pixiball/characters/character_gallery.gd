@tool
extends Node3D

const BALLPLAYER_SCENE = preload("res://characters/ballplayer_actor.tscn")

const PLAYER_SPECS := [
	{
		"seed": 101,
		"role": "pitcher",
		"number": 34,
		"mark": "P",
		"build": "power",
		"throws": "right",
		"primary_color": "#173f73",
		"secondary_color": "#f1ead9",
		"accent_color": "#e2b447",
		"action": "pitch",
	},
	{
		"seed": 202,
		"role": "batter",
		"number": 7,
		"mark": "V",
		"build": "speed",
		"bats": "left",
		"throws": "right",
		"helmet": true,
		"bat": true,
		"glove": false,
		"primary_color": "#9f2439",
		"secondary_color": "#f2eee3",
		"accent_color": "#e9b64e",
		"action": "swing",
	},
	{
		"seed": 303,
		"role": "catcher",
		"number": 12,
		"mark": "B",
		"build": "power",
		"throws": "right",
		"primary_color": "#17604e",
		"secondary_color": "#e7debc",
		"accent_color": "#e46c35",
		"action": "catch",
	},
	{
		"seed": 9001,
		"role": "umpire",
		"number": 0,
		"mark": "",
		"build": "power",
		"throws": "right",
		"glove": false,
		"primary_color": "#151922",
		"secondary_color": "#252c38",
		"accent_color": "#d9e2ea",
		"pants_color": "#282d35",
		"action": "field_ready",
	},
	{
		"seed": 404,
		"role": "fielder",
		"number": 18,
		"mark": "S",
		"build": "balanced",
		"throws": "left",
		"primary_color": "#5b3384",
		"secondary_color": "#e7e6e0",
		"accent_color": "#56b2c8",
		"action": "field_throw",
	},
	{
		"seed": 505,
		"role": "runner",
		"number": 11,
		"mark": "R",
		"build": "speed",
		"bats": "right",
		"throws": "left",
		"helmet": true,
		"bat": false,
		"glove": false,
		"primary_color": "#b4491f",
		"secondary_color": "#f0e6cf",
		"accent_color": "#efbd55",
		"action": "slide",
	},
]

var _generated: Node3D
var _players: Array[BallplayerActor] = []
var _time := 0.0
var _action_index := 0
var _action_cycle := ["idle", "field_ready", "run", "pitch", "field_throw", "swing", "catch", "slide", "celebrate"]


func _ready() -> void:
	_build_gallery()
	set_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		for player in _players:
			player._physics_process(delta)
	_time += delta
	if _time < 2.25:
		return
	_time = 0.0
	_action_index = (_action_index + 1) % _action_cycle.size()
	for index in range(_players.size()):
		var player = _players[index]
		var action: String = _action_cycle[(_action_index + index) % _action_cycle.size()]
		player.set_motion(Vector3(0.0, 0.0, -3.4) if action == "run" else Vector3.ZERO)
		player.play_action(action)


func _build_gallery() -> void:
	if is_instance_valid(_generated):
		_generated.free()
	_generated = Node3D.new()
	_generated.name = "GeneratedGallery"
	add_child(_generated)
	_players.clear()

	_build_stage()
	var spacing := 1.18
	for index in range(PLAYER_SPECS.size()):
		var spec: Dictionary = PLAYER_SPECS[index].duplicate(true)
		var action := String(spec.get("action", "idle"))
		spec.erase("action")
		var player := BALLPLAYER_SCENE.instantiate() as BallplayerActor
		player.name = "Ballplayer%02d" % (index + 1)
		player.position = Vector3((float(index) - (PLAYER_SPECS.size() - 1.0) * 0.5) * spacing, 0.03, 0.0)
		player.configure(spec)
		_generated.add_child(player)
		player.set_facing(Vector3(0.0, 0.0, -1.0))
		player.set_motion(Vector3(0.0, 0.0, -3.4) if action == "run" else Vector3.ZERO)
		player.play_action(action)
		_players.append(player)


func _build_stage() -> void:
	var environment := WorldEnvironment.new()
	environment.name = "Environment"
	var world_environment := Environment.new()
	world_environment.background_mode = Environment.BG_COLOR
	world_environment.background_color = Color("18212c")
	world_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world_environment.ambient_light_color = Color("9fb5cd")
	world_environment.ambient_light_energy = 0.72
	world_environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.environment = world_environment
	_generated.add_child(environment)

	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation_degrees = Vector3(-48.0, -32.0, 0.0)
	key_light.light_color = Color("fff0d2")
	key_light.light_energy = 1.85
	key_light.shadow_enabled = true
	_generated.add_child(key_light)

	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(-4.0, 3.8, -4.0)
	fill.omni_range = 12.0
	fill.light_color = Color("79a8e8")
	fill.light_energy = 3.0
	fill.shadow_enabled = false
	_generated.add_child(fill)

	var floor_mesh := BoxMesh.new()
	floor_mesh.size = Vector3(9.5, 0.12, 3.4)
	var floor_material := StandardMaterial3D.new()
	floor_material.albedo_color = Color("536b49")
	floor_material.roughness = 0.94
	floor_mesh.material = floor_material
	var floor := MeshInstance3D.new()
	floor.name = "GalleryFloor"
	floor.mesh = floor_mesh
	floor.position = Vector3(0.0, -0.07, 0.0)
	_generated.add_child(floor)

	for stripe in [-1.5, -0.5, 0.5, 1.5]:
		var stripe_mesh := BoxMesh.new()
		stripe_mesh.size = Vector3(9.5, 0.012, 0.035)
		var stripe_material := StandardMaterial3D.new()
		stripe_material.albedo_color = Color("d7d2b8")
		stripe_material.roughness = 0.90
		stripe_mesh.material = stripe_material
		var line := MeshInstance3D.new()
		line.name = "ChalkLine"
		line.mesh = stripe_mesh
		line.position = Vector3(0.0, 0.002, stripe)
		_generated.add_child(line)

	var camera := Camera3D.new()
	camera.name = "GalleryCamera"
	camera.position = Vector3(0.0, 1.85, -7.2)
	camera.fov = 38.0
	camera.current = true
	_generated.add_child(camera)
	camera.look_at(Vector3(0.0, 1.02, 0.0), Vector3.UP)
