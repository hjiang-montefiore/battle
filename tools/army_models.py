"""The remaining ground roles from docs/12-unit-roster.md.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/army_models.py

Cross-role silhouette distinction is the rule docs/07 calls MANDATORY — a
player must never mistake a radar vehicle for a tank. Each role below is shaped
around the one feature that identifies it from an RTS camera.
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


# ── manoeuvre ──────────────────────────────────────────────────────
def tank_destroyer():
    """Low casemate, no turret, very long gun. Ambush role once the
    generational cliff bites (docs/03)."""
    HL, HW, CL, HH = 6.60, 3.15, 0.42, 0.88
    p, top = _base(HL, HW, CL, HH, 1.95, "td_hull")
    ROOF = top + 0.62
    p.append(profile([(-2.30, top), (-1.90, ROOF), (1.35, ROOF),
                      (1.70, top)], 2.55, "td_case"))
    p += barrel(-(HL / 2 + 3.60), top + 0.34, 4.60, 0.106, 1.60, 0.150)
    p += detail_kit(HL, HW, top, ROOF, -2.30, 1.70, era=0, mg=False)
    p += running_gear(HL, HW, CL, 6, 0.30, 0.46)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 0.34, gun_y=-2.30)


def apc():
    """Boxy, no turret, one small cupola. Carries infantry only."""
    HL, HW, CL, HH = 6.40, 3.05, 0.44, 1.35
    p, top = _base(HL, HW, CL, HH, 1.50, "apc_hull")
    ROOF = top + 0.42
    p.append(cyl((0.42, -0.35, top + 0.21), 0.42, 0.42, v=14))
    p.append(cube((0, HL * 0.42, top - 0.45), (HW * 0.74, 0.14, 0.86)))   # ramp
    use("deck")
    p.append(cube((0, HL * 0.30, top + 0.02), (1.85, 1.20, 0.08)))
    use("body")
    p += detail_kit(HL, HW, top, ROOF, -0.60, 0.60, era=0, mg=True)
    p += running_gear(HL, HW, CL, 5, 0.29, 0.48)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 0.30, gun_y=-0.60)


def atgm_carrier():
    """APC hull with an elevating missile rack. The CE half of the armour
    matrix — wants range, where a tank wants to close (docs/03)."""
    HL, HW, CL, HH = 5.90, 2.95, 0.42, 1.22
    p, top = _base(HL, HW, CL, HH, 1.45, "atg_hull")
    ROOF = top + 1.05
    use("deck")
    p.append(cube((0, 0.30, top + 0.62), (2.30, 1.05, 0.72), rot=(R(-22), 0, 0)))
    for c in range(4):
        p.append(cyl((-0.78 + c * 0.52, 0.05, top + 0.86), 0.16, 1.55,
                     rot=(R(68), 0, 0), v=10))
    use("body")
    p.append(cube((0, 0.30, top + 0.20), (1.30, 0.90, 0.40)))
    p += detail_kit(HL, HW, top, ROOF, -0.40, 0.80, era=0, mg=False)
    p += running_gear(HL, HW, CL, 5, 0.28, 0.44)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 0.86, gun_y=0.05)


# ── fires ──────────────────────────────────────────────────────────
def towed_artillery():
    """No hull at all — split-trail carriage, wheels, long barrel. The only
    ground role with no vehicle body, so it reads instantly."""
    p = []
    use("body")
    p.append(cube((0, 0.10, 1.05), (1.30, 1.60, 0.55)))              # cradle
    for s in (-1, 1):                                                 # split trails
        p.append(cube((s * 0.85, 2.30, 0.55), (0.20, 4.10, 0.24),
                      rot=(R(4), 0, R(-s * 11))))
        p.append(cube((s * 1.28, 4.20, 0.34), (0.30, 0.55, 0.30)))    # spade
    p.append(cube((0, -0.55, 1.35), (1.10, 0.70, 0.62)))              # breech
    p += barrel(-6.30, 1.35, 5.10, 0.092, 1.30, 0.132)
    use("deck")
    p.append(cyl((0, -1.90, 1.42), 0.36, 0.70, rot=(R(90), 0, 0), v=14))
    use("track")
    for s in (-1, 1):
        p.append(cyl((s * 1.32, 0.10, 0.66), 0.66, 0.34, rot=(0, R(90), 0), v=16))
    use("body")
    p.append(cube((0, 0.10, 1.72), (2.40, 0.14, 0.90), rot=(R(-18), 0, 0)))  # shield
    return p, dict(top=1.10, hull_l=7.0, hull_w=2.9, turret_top=2.20,
                   gun_z=1.35, gun_y=-1.20)


def mortar_carrier():
    """APC hull, open roof, near-vertical tube."""
    HL, HW, CL, HH = 5.80, 2.90, 0.42, 1.30
    p, top = _base(HL, HW, CL, HH, 1.40, "mor_hull")
    ROOF = top + 1.30
    use("deck")
    p.append(cube((0, 0.35, top + 0.06), (2.05, 2.30, 0.10)))         # open roof
    use("gun")
    p.append(cyl((0, 0.35, top + 0.85), 0.098, 1.70, rot=(R(14), 0, 0), v=12))
    use("body")
    p.append(cube((0, 0.35, top + 0.18), (0.70, 0.70, 0.30)))
    p += detail_kit(HL, HW, top, ROOF, -0.50, 0.90, era=0, mg=True)
    p += running_gear(HL, HW, CL, 5, 0.28, 0.46)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 0.85, gun_y=0.35)


def ballistic_launcher():
    """One large missile on a raised TEL. GNSS_INS — kills buildings, never
    movers (docs/02)."""
    HL, HW, CL, HH = 10.60, 3.10, 0.60, 1.05
    p, top = _base(HL, HW, CL, HH, 1.30, "bal_hull")
    p.append(cube((0, -HL * 0.34, top + 0.72), (2.75, 2.60, 1.44)))   # cab
    use("deck")
    p.append(cube((0, HL * 0.16, top + 0.34), (2.30, 5.60, 0.62)))    # cradle
    p.append(cyl((0, HL * 0.16, top + 1.40), 0.56, 8.20,
                 rot=(R(74), 0, 0), v=16))                            # missile
    p.append(cyl((0, HL * 0.16 - 2.20, top + 2.90), 0.30, 1.60,
                 rot=(R(74), 0, 0), v=14, taper=0.35))                # nose cone
    use("body")
    ROOF = top + 4.20
    p += detail_kit(HL, HW, top, top + 1.44, -HL * 0.34, HL * 0.16, era=0, mg=False)
    p += wheeled_gear(HL, HW, CL, 5, 0.60)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 1.40, gun_y=HL * 0.16)


def coastal_battery():
    """Taiwan's signature. Boxed anti-ship canisters angled outboard."""
    HL, HW, CL, HH = 8.40, 2.95, 0.55, 1.00
    p, top = _base(HL, HW, CL, HH, 1.20, "cst_hull")
    p.append(cube((0, -HL * 0.33, top + 0.68), (2.65, 2.30, 1.36)))
    use("deck")
    for r in range(2):
        p.append(cube((0, HL * 0.18, top + 0.70 + r * 0.92), (2.45, 3.40, 0.86),
                      rot=(R(-15), 0, 0)))
    use("body")
    ROOF = top + 2.40
    p += detail_kit(HL, HW, top, top + 1.36, -HL * 0.33, HL * 0.18, era=0, mg=False)
    p += wheeled_gear(HL, HW, CL, 4, 0.56)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 1.20, gun_y=HL * 0.18)


