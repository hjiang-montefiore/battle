"""Adversarial top-down confusion audit for the 19 structures.

    Blender -b --python tools/structure_confusion.py

WHAT THIS MEASURES, AND WHY NOT verify_shape.py
-----------------------------------------------
verify_shape.py asks "does this model match a reference photograph". That is a
FIDELITY question. This asks a LEGIBILITY question: from the fixed overhead RTS
camera, do any two of the nineteen structures occupy the same picture? A high
score here is BAD.

METHOD (stated precisely, because the number is worthless without it)
--------------------------------------------------------------------
Pass A - SILHOUETTE. Each LOD0 GLB is imported alone into an empty scene, every
material replaced by a pure white emission shader, the world set to black, and
the scene rendered through an ORTHOGRAPHIC camera looking straight down (-Z)
from +Z, centred on the world origin where every model is already centred.
ortho_scale is the SAME 48.0 m for all nineteen - the largest cell in the
roster - at 960 px, i.e. a fixed 20.0 px/m. So pass A yields a true-scale
binary plan mask for every structure in one common coordinate frame:
    mask = luminance > 0.5

Pass B - ROOF READ. Same camera, same framing, but the real exported materials,
the standard three-light rig from gameplay_render.py (sun elev 42, azim 140),
AgX view transform and glTF occlusion applied - i.e. what the audit sheets are
lit with. Pass B gives the luminance INSIDE the pass A mask: the roof pattern.

NORMALISATION. Three different normalisations, because they answer three
different questions and only reporting one of them would be cheating:

  iou_shape   crop each mask to its own bounding box, then scale it UNIFORMLY
              (one factor for both axes, so proportion is preserved) to fit a
              128 x 128 box and centre it. Compares SHAPE + ASPECT, ignores
              SIZE. This is the headline number.
  iou_stretch crop to bbox then scale each axis independently to fill 128 x 128.
              Compares OUTLINE ONLY - a 2:1 slab and a square become the same
              picture. Reported as an upper bound, not as the verdict.
  iou_true    no rescaling at all. Both true-scale masks are centred on their
              own centroid in the common 20 px/m frame and intersected. This is
              the only one that knows a bunker is 10 m and an airbase is 48 m.

  roof_iou    the ROOF PATTERN. Take pass B luminance inside the mask, uniformly
              normalise exactly as iou_shape does, then split each structure at
              its OWN median luminance and take the IoU of the two dark sets.
              Both sets are 50% of their mask by construction, so the floor for
              two unrelated patterns is 0.5^2/(2*0.5-0.5^2) = 0.333 and the
              ceiling for identical patterns is 1.0.

Resampling is exact area-average, done as two matrix multiplies with overlap
weight matrices, so no pixel is dropped or double counted.

WHY BOTH. Silhouette IoU alone will say almost every building in an RTS is the
same building, because they are all roughly square things on square aprons.
That is a true and useful finding, but it is only half the sentence: the other
half is whether the ROOF separates the pair the outline could not.
"""
import bpy, math, os, sys, json
import numpy as np
from mathutils import Vector

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gameplay_render as G

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "renders")
SCRATCH = os.path.join(OUT, "confusion")

SPAN = 48.0        # metres across the render, same for every unit
RES = 960          # pixels -> 20.0 px/m
NORM = 128         # normalised comparison grid


def find(name, lod=0):
    for root, _dirs, files in os.walk(os.path.join(ROOT, "art", "blockout")):
        f = f"{name}_LOD{lod}.glb"
        if f in files:
            return os.path.join(root, f)
    return None


def import_glb(path):
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=path)
    new = [o for o in bpy.data.objects if o not in before]
    for o in new:
        if o.type == "EMPTY":
            o.hide_render = True
    return new


def top_camera():
    bpy.ops.object.camera_add(location=(0, 0, 200))
    c = bpy.context.object
    c.rotation_euler = (0, 0, 0)          # -Z is straight down
    c.data.type = "ORTHO"
    c.data.ortho_scale = SPAN
    c.data.clip_start, c.data.clip_end = 1.0, 400.0
    bpy.context.scene.camera = c
    return c


