"""The naval roster from docs/12-unit-roster.md.

    Blender -b --python tools/navy_models.py

Ships are seen from almost directly above in an RTS, so the DECK PLANFORM and
the superstructure block layout carry the identification — hull form below the
waterline is invisible and not worth modelling.

Two hull builders:
    ship_hull()  surface vessels - raked bow, parallel midbody, transom stern
    revolve()    submarines - body of revolution (borrowed from strategic_models)

Waterline is z = 0. Everything below it is omitted: at RTS zoom you never see it,
and it doubles the triangle count for nothing.
"""
import bpy, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_models as H
from hero_models import cube, cyl, dome, profile, use, R
from air_models import plate
from strategic_models import revolve

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def ship_hull(L, B, freeboard=4.0, bow=0.30, transom=0.86, name="hull"):
    """Surface hull as a stack of planform plates, narrowing downward.

    bow     = fraction of length taken by the raked entry
    transom = stern width as a fraction of beam
    """
    out = []
    use("body")
    layers = ((0.00, 1.00), (0.45, 0.94), (0.80, 0.80), (1.00, 0.60))
    for i in range(len(layers) - 1):
        (f0, w0), (f1, w1) = layers[i], layers[i + 1]
        z0 = freeboard * (1.0 - f0)
        z1 = freeboard * (1.0 - f1)
        for frac, w in ((f0, w0),):
            hb = B / 2.0 * w
            pts = [(0.0, L * 0.50),
                   (hb * 0.55, L * (0.50 - bow * 0.55)),
                   (hb, L * (0.50 - bow)),
                   (hb, -L * 0.44),
                   (hb * transom, -L * 0.50),
                   (-hb * transom, -L * 0.50),
                   (-hb, -L * 0.44),
                   (-hb, L * (0.50 - bow)),
                   (-hb * 0.55, L * (0.50 - bow * 0.55))]
            out.append(plate(pts, max(z0 - z1, 0.15), (z0 + z1) / 2.0,
                             f"{name}{i}"))
    return out, freeboard


def deckhouse(y, l, w, h, z, taper=0.86, name="dh"):
    return profile([(y + l / 2, z), (y - l / 2, z),
                    (y - l / 2 * taper, z + h), (y + l / 2 * taper, z + h)],
                   w, name)


def mast(x, y, z, h, r=0.28):
    out = [cyl((x, y, z + h / 2), r, h, v=10)]
    for k in range(3):
        out.append(cube((x, y, z + h * (0.45 + k * 0.20)),
                        (r * 5.5 - k * 0.6, r * 1.6, 0.22)))
    return out


def vls(x, y, z, cols, rows, cell=1.05):
    """Vertical launch cells — a grid of dark squares flush with the deck.
    From above this is one of the few things that separates a modern warship
    from a merchant hull."""
    out = []
    use("deck")
    out.append(cube((x, y, z + 0.06), (cols * cell + 0.5, rows * cell + 0.5, 0.14)))
    for c in range(cols):
        for r_ in range(rows):
            out.append(cube((x - (cols - 1) * cell / 2 + c * cell,
                             y - (rows - 1) * cell / 2 + r_ * cell, z + 0.16),
                            (cell * 0.78, cell * 0.78, 0.10)))
    use("body")
    return out


def helipad(y, w, l, z):
    use("deck")
    out = [cube((0, y, z + 0.05), (w, l, 0.12))]
    out.append(cyl((0, y, z + 0.13), w * 0.30, 0.06, v=20))
    use("body")
    return out


