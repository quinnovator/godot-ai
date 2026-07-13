extends RefCounted

## Pixel ballpark stage bound to PixelBallparkCanvas.

const Style = preload("res://presentation/pixel_art_style.gd")
const Landmarks = preload("res://world/view_landmarks.gd")

var host: PixelBallparkCanvas


func _init(canvas: PixelBallparkCanvas) -> void:
	host = canvas

func crowd_palette(palette: Dictionary) -> Dictionary:
	# Crowd roles on the Lantern Wharf palette (§7.5): dark clustered bodies,
	# town_far catch-light heads, and mood-rationed clay_lit warm faces.
	return {
		"body": palette.crowd_shadow,
		"body_alt": palette.ink_mid,
		"head": palette.town_far,
		"warm": palette.clay_lit,
		"shadow": palette.crowd_shadow,
		"flag_a": palette.signal_teal,
		"flag_b": palette.stitch_red,
	}

func draw_grandstand(palette: Dictionary, rect: Rect2i, seed: int, thin := 0) -> void:
	# Two-deck timber-and-brick ring section (§7.3): stand_shell structure,
	# seat rows on a 2-cell rhythm with empty-seat division ticks, a brick base
	# course, ink shadow under each deck lip, irregular aisle cuts, post rhythm
	# every 10 cells, and drape-variant bunting swags on a drifting ~24-cell
	# facade rhythm in all moods. Shallow strips (fielding, dugout window)
	# collapse to a single deck.
	var left := rect.position.x
	var right := rect.position.x + rect.size.x
	var top := rect.position.y
	var bottom := rect.position.y + rect.size.y
	var brick_rows := 3 if rect.size.y >= 14 else 2
	var brick_top := bottom - brick_rows
	var body_height := brick_top - top
	var decks := 2 if body_height >= 12 else 1
	Style.pixel_rect(host, Rect2(rect), palette.stand_shell)

	# Irregular aisle cuts every 9-13 columns, deterministic per seed.
	var aisles: Array[int] = []
	var aisle_x := left + 4 + int(Style.hash01(seed + 11) * 6.0)
	while aisle_x < right - 4:
		aisles.append(aisle_x)
		aisle_x += 9 + int(Style.hash01(seed + aisle_x * 13) * 5.0)

	var deck_height := int(body_height / float(decks))
	for deck in range(decks):
		var deck_top := top + deck * deck_height
		var deck_bottom := brick_top if deck == decks - 1 else deck_top + deck_height
		Style.pixel_rect(host, Rect2(left, deck_top, rect.size.x, 1), palette.seat_board)
		var crowd_rect := Rect2i(left, deck_top + 1, rect.size.x, deck_bottom - deck_top - 3)
		# Seat boards on the 2-cell rhythm; empty seats stay visible through
		# the 55-80% clump occupancy.
		Style.pixel_rect(host, Rect2(crowd_rect), palette.stand_shell)
		var seat_y := crowd_rect.position.y + 1
		while seat_y < crowd_rect.position.y + crowd_rect.size.y:
			Style.pixel_rect(host, Rect2(left, seat_y, rect.size.x, 1), palette.seat_board)
			# Empty-seat cadence: seat-division ticks on a drifting 4-6 cell
			# rhythm so vacant stretches read as seating, never blank rail.
			var tick_x := left + 1 + posmod(seed + seat_y * 13, 4)
			while tick_x < right - 1:
				Style.pixel_rect(host, Rect2(tick_x, seat_y, 1, 1), palette.stand_shell)
				tick_x += 4 + int(Style.hash01(seed + tick_x * 11 + seat_y) * 3.0)
			seat_y += 2
		for aisle in aisles:
			Style.pixel_rect(host, Rect2(aisle, crowd_rect.position.y, 2, crowd_rect.size.y), palette.stand_shell)
			var step_y := crowd_rect.position.y + 2
			while step_y < crowd_rect.position.y + crowd_rect.size.y:
				Style.pixel_rect(host, Rect2(aisle, step_y, 2, 1), palette.ink_mid)
				step_y += 3
		# The top deck of a two-deck stand is silhouette-only clumps (§7.5);
		# the crest row of the topmost deck may break the rail line so the
		# aggregate crowd silhouette undulates against the harbor (§5.1).
		draw_crowd_clumps(crowd_rect, seed + 900 + deck * 77, aisles, thin, decks == 2 and deck == 0, deck == 0)
		# Deck lip with its ink shadow underneath.
		Style.pixel_rect(host, Rect2(left, deck_bottom - 2, rect.size.x, 1), palette.seat_board)
		Style.pixel_rect(host, Rect2(left, deck_bottom - 1, rect.size.x, 1), palette.ink)

	# Brick base course with staggered header dashes (§7.3).
	Style.pixel_rect(host, Rect2(left, brick_top, rect.size.x, brick_rows), palette.roof_accent)
	var dash_x := left + posmod(seed, 3)
	while dash_x < right:
		Style.pixel_rect(host, Rect2(dash_x, brick_top + brick_rows - 2, mini(2, right - dash_x), 1), palette.clay_lit)
		dash_x += 4 + int(Style.hash01(seed + dash_x * 7) * 3.0)

	# Facade post rhythm every 10 cells, full height, lit at the rail.
	var post_x := left + 5
	while post_x < right:
		Style.pixel_rect(host, Rect2(post_x, top, 1, rect.size.y), palette.ink_mid)
		Style.pixel_rect(host, Rect2(post_x, top, 1, 1), palette.seat_board)
		post_x += 10

	# Bunting swags hung off the lower lip on a drifting ~24-cell rhythm with
	# alternating drape variants, so the facade never reads as one repeated
	# triangle row (§7.3).
	var bunt_index := 0
	var bunt_x := left + 10 + posmod(seed, 7)
	while bunt_x < right - 6:
		draw_bunting(Vector2(bunt_x, brick_top - 1), palette, seed + bunt_index)
		bunt_x += 24 + int(Style.hash01(seed + bunt_index * 31) * 9.0)
		bunt_index += 1

	# Reaction overlays ride each stand section (§9.5, §9.7): cap-toss arcs on
	# the biggest plays and celebration streamers off the upper deck lip.
	draw_cap_toss(palette, rect, seed)
	draw_streamers(palette, rect, seed)