def render_to(path, samples, view="Standard"):
    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.eevee.taa_render_samples = samples
    sc.view_settings.view_transform = view
    if view == "AgX":
        sc.view_settings.look = "AgX - Base Contrast"
    sc.render.resolution_x = sc.render.resolution_y = RES
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.render.film_transparent = False
    sc.render.filepath = path
    bpy.ops.render.render(write_still=True)


def read_png(path):
    img = bpy.data.images.load(path, check_existing=False)
    a = np.array(img.pixels[:], dtype=np.float32).reshape(img.size[1], img.size[0], 4)
    bpy.data.images.remove(img)
    return a[::-1]        # Blender is bottom-up; flip so row 0 is +Y (north)


def black_world():
    w = bpy.data.worlds.new("K")
    w.use_nodes = True
    bg = w.node_tree.nodes["Background"]
    bg.inputs[0].default_value = (0, 0, 0, 1)
    bg.inputs[1].default_value = 0.0
    bpy.context.scene.world = w


def white_emission():
    m = bpy.data.materials.new("SIL")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = (1, 1, 1, 1)
    e.inputs[1].default_value = 1.0
    o = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(e.outputs[0], o.inputs[0])
    return m


def capture(name):
    """Render pass A + pass B for one unit; return (mask, luminance)."""
    path = find(name)
    if path is None:
        print("  MISSING", name)
        return None, None

    # ── pass A: silhouette ────────────────────────────────────────────
    bpy.ops.wm.read_factory_settings(use_empty=True)
    black_world()
    objs = import_glb(path)
    mat = white_emission()
    for o in objs:
        if o.type == "MESH":
            o.data.materials.clear()
            o.data.materials.append(mat)
    top_camera()
    pa = os.path.join(SCRATCH, name + "_sil.png")
    render_to(pa, 8, view="Standard")
    rgba = read_png(pa)
    mask = (rgba[..., 0] > 0.5)

    # ── pass B: roof read ─────────────────────────────────────────────
    bpy.ops.wm.read_factory_settings(use_empty=True)
    G.reset()
    G.sun(strength=3.3, elev=42, azim=140)
    objs = import_glb(path)
    G.apply_occlusion([o for o in objs if o.type == "MESH"])
    top_camera()
    pb = os.path.join(SCRATCH, name + "_roof.png")
    render_to(pb, 48, view="AgX")
    rgb = read_png(pb)
    lum = (0.2126 * rgb[..., 0] + 0.7152 * rgb[..., 1] + 0.0722 * rgb[..., 2])
    return mask, lum


# ── exact area-average resampling ─────────────────────────────────────
def _weights(n_in, n_out):
    """W[o, i] = fraction of output cell o covered by input cell i."""
    W = np.zeros((n_out, n_in), dtype=np.float64)
    s = n_in / n_out
    for o in range(n_out):
        a, b = o * s, (o + 1) * s
        i0, i1 = int(math.floor(a)), int(math.ceil(b))
        for i in range(i0, min(i1, n_in)):
            W[o, i] = max(0.0, min(b, i + 1) - max(a, i))
    W /= W.sum(axis=1, keepdims=True)
    return W


_WC = {}


def resample(img, h, w):
    key = (img.shape[0], h)
    if key not in _WC:
        _WC[key] = _weights(img.shape[0], h)
    key2 = (img.shape[1], w)
    if key2 not in _WC:
        _WC[key2] = _weights(img.shape[1], w)
    return _WC[key] @ img.astype(np.float64) @ _WC[key2].T


def bbox(mask):
    ys, xs = np.where(mask)
    return ys.min(), ys.max() + 1, xs.min(), xs.max() + 1


def norm_uniform(mask, lum=None):
    """Crop to bbox, scale UNIFORMLY to fit NORM x NORM, centre."""
    y0, y1, x0, x1 = bbox(mask)
    m = mask[y0:y1, x0:x1].astype(np.float64)
    h, w = m.shape
    f = min(NORM / h, NORM / w)
    th, tw = max(1, int(round(h * f))), max(1, int(round(w * f)))
    r = resample(m, th, tw)
    out = np.zeros((NORM, NORM))
    oy, ox = (NORM - th) // 2, (NORM - tw) // 2
    out[oy:oy + th, ox:ox + tw] = r
    if lum is None:
        return out >= 0.5
    l = lum[y0:y1, x0:x1]
    lr = resample(l, th, tw)
    lo = np.zeros((NORM, NORM))
    lo[oy:oy + th, ox:ox + tw] = lr
    return out >= 0.5, lo


