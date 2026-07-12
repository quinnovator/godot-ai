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
# Short shutter streak. It is velocity-aligned and time-based, so its apparent
# length does not change with frame rate and it never reads as extra baseballs.
const TRAIL_COUNT := 4
const TRAIL_ALPHAS := [0.18, 0.11, 0.065, 0.03]
const TRAIL_RADII := [0.34, 0.27, 0.20, 0.12]
const SHUTTER_SECONDS := 1.0 / 120.0
const MIN_TRAIL_LENGTH := 0.06
const MAX_TRAIL_LENGTH := 0.72
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
var _last_position := Vector3.ZERO
var _last_velocity := Vector3.ZERO
var _has_last_position := false
var _flight_time := 0.0
var _spin_radians_per_second := 0.0
var _spin_axis := Vector3.RIGHT
var _trail_enabled := true
var _batting_trail := false


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
	# Streak segments live in world space as siblings of the ball. Cylinders join
	# end-to-end behind the measured velocity vector and taper into transparency.
	for i in range(TRAIL_COUNT):
		var node := MeshInstance3D.new()
		node.name = "BallStreak%d" % i
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.01
		mesh.bottom_radius = 0.01
		mesh.height = 0.01
		mesh.radial_segments = 8
		node.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
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
	_trail_enabled = true
	set_visual_scale(PITCH_SCALE)


## Exaggerated ball so the overhead live-play sky cam can see it.
func use_play_ball() -> void:
	_trail_enabled = false
	_hide_trail()
	set_visual_scale(PLAY_SCALE)


func begin_pitch_motion(spin_rate_rpm: float, spin_axis_degrees: float, batting_view: bool) -> void:
	_flight_time = 0.0
	_last_velocity = Vector3.ZERO
	_has_last_position = false
	_spin_radians_per_second = maxf(0.0, spin_rate_rpm) * TAU / 60.0
	var axis_radians := deg_to_rad(spin_axis_degrees)
	_spin_axis = Vector3(cos(axis_radians), sin(axis_radians), 0.0).normalized()
	_batting_trail = batting_view
	_trail_enabled = true
	_refresh_trail_colors()


func set_visual_scale(mult: float) -> void:
	_visual_scale = maxf(0.01, mult)
	if is_instance_valid(body):
		body.scale = Vector3.ONE * _visual_scale
	for seam in seams:
		if is_instance_valid(seam):
			seam.scale = SEAM_BASE_SCALE * _visual_scale


func _refresh_trail_colors() -> void:
	for i in range(trail.size()):
		var mat := trail[i].material_override as StandardMaterial3D
		if mat == null:
			continue
		var tint_amount := 0.04 if i <= 1 else 0.12 + float(i) * 0.03
		var tint := Color.WHITE.lerp(_trail_color, tint_amount)
		var alpha := float(TRAIL_ALPHAS[i]) if i < TRAIL_ALPHAS.size() else 0.03
		if _batting_trail:
			alpha *= 0.58
		mat.albedo_color = Color(tint.r, tint.g, tint.b, alpha)
		mat.emission_enabled = true
		mat.emission = tint
		mat.emission_energy_multiplier = 0.55


func set_active(value: bool) -> void:
	visible = value
	if is_instance_valid(shadow):
		shadow.visible = value
	if not value:
		_has_last_position = false
		_last_velocity = Vector3.ZERO
		_hide_trail()


func set_ball_position(value: Vector3, delta := 0.0) -> void:
	global_position = value
	if delta > 0.00001 and _has_last_position:
		_last_velocity = (value - _last_position) / delta
		_flight_time += delta
		quaternion = Quaternion(_spin_axis, _spin_radians_per_second * _flight_time)
	_last_position = value
	_has_last_position = true
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

func _update_trail() -> void:
	if not visible or not _trail_enabled:
		_hide_trail()
		return
	var speed := _last_velocity.length()
	if speed < 0.5:
		_hide_trail()
		return
	var direction := _last_velocity / speed
	var streak_length := clampf(speed * SHUTTER_SECONDS, MIN_TRAIL_LENGTH, MAX_TRAIL_LENGTH)
	var segment_length := streak_length / float(TRAIL_COUNT)
	var head := global_position - direction * BALL_RADIUS * _visual_scale * 0.45
	for i in range(trail.size()):
		var node := trail[i]
		if not is_instance_valid(node):
			continue
		var segment_start := head - direction * segment_length * float(i)
		var segment_end := segment_start - direction * segment_length
		var segment := segment_end - segment_start
		var mesh := node.mesh as CylinderMesh
		var radius := BALL_RADIUS * _visual_scale * float(TRAIL_RADII[i])
		mesh.top_radius = radius
		mesh.bottom_radius = radius * 0.82
		mesh.height = segment.length()
		node.global_transform = Transform3D(
			_basis_from_y(segment.normalized()),
			(segment_start + segment_end) * 0.5
		)
		node.visible = true


func _basis_from_y(direction: Vector3) -> Basis:
	var side := direction.cross(Vector3.FORWARD)
	if side.length_squared() < 0.000001:
		side = direction.cross(Vector3.RIGHT)
	side = side.normalized()
	var forward := side.cross(direction).normalized()
	return Basis(side, direction, forward)


func _hide_trail() -> void:
	for node in trail:
		if is_instance_valid(node):
			node.visible = false
