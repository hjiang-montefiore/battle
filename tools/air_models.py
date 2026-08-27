"""Fixed-wing, rotary and unmanned roles from docs/12-unit-roster.md.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/air_models.py

From an RTS camera an aircraft is read almost entirely by PLANFORM — the wing
outline seen from above. So wing sweep, span and taper carry the identification,
and fuselage detail barely registers. Every role below is shaped around its
planform first.

HOW SMALL DOES AN AIRCRAFT ACTUALLY GET? Several comments below were written
around "must read at 60 px", which was inherited from the ground roster and
never recalculated. It is a TANK-sized budget. The camera is 48 deg vertical
into a 900 px viewport and clamps at 18-140 m, so a metre of span is 1011/d
pixels and the floor at maximum zoom-out is:

    M1 Abrams  3.66 m ->   26 px      A-10A     17.53 m ->  127 px
    F-16C      9.96 m ->   72 px      F-111F    19.20 m ->  139 px
    F-15C     13.05 m ->   94 px      B-52H     56.39 m ->  407 px

An Abrams passes through 60 px at 62 m, well inside the zoom range, so for a
tank the rule bites. No aircraft in this file ever reaches it: the F-16 would
need the camera 168 m out and the B-2 883 m, against a zoom_max of 140. Read
"60 px" in the notes below as the historical justification it was, not as a
constraint that still applies -- fuselage section is affordable here, which is
the premise the loft() rebuild rests on.

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



def _dist_to_outline(x, y, poly):
    """Shortest distance from a point to a closed polygon's edges."""
    best = 1e30
    n = len(poly)
    for i in range(n):
        ax, ay = poly[i]
        bx, by = poly[(i + 1) % n]
        dx, dy = bx - ax, by - ay
        L2 = dx * dx + dy * dy
        t = 0.0 if L2 < 1e-12 else max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / L2))
        px, py = ax + dx * t, ay + dy * t
        d = math.hypot(x - px, y - py)
        if d < best:
            best = d
    return best


def aerofoil(poly, peak, name="foil", cuts=5, under=0.34, power=0.62,
             extra=None, z=0.0):
    """A planform given a continuous, tapered SECTION.

    plate() extrudes an outline straight up at constant thickness, so every
    surface it makes is horizontal or vertical and a wing built by stacking
    plates is a wedding cake with square risers. This keeps the outline exactly
    -- span, length and plan area are untouched, which matters because the B-2
    planform was verified against its published 478 m2 wing area -- and gives
    it a section instead: thickness falls to nothing at the edges and swells
    inboard, so leading edge, trailing edge and tips all come to a taper.

    Thickness is driven by distance to the outline rather than by span station,
    which thins the leading and trailing edges as well as the tips without
    needing to know where the local chord runs.

    `extra` adds thickness at a place: (x, y, radius, height), used for a
    centre-body or a cockpit fairing that has to grow OUT of the surface rather
    than sit on top of it.
    """
    me = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, 0.0)) for (x, y) in poly]
    face = bm.faces.new(vs)
    bmesh.ops.triangulate(bm, faces=[face])
    for _ in range(cuts):
        bmesh.ops.subdivide_edges(bm, edges=bm.edges[:], cuts=1,
                                  use_grid_fill=False)
    bm.verts.ensure_lookup_table()

    dmax = 0.0
    for v in bm.verts:
        d = _dist_to_outline(v.co.x, v.co.y, poly)
        v.tag = False
        dmax = max(dmax, d)
    if dmax < 1e-6:
        dmax = 1.0

    def thickness(x, y):
        t = peak * (_dist_to_outline(x, y, poly) / dmax) ** power
        if extra:
            for (ex, ey, er, eh) in extra:
                r = math.hypot(x - ex, y - ey) / er
                if r < 1.0:
                    t += eh * (0.5 + 0.5 * math.cos(math.pi * r))
        return t

    top = list(bm.verts)
    dup = bmesh.ops.duplicate(bm, geom=list(bm.verts) + list(bm.edges) + list(bm.faces))
    bottom = [g for g in dup["geom"] if isinstance(g, bmesh.types.BMVert)]
    for v in top:
        v.co.z = z + thickness(v.co.x, v.co.y)
    for v in bottom:
        v.co.z = z - under * thickness(v.co.x, v.co.y)

    top_rim = [e for e in bm.edges if e.is_boundary and e.verts[0] in set(top)]
    bot_set = set(bottom)
    bot_rim = [e for e in bm.edges if e.is_boundary and e.verts[0] in bot_set]
    if top_rim and bot_rim:
        bmesh.ops.bridge_loops(bm, edges=top_rim + bot_rim)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    return tag(obj)



def shell(stations, name="shell"):
    """Continuous surface through outlines that already correspond.

    Every outline must have the same vertex count and the same winding, which
    is true whenever they are interpolated from one another -- the F-117's
    facet tiers are built exactly that way. Bridging them gives SLOPING walls
    between stations instead of the vertical risers plate() leaves, so the
    result reads as facets rather than as a staircase, which is the difference
    between a faceted aircraft and a stack of trays.
    """
    n = len(stations[0][0])
    for poly, _ in stations:
        if len(poly) != n:
            raise ValueError("shell() needs matching vertex counts: %d vs %d"
                             % (len(poly), n))
    me = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    rings = [[bm.verts.new((x, y, z)) for (x, y) in poly] for poly, z in stations]
    bm.verts.ensure_lookup_table()
    for a, b in zip(rings, rings[1:]):
        for i in range(n):
            j = (i + 1) % n
            if len({a[i], a[j], b[j], b[i]}) == 4:
                bm.faces.new((a[i], a[j], b[j], b[i]))
    bm.faces.new(list(reversed(rings[0])))
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    return tag(obj)


def wings(root_y, span, root_c, tip_c, sweep, thick, z, name="wing"):
    """Mirrored swept tapered panels with a real SECTION. sweep = how far back
    the tip sits.

    These used to be plate() extrusions: constant thickness, square edges top
    and bottom. Against a lofted fuselage that reads as plywood, and the
    leading edge is the one part of a wing the camera sees nearly head-on when
    an aircraft crosses the screen. aerofoil() keeps the planform EXACTLY --
    span, chord and area are what identify an aircraft, and several of these
    planforms were checked against published wing areas -- and replaces the
    extrusion with thickness that falls to nothing at leading edge, trailing
    edge and tip.

    The root edge tapers as well, which sounds wrong until you notice it is
    buried inside the fuselage: what emerges from the body is a section at
    roughly two-thirds of peak, which is about where a wing root really sits.

    peak is 0.75 of the old constant thickness so that peak plus the 34 %
    underside returns the same maximum the plate had. Every aircraft in the
    file gets this, including tailplanes, which are built by this function too.
    """
    out = []
    for s in (-1, 1):
        hw = span / 2.0
        pts = [(s * 0.30, root_y),
               (s * hw, root_y - sweep),
               (s * hw, root_y - sweep - tip_c),
               (s * 0.30, root_y - root_c)]
        if s < 0:
            pts.reverse()
        out.append(aerofoil(pts, thick * 0.75, f"{name}_{s}", cuts=4,
                            under=0.34, power=0.55, z=z))
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


def _superellipse(w, h, zc, sq, v):
    """One cross-section ring in the XZ plane.

    sq is the superellipse exponent: 1.0 is a true ellipse, BELOW that the
    section grows shoulders and flattens its top and bottom, above it pinches
    toward a diamond. It is the single number that separates a round tube
    from a chined forebody.
    """
    e = max(sq, 0.05)
    ring = []
    for i in range(v):
        t = 2.0 * math.pi * i / v
        cx, cz = math.cos(t), math.sin(t)
        ring.append((w * math.copysign(abs(cx) ** e, cx),
                     zc + h * math.copysign(abs(cz) ** e, cz)))
    return ring


def loft(sections, v=16, name="loft", cap=(True, True)):
    """Superelliptic lofted body, nose at +Y. The fast-jet fuselage primitive.

    Each section is (y, w, h, zc, sq):

        y    station along the aircraft in metres, nose positive
        w    HALF-width there
        h    HALF-height there
        zc   height of that section's centre above the build plane
        sq   squareness, per _superellipse above; optional, default 1.0
             (a plain ellipse), and zc is optional too, so a station may be
             given as (y, w, h), (y, w, h, zc) or (y, w, h, zc, sq)

    Sections run nose first, descending y. A station with w or h at zero
    collapses to a point, so a nose or a tailcone closes properly instead of
    ending on a disc.

    cap is (front, back). An intake and a jet pipe are HOLES, and a lofted
    tube with both ends capped is a lid where the hole should be -- which is
    exactly what the F-16's inlet and nozzle looked like on the first pass.
    Leave the relevant end open and put a darker inner loft behind it.

    This exists because fuselage() can only stack CIRCULAR cones: one radius
    per station, always centred on z, always round. A real fast jet breaks all
    three at once. An F-16 through the inlet is about 1.6 times wider than it
    is tall; the centreline of its sections climbs roughly 0.9 m from inlet lip
    to spine, so a body drawn on one axis sits either too low at the front or
    too high at the back; and the forebody is a rounded-off triangle with a
    chine down each side, which no circle approximates. Width, height, vertical
    offset and squareness are exactly those three degrees of freedom, and they
    are what make a fighter read as a fighter rather than as a pipe with wings.
    """
    EPS = 1e-4
    me = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    rings = []
    for st in sections:
        y, w, h = st[0], st[1], st[2]
        zc = st[3] if len(st) > 3 else 0.0
        sq = st[4] if len(st) > 4 else 1.0
        if w <= EPS or h <= EPS:
            rings.append([bm.verts.new((0.0, y, zc))])
        else:
            rings.append([bm.verts.new((x, y, z))
                          for (x, z) in _superellipse(w, h, zc, sq, v)])
    bm.verts.ensure_lookup_table()
    for a, b in zip(rings, rings[1:]):
        if len(a) == 1 and len(b) == 1:
            continue
        if len(a) == 1:                                   # nose apex -> fan
            for i in range(v):
                bm.faces.new((a[0], b[i], b[(i + 1) % v]))
        elif len(b) == 1:                                 # -> tail apex
            for i in range(v):
                bm.faces.new((a[i], a[(i + 1) % v], b[0]))
        else:
            for i in range(v):
                j = (i + 1) % v
                if len({a[i], a[j], b[j], b[i]}) == 4:
                    bm.faces.new((a[i], a[j], b[j], b[i]))
    if cap[0] and len(rings[0]) > 1:
        bm.faces.new(list(reversed(rings[0])))
    if cap[1] and len(rings[-1]) > 1:
        bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    return tag(obj)


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


def nozzle(y_aft, r, length, x=0.0, z=0.0, v=18, name="nozzle",
           waist=0.86, flare=1.02):
    """An OPEN jet pipe: an outer shell with a black throat down it.

    Every engine in this file used to be a capped cylinder, and that was
    survivable while the fuselage around it was also a stack of cylinders.
    Once the bodies were lofted, the lid across the back of the exhaust became
    the most obviously fake thing on the aeroplane -- a jet with its exhaust
    welded shut. A real afterburning nozzle necks IN behind the tail fairing
    and flares back out at the petals, and you can see down it.

    Restores the caller's material group on the way out, since this is called
    from inside blocks that have already chosen one.
    """
    prev = H.CURRENT
    y0 = y_aft + length
    out = []
    use("gun")
    out.append(loft([(y0, r, r, z),
                     (y0 - length * 0.62, r * waist, r * waist, z),
                     (y_aft, r * flare, r * flare, z)], v=v, name=name,
                    cap=(True, False)))
    use("gunbore")
    out.append(loft([(y0 - length * 0.30, r * 0.60, r * 0.60, z),
                     (y_aft - 0.02, r * flare * 0.94, r * flare * 0.94, z)],
                    v=v, name=name + "_throat", cap=(True, False)))
    for o in out:
        o.location.x = x
    use(prev)
    return out


def turbofan(y_front, r, length, x=0.0, z=0.0, v=18, name="pod"):
    """A podded turbofan: cowl, dark fan face, open exhaust, spinner.

    Same failure as nozzle(), one step worse. A podded engine drawn as a
    capped cylinder has neither an intake nor an exhaust, so it reads as a
    drop tank -- and the A-10 hangs two of them where the aeroplane's whole
    silhouette depends on their being engines. What separates the two shapes
    at a glance is that an engine is OPEN at both ends with a visibly dark
    disc a little way inside the cowl lip.
    """
    prev = H.CURRENT
    out = []
    ya = y_front - length
    use("gun")
    out.append(loft([(y_front, r * 0.94, r * 0.94, z),
                     (y_front - length * 0.10, r, r, z),
                     (y_front - length * 0.62, r * 0.97, r * 0.97, z),
                     (ya, r * 0.80, r * 0.80, z)], v=v, name=name,
                    cap=(False, False)))
    use("gunbore")
    out.append(loft([(y_front - 0.02, r * 0.90, r * 0.90, z),
                     (y_front - length * 0.30, r * 0.84, r * 0.84, z)],
                    v=v, name=name + "_fan", cap=(False, True)))
    out.append(loft([(y_front - length * 0.70, r * 0.72, r * 0.72, z),
                     (ya + 0.02, r * 0.76, r * 0.76, z)], v=v,
                    name=name + "_jet", cap=(True, False)))
    use("gun")
    out.append(cyl((0, y_front - length * 0.20, z), r * 0.24, length * 0.30,
                   rot=(R(90), 0, 0), v=10, taper=0.06))
    for o in out:
        o.location.x = x
    use(prev)
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



def _prop(cx, cy, cz, dia, blades=4, phase=10.0, chord=0.30, pitch=38.0,
          spinner=(0.30, 0.74)):
    """A PROPELLER disc, spinning in the XZ plane with thrust along +Y.

    Every other lifting or rotating surface in this file lies flat, so a
    propeller is the one primitive that stands on edge. What it contributes
    to the top-down plan is: a spinner projecting forward of the wing
    leading edge, and the near-horizontal blade pair reaching a full radius
    out each side of its nacelle. `pitch` twists each blade out of the plane
    of rotation the way a real blade is set, so from directly overhead the
    horizontal pair shows a real chord instead of a zero-width edge.

    Restores the caller's material group on the way out — it is called from
    inside loops that are already in a group.
    """
    prev = H.CURRENT
    out = []
    use("gun")
    sr, sl = spinner
    out.append(cyl((cx, cy, cz), sr, sl, rot=(R(90), 0, 0), v=14, taper=0.30))
    r = dia / 2.0
    th = max(0.04, dia * 0.022)
    for i in range(blades):
        a = R(i * (360.0 / blades) + phase)
        out.append(cube((cx + math.cos(a) * r * 0.5, cy,
                         cz + math.sin(a) * r * 0.5),
                        (r, th, chord), rot=(R(pitch), -a, 0)))
    use(prev)
    return out