def norm_stretch(mask):
    y0, y1, x0, x1 = bbox(mask)
    return resample(mask[y0:y1, x0:x1].astype(np.float64), NORM, NORM) >= 0.5


def centre_true(mask):
    """Shift a true-scale mask so its centroid sits at the frame centre."""
    ys, xs = np.where(mask)
    cy, cx = ys.mean(), xs.mean()
    out = np.zeros_like(mask)
    dy, dx = int(round(RES / 2 - cy)), int(round(RES / 2 - cx))
    ys2, xs2 = ys + dy, xs + dx
    ok = (ys2 >= 0) & (ys2 < RES) & (xs2 >= 0) & (xs2 < RES)
    out[ys2[ok], xs2[ok]] = True
    return out


def iou(a, b):
    u = np.logical_or(a, b).sum()
    return float(np.logical_and(a, b).sum()) / float(u) if u else 0.0


STRUCTS = [
    "bld_e4_us_hq", "bld_e4_us_power_plant", "bld_e4_us_oil_derrick",
    "bld_e4_us_refinery", "bld_e4_us_supply_depot", "bld_e4_us_barracks",
    "bld_e4_us_light_factory", "bld_e4_us_heavy_factory",
    "bld_e4_us_research_facility", "bld_e4_us_repair_depot",
    "bld_e4_us_airbase", "bld_e4_us_hardened_shelter", "bld_e4_us_helipad",
    "bld_e1_us_naval_yard", "bld_e2_us_coastal_battery",
    "bld_e4_us_fixed_radar", "bld_e4_us_fixed_sam", "bld_e4_us_ew_station",
    "bld_e4_us_bunker",
]
VEHICLES = ["rad_e4_us_search", "aad_e4_us_longsam", "ewj_e4_us_jammer",
            "sam_e4_us_launcher", "cmd_e4_us_command", "eng_e4_us_repair"]


def short(n):
    return n.replace("bld_e4_us_", "").replace("bld_e1_us_", "") \
            .replace("bld_e2_us_", "")


def main():
    os.makedirs(SCRATCH, exist_ok=True)
    names = STRUCTS + VEHICLES
    data = {}
    for n in names:
        print("capturing", n)
        m, l = capture(n)
        if m is None or not m.any():
            print("   EMPTY MASK", n)
            continue
        y0, y1, x0, x1 = bbox(m)
        u, lu = norm_uniform(m, l)
        data[n] = dict(
            mask=m, lum=l,
            plan_x=(x1 - x0) / (RES / SPAN), plan_y=(y1 - y0) / (RES / SPAN),
            area=float(m.sum()) / (RES / SPAN) ** 2,
            u=u, s=norm_stretch(m), t=centre_true(m), lu=lu,
        )

    rows = []
    keys = [n for n in names if n in data]
    for i in range(len(keys)):
        for j in range(i + 1, len(keys)):
            a, b = data[keys[i]], data[keys[j]]
            ua, ub = a["u"], b["u"]
            la = a["lu"][ua]
            lb = b["lu"][ub]
            da = ua & (a["lu"] <= np.median(la))
            db = ub & (b["lu"] <= np.median(lb))
            rows.append(dict(
                a=keys[i], b=keys[j],
                shape=round(iou(ua, ub), 4),
                stretch=round(iou(a["s"], b["s"]), 4),
                true=round(iou(a["t"], b["t"]), 4),
                roof=round(iou(da, db), 4),
            ))

    meta = {n: dict(plan_x=round(data[n]["plan_x"], 2),
                    plan_y=round(data[n]["plan_y"], 2),
                    area_m2=round(data[n]["area"], 1)) for n in keys}
    with open(os.path.join(SCRATCH, "confusion.json"), "w") as f:
        json.dump(dict(meta=meta, pairs=rows), f, indent=1)
    print("wrote", os.path.join(SCRATCH, "confusion.json"))


main()
