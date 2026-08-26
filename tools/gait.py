"""Parametric biped gait. Pure maths, no Blender — so it can be unit-tested.

    python3 tools/gait.py            # self-check: foot slip and leg reach

WHY THIS EXISTS AS ITS OWN MODULE
---------------------------------
docs/14-animation.md calls foot sliding the single most noticeable animation
failure at any zoom, and infantry is where it shows: a tank that skates reads as
a tank on ice, but a soldier that skates reads as broken. A sine wave on the
thigh bone always slides, because it never asks where the foot actually is.

So this inverts the usual authoring order. Instead of posing joints and hoping
the foot lands somewhere plausible, it places the CONTACT POINT on the ground
first and solves the leg to reach it:

    1. pick which part of the foot is bearing weight right now
       (heel -> whole foot -> ball, over the course of one stance)
    2. that point is world-stationary, so in body-local space it travels
       backward at exactly the body speed
    3. derive the ankle from the contact point and the foot's pitch
    4. two-bone IK for hip and knee

Zero slip is then a property of the construction, not something to tune. What is
left to check is REACH: a stride longer than the leg can span forces a clamp,
and the clamp is where slip sneaks back in. `fit_stride` measures that and
shortens the stride until nothing clamps.

THE CLIP/GAME CONTRACT
----------------------
Every clip publishes the speed it was built for. The game plays it at

    rate = unit_speed / clip.speed

Stride length is fixed in the mesh; scaling the rate scales time only, so the
foot's local velocity scales with the body's and the no-slip property survives
at any speed. This is why the clip must ship its reference speed and why the
game must never drive infantry locomotion from a wall-clock timer.

GEOMETRY (metres, 1.8 m soldier, forward is -Y, up is +Z)
"""
import math

L_THIGH = 0.42          # hip joint -> knee joint
L_SHIN = 0.40           # knee joint -> ankle joint
REACH = (L_THIGH + L_SHIN) * 0.995      # never fully lock the knee

# foot landmarks, relative to the ankle joint, foot at rest (flat, toes -Y)
HEEL = (0.0, +0.07, -0.08)
BALL = (0.0, -0.13, -0.08)
TOE = (0.0, -0.19, -0.08)

HIP_X = 0.09            # half hip width


def rot_x(v, a):
    """Rotate about world +X by a. +a carries +Y toward +Z."""
    _, y, z = v
    return (v[0], y * math.cos(a) - z * math.sin(a),
            y * math.sin(a) + z * math.cos(a))


def solve_leg(hip, ankle):
    """Two-bone IK in the sagittal plane. Returns (hip_flexion, knee_flexion,
    reach_ratio) with flexion positive forward, angles in radians.

    reach_ratio > 1 means the target was unreachable and got clamped — which is
    exactly the condition that reintroduces foot slip, so callers must check it.
    """
    dx = ankle[0] - hip[0]
    dy = ankle[1] - hip[1]
    dz = ankle[2] - hip[2]
    d = math.sqrt(dx * dx + dy * dy + dz * dz)
    ratio = d / REACH
    d = min(d, REACH)
    d = max(d, abs(L_THIGH - L_SHIN) + 1e-4)

    # direction of the hip->ankle line, measured from straight down,
    # positive toward -Y (forward)
    psi = math.atan2(-dy, -dz)
    # the knee sits forward of that line by beta
    cb = (L_THIGH * L_THIGH + d * d - L_SHIN * L_SHIN) / (2 * L_THIGH * d)
    beta = math.acos(max(-1.0, min(1.0, cb)))
    ck = (L_THIGH * L_THIGH + L_SHIN * L_SHIN - d * d) / (2 * L_THIGH * L_SHIN)
    knee = math.pi - math.acos(max(-1.0, min(1.0, ck)))
    return psi + beta, knee, ratio


