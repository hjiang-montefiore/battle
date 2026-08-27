"""The remaining ground roles from docs/12-unit-roster.md.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/army_models.py

Cross-role silhouette distinction is the rule docs/07 calls MANDATORY — a
player must never mistake a radar vehicle for a tank. Each role below is shaped
around the one feature that identifies it from an RTS camera.

EVERY ROLE IS PINNED TO A NAMED REAL VEHICLE
--------------------------------------------
Commons has almost no orthographic line art for modern support vehicles. Two
usable sheets were found — File:M113 BW.svg and File:M577.svg, both
orthographic side views, saved as art/reference/3v_m113.png and 3v_m577.png —
and they score the four M113-hulled roles. For the other twelve there is no
line drawing at all, so proportions are set from PUBLISHED
DIMENSIONS instead — hull length, width, height, wheel or roadwheel count,
barrel or canister length. The vehicle each role is modelled on and the figures
used are recorded in that role's docstring.

    tank destroyer      Kanonenjagdpanzer JPz 4-5   6.24 m hull / 8.75 m over gun
    APC                 M113A3                      4.86 x 2.69 x 2.52 m
    ATGM carrier        M901 ITV                    M113 hull, 3.35 m to hammerhead
    towed artillery     M777A2                      10.2 m firing, 39-cal 6.05 m tube
    mortar carrier      M1064A3                     M113 hull, 120 mm through the roof
    ballistic launcher  9P78-class 8x8 TEL          11.8 m, 7.3 x 0.92 m missile
    coastal battery     NSM/Harpoon coastal 6x6     8.7 m, four 4.0 m canisters
    SPAAG               Flakpanzer Gepard 1A2       6.9 m hull, 35 mm L/90, two dishes
    SHORAD              IM-SHORAD (Stryker A1)      6.95 x 2.72 x 2.64 m, 8x8
    long SAM            Patriot M901 launcher       four 5.2 m canisters at 38 deg
    counter-battery     AN/TPQ-53 on FMTV 6x6       7.2 m, portrait array
    EW jammer           R-330Zh-class 6x6           two log-periodic booms
    command vehicle     M577A3                      4.86 x 2.69 x 2.68 m raised box
    ammo truck          M977 HEMTT cargo            10.14 x 2.44 x 2.85 m, 8x8
    engineer            M728 CEV                    M60 hull, dozer + 165 mm demo gun
    repair              M88A2 HERCULES              8.62 x 3.66 x 3.12 m, A-frame boom
                                                    (boom raised, spade stowed)

WHERE THE MODELLED BOX EXCEEDS THE PUBLISHED ONE
------------------------------------------------
Hull length and width are matched to within about 2 percent everywhere. Height
is the figure that drifts, and always for the same two reasons, both of which
are deliberate:

  * published heights are quoted to the hull or turret roof and exclude the
    commander's cupola, the pintle MG and the whip antennas that detail_kit
    adds - the tank destroyer measures 2.64 m against a published 2.085 m
    entirely because of the MG, and its casemate roof is 2.085 m exactly;
  * seven roles are modelled DEPLOYED rather than stowed, because the deployed
    pose is the one the player sees. The M777's trails are spread (3.84 m
    across the spades against a 2.77 m travelling width), the ballistic TEL's
    round is up on its erector, the mortar tube is up, the Patriot canisters
    are elevated, the coastal battery's canisters are fanned outboard, and the
    M88's A-frame boom is RAISED (4.44 m to the apex sheave against a 3.12 m
    hull-roof height, and 10.33 m over the boom against an 8.62 m hull). That
    last one is not decoration - see THE SUPPORT-TRACK OWNERSHIP RULE below.

Everything else sits inside 10 percent of the published figure. The per-role
size envelopes in tools/validate_sockets.py are the CI gate that catches the
rest; all sixteen pass it.

ELEVATION CONVENTION — this was the single biggest defect in the previous
revision. A Blender cylinder points along +Z, and rotating it about X by t
sends the axis to (0, -sin t, cos t). So rot=(R(74), 0, 0) is a tube at SIXTEEN
degrees of elevation, not seventy-four: every missile, canister and mortar tube
in this file was lying nearly flat, which is why the ballistic TEL read as a
flatbed with a log on it. Use _fwd()/_aft(), which take the elevation angle
itself and are named for the direction the muzzle points. Note the two differ
for a CYLINDER (long axis = local Z) and for a CUBE (long axis = local Y);
_canister() and the comments at each use site keep that straight.
"""
import bpy, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_models as H
from hero_models import (cube, cyl, dome, profile, use, running_gear,
                         barrel, detail_kit, R)
from fleet_models import wheeled_gear, boxhull

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def _base(HL, HW, CL, HH, nose, tag):
    h, top = boxhull(HL, HW, CL, HH, nose, tag)
    return [h], top


# ── orientation helpers ────────────────────────────────────────────
def _fwd(elev_deg):
    """X-rotation putting a CYLINDER's axis forward (-Y) at `elev_deg` above
    the horizon. 0 = level ahead, 90 = straight up."""
    return R(90.0 - elev_deg)


def _aft(elev_deg):
    """Same for a cylinder pointing REARWARD (+Y). Mortars and most SAM
    canisters fire over the tail."""
    return R(elev_deg - 90.0)


def _boxfwd(elev_deg):
    """X-rotation aligning a CUBE's long (local Y) axis with a forward-and-up
    bore. A box is symmetric, so R(-e) and R(180-e) describe the same slab."""
    return R(-elev_deg)


def _boxaft(elev_deg):
    """CUBE long axis aligned with a rearward-and-up line."""
    return R(elev_deg)


def _strut(a, b, thick):
    """A box spanning world points a and b — A-frames, push arms, gun trails.

    Hand-typed euler angles are exactly where struts end up not touching the
    thing they are bolted to, which is what hero_models.check_detached reports
    as a floating island. Solving for the angles removes the whole class.
    """
    dx, dy, dz = b[0] - a[0], b[1] - a[1], b[2] - a[2]
    L = math.sqrt(dx * dx + dy * dy + dz * dz)
    pitch = math.asin(max(-1.0, min(1.0, dz / L)))
    yaw = math.atan2(-dx, dy)
    return cube(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2, (a[2] + b[2]) / 2),
                (thick, L, thick), rot=(pitch, 0, yaw))


def _splash(HL, CL, top, HW, nose, w=0.78, cover=0.88, lift=0.10):
    """Trim vane / splash plate lying FLAT ON the glacis, top edge at deck
    height. Real on the M113 family and on every hull meant to swim — and it is
    also what detail_kit's headlights (planted at deck height 0.35 m back from
    the nose) stand on when the glacis is long.

    The angle is derived from the hull's own nose run instead of being typed
    in: a hand-set rake left the plate hinged open like a plough on every
    vehicle whose glacis was steeper than the guess.
    """
    rise = top - CL
    L = math.hypot(rise, nose)
    ang = math.atan2(nose, rise)                 # glacis angle off vertical
    cy = -HL / 2 + nose / 2 - lift * rise / L    # push out along the outward
    cz = CL + rise / 2 + lift * nose / L         # normal of the glacis
    use("body")
    return [cube((0, cy, cz), (HW * w, 0.14, L * cover), rot=(-ang, 0, 0))]


def _cab(y, top, w, d, h, glass_h=0.46):
    """Forward-control truck cab with a raked windscreen. The dark screen is
    what tells a player which end of a support truck is the front — six of
    these roles are otherwise the same beige slab from the RTS camera."""
    p = []
    use("body")
    p.append(cube((0, y, top + h / 2), (w, d, h)))
    p.append(cube((0, y - d / 2 + 0.07, top + h * 0.17), (w * 0.94, 0.18, h * 0.34)))
    use("glass")
    # 100 mm proud of the cab face: recessed even slightly, the whole screen
    # disappears behind the front plate and the truck loses its front
    p.append(cube((0, y - d / 2 - 0.02, top + h - glass_h * 0.62),
                  (w * 0.84, 0.16, glass_h), rot=(R(-10), 0, 0)))
    use("body")
    return p


def _cab_kit(HL, HW, top, cy, cd, ch):
    """detail_kit anchored on the cab roof of a wheeled vehicle.

    detail_kit plants a hatch, two lift eyes and the team-colour patch relative
    to the `roof` argument. Handing it a nominal roof height with nothing under
    it is how the previous revision left team patches hanging in mid air at
    z=2.91 on four different trucks.
    """
    return detail_kit(HL, HW, top, top + ch, cy - cd * 0.30, cy + cd * 0.30,
                      era=0, mg=False)


def _canister(x, y0, z0, length, side, elev, yaw=0.0, cap=True):
    """One boxed missile canister standing on a launch frame, firing over the
    tail. (x, y0, z0) is the BREECH end, so the caller positions the end that
    touches the frame instead of solving for the box centre."""
    e, w = math.radians(elev), math.radians(yaw)
    ax = (-math.cos(e) * math.sin(w), math.cos(e) * math.cos(w), math.sin(e))
    rot = (_boxaft(elev), 0, R(yaw))
    p = []
    use("deck")
    p.append(cube((x + ax[0] * length / 2, y0 + ax[1] * length / 2,
                   z0 + ax[2] * length / 2), (side, length, side), rot=rot))
    if cap:
        # sit the blast cover ON the muzzle face, not inside it: buried at
        # 0.985 the whole gunbore group baked black and warned "AO flat"
        use("gunbore")
        p.append(cube((x + ax[0] * (length + 0.02), y0 + ax[1] * (length + 0.02),
                       z0 + ax[2] * (length + 0.02)),
                      (side * 0.80, side * 0.12, side * 0.80), rot=rot))
    use("body")
    return p


