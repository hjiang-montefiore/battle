"""Render the support fleet alongside an MBT for scale."""
import bpy, glob, math, os, sys
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gameplay_render as G   # reuse reset/sun/ground/camera/render

ROOT = "/Users/hjiang/Desktop/battle"
ROW1 = [("mbt_e4_us_m1_abrams", "MBT"), ("afv_e4_us_ifv", "IFV"),
        ("rec_e4_us_recon", "RECON"), ("art_e4_us_sph", "SPH")]
ROW2 = [("art_e4_us_mlrs", "MLRS"), ("rad_e4_us_search", "SEARCH RADAR"),
        ("rad_e4_us_illuminator", "ILLUMINATOR"), ("sam_e4_us_launcher", "SAM"),
        ("log_e4_us_fueltruck", "FUEL TRUCK")]


def place(name, x, y, yaw=32):
    f = glob.glob(os.path.join(ROOT, "art", "blockout", "**", f"{name}_LOD1.glb"),
                  recursive=True)
    if not f:
        print("MISSING", name); return
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f[0])
    M = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    for o in bpy.data.objects:
        if o in before:
            continue
        if o.parent is None:
            o.matrix_world = M @ o.matrix_world
        if o.type == "EMPTY":
            o.hide_render = True


G.reset(); G.sun(); G.ground(size=200)
SX = 11.5
for i, (n, _) in enumerate(ROW1):
    place(n, (i - 1.5) * SX, 9.0)
for i, (n, _) in enumerate(ROW2):
    place(n, (i - 2.0) * SX, -9.0)
G.camera((0, -74, 50), (0, 0, 1.0), lens=42)
os.makedirs(os.path.join(ROOT, "art", "renders"), exist_ok=True)
G.render(os.path.join(ROOT, "art", "renders", "fleet.png"), 1800, 900)
print("labels row1:", [l for _, l in ROW1])
print("labels row2:", [l for _, l in ROW2])