# ── surface combatants ─────────────────────────────────────────────
def destroyer_aaw():
    """Air-defence destroyer, Arleigh Burke / Type 055 scale: 155 x 20 m.
    The layered-defence ship of docs/02 section 8.6 - big planar arrays, two
    VLS farms, helipad aft."""
    L, B = 155.0, 20.1
    p, fb = ship_hull(L, B, 5.2)
    p.append(deckhouse(L * 0.10, 46.0, 15.0, 7.0, fb, 0.90, "dh1"))
    p.append(deckhouse(L * 0.10 + 4.0, 22.0, 11.0, 4.4, fb + 7.0, 0.88, "dh2"))
    use("deck")
    for s in (-1, 1):                                  # fixed planar arrays
        p.append(cube((s * 5.6, L * 0.19, fb + 8.4), (0.5, 5.0, 4.6),
                      rot=(0, 0, R(s * 28))))
        p.append(cube((s * 5.6, L * 0.02, fb + 8.0), (0.5, 4.6, 4.2),
                      rot=(0, 0, R(-s * 28))))
    use("body")
    p += mast(0, L * 0.03, fb + 11.4, 13.0, 0.42)
    p += vls(0, L * 0.30, fb, 8, 4)                    # forward cells
    p += vls(0, -L * 0.16, fb, 8, 8)                   # aft cells
    use("gun")
    p.append(cyl((0, L * 0.385, fb + 1.5), 2.0, 2.6, v=18))          # gun mount
    p.append(cyl((0, L * 0.415, fb + 1.9), 0.30, 6.4, rot=(R(90), 0, 0), v=12))
    use("body")
    p.append(deckhouse(-L * 0.30, 26.0, 13.0, 5.0, fb, 0.92, "hangar"))
    p += helipad(-L * 0.42, 13.0, 20.0, fb)
    for s in (-1, 1):
        p.append(cyl((s * 4.2, -L * 0.02, fb + 8.6), 1.5, 7.0, v=12))  # funnels
    return p, dict(top=fb, hull_l=L, hull_w=B, turret_top=fb + 24.0,
                   gun_z=fb + 1.9, gun_y=L * 0.40)


def frigate_asw():
    """ASW frigate: smaller, quieter, and dominated by a very large helicopter
    deck and hangar - the towed array and the helo are its weapons."""
    L, B = 142.0, 19.7
    p, fb = ship_hull(L, B, 4.8)
    p.append(deckhouse(L * 0.12, 40.0, 14.0, 6.4, fb, 0.90, "dh1"))
    p.append(deckhouse(L * 0.14, 18.0, 10.0, 4.0, fb + 6.4, 0.88, "dh2"))
    p += mast(0, L * 0.05, fb + 10.4, 12.0, 0.40)
    use("deck")
    p.append(cyl((0, L * 0.20, fb + 8.0), 2.2, 2.4, v=20))            # radome
    p.append(cube((0, -L * 0.47, fb + 0.4), (8.0, 5.0, 0.8)))         # towed array
    use("body")
    p += vls(0, L * 0.30, fb, 4, 4)
    use("gun")
    p.append(cyl((0, L * 0.385, fb + 1.4), 1.8, 2.4, v=18))
    p.append(cyl((0, L * 0.412, fb + 1.7), 0.26, 5.4, rot=(R(90), 0, 0), v=12))
    use("body")
    p.append(deckhouse(-L * 0.26, 32.0, 14.0, 6.2, fb, 0.94, "hangar"))
    p += helipad(-L * 0.42, 14.0, 24.0, fb)
    return p, dict(top=fb, hull_l=L, hull_w=B, turret_top=fb + 22.0,
                   gun_z=fb + 1.7, gun_y=L * 0.40)


def cruiser():
    """Heavy surface combatant: longer than a destroyer, two gun mounts,
    the largest VLS load afloat."""
    L, B = 173.0, 16.8
    p, fb = ship_hull(L, B, 5.4)
    p.append(deckhouse(L * 0.08, 54.0, 13.5, 7.6, fb, 0.90, "dh1"))
    p.append(deckhouse(L * 0.12, 24.0, 10.0, 4.6, fb + 7.6, 0.86, "dh2"))
    use("deck")
    for s in (-1, 1):
        p.append(cube((s * 5.0, L * 0.17, fb + 9.0), (0.5, 4.8, 4.4),
                      rot=(0, 0, R(s * 26))))
    use("body")
    p += mast(0, L * 0.01, fb + 12.2, 14.0, 0.44)
    p += vls(0, L * 0.31, fb, 8, 8)
    p += vls(0, -L * 0.24, fb, 8, 8)
    use("gun")
    for y in (L * 0.39, -L * 0.38):
        p.append(cyl((0, y, fb + 1.5), 1.9, 2.5, v=18))
        p.append(cyl((0, y + (2.8 if y > 0 else -2.8), fb + 1.8), 0.28, 5.8,
                     rot=(R(90), 0, 0), v=12))
    use("body")
    p += helipad(-L * 0.44, 12.0, 16.0, fb)
    return p, dict(top=fb, hull_l=L, hull_w=B, turret_top=fb + 26.0,
                   gun_z=fb + 1.8, gun_y=L * 0.40)