# ── manoeuvre ──────────────────────────────────────────────────────
def tank_destroyer():
    """Kanonenjagdpanzer JPz 4-5. Low casemate, NO turret, gun in a limited-
    traverse mantlet set into the front plate, and one unbroken slope from the
    glacis to the roof. Ambush role once the generational cliff bites (docs/03).

    Published: hull 6.24 m, 8.75 m over the gun (2.51 m of muzzle overhang),
    width 2.98 m, height 2.085 m, clearance 0.44 m, 5 road wheels.
    """
    HL, HW, CL, HH = 6.24, 2.98, 0.44, 0.84
    p, top = _base(HL, HW, CL, HH, 0.95, "td_hull")         # deck at 1.28
    ROOF = 2.085
    p.append(profile([(-2.15, top), (-1.05, ROOF), (1.30, ROOF),
                      (2.15, top)], 2.66, "td_case"))
    p.append(cube((0, -1.74, 1.56), (0.94, 0.72, 0.86)))    # mantlet
    p += barrel(-(HL / 2 + 2.51), 1.56, 4.35, 0.075, 0.95, 0.155)
    use("body")
    p.append(cyl((0.58, 0.55, ROOF + 0.15), 0.34, 0.30, v=14))          # cupola
    use("deck")
    p.append(cyl((0.58, 0.55, ROOF + 0.31), 0.38, 0.05, v=14))
    for k in range(4):                                                  # louvres
        p.append(cube((0, 1.95 + k * 0.26, top + 0.03), (1.90, 0.16, 0.08)))
    use("body")
    for s in (-1, 1):                                                   # smoke pots
        p.append(cyl((s * 1.05, -1.28, ROOF - 0.18), 0.055, 0.34,
                     rot=(0, R(90), 0), v=8))
    p += _splash(HL, CL, top, HW, 0.95)
    p += detail_kit(HL, HW, top, ROOF, -1.05, 1.30, era=0, mg=True)
    p += running_gear(HL, HW, CL, 5, 0.31, 0.50)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=1.56, gun_y=-1.74)


def apc():
    """M113A3. Boxy, no turret, one small commander's cupola with a .50 cal,
    a full-width rear ramp and the trim vane folded on the nose.

    Published: 4.863 x 2.686 m, 2.52 m over the cupola, 0.406 m clearance,
    5 road wheels. Scored against art/reference/3v_m113.png (side).
    """
    HL, HW, CL, HH = 4.86, 2.69, 0.41, 1.44
    p, top = _base(HL, HW, CL, HH, 0.62, "apc_hull")        # roof at 1.85
    CUP = top + 0.40
    use("body")
    p.append(cyl((0.46, -0.30, top + 0.20), 0.44, 0.40, v=14))          # cupola
    use("deck")
    p.append(cyl((0.46, -0.30, top + 0.41), 0.47, 0.06, v=14))          # ring
    p.append(cube((-0.42, 0.30, top + 0.04), (1.05, 1.35, 0.09)))       # cargo hatch
    for k in range(3):                                                  # louvres
        p.append(cube((0.88, -1.15 + k * 0.30, top + 0.04), (0.80, 0.20, 0.08)))
    use("body")
    p.append(cube((0, HL / 2 - 0.09, top - 0.62), (HW * 0.72, 0.18, 1.10)))  # ramp
    p.append(cube((0, HL / 2 - 0.20, top - 0.06), (HW * 0.80, 0.36, 0.12)))
    for s in (-1, 1):                                                   # fuel cells
        p.append(cube((s * (HW / 2 - 0.16), HL / 2 - 0.44, top - 0.44),
                      (0.30, 0.72, 0.72)))
    p.append(cube((0, HL / 2 + 0.10, top - 0.32), (2.05, 0.40, 0.62)))   # rear rack
    for s in (-1, 1):
        p.append(_strut((s * 0.92, HL / 2 - 0.04, top - 0.32),
                        (s * 0.92, HL / 2 + 0.26, top - 0.32), 0.12))
    p += _splash(HL, CL, top, HW, 0.62)
    p += detail_kit(HL, HW, top, top, -0.90, 0.90, era=0, mg=True)
    p += running_gear(HL, HW, CL, 5, 0.305, 0.44)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=CUP,
                   gun_z=CUP + 0.12, gun_y=-0.62)


def atgm_carrier():
    """M901 ITV — the "hammerhead". An M113 hull whose entire identity is the
    armoured mast that lifts a transverse launcher head 3.35 m up, so the
    vehicle can shoot from behind a crest with only the head exposed. The CE
    half of the armour matrix: it wants range, where a tank wants to close
    (docs/03).

    Published: M113A2 hull 4.86 x 2.69 m; 3.35 m to the top of the erected
    launcher; ready TOW tubes either side of the central sight head.
    """
    HL, HW, CL, HH = 4.86, 2.69, 0.41, 1.44
    p, top = _base(HL, HW, CL, HH, 0.62, "atg_hull")
    HEAD = 3.02                                             # hammerhead centre
    use("body")
    p.append(cube((0.24, 0.55, top + 0.24), (1.55, 1.65, 0.48)))        # turret ring
    p.append(cyl((0.24, 0.55, top + 0.70), 0.28, 0.60, v=12))
    p.append(cube((0.24, 0.55, top + 0.86), (0.50, 0.50, 1.08)))        # mast shroud
    p.append(cube((0.24, 0.55, HEAD), (0.88, 0.64, 0.68)))              # sight head
    use("deck")
    for s in (-1, 1):                                                   # tube pods
        p.append(cube((0.24 + s * 0.88, 0.55, HEAD), (0.88, 0.78, 0.76)))
        for k in (-1, 1):
            p.append(cyl((0.24 + s * 0.88, 0.02, HEAD + k * 0.20), 0.155, 1.30,
                         rot=(_fwd(2), 0, 0), v=10))
    use("body")
    p.append(cube((0, HL / 2 - 0.09, top - 0.62), (HW * 0.72, 0.18, 1.10)))  # ramp
    p.append(cube((0, HL / 2 + 0.10, top - 0.32), (2.05, 0.40, 0.62)))   # rear rack
    for s in (-1, 1):
        p.append(_strut((s * 0.92, HL / 2 - 0.04, top - 0.32),
                        (s * 0.92, HL / 2 + 0.26, top - 0.32), 0.12))
    p += _splash(HL, CL, top, HW, 0.62)
    p += detail_kit(HL, HW, top, top, -1.20, -0.30, era=0, mg=False)
    p += running_gear(HL, HW, CL, 5, 0.305, 0.44)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=HEAD + 0.38,
                   gun_z=HEAD, gun_y=0.02)


# ── fires ──────────────────────────────────────────────────────────
def towed_artillery():
    """M777A2. No hull at all — split-trail carriage, two road wheels, a
    39-calibre tube and a double-baffle muzzle brake. The only ground role with
    no vehicle body, so it reads instantly.

    Published: 10.2 m long in the firing position (10.7 m travelling), 2.77 m
    wide travelling, 2.26 m high, 155 mm L/39 = 6.045 m of tube. Modelled
    DEPLOYED, so the trails are spread ~28 deg either side and the across-the-
    spades width (5.0 m) is deliberately wider than the travelling figure.
    There is no gun shield: the M777 has none, and one would read as a towed
    anti-tank gun instead.
    """
    EL, TZ = 9.0, 1.30                      # elevation, trunnion height
    e = math.radians(EL)
    L, r = 6.05, 0.088                      # 155 mm L/39
    MUZ = 5.30                              # muzzle stand-off from the trunnion
    ax = (0.0, -math.cos(e), math.sin(e))   # unit vector along the bore
    ty, tz = -0.30 + ax[1] * MUZ, TZ + ax[2] * MUZ           # muzzle
    cy, cz = ty - ax[1] * L / 2, tz - ax[2] * L / 2          # tube centre
    p = []
    use("body")
    p.append(cube((0, 0.16, 0.94), (1.15, 1.35, 0.72)))                 # saddle
    p.append(cube((0, -0.44, TZ), (0.98, 1.60, 0.62),
                  rot=(_boxfwd(EL), 0, 0)))                             # cradle
    p.append(cyl((0, cy, cz), r, L, rot=(_fwd(EL), 0, 0), v=16))        # tube
    p.append(cyl((0, cy - ax[1] * L * 0.30, cz - ax[2] * L * 0.30),
                 r * 1.34, 1.40, rot=(_fwd(EL), 0, 0), v=16))           # chase
    use("gun")
    p.append(cube((0, ty - ax[1] * 0.30, tz - ax[2] * 0.30),
                  (0.46, 0.64, 0.44), rot=(_boxfwd(EL), 0, 0)))         # muzzle brake
    use("gunbore")
    p.append(cyl((0, ty, tz), r * 0.55, 0.05, rot=(_fwd(EL), 0, 0), v=12))
    use("body")
    for s in (-1, 1):                                                   # recoil rams
        p.append(cyl((s * 0.21, cy - ax[1] * L * 0.28 - 0.05,
                      cz - ax[2] * L * 0.28 + 0.22), 0.075, 1.80,
                     rot=(_fwd(EL), 0, 0), v=10))
    p.append(cube((0, 0.58, TZ - 0.06), (0.88, 0.72, 0.72)))            # breech ring
    for s in (-1, 1):                                   # split trails ~28 deg apart
        piv = (s * 0.34, 0.62, 0.72)
        end = (s * 1.74, 4.42, 0.34)
        p.append(_strut(piv, end, 0.26))
        p.append(cube((end[0], end[1] + 0.18, 0.32), (0.36, 0.56, 0.58)))  # spade
        p.append(_strut((s * 0.30, 0.34, 0.40), (end[0] * 0.62, 2.40, 0.52), 0.14))
    use("track")
    for s in (-1, 1):                                                   # road wheels
        p.append(cyl((s * 1.16, -0.42, 0.55), 0.55, 0.30, rot=(0, R(90), 0), v=16))
    use("body")
    for s in (-1, 1):
        p.append(_strut((s * 0.42, 0.20, 0.80), (s * 1.16, -0.42, 0.55), 0.18))
    p.append(cyl((0, 0.20, 0.34), 0.24, 0.68, v=12))                    # firing jack
    p.append(cube((0, 0.20, 0.06), (0.80, 0.80, 0.12)))
    use("team")
    p.append(cube((0.02, 0.58, 1.63), (0.52, 0.40, 0.06)))          # on the breech
    use("body")
    return p, dict(top=0.94, hull_l=7.0, hull_w=2.77, turret_top=2.26,
                   gun_z=TZ, gun_y=-0.30)