func draw_cap_toss(palette: Dictionary, rect: Rect2i, seed: int) -> void:
	# §9.5: at strength >= 0.7 caps arc over the crowd. Two 2x1 caps per wide
	# section, and no view draws more than three wide sections, so the global
	# alive count stays at or under 8. Flights are whole-cell parabolas keyed
	# to the reaction clock and re-seeded per play through the serial.
	if host.reaction_timer <= 0.0 or host.reaction_strength < host.CAP_TOSS_STRENGTH or rect.size.x < 72:
		return
	var ticks := host._reaction_ticks()
	for cap in range(2):
		var salt := seed * 13 + host.reaction_serial * 101 + cap * 47
		var phase := posmod(ticks - cap * 7, 24)
		if phase >= 16:
			continue
		var start_x := rect.position.x + 8 + int(Style.hash01(salt) * float(rect.size.x - 20))
		var direction := -1 if Style.hash01(salt + 3) < 0.5 else 1
		var cx := start_x + direction * int(phase / 3.0)
		var cy := rect.position.y - 1 - int(float(phase * (16 - phase)) / 8.0)
		var cap_color: Color = palette.signal_teal if cap == 0 else palette.stitch_red
		Style.pixel_rect(host, Rect2(cx, cy, 2, 1), cap_color)

func draw_streamers(palette: Dictionary, rect: Rect2i, seed: int) -> void:
	# §9.7: team-trim 6-cell ribbons drifting from the upper deck during the
	# celebration — two per wide section, at most three wide sections per
	# view, so the alive count stays under the 8-ribbon cap. Ribbons fall one
	# cell per two ticks and sway one cell on a 3-tick cadence.
	if not host._celebrating() or rect.size.x < 72:
		return
	var ticks := host._reaction_ticks()
	for streamer in range(2):
		var salt := seed * 17 + host.reaction_serial * 59 + streamer * 71
		var x := rect.position.x + 12 + int(Style.hash01(salt) * float(rect.size.x - 24))
		var top := rect.position.y + 2 + int(ticks / 2.0)
		var ribbon: Color = palette.stitch_red if posmod(seed + streamer, 2) == 0 else palette.signal_teal
		for link in range(6):
			var cy := top + link
			if cy >= rect.position.y + rect.size.y - 2:
				break
			var cx := x + posmod(int(ticks / 3.0) + int(link / 2.0), 2)
			Style.pixel_rect(host, Rect2(cx, cy, 1, 1), ribbon)