# ── air defence ────────────────────────────────────────────────────
def spaag():
    """Gun AA: twin barrels plus a small tracking dish. No RF dependency —
    immune to anti-radiation weapons."""
    HL, HW, CL, HH = 6.70, 3.25, 0.44, 1.05
    p, top = _base(HL, HW, CL, HH, 1.55, "spa_hull")
    ROOF = top + 1.00
    p.append(cube((0, 0.15, top + 0.50), (2.55, 2.45, 1.00)))
    use("gun")
    for s in (-1, 1):
        p.append(cyl((s * 0.42, -1.90, top + 0.66), 0.062, 2.90,
                     rot=(R(96), 0, 0), v=10))
    use("deck")
    p.append(cyl((0, 1.35, ROOF + 0.42), 0.66, 0.18, rot=(R(-70), 0, 0), v=18))
    use("body")
    p += detail_kit(HL, HW, top, ROOF, -1.10, 1.40, era=0, mg=False)
    p += running_gear(HL, HW, CL, 6, 0.30, 0.50)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF + 0.60,
                   gun_z=top + 0.66, gun_y=-1.10)


def shorad_sam():
    """Short-range SAM: launcher pods either side of a small dish."""
    HL, HW, CL, HH = 6.50, 3.20, 0.44, 1.08
    p, top = _base(HL, HW, CL, HH, 1.50, "sho_hull")
    ROOF = top + 0.95
    p.append(cube((0, 0.20, top + 0.46), (2.10, 2.10, 0.92)))
    use("deck")
    for s in (-1, 1):
        p.append(cube((s * 1.32, 0.20, top + 0.80), (0.52, 1.70, 0.80),
                      rot=(R(-14), 0, 0)))
        for k in range(2):
            p.append(cyl((s * 1.32, 0.20, top + 0.62 + k * 0.38), 0.15, 1.90,
                         rot=(R(76), 0, 0), v=10))
    p.append(cyl((0, 0.70, ROOF + 0.34), 0.52, 0.16, rot=(R(-72), 0, 0), v=18))
    use("body")
    p += detail_kit(HL, HW, top, ROOF, -0.80, 1.20, era=0, mg=False)
    p += running_gear(HL, HW, CL, 6, 0.30, 0.50)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF + 0.50,
                   gun_z=top + 0.80, gun_y=0.20)