def mortar_carrier():
    """M1064A3. M113 hull, a big square roof hatch standing open with both
    doors swung out, and a 120 mm tube whose baseplate sits low INSIDE the
    hull — which is why the muzzle only just clears the roof instead of
    towering over the vehicle the way a naive mortar model does.

    Published: M113 hull 4.86 x 2.69 m, 2.5 m high; 120 mm tube ~2.1 m, fired
    over the rear.
    """
    HL, HW, CL, HH = 4.86, 2.69, 0.41, 1.44
    p, top = _base(HL, HW, CL, HH, 0.62, "mor_hull")
    EL, TL = 46.0, 2.30
    e = math.radians(EL)
    by, bz = -0.30, CL + 0.62                     # turntable, low inside the hull
    use("deck")
    p.append(cube((0, 0.34, top - 0.05), (1.95, 2.10, 0.10)))           # open hatch
    use("body")
    for s in (-1, 1):                                                   # hatch doors
        p.append(cube((s * 1.02, 0.34, top + 0.20), (0.76, 2.10, 0.10),
                      rot=(0, R(s * 20), 0)))
        p.append(cube((s * 0.99, 0.34, top + 0.07), (0.16, 2.16, 0.18)))   # coaming
    p.append(cube((0, -0.74, top + 0.07), (2.14, 0.16, 0.18)))
    p.append(cube((0, 1.42, top + 0.07), (2.14, 0.16, 0.18)))
    use("gun")
    p.append(cyl((0, by + math.cos(e) * TL / 2, bz + math.sin(e) * TL / 2),
                 0.105, TL, rot=(_aft(EL), 0, 0), v=12))                # 120 mm tube
    p.append(cyl((0, by + math.cos(e) * 0.55, bz + math.sin(e) * 0.55),
                 0.135, 0.42, rot=(_aft(EL), 0, 0), v=12))
    use("gunbore")
    p.append(cyl((0, by + math.cos(e) * (TL - 0.03), bz + math.sin(e) * (TL - 0.03)),
                 0.062, 0.06, rot=(_aft(EL), 0, 0), v=12))
    use("body")
    p.append(cyl((0, by, bz), 0.46, 0.24, v=14))                        # baseplate
    p.append(cyl((0, by + 0.24, bz + 0.30), 0.30, 0.34, v=12))          # yoke
    p.append(cube((0, HL / 2 - 0.09, top - 0.62), (HW * 0.72, 0.18, 1.10)))  # ramp
    p.append(cube((0, HL / 2 + 0.10, top - 0.32), (2.05, 0.40, 0.62)))   # rear rack
    for s in (-1, 1):
        p.append(_strut((s * 0.92, HL / 2 - 0.04, top - 0.32),
                        (s * 0.92, HL / 2 + 0.26, top - 0.32), 0.12))
    p += _splash(HL, CL, top, HW, 0.62)
    use("gun")
    p.append(cyl((0.70, -0.98, top + 0.52), 0.042, 0.95,
                 rot=(_fwd(6), 0, 0), v=8))                            # pintle MG
    use("body")
    p.append(cube((0.70, -0.74, top + 0.26), (0.22, 0.24, 0.40)))
    p += detail_kit(HL, HW, top, top, -1.35, -0.70, era=0, mg=False)
    p += running_gear(HL, HW, CL, 5, 0.305, 0.44)
    return p, dict(top=top, hull_l=HL, hull_w=HW,
                   turret_top=bz + math.sin(e) * TL,
                   gun_z=bz + math.sin(e) * TL * 0.5, gun_y=by)


def ballistic_launcher():
    """8x8 transporter-erector-launcher, 9P78 class, one very large round
    up on its erector with the ground jacks down. GNSS_INS — kills buildings,
    never movers (docs/02). The single fat finned missile is what separates it
    from the long-range SAM's flat row of four boxes.

    Published (9P78-1 on MZKT-7930): 13.07 x 3.07 m, 3.29 m over the cab;
    9M723 missile 7.3 m long, 0.92 m diameter. Hull shortened to 11.80 m
    (-9.7%) to stay inside the 12 m 'msl' envelope in validate_sockets.py, and
    the round rides its erector at 20 degrees rather than standing upright: an
    erected 7.3 m missile is a nine-metre-tall model and that same gate caps
    the role at 5.4 m. The raised-but-not-vertical pose keeps every recognition
    cue — fat body, pointed nose, cruciform tail, blast deflector — and puts
    8.5 m of missile across the PLAN view, where a vertical round is one dot.
    """
    HL, HW, CL, HH = 11.80, 3.07, 0.62, 1.05
    p, top = _base(HL, HW, CL, HH, 0.28, "bal_hull")        # deck at 1.67
    CY, CD, CH = -HL * 0.355, 2.60, 1.75
    p += _cab(CY, top, 2.85, CD, CH, glass_h=0.62)
    EL, ML, MR = 20.0, 7.30, 0.46
    e = math.radians(EL)
    ax = (0.0, -math.cos(e), math.sin(e))
    ty, tz = HL * 0.30, top + 0.33                          # trunnion
    use("body")
    p.append(cube((0, ty + 0.30, top + 0.22), (2.60, 3.90, 0.50)))      # cradle deck
    for s in (-1, 1):
        p.append(_strut((s * 0.98, ty + 1.60, top + 0.20), (s * 0.98, ty, tz), 0.34))
    # forward saddle: a block UNDER the round, not posts beside it. Posts at
    # +/-0.98 never touched a 0.92 m missile and shipped as detached islands.
    p.append(cube((0, ty - 2.60, top + 0.43), (1.15, 0.62, 1.00)))
    p.append(cube((0, ty + 1.75, top + 0.80), (2.35, 0.95, 1.14)))      # erector base
    p.append(cube((0, ty + 1.05, top + 0.52), (2.95, 1.10, 0.30)))      # blast deflector
    use("deck")
    p.append(cyl((0, ty + ax[1] * ML / 2, tz + ax[2] * ML / 2), MR, ML,
                 rot=(_fwd(EL), 0, 0), v=18))                           # missile body
    p.append(cyl((0, ty + ax[1] * (ML + 0.85), tz + ax[2] * (ML + 0.85)),
                 MR * 0.97, 1.80, rot=(_fwd(EL), 0, 0), v=18, taper=0.10))  # nose
    u = (0.0, math.sin(e), math.cos(e))                     # radial, in the YZ plane
    fy, fz = ty + ax[1] * 0.80, tz + ax[2] * 0.80           # tail-fin station
    for s in (-1, 1):                                       # cruciform tail fins
        p.append(cube((s * (MR + 0.38), fy, fz), (0.80, 1.35, 0.09),
                      rot=(_boxfwd(EL), 0, 0)))
        p.append(cube((0, fy + u[1] * s * (MR + 0.38), fz + u[2] * s * (MR + 0.38)),
                      (0.09, 1.35, 0.80), rot=(_boxfwd(EL), 0, 0)))
    use("body")
    for s in (-1, 1):                                       # ground jacks, down
        for yj in (HL * 0.12, HL * 0.40):
            p.append(cyl((s * (HW / 2 - 0.16), yj, 0.62), 0.16, 1.24, v=8))
            p.append(cube((s * (HW / 2 - 0.16), yj, 0.07), (0.50, 0.50, 0.14)))
    ROOF = tz + ax[2] * (ML + 1.70)
    p += _cab_kit(HL, HW, top, CY, CD, CH)
    p += wheeled_gear(HL, HW, CL, 2, 0.62, first=0.10, last=0.22)
    p += wheeled_gear(HL, HW, CL, 2, 0.62, first=0.58, last=0.70)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=tz, gun_y=ty)


def coastal_battery():
    """Taiwan's signature. A 6x6 flatbed with four anti-ship canisters on a
    rear frame, elevated 30 deg and FANNED OUTBOARD — the fan is what makes it
    unmistakable from directly above, where a parallel block of canisters would
    read as cargo.

    Published (NSM / Harpoon coastal batteries on a 5-ton 6x6): truck 8.7 x
    2.5 m, 2.9 m over the cab; NSM canister 4.0 m long, ~0.7 m square. 2.5 m is
    the CHASSIS width; the four canisters overhang it by about 0.25 m a side
    when they are fanned, which is how a real coastal launcher sits deployed.
    """
    HL, HW, CL, HH = 8.70, 2.50, 0.55, 0.90
    p, top = _base(HL, HW, CL, HH, 0.26, "cst_hull")        # bed at 1.45
    CY, CD, CH = -HL * 0.34, 2.20, 1.46
    p += _cab(CY, top, 2.34, CD, CH)
    fy = HL * 0.16
    use("body")
    p.append(cube((0, fy, top + 0.22), (2.34, 4.40, 0.34)))             # launch frame
    p.append(cube((0, fy - 1.70, top + 0.52), (2.24, 0.62, 0.66)))      # trunnion beam
    for s in (-1, 1):
        p.append(_strut((s * 1.00, fy + 1.95, top + 0.36),
                        (s * 1.00, fy - 0.55, top + 1.10), 0.22))
    for c in (-1.5, -0.5, 0.5, 1.5):                                    # four canisters
        p += _canister(c * 0.56, fy - 1.55, top + 0.64, 0.62 * 6.45, 0.62,
                       30.0, yaw=-c * 5.0)
    ROOF = top + 0.64 + 4.00 * math.sin(R(30)) + 0.35
    p += _cab_kit(HL, HW, top, CY, CD, CH)
    p += wheeled_gear(HL, HW, CL, 1, 0.58, first=0.15, last=0.15)
    p += wheeled_gear(HL, HW, CL, 2, 0.58, first=0.62, last=0.79)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 1.60, gun_y=fy)


