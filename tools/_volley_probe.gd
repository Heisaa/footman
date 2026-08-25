extends SceneTree
## Does `SimTouch.VOLLEY_FULL` ever fire: run the volley scenario and read the
## counter, which the acts table cannot -- a volley and a settled shot are the
## same SHOT row there.
##     godot --headless --script res://tools/_volley_probe.gd
##
## Measured 2026-08-25: 25 trials, 25 shots, **1 volley**. The scenario drops
## the ball onto his boot (in flight at 1.9 m, falling), it lands inside half a
## second, and the shot goes off around 0.83 s -- he lets it bounce and strikes
## off the grass, so the built act is all but never exercised even in the
## situation made for it.

func _init() -> void:
	var s := SimScenarios.by_name("volley")
	var trials := 25
	var shots := 0
	SimTouch.volleys_struck = 0
	for i in trials:
		var opts := SimRunner.Options.new()
		opts.seed_value = 4000 + i
		opts.home_quality = 0.6
		opts.away_quality = 0.6
		opts.minutes = 90.0
		opts.scenario = s
		var r := s.run(SimRunner.build(opts))
		if r.acts.size() > SimTelemetry.Touch.SHOT:
			shots += r.acts[SimTelemetry.Touch.SHOT]
	print("trials %d  shots %d  volleys_struck %d" % [trials, shots, SimTouch.volleys_struck])
	quit()
