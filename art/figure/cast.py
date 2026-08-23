"""Who to build: four figures taken straight off the references, and a seed.

The presets are there so a change can be judged against the picture it came
from. The seeded draw is there because the game needs five hundred players and
cannot store five hundred wardrobes -- one integer has to be enough.
"""

from .body import Look
from .palette import Color
from .rng import SimRng, clamp, lerp

# --- The body the record packed into the seed --------------------------------
#
# `world/look.gd` writes a man's body type, height and build into the low bits
# of his `appearance_seed`, because `SimPlayer` carries none of the three and
# the seed is the only thing about his looks that reaches a match. A render is
# only the man the game will show if it reads them back instead of drawing its
# own -- a record saying 2.04 m used to arrive here and get an ordinary man.
#
# These masks are `WorldLook`'s and have to stay its. The tag is a byte and not
# a flag bit: a single bit is set in half of all the seeds that were never
# packed, so half of them would have had a body read out of noise.

TYPE_SHIFT, TYPE_MASK = 0, 0x7
HEIGHT_SHIFT, HEIGHT_MASK = 3, 0x1F
BUILD_SHIFT, BUILD_MASK = 8, 0x7
TAG_SHIFT, TAG_MASK, TAG = 11, 0xFF, 0xA7
HEIGHT_MIN, HEIGHT_MAX = 1.56, 2.04

TYPE_NAMES = ["standard", "giant", "sprite", "heavy", "lean"]


def unpack_body(seed_value: int):
    """(body type, height, build), or None for a seed that carries no body.

    Every seed written before the identity layer landed, and every one
    `SimSquadGen` draws, carries none -- and the draw in `from_seed` stands.
    """
    if (seed_value >> TAG_SHIFT) & TAG_MASK != TAG:
        return None
    height = lerp(HEIGHT_MIN, HEIGHT_MAX,
                  ((seed_value >> HEIGHT_SHIFT) & HEIGHT_MASK) / HEIGHT_MASK)
    build = ((seed_value >> BUILD_SHIFT) & BUILD_MASK) / BUILD_MASK
    return (seed_value >> TYPE_SHIFT) & TYPE_MASK, height, build


def type_name(body_type: int) -> str:
    return TYPE_NAMES[max(0, min(body_type, len(TYPE_NAMES) - 1))]

SKIN_TONES = [
    Color("f6dcc4"), Color("f2cfae"), Color("e8bd95"), Color("d9a273"),
    Color("c1885a"), Color("a36c42"), Color("835434"), Color("643f26"),
]

HAIR_COLOURS = [
    Color("1b1719"), Color("2a2018"), Color("4a2f1e"), Color("6b4423"),
    Color("8a5a2b"), Color("b07a3c"), Color("d2ad6f"),
    Color("b5561f"), Color("7d7d80"), Color("c9c6bf"),
]

KITS = {
    "red": (Color("c8202b"), Color("f4f2ee"), Color("f4f2ee"), Color("c8202b")),
    "blue": (Color("2f5bb7"), Color("f4f2ee"), Color("f4f2ee"), Color("f4f2ee")),
    "navy": (Color("f4f2ee"), Color("1f2f5e"), Color("1f2f5e"), Color("f4f2ee")),
    "green": (Color("1e6b3a"), Color("f4f2ee"), Color("1e6b3a"), Color("1e6b3a")),
    "royal": (Color("1d4fd0"), Color("f4f2ee"), Color("f4f2ee"), Color("1d4fd0")),
    "amber": (Color("f0a52c"), Color("22242c"), Color("22242c"), Color("f0a52c")),
}

