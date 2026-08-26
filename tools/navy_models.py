"""The naval roster from docs/12-unit-roster.md.

    Blender -b --python tools/navy_models.py
    python3 tools/build_all.py --module navy_models --jobs 3

Ships are seen from almost directly above in an RTS, so the DECK PLANFORM and
the stepped superstructure carry the identification — hull form below the
waterline is invisible on a surface ship and is not modelled.

────────────────────────────────────────────────────────────────────────────
CONVENTIONS — read these before adding anything
────────────────────────────────────────────────────────────────────────────
BOW IS +Y.  This is the opposite of tools/army_models.py and hero_models.py,
    where a vehicle's nose is at -Y. hero_models.barrel() therefore points the
    WRONG WAY for a ship and must not be used here; gun_mount() below builds
    its own tube and takes an `aft` flag for the stern mount.

WATERLINE IS z = 0, and it means the same thing for every hull in the file:
    the sea surface. Two different things follow from it.

      Surface ships   float with the deck `freeboard` metres above z = 0 and
                      nothing at all is modelled below z = 0. A surface hull's
                      bounding box therefore starts at exactly 0.00.
      Submarines      are bodies of revolution whose axis sits BELOW the sea.
                      sub_hull() is given the SURFACED FREEBOARD — how much of
                      the round hull stands proud amidships — and puts the axis
                      at z = freeboard - B/2, so the crown is at +freeboard and
                      the modelled section reaches freeboard - B. Everything
                      below z = 0 IS modelled, because the shape of the visible
                      strip comes from the round hull and because submerging is
                      then a translation in z, not a different model.

    TWO BUGS, BOTH MEASURED, BOTH FIXED HERE.

      Pass 1 put the axis at z = +B/2, so the whole pressure hull, both stern
      planes and the propeller sat in the AIR. The nuclear boat rode 9.15 m
      high and read as a torpedo lying on the sea.

      Pass 2 over-corrected: it drove the axis from the PUBLISHED DRAUGHT, as
      z = B/2 - draught. That is wrong because a submarine's published draught
      is keel-to-waterline INCLUDING the sonar dome, ballast keel and lower
      fairings that hang below the circular pressure-hull section — structure
      this file does not model at all. Feeding it to a bare cylinder buries the
      cylinder. Measured on the render: the SSN showed a strip of hull 5.13 m
      wide with a 4.65 m casing plank laid on top of it, i.e. 0.24 m of hull
      visible either side, and it read as a raft, not a boat.

      So freeboard is now stated per boat from the surfaced photographs and the
      published draught stays as documentation in each boat's docstring. The
      keel of the modelled section then sits 0.2-1.2 m shallower than the
      published draught, and that gap IS the unmodelled keel structure:

          SSN     freeboard 1.90  hull shows 7.89 m  keel -8.20  (draught 9.4)
          SSK     freeboard 1.20  hull shows 4.90 m  keel -5.00  (draught 5.5)
          AIP     freeboard 1.30  hull shows 5.44 m  keel -5.70  (draught 6.0)
          midget  freeboard 0.80  hull shows 3.10 m  keel -3.00  (draught 3.2)

    The one deliberate exception is the LCAC, which is an air-cushion vehicle:
    on cushion it genuinely does sit ON the water, skirt at z = 0.

MATERIAL GROUPS — measured on the actual render, not assumed. The body camo
    (air_dark) is a DARK blue-grey; the flat groups read LIGHTER than it:

      body      hull sides, superstructure, masts, funnels     dark grey camo
      deck      weather decks, VLS coamings, radomes, boats    LIGHT warm grey
      gun       turrets, barrels, CIWS mounts, tubes           light grey
      gunbore   VLS cell mouths, flight-deck squares, door
                and well-dock openings, recesses               NEAR BLACK
      glass     bridge windows                                 dark blue gloss
      team      ownership patch, one per ship, flat on deck    faction blue
      era       not used at sea

    So the read from overhead is: light deck, dark blocks stepping up off it,
    black holes punched in the deck, one blue patch. Use `with mat("deck"):`
    rather than bare use() — a builder that forgets to switch back to "body"
    silently recolours everything built after it.

────────────────────────────────────────────────────────────────────────────
WHAT DETAIL COSTS — MEASURED, AND NOT WHAT YOU WOULD GUESS
────────────────────────────────────────────────────────────────────────────
COST IS OBJECT COUNT, NOT SIZE. The LOD0 bevel is 3 segments on every edge
over 24 degrees, so a convex box costs about 188 triangles whether it is a
0.9 m liferaft or a 300 m hull side, and an extruded plate about 330. That
inverts the intuition completely:

      the whole 333 m carrier hull, 3 plates            996 tris
      twelve liferafts down a destroyer's deck edge   3 008 tris

so the cheap-looking clutter costs three times the ship it sits on. Budget by
counting objects. Price list at LOD0, after the bevel, measured:

      ship_hull 155 x 20 with sheer     2 056     vls 8x8, 64 cells    3 010
      ship_hull 333 x 41 carrier          996     vls 4x8, 32 cells    1 880
      superstructure, 3 tiers           1 128     gun_mount            2 140
      lattice_mast open, 4 bays         5 304     ciws                 1 500
      lattice_mast solid=True           1 732     planar_array           376
      funnel, 2 uptakes                 1 328     air_search             948
      hangar, 2 doors                     564     arm_launcher           944
      helipad                           1 136     canisters n=2          376
      boat_bay                            752     missile_tubes n=2    2 288
      kingpost                          1 040     torpedo_tubes n=3    1 428
      gantry                            1 040     breakwater             376
      clutter, one escort               ~3 000     team_patch             188
      sub_hull SSN                      3 420     sail, 3 masts        1 892
      stern_planes, either style          752     propulsor screw      1 888
      casing                              188     propulsor pumpjet      856

      railing(), 100 m of run          12 784  <- see the note at the bottom

Two of those are the whole story. An OPEN lattice_mast costs three times a
solid one because it is 27 separate members; pass solid=True unless the ship
is pre-1980. And vls() was 12 220 for a 64-cell farm until it was rebuilt as a
slab with ribs — see the note on vls() itself.

TRIANGLE BUDGET at LOD0, and the headroom actually left, measured on the
current build. The capitals are the ships with room; the escorts are the ships
that are tight, which is the opposite of how it looks:

      carrier      40 000    20 848    +19 152 of headroom
      amphib       40 000    20 504    +19 496
      oiler        40 000    21 260    +18 740
      destroyer    32 000    30 632     +1 368
      cruiser      44 000    41 232     +2 768   two 64-cell farms and two masts
      frigate      28 000    26 116     +1 884
      missileboat  18 000    17 276       +724
      minehunter   18 000    16 604     +1 396
      corvette     16 000    13 560     +2 440
      patrol       14 000    11 416     +2 584
      LCAC         12 000     7 308     +4 692
      SSN          16 000    15 224       +776
      SSK          10 000     8 896     +1 104
      AIP          10 000     7 296     +2 704
      midget        9 000     8 412       +588

The escort ceilings were raised from a flat 26 000 because that number was
guessed in the first pass and the ships had already blown through it — the
cruiser measured 60 216 before vls() and ciws() were repriced. They are now
set just above what each hull costs today, so an addition has to be paid for
by a saving. If you need more than the headroom above, the money is in
lattice_mast(solid=True) and in deleting clutter, not in shaving cylinders.

────────────────────────────────────────────────────────────────────────────
ONE EXCLUSIVE IDENTIFYING FEATURE PER SHIP
────────────────────────────────────────────────────────────────────────────
Every hull is grey and most of them are 100–170 m long, so silhouette alone
will not carry fifteen roles. Each ship owns ONE feature that no other ship in
the roster is allowed to have, chosen to read from directly overhead:

  destroyer     FOUR canted planar arrays clustered on one pyramidal forward
                deckhouse, plus twin centreline funnels
  cruiser       a 5-inch turret at BOTH ends — the only stern main gun afloat
                here — carried by twin fore-and-aft superstructure islands
  frigate       a single trainable arm launcher on the forecastle and NO VLS
                anywhere; its gun sits on the deckhouse ROOF amidships
  corvette      two inclined box canister packs amidships, athwartships
  missile boat  four heavy cylindrical AShM tubes on the deck EDGE, angled
                outboard and overhanging the side
  patrol        a notched transom with a stern boat ramp and a RHIB in it
  carrier       the angled flight deck, four catapult tracks, four deck-edge
                lifts
  amphib        a full-length rectangular deck with painted landing spots and
                an open stern well-dock gate
  oiler         a row of four replenishment kingposts with spanwire booms
  minehunter    a stern A-frame gantry with the sweep sled sitting under it
  LCAC          four ducted lift-fan shrouds on the after deck
  SSK           the raised snorkel induction and exhaust masts abaft the sail
  SSN           twelve vertical-launch tube caps in the bow casing
  AIP           an X-form stern — four canted planes, no cruciform rudder
  midget        two external stores cradles clamped to the casing beside the
                sail

────────────────────────────────────────────────────────────────────────────
EVERY HULL IS PINNED TO A NAMED REAL CLASS
────────────────────────────────────────────────────────────────────────────
    destroyer     Arleigh Burke Flight IIA   155.3 x 20.1 m, draught 9.4 m
    cruiser       Ticonderoga CG-52          172.8 x 16.8 m, draught 10.2 m
    frigate       Oliver Hazard Perry FFG-7  138.1 x 13.7 m, draught  6.7 m
    corvette      Braunschweig K130           89.1 x 13.3 m, draught  3.4 m
    missile boat  Project 1241 Tarantul III   56.1 x 10.2 m, draught  2.5 m
    patrol        Cyclone-class PC            54.6 x  7.6 m, draught  2.4 m
    carrier       Nimitz CVN-68              332.8 x 40.8 m hull, 76.8 m deck
    amphib        Wasp LHD-1                 257.3 x 32.3 m hull, 42.7 m deck
    oiler         Henry J. Kaiser T-AO-187   206.5 x 29.7 m, draught 10.7 m
    minehunter    Avenger MCM-1               68.3 x 11.9 m, draught  3.7 m
    LCAC          LCAC-1                      26.8 x 14.3 m on cushion
    SSK           Type 209/1400               62.0 x  6.2 m, freeboard 1.20 m
    SSN           Los Angeles 688i           110.3 x 10.1 m, freeboard 1.90 m
    AIP           Type 212A                   57.2 x  7.0 m, freeboard 1.30 m
    midget        Sang-O                      34.0 x  3.8 m, freeboard 0.80 m

Freeboard is quoted amidships to the weather deck; the forecastle carries an
extra `sheer` on top of it, which is why the bow deck of every escort stands
higher than its waist. For a surface ship the draught is pure documentation —
nothing below the waterline is built. For a submarine the SURFACED FREEBOARD is
the load-bearing number and the published draught is the documentation, which
is the reverse of what pass 2 assumed.
"""
import bpy, contextlib, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_models as H
from hero_models import cube, cyl, dome, profile, use, R
from air_models import plate
from army_models import _strut as strut
from strategic_models import revolve

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