def corvette():
    """Small, fast, cheap. Anti-ship missiles and not much else."""
    L, B = 90.0, 13.0
    p, fb = ship_hull(L, B, 3.8)
    p.append(deckhouse(L * 0.08, 26.0, 9.5, 5.0, fb, 0.88, "dh1"))
    p += mast(0, L * 0.02, fb + 7.6, 8.5, 0.32)
    use("deck")
    for s in (-1, 1):                                  # AShM canisters
        p.append(cube((s * 3.0, -L * 0.10, fb + 1.1), (2.0, 7.0, 2.0),
                      rot=(R(-14), 0, 0)))
    use("gun")
    p.append(cyl((0, L * 0.34, fb + 1.1), 1.4, 1.9, v=16))
    p.append(cyl((0, L * 0.375, fb + 1.4), 0.20, 4.0, rot=(R(90), 0, 0), v=10))
    use("body")
    p += helipad(-L * 0.38, 9.0, 12.0, fb)
    return p, dict(top=fb, hull_l=L, hull_w=B, turret_top=fb + 16.0,
                   gun_z=fb + 1.4, gun_y=L * 0.36)


def missile_boat():
    """Coastal denial. Taiwan and the KPA lean on these - tiny, fast, and
    carrying missiles far out of proportion to the hull."""
    L, B = 60.0, 9.2
    p, fb = ship_hull(L, B, 3.0, bow=0.34)
    p.append(deckhouse(L * 0.10, 16.0, 7.0, 4.0, fb, 0.84, "dh1"))
    p += mast(0, L * 0.04, fb + 6.0, 6.0, 0.26)
    use("deck")
    for s in (-1, 1):
        for k in range(2):
            p.append(cube((s * (2.2 + k * 1.6), -L * 0.16, fb + 1.0 + k * 0.2),
                          (1.4, 6.4, 1.5), rot=(R(-16), 0, 0)))
    use("gun")
    p.append(cyl((0, L * 0.32, fb + 0.9), 1.1, 1.5, v=14))
    use("body")
    return p, dict(top=fb, hull_l=L, hull_w=B, turret_top=fb + 12.0,
                   gun_z=fb + 0.9, gun_y=L * 0.34)


def patrol_vessel():
    """Presence and escort. Cheap eyes with a gun."""
    L, B = 55.0, 8.4
    p, fb = ship_hull(L, B, 2.9, bow=0.30)
    p.append(deckhouse(L * 0.06, 18.0, 6.6, 4.4, fb, 0.86, "dh1"))
    p += mast(0, L * 0.00, fb + 6.4, 5.6, 0.24)
    use("gun")
    p.append(cyl((0, L * 0.32, fb + 0.9), 1.0, 1.4, v=14))
    use("body")
    p += helipad(-L * 0.34, 7.0, 9.0, fb)
    return p, dict(top=fb, hull_l=L, hull_w=B, turret_top=fb + 11.0,
                   gun_z=fb + 0.9, gun_y=L * 0.34)


# ── submarines ─────────────────────────────────────────────────────
def _sub(L, B, sail_y, sail_l, sail_h, planes=True, name="sub"):
    p = []
    use("body")
    p += revolve(L, B / 2.0,
                 ((0.00, 0.28), (0.05, 0.74), (0.14, 0.97), (0.24, 1.00),
                  (0.68, 1.00), (0.84, 0.80), (0.94, 0.44), (1.00, 0.15)),
                 z=B / 2.0, v=20)
    p.append(profile([(sail_y, B * 0.97), (sail_y - sail_l, B * 0.97),
                      (sail_y - sail_l * 0.90, B * 0.97 + sail_h),
                      (sail_y - sail_l * 0.10, B * 0.97 + sail_h)],
                     B * 0.24, name + "_sail"))
    use("deck")
    for k in range(2):
        p.append(cyl((0.0, sail_y - sail_l * 0.35 - k * 1.4,
                      B * 0.97 + sail_h + 1.5), 0.22, 3.0, v=10))
    use("body")
    if planes:
        for s in (-1, 1):
            p.append(cube((s * B * 0.34, sail_y - sail_l * 0.55,
                           B * 0.97 + sail_h * 0.55),
                          (B * 0.42, sail_l * 0.42, 0.34)))
    for s in (-1, 1):
        p.append(cube((s * B * 0.46, -L * 0.43, B / 2.0),
                      (B * 0.70, L * 0.055, 0.42)))
    p.append(profile([(-L * 0.39, B / 2.0), (-L * 0.46, B / 2.0),
                      (-L * 0.45, B / 2.0 + B * 0.52),
                      (-L * 0.39, B / 2.0 + B * 0.48)], 0.42, name + "_rud"))
    use("gun")
    p.append(cyl((0, -L * 0.485, B / 2.0), B * 0.24, B * 0.20,
                 rot=(R(90), 0, 0), v=16, taper=0.55))
    use("body")
    return p


