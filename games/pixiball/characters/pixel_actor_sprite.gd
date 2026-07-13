class_name PixiballPixelActorSprite
extends Node2D

## "Pocket Giants" presenter for a BallplayerActor logic proxy (art bible §8).
##
## Every mark is authored in integer design cells, then the PixelScene's exact
## 4x CanvasItem transform rasterizes each cell as a native 4x4 block directly
## into the 1280x720 root framebuffer. There is no low-resolution texture,
## filtered silhouette, or post-process upscale.
##
## Three fixed LODs (bible §8.1):
##   Marquee 28x40 cells, head 16 — dugout bench, shell portraits, heroes.
##   Battery 14x22 cells, head 9  — pitcher/batter/catcher/umpire in play views.
##   Diamond  7x11 cells, head 5  — fielders, runners, base coaches afield.
## Marquee/Battery carry a full 1-cell ink contour; Diamond carries ink under
## the cap and feet only and otherwise reads by silhouette value (§5.2).

# Identity roles (bible §3.1) — mood-invariant by design: characters are the
# constant human element and re-grade only through the world light around them.
const INK := Color("0e1220")
const BALL_WHITE := Color("f8f4e6")
const STITCH_RED := Color("d94a3d")
const LANTERN_GOLD := Color("ffc65a")
const SIGNAL_TEAL := Color("55d6c4")
const CHALK_PAPER := Color("efe9d4")
const STEEL_TEXT := Color("9db2c4")

# Equipment palette (bible §8.4).
const BAT_WOOD := Color("a5713f")
const BAT_GRAIN := Color("c99457")
const LEATHER_MAIN := Color("c17b4f")
const LEATHER_LIT := Color("dea16c")
const GEAR_SHELL := Color("2b4359")
const GEAR_BAR := Color("9db2c4")
const UMPIRE_CLOTH := Color("1b2138")
const CLAY_SMUDGE := Color("dea16c")
# The single sanctioned sweat cell for the gassed pitcher (§8.6), authored to
# the day sea_glint value so it reads cool against warm skin in every mood.
const SWEAT_GLINT := Color("cdeae3")

# Night lantern grade (§3.3, §3.4). The night world compresses to V0-V2
# indigo, so the mood-invariant day value pairs lose their internal read:
# ink features drown inside the darker skin ramps, leather sits on the same
# rung as mid skin, and catcher/umpire gear falls into the night V1 band.
# Characters re-grade "through the world light around them": lit steps lerp
# warm toward the night window_lit family and shadow steps sink cool toward
# the night sky_high indigo family — opaque authored colors, night mood only.
const NIGHT_LIFT_ANCHOR := Color("ffd98a")
const NIGHT_SHADE_ANCHOR := Color("1a1f38")
const NIGHT_SKIN_LIFT := 0.30
const NIGHT_HAIR_LIFT := 0.16
const NIGHT_TRIM_LIFT := 0.18
const NIGHT_SHADOW_SINK := 0.45
# Authored night equipment steps: leather follows the night clay ramp (§8.4)
# so mitts separate from lamp-lifted skin; gear shell and umpire cloth lift
# onto the night V3/V4 rungs so both silhouettes survive a V1 backdrop.
const LEATHER_MAIN_NIGHT := Color("6d4b45")
const LEATHER_LIT_NIGHT := Color("8c6253")
const GEAR_SHELL_NIGHT := Color("3a5570")
const UMPIRE_CLOTH_NIGHT := Color("2a3352")

const LOD_MARQUEE := "marquee"
const LOD_BATTERY := "battery"
const LOD_DIAMOND := "diamond"

# Canonical §8.6 game-state expression vocabulary. BallplayerActor validates
# its expression channel against this list; the drawer maps each state onto
# brows/mouth at Marquee/Battery and onto posture at every LOD.
const EXPRESSION_STATES := [
	"neutral", "focus", "good_play", "miss", "dejected",
	"hero", "conceded", "gassed",
]

# The broadcast projector speaks distance tiers; the character system owns the
# translation onto the three Pocket Giants LODs. Pass 06 animation and pass 10
# shell portraits consume this map plus set_lod_override().
const PROJECTOR_LOD_MAP := {
	"large": LOD_MARQUEE,
	"small": LOD_BATTERY,
	"tiny": LOD_DIAMOND,
}

# Authored LOD envelopes in design cells (1 cell = exactly 4 native px) plus
# the per-LOD face grammar (§8.2) and contour rules (§5.2).
const AVATAR_METRICS := {
	"authoring_grid_px": 4,
	"lod_names": ["marquee", "battery", "diamond"],
	"projector_lod_map": {"large": "marquee", "small": "battery", "tiny": "diamond"},
	"lod_cell_sizes": {"marquee": [28, 40], "battery": [14, 22], "diamond": [7, 11]},
	"lod_heights_design_units": {"marquee": 40, "battery": 22, "diamond": 11},
	"lod_head_heights_design_units": {"marquee": 16, "battery": 9, "diamond": 5},
	"lod_heights_px": {"marquee": 160, "battery": 88, "diamond": 44},
	"lod_head_heights_px": {"marquee": 64, "battery": 36, "diamond": 20},
	"head_share_min": 0.40,
	"eye_highlight_px": 4,
	"eye_highlight_design_units": 1,
	"eye_highlights_by_lod": {"marquee": true, "battery": true, "diamond": false},
	"ink_contour_by_lod": {"marquee": "full", "battery": "full", "diamond": "cap_and_feet"},
	"facial_features_by_lod": {
		"marquee": ["eyes", "eye_highlights", "brows", "mouth", "cheek_smudge", "cap_brim_shadow"],
		"battery": ["eyes", "eye_highlights", "brows", "mouth"],
		"diamond": ["eye_mark"],
	},
	"pose_keys": ["anticipation", "action", "settle"],
	"role_silhouettes": [
		"pitcher", "catcher", "batter", "infielder",
		"outfielder", "umpire", "runner",
	],
	"expression_states": EXPRESSION_STATES,
	"smear_frame_budget": {"pitch": 1, "swing": 1},
	"reception_mitt_boost": true,
}

