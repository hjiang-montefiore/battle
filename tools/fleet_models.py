"""Parametric builders for the rest of the roster, reusing the hero pipeline.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/fleet_models.py

Everything here goes through the SAME code as the three reference heroes —
same running gear, same AO bake, same socket contract, same artifact-level
COLOR_0 verification. That is the point of doing it parametrically: a quality
fix made in hero_models.py propagates to every role instead of needing 86
repeats.

Target is the minimum playable set from docs/12-unit-roster.md — the 14 roles
that exercise all seven pillars in one 20-minute match.
"""
import bpy, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_models as H
from hero_models import (cube, cyl, dome, profile, use, running_gear,
                         barrel, detail_kit, R)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ── wheeled running gear (trucks, radar vehicles, launchers) ────────
def wheeled_gear(hull_l, hull_w, clearance, axles, wheel_r, first=0.30, last=0.88):
    parts = []
    use("track")
    for s in (-1, 1):
        x = s * (hull_w / 2 - 0.16)
        for i in range(axles):
            f = first + (last - first) * (i / max(1, axles - 1))
            y = -hull_l / 2 + hull_l * f
            parts.append(cyl((x, y, wheel_r), wheel_r, 0.34,
                             rot=(0, R(90), 0), v=14))
            parts.append(cyl((x, y, wheel_r), wheel_r * 0.52, 0.36,
                             rot=(0, R(90), 0), v=12))
    use("body")
    return parts


def boxhull(hull_l, hull_w, clearance, hull_h, nose=1.0, name="hull"):
    top = clearance + hull_h
    return profile([(-hull_l / 2, clearance),
                    (-hull_l / 2 + nose, top),
                    (hull_l / 2, top),
                    (hull_l / 2, clearance)], hull_w, name), top


# ── tracked armoured family ────────────────────────────────────────
def ifv():
    """Infantry fighting vehicle: low hull, small two-man turret, autocannon
    plus a boxed ATGM launcher on the turret side."""
    # published: 6.55 x 3.60 x 2.98 m, six road wheels, turret OFFSET RIGHT
    HL, HW, CL, HH = 6.55, 3.60, 0.44, 1.40
    p = []
    h, top = boxhull(HL, HW, CL, HH, 1.55, "ifv_hull")
    p.append(h)
    ROOF = 2.98
    TX = 0.42                       # turret offset right, to clear the troop bay
    p.append(profile([(-0.95, top), (-0.80, ROOF - 0.12), (0.85, ROOF),
                      (1.30, ROOF - 0.16), (1.30, top)], 1.72, "ifv_turret"))
    p[-1].location.x = TX
    p.append(cube((TX, -0.55, top + 0.48), (0.60, 0.55, 0.46)))     # mantlet
    p += barrel(-3.95, top + 0.56, 1.95, 0.048, 0.55, 0.070)        # 25 mm
    p[-1].location.x = TX
    use("deck")
    for k in range(2):                                              # TWO TOW tubes
        p.append(cube((TX - 1.00, 0.30, ROOF - 0.34 + k * 0.34),
                      (0.42, 0.92, 0.30)))
    use("body")
    p.append(cube((0, HL * 0.42, top + 0.30), (HW * 0.72, 0.14, 0.60)))  # ramp
    p += detail_kit(HL, HW, top, ROOF, -0.95, 1.30, era=0)
    p += running_gear(HL, HW, CL, 6, 0.30, 0.50)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 0.40, gun_y=-0.95)


def recon_tracked():
    """Reconnaissance vehicle: small, low, mast-mounted sensors, light gun.
    Passive sensors — it feeds the track table without radiating."""
    HL, HW, CL, HH = 5.30, 2.90, 0.40, 0.92
    p = []
    h, top = boxhull(HL, HW, CL, HH, 1.35, "rec_hull")
    p.append(h)
    ROOF = top + 0.52
    p.append(cube((0, 0.10, top + 0.26), (1.62, 1.70, 0.52)))
    p += barrel(-3.15, top + 0.30, 1.30, 0.035, 0.40, 0.052)
    use("deck")
    p.append(cyl((0.55, 0.75, ROOF + 0.85), 0.075, 1.70, v=8))      # sensor mast
    p.append(cube((0.55, 0.75, ROOF + 1.72), (0.46, 0.30, 0.30)))   # sensor head
    use("body")
    p += detail_kit(HL, HW, top, ROOF, -0.75, 0.95, era=0, mg=False)
    p += running_gear(HL, HW, CL, 5, 0.28, 0.44)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 0.30, gun_y=-0.75)


