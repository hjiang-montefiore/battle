"""Infantry: one shared skeleton, seven roles, a real locomotion set.

    Blender -b --python tools/infantry_models.py

docs/14-animation.md sets the economy: ONE skeleton for every infantry unit in
the game. A 1955 rifleman and a 2025 rifleman stand, walk, run and die
identically; only the mesh and the kit differ. So the clip set is authored once
and reused across 7 epochs x 8 factions x 7 roles, turning infantry animation
from a per-unit cost into a fixed cost.

WHY THIS DOES NOT USE THE VEHICLE PIPELINE
------------------------------------------
hero_models.build() joins meshes per material group and bakes ambient occlusion
into a UV channel. Joining would destroy the skin weights, and at 20-40 px tall
a soldier gains nothing from a baked AO map. Infantry gets its own export path.

RIGID SKINNING
--------------
Every vertex is weighted 1.0 to exactly one bone. At RTS zoom an unsmoothed
elbow is invisible, and this removes weight painting from the pipeline
entirely. It still exports as a standard glTF skin, so if these are ever
replaced by real characters the skeleton and clip names stay identical and
nothing downstream changes.

MOVEMENT
--------
The locomotion clips come from tools/gait.py, which places the weight-bearing
contact point on the ground first and solves the leg to reach it, rather than
posing joints and hoping the foot lands somewhere plausible. Measured foot slip
is 0.000 mm/frame on all four gaits. See that module for the reasoning and for
the playback-rate contract the game has to honour.

Two details that carry most of the readability at RTS zoom:

  * A soldier at the ready does NOT swing its arms. Both hands stay on the
    weapon and the torso absorbs the gait. Free arm swing is what civilians do,
    and using it here makes armed infantry read as a crowd. The one exception is
    the sprint, where the weapon drops to one hand and the free arm pumps.
  * Walking vaults over a straight leg (pelvis high at mid-stance); running
    compresses it like a spring (pelvis LOW at mid-stance, high in flight).
    Inverting that is what makes a run read as a fast walk.
"""
import bpy, json, math, os, sys
from mathutils import Vector
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gait import (build_gaits, solve_leg, L_THIGH, L_SHIN, HIP_X,
                  REACH as REACH_MAX)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "blockout", "e4_infantry")
FPS = 30
REST_HIP = 0.90         # hip joint height of the rest skeleton, metres

# (name, parent, head, tail) — 1.8 m soldier, metres, Z up, facing -Y
SKELETON = [
    ("root",       None,         (0, 0, 0.00),      (0, 0, 0.10)),
    ("pelvis",     "root",       (0, 0, 0.90),      (0, 0, 1.10)),
    ("spine",      "pelvis",     (0, 0, 1.10),      (0, 0, 1.30)),
    ("chest",      "spine",      (0, 0, 1.30),      (0, 0, 1.50)),
    ("neck",       "chest",      (0, 0, 1.50),      (0, 0, 1.60)),
    ("head",       "neck",       (0, 0, 1.60),      (0, 0, 1.78)),
    ("shoulder_l", "chest",      (-0.06, 0, 1.46),  (-0.19, 0, 1.46)),
    ("upperarm_l", "shoulder_l", (-0.19, 0, 1.46),  (-0.19, 0, 1.11)),
    ("lowerarm_l", "upperarm_l", (-0.19, 0, 1.11),  (-0.19, 0, 0.85)),
    ("hand_l",     "lowerarm_l", (-0.19, 0, 0.85),  (-0.19, 0, 0.75)),
    ("shoulder_r", "chest",      (0.06, 0, 1.46),   (0.19, 0, 1.46)),
    ("upperarm_r", "shoulder_r", (0.19, 0, 1.46),   (0.19, 0, 1.11)),
    ("lowerarm_r", "upperarm_r", (0.19, 0, 1.11),   (0.19, 0, 0.85)),
    ("hand_r",     "lowerarm_r", (0.19, 0, 0.85),   (0.19, 0, 0.75)),
    ("thigh_l",    "pelvis",     (-HIP_X, 0, 0.90), (-HIP_X, 0, 0.48)),
    ("shin_l",     "thigh_l",    (-HIP_X, 0, 0.48), (-HIP_X, 0, 0.08)),
    ("foot_l",     "shin_l",     (-HIP_X, 0, 0.08), (-HIP_X, -0.19, -0.01)),
    ("thigh_r",    "pelvis",     (HIP_X, 0, 0.90),  (HIP_X, 0, 0.48)),
    ("shin_r",     "thigh_r",    (HIP_X, 0, 0.48),  (HIP_X, 0, 0.08)),
    ("foot_r",     "shin_r",     (HIP_X, 0, 0.08),  (HIP_X, -0.19, -0.01)),
]

# part -> (bone, centre, size). Rigid: every vertex goes to one bone.
BODY = [
    ("torso",    "chest",      (0, 0, 1.35),          (0.33, 0.21, 0.34)),
    ("neck",     "neck",       (0, 0, 1.55),          (0.13, 0.14, 0.14)),
    ("hips",     "pelvis",     (0, 0, 1.06),          (0.30, 0.20, 0.26)),
    ("head",     "head",       (0, 0.005, 1.685),     (0.17, 0.20, 0.19)),
    ("shldr_l",  "shoulder_l", (-0.125, 0, 1.44),     (0.17, 0.20, 0.18)),
    ("uarm_l",   "upperarm_l", (-0.19, 0, 1.285),     (0.11, 0.11, 0.38)),
    ("larm_l",   "lowerarm_l", (-0.19, 0, 0.980),     (0.10, 0.10, 0.29)),
    ("hand_l",   "hand_l",     (-0.19, 0, 0.800),     (0.09, 0.11, 0.13)),
    ("shldr_r",  "shoulder_r", (0.125, 0, 1.44),      (0.17, 0.20, 0.18)),
    ("uarm_r",   "upperarm_r", (0.19, 0, 1.285),      (0.11, 0.11, 0.38)),
    ("larm_r",   "lowerarm_r", (0.19, 0, 0.980),      (0.10, 0.10, 0.29)),
    ("hand_r",   "hand_r",     (0.19, 0, 0.800),      (0.09, 0.11, 0.13)),
    ("thigh_l",  "thigh_l",    (-HIP_X, 0, 0.71),     (0.15, 0.15, 0.47)),
    ("shin_l",   "shin_l",     (-HIP_X, 0, 0.285),    (0.12, 0.12, 0.44)),
    ("boot_l",   "foot_l",     (-HIP_X, -0.05, 0.04), (0.13, 0.28, 0.10)),
    ("thigh_r",  "thigh_r",    (HIP_X, 0, 0.71),      (0.15, 0.15, 0.47)),
    ("shin_r",   "shin_r",     (HIP_X, 0, 0.285),     (0.12, 0.12, 0.44)),
    ("boot_r",   "foot_r",     (HIP_X, -0.05, 0.04),  (0.13, 0.28, 0.10)),
]


