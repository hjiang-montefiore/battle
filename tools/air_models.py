"""Fixed-wing, rotary and unmanned roles from docs/12-unit-roster.md.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/air_models.py

From an RTS camera an aircraft is read almost entirely by PLANFORM — the wing
outline seen from above. So wing sweep, span and taper carry the identification,
and fuselage detail barely registers. Every role below is shaped around its
planform first.

Six of these twenty carry no meaningful air-to-air armament (AEW&C, AEW
helicopter, electronic attack, tanker, ISR, maritime patrol) and are the most
valuable targets in the sky — docs/12.
"""
import bpy, bmesh, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_models as H
from hero_models import cube, cyl, dome, profile, use, tag, R

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CRUISE = 0.0          # models are authored at z=0; the sim lifts them


def plate(pts_xy, thick, z, name="plate"):
    """Extrude a planform polygon (list of (x, y)) vertically. This is the
    wing/tail primitive — planform is what the RTS camera actually sees."""
    me = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, z - thick / 2)) for (x, y) in pts_xy]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(0, 0, thick), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    return tag(obj)


def wings(root_y, span, root_c, tip_c, sweep, thick, z, name="wing"):
    """Mirrored swept tapered panels. sweep = how far back the tip sits."""
    out = []
    for s in (-1, 1):
        hw = span / 2.0
        pts = [(s * 0.30, root_y),
               (s * hw, root_y - sweep),
               (s * hw, root_y - sweep - tip_c),
               (s * 0.30, root_y - root_c)]
        if s < 0:
            pts.reverse()
        out.append(plate(pts, thick, z, f"{name}_{s}"))
    return out


def fin(y, height, root_c, tip_c, sweep, thick, z=0.0, cant=0.0, offset_x=0.0):
    """A VERTICAL surface: a chord/height polygon in the YZ plane, extruded
    sideways for thickness.

    The previous version built the polygon in XY (the wing plane) and tried to
    rotate and scale it upright, which left every fin lying flat on its side.
    profile() already extrudes a YZ polygon along X — that IS a fin.
    """
    o = profile([(y, z), (y - root_c, z),
                 (y - sweep - tip_c, z + height), (y - sweep, z + height)],
                thick, "fin")
    o.location = (offset_x, 0.0, 0.0)
    if cant:
        o.rotation_euler = (0.0, R(cant), 0.0)
    return o


def fuselage(length, r_mid, nose=0.0, tail=0.0, z=0.0, v=14, name="fus",
             stations=((0.00, 0.05), (0.09, 0.38), (0.22, 0.78), (0.40, 1.00),
                       (0.68, 0.98), (0.85, 0.76), (1.00, 0.40))):
    """Lofted body, nose at +Y, built from cone sections between stations.

    Each station is (fraction along length, radius as a fraction of r_mid), so
    the nose actually comes to a point. The previous version stacked three
    cylinders with an inverted taper and produced a blunt fat tube with visible
    steps. nose/tail are accepted and ignored, for call compatibility.
    """
    out = []
    y_nose = length * 0.5
    for i in range(len(stations) - 1):
        (f0, r0), (f1, r1) = stations[i], stations[i + 1]
        y0 = y_nose - f0 * length
        y1 = y_nose - f1 * length
        seg = y0 - y1
        if seg <= 0:
            continue
        ra = max(r_mid * r0, 0.02)
        rb = max(r_mid * r1, 0.02)
        out.append(cyl((0, (y0 + y1) / 2.0, z), ra, seg,
                       rot=(R(90), 0, 0), v=v, taper=rb / ra))
    return out


def _kit(span, length, z, canopy=True, tanks=0, seats=1):
    p = []
    if canopy:
        cy = length * 0.22
        use("body")                                   # windscreen frame
        p.append(dome((0, cy + 0.15, z + 0.36), 0.56, 1.55 * seats, 0.40, v=16))
        use("glass")
        p.append(dome((0, cy + 0.18, z + 0.40), 0.50, 1.42 * seats, 0.38, v=16))
        use("body")
    for i in range(tanks):
        s = -1 if i % 2 == 0 else 1
        p.append(cyl((s * span * 0.20, -0.4, z - 0.55), 0.30, 3.20,
                     rot=(R(90), 0, 0), v=10))
    return p


