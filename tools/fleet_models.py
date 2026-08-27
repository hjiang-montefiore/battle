"""Parametric builders for the rest of the roster, reusing the hero pipeline.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/fleet_models.py

Everything here goes through the SAME code as the three reference heroes —
same running gear, same AO bake, same socket contract, same artifact-level
COLOR_0 verification. That is the point of doing it parametrically: a quality
fix made in hero_models.py propagates to every role instead of needing 86
repeats.

Target is the minimum playable set from docs/12-unit-roster.md — the 14 roles
that exercise all seven pillars in one 20-minute match.

DIMENSIONS
----------
No orthographic 3-view line drawing exists on Wikimedia Commons for any of
these eight vehicles (searched 2026-08-26: the only ground-vehicle hits are
photographs and one photo-trace, and verify_shape.py correctly refuses those).
So every number below is a PUBLISHED SPECIFICATION, named in the docstring of
the builder that uses it, and the model is checked against it by measuring the
exported GLB's bounding box rather than by silhouette IoU.

ORIENTATION
-----------
Blender -Y is FORWARD. Rx(a) maps +Z to (0, -sin a, cos a) and +Y to
(0, cos a, sin a). Getting that backwards is how the MLRS ended up firing
over its own cab and the illuminator ended up with its dish facing away from
its own feed horn; both are fixed here.
"""
import bpy, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_models as H
from hero_models import (cube, cyl, dome, profile, use, running_gear,
                         barrel, detail_kit, R)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


# ── wheeled running gear (trucks, radar vehicles, launchers) ────────
def wheeled_gear(hull_l, hull_w, clearance, axles, wheel_r, first=0.30, last=0.88,
                 at=None):
    """`at` overrides the even spacing with explicit fractions of hull length.

    Real multi-axle trucks are not evenly spaced — a HEMTT is two close pairs
    with a long gap amidships, and that grouping is most of what makes an 8x8
    read as an 8x8 rather than as a centipede. Defaults are unchanged, so
    army_models and strategic_models keep the exact geometry they had.
    """
    parts = []
    fr = list(at) if at else [first + (last - first) * (i / max(1, axles - 1))
                              for i in range(axles)]
    use("track")
    for s in (-1, 1):
        x = s * (hull_w / 2 - 0.16)
        for f in fr:
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


# ── truck construction kit ─────────────────────────────────────────
# A truck is a NARROW ladder frame carried on wheels that stand clear of it,
# with the body above deck height. Every wheeled unit here used to be one
# full-width box extruded from near the ground, which swallowed the wheels and
# made all five of them read as bricks with dots on the side.

def truck_frame(hull_l, hull_w, clearance, deck, deck_y=0.0, deck_len=0.88):
    """Ladder frame plus a full-width deck plate. Returns (parts, frame_half_w)."""
    fhw = min(hull_w * 0.38, 0.95)
    p = [cube((0, 0, (clearance + deck) / 2),
              (fhw * 2, hull_l * 0.97, deck - clearance)),
         cube((0, hull_l * deck_y, deck - 0.07),
              (hull_w * 0.94, hull_l * deck_len, 0.14))]
    return p, fhw


def truck_axles(hull_l, hull_w, at, wheel_r):
    """Axle tubes and differentials — what ties the wheels to the frame."""
    p = []
    for f in at:
        y = -hull_l / 2 + hull_l * f
        p.append(cyl((0, y, wheel_r), 0.095, hull_w - 0.36,
                     rot=(0, R(90), 0), v=8))
        p.append(cube((0, y, wheel_r + 0.10), (0.46, 0.44, 0.62)))
    return p


def pane(y0, z0, y1, z1, w, out=0.045, thick=0.05):
    """Glass panel along a raked profile edge, running from (y0,z0) to (y1,z1).

    Glass is the cheapest possible cue that one end of a box is a CAB. At the
    scale an RTS renders these, it does more work than any amount of panel
    detail.
    """
    dy, dz = y1 - y0, z1 - z0
    L = math.hypot(dy, dz)
    a = -math.atan2(dy, dz)                       # Rx(a): +Z -> along the edge
    cy = (y0 + y1) / 2 - dz / L * out             # push out along the normal
    cz = (z0 + z1) / 2 + dy / L * out
    use("glass")
    o = cube((0, cy, cz), (w, thick, L * 0.92), rot=(a, 0, 0))
    use("body")
    return o


def truck_cab(y0, y1, deck, roof, w, hood=1.05, rake=0.46, sill=0.58,
              name="cab"):
    """Bonneted cab: hood, raked windscreen, boxy crew compartment, side glass."""
    p = []
    hz = deck + sill
    p.append(profile([(y0, deck), (y0, hz), (y0 + hood, hz),
                      (y0 + hood + rake, roof), (y1, roof), (y1, deck)],
                     w, name))
    p.append(pane(y0 + hood, hz, y0 + hood + rake, roof, w * 0.82))
    use("glass")
    back = y0 + hood + rake
    for s in (-1, 1):
        p.append(cube((s * (w / 2 - 0.01), (back + y1) / 2, roof - 0.44),
                      (0.06, (y1 - back) * 0.70, 0.52)))
    use("body")
    return p


