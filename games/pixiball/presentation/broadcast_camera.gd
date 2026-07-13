class_name PixiballBroadcastCamera
extends Node

## Deterministic world-to-pixel view director.
##
## This keeps the simulation's three-axis baseball coordinates but replaces
## perspective projection with 320x180 composition coordinates expanded onto
## a 640x360 design grid. PixelScene maps those positions to 4px-native blocks
## rendered directly into 2560x1440;
## the resulting pixels never pass through a low-res viewport, 3D camera, or
## post-processing filter.

const C = preload("res://gameplay/game_constants.gd")
const ParkGeometry = preload("res://core/fielding/park_geometry.gd")
const Landmarks = preload("res://world/view_landmarks.gd")

const COMPOSITION_SIZE := Vector2(320, 180)
const DENSITY_SCALE := 2
const DESIGN_SIZE := COMPOSITION_SIZE * DENSITY_SCALE
const FRAMEBUFFER_SIZE := Vector2(2560, 1440)
const GRID_PIXEL_SIZE := 4
# Kept for consumers that use "logical" to mean the root rendering size.
const LOGICAL_SIZE := FRAMEBUFFER_SIZE
const PLATE_WORLD_PER_FOOT := ParkGeometry.VERTICAL_WORLD_PER_FOOT
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

@export var logical_vertical_pixels := 1440

var mode := MODE_INTRO
var target_node
var _trauma := 0.0
var _anim_time := 0.0
var _hitstop_frames := 0
var _pixel_shake := Vector2.ZERO


func _ready() -> void:
	add_to_group("pixiball_pixel_projector")
	set_process(true)
	_sync_world_mode()


func set_mode(next_mode: String, focus = null) -> void:
	if next_mode not in [MODE_INTRO, MODE_PITCHING, MODE_FIELDING, MODE_BATTING, MODE_DUGOUT]:
		push_warning("Unknown Pixiball pixel view: %s" % next_mode)
		return
	mode = next_mode
	target_node = focus
	_pixel_shake = Vector2.ZERO
	_sync_world_mode()


func plate_location_world(lateral_ft: float, height_ft: float) -> Vector3:
	return C.HOME_PLATE + Vector3(
		lateral_ft * PLATE_WORLD_PER_FOOT,
		height_ft * PLATE_WORLD_PER_FOOT,
		PITCH_PLANE_Z_OFFSET
	)


func projected_strike_zone() -> Rect2:
	# Authored dense-grid regions remain legible at native 1440p. Shared with
	# the world canvas through view_landmarks.gd so plate composition stays put.
	var composition_rect := Landmarks.strike_zone(mode)
	return Rect2(composition_rect.position * DENSITY_SCALE, composition_rect.size * DENSITY_SCALE)


func projected_strike_zone_native() -> Rect2:
	var design_rect := projected_strike_zone()
	return Rect2(design_rect.position * GRID_PIXEL_SIZE, design_rect.size * GRID_PIXEL_SIZE)


func plate_lateral_screen_sign() -> float:
	return -1.0 if mode == MODE_PITCHING else 1.0


func project_world(value: Vector3) -> Vector2:
	# Return design-grid coordinates because every world presenter is parented
	# beneath PixelScene's exact 4x transform.
	var result := Vector2.ZERO
	match mode:
		MODE_PITCHING:
			result = _project_pitching(value)
		MODE_BATTING:
			result = _project_batting(value)
		MODE_FIELDING:
			result = _project_fielding(value)
		MODE_DUGOUT:
			result = _project_dugout(value)
		_:
			result = _project_intro(value)
	result = (result + _pixel_shake) * DENSITY_SCALE
	return Vector2(roundi(result.x), roundi(result.y))


func project_world_native(value: Vector3) -> Vector2:
	return project_world(value) * GRID_PIXEL_SIZE