# ── combat ─────────────────────────────────────────────────────────
def interceptor():
    """Epoch 1 point-defence interceptor: CONVAIR F-106A DELTA DART.

    21.55 m long, 11.67 m span, 61.5 m2 of wing, aspect ratio 2.21, leading
    edge swept 60 deg, ONE engine, ONE fin and NO horizontal tail. Those five
    facts are the identification, and not one of them is shared with any other
    aircraft in the roster.

    This replaces an F-4E Phantom. The Phantom was dimensionally exact but it
    was the wrong aeroplane for the slot -- a twin-engine, two-seat, tailed
    fighter-bomber of 1961 standing in for a 1950s point-defence interceptor --
    and it put a SIXTH swept tapered trapezoid into a family that already had
    five. It measured 0.714 IoU against the F-16 and 0.656 against the stealth
    jet on planform alone. The F-106 is what the role actually is: the USAF's
    dedicated all-weather interceptor, armed only for air-to-air, tied to a
    ground radar network -- which is the docs/02-detection.md pillar this unit
    exists to carry.

    A tailless delta is the one planform in the fast-jet family that cannot be
    read as a trapezoid-plus-tailplane even at its 84 px floor. The plan is a
    single triangle
    from 41 % of the length back to the trailing edge at 88 %, and behind it
    there is nothing but the fin -- no stabilator, no second surface, no notch.

    Geometry, from the F-106A three-view:
        wing      apex 8.90 m aft, root chord 10.30 m, tip 0.30 m, LE 60.0 deg
                  61.9 m2, AR 2.20   (real 61.52 m2, AR 2.21, LE 60 deg)
        intakes   dorsal, on the wing-root shoulders, 10.6 - 14.2 m aft, which
                  is far further back than any other jet here carries them
        fin       LE 14.4 m aft, root chord 5.60 m, single
        fuselage  area-ruled -- a real coke-bottle waist at 66 % of the length
    """
    L, SPAN = 21.55, 11.67
    N = L / 2.0
    SWP = math.tan(math.radians(60.0)) * (SPAN / 2.0 - 0.30)      # 9.587
    # The F-106 is the aeroplane the AREA RULE was named on: its fuselage
    # pinches where the wing carries the most cross-section and swells again
    # behind it. The old station list already had that dip (0.86 down to 0.84
    # and back to 0.96) but drew it as circles, so it read as a bulge rather
    # than as a waist. With width and height free it is a real coke bottle.
    p = [loft([(10.72, 0.03, 0.03, 0.00),
               (9.70, 0.20, 0.19, 0.00),
               (8.20, 0.42, 0.40, 0.02),
               (6.50, 0.60, 0.56, 0.05, 0.95),
               (4.30, 0.76, 0.68, 0.06, 0.90),
               (1.75, 0.86, 0.78, 0.02, 0.88),
               (-0.90, 0.78, 0.74, 0.00, 0.90),
               (-3.10, 0.73, 0.72, 0.00, 0.92),
               (-5.60, 0.80, 0.78, 0.01, 0.94),
               (-8.20, 0.72, 0.70, 0.02),
               (-9.60, 0.60, 0.58, 0.02),
               (-10.10, 0.54, 0.53, 0.02)], v=22, name="f106_fus")]
    p += wings(N - 8.90, SPAN, 10.30, 0.30, SWP, 0.30, 0.0, "w")
    p.append(fin(N - 14.40, 3.20, 5.60, 1.70, 3.60, 0.26, 0.55))
    use("deck")
    for s in (-1, 1):                                   # shoulder intake ducts
        p.append(cube((s * 1.05, N - 12.40, 0.44), (0.86, 3.60, 0.92)))
        p.append(cube((s * 1.52, N - 12.60, 0.44), (0.14, 3.10, 0.80)))  # ramp
        p.append(cube((s * 3.10, N - 18.40, 0.16), (2.60, 1.30, 0.22)))  # elevon
    use("gun")
    p += nozzle(-10.77, 0.62, 1.05, z=0.02, name="f106_nozzle")
    p.append(cyl((0, N - 0.55, 0.02), 0.16, 1.10, rot=(R(90), 0, 0), v=10))
    use("body")
    p += _kit(SPAN, L, 0)
    return p, dict(top=0.9, hull_l=L, hull_w=SPAN, turret_top=1.9,
                   gun_z=0.2, gun_y=L * 0.30)


def air_superiority():
    """Epoch 4 air superiority: McDONNELL DOUGLAS F-15C EAGLE.

    19.43 x 13.05 m, wing 56.5 m2, aspect ratio 3.01, leading edge swept
    45 deg, stabilator span 8.61 m, twin VERTICAL fins.

    The dimensions were already right; the WING was not. The old model swept
    the leading edge 32.7 deg, which is not an Eagle -- an F-15 wing is swept
    45 deg on the leading edge (38.7 deg at quarter chord). Correcting it to
    the real number is what breaks this aircraft out of the superiority /
    strike / SEAD clique: the Super Hornet next to it is swept 29 deg and the
    Tornado 24 deg, so the three of them were within 8 deg of each other and
    measured 0.88 and 0.77 IoU. 45 deg puts 16 deg of daylight between the
    Eagle and its nearest neighbour.

    Everything else here is the other half of the same correction -- the F-15
    is not a tube with wings, it is TWO ENGINE BOXES with a wing bridged across
    them:

        nacelles   two flat-sided boxes on 2.20 m centres running 2.6 m aft of
                   the nose datum to the nozzles, so the aft two-thirds of the
                   plan is a 3.42 m wide flat slab. Nothing else in the family
                   has a rear plan that is wider than its own nose section.
        intakes    the square variable ramps, standing proud outboard at
                   +/-1.79 m, 4.7 - 7.6 m aft. Square shoulders, seen overhead.
        fins       VERTICAL, not canted. The audit's point 7 was that
                   superiority, strike and SEAD all wore twin fins canted 6-8
                   deg and read as three identical Vs from above. An F-15's
                   fins really are upright; the Hornet's really are canted 20.
        stabilator 8.61 m span, LE swept 50 deg, mounted OUTBOARD of the fins
                   and reaching the aft-most point of the aircraft. That is
                   66 % of the wingspan in tailplane -- the largest ratio of
                   any jet in the roster, and it makes the rear of the plan a
                   second wing rather than a pair of trim tabs.

        wing       root LE 8.30 m aft, root chord 7.20 m, tip 1.46 m,
                   56.5 m2, AR 3.01, LE 45.0 deg   (real 56.5 m2, AR 3.01)
    """
    L, SPAN = 19.43, 13.05
    N = L / 2.0
    SWP = math.tan(math.radians(45.0)) * (SPAN / 2.0 - 0.30)      # 6.225
    # An Eagle is round at the nose and RECTANGULAR by the time it reaches the
    # engines -- the aft body is the flat shovel that carries the two of them
    # side by side, and it is the single strongest cue separating this from
    # the F-16 next to it in the lineup. sq falls from 0.92 to 0.68 down the
    # length, which is that transition; a stack of cones cannot express it.
    p = [loft([(9.60, 0.04, 0.04, 0.00),
               (8.70, 0.26, 0.25, 0.00),
               (7.40, 0.50, 0.46, 0.02),
               (6.00, 0.66, 0.58, 0.05, 0.92),
               (4.20, 0.80, 0.68, 0.04, 0.85),
               (2.00, 0.90, 0.76, 0.00, 0.78),
               (-0.60, 0.94, 0.78, -0.02, 0.72),
               (-3.20, 0.92, 0.74, -0.02, 0.68),
               (-5.60, 0.88, 0.70, 0.00, 0.70),
               (-7.60, 0.80, 0.64, 0.02, 0.75),
               (-9.10, 0.70, 0.58, 0.03, 0.85),
               (-9.72, 0.62, 0.54, 0.03)], v=22, name="f15_fus")]
    p += wings(N - 8.30, SPAN, 7.20, 1.46, SWP, 0.34, 0.0, "w")
    p += wings(N - 13.62, 8.61, 3.55, 1.04, 4.77, 0.28, 0.0, "h")
    for s in (-1, 1):                                   # stabilator SNAG
        y0 = N - 13.62 - (2.60 - 0.30) * 1.1911         # LE at 60 % semispan
        y1 = N - 13.62 - (4.305 - 0.30) * 1.1911
        pts = [(s * 2.60, y0 + 0.35), (s * 4.305, y1 + 0.35),
               (s * 4.305, y1), (s * 2.60, y0)]
        if s < 0:
            pts.reverse()
        p.append(plate(pts, 0.26, 0.0, f"snag_{s}"))
    for s in (-1, 1):
        p.append(fin(N - 12.72, 3.10, 4.20, 1.55, 2.70, 0.24, 0.55,
                     cant=0.0, offset_x=s * 1.30))
    use("deck")
    for s in (-1, 1):                                   # engine nacelle boxes
        p.append(cube((s * 1.10, -3.00, -0.10), (1.22, 11.20, 1.20)))
        p.append(cube((s * 1.12, N - 6.10, -0.14), (1.34, 2.90, 1.06)))  # intake
        p.append(cube((s * 1.66, N - 6.30, -0.10), (0.20, 2.60, 0.90)))  # ramp
        p.append(cube((s * 1.10, -5.60, 0.50), (1.00, 5.40, 0.14)))      # deck
    use("gun")
    for s in (-1, 1):
        p += nozzle(-N, 0.56, 1.60, x=s * 1.10, z=-0.05, v=14,
                    name="f15_nozzle_%d" % s)
    use("body")
    p += _kit(SPAN, L, 0, tanks=2)
    return p, dict(top=0.95, hull_l=L, hull_w=SPAN, turret_top=2.1,
                   gun_z=0.2, gun_y=L * 0.35)


def multirole():
    """Epoch 4 multirole: GENERAL DYNAMICS F-16C FIGHTING FALCON.

    15.06 x 9.96 m, wing 31.0 m2 gross, aspect ratio 3.20, leading edge swept
    40 deg, trailing edge DEAD STRAIGHT, one engine, one fin.

    Dimensions were exact and stay exact. Two things were wrong inside them.

    1. The leading edge was swept 32.7 deg -- identical to two decimal places
       with the F-15 next to it, and not an F-16, which is swept 40 deg. It is
       now 40.0 deg.
    2. The wing was a plain tapered trapezoid whose trailing edge swept aft.
       An F-16 wing is a CROPPED DELTA and its trailing edge is unswept: it
       runs straight across the aeroplane at 11.60 m aft, perpendicular to the
       centreline, from wingtip to wingtip. root 5.07 m, tip 1.15 m, and
       5.07 - 1.15 = 3.93 = exactly the leading-edge sweep offset, which is
       what makes the trailing edge straight. That straight line is the
       structural cue this aircraft was missing: every other jet in the family
       has a trailing edge that sweeps, so even at the F-16's 72 px floor it
       is the only fast jet whose back edge is a ruler line.

    Third: the strakes. The LERX are what make an F-16 plan read as one
    continuous blended body from radome to wingtip instead of a tube with
    wings bolted to it, so they are now a four-point chine curving out from
    +/-0.34 m at 3.90 m aft to +/-1.32 m where they meet the wing apex at
    6.53 m, not the single flat triangle they were.

    Stations off the top view of art/reference/3v_f16_top.png (a crop of
    3v_f16.png, Wikimedia Commons), aft of the nose:

        body      +/-0.49 at 1.7 m, +/-0.94 at 5.1 m, +/-1.13 at 12 m
        strakes   3.90 m out to +/-1.32 where they meet the wing at 6.53 m
        wing      root LE 6.53 m, LE 40.0 deg, TE 11.60 m STRAIGHT across
        boom      aft fuselage 1.72 m across the speedbrake fairings -- 17 %
                  of the span, against the F-15's 3.42 m slab at 26 %. The old
                  model carried 2.26 m of aft body, as wide in proportion as
                  the Eagle's twin nacelles, on a single-engine aeroplane
        rails     wingtip launchers at +/-4.88, fore and aft of the tip chord
        tailplane 12.18 m aft, 5.58 m span, LE 40.0 deg  (real span 5.58 m)
    """
    L, SPAN = 15.06, 9.96
    N = L / 2.0
    SWP = math.tan(math.radians(40.0)) * (SPAN / 2.0 - 0.30)      # 3.927
    # Body: a superelliptic loft, not a stack of cones. Width, height, section
    # centre and squareness each vary independently along the body, which is
    # exactly what fuselage() could not express -- through the inlet this
    # aeroplane is 1.94 m wide against 1.64 m tall, its section centre travels
    # 0.11 m between inlet and spine, and the forebody is a rounded-off
    # triangle (sq 0.75, shoulders) rather than a circle. Stations are metres
    # from the datum with the nose positive, so they land on the +Y-forward
    # axis used here unchanged. w and h are HALF-dimensions.
    p = [loft([(6.20, 0.27, 0.26, 0.01),
               (5.50, 0.42, 0.40, 0.04),
               (4.70, 0.54, 0.50, 0.08, 0.90),
               (3.80, 0.64, 0.56, 0.08, 0.85),
               (2.80, 0.76, 0.66, 0.02, 0.80),
               (1.60, 0.90, 0.78, -0.03, 0.75),
               (0.20, 0.97, 0.82, -0.03, 0.75),
               (-1.40, 0.96, 0.81, -0.01, 0.78),
               (-3.00, 0.90, 0.77, 0.02, 0.80),
               (-4.60, 0.80, 0.70, 0.05, 0.85),
               (-6.00, 0.64, 0.58, 0.06, 0.90),
               (-7.00, 0.48, 0.47, 0.05),
               (-7.50, 0.41, 0.41, 0.05)], v=24, name="f16_fus")]
    use("gun")
    # Radome, then the pitot boom. The quoted 15.06 m is measured to the TIP
    # OF THE BOOM, so the radome closes at 7.08 and the boom runs the last
    # 0.45 m out to +N. Taking the study's 7.52 m radome tip literally and
    # then adding a boom in front of it would have made the aeroplane 15.9 m.
    p.append(loft([(7.08, 0.012, 0.012, 0.0),
                   (6.76, 0.115, 0.115, 0.0),
                   (6.15, 0.272, 0.262, 0.01)], v=20, name="f16_radome"))
    p.append(cyl((0, 7.31, 0.0), 0.022, 0.45, rot=(R(90), 0, 0), v=6))
    for s in (-1, 1):                                   # AoA probes
        p.append(cyl((s * 0.24, 6.45, 0.02), 0.016, 0.28, rot=(R(90), 0, 0), v=6))
    use("body")
    for s in (-1, 1):                                   # LERX chine, blended
        pts = [(s * 0.34, N - 3.90), (s * 0.62, N - 4.80), (s * 0.96, N - 5.60),
               (s * 1.32, N - 6.53), (s * 0.34, N - 6.53)]
        if s < 0:
            pts.reverse()
        p.append(plate(pts, 0.24, 0.0, f"lerx_{s}"))
    p += wings(N - 6.53, SPAN, 5.07, 1.15, SWP, 0.28, 0.0, "w")
    p += wings(N - 12.18, 5.58, 2.55, 0.76, 2.09, 0.22, 0.0, "h")
    p.append(fin(N - 9.20, 3.10, 4.70, 1.30, 3.10, 0.24, 0.35))
    use("deck")
    for s in (-1, 1):                                   # aft body fairings
        p.append(cube((s * 0.55, N - 12.10, 0.0), (0.62, 3.40, 0.86)))
        p.append(cyl((s * 4.88, N - 11.03, 0.05), 0.11, 3.40,   # wingtip rail
                     rot=(R(90), 0, 0), v=8))
        p.append(cyl((s * 2.30, N - 9.35, -0.55), 0.32, 3.60,   # underwing tank
                     rot=(R(90), 0, 0), v=10))
        p.append(cube((s * 2.30, N - 8.95, -0.22), (0.22, 1.20, 0.52)))  # pylon
        p.append(fin(N - 11.60, -0.85, 1.60, 0.80, 0.90, 0.14, -0.55,
                     offset_x=s * 0.62))                        # ventral fin
    use("gun")
    # Nozzle. This was a plain capped cylinder, and once the body around it
    # was lofted it read as a tin can taped to the back. A real afterburning
    # nozzle necks IN behind the fairing and flares back out at the petals,
    # and it is open, so the last station is a black throat rather than a lid.
    p += nozzle(-7.53, 0.50, 1.48, z=0.04, name="f16_nozzle")
    use("deck")
    # The chin inlet, which was a box with a cylinder stuck in it. It is now a
    # duct with a rolled LIP -- the section swells to 0.50 half-width at 2.80
    # and comes back to 0.46 at the throat, which is what makes an intake read
    # as an opening rather than as a pipe end.
    p.append(loft([(2.88, 0.44, 0.32, -0.78, 0.80),
                   (2.80, 0.50, 0.38, -0.78, 0.80),
                   (2.75, 0.46, 0.34, -0.78, 0.80),
                   (1.80, 0.50, 0.38, -0.72, 0.80),
                   (0.20, 0.52, 0.36, -0.62, 0.80),
                   (-1.20, 0.46, 0.28, -0.55, 0.85)], v=20, name="f16_duct",
                  cap=(False, True)))
    use("gunbore")                                      # the hole itself
    p.append(loft([(2.86, 0.44, 0.32, -0.78, 0.80),
                   (2.20, 0.28, 0.20, -0.76, 0.80)], v=20, name="f16_mouth",
                  cap=(False, True)))
    use("gun")
    p.append(cube((0, 2.60, -0.44), (0.52, 0.70, 0.03)))   # splitter plate
    use("body")
    # Canopy. The sill and the dorsal spine are what stop a bubble canopy from
    # looking like a bubble SITTING ON a tube: the sill is the frame line the
    # glass sits in, and the spine carries the fairing aft into the body
    # instead of letting the glass end in mid-air.
    p.append(loft([(3.30, 0.44, 0.50, 0.50),
                   (3.10, 0.42, 0.42, 0.46),
                   (2.30, 0.40, 0.26, 0.34),
                   (1.20, 0.36, 0.16, 0.24),
                   (0.00, 0.30, 0.08, 0.16)], v=16, name="f16_spine"))
    use("gun")
    p.append(loft([(5.55, 0.34, 0.045, 0.235),
                   (4.30, 0.475, 0.05, 0.26),
                   (3.05, 0.44, 0.045, 0.30)], v=12, name="f16_sill"))
    use("glass")
    p.append(dome((0, 4.15, 0.52), 0.46, 1.62, 0.50, v=20))
    use("body")
    p += _kit(SPAN, L, 0, canopy=False, tanks=0)
    return p, dict(top=0.9, hull_l=L, hull_w=SPAN, turret_top=1.9,
                   gun_z=0.2, gun_y=L * 0.34)


