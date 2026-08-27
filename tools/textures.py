"""Procedural camouflage textures, generated with numpy and saved as PNG.

Run inside Blender (numpy and the image API both come bundled):
    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/textures.py

Three schemes, which double as the faction-identification channel that
docs/07-art-pipeline.md says silhouette CANNOT provide for same-role variants.

TEXTURE PASS (2026-08): this module now also carries the per-unit COMPOSE
pipeline — panel lines, weathering, insignia — that hero_models.py drives at
build time. Everything is seeded and deterministic; nothing is downloaded.
The compose inputs are world-space POSITION and NORMAL maps baked over the
unit's unique `bake` UV, so every layer works in metres, not in UV space:
a dust gradient is "the bottom 1.1 m", a decal is "0.9 m wide at this point".
"""
import bpy, math, numpy as np, os

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
    # strike/CAS/bomber camouflage — European One: two greens and a dark
    # grey. The role channel the air roster needs: air-superiority is GREY,
    # mud-movers are GREEN, and the two never meet in band space.
    "air_camo": ([(0.40, (0.24, 0.28, 0.22)),
                  (0.75, (0.33, 0.36, 0.27)),
                  (1.01, (0.28, 0.29, 0.30))], 161, 4),
    # army helicopters — overall olive drab, two close tones
    "helo_drab": ([(0.55, (0.23, 0.25, 0.18)),
                   (1.01, (0.29, 0.31, 0.22))], 171, 3),
    # navy — haze grey (FS 26270 territory). Deliberately LIGHTER than
    # air_dark and flatter than air_grey: a warship is one colour and gets
    # its life from the compose pass (boot topping, rust, deck tone), so the
    # two bands sit close. Subs keep air_dark — a haze-grey submarine would
    # surrender the strongest sub-vs-surface tone cue the roster has.
    "navy_haze": ([(0.52, (0.44, 0.465, 0.48)),
                   (1.01, (0.51, 0.53, 0.545))], 181, 3),
    # submarines — near-uniform anechoic dark, NO_PANEL. air_dark carries the
    # panel speckle tuned for a 2.8 m aircraft tile; sampled at a submarine's
    # 9 m ship tile that speckle blows up to ~1 m blocks and the whole boat
    # rendered as stone masonry (seen on the 2026-08 sub band sheet). Same
    # tone ladder as air_dark — the sub-vs-surface cue survives — minus the
    # grain that had nothing to do with rubber tiles.
    # Bands only 10% apart: even with NO_PANEL the compose pass still showed
    # masonry, and the composed texture pinned it on the per-band colour
    # drift (fbm base 11 — ~0.8 m features at a 9 m tile) amplifying a wide
    # band step. Close bands + the subs' small camo_scale turn both into
    # fine grain.
    "sub_dark": ([(0.50, (0.215, 0.23, 0.253)),
                  (1.01, (0.238, 0.253, 0.275))], 191, 3),
    # ground
    "terrain": ([(0.42, (0.32, 0.33, 0.24)),
                 (0.74, (0.38, 0.38, 0.28)),
                 (1.01, (0.44, 0.42, 0.32))], 44, 9),
}


# ════════════════════════════════════════════════════════════════════
# THE COMPOSE PIPELINE — per-unit textures
#
# hero_models.apply_composed_texture() bakes, per material group,
#     pos  (res,res,3)  world position in metres
#     nrm  (res,res,3)  world unit normal
#     ao   (H,W)        the existing AO bake (SURVIVES separately as the glTF
#                       occlusionTexture — here it is only a MASK for wear)
# over the unit's unique non-overlapping `bake` UV, then calls compose().
# Layer order:  base camo -> tonal mottle -> panel lines -> weathering
#               (dust / streaks / exhaust / edge wear) -> insignia.
#
# Stated resolution per unit size class:
SIZE_CLASS = {"vehicle": 1024, "aircraft": 1024, "ship": 2048, "structure": 1024}
# metres of world per camo tile, per size class (a ship's blotches are not
# tank-sized):
CAMO_SCALE = {"vehicle": 2.2, "aircraft": 2.8, "ship": 9.0, "structure": 3.0}
UNIT_TEX_DIR = os.path.join(OUT, "units")


