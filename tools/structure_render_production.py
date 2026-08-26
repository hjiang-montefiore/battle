"""Production-group structure audit: barracks, light/heavy factory, research
facility, repair depot - plus three controls from the other groups.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/structure_render_production.py

tools/structure_render.py renders the whole roster in one frame, which is the
right sheet for checking that nineteen buildings look like one game. This is
the other test, and the one the production group actually needs: three of these
five are sheds that things come out of, a player who picks the wrong one has
lost a build cycle, and the question is not "do they look like a set" but "at
the size on screen, are these two the same picture".

So it renders the same layout three ways:

  structures_production.png       the 52 deg gameplay camera at 205 m, which is
                                  what says "building, not vehicle" - the apron
                                  collar, vertical walls, external stairs, and
                                  no shadow gap underneath.
  structures_production_plan.png  straight down at 6 px/m, for reading a plan
                                  and confirming what each roof actually owns.
  structures_production_48.png    straight down at 2.4 px/m, so a 20 m building
                                  is 48 px across. This is the only view whose
                                  verdict counts. The first pass of this sheet
                                  is what caught barracks and light_factory
                                  being one picture at two sizes, which is why
                                  light_factory's ribs now run the other way.

Row 1 carries hq, supply_depot and power_plant as CONTROLS - a role from each
of the other groups - so the sheet also tests the five against the roster they
have to live in rather than only against each other.
"""
import bpy, glob, math, os, sys
from mathutils import Matrix
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gameplay_render as G

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "art", "renders")

GRID = [["bld_e4_us_barracks", "bld_e4_us_light_factory",
         "bld_e4_us_heavy_factory", "bld_e4_us_research_facility"],
        ["bld_e4_us_repair_depot", "bld_e4_us_hq",
         "bld_e4_us_supply_depot", "bld_e4_us_power_plant"]]
PITCH = 32.0                      # > the largest cell here (26 m) plus a lane
PX_PER_M_PLAN = 6.0
PX_PER_M_AUDIT = 2.4              # a 20 m building is 48 px across
LOD = 1                           # LOD1 is what the RTS camera renders


def place(name, x, y, yaw=0.0, lod=LOD):
    f = glob.glob(os.path.join(ROOT, "art", "blockout", "**",
                               f"{name}_LOD{lod}.glb"), recursive=True)
    if not f:
        print("MISSING", name)
        return
    before = set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=f[0])
    new = [o for o in bpy.data.objects if o not in before]
    M = Matrix.Translation((x, y, 0)) @ Matrix.Rotation(math.radians(yaw), 4, "Z")
    for o in new:
        if o.parent is None:
            o.matrix_world = M @ o.matrix_world
        if o.type == "EMPTY":
            o.hide_render = True
    G.apply_occlusion([o for o in new if o.type == "MESH"])


def layout():
    """Every cell on the same pitch, plus three M1 blockouts for absolute
    scale - a building that reads as a building next to a tank it dwarfs is
    the only scale check worth having."""
    for r, row in enumerate(GRID):
        y = (len(GRID) - 1) * PITCH / 2 - r * PITCH
        for c, n in enumerate(row):
            place(n, (c - (len(row) - 1) / 2.0) * PITCH, y)
    for i in range(3):
        place("mbt_e4_us_m1_abrams", -60.0 + i * 5.0, -46.0, 14 + i * 6)


def scene():
    G.reset()
    G.sun()
    G.ground(size=420)
    layout()


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    W = len(GRID[0]) * PITCH + 12.0
    H = len(GRID) * PITCH + 24.0

    scene()
    d, e = 205.0, math.radians(52.0)          # the game's camera elevation
    G.camera((0, -d * math.cos(e), d * math.sin(e)), (0, 2.0, 4.0), lens=50)
    G.render(os.path.join(OUT, "structures_production.png"), 1900, 1050)

    scene()
    G.camera((0, 0, 200), (0, 0, 0), ortho=W)
    G.render(os.path.join(OUT, "structures_production_plan.png"),
             int(W * PX_PER_M_PLAN), int(H * PX_PER_M_PLAN))

    scene()
    G.camera((0, 0, 200), (0, 0, 0), ortho=W)
    G.render(os.path.join(OUT, "structures_production_48.png"),
             int(W * PX_PER_M_AUDIT), int(H * PX_PER_M_AUDIT), samples=64)
    print("done ->", OUT)
