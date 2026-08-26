"""Render the hero models as they would appear in the game.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/gameplay_render.py

Outputs:
    art/renders/gameplay.png   RTS camera, a small engagement on terrain
    art/renders/closeup.png    hero close-up — texture and detail at LOD0
"""
import bpy, glob, math, os
from mathutils import Vector, Matrix

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "renders")
TEX = os.path.join(ROOT, "art", "textures")
R = math.radians


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    w = bpy.data.worlds.new("W"); w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0.42, 0.50, 0.62, 1)     # daylight sky
    bg.inputs[1].default_value = 0.55
    bpy.context.scene.world = w


def sun(strength=3.4, elev=42, azim=140):
    """Key + fill + rim. A single hard sun is the other reason a model reads
    as moulded plastic — real surfaces get sky bounce and ground bounce."""
    bpy.ops.object.light_add(type="SUN", location=(0, 0, 60))
    key = bpy.context.object
    key.data.energy = strength
    key.data.angle = R(2.4)
    key.data.color = (1.0, 0.95, 0.86)
    key.rotation_euler = (R(90 - elev), 0, R(azim))

    bpy.ops.object.light_add(type="SUN", location=(0, 0, 55))
    fill = bpy.context.object
    fill.data.energy = strength * 0.30
    fill.data.angle = R(28)                                 # broad, sky-like
    fill.data.color = (0.72, 0.80, 0.96)
    fill.rotation_euler = (R(90 - 58), 0, R(azim + 160))

    bpy.ops.object.light_add(type="SUN", location=(0, 0, 40))
    rim = bpy.context.object
    rim.data.energy = strength * 0.42
    rim.data.angle = R(6)
    rim.data.color = (1.0, 0.90, 0.78)
    rim.rotation_euler = (R(90 - 16), 0, R(azim + 205))      # low back-light
    return key


def ground(size=140):
    bpy.ops.mesh.primitive_plane_add(size=size, location=(0, 0, 0))
    g = bpy.context.object
    m = bpy.data.materials.new("terrain")
    m.use_nodes = True
    nt = m.node_tree
    b = nt.nodes["Principled BSDF"]
    b.inputs["Roughness"].default_value = 0.95
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(os.path.join(TEX, "terrain.png"), check_existing=True)
    map_ = nt.nodes.new("ShaderNodeMapping")
    coord = nt.nodes.new("ShaderNodeTexCoord")
    map_.inputs["Scale"].default_value = (34, 34, 34)
    nt.links.new(coord.outputs["Generated"], map_.inputs["Vector"])
    nt.links.new(map_.outputs["Vector"], tex.inputs["Vector"])

    # a second sample at a different, non-harmonic scale, mixed by low-frequency
    # noise. One tiled image at a single scale reads as a printed play-mat.
    tex2 = nt.nodes.new("ShaderNodeTexImage")
    tex2.image = tex.image
    map2 = nt.nodes.new("ShaderNodeMapping")
    map2.inputs["Scale"].default_value = (7.3, 7.3, 7.3)
    map2.inputs["Rotation"].default_value = (0, 0, 0.7)
    nt.links.new(coord.outputs["Generated"], map2.inputs["Vector"])
    nt.links.new(map2.outputs["Vector"], tex2.inputs["Vector"])
    nse = nt.nodes.new("ShaderNodeTexNoise")
    nse.inputs["Scale"].default_value = 3.2
    nt.links.new(coord.outputs["Generated"], nse.inputs["Vector"])
    mixn = nt.nodes.new("ShaderNodeMixRGB")
    mixn.blend_type = "MIX"
    nt.links.new(nse.outputs["Fac"], mixn.inputs["Fac"])
    nt.links.new(tex.outputs["Color"], mixn.inputs["Color1"])
    nt.links.new(tex2.outputs["Color"], mixn.inputs["Color2"])
    nt.links.new(mixn.outputs["Color"], b.inputs["Base Color"])
    bump = nt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    nt.links.new(mixn.outputs["Color"], bump.inputs["Height"])
    nt.links.new(bump.outputs["Normal"], b.inputs["Normal"])
    g.data.materials.append(m)
    return g


def apply_occlusion(objs):
    """Multiply the glTF occlusionTexture into base colour for rendering.

    Blender's importer parks occlusion on a disconnected "glTF Material Output"
    group because occlusion is a game-engine convention its own renderer
    ignores. Godot applies it; EEVEE does not. Without this the render is not
    showing what the game will show.
    """
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
            link = next((l for l in nt.links if l.to_socket == grp.inputs["Occlusion"]), None)
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


def place(name, lod, x, y, yaw):
    f = glob.glob(os.path.join(ROOT, "art", "blockout", "**",
                               f"{name}_LOD{lod}.glb"), recursive=True)
    if not f:
        print("MISSING", name); return
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f[0])
    new = [o for o in bpy.data.objects if o not in before]
    M = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(R(yaw), 4, "Z")
    for o in new:
        if o.parent is None:
            o.matrix_world = M @ o.matrix_world
        if o.type == "EMPTY":
            o.hide_render = True
    apply_occlusion([o for o in new if o.type == "MESH"])


def camera(loc, look, lens=52, ortho=None):
    bpy.ops.object.camera_add(location=loc)
    c = bpy.context.object
    c.rotation_euler = (Vector(look) - Vector(loc)).to_track_quat("-Z", "Y").to_euler()
    if ortho:
        c.data.type = "ORTHO"; c.data.ortho_scale = ortho
    else:
        c.data.lens = lens
    bpy.context.scene.camera = c
    return c


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


os.makedirs(OUT, exist_ok=True)

# ── 1. gameplay view: a NATO section advancing on a Russian one ────
print("rendering gameplay view...")
reset(); sun(); ground()
NATO = [("mbt_e4_us_m1_abrams", -11.0, -7.5, 8),
        ("mbt_e4_us_m1_abrams", -2.5, -11.5, 2),
        ("mbt_e4_de_leopard2a6", 6.5, -7.0, -6),
        ("mbt_e4_de_leopard2a6", 15.5, -12.0, -3)]
RU = [("mbt_e4_ru_t72", -12.5, 13.0, 186),
      ("mbt_e4_ru_t72", -3.5, 17.0, 172),
      ("mbt_e4_ru_t72", 6.0, 12.5, 195),
      ("mbt_e4_ru_t72", 15.0, 17.5, 178)]
for n, x, y, a in NATO + RU:
    place(n, 1, x, y, a)
camera((2, -68, 47), (2, 2.5, 1.0), lens=55)
render(os.path.join(OUT, "gameplay.png"), 1600, 900)

# ── 2. close-up: texture and detail at LOD0 ────────────────────────
print("rendering close-up...")
reset(); sun(elev=38, azim=125); ground(size=60)
place("mbt_e4_de_leopard2a6", 0, -9.0, 2.0, 26)
place("mbt_e4_us_m1_abrams", 0, 3.6, -2.0, -14)
place("mbt_e4_ru_t72", 0, 14.5, 3.5, 202)
camera((3.0, -42.0, 15.0), (3.0, 1.0, 1.2), lens=60)
render(os.path.join(OUT, "closeup.png"), 1600, 760, samples=64)
print("done")