def armour_cab(y0, y1, deck, roof, w, slope=0.55, sill=0.42, name="cab"):
    """Forward-control armoured cab — flat front, one sloped glacis-screen."""
    p = [profile([(y0, deck), (y0, deck + sill), (y0 + slope, roof),
                  (y1, roof), (y1, deck)], w, name)]
    p.append(pane(y0, deck + sill, y0 + slope, roof, w * 0.80))
    use("glass")
    for s in (-1, 1):
        p.append(cube((s * (w / 2 - 0.01), (y0 + slope + y1) / 2, roof - 0.40),
                      (0.06, (y1 - y0 - slope) * 0.62, 0.46)))
    use("body")
    return p


def outriggers(deck, ys, fhw):
    """Deployed stabiliser jacks. A radar or a launcher that has stopped to do
    its job always has these down, and a plain truck never does — so they are
    free 'this vehicle is emplaced' signalling."""
    p = []
    for s in (-1, 1):
        for y in ys:
            p.append(cube((s * (fhw + 0.22), y, deck - 0.34), (0.68, 0.24, 0.22)))
            p.append(cube((s * (fhw + 0.52), y, (deck - 0.42) / 2 + 0.06),
                          (0.20, 0.26, deck - 0.42)))
            p.append(cyl((s * (fhw + 0.52), y, 0.07), 0.30, 0.14, v=10))
    return p


# ── tracked armoured family ────────────────────────────────────────
def ifv():
    """Infantry fighting vehicle, M2A3 pattern.

    Published: 6.55 m long, 3.60 m wide, 2.98 m to the turret roof, six road
    wheels. Identifying features: turret OFFSET RIGHT to clear the troop bay,
    25 mm autocannon, twin TOW box on the turret's LEFT cheek, rear ramp.
    """
    HL, HW, CL, HH = 6.55, 3.60, 0.44, 1.40
    p = []
    h, top = boxhull(HL, HW, CL, HH, 1.55, "ifv_hull")
    p.append(h)
    ROOF = 2.98
    TX = 0.30                       # turret offset right
    p.append(profile([(-0.95, top), (-0.80, ROOF - 0.12), (0.85, ROOF),
                      (1.30, ROOF - 0.16), (1.30, top)], 1.90, "ifv_turret"))
    p[-1].location.x = TX
    p.append(cube((TX, -0.62, top + 0.56), (0.64, 0.58, 0.50)))     # mantlet
    # The M242 is a 2.7 m tube and on the real vehicle its muzzle clears the
    # nose by only ~0.25 m — the published 6.55 m is very nearly hull alone.
    gun = barrel(-3.52, top + 0.60, 2.62, 0.048, 0.55, 0.070)
    for g in gun:                   # the WHOLE gun follows the turret offset.
        g.location.x += TX          # shifting only the bore disc left it
    p += gun                        # floating 0.42 m off the muzzle.
    use("deck")
    p.append(cube((TX - 1.10, 0.22, ROOF - 0.32), (0.52, 1.10, 0.68)))  # TOW box
    for k in (-1, 1):                                            # two tube mouths
        p.append(cyl((TX - 1.10 + k * 0.13, -0.33, ROOF - 0.32), 0.14, 0.26,
                     rot=(R(90), 0, 0), v=10))
    use("body")
    p.append(cube((0, HL / 2 - 0.09, top - 0.52), (HW * 0.70, 0.18, 1.10)))  # ramp
    # mg=False: the Bradley's 7.62 is a turret coax, not a pintle gun, and the
    # pintle version pushed the model 15% over its published 2.98 m height.
    p += detail_kit(HL, HW, top, ROOF, -0.95, 1.30, era=0, mg=False)
    p += running_gear(HL, HW, CL, 6, 0.31, 0.50)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 0.60, gun_y=-0.95)