def strike():
    """Deep-penetration strike. GENERAL DYNAMICS F-111F AARDVARK, wings SPREAD.

    Was: a Tornado-dimensioned airframe (13.90 x 17.00, LE sweep 24.3, AR 3.56,
    twin canted fins, twin nozzles) that measured 0.8351 against sead() and
    0.7709 against air_superiority() — the fast-jet clique. It was an F-15 in a
    slightly different size, and no amount of stores was going to fix that.

    The F-111F is what a US deep-penetration bomb truck actually is, and it is
    a genuinely different airframe class from a fighter:

        length   73 ft 6 in      = 22.40 m   (the longest fast jet in the game)
        span     63 ft 0 in      = 19.20 m   spread, at the 16 deg wing setting
                 31 ft 11 in     =  9.74 m   at the 72.5 deg setting
        wing area 525 sq ft      = 48.77 m2  spread
        span/length 0.857, aspect ratio 7.6

    Modelled SPREAD, so both numbers above are the published spread pair, not a
    partial-sweep figure invented to hit a target. Spread is also the honest
    RTS pose: these are shown in cruise, and a swept F-111 would fold straight
    back into the long-thin-arrowhead family this refinement exists to break up.

    WHAT SEPARATES IT FROM ABOVE, in the brief's priority order:
      1. planform  a CRANK. The fixed glove leading edge is swept 65 deg and
         the pivoting outer panel only 16 deg, so the outline goes sharply back
         then abruptly straight out — no other aircraft in the roster has a
         leading-edge kink of 49 deg. Aspect ratio 7.4 against the fighters'
         3.0-3.2.
      2. proportion span/length 0.857 against superiority 0.673 and sead 0.502.
      3. engines    two, buried side by side in a wide flat aft body, nozzles
         only 1.7 m apart — against the F-15's 2.9 m spread pair.
      4. tail       ONE fin. The clique's shared cue was three near-identical
         twin-fin Vs; this aircraft leaves that group.
      5. contrast   dark radome, dorsal spine and glove walkways on top.

    Stations aft of the nose:
        radome     0 - 2.2
        capsule    2.5 - 5.9, and 1.9 m WIDE — side-by-side seating, so from
                   overhead it is a broad flat glass rectangle, not a tube
        glove      LE 5.30 at the body side, 9.20 at the pivot (BL 2.15)
        wing       root LE 9.60, root chord 3.75; tip LE 12.27, tip chord 1.35
        inlets     7.0 - 10.0 at +/-1.62, under the glove
        tailplane  16.90 - 21.10, 9.10 m span
        fin        LE 14.60, 4.60 m tall
    """
    L, SPAN = 22.40, 19.20
    N = L / 2.0
    # The F-111 seats its crew SIDE BY SIDE in an escape capsule, so the
    # forward fuselage is wide and flat where a fighter's is deep and narrow:
    # 2.16 m across against 1.72 m tall at the capsule, widening to 2.50 x 1.84
    # amidships. That proportion is most of why the aeroplane reads as a bomber
    # from above rather than as a big fighter, and it is worth stating that the
    # width is carried by the CABIN, not by the engines.
    p = [loft([(11.10, 0.05, 0.05, 0.00),
               (10.10, 0.30, 0.28, 0.00),
               (8.60, 0.60, 0.54, 0.03),
               (7.00, 0.86, 0.72, 0.06, 0.90),
               (5.20, 1.08, 0.86, 0.06, 0.82),
               (2.80, 1.22, 0.92, 0.02, 0.76),
               (0.00, 1.25, 0.92, 0.00, 0.72),
               (-3.00, 1.22, 0.88, 0.00, 0.72),
               (-6.00, 1.14, 0.84, 0.02, 0.75),
               (-8.60, 1.00, 0.78, 0.03, 0.82),
               (-10.40, 0.86, 0.70, 0.04),
               (-11.18, 0.78, 0.66, 0.04)], v=24, name="f111_fus")]
    for s in (-1, 1):                       # the fixed glove — 65 deg LE
        pts = [(s * 1.15, N - 5.30), (s * 3.00, N - 9.20),
               (s * 3.00, N - 13.20), (s * 1.15, N - 14.30)]
        if s < 0:
            pts.reverse()
        p.append(plate(pts, 0.40, 0.0, f"glove_{s}"))
    # Pivoting outer panels. Built as one full-span surface: everything inboard
    # of the BL 2.15 pivot is buried in the glove and the body, which is where
    # the real wing carry-through box lives too. area = 9.30*(3.75+1.35) + 2.3
    # = 49.7 m2 against the real 48.77, AR 7.42 against the real 7.56.
    p += wings(N - 9.60, SPAN, 3.75, 1.35, 2.67, 0.34, 0.0, "w")
    p += wings(N - 16.90, 9.10, 4.20, 1.20, 4.20, 0.30, 0.0, "h")
    p.append(fin(N - 14.60, 4.60, 6.40, 2.20, 4.00, 0.32, z=0.55))
    use("gun")
    for s in (-1, 1):                       # Triple Plow inlets, under the glove
        p.append(cyl((s * 1.62, N - 8.30, -0.28), 0.66, 3.40,
                     rot=(R(90), 0, 0), v=12))
        # nozzles: side by side and CLOSE. 1.70 m apart against the F-15's 2.90
        p += nozzle(-N, 0.62, 2.00, x=s * 0.85, z=-0.05, v=14,
                    name="f111_nozzle_%d" % s)
        for k in range(2):                  # swivelling pylons + stores
            y = N - (10.60 + k * 0.30)
            p.append(cube((s * (2.10 + k * 0.95), y + 0.55, -0.46),
                          (0.24, 1.40, 0.62)))
            p.append(cyl((s * (2.10 + k * 0.95), y, -0.92), 0.28, 3.00,
                         rot=(R(90), 0, 0), v=10))
    use("deck")
    p.append(dome((0, N - 1.10, 0.05), 0.72, 1.05, 0.62, v=16))       # radome
    p.append(cube((0, N - 11.60, 1.30), (0.66, 7.20, 0.26)))          # spine
    for s in (-1, 1):                                                 # walkway
        p.append(cube((s * 1.70, N - 10.40, 0.24), (0.34, 4.20, 0.10)))
    use("body")                             # side-by-side crew capsule, PROUD
    # The escape capsule seats the pilot and the WSO SIDE BY SIDE, so the
    # canopy is 1.9 m across instead of a fighter's 1.1 m — from directly
    # overhead it is a broad flat glass panel, not a bubble on a spine.
    p.append(cube((0, N - 4.20, 1.15), (1.92, 3.40, 0.46)))
    use("glass")
    p.append(dome((0, N - 4.26, 1.20), 0.88, 1.58, 0.30, v=16))
    use("body")
    return p, dict(top=1.25, hull_l=L, hull_w=SPAN, turret_top=2.6,
                   gun_z=0.2, gun_y=L * 0.34)


def cas():
    """Close air support: FAIRCHILD A-10A THUNDERBOLT II. Straight high-aspect
    wing, twin engines podded high on the REAR fuselage, twin fins on the tips
    of a rectangular tailplane, and the two main-gear pods that stick out
    FORWARD of the wing leading edge. The most distinctive planform in the air
    roster and the only fast jet that already measured as separated — every one
    of its six pairs sits below 0.52. So this pass does not touch the envelope:
    16.26 x 17.53 m stays exactly as it was.

    A-10A: length 16.26 m, span 17.53 m, wing area 47.0 m2, aspect ratio 6.54,
    tailplane span 6.1 m. Planform stations below were read off the top view of
    art/reference/3v_a10_top.png (a crop of 3v_a10.png), measured as distance
    aft of the nose:

        fuselage    ~1.5 m wide and near-CONSTANT from 1.8 m to 13 m aft
        wing        LE 6.8 m aft at the root, TE 10.3 m; tip chord 1.75 m
        gear pods   5.8 - 8.5 m aft at +/-2.55 m, i.e. AHEAD of the wing
        nacelles    9.9 - 13.0 m aft, outer edge +/-2.2 m
        tailplane   14.2 - 16.3 m aft, fins at +/-2.8 m

    Refined this pass, all inside the real airframe:
      - root chord 3.45 -> 3.55 m, which puts the wing area at 47.0 m2 and the
        aspect ratio at 6.54, both the published A-10A figures exactly (it was
        46.1 m2 / 6.66).
      - the inboard TRAILING-EDGE KINK at +/-3.40 m. The real inner wing is
        constant-chord — that is where the flaps are — and the taper only
        starts outboard of the nacelle pylons. It was modelled as one
        continuous taper from root to tip, so the kink that tells a viewer this
        is a two-section wing and not a glider's was missing.
      - the gun muzzle offset to PORT, which is where the firing barrel of a
        GAU-8/A actually sits, and made proud enough to read.
      - dark upper-surface walkways and nacelle crowns for camera contrast.

    The previous version hung the nacelles in mid-air with no pylon, so they
    were a detached island and the silhouette scorer dropped them entirely.
    """
    L, SPAN = 16.26, 17.53
    N = L / 2.0                                   # nose sits at y = +N
    # The A-10's nose is BLUNT because a 1.9 m cannon lives in it, and the
    # fuselage behind it barely tapers -- it is a straight-sided box with
    # rounded corners, not a fighter's waisted tube. Through the mid-body sq
    # holds at 0.86-0.88, which is what gives it square shoulders, and the
    # section is very nearly CONSTANT from 3.6 m ahead of the datum to 2.0 m
    # behind it: 1.56 m wide and no waist anywhere. Every other jet in this
    # file narrows somewhere; this one does not, and that is the shape cue.
    p = [loft([(8.05, 0.20, 0.20, 0.02),
               (7.60, 0.34, 0.33, 0.02),
               (6.80, 0.52, 0.50, 0.03, 0.95),
               (5.60, 0.66, 0.64, 0.05, 0.92),
               (3.60, 0.76, 0.74, 0.06, 0.88),
               (1.00, 0.78, 0.78, 0.04, 0.86),
               (-2.00, 0.78, 0.76, 0.02, 0.86),
               (-4.60, 0.72, 0.70, 0.02, 0.88),
               (-6.40, 0.62, 0.60, 0.02),
               (-7.60, 0.50, 0.48, 0.02),
               (-8.10, 0.44, 0.43, 0.02)], v=22, name="a10_fus")]
    Y0 = N - 6.78                                 # wing root leading edge
    p += wings(Y0, SPAN, 3.55, 1.75, 0.55, 0.34, -0.15, "w")
    for s in (-1, 1):                             # inboard constant-chord kink
        pts = [(s * 0.30, Y0 - 3.55), (s * 3.40, Y0 - 3.55 + 0.4576),
               (s * 3.40, Y0 - 3.55 - 0.2014)]
        if s < 0:
            pts.reverse()
        p.append(plate(pts, 0.34, -0.15, f"flap_{s}"))
    p += wings(N - 14.15, 6.10, 2.20, 1.90, 0.12, 0.26, 0.0, "h")
    for s in (-1, 1):                             # fins ON the tailplane tips
        p.append(fin(N - 13.90, 2.60, 2.40, 1.40, 0.95, 0.26,
                     offset_x=s * 2.80))
    use("gun")
    for s in (-1, 1):                             # podded TF34s + their pylons
        p += turbofan(N - 13.25, 0.68, 3.60, x=s * 1.62, z=0.86,
                      name="a10_pod_%d" % s)
        p.append(cube((s * 1.10, N - 11.45, 0.50), (1.20, 2.40, 0.60)))
    # GAU-8/A. The gun is on the centreline but the barrel that FIRES is the
    # one at nine o'clock, so the muzzle sits ~0.25 m to port of it — the one
    # asymmetry a real A-10 has, and it reads at the close camera.
    p.append(cyl((-0.24, N - 1.20, -0.12), 0.27, 2.40, rot=(R(90), 0, 0), v=12))
    use("deck")
    for s in (-1, 1):                             # main-gear pods, wing LE
        p.append(cyl((s * 2.55, N - 7.15, -0.42), 0.36, 2.80,
                     rot=(R(90), 0, 0), v=12))
        p.append(cube((s * 1.35, N - 8.20, 0.06), (0.40, 3.40, 0.10)))  # walkway
        p.append(cube((s * 1.62, N - 11.45, 1.48), (0.90, 3.00, 0.14)))  # crown
    p.append(cube((0, N - 3.05, 0.78), (0.70, 1.30, 0.08)))       # anti-glare
    use("body")                                   # bubble canopy, PROUD
    p.append(dome((0, N - 4.20, 0.70), 0.60, 1.35, 0.50, v=16))
    use("glass")
    p.append(dome((0, N - 4.16, 0.74), 0.54, 1.24, 0.48, v=16))
    use("body")
    p += _kit(SPAN, L, 0, canopy=False, tanks=0)
    return p, dict(top=1.2, hull_l=L, hull_w=SPAN, turret_top=2.2,
                   gun_z=0.2, gun_y=L * 0.40)


