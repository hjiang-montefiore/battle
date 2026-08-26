"""Top-down planform confusion matrix for the air roster.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/air_planform.py

WHAT THIS MEASURES, EXACTLY
---------------------------
Not a render. Every LOD glb is imported, every mesh triangle is taken in WORLD
space and projected orthographically onto the XY plane (Blender is Z-up and the
aircraft are authored nose at +Y, so XY *is* the top-down plan). The union of
those projected triangles is rasterised into a boolean bitmap by half-plane
edge tests at pixel centres. That is a true silhouette: the exact set-union of
the planform, with no lighting, no antialiasing, no camera, no material and no
z-buffer, so the number is reproducible to the bit.

Three normalisations, because they answer three different questions:

  shape   each mask UNIFORMLY scaled about its own bbox centre so its longest
          dimension fills the frame. Removes absolute SIZE, keeps span/length
          proportion -- which is a shape cue, priority 2 in the brief.
  stretch each mask scaled ANISOTROPICALLY so its bbox exactly fills the frame.
          Removes size AND proportion, leaving only the outline. This is the
          literal "normalise to its own bounding box"; it isolates how much of
          the confusion is outline versus how much is proportion.
  scaled  all masks at ONE shared metric scale (the widest aircraft in the
          roster sets it), each centred on its own bbox centre. Size visible.

IoU = intersection / union of the two boolean masks. 1.0 = identical plan,
0.0 = disjoint. Rasterised at 1024x1024 so a 3 m loitering munition still gets
~55 px across at the shared scale.

Also emits a 60 px-per-aircraft gameplay-size version of `shape`, because that
is the size the player actually resolves.
"""
import bpy, json, math, os, sys
import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BLOCKOUT = os.path.join(ROOT, "art", "blockout")
OUT = os.path.join(ROOT, "art", "measure")
N = 1024
NG = 60                                   # gameplay-size grid

ROSTER = ["air_e1_us_interceptor", "air_e4_us_superiority", "air_e4_us_multirole",
          "air_e4_us_strike", "air_e1_us_cas", "air_e2_us_sead",
          "air_e4_us_stealth", "air_e4_us_stealthbomber", "air_e1_us_bomber",
          "ewa_e2_us_electronic", "aew_e3_us_aewc", "aew_e3_uk_aewhelo",
          "isr_e1_us_recon", "mpa_e1_us_maritime", "tkr_e2_us_tanker",
          "hel_e3_us_attack", "hel_e2_us_transport", "hel_e2_us_asw",
          "uav_e5_us_recon", "uav_e6_us_armed", "uav_e7_us_loiter"]
FASTJET = ["air_e1_us_interceptor", "air_e4_us_superiority", "air_e4_us_multirole",
           "air_e4_us_strike", "air_e1_us_cas", "air_e2_us_sead",
           "air_e4_us_stealth"]
SHORT = {n: n.split("_")[-1] for n in ROSTER}
SHORT["air_e4_us_stealthbomber"] = "stlthbmbr"
SHORT["air_e4_us_stealth"] = "stealth"
SHORT["ewa_e2_us_electronic"] = "elecattack"
SHORT["aew_e3_uk_aewhelo"] = "aewhelo"
SHORT["isr_e1_us_recon"] = "isr_recon"
SHORT["uav_e5_us_recon"] = "uav_recon"
SHORT["hel_e3_us_attack"] = "hel_attack"
SHORT["hel_e2_us_transport"] = "hel_trans"
SHORT["hel_e2_us_asw"] = "hel_asw"
SHORT["uav_e6_us_armed"] = "uav_armed"
SHORT["uav_e7_us_loiter"] = "uav_loiter"


# ── geometry -> projected triangles ────────────────────────────────
def clear():
    bpy.ops.wm.read_factory_settings(use_empty=True)


def tris_of(path):
    """World-space triangles of every mesh in the glb, projected to XY."""
    clear()
    bpy.ops.import_scene.gltf(filepath=path)
    bpy.context.view_layer.update()
    out = []
    for o in bpy.data.objects:
        if o.type != "MESH" or not o.data.polygons:
            continue
        me = o.data
        mw = np.array(o.matrix_world.transposed())        # row-vector convention
        n = len(me.vertices)
        co = np.empty(n * 3, dtype=np.float64)
        me.vertices.foreach_get("co", co)
        co = co.reshape(n, 3)
        co = np.hstack([co, np.ones((n, 1))]) @ mw        # -> world
        me.calc_loop_triangles()
        m = len(me.loop_triangles)
        if not m:
            continue
        idx = np.empty(m * 3, dtype=np.int64)
        me.loop_triangles.foreach_get("vertices", idx)
        out.append(co[idx.reshape(m, 3)][:, :, :2])       # keep X,Y only
    return np.concatenate(out, axis=0) if out else np.zeros((0, 3, 2))