def _mat(name, rgb, rough=0.88):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*rgb, 1)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = 0.0
    return m


def _box(name, centre, size, mat, bone):
    bpy.ops.mesh.primitive_cube_add(size=1, location=centre)
    o = bpy.context.object
    o.name = name
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    o.data.materials.append(mat)
    # vertex groups survive the join, so bind here and join later
    g = o.vertex_groups.new(name=bone)
    g.add(range(len(o.data.vertices)), 1.0, "REPLACE")
    return o


def build_armature():
    bpy.ops.object.armature_add(enter_editmode=True, location=(0, 0, 0))
    arm = bpy.context.object
    arm.name = "soldier_rig"
    eb = arm.data.edit_bones
    for b in list(eb):
        eb.remove(b)
    made = {}
    for name, parent, head, tail in SKELETON:
        b = eb.new(name)
        b.head, b.tail = Vector(head), Vector(tail)
        if parent:
            b.parent = made[parent]
        made[name] = b
    bpy.ops.object.mode_set(mode="OBJECT")
    return arm


# ── pose conventions ───────────────────────────────────────────────
# Bones that point straight down (arms, legs) and bones that point straight up
# (root, pelvis, spine, chest) both keep local X aligned to world X, so a
# rotation about world X is just euler.x. Forward is -Y, and +euler.x carries a
# bone's tail toward +Y, so FORWARD FLEXION IS NEGATIVE euler.x.
#
# For the upright bones local Y is world +Z, so yaw about the world vertical is
# euler.y. For the downward bones local Z is world +Y, so abduction is euler.z.
L_UPPER = 0.35                  # shoulder joint -> elbow
L_FORE = 0.26                   # elbow -> wrist

# Where the two hands sit relative to the chest when the weapon is at the
# ready: right hand on the grip, left hand well forward on the handguard. The
# weapon is then authored between them, so the grip really is under one hand
# and the handguard under the other — rather than posing the arms by eye and
# hoping the rifle lands somewhere near both.
# Both hands sit on ONE line just right of the centreline, because that is
# what makes the weapon point where the soldier is facing. Separating them
# across the body — grip on the right, handguard out to the left — cants the
# rifle 45 degrees off the line of travel, which is what the first solved pose
# did.
HAND_R_READY = Vector((0.075, -0.120, 1.150))
HAND_L_READY = Vector((0.045, -0.335, 1.145))
# dashing for cover: weapon in one hand, down at the side
HAND_R_DASH = Vector((0.185, -0.060, 0.880))


def _set(pose, bone, x=None, y=None, z=None):
    e = list(pose.get(bone, (0.0, 0.0, 0.0)))
    if x is not None:
        e[0] = x
    if y is not None:
        e[1] = y
    if z is not None:
        e[2] = z
    pose[bone] = tuple(e)


def aim_bone(arm, name, direction):
    """Point a bone along a world direction, keeping its head where the parent
    chain put it. Minimal twist, which is fine because every child that cares
    about its own orientation gets aimed explicitly too."""
    pb = arm.pose.bones[name]
    rest = arm.data.bones[name].matrix_local.to_3x3()
    rest_dir = (rest @ Vector((0.0, 1.0, 0.0))).normalized()
    q = rest_dir.rotation_difference(Vector(direction).normalized())
    m = (q.to_matrix() @ rest).to_4x4()
    m.translation = pb.matrix.translation
    pb.matrix = m


def place_arm(arm, tag, wrist, hint):
    """Two-bone solve for one arm, same construction as the leg.

    The hint is the direction the elbow should break toward — down and back
    for a weapon at the ready, which is what stops the elbows flaring out
    sideways into the splayed-scarecrow pose that hand-authored eulers gave.
    """
    shoulder = arm.pose.bones[f"upperarm_{tag}"].matrix.translation.copy()
    v = Vector(wrist) - shoulder
    d = max(min(v.length, (L_UPPER + L_FORE) * 0.995),
            abs(L_UPPER - L_FORE) + 1e-4)
    u = v.normalized()
    cb = (L_UPPER ** 2 + d * d - L_FORE ** 2) / (2 * L_UPPER * d)
    beta = math.acos(max(-1.0, min(1.0, cb)))
    h = Vector(hint)
    perp = h - u * h.dot(u)
    perp = perp.normalized() if perp.length > 1e-6 else Vector((0, 0, -1))
    aim_bone(arm, f"upperarm_{tag}", u * math.cos(beta) + perp * math.sin(beta))
    bpy.context.view_layer.update()
    elbow = arm.pose.bones[f"lowerarm_{tag}"].matrix.translation.copy()
    aim_bone(arm, f"lowerarm_{tag}", Vector(wrist) - elbow)
    bpy.context.view_layer.update()


def chest_frame(arm):
    """Map a rest-space point into wherever the posed chest has carried it."""
    b = arm.data.bones["chest"]
    return arm.pose.bones["chest"].matrix @ b.matrix_local.inverted()


def apply_carry(arm, sprint=False):
    """Put both hands on the weapon, tracking the torso."""
    M = chest_frame(arm)
    if sprint:
        place_arm(arm, "r", M @ HAND_R_DASH, (0.5, 0.6, -1.0))
    else:
        place_arm(arm, "r", M @ HAND_R_READY, (0.45, 0.55, -1.0))
        place_arm(arm, "l", M @ HAND_L_READY, (-0.60, 0.35, -1.0))


