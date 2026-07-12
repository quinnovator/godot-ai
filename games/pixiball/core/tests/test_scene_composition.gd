extends SceneTree


func _init() -> void:
	var packed := load("res://main.tscn") as PackedScene
	assert(packed != null)
	var session := packed.instantiate()
	assert(session.has_node("World/Stadium"))
	assert(session.has_node("Actors/Ballplayers"))
	assert(session.has_node("Presentation/Baseball"))
	assert(session.has_node("Presentation/CameraDirector"))
	assert(session.has_node("Systems/LivePlayController"))
	assert(session.has_node("Systems/AudioDirector"))
	assert(session.has_node("Systems/HapticDirector"))
	assert(session.has_node("PixiballHUD"))
	assert(session.has_node("PitchIntelLayer/PitchIntelPanel"))
	var world_viewport := session.get_node("PixelComposite/WorldView/WorldViewport") as SubViewport
	assert(world_viewport.size == Vector2i(1920, 1080))
	var camera_director = session.get_node("Presentation/CameraDirector")
	assert(camera_director.logical_vertical_pixels == 1080)
	print("PIXIBALL_SCENE_CONTRACT_OK nodes=9 world=1920x1080")
	session.free()
	quit(0)
