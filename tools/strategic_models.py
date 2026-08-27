"""The nuclear triad from docs/15-strategic-weapons.md.

    Blender -b --python tools/strategic_models.py

Three basing modes, three different answers to "can you be found?":

    missile silo     accepts detection, survives by hardening
    mobile launcher  evades detection on land, survives by never being located
    SSBN             evades detection at sea, survives by being acoustically dark

The SSBN also introduces the first naval hull builder — a body of revolution
along the waterline, which the rest of the fleet in docs/12 will reuse.

DIMENSIONS AND REFERENCES
-------------------------
Every number below is either a published dimension or a measurement taken off
an orthographic line drawing in art/reference/. See art/reference/SOURCES.md.

    ssbn        Commons "SSBN726 Ohio.svg" + "Ohio Class.png", both port
                elevations. Measured against the known 13.0 m beam, which puts
                the drawing scale at 11.18 px/m and makes every other station
                fall out of the same picture.
    mobile_tel  Commons "Topol M SS27 Sickle B sketch.svg", left elevation of
                the 15U175 launcher on the MZKT-79221 chassis. Scaled so the
                chassis measures its published 22.7 m; at that scale the tyres
                measure 1.61 m, which is the published 1600x600 size, so two
                independent published figures agree with the drawing.
    silo        No orthographic drawing of a Minuteman III launch facility
                exists on Commons — the site is a hole in the ground and every
                image of one is a photograph. Built to published LF figures
                instead: 3.66 m (12 ft) launch tube, ~24 m deep, a sliding
                launcher closure door, and a fenced security area.
"""
import bpy, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_models as H
from hero_models import cube, cyl, dome, profile, use, R

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def revolve(length, r_max, stations, z=0.0, v=20, taper_nose=True):
    """Body of revolution along Y, nose at +Y. stations = ((frac, r_frac), ...)"""
    out = []
    y_nose = length * 0.5
    for i in range(len(stations) - 1):
        (f0, r0), (f1, r1) = stations[i], stations[i + 1]
        y0, y1 = y_nose - f0 * length, y_nose - f1 * length
        seg = y0 - y1
        if seg <= 0:
            continue
        ra = max(r_max * r0, 0.03)
        rb = max(r_max * r1, 0.03)
        out.append(cyl((0, (y0 + y1) / 2.0, z), ra, seg,
                       rot=(R(90), 0, 0), v=v, taper=rb / ra))
    return out