def place_leg(arm, tag, ankle, pf):
    """Put one leg's ankle exactly on the target and level the sole.

    Written as three world-space placements rather than as euler angles,
    because the euler route kept being ALMOST right. Each joint's rotation
    happens about its own local axis, and every rotation upstream tilts that
    axis a little: the pelvis yaw tilts the hip, the hip abduction tilts the
    knee, the knee tilts the ankle. Each correction that was derived by hand
    left a few millimetres of lateral drift from the joint below it.

    Reading back the matrices Blender actually computed removes the algebra
    entirely, and with it that whole family of near-misses. The cost is a
    depsgraph update per joint, which for ninety frames of clip is nothing.
    """
    hip = arm.pose.bones[f"thigh_{tag}"].matrix.translation.copy()
    v = Vector(ankle) - hip
    d = max(min(v.length, REACH_MAX), abs(L_THIGH - L_SHIN) + 1e-4)
    u = v.normalized()

    # knee forward of the hip-ankle line by beta, in the plane that line spans
    # with the forward direction
    cb = (L_THIGH ** 2 + d * d - L_SHIN ** 2) / (2 * L_THIGH * d)
    beta = math.acos(max(-1.0, min(1.0, cb)))
    fwd = Vector((0.0, -1.0, 0.0))
    perp = fwd - u * fwd.dot(u)
    perp = perp.normalized() if perp.length > 1e-6 else fwd
    thigh_dir = u * math.cos(beta) + perp * math.sin(beta)

    aim_bone(arm, f"thigh_{tag}", thigh_dir)
    bpy.context.view_layer.update()
    knee = arm.pose.bones[f"shin_{tag}"].matrix.translation.copy()
    aim_bone(arm, f"shin_{tag}", Vector(ankle) - knee)
    bpy.context.view_layer.update()

    # the sole must end up rotated about world X by exactly pf, which is what
    # the contact solve assumed when it placed the pivot on the ground
    from mathutils import Euler
    pb = arm.pose.bones[f"foot_{tag}"]
    rest = arm.data.bones[f"foot_{tag}"].matrix_local.to_3x3()
    m = (Euler((pf, 0.0, 0.0), "XYZ").to_matrix() @ rest).to_4x4()
    m.translation = pb.matrix.translation
    pb.matrix = m


def locomotion_pose(g, phi, sprint=False):
    """One frame of a gait as bone eulers, a root offset, and the world foot
    pitches the contact solve assumed."""
    pose = {}
    loc = {}
    pitch = {}
    dx, dz, yaw = g.pelvis(phi)
    # root carries the body's translation. Its local Y runs along the bone,
    # which points +Z, so a world vertical offset goes in the y slot.
    loc["root"] = (dx, dz + (g.hip_h - REST_HIP), 0.0)
    _set(pose, "pelvis", x=-g.lean * 0.25, y=yaw)
    _set(pose, "spine", x=-g.lean * 0.45)
    _set(pose, "chest", x=-g.lean * 0.30,
         y=g.chest_rot * math.sin(2 * math.pi * phi))
    # gaze stabilisation: the head unwinds most of the chest's counter-rotation
    # so the soldier keeps looking where it is going
    _set(pose, "neck", y=-0.55 * g.chest_rot * math.sin(2 * math.pi * phi))
    _set(pose, "head", x=g.lean * 0.6)

    _set(pose, "pelvis", x=-g.lean * 0.25, y=yaw)
    for side, tag in ((-1, "l"), (1, "r")):
        ankle, pf, _ = g.foot(phi, side)
        pitch[tag] = (ankle, pf)

    if sprint:
        # weapon in the right hand; the free left arm pumps against the left
        # leg, which is the one time armed infantry swings an arm at all
        s = 0.95 * math.sin(2 * math.pi * phi + math.pi)
        _set(pose, "upperarm_l", x=-s)
        _set(pose, "lowerarm_l", x=-1.05 - 0.35 * abs(s))
    return pose, loc, pitch


def static_pose(name):
    """Non-locomotion clips. These are held poses, not cycles.

    Returns (pose, root offset, holds_weapon). Arm angles are absent on
    purpose: anything holding the weapon gets its arms solved to the hand
    targets afterwards, so the grip stays correct no matter how the torso is
    turned or how far the body has gone over.
    """
    p = {}
    loc = {}
    carry = True
    if name == "idle":
        _set(p, "spine", x=-0.05)
        _set(p, "head", y=0.10)
        loc["root"] = (0, -0.015, 0)
    elif name == "idle_alert":
        _set(p, "spine", x=-0.14)
        _set(p, "thigh_l", x=0.10)
        _set(p, "thigh_r", x=0.10)
        _set(p, "shin_l", x=0.22)
        _set(p, "shin_r", x=0.22)
        _set(p, "foot_l", x=0.12)
        _set(p, "foot_r", x=0.12)
        loc["root"] = (0, -0.055, 0)
    elif name == "fire_stand":
        _set(p, "spine", x=-0.12)
        _set(p, "chest", y=-0.16)
    elif name == "fire_crouch":
        # hips drop, both knees fold, torso stays upright behind the weapon
        for t in ("l", "r"):
            _set(p, f"thigh_{t}", x=0.95)
            _set(p, f"shin_{t}", x=1.55)
            _set(p, f"foot_{t}", x=0.60)
        _set(p, "pelvis", x=-0.26)
        _set(p, "spine", x=-0.20)
        loc["root"] = (0, -0.30, 0)
    elif name == "prone":
        # face down. Rotating root by +90 about world X takes the body's +Z
        # onto -Y; 84 leaves the head slightly raised behind the weapon.
        _set(p, "root", x=math.radians(84))
        loc["root"] = (0, -0.80, 0.905)
        _set(p, "neck", x=-0.55)
        for t in ("l", "r"):
            _set(p, f"thigh_{t}", x=-0.10)
            _set(p, f"shin_{t}", x=0.16)
    elif name == "death":
        _set(p, "root", x=math.radians(88))
        loc["root"] = (0.10, -0.84, 0.92)
        _set(p, "upperarm_r", x=0.40, z=0.80)
        _set(p, "upperarm_l", x=0.30, z=-0.90)
        _set(p, "lowerarm_r", x=-0.25)
        _set(p, "lowerarm_l", x=-0.20)
        _set(p, "neck", x=0.30)
        _set(p, "thigh_r", x=-0.22)
        _set(p, "shin_r", x=0.40)
        carry = False              # dead soldiers drop the weapon arm
    return p, loc, carry


def crawl_frames(n=48, speed=0.42, stride=0.62):
    """Prone movement: alternating elbow-and-knee pulls.

    Honest limitation: this is keyed, not contact-solved like the upright
    gaits, because the contacts alternate between four limbs and the torso.
    Slip is therefore not provably zero. At the speed a crawl actually plays it
    is well under the eye's threshold, and the same distance-driven playback
    contract still applies.
    """
    out = []
    for i in range(n):
        phi = i / n
        p = {}
        loc = {}
        _set(p, "root", x=math.radians(86))
        loc["root"] = (0, -0.80 + 0.012 * math.sin(4 * math.pi * phi), 0.905)
        s = math.sin(2 * math.pi * phi)
        _set(p, "thigh_l", x=-0.10 - 0.38 * s, z=-0.30)
        _set(p, "shin_l", x=0.30 + 0.42 * abs(s))
        _set(p, "thigh_r", x=-0.10 + 0.38 * s, z=0.30)
        _set(p, "shin_r", x=0.30 + 0.42 * abs(s))
        _set(p, "pelvis", y=0.10 * s)
        _set(p, "chest", y=-0.14 * s)
        _set(p, "neck", x=-0.55)
        out.append((p, loc))
    return out


