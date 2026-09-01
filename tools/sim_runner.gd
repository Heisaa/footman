class_name SimRunner
extends RefCounted
## Helpers for building and running matches outside the presentation layer.
##
## Used by the headless entry point, the test suite and the tuning tools. It is
## the only place that knows how to assemble a match from a handful of knobs.

class Options extends RefCounted:
	var seed_value := 1
	## A world seed, or -1 for `SimSquadGen` squads. With one, the two sides
	## are clubs of the league `WorldGen.league` draws at that seed, and the
	## qualities above are ignored: the clubs have their own men.
	var world_seed := -1
	var home_club := 0
	var away_club := 1
	var home_quality := 0.6
	var away_quality := 0.6
	var home_formation := "4-3-3"
	var away_formation := "4-3-3"
	var home_tactics: SimTactics = null
	var away_tactics: SimTactics = null
	var minutes := 90.0
	## Match-clock seconds per simulated second. See SimMatchConfig.clock_rate.
	## 10.0 is the standard nine-minute match; 1 is the measurement affordance.
	var clock_rate := 10.0
	## Shrinks a regulation pitch, eleven a side kept. See SimPitch.scaled.
	var pitch_scale := 1.0
	## Forces the compressed match's scoring fit on at any clock rate, for
	## measurement. See SimMatchConfig.urgency_override.
	var urgency := -1.0
	var trace := false
	var events := true
	var small_sided := false
	var wet := false
	var fidelity := SimMatchConfig.Fidelity.FULL
	## A situation to start from instead of a kick-off. See `SimScenario`.
	##
	## On `Options` rather than on the bench that runs it, because the 3D view
	## builds through `SimRunner.build` too -- so the scenario the owner watches
	## and the scenario the table counts are assembled by the same code, which is
	## the only thing that makes the two comparable.
	var scenario: SimScenario = null


## The pitch a seed is played on.
##
## The phase of the undulation comes off the seed, so each match is played on its
## own set of bumps and a replay of a seed is played on the same ones. Derived
## arithmetically rather than drawn, because the trajectory forecast
## re-integrates the ball over this surface and may not touch the rng.
##
## Public because the 3D view has to build its ground mesh from the same surface
## the ball is integrated over — a pitch and a ball on two different surfaces is
## a ball buried in the grass — and it builds the world before it starts a match.
static func env_for(seed_value: int, wet: bool = false) -> SimEnv:
	return SimEnv.new(wet, false, float(seed_value % 997) * 0.0063)


## The pitch a set of options is played on.
##
## Public for the same reason `env_for` is: the 3D view paints its lines, plants
## its goals and seats its crowd before it has a match to ask, and a stadium
## drawn to one set of dimensions around a match played on another is eleven
## players running through the paint. One decision, made in one place, read by
## both.
static func pitch_for(opts: Options) -> SimPitch:
	if opts.small_sided:
		return SimPitch.small_sided()
	return SimPitch.scaled(opts.pitch_scale)


static func build(opts: Options) -> SimMatch:
	var rng := SimRng.new(opts.seed_value ^ 0x5EED)
	var config := SimMatchConfig.new()
	config.seed_value = opts.seed_value
	config.minutes = opts.minutes
	config.clock_rate = opts.clock_rate
	config.urgency_override = opts.urgency
	config.trace_enabled = opts.trace
	config.events_enabled = opts.events
	config.env = env_for(opts.seed_value, opts.wet)
	config.fidelity = opts.fidelity
	config.pitch = pitch_for(opts)

	var home_shape := SimFormation.by_name("6aside" if opts.small_sided else opts.home_formation)
	var away_shape := SimFormation.by_name("6aside" if opts.small_sided else opts.away_formation)
	if opts.world_seed >= 0 and not opts.small_sided:
		var clubs := world_clubs(opts)
		config.home = clubs[0].to_sim_team(SimConsts.TEAM_HOME)
		config.away = clubs[1].to_sim_team(SimConsts.TEAM_AWAY)
		if opts.home_formation != "4-3-3":
			config.home.formation = home_shape
		if opts.away_formation != "4-3-3":
			config.away.formation = away_shape
	else:
		config.home = SimSquadGen.make_team(rng, SimConsts.TEAM_HOME, opts.home_quality, home_shape, 0 if opts.small_sided else 7)
		config.away = SimSquadGen.make_team(rng, SimConsts.TEAM_AWAY, opts.away_quality, away_shape, 0 if opts.small_sided else 7)
	if opts.home_tactics != null:
		config.home.tactics = opts.home_tactics
	if opts.away_tactics != null:
		config.away.tactics = opts.away_tactics

	var m := SimMatch.new()
	m.setup(config)
	if opts.scenario != null and opts.scenario.place.is_valid():
		opts.scenario.place.call(opts.scenario, m.ctx)
	return m


## The two clubs a world seed puts on the pitch, home then away. The league is
## the one `parade --world` shows, so a man seen there is the man who plays.
static func world_clubs(opts: Options) -> Array[WorldClub]:
	var league := WorldGen.league(SimRng.new(opts.world_seed), WorldSeason.DEFAULT_CLUBS)
	var home := league[clampi(opts.home_club, 0, league.size() - 1)]
	var away := league[clampi(opts.away_club, 0, league.size() - 1)]
	return [home, away]


static func run_one(opts: Options) -> SimMatchStats:
	var m := build(opts)
	m.run_to_completion()
	return SimMatchStats.collect(m)


## Runs `count` matches from consecutive seeds and returns the collected stats.
static func run_batch(base: Options, count: int, progress_every: int = 0) -> Array[SimMatchStats]:
	var out: Array[SimMatchStats] = []
	for i in count:
		var opts := _clone(base)
		opts.seed_value = base.seed_value + i
		out.append(run_one(opts))
		if progress_every > 0 and (i + 1) % progress_every == 0:
			print("  ... %d/%d" % [i + 1, count])
	return out


static func _clone(o: Options) -> Options:
	var c := Options.new()
	c.seed_value = o.seed_value
	c.world_seed = o.world_seed
	c.home_club = o.home_club
	c.away_club = o.away_club
	c.home_quality = o.home_quality
	c.away_quality = o.away_quality
	c.home_formation = o.home_formation
	c.away_formation = o.away_formation
	c.home_tactics = o.home_tactics.clone() if o.home_tactics != null else null
	c.away_tactics = o.away_tactics.clone() if o.away_tactics != null else null
	c.minutes = o.minutes
	c.clock_rate = o.clock_rate
	c.urgency = o.urgency
	c.pitch_scale = o.pitch_scale
	c.trace = o.trace
	c.events = o.events
	c.small_sided = o.small_sided
	c.wet = o.wet
	c.fidelity = o.fidelity
	c.scenario = o.scenario
	return c
