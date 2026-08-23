class_name WorldNames
extends RefCounted
## Where a footballer's name comes from (PLAN.md §8, §9.7).
##
## The register is British football as it was written and drawn between about
## 1985 and 1995, so the pools are the names that were on a team sheet then: men
## born in the fifties, sixties and early seventies. A squad reads right or it
## does not, and the test of it is reading twenty of them aloud.
##
## The four home nations have their own surnames because that is where the
## reading comes from -- a McQuade is Scottish before you are told he is, a
## Prosser Welsh -- and one mixed pool throws that away. Foreign players are
## rare, and were: one turns up every few squads and is worth remarking on.
##
## No famous names. Every surname here is a real British surname and none of
## them belonged to a footballer anybody remembers, because a generated Dalglish
## reads as a bug.

const ENG := 0
const SCO := 1
const WAL := 2
const IRL := 3
const FOREIGN := 4

const NATION_NAMES := ["England", "Scotland", "Wales", "Ireland", ""]
const NATION_CODES := ["ENG", "SCO", "WAL", "IRL", ""]

## Chance any one player is not British. About one in twelve, so a squad of
## eighteen usually has one and often has none.
const FOREIGN_CHANCE := 0.08

const FIRST_NAMES := {
	ENG: [
		"Gary", "Barry", "Kevin", "Dennis", "Trevor", "Terry", "Nigel", "Graham",
		"Stuart", "Ian", "Neil", "Colin", "Alan", "Keith", "Derek", "Malcolm",
		"Brian", "Clive", "Roy", "Ray", "Peter", "Paul", "Steve", "Dave",
		"Micky", "Tony", "Eddie", "Frank", "Les", "Vince", "Norman", "Geoff",
		"Wayne", "Darren", "Lee", "Carl", "Nicky", "Russell", "Martin", "Glenn",
	],
	SCO: [
		"Alec", "Archie", "Willie", "Jock", "Hamish", "Callum", "Donald", "Angus",
		"Fergus", "Murdo", "Sandy", "Duncan", "Kenny", "Davie", "Rab", "Gordon",
		"Stevie", "Iain", "Hughie", "Lachlan", "Euan", "Craig", "Ally", "Doug",
		"Bertie", "Wullie", "Rory", "Struan", "Ewen", "Findlay",
	],
	WAL: [
		"Emlyn", "Ieuan", "Gareth", "Dai", "Huw", "Rhys", "Gwyn", "Glyn",
		"Mervyn", "Aled", "Owain", "Trefor", "Cerith", "Idris", "Meirion", "Bryn",
		"Dylan", "Elfed", "Hywel", "Iolo", "Islwyn", "Gwilym", "Tegid", "Eifion",
		"Padrig", "Wyn", "Emyr", "Carwyn",
	],
	IRL: [
		"Declan", "Padraig", "Seamus", "Eamon", "Liam", "Niall", "Fintan", "Cormac",
		"Aidan", "Donal", "Fergal", "Ronan", "Brendan", "Kieran", "Malachy", "Oisin",
		"Ciaran", "Barra", "Colm", "Eoin", "Fionn", "Turlough", "Ruairi", "Diarmuid",
		"Cathal", "Senan", "Rossa", "Peadar",
	],
}

const SURNAMES := {
	ENG: [
		"Hodgkiss", "Bloomfield", "Tunnicliffe", "Beardsmore", "Padgett", "Sowerby",
		"Rimmer", "Chadwick", "Wetherall", "Grimsdale", "Hollins", "Bagshaw",
		"Pickering", "Kettleborough", "Shackleton", "Thorne", "Ollerenshaw", "Bullimore",
		"Applegarth", "Braithwaite", "Cheeseman", "Dutton", "Entwistle", "Farthing",
		"Garrity", "Hardcastle", "Ibbotson", "Jarvis", "Kenworthy", "Lambert",
		"Micklewright", "Nuttall", "Oldroyd", "Postlethwaite", "Ramsbottom", "Sidebottom",
		"Tetlow", "Umpleby", "Vickers", "Wagstaff", "Yardley", "Ackroyd",
		"Boothroyd", "Crabtree", "Dinsdale", "Earnshaw", "Fothergill", "Greenhalgh",
	],
	SCO: [
		"McQuade", "Kilgour", "Struthers", "Fairgrieve", "Cadenhead", "Lithgow",
		"Tosh", "Rennie", "Sillars", "Meiklejohn", "Baillie", "Guthrie",
		"Mochrie", "Kerrigan", "Nisbet", "Tulloch", "Balfour", "Wardrop",
		"Aitkenhead", "Bruntsfield", "Carnegie", "Drummond", "Elphinstone", "Ferrier",
		"Galbraith", "Hutcheon", "Inglis", "Jardine", "Kinnaird", "Lyall",
		"McCosh", "Nimmo", "Ogilvie", "Pettigrew", "Rintoul", "Symington",
		"Threipland", "Urquhart", "Weir", "Yuill",
	],
	WAL: [
		"Prosser", "Meredith", "Vaughan", "Pugh", "Llewellyn", "Bevan",
		"Tudor", "Maddock", "Beddoe", "Hopkin", "Gwyther", "Pritchard",
		"Cadwallader", "Probert", "Bowen", "Havard", "Amblin", "Brace",
		"Caddick", "Dando", "Eynon", "Gough", "Hemmings", "Joules",
		"Kinsey", "Lougher", "Mainwaring", "Nurse", "Oram", "Pomeroy",
		"Rowlands", "Skym", "Trahaearn", "Wooller",
	],
	IRL: [
		"Ferris", "Mulcahy", "Sheridan", "Kavanagh", "Muldoon", "Rafferty",
		"Boylan", "Cassidy", "Hegarty", "Coyle", "Fitzsimons", "Bracken",
		"Delaney", "Tierney", "Gorman", "Quigley", "Malone", "Considine",
		"Ahearne", "Buckley", "Clohessy", "Dillane", "Egan", "Flanagan",
		"Hanrahan", "Keaveney", "Loughnane", "Mannion", "Noonan", "O'Rourke",
		"Prendergast", "Quirke", "Roche", "Scanlon", "Twomey", "Whelan",
	],
}