def recon_wheeled():
    """Reconnaissance vehicle, M1127 Stryker RV pattern.

    Published (Stryker/LAV III): 6.95 m long, 2.72 m wide, 2.64 m over the
    remote weapon station, 8x8 on 1.1 m tyres in two close pairs. Same chassis
    figures as army_models' IM-SHORAD, deliberately — they are the same
    vehicle family and should read as one.

    NOT an M113: army_models already fields that hull three times (APC, M901
    ITV, mortar carrier), and the ITV is specifically an M113 with a mast, so
    a tracked masted scout would have been unreadable next to it.

    Identifying feature: the two-stage TELESCOPING SENSOR MAST with an LRAS3
    head, deployed. It is passive — it feeds the track table without
    radiating — so the mast, not a radar face, is what a player reads.
    Published height is the 2.64 m hull; the mast is deployed equipment and
    stands well above it, exactly as on the real vehicle.
    """
    HL, HW, CL, HH = 6.95, 2.72, 0.46, 1.54
    p = []
    h, top = boxhull(HL, HW, CL, HH, 1.05, "rec_hull")          # roof at 2.00
    p.append(h)
    ROOF = top + 0.62                                           # 2.62 published
    use("deck")
    p.append(cube((0.52, -1.10, top + 0.31), (0.88, 0.94, 0.62)))   # weapon station
    p.append(cube((-0.52, -0.35, top + 0.05), (0.92, 1.10, 0.10)))  # crew hatch
    use("body")
    p.append(dome((0.52, -1.52, top + 0.50), 0.22, 0.24, 0.20, v=14))  # day/night
    use("gun")
    p.append(cyl((0.52, -1.90, top + 0.46), 0.042, 1.10,
                 rot=(R(90), 0, 0), v=8))                           # .50 cal
    use("deck")
    MX, MY = -0.60, 1.30
    p.append(cyl((MX, MY, top + 0.55), 0.105, 1.10, v=8))           # mast, stage 1
    p.append(cyl((MX, MY, top + 1.45), 0.070, 1.00, v=8))           # stage 2
    p.append(cube((MX, MY, top + 2.10), (0.58, 0.38, 0.36)))        # LRAS3 head
    p.append(cyl((MX, MY - 0.27, top + 2.10), 0.12, 0.26,
                 rot=(R(90), 0, 0), v=10))                          # optic
    use("body")
    for s_ in (-1, 1):                                     # ESM direction finders
        p.append(cyl((s_ * 1.06, HL * 0.30, top + 0.44), 0.040, 0.88, v=6))
    p.append(cube((0, HL / 2 - 0.10, top - 0.70), (HW * 0.68, 0.16, 1.05)))  # ramp
    p += detail_kit(HL, HW, top, top, -1.25, -0.35, era=0, mg=False)
    p += wheeled_gear(HL, HW, CL, 4, 0.55, at=(0.14, 0.31, 0.62, 0.79))
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 0.46, gun_y=-1.10)


def sph():
    """Self-propelled howitzer, M109A6 pattern.

    Published: hull 6.19 m, 9.68 m gun forward, 3.15 m wide, 3.28 m over the
    cupola, SEVEN road wheels. The turret is enormous relative to the hull —
    near full width, near-vertical sides, deep rear bustle. That IS its
    silhouette. Shoot-and-scoot, because counter-battery radar exists.

    ── SILHOUETTE RULE (paired with mlrs(), which see) ────────────────
    This unit OWNS THE LONG FORWARD GUN OVERHANG: 3.50 m of barrel projecting
    past the hull nose, so a 6.20 m hull sits inside a 9.70 m plan length. Its
    mass is LOW, FORWARD and HORIZONTAL, and the barrel is the one part of it
    that reaches outside the body outline where nothing can occlude it.

    The MLRS is the deliberate inverse — HIGH, AFT and VERTICAL — and the two
    must stay that way. Do not elevate this gun above travelling height to
    make it look busier: the horizontal spike IS the read, and tilting it up
    shortens the plan length that separates this vehicle from every other
    tracked box in the roster.
    """
    HL, HW, CL, HH = 6.20, 3.15, 0.45, 1.35                     # top 1.80
    p = []
    h, top = boxhull(HL, HW, CL, HH, 1.20, "sph_hull")
    p.append(h)
    ROOF = 2.85
    p.append(profile([(-1.55, top + 0.05), (-1.40, ROOF), (1.55, ROOF),
                      (2.05, ROOF - 0.35), (2.05, top), (-1.10, top)],
                     2.92, "sph_turret"))
    p.append(cube((0, -1.92, top + 0.62), (0.98, 0.90, 0.92)))      # mantlet
    Y_TIP, GZ = -(HL / 2 + 3.50), top + 0.62                    # 9.70 m overall
    p += barrel(Y_TIP, GZ, 4.55, 0.098, 1.10, 0.140)
    use("gun")
    for dy in (0.20, 0.52):                     # double-baffle muzzle brake —
        p.append(cyl((0, Y_TIP + dy, GZ), 0.175, 0.22,          # this used to
                     rot=(R(90), 0, 0), v=14))                  # sit 1.7 m
    use("body")                                                 # ahead of the
    p.append(cube((0, -2.75, 2.28), (0.54, 0.24, 0.26)))        # muzzle, loose
    for s in (-1, 1):                                           # gun travel lock
        p.append(cube((s * 0.30, -2.75, (top + 2.20) / 2), (0.15, 0.18,
                                                            2.20 - top)))
    p.append(cyl((0.62, -0.35, ROOF + 0.17), 0.44, 0.34, v=14))     # cupola
    p.append(cyl((0.62, -0.62, ROOF + 0.30), 0.075, 0.42, v=8))     # pintle post
    use("gun")
    p.append(cyl((0.62, -1.10, ROOF + 0.50), 0.045, 1.10,
                 rot=(R(90), 0, 0), v=8))                           # .50 cal
    p.append(cube((0.62, -0.42, ROOF + 0.45), (0.20, 0.32, 0.22)))
    use("body")
    p += detail_kit(HL, HW, top, ROOF, -1.55, 2.05, era=0, mg=False)
    p += running_gear(HL, HW, CL, 7, 0.33, 0.58)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=GZ, gun_y=-1.90)