func draw_crowd_clumps(region: Rect2i, seed: int, aisles: Array, thin: int, silhouette: bool, crest := false) -> void:
	# Clump-stamped crowd (§7.5): row-runs of 2-5 clumps with irregular gaps,
	# anchored to the seat rows, deterministic per seed. Warm faces are
	# rationed by the host.mood table; silhouette rows drop all accents. On the
	# crest row of the topmost deck, clumps jitter 0-2 cells upward so heads
	# and flags overhang the rail and the aggregate silhouette undulates
	# instead of running level (§5.1).
	if region.size.y < 3 or region.size.x < 4:
		return
	var palette := Style.palette(host.mood)
	var colors := crowd_palette(palette)
	var warm_ratio := int(host.CROWD_WARM_RATIO.get(host.mood, 5))
	var warm_salt := posmod(seed, warm_ratio)
	var left := region.position.x
	var right := region.position.x + region.size.x
	var fronts := host._wave_front_count()
	var row_count := int(region.size.y / 3.0)
	var start_y := region.position.y + region.size.y - row_count * 3
	var clump_serial := 0
	for row in range(row_count):
		var row_y := start_y + row * 3
		var x := left + posmod(seed + row_y * 31, 3)
		while x + 4 <= right:
			var run := 2 + int(Style.hash01(seed + x * 17 + row_y * 101) * 4.0)
			for index in range(run):
				if x + 4 > right:
					break
				if not blocked_by_aisle(x, aisles) and not thinned(x, left, right, thin, seed + x * 29 + row_y * 7):
					var stamp_index := posmod(int(Style.hash01(seed + x * 43 + row_y * 13) * 8.0), host.CROWD_CLUMP_STAMPS.size())
					var warm := not silhouette and posmod(clump_serial + warm_salt, warm_ratio) == 0
					var lift := 0
					if crest and row == 0:
						var roll := Style.hash01(seed + x * 59 + 7)
						lift = 2 if roll < 0.18 else (1 if roll < 0.55 else 0)
					var raised := host._wave_raised(x, left, region.size.x, fronts)
					draw_crowd_clump(Vector2i(x, row_y - lift), stamp_index, colors, warm, silhouette, raised, seed + x * 3 + row_y)
					clump_serial += 1
				x += 4
			x += 3 + int(Style.hash01(seed + x * 23 + row_y * 47) * 5.0)
	# Night phone lights (§9.5): sparse lantern-gold cells held up over the lit
	# decks while a reaction runs. Three per deck region; silhouette decks stay
	# dark, which keeps every view at or under the 12-cell cap.
	if host.mood == "night" and host.reaction_timer > 0.0 and not silhouette:
		for phone in range(3):
			var salt := seed + 5077 + phone * 97
			var px := left + 1 + int(Style.hash01(salt) * float(maxi(1, region.size.x - 3)))
			var py := region.position.y + int(Style.hash01(salt + 1) * float(maxi(1, region.size.y - 1)))
			Style.pixel_rect(host, Rect2(px, py, 1, 1), palette.window_lit)

func draw_crowd_clump(at: Vector2i, stamp_index: int, colors: Dictionary, warm: bool, silhouette: bool, raised: bool, seed: int) -> void:
	var stamp: Dictionary = host.CROWD_CLUMP_STAMPS[stamp_index]
	# Bodies alternate between the two dark mass tones so long runs read as a
	# textured cluster instead of one flat stripe (§7.5).
	var body_color: Color = colors.shadow if silhouette else (colors.body_alt if Style.hash01(seed + 2) < 0.35 else colors.body)
	for cell in stamp.body:
		Style.pixel_rect(host, Rect2(at.x + cell[0], at.y + cell[1], cell[2], cell[3]), body_color)
	# The traveling wave swaps in the arms-up variant (§9.5): heads lift one
	# cell and the raised arm cells draw in the body tone — 1-cell amplitude.
	if raised:
		for arm in stamp.arms:
			Style.pixel_rect(host, Rect2(at.x + arm[0], at.y + arm[1], 1, 1), body_color)
	var head_lift := 1 if raised else 0
	var head_color: Color = colors.shadow if silhouette else (colors.warm if warm else colors.head)
	for head in stamp.heads:
		Style.pixel_rect(host, Rect2(at.x + head[0], at.y + head[1] - head_lift, 1, 1), head_color)
	# Muted team-trim flag tick, capped around one per 40 spectators (§7.5).
	# Big plays surface a few more wavers and extend each flag by 2 cells.
	var big_play := host.reaction_timer > 0.0 and host.reaction_strength >= host.BIG_PLAY_STRENGTH
	var flag_chance := 0.10 if big_play else 0.05
	if stamp.has("flag") and not silhouette and Style.hash01(seed + 5) < flag_chance:
		var flag: Array = stamp.flag
		var flag_color: Color = colors.flag_a if Style.hash01(seed + 9) < 0.5 else colors.flag_b
		Style.pixel_rect(host, Rect2(at.x + flag[0], at.y + flag[1], 1, 1), flag_color)
		if big_play:
			Style.pixel_rect(host, Rect2(at.x + flag[0] - 1, at.y + flag[1] - 1, 2, 1), flag_color)