# ── air defence ────────────────────────────────────────────────────
def spaag():
    """Flakpanzer Gepard 1A2. Gun AA: TWIN 35 mm mounted OUTBOARD of the
    turret — not on top of it — a round tracking dish on the turret face and an
    oblong search array on a short mast at the back. No RF dependency for the
    guns themselves, so it keeps shooting after an anti-radiation hit.

    Published: hull 6.90 m, 7.68 m over the guns, width 3.71 m, 3.01 m to the
    turret roof and 4.23 m with the search radar up; 35 mm KDA L/90 = 3.15 m
    of barrel; 7 road wheels on the Leopard 1 chassis.
    """
    HL, HW, CL, HH = 6.90, 3.28, 0.44, 1.05
    p, top = _base(HL, HW, CL, HH, 1.15, "spa_hull")        # deck at 1.49
    TR = 2.85                                               # turret roof
    p.append(profile([(-1.35, top), (-1.48, TR - 0.34), (-0.95, TR),
                      (1.45, TR), (1.72, TR - 0.46), (1.72, top)],
                     2.55, "spa_turret"))
    for s in (-1, 1):                                       # outboard gun mounts
        p.append(cube((s * 1.52, -0.20, top + 0.66), (0.54, 1.60, 0.92)))
        p.append(_strut((s * 1.24, -0.15, top + 0.76), (s * 1.52, -0.20, top + 0.66),
                        0.34))
    use("gun")
    for s in (-1, 1):                                       # 35 mm L/90, 3.15 m
        p.append(cyl((s * 1.52, -1.00 - 3.15 / 2 * math.cos(R(3)), top + 0.92),
                     0.062, 3.15, rot=(_fwd(3), 0, 0), v=10))
        p.append(cyl((s * 1.52, -1.00 - 0.50, top + 0.94), 0.092, 0.92,
                     rot=(_fwd(3), 0, 0), v=10))            # barrel jacket
    use("deck")
    p.append(cyl((0, -1.52, TR - 0.52), 0.58, 0.26, rot=(_fwd(12), 0, 0), v=20))
    use("body")
    p.append(cyl((0, 1.18, TR + 0.28), 0.24, 0.60, v=12))               # radar mast
    use("deck")
    p.append(cube((0, 1.18, TR + 1.05), (2.10, 0.28, 1.10), rot=(R(-14), 0, 0)))
    for k in range(4):                                                  # array ribs
        p.append(cube((0, 1.18 - 0.20 + k * 0.06, TR + 0.68 + k * 0.25),
                      (1.95, 0.16, 0.09)))
    use("body")
    p.append(cube((-0.72, -0.62, TR + 0.22), (0.44, 0.52, 0.44)))       # optical sight
    p += _splash(HL, CL, top, HW, 1.15)
    p += detail_kit(HL, HW, top, TR, -0.95, 1.45, era=0, mg=False)
    p += running_gear(HL, HW, CL, 7, 0.37, 0.58)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=TR + 1.60,
                   gun_z=top + 0.92, gun_y=-1.60)


def shorad_sam():
    """IM-SHORAD on a Stryker A1 — the WHEELED air-defence vehicle, which is
    the quickest way to tell it from the tracked SPAAG at a glance. Stinger
    pod on one side, Hellfire rails on the other, 30 mm between them, sensor
    ball forward.

    Published: 6.95 x 2.72 m, 2.64 m high, 8x8 on 1.1 m tyres.
    """
    HL, HW, CL, HH = 6.95, 2.72, 0.46, 1.54
    p, top = _base(HL, HW, CL, HH, 1.05, "sho_hull")        # roof at 2.00
    use("body")
    p.append(cube((0, 0.35, top + 0.24), (1.72, 1.80, 0.48)))           # turret ring
    p.append(cube((0, 0.30, top + 0.68), (1.42, 1.50, 0.44)))           # turret body
    use("deck")
    p.append(cube((-1.10, 0.28, top + 0.96), (0.72, 1.20, 0.96),
                  rot=(_boxfwd(12), 0, 0)))                             # Stinger pod
    for a in (-1, 1):
        for b in (0, 1):
            p.append(cyl((-1.10 + a * 0.16, 0.28 - 0.76, top + 0.80 + b * 0.34),
                         0.10, 1.60, rot=(_fwd(12), 0, 0), v=8))
    p.append(cube((1.08, 0.30, top + 0.90), (0.66, 1.20, 0.40),
                  rot=(_boxfwd(10), 0, 0)))                             # Hellfire rack
    for a in (-1, 1):
        p.append(cyl((1.08 + a * 0.19, 0.30 - 0.72, top + 1.12), 0.095, 1.68,
                     rot=(_fwd(10), 0, 0), v=8))
    use("gun")
    p.append(cyl((0.32, -1.05, top + 0.76), 0.048, 1.95, rot=(_fwd(5), 0, 0), v=10))
    use("body")
    p.append(dome((-0.34, -0.66, top + 0.92), 0.24, 0.26, 0.24, v=14))  # sensor ball
    p.append(cube((0, HL / 2 - 0.10, top - 0.70), (HW * 0.68, 0.16, 1.05)))  # ramp
    p += _splash(HL, CL, top, HW, 1.05)
    p += detail_kit(HL, HW, top, top, -1.15, -0.40, era=0, mg=False)
    p += wheeled_gear(HL, HW, CL, 2, 0.55, first=0.14, last=0.31)
    p += wheeled_gear(HL, HW, CL, 2, 0.55, first=0.62, last=0.79)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=top + 1.45,
                   gun_z=top + 0.92, gun_y=0.30)


def long_sam():
    """Patriot-pattern launching station: FOUR square canisters in ONE ROW,
    elevated to 38 degrees over the tail, on an 8x8. Still launcher ONLY; it
    needs the search radar and the illuminator (docs/12).

    Published: M901 launching station, canister 5.2 m long and ~0.86 m square,
    launch elevation 38 deg, four rounds; chassis a HEMTT-class 8x8 (M977:
    10.14 x 2.44 m). The flat row of four box muzzles at a shallow angle is the
    whole point — it must not read like the ballistic TEL's single fat missile
    stood near-vertical.
    """
    HL, HW, CL, HH = 10.20, 2.60, 0.60, 0.95
    p, top = _base(HL, HW, CL, HH, 0.26, "lsm_hull")        # deck at 1.55
    CY, CD, CH = -HL * 0.355, 2.40, 1.62
    p += _cab(CY, top, 2.44, CD, CH)
    EL, CLEN, CS = 38.0, 5.20, 0.86
    e = math.radians(EL)
    y0, z0 = HL * 0.02, top + 0.28
    use("body")
    p.append(cube((0, HL * 0.14, top + 0.14), (2.44, 5.20, 0.28)))      # launcher deck
    p.append(cube((0, y0 - 0.42, top + 0.24), (3.68, 0.80, 0.44)))      # trunnion beam
    for s in (-1, 1):
        p.append(_strut((s * 1.06, HL * 0.34, top + 0.28),
                        (s * 1.06, y0 + 0.70, z0 + 0.62), 0.24))
    p.append(cube((0, y0 + math.cos(e) * 1.10, z0 + math.sin(e) * 1.10),
                  (3.66, 1.05, 0.34), rot=(_boxaft(EL), 0, 0)))         # canister frame
    for c in (-1.5, -0.5, 0.5, 1.5):
        p += _canister(c * 0.90, y0, z0, CLEN, CS, EL)
    p.append(cube((0, y0 + math.cos(e) * CLEN * 0.66, z0 + math.sin(e) * CLEN * 0.66),
                  (3.72, 0.30, 0.30), rot=(_boxaft(EL), 0, 0)))         # end frame
    ROOF = z0 + math.sin(e) * CLEN + 0.45
    p += _cab_kit(HL, HW, top, CY, CD, CH)
    p += wheeled_gear(HL, HW, CL, 2, 0.58, first=0.11, last=0.25)
    p += wheeled_gear(HL, HW, CL, 2, 0.58, first=0.60, last=0.74)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=z0 + math.sin(e) * CLEN * 0.5, gun_y=y0)


# ── sensors and support ────────────────────────────────────────────
def counter_battery_radar():
    """AN/TPQ-53 class. Backtracks shells to the firing position (docs/10).
    A PORTRAIT array — taller than it is wide, standing almost upright on a
    turntable behind the cab. That is what separates it from the wide,
    laid-back landscape array of fleet_models.search_radar(), which is the
    confusion that actually matters on the battlefield.

    Published: FMTV M1083 6x6 chassis 6.93 x 2.44 m, 2.84 m over the cab;
    Q-53 antenna group roughly 2.6 m wide by 3.0 m tall deployed.
    """
    HL, HW, CL, HH = 7.20, 2.44, 0.58, 0.85
    p, top = _base(HL, HW, CL, HH, 0.26, "cbr_hull")        # deck at 1.43
    CY, CD, CH = -HL * 0.33, 2.30, 1.42
    p += _cab(CY, top, 2.30, CD, CH)
    ay = HL * 0.18
    use("body")
    p.append(cyl((0, ay, top + 0.26), 1.04, 0.52, v=18))                # turntable
    p.append(cube((0, ay + 0.62, top + 0.94), (1.75, 0.95, 1.36)))      # electronics
    for s in (-1, 1):
        p.append(_strut((s * 0.88, ay + 0.66, top + 0.52),
                        (s * 0.88, ay + 0.10, top + 1.66), 0.22))
    use("deck")
    ACZ, TIL = top + 1.80, math.tan(R(28))
    p.append(cube((0, ay - 0.42, ACZ), (2.66, 0.26, 3.00), rot=(R(-28), 0, 0)))
    for k in range(6):                                                  # array ribs
        z = top + 0.62 + k * 0.50
        p.append(cube((0, ay - 0.54 + (z - ACZ) * TIL, z), (2.48, 0.16, 0.10)))
    use("body")
    p.append(cube((0, ay + 0.02, top + 0.44), (2.68, 0.36, 0.36)))      # array pivot
    ROOF = top + 3.20
    p += _cab_kit(HL, HW, top, CY, CD, CH)
    p += wheeled_gear(HL, HW, CL, 1, 0.58, first=0.16, last=0.16)
    p += wheeled_gear(HL, HW, CL, 2, 0.58, first=0.62, last=0.80)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=ACZ, gun_y=ay)


