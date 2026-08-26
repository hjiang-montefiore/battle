#!/usr/bin/env python3
"""Rewrite a GLB into a canonical vertex and triangle order.

    python3 tools/canonicalise_glb.py art/blockout/**/*.glb
    python3 tools/canonicalise_glb.py --check a.glb b.glb   # do two files match?

WHY
---
Blender's exported vertex and face order depends on `bmesh` container iteration,
which hashes by memory address. Under ASLR that order changes between processes,
so two builds of identical geometry emit different bytes: POSITION data matches,
but INDEX, NORMAL and TEXCOORD do not. Measured on this project, 10 of 12 files
differed across runs for geometry that had not changed at all.

This pass makes the ordering a property of the geometry rather than of the
allocator:

  1. sort vertices lexicographically by quantised position, then normal, then UV
  2. permute every attribute by that order
  3. remap indices, rotate each triangle so its lowest index comes first
     (which preserves winding), then sort the triangle list

Two builds of the same geometry then produce identical bytes regardless of what
order Blender happened to emit.

WHAT THIS FIXES, MEASURED
-------------------------
Comparing two builds of the same unit, per mesh group:

    5 of 6 groups   positions byte-identical (max delta 0.00e+00 m)
    1 of 6 groups   vertex COUNT differs, 5204 vs 5196

So the geometry is deterministic. The one group that varies is the body, and it
varies because `bpy.ops.uv.smart_project` — used to make the non-overlapping UV1
channel that ambient occlusion bakes into — cuts island seams differently each
run, and a UV seam splits a vertex. Different seams, different vertex count.

Canonicalising therefore fixes the five groups whose only problem was ordering.
It cannot fix the sixth, because that group genuinely has a different vertex set,
and the baked AO image is keyed to the very UV layout that varied.

THE HONEST CONCLUSION
---------------------
Full byte-reproducibility needs a deterministic replacement for smart_project on
the bake channel. Short of that, generated binaries should not be tracked in
version control — which is the ordinary answer for build output anyway. Tracking
them was a workaround for irreproducibility; the better fix is to make the build
runnable by anyone (done: no hardcoded paths) and publish art as release
artefacts rather than commits.

Pure stdlib: this runs under system Python, not Blender.
"""
import json
import os
import struct
import sys

# glTF componentType -> (struct code, byte size)
CT = {5120: ("b", 1), 5121: ("B", 1), 5122: ("h", 2),
      5123: ("H", 2), 5125: ("I", 4), 5126: ("f", 4)}
NCOMP = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}
QUANT = 1e-5          # position tie-break resolution, ~10 microns
WELD = 1e-4           # weld tolerance, 0.1 mm — well under anything visible
                      # at RTS zoom but far above float round-trip noise


def read_glb(path):
    with open(path, "rb") as f:
        magic, ver, _ = struct.unpack("<4sII", f.read(12))
        if magic != b"glTF" or ver != 2:
            raise ValueError(f"{path}: not glTF 2.0 binary")
        doc = bin_ = None
        while True:
            hdr = f.read(8)
            if len(hdr) < 8:
                break
            ln, kind = struct.unpack("<II", hdr)
            data = f.read(ln)
            if kind == 0x4E4F534A:
                doc = json.loads(data)
            elif kind == 0x004E4942:
                bin_ = data
    return doc, (bin_ or b"")


def write_glb(path, doc, bin_):
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    bn = bin_ + b"\x00" * ((4 - len(bin_) % 4) % 4)
    total = 12 + 8 + len(js) + 8 + len(bn)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(bn), 0x004E4942)); f.write(bn)


def read_accessor(doc, bin_, idx):
    acc = doc["accessors"][idx]
    code, size = CT[acc["componentType"]]
    n = NCOMP[acc["type"]]
    bv = doc["bufferViews"][acc["bufferView"]]
    base = bv.get("byteOffset", 0) + acc.get("byteOffset", 0)
    stride = bv.get("byteStride") or size * n
    out = []
    for i in range(acc["count"]):
        off = base + i * stride
        out.append(struct.unpack_from("<" + code * n, bin_, off))
    return out, acc


