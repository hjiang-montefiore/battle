"""Render the soviet/chinese naval variants NEXT TO the US hulls they must
not be mistaken for. Same bands, cameras and sea as tools/navy_render.py —
this file only chooses different line-ups, so a read that fails here fails
for the reason the roster note claims and not because of a different camera.

    Blender -b --python tools/red_fleet_render.py

Line-ups (the comparison IS the test):
    escorts   Burke | Sovremenny | 052D      three 155 m AAW destroyers
    subs      Type 209 | Kilo | 688i         the diesel-boat separation
"""
import os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import navy_render as N

ESCORT = [("nav_e4_us_destroyer", "BURKE 155m"),
          ("nav_e3_ru_sovremenny", "SOVREMENNY 156m"),
          ("nav_e6_cn_052d", "052D 157m")]
SUBS = [("sub_e1_us_diesel", "TYPE 209 62m"),
        ("sub_e2_ru_kilo", "KILO 73m"),
        ("sub_e2_us_nuclear", "688i 110m")]

if __name__ == "__main__":
    os.makedirs(N.OUT, exist_ok=True)
    print("rendering red fleet...")
    N.band(ESCORT, "red_fleet_escort.png", 78.0, (40, -330, 195), (0, 0, 6),
           40, 1900, 760)
    N.band(SUBS, "red_fleet_subs.png", 46.0, (25, -215, 118), (0, 0, 2),
           42, 1900, 720)
    N.plan(ESCORT, "red_fleet_plan_escort.png", 25.0, 200.0, 1900, 110)
    N.plan(SUBS, "red_fleet_plan_subs.png", 23.0, 125.0, 1900, 120)
    print("done ->", N.OUT)
