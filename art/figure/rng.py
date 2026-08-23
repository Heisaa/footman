"""Port of `sim/core/sim_rng.gd`. Same stream, same seeds, same players.

Bit-identical on purpose: seed 41 in Blender has to be seed 41 in the game, or
the figure being looked at is not the figure being shipped.
"""

MASK = 0xFFFFFFFF
INV_2_32 = 1.0 / 4294967296.0
TAU = 6.283185307179586


def _mix(v: int) -> int:
    h = v & MASK
    h = (h ^ (h >> 16)) & MASK
    h = (h * 0x7FEB352D) & MASK
    h = (h ^ (h >> 15)) & MASK
    h = (h * 0x846CA68B) & MASK
    h = (h ^ (h >> 16)) & MASK
    return h


class SimRng:
    def __init__(self, seed_value: int = 0) -> None:
        self.set_seed(seed_value)

    def set_seed(self, seed_value: int) -> None:
        self._x = _mix(seed_value ^ 0x9E3779B9)
        self._y = _mix(self._x ^ 0x85EBCA6B)
        self._z = _mix(self._y ^ 0xC2B2AE35)
        self._w = _mix(self._z ^ 0x27D4EB2F)
        if self._x == 0 and self._y == 0 and self._z == 0 and self._w == 0:
            self._x = 0x2545F491
        for _ in range(8):
            self.next_u32()

    def next_u32(self) -> int:
        t = (self._x ^ ((self._x << 11) & MASK)) & MASK
        self._x = self._y
        self._y = self._z
        self._z = self._w
        self._w = ((self._w ^ (self._w >> 19)) ^ (t ^ (t >> 8))) & MASK
        return self._w

    def unit_float(self) -> float:
        return float(self.next_u32()) * INV_2_32

    def range_float(self, a: float, b: float) -> float:
        return a + (b - a) * self.unit_float()

    def range_int(self, a: int, b: int) -> int:
        if b <= a:
            return a
        return a + int(self.next_u32() % (b - a + 1))

    def chance(self, p: float) -> bool:
        return self.unit_float() < p


def lerp(a: float, b: float, t: float) -> float:
    return a + (b - a) * t


def clamp(v: float, lo: float, hi: float) -> float:
    return lo if v < lo else (hi if v > hi else v)
