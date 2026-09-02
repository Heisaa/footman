extends SceneTree
## One fallen man, tick by tick: what the sim says about his body while he is
## down. Written for bookmark seed1-t751, the foul at t675 on #11 (GRE).
##     godot --headless --script res://tools/_fall_probe.gd -- --seed 1 --from 660 --to 800

var seed_value := 1
var from := 660
var to := 800
var world_seed := -1

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--seed" and i + 1 < args.size():
			seed_value = int(args[i + 1])
		if args[i] == "--from" and i + 1 < args.size():
			from = int(args[i + 1])
		if args[i] == "--to" and i + 1 < args.size():
			to = int(args[i + 1])
	var opts := SimRunner.Options.new()
	opts.seed_value = seed_value
	opts.minutes = 9.0
	opts.clock_rate = 10.0
	opts.home_quality = 0.60000002384186
	opts.away_quality = 0.60000002384186
	var m := SimRunner.build(opts)
	var ctx := m.ctx
	var victim: SimPlayer = null
	var last := ""
	while not m.finished and ctx.tick_index <= to:
		m.tick()
		if victim == null:
			for p in ctx.players:
				if p.anim == SimConsts.Anim.FALL:
					victim = p
					print("fall: #%d team %d at tick %d" % [p.shirt, p.team, ctx.tick_index])
		if victim == null or ctx.tick_index < from:
			continue
		var line := "t%d pos(%.2f,%.2f) vel %.2f facing %.2f anim %s commit %d rec %d down %s" % [
			ctx.tick_index, victim.pos.x, victim.pos.z, victim.vel.length(), victim.facing,
			SimConsts.Anim.keys()[victim.anim], victim.commit_ticks, victim.recovery_ticks, victim.down]
		print(line)
		if victim.recovery_ticks == 0 and victim.commit_ticks == 0 and ctx.tick_index > from + 5:
			break
	quit()
