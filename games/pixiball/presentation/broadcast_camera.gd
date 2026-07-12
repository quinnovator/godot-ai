class_name PixiballBroadcastCamera
extends Node3D

const C = preload("res://gameplay/game_constants.gd")
const ParkGeometry = preload("res://core/fielding/park_geometry.gd")

## --- Park <-> Godot stage coordinate mapping ---------------------------------
## The authoritative simulation works in Citizens-Bank-Park FEET; the presentation
## boundary (see gameplay/live_play_controller.gd::_field_state_to_world) maps a
## park sample to this stage's Godot units with:
##     world = HOME_PLATE + (park_x * H, park_z * V, -park_y * H)
## where
##     HOME_PLATE = C.HOME_PLATE = (0, 0.08, 18)
##     H = ParkGeometry.HORIZONTAL_WORLD_PER_FOOT = 0.155  (u/ft, lateral + depth)
##     V = ParkGeometry.VERTICAL_WORLD_PER_FOOT   = 0.3048 (u/ft, height)
## Axes in park feet: +x -> first base (right), +y -> center field (depth), +z up.
## In Godot stage units that becomes: +X -> first base, -Z -> center field,
## +Y -> up. Home plate sits at Z=+18, the mound at ~Z=+8.6 (actors are placed a
## touch flatter, mound at Z=0). The outfield wall lands near Z=-44 (CF ~401 ft).
##
## NOTE ON SCALE: this is a *compressed* stage - depth uses 0.155 u/ft while
## height uses 0.3048 u/ft, so a literal 393 ft center-field camera sits only
## ~61 u out. At that distance a broadcast FOV (~52 deg) renders the battery a
## few pixels tall. The center-field broadcast cam below therefore keeps the UE
## vantage (out toward CF, a hair to the 3B side, low, looking back at the plate,
## a whisper of up-tilt) but uses a telephoto FOV to compress and frame the
## pitcher/batter/catcher/umpire - exactly how a real MLB center-field lens works
## from 400 ft. The live-play (PlayCam) sky cam converts the UE follow law from
## park feet through the mapping above, using H for its height so the overhead
## framing stays proportional to the compressed field footprint.
const FT_H := ParkGeometry.HORIZONTAL_WORLD_PER_FOOT
const FT_V := ParkGeometry.VERTICAL_WORLD_PER_FOOT

# Plate-local dimensions use the vertical (true-foot) scale. The field depth is
# compressed for presentation, but players, the baseball, and the rulebook zone
# remain human-scale at home plate.
const PLATE_WORLD_PER_FOOT := FT_V
const STRIKE_ZONE_HALF_WIDTH_FT := 17.0 / 24.0
const STRIKE_ZONE_BOTTOM_FT := 1.5
const STRIKE_ZONE_TOP_FT := 3.5
const PITCH_PLANE_Z_OFFSET := -0.55

const MODE_INTRO := "intro"
const MODE_PITCHING := "pitching"
const MODE_FIELDING := "fielding"
const MODE_BATTING := "batting"
const MODE_DUGOUT := "dugout"
const GAMEPLAY_MODES := [MODE_PITCHING, MODE_FIELDING, MODE_BATTING]

## When set, the broadcast camera is parented into that SubViewport so the
## 3D world renders at the fixed logical resolution while this director node
## keeps authoring motion in the main scene tree.
@export var world_viewport_path: NodePath
## Vertical logical pixel count of the world render target. Orthographic
## plate cameras snap position and shake in world increments derived from
## this so pixels never crawl at subpixel offsets. Must match the
## WorldViewport height.
@export var logical_vertical_pixels := 720

# --- Camera juice (matches PixCameraJuiceComponent) ---------------------------
const TRAUMA_DECAY := 3.4
## UE amplitude is ~6.0 world-cm; scaled into this compressed stage's units so a
## full-trauma contact reads without launching the frame off the rails.
const TRAUMA_SHAKE := 0.16
const CONTACT_FADE_FROM := 0.35
const CONTACT_FADE_SEC := 0.12
const HITSTOP_SCALE := 0.08