func project_pitch_world(value: Vector3) -> Vector2:
	# Actors and field landmarks use the compact broadcast projection, while a
	# pitched ball must finish inside the deliberately enlarged, readable zone.
	# Blend into that plate-space mapping only over the back half of flight so
	# release still comes directly out of the pitcher's hand.
	if mode not in [MODE_PITCHING, MODE_BATTING]:
		return project_world(value)
	var normal := project_world(value)
	var travel := clampf(
		(value.z - C.PITCHER_MOUND.z) / (C.HOME_PLATE.z - C.PITCHER_MOUND.z),
		0.0,
		1.0
	)
	var zone := projected_strike_zone()
	if zone.size.x <= 1.0 or zone.size.y <= 1.0:
		return normal
	if mode == MODE_PITCHING:
		# World-height projection is intentionally compact for field actors, but
		# the authored pitcher sprite is taller. Seat the first flight frames on
		# the visible release hand, then converge back to physical plate space.
		var release_weight := 1.0 - smoothstep(0.0, 0.28, travel)
		normal += Vector2(signf(value.x) * 4.0, -12.0) * DENSITY_SCALE * release_weight
	var lateral_ft := (value.x - C.HOME_PLATE.x) / PLATE_WORLD_PER_FOOT
	var height_ft := (value.y - C.HOME_PLATE.y) / PLATE_WORLD_PER_FOOT
	var plate_space := Vector2(
		zone.get_center().x + plate_lateral_screen_sign() * lateral_ft / STRIKE_ZONE_HALF_WIDTH_FT * zone.size.x * 0.5,
		zone.end.y - (height_ft - STRIKE_ZONE_BOTTOM_FT) / (STRIKE_ZONE_TOP_FT - STRIKE_ZONE_BOTTOM_FT) * zone.size.y
	)
	var plate_blend := smoothstep(0.42, 1.0, travel)
	return normal.lerp(plate_space, plate_blend).round()


func actor_lod(value: Vector3, role := "fielder") -> String:
	match mode:
		MODE_PITCHING:
			# Pitcher and plate battery share the 22-cell gameplay tier. The former
			# 40-cell marquee body hid the rubber and made the mound read as a base.
			if role == "pitcher":
				return "small"
			if value.z <= 5.0:
				return "large"
			if role == "umpire":
				return "tiny"
			if role in ["batter", "catcher"] or value.z <= 24.0:
				return "small"
			return "tiny"
		MODE_BATTING:
			return "large" if value.z >= 12.0 else "small"
		MODE_FIELDING:
			return "tiny"
		MODE_DUGOUT:
			return "large"
		_:
			return "small" if value.z > 8.0 else "large"


func actor_visible(value: Vector3, role := "fielder") -> bool:
	# Fixed-room composition is intentionally selective. A center-field pitch
	# view needs four readable silhouettes, not nine distant figures collapsing
	# into the same twenty-pixel patch.
	match mode:
		MODE_PITCHING:
			return role in ["pitcher", "batter", "catcher", "umpire"]
		MODE_BATTING:
			return role in ["pitcher", "batter"]
		MODE_DUGOUT:
			return value.z > 8.0
		_:
			return true


func actor_screen_offset(_value: Vector3, role := "fielder") -> Vector2:
	# Pitching offsets are authored so the plate battery fans out around the
	# strike-zone chalk: batter left of plate, catcher low under the zone,
	# umpire clear right. Values are design cells (1 cell = 4 native px).
	var offset := Vector2.ZERO
	if mode == MODE_PITCHING:
		match role:
			"batter":
				offset = Vector2(-11, 1)
			"catcher":
				offset = Vector2(0, 7)
			"umpire":
				offset = Vector2(8, 1)
			"pitcher":
				# Plant the marquee figure a cell onto the rubber so delivery
				# reads from the mound island, not floating over clay.
				offset = Vector2(0, 1)
	elif mode == MODE_BATTING and role == "batter":
		offset = Vector2(-22, -1)
	return offset * DENSITY_SCALE


func depth_order(value: Vector3, role := "fielder") -> int:
	# Near actors (high screen-y on the pitch lane) draw above far ones. Plate
	# roles get a stable within-cluster stack: catcher in front of batter in
	# front of umpire so the crouch mitt never sinks under the hitter.
	var base := 30 + int(project_world(Vector3(value.x, 0.08, value.z)).y)
	if mode == MODE_FIELDING:
		return 40 + int(project_world(value).y)
	if mode == MODE_PITCHING:
		# Bonuses beat the ~5-cell screen-y gap between plate actors so the
		# stack is role-stable: pitcher > catcher > batter > umpire.
		match role:
			"pitcher":
				return base + 40
			"catcher":
				return base + 14
			"batter":
				return base + 6
			"umpire":
				return base
	return base


func shake(strength := 0.3) -> void:
	_trauma = minf(1.0, _trauma + strength)


func contact_juice(exit_velocity_mph: float) -> void:
	# Impact read is the local contact burst (bible 9.3) plus hitstop and
	# whole-pixel shake here; never a screen flash (bible 11.5).
	var force := clampf((exit_velocity_mph - 60.0) / 55.0, 0.0, 1.0)
	_hitstop_frames = 3 if force > 0.65 else 2
	_trauma = minf(1.0, _trauma + 0.45 + force * 0.4)


