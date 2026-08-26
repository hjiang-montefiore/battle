"""The remaining national MBTs, built as bucket derivatives.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/faction_models.py

docs/08-factions.md says nation is the DERIVATIVE axis, not the hero axis —
eight factions cluster into three equipment lineages. These five are built from
the same parametric parts as the three reference heroes, differing in turret
side profile, gun, running gear and camouflage.

  WESTERN lineage    Challenger 2 (UK) · Leclerc (FR) · M1A2T (TW, US-derived)
  CHINESE indigenous ZTZ-99A (CN)
  SOVIET lineage     Chonma-ho (KP, T-62 derived)

Published dimensions; gun overhang is (length gun-forward − hull length), which
docs/07 records as a strong silhouette cue.
"""
import bpy, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_models as H
from hero_models import (cube, cyl, dome, profile, use, running_gear,
                         barrel, detail_kit, R)

ROOT = "/Users/hjiang/Desktop/battle"


def challenger2():
    """UK. Boxy Dorchester turret, RIFLED L30 — a visibly thicker tube, the
    only modern main gun that is not a smoothbore. Hull 8.33 m, gun-forward
    11.50 m -> 3.17 m overhang. 6 road wheels."""
    HL, HW, CL, HH = 8.33, 3.52, 0.50, 1.02
    top, ROOF = CL + HH, 2.49
    p = []
    p.append(profile([(-HL / 2, CL), (-HL / 2 + 1.95, top),
                      ( HL / 2, top), ( HL / 2, CL)], HW, "cr2_hull"))
    # long, square, slab-sided turret — the most rectangular of the Westerners
    p.append(profile([(-2.10, 1.66), (-2.02, 2.06), (-1.15, 2.44),
                      ( 1.35, ROOF), ( 2.45, 2.42), ( 2.45, 1.66),
                      ( 0.20, top),  (-1.55, top)], 2.86, "cr2_turret"))
    p.append(cube((0, 2.62, 2.02), (2.40, 0.34, 0.62)))         # bustle rack
    p.append(cyl((0.62, 0.95, ROOF + 0.20), 0.34, 0.40, v=12))
    p.append(cube((-0.86, 0.05, ROOF + 0.24), (0.50, 0.62, 0.46)))
    use("deck")
    for s in (-1, 1):
        p.append(cube((s * 0.92, HL * 0.33, top - 0.03), (1.45, 2.20, 0.08)))
        for k in range(8):
            p.append(cube((s * 0.92, HL * 0.33 - 0.90 + k * 0.26, top + 0.075),
                          (1.34, 0.14, 0.17)))
    use("body")
    p += barrel(-(HL / 2 + 3.17), 1.84, 4.55, 0.132, 1.90, 0.176)   # rifled: thicker
    p += detail_kit(HL, HW, top, ROOF, -2.10, 2.45, era=0)
    p += running_gear(HL, HW, CL, 6, 0.34, 0.62)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=1.84, gun_y=-2.10)


def leclerc():
    """France. Shortest Western hull, autoloader so a DEEP rear bustle and a
    3-man crew. Hull 6.88 m, gun-forward 9.87 m -> 2.99 m overhang. 6 wheels."""
    HL, HW, CL, HH = 6.88, 3.71, 0.50, 1.10
    top, ROOF = CL + HH, 2.53
    p = []
    p.append(profile([(-HL / 2, CL), (-HL / 2 + 1.60, top),
                      ( HL / 2, top), ( HL / 2, CL)], HW, "lec_hull"))
    # tall boxy turret dominated by the autoloader bustle
    p.append(profile([(-1.70, 1.74), (-1.62, 2.14), (-0.95, 2.48),
                      ( 0.85, ROOF), ( 2.30, 2.46), ( 2.30, 1.70),
                      ( 0.10, top),  (-1.20, top)], 2.78, "lec_turret"))
    p.append(cube((0, 1.95, 2.10), (2.62, 1.05, 0.74)))          # autoloader bustle
    p.append(cyl((0.58, 0.62, ROOF + 0.18), 0.32, 0.38, v=12))
    p.append(cube((-0.84, -0.20, ROOF + 0.22), (0.46, 0.58, 0.44)))
    use("era")
    for s in (-1, 1):                                             # modular blocks
        for k in range(3):
            p.append(cube((s * 1.24, -1.20 + k * 0.62, 2.02), (0.22, 0.56, 0.52)))
    use("deck")
    p.append(cube((0, HL * 0.34, top - 0.03), (2.30, 1.70, 0.08)))
    for k in range(7):
        p.append(cube((0, HL * 0.34 - 0.72 + k * 0.24, top + 0.075),
                      (2.18, 0.13, 0.16)))
    use("body")
    p += barrel(-(HL / 2 + 2.99), 1.88, 4.55, 0.112, 2.00, 0.160)
    p += detail_kit(HL, HW, top, ROOF, -1.70, 2.30, era=0)
    p += running_gear(HL, HW, CL, 6, 0.34, 0.64)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=1.88, gun_y=-1.70)