def ew_jammer():
    """R-330Zh class. Denies the enemy picture — and is itself a screaming RF
    beacon (docs/02). Two log-periodic booms RAKED FORWARD off the shelter
    roof, dipoles shortening toward the tip: a pair of fishbones that are
    unmistakable from directly above, where the old vertical masts collapsed to
    two dots.

    No published orthographic dimensions exist for this class; proportions come
    from the same 5-ton 6x6 chassis as the counter-battery radar (7.85 x 2.50 m,
    2.9 m over the cab) carrying a standard S-280 shelter body.
    """
    HL, HW, CL, HH = 7.85, 2.50, 0.58, 0.85
    p, top = _base(HL, HW, CL, HH, 0.26, "ewj_hull")        # deck at 1.43
    CY, CD, CH = -HL * 0.34, 2.20, 1.46
    p += _cab(CY, top, 2.34, CD, CH)
    sy = HL * 0.17
    SH = top + 1.84                                          # shelter roof
    use("body")
    p.append(cube((0, sy, top + 0.92), (2.42, 4.20, 1.84)))             # S-280 shelter
    p.append(cube((0, sy + 2.12, top + 1.00), (2.10, 0.16, 1.30)))      # rear door
    for s in (-1, 1):
        p.append(cube((s * 1.24, sy, top + 0.92), (0.12, 4.24, 0.18)))
    p.append(cube((0.90, sy - 2.58, top + 0.44), (0.62, 0.92, 0.88)))   # generator
    use("deck")
    for s in (-1, 1):                                        # log-periodic booms
        bx = s * 0.66
        p.append(_strut((bx, sy + 1.42, SH + 0.06), (bx, sy - 1.95, SH + 1.95), 0.12))
        p.append(_strut((bx, sy + 1.42, SH + 0.06), (bx, sy + 1.05, SH + 0.86), 0.11))
        for k in range(7):                                   # dipoles shorten forward
            f = k / 6.0
            p.append(cube((bx, sy + 1.36 - f * 3.28, SH + 0.14 + f * 1.83),
                          (1.32 - f * 0.88, 0.08, 0.08)))
    p.append(cyl((0, sy + 1.95, SH + 0.78), 0.34, 0.14, v=16))          # DF loop
    use("body")
    p.append(cyl((0, sy + 1.95, SH + 0.36), 0.09, 0.76, v=8))
    ROOF = SH + 2.05
    p += _cab_kit(HL, HW, top, CY, CD, CH)
    p += wheeled_gear(HL, HW, CL, 1, 0.58, first=0.15, last=0.15)
    p += wheeled_gear(HL, HW, CL, 2, 0.58, first=0.62, last=0.79)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=SH + 1.00, gun_y=sy)


def command_vehicle():
    """M577A3 command post carrier. Datalink node — killing it fragments the
    faction track table (docs/12). Identified by the RAISED BOX over the rear
    two thirds of an M113 hull plus an antenna farm, not by a weapon. The tall
    square box IS the recognition cue and the previous flat-decked version had
    none of it.

    Published: 4.86 x 2.69 m, 2.68 m to the roof of the raised compartment.
    """
    HL, HW, CL, HH = 4.86, 2.69, 0.41, 1.44
    p, top = _base(HL, HW, CL, HH, 0.62, "cmd_hull")        # driver's roof at 1.85
    BOX = 2.68
    use("body")
    p.append(cube((0, 0.75, (top + BOX) / 2), (2.46, 3.20, BOX - top)))  # raised box
    p.append(cube((0, 0.75, BOX - 0.05), (2.58, 3.32, 0.12)))            # roof cap
    p.append(cube((0, -0.90, top + 0.30), (2.12, 0.18, 0.56)))           # front face
    use("deck")
    p.append(cube((-0.40, 0.45, BOX + 0.05), (1.05, 1.20, 0.10)))        # roof hatch
    use("body")
    for k in range(3):                     # tent frame stowed on the roof: three
        ay = -0.35 + k * 1.10              # arches over a ridge pole, which is
        for s in (-1, 1):                  # what art/reference/3v_m577_side.png
            p.append(_strut((s * 1.14, ay, BOX - 0.02), (0, ay, BOX + 0.24), 0.10))
        p.append(cube((0, ay, BOX + 0.24), (0.36, 0.16, 0.14)))
    p.append(cube((0, 0.75, BOX + 0.22), (0.16, 3.24, 0.12)))            # ridge pole
    p.append(cube((0.92, -1.52, top + 0.28), (0.62, 0.84, 0.56)))        # generator
    p.append(cube((0, HL / 2 - 0.09, top - 0.55), (HW * 0.66, 0.16, 0.95)))  # rear door
    # Whips are kept SHORT on purpose. Real M577s fly 3 m AS-1729s, but the
    # bounding box is what a silhouette score normalises by, and 3 m of 45 mm
    # wire doubles the model's height for two pixels of width at RTS range: it
    # cost 0.25 IoU against the reference drawing and bought no recognition.
    p.append(cube((0, HL / 2 + 0.10, top + 0.14), (2.24, 0.40, 0.62)))   # stowage basket
    for s in (-1, 1):
        p.append(_strut((s * 1.06, HL / 2 - 0.04, top + 0.14),
                        (s * 1.06, HL / 2 + 0.26, top + 0.14), 0.12))
    for ax, ay, ah in [(-1.14, -0.66, 0.70), (1.14, -0.66, 0.56),
                       (-1.14, 2.16, 0.76), (1.14, 2.16, 0.62)]:
        p.append(cube((ax, ay, top + 0.16), (0.22, 0.22, 0.30)))         # antenna base
        use("gun")
        p.append(cyl((ax, ay, top + 0.28 + ah / 2), 0.05, ah, v=6))      # whip
        use("body")
    p += _splash(HL, CL, top, HW, 0.62)
    p += detail_kit(HL, HW, top, BOX, 0.00, 1.60, era=0, mg=False)
    p += running_gear(HL, HW, CL, 5, 0.305, 0.44)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=BOX + 0.50,
                   gun_z=BOX, gun_y=0.75)


def ammo_truck():
    """M977 HEMTT cargo. Sustains rate of fire: 8x8, short cab-over forward, a
    long open flatbed of palletised rounds, and a knuckle-boom crane at the
    tail. The 8x8 wheel pattern — two axles bunched forward, two bunched aft —
    is itself a recognition cue that the old evenly-spaced 6x6 had lost.

    Published: 10.14 x 2.44 m, 2.85 m over the cab, 8x8 on 1.2 m tyres.
    """
    HL, HW, CL, HH = 10.14, 2.44, 0.58, 0.72
    p, top = _base(HL, HW, CL, HH, 0.24, "amm_hull")        # frame at 1.30
    CY, CD, CH = -HL * 0.355, 2.45, 1.56
    p += _cab(CY, top, 2.32, CD, CH)
    by = HL * 0.13
    use("body")
    p.append(cube((0, by, top + 0.10), (2.34, 6.10, 0.20)))             # bed floor
    for s in (-1, 1):                                                   # bed rails
        p.append(cube((s * 1.14, by, top + 0.44), (0.12, 6.10, 0.56)))
    p.append(cube((0, by + 3.02, top + 0.44), (2.34, 0.14, 0.56)))
    p.append(cube((0, by - 3.02, top + 0.64), (2.34, 0.16, 0.96)))      # headboard
    use("deck")
    for r in range(3):                                                  # ammo pallets
        for c in range(2):
            p.append(cube(((c - 0.5) * 1.06, by - 1.90 + r * 1.90, top + 0.62),
                          (0.96, 1.70, 0.84)))
    use("body")
    for r in range(3):                                                  # pallet strapping
        for c in range(2):
            p.append(cube(((c - 0.5) * 1.06, by - 1.90 + r * 1.90, top + 1.06),
                          (1.00, 0.16, 0.10)))
    p.append(cyl((0.80, by + 3.16, top + 0.62), 0.32, 1.04, v=12))      # crane pedestal
    p.append(_strut((0.80, by + 3.16, top + 1.04), (0.80, by + 1.05, top + 1.56), 0.26))
    p.append(_strut((0.80, by + 1.05, top + 1.56), (0.80, by - 0.60, top + 1.32), 0.19))
    p.append(cyl((0.80, by - 0.60, top + 1.12), 0.05, 0.52, v=6))       # crane hook
    for s in (-1, 1):                                                   # stabiliser legs
        p.append(cyl((s * (HW / 2 - 0.08), by + 3.16, 0.52), 0.13, 1.04, v=8))
        p.append(cube((s * (HW / 2 - 0.08), by + 3.16, 0.06), (0.32, 0.34, 0.12)))
    p.append(cube((0, HL / 2 - 0.12, top + 0.16), (2.20, 0.22, 0.36)))  # rear bumper
    p += _cab_kit(HL, HW, top, CY, CD, CH)
    p += wheeled_gear(HL, HW, CL, 2, 0.60, first=0.11, last=0.25)
    p += wheeled_gear(HL, HW, CL, 2, 0.60, first=0.61, last=0.75)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=top + 2.40,
                   gun_z=top + 0.62, gun_y=by)