func blocked_by_aisle(x: int, aisles: Array) -> bool:
	for aisle in aisles:
		var aisle_x := int(aisle)
		if x + 4 > aisle_x and x < aisle_x + 2:
			return true
	return false

func thinned(x: int, left: int, right: int, thin: int, seed: int) -> bool:
	# Occupancy falloff toward one edge (§6.3: batting crowds thin toward the
	# pitch corridor). thin=+1 empties toward the right edge, -1 the left.
	if thin == 0:
		return false
	var t := float(x - left) / maxf(1.0, float(right - left))
	if thin < 0:
		t = 1.0 - t
	return Style.hash01(seed) < t * 0.85

func draw_bell_tower(palette: Dictionary, base: Vector2i, height: int) -> void:
	# Harbor bell tower (§7.3, §9.6): plank shaft rising out of the stand
	# bowl, a dark belfry opening holding the bell, and a stepped roof cap.
	# `base` is the tower foot on the facade; pass 08 rocks the bell and
	# radiates its stepped arc rings from the belfry.
	var top := base.y - height
	Style.pixel_rect(host, Rect2(base.x - 6, top + 12, 12, height - 12), palette.stand_shell)
	Style.pixel_rect(host, Rect2(base.x - 6, top + 12, 1, height - 12), palette.seat_board)
	Style.pixel_rect(host, Rect2(base.x + 5, top + 12, 1, height - 12), palette.ink_mid)
	Style.pixel_rect(host, Rect2(base.x - 6, base.y - 3, 12, 3), palette.roof_accent)
	# Belfry frame and opening.
	Style.pixel_rect(host, Rect2(base.x - 6, top + 2, 12, 10), palette.stand_shell)
	Style.pixel_rect(host, Rect2(base.x - 6, top + 2, 1, 10), palette.seat_board)
	Style.pixel_rect(host, Rect2(base.x - 5, top + 3, 10, 9), palette.ink)
	draw_bell(Vector2(base.x, top + 4), palette)
	# Stepped roof cap with a finial that lights after dark (§7.6).
	Style.pixel_rect(host, Rect2(base.x - 7, top + 1, 14, 1), palette.seat_board)
	Style.pixel_rect(host, Rect2(base.x - 4, top, 8, 1), palette.stand_shell)
	Style.pixel_rect(host, Rect2(base.x - 2, top - 1, 4, 1), palette.seat_board)
	var finial: Color = palette.seat_board if host.mood == "day" else palette.window_lit
	Style.pixel_rect(host, Rect2(base.x - 1, top - 3, 2, 2), finial)
	# While the bell rocks, its stepped arc rings radiate over the roofline.
	if host.bell_timer > 0.0:
		draw_bell_rings(palette, Vector2i(base.x, top + 7))