var host: Node
var projector: Node
var _lod := LOD_BATTERY
var _lod_override := ""
var _draw_key := ""
var _mood := "day"
var _leather_main := LEATHER_MAIN
var _leather_lit := LEATHER_LIT
var _gear_shell := GEAR_SHELL
var _umpire_cloth := UMPIRE_CLOTH


func bind(actor: Node) -> void:
	host = actor
	name = "%sPixels" % actor.name
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_as_relative = false
	set_process(true)
	queue_redraw()


func get_avatar_metrics() -> Dictionary:
	return AVATAR_METRICS.duplicate(true)


## Canonical current LOD name (marquee/battery/diamond).
func lod_name() -> String:
	return _lod_override if not _lod_override.is_empty() else _lod


## Pass-10 hook: shell portraits pin a bound sprite to one LOD regardless of
## the projector. Pass an empty string to return control to the projector.
func set_lod_override(lod: String) -> void:
	_lod_override = lod if lod in AVATAR_METRICS.lod_names else ""
	queue_redraw()


func _process(_delta: float) -> void:
	if not is_instance_valid(host):
		visible = false
		return
	visible = bool(host.visible)
	if not visible:
		return
	if not is_instance_valid(projector):
		projector = get_tree().get_first_node_in_group("pixiball_pixel_projector")
	if not is_instance_valid(projector):
		return
	var world_position: Vector3 = host.global_position
	if projector.has_method("actor_visible"):
		visible = bool(projector.call("actor_visible", world_position, host.get_role()))
	if not visible:
		return
	var projected: Vector2 = projector.call("project_world", world_position)
	if projector.has_method("actor_screen_offset"):
		var offset: Variant = projector.call("actor_screen_offset", world_position, host.get_role())
		if offset is Vector2:
			projected += offset
	position = Vector2(roundi(projected.x), roundi(projected.y))
	var tier := String(projector.call("actor_lod", world_position, host.get_role()))
	_lod = String(PROJECTOR_LOD_MAP.get(tier, LOD_BATTERY))
	z_index = int(projector.call("depth_order", world_position))
	_mood = _world_mood()
	var pose: Dictionary = host.get_pixel_pose()
	var next_key := "%s/%s/%s/%s/%s/%s/%s/%s/%s/%s/%s/%s/%s" % [
		_mood,
		lod_name(),
		pose.get("action", "idle"),
		pose.get("frame", 0),
		pose.get("pose_key", "action"),
		pose.get("facing", 1),
		pose.get("role_variant", "fielder"),
		pose.get("highlighted", false),
		pose.get("expression", ""),
		pose.get("smear", false),
		pose.get("reception", false),
		pose.get("brim_pop", false),
		host.get_generation_signature(),
	]
	if next_key != _draw_key:
		_draw_key = next_key
		queue_redraw()


func _draw() -> void:
	if not is_instance_valid(host):
		return
	var night := _mood == "night"
	var palette: Dictionary = host.get_pixel_palette()
	if night:
		palette = _night_graded(palette)
	_leather_main = LEATHER_MAIN_NIGHT if night else LEATHER_MAIN
	_leather_lit = LEATHER_LIT_NIGHT if night else LEATHER_LIT
	_gear_shell = GEAR_SHELL_NIGHT if night else GEAR_SHELL
	_umpire_cloth = UMPIRE_CLOTH_NIGHT if night else UMPIRE_CLOTH
	var pose: Dictionary = host.get_pixel_pose()
	match lod_name():
		LOD_DIAMOND:
			_draw_diamond(palette, pose)
		LOD_MARQUEE:
			_draw_body(palette, pose, 2)
		_:
			_draw_body(palette, pose, 1)


# ---------------------------------------------------------------------------
# Shared stance authoring. All coordinates are battery-scale design cells with
# the actor anchored at the feet; Marquee doubles them. Hands are absolute
# (x multiplied by facing at draw time); poses land on whole cells only.
# ---------------------------------------------------------------------------

