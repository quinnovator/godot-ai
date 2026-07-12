extends SceneTree

const MODEL_PATH := "res://assets/models/ballplayer/ballplayer.glb"
const ACTOR_SCENE_PATH := "res://characters/ballplayer_actor.tscn"

const REQUIRED_BONES := [
	"root", "hips", "spine", "chest", "neck", "head",
	"clavicle.L", "upper_arm.L", "forearm.L", "hand.L",
	"clavicle.R", "upper_arm.R", "forearm.R", "hand.R",
	"thigh.L", "shin.L", "foot.L", "toe.L",
	"thigh.R", "shin.R", "foot.R", "toe.R",
	"socket_head", "socket_chest", "socket_glove", "socket_catch",
	"socket_bat", "socket_ball", "socket_bat_tip", "socket_foot.L", "socket_foot.R",
]

const REQUIRED_MESHES := [
	"Body_Skinned", "Jersey_Skinned", "Pants_Skinned", "Socks_Skinned",
	"Hair_Skinned", "Face_Details_Skinned", "Cap_Skinned", "Cleats_Skinned",
	"Glove_Skinned", "Bat_Skinned", "Jersey_Collar", "Jersey_Placket",
	"Jersey_Cuff_L", "Jersey_Cuff_R", "Uniform_Belt", "Uniform_Belt_Buckle",
	"JerseyIdentityFront", "JerseyIdentityBack", "Gear_BattingHelmet",
	"Gear_CatcherMask", "Gear_CatcherChest", "Gear_CatcherShinL",
	"Gear_CatcherShinR", "Gear_UmpireMask", "Gear_UmpireChest",
]

const REQUIRED_MATERIALS := [
	"TEAM_Primary", "TEAM_Secondary", "TEAM_Accent", "MAT_Skin",
	"MAT_Hair", "MAT_EyeWhite", "MAT_Iris", "MAT_Pants", "MAT_Jersey",
	"MAT_Leather", "MAT_Bat", "MAT_Cleat", "MAT_Metal",
]