WATERLINE = 0.0


@contextlib.contextmanager
def mat(group):
    """Switch material group for a block and put it back afterwards.

    hero_models.use() is a global; every builder in the old file ended with a
    bare use("body") and one missed call silently recolours the rest of the
    ship. This cannot be got wrong."""
    prev = H.CURRENT
    use(group)
    try:
        yield
    finally:
        use(prev)


# ══ hull ═══════════════════════════════════════════════════════════
def hull_planform(L, B, bow=0.30, transom=0.86, w=1.0):
    """The deck outline as (x, y) points, bow at +Y, ready for plate().

    Shared so that a flight deck, a work deck, a bulwark and the hull itself
    are all cut from the same curve instead of three hand-typed polygons that
    disagree at the bow. `bow` is the fraction of length taken by the entry,
    `transom` the stern width as a fraction of beam, `w` a width scale.
    """
    hb = B * 0.5 * w
    entry = [(hb * (t ** 0.62), L * (0.50 - bow * t))
             for t in (0.0, 0.30, 0.55, 0.78, 1.0)]
    side = entry + [(hb, -L * 0.400), (hb * 0.99, -L * 0.455),
                    (hb * transom, -L * 0.500)]
    return side + [(-x, y) for (x, y) in reversed(side) if x > 1e-9]


def weather_deck(L, B, z, bow=0.30, transom=0.86, w=0.94, group="deck",
                 name="wdeck"):
    """The flat deck surface itself, as a separate material.

    Rule 2 of the brief: the deck is the read. A light deck inside a dark hull
    outline is what turns a grey lozenge into a ship at 60 px."""
    with mat(group):
        return plate(hull_planform(L, B, bow, transom, w), 0.22, z + 0.11, name)


def ship_hull(L, B, freeboard=4.0, bow=0.30, transom=0.86, sheer=0.0,
              deck=True, name="hull"):
    """Surface hull: stacked planform plates from the deck down to z = 0.

    Returns (parts, freeboard) — freeboard is the weather-deck height amidships
    and is what everything else on the ship is placed off. `sheer` raises a
    forecastle over the forward third; the raised deck is at freeboard + sheer
    and is returned to nobody, because nothing is placed on it but the anchor
    gear and the forward gun, which take it as an argument.
    """
    out = []
    use("body")
    layers = ((0.00, 1.000), (0.42, 0.965), (0.76, 0.875), (1.00, 0.720))
    for i in range(len(layers) - 1):
        (f0, w0), (f1, _) = layers[i], layers[i + 1]
        z0, z1 = freeboard * (1.0 - f0), freeboard * (1.0 - f1)
        out.append(plate(hull_planform(L, B, bow, transom, w0),
                         max(z0 - z1, 0.15), (z0 + z1) / 2.0, f"{name}{i}"))
    if deck:
        out.append(weather_deck(L, B, freeboard, bow, transom))
    if sheer > 0.0:
        pts = hull_planform(L, B, bow, transom, 0.985)
        fc = [(x, y) for (x, y) in pts if y > L * 0.045]
        fc = ([(fc[0][0], L * 0.045)] + fc + [(fc[-1][0], L * 0.045)])
        out.append(plate(fc, sheer, freeboard + sheer / 2.0, f"{name}_fc"))
        with mat("deck"):
            out.append(plate([(x * 0.94, y) for (x, y) in fc], 0.22,
                             freeboard + sheer + 0.11, f"{name}_fcd"))
    use("body")
    return out, freeboard


def ship_meta(L, B, deck_z, mast_top, gun_y=0.0, gun_z=None):
    """The dict hero_models.sockets_for() wants. Ships have no turret ring and
    no tracks; `turret_top` is read as the masthead and `top` as the deck."""
    return dict(top=deck_z, hull_l=L, hull_w=B, turret_top=mast_top,
                gun_z=deck_z + 1.8 if gun_z is None else gun_z, gun_y=gun_y)


def team_patch(y, z, w=4.2, l=5.0, x=0.0):
    """One flat ownership patch per ship, on a horizontal surface, visible
    from directly above. CONVENTIONS.md requires it."""
    with mat("team"):
        return cube((x, y, z + 0.14), (w, l, 0.16))


# ══ superstructure ═════════════════════════════════════════════════
def deckhouse(y, l, w, h, z, taper=0.86, name="dh", x=0.0):
    o = profile([(y + l / 2, z), (y - l / 2, z),
                 (y - l / 2 * taper, z + h), (y + l / 2 * taper, z + h)],
                w, name)
    o.location.x = x
    return o


def superstructure(y, z, levels, taper=0.90, glass=True, x=0.0, name="sup"):
    """A deckhouse that STEPS UP in tiers, and returns the height it reached.

    Rule 1 of the brief: the stepped profile is the strongest "this is a
    warship" cue and it survives any zoom. A warship goes forecastle → main
    house → 01 level → bridge → mast in three or four steps, each shorter and
    narrower than the one below and usually set back from its front.

        levels = ((length, width, height), ...) from the main deck upward,
                 or (length, width, height, dy) to shift that tier fore(+) or
                 aft(-) of `y`.

    Returns (parts, top_z) so the mast, funnel and director above are placed
    off the returned number instead of a hand-added stack of magic constants
    that drifts the moment a tier height changes.
    """
    out, zc = [], z
    top_l = top_w = top_dy = 0.0
    for i, lv in enumerate(levels):
        l, w, h = lv[0], lv[1], lv[2]
        dy = lv[3] if len(lv) > 3 else 0.0
        use("body")
        out.append(deckhouse(y + dy, l, w, h, zc, taper, f"{name}{i}", x))
        top_l, top_w, top_dy = l, w, dy
        zc += h
    if glass and levels:
        # bridge windows wrap the front and the forward quarter of each side
        yf = y + top_dy + top_l * 0.5 * (1.0 + taper) * 0.5
        zw = zc - top_l * 0.0 - (levels[-1][2] * 0.42)
        with mat("glass"):
            out.append(cube((x, yf - 0.10, zw), (top_w * 0.80, 0.34,
                                                 levels[-1][2] * 0.34)))
            for s in (-1, 1):
                out.append(cube((x + s * (top_w * 0.5 - 0.12),
                                 yf - top_l * 0.20, zw),
                                (0.30, top_l * 0.30, levels[-1][2] * 0.30)))
    use("body")
    return out, zc


def lattice_mast(x, y, z, h, foot=2.6, head=1.0, bays=4,
                 yards=((0.58, 8.0), (0.82, 5.2)), radome=0.0, platform=0.0,
                 solid=False, name="mast"):
    """Rule 3: a stick mast reads as a barge. This is four raked legs with
    horizontal bracing at every bay, yardarms, an optional platform and an
    optional radome on the head.

        yards = ((height fraction, full span in metres), ...)
        solid = True builds a plated pyramid mast instead of an open lattice,
                which is what a post-1990 ship carries.
    """
    out = []
    use("body")
    if solid:
        out.append(cyl((x, y, z + h / 2.0), foot * 0.72, h, rot=(0, 0, R(45)),
                       v=4, taper=max(head / foot, 0.05)))
    else:
        t = max(foot * 0.11, 0.16)
        for sx in (-1, 1):
            for sy in (-1, 1):
                out.append(strut((x + sx * foot / 2, y + sy * foot / 2, z),
                                 (x + sx * head / 2, y + sy * head / 2, z + h),
                                 t))
        for k in range(1, bays + 1):
            f = k / float(bays)
            s = foot + (head - foot) * f
            zz = z + h * f
            for sy in (-1, 1):
                out.append(cube((x, y + sy * s / 2, zz), (s, t, t)))
            for sx in (-1, 1):
                out.append(cube((x + sx * s / 2, y, zz), (t, s, t)))
    for f, span in yards:
        out.append(cube((x, y, z + h * f), (span, foot * 0.34, foot * 0.24)))
        for s in (-1, 1):
            out.append(cube((x + s * span * 0.46, y, z + h * f + 0.34),
                            (foot * 0.20, foot * 0.20, 0.68)))
    if platform > 0.0:
        with mat("deck"):
            out.append(cyl((x, y, z + h * 0.46), platform, 0.20, v=8))
    if radome > 0.0:
        with mat("deck"):
            out.append(dome((x, y, z + h + radome * 0.35),
                            radome, radome, radome * 1.10, v=16))
    use("body")
    return out


def mast(x, y, z, h, r=0.28):
    """Legacy signature kept so nothing breaks; it is a lattice now."""
    return lattice_mast(x, y, z, h, foot=r * 7.0, head=r * 2.6, bays=3,
                        yards=((0.52, r * 20), (0.78, r * 13)))


def funnel(x, y, z, l, w, h, rake=10.0, uptakes=2, cap=True, name="fnl"):
    """A raked funnel with a dark cap and uptake pipes.

    Rule 3 again: a warship without a funnel reads as a ferry, and the funnel
    is the one top-silhouette break that survives being seen from directly
    overhead because the cap is a dark rectangle on a light deck.
    """
    out = []
    dy = h * math.tan(R(rake))
    use("body")
    o = profile([(y + l / 2, z), (y - l / 2, z),
                 (y - l / 2 - dy, z + h), (y + l / 2 * 0.84 - dy, z + h)],
                w, name)
    o.location.x = x
    out.append(o)
    if cap:
        with mat("gunbore"):
            out.append(cube((x, y - dy - l * 0.06, z + h - 0.05),
                            (w * 0.90, l * 0.80, 0.30)))
    with mat("gun"):
        for k in range(uptakes):
            ox = 0.0 if uptakes == 1 else (k - (uptakes - 1) / 2.0) * w * 0.34
            out.append(cyl((x + ox, y - dy - l * 0.06, z + h + 0.35),
                           w * 0.13, 1.10, v=10))
    use("body")
    return out


