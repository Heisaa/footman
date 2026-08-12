class_name SimAttributes
extends RefCounted
## A player's true attributes, all normalised to 0..1.
##
## These drive the simulation exactly and are never shown to the player as
## numbers (PLAN.md §6.1). The scout-report generator is the only thing that
## turns them into something a human reads.

# Physical
var pace := 0.5
var acceleration := 0.5
var stamina := 0.5
var strength := 0.5
var jumping := 0.5
var agility := 0.5

# Technical
var first_touch := 0.5
var passing := 0.5
var technique := 0.5
var finishing := 0.5
var power := 0.5
var heading := 0.5
var tackling := 0.5
var dribbling := 0.5
var crossing := 0.5

# Mental
var decisions := 0.5
var awareness := 0.5
var positioning := 0.5
var composure := 0.5
var work_rate := 0.5
var aggression := 0.5
var teamwork := 0.5

# Goalkeeping
var reflexes := 0.5
var handling := 0.5
var command := 0.5
var distribution := 0.5

const PHYSICAL := ["pace", "acceleration", "stamina", "strength", "jumping", "agility"]
const TECHNICAL := ["first_touch", "passing", "technique", "finishing", "power", "heading", "tackling", "dribbling", "crossing"]
const MENTAL := ["decisions", "awareness", "positioning", "composure", "work_rate", "aggression", "teamwork"]
const KEEPING := ["reflexes", "handling", "command", "distribution"]

const ALL := [
	"pace", "acceleration", "stamina", "strength", "jumping", "agility",
	"first_touch", "passing", "technique", "finishing", "power", "heading", "tackling", "dribbling", "crossing",
	"decisions", "awareness", "positioning", "composure", "work_rate", "aggression", "teamwork",
	"reflexes", "handling", "command", "distribution",
]


func clone() -> SimAttributes:
	var a := SimAttributes.new()
	for key in ALL:
		a.set(key, get(key))
	return a


## Mean of the attributes that matter for a role. Used for squad ratings and by
## the abstract league model, never shown to the player.
func role_rating(role: int) -> float:
	var weights: Dictionary = SimRole.attribute_weights(role)
	var total := 0.0
	var weight_sum := 0.0
	for key in weights:
		total += float(get(key)) * float(weights[key])
		weight_sum += float(weights[key])
	return total / maxf(weight_sum, 1e-6) if weight_sum > 0.0 else 0.5


## Generates a plausible attribute set for a role at a given quality (0..1),
## with `spread` controlling how lumpy the player is.
static func generate(rng: SimRng, role: int, quality: float, spread: float = 0.12) -> SimAttributes:
	var a := SimAttributes.new()
	var weights: Dictionary = SimRole.attribute_weights(role)
	for key in ALL:
		# Role-relevant attributes cluster near the player's quality; the rest
		# drift toward the middle of the population.
		var relevance := float(weights.get(key, 0.0))
		var centre: float = lerpf(0.35 + 0.3 * quality, quality, clampf(relevance, 0.0, 1.0))
		var v: float = rng.gauss_clamped(centre, spread, 2.5)
		a.set(key, clampf(v, 0.05, 0.99))
	if role == SimRole.GK:
		for key in KEEPING:
			a.set(key, clampf(rng.gauss_clamped(quality, spread * 0.8, 2.5), 0.05, 0.99))
	else:
		# Outfield players are hopeless keepers, and it must never be worth
		# playing one in goal.
		for key in KEEPING:
			a.set(key, clampf(float(a.get(key)) * 0.35, 0.02, 0.4))
	return a