def bomber():
    """Heavy bomber, B-52H STRATOFORTRESS. 48.5 m long, 56.4 m span — the
    largest wing in the roster — with EIGHT engines in four twin pods and a
    pronounced droop.

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

    The planform above is verified and is NOT touched by this pass. What this
    pass adds is the top-down detail the reference shows and the model did
    not: the four PYLONS that hang the twin pods off the wing (without them
    eight nacelles floated under a clean wing and read as smudges), the two
    fixed 700-gallon external tanks on the outer panels, the tail turret at
    the extreme tail, and a dorsal spine plus wing walkways in a contrasting
    material — because the upper surface is the only surface the RTS camera
    ever sees. Against the KC-135 tanker it shares the sky with, the eight
    dark nacelles projecting 4 m ahead of a 36 deg leading edge are the cue,
    and they are now attached to something."""
    L, SPAN = 48.5, 56.4
    N = L / 2.0
    p = fuselage(L, 1.72,
                 stations=((0.00, 0.22), (0.02, 0.78), (0.05, 1.00),
                           (0.12, 1.00), (0.62, 1.00), (0.80, 0.92),
                           (0.92, 0.62), (1.00, 0.40)))
    p += wings(N - 9.05, SPAN, 9.90, 4.40, 20.40, 0.62, -0.55, "w")
    p += wings(N - 35.40, 16.40, 8.20, 1.70, 6.40, 0.44, 0.0, "h")
    p.append(fin(N - 39.20, 9.6, 9.0, 3.0, 6.2, 0.46, 1.2))
    use("gun")
    for s in (-1, 1):                       # four twin pods = eight nacelles
        for px, py, ply in ((9.65, N - 14.70, 6.90),
                            (17.55, N - 20.20, 1.30)):
            for e in range(2):
                p.append(cyl((s * (px + e * 1.70), py, -1.55), 0.85, 5.50,
                             rot=(R(90), 0, 0), v=12))
            # the pylon that carries the pair up to the wing. Between the two
            # nacelles and straddling the leading edge, so from above it reads
            # as one dark finger per pod instead of two floating tubes.
            p.append(cube((s * (px + 0.85), ply, -1.05), (0.26, 2.60, 1.00)))
        # fixed 700 US gal external tank on the outer panel — not a store,
        # the H model cannot drop them
        p.append(cyl((s * 23.00, -1.00, -1.28), 0.62, 6.60,
                     rot=(R(90), 0, 0), v=12))
        p.append(cyl((s * 23.00, 2.55, -1.28), 0.62, 0.90,
                     rot=(R(90), 0, 0), v=12, taper=0.24))
        p.append(cube((s * 23.00, -0.20, -0.92), (0.22, 2.20, 0.90)))
    # tail turret. The H flew with a 20 mm Vulcan back there until 1991 and
    # the fairing is still the widest thing at the extreme tail.
    p.append(dome((0, -N + 1.30, 0.02), 0.86, 1.30, 0.78, v=16))
    for s in (-1, 1):
        p.append(cyl((s * 0.30, -N + 0.55, 0.02), 0.10, 1.35,
                     rot=(R(90), 0, 0), v=8))
    use("deck")
    p.append(cube((0, 1.0, -1.95), (2.60, 9.00, 0.70)))          # bomb bay
    # upper-surface contrast: dorsal spine and the two wing walkways
    p.append(cube((0, N - 20.00, 1.72), (0.72, 15.00, 0.26)))
    for s in (-1, 1):
        p.append(cube((s * 4.60, 8.50, -0.27), (0.42, 5.00, 0.14)))
    use("glass")
    p.append(cube((0, N - 3.60, 1.58), (1.34, 3.20, 0.34)))      # flight deck
    use("body")
    return p, dict(top=1.8, hull_l=L, hull_w=SPAN, turret_top=5.0,
                   gun_z=0.4, gun_y=L * 0.32)


def stealth_bomber():
    """Flying wing, B-2A SPIRIT: 52.43 m span, 21.03 m long, leading edge swept
    33 deg, no fuselage, no vertical surface of any kind.

    Epoch 4+. This is the airframe that makes the fourth-root RCS cliff in
    docs/02 matter: a radar seeing a 4th-gen fighter at 200 km sees this at
    roughly 11 km.

    THE PLANFORM IS NOW THE REAL ONE. The previous build sat at 28.1 deg of
    leading-edge sweep with a shallow trailing-edge sawtooth, and measured
    19.69 m long against the 21.03 m it declared. At the true 33 deg the tip
    falls 17.02 m aft of the apex -- 4.0 m FORWARD of the tail, which is what
    makes the double-W trailing edge possible at all -- and the resulting
    plan area is 482 m2 against the published 478 m2 wing area. That 1% match
    is the check that the sweep and the sawtooth are both right; a shallower
    sweep or a deeper sawtooth misses it by 15%.

    THE DOUBLE-W. One aft point on the centreline (the beaver tail, the aft
    extremity of the aircraft), one forward notch and one aft peak per side,
    then the tip. Six trailing-edge vertices per side. This is the feature
    that separates it from every four-engined swept-wing aircraft in the
    roster at a glance, and unlike a pod or a store it is the outline itself,
    so it survives LOD2 -- and a B-52 never falls below 407 px anyway.

    Tiering: the wing is thin at the tips and 2.2 m deep on the centreline,
    so it is built as three stacked plates that shrink inboard-to-outboard,
    with the two upper-surface intakes and the two exhaust troughs sitting on
    the middle tier. Every duct is on TOP of the wing, which is both the real
    aircraft and the only thing the RTS camera can see."""
    L, SPAN = 21.03, 52.43
    ny, hs = L / 2.0, SPAN / 2.0
    tip_y = ny - hs * math.tan(R(33.0))            # -6.509: the 33 deg LE

    def mirror(right):
        return right + [(-x, y) for (x, y) in reversed(right[1:-1])]

    plan = mirror([(0.00, ny), (hs, tip_y),
                   (20.40, -8.60), (15.20, -4.60),       # outer peak, notch
                   (9.90, -9.10), (4.60, -5.20),         # inner peak, notch
                   (0.00, -ny)])                         # beaver tail
    tier2 = mirror([(0.00, 9.90), (11.50, -0.90), (10.60, -6.60),
                    (0.00, -9.60)])
    centre = mirror([(0.00, 9.40), (4.20, 0.60), (3.60, -6.20),
                     (0.00, -8.60)])
    use("body")
    # ONE continuous tapered shell, not three stacked plates. The planform is
    # untouched -- span, length and the 478 m2 plan area all still hold -- but
    # it now has a section: thickness falls to a taper at the leading edge,
    # the trailing edge and the tips, and swells over the centre-body. The old
    # 1.00 / 1.30 / 1.30 m constant-thickness tiers had vertical risers between
    # them, and a stack of slabs is what reads as a toy brick from every angle
    # except directly overhead.
    #
    # The centre-body and the cockpit fairing are bumps ADDED to the section
    # rather than objects sitting on it, which is how they are on the aircraft:
    # the crown swells out of the wing with no seam anywhere.
    p = [aerofoil(plan, 1.05, "b2_shell", cuts=5, under=0.34, power=0.58,
                  extra=[(0.0, -0.60, 12.0, 0.95),      # centre-body
                         (0.0, 6.10, 4.20, 0.55)])]     # cockpit fairing
    for s in (-1, 1):
        # one serpentine intake per side, each feeding two F118s, buried in
        # the UPPER surface where no ground radar and no RTS camera looks up.
        # The fairing is in the airframe's own material; only the mouth and
        # the exhaust slot are dark, because four pale rectangles on a grey
        # wing read as decals rather than as structure.
        # settled into the crown rather than perched on it
        p.append(cube((s * 5.60, 1.60, 1.12), (4.30, 3.60, 0.42),
                      rot=(R(-8), 0, 0)))
    use("gunbore")
    for s in (-1, 1):
        p.append(cube((s * 5.60, 3.15, 1.44), (3.90, 0.50, 0.34),
                      rot=(R(-8), 0, 0)))                    # intake mouth
        p.append(cube((s * 5.20, -4.35, 1.30), (3.10, 0.62, 0.26)))
        # the shielded exhaust trough, RECESSED and dark: a slot cut into the
        # upper deck running aft from the nozzle to the trailing edge. It was
        # a raised pale slab, which is exactly the "pale rectangle reads as a
        # decal" failure the intake note above warns about — two tan plates on
        # a grey wing were the loudest thing on the aeroplane and they were
        # the one part of it that is not structure.
        p.append(cube((s * 5.20, -5.95, 1.22), (3.50, 2.70, 0.26)))
    use("deck")
    for s in (-1, 1):
        # the heat-tile floor of the trough, inset inside the dark slot so it
        # reads as a lit strip at the bottom of a groove rather than a plate
        # stuck on the surface
        p.append(cube((s * 5.20, -6.05, 1.20), (2.30, 2.10, 0.24)))
    use("glass")
    # the cockpit. Four large forward windows in a low bulge on the centreline
    # — the only break in the leading-edge slope and the only thing on the
    # upper surface with a horizon in it. It was a 0.95 m dome, invisible on a
    # 52 m wing; the real canopy is 2.6 m across.
    # Sunk INTO the fairing that is now part of the shell, so only the glass
    # shows. It used to be a disc floating clear of the surface.
    p.append(dome((0, 6.30, 1.66), 1.14, 2.30, 0.30, v=16))
    use("body")
    return p, dict(top=2.20, hull_l=L, hull_w=SPAN, turret_top=2.6,
                   gun_z=0.5, gun_y=6.0)


# ── SEAD vs ELECTRONIC ATTACK: the silhouette contract ─────────────
# These two fly the same mission slice of docs/02 from opposite ends — SEAD
# kills the emitter, the jammer blinds it without firing — so a player who
# cannot tell them apart cannot play either pillar. They were once the same
# mesh: electronic_attack() called sead() and appended three belly pods that
# hang UNDER the wing, where the RTS camera never sees them.
#
# The first repair gave each aircraft a planform element the other could not
# have: sead() owned TWIN CANTED FINS, electronic_attack() owned ONE TALL
# CENTRE FIN with the receiver football on top. That worked on its own terms —
# the pair measured 0.5634 — but it solved the wrong problem. Fin count is a
# two-state cue, and there are seven fast jets: air_superiority(), strike() and
# the old sead() ALL carried twin canted fins at 6-8 deg, so from overhead they
# were three identical Vs and the trio measured 0.77, 0.84 and 0.88 against
# each other. The contract had protected sead() from the jammer and left it
# fused to the fighters instead.
#
# So the separation now rests on the AIRFRAME, which is a seven-state cue, not
# a two-state one, and it comes from real lineage rather than from styling.
# US defence suppression has always been a FIGHTER — F-100F, F-105G, F-4G,
# F-16CJ — while US electronic attack has always been a wide-winged multi-crew
# ATTACK airframe: EB-66, EA-6A from 1963, then EA-6B and EF-111A. Build each
# as what it is and they cannot converge:
#
#   sead()               F-105F/G Thunderchief Wild Weasel III, 10.65x21.21 m.
#                        span/length 0.502 — the narrowest airframe in the
#                        roster — 49 deg of leading-edge sweep, aspect ratio
#                        3.1, ONE engine, ONE fin, an area-ruled waist and the
#                        forward-swept wing-root intakes.
#
#   electronic_attack()  EA-6B Prowler, 16.15 x 18.24 m. span/length 0.885,
#                        23 deg of sweep, aspect ratio 5.2, ONE tall centre fin
#                        capped by the receiver football, and a 5.4 m four-seat
#                        greenhouse — a big flat glass area seen from overhead.
#
# 0.502 against 0.885 is the widest proportion gap in the fast-jet family, and
# 49 deg against 23 deg is the widest sweep gap. Neither number can be reached
# from the other without abandoning the real aircraft.
#
# RULE: sead() never gets a jamming pod and never gets a second engine;
# electronic_attack() never gets a missile and never loses its greenhouse. The
# span/length figures above are load-bearing — if a future edit moves one
# aircraft's proportion toward the other's, it has to move the other one too,
# or the pair collapses. Do not implement one by calling the other.
def sead():
    """Defence suppression — the SEAD duel of docs/02. REPUBLIC F-105F/G
    THUNDERCHIEF WILD WEASEL III.

    Was: an F/A-18E, 13.60 x 18.30 m, twin canted fins, twin nozzles, mid-sweep
    trapezoid wing. That is the same aircraft as air_superiority() in a slightly
    smaller size, and it measured it: 0.8817 against the F-15 and 0.8351
    against strike(), the two worst pairs in the entire 210-pair air roster.
    The audit's own words were "I genuinely cannot tell the sead from the
    superiority fighter at gameplay size". Adding anti-radiation missiles had
    bought 0.09 of IoU and all of it vanished at LOD2.

    A Super Hornet was also the wrong aircraft for this slot on its own terms.
    The unit id is air_e2_us_sead — epoch 2, 1960-1969 by docs/05 — and an
    F/A-18E is a 1999 aeroplane, epoch 5. The epoch-2 US Wild Weasel is the
    two-seat F-105F, which took over the mission from the F-100F in 1966 and
    flew it at scale over Route Pack VI; the F-105G is the same airframe with
    the ALQ-105 fitted, so the geometry below covers both. It is also the type
    electronic_attack()'s own docstring already cites as the SEAD lineage.

        F-105F/G   length 69 ft 7 in  = 21.21 m   (F-105D single-seat: 19.63 m)
                   span   34 ft 11 in = 10.65 m
                   wing area 385 sq ft = 35.77 m2, 45 deg at quarter chord
                   span/length 0.502, aspect ratio 3.17

    That proportion is the point. 0.502 against the F-15's 0.673, the F-16's
    0.652 and the F-4's 0.609 — the fast jets were living in a 0.21-wide window
    from 0.609 to 0.818, and this airframe is REALLY outside it. Nothing has
    been stretched: it is a 10.65 m wing on a 21.21 m aeroplane because the
    F-105 was the heaviest single-seat single-engine fighter ever built and
    carried its bomb load internally, so it is all fuselage.

    WHAT SEPARATES IT FROM ABOVE, in the brief's priority order:
      1. planform  49 deg of leading-edge sweep, the steepest manned wing in
         the roster, on an aspect ratio of 3.1. Against strike()'s 16 deg glove
         crank and cas()'s 4 deg straight wing.
      2. proportion 0.502. The narrowest thing with a pilot in it.
      3. engines   ONE. A single centred nozzle, against the F-15's and the old
         F/A-18's paired ones — and the forward-swept wing-root intakes throw a
         pair of shoulders out to +/-1.70 m at 30-60% of length, which is a
         planform element no other fast jet has.
      4. tail      ONE fin, and a large one. It leaves the twin-canted-fin
         clique that superiority and the old strike shared.
      5. contrast  black radome, black dorsal spine down the whole upper deck.

    Stations aft of the nose:
        radome     0 - 2.3
        canopy     3.4 - 8.0, tandem two-seat (the Weasel's bear in the back)
        intakes    6.1 - 12.8, out to +/-1.70, LE raked FORWARD as it goes out
        wing       root LE 9.70, root chord 5.05; tip LE 15.53, tip chord 1.55
        waist      area rule pinches the body to 82% at 50% of length
        fin        LE 13.60, 3.60 m tall, root chord 5.60
        stabilator 16.30 - 20.45, 5.60 m span

    It carries NO jamming pod. The real F-105G's ALQ-105 lived in two shallow
    strakes blended into the lower fuselage sides, invisible from any camera
    this game uses, and a visible jamming pod is what fused this aircraft to
    electronic_attack() in the first place — see the contract above.
    """
    L, SPAN = 21.21, 10.65
    N = L / 2.0
    # Area-ruled body: widest at the inlets, pinched to 82% over the wing, then
    # swelling again for the afterburner can. On a 21.21 x 10.65 planform that
    # waist is what stops the fuselage reading as a plain tube.
    # A Thunderchief is area-ruled like the F-106 but much bigger, and it is
    # the waist plus the sheer 21 m length that reads at a glance. Same
    # treatment: the waist is now a genuine narrowing in BOTH axes rather than
    # a smaller circle, which is what makes it visible from above.
    p = [loft([(10.55, 0.04, 0.04, 0.00),
               (9.40, 0.24, 0.23, 0.00),
               (7.90, 0.48, 0.45, 0.02),
               (6.30, 0.68, 0.62, 0.05, 0.94),
               (4.40, 0.86, 0.76, 0.06, 0.88),
               (2.40, 0.98, 0.84, 0.02, 0.84),
               (0.00, 0.92, 0.82, 0.00, 0.86),
               (-2.60, 0.84, 0.78, 0.00, 0.88),
               (-5.00, 0.92, 0.84, 0.01, 0.90),
               (-7.40, 0.88, 0.80, 0.02),
               (-9.40, 0.72, 0.68, 0.02),
               (-10.15, 0.62, 0.60, 0.02)], v=22, name="f105_fus")]
    for s in (-1, 1):        # forward-swept wing-root intakes, +/-1.70 shoulders
        pts = [(s * 0.55, N - 7.30), (s * 1.70, N - 6.10),
               (s * 1.70, N - 11.20), (s * 0.55, N - 12.80)]
        if s < 0:
            pts.reverse()
        p.append(plate(pts, 1.10, -0.10, f"inlet_{s}"))
    # 49.2 deg leading edge. area = 5.025*(5.05+1.55) + 0.6*5.05 = 36.2 m2
    # against the real 35.77; aspect ratio 3.13 against the real 3.17.
    p += wings(N - 9.70, SPAN, 5.05, 1.55, 5.83, 0.30, 0.0, "w")
    p += wings(N - 16.30, 5.60, 3.10, 1.05, 2.55, 0.26, 0.0, "h")
    p.append(fin(N - 13.60, 3.60, 5.60, 1.90, 3.10, 0.28, z=0.42))
    p.append(fin(-6.20, -1.05, 2.80, 1.50, 1.20, 0.22, z=-0.60))   # ventral fin
    use("gun")
    p += nozzle(-10.60, 0.66, 1.10, z=0.02, name="f105_nozzle")
    # Anti-radiation missiles. By the brief these carry NO identification —
    # they are gone at LOD2 and invisible overhead — so they are detail, not
    # separation. AGM-78 Standard ARM inboard, AGM-45 Shrike outboard.
    for s in (-1, 1):
        p.append(cube((s * 2.30, -1.60, -0.40), (0.22, 1.30, 0.52)))
        p.append(cyl((s * 2.30, -1.10, -0.72), 0.17, 4.10,
                     rot=(R(90), 0, 0), v=10))
        p.append(cyl((s * 2.30, 1.19, -0.72), 0.17, 0.48,
                     rot=(R(90), 0, 0), v=10, taper=0.10))
        p.append(cube((s * 3.60, -3.70, -0.40), (0.20, 1.20, 0.48)))
        p.append(cyl((s * 3.60, -3.20, -0.74), 0.14, 2.60,
                     rot=(R(90), 0, 0), v=10))
        p.append(cyl((s * 3.60, -1.68, -0.74), 0.14, 0.44,
                     rot=(R(90), 0, 0), v=10, taper=0.10))
    p.append(cyl((0, -0.60, -1.20), 0.45, 5.60, rot=(R(90), 0, 0), v=12))
    use("deck")
    p.append(dome((0, N - 1.15, 0.02), 0.52, 1.10, 0.48, v=16))       # radome
    p.append(cube((0, -1.20, 0.86), (0.56, 7.00, 0.24)))              # spine
    use("body")             # 4.6 m tandem two-seat canopy, PROUD of the spine
    p.append(dome((0, N - 5.70, 0.72), 0.60, 2.30, 0.42, v=16))
    use("glass")
    p.append(dome((0, N - 5.66, 0.76), 0.54, 2.16, 0.40, v=16))
    use("body")
    return p, dict(top=1.0, hull_l=L, hull_w=SPAN, turret_top=2.2,
                   gun_z=0.2, gun_y=L * 0.34)