# ── fixed silo ─────────────────────────────────────────────────────
def missile_silo():
    """Hardened underground launcher, Minuteman III launch facility scale.

    Its position is known from the first minute of the match; it survives by
    being buried in concrete, so in docs/03 terms it has an absurd TOP facet
    and nothing else that matters.

    Almost no silhouette — a concrete apron, a 3.66 m tube mouth, and the
    displaced blast door sitting on its rails, inside a fenced security area.
    That flatness IS the identification: nothing else in the roster is a
    30 m square of nothing.

    Published (LGM-30G launch facility): launch tube 12 ft = 3.66 m across and
    80 ft = 24.4 m deep; launcher closure door a ~6 x 7 m slab that slides
    clear on rails rather than hinging; support equipment all underground.
    """
    APRON, PAD, TUBE_R = 24.0, 5.1, 1.83
    FENCE = 10.6                                                  # half-extent
    p = []
    use("body")
    p.append(cube((0, 0, 0.09), (APRON, APRON, 0.18)))            # graded apron
    use("deck")
    # the cap and collar are concrete, not gravel: giving them the deck
    # material is what makes the headworks read as a disc from directly
    # overhead instead of vanishing into the apron camouflage.
    p.append(cyl((0, 0, 0.50), PAD, 0.68, v=28))                  # headworks cap
    p.append(cyl((0, 0, 0.96), 2.55, 0.32, v=24))                 # tube collar
    p.append(cyl((0, 0, 1.09), 2.15, 0.26, v=24))                 # mouth rim
    for s in (-1, 1):                                             # door rails
        p.append(cube((4.0, s * 2.45, 0.94), (12.0, 0.55, 0.30)))
    use("gunbore")
    p.append(cyl((0, 0, 1.21), TUBE_R, 0.14, v=24))               # open tube
    use("deck")
    # launcher closure door, slid clear of the mouth on its rails
    p.append(cube((6.95, 0.0, 1.66), (6.10, 6.70, 1.16)))
    p.append(cube((6.95, 0.0, 2.28), (5.20, 5.80, 0.14)))         # door cap

    use("body")
    for s in (-1, 1):                                             # blast valves
        p.append(cube((s * 5.9, -6.6, 0.62), (1.70, 1.70, 0.92)))
    p.append(cube((-8.4, 6.6, 0.78), (3.20, 4.20, 1.24)))         # crew headworks
    use("deck")
    p.append(cyl((-8.4, 6.6, 1.52), 0.34, 0.34, v=14))            # access hatch
    p.append(cyl((-4.9, 4.3, 0.30), 0.78, 0.28, v=16))            # personnel hatch
    use("body")
    # survivable MF antenna — the one thing on an LF that is not flat
    p.append(cyl((-8.0, -7.6, 0.61), 0.55, 0.90, v=14))
    p.append(dome((-8.0, -7.6, 1.06), 1.55, 1.55, 0.60, v=16))
    use("gun")
    p.append(cyl((-8.0, -7.6, 2.10), 0.09, 1.60, v=8))            # UHF whip

    # security fence. An LF reads from the air as a fenced square of gravel
    # with one slab in it; without the fence it is just a disc on a plate.
    use("gun")
    n = 7
    for i in range(n):
        t = -FENCE + 2 * FENCE * i / float(n - 1)
        for s in (-1, 1):
            p.append(cube((t, s * FENCE, 1.05), (0.16, 0.16, 1.78)))
            if 0 < i < n - 1 and not (s < 0 and abs(t) < 0.1):    # gate gap
                p.append(cube((s * FENCE, t, 1.05), (0.16, 0.16, 1.78)))
    for s in (-1, 1):
        for zr in (0.98, 1.86):
            p.append(cube((0, s * FENCE, zr), (2 * FENCE, 0.09, 0.10)))
            p.append(cube((s * FENCE, 0, zr), (0.09, 2 * FENCE, 0.10)))

    use("team")
    p.append(cube((-4.0, 9.0, 0.24), (2.80, 2.00, 0.12)))
    use("body")
    return p, dict(top=0.18, hull_l=APRON, hull_w=APRON, turret_top=1.9,
                   gun_z=1.0, gun_y=0.0)


