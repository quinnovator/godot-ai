extends SceneTree

const PIXEL_AVATAR := preload("res://characters/pixel_actor_sprite.gd")
const STYLE_CONTRACT_PATH := "res://content/pixel/style_contract.json"
const LOD_NAMES := ["marquee", "battery", "diamond"]
const PROJECTOR_MAP := {"large": "marquee", "small": "battery", "tiny": "diamond"}
const CELL_SIZES := {
	"marquee": [28, 40],
	"battery": [14, 22],
	"diamond": [7, 11],
}
const BODY_HEIGHTS := {"marquee": 40, "battery": 22, "diamond": 11}
const HEAD_HEIGHTS := {"marquee": 16, "battery": 9, "diamond": 5}
const NATIVE_BODY_HEIGHTS := {"marquee": 160, "battery": 88, "diamond": 44}
const NATIVE_HEAD_HEIGHTS := {"marquee": 64, "battery": 36, "diamond": 20}
const REQUIRED_ROLES := [
	"pitcher", "catcher", "batter", "infielder",
	"outfielder", "umpire", "runner",
]

var _failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var avatar := PIXEL_AVATAR.new() as PixiballPixelActorSprite
	_expect(avatar != null, "pixel avatar presenter did not instantiate")
	if avatar == null:
		_finish()
		return
	var metrics := avatar.get_avatar_metrics()
	_validate_metrics(metrics)
	_validate_style_contract(metrics)
	avatar.free()
	_finish()


func _validate_metrics(metrics: Dictionary) -> void:
	var grid := int(metrics.get("authoring_grid_px", 0))
	_expect(grid == 4, "Pocket Giants must use the native 4px authoring grid")
	_expect(metrics.get("lod_names", []) == LOD_NAMES, "Pocket Giants LOD names or order changed")
	_expect(metrics.get("projector_lod_map", {}) == PROJECTOR_MAP, "projector tiers no longer map onto Pocket Giants LODs")
	_expect(metrics.get("lod_cell_sizes", {}) == CELL_SIZES, "authored Pocket Giants cell envelopes changed")

	var body_heights: Dictionary = metrics.get("lod_heights_design_units", {})
	var head_heights: Dictionary = metrics.get("lod_head_heights_design_units", {})
	var native_body_heights: Dictionary = metrics.get("lod_heights_px", {})
	var native_head_heights: Dictionary = metrics.get("lod_head_heights_px", {})
	for lod in LOD_NAMES:
		_expect(int(body_heights.get(lod, 0)) == BODY_HEIGHTS[lod], "%s body height changed" % lod)
		_expect(int(head_heights.get(lod, 0)) == HEAD_HEIGHTS[lod], "%s head height changed" % lod)
		_expect(int(native_body_heights.get(lod, 0)) == NATIVE_BODY_HEIGHTS[lod], "%s native body height changed" % lod)
		_expect(int(native_head_heights.get(lod, 0)) == NATIVE_HEAD_HEIGHTS[lod], "%s native head height changed" % lod)
		_expect(
			float(head_heights.get(lod, 0)) / float(maxi(1, int(body_heights.get(lod, 0)))) >= 0.40,
			"%s LOD is not face-first" % lod,
		)

	_expect(int(metrics.get("eye_highlight_px", 0)) == 4, "eye highlight must occupy one native grid cell")
	_expect(int(metrics.get("eye_highlight_design_units", 0)) == 1, "eye highlight must remain one design cell")
	_expect(
		metrics.get("eye_highlights_by_lod", {}) == {"marquee": true, "battery": true, "diamond": false},
		"Pocket Giants catch-light coverage changed",
	)
	_expect(
		metrics.get("ink_contour_by_lod", {}) == {"marquee": "full", "battery": "full", "diamond": "cap_and_feet"},
		"Pocket Giants contour hierarchy changed",
	)
	_expect(metrics.get("pose_keys", []) == ["anticipation", "action", "settle"], "pose-key hooks changed")
	_expect(metrics.get("role_silhouettes", []) == REQUIRED_ROLES, "role silhouette coverage changed")

	var features: Dictionary = metrics.get("facial_features_by_lod", {})
	for feature in ["eyes", "eye_highlights", "brows", "mouth", "cheek_smudge", "cap_brim_shadow"]:
		_expect(feature in features.get("marquee", []), "Marquee face is missing %s" % feature)
	for feature in ["eyes", "eye_highlights", "brows", "mouth"]:
		_expect(feature in features.get("battery", []), "Battery face is missing %s" % feature)
	_expect(features.get("diamond", []) == ["eye_mark"], "Diamond face grammar changed")


func _validate_style_contract(metrics: Dictionary) -> void:
	_expect(FileAccess.file_exists(STYLE_CONTRACT_PATH), "native pixel style contract is missing")
	if not FileAccess.file_exists(STYLE_CONTRACT_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(STYLE_CONTRACT_PATH))
	_expect(parsed is Dictionary, "native pixel style contract is not valid JSON")
	if not (parsed is Dictionary):
		return
	var contract: Dictionary = parsed
	var framebuffer: Array = contract.get("native_framebuffer", [])
	_expect(framebuffer.size() == 2 and int(framebuffer[0]) == 1280 and int(framebuffer[1]) == 720, "style contract lost the native 1280x720 framebuffer")
	_expect(int(contract.get("authoring_grid_px", 0)) == int(metrics.get("authoring_grid_px", -1)), "style contract and avatar disagree on the 4px authoring grid")
	var runtime: Dictionary = contract.get("runtime", {})
	_expect(String(runtime.get("render_path", "")) == "direct_root_canvas", "style contract lost the direct root canvas")
	_expect(not bool(runtime.get("offscreen_intermediate", true)), "style contract reintroduced an offscreen intermediate")
	var characters: Dictionary = contract.get("characters", {})
	_expect(String(characters.get("avatar_language", "")) == "saltlight_pocket_giants", "style contract lost the SALTLIGHT Pocket Giants language")
	_expect(characters.get("lod_names", []) == LOD_NAMES, "style contract lost the named Pocket Giants LODs")
	_expect(characters.get("projector_lod_map", {}) == PROJECTOR_MAP, "style contract projector mapping drifted from the runtime")
	var contract_body_heights: Dictionary = characters.get("lod_heights_px", {})
	var contract_head_heights: Dictionary = characters.get("lod_head_heights_px", {})
	for projector_tier in PROJECTOR_MAP:
		var lod: String = PROJECTOR_MAP[projector_tier]
		_expect(int(contract_body_heights.get(projector_tier, 0)) == NATIVE_BODY_HEIGHTS[lod], "style contract %s output height changed" % projector_tier)
		_expect(int(contract_head_heights.get(projector_tier, 0)) == NATIVE_HEAD_HEIGHTS[lod], "style contract %s head height changed" % projector_tier)
	_expect(int(characters.get("animation_fps", 0)) == 10, "style contract animation cadence changed")
	_expect(int(characters.get("maximum_ramp_tones", 0)) == 4, "style contract character ramp budget changed")


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)


func _finish() -> void:
	if _failures.is_empty():
		print("PIXIBALL_PIXEL_AVATAR_STYLE_OK language=pocket_giants grid=4px lods=marquee/battery/diamond roles=7")
		quit(0)
		return
	for failure in _failures:
		push_error("PIXIBALL_PIXEL_AVATAR_STYLE: %s" % failure)
	quit(1)