def long_sam():
    """Long-range SAM launcher — bigger canisters, steeper. Still launcher
    ONLY; it needs the search radar and the illuminator (docs/12)."""
    HL, HW, CL, HH = 9.40, 3.05, 0.56, 1.10
    p, top = _base(HL, HW, CL, HH, 1.25, "lsm_hull")
    p.append(cube((0, -HL * 0.33, top + 0.66), (2.70, 2.40, 1.32)))
    use("deck")
    p.append(cube((0, HL * 0.18, top + 0.32), (2.50, 4.10, 0.60)))
    for c in range(4):
        p.append(cyl((-1.02 + c * 0.68, HL * 0.18, top + 2.30), 0.36, 7.60,
                     rot=(R(70), 0, 0), v=14))
    use("body")
    ROOF = top + 4.10
    p += detail_kit(HL, HW, top, top + 1.32, -HL * 0.33, HL * 0.18, era=0, mg=False)
    p += wheeled_gear(HL, HW, CL, 5, 0.58)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 2.30, gun_y=HL * 0.18)


# ── sensors and support ────────────────────────────────────────────
def counter_battery_radar():
    """Backtracks shells to the firing position (docs/10). A small flat panel
    lying back, distinct from the tall rotating search array."""
    HL, HW, CL, HH = 7.60, 2.90, 0.52, 1.05
    p, top = _base(HL, HW, CL, HH, 1.20, "cbr_hull")
    p.append(cube((0, -HL * 0.31, top + 0.60), (2.60, 2.20, 1.20)))
    use("deck")
    p.append(cube((0, HL * 0.20, top + 1.10), (3.30, 0.26, 2.10),
                  rot=(R(-38), 0, 0)))
    for k in range(4):
        p.append(cube((0, HL * 0.20 - 0.30 + k * 0.22, top + 0.60 + k * 0.34),
                      (3.15, 0.12, 0.10)))
    use("body")
    p.append(cube((0, HL * 0.20, top + 0.30), (1.20, 0.90, 0.60)))
    ROOF = top + 2.30
    p += detail_kit(HL, HW, top, top + 1.20, -HL * 0.31, HL * 0.20, era=0, mg=False)
    p += wheeled_gear(HL, HW, CL, 3, 0.55)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 1.10, gun_y=HL * 0.20)


def ew_jammer():
    """Denies the enemy picture — and is itself a screaming RF beacon
    (docs/02). Log-periodic masts, unmistakable from above."""
    HL, HW, CL, HH = 7.90, 2.90, 0.52, 1.08
    p, top = _base(HL, HW, CL, HH, 1.25, "ewj_hull")
    p.append(cube((0, -HL * 0.30, top + 0.62), (2.60, 2.30, 1.24)))
    p.append(cube((0, HL * 0.18, top + 0.66), (2.45, 3.30, 1.32)))    # shelter
    use("deck")
    for s in (-1, 1):
        p.append(cyl((s * 0.95, HL * 0.18, top + 2.10), 0.075, 1.70, v=8))
        for k in range(6):                                           # dipoles
            w = 1.15 - k * 0.14
            p.append(cube((s * 0.95, HL * 0.18, top + 1.45 + k * 0.26),
                          (w, 0.07, 0.07)))
    use("body")
    ROOF = top + 3.10
    p += detail_kit(HL, HW, top, top + 1.32, -HL * 0.30, HL * 0.18, era=0, mg=False)
    p += wheeled_gear(HL, HW, CL, 3, 0.55)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 1.45, gun_y=HL * 0.18)