var camera: Camera3D
var mode := MODE_INTRO
var target_node: Node3D
var desired_position := Vector3(19, 12, 31)
var desired_target := Vector3(0, 2.5, 3)
var _look_target := Vector3(0, 2.5, 3)
var _shake_strength := 0.0
var _intro_time := 0.0
var _anim_time := 0.0
var _snap_requested := false

var _trauma := 0.0
var _flash_time := 0.0
var _hitstop_frames := 0
var _flash_layer: CanvasLayer
var _flash_rect: ColorRect
var _broadcast_fill: DirectionalLight3D


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "BroadcastCamera"
	camera.current = true
	camera.fov = 46.0
	camera.near = 0.08
	camera.far = 260.0
	var render_viewport := get_node_or_null(world_viewport_path) as SubViewport
	if render_viewport != null:
		render_viewport.add_child(camera)
	else:
		add_child(camera)
	# A restrained camera-axis fill preserves faces, gloves, and jersey numbers
	# against the bright field and waterfront. It carries no shadows and never
	# replaces the stadium key; it only restores the readable value hierarchy
	# expected from a real broadcast lens.
	_broadcast_fill = DirectionalLight3D.new()
	_broadcast_fill.name = "BroadcastFill"
	_broadcast_fill.light_color = Color("ffe6c2")
	_broadcast_fill.light_energy = 0.18
	_broadcast_fill.light_cull_mask = BallplayerActor.CHARACTER_RENDER_LAYER
	_broadcast_fill.shadow_enabled = false
	add_child(_broadcast_fill)
	global_position = desired_position
	look_at(desired_target, Vector3.UP)
	_build_flash()
	_sync_render_camera()


func set_mode(next_mode: String, focus: Node3D = null) -> void:
	mode = next_mode
	target_node = focus
	match mode:
		MODE_INTRO:
			_broadcast_fill.light_energy = 0.16
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			desired_position = Vector3(19, 12, 31)
			desired_target = Vector3(0, 2.5, 2)
			camera.fov = 45.0
		MODE_PITCHING:
			# Long center-field broadcast lens, just to the third-base side.
			_broadcast_fill.light_energy = 0.44
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			camera.fov = 8.0
			# The first-base-side offset places the plate group on the left and the
			# pitcher on the right, matching the approved gameplay composition.
			desired_position = Vector3(3.2, 1.9, -28.0)
			desired_target = Vector3(0.0, 2.0, 16.5)
		MODE_BATTING:
			_broadcast_fill.light_energy = 0.28
			# Competitive zone-hitting view from the clear backstop corridor. The
			# physical rulebook zone stays large in the lower center while the
			# elevated look point keeps the pitcher's full delivery in frame. Its
			# size comes from projection, not an independently enlarged HUD rectangle.
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			camera.fov = 15.0
			desired_position = Vector3(0.0, 2.4, 27.0)
			desired_target = plate_location_world(0.0, 4.15)
		MODE_FIELDING:
			_broadcast_fill.light_energy = 0.18
			# UE PlayCam: overhead live-play sky cam, driven by the follow law
			# below every frame. Fixed FOV 52 and a fixed -58 deg downward pitch.
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			camera.fov = 52.0
			_drive_playcam()
		MODE_DUGOUT:
			_broadcast_fill.light_energy = 0.22
			camera.projection = Camera3D.PROJECTION_PERSPECTIVE
			desired_position = Vector3(-25, 5.5, 18)
			desired_target = Vector3(0, 2.0, 5)
			camera.fov = 44.0
		_:
			push_warning("Unknown Pixiball camera mode: %s" % mode)
			return
	if mode in GAMEPLAY_MODES:
		_snap_requested = true
		_apply_requested_cut()


func plate_location_world(lateral_ft: float, height_ft: float) -> Vector3:
	return C.HOME_PLATE + Vector3(
		lateral_ft * PLATE_WORLD_PER_FOOT,
		height_ft * PLATE_WORLD_PER_FOOT,
		PITCH_PLANE_Z_OFFSET
	)


