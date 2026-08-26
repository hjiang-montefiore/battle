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

THE TARGET IS DECLARED, NOT DISCOVERED. Each sheet needs a sidecar
<reference>.json naming the region for each view and the rot/mirror that brings
it into the orientation render_silhouette() produces; see the convention block
further down. Without one the tool refuses to score rather than picking a
region for itself. These outcomes are distinct and are not
interchangeable:

    CANNOT SCORE  no sidecar, view not declared, region unusable, two
                  declarations of the same view contradict each other, or the
                  reference is a photograph — no comparison happened at all,
                  and the tool exits 2 without printing an IoU
    NO MATCH      compared, and the shapes are unrelated (IoU < 0.25)
    VERDICT WITHHELD  compared, IoU printed, but no null has been measured for
                  this sheet and view, so there is nothing to say whether a
                  wrong model would score as well
    INDISTINCT    compared, and the score does not beat the best WRONG model
                  measured on this exact region — a real number, and not
                  evidence that the model is right
    IoU + GOOD / FAIR / POOR    compared, beat the null, and here is how close

THE VERDICT IS EARNED AGAINST A MEASURED NULL. On a flat scale an F-15 model
scored IoU 0.807 GOOD against the B-52 side view while the B-52 itself scored
0.451 POOR: an aspect-normalised elevation of any fixed-wing aircraft is a long
tube with one fin. Each sheet/view therefore carries a <sheet>.null.json
measured by this tool (-- --null ...) recording the best score reached by a
model that is NOT the subject; a score at or below that is reported INDISTINCT.
"""
import bpy, glob, json, math, os, sys
import numpy as np
from collections import deque
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


def _load_rgba(path):
    """Read an image as (h, w, 4) float32, RGB composited over WHITE.

    Every call site used to threshold luminance alone. That is wrong for the
    PNGs we actually hold: a greyscale+alpha sheet can carry a grey channel
    that is 0 everywhere and keep the whole drawing in alpha, which reads as a
    solid black rectangle and turns every score into arithmetic on that
    rectangle. Compositing over white is what a viewer sees, so that is what we
    measure. The datablock is freed here — these sheets are ~4 Mpx and used to
    be decoded once per call site and never released.

    THE BUFFER IS FORCED INTO ONE DECLARED SPACE. Blender does not hand back
    every image the same way: an 8-bit file arrives as byte/255, i.e. still
    display-encoded, but a 16-bit or float file is colour-managed on the way in
    and arrives SCENE-LINEAR. The same nominal grey then reads 0.502 from an
    8-bit PNG and 0.216 from a 16-bit one — opposite sides of the 0.45 ink
    threshold. A byte-identical picture saved at both depths was measured as
    kind='photo', ink=0.270 (refused) at 8 bits and kind='line-drawing',
    ink=1.0000 (scored, as a solid rectangle) at 16 bits: the exact
    solid-rectangle pathology this loader exists to kill, reached through bit
    depth instead of alpha. Setting the colourspace to Non-Color before the
    read suppresses the transform, so the buffer holds the file's own values
    whatever its depth. Measured: 16-bit 0.216 -> 0.502, matching the 8-bit
    read exactly, and zero pixels changed on any 8-bit sheet in the repository.
    """
    if not os.path.exists(path):
        raise SystemExit(f"FAIL: no such image: {path}")
    img = bpy.data.images.load(path, check_existing=False)
    try:
        try:
            img.colorspace_settings.name = "Non-Color"
        except Exception as exc:                       # pragma: no cover
            raise SystemExit(
                f"FAIL: cannot pin the colourspace of {path} ({exc}); the "
                f"buffer's encoding would be undeclared and the ink threshold "
                f"meaningless")
        w, h = img.size
        if w == 0 or h == 0:
            raise SystemExit(f"FAIL: unreadable image: {path}")
        buf = np.empty(w * h * 4, dtype=np.float32)
        img.pixels.foreach_get(buf)
    finally:
        bpy.data.images.remove(img)
    px = buf.reshape(h, w, 4)
    a = px[..., 3:4]
    out = np.empty_like(px)
    out[..., :3] = px[..., :3] * a + (1.0 - a)   # over white
    out[..., 3] = 1.0
    return out


def _luma(px):
    return px[..., 0] * 0.299 + px[..., 1] * 0.587 + px[..., 2] * 0.114


def _label(m):
    """True 4-connected components by explicit BFS. Returns (labels, sizes).

    Replaces a capped label-propagation loop that stopped after a fixed number
    of iterations and returned whatever partial labelling it had reached, so a
    single component came back split into hundreds of fragments and the caller
    silently kept only one fragment. There is no iteration budget here: the
    queue empties exactly when the component is complete.

    FOUR-CONNECTED, DELIBERATELY, and paired with a 4-connected background
    flood in _fill_raw(). The Jordan-consistent pairing is 4/8, so labelling
    the object 4-connected can in principle split a subject whose lobes meet
    only at a corner — over 200 random sparse-ink trials the 4- and 8-connected
    component counts of a fill_outlines() output differed in 193. It does not
    happen on real art here: on all 16 declared regions the two agree exactly,
    both in component count (1) and in largest-component size. It is kept
    4-connected so that a diagonal hairline cannot bridge two views of the
    sheet into one subject, and this comment exists so the choice is a decision
    rather than an accident.
    """
    h, w = m.shape
    flat = np.ascontiguousarray(m).ravel()
    lab = np.zeros(flat.size, dtype=np.int32)
    sizes = []
    nxt = 0
    for start in np.flatnonzero(flat):
        start = int(start)
        if lab[start]:
            continue
        nxt += 1
        lab[start] = nxt
        n = 0
        q = deque((start,))
        push = q.append
        pop = q.popleft
        while q:
            p = pop()
            n += 1
            y, x = divmod(p, w)
            if y > 0:
                t = p - w
                if flat[t] and not lab[t]:
                    lab[t] = nxt; push(t)
            if y < h - 1:
                t = p + w
                if flat[t] and not lab[t]:
                    lab[t] = nxt; push(t)
            if x > 0:
                t = p - 1
                if flat[t] and not lab[t]:
                    lab[t] = nxt; push(t)
            if x < w - 1:
                t = p + 1
                if flat[t] and not lab[t]:
                    lab[t] = nxt; push(t)
        sizes.append(n)
    return lab.reshape(h, w), sizes


def largest_blob(m):
    """Keep only the biggest connected component.

    Reference sheets routinely carry two aircraft plus captions; masking every
    dark pixel measures the caption text too and the score is meaningless.
    """
    lab, sizes = _label(m)
    if not sizes:
        return m
    return lab == (int(np.argmax(sizes)) + 1)


def grow(seed, allowed):
    """Flood `seed` through `allowed` by BFS, to completion.

    This used to be a dilate-to-fixpoint capped at 900 iterations, which on a
    ~2000 px sheet exits early and hands back a half-grown region as though it
    had converged. The tell is perfect 45-degree edges — the L1 iso-contour of
    a truncated dilation. A queue has no such cap: it terminates when the
    reachable set is exhausted, and never before.
    """
    h, w = allowed.shape
    aflat = np.ascontiguousarray(allowed).ravel()
    out = np.zeros(aflat.size, dtype=bool)
    starts = np.flatnonzero(np.ascontiguousarray(seed).ravel() & aflat)
    out[starts] = True
    q = deque(int(i) for i in starts)
    push = q.append
    pop = q.popleft
    while q:
        p = pop()
        y, x = divmod(p, w)
        if y > 0:
            t = p - w
            if aflat[t] and not out[t]:
                out[t] = True; push(t)
        if y < h - 1:
            t = p + w
            if aflat[t] and not out[t]:
                out[t] = True; push(t)
        if x > 0:
            t = p - 1
            if aflat[t] and not out[t]:
                out[t] = True; push(t)
        if x < w - 1:
            t = p + 1
            if aflat[t] and not out[t]:
                out[t] = True; push(t)
    return out.reshape(h, w)


def dilate(m, n=1):
    for _ in range(n):
        o = m.copy()
        o[1:, :] |= m[:-1, :]; o[:-1, :] |= m[1:, :]
        o[:, 1:] |= m[:, :-1]; o[:, :-1] |= m[:, 1:]
        m = o
    return m


def erode(m, n=1):
    return ~dilate(~m, n)


def assess_reference(path, thresh=0.45):
    """Is this image actually usable for shape verification?

    A photograph of a vehicle 200 m away under camouflage netting will threshold
    into noise and produce a confident, meaningless score. Refuse those.
    """
    px = _load_rgba(path)
    h, w = px.shape[0], px.shape[1]
    lum = _luma(px)
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
    if ink > 0.55:
        # There was a lower bound here and no upper one, so a read that turned
        # the whole sheet into one black block (ink=1.0000) drew not even a
        # warning. High ink is not by itself fatal — art/reference/3v_m577.png
        # is one legitimate solid silhouette at ink=0.7308 — so this is a note,
        # and the hard refusal lives in region_mask() where a solid block can
        # actually be told apart from a fat subject.
        notes.append(f"ink is {ink:.0%} of the sheet — check the polarity, and "
                     f"that the whole sheet is not reading as one block")
    if w < 700:
        notes.append(f"low resolution ({w}px)")
    return kind, ink, notes


CLOSE = 2          # outline-closing radius used on the scoring path


def _fill_raw(dark, close):
    """The filled region BEFORE the closing radius is eroded back off."""
    closed = dilate(dark, close)
    seed = np.zeros_like(dark)
    seed[0, :] = seed[-1, :] = True
    seed[:, 0] = seed[:, -1] = True
    return (~grow(seed, ~closed)) | dark


def fill_outlines(dark, close=CLOSE):
    """Line art has no filled region. Close the outlines, flood from the
    border, and treat everything unreached as interior.

    THE CLOSING IS UNDONE AFTERWARDS. The flood can only stop `close` px short
    of the ink, so the raw result is the subject fattened by exactly `close` px
    all the way round — but the model render is not fattened, and the two are
    compared on a fixed 512 px budget. Two px of reference fat costs almost
    nothing when the drawn subject is 1400 px long and a great deal when it is
    325 px long, so the attainable ceiling moved with the sheet: a
    geometrically PERFECT model scored 0.958 against 3v_b52.png[side] and only
    0.811 against 3v_apache.png[side] — below the flat 0.80 GOOD line by 0.011,
    i.e. no model could ever honestly earn GOOD on that sheet. Eroding the same
    radius back off restores the subject as drawn and makes the ceiling
    sheet-independent. Nothing is lost by it: the result contains
    erode(dilate(dark, close), close), which is the morphological closing of
    the ink and therefore a superset of the ink.
    """
    return erode(_fill_raw(dark, close), close) | dark


def all_blobs(m, min_frac=0.012):
    lab, sizes = _label(m)
    out = []
    for i, c in enumerate(sizes, start=1):
        if c < min_frac * m.size:
            continue
        b = lab == i
        ys, xs = np.where(b)
        out.append(b[ys.min():ys.max() + 1, xs.min():xs.max() + 1])
    return out


def pick_view(path, want_aspect, thresh=0.45):
    """Enumerate the plausible sub-views on a sheet. AUTHORING AID ONLY.

    This is no longer on the scoring path. It used to be: the scorer took these
    candidates and kept whichever one scored highest, which made the target a
    function of the model under test. Scoring now reads a declared region from
    the sheet's sidecar. What this is still good for is writing that sidecar in
    the first place — run it to see what is on a new sheet, then record the
    rect and orientation you actually want. `want_aspect` is unused and kept so
    existing callers keep working.
    """
    m = _luma(_load_rgba(path)) < thresh
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
    m = _luma(_load_rgba(path)) < thresh
    if m.sum() < 50:
        return None, 0.0
    if isolate:
        m = largest_blob(m)
    ys, xs = np.where(m)
    return m[ys.min():ys.max() + 1, xs.min():xs.max() + 1], m.sum() / float(m.size)


def resample(m, n=RES):
    """Fit `m` into an n x n canvas PRESERVING ASPECT RATIO (letterboxed).

    Stretching each mask independently to a square was throwing away the very
    thing a shape check exists to catch: a model whose length-to-width ratio is
    wrong got rescaled until it matched the reference before the two were ever
    compared. The longer side is mapped to n, the shorter is scaled by the same
    factor, and the result is centred on an empty canvas.
    """
    h, w = m.shape
    if h >= w:
        nh = n
        nw = max(1, int(round(w * n / float(h))))
    else:
        nw = n
        nh = max(1, int(round(h * n / float(w))))
    yi = np.clip(np.arange(nh) * h // nh, 0, h - 1)
    xi = np.clip(np.arange(nw) * w // nw, 0, w - 1)
    small = m[yi][:, xi]
    out = np.zeros((n, n), dtype=bool)
    y0 = (n - nh) // 2
    x0 = (n - nw) // 2
    out[y0:y0 + nh, x0:x0 + nw] = small
    return out


# ---------------------------------------------------------------------------
# Declared scoring target.
#
# The scorer used to build every plausible blob on the sheet and then keep
# whichever one scored highest:
#
#     best = max((score(b) + (b,) for b in cands), key=lambda s: s[0])
#
# That makes the optimisation target a function of the model being scored. Two
# consecutive runs on two different models could be measured against two
# different pictures, so the numbers were not comparable across iterations, a
# model could improve its score by drifting towards some *other* view on the
# sheet, and the tool could never say "this does not match" — there was always
# a best blob. It is replaced by a per-sheet sidecar that names the region.
#
# CONVENTION (canonical, and the only one accepted):
#   <sheet>.json holds one entry per declared view, keyed "top"/"side"/"front".
#   Keys beginning with "_" are documentation and are ignored.
#
#     "rect":   [x, y, w, h] in TOP-DOWN pixels — y counted DOWN from the top
#               row, the way a human reads coordinates off an image viewer.
#               _load_rgba returns row-0-at-bottom, so the rows to take are
#               [H-(y+h) : H-y], and the crop is then reversed back to
#               top-down order before the transform below is applied.
#     "rot":    degrees counter-clockwise AS THE PICTURE IS SEEN, applied to
#               that top-down-ordered crop as np.rot90(crop, rot // 90).
#     "mirror": horizontal (left-right) flip, applied AFTER the rotation.
#
#   The declared pair maps the drawn view into the orientation that
#   render_silhouette() produces, and leaves the result in the same row order
#   as the render's own mask (row 0 = bottom), so the two are directly
#   comparable with no further flipping.
#
#   A sheet may state "_rect_origin". If present it must be "top-left"; any
#   other value is refused rather than silently reinterpreted. One sidecar in
#   this repository was authored against a bottom-up frame and was migrated to
#   the canonical frame by exact array comparison, not by eye.
#
# The transforms are DECLARED, never searched. Trying all eight dihedral
# transforms at score time would reintroduce exactly the self-selecting target
# removed above, and worse: it would let a model built mirror-imaged score as
# a perfect match.
# ---------------------------------------------------------------------------

VIEWS_RENDERABLE = ("top", "side")


def sidecar_path(ref_path):
    return os.path.splitext(ref_path)[0] + ".json"


def load_regions(ref_path):
    """Declared regions for a sheet, or None when the sheet has no sidecar.

    None is a distinct answer from "the sidecar has no such view" and from
    "the view scored badly"; the caller keeps the three apart.
    """
    sc = sidecar_path(ref_path)
    if not os.path.exists(sc):
        return None
    with open(sc, "r") as f:
        d = json.load(f)
    origin = d.get("_rect_origin", "top-left")
    if origin != "top-left":
        raise SystemExit(
            f"FAIL: {os.path.relpath(sc, ROOT)} declares _rect_origin="
            f"{origin!r}; this tool only reads top-left rects. Migrate the "
            f"sidecar rather than guessing.")
    return {k: v for k, v in d.items() if not str(k).startswith("_")}


def keep_significant(m, min_frac=0.02):
    """Drop specks, keep every substantial component.

    largest_blob() is the wrong tool inside a declared rect. The rect already
    excludes the captions and the neighbouring views that largest_blob existed
    to suppress, so isolating one component here would delete real structure —
    the A-10's nacelles read as two separate islands in plan view. Anything at
    least `min_frac` of the biggest component is kept; dimension ticks and
    stray leader-line pixels fall below that.
    """
    lab, sizes = _label(m)
    if not sizes:
        return m
    big = max(sizes)
    keep = np.zeros(m.shape, dtype=bool)
    for i, c in enumerate(sizes, start=1):
        if c >= min_frac * big:
            keep |= (lab == i)
    return keep


SEAL_PROBE = (8, 24)      # extra closing radii used to test the outline seal
SEAL_RATIO = 0.5          # recovered interior / delivered area that means "leak"
SOLID_FILL = 0.90         # a region this full of its own bbox is a block, not art


def check_outline_seal(crop, pad):
    """Did the border flood get INSIDE the subject?

    fill_outlines() closes gaps of up to 2*CLOSE px. A wider break in an
    outline lets the flood in and region_mask hands back a HOLLOW RING with no
    complaint: measured on a rectangle outline whose true interior is 104,901
    px, a 5 px break dropped the delivered mask from 108,888 px to 6,961 px,
    and end to end the tool then printed a confident "IoU=0.011 NO MATCH" about
    a reference whose subject had 90% of its area deleted. The only sanity gate
    on the path was `m.sum() < 50`, which 6,961 px sails through.

    The test: re-fill with a much larger closing radius and ask whether that
    recovers a THICK region the operative fill missed. Boundary growth from the
    larger radius is a shell of known width, so eroding by that width leaves
    nothing; a recovered interior is hundreds of px thick and survives. Measured
    over the 16 declared regions in art/reference the worst honest value is
    0.144 (3v_apache.png[side], whose rotor blades bridge at radius 24); breaks
    of 5-44 px in a synthetic outline give 11.8-14.2. The 0.5 threshold sits
    between them with 3.5x and 24x of margin. Breaks wider than ~2*max(probe)
    are NOT caught, and this says so rather than pretending otherwise.
    """
    f2 = _fill_raw(_pad(crop, pad), CLOSE)[pad:-pad, pad:-pad]
    base = max(int(f2.sum()), 1)
    for k in SEAL_PROBE:
        q = k + 4
        fk = _fill_raw(_pad(crop, q), k)[q:-q, q:-q]
        d = fk & ~f2
        if not d.any():
            continue
        deep = int(erode(d, k - 2).sum())
        if deep > SEAL_RATIO * base:
            return (f"outline is not sealed: closing at radius {k} recovers "
                    f"{deep} px of interior that the radius-{CLOSE} fill left "
                    f"outside, against {base} px delivered — the region would "
                    f"be scored as a hollow ring")
    return None


def _pad(m, pad):
    o = np.zeros((m.shape[0] + 2 * pad, m.shape[1] + 2 * pad), dtype=bool)
    o[pad:pad + m.shape[0], pad:pad + m.shape[1]] = m
    return o


def clipped_edges(dark_topdown, rect, tol=5):
    """Edges of the rect that a connected run of ink crosses.

    The bbox is the ONLY normalisation frame, so a rect that cuts through the
    subject silently rescales everything inside it. Measured on this
    repository: 3v_f16.json[side] leaves 13 px of ink on the row immediately
    below its rect and [front] 6 px on the column immediately left of its own,
    while every other declared rect has clean background on all four sides.
    """
    x, y, w, h = rect
    H, W = dark_topdown.shape
    hits = []
    if y > 0 and int(dark_topdown[y - 1, x:x + w].sum()) > tol:
        hits.append(("top", int(dark_topdown[y - 1, x:x + w].sum())))
    if y + h < H and int(dark_topdown[y + h, x:x + w].sum()) > tol:
        hits.append(("bottom", int(dark_topdown[y + h, x:x + w].sum())))
    if x > 0 and int(dark_topdown[y:y + h, x - 1].sum()) > tol:
        hits.append(("left", int(dark_topdown[y:y + h, x - 1].sum())))
    if x + w < W and int(dark_topdown[y:y + h, x + w].sum()) > tol:
        hits.append(("right", int(dark_topdown[y:y + h, x + w].sum())))
    return hits


_REGION_CACHE = {}


def region_mask(ref_path, view, thresh=0.45, pad=6):
    """The NAMED view from a sheet, in the render's orientation.

    Returns (mask, info). `mask` is tight-cropped to its own ink. Memoised:
    the scoring path asks for the same region twice (once to refuse early,
    once to score) and the seal check is not free.
    """
    key = (os.path.abspath(ref_path), view, thresh, pad)
    if key in _REGION_CACHE:
        return _REGION_CACHE[key]
    out = _region_mask(ref_path, view, thresh, pad)
    _REGION_CACHE[key] = out
    return out


def _region_mask(ref_path, view, thresh=0.45, pad=6):
    regions = load_regions(ref_path)
    if regions is None:
        return None, "no region sidecar (%s)" % os.path.basename(
            sidecar_path(ref_path))
    if view not in regions:
        return None, "sidecar declares %s — no '%s'" % (
            sorted(regions) or ["nothing"], view)

    r = regions[view]
    try:
        x, y, w, h = [int(v) for v in r["rect"]]
        rot = int(r.get("rot", 0)) % 360
        mirror = bool(r.get("mirror", False))
    except Exception as exc:
        return None, f"malformed '{view}' entry: {exc}"
    if rot % 90:
        return None, f"'{view}' declares rot={rot}, not a multiple of 90"

    px = _load_rgba(ref_path)
    H, W = px.shape[0], px.shape[1]
    if x < 0 or y < 0 or x + w > W or y + h > H or w <= 0 or h <= 0:
        return None, (f"'{view}' rect {[x, y, w, h]} does not fit the "
                      f"{W}x{H} sheet")

    dark = _luma(px) < thresh
    crop = dark[H - (y + h):H - y, x:x + w][::-1]      # -> top-down order

    warn = []
    clipped = clipped_edges(dark[::-1], (x, y, w, h))
    if clipped:
        warn.append("rect clips ink at the " + ", ".join(
            f"{e} edge ({n} px)" for e, n in clipped))

    # Fill the outlines while the crop still has clean background around it.
    # The rects are tight, so a subject touching the rect edge would let the
    # border flood leak straight into the interior and hollow the subject out.
    # Pad with guaranteed background first, fill, then discard the padding.
    if crop.mean() < 0.28:
        bad = check_outline_seal(crop, pad)
        if bad:
            return None, f"'{view}' {bad}"
        crop = fill_outlines(_pad(crop, pad))[pad:pad + crop.shape[0],
                                              pad:pad + crop.shape[1]]

    crop = keep_significant(crop)

    # rot/mirror are stated the way a human reads the sheet, so they are applied
    # in top-down ("as seen") order; the result is then returned to the row
    # order the render's own mask uses. Skipping that last step is not a no-op:
    # it hands back a vertically mirrored view, which reads as plausible for a
    # roughly symmetric plan view and is glaring for an elevation — a B-52 with
    # its fin below the fuselage, scoring IoU 0.093 against a correct model.
    m = np.rot90(crop, rot // 90)
    if mirror:
        m = m[:, ::-1]
    m = np.ascontiguousarray(m[::-1])
    if m.sum() < 50:
        return None, f"'{view}' region is effectively empty ({int(m.sum())} px)"
    ys, xs = np.where(m)
    tight = m[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    # A region that fills essentially all of its own bounding box is a solid
    # block, not a vehicle: every declared region in this repository sits
    # between 0.109 and 0.525, and a whole-sheet misread sits at 1.000. This is
    # the backstop for any future path that turns the reference into a
    # rectangle — the one bit-depth misread that reached it produced exactly
    # that, scored 0.434 against a pixel-perfect model, and printed POOR.
    fill = tight.mean()
    if fill > SOLID_FILL:
        return None, (f"'{view}' region is a solid block ({fill:.1%} of its "
                      f"own bounding box) — nothing was segmented")
    info = f"rect={[x, y, w, h]} rot={rot} mirror={mirror}"
    if warn:
        info += "  [" + "; ".join(warn) + "]"
    return tight, info



# ---------------------------------------------------------------------------
# Cross-checking one declaration against another.
#
# The transforms are declared, never searched — but nothing used to check the
# declarations against each other, so a mirrored reference simply moved the
# defect out of the scorer and into the sidecar, where it is invisible. It is
# live in this repository: art/reference/3v_apache.json[top] (rot 0, mirror
# True) and art/reference/3v_apache_top.json[top] (rot 180, mirror False)
# extract to masks that are EXACT left-right mirrors of one another — ref-vs-ref
# IoU 0.822 as declared, 1.000 under a mirror — and the tool scored the same
# model 0.711 against one and 0.713 against the other without a murmur. One of
# them is a reversed plan view and this cannot tell which, so it refuses.
# ---------------------------------------------------------------------------

VIEW_SUFFIXES = ("_top", "_side", "_front")
MIRROR_MARGIN = 0.10      # how much better a mirror must fit to be a finding


def subject_stem(ref_path):
    stem = os.path.splitext(os.path.basename(ref_path))[0]
    for suf in VIEW_SUFFIXES:
        if stem.endswith(suf):
            return stem[:-len(suf)]
    return stem


def sibling_sheets(ref_path):
    """Other sheets in the same folder drawing the same subject."""
    me = os.path.abspath(ref_path)
    stem = subject_stem(ref_path)
    out = []
    for cand in sorted(glob.glob(os.path.join(os.path.dirname(me), "*.png"))):
        if os.path.abspath(cand) == me:
            continue
        if subject_stem(cand) == stem and os.path.exists(sidecar_path(cand)):
            out.append(cand)
    return out


def _iou(a, b):
    A, B = resample(a), resample(b)
    return float(np.logical_and(A, B).sum()) / max(int(np.logical_or(A, B).sum()), 1)


def handedness_conflict(ref_path, view):
    """A sibling sheet whose declared view only agrees after a mirror."""
    mine, _ = region_mask(ref_path, view)
    if mine is None:
        return None
    for other in sibling_sheets(ref_path):
        try:
            theirs, _ = region_mask(other, view)
        except SystemExit:
            continue
        if theirs is None:
            continue
        same = _iou(mine, theirs)
        flip = _iou(mine, theirs[:, ::-1])
        if flip > same + MIRROR_MARGIN:
            return (f"{os.path.basename(sidecar_path(ref_path))}[{view}] and "
                    f"{os.path.basename(sidecar_path(other))}[{view}] draw the "
                    f"same subject but agree only after a left-right mirror "
                    f"(as declared {same:.3f}, mirrored {flip:.3f}) — one of "
                    f"the two declarations is reversed and this cannot tell "
                    f"which")
    return None


# ---------------------------------------------------------------------------
# Calibration: what does a WRONG model score here?
#
# A fixed target made the number reproducible; it did not make the verdict
# mean anything. Measured on the declared side views, an F-15 model
# (air_e4_us_superiority) scores IoU 0.807 against 3v_b52.png[side] — GOOD on
# the old flat scale — while the B-52 model itself scores 0.436. An
# aspect-normalised elevation of any fixed-wing aircraft is "long tube, one
# fin", and IoU cannot separate them. The thresholds were never calibrated
# against that, so GOOD was an assertion the measurement could not support.
#
# So the verdict is now earned against a MEASURED null: the best score any
# model that is NOT the subject achieves on this exact declared region.
# Below the null the tool says INDISTINCT — it compared, and the result does
# not distinguish this model from a wrong one. With no null on file it prints
# the IoU and withholds the label rather than inventing one.
#
#   Blender -b --python tools/verify_shape.py -- --null <sheet.png> <view> \
#           <subject-model> [family-prefix ...]
#
# writes <sheet>.null.json next to the sidecar. Declarations and measurements
# are kept in separate files on purpose: the sidecar is authored by hand, the
# null is produced by this tool and can be regenerated.
# ---------------------------------------------------------------------------


def null_path(ref_path):
    return os.path.splitext(ref_path)[0] + ".null.json"


def load_null(ref_path, view):
    p = null_path(ref_path)
    if not os.path.exists(p):
        return None
    with open(p, "r") as f:
        d = json.load(f)
    n = d.get(view)
    if not n or "max" not in n:
        return None
    return n


def model_names(prefixes):
    out = set()
    for g_ in glob.glob(os.path.join(ROOT, "art", "blockout", "**",
                                     "*_LOD0.glb"), recursive=True):
        nm = os.path.basename(g_)[:-len("_LOD0.glb")]
        if any(nm.startswith(pre) for pre in prefixes):
            out.add(nm)
    return sorted(out)


def silhouette_of(model, view, outdir):
    png = os.path.join(outdir, f"{model}_{view}.png")
    render_silhouette(model, view, png)
    m, _ = mask_of(png, isolate=False)
    return m


a = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if a and a[0] == "--null":
    if len(a) < 4:
        raise SystemExit("usage: -- --null <sheet.png> <view> <subject-model> "
                         "[family-prefix ...]")
    ref = a[1] if os.path.isabs(a[1]) else os.path.join(ROOT, "art", "reference", a[1])
    view, subject = a[2], a[3]
    prefixes = a[4:] or [subject.split("_", 1)[0] + "_"]
    if view not in VIEWS_RENDERABLE:
        raise SystemExit(f"FAIL: no '{view}' camera")
    B0, info = region_mask(ref, view)
    if B0 is None:
        raise SystemExit(f"FAIL: {info}")
    outdir = os.path.join(ROOT, "art", "verify", "null")
    os.makedirs(outdir, exist_ok=True)
    B = resample(B0)
    scores = {}
    for nm in model_names(prefixes):
        if nm == subject:
            continue
        A0 = silhouette_of(nm, view, outdir)
        if A0 is None:
            continue
        A = resample(A0)
        scores[nm] = round(float(np.logical_and(A, B).sum()) /
                           max(int(np.logical_or(A, B).sum()), 1), 4)
    if not scores:
        raise SystemExit(f"FAIL: no models matched {prefixes} besides {subject}")
    top = max(scores, key=scores.get)
    p = null_path(ref)
    d = json.load(open(p)) if os.path.exists(p) else {}
    d["_note"] = ("Measured by verify_shape.py --null, not authored. 'max' is "
                  "the best IoU any model that is NOT the subject reaches on "
                  "this declared region; a score at or below it does not "
                  "distinguish the model from a wrong one. Regenerate after "
                  "changing the sidecar rect/rot/mirror or the model pool.")
    d[view] = {"subject": subject, "pool": prefixes, "n": len(scores),
               "max": scores[top], "max_model": top, "scores": scores}
    with open(p, "w") as f:
        json.dump(d, f, indent=1, sort_keys=True)
        f.write("\n")
    print(f"NULL {os.path.basename(ref)}[{view}]  subject={subject}  "
          f"n={len(scores)}  max={scores[top]:.3f} by {top}")
    print(f"     -> {os.path.relpath(p, ROOT)}")
    raise SystemExit(0)

if len(a) < 2:
    raise SystemExit("usage: -- <model> <reference.png> [top|side]\n"
                     "       -- --null <reference.png> <view> <subject-model> "
                     "[family-prefix ...]")
name, ref, view = a[0], a[1], (a[2] if len(a) > 2 else "side")
ref = ref if os.path.isabs(ref) else os.path.join(ROOT, "art", "reference", ref)

outdir = os.path.join(ROOT, "art", "verify")
os.makedirs(outdir, exist_ok=True)


def cannot_score(reason):
    """Refusing to score is a real outcome, and not the same as scoring low.

    A low IoU is a measurement: the model was compared with the declared view
    and disagreed with it. CANNOT SCORE means no comparison happened at all.
    Collapsing the two is how an unscorable sheet ends up quoted as a number.
    """
    print(f"SHAPE {name} [{view}]  CANNOT SCORE  ({reason})")
    raise SystemExit(2)


# Refuse before rendering anything if the target is not declared.
if view not in VIEWS_RENDERABLE:
    cannot_score(f"render_silhouette() implements {list(VIEWS_RENDERABLE)}; "
                 f"there is no '{view}' camera to compare against")
probe, why = region_mask(ref, view)
if probe is None:
    cannot_score(why)
clash = handedness_conflict(ref, view)
if clash:
    cannot_score(clash)

kind, ink, notes = assess_reference(ref)
print(f"      reference: {kind}, {ink:.1%} ink" +
      ("  [" + "; ".join(notes) + "]" if notes else ""))
if kind == "photo":
    cannot_score("reference is a photograph, not a line drawing or "
                 "silhouette — shape scoring needs clean orthographic art")

mine_png = os.path.join(outdir, f"{name}_{view}.png")
render_silhouette(name, view, mine_png)

# Every dark pixel in the model render IS the model: the world is white and
# the only material is a black emission shader. Isolating the largest component
# here deletes legitimately disconnected parts of the subject — engine nacelles
# seen from above, external stores, rotor discs, outriggers, tail booms.
A0, _ = mask_of(mine_png, isolate=False)
if A0 is None:
    raise SystemExit("FAIL: model silhouette is empty")

B0, info = region_mask(ref, view)
if B0 is None:
    cannot_score(info)
print(f"      target: {os.path.basename(sidecar_path(ref))}[{view}]  {info}")

# No flip here. A0 and B0 come through the identical _load_rgba path and so
# already share Blender's row-0-is-bottom ordering; flipping only A mirrored
# the model against the reference. (The [::-1] further down is a different
# thing — that one converts back to top-down order for the PNG write, and is
# correct.)
A = resample(A0)
B = resample(B0)
inter = int(np.logical_and(A, B).sum())
union = int(np.logical_or(A, B).sum())
iou = inter / max(union, 1)

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

# The verdict is earned against the measured null, not against a flat scale.
# GOOD used to mean "IoU >= 0.80", which an F-15 reached against a B-52 side
# view; it now additionally has to beat every wrong model that was tried.
nul = load_null(ref, view)
if iou < 0.25:
    verdict, why_v = "NO MATCH", "  (model and declared view are unrelated shapes)"
elif nul is None:
    verdict, why_v = "VERDICT WITHHELD", (
        f"  (no null measured for {os.path.basename(null_path(ref))}[{view}]; "
        f"IoU alone does not say whether a wrong model would score as well — "
        f"run --null)")
elif iou <= nul["max"]:
    verdict, why_v = "INDISTINCT", (
        f"  (this model IS the best-scoring wrong model on this region, of "
        f"{nul['n']} tried — the sheet's subject is {nul.get('subject')})"
        if nul["max_model"] == name else
        f"  (does not beat the best wrong model: {nul['max_model']} scores "
        f"{nul['max']:.3f} on this region, n={nul['n']})")
elif iou >= 0.80:
    verdict, why_v = "GOOD", ""
elif iou >= 0.65:
    verdict, why_v = "FAIR", ""
else:
    verdict, why_v = "POOR", ""
print(f"SHAPE {name} [{view}]  IoU={iou:.3f}  {verdict}{why_v}")
if nul is not None:
    if nul.get("subject") and nul["subject"] != name:
        print(f"      note: this sheet's declared subject is "
              f"{nul['subject']}, not {name}")
    print(f"      null: best of {nul['n']} wrong models = {nul['max']:.3f} "
          f"({nul['max_model']})")
print(f"      model aspect {A0.shape[1] / A0.shape[0]:.2f}   "
      f"reference aspect {B0.shape[1] / B0.shape[0]:.2f}")
print(f"      missing {(B & ~A).sum()/max(union,1):.1%}   "
      f"excess {(A & ~B).sum()/max(union,1):.1%}")
print(f"      overlay -> {os.path.relpath(cmp_png, ROOT)}")