# ══ weapons and sensors ════════════════════════════════════════════
def vls(x, y, z, cols, rows, cell=1.05, name="vls"):
    """Vertical launch cells: a light coaming, ONE black cell field, and the
    grid drawn on it as light ribs.

    From overhead this is the single most legible thing on a modern warship —
    a regular dark grid on a light deck — and it is the reason the destroyer
    and the cruiser cannot be mistaken for the frigate, which has none.

    BUILT INSIDE OUT FROM PASS 1, FOR TWO MEASURED REASONS.

      Cost. Pass 1 built one bevelled box per cell. A 64-cell farm came to
      12 220 triangles after the LOD0 bevel — more than the whole carrier hull
      and superstructure together — and the cruiser carries two of them, which
      is 41% of that ship's entire budget spent on a flat rectangle. Slab plus
      (cols-1)+(rows-1) ribs draws the same pattern for about 3 000.

      Read. 64 separated dark squares average out to mid-grey the moment the
      cells stop resolving, and the ship's `body` camo is a fine checker that
      is already competing at that frequency. A solid dark field survives all
      the way down and simply gets cleaner as the ribs drop out, which is the
      behaviour you want from the feature that separates two grey escorts.
    """
    out = []
    W, D = cols * cell, rows * cell
    with mat("deck"):                                   # coaming
        out.append(cube((x, y, z + 0.17), (W + 0.9, D + 0.9, 0.34)))
    with mat("gunbore"):                                # the cell field
        out.append(cube((x, y, z + 0.40), (W, D, 0.24)))
    with mat("deck"):                                   # the grid, as ribs
        t = cell * 0.22
        for c in range(1, cols):
            out.append(cube((x - W / 2.0 + c * cell, y, z + 0.50), (t, D, 0.12)))
        for r_ in range(1, rows):
            out.append(cube((x, y - D / 2.0 + r_ * cell, z + 0.50), (W, t, 0.12)))
    return out


def gun_mount(y, z, r=2.0, barrel_l=6.4, barrel_r=0.28, x=0.0, aft=False,
              name="gun"):
    """A faceted gunhouse with a tube, pointing over the bow (or the stern).

    hero_models.barrel() cannot be used: it builds a tank barrel running toward
    -Y, and a ship's bow is +Y.
    """
    out = []
    s = -1.0 if aft else 1.0
    h = r * 1.30
    with mat("gun"):
        out.append(cyl((x, y, z + 0.22), r * 1.05, 0.44, v=18))     # barbette
        o = profile([(y + s * r * 1.30, z + 0.40), (y - s * r * 1.15, z + 0.40),
                     (y - s * r * 1.00, z + h), (y + s * r * 0.25, z + h),
                     (y + s * r * 1.24, z + h * 0.52)], r * 1.55, name)
        o.location.x = x
        out.append(o)
        ymuz = y + s * (r * 1.24 + barrel_l)
        out.append(cyl((x, y + s * (r * 1.24 + barrel_l / 2), z + h * 0.62),
                       barrel_r, barrel_l, rot=(R(90), 0, 0), v=12))
        out.append(cyl((x, y + s * (r * 1.24 + barrel_l * 0.16), z + h * 0.62),
                       barrel_r * 1.9, barrel_l * 0.30, rot=(R(90), 0, 0), v=12))
    with mat("gunbore"):
        out.append(cyl((x, ymuz, z + h * 0.62), barrel_r * 0.55, 0.14,
                       rot=(R(90), 0, 0), v=10))
    return out


def ciws(x, y, z, r=1.05, elev=22.0, aft=False, name="ciws"):
    """Close-in weapon: dark drum, LIGHT radome, short gatling cluster.

    Tiny, but the light radome is a bright dot at the corners of the
    superstructure where the eye already goes, and it is a rung on the
    docs/02 section 8.6 ladder, so it is gameplay rather than decoration.
    """
    out = []
    s = -1.0 if aft else 1.0
    # v is deliberately low: this is a 2 m object that every escort carries two
    # of and the carrier three. At v=14 it cost 2 540 triangles after the LOD0
    # bevel, as much as a whole three-tier superstructure, for a shape that is
    # four pixels across. v=8/10 is visually identical at the game camera.
    with mat("gun"):
        out.append(cyl((x, y, z + 0.35), r * 0.95, 0.70, v=8))
        out.append(cyl((x, y, z + 1.30), r * 0.78, 1.30, v=8))
    with mat("deck"):
        out.append(dome((x, y, z + 2.05), r * 0.92, r * 0.92, r * 1.20, v=10))
    with mat("gunbore"):
        out.append(cyl((x, y + s * r * 1.05, z + 1.55), r * 0.30, r * 2.0,
                       rot=(R(90 - elev), 0, 0), v=8))
    return out


def arm_launcher(x, y, z, elev=18.0, arm=6.2, name="arm"):
    """A single trainable rail arm on a magazine drum — the Mk13.

    The frigate's exclusive feature. Nothing else in the roster has a moving
    launcher arm, and from overhead it is a bar sticking out of a circle.
    """
    out = []
    with mat("deck"):
        out.append(cyl((x, y, z + 0.30), 2.30, 0.60, v=20))          # magazine
    with mat("gun"):
        out.append(cyl((x, y, z + 1.05), 1.35, 1.00, v=16))          # trunnion
        out.append(cube((x, y + arm * 0.40, z + 1.05 + arm * 0.40 * math.tan(R(elev))),
                        (0.62, arm, 0.52), rot=(R(-elev), 0, 0)))
        out.append(cube((x, y + arm * 0.78, z + 1.05 + arm * 0.78 * math.tan(R(elev))),
                        (0.86, 0.40, 0.86), rot=(R(-elev), 0, 0)))
    return out


def canisters(x, y, z, n=4, l=6.4, w=1.55, h=1.55, elev=15.0, yaw=0.0,
              pitch_rows=1, name="can"):
    """A pack of boxed anti-ship missile canisters, inclined and trained out.
    The corvette's exclusive feature when used as two athwartships packs."""
    out = []
    with mat("gun"):
        for row in range(pitch_rows):
            for k in range(n):
                ox = (k - (n - 1) / 2.0) * (w * 1.10)
                out.append(cube((x + ox, y, z + h * (0.5 + row) +
                                 l * 0.5 * math.tan(R(elev))),
                                (w, l, h), rot=(R(-elev), 0, R(yaw))))
    return out


def missile_tubes(x, y, z, n=2, l=7.2, r=0.86, elev=12.0, yaw=0.0, name="tube"):
    """Heavy CYLINDRICAL launch tubes — Termit/Styx scale. Deliberately not
    the same shape as canisters(): the missile boat owns the round tube and
    the corvette owns the box, so the two never read alike from above."""
    out = []
    with mat("gun"):
        for k in range(n):
            oy = y - k * (r * 2.6)
            out.append(cyl((x, oy, z + l * 0.5 * math.tan(R(elev))), r, l,
                           rot=(R(90 - elev), 0, R(yaw)), v=12))
    with mat("gunbore"):
        for k in range(n):
            oy = y - k * (r * 2.6)
            out.append(cyl((x + math.sin(R(yaw)) * l * 0.5,
                            oy + math.cos(R(yaw)) * l * 0.50,
                            z + l * 0.5 * math.tan(R(elev)) + l * 0.5 * math.sin(R(elev))),
                           r * 0.80, 0.18, rot=(R(90 - elev), 0, R(yaw)), v=12))
    return out


def torpedo_tubes(x, y, z, n=3, l=6.6, r=0.36, yaw=45.0, name="tt"):
    """Triple ASW tubes trained outboard. docs/02 section 8.5 gear."""
    out = []
    with mat("gun"):
        for k in range(n):
            out.append(cyl((x + k * r * 2.3 * math.cos(R(yaw)),
                            y - k * r * 2.3 * math.sin(R(yaw)), z + r),
                           r, l, rot=(R(90), 0, R(yaw)), v=10))
    return out


def planar_array(x, y, z, w=4.6, h=4.4, cant=28.0, yaw=0.0, name="spy"):
    """A fixed phased-array face: dark radiating face in a body-coloured
    frame, canted outboard. Four of these on one deckhouse is the destroyer's
    exclusive; two split fore and aft is the cruiser's."""
    out = []
    use("body")
    out.append(cube((x, y, z), (0.55, w, h), rot=(R(cant), 0, R(yaw))))
    with mat("gunbore"):
        out.append(cube((x + 0.30 * math.cos(R(yaw)), y - 0.30 * math.sin(R(yaw)), z),
                        (0.18, w * 0.80, h * 0.80), rot=(R(cant), 0, R(yaw))))
    use("body")
    return out


def air_search(x, y, z, w=6.4, h=2.6, tilt=14.0, name="as"):
    """A rotating air-search slab on a pedestal — the pre-phased-array answer,
    and what the frigate, corvette and auxiliaries carry instead."""
    out = []
    with mat("gun"):
        out.append(cyl((x, y, z + 0.45), 0.80, 0.90, v=12))
        out.append(cube((x, y, z + 1.20 + h * 0.45), (w, 0.44, h),
                        rot=(R(tilt), 0, 0)))
        out.append(cube((x, y - 0.30, z + 1.20), (w * 0.30, 0.34, 0.60)))
    return out


def radome(x, y, z, r, name="rdm"):
    with mat("deck"):
        return [cyl((x, y, z + r * 0.18), r * 0.72, r * 0.36, v=14),
                dome((x, y, z + r * 0.34), r, r, r * 0.94, v=16)]


# ══ decks, aviation, boats, working gear ═══════════════════════════
def helipad(y, w, l, z, x=0.0, name="pad"):
    """Landing spot: BLACK deck square, light circle and lead-in line.

    Reversed from the first pass, which painted it light on a dark hull. A
    flight deck is the darkest thing on a real ship and the marking circle is
    the lightest, and that pairing survives to the smallest zoom.
    """
    out = []
    with mat("gunbore"):
        out.append(cube((x, y, z + 0.14), (w, l, 0.28)))
    with mat("deck"):
        out.append(cyl((x, y, z + 0.30), w * 0.32, 0.10, v=24))
    with mat("gunbore"):
        out.append(cyl((x, y, z + 0.37), w * 0.25, 0.10, v=24))
    with mat("deck"):
        out.append(cube((x, y + l * 0.34, z + 0.30), (0.55, l * 0.26, 0.10)))
    return out


def hangar(y, l, w, h, z, doors=1, taper=0.94, x=0.0, name="hgr"):
    """Helicopter hangar with the door opening cut dark into the after face.
    docs/02 section 8.5: the embarked helicopter is an ASW sensor, so the
    hangar is a gameplay statement about what the ship can do."""
    out = [deckhouse(y, l, w, h, z, taper, name, x)]
    with mat("gunbore"):
        for k in range(doors):
            ox = 0.0 if doors == 1 else (k - (doors - 1) / 2.0) * w * 0.46
            out.append(cube((x + ox, y - l * 0.5 - 0.05, z + h * 0.42),
                            (w * (0.72 if doors == 1 else 0.40), 0.34, h * 0.74)))
    use("body")
    return out


