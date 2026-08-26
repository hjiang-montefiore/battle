"""Parametric armoured-vehicle blockouts.

These are GREYBOX PROXIES, not art. Their job is to be correctly scaled,
correctly socketed and readable in silhouette so that engine, gameplay and
pipeline work can proceed before an artist opens Blender.

Every dimension is in metres and matches the real vehicle class it stands for.
Silhouette is the point — see docs/07-art-pipeline.md.
"""
from gltf import Gltf, box, prism, cylinder_z

# ── the socket contract (docs/07-art-pipeline.md) ──────────────────
REQUIRED_SOCKETS = [
    "turret_mount", "gun_mantlet", "sensor_mast", "exhaust",
    "track_left", "track_right",
    "damage_hull", "damage_turret", "damage_track",
]
OPTIONAL_SOCKET_GROUPS = {"era_plate": 6, "aps_launcher": 4, "hardpoint": 4}

PALETTE = {
    "hull":   (0.36, 0.38, 0.33),
    "turret": (0.40, 0.42, 0.37),
    "gun":    (0.24, 0.25, 0.23),
    "track":  (0.17, 0.17, 0.18),
    "detail": (0.30, 0.31, 0.29),
    "era":    (0.46, 0.42, 0.30),
    "team":   (0.55, 0.30, 0.16),   # team-colour mask area
}


def spec(**kw):
    d = dict(
        hull_l=7.0, hull_w=3.6, hull_h=1.15, clearance=0.45,
        glacis_l=1.9, glacis_h=0.75,
        turret_l=3.4, turret_w=2.7, turret_h=0.85, turret_z=0.10,
        turret_taper_z=0.72, turret_taper_x=0.80, bustle=0.0,
        gun_len=5.3, gun_r=0.115,
        track_w=0.60, wheels=6, skirts=True,
        era=0, aps=0, style="western",
    )
    d.update(kw)
    return d