def sph():
    """Self-propelled howitzer: large turret, very long barrel with a big
    muzzle brake. Shoot-and-scoot, because counter-battery radar exists."""
    # published: hull 6.2 m, 9.75 m gun forward, 3.15 m wide, 3.25 m tall
    HL, HW, CL, HH = 6.20, 3.15, 0.45, 1.20
    p = []
    h, top = boxhull(HL, HW, CL, HH, 1.20, "sph_hull")
    p.append(h)
    ROOF = 3.25
    # the M109's turret is enormous relative to the hull — nearly full width,
    # near-vertical sides, and a deep rear bustle. That IS its silhouette.
    p.append(profile([(-1.55, top + 0.05), (-1.40, ROOF), (1.55, ROOF),
                      (2.05, ROOF - 0.35), (2.05, top), (-1.10, top)],
                     2.92, "sph_turret"))
    p.append(cube((0, -1.75, top + 0.75), (0.95, 0.70, 0.90)))
    p += barrel(-(HL / 2 + 3.55), top + 0.85, 4.30, 0.098, 1.10, 0.140)
    use("deck")
    p.append(cyl((0, -8.30, top + 0.64), 0.175, 0.62, rot=(R(90), 0, 0), v=14))
    use("body")
    p += detail_kit(HL, HW, top, ROOF, -1.55, 2.05, era=0)
    p += running_gear(HL, HW, CL, 6, 0.33, 0.58)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 0.64, gun_y=-1.90)


def mlrs():
    """Rocket artillery: hull with a boxed launcher pod on an elevating
    cradle. Area-fires at TQ0 — the one weapon needing no track at all."""
    HL, HW, CL, HH = 6.90, 3.18, 0.46, 1.22
    p = []
    h, top = boxhull(HL, HW, CL, HH, 1.60, "mlrs_hull")
    p.append(h)
    p.append(cube((0, -HL * 0.24, top + 0.60), (2.55, 2.35, 1.20)))  # cab
    ROOF = top + 1.20
    use("deck")
    p.append(cube((0, HL * 0.20, top + 0.86), (2.30, 3.05, 1.05),
                  rot=(R(-16), 0, 0)))                               # pod
    # two 6-pack pods = twelve rockets, arranged six across and two high
    for r in range(2):
        for c in range(6):
            p.append(cyl((-1.05 + c * 0.42, HL * 0.20 - 1.45, top + 0.55 + r * 0.44),
                         0.115, 3.00, rot=(R(74), 0, 0), v=8))
    use("body")
    for s in (-1, 1):
        p.append(cube((s * 1.20, HL * 0.16, top + 0.34), (0.24, 1.30, 0.68)))
    p += detail_kit(HL, HW, top, ROOF, -0.60, 1.40, era=0, mg=False)
    p += running_gear(HL, HW, CL, 6, 0.32, 0.56)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 0.86, gun_y=-0.60)


# ── wheeled family ─────────────────────────────────────────────────
def search_radar():
    """Long-range search radar on an 8x8 chassis. max_quality = TRACK — it
    finds things and cannot guide a weapon. The array ROTATES only while
    EMCON is RADIATE, which is how a player sees emission state."""
    HL, HW, CL, HH = 9.20, 3.00, 0.52, 1.10
    p = []
    h, top = boxhull(HL, HW, CL, HH, 1.20, "srad_hull")
    p.append(h)
    p.append(cube((0, -HL * 0.33, top + 0.62), (2.75, 2.45, 1.24)))  # cab
    use("deck")
    p.append(cube((0, HL * 0.16, top + 0.34), (2.30, 3.60, 0.68)))   # turntable
    p.append(cube((0, HL * 0.16, top + 2.05), (5.40, 0.30, 2.70),
                  rot=(R(-14), 0, 0)))                               # planar array
    for k in range(5):
        p.append(cube((0, HL * 0.16 - 0.13, top + 0.95 + k * 0.52),
                      (5.20, 0.22, 0.13)))
    use("body")
    p.append(cyl((0, HL * 0.16, top + 1.00), 0.44, 1.30, v=14))      # mast
    ROOF = top + 3.40
    p += detail_kit(HL, HW, top, top + 1.24, -HL * 0.33, HL * 0.16, era=0, mg=False)
    p += wheeled_gear(HL, HW, CL, 4, 0.58)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 2.0, gun_y=0.0)