func projected_strike_zone() -> Rect2:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return Rect2()
	var corners := [
		plate_location_world(-STRIKE_ZONE_HALF_WIDTH_FT, STRIKE_ZONE_TOP_FT),
		plate_location_world(STRIKE_ZONE_HALF_WIDTH_FT, STRIKE_ZONE_TOP_FT),
		plate_location_world(-STRIKE_ZONE_HALF_WIDTH_FT, STRIKE_ZONE_BOTTOM_FT),
		plate_location_world(STRIKE_ZONE_HALF_WIDTH_FT, STRIKE_ZONE_BOTTOM_FT),
	]
	var minimum := Vector2(INF, INF)
	var maximum := Vector2(-INF, -INF)
	for corner in corners:
		if camera.is_position_behind(corner):
			return Rect2()
		var screen_point := camera.unproject_position(corner)
		minimum = minimum.min(screen_point)
		maximum = maximum.max(screen_point)
	return Rect2(minimum, maximum - minimum)


func plate_lateral_screen_sign() -> float:
	if not is_instance_valid(camera) or not camera.is_inside_tree():
		return 1.0
	var center_screen := camera.unproject_position(plate_location_world(0.0, 2.5))
	var positive_screen := camera.unproject_position(plate_location_world(1.0, 2.5))
	var delta_x := positive_screen.x - center_screen.x
	return signf(delta_x) if not is_zero_approx(delta_x) else 1.0


func shake(strength := 0.3) -> void:
	_trauma = minf(1.0, _trauma + strength)


## Contact juice: hitstop + trauma shake + white flash, scaled by exit velocity,
## mirroring PixCameraJuiceComponent's contact beat.
func contact_juice(exit_velocity_mph: float) -> void:
	var ev01 := clampf((exit_velocity_mph - 60.0) / 55.0, 0.0, 1.0)
	_hitstop_frames = 4 if ev01 > 0.75 else (3 if ev01 > 0.45 else 2)
	_trauma = minf(1.0, _trauma + sqrt((1.0 + 3.0 * ev01) / 6.0))
	_flash_time = CONTACT_FADE_SEC


func _process(delta: float) -> void:
	_intro_time += delta
	_anim_time += delta

	if mode == MODE_INTRO:
		var angle := _intro_time * 0.055
		desired_position = Vector3(19.0 + sin(angle) * 5.0, 12.0 + sin(angle * 2.0), 31.0 - cos(angle) * 4.0)
	elif mode == MODE_FIELDING and is_instance_valid(target_node):
		_drive_playcam()

	if _snap_requested:
		_apply_requested_cut()
	else:
		# UE ease: K = 1 - exp(-dt * 4.5).
		global_position = global_position.lerp(desired_position, 1.0 - exp(-4.5 * delta))
		_look_target = _look_target.lerp(desired_target, 1.0 - exp(-5.5 * delta))

	global_position += _trauma_offset(delta)
	look_at(_look_target, Vector3.UP)
	_update_hitstop()
	_update_flash(delta)
	_sync_render_camera()


func _apply_requested_cut() -> void:
	global_position = desired_position
	_look_target = desired_target
	_snap_requested = false
	look_at(_look_target, Vector3.UP)
	_sync_render_camera()