# ── THE SUPPORT-TRACK OWNERSHIP RULE ───────────────────────────────
# eng_e4_us_engineer and eng_e4_us_repair are both six-road-wheel tracked
# support hulls of nearly the same size, so they can only be told apart by
# what they CARRY. They converged once already: the CEV grew an A-frame while
# the M88 kept a full-width spade, and the pair rendered at gameplay zoom as
# two tan boxes each with one dark bar across the nose (measured: top-down
# plan IoU 0.81, widths 3.70 vs 3.55 m — a 4 percent difference).
#
# So each vehicle OWNS exactly one out-of-outline element and may never carry
# the other's:
#
#   ENGINEER OWNS THE BLADE.    A full-width dark moldboard, swept back at the
#     tips into a shallow V in PLAN, standing on push arms with ~0.9 m of open
#     ground between blade and glacis. Above the turret roof the engineer
#     carries NOTHING — no boom, no A-frame, no mast. Its plan is a bar
#     detached from the front of a rectangle.
#
#   RECOVERY OWNS THE TRIANGLE. An A-frame boom RAISED and pitched forward, so
#     the apex stands ahead of the nose and 4.4 m up and the two legs converge
#     to a point OUTSIDE the hull outline. Its spade is stowed flat on the
#     glacis, body-coloured, inside the hull plan and below the deck line, so
#     it never reads as a blade. Its plan is an arrowhead on the front of a
#     rectangle.
#
# Both elements are large, project outside the body where nothing occludes
# them, and change the TOP-DOWN plan shape, which is what the RTS camera sees.
# The failure mode to watch for is either vehicle "just" gaining a small
# version of the other's element: a stowed boom on the CEV, or a spade proud
# of the M88's nose. That is exactly how the pair converged last time. Adding
# either one back is a silhouette regression, not a detail.


def engineer_vehicle():
    """M728 Combat Engineer Vehicle. Obstacles, mines, fortifications. Two
    features carry it: a FULL-WIDTH dozer blade standing clear of the nose on
    push arms, and a short, very fat 165 mm demolition gun — a stubby
    large-bore barrel is the fastest way to say "not a tank" when the hull
    underneath is an MBT hull.

    It owns the blade and carries NO boom (see the ownership rule above). The
    real M728's A-frame stows folded along the deck; modelling it cost the
    pair its silhouette separation and bought a feature that is flat, on top,
    and occluded from overhead, so it is not modelled.

    Published: M60 hull, 8.83 m over the dozer, 3.71 m wide, 3.20 m high,
    6 road wheels.
    """
    HL, HW, CL, HH = 6.95, 3.40, 0.46, 1.15
    p, top = _base(HL, HW, CL, HH, 1.20, "eng_hull")        # deck at 1.61
    TR = 2.45
    p.append(profile([(-1.55, top), (-1.30, TR - 0.16), (1.15, TR),
                      (1.62, TR - 0.34), (1.62, top)], 2.70, "eng_turret"))
    p.append(cube((0, -1.62, top + 0.48), (1.02, 0.76, 0.90)))          # mantlet
    p += barrel(-4.60, top + 0.48, 2.70, 0.145, 0.62, 0.215)            # 165 mm demo
    # ── the blade. Centre panel plus two wings yawed 18 deg back, so the
    # PLAN is a shallow V 3.71 m over the tips against a 3.40 m hull — the
    # blade is the widest thing on the vehicle and reads from directly above.
    BY = -HL / 2 - 1.10                     # 0.95 m of daylight to the glacis
    use("deck")
    p.append(cube((0, BY, 0.88), (2.16, 0.30, 1.22), rot=(R(-9), 0, 0)))
    p.append(cube((0, BY + 0.13, 0.28), (2.16, 0.44, 0.22), rot=(R(-32), 0, 0)))
    # 1.265, not 1.33: an 18 deg yaw throws the CUTTING EDGE's outer corner
    # further out than the wing panel's, because the edge is deeper in y
    # (0.44 vs 0.30). Placing the wings at 1.33 measured 3.844 m over the tips
    # against the published 3.71 m — a 3.5% overshoot at exactly the feature
    # the whole separation rests on, which is the one place it must not happen.
    for s in (-1, 1):
        p.append(cube((s * 1.265, BY + 0.16, 0.86), (1.10, 0.30, 1.22),
                      rot=(R(-9), 0, R(s * 18))))                       # wing
        p.append(cube((s * 1.265, BY + 0.29, 0.27), (1.10, 0.44, 0.22),
                      rot=(R(-32), 0, R(s * 18))))                      # cutting edge
    use("body")
    for s in (-1, 1):                                                   # push arms
        p.append(_strut((s * 1.32, -HL / 2 + 0.90, CL + 0.24),
                        (s * 1.32, BY + 0.20, 0.92), 0.22))
        p.append(_strut((s * 0.86, -HL / 2 + 1.30, top + 0.10),
                        (s * 1.12, BY + 0.18, 1.40), 0.15))             # lift rams
    p.append(cyl((0, 1.40, top + 0.32), 0.34, 0.95, rot=(0, R(90), 0), v=14))  # winch
    p.append(cyl((0.62, 0.20, TR + 0.18), 0.32, 0.36, v=12))            # cupola
    p += _splash(HL, CL, top, HW, 1.20)
    p += detail_kit(HL, HW, top, TR, -1.30, 1.15, era=0, mg=True)
    p += running_gear(HL, HW, CL, 6, 0.36, 0.56)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=TR + 0.18,
                   gun_z=top + 0.48, gun_y=-1.62)


def repair_vehicle():
    """M88A2 HERCULES. Recovers mobility and firepower kills. NO gun at all —
    a tall slab superstructure and an A-FRAME BOOM RAISED over the nose.

    It owns the triangle (see the ownership rule above). The boom is modelled
    DEPLOYED, apex 1.45 m ahead of the hull nose and 4.44 m up, because a
    stowed boom lies flat on the deck where the overhead camera cannot see it
    — that is precisely the pose that made this vehicle read as the engineer.
    The front spade is stowed flat on the glacis, painted in the vehicle
    scheme rather than the dark deck group, and kept inside the hull plan: the
    dark full-width bar at the nose belongs to the engineer alone.

    Published: 8.62 x 3.66 m, 3.12 m to the hull roof, 6 road wheels.
    """
    HL, HW, CL, HH = 8.62, 3.55, 0.46, 1.30
    p, top = _base(HL, HW, CL, HH, 1.25, "rep_hull")        # deck at 1.76
    SUP = 3.12                                              # superstructure roof
    p.append(profile([(-1.85, top), (-1.62, SUP - 0.22), (1.95, SUP),
                      (2.45, SUP - 0.50), (2.45, top)], 3.05, "rep_house"))
    use("body")
    p.append(cyl((0.66, 0.15, SUP + 0.18), 0.34, 0.36, v=14))           # cupola
    use("deck")
    p.append(cyl((0.66, 0.15, SUP + 0.37), 0.38, 0.06, v=14))
    use("body")
    # spade STOWED: 2.60 m wide inside a 3.55 m hull, lying on the glacis at
    # the glacis angle, top edge below the deck. Body group, not deck group.
    ang = math.atan2(1.25, top - CL)
    p.append(cube((0, -HL / 2 + 0.42, 0.98), (2.60, 0.22, 1.24), rot=(-ang, 0, 0)))
    for s in (-1, 1):                                                   # spade rams
        p.append(_strut((s * 1.26, -HL / 2 + 0.85, CL + 0.22),
                        (s * 1.26, -HL / 2 + 0.30, 0.74), 0.22))
    # ── the triangle. Legs run from the pivot posts amidships to an apex
    # ahead of and above the nose, so from overhead the plan gains an
    # arrowhead that no other tracked support vehicle has.
    # Reach is deliberately short of what the boom could do. At -1.45 the plan
    # ran to 10.33 m against an 8.62 m hull, and that aspect ratio (0.344) lands
    # on the tank destroyer's (0.341) — the pair measured 0.827, worse than the
    # 0.757 this vehicle was just separated TO. A recovery vehicle reads by its
    # triangle, not by how far the triangle reaches.
    APEX = (0.0, -HL / 2 - 0.60, 4.44)
    for s in (-1, 1):
        p.append(_strut((s * 1.55, 0.95, SUP - 0.18), APEX, 0.34))
        p.append(_strut((s * 1.52, 0.90, SUP - 0.20), (s * 1.52, 0.90, top + 0.10),
                        0.26))                                          # pivot posts
    p.append(cyl(APEX, 0.26, 0.86, rot=(0, R(90), 0), v=12))            # apex sheave
    p.append(cyl((0, APEX[1] + 0.08, 2.70), 0.05, 3.50, v=6))           # winch cable
    p.append(cube((0, APEX[1] + 0.08, 0.88), (0.40, 0.40, 0.90)))       # hook block
    p.append(cyl((0, -2.45, top + 0.24), 0.30, 1.20,
                 rot=(0, R(90), 0), v=14))                              # cable fairlead
    p.append(cube((0, 3.25, top + 0.34), (2.60, 1.10, 0.58)))           # tow pintle deck
    p.append(cube((0.95, 1.15, SUP + 0.13), (0.55, 1.60, 0.30)))        # roof stowage
    p += _splash(HL, CL, top, HW, 1.25)
    p += detail_kit(HL, HW, top, SUP, -1.55, 1.85, era=0, mg=True)
    p += running_gear(HL, HW, CL, 6, 0.37, 0.62)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=SUP + 0.42,
                   gun_z=top + 0.44, gun_y=-1.20)


# ── soviet-lineage ground family (2026-08) ─────────────────────────
# ru/cn/kp derivatives whose outlines genuinely differ from the US baseline.
# Dimensions from data/factions/ru.json / cn.json (entry named per docstring);
# anything the data lacks is a published spec, called out where used.