def raster(tris, n, cx, cy, sx, sy):
    """Boolean union of triangles. col = (x-cx)*sx + n/2, row = n/2 - (y-cy)*sy."""
    m = np.zeros((n, n), dtype=bool)
    if len(tris) == 0:
        return m
    px = (tris[:, :, 0] - cx) * sx + n / 2.0
    py = n / 2.0 - (tris[:, :, 1] - cy) * sy
    x0 = np.floor(px.min(1)).astype(int); x1 = np.ceil(px.max(1)).astype(int)
    y0 = np.floor(py.min(1)).astype(int); y1 = np.ceil(py.max(1)).astype(int)
    for t in range(len(tris)):
        ax0, ax1 = max(0, x0[t]), min(n - 1, x1[t])
        ay0, ay1 = max(0, y0[t]), min(n - 1, y1[t])
        if ax1 < ax0 or ay1 < ay0:
            continue
        X = np.arange(ax0, ax1 + 1) + 0.5
        Y = (np.arange(ay0, ay1 + 1) + 0.5)[:, None]
        (Ax, Ay), (Bx, By), (Cx, Cy) = zip(px[t], py[t])
        d = (Bx - Ax) * (Cy - Ay) - (By - Ay) * (Cx - Ax)
        if abs(d) < 1e-12:                      # degenerate: stamp its bbox line
            m[ay0:ay1 + 1, ax0:ax1 + 1] |= (ax1 - ax0 < 2) or (ay1 - ay0 < 2)
            continue
        w0 = ((Bx - Ax) * (Y - Ay) - (By - Ay) * (X - Ax)) / d
        w1 = ((Cx - Bx) * (Y - By) - (Cy - By) * (X - Bx)) / d
        w2 = ((Ax - Cx) * (Y - Cy) - (Ay - Cy) * (X - Cx)) / d
        m[ay0:ay1 + 1, ax0:ax1 + 1] |= (w0 >= 0) & (w1 >= 0) & (w2 >= 0)
    return m


def iou(a, b):
    u = np.count_nonzero(a | b)
    return float(np.count_nonzero(a & b) / u) if u else 0.0


# ── wing parameters, by instrumenting the builder ──────────────────
def wing_params():
    import air_models as A
    rec, cur = {}, [None]
    orig_wings, orig_plate = A.wings, A.plate

    def wings(root_y, span, root_c, tip_c, sweep, thick, z, name="wing"):
        rec[cur[0]]["wings"].append(dict(name=name, root_y=root_y, span=span,
                                         root_c=root_c, tip_c=tip_c, sweep=sweep))
        return orig_wings(root_y, span, root_c, tip_c, sweep, thick, z, name)

    def plate(pts, thick, z, name="plate"):
        rec[cur[0]]["plates"].append(dict(name=name, pts=[list(p) for p in pts]))
        return orig_plate(pts, thick, z, name)

    A.wings, A.plate = wings, plate
    for name, fn, _ in A.AIR:
        cur[0] = name
        rec[name] = dict(wings=[], plates=[])
        clear()
        try:
            _, meta = fn()
            rec[name]["decl_l"] = meta["hull_l"]
            rec[name]["decl_w"] = meta["hull_w"]
        except Exception as e:                                   # pragma: no cover
            rec[name]["error"] = repr(e)
    A.wings, A.plate = orig_wings, orig_plate
    return rec


