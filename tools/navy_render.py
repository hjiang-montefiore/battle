"""Render the naval roster. Ships need their own treatment.

    Blender -b --python tools/navy_render.py

A carrier is 333 m and a midget submarine is 29 m — a 11:1 spread that no
single lineup camera can hold. The vehicle renders get away with one shared
camera because a tank and a truck are within 2:1 of each other; ships do not.

So this renders in three size bands at a shared scale WITHIN each band, and
labels the band, rather than pretending one frame can show them all. Submarines
get a waterline plane, because a submarine rendered in air reads as a lost
fuselage and tells you nothing about what a player would see.
"""
import bpy, math, os, sys
from mathutils import Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gameplay_render as R

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "blockout", "e4_navy")
OUT = os.path.join(ROOT, "art", "renders")

# (unit, label) grouped by hull length so a band shares one honest scale
CAPITAL = [("nav_e1_us_carrier", "CARRIER 333m"),
           ("nav_e2_us_amphib", "AMPHIB 257m"),
           ("nav_e1_us_oiler", "OILER 206m")]
ESCORT = [("nav_e4_us_destroyer", "DESTROYER 155m"),
          ("nav_e1_us_cruiser", "CRUISER 173m"),
          ("nav_e1_us_frigate", "ASW FRIGATE 138m"),
          ("nav_e1_us_corvette", "CORVETTE 90m")]
SMALL = [("nav_e2_us_missileboat", "MISSILE BOAT 56m"),
         ("nav_e1_us_patrol", "PATROL 52m"),
         ("nav_e1_us_minewarfare", "MINEHUNTER 68m"),
         ("nav_e1_us_landingcraft", "LANDING CRAFT 27m")]
SUBS = [("sub_e2_us_nuclear", "SSN 110m"),
        ("sub_e1_us_diesel", "SSK 76m"),
        ("sub_e7_de_aip", "AIP 56m"),
        ("sub_e1_kp_midget", "MIDGET 29m")]


def load(name, x, y=0.0, yaw=0.0):
    path = os.path.join(SRC, f"{name}_LOD0.glb")
    if not os.path.exists(path):
        print("  MISSING", name)
        return []
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    # matrix_world, not location + rotation_euler. Setting rotation_euler on the
    # imported root does not reach its children here: an object's matrix_world is
    # only recomputed on a scene update, and in a -b script neither
    # view_layer.update() nor a depsgraph update rebuilt it — measured, the
    # children kept their unrotated matrices and the plan sheet came out with
    # four ships stacked on top of each other. tools/naval_waterline_render.py
    # already composes the matrix by hand for the same reason.
    M = Matrix.Translation((x, y, 0.0)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    for o in new:
        if o.parent is None:
            o.matrix_world = M @ o.matrix_world
    R.apply_occlusion([o for o in new if o.type == "MESH"])
    return new


def sea(size=1400.0):
    """A flat water plane at z=0. Every hull in navy_models is built with its
    waterline on z=0, so this is what separates freeboard from draught and is
    the only way a submarine render means anything."""
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    o = bpy.context.object
    m = bpy.data.materials.new("sea")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.045, 0.085, 0.125, 1)
    b.inputs["Roughness"].default_value = 0.14
    b.inputs["Metallic"].default_value = 0.0
    o.data.materials.append(m)
    return o


def band(items, out, spacing, cam, look, lens, w=1800, h=720, yaw=0.0):
    """Spread ABEAM, not in line.

    navy_models builds every hull with its length along Y, so spacing the
    lineup along Y puts the ships nose-to-tail and the camera ends up inside
    the formation looking down a 333 m flight deck. They go side by side on X,
    and the camera sits far enough back to hold the longest hull in frame."""
    R.reset()
    R.sun(strength=3.2, elev=38, azim=132)
    sea()
    n = len(items)
    for i, (name, _label) in enumerate(items):
        load(name, (i - (n - 1) / 2.0) * spacing, 0.0, yaw)
    R.camera(cam, look, lens=lens)
    R.render(os.path.join(OUT, out), w, h, 44)
    print(f"  {out}: {', '.join(l for _, l in items)}")


def plan(items, out, spacing, span, w=1900, px=0):
    """ORTHOGRAPHIC PLAN — the sheet the whole roster is actually designed for.

    Every claim in navy_models about an "exclusive identifying feature" is a
    claim about what a player sees looking DOWN at a ship, and the three-quarter
    band sheets cannot settle it: at 30 degrees of elevation a deck is
    foreshortened and the superstructure hides what is behind it. This looks
    straight down, orthographic, so two ships are directly comparable and a
    feature either reads or it does not.

    The hulls are turned broadside — navy_models runs length along +Y, so a
    bow-up plan of a 333 m carrier wants a frame twelve times taller than it is
    wide. Yawed 90 degrees they lie across the frame and stack on Y, and the
    image height falls out of the stack instead of being guessed.

    `px` renders a second copy at that pixel height, which is the honest test:
    a detail that has vanished at 96 px is not detail, it is triangles.
    """
    R.reset()
    R.sun(strength=3.4, elev=62, azim=150)
    sea()
    n = len(items)
    for i, (name, _label) in enumerate(items):
        load(name, 0.0, ((n - 1) / 2.0 - i) * spacing, 90.0)
    h = int(round(w * (n * spacing) / span))
    R.camera((0, 0, 700), (0, 0, 0), ortho=span)
    R.render(os.path.join(OUT, out), w, h, 44)
    print(f"  {out} ({w}x{h}): {', '.join(l for _, l in items)}")
    if px:
        R.render(os.path.join(OUT, out.replace(".png", f"_{px}.png")),
                 max(int(round(w * px / float(h))), 16), px, 32)
        print(f"  {out.replace('.png', f'_{px}.png')}: the zoom test")


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    print("rendering navy...")
    #                     spacing      camera                 look        lens
    band(CAPITAL, "navy_capital.png", 140.0, (60, -560, 330), (0, 0, 8), 40, 1900, 780)
    band(ESCORT,  "navy_escort.png",   78.0, (40, -330, 195), (0, 0, 6), 40, 1900, 760)
    band(SMALL,   "navy_small.png",    42.0, (20, -175, 100), (0, 0, 3), 42, 1900, 720)
    band(SUBS,    "navy_subs.png",     46.0, (25, -215, 118), (0, 0, 2), 42, 1900, 720)
    print("rendering navy plans...")
    #                        spacing   ortho span
    #                        spacing on Y   ortho span on X   zoom-test height
    plan(CAPITAL, "navy_plan_capital.png",  95.0, 350.0, 1900, 130)
    plan(ESCORT,  "navy_plan_escort.png",   25.0, 200.0, 1900, 110)
    plan(SMALL,   "navy_plan_small.png",    18.0,  80.0, 1900, 130)
    plan(SUBS,    "navy_plan_subs.png",     23.0, 125.0, 1900, 120)
    print("done ->", OUT)
