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

    unit          hull L   width   height   gun fwd   overhang   wheels
    Challenger 2   8.33     3.52    2.49     11.50      3.17        6
    Leclerc        6.88     3.71    2.53      9.87      2.99        6
    ZTZ-99A        7.60     3.70    2.35     11.00      3.40        6
    Chonma-ho      6.63     3.30    2.40      9.34      2.71        5
    M1A2T          7.93     3.66    2.44      9.77      1.84        7

Challenger 2 hull/gun-forward are the British Army's 8.33 m / 11.55 m; the
enwiki infobox's "13.5 m gun forward" is not credible for a 6.6 m L30A1 on an
8.3 m hull and is not used. Chonma-ho takes the T-62's 9.34 m / 6.63 m because
its own infobox omits the gun-forward figure.
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_models as H
from hero_models import (cube, cyl, dome, profile, use, running_gear,
                         barrel, detail_kit, R)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ── shared corrections ─────────────────────────────────────────────
def gun(y_tip, y_breech, z, r, sleeve_r, sleeve_frac=0.40):
    """A barrel that actually reaches its own turret.

    hero_models.barrel() takes a tube LENGTH, and every derivative in this file
    was passing one measured off the real gun rather than off the turret it is
    bolted to. Measured on the LOD0 exports: the Challenger's tube stopped
    0.69 m in FRONT of the mantlet, the ZTZ's 0.60 m, the Chonma's 0.29 m — the
    whole gun shipped as a floating island. check_detached() never flagged it
    because the tube, sleeve, evacuator and muzzle overlap EACH OTHER, so every
    island in the cluster has a neighbour; and verify_shape's largest_blob then
    scored the hull alone (90.6% of the dark pixels) against a whole vehicle.

    Driving the tube from the breech end instead keeps the muzzle at the
    published overhang — which is the silhouette cue — and guarantees the
    breech lands inside the turret.
    """
    length = y_breech - y_tip
    return barrel(y_tip, z, length, r, length * sleeve_frac, sleeve_r)


def mantlet(y_face, z, w, h, d=0.62):
    """The armoured block the gun pivots in.

    Without one the tube emerges from a flat plate, which is what every one of
    these turrets was doing. It straddles the turret face so it also closes any
    residual seam between tube and turret.
    """
    return cube((0, y_face + d * 0.16, z), (w, d, h))


def challenger2():
    """UK. Boxy Dorchester turret, RIFLED L30 — a visibly thicker tube, the
    only modern main gun that is not a smoothbore. Hull 8.33 m, gun-forward
    11.50 m -> 3.17 m overhang. 6 road wheels."""
    HL, HW, CL, HH = 8.33, 3.52, 0.50, 1.02
    top, ROOF = CL + HH, 2.49
    FACE = -2.10                                  # turret front, and the gun
    p = []
    p.append(profile([(-HL / 2, CL), (-HL / 2 + 1.95, top),
                      ( HL / 2, top), ( HL / 2, CL)], HW, "cr2_hull"))
    # long, square, slab-sided turret — the most rectangular of the Westerners
    # The front was a 24-degree ramp running unbroken into the glacis, which
    # reads as a wedge turret — a Leopard 2A5 cue, and the opposite of the
    # Challenger's blunt Dorchester box. Steepen it to 40 degrees over a short
    # run so the roof stays long and flat, which is the actual CR2 tell.
    p.append(profile([(FACE, 1.66), (-2.05, 2.04), (-1.58, 2.46),
                      ( 1.35, ROOF), ( 2.45, 2.42), ( 2.45, 1.66),
                      ( 0.20, top),  (-1.55, top)], 2.86, "cr2_turret"))
    p.append(cube((0, 2.62, 2.02), (2.40, 0.34, 0.62)))         # bustle rack
    p.append(cyl((0.62, 0.95, ROOF + 0.20), 0.34, 0.40, v=12))
    p.append(cube((-0.86, 0.05, ROOF + 0.24), (0.50, 0.62, 0.46)))
    p.append(mantlet(FACE, 1.84, 1.16, 0.76, 0.66))
    use("deck")
    for s in (-1, 1):
        p.append(cube((s * 0.92, HL * 0.33, top - 0.03), (1.45, 2.20, 0.08)))
        for k in range(8):
            p.append(cube((s * 0.92, HL * 0.33 - 0.90 + k * 0.26, top + 0.075),
                          (1.34, 0.14, 0.17)))
    use("body")
    p += gun(-(HL / 2 + 3.17), FACE + 0.38, 1.84, 0.132, 0.176)  # rifled: thick
    p += detail_kit(HL, HW, top, ROOF, FACE, 2.45, era=0)
    p += running_gear(HL, HW, CL, 6, 0.34, 0.62)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=1.84, gun_y=FACE)