class Gait:
    """One locomotion cycle.

    speed       m/s the clip is authored for
    stride      m of ground covered per full cycle (two steps)
    duty        fraction of the cycle each foot spends on the ground.
                >0.5 means double support exists — that IS walking.
                <0.5 means a flight phase exists — that IS running.
    contact     'heel_toe' (walk: heel strike, roll, push off the ball)
                'forefoot' (run/sprint: land on the ball, never heel down)
    """

    def __init__(self, speed, stride, duty, hip_h, contact="heel_toe",
                 clearance=0.055, bob=0.045, sway=0.022, pelvis_rot=0.07,
                 chest_rot=0.09, lean=0.0, bob_invert=False, stance_bias=0.0,
                 step_width=0.13):
        self.speed = speed
        self.stride = stride
        self.duty = duty
        self.hip_h = hip_h
        self.contact = contact
        self.clearance = clearance
        self.bob = bob
        self.sway = sway
        self.pelvis_rot = pelvis_rot
        self.chest_rot = chest_rot
        self.lean = lean
        self.bob_invert = bob_invert
        # Fraction of the contact travel to shift the whole stance rearward.
        # Landing with the foot well ahead of the hip is over-striding: it
        # brakes, and it is the pose that over-extends the knee. Real runners
        # touch down almost under the centre of mass and push off long behind.
        self.stance_bias = stance_bias
        # distance between the two footfall lines. Runners track narrower than
        # walkers, close to single-file at sprint pace.
        self.step_width = step_width

    # ── body ───────────────────────────────────────────────────────
    def pelvis(self, phi):
        """Pelvis offset and rotation at cycle phase phi, keyed to the LEFT leg.

        Walking is lowest at double support and highest at mid-stance, because
        the body vaults over a straight leg. Running is the opposite: the stance
        leg compresses like a spring, so the low point is mid-stance and the
        high point is the flight phase. Getting that inversion wrong makes a run
        read as a fast walk.
        """
        s = -1.0 if self.bob_invert else 1.0
        dz = s * (self.bob * 0.5) * -math.cos(4 * math.pi * phi)
        dx = -self.sway * math.sin(2 * math.pi * phi)
        # transverse rotation: the swinging hip leads
        yaw = -self.pelvis_rot * math.sin(2 * math.pi * phi)
        return dx, dz, yaw

    def hip(self, phi, side):
        """World position of one hip joint, after pelvis motion."""
        dx, dz, yaw = self.pelvis(phi)
        x0 = HIP_X * side
        return (dx + x0 * math.cos(yaw),
                x0 * math.sin(yaw),
                self.hip_h + dz)

    # ── foot ───────────────────────────────────────────────────────
    def _pivot(self, u):
        """Which landmark is bearing weight, and where it is in body space.

        The sole is RIGID — a combat boot has no toe joint — and that single
        fact determines everything here. Pivot about the ball with the toes
        pointing down and the toe tip goes through the ground; pivot about the
        heel with the toes up and the heel does. So:

            toes down (plantarflexed)  ->  pivot on the TOE
            toes up   (dorsiflexed)    ->  pivot on the HEEL
            flat                       ->  either; both are on the ground

        Whichever it is, that point is world-stationary, so in body space it
        travels backward at exactly the body speed. The two landmarks are a
        fixed 0.26 m apart along the sole, which keeps the handover continuous
        at the moment the foot passes through flat.
        """
        travel = self.stride * self.duty
        if self.contact == "heel_toe" and u < 0.62:
            return HEEL, self.f0 - travel * u
        span = HEEL[1] - TOE[1]                 # toe is this far forward of heel
        return TOE, self.f0 + span - travel * u

    def _pitch(self, u):
        """Ankle angle through stance. Positive is plantarflexion, toes down."""
        if self.contact == "heel_toe":
            roll, heel_off = 0.10, 0.62
            if u < roll:                        # heel strike rolling to flat
                return -0.21 * (1 - u / roll)
            if u < heel_off:                    # foot flat
                return 0.0
            k = (u - heel_off) / (1 - heel_off)  # heel lifts, push off the toe
            return 0.58 * k * k
        # forefoot strike: land toes-down, let the heel settle toward the
        # ground under load, then drive off. Never a heel contact at all, which
        # is what makes a run silhouette bounce rather than stride.
        return 0.30 - 0.26 * math.sin(math.pi * min(1.0, u * 1.05)) \
            + 0.42 * u * u

    def _stance(self, u):
        """Stance, u in [0,1). Returns (ankle_forward, ankle_z, plantarflex).

        Derived from the contact point outward: the pivot is on the ground and
        world-stationary, and the ankle is wherever the rigid foot puts it.
        """
        pf = self._pitch(u)
        mark, f_mark = self._pivot(u)
        a = rot_x(mark, pf)
        return f_mark + a[1], -a[2], pf

    def _swing(self, u):
        """Swing, u in [0,1). Ankle arcs from toe-off back to touchdown."""
        f_end, z_end, pf_end = self._stance(0.9999)
        f_start, z_start, pf_start = self._stance(0.0)
        # ease out of push-off, ease into touchdown
        k = u * u * (3 - 2 * u)
        f = f_end + (f_start - f_end) * k
        lift = self.clearance * math.sin(math.pi * (u ** 0.85))
        z = z_end + (z_start - z_end) * k + lift
        # the ankle unwinds from push-off, then cocks up for touchdown
        pf = pf_end * (1 - min(1.0, u * 2.2)) + pf_start * k
        return f, z, pf

    def foot(self, phi, side):
        """Ankle position and foot pitch for one leg at cycle phase phi.

        The lateral placement is FIXED, at half the step width either side of
        the midline. It deliberately does not follow the pelvis: the pelvis
        sways over a stationary foot, the foot does not slide sideways under a
        swaying pelvis. Tying the two together put the whole sway amplitude
        into the planted foot as lateral drift — about 5 mm per frame — and
        because the sway is a smooth sinusoid it never looked like a bug in
        isolation, it just quietly skated.

        Step width is narrower than the hips (0.13 m against 0.18 m), which is
        why walking needs a little hip adduction and why the 3-DOF hip solve
        has to exist at all.
        """
        p = (phi + (0.0 if side < 0 else 0.5)) % 1.0
        if p < self.duty:
            f, z, pf = self._stance(p / self.duty)
            planted = True
        else:
            f, z, pf = self._swing((p - self.duty) / (1 - self.duty))
            planted = False
        return (side * self.step_width * 0.5, -f, z), pf, planted

    # ── stride fitting ─────────────────────────────────────────────
    @property
    def f0(self):
        """Forward position of the heel at touchdown, chosen so the ankle's
        excursion is centred under the body. An off-centre stance makes the
        soldier look like it is leaning into or away from its own direction.

        Solved by probing _stance with the offset zeroed, so `is None` — not a
        truthiness test — has to gate the cache: the answer is legitimately 0.0
        for a symmetric gait, and `or` would treat that as "not computed yet"
        and recurse forever.
        """
        if getattr(self, "_f0", None) is None:
            self._f0 = 0.0
            a = self._stance(0.0)[0]
            b = self._stance(0.9999)[0]
            self._f0 = -(a + b) * 0.5 - self.stance_bias * self.stride * self.duty
        return self._f0

    def worst_reach(self, samples=120):
        w = 0.0
        for i in range(samples):
            phi = i / samples
            for side in (-1, 1):
                ankle, _, _ = self.foot(phi, side)
                _, _, r = solve_leg(self.hip(phi, side), ankle)
                w = max(w, r)
        return w

    def fit_stride(self, limit=0.985, tries=40):
        """Shrink the stride until no frame clamps the IK.

        A clamped frame is a frame where the foot cannot reach where the
        contract says it must be — which is precisely a sliding frame. Rather
        than accept it, give up stride length: a slightly shorter step at the
        same cadence is invisible, a sliding foot is not.
        """
        for _ in range(tries):
            self._f0 = None
            if self.worst_reach() <= limit:
                return True
            self.stride *= 0.97
            self.speed *= 0.97
        return False

    def slip(self, fps=30):
        """Max world-space movement of the weight-bearing contact point, mm.

        This is the number that matters. The body advances speed/fps each frame;
        a planted contact point must move back by exactly that much in body
        space. Anything left over is the foot skating across the ground.
        """
        n = max(4, round(self.stride / self.speed * fps))
        dt = (self.stride / self.speed) / n
        worst = 0.0
        for side in (-1, 1):
            prev = prev_mark = None
            for i in range(n + 1):
                phi = (i % n) / n
                p = (phi + (0.0 if side < 0 else 0.5)) % 1.0
                ankle, pf, planted = self.foot(phi, side)
                if not planted:
                    prev = prev_mark = None
                    continue
                u = p / self.duty
                mark, _ = self._pivot(u)
                off = rot_x(mark, pf)
                # the body advances toward -Y, so a world-stationary point has
                # world_y = local_y - speed*t
                world_x = ankle[0] + off[0]
                world_y = ankle[1] + off[1] - self.speed * (i * dt)
                world_z = ankle[2] + off[2]
                if prev is not None and mark is prev_mark:
                    worst = max(worst, math.dist((world_x, world_y, world_z),
                                                 prev))
                prev, prev_mark = (world_x, world_y, world_z), mark
        return worst * 1000.0


