extends SceneTree

## Compatibility audit for the authorized UE full-sim fixtures.
##
## The Godot semantic sim deliberately delegates live-play classification and
## has no presentation tick state, so these fixtures are not asserted as Godot
## goldens. This executable audit validates their frozen schema, runs a pinned
## deterministic Godot policy for every canonical seed, and records exactly
## which comparable coarse fields diverge. It must never print or imply full
## UE GoldenReplay/TraceDigest parity.

const SimScript = preload("res://gameplay/pixiball_sim.gd")
const CatalogScript = preload("res://core/content/content_catalog.gd")
const PitchModelScript = preload("res://core/model/pitch_model.gd")
const PixRngScript = preload("res://core/model/pix_rng.gd")

const SIM_GOLDEN_PATH := "res://content/data/golden/sim_golden.json"
const TRACE_GOLDEN_PATH := "res://content/data/golden/trace_golden.json"
const CANONICAL_SEEDS := [12648430, 1234567, 42, 90210, 3735928559]
const COMPARABLE_FIELDS := [
	"awayRuns", "homeRuns", "awayHits", "homeHits",
	"awayK", "homeK", "awayWalks", "homeWalks",
	"awayBattersFaced", "homeBattersFaced", "innings", "pitches",
]

const COARSE_UNAVAILABLE_ITEMS := [
	"12648430:ticks", "1234567:ticks", "42:ticks", "90210:ticks", "3735928559:ticks",
]
const TRACE_UNAVAILABLE_ITEMS := [
	"ticks", "finalHash", "checkpoint:10000", "checkpoint:20000", "checkpoint:30000", "checkpoint:40000",
]


func _init() -> void:
	var passed := _run()
	quit(0 if passed else 1)


func _run() -> bool:
	var sim_fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(SIM_GOLDEN_PATH))
	var trace_fixture: Variant = JSON.parse_string(FileAccess.get_file_as_string(TRACE_GOLDEN_PATH))
	assert(sim_fixture is Dictionary and trace_fixture is Dictionary)
	var sim_root: Dictionary = sim_fixture
	var trace_root: Dictionary = trace_fixture
	_validate_sim_fixture(sim_root)
	_validate_trace_fixture(trace_root, sim_root)

	var catalog = CatalogScript.new()
	assert(catalog.load_all())
	var model = PitchModelScript.new()
	assert(model.load_from_directory())
	var games: Array = sim_root.games
	var total_matches := 0
	var total_mismatches := 0
	var observed_mismatches := {}
	var actual_digests := {}
	var balance_totals := {
		"runs": 0, "hits": 0, "strikeouts": 0, "walks": 0,
		"batters_faced": 0, "pitches": 0,
	}
	for index in games.size():
		var expected: Dictionary = games[index]
		var seed := int(expected.seed)
		var actual := _run_godot_semantic_game(seed, catalog, model)
		var replay := _run_godot_semantic_game(seed, catalog, model)
		assert(bool(actual.completed) and actual == replay)
		_assert_plausible_game(actual)
		_accumulate_balance(balance_totals, actual)
		actual_digests[str(seed)] = actual.duplicate(true)
		var mismatches: Array[String] = []
		for field in COMPARABLE_FIELDS:
			if int(actual[field]) == int(expected[field]):
				total_matches += 1
			else:
				total_mismatches += 1
				mismatches.append(field)
		observed_mismatches[str(seed)] = mismatches
		assert(not mismatches.is_empty())

	print("GODOT_GOLDEN_DIAGNOSTIC actual=", actual_digests)
	print("GODOT_GOLDEN_DIAGNOSTIC mismatches=", observed_mismatches)
	_assert_plausible_population(balance_totals)
	assert(total_matches + total_mismatches == games.size() * COMPARABLE_FIELDS.size())
	assert(total_mismatches > 0)
	# One coarse `ticks` value per game cannot be compared: PixiballSim is a
	# semantic transition system rather than GameSim's paced 60 Hz state machine.
	var unavailable_coarse := COARSE_UNAVAILABLE_ITEMS.size()
	# Trace ticks, final hash, and four checkpoint hashes require UE per-tick
	# PlaySim positions/events and are therefore all explicitly unavailable.
	var unavailable_trace := TRACE_UNAVAILABLE_ITEMS.size()
	assert(unavailable_coarse == 5 and unavailable_trace == 6)
	assert(TRACE_UNAVAILABLE_ITEMS.size() == 2 + (trace_root.checkpoints as Array).size())
	print("PIXIBALL_UE_GOLDEN_COMPAT schema=valid balance=plausible coarse_matches=%d coarse_mismatches=%d coarse_unavailable_ticks=%d trace_matches=0 trace_unavailable=%d parity=false" % [
		total_matches,
		total_mismatches,
		unavailable_coarse,
		unavailable_trace,
	])
	return true


