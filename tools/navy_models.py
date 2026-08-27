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

    SUBMARINES INVERT IT, DELIBERATELY, SINCE PASS 4. A boat's casing is
    `gunbore` and only its walkway, hatches and sail crown are `deck`, so a
    surfaced submarine is a DARK lozenge carrying a few bright marks while
    every surface ship is a LIGHT deck inside a dark hull. Two reasons: it is
    what an anechoic-tiled casing actually looks like from a helicopter, and
    docs/02 §8 makes ASW a pillar, so telling a surfaced boat from a corvette
    at one glance is gameplay rather than styling. The consequence is that a
    boat's exclusive feature has to be LIGHT ON BLACK — see the note at the
    head of the submarine section, and the SSN's launch caps, which were
    invisible in two consecutive passes for two different versions of this
    mistake.

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
      sub_hull SSN v=24                 3 420     sail, 3 masts        2 268
      sub_hull SSN v=18                 2 556     sail, with a step    2 456
      casing, black + walkway             408     sub_fittings, each     476
      stern_planes cross                  752     propulsor screw      1 512
      stern_planes x, with tip fairings 1 128     propulsor pumpjet      856
      sub_towed_array                     568

      railing(), 100 m of run          12 784  <- see the note at the bottom

The escort fittings added by the detail pass, measured the same way:

      director, 2 objects                 600     satcom, dome v=8       512
      esm_array                           376     satcom, dome v=12    1 152
      bridge_wing with a 25 mm            568     anchor_gear            852
      chaff_launcher                      188     towed_array          1 232
      deck_panel                          188     tube_sponson           376

A SPHERE IS THE WORST VALUE IN THE FILE, and it is not obvious from the
source. dome() bevels every one of its edges, so a single 1.4 m SATCOM ball
at v=12 costs 1 152 triangles — more than the whole 333 m carrier hull — and
at v=8 it costs 512 and is indistinguishable at the three pixels it occupies.
Check the vertex count on every dome you add; ciws() and radome() already do.

Two of those are the whole story. An OPEN lattice_mast costs three times a
solid one because it is 27 separate members; pass solid=True unless the ship
is pre-1980. And vls() was 12 220 for a 64-cell farm until it was rebuilt as a
slab with ribs — see the note on vls() itself.

TRIANGLE BUDGET at LOD0, and the headroom actually left, measured on the
current build. The capitals are the ships with room; the escorts are the ships
that are tight, which is the opposite of how it looks:

      carrier      40 000    32 844     +7 156 of headroom
      amphib       40 000    28 168    +11 832
      oiler        40 000    23 676    +16 324
      destroyer    36 000    34 760     +1 240   detail pass, see below
      cruiser      44 000    42 020     +1 980   two 64-cell farms and two masts
      frigate      32 000    30 136     +1 864   detail pass, see below
      missileboat  18 000    17 940        +60
      minehunter   18 000    18 000         +0
      corvette     16 000    15 628       +372
      patrol       14 000    13 896       +104
      LCAC         12 000    11 728       +272
      SSN          17 000    15 868     +1 132
      SSK          11 500    10 056     +1 444
      AIP          10 000     7 980     +2 020
      midget       10 000     9 104       +896

The four submarine ceilings were raised in pass 4 and the reason is on the
record. They had been set to just above what the pass-3 boats cost, which left
the midget +588 — three boxes — at the same moment the project owner rejected
the fleet for having no detail, so the constraint and the instruction could not
both be satisfied. They now sit about 1 000 above measured, and the additions
were part-paid by real savings rather than by the raise alone: sub_hull v 24→18
(-864 on the SSN), a five-bladed screw at a sane diameter (-376), and the AIP's
two flank panels that sat 1.08 m under the sea (-376).

The escort ceilings were raised from a flat 26 000 because that number was
guessed in the first pass and the ships had already blown through it — the
cruiser measured 60 216 before vls() and ciws() were repriced. If you need
more than the headroom above, the money is in lattice_mast(solid=True), in a
lower vertex count on any dome, and in deleting clutter — not in shaving
cylinder segments off things that are already at v=8.

TWO CEILINGS MOVED IN THE ESCORT DETAIL PASS, AND HERE IS THE ARITHMETIC.
Setting each ceiling "just above what the hull costs today" is a ratchet that
forbids the ship from ever getting better, and the owner rejected the fleet
that ratchet produced. The destroyer went 30 632 -> 34 760 and the frigate
26 116 -> 30 136, both under the owner's stated ~40 000 for the largest object
in the game. What the +4 100 bought on each is three illuminators, ESM
outriggers, bridge wings, chaff, anchor gear and — on the frigate — the whole
ASW fit: a second marked helicopter spot, the torpedo-tube sponsons and the
towed-array winch.

THE CRUISER DID NOT NEED A NEW CEILING and is the model for how to pay. It
gained four illuminators, an SPS-49 slab, ESM, bridge wings, chaff, SATCOM and
anchor gear for a NET of +788 triangles, because plating the fore mast gave
back 3 572 and thinning the liferafts gave back 1 300. Two open lattices were
costing 42 objects and 11 000 triangles — a quarter of the ship — on the two
fittings this file's own zoom test says disappear first.

────────────────────────────────────────────────────────────────────────────
ONE EXCLUSIVE IDENTIFYING FEATURE PER SHIP
────────────────────────────────────────────────────────────────────────────
Every hull is grey and most of them are 100–170 m long, so silhouette alone
will not carry fifteen roles. Each ship owns ONE feature that no other ship in
the roster is allowed to have, chosen to read from directly overhead.

AND IT HAS TO SIT SOMEWHERE NOTHING ELSE'S DOES. Measured on the zoom sheet
(art/renders/navy_plan_escort_110.png), what survives to the game camera is not
WHAT a dark patch on the deck is, it is WHERE it is and how long the hull is.
The destroyer and the cruiser both come down to "two dark rectangles on a grey
lozenge" and the only thing separating them at that size is that the cruiser's
sit at the extreme ends and the destroyer's do not. So when you place your
ship's exclusive feature, place it at a station along the hull that no other
ship's feature occupies, and do not defend a choice on the grounds that the
feature is a different SHAPE — at 1.1 px per metre it is not a shape, it is a
smudge at a position.

  destroyer     FOUR canted planar arrays clustered on one pyramidal forward
                deckhouse, plus twin centreline funnels
  cruiser       a 5-inch turret at BOTH ends — the only stern main gun afloat
                here — carried by twin fore-and-aft superstructure islands
  frigate       a single trainable arm launcher on the forecastle and NO VLS
                anywhere; its gun sits on the deckhouse ROOF amidships. Its
                ASW fit is three more plan features nothing else has: TWO
                marked helicopter spots on one flight deck, torpedo-tube
                sponsons standing PROUD of the hull line amidships, and the
                towed-array winch on the last four metres before the transom
  corvette      two inclined box canister packs amidships, athwartships
  missile boat  four heavy cylindrical AShM tubes on the deck EDGE, angled
                outboard and overhanging the side
  patrol        a notched transom with a stern boat ramp and a RHIB in it
  carrier       the angled flight deck, four catapult tracks, four deck-edge
                lifts
  amphib        a full-length rectangular landing lane with painted spots and
                the stern well-dock gate DOWN — a ramp lying out over the
                water abaft the transom, because a vertical door has no plan
  oiler         a row of four replenishment kingposts with spanwire booms
  minehunter    a stern A-frame gantry with the sweep sled sitting under it,
                over a WORKING DECK BUILT IN `gunbore` — the after 47% of the
                hull is black, which is the only figure-ground inversion in
                the small-craft band
  LCAC          four ducted lift-fan shrouds, now VERTICAL and on the
                ROOFS of the side boxes so they read in plan, over a dark
                open cargo well that runs out through both ramps
  SSK           the raised snorkel induction and exhaust masts abaft the sail,
                on a light induction housing at 0.01 L — dead amidships
  SSN           twelve vertical-launch tube caps in the bow casing
  AIP           an X-form stern — four canted planes, no cruciform rudder,
                the two upper ones carrying light fairings above the water
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
# FIGURE-GROUND AT SEA, DECIDED HERE RATHER THAN LEFT IMPLICIT.
#
# Pass 3 left the casing in the `deck` group, so every boat rendered as a pale
# plank sixty per cent of its own length laid inside a thin dark rim, with one
# small fin on it and nothing else — art/renders/navy_subs.png, four ferries.
# The plank was also the brightest thing in the frame, brighter than the sea,
# so the eye went to a featureless rectangle.
#
# It is now inverted, and the inversion is the class read:
#
#     hull        `body`     dark camo, textured
#     casing      `gunbore`  NEAR BLACK — anechoic/free-flood casing
#     walkway,    `deck`     light warm grey, and SMALL
#     hatches,
#     sail cap
#
# so a surfaced submarine is a DARK rounded lozenge carrying a handful of
# bright marks, where every surface ship in the roster is a LIGHT deck inside a
# dark hull. That separation is worth having on its own — docs/02 §8 makes ASW
# a pillar, and telling a surfaced boat from a corvette at a glance is the
# gameplay — and it is also what a real submarine looks like from a helicopter.
#
# It changes what the exclusive features have to be made of. A dark feature on
# a dark casing is nothing, which is how the SSN's twelve launch caps came to
# be invisible twice running. Every boat's exclusive is now LIGHT ON BLACK:
#
#     SSN     twelve light launch-tube caps, two rows of six, +0.215..+0.308L
#     SSK     a light snorkel-induction housing abaft the sail, -0.07..+0.05L
#     AIP     two light X-plane fairings above the water, at -0.362L
#     midget  two light stores cradles OUTBOARD of the hull, at +0.02L
#
# and no two of them sit at the same station, which is the rule in the module
# docstring: at 1.1 px per metre a feature is not a shape, it is a mark at a
# place.
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


