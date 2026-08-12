class_name SimSquadGen
extends RefCounted
## Generates squads for tests, batch runs and the world layer.
##
## Everything is drawn from a passed-in SimRng so a seed reproduces a squad
## exactly. No global randomness.

const FIRST_NAMES := [
	"Ade", "Bo", "Cass", "Dev", "Ez", "Fen", "Gus", "Hal", "Ib", "Jarl",
	"Kit", "Lem", "Mo", "Nils", "Ove", "Pim", "Quin", "Rex", "Sten", "Tor",
	"Uzo", "Vic", "Wim", "Xan", "Yves", "Zeb", "Arn", "Bram", "Cole", "Dag",
	"Emil", "Finn", "Gil", "Hugo", "Ivo", "Jonas", "Kai", "Loki", "Mats", "Noa",
]

const LAST_NAMES := [
	"Ashby", "Brann", "Corta", "Duvall", "Eklund", "Farr", "Grieg", "Holm",
	"Iversen", "Jansen", "Krol", "Lund", "Mata", "Nurse", "Oduya", "Pratt",
	"Quist", "Renn", "Sorel", "Thane", "Ulven", "Vance", "Wren", "Yorke",
	"Zima", "Baird", "Cobb", "Drexler", "Elm", "Fogg", "Garnet", "Hask",
]

const CLUB_PREFIX := ["North", "Old", "Royal", "Little", "Great", "New", "Upper", "Iron", "Green", "Saint"]
const CLUB_STEM := ["ford", "burgh", "wich", "combe", "haven", "moor", "field", "gate", "well", "stead"]
const CLUB_SUFFIX := ["FC", "United", "Town", "City", "Rovers", "Athletic", "Wanderers", "Albion"]


## Builds a team of `formation.size()` starters plus `bench_size` substitutes at
## the given quality (0..1).
static func make_team(rng: SimRng, team_index: int, quality: float, formation: SimFormation = null, bench_size: int = 7) -> SimTeam:
	var team := SimTeam.new()
	team.team_index = team_index
	team.formation = formation if formation != null else SimFormation.four_three_three()
	team.club_name = club_name(rng)
	team.short_name = team.club_name.substr(0, 3).to_upper()
	team.tactics = SimTactics.balanced()
	team.kit = PackedColorArray([random_kit_colour(rng), Color(1, 1, 1)])

	var next_id := team_index * 100
	for slot in team.formation.size():
		var role := team.formation.roles[slot]
		# Individual quality varies around the team's level, so a squad has a
		# shape rather than eleven identical players.
		var individual: float = clampf(rng.gauss_clamped(quality, 0.075, 2.0), 0.05, 0.98)
		var p := _make_player(rng, next_id, team_index, role, individual, slot + 1)
		next_id += 1
		team.players.append(p)

	var bench_roles := [SimRole.GK, SimRole.CB, SimRole.FB, SimRole.CM, SimRole.CM, SimRole.WIDE, SimRole.ST]
	for i in bench_size:
		var role: int = bench_roles[i % bench_roles.size()]
		var individual: float = clampf(rng.gauss_clamped(quality - 0.06, 0.08, 2.0), 0.05, 0.95)
		var p := _make_player(rng, next_id, team_index, role, individual, team.formation.size() + i + 1)
		next_id += 1
		team.bench.append(p)
	return team


static func _make_player(rng: SimRng, id: int, team_index: int, role: int, quality: float, shirt: int) -> SimPlayer:
	var p := SimPlayer.new()
	var attrs := SimAttributes.generate(rng, role, quality)
	p.configure(id, team_index, role, attrs, person_name(rng))
	p.shirt = shirt
	p.appearance_seed = rng.next_u32()
	p.stamina = 1.0
	p.sharpness = rng.range_float(0.94, 1.0)
	p.morale = rng.range_float(0.4, 0.7)
	return p


static func person_name(rng: SimRng) -> String:
	return "%s %s" % [
		FIRST_NAMES[rng.range_int(0, FIRST_NAMES.size() - 1)],
		LAST_NAMES[rng.range_int(0, LAST_NAMES.size() - 1)],
	]


static func club_name(rng: SimRng) -> String:
	var stem: String = CLUB_PREFIX[rng.range_int(0, CLUB_PREFIX.size() - 1)] + CLUB_STEM[rng.range_int(0, CLUB_STEM.size() - 1)]
	return "%s %s" % [stem, CLUB_SUFFIX[rng.range_int(0, CLUB_SUFFIX.size() - 1)]]


static func random_kit_colour(rng: SimRng) -> Color:
	# Drawn from the master palette so the game stays coherent (PLAN.md §9.3).
	var palette := SimPalette.KIT_COLOURS
	return palette[rng.range_int(0, palette.size() - 1)]
