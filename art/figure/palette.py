"""Godot's `Color` and `shared/palette.gd`, only as far as the figure needs.

`Color` components are sRGB in 0..1, exactly as Godot stores them, so every
number copied out of the GDScript means the same thing here. `linear()` is the
one place that changes, because Blender's shader sockets want linear.
"""

import colorsys

from .rng import clamp, lerp


class Color:
    __slots__ = ("r", "g", "b", "a")

    def __init__(self, r, g=None, b=None, a=1.0):
        if isinstance(r, str):
            h = r.lstrip("#")
            self.r = int(h[0:2], 16) / 255.0
            self.g = int(h[2:4], 16) / 255.0
            self.b = int(h[4:6], 16) / 255.0
            self.a = int(h[6:8], 16) / 255.0 if len(h) >= 8 else 1.0
        else:
            self.r, self.g, self.b, self.a = float(r), float(g), float(b), float(a)

    # Godot's own weights, applied to the sRGB components -- not linearised.
    def luminance(self) -> float:
        return 0.2126 * self.r + 0.7152 * self.g + 0.0722 * self.b

    @property
    def hsv(self):
        return colorsys.rgb_to_hsv(self.r, self.g, self.b)

    @property
    def h(self):
        return self.hsv[0]

    @property
    def s(self):
        return self.hsv[1]

    @property
    def v(self):
        return self.hsv[2]

    @staticmethod
    def from_hsv(h, s, v, a=1.0):
        return Color(*colorsys.hsv_to_rgb(h % 1.0, s, v), a)

    def darkened(self, amount):
        k = 1.0 - amount
        return Color(self.r * k, self.g * k, self.b * k, self.a)

    def lightened(self, amount):
        return Color(
            self.r + (1.0 - self.r) * amount,
            self.g + (1.0 - self.g) * amount,
            self.b + (1.0 - self.b) * amount,
            self.a,
        )

    def lerp(self, other, t):
        return Color(
            lerp(self.r, other.r, t),
            lerp(self.g, other.g, t),
            lerp(self.b, other.b, t),
            lerp(self.a, other.a, t),
        )

    def linear(self):
        """sRGB -> linear, which is what a Blender colour socket wants."""
        return tuple(_to_linear(c) for c in (self.r, self.g, self.b)) + (self.a,)


def _to_linear(c: float) -> float:
    c = clamp(c, 0.0, 1.0)
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


INK = Color("221d26")
PAPER = Color("fdf4e3")
RED = Color("e8443c")
CORAL = Color("f4776b")
SALMON = Color("f79a86")
ORANGE = Color("f2913a")
AMBER = Color("f6c445")
LEMON = Color("f0e35b")
LIME = Color("a8cf46")
GRASS = Color("5cb15a")
PINE = Color("2f7d55")
TEAL = Color("3fb0a4")
SKY = Color("52aee0")
BLUE = Color("3b6fce")
NAVY = Color("2b3f7a")
VIOLET = Color("7b5bc4")
PLUM = Color("a8479b")
PINK = Color("ef7fb4")
BROWN = Color("8a5a3b")
SAND = Color("d9b787")
SLATE = Color("6b7a8f")
CHALK = Color("f2f2ee")

KIT_COLOURS = [RED, CORAL, ORANGE, AMBER, LEMON, TEAL, SKY, BLUE, NAVY,
               VIOLET, PLUM, PINK, BROWN, SLATE, INK]
SHORTS_COLOURS = [CHALK, INK, NAVY, SLATE, RED, BLUE]
BACKDROPS = [SALMON, CORAL, AMBER, SKY, VIOLET, TEAL, LIME]


def contrast_for(primary: Color) -> Color:
    return INK if primary.luminance() > 0.45 else CHALK


def shorts_for(primary: Color) -> Color:
    at = abs(int(primary.h * 97.0 + primary.luminance() * 31.0))
    for step in range(len(SHORTS_COLOURS)):
        candidate = SHORTS_COLOURS[(at + step) % len(SHORTS_COLOURS)]
        if abs(candidate.luminance() - primary.luminance()) >= 0.14:
            return candidate
    return contrast_for(primary)


def kit_for(primary: Color):
    """Shirt, trim, shorts -- `SimAppearance.kit_for`."""
    return [primary, contrast_for(primary), shorts_for(primary)]