def stealth_strike():
    """Stealth strike. This is an F-117A NIGHTHAWK: 20.09 m long, 13.20 m span,
    leading edge swept 67.5 deg, no vertical fin, no tailplane, a V-tail of two
    all-moving ruddervators canted 40 deg, and a faceted body that IS the wing.

    WHY THE F-117 AND NOT THE F-35. The audit measured this slot at 0.75 IoU
    against the F-16 multirole -- the fifth worst pair in the roster -- because
    the previous build carried F-35A dimensions (10.70 x 15.70, LE sweep 42
    deg), and an F-35 really is an F-16-sized cropped delta. Seven degrees of
    extra sweep cannot separate two aircraft that are the same family, the same
    size and the same proportion. The F-117 is the aircraft docs/12 actually
    describes -- "Stealth strike aircraft, epoch 4, the fourth-root cliff
    arrives", which is Baghdad 1991, not Lightning II -- and it is the only
    combat jet in the roster whose planform is a single unbroken dart. Measured
    against the same F-16 it lands at 0.596 shape / 0.604 at 60 px. That
    second figure is a measurement AT 60 px, not a claim that it ever appears
    that small: an F-117 bottoms out at 95 px.

    THE PLANFORM IS THE WHOLE AIRCRAFT. Apex on the nose, one straight 67.5 deg
    leading edge to each tip (tan 67.5 = 2.414, so a 6.60 m semi-span puts the
    tip 15.93 m aft of the nose, at 79% of length), then the W-SHAPED TRAILING
    EDGE the four faceted elevons cut -- two outboard and two inboard, with the
    kink between them at the aftmost point of the aeroplane and a 2.42 m notch
    on the centreline between the two exhaust troughs. Total plan area 142 m2.
    Nothing projects from it: no fin above, no stabiliser behind, no wingtip
    outboard of the leading edge. Every other fast jet in the roster is a
    fuselage with surfaces attached; this one has no fuselage to attach them to.

    THE W IS NOT A STYLING CHOICE, and it is not shared with stealth_bomber().
    The B-2 carries a DOUBLE W -- six trailing-edge vertices per side over a
    52.43 m span -- against this aircraft's one kink and one notch over 13.20 m.
    The two are four times apart in span, so the shared-metric-scale IoU between
    them cannot exceed the ratio of their plan areas, 142/482 = 0.29, whatever
    the outline metric says once size is normalised away. They are the two
    tailless aircraft in the roster and reading as a family is correct.

    The upper surface is six interpolated facet tiers converging on a
    centreline ridge, because that faceting is what the RTS camera sees of a
    shape that is otherwise a black triangle, and the two exhaust decks and
    two grid-covered intakes give it the material contrast the brief asks for
    at priority 5."""
    L, SPAN = 20.09, 13.20
    ny, hs = L / 2.0, SPAN / 2.0
    tip_y = ny - hs * math.tan(R(67.5))            # -5.885: the 67.5 deg LE

    def mirror(right):
        return right + [(-x, y) for (x, y) in reversed(right[1:-1])]

    # tier 1: the true planform. Wingtip chord is short and raked; the
    # trailing edge runs forward from the platypus tail to the tip.
    # THE W TRAILING EDGE. Per side: the tip chord, then aft-inboard along the
    # OUTBOARD elevon to the aircraft's aftmost point at +/-3.40 m, then
    # forward-inboard along the INBOARD elevon to the centreline notch between
    # the two exhaust troughs. Left tip to right tip that reads high-low-high-
    # low-high: a W, which is what the four faceted elevons of the real
    # aircraft produce. The previous build ran a smooth arrow from each tip to
    # a single point on the centreline, which made the tail the fullest part
    # of a convex dart -- and the F-15 it is measured against parks its
    # fuselage, nozzles and inboard stabilator root in exactly that centreline
    # wedge. The notch is 2.42 m deep and takes span and length with it: the
    # aftmost points are still 20.09 m from the apex and the tips still
    # +/-6.60 m.
    plan = mirror([(0.00, ny), (hs, tip_y), (hs - 0.30, -7.30),
                   (3.40, -ny), (0.00, -7.62)])
    ridge = mirror([(0.00, 7.40), (2.10, -0.55), (1.95, -5.55),
                    (1.60, -8.55), (0.00, -6.55)])
    use("body")
    # ONE faceted shell through the same stations, not six stacked plates.
    # The stations were always right -- plan and ridge correspond vertex for
    # vertex, so they interpolate cleanly -- but plate() extrudes each one
    # straight up at constant thickness, which left a 0.4-0.5 m VERTICAL riser
    # between every tier. Six risers is a staircase, and a staircase is what
    # reads as a toy brick. Bridging the stations instead gives sloping walls,
    # which is what a facet is.
    #
    # The underside is a shallow inverted vee rather than a flat pan, because
    # the real aircraft's lower surface is faceted too and a flat bottom shows
    # as a hard bright edge all round the planform.
    def at(t):
        return [(a[0] + t * (b[0] - a[0]), a[1] + t * (b[1] - a[1]))
                for a, b in zip(plan, ridge)]

    p = [shell([(at(0.10), -0.30), (at(0.00), -0.08), (at(0.00), 0.19),
                (at(0.22), 0.59), (at(0.44), 0.97), (at(0.66), 1.36),
                (at(0.85), 1.72), (at(1.00), 2.03)], "f117_hull")]
    # OWNED: a V-TAIL and no other vertical surface. Two all-moving
    # ruddervators canted 40 deg off vertical, so from directly above they
    # read as two blades splaying aft-outboard from the tail -- not the
    # near-parallel twin fins the superiority/strike/sead clique all carry.
    for s in (-1, 1):
        p.append(fin(-5.20, 3.30, 2.95, 1.15, 1.95, 0.26,
                     z=1.30, cant=40 * s, offset_x=s * 0.55))
    for s in (-1, 1):
        # intake fairings, ON TOP of the wing at the root leading edge, in the
        # airframe's own material with only the grid-covered mouth dark. Built
        # as pale panels they read as two stickers stuck to the wing.
        p.append(cube((s * 1.65, 3.10, 1.15), (1.16, 1.90, 0.46),
                      rot=(R(-7), 0, 0)))
    use("gunbore")
    for s in (-1, 1):
        p.append(cube((s * 1.65, 3.92, 1.20), (1.02, 0.26, 0.34),
                      rot=(R(-7), 0, 0)))
    use("gunbore")
    for s in (-1, 1):
        # the platypus trough itself: the darkest thing on a black aeroplane,
        # a slot recessed into the aft deck between the ruddervator and the
        # trailing edge.
        p.append(cube((s * 2.05, -7.90, 0.96), (2.50, 3.10, 0.22)))
    use("deck")
    for s in (-1, 1):
        # the pale heat tiles that line it. On the real aircraft these are the
        # ONLY light-toned area on an otherwise matt-black airframe, so at
        # gameplay size they are two small bright marks near the tail — but
        # they have to stay small, or a 13 m aeroplane reads as two white
        # plates with a dark border. 1.55 x 2.20 m each, 5% of the plan.
        p.append(cube((s * 2.05, -7.90, 1.06), (1.55, 2.20, 0.14)))
    use("glass")
    # faceted five-panel canopy, flat plates rather than a bubble
    p.append(cube((0, 5.15, 2.16), (1.30, 1.95, 0.44), rot=(R(-6), 0, 0)))
    p.append(cube((0, 6.32, 2.00), (1.00, 0.95, 0.34), rot=(R(-22), 0, 0)))
    use("body")
    return p, dict(top=2.10, hull_l=L, hull_w=SPAN, turret_top=3.5,
                   gun_z=0.3, gun_y=L * 0.30)


# ── enablers ───────────────────────────────────────────────────────
def aewc():
    """Boeing E-3B Sentry, on the 707-320B airframe: 44.42 m span, 46.61 m
    long, wing area 283.4 m^2 (AR 6.96), leading edge swept 35 deg.

    Pillar 5. The ROTODOME is the clearest single identifier in the game and
    it is built to its real size — 9.14 m across and 1.83 m deep, which is
    20% of this aircraft's length sitting as a hard disc on top of an
    otherwise plain airliner plan. It is 'deck' dark grey on an air_white
    fuselage, so from the fixed overhead camera it is a black circle on a
    white cross. Nothing else in the roster is a circle.

    It shares an airframe with tanker(): both are 707s and pretending
    otherwise would be a fake. The honest separators are the rotodome here
    and the trailing boom there, plus the engines — this keeps the original
    slim low-bypass TF33 pods (1.56 m nacelle) where the KC-135R was
    re-engined with the fat CFM56 (2.15 m).
    """
    L, SPAN = 46.61, 44.42
    p = fuselage(L, 1.88, 0.52, 0.52)
    # semispan 22.21, panel root at x=0.30, so sweep 15.35 => LE 35.1 deg.
    p += wings(7.4, SPAN, 9.2, 3.0, 15.35, 0.60, -0.62, "w")
    p += wings(-16.2, 14.35, 4.8, 1.9, 4.4, 0.44, 0.0, "h")
    p.append(fin(-14.0, 8.4, 8.6, 2.9, 6.0, 0.44, 1.05))
    use("gun")
    for s in (-1, 1):                              # four TF33 pods on pylons
        for k, (x, y) in enumerate(((5.9, 1.6), (10.6, -1.6))):
            p.append(cyl((s * x, y, -1.55), 0.78, 5.60,
                         rot=(R(90), 0, 0), v=14))
            p.append(cube((s * x, y + 1.90, -1.05), (0.34, 2.20, 0.95)))
    use("deck")
    # THE ROTODOME. Real AN/APY-1 dimensions: 9.14 m diameter, 1.83 m deep,
    # 4.2 m above the fuselage on two struts, centred well aft of the wing.
    p.append(cyl((0, -6.40, 5.05), 4.57, 1.83, v=32))
    p.append(cyl((0, -6.40, 5.05), 4.62, 0.34, v=32))            # rim band
    for s in (-1, 1):                                            # the struts
        p.append(cube((s * 1.05, -6.40, 3.05), (0.42, 3.10, 2.90)))
    p.append(cube((0, -6.40, 1.90), (2.60, 3.40, 0.70)))         # strut base
    use("body")
    p.append(cyl((0, 5.60, 1.72), 0.44, 2.20, rot=(R(90), 0, 0), v=10))  # SATCOM
    use("glass")
    p.append(dome((0, L * 0.40, 0.66), 0.70, 1.60, 0.42, v=16))
    use("body")
    return p, dict(top=2.1, hull_l=L, hull_w=SPAN, turret_top=5.9,
                   gun_z=0.4, gun_y=L * 0.30)


def aew_helo():
    """Westland Sea King AEW2 / ASaC.7 — the UK compromise (docs/08): a rotor
    aircraft with a radar bulge. ~3 km altitude gives ~235 km horizon against
    ~400 km for a fixed-wing AEW.

    Real Sea King: main rotor 18.90 m over FIVE blades, fuselage 17.02 m,
    tail rotor 3.16 m on the port side, boat hull with sponsons.

    Two things carry it from overhead. The rotor is the ONLY five-blade disc
    in the roster — attack, transport and ASW are all four-blade, so a parked
    five-blade star cannot be read as any of them at any azimuth. And the
    Searchwater bag swings down on the STARBOARD side: a 2.9 m ovoid hung
    clear of the fuselage, asymmetric, which no other rotary unit has.
    """
    L, ROTOR = 17.02, 18.90
    p = _at(fuselage(11.60, 1.42, 0.62, 0.40, z=1.35,
                     stations=((0.00, 0.10), (0.06, 0.52), (0.15, 0.84),
                               (0.26, 1.00), (0.60, 1.00), (0.80, 0.84),
                               (1.00, 0.46))),
            L * 0.5 - 6.10)
    p.append(cube((0, -L * 0.31, 1.55), (0.78, L * 0.40, 0.86)))   # tail boom
    p += wings(-L * 0.44, 4.60, 1.70, 1.05, 0.55, 0.22, 1.50, "h")
    p.append(fin(-L * 0.375, 2.60, 2.40, 1.10, 1.20, 0.24, 1.75))
    use("deck")
    # The Searchwater radome, lowered to starboard. A 2.9 m bag on a 17 m
    # airframe, standing clear of the hull so it breaks the plan outline.
    p.append(dome((2.35, 0.70, 0.85), 1.12, 1.45, 1.05, v=18))
    p.append(cube((1.35, 0.70, 1.55), (1.30, 0.90, 0.70)))         # swing arm
    for s in (-1, 1):                                              # sponsons
        p.append(cube((s * 1.55, -0.20, 0.72), (0.80, 3.10, 0.62)))
    use("body")
    p.append(cyl((0, 0.90, 2.55), 0.34, 0.90, v=14))               # rotor head
    p += _rotor(5, ROTOR, 2.95, y0=0.90, phase=18.0, chord=(0.30, 0.22))
    use("gun")                                        # 3.16 m tail rotor, port
    p.append(cyl((-0.52, -L * 0.46, 2.30), 1.58, 0.24,
                 rot=(0, R(90), 0), v=14))
    use("body")
    p += _heli_glass(L * 0.5 - 1.55, 2.05, 1.05, 1.40, 0.60)
    return p, dict(top=2.0, hull_l=L, hull_w=ROTOR, turret_top=3.0,
                   gun_z=1.3, gun_y=L * 0.20)