## The rare foreigner, by the places a British club in this period actually
## bought from. The code goes on the record and on the team sheet.
const FOREIGN_POOLS := [
	{"code": "NOR", "country": "Norway",
		"first": ["Ole", "Rune", "Stig", "Jorgen", "Terje", "Havard"],
		"last": ["Sandvik", "Haugen", "Bjornstad", "Lillehaug", "Nordgaard", "Vik"]},
	{"code": "SWE", "country": "Sweden",
		"first": ["Lars", "Kenneth", "Mats", "Bjorn", "Roland", "Tommy"],
		"last": ["Oberg", "Sjoholm", "Lindqvist", "Palmgren", "Ekstrand", "Ahlberg"]},
	{"code": "DEN", "country": "Denmark",
		"first": ["Jens", "Soren", "Preben", "Flemming", "Morten", "Bent"],
		"last": ["Riis", "Kjeldsen", "Vestergaard", "Holmboe", "Dalgaard", "Skov"]},
	{"code": "NED", "country": "Holland",
		"first": ["Wim", "Ruud", "Cor", "Jurgen", "Pieter", "Sjaak"],
		"last": ["Doorn", "van Beek", "Kloosterman", "de Waal", "Verkerk", "Bosman"]},
	{"code": "YUG", "country": "Yugoslavia",
		"first": ["Zoran", "Dragan", "Slobodan", "Milos", "Branko", "Ivica"],
		"last": ["Petkovic", "Vasiljevic", "Radic", "Tomasevic", "Blazevic", "Kovacevic"]},
	{"code": "POL", "country": "Poland",
		"first": ["Krzysztof", "Zbigniew", "Andrzej", "Marek", "Jacek", "Tadeusz"],
		"last": ["Nowak", "Wisniewski", "Ostrowski", "Zielinski", "Baran", "Rutkowski"]},
	{"code": "ISL", "country": "Iceland",
		"first": ["Sigurdur", "Gunnar", "Petur", "Arnor", "Hafthor", "Bjarni"],
		"last": ["Palsson", "Thorvaldsson", "Jonsson", "Magnusson", "Gislason", "Einarsson"]},
	{"code": "GHA", "country": "Ghana",
		"first": ["Kwame", "Kofi", "Yaw", "Nii", "Kojo", "Ebo"],
		"last": ["Boateng", "Mensah", "Adjei", "Quartey", "Ofori", "Danquah"]},
	{"code": "NGA", "country": "Nigeria",
		"first": ["Ade", "Emeka", "Tunde", "Chuka", "Segun", "Uche"],
		"last": ["Bankole", "Okonkwo", "Adesanya", "Eze", "Balogun", "Nwosu"]},
]

## Terrace shortenings. What the crowd calls a man who has not earned an
## epithet, and the reason an ordinary squad member is still somebody.
##
## The first names that have a form everybody already knows. Generating these
## from the letters produced "Briao" and "Keny": the real ones are irregular,
## short, and there are not many of them, so they are simply written down.
const FIRST_FAMILIARS := {
	"Gary": "Gazza", "Barry": "Bazza", "Terry": "Tezza", "Kevin": "Kev",
	"Dennis": "Denno", "Trevor": "Trev", "Graham": "Gra", "Stuart": "Stu",
	"Malcolm": "Malc", "Derek": "Del", "Brian": "Bri", "Clive": "Cliff",
	"Peter": "Pete", "Paul": "Pauly", "Steve": "Stevo", "Dave": "Davo",
	"Micky": "Mick", "Tony": "Tone", "Eddie": "Ed", "Frank": "Frankie",
	"Norman": "Norm", "Geoff": "Geoffo", "Wayne": "Wazza", "Darren": "Daz",
	"Nicky": "Nick", "Russell": "Russ", "Martin": "Marty", "Nigel": "Nige",
	"Kenny": "Kenny", "Gordon": "Gordo", "Duncan": "Dunc", "Willie": "Wullie",
	"Archie": "Archie", "Alec": "Ecky", "Angus": "Gus", "Donald": "Donny",
	"Gareth": "Gaz", "Rhys": "Reesy", "Huw": "Huwie", "Declan": "Deco",
	"Seamus": "Shay", "Liam": "Lee", "Brendan": "Brenno", "Kieran": "Kez",
}