# ── road-mobile launcher ───────────────────────────────────────────
def mobile_tel():
    """Road-mobile ICBM transporter-erector-launcher, 15U175 / MZKT-79221
    scale. Eight axles, one very large canister. No armour worth modelling:
    anything that hits it kills it, so the entire contest is LOCATING it
    before it fires (docs/15).

    The erected state is deliberately not the default — raising the canister is
    a huge signature and a real vulnerability window.

    Identification, in the order a player sees it:
      * a canister longer than the truck, its ogive nose overhanging the front
        and its gas-generator closure overhanging the rear
      * two narrow cabs flanking that nose instead of one wide cab
      * eight axles in a 2 + 2 + 4 group, not eight evenly spaced ones
    Published: chassis 22.7 x 3.40 m, 16x16, 1600x600 tyres. The commonly
    quoted 3.3 m height is the bare chassis; with the canister aboard the
    drawing gives 4.5 m, which is what parade photographs show.
    """
    HL, HW, CL = 22.70, 3.40, 0.64
    top = 1.64                                                    # frame deck
    CAN_R, CAN_Z = 1.12, 3.37                                     # canister
    NOSE = -HL / 2 - 2.45                                         # ogive tip
    p = []
    # frame, with the underside swept UP at the front. A flat-bottomed box the
    # full length gave the truck no approach angle and put 0.5 m of solid
    # chassis where the drawing has daylight.
    p.append(profile([(-HL / 2, 1.15), (-8.20, CL), (10.00, CL),
                      (HL / 2, 0.95), (HL / 2, top), (-HL / 2, top)],
                     HW, "tel_hull"))

    # ── cab: full-width lower box with two narrow raised cabs either side of
    # the canister nose. That split is the single feature that tells this
    # apart from every other eight-axle truck in the roster.
    p.append(cube((0, -HL / 2 + 0.96, 1.645), (HW, 1.91, 1.11)))
    for s in (-1, 1):
        p.append(cube((s * 1.26, -HL / 2 + 0.93, 2.445), (0.86, 1.75, 0.49)))
    use("glass")
    for s in (-1, 1):
        p.append(cube((s * 1.26, -HL / 2 + 0.06, 2.46), (0.76, 0.12, 0.34)))
    use("body")
    p.append(cube((0, -HL / 2 + 0.15, 1.30), (HW - 0.10, 0.30, 0.52)))  # bumper
    for s in (-1, 1):
        p.append(cube((s * 1.10, -HL / 2 + 0.12, 1.42), (0.42, 0.16, 0.26)))

    # ── launch canister
    use("deck")
    p.append(cyl((0, NOSE + 13.69, CAN_Z), CAN_R,
                 23.76, rot=(R(90), 0, 0), v=22))                 # body
    p.append(cyl((0, NOSE + 0.905, CAN_Z), CAN_R, 1.81,
                 rot=(R(90), 0, 0), v=22, taper=0.10))            # ogive nose
    p.append(cyl((0, NOSE + 26.23, CAN_Z), 0.885, 1.31,
                 rot=(R(90), 0, 0), v=18))                        # rear closure
    for k in range(8):                                            # stiffeners
        p.append(cyl((0, NOSE + 3.6 + k * 2.85, CAN_Z), CAN_R + 0.045, 0.22,
                     rot=(R(90), 0, 0), v=22))
    use("body")
    p.append(cube((0, 0.80, 1.995), (2.50, 20.40, 0.71)))         # cradle

    # ── deck equipment: the band between frame and canister is solid kit
    for s in (-1, 1):
        for k in range(5):
            p.append(cube((s * 1.46, -8.0 + k * 3.5, 2.00), (0.60, 3.00, 0.72)))
        p.append(cube((s * 1.46, 8.6, 2.06), (0.60, 2.20, 0.84)))
    # rear erector pivot and launch base — the canister rotates about here
    p.append(cube((0, 10.50, 1.55), (2.90, 1.70, 1.95)))
    for s in (-1, 1):
        p.append(cube((s * 1.32, 10.90, 2.45), (0.30, 1.60, 1.50)))
    # levelling jacks, stowed
    for s in (-1, 1):
        for jy in (-7.96, -3.53, 1.38, 10.85):
            p.append(cube((s * 1.60, jy, 1.13), (0.34, 0.40, 1.02)))
            p.append(cube((s * 1.60, jy, 0.70), (0.62, 0.62, 0.22)))
    use("gun")
    for s in (-1, 1):                                             # antennas
        p.append(cyl((s * 1.30, -6.4 + s * 1.6, 2.90), 0.05, 1.60, v=6))
    use("team")
    for s in (-1, 1):                     # on the cab roofs, clear from above
        p.append(cube((s * 1.26, -HL / 2 + 0.93, 2.72), (0.80, 1.60, 0.12)))

    # ── running gear: 2 + 2 + 4, measured off the drawing, not evenly spaced
    use("track")
    WR = 0.805
    for s in (-1, 1):
        x = s * (HW / 2 - 0.16)
        for f in (0.205, 0.294, 0.414, 0.504, 0.624, 0.713, 0.803, 0.893):
            y = -HL / 2 + HL * f
            p.append(cyl((x, y, WR), WR, 0.40, rot=(0, R(90), 0), v=14))
            p.append(cyl((x, y, WR), WR * 0.52, 0.42, rot=(0, R(90), 0), v=12))
    use("body")
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=CAN_Z + CAN_R,
                   gun_z=CAN_Z, gun_y=0.0)