# The four references, in order.
PRESETS = {
    "moustache": dict(
        kit="red", hair_style="cap", hair_colour=HAIR_COLOURS[2], moustache=True,
        mouth="none", skin=SKIN_TONES[1], brow_lift=0.02, shirt_number=4),
    "perm": dict(
        kit="blue", hair_style="perm", hair_colour=HAIR_COLOURS[2], mouth="smile",
        skin=SKIN_TONES[1], shirt_number=9),
    "mop": dict(
        kit="royal", hair_style="mop", hair_colour=HAIR_COLOURS[1], mouth="line",
        skin=SKIN_TONES[3], nose=0.026, eye_gap=0.062, shirt_number=8),
    "keeper": dict(
        kit="green", hair_style="crop", hair_colour=HAIR_COLOURS[3], mouth="line",
        skin=SKIN_TONES[0], sleeves_long=True, shirt_number=1),
}

ORDER = ["moustache", "perm", "mop", "keeper"]


def preset(name: str, height: float = 1.80) -> Look:
    spec = dict(PRESETS[name])
    shirt, trim, shorts, sock = KITS[spec.pop("kit")]
    return Look(height=height, shirt_colour=shirt, trim_colour=trim,
                shorts_colour=shorts, sock_colour=sock, **spec)


def from_seed(seed_value: int) -> Look:
    """One integer, one player. The same seed is the same man every time."""
    rng = SimRng(seed_value)
    # Height clusters in the middle of a squad list and occasionally draws a
    # giant or a small one -- an eleven of identically sized men is off-register
    # even when every number in it is plausible.
    if rng.chance(0.14):
        height = lerp(1.58, 1.70, rng.unit_float()) if rng.chance(0.5) \
            else lerp(1.88, 2.02, rng.unit_float())
    else:
        height = lerp(1.70, 1.88, (rng.unit_float() + rng.unit_float()) * 0.5)
    build = clamp((rng.unit_float() + rng.unit_float()) * 0.5
                  + (height - 1.79) * 0.9, 0.0, 1.0)
    # The record wins where it has an opinion. The draws above still run, so a
    # packed and an unpacked seed take the same path and everything below --
    # skin, hair, face, kit -- comes off the same stream either way.
    body_type = 0
    packed = unpack_body(seed_value)
    if packed is not None:
        body_type, height, build = packed

    skin = SKIN_TONES[rng.range_int(0, len(SKIN_TONES) - 1)]
    hair = HAIR_COLOURS[rng.range_int(0, len(HAIR_COLOURS) - 1)]
    # Hair has to separate from the face or the head is one shape and the cut is
    # only a silhouette.
    if abs(hair.luminance() - skin.luminance()) < 0.14:
        hair = hair.darkened(0.45) if hair.luminance() <= skin.luminance() \
            else hair.lightened(0.4)

    kit_name = list(KITS)[rng.range_int(0, len(KITS) - 1)]
    shirt, trim, shorts, sock = KITS[kit_name]
    styles = ["cap", "cap", "crop", "perm", "mop", "bald"]

    return Look(
        height=height,
        build=build,
        body_type=body_type,
        head_w=lerp(0.158, 0.174, rng.unit_float()),
        head_h=lerp(0.155, 0.172, rng.unit_float()),
        head_d=lerp(0.142, 0.158, rng.unit_float()),
        skin=skin,
        hair_colour=hair,
        hair_style=styles[rng.range_int(0, len(styles) - 1)],
        moustache=rng.chance(0.22),
        mouth=("smile" if rng.chance(0.35) else "line"),
        brow_lift=lerp(-0.03, 0.05, rng.unit_float()),
        brow_tilt=lerp(-0.05, 0.06, rng.unit_float()),
        eye_gap=lerp(0.062, 0.082, rng.unit_float()),
        nose=lerp(0.024, 0.036, rng.unit_float()),
        shirt_colour=shirt, trim_colour=trim, shorts_colour=shorts,
        sock_colour=sock,
        sleeves_long=rng.chance(0.2),
        sock_hoops=rng.range_int(1, 3),
        shirt_number=rng.range_int(2, 11),
    )


def describe(look: Look) -> str:
    return (f"{type_name(look.body_type)} {look.height:.2f}m "
            f"build {look.build:.2f} head "
            f"{look.head_w:.3f}x{look.head_h:.3f} {look.hair_style}"
            f"{' tache' if look.moustache else ''} {look.mouth}")