# ── combat ─────────────────────────────────────────────────────────
def interceptor():
    """Epoch 1. Short, sharply swept wing, one big intake. Fast, short-legged."""
    L, SPAN = 19.2, 11.7
    p = fuselage(L, 0.82, 0.5, 0.42)
    p += wings(1.2, SPAN, 5.2, 1.6, 4.4, 0.30, 0.0, "w")
    p += wings(-5.8, 6.6, 2.4, 0.9, 1.9, 0.24, 0.0, "h")
    p.append(fin(-5.4, 3.2, 3.0, 1.1, 2.0, 0.24, 0.35))
    use("deck")
    p.append(cyl((0, L * 0.44, 0), 0.66, 0.30, rot=(R(90), 0, 0), v=14))
    use("gun")
    p.append(cyl((0, -L * 0.47, 0), 0.62, 1.10, rot=(R(90), 0, 0), v=14))
    use("body")
    p += _kit(SPAN, L, 0)
    return p, dict(top=0.9, hull_l=L, hull_w=SPAN, turret_top=1.9,
                   gun_z=0.2, gun_y=L * 0.35)


def air_superiority():
    """Large twin-tail fighter. Broad wing, wide-spaced engines."""
    L, SPAN = 19.4, 13.05
    p = fuselage(L, 0.92, 0.48, 0.62)
    p += wings(2.2, SPAN, 6.4, 2.0, 4.0, 0.32, 0.0, "w")
    p += wings(-5.4, 8.6, 3.0, 1.1, 2.0, 0.26, 0.0, "h")
    for s in (-1, 1):
        f = fin(-4.6, 3.5, 3.2, 1.2, 2.2, 0.24, cant=8 * s, offset_x=s * 1.15)
        p.append(f)
    use("gun")
    for s in (-1, 1):
        p.append(cyl((s * 0.72, -L * 0.44, -0.05), 0.52, 2.20,
                     rot=(R(90), 0, 0), v=12))
    use("body")
    p += _kit(SPAN, L, 0, tanks=2)
    return p, dict(top=0.95, hull_l=L, hull_w=SPAN, turret_top=2.1,
                   gun_z=0.2, gun_y=L * 0.35)


def multirole():
    """Single tail, blended body, one engine. Flexible, never best."""
    L, SPAN = 15.0, 9.96
    p = fuselage(L, 0.78, 0.5, 0.55)
    p += wings(0.9, SPAN, 5.0, 1.5, 3.2, 0.28, 0.0, "w")
    p += wings(-4.6, 6.0, 2.2, 0.9, 1.6, 0.22, 0.0, "h")
    p.append(fin(-4.0, 3.1, 3.4, 1.1, 2.2, 0.22, 0.30))
    use("gun")
    p.append(cyl((0, -L * 0.46, 0), 0.58, 1.60, rot=(R(90), 0, 0), v=12))
    use("body")
    p += _kit(SPAN, L, 0, tanks=2)
    return p, dict(top=0.9, hull_l=L, hull_w=SPAN, turret_top=1.9,
                   gun_z=0.2, gun_y=L * 0.34)


def strike():
    """Two seats, heavy stores. Deep fuselage, big wing."""
    L, SPAN = 17.0, 13.9
    p = fuselage(L, 0.98, 0.52, 0.58)
    p += wings(1.6, SPAN, 5.6, 2.2, 3.0, 0.32, 0.0, "w")
    p += wings(-5.0, 8.0, 2.8, 1.1, 1.8, 0.26, 0.0, "h")
    for s in (-1, 1):
        p.append(fin(-4.4, 3.4, 3.0, 1.1, 2.0, 0.24, cant=6 * s, offset_x=s * 1.05))
    use("deck")
    use("glass")
    p.append(dome((0, L * 0.20, 0.48), 0.50, 2.05, 0.34, v=16))
    use("gun")
    for s in (-1, 1):
        p.append(cyl((s * 0.68, -L * 0.44, -0.05), 0.50, 2.00,
                     rot=(R(90), 0, 0), v=12))
    use("body")
    p += _kit(SPAN, L, 0, canopy=False, tanks=4)
    return p, dict(top=1.0, hull_l=L, hull_w=SPAN, turret_top=2.1,
                   gun_z=0.2, gun_y=L * 0.34)


