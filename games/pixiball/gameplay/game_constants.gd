class_name PixiballConstants
extends RefCounted

const HOME_PLATE := Vector3(0.0, 0.08, 18.0)
const PITCHER_MOUND := Vector3(0.0, 0.08, 0.0)
const FIRST_BASE := Vector3(13.0, 0.08, 4.0)
const SECOND_BASE := Vector3(0.0, 0.08, -9.0)
const THIRD_BASE := Vector3(-13.0, 0.08, 4.0)
const BASES := [HOME_PLATE, FIRST_BASE, SECOND_BASE, THIRD_BASE]

const DEFENSIVE_POSITIONS := {
	"pitcher": PITCHER_MOUND,
	"catcher": Vector3(0.0, 0.08, 20.0),
	"first": Vector3(15.5, 0.08, 0.0),
	"second": Vector3(7.5, 0.08, -8.5),
	"short": Vector3(-7.5, 0.08, -8.5),
	"third": Vector3(-15.5, 0.08, 0.0),
	"left": Vector3(-22.0, 0.08, -30.0),
	"center": Vector3(0.0, 0.08, -39.0),
	"right": Vector3(22.0, 0.08, -30.0),
}

const HOME_TEAM := {
	"city": "NOVA CITY",
	"name": "PULSE",
	"abbr": "PUL",
	"primary": Color("44d7b6"),
	"secondary": Color("102a43"),
	"trim": Color("f8f3dc"),
}

const AWAY_TEAM := {
	"city": "EMBER FALLS",
	"name": "FOXES",
	"abbr": "FOX",
	"primary": Color("ff6b5e"),
	"secondary": Color("41152d"),
	"trim": Color("ffd166"),
}

const PITCHES := [
	{"id": "kc", "code": "KC", "name": "KNUCKLE CURVE", "speed": 79.1, "color": Color("b88cff")},
	{"id": "ff", "code": "FF", "name": "FOUR-SEAM", "speed": 92.5, "color": Color("79f28f")},
	{"id": "si", "code": "SI", "name": "SINKER", "speed": 91.5, "color": Color("5de0d2")},
	{"id": "ch", "code": "CH", "name": "CHANGEUP", "speed": 85.7, "color": Color("ffd94a")},
	{"id": "fc", "code": "FC", "name": "CUTTER", "speed": 87.5, "color": Color("ff6b6b")},
]

const PLAYER_NAMES := [
	"MARA VEGA", "JAX HOLLIS", "NIKO PARK", "ZURI COLE", "ELI QUINN",
	"TESSA REED", "OMAR VALE", "FINN ROOK", "AYA STONE", "LUCA WREN",
	"MILO KENT", "SAGE YOUNG", "ROSA FROST", "THEO BANKS", "IVA DAWN",
	"KAI RIVERS", "NOA BLAKE", "REMI CROSS",
]

static func base_position(index: int) -> Vector3:
	return BASES[clampi(index, 0, BASES.size() - 1)]
