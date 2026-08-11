class_name TestGolden
extends SimTestCase
## Golden replays (PLAN.md §11): a fixed seed must produce a fixed event-log
## hash within a build.
##
## Unlike the determinism test, which only compares a run against itself, this
## catches a change in *behaviour*. It is expected to fail whenever the engine
## is deliberately retuned; re-baseline with
##
##   godot --headless --script res://tests/record_golden.gd
##
## and say so in the commit. A golden test that is quietly re-recorded on every
## failure is worth nothing, so the recording is a separate, explicit action.

const GOLDEN_PATH := "res://tests/golden.json"
const SEEDS := [101, 202, 303]
const MINUTES := 8.0


func run() -> void:
	var golden := load_golden()
	if golden.is_empty():
		# Nothing recorded yet. Say so rather than inventing a pass.
		failures.append("no golden baseline; run tests/record_golden.gd to create one")
		checks += 1
		return
	for seed_value in SEEDS:
		var key := str(seed_value)
		var digest := digest_for(seed_value)
		checks += 1
		if not golden.has(key):
			failures.append("seed %d has no recorded baseline" % seed_value)
		elif golden[key] != digest:
			failures.append("seed %d diverged from the baseline (expected %s, got %s) -- re-record if this was intentional" % [
				seed_value, str(golden[key]).substr(0, 12), digest.substr(0, 12),
			])


static func digest_for(seed_value: int) -> String:
	var opts := SimRunner.Options.new()
	opts.seed_value = seed_value
	opts.minutes = MINUTES
	var m := SimRunner.build(opts)
	m.run_to_completion()
	return m.ctx.telemetry.digest()


static func load_golden() -> Dictionary:
	if not FileAccess.file_exists(GOLDEN_PATH):
		return {}
	var file := FileAccess.open(GOLDEN_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
