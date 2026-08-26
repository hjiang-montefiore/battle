"""Objectively score a model's silhouette against a reference drawing.

    Blender -b --python tools/verify_shape.py -- <model> <reference.png> [top|side]

Spot-checking dimensions is not verification. This renders the model as a pure
silhouette, extracts the subject outline from a canonical reference drawing,
normalises both to the same bounding box, and reports INTERSECTION OVER UNION —
one number for "does this look like the real thing".

It also writes an overlay so the disagreement is visible:
    red   = in the reference but not the model
    blue  = in the model but not the reference
    dark  = agreement

Commons reference drawings are usually a dark silhouette on a light ground,
which thresholds cleanly. A photographic background will not work, and the tool
says so rather than returning a meaningless score.
"""
import bpy, glob, math, os, sys
import numpy as np
from mathutils import Vector

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RES = 512


def render_silhouette(name, view, out_png):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    w = bpy.data.worlds.new("W")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs[0].default_value = (1, 1, 1, 1)
    w.node_tree.nodes["Background"].inputs[1].default_value = 1.0
    bpy.context.scene.world = w

    hits = glob.glob(os.path.join(ROOT, "art", "blockout", "**",
                                  f"{name}_LOD0.glb"), recursive=True)
    if not hits:
        raise SystemExit(f"FAIL: no model named {name}")
    bpy.ops.import_scene.gltf(filepath=hits[0])
    objs = [o for o in bpy.data.objects if o.type == "MESH"]

    mat = bpy.data.materials.new("K")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs[0].default_value = (0, 0, 0, 1)
    nt.links.new(e.outputs[0], nt.nodes.new("ShaderNodeOutputMaterial").inputs[0])

    lo = np.array([1e9, 1e9, 1e9])
    hi = np.array([-1e9, -1e9, -1e9])
    for o in objs:
        o.data.materials.clear()
        o.data.materials.append(mat)
        for c in o.bound_box:
            v = o.matrix_world @ Vector(c)
            lo = np.minimum(lo, [v.x, v.y, v.z])
            hi = np.maximum(hi, [v.x, v.y, v.z])
    ctr = (lo + hi) / 2.0
    size = float(np.max(hi - lo)) * 1.06

    if view == "top":
        loc, rot = (ctr[0], ctr[1], ctr[2] + 300.0), (0.0, 0.0, 0.0)
    else:
        loc = (ctr[0] - 300.0, ctr[1], ctr[2])
        rot = (math.radians(90), 0.0, math.radians(-90))
    bpy.ops.object.camera_add(location=loc, rotation=rot)
    cam = bpy.context.object
    cam.data.type = "ORTHO"
    cam.data.ortho_scale = size
    bpy.context.scene.camera = cam

    sc = bpy.context.scene
    sc.render.engine = "BLENDER_EEVEE_NEXT"
    sc.render.film_transparent = False
    sc.view_settings.view_transform = "Standard"
    sc.render.resolution_x = RES
    sc.render.resolution_y = RES
    sc.render.image_settings.file_format = "PNG"
    sc.render.filepath = out_png
    bpy.ops.render.render(write_still=True)


def largest_blob(m):
    """Keep only the biggest connected component.

    Reference sheets routinely carry two aircraft plus captions; masking every
    dark pixel measures the caption text too and the score is meaningless.
    Iterative label propagation — no scipy in Blender's Python.
    """
    h, w = m.shape
    lab = np.zeros((h, w), dtype=np.int32)
    lab[m] = np.arange(1, int(m.sum()) + 1)
    for _ in range(400):
        prev = lab
        cur = lab.copy()
        cur[1:, :] = np.maximum(cur[1:, :], lab[:-1, :])
        cur[:-1, :] = np.maximum(cur[:-1, :], lab[1:, :])
        cur[:, 1:] = np.maximum(cur[:, 1:], lab[:, :-1])
        cur[:, :-1] = np.maximum(cur[:, :-1], lab[:, 1:])
        cur[~m] = 0
        if np.array_equal(cur, prev):
            break
        lab = cur
    ids, counts = np.unique(lab[lab > 0], return_counts=True)
    if len(ids) == 0:
        return m
    return lab == ids[int(np.argmax(counts))]