def sub_diesel():
    """Diesel-electric. Quiet on the battery, loud snorkelling (docs/11 Q1)."""
    L, B = 57.0, 6.8
    p = _sub(L, B, L * 0.16, 7.0, 4.0, name="ssk")
    return p, dict(top=B, hull_l=L, hull_w=B, turret_top=B * 0.97 + 5.6,
                   gun_z=B * 0.9, gun_y=L * 0.2)


def sub_nuclear():
    """Nuclear attack boat. Fast and long-legged - and in epoch 2, NOISIER
    than the diesels it replaced (docs/11)."""
    L, B = 115.0, 10.4
    p = _sub(L, B, L * 0.17, 11.0, 5.6, name="ssn")
    use("deck")
    for s in (-1, 1):                                   # bow VLS tubes
        p.append(cyl((s * 2.6, L * 0.30, B * 0.98), 0.85, 0.30, v=14))
    use("body")
    return p, dict(top=B, hull_l=L, hull_w=B, turret_top=B * 0.97 + 7.4,
                   gun_z=B * 0.9, gun_y=L * 0.2)


def sub_aip():
    """Air-independent propulsion. Near-silent at creep: the best ambusher and
    the worst pursuer in the game (docs/08, Germany)."""
    L, B = 57.0, 7.0
    p = _sub(L, B, L * 0.14, 6.2, 3.6, name="aip")
    return p, dict(top=B, hull_l=L, hull_w=B, turret_top=B * 0.97 + 5.2,
                   gun_z=B * 0.9, gun_y=L * 0.2)


def sub_midget():
    """The KPA's asymmetric tool: tiny acoustic signature, tiny range."""
    L, B = 20.0, 3.1
    p = _sub(L, B, L * 0.12, 2.6, 1.5, planes=False, name="mid")
    return p, dict(top=B, hull_l=L, hull_w=B, turret_top=B * 0.97 + 2.2,
                   gun_z=B * 0.9, gun_y=L * 0.2)


# ── aviation, amphibious, fleet train ──────────────────────────────
def carrier():
    """Nimitz scale: 333 m hull, 77 m across the flight deck. The ANGLED DECK
    and the starboard island are the identification, and both read from
    directly above - which is the only view an RTS gets."""
    L, B, DECK_W = 333.0, 41.0, 77.0
    p, fb = ship_hull(L, B, 11.0, bow=0.22, transom=0.94)
    use("body")
    # flight deck: rectangular, overhanging, with the angled landing area
    p.append(plate([(-DECK_W * 0.30, L * 0.49), (DECK_W * 0.34, L * 0.30),
                    (DECK_W * 0.50, -L * 0.10), (DECK_W * 0.50, -L * 0.50),
                    (-DECK_W * 0.50, -L * 0.50), (-DECK_W * 0.50, L * 0.10),
                    (-DECK_W * 0.42, L * 0.34)], 1.6, fb + 1.0, "flightdeck"))
    use("deck")
    p.append(plate([(-DECK_W * 0.46, -L * 0.44), (-DECK_W * 0.04, L * 0.30),
                    (-DECK_W * 0.16, L * 0.33), (-DECK_W * 0.50, -L * 0.42)],
                   0.16, fb + 1.9, "angledeck"))
    for k in range(4):                                  # arrestor wires
        p.append(cube((-DECK_W * 0.22, -L * 0.30 + k * 6.0, fb + 1.92),
                      (DECK_W * 0.44, 0.5, 0.08)))
    use("body")
    isl_x = DECK_W * 0.36
    p.append(deckhouse(-L * 0.04, 36.0, 11.0, 12.0, fb + 1.8, 0.92, "island"))
    p[-1].location.x = isl_x
    p.append(deckhouse(-L * 0.04, 18.0, 8.0, 5.0, fb + 13.8, 0.9, "island2"))
    p[-1].location.x = isl_x
    p += mast(isl_x, -L * 0.06, fb + 18.8, 16.0, 0.5)
    use("deck")
    for s in (-1, 1):                                   # deck-edge lifts
        p.append(cube((s * DECK_W * 0.50, -L * 0.18 + s * L * 0.16,
                       fb + 1.0), (9.0, 20.0, 1.0)))
    use("body")
    return p, dict(top=fb + 1.6, hull_l=L, hull_w=DECK_W,
                   turret_top=fb + 36.0, gun_z=fb + 2.0, gun_y=0.0)


