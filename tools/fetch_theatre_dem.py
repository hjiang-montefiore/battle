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

# ── sources, best first ──────────────────────────────────────────────────────
# GMRT (Global Multi-Resolution Topography) is the finest reachable source with
# no login. Its GridServer scales resolution to the requested box, so a whole
# theatre comes back in ONE request at 486 m -- roughly four times finer than
# ETOPO1 and enough to support a 1 km game grid without inventing detail.
# Checked against known ground: Yushan 3723 m (3952 m real), the Taiwan Strait
# -62 m, the Philippine Sea -4882 m, Taipei 21 m, and no nodata at all.
GMRT = "https://www.gmrt.org/services/GridServer"
GMRT_RESOLUTION = "med"     # low ~970 m, med ~490 m, high ~240 m and 36 MB

# ── sources ──────────────────────────────────────────────────────────────────
# ERDDAP griddap serves a whole rectangular subset in ONE request, which is both
# kinder to the service and far finer than sampling point by point: the entire
# Taiwan box comes back as 84,537 samples at 1 arc-minute in under a second,
# against 369 rate-limited calls for a coarser result.
ERDDAP = "https://coastwatch.pfeg.noaa.gov/erddap/griddap/etopo360.csv"
ERDDAP_SPACING_DEG = 1.0 / 60.0

# The per-point API is kept as a fallback: it uses GEBCO 2020, which is finer
# than ETOPO1, and is the only route if ERDDAP is unreachable.
POINT_API = "https://api.opentopodata.org/v1/gebco2020"
BATCH = 100          # the point endpoint's hard limit
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
        # The North German Plain, the Harz, and the Baltic coast. Centred at
        # 51.3 the box was entirely inland and came back 0% water, which threw
        # away the amphibious flank and the Baltic approaches that make this
        # theatre a coalition problem rather than a purely ground one.
        "lat": 53.40, "lon": 12.20, "extent_km": 480.0,
    },
    "north_atlantic": {
        "name": "North Atlantic",
        # The GIUK gap: the water every Atlantic submarine problem runs through.
        "lat": 61.50, "lon": -12.00, "extent_km": 768.0,
    },
}

HF_MAGIC = b"BTHF"
HF_VERSION = 2


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


def fetch_gmrt(spec, resolution=None):
    """Whole box in one request, as ESRI ASCII. Returns (lats, lons, grid).

    Latitudes ascend, so grid[0] is the SOUTHERN row -- the file itself stores
    rows north first, which is flipped here."""
    lat0, lat1, lon0, lon1 = box_for(spec)
    url = ("%s?minlongitude=%.5f&maxlongitude=%.5f&minlatitude=%.5f"
           "&maxlatitude=%.5f&format=esriascii&resolution=%s"
           % (GMRT, lon0, lon1, lat0, lat1, resolution or GMRT_RESOLUTION))
    proc = subprocess.run(["curl", "-s", "-m", "300", url],
                          capture_output=True, text=True)
    text = proc.stdout
    if not text.startswith("ncols"):
        raise RuntimeError("GMRT returned something unexpected: " + text[:200])

    lines = text.splitlines()
    hdr = {}
    for i in range(6):
        k, v = lines[i].split()
        hdr[k.lower()] = float(v)
    nc = int(hdr["ncols"]); nr = int(hdr["nrows"])
    x0 = hdr["xllcorner"]; y0 = hdr["yllcorner"]
    cs = hdr["cellsize"]; nodata = hdr["nodata_value"]

    rows = []
    for ln in lines[6:]:
        if not ln.strip():
            continue
        rows.append([float(x) for x in ln.split()])
    if len(rows) != nr:
        raise RuntimeError("GMRT row count %d != header %d" % (len(rows), nr))

    # North-first in the file, ascending latitude in memory.
    grid = [rows[nr - 1 - i] for i in range(nr)]

    # GMRT is gap-free over these boxes, but a NODATA cell would otherwise be a
    # -2 billion metre cliff, so patch any from the nearest real neighbour.
    holes = 0
    for i in range(nr):
        for j in range(nc):
            if grid[i][j] == nodata:
                holes += 1
                grid[i][j] = _nearest_real(grid, i, j, nodata, nr, nc)
    if holes:
        print("    patched %d NODATA cell(s)" % holes)

    lats = [y0 + (i + 0.5) * cs for i in range(nr)]
    lons = [x0 + (j + 0.5) * cs for j in range(nc)]
    return lats, lons, grid


