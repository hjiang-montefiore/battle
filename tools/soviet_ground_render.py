"""Soviet/Chinese-lineage ground variants, each beside its US counterpart.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/soviet_ground_render.py

Pairs, left (new variant) against right (the US-lineage baseline the player
must be able to tell it from), plus the existing T-72/ZTZ-99A for the tank
row context. The check is the method note's: BMP = low flat wedge vs the
Bradley; BTR = 8-wheel boat vs the M113 box; 2S3 turret mid-hull vs the
M109's aft box; BM-21 = truck with a flat pack vs the boxy M270; S-300 =
2x2 round tubes vs the Patriot's flat square row; BRDM = small 4-wheel dome
vs the masted Stryker; Shilka = centre quad + dish vs the Gepard's outboard
pair + array; Type 59 = 5-wheel egg dome vs the T-72.
"""
import bpy, glob, math, os, sys
from mathutils import Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gameplay_render as G

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROWS = [
    ["afv_e3_ru_bmp1", "afv_e4_us_ifv", "afv_e2_ru_btr60",
     "afv_e4_us_apc", "rec_e2_ru_brdm2", "rec_e4_us_recon"],
    ["art_e3_ru_2s3", "art_e4_us_sph", "art_e2_ru_bm21",
     "art_e4_us_mlrs", "aad_e3_ru_zsu23", "aad_e4_us_spaag"],
    ["sam_e4_ru_s300tel", "aad_e4_us_longsam", "mbt_e2_cn_type59",
     "mbt_e4_ru_t72", "afv_e6_cn_zbd04", "mbt_e6_cn_ztz99a"],
]
SX, SY = 13.0, 15.0


def place(name, x, y, yaw=30):
    f = glob.glob(os.path.join(ROOT, "art", "blockout", "**", f"{name}_LOD1.glb"),
                  recursive=True)
    if not f:
        print("MISSING", name); return
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f[0])
    new = [o for o in bpy.data.objects if o not in before]
    M = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    for o in new:
        if o.parent is None:
            o.matrix_world = M @ o.matrix_world
        if o.type == "EMPTY":
            o.hide_render = True
    G.apply_occlusion([o for o in new if o.type == "MESH"])


G.reset(); G.sun(); G.ground(size=220)
for r, row in enumerate(ROWS):
    for c, n in enumerate(row):
        place(n, (c - 2.5) * SX, (1.35 - r) * SY)
G.camera((0, -95, 80), (0, 3.0, 1.0), lens=44)
G.render(os.path.join(ROOT, "art", "renders", "soviet_ground.png"), 1800, 860)
