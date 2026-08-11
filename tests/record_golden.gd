extends SceneTree
## Re-baselines the golden replay hashes. Explicit and separate on purpose: a
## golden test that re-records itself whenever it fails is not a test.
##
##   godot --headless --script res://tests/record_golden.gd


func _initialize() -> void:
	var out := {}
	for seed_value in TestGolden.SEEDS:
		var digest := TestGolden.digest_for(seed_value)
		out[str(seed_value)] = digest
		print("  seed %d -> %s" % [seed_value, digest])
	var file := FileAccess.open(TestGolden.GOLDEN_PATH, FileAccess.WRITE)
	if file == null:
		printerr("could not write %s" % TestGolden.GOLDEN_PATH)
		quit(1)
		return
	file.store_string(JSON.stringify(out, "\t", true))
	file.close()
	print("recorded %d baselines to %s" % [out.size(), TestGolden.GOLDEN_PATH])
	quit(0)