def key(arm, frame, pose, loc):
    """Write a COMPLETE pose. Every bone, every frame.

    Anything left unkeyed is not neutral — it holds whatever the last thing to
    touch it left behind, both here at author time and in the engine when one
    clip follows another. Keying the full skeleton costs a few hundred bytes
    per clip and removes the entire class of bug.
    """
    apply_pose(arm, pose, loc)
    insert(arm, frame)


def apply_pose(arm, pose, loc):
    for pb in arm.pose.bones:
        pb.rotation_mode = "XYZ"
        pb.rotation_euler = pose.get(pb.name, (0.0, 0.0, 0.0))
        pb.location = loc.get(pb.name, (0.0, 0.0, 0.0))


def insert(arm, frame):
    for pb in arm.pose.bones:
        pb.keyframe_insert("rotation_euler", frame=frame)
        pb.keyframe_insert("location", frame=frame)


def author_clips(arm):
    """Build every action and stash each on its own NLA track, which is what
    makes the exporter emit them as separate glTF animations."""
    gaits = build_gaits()
    arm.animation_data_create()
    made, meta = [], {}

    def new_action(name):
        act = bpy.data.actions.new(name)
        arm.animation_data.action = act
        return act

    # locomotion — the cycles, contact-solved
    for name, g in gaits.items():
        n = max(8, round(g.stride / g.speed * FPS))
        act = new_action(name)
        for i in range(n + 1):                 # +1 duplicates frame 0 to close
            pose, loc, pitch = locomotion_pose(g, (i % n) / n,
                                               sprint=name == "sprint")
            apply_pose(arm, pose, loc)
            bpy.context.view_layer.update()
            for tag, (ankle, pf) in pitch.items():
                place_leg(arm, tag, ankle, pf)
            apply_carry(arm, sprint=name == "sprint")
            insert(arm, i + 1)
        act.use_fake_user = True
        made.append(act)
        meta[name] = dict(loop=True, frames=n, fps=FPS,
                          speed=round(g.speed, 3), stride=round(g.stride, 3),
                          duty=round(g.duty, 3), slip_mm=round(g.slip(FPS), 4))

    # prone movement
    act = new_action("crawl")
    frames = crawl_frames()
    for i, (p, l) in enumerate(frames + [frames[0]]):
        apply_pose(arm, p, l)
        bpy.context.view_layer.update()
        apply_carry(arm)
        insert(arm, i + 1)
    act.use_fake_user = True
    made.append(act)
    meta["crawl"] = dict(loop=True, frames=len(frames), fps=FPS,
                         speed=0.42, stride=0.62, duty=None, slip_mm=None)

    # held poses
    for name in ("idle", "idle_alert", "fire_stand", "fire_crouch",
                 "prone", "death"):
        act = new_action(name)
        p, l, carry = static_pose(name)
        for f in (1, 2):
            apply_pose(arm, p, l)
            bpy.context.view_layer.update()
            if carry:
                apply_carry(arm)
            insert(arm, f)
        act.use_fake_user = True
        made.append(act)
        meta[name] = dict(loop=name in ("idle", "idle_alert"), frames=2,
                          fps=FPS, speed=0.0)

    arm.animation_data.action = None
    for act in made:
        tr = arm.animation_data.nla_tracks.new()
        tr.name = act.name
        tr.strips.new(act.name, 1, act)
    return meta


# ── the era / faction / role kit ladder ───────────────────────────
# Researched and consistency-checked 2026-08-26. Pixel scale throughout: a
# 1.8 m soldier at 30 px means 1 px = 0.060 m, and anything under ~0.015 m is
# declared invisible and never used as a tell.
#
# THE FINDING THAT SHAPED THIS TABLE: infantry does not have seven silhouettes.
# It has three.
#     epochs 1-3   steel pot, long rifle, flat chest, load carried on the belt
#     epochs 4-5   composite helmet, the load climbs to the chest, plates arrive
#     epochs 6-7   short carbine with an optic, plate-carrier bulk, NVG
# Epochs 1 and 2 are declared VISUALLY IDENTICAL for the rifleman, engineer and
# mortar — the M1 helmet ran unchanged from 1941 to 1985 and the flak vest of
# 1952 is no bulkier than the one that replaced it. Epoch 2 is carried entirely
# by the AT role, whose launcher collapses from a 1.53 m bazooka to a 0.88 m
# LAW: an 11 px change, and the largest single event in the whole ladder.
#
# The weapon is the strongest generational channel by a wide margin. 1.10 m of
# Garand is 18 px of horizontal line held clear of the body against 13 px for a
# modern carbine, and that 5 px is worth more than the helmet and the armour
# combined. Body armour is the weakest: a 0.02 m flak vest is a third of a
# pixel, so epochs 1-4 are deliberately flat at 0.020 and the real cliff is put
# where the real cliff was — Interceptor with rifle plates, epoch 5.
EPOCH_KIT = {
    # 1 Early Cold War 1950-59 — M1 pot, OG-107, M1 Garand, belt-order load.
    1: dict(helmet_shape="pot", helmet_size=(0.240, 0.275, 0.125), nvg=False,
            torso_armour=0.020, webbing=0.035, belt_bulk=0.050,
            pack=0.14, pack_tall=False, yoke=False,
            optic_len=0.00, weapon_len=1.10, weapon_style="battle_rifle"),
    # 2 Missile Age 1960-69 — identical to epoch 1 above the waist. See above.
    2: dict(helmet_shape="pot", helmet_size=(0.240, 0.275, 0.125), nvg=False,
            torso_armour=0.020, webbing=0.035, belt_bulk=0.050,
            pack=0.14, pack_tall=False, yoke=False,
            optic_len=0.00, weapon_len=1.10, weapon_style="battle_rifle"),
    # 3 Precision Dawn 1970-79 — M16A1, and the ALICE frame puts a square hump
    #   at the shoulder line. First epoch where the weapon reads as an L.
    3: dict(helmet_shape="pot", helmet_size=(0.240, 0.275, 0.125), nvg=False,
            torso_armour=0.020, webbing=0.035, belt_bulk=0.050,
            pack=0.20, pack_tall=True, yoke=False,
            optic_len=0.00, weapon_len=1.00, weapon_style="assault"),
    # 4 Digital 1980-89 — PASGT. The ONLY epoch-4 tell is the head: the brim
    #   goes and a skirt closes the neck gap, so the head stops being a
    #   mushroom on a stalk and becomes continuous with the shoulders.
    4: dict(helmet_shape="composite", helmet_size=(0.235, 0.260, 0.150), nvg=False,
            torso_armour=0.020, webbing=0.035, belt_bulk=0.050,
            pack=0.20, pack_tall=True, yoke=False,
            optic_len=0.00, weapon_len=1.00, weapon_style="assault"),
    # 5 Networked 1990-2004 — the load moves off the belt onto the chest,
    #   rifle plates arrive, optic and NVG blocks appear. Biggest transition.
    5: dict(helmet_shape="composite", helmet_size=(0.235, 0.260, 0.150), nvg=True,
            torso_armour=0.055, webbing=0.075, belt_bulk=0.015,
            pack=0.16, pack_tall=False, yoke=False,
            optic_len=0.16, weapon_len=1.00, weapon_style="assault"),
    # 6 Sensor Fusion 2005-15 — the carbine, plus the squared IOTV yoke.
    6: dict(helmet_shape="composite", helmet_size=(0.235, 0.260, 0.150), nvg=True,
            torso_armour=0.075, webbing=0.075, belt_bulk=0.015,
            pack=0.16, pack_tall=False, yoke=True,
            optic_len=0.16, weapon_len=0.80, weapon_style="carbine"),
    # 7 Contested 2016- — high cut: skirt deleted, shell widened for ear cups
    #   plus a rear counterweight. Armour SLIMS for the first time.
    7: dict(helmet_shape="highcut", helmet_size=(0.260, 0.290, 0.130), nvg=True,
            torso_armour=0.050, webbing=0.075, belt_bulk=0.015,
            pack=0.16, pack_tall=False, yoke=False,
            optic_len=0.16, weapon_len=0.86, weapon_style="carbine"),
}