def mlrs():
    """Rocket artillery, M270 pattern on the IFV chassis.

    Published: 6.97 m long, 2.97 m wide, 2.59 m high TRAVELLING, six road
    wheels. Armoured cab forward, loader-launcher module aft holding two
    six-round pods — twelve tubes, six across and two high.

    The module elevates and fires REARWARD, over the tail. It was tilted the
    other way, so the vehicle aimed its rockets through its own cab; that fix
    is kept and this one builds on top of it.

    MODELLED DEPLOYED at 57 deg, of the real vehicle's 60 deg maximum, for the
    same reason the towed gun and the coastal battery are modelled deployed:
    this vehicle only matters when it has stopped to shoot. It was the last
    fires/AD role still modelled effectively stowed. Measured across the built
    roster at LOD1, every other role that emplaces to do its job stands
    4.3-5.4 m — long SAM 5.35, jammer 5.26, ballistic 5.13, search radar 5.08,
    SAM launcher 4.90, counter-battery 4.59, spaag 4.57, coastal 4.34 — while
    this one sat at 2.91 m, the shortest of the group by 1.4 m, and was the
    weakest ground read in the roster because of it.

    The published 2.59 m is the TRAVELLING height and is still exactly what the
    hull and cab measure here; the module above it is deployed equipment and
    stands clear of it, precisely as the recon vehicle's mast does. No
    real-world dimension is faked: hull 6.97 x 2.97 m is unchanged.

    ── SILHOUETTE RULE (do not let these converge again) ──────────────
    This unit OWNS, exclusively in the ground roster:

        A TALL RAISED SLAB CARRIED AFT ON A TRACKED HULL, notched down its
        centreline, leaning back at ~57 deg with twelve bores at its top edge.

    Three claims, each separately checked, hold that rule up:

      * TRACKED + TALL. Every other unit over 4.3 m tall is a wheeled truck
        (long SAM, ballistic, coastal, counter-battery, jammer, search radar,
        SAM launcher). The only other tall tracked vehicle is the SPAAG, and
        that is a turret with guns hung OUTBOARD, not a slab.
      * THICK, NOT FLAT. The radar family owns thin planar panels — the search
        array is 0.26 m thick. This module is a 0.86 m box carrying 0.90 m pods,
        ~1.5 m through, so from the RTS three-quarter its SIDE has real area
        while a radar panel collapses to a line.
      * A QUARTER OF THE VEHICLE IS DARK. The two six-round pods are `deck`
        material, and from the RTS camera they are 26.4% of every pixel this
        vehicle paints, against 4.1% before the change and 0.0% on the SPH,
        which is 92.4% pale body camo. That is criterion 4 — a big flat area
        of a different material group — and it is the read that survives
        furthest out, because a value step does not need resolution.
        The 0.36 m channel between the pods (just over 1/20th of the 6.97 m
        length, this project's floor for a feature that counts) splits that
        dark area in two. Be honest about what it does: the module is
        narrower than the hull, so the channel is a hole in the SHADING, not
        a notch in the outline — a flat black top-down silhouette of this
        vehicle is still a rectangle and always will be, because the hull is
        the widest thing on it. The channel earns its place in the lit render,
        which is the only place the player ever sees it.

    And what the neighbour owns, so neither drifts into the other:

        art_e4_us_sph OWNS THE LONG FORWARD GUN OVERHANG — 3.50 m of barrel
        outside the hull nose, a 6.20 m hull inside a 9.70 m plan length. The
        SPH's mass is LOW, FORWARD and HORIZONTAL. The MLRS's mass is HIGH,
        AFT and VERTICAL. They are deliberate opposites, and that is the whole
        of the separation: it does not depend on the tube mouths, which at
        0.31 m across are 1/22nd of the vehicle and do not count on their own.

    Do NOT give the MLRS a barrel, and do NOT elevate the SPH's gun above
    travelling height. Either one collapses the pair back to 0.80 IoU.

    MEASURED, LOD1, on the exported GLBs (three-quarter view at the army
    lineup's own camera, 37 deg elevation, 30 deg yaw):

        bounding box     2.97 x 6.96 x 2.91 m  ->  2.97 x 6.96 x 5.16 m
                         (width and length UNCHANGED; only deployed
                         equipment moved)
        triangles        LOD0 52484 -> 54828, LOD1 10312 -> 10788,
                         LOD2 344 -> 364      (LOD1 stays inside 8-15k)
        outline area     21.21 -> 24.11 m2, of which 3.36 m2 is new outline
                         standing where the old model drew nothing at all
        silhouette IoU   against art_e4_us_sph: 0.796 -> 0.711 front-quarter,
                         0.622 -> 0.583 rear-quarter. IoU understates this
                         badly and is recorded so nobody re-derives it and
                         panics: the two share an identical tracked hull, and
                         the hull is most of the pixels. The change is in the
                         3.36 m2 that is NOT hull.
    """
    HL, HW, CL, HH = 6.97, 2.97, 0.46, 1.10                     # top 1.56
    p = []
    h, top = boxhull(HL, HW, CL, HH, 1.60, "mlrs_hull")
    p.append(h)
    CAB = 2.51
    p += armour_cab(-HL / 2 + 0.14, -0.80, top, CAB, 2.62, 0.58, 0.42,
                    "mlrs_cab")
    # Sunk into the deck and overlapping the bed above it: at LOD2 the 0.09
    # decimation walks vertices, and anything that merely TOUCHES its
    # neighbour comes apart into a floating island.
    p.append(cyl((0, 0.55, top + 0.02), 1.24, 0.40, v=16))          # traverse ring
    p.append(cube((0, 0.55, top + 0.26), (2.30, 1.90, 0.44)))       # trunnion bed

    E = R(57)                             # DEPLOYED. Real M270 maximum is 60.
    TY, TZ = -0.32, top + 0.56            # trunnion, at the module's FORWARD end
    uy, uz = math.cos(E), math.sin(E)     # up the module: aft and up
    vy, vz = -math.sin(E), math.cos(E)    # across it
    LM, MW, TH = 3.00, 2.42, 0.86         # module length, width, thickness

    def at(a, b=0.0):
        """A point a metres up the module and b metres across it."""
        return TY + a * uy + b * vy, TZ + a * uz + b * vz

    # The module pivots about its FORWARD trunnion, so elevating raises the
    # muzzle end instead of driving the breech end down through the hull deck.
    ry, rz = at(LM / 2)
    use("deck")
    p.append(cube((0, *at(LM / 2, -0.35)), (MW, LM, 0.16), rot=(E, 0, 0)))
    use("body")
    for s in (-1, 1):                     # cage side rails — the module is an
        p.append(cube((s * 1.12, ry, rz), (0.18, LM, TH),          # open frame,
                      rot=(E, 0, 0)))                              # not a box
    p.append(cube((0, *at(0.26)), (2.46, 0.52, 0.94), rot=(E, 0, 0)))  # breech end
    for s in (-1, 1):                                              # trunnion pins
        p.append(cyl((s * 1.26, *at(0.26)), 0.16, 0.30,
                     rot=(0, R(90), 0), v=10))
    for s_ in (-1, 1):                    # elevating rams. They are what makes
        ay, az = at(1.30, -0.30)          # the raised module read as JACKED UP
        by, bz = 0.30, top - 0.05         # rather than as a fixed superstructure
        L = math.hypot(ay - by, az - bz)
        p.append(cyl((s_ * 0.98, (ay + by) / 2, (az + bz) / 2), 0.11, L,
                     rot=(-math.atan2(ay - by, az - bz), 0, 0), v=10))

    A0, A1 = 0.42, LM + 0.14              # pods, standing proud of the cage aft
    use("deck")                           # dark: a big flat area of a different
    for s in (-1, 1):                     # material group, tilted to face the
        p.append(cube((s * 0.695, *at((A0 + A1) / 2)),             # RTS camera
                      (1.03, A1 - A0, 0.90), rot=(E, 0, 0)))
    fy, fz = at(A1)                       # muzzle face of the pods
    use("gunbore")
    for c in (-1.035, -0.695, -0.355, 0.355, 0.695, 1.035):
        for r in (-0.20, 0.20):           # twelve bores, six across and two
            p.append(cyl((c, fy + r * vy - 0.03 * uy,              # high, split
                          fz + r * vz - 0.03 * uz), 0.155, 0.34,   # 3+3 by the
                         rot=(E - R(90), 0, 0), v=10))             # pod channel
    use("body")
    p += detail_kit(HL, HW, top, CAB, -2.60, -1.10, era=0, mg=False)
    p += running_gear(HL, HW, CL, 6, 0.32, 0.56)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=fz + 0.44,
                   gun_z=fz, gun_y=fy)