def illuminator():
    """Fire-control / illuminator radar. max_quality = FIRE_CONTROL, so this
    is the vehicle to kill — and the thing anti-radiation missiles home on."""
    HL, HW, CL, HH = 7.40, 2.90, 0.50, 1.05
    p = []
    h, top = boxhull(HL, HW, CL, HH, 1.15, "ill_hull")
    p.append(h)
    p.append(cube((0, -HL * 0.30, top + 0.58), (2.60, 2.20, 1.16)))
    use("deck")
    p.append(cyl((0, HL * 0.20, top + 0.42), 0.90, 0.84, v=16))
    p.append(cyl((0, HL * 0.20, top + 1.55), 1.42, 0.26, rot=(R(-24), 0, 0), v=20))
    p.append(cyl((0, HL * 0.20 - 0.36, top + 1.72), 0.13, 0.90,
                 rot=(R(66), 0, 0), v=8))                            # feed horn
    use("body")
    ROOF = top + 2.30
    p += detail_kit(HL, HW, top, top + 1.16, -HL * 0.30, HL * 0.20, era=0, mg=False)
    p += wheeled_gear(HL, HW, CL, 3, 0.55)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 1.55, gun_y=HL * 0.20)


def sam_launcher():
    """Medium SAM launcher — launcher ONLY. Needs a search radar to find and
    an illuminator to guide. Splitting the battery is what creates the
    SEAD duel in docs/02."""
    HL, HW, CL, HH = 7.80, 3.00, 0.52, 1.08
    p = []
    h, top = boxhull(HL, HW, CL, HH, 1.25, "sam_hull")
    p.append(h)
    p.append(cube((0, -HL * 0.31, top + 0.60), (2.70, 2.30, 1.20)))
    use("deck")
    p.append(cube((0, HL * 0.18, top + 0.30), (2.40, 3.30, 0.60)))   # cradle
    for c in range(4):
        p.append(cyl((-1.02 + c * 0.68, HL * 0.18, top + 1.55), 0.30, 5.40,
                     rot=(R(58), 0, 0), v=12))                       # canisters
    use("body")
    for s in (-1, 1):
        p.append(cube((s * 1.32, HL * 0.18, top + 0.62), (0.16, 3.10, 0.70)))
    ROOF = top + 3.10
    p += detail_kit(HL, HW, top, top + 1.20, -HL * 0.31, HL * 0.18, era=0, mg=False)
    p += wheeled_gear(HL, HW, CL, 4, 0.56)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 1.55, gun_y=HL * 0.18)


def fuel_truck():
    """Pillar 4 made physical. Soft, slow, and often better to kill than the
    tanks it feeds."""
    HL, HW, CL, HH = 8.60, 2.86, 0.55, 0.72
    p = []
    h, top = boxhull(HL, HW, CL, HH, 0.90, "fuel_hull")
    p.append(h)
    p.append(cube((0, -HL * 0.34, top + 0.72), (2.55, 2.20, 1.44)))  # cab
    p.append(cyl((0, HL * 0.16, top + 0.95), 1.16, 5.20,
                 rot=(R(90), 0, 0), v=20))                           # tank barrel
    use("deck")
    for k in range(4):                                               # ring stiffeners
        p.append(cyl((0, HL * 0.16 - 1.95 + k * 1.30, top + 0.95), 1.21, 0.10,
                     rot=(R(90), 0, 0), v=20))
    p.append(cube((0, HL * 0.16, top + 2.16), (0.70, 0.90, 0.30)))   # manway
    use("body")
    ROOF = top + 2.20
    p += detail_kit(HL, HW, top, top + 1.44, -HL * 0.34, HL * 0.16, era=0, mg=False)
    p += wheeled_gear(HL, HW, CL, 3, 0.56)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 0.95, gun_y=0.0)


FLEET = [
    ("afv_e4_us_ifv",        ifv),
    ("rec_e4_us_recon",      recon_tracked),
    ("art_e4_us_sph",        sph),
    ("art_e4_us_mlrs",       mlrs),
    ("rad_e4_us_search",     search_radar),
    ("rad_e4_us_illuminator", illuminator),
    ("sam_e4_us_launcher",   sam_launcher),
    ("log_e4_us_fueltruck",  fuel_truck),
]

if __name__ == "__main__":
    H.set_out(os.path.join(ROOT, "art", "blockout", "e4_support"))
    for name, fn in FLEET:
        H.CAMO[name] = "camo_us"
        H.TEAM[name] = (0.06, 0.20, 0.62)
    print("building fleet...")
    for name, fn in FLEET:
        for lod in (0, 1, 2):
            n = H.build(name, fn, lod)
            print(f"  {name:26s} LOD{lod}  {n:6d} tris")
    print("done")
