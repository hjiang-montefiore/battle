"""Procedural camouflage textures, generated with numpy and saved as PNG.

Run inside Blender (numpy and the image API both come bundled):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/textures.py

Three schemes, which double as the faction-identification channel that
docs/07-art-pipeline.md says silhouette CANNOT provide for same-role variants.
"""
import bpy, numpy as np, os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "textures")
SIZE = 1024


def vnoise(h, w, res, rng):
    """Smooth value noise by bilinear upsample of a random lattice."""
    g = rng.random((res + 2, res + 2))
    g[res, :] = g[0, :]; g[res + 1, :] = g[1, :]      # wrap -> tileable
    g[:, res] = g[:, 0]; g[:, res + 1] = g[:, 1]
    ys = np.linspace(0, res, h, endpoint=False)
    xs = np.linspace(0, res, w, endpoint=False)
    y0 = ys.astype(int); x0 = xs.astype(int)
    fy = (ys - y0)[:, None]; fx = (xs - x0)[None, :]
    fy = fy * fy * (3 - 2 * fy); fx = fx * fx * (3 - 2 * fx)
    a = g[y0][:, x0]; b = g[y0 + 1][:, x0]
    c = g[y0][:, x0 + 1]; d = g[y0 + 1][:, x0 + 1]
    return a * (1 - fy) * (1 - fx) + b * fy * (1 - fx) + c * (1 - fy) * fx + d * fy * fx


def fbm(h, w, rng, octaves=4, base=5):
    out = np.zeros((h, w)); amp = 1.0; tot = 0.0
    for o in range(octaves):
        out += amp * vnoise(h, w, base * (2 ** o), rng)
        tot += amp; amp *= 0.5
    return out / tot


def camo(name, bands, seed, base_res=5, grain=0.035, panel=True):
    """bands: list of (threshold, rgb). Lowest threshold first."""
    rng = np.random.default_rng(seed)
    n = fbm(SIZE, SIZE, rng, 4, base_res)
    n = (n - n.min()) / (n.max() - n.min())

    # SOFT band boundaries. Hard thresholds read as printed plastic; real
    # camouflage is sprayed and its edges are a few centimetres wide.
    img = np.zeros((SIZE, SIZE, 3))
    wsum = np.zeros((SIZE, SIZE, 1))
    edge = 0.045
    prev = -1.0
    for thr, rgb in bands:
        # Both ramps used to reach zero at the SAME n, so wsum -> 0 and the
        # divide drove a 1-px black hairline along every band boundary. On a
        # stretched pattern those became continuous dark contour lines.
        # Offset the ramps so adjacent bands cross at 0.5 instead.
        lo = np.clip((n - prev) / edge + 1.0, 0, 1)
        hi = np.clip((thr - n) / edge + 1.0, 0, 1)
        w = (lo * lo * (3 - 2 * lo)) * (hi * hi * (3 - 2 * hi))
        w = w[..., None]
        img += w * np.array(rgb)
        wsum += w
        prev = thr
    img /= np.maximum(wsum, 1e-4)

    # per-band colour drift, so a "green" area is not one flat green
    img *= (0.88 + 0.24 * fbm(SIZE, SIZE, rng, 3, 11)[..., None])
    # fine grain
    img *= (1.0 + (rng.random((SIZE, SIZE, 1)) - 0.5) * grain)

    if panel:
        # A single-colour vehicle gets ALL of its contrast from surface
        # information. Without this an Abrams reads as carved sandstone.
        yy, xx = np.mgrid[0:SIZE, 0:SIZE]

        # Only DIRECTION-INDEPENDENT detail belongs in the texture now that the
        # projection is a world-scale cube. Height grime moved to the AO term.
        sc = fbm(SIZE, SIZE, rng, 4, 26)
        img *= np.where((sc > 0.68)[..., None], 1.24, 1.0)
        img *= np.where((sc < 0.26)[..., None], 0.82, 1.0)
        mot = fbm(SIZE, SIZE, rng, 3, 48)
        img *= (0.90 + 0.20 * mot[..., None])

    img = np.clip(img, 0, 1)
    rgba = np.dstack([img, np.ones((SIZE, SIZE, 1))]).astype(np.float32)

    os.makedirs(OUT, exist_ok=True)
    bi = bpy.data.images.new(name, SIZE, SIZE, alpha=False)
    bi.pixels = rgba.ravel()
    bi.filepath_raw = os.path.join(OUT, f"{name}.png")
    bi.file_format = "PNG"
    bi.save()
    print(f"  {name}.png  {SIZE}x{SIZE}")