def command_vehicle():
    """Datalink node. Killing it fragments the faction track table (docs/12).
    Identified by an antenna farm, not a weapon."""
    HL, HW, CL, HH = 6.80, 3.00, 0.44, 1.55
    p, top = _base(HL, HW, CL, HH, 1.35, "cmd_hull")
    ROOF = top + 0.30
    use("deck")
    p.append(cube((0, 0.30, top + 0.05), (2.20, 2.60, 0.10)))
    for i in range(6):
        p.append(cyl((-0.85 + (i % 3) * 0.85, -0.40 + (i // 3) * 1.30,
                      top + 0.95), 0.05, 1.80, v=6))
    use("body")
    p.append(cube((0, HL * 0.40, top - 0.55), (HW * 0.70, 0.14, 0.80)))
    p += detail_kit(HL, HW, top, ROOF, -0.60, 0.90, era=0, mg=False)
    p += running_gear(HL, HW, CL, 5, 0.29, 0.52)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=top + 1.90,
                   gun_z=top + 0.30, gun_y=0.0)


def ammo_truck():
    """Sustains rate of fire. Flatbed stacked with crates."""
    HL, HW, CL, HH = 8.20, 2.86, 0.55, 0.75
    p, top = _base(HL, HW, CL, HH, 0.90, "amm_hull")
    p.append(cube((0, -HL * 0.33, top + 0.70), (2.55, 2.20, 1.40)))
    use("deck")
    for r in range(2):
        for c in range(3):
            p.append(cube((-0.80 + c * 0.80, HL * 0.16 - 1.20 + r * 1.60,
                           top + 0.45 + r * 0.02), (0.72, 1.40, 0.86)))
    use("body")
    for s in (-1, 1):
        p.append(cube((s * 1.36, HL * 0.16, top + 0.42), (0.10, 4.30, 0.80)))
    ROOF = top + 1.40
    p += detail_kit(HL, HW, top, top + 1.40, -HL * 0.33, HL * 0.16, era=0, mg=False)
    p += wheeled_gear(HL, HW, CL, 3, 0.56)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=ROOF,
                   gun_z=top + 0.90, gun_y=HL * 0.16)


def engineer_vehicle():
    """Dozer blade forward, crane aft. Obstacles, mines, fortifications."""
    HL, HW, CL, HH = 7.10, 3.35, 0.46, 1.15
    p, top = _base(HL, HW, CL, HH, 1.50, "eng_hull")
    ROOF = top + 0.60
    p.append(cube((0, -0.30, top + 0.30), (2.20, 2.00, 0.60)))
    use("deck")
    p.append(cube((0, -HL / 2 - 0.45, 0.62), (3.55, 0.26, 1.15),
                  rot=(R(-12), 0, 0)))                                # blade
    for s in (-1, 1):
        p.append(cube((s * 1.20, -HL / 2 + 0.35, 0.80), (0.16, 1.50, 0.20),
                      rot=(R(16), 0, 0)))                             # arms
    p.append(cube((0.70, HL * 0.22, top + 1.30), (0.34, 3.30, 0.34),
                  rot=(R(-26), 0, 0)))                                # crane jib
    use("body")
    p += detail_kit(HL, HW, top, ROOF, -1.00, 0.80, era=0, mg=False)
    p += running_gear(HL, HW, CL, 6, 0.31, 0.52)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=top + 2.10,
                   gun_z=top + 0.30, gun_y=-1.00)


def repair_vehicle():
    """Recovers mobility and firepower kills. Heavy crane, winch, spade."""
    HL, HW, CL, HH = 7.30, 3.30, 0.46, 1.20
    p, top = _base(HL, HW, CL, HH, 1.45, "rep_hull")
    ROOF = top + 0.70
    p.append(cube((0, -0.55, top + 0.35), (2.35, 2.30, 0.70)))
    use("deck")
    p.append(cyl((-0.85, 0.60, top + 0.90), 0.32, 0.70, v=14))        # crane base
    p.append(cube((-0.85, 1.90, top + 1.85), (0.34, 3.90, 0.34),
                  rot=(R(-30), 0, 0)))
    p.append(cube((0, HL / 2 + 0.30, 0.58), (3.20, 0.24, 0.95),
                  rot=(R(10), 0, 0)))                                 # spade
    use("body")
    p += detail_kit(HL, HW, top, ROOF, -1.20, 0.90, era=0, mg=False)
    p += running_gear(HL, HW, CL, 6, 0.31, 0.54)
    return p, dict(top=top, hull_l=HL, hull_w=HW, turret_top=top + 2.60,
                   gun_z=top + 0.35, gun_y=-1.20)


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
]

if __name__ == "__main__":
    H.set_out(os.path.join(ROOT, "art", "blockout", "e4_army"))
    for name, _ in ARMY:
        H.CAMO[name] = "camo_us"
        H.TEAM[name] = (0.06, 0.20, 0.62)
    print("building army roles...")
    for name, fn in ARMY:
        for lod in (0, 1, 2):
            n = H.build(name, fn, lod)
            print(f"  {name:28s} LOD{lod}  {n:6d} tris")
    print("done")