def sub_hull(L, B, freeboard, stations=SUB_STATIONS, v=18, name="sub"):
    """Surfaced submarine hull. Returns (parts, axis_z, casing_z).

    casing_z is the crown of the hull — the deck a sail, a hatch or a launch
    tube sits on — and equals `freeboard` by construction. Geometry below
    z = 0 is intentional and the sea plane hides it; submerging the boat is a
    translation in z and not a second model. That is also the answer to
    "is a periscope-depth variant worth having": no. It is this asset moved
    down by (freeboard + d) metres, with the sail crown left proud, and it
    needs no second model, no second roster entry and no second budget.

    The number that decides whether the boat reads as a boat is how wide the
    hull shows in PLAN, which is 2*sqrt((B/2)^2 - (B/2 - freeboard)^2). It has
    to beat the width of the casing laid on top of it or the casing is all you
    see; sub_hull asserts that, because getting it wrong is invisible in code
    and obvious in the render.

    v DROPPED FROM 24 TO 18 IN PASS 4, and it paid for the deck detail. The
    only part of the barrel a player ever sees is the strip between the two
    waterline chords — five or six facets of eighteen — and the edge-split
    angle is 26 degrees, so at v=18 the 20-degree facet break still shades
    smooth and the crown is visibly identical. Measured on the SSN: 3 420 tris
    at v=24, 2 568 at v=18, and no difference in the render at any zoom.
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


def sub_rfrac(f):
    """Hull radius at fraction f of the length from the bow, as a fraction of
    B/2. Linear between the SUB_STATIONS knots — the same curve revolve() uses,
    so anything placed with it lands ON the hull instead of near it."""
    f = min(max(f, 0.0), 1.0)
    for i in range(len(SUB_STATIONS) - 1):
        (f0, r0), (f1, r1) = SUB_STATIONS[i], SUB_STATIONS[i + 1]
        if f0 <= f <= f1 and f1 > f0:
            return r0 + (r1 - r0) * (f - f0) / (f1 - f0)
    return SUB_STATIONS[-1][1]


def sub_crown(L, B, axis_z, y):
    """Height of the top of the hull at station y."""
    r = (B / 2.0) * sub_rfrac((L * 0.5 - y) / L)
    return axis_z + r


def sub_show_at(L, B, axis_z, y):
    """How wide the hull shows at the waterline at station y — zero once the
    tail has narrowed past the axis depth. This is what decides how far aft the
    stern planes can stand and still look attached: at -0.415 L the SSN showed
    a strip 0.0 m wide and the rudder read as a loose rectangle in open sea; at
    -0.390 L it shows 5.6 m."""
    r = (B / 2.0) * sub_rfrac((L * 0.5 - y) / L)
    return 2.0 * math.sqrt(max(r * r - axis_z * axis_z, 0.0))


def _casing_plan(y0, y1, w, nose=0.17, tail=0.24):
    """Casing outline: pointed forward, tapered aft, never a blunt rectangle.

    The pass-3 casing was cube((0, mid), (w, len, h)) — a plank with square
    ends sitting on a pointed hull, which is the single loudest reason the
    boats read as barges. A real casing fairs into the hull crown at both ends.
    """
    hw, ln = w / 2.0, (y0 - y1)
    a, b = ln * nose, ln * tail
    right = [(0.0, y0), (hw * 0.60, y0 - a * 0.40), (hw, y0 - a),
             (hw, y1 + b), (hw * 0.52, y1 + b * 0.38), (0.0, y1)]
    return right + [(-x, y) for (x, y) in reversed(right) if x > 1e-9]


def casing(y0, y1, w, z, h=0.42, walk=0.44, name="csg"):
    """The free-flood casing over the crown of the pressure hull, NEAR BLACK,
    with a light non-skid walkway down its centreline.

    Two objects, and between them they carry the whole class read: the black
    plate makes the boat a dark lozenge, and the thin light stripe is the only
    continuous bright thing on it, so the eye follows the boat's length instead
    of stopping on a pale slab. See the note at the head of this section.
    """
    out = []
    pts = _casing_plan(y0, y1, w)
    with mat("gunbore"):
        out.append(plate(pts, h, z + h / 2.0, name))
    with mat("deck"):
        out.append(cube((0.0, (y0 + y1) / 2.0 - (y0 - y1) * 0.02,
                         z + h + 0.07),
                        (w * walk, (y0 - y1) * 0.90, 0.14)))
    return out


def sub_fittings(y_list, z, r=0.62, x=0.0, h=0.20, v=10, name="ftg"):
    """Light discs on the black casing: escape trunks, the weapon shipping
    hatch, the capstan. Small, but they are the only marks between the bow and
    the sail on a boat that is otherwise 60 m of nothing, and on the black
    casing they are the highest-contrast thing on the model."""
    with mat("deck"):
        return [cyl((x, y, z + h / 2.0), r, h, v=v) for y in y_list]


def sail(y, l, h, w, z, planes=True, masts=3, step=0.0, cap=True, name="sail"):
    """Fin/sail, built in TIERS the way the superstructure of a surface ship is.

    Rule 1 of the brief applied to a boat that has no superstructure: almost
    all of a submarine's read is the sail, so the sail is the thing that gets
    the tiering. Bottom to top —

        fillet   the low, long, wide fairing where the fin meets the casing.
                 Every real sail has one and it is what stops the fin looking
                 like a card stuck in a loaf.
        fin      the raked leading-edge body.
        step     an optional shorter, narrower second tier set aft, for the
                 SSK, whose 209 fin is visibly stepped.
        cap      a LIGHT `deck` plate on the crown. On the near-black casing
                 this is the one bright mark high on the boat, and its station
                 along the hull is what separates the four classes at the game
                 camera — measured at y - 0.56 l, that is SSN 0.156 L,
                 SSK 0.133 L, AIP 0.110 L, midget 0.101 L.

    `masts` raised periscopes/ESM in `gun`, and a gunbore bridge cockpit notch.
    """
    out = []
    use("body")
    out.append(profile([(y + l * 0.10, z - 0.05), (y - l * 1.16, z - 0.05),
                        (y - l * 1.04, z + h * 0.20), (y + l * 0.02, z + h * 0.20)],
                       w * 1.55, name + "_fil"))
    out.append(profile([(y, z + h * 0.10), (y - l, z + h * 0.10),
                        (y - l * 0.88, z + h), (y - l * 0.12, z + h)], w, name))
    top = z + h
    if step > 0.0:
        out.append(profile([(y - l * 0.24, top - 0.05), (y - l * 0.92, top - 0.05),
                            (y - l * 0.84, top + step), (y - l * 0.30, top + step)],
                           w * 0.80, name + "_stp"))
        top += step
    with mat("gunbore"):
        out.append(cube((0.0, y - l * 0.30, top - 0.30), (w * 0.60, l * 0.26, 0.60)))
    if cap:
        with mat("deck"):
            out.append(cube((0.0, y - l * 0.56, top + 0.06), (w * 0.86, l * 0.60, 0.18)))
    with mat("gun"):
        for k in range(masts):
            out.append(cyl((0.0, y - l * 0.42 - k * l * 0.13, top + 1.6 - k * 0.35),
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


def stern_planes(L, B, axis_z, style="cross", tip=None, chord=None,
                 tipcap=False, station=None, name="sp"):
    """Stern control surfaces. `tip` is the TIP RADIUS from the axis, not a
    span, because the span form was being read as a diameter and the planes
    came out at twice life size — the AIP's X planes reached 0.61 of a span of
    1.55 B, i.e. a 13 m diagonal on a 7 m boat, and rendered as a slab.

    style="cross" is the conventional cruciform: two horizontal planes plus an
    upper and a lower rudder.

    style="x" is the four-canted X-form and it is the AIP's exclusive feature.
    HONEST CORRECTION TO THE PASS-3 CLAIM: it does NOT read "as a diagonal
    cross" from overhead. Projected straight down the two upper planes fall on
    a single athwartships bar, exactly like the cruciform pair. What actually
    separates it is that the upper planes BREAK THE SURFACE — with tipcap they
    show two light plates standing proud at the transom, in a V, where the
    three cruciform boats show one thin fore-and-aft fin. It separates on
    material and on being above water, not on any diagonal.

    A ROTATION BUG WAS FIXED HERE. The canted planes used rot=(0, R(45 - a), 0),
    which leaves the a=45 plane horizontal and stands the a=135 plane vertical,
    so the X boat had a cruciform stern drawn at the wrong radius. It is
    rot=(0, R(-a), 0).
    """
    out = []
    tip = tip if tip is not None else B * 0.78
    chord = chord if chord is not None else L * 0.055
    root = B * 0.26
    ln, ctr = tip - root, (tip + root) / 2.0
    # -0.390 L, not -0.415 L. At 0.415 the hull has narrowed to a strip too
    # thin to see and the rudder rendered as a loose rectangle with open sea
    # between it and the boat — the "detached chip" of the pass-3 report. Two
    # and a half metres further forward the hull still shows about 0.69 of its
    # radius and the rudder grows out of something.
    #
    # The X form has to come further forward still, and the arithmetic says why.
    # A plane canted at 45 degrees breaks the surface at radius (freeboard's
    # depth)/cos 45 — on the AIP at x = 2.20 m — so it is only ever attached to
    # what the hull SHOWS at its own station. At -0.390 L the AIP shows 1.9 m
    # and the planes floated with 1.3 m of sea inboard of them; at -0.362 L it
    # shows 3.1 m and the gap is 0.65 m, which is ten pixels on the plan sheet
    # and none at the game camera.
    y = station if station is not None else (
        -L * 0.362 if style == "x" else -L * 0.390)
    use("body")
    if style == "x":
        for a in (45, 135, 225, 315):
            out.append(cube((math.cos(R(a)) * ctr, y, axis_z + math.sin(R(a)) * ctr),
                            (ln, chord, 0.42), rot=(0, R(-a), 0)))
        if tipcap:
            # An X plane is body camo, and the part of it that is above the
            # sea is the OUTER half — so what the plan sheet gets is a camo
            # patch on a blue sea, which is exactly the case the module
            # docstring says does not read. The fix is a light fairing lying
            # along the whole above-water length of each UPPER plane, from just
            # outside the point where it breaks the surface out to the tip.
            #
            # IT MUST OVERLAP THE PLANE, NOT PERCH ON THE TIP. The first cut
            # sat at 0.88 of the tip radius and 0.34 of the span wide, which on
            # the AIP left it 3.2 m clear of everything and rendered as two
            # light boxes floating in open water beside the boat. At 0.79 and
            # 0.48 it covers the plane's visible band and the remaining metre
            # of sea between it and the narrow stern is what an X stern really
            # looks like.
            with mat("deck"):
                d = tip * 0.707
                for a in (45, 135):
                    out.append(cube((math.cos(R(a)) * tip * 0.79, y,
                                     axis_z + d * 0.79 + 0.10),
                                    (d * 0.48, chord * 0.80, 0.50)))
    else:
        for s in (-1, 1):
            out.append(cube((s * ctr, y, axis_z), (ln, chord, 0.42)))
        out.append(profile([(y + chord * 0.6, axis_z), (y - chord * 0.6, axis_z),
                            (y - chord * 0.5, axis_z + B * 0.72),
                            (y + chord * 0.3, axis_z + B * 0.66)], 0.42,
                           name + "_ru"))
        out.append(profile([(y + chord * 0.6, axis_z), (y - chord * 0.6, axis_z),
                            (y - chord * 0.5, axis_z - B * 0.62),
                            (y + chord * 0.3, axis_z - B * 0.58)], 0.42,
                           name + "_rl"))
    return out


def sub_towed_array(L, B, axis_z, y0, y1, side=1, name="tas"):
    """The towed-array fairing along ONE side of a submarine, and its reel.

    NAMED sub_ BECAUSE THE ESCORTS OWN towed_array(). A surface ship's array is
    a winch and a chute on the transom; a boat's is a raised tube down the
    flank, and the two are different shapes on different hulls. Two functions,
    two names — the first version of this collided with the escort builder and
    the SSN build died on the argument list.

    docs/02 §8 makes ASW a pillar and the array is the boat's own half of it.
    It is also the only ASYMMETRIC feature in the fleet: one raised line down
    the starboard side and nothing to port. Dark on dark, so it is a
    three-quarter-sheet feature and is budgeted as one — two objects.
    """
    out = []
    # It has to sit ABOVE the waterline chord or it is 2 objects nobody can
    # see: pass 4's first cut put it at axis + 0.46 r, which on the SSN is
    # 0.86 m under the sea. At 0.72 r it lies on the flank just inboard of the
    # visible edge and shows as one raised line down one side.
    r = (B / 2.0) * 0.985
    with mat("gunbore"):
        out.append(cyl((side * r * 0.74, (y0 + y1) / 2.0, axis_z + r * 0.72),
                       B * 0.036, y0 - y1, rot=(R(90), 0, 0), v=8))
        out.append(cube((side * r * 0.70, y1 - B * 0.09, axis_z + r * 0.76),
                        (B * 0.11, B * 0.20, B * 0.09)))
    return out


def propulsor(L, B, axis_z, kind="screw", name="prop"):
    """Screw or pumpjet. Five blades, not seven: it is permanently below the
    sea plane in every render and in the game, and the two extra blades cost
    376 triangles that the deck wanted."""
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
            # Blade tips at 0.28 B, i.e. a screw 0.56 B across. The pass-3
            # blade was a 4.44 m box centred at 0.26 B, so it reached 0.48 B —
            # a 9.7 m screw on a 10.1 m hull — and because a submarine's axis
            # here sits only (B/2 - freeboard) below the sea, the top blade
            # came 1.70 m OUT OF THE WATER and rendered as a pale chip astern.
            for k in range(5):
                a = 2.0 * math.pi * k / 5.0
                out.append(cube((B * 0.17 * math.sin(a), y,
                                 axis_z + B * 0.17 * math.cos(a)),
                                (0.10, B * 0.16, B * 0.22), rot=(0, a, 0)))
    return out


# ══ escort fittings ════════════════════════════════════════════════
# Added by the escort detail pass, and called ONLY by the destroyer, the
# cruiser and the frigate. They exist because those three ships were spending
# 250 triangles apiece on 1 m liferafts while every deckhouse roof in the
# group was a bare slab, which is the wrong way round: a roof is a surface the
# game camera looks straight down on and a liferaft is one pixel.
#
# Every one of these is four objects or fewer, and every one is either a rung
# on a docs/02 sensor ladder or a material step on a surface that was blank.


def director(x, y, z, r=1.30, tilt=15.0, aft=False, name="dir"):
    """Fire-control illuminator: a pedestal and a canted dish.

    docs/02 section 8.6 — a semi-active missile cannot be guided to the target
    without one of these pointed at it, so the COUNT is the ship's simultaneous
    engagement capacity and it is gameplay, not decoration. Burke IIA carries
    three, Ticonderoga four, Perry one. The dish is `deck`, the lightest group
    afloat, so it reads as a bright disc on a dark roof — which is exactly how
    a director reads on the real ship.

    Two objects. `aft` swings the dish to point over the stern.
    """
    s = -1.0 if aft else 1.0
    out = []
    with mat("gun"):
        out.append(cyl((x, y, z + 0.85), r * 0.50, 1.70, v=8))
    with mat("deck"):
        out.append(cyl((x, y + s * 0.34, z + 2.05), r, 0.50,
                       rot=(R(s * (tilt - 90.0)), 0, 0), v=14, taper=0.60))
    return out


def esm_array(x, y, z, l=2.80, h=2.40, name="esm"):
    """ESM/ECM outrigger — SLQ-32 scale — on a stub sponson at the bridge.

    docs/02 makes jamming a pillar. A ship that can see an emitter and a ship
    that can burn one down have to look different, and the only honest place
    to say so is the pair of boxes carried out past the bridge face where the
    real ones sit. Two objects: a body bracket and a near-black array face,
    and `x` picks the side.
    """
    s = 1.0 if x > 0 else -1.0
    out = []
    use("body")
    out.append(cube((x, y, z + h * 0.50), (1.15, l, h)))
    with mat("gunbore"):
        out.append(cube((x + s * 0.62, y, z + h * 0.56),
                        (0.24, l * 0.80, h * 0.70)))
    use("body")
    return out


def bridge_wing(x, y, z, l=3.6, w=2.8, gun=False, name="bw"):
    """The open bridge wing that overhangs the ship's side, and optionally the
    light 25 mm mount on the end of it. One or two objects, and it is what
    stops a bridge tier reading as a shoebox."""
    s = 1.0 if x > 0 else -1.0
    out = []
    with mat("deck"):
        out.append(cube((x, y, z + 0.13), (w, l, 0.26)))
    if gun:
        with mat("gun"):
            out.append(cyl((x + s * w * 0.22, y, z + 0.75), 0.42, 1.20, v=8))
    return out


def chaff_launcher(x, y, z, yaw=0.0, elev=45.0, name="chaff"):
    """Mk 36 SRBOC decoy mortar: six barrels in a trainable box, canted up and
    outboard. One object, and decoys are a docs/02 counter-measure rung."""
    with mat("gun"):
        return [cube((x, y, z + 0.72), (1.35, 1.10, 1.45),
                     rot=(R(-elev), 0, R(yaw)))]


def deck_panel(x, y, z, w, l, group="gunbore", h=0.20, name="pnl"):
    """One flat contrasting rectangle on a weather deck — a hatch, an ammo
    handling square, a sonobuoy stowage, a VERTREP spot.

    Measured: a plain box in `gunbore` costs 188 triangles and is the only
    kind of detail in this file that still reads at 1.1 px per metre, because
    it is a material step and not a shape. Twelve liferafts cost sixteen times
    as much and read at none — which is why the three escorts now carry fewer
    rafts and more panels.
    """
    with mat(group):
        return [cube((x, y, z + h * 0.5), (w, l, h))]


def anchor_gear(y, z, B, name="anc"):
    """Windlass, and the chain runs from it to the hawse. Three small dark
    objects on what is otherwise the emptiest deck on any escort — the
    forecastle — and they cost less than one liferaft each."""
    out = []
    with mat("gun"):
        out.append(cyl((0.0, y, z + 0.55), 0.90, 1.10, v=10))
    with mat("gunbore"):
        for s in (-1, 1):
            out.append(cube((s * B * 0.135, y - 3.4, z + 0.11),
                            (1.25, 6.6, 0.22)))
    return out


def satcom(x, y, z, r=1.35, name="sat"):
    """A SATCOM radome: one light dot high on a dark structure.

    v=8, NOT the dome() default of 24 and not even 12. Measured after the LOD0
    bevel: v=12 costs 1 152 triangles and v=8 costs 512, for a 1.4 m ball that
    is three pixels across at the game camera. A sphere is the worst value in
    the file because the bevel fires on every one of its edges — two of these
    at v=12 cost more than the whole 155 m destroyer hull."""
    with mat("deck"):
        return [dome((x, y, z + r * 0.22), r, r, r * 0.92, v=8)]


def tube_sponson(x, y, z, w=4.6, l=7.4, name="spn"):
    """A platform carried outboard of the hull line for the ASW torpedo tubes.

    The frigate's, and only the frigate's. In plan it is a light plate and a
    black shadow panel standing PROUD of the hull outline at one station
    amidships — the hull visibly gets wider there — and no other escort's
    outline does anything but taper. That is a position feature, which is the
    only kind that survives the zoom test.
    """
    s = 1.0 if x > 0 else -1.0
    out = []
    with mat("deck"):
        out.append(cube((x, y, z + 0.14), (w, l, 0.28)))
    with mat("gunbore"):
        out.append(cube((x + s * w * 0.10, y, z - 0.55), (w * 0.80, l * 0.86,
                                                          1.10)))
    return out


def towed_array(y, z, w=8.6, name="ta"):
    """Towed-array handling at the transom: the winch drum athwartships, the
    cable chute cut dark into the deck, and the fairlead sheaves.

    docs/02 section 8 makes passive towed-array search the ASW pillar, and it
    is the one piece of ASW equipment big enough to see from the game camera.
    Four objects, all of them on the last four metres of the ship, where no
    other escort has anything at all.
    """
    out = []
    use("body")
    out.append(cube((0.0, y + 1.10, z + 1.15), (w * 0.52, 2.20, 2.30)))
    with mat("gunbore"):
        out.append(cyl((0.0, y + 1.10, z + 1.55), 1.05, w * 0.66,
                       rot=(0, R(90), 0), v=14))
        out.append(cube((0.0, y - 1.30, z + 0.12), (w * 0.34, 2.60, 0.24)))
    with mat("deck"):
        out.append(cube((0.0, y - 0.30, z + 0.75), (w, 0.70, 1.50)))
    use("body")
    return out


# ══ surface combatants ═════════════════════════════════════════════
def destroyer_aaw():
    """Arleigh Burke Flight IIA — 155.3 x 20.1 m, draught 9.4 m, 5.9 m of
    freeboard amidships and 2.4 m of sheer to the forecastle.

    EXCLUSIVE FEATURE: four canted planar arrays on ONE pyramidal forward
    deckhouse, plus twin close-coupled centreline funnels. The cruiser splits
    its arrays fore and aft and the frigate has none, so the cluster is
    unambiguous.

    DECK SIGNATURE, which is the part that survives the zoom test: a SMALL
    32-cell farm on the forecastle and a LARGE 64-cell farm amidships-aft.
    Asymmetric, and neither of them at an extremity — that is what separates
    it from the cruiser, whose two equal farms sit at the very ends.

    THREE PLACEMENT BUGS FIXED IN THIS PASS, all of them found by rendering
    the ship alone from the beam instead of trusting the source:

      * THE MAST WAS FLOATING. It was placed at y = 0.015L with its base at
        the height the three-tier superstructure reached at y = 0.11L, and
        those are 16 m apart, so the whole 15 m mast hung in clear air nine
        metres above the deckhouse roof with sky under it. It now stands on
        the SPY deckhouse roof, abaft the pilothouse, where a Burke's does.
      * THE FORWARD CIWS WAS INSIDE THE PILOTHOUSE. Same cause: a height
        taken from `top` and a station taken from a different tier.
      * THE OWNERSHIP PATCH WAS UNDER THE AFT VLS COAMING. CONVENTIONS.md
        requires one patch visible from directly above; this one was covered
        by a 9.3 m slab of near-black. It is now on the hangar roof, which is
        the largest uninterrupted horizontal surface on the ship.

    Also: the hangar was 26 m at -0.300L and the flight deck 20 m at -0.425L,
    which overlapped by 3.6 m, so the forward fifth of the flight deck was
    inside the hangar. Both were re-stationed off the transom instead of off
    round fractions of L.

    The layered-defence ship of docs/02 section 8.6: 96 cells in two farms,
    three illuminators, two CIWS, a 5-inch mount, twin hangars and a helipad.
    """
    L, B, FB, SH = 155.3, 20.1, 5.9, 2.4
    p, fb = ship_hull(L, B, FB, bow=0.30, sheer=SH)

    # ── the pyramidal forward deckhouse ─────────────────────────────
    # 01 level -> SPY deckhouse -> pilothouse. The arrays go on the middle
    # tier's four corners, which is what makes the mass read as one pyramid
    # with faces on it rather than as two boxes.
    sup, top = superstructure(L * 0.105, fb,
                              ((50.0, 16.8, 6.4), (34.0, 14.4, 4.8, 2.0),
                               (21.0, 11.2, 4.4, 4.0)), taper=0.92)
    p += sup                                        # top = fb + 15.6
    z_01, z_spy, z_bridge = fb + 6.4, fb + 11.2, fb + 15.6

    for s in (-1, 1):                               # the exclusive: four faces
        p += planar_array(s * 6.5, 30.0, z_spy - 2.3, 5.0, 4.6, 26, s * 32)
        p += planar_array(s * 6.5, 6.5, z_spy - 2.3, 5.0, 4.6, 26, -s * 148)

    # mast on the SPY deckhouse roof, abaft the pilothouse — see the note
    p += lattice_mast(0, 6.0, z_spy, 22.0, foot=4.6, head=1.5, solid=True,
                      yards=((0.40, 12.0), (0.66, 7.6)), radome=2.0)

    # ── the after deckhouse, which is what the funnels stand on ──────
    # Stationed off the aft VLS coaming, not off a round fraction of L: at
    # 30 m and -0.070L its after face landed at -23.0 and buried 2.6 m of the
    # 9.3 m farm, which is the same class of bug as the hangar overlap.
    p.append(deckhouse(-L * 0.058, 28.0, 13.0, 5.2, fb))
    z_aft = fb + 5.2
    p += funnel(0, L * 0.005, fb + 2.6, 9.0, 7.6, 8.2, rake=8)
    p += funnel(0, -L * 0.113, fb + 2.6, 9.0, 7.6, 8.2, rake=8)
    for s in (-1, 1):
        p += satcom(s * 4.6, -19.5, z_aft, 1.45)

    # ── aviation, re-stationed off the transom ──────────────────────
    p += hangar(-L * 0.296, 22.0, 13.6, 6.4, fb, doors=2)   # -57.0 .. -35.0
    p += helipad(-L * 0.431, 13.2, 20.0, fb)                # -77.0 .. -57.0

    # ── sensors and directors: three Mk 99, which is the AAW capacity ──
    p += director(0, 24.0, z_bridge, 1.30)
    p += director(0, 13.5, z_bridge, 1.30)
    p += director(0, -37.5, fb + 6.4, 1.30, aft=True)        # hangar roof
    for s in (-1, 1):
        p += esm_array(s * 7.9, 24.0, z_spy)
        p += bridge_wing(s * 7.0, 27.0, z_bridge, gun=True)
        p += chaff_launcher(s * 7.6, 14.0, z_01, yaw=s * 30)

    # ── armament ─────────────────────────────────────────────────────
    p += vls(0, L * 0.315, fb + SH, 4, 8)               # 32 cells, forecastle
    p += vls(0, -L * 0.180, fb, 8, 8)                   # 64 cells, aft of the
    p += gun_mount(L * 0.393, fb + SH, r=2.05, barrel_l=6.6)   # after house
    p += breakwater(L * 0.345, B * 0.72, fb + SH)
    p += anchor_gear(L * 0.438, fb + SH, B)
    p += ciws(0, 20.0, z_bridge, 1.10)                  # on the pilothouse
    p += ciws(0, -L * 0.310, fb + 6.4, 1.10, aft=True)  # on the hangar
    for s in (-1, 1):
        p += boat_bay(s * B * 0.47, -L * 0.045, fb)
        p += torpedo_tubes(s * B * 0.30, -L * 0.150, fb + 0.4, yaw=s * 55)

    # Liferafts thinned from 13 m spacing to 34 m. Sixteen of them cost 3 008
    # triangles and every one is a 1 m box that vanishes at the game camera;
    # the five that survive still break the deck edge, and the 2 900 saved
    # bought the three illuminators, the ESM outriggers and the anchor gear.
    p += clutter(hull_planform(L, B, w=0.90), fb, spacing=34.0)
    p.append(team_patch(-L * 0.275, fb + 6.4, 4.4, 5.2))     # hangar roof
    return p, ship_meta(L, B, fb, z_spy + 22.0, gun_y=L * 0.40,
                        gun_z=fb + SH + 2.6)


def cruiser():
    """Ticonderoga CG-52 — 172.8 x 16.8 m, draught 10.2 m, freeboard 5.6 m.

    EXCLUSIVE FEATURE: a 5-inch turret at BOTH ends. It is the only ship in
    the roster with a stern main gun, and the pair of fore-and-aft
    superstructure islands that carry its two array faces makes the hull read
    symmetric from overhead, which no other escort does.

    Against the destroyer the fact that survives the zoom test is that the
    cruiser's two dark deck patches sit at the EXTREME ends and are EQUAL in
    size, where the destroyer's are unequal and inboard.

    Longer and 3.3 m narrower than the destroyer — L/B 10.3 against 7.7 — so
    even before the armament the planform is a different animal.

    FIXED THIS PASS, all three found on a beam render of the ship alone:
    BOTH MASTS WERE FLOATING (the fore mast by 8.6 m, the main by 4.4 m, each
    for the same reason as the destroyer's — a height from `top` and a station
    from a different tier); the forward CIWS was buried inside the pilothouse;
    and the ownership patch at -0.100L sat inside the after superstructure's
    footprint and could not be seen from any angle.

    WHAT SEPARATES IT FROM THE DESTROYER AT CLOSE RANGE: the cruiser keeps an
    OPEN lattice fore mast and carries a rotating SPS-49 air-search slab,
    because it is a 1980s design; the Burke has a solid plated pyramid and no
    rotating antenna at all. Four illuminators against the Burke's three is
    the doctrinal difference — this is the ship that can hold four engagements
    at once, and docs/02 section 8.6 makes that a number, not a look.
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
    z_01, z_spy, z_bridge = fb + 7.0, fb + 11.6, fb + 15.6
    z_a01, z_amid = fb + 6.2, fb + 10.6

    for s in (-1, 1):
        p += planar_array(s * 5.6, 29.5, fb + 9.8, 4.4, 4.2, 24, s * 30)
        p += planar_array(s * 5.4, -L * 0.245, fb + 9.0, 4.4, 4.2, 24, s * 150)

    # Fore mast is a PLATED tower on the SPY deckhouse roof abaft the
    # pilothouse, which is what CG-52 carries; the main mast on the after
    # island is the open lattice, and the SPS-49 slab stands beside it.
    #
    # MEASURED, AND IT IS WHY THE FORE MAST IS PLATED. Two open lattices cost
    # 42 objects and 11 000 triangles — a quarter of this ship — on the two
    # fittings the file's own zoom test says disappear first. Plating the
    # taller one gave back 4 700 and paid for four illuminators, the ESM
    # outriggers, the air-search slab and the anchor gear.
    p += lattice_mast(0, 7.5, z_spy, 18.0, foot=3.4, head=1.1, solid=True,
                      yards=((0.50, 12.0), (0.78, 7.4)), radome=1.7)
    p += lattice_mast(0, -33.5, z_amid, 12.5, foot=2.4, head=0.9, bays=2,
                      yards=((0.58, 8.0),), name="mainmast")
    p += air_search(0, -27.5, z_amid, 7.2, 2.8)

    for s in (-1, 1):                                   # staggered funnels
        p += funnel(s * 4.6, -L * 0.045 - s * L * 0.055, fb + 2.4, 8.6, 6.2,
                    7.8, rake=9, name=f"fnl{s}")

    # four illuminators — two forward, two aft. This is the number.
    p += director(0, 24.0, z_bridge, 1.25)
    p += director(0, 29.0, z_spy, 1.25)
    for s in (-1, 1):
        p += director(s * 4.0, -38.0, z_amid, 1.25, aft=True)
        p += esm_array(s * 7.4, 22.0, z_01)
        p += bridge_wing(s * 6.0, 25.0, z_bridge, gun=True)
        p += chaff_launcher(s * 6.2, 10.0, z_01, yaw=s * 30)
        p += satcom(s * 4.2, -3.2, z_01, 1.30)

    p += vls(0, L * 0.305, fb + SH, 8, 8)
    p += vls(0, -L * 0.355, fb, 8, 8)
    p += gun_mount(L * 0.386, fb + SH, r=1.95, barrel_l=6.4)
    p += gun_mount(-L * 0.300, fb, r=1.95, barrel_l=6.4, aft=True)
    p += breakwater(L * 0.340, B * 0.70, fb + SH)
    p += anchor_gear(L * 0.435, fb + SH, B)
    p += ciws(0, 15.0, z_bridge, 1.05)
    p += ciws(0, -L * 0.130, z_a01, 1.05, aft=True)
    p += helipad(-L * 0.440, 11.6, 16.0, fb)
    for s in (-1, 1):
        p += boat_bay(s * B * 0.47, -L * 0.010, fb, l=6.8)
        p += torpedo_tubes(s * B * 0.30, -L * 0.090, fb + 0.4, yaw=s * 55)
    p += clutter(hull_planform(L, B, transom=0.82, w=0.90), fb, spacing=34.0)
    p.append(team_patch(-10.3, fb, 4.0, 6.0))       # open deck between islands
    return p, ship_meta(L, B, fb, z_spy + 18.0, gun_y=L * 0.39,
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

    THE ASW FIT, WHICH IS THE POINT OF THIS SHIP AND HAS TO BE VISIBLE FROM
    DIRECTLY ABOVE (docs/02 section 8). Three things carry it, and all three
    are deck-plan features in a contrasting material, which is the only kind
    that survives the zoom test:

      TWO marked helicopter spots on one flight deck. The destroyer and the
      cruiser have one circle each; this ship hangars two LAMPS airframes and
      shows two, and a pair of circles is the loudest thing on the after
      third of any escort in the roster.

      TORPEDO-TUBE SPONSONS standing PROUD of the hull line amidships. In
      plan the hull visibly gets WIDER at one station — a light plate with a
      black shadow under it, outboard of the deck edge — and every other
      escort's outline does nothing but taper from amidships to the transom.

      TOWED-ARRAY HANDLING on the last four metres before the transom: the
      winch drum athwartships, the cable chute cut dark into the deck. No
      other escort has anything abaft its flight deck.

    FIXED THIS PASS: the mast floated 4.2 m above the deckhouse (same bug as
    both other escorts); the air-search slab was standing inside the funnel;
    and the 30 m hangar at -0.275L overlapped the 24 m flight deck at -0.415L
    by 7.7 m, so a third of the flight deck was inside the hangar and did not
    render, while the deck's after edge overhung the transom by 0.25 m. Both
    are now stationed off the transom.

    6.4 m narrower than the destroyer over nearly the same length.
    """
    L, B, FB, SH = 138.1, 13.7, 4.6, 2.0
    p, fb = ship_hull(L, B, FB, bow=0.32, transom=0.78, sheer=SH)
    sup, top = superstructure(-L * 0.010, fb,
                              ((52.0, 11.6, 5.8), (24.0, 9.2, 4.2, 8.0),
                               (13.0, 7.0, 3.2, 10.0)), taper=0.92)
    p += sup
    z_01, z_02, z_bridge = fb + 5.8, fb + 10.0, fb + 13.2

    p += arm_launcher(0, L * 0.330, fb + SH)            # Mk13, the exclusive
    p += gun_mount(-L * 0.055, z_01, r=1.35, barrel_l=4.6)   # gun on the roof
    # foot widened from 2.6 to 3.6 and a platform added: at 2.6 m over 18 m
    # of height this read as a stick, and rule 3 of the brief is that a ship
    # with a stick mast reads as a barge.
    p += lattice_mast(0, -1.0, z_02, 18.0, foot=3.6, head=1.2, bays=3,
                      yards=((0.52, 9.4), (0.80, 6.0)), radome=1.5,
                      platform=2.6)
    p += air_search(0, -10.0, z_01, 7.0, 2.8)           # clear of the funnel
    p += funnel(0, -L * 0.135, fb + 2.2, 8.0, 5.6, 7.0, rake=10)
    p += ciws(0, -L * 0.330, fb + 6.0, 1.05, aft=True)

    # aviation, stationed off the transom (-69.05) instead of off L
    p += hangar(-L * 0.245, 21.0, 12.2, 6.0, fb, doors=2)   # -44.3 .. -23.3
    p += helipad(-L * 0.410, 12.4, 22.0, fb)                # -67.6 .. -45.6
    p += director(0, -27.0, fb + 6.0, 1.50, aft=True)       # Mk 92 STIR
    p += deck_panel(0, -34.0, fb + 6.0, 4.4, 5.0, group="gunbore")

    # the second marked spot. helipad() lays the black deck and one circle;
    # this is the other one, and it is the frigate's loudest plan feature.
    with mat("deck"):
        p.append(cyl((0, -61.5, fb + 0.30), 3.95, 0.10, v=24))
    with mat("gunbore"):
        p.append(cyl((0, -61.5, fb + 0.37), 3.10, 0.10, v=24))
    with mat("deck"):
        p.append(cube((0, -55.0, fb + 0.30), (0.55, 5.6, 0.10)))
    with mat("gunbore"):                                # RAST haul-down track
        p.append(cube((0, -56.6, fb + 0.30), (0.7, 20.0, 0.16)))

    p += towed_array(-L * 0.492, fb, 8.6)               # -67.9, at the transom

    for s in (-1, 1):
        p += tube_sponson(s * (B * 0.50 + 1.9), -L * 0.060, fb)
        p += torpedo_tubes(s * (B * 0.50 + 0.6), -L * 0.060, fb + 0.4,
                           yaw=s * 62)
        p += esm_array(s * 5.9, 12.0, z_02)
        p += bridge_wing(s * 5.4, 15.0, z_bridge, gun=True)
        p += chaff_launcher(s * 5.4, 4.0, z_01, yaw=s * 30)
        p += boat_bay(s * B * 0.47, L * 0.075, fb, l=6.4)

    p += breakwater(L * 0.395, B * 0.68, fb + SH)
    p += anchor_gear(L * 0.440, fb + SH, B)
    p += clutter(hull_planform(L, B, bow=0.32, transom=0.78, w=0.90), fb,
                 spacing=30.0)
    p.append(team_patch(L * 0.240, fb + SH, 3.6, 5.4))      # bare forecastle
    return p, ship_meta(L, B, fb, z_02 + 18.0, gun_y=-L * 0.02, gun_z=fb + 7.4)


def corvette():
    """Braunschweig K130 — 89.1 x 13.3 m, draught 3.4 m, freeboard 3.9 m.

    EXCLUSIVE FEATURE: two inclined box canister packs sitting athwartships
    amidships. Small, fast, cheap: anti-ship missiles and not much else.

    DETAIL PASS. The corvette sits between the missile boat and the frigate and
    was collapsing toward the missile boat, because both were a two-tier box
    with a mast. Three things separate it now and all three are deck-plan facts:

      THREE TIERS, NOT TWO. The K130 carries its bridge a full 10 m over the
      main deck. superstructure() now gets a pilothouse tier with the glass on
      it and bridge wings cantilevered either side in `deck`, so the light
      cross-bar of the wings sits where the missile boat has nothing.

      THE WAIST IS NO LONGER BARE. Between the funnel and the flight deck the
      hull ran 9 m of empty grey. It now carries a light boat/UAV house with a
      dark door in its after face, and the canister packs have moved aft to
      -0.095L so they stand clear of the deckhouse bulkhead they were touching.

      DARK DECK PUNCTUATION. Three `gunbore` hatch rectangles — two on the
      raised forecastle either side of the breakwater, one on the waist. At the
      escort zoom these are the only marks forward of the bridge on a hull
      whose forecastle is otherwise as empty as the frigate's, and they read as
      a corvette's crowded working deck rather than an escort's clear one.

    PAID FOR by walking clutter() at 12.5 m instead of 9 m: the liferaft run is
    a texture, not a feature, and a third fewer of them is invisible.
    """
    L, B, FB, SH = 89.1, 13.3, 3.9, 1.5
    p, fb = ship_hull(L, B, FB, bow=0.30, transom=0.80, sheer=SH)
    sup, top = superstructure(L * 0.085, fb,
                              ((28.0, 10.2, 4.4), (18.0, 8.4, 3.2, 0.6),
                               (9.6, 6.2, 2.8, 1.8)),
                              taper=0.86)
    p += sup
    with mat("deck"):                                   # bridge wings
        for s in (-1, 1):
            p.append(cube((s * 4.05, L * 0.085 + 3.2, fb + 7.85),
                          (2.6, 3.4, 0.50)))
    p += lattice_mast(0, L * 0.070, top, 8.4, foot=2.2, head=0.8, bays=3,
                      solid=True, yards=((0.50, 6.4),), radome=1.3)
    p += ciws(0, -L * 0.012, fb + 7.6, 0.90)
    use("body")                                         # funnel casing
    p.append(deckhouse(-L * 0.150, 12.0, 6.6, 2.2, fb, 0.92, "cv_cas"))
    p += funnel(0, -L * 0.155, fb + 2.2, 6.0, 4.4, 5.2, rake=10, uptakes=1)
    with mat("gunbore"):                                # the missile deck
        p.append(cube((0, -L * 0.095, fb + 0.30), (B * 0.92, 8.8, 0.44)))
    for s in (-1, 1):                                   # the exclusive
        p += canisters(s * 3.85, -L * 0.095, fb + 0.7, n=2, l=6.4, w=1.9,
                       h=1.7, elev=16, yaw=s * 12, name=f"can{s}")
    p += gun_mount(L * 0.335, fb + SH, r=1.45, barrel_l=4.2)
    p += breakwater(L * 0.240, B * 0.66, fb + SH)
    for s, y in ((-1, L * 0.290), (1, L * 0.290), (1, -L * 0.130)):
        with mat("gunbore"):                            # deck hatches
            p.append(cube((s * (B * 0.235 if y > 0 else B * 0.370), y,
                           fb + (SH if y > L * 0.045 else 0.0) + 0.15),
                          (2.0, 2.8, 0.30)))
    with mat("deck"):                                   # boat / UAV house
        p.append(cube((0, -L * 0.245, fb + 1.45), (8.2, 8.6, 2.9)))
    with mat("gunbore"):
        p.append(cube((0, -L * 0.293, fb + 1.30), (4.6, 0.34, 2.2)))
    with mat("deck"):                                   # RAM box, fore and aft
        p.append(cube((0, L * 0.205, fb + 5.30), (3.2, 2.4, 1.8),
                      rot=(R(-22), 0, 0)))
        p.append(cube((0, -L * 0.219, fb + 3.75), (3.0, 2.2, 1.7),
                      rot=(R(20), 0, 0)))
    p += helipad(-L * 0.375, 9.4, 12.4, fb)
    p += clutter(hull_planform(L, B, transom=0.80, w=0.88), fb, spacing=12.5,
                 size=(0.9, 1.6, 0.75))
    p.append(team_patch(-L * 0.269, fb + 2.90, 3.0, 3.6))
    use("body")
    return p, ship_meta(L, B, fb, top + 8.4, gun_y=L * 0.34, gun_z=fb + SH + 1.9)


def missile_boat():
    """Project 1241 Tarantul III — 56.1 x 10.2 m, draught 2.5 m, freeboard
    3.0 m. Coastal denial; Taiwan and the KPA lean on these.

    EXCLUSIVE FEATURE: four heavy CYLINDRICAL anti-ship tubes mounted on the
    deck edge, angled outboard and overhanging the side. The corvette owns the
    box canister; this owns the round tube, and from overhead the two never
    look alike.

    DETAIL PASS, AND IT HAD THE LEAST ROOM OF THE FIVE SMALL CRAFT (+724).
    Everything below is paid for, not added:

      SPENT. A pilothouse tier so the boat steps bridge-over-house like the
      corvette rather than sitting under one flat lid; light bridge wings; the
      after AK-630 lifted onto a light `deck` gun tub instead of standing on
      the bare deck; a breakwater on the short forecastle; and — the one thing
      that reads from directly overhead — TWO DARK GAS-TURBINE UPTAKE PORTS CUT
      INTO THE TRANSOM. A Tarantul exhausts through the stern, not a funnel,
      and no other hull in the roster has a dark mark ON its transom, so the
      boat now terminates in something instead of trailing off.

      SAVED. clutter() at 15 m instead of 8 m, and the lattice at two bays
      instead of three. It is still an OPEN lattice, because this is a 1980s
      Soviet hull and the see-through mast is half of why it does not look like
      the corvette, which carries a solid pyramid.
    """
    L, B, FB = 56.1, 10.2, 3.0
    p, fb = ship_hull(L, B, FB, bow=0.34, transom=0.84, sheer=1.1)
    sup, top = superstructure(L * 0.075, fb,
                              ((17.5, 7.4, 4.0), (11.0, 6.0, 2.8, 0.6),
                               (5.6, 4.2, 2.4, 1.9)),
                              taper=0.84)
    p += sup
    with mat("deck"):                                   # bridge wings
        for s in (-1, 1):
            p.append(cube((s * 2.95, L * 0.075 + 2.6, fb + 7.05),
                          (2.0, 2.6, 0.44)))
    p += lattice_mast(0, L * 0.105, top, 7.0, foot=1.8, head=0.7, bays=2,
                      yards=((0.55, 5.0),), radome=1.1)
    for s in (-1, 1):                                   # the exclusive
        p += missile_tubes(s * (B * 0.42), -L * 0.090, fb + 0.9, n=2, l=7.4,
                           r=0.88, elev=11, yaw=s * 9, name=f"tube{s}")
    p += gun_mount(L * 0.335, fb + 1.1, r=1.05, barrel_l=3.0)
    p += breakwater(L * 0.245, B * 0.62, fb + 1.1, h=0.95)
    with mat("deck"):                                   # AK-630 gun tub
        p.append(cyl((0, -L * 0.355, fb + 0.55), 2.05, 1.10, v=10))
    p += ciws(0, -L * 0.355, fb + 1.1, 0.85, aft=True)
    with mat("gunbore"):                                # turbine uptakes, transom
        for s in (-1, 1):
            p.append(cube((s * B * 0.21, -L * 0.5015, fb - 0.95),
                          (2.5, 0.72, 1.7)))
    p += clutter(hull_planform(L, B, bow=0.34, transom=0.84, w=0.86), fb,
                 spacing=15.0, size=(0.8, 1.4, 0.7))
    p.append(team_patch(-L * 0.235, fb, 2.4, 3.0))
    use("body")
    return p, ship_meta(L, B, fb, top + 7.0, gun_y=L * 0.34, gun_z=fb + 2.1)


def patrol_vessel():
    """Cyclone-class PC — 54.6 x 7.6 m, draught 2.4 m, freeboard 2.9 m.
    Presence, escort, cheap eyes with a gun.

    EXCLUSIVE FEATURE: a notched transom with a stern boat ramp and a RHIB
    sitting in it. It is the only hull in the roster whose stern is cut open,
    and at any zoom the notch breaks the rectangle of the after deck.

    DETAIL PASS, DELIBERATELY THE LIGHTEST OF THE FIVE. This boat's job in the
    roster is to be the bare one — if it grows as much furniture as the
    corvette then the corvette stops meaning anything. So it gets structure,
    not weapons:

      A pilothouse tier and bridge wings, so the profile steps three times over
      a 55 m hull and reads as tall-for-its-length, which is exactly what a
      Cyclone looks like from abeam.
      FOUR .50-cal / Mk38 gun tubs — light `deck` rings at the bridge-wing
      corners and either side of the after deck. A Cyclone is a gun boat and
      the tubs are the only thing on its weather deck.
      Two dark side exhaust ports amidships: a Cyclone has no funnel at all,
      which is why the waist looked unfinished, and a pair of dark rectangles
      low on the hull side is what is actually there.
      A breakwater, and a platform on the mast for the surface-search set.

    Paid for with clutter() at 12.5 m instead of 8 m and the mast at two bays
    instead of three; the boat had +2 584 and lands at 13 896. It is still the
    emptiest deck in the roster and that is the point.
    """
    L, B, FB = 54.6, 7.6, 2.9
    p, fb = ship_hull(L, B, FB, bow=0.30, transom=0.90)
    sup, top = superstructure(L * 0.055, fb,
                              ((19.0, 6.4, 4.0), (11.0, 5.2, 2.8, 0.8),
                               (5.4, 3.8, 2.2, 1.9)),
                              taper=0.86)
    p += sup
    with mat("deck"):                                   # bridge wings
        for s in (-1, 1):
            p.append(cube((s * 2.65, L * 0.055 + 2.4, fb + 6.95),
                          (1.9, 2.4, 0.42)))
    p += lattice_mast(0, -L * 0.022, fb + 6.8, 6.2, foot=1.6, head=0.6, bays=2,
                      yards=((0.56, 4.4),), radome=1.0, platform=1.15)
    with mat("gunbore"):                                # the exclusive: the notch
        p.append(cube((0, -L * 0.455, fb - 0.6), (B * 0.52, L * 0.14, 2.6),
                      rot=(R(-9), 0, 0)))
    with mat("deck"):
        o = profile([(-L * 0.360, fb + 0.1), (-L * 0.470, fb - 0.35),
                     (-L * 0.462, fb + 0.75), (-L * 0.365, fb + 0.95)],
                    2.30, "pc_rhib")
        p.append(o)
    p += gun_mount(L * 0.330, fb, r=1.00, barrel_l=2.6)
    p += breakwater(L * 0.245, B * 0.60, fb, h=0.85)
    with mat("deck"):                                   # four gun tubs
        for x, y, z in ((-2.65, L * 0.070, fb + 7.16), (2.65, L * 0.070, fb + 7.16),
                        (-B * 0.30, -L * 0.185, fb), (B * 0.30, -L * 0.185, fb)):
            p.append(cyl((x, y, z + 0.45), 1.25, 0.90, v=12))
    with mat("gun"):
        for s in (-1, 1):
            p.append(cyl((s * B * 0.30, -L * 0.185, fb + 1.35), 0.42, 1.5, v=10))
    with mat("gunbore"):                                # side exhaust ports
        for s in (-1, 1):
            p.append(cube((s * B * 0.485, -L * 0.075, fb - 1.15),
                          (0.60, 3.4, 1.15)))
    p += clutter(hull_planform(L, B, transom=0.90, w=0.84), fb, spacing=12.5,
                 size=(0.75, 1.3, 0.65))
    p.append(team_patch(-L * 0.290, fb, 2.2, 2.8))
    use("body")
    return p, ship_meta(L, B, fb, fb + 13.0, gun_y=L * 0.33, gun_z=fb + 1.3)


# ══ submarines ═════════════════════════════════════════════════════
def sub_diesel():
    """Type 209/1400 — 62.0 x 6.2 m, published draught 5.5 m; the round hull
    stands 1.20 m proud when surfaced and shows 4.90 m wide in plan. Quiet on
    the battery, loud snorkelling (docs/11 Q1).

    EXCLUSIVE FEATURE: the snorkel induction and diesel exhaust masts raised
    abaft the sail, standing on a light induction housing that sits at 0.01 L —
    dead amidships, where no other boat has a bright mark. It is the only boat
    here showing masts that are not on the sail centreline, and snorkelling is
    the thing that gets it killed.

    The 209's fin is visibly STEPPED, so this is the boat that takes sail(step=).
    """
    L, B, FB = 62.0, 6.2, 1.20            # published draught 5.5 m to the keel
    assert sub_show_width(B, FB) > B * 0.52
    p, axis, deck = sub_hull(L, B, FB, name="ssk")
    p += casing(L * 0.32, -L * 0.34, B * 0.50, deck - 0.10)
    top = deck - 0.10 + 0.42                                    # casing crown
    p += sail(L * 0.20, 7.4, 3.6, B * 0.36, deck, planes=True, masts=2, step=1.1)
    p += sub_fittings([L * 0.250, -L * 0.125, -L * 0.250], top, r=0.50)
    with mat("deck"):                                     # the exclusive, part 1
        p.append(cube((0.0, -L * 0.010, top + 0.28), (B * 0.38, L * 0.120, 0.56)))
    with mat("gun"):                                      # the exclusive, part 2
        p.append(cyl((0.9, L * 0.020, top + 3.6), 0.24, 7.2, rot=(R(8), 0, 0), v=8))
        p.append(cyl((-0.9, L * 0.005, top + 3.1), 0.20, 6.2, rot=(R(8), 0, 0), v=8))
        p.append(cube((0.9, L * 0.050, top + 6.9), (0.6, 1.1, 0.5)))
    p += stern_planes(L, B, axis, "cross")
    p += propulsor(L, B, axis, "screw")
    p.append(team_patch(-L * 0.055, top, 1.6, 2.4))
    return p, ship_meta(L, B, deck, deck + 3.6 + 1.1 + 3.4, gun_y=L * 0.2,
                        gun_z=deck + 1.0)


def sub_nuclear():
    """Los Angeles 688i — 110.3 x 10.1 m, published draught 9.4 m; the round
    hull stands 1.90 m proud when surfaced and shows 7.89 m wide in plan. Fast
    and long-legged — and in epoch 2 NOISIER than the diesels it replaced
    (docs/11).

    EXCLUSIVE FEATURE: twelve vertical-launch tube caps in the bow casing, two
    rows of six forward of the sail. Nothing else underwater has a hatch grid.

    IT HAS NOW BEEN INVISIBLE TWICE AND FOR TWO DIFFERENT REASONS, so both are
    recorded. Pass 2 put the caps at deck - 0.02 with the casing spanning
    deck - 0.12 to deck + 0.30, so all twelve were buried inside it. Pass 3
    lifted them onto the casing but left them in `gunbore`, near black, on a
    casing that was then `deck` — visible, but only by luck. Pass 4 inverts the
    casing to near black, which would have buried them a third time, so they
    are now LIGHT `deck` caps: a bright twelve-dot grid on a black spine, the
    highest-contrast feature on any boat in the roster.

    They also have to fit. The casing narrows over its forward 11 per cent, so
    the grid runs from 0.308 L aft to 0.215 L, entirely inside the full-width
    part of the casing and clear of the walkway at x = +/-0.98.
    """
    L, B, FB = 110.3, 10.1, 1.90          # published draught 9.4 m to the keel
    assert sub_show_width(B, FB) > B * 0.44
    p, axis, deck = sub_hull(L, B, FB, name="ssn")
    p += casing(L * 0.40, -L * 0.32, B * 0.44, deck - 0.12, walk=0.40)
    top = deck - 0.12 + 0.42                                    # casing crown
    p += sail(L * 0.215, 11.6, 5.8, B * 0.32, deck, planes=True, masts=3)
    with mat("deck"):                                           # the exclusive
        for s in (-1, 1):
            for k in range(6):
                p.append(cyl((s * 1.50, L * 0.308 - k * 1.86, top + 0.11),
                             0.62, 0.22, v=10))
    p += sub_fittings([L * 0.335, -L * 0.020, -L * 0.155, -L * 0.255], top, r=0.70)
    p += sub_towed_array(L, B, axis, L * 0.10, -L * 0.25, side=1)
    p += stern_planes(L, B, axis, "cross")
    p += propulsor(L, B, axis, "screw")
    p.append(team_patch(-L * 0.085, top, 2.2, 3.2))
    return p, ship_meta(L, B, deck, deck + 5.8 + 3.4, gun_y=L * 0.2,
                        gun_z=deck + 1.0)


def sub_aip():
    """Type 212A — 57.2 x 7.0 m, published draught 6.0 m; 1.30 m of hull
    proud when surfaced, showing 5.44 m wide in plan.
    Air-independent propulsion: near-silent at creep, the best ambusher and
    the worst pursuer in the game (docs/08, Germany).

    EXCLUSIVE FEATURE: an X-form stern — four canted planes and no cruciform
    rudder — with the two UPPER planes breaking the surface as light plates.
    See the honest correction in stern_planes(): from directly overhead the two
    upper planes project onto one athwartships bar and there is no diagonal
    cross to be seen. What separates the boat is that its transom carries two
    bright plates standing out of the water in a V where the three cruciform
    boats carry one thin dark fin.

    It is also the CLEAN boat: no launch caps, no induction housing, no
    outboard stores, two hatches and nothing else. Pass 3 had a pair of flank
    array panels on it in `gunbore`; measured, they sat at axis + 0.16 B, which
    on this boat is 1.08 m BELOW the sea, so they were 376 triangles of
    geometry no camera could ever see. Deleted.
    """
    L, B, FB = 57.2, 7.0, 1.30            # published draught 6.0 m to the keel
    assert sub_show_width(B, FB) > B * 0.44
    p, axis, deck = sub_hull(L, B, FB, name="aip")
    p += casing(L * 0.30, -L * 0.30, B * 0.44, deck - 0.10)
    top = deck - 0.10 + 0.42                                    # casing crown
    p += sail(L * 0.175, 6.6, 3.8, B * 0.30, deck, planes=False, masts=3)
    p += sub_fittings([L * 0.235, -L * 0.190], top, r=0.58)
    p += stern_planes(L, B, axis, "x", tip=B * 0.72, chord=L * 0.048,
                      tipcap=True)                                  # exclusive
    p += propulsor(L, B, axis, "pumpjet")
    p.append(team_patch(-L * 0.075, top, 1.6, 2.4))
    return p, ship_meta(L, B, deck, deck + 3.8 + 3.4, gun_y=L * 0.2,
                        gun_z=deck + 1.0)


def sub_midget():
    """Sang-O — 34.0 x 3.8 m, published draught 3.2 m; 0.80 m of hull proud
    when surfaced, showing 3.10 m wide in plan. The KPA's asymmetric tool:
    tiny acoustic signature, tiny range.

    EXCLUSIVE FEATURE: two external stores cradles clamped to the casing
    alongside the sail. It is the only boat that carries its weapons on the
    OUTSIDE, and the cradles sit at x = +/-1.67 where the hull only shows to
    1.55, so they OVERHANG the plan outline — the only boat in the roster whose
    silhouette is not a clean lozenge. That is what makes a 34 m hull
    identifiable at the small-craft zoom.
    """
    L, B, FB = 34.0, 3.8, 0.80            # published draught 3.2 m to the keel
    assert sub_show_width(B, FB) > B * 0.50
    p, axis, deck = sub_hull(L, B, FB, v=16, name="mid")
    p += casing(L * 0.26, -L * 0.30, B * 0.50, deck - 0.06, walk=0.38)
    top = deck - 0.06 + 0.42                                    # casing crown
    p += sail(L * 0.150, 3.0, 1.9, B * 0.34, deck, planes=False, masts=2)
    p += sub_fittings([L * 0.215, -L * 0.215], top, r=0.34, h=0.16, v=8)
    with mat("gun"):                                            # the exclusive
        for s in (-1, 1):
            p.append(cyl((s * B * 0.44, L * 0.02, deck - 0.05), 0.42, L * 0.30,
                         rot=(R(90), 0, 0), v=10))
            p.append(cube((s * B * 0.44, L * 0.12, deck - 0.22), (0.55, 0.30, 0.75)))
            p.append(cube((s * B * 0.44, -L * 0.10, deck - 0.22), (0.55, 0.30, 0.75)))
    p += stern_planes(L, B, axis, "cross")
    p += propulsor(L, B, axis, "screw")
    p.append(team_patch(-L * 0.055, top, 0.9, 1.5))
    return p, ship_meta(L, B, deck, deck + 1.9 + 2.4, gun_y=L * 0.2,
                        gun_z=deck + 0.6)


# ══ aviation, amphibious, fleet train ══════════════════════════════
# ══ capital-ship deck painting ═════════════════════════════════════
# Three helpers used only by carrier(), amphibious_assault() and
# fleet_oiler(). A capital ship's problem is the opposite of an escort's: it
# has ACRES of deck and almost nothing standing on it, so the empty area is
# not empty grey, it is 5 000 m2 of `body` camo checker. The fix is paint and
# openings, not more boxes — see the note at the top on why detail inside the
# `body` group does not read.
def _stripe(x0, y0, x1, y1, z, w=1.20, t=0.16, group="deck", name="stripe"):
    """One painted deck line between two deck points, as a flat bar.

    The cheapest read in the file: one box, 188 triangles after the LOD0
    bevel, in a material that is not the deck's. A 1.3 m line is 7 px on the
    plan sheet and survives to the 130 px zoom copy as a change in the deck's
    average tone, which is exactly what a real flight deck's markings do.

    ON A LIGHT DECK, DO NOT GO BELOW ABOUT 1.2 m WIDE, and the reason is not
    resolution. The LOD0 pipeline bakes an AO texture, and a 0.6 m bar lying
    flat on a deck is all crevice — it bakes dark, so the first cut of the
    carrier's tie-down grid came out as dark scratches on a light camo deck
    instead of paint, while the 2.6 m catapult tracks in the same pass read
    correctly light. Width, not the material's own brightness, separated them.
    On the BLACK `gunbore` areas — the angled deck, the amphib's landing lane
    — the constraint does not apply: the same AO darkening is invisible
    against near-black, and the 0.75 m arrestor wires and the 0.90 m lane
    centreline both read cleanly as light lines. Measured on both sheets."""
    dx, dy = x1 - x0, y1 - y0
    ln = math.hypot(dx, dy)
    with mat(group):
        return cube(((x0 + x1) / 2.0, (y0 + y1) / 2.0, z + t / 2.0),
                    (w, ln, t), rot=(0, 0, math.atan2(-dx, dy)))


def _deck_lift(x, y, z, w, l, name="lift"):
    """A deck-edge aircraft lift: a light platform inside a dark well.

    The platform on its own is a light rectangle on a camo deck and half of it
    dissolves into the checker at any distance. The dark coaming round it is
    what turns it into a hard-edged notch in the deck plan, and it is what the
    real thing looks like — the well surround is unpainted deck."""
    out = []
    with mat("gunbore"):
        out.append(cube((x, y, z + 0.10), (w + 2.6, l + 2.6, 0.46)))
    with mat("deck"):
        out.append(cube((x, y, z + 0.44), (w, l, 1.00)))
    return out


def _sponson(x_edge, y, z, out_w=5.6, l=12.0, brace=True, name="spn"):
    """A deck-edge sponson: a platform hung off the ship's side below deck.

    Every capital ship carries a row of them and no escort does, because an
    escort's deck edge IS its hull side. They earn their triangles in PLAN for
    a reason that has nothing to do with what stands on them: a 257-333 m
    dead-straight deck edge is the least ship-like line in the roster, and
    eight sponsons turn it into a dotted one."""
    out = []
    s = 1.0 if x_edge > 0 else -1.0
    with mat("deck"):
        out.append(cube((x_edge + s * out_w * 0.34, y, z + 0.35),
                        (out_w, l, 0.70)))
    if brace:
        use("body")
        for k in (-1, 1):
            out.append(strut((x_edge, y + k * l * 0.33, z - 3.6),
                             (x_edge + s * out_w * 0.66, y + k * l * 0.33,
                              z + 0.10), 0.52))
        use("body")
    return out


def carrier():
    """Nimitz CVN-68 — 332.8 m hull, 40.8 m at the waterline, 76.8 m across
    the flight deck, draught 11.3 m. The flight deck stands 19.6 m above the
    sea (hull to the hangar deck, then the hangar itself), which is why a
    carrier towers over an escort whose deck is at 5.9 m.

    EXCLUSIVE FEATURE: the angled landing deck, four catapult tracks and four
    deck-edge lifts.

    PASS 3 — WHAT WAS WRONG AND WHAT IT COST.

      The angled deck was a SLIVER. It was a quad whose two ends were 3 m and
      9 m apart in x, i.e. a tapering wedge about 6 m wide, on a ship whose
      real landing area is 24 m wide and 240 m long. On the plan sheet it read
      as a scratch. It is now a proper constant-width band, 24 m across, canted
      9.1 degrees, laid out off ONE parameterised axis (A0, A1, AX) so the
      wires, the foul lines and the two waist catapults cannot drift off it the
      way three hand-typed polygons do.

      The deck was EMPTY. Two-thirds of 24 000 m2 of flight deck carried
      nothing, and because the deck is built in `body` that is not empty grey,
      it is empty camo checker — the exact frequency the top of this file warns
      about. A real flight deck is not empty either: it is covered in paint.
      Paint costs 188 triangles a line here and it is in a different material
      group, which is the only thing that reads. The deck now carries the
      landing centreline, two foul lines, four cross-deck wires, four catapult
      tracks with their shuttle slots, a deck-edge safety line round the whole
      starboard side and bow, and tie-down bands in both parking areas.

      The lifts were bare platforms. Each now sits in a dark well, so it is a
      light rectangle with a hard dark border instead of a light rectangle
      fading into checker.

      The deck edge was a 333 m straight line. Eight sponsons now break it, and
      the three CIWS and two Sea Sparrow boxes stand on them where they belong
      instead of floating on the deck.

      There was a FUNNEL. On a nuclear carrier. Removed — Nimitz has no
      uptakes and no stack; the island is radar, exhaust-free, and taller than
      it was. The top-silhouette break that the funnel was doing is now done by
      a five-tier island and an 18 m masthead, which is what actually breaks a
      carrier's outline.

      The flight deck did not cover the bow. The hull's stem stood 2 m proud
      of the deck plate and rendered as a grey spike ahead of the ship. The
      deck now runs to L*0.502 and overhangs it, as the real bow does.
    """
    L, B, DECK_W, FD = 332.8, 40.8, 76.8, 19.6
    HDW = DECK_W * 0.5
    p, fb = ship_hull(L, B, FD, bow=0.22, transom=0.94, deck=False)
    use("body")
    FDECK = [(-HDW * 0.62, L * 0.452), (-HDW * 0.40, L * 0.502),
             (HDW * 0.14, L * 0.502), (HDW * 0.54, L * 0.404),
             (HDW * 0.82, L * 0.238), (HDW * 1.00, L * 0.030),
             (HDW * 1.00, -L * 0.500), (-HDW * 1.00, -L * 0.500),
             (-HDW * 1.00, -L * 0.040), (-HDW * 0.88, L * 0.196),
             (-HDW * 0.74, L * 0.352)]
    p.append(plate(FDECK, 1.8, fb + 0.9, "flightdeck"))
    fdz = fb + 1.8

    isl_x = HDW * 0.800                     # starboard, hard against the edge

    # ── the angled deck, laid out off one axis ─────────────────────
    # A0 is the landing centreline where it meets the round-down, A1 where it
    # runs out forward; 38.5 m of offset over 239 m is the real 9.1 degrees.
    A0, A1, HW = (-25.5, -L * 0.487), (12.5, L * 0.232), 12.0
    dl = math.hypot(A1[0] - A0[0], A1[1] - A0[1])
    ux, uy = (A1[0] - A0[0]) / dl, (A1[1] - A0[1]) / dl
    nx, ny = uy, -ux                       # unit normal, positive to starboard

    def AX(d, off=0.0):
        """A point d metres up the landing axis and off metres to starboard."""
        return (A0[0] + ux * d + nx * off, A0[1] + uy * d + ny * off)

    # The aft edge stops at -1.5 m, not -4.0. It is a canted edge, so its
    # starboard corner runs further aft than its port one, and at -4.0 that
    # corner stood 1.5 m past the transom — a black chip floating off the
    # stern in plan. Measured on the export: y now ends at exactly -166.400.
    with mat("gunbore"):
        p.append(plate([AX(-1.5, -HW), AX(dl + 5.0, -HW),
                        AX(dl + 5.0, HW), AX(-1.5, HW)],
                       0.20, fdz + 0.02, "angledeck"))
    # ONE height for every painted line on the ship. The first cut of this
    # pass laid them at fdz + 0.34 on a deck whose top is fdz, so each line
    # floated a third of a metre in the air and rendered as a light bar with
    # its own shadow printed beside it. PAINT_Z clears the angled deck's top
    # by 0.16 m and stands 0.10 m over the bare deck, which is a fifth of a
    # pixel on the plan sheet and nothing at the game camera.
    PAINT_Z = fdz + 0.10
    p.append(_stripe(*AX(10.0), *AX(dl - 8.0), PAINT_Z, 1.10, 0.18))  # centre
    for off in (-(HW - 1.5), HW - 1.5):                               # foul
        p.append(_stripe(*AX(4.0, off), *AX(dl + 2.0, off),
                         PAINT_Z, 0.90, 0.18))
    for d in (46.0, 58.5, 71.0, 83.5):                                # wires
        p.append(_stripe(*AX(d, -HW + 0.6), *AX(d, HW - 0.6),
                         PAINT_Z, 0.75, 0.18))
    p.append(_stripe(*AX(0.4, -HW + 0.4), *AX(0.4, HW - 0.4),
                     PAINT_Z, 1.60, 0.18))                            # ramp

    # ── four catapults: two on the bow, two on the waist ───────────
    CATS = (((-25.0, L * 0.185), (-20.6, L * 0.470)),
            ((-6.6, L * 0.185), (-2.6, L * 0.470)),
            (AX(70.0, -16.0), AX(166.0, -16.0)),
            (AX(70.0, -3.0), AX(166.0, -3.0)))
    for (a, b) in CATS:
        p.append(_stripe(a[0], a[1], b[0], b[1], PAINT_Z, 2.60, 0.18))
        p.append(_stripe(a[0], a[1], b[0], b[1], PAINT_Z + 0.14, 0.70, 0.18,
                         group="gunbore"))
        with mat("gunbore"):                            # jet blast deflector
            ang = math.atan2(-(b[0] - a[0]), b[1] - a[1])
            p.append(cube((a[0] - (b[0] - a[0]) * 0.045,
                           a[1] - (b[1] - a[1]) * 0.045, fdz + 1.20),
                          (15.5, 1.5, 2.40), rot=(R(-30), 0, ang)))

    # ── paint the parking areas, CLIPPED TO THE DECK ────────────────
    # First cut hand-typed the band ends as fractions of the half-width, and
    # on a deck whose starboard edge sweeps in from 1.00 to 0.54 of HDW over
    # the forward third, a band that fits amidships hangs 8 m over open water
    # at the bow. It rendered as five dark strokes lying on the sea. Both ends
    # of every band are now solved against FDECK and against the angled deck's
    # own edge lines, so a band exists only where there is deck to paint it on.
    def deck_x(y):
        """Port and starboard deck edge at this station, out of FDECK."""
        xs = []
        for i in range(len(FDECK)):
            (x0, y0), (x1, y1) = FDECK[i], FDECK[(i + 1) % len(FDECK)]
            if (y0 - y) * (y1 - y) < 0.0:
                xs.append(x0 + (x1 - x0) * (y - y0) / (y1 - y0))
        return (min(xs), max(xs)) if len(xs) >= 2 else (0.0, 0.0)

    def ang_x(y, off):
        """x where an angled-deck edge crosses this station, or None."""
        e0, e1 = AX(-1.5, off), AX(dl + 5.0, off)
        if not min(e0[1], e1[1]) <= y <= max(e0[1], e1[1]):
            return None
        return e0[0] + (e1[0] - e0[0]) * (y - e0[1]) / (e1[1] - e0[1])

    for k in range(23):
        yy = -L * 0.446 + k * 13.6
        px_, sx_ = deck_x(yy)
        if sx_ - px_ < 14.0:
            continue
        a, b = ang_x(yy, HW), ang_x(yy, -HW)
        lo = max(px_ + 3.2, a + 3.0 if a is not None else -1e9)
        hi = sx_ - 3.2
        if -34.0 < yy < 4.0 and hi > isl_x - 7.0:       # keep off the island
            hi = isl_x - 8.0
        if hi - lo > 7.0:
            p.append(_stripe(lo, yy, hi, yy, PAINT_Z, 1.30, 0.18))
        lo2, hi2 = px_ + 3.2, min(sx_ - 3.2,
                                  b - 3.0 if b is not None else 1e9)
        if hi2 - lo2 > 7.0:
            p.append(_stripe(lo2, yy, hi2, yy, PAINT_Z, 1.30, 0.18))
    cx_ = sum(x for x, _ in FDECK) / len(FDECK)         # deck-edge safety line
    cy_ = sum(y for _, y in FDECK) / len(FDECK)
    for i in range(len(FDECK)):
        (x0, y0), (x1, y1) = FDECK[i], FDECK[(i + 1) % len(FDECK)]
        if y0 < -L * 0.47 and y1 < -L * 0.47:
            continue                                    # not across the stern
        ex, ey = x1 - x0, y1 - y0
        el = math.hypot(ex, ey)
        if el < 8.0:
            continue
        ix, iy = -ey / el, ex / el
        if (cx_ - (x0 + x1) / 2.0) * ix + (cy_ - (y0 + y1) / 2.0) * iy < 0.0:
            ix, iy = -ix, -iy
        p.append(_stripe(x0 + ix * 3.0, y0 + iy * 3.0,
                         x1 + ix * 3.0, y1 + iy * 3.0, PAINT_Z, 1.70, 0.18))

    # ── island. No funnel: this ship is nuclear. ───────────────────
    sup, top = superstructure(-L * 0.045, fdz,
                              ((30.0, 11.0, 7.2), (25.0, 9.8, 5.0, 0.6),
                               (19.0, 8.6, 4.6, 1.4), (13.5, 7.2, 4.2, 2.2),
                               (9.0, 5.6, 3.6, 2.6)), taper=0.94, x=isl_x,
                              name="island")
    p += sup
    p.append(deckhouse(-L * 0.088, 9.0, 6.0, 4.4, fdz + 7.2, 0.90, "prifly",
                       x=isl_x - 3.2))                  # pri-fly, hung aft
    p += lattice_mast(isl_x, -L * 0.052, top, 18.0, foot=3.0, head=1.0,
                      bays=4, yards=((0.42, 13.0), (0.72, 8.0)), radome=2.2,
                      solid=True)
    for s in (-1, 1):
        p += planar_array(isl_x - s * 4.7, -L * 0.045, top - 9.0, 4.4, 4.2,
                          22, 90 + s * 40)
    p += air_search(isl_x, -L * 0.010, top - 4.4, 8.2, 3.2)
    p += radome(isl_x - 3.6, -L * 0.070, top - 5.6, 2.0)
    p += radome(isl_x + 3.4, -L * 0.070, top - 5.6, 2.0)

    # ── deck-edge sponsons, and the guns that stand on them ────────
    # Two things are solved here rather than typed, and both were bugs first.
    #   The flight deck overhangs the 40.8 m hull by 18 m a side, so a sponson
    #   hung at hull height floats in mid-air with nothing under it. They go
    #   directly under the deck slab, which is where the real ones are.
    #   The deck edge is only at HDW abaft L*0.030 — forward of that it sweeps
    #   in to 0.54 of HDW. A sponson typed at s*HDW therefore sat 7 m clear of
    #   the bow and rendered as a grey box floating on the sea beside the ship.
    #   Every edge fitting below asks deck_x() where the edge actually is.
    def edge(s, y):
        return deck_x(y)[1] if s > 0 else deck_x(y)[0]

    for (s, y) in ((1, L * 0.312), (1, L * 0.056), (1, -L * 0.212),
                   (1, -L * 0.436), (-1, L * 0.150), (-1, -L * 0.086),
                   (-1, -L * 0.296), (-1, -L * 0.472)):
        p += _sponson(edge(s, y), y, fdz - 1.5, out_w=5.8, l=13.0, brace=False)
    p += ciws(edge(1, L * 0.312) + 2.6, L * 0.312, fdz - 0.80, 1.15)
    p += ciws(edge(-1, -L * 0.472) - 2.6, -L * 0.472, fdz - 0.80, 1.15,
              aft=True)
    p += ciws(isl_x, -L * 0.118, fdz + 1.2, 1.15, aft=True)
    with mat("gunbore"):                                # Sea Sparrow boxes
        for (s, y) in ((1, -L * 0.436), (-1, L * 0.150)):
            p.append(cube((edge(s, y) + s * 2.6, y, fdz + 0.15),
                          (3.6, 4.4, 1.9), rot=(R(-24), 0, 0)))

    # ── four deck-edge lifts, each in a dark well ──────────────────
    # They sat exactly on the deck edge line in pass 1, which put half of each
    # 10.5 m platform over open water and rendered them as light rafts
    # alongside the ship. A raised lift is flush with the deck, so each is
    # pulled inboard to overhang by 1.9 m — off the edge WHERE IT IS at that
    # station, not off HDW, which the forward starboard lift is 5 m inboard of.
    for (sx, ly) in ((1, L * 0.180), (1, -L * 0.150),
                     (1, -L * 0.330), (-1, L * 0.075)):
        p += _deck_lift(edge(sx, ly) - sx * (5.25 - 1.9), ly,
                        fdz - 0.75, 10.5, 21.0)

    with mat("gunbore"):                                # hangar-side openings
        for s in (-1, 1):
            for k in range(3):
                p.append(cube((s * B * 0.50, L * 0.16 - k * L * 0.16, fb - 5.0),
                              (0.9, 22.0, 6.4)))
    # +0.22: the ownership patch has to sit ABOVE PAINT_Z or the tie-down
    # band that crosses it prints a dark line through the middle of the
    # faction colour, which is what the amphib's did on the first render.
    p.append(team_patch(-L * 0.462, fdz + 0.22, 9.0, 11.0, x=HDW * 0.62))
    return p, ship_meta(L, DECK_W, fdz, top + 18.0, gun_y=0.0, gun_z=fdz + 2.0)


def amphibious_assault():
    """Wasp LHD-1 — 257.3 m hull, 32.3 m at the waterline, 42.7 m across the
    flight deck, draught 8.1 m, flight deck 19.0 m above the sea.

    EXCLUSIVE FEATURE: a full-length RECTANGULAR landing lane with painted
    spots down the port side, and an OPEN STERN WELL DOCK with the gate down.
    No angle, no catapults, no waist — which is exactly how you tell it from
    the carrier from directly above.

    PASS 3 — THE TWO THINGS THAT WERE WEAK.

      The six spots read, but nothing tied them together, so the amphib's plan
      was six dots on 11 000 m2 of camo checker and the "no angle" claim was
      being carried by an absence. It is now carried by a PRESENCE: a straight
      dark lane 16 m wide runs the full 226 m of the deck with the six spots
      painted in it as light rings. Set beside the carrier's canted band the
      separating fact is now a positive one and it survives the zoom copy —
      one dark stripe parallel to the hull against one dark stripe crossing it
      at nine degrees.

      The well dock was the weakest feature on the capital sheet, and the
      reason is that it was built as an opening in the TRANSOM, which is a
      vertical surface, and the sheet that matters looks straight down. A
      vertical rectangle has no plan. So the gate is now DOWN: a 20 m ramp
      lying out over the water 16 m abaft the transom, in `deck` against the
      sea, flanked by the two body-coloured gate walls. It is the only hull in
      the roster with anything projecting past its stern except the
      minehunter's A-frame, and unlike a vertical door it is visible from
      exactly the angle the game uses. That is also the gameplay statement —
      it is where nav_e1_us_landingcraft comes from (docs/12).
    """
    L, B, DECK_W, FD = 257.3, 32.3, 42.7, 19.0
    HDW = DECK_W * 0.5
    p, fb = ship_hull(L, B, FD, bow=0.24, transom=0.94, deck=False)
    use("body")
    FDECK = [(-HDW * 0.68, L * 0.480), (HDW * 0.68, L * 0.480),
             (HDW * 1.00, L * 0.300), (HDW * 1.00, -L * 0.500),
             (-HDW * 1.00, -L * 0.500), (-HDW * 1.00, L * 0.300)]
    p.append(plate(FDECK, 1.6, fb + 0.8, "deck"))
    fdz = fb + 1.6

    isl_x = HDW * 0.760                     # starboard, hard against the edge

    # ── the exclusive, part one: one STRAIGHT lane, six painted spots ──
    # PAINT_Z: one height for every marking, 0.16 m proud of the lane and
    # 0.10 m over the bare deck. See the note in carrier() — laying paint at
    # +0.34 on a deck whose top is fdz floats every line and gives it a shadow.
    LANE_X, LANE_W = -HDW * 0.330, 16.0
    PAINT_Z = fdz + 0.10
    with mat("gunbore"):
        p.append(cube((LANE_X, -L * 0.031, fdz + 0.02),
                      (LANE_W, L * 0.878, 0.20)))
    for k in range(6):
        sy = L * 0.340 - k * L * 0.132
        with mat("deck"):
            p.append(cyl((LANE_X, sy, fdz + 0.20), 4.90, 0.22, v=20))
        with mat("gunbore"):
            p.append(cyl((LANE_X, sy, fdz + 0.30), 3.70, 0.18, v=20))
        p.append(_stripe(LANE_X, sy + 6.0, LANE_X, sy + 9.4,
                         PAINT_Z, 0.70, 0.18))
    p.append(_stripe(LANE_X, L * 0.400, LANE_X, -L * 0.452,
                     PAINT_Z, 0.90, 0.18))                       # lane centre
    for s in (-1, 1):                                            # lane edges
        p.append(_stripe(LANE_X + s * (LANE_W * 0.5 - 1.1), L * 0.418,
                         LANE_X + s * (LANE_W * 0.5 - 1.1), -L * 0.470,
                         PAINT_Z, 0.80, 0.18))

    # ── vehicle park paint to starboard, CLIPPED TO THE DECK ───────
    def deck_x(y):
        xs = []
        for i in range(len(FDECK)):
            (x0, y0), (x1, y1) = FDECK[i], FDECK[(i + 1) % len(FDECK)]
            if (y0 - y) * (y1 - y) < 0.0:
                xs.append(x0 + (x1 - x0) * (y - y0) / (y1 - y0))
        return (min(xs), max(xs)) if len(xs) >= 2 else (0.0, 0.0)

    for k in range(19):
        yy = -L * 0.452 + k * 13.4
        px_, sx_ = deck_x(yy)
        lo, hi = LANE_X + LANE_W * 0.5 + 2.2, sx_ - 3.0
        if -34.0 < yy < 12.0 and hi > isl_x - 7.0:      # keep off the island
            hi = isl_x - 8.0
        if hi - lo > 7.0:
            p.append(_stripe(lo, yy, hi, yy, PAINT_Z, 1.30, 0.18))
        lo2, hi2 = px_ + 3.0, LANE_X - LANE_W * 0.5 - 2.2
        if hi2 - lo2 > 7.0:
            p.append(_stripe(lo2, yy, hi2, yy, PAINT_Z, 1.30, 0.18))
    cx_ = sum(x for x, _ in FDECK) / len(FDECK)         # deck-edge safety line
    cy_ = sum(y for _, y in FDECK) / len(FDECK)
    for i in range(len(FDECK)):
        (x0, y0), (x1, y1) = FDECK[i], FDECK[(i + 1) % len(FDECK)]
        if y0 < -L * 0.47 and y1 < -L * 0.47:
            continue
        ex, ey = x1 - x0, y1 - y0
        el = math.hypot(ex, ey)
        if el < 8.0:
            continue
        ix, iy = -ey / el, ex / el
        if (cx_ - (x0 + x1) / 2.0) * ix + (cy_ - (y0 + y1) / 2.0) * iy < 0.0:
            ix, iy = -ix, -iy
        p.append(_stripe(x0 + ix * 3.0, y0 + iy * 3.0,
                         x1 + ix * 3.0, y1 + iy * 3.0, PAINT_Z, 1.70, 0.18))

    # ── island: longer and taller, twin stacks (this ship is not nuclear) ──
    sup, top = superstructure(-L * 0.030, fdz,
                              ((50.0, 10.4, 7.2), (38.0, 9.2, 4.8, 1.0),
                               (26.0, 8.0, 4.4, 2.0), (16.0, 6.6, 4.0, 3.0)),
                              taper=0.94, x=isl_x, name="island")
    p += sup
    for k in (-1, 1):
        p += funnel(isl_x, -L * 0.010 + k * L * 0.058, top - 6.4, 11.0, 7.2,
                    9.0, rake=6, name=f"fnl{k}")
    p += lattice_mast(isl_x, -L * 0.070, top, 15.0, foot=2.8, head=1.0,
                      bays=4, yards=((0.48, 10.5), (0.76, 6.6)), radome=1.9,
                      solid=True)
    p += air_search(isl_x, -L * 0.104, top - 4.2, 7.4, 3.0)
    p += radome(isl_x - 3.2, -L * 0.128, top - 5.2, 1.7)
    p.append(deckhouse(-L * 0.072, 8.0, 5.4, 4.0, fdz + 7.2, 0.90, "prifly",
                       x=isl_x - 3.0))

    # ── the exclusive, part two: the stern gate DOWN ───────────────
    GW = B * 0.62
    with mat("gunbore"):                                # the well-dock mouth
        p.append(cube((0, -L * 0.494, fb - FD * 0.44), (GW + 1.2, 3.6,
                                                        FD * 0.50)))
        p.append(cube((0, -L * 0.452, fb - FD * 0.62), (GW * 0.94, L * 0.10,
                                                        1.4)))
    with mat("deck"):                                   # the ramp, lying out
        p.append(profile([(-L * 0.492, fb - FD * 0.46),
                          (-L * 0.492, fb - FD * 0.46 - 1.2),
                          (-L * 0.562, 0.10), (-L * 0.562, 1.30)],
                         GW, "wellramp"))
    use("body")

    # ── deck-edge sponsons and the guns that stand on them ─────────
    # Under the deck slab, not at hull height, and hung off the edge WHERE IT
    # IS — this deck chamfers in to 0.68 of HDW over the forward 18 m, and the
    # port sponson at L*0.316 stands in that chamfer. See the note in
    # carrier(), where typing s*HDW put a sponson on open water.
    def edge(s, y):
        return deck_x(y)[1] if s > 0 else deck_x(y)[0]

    for (s, y) in ((1, L * 0.246), (1, -L * 0.056), (1, -L * 0.392),
                   (-1, L * 0.316), (-1, L * 0.010), (-1, -L * 0.402)):
        p += _sponson(edge(s, y), y, fdz - 1.4, out_w=5.2, l=11.0, brace=False)
    p += ciws(edge(1, L * 0.246) + 2.4, L * 0.246, fdz - 0.70, 1.15)
    p += ciws(edge(-1, -L * 0.402) - 2.4, -L * 0.402, fdz - 0.70, 1.15,
              aft=True)
    p += ciws(isl_x, -L * 0.126, fdz + 1.2, 1.15, aft=True)
    with mat("gunbore"):                                # RAM / Sea Sparrow
        for (s, y) in ((-1, L * 0.316), (1, -L * 0.392)):
            p.append(cube((edge(s, y) + s * 2.4, y, fdz + 0.20),
                          (3.4, 4.0, 1.8), rot=(R(-24), 0, 0)))

    # ── two deck-edge lifts, each in a dark well (see carrier()) ───
    for (sx, ly) in ((-1, -L * 0.300), (1, -L * 0.130)):
        p += _deck_lift(edge(sx, ly) - sx * (4.75 - 1.7), ly,
                        fdz - 0.75, 9.5, 18.0)
    p.append(team_patch(-L * 0.458, fdz + 0.22, 7.0, 8.4, x=HDW * 0.56))
    return p, ship_meta(L, DECK_W, fdz, top + 15.0, gun_y=0.0, gun_z=fdz + 2.0)


def landing_craft():
    """LCAC-1 — 26.8 x 14.3 m on cushion. Ship-to-shore.

    THE ONE WATERLINE EXCEPTION IN THE FILE: an air-cushion vehicle really
    does sit on the surface, so the skirt base is at z = 0 and the buoyancy
    boxes start 1.5 m up. Everything else in the roster floats in the sea.

    EXCLUSIVE FEATURE: four ducted lift-fan shrouds — two a side, standing
    VERTICALLY on the roofs of the buoyancy boxes, plus the two big shrouded
    propulsors at the stern. Nothing else in the roster shows a circle from
    directly above, and four of them in a rectangle is the whole read.

    DETAIL PASS, AND IT HAD BY FAR THE MOST ROOM (+4 692) BECAUSE IT WAS THE
    LEAST FINISHED THING IN THE FILE. It was a slab, two side boxes, two raked
    plates and four tubes, and from overhead it read as a grey brick.

      THE CARGO WELL IS THE SHIP. An LCAC seen from above is a DARK open box
      between two light side structures, and it was previously a LIGHT deck
      cube between two dark ones — exactly inverted. The well floor is now
      `gunbore` with light `deck` tie-down ribs across it, the same slab-and-
      ribs trick vls() uses, and light coaming rails down both sides. That one
      change is what makes a 27 m object identifiable at the small-craft zoom:
      it is the only hull in the roster that is dark down the middle and light
      down the sides.

      BOTH RAMPS ACTUALLY OPEN. The bow and stern ramps were body-coloured
      plates flush with the ends, indistinguishable from the hull. Each is now
      a light `deck` ramp lying down over a `gunbore` opening, so the dark well
      runs out through both ends of the craft and the two ramps are the widest
      light bars on it.

      A CAB, NOT A WINDOW. The starboard control cab is now a stepped two-tier
      house with wrapped glass and a mast, and the port operator's cab is
      built as its smaller mirror. Real LCACs are asymmetric that way and it
      is the cheapest thing that stops the craft reading as a symmetrical
      brick.

      FOUR LIFT-FAN INTAKES ON TOP. The four ducts stay — they are the stated
      exclusive — but they were fore-and-aft tubes buried in the side boxes,
      i.e. invisible from the one camera that matters. Four dark intake wells
      with light rims now sit on the ROOFS of the side boxes, two a side, and
      they read in plan as four circles. The fore-and-aft ducts remain at the
      stern, where they are the propulsors, with the shroud flipped to `deck`
      so it stands off the dark side box instead of matching it.

    THE WATERLINE EXCEPTION IS UNCHANGED: skirt base at z = 0.
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
    for s in (-1, 1):                                   # side buoyancy boxes
        p.append(deckhouse(L * 0.02, L * 0.74, 3.0, 2.6, 3.05, 0.94,
                           f"lc_side{s}", s * B * 0.365))
    with mat("gunbore"):                                # the open cargo well
        p.append(cube((0, 0.0, 3.16), (B * 0.52, L * 0.98, 0.36)))
    with mat("deck"):                                   # tie-down ribs
        for k in range(3):
            p.append(cube((0, L * (0.30 - 0.28 * k), 3.36),
                          (B * 0.52, 0.34, 0.16)))
        for s in (-1, 1):                               # well coamings
            p.append(cube((s * B * 0.281, 0, 3.60), (0.62, L * 0.98, 1.10)))
    with mat("deck"):                                   # bow and stern ramps
        p.append(cube((0, L * 0.475, 3.10), (B * 0.50, 3.6, 0.40),
                      rot=(R(-26), 0, 0)))
        p.append(cube((0, -L * 0.475, 3.10), (B * 0.46, 3.4, 0.40),
                      rot=(R(24), 0, 0)))
    use("body")                                         # ramp side cheeks
    for s in (-1, 1):
        p.append(cube((s * B * 0.275, L * 0.425, 3.60), (0.55, 3.6, 1.60)))
    with mat("deck"):                                   # starboard control cab
        p.append(cube((B * 0.365, L * 0.235, 6.40), (3.1, 4.4, 1.50)))
        p.append(cube((B * 0.365, L * 0.245, 7.65), (2.5, 3.4, 1.00)))
    with mat("glass"):
        p.append(cube((B * 0.365, L * 0.303, 7.72), (2.2, 0.30, 0.66)))
        for s in (-1, 1):
            p.append(cube((B * 0.365 + s * 1.16, L * 0.205, 7.72),
                          (0.28, 1.9, 0.62)))
    with mat("deck"):                                   # port operator's cab
        p.append(cube((-B * 0.365, L * 0.255, 6.30), (2.7, 3.2, 1.30)))
    with mat("glass"):
        p.append(cube((-B * 0.365, L * 0.302, 6.45), (2.0, 0.30, 0.60)))
    use("body")                                         # cab mast
    p.append(cyl((B * 0.365, L * 0.075, 8.9), 0.22, 3.4, v=8))
    with mat("gun"):
        p.append(cube((B * 0.365, L * 0.075, 10.2), (2.6, 0.30, 0.26)))
    with mat("deck"):                                   # the exclusive, seen in PLAN:
        for s in (-1, 1):                               # four lift-fan intakes
            for k in range(2):
                p.append(cyl((s * B * 0.365, L * (0.055 - 0.235 * k), 6.10),
                             1.58, 0.90, v=14))
    with mat("gunbore"):
        for s in (-1, 1):
            for k in range(2):
                p.append(cyl((s * B * 0.365, L * (0.055 - 0.235 * k), 6.14),
                             1.14, 0.72, v=14))
    with mat("deck"):                                   # stern propulsor shrouds
        for s in (-1, 1):
            p.append(cyl((s * B * 0.365, -L * 0.395, 5.05), 1.95, 2.30,
                         rot=(R(90), 0, 0), v=16))
    with mat("gunbore"):
        for s in (-1, 1):
            p.append(cyl((s * B * 0.365, -L * 0.395, 5.05), 1.52, 2.50,
                         rot=(R(90), 0, 0), v=12))
    p.append(team_patch(-L * 0.320, 3.36, 2.6, 3.2))
    use("body")
    return p, ship_meta(L, B, 3.4, 10.6, gun_y=0.0, gun_z=5.0)


def fleet_oiler():
    """Henry J. Kaiser T-AO-187 — 206.5 x 29.7 m, draught 10.7 m, freeboard
    8.0 m. Pillar 4's centrepiece (docs/04): a submarine that finds this has
    taken the fleet's RANGE, which is worth more than a destroyer.

    EXCLUSIVE FEATURE: a row of four replenishment kingposts with spanwire
    booms. They are the only masts in the fleet that are NOT on the
    centreline, and four tall verticals in a line down a long flat deck is
    unmistakable from any angle.

    PASS 3 — THE OILER READ BEST OF THE THREE CAPITALS AND WAS STILL THE
    EMPTIEST SHIP IN THE FILE, FOR A REASON WORTH WRITING DOWN.

      The oiler is the file's one INVERTED ship. Every escort is a dark camo
      hull with a light deck laid inside it, so the escort's deck features are
      built dark and read as holes. The oiler's deck plate covers almost the
      whole hull, so the oiler is a LIGHT ship, and a light deck fitting on it
      is invisible. Everything added here is therefore dark — `gunbore` cargo
      hatches, a `body` pipe gallery, `body` rig houses — which is the exact
      opposite of what the carrier and the amphib needed twenty lines up.

      The second thing, and it was silently eating the old deck fittings:
      ship_hull(sheer=2.6) raises EVERYTHING forward of L*0.045 by 2.6 m, and
      that is 45% of this hull. The five light tank-top discs of pass 2 sat at
      fb + 0.80 and the forecastle deck over them is at fb + 2.82, so four of
      the five were buried inside the forecastle and rendered as nothing —
      the same class of bug as the destroyer's VLS farm inside its hangar.
      There are now two deck levels in this function and every fitting states
      which one it stands on. FCY and fcz are the break and the raised deck.

      The rigs themselves were four bare poles. Each of the four now has a
      transfer station round its foot: a dark rig house inboard, a light
      sponson hung outboard past the hull line, and a fuel line running in to
      the centreline gallery. That puts four notches in the hull outline at
      exactly the stations the kingposts stand at, which ties the exclusive
      feature to the silhouette instead of leaving it 17 m up in the air where
      the plan view cannot see it.
    """
    L, B, FB = 206.5, 29.7, 8.0
    p, fb = ship_hull(L, B, FB, bow=0.24, transom=0.90, sheer=2.6)
    FCY = L * 0.045                     # the forecastle break, from ship_hull
    fcz = fb + 2.82                     # the raised forecastle deck surface
    EDGE = B * 0.47                     # where the weather deck runs out

    sup, top = superstructure(-L * 0.360, fb,
                              ((34.0, 20.0, 7.0), (28.0, 17.0, 3.6),
                               (20.0, 13.0, 3.4), (13.0, 9.6, 3.2)),
                              taper=0.94)
    p += sup
    with mat("deck"):                                   # bridge wings
        for s in (-1, 1):
            p.append(cube((s * 11.6, -L * 0.348, top - 3.0),
                          (9.0, 4.6, 0.55)))
            p.append(strut((s * 6.4, -L * 0.348, top - 5.6),
                           (s * 15.0, -L * 0.348, top - 3.2), 0.42))
    p += funnel(0, -L * 0.435, top - 8.0, 13.0, 10.0, 11.0, rake=8)
    p += lattice_mast(0, -L * 0.395, top, 11.0, foot=2.8, head=1.0, bays=3,
                      yards=((0.55, 9.0),), radome=1.6, solid=True)

    # ── the exclusive: four kingposts, each with a transfer station ──
    # The forward pair stands on the forecastle, the after pair on the cargo
    # deck 2.6 m lower — which is where those decks actually are on this hull.
    for s in (-1, 1):
        for (y, base) in ((L * 0.150, fcz), (-L * 0.075, fb)):
            p += kingpost(s * 4.9, y, base, 17.0, boom=12.0, side=s,
                          name=f"kp{s}{y:.0f}")
            use("body")                                 # rig house, inboard
            p.append(cube((s * 11.4, y, base + 1.85), (4.4, 7.4, 3.70)))
            p += _sponson(s * EDGE, y, base - 0.6, out_w=5.0, l=9.0,
                          brace=False)
            with mat("gun"):                            # fuel line to the rig
                p.append(cube((s * 10.0, y, base + 1.05), (6.4, 1.05, 1.05)))

    # ── cargo deck: dark hatches and a dark pipe gallery on a light deck ──
    with mat("gunbore"):
        for k in range(5):                              # forecastle tank tops
            p.append(cube((0.0, 20.0 + k * 14.0, fcz + 0.34),
                          (7.4, 7.2, 0.68)))
        for k in range(2):                              # cargo deck hatches
            p.append(cube((0.0, -6.0 - k * 14.0, fb + 0.34),
                          (7.4, 7.2, 0.68)))
    use("body")                                         # cargo pipe galleries
    for s in (-1, 1):
        p.append(cube((s * 7.6, 45.0, fcz + 1.00), (3.0, 66.0, 2.00)))
        p.append(cube((s * 7.6, -23.5, fb + 1.00), (3.0, 63.0, 2.00)))
        p.append(cube((s * 7.6, FCY + 0.6, fb + 1.55), (3.0, 6.4, 3.10)))

    p += helipad(-L * 0.205, 15.0, 19.0, fb)
    p.append(_stripe(-9.0, -L * 0.205, 9.0, -L * 0.205, fb + 0.30, 0.70, 0.18))
    for s in (-1, 1):
        p += boat_bay(s * B * 0.47, -L * 0.300, fb, l=8.4, h=3.2)
    p += breakwater(L * 0.400, B * 0.60, fcz)
    with mat("gunbore"):                                # anchor gear forward
        for s in (-1, 1):
            p.append(cube((s * 3.2, L * 0.452, fcz + 0.30), (2.4, 4.4, 0.60)))
    with mat("gun"):
        p.append(cyl((0, L * 0.428, fcz + 0.85), 1.55, 1.70, v=14))
    p += clutter(hull_planform(L, B, bow=0.24, transom=0.90, w=0.92), fb,
                 spacing=15.0, size=(1.2, 2.2, 0.95))
    p.append(team_patch(-L * 0.140, fb, 5.0, 6.0))
    return p, ship_meta(L, B, fb, top + 11.0, gun_y=0.0, gun_z=fb + 1.0)


def mine_warfare():
    """Avenger MCM-1 — 68.3 x 11.9 m, draught 3.7 m, freeboard 3.6 m. Laying
    and sweeping; Taiwan's force multiplier (docs/12).

    EXCLUSIVE FEATURE: a stern A-frame gantry with the sweep sled sitting
    under it on an open working deck. Nothing else has a frame standing over
    the transom, and the big empty after deck is itself a read.

    DETAIL PASS. The A-frame was already there and it does read at the small
    zoom, but everything under it was light-on-light: a `deck` working deck
    laid on a `deck` weather deck, which is one material painted on itself and
    therefore invisible. Three changes, and the first is the whole pass:

      THE WORKING DECK IS NOW DARK. The after 40% of the hull is a `gunbore`
      plate cut from the same hull_planform curve, so from directly overhead
      the minehunter is a short fat light hull whose back half is BLACK. That
      is a figure-ground inversion no other small craft has — the corvette's
      dark patch is a 12 m helipad, this one is 27 m and runs to the transom —
      and it cost 330 triangles, replacing a 188-triangle cube that did
      nothing. Everything that works on that deck was flipped to light so it
      now reads AGAINST the black instead of vanishing into grey: the mine
      rails, the sweep sled and the acoustic floats.

      TWO SWEEP-CABLE REELS. Big athwartships drums on the after deck, which
      is what an Avenger actually has and what a warship never does. Light
      drums on the black deck; they read at the small-craft zoom as a pair of
      bars across the dark rectangle.

      A QUARTER CRANE for the neutralisation vehicle, offset to starboard —
      the only off-centreline boom in the small-craft band.

    HULL. bow 0.28 -> 0.24, a bluffer entry. The brief asked for a hull that
    reads tubby and the Avenger is genuinely a full-bodied 68.3 x 11.9 wooden
    hull (L/B 5.7 against the corvette's 6.7); the fine 0.28 entry was flattering
    it into a warship. Length, beam and freeboard are unchanged.

    PAID FOR by clutter() at 14 m instead of 9 m and the mast at two bays
    instead of three; the ship lands exactly on its 18 000 ceiling.
    """
    L, B, FB = 68.3, 11.9, 3.6
    p, fb = ship_hull(L, B, FB, bow=0.24, transom=0.88, sheer=1.2)
    sup, _top = superstructure(L * 0.195, fb,
                               ((21.0, 9.0, 4.6), (13.0, 7.4, 3.0, 0.8),
                                (7.0, 5.4, 2.6, 2.2)),
                               taper=0.88)
    p += sup
    p += lattice_mast(0, L * 0.140, fb + 7.6, 8.0, foot=2.2, head=0.8, bays=2,
                      yards=((0.52, 6.2),), radome=1.2)
    p += funnel(0, -L * 0.005, fb, 5.6, 4.2, 5.6, rake=12, uptakes=1)
    wd = [(x, y) for (x, y) in hull_planform(L, B, bow=0.24, transom=0.88,
                                             w=0.90) if y < -L * 0.030]
    with mat("gunbore"):                                # the dark working deck
        p.append(plate([(wd[0][0], -L * 0.030)] + wd + [(wd[-1][0], -L * 0.030)],
                       0.30, fb + 0.15, "mcm_work"))
    p += gantry(-L * 0.450, fb, B * 0.72, 5.4, depth=3.4)   # the exclusive
    with mat("deck"):                                   # the sweep sled
        p.append(cube((0, -L * 0.395, fb + 1.2), (4.2, 5.0, 1.8)))
        for s in (-1, 1):
            p.append(cyl((s * 1.5, -L * 0.395, fb + 2.4), 0.55, 4.6,
                         rot=(R(90), 0, 0), v=10))
    with mat("deck"):                                   # mine rails, light on black
        for s in (-1, 1):
            p.append(cube((s * B * 0.30, -L * 0.245, fb + 0.45),
                          (0.95, L * 0.36, 0.30)))
    with mat("deck"):                                   # two sweep-cable reels
        for y in (-L * 0.135, -L * 0.235):
            p.append(cyl((0, y, fb + 2.05), 1.85, B * 0.52,
                         rot=(0, R(90), 0), v=12))
    with mat("gunbore"):                                # reel end flanges
        for y in (-L * 0.135, -L * 0.235):
            for s in (-1, 1):
                p.append(cube((s * B * 0.265, y, fb + 2.05), (0.40, 4.1, 4.1)))
    use("body")                                         # quarter crane, starboard
    p.append(cyl((B * 0.34, -L * 0.075, fb + 2.6), 0.60, 5.2, v=10, taper=0.7))
    with mat("gun"):
        p.append(cube((B * 0.34 - 3.4, -L * 0.075, fb + 4.6), (7.0, 0.50, 0.50)))
        p.append(strut((B * 0.34, -L * 0.075, fb + 1.4),
                       (B * 0.34 - 6.3, -L * 0.075, fb + 4.4), 0.26))
    with mat("deck"):                                   # acoustic floats, abreast
        for x in (-2.4, 0.0, 2.4):
            p.append(cyl((x, -L * 0.300, fb + 1.05), 1.05, 1.5, v=12))
    p += gun_mount(L * 0.400, fb + 1.2, r=1.00, barrel_l=2.4)
    p += clutter(hull_planform(L, B, bow=0.24, transom=0.88, w=0.88), fb,
                 spacing=14.0, size=(0.9, 1.6, 0.75))
    p.append(team_patch(-L * 0.085, fb + 0.20, 2.8, 2.8))
    use("body")
    return p, ship_meta(L, B, fb, fb + 15.6, gun_y=L * 0.40, gun_z=fb + 2.4)


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


# ══════════════════════════════════════════════════════════════════
# THE TEXTURE PASS (2026-08) — roster data only, geometry frozen
# ══════════════════════════════════════════════════════════════════
# Each entry below REQUESTS compose layers from tools/textures.py through the
# additive hero_models.texture_features() hook. The treatment, uniform across
# the surface fleet:
#   - haze grey hull (navy_haze in the roster, replacing air_dark),
#   - black boot-topping stripe at the waterline (hulls float at z = 0),
#   - vertical rust streaking from the scuppers (deck edge, z0 = fb) and a
#     pair of hawse-pipe stains run straight down the bow flare,
#   - the weather deck recoloured to a darker neutral non-slip grey via the
#     base_rgb override (GROUP_MATS itself is shared with every module and
#     stays untouched),
#   - the hull number stencilled white on both sides of the bow.
# SUBMARINES STAY DARK — tone is the strongest sub-vs-surface cue the roster
# has (same argument as the F-117 in textures.py) — but on `sub_dark`, a
# no-panel twin of air_dark: the aircraft scheme's baked speckle read as
# stone masonry at ship camo scale. They take the weathering pass on the
# dark scheme and carry their number on the sail.
_STENCIL = (0.90, 0.90, 0.87)
_RUST = (0.35, 0.20, 0.11)
_DECK_GREY = (0.165, 0.170, 0.168)


def _ship_tex(name, L, B, fb, sheer, num, res=2048, bow=0.30, num_frac=0.40,
              extra_insignia=(), extra_weather=None, groups=("body", "deck")):
    """One surface ship's texture request. All coordinates are build-space
    metres: bow at +Y, waterline at z = 0, weather deck at z = fb."""
    zt = fb + sheer                          # sheer strake height at the bow
    t = (0.50 - num_frac) / bow              # entry fraction at the number
    xn = 0.5 * B * (t ** 0.62)               # deck-level half-beam there
    size = max(1.8, 0.72 * zt)
    ins = [dict(kind="pennant", text=num, color=_STENCIL, alpha=0.92,
                center=(s * xn, num_frac * L, 0.54 * zt),
                normal=(s, 0, 0), size=size) for s in (-1, 1)] if num else []
    weather = dict(
        boottop=dict(z1=min(2.2, 0.16 * fb + 0.35), tint=(0.045, 0.048, 0.052)),
        streaks=[dict(z0=fb + 0.10, length=max(4.0, fb * 1.1), density=0.34,
                      strength=0.58, tint=_RUST)],
        exhaust=[dict(origin=(s * 0.17 * B, 0.445 * L, zt + 0.05),
                      direction=(0, 0, -1), length=max(2.0, zt * 0.75),
                      width=0.55, strength=0.6, tint=_RUST)
                 for s in (-1, 1)],          # the hawse-pipe stains
        edge_wear=dict(strength=0.35))
    if extra_weather:
        weather.update(extra_weather)
    H.texture_features(
        name, size_class="ship", res=res, groups=groups,
        base_rgb=({"deck": _DECK_GREY} if "deck" in groups else None),
        # Big soft haze blotches, and RESTRAINED plating: at 0.42/0.45 the
        # destroyer rendered as carved stone blocks — every plate outlined.
        camo_scale=min(24.0, max(10.0, L * 0.12)),
        # width=0.30 m: without it the seam falls back to 2.6 texels, which on
        # a 2048 px capital hull is a ~50 cm soft grout line — bathroom tile.
        panels=dict(spacing=min(9.0, max(3.0, L * 0.045)), strength=0.34,
                    jitter=0.05, seams=0.28, width=0.30),
        weathering=weather,
        insignia=ins + list(extra_insignia))


def _sub_tex(name, L, B, deck, num, sail_y, sail_h, sail_w, num_size=1.8,
             sail_l=0.0):
    # sail_y is the sail's LEADING-EDGE station and the fin body runs AFT of
    # it (sail() profiles span y-l..y), so a stamp centred at sail_y painted
    # only the raked leading edge — the 2026-08 side sheet showed one sliver
    # of one digit. Centre on the fin's mid-length instead.
    ins = []
    if num:
        yc = sail_y - 0.5 * sail_l
        ins = [dict(kind="pennant", text=num, color=_STENCIL, alpha=0.96,
                    center=(s * sail_w * 0.5, yc, deck + sail_h * 0.55),
                    normal=(s, 0, 0), size=num_size) for s in (-1, 1)]
    H.texture_features(
        name, size_class="ship", res=1024, groups=("body",),
        # 3.5 m tile: shrinks the base-scheme drift to sub-30 cm grain — at
        # the ship default 9 m it read as ~1 m stone blocks on the hull.
        camo_scale=3.5,
        panels=dict(spacing=3.0, strength=0.28, jitter=0.04, seams=0.25,
                    width=0.22),
        weathering=dict(
            streaks=[dict(z0=deck + 0.35, length=2.6, density=0.30,
                          strength=0.35, tint=(0.26, 0.18, 0.12))],
            edge_wear=dict(strength=0.30)),
        insignia=ins)


#          name                    L      B     fb   sheer  number
_ship_tex("nav_e4_us_destroyer",  155.3, 20.1, 5.9, 2.4, "62")
_ship_tex("nav_e1_us_cruiser",    172.8, 16.8, 5.6, 2.2, "52")
_ship_tex("nav_e1_us_frigate",    138.1, 13.7, 4.6, 2.0, "54", bow=0.32)
# num_frac 0.31: at the default 0.40 the corvette's fine entry put the decal
# slab half off the flare and "30" rendered broken (2026-08 side sheet).
_ship_tex("nav_e1_us_corvette",    89.1, 13.3, 3.9, 1.5, "30", res=1024,
          num_frac=0.31)
_ship_tex("nav_e2_us_missileboat", 56.1, 10.2, 3.0, 1.1, "71", res=1024,
          bow=0.34)
_ship_tex("nav_e1_us_patrol",      54.6,  7.6, 2.9, 0.0, "13", res=1024)
_ship_tex("nav_e1_us_minewarfare", 68.3, 11.9, 3.6, 1.2, "1",  res=1024,
          bow=0.24)
_ship_tex("nav_e1_us_oiler",      206.5, 29.7, 8.0, 2.6, "187", bow=0.24)
# Capitals: the flight deck lives in the BODY group, so its dark non-slip
# coat is a deckpaint layer over everything up-facing above the deck line;
# the painted `deck`-group stripes are left out of the compose so they keep
# their designed contrast against the dark lanes. Deck number at the bow.
_ship_tex("nav_e1_us_carrier",    332.8, 40.8, 19.6, 0.0, None,
          groups=("body",),
          extra_weather=dict(deckpaint=dict(z0=20.8, tint=(0.155, 0.16, 0.165))),
          extra_insignia=[dict(kind="pennant", text="68", color=_STENCIL,
                               center=(8.0, 146.0, 21.4), normal=(0, 0, 1),
                               size=18.0, up=(0, -1, 0), alpha=0.9)])
_ship_tex("nav_e2_us_amphib",     257.3, 32.3, 19.0, 0.0, None,
          groups=("body",),
          extra_weather=dict(deckpaint=dict(z0=20.1, tint=(0.155, 0.16, 0.165))),
          extra_insignia=[dict(kind="pennant", text="1", color=_STENCIL,
                               center=(8.5, 113.0, 20.6), normal=(0, 0, 1),
                               size=12.0, up=(0, -1, 0), alpha=0.9)])
# The LCAC floats ON the sea: no boot topping (the dark skirt is the
# waterline), no rust columns on an aluminium craft — panels and wear only,
# plus its craft number on both side boxes.
H.texture_features(
    "nav_e1_us_landingcraft", size_class="ship", res=1024, groups=("body",),
    panels=dict(spacing=2.4, strength=0.40, jitter=0.08, seams=0.45),
    weathering=dict(edge_wear=dict(strength=0.40)),
    insignia=[dict(kind="pennant", text="91", color=_STENCIL, alpha=0.9,
                   center=(s * 14.3 * 0.47, 0.5, 4.1), normal=(s, 0, 0),
                   size=2.2) for s in (-1, 1)])
#         name                L      B    deck  number  sail y/h/w (+l)
_sub_tex("sub_e2_us_nuclear", 110.3, 10.1, 1.90, "688", 23.7, 5.8, 3.2,
         num_size=2.4, sail_l=11.6)
_sub_tex("sub_e1_us_diesel",   62.0,  6.2, 1.20, "209", 12.4, 3.6, 2.2,
         sail_l=7.4)
_sub_tex("sub_e7_de_aip",      57.2,  7.0, 1.30, "212", 10.0, 3.8, 2.1,
         sail_l=6.6)
_sub_tex("sub_e1_kp_midget",   34.0,  3.8, 0.80, None,   5.1, 1.9, 1.3)



# ══ soviet / chinese lineage variants (2026-08 red-fleet pass) ═════
# Additive: dims from data/factions/ru.json and cn.json where present;
# the 052D's hull dims are published figures (cn.json e6 carries mass and
# sensors but no dims_m) and are noted as such in its docstring.
def twin_gun_mount(y, z, r=2.1, barrel_l=7.0, barrel_r=0.26, x=0.0,
                   aft=False, name="tgun"):
    """gun_mount() with TWO tubes side by side — the AK-130 read.

    NATO escorts in this roster all mount single-barrel guns, so a pair of
    parallel tubes off one gunhouse is by itself a lineage cue, and the
    Sovremenny carries it twice. Geometry follows gun_mount() exactly; only
    the tube is doubled, at x = +/- r*0.28.
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
        for sx in (-1, 1):
            bx = x + sx * r * 0.28
            out.append(cyl((bx, y + s * (r * 1.24 + barrel_l / 2), z + h * 0.62),
                           barrel_r, barrel_l, rot=(R(90), 0, 0), v=10))
            out.append(cyl((bx, y + s * (r * 1.24 + barrel_l * 0.16), z + h * 0.62),
                           barrel_r * 1.8, barrel_l * 0.30, rot=(R(90), 0, 0), v=10))
    with mat("gunbore"):
        for sx in (-1, 1):
            out.append(cyl((x + sx * r * 0.28, ymuz, z + h * 0.62),
                           barrel_r * 0.55, 0.14, rot=(R(90), 0, 0), v=8))
    return out


def sovremenny():
    """Project 956 Sovremenny — 156.0 x 17.3 m, draught 6.5 m, freeboard
    5.2 m, 7 940 t (ru.json air_defence_destroyer e4-e6; the same hull is
    cn's imported e5). The gun-and-arm destroyer of the Soviet lineage.

    WHAT SEPARATES IT FROM THE BURKE, deck-plan facts first, because from
    3/4 view the two are grey escorts of identical length:

      NOT ONE VLS CELL. The Burke's read is two black cell farms; this deck
      has none, and instead shows TWO TWIN-GUN MOUNTS — the aft one on the
      quarterdeck, and no other escort in the roster has a main gun aft.
      FOUR FAT ROUND TUBES A SIDE abeam the bridge: the Moskit quads,
      Tarantul-pattern tubes at three times the scale, angled outboard and
      overhanging nothing — a row of four dark mouths in plan each side.
      ONE massive squat funnel where the Burke has two close-coupled.
      The HELIPAD IS AMIDSHIPS, between funnel and aft SAM barbette. Every
      NATO escort pads at the stern; a pad with deck both fore AND aft of
      it is instantly Soviet.
      Arm launchers fore and aft (Shtil) — the frigate's Mk13 shape, twice.
      Tower foremast: a solid truncated pyramid with a big rotating slab
      (Top Steer) on the crown, plus a Band Stand radome over the bridge.
    """
    L, B, FB, SH = 156.0, 17.3, 5.2, 2.0
    p, fb = ship_hull(L, B, FB, bow=0.32, transom=0.80, sheer=SH)
    sup, top = superstructure(L * 0.100, fb,
                              ((34.0, 12.6, 5.0), (24.0, 10.6, 4.2, 1.0),
                               (13.0, 8.6, 3.6, 4.5)), taper=0.92)
    p += sup
    z_01, z_02, z_bridge = fb + 5.0, fb + 9.2, fb + 12.8

    # tower foremast: solid pyramid, Top Steer slab on the crown
    p += lattice_mast(0, 8.5, z_02, 13.0, foot=5.4, head=2.0, bays=3,
                      solid=True, yards=((0.55, 9.0),))
    p += air_search(0, 8.5, z_02 + 13.0, 7.2, 3.0)
    p += radome(0, 20.0, z_bridge, 1.7)                 # Band Stand
    p += director(0, 30.5, z_01, 1.45)                  # Front Dome, forward

    # the Moskit quads — the loudest lineage cue on the ship
    for s in (-1, 1):
        p += missile_tubes(s * 7.1, 19.0, fb + 0.9, n=4, l=9.8, r=0.98,
                           elev=9, yaw=s * 15, name=f"mosk{s}")

    # after deckhouse, ONE fat funnel, open lattice mainmast
    p.append(deckhouse(-L * 0.075, 26.0, 10.4, 4.6, fb))
    p += funnel(0, -8.0, fb + 4.6, 11.0, 8.4, 6.8, rake=7)
    p += lattice_mast(0, -20.0, fb + 4.6, 9.5, foot=2.6, head=1.0, bays=3,
                      yards=((0.60, 6.4),), radome=1.2)
    p += director(0, -23.5, fb + 4.6, 1.45, aft=True)   # Front Dome, aft
    for s in (-1, 1):
        p += ciws(s * 4.2, -14.5, fb + 4.6, 0.90, aft=True)   # AK-630 pair
        p += esm_array(s * 5.9, 13.5, z_02)
        p += bridge_wing(s * 6.0, 21.5, z_bridge, gun=False)
        p += chaff_launcher(s * 5.6, 4.0, z_01, yaw=s * 30)
        p += torpedo_tubes(s * 6.4, -L * 0.030, fb + 0.4, yaw=s * 60)
        p += boat_bay(s * B * 0.47, L * 0.010, fb)

    # helipad AMIDSHIPS-AFT — deck fore and aft of it, the Soviet pad
    p += helipad(-35.0, 12.5, 14.0, fb)

    # the gun-and-arm armament ladder, doubled fore and aft
    p += twin_gun_mount(L * 0.360, fb + SH, r=2.1, barrel_l=7.0)
    with mat("deck"):
        p.append(cyl((0, L * 0.270, fb + SH + 0.35), 2.30, 0.70, v=18))
    p += arm_launcher(0, L * 0.270, fb + SH + 0.7, arm=5.6)
    with mat("deck"):
        p.append(cyl((0, -49.1, fb + 0.35), 2.30, 0.70, v=18))
    p += arm_launcher(0, -49.1, fb + 0.7, arm=5.6)
    p += twin_gun_mount(-L * 0.400, fb, r=2.1, barrel_l=7.0, aft=True)

    p += breakwater(L * 0.315, B * 0.70, fb + SH)
    p += anchor_gear(L * 0.440, fb + SH, B)
    p += clutter(hull_planform(L, B, bow=0.32, transom=0.80, w=0.90), fb,
                 spacing=34.0)
    p.append(team_patch(36.8, fb + SH, 3.6, 4.0))       # bare forecastle
    return p, ship_meta(L, B, fb, z_02 + 16.0, gun_y=L * 0.36,
                        gun_z=fb + SH + 2.7)


def type052d():
    """Type 052D Luyang III — hull 157.0 x 17.0 m, draught 6.0 m (published
    figures; cn.json air_defence_destroyer e6 carries mass 7 500 t, Type 346A
    AESA and the 64-cell VLS but no dims_m). Freeboard 5.9 m, sheer 2.2 m.

    A Burke-generation AAW ship on purpose — four canted array faces forward
    — so the separation is carried by everything else, all of it plan-legible:

      ONE funnel. The Burke's twin close-coupled funnels are its midships
      read; the 052D shows a single block and a single dark cap.
      EQUAL VLS FARMS, 32 + 32 (4x8 both), one on the forecastle and one
      between funnel and hangar — the Burke's farms are unequal (32/64) and
      the cruiser's sit at the extremities.
      The arrays sit LOW on a single slab-sided block (taper 0.96, near
      vertical), not on a pyramid: the faces are bigger, closer to the deck,
      and the block reads as one mass under a SOLID enclosed mainmast.
      HQ-10 on the hangar roof instead of an aft CIWS drum, and only ONE
      hangar door where the Burke has two.
      NO director domes at all — an AESA ship guides its own missiles, and
      the Burke carries three.
    """
    L, B, FB, SH = 157.0, 17.0, 5.9, 2.2
    p, fb = ship_hull(L, B, FB, bow=0.30, transom=0.84, sheer=SH)
    sup, top = superstructure(L * 0.095, fb,
                              ((44.0, 15.2, 6.2), (30.0, 13.4, 5.0, 0.0),
                               (16.0, 10.6, 4.2, 2.5)), taper=0.96)
    p += sup
    z_01, z_02, z_bridge = fb + 6.2, fb + 11.2, fb + 15.4

    for s in (-1, 1):                       # four Type 346A faces, LOW
        p += planar_array(s * 6.4, 26.5, fb + 8.7, 5.8, 5.2, 20, s * 30)
        p += planar_array(s * 6.4, 3.5, fb + 8.7, 5.8, 5.2, 20, -s * 150)

    # solid enclosed mainmast on the block, radome on the head
    p += lattice_mast(0, 6.5, z_02, 15.0, foot=5.0, head=2.4, bays=3,
                      solid=True, yards=((0.45, 10.0),), radome=1.6)
    p += ciws(0, 33.5, z_01, 1.10)                      # Type 1130, forward

    # after deckhouse and the ONE funnel
    p.append(deckhouse(-L * 0.072, 24.0, 12.6, 5.4, fb))
    p += funnel(0, -L * 0.078, fb + 5.4, 9.6, 8.8, 6.4, rake=8)
    p += air_search(0, -3.5, fb + 5.4, 6.8, 2.8)        # Type 517 mattress
    for s in (-1, 1):
        p += satcom(s * 4.4, -20.5, fb + 5.4, 1.40)
        p += esm_array(s * 7.2, 22.0, z_02)
        p += bridge_wing(s * 6.4, 24.0, z_bridge, gun=False)
        p += chaff_launcher(s * 6.8, 15.0, z_01, yaw=s * 30)
        p += boat_bay(s * B * 0.47, -L * 0.040, fb)
        p += torpedo_tubes(s * B * 0.32, -L * 0.155, fb + 0.4, yaw=s * 55)

    # aviation and the aft farm
    p += vls(0, -L * 0.192, fb, 4, 8)                   # 32 aft = 32 fwd
    p += hangar(-L * 0.290, 19.0, 13.2, 6.4, fb, doors=1)
    p += helipad(-L * 0.428, 13.0, 19.0, fb)
    with mat("deck"):                                   # HQ-10, hangar roof
        p.append(cube((0, -38.5, fb + 6.4 + 1.2), (3.4, 2.6, 2.0),
                      rot=(R(-20), 0, 0)))

    p += vls(0, L * 0.290, fb + SH, 4, 8)               # 32 fwd
    p += gun_mount(L * 0.385, fb + SH, r=1.95, barrel_l=6.8)   # H/PJ-38 130mm
    p += breakwater(L * 0.335, B * 0.70, fb + SH)
    p += anchor_gear(L * 0.440, fb + SH, B)
    p += clutter(hull_planform(L, B, bow=0.30, transom=0.84, w=0.90), fb,
                 spacing=34.0)
    p.append(team_patch(-47.0, fb + 6.4, 4.2, 5.0))     # hangar roof, aft
    return p, ship_meta(L, B, fb, z_02 + 15.0 + 2.0, gun_y=L * 0.385,
                        gun_z=fb + SH + 2.5)


def sub_kilo():
    """Project 877 Kilo — 72.6 x 9.9 m, published draught 6.2 m, 2 300 t
    surfaced (published figures; ru.json carries no submarine role). A
    double-hulled boat with a big reserve of buoyancy, so it rides HIGH:
    freeboard 1.70 m, showing 7.47 m wide in plan.

    WHAT SEPARATES IT FROM THE TYPE 209, since both are diesel boats:

      THE PLAN IS FAT. L/B = 7.3 against the 209's 10.0 — at the same zoom
      the Kilo is a wide teardrop where the 209 is a pencil, and the plan
      strip it shows (7.5 m) is half again the 209's 4.9 m.
      THE SAIL IS LONG AND LOW, 12 m for only 3.2 m of height, unstepped,
      with no fairwater planes (a Kilo's foreplanes are hull-mounted and
      retracted at the surface) — against the 209's short stepped fin.
      A RAISED WHALEBACK over the torpedo room: the bow casing steps up a
      dark half-metre with two bright hatches on it, where the 209's mark
      amidships is its light snorkel housing.
    """
    L, B, FB = 72.6, 9.9, 1.70            # published draught 6.2 m to the keel
    assert sub_show_width(B, FB) > B * 0.52
    p, axis, deck = sub_hull(L, B, FB, name="kilo")
    p += casing(L * 0.34, -L * 0.34, B * 0.54, deck - 0.10)
    top = deck - 0.10 + 0.42                                    # casing crown
    with mat("gunbore"):                                # the whaleback
        p.append(cube((0, L * 0.200, top + 0.20), (B * 0.40, L * 0.160, 0.40)))
    p += sub_fittings([L * 0.230, L * 0.165], top + 0.40, r=0.50)
    p += sail(L * 0.140, 12.0, 3.2, B * 0.30, deck, planes=False, masts=3)
    p += sub_fittings([-L * 0.140, -L * 0.260], top, r=0.62)
    p += stern_planes(L, B, axis, "cross")
    p += propulsor(L, B, axis, "screw")
    p.append(team_patch(-L * 0.060, top, 1.8, 2.6))
    return p, ship_meta(L, B, deck, deck + 3.2 + 3.4, gun_y=L * 0.2,
                        gun_z=deck + 1.0)


#          name                     L      B     fb   sheer  number
_ship_tex("nav_e3_ru_sovremenny", 156.0, 17.3, 5.2, 2.0, "715", bow=0.32)
_ship_tex("nav_e6_cn_052d",       157.0, 17.0, 5.9, 2.2, "172")
# no pennant number: Russian boats do not paint one on the sail
_sub_tex("sub_e2_ru_kilo",         72.6,  9.9, 1.70, None, 10.2, 3.2, 2.97)


NAVY = [
    ("nav_e4_us_destroyer",  destroyer_aaw,       "navy_haze"),
    ("nav_e1_us_frigate",    frigate_asw,         "navy_haze"),
    ("nav_e1_us_cruiser",    cruiser,             "navy_haze"),
    ("nav_e1_us_corvette",   corvette,            "navy_haze"),
    ("nav_e2_us_missileboat", missile_boat,       "navy_haze"),
    ("nav_e1_us_patrol",     patrol_vessel,       "navy_haze"),
    # sub_dark, not air_dark: same tone ladder, minus the aircraft-scale
    # panel speckle that read as stone masonry at a ship's 9 m camo tile.
    ("sub_e1_us_diesel",     sub_diesel,          "sub_dark"),
    ("sub_e2_us_nuclear",    sub_nuclear,         "sub_dark"),
    ("sub_e7_de_aip",        sub_aip,             "sub_dark"),
    ("sub_e1_kp_midget",     sub_midget,          "sub_dark"),
    ("nav_e1_us_carrier",    carrier,             "navy_haze"),
    ("nav_e2_us_amphib",     amphibious_assault,  "navy_haze"),
    ("nav_e1_us_landingcraft", landing_craft,     "navy_haze"),
    ("nav_e1_us_oiler",      fleet_oiler,         "navy_haze"),
    ("nav_e1_us_minewarfare", mine_warfare,       "navy_haze"),
    # soviet / chinese lineage (red team, same convention as army/fleet)
    ("nav_e3_ru_sovremenny", sovremenny,          "navy_haze", (0.68, 0.10, 0.10)),
    ("nav_e6_cn_052d",       type052d,            "navy_haze", (0.68, 0.10, 0.10)),
    ("sub_e2_ru_kilo",       sub_kilo,            "sub_dark",  (0.68, 0.10, 0.10)),
]

if __name__ == "__main__":
    H.set_out(os.path.join(ROOT, "art", "blockout", "e4_navy"))
    for entry in NAVY:
        name = entry[0]
        H.CAMO[name] = entry[2] if len(entry) > 2 else "navy_haze"
        H.TEAM[name] = entry[3] if len(entry) > 3 else (0.06, 0.20, 0.62)
    print("building navy...")
    for entry in NAVY:
        name, fn = entry[0], entry[1]
        for lod in (0, 1, 2):
            n = H.build(name, fn, lod)
            print(f"  {name:26s} LOD{lod}  {n:6d} tris")
    print("done")