def _nearest_real(grid, i, j, nodata, nr, nc):
    for r in range(1, 12):
        for di in (-r, 0, r):
            for dj in (-r, 0, r):
                a, b = i + di, j + dj
                if 0 <= a < nr and 0 <= b < nc and grid[a][b] != nodata:
                    return grid[a][b]
    return 0.0


def fetch_bulk(spec):
    """Whole box in one ERDDAP request. Returns (lats, lons, values[lat][lon]).

    Latitudes come back ascending; the caller flips as needed."""
    lat0, lat1, lon0, lon1 = box_for(spec)
    url = ("%s?altitude%%5B(%.5f):1:(%.5f)%%5D%%5B(%.5f):1:(%.5f)%%5D"
           % (ERDDAP, lat0, lat1, lon0, lon1))
    proc = subprocess.run(["curl", "-s", "-m", "180", url],
                          capture_output=True, text=True)
    body = proc.stdout
    if not body.startswith("latitude"):
        raise RuntimeError("ERDDAP returned something unexpected: " + body[:200])
    lat_index = {}
    lon_index = {}
    cells = {}
    for i, line in enumerate(body.splitlines()):
        if i < 2:
            continue
        parts = line.split(",")
        if len(parts) != 3:
            continue
        try:
            la = float(parts[0]); lo = float(parts[1]); v = float(parts[2])
        except ValueError:
            continue
        if la not in lat_index:
            lat_index[la] = True
        if lo not in lon_index:
            lon_index[lo] = True
        cells[(la, lo)] = v
    lats = sorted(lat_index)
    lons = sorted(lon_index)
    if len(lats) < 2 or len(lons) < 2:
        raise RuntimeError("ERDDAP subset too small: %d x %d" % (len(lats), len(lons)))
    grid = [[cells.get((la, lo), 0.0) for lo in lons] for la in lats]
    return lats, lons, grid


def _bilinear(lats, lons, grid, lat, lon):
    """Sample the source grid. Clamps at the edges rather than wrapping."""
    def span(arr, v):
        if v <= arr[0]:
            return 0, 0, 0.0
        if v >= arr[-1]:
            n = len(arr) - 1
            return n, n, 0.0
        lo, hi = 0, len(arr) - 1
        while hi - lo > 1:
            mid = (lo + hi) // 2
            if arr[mid] <= v:
                lo = mid
            else:
                hi = mid
        t = (v - arr[lo]) / (arr[hi] - arr[lo])
        return lo, hi, t
    i0, i1, ti = span(lats, lat)
    j0, j1, tj = span(lons, lon)
    a = grid[i0][j0]; b = grid[i0][j1]
    c = grid[i1][j0]; d = grid[i1][j1]
    return (a + (b - a) * tj) * (1.0 - ti) + (c + (d - c) * tj) * ti


def resample(spec, grid_n, lats, lons, src):
    """Onto the game grid, row-major from the NORTH edge."""
    lat0, lat1, lon0, lon1 = box_for(spec)
    out = []
    for r in range(grid_n):
        lat = lat1 - (lat1 - lat0) * (r + 0.5) / grid_n
        for c in range(grid_n):
            lon = lon0 + (lon1 - lon0) * (c + 0.5) / grid_n
            out.append(_bilinear(lats, lons, src, lat, lon))
    return out


