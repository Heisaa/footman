class_name TestClock
extends SimTestCase
## The compressed clock's arithmetic (docs/INVARIANTS.md, "The match clock is
## compressed"). The standard match is nine minutes — `clock_rate` 10, the
## default everywhere — and the urgency anchor stays at 30, where the scoring
## fit was made. Two properties hold the arrangement up: every fit knob is a
## no-op at `clock_rate` 1, and the standard match runs the fit at about 0.68
## strength. No match is simulated; this is sub-millisecond.

const STANDARD_RATE := 10.0
const STANDARD_URGENCY := 0.677  # log(10) / log(30)


func run() -> void:
	_default_is_the_standard_match()
	_no_op_at_real_time()
	_standard_match_urgency()
	_anchor_at_thirty()
	_standard_scales_sit_between()
	_ticks_divide_by_rate()
	_override_forces()


func _config(rate: float) -> SimMatchConfig:
	var c := SimMatchConfig.new()
	c.clock_rate = rate
	return c


## Real-time games are never run (DECISIONS.md, sixth amendment): the sim and
## the runner both default to the standard match.
func _default_is_the_standard_match() -> void:
	check_near(SimMatchConfig.new().clock_rate, STANDARD_RATE, 0.0001,
		"the sim must default to the standard match")
	check_near(SimRunner.Options.new().clock_rate, STANDARD_RATE, 0.0001,
		"the runner must default to the standard match")


## The property the goldens, the bands and docs/STATUS.md rest on: at real time
## the fit does not exist.
func _no_op_at_real_time() -> void:
	var c := _config(1.0)
	check_near(c.urgency(), 0.0, 0.0001, "urgency must be 0 at real time")
	check_near(c.shot_appetite(), 1.0, 0.0001, "shot appetite must be a no-op at 1x")
	check_near(c.shot_sigma_scale(), 1.0, 0.0001, "shot sigma must be a no-op at 1x")
	check_near(c.keeper_save_scale(), 1.0, 0.0001, "keeper save must be a no-op at 1x")
	check_near(c.keeper_reach_scale(), 1.0, 0.0001, "keeper reach must be a no-op at 1x")
	check_near(_config(0.5).urgency(), 0.0, 0.0001, "urgency must clamp to 0 below 1x")


func _standard_match_urgency() -> void:
	check_near(_config(STANDARD_RATE).urgency(), STANDARD_URGENCY, 0.001,
		"the nine-minute match must run the fit at about 0.68")


func _anchor_at_thirty() -> void:
	var c := _config(30.0)
	check_near(c.urgency(), 1.0, 0.0001, "urgency must be 1 at the 30x anchor")
	check_near(c.shot_appetite(), SimMatchConfig.SHOT_APPETITE_URGENT, 0.0001,
		"appetite must reach its fitted value at the anchor")
	check_near(_config(60.0).urgency(), 1.0, 0.0001, "urgency must cap at 1 past the anchor")


## The partial fit: at 10x every scale sits strictly between its 1x and 30x
## values, on the fitted side of 1.
func _standard_scales_sit_between() -> void:
	var c := _config(STANDARD_RATE)
	check_between(c.shot_appetite(), 1.0, SimMatchConfig.SHOT_APPETITE_URGENT,
		"appetite at 10x must sit between the endpoints")
	check_between(c.shot_sigma_scale(), SimMatchConfig.SHOT_SIGMA_URGENT, 1.0,
		"shot sigma at 10x must sit between the endpoints")
	check_between(c.keeper_save_scale(), SimMatchConfig.KEEPER_SAVE_URGENT, 1.0,
		"keeper save at 10x must sit between the endpoints")
	check_between(c.keeper_reach_scale(), SimMatchConfig.KEEPER_REACH_URGENT, 1.0,
		"keeper reach at 10x must sit between the endpoints")


## The compression is in the clock: a ninety-minute match at 10x is nine
## minutes of ticks, and the tick itself never changes.
func _ticks_divide_by_rate() -> void:
	check_equal(_config(1.0).total_ticks(), 90 * 60 * SimConsts.TICK_HZ,
		"an uncompressed ninety is ninety minutes of ticks")
	check_equal(_config(STANDARD_RATE).total_ticks(), 9 * 60 * SimConsts.TICK_HZ,
		"the standard match is nine minutes of ticks")


func _override_forces() -> void:
	var c := _config(1.0)
	c.urgency_override = 1.0
	check_near(c.urgency(), 1.0, 0.0001, "--urgency must force the fit at any rate")