# Colour is nearly the whole national layer. These are spread across five luma
# tiers with real blue-channel separation, which is NOT what the eight armies
# actually look like — US woodland, Russian flora and PLA type-07 are all much
# the same green in life. Reproducing that faithfully would leave a player
# unable to tell three armies apart on one map, so legibility wins and the
# choice is recorded here rather than hidden.
#
# Camouflage PATTERN is rejected outright, and not merely as invisible: at
# 30 px a two-tone dither averages toward its own mean, which REDUCES a
# faction's contrast against the other seven. Painting camo would undo the
# separation this palette exists to create.
#
# Every *_from dict is keyed by the epoch a value takes effect from; the
# largest key <= era wins, and a value of None reverts to the epoch default.
FACTION_KIT = {
    "us": dict(body=(0.28, 0.32, 0.17), helmet=(0.18, 0.20, 0.12),
               helmet_from={}, weapon_from={}, optic_from={}, at_len_from={},
               no_armour=False, no_nvg=False),
    # Mk III turtle in epochs 1-2 with the brim exaggerated well past life,
    # and the 1.14 m L1A1 SLR held through epoch 4 while everyone else is at
    # 1.00 — the strongest national delta in the set. It wins by borrowing the
    # GENERATIONAL channel rather than by being nationally distinct.
    "uk": dict(body=(0.32, 0.23, 0.14), helmet=(0.50, 0.44, 0.30),
               helmet_from={1: "turtle", 3: None},
               weapon_from={1: (1.14, "battle_rifle"), 5: (0.785, "bullpup")},
               optic_from={5: 0.24}, at_len_from={},
               no_armour=False, no_nvg=False),
    # Zero shape deltas, deliberately. The G3 at 1.025 m and the Gefechtshelm
    # M92 both land inside one pixel of the epoch default. Germany is the clean
    # confirmation that a faction can be carried entirely by colour.
    "de": dict(body=(0.26, 0.29, 0.32), helmet=(0.24, 0.27, 0.30),
               helmet_from={}, weapon_from={}, optic_from={}, at_len_from={},
               no_armour=False, no_nvg=False),
    "fr": dict(body=(0.60, 0.56, 0.44), helmet=(0.19, 0.22, 0.18),
               helmet_from={},
               weapon_from={4: (0.757, "bullpup"), 7: (0.90, "carbine")},
               optic_from={}, at_len_from={}, no_armour=False, no_nvg=False),
    "cn": dict(body=(0.38, 0.46, 0.37), helmet=(0.21, 0.28, 0.21),
               helmet_from={1: "cap", 2: "dome", 6: None},
               weapon_from={1: (0.843, "assault"), 2: (0.880, "assault"),
                            6: (0.746, "bullpup"), 7: (0.899, "carbine")},
               optic_from={}, at_len_from={1: 0.95, 6: None},
               no_armour=False, no_nvg=False),
    "ru": dict(body=(0.46, 0.41, 0.17), helmet=(0.24, 0.25, 0.13),
               helmet_from={1: "dome", 6: None},
               weapon_from={2: (0.880, "assault")},
               optic_from={}, at_len_from={1: 0.95},
               no_armour=False, no_nvg=False),
    "tw": dict(body=(0.13, 0.23, 0.35), helmet=(0.36, 0.46, 0.54),
               helmet_from={}, weapon_from={}, optic_from={}, at_len_from={},
               no_armour=False, no_nvg=False),
    # Dome helmet for all seven epochs, no rifle plates ever, no NVG ever: a
    # lineage read early and a generational-lag read late, from one table.
    "kp": dict(body=(0.19, 0.19, 0.14), helmet=(0.17, 0.17, 0.13),
               helmet_from={1: "dome"},
               weapon_from={1: (0.843, "assault"), 2: (0.880, "assault")},
               optic_from={}, at_len_from={1: 0.95},
               no_armour=True, no_nvg=True),
}