func _process(delta: float) -> void:
	_anim_time += delta
	_update_trauma(delta)
	_update_hitstop()
	if mode == MODE_FIELDING and is_instance_valid(target_node):
		var target_position := _world_position_of(target_node)
		for world in get_tree().get_nodes_in_group("pixiball_pixel_world"):
			if world.has_method("set_field_focus"):
				world.call("set_field_focus", target_position)


func _project_pitching(value: Vector3) -> Vector2:
	# Use the real plate-to-second-base depth interval. This keeps home, mound,
	# and second collinear in the authored center-field view and prevents the
	# old extreme lower-right to upper-left camera skew.
	var depth := clampf(
		(value.z - C.SECOND_BASE.z) / (C.HOME_PLATE.z - C.SECOND_BASE.z),
		0.0,
		1.0
	)
	var lane_spec: Dictionary = Landmarks.projection_lane(MODE_PITCHING)
	var lane: Vector2 = (lane_spec.near as Vector2).lerp(lane_spec.far as Vector2, depth)
	var lateral_scale := lerpf(2.8, 1.45, depth)
	return lane + Vector2(value.x * lateral_scale, -value.y * lerpf(4.0, 2.5, depth))


func _project_batting(value: Vector3) -> Vector2:
	var depth := clampf((C.HOME_PLATE.z - value.z) / 18.0, 0.0, 1.0)
	var lane_spec: Dictionary = Landmarks.projection_lane(MODE_BATTING)
	var lane: Vector2 = (lane_spec.near as Vector2).lerp(lane_spec.far as Vector2, depth)
	var lateral_scale := lerpf(4.2, 1.9, depth)
	return lane + Vector2(value.x * lateral_scale, -value.y * lerpf(4.2, 2.4, depth))


func _project_fielding(value: Vector3) -> Vector2:
	var focus_shift := Vector2.ZERO
	if is_instance_valid(target_node):
		var focus := _world_position_of(target_node)
		focus_shift.x = clampf(focus.x * -0.35, -22.0, 22.0)
		focus_shift.y = clampf((focus.z + 4.0) * -0.18, -14.0, 14.0)
	var origin: Vector2 = Landmarks.projection_lane(MODE_FIELDING).origin
	return Vector2(
		origin.x + value.x * 3.15,
		origin.y + (value.z - C.HOME_PLATE.z) * 2.0 - value.y * 2.7
	) + focus_shift


func _project_intro(value: Vector3) -> Vector2:
	var depth := clampf((value.z + 10.0) / 32.0, 0.0, 1.0)
	var lane_spec: Dictionary = Landmarks.projection_lane(MODE_INTRO)
	var lane: Vector2 = (lane_spec.near as Vector2).lerp(lane_spec.far as Vector2, depth)
	return lane + Vector2(value.x * lerpf(2.7, 1.3, depth), -value.y * 3.0)


func _project_dugout(value: Vector3) -> Vector2:
	var origin: Vector2 = Landmarks.projection_lane(MODE_DUGOUT).origin
	return Vector2(origin.x + value.x * 3.0, origin.y + (value.z - 10.0) * 0.7 - value.y * 4.0)


func _update_trauma(delta: float) -> void:
	if _trauma <= 0.001:
		_trauma = 0.0
		_pixel_shake = Vector2.ZERO
		return
	var amplitude := _trauma * _trauma * 3.0
	var tick: float = floorf(_anim_time * 30.0)
	_pixel_shake = Vector2(
		roundi(_noise(tick, 3.0) * amplitude),
		roundi(_noise(tick, 11.0) * amplitude),
	)
	_trauma = maxf(0.0, _trauma - delta * 3.8)


func _update_hitstop() -> void:
	if _hitstop_frames <= 0:
		return
	Engine.time_scale = 0.08
	_hitstop_frames -= 1
	if _hitstop_frames <= 0:
		Engine.time_scale = 1.0


func _sync_world_mode() -> void:
	for world in get_tree().get_nodes_in_group("pixiball_pixel_world"):
		if world.has_method("set_view_mode"):
			world.call("set_view_mode", mode)


func _world_position_of(node: Variant) -> Vector3:
	if node == null:
		return C.HOME_PLATE
	var value: Variant = node.get("global_position")
	return value if value is Vector3 else C.HOME_PLATE


func _noise(a: float, b: float) -> float:
	var value := sin(a * 12.9898 + b * 78.233) * 43758.5453
	return (value - floor(value)) * 2.0 - 1.0


func _exit_tree() -> void:
	if _hitstop_frames > 0 or not is_equal_approx(Engine.time_scale, 1.0):
		_hitstop_frames = 0
		Engine.time_scale = 1.0
