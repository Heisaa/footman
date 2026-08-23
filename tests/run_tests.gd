extends SceneTree
## The test suite, run through the headless entry point:
##
##   godot --headless --script res://tests/run_tests.gd
##   godot --headless --script res://tests/run_tests.gd -- --only TestBall
##   godot --headless --script res://tests/run_tests.gd -- --bands
##
## PLAN.md §11 asks for three suites: golden replays, the statistical bands, and
## determinism. All three live here; the statistical bands are a slow suite and
## are only run with `--bands`, because they simulate matches by the dozen.
##
## `--bands` was documented here and never implemented, so every statistical
## check ran on every pass. `SimTestCase.bands` is the flag, and a case asks it
## before simulating a sample rather than a match: `test_tactics` alone was 112
## match-minutes, more than the whole of the rest of the suite.
##
## **What the suite is for** (CLAUDE.md, "Verification is proportional to the
## change"): it is the check that has to be cheap enough to run on any change.
## Breadth across seeds is what `smoke` and `gate` are for, and a rate measured
## over many matches is what `accept` is for. Nothing here should simulate a
## match longer than the shortest one that can fail.

const CASES := [
	"res://tests/test_rng.gd",
	"res://tests/test_clock.gd",
	"res://tests/test_ball.gd",
	"res://tests/test_distances.gd",
	"res://tests/test_locomotion.gd",
	"res://tests/test_value_field.gd",
	"res://tests/test_touch.gd",
	"res://tests/test_match.gd",
	"res://tests/test_determinism.gd",
	"res://tests/test_golden.gd",
	"res://tests/test_tactics.gd",
	"res://tests/test_patterns.gd",
	"res://tests/test_world.gd",
]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var only := ""
	for i in args.size():
		if args[i] == "--only" and i + 1 < args.size():
			only = args[i + 1]
		if args[i] == "--bands":
			SimTestCase.bands = true

	var total_checks := 0
	var total_failures := 0
	var failed_cases := 0
	var started := Time.get_ticks_msec()

	for path in CASES:
		var script: Script = load(path)
		if script == null:
			printerr("could not load %s" % path)
			total_failures += 1
			continue
		var case: SimTestCase = script.new()
		var name: String = str(path).get_file().replace(".gd", "")
		# Match "TestBall", "test_ball" or "ball" alike.
		if only != "" and not name.to_lower().replace("_", "").contains(only.to_lower().replace("_", "")):
			continue
		var case_started := Time.get_ticks_msec()
		case.run()
		var elapsed := Time.get_ticks_msec() - case_started
		total_checks += case.checks
		total_failures += case.failures.size()
		if case.failures.is_empty():
			print("  ok   %-22s %3d checks  %5d ms" % [name, case.checks, elapsed])
		else:
			failed_cases += 1
			print("  FAIL %-22s %3d checks  %5d ms" % [name, case.checks, elapsed])
			for f in case.failures:
				print("         - %s" % f)

	var elapsed := Time.get_ticks_msec() - started
	print("\n%d checks, %d failures, %d failing cases, %d ms" % [total_checks, total_failures, failed_cases, elapsed])
	if not SimTestCase.bands:
		print("(statistical checks skipped; --bands runs them and takes minutes)")
	if total_failures == 0:
		print("PASS")
		quit(0)
	else:
		print("FAIL")
		quit(1)
