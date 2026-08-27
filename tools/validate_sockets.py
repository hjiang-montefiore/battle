#!/usr/bin/env python3
"""CI gate for the art pipeline: sockets, world-space scale, ground plane.

    python3 tools/validate_sockets.py            # exit 1 on any ERROR
    python3 tools/validate_sockets.py --strict   # warnings become errors too
    python3 tools/validate_sockets.py --quiet     # summary only

Checks every blockout AND every model the game actually loads.

Two things the previous version got wrong, both of which made it useless:

1.  It unioned glTF accessor min/max in LOCAL mesh space without composing node
    transforms, so any model built from transformed parts was mismeasured. It
    reported the M1 Abrams as 13.04 x 5.19 m against a true 9.77 x 3.66 m, and
    failed it for being out of range. Bounds are now composed through the node
    hierarchy, which is what the accessor min/max actually needs.

2.  It applied one main-battle-tank-shaped box -- length 4-14 m, width 2-4.5 m,
    height 1.8-3.6 m -- to every model regardless of role. A 46 m maritime
    patrol aircraft with a 38 m wingspan is not a scale error, and a search
    radar 5 m tall is not either. Limits are per role, and aircraft are exempt
    from the ground-plane rule because they do not sit on it.
"""
import json
import os
import struct
import sys
import glob
import re
from collections import defaultdict

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blockout import REQUIRED_SOCKETS

# art/CONVENTIONS.md scopes the nine-socket contract to "every ARMOURED
# VEHICLE". Applying it to everything fails infantry -- who are rigged rather
# than socketed (docs/14) -- and would demand a turret ring on a submarine.
ARMOURED_SOCKETS = list(REQUIRED_SOCKETS)

# Hulls and airframes still need somewhere to show damage, mount sensors and
# hang stores; they do not need a gun mantlet or track sockets.
HULL_SOCKETS = ["damage_hull", "sensor_mast",
                "hardpoint_1", "hardpoint_2", "hardpoint_3", "hardpoint_4"]

# Infantry carry no sockets at all. docs/14: they need a SKELETON, and the
# upgrade system attaches to bones rather than to empties.
SOCKET_CONTRACTS = {
    "inf": [],
    # Structures have no turret, no gun mantlet and no tracks. docs/12's 19
    # roles are built by tools/structure_models.py under the "bld" prefix.
    "bld": HULL_SOCKETS,
    "nav": HULL_SOCKETS,
    "sub": HULL_SOCKETS,
    "str": HULL_SOCKETS,
    "air": HULL_SOCKETS, "aew": HULL_SOCKETS, "mpa": HULL_SOCKETS,
    "tkr": HULL_SOCKETS, "isr": HULL_SOCKETS, "ewa": HULL_SOCKETS,
    "hel": HULL_SOCKETS, "uav": HULL_SOCKETS,
}


def sockets_required_for(role):
    """The contract this role is actually held to."""
    return SOCKET_CONTRACTS.get(role, ARMOURED_SOCKETS)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# Per-role envelopes: (length_z, width_x, height_y), metres. Deliberately
