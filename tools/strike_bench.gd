class_name StrikeBench
extends RefCounted
## `./run.sh strike` — where a struck ball actually lands, against where the
## decision layer was told it would.
##
## `SimTouch.execution_accuracy` exists so a value function cannot pick a
## forty-metre ball on the strength of the grass at the far end, having no idea
## the player cannot hit it, and its own note says the point of it is that the
## model and the strike **share one error model**. Nothing checked that they did.
##
## They are checkable, and this is the check: strike the real ball, with the real
## `_perturb`, and integrate it to where it lands. The ball is not asked to be
## accurate — it is asked to be *as accurate as the model says*, which is a
## different question and the only one that can be wrong on its own.
##
## No match runs and no ticks advance. The rolls are drawn from `ctx.rng` like
## everything else, so a seed gives the same table on every build.
##
## Read the pairs. `said` against `rolled` on each axis is the calibration, and
## the axes are separated because a ball in the air fails on the long axis and a
## ball on the floor fails on the short one — a mean over both would have hidden
## exactly the defect this was written to find.

## How many times each row is struck. Three hundred puts the sigma of a sigma at
## about 4%, which is well inside the gaps that matter here.
const ROLLS := 300

## The distances each kind is asked over, chosen as the ball it is actually played
## at rather than as a sweep. `Passes by kind` in the diagnose is where the means
## come from: a ground pass is 11 m, a lofted ball 33 m, a cross 31 m.
const GROUND_AT := [8.0, 14.0, 22.0, 30.0]
const AIR_AT := [20.0, 30.0, 40.0]

## Where the striker stands, and where he is aiming. Along the pitch, away from
## every line, so nothing is clamped and no row is measuring the touchline.
const FROM_X := -20.0


static func run(flags: Dictionary) -> void:
	var opts := SimRunner.Options.new()
	opts.seed_value = int(flags.get("seed", 7))
	opts.minutes = 1.0
	var ctx := SimRunner.build(opts).ctx
	print("Where the ball lands against where the model said  (%d strikes a row, no match)" % ROLLS)
	print("  %-8s %6s %8s   %-15s   %-22s   %-13s" % [
		"kind", "over", "skill", "sideways sigma", "long sigma", "in tolerance"])
	print("  %-8s %6s %8s   %7s %7s   %7s %7s %6s   %6s %6s" % [
		"", "", "", "said", "rolled", "said", "rolled", "bias", "said", "rolled"])
	for d in GROUND_AT:
		_row(ctx, SimTelemetry.Touch.GROUND_PASS, d)
	for d in AIR_AT:
		_row(ctx, SimTelemetry.Touch.LOFTED_PASS, d)
	for d in AIR_AT:
		_row(ctx, SimTelemetry.Touch.CROSS, d)
	print("  `said` is what `SimTouch.execution_accuracy` hands the decision layer for that")
	print("  same ball; `rolled` is where the ball went. A gap on one axis only is the two")
	print("  models disagreeing about the physics, not the player being bad at football")