func draw_led_board(at: Vector2, palette: Dictionary) -> void:
	# Enamel lightboard face (§10.1 material, §7.3 placement): raised bezel,
	# ink face, corner rivets, and the reaction word in lantern gold (§9.5).
	Style.pixel_rect(host, Rect2(at, Vector2(52, 17)), palette.stand_shell)
	Style.pixel_rect(host, Rect2(at, Vector2(52, 1)), palette.seat_board)
	Style.pixel_rect(host, Rect2(at + Vector2(0, 16), Vector2(52, 1)), palette.ink_mid)
	Style.pixel_rect(host, Rect2(at + Vector2(2, 2), Vector2(48, 13)), palette.ink_mid)
	Style.pixel_rect(host, Rect2(at + Vector2(3, 3), Vector2(46, 11)), palette.ink)
	for rivet in [Vector2(1, 1), Vector2(50, 1), Vector2(1, 15), Vector2(50, 15)]:
		Style.pixel_rect(host, Rect2(at + rivet, Vector2(1, 1)), palette.seat_board)
	var text: String = host.led_text if host.led_timer > 0.0 else "PIXIBALL"
	var width: int = text.length() * 4 - 1
	var text_x: float = at.x + floor((52.0 - float(width)) * 0.5)
	# The reaction word blinks on the 12 fps crowd clock (§9.5): four ticks on,
	# four off — a 1.5 Hz cycle, comfortably under the 3 Hz cap (§11.5).
	var blink_on: bool = host.led_timer <= 0.0 or posmod(int(host.crowd_motion_tick / 4.0), 2) == 0
	if blink_on:
		# Reaction copy is the board's lantern_gold focal; ambient board chrome stays cooler.
		Style.pixel_text(host, text, Vector2(text_x, at.y + 6), palette.lantern_gold if host.led_timer > 0.0 else palette.lamp_glow, 1)
	Style.pixel_rect(host, Rect2(at.x + 8, at.y + 17, 3, 6), palette.stand_shell)
	Style.pixel_rect(host, Rect2(at.x + 41, at.y + 17, 3, 6), palette.stand_shell)
	Style.pixel_rect(host, Rect2(at.x + 8, at.y + 17, 1, 6), palette.ink_mid)
	Style.pixel_rect(host, Rect2(at.x + 41, at.y + 17, 1, 6), palette.ink_mid)

func draw_bell(pivot: Vector2, palette: Dictionary) -> void:
	# Compact 9-cell-wide bell sized for the belfry opening. While the bell
	# envelope runs it rocks exactly one cell left/right every four ticks with
	# a counter-swinging clapper (§9.6) — whole cells, no rotation.
	var sway := 0
	if host.bell_timer > 0.0:
		sway = 1 if posmod(int(host._bell_ticks() / 4.0), 2) == 0 else -1
	var x := int(pivot.x) + sway
	var y := int(pivot.y)
	Style.pixel_line(host, Vector2(pivot.x, y - 2), Vector2(pivot.x, y), palette.seat_board, 1)
	Style.pixel_rect(host, Rect2(x - 2, y, 5, 2), palette.window_lit)
	Style.pixel_rect(host, Rect2(x - 3, y + 2, 7, 3), palette.window_lit)
	Style.pixel_rect(host, Rect2(x - 4, y + 5, 9, 2), palette.lamp_glow)
	Style.pixel_rect(host, Rect2(x - sway * 2, y + 7, 1, 1), palette.lamp_glow)

func draw_bell_rings(palette: Dictionary, center: Vector2i) -> void:
	# Stepped lamp_glow arc rings radiate from the belfry, one per rock and at
	# most three alive (§9.6): each ring lives 12 ticks and rocks come every
	# 4, so the alive set can never exceed three.
	var ticks := host._bell_ticks()
	var latest := int(ticks / 4.0)
	for spawn in range(maxi(0, latest - 2), latest + 1):
		var age := ticks - spawn * 4
		if age < 0 or age >= 12:
			continue
		var radius := 5 + int(age / 2.0)
		var side := int(round(float(radius) * 0.7))
		Style.pixel_rect(host, Rect2(center.x - 1, center.y - radius, 3, 1), palette.lamp_glow)
		Style.pixel_rect(host, Rect2(center.x - side - 1, center.y - side, 2, 1), palette.lamp_glow)
		Style.pixel_rect(host, Rect2(center.x + side, center.y - side, 2, 1), palette.lamp_glow)
		Style.pixel_rect(host, Rect2(center.x - radius, center.y - 1, 1, 2), palette.lamp_glow)
		Style.pixel_rect(host, Rect2(center.x + radius, center.y - 1, 1, 2), palette.lamp_glow)