# ── wheeled family ─────────────────────────────────────────────────
def search_radar():
    """Long-range search radar on an 8x8 HEMTT-class chassis.

    Chassis follows the M977 family: 10.17 m long, 2.50 m wide, cab 2.54 m,
    four axles in two close pairs. max_quality = TRACK — it finds things and
    cannot guide a weapon. The array ROTATES only while EMCON is RADIATE,
    which is how a player sees emission state.

    Silhouette rule for the battery: RECTANGLE = search, DISH = fire control.
    A player has to be able to call that at a glance, so the array is a large
    flat planar face and the illuminator gets a round one.
    """
    HL, HW, CL, DECK = 10.10, 2.50, 0.78, 1.42
    AXLES = (0.13, 0.265, 0.665, 0.80)
    p = []
    frame, fhw = truck_frame(HL, HW, CL, DECK, deck_y=0.04, deck_len=0.86)
    p += frame
    CAB = DECK + 1.12
    p += truck_cab(-HL / 2 + 0.15, -1.85, DECK, CAB, 2.36, 1.10, 0.48, 0.60,
                   "srad_cab")
    p.append(cube((0, -0.55, DECK + 0.64), (2.34, 2.10, 1.28)))   # crew shelter
    p.append(cyl((0, 2.60, DECK + 0.28), 1.05, 0.56, v=16))       # turntable
    p.append(cyl((0, 2.60, DECK + 1.10), 0.42, 1.24, v=12))       # pedestal
    T = R(-18)                                          # array tilted back 18 deg
    ny, nz = -math.cos(T), -math.sin(T)                 # face normal, fwd and up
    uy, uz = -math.sin(T), math.cos(T)                  # up the face
    AY, AZ = 2.60, 3.62
    use("deck")
    p.append(cube((0, AY, AZ), (4.20, 0.26, 3.00), rot=(T, 0, 0)))
    for k in range(5):                                            # radiating bars
        hgt = -1.20 + k * 0.60
        p.append(cube((0, AY + hgt * uy + 0.16 * ny, AZ + hgt * uz + 0.16 * nz),
                      (3.90, 0.16, 0.14), rot=(T, 0, 0)))
    use("body")
    p += outriggers(DECK, (-0.90, 4.30), fhw)
    p += detail_kit(HL, HW, DECK, CAB, -3.90, -2.40, era=0, mg=False)
    p += truck_axles(HL, HW, AXLES, 0.60)
    p += wheeled_gear(HL, HW, CL, 4, 0.60, at=AXLES)
    return p, dict(top=DECK, hull_l=HL, hull_w=HW, turret_top=AZ + 1.47,
                   gun_z=AZ, gun_y=AY)