def cas():
    """Close air support: STRAIGHT high-aspect wing, twin engines mounted high
    and aft, twin tail. The most distinctive planform in the air roster."""
    L, SPAN = 16.3, 17.5
    p = fuselage(L, 0.95, 0.55, 0.70)
    p += wings(1.0, SPAN, 3.1, 2.3, 0.35, 0.34, -0.15, "w")   # near-straight
    p += wings(-5.6, 6.8, 2.4, 1.6, 0.3, 0.26, 0.0, "h")
    for s in (-1, 1):
        p.append(fin(-5.2, 2.6, 2.4, 1.4, 0.9, 0.24, offset_x=s * 3.2))
    use("gun")
    for s in (-1, 1):                                          # podded engines
        p.append(cyl((s * 1.55, -L * 0.24, 0.82), 0.62, 3.30,
                     rot=(R(90), 0, 0), v=14))
    p.append(cyl((0, L * 0.44, -0.28), 0.22, 2.60, rot=(R(90), 0, 0), v=10))
    use("body")
    p += _kit(SPAN, L, 0, tanks=4)
    return p, dict(top=1.2, hull_l=L, hull_w=SPAN, turret_top=2.2,
                   gun_z=0.2, gun_y=L * 0.40)


def bomber():
    """Heavy bomber, B-52 class. 48 m long, 56.4 m span — the largest wing in
    the roster — with EIGHT engines in four twin pods and a pronounced droop.

    Huge radar cross-section (~100 m2, docs/02 table), so it is detected at
    maximum range and needs escort. Its job is standoff volume, not
    penetration; the stealth bomber does that.
    """
    L, SPAN = 48.0, 56.4
    p = fuselage(L, 1.70)
    p += wings(7.5, SPAN, 10.5, 3.2, 15.5, 0.62, -0.55, "w")
    p += wings(-17.5, 16.5, 5.2, 1.9, 4.2, 0.44, 0.0, "h")
    p.append(fin(-15.0, 9.6, 9.0, 3.0, 6.2, 0.46, 1.2))
    use("gun")
    for s in (-1, 1):                       # four twin pods = eight nacelles
        for pod, (px, py) in enumerate(((6.4, 3.2), (11.8, 0.6))):
            for e in range(2):
                p.append(cyl((s * (px + e * 1.35), py, -1.55), 0.72, 4.30,
                             rot=(R(90), 0, 0), v=12))
    use("deck")
    p.append(cube((0, 1.0, -1.95), (2.60, 9.00, 0.70)))          # bomb bay
    use("body")
    return p, dict(top=1.8, hull_l=L, hull_w=SPAN, turret_top=5.0,
                   gun_z=0.4, gun_y=L * 0.32)


def stealth_bomber():
    """Flying wing, B-2 class. 21 m long, 52.4 m span, NO fuselage and NO
    vertical surfaces — the most distinctive planform in the entire roster and
    unmistakable from directly above, which is the only view an RTS gets.

    Epoch 4+. This is the airframe that makes the fourth-root RCS cliff in
    docs/02 matter: a radar seeing a 4th-gen fighter at 200 km sees this at
    roughly 11 km.
    """
    L, SPAN = 21.0, 52.4
    hs = SPAN / 2.0
    # one continuous planform: swept leading edge, double-W trailing edge
    right = [(0.0, 10.5), (hs, -3.5), (20.0, -6.2),
             (15.5, -2.4), (10.0, -7.8), (5.0, -3.9), (0.0, -9.2)]
    poly = right + [(-x, y) for (x, y) in reversed(right[1:-1])]
    use("body")
    p = [plate(poly, 1.05, 0.0, "b2_wing")]
    p.append(plate([(0.0, 9.0), (3.4, 1.0), (3.0, -6.0), (-3.0, -6.0),
                    (-3.4, 1.0)], 1.85, 0.30, "b2_centre"))       # centre body
    use("deck")
    for s in (-1, 1):                                  # buried intakes on TOP
        p.append(cube((s * 3.9, 3.0, 1.24), (2.10, 3.60, 0.42),
                      rot=(R(-9), 0, 0)))
        p.append(cube((s * 4.4, -4.6, 1.10), (2.30, 2.40, 0.26)))  # exhaust troughs
    use("glass")
    p.append(dome((0, 6.6, 1.20), 0.92, 1.72, 0.38, v=16))         # cockpit
    use("body")
    return p, dict(top=0.9, hull_l=L, hull_w=SPAN, turret_top=1.8,
                   gun_z=0.5, gun_y=6.0)