func _compute_stance(pose: Dictionary, variant: String) -> Dictionary:
	var action := String(pose.get("action", "idle"))
	var pose_key := String(pose.get("pose_key", "action"))
	var frame := int(pose.get("frame", 0))
	var stance := {
		"crouch": 0, "lean": 0, "bob": 0, "spread": 0,
		"stretch": 0, "twist": 0, "head_drop": 0,
		"l_hand": Vector2i(-7, -7), "r_hand": Vector2i(7, -7),
		"legs_run": false, "stride": false, "mitt_boost": false,
	}
	match variant:
		"catcher":
			stance.crouch = 4
			stance.spread = 2
			stance.l_hand = Vector2i(-7, -9)
			stance.r_hand = Vector2i(5, -6)
		"infielder":
			stance.crouch = 2
			stance.spread = 1
			stance.l_hand = Vector2i(-7, -4)
			stance.r_hand = Vector2i(6, -5)
		"outfielder":
			stance.spread = 1
		"umpire":
			stance.crouch = 2
			stance.spread = 2
			stance.l_hand = Vector2i(-7, -5)
			stance.r_hand = Vector2i(7, -5)
		"runner":
			stance.lean = 2
	match action:
		"run":
			stance.legs_run = true
			stance.lean = maxi(stance.lean, 2) if variant == "runner" else maxi(stance.lean, 1)
			stance.bob = -1 if frame % 2 == 0 else 0
			if frame % 2 == 0:
				stance.l_hand = Vector2i(6, -9)
				stance.r_hand = Vector2i(-7, -6)
			else:
				stance.l_hand = Vector2i(-7, -6)
				stance.r_hand = Vector2i(6, -9)
		"field_ready":
			stance.crouch = maxi(stance.crouch, 2)
			stance.spread = maxi(stance.spread, 1)
			stance.l_hand = Vector2i(-7, -4)
			stance.r_hand = Vector2i(6, -5)
		"pitch":
			match pose_key:
				"anticipation":
					# Wind-up compresses the whole figure to 90% height (§8.5).
					stance.stretch = -2
					stance.l_hand = Vector2i(-2, -13)
					stance.r_hand = Vector2i(2, -13)
				"action":
					# Drive stretches to 115% with a 3-cell stride (§8.5).
					stance.stretch = 3
					stance.stride = true
					stance.lean = -1
					stance.l_hand = Vector2i(-9, -13)
					stance.r_hand = Vector2i(8, -19)
				_:
					stance.lean = -2
					stance.l_hand = Vector2i(-4, -9)
					stance.r_hand = Vector2i(-7, -11)
		"throw", "field_throw":
			match pose_key:
				"anticipation":
					stance.l_hand = Vector2i(-6, -11)
					stance.r_hand = Vector2i(5, -14)
				"action":
					stance.lean = -1
					stance.l_hand = Vector2i(-8, -12)
					stance.r_hand = Vector2i(8, -18)
				_:
					stance.l_hand = Vector2i(-5, -9)
					stance.r_hand = Vector2i(-8, -12)
		"swing":
			match pose_key:
				"anticipation":
					# Load twists the shoulders 2 cells back (§8.5).
					stance.lean = -1
					stance.twist = -2
					stance.l_hand = Vector2i(5, -15)
					stance.r_hand = Vector2i(7, -16)
				"action":
					stance.lean = 1
					stance.l_hand = Vector2i(7, -11)
					stance.r_hand = Vector2i(9, -11)
				_:
					stance.l_hand = Vector2i(-3, -17)
					stance.r_hand = Vector2i(-5, -18)
		"catch":
			# The mitt doubles on the single reception frame only (§8.5), keyed
			# to the glove_contact marker tick rather than the whole action key.
			stance.mitt_boost = bool(pose.get("reception", false))
			match pose_key:
				"anticipation":
					stance.l_hand = Vector2i(-7, -12)
					stance.r_hand = Vector2i(5, -8)
				"action":
					stance.l_hand = Vector2i(-8, -16)
					stance.r_hand = Vector2i(5, -9)
				_:
					stance.l_hand = Vector2i(-6, -10)
					stance.r_hand = Vector2i(5, -8)
		"celebrate":
			# Home-run hero read (§8.6): a full 115% stretch jump under raised arms.
			stance.bob = -1 if frame % 2 == 0 else 0
			stance.stretch = 3 if frame % 2 == 0 else 1
			stance.l_hand = Vector2i(-8, -19)
			stance.r_hand = Vector2i(8, -19)
		_:
			if frame % 2 == 1:
				stance.l_hand.y += 1
				stance.r_hand.y += 1
	# §8.6 posture channel: outcome states re-shape the body only between the
	# committed §8.5 action keys, so squash/stretch keys stay authoritative.
	if action in ["idle", "field_ready", "run", "celebrate"]:
		match String(pose.get("expression", "")):
			"focus":
				stance.lean = maxi(int(stance.lean), 1)
			"good_play":
				stance.stretch += 1
			"miss":
				stance.head_drop = 1
			"dejected":
				stance.stretch -= 2
				stance.head_drop = 1
			"hero":
				if action != "celebrate":
					stance.stretch += 2
					stance.l_hand = Vector2i(-8, -19)
					stance.r_hand = Vector2i(8, -19)
			"conceded":
				stance.stretch -= 1
				stance.head_drop = 1
			"gassed":
				stance.crouch += 1
				stance.head_drop = 1
	return stance


func _expression(pose: Dictionary) -> Dictionary:
	# The §8.6 game-state channel wins when set; "neutral" and unset states
	# fall back to the action-derived read so faces never go blank.
	match String(pose.get("expression", "")):
		"focus":
			return {"brow": "inner_down", "mouth": "dot"}
		"good_play":
			return {"brow": "up", "mouth": "grin"}
		"miss":
			return {"brow": "inner_up", "mouth": "frown"}
		"dejected":
			return {"brow": "inner_up", "mouth": "open"}
		"hero":
			return {"brow": "up", "mouth": "open_grin"}
		"conceded":
			return {"brow": "low", "mouth": "frown"}
		"gassed":
			return {"brow": "low", "mouth": "wavy"}
	var action := String(pose.get("action", "idle"))
	var pose_key := String(pose.get("pose_key", "action"))
	match action:
		"celebrate":
			return {"brow": "up", "mouth": "open_grin"}
		"pitch", "swing", "throw", "field_throw":
			if pose_key == "anticipation":
				return {"brow": "inner_down", "mouth": "dot"}
			if pose_key == "action":
				return {"brow": "inner_down", "mouth": "open"}
			return {"brow": "flat", "mouth": "line"}
		"catch":
			return {"brow": "inner_down", "mouth": "open" if pose_key == "action" else "dot"}
		"slide":
			return {"brow": "inner_up", "mouth": "open"}
		"run":
			return {"brow": "inner_down", "mouth": "line"}
		_:
			if bool(pose.get("highlighted", false)):
				return {"brow": "inner_down", "mouth": "dot"}
			return {"brow": "flat", "mouth": "line"}


# ---------------------------------------------------------------------------
# Marquee + Battery share one skeleton at scale 2 / scale 1. Both carry a
# full 1-cell ink contour on every mass (§5.2).
# ---------------------------------------------------------------------------