def illuminator():
    """Fire-control / illuminator radar on a 6x6.

    Chassis follows the M977 family shortened to three axles: 8.20 m long,
    2.50 m wide, cab 2.48 m. max_quality = FIRE_CONTROL, so this is the
    vehicle to kill — and the thing anti-radiation missiles home on.

    Signature: one big PARABOLIC DISH with a prime-focus feed horn on the axis
    (2.60 m dish, 1.05 m focal boom — the real 0.4 D ratio), an IFF bar across
    the top, and no rectangular array anywhere. The dish used to face away
    from its own feed horn.
    """
    HL, HW, CL, DECK = 8.20, 2.50, 0.75, 1.36
    AXLES = (0.15, 0.62, 0.79)
    p = []
    frame, fhw = truck_frame(HL, HW, CL, DECK, deck_y=0.06, deck_len=0.84)
    p += frame
    CAB = DECK + 1.12
    p += truck_cab(-HL / 2 + 0.15, -1.25, DECK, CAB, 2.36, 1.10, 0.48, 0.60,
                   "ill_cab")
    p.append(cube((0, 0.20, DECK + 0.58), (2.30, 1.90, 1.16)))    # crew shelter
    p.append(cyl((0, 2.55, DECK + 0.55), 0.62, 1.10, v=14))       # pedestal
    for s in (-1, 1):                                             # elevation yoke
        p.append(cube((s * 0.66, 2.55, 2.58), (0.16, 0.24, 0.64)))
    T = R(30)                                        # dish faces forward and up
    ny, nz = -math.sin(T), math.cos(T)               # boresight
    uy, uz = math.cos(T), math.sin(T)                # up the dish face
    CY, CZ = 2.55, 2.96
    use("deck")
    p.append(cyl((0, CY - 0.10 * ny, CZ - 0.10 * nz), 1.24, 0.16,
                 rot=(T, 0, 0), v=22))                             # back plate
    p.append(cyl((0, CY + 0.06 * ny, CZ + 0.06 * nz), 0.98, 0.34,
                 rot=(T, 0, 0), v=22, taper=1.33))                 # bowl
    p.append(cyl((0, CY + 0.24 * ny, CZ + 0.24 * nz), 1.30, 0.10,
                 rot=(T, 0, 0), v=22))                             # rim
    use("body")
    p.append(cyl((0, CY + 0.55 * ny, CZ + 0.55 * nz), 0.10, 1.10,
                 rot=(T, 0, 0), v=8))                              # focal boom
    p.append(cyl((0, CY + 1.05 * ny, CZ + 1.05 * nz), 0.15, 0.34,
                 rot=(T, 0, 0), v=10, taper=0.55))                 # feed horn
    p.append(cube((0, CY + 1.36 * uy, CZ + 1.36 * uz), (2.20, 0.16, 0.20),
                  rot=(T, 0, 0)))                                  # IFF bar
    p += outriggers(DECK, (-0.70, 3.45), fhw)
    p += detail_kit(HL, HW, DECK, CAB, -3.10, -1.70, era=0, mg=False)
    p += truck_axles(HL, HW, AXLES, 0.58)
    p += wheeled_gear(HL, HW, CL, 3, 0.58, at=AXLES)
    return p, dict(top=DECK, hull_l=HL, hull_w=HW, turret_top=CZ + 1.46,
                   gun_z=CZ, gun_y=CY)


