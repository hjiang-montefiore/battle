"""The one check tools/structure_render.py cannot make: THE WATERLINE.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/naval_waterline_render.py

    art/renders/structures_naval_coastal.png       52 deg game camera, with sea
    art/renders/structures_naval_coastal_plan.png  orthographic plan
    art/renders/structures_naval_coastal_48.png    48 px per cell

naval_yard and coastal_battery are the only two structures placed AT the water,
and navy_models.py fixes the waterline at z = 0. The shared structure sheet
renders every role on dry terrain, which is right for the other seventeen and
useless for these two: it cannot show whether the yard's basin surface and a
ship's hull agree about where the sea is. So this sheet lays a plane at exactly
z = 0 for the sea and berths a missile boat in the basin, and the answer is
read off the picture rather than asserted.

The gameplay_render import is deliberately NOT a plain `import`: that module
runs its own two renders at the bottom of the file, so importing it costs about
four minutes and overwrites art/renders/gameplay.png and closeup.png as a side
effect of borrowing its helpers (army_render.py and structure_render.py both
pay this). The source is cut at its os.makedirs line, which is exactly where
the helpers stop and the script starts.
"""
import bpy, glob, math, os, sys, types
from mathutils import Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
OUT = os.path.join(ROOT, "art", "renders")
R = math.radians
ELEV = 52.0

_gp = os.path.join(HERE, "gameplay_render.py")
_src = open(_gp).read()
_src = _src[:_src.index("os.makedirs(OUT, exist_ok=True)")]
G = types.ModuleType("gameplay_render_helpers")
G.__file__ = _gp
exec(compile(_src, _gp, "exec"), G.__dict__)


def place(name, x, y, lod=1, yaw=0.0):
    f = sorted(glob.glob(os.path.join(ROOT, "art", "blockout", "**",
                                      f"{name}_LOD{lod}.glb"), recursive=True))
    if not f:
        print("MISSING", name)
        return
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f[0])
    new = [o for o in bpy.data.objects if o not in before]
    M = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(R(yaw), 4, "Z")
    for o in new:
        if o.parent is None:
            o.matrix_world = M @ o.matrix_world
        if o.type == "EMPTY":
            o.hide_render = True
    G.apply_occlusion([o for o in new if o.type == "MESH"])


def sea(y0, size=520.0):
    """Water at EXACTLY z = 0 - navy_models' waterline, nothing rounded."""
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, y0 + size / 2, 0.0))
    o = bpy.context.object
    m = bpy.data.materials.new("sea")
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    # kept far from the team blue so the ownership band cannot be mistaken for
    # water in the sheet - the first cut had both at a similar blue
    b.inputs["Base Color"].default_value = (0.008, 0.016, 0.024, 1)
    b.inputs["Roughness"].default_value = 0.14
    o.data.materials.append(m)


def build_scene(with_ships):
    G.reset(); G.sun(elev=44, azim=138); G.ground(size=320)
    sea(20.0)
    place("bld_e1_us_naval_yard", 0.0, 0.0)
    place("bld_e2_us_coastal_battery", 46.0, -2.0)
    if with_ships:
        # 9.2 m beam inside a 10 m basin; 60 m of hull running out to sea. A
        # 10 x 26 m building dock does not enclose a 60 m hull and is not meant
        # to - it is a fitting-out berth, and what is being checked here is the
        # HEIGHT of the hull against the quay, not the length.
        place("nav_e2_us_missileboat", 0.0, 22.0, yaw=180)
        place("mbt_e4_us_m1_abrams", -26.0, -21.0, yaw=28)   # scale reference
        place("afv_e4_us_apc", -21.0, -25.5, yaw=20)


os.makedirs(OUT, exist_ok=True)

print("rendering naval-coastal at the game camera...")
build_scene(True)
d, e = 132.0, R(ELEV)
G.camera((22.0, -d * math.cos(e), d * math.sin(e)), (22.0, 0.0, 5.0), lens=48)
G.render(os.path.join(OUT, "structures_naval_coastal.png"), 1700, 950)

# Plan and 48 px go without the ships: the ships are the waterline evidence,
# and in plan they would sit on top of the thing being judged.
print("rendering naval-coastal plan and 48 px...")
build_scene(False)
SPAN = 92.0                       # 36 m cell + 22 m cell + gap, with margin
G.camera((22.0, 0.0, 180.0), (22.0, 0.0, 0.0), ortho=SPAN)
G.render(os.path.join(OUT, "structures_naval_coastal_plan.png"), 1400, 700)
px = int(round(48.0 * SPAN / 36.0))          # 36 m naval_yard cell -> 48 px
G.render(os.path.join(OUT, "structures_naval_coastal_48.png"), px, px // 2,
         samples=32)
print(f"  48 px sheet is {px} x {px // 2}; naval_yard cell = 48 px, "
      f"coastal_battery cell = {48.0 * 22.0 / 36.0:.0f} px")
print("done")
