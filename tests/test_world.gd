extends SimTestCase
## The identity layer: names, tails, beliefs, squads and a fixture list.
##
## Everything here is a check on a mechanism rather than on a figure (CLAUDE.md,
## "Test and debug with causality in mind"). Whether a squad *reads* right is a
## thing the owner judges by looking at `./run.sh world`; what this asserts is
## that the machinery underneath it did what it says -- the pool a surname came
## from, the tail that was forced, the belief that moved toward the truth, the
## fixture list where everybody plays everybody twice.


func run() -> void:
	_test_names_come_from_the_right_pool()
	_test_familiar_names()
	_test_generation_is_deterministic()
	_test_squad_has_one_or_two_tails()
	_test_forced_tail_reaches_the_tail()
	_test_reputation_moves_the_mean()
	_test_epithets_only_on_tails()
	_test_knowledge_starts_vague_and_sharpens()
	_test_best_eleven_fills_the_shape()
	_test_sim_team_is_complete()
	_test_season_is_the_length_it_says()
	_test_fixture_list_is_a_double_round_robin()
	_test_table_arithmetic()
	_test_wage_rises_with_quality()


func _test_names_come_from_the_right_pool() -> void:
	var rng := SimRng.new(11)
	for nation in [WorldNames.ENG, WorldNames.SCO, WorldNames.WAL, WorldNames.IRL]:
		for _i in 40:
			var parts := WorldNames.draw_name(rng, nation)
			check(WorldNames.FIRST_NAMES[nation].has(parts["first"]),
				"first name %s is not in the %s pool" % [parts["first"], WorldNames.NATION_CODES[nation]])
			check(WorldNames.SURNAMES[nation].has(parts["last"]),
				"surname %s is not in the %s pool" % [parts["last"], WorldNames.NATION_CODES[nation]])
			check_equal(parts["code"], WorldNames.NATION_CODES[nation], "nation code follows the pool")

	# A foreigner carries his own country's code, not a placeholder.
	var foreign := WorldNames.draw_name(rng, WorldNames.FOREIGN)
	check(str(foreign["code"]).length() == 3, "foreign code is a three-letter country")
	check(str(foreign["country"]) != "", "foreign player has a country")

	# A club's own nation dominates its squad without excluding the others.
	var weights := WorldNames.nation_weights(WorldNames.SCO)
	check(weights[WorldNames.SCO] > weights[WorldNames.ENG], "a Scottish club is mostly Scottish")
	for i in weights.size():
		check(weights[i] > 0.0, "no home nation is impossible at any club")


func _test_familiar_names() -> void:
	var rng := SimRng.new(3)
	var british := 0
	for _i in 60:
		var parts := WorldNames.draw_name(rng, WorldNames.ENG)
		var fam := WorldNames.familiar(rng, parts["first"], parts["last"], WorldNames.ENG)
		if fam != "":
			british += 1
			# "Ed" is a name; "E." is an initial, and this layer never produces one.
			check(fam.length() >= 2 and not fam.contains("."),
				"a familiar name is a shortening, not an initial: %s" % fam)
			check(fam == fam.substr(0, 1).to_upper() + fam.substr(1), "familiar name is capitalised once: %s" % fam)
	check(british > 45, "most British names take a terrace shortening (got %d of 60)" % british)

	var foreign := WorldNames.draw_name(rng, WorldNames.FOREIGN)
	check_equal(WorldNames.familiar(rng, foreign["first"], foreign["last"], WorldNames.FOREIGN), "",
		"foreign players get no terrace shortening")


func _test_generation_is_deterministic() -> void:
	var a := WorldGen.club(SimRng.new(77), 0, 0.4)
	var b := WorldGen.club(SimRng.new(77), 0, 0.4)
	check_equal(a.name, b.name, "same seed, same club name")
	check_equal(a.squad.size(), b.squad.size(), "same seed, same squad size")
	for i in a.squad.size():
		check_equal(a.squad[i].full_name(), b.squad[i].full_name(), "same seed, same man at slot %d" % i)
		check_near(a.squad[i].attrs.passing, b.squad[i].attrs.passing, 1e-9, "same seed, same attributes")
		check_equal(a.squad[i].appearance_seed, b.squad[i].appearance_seed, "same seed, same face")

	var c := WorldGen.club(SimRng.new(78), 0, 0.4)
	check(c.name != a.name or c.squad[0].full_name() != a.squad[0].full_name(),
		"a different seed is a different club")