# ── png writing ────────────────────────────────────────────────────
def write_png(arr, path):
    """arr: float HxW in 0..1 -> greyscale png via Blender's image API."""
    h, w = arr.shape
    img = bpy.data.images.new("sheet", width=w, height=h, alpha=False)
    rgba = np.ones((h, w, 4), dtype=np.float32)
    rgba[:, :, 0] = rgba[:, :, 1] = rgba[:, :, 2] = arr[::-1]    # png origin bottom
    img.pixels.foreach_set(rgba.ravel())
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def main():
    os.makedirs(OUT, exist_ok=True)
    wp = wing_params()

    tris, bbox = {}, {}
    for name in ROSTER:
        for lod in (0, 1, 2):
            p = os.path.join(BLOCKOUT, "e4_air", f"{name}_LOD{lod}.glb")
            t = tris_of(p)
            tris[(name, lod)] = t
            xs, ys = t[:, :, 0], t[:, :, 1]
            bbox[(name, lod)] = (float(xs.min()), float(xs.max()),
                                 float(ys.min()), float(ys.max()))
            print(f"  {name:26s} LOD{lod} {len(t):6d} tris")

    GLOBAL = max(max(bbox[(n, 1)][1] - bbox[(n, 1)][0],
                     bbox[(n, 1)][3] - bbox[(n, 1)][2]) for n in ROSTER)

    masks = {}
    for name in ROSTER:
        for lod in (0, 1, 2):
            x0, x1, y0, y1 = bbox[(name, lod)]
            cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
            w, h = max(x1 - x0, 1e-6), max(y1 - y0, 1e-6)
            t = tris[(name, lod)]
            u = (N - 2) / max(w, h)
            masks[("shape", name, lod)] = raster(t, N, cx, cy, u, u)
            masks[("stretch", name, lod)] = raster(t, N, cx, cy,
                                                   (N - 2) / w, (N - 2) / h)
            g = (N - 2) / GLOBAL
            masks[("scaled", name, lod)] = raster(t, N, cx, cy, g, g)
            ug = (NG - 1) / max(w, h)
            masks[("game", name, lod)] = raster(t, NG, cx, cy, ug, ug)

    mats = {}
    for kind in ("shape", "stretch", "scaled", "game"):
        for lod in (0, 1, 2):
            M = np.eye(len(ROSTER))
            for i, a in enumerate(ROSTER):
                for j in range(i + 1, len(ROSTER)):
                    v = iou(masks[(kind, a, lod)], masks[(kind, ROSTER[j], lod)])
                    M[i, j] = M[j, i] = v
            mats[f"{kind}_lod{lod}"] = M

    # ── report ─────────────────────────────────────────────────────
    lines = []
    P = lines.append
    P("METHOD: orthographic top-down (XY) union-of-triangles rasterisation at "
      f"{N}x{N}, half-plane test at pixel centres; IoU = |A&B|/|A|B|.")
    P(f"shared metric scale set by the widest plan in the roster: {GLOBAL:.2f} m")
    P("")
    P("=== PLANFORM TABLE (geometry-measured from LOD1, metres) ===")
    P(f"{'aircraft':<26}{'span':>7}{'length':>8}{'sp/len':>8}{'LEswp':>7}"
      f"{'AR':>6}{'declW':>7}{'declL':>7}")
    tab = {}
    for n in ROSTER:
        x0, x1, y0, y1 = bbox[(n, 1)]
        span, leng = x1 - x0, y1 - y0
        w = [x for x in wp[n]["wings"]]
        mw = max(w, key=lambda d: d["span"]) if w else None
        if mw:
            run = mw["span"] / 2.0 - 0.30
            swp = math.degrees(math.atan2(mw["sweep"], run)) if run > 0 else 0.0
            area = mw["span"] * (mw["root_c"] + mw["tip_c"]) / 2.0
            ar = mw["span"] ** 2 / area if area else 0.0
        else:
            swp, ar = float("nan"), float("nan")
        tab[n] = dict(span=span, length=leng, ratio=span / leng, sweep=swp, ar=ar,
                      decl_w=wp[n]["decl_w"], decl_l=wp[n]["decl_l"],
                      main_wing=mw)
        P(f"{SHORT[n]:<26}{span:7.2f}{leng:8.2f}{span/leng:8.3f}{swp:7.1f}"
          f"{ar:6.2f}{wp[n]['decl_w']:7.2f}{wp[n]['decl_l']:7.2f}")
    P("")

    def worst(kind, lod, k=25):
        M = mats[f"{kind}_lod{lod}"]
        pairs = [(M[i, j], ROSTER[i], ROSTER[j])
                 for i in range(len(ROSTER)) for j in range(i + 1, len(ROSTER))]
        return sorted(pairs, reverse=True)[:k]

    P("=== 25 WORST PAIRS, ranked by shape IoU at LOD1 ===")
    P(f"{'#':>3} {'pair':<26}{'shapeL1':>9}{'shapeL2':>9}{'stretchL1':>11}"
      f"{'scaledL1':>10}{'game60':>8}")
    S1 = mats["shape_lod1"]
    order = sorted([(S1[i, j], i, j) for i in range(len(ROSTER))
                    for j in range(i + 1, len(ROSTER))], reverse=True)
    worst_rows = []
    for r, (v, i, j) in enumerate(order[:25], 1):
        a, b = ROSTER[i], ROSTER[j]
        row = dict(rank=r, a=a, b=b, shape_lod1=v,
                   shape_lod2=mats["shape_lod2"][i, j],
                   stretch_lod1=mats["stretch_lod1"][i, j],
                   scaled_lod1=mats["scaled_lod1"][i, j],
                   game60_lod1=mats["game_lod1"][i, j])
        worst_rows.append(row)
        P(f"{r:>3} {SHORT[a]+' / '+SHORT[b]:<26}{v:9.4f}"
          f"{row['shape_lod2']:9.4f}{row['stretch_lod1']:11.4f}"
          f"{row['scaled_lod1']:10.4f}{row['game60_lod1']:8.4f}")
    P("")
    for kind in ("stretch", "scaled"):
        P(f"--- top 10 by {kind} IoU at LOD1 (cross-check) ---")
        for r, (v, a, b) in enumerate(worst("%s" % kind, 1, 10), 1):
            P(f"{r:>3} {SHORT[a]+' / '+SHORT[b]:<26}{v:9.4f}")
        P("")

    idx = [ROSTER.index(n) for n in FASTJET]
    for kind, lod in (("shape", 1), ("shape", 2), ("stretch", 1), ("scaled", 1),
                      ("game", 1)):
        M = mats[f"{kind}_lod{lod}"]
        P(f"=== FAST JET MATRIX  ({kind}, LOD{lod}) ===")
        P(" " * 14 + "".join(f"{SHORT[n][:9]:>11}" for n in FASTJET))
        for a in idx:
            P(f"{SHORT[ROSTER[a]][:13]:<14}" +
              "".join("       --- " if a == b else f"{M[a, b]:11.4f}" for b in idx))
        sub = [M[a, b] for ii, a in enumerate(idx) for b in idx[ii + 1:]]
        P(f"  mean {np.mean(sub):.4f}   max {np.max(sub):.4f}   "
          f"min {np.min(sub):.4f}   n={len(sub)}")
        P("")

    P("=== per-aircraft worst partner (shape LOD1) ===")
    for i, n in enumerate(ROSTER):
        row = [(S1[i, j], ROSTER[j]) for j in range(len(ROSTER)) if j != i]
        v, o = max(row)
        P(f"{SHORT[n]:<26}{v:7.4f}  vs {SHORT[o]}")

    txt = "\n".join(lines)
    print(txt)
    open(os.path.join(OUT, "air_planform.txt"), "w").write(txt + "\n")
    json.dump(dict(method=lines[0], global_scale=GLOBAL, roster=ROSTER,
                   table=tab, worst=worst_rows,
                   matrices={k: v.tolist() for k, v in mats.items()}),
              open(os.path.join(OUT, "air_planform.json"), "w"), indent=1,
              default=str)

    # ── contact sheets ─────────────────────────────────────────────
    cell, cols = 256, 6
    rows = (len(ROSTER) + cols - 1) // cols
    for kind, fn in (("scaled", "sheet_shared_scale"), ("shape", "sheet_shape")):
        sheet = np.ones((rows * cell, cols * cell), dtype=np.float32)
        for k, n in enumerate(ROSTER):
            m = masks[(kind, n, 1)]
            small = m.reshape(cell, N // cell, cell, N // cell).any(1).any(2)
            r, c = divmod(k, cols)
            sheet[r * cell:(r + 1) * cell, c * cell:(c + 1) * cell] = 1.0 - small
            sheet[r * cell, :] = 0.7
        write_png(sheet, os.path.join(OUT, f"{fn}.png"))
    # fast jets, own-bbox shape, big; and the same at 60 px blown up
    big = np.ones((cell, len(FASTJET) * cell), dtype=np.float32)
    tiny = np.ones((cell, len(FASTJET) * cell), dtype=np.float32)
    for k, n in enumerate(FASTJET):
        m = masks[("shape", n, 1)]
        big[:, k * cell:(k + 1) * cell] = 1.0 - m.reshape(
            cell, N // cell, cell, N // cell).any(1).any(2)
        g = masks[("game", n, 1)]
        up = np.kron(g, np.ones((4, 4)))[:cell, :cell]
        pad = np.ones((cell, cell), dtype=np.float32)
        pad[:up.shape[0], :up.shape[1]] = 1.0 - up
        tiny[:, k * cell:(k + 1) * cell] = pad
    write_png(np.vstack([big, tiny]), os.path.join(OUT, "sheet_fastjet.png"))
    print("wrote", OUT)


main()
