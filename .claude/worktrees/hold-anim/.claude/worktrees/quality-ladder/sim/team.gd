class_name SimTeam
extends RefCounted
## One side in a match: a shape, a set of players, and a tactical plan.

var team_index := SimConsts.TEAM_HOME
var club_name := "Home"
var short_name := "HOM"
var formation: SimFormation = SimFormation.four_three_three()
var tactics: SimTactics = null
## Players in slot order: index i occupies formation slot i.
var players: Array[SimPlayer] = []
## Players available on the bench.
var bench: Array[SimPlayer] = []
## Presentation only. Kit colours as a two-entry palette.
var kit := PackedColorArray([Color(0.92, 0.24, 0.24), Color(1, 1, 1)])

var substitutions_made := 0


func size() -> int:
	return players.size()


func keeper() -> SimPlayer:
	for p in players:
		if p.is_keeper and p.on_pitch:
			return p
	return players[0] if not players.is_empty() else null


## Mean role rating of the starting eleven. Used for reporting and by the
## abstract league model; never shown to the player as a number.
func rating() -> float:
	if players.is_empty():
		return 0.5
	var total := 0.0
	for p in players:
		total += p.attrs.role_rating(p.role)
	return total / float(players.size())


func slot_of(player: SimPlayer) -> int:
	return players.find(player)


func ensure_tactics() -> SimTactics:
	if tactics == null:
		tactics = SimTactics.new()
	return tactics