const REQUIRED_ACTIONS := [
	"idle", "run", "pitch", "swing", "catch",
	"field_ready", "field_throw", "celebrate", "slide",
]
const REQUIRED_SOCKETS := [
	"head", "chest", "left_hand", "right_hand", "glove", "catch",
	"throw_hand", "ball_release", "bat_grip", "bat_tip", "left_foot", "right_foot", "feet",
	"left_shin", "right_shin",
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	_expect(packed != null, "rigged GLB did not load as PackedScene")
	if packed == null:
		_finish()
		return

	var model := packed.instantiate()
	root.add_child(model)
	await process_frame

	var skeletons: Array[Skeleton3D] = []
	var animation_players: Array[AnimationPlayer] = []
	var meshes: Array[MeshInstance3D] = []
	_collect(model, skeletons, animation_players, meshes)
	_expect(skeletons.size() == 1, "expected one shared Skeleton3D, got %d" % skeletons.size())
	_expect(animation_players.size() == 1, "expected one AnimationPlayer, got %d" % animation_players.size())
	_expect(meshes.size() == 35, "expected 35 authored Blender mesh objects, got %d" % meshes.size())

	if not skeletons.is_empty():
		var skeleton := skeletons[0]
		_expect(skeleton.get_bone_count() == 31, "expected 31 rig bones, got %d" % skeleton.get_bone_count())
		for bone_name in REQUIRED_BONES:
			_expect(skeleton.find_bone(bone_name) >= 0, "missing rig bone %s" % bone_name)

	if not animation_players.is_empty():
		var player := animation_players[0]
		var action_signatures: Dictionary = {}
		for action in REQUIRED_ACTIONS:
			_expect(player.has_animation(action), "missing imported action %s" % action)
			if player.has_animation(action):
				var animation := player.get_animation(action)
				_expect(animation.get_track_count() >= 22, "action %s has too few skeletal tracks" % action)
				_expect(animation.length >= 0.75, "action %s is unexpectedly short" % action)
				if action == "pitch":
					_expect(animation.length >= 1.40, "pitch no longer contains the full authored delivery")
					_expect(_max_track_key_count(animation) >= 18, "pitch lost its frame-reviewed biomechanical beats")
				action_signatures[action] = _animation_signature(animation)
		if action_signatures.size() == REQUIRED_ACTIONS.size():
			_expect(action_signatures.field_throw != action_signatures.pitch, "field_throw duplicates the mound delivery")
			_expect(action_signatures.celebrate != action_signatures.catch, "celebrate duplicates the catch clip")
			_expect(action_signatures.slide != action_signatures.run, "slide duplicates the run clip")
			_expect(action_signatures.field_ready != action_signatures.idle, "field_ready duplicates the idle clip")

	var mesh_names: Array[String] = []
	var material_names: Dictionary = {}
	var total_vertices := 0
	var blended_vertices := 0
	var body_bounds := AABB()
	var has_body_bounds := false
	var pbr_textured_surfaces := 0
	for mesh_instance in meshes:
		mesh_names.append(String(mesh_instance.name))
		_expect(mesh_instance.skin != null, "%s is not assigned to the shared skin" % mesh_instance.name)
		_expect(mesh_instance.scale.is_equal_approx(Vector3.ONE), "%s has non-unit object scale" % mesh_instance.name)
		if mesh_instance.mesh == null:
			continue
		if mesh_instance.name == "Body_Skinned":
			body_bounds = mesh_instance.global_transform * mesh_instance.get_aabb()
			has_body_bounds = true
		for surface in range(mesh_instance.mesh.get_surface_count()):
			total_vertices += mesh_instance.mesh.surface_get_array_len(surface)
			blended_vertices += _count_blended_vertices(mesh_instance.mesh, surface)
			var material := mesh_instance.mesh.surface_get_material(surface)
			if material != null:
				material_names[material.resource_name] = true
				if material is BaseMaterial3D:
					var pbr := material as BaseMaterial3D
					if pbr.normal_texture != null or pbr.roughness_texture != null:
						pbr_textured_surfaces += 1
	for mesh_name in REQUIRED_MESHES:
		_expect(mesh_name in mesh_names, "missing logical mesh %s" % mesh_name)
	for material_name in REQUIRED_MATERIALS:
		_expect(material_names.has(material_name), "missing material slot %s" % material_name)
	_expect(total_vertices > 8000, "asset geometry is below the production detail floor")
	_expect(blended_vertices > 500, "asset has too few multi-weight deformation vertices: %d" % blended_vertices)
	_expect(pbr_textured_surfaces > 0, "authored cloth lost its PBR normal/roughness maps")
	_expect(has_body_bounds, "authored body did not produce bounds")
	if has_body_bounds:
		_expect(body_bounds.position.y >= -0.02 and body_bounds.position.y <= 0.03, "body feet are not grounded: %s" % body_bounds)
		_expect(body_bounds.size.y >= 1.78 and body_bounds.size.y <= 1.90, "body height is outside contract: %s" % body_bounds.size.y)
		# This includes the lowered arms and hands, not just the torso.
		_expect(body_bounds.size.x >= 0.82 and body_bounds.size.x <= 0.98, "body span is outside the athletic silhouette contract: %s" % body_bounds.size.x)
		_expect(body_bounds.size.y / body_bounds.size.x >= 1.85, "body span is not proportionally athletic: %s" % body_bounds)

	var actor_scene := load(ACTOR_SCENE_PATH) as PackedScene
	_expect(actor_scene != null, "BallplayerActor scene did not load")
	if actor_scene != null:
		var actor = actor_scene.instantiate()
		actor.configure({
			"seed": 20260710,
			"role": "batter",
			"number": 27,
			"build": "power",
			"bats": "left",
			"throws": "right",
			"bat": true,
			"glove": false,
			"primary_color": Color("813348"),
			"secondary_color": Color("e8dfcb"),
			"accent_color": Color("dfad3e"),
		})
		root.add_child(actor)
		await process_frame
		_expect(not actor.is_using_fallback(), "BallplayerActor reported a removed fallback path")
		_expect(actor.get_model_kind() == "rigged_glb", "BallplayerActor reported the wrong model kind")
		for socket_name in REQUIRED_SOCKETS:
			_expect(_is_finite_vector(actor.get_socket_position(socket_name)), "socket %s is not finite" % socket_name)
		_expect(actor.get_socket_position("bat_tip").distance_to(actor.get_socket_position("bat_grip")) > 0.50, "bat sockets are not separated")
		var actor_meshes: Array[MeshInstance3D] = []
		_collect_meshes(actor, actor_meshes)
		var bat := _mesh_named(actor_meshes, "Bat_Skinned")
		var glove := _mesh_named(actor_meshes, "Glove_Skinned")
		_expect(is_instance_valid(bat) and bat.visible, "batter did not enable imported bat")
		_expect(is_instance_valid(glove) and not glove.visible, "batter did not hide imported glove")
		_expect(_active_material_color(actor_meshes, "TEAM_Primary").is_equal_approx(Color("813348")), "primary team material override failed")
		_expect(_authored_pbr_surface_count(actor_meshes) > 0, "actor did not preserve authored PBR materials")
		_expect(_mesh_named(actor_meshes, "JerseyIdentityFront") != null, "actor lost the authored front identity surface")
		_expect(_mesh_named(actor_meshes, "JerseyIdentityBack") != null, "actor lost the authored back identity surface")

		var started: Array[String] = []
		var markers: Array[String] = []
		actor.action_started.connect(func(action_name: String) -> void: started.append(action_name))
		actor.action_marker.connect(func(action_name: String, marker_name: String) -> void: markers.append("%s:%s" % [action_name, marker_name]))
		actor.play_action("pitch")
		_expect(actor.get_current_action() == "pitch", "pitch did not become current action")
		var imported_player := _first_animation_player(actor)
		_expect(imported_player != null, "actor lost its imported AnimationPlayer")
		_expect("pitch" in started, "actor did not emit action_started")
		if imported_player != null:
			imported_player.advance(0.82)
			actor._physics_process(0.82)
			_expect(not "pitch:ball_release" in markers, "pitch marker fired before the authored release frame")
			imported_player.advance(0.08)
			actor._physics_process(0.08)
		_expect("pitch:ball_release" in markers, "actor did not emit imported pitch marker")

		var rigged_root := actor.get_node_or_null("RiggedBallplayer") as Node3D
		actor.play_action("swing")
		_expect(is_instance_valid(rigged_root) and rigged_root.scale.x < 0.0, "left-handed swing did not mirror the production model")
		actor.play_action("throw")
		_expect(actor.get_current_action() == "throw", "throw compatibility action did not activate")
		_expect(imported_player != null and String(imported_player.current_animation) == "field_throw", "throw did not select the dedicated field_throw clip")
		_expect(is_instance_valid(rigged_root) and rigged_root.scale.x > 0.0, "right-handed field throw did not restore throwing-hand orientation")
		if imported_player != null:
			imported_player.advance(0.60)
			actor._physics_process(0.60)
		_expect("throw:ball_release" in markers, "dedicated field throw did not emit ball_release")

		actor.play_action("celebrate")
		if imported_player != null:
			imported_player.advance(0.86)
			actor._physics_process(0.86)
		_expect("celebrate:celebration_peak" in markers, "celebration peak marker was not emitted")

		actor.play_action("slide")
		if imported_player != null:
			imported_player.advance(0.78)
			actor._physics_process(0.78)
		_expect("slide:base_contact" in markers, "slide base-contact marker was not emitted")
		for action in ["field_ready", "field_throw", "slide"]:
			_expect(action in actor.get_available_actions(), "actor omitted action %s from its public contract" % action)
		actor.play_action("field_ready")
		actor.set_motion(Vector3.ZERO)
		_expect(actor.get_current_action() == "field_ready", "stationary motion input cancelled field_ready")
		actor.set_motion(Vector3(0.0, 0.0, -3.2))
		_expect(actor.get_current_action() == "run", "field_ready did not transition to run when motion began")
		actor.set_motion(Vector3.ZERO)

		var left_thrower = actor_scene.instantiate()
		left_thrower.configure({"seed": 77, "role": "fielder", "throws": "left", "build": "balanced"})
		root.add_child(left_thrower)
		await process_frame
		left_thrower.play_action("field_throw")
		var left_root := left_thrower.get_node_or_null("RiggedBallplayer") as Node3D
		_expect(is_instance_valid(left_root) and left_root.scale.x < 0.0, "left-handed field throw was not mirrored")

		var signature: String = actor.get_generation_signature()
		var duplicate = actor_scene.instantiate()
		duplicate.configure({
			"seed": 20260710,
			"role": "batter",
			"number": 27,
			"build": "power",
			"bats": "left",
			"throws": "right",
		})
		_expect(duplicate.get_generation_signature() == signature, "same actor identity produced a different signature")
		duplicate.free()

	_finish()


func _collect(node: Node, skeletons: Array[Skeleton3D], players: Array[AnimationPlayer], meshes: Array[MeshInstance3D]) -> void:
	if node is Skeleton3D:
		skeletons.append(node)
	elif node is AnimationPlayer:
		players.append(node)
	elif node is MeshInstance3D:
		meshes.append(node)
	for child in node.get_children():
		_collect(child, skeletons, players, meshes)


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		output.append(node)
	for child in node.get_children():
		_collect_meshes(child, output)


func _mesh_named(meshes: Array[MeshInstance3D], wanted: String) -> MeshInstance3D:
	for mesh_instance in meshes:
		if mesh_instance.name == wanted:
			return mesh_instance
	return null


func _active_material_color(meshes: Array[MeshInstance3D], wanted: String) -> Color:
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface)
			if material == null or material.resource_name != wanted:
				continue
			if material is ShaderMaterial:
				var color: Variant = (material as ShaderMaterial).get_shader_parameter("base_color")
				if color is Color:
					return color
			elif material is BaseMaterial3D:
				return (material as BaseMaterial3D).albedo_color
	return Color.TRANSPARENT


