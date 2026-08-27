"""Texture-pass proof renders: one unit close up + at gameplay distance.

    Blender -b --python tools/texture_proof_render.py -- <unit> [<unit> ...]

Writes art/renders/texproof_<unit>_close.png and _game.png.
Lighting/ground/camera logic mirrors tools/gameplay_render.py (which renders
at import and so cannot be imported).
"""
import bpy, glob, math, os, sys
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "renders")
TEX = os.path.join(ROOT, "art", "textures")
R = math.radians


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    w = bpy.data.worlds.new("W"); w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.42, 0.50, 0.62, 1)
    bg.inputs[1].default_value = 0.55
    bpy.context.scene.world = w


def sun(strength=3.4, elev=42, azim=140):
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 60))
    key = bpy.context.object
    key.data.energy = strength; key.data.angle = R(2.4)
    key.data.color = (1.0, 0.95, 0.86)
    key.rotation_euler = (R(90 - elev), 0, R(azim))
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 55))
    fill = bpy.context.object
    fill.data.energy = strength * 0.30; fill.data.angle = R(28)
    fill.data.color = (0.72, 0.80, 0.96)
    fill.rotation_euler = (R(90 - 58), 0, R(azim + 160))
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 40))
    rim = bpy.context.object
    rim.data.energy = strength * 0.42; rim.data.angle = R(6)
    rim.data.color = (1.0, 0.90, 0.78)
    rim.rotation_euler = (R(90 - 16), 0, R(azim + 205))


def ground(size=140):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    g = bpy.context.object
    m = bpy.data.materials.new("terrain"); m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.95
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(TEX, "terrain.png"),
                                     check_existing=True)
    map_ = nt.nodes.new("ShaderNodeMapping")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    map_.inputs["Scale"].default_value = (size / 4, size / 4, size / 4)
    nt.links.new(coord.outputs["Generated"], map_.inputs["Vector"])
    nt.links.new(map_.outputs["Vector"], tex.inputs["Vector"])
    nt.links.new(tex.outputs["Color"], b.inputs["Base Color"])
    g.data.materials.append(m)


def water(size=800):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    g = bpy.context.object
    m = bpy.data.materials.new("sea"); m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (0.06, 0.11, 0.15, 1)
    b.inputs["Roughness"].default_value = 0.18
    g.data.materials.append(m)


def apply_occlusion(objs):
    done = set()
    for o in objs:
        for slot in getattr(o, "material_slots", []):
            m = slot.material
            if m is None or m.name in done or not m.use_nodes:
                continue
            done.add(m.name)
            nt = m.node_tree
            grp = next((n for n in nt.nodes if n.type == "GROUP" and n.node_tree
                        and "glTF" in n.node_tree.name), None)
            if grp is None or "Occlusion" not in grp.inputs:
                continue
            link = next((l for l in nt.links
                         if l.to_socket == grp.inputs["Occlusion"]), None)
            if link is None:
                continue
            ao_out = link.from_socket
            bsdf = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
            if bsdf is None:
                continue
            base = bsdf.inputs["Base Color"]
            mix = nt.nodes.new("ShaderNodeMixRGB")
            mix.blend_type = "MULTIPLY"
            mix.inputs["Fac"].default_value = 1.0
            if base.is_linked:
                src = base.links[0].from_socket
                nt.links.new(src, mix.inputs["Color1"])
            else:
                mix.inputs["Color1"].default_value = base.default_value
            nt.links.new(ao_out, mix.inputs["Color2"])
            nt.links.new(mix.outputs["Color"], base)


def place(name, lod, x=0.0, y=0.0, yaw=0.0, z=0.0):
    f = glob.glob(os.path.join(ROOT, "art", "blockout", "**",
                               f"{name}_LOD{lod}.glb"), recursive=True)
    if not f:
        print("MISSING", name); return 0.0
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f[0])
    new = [o for o in bpy.data.objects if o not in before]
    M = Matrix.Translation((x, y, z)) @ Matrix.Rotation(R(yaw), 4, "Z")
    ext = 1.0
    for o in new:
        if o.parent is None:
            o.matrix_world = M @ o.matrix_world
        if o.type == "EMPTY":
            o.hide_render = True
        if o.type == "MESH":
            xs = [(o.matrix_world @ Vector(c)) for c in o.bound_box]
            ext = max(ext, max(abs(v.x) for v in xs), max(abs(v.y) for v in xs))
    apply_occlusion([o for o in new if o.type == "MESH"])
    return ext


def camera(loc, look, lens=52):
    bpy.ops.object.camera_add(location=loc)
    c = bpy.context.object
    c.rotation_euler = (Vector(look) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    c.data.lens = lens
    c.data.clip_end = 5000
    bpy.context.scene.camera = c


def render(path, w, h, samples=48):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.eevee.taa_render_samples = samples
    try:
        sc.eevee.use_raytracing = True
        sc.eevee.ray_tracing_options.use_denoise = True
        sc.eevee.use_shadow_jitter_viewport = True
    except Exception:
        pass
    try:
        sc.eevee.use_fast_gi = True
    except Exception:
        pass
    sc.view_settings.view_transform = "AgX"
    sc.view_settings.look = "AgX - Base Contrast"
    sc.render.resolution_x, sc.render.resolution_y = w, h
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)
    print("  wrote", os.path.relpath(path, ROOT))


def proof(unit):
    naval = unit.startswith(("nav_", "sub_"))
    air = unit.split("_")[0] in ("air", "aew", "ewa", "tkr", "isr", "mpa",
                                 "hel", "uav")
    os.makedirs(OUT, exist_ok=True)

    # ── close-up, LOD0 ───────────────────────────────────────────────
    reset(); sun(elev=38, azim=125)
    if naval:
        water()
    else:
        ground()
    z = 30.0 if air else 0.0
    ext = place(unit, 0, 0, 0, 24, z=z)
    d = ext * 2.3
    camera((d * 0.95, -d * 0.80, z + ext * 0.55), (0, 0, z + ext * 0.12), lens=60)
    render(os.path.join(OUT, f"texproof_{unit}_close.png"), 1600, 900,
           samples=64)

    # ── gameplay distance, LOD1 — the unit at RTS zoom ───────────────
    reset(); sun()
    if naval:
        water()
    else:
        ground(size=400)
    ext = place(unit, 1, 0, 0, 8, z=z)
    for k, (dx, dy) in enumerate([(-3.2, -1.6), (3.0, 1.4), (-1.4, 3.0)]):
        place(unit, 1, dx * ext, dy * ext, 8 + k * 17, z=z)
    d = ext * 9.0
    camera((0.15 * d, -d, 0.75 * d + z), (0, 0.05 * d, z + 1), lens=55)
    render(os.path.join(OUT, f"texproof_{unit}_game.png"), 1600, 900)


argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
for u in argv or ["mbt_e4_us_m1_abrams"]:
    print("proof render:", u)
    proof(u)
print("done")