def seed_of(name):
    """Deterministic across processes — hash() is salted, this is not."""
    return sum(ord(c) * (i + 11) for i, c in enumerate(name)) & 0x7FFFFFFF


def load_png(name):
    """art/textures/{name}.png -> float (H,W,3), values exactly as stored."""
    img = bpy.data.images.load(os.path.join(OUT, f"{name}.png"),
                               check_existing=True)
    w, h = img.size
    arr = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, img.channels)
    return arr[..., :3]


def save_unit_png(name, rgb):
    """Write art/textures/units/{name}.png and return the bpy image, ready to
    plug straight into a material (the glTF exporter packs it)."""
    os.makedirs(UNIT_TEX_DIR, exist_ok=True)
    h, w = rgb.shape[:2]
    old = bpy.data.images.get(name)
    if old is not None:
        bpy.data.images.remove(old)
    img = bpy.data.images.new(name, w, h, alpha=False)
    rgba = np.dstack([np.clip(rgb, 0, 1),
                      np.ones((h, w, 1), np.float32)]).astype(np.float32)
    img.pixels = rgba.ravel()
    img.filepath_raw = os.path.join(UNIT_TEX_DIR, f"{name}.png")
    img.file_format = "PNG"
    img.save()
    return img


# ── samplers ────────────────────────────────────────────────────────
def _sample_rgb(img, u, v):
    """Bilinear, wrapping. img (H,W,3); u,v arrays in tile units."""
    h, w = img.shape[:2]
    x = (u % 1.0) * w; y = (v % 1.0) * h
    x0 = np.floor(x).astype(np.int32) % w
    y0 = np.floor(y).astype(np.int32) % h
    x1 = (x0 + 1) % w; y1 = (y0 + 1) % h
    fx = (x - np.floor(x))[..., None]; fy = (y - np.floor(y))[..., None]
    return (img[y0, x0] * (1 - fy) * (1 - fx) + img[y1, x0] * fy * (1 - fx)
            + img[y0, x1] * (1 - fy) * fx + img[y1, x1] * fy * fx)


def _sample_gray(img, u, v):
    return _sample_rgb(img[..., None], u, v)[..., 0]


def _resize(arr, res):
    h, w = arr.shape[:2]
    if h == res and w == res:
        return arr
    ys = np.linspace(0, h - 1, res); xs = np.linspace(0, w - 1, res)
    y0 = np.floor(ys).astype(int); x0 = np.floor(xs).astype(int)
    y1 = np.minimum(y0 + 1, h - 1); x1 = np.minimum(x0 + 1, w - 1)
    fy = (ys - y0)[:, None]; fx = (xs - x0)[None, :]
    if arr.ndim == 3:
        fy = fy[..., None]; fx = fx[..., None]
    return (arr[y0][:, x0] * (1 - fy) * (1 - fx) + arr[y1][:, x0] * fy * (1 - fx)
            + arr[y0][:, x1] * (1 - fy) * fx + arr[y1][:, x1] * fy * fx)


def _wnoise(a, b, period, rng, octaves=3, base=4, res=256):
    """Tileable fbm sampled by WORLD coordinates a,b at `period` metres."""
    img = fbm(res, res, rng, octaves, base)
    img = (img - img.min()) / (img.max() - img.min() + 1e-9)
    return _sample_gray(img.astype(np.float32), a / period, b / period)


def _project2d(pos, nrm):
    """Dominant-axis planar coords (a,b) per texel + the axis id.

    This is the numpy twin of the world-scale cube projection the blockouts
    use for UV0 — it lets compose() lay the same camo down on the unique
    unwrap without a diffuse bake."""
    ax = np.argmax(np.abs(nrm), axis=-1)
    a = np.where(ax == 0, pos[..., 1], pos[..., 0])
    b = np.where(ax == 2, pos[..., 1], pos[..., 2])
    return a.astype(np.float32), b.astype(np.float32), ax


def _texel_size(pos, valid):
    """Median metres-per-texel — needed so line widths hold at any res."""
    d = np.linalg.norm(np.diff(pos, axis=1), axis=-1)
    vv = valid[:, 1:] & valid[:, :-1]
    d = d[vv & (d > 1e-7)]
    if d.size == 0:
        return 0.01
    return float(np.median(d))


