class_name PixiballShellModel
extends RefCounted

## Deterministic, render-free menu state. The HUD only paints this state and
## Main translates returned commands into session changes.

const SCREEN_LANDING := "landing"
const SCREEN_PITCHER := "pitcher_select"
const SCREEN_TEAM := "team_select"
const SCREEN_GAME := "game"
const SCREEN_FINAL := "final"

const INNINGS := [3, 6, 9]
const DIFFICULTIES := [
	{"name": "ROOKIE", "value": 0.25},
	{"name": "PRO", "value": 0.50},
	{"name": "ALL-STAR", "value": 0.80},
]

var screen := SCREEN_LANDING
var landing_focus := 0
var pitcher_index := 0
var team_focus := 0
var player_team_index := -1
var cpu_team_index := -1
var innings_index := 0
var difficulty_index := 1
var final_focus := 0


func show_landing() -> void:
	screen = SCREEN_LANDING
	landing_focus = clampi(landing_focus, 0, 1)


func show_pitchers(index := 0) -> void:
	screen = SCREEN_PITCHER
	pitcher_index = clampi(index, 0, 9)


func show_teams() -> void:
	screen = SCREEN_TEAM
	team_focus = 0
	player_team_index = -1
	cpu_team_index = -1


func show_game() -> void:
	screen = SCREEN_GAME


func show_final() -> void:
	screen = SCREEN_FINAL
	final_focus = 0


func navigate(x: int, y: int) -> void:
	match screen:
		SCREEN_LANDING:
			if x != 0 or y != 0:
				landing_focus = 1 - landing_focus
		SCREEN_PITCHER:
			pitcher_index = posmod(pitcher_index + x + y * 5, 10)
		SCREEN_TEAM:
			_navigate_teams(x, y)
		SCREEN_FINAL:
			if x != 0 or y != 0:
				final_focus = 1 - final_focus


func confirm() -> Dictionary:
	match screen:
		SCREEN_LANDING:
			if landing_focus == 0:
				show_pitchers(pitcher_index)
				return {"command": "open_pitchers"}
			show_teams()
			return {"command": "open_teams"}
		SCREEN_PITCHER:
			return {"command": "start_endless", "pitcher_index": pitcher_index}
		SCREEN_TEAM:
			if team_focus < 8:
				if player_team_index < 0:
					player_team_index = team_focus
				elif team_focus != player_team_index:
					cpu_team_index = team_focus
				return {"command": "team_changed"}
			if team_focus == 8:
				difficulty_index = posmod(difficulty_index + 1, DIFFICULTIES.size())
				return {"command": "option_changed"}
			if team_focus == 9:
				innings_index = posmod(innings_index + 1, INNINGS.size())
				return {"command": "option_changed"}
			if can_play():
				return {
					"command": "start_versus",
					"player_team_index": player_team_index,
					"cpu_team_index": cpu_team_index,
					"innings": innings_value(),
					"difficulty": difficulty_value(),
				}
			return {"command": "disabled"}
		SCREEN_FINAL:
			return {"command": "rematch" if final_focus == 0 else "exit_to_menu"}
	return {"command": "none"}


func back() -> Dictionary:
	match screen:
		SCREEN_PITCHER, SCREEN_TEAM, SCREEN_FINAL:
			show_landing()
			return {"command": "exit_to_menu"}
	return {"command": "none"}


func cycle_option(direction: int) -> void:
	if screen != SCREEN_TEAM or direction == 0:
		return
	if team_focus == 8:
		difficulty_index = posmod(difficulty_index + direction, DIFFICULTIES.size())
	elif team_focus == 9:
		innings_index = posmod(innings_index + direction, INNINGS.size())


func can_play() -> bool:
	return player_team_index >= 0 and cpu_team_index >= 0 and player_team_index != cpu_team_index


func innings_value() -> int:
	return int(INNINGS[innings_index])


func difficulty_value() -> float:
	return float(DIFFICULTIES[difficulty_index].value)


func difficulty_name() -> String:
	return String(DIFFICULTIES[difficulty_index].name)


func snapshot() -> Dictionary:
	return {
		"screen": screen,
		"landing_focus": landing_focus,
		"pitcher_index": pitcher_index,
		"team_focus": team_focus,
		"player_team_index": player_team_index,
		"cpu_team_index": cpu_team_index,
		"innings": innings_value(),
		"difficulty": difficulty_value(),
		"difficulty_name": difficulty_name(),
		"can_play": can_play(),
		"final_focus": final_focus,
	}


func _navigate_teams(x: int, y: int) -> void:
	if team_focus < 8:
		if y > 0:
			if team_focus < 4:
				team_focus += 4
			else:
				team_focus = 8 + mini(team_focus - 4, 2)
		elif y < 0:
			team_focus = posmod(team_focus - 4, 8)
		else:
			team_focus = posmod(team_focus + x, 8)
	else:
		if y < 0:
			team_focus = 4 + mini(team_focus - 8, 3)
		elif y > 0:
			team_focus = posmod(team_focus + 1, 8)
		elif x != 0:
			team_focus = 8 + posmod(team_focus - 8 + x, 3)
