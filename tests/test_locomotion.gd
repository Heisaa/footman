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
	_the_race_predictor_is_the_body()
	_braking_takes_room()
	_a_look_survives_the_run()
	_a_sprint_slaves_the_body()
	_a_side_on_start_costs_the_hips()
	_slaving_is_latched()


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


func _the_race_predictor_is_the_body() -> void:
	# Every race in the engine is settled by `time_to_arrive`, so the time it
	# quotes has to be the time the legs take: a standing start, a running
	# start, and a start at pace, over short and long ground.
	for start in [0.0, 3.0, 7.0]:
		for distance in [4.0, 12.0, 30.0]:
			var p := make_player(0.6, 0.6)
			p.pos = Vector3.ZERO
			p.vel = Vector3(start, 0.0, 0.0)
			p.facing = 0.0
			var said := SimValueField.time_to_arrive(p, Vector3(distance, 0.0, 0.0))
			var t := 0.0
			while p.pos.x < distance and t < 10.0:
				p.desired_vel = Vector3(30.0, 0.0, 0.0)
				p.locomote(SimConsts.DT)
				t += SimConsts.DT
			check_near(said, t, 0.05, "time_to_arrive must be the legs' own time, from %.0f m/s over %.0f m" % [start, distance])
			# And the inverse, read off the start he had.
			p.vel = Vector3(start, 0.0, 0.0)
			check_near(SimValueField.reach_in(p, Vector3(1, 0, 0), t), distance, 0.3,
				"reach_in must be the ground the legs cover in that time")


func _braking_takes_room() -> void:
	# A body brakes at 6-8 m/s^2 at the very most. From top speed that is
	# metres, not a stride: structural bounds, not a tuned figure.
	var p := make_player(0.9, 0.9)
	p.pos = Vector3.ZERO
	p.vel = Vector3(p.max_speed(), 0.0, 0.0)
	p.facing = 0.0
	var t := 0.0
	while p.speed() > 0.05 and t < 5.0:
		p.desired_vel = Vector3.ZERO
		p.locomote(SimConsts.DT)
		t += SimConsts.DT
	check_between(p.pos.x, 4.5, 10.0, "a stop from a sprint takes metres")
	check_between(t, 1.0, 2.5, "and over a second")


func _a_look_survives_the_run() -> void:
	# A held body: the look turns the hips while he stands, and a shuffle along
	# his old facing does not take them back. Structural: the strafe cap is the
	# one figure, and it is the constant itself.
	var p := make_player(0.6, 0.6)
	p.pos = Vector3.ZERO
	p.facing = 0.0
	p.look_target = Vector3(0.0, 0.0, 1000.0)
	for i in 30:
		p.desired_vel = Vector3.ZERO
		p.locomote(SimConsts.DT)
	check_near(angle_difference(p.facing, PI * 0.5), 0.0, 0.05, "a standing man turns his body onto the look")
	for i in 120:
		p.desired_vel = Vector3(3.0, 0.0, 0.0)
		p.locomote(SimConsts.DT)
	check_near(angle_difference(p.facing, PI * 0.5), 0.0, 0.05, "a shuffle along the old facing leaves the hips on the look")
	check_greater(p.pos.x, 2.0, "and he still gets there")
	check_less(p.speed(), p.max_speed() * SimPlayer.STRAFE_SHARE + 0.01, "at no more than the strafe cap")


func _a_sprint_slaves_the_body() -> void:
	# A chase is never slowed by a look: the sprint takes the hips with it and
	# the predictor's time stands.
	var p := make_player(0.6, 0.6)
	p.pos = Vector3.ZERO
	p.facing = PI * 0.5
	p.look_target = Vector3(0.0, 0.0, 1000.0)
	for i in 30:
		p.desired_vel = Vector3.ZERO
		p.locomote(SimConsts.DT)
	for i in SimConsts.TICK_HZ:
		p.desired_vel = Vector3(20.0, 0.0, 0.0)
		p.locomote(SimConsts.DT)
	check_near(angle_difference(p.facing, 0.0), 0.0, 0.05, "a sprint slaves the body to the run within a second")
	for i in 240:
		p.desired_vel = Vector3(20.0, 0.0, 0.0)
		p.locomote(SimConsts.DT)
	check_near(p.speed(), p.max_speed(), 0.05, "and reaches top speed")
	# The predictor's case again, with a look set the whole way.
	for distance in [4.0, 12.0, 30.0]:
		var q := make_player(0.6, 0.6)
		q.pos = Vector3.ZERO
		q.facing = 0.0
		q.look_target = Vector3(0.0, 0.0, 1000.0)
		var said := SimValueField.time_to_arrive(q, Vector3(distance, 0.0, 0.0))
		var t := 0.0
		while q.pos.x < distance and t < 10.0:
			q.desired_vel = Vector3(30.0, 0.0, 0.0)
			q.locomote(SimConsts.DT)
			t += SimConsts.DT
		check_near(said, t, 0.05, "time_to_arrive stands with a look set, over %.0f m" % distance)


func _a_side_on_start_costs_the_hips() -> void:
	# The predictor is the velocity's view; a start with the body side-on to
	# the run costs one hip turn on top of it, and no more than a stride.
	for distance in [4.0, 12.0, 30.0]:
		var p := make_player(0.6, 0.6)
		p.pos = Vector3.ZERO
		p.facing = PI * 0.5
		var said := SimValueField.time_to_arrive(p, Vector3(distance, 0.0, 0.0))
		var t := 0.0
		while p.pos.x < distance and t < 10.0:
			p.desired_vel = Vector3(30.0, 0.0, 0.0)
			p.locomote(SimConsts.DT)
			t += SimConsts.DT
		check_between(t - said, -0.05, 0.25, "a side-on start costs at most a hip turn over %.0f m" % distance)


func _slaving_is_latched() -> void:
	# A desired speed straddling the threshold must not flip the body every
	# tick: once the sprint takes the hips, the shuffle does not give them back.
	var p := make_player(0.6, 0.6)
	p.pos = Vector3.ZERO
	p.facing = 0.0
	p.look_target = Vector3(0.0, 0.0, 1000.0)
	for i in 30:
		p.desired_vel = Vector3.ZERO
		p.locomote(SimConsts.DT)
	var last := p.facing
	var last_sign := 0.0
	var flips := 0
	for i in 120:
		var share := 0.55 if i % 2 == 0 else 0.45
		p.desired_vel = Vector3(p.max_speed() * share, 0.0, 0.0)
		p.locomote(SimConsts.DT)
		var d := angle_difference(last, p.facing)
		if absf(d) > 1e-6:
			var sign := signf(d)
			if last_sign != 0.0 and sign != last_sign:
				flips += 1
			last_sign = sign
		last = p.facing
	check_less(flips, 1, "the body turns one way, never back and forth")
	check_near(angle_difference(p.facing, 0.0), 0.0, 0.05, "and ends on the run")