def amphibious_assault():
    """Flat deck plus a well dock. Smaller than a carrier and without the
    angled landing area, which is how you tell them apart from above."""
    L, B, DECK_W = 257.0, 32.0, 42.0
    p, fb = ship_hull(L, B, 9.0, bow=0.24, transom=0.92)
    use("body")
    p.append(plate([(-DECK_W * 0.34, L * 0.48), (DECK_W * 0.34, L * 0.48),
                    (DECK_W * 0.50, L * 0.30), (DECK_W * 0.50, -L * 0.50),
                    (-DECK_W * 0.50, -L * 0.50), (-DECK_W * 0.50, L * 0.30)],
                   1.4, fb + 0.9, "deck"))
    isl_x = DECK_W * 0.34
    p.append(deckhouse(-L * 0.02, 44.0, 10.0, 11.0, fb + 1.6, 0.92, "island"))
    p[-1].location.x = isl_x
    p += mast(isl_x, -L * 0.06, fb + 12.6, 13.0, 0.44)
    use("deck")
    for k in range(6):                                  # landing spots
        p.append(cyl((-DECK_W * 0.16, L * 0.34 - k * L * 0.13, fb + 1.7),
                     4.6, 0.10, v=20))
    p.append(cube((0, -L * 0.485, fb - 3.0), (B * 0.70, 3.0, 5.0)))  # well dock
    use("body")
    return p, dict(top=fb + 1.4, hull_l=L, hull_w=DECK_W,
                   turret_top=fb + 26.0, gun_z=fb + 2.0, gun_y=0.0)


def landing_craft():
    """Ship-to-shore. A flat box with a bow ramp and a huge skirt."""
    L, B = 27.0, 14.3
    p = []
    use("body")
    p.append(plate([(-B * 0.44, L * 0.44), (B * 0.44, L * 0.44),
                    (B * 0.50, L * 0.20), (B * 0.50, -L * 0.44),
                    (-B * 0.50, -L * 0.44), (-B * 0.50, L * 0.20)],
                   1.5, 1.5, "lc_hull"))
    p.append(cube((0, L * 0.44, 1.4), (B * 0.62, 1.4, 2.4),
                  rot=(R(-30), 0, 0)))                   # bow ramp
    for s in (-1, 1):
        p.append(deckhouse(0.0, 12.0, 3.0, 3.2, 2.3, 0.9, f"lc_side{s}"))
        p[-1].location.x = s * B * 0.36
    use("deck")
    p.append(cube((0, 0, 0.55), (B * 1.02, L * 0.94, 1.1)))          # skirt
    use("gun")
    for s in (-1, 1):
        p.append(cyl((s * B * 0.24, -L * 0.40, 3.4), 2.2, 1.4,
                     rot=(R(90), 0, 0), v=16))                       # fans
    use("body")
    return p, dict(top=2.2, hull_l=L, hull_w=B, turret_top=6.0,
                   gun_z=3.0, gun_y=0.0)


