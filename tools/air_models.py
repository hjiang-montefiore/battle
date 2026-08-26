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
    """Single tail, blended body, one engine. Flexible, never best.

    F-16 class: 15.06 m long, 9.96 m span, cropped delta with 40 deg of
    leading-edge sweep and a STRAIGHT trailing edge, big all-moving tailplanes
    right at the tail, and wingtip launch rails that stick out fore and aft of
    the tip. The identifying feature from above is the pair of LERX strakes
    running forward from the wing root along the fuselage — they are what make
    an F-16 planform read as one continuous blended body rather than a tube
    with wings bolted on.

    Stations off the top view of art/reference/3v_f16_top.png (a crop of
    3v_f16.png, Wikimedia Commons), aft of the nose:

        body      +/-0.49 at 1.7 m, +/-0.94 at 5.1 m, +/-1.13 at 12 m
        strakes   from 4.2 m out to +/-1.45 where they meet the wing at 7.7 m
        wing      root LE 7.0 m, tip LE 10.0 m, TE 11.6 m straight across
        rails     8.9 - 11.5 m at +/-4.9, outboard of the wingtip itself
        tailplane 12.55 - 15.05 m, 5.98 m span, LE reaching +/-2.85 by 14.1 m

    The old version had a bare +/-0.78 tube with no strakes and no rails, and
    its two drop tanks hung 1.7 m forward of the wing leading edge where the
    real jet has nothing.
    """
    L, SPAN = 15.06, 9.96
    N = L / 2.0
    p = fuselage(L, 0.92, 0.5, 0.55,
                 stations=((0.00, 0.04), (0.03, 0.26), (0.08, 0.53),
                           (0.14, 0.67), (0.22, 0.85), (0.34, 1.00),
                           (0.50, 1.00), (0.62, 0.92), (0.78, 0.88),
                           (0.90, 0.80), (1.00, 0.62)))
    for s in (-1, 1):                                   # LERX strakes
        pts = [(s * 0.35, N - 4.20), (s * 1.45, N - 7.74), (s * 0.35, N - 7.74)]
        if s < 0:
            pts.reverse()
        p.append(plate(pts, 0.24, 0.0, f"lerx_{s}"))
    p += wings(N - 7.00, SPAN, 4.60, 1.60, 3.00, 0.28, 0.0, "w")
    p += wings(N - 12.55, 5.98, 2.55, 0.75, 1.75, 0.22, 0.0, "h")
    p.append(fin(N - 9.20, 3.20, 4.60, 1.30, 2.90, 0.24, 0.35))
    use("deck")
    for s in (-1, 1):                                   # aft body fairings
        p.append(cube((s * 0.68, N - 12.10, 0.0), (0.90, 3.40, 0.90)))
        p.append(cyl((s * 4.88, N - 10.20, 0.05), 0.11, 2.60,   # wingtip rail
                     rot=(R(90), 0, 0), v=8))
        p.append(cyl((s * 2.30, N - 10.00, -0.55), 0.32, 3.60,  # underwing tank
                     rot=(R(90), 0, 0), v=10))
        p.append(cube((s * 2.30, N - 9.60, -0.22), (0.22, 1.20, 0.52)))  # pylon
        p.append(fin(N - 11.60, -0.85, 1.60, 0.80, 0.90, 0.14, -0.55,
                     offset_x=s * 0.62))                        # ventral fin
    use("gun")
    p.append(cyl((0, -N + 0.55, 0), 0.56, 1.60, rot=(R(90), 0, 0), v=12))
    use("body")                                         # bubble canopy, PROUD
    p.append(dome((0, N - 4.30, 0.66), 0.56, 1.62, 0.46, v=16))
    use("glass")
    p.append(dome((0, N - 4.25, 0.70), 0.50, 1.50, 0.44, v=16))
    use("body")
    p += _kit(SPAN, L, 0, canopy=False, tanks=0)
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
    """Close air support: STRAIGHT high-aspect wing, twin engines podded high
    on the REAR fuselage, twin fins on the tips of a rectangular tailplane, and
    the two main-gear pods that stick out FORWARD of the wing leading edge.
    The most distinctive planform in the air roster.

    A-10A: length 16.26 m, span 17.53 m, tailplane span 6.1 m. Planform
    stations below were read off the top view of art/reference/3v_a10_top.png
    (a crop of 3v_a10.png), measured as distance aft of the nose:

        fuselage    ~1.5 m wide and near-CONSTANT from 1.8 m to 13 m aft
        wing        LE 7.0 m aft at the root, TE 10.3 m; tip chord 1.6 m
        gear pods   5.8 - 8.5 m aft at +/-2.55 m, i.e. AHEAD of the wing
        nacelles    9.9 - 13.0 m aft, outer edge +/-2.2 m
        tailplane   14.2 - 16.3 m aft, fins at +/-2.8 m

    The previous version hung the nacelles in mid-air with no pylon, so they
    were a detached island and the silhouette scorer dropped them entirely.
    """
    L, SPAN = 16.26, 17.53
    N = L / 2.0                                   # nose sits at y = +N
    p = fuselage(L, 0.78, 0.55, 0.70,
                 stations=((0.00, 0.24), (0.04, 0.62), (0.09, 0.85),
                           (0.16, 0.97), (0.34, 1.00), (0.62, 1.00),
                           (0.80, 0.90), (0.90, 0.74), (1.00, 0.58)))
    p += wings(N - 6.78, SPAN, 3.45, 1.75, 0.60, 0.34, -0.15, "w")
    p += wings(N - 14.15, 6.10, 2.20, 1.90, 0.12, 0.26, 0.0, "h")
    for s in (-1, 1):                             # fins ON the tailplane tips
        p.append(fin(N - 13.90, 2.60, 2.40, 1.40, 0.95, 0.26,
                     offset_x=s * 2.80))
    use("gun")
    for s in (-1, 1):                             # podded TF34s + their pylons
        p.append(cyl((s * 1.50, N - 11.45, 0.86), 0.70, 3.20,
                     rot=(R(90), 0, 0), v=14))
        p.append(cube((s * 1.05, N - 11.45, 0.50), (1.20, 2.40, 0.60)))
    p.append(cyl((0, N - 1.30, -0.10), 0.24, 2.60, rot=(R(90), 0, 0), v=10))
    use("deck")
    for s in (-1, 1):                             # main-gear pods, wing LE
        p.append(cyl((s * 2.55, N - 7.15, -0.42), 0.36, 2.80,
                     rot=(R(90), 0, 0), v=12))
    use("body")
    p += _kit(SPAN, L, 0, tanks=0)
    return p, dict(top=1.2, hull_l=L, hull_w=SPAN, turret_top=2.2,
                   gun_z=0.2, gun_y=L * 0.40)