# Role is the strongest axis of the three, because it is the only one that puts
# a long object OUTSIDE the body outline where nothing can occlude it.
ROLE_KIT = {
    "rifle": dict(note="baseline - the epoch table IS the rifleman"),
    "at": dict(weapon_len={1: 1.53, 2: 0.88, 3: 1.16, 5: 1.20},
               weapon_bore={1: 0.090, 3: 0.105, 5: 0.140},
               launcher_block={3: "side", 5: "under"}, pack_bonus=0.04,
               note="1.53 bazooka -> 0.88 LAW is 11 px, the largest single "
                    "event in the ladder and the whole reason epoch 2 exists"),
    "manpads": dict(weapon_len={2: 1.40, 4: 1.52},
                    weapon_bore={2: 0.085, 4: 0.115},
                    locked=(1,), pack_bonus=0.02,
                    note="no shoulder-fired SAM existed anywhere before 1968; "
                         "the Stinger is unchanged 1981-present, so epochs "
                         "4-7 are ONE shape - do not invent a change"),
    "recon": dict(helmet_at={1: False, 6: True}, optic_bonus=0.04,
                  antenna={3: 1.00, 6: 0.0}, tripod_from=6, pack_bonus=0.05,
                  note="the PRC-77 whip antenna is the most legible role "
                       "marker in the game"),
    "engineer": dict(detector=True, tools=True, pack_bonus=0.08,
                     note="a pole held forward and low with a disc head - an "
                          "outline no other role or epoch has, free in all "
                          "seven epochs"),
    "sf": dict(helmet_at={1: False, 6: True}, helmet_shape_at={6: "highcut"},
               weapon_len={1: 0.90, 2: 0.75}, armour_at={5: 0.045},
               webbing_at={5: 0.050}, nvg_from=4, optic_bonus=0.04,
               pack_bonus=-0.04,
               note="the one role THINNER than its epoch baseline"),
    "mortar": dict(weapon_len={1: 1.05}, weapon_bore={1: 0.085},
                   baseplate=True, pack_bonus=0.06,
                   note="tube length is epoch-invariant since 1952; the "
                        "baseplate slab is the read"),
}


def _pick(d, era, default=None):
    """Value for the largest key <= era. A stored None reverts to default."""
    if not d:
        return default
    keys = [k for k in sorted(d) if k <= era]
    if not keys:
        return default
    v = d[keys[-1]]
    return default if v is None else v


def locked(era, role):
    """Role/epoch combinations that did not exist."""
    return era in ROLE_KIT[role].get("locked", ())


def kit(era, faction, role):
    """Merge the three ladders into one spec for a single variant."""
    e = dict(EPOCH_KIT[era])
    f = FACTION_KIT[faction]
    r = ROLE_KIT[role]

    e["body"], e["helmet_colour"] = f["body"], f["helmet"]
    e["role"] = role

    # headgear: role first (recon and SF go bare-headed until epoch 6), then
    # the national helmet lineage, then the epoch default
    e["helmet"] = _pick(r.get("helmet_at", {}), era, True)
    shape = _pick(r.get("helmet_shape_at", {}), era,
                  _pick(f["helmet_from"], era, e["helmet_shape"]))
    if shape == "cap":
        e["helmet"], shape = False, e["helmet_shape"]
    e["helmet_shape"] = shape

    # weapon: a role weapon replaces the rifle outright, otherwise the nation's
    # rifle replaces the epoch's. Bullpup lengths are ABSOLUTE — the earlier
    # 0.86 multiplier produced 0.851 m for a rifle that is really 785 mm.
    if "weapon_len" in r:
        e["weapon_len"] = _pick(r["weapon_len"], era, e["weapon_len"])
        e["weapon_bore"] = _pick(r.get("weapon_bore", {}), era, 0.07)
        e["weapon_style"] = "launcher" if role in ("at", "manpads") else "tube"
        if role == "mortar":
            e["weapon_style"] = "tube"
    else:
        nat = _pick(f["weapon_from"], era)
        if nat:
            e["weapon_len"], e["weapon_style"] = nat
        national_at = _pick(f["at_len_from"], era)
        e["weapon_bore"] = 0.055 if era >= 5 else 0.065
        if national_at and role == "at":
            e["weapon_len"] = national_at

    e["optic_len"] = _pick(f["optic_from"], era, e["optic_len"])
    if e["optic_len"] > 0:
        e["optic_len"] += r.get("optic_bonus", 0.0)

    e["torso_armour"] = _pick(r.get("armour_at", {}), era, e["torso_armour"])
    e["webbing"] = _pick(r.get("webbing_at", {}), era, e["webbing"])
    if f["no_armour"]:
        e["torso_armour"] = 0.0
        e["yoke"] = False
    e["pack"] = max(0.06, e["pack"] + r.get("pack_bonus", 0.0))

    nvg_from = r.get("nvg_from")
    if nvg_from is not None:
        e["nvg"] = era >= nvg_from
    if f["no_nvg"]:
        e["nvg"] = False

    e["tools"] = r.get("detector", False) or r.get("tools", False)
    e["detector"] = r.get("detector", False)
    e["baseplate"] = r.get("baseplate", False)
    e["antenna"] = _pick(r.get("antenna", {}), era, 0.0)
    e["tripod"] = bool(r.get("tripod_from")) and era >= r.get("tripod_from", 99)
    e["launcher_block"] = _pick(r.get("launcher_block", {}), era)
    # the magazine box: turns the weapon from a plain bar into an L. A shape
    # change survives downsampling better than a length change does, and it is
    # what makes the epoch 2->3 break visible at all.
    e["mag_drop"] = e["weapon_style"] in ("assault", "carbine", "bullpup")
    return e


ERAS = sorted(EPOCH_KIT)
FACTIONS = sorted(FACTION_KIT)