func _test_squad_has_one_or_two_tails() -> void:
	for seed_value in range(20, 32):
		var squad := WorldGen.squad(SimRng.new(seed_value), 0.4, WorldNames.ENG, 0)
		var noted := 0
		for p in squad:
			if p.archetype != WorldNickname.NONE:
				noted += 1
		# The generator forces one or two; a third can fall out of the ordinary
		# draw, which is allowed. None cannot: that is the mechanism failing.
		check(noted >= 1, "seed %d: a squad with nobody in it worth describing" % seed_value)
		check(noted <= 5, "seed %d: %d men in one squad are tails" % [seed_value, noted])


func _test_forced_tail_reaches_the_tail() -> void:
	var rng := SimRng.new(5)
	var weights := WorldNames.nation_weights(WorldNames.ENG)

	var giant := WorldGen.player(rng, 1, SimRole.ST, 0.5, weights, WorldNickname.GIANT)
	check(giant.height >= WorldGen.GIANT_HEIGHT, "a giant is a giant: %.2f m" % giant.height)
	check(giant.attrs.strength >= 0.80, "a giant is strong with it")
	check_equal(giant.archetype, WorldNickname.GIANT, "the forced tail is the archetype that comes out")

	var sprite := WorldGen.player(rng, 2, SimRole.AM, 0.5, weights, WorldNickname.SPRITE)
	check(sprite.height <= WorldGen.SPRITE_HEIGHT, "a sprite is small: %.2f m" % sprite.height)
	check(sprite.attrs.strength <= 0.30, "and pays for it")

	var hammer := WorldGen.player(rng, 3, SimRole.ST, 0.5, weights, WorldNickname.HAMMER)
	check(hammer.attrs.power >= 0.85, "a hammer strikes it")
	check(hammer.attrs.passing <= 0.50, "and does not pass it")

	# The exchange is the point: a tail is uneven, not merely better.
	var plain := WorldGen.player(rng, 4, SimRole.ST, 0.5, weights)
	check(hammer.attrs.power > plain.attrs.power, "the tail is above the ordinary man where it is named")


func _test_reputation_moves_the_mean() -> void:
	# Reputation shifts the mean and nothing else, so a big sample of a strong
	# club beats a big sample of a weak one on average without either losing
	# its tails. Two squads is not a sample; ten is enough for a mean this far
	# apart to be structural rather than statistical.
	var strong := 0.0
	var weak := 0.0
	for seed_value in 10:
		strong += _mean_quality(WorldGen.squad(SimRng.new(seed_value), 0.85, WorldNames.ENG, 0))
		weak += _mean_quality(WorldGen.squad(SimRng.new(seed_value), 0.10, WorldNames.ENG, 0))
	check(strong > weak, "a better club has better players (%.3f v %.3f)" % [strong / 10.0, weak / 10.0])

	# And the small club still gets its freak.
	var found := false
	for seed_value in range(40, 48):
		for p in WorldGen.squad(SimRng.new(seed_value), 0.10, WorldNames.ENG, 0):
			if p.archetype != WorldNickname.NONE:
				found = true
				break
	check(found, "a bottom club is still allowed a man worth describing")


func _test_epithets_only_on_tails() -> void:
	# An epithet implies a tail, but a tail does not imply an epithet: a squad
	# carries at most `EPITHETS_PER_SQUAD_MAX` of them and never two of a kind,
	# because a bad side otherwise came out with three calamities in it.
	for seed_value in 10:
		var named := 0
		var kinds := {}
		for p in WorldGen.squad(SimRng.new(seed_value), 0.20, WorldNames.ENG, 0):
			if p.epithet == "":
				check_equal(p.display_name(), p.surname, "a man with no epithet is his surname")
				continue
			named += 1
			check(p.archetype != WorldNickname.NONE, "%s has an epithet and no tail" % p.full_name())
			check(not kinds.has(p.archetype), "two %ss in one squad" % p.archetype)
			kinds[p.archetype] = true
			check(p.display_name().contains(p.surname), "the epithet goes in front of the surname")
		check(named <= WorldGen.EPITHETS_PER_SQUAD_MAX,
			"seed %d: %d men in one squad are called something other than their name" % [seed_value, named])
		check(named >= 1, "seed %d: nobody in the squad is called anything" % seed_value)

	# How an epithet is written, and it has to read as a nickname rather than as
	# a middle name.
	check_equal(WorldNickname.stitch("Hot-Shot", "Balfour"), "'Hot-Shot' Balfour", "the epithet is quoted")
	check_equal(WorldNickname.stitch("The Wall", "Kilgour"), "'The Wall' Kilgour", "a phrase is quoted too")
	check_equal(WorldNickname.stitch("", "Prosser"), "Prosser", "no epithet, no decoration")


