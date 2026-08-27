"""The strategic triad, textured: a lineup and a close pair.

    Blender -b --python tools/strategic_render.py

    art/renders/strategic.png        all three, RTS-ish high camera
    art/renders/strategic_close.png  silo + TEL at texture-reading distance
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gameplay_render as G

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "renders")

# lineup: the SSBN is 170 m, so it sets the frame; it lies along X (yaw 90)
# behind the two land units.
G.reset(); G.sun(); G.ground(size=520)
G.place("str_e3_us_ssbn", 1, 0, 62, 96)
G.place("str_e2_us_silo", 1, -46, -18, 12)
G.place("str_e5_us_tel", 1, 34, -22, -24)
G.camera((0, -215, 150), (0, 6, 2.0), lens=44)
G.render(os.path.join(OUT, "strategic.png"), 1800, 950)

# close pair, LOD0: does the concrete read as concrete and the canister as a
# banded vehicle at the zoomed-in RTS distance?
G.reset(); G.sun(elev=38, azim=125); G.ground(size=140)
G.place("str_e2_us_silo", 0, -20.0, 6.0, 18)
G.place("str_e5_us_tel", 0, 13.0, -6.0, -30)
G.camera((0, -78, 40), (0, 0, 1.2), lens=52)
G.render(os.path.join(OUT, "strategic_close.png"), 1800, 850)
print("done")