def electronic_attack():
    """Airborne jamming — the pillar-3 aircraft. GRUMMAN EA-6A INTRUDER,
    16.15 m span x 16.92 m long (53 ft 0 in x 55 ft 6 in), wing area 49.1 m2,
    aspect ratio 5.31, leading edge swept 25 deg.

    A SEPARATE AIRFRAME from sead(), not sead() with pods bolted on — see the
    silhouette contract above. That contract now holds comfortably: sead() is
    an F-105F Wild Weasel at 10.65 x 21.21 (span/length 0.502) and this is a
    wide-winged carrier attack airframe at 0.955. Nothing here narrows toward
    the fighter.

    WHY THE EA-6A AND NOT THE EA-6B. Two reasons, and they point the same way.

      Epoch. The unit id is ewa_e2_us_electronic — epoch 2, 1960-1969 by
      docs/05. The EA-6B Prowler first flew in 1968 and reached the fleet in
      1971, which is epoch 3. The epoch-2 US electronic attack aircraft is the
      EA-6A: the electronic prototype flew on 26 April 1963 and Marine VMCJ
      squadrons flew it over North Vietnam alongside the F-105F/G Wild Weasels
      that sead() is now built as. The contract paragraph above already named
      "EA-6A from 1963 — epoch 2" as this slot's aircraft; the geometry simply
      had not caught up. Same correction, same reasoning, as the F/A-18E ->
      F-105F move in sead().

      Separation. strike() is now an F-111 with the wings spread — 19.20 x
      22.40, span/length 0.857 — and the EA-6B's 16.15 x 18.24 is span/length
      0.885. Those two numbers are within 3% of each other, so the pair
      measured 0.7069 shape / 0.7082 stretch: the proportion cue was carrying
      nothing at all and the two aircraft were one swept-wing two-seat attack
      jet in two sizes, which is exactly the failure the fast-jet pass was
      called in to fix. The EA-6B is an EA-6A with a 1.32 m fuselage plug
      ahead of the wing for the two extra crew; taking the plug out is a
      REAL-DIMENSIONS correction, not a stretch, and it moves span/length to
      0.955 and cuts plan area to 63% of the F-111's.

    WHAT SEPARATES IT FROM ABOVE, in the brief's priority order:
      1. planform  25 deg of leading edge on an aspect ratio of 5.31, with a
         near-unswept trailing edge (0.41 m of aft sweep across a 7.775 m
         semi-span, 3 deg) — a triangular panel, not the near-parallel
         trapezoid the fighters carry and not the F-111's 16 deg high-aspect
         glove-and-panel.
      2. proportion 0.955, against strike 0.857 and sead 0.502.
      3. engines   TWO J52s buried in the fuselage sides at the wing root, so
         the body is at its widest — 4.1 m across the intakes — at 40% of
         length and nothing projects ahead of the leading edge. The four-engine
         aircraft it might otherwise be read against all hang pods forward.
      4. tail      ONE tall centre fin capped by the ECM canoe.
      5. contrast  the side-by-side two-seat canopy is a 3.3 m flat glass box
         on a 16.9 m aeroplane, and the fin canoe is the highest thing on it.

    Stations aft of the nose:
        radome     0 - 2.0
        canopy     3.2 - 6.5, side by side (pilot left, ECMO right)
        intakes    5.4 - 8.6, fuselage sides, out to +/-2.05
        wing       root LE 7.16, root chord 4.66; tip LE 10.79, tip chord 1.44
        fin        LE 12.31, 2.48 m tall, root chord 4.35
        canoe      13.9 - 16.8, on the fin tip
        stabilator 13.76 - 16.46, 6.60 m span

    It is unarmed. Everything it carries transmits."""
    L, SPAN = 16.92, 16.15
    N = L / 2.0
    # Blunt radome nose and a body that stays full-width back to the wing —
    # the A-6 forward fuselage is a wide box, not the fighter's needle.
    p = fuselage(L, 1.22, 0.0, 0.0,
                 stations=((0.00, 0.42), (0.05, 0.74), (0.17, 0.96),
                           (0.46, 1.00), (0.74, 0.90), (0.89, 0.62),
                           (1.00, 0.32)))
    # OWNED: high-aspect attack wing at the real A-6 taper. Area
    # 16.15*(4.66+1.44)/2 = 49.3 m^2 against the published 49.1, AR 5.29
    # against 5.31. sead()'s wing is 10.65 x (5.05+1.55)/2 = 36.2 m^2 at AR
    # 3.13 — two thirds the area at half again the slenderness, and swept 49
    # deg against this wing's 25. sweep 3.63 m over a 7.775 m semi-span
    # outboard of the root = 25.0 deg.
    p += wings(N - 7.16, SPAN, 4.66, 1.44, 3.63, 0.34, 0.0, "w")
    p += wings(N - 13.76, 6.6, 2.7, 1.4, 1.4, 0.28, 0.12, "h")
    # OWNED: ONE tall centre fin. sead() has one too but it is a fighter fin on
    # a 10.65 m span; this one carries the canoe.
    p.append(fin(N - 12.31, 2.48, 4.35, 1.55, 3.05, 0.30, z=0.60))
    use("deck")
    # OWNED: the ECM canoe on the fin tip — the ALQ-41/51/55 receiver fairing
    # that is the EA-6A's identifying feature. 2.9 m long on a 16.92 m
    # aircraft = 17% of length, at the highest point of the airframe with
    # nothing above it to occlude it from any camera angle.
    p.append(dome((0, N - 15.35, 3.14), 0.42, 1.42, 0.40, v=16))
    p.append(cyl((0, N - 14.15, 3.14), 0.28, 0.90, rot=(R(90), 0, 0), v=12,
                 taper=0.35))
    # Five transmitter pods, wing and centreline. These hang under the wing so
    # by the contract above they carry NO identification — they are here for
    # the close camera only.
    for s in (-1, 1):
        for k in range(2):
            p.append(cyl((s * (2.35 + k * 2.60), -0.35 - k * 0.55, -0.98),
                         0.38, 4.30, rot=(R(90), 0, 0), v=10))
    p.append(cyl((0, 0.55, -1.05), 0.38, 4.30, rot=(R(90), 0, 0), v=10))
    # Side-mounted intakes: the A-6 is widest at the wing root, not at the nose.
    for s in (-1, 1):
        p.append(cyl((s * 1.42, N - 7.00, -0.10), 0.62, 3.20, rot=(R(90), 0, 0),
                     v=12))
    use("body")
    # OWNED: the 3.3 m SIDE-BY-SIDE two-seat canopy — pilot left, ECMO right,
    # with the right seat set low and aft. sead() has a 4.6 m tandem canopy
    # 0.6 m wide. Seen from directly overhead this is a 2.3 m WIDE flat glass
    # panel on a 2.44 m fuselage: the aircraft is nearly all windscreen across
    # the shoulders, which is the read the tandem fighters cannot produce.
    p.append(cube((0, N - 4.85, 0.86), (2.30, 3.30, 0.86)))
    p.append(dome((0, N - 3.15, 0.86), 1.14, 0.95, 0.42, v=14))     # front cap
    use("glass")
    p.append(cube((0, N - 4.78, 0.99), (2.08, 3.00, 0.66)))
    p.append(dome((0, N - 3.18, 0.94), 1.00, 0.92, 0.34, v=14))
    use("gun")
    # The fixed refuelling probe, on the centreline ahead of the windscreen.
    # Tip stops 0.9 m short of the radome, so overall length stays 16.92 m.
    p.append(cyl((0, N - 2.20, 1.44), 0.09, 1.75, rot=(R(83), 0, 0), v=8))
    p.append(cyl((0, N - 1.50, 1.53), 0.14, 0.40, rot=(R(83), 0, 0), v=10,
                 taper=0.40))
    use("body")
    p.append(dome((0, N - 1.00, 0.02), 0.94, 1.05, 0.90, v=16))     # radome
    return p, dict(top=1.30, hull_l=L, hull_w=SPAN, turret_top=3.9,
                   gun_z=0.4, gun_y=L * 0.26)


def tanker():
    """Boeing KC-135R Stratotanker: 39.88 m span, 41.53 m long, wing area
    226.0 m^2 (AR 7.04), leading edge swept 35 deg.

    Pillar 4 in the air. Turns a 30-minute CAP into a three-hour one, and is
    the second most valuable target in the sky.

    Same 707 family as aewc(), so the airframe is deliberately NOT restyled
    away from it. What separates them is what each one is FOR, and both of
    those things stick out into the planform:

      the BOOM. 8.5 m of flying boom trailing aft and down from the tail,
        with its ruddevator V and the boom operator's ventral fairing. It
        pushes the plan length to ~46 m against a 41.5 m airframe — a spike
        aft of the tailplane that the E-3 does not have.
      the WING PODS. Two MPRS hose-and-drogue pods on the wingtips, so the
        span outline ends in a pair of hard cylinders.
      the ENGINES. CFM56-2B, 2.15 m nacelles. The E-3B kept the slim 1.56 m
        TF33s, so at the same wing station this aircraft's pods are half
        again as wide.
    """
    L, SPAN = 41.53, 39.88
    p = fuselage(L, 1.88, 0.52, 0.50)
    # semispan 19.94, panel root at x=0.30, so sweep 13.75 => LE 35.0 deg.
    p += wings(6.6, SPAN, 8.8, 2.9, 13.75, 0.56, -0.58, "w")
    p += wings(-14.6, 12.90, 4.5, 1.8, 4.1, 0.42, 0.0, "h")
    p.append(fin(-12.6, 8.0, 8.2, 2.8, 5.6, 0.42, 1.0))
    use("gun")
    for s in (-1, 1):                              # four fat CFM56 nacelles
        for x, y in ((5.6, 1.4), (10.1, -1.5)):
            p.append(cyl((s * x, y, -1.42), 1.07, 4.90,
                         rot=(R(90), 0, 0), v=14))
            p.append(cube((s * x, y + 1.80, -0.95), (0.34, 2.10, 0.90)))
    use("deck")
    # THE BOOM, stowed: down and aft from under the tail, with its ruddevators.
    p.append(cyl((0, -L * 0.505, -1.35), 0.34, 8.60, rot=(R(74), 0, 0), v=12))
    p.append(cyl((0, -L * 0.585, -2.65), 0.20, 3.20, rot=(R(80), 0, 0), v=10))
    p += wings(-L * 0.545, 4.60, 1.55, 0.85, 0.60, 0.20, -2.20, "bv")
    p.append(cube((0, -L * 0.40, -1.85), (1.30, 4.20, 0.80)))    # boomer pod
    for s in (-1, 1):                              # MPRS wingtip drogue pods
        p.append(cyl((s * (SPAN * 0.5 - 0.42), -8.40, -0.62), 0.42, 3.60,
                     rot=(R(90), 0, 0), v=12))
    use("body")
    use("glass")
    p.append(dome((0, L * 0.40, 0.66), 0.70, 1.60, 0.42, v=16))
    use("body")
    return p, dict(top=2.0, hull_l=L, hull_w=SPAN, turret_top=4.2,
                   gun_z=0.4, gun_y=L * 0.30)


def isr():
    """Lockheed U-2S Dragon Lady: 31.39 m span, 19.20 m long, wing area
    92.9 m^2 (AR 10.6), leading edge swept ~6 deg. Contributes tracks,
    carries nothing.

    WAS WRONG. This was modelled 34.0 x 30.0 m with AR 13.9 and four-engine
    airliner proportions — not any aircraft that has ever flown, and sitting
    between the U-2, the RC-135 and the Global Hawk without being any of
    them. It is now a U-2, for two reasons: it is the epoch-1 high-altitude
    reconnaissance aircraft the role is written around, and the other two
    candidates are already taken — uav_e5_us_recon IS an RQ-4 Global Hawk,
    and an RC-135 is a 707, which is aewc() and tanker().

    From above it is a glider: one enormous straight wing, span 1.63x the
    length, on a body barely wider than a fighter's, with a single fin and
    ONE engine buried in the fuselage. Every other high-aspect aircraft in
    the roster is either unmanned (V-tail, AR 17-25) or multi-engined.
    """
    L, SPAN = 19.20, 31.39
    p = fuselage(L, 0.76, 0.50, 0.45,
                 stations=((0.00, 0.06), (0.08, 0.42), (0.20, 0.72),
                           (0.34, 0.94), (0.52, 1.00), (0.74, 0.92),
                           (0.90, 0.68), (1.00, 0.30)))
    # semispan 15.70, panel root at x=0.30, so sweep 1.62 => LE 6.0 deg.
    # area 31.39 * (4.30 + 1.62) / 2 = 92.9 m^2, the real wing area.
    p += wings(3.30, SPAN, 4.30, 1.62, 1.62, 0.34, 0.28, "w")
    p += wings(-6.90, 6.10, 2.10, 1.05, 0.55, 0.26, 0.20, "h")
    p.append(fin(-5.28, 3.30, 4.30, 1.70, 2.60, 0.30, 0.55))
    use("deck")
    # The Q-bay hump and the dorsal satcom fairing: on a body this slim they
    # are the only things that widen the plan between wing and canopy.
    p.append(dome((0, 4.10, 0.78), 0.72, 2.00, 0.52, v=16))
    p.append(dome((0, -1.30, 0.86), 0.58, 1.60, 0.48, v=16))
    for s in (-1, 1):                              # root intakes, buried F118
        p.append(cube((s * 1.02, 2.10, 0.10), (0.62, 2.60, 0.86)))
    use("gun")
    p.append(cyl((0, -L * 0.46, 0.10), 0.44, 0.90, rot=(R(90), 0, 0), v=14,
                 taper=0.72))                                     # tailpipe
    p.append(cyl((0, L * 0.42, 0.02), 0.40, 1.60, rot=(R(90), 0, 0), v=14,
                 taper=0.30))                                     # sensor nose
    use("body")
    for s in (-1, 1):                              # wing super pods, slung low
        p.append(cyl((s * 4.20, 3.10, -0.98), 0.54, 6.00,
                     rot=(R(90), 0, 0), v=12))
    use("glass")
    p.append(dome((0, 6.40, 0.72), 0.56, 1.30, 0.40, v=16))
    use("body")
    return p, dict(top=1.0, hull_l=L, hull_w=SPAN, turret_top=1.9,
                   gun_z=0.3, gun_y=L * 0.30)