def bomber():
    """Heavy bomber, B-52 class. 48.5 m long, 56.4 m span — the largest wing in
    the roster — with EIGHT engines in four twin pods and a pronounced droop.

    Huge radar cross-section (~100 m2, docs/02 table), so it is detected at
    maximum range and needs escort. Its job is standoff volume, not
    penetration; the stealth bomber does that.

    Planform stations measured off the top view of art/reference/3v_b52_top.png
    (a crop of 3v_b52.png, nose air-data probe excluded), as distance aft of
    the nose:

        fuselage    3.3 m wide and constant from 3 m to 33 m aft
        wing        root LE 9.5 m aft, root TE 19.3; tip LE 29.5, TE 33.4
                    -> 20 m of sweep over a 28.2 m semi-span, i.e. ~35 deg
        pods        inboard twin at +/-10.5, outboard twin at +/-18.4, each
                    straddling the leading edge and projecting ~5 m AHEAD of it
        tailplane   36 - 44 m aft, 16.4 m span, swept

    The previous version put the wing root LE 16.5 m aft instead of 9.5 and
    the engine pods at +/-6.4 and +/-11.8 instead of +/-10.5 and +/-18.4, so
    the whole wing sat 7 m too far back and the pods bunched near the roots.
    """
    L, SPAN = 48.5, 56.4
    N = L / 2.0
    p = fuselage(L, 1.72,
                 stations=((0.00, 0.22), (0.02, 0.78), (0.05, 1.00),
                           (0.12, 1.00), (0.62, 1.00), (0.80, 0.92),
                           (0.92, 0.62), (1.00, 0.40)))
    p += wings(N - 9.05, SPAN, 9.90, 4.40, 20.40, 0.62, -0.55, "w")
    p += wings(N - 35.40, 17.20, 8.20, 1.70, 6.40, 0.44, 0.0, "h")
    p.append(fin(N - 39.20, 9.6, 9.0, 3.0, 6.2, 0.46, 1.2))
    use("gun")
    for s in (-1, 1):                       # four twin pods = eight nacelles
        for px, py in ((9.65, N - 14.70), (17.55, N - 20.20)):
            for e in range(2):
                p.append(cyl((s * (px + e * 1.70), py, -1.55), 0.85, 5.50,
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


# ── SEAD vs ELECTRONIC ATTACK: the silhouette contract ─────────────
# These two fly the same mission slice of docs/02 from opposite ends — SEAD
# kills the emitter, the jammer blinds it without firing — so a player who
# cannot tell them apart cannot play either pillar. They were previously the
# same mesh: electronic_attack() called sead() and appended three belly pods
# that hang UNDER the wing, where the RTS camera never sees them. Both measured
# 18.30 x 13.60 m and were indistinguishable in art/renders/air.png.
#
# Each aircraft now OWNS a planform element the other may never carry:
#
#   sead()               TWIN CANTED FINS + a low-aspect fighter wing
#                        (span 13.60 / length 18.30 = 0.74, AR 3.4), and the
#                        anti-radiation missiles are mounted so their noses
#                        project ~3.1 m AHEAD of the local wing leading edge —
#                        over open air, so they read from straight above.
#
#   electronic_attack()  ONE TALL CENTRE FIN capped by the receiver football,
#                        and a high-aspect attack wing (span 16.15 / length
#                        18.24 = 0.89, AR 5.2), plus a 5.4 m four-seat
#                        greenhouse — a big flat glass area seen from overhead.
#
# RULE: sead() never gets a jamming pod and never loses its second fin;
# electronic_attack() never gets a missile and never gets a second fin. If a
# future edit wants to move either element, it has to move the OTHER one too,
# or the pair collapses back into one aircraft. Do not implement one by
# calling the other.
def sead():
    """Defence suppression. A fighter airframe carrying anti-radiation
    missiles — the SEAD duel of docs/02. Dimensioned on the F/A-18E
    (18.31 x 13.62 m). Twin canted fins are its half of the contract above.

    It carries NO jamming pod: jamming is electronic_attack()'s pillar, and the
    pods were what made the two aircraft the same shape in the first place."""
    L, SPAN = 18.3, 13.6
    p = fuselage(L, 0.90, 0.50, 0.60)
    p += wings(1.8, SPAN, 5.8, 2.0, 3.6, 0.30, 0.0, "w")
    p += wings(-5.2, 8.2, 2.8, 1.1, 1.9, 0.26, 0.0, "h")
    for s in (-1, 1):                                     # OWNED: twin fins
        p.append(fin(-4.5, 3.4, 3.0, 1.1, 2.0, 0.24, cant=7 * s, offset_x=s * 1.10))
    use("gun")
    # OWNED: anti-radiation missiles. 4.14 m body (AGM-88 length) on the
    # outboard station, where the wing chord is 4.05 m — pushed forward so
    # 3.1 m of missile sits ahead of the leading edge with nothing above it.
    for s in (-1, 1):
        p.append(cyl((s * 3.30, 1.05, -0.58), 0.19, 3.40, rot=(R(90), 0, 0), v=10))
        p.append(cyl((s * 3.30, 2.94, -0.58), 0.19, 0.74, rot=(R(90), 0, 0),
                     v=10, taper=0.12))                    # seeker nose
        for k, ang in enumerate((0, 90)):                  # cruciform tail fins
            p.append(cube((s * 3.30, -0.35, -0.58), (0.94, 0.62, 0.05),
                          rot=(0, R(ang), 0)))
        p.append(cyl((s * 0.70, -L * 0.44, -0.05), 0.50, 2.00,
                     rot=(R(90), 0, 0), v=12))             # nozzles
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
    """Airborne jamming — the pillar-3 aircraft. A SEPARATE AIRFRAME from
    sead(), not sead() with pods bolted on. See the silhouette contract above.

    Real-world lineage supports two airframes and always has: US defence
    suppression is a fighter (F-100F/F-105G Wild Weasel, F-4G, F-16CJ) while
    US electronic attack is a wide-winged, multi-crew attack airframe
    (EB-66, EA-6A from 1963 — epoch 2 — then EA-6B, EF-111A). This is
    dimensioned on the EA-6 Prowler: 59 ft 10 in x 53 ft = 18.24 x 16.15 m.
    Same LENGTH as the SEAD fighter to within 0.3%, but 18.8% more SPAN over a
    wing of half again the aspect ratio, so the top-down plan is a different
    shape without either aircraft's real size being touched.

    It is unarmed. Everything it carries transmits."""
    L, SPAN = 18.24, 16.15
    # Blunt radome nose and a body that stays full-width back to the wing —
    # the A-6 forward fuselage is a wide box, not the fighter's needle.
    p = fuselage(L, 1.02, 0.0, 0.0,
                 stations=((0.00, 0.46), (0.05, 0.78), (0.17, 0.97),
                           (0.46, 1.00), (0.74, 0.92), (0.89, 0.66),
                           (1.00, 0.36)))
    # OWNED: high-aspect attack wing. area 16.15*(4.2+2.0)/2 = 50.1 m^2 against
    # the real 49.1, aspect ratio 5.2 against the real 5.31. sead()'s wing is
    # 13.6 x (5.8+2.0)/2 = 53.0 m^2 at AR 3.4 — same area class, twice the
    # slenderness, which is the whole planform difference.
    p += wings(1.9, SPAN, 4.2, 2.0, 3.3, 0.34, 0.0, "w")
    p += wings(-5.9, 6.6, 2.7, 1.4, 1.4, 0.28, 0.12, "h")
    # OWNED: ONE tall centre fin. sead() has two, canted, spread to +/-1.10 m;
    # from overhead that is a V outboard of the tail against this single spine.
    p.append(fin(-4.45, 2.48, 4.35, 1.55, 3.05, 0.30, z=0.60))
    use("deck")
    # OWNED: the receiver football on the fin tip. 2.85 m long on an 18.24 m
    # aircraft = 16% of length, at the highest point of the airframe with
    # nothing above it to occlude it from any camera angle.
    p.append(dome((0, -6.30, 3.14), 0.42, 1.42, 0.40, v=16))
    p.append(cyl((0, -5.10, 3.14), 0.28, 0.90, rot=(R(90), 0, 0), v=12,
                 taper=0.35))
    # Five transmitter pods, wing and centreline. These hang under the wing so
    # by the contract above they carry NO identification — they are here for
    # the close camera only.
    for s in (-1, 1):
        for k in range(2):
            p.append(cyl((s * (2.35 + k * 2.60), 0.30 - k * 0.55, -0.98),
                         0.38, 4.30, rot=(R(90), 0, 0), v=10))
    p.append(cyl((0, 1.20, -1.05), 0.38, 4.30, rot=(R(90), 0, 0), v=10))
    # Side-mounted intakes: the A-6 is widest at the wing root, not at the nose.
    for s in (-1, 1):
        p.append(cyl((s * 1.30, 2.60, -0.10), 0.62, 3.20, rot=(R(90), 0, 0),
                     v=12))
    use("body")
    # OWNED: the 5.4 m four-seat greenhouse. sead() has a 1.55 m single-seat
    # canopy. Seen from directly overhead this is a flat glass panel running a
    # third of the fuselage — the "big flat area of a different material" read.
    p.append(cube((0, 4.55, 0.86), (1.92, 5.40, 0.72)))
    p.append(dome((0, 7.25, 0.86), 0.96, 0.95, 0.36, v=14))         # front cap
    use("glass")
    p.append(cube((0, 4.62, 0.94), (1.74, 5.10, 0.62)))
    p.append(dome((0, 7.22, 0.92), 0.84, 0.92, 0.30, v=14))
    use("body")
    p.append(dome((0, L * 0.44, 0.02), 0.86, 1.05, 0.84, v=16))     # radome
    return p, dict(top=1.30, hull_l=L, hull_w=SPAN, turret_top=3.9,
                   gun_z=0.4, gun_y=L * 0.26)


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


def _rotor(n, dia, z, hub_r=0.42, y0=0.0, phase=15.0, chord=(0.26, 0.18)):
    """Disc of n blades about a hub at (0, y0, z).

    y0 exists because a helicopter's mast is NOT at the middle of its
    fuselage, and the blade tips are what set the top-view bounding box, so
    getting the mast station wrong shifts the whole silhouette. phase is the
    parked blade azimuth; on a 4-blade disc it swings the bounding box between
    a '+' (phase 0, box = the full rotor diameter each way) and an 'X'
    (phase 45, box = 0.707 of it), which is a large effect on the planform.
    """
    out = []
    use("gun")
    out.append(cyl((0, y0, z), hub_r, 0.62, v=14))
    for i in range(n):
        cr, ct = chord
        b = plate([(-cr, 0), (cr, 0), (ct, dia / 2), (-ct, dia / 2)],
                  0.11, z - 0.05, f"rb{i}")
        b.rotation_euler = (0, 0, R(i * (360.0 / n) + phase))
        b.location = (0.0, y0, 0.0)
        out.append(b)
    use("body")
    return out


def attack_helo():
    """Thin fuselage, stub wings hung with ATGMs, chin turret, tail rotor on
    the LEFT of the fin. Terrain-masks below the radar horizon (docs/12).

    AH-64: fuselage 15.06 m nose to tail, main rotor 14.63 m, stub wing 5.23 m,
    stabilator 3.4 m, tail rotor 2.79 m, 3.87 m to the rotor head.

    Read off the top view of art/reference/3v_apache_top.png (a crop of
    3v_apache.png), as distance aft of the nose:

        fuselage   0.9 m wide at 0.6 m aft, 1.9 m from 2.3 m to 4 m aft
        engines    4.0 - 6.0 m aft, taking the body out to 3.3 m wide
        stub wing  4.6 - 6.0 m aft, 5.2 m span, pylons at +/-2.0
        boom       8.5 - 12.5 m aft, ~1.1 m wide
        stabilator 13.4 - 14.4 m aft, 3.4 m span
        tail rotor 12.5 - 14.8 m aft, on the LEFT side only
        mast       5.0 m aft -- a THIRD of the way back, not the middle

    Three things were wrong before and all three moved the planform: the body
    was built 9 m long instead of 15.06 so the nose stopped 3 m short; the
    mast sat at the body centre instead of 5 m aft of the nose; and the parked
    blades were at 15 deg, which reads as a '+' from above where the drawing
    (and every parked Apache) shows an 'X'.
    """
    L, ROTOR = 15.06, 14.63
    N = L / 2.0                                   # nose at +7.53
    HUB = N - 5.00                                # mast 5.0 m aft of the nose
    p = fuselage(L, 0.95, 0.55, 0.42, z=1.55,
                 stations=((0.00, 0.05), (0.04, 0.47), (0.08, 0.65),
                           (0.11, 0.84), (0.15, 1.00), (0.27, 1.00),
                           (0.38, 0.84), (0.50, 0.66), (0.58, 0.56),
                           (0.92, 0.53), (1.00, 0.44)))
    p += wings(N - 4.95, 5.23, 1.30, 1.05, 0.15, 0.24, 1.35, "stub")
    use("deck")
    for s in (-1, 1):                             # engine nacelle over the wing
        p.append(cube((s * 1.15, N - 6.00, 2.10), (0.95, 4.00, 1.00)))
        p.append(cube((s * 2.00, N - 5.45, 1.05), (0.75, 1.60, 0.60)))
        for k in range(2):                        # ATGM tubes on the pylon
            p.append(cyl((s * 2.00, N - 5.45, 0.86 + k * 0.34), 0.15, 1.45,
                         rot=(R(90), 0, 0), v=8))
    use("gun")
    p.append(cyl((0, N - 1.30, 1.05), 0.30, 0.44, v=12))         # chin turret
    p.append(cyl((0, N - 0.63, 0.98), 0.09, 1.10, rot=(R(90), 0, 0), v=8))
    use("body")
    p.append(cyl((0, HUB, 2.75), 0.30, 1.10, v=12))              # mast
    p += _rotor(4, ROTOR, 3.10, y0=HUB, phase=45.0, chord=(0.34, 0.26))
    p.append(fin(N - 13.10, 2.10, 1.90, 0.90, 0.80, 0.22, 1.90))
    p += wings(N - 13.40, 3.40, 0.95, 0.80, 0.12, 0.20, 1.30, "h")
    use("gun")                                    # tail rotor, LEFT side only
    p.append(cube((-0.40, N - 13.65, 2.60), (0.70, 0.50, 0.50)))
    p.append(cyl((-0.75, N - 13.65, 2.60), 1.40, 0.26, rot=(0, R(90), 0), v=12))
    use("glass")                       # tandem stepped canopy
    p.append(dome((0, N - 2.25, 2.02), 0.56, 0.95, 0.52, v=14))   # gunner, low
    p.append(dome((0, N - 3.55, 2.26), 0.58, 1.00, 0.54, v=14))   # pilot, raised
    use("body")
    p.append(cube((0, N - 2.95, 2.14), (0.62, 0.30, 0.42)))       # step fairing
    for s in (-1, 1):                             # main wheels on their struts
        p.append(cube((s * 0.85, N - 5.60, 1.00), (0.24, 0.24, 1.00)))
        p.append(cyl((s * 0.85, N - 5.60, 0.42), 0.42, 0.26,
                     rot=(0, R(90), 0), v=12))
    return p, dict(top=2.1, hull_l=L, hull_w=ROTOR, turret_top=3.0,
                   gun_z=1.05, gun_y=L * 0.30)


def _at(objs, dy):
    """Slide a group of parts along Y.

    fuselage() lofts about the origin, but a helicopter's mast, cabin and boom
    are all placed relative to the NOSE, so the loft has to be put where the
    nose says it goes rather than the airframe being drawn around the loft.
    """
    for o in objs:
        o.location.y += dy
    return objs


# ── the transport / ASW pair ───────────────────────────────────────
# SILHOUETTE OWNERSHIP. These two converged completely once — both measured
# 15.92 x 17.05 m with a plan IoU of 0.81 (every other rotary pair sat at
# 0.29-0.54) because both were a 16.4 m disc over a 9.5 m loft, and the ASW's
# whole identity — winch, sonar body, torpedoes — hung UNDER the cabin, where
# the fixed overhead RTS camera cannot see it and LOD2 crushes it anyway.
#
# The rule, which matters more than the geometry below:
#
#   transport OWNS  BULK. A 15.3 m airframe with 5.6 m of straight-sided
#       parallel cabin, the ESSS stub wings carrying four external tanks out
#       to a 5.4 m shoulder at the cabin roofline (visible fuel range,
#       docs/04), a flat engine deck flanking the mast, the big 16.4 m disc
#       parked loose and near fore-and-aft, and a 3.35 m tail rotor.
#   asw       OWNS  COMPACTNESS. The frigate-embarked SH-2F class: a 12.3 m
#       airframe under a 13.4 m disc — 20% less body and 18% less disc — with
#       the blades INDEXED to an X, the way a helicopter that has to fit a
#       frigate's deck and hangar parks them — that alone cuts 13.4 m of
#       span to 9.5 m — a bare boom that is a third of its length, a nose
#       radome, and NOTHING above the cabin line at all.
#
# Neither may take the other's element. In particular nothing underslung may
# ever be either unit's identifier again: the dipping sonar is what the ASW
# DOES (docs/02 §8, docs/12 — pillar 6), not what the player reads it by.
def transport_helo():
    """UH-60-class utility helicopter. Air assault (docs/12).

    Real UH-60A, and the model now fills it instead of hiding inside the
    rotor disc: fuselage 15.27 m nose to tail-rotor tip, main rotor 16.36 m,
    cabin 2.36 m wide with a 1.75 m sliding door a side, stabilator 4.38 m,
    tail rotor 3.35 m, mast 6.40 m aft of the nose, ESSS stub wings with two
    external tanks a side.

    The old body was lofted at only L * 0.62 = 9.49 m, so 5.8 m of the
    declared 15.3 m airframe did not exist and the parked blades set the
    entire bounding box. That is what made it identical to asw_helo.
    """
    L, ROTOR = 15.3, 16.4
    N = L / 2.0                                   # nose +7.65
    HUB = N - 6.40                                # mast 6.40 m aft of the nose
    p = _at(fuselage(11.20, 1.18, 0.62, 0.40, z=1.78,
                     stations=((0.00, 0.06), (0.06, 0.46), (0.13, 0.78),
                               (0.22, 0.97), (0.34, 1.00), (0.58, 1.00),
                               (0.74, 0.92), (0.88, 0.62), (1.00, 0.34))),
            N - 5.60)
    # 5.6 m of PARALLEL cabin side — the transport's exclusive plan feature.
    p.append(cube((0, N - 5.35, 1.82), (2.36, 5.60, 1.86)))
    p.append(cube((0, N - 9.55, 2.00), (0.72, 2.60, 0.86)))      # tail boom
    use("deck")
    for s in (-1, 1):                                            # sliding doors
        p.append(cube((s * 1.20, N - 5.25, 1.78), (0.10, 1.75, 1.34)))
    p.append(cube((0, HUB, 2.98), (1.34, 2.90, 0.56)))           # engine deck
    for s in (-1, 1):                                            # ESSS tanks
        for x in (1.60, 2.35):
            p.append(cyl((s * x, N - 5.25, 1.98), 0.33, 4.30,
                         rot=(R(90), 0, 0), v=12))
    use("body")
    p += wings(N - 4.75, 5.00, 1.05, 0.85, 0.12, 0.20, 2.45, "esss")
    # phase 20: parked near fore-and-aft, NOT indexed. Swept 0/15/20/30/45
    # against the other three rotary units and 20 was the minimum on all
    # three (asw 0.326, attack 0.443, aew 0.294 plan IoU); phase 0 cost
    # +0.03 against the ASW and +0.03 against the attack helo.
    p += _rotor(4, ROTOR, 3.45, y0=HUB, phase=20.0, chord=(0.32, 0.24))
    p += wings(-4.55, 4.38, 1.25, 0.95, 0.28, 0.20, 1.78, "stab")
    p.append(fin(-5.05, 2.30, 1.75, 0.85, 0.85, 0.24, 2.05))
    use("gun")                                    # 3.35 m tail rotor, to port
    p.append(cyl((-0.58, -5.98, 3.05), 1.675, 0.26, rot=(0, R(90), 0), v=16))
    use("body")
    for s in (-1, 1):                                            # main gear
        p.append(cube((s * 1.30, N - 6.60, 0.86), (0.24, 0.24, 0.90)))
        p.append(cyl((s * 1.30, N - 6.60, 0.42), 0.42, 0.28,
                     rot=(0, R(90), 0), v=12))
    p.append(cyl((0, -4.30, 0.38), 0.34, 0.24, rot=(0, R(90), 0), v=12))
    p += _heli_glass(N - 1.75, 2.30, 1.10, 1.55, 0.60)
    return p, dict(top=2.75, hull_l=L, hull_w=ROTOR, turret_top=3.45,
                   gun_z=1.8, gun_y=L * 0.20)


def asw_helo():
    """DIPPING SONAR — mobile, no own-noise, leapfrogs ahead of the ship
    (docs/02 §8, docs/12). Pillar 6.

    It flies off the ASW frigate, so it is built to the compact shipborne
    class — SH-2F Seasprite: fuselage 12.34 m, main rotor 13.41 m, tail rotor
    2.44 m, mast 4.60 m aft of the nose, main gear wide and well forward for
    deck handling, nose search radome — and NOT to the transport's airframe.

    The winch, sonar body and torpedoes under the cabin stay, because they are
    the close-range story, but they are deliberately not the identifier: from
    the RTS camera they sit behind the fuselage. What identifies this unit is
    that it is SMALL — 18% less disc, 20% less body than the transport — with
    its blades stowed in an X, the way a helicopter that lives on a flight
    deck parks them.
    """
    L, ROTOR = 12.3, 13.4
    N = L / 2.0                                   # nose +6.15
    HUB = N - 4.60                                # mast 4.60 m aft of the nose
    p = _at(fuselage(8.20, 0.95, 0.62, 0.42, z=1.62,
                     stations=((0.00, 0.07), (0.07, 0.52), (0.16, 0.84),
                               (0.28, 1.00), (0.56, 1.00), (0.78, 0.80),
                               (1.00, 0.42))),
            N - 4.10)
    p.append(cube((0, N - 9.45, 1.85), (0.58, 2.60, 0.74)))      # bare boom
    use("deck")
    p.append(dome((0, N - 0.55, 1.30), 0.80, 1.05, 0.52, v=16))  # nose radome
    p.append(cube((1.02, 1.00, 1.90), (0.50, 0.70, 0.50)))       # winch housing
    p.append(cyl((1.02, 1.00, 1.02), 0.06, 1.55, v=8))           # cable
    p.append(cyl((1.02, 1.00, 0.30), 0.30, 0.88, v=14))          # sonar body
    for s in (-1, 1):                                            # Mk46 torpedo
        p.append(cyl((s * 1.05, -0.40, 1.05), 0.17, 2.60,
                     rot=(R(90), 0, 0), v=10))
    use("body")
    p += _rotor(4, ROTOR, 3.05, y0=HUB, phase=45.0, chord=(0.26, 0.20))
    p += wings(-3.75, 2.60, 0.85, 0.62, 0.15, 0.16, 1.70, "stab")
    p.append(fin(-4.30, 1.85, 1.35, 0.70, 0.70, 0.22, 1.95))
    use("gun")                                    # 2.44 m tail rotor
    p.append(cyl((-0.42, -4.93, 2.70), 1.22, 0.24, rot=(0, R(90), 0), v=14))
    use("body")
    for s in (-1, 1):                             # wide, forward deck gear
        p.append(cube((s * 1.55, N - 3.30, 0.86), (0.22, 0.22, 0.90)))
        p.append(cyl((s * 1.55, N - 3.30, 0.42), 0.42, 0.26,
                     rot=(0, R(90), 0), v=12))
    p.append(cyl((0, -3.90, 0.36), 0.30, 0.22, rot=(0, R(90), 0), v=12))
    p += _heli_glass(N - 1.45, 2.05, 0.95, 1.25, 0.55)
    return p, dict(top=2.20, hull_l=L, hull_w=ROTOR, turret_top=3.05,
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