func _draw_body(p: Dictionary, pose: Dictionary, s: int) -> void:
	var action := String(pose.get("action", "idle"))
	var facing := int(pose.get("facing", 1))
	var variant := String(pose.get("role_variant", "fielder"))
	var stance := _compute_stance(pose, variant)
	var glove_left := String(host.get_throwing_hand()) != "left"

	_ground_shade(5 * s)
	if bool(pose.get("highlighted", false)):
		_focus_ring(4 * s + 2)
	if action == "slide":
		_draw_slide_body(p, pose, s)
		return

	var f := facing
	var crouch: int = int(stance.crouch) * s
	var lean: int = int(stance.lean) * s * f
	var bob: int = int(stance.bob) * s
	var spread: int = int(stance.spread)
	# Squash/stretch lands on whole cells: positive stretch lengthens the legs
	# (115% drive), negative compresses the figure (90% wind-up) (§8.5).
	var stretch: int = int(stance.stretch) * s
	var twist: int = int(stance.twist) * s * f
	var head_drop: int = int(stance.head_drop) * s
	var cloth: Color = _umpire_cloth if variant == "umpire" else p.cloth
	var cloth_shadow: Color = INK if variant == "umpire" else p.cloth_shadow
	var trim: Color = p.trim
	var head_h := 9 * s if s == 1 else 16
	var torso_h := 6 * s if s == 1 else 14
	var leg_top := -(7 * s if s == 1 else 10) + crouch - stretch + bob
	var torso_top := leg_top - torso_h
	var head_top := torso_top - head_h + head_drop

	# Legs, socks, oversized shoes (+30% masses so the pose reads at range).
	var hip_y := leg_top
	var ankle_y := -2 * s + bob
	var l_ankle := Vector2i((-3 - spread) * s, ankle_y)
	var r_ankle := Vector2i((3 + spread) * s, ankle_y)
	if stance.legs_run:
		var step := 1 if int(pose.get("frame", 0)) % 2 == 0 else -1
		l_ankle = Vector2i(-4 * s * step * f, ankle_y)
		r_ankle = Vector2i(4 * s * step * f, ankle_y + s)
	elif stance.stride:
		# 3-cell drive stride off the square stance (§8.5).
		l_ankle = Vector2i(-6 * s * f, ankle_y)
		r_ankle = Vector2i(3 * s * f, ankle_y)
	var leg_w := 2 * s
	var drive_boost := s if variant == "pitcher" else 0
	_limb(Vector2i(-2 * s + lean, hip_y), l_ankle, p.pants, leg_w, true)
	_limb(Vector2i(2 * s + lean, hip_y), r_ankle, p.pants, leg_w + drive_boost, true)
	_rect(l_ankle.x - s, ankle_y - s, 2 * s, s, trim if variant != "umpire" else _umpire_cloth)
	_rect(r_ankle.x - s, ankle_y - s, 2 * s, s, trim if variant != "umpire" else _umpire_cloth)
	_shoe(l_ankle.x, f, s)
	_shoe(r_ankle.x, f, s)
	if variant == "catcher":
		for shin_x in [l_ankle.x, r_ankle.x]:
			_rect(shin_x - s, ankle_y - 3 * s, 2 * s, 3 * s, GEAR_BAR)
			_rect(shin_x - s, ankle_y - 2 * s, 2 * s, 1, _gear_shell)

	# Tapered torso: chest wider than hips, no neck; ink pass then cloth bands.
	# The chest band carries the shoulder twist so the swing load reads (§8.5).
	var chest_w := (12 + (2 if variant in ["catcher", "umpire"] else 0)) * s
	var hip_w := 8 * s
	var mid_w := (chest_w + hip_w) / 2
	var band_h := torso_h / 3
	var bands := [
		[torso_top, chest_w, band_h, twist],
		[torso_top + band_h, mid_w, band_h, twist / 2],
		[torso_top + 2 * band_h, hip_w, torso_h - 2 * band_h, 0],
	]
	for band in bands:
		_rect(lean + int(band[3]) - int(band[1]) / 2 - 1, int(band[0]) - 1, int(band[1]) + 2, int(band[2]) + 2, INK)
	for band in bands:
		_rect(lean + int(band[3]) - int(band[1]) / 2, int(band[0]), int(band[1]), int(band[2]), cloth)
	_rect(lean - hip_w / 2, leg_top - s, hip_w, s, cloth_shadow)
	if variant == "umpire":
		_rect(lean + twist - chest_w / 2 + s, torso_top + s, chest_w - 2 * s, 2 * s, GEAR_BAR)
	elif variant == "catcher":
		_rect(lean + twist - chest_w / 2 + s, torso_top + s, chest_w - 2 * s, torso_h - 2 * s, _gear_shell)
		for bar in range(2):
			_rect(lean + twist - chest_w / 2 + s, torso_top + (2 + bar * 2) * s, chest_w - 2 * s, 1, GEAR_BAR)
	else:
		_rect(lean + twist - chest_w / 2, torso_top + s, chest_w, s, trim)
		_rect(lean + twist - chest_w / 2, torso_top + 2 * s, chest_w, 1, p.trim_shadow)
		_team_logo(lean + twist + 3 * s * f, torso_top + 3 * s, p)
		if s == 2 and int(host.get_jersey_number()) > 0:
			PixiballPixelArtStyle.pixel_text(
				self,
				str(mini(99, int(host.get_jersey_number()))),
				Vector2(lean + twist - 3, torso_top + 8),
				INK,
			)

	# Arms are 1-2 cell ribbons with oversized hand masses.
	var shoulder_y := torso_top + s
	var l_hand := Vector2i(int(stance.l_hand.x) * s * f, int(stance.l_hand.y) * s + bob)
	var r_hand := Vector2i(int(stance.r_hand.x) * s * f, int(stance.r_hand.y) * s + bob)
	_limb(Vector2i(-5 * s * f + lean + twist, shoulder_y), l_hand, p.skin, s, true)
	_limb(Vector2i(5 * s * f + lean + twist, shoulder_y), r_hand, p.skin, s, true)
	if bool(pose.get("smear", false)) and action == "pitch":
		# 1-frame authored arm-arc smear: two opaque clusters trailing the
		# release hand along the delivery arc (§8.5) — never a blur.
		_rect(r_hand.x - 3 * s * f, r_hand.y - s, 2 * s, s, p.skin)
		_rect(r_hand.x - 6 * s * f, r_hand.y + 2 * s, 2 * s, s, p.skin_shadow)

	# Head: 40%+ of the envelope, round-cornered, full ink contour, cap or
	# helmet in the team trim family, face grammar per LOD (§8.2).
	var head_cx := lean + (s if stance.lean != 0 else 0)
	if s == 2:
		_draw_marquee_head(head_cx, head_top, p, pose, variant, f)
	else:
		_draw_battery_head(head_cx, head_top, p, pose, variant, f)

	# Equipment resolves after the body so masses break the silhouette.
	var glove_hand := l_hand if glove_left else r_hand
	var bare_hand := r_hand if glove_left else l_hand
	match variant:
		"batter":
			_hand(l_hand, p.skin, s)
			_hand(r_hand, p.skin, s)
			_draw_bat(r_hand, action, String(pose.get("pose_key", "action")), f, s, bool(pose.get("smear", false)))
		"umpire":
			_hand(l_hand, p.skin, s)
			_hand(r_hand, p.skin, s)
		"catcher":
			_hand(bare_hand, p.skin, s)
			_mitt(glove_hand, (4 if not stance.mitt_boost else 5) * s)
		_:
			_hand(bare_hand, p.skin, s)
			_mitt(glove_hand, (3 if not stance.mitt_boost else 4) * s)