## Suffixes for the surname form, which is the other half of how a dressing room
## does it: Robson becomes Robbo, Nisbet becomes Nissy.
const FAMILIAR_SUFFIXES := ["o", "y", "sy"]

const VOWELS := "aeiou"


## The nation mix for a club, given the nation the club is in. A Scottish club
## is mostly Scottish and still signs Englishmen.
static func nation_weights(club_nation: int) -> PackedFloat32Array:
	var w := PackedFloat32Array([0.10, 0.10, 0.06, 0.08])
	w[club_nation] = 0.76
	return w


## Draws a nation for one player. `weights` is over the four home nations; the
## foreign draw happens first and ignores them.
static func draw_nation(rng: SimRng, weights: PackedFloat32Array, allow_foreign: bool = true) -> int:
	if allow_foreign and rng.chance(FOREIGN_CHANCE):
		return FOREIGN
	return rng.weighted_index(weights)


## A full name for a nation: first, last, and the code that goes on the record.
## For a foreigner the code is his country's, not "FOR".
static func draw_name(rng: SimRng, nation: int) -> Dictionary:
	if nation == FOREIGN:
		var pool: Dictionary = FOREIGN_POOLS[rng.range_int(0, FOREIGN_POOLS.size() - 1)]
		var firsts: Array = pool["first"]
		var lasts: Array = pool["last"]
		return {
			"first": firsts[rng.range_int(0, firsts.size() - 1)],
			"last": lasts[rng.range_int(0, lasts.size() - 1)],
			"code": pool["code"],
			"country": pool["country"],
		}
	var first_pool: Array = FIRST_NAMES[nation]
	var last_pool: Array = SURNAMES[nation]
	return {
		"first": first_pool[rng.range_int(0, first_pool.size() - 1)],
		"last": last_pool[rng.range_int(0, last_pool.size() - 1)],
		"code": NATION_CODES[nation],
		"country": NATION_NAMES[nation],
	}


## What the dressing room calls him. Gary Hodgkiss is Gazza, Alec Nisbet is
## Nissy, and a name that will not take either form has none -- plenty of men
## are called by their surname and nothing else.
##
## Foreign players do not get one. The terrace gave them one eventually, but a
## generated "Sandvikky" reads as a bug rather than as affection.
static func familiar(rng: SimRng, first: String, last: String, nation: int) -> String:
	if nation == FOREIGN:
		return ""
	# The first-name form, where one exists, is what he is actually called.
	if FIRST_FAMILIARS.has(first) and rng.chance(0.65):
		return FIRST_FAMILIARS[first]
	return _from_surname(rng, last)


## Cuts a surname at the end of its first syllable and hangs a suffix on it.
## Refuses rather than produces nonsense: "Trahaearn" has no short form and a
## made-up one is worse than none.
static func _from_surname(rng: SimRng, last: String) -> String:
	var lower := last.to_lower()
	var cut := ""
	# Walk to the first vowel, then take the consonants that close the syllable.
	var seen_vowel := false
	for i in lower.length():
		var ch := lower.substr(i, 1)
		var is_vowel := VOWELS.contains(ch)
		if seen_vowel and not is_vowel:
			cut = lower.substr(0, i + 1)
			break
		if is_vowel:
			seen_vowel = true
	if cut.length() < 3 or cut.length() > 5:
		return ""
	var tail := cut.substr(cut.length() - 1, 1)
	# 'h', 'w' and 'y' close nothing you can say a suffix after.
	if "hwy".contains(tail):
		return ""
	var suffix: String = FAMILIAR_SUFFIXES[rng.range_int(0, FAMILIAR_SUFFIXES.size() - 1)]
	# A doubled consonant is what makes Robbo out of Robson and Kerry out of
	# Kerrigan, and it only works where the syllable is short.
	if suffix != "sy" and cut.length() == 3 and VOWELS.contains(cut.substr(1, 1)):
		cut += tail
	if suffix == "sy" and tail == "s":
		suffix = "y"
	return cut.substr(0, 1).to_upper() + cut.substr(1) + suffix