def boat_bay(x, y, z, l=7.6, h=2.9, boat=True, name="boat"):
    """A recess in the hull side with a RHIB and davit arms. `x` is the hull
    side, so pass +/- B/2."""
    out = []
    s = 1.0 if x > 0 else -1.0
    with mat("gunbore"):
        out.append(cube((x - s * 0.35, y, z - h * 0.38), (1.30, l, h)))
    if boat:
        with mat("deck"):
            o = profile([(y + l * 0.40, z - h * 0.55), (y - l * 0.40, z - h * 0.52),
                         (y - l * 0.36, z - h * 0.16), (y + l * 0.30, z - h * 0.10)],
                        1.55, name + "_rhib")
            o.location.x = x - s * 0.75
            out.append(o)
    with mat("gun"):
        for k in (-1, 1):
            out.append(cube((x - s * 0.30, y + k * l * 0.38, z + 0.90),
                            (0.26, 0.26, 1.80)))
    use("body")
    return out


def kingpost(x, y, z, h, boom=11.0, side=1, name="kp"):
    """A replenishment kingpost with its spanwire boom. Four of these in a row
    is the oiler's exclusive — nothing else in the fleet has a mast that is not
    on the centreline."""
    out = []
    use("body")
    out.append(cyl((x, y, z + h / 2.0), 0.85, h, v=10, taper=0.55))
    with mat("gun"):
        out.append(cube((x + side * boom * 0.5, y, z + h * 0.78),
                        (boom, 0.55, 0.55)))
        out.append(cube((x + side * boom * 0.94, y, z + h * 0.60),
                        (0.44, 0.44, h * 0.36)))
        out.append(strut((x, y, z + h * 0.34),
                         (x + side * boom * 0.86, y, z + h * 0.74), 0.26))
    use("body")
    return out


def gantry(y, z, w, h, depth=3.2, name="gan"):
    """A stern A-frame gantry, legs raked aft over the transom. The
    minehunter's exclusive."""
    out = []
    use("body")
    for s in (-1, 1):
        out.append(strut((s * w * 0.5, y + depth * 0.5, z),
                         (s * w * 0.40, y - depth * 0.5, z + h), 0.52))
    out.append(cube((0, y - depth * 0.5, z + h), (w * 0.86, 0.62, 0.62)))
    with mat("gun"):
        out.append(cyl((0, y - depth * 0.5, z + h - 0.60), 0.42, 0.90, v=10))
    use("body")
    return out


def breakwater(y, w, z, h=1.15, name="bw"):
    """The chevron across the forecastle that keeps green water off the gun.
    Cheap, and it is a hard diagonal on an otherwise empty bow, so it reads."""
    out = []
    use("body")
    for s in (-1, 1):
        out.append(cube((s * w * 0.25, y, z + h / 2.0), (w * 0.56, 0.36, h),
                        rot=(0, 0, R(s * 26))))
    return out