func _draw_slide_body(p: Dictionary, pose: Dictionary, s: int) -> void:
	var f := int(pose.get("facing", 1))
	var variant := String(pose.get("role_variant", "fielder"))
	var cloth: Color = _umpire_cloth if variant == "umpire" else p.cloth
	_rect(-2 * s * f - f - 1, -5 * s - 1, 8 * s * f + 2 * f, 4 * s + 2, INK)
	_rect(-2 * s * f, -5 * s, 8 * s * f, 4 * s, cloth)
	_rect(4 * s * f, -3 * s - 1, 8 * s * f + f, 2 * s + 1, INK)
	_rect(4 * s * f, -3 * s, 8 * s * f, 2 * s, p.pants)
	_rect(10 * s * f, -2 * s, 2 * s * f, s, p.trim)
	_limb(Vector2i(-s * f, -4 * s), Vector2i(-6 * s * f, -2 * s), p.skin, s, true)
	if s == 2:
		_draw_marquee_head(-5 * s * f, -5 * s - 16, p, pose, variant, f)
	else:
		_draw_battery_head(-5 * s * f, -5 * s - 9, p, pose, variant, f)
	if variant == "batter":
		_draw_bat(Vector2i(-6 * s * f, -2 * s), "idle", "action", f, s)
	elif variant != "umpire":
		_mitt(Vector2i(-7 * s * f, -2 * s), 3 * s)


func _draw_battery_head(cx: int, top: int, p: Dictionary, pose: Dictionary, variant: String, f: int) -> void:
	var e := _expression(pose)
	# Full ink contour with a stepped round top; the head sits directly on
	# the shoulders (no neck), so the bottom edge merges into the torso.
	_rect(cx - 5, top, 11, 1, INK)
	_rect(cx - 6, top + 1, 13, 8, INK)
	# Face fill under the headwear line.
	_rect(cx - 5, top + 3, 11, 5, p.skin)
	_rect(cx - 4, top + 8, 9, 1, p.skin_shadow)
	_rect(cx - 5, top + 4, 1, 3, p.skin_shadow)
	_rect(cx + 5, top + 4, 1, 3, p.skin_shadow)
	# Hair framing below the headwear.
	_rect(cx - 5, top + 3, 2, 2, p.hair)
	_rect(cx + 4, top + 3, 2, 2, p.hair)
	_headwear(cx, top, p, variant, f, 1, bool(pose.get("brim_pop", false)))
	# Cap-brim shadow band across the brow line.
	_rect(cx - 4, top + 3, 9, 1, p.skin_shadow)
	# Brows (1 cell), 2x2 ink eyes with a single ball-white catch-light.
	var brow_y := top + 4
	var tilt := 0
	if String(e.brow) == "inner_down":
		tilt = 1
	elif String(e.brow) == "inner_up" or String(e.brow) == "up":
		tilt = -1
	var brow_drop := 1 if String(e.brow) == "low" else 0
	_rect(cx - 4, brow_y + brow_drop + maxi(0, tilt * f), 2, 1, INK)
	_rect(cx + 2, brow_y + brow_drop + maxi(0, -tilt * f), 2, 1, INK)
	_rect(cx - 4, top + 5, 2, 2, INK)
	_rect(cx + 2, top + 5, 2, 2, INK)
	var glint := 0 if f > 0 else 1
	_rect(cx - 4 + glint, top + 5, 1, 1, BALL_WHITE)
	_rect(cx + 2 + glint, top + 5, 1, 1, BALL_WHITE)
	# Mouth states: 1-2 cells only at Battery LOD.
	match String(e.mouth):
		"grin":
			_rect(cx - 1, top + 7, 2, 1, INK)
			_rect(cx - 1, top + 8, 2, 1, BALL_WHITE)
		"open_grin":
			_rect(cx - 1, top + 7, 2, 2, INK)
			_rect(cx - 1, top + 7, 2, 1, BALL_WHITE)
		"open":
			_rect(cx, top + 7, 1, 2, INK)
		"dot":
			_rect(cx, top + 7, 1, 1, INK)
		"frown":
			_rect(cx - 1, top + 8, 2, 1, INK)
		"wavy":
			_rect(cx - 1, top + 7, 1, 1, INK)
			_rect(cx, top + 8, 1, 1, INK)
		_:
			_rect(cx - 1, top + 7, 2, 1, INK)
	if String(pose.get("expression", "")) == "gassed":
		# The single sanctioned sea_glint sweat cell at the temple (§8.6).
		_rect(cx + 4 * f, top + 4, 1, 1, SWEAT_GLINT)
	if variant in ["catcher", "umpire"]:
		_mask_grill(cx, top + 3, 5, 1)


