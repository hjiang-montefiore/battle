"""Lineup of every ground role, for the cross-role silhouette check."""
import bpy, glob, math, os, sys
from mathutils import Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gameplay_render as G

ROOT = "/Users/hjiang/Desktop/battle"
ROWS = [
    ["mbt_e4_us_m1_abrams", "afv_e4_us_tankdestroyer", "afv_e4_us_ifv",
     "afv_e4_us_apc", "afv_e4_us_atgm", "rec_e4_us_recon"],
    ["art_e4_us_sph", "art_e4_us_mlrs", "art_e4_us_towed",
     "art_e4_us_mortar", "msl_e4_us_ballistic", "msl_e4_us_coastal"],
    ["aad_e4_us_spaag", "aad_e4_us_shorad", "aad_e4_us_longsam",
     "sam_e4_us_launcher", "rad_e4_us_search", "rad_e4_us_illuminator"],
    ["rad_e4_us_counterbty", "ewj_e4_us_jammer", "cmd_e4_us_command",
     "log_e4_us_fueltruck", "log_e4_us_ammotruck", "eng_e4_us_engineer"],
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


G.reset(); G.sun(); G.ground(size=260)
for r, row in enumerate(ROWS):
    for c, n in enumerate(row):
        place(n, (c - 2.5) * SX, (1.5 - r) * SY)
G.camera((0, -96, 74), (0, 0, 1.0), lens=46)
G.render(os.path.join(ROOT, "art", "renders", "army.png"), 1800, 1000)