def grow(seed, allowed, iters=900):
    """Propagate seed through `allowed`. No scipy in Blender's Python."""
    cur = seed & allowed
    for _ in range(iters):
        nxt = cur.copy()
        nxt[1:, :] |= cur[:-1, :]
        nxt[:-1, :] |= cur[1:, :]
        nxt[:, 1:] |= cur[:, :-1]
        nxt[:, :-1] |= cur[:, 1:]
        nxt &= allowed
        if np.array_equal(nxt, cur):
            break
        cur = nxt
    return cur


def dilate(m, n=1):
    for _ in range(n):
        o = m.copy()
        o[1:, :] |= m[:-1, :]; o[:-1, :] |= m[1:, :]
        o[:, 1:] |= m[:, :-1]; o[:, :-1] |= m[:, 1:]
        m = o
    return m


def assess_reference(path, thresh=0.45):
    """Is this image actually usable for shape verification?

    A photograph of a vehicle 200 m away under camouflage netting will threshold
    into noise and produce a confident, meaningless score. Refuse those.
    """
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    r, g, b = px[..., 0], px[..., 1], px[..., 2]
    lum = r * 0.299 + g * 0.587 + b * 0.114
    sat = np.max(px[..., :3], axis=2) - np.min(px[..., :3], axis=2)
    dark = lum < thresh
    notes = []
    ink = dark.mean()
    colour = (sat > 0.12).mean()
    # a mid-grey mass with no strong black/white separation reads as a photo
    bimodal = ((lum < 0.25).mean() + (lum > 0.80).mean())
    kind = "line-drawing"
    if colour > 0.25:
        kind = "photo"; notes.append(f"{colour:.0%} of pixels are colourful")
    if bimodal < 0.55:
        kind = "photo"; notes.append(f"only {bimodal:.0%} of pixels are near-black or near-white")
    if ink < 0.005:
        notes.append("almost no ink — drawing may be too faint")
    if w < 700:
        notes.append(f"low resolution ({w}px)")
    return kind, ink, notes


def fill_outlines(dark):
    """Line art has no filled region. Close the outlines, flood from the
    border, and treat everything unreached as interior."""
    closed = dilate(dark, 2)
    outside_allowed = ~closed
    seed = np.zeros_like(dark)
    seed[0, :] = seed[-1, :] = True
    seed[:, 0] = seed[:, -1] = True
    outside = grow(seed, outside_allowed)
    return (~outside) | dark