def leclerc():
    """France. Shortest Western hull, autoloader so a DEEP rear bustle and a
    3-man crew. Hull 6.88 m, gun-forward 9.87 m -> 2.99 m overhang. 6 wheels."""
    HL, HW, CL, HH = 6.88, 3.71, 0.50, 1.10
    top, ROOF = CL + HH, 2.53
    FACE = -1.70
    p = []
    p.append(profile([(-HL / 2, CL), (-HL / 2 + 1.60, top),
                      ( HL / 2, top), ( HL / 2, CL)], HW, "lec_hull"))
    # tall boxy turret dominated by the autoloader bustle
    p.append(profile([(FACE, 1.74), (-1.62, 2.14), (-0.95, 2.48),
                      ( 0.85, ROOF), ( 2.30, 2.46), ( 2.30, 1.70),
                      ( 0.10, top),  (-1.20, top)], 2.78, "lec_turret"))
    p.append(cube((0, 1.95, 2.10), (2.62, 1.05, 0.74)))          # autoloader bustle
    p.append(cyl((0.58, 0.62, ROOF + 0.18), 0.32, 0.38, v=12))
    p.append(cube((-0.84, -0.20, ROOF + 0.22), (0.46, 0.58, 0.44)))
    p.append(mantlet(FACE, 1.88, 1.04, 0.72, 0.60))
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
    p += gun(-(HL / 2 + 2.99), FACE + 0.38, 1.88, 0.112, 0.160)
    p += detail_kit(HL, HW, top, ROOF, FACE, 2.30, era=0)
    p += running_gear(HL, HW, CL, 6, 0.34, 0.64)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=1.88, gun_y=FACE)


def ztz99a():
    """China. Indigenous lineage from epoch 5 (docs/08). Wedge-fronted turret
    with arrow-shaped applique, autoloaded 125 mm. Hull 7.60 m, gun-forward
    11.00 m -> 3.40 m overhang, 3.70 m wide, 2.35 m to the roof. 6 large
    T-72-pattern road wheels."""
    HL, HW, CL, HH = 7.60, 3.70, 0.47, 1.03
    top, ROOF = CL + HH, 2.35
    FACE = -1.60
    p = []
    p.append(profile([(-HL / 2, CL), (-HL / 2 + 1.50, top),
                      ( HL / 2, top), ( HL / 2, CL)], HW, "ztz_hull"))
    p.append(profile([(FACE, 1.62), (-1.05, 2.30), ( 1.05, ROOF),
                      ( 1.95, 2.32), ( 1.95, 1.62), ( 0.10, top),
                      (-1.20, top)], 2.72, "ztz_turret"))
    use("era")
    for s in (-1, 1):                       # the arrow-shaped frontal applique
        # 1.44 m long, it reached 1.0 m past the turret face and hung over the
        # glacis; the real plate projects about half that. Keep the plan-view
        # chevron, which is the identifying feature from the RTS camera.
        p.append(cube((s * 0.66, -1.58, 2.06), (1.06, 1.05, 0.50),
                      rot=(0, 0, R(s * 27))))
    use("body")
    p.append(cube((0, 1.90, 2.00), (2.10, 0.66, 0.56)))
    p.append(cyl((0.52, 0.55, ROOF + 0.16), 0.31, 0.34, v=12))
    p.append(mantlet(FACE, 1.82, 1.00, 0.70, 0.58))
    use("deck")
    p.append(cube((0, HL * 0.32, top - 0.03), (2.35, 1.85, 0.08)))
    for k in range(7):
        p.append(cube((0, HL * 0.32 - 0.78 + k * 0.26, top + 0.07),
                      (2.22, 0.14, 0.16)))
    use("body")
    p += gun(-(HL / 2 + 3.40), FACE + 0.55, 1.82, 0.124, 0.172)
    p += detail_kit(HL, HW, top, ROOF, FACE, 1.95, era=0)
    p += running_gear(HL, HW, CL, 6, 0.38, 0.58)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=1.82, gun_y=FACE)