func _draw_marquee_head(cx: int, top: int, p: Dictionary, pose: Dictionary, variant: String, f: int) -> void:
	var e := _expression(pose)
	# Stepped round-cornered 16-row head with a full ink contour.
	_rect(cx - 6, top, 13, 1, INK)
	_rect(cx - 8, top + 1, 17, 1, INK)
	_rect(cx - 9, top + 2, 19, 13, INK)
	_rect(cx - 8, top + 15, 17, 1, INK)
	# Face fill.
	_rect(cx - 7, top + 5, 15, 10, p.skin)
	_rect(cx - 6, top + 15, 13, 1, p.skin_shadow)
	_rect(cx - 8, top + 6, 1, 6, p.skin_shadow)
	_rect(cx + 7, top + 6, 1, 6, p.skin_shadow)
	# Hair mass framing the face; ramp shade at the nape.
	_rect(cx - 8, top + 4, 3, 5, p.hair)
	_rect(cx + 6, top + 4, 3, 5, p.hair)
	_rect(cx - 8, top + 8, 2, 2, p.hair_shadow)
	_rect(cx + 7, top + 8, 2, 2, p.hair_shadow)
	_headwear(cx, top, p, variant, f, 2, bool(pose.get("brim_pop", false)))
	# Cap-brim shadow band across the brow line (§8.2).
	_rect(cx - 6, top + 5, 13, 1, p.skin_shadow)
	# Brows: the primary emotion channel, 2 cells each.
	var brow_y := top + 7
	var inner := 0
	match String(e.brow):
		"up":
			brow_y -= 1
		"inner_down":
			inner = 1
		"inner_up":
			inner = -1
		"low":
			brow_y += 1
	_rect(cx - 5, brow_y + maxi(0, inner * f), 2, 1, INK)
	_rect(cx + 3, brow_y + maxi(0, -inner * f), 2, 1, INK)
	# 2x3 ink eyes with one 1-cell ball-white catch-light each.
	_rect(cx - 5, top + 8, 2, 3, INK)
	_rect(cx + 3, top + 8, 2, 3, INK)
	var glint := 0 if f > 0 else 1
	_rect(cx - 5 + glint, top + 8, 1, 1, BALL_WHITE)
	_rect(cx + 3 + glint, top + 8, 1, 1, BALL_WHITE)
	# Cheek blush / dirt smudge, 1 cell per cheek.
	_rect(cx - 6, top + 12, 1, 1, CLAY_SMUDGE)
	_rect(cx + 5, top + 12, 1, 1, CLAY_SMUDGE)
	# Mouth states: 1-3 cells wide.
	match String(e.mouth):
		"grin":
			_rect(cx - 2, top + 12, 4, 2, INK)
			_rect(cx - 1, top + 12, 2, 1, BALL_WHITE)
		"open_grin":
			_rect(cx - 2, top + 11, 4, 3, INK)
			_rect(cx - 1, top + 11, 2, 1, BALL_WHITE)
		"open":
			_rect(cx - 1, top + 12, 2, 2, INK)
		"dot":
			_rect(cx, top + 12, 1, 1, INK)
		"frown":
			_rect(cx - 1, top + 13, 3, 1, INK)
		"wavy":
			_rect(cx - 2, top + 12, 2, 1, INK)
			_rect(cx, top + 13, 2, 1, INK)
		_:
			_rect(cx - 1, top + 12, 3, 1, INK)
	if String(pose.get("expression", "")) == "gassed":
		# The single sanctioned sea_glint sweat cell at the temple (§8.6).
		_rect(cx + 6 * f, top + 9, 1, 1, SWEAT_GLINT)
	if variant in ["catcher", "umpire"]:
		_mask_grill(cx, top + 6, 8, 2)


func _headwear(cx: int, top: int, p: Dictionary, variant: String, f: int, s: int, brim_pop := false) -> void:
	var trim: Color = _umpire_cloth if variant == "umpire" else p.trim
	var trim_shadow: Color = INK if variant == "umpire" else p.trim_shadow
	var crown_h := 3 * s
	var w := 11 if s == 1 else 15
	var half := w / 2
	if variant == "batter":
		# Helmet: team trim + ink, ear-flap bump on the trailing side.
		_rect(cx - half + s, top, w - 2 * s, 1, trim)
		_rect(cx - half, top + 1, w, crown_h - 1, trim)
		_rect(cx - half, top + crown_h - 1, w, 1, trim_shadow)
		var flap_x := cx - half - s if f > 0 else cx + half - s + 1
		_rect(flap_x - 1, top + crown_h - 1, 2 * s + 2, 3 * s + 1, INK)
		_rect(flap_x, top + crown_h, 2 * s, 3 * s - 1, trim)
		_rect(cx + (half - s) * f, top + crown_h - s, (3 * s + 1) * f, s, INK)
		if s == 2:
			_rect(cx - 1, top + 1, 2, 1, LANTERN_GOLD)
	else:
		var tilt := s if variant == "pitcher" else 0
		_rect(cx - half + s, top, w - 2 * s, 1, trim)
		_rect(cx - half, top + 1, w, crown_h - 1, trim)
		_rect(cx - half, top + crown_h - 1, w, 1, trim_shadow)
		_rect(cx - s, top + 1, 2 * s, 1, p.accent)
		# Brim: ink underside with a lit trim top edge, forward-tilted for
		# pitchers; runners carry the lantern-gold cap tick (§8.3). The 2-tick
		# release brim-pop (§8.5) snaps the whole brim one cell up and flicks
		# the tip a cell higher — whole cells only, never a rotation.
		var pop := s if brim_pop else 0
		var brim_len := (4 + (1 if variant == "pitcher" else 0)) * s
		_rect(cx + (half - s) * f, top + crown_h - 1 + tilt - pop, (brim_len + s) * f, s, INK)
		_rect(cx + (half - s) * f, top + crown_h - 2 + tilt - pop, brim_len * f, 1, trim)
		if pop > 0:
			_rect(cx + (half - s + brim_len) * f, top + crown_h - 1 + tilt - 2 * pop, s * f, s, trim)
	if variant == "runner":
		_rect(cx - s, top, 2 * s, 1, LANTERN_GOLD)


func _mask_grill(cx: int, top: int, rows: int, s: int) -> void:
	var half := 4 * s
	_rect(cx - half - s, top, 1, rows, _gear_shell)
	_rect(cx + half + s - 1, top, 1, rows, _gear_shell)
	var y := top + 1
	while y < top + rows:
		_rect(cx - half, y, 2 * half, 1, GEAR_BAR)
		y += 2
	_rect(cx, top, 1, rows, GEAR_BAR)


# ---------------------------------------------------------------------------
# Diamond LOD: 7x11 silhouette-first figures. Ink appears under the cap and at
# the feet only (§5.2); a single eye mark at most; expression is posture.
# ---------------------------------------------------------------------------