def sead():
    """Defence suppression. A multirole airframe hung with anti-radiation
    missiles and jamming pods — the SEAD duel of docs/02."""
    L, SPAN = 18.3, 13.6
    p = fuselage(L, 0.90, 0.50, 0.60)
    p += wings(1.8, SPAN, 5.8, 2.0, 3.6, 0.30, 0.0, "w")
    p += wings(-5.2, 8.2, 2.8, 1.1, 1.9, 0.26, 0.0, "h")
    for s in (-1, 1):
        p.append(fin(-4.5, 3.4, 3.0, 1.1, 2.0, 0.24, cant=7 * s, offset_x=s * 1.10))
    use("deck")
    for s in (-1, 1):                                          # jamming pods
        p.append(cyl((s * 3.30, 0.6, -0.62), 0.36, 3.60, rot=(R(90), 0, 0), v=12))
    use("gun")
    for s in (-1, 1):
        p.append(cyl((s * 0.70, -L * 0.44, -0.05), 0.50, 2.00,
                     rot=(R(90), 0, 0), v=12))
    use("body")
    p += _kit(SPAN, L, 0, tanks=2)
    return p, dict(top=0.95, hull_l=L, hull_w=SPAN, turret_top=2.1,
                   gun_z=0.2, gun_y=L * 0.34)


def stealth_strike():
    """Faceted, no vertical surfaces you can see from above, canted fins. The
    fourth-root RCS cliff of docs/02 arrives with this airframe."""
    L, SPAN = 15.7, 10.7
    p = []
    use("body")
    p.append(plate([(0, L * 0.46), (2.05, -1.6), (1.55, -L * 0.42),
                    (-1.55, -L * 0.42), (-2.05, -1.6)], 1.10, 0.0, "sf_body"))
    p += wings(1.0, SPAN, 5.4, 1.2, 4.6, 0.26, 0.0, "w")      # sharp delta
    for s in (-1, 1):
        p.append(fin(-4.4, 2.4, 2.6, 0.9, 1.9, 0.22, cant=26 * s, offset_x=s * 1.30))
    use("deck")
    use("glass")
    p.append(dome((0, L * 0.20, 0.60), 0.44, 1.20, 0.28, v=14))
    use("gun")
    p.append(cyl((0, -L * 0.44, -0.05), 0.52, 1.40, rot=(R(90), 0, 0), v=12))
    use("body")
    return p, dict(top=0.75, hull_l=L, hull_w=SPAN, turret_top=1.7,
                   gun_z=0.2, gun_y=L * 0.34)


# ── enablers ───────────────────────────────────────────────────────
def aewc():
    """Pillar 5. An airliner with a ROTODOME — the most identifiable planform
    in the game, and the most valuable target on the map."""
    L, SPAN = 46.6, 44.4
    p = fuselage(L, 2.05, 0.52, 0.52)
    p += wings(7.0, SPAN, 9.0, 3.2, 12.0, 0.60, -0.40, "w")
    p += wings(-17.0, 14.5, 4.6, 1.8, 3.6, 0.44, 0.0, "h")
    p.append(fin(-14.5, 8.2, 8.0, 2.8, 5.4, 0.44, 1.1))
    use("gun")
    for s in (-1, 1):
        for k in range(2):
            p.append(cyl((s * (5.6 + k * 4.4), 3.0 - k * 1.2, -1.20), 0.98, 4.40,
                         rot=(R(90), 0, 0), v=14))
    use("deck")                                                # the rotodome
    p.append(cyl((0, -1.5, 3.35), 4.55, 0.72, v=28))
    for s in (-1, 1):
        p.append(cube((s * 0.9, -1.5, 2.55), (0.34, 2.60, 1.70)))
    use("body")
    use("glass")
    p.append(dome((0, L * 0.40, 0.72), 0.72, 1.60, 0.42, v=16))
    use("body")
    return p, dict(top=2.1, hull_l=L, hull_w=SPAN, turret_top=4.3,
                   gun_z=0.4, gun_y=L * 0.30)


