#!/usr/bin/env python3
"""Build every model, one Blender process per unit, for byte-reproducibility.

    python3 tools/build_all.py [--only NAME] [--jobs N]

WHY ONE PROCESS PER UNIT
------------------------
Building several units inside a single Blender session is not reproducible.
Measured: the same unit built twice in one session is byte-identical, but four
units built in an interleaved sequence produced 10 of 12 files differing across
runs — with POSITION data identical and only INDEX, NORMAL, TEXCOORD and the
baked AO image varying. That signature means face/vertex ORDER changed, not
geometry.

ROOT CAUSE (measured, 2026-08-25)
---------------------------------
It is address-ordered iteration plus ASLR, and process isolation makes it WORSE
rather than better:

    same unit, twice in ONE session      -> byte-identical
    4 units interleaved in one session   -> 10 of 12 files differ
    same unit, two SEPARATE processes    -> differs

Within a session the allocator repeats its pattern, so any container keyed on a
`bmesh` element (which hashes by memory address) iterates the same way twice.
Across processes, address-space randomisation shifts every allocation and the
order changes. Pinning the one such set in our own code — the subdivision edge
set — fixed the repeated-same-unit case but not the others, so at least one more
address-ordered container lives inside Blender's own operators, where we cannot
reach it.

So one-process-per-unit does NOT buy reproducibility. It is still worth doing
for isolation — a unit that fails cannot corrupt the next — but the real fix is
to canonicalise the exported GLB: renumber vertices into a deterministic order
(lexicographic by position), permute every attribute to match, and sort the
triangle list. That makes output byte-stable no matter what order Blender
happened to emit.

This matters because art/blockout/ is tracked in git: without reproducibility,
every rebuild rewrites ~315 binaries with different bytes for identical geometry
and the repository grows by the full art payload each time, permanently.
"""
import argparse
import concurrent.futures as cf
import os
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLENDER = os.environ.get(
    "BLENDER", "/Applications/Blender.app/Contents/MacOS/Blender")

# module -> (out_bucket, roster attribute)
MODULES = [
    ("hero_models",    "e4_mbt_hero",    "HEROES"),
    ("faction_models", "e4_mbt_nations", "FACTIONS"),
    ("fleet_models",   "e4_support",     "FLEET"),
    ("army_models",    "e4_army",        "ARMY"),
    ("air_models",     "e4_air",         "AIR"),
    ("navy_models",    "e4_navy",        "NAVY"),
    ("strategic_models", "e4_strategic",  "STRATEGIC"),
]

CHILD = r'''
import sys, os
sys.path.insert(0, os.path.join(os.environ["BATTLE_ROOT"], "tools"))
import hero_models as H
mod = __import__(os.environ["BATTLE_MODULE"])
roster = getattr(mod, os.environ["BATTLE_ROSTER"])
want = os.environ["BATTLE_UNIT"]
H.set_out(os.path.join(os.environ["BATTLE_ROOT"], "art", "blockout",
                       os.environ["BATTLE_BUCKET"]))
for entry in roster:
    name, fn = entry[0], entry[1]
    if name != want:
        continue
    camo = entry[2] if len(entry) > 2 and isinstance(entry[2], str) else None
    team = entry[3] if len(entry) > 3 else None
    if camo:
        H.CAMO[name] = camo
    H.CAMO.setdefault(name, "camo_us")
    H.TEAM[name] = team or (0.06, 0.20, 0.62)
    for lod in (0, 1, 2):
        n = H.build(name, fn, lod)
        print("BUILT %s LOD%d %d" % (name, lod, n))
    break
'''


def roster_of(module, attr):
    """Read a roster without importing bpy — parse the module source."""
    src = open(os.path.join(ROOT, "tools", module + ".py")).read()
    marker = attr + " = ["
    if marker not in src:
        return []
    body = src[src.index(marker) + len(marker):]
    depth, out = 1, []
    for i, ch in enumerate(body):
        if ch == "[":
            depth += 1
        elif ch == "]":
            depth -= 1
            if depth == 0:
                body = body[:i]
                break
    for line in body.splitlines():
        line = line.strip()
        if line.startswith('("'):
            out.append(line.split('"')[1])
    return out


def build_one(module, bucket, attr, unit):
    env = dict(os.environ,
               BATTLE_ROOT=ROOT, BATTLE_MODULE=module,
               BATTLE_ROSTER=attr, BATTLE_BUCKET=bucket, BATTLE_UNIT=unit)
    # one child script per unit, so parallel workers cannot clobber each other
    child = os.path.join(ROOT, "tools", f".build_{unit}.py")
    with open(child, "w") as f:
        f.write(CHILD)
    try:
        r = subprocess.run([BLENDER, "-b", "--python", child],
                           env=env, capture_output=True, text=True, cwd=ROOT)
    finally:
        try:
            os.remove(child)
        except OSError:
            pass
    built = r.stdout.count("BUILT ")
    fail = [l for l in (r.stdout + r.stderr).splitlines()
            if l.startswith("FAIL") or "Traceback" in l]
    return built, fail


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--only", help="build a single unit by name")
    ap.add_argument("--module", help="build only this module")
    ap.add_argument("--jobs", type=int, default=0,
                    help="parallel Blender processes (default: cores-2)")
    args = ap.parse_args()

    jobs = args.jobs or max(1, (os.cpu_count() or 4) - 2)
    work = []
    for module, bucket, attr in MODULES:
        if args.module and module != args.module:
            continue
        for u in roster_of(module, attr):
            if args.only and u != args.only:
                continue
            work.append((module, bucket, attr, u))
    if not work:
        print("nothing to build")
        return 0

    # Each unit is an independent Blender process, so this parallelises with no
    # shared state. Blender is single-threaded for our workload, so wall-clock
    # scales close to linearly up to the core count.
    print(f"{len(work)} unit(s) on {jobs} parallel job(s)")
    t0 = time.time()
    total = failed = 0
    with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
        futs = {ex.submit(build_one, m, b, a, u): u for m, b, a, u in work}
        for fut in cf.as_completed(futs):
            u = futs[fut]
            try:
                built, fail = fut.result()
            except Exception as e:
                built, fail = 0, [str(e)]
            total += built
            if fail or built != 3:
                failed += 1
                print(f"   FAIL {u}: {fail[0][:110] if fail else f'only {built}/3 LODs'}")
            else:
                print(f"   ok   {u}")
    print(f"\n{total} files, {failed} unit(s) failed, {time.time()-t0:.0f}s "
          f"({jobs} jobs)")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