func _authored_pbr_surface_count(meshes: Array[MeshInstance3D]) -> int:
	var count := 0
	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		for surface in range(mesh_instance.mesh.get_surface_count()):
			var material := mesh_instance.get_active_material(surface) as BaseMaterial3D
			if material != null and (material.normal_texture != null or material.roughness_texture != null):
				count += 1
	return count


func _max_track_key_count(animation: Animation) -> int:
	var result := 0
	for track in range(animation.get_track_count()):
		result = maxi(result, animation.track_get_key_count(track))
	return result


func _count_blended_vertices(mesh: Mesh, surface: int) -> int:
	var arrays := mesh.surface_get_arrays(surface)
	if arrays.size() <= Mesh.ARRAY_WEIGHTS:
		return 0
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var vertex_count: int = mesh.surface_get_array_len(surface)
	if vertex_count <= 0 or weights.is_empty() or weights.size() % vertex_count != 0:
		return 0
	var stride: int = weights.size() / vertex_count
	var result := 0
	for vertex in range(vertex_count):
		var influences := 0
		for slot in range(stride):
			if weights[vertex * stride + slot] > 0.01:
				influences += 1
		if influences >= 2:
			result += 1
	return result


func _animation_signature(animation: Animation) -> String:
	var signature := "%.6f" % animation.length
	for track in range(animation.get_track_count()):
		signature += "|%s:%d" % [animation.track_get_path(track), animation.track_get_key_count(track)]
		for key in range(animation.track_get_key_count(track)):
			signature += "@%.6f=%s" % [animation.track_get_key_time(track, key), str(animation.track_get_key_value(track, key))]
	return signature


func _first_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _first_animation_player(child)
		if found != null:
			return found
	return null


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _is_finite_vector(value: Vector3) -> bool:
	return is_finite(value.x) and is_finite(value.y) and is_finite(value.z)


func _finish() -> void:
	if _failures.is_empty():
		print("PIXIBALL_BALLPLAYER_ASSET_OK bones=31 meshes=35 actions=9 authored_pbr=verified handedness=verified")
		quit(0)
		return
	for failure in _failures:
		push_error("PIXIBALL_BALLPLAYER_ASSET: %s" % failure)
	quit(1)