def aew_helo():
    """The UK compromise (docs/08): a rotor aircraft with a radar bulge. ~3 km
    altitude gives ~235 km horizon against ~400 km for a fixed-wing AEW."""
    L, ROTOR = 17.0, 18.6
    p = fuselage(L * 0.62, 1.35, 0.62, 0.40, z=1.20)
    p.append(cube((0, -L * 0.30, 1.30), (0.75, L * 0.42, 0.80)))   # tail boom
    p += wings(-L * 0.44, 4.6, 1.6, 1.0, 0.6, 0.20, 1.30, "h")
    p.append(fin(-L * 0.46, 2.4, 2.0, 1.0, 0.9, 0.22, 1.60))
    use("deck")
    p.append(cyl((1.45, 0.4, 1.10), 1.35, 1.90, rot=(0, R(90), 0), v=18))  # radome
    use("gun")
    p.append(cyl((0, 0.6, 2.35), 0.36, 0.70, v=14))                # rotor head
    for i in range(4):                                              # blades
        b = plate([(-0.22, 0), (0.22, 0), (0.16, ROTOR / 2), (-0.16, ROTOR / 2)],
                  0.10, 2.55, f"bl{i}")
        b.rotation_euler = (0, 0, R(i * 90 + 12))
        p.append(b)
    p.append(cyl((0.55, -L * 0.46, 1.95), 0.22, 0.30, rot=(0, R(90), 0), v=12))
    use("body")
    return p, dict(top=2.0, hull_l=L, hull_w=ROTOR, turret_top=2.8,
                   gun_z=1.3, gun_y=L * 0.20)


def electronic_attack():
    """Airborne jamming. Multirole airframe covered in pods."""
    L, SPAN = 18.3, 13.6
    p, m = sead()
    use("deck")
    for s in (-1, 1):
        p.append(cyl((s * 1.85, -0.2, -0.66), 0.40, 4.20, rot=(R(90), 0, 0), v=12))
    p.append(cyl((0, L * 0.30, -0.60), 0.38, 3.20, rot=(R(90), 0, 0), v=12))
    use("body")
    return p, m


def tanker():
    """Pillar 4 in the air. Airliner body plus a refuelling boom — turns a
    30-minute CAP into a three-hour one, and is the second most valuable
    target in the sky."""
    L, SPAN = 41.5, 39.9
    p = fuselage(L, 1.95, 0.52, 0.50)
    p += wings(6.4, SPAN, 8.6, 3.0, 11.2, 0.56, -0.36, "w")
    p += wings(-15.4, 13.6, 4.4, 1.7, 3.4, 0.42, 0.0, "h")
    p.append(fin(-13.2, 7.8, 7.8, 2.7, 5.2, 0.42, 1.0))
    use("gun")
    for s in (-1, 1):
        for k in range(2):
            p.append(cyl((s * (5.4 + k * 4.2), 2.6 - k * 1.1, -1.15), 0.94, 4.20,
                         rot=(R(90), 0, 0), v=14))
    use("deck")                                                 # the boom
    p.append(cyl((0, -L * 0.50, -1.30), 0.30, 9.0, rot=(R(76), 0, 0), v=12))
    p += wings(-L * 0.56, 5.2, 1.4, 0.8, 0.5, 0.18, -2.30, "bv")
    use("body")
    use("glass")
    p.append(dome((0, L * 0.40, 0.72), 0.72, 1.60, 0.42, v=16))
    use("body")
    return p, dict(top=2.0, hull_l=L, hull_w=SPAN, turret_top=4.2,
                   gun_z=0.4, gun_y=L * 0.30)


def isr():
    """Very high aspect ratio wing, slender body. Contributes tracks, carries
    nothing."""
    L, SPAN = 30.0, 34.0
    p = fuselage(L, 1.15, 0.50, 0.45)
    p += wings(3.0, SPAN, 3.4, 1.5, 3.0, 0.36, 0.0, "w")       # long thin wing
    p += wings(-11.0, 9.0, 2.6, 1.2, 1.6, 0.30, 0.0, "h")
    p.append(fin(-9.6, 5.0, 4.6, 1.8, 3.0, 0.32, 0.7))
    use("deck")
    p.append(dome((0, 2.0, -1.05), 1.05, 1.60, 0.70, v=16))     # sensor fairing
    use("gun")
    for s in (-1, 1):
        p.append(cyl((s * 2.6, 1.0, -0.70), 0.62, 3.00, rot=(R(90), 0, 0), v=12))
    use("body")
    use("glass")
    p.append(dome((0, L * 0.40, 0.72), 0.72, 1.60, 0.42, v=16))
    use("body")
    return p, dict(top=1.3, hull_l=L, hull_w=SPAN, turret_top=3.0,
                   gun_z=0.3, gun_y=L * 0.30)