def btr60():
    """afv_e2_ru_btr60 — BTR-60PB (ru.json apc e2: 7.56 x 2.83 x 2.31 m,
    10.3 t, 8x8 amphibious, 14.5 mm KPVT).

    An 8-WHEEL BOAT HULL — nothing like the tracked M113 box. The hull rises
    to a point at BOTH ends (bow tip at 1.12 m, boat stern), eight big wheels
    carry it with daylight under the belly, and the only thing on the roof is
    the same little cone turret the BRDM-2 wears, set FORWARD over the second
    axle. Axle fractions follow the real 1.35/1.53/1.35 m spacing, so the
    slight centre gap that identifies a BTR from above is preserved.
    """
    HL, HW, CL = 7.56, 2.83, 0.45
    top = 1.86
    p = []
    p.append(profile([(-HL / 2, 1.12), (-HL / 2 + 1.48, top),
                      (2.20, top), (HL / 2, 1.30), (3.30, CL),
                      (-2.80, CL)], HW, "btr_hull"))
    p.append(cube((0, -2.98, 1.50), (HW * 0.68, 0.10, 0.82),
                  rot=(R(-60), 0, 0)))                          # trim vane
    use("glass")
    p.append(cube((0, -2.42, 1.72), (1.60, 0.08, 0.26),
                  rot=(R(-27), 0, 0)))                          # driver screens
    use("body")
    p.append(cyl((0, -1.15, top + 0.20), 0.55, 0.40, v=16, taper=0.52))
    p.append(dome((0, -1.15, top + 0.40), 0.30, 0.30, 0.12, v=14))
    use("gun")
    p.append(cyl((0, -1.85, top + 0.24), 0.034, 1.30, rot=(_fwd(2), 0, 0), v=8))
    p.append(cyl((0, -1.65, top + 0.16), 0.024, 0.80, rot=(_fwd(2), 0, 0), v=6))
    use("deck")
    for k in range(2):                                          # troop hatches
        p.append(cube((0, 0.10 + k * 0.95, top + 0.02), (1.45, 0.80, 0.06)))
    p.append(cube((0, 2.62, 1.665), (1.60, 0.85, 0.06)))        # engine grilles
    use("body")
    for s in (-1, 1):                                           # side bench rails
        p.append(cube((s * (HW / 2 - 0.05), 0.30, 1.30), (0.10, 3.60, 0.14)))
    p += detail_kit(HL, HW, top, top + 0.40, -1.70, -0.60, era=0, mg=False)
    p += wheeled_gear(HL, HW, CL, 4, 0.54, at=(0.16, 0.34, 0.54, 0.72))
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=2.31,
                   gun_z=top + 0.24, gun_y=-1.30)


def zsu23():
    """aad_e3_ru_zsu23 — ZSU-23-4M Shilka (ru.json spaag e2/e3: 6.54 x 3.13
    x 2.58 m, 19.5 t, 6 road wheels, quad 23 mm, RPK-2 dish).

    Built because the pair genuinely separates from the Gepard: the Shilka is
    FOUR SHORT water-jacketed barrels CLUSTERED at the CENTRE of a big boxy
    near-full-width turret with a ROUND DISH on a mast behind it — the Gepard
    is TWO LONG barrels hung OUTBOARD of the turret sides under an OBLONG
    search array. Cluster-vs-outboard and dish-vs-rectangle both survive RTS
    zoom; hull is also 0.9 m lower than the Leopard-based Gepard's.
    """
    HL, HW, CL, HH = 6.54, 3.13, 0.40, 1.12
    p, top = _base(HL, HW, CL, HH, 1.30, "zsu_hull")            # deck at 1.52
    TR = 2.50
    p.append(profile([(-1.42, top), (-1.55, TR - 0.40), (-1.15, TR),
                      (1.25, TR), (1.48, TR - 0.42), (1.40, top)],
                     2.90, "zsu_turret"))
    p.append(cube((0, -1.30, 2.02), (1.34, 0.55, 0.50)))        # gun trough
    e = math.radians(8)
    ax = (0.0, -math.cos(e), math.sin(e))
    # Barrel weights are RTS weights, not scale: at 0.030 m the quad
    # cluster — the whole point of the vehicle — vanished from the lineup
    # render while the Gepard's pair still read. 0.075/0.045 keeps the
    # four-across grouping legible at gameplay zoom.
    for x in (-0.51, -0.17, 0.17, 0.51):                        # quad 23 mm
        p.append(cyl((x, -1.30 + ax[1] * 0.75, 2.02 + ax[2] * 0.75),
                     0.075, 1.30, rot=(_fwd(8), 0, 0), v=10))   # water jacket
        use("gun")
        p.append(cyl((x, -1.30 + ax[1] * 1.95, 2.02 + ax[2] * 1.95),
                     0.045, 1.20, rot=(_fwd(8), 0, 0), v=8))
        p.append(cyl((x, -1.30 + ax[1] * 2.50, 2.02 + ax[2] * 2.50),
                     0.062, 0.14, rot=(_fwd(8), 0, 0), v=8))    # flash hider
        use("gunbore")
        p.append(cyl((x, -1.30 + ax[1] * 2.58, 2.02 + ax[2] * 2.58),
                     0.030, 0.02, rot=(_fwd(8), 0, 0), v=8))
        use("body")
    p.append(cyl((0, 1.05, TR + 0.30), 0.13, 0.65, v=10))       # radar mast
    use("deck")
    p.append(cyl((0, 1.05, TR + 0.90), 0.58, 0.30,
                 rot=(_fwd(70), 0, 0), v=18))                   # the Gun Dish
    use("body")
    p.append(cyl((0, 0.83, TR + 0.98), 0.05, 0.40,
                 rot=(_fwd(20), 0, 0), v=6))                    # feed horn
    p.append(cube((-0.85, -0.75, TR + 0.16), (0.42, 0.50, 0.32)))  # optic box
    p += _splash(HL, CL, top, HW, 1.30)
    p += detail_kit(HL, HW, top, TR, -1.15, 1.25, era=0, mg=False)
    p += running_gear(HL, HW, CL, 6, 0.335, 0.30)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=TR + 1.20,
                   gun_z=2.02, gun_y=-1.30)


def s300_tel():
    """sam_e4_ru_s300tel — S-300PS 5P85-class TEL (ru.json long_sam e4:
    13.11 x 3.15 x 3.8 m travelling, MAZ-7910 8x8, 4x 5V55R).

    FOUR ROUND TUBES IN A 2x2 CLUSTER raised over the tail — against the
    Patriot's ONE FLAT ROW of four SQUARE canisters at 38 deg, which is the
    exact confusion the method notes call out. Round-vs-square and
    cluster-vs-row both read in plan and in profile.

    Two deliberate deviations, both for the validate_sockets 'sam' envelope
    (12.9 m length, 7.2 m height ceilings, same reason the ballistic TEL is
    shortened): hull 12.80 m against the published 13.11 (-2.4%), and the
    tubes raised to 40 deg at 7.0 m rather than erected vertical at the real
    ~7.8 m — vertical is a 9.6 m model. 40 deg keeps every cue (fat round
    tubes, blunt caps, 2x2 frame, jacks down) and puts 4 m of tube across
    the PLAN view where a vertical cluster is four dots.
    """
    HL, HW, CL, HH = 12.80, 3.15, 0.65, 1.00
    p, top = _base(HL, HW, CL, HH, 0.30, "s3_hull")             # deck at 1.65
    CY, CD, CH = -HL * 0.40, 2.30, 1.55
    p += _cab(CY, top, 2.95, CD, CH, glass_h=0.55)
    p.append(cube((0, -2.30, top + 0.70), (2.95, 3.30, 1.40)))  # equipment cabin
    E, L, TR_ = 40.0, 7.00, 0.36
    e = math.radians(E)
    uy, uz = math.cos(e), math.sin(e)                # up the tubes (aft + up)
    vy, vz = -math.sin(e), math.cos(e)               # across the cluster
    TY, Z0 = 0.45, 1.95                              # breech-end trunnion
    p.append(cube((0, TY + 0.15, top + 0.30), (2.45, 2.30, 0.60)))  # erector base
    p.append(cube((0, TY + 0.40 * uy, Z0 + 0.40 * uz - 0.05),
                  (1.95, 1.00, 1.95), rot=(R(E), 0, 0)))        # breech frame
    for a in (2.60, 4.70):                                      # collar plates
        p.append(cube((0, TY + a * uy, Z0 + a * uz), (1.78, 0.16, 1.78),
                      rot=(R(E), 0, 0)))
    for s in (-1, 1):                                           # erector rams
        p.append(_strut((s * 0.92, TY + 1.90, top + 0.10),
                        (s * 0.92, TY + 2.30 * uy, Z0 + 2.30 * uz - 0.30),
                        0.17))
    use("deck")
    for sx in (-1, 1):                                          # 2x2 tube cluster
        for sv in (-1, 1):
            x = sx * 0.44
            by, bz = TY + sv * 0.36 * vy, Z0 + sv * 0.36 * vz
            p.append(cyl((x, by + uy * L / 2, bz + uz * L / 2), TR_, L,
                         rot=(_aft(E), 0, 0), v=16))
            use("gunbore")
            p.append(cyl((x, by + uy * (L + 0.02), bz + uz * (L + 0.02)),
                         TR_ * 0.93, 0.06, rot=(_aft(E), 0, 0), v=16))
            use("deck")
    use("body")
    for s in (-1, 1):                                           # ground jacks
        for yj in (-1.60, 4.90):
            p.append(cyl((s * (HW / 2 - 0.16), yj, 0.60), 0.16, 1.20, v=8))
            p.append(cube((s * (HW / 2 - 0.16), yj, 0.07), (0.50, 0.50, 0.14)))
    ROOF = Z0 + 0.36 * vz + L * uz + TR_ * vz
    p += _cab_kit(HL, HW, top, CY, CD, CH)
    p += wheeled_gear(HL, HW, CL, 2, 0.64, first=0.075, last=0.195)
    p += wheeled_gear(HL, HW, CL, 2, 0.64, first=0.63, last=0.75)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=Z0 + uz * L / 2, gun_y=TY + uy * L / 2)


