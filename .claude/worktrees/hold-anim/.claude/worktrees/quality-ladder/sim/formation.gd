class_name SimFormation
extends RefCounted
## Formation shape: a role and a home position per slot.
##
## Home positions are given in a canonical frame for a team attacking +X on a
## regulation pitch. SimPitch scales and orients them, so the same formation
## works on a small-sided pitch and on either end.

var display_name := "4-3-3"
## Role per slot, in fixed slot order.
var roles := PackedInt32Array()
## Canonical home position per slot.
var homes := PackedVector3Array()


func size() -> int:
	return roles.size()


func add(role: int, x: float, z: float) -> void:
	roles.append(role)
	homes.append(Vector3(x, 0.0, z))


## Home position for a slot on a given pitch, for the given team's direction.
func home_for(slot: int, pitch: SimPitch, team: int) -> Vector3:
	return pitch.orient(team, pitch.scale_point(homes[slot]))


## Average X of the outfield slots. Used as the shape's reference depth.
func mean_depth() -> float:
	var total := 0.0
	var n := 0
	for i in roles.size():
		if roles[i] == SimRole.GK:
			continue
		total += homes[i].x
		n += 1
	return total / maxf(float(n), 1.0)


static func by_name(fname: String) -> SimFormation:
	match fname:
		"4-4-2":
			return four_four_two()
		"4-2-3-1":
			return four_two_three_one()
		"5-3-2":
			return five_three_two()
		"6aside":
			return six_a_side()
		_:
			return four_three_three()


static func all_names() -> PackedStringArray:
	return PackedStringArray(["4-3-3", "4-4-2", "4-2-3-1", "5-3-2"])


static func four_three_three() -> SimFormation:
	var f := SimFormation.new()
	f.display_name = "4-3-3"
	f.add(SimRole.GK, -48.0, 0.0)
	f.add(SimRole.FB, -30.0, -23.0)
	f.add(SimRole.CB, -34.0, -8.0)
	f.add(SimRole.CB, -34.0, 8.0)
	f.add(SimRole.FB, -30.0, 23.0)
	f.add(SimRole.DM, -19.0, 0.0)
	f.add(SimRole.CM, -7.0, -12.0)
	f.add(SimRole.CM, -7.0, 12.0)
	f.add(SimRole.WIDE, 10.0, -25.0)
	f.add(SimRole.ST, 17.0, 0.0)
	f.add(SimRole.WIDE, 10.0, 25.0)
	return f


static func four_four_two() -> SimFormation:
	var f := SimFormation.new()
	f.display_name = "4-4-2"
	f.add(SimRole.GK, -48.0, 0.0)
	f.add(SimRole.FB, -29.0, -23.0)
	f.add(SimRole.CB, -33.0, -8.0)
	f.add(SimRole.CB, -33.0, 8.0)
	f.add(SimRole.FB, -29.0, 23.0)
	f.add(SimRole.WIDE, -8.0, -24.0)
	f.add(SimRole.CM, -12.0, -7.0)
	f.add(SimRole.CM, -12.0, 7.0)
	f.add(SimRole.WIDE, -8.0, 24.0)
	f.add(SimRole.ST, 12.0, -6.0)
	f.add(SimRole.ST, 12.0, 6.0)
	return f


static func four_two_three_one() -> SimFormation:
	var f := SimFormation.new()
	f.display_name = "4-2-3-1"
	f.add(SimRole.GK, -48.0, 0.0)
	f.add(SimRole.FB, -30.0, -23.0)
	f.add(SimRole.CB, -34.0, -8.0)
	f.add(SimRole.CB, -34.0, 8.0)
	f.add(SimRole.FB, -30.0, 23.0)
	f.add(SimRole.DM, -20.0, -6.0)
	f.add(SimRole.DM, -20.0, 6.0)
	f.add(SimRole.WIDE, 2.0, -24.0)
	f.add(SimRole.AM, 0.0, 0.0)
	f.add(SimRole.WIDE, 2.0, 24.0)
	f.add(SimRole.ST, 16.0, 0.0)
	return f


static func five_three_two() -> SimFormation:
	var f := SimFormation.new()
	f.display_name = "5-3-2"
	f.add(SimRole.GK, -48.0, 0.0)
	f.add(SimRole.FB, -28.0, -26.0)
	f.add(SimRole.CB, -36.0, -13.0)
	f.add(SimRole.CB, -38.0, 0.0)
	f.add(SimRole.CB, -36.0, 13.0)
	f.add(SimRole.FB, -28.0, 26.0)
	f.add(SimRole.CM, -16.0, -11.0)
	f.add(SimRole.DM, -18.0, 0.0)
	f.add(SimRole.CM, -16.0, 11.0)
	f.add(SimRole.ST, 10.0, -7.0)
	f.add(SimRole.ST, 10.0, 7.0)
	return f


## Six-a-side prototype shape (PLAN.md §12). Canonical coordinates are still
## given for a regulation pitch and scaled down by SimPitch.small_sided().
static func six_a_side() -> SimFormation:
	var f := SimFormation.new()
	f.display_name = "6-a-side"
	f.add(SimRole.GK, -46.0, 0.0)
	f.add(SimRole.CB, -30.0, -14.0)
	f.add(SimRole.CB, -30.0, 14.0)
	f.add(SimRole.CM, -8.0, 0.0)
	f.add(SimRole.WIDE, 8.0, -20.0)
	f.add(SimRole.ST, 14.0, 10.0)
	return f
