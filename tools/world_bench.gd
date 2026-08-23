class_name WorldBench
extends RefCounted
## Prints a generated club so the names, the ages and the tails can be read
## rather than measured (`./run.sh world`).
##
## No match runs and nothing here is a statistic. It exists because a squad is
## judged the way the match is judged -- by looking at it -- and twenty names
## read aloud say more about the register than any number could.

static func run(flags: Dictionary) -> void:
	var seed_value := int(flags.get("seed", "1"))
	var reputation := float(flags.get("reputation", "0.35"))
	var club_count := int(flags.get("clubs", "0"))
	var rounds := int(flags.get("rounds", str(WorldSeason.DEFAULT_ROUNDS)))
	var reports := int(flags.get("reports", "3"))
	var rng := SimRng.new(seed_value)

	if club_count > 0 or flags.has("league"):
		_print_league(rng, club_count if club_count > 0 else WorldSeason.DEFAULT_CLUBS, reputation, rounds)
		return

	var club := WorldGen.club(rng, 0, reputation)
	_print_club(club, reports)


static func _print_club(club: WorldClub, reports: int) -> void:
	print("%s (%s), %s" % [club.name, club.nickname, club.ground])
	print("reputation %.2f, capacity %s, wage budget £%s/wk, balance £%s" % [
		club.reputation, _thousands(club.capacity), _thousands(club.wage_budget), _thousands(club.balance)])
	print("")

	var starters := club.best_eleven()
	var picked := {}
	for p in starters:
		picked[p.id] = true

	var listed := club.squad.duplicate()
	listed.sort_custom(func(a, b): return a.shirt < b.shirt)
	print("  # XI  name                             called    nat  role  age   ht   wage  traits")
	for p in listed:
		print("%3d %s  %-31s  %-8s  %s  %-4s  %2d  %.2f  %5s  %s" % [
			p.shirt,
			"*" if picked.has(p.id) else " ",
			"%s %s" % [p.first_name, p.display_name()],
			p.familiar,
			p.nation_code,
			SimRole.name_of(p.role),
			p.age,
			p.height,
			"£" + str(p.wage),
			", ".join(_trait_labels(p.traits)),
		])
	print("")
	print("true rating %.3f, believed %.3f" % [club.true_rating(), _believed(starters)])

	var noted := _noted(club.squad)
	if noted.is_empty():
		print("nobody in this squad is describable in four words -- check WorldGen.TAIL_KINDS")
	else:
		print("")
		for p in noted:
			print("%s -- %s, %s" % [p.display_name(), p.archetype, p.full_name()])

	if reports > 0:
		print("")
		var shown := 0
		for p in starters:
			if shown >= reports:
				break
			print(WorldScout.report(p))
			print("")
			shown += 1


static func _print_league(rng: SimRng, club_count: int, centre: float, rounds: int) -> void:
	var clubs := WorldGen.league(rng, club_count, centre)
	var ids := PackedInt32Array()
	for c in clubs:
		ids.append(c.id)
	var season := WorldSeason.create(rng, ids, 1985, rounds)

	print("%d clubs, %d games each, %d fixtures over %d weeks" % [
		clubs.size(), season.games_per_club(), season.fixtures.size(), season.round_count()])
	print("")
	print("  club                        short  nickname          rep   ground")
	for c in clubs:
		print("  %-26s  %-5s  %-16s  %.2f  %s" % [c.name, c.short_name, c.nickname, c.reputation, c.ground])
	print("")
	print("week 1:")
	for f in season.fixtures_in_round(0):
		print("  %s v %s" % [_club_by_id(clubs, int(f["home"])).name, _club_by_id(clubs, int(f["away"])).name])


static func _club_by_id(clubs: Array[WorldClub], id: int) -> WorldClub:
	for c in clubs:
		if c.id == id:
			return c
	return WorldClub.new()


static func _trait_labels(traits: PackedStringArray) -> PackedStringArray:
	var out := PackedStringArray()
	for t in traits:
		out.append(WorldTraits.label(t))
	return out


static func _noted(squad: Array[WorldPlayer]) -> Array[WorldPlayer]:
	var out: Array[WorldPlayer] = []
	for p in squad:
		if p.epithet != "":
			out.append(p)
	return out


static func _believed(players: Array[WorldPlayer]) -> float:
	if players.is_empty():
		return 0.0
	var total := 0.0
	for p in players:
		total += p.believed_rating()
	return total / float(players.size())


static func _thousands(value: int) -> String:
	var s := str(absi(value))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = "," + out
	return ("-" if value < 0 else "") + out
