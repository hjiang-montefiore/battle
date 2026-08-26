"""Measure foot slip on the RIGGED soldier, not on the maths.

    Blender -b --python tools/verify_gait.py

tools/gait.py already reports 0.000 mm of slip, but that is the model checking
itself. It proves the trajectory is right; it proves nothing about whether the
bone conventions that turn that trajectory into euler angles are right. A sign
flip on the knee would still measure zero there while producing a soldier
walking backwards on inverted legs.

So this walks forward kinematics through the actual posed armature — the same
matrices the exporter writes — and asks three questions of the result:

    SLIP        does the weight-bearing point stay put in world space?
    CLEARANCE   does any part of the foot go below the ground?
    ALTERNATION do the two legs actually take turns, or has a sign error
                left them swinging in unison?

The third is the one that catches convention errors that the first two miss.
"""
import bpy, math, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gait as G
import infantry_models as IM

FPS = IM.FPS
TOL_SLIP = 2.0        # mm/frame; below this nothing is visible at any zoom
TOL_SINK = 8.0        # mm below ground before it reads as feet in the dirt


def landmark_world(arm, bone_name, rest_point):
    """Where a point that is fixed to a bone ends up once the bone is posed."""
    bone = arm.data.bones[bone_name]
    pb = arm.pose.bones[bone_name]
    local = bone.matrix_local.inverted() @ Vector(rest_point)
    return arm.matrix_world @ (pb.matrix @ local)


def check(arm, clip, meta):
    scn = bpy.context.scene
    track = next(t for t in arm.animation_data.nla_tracks if t.name == clip)
    for t in arm.animation_data.nla_tracks:
        t.mute = t.name != clip
    n = meta["frames"]
    speed = meta["speed"]
    dt = (meta["stride"] / speed) / n if speed else 0.0

    ankle_rest = {"l": Vector((-G.HIP_X, 0, 0.08)),
                  "r": Vector((G.HIP_X, 0, 0.08))}
    worst_slip = 0.0
    worst_sink = 0.0
    stance = {"l": [], "r": []}

    hist = {"l": [], "r": []}
    for i in range(n + 1):
        scn.frame_set(i + 1)
        for tag in ("l", "r"):
            b = f"foot_{tag}"
            pts = {k: landmark_world(arm, b, ankle_rest[tag] + Vector(v))
                   for k, v in (("heel", G.HEEL), ("ball", G.BALL),
                                ("toe", G.TOE))}
            lowest = min(p.z for p in pts.values())
            worst_sink = max(worst_sink, -lowest * 1000.0)
            hist[tag].append((pts, lowest))

    for tag in ("l", "r"):
        for i in range(n):
            pts, lowest = hist[tag][i]
            nxt, _ = hist[tag][i + 1]
            planted = lowest < 0.012          # something is on the ground
            stance[tag].append(planted)
            if not planted:
                continue
            # A rigid foot in contact must have at least ONE stationary point,
            # or it is sliding. So take the BEST candidate: the smallest
            # movement across every landmark that is on the ground in both
            # frames. If even the best one moves, the foot really is skating.
            #
            # Deliberately not "ask the gait which point is the pivot" — the
            # whole value of this check is that it does not share assumptions
            # with the thing it is checking. An earlier version guessed the
            # pivot with a hysteresis rule and reported 5.5 mm of slip on a
            # walk that was in fact exact, because it held the ball of the foot
            # through push-off while the toe was carrying the weight.
            best = None
            for m in pts:
                if pts[m].z > 0.006 or nxt[m].z > 0.006:
                    continue
                a, b = pts[m], nxt[m]
                # The clip is in-place, so a world-stationary point drifts
                # BACKWARD (+Y) in body space by speed*dt each frame.
                d = math.sqrt((b.x - a.x) ** 2
                              + (b.y - a.y - speed * dt) ** 2
                              + (b.z - a.z) ** 2)
                best = d if best is None else min(best, d)
            if best is not None:
                worst_slip = max(worst_slip, best * 1000.0)

    both = sum(1 for i in range(n) if stance["l"][i] and stance["r"][i]) / n
    neither = sum(1 for i in range(n)
                  if not stance["l"][i] and not stance["r"][i]) / n
    lo = sum(stance["l"]) / n
    return worst_slip, worst_sink, lo, both, neither


if __name__ == "__main__":
    # the gait lives on the skeleton, not on any one variant's kit, so build
    # the plainest soldier there is and author the clips onto it
    spec = IM.kit(4, "us", "rifle")
    arm, _, _ = IM.build_rig(spec, 4, "us", "rifle")
    IM.author_clips(arm)
    gaits = G.build_gaits()

    print(f"\n{'clip':14s} {'slip':>9s} {'sink':>8s} {'stance':>7s} "
          f"{'double':>7s} {'flight':>7s}")
    ok = True
    for name, g in gaits.items():
        n = max(8, round(g.stride / g.speed * FPS))
        meta = dict(frames=n, speed=g.speed, stride=g.stride)
        slip, sink, lo, both, neither = check(arm, name, meta)
        bad = []
        if slip > TOL_SLIP:
            bad.append("SLIP")
        if sink > TOL_SINK:
            bad.append("SINK")
        # a walk must have double support and no flight; a run is the reverse.
        # If both legs move together, one of these collapses to 0 or 1 and the
        # gait is a hop, not a stride.
        if g.duty > 0.5 and both < 0.05:
            bad.append("NO-DOUBLE-SUPPORT")
        if g.duty < 0.5 and neither < 0.05:
            bad.append("NO-FLIGHT")
        if not 0.15 < lo < 0.85:
            bad.append("STANCE-RATIO")
        if bad:
            ok = False
        print(f"{name:14s} {slip:7.2f}mm {sink:6.2f}mm {lo:6.0%} "
              f"{both:6.0%} {neither:6.0%}  {' '.join(bad)}")
    print("\nslip = world movement of the weight-bearing point between frames")
    print("PASS" if ok else "FAIL")
