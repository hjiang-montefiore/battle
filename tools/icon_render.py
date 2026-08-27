"""Render one sidebar icon per unit: the picture on a build card.

    Blender -b --python tools/icon_render.py            # every buildable stem
    Blender -b --python tools/icon_render.py -- mbt_e4_us bld_e4_us_power_plant
    Blender -b --python tools/icon_render.py -- prefix:inf_       # by family

A text-only build sidebar makes a player read six words to find the thing they
already know the shape of. These are the same models the game spawns, lit the
same way and shot from the same three-quarter angle the RTS camera uses, so
the card and the thing on the ground are recognisably one object.

Each icon is framed to its OWN bounding box rather than a shared scale: a
sidebar is a list of names with pictures, not a size comparison, and scaling a
rifle squad against a carrier would leave the squad invisible. Background is
transparent, so the button's own styling shows through.
"""
import bpy, math, os, sys
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gameplay_render as R

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLOCKOUT = os.path.join(ROOT, "art", "blockout")
OUT = os.path.join(ROOT, "art", "icons")
PX = 128


def find_glb(stem):
    for bucket in sorted(os.listdir(BLOCKOUT)):
        d = os.path.join(BLOCKOUT, bucket)
        if not os.path.isdir(d):
            continue
        p = os.path.join(d, stem + "_LOD0.glb")
        if os.path.exists(p):
            return p
    return None


def all_stems():
    seen = set()
    for bucket in sorted(os.listdir(BLOCKOUT)):
        d = os.path.join(BLOCKOUT, bucket)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.endswith("_LOD0.glb"):
                seen.add(f[: -len("_LOD0.glb")])
    # Infantry is a 392-variant matrix and the sidebar shows one row of it.
    # US infantry across every epoch; the other 7 factions share silhouettes.
    return sorted(s for s in seen if not s.startswith("inf_") or "_us_" in s)


def icon(stem, path):
    src = find_glb(stem)
    if src is None:
        return False
    R.reset()
    # No sky: the icon sits on the button, not in a scene.
    bpy.context.scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.30
    R.sun(strength=3.6, elev=46, azim=132)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=src)
    new = [o for o in bpy.data.objects if o not in before]
    meshes = [o for o in new if o.type == "MESH"]
    if not meshes:
        return False
    R.apply_occlusion(meshes)

    # Frame to the model's own extent, measured in world space.
    lo = Vector((1e9, 1e9, 1e9))
    hi = Vector((-1e9, -1e9, -1e9))
    for o in meshes:
        for c in o.bound_box:
            w = o.matrix_world @ Vector(c)
            lo = Vector((min(lo[i], w[i]) for i in range(3)))
            hi = Vector((max(hi[i], w[i]) for i in range(3)))
    centre = (lo + hi) * 0.5
    span = max((hi - lo).x, (hi - lo).y, (hi - lo).z, 0.5)

    # The gameplay three-quarter, normalised: same angle for every card.
    d = span * 1.9
    eye = centre + Vector((d * 0.62, -d * 0.78, d * 0.60))
    R.camera(tuple(eye), tuple(centre), ortho=span * 1.35)

    sc = bpy.context.scene
    sc.render.film_transparent = True
    R.render(path, PX, PX, 40)
    return True


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    # A single "prefix:inf_" argument rather than a long list of names: an
    # argument vector that long does not survive the trip through Blender's
    # own argument handling, and arrives as one string.
    if len(argv) == 1 and argv[0].startswith("prefix:"):
        pre = argv[0][len("prefix:"):]
        stems = [s for s in all_stems() if s.startswith(pre)]
    else:
        stems = argv if argv else all_stems()
    done = failed = 0
    for s in stems:
        p = os.path.join(OUT, s + ".png")
        try:
            if icon(s, p):
                done += 1
            else:
                failed += 1
                print("  no mesh:", s)
        except Exception as exc:                       # noqa: BLE001
            failed += 1
            print("  FAILED", s, exc)
    print(f"{done} icon(s), {failed} skipped -> {OUT}")
