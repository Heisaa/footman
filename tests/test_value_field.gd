class_name TestValueField
extends SimTestCase
## Pitch control and expected threat (PLAN.md §4.1).


func run() -> void:
	_threat_is_low_at_home_and_high_near_goal()
	_threat_is_symmetric_across_the_pitch()
	_threat_is_oriented_per_team()
	_arrival_time_accounts_for_velocity()
	_control_favours_the_nearer_side()
	_local_sampling_agrees_with_the_full_evaluation()


func _threat_is_low_at_home_and_high_near_goal() -> void:
	var v := SimValueField.new()
	var pitch := SimPitch.regulation()
	var own_third := v.xt_at(0, Vector3(-40.0, 0.0, 0.0), pitch)
	var halfway := v.xt_at(0, Vector3(0.0, 0.0, 0.0), pitch)
	var edge_of_box := v.xt_at(0, Vector3(36.0, 0.0, 0.0), pitch)
	var spot := v.xt_at(0, Vector3(41.5, 0.0, 0.0), pitch)
	check_less(own_third, 0.01, "own third is worth nearly nothing")
	check_greater(halfway, own_third, "value rises up the pitch")
	check_greater(edge_of_box, halfway * 2.0, "value rises steeply approaching the box")
	check_greater(spot, edge_of_box, "and peaks around the penalty spot")
	check_between(spot, 0.15, 0.5, "peak threat is a plausible goal probability")


func _threat_is_symmetric_across_the_pitch() -> void:
	var v := SimValueField.new()
	var pitch := SimPitch.regulation()
	for x in [-30.0, 0.0, 30.0, 45.0]:
		for z in [8.0, 20.0, 30.0]:
			var left := v.xt_at(0, Vector3(x, 0.0, -z), pitch)
			var right := v.xt_at(0, Vector3(x, 0.0, z), pitch)
			check_near(left, right, 0.005, "threat must be symmetric about the centre line")


func _threat_is_oriented_per_team() -> void:
	var v := SimValueField.new()
	var pitch := SimPitch.regulation()
	var point := Vector3(45.0, 0.0, 0.0)
	check_greater(v.xt_at(0, point, pitch), 0.1, "the home end of the pitch is dangerous for the home side")
	check_less(v.xt_at(1, point, pitch), 0.01, "and worthless for the away side, who attack the other way")


func _arrival_time_accounts_for_velocity() -> void:
	var running := make_player()
	running.pos = Vector3.ZERO
	running.vel = Vector3(7.0, 0.0, 0.0)
	var standing := make_player()
	standing.pos = Vector3.ZERO
	standing.vel = Vector3.ZERO
	var ahead := Vector3(15.0, 0.0, 0.0)
	check_less(
		SimValueField.time_to_arrive(running, ahead),
		SimValueField.time_to_arrive(standing, ahead),
		"momentum toward a point must help"
	)
	var behind := Vector3(-15.0, 0.0, 0.0)
	check_greater(
		SimValueField.time_to_arrive(running, behind),
		SimValueField.time_to_arrive(standing, behind),
		"momentum away from a point must hurt -- a committed run cannot be undone"
	)


func _control_favours_the_nearer_side() -> void:
	var m := _small_match()
	var ctx := m.ctx
	var home := ctx.players[1]
	var away := ctx.players[ctx.team_players[1][1]]
	var point := Vector3(0.0, 0.0, 0.0)
	home.pos = Vector3(1.0, 0.0, 0.0)
	home.vel = Vector3.ZERO
	away.pos = Vector3(25.0, 0.0, 0.0)
	away.vel = Vector3.ZERO
	for p in ctx.players:
		if p.id != home.id and p.id != away.id:
			p.pos = Vector3(0.0, 0.0, 60.0)
	var control := ctx.value.control_at(ctx, point, 0)
	check_greater(control, 0.9, "the side standing on the ball owns that space")
	check_less(ctx.value.control_at(ctx, point, 1), 0.1, "and the other side does not")


func _local_sampling_agrees_with_the_full_evaluation() -> void:
	# begin_local / control_at_local exist purely for speed. If they disagree
	# with the full evaluation, the shortcut is changing behaviour.
	var m := _small_match()
	var ctx := m.ctx
	for i in 400:
		m.tick()
	var worst := 0.0
	for probe in [Vector3(0, 0, 0), Vector3(20, 0, -10), Vector3(-30, 0, 15), Vector3(44, 0, 4)]:
		ctx.value.begin_local(ctx, probe, 30.0)
		var local := ctx.value.control_at_local(ctx, probe, 0)
		var full := ctx.value.control_at(ctx, probe, 0)
		worst = maxf(worst, absf(local - full))
	check_less(worst, 0.05, "local sampling must match the full evaluation")


static func _small_match() -> SimMatch:
	var opts := SimRunner.Options.new()
	opts.seed_value = 11
	opts.minutes = 4.0
	return SimRunner.build(opts)
