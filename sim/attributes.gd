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

## Which foot he favours, and how much of him the other one is.
##
## Not in `ALL`, and deliberately: everything in that list is a 0..1 quantity
## drawn against the player's quality and averaged into a role rating, and a
## foot is neither a quantity nor better in one direction. `weak_foot` is a
## quantity but is not a *quality* -- a two-footed journeyman is common and a
## brilliant one-footed winger is the game's most familiar shape -- so it is
## drawn on its own too.
##
## What reads them is `SimTouch`: the side of the body a ball is played to costs
## aim and costs range, exactly the way the direction the body is pointing
## already does, and the foot that ends up striking the ball is what decides
## which way it bends. See `SimTouch.foot_cost` and `SimTouch.curl_for`.
const FOOT_RIGHT := 0
const FOOT_LEFT := 1
var foot := FOOT_RIGHT
## How usable the other foot is: 0 is a man with one, 1 is genuinely two-footed.
var weak_foot := 0.5


static func other_foot(f: int) -> int:
	return FOOT_LEFT if f == FOOT_RIGHT else FOOT_RIGHT

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
	a.foot = foot
	a.weak_foot = weak_foot
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


## Share of footballers who are left-footed, and what standing on a flank does
## to it.
##
## A side is not a coin flip eleven times. Left-footers are about a fifth of the
## population and most of them end up in the two left-sided slots, which is why
## a real team has a left-footed left-back and a right-footed everything else --
## and why the inverted winger reads as a *choice* when a manager makes it. With
## a flat draw there is no such thing as an inverted winger, because there is no
## expectation to invert.
##
## `side` is the slot's canonical z over the half-width, so negative is the left
## flank: a team attacking +X faces +X, and facing +X a man's left is -Z.
const LEFT_FOOTED := 0.22
const LEFT_FOOTED_ON_LEFT := 0.68
const LEFT_FOOTED_ON_RIGHT := 0.07


## The chance this slot's occupant is left-footed.
static func left_foot_chance(side: float) -> float:
	if side < 0.0:
		return lerpf(LEFT_FOOTED, LEFT_FOOTED_ON_LEFT, clampf(-side, 0.0, 1.0))
	return lerpf(LEFT_FOOTED, LEFT_FOOTED_ON_RIGHT, clampf(side, 0.0, 1.0))


## Generates a plausible attribute set for a role at a given quality (0..1),
## with `spread` controlling how lumpy the player is. `side` is where the slot
## stands across the pitch, -1 to 1, and is read by the foot alone.
static func generate(rng: SimRng, role: int, quality: float, spread: float = 0.12, side: float = 0.0) -> SimAttributes:
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
	a.foot = FOOT_LEFT if rng.chance(left_foot_chance(side)) else FOOT_RIGHT
	# A better player has a slightly better other foot, and only slightly. It is
	# a thing you are coached out of rather than a thing talent brings, so the
	# ladder is short and the spread is wide: the population is full of good
	# players with one foot, which is the shape the attribute exists to make.
	a.weak_foot = clampf(rng.gauss_clamped(lerpf(0.28, 0.44, quality), 0.15, 2.5), 0.05, 0.95)
	return a