def maritime_patrol():
    """Pillar 6 from the air: sonobuoys, MAD boom, torpedoes."""
    L, SPAN = 39.5, 37.6
    p = fuselage(L, 1.90, 0.52, 0.48)
    p += wings(5.8, SPAN, 8.0, 2.9, 10.4, 0.54, -0.34, "w")
    p += wings(-14.6, 13.0, 4.2, 1.7, 3.2, 0.40, 0.0, "h")
    p.append(fin(-12.6, 7.4, 7.4, 2.6, 5.0, 0.40, 1.0))
    use("gun")
    for s in (-1, 1):
        for k in range(2):
            p.append(cyl((s * (5.2 + k * 4.0), 2.4 - k * 1.0, -1.10), 0.90, 4.00,
                         rot=(R(90), 0, 0), v=14))
    use("deck")
    p.append(cyl((0, -L * 0.54, 0.10), 0.22, 5.0, rot=(R(90), 0, 0), v=10))  # MAD
    p.append(cube((0, 1.0, -1.85), (2.10, 6.20, 0.60)))          # weapons bay
    use("body")
    use("glass")
    p.append(dome((0, L * 0.40, 0.72), 0.72, 1.60, 0.42, v=16))
    use("body")
    return p, dict(top=2.0, hull_l=L, hull_w=SPAN, turret_top=4.0,
                   gun_z=0.4, gun_y=L * 0.30)


# ── rotary ─────────────────────────────────────────────────────────
def _heli_glass(y, z, w=1.05, d=1.35, h=0.62):
    use("glass")
    o = dome((0, y, z), w, d, h, v=16)
    use("body")
    return [o]


def _rotor(n, dia, z, hub_r=0.42):
    out = []
    use("gun")
    out.append(cyl((0, 0, z), hub_r, 0.62, v=14))
    for i in range(n):
        b = plate([(-0.26, 0), (0.26, 0), (0.18, dia / 2), (-0.18, dia / 2)],
                  0.11, z - 0.05, f"rb{i}")
        b.rotation_euler = (0, 0, R(i * (360.0 / n) + 15))
        out.append(b)
    use("body")
    return out


def attack_helo():
    """Thin fuselage, stub wings hung with ATGMs, chin turret. Terrain-masks
    below the radar horizon (docs/12)."""
    L, ROTOR = 15.0, 14.6
    p = fuselage(L * 0.60, 0.92, 0.55, 0.42, z=1.55)
    p.append(cube((0, -L * 0.30, 1.62), (0.62, L * 0.44, 0.72)))
    p += wings(0.2, 5.8, 1.5, 1.1, 0.3, 0.24, 1.35, "stub")     # stub wings
    use("deck")
    for s in (-1, 1):
        p.append(cube((s * 2.35, 0.1, 1.05), (0.70, 1.50, 0.60)))
        for k in range(2):
            p.append(cyl((s * 2.35, 0.1, 0.86 + k * 0.34), 0.15, 1.45,
                         rot=(R(90), 0, 0), v=8))
    use("gun")
    p.append(cyl((0, L * 0.30, 1.05), 0.30, 0.44, v=12))         # chin turret
    p.append(cyl((0, L * 0.38, 0.98), 0.09, 1.10, rot=(R(90), 0, 0), v=8))
    use("body")
    p += _rotor(4, ROTOR, 2.75)
    p.append(cyl((0.42, -L * 0.46, 2.30), 0.20, 0.26, rot=(0, R(90), 0), v=12))
    p += fuselage(1.0, 0.30, 1.0, 1.0, z=2.30)
    p.append(fin(-L * 0.46, 2.1, 1.8, 0.9, 0.8, 0.20, 1.90))
    use("glass")                       # tandem stepped canopy
    p.append(dome((0, L * 0.30, 1.62), 0.56, 0.95, 0.44, v=14))   # gunner, low
    p.append(dome((0, L * 0.16, 1.86), 0.58, 1.00, 0.46, v=14))   # pilot, raised
    use("body")
    p.append(cube((0, L * 0.23, 1.76), (0.62, 0.30, 0.30)))       # step fairing
    p.append(cyl((0, -L * 0.44, 0.34), 0.22, 0.24, rot=(0, R(90), 0), v=10))
    return p, dict(top=2.1, hull_l=L, hull_w=ROTOR, turret_top=3.0,
                   gun_z=1.05, gun_y=L * 0.30)


