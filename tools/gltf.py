"""Minimal glTF 2.0 / GLB writer. Pure stdlib — no dependencies, no Blender.

Coordinate convention (matches Godot 4 and glTF):
    +X right   +Y up   -Z forward
Units are metres, 1:1 with the real vehicle.
"""
import json, struct

ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER = 34962, 34963
FLOAT, UINT = 5126, 5125


class Gltf:
    def __init__(self):
        self.buf = bytearray()
        self.bufferViews, self.accessors = [], []
        self.meshes, self.nodes, self.materials = [], [], []
        self._mat_index = {}

    # ── buffer plumbing ────────────────────────────────────────────
    def _view(self, data, target):
        while len(self.buf) % 4:
            self.buf.append(0)
        off = len(self.buf)
        self.buf += data
        self.bufferViews.append(
            {"buffer": 0, "byteOffset": off, "byteLength": len(data), "target": target})
        return len(self.bufferViews) - 1

    def _vec3(self, vals):
        data = b"".join(struct.pack("<3f", *v) for v in vals)
        bv = self._view(data, ARRAY_BUFFER)
        mn = [min(v[i] for v in vals) for i in range(3)]
        mx = [max(v[i] for v in vals) for i in range(3)]
        self.accessors.append({"bufferView": bv, "componentType": FLOAT,
                               "count": len(vals), "type": "VEC3", "min": mn, "max": mx})
        return len(self.accessors) - 1

    def _idx(self, vals):
        data = b"".join(struct.pack("<I", i) for i in vals)
        bv = self._view(data, ELEMENT_ARRAY_BUFFER)
        self.accessors.append({"bufferView": bv, "componentType": UINT,
                               "count": len(vals), "type": "SCALAR"})
        return len(self.accessors) - 1

    # ── authoring ──────────────────────────────────────────────────
    def material(self, name, rgb, rough=0.85, metal=0.05):
        if name in self._mat_index:
            return self._mat_index[name]
        self.materials.append({
            "name": name,
            "pbrMetallicRoughness": {
                "baseColorFactor": [rgb[0], rgb[1], rgb[2], 1.0],
                "metallicFactor": metal, "roughnessFactor": rough}})
        self._mat_index[name] = len(self.materials) - 1
        return self._mat_index[name]

    def mesh(self, name, geoms):
        """geoms: list of (verts, normals, indices, material_index)"""
        prims = []
        for verts, norms, idx, mat in geoms:
            prims.append({
                "attributes": {"POSITION": self._vec3(verts), "NORMAL": self._vec3(norms)},
                "indices": self._idx(idx), "material": mat, "mode": 4})
        self.meshes.append({"name": name, "primitives": prims})
        return len(self.meshes) - 1

    def node(self, name, mesh=None, translation=None, children=None, extras=None):
        n = {"name": name}
        if mesh is not None:
            n["mesh"] = mesh
        if translation:
            n["translation"] = list(translation)
        if children:
            n["children"] = children
        if extras:
            n["extras"] = extras
        self.nodes.append(n)
        return len(self.nodes) - 1

    # ── output ─────────────────────────────────────────────────────
    def save(self, path, roots, generator="battle-blockout"):
        doc = {
            "asset": {"version": "2.0", "generator": generator},
            "scene": 0, "scenes": [{"nodes": roots}],
            "nodes": self.nodes, "meshes": self.meshes,
            "materials": self.materials,
            "accessors": self.accessors, "bufferViews": self.bufferViews,
            "buffers": [{"byteLength": len(self.buf)}],
        }
        js = json.dumps(doc, separators=(",", ":")).encode()
        js += b" " * ((4 - len(js) % 4) % 4)
        bn = bytes(self.buf) + b"\x00" * ((4 - len(self.buf) % 4) % 4)
        total = 12 + 8 + len(js) + 8 + len(bn)
        with open(path, "wb") as f:
            f.write(struct.pack("<4sII", b"glTF", 2, total))
            f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
            f.write(struct.pack("<II", len(bn), 0x004E4942)); f.write(bn)
        return total