def ztz99a():
    """China. Indigenous lineage from epoch 5 (docs/08). Wedge-fronted turret
    with arrow-shaped applique, autoloaded 125 mm. Hull 7.0 m, ~2.37 m tall."""
    HL, HW, CL, HH = 7.00, 3.50, 0.47, 1.03
    top, ROOF = CL + HH, 2.37
    p = []
    p.append(profile([(-HL / 2, CL), (-HL / 2 + 1.50, top),
                      ( HL / 2, top), ( HL / 2, CL)], HW, "ztz_hull"))
    p.append(profile([(-1.60, 1.62), (-1.05, 2.30), ( 1.05, ROOF),
                      ( 1.95, 2.32), ( 1.95, 1.62), ( 0.10, top),
                      (-1.20, top)], 2.72, "ztz_turret"))
    use("era")
    for s in (-1, 1):                       # the arrow-shaped frontal applique
        p.append(cube((s * 0.66, -1.72, 2.02), (1.06, 1.44, 0.50),
                      rot=(0, 0, R(s * 27))))
    use("body")
    p.append(cube((0, 1.90, 2.00), (2.10, 0.66, 0.56)))
    p.append(cyl((0.52, 0.55, ROOF + 0.16), 0.31, 0.34, v=12))
    use("deck")
    p.append(cube((0, HL * 0.32, top - 0.03), (2.35, 1.85, 0.08)))
    for k in range(7):
        p.append(cube((0, HL * 0.32 - 0.78 + k * 0.26, top + 0.07),
                      (2.22, 0.14, 0.16)))
    use("body")
    p += barrel(-(HL / 2 + 3.55), 1.82, 4.85, 0.124, 1.85, 0.172)
    p += detail_kit(HL, HW, top, ROOF, -1.60, 1.95, era=0)
    p += running_gear(HL, HW, CL, 6, 0.34, 0.58)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=1.82, gun_y=-1.60)


def chonma():
    """North Korea. T-62 lineage: TALLER and older than a T-72, 5 large road
    wheels with wide gaps, 115 mm. The KPA's bulk force (docs/08)."""
    HL, HW, CL, HH = 6.63, 3.30, 0.43, 1.12
    top, ROOF = CL + HH, 2.40
    p = []
    p.append(profile([(-HL / 2, CL), (-HL / 2 + 1.30, top),
                      ( HL / 2, top), ( HL / 2, CL)], HW, "cho_hull"))
    p.append(dome((0, -0.42, top - 0.14), 1.28, 1.36, 0.86, v=20))
    p.append(cube((0, 0.60, top + 0.26), (1.90, 0.80, 0.52)))
    p.append(cyl((0.46, -0.05, top + 0.72), 0.30, 0.26, v=14))
    use("deck")
    for k in range(5):
        p.append(cube((0, HL * 0.30 + (k - 2) * 0.28, top + 0.02),
                      (2.05, 0.20, 0.09)))
    use("body")
    p += barrel(-(HL / 2 + 2.85), 1.84, 4.10, 0.108, 1.55, 0.150)
    for s in (-1, 1):                                        # external drums
        p.append(cyl((s * 0.95, HL / 2 - 0.20, top - 0.04), 0.26, 0.86,
                     rot=(R(90), 0, 0), v=12))
    p += detail_kit(HL, HW, top, top + 0.60, -1.50, 0.90, era=0, mg=True)
    p += running_gear(HL, HW, CL, 5, 0.42, 0.36, skirt_front_only=True)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=1.84, gun_y=-1.50)


# Taiwan fields the M1A2T — a true derivative: identical geometry, ROC scheme.
FACTIONS = [
    ("mbt_e4_uk_challenger2",  challenger2,        "camo_uk", (0.10, 0.30, 0.66)),
    ("mbt_e4_fr_leclerc",      leclerc,            "camo_fr", (0.12, 0.34, 0.70)),
    ("mbt_e6_cn_ztz99a",       ztz99a,             "camo_cn", (0.72, 0.14, 0.10)),
    ("mbt_e2_kp_chonma",       chonma,             "camo_kp", (0.66, 0.12, 0.14)),
    ("mbt_e4_tw_m1a2t",        H.m1_abrams,        "camo_tw", (0.16, 0.46, 0.24)),
]

if __name__ == "__main__":
    H.set_out(os.path.join(ROOT, "art", "blockout", "e4_mbt_nations"))
    for name, _, camo, team in FACTIONS:
        H.CAMO[name] = camo
        H.TEAM[name] = team
    print("building national variants...")
    for name, fn, _, _ in FACTIONS:
        for lod in (0, 1, 2):
            n = H.build(name, fn, lod)
            print(f"  {name:26s} LOD{lod}  {n:6d} tris")
    print("done")
