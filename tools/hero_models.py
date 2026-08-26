"""Hero models: M1 Abrams, T-72, Leopard 2A5.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/hero_models.py

Built parametrically in Blender. Still proxies, not final art — but corrected
against published dimensions AND public-domain side-view photographs in
art/reference/ (see SOURCES.md). Turret shapes are extruded from exact SIDE
PROFILES, because the side profile is what the silhouette gate in
docs/07-art-pipeline.md actually measures.

    M1 Abrams    long, LOW turret that TAPERS DOWN toward the front, deep bustle
    T-72         small, low, DOMED cast turret set FORWARD; gill skirts front-only
    Leopard 2A6  TALL, with the wedge as a sloping forward PROW in side view

Gun overhang past the hull nose is a published figure and a strong silhouette
cue — the three differ sharply:
    M1 1.84 m   (9.77 gun-forward − 7.93 hull)
    T-72 2.87 m (9.73 − 6.86)
    Leo 3.25 m  (10.97 − 7.72, L/55)

Blender is Z-up / -Y forward. The glTF exporter converts to Y-up / -Z forward,
matching art/CONVENTIONS.md. Vehicles are built facing -Y.
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree

ROOT = "/Users/hjiang/Desktop/battle"
OUT = os.path.join(ROOT, "art", "blockout", "e4_mbt_hero")


def set_out(path):
    global OUT
    OUT = path
    os.makedirs(OUT, exist_ok=True)
R = math.radians


# ── ambient occlusion ──────────────────────────────────────────────
# bpy.ops.paint.vertex_color_dirt() runs without error in a headless build and
# writes nothing — every vertex came out pure white. Cast the rays directly so
# the result is verifiable.

_HEMI = None


def _hemi(n=28):
    """COSINE-weighted hemisphere about +Z. Deterministic.

    The previous set spaced z linearly, which is horizon-biased: most rays
    grazed along the surface where the clutter is, so everything read as
    occluded. Cosine weighting puts sample density where the light actually
    comes from.
    """
    global _HEMI
    if _HEMI is None:
        pts = []
        ga = math.pi * (3.0 - math.sqrt(5.0))
        for i in range(n):
            u = (i + 0.5) / n
            z = math.sqrt(1.0 - u)          # cosine distribution
            r = math.sqrt(max(0.0, 1.0 - z * z))
            a = ga * i
            pts.append(Vector((math.cos(a) * r, math.sin(a) * r, z)))
        _HEMI = pts
    return _HEMI


def subdivide_large_faces(obj, max_area=0.30, rounds=3):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    for _ in range(rounds):
        big = [f for f in bm.faces if f.calc_area() > max_area]
        if not big:
            break
        edges = list({e for f in big for e in f.edges})
        bmesh.ops.subdivide_edges(bm, edges=edges, cuts=1, use_grid_fill=True)
    bm.to_mesh(obj.data)
    bm.free()
    obj.data.update()


def whole_vehicle_bvh(objs):
    """One BVH over the ENTIRE vehicle, in world space.

    Baking each material group against its own mesh meant the turret cast no
    occlusion onto the hull deck and the hull cast none into the track recess —
    which is precisely why the vehicles read as one moulded piece. Occluders
    must include every group.
    """
    verts, polys = [], []
    for o in objs:
        mw = o.matrix_world
        off = len(verts)
        verts.extend([mw @ v.co for v in o.data.vertices])
        polys.extend([tuple(i + off for i in pg.vertices) for pg in o.data.polygons
                      if len(pg.vertices) in (3, 4)])
    return BVHTree.FromPolygons(verts, polys)


def bake_ao_texture(obj, res=512, samples=24):
    """Bake AO into an IMAGE instead of vertex colours, and multiply it into
    the camouflage to produce one finished albedo per part.

    This is the fix for the blocker that has failed three reviews: per-vertex
    AO cannot represent contact occlusion on a mesh whose large flat plates
    carry only corner vertices. A texture is independent of vertex density, so
    a 2.9 x 2.1 m turret roof gets 512x512 of occlusion instead of 2 samples.
    It is also the standard game workflow — bake AO, multiply into albedo.

    UV0 stays the world-scale cube projection for the camo lookup; UV1 is a
    non-overlapping smart-project used only as the bake target.
    """
    me = obj.data
    if len(me.uv_layers) < 2:
        bpy.context.view_layer.objects.active = obj
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        me.uv_layers.new(name="bake")
        me.uv_layers.active_index = 1
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.mesh.select_all(action="SELECT")
        bpy.ops.uv.smart_project(angle_limit=R(66), island_margin=0.02)
        bpy.ops.object.mode_set(mode="OBJECT")
    me.uv_layers.active_index = 1

    img = bpy.data.images.new(f"{obj.name}_ao", res, res, alpha=False)
    for m in me.materials:
        nt = m.node_tree
        n = nt.nodes.new("ShaderNodeTexImage")
        n.image = img
        n.select = True
        nt.nodes.active = n
        uvn = nt.nodes.new("ShaderNodeUVMap")
        uvn.uv_map = "bake"
        nt.links.new(uvn.outputs["UV"], n.inputs["Vector"])
        # glTF reads occlusion from a node group of this exact name
        grp = bpy.data.node_groups.get("glTF Material Output")
        if grp is None:
            grp = bpy.data.node_groups.new("glTF Material Output", "ShaderNodeTree")
            grp.interface.new_socket("Occlusion", in_out="INPUT",
                                     socket_type="NodeSocketFloat")
            grp.nodes.new("NodeGroupInput")
        gn = nt.nodes.new("ShaderNodeGroup")
        gn.node_tree = grp
        nt.links.new(n.outputs["Color"], gn.inputs["Occlusion"])

    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = samples
    # Cycles seeds its sampler randomly per run, so the baked AO image — and
    # therefore the embedded JPEG — differed between builds. Measured as an
    # 816-byte delta on an otherwise identical tank. Pin the seed.
    sc.cycles.seed = 20260825
    sc.cycles.use_animated_seed = False
    sc.render.bake.margin = 8
    sc.render.bake.use_selected_to_active = False
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.bake(type="AO")
    px = img.pixels[:]
    lit = px[0::4]
    lo, hi = min(lit), max(lit)
    mean = sum(lit) / len(lit)
    if hi - lo < 0.25:
        # fully black means the part is enclosed by other geometry; fully white
        # means the bake found no occluders. Both are placement bugs.
        print(f"      WARN {obj.name.rsplit('_', 1)[-1]}: AO flat {lo:.2f}-{hi:.2f}")
    print(f"      AO tex {obj.name.rsplit('_', 1)[-1]:7s} "
          f"{lo:.2f}-{hi:.2f} mean {mean:.2f}")
    return img


def bake_vertex_ao(obj, tree, dist=0.60, strength=0.60, ground_lo=0.66, ground_h=0.85):
    """Raycast AO into COLOR_0, plus a WORLD-space ground-contact gradient.

    dist must exceed the turret overhang or the deck never darkens. The ground
    term previously used local v.co.z, so after join() moved the origin a plate
    2.7 m in the air was shaded as if it lay on the ground.
    """
    me = obj.data
    me.calc_loop_triangles()
    mw = obj.matrix_world
    dirs = _hemi()
    ao = [1.0] * len(me.vertices)
    for i, v in enumerate(me.vertices):
        n = v.normal
        if n.length < 1e-6:
            continue
        n = n.normalized()
        wco = mw @ v.co
        wn = (mw.to_3x3() @ n).normalized()
        up = Vector((0, 0, 1)) if abs(wn.z) < 0.95 else Vector((1, 0, 0))
        tx = wn.cross(up).normalized()
        ty = wn.cross(tx)
        origin = wco + wn * 0.006
        # DISTANCE-WEIGHTED, not binary. A hit at 2.79 m used to count exactly
        # as much as a hit at 5 mm, which turns occlusion into a flat dimmer.
        acc = 0.0
        for d in dirs:
            w = (tx * d.x + ty * d.y + wn * d.z).normalized()
            hit = tree.ray_cast(origin, w, dist)
            if hit[0] is not None:
                acc += 1.0 - (hit[3] / dist) ** 0.5     # near hits dominate
        occ = 1.0 - strength * (acc / len(dirs))
        g = ground_lo + (1.0 - ground_lo) * min(1.0, max(0.0, wco.z / ground_h))
        ao[i] = max(0.11, occ * g)

    for ca in list(me.color_attributes):
        me.color_attributes.remove(ca)
    ca = me.color_attributes.new(name="Col", type="BYTE_COLOR", domain="CORNER")
    for li, lp in enumerate(me.loops):
        a = ao[lp.vertex_index]
        ca.data[li].color = (a, a, a, 1.0)
    # Two attributes reaching the exporter means the empty one wins COLOR_0 and
    # the real data lands in COLOR_1, which no glTF consumer reads. Force one,
    # and make it both the active and the render colour.
    me.color_attributes.active_color_index = 0
    me.color_attributes.render_color_index = 0
    assert len(me.color_attributes) == 1, "more than one colour attribute"
    back = [ca.data[i].color[0] for i in range(0, len(ca.data), max(1, len(ca.data) // 50))]
    print(f"      [{obj.name.split('_')[-1]}] wrote ao {min(ao):.2f}-{max(ao):.2f}  "
          f"readback {min(back):.2f}-{max(back):.2f}  attrs={len(me.color_attributes)} "
          f"name={ca.name} type={ca.data_type} domain={ca.domain}")


# ── material grouping ──────────────────────────────────────────────
# Parts are tagged as they are built, then joined per group so the hull can
# carry camouflage while tracks and gun stay bare metal.
CURRENT = "body"
GROUPS = {}


def tag(o):
    GROUPS.setdefault(CURRENT, []).append(o)
    return o


def use(group):
    global CURRENT
    CURRENT = group


# ── primitives ─────────────────────────────────────────────────────
def profile(pts, width, name="prof"):
    """Extrude a closed side profile (list of (y, z)) along X.

    This is the important helper: it lets each turret have an EXACT side
    silhouette instead of being approximated by stacked boxes.
    """
    me = bpy.data.meshes.new(name)
    obj = bpy.data.objects.new(name, me)
    bpy.context.collection.objects.link(obj)
    bm = bmesh.new()
    vs = [bm.verts.new((-width / 2, y, z)) for (y, z) in pts]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    moved = [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]
    bmesh.ops.translate(bm, vec=(width, 0, 0), verts=moved)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    bm.to_mesh(me)
    bm.free()
    return tag(obj)


def cube(loc, size, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = size
    return tag(o)


def cyl(loc, r, d, rot=(0, 0, 0), v=16, taper=1.0):
    if taper == 1.0:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=d, location=loc,
                                            rotation=rot, vertices=v)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r * taper, depth=d,
                                        location=loc, rotation=rot, vertices=v)
    return tag(bpy.context.object)


def dome(loc, rx, ry, rz, v=24):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=1.0, location=loc,
                                         segments=v, ring_count=v // 2)
    o = bpy.context.object
    o.scale = (rx, ry, rz)
    return tag(o)


def wedge(loc, w, length, h, rot_z=0.0):
    """Arrowhead plate — the Leopard 2A5 signature."""
    bpy.ops.mesh.primitive_cone_add(vertices=3, radius1=1.0, depth=1.0,
                                    location=loc, rotation=(R(90), 0, rot_z))
    o = bpy.context.object
    o.scale = (w, h, length)
    return tag(o)


def running_gear(hull_l, hull_w, clearance, n_wheels, wheel_r, skirt_h,
                 skirt_front_only=False):
    """Real running gear: roadwheels on the ground, track curving up over a
    raised idler and sprocket, skirt covering only the UPPER half of the wheels.

    The previous version was a solid slab the full length of the hull, which
    made every vehicle a brick sitting flat on the ground — the single biggest
    reason the models read as toys. Ground contact should be ~60% of hull
    length, not 100%, and the gap under the belly has to be visible.
    """
    parts = []
    tw = 0.60
    contact = hull_l * 0.60
    ex = contact / 2
    end_x = hull_l * 0.455
    end_z = wheel_r * 1.55
    top_z = wheel_r * 2.05

    for s in (-1, 1):
        use("track")            # per side. Setting this once outside the loop
        x = s * (hull_w / 2 - tw / 2)   # put the right-hand track into the hull
                                        # mesh, where it picked up camouflage.
        # Wheels stay DARK on every scheme. On a tan vehicle, camo-painted
        # discs erase the lower value band entirely — and that band is the
        # horizontal break that makes a tank read as tracked at any distance.
        # Hub plates in body colour give the internal structure instead.
        use("body")
        for i in range(n_wheels):
            y = -ex + i * (contact * 1.02 / (n_wheels - 1))
            parts.append(cyl((x, y, wheel_r), wheel_r * 0.44, tw * 0.90,
                             rot=(0, R(90), 0), v=12))
        use("track")
        for i in range(n_wheels):
            y = -ex + i * (contact * 1.02 / (n_wheels - 1))
            parts.append(cyl((x, y, wheel_r), wheel_r * 0.92, tw * 0.84,
                             rot=(0, R(90), 0), v=14))
        for i in range(n_wheels):
            y = -ex + i * (contact * 1.02 / (n_wheels - 1))
            parts.append(cyl((x, y, wheel_r), wheel_r, tw * 0.62,
                             rot=(0, R(90), 0), v=14))
        for y in (-end_x, end_x):
            parts.append(cyl((x, y, end_z), wheel_r * 0.74, tw * 0.80,
                             rot=(0, R(90), 0), v=12))
        n = 22
        for k in range(n):
            y = -ex + k * (contact / (n - 1))
            parts.append(cube((x, y, 0.035), (tw, contact / n * 0.92, 0.07)))
        for sgn in (-1, 1):
            # Segments must OVERLAP. Spacing them by their own projected length
            # left ~58 mm gaps and the run shipped as detached islands.
            y0, y1 = sgn * ex, sgn * end_x
            steps = 6
            seg = (abs(y1 - y0) / steps) / math.cos(R(34)) * 1.9
            for k in range(steps + 1):
                f = k / float(steps)
                parts.append(cube((x, y0 + (y1 - y0) * f,
                                   0.035 + (end_z - 0.035) * f),
                                  (tw, seg, 0.075), rot=(R(-sgn * 34), 0, 0)))
        parts.append(cube((x, 0, top_z), (tw * 0.96, end_x * 2 * 0.94, 0.07)))

        use("body")
        sl = hull_l * (0.52 if skirt_front_only else 0.93)
        sy = -hull_l * 0.20 if skirt_front_only else 0.0
        sbot = wheel_r * 1.34   # show two thirds of the wheel
        stop = clearance + skirt_h
        # discrete bolted panels with visible joints — free silhouette detail
        npan = 4 if skirt_front_only else 6
        for k in range(npan):
            py = sy - sl / 2 + (k + 0.5) * (sl / npan)
            # inboard of the track, so the TRACK is the widest thing on the
            # vehicle and throws a hard shadow line down the flank
            parts.append(cube((s * (hull_w / 2 - 0.16), py, (sbot + stop) / 2),
                              (0.10, sl / npan * 0.94, stop - sbot)))
        parts.append(cube((s * (hull_w / 2 - 0.15), sy, stop - 0.05),
                          (0.13, sl, 0.09)))          # top rail
    use("body")
    return parts


def barrel(y_tip, z, length, r, sleeve_len=0.0, sleeve_r=0.0):
    use("gun")
    """y_tip is the ABSOLUTE muzzle position, set from published
    length-gun-forward minus hull length. Barrel runs back from there."""
    y_breech = y_tip + length
    # The tube is PAINTED in the vehicle scheme, not bare metal — every
    # reference photo shows this, and a grey barrel is the first thing the eye
    # finds in a gameplay frame. Only the last half-metre is gun material.
    use("body")
    inner = length * 0.82
    parts = [cyl((0, y_breech - inner / 2, z), r * 1.06, inner,
                 rot=(R(90), 0, 0), v=16)]                     # parallel-sided
    if sleeve_len:
        parts.append(cyl((0, y_breech - sleeve_len / 2, z), sleeve_r, sleeve_len,
                         rot=(R(90), 0, 0), v=16))             # one shroud step
        parts.append(cyl((0, y_breech - sleeve_len - 0.05, z), sleeve_r * 0.99,
                         0.10, rot=(R(90), 0, 0), v=16))
    # bore evacuator bulge at ~55% out
    parts.append(cyl((0, y_tip + length * 0.45, z), r * 1.42, 0.46,
                     rot=(R(90), 0, 0), v=16))
    use("gun")
    parts.append(cyl((0, y_tip + (length - inner) / 2, z), r * 1.02, length - inner,
                     rot=(R(90), 0, 0), v=16))
    parts.append(cyl((0, y_tip + 0.09, z), r * 1.20, 0.18, rot=(R(90), 0, 0), v=16))
    use("gunbore")
    parts.append(cyl((0, y_tip + 0.008, z), r * 0.62, 0.02, rot=(R(90), 0, 0), v=14))
    use("body")
    return parts


def detail_kit(HL, HW, top, roof, t_front, t_rear, era=0, mg=True):
    """Small parts that sell the model at close range and vanish by LOD2."""
    p = []
    use("body")
    tmid = (t_front + t_rear) / 2
    p.append(cyl((-0.55, tmid + 0.15, roof + 0.05), 0.36, 0.10, v=14))  # loader hatch
    for s in (-1, 1):                                               # lift eyes
        p.append(cube((s * 0.62, t_rear - 0.30, roof - 0.10), (0.14, 0.22, 0.20)))
    p.append(cube((0.30, -HL / 2 + 0.35, top + 0.06), (0.34, 0.24, 0.18)))   # headlight
    p.append(cube((-0.30, -HL / 2 + 0.35, top + 0.06), (0.34, 0.24, 0.18)))
    for s in (-1, 1):                                               # fender stowage
        p.append(cube((s * (HW / 2 - 0.22), -HL * 0.22, top + 0.14),
                      (0.36, 1.05, 0.28)))
        p.append(cube((s * (HW / 2 - 0.22), HL * 0.30, top + 0.14),
                      (0.36, 0.80, 0.26)))
    use("gun")
    if mg:
        p.append(cyl((0.62, -0.55, roof + 0.42), 0.045, 1.10, rot=(R(90), 0, 0), v=8))
        p.append(cube((0.62, 0.15, roof + 0.30), (0.20, 0.34, 0.22)))
    # antennas mount on the HULL deck, which every vehicle definitely has
    # underneath — mounting them off the turret roof left them hovering
    p.append(cyl((-1.15, HL * 0.26, top + 0.42), 0.045, 0.84, v=6))
    p.append(cyl((1.15, HL * 0.31, top + 0.34), 0.045, 0.68, v=6))
    use("team")
    # dedicated team-colour patch, flat and visible from directly above.
    # CONVENTIONS.md requires it and without it you cannot tell sides apart.
    ty = t_front + (t_rear - t_front) * 0.34
    p.append(cube((0.02, ty, roof + 0.030), (0.62, 0.44, 0.06)))
    use("era")
    for i in range(era):
        if i < 6:      # glacis bricks, angled with the plate
            col = i % 3; row = i // 3
            p.append(cube((-0.72 + col * 0.72, -HL / 2 + 0.55 + row * 0.42,
                           top - 0.62 + row * 0.30),
                          (0.62, 0.36, 0.14), rot=(R(-22), 0, 0)))
        else:          # turret cheeks
            k = i - 6
            p.append(cube(((-1 if k % 2 else 1) * (0.92 + 0.10 * (k // 2)),
                           -1.05 + (k // 2) * 0.40, top + 0.32),
                          (0.34, 0.34, 0.16)))
    use("body")
    return p


# ── the three heroes ───────────────────────────────────────────────
# Turret side profiles are (y, z) in metres, absolute Z from the ground.
# y is negative toward the front (Blender -Y is forward).

def m1_abrams():
    """M1A2. Long LOW turret tapering down at the front; deep rear bustle.
    7 small road wheels. Gun overhangs the nose by only 1.84 m."""
    HL, HW, CL, HH = 7.93, 3.66, 0.48, 1.05
    top, ROOF = CL + HH, 2.44
    p = []
    # hull as one side profile — the long shallow glacis is part of it, not a
    # separate plate bolted onto the nose
    # nose drops ~0.5 m and the glacis slopes back — from the RTS camera the
    # long low driver's plate ahead of the turret ring is a major identity cue
    p.append(profile([(-HL / 2, CL), (-HL / 2 + 0.12, CL + 0.52),
                      (-HL / 2 + 2.30, top), ( HL / 2, top),
                      ( HL / 2, CL)], HW, "m1_hull"))
    use("deck")
    p.append(cube((0, HL * 0.33, top - 0.03), (2.50, 2.40, 0.08)))   # shallow well
    for k in range(11):        # slat TOPS sit above the deck plate, not in a pit
        p.append(cube((0, HL * 0.33 - 1.10 + k * 0.22, top + 0.075),
                      (2.34, 0.13, 0.17)))
    use("body")
    for s in (-1, 1):                                                # grille frame
        p.append(cube((s * 1.32, HL * 0.33, top + 0.05), (0.16, 2.55, 0.12)))
    p.append(cube((0, HL * 0.33, top - 0.04), (HW * 0.96, 2.6, 0.16)))

    # side profile: low sloped front → flat roof → deep square bustle
    # turret ~3.9 m (49% of hull), leaving ~2.2 m of glacis ahead of the ring
    p.append(profile([(-1.86, 1.72), (-1.82, 2.04), (-1.05, 2.40),
                      ( 1.05, ROOF), ( 2.04, 2.34), ( 2.04, 1.62),
                      ( 0.20, top),  (-1.30, top)], 2.92, "m1_turret"))
    for s in (-1, 1):                                        # M1 front cheeks taper IN
        p.append(cube((s * 1.02, -1.30, 2.02), (0.98, 1.20, 0.62),
                      rot=(0, 0, R(-s * 9))))
    p.append(cube((0, 2.24, 2.02), (2.30, 0.30, 0.56)))     # bustle stowage rack
    p.append(cyl((0.60, 0.80, ROOF + 0.20), 0.34, 0.40, v=12))       # cupola
    p.append(cube((-0.86, -0.30, ROOF + 0.22), (0.52, 0.66, 0.44)))  # GPS sight block
    use("deck")
    for s in (-1, 1):                                                 # blowout panels
        p.append(cube((s * 0.62, 1.62, ROOF + 0.02), (1.02, 0.86, 0.07)))
    use("body")

    p += barrel(-5.805, 1.86, 3.95, 0.105, 1.55, 0.158)     # tip 1.84 m past nose
    p += detail_kit(HL, HW, top, ROOF, -1.86, 2.04, era=0)
    p += running_gear(HL, HW, CL, 7, 0.32, 0.60)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=1.86, gun_y=-2.78)


def t72():
    """T-72A. Small, low, DOMED cast turret set well forward. 6 large road
    wheels. Gill skirts front half only. Gun overhangs 2.87 m."""
    HL, HW, CL, HH = 6.86, 3.59, 0.49, 1.00
    top, ROOF = CL + HH, 2.23
    p = []
    p.append(profile([(-HL / 2, CL), (-HL / 2 + 1.38, top),
                      ( HL / 2, top), ( HL / 2, CL)], HW, "t72_hull"))
    p.append(cube((0, -HL / 2 + 0.50, CL + 0.30), (HW * 0.55, 0.44, 0.12),
                  rot=(R(-38), 0, 0)))                      # V splash guard
    # wide flat fenders — very visible from above in the reference
    for s in (-1, 1):        # fenders INSIDE the hull width — the T-72 is the
        p.append(cube((s * (HW / 2 - 0.20), 0.1, top - 0.06),   # narrowest of
                      (0.34, HL * 0.92, 0.09)))                  # the three


    d = dome((0, -0.52, top - 0.22), 1.24, 1.28, 0.78, v=22)   # forward-set dome
    p.append(d)
    p.append(cube((0, 0.52, top + 0.16), (1.88, 0.76, 0.44)))  # turret rear
    p.append(cyl((0.44, -0.05, ROOF - 0.14), 0.30, 0.22, v=14))      # cupola
    use("deck")
    p.append(cyl((0.44, -0.05, ROOF - 0.02), 0.34, 0.05, v=14))      # DShK ring
    p.append(cyl((-0.46, 0.02, ROOF - 0.16), 0.27, 0.05, v=14))      # loader hatch
    for k in range(5):                                               # engine louvres
        p.append(cube((0, HL * 0.30 + (k - 2) * 0.28, top + 0.01),
                      (2.15, 0.20, 0.07)))
    use("body")
    p.append(cyl((-0.34, 1.02, top + 0.62), 0.13, 1.30, rot=(R(62), 0, 0), v=8))

    p += barrel(-6.30, 1.86, 4.45, 0.125, 1.80, 0.175)      # long visible barrel
    for s in (-1, 1):                                        # external fuel drums
        p.append(cyl((s * 1.00, HL / 2 - 0.16, top - 0.02), 0.27, 0.92,
                     rot=(R(90), 0, 0), v=12))
    p += detail_kit(HL, HW, top, top + 0.54, -1.60, 0.86, era=10)
    p += running_gear(HL, HW, CL, 6, 0.40, 0.40, skirt_front_only=True)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=1.86, gun_y=-1.85)


def leopard2a6():
    """Leopard 2A6. TALL, with the spaced-armour wedge as a sloping forward
    PROW in side view. 7 large well-separated road wheels. L/55 gun
    overhanging 3.25 m — the longest of the three."""
    HL, HW, CL, HH = 7.72, 3.75, 0.49, 1.15
    top, ROOF = CL + HH, 2.64
    p = []
    p.append(profile([(-HL / 2, CL), (-HL / 2 + 1.52, top),
                      ( HL / 2, top), ( HL / 2, CL)], HW, "leo_hull"))

    # the A5/A6 wedge: a sharp prow sloping down and forward from the roof
    # turret body ~4.3 m; the wedge projects forward of the face, it is not
    # the turret itself
    p.append(profile([(-2.42, 1.88), (-1.20, 2.58), ( 1.10, ROOF),
                      ( 1.90, 2.54), ( 1.90, 1.80), ( 0.10, top),
                      (-1.40, top)], 2.88, "leo_turret"))
    # the wedge is an arrowhead in PLAN as well as a prow in elevation — without
    # the plan-view half it vanishes at RTS camera angles, where the turret roof
    # outline is most of what the player sees
    for s in (-1, 1):
        # the 2A6 wedge projects ~1.5 m ahead of the turret face at an acute
        # angle — it is the entire visual identity of the variant
        p.append(cube((s * 0.66, -2.34, 2.20), (1.16, 2.30, 0.62),
                      rot=(0, 0, R(s * 21))))
    p.append(cube((0, 2.10, 2.10), (2.24, 0.30, 0.60)))     # stowage basket
    p.append(cyl((0.58, 1.02, ROOF + 0.18), 0.33, 0.40, v=12))       # PERI cupola
    p.append(cube((-0.88, 0.10, ROOF + 0.26), (0.52, 0.64, 0.52)))   # EMES-15 sight
    use("deck")
    for k in range(8):                                               # smoke bank
        p.append(cyl((-1.40, -0.55 + (k % 4) * 0.26, 2.28 + (k // 4) * 0.26),
                     0.055, 0.30, rot=(0, R(90), 0), v=8))
    for s in (-1, 1):                                                # rear grilles
        p.append(cube((s * 0.95, HL * 0.34, top - 0.03), (1.55, 1.95, 0.08)))
        for k in range(7):        # slats — the Leopard was left a bare plate
            p.append(cube((s * 0.95, HL * 0.34 - 0.78 + k * 0.26, top + 0.075),
                          (1.44, 0.14, 0.17)))
    use("body")

    p += barrel(-7.11, 1.92, 5.35, 0.112, 2.30, 0.162)
    p += detail_kit(HL, HW, top, ROOF, -2.42, 1.90, era=0)
    p += running_gear(HL, HW, CL, 7, 0.375, 0.66)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=1.92, gun_y=-2.10)


# ── assembly / export ──────────────────────────────────────────────
SOCKETS = ["turret_mount", "gun_mantlet", "sensor_mast", "exhaust",
           "track_left", "track_right",
           "damage_hull", "damage_turret", "damage_track"]


def sockets_for(m):
    hw, hl = m["hull_w"], m["hull_l"]
    s = {
        "turret_mount":  (0, 0.2, m["top"]),
        "gun_mantlet":   (0, m["gun_y"], m["gun_z"]),
        "sensor_mast":   (0.62, 0.7, m["turret_top"] + 0.12),
        "exhaust":       (0, hl / 2, m["top"] - 0.18),
        "track_left":    (-(hw / 2 - 0.30), 0, 0.30),
        "track_right":   ((hw / 2 - 0.30), 0, 0.30),
        "damage_hull":   (0, -0.6, m["top"]),
        "damage_turret": (0, 0.2, m["turret_top"]),
        "damage_track":  (-(hw / 2), -1.2, 0.30),
    }
    for i in range(6):
        s[f"era_plate_{i+1}"] = (-0.6 + (i % 3) * 0.6, m["gun_y"] + 0.5,
                                 m["top"] + 0.3 + (i // 3) * 0.34)
    for i in range(4):
        s[f"aps_launcher_{i+1}"] = ((-1 if i % 2 else 1) * (hw / 2 - 0.5),
                                    0.5 - (i // 2) * 0.9, m["turret_top"] - 0.2)
    for i in range(4):
        s[f"hardpoint_{i+1}"] = (0, 1.0 - i * 0.5, m["turret_top"] + 0.15)
    return s


TEX = "/Users/hjiang/Desktop/battle/art/textures"
# Distinct per side, and chosen at a fixed luminance so the marking has similar
# salience against desert tan and against dark green.
TEAM = {"mbt_e4_us_m1_abrams":  (0.06, 0.20, 0.62),   # NATO blue
        "mbt_e4_de_leopard2a6": (0.10, 0.32, 0.72),   # NATO blue, lighter
        "mbt_e4_ru_t72":        (0.68, 0.10, 0.10)}   # opposing red

CAMO = {"mbt_e4_us_m1_abrams": "camo_us",
        "mbt_e4_ru_t72": "camo_ru",
        "mbt_e4_de_leopard2a6": "camo_de"}


def uvproj(obj, world_size=2.2, jitter=0.0):
    """Uniform WORLD-SCALE cube projection.

    smart_project normalises islands to the object's own UV area, so a 0.14 m
    stowage box and a 7.7 m hull side received the same number of camo blobs —
    small parts landed inside a single blob and came out flat pale grey, and
    long thin islands stretched anisotropically into horizontal wood-grain
    banding. A cube projection at a fixed size in metres fixes both.
    """
    bpy.context.view_layer.objects.active = obj
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.cube_project(cube_size=world_size)
    bpy.ops.object.mode_set(mode="OBJECT")
    if jitter:
        for lp in obj.data.uv_layers[0].data:
            lp.uv = (lp.uv[0] + jitter, lp.uv[1] + jitter * 0.61)


def mat_textured(mname, png, rough=0.82, metal=0.0):
    m = bpy.data.materials.new(mname)
    m.use_nodes = True
    m.use_backface_culling = True          # -> doubleSided: false in glTF
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Metallic"].default_value = metal
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(TEX, png + ".png"), check_existing=True)
    tex.interpolation = "Smart"
    nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return m


def mat_flat(mname, rgb, rough=0.65, metal=0.6):
    m = bpy.data.materials.new(mname)
    m.use_nodes = True
    m.use_backface_culling = True
    b = m.node_tree.nodes["Principled BSDF"]
    # Set base colour DIRECTLY. Routing it through a MixRGB to multiply vertex
    # colour defeats the glTF exporter's node-graph reader, which then falls
    # back to white baseColorFactor. glTF multiplies COLOR_0 into base colour
    # per spec, so the node graph was never needed.
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m


GROUP_MATS = {
    "body":  lambda n: mat_textured(f"{n}_body", CAMO[n], 0.78, 0.05),
    "track": lambda n: mat_flat(f"{n}_track", (0.050, 0.048, 0.046), 0.62, 0.70),
    "gun":   lambda n: mat_flat(f"{n}_gun", (0.115, 0.118, 0.105), 0.72, 0.0),
    "glass": lambda n: mat_flat(f"{n}_glass", (0.045, 0.058, 0.075), 0.06, 0.35),
    "team":  lambda n: mat_flat(f"{n}_team", TEAM[n], 0.85, 0.0),
    "deck":  lambda n: mat_flat(f"{n}_deck", (0.105, 0.098, 0.082), 0.86, 0.02),
    "gunbore": lambda n: mat_flat(f"{n}_bore", (0.012, 0.012, 0.014), 0.9, 0.0),
    "era":   lambda n: mat_flat(f"{n}_era", (0.20, 0.23, 0.16), 0.88, 0.02),
}


def build(name, fn, lod):
    global GROUPS, CURRENT
    bpy.ops.wm.read_factory_settings(use_empty=True)
    GROUPS, CURRENT = {}, "body"
    parts, m = fn()

    for o in parts:
        bpy.context.view_layer.objects.active = o
        o.select_set(True)
        bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
        o.select_set(False)

    root = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(root)

    # ── pass 1: join each material group and apply modifiers ──────────
    made = {}
    for gname, objs in GROUPS.items():
        objs = [o for o in objs if o.name in bpy.data.objects]
        if not objs:
            continue
        bpy.ops.object.select_all(action="DESELECT")
        for o in objs:
            o.select_set(True)
        bpy.context.view_layer.objects.active = objs[0]
        if len(objs) > 1:
            bpy.ops.object.join()
        g = bpy.context.object
        g.name = f"{name}_LOD{lod}_{gname}"
        bpy.context.view_layer.objects.active = g
        if lod <= 1:
            bev = g.modifiers.new("bevel", "BEVEL")
            bev.width = 0.024 if lod == 0 else 0.016
            bev.segments = 3 if lod == 0 else 2
            bev.limit_method = "ANGLE"
            bev.angle_limit = R(24)
            bev.harden_normals = True
            bpy.ops.object.modifier_apply(modifier=bev.name)
        if lod >= 1:
            dec = g.modifiers.new("dec", "DECIMATE")
            dec.ratio = 0.34 if lod == 1 else 0.09
            bpy.ops.object.modifier_apply(modifier=dec.name)
        bpy.ops.object.select_all(action="DESELECT")
        g.select_set(True)
        bpy.context.view_layer.objects.active = g
        bpy.ops.object.shade_smooth()
        es = g.modifiers.new("edgesplit", "EDGE_SPLIT")
        es.split_angle = R(26)
        es.use_edge_angle, es.use_edge_sharp = True, True
        bpy.ops.object.modifier_apply(modifier=es.name)
        made[gname] = g

    # ── pass 2: ONE BVH over the whole vehicle, then bake every group ──
    # Per-vertex AO cannot represent contact occlusion on a mesh whose large
    # plates carry only corner vertices — the M1 turret roof had TWO up-facing
    # verts for a 2.9 x 2.1 m plate, so it was shaded entirely by its corners.
    # Give the big faces interior vertices before baking.
    # A ground plane during the bake turns geometric AO into real CONTACT
    # occlusion — the track and lower hull darken because the ground is there,
    # which is what pulls the running gear out of the silhouette.
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, -0.002))
    ground = bpy.context.object
    # hash() is salted per process, so camo alignment changed on every
    # rebuild and the build was not reproducible.
    jitter = (sum(ord(c) * (i + 7) for i, c in enumerate(name)) % 97) / 97.0
    for gname, g in made.items():
        uvproj(g, world_size=2.2, jitter=jitter)
        g.data.materials.append(GROUP_MATS[gname](name))
    for gname, g in made.items():
        # LOD1 is what the RTS camera actually renders — bake it too
        if lod <= 1:
            bake_ao_texture(g, res=(1024 if gname == "body" else 256))
        g.parent = root
    bpy.data.objects.remove(ground, do_unlink=True)

    for k, v in sockets_for(m).items():
        e = bpy.data.objects.new(f"SOCKET_{k}", None)
        e.empty_display_size = 0.18
        e.location = v
        bpy.context.collection.objects.link(e)
        e.parent = root

    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}_LOD{lod}.glb")
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB",
                              use_selection=True, export_apply=True,
                              export_yup=True, export_extras=True,
                              export_image_format="JPEG",
                              export_vertex_color="NAME",
                              export_vertex_color_name="Col",
                              export_all_vertex_colors=False)
    tris = sum(sum(len(pg.vertices) - 2 for pg in o.data.polygons)
               for o in root.children if o.type == "MESH")
    det = check_detached(root)
    if det and lod == 0:
        print(f"      WARN {os.path.basename(path)}: {len(det)} detached island(s)")
    verify_export(path, lod)
    return tris


def check_detached(root, tol=0.035):
    """Report mesh islands floating clear of the ENTIRE vehicle.

    The previous version compared islands only within a single object, so a
    machine gun in the `gun` group that rests on the `body` mesh looked
    orphaned, while a genuinely floating box in the same group looked fine.
    Islands must be gathered across every group and tested against all of them.
    """
    import bmesh as _bm
    boxes, labels = [], []
    for o in root.children:
        if o.type != "MESH":
            continue
        mw = o.matrix_world
        bm = _bm.new()
        bm.from_mesh(o.data)
        _bm.ops.remove_doubles(bm, verts=bm.verts, dist=0.001)
        seen = set()
        for v in bm.verts:
            if v.index in seen:
                continue
            stack, comp = [v], []
            seen.add(v.index)
            while stack:
                cur = stack.pop()
                comp.append(mw @ cur.co)
                for ed in cur.link_edges:
                    ov = ed.other_vert(cur)
                    if ov.index not in seen:
                        seen.add(ov.index)
                        stack.append(ov)
            xs = [c.x for c in comp]; ys = [c.y for c in comp]; zs = [c.z for c in comp]
            boxes.append((min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
            labels.append(o.name.rsplit("_", 1)[-1])
        bm.free()

    bad = []
    for i, a in enumerate(boxes):
        if (a[1] - a[0]) < 0.004 and (a[5] - a[4]) < 0.004:
            continue
        near = False
        for j, b in enumerate(boxes):
            if i == j:
                continue
            if (a[0] - tol <= b[1] and b[0] - tol <= a[1] and
                    a[2] - tol <= b[3] and b[2] - tol <= a[3] and
                    a[4] - tol <= b[5] and b[4] - tol <= a[5]):
                near = True
                break
        if not near:
            bad.append((labels[i], round(a[4], 3)))
    if bad:
        print(f"      DETACHED {len(bad)}/{len(boxes)}: " +
              ", ".join(f"{n}@z={z}" for n, z in bad[:8]))
    return bad


def verify_export(path, lod=0):
    """Assert the artifact carries a real occlusionTexture and world-scale UVs.

    AO now lives in a baked image rather than COLOR_0, so the pixel statistics
    are checked in bake_ao_texture() against the image that gets embedded.
    This checks the structure that reaches the file: that an occlusionTexture
    exists on the large groups, that it points at real image data, and that
    TEXCOORD_0 still carries the 1/2.2 m world-scale density.
    """
    import json as _j, struct as _s
    with open(path, "rb") as f:
        f.read(12)
        jlen, _ = _s.unpack("<II", f.read(8))
        doc = _j.loads(f.read(jlen))
        blen, _ = _s.unpack("<II", f.read(8))
        bin_ = f.read(blen)

    NC = {"VEC2": 2, "VEC3": 3, "VEC4": 4}
    FMT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
           5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}

    def span(ai, comps):
        acc = doc["accessors"][ai]
        fmt, size = FMT[acc["componentType"]]
        bv = doc["bufferViews"][acc["bufferView"]]
        off = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
        stride = bv.get("byteStride") or size * NC[acc["type"]]
        mn = [1e9] * comps
        mx = [-1e9] * comps
        n = acc["count"]
        for i in range(0, n, max(1, n // 400)):
            for c in range(comps):
                v = _s.unpack_from("<" + fmt, bin_, off + i * stride + c * size)[0]
                mn[c] = min(mn[c], v); mx[c] = max(mx[c], v)
        return [mx[c] - mn[c] for c in range(comps)]

    mats = doc.get("materials", [])
    imgs = doc.get("images", [])
    fails, rows = [], []
    for mesh in doc.get("meshes", []):
        for pr in mesh["primitives"]:
            at = pr["attributes"]
            mi = pr.get("material")
            m = mats[mi] if mi is not None else {}
            gname = m.get("name", "?").rsplit("_", 1)[-1]
            npos = doc["accessors"][at["POSITION"]]["count"]
            occ = m.get("occlusionTexture")
            if npos > 400 and lod <= 1:
                if occ is None:
                    fails.append(f"{gname} has no occlusionTexture")
                else:
                    src = doc["textures"][occ["index"]].get("source")
                    if src is None or src >= len(imgs):
                        fails.append(f"{gname} occlusionTexture -> no image")
            if "TEXCOORD_0" in at and npos > 400:
                du = span(at["TEXCOORD_0"], 2)[0]
                dxz = span(at["POSITION"], 3)
                world = max(dxz[0], dxz[2])
                if world > 0.2:
                    dens = du / world
                    rows.append((gname, dens, occ is not None))
                    # cube_project maps each face to its dominant axis, so a
                    # group containing a 6 m barrel reports a skewed ratio. A
                    # wider band still catches a gross scale error (the old
                    # smart_project x17 measured ~3.0) without false alarms.
                    if lod <= 1 and not (0.30 < dens < 0.62):
                        fails.append(f"{gname} UV density {dens:.3f} off 1/2.2")
    if fails:
        raise SystemExit(f"FAIL {os.path.basename(path)} LOD{lod}: "
                         + "; ".join(fails[:4]))
    if lod == 0 and rows:
        print("      " + "  ".join(f"{g}[uv{d:.2f}{'+ao' if o else ''}]"
                                   for g, d, o in rows))


HEROES = [("mbt_e4_us_m1_abrams", m1_abrams),
          ("mbt_e4_ru_t72", t72),
          ("mbt_e4_de_leopard2a6", leopard2a6)]

if __name__ == "__main__":
    print("building hero models...")
    for name, fn in HEROES:
        for lod in (0, 1, 2):
            n = build(name, fn, lod)
            print(f"  {name:26s} LOD{lod}  {n:6d} tris")
    print("done")
