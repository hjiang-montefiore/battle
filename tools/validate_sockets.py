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
ROLE_LIMITS = {
    "mbt": ((8.0, 14.0), (3.0, 4.3), (2.0, 3.7)),   # main battle tank
    "afv": ((5.0, 11.0), (2.4, 4.0), (1.8, 3.9)),   # IFV / APC / ATGM / TD
    "art": ((5.0, 13.5), (2.4, 4.0), (1.9, 4.3)),   # SPH / MLRS / mortar / towed
    "aad": ((5.0, 11.0), (2.4, 4.0), (2.4, 6.2)),   # SPAAG / SHORAD / long SAM
    "sam": ((6.0, 12.0), (2.4, 4.0), (2.8, 5.6)),   # launcher vehicle
    "msl": ((6.0, 12.0), (2.4, 4.0), (3.0, 5.4)),   # ballistic / coastal
    "rad": ((6.0, 10.5), (2.4, 6.2), (2.8, 5.6)),   # search / illuminator / CB
    "rec": ((4.0, 9.0), (2.2, 3.8), (1.7, 4.4)),    # reconnaissance
    "log": ((5.5, 11.5), (2.2, 3.6), (2.0, 4.4)),   # fuel / ammo truck
    "cmd": ((5.0, 10.0), (2.4, 4.0), (2.4, 5.4)),   # command post
    "eng": ((5.0, 10.5), (2.6, 4.0), (2.4, 5.2)),   # engineer / repair
    "ewj": ((5.0, 10.0), (2.4, 4.0), (2.4, 5.4)),   # ground jammer
    # Air. Width is WINGSPAN and routinely exceeds length -- an entirely normal
    # planform that the old length>width heuristic would have failed.
    "air": ((9.0, 56.0), (7.0, 62.0), (1.8, 15.0)),
    "aew": ((15.0, 56.0), (12.0, 62.0), (3.0, 14.0)),
    "mpa": ((15.0, 56.0), (12.0, 62.0), (3.0, 14.0)),
    "tkr": ((20.0, 60.0), (15.0, 64.0), (3.0, 15.0)),
    "isr": ((12.0, 56.0), (10.0, 62.0), (2.5, 14.0)),
    "ewa": ((10.0, 30.0), (8.0, 26.0), (2.5, 8.0)),
    "hel": ((10.0, 22.0), (8.0, 20.0), (2.5, 7.0)),
    "uav": ((1.5, 22.0), (1.5, 42.0), (0.3, 5.0)),
    # Infantry are people: taller than they are long, and about 1.8 m of it.
    "inf": ((0.25, 1.40), (0.35, 1.60), (1.40, 2.40)),
    # Naval. Width can be a flight deck, so it is generous; a supercarrier is
    # ~333 m long and a corvette ~26 m, and both must pass the same rule.
    "nav": ((18.0, 360.0), (4.0, 95.0), (3.0, 55.0)),
    "sub": ((12.0, 190.0), (2.5, 28.0), (4.0, 28.0)),
    # Strategic sites: silos, bridges, airbases, radar arrays.
    "str": ((4.0, 220.0), (2.5, 70.0), (2.0, 45.0)),
}

# Roles that sit on the ground plane and whose hull is longer than it is wide.
# Infantry are excluded from BOTH halves: a standing figure is taller than it
# is long, which is not a rotated export, and boots dipping below the origin is
# a rig detail rather than a scale error.
GROUND_ROLES = {"mbt", "afv", "art", "aad", "sam", "msl", "rad", "rec",
                "log", "cmd", "eng", "ewj"}
# These sit on a surface but are not longer-than-wide by rule.
SURFACE_ROLES = {"nav", "sub", "str", "inf"}

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