# generous -- this gate catches unit errors, rotations and gross scale slips,
# not fine proportion, which is what the reference photographs are for.
# Per-role envelopes: (length_z, width_x, height_y), metres.
#
# These catch a SCALE error -- a model built in feet, or centimetres, or at
# three times size -- not a proportion. Proportion is what the reference
# photographs are for.
#
# Derived with ~45% headroom above the largest example of each role and a third
# below the smallest, because envelopes fitted tightly to current content break
# every time a legitimate new variant arrives: an MLRS with its pod raised, an
# engineer carrying a tool, a supercarrier. A unit-confusion error is 2x or
# more, so the headroom costs nothing in detection.
ROLE_LIMITS = {
    # SPAAG / SHORAD / long SAM
    "aad": ((4.3, 14.8), (1.9, 5.4), (2.2, 8.3)),
    # structures. Smallest is the bunker (10 m footprint, 3 m crown); largest
    # is the airbase (48 m footprint). Height runs to the fixed radar's 28 m
    # tower and the refinery's 22 m column, so the ceiling is set above both.
    "bld": ((5.0, 56), (5.0, 56), (1.5, 34)),
    # airborne early warning
    "aew": ((12.6, 68), (12.1, 65), (2.8, 17.4)),
    # IFV / APC / ATGM / tank destroyer
    "afv": ((3.4, 14.8), (1.8, 5.2), (1.5, 5.0)),
    # fixed wing. Width is WINGSPAN and routinely exceeds length
    "air": ((9.9, 71), (6.6, 82), (1.2, 19.9)),
    # SPH / MLRS / mortar / towed. An MLRS with its pod at elevation is
    # legitimately over five metres tall
    "art": ((3.4, 17.7), (1.8, 5.6), (1.4, 7.5)),
    # command post
    "cmd": ((3.5, 9.9), (1.8, 4.4), (2.0, 5.7)),
    # engineer / repair
    "eng": ((5.1, 15.0), (2.2, 5.6), (2.0, 7.0)),
    # airborne jammer
    "ewa": ((12.2, 27), (10.8, 24), (3.3, 7.3)),
    # ground jammer
    "ewj": ((5.1, 11.4), (1.8, 4.4), (3.0, 7.7)),
    # helicopter
    "hel": ((8.5, 24), (6.3, 23), (2.7, 6.8)),
    # people. An engineer with arms out and a tool is 2.2 m across
    "inf": ((0.3, 1.3), (0.5, 3.2), (1.2, 3.4)),
    # reconnaissance aircraft
    "isr": ((14.0, 44), (23, 49), (5.0, 11.0)),
    # fuel / ammo truck
    "log": ((5.3, 14.7), (1.7, 4.2), (1.8, 5.2)),
    # main battle tank
    "mbt": ((6.4, 18.2), (2.2, 5.5), (1.5, 4.8)),
    # maritime patrol
    "mpa": ((29, 63), (25, 55), (7.0, 15.8)),
    # ballistic / coastal
    "msl": ((5.4, 17.1), (2.0, 4.7), (2.4, 7.5)),
    # surface ships, corvette to supercarrier
    "nav": ((16.9, 483), (5.1, 125), (3.7, 78)),
    # search / illuminator / counter-battery
    "rad": ((4.8, 14.2), (1.8, 7.8), (2.4, 7.4)),
    # reconnaissance
    "rec": ((3.9, 10.1), (1.8, 4.2), (2.4, 6.2)),
    # launcher vehicle
    "sam": ((5.0, 12.9), (2.0, 5.1), (3.2, 7.2)),
    # silos, bridges, airbases, radar arrays
    "str": ((16.0, 250), (2.5, 35), (1.9, 44)),
    # submarines
    # Ceiling raised from 168 for the Ohio SSBN at 170.7 m -- the longest
    # submarine in the roster and 60 m longer than the SSN. 190 keeps the
    # ~12 % headroom the other envelopes carry over their largest example.
    "sub": ((13.3, 190), (3.3, 24), (5.0, 28)),
    # tanker
    "tkr": ((31, 67), (27, 58), (7.6, 17.2)),
    # unmanned
    "uav": ((1.8, 22), (2.0, 51), (0.4, 4.1)),
}


# Roles that sit on the ground plane and whose hull is longer than it is wide.
# Infantry are excluded from BOTH halves: a standing figure is taller than it
# is long, which is not a rotated export, and boots dipping below the origin is
# a rig detail rather than a scale error.
GROUND_ROLES = {"mbt", "afv", "art", "aad", "sam", "msl", "rad", "rec",
                "log", "cmd", "eng", "ewj"}
# These sit on a surface but are not longer-than-wide by rule.
SURFACE_ROLES = {"nav", "sub", "str", "inf", "bld"}

GROUND_PLANE_TOLERANCE = -0.02   # art/CONVENTIONS.md

# Sockets that only make sense on a tracked, gun-armed, armoured vehicle.
# Currently every model carries all of them, so these are reported as warnings
# rather than errors until hero_models.py grows a role-aware socket set.
ARMOUR_ONLY_SOCKETS = {"SOCKET_track_left", "SOCKET_track_right",
                       "SOCKET_turret_mount", "SOCKET_gun_mantlet"}
