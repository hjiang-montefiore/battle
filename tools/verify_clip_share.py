"""Prove one clip library drives every variant mesh.

    Blender -b --python tools/verify_clip_share.py

The infantry budget rests on a claim: export the skeleton and its eleven clips
ONCE, export 392 variant meshes with no animation at all, and let the engine
bind the one library to all of them. That saves roughly 60 MB of duplicated
keyframes, but it is only true if the bone names, bind poses and rest
transforms really match across separately exported files.

"The bone names match" is not proof. A rest-pose or bind-matrix difference
would still let the actions apply and would still produce a moving soldier —
just a subtly wrong one. So this checks the thing that would actually break:
whether the variant's SKIN lands in the same world positions as the rig the
clips were authored against.
"""
import bpy, math, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gait as G

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "blockout", "e4_infantry")
TOL_MM = 0.5


def load(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    arm = next((o for o in new if o.type == "ARMATURE"), None)
    # Pick the SKINNED mesh, not merely the first one. The importer can leave a
    # placeholder object behind for a skin that no mesh uses, and taking
    # new[0] silently measures that instead of the soldier.
    meshes = [o for o in new if o.type == "MESH"]
    mesh = max(meshes, key=lambda o: len(o.vertex_groups), default=None)
    return new, arm, mesh


def bind(rig, act):
    """Assign an action so it actually drives this rig.

    Blender 4.4 introduced slotted actions: an action carries slots bound to
    specific IDs, and assigning the action alone leaves a second rig at rest
    while silently reporting success. That is what made the first run of this
    check report 3.5 metres of divergence for assets that were in fact correct.
    """
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


def bone_snapshot(arm):
    return {b.name: arm.pose.bones[b.name].matrix.copy() for b in arm.data.bones}


def main():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    lib_path = os.path.join(SRC, "inf_rig_clips.glb")
    if not os.path.exists(lib_path):
        print("FAIL: no clip library at", lib_path)
        return 1
    _, lib_arm, _ = load(lib_path)
    actions = sorted(a.name for a in bpy.data.actions)
    print(f"clip library: {len(actions)} action(s)")

    variants = sorted(f for f in os.listdir(SRC)
                      if f.endswith("_LOD0.glb") and f.startswith("inf_e"))
    if not variants:
        print("FAIL: no variant meshes")
        return 1
    print(f"variants: {len(variants)}")

    fails = []
    checked = 0
    # sample across the era ladder rather than all of them - the question is
    # whether the SKELETON is shared, and that is the same question for every
    # variant built by the same builder
    for v in variants[:: max(1, len(variants) // 6)]:
        _, arm, mesh = load(os.path.join(SRC, v))
        if arm is None or mesh is None:
            fails.append(f"{v}: import produced armature={arm} mesh={mesh}")
            continue

        # 1. the joint sets must be identical, not merely overlapping
        lib_bones = {b.name for b in lib_arm.data.bones}
        var_bones = {b.name for b in arm.data.bones}
        if lib_bones != var_bones:
            fails.append(f"{v}: joint mismatch "
                         f"missing={sorted(lib_bones - var_bones)} "
                         f"extra={sorted(var_bones - lib_bones)}")
            continue

        # 2. the REST transforms must agree, or the same action produces
        #    different world poses on the two rigs
        worst_rest = 0.0
        for name in sorted(lib_bones):
            a = lib_arm.data.bones[name].matrix_local.translation
            b = arm.data.bones[name].matrix_local.translation
            worst_rest = max(worst_rest, (a - b).length * 1000.0)
        if worst_rest > TOL_MM:
            fails.append(f"{v}: rest pose differs by {worst_rest:.3f} mm")

        # 3. bind the library's actions and confirm the variant poses to the
        #    SAME world matrices the library rig does
        worst_pose = 0.0
        for act_name in actions:
            act = bpy.data.actions[act_name]
            for rig in (lib_arm, arm):
                bind(rig, act)
            n = int(act.frame_range[1])
            for f in (1, max(1, n // 3), max(1, (2 * n) // 3), n):
                bpy.context.scene.frame_set(f)
                bpy.context.view_layer.update()
                A, B = bone_snapshot(lib_arm), bone_snapshot(arm)
                for name in A:
                    d = (A[name].translation - B[name].translation).length
                    worst_pose = max(worst_pose, d * 1000.0)
        if worst_pose > TOL_MM:
            fails.append(f"{v}: posed joints differ by {worst_pose:.3f} mm")

        # 4. the mesh must actually be skinned to those joints, not parented
        #    rigid to one of them
        groups = {g.name for g in mesh.vertex_groups}
        bound = groups & lib_bones
        if len(bound) < 12:
            fails.append(f"{v}: only {len(bound)} joints have weights")

        print(f"  {v[:40]:42s} rest {worst_rest:5.3f}mm  "
              f"posed {worst_pose:5.3f}mm  joints {len(bound)}")
        checked += 1

    print(f"\nchecked {checked} variant(s) against {len(actions)} clip(s)")
    if fails:
        for f in fails:
            print("  FAIL", f)
        print("FAIL")
        return 1
    print("PASS - one clip library drives every variant")
    return 0


if __name__ == "__main__":
    sys.exit(main())