static func _row(ctx: SimContext, kind: int, distance: float) -> void:
	var player := ctx.players[_striker(ctx)]
	var skill: float = player.attrs.crossing if kind == SimTelemetry.Touch.CROSS \
		else player.attrs.passing
	var from := Vector3(FROM_X, SimConsts.BALL_RADIUS, 0.0)
	var aim := Vector3(FROM_X + distance, 0.0, 0.0)

	# Everything about the striker held still, so the row is a property of the
	# strike rule. `aim_sigma` reads his pace, his fatigue and the way he is
	# facing, and a bench that let any of those wander would be measuring them.
	player.pos = from
	player.vel = Vector3.ZERO
	player.facing = atan2(aim.z - from.z, aim.x - from.x)
	player.touch_cooldown = 0.0

	var lateral := 0.0
	var longitudinal := 0.0
	# Signed, because an RMS cannot tell a scatter from a systematic long or
	# short — and a systematic miss is a solver fault where a scatter is the
	# player's. The drive correction on the ground pass was fitted off this.
	var bias := 0.0
	var inside := 0
	var tolerance := _tolerance(kind, distance)
	var in_air := kind != SimTelemetry.Touch.GROUND_PASS
	for i in ROLLS:
		ctx.ball.pos = from
		ctx.ball.vel = Vector3.ZERO
		ctx.ball.spin = Vector3.ZERO
		ctx.ball.grounded = kind == SimTelemetry.Touch.GROUND_PASS
		player.touch_cooldown = 0.0
		_strike(ctx, player, kind, aim, distance)
		var landed := _land(ctx, kind, from, distance)
		var dz := landed.z - aim.z
		var dx := landed.x - aim.x
		lateral += dz * dz
		longitudinal += dx * dx
		bias += dx
		# The model's own criterion, not a box of the bench's choosing: a ball on
		# the floor is charged sideways only, because it runs through the receiver
		# rather than landing short of him. An instrument that scored the two kinds
		# by one rule would be arguing with the model instead of measuring it.
		if absf(dz) < tolerance and (not in_air or absf(dx) < tolerance):
			inside += 1
	lateral = sqrt(lateral / float(ROLLS))
	longitudinal = sqrt(longitudinal / float(ROLLS))
	bias /= float(ROLLS)

	# What the decision layer was told about this same ball, off the same call it
	# makes -- never off a second copy of the formula, which is the fault being
	# measured.
	var base: float = SimTouch.AIR_MODEL_AIM_BASE if in_air else SimTouch.GROUND_AIM_BASE
	var sigma := SimTouch.aim_sigma(ctx, player, skill, distance, base, aim - from)
	var said_lat := sigma * distance
	# The cross has its own long law since `LOFT_RUNON_SHARE`: the lofted pass
	# finishes at its man while the cross lands hot on its spot, and the bench
	# has to quote the claim the decision layer actually hears for each.
	var axis := SimTouch.LONG_NONE
	if kind == SimTelemetry.Touch.CROSS:
		axis = SimTouch.LONG_AIR_CROSS
	elif in_air:
		axis = SimTouch.LONG_AIR
	var said_long := SimTouch.long_sigma(player, skill, distance, axis)
	var said_in := SimTouch.execution_accuracy(
		ctx, player, skill, distance, base, tolerance, aim - from, axis)
	print("  %-8s %5.0f m %8.2f   %6.2fm %6.2fm   %6.2fm %6.2fm %+6.2fm   %5.0f%% %5.0f%%" % [
		SimTelemetry.touch_name(kind), distance, skill,
		said_lat, lateral, said_long, longitudinal, bias,
		100.0 * said_in, 100.0 * float(inside) / float(ROLLS)])


## The tolerance the decision layer prices this kind against, so `in tolerance`
## is the number that actually reaches a score rather than an arbitrary radius.
static func _tolerance(kind: int, distance: float) -> float:
	if kind == SimTelemetry.Touch.GROUND_PASS:
		return SimDecision.pass_tolerance(distance)
	return SimDecision.pass_tolerance(distance) * SimDecision.AERIAL_TOLERANCE


## The real strike, through the real entry point. A bench that reimplemented the
## perturbation would agree with itself forever.
static func _strike(ctx: SimContext, player: SimPlayer, kind: int, aim: Vector3, distance: float) -> void:
	if kind == SimTelemetry.Touch.GROUND_PASS:
		var pace := SimDecision.arrival_pace(distance, ctx.tactics(player.team))
		SimTouch.ground_pass(ctx, player, aim, pace, -1, kind)
		return
	SimTouch.lofted_pass(ctx, player, aim, SimTouch.lofted_flight(distance), -1, kind)


## Where it finishes. For a ball in the air that is where it first comes down;
## for one on the floor it is where it has decayed to the pace it was struck to
## arrive at, which is the point the pass model aims at and the point a receiver
## meets it.
static func _land(ctx: SimContext, kind: int, from: Vector3, distance: float) -> Vector3:
	var ball := ctx.ball
	var pace := SimDecision.arrival_pace(distance, ctx.tactics(SimConsts.TEAM_HOME))
	var t := 0.0
	while t < 8.0:
		var previous := ball.pos
		ball.integrate(SimConsts.FORECAST_DT, ctx.env)
		t += SimConsts.FORECAST_DT
		if kind == SimTelemetry.Touch.GROUND_PASS:
			if ball.vel.length() <= pace:
				return ball.pos
		elif ball.pos.y <= SimConsts.BALL_RADIUS + 0.01 and ball.vel.y <= 0.0:
			return previous
	return ball.pos


## Somebody ordinary to strike it: the first outfield player, whoever that is in
## the squad this seed built. His attributes are printed beside every row, so a
## row is readable without knowing which of them it was.
static func _striker(ctx: SimContext) -> int:
	for p in ctx.players:
		if not p.is_keeper and p.team == SimConsts.TEAM_HOME:
			return p.id
	return 0

