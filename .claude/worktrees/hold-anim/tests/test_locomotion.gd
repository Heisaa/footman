class_name TestLocomotion
extends SimTestCase
## Player movement (PLAN.md §3.2).
##
## The speed-dependent turn rate is the load-bearing part: it is why fast
## players overrun the ball and why a change of direction beats a quicker
## opponent. If these tests go, the sim looks like air hockey.


func run() -> void:
	_reaches_top_speed()
	_turn_rate_falls_off_with_speed()
	_fast_players_overrun_a_hairpin()
	_stamina_drains_with_effort()
	_fatigue_slows_a_player_down()
	_deadband_stops_fidgeting()
	_separation_pushes_apart_by_strength()


func _reaches_top_speed() -> void:
	var p := make_player(0.7)
	p.desired_vel = Vector3(20.0, 0.0, 0.0)
	for i in 600:
		p.desired_vel = Vector3(20.0, 0.0, 0.0)
		p.locomote(SimConsts.DT)
	check_near(p.speed(), p.max_speed(), 0.05, "a player should settle at their maximum speed")
	check_between(p.max_speed(), SimConsts.SPEED_MIN, SimConsts.SPEED_MAX, "top speed inside the attribute range")


func _turn_rate_falls_off_with_speed() -> void:
	var p := make_player()
	var standing := p.turn_rate(0.0)
	var sprinting := p.turn_rate(8.0)
	check_greater(standing, sprinting * 2.0, "turning at a sprint must be far harder than turning on the spot")
	check_near(sprinting, standing / (1.0 + 8.0 * SimConsts.TURN_SPEED_FALLOFF), 0.01, "turn rate follows base / (1 + v * k)")


func _fast_players_overrun_a_hairpin() -> void:
	# Run flat out, then ask for an immediate reversal. The player must carry on
	# past the turning point rather than pivoting on the spot.
	var p := make_player(0.9, 0.9)
	for i in 400:
		p.desired_vel = Vector3(20.0, 0.0, 0.0)
		p.locomote(SimConsts.DT)
	var turn_start := p.pos.x
	for i in 30:
		p.desired_vel = Vector3(-20.0, 0.0, 0.0)
		p.locomote(SimConsts.DT)
	check_greater(p.pos.x - turn_start, 0.6, "a sprinting player must overrun before reversing")
	var half_second := p.pos.x
	# A footballer at full tilt takes well over a second to be going the other
	# way. That delay is the whole reason a change of direction beats pace.
	for i in 90:
		p.desired_vel = Vector3(-20.0, 0.0, 0.0)
		p.locomote(SimConsts.DT)
	check_less(p.vel.x, 0.0, "but should be heading back within two seconds")
	check_greater(half_second, turn_start, "the overrun happens before the reversal")


func _stamina_drains_with_effort() -> void:
	var sprinter := make_player(0.6)
	var jogger := make_player(0.6)
	for i in SimConsts.TICK_HZ * 120:
		sprinter.desired_vel = Vector3(20.0, 0.0, 0.0)
		sprinter.locomote(SimConsts.DT)
		jogger.desired_vel = Vector3(2.0, 0.0, 0.0)
		jogger.locomote(SimConsts.DT)
	check_less(sprinter.stamina, jogger.stamina - 0.02, "sprinting must cost more than jogging")
	check_greater(sprinter.stamina, 0.5, "two minutes of running should not empty a footballer")


func _fatigue_slows_a_player_down() -> void:
	var p := make_player(0.6)
	var fresh := p.max_speed()
	p.stamina = 0.0
	p.refresh_caps()
	check_near(p.max_speed(), fresh * SimConsts.STAMINA_FLOOR_OUTPUT, 0.02, "an exhausted player drops to the output floor")
	p.stamina = SimConsts.STAMINA_FATIGUE_KNEE
	p.refresh_caps()
	check_near(p.max_speed(), fresh, 0.02, "above the knee there is no penalty")


func _deadband_stops_fidgeting() -> void:
	var p := make_player()
	p.pos = Vector3.ZERO
	p.steer_to(Vector3(1.0, 0.0, 0.0), INF, 2.0)
	check_equal(p.desired_vel, Vector3.ZERO, "inside the deadband a player stays put")
	p.steer_to(Vector3(6.0, 0.0, 0.0), INF, 2.0)
	check_greater(p.desired_vel.length(), 0.5, "outside it they move")


func _separation_pushes_apart_by_strength() -> void:
	var config := SimMatchConfig.new()
	config.seed_value = 3
	config.minutes = 1.0
	var rng := SimRng.new(3)
	config.home = SimSquadGen.make_team(rng, SimConsts.TEAM_HOME, 0.6, SimFormation.four_three_three(), 0)
	config.away = SimSquadGen.make_team(rng, SimConsts.TEAM_AWAY, 0.6, SimFormation.four_three_three(), 0)
	var m := SimMatch.new()
	m.setup(config)
	# Stack two players on the same spot and let the separation pass run.
	var a := m.ctx.players[1]
	var b := m.ctx.players[12]
	a.attrs.strength = 0.9
	b.attrs.strength = 0.1
	a.pos = Vector3(0.0, 0.0, 0.0)
	b.pos = Vector3(0.2, 0.0, 0.0)
	m._separate_players()
	var gap := a.dist_to(b.pos)
	check_near(gap, SimConsts.PLAYER_SEPARATION, 0.02, "overlapping players are pushed to the capsule distance")
	check_less(absf(a.pos.x), absf(b.pos.x - 0.2), "the stronger player yields less ground")
