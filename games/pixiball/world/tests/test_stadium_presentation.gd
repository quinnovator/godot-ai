extends SceneTree

const Stadium = preload("res://world/voxel_stadium.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var first := Stadium.new()
	first.name = "FirstStadium"
	root.add_child(first)
	await process_frame

	var second := Stadium.new()
	second.name = "SecondStadium"
	root.add_child(second)
	await process_frame

	for side_name in ["SpectatorCrowdLeft", "SpectatorCrowdRight"]:
		_check_crowd(first.get_node_or_null(side_name) as Node3D, side_name)
		_check_determinism(
			first.get_node_or_null(side_name) as Node3D,
			second.get_node_or_null(side_name) as Node3D,
			side_name
		)
	_check_plate_crowd(first)
	_check_determinism(
		first.get_node_or_null("HomeBackstop/SpectatorCrowdPlate") as Node3D,
		second.get_node_or_null("HomeBackstop/SpectatorCrowdPlate") as Node3D,
		"SpectatorCrowdPlate"
	)
	_check_motion_contract(first, second)
	_check_reaction_and_decay(first)

	_check_moods(first)

	var exit_code := 0
	if failures.is_empty():
		print("PIXIBALL_STADIUM_PRESENTATION_OK spectators=3d dense=true motion=staggered reactions=decay moods=3 deterministic=true")
	else:
		for failure in failures:
			push_error("PIXIBALL_STADIUM_PRESENTATION: %s" % failure)
		exit_code = 1
	first.queue_free()
	second.queue_free()
	await process_frame
	quit(exit_code)


func _check_crowd(crowd: Node3D, context: String) -> void:
	_check(crowd != null, "%s must exist" % context)
	if crowd == null:
		return
	var count := int(crowd.get_meta("spectator_count", 0))
	_check(count >= 440, "%s must contain a substantially denser deterministic audience" % context)
	var expected_counts := {
		"Torsos": count,
		"Necks": count,
		"Heads": count,
		"Hair": count,
		"UpperArms": count * 2,
		"Forearms": count * 2,
		"Eyes": count * 2,
		"Mouths": count,
	}
	for batch_name in expected_counts:
		var batch := crowd.get_node_or_null(batch_name) as MultiMeshInstance3D
		_check(batch != null, "%s/%s must exist" % [context, batch_name])
		if batch == null:
			continue
		_check(batch.multimesh != null, "%s/%s must own a MultiMesh" % [context, batch_name])
		if batch.multimesh == null:
			continue
		_check(batch.multimesh.instance_count == int(expected_counts[batch_name]), "%s/%s instance count must match connected body topology" % [context, batch_name])
		var primitive := batch.multimesh.mesh as PrimitiveMesh
		_check(primitive != null and primitive.material is StandardMaterial3D, "%s/%s must use a standard lit material" % [context, batch_name])
		if primitive != null and primitive.material is StandardMaterial3D:
			var material := primitive.material as StandardMaterial3D
			_check(material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED, "%s/%s must respond to stadium lighting" % [context, batch_name])
	var caps := crowd.get_node_or_null("Caps") as MultiMeshInstance3D
	var cap_brims := crowd.get_node_or_null("CapBrims") as MultiMeshInstance3D
	_check(caps != null and cap_brims != null, "%s must batch deterministic spectator accessories" % context)
	if caps != null and cap_brims != null:
		_check(caps.multimesh.instance_count >= count / 5, "%s must give a visible minority of fans distinct caps" % context)
		_check(caps.multimesh.instance_count == cap_brims.multimesh.instance_count, "%s cap domes and brims must stay paired" % context)
	if crowd.has_node("Torsos"):
		var layout_bounds: AABB = crowd.get_meta("layout_bounds", AABB())
		_check(layout_bounds.size.z > 42.0, "%s must follow the full stand rake" % context)
		_check(layout_bounds.size.x > 9.0 and layout_bounds.size.y > 3.0, "%s must layer spectators across stand depth and height" % context)
		_check(float(crowd.get_meta("minimum_face_clearance", 0.0)) > 0.2, "%s must not be coplanar with a stand face" % context)
		_check((crowd.get_node("Torsos") as MultiMeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "%s torsos must cast shadows" % context)
	_check_human_proportions(crowd, context)


func _check_determinism(first: Node3D, second: Node3D, context: String) -> void:
	_check(first != null and second != null, "%s determinism roots must exist" % context)
	if first == null or second == null:
		return
	_check(first.get_meta("layout_bounds") == second.get_meta("layout_bounds"), "%s layout bounds must be deterministic" % context)
	_check(first.get_meta("layout_samples") == second.get_meta("layout_samples"), "%s layout samples must be deterministic" % context)
	for batch_name in ["Torsos", "Necks", "Heads", "Hair", "UpperArms", "Forearms", "Eyes", "Mouths"]:
		var a := (first.get_node(batch_name) as MultiMeshInstance3D).multimesh
		var b := (second.get_node(batch_name) as MultiMeshInstance3D).multimesh
		_check(a.instance_count == b.instance_count, "%s/%s deterministic counts must match" % [context, batch_name])


func _check_plate_crowd(stadium: Node) -> void:
	var crowd := stadium.get_node_or_null("HomeBackstop/SpectatorCrowdPlate") as Node3D
	_check(crowd != null, "plate foreground spectator root must exist")
	if crowd == null:
		return
	var count := int(crowd.get_meta("spectator_count", 0))
	_check(count >= 260, "plate foreground must contain five populated 3D seating blocks around the overlook")
	_check(int(crowd.get_meta("row_count", 0)) == Stadium.PLATE_SPECTATOR_ROWS, "plate foreground must report five staggered rows")
	_check(is_zero_approx(float(crowd.get_meta("strip_recess", -1.0))), "plate foreground must rely on real spectators rather than duplicate sprite strips")
	var bounds: AABB = crowd.get_meta("layout_bounds", AABB())
	_check(bounds.size.x > 34.0 and bounds.size.y > 1.4 and bounds.size.z > 1.4, "plate foreground must span the lower bowl rake")
	var expected_counts := {
		"Torsos": count,
		"Necks": count,
		"Heads": count,
		"Hair": count,
		"UpperArms": count * 2,
		"Forearms": count * 2,
		"Eyes": count * 2,
		"Mouths": count,
	}
	for batch_name in expected_counts:
		var batch := crowd.get_node_or_null(batch_name) as MultiMeshInstance3D
		_check(batch != null and batch.multimesh != null, "plate %s batch must exist" % batch_name)
		if batch != null and batch.multimesh != null:
			_check(batch.multimesh.instance_count == int(expected_counts[batch_name]), "plate %s topology must match spectator count" % batch_name)
	_check(stadium.get_node_or_null("CrowdStrip000") == null, "plate overlook must not paint a second sprite audience through the 3D fans")
	_check_human_proportions(crowd, "SpectatorCrowdPlate")


func _check_motion_contract(first: Node, second: Node) -> void:
	var distinct_phases := {}
	for path in ["SpectatorCrowdLeft/Torsos", "SpectatorCrowdRight/Torsos", "HomeBackstop/SpectatorCrowdPlate/Torsos"]:
		var first_batch := first.get_node_or_null(path) as MultiMeshInstance3D
		var second_batch := second.get_node_or_null(path) as MultiMeshInstance3D
		_check(first_batch != null and second_batch != null, "%s motion batches must exist" % path)
		if first_batch == null or second_batch == null:
			continue
		var a := first_batch.multimesh
		var b := second_batch.multimesh
		_check(a.use_custom_data and b.use_custom_data, "%s must expose deterministic per-fan motion data" % path)
		# The dummy headless renderer does not round-trip MultiMesh custom buffers;
		# production still receives them, while this bounded mirror is CI-readable.
		var samples_a: Array = first_batch.get_meta("motion_samples", [])
		var samples_b: Array = second_batch.get_meta("motion_samples", [])
		_check(samples_a.size() == 16 and samples_b.size() == 16, "%s must retain bounded motion audit samples" % path)
		for index in range(mini(samples_a.size(), samples_b.size())):
			var custom_a: Color = samples_a[index]
			var custom_b: Color = samples_b[index]
			_check(custom_a.is_equal_approx(custom_b), "%s custom motion data must be reproducible at index %d" % [path, index])
			_check(custom_a.g >= 0.55 and custom_a.b >= 0.55 and custom_a.a >= 0.18, "%s custom data must encode useful speed/amplitude/individual response" % path)
			distinct_phases[snappedf(custom_a.r, 0.0001)] = true
	_check(distinct_phases.size() >= 12, "crowd idle phases must be staggered per fan rather than synchronized by strip")
	var state: Dictionary = first.crowd_state()
	_check(int(state.get("total_spectators", 0)) >= 1180, "stadium must batch more than eleven hundred 3D spectators")
	_check(int(state.get("animated_batches", 0)) == 30, "three audience sections must animate ten connected MultiMesh batches each")


func _check_reaction_and_decay(stadium: Node) -> void:
	stadium.set_process(false)
	var before_state: Dictionary = stadium.crowd_state()
	var before: Vector3 = before_state.motion_sample
	var serial_before := int(before_state.get("reaction_serial", 0))
	stadium.react_to_play("home_run")
	var active: Dictionary = stadium.crowd_state()
	var reacted: Vector3 = active.motion_sample
	_check(int(active.reaction_serial) == serial_before + 1, "semantic reaction API must register exactly one crowd response")
	_check(is_equal_approx(float(active.reaction_strength), 1.0), "home run must request the strongest audience response")
	_check(float(active.reaction_timer) >= 3.19 and float(active.reaction_level) > 0.99, "home run crowd response must start at full intensity")
	_check(float(active.led_timer) > 1.0 and float(active.bell_timer) >= 5.0, "home run must coordinate LED ribbon and Liberty Bell")
	_check(not before.is_equal_approx(reacted), "3D fan transforms must react immediately, independent of crowd textures")

	stadium._process(0.40)
	var mid: Dictionary = stadium.crowd_state()
	var moved: Vector3 = mid.motion_sample
	_check(float(mid.reaction_timer) < float(active.reaction_timer), "crowd reaction timer must decay with presentation time")
	_check(float(mid.reaction_level) > 0.0 and float(mid.reaction_level) < float(active.reaction_level), "crowd reaction envelope must ease down continuously")
	_check(int(mid.motion_tick) >= int(active.motion_tick) + 4, "batched crowd motion must advance at its fixed update cadence")
	_check(not moved.is_equal_approx(reacted), "staggered 3D fan pose must continue moving during the cheer")

	stadium._process(3.20)
	var settled: Dictionary = stadium.crowd_state()
	_check(is_zero_approx(float(settled.reaction_timer)) and is_zero_approx(float(settled.reaction_level)), "crowd reaction must fully decay to idle")
	_check(is_zero_approx(float(settled.reaction_strength)), "completed crowd reaction must clear retained strength")


func _check_human_proportions(crowd: Node3D, context: String) -> void:
	var torso := (crowd.get_node("Torsos") as MultiMeshInstance3D).multimesh.mesh as CylinderMesh
	var neck := (crowd.get_node("Necks") as MultiMeshInstance3D).multimesh.mesh as CylinderMesh
	var head := (crowd.get_node("Heads") as MultiMeshInstance3D).multimesh.mesh as SphereMesh
	var hair := (crowd.get_node("Hair") as MultiMeshInstance3D).multimesh.mesh as SphereMesh
	var upper_arm := (crowd.get_node("UpperArms") as MultiMeshInstance3D).multimesh.mesh as CapsuleMesh
	var forearm := (crowd.get_node("Forearms") as MultiMeshInstance3D).multimesh.mesh as CapsuleMesh
	var eyes := (crowd.get_node("Eyes") as MultiMeshInstance3D).multimesh.mesh as BoxMesh
	var mouth := (crowd.get_node("Mouths") as MultiMeshInstance3D).multimesh.mesh as BoxMesh
	_check(torso != null and torso.top_radius > torso.bottom_radius, "%s torsos must taper into visible shoulders" % context)
	_check(neck != null and neck.height >= 0.1, "%s heads must connect through a visible neck" % context)
	_check(head != null and head.radius <= 0.125, "%s heads must keep human rather than icon proportions" % context)
	_check(hair != null and not hair.is_hemisphere, "%s must use rounded overlapping hair silhouettes" % context)
	_check(upper_arm != null and forearm != null and upper_arm.height <= 0.25, "%s must use articulated upper and lower arm segments" % context)
	_check(eyes != null and eyes.size.x < 0.03 and mouth != null and mouth.size.x < 0.06, "%s facial marks must remain subtle" % context)
	_check((crowd.get_node("Hair") as MultiMeshInstance3D).cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_ON, "%s hair and body silhouettes must cast contact shadows" % context)


func _check_moods(stadium: Node) -> void:
	var world_environment := stadium.get_node_or_null("WorldEnvironment") as WorldEnvironment
	_check(world_environment != null and world_environment.environment != null, "stadium must own its environment")
	if world_environment == null or world_environment.environment == null:
		return
	var env := world_environment.environment
	var torso_batch := stadium.get_node("SpectatorCrowdLeft/Torsos") as MultiMeshInstance3D
	var torso_material := (torso_batch.multimesh.mesh as PrimitiveMesh).material as StandardMaterial3D

	stadium.set_mood("day")
	var day_tint := torso_material.albedo_color
	var day_glow := env.glow_intensity
	var day_ambient := env.ambient_light_energy
	stadium.set_mood("golden")
	var golden_tint := torso_material.albedo_color
	var golden_glow := env.glow_intensity
	stadium.set_mood("night")
	var night_tint := torso_material.albedo_color
	_check(not day_tint.is_equal_approx(golden_tint) and not golden_tint.is_equal_approx(night_tint), "moods must tint 3D spectators")
	_check(day_glow < golden_glow and golden_glow < env.glow_intensity, "mood glow must rise from day through night")
	_check(day_ambient < env.ambient_light_energy, "night ambient fill must preserve readable crowd depth")
	_check(float(Stadium.MOODS.golden.lamp_energy) < 1.0, "golden suite emission must preserve panel shape")
	_check(float(Stadium.MOODS.night.lamp_energy) < 1.25, "night suite emission must preserve panel shape")
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		_check(env.ssao_enabled, "Forward+ stadium must enable SSAO")
		_check(env.ssao_intensity >= 1.5 and env.ssao_radius < 0.8, "Forward+ stadium must use tight spectator contact shadows")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
