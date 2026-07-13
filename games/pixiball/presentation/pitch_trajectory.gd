class_name PixiballPitchTrajectory
extends RefCounted

## Presentation sampler for the semantic release/tunnel/plate pitch contract.
## The simulator owns the three measured points; this helper only produces a
## smooth world-space curve through them for the rendered ball and trail.

const ParkGeometry = preload("res://core/fielding/park_geometry.gd")

const TUNNEL_FRACTION := 0.52
const TUNNEL_BREAK_SHARE := 0.30
const FEET_TO_WORLD := ParkGeometry.VERTICAL_WORLD_PER_FOOT


static func sample(start: Vector3, finish: Vector3, path: Dictionary, progress: float) -> Vector3:
	var t := clampf(progress, 0.0, 1.0)
	if is_zero_approx(t):
		return start
	if is_equal_approx(t, 1.0):
		return finish
	var tunnel := _tunnel_world(start, finish, path)
	# Three-point Lagrange interpolation passes exactly through release,
	# semantic tunnel, and plate. Because tunnel.z is linear in flight depth,
	# forward travel remains monotonic while lateral/vertical movement bends.
	var k := TUNNEL_FRACTION
	var release_weight := ((t - k) * (t - 1.0)) / k
	var tunnel_weight := (t * (t - 1.0)) / (k * (k - 1.0))
	var plate_weight := (t * (t - k)) / (1.0 - k)
	return start * release_weight + tunnel * tunnel_weight + finish * plate_weight


static func _tunnel_world(start: Vector3, finish: Vector3, path: Dictionary) -> Vector3:
	var tunnel := start.lerp(finish, TUNNEL_FRACTION)
	var tunnel_ft: Array = path.get("tunnel_ft", [])
	if tunnel_ft.size() >= 3:
		var plate_ft: Array = path.get("plate_ft", [])
		var plate_ground_y := finish.y
		if plate_ft.size() >= 3:
			plate_ground_y -= float(plate_ft[2]) * FEET_TO_WORLD
		tunnel.x = float(tunnel_ft[0]) * FEET_TO_WORLD
		tunnel.y = plate_ground_y + float(tunnel_ft[2]) * FEET_TO_WORLD
		return tunnel
	var break_ft: Array = path.get("break_ft", [])
	if break_ft.size() >= 2:
		tunnel.x += float(break_ft[0]) * FEET_TO_WORLD * TUNNEL_BREAK_SHARE
		tunnel.y += float(break_ft[1]) * FEET_TO_WORLD * TUNNEL_BREAK_SHARE
	return tunnel