func _draw_diamond(p: Dictionary, pose: Dictionary) -> void:
	var action := String(pose.get("action", "idle"))
	var frame := int(pose.get("frame", 0))
	var f := int(pose.get("facing", 1))
	var variant := String(pose.get("role_variant", "fielder"))
	var stance := _compute_stance(pose, variant)
	var cloth: Color = _umpire_cloth if variant == "umpire" else p.cloth
	var trim: Color = p.trim

	_ground_shade(3)
	if bool(pose.get("highlighted", false)):
		_focus_ring(4)
	if action == "slide":
		_rect(0, -3, 7 * f, 3, cloth)
		_rect(4 * f, -2, 4 * f, 2, p.pants)
		_rect(-3 * f, -5, 4 * f, 3, p.skin)
		_rect(-3 * f, -6, 4 * f, 1, trim)
		_rect(5 * f, 0, 3 * f, 1, INK)
		if variant != "umpire" and variant != "batter":
			_rect(-5 * f, -3, 2 * f, 2, _leather_main)
		return

	var crouch := clampi(int(stance.crouch) / 2 + (1 if int(stance.crouch) % 2 != 0 else 0), 0, 3)
	var lean := clampi(int(stance.lean), -2, 2) * f
	var bob := int(stance.bob)
	var spread := clampi(int(stance.spread), 0, 2)
	var head_top := -11 + crouch + bob
	var torso_top := head_top + 5

	# Legs and ink feet.
	var l_leg := -3 - spread + (0 if not stance.legs_run else (-1 if frame % 2 == 0 else 1) * f)
	var r_leg := 1 + spread + (0 if not stance.legs_run else (1 if frame % 2 == 0 else -1) * f)
	if stance.stride:
		l_leg = -4 * f
		r_leg = 2 * f
	_rect(l_leg, -2 + bob, 2, 2 - bob, p.pants)
	_rect(r_leg, -2 + bob, 2, 2 - bob, p.pants)
	_rect(l_leg, -2 + bob, 2, 1, trim if variant != "umpire" else _umpire_cloth)
	_rect(r_leg, -2 + bob, 2, 1, trim if variant != "umpire" else _umpire_cloth)
	_rect(l_leg, 0, 2, 1, INK)
	_rect(r_leg, 0, 2, 1, INK)

	# Torso taper with the trim chest band carrying team identity.
	var chest_w := 7 if variant in ["catcher", "umpire"] else 5
	_rect(lean - chest_w / 2, torso_top, chest_w, 2, cloth)
	_rect(lean - 2, torso_top + 2, 5, 2, cloth)
	if variant == "umpire":
		_rect(lean - 2, torso_top, 5, 1, GEAR_BAR)
	elif variant == "catcher":
		_rect(lean - 2, torso_top, 5, 2, _gear_shell)
		_rect(lean - 2, torso_top + 1, 5, 1, GEAR_BAR)
	else:
		_rect(lean - chest_w / 2, torso_top + 1, chest_w, 1, trim)

	# Arms: 1-cell ribbons to the pose hands.
	var l_hand := Vector2i(clampi(int(stance.l_hand.x) / 2, -5, 5) * f + lean, mini(-2, int(stance.l_hand.y) / 2 + crouch) + bob)
	var r_hand := Vector2i(clampi(int(stance.r_hand.x) / 2, -5, 5) * f + lean, mini(-2, int(stance.r_hand.y) / 2 + crouch) + bob)
	_rect(l_hand.x, l_hand.y, 1, torso_top + 1 - l_hand.y, p.skin)
	_rect(r_hand.x, r_hand.y, 1, torso_top + 1 - r_hand.y, p.skin)

	# Head: cap, ink under-brim line, two face rows, single eye mark.
	_rect(lean - 2, head_top, 5, 1, trim)
	_rect(lean - 3, head_top + 1, 7, 1, trim)
	if variant == "batter":
		var flap_x := lean - 3 if f > 0 else lean
		_rect(flap_x, head_top + 2, 4, 1, trim)
	_rect(lean - 3, head_top + 2, 7, 1, INK)
	_rect(lean - 2, head_top + 3, 5, 2, p.skin)
	_rect(lean - 2, head_top + 4, 5, 1, p.skin_shadow)
	_rect(lean + f, head_top + 3, 1, 1, INK)
	if variant == "runner":
		_rect(lean - 1, head_top, 2, 1, LANTERN_GOLD)
	if variant in ["catcher", "umpire"]:
		_rect(lean - 2, head_top + 3, 1, 2, GEAR_BAR)
		_rect(lean + 2, head_top + 3, 1, 2, GEAR_BAR)

	# Equipment masses break the silhouette.
	if variant == "batter":
		var tip := Vector2i(r_hand.x + 4 * f, r_hand.y - 4)
		if action == "swing" and String(pose.get("pose_key", "")) == "action":
			tip = Vector2i(r_hand.x + 5 * f, r_hand.y)
		elif action == "swing" and String(pose.get("pose_key", "")) == "settle":
			tip = Vector2i(r_hand.x - 4 * f, r_hand.y - 4)
		_limb(r_hand, tip, BAT_WOOD, 1, false)
		_rect(tip.x, tip.y, 1, 1, LANTERN_GOLD)
	elif variant == "catcher":
		var glove_hand := l_hand if String(host.get_throwing_hand()) != "left" else r_hand
		_rect(glove_hand.x - 1, glove_hand.y - 1, 2, 2, _leather_main)
		_rect(glove_hand.x - 1, glove_hand.y - 1, 1, 1, _leather_lit)
		_rect(glove_hand.x, glove_hand.y - 2, 1, 1, _leather_main)
	elif variant != "umpire":
		var glove_hand := l_hand if String(host.get_throwing_hand()) != "left" else r_hand
		var boost := 1 if stance.mitt_boost else 0
		_rect(glove_hand.x - 1, glove_hand.y - 1 - boost, 2 + boost, 2 + boost, _leather_main)
		_rect(glove_hand.x, glove_hand.y - boost, 1, 1, _leather_lit)


# ---------------------------------------------------------------------------
# Equipment and shared primitives.
# ---------------------------------------------------------------------------

func _draw_bat(hand: Vector2i, action: String, pose_key: String, f: int, s: int, smear := false) -> void:
	# The bat diagonal always breaks the silhouette, with one lantern-gold
	# highlight cell near the barrel (§8.3).
	var tip := hand + Vector2i(4 * s * f, -7 * s)
	if action == "swing":
		if pose_key == "anticipation":
			tip = hand + Vector2i(-3 * s * f, -8 * s)
		elif pose_key == "action":
			# Contact stretches bat + arms into one long diagonal; the smear
			# tick reaches two further cells so the full extension reads (§8.5).
			tip = hand + Vector2i((9 + (2 if smear else 0)) * s * f, s)
		else:
			tip = hand + Vector2i(-6 * s * f, -6 * s)
	if smear and action == "swing":
		# The 1-frame authored 3-cluster arc smear: opaque wood-ramp ghosts of
		# the barrel along the swept load-to-contact arc (§8.5) — never a blur,
		# drawn under the bat so the live diagonal stays the strongest read.
		_rect(hand.x + 8 * s * f, hand.y - 4 * s, 2 * s * f, s, BAT_WOOD)
		_rect(hand.x + 5 * s * f, hand.y - 8 * s, 2 * s * f, s, BAT_GRAIN)
		_rect(hand.x + s * f, hand.y - 10 * s, s * f, 2 * s, BAT_GRAIN)
	_limb(hand, tip, BAT_WOOD, s, true)
	var grain := hand + (tip - hand) / 2
	_rect(grain.x, grain.y, s, 1, BAT_GRAIN)
	var sheen := hand + (tip - hand) * 3 / 4
	_rect(sheen.x, sheen.y, 1, 1, LANTERN_GOLD)


