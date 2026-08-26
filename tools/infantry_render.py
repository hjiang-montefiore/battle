"""Render infantry, posed from the shared clip library.

    Blender -b --python tools/infantry_render.py
    Blender -b --python tools/infantry_render.py -- --clip walk --frame 9

The variants carry no animation of their own — that is the whole point of the
split — so anything that renders them has to bind the library first, exactly as
the engine does. Rendering the bind pose instead shows a soldier holding its
rifle at a steep angle, which is correct for a bind pose and useless for
judging whether the art works.
"""
import bpy, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gameplay_render as R

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "blockout", "e4_infantry")
OUT = os.path.join(ROOT, "art", "renders")
ROLES = ["rifle", "at", "manpads", "recon", "engineer", "sf", "mortar"]
FACTIONS = ["us", "uk", "de", "fr", "cn", "ru", "tw", "kp"]


def load_clips():
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=os.path.join(SRC, "inf_rig_clips.glb"))
    for o in [o for o in bpy.data.objects if o not in before]:
        bpy.data.objects.remove(o, do_unlink=True)
    return {a.name.split("|")[-1]: a for a in bpy.data.actions}


def bind(rig, act):
    """Blender 4.4 slotted actions: assigning the action alone leaves a second
    rig at rest while silently reporting success. The slot has to be bound."""
    if rig.animation_data is None:
        rig.animation_data_create()
    ad = rig.animation_data
    for tr in list(ad.nla_tracks):
        ad.nla_tracks.remove(tr)
    ad.action = act
    if hasattr(ad, "action_slot"):
        cand = list(getattr(ad, "action_suitable_slots", []) or act.slots)
        if cand:
            ad.action_slot = cand[0]


def place(name, pos=(0.0, 0.0), yaw=0.0, lod=0, act=None, frame=1):
    path = os.path.join(SRC, f"{name}_LOD{lod}.glb")
    if not os.path.exists(path):
        return None
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    # glTF exports a skinned mesh as a SIBLING of the skeleton, not a child, so
    # every parentless object has to move, not just the first one found
    for o in new:
        if o.parent is None:
            o.location = (pos[0], pos[1], 0.0)
            o.rotation_euler = (0, 0, math.radians(yaw))
    arm = next((o for o in new if o.type == "ARMATURE"), None)
    if arm is not None and act is not None:
        bind(arm, act)
    R.apply_occlusion([o for o in new if o.type == "MESH"])
    return new


def strip(names, out, clip, frame, cam, look, lens, w, h, yaw=0.0,
          spread=1.05, axis="y"):
    acts = load_clips()
    act = acts.get(clip)
    R.reset(); R.sun(); R.ground(48)
    acts = load_clips()
    act = acts.get(clip)
    n = len(names)
    for i, nm in enumerate(names):
        d = (i - (n - 1) / 2.0) * spread
        pos = (0.0, d) if axis == "y" else (d, 0.0)
        place(nm, pos, yaw, act=act, frame=frame)
    bpy.context.scene.frame_set(frame)
    R.camera(cam, look, lens=lens)
    R.render(os.path.join(OUT, out), w, h, 52)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    clip = argv[argv.index("--clip") + 1] if "--clip" in argv else "walk"
    frame = int(argv[argv.index("--frame") + 1]) if "--frame" in argv else 9

    print(f"rendering infantry posed on '{clip}' frame {frame}...")
    # the epoch ladder, side on: the view that judges the outline
    strip([f"inf_e{e}_us_rifle" for e in range(1, 8)], "inf_era_ladder.png",
          clip, frame, (9.0, -5.6, 2.30), (0, 0, 0.95), 38, 1680, 620,
          yaw=148, spread=1.45)
    # the seven roles at one epoch: role is the strongest axis at RTS zoom
    strip([f"inf_e6_us_{r}" for r in ROLES], "inf_roles.png",
          clip, frame, (9.4, -5.8, 2.40), (0, 0, 0.95), 34, 1680, 620,
          yaw=148, spread=1.60)
    # the eight factions at one epoch: mostly a colour test
    strip([f"inf_e6_{f}_rifle" for f in FACTIONS], "inf_factions.png",
          clip, frame, (10.0, -6.2, 2.45), (0, 0, 0.95), 34, 1760, 600,
          yaw=148, spread=1.45)
    # and the epoch ladder at gameplay distance, which is what actually decides
    strip([f"inf_e{e}_us_rifle" for e in range(1, 8)], "inf_era_top.png",
          clip, frame, (0.0, -3.4, 6.4), (0, 0, 0.9), 50, 1400, 500,
          yaw=200, spread=0.85, axis="x")
    print("done ->", OUT)