SCHEMES = {
    # US — CARC desert sand, near-uniform with mottling (matches the reference photo)
    "camo_us": ([(0.44, (0.58, 0.52, 0.38)),
                 (0.74, (0.68, 0.61, 0.46)),
                 (1.01, (0.75, 0.69, 0.53))], 11, 4),
    # Germany — NATO three-colour: green / brown / black
    "camo_de": ([(0.42, (0.32, 0.36, 0.27)),
                 (0.80, (0.39, 0.32, 0.24)),
                 (1.01, (0.25, 0.26, 0.23))], 22, 6),
    # Russia — two-tone green
    "camo_ru": ([(0.50, (0.21, 0.26, 0.16)),
                 (1.01, (0.38, 0.42, 0.29))], 33, 4),
    # UK — NATO green/black, high contrast, few large patches
    "camo_uk": ([(0.52, (0.26, 0.31, 0.24)),
                 (1.01, (0.15, 0.16, 0.15))], 55, 4),
    # France — CE scheme, green / earth / black
    "camo_fr": ([(0.40, (0.33, 0.36, 0.26)),
                 (0.74, (0.42, 0.35, 0.24)),
                 (1.01, (0.17, 0.18, 0.16))], 66, 5),
    # PLA — digital-ish green over sand, tighter blobs
    "camo_cn": ([(0.38, (0.27, 0.32, 0.23)),
                 (0.70, (0.45, 0.44, 0.32)),
                 (1.01, (0.20, 0.23, 0.19))], 77, 8),
    # Taiwan — dark green / brown, humid-island palette
    "camo_tw": ([(0.46, (0.23, 0.29, 0.21)),
                 (0.80, (0.35, 0.30, 0.21)),
                 (1.01, (0.16, 0.19, 0.15))], 88, 5),
    # North Korea — flat single-tone olive, minimal maintenance
    "camo_kp": ([(0.58, (0.28, 0.31, 0.22)),
                 (1.01, (0.34, 0.36, 0.26))], 99, 3),
    # aircraft — low-visibility greys, the modern convention
    "air_grey":  ([(0.50, (0.42, 0.45, 0.48)),
                   (1.01, (0.52, 0.55, 0.58))], 121, 3),
    "air_dark":  ([(0.50, (0.22, 0.24, 0.27)),
                   (1.01, (0.30, 0.32, 0.35))], 131, 3),
    "air_white": ([(0.50, (0.66, 0.67, 0.68)),
                   (1.01, (0.74, 0.75, 0.76))], 141, 3),
    # the stealth tier. The F-117A is painted matt black (FS 36081) and it is
    # the only aircraft in the roster that is: from the fixed overhead camera
    # tone is the cue that survives when the outline does not, and an F-117
    # sits inside an F-15's bounding box at 94% nesting, so it has to win on
    # something other than planform. Two bands 0.055 -> 0.090 against
    # air_dark's 0.22 -> 0.30 and air_grey's 0.42 -> 0.52.
    "air_black": ([(0.50, (0.055, 0.058, 0.065)),
                   (1.01, (0.088, 0.092, 0.102))], 151, 3),
    # ground
    "terrain": ([(0.42, (0.32, 0.33, 0.24)),
                 (0.74, (0.38, 0.38, 0.28)),
                 (1.01, (0.44, 0.42, 0.32))], 44, 9),
}

print("generating textures...")
for name, (bands, seed, res) in SCHEMES.items():
    camo(name, bands, seed, res, panel=(name != "terrain"))
print("done")