def fleet_oiler():
    """Pillar 4's centrepiece (docs/04). Long flat deck, kingposts and hose
    rigs amidships, accommodation right aft. A submarine that finds this has
    taken the fleet's RANGE, which is worth more than a destroyer."""
    L, B = 206.0, 29.5
    p, fb = ship_hull(L, B, 8.0, bow=0.24, transom=0.90)
    p.append(deckhouse(-L * 0.36, 34.0, 20.0, 12.0, fb, 0.92, "acc"))
    p += mast(0, -L * 0.44, fb + 12.4, 11.0, 0.42)
    use("deck")
    for s in (-1, 1):                                    # replenishment rigs
        for y in (L * 0.16, -L * 0.06):
            p.append(cyl((s * 3.2, y, fb + 8.0), 0.60, 16.0, v=10))
            p.append(cube((s * 8.5, y, fb + 13.0), (12.0, 1.1, 1.1)))
    p.append(cube((0, L * 0.10, fb + 0.3), (B * 0.80, L * 0.44, 0.6)))  # tank tops
    for k in range(5):
        p.append(cyl((0, L * 0.30 - k * L * 0.11, fb + 0.9), 2.2, 0.7, v=16))
    use("body")
    p += helipad(-L * 0.20, 14.0, 18.0, fb)
    return p, dict(top=fb, hull_l=L, hull_w=B, turret_top=fb + 24.0,
                   gun_z=fb + 1.0, gun_y=0.0)


def mine_warfare():
    """Laying and sweeping. Taiwan's force multiplier - a small hull with a
    big open working deck and a stern gantry."""
    L, B = 68.0, 11.8
    p, fb = ship_hull(L, B, 3.6, bow=0.28)
    p.append(deckhouse(L * 0.20, 20.0, 8.6, 5.2, fb, 0.88, "dh"))
    p += mast(0, L * 0.10, fb + 7.8, 7.0, 0.28)
    use("deck")
    p.append(cube((0, -L * 0.22, fb + 0.2), (B * 0.78, L * 0.40, 0.4)))  # work deck
    for s in (-1, 1):                                    # stern gantry
        p.append(cube((s * B * 0.34, -L * 0.44, fb + 2.0), (0.6, 0.6, 4.0)))
    p.append(cube((0, -L * 0.44, fb + 4.0), (B * 0.74, 0.7, 0.7)))
    for k in range(3):                                   # mines on rails
        p.append(cyl((0, -L * 0.10 - k * 4.0, fb + 1.0), 1.0, 1.4, v=14))
    use("body")
    return p, dict(top=fb, hull_l=L, hull_w=B, turret_top=fb + 15.0,
                   gun_z=fb + 1.0, gun_y=L * 0.30)


NAVY = [
    ("nav_e4_us_destroyer",  destroyer_aaw,       "air_dark"),
    ("nav_e1_us_frigate",    frigate_asw,         "air_dark"),
    ("nav_e1_us_cruiser",    cruiser,             "air_dark"),
    ("nav_e1_us_corvette",   corvette,            "air_dark"),
    ("nav_e2_us_missileboat", missile_boat,       "air_dark"),
    ("nav_e1_us_patrol",     patrol_vessel,       "air_dark"),
    ("sub_e1_us_diesel",     sub_diesel,          "air_dark"),
    ("sub_e2_us_nuclear",    sub_nuclear,         "air_dark"),
    ("sub_e7_de_aip",        sub_aip,             "air_dark"),
    ("sub_e1_kp_midget",     sub_midget,          "air_dark"),
    ("nav_e1_us_carrier",    carrier,             "air_dark"),
    ("nav_e2_us_amphib",     amphibious_assault,  "air_dark"),
    ("nav_e1_us_landingcraft", landing_craft,     "air_dark"),
    ("nav_e1_us_oiler",      fleet_oiler,         "air_dark"),
    ("nav_e1_us_minewarfare", mine_warfare,       "air_dark"),
]

if __name__ == "__main__":
    H.set_out(os.path.join(ROOT, "art", "blockout", "e4_navy"))
    for name, _, camo in NAVY:
        H.CAMO[name] = camo
        H.TEAM[name] = (0.06, 0.20, 0.62)
    print("building navy...")
    for name, fn, _ in NAVY:
        for lod in (0, 1, 2):
            n = H.build(name, fn, lod)
            print(f"  {name:26s} LOD{lod}  {n:6d} tris")
    print("done")