def chonma():
    """North Korea. T-62 lineage: TALLER and older than a T-72, 5 large road
    wheels with wide gaps, 115 mm. The KPA's bulk force (docs/08).

    Hull 6.63 m, gun-forward 9.34 m -> 2.71 m overhang. The later Ch'onma-ho
    marks carry a slab of ERA across the glacis and turret cheeks and a heavy
    MG on a raised commander's cupola, which is what tells this apart from a
    plain T-62 at a glance."""
    # Heights read off the orthographic side drawing (art/reference/3v_chonma
    # .png, calibrated on the 9.34 m gun-forward length): hull roof 1.38 m,
    # turret roof 2.41 m, gun axis 1.56 m. The hull was 0.13 m too tall and the
    # gun sat 0.20 m too high, which made the whole vehicle read as a modern
    # MBT instead of a 1960s Soviet one.
    HL, HW, CL, HH = 6.63, 3.30, 0.43, 0.99
    top, ROOF = CL + HH, 2.40
    DOME_Y, DOME_RY = -0.42, 1.36
    FACE = DOME_Y - DOME_RY                       # front of the cast dome
    p = []
    p.append(profile([(-HL / 2, CL), (-HL / 2 + 1.30, top),
                      ( HL / 2, top), ( HL / 2, CL)], HW, "cho_hull"))
    p.append(dome((0, DOME_Y, top - 0.06), 1.28, DOME_RY, 1.02, v=20))
    p.append(cube((0, 0.60, top + 0.26), (1.90, 0.80, 0.52)))
    p.append(cyl((0.46, -0.05, top + 0.90), 0.34, 0.34, v=14))   # cupola
    p.append(mantlet(FACE, 1.52, 0.94, 0.54, 0.58))
    use("deck")
    for k in range(5):
        p.append(cube((0, HL * 0.30 + (k - 2) * 0.28, top + 0.02),
                      (2.05, 0.20, 0.09)))
    use("body")
    p += gun(-(HL / 2 + 2.71), FACE + 0.30, 1.52, 0.108, 0.150)
    for s in (-1, 1):                                        # external drums
        p.append(cyl((s * 0.95, HL / 2 - 0.20, top - 0.04), 0.26, 0.86,
                     rot=(R(90), 0, 0), v=12))
    p += detail_kit(HL, HW, top, top + 0.60, -1.50, 0.90, era=8, mg=True)
    # Tall whip on the turret rear. The KPA cars carry one erect, and it is the
    # top of the silhouette in the reference drawing — without it the model
    # measures 3.54 long-to-tall against the drawing's 3.02 and every
    # bbox-normalised comparison starts with the whole vehicle mis-registered.
    p.append(cyl((-0.74, 0.80, top + 0.95), 0.042, 1.44, v=6))
    use("team")
    # detail_kit puts its team patch at 34% along the turret, which on a CAST
    # DOME is 0.10 m BELOW the surface — buried, and CONVENTIONS.md wants it
    # readable from directly above. Put a second one on the flat turret rear.
    p.append(cube((0.02, 0.60, top + 0.50), (0.62, 0.44, 0.06)))
    use("body")
    # running_gear() puts the idler and sprocket at 0.455 of the hull length it
    # is given and only 60% of that on the ground. On a T-62 both end wheels sit
    # at the extreme ends of the hull, so it is handed a 10% longer hull to work
    # from; that lands them on the real hull ends instead of 0.3 m inboard.
    p += running_gear(HL * 1.10, HW, CL, 5, 0.42, 0.36, skirt_front_only=True)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=1.52, gun_y=-1.50)