def sam_launcher():
    """Medium SAM launcher on an 8x8 — launcher ONLY.

    Chassis 9.10 x 2.55 m, cab 2.56 m, four axles in two close pairs. SIX
    4.10 m canisters in a 3-wide by 2-high block, elevated 40 degrees REARWARD
    over the tail, away from the cab; they used to elevate forward, over the
    crew.

    The block is deliberate. army_models' long-range launcher is a Patriot
    pattern — four fat square canisters in ONE flat row at 38 degrees — and a
    player has to be able to tell medium from long range at a glance. More
    rounds, thinner, stacked two deep is what a shorter-legged missile looks
    like, and it is the arrangement every modern medium SAM TEL uses.

    No radar of any kind, anywhere on the vehicle: it needs a search radar to
    find and an illuminator to guide, and that dependency is what creates the
    SEAD duel in docs/02.
    """
    HL, HW, CL, DECK = 9.10, 2.55, 0.80, 1.44
    AXLES = (0.13, 0.265, 0.665, 0.80)
    p = []
    frame, fhw = truck_frame(HL, HW, CL, DECK, deck_y=0.06, deck_len=0.86)
    p += frame
    CAB = DECK + 1.12
    p += truck_cab(-HL / 2 + 0.15, -1.55, DECK, CAB, 2.38, 1.10, 0.48, 0.60,
                   "sam_cab")
    E, CLEN, CR = R(40), 4.10, 0.21
    uy, uz = math.cos(E), math.sin(E)                    # up the launch rail
    vy, vz = -math.sin(E), math.cos(E)                   # across the block
    BY, BZ = 0.10, DECK + 0.48                           # erector hinge
    p.append(cube((0, -0.30, DECK + 0.46), (2.26, 2.60, 0.92)))    # erector base
    my, mz = BY + CLEN / 2 * uy, BZ + CLEN / 2 * uz      # canister mid-length
    use("deck")
    p.append(cube((0, my - 0.46 * vy, mz - 0.46 * vz),
                  (1.94, CLEN * 0.92, 0.28), rot=(E, 0, 0)))       # cradle
    for s_ in (-1, 1):                                             # side rails
        p.append(cube((s_ * 0.92, my, mz), (0.16, CLEN * 0.98, 0.80),
                      rot=(E, 0, 0)))
    use("body")
    for c in (-1, 0, 1):                       # three across, two high = six
        for r in (-0.25, 0.25):
            x = c * 0.50
            cy, cz = my + r * vy, mz + r * vz
            p.append(cyl((x, cy, cz), CR, CLEN, rot=(E - R(90), 0, 0), v=12))
            use("gunbore")
            p.append(cyl((x, cy + (CLEN / 2 - 0.04) * uy,
                          cz + (CLEN / 2 - 0.04) * uz), 0.175, 0.10,
                         rot=(E - R(90), 0, 0), v=12))             # muzzle cap
            use("body")
    p += outriggers(DECK, (-2.60, 3.55), fhw)
    p += detail_kit(HL, HW, DECK, CAB, -3.60, -2.10, era=0, mg=False)
    p += truck_axles(HL, HW, AXLES, 0.60)
    p += wheeled_gear(HL, HW, CL, 4, 0.60, at=AXLES)
    return p, dict(top=DECK, hull_l=HL, hull_w=HW,
                   turret_top=BZ + CLEN * uz, gun_z=mz, gun_y=my)


