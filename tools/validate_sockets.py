#!/usr/bin/env python3
"""Fail the build if any blockout is missing a required socket, or is off-scale.

    python3 tools/validate_sockets.py        # exit 1 on any failure
"""
import json, os, struct, sys, glob
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from blockout import REQUIRED_SOCKETS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
LIMITS = {"length": (4.0, 14.0), "width": (2.0, 4.5), "height": (1.8, 3.6)}


def read_glb_json(path):
    with open(path, "rb") as f:
        magic, ver, _ = struct.unpack("<4sII", f.read(12))
        assert magic == b"glTF" and ver == 2, f"{path}: not a glTF 2.0 binary"
        ln, ty = struct.unpack("<II", f.read(8))
        assert ty == 0x4E4F534A, f"{path}: first chunk is not JSON"
        return json.loads(f.read(ln))


def main():
    files = sorted(glob.glob(os.path.join(ROOT, "art", "blockout", "**", "*.glb"),
                             recursive=True))
    if not files:
        print("no blockouts found — run tools/build_assets.py first")
        return 1
    fails, checked = [], 0
    for p in files:
        rel = os.path.relpath(p, ROOT)
        doc = read_glb_json(p)
        names = {n.get("name", "") for n in doc["nodes"]}
        for s in REQUIRED_SOCKETS:
            if f"SOCKET_{s}" not in names:
                fails.append(f"{rel}: missing SOCKET_{s}")
        # scale sanity — POSITION accessors ONLY. Normals are also VEC3 and
        # run to ±1, which silently inflates every bound if you include them.
        pos = set()
        for m in doc.get("meshes", []):
            for prim in m["primitives"]:
                if "POSITION" in prim["attributes"]:
                    pos.add(prim["attributes"]["POSITION"])
        mn = [1e9] * 3; mx = [-1e9] * 3
        for i in pos:
            a = doc["accessors"][i]
            mn = [min(mn[k], a["min"][k]) for k in range(3)]
            mx = [max(mx[k], a["max"][k]) for k in range(3)]
        dims = {"width": mx[0] - mn[0], "height": mx[1] - mn[1], "length": mx[2] - mn[2]}
        for k, (lo, hi) in LIMITS.items():
            if not (lo <= dims[k] <= hi):
                fails.append(f"{rel}: {k} {dims[k]:.2f} m outside [{lo}, {hi}] — check units")
        if mn[1] < -0.02:
            fails.append(f"{rel}: geometry below ground plane (min Y = {mn[1]:.3f})")
        checked += 1

    print(f"checked {checked} blockouts against {len(REQUIRED_SOCKETS)} required sockets")
    if fails:
        print(f"\n{len(fails)} FAILURE(S):")
        for f in fails:
            print("  ✗", f)
        return 1
    print("all pass — sockets complete, scale sane, nothing below the ground plane")
    return 0


if __name__ == "__main__":
    sys.exit(main())