def all_blobs(m, min_frac=0.012):
    h, w = m.shape
    lab = np.zeros((h, w), dtype=np.int32)
    lab[m] = np.arange(1, int(m.sum()) + 1)
    for _ in range(400):
        prev = lab
        cur = lab.copy()
        cur[1:, :] = np.maximum(cur[1:, :], lab[:-1, :])
        cur[:-1, :] = np.maximum(cur[:-1, :], lab[1:, :])
        cur[:, 1:] = np.maximum(cur[:, 1:], lab[:, :-1])
        cur[:, :-1] = np.maximum(cur[:, :-1], lab[:, 1:])
        cur[~m] = 0
        if np.array_equal(cur, prev):
            break
        lab = cur
    out = []
    ids, counts = np.unique(lab[lab > 0], return_counts=True)
    for i, c in zip(ids, counts):
        if c < min_frac * m.size:
            continue
        b = lab == i
        ys, xs = np.where(b)
        out.append(b[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
    return out


def pick_view(path, want_aspect, thresh=0.45):
    """From a 3-view sheet, return the sub-view closest to want_aspect."""
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    lum = px[..., 0] * 0.299 + px[..., 1] * 0.587 + px[..., 2] * 0.114
    m = lum < thresh
    if m.sum() < 50:
        return None, []
    if m.mean() < 0.28:          # sparse ink -> outline art, so fill it
        m = fill_outlines(m)
    blobs = all_blobs(m)
    if not blobs:
        return None, []
    # A vehicle outline is concave — wings meet a fuselage, a hull meets a
    # turret. A blob that fills most of its own bounding box is a filled
    # rectangle or a leaked enclosure, not a subject.
    keep = [b for b in blobs if b.sum() / float(b.size) < 0.72]
    return (keep or blobs), []


def mask_of(path, thresh=0.45, isolate=True):
    img = bpy.data.images.load(path, check_existing=False)
    w, h = img.size
    px = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    lum = px[..., 0] * 0.299 + px[..., 1] * 0.587 + px[..., 2] * 0.114
    m = lum < thresh
    if m.sum() < 50:
        return None, 0.0
    if isolate:
        m = largest_blob(m)
    ys, xs = np.where(m)
    return m[ys.min():ys.max() + 1, xs.min():xs.max() + 1], m.sum() / float(m.size)


def resample(m, n=RES):
    h, w = m.shape
    yi = np.clip(np.arange(n) * h // n, 0, h - 1)
    xi = np.clip(np.arange(n) * w // n, 0, w - 1)
    return m[yi][:, xi]


a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(a) < 2:
    raise SystemExit("usage: -- <model> <reference.png> [top|side]")
name, ref, view = a[0], a[1], (a[2] if len(a) > 2 else "side")
ref = ref if os.path.isabs(ref) else os.path.join(ROOT, "art", "reference", ref)

outdir = os.path.join(ROOT, "art", "verify")
os.makedirs(outdir, exist_ok=True)
mine_png = os.path.join(outdir, f"{name}_{view}.png")
render_silhouette(name, view, mine_png)

kind, ink, notes = assess_reference(ref)
print(f"      reference: {kind}, {ink:.1%} ink" +
      ("  [" + "; ".join(notes) + "]" if notes else ""))
if kind == "photo":
    raise SystemExit("FAIL: reference is a photograph, not a line drawing or "
                     "silhouette. Shape scoring needs clean orthographic art — "
                     "search Commons for '<type> 3-view line drawing'.")

A0, _ = mask_of(mine_png)
if A0 is None:
    raise SystemExit("FAIL: model silhouette is empty")
want = A0.shape[1] / A0.shape[0]
cands = pick_view(ref, want)[0]
if not cands:
    raise SystemExit("FAIL: no usable sub-view in the reference")


def score(Bm):
    Ax = resample(A0)[::-1]
    Bx = resample(Bm)
    i = int(np.logical_and(Ax, Bx).sum())
    u = int(np.logical_or(Ax, Bx).sum())
    return i / max(u, 1), Ax, Bx


best = max((score(b) + (b,) for b in cands), key=lambda s: s[0])
iou_best, A, B, B0 = best[0], best[1], best[2], best[3]
print(f"      reference: {len(cands)} candidate view(s); model aspect "
      f"{want:.2f}, best match aspect {B0.shape[1] / B0.shape[0]:.2f}")

union = int(np.logical_or(A, B).sum())
iou = iou_best

rgb = np.ones((RES, RES, 3), dtype=np.float32)
rgb[B & ~A] = (0.85, 0.15, 0.15)
rgb[A & ~B] = (0.15, 0.30, 0.85)
rgb[A & B] = (0.20, 0.20, 0.22)
out = bpy.data.images.new("cmp", RES, RES, alpha=False)
out.pixels = np.dstack([rgb[::-1],
                        np.ones((RES, RES, 1), dtype=np.float32)]).ravel()
cmp_png = os.path.join(outdir, f"{name}_{view}_overlay.png")
out.filepath_raw = cmp_png
out.file_format = "PNG"
out.save()

verdict = "GOOD" if iou >= 0.80 else "FAIR" if iou >= 0.65 else "POOR"
print(f"SHAPE {name} [{view}]  IoU={iou:.3f}  {verdict}")
print(f"      missing {(B & ~A).sum()/max(union,1):.1%}   "
      f"excess {(A & ~B).sum()/max(union,1):.1%}")
print(f"      overlay -> {os.path.relpath(cmp_png, ROOT)}")