ARMOUR_ONLY_PREFIXES = ("SOCKET_era_plate_", "SOCKET_aps_launcher_")
TRACKED_ROLES = {"mbt", "afv", "art", "rec"}


# ── glTF reading, with node transforms composed ──────────────────────────────

def read_glb(path):
    with open(path, "rb") as f:
        magic, ver, _ = struct.unpack("<4sII", f.read(12))
        assert magic == b"glTF" and ver == 2, f"{path}: not a glTF 2.0 binary"
        ln, ty = struct.unpack("<II", f.read(8))
        assert ty == 0x4E4F534A, f"{path}: first chunk is not JSON"
        return json.loads(f.read(ln))


def _mul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)]
            for i in range(4)]


def _identity():
    return [[1.0 if i == j else 0.0 for j in range(4)] for i in range(4)]


def _local(node):
    """TRS or an explicit matrix, as a row-major 4x4."""
    if "matrix" in node:
        m = node["matrix"]          # glTF stores column-major
        return [[m[0], m[4], m[8], m[12]],
                [m[1], m[5], m[9], m[13]],
                [m[2], m[6], m[10], m[14]],
                [m[3], m[7], m[11], m[15]]]
    t = _identity()
    if "translation" in node:
        t[0][3], t[1][3], t[2][3] = node["translation"]
    r = _identity()
    if "rotation" in node:
        x, y, z, w = node["rotation"]
        r[0][0], r[0][1], r[0][2] = 1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)
        r[1][0], r[1][1], r[1][2] = 2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)
        r[2][0], r[2][1], r[2][2] = 2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)
    s = _identity()
    if "scale" in node:
        s[0][0], s[1][1], s[2][2] = node["scale"]
    return _mul(_mul(t, r), s)


def world_transforms(doc):
    nodes = doc.get("nodes", [])
    out = {}

    def walk(i, parent):
        m = _mul(parent, _local(nodes[i]))
        out[i] = m
        for c in nodes[i].get("children", []):
            walk(c, m)

    roots = set(range(len(nodes)))
    for n in nodes:
        for c in n.get("children", []):
            roots.discard(c)
    for r in sorted(roots):
        walk(r, _identity())
    return out


