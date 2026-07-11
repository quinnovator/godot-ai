class_name BaseballVisual
extends Node3D

# Pitch-slot trail palette (UE PixStyle PitchSlot[5]: green/red/blue/yellow/purple).
const SLOT_COLORS := [
	Color("6ee76e"),
	Color("ff6b6b"),
	Color("67b7ff"),
	Color("ffd94a"),
	Color("c78bff"),
]
# UE comet: 5 shrinking spheres, per-node alpha, x3 emissive.
const TRAIL_COUNT := 5
const TRAIL_ALPHAS := [0.35, 0.22, 0.16, 0.10, 0.06]
const BALL_RADIUS := 0.18
const SEAM_BASE_SCALE := Vector3(0.68, 1.0, 0.68)
# Per-view multipliers on BALL_RADIUS. The pitch ball reads as a small bright
# dot from the center-field broadcast lens (UE ~9 cm scale); the live-play ball
# is exaggerated so the sky cam can still see it (UE 0.35 scale).
const PITCH_SCALE := 0.32
const PLAY_SCALE := 2.0
# Ball height in feet == (world_y - home_plate_y) / vertical scale.
const VERTICAL_WORLD_PER_FOOT := 0.3048
const C_HOME_Y := 0.08

var body: MeshInstance3D
var seams: Array[MeshInstance3D] = []
var trail: Array[MeshInstance3D] = []
var shadow: MeshInstance3D

var _trail_color := Color("6ee76e")
var _visual_scale := PITCH_SCALE
var _history: Array[Vector3] = []
# Samples of ball position we drop the comet nodes onto; ~sub-pixel spacing.
var _sample_stride := 3


func _ready() -> void:
	body = MeshInstance3D.new()
	body.name = "BallMesh"
	var sphere := SphereMesh.new()
	sphere.radius = BALL_RADIUS
	sphere.height = BALL_RADIUS * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	body.mesh = sphere
	var ball_material := StandardMaterial3D.new()
	ball_material.albedo_color = Color("fff7df")
	ball_material.roughness = 0.78
	# A little self-emission keeps it a bright dot at broadcast distance.
	ball_material.emission_enabled = true
	ball_material.emission = Color("fff7df")
	ball_material.emission_energy_multiplier = 0.7
	body.material_override = ball_material
	add_child(body)

	# Two raised seams make close pitch shots immediately read as a baseball.
	for side in [-1.0, 1.0]:
		var seam := MeshInstance3D.new()
		var seam_mesh := TorusMesh.new()
		seam_mesh.inner_radius = 0.145
		seam_mesh.outer_radius = 0.16
		seam_mesh.rings = 12
		seam_mesh.ring_segments = 5
		seam.mesh = seam_mesh
		seam.scale = SEAM_BASE_SCALE
		seam.rotation_degrees = Vector3(90, side * 26, 0)
		var seam_material := StandardMaterial3D.new()
		seam_material.albedo_color = Color("d74343")
		seam.material_override = seam_material
		seams.append(seam)
		add_child(seam)

	_build_trail()
	set_visual_scale(_visual_scale)

	shadow = MeshInstance3D.new()
	shadow.name = "BallShadow"
	var disc := CylinderMesh.new()
	disc.top_radius = 0.28
	disc.bottom_radius = 0.28
	disc.height = 0.012
	disc.radial_segments = 16
	shadow.mesh = disc
	var shadow_material := StandardMaterial3D.new()
	shadow_material.albedo_color = Color(0.01, 0.02, 0.03, 0.30)
	shadow_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shadow_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	shadow.material_override = shadow_material
	get_parent().call_deferred("add_child", shadow)
	visible = false


func _build_trail() -> void:
	# Comet nodes live in world space (siblings of the ball), trailing the head
	# along its recent path. Head (i<=1) stays white; tail nodes take the slot
	# tint. Scale follows UE's 0.13 * 0.82^(i+1) ratio relative to the ball.
	for i in range(TRAIL_COUNT):
		var node := MeshInstance3D.new()
		node.name = "BallTrail%d" % i
		var mesh := SphereMesh.new()
		var node_radius := BALL_RADIUS * (0.13 * pow(0.82, i + 1)) / 0.09
		mesh.radius = node_radius
		mesh.height = node_radius * 2.0
		mesh.radial_segments = 8
		mesh.rings = 4
		node.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		node.material_override = mat
		node.visible = false
		trail.append(node)
		get_parent().call_deferred("add_child", node)
	_refresh_trail_colors()


## Tint the comet tail by the active pitch slot (0-4). Head nodes stay white.
func set_trail_slot(slot: int) -> void:
	_trail_color = SLOT_COLORS[clampi(slot, 0, SLOT_COLORS.size() - 1)]
	_refresh_trail_colors()


## Small bright dot for the center-field pitch view.
func use_pitch_ball() -> void:
	set_visual_scale(PITCH_SCALE)


## Exaggerated ball so the overhead live-play sky cam can see it.
func use_play_ball() -> void:
	set_visual_scale(PLAY_SCALE)


func set_visual_scale(mult: float) -> void:
	_visual_scale = maxf(0.01, mult)
	if is_instance_valid(body):
		body.scale = Vector3.ONE * _visual_scale
	for seam in seams:
		if is_instance_valid(seam):
			seam.scale = SEAM_BASE_SCALE * _visual_scale
	for node in trail:
		if is_instance_valid(node):
			node.scale = Vector3.ONE * _visual_scale


func _refresh_trail_colors() -> void:
	for i in range(trail.size()):
		var mat := trail[i].material_override as StandardMaterial3D
		if mat == null:
			continue
		var tint := Color.WHITE if i <= 1 else _trail_color
		var alpha := float(TRAIL_ALPHAS[i]) if i < TRAIL_ALPHAS.size() else 0.06
		# Translucent node (soft comet glow, NOT an opaque balloon); the x3 gain
		# is emissive energy only.
		mat.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 3.0


func set_active(value: bool) -> void:
	visible = value
	if is_instance_valid(shadow):
		shadow.visible = value
	if not value:
		_history.clear()
		for node in trail:
			if is_instance_valid(node):
				node.visible = false


func set_ball_position(value: Vector3) -> void:
	global_position = value
	rotation += Vector3(0.09, 0.16, 0.12)
	_push_history(value)
	_update_trail()
	if is_instance_valid(shadow):
		shadow.global_position = Vector3(value.x, 0.075, value.z)
		var scale_value := clampf(1.15 - value.y * 0.035, 0.35, 1.0) * _visual_scale
		shadow.scale = Vector3.ONE * scale_value
		# Blob opacity fades with height: clamp(0.30 - 0.024 * z_ft, 0.08, 0.30).
		var z_ft := maxf(0.0, (value.y - C_HOME_Y) / VERTICAL_WORLD_PER_FOOT)
		var mat := shadow.material_override as StandardMaterial3D
		if mat != null:
			mat.albedo_color.a = clampf(0.30 - 0.024 * z_ft, 0.08, 0.30)


func _push_history(value: Vector3) -> void:
	_history.push_front(value)
	var cap := TRAIL_COUNT * _sample_stride + 2
	if _history.size() > cap:
		_history.resize(cap)


func _update_trail() -> void:
	if not visible:
		return
	for i in range(trail.size()):
		var node := trail[i]
		if not is_instance_valid(node):
			continue
		var index := (i + 1) * _sample_stride
		if index < _history.size():
			node.global_position = _history[index]
			node.visible = true
		else:
			node.visible = false
