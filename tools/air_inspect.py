"""Top and side view of a single aircraft, orthographic, for shape checking."""
import bpy, glob, math, os, sys
from mathutils import Vector, Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gameplay_render as G

ROOT = "/Users/hjiang/Desktop/battle"
NAME = os.environ.get("AC", "air_e4_us_superiority")


def load(x, yaw, pitch=0.0):
    f = glob.glob(os.path.join(ROOT, "art", "blockout", "**", f"{NAME}_LOD0.glb"),
                  recursive=True)[0]
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f)
    new = [o for o in bpy.data.objects if o not in before]
    M = (Matrix.Translation((x, 0, 8)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
         @ Matrix.Rotation(math.radians(pitch), 4, "X"))
    for o in new:
        if o.parent is None:
            o.matrix_world = M @ o.matrix_world
        if o.type == "EMPTY":
            o.hide_render = True
    G.apply_occlusion([o for o in new if o.type == "MESH"])


G.reset(); G.sun(elev=58); G.ground(size=200)
load(-16, 0)          # top view
load(16, 90)          # side view (yawed 90 so the profile faces the camera)
bpy.ops.object.camera_add(location=(0, 0, 90))
cam = bpy.context.object
cam.rotation_euler = (0, 0, 0)
cam.data.type = "ORTHO"
cam.data.ortho_scale = 62
bpy.context.scene.camera = cam
G.render(os.path.join(ROOT, "art", "renders", "air_inspect.png"), 1600, 800)