def transport_helo():
    """Fat cabin, wide doors, four-blade rotor. Air assault."""
    L, ROTOR = 15.3, 16.4
    p = fuselage(L * 0.62, 1.42, 0.62, 0.40, z=1.70)
    p.append(cube((0, -L * 0.30, 1.72), (0.72, L * 0.42, 0.82)))
    use("deck")
    for s in (-1, 1):
        p.append(cube((s * 1.42, 0.2, 1.60), (0.10, 2.60, 1.10)))  # cabin doors
    use("body")
    p += _rotor(4, ROTOR, 2.95)
    p.append(cyl((0.46, -L * 0.46, 2.45), 0.22, 0.28, rot=(0, R(90), 0), v=12))
    p += wings(-L * 0.42, 3.8, 1.3, 0.9, 0.4, 0.20, 1.80, "h")
    p.append(fin(-L * 0.47, 2.3, 1.9, 0.9, 0.9, 0.22, 2.05))
    for s in (-1, 1):                                             # skids
        p.append(cube((s * 1.25, 0.2, 0.30), (0.16, 4.20, 0.16)))
    p += _heli_glass(L * 0.24, 1.92, 1.02, 1.20, 0.58)
    return p, dict(top=2.3, hull_l=L, hull_w=ROTOR, turret_top=3.2,
                   gun_z=1.7, gun_y=L * 0.20)


def asw_helo():
    """DIPPING SONAR — mobile, no own-noise, leapfrogs ahead of the ship
    (docs/02). The winch and sonar body are the identifier."""
    L, ROTOR = 15.3, 16.4
    p = fuselage(L * 0.60, 1.30, 0.62, 0.42, z=1.65)
    p.append(cube((0, -L * 0.30, 1.68), (0.68, L * 0.42, 0.78)))
    use("deck")
    p.append(cube((1.30, 0.9, 1.95), (0.55, 0.75, 0.55)))          # winch housing
    p.append(cyl((1.30, 0.9, 1.05), 0.06, 1.60, v=8))              # cable
    p.append(cyl((1.30, 0.9, 0.30), 0.30, 0.90, v=14))             # sonar body
    for s in (-1, 1):                                              # torpedoes
        p.append(cyl((s * 1.55, -0.2, 1.05), 0.24, 2.80, rot=(R(90), 0, 0), v=10))
    use("body")
    p += _rotor(4, ROTOR, 2.90)
    p.append(cyl((0.46, -L * 0.46, 2.40), 0.22, 0.28, rot=(0, R(90), 0), v=12))
    p.append(fin(-L * 0.47, 2.2, 1.9, 0.9, 0.9, 0.22, 2.00))
    p += _heli_glass(L * 0.24, 1.86, 0.96, 1.15, 0.55)
    return p, dict(top=2.2, hull_l=L, hull_w=ROTOR, turret_top=3.1,
                   gun_z=1.6, gun_y=L * 0.20)


# ── unmanned ───────────────────────────────────────────────────────
def recon_uav():
    """Enormous span on a tiny body — the most extreme aspect ratio in the
    roster, and unmistakable from above."""
    L, SPAN = 14.5, 35.0
    p = fuselage(L, 0.72, 0.55, 0.40)
    p += wings(1.6, SPAN, 2.0, 0.9, 1.4, 0.22, 0.30, "w")
    for s in (-1, 1):                                              # V-tail
        p.append(fin(-L * 0.40, 2.6, 2.2, 1.0, 1.4, 0.20, cant=38 * s,
                     offset_x=s * 0.45))
    use("deck")
    p.append(dome((0, L * 0.30, 0.40), 0.62, 1.10, 0.46, v=14))    # satcom bulge
    use("gun")
    p.append(cyl((0, -L * 0.40, 0.55), 0.42, 2.20, rot=(R(90), 0, 0), v=12))
    use("body")
    return p, dict(top=0.7, hull_l=L, hull_w=SPAN, turret_top=1.6,
                   gun_z=0.2, gun_y=L * 0.30)


