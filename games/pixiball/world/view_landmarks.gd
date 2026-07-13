class_name PixiballViewLandmarks
extends RefCounted

## Shared design-grid landmarks for every authored broadcast view.
##
## Band datums (art bible §6) and plate/mound/base anchors stay in one table so
## PixelBallparkCanvas compositions and PixiballBroadcastCamera projections
## cannot drift apart. Coordinates use the 320x180 composition vocabulary and
## are expanded 2x by presenters onto the 640x360 dense design grid.

const BAND_DATUMS := {
	"intro": {"horizon": 58, "sea_bottom": 114, "stands_top": 82, "wall_top": 114, "field_top": 118},
	# The center-field pitching camera faces home plate, so its upper band is a
	# closed club/seating interior rather than an exterior horizon.
	"pitching": {"horizon": 0, "sea_bottom": 76, "stands_top": 35, "wall_top": 76, "field_top": 82},
	"batting": {"horizon": 42, "sea_bottom": 56, "stands_top": 42, "wall_top": 54, "field_top": 60},
	"fielding": {"horizon": 36, "sea_bottom": 50, "stands_top": 48, "wall_top": 58, "field_top": 62},
	"dugout": {"horizon": 56, "sea_bottom": 63, "stands_top": 63, "wall_top": 73, "field_top": 75},
}

## Design-space diamond anchors per view. Keys match gameplay landmarks.
const DIAMOND := {
	"intro": {
		"plate": Vector2(160, 162),
		"mound": Vector2(160, 146),
		"first": Vector2(198, 143),
		"second": Vector2(160, 125),
		"third": Vector2(122, 143),
	},
	"pitching": {
		# Citizens Bank Park-inspired center-field feed: the camera is notably
		# offset, leaving the pitcher left of the plate sightline. Only plate and
		# mound are rendered in this telephoto crop; the bag anchors remain useful
		# projection contracts outside the visible stage.
		"plate": Vector2(160, 92),
		"mound": Vector2(138, 141),
		"first": Vector2(171, 130),
		"second": Vector2(127, 166),
		"third": Vector2(115, 130),
	},
	"batting": {
		"plate": Vector2(160, 154),
		"mound": Vector2(160, 76),
		"first": Vector2(191, 93),
		"second": Vector2(160, 71),
		"third": Vector2(129, 93),
	},
	"fielding": {
		"plate": Vector2(160, 155),
		"mound": Vector2(160, 119),
		"first": Vector2(201, 127),
		"second": Vector2(160, 101),
		"third": Vector2(119, 127),
		"field_center": Vector2(160, 118),
	},
	"dugout": {
		"plate": Vector2(236, 89),
		"mound": Vector2(236, 82),
		"first": Vector2(258, 83),
		"second": Vector2(236, 77),
		"third": Vector2(214, 83),
	},
}

## Authored strike-zone rectangles (design cells) for the two tight views.
const STRIKE_ZONES := {
	"batting": Rect2(137, 91, 46, 56),
	# Near-physical 17:24 proportions, lifted clear of the plate cutout. The
	# former wider frame read as a generic targeting panel in this tight view.
	"pitching": Rect2(151, 57, 22, 30),
}

## Projection lanes: near→far design anchors for depth mapping.
const PROJECTION_LANES := {
	"intro": {"near": Vector2(208, 145), "far": Vector2(116, 92)},
	"pitching": {"near": Vector2(127, 166), "far": Vector2(160, 92)},
	"batting": {"near": Vector2(160, 154), "far": Vector2(160, 76)},
	"dugout": {"origin": Vector2(160, 142)},
	"fielding": {"origin": Vector2(160, 155)},
}

const BELL_TOWER_ANCHOR := Vector2i(72, 88)


static func bands(view: String) -> Dictionary:
	return BAND_DATUMS.get(view, BAND_DATUMS.intro)


static func diamond(view: String) -> Dictionary:
	return DIAMOND.get(view, DIAMOND.intro)


static func plate(view: String) -> Vector2:
	return diamond(view).plate as Vector2


static func mound(view: String) -> Vector2:
	return diamond(view).mound as Vector2


static func bag(view: String, which: String) -> Vector2:
	return diamond(view).get(which, Vector2.ZERO) as Vector2


static func strike_zone(view: String) -> Rect2:
	return STRIKE_ZONES.get(view, Rect2()) as Rect2


static func projection_lane(view: String) -> Dictionary:
	return PROJECTION_LANES.get(view, PROJECTION_LANES.intro)