func _validate_sim_fixture(root: Dictionary) -> void:
	assert(String(root.get("note", "")).contains("pixiball.Sim.GoldenReplay"))
	var games: Array = root.get("games", [])
	assert(games.size() == CANONICAL_SEEDS.size())
	var required := ["seed"] + COMPARABLE_FIELDS + ["ticks"]
	for index in games.size():
		var game: Dictionary = games[index]
		assert(int(game.get("seed", -1)) == int(CANONICAL_SEEDS[index]))
		for field in required:
			assert(game.has(field))
			var value := float(game[field])
			assert(is_finite(value) and value >= 0.0 and value == floor(value))


func _validate_trace_fixture(root: Dictionary, sim_root: Dictionary) -> void:
	assert(String(root.get("note", "")).contains("pixiball.Sim.TraceDigest"))
	assert(int(root.get("seed", -1)) == int(CANONICAL_SEEDS[0]))
	assert(int(root.get("ticks", -1)) == int((sim_root.games as Array)[0].ticks))
	assert(_is_hex8(String(root.get("finalHash", ""))))
	var checkpoints: Array = root.get("checkpoints", [])
	assert(checkpoints.size() == int(root.ticks) / 10000)
	for index in checkpoints.size():
		var checkpoint: Dictionary = checkpoints[index]
		assert(int(checkpoint.tick) == (index + 1) * 10000)
		assert(_is_hex8(String(checkpoint.hash)))


func _run_godot_semantic_game(seed: int, catalog, model) -> Dictionary:
	var sim = SimScript.new(seed, 3, 0.5)
	assert(sim.configure_replica(catalog.pitcher_at(0), catalog.pitcher_at(1), model).ok)
	var strikeouts := {"away": 0, "home": 0}
	var walks := {"away": 0, "home": 0}
	var transitions := 0
	while not sim.is_game_over() and transitions < 5000:
		var state: Dictionary = sim.snapshot()
		if state.phase == "pitch":
			var pitch: Dictionary
			var result: Dictionary
			if sim.is_user_pitching():
				var pitches: Array = sim.user_pitcher().get("pitches", [])
				var code := String((pitches[int(state.pitch_serial) % pitches.size()] as Dictionary).get("code", "FF")).to_lower()
				pitch = sim.create_user_pitch(code, _neutral_pitch_aim(state))
				result = sim.resolve_cpu_batter(pitch)
			else:
				pitch = sim.create_cpu_pitch()
				result = sim.resolve_user_batter(pitch, _neutral_swing(seed, state, pitch))
			assert(bool(pitch.get("ok", false)) and bool(result.get("ok", false)))
			var batting_side := String(state.batting_side)
			var committed: Dictionary = sim.commit_plate_result(result)
			if String(result.get("outcome", "")) == "in_play":
				var semantic_result: Dictionary = sim.resolve_semantic_live_play(0.55)
				assert(bool(semantic_result.get("ok", false)))
				committed = sim.commit_live_play(semantic_result)
			var booked: Dictionary = committed.get("last_result", {})
			if String(booked.get("outcome", "")) == "strikeout":
				strikeouts[batting_side] = int(strikeouts[batting_side]) + 1
			elif String(booked.get("outcome", "")) == "walk":
				walks[batting_side] = int(walks[batting_side]) + 1
		elif state.phase == "result":
			sim.advance_after_result()
		else:
			assert(false, "semantic harness reached unsupported phase %s" % String(state.phase))
		transitions += 1
	var final_state: Dictionary = sim.snapshot()
	return {
		"completed": sim.is_game_over(),
		"awayRuns": int(final_state.score.away),
		"homeRuns": int(final_state.score.home),
		"awayHits": int(final_state.hits.away),
		"homeHits": int(final_state.hits.home),
		"awayK": int(strikeouts.away),
		"homeK": int(strikeouts.home),
		"awayWalks": int(walks.away),
		"homeWalks": int(walks.home),
		"awayBattersFaced": int(final_state.batters_faced.away),
		"homeBattersFaced": int(final_state.batters_faced.home),
		"innings": int(final_state.inning),
		"pitches": int(final_state.pitch_serial),
		"semanticTransitions": transitions,
	}


func _neutral_pitch_aim(state: Dictionary) -> Vector2:
	# A reproducible strike/edge/chase mix. Three-ball counts tighten toward the
	# zone, but do not become an impossible command oracle, so walks can occur.
	if int(state.count.balls) == 3:
		return Vector2(0.38 if int(state.pitch_serial) % 2 == 0 else -0.38, 2.45)
	var locations := [
		Vector2(0.0, 2.50),
		Vector2(-0.56, 1.82),
		Vector2(0.58, 3.16),
		Vector2(-0.88, 2.12),
		Vector2(0.90, 2.92),
		Vector2(0.0, 1.34),
		Vector2(-0.42, 3.38),
		Vector2(0.45, 1.62),
	]
	return locations[int(state.pitch_serial) % locations.size()]