## UE PlayCam DriveCamera: clamp the ball to park bounds, ease a fixed-orientation
## sky camera toward a depth/lateral-compressed target.
func _drive_playcam() -> void:
	var ball := target_node.global_position if is_instance_valid(target_node) else C.HOME_PLATE
	# Godot stage world -> park feet (inverse of _field_state_to_world).
	var cx := clampf(ball.x / FT_H, -240.0, 240.0)
	var cy := clampf((C.HOME_PLATE.z - ball.z) / FT_H, 30.0, 420.0)
	var depth_t := clampf((cy - 30.0) / 390.0, 0.0, 1.0)
	var back_off := lerpf(60.0, 100.0, depth_t)
	var height_ft := lerpf(260.0, 330.0, depth_t)
	var cam_depth := cy * 0.35 - back_off
	var cam_lat := cx * 0.55
	# Height uses the horizontal scale so the overhead framing matches the
	# compressed depth footprint instead of towering twice as high.
	desired_position = C.HOME_PLATE + Vector3(cam_lat * FT_H, height_ft * FT_H, -cam_depth * FT_H)
	# Fixed orientation: yaw 0 (face center field, -Z) pitched -58 deg down.
	var pitch := deg_to_rad(58.0)
	var dir := Vector3(0.0, -sin(pitch), -cos(pitch))
	desired_target = desired_position + dir * 20.0


func _trauma_offset(delta: float) -> Vector3:
	var offset := Vector3.ZERO
	if _trauma > 0.0005:
		var amp := _trauma * _trauma * TRAUMA_SHAKE
		var t := _anim_time * 60.0
		# Vertical (Y) full, lateral (X) reduced - the impact reads mostly as a
		# vertical kick on the center-field lens (UE: Y full / cross-axis 0.6x).
		offset = Vector3(_noise(t, 3.0) * amp * 0.6, _noise(t, 11.0) * amp, 0.0)
		_trauma = maxf(0.0, _trauma - TRAUMA_DECAY * delta)
	return offset


func _update_hitstop() -> void:
	if _hitstop_frames > 0:
		Engine.time_scale = HITSTOP_SCALE
		_hitstop_frames -= 1
		if _hitstop_frames <= 0:
			Engine.time_scale = 1.0


func _update_flash(delta: float) -> void:
	if _flash_rect == null:
		return
	if _flash_time > 0.0:
		_flash_time = maxf(0.0, _flash_time - delta)
		_flash_rect.color.a = CONTACT_FADE_FROM * (_flash_time / CONTACT_FADE_SEC)
		_flash_rect.visible = true
	elif _flash_rect.visible:
		_flash_rect.color.a = 0.0
		_flash_rect.visible = false


func _build_flash() -> void:
	_flash_layer = CanvasLayer.new()
	_flash_layer.name = "ContactFlash"
	_flash_layer.layer = 40
	add_child(_flash_layer)
	_flash_rect = ColorRect.new()
	_flash_rect.color = Color(1, 1, 1, 0)
	_flash_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash_rect.visible = false
	_flash_layer.add_child(_flash_rect)


func _exit_tree() -> void:
	# Never leave the global clock stuck if we tear down mid-hitstop.
	if _hitstop_frames > 0:
		_hitstop_frames = 0
		Engine.time_scale = 1.0


func _noise(a: float, b: float) -> float:
	var v := sin(a * 12.9898 + b * 78.233) * 43758.5453
	return (v - floor(v)) * 2.0 - 1.0


func _sync_render_camera() -> void:
	if camera == null or camera.get_parent() == self:
		# Legacy fallback: the camera inherits this node's transform directly.
		return
	var render_transform := global_transform
	if camera.projection == Camera3D.PROJECTION_ORTHOGONAL and logical_vertical_pixels > 0:
		# One world-unit step per logical pixel keeps the ortho plate view,
		# its motion, and its shake locked to the render grid. The smooth
		# transform stays on this node, so snapping never feeds back into
		# the motion lerp. (Perspective broadcast/PlayCam modes skip this.)
		var pixel := camera.size / float(logical_vertical_pixels)
		var origin := render_transform.origin
		var snapped_right := snappedf(origin.dot(render_transform.basis.x), pixel)
		var snapped_up := snappedf(origin.dot(render_transform.basis.y), pixel)
		var depth := origin.dot(render_transform.basis.z)
		render_transform.origin = (
			render_transform.basis.x * snapped_right
			+ render_transform.basis.y * snapped_up
			+ render_transform.basis.z * depth
		)
	camera.global_transform = render_transform