def canonicalise(path, verbose=False):
    doc, bin_ = read_glb(path)
    if not doc.get("meshes"):
        return False

    new_bin = bytearray()
    new_views = []
    new_accessors = []

    def emit(values, acc_template, target=None):
        """Append tightly-packed data, return the new accessor index."""
        code, size = CT[acc_template["componentType"]]
        n = NCOMP[acc_template["type"]]
        while len(new_bin) % 4:
            new_bin.append(0)
        off = len(new_bin)
        for v in values:
            new_bin.extend(struct.pack("<" + code * n, *v))
        bv = {"buffer": 0, "byteOffset": off, "byteLength": len(new_bin) - off}
        if target:
            bv["target"] = target
        new_views.append(bv)
        a = {"bufferView": len(new_views) - 1,
             "componentType": acc_template["componentType"],
             "count": len(values), "type": acc_template["type"]}
        if acc_template.get("normalized"):
            a["normalized"] = True
        if acc_template["type"] == "VEC3" and acc_template.get("min") is not None:
            cols = list(zip(*values)) if values else []
            a["min"] = [min(c) for c in cols]
            a["max"] = [max(c) for c in cols]
        new_accessors.append(a)
        return len(new_accessors) - 1

    changed = 0
    for mesh in doc["meshes"]:
        for prim in mesh["primitives"]:
            attrs = prim["attributes"]
            if "POSITION" not in attrs:
                continue
            decoded = {}
            templates = {}
            for k, ai in attrs.items():
                decoded[k], templates[k] = read_accessor(doc, bin_, ai)
            nvert = len(decoded["POSITION"])

            # 1. RE-WELD, then order. Sorting alone is not enough: the glTF
            #    exporter's own vertex deduplication is order-dependent, so two
            #    runs emitted 2009 and 2014 vertices for the same 1584
            #    triangles. Rebuilding the vertex set from a quantised key
            #    makes the count a property of the geometry.
            keys = []
            for i in range(nvert):
                key = tuple(round(c / WELD) for c in decoded["POSITION"][i])
                for k in ("NORMAL", "TEXCOORD_0", "TEXCOORD_1", "COLOR_0"):
                    if k in decoded:
                        key += tuple(round(c / WELD) if isinstance(c, float)
                                     else c for c in decoded[k][i])
                keys.append(key)

            uniq = sorted(set(keys))
            slot = {k: n for n, k in enumerate(uniq)}
            inv = [slot[k] for k in keys]          # old vertex -> new slot
            first = {}
            for i, k in enumerate(keys):
                first.setdefault(k, i)             # representative per slot
            rep = [first[k] for k in uniq]

            for k in decoded:
                decoded[k] = [decoded[k][i] for i in rep]
            nvert = len(uniq)

            # 3. remap indices, rotate each triangle to start at its lowest
            #    vertex (winding preserved), then sort the triangle list
            if "indices" in prim:
                idx, itmpl = read_accessor(doc, bin_, prim["indices"])
                flat = [inv[v[0]] for v in idx]
                tris = []
                for t in range(0, len(flat) - 2, 3):
                    a, b, c = flat[t], flat[t + 1], flat[t + 2]
                    if b <= a and b <= c:
                        a, b, c = b, c, a
                    elif c <= a and c <= b:
                        a, b, c = c, a, b
                    tris.append((a, b, c))
                tris.sort()
                prim["indices"] = emit([(v,) for tri in tris for v in tri],
                                       itmpl, 34963)

            for k in list(attrs):
                attrs[k] = emit(decoded[k], templates[k], 34962)
            changed += 1

    if not changed:
        return False

    # carry over anything else that lived in the buffer (embedded images)
    for im in doc.get("images", []):
        if "bufferView" in im:
            bv = doc["bufferViews"][im["bufferView"]]
            off = bv.get("byteOffset", 0)
            data = bin_[off:off + bv["byteLength"]]
            while len(new_bin) % 4:
                new_bin.append(0)
            new_off = len(new_bin)
            new_bin.extend(data)
            new_views.append({"buffer": 0, "byteOffset": new_off,
                              "byteLength": len(data)})
            im["bufferView"] = len(new_views) - 1

    doc["bufferViews"] = new_views
    doc["accessors"] = new_accessors
    doc["buffers"] = [{"byteLength": len(new_bin)}]
    write_glb(path, doc, bytes(new_bin))
    if verbose:
        print(f"  canonicalised {os.path.basename(path)}  "
              f"{changed} primitive(s)")
    return True


def geometry_digest(path):
    """Hash only geometry, ignoring embedded images."""
    import hashlib
    doc, bin_ = read_glb(path)
    h = hashlib.sha256()
    for mesh in doc.get("meshes", []):
        for prim in mesh["primitives"]:
            for k in sorted(prim["attributes"]):
                vals, _ = read_accessor(doc, bin_, prim["attributes"][k])
                h.update(k.encode())
                h.update(repr(vals).encode())
            if "indices" in prim:
                vals, _ = read_accessor(doc, bin_, prim["indices"])
                h.update(repr(vals).encode())
    return h.hexdigest()[:16]


def main(argv):
    if not argv:
        print(__doc__.strip())
        return 2
    if argv[0] == "--check":
        files = argv[1:]
        if len(files) != 2:
            print("--check needs exactly two files")
            return 2
        a, b = (geometry_digest(f) for f in files)
        same = a == b
        print(f"geometry {'IDENTICAL' if same else 'DIFFERS'}   {a}  {b}")
        import hashlib
        fa, fb = (hashlib.sha256(open(f, 'rb').read()).hexdigest()[:16]
                  for f in files)
        print(f"whole file {'IDENTICAL' if fa == fb else 'DIFFERS'}   {fa}  {fb}")
        return 0 if same else 1
    n = sum(1 for p in argv if canonicalise(p, verbose=True))
    print(f"{n} file(s) canonicalised")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