# ── primitive geometry ─────────────────────────────────────────────
def box(c, s):
    """Axis-aligned box. c = centre (x,y,z), s = size (x,y,z)."""
    x, y, z = c
    hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
    faces = [
        ((0, 0, 1),  [(-hx, -hy, hz), (hx, -hy, hz), (hx, hy, hz), (-hx, hy, hz)]),
        ((0, 0, -1), [(hx, -hy, -hz), (-hx, -hy, -hz), (-hx, hy, -hz), (hx, hy, -hz)]),
        ((1, 0, 0),  [(hx, -hy, hz), (hx, -hy, -hz), (hx, hy, -hz), (hx, hy, hz)]),
        ((-1, 0, 0), [(-hx, -hy, -hz), (-hx, -hy, hz), (-hx, hy, hz), (-hx, hy, -hz)]),
        ((0, 1, 0),  [(-hx, hy, hz), (hx, hy, hz), (hx, hy, -hz), (-hx, hy, -hz)]),
        ((0, -1, 0), [(-hx, -hy, -hz), (hx, -hy, -hz), (hx, -hy, hz), (-hx, -hy, hz)]),
    ]
    v, n, i = [], [], []
    for nrm, quad in faces:
        b = len(v)
        for p in quad:
            v.append((p[0] + x, p[1] + y, p[2] + z))
            n.append(nrm)
        i += [b, b + 1, b + 2, b, b + 2, b + 3]
    return v, n, i


def prism(c, s, top_scale_z=1.0, top_scale_x=1.0, shift_y=0.0):
    """Box whose top face is scaled — turret tapers, glacis wedges."""
    x, y, z = c
    hx, hy, hz = s[0] / 2, s[1] / 2, s[2] / 2
    tx, tz = hx * top_scale_x, hz * top_scale_z
    B = [(-hx, -hy, hz), (hx, -hy, hz), (hx, -hy, -hz), (-hx, -hy, -hz)]
    T = [(-tx, hy + shift_y, tz), (tx, hy + shift_y, tz),
         (tx, hy + shift_y, -tz), (-tx, hy + shift_y, -tz)]
    quads = [(B[3], B[2], B[1], B[0]), (T[0], T[1], T[2], T[3]),
             (B[0], B[1], T[1], T[0]), (B[2], B[3], T[3], T[2]),
             (B[1], B[2], T[2], T[1]), (B[3], B[0], T[0], T[3])]
    v, n, i = [], [], []
    for q in quads:
        ax = (q[1][0] - q[0][0], q[1][1] - q[0][1], q[1][2] - q[0][2])
        bx = (q[2][0] - q[0][0], q[2][1] - q[0][1], q[2][2] - q[0][2])
        nr = (ax[1] * bx[2] - ax[2] * bx[1], ax[2] * bx[0] - ax[0] * bx[2],
              ax[0] * bx[1] - ax[1] * bx[0])
        L = max((nr[0] ** 2 + nr[1] ** 2 + nr[2] ** 2) ** 0.5, 1e-9)
        nr = (nr[0] / L, nr[1] / L, nr[2] / L)
        b = len(v)
        for p in q:
            v.append((p[0] + x, p[1] + y, p[2] + z))
            n.append(nr)
        i += [b, b + 1, b + 2, b, b + 2, b + 3]
    return v, n, i


def cylinder_z(c, radius, length, seg=12, taper=1.0):
    """Cylinder along -Z — gun barrels, launcher tubes."""
    import math
    x, y, z = c
    v, n, i = [], [], []
    for k in range(seg):
        a0 = 2 * math.pi * k / seg
        a1 = 2 * math.pi * (k + 1) / seg
        for (a, rr, zz) in ((a0, radius, 0), (a1, radius, 0),
                            (a1, radius * taper, -length), (a0, radius * taper, -length)):
            pass
        p = [(math.cos(a0) * radius, math.sin(a0) * radius, 0),
             (math.cos(a1) * radius, math.sin(a1) * radius, 0),
             (math.cos(a1) * radius * taper, math.sin(a1) * radius * taper, -length),
             (math.cos(a0) * radius * taper, math.sin(a0) * radius * taper, -length)]
        nr = (math.cos((a0 + a1) / 2), math.sin((a0 + a1) / 2), 0)
        b = len(v)
        for q in p:
            v.append((q[0] + x, q[1] + y, q[2] + z))
            n.append(nr)
        i += [b, b + 1, b + 2, b, b + 2, b + 3]
    return v, n, i