# ── the seven roles ────────────────────────────────────────────────
# Era and faction change the KIT and the weapon, never the skeleton.
def carried_weapon(arm, name, spec, mat):
    """Build everything held in the hands, in the POSED frame, then transform
    it back to rest.

    Rigid binding means anything on hand_r inherits every rotation between
    shoulder and hand — about -95 degrees of elbow at the ready. Modelling a
    rifle horizontal at rest therefore ships a soldier carrying it vertically
    over one shoulder, which is exactly what the first render showed.
    Authoring in the posed frame and inverting back through the skinning
    transform fixes it and leaves the rest pose clean for the bind.

    The axis is the line between the two hands rather than a guessed angle,
    which is what makes both hands actually land on the weapon.
    """
    l = spec["weapon_len"]
    bore = spec.get("weapon_bore", 0.06)
    style = spec.get("weapon_style", "assault")
    apply_pose(arm, {}, {})
    bpy.context.view_layer.update()
    apply_carry(arm)

    axis = (HAND_L_READY - HAND_R_READY).normalized()
    up = Vector((0.0, 0.0, 1.0))
    centre = HAND_R_READY + axis * (l * 0.5 - 0.20)
    q = Vector((0.0, -1.0, 0.0)).rotation_difference(axis)
    back = (arm.data.bones["hand_r"].matrix_local
            @ arm.pose.bones["hand_r"].matrix.inverted())

    pieces = [("weapon", centre, (bore, l, bore * 1.25))]

    # THE MAGAZINE. A box hanging below the receiver turns the weapon from a
    # plain horizontal bar into an L, and a SHAPE change survives downsampling
    # far better than a length change does. It is what makes the epoch 2->3
    # break visible at all, and it pays forward: every assault weapon from
    # there to epoch 7 has one, so "bar" versus "L" becomes a permanent
    # generational marker for the cost of a single box.
    if spec.get("mag_drop"):
        pieces.append(("mag", HAND_R_READY + axis * 0.10 - up * 0.105,
                       (0.026, 0.055, 0.170)))

    # A bullpup puts the action BEHIND the grip, so the receiver sits back
    # against the shoulder. The only national shape difference the silhouette
    # test said survives at this zoom.
    if style == "bullpup":
        pieces.append(("receiver", HAND_R_READY - axis * 0.06,
                       (bore * 1.5, 0.30, bore * 2.1)))

    if spec.get("optic_len", 0) > 0:
        pieces.append(("optic", HAND_R_READY + axis * 0.06
                       + up * (bore * 0.62 + 0.030),
                       (0.042, spec["optic_len"], 0.052)))

    # AT launchers: the sighting block is the tell, not the tube length. It
    # sits on the SIDE for the wire-guided generation and moves UNDERNEATH for
    # the fire-and-forget generation.
    lb = spec.get("launcher_block")
    if lb == "side":
        pieces.append(("tracker", HAND_R_READY + axis * 0.22
                       + Vector((0.13, 0.0, 0.02)), (0.13, 0.30, 0.12)))
    elif lb == "under":
        pieces.append(("clu", HAND_R_READY + axis * 0.20 - up * 0.115,
                       (0.13, 0.30, 0.13)))

    made = []
    for pname, c, size in pieces:
        o = _box(f"{name}_{pname}", c, size, mat, "hand_r")
        o.rotation_euler = q.to_euler()
        bpy.ops.object.transform_apply(rotation=True)
        o.data.transform(back)
        made.append(o)

    # Anything else held in a HAND needs exactly the same treatment. The mine
    # detector was first authored in rest space and shipped pointing at the
    # sky, for the same reason the rifle did: a rest-space box bound to a hand
    # inherits the whole arm rotation once the carry pose is applied.
    if spec.get("detector"):
        back_l = (arm.data.bones["hand_l"].matrix_local
                  @ arm.pose.bones["hand_l"].matrix.inverted())
        # a pole angled down and forward with a disc head near the ground -
        # an outline no other role or epoch in the game has
        for pname, c, size, rot in (
                ("det_pole", (-0.02, -0.72, 0.66), (0.030, 1.10, 0.030),
                 (math.radians(-32), 0.0, 0.0)),
                ("det_head", (-0.02, -1.20, 0.13), (0.32, 0.32, 0.035),
                 (0.0, 0.0, 0.0))):
            o = _box(f"{name}_{pname}", c, size, mat, "hand_l")
            o.rotation_euler = rot
            bpy.ops.object.transform_apply(rotation=True)
            o.data.transform(back_l)
            made.append(o)

    apply_pose(arm, {}, {})              # back to rest for the skin bind
    bpy.context.view_layer.update()
    return made


def role_kit_parts(spec):
    """Role gear that hangs off the body rather than the hands.

    These matter more than they look: role is the strongest of the three axes
    at RTS zoom, because it is the only one that puts a long object OUTSIDE the
    body outline where nothing can occlude it.
    """
    out = []
    if spec.get("antenna", 0) > 0:
        out.append(("antenna", "chest", (0.14, 0.15, 1.34 + spec["antenna"] * 0.5),
                    (0.016, 0.016, spec["antenna"])))
    if spec.get("tripod"):
        out.append(("tripod", "chest", (0, 0.14 + spec["pack"], 1.30),
                    (0.09, 0.09, 0.62)))
    if spec.get("baseplate"):
        out.append(("baseplate", "chest", (0, 0.16 + spec["pack"], 1.30),
                    (0.34, 0.05, 0.34)))
    if spec.get("tools") and not spec.get("detector"):
        out.append(("tools", "chest", (0.16, 0.09, 1.22), (0.07, 0.09, 0.29)))
    return out


def helmet_parts(spec, era):
    """Headgear. The single clearest generational tell infantry has, so the
    profiles are deliberately pushed past life to make them survive at 30 px.

    The read is mostly about the BRIM box and the NECK GAP:
      pot        brim all round; the head is the widest thing above the
                 shoulders, so the soldier reads as a narrow body with a
                 mushroom on top
      turtle     the same idea exaggerated much further (UK, epochs 1-2)
      dome       no brim at all (Soviet lineage: ru, cn, kp) - presence or
                 absence of the brim box is the most robust low-resolution
                 read available, and it is a LINEAGE cue, not a generation one
      composite  brim deleted, skirt closes the neck gap, so the head becomes
                 continuous with the shoulders - the inverse of the pot
      highcut    bare shell with the ears exposed, widened for ear cups, plus
                 a rear counterweight. That absence IS the read.
    """
    if not spec.get("helmet", True):
        return [("cap", "head", (0, 0.01, 1.765), (0.19, 0.21, 0.055))]
    w, d, h = spec["helmet_size"]
    z = 1.72 + h * 0.5
    shape = spec.get("helmet_shape", "pot")
    out = [("helmet", "head", (0, 0.01, z), (w, d, h))]
    if shape == "pot":
        out.append(("brim", "head", (0, 0.01, z - h * 0.44),
                    (w + 0.055, d + 0.055, 0.020)))
    elif shape == "turtle":
        out.append(("brim", "head", (0, 0.01, z - h * 0.40),
                    (w + 0.170, d + 0.110, 0.022)))
    elif shape == "composite":
        out.append(("skirt", "head", (0, 0.024, z - h * 0.50),
                    (w + 0.022, d + 0.014, 0.048)))
    elif shape == "highcut":
        out.append(("cwt", "head", (0, d * 0.50, z + h * 0.06),
                    (0.10, 0.055, 0.070)))
    # "dome" adds nothing on purpose - the bare shell is the whole point
    if spec.get("nvg"):
        out.append(("nvg", "head", (0, -d * 0.54, z + h * 0.12),
                    (0.070, 0.060, 0.055)))
    return out