def _seam_mask(pos, texel, k=4.0):
    """Texels where world position JUMPS between neighbours: unwrap island
    borders — which smart_project cuts at hard angles, i.e. at the real
    plate boundaries of the model. Free panel lines along natural seams."""
    m = np.zeros(pos.shape[:2], bool)
    j = np.linalg.norm(np.diff(pos, axis=0), axis=-1) > k * texel
    m[:-1] |= j; m[1:] |= j
    j = np.linalg.norm(np.diff(pos, axis=1), axis=-1) > k * texel
    m[:, :-1] |= j; m[:, 1:] |= j
    return m


# ── layers ──────────────────────────────────────────────────────────
def panel_lines(pos, nrm, a, b, ax, texel, spacing=1.6, strength=0.5,
                jitter=0.10, seams=0.55, seed=0, width=None):
    """Multiplicative field: per-panel value shifts + darkened seams.

    Two sources: a world-space panel grid (`spacing` metres, hashed per cell
    for the value shift — this is what makes a big flat plate read as built
    from plates), and the geometry seam mask (island borders = real part
    outlines)."""
    sp2 = spacing * 0.72
    ia = np.floor(a / spacing).astype(np.int64)
    ib = np.floor(b / sp2).astype(np.int64)
    h = (ia * 73856093) ^ (ib * 19349663) ^ (ax.astype(np.int64) * 83492791) \
        ^ np.int64(seed)
    r = (h & 0xFFFF).astype(np.float32) / 65535.0
    field = 1.0 + (r - 0.5) * 2 * jitter

    fa = a / spacing - ia; fb_ = b / sp2 - ib
    d = np.minimum(np.minimum(fa, 1 - fa) * spacing,
                   np.minimum(fb_, 1 - fb_) * sp2)
    # `width` (additive, 2026-08 navy pass): explicit seam width in METRES.
    # The texel-scaled default is right for a 7 m tank at 1024 px but on a
    # 155 m hull the texel is ~20 cm and 2.6 texels of quintic falloff drew
    # a 50 cm soft grout line — the destroyer close-up read as bathroom
    # tile. Ships pass width≈0.3; everything that doesn't builds as before.
    wline = width if width is not None else max(texel * 2.6, 0.02)
    wline = max(wline, texel * 1.2, 0.02)   # never sub-texel: lines must not alias away
    line = np.clip(1 - d / wline, 0, 1)
    field = field * (1 - strength * 0.75 * line ** 1.5)

    field = field * np.where(_seam_mask(pos, texel), 1 - strength * seams, 1.0)
    return field.astype(np.float32)


def concrete_field(pos, nrm, a, b, rng, zmin=0.0, roof_above=2.0,
                   gravel=0.16, gravel_lift=1.65, wall=0.13, apron=0.08,
                   gravel_scale=0.45, apron_lift=1.0):
    """Multiplicative concrete finish for STRUCTURES — the layer that makes a
    roof deck read as gravel ballast and a wall read as weathered render.

    Three surface families, split by normal and height (world metres):
      * up-facing above zmin+roof_above  -> ROOF: two-scale gravel grain plus
        a small mean lift, so a roof deck and the apron below it stop being
        the same flat pour;
      * near-vertical                    -> WALL: rain-tone streaking, long in
        Z and short across, the way weather actually runs down concrete;
      * up-facing below the roof line    -> APRON/PAD: broad pour mottle only.
    Everything is a factor around 1.0 — the value LADDER between camo wall
    (0.588) and concrete deck (0.098) survives untouched.
    """
    z = pos[..., 2]
    nz = nrm[..., 2]
    up = nz > 0.55
    vert = np.abs(nz) < 0.45
    roof = up & (z > zmin + roof_above)
    ground = up & ~roof
    f = np.ones(z.shape, np.float32)
    if gravel > 0:
        g1 = _wnoise(a, b, gravel_scale, rng, octaves=2, base=8)
        g2 = rng.random(z.shape).astype(np.float32)
        f = np.where(roof, f * gravel_lift
                     * (1.0 + gravel * (g1 - 0.5) * 2.0)
                     * (1.0 + 0.5 * gravel * (g2 - 0.5)), f)
    else:
        # smooth poured concrete still varies pour to pour
        g1 = _wnoise(a, b, 2.6, rng, octaves=2, base=5)
        f = np.where(roof, f * (1.0 + 0.10 * (g1 - 0.5) * 2.0), f)
    s = _wnoise(a, z * 0.22, 1.7, rng, octaves=2, base=6)
    f = np.where(vert, f * (1.0 + wall * (s - 0.5) * 2.0), f)
    m = _wnoise(a, b, 6.0, rng, octaves=2, base=4)
    # apron_lift (additive, structures pass 2): ground-level ASPHALT needs a
    # mean shift to read at all — ±22% of 0.048 albedo is invisible, but aged
    # sun-bleached tarmac genuinely sits at ~1.3x fresh, and the patch mottle
    # then spans values the eye can find while the ladder order survives.
    f = np.where(ground, f * apron_lift * (1.0 + apron * (m - 0.5) * 2.0), f)
    return f.astype(np.float32)