def fetch_batch(points):
    locs = "|".join("%.6f,%.6f" % (a, b) for a, b in points)
    for attempt in range(5):
        proc = subprocess.run(
            ["curl", "-s", "-m", "60", "-G", "--data-urlencode",
             "locations=" + locs, POINT_API],
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


def write_hf(path, name, grid, cell_size_m, heights, lat=0.0, lon=0.0):
    """int16 metres. GEBCO spans about -11000..8800, which fits with room.

    The centre lat/lon is stored so the sim can ask for a place by name --
    without it a heightfield is just a picture and nothing can be checked
    against the real world."""
    nb = name.encode("utf-8")
    with open(path, "wb") as f:
        f.write(HF_MAGIC)
        f.write(struct.pack("<HIIfffH", HF_VERSION, grid, grid, cell_size_m,
                            lat, lon, len(nb)))
        f.write(nb)
        f.write(struct.pack("<%dh" % len(heights),
                            *[max(-32768, min(32767, int(round(h)))) for h in heights]))


def fetch(key, grid, use_bulk=True):
    spec = THEATRES[key]
    if use_bulk:
        try:
            lats, lons, src = fetch_gmrt(spec)
            source = "GMRT"
        except Exception as e:
            print("    GMRT unavailable (%s); falling back to ERDDAP" % str(e)[:80])
            lats, lons, src = fetch_bulk(spec)
            source = "ERDDAP/ETOPO1"
        heights = resample(spec, grid, lats, lons, src)
        os.makedirs(OUT_DIR, exist_ok=True)
        cell = spec["extent_km"] * 1000.0 / grid
        out = os.path.join(OUT_DIR, "%s.hf" % key)
        write_hf(out, spec["name"], grid, cell, heights, spec["lat"], spec["lon"])
        lo, hi = min(heights), max(heights)
        water = sum(1 for h in heights if h < 0) / float(len(heights)) * 100.0
        src_m = (lats[1] - lats[0]) * 110574.0 if len(lats) > 1 else 0.0
        print("  %-18s %d x %d @ %.0f m  from %s %d x %d @ %.0f m  "
              "elevation %.0f..%.0f m  %.0f%% water"
              % (key, grid, grid, cell, source, len(lons), len(lats), src_m,
                 lo, hi, water))
        return

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
    write_hf(out, spec["name"], grid, cell, done, spec["lat"], spec["lon"])

    lo, hi = min(done), max(done)
    water = sum(1 for h in done if h < 0) / float(total) * 100.0
    print("  %-18s %d x %d @ %.0f m  elevation %.0f..%.0f m  %.0f%% water  -> %s"
          % (key, grid, grid, cell, lo, hi, water, os.path.relpath(out, ROOT)))


# Grids matched to the 1 arc-minute source, so the game grid neither throws
# away detail nor invents it.
# Grids matched to GMRT's ~490 m source, so the game grid neither throws away
# detail nor invents it. Roughly 1 km cells, which is where ridgeline masking
# stops improving for theatres this size.
DEFAULT_GRID = {
    "taiwan_strait": 512,      # 1.00 km cells
    "korean_peninsula": 384,   # 0.90 km
    "central_europe": 512,     # 0.94 km
    "north_atlantic": 512,     # 1.50 km
}


def main(argv):
    grid = 0
    keys = []
    use_bulk = True
    i = 0
    while i < len(argv):
        if argv[i] == "--grid":
            grid = int(argv[i + 1]); i += 2
        elif argv[i] == "--points":
            use_bulk = False; i += 1
        else:
            keys.append(argv[i]); i += 1
    if not keys:
        keys = list(THEATRES)
    for k in keys:
        if k not in THEATRES:
            print("unknown theatre:", k)
            return 1
    if use_bulk:
        print("fetching %d theatre(s) from ERDDAP -- one request each" % len(keys))
    else:
        n = grid or 128
        calls = sum(math.ceil(n * n / BATCH) for _ in keys)
        print("fetching %d theatre(s) point-by-point at %dx%d -- %d calls, %.0f min"
              % (len(keys), n, n, calls, calls * DELAY_S / 60.0))
    for k in keys:
        g = grid or DEFAULT_GRID.get(k, 128)
        fetch(k, g, use_bulk)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