def m1a2t():
    """Taiwan. The M1A2T is an M1A2 SEPv3 hull and turret, so it is built from
    the hero M1 unchanged — same 7.93 m hull, same 3.66 m width, same 1.84 m
    gun overhang, same seven small road wheels. Only the roof is added to.

    What separates it from the US car in a gameplay frame is the CROWS-II
    remote weapon station standing proud of the commander's station — a boxed
    sight-and-gun pod roughly half a metre tall, where the M1A2 has a bare
    hatch ring — plus the SEPv3 line-replaceable module on the left rear of the
    bustle. Everything here is ADDITIVE on top of the hero parts: nothing is
    deleted, so this cannot silently diverge if the hero M1 is re-tuned, and a
    national variant that is the US tank in a different colour is the one thing
    docs/08 says a derivative may not be."""
    p, m = H.m1_abrams()
    ROOF = m["turret_top"]
    use("body")
    # CROWS-II: pod on the cupola ring, ammunition can, sight head canted fwd
    p.append(cube((0.60, 0.80, ROOF + 0.44), (0.54, 0.72, 0.40)))
    p.append(cube((0.60, 0.42, ROOF + 0.64), (0.26, 0.34, 0.20)))
    p.append(cube((-0.95, 2.16, ROOF - 0.04), (0.70, 0.44, 0.40)))   # SEPv3 LRM
    use("gun")
    p.append(cyl((0.60, 0.02, ROOF + 0.50), 0.050, 1.20,             # M2 on RWS
                 rot=(R(90), 0, 0), v=8))
    use("body")
    return p, m


FACTIONS = [
    ("mbt_e4_uk_challenger2",  challenger2,        "camo_uk", (0.10, 0.30, 0.66)),
    ("mbt_e4_fr_leclerc",      leclerc,            "camo_fr", (0.12, 0.34, 0.70)),
    ("mbt_e6_cn_ztz99a",       ztz99a,             "camo_cn", (0.72, 0.14, 0.10)),
    ("mbt_e2_kp_chonma",       chonma,             "camo_kp", (0.66, 0.12, 0.14)),
    ("mbt_e4_tw_m1a2t",        m1a2t,              "camo_tw", (0.16, 0.46, 0.24)),
]


# ── texture pass (2026-08): composed-texture REQUESTS, roster data only ──
# Build-space metres, Z-up, forward = -Y. Each nation gets its own marking
# and its own mud: European operators run dark wet loam, the ZTZ a paler
# loess dust, the Chonma-ho the heaviest grime of the roster (minimal
# maintenance is that faction's read).
def _mbt(name, kind, x, y, z, size, dust, tint, color=None):
    H.texture_features(
        name, size_class="vehicle", groups=("body", "deck"),
        panels=dict(spacing=1.5, strength=0.55, jitter=0.13, seams=0.55),
        weathering=dict(
            dust=dict(height=1.3, strength=dust, tint=tint),
            edge_wear=dict(strength=0.5)),
        insignia=[dict(kind=kind, center=( x, y, z), normal=( 1, 0, 0),
                       size=size, alpha=0.9, color=color),
                  dict(kind=kind, center=(-x, y, z), normal=(-1, 0, 0),
                       size=size, alpha=0.9, color=color)])


_mbt("mbt_e4_uk_challenger2", "roundel_uk", 1.50, 0.30, 2.00, 0.45,
     0.50, (0.33, 0.29, 0.22))
_mbt("mbt_e4_fr_leclerc",     "roundel_fr", 1.55, 0.30, 2.05, 0.45,
     0.50, (0.35, 0.31, 0.23))
_mbt("mbt_e6_cn_ztz99a",      "star_cn",    1.50, 0.20, 1.95, 0.50,
     0.55, (0.46, 0.41, 0.30))
_mbt("mbt_e2_kp_chonma",      "star_kp",    1.62, 0.40, 1.00, 0.45,
     0.70, (0.36, 0.32, 0.24))
_mbt("mbt_e4_tw_m1a2t",       "sun_tw",     1.45, -0.20, 2.00, 0.50,
     0.55, (0.30, 0.27, 0.20))

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