func _hand(at: Vector2i, skin: Color, s: int) -> void:
	var size := 2 * s
	_rect(at.x - size / 2 - 1, at.y - size / 2 - 1, size + 2, size + 2, INK)
	_rect(at.x - size / 2, at.y - size / 2, size, size, skin)


func _mitt(at: Vector2i, size: int) -> void:
	_rect(at.x - size / 2 - 1, at.y - size / 2 - 1, size + 2, size + 2, INK)
	_rect(at.x - size / 2, at.y - size / 2, size, size, _leather_main)
	_rect(at.x - size / 2 + 1, at.y - size / 2 + 1, size / 2, size / 2, _leather_lit)


func _shoe(center_x: int, f: int, s: int) -> void:
	var w := 3 * s
	_rect(center_x - w / 2 - (s if f < 0 else 0), -2 * s, w + s, 2 * s, INK)
	_rect(center_x - w / 2 + (0 if f < 0 else s), -s, 1, 1, STEEL_TEXT)


func _team_logo(x: int, y: int, p: Dictionary) -> void:
	# 2x2-cell abstract mark, never letters below Marquee LOD (§8.4): the
	# fox-head notch for the red family, the pier-light dot for the teal.
	match String(p.get("trim_family", "neutral")):
		"fox":
			_rect(x, y, 2, 2, STITCH_RED)
			_rect(x + 1, y, 1, 1, INK)
		"pier":
			_rect(x, y, 2, 2, SIGNAL_TEAL)
			_rect(x, y + 1, 1, 1, BALL_WHITE)
		_:
			_rect(x, y, 2, 2, p.trim)


## Night lantern grade: raise every lit step warm and sink every shadow step
## cool so faces, cap/equipment cues, and uniform bands keep >= 2 rungs of
## internal separation inside the compressed night value ladder (§4.1). Cloth
## and pants mains stay untouched — home chalk whites and road steel grays are
## the figure's guaranteed V5 content at night, including the controlled
## player's lantern-against-sea contract.
func _night_graded(p: Dictionary) -> Dictionary:
	var graded := p.duplicate()
	graded.skin = _night_lift(p.skin, NIGHT_SKIN_LIFT)
	graded.skin_shadow = _night_sink(p.skin_shadow)
	graded.hair = _night_lift(p.hair, NIGHT_HAIR_LIFT)
	graded.hair_shadow = _night_sink(p.hair_shadow)
	graded.trim = _night_lift(p.trim, NIGHT_TRIM_LIFT)
	graded.trim_shadow = _night_sink(p.trim_shadow)
	graded.accent = _night_lift(p.accent, NIGHT_TRIM_LIFT)
	graded.cloth_shadow = _night_sink(p.cloth_shadow)
	graded.pants_shadow = _night_sink(p.pants_shadow)
	return graded


func _night_lift(color: Color, amount: float) -> Color:
	var lifted := color.lerp(NIGHT_LIFT_ANCHOR, amount)
	lifted.a = 1.0
	return lifted


func _night_sink(color: Color) -> Color:
	var sunk := color.lerp(NIGHT_SHADE_ANCHOR, NIGHT_SHADOW_SINK)
	sunk.a = 1.0
	return sunk


func _world_mood() -> String:
	if not is_inside_tree():
		return "day"
	for world in get_tree().get_nodes_in_group("pixiball_pixel_world"):
		var direct: Variant = world.get("mood")
		if direct is String:
			return PixiballPixelArtStyle.normalized_mood(direct)
		var facade: Variant = world.get("_mood")
		if facade is String:
			return PixiballPixelArtStyle.normalized_mood(facade)
	return "day"


func _ground_shade(half_width: int) -> void:
	_rect(-half_width, 0, half_width * 2, 1, INK)


func _focus_ring(radius: int) -> void:
	# Stepped lantern-gold ring at the feet, 1 cell thick (§6.4).
	var half := maxi(2, radius / 2)
	_rect(-half, -2, half * 2, 1, LANTERN_GOLD)
	_rect(-half, 2, half * 2, 1, LANTERN_GOLD)
	_rect(-radius, 0, 2, 1, LANTERN_GOLD)
	_rect(radius - 2, 0, 2, 1, LANTERN_GOLD)
	_rect(-radius + 1, -1, 1, 1, LANTERN_GOLD)
	_rect(radius - 2, -1, 1, 1, LANTERN_GOLD)
	_rect(-radius + 1, 1, 1, 1, LANTERN_GOLD)
	_rect(radius - 2, 1, 1, 1, LANTERN_GOLD)


func _limb(a: Vector2i, b: Vector2i, fill: Color, thickness: int, contour: bool) -> void:
	if contour:
		_limb_pass(a, b, INK, thickness + 2)
	_limb_pass(a, b, fill, thickness)


func _limb_pass(a: Vector2i, b: Vector2i, color: Color, thickness: int) -> void:
	# Whole-cell stair walk: no engine line rasterizing, no antialiasing.
	var steps := maxi(1, maxi(absi(b.x - a.x), absi(b.y - a.y)))
	var half := thickness / 2
	for i in range(steps + 1):
		var x := a.x + roundi(float(b.x - a.x) * float(i) / float(steps))
		var y := a.y + roundi(float(b.y - a.y) * float(i) / float(steps))
		_rect(x - half, y - half, thickness, thickness, color)


func _rect(x: int, y: int, width: int, height: int, color: Color) -> void:
	var px := x
	var w := width
	if width < 0:
		px = x + width
		w = -width
	if height < 0:
		y += height
		height = -height
	draw_rect(Rect2(px, y, maxi(1, w), maxi(1, height)), color, true)
