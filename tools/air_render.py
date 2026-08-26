"""Air roster lineup, grouped by size class.

Spans run from a 3 m loitering munition to a 56.4 m B-52, so a single grid
pitch cannot work — each row gets its own spacing from the widest aircraft in
it. Camera is steep because an aircraft is identified by PLANFORM.
"""
import bpy, glob, math, os, sys
from mathutils import Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gameplay_render as G

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# (row spacing, row Y, [roles])
ROWS = [
    (24.0,  105.0, ["air_e1_us_interceptor", "air_e4_us_superiority",
                    "air_e4_us_multirole", "air_e4_us_strike",
                    "air_e1_us_cas", "air_e4_us_stealth"]),
    (24.0,   62.0, ["air_e2_us_sead", "ewa_e2_us_electronic",
                    "hel_e3_us_attack", "hel_e2_us_transport",
                    "hel_e2_us_asw", "aew_e3_uk_aewhelo"]),
    (44.0,   12.0, ["uav_e7_us_loiter", "uav_e6_us_armed",
                    "uav_e5_us_recon", "isr_e1_us_recon"]),
    (68.0,  -68.0, ["mpa_e1_us_maritime", "tkr_e2_us_tanker",
                    "aew_e3_us_aewc", "air_e1_us_bomber",
                    "air_e4_us_stealthbomber"]),
]


def place(name, x, y):
    f = glob.glob(os.path.join(ROOT, "art", "blockout", "**", f"{name}_LOD1.glb"),
                  recursive=True)
    if not f:
        print("MISSING", name)
        return
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f[0])
    new = [o for o in bpy.data.objects if o not in before]
    M = Matrix.Translation((x, y, 6.0))
    for o in new:
        if o.parent is None:
            o.matrix_world = M @ o.matrix_world
        if o.type == "EMPTY":
            o.hide_render = True
    G.apply_occlusion([o for o in new if o.type == "MESH"])


G.reset()
G.sun(elev=64, azim=150)
G.ground(size=900)
for sx, ry, row in ROWS:
    n = len(row)
    for c, name in enumerate(row):
        place(name, (c - (n - 1) / 2.0) * sx, ry)
G.camera((0, -300, 330), (0, 16, 6), lens=40)
G.render(os.path.join(ROOT, "art", "renders", "air.png"), 1900, 1150)
