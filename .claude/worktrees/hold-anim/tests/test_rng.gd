class_name TestRng
extends SimTestCase
## The determinism guarantee starts here: every draw in the simulation comes
## from one of these, and two runs of the same seed must produce the same
## stream (PLAN.md §2.4).


func run() -> void:
	_same_seed_same_stream()
	_different_seeds_diverge()
	_state_round_trips()
	_uniform_is_uniform()
	_gaussian_is_gaussian()
	_weighted_index_respects_weights()


func _same_seed_same_stream() -> void:
	var a := SimRng.new(12345)
	var b := SimRng.new(12345)
	var identical := true
	for i in 500:
		if a.next_u32() != b.next_u32():
			identical = false
			break
	check(identical, "same seed must produce the same stream")


func _different_seeds_diverge() -> void:
	# Adjacent seeds must not produce correlated streams: a run is seeded from a
	# small integer, and runs 1 and 2 have to feel unrelated.
	var a := SimRng.new(1)
	var b := SimRng.new(2)
	var same := 0
	for i in 200:
		if a.next_u32() == b.next_u32():
			same += 1
	check_less(float(same), 3.0, "adjacent seeds must decorrelate")


func _state_round_trips() -> void:
	var a := SimRng.new(999)
	for i in 37:
		a.gauss()
	var state := a.get_state()
	var expected := PackedFloat64Array()
	for i in 20:
		expected.append(a.gauss(3.0, 2.0))
	var b := SimRng.new(1)
	b.set_state(state)
	var matched := true
	for i in 20:
		if not is_equal_approx(b.gauss(3.0, 2.0), expected[i]):
			matched = false
			break
	check(matched, "generator state must round-trip, cached gaussian included")


func _uniform_is_uniform() -> void:
	var rng := SimRng.new(7)
	var buckets := PackedInt32Array()
	buckets.resize(10)
	var n := 40000
	var in_range := true
	for i in n:
		var v := rng.unit_float()
		if v < 0.0 or v >= 1.0:
			in_range = false
		buckets[clampi(int(v * 10.0), 0, 9)] += 1
	check(in_range, "unit_float must stay in [0, 1)")
	var expected := float(n) / 10.0
	var worst := 0.0
	for b in buckets:
		worst = maxf(worst, absf(float(b) - expected) / expected)
	check_less(worst, 0.08, "uniform draws must fill the range evenly")


func _gaussian_is_gaussian() -> void:
	var rng := SimRng.new(31)
	var n := 40000
	var total := 0.0
	var total_sq := 0.0
	for i in n:
		var v := rng.gauss(2.0, 3.0)
		total += v
		total_sq += v * v
	var mean := total / float(n)
	var variance := total_sq / float(n) - mean * mean
	check_near(mean, 2.0, 0.06, "gaussian mean")
	check_near(sqrt(variance), 3.0, 0.06, "gaussian standard deviation")


func _weighted_index_respects_weights() -> void:
	var rng := SimRng.new(5)
	var weights := PackedFloat32Array([1.0, 3.0, 0.0, 6.0])
	var counts := PackedInt32Array()
	counts.resize(4)
	var n := 20000
	for i in n:
		counts[rng.weighted_index(weights)] += 1
	check_equal(counts[2], 0, "a zero weight must never be chosen")
	check_near(float(counts[0]) / float(n), 0.1, 0.02, "weight 1 of 10")
	check_near(float(counts[1]) / float(n), 0.3, 0.02, "weight 3 of 10")
	check_near(float(counts[3]) / float(n), 0.6, 0.02, "weight 6 of 10")
	check_equal(rng.weighted_index(PackedFloat32Array([0.0, 0.0])), -1, "all-zero weights return -1")
