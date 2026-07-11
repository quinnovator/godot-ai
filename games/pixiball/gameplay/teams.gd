class_name PixiballTeams
extends RefCounted

## Team helpers faithfully ported from:
##   ../pixiball-ue/Source/PixCore/Sim/Teams.cpp


static func team_by_id(teams: Array, id_value: String) -> Dictionary:
	for team_value in teams:
		var team: Dictionary = team_value
		if String(team.get("id", "")) == id_value:
			return team.duplicate(true)
	return {}


static func bat_quality(team: Dictionary) -> float:
	return clampf((float(team.get("bat", 79)) - 79.0) / 9.0, -1.0, 1.0)


static func build_versus_rosters(all_pitchers: Array, cards: Dictionary, home: Dictionary, away: Dictionary) -> Dictionary:
	var ranked: Array[Dictionary] = []
	for pitcher_value in all_pitchers:
		ranked.append((pitcher_value as Dictionary).duplicate(true))
	ranked.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var a_card: Dictionary = cards.get(int(a.get("id", -1)), {})
		var b_card: Dictionary = cards.get(int(b.get("id", -1)), {})
		var a_ovr := int(a_card.get("ovr", 0))
		var b_ovr := int(b_card.get("ovr", 0))
		if a_ovr != b_ovr:
			return a_ovr > b_ovr
		return int(a.get("id", 0)) < int(b.get("id", 0))
	)
	var home_first := int(home.get("pit", 0)) >= int(away.get("pit", 0))
	var home_roster: Array[Dictionary] = []
	var away_roster: Array[Dictionary] = []
	for index in ranked.size():
		var home_pick := (index % 2 == 0) == home_first
		(home_roster if home_pick else away_roster).append(ranked[index])
	return {"home": home_roster, "away": away_roster, "home_first": home_first}