def ao_grime(ao2, a, b, rng, strength=0.35, threshold=0.55):
    """Blend-factor field: grime pooled where the AO bake is already dark —
    the base of every vent box, duct, parapet and mast lands a stain without
    any of them needing coordinates. Noise-broken so it reads as dirt, not as
    a second AO pass."""
    g = np.clip((threshold - ao2) / max(threshold, 1e-4), 0, 1)
    g = g * (0.45 + 0.65 * _wnoise(a, b, 1.1, rng, octaves=2, base=8))
    return np.clip(strength * g, 0, 1).astype(np.float32)


def dust_gradient(pos, nrm, a, b, rng, zmin=0.0, height=1.2,
                  strength=0.45, tint=(0.45, 0.40, 0.31)):
    """Factor field for dust rising from the running gear. Blend to `tint`."""
    z = pos[..., 2]
    f = np.clip(1.0 - (z - zmin) / height, 0, 1) ** 1.5
    m = _wnoise(a, b, max(height * 1.7, 0.5), rng, octaves=3, base=6)
    f = strength * f * (0.45 + 0.75 * m)
    f = np.where(nrm[..., 2] < -0.5, f * 0.25, f)   # not on the belly
    return np.clip(f, 0, 1).astype(np.float32)


def rust_streaks(pos, nrm, a, rng, z0, length=7.0, density=0.35,
                 strength=0.5, tint=(0.30, 0.22, 0.16)):
    """Vertical grime/rust columns running DOWN from z0 (a ship's deck edge,
    scupper line). Sparse columns keyed on the horizontal coordinate."""
    z = pos[..., 2]
    c = 0.62 * _wnoise(a, np.zeros_like(a), length * 1.6, rng, 2, 12) \
        + 0.38 * _wnoise(a, np.zeros_like(a), length * 0.37, rng, 2, 16)
    sharp = np.clip((c - (1 - density)) / 0.10, 0, 1)
    below = np.where(z < z0, np.exp(-np.clip(z0 - z, 0, None) / (length * 0.45)), 0.0)
    vert = np.clip((0.6 - np.abs(nrm[..., 2])) / 0.6, 0, 1)
    return np.clip(strength * sharp * below * vert, 0, 1).astype(np.float32)


def exhaust_streak(pos, nrm, rng, origin=(0, 0, 0), direction=(0, 1, 0),
                   length=2.5, width=0.4, strength=0.6):
    """Soot cone from `origin` along `direction`, widening as it runs."""
    d = np.array(direction, np.float32)
    d = d / (np.linalg.norm(d) + 1e-9)
    v = pos - np.array(origin, np.float32)
    t = v @ d
    r = np.linalg.norm(v - t[..., None] * d, axis=-1)
    wt = width * (1 + 1.8 * np.clip(t, 0, None) / length)
    f = strength * np.exp(-(r / np.maximum(wt, 1e-4)) ** 2) \
        * np.clip(1 - t / length, 0, 1) * (t > -0.15)
    m = _wnoise(t, r * 3.0, max(length * 0.5, 0.4), rng, 2, 8)
    return np.clip(f * (0.55 + 0.65 * m), 0, 1).astype(np.float32)


def tint_spot(pos, center, radius, strength=0.6):
    """Factor field for a locally repainted REGION — a radome, an anti-glare
    panel, a di-electric fairing. Solid inside `radius` of `center`, with a
    soft ~25% falloff band so the paint edge is sprayed, not decal-cut."""
    d = np.linalg.norm(pos - np.array(center, np.float32), axis=-1)
    f = np.clip((radius - d) / (radius * 0.25 + 1e-6), 0, 1)
    return (strength * f).astype(np.float32)