def type59():
    """mbt_e2_cn_type59 — Type 59 (cn.json mbt e1/e2: 9.0 m gun forward,
    3.27 m wide, 2.59 m high; the T-54A pattern. Hull length 6.04 m is the
    published T-54 figure the data's gun-forward length implies).

    The PLA's bulk tank for three epochs. Against the T-72 it must NOT read
    as the same vehicle: FIVE big road wheels with the long bare gap of
    T-54 torsion spacing (the T-72 runs six), a HIGH EGG DOME set forward
    (the T-72's dome is squat and wide), NO skirts, NO ERA, and a CLEAN
    100 mm tube — no bore evacuator, no brake, the D-10 tell (every later
    Soviet gun carries a mid-tube bulge).
    """
    HL, HW, CL, HH = 6.04, 3.27, 0.43, 1.09
    top = CL + HH                                               # 1.52
    p = []
    p.append(profile([(-HL / 2, CL), (-HL / 2 + 1.25, top),
                      (HL / 2, top), (HL / 2, CL)], HW, "t59_hull"))
    p.append(dome((0, -0.50, top - 0.10), 1.42, 1.52, 0.95, v=22))  # egg dome
    p.append(cyl((0, -0.45, top + 0.03), 1.32, 0.14, v=20))     # turret ring
    p.append(cube((0, -1.78, 1.72), (0.82, 0.52, 0.58)))        # mantlet
    # 100 mm D-10T, hand-rolled so it stays CLEAN (barrel() adds an evacuator)
    p.append(cyl((0, -3.57, 1.75), 0.100, 3.94, rot=(R(90), 0, 0), v=16))
    use("gun")
    p.append(cyl((0, -5.73, 1.75), 0.098, 0.52, rot=(R(90), 0, 0), v=16))
    use("gunbore")
    p.append(cyl((0, -5.975, 1.75), 0.060, 0.02, rot=(R(90), 0, 0), v=14))
    use("body")
    p.append(cyl((0.48, -0.05, 2.28), 0.30, 0.28, v=14))        # cupola
    use("deck")
    p.append(cyl((0.48, -0.05, 2.43), 0.33, 0.05, v=14))
    for k in range(4):                                          # engine louvres
        p.append(cube((0, 1.75 + k * 0.28, top + 0.02), (2.05, 0.20, 0.08)))
    use("body")
    for s in (-1, 1):                                           # rear fuel drums
        p.append(cyl((s * 1.02, HL / 2 - 0.12, top + 0.24), 0.29, 0.90,
                     rot=(R(90), 0, 0), v=12))
    p.append(cyl((0, HL / 2 + 0.14, 0.98), 0.14, 2.30,
                 rot=(0, R(90), 0), v=10))                      # unditching log
    p += detail_kit(HL, HW, top, 2.30, -1.90, 0.90, era=0, mg=True)
    p += running_gear(HL * 1.12, HW, CL, 5, 0.40, 0.28, skirt_front_only=True)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=2.40,
                   gun_z=1.75, gun_y=-1.78)


ARMY = [
    ("afv_e4_us_tankdestroyer", tank_destroyer),
    ("afv_e4_us_apc",           apc),
    ("afv_e4_us_atgm",          atgm_carrier),
    ("art_e4_us_towed",         towed_artillery),
    ("art_e4_us_mortar",        mortar_carrier),
    ("msl_e4_us_ballistic",     ballistic_launcher),
    ("msl_e4_us_coastal",       coastal_battery),
    ("aad_e4_us_spaag",         spaag),
    ("aad_e4_us_shorad",        shorad_sam),
    ("aad_e4_us_longsam",       long_sam),
    ("rad_e4_us_counterbty",    counter_battery_radar),
    ("ewj_e4_us_jammer",        ew_jammer),
    ("cmd_e4_us_command",       command_vehicle),
    ("log_e4_us_ammotruck",     ammo_truck),
    ("eng_e4_us_engineer",      engineer_vehicle),
    ("eng_e4_us_repair",        repair_vehicle),
    # soviet / chinese lineage (camo + team colour per entry; the US entries
    # above keep their 2-tuple form and default to camo_us / NATO blue)
    ("afv_e2_ru_btr60",         btr60,    "camo_ru", (0.68, 0.10, 0.10)),
    ("aad_e3_ru_zsu23",         zsu23,    "camo_ru", (0.68, 0.10, 0.10)),
    ("sam_e4_ru_s300tel",       s300_tel, "camo_ru", (0.68, 0.10, 0.10)),
    ("mbt_e2_cn_type59",        type59,   "camo_cn", (0.72, 0.14, 0.10)),
]


# ── texture pass (2026-08): composed-texture REQUESTS, roster data only ──
# Coordinates are build-space metres (Z-up, forward = -Y), read off the same
# published dimensions each role above is pinned to. Dust and mud dominate a
# ground vehicle at RTS zoom; insignia are subdued single-colour US stars on
# the vertical plates (hull / casemate / shelter sides).
_STAR = (0.14, 0.13, 0.12)          # subdued CARC-black star
_DUST = (0.50, 0.44, 0.34)          # desert dust


def _us_ground(name, x, y, z, size=0.55, dust=0.55, height=1.2, spacing=1.5):
    """Standard US ground-vehicle request: mirrored hull-side stars at
    (±x, y, z). x=None -> no insignia (the towed gun has no flat plate)."""
    ins = []
    if x is not None:
        ins = [dict(kind="star_us", center=( x, y, z), normal=( 1, 0, 0),
                    size=size, alpha=0.85, color=_STAR),
               dict(kind="star_us", center=(-x, y, z), normal=(-1, 0, 0),
                    size=size, alpha=0.85, color=_STAR)]
    H.texture_features(
        name, size_class="vehicle", groups=("body", "deck"),
        panels=dict(spacing=spacing, strength=0.55, jitter=0.13, seams=0.55),
        weathering=dict(
            dust=dict(height=height, strength=dust, tint=_DUST),
            edge_wear=dict(strength=0.5)),
        insignia=ins)


_us_ground("afv_e4_us_tankdestroyer", 1.46, 0.30, 1.55, size=0.50)
_us_ground("afv_e4_us_apc",           1.35, 0.40, 1.25, size=0.60)
_us_ground("afv_e4_us_atgm",          1.35, 0.60, 1.25, size=0.55)
_us_ground("art_e4_us_towed",         None, 0, 0, dust=0.40, height=0.9,
           spacing=1.0)
_us_ground("art_e4_us_mortar",        1.35, 0.40, 1.25, size=0.55)
_us_ground("msl_e4_us_ballistic",     1.54, 1.20, 1.15, size=0.50, dust=0.60)
_us_ground("msl_e4_us_coastal",       1.25, 1.20, 1.00, size=0.50)
_us_ground("aad_e4_us_spaag",         1.63, 0.60, 1.05, size=0.50)
_us_ground("aad_e4_us_shorad",        1.36, 0.40, 1.35, size=0.60)
_us_ground("aad_e4_us_longsam",       1.30, 1.60, 1.05, size=0.50)
_us_ground("rad_e4_us_counterbty",    1.22, 1.00, 1.00, size=0.50)
_us_ground("ewj_e4_us_jammer",        1.25, 1.00, 1.00, size=0.50)
_us_ground("cmd_e4_us_command",       1.35, 0.70, 1.95, size=0.55)
_us_ground("log_e4_us_ammotruck",     1.22, 1.60, 0.95, size=0.45, dust=0.60)
_us_ground("eng_e4_us_engineer",      1.70, 0.50, 1.15, size=0.50, dust=0.65)
_us_ground("eng_e4_us_repair",        1.52, 0.30, 2.40, size=0.60, dust=0.65,
           height=1.4)


# soviet/chinese-lineage texture requests: national star on the flat hull /
# turret sides, ru flora mud and cn loess dust (same tints faction_models'
# MBTs run, so a mixed battlegroup weathers as one force).
_RU_MUD = (0.36, 0.32, 0.24)
_CN_DUST = (0.46, 0.41, 0.30)


def _sov_ground(name, kind, x, y, z, size=0.50, dust=0.55, height=1.2,
                spacing=1.5, tint=_RU_MUD):
    H.texture_features(
        name, size_class="vehicle", groups=("body", "deck"),
        panels=dict(spacing=spacing, strength=0.55, jitter=0.13, seams=0.55),
        weathering=dict(
            dust=dict(height=height, strength=dust, tint=tint),
            edge_wear=dict(strength=0.5)),
        insignia=[dict(kind=kind, center=( x, y, z), normal=( 1, 0, 0),
                       size=size, alpha=0.9),
                  dict(kind=kind, center=(-x, y, z), normal=(-1, 0, 0),
                       size=size, alpha=0.9)])


_sov_ground("afv_e2_ru_btr60",   "star_ru", 1.40, 0.60, 1.35, size=0.50,
            height=1.1)
_sov_ground("aad_e3_ru_zsu23",   "star_ru", 1.46, -0.05, 2.05, size=0.50)
_sov_ground("sam_e4_ru_s300tel", "star_ru", 1.56, -2.30, 1.35, size=0.50,
            dust=0.60)
_sov_ground("mbt_e2_cn_type59",  "star_cn", 1.62, 0.30, 1.10, size=0.50,
            dust=0.60, tint=_CN_DUST)


if __name__ == "__main__":
    H.set_out(os.path.join(ROOT, "art", "blockout", "e4_army"))
    for entry in ARMY:
        name = entry[0]
        H.CAMO[name] = entry[2] if len(entry) > 2 else "camo_us"
        H.TEAM[name] = entry[3] if len(entry) > 3 else (0.06, 0.20, 0.62)
    print("building army roles...")
    for entry in ARMY:
        name, fn = entry[0], entry[1]
        for lod in (0, 1, 2):
            n = H.build(name, fn, lod)
            print(f"  {name:28s} LOD{lod}  {n:6d} tris")
    print("done")