# ── ballistic missile submarine ────────────────────────────────────
def ssbn():
    """Ohio-class scale: 170 m long, 13 m beam. The survivable leg.

    Everything that makes it work is in docs/02 section 8 already — the
    speed-to-noise curve, the layer, passive bearing-only contacts. The one
    thing unique to this hull is the raised missile deck aft of the sail with
    its two rows of tube hatches, which is also the only feature that reads
    from above.

    Stations measured off the Commons port elevation at 11.18 px/m (set by the
    known 13 m beam): parallel middle from 0.18L to 0.72L, sail leading edge
    31.9 m abaft the bow — a QUARTER of the way down the hull, not halfway —
    and the twelve hatches per row spanning 55 to 89 m from the bow.
    """
    L, BEAM = 170.0, 13.0
    AX = BEAM / 2.0                                               # hull axis z
    DECK = 15.00                                                  # casing top
    p = []
    use("body")
    # pressure hull: blunt spherical bow, long parallel middle, tapered tail
    p += revolve(L, AX,
                 ((0.00, 0.28), (0.02, 0.60), (0.04, 0.78), (0.07, 0.90),
                  (0.12, 0.99), (0.18, 1.00), (0.72, 1.00), (0.80, 0.93),
                  (0.86, 0.81), (0.92, 0.63), (0.96, 0.38), (1.00, 0.20)),
                 z=AX, v=24)
    # raised missile casing — 1.4 m proud of the hull crown, blended each end
    p.append(profile([(60.0, 12.10), (53.0, DECK), (-21.0, DECK),
                      (-29.0, 12.10)], 7.00, "casing"))
    # 24 tubes in two rows of twelve, 3.11 m pitch
    use("deck")
    for row in (-1, 1):
        for k in range(12):
            p.append(cyl((row * 2.15, 30.1 - k * 3.11, DECK - 0.22),
                         1.15, 0.70, v=16))
    use("team")
    p.append(cube((0, 37.0, DECK + 0.06), (4.40, 5.00, 0.14)))
    use("body")
    # sail, well forward: leading edge 31.9 m abaft the bow
    p.append(profile([(54.0, 14.20), (44.2, 14.20), (45.1, 21.30),
                      (52.5, 21.30)], 3.40, "sail"))
    for s in (-1, 1):                                             # fairwater planes
        p.append(cube((s * 4.90, 48.40, 18.20), (6.60, 4.40, 0.55)))
    use("gun")
    for k in range(3):                                            # masts
        p.append(cyl((0.0, 46.6 + k * 1.8, 25.05), 0.28, 7.70, v=12))
    use("body")
    # stern control surfaces, cruciform, tips inside the hull envelope
    for s in (-1, 1):
        p.append(cube((s * 5.40, -78.40, AX), (7.80, 5.60, 0.70)))
    p.append(profile([(-69.5, 7.60), (-81.6, 7.60), (-81.2, 12.90),
                      (-75.6, 12.60)], 0.95, "rudder"))
    p.append(profile([(-69.5, 5.40), (-81.6, 5.40), (-81.2, 0.25),
                      (-75.6, 0.55)], 0.95, "lower_rudder"))
    use("gun")
    # single seven-bladed screw, not a pump-jet duct: the Ohio predates those
    p.append(cyl((0, -85.75, AX), 1.30, 1.50,
                 rot=(R(90), 0, 0), v=16, taper=0.30))            # hub
    for k in range(7):
        a = 2.0 * math.pi * k / 7.0
        p.append(cube((1.75 * math.sin(a), -85.40, AX + 1.75 * math.cos(a)),
                      (0.14, 0.95, 3.10), rot=(0, a, 0)))
    use("body")
    return p, dict(top=DECK, hull_l=L, hull_w=BEAM, turret_top=21.30,
                   gun_z=DECK, gun_y=13.0)


STRATEGIC = [
    ("str_e2_us_silo",     missile_silo, "camo_us"),
    ("str_e5_us_tel",      mobile_tel,   "camo_us"),
    # sub_dark, not air_dark: same reasoning as the navy submarines — the
    # aircraft scheme's baked panel speckle reads as stone masonry at a
    # 170 m hull's camo scale, and tone is the sub-vs-surface cue.
    ("str_e3_us_ssbn",     ssbn,         "sub_dark"),
]


# ── texture pass (2026-08): composed-texture REQUESTS, roster data only ──
# Build-space metres, Z-up, forward = -Y. Three basing modes, three surface
# languages, each borrowed from the module that owns that language:
#   silo  -> structure_models: weathered concrete, near-flat, faction star
#            stencilled on the apron (its position is public knowledge — the
#            marking gives the flat pad an owner at gameplay zoom)
#   tel   -> army_models: dusty wheeled vehicle, panel seams, subdued star
#            on the cab side; the canister keeps its stiffener pitch as the
#            deck-group panel spacing so the bands read as real seams
#   ssbn  -> navy_models _sub_tex: dark, near-uniform, tight 3.5 m tile,
#            subtle scupper streaking off the missile casing, hull number
#            on the sail — nothing else, a boomer is FEATURELESS by design
_STAR = (0.14, 0.13, 0.12)          # subdued CARC-black star
_DUST = (0.50, 0.44, 0.34)          # desert dust
_STENCIL = (0.90, 0.90, 0.87)

