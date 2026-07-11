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
	print("PIXIBALL_SCENE_CONTRACT_OK nodes=9")
	session.free()
	quit(0)