def armed_uav():
    """High aspect wing, downward V-tail, missiles under the wing."""
    L, SPAN = 11.0, 20.0
    p = fuselage(L, 0.58, 0.55, 0.42)
    p += wings(1.2, SPAN, 1.7, 0.8, 1.0, 0.20, 0.20, "w")
    for s in (-1, 1):
        p.append(fin(-L * 0.40, -2.0, 1.8, 0.8, 1.1, 0.18, cant=40 * s,
                     offset_x=s * 0.38))
    use("deck")
    p.append(dome((0, L * 0.32, 0.34), 0.48, 0.85, 0.38, v=12))
    for s in (-1, 1):
        p.append(cyl((s * 3.0, 0.2, -0.30), 0.13, 1.70, rot=(R(90), 0, 0), v=8))
    use("gun")
    p.append(cyl((0, -L * 0.42, 0.40), 0.34, 1.60, rot=(R(90), 0, 0), v=12))
    use("body")
    return p, dict(top=0.6, hull_l=L, hull_w=SPAN, turret_top=1.3,
                   gun_z=0.2, gun_y=L * 0.30)


def loitering_munition():
    """Epoch 7. Cheap and expendable — spend them to make the enemy radiate
    (docs/05)."""
    L, SPAN = 2.5, 3.0
    p = fuselage(L, 0.18, 0.6, 0.5)
    p += wings(0.3, SPAN, 0.45, 0.30, 0.25, 0.06, 0.0, "w")
    for s in (-1, 1):
        p.append(fin(-L * 0.40, 0.55, 0.42, 0.20, 0.24, 0.05, cant=42 * s,
                     offset_x=s * 0.10))
    use("gun")
    p.append(cyl((0, -L * 0.46, 0), 0.12, 0.34, rot=(R(90), 0, 0), v=10))
    use("body")
    return p, dict(top=0.2, hull_l=L, hull_w=SPAN, turret_top=0.5,
                   gun_z=0.05, gun_y=L * 0.30)


AIR = [
    ("air_e1_us_interceptor",   interceptor,        "air_grey"),
    ("air_e4_us_superiority",   air_superiority,    "air_grey"),
    ("air_e4_us_multirole",     multirole,          "air_grey"),
    ("air_e4_us_strike",        strike,             "air_dark"),
    ("air_e1_us_cas",           cas,                "air_dark"),
    ("air_e1_us_bomber",        bomber,             "air_dark"),
    ("air_e4_us_stealthbomber", stealth_bomber,     "air_dark"),
    ("air_e2_us_sead",          sead,               "air_grey"),
    ("air_e4_us_stealth",       stealth_strike,     "air_dark"),
    ("aew_e3_us_aewc",          aewc,               "air_white"),
    ("aew_e3_uk_aewhelo",       aew_helo,           "air_grey"),
    ("ewa_e2_us_electronic",    electronic_attack,  "air_grey"),
    ("tkr_e2_us_tanker",        tanker,             "air_white"),
    ("isr_e1_us_recon",         isr,                "air_dark"),
    ("mpa_e1_us_maritime",      maritime_patrol,    "air_white"),
    ("hel_e3_us_attack",        attack_helo,        "air_dark"),
    ("hel_e2_us_transport",     transport_helo,     "air_dark"),
    ("hel_e2_us_asw",           asw_helo,           "air_grey"),
    ("uav_e5_us_recon",         recon_uav,          "air_white"),
    ("uav_e6_us_armed",         armed_uav,          "air_grey"),
    ("uav_e7_us_loiter",        loitering_munition, "air_grey"),
]

if __name__ == "__main__":
    H.set_out(os.path.join(ROOT, "art", "blockout", "e4_air"))
    for name, _, camo in AIR:
        H.CAMO[name] = camo
        H.TEAM[name] = (0.06, 0.20, 0.62)
    print("building air roles...")
    for name, fn, _ in AIR:
        for lod in (0, 1, 2):
            n = H.build(name, fn, lod)
            print(f"  {name:26s} LOD{lod}  {n:6d} tris")
    print("done")
