class_name SimEnv
extends RefCounted
## Pitch and weather conditions. Read-only for the duration of a match.

var wet := false
var long_grass := false

var restitution := SimConsts.RESTITUTION_DRY
var roll_decel := SimConsts.ROLL_DECEL_DRY
var slide_friction := SimConsts.SLIDE_FRICTION
## Height of the undulation, metres. Long grass sits deeper and swallows the
## bumps; nothing else moves it.
var surface_amplitude := SimConsts.SURFACE_AMPLITUDE
## Height of the middle of the pitch over the touchlines, metres.
var camber := SimConsts.SURFACE_CAMBER
## Phase offsets of the three surface components. Fixed per match and never
## drawn from `ctx.rng`, so the trajectory forecast — which re-integrates the
## same code — sees exactly the surface the ball will meet.
var bump_phase := 0.0


func _init(is_wet: bool = false, is_long_grass: bool = false, phase: float = 0.0) -> void:
	wet = is_wet
	long_grass = is_long_grass
	bump_phase = phase
	restitution = SimConsts.RESTITUTION_WET if wet else SimConsts.RESTITUTION_DRY
	# Grass length sets the rolling resistance and wetness scales it. The two
	# were sharing one branch and one constant, which made a wet pitch slow the
	# ball down; a greasy surface makes it run on faster, and only the grass
	# kills it.
	roll_decel = SimConsts.ROLL_DECEL_LONG_GRASS if long_grass else SimConsts.ROLL_DECEL_DRY
	if wet:
		roll_decel *= SimConsts.ROLL_DECEL_WET_FACTOR
	slide_friction = SimConsts.SLIDE_FRICTION * (0.85 if wet else 1.0)
	surface_amplitude = SimConsts.SURFACE_AMPLITUDE * (0.7 if long_grass else 1.0)


func duplicate_env() -> SimEnv:
	return SimEnv.new(wet, long_grass, bump_phase)


# --- The surface ------------------------------------------------------------
#
# Three sines, sampled and differentiated analytically. Called a few times per
# tick by the ball and by every forecast step, so it stays this cheap.


## Height of the grass at a point, metres, relative to the middle of the pitch.
##
## Anchored at the middle rather than at the touchlines, because the rest of the
## simulation places a ball on the ground by setting y to the ball's radius —
## every set-piece spot does — and a camber measured upwards from the touchline
## would put the whole middle of the pitch above that. Only the slope matters to
## the ball, and the slope is the same either way.
func surface_height(x: float, z: float) -> float:
	var p := bump_phase
	# Clamped at the touchline: past it the ground is flat rather than falling
	# away for ever. A quadratic that keeps going put a ball hoofed into the
	# stand a metre underground.
	var t := clampf(z / SimConsts.HALF_WIDTH, -1.0, 1.0)
	return -camber * t * t + surface_amplitude * (
			sin(SimConsts.SURFACE_K1 * x + p) * cos(SimConsts.SURFACE_K2 * z - p) * 0.6
			+ sin(SimConsts.SURFACE_K2 * x - p * 0.5) * 0.25
			+ sin(SimConsts.SURFACE_K3 * (x * 0.6 + z * 0.8) + p * 1.7) * 0.15)


## Gradient of `surface_height`, as (dh/dx, 0, dh/dz). For small angles this is
## the tilt of the surface, so -gradient is the downhill direction and
## (-dh/dx, 1, -dh/dz) normalised is the contact normal.
func surface_slope(x: float, z: float) -> Vector3:
	var p := bump_phase
	var a := surface_amplitude
	var k1 := SimConsts.SURFACE_K1
	var k2 := SimConsts.SURFACE_K2
	var k3 := SimConsts.SURFACE_K3
	var diag := k3 * (x * 0.6 + z * 0.8) + p * 1.7
	var dx := a * (
			k1 * cos(k1 * x + p) * cos(k2 * z - p) * 0.6
			+ k2 * cos(k2 * x - p * 0.5) * 0.25
			+ k3 * 0.6 * cos(diag) * 0.15)
	var dz := a * (
			-k2 * sin(k1 * x + p) * sin(k2 * z - p) * 0.6
			+ k3 * 0.8 * cos(diag) * 0.15)
	# The camber, which falls away from the middle in z alone and stops at the
	# touchline, as its height does.
	if absf(z) < SimConsts.HALF_WIDTH:
		dz -= 2.0 * camber * z / (SimConsts.HALF_WIDTH * SimConsts.HALF_WIDTH)
	return Vector3(dx, 0.0, dz)