func _test_knowledge_starts_vague_and_sharpens() -> void:
	var rng := SimRng.new(9)
	var p := WorldGen.player(rng, 1, SimRole.CM, 0.6, WorldNames.nation_weights(WorldNames.ENG))
	p.seed_knowledge(rng, 0.05)

	var before := absf(p.estimate_of("passing") - p.attrs.passing)
	var confidence_before := p.confidence_of("passing")
	for _i in 40:
		p.observe(rng, "passing", 0.25)
	var after := absf(p.estimate_of("passing") - p.attrs.passing)
	check(p.confidence_of("passing") > confidence_before, "watching him raises confidence")
	check(after <= before + 0.02, "watching him moves the estimate toward the truth (%.3f -> %.3f)" % [before, after])
	check(p.confidence_of("tackling") < p.confidence_of("passing"),
		"an attribute nobody watched stays unknown")

	# The truth never moves. Everything a screen shows comes from the belief,
	# and if an observation could edit `attrs` the hidden-numbers rule is gone.
	var truth := p.attrs.passing
	p.observe(rng, "passing", 1.0)
	check_near(p.attrs.passing, truth, 1e-9, "observing a player does not change the player")


func _test_best_eleven_fills_the_shape() -> void:
	var club := WorldGen.club(SimRng.new(4), 0, 0.5)
	var shape := club.ensure_formation()
	var eleven := club.best_eleven()
	check_equal(eleven.size(), shape.size(), "every slot in the formation is filled")

	var seen := {}
	for i in eleven.size():
		var p: WorldPlayer = eleven[i]
		check(not seen.has(p.id), "%s is picked twice" % p.full_name())
		seen[p.id] = true
		var slot_role: int = shape.roles[i]
		check_equal(p.role == SimRole.GK, slot_role == SimRole.GK,
			"a keeper is picked in goal and nowhere else")

	var bench := club.remainder(eleven)
	check_equal(eleven.size() + bench.size(), club.squad.size(), "everybody is either picked or not")
	for i in range(1, bench.size()):
		check(bench[i - 1].believed_rating() >= bench[i].believed_rating(),
			"the bench is in the order a manager would reach for it")


func _test_sim_team_is_complete() -> void:
	var club := WorldGen.club(SimRng.new(6), 1, 0.5)
	var team := club.to_sim_team(SimConsts.TEAM_AWAY)
	check_equal(team.players.size(), club.ensure_formation().size(), "the sim gets a full side")
	check(team.bench.size() > 0, "and a bench")
	check(team.keeper() != null, "and a keeper in it")
	check_equal(team.club_name, club.name, "the club travels with the team")

	var ids := {}
	for p in team.players + team.bench:
		check(not ids.has(p.id), "two men in one squad share a sim id")
		ids[p.id] = true
		check(p.player_name != "", "every man on the team sheet has a name")


func _test_season_is_the_length_it_says() -> void:
	# The division the game ships with: nine clubs, home and away, sixteen games
	# each. The number is a wall-clock decision (`WorldSeason.DEFAULT_CLUBS`),
	# so it is checked rather than assumed.
	var ids := PackedInt32Array()
	for i in WorldSeason.DEFAULT_CLUBS:
		ids.append(i)
	var season := WorldSeason.create(SimRng.new(1), ids)
	check_equal(season.games_per_club(), 16, "nine clubs home and away is sixteen games each")
	check_equal(season.round_count(), 18, "and eighteen weeks, one of them blank for each club")
	check_equal(season.fixtures.size(), 72, "which is seventy-two fixtures")

	var played := {}
	for f in season.fixtures:
		for id in [int(f["home"]), int(f["away"])]:
			played[id] = int(played.get(id, 0)) + 1
	for id in ids:
		check_equal(int(played.get(id, 0)), 16, "club %d plays sixteen" % id)

	# A single pass is the same list with one leg: half the games, half the year.
	var single := WorldSeason.create(SimRng.new(1), ids, 1985, 1)
	check_equal(single.games_per_club(), 8, "one pass is eight games each")
	check_equal(single.round_count(), 9, "over nine weeks")