def build(g, s, lod):
    """Returns (geoms, sockets). lod 0 = full, 1 = gameplay, 2 = silhouette."""
    M = {k: g.material(k, v) for k, v in PALETTE.items()}
    G = []
    hy = s["clearance"] + s["hull_h"] / 2          # hull centre height
    top = s["clearance"] + s["hull_h"]             # hull roof
    ty = top + s["turret_z"] / 2

    # hull
    G.append(box((0, hy, 0), (s["hull_w"], s["hull_h"], s["hull_l"])) + (M["hull"],))
    # sloped glacis
    G.append(prism((0, s["clearance"] + s["glacis_h"] / 2, -(s["hull_l"] / 2 + s["glacis_l"] / 2)),
                   (s["hull_w"], s["glacis_h"], s["glacis_l"]),
                   top_scale_z=0.15, top_scale_x=0.94) + (M["hull"],))
    # turret ring riser
    G.append(box((0, ty, 0.15), (s["turret_w"] * 0.85, s["turret_z"], s["turret_l"] * 0.8)) + (M["turret"],))

    # turret
    tby = top + s["turret_z"]
    G.append(prism((0, tby + s["turret_h"] / 2, 0.15),
                   (s["turret_w"], s["turret_h"], s["turret_l"]),
                   top_scale_z=s["turret_taper_z"], top_scale_x=s["turret_taper_x"]) + (M["turret"],))
    if s["bustle"] > 0:
        G.append(box((0, tby + s["turret_h"] * 0.55, s["turret_l"] / 2 + s["bustle"] / 2 + 0.1),
                     (s["turret_w"] * 0.7, s["turret_h"] * 0.7, s["bustle"])) + (M["turret"],))

    gy = tby + s["turret_h"] * 0.45
    gz = -(s["turret_l"] / 2) + 0.15
    # mantlet + barrel
    G.append(box((0, gy, gz - 0.25), (0.85, 0.62, 0.7)) + (M["gun"],))
    G.append(cylinder_z((0, gy, gz - 0.5), s["gun_r"], s["gun_len"],
                        seg=8 if lod else 12, taper=0.92) + (M["gun"],))

    # running gear
    for sgn in (-1, 1):
        x = sgn * (s["hull_w"] / 2 - s["track_w"] / 2)
        G.append(box((x, s["clearance"] * 0.62, 0),
                     (s["track_w"], s["clearance"] * 1.24, s["hull_l"] * 0.98)) + (M["track"],))
        if lod == 0:
            for w in range(s["wheels"]):
                z = -s["hull_l"] * 0.42 + w * (s["hull_l"] * 0.84 / max(s["wheels"] - 1, 1))
                G.append(box((x, s["clearance"] * 0.62, z),
                             (s["track_w"] * 1.12, s["clearance"] * 1.0, 0.55)) + (M["detail"],))
        if lod <= 1 and s["skirts"]:
            G.append(box((x, s["clearance"] + 0.28, 0),
                         (0.10, 0.56, s["hull_l"] * 0.9)) + (M["detail"],))

    if lod == 0:
        # stowage + team-colour panel (top-visible, per docs/07)
        G.append(box((0, tby + s["turret_h"] + 0.10, 0.15),
                     (s["turret_w"] * 0.42, 0.20, s["turret_l"] * 0.38)) + (M["team"],))
        G.append(box((s["hull_w"] * 0.30, top + 0.16, s["hull_l"] * 0.36),
                     (0.70, 0.32, 0.9)) + (M["detail"],))
        for e in range(s["era"]):
            col, row = e % 3, e // 3
            G.append(box((-0.6 + col * 0.6, tby + 0.30 + row * 0.34, gz - 0.05),
                         (0.52, 0.28, 0.16)) + (M["era"],))
        for a in range(s["aps"]):
            G.append(box(((-1 if a % 2 else 1) * (s["turret_w"] / 2 + 0.10),
                          tby + 0.42, 0.5 - (a // 2) * 0.9),
                         (0.22, 0.34, 0.5)) + (M["detail"],))

    sockets = {
        "turret_mount":  (0, top, 0.15),
        "gun_mantlet":   (0, gy, gz - 0.25),
        "sensor_mast":   (s["turret_w"] * 0.28, tby + s["turret_h"] + 0.15, 0.55),
        "exhaust":       (0, top - 0.15, s["hull_l"] / 2),
        "track_left":    (-(s["hull_w"] / 2 - s["track_w"] / 2), s["clearance"] * 0.6, 0),
        "track_right":   ((s["hull_w"] / 2 - s["track_w"] / 2), s["clearance"] * 0.6, 0),
        "damage_hull":   (0, top, -0.6),
        "damage_turret": (0, tby + s["turret_h"], 0.15),
        "damage_track":  (-(s["hull_w"] / 2), s["clearance"] * 0.6, -1.2),
    }
    for i in range(OPTIONAL_SOCKET_GROUPS["era_plate"]):
        sockets[f"era_plate_{i+1}"] = (-0.6 + (i % 3) * 0.6, tby + 0.30 + (i // 3) * 0.34, gz)
    for i in range(OPTIONAL_SOCKET_GROUPS["aps_launcher"]):
        sockets[f"aps_launcher_{i+1}"] = ((-1 if i % 2 else 1) * (s["turret_w"] / 2 + 0.10),
                                          tby + 0.42, 0.5 - (i // 2) * 0.9)
    for i in range(OPTIONAL_SOCKET_GROUPS["hardpoint"]):
        sockets[f"hardpoint_{i+1}"] = (0, tby + s["turret_h"] + 0.2, 0.9 - i * 0.5)
    return G, sockets


def write(path, name, s, lod):
    g = Gltf()
    geoms, sockets = build(g, s, lod)
    mesh = g.mesh(f"{name}_LOD{lod}", geoms)
    kids = [g.node(f"SOCKET_{k}", translation=v, extras={"socket": k})
            for k, v in sorted(sockets.items())]
    body = g.node(f"{name}_LOD{lod}_body", mesh=mesh)
    root = g.node(name, children=[body] + kids,
                  extras={"lod": lod, "blockout": True, "style": s["style"]})
    g.save(path, [root])
    tris = sum(len(gm[2]) for gm in geoms) // 3
    return tris, len(sockets)