def clutter(pts, z, spacing=11.0, inset=1.5, size=(1.05, 2.0, 0.85),
            group="deck", name="clt"):
    """Liferaft canisters, lockers and deck boxes walked along the deck edge.

    This is the cheapest density in the file: a dozen small light boxes down
    both sides is what makes a deck look worked rather than moulded. Skips the
    bow so it never sits on the gun."""
    out = []
    with mat(group):
        for i in range(len(pts)):
            ax, ay = pts[i]
            bx, by = pts[(i + 1) % len(pts)]
            seg = math.hypot(bx - ax, by - ay)
            n = int(seg // spacing)
            if n <= 0 or abs(ax) < 0.3:
                continue
            ux, uy = (bx - ax) / seg, (by - ay) / seg
            for k in range(n):
                t = (k + 0.5) * seg / n
                px, py = ax + ux * t, ay + uy * t
                sx = -1.0 if px < 0 else 1.0
                out.append(cube((px - sx * inset, py, z + size[2] / 2.0), size,
                                rot=(0, 0, math.atan2(-(bx - ax), by - ay))))
    return out


def railing(pts, z, h=1.05, t=0.10, stanchion=3.0, name="rail"):
    """Deck-edge railings. MEASURED, NOT ASSUMED — see the note at the bottom
    of this file: at the game camera a 0.10 m rail is a third of a pixel and
    contributes nothing but triangles and shimmer, so no ship calls this. It
    is kept for close-up cinematics only."""
    out = []
    use("body")
    for i in range(len(pts)):
        ax, ay = pts[i]
        bx, by = pts[(i + 1) % len(pts)]
        seg = math.hypot(bx - ax, by - ay)
        if seg < 0.01:
            continue
        out.append(strut((ax, ay, z + h), (bx, by, z + h), t))
        n = max(int(seg // stanchion), 1)
        for k in range(n):
            f = (k + 0.5) / n
            out.append(cube((ax + (bx - ax) * f, ay + (by - ay) * f, z + h / 2),
                            (t, t, h)))
    return out


# ══ submarines ═════════════════════════════════════════════════════
SUB_STATIONS = ((0.00, 0.26), (0.03, 0.56), (0.07, 0.80), (0.13, 0.94),
                (0.20, 1.00), (0.66, 1.00), (0.78, 0.93), (0.87, 0.76),
                (0.94, 0.50), (1.00, 0.18))


def sub_axis_z(B, freeboard):
    """THE waterline rule for submarines, in one line.

    `freeboard` is how much of the round hull stands above the sea amidships
    when surfaced, so the axis goes half a beam below the crown. It is
    NEGATIVE for every real boat. Do NOT pass a published draught here — see
    the two-bug note in the module docstring; a published draught is measured
    to a keel this file does not model.
    """
    return freeboard - B / 2.0


def sub_hull(L, B, freeboard, stations=SUB_STATIONS, v=24, name="sub"):
    """Surfaced submarine hull. Returns (parts, axis_z, casing_z).

    casing_z is the crown of the hull — the deck a sail, a hatch or a launch
    tube sits on — and equals `freeboard` by construction. Geometry below
    z = 0 is intentional and the sea plane hides it; submerging the boat is a
    translation in z and not a second model.

    The number that decides whether the boat reads as a boat is how wide the
    hull shows in PLAN, which is 2*sqrt((B/2)^2 - (B/2 - freeboard)^2). It has
    to beat the width of the casing laid on top of it or the casing is all you
    see; sub_hull asserts that, because getting it wrong is invisible in code
    and obvious in the render.
    """
    assert 0.0 < freeboard < B, f"{name}: freeboard {freeboard} outside 0..B"
    use("body")
    az = sub_axis_z(B, freeboard)
    parts = revolve(L, B / 2.0, stations, z=az, v=v)
    return parts, az, az + B / 2.0


def sub_show_width(B, freeboard):
    """How wide the round hull shows in plan at the waterline. The casing must
    be narrower than this or the boat reads as a plank."""
    return 2.0 * math.sqrt(max((B / 2.0) ** 2 - (B / 2.0 - freeboard) ** 2, 0.0))


def casing(y0, y1, w, z, h=0.42, name="csg"):
    """The flat walking casing along the crown of the hull."""
    with mat("deck"):
        return [cube((0.0, (y0 + y1) / 2.0, z + h / 2.0), (w, y0 - y1, h))]


def sail(y, l, h, w, z, planes=True, masts=3, name="sail"):
    """Fin/sail with a raked leading edge, a bridge notch and raised masts."""
    out = []
    use("body")
    out.append(profile([(y, z), (y - l, z), (y - l * 0.88, z + h),
                        (y - l * 0.12, z + h)], w, name))
    with mat("gunbore"):
        out.append(cube((0.0, y - l * 0.30, z + h - 0.30), (w * 0.60, l * 0.26, 0.60)))
    with mat("gun"):
        for k in range(masts):
            out.append(cyl((0.0, y - l * 0.42 - k * l * 0.13, z + h + 1.6 - k * 0.35),
                           0.20, 3.4 - k * 0.6, v=8))
    if planes:
        # Fairwater planes, sized off the real thing. The first cut reached
        # w*2.80 from the centreline, which on the SSN is 9.05 m of plane on a
        # 10.1 m beam — in plan the boat read as a giant cross with a hull
        # somewhere underneath it. A 688's fairwater planes span about 7 m tip
        # to tip, so the tip belongs at roughly 0.36 of the beam.
        use("body")
        for s in (-1, 1):
            out.append(cube((s * w * 0.55, y - l * 0.55, z + h * 0.52),
                            (w * 1.20, l * 0.44, 0.36)))
    use("body")
    return out


def stern_planes(L, B, axis_z, style="cross", span=None, chord=None,
                 name="sp"):
    """Stern control surfaces. style="cross" is the conventional cruciform;
    style="x" is the four-canted X-form that is the AIP boat's exclusive
    feature and reads from above as a diagonal cross instead of a bar."""
    out = []
    span = span if span is not None else B * 1.55
    chord = chord if chord is not None else L * 0.055
    y = -L * 0.415
    use("body")
    if style == "x":
        for a in (45, 135, 225, 315):
            out.append(cube((math.cos(R(a)) * span * 0.30, y,
                             axis_z + math.sin(R(a)) * span * 0.30),
                            (span * 0.62, chord, 0.42), rot=(0, R(-a + 45), 0)))
    else:
        for s in (-1, 1):
            out.append(cube((s * span * 0.30, y, axis_z),
                            (span * 0.62, chord, 0.42)))
        out.append(profile([(y + chord * 0.6, axis_z), (y - chord * 0.6, axis_z),
                            (y - chord * 0.5, axis_z + B * 0.62),
                            (y + chord * 0.3, axis_z + B * 0.58)], 0.42,
                           name + "_ru"))
        out.append(profile([(y + chord * 0.6, axis_z), (y - chord * 0.6, axis_z),
                            (y - chord * 0.5, axis_z - B * 0.55),
                            (y + chord * 0.3, axis_z - B * 0.52)], 0.42,
                           name + "_rl"))
    return out


def propulsor(L, B, axis_z, kind="screw", name="prop"):
    out = []
    y = -L * 0.485
    with mat("gun"):
        if kind == "pumpjet":
            out.append(cyl((0, y, axis_z), B * 0.30, B * 0.34,
                           rot=(R(90), 0, 0), v=18))
            out.append(cyl((0, y, axis_z), B * 0.13, B * 0.40,
                           rot=(R(90), 0, 0), v=12))
        else:
            out.append(cyl((0, y, axis_z), B * 0.13, B * 0.22,
                           rot=(R(90), 0, 0), v=12, taper=0.5))
            for k in range(7):
                a = 2.0 * math.pi * k / 7.0
                out.append(cube((B * 0.26 * math.sin(a), y,
                                 axis_z + B * 0.26 * math.cos(a)),
                                (0.10, B * 0.16, B * 0.44), rot=(0, a, 0)))
    return out


# ══ surface combatants ═════════════════════════════════════════════
def destroyer_aaw():
    """Arleigh Burke Flight IIA — 155.3 x 20.1 m, draught 9.4 m, 5.9 m of
    freeboard amidships and 2.4 m of sheer to the forecastle.

    EXCLUSIVE FEATURE: four canted planar arrays on ONE pyramidal forward
    deckhouse, plus twin centreline funnels. The cruiser splits its arrays
    fore and aft and the frigate has none, so the cluster is unambiguous.

    The layered-defence ship of docs/02 section 8.6: 96 strike cells in two
    farms, two CIWS, a 5-inch mount, twin hangars and a helipad.
    """
    L, B, FB, SH = 155.3, 20.1, 5.9, 2.4
    p, fb = ship_hull(L, B, FB, bow=0.30, sheer=SH)
    sup, top = superstructure(L * 0.11, fb,
                              ((48.0, 16.8, 6.6), (32.0, 14.0, 4.8, 2.5),
                               (19.0, 10.6, 4.2, 3.6)), taper=0.92)
    p += sup
    # the four faces: two forward on the front corners, two aft on the back
    for s in (-1, 1):
        p += planar_array(s * 6.8, L * 0.205, fb + 9.6, 4.8, 4.6, 26, s * 32)
        p += planar_array(s * 6.6, L * 0.045, fb + 9.2, 4.6, 4.4, 26, -s * 148)
    p += lattice_mast(0, L * 0.015, top, 15.0, foot=4.2, head=1.4, solid=True,
                      yards=((0.42, 11.0), (0.70, 7.0)), radome=1.9)
    p += funnel(0, L * 0.005, fb + 2.6, 9.0, 7.6, 8.2, rake=8)
    p += funnel(0, -L * 0.113, fb + 2.6, 9.0, 7.6, 8.2, rake=8)
    p += vls(0, L * 0.315, fb + SH, 4, 8)              # 32 cells, forecastle
    # 64 cells aft. Measured in plan: at -0.235L the 9.3 m coaming ran from
    # -31.8 to -41.1 and the hangar from -33.6 to -59.6, so 7.6 m of the farm —
    # 82% of it — was inside the hangar and the ship's loudest overhead feature
    # did not render at all. The farm moved forward to clear the hangar and the
    # after funnel moved forward to clear the farm.
    p += vls(0, -L * 0.180, fb, 8, 8)
    p += gun_mount(L * 0.393, fb + SH, r=2.05, barrel_l=6.6)
    p += breakwater(L * 0.345, B * 0.72, fb + SH)
    p += ciws(0, L * 0.145, top - 4.2, 1.10)
    p += ciws(0, -L * 0.300, fb + 6.4, 1.10, aft=True)
    p += hangar(-L * 0.300, 26.0, 13.6, 6.4, fb, doors=2)
    p += helipad(-L * 0.425, 13.2, 20.0, fb)
    for s in (-1, 1):
        p += boat_bay(s * B * 0.47, -L * 0.045, fb)
        p += torpedo_tubes(s * B * 0.30, -L * 0.115, fb + 0.4, yaw=s * 55)
    p += clutter(hull_planform(L, B, w=0.90), fb, spacing=13.0)
    p.append(team_patch(-L * 0.175, fb, 4.4, 5.2))
    return p, ship_meta(L, B, fb, top + 15.0, gun_y=L * 0.40, gun_z=fb + SH + 2.6)


def cruiser():
    """Ticonderoga CG-52 — 172.8 x 16.8 m, draught 10.2 m, freeboard 5.6 m.

    EXCLUSIVE FEATURE: a 5-inch turret at BOTH ends. It is the only ship in
    the roster with a stern main gun, and the pair of fore-and-aft
    superstructure islands that carry its two array faces makes the hull read
    symmetric from overhead, which no other escort does.

    Longer and 3.3 m narrower than the destroyer — L/B 10.3 against 7.7 — so
    even before the armament the planform is a different animal.
    """
    L, B, FB, SH = 172.8, 16.8, 5.6, 2.2
    p, fb = ship_hull(L, B, FB, bow=0.30, transom=0.82, sheer=SH)
    fwd, ftop = superstructure(L * 0.095, fb,
                               ((44.0, 13.8, 7.0), (26.0, 11.4, 4.6, 2.0),
                                (15.0, 8.8, 4.0, 2.8)), taper=0.90)
    aft, atop = superstructure(-L * 0.185, fb,
                               ((34.0, 13.2, 6.2), (18.0, 10.0, 4.4, -1.5)),
                               taper=0.90, glass=False, name="aftsup")
    p += fwd + aft
    for s in (-1, 1):
        p += planar_array(s * 5.6, L * 0.185, fb + 9.8, 4.4, 4.2, 24, s * 30)
        p += planar_array(s * 5.4, -L * 0.245, fb + 9.0, 4.4, 4.2, 24,
                          s * 150)
    p += lattice_mast(0, L * 0.020, ftop, 16.0, foot=3.0, head=1.0, bays=4,
                      yards=((0.50, 12.0), (0.78, 7.4)), radome=1.7)
    p += lattice_mast(0, -L * 0.250, atop, 10.5, foot=2.4, head=0.9, bays=3,
                      yards=((0.58, 8.0),), name="mainmast")
    for s in (-1, 1):                                   # paired funnels
        p += funnel(s * 4.6, -L * 0.045 - s * L * 0.055, fb + 2.4, 8.6, 6.2,
                    7.8, rake=9, name=f"fnl{s}")
    p += vls(0, L * 0.305, fb + SH, 8, 8)
    p += vls(0, -L * 0.355, fb, 8, 8)
    p += gun_mount(L * 0.386, fb + SH, r=1.95, barrel_l=6.4)
    p += gun_mount(-L * 0.300, fb, r=1.95, barrel_l=6.4, aft=True)
    p += breakwater(L * 0.340, B * 0.70, fb + SH)
    p += ciws(0, L * 0.140, ftop - 4.4, 1.05)
    p += ciws(0, -L * 0.130, fb + 6.2, 1.05, aft=True)
    p += helipad(-L * 0.440, 11.6, 16.0, fb)
    for s in (-1, 1):
        p += boat_bay(s * B * 0.47, -L * 0.010, fb, l=6.8)
        p += torpedo_tubes(s * B * 0.30, -L * 0.090, fb + 0.4, yaw=s * 55)
    p += clutter(hull_planform(L, B, transom=0.82, w=0.90), fb, spacing=12.0)
    p.append(team_patch(-L * 0.100, fb, 4.0, 4.8))
    return p, ship_meta(L, B, fb, ftop + 16.0, gun_y=L * 0.39,
                        gun_z=fb + SH + 2.5)


def frigate_asw():
    """Oliver Hazard Perry FFG-7, long hull — 138.1 x 13.7 m, draught 6.7 m
    over the sonar dome, freeboard 4.6 m, sheer 2.0 m.

    EXCLUSIVE FEATURE: a single trainable arm launcher on the forecastle and
    NOT ONE VLS CELL anywhere on the ship — and its gun sits on the deckhouse
    ROOF amidships instead of on the bow. Those two facts invert the standard
    escort layout: where the destroyer and the cruiser have a turret forward
    and a cell grid behind it, this ship has an arm forward and a bare
    forecastle, and the eye lands on the empty deck.

    6.4 m narrower than the destroyer over nearly the same length, and the
    towed array plus a two-helicopter hangar are its actual weapons
    (docs/02 section 8.5).
    """
    L, B, FB, SH = 138.1, 13.7, 4.6, 2.0
    p, fb = ship_hull(L, B, FB, bow=0.32, transom=0.78, sheer=SH)
    sup, top = superstructure(-L * 0.010, fb,
                              ((52.0, 11.6, 5.8), (24.0, 9.2, 4.2, 8.0)),
                              taper=0.92)
    p += sup
    p += arm_launcher(0, L * 0.330, fb + SH)            # Mk13, the exclusive
    p += gun_mount(-L * 0.055, fb + 5.8, r=1.35, barrel_l=4.6)   # gun on the roof
    p += lattice_mast(0, -L * 0.090, top, 13.5, foot=2.6, head=0.9, bays=4,
                      yards=((0.52, 9.4), (0.80, 6.0)), radome=1.5)
    p += air_search(0, -L * 0.150, top - 4.2, 7.0, 2.8)
    p += funnel(0, -L * 0.135, fb + 2.2, 8.0, 5.6, 7.0, rake=10)
    p += ciws(0, -L * 0.365, fb + 6.0, 1.05, aft=True)
    p += hangar(-L * 0.275, 30.0, 12.2, 6.0, fb, doors=2)
    p += helipad(-L * 0.415, 12.4, 24.0, fb)
    with mat("gunbore"):                                # RAST haul-down track
        p.append(cube((0, -L * 0.415, fb + 0.30), (0.7, 22.0, 0.16)))
    with mat("deck"):                                   # towed array fairlead
        p.append(cube((0, -L * 0.487, fb + 0.5), (7.6, 4.6, 1.0)))
    for s in (-1, 1):
        p += boat_bay(s * B * 0.47, L * 0.075, fb, l=6.4)
        p += torpedo_tubes(s * B * 0.28, -L * 0.060, fb + 0.4, yaw=s * 60)
    p += breakwater(L * 0.395, B * 0.68, fb + SH)
    p += clutter(hull_planform(L, B, bow=0.32, transom=0.78, w=0.90), fb,
                 spacing=11.0)
    p.append(team_patch(L * 0.170, fb + SH, 3.6, 4.4))
    return p, ship_meta(L, B, fb, top + 13.5, gun_y=-L * 0.02, gun_z=fb + 7.4)


def corvette():
    """Braunschweig K130 — 89.1 x 13.3 m, draught 3.4 m, freeboard 3.9 m.

    EXCLUSIVE FEATURE: two inclined box canister packs sitting athwartships
    amidships. Small, fast, cheap: anti-ship missiles and not much else.
    """
    L, B, FB, SH = 89.1, 13.3, 3.9, 1.5
    p, fb = ship_hull(L, B, FB, bow=0.30, transom=0.80, sheer=SH)
    sup, top = superstructure(L * 0.085, fb,
                              ((28.0, 10.2, 5.0), (14.0, 7.6, 3.8, 1.4)),
                              taper=0.86)
    p += sup
    p += lattice_mast(0, -L * 0.010, top, 9.0, foot=2.2, head=0.8, bays=3,
                      solid=True, yards=((0.50, 6.4),), radome=1.3)
    p += funnel(0, -L * 0.115, fb + 2.0, 6.0, 4.4, 5.4, rake=10, uptakes=1)
    for s in (-1, 1):                                   # the exclusive
        p += canisters(s * 3.4, -L * 0.070, fb + 0.5, n=2, l=6.2, w=1.5,
                       h=1.5, elev=16, yaw=s * 12, name=f"can{s}")
    p += gun_mount(L * 0.335, fb + SH, r=1.45, barrel_l=4.2)
    p += ciws(0, L * 0.150, top - 3.4, 0.90)
    p += helipad(-L * 0.360, 9.4, 13.0, fb)
    p += clutter(hull_planform(L, B, transom=0.80, w=0.88), fb, spacing=9.0,
                 size=(0.9, 1.6, 0.75))
    p.append(team_patch(-L * 0.215, fb, 3.0, 3.6))
    return p, ship_meta(L, B, fb, top + 9.0, gun_y=L * 0.34, gun_z=fb + SH + 1.9)


def missile_boat():
    """Project 1241 Tarantul III — 56.1 x 10.2 m, draught 2.5 m, freeboard
    3.0 m. Coastal denial; Taiwan and the KPA lean on these.

    EXCLUSIVE FEATURE: four heavy CYLINDRICAL anti-ship tubes mounted on the
    deck edge, angled outboard and overhanging the side. The corvette owns the
    box canister; this owns the round tube, and from overhead the two never
    look alike.
    """
    L, B, FB = 56.1, 10.2, 3.0
    p, fb = ship_hull(L, B, FB, bow=0.34, transom=0.84, sheer=1.1)
    sup, top = superstructure(L * 0.075, fb,
                              ((17.5, 7.4, 4.2), (9.0, 5.6, 3.0, 0.8)),
                              taper=0.84)
    p += sup
    p += lattice_mast(0, -L * 0.020, top, 7.2, foot=1.8, head=0.7, bays=3,
                      yards=((0.55, 5.0),), radome=1.1)
    for s in (-1, 1):                                   # the exclusive
        p += missile_tubes(s * (B * 0.42), -L * 0.090, fb + 0.9, n=2, l=7.4,
                           r=0.88, elev=11, yaw=s * 9, name=f"tube{s}")
    p += gun_mount(L * 0.335, fb + 1.1, r=1.05, barrel_l=3.0)
    p += ciws(0, -L * 0.360, fb + 0.6, 0.85, aft=True)
    p += clutter(hull_planform(L, B, bow=0.34, transom=0.84, w=0.86), fb,
                 spacing=8.0, size=(0.8, 1.4, 0.7))
    p.append(team_patch(-L * 0.250, fb, 2.4, 3.0))
    return p, ship_meta(L, B, fb, top + 7.2, gun_y=L * 0.34, gun_z=fb + 2.1)


def patrol_vessel():
    """Cyclone-class PC — 54.6 x 7.6 m, draught 2.4 m, freeboard 2.9 m.
    Presence, escort, cheap eyes with a gun.

    EXCLUSIVE FEATURE: a notched transom with a stern boat ramp and a RHIB
    sitting in it. It is the only hull in the roster whose stern is cut open,
    and at any zoom the notch breaks the rectangle of the after deck.
    """
    L, B, FB = 54.6, 7.6, 2.9
    p, fb = ship_hull(L, B, FB, bow=0.30, transom=0.90)
    sup, top = superstructure(L * 0.055, fb,
                              ((19.0, 6.4, 4.4), (9.5, 4.8, 3.0, 1.0)),
                              taper=0.86)
    p += sup
    p += lattice_mast(0, -L * 0.030, top, 6.6, foot=1.6, head=0.6, bays=3,
                      yards=((0.56, 4.4),), radome=1.0)
    with mat("gunbore"):                                # the exclusive: the notch
        p.append(cube((0, -L * 0.455, fb - 0.6), (B * 0.52, L * 0.14, 2.6),
                      rot=(R(-9), 0, 0)))
    with mat("deck"):
        o = profile([(-L * 0.360, fb + 0.1), (-L * 0.470, fb - 0.35),
                     (-L * 0.462, fb + 0.75), (-L * 0.365, fb + 0.95)],
                    2.30, "pc_rhib")
        p.append(o)
    p += gun_mount(L * 0.330, fb, r=1.00, barrel_l=2.6)
    with mat("gun"):
        for s in (-1, 1):
            p.append(cyl((s * B * 0.30, -L * 0.145, fb + 0.9), 0.42, 1.5, v=10))
    p += clutter(hull_planform(L, B, transom=0.90, w=0.84), fb, spacing=8.0,
                 size=(0.75, 1.3, 0.65))
    p.append(team_patch(-L * 0.250, fb, 2.2, 2.8))
    return p, ship_meta(L, B, fb, top + 6.6, gun_y=L * 0.33, gun_z=fb + 1.3)


# ══ submarines ═════════════════════════════════════════════════════
def sub_diesel():
    """Type 209/1400 — 62.0 x 6.2 m, published draught 5.5 m; the round hull
    stands 1.20 m proud when surfaced and shows 4.90 m wide in plan. Quiet on the battery, loud snorkelling (docs/11 Q1).

    EXCLUSIVE FEATURE: the snorkel induction and diesel exhaust masts raised
    abaft the sail. It is the only boat here showing masts that are not on the
    sail centreline, and snorkelling is the thing that gets it killed.
    """
    L, B, FB = 62.0, 6.2, 1.20            # published draught 5.5 m to the keel
    assert sub_show_width(B, FB) > B * 0.52
    p, axis, deck = sub_hull(L, B, FB, name="ssk")
    p += casing(L * 0.30, -L * 0.34, B * 0.52, deck - 0.10)
    p += sail(L * 0.20, 7.4, 4.2, B * 0.36, deck, planes=True, masts=2)
    with mat("gun"):                                    # the exclusive
        p.append(cyl((0.9, L * 0.10, deck + 3.4), 0.24, 7.2, rot=(R(8), 0, 0), v=8))
        p.append(cyl((-0.9, L * 0.09, deck + 2.9), 0.20, 6.2, rot=(R(8), 0, 0), v=8))
        p.append(cube((0.9, L * 0.135, deck + 6.7), (0.6, 1.1, 0.5)))
    p += stern_planes(L, B, axis, "cross")
    p += propulsor(L, B, axis, "screw")
    p.append(team_patch(-L * 0.06, deck - 0.05, 1.8, 2.6))
    return p, ship_meta(L, B, deck, deck + 4.2 + 3.4, gun_y=L * 0.2,
                        gun_z=deck + 1.0)


def sub_nuclear():
    """Los Angeles 688i — 110.3 x 10.1 m, published draught 9.4 m; the round
    hull stands 1.90 m proud when surfaced and shows 7.89 m wide in plan. Fast and long-legged — and in epoch 2 NOISIER than the diesels
    it replaced (docs/11).

    EXCLUSIVE FEATURE: twelve vertical-launch tube caps in the bow casing, two
    rows of six forward of the sail. Nothing else underwater has a hatch grid.
    """
    L, B, FB = 110.3, 10.1, 1.90          # published draught 9.4 m to the keel
    assert sub_show_width(B, FB) > B * 0.46
    p, axis, deck = sub_hull(L, B, FB, name="ssn")
    p += casing(L * 0.36, -L * 0.30, B * 0.46, deck - 0.12)
    p += sail(L * 0.215, 11.6, 5.8, B * 0.32, deck, planes=True, masts=3)
    # The exclusive. It has to sit ON the casing, not in it: the first cut put
    # the caps at deck - 0.02 with the casing spanning deck - 0.12 to deck + 0.30,
    # so all twelve were buried inside it and the boat's identifying feature
    # rendered as nothing. They also started 0.6 m forward of the casing and
    # overhung its edge by 0.2 m either side.
    with mat("gunbore"):
        for s in (-1, 1):
            for k in range(6):
                p.append(cyl((s * 1.55, L * 0.330 - k * 2.05, deck + 0.40),
                             0.62, 0.30, v=12))
    p += stern_planes(L, B, axis, "cross")
    p += propulsor(L, B, axis, "screw")
    p.append(team_patch(-L * 0.08, deck - 0.07, 2.4, 3.4))
    return p, ship_meta(L, B, deck, deck + 5.8 + 3.4, gun_y=L * 0.2,
                        gun_z=deck + 1.0)


def sub_aip():
    """Type 212A — 57.2 x 7.0 m, published draught 6.0 m; 1.30 m of hull
    proud when surfaced, showing 5.44 m wide in plan.
    Air-independent propulsion: near-silent at creep, the best ambusher and
    the worst pursuer in the game (docs/08, Germany).

    EXCLUSIVE FEATURE: an X-form stern. Four canted planes and no cruciform
    rudder — from overhead a diagonal cross where every other boat shows a
    horizontal bar.
    """
    L, B, FB = 57.2, 7.0, 1.30            # published draught 6.0 m to the keel
    assert sub_show_width(B, FB) > B * 0.44
    p, axis, deck = sub_hull(L, B, FB, name="aip")
    p += casing(L * 0.30, -L * 0.30, B * 0.44, deck - 0.10)
    p += sail(L * 0.175, 6.6, 3.8, B * 0.30, deck, planes=False, masts=3)
    p += stern_planes(L, B, axis, "x")                  # the exclusive
    p += propulsor(L, B, axis, "pumpjet")
    with mat("gunbore"):                                # flank array panels
        for s in (-1, 1):
            p.append(cube((s * B * 0.47, L * 0.06, axis + B * 0.16),
                          (0.30, L * 0.26, 0.85)))
    p.append(team_patch(-L * 0.07, deck - 0.05, 1.8, 2.6))
    return p, ship_meta(L, B, deck, deck + 3.8 + 3.4, gun_y=L * 0.2,
                        gun_z=deck + 1.0)


def sub_midget():
    """Sang-O — 34.0 x 3.8 m, published draught 3.2 m; 0.80 m of hull proud
    when surfaced, showing 3.10 m wide in plan. The KPA's
    asymmetric tool: tiny acoustic signature, tiny range.

    EXCLUSIVE FEATURE: two external stores cradles clamped to the casing
    alongside the sail. It is the only boat that carries its weapons on the
    OUTSIDE, which is exactly what a swimmer-delivery and mine-laying boat
    does, and the pair of cylinders makes a 34 m hull identifiable.
    """
    L, B, FB = 34.0, 3.8, 0.80            # published draught 3.2 m to the keel
    assert sub_show_width(B, FB) > B * 0.50
    p, axis, deck = sub_hull(L, B, FB, v=18, name="mid")
    p += casing(L * 0.26, -L * 0.28, B * 0.50, deck - 0.06)
    p += sail(L * 0.150, 3.0, 1.9, B * 0.34, deck, planes=False, masts=2)
    with mat("gun"):                                    # the exclusive
        for s in (-1, 1):
            p.append(cyl((s * B * 0.44, L * 0.02, deck - 0.15), 0.42, L * 0.30,
                         rot=(R(90), 0, 0), v=10))
            p.append(cube((s * B * 0.44, L * 0.12, deck - 0.30), (0.55, 0.30, 0.75)))
            p.append(cube((s * B * 0.44, -L * 0.10, deck - 0.30), (0.55, 0.30, 0.75)))
    p += stern_planes(L, B, axis, "cross")
    p += propulsor(L, B, axis, "screw")
    p.append(team_patch(-L * 0.05, deck - 0.03, 1.0, 1.6))
    return p, ship_meta(L, B, deck, deck + 1.9 + 2.4, gun_y=L * 0.2,
                        gun_z=deck + 0.6)


# ══ aviation, amphibious, fleet train ══════════════════════════════
def carrier():
    """Nimitz CVN-68 — 332.8 m hull, 40.8 m at the waterline, 76.8 m across
    the flight deck, draught 11.3 m. The flight deck stands 19.6 m above the
    sea (hull to the hangar deck, then the hangar itself), which is why a
    carrier towers over an escort whose deck is at 5.9 m.

    EXCLUSIVE FEATURE: the angled landing deck, four catapult tracks and four
    deck-edge lifts. Both the angle and the lifts read from directly above,
    which is the only view an RTS gets, and the amphib deliberately has
    neither.
    """
    L, B, DECK_W, FD = 332.8, 40.8, 76.8, 19.6
    p, fb = ship_hull(L, B, FD, bow=0.22, transom=0.94, deck=False)
    use("body")
    p.append(plate([(-DECK_W * 0.30, L * 0.492), (DECK_W * 0.34, L * 0.300),
                    (DECK_W * 0.50, -L * 0.100), (DECK_W * 0.50, -L * 0.500),
                    (-DECK_W * 0.50, -L * 0.500), (-DECK_W * 0.50, L * 0.100),
                    (-DECK_W * 0.42, L * 0.340)], 1.8, fb + 0.9, "flightdeck"))
    fdz = fb + 1.8
    with mat("gunbore"):                                # angled landing area
        p.append(plate([(-DECK_W * 0.46, -L * 0.445), (-DECK_W * 0.05, L * 0.300),
                        (-DECK_W * 0.17, L * 0.330), (-DECK_W * 0.50, -L * 0.425)],
                       0.16, fdz + 0.08, "angledeck"))
    with mat("deck"):                                   # four catapult tracks
        for (x0, y0, x1, y1) in ((-DECK_W * 0.30, L * 0.44, -DECK_W * 0.22, L * 0.06),
                                 (-DECK_W * 0.12, L * 0.44, -DECK_W * 0.05, L * 0.06),
                                 (-DECK_W * 0.44, -L * 0.40, -DECK_W * 0.20, L * 0.16),
                                 (-DECK_W * 0.33, -L * 0.42, -DECK_W * 0.09, L * 0.14)):
            p.append(strut((x0, y0, fdz + 0.10), (x1, y1, fdz + 0.10), 0.55))
        for k in range(4):                              # arrestor wires
            p.append(cube((-DECK_W * 0.24, -L * 0.290 + k * 6.4, fdz + 0.10),
                          (DECK_W * 0.44, 0.42, 0.10), rot=(0, 0, R(9))))
    with mat("gunbore"):                                # jet blast deflectors
        for (bx, by) in ((-DECK_W * 0.26, L * 0.395), (-DECK_W * 0.08, L * 0.395),
                         (-DECK_W * 0.40, -L * 0.330)):
            p.append(cube((bx, by, fdz + 0.9), (11.0, 1.1, 1.8), rot=(R(-32), 0, 0)))
    isl_x = DECK_W * 0.375
    sup, top = superstructure(-L * 0.045, fdz,
                              ((34.0, 10.6, 8.0), (24.0, 9.0, 5.0, 1.0),
                               (14.0, 7.4, 4.4, 1.6)), taper=0.94, x=isl_x,
                              name="island")
    p += sup
    p += funnel(isl_x, -L * 0.085, top - 6.0, 12.0, 8.2, 9.0, rake=6, uptakes=2)
    p += lattice_mast(isl_x, -L * 0.050, top, 17.0, foot=3.2, head=1.0, bays=4,
                      yards=((0.46, 12.0), (0.76, 7.6)), radome=2.2)
    for s in (-1, 1):
        p += planar_array(isl_x - s * 4.6, -L * 0.045, top - 8.0, 4.2, 4.0,
                          22, 90 + s * 40)
    p += ciws(isl_x, -L * 0.115, fdz + 1.2, 1.15, aft=True)
    p += ciws(-DECK_W * 0.46, -L * 0.470, fdz + 1.2, 1.15, aft=True)
    p += ciws(DECK_W * 0.44, L * 0.300, fdz + 1.2, 1.15)
    # Four deck-edge lifts. Sat on the deck EDGE line in the first cut, which
    # put half of each 10.5 m platform over open water: they rendered as light
    # rafts alongside the ship rather than as part of it. A raised lift is
    # flush with the deck, so they are pulled inboard to overhang by 1.9 m,
    # which is enough to notch the deck outline without detaching.
    with mat("deck"):
        LW = 10.5
        for (lx, ly) in ((1, L * 0.180), (1, -L * 0.150),
                         (1, -L * 0.330), (-1, L * 0.075)):
            p.append(cube((lx * (DECK_W * 0.50 - LW * 0.5 + 1.9), ly,
                           fdz - 0.25), (LW, 21.0, 1.1)))
    with mat("gunbore"):                                # hangar-side openings
        for s in (-1, 1):
            for k in range(3):
                p.append(cube((s * B * 0.50, L * 0.16 - k * L * 0.16, fb - 5.0),
                              (0.9, 22.0, 6.4)))
    p.append(team_patch(-L * 0.470, fdz, 9.0, 11.0, x=-DECK_W * 0.20))
    return p, ship_meta(L, DECK_W, fdz, top + 17.0, gun_y=0.0, gun_z=fdz + 2.0)


def amphibious_assault():
    """Wasp LHD-1 — 257.3 m hull, 32.3 m at the waterline, 42.7 m across the
    flight deck, draught 8.1 m, flight deck 19.0 m above the sea.

    EXCLUSIVE FEATURE: a full-length RECTANGULAR deck with painted landing
    spots down the port side and an OPEN STERN WELL-DOCK GATE. No angle, no
    catapults, no waist — which is exactly how you tell it from the carrier
    from directly above, and the well dock is where the landing craft comes
    from, so it is gameplay.
    """
    L, B, DECK_W, FD = 257.3, 32.3, 42.7, 19.0
    p, fb = ship_hull(L, B, FD, bow=0.24, transom=0.94, deck=False)
    use("body")
    p.append(plate([(-DECK_W * 0.34, L * 0.480), (DECK_W * 0.34, L * 0.480),
                    (DECK_W * 0.50, L * 0.300), (DECK_W * 0.50, -L * 0.500),
                    (-DECK_W * 0.50, -L * 0.500), (-DECK_W * 0.50, L * 0.300)],
                   1.6, fb + 0.8, "deck"))
    fdz = fb + 1.6
    with mat("gunbore"):                                # nine landing spots
        for k in range(6):
            p.append(cyl((-DECK_W * 0.17, L * 0.340 - k * L * 0.132, fdz + 0.10),
                         4.9, 0.16, v=20))
    with mat("deck"):
        for k in range(6):
            p.append(cyl((-DECK_W * 0.17, L * 0.340 - k * L * 0.132, fdz + 0.16),
                         3.7, 0.10, v=20))
    isl_x = DECK_W * 0.345
    sup, top = superstructure(-L * 0.030, fdz,
                              ((46.0, 9.8, 7.4), (30.0, 8.4, 4.6, 1.2),
                               (16.0, 6.8, 4.0, 1.8)), taper=0.94, x=isl_x,
                              name="island")
    p += sup
    for k in (-1, 1):
        p += funnel(isl_x, -L * 0.010 + k * L * 0.055, top - 5.4, 11.0, 7.0,
                    8.0, rake=6, name=f"fnl{k}")
    p += lattice_mast(isl_x, -L * 0.062, top, 14.0, foot=2.8, head=1.0,
                      bays=4, yards=((0.50, 10.0), (0.78, 6.4)), radome=1.9)
    p += air_search(isl_x, -L * 0.098, top - 4.0, 7.4, 3.0)
    p += ciws(isl_x, -L * 0.120, fdz + 1.2, 1.15, aft=True)
    p += ciws(-DECK_W * 0.47, -L * 0.470, fdz + 1.2, 1.15, aft=True)
    with mat("gunbore"):                                # the exclusive: the gate
        p.append(cube((0, -L * 0.492, fb - FD * 0.42), (B * 0.66, 3.4, FD * 0.44)))
        p.append(cube((0, -L * 0.455, fb - FD * 0.60), (B * 0.60, L * 0.09, 1.2)))
    with mat("deck"):                                   # deck-edge lifts
        LW = 9.5                                        # inboard: see carrier()
        for (sx, ly) in ((-1, -L * 0.300), (1, -L * 0.130)):
            p.append(cube((sx * (DECK_W * 0.50 - LW * 0.5 + 1.7), ly,
                           fdz - 0.25), (LW, 18.0, 1.1)))
    p.append(team_patch(-L * 0.460, fdz, 7.0, 8.4, x=DECK_W * 0.12))
    return p, ship_meta(L, DECK_W, fdz, top + 14.0, gun_y=0.0, gun_z=fdz + 2.0)


def landing_craft():
    """LCAC-1 — 26.8 x 14.3 m on cushion. Ship-to-shore.

    THE ONE WATERLINE EXCEPTION IN THE FILE: an air-cushion vehicle really
    does sit on the surface, so the skirt base is at z = 0 and the buoyancy
    boxes start 1.5 m up. Everything else in the roster floats in the sea.

    EXCLUSIVE FEATURE: four ducted lift-fan shrouds on the after deck.
    """
    L, B = 26.8, 14.3
    p = []
    with mat("gunbore"):                                # skirt, on the water
        p.append(cube((0, 0, 0.72), (B * 1.02, L * 0.96, 1.44)))
    use("body")
    p.append(plate([(-B * 0.44, L * 0.44), (B * 0.44, L * 0.44),
                    (B * 0.50, L * 0.20), (B * 0.50, -L * 0.44),
                    (-B * 0.50, -L * 0.44), (-B * 0.50, L * 0.20)],
                   1.6, 2.25, "lc_hull"))
    with mat("deck"):                                   # cargo deck
        p.append(cube((0, L * 0.02, 3.10), (B * 0.56, L * 0.62, 0.24)))
    use("body")
    p.append(cube((0, L * 0.455, 3.4), (B * 0.60, 2.6, 2.6), rot=(R(-34), 0, 0)))
    p.append(cube((0, -L * 0.455, 3.4), (B * 0.56, 2.4, 2.4), rot=(R(34), 0, 0)))
    for s in (-1, 1):                                   # side buoyancy boxes
        p.append(deckhouse(L * 0.02, L * 0.74, 3.0, 3.0, 3.05, 0.94,
                           f"lc_side{s}", s * B * 0.365))
    with mat("glass"):
        p.append(cube((B * 0.365, L * 0.28, 5.5), (2.4, 2.6, 1.0)))
    with mat("gun"):                                    # the exclusive: 4 fans
        for s in (-1, 1):
            for k in range(2):
                p.append(cyl((s * B * 0.365, -L * 0.10 - k * L * 0.24, 4.9),
                             1.85, 2.10, rot=(R(90), 0, 0), v=16))
                p.append(cyl((s * B * 0.365, -L * 0.10 - k * L * 0.24, 4.9),
                             1.45, 2.30, rot=(R(90), 0, 0), v=12))
    with mat("gunbore"):
        for s in (-1, 1):
            for k in range(2):
                p.append(cyl((s * B * 0.365, -L * 0.10 - k * L * 0.24 - 1.2, 4.9),
                             1.30, 0.20, rot=(R(90), 0, 0), v=12))
    p.append(team_patch(L * 0.02, 3.20, 2.6, 3.2))
    use("body")
    return p, ship_meta(L, B, 2.9, 6.6, gun_y=0.0, gun_z=4.9)


def fleet_oiler():
    """Henry J. Kaiser T-AO-187 — 206.5 x 29.7 m, draught 10.7 m, freeboard
    8.0 m. Pillar 4's centrepiece (docs/04): a submarine that finds this has
    taken the fleet's RANGE, which is worth more than a destroyer.

    EXCLUSIVE FEATURE: a row of four replenishment kingposts with spanwire
    booms. They are the only masts in the fleet that are NOT on the
    centreline, and four tall verticals in a line down a long flat deck is
    unmistakable from any angle.
    """
    L, B, FB = 206.5, 29.7, 8.0
    p, fb = ship_hull(L, B, FB, bow=0.24, transom=0.90, sheer=2.6)
    sup, top = superstructure(-L * 0.360, fb,
                              ((34.0, 20.0, 7.0), (28.0, 17.0, 3.6),
                               (20.0, 13.0, 3.4), (13.0, 9.6, 3.2)),
                              taper=0.94)
    p += sup
    p += funnel(0, -L * 0.435, top - 8.0, 13.0, 10.0, 11.0, rake=8)
    p += lattice_mast(0, -L * 0.395, top, 11.0, foot=2.8, head=1.0, bays=3,
                      yards=((0.55, 9.0),), radome=1.6)
    for s in (-1, 1):                                   # the exclusive
        for y in (L * 0.175, -L * 0.055):
            p += kingpost(s * 4.4, y, fb, 17.0, boom=12.0, side=s,
                          name=f"kp{s}{y:.0f}")
    with mat("deck"):                                   # tank tops and hatches
        p.append(cube((0, L * 0.075, fb + 0.28), (B * 0.80, L * 0.50, 0.56)))
        for k in range(5):
            p.append(cyl((0, L * 0.275 - k * L * 0.105, fb + 0.80), 2.3, 0.72,
                         v=16))
    p += helipad(-L * 0.205, 15.0, 19.0, fb)
    for s in (-1, 1):
        p += boat_bay(s * B * 0.47, -L * 0.300, fb, l=8.4, h=3.2)
    p += breakwater(L * 0.400, B * 0.60, fb + 2.6)
    p += clutter(hull_planform(L, B, bow=0.24, transom=0.90, w=0.92), fb,
                 spacing=15.0, size=(1.2, 2.2, 0.95))
    p.append(team_patch(L * 0.310, fb, 5.0, 6.0))
    return p, ship_meta(L, B, fb, top + 11.0, gun_y=0.0, gun_z=fb + 1.0)


def mine_warfare():
    """Avenger MCM-1 — 68.3 x 11.9 m, draught 3.7 m, freeboard 3.6 m. Laying
    and sweeping; Taiwan's force multiplier (docs/12).

    EXCLUSIVE FEATURE: a stern A-frame gantry with the sweep sled sitting
    under it on an open working deck. Nothing else has a frame standing over
    the transom, and the big empty after deck is itself a read.
    """
    L, B, FB = 68.3, 11.9, 3.6
    p, fb = ship_hull(L, B, FB, bow=0.28, transom=0.88, sheer=1.2)
    sup, top = superstructure(L * 0.195, fb,
                              ((21.0, 9.0, 5.4), (11.0, 6.8, 3.4, 1.0)),
                              taper=0.88)
    p += sup
    p += lattice_mast(0, L * 0.105, top, 8.4, foot=2.2, head=0.8, bays=3,
                      yards=((0.52, 6.2),), radome=1.2)
    p += funnel(0, L * 0.040, fb + 1.8, 5.6, 4.2, 5.0, rake=12, uptakes=1)
    with mat("deck"):                                   # open working deck
        p.append(cube((0, -L * 0.215, fb + 0.24), (B * 0.80, L * 0.40, 0.48)))
    p += gantry(-L * 0.450, fb, B * 0.72, 5.4, depth=3.4)   # the exclusive
    with mat("gun"):                                    # the sweep sled
        p.append(cube((0, -L * 0.395, fb + 1.1), (4.2, 5.0, 1.8)))
        for s in (-1, 1):
            p.append(cyl((s * 1.5, -L * 0.395, fb + 2.3), 0.55, 4.6,
                         rot=(R(90), 0, 0), v=10))
    with mat("gunbore"):                                # mine rails
        for s in (-1, 1):
            p.append(cube((s * B * 0.26, -L * 0.230, fb + 0.55), (0.55, L * 0.34,
                                                                  0.20)))
    with mat("gun"):
        for k in range(3):
            p.append(cyl((0, -L * 0.090 - k * 4.2, fb + 1.05), 1.05, 1.5, v=14))
    p += gun_mount(L * 0.400, fb + 1.2, r=1.00, barrel_l=2.4)
    p += clutter(hull_planform(L, B, bow=0.28, transom=0.88, w=0.88), fb,
                 spacing=9.0, size=(0.9, 1.6, 0.75))
    p.append(team_patch(-L * 0.060, fb, 2.8, 3.4))
    return p, ship_meta(L, B, fb, top + 8.4, gun_y=L * 0.40, gun_z=fb + 2.4)


# ══════════════════════════════════════════════════════════════════
# THE NOTE AT THE BOTTOM OF THE FILE: RAILINGS DO NOT SURVIVE
# ══════════════════════════════════════════════════════════════════
# The brief asked for deck-edge railings "if they survive at zoom — test
# whether they do; if not, say so and do not add them." Tested twice, and the
# answer is no, twice.
#
# SCALE. tools/navy_render.py renders navy_plan_escort.png at 200 m of ortho
# span across 1900 px, which is 9.5 px per metre, and then re-renders the same
# frame at 110 px high, which is 1.1 px per metre and is about what the game
# camera gives a 155 m destroyer. A railing stanchion is 0.10 m. It is
# ONE NINTH OF A PIXEL. Even the top rail, at 0.10 m, is the same. Nothing
# about anti-aliasing rescues a feature an order of magnitude under a pixel;
# it contributes a faint grey haze along the deck edge and shimmers when the
# ship moves.
#
# COST. railing() over 100 m of run measures 12 784 triangles after the LOD0
# bevel, because it is 68 separate members and cost here is object count. An
# escort's two sides and transom is roughly 330 m of run, so railing one
# destroyer costs about 42 000 triangles — MORE THAN THE ENTIRE SHIP (30 632)
# and more than the carrier's whole budget.
#
# WHAT TO DO INSTEAD. The deck edge is already carried for free by the
# material step from the light `deck` plate to the dark `body` hull side, and
# clutter() walks liferaft canisters down it for 3 000. That is the same read
# for a fourteenth of the price. railing() is kept for close-up cinematics and
# NO SHIP IN THIS FILE CALLS IT. Do not be the agent who adds it.
#
# The same measurement disposes of a second temptation: at 1.1 px per metre
# nothing under about 3 m resolves at all. On the zoom sheet the CIWS mounts,
# the gun mounts, the torpedo tubes, the funnels and the masts have all gone,
# and what still reads is the hull outline, the superstructure mass, the VLS
# field, and the helipad — every one of them a DECK-PLAN feature 8 m or larger
# in a material that contrasts with the hull. Detail smaller than that is for
# the three-quarter band sheets and for nothing else.


NAVY = [
    ("nav_e4_us_destroyer",  destroyer_aaw,       "air_dark"),
    ("nav_e1_us_frigate",    frigate_asw,         "air_dark"),
    ("nav_e1_us_cruiser",    cruiser,             "air_dark"),
    ("nav_e1_us_corvette",   corvette,            "air_dark"),
    ("nav_e2_us_missileboat", missile_boat,       "air_dark"),
    ("nav_e1_us_patrol",     patrol_vessel,       "air_dark"),
    ("sub_e1_us_diesel",     sub_diesel,          "air_dark"),
    ("sub_e2_us_nuclear",    sub_nuclear,         "air_dark"),
    ("sub_e7_de_aip",        sub_aip,             "air_dark"),
    ("sub_e1_kp_midget",     sub_midget,          "air_dark"),
    ("nav_e1_us_carrier",    carrier,             "air_dark"),
    ("nav_e2_us_amphib",     amphibious_assault,  "air_dark"),
    ("nav_e1_us_landingcraft", landing_craft,     "air_dark"),
    ("nav_e1_us_oiler",      fleet_oiler,         "air_dark"),
    ("nav_e1_us_minewarfare", mine_warfare,       "air_dark"),
]

if __name__ == "__main__":
    H.set_out(os.path.join(ROOT, "art", "blockout", "e4_navy"))
    for name, _, camo in NAVY:
        H.CAMO[name] = camo
        H.TEAM[name] = (0.06, 0.20, 0.62)
    print("building navy...")
    for name, fn, _ in NAVY:
        for lod in (0, 1, 2):
            n = H.build(name, fn, lod)
            print(f"  {name:26s} LOD{lod}  {n:6d} tris")
    print("done")