# ── the locomotion set ─────────────────────────────────────────────
# hip_h is the hip JOINT height, not the pelvis centre. Standing it sits near
# 0.90 on a 1.8 m soldier; every gait here runs slightly lower because a locked
# knee cannot absorb ground contact and reads as a stilt walk.
def build_gaits():
    g = {
        # cautious patrol pace, weapon up. The slowest thing infantry does
        # while still covering ground, and the pose most often seen.
        "walk": Gait(1.25, 1.20, 0.62, 0.845, clearance=0.050,
                     bob=0.040, sway=0.022, pelvis_rot=0.06, chest_rot=0.075),
        # crouched: lower, shorter, flatter. Presents a smaller target and the
        # silhouette has to say so from directly above.
        "walk_crouch": Gait(0.80, 0.78, 0.68, 0.660, step_width=0.17,
                            clearance=0.040,
                            bob=0.022, sway=0.026, pelvis_rot=0.04,
                            chest_rot=0.05, lean=0.30),
        # combat move: flight phase, forefoot landing, weapon still controlled
        "run": Gait(3.30, 2.36, 0.28, 0.830, contact="forefoot", step_width=0.09,
                    clearance=0.135, bob=0.075, sway=0.016, pelvis_rot=0.10,
                    chest_rot=0.13, lean=0.13, bob_invert=True,
                    stance_bias=0.10),
        # dash for cover: weapon drops to one hand, free arm pumps
        "sprint": Gait(5.20, 3.40, 0.21, 0.815, contact="forefoot", step_width=0.06,
                       clearance=0.185, bob=0.095, sway=0.012, pelvis_rot=0.13,
                       chest_rot=0.17, lean=0.26, bob_invert=True,
                       stance_bias=0.14),
    }
    for k in g:
        g[k].fit_stride()
    return g


if __name__ == "__main__":
    print(f"{'clip':14s} {'speed':>7s} {'stride':>7s} {'duty':>5s} "
          f"{'reach':>6s} {'slip':>8s}")
    ok = True
    for name, gait in build_gaits().items():
        r, s = gait.worst_reach(), gait.slip()
        flag = "" if (r <= 0.99 and s < 1.0) else "   <-- CHECK"
        if flag:
            ok = False
        print(f"{name:14s} {gait.speed:6.2f}m/s {gait.stride:6.2f}m "
              f"{gait.duty:5.2f} {r:6.3f} {s:7.3f}mm{flag}")
    print("\nslip is per-frame world movement of the planted contact point")
    print("PASS" if ok else "FAIL")
