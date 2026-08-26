"""Render the 19 structures from the camera that actually judges them.

    Blender -b --python tools/structure_render.py

Buildings are judged from the fixed three-quarter overhead RTS camera, where
the roof is most of what you see and is the only surface never occluded. A hero
shot from ground level flatters a building and tells you nothing about whether
a player can pick it out of a base.
"""
import bpy, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gameplay_render as R

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "blockout", "e4_structures")
OUT = os.path.join(ROOT, "art", "renders")


def units():
    out = []
    for f in sorted(os.listdir(SRC)):
        if f.endswith("_LOD0.glb"):
            out.append(f[:-len("_LOD0.glb")])
    return out


def place(name, x, z):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, name + "_LOD0.glb"))
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.parent is None:
            o.location = (x, z, 0.0)
    R.apply_occlusion([o for o in new if o.type == "MESH"])


def sheet(names, out, cols, pitch, cam, look, lens, w, h):
    R.reset()
    R.sun(strength=3.3, elev=44, azim=136)
    R.ground(560)
    for i, n in enumerate(names):
        cx = (i % cols - (cols - 1) / 2.0) * pitch
        cz = ((i // cols) - ((len(names) - 1) // cols) / 2.0) * pitch
        place(n, cx, cz)
    R.camera(cam, look, lens=lens)
    R.render(os.path.join(OUT, out), w, h, 48)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    u = units()
    print(f"rendering {len(u)} structures...")
    # gameplay three-quarter: the view a player actually has
    sheet(u, "structures.png", 5, 78.0,
          (185, -215, 168), (0, 0, 6), 40, 1900, 1080)
    # straight down: the harshest test, and where confusable pairs show up
    sheet(u, "structures_top.png", 5, 78.0,
          (0, 0.01, 340), (0, 0, 0), 42, 1500, 1200)
    print("done ->", OUT)
