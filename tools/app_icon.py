"""Render the application icon from the game's own model.

    Blender -b --python tools/app_icon.py

An icon drawn separately from the game always drifts from it. This renders the
hero M1 -- the same GLB the game spawns, with the same fattened gun the player
sees -- at a low three-quarter angle, which is the view that gives a tank its
most recognisable silhouette: hull length, turret mass and the gun breaking the
outline. Icons are read at 32 px more often than at 1024, so the composition is
built around the SHAPE holding up when it is thumbnail-sized.
"""
import bpy, math, os, sys
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gameplay_render as R

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "blockout")
OUT = os.path.join(ROOT, "art", "icons", "app_icon.png")
PX = 1024


def find(stem):
    for bucket in sorted(os.listdir(SRC)):
        d = os.path.join(SRC, bucket)
        p = os.path.join(d, stem + "_LOD0.glb")
        if os.path.isdir(d) and os.path.exists(p):
            return p
    return None


def backdrop():
    """A dark field with a warm pool behind the subject.

    EMISSIVE, not lit. The first version used a Principled surface and the key
    light simply washed it to a flat olive -- the backdrop rendered at nearly
    the same value as the tank and the silhouette had nothing to sit against,
    which is precisely the thing an icon cannot afford at 32 px.
    """
    bpy.ops.mesh.primitive_plane_add(size=600, location=(0, 90, 0))
    p = bpy.context.object
    p.rotation_euler = (math.radians(90), 0, 0)
    m = bpy.data.materials.new("bg")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes["Principled BSDF"])
    out = nt.nodes["Material Output"]
    emit = nt.nodes.new("ShaderNodeEmission")
    grad = nt.nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "SPHERICAL"
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    # A SPHERICAL gradient reads 1 at its centre and 0 at its rim, so the WARM
    # colour belongs on the right of the ramp. Having them the other way round
    # painted the warm pool over the entire backdrop and produced a flat
    # mustard field -- the exact failure the emissive backdrop was meant to fix.
    ramp.color_ramp.elements[0].position = 0.22
    ramp.color_ramp.elements[0].color = (0.017, 0.024, 0.032, 1)  # dark slate
    ramp.color_ramp.elements[1].position = 0.92
    ramp.color_ramp.elements[1].color = (0.34, 0.21, 0.05, 1)     # warm pool
    coord = nt.nodes.new("ShaderNodeTexCoord")
    map_ = nt.nodes.new("ShaderNodeMapping")
    map_.inputs["Scale"].default_value = (1.7, 1.7, 1.7)
    nt.links.new(coord.outputs["Object"], map_.inputs["Vector"])
    nt.links.new(map_.outputs["Vector"], grad.inputs["Vector"])
    nt.links.new(grad.outputs["Color"], ramp.inputs["Fac"])
    nt.links.new(ramp.outputs["Color"], emit.inputs["Color"])
    nt.links.new(emit.outputs["Emission"], out.inputs["Surface"])
    p.data.materials.append(m)


def main():
    src = find("mbt_e4_us_m1_abrams") or find("mbt_e4_us")
    if src is None:
        raise SystemExit("no MBT model found -- run build_all first")
    R.reset()
    bpy.context.scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.18
    backdrop()
    R.sun(strength=4.6, elev=34, azim=118)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=src)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    R.apply_occlusion(meshes)

    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo[i], w[i]) for i in range(3)))
            hi = Vector((max(hi[i], w[i]) for i in range(3)))
    centre = (lo + hi) * 0.5
    span = max((hi - lo).x, (hi - lo).y, (hi - lo).z)

    # Low and close: a top-down view flattens a tank into a rectangle, and the
    # gun -- the one part that says "tank" at 32 px -- disappears into it.
    d = span * 1.02
    eye = centre + Vector((d * 0.92, -d * 1.02, d * 0.42))
    R.camera(tuple(eye), tuple(centre + Vector((0, 0, span * 0.01))), lens=55)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    R.render(OUT, PX, PX, 96)
    print("icon ->", OUT)


if __name__ == "__main__":
    main()
