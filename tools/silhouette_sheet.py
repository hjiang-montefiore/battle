"""Render every blockout as a flat black silhouette on white — the readability
gate from docs/07-art-pipeline.md.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/silhouette_sheet.py

Two outputs:
    art/silhouettes/contact_sheet.png   inspection size — compare shapes
    art/silhouettes/gameplay_zoom.png   actual play scale — the real test

The rule being tested: "If two units are confusable in silhouette, one of them
is wrong regardless of how good the model is."

Camera is straight-on (azimuth 0) so the grid stays square to the frame; each
UNIT is yawed instead, which gives the three-quarter RTS presentation without
skewing the layout.

NOTE ON AXES: our GLBs are glTF-native (Y up, -Z forward), but Blender is Z up,
-Y forward, and the importer converts on load. So everything in THIS file works
in Blender's convention: X right, Y depth, Z up, yaw about Z.
"""
import bpy, glob, math, os
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "silhouettes")
COLS, SX, SZ = 5, 11.5, 18.0
ELEV, UNIT_YAW = 34.0, 40.0

ORDER = [
    "mbt_e1_western_hero", "mbt_e1_soviet_hero",
    "mbt_e4_western_hero", "mbt_e4_us", "mbt_e4_uk",
    "mbt_e4_de", "mbt_e4_fr",
    "mbt_e4_soviet_hero", "mbt_e4_ru", "mbt_e4_cn",
]


def flat_black():
    """Emission-black material — renders pure black regardless of lighting."""
    m = bpy.data.materials.new("SIL")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = (0.05, 0.05, 0.07, 1)
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o.inputs[0])
    return m


def white_world():
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.96, 0.96, 0.95, 1)
    bg.inputs[1].default_value = 1.0
    bpy.context.scene.world = w


def place(name, col, row, mat):
    hits = glob.glob(os.path.join(ROOT, "art", "blockout", "**", f"{name}_LOD1.glb"),
                     recursive=True)
    if not hits:
        print(f"  MISSING {name}")
        return None
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=hits[0])
    new = [o for o in bpy.data.objects if o not in before]
    x = (col - (COLS - 1) / 2) * SX
    y = row * SZ
    # Blender is Z-up: grid runs in X (across) and Y (depth); yaw is about Z.
    # Compose into matrix_world — setting rotation_euler directly clobbers the
    # glTF importer's axis conversion on the root node.
    M = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(math.radians(UNIT_YAW), 4, "Z")
    for o in new:
        if o.parent is None:
            o.matrix_world = M @ o.matrix_world
        if o.type == "EMPTY":
            o.hide_render = True
        if o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(mat)
    return (x, y)


def label(text, x, y, cam_rot, size=0.78):
    bpy.ops.object.text_add(location=(x, y - 6.6, 0.05))
    t = bpy.context.object
    t.data.body = text
    t.data.size = size
    t.data.align_x = "CENTER"
    t.rotation_euler = cam_rot          # billboard toward the camera
    m = flat_black()
    t.data.materials.append(m)


def aim_camera(rows, aspect):
    el = math.radians(ELEV)
    d = Vector((0, -math.cos(el), math.sin(el)))          # Z-up: back and above
    centre = Vector((0, (rows - 1) * SZ / 2, 1.2))
    bpy.ops.object.camera_add(location=centre + d * 220)
    cam = bpy.context.object
    cam.rotation_euler = (centre - cam.location).to_track_quat("-Z", "Y").to_euler()
    cam.data.type = "ORTHO"
    span_x = COLS * SX
    # screen-vertical = depth foreshortened by sin(el), plus height by cos(el)
    span_v = (rows - 1) * SZ * math.sin(el) + 9.0 * math.sin(el) + 3.2 * math.cos(el) + 5.0
    cam.data.ortho_scale = max(span_x, span_v * aspect) * 1.06
    bpy.context.scene.camera = cam
    return cam


def render(path, w, h, note):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.eevee.taa_render_samples = 32
    sc.render.film_transparent = False
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print(f"  wrote {os.path.relpath(path, ROOT)}  {w}x{h} {note}")


def build(with_labels, aspect):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    white_world()
    mat = flat_black()
    rows = (len(ORDER) + COLS - 1) // COLS
    cam = aim_camera(rows, aspect)
    pending = []
    for i, name in enumerate(ORDER):
        pos = place(name, i % COLS, i // COLS, mat)
        if pos and with_labels:
            pending.append((name.replace("mbt_", "").replace("_hero", " HERO"), pos))
    for text, (x, y) in pending:
        label(text, x, y, cam.rotation_euler)


os.makedirs(OUT, exist_ok=True)
print("rendering silhouette contact sheet...")
build(True, 1800 / 900)
render(os.path.join(OUT, "contact_sheet.png"), 1800, 900, "(inspection)")

print("rendering at gameplay zoom...")
build(False, 620 / 310)
render(os.path.join(OUT, "gameplay_zoom.png"), 620, 310, "(actual play scale)")
print("done")