func draw_bunting(center: Vector2, palette: Dictionary, variant := 0) -> void:
	# Bunting swag (§7.3): one stepped tri-band drape sagging between two rope
	# ticks, in stitch/chalk/team_teal. The variant flips the band order so
	# neighboring swags never repeat exactly — the old triple-triangle rhythm
	# is dead.
	var bands: Array = [palette.chalk_line, palette.stitch_red, palette.signal_teal]
	if posmod(variant, 2) == 1:
		bands = [palette.chalk_line, palette.signal_teal, palette.stitch_red]
	Style.pixel_rect(host, Rect2(center.x - 5, center.y - 1, 2, 1), palette.ink_mid)
	Style.pixel_rect(host, Rect2(center.x + 4, center.y - 1, 2, 1), palette.ink_mid)
	Style.pixel_rect(host, Rect2(center.x - 4, center.y, 8, 1), bands[0])
	Style.pixel_rect(host, Rect2(center.x - 3, center.y + 1, 6, 1), bands[1])
	Style.pixel_rect(host, Rect2(center.x - 2, center.y + 2, 4, 1), bands[2])

func draw_fireworks(palette: Dictionary, left: int, right: int, horizon: int) -> void:
	# Walk-off fireworks (§9.7): only full-strength celebrations earn them.
	# Two burst slots alternate on the reaction clock, each living 4 ticks, so
	# at most two are ever simultaneous. Every spoke is a stepped 2-cell dash:
	# a lamp_glow inner cell under a team-trim tip.
	if not host._celebrating() or host.reaction_strength < 0.999:
		return
	var ticks := host._reaction_ticks()
	var span := right - left
	for slot in range(2):
		var phase := posmod(ticks - 6 - slot * 10, 20)
		if phase >= 4:
			continue
		var salt := host.reaction_serial * 37 + slot * 91 + (ticks - phase) * 7
		var cx := left + int(float(span) * (0.30 + 0.36 * float(slot))) + int(Style.hash01(salt) * 12.0) - 6
		var cy := horizon - 18 + int(Style.hash01(salt + 1) * 6.0)
		var trim: Color = palette.signal_teal if posmod(slot + host.reaction_serial, 2) == 0 else palette.stitch_red
		if phase == 0:
			Style.pixel_rect(host, Rect2(cx - 1, cy - 1, 2, 2), palette.lamp_glow)
			continue
		var radius := 1 + phase
		for direction: Vector2i in [
			Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
			Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
		]:
			var reach := radius if direction.x == 0 or direction.y == 0 else maxi(1, int(float(radius) * 0.75))
			var tip := Vector2i(cx, cy) + direction * reach
			var inner := Vector2i(cx, cy) + direction * maxi(1, reach - 1)
			Style.pixel_rect(host, Rect2(inner.x, inner.y, 1, 1), palette.lamp_glow)
			Style.pixel_rect(host, Rect2(tip.x, tip.y, 1, 1), trim)
		if phase < 2:
			Style.pixel_rect(host, Rect2(cx, cy, 1, 1), palette.lamp_glow)

func draw_lightbank(palette: Dictionary, x: int, top: int, base: int) -> void:
	Style.pixel_rect(host, Rect2(x + 6, top + 10, 4, base - top - 10), palette.stand_shell)
	Style.pixel_rect(host, Rect2(x + 7, top + 10, 1, base - top - 10), palette.seat_board)
	Style.pixel_rect(host, Rect2(x + 4, base - 2, 8, 2), palette.stand_shell)
	Style.pixel_rect(host, Rect2(x, top, 16, 10), palette.stand_shell)
	Style.pixel_rect(host, Rect2(x, top, 16, 1), palette.seat_board)
	# Night bell rock: the floodlight heads pulse one value step for two ticks
	# of every four-tick rock (§9.6).
	var head: Color = palette.window_lit
	if host.mood == "night" and host.bell_timer > 0.0 and posmod(host._bell_ticks(), 4) < 2:
		head = Style.shift_value(head, 1)
	for row in range(2):
		for col in range(4):
			Style.pixel_rect(host, Rect2(x + 1 + col * 4, top + 2 + row * 4, 3, 3), head)
	# Stepped bloom above the head: 2 rings by day/golden, 3 at night (§7.6).
	var rings := 3 if host.mood == "night" else 2
	for ring in range(1, rings + 1):
		var span := 16 - ring * 4
		Style.pixel_rect(host, Rect2(x + int((16 - span) / 2.0), top - ring * 2, span, 1), palette.lamp_glow)
	Style.pixel_rect(host, Rect2(x + 2, top + 10, 12, 1), palette.lamp_glow)