def torso_parts(spec):
    """Chest, waist and back.

    The waist-to-chest inversion is the quiet half of the generational read and
    is worth as much as the armour: through epochs 1-4 the load rides on the
    BELT, so the widest point of the body is the hips. From epoch 5 it moves
    onto the chest and the belt narrows. A 1955 soldier is a triangle standing
    on its base; a 2015 soldier is the same triangle inverted.
    """
    out = []
    a = spec.get("torso_armour", 0.0)
    if a > 0.001:
        # the IOTV yoke squares off the shoulders; before it, armour follows
        # the ribs and stays narrower than the deltoids
        wide = 0.360 if spec.get("yoke") else 0.345
        out.append(("armour", "chest", (0, 0, 1.345),
                    (wide, 0.21 + a * 2.0, 0.315)))
    out.append(("webbing", "chest", (0, -0.105 - spec["webbing"] * 0.5, 1.285),
                (0.30, spec["webbing"], 0.135)))
    belt = spec.get("belt_bulk", 0.0)
    if belt > 0.004:
        out.append(("belt", "pelvis", (0, 0, 1.010),
                    (0.30 + belt * 2.0, 0.20 + belt * 2.0, 0.115)))
    pack = spec["pack"]
    # the ALICE frame reaches the shoulder line; a modern pack sits low and
    # square because the ammunition has moved to the front
    ph, pz = (0.44, 1.395) if spec.get("pack_tall") else (0.30, 1.345)
    out.append(("pack", "chest", (0, 0.115 + pack * 0.5, pz), (0.29, pack, ph)))
    return out


def build_rig(spec, era, faction, role, lod=0):
    """Skeleton plus one skinned mesh. No animation — see build_clip_library."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    cloth = _mat("cloth", spec["body"])
    gear = _mat("gear", tuple(c * 0.55 for c in spec["helmet_colour"]))
    helm = _mat("helm", spec["helmet_colour"])
    skin = _mat("skin", (0.50, 0.38, 0.30))

    arm = build_armature()
    name = f"inf_e{era}_{faction}_{role}"

    parts = list(BODY)
    parts += helmet_parts(spec, era)
    parts += torso_parts(spec)
    parts += role_kit_parts(spec)

    # LOD1 drops the small kit. At 276 triangles the saving is small — the real
    # cost of a crowd is draw calls and skinning, not geometry — so this exists
    # for pipeline consistency and to cut overdraw on tiny distant figures, and
    # there is deliberately no LOD2: a third level of a box character would be
    # dishonest bookkeeping rather than an optimisation.
    if lod >= 1:
        drop = ("nvg", "tools", "cwt", "hand_l", "hand_r",
                "shldr_l", "shldr_r", "mag")
        parts = [p for p in parts if p[0] not in drop]

    objs = []
    for pname, bone, centre, size in parts:
        if pname == "head":
            mat = skin
        elif pname in ("helmet", "brim", "skirt", "cap", "cwt"):
            mat = helm
        elif pname in ("torso", "hips") or pname.startswith(
                ("uarm", "larm", "thigh", "shin", "shldr", "hand")):
            mat = cloth
        else:
            mat = gear
        objs.append(_box(f"{name}_{pname}", centre, size, mat, bone))

    objs += carried_weapon(arm, name, spec, gear)

    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    body = bpy.context.object
    body.name = name
    body.parent = arm
    body.modifiers.new("Armature", "ARMATURE").object = arm
    return arm, body, name


def build_variant(era, faction, role, lod=0):
    spec = kit(era, faction, role)
    arm, body, name = build_rig(spec, era, faction, role, lod)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, f"{name}_LOD{lod}.glb")
    bpy.ops.object.select_all(action="DESELECT")
    body.select_set(True)
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB",
                              use_selection=True, export_yup=True,
                              export_animations=False, export_skins=True,
                              export_apply=False)
    return path, len(body.data.polygons) * 2


def build_clip_library():
    """The skeleton and every clip, once, with no mesh attached.

    docs/14 makes the whole infantry budget rest on one shared skeleton, and
    that only pays off if the clips are shared too. Embedding all eleven clips
    in each of 7 epochs x 8 factions x 7 roles would ship the same 150 KB of
    animation 392 times — about 60 MB of duplicated keyframes for geometry that
    is 276 triangles. Exporting the rig once and every variant mesh against the
    same bone names lets the engine bind one AnimationLibrary to all of them.
    """
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.render.fps = FPS
    arm = build_armature()
    meta = author_clips(arm)
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, "inf_rig_clips.glb")
    bpy.ops.object.select_all(action="DESELECT")
    arm.select_set(True)
    bpy.context.view_layer.objects.active = arm
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB",
                              use_selection=True, export_yup=True,
                              export_animations=True, export_nla_strips=True,
                              export_skins=True)
    with open(os.path.join(OUT, "clips.json"), "w") as f:
        json.dump(meta, f, indent=2, sort_keys=True)
    return path, meta


def roster():
    return [(e, f, r) for e in ERAS for f in FACTIONS
            for r in sorted(ROLE_KIT) if not locked(e, r)]


if __name__ == "__main__":
    import argparse
    ap = argparse.ArgumentParser()
    ap.add_argument("--clips-only", action="store_true")
    ap.add_argument("--era", type=int)
    ap.add_argument("--faction")
    ap.add_argument("--role")
    ap.add_argument("--lods", type=int, default=2)
    a = ap.parse_args([x for x in sys.argv[sys.argv.index("--") + 1:]]
                      if "--" in sys.argv else [])

    print("building infantry clip library...")
    cpath, meta = build_clip_library()
    print(f"  {os.path.basename(cpath)}  {len(meta)} clips, "
          f"{os.path.getsize(cpath) / 1024:.0f} KB")
    for k in sorted(meta):
        c = meta[k]
        s = f"{c['speed']:.2f} m/s" if c["speed"] else "static"
        slip = c.get("slip_mm")
        extra = f"  slip {slip:.3f} mm/frame" if slip is not None else ""
        print(f"    {k:14s} {c['frames']:3d}f  {s:>9s}{extra}")

    if a.clips_only:
        sys.exit(0)

    work = [w for w in roster()
            if (a.era is None or w[0] == a.era)
            and (a.faction is None or w[1] == a.faction)
            and (a.role is None or w[2] == a.role)]
    print(f"\nbuilding {len(work)} variant(s) x {a.lods} LOD(s)...")
    n = tris = 0
    for era, fac, role in work:
        for lod in range(a.lods):
            _, tr = build_variant(era, fac, role, lod)
            n += 1
            if lod == 0:
                tris += tr
    print(f"done - {n} files, {tris / max(1, len(work)):.0f} avg tris at LOD0")
