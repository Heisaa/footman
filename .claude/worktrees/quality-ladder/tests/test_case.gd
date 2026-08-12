class_name SimTestCase
extends RefCounted
## Minimal test-case base. No plugin, no dependency: the test suite has to run
## from the same headless entry point as everything else (PLAN.md §2.1).

var failures: PackedStringArray = PackedStringArray()
var checks := 0


## Override with the tests. Use the check_* helpers; they record rather than
## abort, so one broken assumption does not hide the next five.
func run() -> void:
	pass


func case_name() -> String:
	return get_script().resource_path.get_file().replace(".gd", "")


func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)


func check_near(actual: float, expected: float, tolerance: float, message: String) -> void:
	checks += 1
	if absf(actual - expected) > tolerance:
		failures.append("%s (got %.4f, expected %.4f +/- %.4f)" % [message, actual, expected, tolerance])


func check_between(actual: float, low: float, high: float, message: String) -> void:
	checks += 1
	if actual < low or actual > high:
		failures.append("%s (got %.4f, expected %.4f - %.4f)" % [message, actual, low, high])


func check_equal(actual: Variant, expected: Variant, message: String) -> void:
	checks += 1
	if actual != expected:
		failures.append("%s (got %s, expected %s)" % [message, str(actual), str(expected)])


func check_greater(actual: float, threshold: float, message: String) -> void:
	checks += 1
	if actual <= threshold:
		failures.append("%s (got %.4f, expected > %.4f)" % [message, actual, threshold])


func check_less(actual: float, threshold: float, message: String) -> void:
	checks += 1
	if actual >= threshold:
		failures.append("%s (got %.4f, expected < %.4f)" % [message, actual, threshold])


# --- Shared fixtures --------------------------------------------------------


static func dry_env() -> SimEnv:
	return SimEnv.new(false, false)


## A ball placed at rest with a given velocity and spin, plus a scratch pitch.
static func launch_ball(vel: Vector3, spin: Vector3 = Vector3.ZERO, at: Vector3 = Vector3(0.0, SimConsts.BALL_RADIUS, 0.0)) -> SimBall:
	var b := SimBall.new()
	b.reset(at)
	b.launch(vel, spin)
	return b


## Steps a ball for `seconds` and returns it.
static func advance(ball: SimBall, env: SimEnv, seconds: float) -> SimBall:
	var steps := int(round(seconds * float(SimConsts.TICK_HZ)))
	for i in steps:
		ball.integrate(SimConsts.DT, env)
	return ball


static func make_player(pace: float = 0.6, accel: float = 0.6, agility: float = 0.6) -> SimPlayer:
	var attrs := SimAttributes.new()
	attrs.pace = pace
	attrs.acceleration = accel
	attrs.agility = agility
	var p := SimPlayer.new()
	p.configure(0, SimConsts.TEAM_HOME, SimRole.CM, attrs, "Test")
	return p
