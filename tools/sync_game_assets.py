#!/usr/bin/env python3
"""Copy selected blockout output into the Godot project.

    python3 tools/sync_game_assets.py                # the proving-ground set
    python3 tools/sync_game_assets.py --all          # everything
    python3 tools/sync_game_assets.py --match inf_   # by name prefix

WHY THIS IS A SELECTION AND NOT A MIRROR
----------------------------------------
art/blockout/ now holds over a thousand GLBs, and infantry alone is 392
variants because it is a full 7-epoch x 8-faction x 7-role matrix. The Godot
proving ground exists to check that the pipeline's output loads, scales and
animates correctly — it does not need every variant to do that, and importing
a thousand meshes makes the editor's import pass slow enough to discourage
running the check at all.

So this copies a deliberate sample by default: enough coverage to catch a
broken export, few enough to reimport in seconds. --all is there for when the
real game needs the full set.

Sidecar files (.import) are left alone; Godot regenerates them.
"""
import argparse
import os
import shutil
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "art", "blockout")
DST = os.path.join(ROOT, "game", "assets", "units")

# The proving-ground sample: one axis varied at a time, so a failure points at
# a cause rather than at "infantry is broken".
SAMPLE = [
    "inf_rig_clips",                                   # the shared clip library
] + [f"inf_e{e}_us_rifle" for e in range(1, 8)]        # the epoch ladder
SAMPLE += [f"inf_e6_{f}_rifle" for f in
           ("us", "uk", "de", "fr", "cn", "ru", "tw", "kp")]   # the faction row
SAMPLE += [f"inf_e6_us_{r}" for r in
           ("at", "manpads", "recon", "engineer", "sf", "mortar")]  # the roles


def find(name):
    for bucket in sorted(os.listdir(SRC)):
        d = os.path.join(SRC, bucket)
        if not os.path.isdir(d):
            continue
        for f in sorted(os.listdir(d)):
            if f.startswith(name) and f.endswith(".glb"):
                yield os.path.join(d, f)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--match", help="copy every unit whose name starts with this")
    ap.add_argument("--lod", type=int, default=0,
                    help="only this LOD (default 0); -1 for every LOD")
    args = ap.parse_args()

    os.makedirs(DST, exist_ok=True)
    if args.all:
        wanted = [""]
    elif args.match:
        wanted = [args.match]
    else:
        wanted = SAMPLE

    seen = set()
    copied = skipped = 0
    for name in wanted:
        for path in find(name):
            base = os.path.basename(path)
            if base in seen:
                continue
            seen.add(base)
            if args.lod >= 0 and f"_LOD{args.lod}.glb" not in base:
                # the clip library has no LOD suffix and must always come along
                if not base.startswith("inf_rig_clips"):
                    continue
            out = os.path.join(DST, base)
            if (os.path.exists(out)
                    and os.path.getmtime(out) >= os.path.getmtime(path)):
                skipped += 1
                continue
            shutil.copy2(path, out)
            copied += 1

    print(f"{copied} copied, {skipped} already current -> game/assets/units/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