def fuel_truck():
    """Pillar 4 made physical, M978 pattern.

    Published: 10.17 m long, 2.44 m wide, 2.56 m high, 8x8 with two close
    front axles and two close rear axles, 2 500 US gal. The tank here is
    0.70 m radius over 6.10 m, which is 9.4 m3 — 2 480 gal, the right barrel
    for the right truck. Soft, slow, and often better to kill than the tanks
    it feeds.
    """
    HL, HW, CL, DECK = 10.17, 2.44, 0.72, 1.24
    AXLES = (0.115, 0.245, 0.665, 0.795)
    p = []
    frame, fhw = truck_frame(HL, HW, CL, DECK, deck_y=0.11, deck_len=0.72)
    p += frame
    CAB = DECK + 1.28
    p += truck_cab(-HL / 2 + 0.15, -1.75, DECK, CAB, 2.30, 1.09, 0.45, 0.60,
                   "fuel_cab")
    TY, TR = 1.55, 0.70
    p.append(cyl((0, TY, DECK + TR), TR, 6.10, rot=(R(90), 0, 0), v=20))
    use("deck")
    for k in range(4):                                          # ring stiffeners
        p.append(cyl((0, TY - 2.30 + k * 1.55, DECK + TR), TR + 0.05, 0.10,
                     rot=(R(90), 0, 0), v=20))
    use("body")
    p.append(cube((0, TY - 0.75, DECK + 2 * TR - 0.07), (0.62, 0.72, 0.20)))
    p.append(cyl((0, TY - 0.75, DECK + 2 * TR - 0.02), 0.24, 0.14, v=12))  # manway
    p.append(cube((0, 4.62, DECK + 0.62), (2.16, 0.92, 1.24)))    # pump cabinet
    use("deck")
    for s in (-1, 1):                                             # hose reels
        p.append(cyl((s * 0.86, 4.62, DECK + 1.02), 0.34, 0.34,
                     rot=(0, R(90), 0), v=12))
    use("body")
    p += detail_kit(HL, HW, DECK, CAB, -3.30, -1.90, era=0, mg=False)
    p += truck_axles(HL, HW, AXLES, 0.60)
    p += wheeled_gear(HL, HW, CL, 4, 0.60, at=AXLES)
    return p, dict(top=DECK, hull_l=HL, hull_w=HW, turret_top=DECK + 2 * TR,
                   gun_z=DECK + TR, gun_y=TY)


FLEET = [
    ("afv_e4_us_ifv",        ifv),
    ("rec_e4_us_recon",      recon_wheeled),
    ("art_e4_us_sph",        sph),
    ("art_e4_us_mlrs",       mlrs),
    ("rad_e4_us_search",     search_radar),
    ("rad_e4_us_illuminator", illuminator),
    ("sam_e4_us_launcher",   sam_launcher),
    ("log_e4_us_fueltruck",  fuel_truck),
]


# ── texture pass (2026-08): composed-texture REQUESTS, roster data only ──
# Build-space metres, Z-up, forward = -Y. Same convention as army_models:
# dust rising from the running gear, subdued US stars on vertical plates
# (hull sides, radar-shelter sides, the fuel tank barrel).
_STAR = (0.14, 0.13, 0.12)
_DUST = (0.50, 0.44, 0.34)


def _us_ground(name, x, y, z, size=0.55, dust=0.55, height=1.2, spacing=1.5):
    ins = [dict(kind="star_us", center=( x, y, z), normal=( 1, 0, 0),
                size=size, alpha=0.85, color=_STAR),
           dict(kind="star_us", center=(-x, y, z), normal=(-1, 0, 0),
                size=size, alpha=0.85, color=_STAR)]
    H.texture_features(
        name, size_class="vehicle", groups=("body", "deck"),
        panels=dict(spacing=spacing, strength=0.55, jitter=0.13, seams=0.55),
        weathering=dict(
            dust=dict(height=height, strength=dust, tint=_DUST),
            edge_wear=dict(strength=0.5)),
        insignia=ins)


_us_ground("afv_e4_us_ifv",         1.79, 0.50, 1.30, size=0.60, dust=0.60)
_us_ground("rec_e4_us_recon",       1.36, 0.30, 1.35, size=0.60)
_us_ground("art_e4_us_sph",         1.57, 0.60, 1.20, size=0.55, dust=0.60)
_us_ground("art_e4_us_mlrs",        1.48, 0.60, 1.05, size=0.50, dust=0.60)
_us_ground("rad_e4_us_search",      1.17, -0.55, 2.05, size=0.55)
_us_ground("rad_e4_us_illuminator", 1.15, 0.20, 1.95, size=0.55)
_us_ground("sam_e4_us_launcher",    1.13, -0.30, 1.90, size=0.50)
_us_ground("log_e4_us_fueltruck",   0.70, 1.55, 1.95, size=0.50, dust=0.60)


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
