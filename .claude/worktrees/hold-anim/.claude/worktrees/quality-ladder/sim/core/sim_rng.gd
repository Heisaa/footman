class_name SimRng
extends RefCounted
## Deterministic pseudo-random generator owned by a match.
##
## The simulation must never touch Godot's global RNG (`randf`, `randi`, ...) or
## a shared `RandomNumberGenerator`: every draw comes from an instance of this
## class that the match owns and advances only inside its tick loop. See §2.4 of
## PLAN.md.
##
## Algorithm is xorshift128 over 32-bit words. Every operation is masked back to
## 32 bits so the results never depend on GDScript's 64-bit integer width, and a
## given seed therefore produces the same stream on any platform.

const MASK := 0xFFFFFFFF
const INV_2_32 := 1.0 / 4294967296.0

var _x: int
var _y: int
var _z: int
var _w: int
var _has_spare_gauss := false
var _spare_gauss := 0.0


func _init(seed_value: int = 0) -> void:
	set_seed(seed_value)


## Reseeds the stream. Nearby seeds are decorrelated by an avalanche mix, so
## seed 1 and seed 2 produce entirely unrelated matches.
func set_seed(seed_value: int) -> void:
	_x = _mix(seed_value ^ 0x9E3779B9)
	_y = _mix(_x ^ 0x85EBCA6B)
	_z = _mix(_y ^ 0xC2B2AE35)
	_w = _mix(_z ^ 0x27D4EB2F)
	if _x == 0 and _y == 0 and _z == 0 and _w == 0:
		_x = 0x2545F491
	_has_spare_gauss = false
	_spare_gauss = 0.0
	# Discard a short warm-up so the first few draws are not correlated with the
	# seed bits.
	for i in 8:
		next_u32()


## Captures the full generator state, including the cached gaussian, so a match
## can be snapshotted and resumed bit-identically.
func get_state() -> PackedInt64Array:
	var state := PackedInt64Array()
	state.resize(6)
	state[0] = _x
	state[1] = _y
	state[2] = _z
	state[3] = _w
	state[4] = 1 if _has_spare_gauss else 0
	state[5] = _spare_gauss_bits()
	return state


func set_state(state: PackedInt64Array) -> void:
	assert(state.size() == 6)
	_x = state[0]
	_y = state[1]
	_z = state[2]
	_w = state[3]
	_has_spare_gauss = state[4] != 0
	_spare_gauss = _bits_to_float(state[5])


func next_u32() -> int:
	var t := (_x ^ ((_x << 11) & MASK)) & MASK
	_x = _y
	_y = _z
	_z = _w
	_w = ((_w ^ (_w >> 19)) ^ (t ^ (t >> 8))) & MASK
	return _w


## Uniform in [0, 1).
##
## Note the names in this class deliberately avoid `randf`, `randfn` and
## `randi_range`. Those exist in @GlobalScope, and an unqualified call to one of
## them inside this class resolves to the *engine's* generator rather than to
## this one -- which silently reintroduces global randomness into the sim and
## breaks reproducibility in a way that is very hard to find.
func unit_float() -> float:
	return float(next_u32()) * INV_2_32


## Uniform in [from, to).
func range_float(from: float, to: float) -> float:
	return from + (to - from) * unit_float()


## Uniform integer in [from, to], inclusive.
func range_int(from: int, to: int) -> int:
	if to <= from:
		return from
	return from + int(next_u32() % (to - from + 1))


## Normally distributed with the given mean and standard deviation.
## Uses Box-Muller; the unused second variate is cached and is part of the
## generator state so that determinism survives a state round-trip.
func gauss(mean: float = 0.0, deviation: float = 1.0) -> float:
	if _has_spare_gauss:
		_has_spare_gauss = false
		return mean + deviation * _spare_gauss
	# A draw of exactly zero is possible, and log() cannot take it.
	var u1 := maxf(unit_float(), 1e-12)
	var u2 := unit_float()
	var r := sqrt(-2.0 * log(u1))
	var theta := TAU * u2
	_spare_gauss = r * sin(theta)
	_has_spare_gauss = true
	return mean + deviation * r * cos(theta)


## Normally distributed but clamped to +/- `max_sigma` deviations. Used wherever
## a fat tail would produce nonsense (a pass 40 degrees off target, say).
func gauss_clamped(mean: float, deviation: float, max_sigma: float = 3.0) -> float:
	var z := clampf(gauss(0.0, 1.0), -max_sigma, max_sigma)
	return mean + deviation * z


## True with probability `p`.
func chance(p: float) -> bool:
	return unit_float() < p


## Uniform direction on the unit circle in the ground plane.
func rand_ground_dir() -> Vector3:
	var a := unit_float() * TAU
	return Vector3(cos(a), 0.0, sin(a))


## Picks an index from unnormalised positive weights. Returns -1 for an empty or
## all-zero weight list.
func weighted_index(weights: PackedFloat32Array) -> int:
	var total := 0.0
	for w in weights:
		total += w
	if total <= 0.0:
		return -1
	var roll := unit_float() * total
	var acc := 0.0
	for i in weights.size():
		acc += weights[i]
		if roll < acc:
			return i
	return weights.size() - 1


static func _mix(v: int) -> int:
	var h := v & MASK
	h = (h ^ (h >> 16)) & MASK
	h = (h * 0x7FEB352D) & MASK
	h = (h ^ (h >> 15)) & MASK
	h = (h * 0x846CA68B) & MASK
	h = (h ^ (h >> 16)) & MASK
	return h


func _spare_gauss_bits() -> int:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, _spare_gauss)
	return bytes.decode_s64(0)


static func _bits_to_float(bits: int) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_s64(0, bits)
	return bytes.decode_double(0)