# silo: the apron IS the unit. Concrete mottle on the up-facing pour, rain
# streaks down the (few) vertical faces, grime pooled where the AO bake is
# already dark (door rails, collar base), and the star on open apron clear
# of the door rails, valves and headworks.
H.texture_features(
    "str_e2_us_silo",
    size_class="structure", groups=("body", "deck"),
    panels=dict(spacing=4.0, strength=0.34, jitter=0.08, seams=0.40),
    concrete=dict(roof_above=2.0, gravel=0.0, wall=0.13, apron=0.10),
    weathering=dict(
        dust=dict(height=0.55, strength=0.26, tint=(0.36, 0.33, 0.26)),
        ao_grime=dict(strength=0.34, threshold=0.55),
        edge_wear=dict(strength=0.30)),
    groups_override={"deck": dict(
        # the headworks cap, collar and closure door: first render came out
        # a jet-black slab — smooth pour at the 0.098 deck albedo has no
        # paintable variation. Give the up-facing pour the structures' roof
        # treatment instead (gravel grain + mean lift, structure_models
        # _TEX_GRAVEL scale), and the fortification family's pale lime
        # rain-wash on the vertical door sides — a dark streak on near-black
        # concrete is unpaintable.
        panels=dict(spacing=3.0, strength=0.30, jitter=0.06, seams=0.36),
        concrete=dict(roof_above=0.4, gravel=0.13, gravel_lift=1.55,
                      gravel_scale=0.40, wall=0.14, apron=0.22,
                      apron_lift=1.30),
        weathering=dict(
            ao_grime=dict(strength=0.36, threshold=0.58,
                          tint=(0.052, 0.050, 0.046)),
            streaks=dict(z0=2.30, length=2.2, density=0.36, strength=0.28,
                         tint=(0.155, 0.150, 0.135)),
            edge_wear=dict(strength=0.24)))},
    insignia=[dict(kind="star_us", center=(-2.3, -7.6, 0.19),
                   normal=(0, 0, 1), up=(0, -1, 0), size=3.0,
                   alpha=0.80, color=_STAR)])

# TEL: an army vehicle request (cf. army_models._us_ground), plus a deck
# override that pins the canister's panel spacing to its 2.85 m stiffener
# pitch so the compose seams land between the modelled bands.
H.texture_features(
    "str_e5_us_tel",
    size_class="vehicle", groups=("body", "deck"),
    panels=dict(spacing=2.0, strength=0.50, jitter=0.12, seams=0.55),
    weathering=dict(
        dust=dict(height=1.7, strength=0.60, tint=_DUST),
        edge_wear=dict(strength=0.5)),
    groups_override={"deck": dict(
        panels=dict(spacing=2.85, strength=0.45, jitter=0.03, seams=0.50))},
    insignia=[dict(kind="star_us", center=( 1.70, -10.35, 1.70),
                   normal=( 1, 0, 0), size=0.50, alpha=0.85, color=_STAR),
              dict(kind="star_us", center=(-1.70, -10.35, 1.70),
                   normal=(-1, 0, 0), size=0.50, alpha=0.85, color=_STAR)])

# SSBN: navy_models._sub_tex verbatim, with this hull's stations. Sail body
# spans y 44.2..54.0, x half-width 1.70, cap at 21.3; casing top at 15.0.
# Streaks run from the casing edge, not the sail top — the missile deck is
# what weathers on an Ohio's turtleback.
H.texture_features(
    "str_e3_us_ssbn",
    size_class="ship", res=1024, groups=("body",),
    camo_scale=3.5,
    panels=dict(spacing=3.0, strength=0.28, jitter=0.04, seams=0.25,
                width=0.22),
    weathering=dict(
        streaks=[dict(z0=15.35, length=3.0, density=0.30,
                      strength=0.35, tint=(0.26, 0.18, 0.12))],
        edge_wear=dict(strength=0.30)),
    insignia=[dict(kind="pennant", text="726", color=_STENCIL, alpha=0.96,
                   center=( 1.70, 49.1, 18.1), normal=( 1, 0, 0), size=2.4),
              dict(kind="pennant", text="726", color=_STENCIL, alpha=0.96,
                   center=(-1.70, 49.1, 18.1), normal=(-1, 0, 0), size=2.4)])

if __name__ == "__main__":
    H.set_out(os.path.join(ROOT, "art", "blockout", "e4_strategic"))
    for name, _, camo in STRATEGIC:
        H.CAMO[name] = camo
        H.TEAM[name] = (0.06, 0.20, 0.62)
    print("building strategic triad...")
    for name, fn, _ in STRATEGIC:
        for lod in (0, 1, 2):
            n = H.build(name, fn, lod)
            print(f"  {name:22s} LOD{lod}  {n:6d} tris")
    print("done")