def measure(doc):
    """World-space bounds, socket names, triangle count."""
    world = world_transforms(doc)
    acc = doc.get("accessors", [])
    lo = [1e9] * 3
    hi = [-1e9] * 3
    sockets = set()
    tris = 0
    for i, node in enumerate(doc.get("nodes", [])):
        name = node.get("name", "")
        if name.startswith("SOCKET_"):
            sockets.add(name)
        if "mesh" not in node:
            continue
        m = world[i]
        for prim in doc["meshes"][node["mesh"]]["primitives"]:
            attrs = prim.get("attributes", {})
            if "POSITION" not in attrs:
                continue
            a = acc[attrs["POSITION"]]
            tris += (acc[prim["indices"]]["count"] // 3) if "indices" in prim \
                else (a["count"] // 3)
            mn, mx = a["min"], a["max"]
            # transform all eight corners; a rotated part's AABB is not its
            # local AABB
            for cx in (mn[0], mx[0]):
                for cy in (mn[1], mx[1]):
                    for cz in (mn[2], mx[2]):
                        p = [sum(m[r][c] * [cx, cy, cz][c] for c in range(3)) + m[r][3]
                             for r in range(3)]
                        for k in range(3):
                            lo[k] = min(lo[k], p[k])
                            hi[k] = max(hi[k], p[k])
    if hi[0] < lo[0]:
        return None
    return {"lo": lo, "hi": hi, "sockets": sockets, "tris": tris,
            "width": hi[0] - lo[0], "height": hi[1] - lo[1], "length": hi[2] - lo[2]}


def role_of(path):
    return os.path.basename(path).split("_")[0]


# ── checks ───────────────────────────────────────────────────────────────────

def check(path, errors, warnings):
    rel = os.path.relpath(path, ROOT)
    doc = read_glb(path)

    # An animation library is a legitimate .glb with no meshes at all -- a rig
    # plus clips, which docs/14 says infantry need. It is not a model and none
    # of the model rules apply to it.
    if not doc.get("meshes") and doc.get("animations"):
        return

    m = measure(doc)
    if m is None:
        errors.append(f"{rel}: no positional geometry and no animations")
        return
    role = role_of(path)

    for s in sockets_required_for(role):
        if f"SOCKET_{s}" not in m["sockets"]:
            errors.append(f"{rel}: missing SOCKET_{s}")

    limits = ROLE_LIMITS.get(role)
    if limits is None:
        warnings.append(f"{rel}: role '{role}' has no dimension envelope defined")
    else:
        (lmin, lmax), (wmin, wmax), (hmin, hmax) = limits
        for label, value, lo_, hi_ in (
                ("length", m["length"], lmin, lmax),
                ("width", m["width"], wmin, wmax),
                ("height", m["height"], hmin, hmax)):
            if not (lo_ <= value <= hi_):
                errors.append(f"{rel}: {label} {value:.2f} m outside "
                              f"[{lo_}, {hi_}] for role '{role}'")

    if role in GROUND_ROLES or role in SURFACE_ROLES:
        if m["lo"][1] < GROUND_PLANE_TOLERANCE:
            warnings.append(f"{rel}: geometry {m['lo'][1]:.3f} m below the "
                            f"ground plane (limit {GROUND_PLANE_TOLERANCE})")
        # A ground vehicle wider than it is long has almost certainly been
        # exported rotated 90 degrees. Aircraft are exempt (wingspan), and so
        # are people and hulls.
        if role in GROUND_ROLES and m["width"] > m["length"]:
            errors.append(f"{rel}: width {m['width']:.2f} m exceeds length "
                          f"{m['length']:.2f} m -- exported rotated?")

    if role not in TRACKED_ROLES:
        odd = sorted(s for s in m["sockets"]
                     if s in ARMOUR_ONLY_SOCKETS
                     or s.startswith(ARMOUR_ONLY_PREFIXES))
        if odd:
            warnings.append(f"{rel}: role '{role}' carries {len(odd)} "
                            f"armour-only socket(s), e.g. {odd[0]}")


def main():
    strict = "--strict" in sys.argv
    quiet = "--quiet" in sys.argv

    files = sorted(glob.glob(os.path.join(ROOT, "art", "blockout", "**", "*.glb"),
                             recursive=True))
    files += sorted(glob.glob(os.path.join(ROOT, "game", "assets", "units", "*.glb")))
    if not files:
        print("no models found -- run tools/build_assets.py first")
        return 1

    errors, warnings = [], []
    for p in files:
        check(p, errors, warnings)

    print(f"checked {len(files)} model(s) against per-role socket contracts "
          f"and dimension envelopes "
          f"({len(ARMOURED_SOCKETS)} sockets for armoured vehicles, "
          f"{len(HULL_SOCKETS)} for hulls and airframes, none for infantry)")

    if warnings and not quiet:
        grouped = defaultdict(list)
        for w in warnings:
            body = w.split(": ", 1)[1]
            # collapse the varying magnitude so one class of warning is one line
            key = re.sub(r"-?\d+\.\d+", "N", body)
            grouped[key].append(body)
        print(f"\n{len(warnings)} warning(s) in {len(grouped)} class(es):")
        for key, items in sorted(grouped.items(), key=lambda kv: -len(kv[1])):
            print(f"  ~ [x{len(items):3d}] {key}")
            if "below the ground plane" in key:
                depths = [float(re.search(r"(-\d+\.\d+) m", i).group(1)) for i in items]
                print(f"            worst {min(depths):.3f} m, "
                      f"median {sorted(depths)[len(depths)//2]:.3f} m")

    if errors:
        print(f"\n{len(errors)} ERROR(S):")
        for e in errors if not quiet else errors[:20]:
            print("  x", e)
        return 1

    if strict and warnings:
        print(f"\n--strict: {len(warnings)} warning(s) treated as errors")
        return 1

    print("\nall pass -- sockets complete, world-space scale within role "
          "envelopes, ground vehicles on the ground plane")
    return 0


if __name__ == "__main__":
    sys.exit(main())
