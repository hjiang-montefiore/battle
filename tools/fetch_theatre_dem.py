#!/usr/bin/env python3
"""Fetch real elevation and bathymetry for each theatre.

    python3 tools/fetch_theatre_dem.py                  # all theatres
    python3 tools/fetch_theatre_dem.py taiwan_strait    # just one
    python3 tools/fetch_theatre_dem.py --grid 96        # coarser and quicker

Samples GEBCO 2020 through the public opentopodata.org API and writes a compact
heightfield to game/assets/terrain/<key>.hf, which SimTerrain loads directly.

WHY GEBCO. It is the only free global grid that carries BOTH topography and
bathymetry, and this design needs both from one array: the same heights that
mask a radar (docs/02 §1) give the acoustic layer its depth (docs/02 §8.3).
Elevations are metres, negative is water. GEBCO's own resolution is 15
arc-seconds, far finer than anything sampled here.

WHAT LEAVES THIS MACHINE. Latitude and longitude only. Nothing else is sent,
and the results are cached in the repository so the network is needed exactly
once per theatre.

POLITENESS. The public endpoint allows 100 locations per request, one call a
second and 1000 calls a day. This honours all three, and is resumable: partial
results are cached per theatre, so an interrupted run picks up where it left
off rather than starting the quota again.
"""
import json
import math
import os
import struct
import subprocess
import sys
import time

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "game", "assets", "terrain")
CACHE_DIR = os.path.join(ROOT, ".dem_cache")

API = "https://api.opentopodata.org/v1/gebco2020"
BATCH = 100          # the public endpoint's hard limit
DELAY_S = 1.05       # one call a second, with a little headroom

# Geographic boxes, chosen so each theatre contains what makes it that theatre.
# extent_km is the square the game plays on; the box is derived from it so the
# scale is honest rather than a stretched rectangle.
THEATRES = {
    "taiwan_strait": {
        "name": "Taiwan Strait",
        # Fujian coast, the strait, Taiwan and its central range, and the
        # Philippine Sea shelf dropping away to the east.
        "lat": 23.90, "lon": 120.20, "extent_km": 512.0,
    },
    "korean_peninsula": {
        "name": "Korean Peninsula",
        # The DMZ, the Taebaek range, and the corridors either side of it.
        "lat": 38.00, "lon": 127.40, "extent_km": 346.0,
    },
    "central_europe": {
        "name": "Central Europe",
        # The North German Plain, the Harz, and the Thuringian forest.
        "lat": 51.30, "lon": 11.00, "extent_km": 480.0,
    },
    "north_atlantic": {
        "name": "North Atlantic",
        # The GIUK gap: the water every Atlantic submarine problem runs through.
        "lat": 61.50, "lon": -12.00, "extent_km": 768.0,
    },
}

HF_MAGIC = b"BTHF"
HF_VERSION = 1


def box_for(spec):
    """Lat/lon bounds for a square of extent_km centred on the given point."""
    half = spec["extent_km"] / 2.0
    dlat = half / 110.574
    dlon = half / (111.320 * math.cos(math.radians(spec["lat"])))
    return (spec["lat"] - dlat, spec["lat"] + dlat,
            spec["lon"] - dlon, spec["lon"] + dlon)


def sample_points(spec, grid):
    """Row-major grid. Row 0 is the NORTH edge, so +z in the sim is north."""
    lat0, lat1, lon0, lon1 = box_for(spec)
    pts = []
    for r in range(grid):
        lat = lat1 - (lat1 - lat0) * (r + 0.5) / grid
        for c in range(grid):
            lon = lon0 + (lon1 - lon0) * (c + 0.5) / grid
            pts.append((lat, lon))
    return pts


def fetch_batch(points):
    locs = "|".join("%.6f,%.6f" % (a, b) for a, b in points)
    for attempt in range(5):
        proc = subprocess.run(
            ["curl", "-s", "-m", "60", "-G", "--data-urlencode", "locations=" + locs, API],
            capture_output=True, text=True)
        try:
            doc = json.loads(proc.stdout)
        except Exception:
            time.sleep(2.0 + attempt * 2.0)
            continue
        if doc.get("status") == "OK":
            out = []
            for r in doc["results"]:
                e = r.get("elevation")
                # GEBCO has no gaps, but a null would otherwise become a cliff.
                out.append(0.0 if e is None else float(e))
            return out
        # Rate limited or transient: back off rather than hammering.
        time.sleep(3.0 + attempt * 3.0)
    raise RuntimeError("gave up on a batch after 5 attempts")


def write_hf(path, name, grid, cell_size_m, heights):
    """int16 metres. GEBCO spans about -11000..8800, which fits with room."""
    nb = name.encode("utf-8")
    with open(path, "wb") as f:
        f.write(HF_MAGIC)
        f.write(struct.pack("<HIIfH", HF_VERSION, grid, grid, cell_size_m, len(nb)))
        f.write(nb)
        f.write(struct.pack("<%dh" % len(heights),
                            *[max(-32768, min(32767, int(round(h)))) for h in heights]))


def fetch(key, grid):
    spec = THEATRES[key]
    pts = sample_points(spec, grid)
    total = len(pts)
    os.makedirs(CACHE_DIR, exist_ok=True)
    cache = os.path.join(CACHE_DIR, "%s_%d.json" % (key, grid))

    done = []
    if os.path.exists(cache):
        with open(cache) as f:
            done = json.load(f)
        print("  resuming %s: %d/%d already cached" % (key, len(done), total))

    calls = 0
    start = time.time()
    while len(done) < total:
        chunk = pts[len(done):len(done) + BATCH]
        done.extend(fetch_batch(chunk))
        calls += 1
        with open(cache, "w") as f:
            json.dump(done, f)
        if calls % 10 == 0 or len(done) >= total:
            pct = len(done) / total * 100.0
            rate = len(done) / max(time.time() - start, 1e-6)
            eta = (total - len(done)) / max(rate, 1e-6)
            print("    %s  %5.1f%%  (%d/%d)  eta %4.1f min"
                  % (key, pct, len(done), total, eta / 60.0), flush=True)
        if len(done) < total:
            time.sleep(DELAY_S)

    os.makedirs(OUT_DIR, exist_ok=True)
    cell = spec["extent_km"] * 1000.0 / grid
    out = os.path.join(OUT_DIR, "%s.hf" % key)
    write_hf(out, spec["name"], grid, cell, done)

    lo, hi = min(done), max(done)
    water = sum(1 for h in done if h < 0) / float(total) * 100.0
    print("  %-18s %d x %d @ %.0f m  elevation %.0f..%.0f m  %.0f%% water  -> %s"
          % (key, grid, grid, cell, lo, hi, water, os.path.relpath(out, ROOT)))


def main(argv):
    grid = 128
    keys = []
    i = 0
    while i < len(argv):
        if argv[i] == "--grid":
            grid = int(argv[i + 1]); i += 2
        else:
            keys.append(argv[i]); i += 1
    if not keys:
        keys = list(THEATRES)
    for k in keys:
        if k not in THEATRES:
            print("unknown theatre:", k)
            return 1
    calls = sum(math.ceil(grid * grid / BATCH) for _ in keys)
    print("fetching %d theatre(s) at %dx%d -- about %d API calls, %.0f min"
          % (len(keys), grid, grid, calls, calls * DELAY_S / 60.0))
    for k in keys:
        fetch(k, grid)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