func _neutral_swing(seed: int, state: Dictionary, pitch: Dictionary) -> Dictionary:
	# This is a neutral controller policy, not an outcome override: it still
	# enters PixiballSim's normal swing/take, model feedback, and count flow.
	# Domain 12 is appended after the original Play stream and is local to this
	# compatibility driver, keeping all production streams untouched.
	var rng = PixRngScript.new(PixRngScript.stream_seed(seed, int(state.epoch), 12, int(pitch.serial)))
	var in_zone := bool(pitch.get("in_zone", false))
	var swing_probability := 0.74 if in_zone else 0.22
	if int(state.count.strikes) == 2:
		swing_probability += 0.14
	if int(state.count.balls) == 3 and not in_zone:
		swing_probability -= 0.08
	var did_swing := rng.next() < clampf(swing_probability, 0.05, 0.94)
	if not did_swing:
		return {"did_swing": false}
	var actual: Array = pitch.get("actual", [0.0, 2.5])
	return {
		"did_swing": true,
		"reticle": [
			float(actual[0]) + rng.gauss(0.0, 0.24),
			float(actual[1]) + rng.gauss(0.0, 0.24),
		],
		"timing_error_sec": rng.gauss(0.0, 0.052),
	}


func _assert_plausible_game(game: Dictionary) -> void:
	var innings := int(game.innings)
	assert(innings >= 3 and innings <= 7)
	assert(int(game.awayRuns) >= 0 and int(game.awayRuns) <= innings * 3)
	assert(int(game.homeRuns) >= 0 and int(game.homeRuns) <= innings * 3)
	assert(int(game.awayRuns) + int(game.homeRuns) <= innings * 5)
	assert(int(game.awayHits) >= 0 and int(game.awayHits) <= innings * 5)
	assert(int(game.homeHits) >= 0 and int(game.homeHits) <= innings * 5)
	assert(int(game.awayBattersFaced) >= 9 and int(game.awayBattersFaced) <= innings * 9)
	# A leading home club can skip the final bottom half.
	assert(int(game.homeBattersFaced) >= 6 and int(game.homeBattersFaced) <= innings * 9)
	assert(int(game.awayK) + int(game.awayWalks) <= int(game.awayBattersFaced))
	assert(int(game.homeK) + int(game.homeWalks) <= int(game.homeBattersFaced))
	var total_batters := int(game.awayBattersFaced) + int(game.homeBattersFaced)
	assert(int(game.pitches) >= total_batters and int(game.pitches) <= total_batters * 8)


func _accumulate_balance(totals: Dictionary, game: Dictionary) -> void:
	totals.runs = int(totals.runs) + int(game.awayRuns) + int(game.homeRuns)
	totals.hits = int(totals.hits) + int(game.awayHits) + int(game.homeHits)
	totals.strikeouts = int(totals.strikeouts) + int(game.awayK) + int(game.homeK)
	totals.walks = int(totals.walks) + int(game.awayWalks) + int(game.homeWalks)
	totals.batters_faced = int(totals.batters_faced) + int(game.awayBattersFaced) + int(game.homeBattersFaced)
	totals.pitches = int(totals.pitches) + int(game.pitches)


func _assert_plausible_population(totals: Dictionary) -> void:
	var batters := float(totals.batters_faced)
	assert(batters > 0.0)
	var hit_rate := float(totals.hits) / batters
	var strikeout_rate := float(totals.strikeouts) / batters
	var walk_rate := float(totals.walks) / batters
	var pitches_per_batter := float(totals.pitches) / batters
	assert(hit_rate >= 0.10 and hit_rate <= 0.45)
	assert(strikeout_rate >= 0.08 and strikeout_rate <= 0.45)
	assert(walk_rate >= 0.01 and walk_rate <= 0.20)
	assert(pitches_per_batter >= 2.0 and pitches_per_batter <= 6.5)
	print("GODOT_BALANCE_DIAGNOSTIC runs=%d hits=%d strikeouts=%d walks=%d batters=%d hit_rate=%.3f k_rate=%.3f bb_rate=%.3f pitches_per_batter=%.3f" % [
		int(totals.runs), int(totals.hits), int(totals.strikeouts), int(totals.walks), int(totals.batters_faced),
		hit_rate, strikeout_rate, walk_rate, pitches_per_batter,
	])


func _is_hex8(value: String) -> bool:
	if value.length() != 8:
		return false
	for character in value.to_upper():
		if character not in "0123456789ABCDEF":
			return false
	return true