def edge_wear(ao, strength=0.4):
    """Additive highlight field from the AO bake's own gradients: worn bright
    edges where occlusion transitions to fully lit (an AO-inverse)."""
    a = ao
    b = (a + np.roll(a, 1, 0) + np.roll(a, -1, 0)
         + np.roll(a, 1, 1) + np.roll(a, -1, 1)) / 5.0
    gy, gx = np.gradient(b)
    g = np.sqrt(gx * gx + gy * gy)
    e = np.clip(g * 10, 0, 1) * np.clip((b - 0.70) / 0.30, 0, 1)
    return (strength * e).astype(np.float32)


# ── insignia ────────────────────────────────────────────────────────
_SS = 2      # stamps are rasterised supersampled then box-filtered


def _grid(px):
    n = px * _SS
    c = (np.arange(n) + 0.5) / n * 2 - 1
    return np.meshgrid(c, c)


def _down(arr):
    h, w = arr.shape[:2]
    return arr.reshape(h // _SS, _SS, w // _SS, _SS, arr.shape[2]).mean((1, 3))


def _poly_mask(xx, yy, pts):
    inside = np.zeros(xx.shape, bool)
    n = len(pts)
    for i in range(n):
        x0, y0 = pts[i]; x1, y1 = pts[(i + 1) % n]
        cond = (y0 > yy) != (y1 > yy)
        xi = x0 + (yy - y0) / (y1 - y0 + 1e-12) * (x1 - x0)
        inside ^= cond & (xx < xi)
    return inside


def _star_pts(points=5, r=1.0, inner=0.382, rot=math.pi / 2):
    pts = []
    for k in range(points * 2):
        rr = r if k % 2 == 0 else r * inner
        an = rot + k * math.pi / points
        pts.append((math.cos(an) * rr, math.sin(an) * rr))
    return pts


def _paint(layers, px):
    """layers: [(mask, rgb)] painted in order -> (px,px,4) RGBA float."""
    xxshape = layers[0][0].shape
    rgb = np.zeros((*xxshape, 3), np.float32)
    alpha = np.zeros((*xxshape, 1), np.float32)
    for mask, col in layers:
        m = mask[..., None].astype(np.float32)
        rgb = rgb * (1 - m) + np.array(col, np.float32) * m
        alpha = np.maximum(alpha, m)
    return _down(np.dstack([rgb, alpha]))


_FONT = {  # 5x7, enough for pennant numbers
    "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
    "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
    "2": ["01110", "10001", "00001", "00110", "01000", "10000", "11111"],
    "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
    "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
    "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
    "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
    "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
    "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
    "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
}


def _text_mask(xx, yy, text, h=1.6):
    """Rows of 5x7 glyphs centred in the stamp. h = glyph height in stamp
    units (stamp spans -1..1)."""
    mask = np.zeros(xx.shape, bool)
    n = len(text)
    gw = h * 5.0 / 7.0
    adv = gw * 1.25
    total = adv * n - (adv - gw)
    x0 = -total / 2
    for i, ch in enumerate(text):
        bits = _FONT.get(ch)
        if bits is None:
            continue
        gx = (xx - (x0 + i * adv)) / gw          # 0..1 across glyph
        gy = (h / 2 - yy) / h                    # 0..1 down glyph
        ok = (gx >= 0) & (gx < 1) & (gy >= 0) & (gy < 1)
        col = np.clip((gx * 5).astype(int), 0, 4)
        row = np.clip((gy * 7).astype(int), 0, 6)
        arr = np.array([[c == "1" for c in r] for r in bits])
        mask |= ok & arr[row, col]
    return mask


def insignia_stamp(kind, px=256, text=None, color=None):
    """Vector-ish raster stamps, RGBA (px,px,4). Kinds:
    star_us, cross_de, roundel_uk, roundel_fr, star_ru, star_cn, star_kp,
    sun_tw, helipad, pennant (needs text="62")."""
    xx, yy = _grid(px)
    rr = np.sqrt(xx * xx + yy * yy)
    white = (0.92, 0.92, 0.90)
    if kind == "star_us":
        col = color or white
        star = _poly_mask(xx, yy, _star_pts(5, 0.94))
        ring = (rr < 0.99) & (rr > 0.90)
        return _paint([(ring, col), (star, col)], px)
    if kind == "cross_de":
        lim = (np.abs(xx) < 0.95) & (np.abs(yy) < 0.95)
        outer = lim & ((np.abs(xx) < 0.34) | (np.abs(yy) < 0.34))
        inner = lim & ((np.abs(xx) < 0.20) | (np.abs(yy) < 0.20))
        return _paint([(outer, white), (inner, (0.05, 0.05, 0.05))], px)
    if kind == "roundel_uk":
        return _paint([(rr < 0.95, (0.05, 0.13, 0.34)),
                       (rr < 0.62, white),
                       (rr < 0.30, (0.62, 0.09, 0.11))], px)
    if kind == "roundel_fr":
        return _paint([(rr < 0.95, (0.62, 0.09, 0.11)),
                       (rr < 0.62, white),
                       (rr < 0.30, (0.05, 0.13, 0.34))], px)
    if kind == "star_ru":
        return _paint([(_poly_mask(xx, yy, _star_pts(5, 0.98)), white),
                       (_poly_mask(xx, yy, _star_pts(5, 0.80)),
                        (0.60, 0.08, 0.08))], px)
    if kind == "star_cn":
        return _paint([(_poly_mask(xx, yy, _star_pts(5, 0.98)),
                        (0.85, 0.70, 0.12)),
                       (_poly_mask(xx, yy, _star_pts(5, 0.78)),
                        (0.60, 0.08, 0.08))], px)
    if kind == "star_kp":
        return _paint([(rr < 0.98, white),
                       (_poly_mask(xx, yy, _star_pts(5, 0.80)),
                        (0.60, 0.08, 0.08))], px)
    if kind == "sun_tw":
        return _paint([(rr < 0.98, (0.05, 0.13, 0.34)),
                       (_poly_mask(xx, yy, _star_pts(12, 0.66, inner=0.55)),
                        white)], px)
    if kind == "helipad":
        ring = (rr < 0.96) & (rr > 0.84)
        hbar = (np.abs(yy) < 0.42) & (np.abs(np.abs(xx) - 0.24) < 0.08)
        hmid = (np.abs(yy) < 0.08) & (np.abs(xx) < 0.24)
        return _paint([(ring, white), (hbar | hmid, white)], px)
    if kind == "pennant":
        col = color or white
        t = text or "0"
        # Auto-fit: at the default h=1.6 anything past one glyph overruns the
        # -1..1 stamp and is clipped by the decal window. Solve h so the row
        # spans at most 1.9 stamp units (total = gw * (1.25 n - 0.25)).
        h = min(1.5, 1.9 / ((5.0 / 7.0) * (1.25 * len(t) - 0.25)))
        return _paint([(_text_mask(xx, yy, t, h=h), col)], px)
    raise KeyError(f"unknown insignia kind {kind!r}")


INSIGNIA = ["star_us", "cross_de", "roundel_uk", "roundel_fr", "star_ru",
            "star_cn", "star_kp", "sun_tw", "helipad", "pennant"]


def project_decal(img, pos, nrm, stamp, center, normal, size,
                  up=None, alpha=1.0):
    """Alpha-blend `stamp` onto img, decal-projected in WORLD space: painted
    where the surface faces `normal` within a size*0.75 slab of `center`.
    No geometry involved — this is why insignia cannot leak to the far side
    (the depth window and the facing test both cut it)."""
    n = np.array(normal, np.float32)
    n = n / (np.linalg.norm(n) + 1e-9)
    if up is None:
        up = (0.0, -1.0, 0.0) if abs(n[2]) > 0.8 else (0.0, 0.0, 1.0)
    u_ = np.array(up, np.float32)
    ua = np.cross(u_, n); ua = ua / (np.linalg.norm(ua) + 1e-9)
    va = np.cross(n, ua)
    rel = pos - np.array(center, np.float32)
    u = (rel @ ua) / size + 0.5
    v = (rel @ va) / size + 0.5
    ok = ((u >= 0) & (u < 1) & (v >= 0) & (v < 1)
          & ((nrm @ n) > 0.35) & (np.abs(rel @ n) < size * 0.75))
    if not ok.any():
        return img
    S = stamp.shape[0]
    xi = np.clip((u * S).astype(int), 0, S - 1)
    yi = np.clip((v * S).astype(int), 0, S - 1)
    sm = stamp[yi, xi]
    a = sm[..., 3:] * alpha * ok[..., None]
    return img * (1 - a) + sm[..., :3] * a


# ── the orchestrator ────────────────────────────────────────────────
def compose(unit, group, camo_png, base_rgb, pos, nrm, ao, features):
    """base camo -> tonal mottle -> panel lines -> weathering -> insignia.

    pos/nrm: world maps baked over the unique unwrap. ao: the existing AO
    bake, used only as a MASK (it ships separately as occlusionTexture, so
    it composites WITH this albedo rather than being overwritten by it).
    Returns float RGB at pos's resolution, same value space as the camo PNGs.
    """
    res = pos.shape[0]
    # Per-GROUP overrides (additive, 2026-08): one unit's deck and body can
    # want different layers — a building's concrete apron is not its painted
    # wall. Keys under groups_override[group] REPLACE the top-level key.
    ov = features.get("groups_override") or {}
    if group in ov:
        features = {**features, **ov[group]}
    rng = np.random.default_rng(seed_of(f"{unit}:{group}"))
    nlen = np.linalg.norm(nrm, axis=-1)
    valid = np.abs(nlen - 1.0) < 0.35
    n = (nrm / np.maximum(nlen, 1e-6)[..., None]).astype(np.float32)
    sc = features.get("size_class", "vehicle")
    scale = float(features.get("camo_scale") or CAMO_SCALE.get(sc, 2.2))
    a, b, ax = _project2d(pos, n)

    if camo_png:
        base = _sample_rgb(load_png(camo_png), a / scale, b / scale)
    else:
        base = np.ones((res, res, 3), np.float32) * np.array(base_rgb, np.float32)
    img = base.astype(np.float32)

    # 1. tonal variation at the scale of the WHOLE unit — the layer that
    # separates steel from plastic at RTS zoom
    if valid.any():
        vp = pos[valid]
        span = float(max(vp[:, 0].max() - vp[:, 0].min(),
                         vp[:, 1].max() - vp[:, 1].min(),
                         vp[:, 2].max() - vp[:, 2].min(), 1.0))
        zmin = float(vp[:, 2].min())
    else:
        span, zmin = 10.0, 0.0
    macro = _wnoise(a, b, span * 0.55, rng, octaves=3, base=3)
    img = img * (0.93 + 0.14 * macro)[..., None]
    mid = _wnoise(a, b, max(span * 0.09, 0.8), rng, octaves=2, base=6)
    img = img * (0.94 + 0.12 * mid)[..., None]

    # 1b. local repaints (radomes, fairings) — paint, so UNDER panel lines
    # and weathering
    for t in features.get("tints") or []:
        f = tint_spot(pos, t["center"], t["radius"],
                      t.get("strength", 0.6))[..., None]
        img = img * (1 - f) + np.array(t["rgb"], np.float32) * f

    texel = _texel_size(pos, valid)

    # 1b. concrete finish (structures): roof gravel vs wall tone vs apron
    ccfg = features.get("concrete")
    if ccfg is not None:
        img = img * concrete_field(pos, n, a, b, rng, zmin=zmin,
                                   **ccfg)[..., None]

    # 2. panel lines + per-panel value shifts
    pcfg = features.get("panels")
    if pcfg is not None:
        img = img * panel_lines(pos, n, a, b, ax, texel,
                                seed=seed_of(unit), **pcfg)[..., None]

    # 3. weathering
    wx = features.get("weathering") or {}
    ao2 = _resize(ao.astype(np.float32), res)
    if "deckpaint" in wx:
        # Flat-paint every UP-FACING surface above z0 — how a carrier's
        # flight deck (which lives in the `body` group, not `deck`) gets its
        # dark non-slip coat without touching geometry. Keeps the mid-scale
        # mottle so the acreage doesn't go back to reading as plastic.
        cfg = dict(wx["deckpaint"])
        tint = np.array(cfg.pop("tint", (0.16, 0.165, 0.17)), np.float32)
        z0 = float(cfg.pop("z0")); st = float(cfg.pop("strength", 1.0))
        f = st * np.clip((pos[..., 2] - z0) / max(texel * 2, 0.1), 0, 1) \
            * np.clip((n[..., 2] - 0.55) / 0.30, 0, 1)
        f = (f * valid)[..., None]
        paint = tint * (0.90 + 0.20 * mid[..., None])
        img = img * (1 - f) + paint * f
    if "boottop" in wx:
        # The waterline boot-topping stripe. PAINT, so it goes down first and
        # the rust runs over it. Vertical surfaces only — the band must not
        # creep onto a low deck or a sponson underside.
        cfg = dict(wx["boottop"])
        tint = np.array(cfg.pop("tint", (0.045, 0.048, 0.052)), np.float32)
        z1 = float(cfg.pop("z1", 1.0)); z0 = float(cfg.pop("z0", -10.0))
        zz = pos[..., 2]
        e = max(texel * 1.5, 0.05)
        f = np.clip((z1 - zz) / e, 0, 1) * np.clip((zz - z0) / e, 0, 1)
        f = f * np.clip((0.55 - np.abs(n[..., 2])) / 0.35, 0, 1)
        f = (f * valid)[..., None]
        img = img * (1 - f) + tint * f
    if "dust" in wx:
        cfg = dict(wx["dust"]); tint = np.array(cfg.pop("tint", (0.45, 0.40, 0.31)), np.float32)
        f = dust_gradient(pos, n, a, b, rng, zmin=zmin, **cfg)[..., None]
        img = img * (1 - f) + tint * f
    # streaks: one dict or a list of them — a ship rusts from its scuppers
    # AND from its hawse pipes, at two different z0.
    scfgs = wx.get("streaks")
    for cfg in ([scfgs] if isinstance(scfgs, dict) else scfgs or []):
        cfg = dict(cfg); tint = np.array(cfg.pop("tint", (0.30, 0.22, 0.16)), np.float32)
        f = rust_streaks(pos, n, a, rng, **cfg)[..., None]
        img = img * (1 - f) + tint * f
    for e in wx.get("exhaust") or []:
        e = dict(e)
        tint = np.array(e.pop("tint", (0.06, 0.058, 0.055)), np.float32)
        f = exhaust_streak(pos, n, rng, **e)[..., None]
        img = img * (1 - f) + tint * f
    # stains: the exhaust cone reused as a grime/soot smudge with its own
    # tint — stack soot, drips below a known fixture. Coordinates in metres.
    for e in wx.get("stains") or []:
        cfg = dict(e)
        tint = np.array(cfg.pop("tint", (0.10, 0.096, 0.09)), np.float32)
        f = exhaust_streak(pos, n, rng, **cfg)[..., None]
        img = img * (1 - f) + tint * f
    if "ao_grime" in wx:
        cfg = dict(wx["ao_grime"])
        tint = np.array(cfg.pop("tint", (0.13, 0.125, 0.115)), np.float32)
        f = ao_grime(ao2, a, b, rng, **cfg)[..., None]
        img = img * (1 - f) + tint * f
    if "edge_wear" in wx:
        img = img * (1 + edge_wear(ao2, **wx["edge_wear"]))[..., None]

    # 4. insignia
    for spec in features.get("insignia") or []:
        st = insignia_stamp(spec["kind"], text=spec.get("text"),
                            color=spec.get("color"))
        img = project_decal(img, pos, n, st, spec["center"], spec["normal"],
                            spec["size"], spec.get("up"),
                            spec.get("alpha", 1.0))

    # background/JPEG-bleed fill
    if valid.any():
        fill = np.median(img[valid].reshape(-1, 3), axis=0)
        img = np.where(valid[..., None], img, fill)
    return np.clip(img, 0, 1).astype(np.float32)


# Schemes that must NOT carry the fine panel mottle: terrain never wanted it,
# and navy_haze turns into carved concrete with it — at a ship's 15+ m camo
# scale the "panel" speckle lands at 30 cm and reads as stone grain. A ship's
# tonal life comes from the compose pass instead.
NO_PANEL = {"terrain", "navy_haze", "sub_dark"}


def generate_all():
    print("generating textures...")
    for name, (bands, seed, res) in SCHEMES.items():
        camo(name, bands, seed, res, panel=(name not in NO_PANEL),
             grain=(0.02 if name in NO_PANEL else 0.035))
    print("done")


if __name__ == "__main__":
    generate_all()
