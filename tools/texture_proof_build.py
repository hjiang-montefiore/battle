"""Texture-pass proof: drive the composed-texture API on one aircraft and one
ship WITHOUT touching the roster modules (their geometry is owned elsewhere).

    Blender -b --python tools/texture_proof_build.py

This is exactly the call pattern the roster appliers will use — a
texture_features() registration next to the roster, then the normal build.
"""
import os, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_models as H

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# ── F-16C multirole. Nose is +Y in its build space; wing top z ~ 0.12 ──
H.texture_features(
    "air_e4_us_multirole",
    size_class="aircraft",
    groups=("body",),
    panels=dict(spacing=1.6, strength=0.5, jitter=0.07, seams=0.45),
    weathering=dict(
        exhaust=[dict(origin=(0.0, -5.0, 0.2), direction=(0, -1, 0.05),
                      length=2.8, width=0.55, strength=0.5)],
        edge_wear=dict(strength=0.4)),
    insignia=[
        dict(kind="star_us", center=(-2.7, -1.7, 0.14), normal=(0, 0, 1),
             size=1.25, up=(0, 1, 0), alpha=0.9, color=(0.30, 0.32, 0.36)),
        dict(kind="star_us", center=(2.7, -1.7, 0.14), normal=(0, 0, 1),
             size=1.25, up=(0, 1, 0), alpha=0.9, color=(0.30, 0.32, 0.36)),
        dict(kind="star_us", center=(0.95, -2.0, 0.10), normal=(1, 0, 0),
             size=0.75, alpha=0.9, color=(0.30, 0.32, 0.36)),
        dict(kind="star_us", center=(-0.95, -2.0, 0.10), normal=(-1, 0, 0),
             size=0.75, alpha=0.9, color=(0.30, 0.32, 0.36)),
        dict(kind="pennant", center=(0.0, -5.6, 2.3), normal=(1, 0, 0),
             size=1.1, alpha=0.85, text="16", color=(0.30, 0.32, 0.36)),
    ])

# ── Arleigh Burke destroyer. Bow +Y; deck edge ~z 5.9, funnel tops ~17 ──
H.texture_features(
    "nav_e4_us_destroyer",
    size_class="ship",
    groups=("body",),
    panels=dict(spacing=6.0, strength=0.4, jitter=0.07, seams=0.45),
    weathering=dict(
        streaks=dict(z0=5.9, length=5.5, density=0.40, strength=0.55,
                     tint=(0.26, 0.19, 0.14)),
        exhaust=[dict(origin=(0.0, -1.0, 17.0), direction=(0, -1, 0.15),
                      length=7.0, width=1.6, strength=0.38),
                 dict(origin=(0.0, -18.5, 17.0), direction=(0, -1, 0.15),
                      length=7.0, width=1.6, strength=0.38)],
        edge_wear=dict(strength=0.35)),
    insignia=[
        dict(kind="pennant", center=(6.5, 60.0, 5.0), normal=(1, 0.2, 0),
             size=5.0, alpha=0.9, text="62"),
        dict(kind="pennant", center=(-6.5, 60.0, 5.0), normal=(-1, 0.2, 0),
             size=5.0, alpha=0.9, text="62"),
        dict(kind="helipad", center=(0.0, -67.0, 6.0), normal=(0, 0, 1),
             size=11.0, up=(0, 1, 0), alpha=0.85),
    ])

import air_models      # noqa: E402  (registers nothing; rosters only)
import navy_models     # noqa: E402

for mod, bucket, roster in ((air_models, "e4_air", air_models.AIR),
                            (navy_models, "e4_navy", navy_models.NAVY)):
    for entry in roster:
        name, fn = entry[0], entry[1]
        if name not in H.TEXTURE_FEATURES:
            continue
        camo = entry[2] if len(entry) > 2 and isinstance(entry[2], str) else None
        if camo:
            H.CAMO[name] = camo
        H.CAMO.setdefault(name, "camo_us")
        H.TEAM.setdefault(name, (0.06, 0.20, 0.62))
        H.set_out(os.path.join(ROOT, "art", "blockout", bucket))
        for lod in (0, 1, 2):
            n = H.build(name, fn, lod)
            print(f"BUILT {name} LOD{lod} {n}")
print("proof build done")