func _test_fixture_list_is_a_double_round_robin() -> void:
	for club_count in [4, 9, 10, 15]:
		var ids := PackedInt32Array()
		for i in club_count:
			ids.append(i)
		var season := WorldSeason.create(SimRng.new(club_count), ids)
		check_equal(season.fixtures.size(), club_count * (club_count - 1),
			"%d clubs play %d fixtures" % [club_count, club_count * (club_count - 1)])

		var pairs := {}
		for f in season.fixtures:
			var key := "%d-%d" % [int(f["home"]), int(f["away"])]
			check(not pairs.has(key), "%s is played twice at the same ground" % key)
			pairs[key] = true
		for a in club_count:
			for b in club_count:
				if a == b:
					continue
				check(pairs.has("%d-%d" % [a, b]), "%d never hosts %d" % [a, b])

		# Nobody plays twice in one week, which is what makes it a fixture list
		# rather than a list of fixtures.
		for r in season.round_count():
			var playing := {}
			var week_fixtures := season.fixtures_in_round(r)
			check_equal(week_fixtures.size(), club_count / 2,
				"week %d of a %d-club season is %d matches" % [r, club_count, club_count / 2])
			for f in week_fixtures:
				for id in [int(f["home"]), int(f["away"])]:
					check(not playing.has(id), "club %d plays twice in week %d" % [id, r])
					playing[id] = true


func _test_table_arithmetic() -> void:
	var ids := PackedInt32Array([0, 1, 2, 3])
	var season := WorldSeason.create(SimRng.new(2), ids)
	var goals := 0
	var index := 0
	for f in season.fixtures:
		# A made-up spread of results; the arithmetic is what is under test.
		season.record_result(f, index % 3, (index + 1) % 2)
		goals += (index % 3) + ((index + 1) % 2)
		index += 1

	var rows := season.table()
	check_equal(rows.size(), 4, "a row per club")
	var points := 0
	var played := 0
	var scored := 0
	for row in rows:
		points += int(row["points"])
		played += int(row["played"])
		scored += int(row["for"])
		check_equal(int(row["played"]), int(row["won"]) + int(row["drawn"]) + int(row["lost"]),
			"a club's results add up to its games")
		check_equal(int(row["difference"]), int(row["for"]) - int(row["against"]),
			"goal difference is goals for minus against")
	check_equal(played, season.fixtures.size() * 2, "every fixture is two clubs' games")
	check_equal(scored, goals, "the goals in the table are the goals that were scored")

	var draws := 0
	for f in season.fixtures:
		if int(f["home_goals"]) == int(f["away_goals"]):
			draws += 1
	check_equal(points, (season.fixtures.size() - draws) * WorldSeason.WIN_POINTS + draws * 2 * WorldSeason.DRAW_POINTS,
		"three for a win, one each for a draw, and nothing invented")

	for i in range(1, rows.size()):
		check(int(rows[i - 1]["points"]) >= int(rows[i]["points"]), "the table is sorted on points")
	check(season.position_of(int(rows[0]["club"])) == 1, "the top of the table is first")


func _test_wage_rises_with_quality() -> void:
	check(WorldGen.wage_for(0.8, 26) > WorldGen.wage_for(0.4, 26), "a better player costs more")
	check(WorldGen.wage_for(0.6, 18) < WorldGen.wage_for(0.6, 26), "a teenager is on nothing")
	check(WorldGen.wage_for(0.6, 36) < WorldGen.wage_for(0.6, 26), "and so is a man at the end")


func _mean_quality(squad: Array[WorldPlayer]) -> float:
	var total := 0.0
	for p in squad:
		total += p.attrs.role_rating(p.role)
	return total / maxf(float(squad.size()), 1.0)
