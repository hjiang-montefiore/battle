"""Side-by-side silhouette comparison of the three hero models.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/hero_silhouette.py

Top row  : pure SIDE view — where the profile differences live.
Bottom   : RTS three-quarter at gameplay zoom — the actual gate.
"""
import bpy, glob, math, os
from mathutils import Vector, Matrix

ROOT = "/Users/hjiang/Desktop/battle"
OUT = os.path.join(ROOT, "art", "silhouettes")
HEROES = ["mbt_e4_us_m1_abrams", "mbt_e4_ru_t72", "mbt_e4_de_leopard2a6"]
LABELS = ["M1A2 ABRAMS", "T-72", "LEOPARD 2A6"]
SX = 13.8


def flat_black():
    m = bpy.data.materials.new("SIL")
    m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = (0.05, 0.05, 0.07, 1)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o.inputs[0])
    return m


def scene(elev, yaw, labels):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    w = bpy.data.worlds.new("W"); w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (0.96, 0.96, 0.95, 1)
    bpy.context.scene.world = w
    mat = flat_black()

    for i, name in enumerate(HEROES):
        f = glob.glob(os.path.join(ROOT, "art", "blockout", "**", f"{name}_LOD1.glb"),
                      recursive=True)
        if not f:
            print("MISSING", name); continue
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=f[0])
        new = [o for o in bpy.data.objects if o not in before]
        x = (i - 1) * SX
        M = Matrix.Translation((x, 0, 0)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
        for o in new:
            if o.parent is None:
                o.matrix_world = M @ o.matrix_world
            if o.type == "EMPTY":
                o.hide_render = True
            if o.type == "MESH":
                o.data.materials.clear(); o.data.materials.append(mat)

    el = math.radians(elev)
    d = Vector((0, -math.cos(el), math.sin(el)))
    centre = Vector((0, 0, 1.15))
    bpy.ops.object.camera_add(location=centre + d * 240)
    cam = bpy.context.object
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = 3 * SX * 1.02
    bpy.context.scene.camera = cam

    if labels:
        for i, txt in enumerate(LABELS):
            bpy.ops.object.text_add(location=((i - 1) * SX, 0.0, -1.55))
            t = bpy.context.object
            t.data.body = txt; t.data.size = 0.86; t.data.align_x = "CENTER"
            t.rotation_euler = cam.rotation_euler
            t.data.materials.append(flat_black())
    return cam


def render(path, w, h):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.eevee.taa_render_samples = 32
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("  wrote", os.path.relpath(path, ROOT))


os.makedirs(OUT, exist_ok=True)
scene(elev=2.0, yaw=90.0, labels=True)   # yaw 90 puts the long axis across screen
render(os.path.join(OUT, "heroes_side.png"), 1700, 520)
scene(elev=34.0, yaw=40.0, labels=False)
render(os.path.join(OUT, "heroes_gameplay.png"), 900, 300)
print("done")