def maritime_patrol():
    """Lockheed P-3C Orion: 30.37 m span, 35.57 m long over the MAD boom,
    wing area 120.8 m^2 (AR 7.64), leading edge swept ~8 deg, four Allison
    T56 turboprops turning 4.11 m four-blade propellers. Pillar 6 from the
    air: sonobuoys, MAD boom, torpedoes.

    WAS THE WORST PAIR IN THE ROSTER (0.9312 against the tanker) and the
    cause was a dimension error, not a styling one: it was built 37.60 x
    39.50 m — 24% too much span and 11% too much length — which put a
    four-engine swept-wing aircraft inside 6% of the KC-135's envelope. At
    its true P-3 size it is 24% shorter in span and 14% shorter than the
    tanker, and the shape changes with it:

      the WING is a straight Electra wing, LE swept 8 deg against the 707's
        35 deg. From overhead that is a bar across the fuselage, not a V.
      the PROPELLERS. Four 4.11 m discs, and a parked prop shows its
        near-horizontal blade pair sticking a full 2 m out each side of the
        nacelle. Eight blade shapes strung across the wing is a signature no
        jet in the roster can produce, and it survives to LOD2 because the
        blades are on top of the wing, not slung under it.
      the MAD BOOM. 3.5 m of tapering stinger aft of the tail cone, on the
        centreline, where the tanker's boom hangs low and carries a
        ruddevator V.
    """
    L, SPAN = 35.57, 30.37
    NOSE = 16.03                                   # 32.06 m of loft, then MAD
    p = fuselage(32.06, 1.72, 0.52, 0.48,
                 stations=((0.00, 0.16), (0.05, 0.58), (0.13, 0.88),
                           (0.24, 1.00), (0.63, 1.00), (0.80, 0.84),
                           (0.92, 0.60), (1.00, 0.32)))
    # semispan 15.185, panel root at x=0.30, so sweep 2.09 => LE 8.0 deg.
    # area 30.37 * (5.60 + 2.36) / 2 = 120.9 m^2, the real wing area.
    p += wings(4.20, SPAN, 5.60, 2.36, 2.09, 0.52, -1.02, "w")
    p += wings(-12.30, 12.10, 3.90, 1.70, 1.05, 0.42, 0.30, "h")
    p.append(fin(-11.10, 6.30, 6.60, 2.40, 3.60, 0.42, 1.35))
    use("gun")
    # Four T56 nacelles at +/-5.0 and +/-9.5 m, each standing 2.6 m proud of
    # the leading edge, with its propeller disc ahead of that.
    for s in (-1, 1):
        for x, le in ((5.00, 3.54), (9.50, 2.91)):
            p.append(cyl((s * x, le - 1.10, -0.62), 0.72, 6.40,
                         rot=(R(90), 0, 0), v=14))
            p += _prop(s * x, le + 2.35, -0.62, 4.11, blades=4, phase=9.0,
                       chord=0.36)
    use("deck")
    # MAD stinger: 3.54 m aft of the tail cone, on the centreline.
    p.append(cyl((0, -(NOSE + 1.72), 0.28), 0.30, 3.54,
                 rot=(R(90), 0, 0), v=12, taper=0.22))
    p.append(cube((0, 7.60, -2.02), (2.10, 3.95, 0.52)))         # weapons bay
    p.append(dome((0, NOSE - 2.30, -1.24), 1.06, 1.80, 0.62, v=16))  # APS-115
    for s in (-1, 1):                              # ESM / sonobuoy fairings
        p.append(cube((s * 1.72, -3.40, -0.20), (0.34, 3.20, 0.70)))
    use("body")
    use("glass")
    p.append(dome((0, NOSE - 3.20, 0.62), 0.66, 1.70, 0.42, v=16))
    use("body")
    return p, dict(top=1.9, hull_l=L, hull_w=SPAN, turret_top=3.6,
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
    """Northrop Grumman RQ-4A Global Hawk Block 10: 35.42 m span, 13.54 m
    long, wing area 50.2 m^2 (AR 25) — the most extreme aspect ratio in the
    roster, and unmistakable from above.

    It shares a family outline with armed_uav() (long straight wing, V-tail)
    and the two used to be separated only by proportion, which is fragile.
    Three OUTLINE elements are now exclusive to this one:

      the WHALE NOSE. A 2.3 m satcom radome on a 1.4 m body — the plan is
        wider at the nose than anywhere aft of it until the wing.
      the DORSAL ENGINE. The AE3007 sits ON TOP of the rear fuselage, so
        from directly overhead there is a 4.0 m dark nacelle lying along the
        spine. The Reaper's engine is buried and drives a tail propeller.
      an UPRIGHT V-TAIL over a plain tailcone, with nothing behind it.
    """
    L, SPAN = 13.54, 35.42
    p = fuselage(L, 0.70, 0.55, 0.40,
                 stations=((0.00, 0.55), (0.07, 0.96), (0.18, 1.00),
                           (0.34, 0.96), (0.60, 0.86), (0.82, 0.66),
                           (1.00, 0.30)))
    # semispan 17.71, panel root at x=0.30, so sweep 1.83 => LE 6.0 deg.
    # area 35.42 * (2.06 + 0.78) / 2 = 50.3 m^2, the real wing area.
    p += wings(1.90, SPAN, 2.06, 0.78, 1.83, 0.22, 0.34, "w")
    for s in (-1, 1):                              # V-tail, upright
        p.append(fin(-4.35, 2.30, 2.40, 1.05, 1.45, 0.20, cant=36 * s,
                     offset_x=s * 0.42))
    use("deck")
    # The whale nose: wider than the fuselage, and it IS the front of the plan.
    p.append(dome((0, 4.52, 0.30), 1.16, 2.22, 0.92, v=20))
    # Dorsal engine nacelle and its inlet lip, on the spine.
    p.append(cyl((0, -3.20, 1.02), 0.62, 4.00, rot=(R(90), 0, 0), v=16))
    p.append(cyl((0, -1.05, 1.02), 0.66, 0.55, rot=(R(90), 0, 0), v=16,
                 taper=0.92))
    use("body")
    return p, dict(top=0.7, hull_l=L, hull_w=SPAN, turret_top=1.7,
                   gun_z=0.2, gun_y=L * 0.30)


def armed_uav():
    """General Atomics MQ-9A Reaper: 20.12 m span, 11.00 m long, wing area
    23.1 m^2 (AR 17.5).

    The counterpart to recon_uav(), and the elements that keep it out of the
    Global Hawk's outline are all at the tail:

      a PUSHER PROPELLER. 2.03 m three-blade, at the very back, behind
        everything else. From overhead it lays a hard bar across the extreme
        tail — the only aircraft in the roster with a propeller aft of its
        tail surfaces.
      a Y-TAIL: the V hangs DOWNWARD and there is a vertical fin above it.
        The Global Hawk's V points up and carries nothing above.
      a shallower nose bulge on a proportionally longer, thinner boom.
    """
    L, SPAN = 11.00, 20.12
    p = fuselage(L, 0.56, 0.55, 0.42,
                 stations=((0.00, 0.30), (0.07, 0.78), (0.18, 1.00),
                           (0.40, 0.96), (0.66, 0.72), (0.86, 0.52),
                           (1.00, 0.44)))
    # semispan 10.06, panel root at x=0.30, so sweep 1.06 => LE 6.2 deg.
    # area 20.12 * (1.62 + 0.68) / 2 = 23.1 m^2.
    p += wings(1.45, SPAN, 1.62, 0.68, 1.06, 0.20, 0.22, "w")
    for s in (-1, 1):                              # the V, hanging DOWN
        p.append(fin(-3.70, -1.95, 1.85, 0.85, 1.10, 0.18, cant=42 * s,
                     offset_x=s * 0.36))
    p.append(fin(-3.70, 1.55, 1.70, 0.80, 1.00, 0.18, z=0.16))   # dorsal fin
    use("gun")
    # Pusher propeller, aft of the tail surfaces. 2.03 m, three blades.
    p += _prop(0.0, -L * 0.482, 0.12, 2.03, blades=3, phase=14.0, chord=0.20,
               spinner=(0.16, 0.40))
    use("deck")
    p.append(dome((0, 3.55, 0.28), 0.52, 1.20, 0.40, v=14))      # satcom bulge
    for s in (-1, 1):                              # Hellfire rails
        p.append(cyl((s * 2.60, 0.60, -0.34), 0.13, 1.70,
                     rot=(R(90), 0, 0), v=8))
        p.append(cyl((s * 4.10, 0.40, -0.30), 0.11, 1.50,
                     rot=(R(90), 0, 0), v=8))
    use("body")
    return p, dict(top=0.6, hull_l=L, hull_w=SPAN, turret_top=1.5,
                   gun_z=0.2, gun_y=L * 0.30)


def loitering_munition():
    """IAI Harop: 3.00 m span, 2.50 m long. Epoch 7. Cheap and expendable —
    spend them to make the enemy radiate (docs/05).

    It used to be a small high-aspect straight-winged aircraft with a V-tail,
    i.e. a shrunken Reaper, which is exactly what a loitering munition is
    not. It is now built as what it is: a MISSILE that happens to fly for six
    hours — a needle body with a short 24 deg swept wing of aspect ratio 4.6,
    canard foreplanes right behind the seeker, twin tail fins and a pusher
    prop. At 3 m it is 1/7 the span of the next smallest air unit, so size
    already separates it; this makes it read as a weapon rather than as an
    aircraft when the player looks closely.
    """
    L, SPAN = 2.50, 3.00
    p = fuselage(L, 0.19, 0.6, 0.5,
                 stations=((0.00, 0.34), (0.10, 0.86), (0.22, 1.00),
                           (0.62, 1.00), (0.84, 0.86), (1.00, 0.56)))
    # semispan 1.50, panel root at x=0.30, so sweep 0.54 => LE 24.2 deg.
    # area 3.00 * (0.95 + 0.35) / 2 = 1.95 m^2, AR 4.6.
    p += wings(0.30, SPAN, 0.95, 0.35, 0.54, 0.07, 0.0, "w")
    p += wings(0.98, 0.92, 0.34, 0.18, 0.16, 0.05, 0.05, "canard")
    for s in (-1, 1):                              # twin near-upright fins
        p.append(fin(-L * 0.36, 0.42, 0.40, 0.20, 0.20, 0.05, cant=14 * s,
                     offset_x=s * 0.16))
    use("gun")
    p.append(cyl((0, L * 0.43, 0), 0.15, 0.30, rot=(R(90), 0, 0), v=12,
                 taper=0.34))                                     # seeker
    p += _prop(0.0, -L * 0.46, 0.0, 0.70, blades=2, phase=20.0, chord=0.09,
               spinner=(0.07, 0.20))
    use("body")
    return p, dict(top=0.2, hull_l=L, hull_w=SPAN, turret_top=0.4,
                   gun_z=0.05, gun_y=L * 0.30)


AIR = [
    ("air_e1_us_interceptor",   interceptor,        "air_grey"),
    ("air_e4_us_superiority",   air_superiority,    "air_grey"),
    ("air_e4_us_multirole",     multirole,          "air_grey"),
    ("air_e4_us_strike",        strike,             "air_camo"),
    ("air_e1_us_cas",           cas,                "air_camo"),
    ("air_e1_us_bomber",        bomber,             "air_camo"),
    ("air_e4_us_stealthbomber", stealth_bomber,     "air_dark"),
    ("air_e2_us_sead",          sead,               "air_grey"),
    ("air_e4_us_stealth",       stealth_strike,     "air_black"),
    ("aew_e3_us_aewc",          aewc,               "air_white"),
    ("aew_e3_uk_aewhelo",       aew_helo,           "air_grey"),
    ("ewa_e2_us_electronic",    electronic_attack,  "air_grey"),
    ("tkr_e2_us_tanker",        tanker,             "air_white"),
    ("isr_e1_us_recon",         isr,                "air_dark"),
    ("mpa_e1_us_maritime",      maritime_patrol,    "air_white"),
    ("hel_e3_us_attack",        attack_helo,        "helo_drab"),
    ("hel_e2_us_transport",     transport_helo,     "helo_drab"),
    ("hel_e2_us_asw",           asw_helo,           "air_grey"),
    ("uav_e5_us_recon",         recon_uav,          "air_white"),
    ("uav_e6_us_armed",         armed_uav,          "air_grey"),
    ("uav_e7_us_loiter",        loitering_munition, "air_grey"),
]



# ── the texture pass (2026-08): per-unit composed-texture requests ─────────
# Roster DATA, not geometry: every number below was measured off the built
# meshes (chord intersections at spanwise stations), so a decal sits ON the
# wing it names. Conventions: nose is +Y, port is -X. US star goes on the
# PORT wing top and the STARBOARD wing bottom (the real placement — from the
# RTS camera you see exactly one wing star, like an overhead photo).
# Colour code: e1/e2 grey-and-white aircraft carry full-colour (insignia
# blue) stars, e4 low-vis greys carry grey stencils, camouflage carries
# black stencils. Radomes are their own paint via `tints`.
_LOWVIS = (0.25, 0.27, 0.31)
_BLUE   = (0.10, 0.16, 0.38)
_BLACK  = (0.10, 0.10, 0.11)
_RADOME_GREY = (0.20, 0.21, 0.24)
_RADOME_DARK = (0.12, 0.12, 0.13)


def _wingstars(xw, y, z, size, color, alpha=0.9, dz=0.05):
    """Port-top + starboard-bottom pair at the measured wing point."""
    return [dict(kind="star_us", center=(-xw, y, z + dz), normal=(0, 0, 1),
                 size=size, up=(0, 1, 0), alpha=alpha, color=color),
            dict(kind="star_us", center=(xw, y, z - dz), normal=(0, 0, -1),
                 size=size, alpha=alpha, color=color)]


def _sidestars(xs, y, z, size, color, alpha=0.9):
    return [dict(kind="star_us", center=(xs, y, z), normal=(1, 0, 0),
                 size=size, alpha=alpha, color=color),
            dict(kind="star_us", center=(-xs, y, z), normal=(-1, 0, 0),
                 size=size, alpha=alpha, color=color)]


H.texture_features(          # F-106: single tail-pipe, black radome era
    "air_e1_us_interceptor", size_class="aircraft", ao_ground="under",
    groups=("body", "deck"), group_base={"deck": "camo"},
    panels=dict(spacing=1.3, strength=0.5, jitter=0.07, seams=0.45),
    weathering=dict(
        exhaust=[dict(origin=(0.0, -6.2, 0.8), direction=(0, -1, 0.03),
                      length=3.0, width=0.5, strength=0.45)],
        edge_wear=dict(strength=0.35)),
    tints=[dict(center=(0.0, 10.6, 0.0), radius=0.85, rgb=_RADOME_GREY,
                strength=0.8)],
    insignia=_wingstars(2.9, -5.45, 0.15, 1.15, _BLUE))

H.texture_features(          # F-15: twin engines, low-vis everything
    "air_e4_us_superiority", size_class="aircraft", ao_ground="under",
    groups=("body", "deck"), group_base={"deck": "camo"},
    panels=dict(spacing=1.5, strength=0.5, jitter=0.07, seams=0.45),
    weathering=dict(
        exhaust=[dict(origin=(1.1, -6.8, 0.65), direction=(0, -1, 0.05),
                      length=2.8, width=0.55, strength=0.55),
                 dict(origin=(-1.1, -6.8, 0.65), direction=(0, -1, 0.05),
                      length=2.8, width=0.55, strength=0.55)],
        edge_wear=dict(strength=0.35)),
    tints=[dict(center=(0.0, 9.7, 0.0), radius=0.9, rgb=_RADOME_GREY,
                strength=0.8)],
    insignia=(_wingstars(3.3, -3.8, 0.17, 1.3, _LOWVIS)
              + _sidestars(1.1, 3.1, 0.0, 0.9, _LOWVIS)))

H.texture_features(          # F-16 — the entry proven by the API proof build
    "air_e4_us_multirole", size_class="aircraft", ao_ground="under",
    groups=("body", "deck"), group_base={"deck": "camo"},
    panels=dict(spacing=1.6, strength=0.5, jitter=0.07, seams=0.45),
    weathering=dict(
        exhaust=[dict(origin=(0.0, -5.0, 0.2), direction=(0, -1, 0.05),
                      length=2.8, width=0.55, strength=0.5)],
        edge_wear=dict(strength=0.4)),
    tints=[dict(center=(0.0, 7.5, 0.0), radius=0.7, rgb=_RADOME_GREY,
                strength=0.8)],
    insignia=[
        dict(kind="star_us", center=(-2.7, -1.7, 0.19), normal=(0, 0, 1),
             size=1.25, up=(0, 1, 0), alpha=0.9, color=_LOWVIS),
        dict(kind="star_us", center=(2.7, -1.7, 0.09), normal=(0, 0, -1),
             size=1.25, alpha=0.9, color=_LOWVIS),
        dict(kind="star_us", center=(0.95, -2.0, 0.10), normal=(1, 0, 0),
             size=0.75, alpha=0.9, color=_LOWVIS),
        dict(kind="star_us", center=(-0.95, -2.0, 0.10), normal=(-1, 0, 0),
             size=0.75, alpha=0.9, color=_LOWVIS),
        dict(kind="pennant", center=(0.0, -5.6, 2.3), normal=(1, 0, 0),
             size=1.1, alpha=0.85, text="16", color=_LOWVIS)])

H.texture_features(          # F-111: swing wing measured at mid-sweep
    "air_e4_us_strike", size_class="aircraft", ao_ground="under",
    groups=("body", "deck"), group_base={"deck": "camo"},
    camo_scale=3.2,
    panels=dict(spacing=1.6, strength=0.5, jitter=0.07, seams=0.45),
    weathering=dict(
        exhaust=[dict(origin=(0.55, -8.6, 0.95), direction=(0, -1, 0.05),
                      length=3.0, width=0.55, strength=0.5),
                 dict(origin=(-0.55, -8.6, 0.95), direction=(0, -1, 0.05),
                      length=3.0, width=0.55, strength=0.5)],
        edge_wear=dict(strength=0.35)),
    tints=[dict(center=(0.0, 11.2, 0.0), radius=0.9, rgb=(0.15, 0.16, 0.17),
                strength=0.8)],
    insignia=_wingstars(4.8, -1.0, 0.17, 1.25, _BLACK))

H.texture_features(          # A-10: soot from the podded TF34s
    "air_e1_us_cas", size_class="aircraft", ao_ground="under",
    groups=("body", "deck", "gun"),
    group_base={"deck": "camo", "gun": "camo"},
    panels=dict(spacing=1.4, strength=0.5, jitter=0.07, seams=0.45),
    weathering=dict(
        exhaust=[dict(origin=(1.62, -5.3, 1.0), direction=(0, -1, 0.06),
                      length=3.0, width=0.55, strength=0.5),
                 dict(origin=(-1.62, -5.3, 1.0), direction=(0, -1, 0.06),
                      length=3.0, width=0.55, strength=0.5)],
        edge_wear=dict(strength=0.35)),
    insignia=_wingstars(5.7, -0.2, 0.02, 1.35, _BLACK))

H.texture_features(          # B-52: SEA camouflage, black radome
    "air_e1_us_bomber", size_class="aircraft", ao_ground="under",
    groups=("body", "deck"), group_base={"deck": "camo"},
    camo_scale=6.0,
    # spacing up / strength down (2026-08-27): at 3.0 m the grid crossed the
    # swept wing as a fishnet of diamonds; fewer, fainter lines read as plates
    panels=dict(spacing=3.6, strength=0.30, jitter=0.06, seams=0.45),
    weathering=dict(edge_wear=dict(strength=0.3)),
    tints=[dict(center=(0.0, 24.3, 0.0), radius=1.3, rgb=_RADOME_DARK,
                strength=0.85)],
    insignia=_wingstars(14.1, 1.5, -0.24, 2.4, _BLACK, dz=0.08))

H.texture_features(          # B-2: exhaust troughs stain the upper deck
    "air_e4_us_stealthbomber", size_class="aircraft", ao_ground="under", groups=("body",),
    # camo tile up 5 -> 9 m (2026-08-27): at 5 m the low-contrast air_dark
    # tile repeated ~10x across the 52 m wing and the periodicity read as a
    # quilt; panel grid softened for the same reason — the strong regular
    # grid was lifting the whole airframe half a value lighter than air_dark
    camo_scale=9.0,
    panels=dict(spacing=3.8, strength=0.32, jitter=0.045, seams=0.5),
    weathering=dict(
        exhaust=[dict(origin=(5.2, -7.4, 1.15), direction=(0, -1, 0),
                      length=3.5, width=1.0, strength=0.4),
                 dict(origin=(-5.2, -7.4, 1.15), direction=(0, -1, 0),
                      length=3.5, width=1.0, strength=0.4)],
        edge_wear=dict(strength=0.3)),
    tints=[dict(center=(0.0, 10.5, 0.35), radius=1.5, rgb=(0.14, 0.15, 0.17),
                strength=0.5)],
    insignia=_wingstars(13.1, -2.2, 0.5, 1.7, (0.36, 0.38, 0.42), alpha=0.8))

H.texture_features(          # F-105G: Vietnam-era full-colour stars
    "air_e2_us_sead", size_class="aircraft", ao_ground="under",
    groups=("body", "deck"), group_base={"deck": "camo"},
    panels=dict(spacing=1.4, strength=0.5, jitter=0.07, seams=0.45),
    weathering=dict(
        exhaust=[dict(origin=(0.0, -7.2, 0.95), direction=(0, -1, 0.04),
                      length=3.0, width=0.5, strength=0.5)],
        edge_wear=dict(strength=0.35)),
    tints=[dict(center=(0.0, 10.6, 0.0), radius=0.8, rgb=_RADOME_GREY,
                strength=0.8)],
    insignia=(_wingstars(2.7, -3.55, 0.15, 1.1, _BLUE)
              + _sidestars(1.15, 3.0, 0.03, 0.85, _BLUE)))

H.texture_features(          # F-117: matt black — panels and soot only,
    "air_e4_us_stealth",     # tone IS the identification channel
    size_class="aircraft", ao_ground="under",
    groups=("body", "deck"), group_base={"deck": "camo"},
    panels=dict(spacing=1.3, strength=0.35, jitter=0.05, seams=0.4),
    weathering=dict(
        exhaust=[dict(origin=(1.5, -4.9, 0.98), direction=(0, -1, 0),
                      length=2.5, width=0.8, strength=0.3),
                 dict(origin=(-1.5, -4.9, 0.98), direction=(0, -1, 0),
                      length=2.5, width=0.8, strength=0.3)],
        edge_wear=dict(strength=0.25)))

H.texture_features(          # E-3: full-colour markings on white
    "aew_e3_us_aewc", size_class="aircraft", ao_ground="under", groups=("body",),
    camo_scale=4.5,
    panels=dict(spacing=2.4, strength=0.4, jitter=0.06, seams=0.45),
    weathering=dict(edge_wear=dict(strength=0.3)),
    tints=[dict(center=(0.0, 23.3, 0.0), radius=1.0, rgb=_RADOME_DARK,
                strength=0.85)],
    insignia=(_wingstars(11.1, -3.2, -0.32, 2.0, _BLUE, dz=0.06)
              + _sidestars(1.35, 7.3, 0.0, 1.4, _BLUE)))

H.texture_features(          # Sea King AEW: RAF roundels, side and top
    "aew_e3_uk_aewhelo", size_class="aircraft", ao_ground="under",
    groups=("body", "gun"), group_base={"gun": "camo"},
    panels=dict(spacing=1.1, strength=0.45, jitter=0.07, seams=0.45),
    weathering=dict(
        exhaust=[dict(origin=(0.8, 1.6, 2.5), direction=(0, -1, 0),
                      length=2.2, width=0.4, strength=0.4),
                 dict(origin=(-0.8, 1.6, 2.5), direction=(0, -1, 0),
                      length=2.2, width=0.4, strength=0.4)],
        edge_wear=dict(strength=0.3)),
    tints=[dict(center=(0.0, 8.2, 1.35), radius=0.5, rgb=(0.15, 0.16, 0.17),
                strength=0.6)],
    insignia=[
        dict(kind="roundel_uk", center=(1.45, 2.0, 1.6), normal=(1, 0, 0),
             size=0.95, alpha=0.9),
        dict(kind="roundel_uk", center=(-1.45, 2.0, 1.6), normal=(-1, 0, 0),
             size=0.95, alpha=0.9),
        dict(kind="roundel_uk", center=(0.0, 0.6, 2.6), normal=(0, 0, 1),
             size=1.15, up=(0, 1, 0), alpha=0.9)])

H.texture_features(          # EB-66: wide wing, full-colour era
    "ewa_e2_us_electronic", size_class="aircraft", ao_ground="under", groups=("body",),
    panels=dict(spacing=1.5, strength=0.5, jitter=0.07, seams=0.45),
    weathering=dict(
        exhaust=[dict(origin=(0.7, -5.6, 0.75), direction=(0, -1, 0.04),
                      length=2.6, width=0.5, strength=0.45),
                 dict(origin=(-0.7, -5.6, 0.75), direction=(0, -1, 0.04),
                      length=2.6, width=0.5, strength=0.45)],
        edge_wear=dict(strength=0.35)),
    tints=[dict(center=(0.0, 8.5, 0.05), radius=0.8, rgb=_RADOME_GREY,
                strength=0.8)],
    insignia=(_wingstars(4.0, -2.0, 0.17, 1.15, _BLUE)
              + _sidestars(1.25, 2.5, 0.1, 0.85, _BLUE)))

H.texture_features(          # KC-135: white top, blue markings
    "tkr_e2_us_tanker", size_class="aircraft", ao_ground="under", groups=("body",),
    camo_scale=4.5,
    panels=dict(spacing=2.4, strength=0.4, jitter=0.06, seams=0.45),
    weathering=dict(edge_wear=dict(strength=0.3)),
    tints=[dict(center=(0.0, 20.8, 0.0), radius=0.9, rgb=_RADOME_DARK,
                strength=0.85)],
    insignia=(_wingstars(10.0, -3.1, -0.30, 1.9, _BLUE, dz=0.06)
              + _sidestars(1.3, 6.6, 0.0, 1.35, _BLUE)))

H.texture_features(          # U-2: near-black, whisper-quiet markings
    "isr_e1_us_recon", size_class="aircraft", ao_ground="under",
    groups=("body", "deck"), group_base={"deck": "camo"},
    panels=dict(spacing=1.6, strength=0.4, jitter=0.05, seams=0.4),
    weathering=dict(
        exhaust=[dict(origin=(0.0, -6.8, 0.5), direction=(0, -1, 0.03),
                      length=2.5, width=0.45, strength=0.4)],
        edge_wear=dict(strength=0.3)),
    insignia=_wingstars(7.9, 1.0, 0.45, 1.0, (0.42, 0.44, 0.48), alpha=0.85))

H.texture_features(          # P-3: white over grey, black radome
    "mpa_e1_us_maritime", size_class="aircraft", ao_ground="under",
    groups=("body", "deck"), group_base={"deck": "camo"},
    camo_scale=4.0,
    panels=dict(spacing=2.2, strength=0.4, jitter=0.06, seams=0.45),
    weathering=dict(edge_wear=dict(strength=0.3)),
    tints=[dict(center=(0.0, 16.0, 0.0), radius=0.9, rgb=_RADOME_DARK,
                strength=0.85)],
    insignia=(_wingstars(7.6, 1.2, -0.76, 1.5, _BLUE, dz=0.06)
              + _sidestars(1.55, 2.45, 0.0, 1.25, _BLUE)))

H.texture_features(          # AH-64: olive drab, black stencils on the boom
    "hel_e3_us_attack", size_class="aircraft", ao_ground="under",
    groups=("body", "deck", "gun"),
    group_base={"deck": "camo", "gun": "camo"},
    panels=dict(spacing=0.9, strength=0.45, jitter=0.07, seams=0.45),
    weathering=dict(
        dust=dict(height=0.9, strength=0.3, tint=(0.40, 0.36, 0.28)),
        exhaust=[dict(origin=(0.9, -0.6, 2.1), direction=(0, -1, -0.02),
                      length=2.2, width=0.4, strength=0.45),
                 dict(origin=(-0.9, -0.6, 2.1), direction=(0, -1, -0.02),
                      length=2.2, width=0.4, strength=0.45)],
        edge_wear=dict(strength=0.3)),
    tints=[dict(center=(0.0, 7.5, 1.55), radius=0.5, rgb=_RADOME_DARK,
                strength=0.7)],
    insignia=_sidestars(0.6, -3.8, 1.6, 0.7, _BLACK))

H.texture_features(          # UH-60: olive drab, dustier
    "hel_e2_us_transport", size_class="aircraft", ao_ground="under",
    groups=("body", "deck", "gun"),
    group_base={"deck": "camo", "gun": "camo"},
    panels=dict(spacing=1.0, strength=0.45, jitter=0.07, seams=0.45),
    weathering=dict(
        dust=dict(height=1.0, strength=0.3, tint=(0.40, 0.36, 0.28)),
        exhaust=[dict(origin=(0.8, 0.4, 2.6), direction=(0, -1, 0),
                      length=2.4, width=0.45, strength=0.4),
                 dict(origin=(-0.8, 0.4, 2.6), direction=(0, -1, 0),
                      length=2.4, width=0.45, strength=0.4)],
        edge_wear=dict(strength=0.3)),
    tints=[dict(center=(0.0, 7.65, 1.78), radius=0.5, rgb=_RADOME_DARK,
                strength=0.6)],
    insignia=_sidestars(0.65, -3.7, 1.55, 0.75, _BLACK))

H.texture_features(          # SH-60: navy low-vis grey
    "hel_e2_us_asw", size_class="aircraft", ao_ground="under",
    groups=("body", "gun"), group_base={"gun": "camo"},
    panels=dict(spacing=1.0, strength=0.45, jitter=0.07, seams=0.45),
    weathering=dict(
        exhaust=[dict(origin=(0.6, 0.8, 2.3), direction=(0, -1, 0),
                      length=1.8, width=0.4, strength=0.35)],
        edge_wear=dict(strength=0.3)),
    tints=[dict(center=(0.0, 6.15, 1.6), radius=0.45, rgb=(0.18, 0.19, 0.21),
                strength=0.6)],
    insignia=_sidestars(0.4, -3.45, 1.7, 0.6, _LOWVIS))

H.texture_features(          # RQ-4: white, grey stencil, bulged nose
    "uav_e5_us_recon", size_class="aircraft", ao_ground="under",
    groups=("body", "deck"), group_base={"deck": "camo"},
    panels=dict(spacing=1.3, strength=0.4, jitter=0.05, seams=0.4),
    weathering=dict(edge_wear=dict(strength=0.3)),
    tints=[dict(center=(0.0, 6.5, 0.15), radius=0.7, rgb=(0.55, 0.57, 0.60),
                strength=0.5)],
    insignia=_wingstars(7.1, 0.4, 0.45, 0.9, (0.32, 0.34, 0.38), alpha=0.85))

H.texture_features(          # MQ-9: grey, low-vis
    "uav_e6_us_armed", size_class="aircraft", ao_ground="under",
    groups=("body", "deck"), group_base={"deck": "camo"},
    panels=dict(spacing=1.0, strength=0.4, jitter=0.05, seams=0.4),
    weathering=dict(edge_wear=dict(strength=0.3)),
    tints=[dict(center=(0.0, 5.5, 0.0), radius=0.5, rgb=_RADOME_GREY,
                strength=0.7)],
    insignia=_wingstars(5.0, 0.35, 0.32, 0.75, _LOWVIS, dz=0.04))

H.texture_features(          # loitering munition: 3 m — panels only
    "uav_e7_us_loiter", size_class="aircraft", ao_ground="under", groups=("body",),
    panels=dict(spacing=0.45, strength=0.35, jitter=0.05, seams=0.4),
    weathering=dict(edge_wear=dict(strength=0.3)))

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
