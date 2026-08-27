"""The 19 structures from docs/12-unit-roster.md - SHARED HELPERS ONLY.

    /Applications/Blender.app/Contents/MacOS/Blender -b --python tools/structure_models.py

This module holds no models yet. It holds the CONTRACT that every structure
model is built from, so that nineteen buildings written by different hands come
out looking like nineteen buildings from one game instead of nineteen unrelated
boxes. Read this whole header before adding a role to STRUCTURES.


1. WHY BUILDINGS ARE A DIFFERENT PROBLEM FROM VEHICLES
======================================================
The camera is fixed three-quarter overhead. Measured off the existing gameplay
render (tools/gameplay_render.py, camera elevation 52 deg): at that angle a
surface facing straight up projects to cos(38 deg) = 0.79 of its true area,
while a vertical wall projects to sin(38 deg) = 0.62 - and only the two walls
facing the camera are visible at all. For a 20 x 20 m building 10 m tall that
is 315 m2 of visible roof against 2 x 124 = 248 m2 of visible wall, and the
wall figure is the OPTIMISTIC one because neighbouring buildings, trees and
the building's own parapet eat into it constantly while nothing ever occludes
the roof.

    THE ROOF IS THE FACE OF THE BUILDING. A structure whose identity lives on
    its walls has no identity in this game.

Vehicles do not have this problem: a tank is 2.4 m tall and its roof and its
plan are the same rectangle, so its identity has nowhere else to live anyway.
A building is 8-22 m tall and has a genuine choice about where to put the
read. Put it on the roof, every time.


2. HOW A PLAYER KNOWS A THING IS A BUILDING AND NOT A VEHICLE
=============================================================
Four cues, in descending order of strength. The first two are mandatory on
every one of the nineteen; a model that skips them is wrong however good it is.

  (a) IT SITS ON AN APRON. Every structure starts with apron() - a graded slab
      of concrete or asphalt 0.18-0.24 m thick that extends 2.0 m beyond the
      building on every side. This is the single most valuable helper in the
      file and it does three separate jobs:
        - it removes the shadow gap. A vehicle reads as an object RESTING on
          the terrain because AO darkens the ground under its belly and the
          silhouette floats on that dark line (hero_models.running_gear exists
          almost entirely to produce that gap). A building has no gap: the
          apron is welded to the terrain and the contact AO lands on the apron
          EDGE, 2 m out from the wall, where it reads as a hard bright collar
          rather than a lifted hull.
        - it declares the grid cell. The apron IS the footprint the player is
          placing, drawn on the ground at full size, so two buildings dropped
          side by side show their spacing.
        - it gives every structure a rectangular, axis-aligned outer plan even
          when the mass on top of it is cruciform, circular or hexagonal.

  (b) NO WHEELS, NO TRACKS, NO TURRET, NO BARREL, AND NO NOSE. The first four
      are obvious. The fifth is the one that gets forgotten: a vehicle plan is
      an arrow - longer than it is wide, tapered or sloped at the front, and
      it points somewhere. A building plan must be between 1:1 and 2:1 and
      must be symmetric about at least one axis, so it points nowhere. The two
      structures that legitimately face a direction (coastal_battery,
      hardened_shelter) express it with a dark OPENING, never with a taper.

  (c) HUMAN SCALE ON THE OUTSIDE. Vehicles carry hatches; only buildings carry
      external staircases, landings, handrails, roof ladders and 2.1 m doors.
      stair() is cheap and it is the fastest way to tell the player that the
      thing he is looking at is 12 m tall and not 3 m tall. Use it on anything
      over 6 m.

  (d) VERTICAL WALLS AND A HARD ROOF EDGE. Vehicle plate is sloped for ballistic
      reasons and every silhouette in this project reads that slope. Building
      walls go straight up and stop at a hard horizontal line. The exception is
      the fortification family, which has no walls at all - see below.


3. THE THREE FAMILIES
=====================
Nineteen flat-roofed boxes would be unreadable, so the roster splits into three
families with three different ROOF GRAMMARS. Family is legible before role is:
a player should know he is looking at industry, at a military installation or
at a fortification from the roof texture alone, at 48 px, before he works out
which one.

  INDUSTRIAL - power_plant, oil_derrick, refinery, supply_depot, light_factory,
  heavy_factory, naval_yard, repair_depot.
      Roof grammar: BROKEN AND REPEATING. Sawtooth ribs, barrel vaults, crane
      rails, pipe runs, tank tops. Industrial roofs are never plain and never
      have a parapet - the ribs and the plant ARE the surface. Every industrial
      structure also carries at least one TALL THIN VERTICAL (stack, column,
      derrick, crane leg) that throws a long shadow across its own apron, which
      is what separates industry from military at a glance: the military family
      is flat, the industrial family bristles.
      Palette: body camo mass, gun-grey steel for everything tubular, glass for
      north-lights, gunbore for openings. Concrete is used for the apron only.

  MILITARY / ADMINISTRATIVE - hq, barracks, airbase, helipad, fixed_radar,
  ew_station, research_facility.
      Roof grammar: FLAT, PLAIN AND FRAMED. A parapet ring 0.85 m tall runs the
      whole perimeter and casts a thin unbroken shadow line INSIDE the roof -
      from directly overhead that line is what makes the plan outline crisp.
      Inside the frame the roof stays deliberately empty: a small vent cluster,
      the team band, and one identity object. Antennas and markings, not
      machinery.
      Palette: deck concrete roof against body-camo walls. The value step
      between the two is the point, and it is bigger than it sounds - see the
      measured ladder in section 5. The roof is the DARK element and the walls
      are the light one, which is the opposite of the intuition and the reason
      the parapet works: a pale ring around a dark field.

  FORTIFICATION - hardened_shelter, fixed_sam, coastal_battery, bunker.
      Roof grammar: NO ROOF AND NO WALLS. The profile is earth: a berm that
      slopes from the ground up over the structure, so the plan outline and the
      roof outline are different sizes - a thick soft-value ring of earth
      around a small hard core. Nothing else in the game has that ring, which
      makes it the strongest family cue available; it also happens to be what
      hardening actually looks like.
      Palette: era-group olive earth for the berm, deck concrete for the core,
      gunbore black for every opening. No camo, no team colour on the berm -
      the team band goes on the core, small.

  Read as three plan textures: industry is STRIPED, military is FRAMED,
  fortification is RINGED.


4. THE NINETEEN OWNERSHIP RULES
===============================
Each structure OWNS exactly one silhouette element, readable from directly
overhead, and no other structure may use it. These are rules, not suggestions:
the ground audit found four vehicles that were "four indistinguishable tan
rectangles" at 48 px, and nineteen flat-roofed boxes would be far worse. If a
role needs a shape that is on this list under another role's name, it needs a
different shape.

The dangerous collisions were identified first and given the widest separation:
the three production halls (light_factory / heavy_factory / naval_yard) are
separated by ROOF GRAMMAR - fine stripes, one heavy crossbar, a cut-out void -
rather than by size; the three logistics yards (supply_depot / repair_depot /
refinery) by PLAN TEXTURE - a modular grid, a three-band stripe, a field of
circles; and the two mast roles (fixed_radar / ew_station) by COUNT - one big
solid thing high up against many small thin things in a circle.

    key                owns exclusively
    ---------------------------------------------------------------------
    hq                 the STEPPED ROOF - a second, smaller roof deck on top
                       of the main one, with its own parapet. The only
                       roof-on-roof in the game; its step casts a hard shadow
                       across the lower deck that no other structure has.
    power_plant        TWO EQUAL TAPERED STACKS side by side. Circles are rare
                       in a rectangular roster and a matched PAIR of them is
                       unique. Other roles may have one stack; never two alike.
    oil_derrick        the OPEN LATTICE DERRICK over a bare pad - the only
                       structure you can see the terrain through, so from
                       overhead it is a square of thin lines, not a mass.
    refinery           SPHERES AND A COLUMN - a field of circles of UNEQUAL
                       diameter including true hemispheres on legs. No other
                       role gets a sphere or more than two circles in plan.
    supply_depot       the MODULAR CONTAINER GRID - a repeating checkerboard of
                       identical 6 m boxes with lanes between. The only
                       repeating array of separate objects in the roster.
    barracks           THREE PARALLEL GABLE RIDGES with gaps between the huts.
                       Symmetric, coarse, separated - the deliberate opposite
                       of light_factory's asymmetric fine sawtooth.
    light_factory      the SAWTOOTH ROOF - glazed north-lights at 4 m pitch,
                       reading as fine parallel dark-blue stripes.
    heavy_factory      the GANTRY CRANE BRIDGE - two rails down the long edges
                       and one heavy bar across, an H in plan, on a CLOSED
                       hall. Nothing else carries a transverse bridge on a roof.
    airbase            the PAINTED ASPHALT APRON - the largest continuous
                       near-black surface in the game, with threshold chevrons
                       and open-fronted arch hangars along one edge.
    hardened_shelter   the CAPSULE - a single earth-covered barrel arch with
                       semicircular ends and one dark mouth. The only
                       rounded-end plan.
    helipad            the CIRCLE-AND-H on a raised square pad with corner
                       light masts. The aviation symbol, and the only painted
                       circle.
    naval_yard         the WATER NOTCH - a basin cut INTO the plan from one
                       edge, dark water inside it, straddled by a PORTAL crane
                       on legs. The only negative volume and the only U plan.
    fixed_radar        the FLOATING ARRAY - one large solid rectangle held clear
                       of the ground on a lattice tower at 28 m, seen from above
                       as a bar offset from its own building with its shadow
                       lying across the pad.
    fixed_sam          FOUR PARALLEL ELEVATED CANISTERS in a square revetment -
                       four bright tube mouths in a row, inside an earth ring.
    coastal_battery    the ROUND CASEMATE - a concrete drum in a circular berm
                       with one radial embrasure slot. The only circular
                       building outline in the roster.
    ew_station         the ANTENNA RING - sixteen thin masts on a circle round a
                       small hut, reading as a DOTTED circle. Many small
                       verticals, which is the opposite read to fixed_radar's
                       one big one.
    research_facility  the CRUCIFORM PLAN - two 8 m wings crossing at right
                       angles with a glazed lantern along both spines. The only
                       non-rectangular administrative plan, and it still sits in
                       a square grid cell.
    repair_depot       the THREE-BAND HARDSTAND - open canopy, black through-
                       lane with inspection pits, open canopy. Roof on columns
                       with NO walls; bright-dark-bright in plan.
    bunker             the HEXAGON - a small six-sided pillbox with a black
                       embrasure on every face inside a sandbag ring. The only
                       hexagonal plan.

Two of these are shared TECHNIQUES rather than shapes and are policed by the
helpers: only power_plant may call stack() twice with equal arguments, and only
heavy_factory and naval_yard may call gantry() - the first without legs, the
second with them.


5. TEAM COLOUR IS A ROOF MARKING, NOT A TRIM
============================================
docs/07 is explicit that same-role distinction is a colour problem and that
team colour belongs "on large flat areas visible from directly above". For
structures that is not decoration, it is the whole ownership channel: a captured
or enemy refinery is the same model. team_mark() puts a band across the roof at
a fixed proportion of the roof area (12 percent by default) in a fixed place -
the edge nearest -Y. Fixed place matters more than size: the eye finds a
consistent mark faster than a large one.


6. THE VALUE LADDER, MEASURED
=============================
Structures have no camouflage disruption to hide behind and no running gear to
break their outline, so material VALUE does most of the separating. These are
the eight groups' luminances, computed as 0.2126R + 0.7152G + 0.0722B over
hero_models.GROUP_MATS (and, for `body`, over the mean pixel of camo_us.png):

    body    camo wall     0.588      <- by far the lightest thing available
    era     earth berm    0.219
    gun     bare steel    0.116
    deck    concrete      0.098
    glass   glazing       0.056
    track   asphalt       0.048
    gunbore void          0.012

Three consequences, all of which cost a model its read if ignored:

  * A CONCRETE ROOF IS SIX TIMES DARKER THAN A CAMO WALL. That is the largest
    value step in the palette and it is free. Every flat-roofed structure gets
    it automatically by using deck for the roof and body for the walls, and it
    is why the parapet ring reads: a pale 0.3 m band around a dark field.

  * STEEL DOES NOT READ AGAINST CONCRETE. gun 0.116 against deck 0.098 is a
    ratio of 1.18 - invisible at gameplay zoom. Masts, ducts, cranes and
    handrails must be seen against a camo wall, against the sky, or against
    their own shadow on the apron. Never lay steel kit flat on a concrete roof
    and expect it to be the identity element; on a flat roof the identity has
    to be a shape that breaks the parapet line or a team/camo-coloured mass.

  * A BLACK OPENING NEEDS A LIGHT SURROUND. gunbore 0.012 against body 0.588 is
    49:1 and unmissable; against track asphalt it is 4:1 and nearly gone. Cut
    embrasures and hangar mouths into camo or concrete, not into tarmac.

Verified by rendering: four probe structures built only from the helpers below,
placed with three M1 blockouts for scale, rendered top-down orthographic over a
100 m field at 190 px (1.9 px/m, so a 20 m building is 38 px across). All four
were separable from each other and from the tanks at that size - framed dark
roof, striped roof, olive ring, open lattice square.


7. FOOTPRINTS
=============
FOOTPRINT is a real number in metres and it is gameplay, not art. game/sim
already fixes five of them and they are BINDING - the art plan must fit inside
footprint x footprint or placement and collision disagree with the picture:

    hq 26 - heavy_factory 20 - airbase 48 - naval_yard 36 - bunker 10

Every other structure defaults to 12.0 m in sim_roster.gd because it was left
unspecified, which is wrong for a refinery and wrong for a helipad. FOOTPRINTS
below is the art contract for all nineteen, chosen so that the five binding
values are anchors and the ladder between them means something. Each entry
records what the size is based on. Plans are laid out on a 4.0 m GRID.

The scalar is the LONGEST PLAN DIMENSION including the apron, so a structure
with footprint 24 occupies a 24 x 24 m cell whatever shape sits in it. Two
arithmetic traps follow from that and both have already been checked here:

    plan_w + 2 * APRON_MARGIN  <=  footprint_m
    berm(w, l, ..., base=b) extends b metres beyond w and l ON EACH SIDE, so a
    revetted role must size its CORE at plan_w - 2 * b, not at plan_w

All nineteen rows satisfy the first with the default 2.0 m margin. fixed_sam,
coastal_battery, hardened_shelter and bunker are the four that have to do the
second sum.


8. HOW TO ADD A ROLE
====================
Same contract as every other model module. A model function takes no arguments
and returns (parts, meta):

    def refinery():
        p = []
        p += apron(32, 28)
        ...
        return p, struct_meta(32, 28, roof_z=9.0, mount_z=22.0)

then append ("bld_e1_us_refinery", refinery) to STRUCTURES. hero_models.build()
joins by material group, bevels, bakes AO against a ground plane and exports
three LODs. Name prefix is "bld" so tools/validate_sockets.py picks up the
building envelope and the hull socket contract.

WHAT EVERY MODEL FUNCTION OWES THE PLAYER, restated as a checklist:
    - apron() first, before anything else
    - a plan between 1:1 and 2:1, symmetric about at least one axis
    - the one silhouette element this role owns EXCLUSIVELY, on the roof or in
      the plan, stated as a comment in the docstring so nobody erodes it later
    - team_mark() on the largest horizontal surface
    - stair() if it is over 6 m tall
    - nothing below z = 0 (validate_sockets fails at -0.02)
"""
import bpy, functools, math, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import hero_models as H
from hero_models import cube, cyl, dome, profile, use, R

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The placement grid. Every plan dimension in this module is a multiple of it,
# so any two structures dropped next to each other line up.
GRID = 4.0

# How far the apron runs past the mass, per side. 2.0 m is a working figure and
# a legible one: at the render scale used for the audit sheets it is 4-5 px of
# bright concrete all the way round the building, which is enough to separate
# two structures built shoulder to shoulder.
APRON_MARGIN = 2.0

# Material groups, restated in building terms. These are hero_models.GROUP_MATS
# and there are no others - do not add groups, reinterpret them:
#
#   body     painted wall, rendered blockwork, tank shells   (camo texture)
#   deck     concrete: aprons, roof decks, parapets, cores   (pale warm grey)
#   track    asphalt: airbase aprons, tarred roofs, roads     (near black)
#   gun      bare steel: masts, lattice, pipes, cranes, rails (mid grey)
#   glass    glazing: north-lights, clerestory, control rooms (dark blue)
#   gunbore  VOIDS: embrasures, hangar mouths, pits, water    (almost black)
#   era      earth: berms, revetment fill, sandbags           (olive)
#   team     the ownership band                               (team colour)
CONCRETE, ASPHALT, STEEL, EARTH, VOID = "deck", "track", "gun", "era", "gunbore"


def keeps_group(fn):
    """Every helper below restores the caller's material group on the way out.

    hero_models.use() sets a module-level global, so a helper that called
    use("gun") and then returned would silently retag the caller's next
    primitive - and a helper that called another helper would be retagged
    mid-body. That bug is invisible until a render comes back with a concrete
    apron painted in camouflage. Wrap, save, restore.
    """
    @functools.wraps(fn)
    def wrapped(*a, **k):
        prev = H.CURRENT
        try:
            return fn(*a, **k)
        finally:
            use(prev)
    return wrapped


# ═══ FOOTPRINTS ════════════════════════════════════════════════════════════
# key -> (footprint_m, plan_w, plan_l, basis)
# footprint_m is the grid cell and the longest plan dimension including apron.
# plan_w / plan_l are the mass INSIDE the apron, on the 4 m grid.
FOOTPRINTS = {
    "hq":              (26.0, 22.0, 22.0, "ROSTER. 3-storey permanent post headquarters block, "
                                          "22 m square at 3.6 m per storey; mount 14 m is the "
                                          "comms tower on the penthouse"),
    "power_plant":     (24.0, 20.0, 16.0, "turbine hall of a ~50 MW oil/gas station. Real halls "
                                          "run 30-40 m; compressed to the grid, but the two "
                                          "stacks keep their full roster height of 18 m"),
    "oil_derrick":     (16.0, 12.0, 12.0, "single-well production site: 9 m square derrick base "
                                          "on a 12 m graded pad, crown at the roster's 20 m"),
    "refinery":        (32.0, 28.0, 24.0, "one small crude-distillation unit: a 22 m column "
                                          "(roster mount), three 9 m spheres (~380 m3, real "
                                          "small-LPG size), pipe rack between them"),
    "supply_depot":    (20.0, 16.0, 16.0, "open container hardstand: 3 x 2 rows of 6.06 m ISO "
                                          "boxes stacked 2 high (2.59 m each) with 3 m lanes"),
    "barracks":        (24.0, 20.0, 20.0, "three company huts, each 20 x 5.5 m at 5 m centres - "
                                          "the US 700-series barracks hut is 9 x 30 m, scaled "
                                          "to the grid and kept as three separate ridges"),
    "light_factory":   (16.0, 12.0, 12.0, "light-vehicle assembly shed, 3 sawtooth bays at 4 m. "
                                          "Real north-light bays are 6-9 m; 4 m is a declared "
                                          "exaggeration so the ribs read as stripes at 48 px"),
    "heavy_factory":   (20.0, 16.0, 16.0, "ROSTER. Single-bay armour hall spanned by a 16 m "
                                          "overhead travelling crane, 30 t class, eaves at the "
                                          "roster's 12 m - enough to lift a hull over a hull"),
    "airbase":         (48.0, 44.0, 40.0, "ROSTER. Operational readiness platform: 44 m of apron "
                                          "clears a 15 m-span fighter with room to turn, plus "
                                          "two 18 x 14 m open hangars along one edge"),
    "hardened_shelter": (24.0, 20.0, 14.0, "NATO 3rd-generation HAS (TAB-VEE type), about "
                                           "26 x 17 m on plan and 8-9 m to the crown inside"),
    "helipad":         (16.0, 12.0, 12.0, "TLOF/FATO for a UH-60-class helicopter. Real minima "
                                          "are TLOF 0.83 x and FATO 1.0 x the 19.8 m overall "
                                          "length; here the 12 m raised pad is the TLOF, the "
                                          "16 m apron is the FATO safety area"),
    "naval_yard":      (36.0, 32.0, 32.0, "ROSTER. Small building dock: a 10 x 24 m basin cut "
                                          "into the plan, straddled by a portal crane on 16 m "
                                          "gauge rails, 14 m under the beam"),
    "fixed_radar":     (20.0, 12.0, 12.0, "equipment shelter under a 28 m tower - the tower is "
                                          "the roster's own mount figure and its 200 km "
                                          "reference range depends on it"),
    "fixed_sam":       (20.0, 16.0, 16.0, "four-cell hardened launcher in a square earth "
                                          "revetment; the 5.2 m canister is the Patriot figure "
                                          "already used by army_models.long_sam"),
    "coastal_battery": (22.0, 18.0, 18.0, "casemated coastal emplacement, Atlantic-Wall class: "
                                          "a 12 m concrete drum inside a 22 m earth apron"),
    "ew_station":      (24.0, 20.0, 20.0, "circularly-disposed antenna array. AN/FLR-9 is 260 m "
                                          "across - scaled by 1/11 and DECLARED, because the "
                                          "real one is a map feature rather than a building"),
    "research_facility": (24.0, 20.0, 20.0, "mid-century laboratory block, cruciform for "
                                            "daylight: 8 m wing depth is the limit for a "
                                            "double-loaded lab corridor"),
    "repair_depot":    (20.0, 16.0, 16.0, "field maintenance hardstand: two 7 m canopy bays take "
                                          "a 4 m-wide vehicle with working room either side, "
                                          "split by a 6 m through-lane"),
    "bunker":          (10.0, 6.0, 6.0, "ROSTER. Reinforced-concrete pillbox: a 6 m hexagonal "
                                        "chamber inside a 2 m earth apron"),
}


# ═══ the meta contract ═════════════════════════════════════════════════════
def struct_meta(w, l, roof_z, mount_z=None, door_y=None):
    """The dict hero_models.build() needs, in building terms.

    build() calls sockets_for(m), which was written for tanks. The mapping for
    a structure is:

        top          roof deck height        -> SOCKET_turret_mount, damage_hull
        turret_top   the MOUNT height        -> SOCKET_sensor_mast, damage_turret
        gun_z/gun_y  the main opening        -> SOCKET_gun_mantlet
        hull_w/l     plan, apron excluded    -> track_*, exhaust

    `mount_z` must be the roster's "mount" value for the role - it is the
    sensor/antenna height the simulation uses for radar horizon, so the model
    and the sim have to agree on it. Defaults to the roof.
    """
    mount_z = roof_z if mount_z is None else mount_z
    return dict(top=roof_z, hull_l=l, hull_w=w,
                turret_top=mount_z,
                gun_z=min(3.2, roof_z * 0.5),
                gun_y=-l / 2 if door_y is None else door_y)


# ═══ GROUND ════════════════════════════════════════════════════════════════
@keeps_group
def apron(w, l, margin=APRON_MARGIN, h=0.20, group=CONCRETE, kerb=True):
    """The graded slab every structure stands on. CALL THIS FIRST.

    Returns the slab, and optionally a kerb ring 0.12 m proud of it. Top face
    is at `h`, so the building mass that follows starts at z=h and there is no
    gap anywhere: apron to terrain, mass to apron.

    The kerb is not decoration. From directly overhead a plain slab and the
    terrain are both flat and the AO bake has nothing to bite on, so the
    footprint edge goes soft; a 0.12 m upstand puts a hard shadow line exactly
    on the boundary of the grid cell the player just spent money on.
    """
    W, L = w + 2 * margin, l + 2 * margin
    use(group)
    p = [cube((0, 0, h / 2), (W, L, h))]
    if kerb and margin > 0.4:
        for s in (-1, 1):
            p.append(cube((s * (W / 2 - 0.18), 0, h + 0.06), (0.36, L, 0.12)))
            p.append(cube((0, s * (L / 2 - 0.18), h + 0.06), (W, 0.36, 0.12)))
    return p


@keeps_group
def markings(z, lines=(), group="team", t=0.06):
    """Painted lines on an apron. `lines` are (cx, cy, lw, ll) in metres.

    Painted geometry is 0.06 m proud rather than coplanar: a coincident face
    z-fights, and 0.06 m also gives the bevel something to catch so the mark
    survives the LOD2 decimate as a shape rather than a texture.
    """
    use(group)
    p = [cube((cx, cy, z + t / 2), (lw, ll, t)) for (cx, cy, lw, ll) in lines]
    return p


@keeps_group
def team_mark(w, l, z, frac=0.12, edge=-1, group="team"):
    """The ownership band. MANDATORY on every structure.

    A single band across the full width of the largest horizontal surface,
    placed against the -Y edge (edge=-1) or +Y edge, sized to `frac` of that
    surface's area. Fixed POSITION is worth more than size - the eye locates a
    mark that is always in the same place far faster than a big one that moves,
    and this is the only channel that tells a player whose refinery that is.
    """
    band = max(1.2, l * frac)
    use(group)
    p = [cube((0, edge * (l / 2 - band / 2 - 0.35), z + 0.05),
              (w - 0.7, band, 0.10))]
    return p


# ═══ MASS ══════════════════════════════════════════════════════════════════
@keeps_group
def box_building(w, l, h, z=0.20, group="body", batter=0.0):
    """A walled mass with vertical sides and a hard top edge, standing ON the
    apron. `batter` tapers the top in by that many metres per side, which is
    for the fortification family only - buildings do not slope.

    Blockout convention: solid, not hollow. Nothing sees inside.
    """
    use(group)
    if batter <= 0.0:
        p = [cube((0, 0, z + h / 2), (w, l, h))]
    else:
        # square frustum via profile: cross-section in Y-Z, extruded along X.
        # Two crossed prisms would seam; one prism plus end caps is cheaper and
        # the ends are what the player sees least.
        o = profile([(-l / 2, z), (l / 2, z),
                     (l / 2 - batter, z + h), (-l / 2 + batter, z + h)], w, "mass")
        p = [o]
    return p


@keeps_group
def parapet_roof(w, l, z, rail=0.85, t=0.30, group=CONCRETE, deck_group=None):
    """MILITARY FAMILY roof: a flat deck with an unbroken parapet ring.

    The parapet is the family badge. It is 0.85 m - real parapets are 1.0-1.1 m
    to code, and 0.85 m is the height at which, at the game's 52 deg camera, the
    ring throws a 0.66 m shadow onto its own deck: a bright deck with a dark
    line inset all the way round, which is the crispest plan outline available
    from directly overhead and costs eight boxes.

    Returns deck + four parapet runs. `z` is the top of the walls.
    """
    use(deck_group or group)
    p = [cube((0, 0, z + t / 2), (w, l, t))]
    use(group)
    for s in (-1, 1):
        p.append(cube((s * (w / 2 - 0.15), 0, z + t + rail / 2), (0.30, l, rail)))
        p.append(cube((0, s * (l / 2 - 0.15), z + t + rail / 2), (w, 0.30, rail)))
    return p


@keeps_group
def sawtooth_roof(w, l, z, bays=3, rise=2.2, glaze=0.62, group="body"):
    """INDUSTRIAL FAMILY roof: north-light sawtooth, ribs running along X.

    Each bay is a right triangle - a long shallow slope facing -Y and a short
    vertical GLAZED riser facing +Y. From overhead the glazing is a set of
    parallel dark-blue stripes at a fixed pitch, which is a texture no other
    structure has and which survives to LOD2 because it is real geometry.

    `bays` x pitch = l, so pitch = l / bays. Keep pitch at 4 m or under: at
    6 m the stripes stop reading as stripes and start reading as steps.
    """
    pitch = l / float(bays)
    p = []
    for i in range(bays):
        y0 = -l / 2 + i * pitch
        use(group)
        p.append(profile([(y0, z), (y0 + pitch, z),
                          (y0 + pitch, z + rise), (y0, z + rise * 0.18)],
                         w, "tooth"))
        use("glass")
        p.append(cube((0, y0 + pitch - 0.12, z + rise - glaze / 2 + 0.02),
                      (w - 0.5, 0.24, glaze)))
    return p


@keeps_group
def gable_roof(w, l, z, rise, group="body", along="x"):
    """Symmetric double-pitch, ridge running along X (`along="x"`) or Y.

    Reserved for the barracks family of huts. It must stay visually distinct
    from sawtooth_roof: a gable is SYMMETRIC and coarse (one ridge per hut,
    huts spaced apart), a sawtooth is asymmetric and fine (many ribs, no gaps).
    """
    use(group)
    if along == "x":
        o = profile([(-l / 2, z), (l / 2, z), (0, z + rise)], w, "gable")
    else:
        o = profile([(-w / 2, z), (w / 2, z), (0, z + rise)], l, "gable")
        o.rotation_euler = (0, 0, R(90))
    return [o]


@keeps_group
def barrel_roof(w, l, z, rise, v=14, group=CONCRETE, span="x"):
    """A half-cylinder vault. Arch shelters, hardened shelters, hangar bays.

    `span="x"` puts the axis along X so the arch springs from the two Y walls.
    From overhead this is a rounded rectangle whose brightest band runs down
    the crown - a soft-edged capsule, and the only curved roof in the roster.
    """
    use(group)
    if span == "x":
        o = cyl((0, 0, z), rise, w, rot=(0, R(90), 0), v=v)
        o.scale = (1.0, l / (2.0 * rise), 1.0)
    else:
        o = cyl((0, 0, z), rise, l, rot=(R(90), 0, 0), v=v)
        o.scale = (w / (2.0 * rise), 1.0, 1.0)
    return [o]


@keeps_group
def door(x, y, z, w, h, facing="y", depth=0.45, group=VOID):
    """A dark opening recessed into a wall - hangar mouth, shelter throat,
    embrasure, roller shutter.

    Openings are the only way a structure is allowed to indicate a direction.
    A taper or a slope would make it a vehicle; a black rectangle on one face
    reads as a door from any angle and reads as nothing from directly above,
    which is correct - a door is not a roof feature.
    """
    use(group)
    if facing == "y":
        p = [cube((x, y, z + h / 2), (w, depth, h))]
    else:
        p = [cube((x, y, z + h / 2), (depth, w, h))]
    return p


# ═══ ROOFTOP AND SERVICES KIT ══════════════════════════════════════════════
@keeps_group
def vent_kit(w, l, z, n=3, group=CONCRETE, duct=True, seed=0):
    """Rooftop plant: air-handling boxes, extract cowls and a duct spine.

    This is the read that says "occupied building" as opposed to "a slab". Keep
    it SMALL - it is texture, not identity. Anything on a roof big enough to be
    identified from 48 px is competing with the element that role owns, and the
    ownership rules in this module's header always win.

    Deterministic layout from `seed`; nothing here uses random().
    """
    p = []
    use(group)
    for i in range(n):
        t = (i + 0.5) / n
        x = (t - 0.5) * (w - 3.0)
        y = ((seed + i) % 3 - 1) * (l * 0.22)
        p.append(cube((x, y, z + 0.55), (2.10, 1.60, 1.10)))
        p.append(cube((x, y, z + 1.22), (1.70, 1.20, 0.24)))
    use(STEEL)
    for i in range(n):
        t = (i + 0.5) / n
        x = (t - 0.5) * (w - 3.0)
        p.append(cyl((x + 1.4, (seed % 2 - 0.5) * l * 0.3, z + 0.65), 0.34, 1.30, v=10))
    if duct:
        p.append(cube((0, l * 0.34, z + 0.75), (w - 2.4, 0.90, 0.90)))
    return p


@keeps_group
def duct_run(a, b, r=0.34, group=STEEL, v=10):
    """A pipe or duct between two 3-tuples, with a flange at each end.

    Industrial structures earn their family read from external services: pipes
    that leave the mass and land on something else. A pipe that goes nowhere is
    worse than no pipe, so both ends must terminate on real geometry.
    """
    ax, ay, az = a
    bx, by, bz = b
    dx, dy, dz = bx - ax, by - ay, bz - az
    ln = math.sqrt(dx * dx + dy * dy + dz * dz)
    if ln < 1e-4:
        return []
    use(group)
    ry = math.acos(max(-1.0, min(1.0, dz / ln)))
    rz = math.atan2(dy, dx)
    o = cyl(((ax + bx) / 2, (ay + by) / 2, (az + bz) / 2), r, ln,
            rot=(0, ry, rz), v=v)
    p = [o]
    for (px, py, pz) in (a, b):
        p.append(cyl((px, py, pz), r * 1.35, 0.18, rot=(0, ry, rz), v=v))
    return p


@keeps_group
def stack(x, y, z, h, r, taper=0.70, group="body", cap=True, bands=2):
    """A chimney or exhaust stack: a tapered cylinder with a steel cap.

    Two of these in a row is power_plant's exclusive element, so DO NOT put a
    pair of equal stacks on anything else. A single stack of a different height
    is available to any industrial role.
    """
    use(group)
    p = [cyl((x, y, z + h / 2), r, h, v=16, taper=taper)]
    use(STEEL)
    if cap:
        p.append(cyl((x, y, z + h + 0.15), r * taper * 1.22, 0.42, v=16))
    for i in range(bands):
        zb = z + h * (0.42 + 0.28 * i)
        rb = r * (1.0 + (taper - 1.0) * (zb - z) / h)
        p.append(cyl((x, y, zb), rb * 1.08, 0.22, v=16))
    return p


@keeps_group
def mast(x, y, z, h, r=0.13, group=STEEL, stays=True, head=None):
    """A slim guyed mast. `head` is an optional (w, l, t) box at the top.

    A mast alone is NOT an identity - three roles could carry one. It is a
    height cue and a services cue. The identity belongs to what is on top of
    it, and to whether it stands on a lattice tower instead (see below).
    """
    use(group)
    p = [cyl((x, y, z + h / 2), r, h, v=8)]
    if stays:
        for k in range(3):
            a = R(90 + k * 120)
            p += duct_run((x, y, z + h * 0.78),
                          (x + math.cos(a) * h * 0.34, y + math.sin(a) * h * 0.34, z),
                          r=0.05, v=6)
    if head:
        hw, hl, ht = head
        p.append(cube((x, y, z + h + ht / 2), (hw, hl, ht)))
    return p


@keeps_group
def lattice_tower(x, y, z, h, base_w, top_w, bays=6, leg=0.16, group=STEEL):
    """An open four-leg braced tower - the TRANSPARENT structure.

    This is worth spelling out because it is the rarest read in the file: a
    lattice tower is the only thing in the roster you can see the ground
    THROUGH. From directly overhead it is not a shape, it is a small open
    square of thin lines with terrain inside it, and the AO bake puts the
    tower's shadow on the apron beside it rather than under it. Two roles use
    it - oil_derrick (with a crown block, no array) and fixed_radar (with an
    array, no crown block) - and they are told apart by what is on top.
    """
    use(group)
    p = []
    for i in range(bays):
        f0, f1 = i / float(bays), (i + 1) / float(bays)
        z0, z1 = z + h * f0, z + h * f1
        w0 = base_w + (top_w - base_w) * f0
        w1 = base_w + (top_w - base_w) * f1
        for sx in (-1, 1):
            for sy in (-1, 1):
                p += duct_run((x + sx * w0 / 2, y + sy * w0 / 2, z0),
                              (x + sx * w1 / 2, y + sy * w1 / 2, z1),
                              r=leg / 2, v=6, group=group)
        # one diagonal per face per bay, alternating hand so the tower reads as
        # braced rather than as four sticks
        d = 1 if i % 2 else -1
        for sy in (-1, 1):
            p += duct_run((x - d * w0 / 2, y + sy * w0 / 2, z0),
                          (x + d * w1 / 2, y + sy * w1 / 2, z1),
                          r=leg / 3, v=5, group=group)
        for sx in (-1, 1):
            p += duct_run((x + sx * w0 / 2, y - d * w0 / 2, z0),
                          (x + sx * w1 / 2, y + d * w1 / 2, z1),
                          r=leg / 3, v=5, group=group)
        p.append(cube((x, y, z1), (w1, leg * 0.7, leg * 0.7)))
        p.append(cube((x, y, z1), (leg * 0.7, w1, leg * 0.7)))
    return p


@keeps_group
def stair(x, y, z0, z1, w=1.30, run=None, group=STEEL, facing="y"):
    """An external staircase with a top landing - the human-scale cue.

    Treads are 0.28 m going / 0.18 m rise, which is the real ratio, so the
    flight itself carries the scale information. Use on anything over 6 m; it
    is the cheapest way to stop a 12 m building reading as a 3 m one.
    """
    rise = max(0.4, z1 - z0)
    n = max(3, int(rise / 0.18))
    run = run or n * 0.28
    use(group)
    p = []
    for i in range(n):
        f = (i + 0.5) / n
        d = -run / 2 + run * f
        zz = z0 + rise * f
        if facing == "y":
            p.append(cube((x, y + d, zz), (w, run / n * 1.05, 0.06)))
        else:
            p.append(cube((x + d, y, zz), (run / n * 1.05, w, 0.06)))
    # stringers and a handrail, so the flight is a solid diagonal in profile
    a0 = (x, y - run / 2, z0) if facing == "y" else (x - run / 2, y, z0)
    a1 = (x, y + run / 2, z1) if facing == "y" else (x + run / 2, y, z1)
    for s in (-1, 1):
        o0 = (a0[0] + (s * w / 2 if facing != "y" else 0),
              a0[1] + (s * w / 2 if facing == "y" else 0), a0[2])
        o1 = (a1[0] + (s * w / 2 if facing != "y" else 0),
              a1[1] + (s * w / 2 if facing == "y" else 0), a1[2] + 1.0)
        p += duct_run(o0, o1, r=0.05, v=5, group=group)
    return p


@keeps_group
def handrail(w, l, z, group=STEEL, posts=6, h=1.05):
    """A perimeter handrail for an open deck or tank top. Same job as a
    parapet on the military family, at a tenth of the mass: it draws the
    outline of a horizontal surface that would otherwise dissolve into the
    roof behind it."""
    use(group)
    p = []
    for s in (-1, 1):
        p.append(cube((s * w / 2, 0, z + h), (0.06, l, 0.06)))
        p.append(cube((0, s * l / 2, z + h), (w, 0.06, 0.06)))
    for i in range(posts):
        t = -0.5 + (i + 0.5) / posts
        for s in (-1, 1):
            p.append(cube((s * w / 2, t * l, z + h / 2), (0.07, 0.07, h)))
            p.append(cube((t * w, s * l / 2, z + h / 2), (0.07, 0.07, h)))
    return p


# ═══ FORTIFICATION KIT ═════════════════════════════════════════════════════
@keeps_group
def berm(w, l, h, base=3.6, top=1.2, z=0.20, group=EARTH, open_side=None):
    """The earth ring. THE fortification badge, and the strongest family cue
    in the structure roster.

    Four mitred trapezoidal banks around a rectangle `w` x `l`, sloping from
    `base` metres wide at the ground to `top` metres at the crest, `h` tall.
    `open_side` in ("-y", "+y", "-x", "+x") omits one bank, which turns the
    ring into a revetment with a mouth.

    Why a ring and not a solid mound: from directly overhead a ring gives two
    concentric outlines at different values - olive earth outside, concrete
    core inside - and that pair is unmistakable at 48 px, where a solid mound
    is just a blurred rectangle. It is also what a real revetment is.

    The banks overlap at the corners rather than mitring exactly. That is
    deliberate: they are one material group and get joined, and a chunky corner
    is what an earth bank actually looks like.
    """
    p = []
    use(group)
    W, L = w + 2 * base, l + 2 * base
    spec = (("-y", 0, -(l + base) / 2, W, 0.0),
            ("+y", 0, (l + base) / 2, W, 0.0),
            ("-x", -(w + base) / 2, 0, L, 90.0),
            ("+x", (w + base) / 2, 0, L, 90.0))
    for side, cx, cy, run, rot in spec:
        if open_side == side:
            continue
        o = profile([(-base / 2, z), (base / 2, z),
                     (top / 2, z + h), (-top / 2, z + h)], run, "bank")
        o.rotation_euler = (0, 0, R(rot))
        o.location = (cx, cy, 0)
        p.append(o)
    return p


@keeps_group
def revetment(w, l, h, open_side="-y", **kw):
    """A berm with a mouth. Sugar for berm(open_side=...) so that model code
    reads as what it is."""
    return berm(w, l, h, open_side=open_side, **kw)


@keeps_group
def sandbags(cx, cy, z, r, h=0.95, n=14, group=EARTH, arc=360.0, a0=0.0):
    """A ring or arc of sandbag courses. Small-scale fortification texture for
    bunker and the SAM/coastal cores - it reads as a dotted olive ring, which
    is a different mark from the smooth berm and can sit inside one."""
    use(group)
    p = []
    for i in range(n):
        a = R(a0 + arc * i / float(n))
        p.append(cube((cx + math.cos(a) * r, cy + math.sin(a) * r, z + h / 2),
                      (0.85, 0.55, h), rot=(0, 0, a)))
    return p


@keeps_group
def fence(w, l, z=0.20, h=2.10, group=STEEL, gate="-y", posts=8):
    """A security fence around a compound, with one gate gap.

    For the roles whose mass does not fill their footprint - oil_derrick,
    supply_depot, fixed_radar. A fenced perimeter is what makes an open pad
    read as an INSTALLATION rather than as a patch of ground, and it draws the
    grid cell for a structure that has no walls to draw it.
    """
    use(group)
    p = []
    for i in range(posts + 1):
        t = -0.5 + i / float(posts)
        for s in (-1, 1):
            if not (gate == ("-y" if s < 0 else "+y") and abs(t) < 0.09):
                p.append(cube((t * w, s * l / 2, z + h / 2), (0.12, 0.12, h)))
            if not (gate == ("-x" if s < 0 else "+x") and abs(t) < 0.09):
                p.append(cube((s * w / 2, t * l, z + h / 2), (0.12, 0.12, h)))
    for zr in (h * 0.46, h * 0.94):
        for s in (-1, 1):
            p.append(cube((0, s * l / 2, z + zr), (w, 0.05, 0.06)))
            p.append(cube((s * w / 2, 0, z + zr), (0.05, l, 0.06)))
    return p


# ═══ INDUSTRIAL KIT ════════════════════════════════════════════════════════
@keeps_group
def tank_cyl(x, y, z, r, h, group="body", roof_ring=True):
    """A vertical storage tank. Circles in plan, which the rectangular roster
    badly needs - but see the ownership rules: a FIELD of unequal circles plus
    spheres belongs to refinery alone."""
    use(group)
    p = [cyl((x, y, z + h / 2), r, h, v=20)]
    if roof_ring:
        use(STEEL)
        p.append(cyl((x, y, z + h + 0.10), r * 1.02, 0.20, v=20))
        p.append(cyl((x, y, z + h + 0.28), r * 0.16, 0.55, v=8))
    return p


@keeps_group
def gantry(w, span_y, z, rail_h=0.5, beam=1.6, group=STEEL, legs=False):
    """An overhead travelling crane: two rails along X plus one bridge across.

    From overhead this is an H - two thin lines the length of the plan and one
    heavy bar across it. heavy_factory owns the H drawn ON a closed hall;
    naval_yard owns the same bar on LEGS beside a water basin (`legs=True`).
    Nothing else may carry a transverse bridge.
    """
    use(group)
    p = []
    for s in (-1, 1):
        p.append(cube((s * (w / 2 - 0.45), 0, z + rail_h / 2), (0.55, span_y, rail_h)))
    p.append(cube((0, span_y * 0.18, z + rail_h + beam / 2), (w, beam, beam)))
    p.append(cube((0, span_y * 0.18, z + rail_h + beam * 0.45), (2.4, beam * 1.5, 1.0)))
    if legs:
        for sx in (-1, 1):
            for sy in (-1, 1):
                p += duct_run((sx * (w / 2 - 0.45), span_y * 0.18 + sy * beam * 0.4, 0.20),
                              (sx * (w / 2 - 0.45), span_y * 0.18 + sy * beam * 0.4, z),
                              r=0.30, v=8, group=group)
    return p


@keeps_group
def container(x, y, z, rot_z=0.0, group="body", teu=1):
    """One ISO container, 6.06 x 2.44 x 2.59 m (or 12.19 m at teu=2).

    supply_depot owns the stacked GRID of these. A single one used as stowage
    elsewhere is fine; a repeating array of them is not.
    """
    L = 12.19 if teu == 2 else 6.06
    use(group)
    p = [cube((x, y, z + 2.59 / 2), (2.44, L, 2.59), rot=(0, 0, R(rot_z)))]
    use(STEEL)
    p.append(cube((x, y, z + 2.59), (2.50, L * 1.005, 0.10), rot=(0, 0, R(rot_z))))
    return p


# ═══ GROUP: sensors-defence ════════════════════════════════════════════════
# fixed_radar, fixed_sam, ew_station, bunker.
#
# These four are the ONLY structures with a mobile twin already in the roster:
# fleet_models.search_radar (a 4.2 x 3.0 m array on an 8x8 at 3.6 m),
# army_models.long_sam (four 5.2 m canisters on a 10.2 m HEMTT) and
# army_models.ew_jammer (two log-periodic booms on a 7.85 m 6x6). So the
# separation problem is TWO-WAY and it is solved the same way twice:
#
#   FIXED vs MOBILE  - every one of the four starts on an apron(), none has a
#       wheel, a track or a nose, and the sensor sits 3-8x higher than the
#       truck version can reach. The mobile search radar's array top is 5.1 m;
#       fixed_radar's is 28.0 m. The mobile jammer's booms top out at 5.3 m;
#       ew_station's masts are 20.0 m and there are sixteen of them. That is
#       not a proportion difference, it is a category difference, and it is
#       visible before the wheels are.
#
#   EACH OTHER       - by COUNT and by FAMILY. fixed_radar is MILITARY (flat
#       parapet roof) and shows ONE big solid rectangle high up; ew_station is
#       MILITARY and shows SIXTEEN small verticals in a circle; fixed_sam and
#       bunker are FORTIFICATION (earth ring, no roof) and are 20 m vs 10 m
#       across with a square-in-square plan against a hexagon-in-hexagon.
#       Nothing in this group shares a plan outline with anything else in it.


@keeps_group
def _sd_shift(parts, dx=0.0, dy=0.0, dz=0.0):
    """Translate a list of objects returned by a shared helper.

    The shared helpers all build about the origin, which is right for a mass
    that fills its cell and wrong for the two roles here that put a small
    building beside a tall tower. Object-level translation is safe: cube/cyl
    carry their geometry at the origin and their position in `location`, and
    profile()/berm() carry absolute geometry with location (0,0,0), so adding
    to `location` moves both correctly, and hero_models.build() applies
    rotation and scale ONLY - location survives into the join.
    """
    for o in parts:
        o.location = (o.location[0] + dx, o.location[1] + dy, o.location[2] + dz)
    return parts


@keeps_group
def _sd_hex(x, y, z, r, h, group=CONCRETE, taper=1.0):
    """A regular hexagonal prism. cyl(v=6) puts its VERTICES at 90, 30, -30,
    -90, -150 and 150 degrees (measured, Blender 4.5), so the six FACE normals
    lie at 0, 60, 120, 180, 240 and 300 degrees and the apothem is r*cos(30).
    Both facts are needed to land an embrasure on the middle of a face, so they
    are recorded here rather than rediscovered.

    bunker owns the hexagon. Nothing else in the roster may be six-sided.
    """
    use(group)
    return [cyl((x, y, z + h / 2), r, h, v=6, taper=taper)]


# ── fixed_radar ────────────────────────────────────────────────────────────
def fixed_radar():
    """Fixed long-range search radar. MILITARY family.

    OWNS EXCLUSIVELY: THE FLOATING ARRAY. One large solid rectangle held clear
    of the ground on an open lattice tower, OFFSET in plan from its own
    equipment shelter. From directly overhead it is a 7.6 m bar sitting beside
    a small parapeted box with the tower's shadow lying across the pad between
    them. No other structure puts a single big solid object high in the air;
    ew_station is the deliberate opposite read (sixteen small verticals in a
    ring), and oil_derrick is the only other lattice tower - it is told apart
    by having a crown block and no array.

    Real basis: AN/FPS-117 / TPS-77 fixed air-defence radar. Published antenna
    is 7.6 m wide by 4.3 m high; the class is sited on 12-30 m towers, and
    docs/12 gives this role "free range on high ground", so it takes the tall
    end. The 28.0 m array top is sim_roster's own `mount` value for the role
    and its 200 km reference range depends on it - do not change one without
    the other.

    Footprint 20.0 m cell, mass 12 x 12 (the 16 x 16 apron plus a fence out to
    15.2 - the extra cell room IS the security perimeter, which is what makes
    an open pad read as an installation).
    """
    FP, PW, PL = 20.0, 12.0, 12.0
    Z = 0.20                       # apron top; everything stands on it
    MOUNT = 28.0                   # sim_roster fixed_radar.mount
    p = apron(PW, PL)                                   # 16 x 16 slab + kerb
    p += fence(15.2, 15.2, z=Z, gate="-y", posts=9)

    # equipment shelter: 7 x 5 x 4.0 m, pushed to the -Y half so the tower and
    # the array are not stacked on the same square of ground in plan.
    SY, SW, SL, SH = -3.20, 7.0, 5.0, 4.00
    ROOF = Z + SH                                        # 4.20 wall head
    p += _sd_shift(box_building(SW, SL, SH, z=Z), 0, SY)
    p += _sd_shift(parapet_roof(SW, SL, ROOF), 0, SY)    # deck 4.50, rail 5.35
    DECK = ROOF + 0.30
    p += _sd_shift(vent_kit(SW, SL, DECK, n=2), 0, SY)
    p += _sd_shift(team_mark(SW, SL, DECK), 0, SY)       # MANDATORY
    p += door(0, SY - SL / 2, Z, 1.80, 2.40, facing="y")
    p += stair(SW / 2 + 1.10, SY, Z, DECK, run=3.60, facing="y")

    # the tower, on the +Y half. 7 bays over 23.12 m is a 3.3 m bay, which is
    # the ratio a real guyed-free self-supporting mast is built at.
    TY, TH = 3.20, 23.12
    p += lattice_tower(0, TY, Z, TH, 5.60, 2.60, bays=7)
    use(CONCRETE)
    for sx in (-1, 1):                                   # pad footings
        for sy in (-1, 1):
            p.append(cube((sx * 2.80, TY + sy * 2.80, Z + 0.25), (1.20, 1.20, 0.50)))
    TOP = Z + TH                                         # 23.32
    p.append(cube((0, TY, TOP + 0.14), (3.60, 3.60, 0.28)))   # maintenance deck
    p += handrail(3.60, 3.60, TOP + 0.28)
    use(STEEL)
    p.append(cyl((0, TY, TOP + 0.28 + 0.45), 0.80, 0.90, v=14))   # pedestal

    # THE ARRAY. 7.6 x 4.3 m face, 0.62 m deep, raked back 15 deg so the face
    # looks -Y and slightly up - the same side the RTS camera is on, so the
    # player sees the face and not the edge. Top lands exactly on MOUNT:
    #   half-height in z = (4.30/2)cos15 + (0.62/2)sin15 = 2.0768 + 0.0802
    #
    # THE ARRAY IS CAMO, NOT CONCRETE, AND THIS WAS A RENDER FIX. Built first in
    # deck concrete it measured 0.098 against a deck-concrete apron at 0.098 -
    # 1.0:1, and the top-down sheet came back as one undifferentiated dark grey
    # field with no "one big solid thing" in it at all. Camo at 0.588 is 6.0:1
    # against the same apron and against the tower's own shadow, which is the
    # rule this module's header states: a steel or concrete object on a concrete
    # ground plane has to be seen against camo, against sky, or against shadow.
    # It is also what an FPS-117 antenna actually is - a pale radome face.
    # RAKE 28 deg is chosen off the 48 px sheet, not off a photograph: the plan
    # depth of the array is AH sin(rake) + AT cos(rake), which is 2.05 m at 20
    # deg and 2.57 m at 28 deg - a 25% larger bright mark for nothing, and 28
    # is still inside the 20-30 deg the FPS-117 class is actually tilted at.
    AW, AH, AT, RAKE = 7.60, 4.30, 0.62, 28.0
    half = (AH / 2) * math.cos(R(RAKE)) + (AT / 2) * math.sin(R(RAKE))
    ACZ = MOUNT - half
    use("body")
    p.append(cube((0, TY, ACZ), (AW, AT, AH), rot=(R(-RAKE), 0, 0)))
    # Recessed slots across the face. STEEL on CONCRETE measures 0.116 vs 0.098
    # = 1.18:1 and is invisible at gameplay zoom, so the face is articulated
    # with VOID instead: 0.012 vs 0.098 is 8:1 and survives to 48 px.
    use(VOID)
    for k in range(4):
        d = (k - 1.5) * 0.98
        p.append(cube((0, TY - math.sin(R(RAKE)) * d - math.cos(R(RAKE)) * (AT / 2 - 0.06),
                       ACZ + math.cos(R(RAKE)) * d - math.sin(R(RAKE)) * (AT / 2 - 0.06)),
                      (AW - 0.80, 0.16, 0.42), rot=(R(-RAKE), 0, 0)))
    # waveguide from the shelter to the tower foot - both ends land on geometry
    p += duct_run((0, SY + SL / 2, Z + 0.95), (0, TY - 2.80, Z + 0.95), r=0.26)
    return p, struct_meta(PW, PL, DECK, mount_z=MOUNT, door_y=SY - SL / 2)


# ── fixed_sam ──────────────────────────────────────────────────────────────
def fixed_sam():
    """Fixed surface-to-air missile site. FORTIFICATION family.

    OWNS EXCLUSIVELY: FOUR PARALLEL ELEVATED CANISTERS IN A SQUARE EARTH
    REVETMENT. Four bright tube mouths in a row, sitting inside a closed olive
    ring. The ring is closed rather than open on purpose - docs/12 says this
    site "cannot relocate", and a revetment with no vehicle mouth says so; the
    only way in is the stair over the -Y bank.

    Told apart from army_models.long_sam, which fires the same four 5.2 m
    canisters, by everything around them: no cab, no 8x8, no nose, a 16 m earth
    ring instead of a 10.2 m hull, and the canisters at 72 deg standing on a
    concrete magazine rather than at 38 deg lying over a tail.

    Real basis: Patriot M901 launching station - canister 5.2 m long, ~0.86 m
    square, four rounds - re-mounted in a hardened square revetment of the kind
    built for fixed Nike and Patriot sites. Elevation is 60.0 deg, solved so
    the upper muzzle CORNER - not the axis tip - lands on sim_roster's mount:
        4.2817 + 5.2 sin(60) + (0.86/2) cos(60) = 4.2817 + 4.5033 + 0.2150 = 9.00
    The first build used 72 deg and the 48 px sheet killed it: the canisters
    foreshortened to 5.2 cos(72) = 1.61 m and the four of them covered 5.5 m2 of
    a 400 m2 cell, so the role's own identity element was three pixels. At 60
    deg they are 2.60 m deep and cover 11.6 m2, and the magazine roof rises to
    4.03 - 0.63 m PROUD of the 3.40 m berm crest - so the fortification family's
    two concentric outlines both show. 60 deg is a real inclined-launcher
    figure and it is nothing like the 38 deg army_models.long_sam fires the
    same canister at, which is the separation that actually matters.

    Footprint 20.0 m cell, mass 16 x 16. The berm arithmetic is forced:
    berm(base=3.6) grows 3.6 m per side, so the core is 16 - 2 x 3.6 = 8.8.
    """
    FP, PW, PL = 20.0, 16.0, 16.0
    Z = 0.20
    MOUNT = 9.0                    # sim_roster fixed_sam.mount
    CORE = 8.80                    # 8.8 + 2 x 3.6 = 16.0 exactly
    p = apron(PW, PL)                                    # 20 x 20 slab + kerb

    # THE RING. 3.2 m of earth all the way round, crest at 3.40.
    BH = 3.20
    p += berm(CORE, CORE, BH, base=3.6, top=1.2, z=Z)
    p += box_building(CORE, CORE, 0.50, z=Z, group=CONCRETE)     # core hardstand
    HARD = Z + 0.50                                      # 0.70

    # the magazine block the launcher stands on - this is what lifts the
    # canisters over the crest so the mouths clear their own revetment.
    # MH is solved backwards from MOUNT: putting the upper muzzle corner on
    # 9.00 at 60 deg fixes the trunnion at 4.2817 and the magazine roof at 4.03.
    MW, ML, MH = 7.60, 5.60, 3.33
    p += box_building(MW, ML, MH, z=HARD, group=CONCRETE)
    MROOF = HARD + MH                                    # 3.80
    p += team_mark(MW, ML, MROOF)                        # MANDATORY, on the core
    use(STEEL)
    p.append(cube((0, -1.20, MROOF + 0.25), (5.40, 1.00, 0.50)))   # trunnion beam
    Z0, Y0, ELEV, CLEN, CS = MROOF + 0.25, -1.40, 60.0, 5.20, 0.86
    e = R(ELEV)
    ax = (0.0, math.cos(e), math.sin(e))
    for c in (-1.5, -0.5, 0.5, 1.5):
        cx = c * 1.20
        # Canisters are CAMO, not concrete, and the reason is measured: against
        # era earth at 0.219, body camo 0.588 is 2.7:1 and reads, while deck
        # concrete 0.098 is 0.45:1 - the canisters would come out DARKER than
        # their own berm and disappear into it. The mouths are VOID: 0.012
        # against 0.588 is 49:1, the largest contrast in the palette.
        use("body")
        p.append(cube((cx, Y0 + ax[1] * CLEN / 2, Z0 + ax[2] * CLEN / 2),
                      (CS, CLEN, CS), rot=(R(ELEV), 0, 0)))
        # cap recessed 0.30 m down the bore, so the muzzle CORNER is the
        # model's highest point and lands on MOUNT exactly
        use(VOID)
        p.append(cube((cx, Y0 + ax[1] * (CLEN - 0.30), Z0 + ax[2] * (CLEN - 0.30)),
                      (CS * 0.78, 0.14, CS * 0.78), rot=(R(ELEV), 0, 0)))
    use(STEEL)                                           # elevation frame
    p.append(cube((0, Y0 + ax[1] * 1.10, Z0 + ax[2] * 1.10),
                  (5.10, 1.00, 0.30), rot=(R(ELEV), 0, 0)))
    p.append(cube((0, Y0 + ax[1] * CLEN * 0.72, Z0 + ax[2] * CLEN * 0.72),
                  (5.10, 0.26, 0.26), rot=(R(ELEV), 0, 0)))
    for s in (-1, 1):                                    # back struts to the roof
        p += duct_run((s * 2.55, Y0 + 1.90, MROOF), (s * 2.55, Y0 + 0.30, Z0 + 0.30),
                      r=0.16, v=6)

    # the site's own illuminator (sim_roster gives this role sensor "illuminator").
    # Kept small and low - a 2.2 m tilted disc at 5.4 m. fixed_radar owns the
    # BIG rectangle high up; one small dish does not compete with it.
    use(STEEL)
    p.append(cyl((2.40, 1.90, MROOF + 0.55), 0.34, 1.10, v=10))
    p.append(cyl((2.40, 1.90, MROOF + 1.35), 1.10, 0.26, rot=(R(-35), 0, 0), v=16))
    use(CONCRETE)
    p.append(cube((-2.60, 1.90, MROOF + 0.70), (1.80, 1.60, 1.40)))   # power/coolant

    p += stair(3.00, -2.60, HARD, MROOF, run=3.00, facing="y")   # core to magazine
    p += stair(-4.00, -6.20, Z, Z + BH, run=3.40, facing="y")    # over the bank
    return p, struct_meta(PW, PL, MROOF, mount_z=MOUNT, door_y=-2.80)


# ── ew_station ─────────────────────────────────────────────────────────────
def ew_station():
    """Electronic-warfare / ESM station. MILITARY family.

    OWNS EXCLUSIVELY: THE ANTENNA RING. Sixteen thin masts standing on a 20 m
    circle around a small parapeted hut, reading from directly overhead as a
    DOTTED CIRCLE. This is the exact opposite read to fixed_radar's single big
    solid array, which is how the two sensor buildings are kept apart: COUNT,
    not size. It is also nothing like army_models.ew_jammer, which is two
    fishbone booms on a 7.85 m truck.

    Real basis: AN/FLR-9 "Elephant Cage" circularly-disposed antenna array. The
    real thing is 260 m across, which is a map feature and not a building, so
    it is DECLARED AS SCALED: the 24 m grid cell is 260/11 = 23.6 m and the
    20 m mast circle is 260/13. Everything about the shape is kept - a ring of
    equal vertical elements around a central operations building - and only the
    diameter is a lie.

    Mast tops land on sim_roster's mount of 20.0 m exactly:
        0.20 apron + 19.35 shaft + 0.45 crossarm head = 20.00

    Sixteen 0.20 m masts are 0.40 m wide and a 24 m cell is about 48 px in the
    audit sheet, so a mast shaft alone is under half a pixel. Two things make
    the ring read anyway and both are deliberate: the masts are painted CAMO
    (0.588) rather than left steel (0.116), which is 6:1 against the concrete
    apron instead of 1.18:1 and invisible; and every mast foot gets a 2.2 m
    ASPHALT pad, 0.048 against 0.098, so the ring is sixteen dark blobs on a
    pale field even where the mast itself is sub-pixel.

    Footprint 24.0 m cell, mass 20 x 20.
    """
    FP, PW, PL = 24.0, 20.0, 20.0
    Z = 0.20
    MOUNT = 20.0                   # sim_roster ew_station.mount
    RING, N = 10.0, 16             # 20 m circle, sixteen elements
    p = apron(PW, PL)                                    # 24 x 24 slab + kerb

    # central operations hut, 8 x 8 x 4.0 - small on purpose. The ring is the
    # identity; a big hut would turn this into another flat-roofed box.
    HW_, HL_, HH_ = 8.0, 8.0, 4.00
    p += box_building(HW_, HL_, HH_, z=Z)
    ROOF = Z + HH_                                       # 4.20
    p += parapet_roof(HW_, HL_, ROOF)
    DECK = ROOF + 0.30                                   # 4.50
    p += vent_kit(HW_, HL_, DECK, n=2)
    p += door(0, -HL_ / 2, Z, 1.80, 2.40, facing="y")
    p += stair(HW_ / 2 + 1.90, 0, Z, DECK, run=4.20, facing="x")

    # THE RING.
    SHAFT, HEADT = 19.50, 0.45     # 0.05 base + 19.50 + 0.45 head = 20.00
    pads = []
    for i in range(N):
        a = R(i * 360.0 / N)
        mx, my = math.cos(a) * RING, math.sin(a) * RING
        pads.append((mx, my, 2.20, 2.20))
        p += mast(mx, my, Z - 0.15, SHAFT, r=0.20, group="body",
                  stays=False, head=(0.95, 0.95, HEADT))
    p += markings(Z, tuple(pads), group=ASPHALT, t=0.06)
    # feeder ring at chest height, tying the sixteen masts into one object so
    # the ring reads as a structure rather than sixteen unrelated poles
    use(STEEL)
    for i in range(N):
        a0, a1 = R(i * 360.0 / N), R((i + 1) * 360.0 / N)
        p += duct_run((math.cos(a0) * RING, math.sin(a0) * RING, Z + 2.30),
                      (math.cos(a1) * RING, math.sin(a1) * RING, Z + 2.30),
                      r=0.09, v=5)
    # four feeders from the hut out to the ring - both ends on real geometry
    for k in range(4):
        a = R(45 + k * 90)
        p += duct_run((math.cos(a) * 4.4, math.sin(a) * 4.4, Z + 0.85),
                      (math.cos(a) * (RING - 0.2), math.sin(a) * (RING - 0.2), Z + 0.85),
                      r=0.16, v=6)
    # MANDATORY team band. It goes on the apron rather than the 8 m hut roof
    # because the apron is by far the largest horizontal surface here, and the
    # band lands on the -Y chord INSIDE the ring where nothing occludes it.
    p += team_mark(PW, PL, Z)
    return p, struct_meta(PW, PL, DECK, mount_z=MOUNT, door_y=-HL_ / 2)


# ── bunker ─────────────────────────────────────────────────────────────────
def bunker():
    """Reinforced-concrete pillbox. FORTIFICATION family.

    OWNS EXCLUSIVELY: THE HEXAGON. A six-sided chamber with a black embrasure
    on every one of its six faces, half-buried in a hexagonal earth glacis and
    collared by a sandbag ring. It is the only hexagonal plan in the roster,
    and the hexagon is doubled - olive earth hex at 6.0 m across corners around
    a concrete hex at 5.2 - so the fortification family's ring cue is carried by
    the plan even though the whole thing is only 3 m tall.

    docs/12 asks for "very high effective armor" and the geometry says it: no
    wall is exposed for more than its top metre, the earth runs up to within
    1.0 m of the crown, and the roof slab oversails the chamber by 0.25 m all
    round - the overhang shadow is what tells the player the roof is thick.

    Real basis: Atlantic-Wall / Maginot-class hexagonal MG pillbox, 5-6 m across
    the chamber with 1.5-2.0 m walls. Crown at 3.0 m is sim_roster's own mount
    figure and footprint 10.0 m is sim_roster's own footprint - both binding.
    The 6 m mass leaves exactly APRON_MARGIN on each side: 6.0 + 2 x 2.0 = 10.0.

    The dotted sandbag collar is not the same mark as ew_station's dotted mast
    ring and cannot be confused with it: these are 0.85 m bags on a 6.7 m circle
    inside a 10 m cell, and the entire bunker is smaller than ew_station's hut.
    """
    FP, PW, PL = 10.0, 6.0, 6.0
    Z = 0.20
    MOUNT = 3.0                    # sim_roster bunker.mount, and the crown
    RC, AP = 3.00, 3.00 * math.cos(R(30))       # 6.0 m across corners, apothem 2.598
    p = apron(PW, PL)                                    # 10 x 10 slab + kerb

    # THE EARTH GOES IN THE MARGIN. First build put a 3.00 m glacis around a
    # 2.85 m cap and the top-down sheet showed a 0.15 m sliver of olive - the
    # fortification family's ring cue was simply absent. docs/12's wording is
    # literal: "a 6 m hexagonal chamber inside a 2 m earth apron", so the earth
    # IS the 2 m apron margin. Glacis 4.55 m base against a 3.25 m cap leaves a
    # 1.30 m olive ring in plan, plus the sandbag collar outside that, and the
    # concrete corners of the 10 m slab still show past both.
    p += _sd_hex(0, 0, Z, 4.55, 1.50, group=EARTH, taper=0.68)
    # the chamber
    p += _sd_hex(0, 0, Z, RC, 2.40, group=CONCRETE)      # 0.20 -> 2.60
    # oversailing roof slab. 0.30 thick, 0.25 proud, top at MOUNT - 0.10 so the
    # team band's 0.10 m of paint finishes exactly on the roster's 3.0 m crown.
    p += _sd_hex(0, 0, 2.60, RC + 0.25, 0.30, group=CONCRETE)    # cap r 3.25
    CROWN = 2.90
    p += team_mark(3.00, 4.20, CROWN)                    # MANDATORY
    use(STEEL)
    p.append(cyl((1.10, 1.20, CROWN + 0.00), 0.11, 0.20, v=8))    # periscope head
    p.append(cube((-1.20, 1.30, CROWN + 0.04), (0.60, 0.60, 0.09)))  # hatch

    # ONE EMBRASURE PER FACE. Faces sit at 0, 60, 120, 180, 240, 300 deg (see
    # _sd_hex), so each slot is placed on the apothem and yawed to match.
    # VOID on CONCRETE is 0.012 vs 0.098 = 8:1, which is the contrast that
    # makes six black slots read as a pillbox and not as a concrete lump.
    use(VOID)
    for k in range(6):
        a = R(k * 60.0)
        p.append(cube((math.cos(a) * (AP + 0.10), math.sin(a) * (AP + 0.10), 2.02),
                      (0.36, 1.70, 0.52), rot=(0, 0, a)))
    # entry throat, cut into the +Y corner behind the earth
    use(VOID)
    p.append(cube((0, 2.70, Z + 0.95), (1.10, 0.90, 1.90)))
    use(EARTH)
    for s in (-1, 1):                                    # blast walls either side
        p.append(cube((s * 1.25, 3.55, Z + 0.55), (0.70, 2.20, 1.10)))

    # sandbag collar, sitting against the foot of the glacis so it is a
    # continuous olive ring rather than twenty-two detached islands: bags reach
    # in to 4.55 - 0.425 = 4.125 and the glacis base is 4.55, so they touch.
    # The radius is capped by the CELL, measured: at r 4.70 the model exported
    # 10.25 m across and overhung its own 10 m grid square, which is the one
    # error a placement grid cannot absorb. 4.55 + 0.425 = 4.975.
    p += sandbags(0, 0, Z, 4.55, h=0.85, n=22)
    return p, struct_meta(PW, PL, CROWN, mount_z=MOUNT, door_y=2.70)



# ═══ NAVAL-COASTAL GROUP ═══════════════════════════════════════════════════
# naval_yard + coastal_battery. Both sit at the WATERLINE, which is a placement
# constraint no other structure has, so both are written against the one
# convention navy_models.py already fixed:
#
#     navy_models.ship_hull() puts the WATERLINE AT z = 0 and omits everything
#     below it.  A yard and a ship therefore only agree about where the sea is
#     if the yard's water surface is also at z = 0.
#
# That is why naval_yard does NOT call apron() once over its whole cell. The
# apron top is at z = 0.20, and a basin whose water sits ON the apron would put
# the sea 0.20 m too high and give the quay no face at all. The basin has to be
# a real hole in the slab, so the apron is composed from three apron() calls -
# see _slab() - and the water is a 0.06 m VOID sheet lying on the terrain in the
# gap. Measured mismatch against navy_models: 0.06 m, which is 1.2 % of the
# 5.2 m freeboard of the corvette that berths in it. It cannot be zero: nothing
# may sit below z = 0 (validate_sockets fails at -0.02) and a sheet thinner than
# 0.06 m is degenerate under the LOD0 bevel (width 0.024, 3 segments).
#
# BOTH ROLES FACE +Y. The sea is +Y for the whole group: the dock mouth opens
# to +Y and the embrasure looks out to +Y. That leaves the -Y (landward) edge
# free for team_mark(), which is where team_mark() puts the band anyway.


@keeps_group
def _move(objs, dx=0.0, dy=0.0, dz=0.0):
    """Translate a helper's return value. The origin-centred helpers (apron,
    box_building, gantry, vent_kit, team_mark) can only be placed this way, and
    build() applies rotation and scale but NOT location, so the offset survives
    the join."""
    for o in objs:
        o.location.x += dx
        o.location.y += dy
        o.location.z += dz
    return objs


@keeps_group
def _slab(cx, cy, w, l):
    """One panel of a non-rectangular apron: apron() with the collar and kerb
    switched off, moved into place. Three of these make the naval yard's
    U-shaped slab, which is the only way to leave a genuine hole for the
    basin - there are no booleans in this pipeline."""
    return _move(apron(w, l, margin=0.0, kerb=False), cx, cy)


def naval_yard():
    """OWNS: THE WATER NOTCH. A 10 x 24 m basin cut INTO the plan from the
    seaward edge with dark water in it, straddled by a PORTAL crane on legs.
    The only negative volume and the only U-shaped plan in the roster. Nothing
    else may cut a hole in its own apron, and gantry(legs=True) is this role's
    alone (heavy_factory gets the same bar with legs=False, on a closed roof).

    Basis - a small BUILDING DOCK, the smallest yard that can lay down a hull:
        cell            36.0 m          ROSTER (sim_roster.gd "footprint": 36.0)
        mass            32 x 32 m       apron margin 2.0 m per side
        basin           10 x 26 m       x = +-5, y = -8 .. +18 (open at +Y)
                                        24 m of it inside the mass, 2 m through
                                        the collar, because water that stops
                                        short of the cell edge is a pond
        water surface   z = +0.06       navy_models waterline is z = 0
        quay face       0.20 m slab + 0.35 m coping = 0.55 m above the water
        crane gauge     16.0 m          rails at x = +-8.0, 3.0 m off the coping
        under the beam  14.0 m          bridge soffit; 2.0 m box girder over a
                                        16.9 m span is span/8.5, a real ratio
        beam top        16.0 m          = sim_roster.gd "mount": 16.0 EXACTLY
        crane legs      13.3 m x 0.6 m  four of them: the industrial family's
                                        mandatory TALL THIN VERTICAL
        sheds           7.6 x 18 x 9.0 m, mirrored at x = +-13.2

    ROOF GRAMMAR (industrial: broken and repeating, never plain, never a
    parapet). The two sheds carry 8 transverse steel ribs each at 2.25 m pitch
    plus a spine duct. Ribs are STEEL on BODY camo - 0.116 against 0.588, a 5:1
    step. They are deliberately NOT sawtooth north-lights: light_factory owns
    the glazed sawtooth and this file's ownership rules are not negotiable.

    SYMMETRY. Mirror-symmetric about X = 0, so the plan points nowhere; the
    only thing that faces anywhere is the black basin mouth, which is exactly
    the exception rule (b) allows - a dark OPENING, never a taper.
    """
    W, L = 32.0, 32.0                  # mass; apron collar takes it to 36 x 36
    BW, BY0, BY1 = 10.0, -8.0, 18.0    # basin: 10 m wide, y -8 .. +18
    QX = BW / 2.0                      # basin edge / quay face at x = +-5
    SHED_W, SHED_L, SHED_H = 7.6, 18.0, 9.0
    SHED_X, SHED_Y = 13.2, 4.0
    RAIL_X = 8.0                       # 16 m gauge
    Z = 0.20                           # apron top

    p = []
    # ── the U-shaped apron. Outer extent is exactly 36 x 36. ──────────────
    p += _slab(0.0, -13.0, 36.0, 10.0)          # south block   y -18 .. -8
    p += _slab(-11.5, 5.0, 13.0, 26.0)          # west quay     x -18 .. -5
    p += _slab(11.5, 5.0, 13.0, 26.0)           # east quay     x  +5 .. +18
    # The kerb apron() would have drawn, rebuilt to follow the U. It is not
    # decoration: from directly overhead a slab and the terrain are both flat
    # and the AO bake has nothing to bite on, so a 0.12 m upstand is what puts
    # a hard line on the grid cell the player just paid for. The +Y run is
    # deliberately BROKEN over the basin mouth - a kerb across the dock
    # entrance would be a sill, and a sill would say the water stops there.
    use(CONCRETE)
    p.append(cube((0, -17.82, Z + 0.06), (36.0, 0.36, 0.12)))      # south, once
    for s in (-1, 1):
        p.append(cube((s * 17.82, 0.0, Z + 0.06), (0.36, 36.0, 0.12)))
        p.append(cube((s * 11.5, 17.82, Z + 0.06), (13.0, 0.36, 0.12)))

    # ── the water. 10 x 26 m of VOID lying on the terrain, top at z = 0.06.
    # 13 px of near-black across a 48 px structure: this is the whole read.
    use(VOID)
    p.append(cube((0, (BY0 + BY1) / 2, 0.03), (BW, BY1 - BY0, 0.06)))

    # ── quay coping and furniture. 0.35 m upstand: at the game's 52 deg
    # camera it drops a 0.27 m shadow onto the water, sharpening a line that
    # is already 8:1 (concrete 0.098 against void 0.012).
    use(CONCRETE)
    for s in (-1, 1):
        p.append(cube((s * (QX + 0.30), 5.0, Z + 0.175), (0.60, 26.0, 0.35)))
    p.append(cube((0, -8.30, Z + 0.175), (11.2, 0.60, 0.35)))       # dock head
    use(STEEL)
    for s in (-1, 1):
        p.append(cube((s * RAIL_X, 5.0, Z + 0.06), (0.50, 26.0, 0.12)))  # runway
        for k in range(5):                                               # bollards
            p.append(cyl((s * (QX + 0.9), -5.0 + k * 5.5, Z + 0.38), 0.30, 0.76, v=10))

    # ── the portal crane. gantry(legs=True) is naval_yard's exclusively. ──
    p += _move(gantry(2 * RAIL_X + 0.9, 26.0, 13.5, rail_h=0.5, beam=2.0,
                      legs=True), 0.0, 5.0)

    # ── two mirrored fitting-out sheds ───────────────────────────────────
    for s in (-1, 1):
        cx = s * SHED_X
        p += _move(box_building(SHED_W, SHED_L, SHED_H, z=Z), cx, SHED_Y)
        # THE SHED ROOF IS THE PART THAT HAD TO BE REDESIGNED TWICE, and both
        # failures were the same failure: a REGULAR TRANSVERSE PITCH under 2.5 m
        # reads as a STACK OF MATERIAL, not as a building. Cut 1 was 8 ribs of
        # 0.34 x 0.28 m overhanging the eaves at 2.25 m pitch and the sheds
        # came back looking like piles of timber. Cut 2 thinned them to
        # 0.22 x 0.16 m at 1.8 m pitch and it got WORSE - finer pitch is more
        # like stacked plate, not less. That is supply_depot's exclusive
        # element (a repeating array of separate objects) and the yard is not
        # allowed to borrow it.
        #
        # Cut 3 changes the GRAMMAR instead of the dimensions. Four trusses at
        # 4.5 m centres is a structural bay spacing, not a stacking pitch: at
        # 0.75 m/px that is 6 px apart, far too coarse to read as courses of
        # anything, and it is the real bay of a portal-framed shed. The
        # longitudinal monitor over the spine then breaks the transverse
        # rhythm outright, so the roof can no longer be read as a stack in any
        # direction - and a raised glazed monitor is what a fitting-out shed
        # actually has, because the work underneath needs top light.
        use(STEEL)
        for i in range(4):                       # 4 bays at 4.5 m
            y = SHED_Y + (i + 0.5 - 2) * (SHED_L / 4.0)
            p.append(cube((cx, y, Z + SHED_H + 0.17), (SHED_W + 0.4, 0.30, 0.34)))
        use("body")                              # the monitor, 2.2 x 15 x 1.4
        p.append(cube((cx, SHED_Y, Z + SHED_H + 0.70), (2.20, 15.00, 1.40)))
        use("glass")                             # clerestory, one strip a side
        for gs in (-1, 1):
            p.append(cube((cx + gs * 1.08, SHED_Y, Z + SHED_H + 0.72),
                          (0.14, 14.40, 0.90)))
        # services duct, moved off the spine now that the monitor is there
        p += duct_run((cx + s * 2.60, SHED_Y - 8.4, Z + SHED_H + 0.45),
                      (cx + s * 2.60, SHED_Y + 8.4, Z + SHED_H + 0.45), r=0.34)
        p += _move(vent_kit(SHED_W, SHED_L, Z + SHED_H, n=2, duct=False),
                   cx, SHED_Y)
        # human scale: a 9 m shed needs a stair. A single straight flight to
        # the eaves would be 14 m long and would fill the quay, so this one
        # climbs to the 4.7 m mezzanine door, which carries the same cue.
        p += stair(cx - s * 3.0, SHED_Y - 12.0, Z, 4.70, w=1.20, facing="y")
        use(STEEL)
        p.append(cube((cx - s * 3.0, SHED_Y - 9.6, 4.70), (2.60, 1.60, 0.18)))
        p += door(cx - s * 3.0, SHED_Y - 9.05, 4.80, 1.60, 2.10, depth=0.50)
        p += door(cx + s * 0.8, SHED_Y - 9.05, Z, 3.60, 5.00, depth=0.50)
        # quayside floodlight - height cue, kept well under the crane
        p += mast(s * 6.6, -6.0, Z, 11.0, r=0.14, stays=False, head=(1.2, 0.5, 0.35))
        # NOTE: an earlier pass put camo plate stacks on the south hardstand.
        # They rendered as ISO boxes, which is supply_depot's alone. Deleted.

    # ── ownership: the band goes on the apron, the largest horizontal
    # surface by a wide margin (1024 m2 of slab against 137 m2 of shed roof),
    # on the landward south block where nothing else competes.
    p += team_mark(30.0, 34.0, Z)

    use("body")
    return p, struct_meta(W, L, 9.20, mount_z=16.00, door_y=16.0)


def coastal_battery():
    """OWNS: THE ROUND CASEMATE. A concrete drum half-sunk in earth with one
    radial embrasure slot facing seaward. The ONLY circular building outline in
    the roster - every other role is a rectangle, a cruciform or a hexagon. It
    has NO TURRET AND NO BARREL: rule (b) is absolute, and the direction is
    carried entirely by the black slot, which is cut down THROUGH the roof so
    that it is still there when you are looking straight down.

    Basis - a casemated coastal emplacement of the Atlantic-Wall class
    (Regelbau 671 / M272 family: a circular gun casemate with a 10-14 m
    external drum under 2-3.5 m of concrete, sunk into a graded earth mass):
        cell            22.0 m          art contract; sim_roster.gd still has
                                        this role on its 12.0 m default and
                                        should be corrected to 22.0
        mass            18 x 18 m       berm outer; apron margin 2.0 m per side
        berm            core 12.8, base 2.6 -> 12.8 + 2*2.6 = 18.0  ARITHMETIC
                                        RULE: core = plan_w - 2*base
        drum             9.6 m dia, z 0.20 .. 4.20  (r = 4.8)
        roof slab       11.2 m dia, z 4.20 .. 4.80  (r = 5.6)
        glacis          r 9.05 -> 5.10 cone, z 0.20 .. 2.60
        sunk fraction   2.60 / 4.80 = 54 %   - "half-sunk", measured
        embrasure       4.8 m wide slot, sill 1.40 m, cut out through the roof
        director top    8.00 m          = sim_roster.gd "mount": 8.0 EXACTLY

    THE DRUM DIAMETER IS A MEASURED CORRECTION, not the 12.0 m the footprint
    note started from. At 12 m the roof slab came out 13.2 m across against a
    berm whose inner opening is only 12.8 m: the concrete jammed against the
    earth, and rendered at 48 px (0.46 m/px for a 22 m cell) there was a 2.4 m
    olive fringe left - about 5 px - so the circle had nothing to be a circle
    against and the structure read as an olive frame with a dark blob in it.
    At 9.6 m the roof is 11.2 m, the fringe is 3.4 m on the axes and 8.1 m on
    the diagonals, and the ring/core pair is the read it is supposed to be.
    9.6 m is inside the real Regelbau band, so nothing is given up for it.

    ROOF GRAMMAR (fortification: no roof and no walls, the profile is earth).
    berm() gives the square outer plan and the crest ring; the glacis cone
    fills the whole inside of it and banks up against the drum. Both are group
    EARTH, so they join into one mass and the result is the read the family is
    built on - an outer plan that is SQUARE and an inner one that is ROUND,
    with a small hard core in the middle. Nothing else in the roster has an
    outline that changes shape between the ground and the top.

    VALUE. earth 0.219 over concrete 0.098 is only 2.2:1, so the drum is not
    allowed to carry the identity by brightness alone. It carries it by the
    0.8 m roof overhang (a 0.63 m shadow ring at the 52 deg camera), by the
    team band (12.1 % of the 98.5 m2 roof, arithmetic below), and by the void
    slot at 8:1 against concrete.
    """
    W, L = 18.0, 18.0
    BASE, BERM_TOP, BERM_H = 2.6, 2.0, 3.00
    CORE = W - 2 * BASE                          # 12.8 -> berm outer is 18.0
    R_DRUM, R_ROOF, R_GLAC = 4.8, 5.6, 9.05
    Z = 0.20
    DRUM_TOP, ROOF_TOP, GLAC_TOP = 4.20, 4.80, 2.60
    MOUNT = 8.00

    p = apron(W, L)                              # 22 x 22, top at z = 0.20

    # ── the earth. berm() is the family badge and gives the square outer
    # plan; the cone fills it to a circle and buries the lower drum. The cone
    # base is CORE/2 * sqrt(2) = 9.05 so that it also covers the four corners
    # of the berm's inner opening - at the smaller radius those corners came
    # back as four bright specks of bare apron inside the earth field.
    p += berm(CORE, CORE, BERM_H, base=BASE, top=BERM_TOP, z=Z)
    use(EARTH)
    p.append(cyl((0, 0, (Z + GLAC_TOP) / 2), R_GLAC, GLAC_TOP - Z,
                 v=28, taper=5.10 / R_GLAC))

    # ── the casemate ─────────────────────────────────────────────────────
    use(CONCRETE)
    p.append(cyl((0, 0, (Z + DRUM_TOP) / 2), R_DRUM, DRUM_TOP - Z, v=28))
    p.append(cyl((0, 0, (DRUM_TOP + ROOF_TOP) / 2), R_ROOF, ROOF_TOP - DRUM_TOP,
                 v=28))
    p.append(cyl((2.40, -0.60, ROOF_TOP + 0.35), 0.85, 0.70, v=12))   # crew hatch

    # ── the embrasure. Two VOIDs, because a slot that exists only on the
    # vertical face is invisible from an overhead camera and this is the only
    # thing that tells the player which way the battery looks.
    #   (i)  the slot proper, taken up through the roof and 0.06 m proud of it
    #        so it does not z-fight the deck it is notching. 4.6 m wide biting
    #        3.6 m into an 11.2 m circle: a big enough bite to survive 48 px.
    #   (ii) the cleared cut through the glacis and the +Y berm bank - the
    #        field of fire. 5.2 m of an 18 m bank, so the ring stays a ring.
    use(VOID)
    p.append(cube((0, 3.90, (1.40 + 4.86) / 2), (4.80, 5.00, 4.86 - 1.40)))
    p.append(cube((0, 7.30, (Z + 2.90) / 2), (5.20, 4.60, 2.90 - Z)))

    # ── fire direction. NOT a turret: a 1.8 x 1.0 x 0.4 m director box on a
    # 0.32 m column. Top lands at exactly 8.00 m, the roster's mount height,
    # which is what the sim uses for the anti-ship radar horizon.
    p += mast(0, -1.20, ROOF_TOP, MOUNT - ROOF_TOP - 0.40, r=0.16,
              stays=False, head=(1.80, 1.00, 0.40))

    # ── sandbag revetting. THIS IS WHAT MAKES THE CIRCLE A CIRCLE. Rendered
    # in the 19-role sheet at 48 px the first cut sat next to fixed_sam and the
    # two were hard to tell apart: both are an olive square ring with a core in
    # the middle, because that ring is the FAMILY badge and is supposed to be
    # shared. What separates the roles is the core, and a dark disc on a dark
    # apron seen through a light ring did not announce itself as round -
    # concrete 0.098 against earth 0.219 is 2.2:1 and the outline went soft.
    # Two 100 deg arcs of bags at r = 4.75 draw the circle explicitly, in olive
    # on concrete, as 14 discrete marks that survive the LOD2 decimate. The two
    # gaps are not decoration either: the arcs stop clear of the embrasure
    # (which subtends atan(2.4 / 5.6) = 23.2 deg either side of +Y, so it
    # occupies 66.8 - 113.2 deg) and clear of the team band (whose corners at
    # +-3.35, -2.56 and +-3.35, -4.35 put it across 217 - 323 deg), so nothing
    # is ever stacked on top of the ownership channel.
    p += sandbags(0, 0, ROOF_TOP, 4.75, h=0.85, n=7, arc=100.0, a0=115.0)
    p += sandbags(0, 0, ROOF_TOP, 4.75, h=0.85, n=7, arc=100.0, a0=325.0)

    # ── access, landward. Two flights and a pair of concrete cheek walls.
    # The berm's outer face rises 3.0 m in 0.9 m of run, so ANY stair on it
    # is a stair CUT INTO the bank rather than one laid on it - the cheeks are
    # what say so, and they are the part that stays visible from overhead
    # (concrete 0.098 against earth 0.219, 2.2:1, two hard parallel lines).
    # Both flights are sized to keep every vertex inside the 22 m cell: the
    # first cut ran to y = -11.59 because stair() offsets its stringers ALONG
    # the flight instead of across it, which puts them 0.6 m past the last
    # tread at each end.
    p += stair(0, -8.45, Z, BERM_H + 0.20, w=1.20, run=3.60, facing="y")
    p += stair(0, -6.00, BERM_H + 0.20, ROOF_TOP, w=1.10, run=1.30, facing="y")
    use(CONCRETE)
    for s in (-1, 1):
        o = profile([(-10.40, Z), (-6.40, Z), (-6.40, 3.55), (-10.40, 0.90)],
                    0.36, "stepcheek")
        o.location.x = s * 0.86
        p.append(o)

    # ── ownership. The roof is pi * 5.6^2 = 98.5 m2; team_mark() sizes its
    # band off a RECTANGLE, so the rectangle is chosen to inscribe: at
    # frac = 0.19 on l = 9.40 the band is 1.79 x 6.70 = 12.0 m2 = 12.1 % of
    # the circle, and its far edge at y = -4.35 has 3.53 m of circle either
    # side of the centreline against a 3.35 m half-band, so no corner of the
    # mark hangs over the drum.
    p += team_mark(7.40, 9.40, ROOF_TOP, frac=0.19)

    use("body")
    return p, struct_meta(W, L, ROOF_TOP, mount_z=MOUNT, door_y=R_ROOF)


# ═══ GROUP: COMMAND-ECONOMY ════════════════════════════════════════════════
# hq · power_plant · oil_derrick · refinery · supply_depot
#
# The economic spine, and the five buildings a player looks at most because
# they are what an attacker goes for. Written against the FOOTPRINTS table and
# the mount heights in game/sim/economy/sim_roster.gd, which are BINDING:
#
#     key            roster mount   what carries it here
#     hq                 14.0 m     top of the penthouse comms deck
#     power_plant        18.0 m     top of BOTH stack caps
#     oil_derrick        20.0 m     top of the crown block
#     refinery           22.0 m     top of the distillation column
#     supply_depot        8.0 m     top of the floodlight mast head
#
# The pair problem inside this group is oil_derrick -> refinery: they are one
# process (crude -> fuel) and must read as related without ever reading as each
# other. They are separated by MASS versus VOID. The derrick is the only
# structure in the roster you can see the terrain THROUGH - an open lattice on
# a bare fenced pad, 12 x 12 m, and from overhead it is not a shape at all, it
# is a square of thin lines with ground inside it and its shadow lying beside
# it. The refinery is the opposite: 28 x 24 m packed with solid circles of
# unequal diameter - three 9 m spheres, a 3.2 m column, two drums - so it is a
# field of discs where the derrick is a wireframe. Same steel palette, same
# pipe language, opposite plan density. Sizes help too: 16 m cell against 32 m.
#
# supply_depot is deliberately NOT a plant. It is an open compound - a fence,
# a gate, lanes and a repeating grid of separate ISO boxes - because the roster
# gives it the largest supply_radius in the game (340 m) and it should read as
# a NODE on the network rather than as a thing that makes something.


def _ce_shift(objs, dx=0.0, dy=0.0, dz=0.0):
    """Translate a helper's return value.

    Every helper in this module builds centred on the origin, which is right
    for a single mass and wrong the moment a structure has two of them (a hall
    and a boiler house, a main roof and a penthouse). Objects are moved by
    their OBJECT location, never by their mesh data, because hero_models.build
    applies rotation and scale but deliberately not location - so a shift here
    survives the join with world position intact.
    """
    for o in objs:
        x, y, z = o.location
        o.location = (x + dx, y + dy, z + dz)
    return objs


def hq():
    """Headquarters - 26 m cell, 22 x 22 m mass, roof 11.5 m, mount 14.0 m.

    OWNS EXCLUSIVELY: THE STEPPED ROOF. A second, smaller roof deck standing on
    top of the main one, with its own parapet. It is the only roof-on-roof in
    the roster, and the step is worth more than the shape: the penthouse stands
    2.2 m proud of the main deck, which at the render sun's 42 deg elevation
    lays a 2.44 m hard-edged shadow across the lower deck. Nothing else in the
    nineteen produces a shadow ON its own roof. Do not flatten the penthouse
    into a vent box and do not let any other role grow one.

    BASIS: a three-storey permanent-post headquarters block. 22 m square is a
    real double-loaded-corridor plan (two 6 m office bands either side of a
    2.4 m corridor, plus cores); 3.6 m floor-to-floor x 3 = 10.8 m, plus a
    0.7 m ground plinth and roof build-up = 11.5 m to the top of the walls.
    The penthouse is a 10 x 10 m plant and communications room, 1.95 m to the
    underside of its own roof slab, and its deck lands at exactly 14.00 m -
    the sim_roster mount figure, which is the height the datalink antenna
    steps off and the number the radar horizon is computed from.

    MILITARY FAMILY, so the roof grammar is FLAT, PLAIN AND FRAMED: a 0.85 m
    parapet ring on the main deck, a 0.55 m one on the penthouse. Concrete deck
    (luma 0.098) inside camo walls (0.588) is a 6:1 step, so the parapet reads
    as a pale ring around a dark field from directly overhead. The roof carries
    nothing else but a small vent cluster, the roof stair and the team band.
    """
    W = L = 22.0
    Z = 0.20                       # apron top
    WALL = 11.50                   # top of the walls / underside of the deck
    DECK = WALL + 0.30             # 11.80, top of the main roof slab
    PW = 10.0                      # penthouse plan
    PY = 3.0                       # penthouse pushed to +Y so the -Y half of
                                   # the main deck stays clear for the band
    PWALL = DECK + 1.50            # 13.30, top of the penthouse walls
    PDECK = PWALL + 0.25           # 13.55, top of the penthouse slab
    MOUNT = 14.00                  # = sim_roster["hq"]["mount"] EXACTLY

    p = apron(W, L)                                        # 26 x 26 m cell
    p += box_building(W, L, WALL - Z, z=Z)

    # glazed storey bands. These live on the WALLS, so they are worth almost
    # nothing from overhead and are here purely for the three-quarter read -
    # three of them stack the building into three floors at a glance.
    use("glass")
    for zg in (2.40, 6.00, 9.60):
        for s in (-1, 1):
            p.append(cube((s * (W / 2 - 0.02), 0, zg + 0.80), (0.16, L - 3.0, 1.60)))
            p.append(cube((0, s * (L / 2 - 0.02), zg + 0.80), (W - 3.0, 0.16, 1.60)))
    use("body")

    p += parapet_roof(W, L, WALL)                          # deck 11.80, rail 12.65

    # ── the step. Penthouse + its own parapet, offset to +Y.
    p += _ce_shift(box_building(PW, PW, 1.50, z=DECK), dy=PY)
    # the penthouse parapet tops out at exactly 14.00 - the roster mount
    p += _ce_shift(parapet_roof(PW, PW, PWALL, rail=0.45, t=0.25), dy=PY)

    # the comms farm. Every ANTENNA stops dead on 14.00 m: the roster uses
    # mount for the datalink antenna height and the model has to agree with it.
    # Measured overall height off the export is 14.65 m, and the 0.65 m above
    # the mount is the roof stair's handrail - a handrail, not a sensor. A 2.2 m antenna mast over an 11.5 m
    # roof is also simply what a real post headquarters carries - the height
    # comes from the building, not from a tower.
    for (ax, ay) in ((-3.2, -1.2), (0.0, -1.2), (3.2, -1.2)):
        p += mast(ax, ay, DECK, MOUNT - DECK - 0.20, r=0.085, stays=False,
                  head=(0.70, 0.08, 0.20))
    use(STEEL)
    p.append(cyl((5.6, -1.2, DECK + 0.55), 0.16, 1.10, v=8))        # dish pedestal
    p.append(cyl((5.6, -1.2, DECK + 1.35), 0.95, 0.26,
                 rot=(R(62), 0, 0), v=16))                          # satcom dish

    # roof stair from the main deck up to the penthouse deck - the human-scale
    # cue that is actually VISIBLE from the RTS camera, unlike a ground door.
    p += stair(0.0, -3.30, DECK, PDECK, w=1.30, facing="y")

    # external escape stair, two flights and a landing on the +X apron. A
    # single 11.6 m flight would be 65 treads and 18 m long; real buildings
    # break at a half-landing and so does this.
    MID = 5.85
    p += stair(12.0, -4.6, Z, MID, facing="y")
    p += stair(12.0, 4.6, MID, DECK, facing="y")
    use(STEEL)
    p.append(cube((12.0, 0, MID - 0.09), (1.90, 2.20, 0.18)))       # half-landing
    p.append(cube((12.0, 0, DECK - 0.09), (1.90, 1.60, 0.18)))      # top landing

    # rooftop plant, kept small and pushed into the -Y half. Anything on a roof
    # big enough to identify at 48 px competes with the element the role owns.
    p += _ce_shift(vent_kit(14.0, 5.0, DECK, n=3, seed=0, duct=False), dy=-6.0)

    # entrance: canopy, columns, low platform and a 3.6 x 3.0 m dark opening.
    use(CONCRETE)
    p.append(cube((0, -11.9, 3.90), (8.00, 2.00, 0.30)))            # canopy slab
    p.append(cube((0, -11.9, 0.35), (8.00, 2.00, 0.30)))            # entry platform
    use(STEEL)
    for s in (-1, 1):
        p.append(cyl((s * 3.2, -12.5, 2.02), 0.22, 3.65, v=10))
    p += door(0.0, -(L / 2 + 0.10), Z, 3.60, 3.00, facing="y", depth=0.45)

    p += team_mark(W, L, DECK)
    return p, struct_meta(W, L, WALL, mount_z=MOUNT, door_y=-L / 2)


def power_plant():
    """Power plant - 24 m cell, 20 x 16 m mass, hall roof 12.0 m, mount 18.0 m.

    OWNS EXCLUSIVELY: TWO EQUAL TAPERED STACKS SIDE BY SIDE. Circles are rare
    in a rectangular roster and a matched PAIR of them is unique - any other
    industrial role may carry one stack, never two alike. The pair is at
    x = +/- 5.0 m, so 10 m between centres against a 3.0 m base diameter: the
    gap is more than three times the stack, which is what keeps them reading as
    TWO objects at 48 px instead of one blob. Both reach 18.00 m to the top of
    the cap = sim_roster["power_plant"]["mount"], and at the render sun's
    42 deg they throw 19.8 m of shadow - the longest in the industrial family,
    and it lands on the plant's own apron and on the ground beyond it.

    BASIS: the turbine hall of a ~50 MW oil/gas station. Real halls are 30-40 m
    long; 20 m is a declared compression onto the grid, but the stacks keep
    their full roster height. A 50 MW oil-fired stack is really 2-3 m across
    and 30-45 m tall - 3.0 m base and 18 m is the same slenderness at the
    roster's height. Split plan: a 20 x 10 m machine hall at 12.0 m eaves on
    the -Y half, a 20 x 6 m boiler house at 6.0 m on the +Y half with both
    stacks rising from the apron THROUGH it, which is why the stacks read as
    18 m of stack and not as 6 m of stack on a 12 m roof.

    INDUSTRIAL FAMILY: no parapet anywhere. The hall roof is four 0.70 m steel
    ribs at a 2.0 m pitch - coarse on purpose, because a purlin pitch of 1 m
    aliases into grey at gameplay zoom - plus two extract cowls, and the -Y
    strip of the roof is left plain for the team band.
    """
    W, L = 20.0, 16.0
    Z = 0.20
    HALL_W, HALL_L, HALL_Y = 20.0, 10.0, -3.0          # y -8.0 .. +2.0
    BOIL_W, BOIL_L, BOIL_Y = 20.0, 6.0, 5.0            # y +2.0 .. +8.0
    HALL_TOP = 12.00
    BOIL_TOP = 6.00
    SX, SY = 5.0, 5.0                                  # stack centres
    SR = 1.50                                          # stack base radius
    # stack() puts the cap top at z + h + 0.36, so solve for the roster mount
    SH = 18.00 - Z - 0.36                              # 17.44
    MOUNT = 18.00                                      # = sim_roster mount

    p = apron(W, L)                                    # 24 x 20 m cell

    # ── machine hall
    p += _ce_shift(box_building(HALL_W, HALL_L, HALL_TOP - 0.25 - Z, z=Z), dy=HALL_Y)
    use(CONCRETE)
    p.append(cube((0, HALL_Y, HALL_TOP - 0.125), (HALL_W, HALL_L, 0.25)))
    use("glass")                                       # crane-hall clerestory
    for s in (-1, 1):
        p.append(cube((0, HALL_Y + s * (HALL_L / 2 - 0.02), 9.30),
                      (HALL_W - 2.4, 0.16, 1.70)))
        p.append(cube((s * (HALL_W / 2 - 0.02), HALL_Y, 9.30),
                      (0.16, HALL_L - 2.4, 1.70)))
    # roof ribs: the industrial "broken and repeating" read. Four ribs at a
    # 2.0 m pitch, 0.70 m deep, stopping 1.5 m short of the -Y eaves so the
    # team band has clean concrete to sit on.
    use(STEEL)
    for i in range(4):
        yr = HALL_Y - 3.0 + i * 2.0
        p.append(cube((0, yr, HALL_TOP + 0.35), (HALL_W - 0.6, 0.70, 0.70)))
    for s in (-1, 1):                                  # extract cowls
        p.append(cyl((s * 6.5, HALL_Y + 4.0, HALL_TOP + 0.75), 0.85, 1.50, v=12))
        p.append(cyl((s * 6.5, HALL_Y + 4.0, HALL_TOP + 1.62), 1.05, 0.24, v=12))

    # ── boiler house, lower, carrying both stacks
    p += _ce_shift(box_building(BOIL_W, BOIL_L, BOIL_TOP - 0.25 - Z, z=Z), dy=BOIL_Y)
    use(CONCRETE)
    p.append(cube((0, BOIL_Y, BOIL_TOP - 0.125), (BOIL_W, BOIL_L, 0.25)))
    p += handrail(BOIL_W - 0.4, BOIL_L - 0.4, BOIL_TOP)

    # ── THE PAIR. Equal in every argument - that equality is the identity.
    for sx in (-1, 1):
        p += stack(sx * SX, SY, Z, SH, SR, taper=0.70, group="body", bands=2)
    # breeching ducts, hall -> stack. A pipe that goes nowhere is worse than no
    # pipe, so both ends land on real geometry.
    for sx in (-1, 1):
        p += duct_run((sx * SX, 1.60, 8.60), (sx * SX, 3.65, 7.20), r=0.95)

    # switchyard on the -Y apron: transformers and a busbar frame. Steel is
    # 0.116 against concrete 0.098 and does not read, so these are here for the
    # three-quarter view; the roof does the identifying.
    use("body")
    for i in (-1, 0, 1):
        p.append(cube((i * 6.0, -9.0, 1.50), (2.40, 2.00, 2.60)))
    use(STEEL)
    for i in (-1, 0, 1):
        p.append(cyl((i * 6.0, -9.0, 3.55), 0.30, 1.50, v=10))
        p.append(cyl((i * 6.0 - 1.6, -9.0, 4.10), 0.10, 3.80, v=6))
        p.append(cyl((i * 6.0 + 1.6, -9.0, 4.10), 0.10, 3.80, v=6))
    p.append(cube((0, -9.0, 6.00), (15.0, 0.14, 0.14)))

    # external stair to the hall roof, two flights on the +X apron
    MID = 6.10
    p += stair(10.9, -4.6, Z, MID, facing="y")
    p += stair(10.9, 4.6, MID, HALL_TOP, facing="y")
    use(STEEL)
    p.append(cube((10.9, 0, MID - 0.09), (1.90, 2.20, 0.18)))
    p.append(cube((10.9, 0, HALL_TOP - 0.09), (1.90, 1.60, 0.18)))

    p += door(0.0, -(L / 2 + 0.10), Z, 5.00, 4.40, facing="y", depth=0.45)
    p += _ce_shift(team_mark(HALL_W, HALL_L, HALL_TOP), dy=HALL_Y)
    return p, struct_meta(W, L, HALL_TOP, mount_z=MOUNT, door_y=-L / 2)


def oil_derrick():
    """Oil derrick - 16 m cell, 12 x 12 m pad, rig floor 3.2 m, mount 20.0 m.

    OWNS EXCLUSIVELY: THE OPEN LATTICE DERRICK OVER A BARE FENCED PAD. This is
    the only structure in the roster you can see the terrain THROUGH, and that
    is the entire read. From directly overhead it is not a mass: it is a 9 m
    square of thin steel lines with ground visible inside it, its own shadow
    lying BESIDE it on the apron rather than under it, and a fence drawing the
    grid cell that the building has no walls to draw. NO CLADDING, EVER - the
    moment a panel goes on the derrick this becomes a small tower block and the
    role loses the one thing it has. The rig floor is a beam grid, not a slab,
    for the same reason.

    BASIS: a single-well land production site. 9 m square at the derrick base
    is a standard land-rig substructure footprint; the crown block sits at
    20.00 m = sim_roster["oil_derrick"]["mount"], which is short for a drilling
    mast (real ones are 40 m) and is declared as such - this is a PRODUCTION
    derrick over a completed well, and the roster's mount figure governs. Rig
    floor at 3.2 m is the real substructure height class for a small rig.

    INDUSTRIAL FAMILY. Its tall thin vertical is the derrick itself, and it is
    the extreme case of the family cue: 20 m of nothing but vertical.
    """
    W = L = 12.0
    Z = 0.20
    BASE_W, TOP_W = 9.0, 2.60
    CROWN = 20.00                       # = sim_roster["oil_derrick"]["mount"]
    FLOOR = 3.20                        # rig floor / substructure deck

    p = apron(W, L)                                    # 16 x 16 m cell
    p += fence(W, L, z=Z, gate="-y", posts=8)

    # ── the derrick. THE LATTICE IS CAMO, NOT STEEL, and that is a measured
    # decision rather than a stylistic one. The first build used the helper's
    # default gun-steel and at 48 px the derrick vanished: this module's own
    # value ladder puts steel at 0.116 against deck concrete at 0.098, which is
    # 1.18:1 - the exact "steel does not read against concrete" failure the
    # header warns about, and the derrick is nothing BUT thin members standing
    # on a concrete pad. Camo body is 0.588, so the same members against the
    # same pad are 6:1, the largest step in the palette. It stays see-through,
    # it just stops being invisible. Real land derricks are painted anyway.
    # Legs went 0.26 -> 0.36 and bays 7 -> 6 for the same reason: fewer, bolder
    # members survive the LOD2 decimate as bracing instead of as a grey haze.
    p += lattice_tower(0.0, 0.0, Z, CROWN - Z - 0.45, BASE_W, TOP_W,
                       bays=6, leg=0.36, group="body")
    use(STEEL)
    p.append(cube((0, 0, CROWN - 0.45), (2.80, 2.80, 0.90)))        # crown block
    for s in (-1, 1):                                              # crown sheaves
        p.append(cyl((s * 0.75, 0, CROWN - 0.45), 0.42, 0.34, rot=(0, R(90), 0), v=12))

    # ── rig floor as an OPEN BEAM GRID, so the pad stays see-through
    for s in (-1, 1):
        p.append(cube((s * 2.30, 0, FLOOR - 0.15), (0.30, 4.60, 0.30)))
        p.append(cube((0, s * 2.30, FLOOR - 0.15), (4.60, 0.30, 0.30)))
    for i in (-1, 0, 1):
        p.append(cube((i * 1.15, 0, FLOOR - 0.15), (0.22, 4.60, 0.28)))
    for s in (-1, 1):                                              # floor posts
        for t in (-1, 1):
            p.append(cyl((s * 2.30, t * 2.30, (FLOOR - 0.30 + Z) / 2 + 0.10),
                         0.18, FLOOR - 0.30 - Z, v=8))
    p += handrail(4.60, 4.60, FLOOR, posts=4)
    p += stair(0.0, -3.60, Z, FLOOR, w=1.30, facing="y")

    # wellhead, rotary table, draw-works and the travelling block on its line.
    # Small and central: they must not fill the square.
    use(STEEL)
    p.append(cyl((0, 0, FLOOR + 0.12), 0.70, 0.24, v=14))          # rotary table
    p.append(cyl((0, 0, FLOOR + 1.30), 0.34, 2.20, v=10))          # wellhead stack
    p.append(cube((0, 0, FLOOR + 2.55), (0.90, 0.90, 0.44)))       # tree
    p.append(cube((1.55, 0, FLOOR + 0.85), (1.60, 2.60, 1.40)))    # draw-works skid
    p.append(cyl((0, 0, 11.60), 0.05, 16.5, v=6))                  # drill line
    p.append(cube((0, 0, 8.20), (0.90, 0.90, 2.00)))               # travelling block

    # pad furniture, pushed to the edges. Mud tanks are RECTANGULAR on purpose:
    # circles in plan belong to the refinery, and these two roles must never
    # trade cues.
    use("body")
    p.append(cube((0, 4.70, 1.30), (5.40, 2.00, 2.20)))            # mud tanks
    p.append(cube((-3.10, -1.60, 1.50), (2.40, 3.20, 2.60)))       # doghouse
    use(STEEL)
    p.append(cube((0, 4.70, 2.48), (5.40, 2.00, 0.16)))
    p += duct_run((0.0, 3.70, 1.60), (0.0, 1.20, 1.60), r=0.22)    # flow line
    p += duct_run((-3.10, -3.10, 1.10), (-1.20, -1.20, 1.10), r=0.16)

    p += team_mark(W, L, Z)                            # the band is on the PAD
    return p, struct_meta(W, L, FLOOR, mount_z=CROWN, door_y=-L / 2)


def refinery():
    """Refinery - 32 m cell, 28 x 24 m plan, heater roof 7.0 m, mount 22.0 m.

    OWNS EXCLUSIVELY: SPHERES AND A COLUMN - a field of circles of UNEQUAL
    diameter, including true spheres on legs. No other role in the nineteen
    gets a sphere, and no other role gets more than two circles in plan. Here
    there are six of five different diameters (9.0, 9.0, 9.0, 5.2, 3.6, 3.2 m),
    which is what makes it read as a process plant rather than as a tank farm:
    a tank farm is equal circles, a refinery is a size ladder.

    BASIS: one small crude-distillation unit. The 22.0 m column is
    sim_roster["refinery"]["mount"] and is modelled at 3.2 m diameter, a real
    slenderness for a small topping column. The three spheres are 9.0 m across
    = 381 m3, which is a real small-LPG storage sphere, on 3.6 m legs so the
    equator stands clear. Fired heater 9 x 7 m with its own 14 m stack - ONE
    stack, of a different height and diameter from the power plant's matched
    pair, which is the rationing rule that keeps the two roles apart.

    INDUSTRIAL FAMILY. Tall thin vertical = the column, and its four ring
    platforms turn it into a stack of concentric circles from overhead, which
    is a second reading of the same "circles" idea and costs almost nothing.
    """
    W, L = 28.0, 24.0
    Z = 0.20
    COL_X, COL_Y, COL_R = -11.0, -6.5, 1.60
    COL_TOP = 22.00                     # = sim_roster["refinery"]["mount"]
    SPH_R, SPH_LEG, SPH_Y = 4.50, 3.60, 7.00
    SPH_Z = Z + SPH_LEG + SPH_R         # 8.30 centre, 3.80 bottom
    RACK_Z = 5.00
    HEAT_TOP = 7.00

    p = apron(W, L)                                    # 32 x 28 m cell

    # ── the column, with ring platforms and an access stair to the first one
    COL_CAP = COL_R * 0.55                             # 0.88 m dished head
    use("body")
    # cylinder stops one cap-rise short so the DISHED HEAD tops out at exactly
    # 22.00 m - the roster mount. Nothing on this model is taller.
    p.append(cyl((COL_X, COL_Y, (Z + COL_TOP - COL_CAP) / 2), COL_R,
                 COL_TOP - COL_CAP - Z, v=20))
    p.append(dome((COL_X, COL_Y, COL_TOP - COL_CAP), COL_R, COL_R, COL_CAP, v=16))
    use(STEEL)
    for zp in (5.00, 9.50, 14.00, 18.50):
        p.append(cyl((COL_X, COL_Y, zp), COL_R + 1.00, 0.14, v=20))
        p.append(cyl((COL_X, COL_Y, zp + 0.55), COL_R + 1.00, 0.07, v=20))
    p.append(cyl((COL_X + COL_R + 0.55, COL_Y, (Z + COL_TOP) / 2),
                 0.45, COL_TOP - Z, v=10))             # caged ladder run
    # the stair runs ALONG X, inboard. Running it in -Y put its top stringer
    # 1.10 m outside the apron (measured off the export: y = -15.10 against an
    # apron edge at -14.00), and the apron has to stay the outer plan or the
    # grid cell the player is buying is a lie.
    p += stair(COL_X, COL_Y + 3.10, Z, 5.00, facing="x")

    # ── the three spheres. Equal to each other, unequal to everything else.
    for sx in (-1, 0, 1):
        x = sx * 9.50
        use("body")
        p.append(dome((x, SPH_Y, SPH_Z), SPH_R, SPH_R, SPH_R, v=20))
        use(STEEL)
        for k in range(6):
            a = R(30 + k * 60)
            p.append(cyl((x + math.cos(a) * 3.20, SPH_Y + math.sin(a) * 3.20,
                          (Z + SPH_Z) / 2), 0.26, SPH_Z - Z, v=8))
        p.append(cyl((x, SPH_Y, SPH_Z + SPH_R + 0.30), 0.22, 0.70, v=8))
        p += duct_run((x, SPH_Y - SPH_R + 0.4, Z + 0.90),
                      (x, 1.90, Z + 0.90), r=0.24)     # sphere -> rack leg

    # ── pipe rack: seven portal frames on a 4.2 m bay, four pipes on top.
    # This is the piece that makes the plant read as CONNECTED rather than as
    # objects parked near each other.
    use(STEEL)
    for i in range(7):
        x = -12.6 + i * 4.20
        for sy in (-1, 1):
            p.append(cube((x, 0.50 + sy * 1.80, (Z + RACK_Z) / 2),
                          (0.42, 0.42, RACK_Z - Z)))
        p.append(cube((x, 0.50, RACK_Z - 0.20), (0.42, 4.20, 0.40)))
    for i, (dy, r) in enumerate(((-1.15, 0.30), (-0.35, 0.22),
                                 (0.45, 0.34), (1.30, 0.20))):
        p += duct_run((-13.20, 0.50 + dy, RACK_Z + 0.28 + i * 0.02),
                      (13.20, 0.50 + dy, RACK_Z + 0.28 + i * 0.02), r=r)
    p += duct_run((COL_X, COL_Y + 1.60, RACK_Z + 0.30),
                  (COL_X, 0.50, RACK_Z + 0.30), r=0.30)

    # ── fired heater with ONE stack, and two drums of unequal diameter
    p += _ce_shift(box_building(9.0, 7.0, HEAT_TOP - 0.25 - Z, z=Z), dx=2.0, dy=-5.0)
    use(CONCRETE)
    p.append(cube((2.0, -5.0, HEAT_TOP - 0.125), (9.0, 7.0, 0.25)))
    p += _ce_shift(handrail(8.6, 6.6, HEAT_TOP), dx=2.0, dy=-5.0)
    p += stack(2.0, -5.0, HEAT_TOP, 6.60, 0.85, taper=0.80, group="body", bands=1)
    p += duct_run((2.0, -1.60, 4.20), (2.0, 0.50, RACK_Z - 0.60), r=0.40)
    p += tank_cyl(11.0, -5.00, Z, 2.60, 8.00)          # 5.2 m drum
    p += tank_cyl(-2.5, 4.20, Z, 1.80, 6.50)           # 3.6 m drum
    p += duct_run((11.0, -5.00, 6.20), (11.0, 0.50, RACK_Z + 0.60), r=0.26)
    p += duct_run((-2.5, 4.20, 5.40), (-2.5, 1.20, RACK_Z + 0.60), r=0.22)

    # No control room and no flare stack. Both were tried and both cost more
    # than they returned: the control room is a plain box that competes with
    # the discs for plan area, and a flare would add a second tall thin
    # vertical, which is the power plant's territory. The heater house carries
    # the door instead.
    p += door(2.0, -8.60, Z, 2.40, 2.60, facing="y", depth=0.45)

    p += team_mark(W, L, Z)                            # band on the hardstand
    return p, struct_meta(W, L, HEAT_TOP, mount_z=COL_TOP, door_y=-8.60)


@keeps_group
def _ce_box_top(x, y, ztop, group):
    """A container ROOF panel, in the container's own colour.

    container() finishes every box with a full-width steel rail plate, which is
    right in elevation and wrong from directly overhead: it means the top face
    of every container in the yard is gun-steel at 0.116 whatever group the box
    itself was built in, so the checkerboard that separates the stacks was
    invisible in plan - the one view that decides anything. This lays the box's
    real colour back over the rail, 0.08 m proud, and restores a 5:1 step
    between a camo top and a steel one.
    """
    use(group)
    return [cube((x, y, ztop + 0.12), (2.26, 5.70, 0.10), rot=(0, 0, R(90)))]


def supply_depot():
    """Supply depot - 20 m cell, 16 x 16 m compound, stacks 5.4 m, mount 8.0 m.

    OWNS EXCLUSIVELY: THE MODULAR CONTAINER GRID. A repeating array of
    SEPARATE, IDENTICAL 6.06 m ISO boxes on a 2 x 3 pattern with lanes between
    them - the only repeating array of separate objects in the roster. Every
    other structure is one mass or a few unlike masses; this is nine copies of
    the same box. It is an open compound, not a building, which is the point:
    sim_roster gives it the largest supply_radius in the game (340 m) and the
    role is a NODE on the network rather than a plant that makes something.

    The checkerboard matters as much as the grid. Three of the six positions
    carry a second tier and three do not, and two boxes are steel-grey against
    seven camo, so from overhead the array is a value pattern rather than a
    solid rectangle - which is what stops it reading as one flat-roofed box.

    BASIS: an open container hardstand. 6.06 x 2.44 x 2.59 m is the 20 ft ISO
    box exactly, laid across the plan so a 2-wide x 3-deep grid with a 2.1 m
    centre lane and 1.2 m cross lanes fits a 16 m square with the -Y strip left
    over for the gate, the site office and the team band. The floodlight mast
    head lands at 8.00 m = sim_roster["supply_depot"]["mount"].

    INDUSTRIAL FAMILY, at its most reduced: no roof at all, so the "broken and
    repeating" grammar is carried by the array itself, and the tall thin
    vertical is the pair of floodlight masts.
    """
    W = L = 16.0
    Z = 0.20
    BOX_H = 2.59
    MOUNT = 8.00                                       # = roster mount

    p = apron(W, L)                                    # 20 x 20 m cell
    p += fence(W, L, z=Z, gate="-y", posts=8)

    # ── the grid. rot_z=90 lays the 6.06 m box along X, which is what lets a
    # 2 x 3 array plus lanes fit a 16 m square.
    COLS = (-4.10, 4.10)                               # 2.14 m centre lane
    ROWS = (-1.00, 2.60, 6.20)                         # 1.16 m cross lanes
    # deterministic value pattern - no random(), the build must be reproducible
    GREY = {(0, 1), (1, 2)}
    for ci, x in enumerate(COLS):
        for ri, y in enumerate(ROWS):
            g = STEEL if (ci, ri) in GREY else "body"
            p += container(x, y, Z, rot_z=90.0, group=g)
            if (ci + ri) % 2 == 0:                     # the second tier
                p += container(x, y, Z + BOX_H, rot_z=90.0,
                               group="body" if g == STEEL else g)
                p += _ce_box_top(x, y, Z + 2 * BOX_H, "body")
            else:
                p += _ce_box_top(x, y, Z + BOX_H, g)

    # ── site office: a two-high stack at the gate with an external stair and a
    # railed top. Nine identical boxes need one that a person clearly uses, and
    # the stair is the human-scale cue this role would otherwise have none of.
    OX, OY = 4.10, -4.50
    p += container(OX, OY, Z, rot_z=90.0, group="body")
    p += container(OX, OY, Z + BOX_H, rot_z=90.0, group="body")
    use("glass")
    for s in (-1, 1):
        p.append(cube((OX, OY + s * 1.24, Z + BOX_H + 1.55), (4.20, 0.14, 1.10)))
    p += stair(OX - 3.60, OY, Z, Z + BOX_H, w=1.10, facing="x")
    p += _ce_shift(handrail(6.00, 2.40, Z + 2 * BOX_H, posts=4), dx=OX, dy=OY)
    p += door(OX + 1.20, OY - 1.30, Z, 1.00, 2.10, facing="y", depth=0.35)

    # ── floodlight masts. Head top at exactly the roster's 8.00 m mount.
    for (mx, my) in ((-7.40, 7.40), (7.40, 7.40)):
        p += mast(mx, my, Z, MOUNT - Z - 0.35, r=0.16, stays=False,
                  head=(1.60, 0.90, 0.35))

    # ── gate furniture and lane hardware on the clear -Y strip
    use("body")
    p.append(cube((-5.00, -4.60, Z + 1.35), (2.60, 2.20, 2.30)))   # guard hut
    use(CONCRETE)
    p.append(cube((-5.00, -4.60, Z + 2.60), (2.90, 2.50, 0.20)))
    use(STEEL)
    p.append(cube((-1.60, -7.85, Z + 1.10), (0.30, 0.30, 1.80)))   # barrier post
    p.append(cube((0.40, -7.85, Z + 1.85), (4.30, 0.22, 0.22)))    # barrier boom
    use("body")                                                    # pallet stacks
    p.append(cube((-2.30, -3.30, Z + 0.55), (1.60, 1.20, 1.10)))
    p.append(cube((-0.20, -3.30, Z + 0.40), (1.60, 1.20, 0.80)))

    p += team_mark(W, L, Z, frac=0.10)                 # band on the hardstand
    return p, struct_meta(W, L, Z + 2 * BOX_H, mount_z=MOUNT, door_y=-L / 2)


# ═══════════════════════════════════════════════════════════════════════════
# PRODUCTION GROUP - barracks, light_factory, heavy_factory,
#                    research_facility, repair_depot
# ═══════════════════════════════════════════════════════════════════════════
# THE COLLISION THIS GROUP HAS TO SURVIVE
# ---------------------------------------
# Three of these five are sheds that things come out of. A player who wants a
# tank and clicks the shed that makes trucks has lost a build cycle, so the
# separation cannot rest on a sign over the door - at the gameplay zoom used
# for the audit sheet (1.9 px/m, so a 20 m building is 38 px across) a sign is
# one pixel. They are separated on three channels that all survive 48 px, and
# every one of them is a ROOF channel:
#
#   PLAN SIZE       barracks 24 m cell, heavy_factory 20, light_factory 16.
#                   A 50 percent step between neighbours in the ladder.
#   ROOF TEXTURE    barracks   three COARSE gable ridges with daylight gaps
#                              between the huts - you see apron through the
#                              plan, twice, in 1.5 m slots.
#                   light_fac  FINE sawtooth, three glazed ridges at 4 m pitch
#                              on a 12 m plan, plus a rendered stack outboard.
#                   heavy_fac  ONE unbroken camo deck with a black steel H
#                              across it, plus a bare steel flue at 15.5 m.
#   ROOF VALUE      barracks and heavy_factory are camo-bright (0.588) with
#                   dark linework on top; research_facility is concrete-dark
#                   (0.098) with a bright cross on top; repair_depot is
#                   bright-dark-bright banded. No two of the five have the
#                   same value pattern in plan.
#
# The other two are not sheds at all and are separated from the sheds first by
# family grammar: research_facility is MILITARY (flat, parapet-framed, plain)
# and repair_depot is INDUSTRIAL but WALLLESS, the only roof in the roster
# standing on columns with daylight under it.
#
# WHERE THE TEAM BAND GOES, AND WHY IT MOVES
# ------------------------------------------
# team_mark() is mandatory and its POSITION is the fixed thing: the -Y edge,
# always. The SURFACE it lands on is whichever horizontal surface the player
# is actually looking at for that role - the roof deck where there is a flat
# roof (heavy_factory, research_facility) and the front apron strip where the
# roof is pitched, sawtoothed or absent (barracks, light_factory,
# repair_depot). A band laid across a gable or a sawtooth would be a broken
# zig-zag and would read as damage. The apron band is at the same -Y edge, at
# the kerb, which is where the eye already goes to find the footprint.


@keeps_group
def _pd_shift(parts, dx=0.0, dy=0.0, dz=0.0):
    """Translate a list of objects returned by a shared helper.

    Same reasoning as _sd_shift above: cube()/cyl() carry geometry at the
    origin and position in `location`, profile() carries absolute geometry with
    location (0, 0, 0), and hero_models.build() applies rotation and scale only
    - so adding to `location` moves either kind correctly and survives the join.
    """
    for o in parts:
        o.location = (o.location[0] + dx, o.location[1] + dy, o.location[2] + dz)
    return parts


@keeps_group
def _pd_ring(pts, z, rail=0.85, t=0.30, group=CONCRETE):
    """A parapet following an arbitrary closed rectilinear plan.

    parapet_roof() rings a RECTANGLE, which is all eight of the other military
    roles need. research_facility's plan is a Greek cross, and the parapet is
    the whole point of the military roof grammar, so the ring has to follow
    twelve edges instead of four. `pts` must be counter-clockwise; each wall is
    inset by t/2 along the inward normal (-dy, dx) so its OUTER face lands
    exactly on the plan line, which is what parapet_roof does for a rectangle.
    """
    use(group)
    p = []
    n = len(pts)
    for i in range(n):
        (x0, y0), (x1, y1) = pts[i], pts[(i + 1) % n]
        dx, dy = x1 - x0, y1 - y0
        ln = math.hypot(dx, dy)
        nx, ny = -dy / ln, dx / ln                      # inward normal, CCW
        cx = (x0 + x1) / 2 + nx * t / 2
        cy = (y0 + y1) / 2 + ny * t / 2
        p.append(cube((cx, cy, z + rail / 2), (ln + t, t, rail),
                      rot=(0, 0, math.atan2(dy, dx))))
    return p


@keeps_group
def _pd_turn90(parts):
    """Rotate a whole helper's output a quarter turn about the world Z axis.

    sawtooth_roof() only steps along Y, so every shed that calls it gets ribs
    lying the same way in plan. MEASURED on the first audit sheet: barracks
    (three camo bands, ribs across X) and light_factory (three camo bands, ribs
    across X) were the same picture at two sizes - exactly the failure the
    ground audit found. Turning the factory's roof a quarter turn makes one
    striped ACROSS and the other striped DOWN, which is a difference that
    survives 48 px and costs nothing.

    Safe for both primitive kinds: cube()/cyl() carry position in `location`,
    which is rotated here explicitly, and profile() carries absolute geometry
    at location (0, 0, 0), so rotating about its own origin IS rotating about
    the world origin. Only valid while the parts carry no X or Y rotation,
    which is true of everything sawtooth_roof() makes.
    """
    for o in parts:
        x, y, z = o.location
        o.location = (-y, x, z)
        rx, ry, rz = o.rotation_euler
        assert abs(rx) < 1e-6 and abs(ry) < 1e-6, "_pd_turn90: tilted part"
        o.rotation_euler = (rx, ry, rz + R(90))
    return parts


@keeps_group
def _pd_steps(x, y, z0, z1, w, n=3, going=0.32, face=-1.0, group=CONCRETE):
    """A concrete entrance stoop: n slabs, each one `going` deeper than the one
    above, stacked against a wall at `y`.

    stair() is the right helper for a flight that carries the HEIGHT of a
    building, and its `w` is meant to stay near the 1.3 m default. A 0.55 m
    door threshold is not that: it is a stoop, it is concrete rather than steel
    in every real barracks and lab block, and it costs three cubes.
    """
    use(group)
    rise = (z1 - z0) / n
    p = []
    for i in range(n):
        depth = (n - i) * going
        p.append(cube((x, y + face * depth / 2, z0 + rise * (i + 0.5)),
                      (w, depth, rise)))
    return p


@keeps_group
def _pd_ladder(x, y, z0, z1, group=STEEL, face=1.0):
    """A caged roof-access ladder: two stiles, rungs at 0.30 m, three hoops.

    The other half of cue (c). stair() carries the height of a building the
    player is meant to walk up; a ladder carries the height of a thing he is
    only meant to service, and it costs a tenth of the geometry. Used where a
    full second flight would be 9 m of stair on a 16 m building.
    """
    use(group)
    h = z1 - z0
    n = max(2, int(h / 0.30))
    p = [cube((x + s * 0.24, y, z0 + h / 2), (0.07, 0.07, h)) for s in (-1, 1)]
    for i in range(n):
        p.append(cube((x, y, z0 + (i + 0.5) * h / n), (0.55, 0.05, 0.05)))
    for i in range(3):
        p.append(cube((x, y + face * 0.18, z0 + h * (0.45 + 0.24 * i)),
                      (0.62, 0.42, 0.06)))
    return p


# ── barracks ───────────────────────────────────────────────────────────────
def barracks():
    """Infantry barracks. MILITARY family, and the family's one pitched roof.

    OWNS EXCLUSIVELY: THREE PARALLEL GABLE RIDGES WITH DAYLIGHT BETWEEN THEM.
    Three separate huts, not one hut with three ridges - the 1.5 m fire gaps go
    all the way to the apron, so from overhead the plan is a bright band, a
    dark slot, a bright band, a dark slot, a bright band. Coarse (7.0 m pitch),
    symmetric (a gable has a ridge down the middle) and SEPARATED, which is the
    deliberate opposite of light_factory's fine, asymmetric, continuous
    sawtooth at 4.0 m pitch. No other structure may be built from detached
    parallel masses.

    BASED ON: the US 700-series mobilization barracks, 27 x 100 ft
    (8.2 x 30.5 m), two storeys. Compressed to this grid at 5.5 x 20.0 m and
    kept as THREE buildings rather than merged into one block, because the gaps
    are the identity.

    THE GAP WIDTH IS MEASURED, NOT CHOSEN. The first audit sheet was built with
    5.5 m huts at 7.0 m centres, giving 1.5 m gaps - real fire separation for
    timber barracks - and at 2.4 px/m those gaps came out 3.6 px wide, which is
    the same mark as a roof rib. barracks and light_factory were one picture at
    two sizes. The huts are now 5.0 m at 7.5 m centres: 2.5 m of gap, 2.2 m of
    it still open at plinth level, a 1:2 duty cycle against the 5 m huts
    instead of 1:3.7, and the apron is visible THROUGH the plan twice.

    MEASURED: plan 20.0 x 20.3 m inside a 24.0 x 24.0 m apron. Plinth 0.20 to
    0.75, two storeys of 2.65 m to eaves at 6.05, gable rise 1.95 m (38.0 deg
    pitch over the 2.5 m half-span) to a ridge at 8.00 m, which is the roster's
    mount figure exactly. The brief's 7.6 m ridge was raised 0.40 m for that
    reason: sim_roster gives barracks mount 8.0, and a sensor socket hanging
    0.4 m above the roof in mid-air is worse than a 38 deg pitch.
    """
    p = []
    p += apron(20.0, 20.0)                              # 24 x 24 m cell

    for cy in (-6.50, 1.00, 8.50):                      # 7.5 m centres
        # concrete plinth: a bright 0.15 m ledge round each hut, so the three
        # masses have a hard base line on the apron and read as separate
        use(CONCRETE)
        p.append(cube((0, cy, 0.475), (20.6, 5.3, 0.55)))
        p += _pd_shift(box_building(20.0, 5.0, 5.30, z=0.75), dy=cy)
        p += _pd_shift(gable_roof(20.0, 5.0, 6.05, 1.95), dy=cy)
        # ridge ventilator. Steel on camo is 5:1, so this is a dark line down
        # the middle of every bright band - it says "ridge" from overhead,
        # where a gable's own slope difference says nothing. Kept NARROW
        # (0.60 m) so it stays a centre line and never reads as a rib edge.
        use(STEEL)
        p.append(cube((0, cy, 7.62), (12.0, 0.60, 0.55)))
        # two doors and two stoops per hut on the -Y long wall
        for dx in (-5.0, 5.0):
            p += door(dx, cy - 2.35, 0.75, 1.60, 2.40)
            p += _pd_steps(dx, cy - 2.70, 0.20, 0.75, 2.20)

    # team band on the front apron strip: the roof is pitched, so the largest
    # FLAT surface is the apron, and the -Y kerb is where the eye already is.
    # The three huts are pushed 1.0 m towards +Y to open a 2.85 m formation
    # apron at the front, which is where a barracks square is anyway; frac 0.09
    # -> a 2.16 m band clearing the front plinth edge at -9.15 by 0.34 m.
    p += team_mark(20.0, 24.0, 0.20, frac=0.09)
    return p, struct_meta(20.0, 20.3, roof_z=8.00, mount_z=8.00, door_y=-9.15)


# ── light_factory ──────────────────────────────────────────────────────────
def light_factory():
    """Light vehicle factory. INDUSTRIAL family.

    OWNS EXCLUSIVELY: THE SAWTOOTH ROOF. Glazed north-lights at 4.0 m pitch
    across the whole 12 m plan, plus a glazed monitor straddling each ridge so
    the stripe survives the camera: the helper's riser glazing faces +Y, which
    is AWAY from a camera sitting at -Y, so on its own it would only ever be a
    shadow. The monitors are 1.40 m wide - 35% of the pitch, 3.4 px at the
    audit zoom - and stand 0.50 m proud so each casts its own line as well.
    Nothing else in the roster is allowed a repeating ribbed roof.

    AND THE RIBS RUN THE OTHER WAY. The roof is turned a quarter turn by
    _pd_turn90 so the stripes run DOWN the plan while barracks' three ridges
    run ACROSS it. That is the fix for the one collision that actually
    appeared on the first audit sheet, and it is worth more than any amount of
    detail: two striped roofs at two sizes are one picture; a striped roof and
    a cross-striped roof are two.

    BASED ON: a light-vehicle assembly shed with north-light bays. Real
    north-light bays are 6-9 m; 4.0 m is a DECLARED exaggeration - at 6 m a
    12 m plan holds two ribs and reads as two steps rather than as a texture.

    MEASURED: 12.0 x 12.0 m plan in a 16.0 x 16.0 m apron, eaves 6.20 m, tooth
    crown 8.40 m, monitor crown 8.90 m. Boiler stack 9.65 m of shaft from the
    apron with its cap at 10.00 m - the roster's mount figure - at 1.10 m
    diameter, standing outboard of the -X flank where it is seen against a camo
    wall (5:1) and against sky, never against concrete (1.18:1).
    """
    p = []
    p += apron(12.0, 12.0)                              # 16 x 16 m cell
    p += box_building(12.0, 12.0, 6.00)                 # eaves 6.20
    # The roof is built along Y and then TURNED, so its ribs lie across the
    # plan the opposite way from barracks' three ridges. See _pd_turn90.
    roof = sawtooth_roof(12.0, 12.0, 6.20, bays=3, rise=2.20, glaze=0.62)
    # glazed ridge monitors, one per tooth, straddling the 1.80 m step. 1.40 m
    # wide, which is 35% of the 4.0 m pitch: from overhead the roof is a third
    # dark blue by area, not three hairlines.
    use("glass")
    for i in range(3):
        yr = -6.0 + (i + 1) * 4.0                       # ridge of tooth i
        roof.append(cube((0, yr - 0.55, 8.55), (11.4, 1.40, 0.70)))
    use(STEEL)
    for i in range(3):
        yr = -6.0 + (i + 1) * 4.0
        for s in (-1, 1):
            roof.append(cube((0, yr - 0.55 + s * 0.70, 8.86), (11.5, 0.10, 0.10)))
    p += _pd_turn90(roof)

    # the industrial family's mandatory tall thin vertical. Overlaps the flank
    # wall by 0.05 m so it is welded rather than a floating island.
    p += stack(-6.50, 2.00, 0.20, 9.65, 0.55, taper=0.70, group="body")

    # 4.5 x 4.6 m roller shutter, black into camo (49:1), with a concrete
    # lintel and jambs so the void has the light surround the value ladder asks
    # for. This is the finished-vehicle door and it is deliberately HALF the
    # size of heavy_factory's 7.0 x 7.0 m one.
    p += door(0.0, -5.95, 0.20, 4.50, 4.60)
    use(CONCRETE)
    p.append(cube((0, -6.25, 5.10), (5.60, 0.70, 0.40)))
    for s in (-1, 1):
        p.append(cube((s * 2.65, -6.25, 2.70), (0.50, 0.70, 4.80)))
    p += door(-4.30, -5.95, 0.20, 1.20, 2.20)
    p += _pd_steps(-4.30, -6.05, 0.20, 0.62, 1.80, n=2)

    # external stair to the eaves. 6.00 m of rise at the real 0.18/0.28 tread
    # ratio is a 9.24 m flight at 33 deg - that length IS the height cue.
    p += stair(6.60, 0.00, 0.20, 6.20, w=1.30)
    use(STEEL)
    p.append(cube((6.60, 5.20, 6.35), (1.80, 1.60, 0.30)))
    p += _pd_shift(handrail(1.70, 1.50, 6.50, posts=2), dx=6.60, dy=5.20)

    p += team_mark(12.0, 16.0, 0.20, frac=0.09)
    return p, struct_meta(12.0, 12.0, roof_z=8.90, mount_z=10.00, door_y=-6.00)


# ── heavy_factory ──────────────────────────────────────────────────────────
def heavy_factory():
    """Heavy vehicle factory. INDUSTRIAL family.

    OWNS EXCLUSIVELY: THE GANTRY CRANE BRIDGE. Two rails down the long edges
    and one heavy transverse bar across them, an H in plan, sitting on a CLOSED
    hall. naval_yard has the same bar but on legs beside a water basin; nothing
    else in the roster carries a transverse bridge at all.

    The roof deck is CAMO, not concrete, and that is a value decision rather
    than a material one: bare steel is 0.116 and concrete is 0.098, a ratio of
    1.18, so an H laid on a concrete roof is invisible at gameplay zoom. On
    camo at 0.588 the same H is 5:1 and it is the first thing the eye finds.

    BASED ON: a single-bay armour hall spanned by a 16 m overhead travelling
    crane of the 30 t class, eaves at the roster's own mount figure of 12.0 m -
    enough hook height to lift a hull over another hull.

    MEASURED: 16.0 x 16.0 m plan in a 20.0 x 20.0 m apron. Walls 0.20 to 12.00,
    roof deck 12.00 to 12.35, runway girders to 12.80, crane rails to 13.30,
    bridge soffit 13.30 and bridge crown 14.90. Crane gauge 13.6 m inside the
    16 m hall. Vehicle door 7.0 x 7.0 m. Fume flue 15.50 m at 1.50 m diameter,
    bare steel, read against the camo flank and the sky.
    """
    p = []
    p += apron(16.0, 16.0)                              # 20 x 20 m cell
    p += box_building(16.0, 16.0, 11.80)                # eaves / mount 12.00
    use("body")
    p.append(cube((0, 0, 12.175), (16.0, 16.0, 0.35)))  # camo roof deck

    # THREE roof-lights, one row, at the +Y end. The first audit sheet carried
    # six in two rows and they beat the crane: the roof read as a windowed box
    # and the H read as edge trim. Roof texture is texture; it does not get to
    # be the identity, and where it competes it loses rows.
    use("glass")
    for cx in (-4.00, 0.0, 4.00):
        p.append(cube((cx, 6.20, 12.44), (2.40, 1.80, 0.22)))

    # THE CRANE RUNWAY, then THE H. gantry()'s rails are 0.55 m wide and sat
    # 0.45 m in from a 16 m roof edge, which reads as a parapet lip rather than
    # as a rail. Real runway rails sit on GIRDERS carried on corbels inboard of
    # the wall, so the girders are drawn: 0.90 m wide, 0.45 m proud, on a
    # 13.6 m gauge - the crane a 16 m hall actually takes - which puts two
    # 2.2 px steel lines 1.65 m INSIDE the roof outline where they read as
    # lines on the roof. gantry() is rationed: heavy_factory legs=False,
    # naval_yard legs=True, and no third caller.
    use(STEEL)
    for s in (-1, 1):
        p.append(cube((s * 6.35, 0, 12.575), (0.90, 16.00, 0.45)))
    p += gantry(13.6, 16.0, 12.80, rail_h=0.50, beam=1.60, legs=False)

    # the family's tall thin vertical, and the counterpart to light_factory's
    # rendered stack: bare steel, half again as tall, straight rather than
    # tapered, so the pair of factories never share a skyline element either.
    p += stack(8.60, -4.00, 0.20, 15.10, 0.75, taper=0.90, group=STEEL,
               bands=3)

    # 7.0 x 7.0 m vehicle door with a concrete surround - twice the area of
    # light_factory's, which is the size cue a player reads at the door itself
    p += door(0.0, -7.90, 0.20, 7.00, 7.00)
    use(CONCRETE)
    p.append(cube((0, -8.20, 7.55), (8.20, 0.75, 0.55)))
    for s in (-1, 1):
        p.append(cube((s * 3.95, -8.20, 3.85), (0.55, 0.75, 7.30)))
    p += door(-6.30, -7.90, 0.20, 1.20, 2.20)

    # human scale on a 12 m wall: one 9.24 m flight to a landing at 6.20, then
    # a caged ladder. A second flight would be another 9.2 m of stair on a
    # 20 m apron and would read as a ramp.
    p += stair(-8.60, 0.00, 0.20, 6.20, w=1.30)
    use(STEEL)
    p.append(cube((-8.60, 5.30, 6.35), (1.90, 1.80, 0.30)))
    p += _pd_shift(handrail(1.80, 1.70, 6.50, posts=2), dx=-8.60, dy=5.30)
    p += _pd_shift(_pd_ladder(0, 0, 6.50, 12.35, face=-1.0), dx=-8.15, dy=5.30)

    p += team_mark(16.0, 16.0, 12.35, frac=0.12)        # on the camo deck
    return p, struct_meta(16.0, 16.0, roof_z=12.35, mount_z=12.00, door_y=-8.00)


# ── research_facility ──────────────────────────────────────────────────────
def research_facility():
    """Research facility. MILITARY / ADMINISTRATIVE family.

    OWNS EXCLUSIVELY: THE CRUCIFORM PLAN. Two 8 m wings crossing at right
    angles, with a glazed lantern running along both spines. The only
    non-rectangular administrative plan in the roster, and it still sits inside
    a square 24 m grid cell so placement is unaffected - the apron under it is
    a plain 24 x 24 m rectangle and the four re-entrant corners are deliberately
    left EMPTY, because filling them with a stair core or a plant room would
    turn the cross back into a square.

    The lantern is the second half of the identity and it is a VALUE trick: a
    concrete deck is 0.098 and a camo mass is 0.588, so a 3.0 m camo-capped
    lantern on a dark deck is a bright cross at 6:1 - the only bright cross in
    the game. It is 3.0 m wide with no parapet of its own, so it cannot be
    confused with hq's stepped penthouse deck, which is a large rectangle WITH
    a parapet.

    BASED ON: a mid-century laboratory block. The 8 m wing depth is the real
    daylight limit for a double-loaded lab corridor - 3.0 m of bench each side
    of a 2.0 m corridor - which is exactly why real labs of the period are
    cruciform, H- or E-shaped instead of deep and square.

    MEASURED: 20.0 x 20.0 m over the arms, 8.0 m wing depth, in a 24 x 24 m
    apron. Podium 0.20 to 0.75, three storeys of 3.35 m to a roof structure at
    10.80, deck 10.80 to 11.10, parapet crown 11.95, lantern crown 12.00 -
    which is the roster's mount figure exactly - and the rooftop vent cluster
    at 12.44 as the only thing above it.
    """
    A, B = 20.0, 8.0                                    # arm span, wing depth
    p = []
    p += apron(20.0, 20.0)                              # 24 x 24 m cell

    # cruciform podium and mass. Two crossed boxes; the overlap is joined away.
    use(CONCRETE)
    p.append(cube((0, 0, 0.475), (A + 0.6, B + 0.6, 0.55)))
    p.append(cube((0, 0, 0.475), (B + 0.6, A + 0.6, 0.55)))
    p += box_building(A, B, 10.05, z=0.75)
    p += box_building(B, A, 10.05, z=0.75)
    use(CONCRETE)
    p.append(cube((0, 0, 10.95), (A, B, 0.30)))         # deck 10.80 -> 11.10
    p.append(cube((0, 0, 10.95), (B, A, 0.30)))

    # the twelve-edge parapet, counter-clockwise from the +X arm's -Y corner
    a, b = A / 2, B / 2
    p += _pd_ring([(a, -b), (a, b), (b, b), (b, a), (-b, a), (-b, b),
                   (-a, b), (-a, -b), (-b, -b), (-b, -a), (b, -a), (b, -b)],
                  11.10, rail=0.85, t=0.30)

    # the glazed lantern, stopped 2.5 m short of each arm end so the arm ends
    # keep plain parapeted deck - which is where the team band goes
    for wx, wy in ((15.0, 2.60), (2.60, 15.0)):
        use("glass")
        p.append(cube((0, 0, 11.43), (wx, wy, 0.65)))
        use("body")
        p.append(cube((0, 0, 11.875), (wx + 0.40, wy + 0.40, 0.25)))

    # a small vent cluster on the +Y arm - texture, not identity
    p += _pd_shift(vent_kit(6.0, 5.0, 11.10, n=2, seed=1), dy=7.20)

    # entrance on the -Y arm end: recessed void, concrete canopy on two
    # columns, and a 5 m-wide flight up the 0.55 m podium
    p += door(0.0, -9.80, 0.75, 3.60, 3.00)
    use(CONCRETE)
    p.append(cube((0, -10.90, 3.90), (6.40, 2.00, 0.35)))
    use(STEEL)
    for s in (-1, 1):
        p.append(cube((s * 2.80, -10.90, 2.05), (0.30, 0.30, 3.70)))
    p += _pd_steps(0.0, -10.35, 0.20, 0.75, 6.00, going=0.40)

    # external escape stair on the +X arm end, one flight to a landing at 5.85
    # and a caged ladder above. Thin, steel, and symmetric in extent about the
    # X axis so the cruciform plan is not turned into an arrow.
    p += stair(10.95, 0.00, 0.20, 5.85, w=1.20)
    use(STEEL)
    p.append(cube((10.95, 4.80, 6.00), (1.70, 1.50, 0.30)))
    p += _pd_shift(_pd_ladder(0, 0, 6.15, 11.10, face=-1.0), dx=10.55, dy=4.80)

    p += team_mark(8.0, 20.0, 11.10, frac=0.10)         # -Y arm deck
    return p, struct_meta(20.0, 20.0, roof_z=11.10, mount_z=12.00, door_y=-10.0)


# ── repair_depot ───────────────────────────────────────────────────────────
def repair_depot():
    """Repair depot. INDUSTRIAL family, and the only walless one.

    OWNS EXCLUSIVELY: THE THREE-BAND HARDSTAND. Open canopy, black through-lane
    with inspection pits, open canopy - bright, dark, bright, straight across
    the plan. It is also the only roof in the game standing on columns with NO
    walls, so daylight shows under both canopies at the game's 52 deg camera
    and the columns read as a row of separate legs rather than as a wall.

    The band contrast is the largest in the palette and it is free: the canopy
    decks are camo at 0.588 and the lane is asphalt at 0.048, which is 12:1.
    The pits are gunbore at 0.012 but they are sunk inside bright concrete kerb
    frames, because a black slot cut into tarmac is 4:1 and would vanish.

    THE JIB, not a portal. The roster's 10.0 m mount is carried by a pillar jib
    crane - one vertical column with one horizontal arm cantilevered over the
    lane, an L in silhouette. gantry() is rationed to heavy_factory and
    naval_yard, and a portal frame here would have read as a small naval_yard.

    BASED ON: a field maintenance hardstand. The roster basis quotes two 7 m
    bays split by a 6 m lane, which is 20.0 m and does NOT fit the declared
    20 m cell once the mandatory 2 m apron is taken off each side. The bays are
    therefore compressed to 5.5 m - still 0.9 m of working room each side of an
    M88 HERCULES at 3.66 m wide, the widest recovery vehicle in the ground
    roster - and the lane to 5.0 m, giving 5.5 + 5.0 + 5.5 = 16.0 m exactly.

    MEASURED: 16.0 x 16.0 m plan in a 20.0 x 20.0 m apron. Canopy soffit
    6.00 m, deck crown 6.40 m on 16 columns of 0.40 m square at 4.67 m centres.
    Lane 5.0 x 16.0 m of asphalt; two inspection pits 1.4 x 5.0 m in kerb
    frames 0.20 m proud. Jib pillar 0.20 to 10.00 m - the roster's mount - with
    a 6.9 m arm at 8.85 m and a hook block over the lane.
    """
    p = []
    p += apron(16.0, 16.0)                              # 20 x 20 m cell

    # ── the dark band: asphalt lane down the middle, entered from -Y
    use(ASPHALT)
    p.append(cube((0, 0, 0.24), (5.00, 16.00, 0.08)))
    use(CONCRETE)
    for s in (-1, 1):                                   # bright lane kerbs
        p.append(cube((s * 2.62, 0, 0.34), (0.26, 16.00, 0.20)))
    for cy in (-3.60, 3.60):                            # two inspection pits
        use(VOID)
        p.append(cube((0, cy, 0.31), (1.40, 5.00, 0.10)))
        use(CONCRETE)
        for s in (-1, 1):
            p.append(cube((s * 0.85, cy, 0.38), (0.30, 5.60, 0.20)))
            p.append(cube((0, cy + s * 2.65, 0.38), (2.00, 0.30, 0.20)))

    # ── the two bright bands: camo canopy decks on open steel columns
    for cx in (-5.25, 5.25):
        use(STEEL)
        for sx in (-1, 1):
            for cy in (-7.00, -2.33, 2.33, 7.00):
                p.append(cube((cx + sx * 2.35, cy, 3.10), (0.40, 0.40, 5.80)))
            p.append(cube((cx + sx * 2.95, 0, 5.85), (0.25, 16.40, 0.45)))
        use("body")
        p.append(cube((cx, 0, 6.20), (5.90, 16.40, 0.40)))
        use(STEEL)
        for cy in (-6.00, -2.00, 2.00, 6.00):           # transverse roof ribs
            p.append(cube((cx, cy, 6.52), (5.90, 0.35, 0.24)))
        p += _pd_shift(handrail(5.60, 16.10, 6.40, posts=7), dx=cx)

    # ── the jib crane, an L: one pillar, one arm, one tie, one hook block
    use(CONCRETE)
    p.append(cube((0, 6.60, 0.30), (1.90, 1.90, 0.20)))
    use(STEEL)
    p.append(cyl((0, 6.60, 5.10), 0.34, 9.80, v=12))    # 0.20 -> 10.00
    p.append(cube((0, 3.30, 8.85), (0.36, 6.90, 0.50)))
    p += duct_run((0, 6.60, 9.90), (0, 0.40, 9.05), r=0.08, v=6)
    p.append(cube((0, 1.80, 8.45), (0.60, 0.90, 0.36)))  # trolley
    p.append(cyl((0, 1.80, 8.05), 0.05, 1.30, v=6))      # fall rope
    p.append(cube((0, 1.80, 7.55), (0.50, 0.70, 0.90)))  # hook block

    # ── roof access. 6.4 m is over the 6 m threshold, so it gets a real
    # flight, bridged onto the west deck by a landing so nothing floats.
    p += stair(-9.00, 0.00, 0.20, 6.40, w=1.30)
    use(STEEL)
    p.append(cube((-8.60, 4.60, 6.55), (2.40, 1.60, 0.30)))

    p += team_mark(16.0, 20.0, 0.20, frac=0.075)        # front apron strip
    return p, struct_meta(16.0, 16.0, roof_z=6.40, mount_z=10.00, door_y=-8.00)


# ═══ THE AIR GROUP: airbase - hardened_shelter - helipad ═══════════════════
# Three roles that all serve aircraft and therefore all risk reading as "a flat
# grey area with a thing on it". They are separated on PLAN GEOMETRY, which is
# the one channel that survives to 48 px:
#
#   airbase           a 44 x 40 m RECTANGLE of near-black asphalt, painted,
#                     with two open arch mouths along its +Y edge. The biggest
#                     footprint in the game (48 m cell) and the darkest field.
#   hardened_shelter  an OVAL of olive earth, 20 x 13.2 m, with a concrete
#                     portal projecting from one end and a black mouth in it.
#                     The only rounded plan outline in the roster.
#   helipad           a 12 m SQUARE plinth with a painted RING on it inside a
#                     16 m concrete apron. The only painted circle in the game
#                     and, at 0.90 m, by far the flattest structure.
#
# So at gameplay zoom the three are: a big dark rectangle, a small olive oval,
# a small pale square with a ring in it. Different SIZE, different VALUE and
# different PLAN CURVE - three independent channels, none of which asks the
# player to resolve a wall.
#
# The near-black asphalt field is rationed to airbase by the ownership rules,
# so helipad's 12 m pad is the one other asphalt surface allowed anywhere and
# it is a twelfth of the area (144 m2 against 1760 m2). It reads as the same
# MATERIAL without being confusable as the same OBJECT, which is exactly what
# an airfield and a helipad are.


@keeps_group
def _air_shift(parts, dx=0.0, dy=0.0, dz=0.0):
    """Translate objects returned by a shared helper that builds about origin.

    Kept local to this group rather than promoted into the shared kit: the
    helpers above are the module's contract and this is a convenience. Safe
    because cube()/cyl() carry their geometry at the origin and their position
    in `location`, profile()-based helpers carry absolute geometry with
    location (0,0,0), and hero_models.build() applies rotation and scale ONLY -
    so `location` survives untouched into the join.
    """
    for o in parts:
        o.location = (o.location[0] + dx, o.location[1] + dy, o.location[2] + dz)
    return parts


@keeps_group
def _paint_ring(cx, cy, z, r_out, band=0.55, t=0.07, v=48,
                group=CONCRETE, fill=ASPHALT):
    """A painted circle, built as TWO DISCS rather than as a ring of bars.

    The ring is the one plan mark in the roster that is not a rectangle, and it
    has to be BUILT rather than textured because the blockout has no decals.
    The first version laid 40 tangential bars around the circle; it cost about
    4000 triangles at LOD0 and, rendered at the 52 deg camera, every bar end
    bevelled and the mark read as a cobbled kerb rather than as paint.

    Two coaxial discs are better on every count: a `group` disc of radius
    r_out standing t proud of the pad, and a `fill` disc of radius
    r_out - band standing 0.01 m higher, in the SAME material as the pad, which
    covers the middle. The visible result is a true annulus with no facets, and
    it costs 4v + 4 triangles instead of forty bevelled boxes.

    t is 0.07 m rather than coplanar for the usual reason: a coincident face
    z-fights, and the relief gives the bevel something to catch so the mark
    survives the LOD2 decimate as a shape. It also matters more here than
    anywhere else, because deck 0.098 over track 0.048 is only a 2:1 albedo
    step - the highlight and the hairline shadow are carrying half the read.
    """
    use(group)
    p = [cyl((cx, cy, z + t / 2), r_out, t, v=v)]
    use(fill)
    p.append(cyl((cx, cy, z + (t + 0.01) / 2), r_out - band, t + 0.01, v=v))
    return p


@keeps_group
def _arch_hangar(cx, cy, w=18.0, l=14.0, wall=5.40, crown=8.40, mouth_w=15.6):
    """One open-fronted arch hangar, mouth facing -Y. AIRBASE ONLY.

    Camo side walls and a back wall carry a shallow elliptical vault; the mouth
    is a VOID block standing 1.0 m PROUD of the arch face. Proud, not recessed,
    because these are solid blockout masses joined per material group: a void
    volume buried inside a solid body is invisible, so the only way to publish
    an opening is to let the black block break the surface. At the 52 deg
    camera a 15.6 x 6.2 m black face standing 1 m out of an elliptical camo rim
    reads as a hangar mouth from every azimuth, and from directly overhead it
    reads as a 15.6 x 1.0 m black reveal along the front edge - which is what
    the door pocket of a real hangar looks like from the air.

    The vault is deliberately SHALLOW: 3.20 m of rise over a 9.0 m half-span,
    a ratio of 0.36, against hardened_shelter's 8.30 m over 10.0 m, a ratio of
    0.83. Same curved-roof idea, opposite proportion, opposite material - this
    pair is camouflaged concrete standing on tarmac, the HAS is buried in
    olive earth. Nothing else in the roster gets a curved roof at all.
    """
    p = []
    z0 = 0.28                                   # standing on the asphalt field
    hw = wall - z0
    use("body")
    for s in (-1, 1):                           # side walls, 1.2 m thick
        p.append(cube((cx + s * (w / 2 - 0.6), cy, z0 + hw / 2), (1.2, l, hw)))
    p.append(cube((cx, cy + l / 2 - 0.6, z0 + hw / 2), (w, 1.2, hw)))   # back
    # The vault. z is the ellipse CENTRE and rise its vertical semi-axis, so
    # the lowest point of the solid is z - rise = 2.00 m - above ground (the
    # module forbids anything under z = 0) and inside the walls.
    rise = 3.20
    p += _air_shift(barrel_roof(w, l, z=crown - rise, rise=rise, span="y",
                                group="body"), dx=cx, dy=cy)
    use(VOID)                                   # the mouth
    p.append(cube((cx, cy - l / 2 + 0.8, z0 + 3.10), (mouth_w, 3.6, 6.20)))
    # 2.10 m personnel door in the inboard wall - the human-scale cue that
    # tells the player the mouth beside it is 6.2 m and not 2.5 m. Inboard
    # because the outboard wall of the -X hangar carries the access stair.
    sgn = -1.0 if cx > 0 else 1.0
    p += door(cx + sgn * (w / 2 - 0.05), cy - 3.5, z0, 1.00, 2.10,
              facing="x", depth=0.40)
    return p


# ── airbase ────────────────────────────────────────────────────────────────
def airbase():
    """Operational readiness platform. MILITARY family. 48.0 m cell.

    OWNS EXCLUSIVELY: THE PAINTED ASPHALT APRON. A 44 x 40 m sheet of
    near-black tarmac - 1760 m2, of which 1256 m2 is left exposed - the largest
    single-value surface in the game and nine times the exposed area of the
    only other asphalt allowed anywhere in the roster (helipad's 144 m2 pad).
    No other structure may carry a large tarmac plan. The identity is the DARK
    FIELD ITSELF, not the buildings on it, which is why every building is
    pushed onto one edge and the middle two thirds of the cell are left empty.

    WHY THE FIELD IS FRAMED RATHER THAN RUN TO THE CELL EDGE. The mass is
    44 x 40 in a 48 m cell, so apron() leaves a 2.0 m concrete collar all the
    way round. That collar does the job the parapet does for the other six
    military roles. deck concrete 0.098 against track asphalt 0.048 is only
    2:1, but it is a hard geometric edge at a known offset, and it is what
    stops 1760 m2 of near-black from dissolving into terrain shadow. The
    markings are painted in the same concrete, so the whole structure resolves
    in one value pair plus one team band.

    DIMENSIONS AND WHAT THEY ARE BASED ON
        cell            48.0 m       ROSTER (sim_roster.gd "footprint": 48.0)
        asphalt field   44.0 x 40.0 m
        hangars         2 off 18.0 x 14.0 m, eaves 5.40 m, crown 8.40 m
        runway strip    42.0 x 12.0 m, threshold keys at both ends
        control cabin   4.6 x 6.0 m, deck 3.78 m, parapet 4.63 m
        mast head       6.00 m       ROSTER ("mount": 6.0) - the simulation
                                     reads this as the sensor height, so the
                                     model and the sim have to agree on it
    The 44 m of apron is an operational figure, not a composition one: a
    15 m-span fighter needs its own span plus a wingtip margin either side to
    turn on the spot, which puts the number near 44 rather than near 30. The
    18 m hangar bay is the same sum for a parked aircraft - 15 m of span and
    1.5 m of working clearance per side.

    NOT A VEHICLE: no wheels, no tracks, no turret, no barrel, and the plan is
    44 x 40 - 1.1:1, symmetric about X - so it points nowhere. The hangars face
    -Y and say so with two black mouths, which is the only direction cue a
    structure in this module is permitted.
    """
    p = []
    # (1) the concrete collar. apron() first, always.
    p += apron(44.0, 40.0)
    # (2) THE FIELD: 44 x 40 of asphalt, 0.08 m proud of the collar so the
    #     boundary is a real edge for the bevel and the AO bake to bite on.
    use(ASPHALT)
    p.append(cube((0, 0, 0.24), (44.0, 40.0, 0.08)))
    Z = 0.28                                     # top of the asphalt

    # (3) the paint. Runway centred on y = -9.0, 12 m wide, 42 m long.
    lines = []
    for i in range(7):                           # centreline dashes
        lines.append((-18.0 + i * 6.0, -9.0, 4.00, 0.45))
    lines.append((0.0, -14.60, 42.0, 0.35))      # runway edge lines
    lines.append((0.0, -3.40, 42.0, 0.35))
    for s in (-1, 1):                            # threshold keys, both ends
        for k in range(6):
            lines.append((s * 19.4, -14.0 + k * 1.9, 3.60, 0.90))
    lines.append((0.0, 1.30, 0.45, 9.40))        # taxiway centreline
    for s in (-1, 1):                            # hangar lead-in lines
        lines.append((s * 12.5, 4.00, 0.45, 4.00))
    p += markings(Z, lines, group=CONCRETE)

    # (4) the two hangars, along the +Y edge, mouths facing -Y
    p += _arch_hangar(-12.5, 13.0)
    p += _arch_hangar(12.5, 13.0)

    # (5) the control cabin in the 7 m gap between them. Deliberately TINY:
    #     hq owns the framed parapet block and a large one here would read as
    #     an hq at the wrong scale, so this is 4.6 x 6.0 m - smaller than one
    #     hangar mouth - and it carries the mast rather than the read.
    p += _air_shift(box_building(4.6, 6.0, 3.20, z=Z), dy=12.0)
    p += _air_shift(parapet_roof(4.6, 6.0, 3.48, rail=0.85, t=0.30), dy=12.0)
    p += mast(0.0, 12.0, 3.78, 2.02, r=0.12, stays=False, head=(0.90, 0.90, 0.40))
    p += stair(2.90, 12.0, Z, 3.78, w=1.10, facing="y")
    p += stair(-21.30, 13.0, Z, 5.40, w=1.20, facing="y")

    # (6) ownership. team_mark lands on the largest horizontal surface - the
    #     asphalt - against the -Y edge, clear of the runway edge line at
    #     y = -14.60. 43.3 x 4.8 m, 12 percent of the field.
    p += team_mark(44.0, 40.0, Z)

    # top = the hangar eaves, the only real roof line on the structure. The
    # crown is 8.40 m and the mount is the control mast head at the roster's
    # 6.00 m. door_y is the hangar mouth face.
    return p, struct_meta(44.0, 40.0, roof_z=5.40, mount_z=6.00, door_y=5.00)


# ── hardened_shelter ───────────────────────────────────────────────────────
def hardened_shelter():
    """NATO 3rd-generation hardened aircraft shelter. FORTIFICATION family.

    OWNS EXCLUSIVELY: THE CAPSULE. An earth mound that is an OVAL in plan -
    20.0 x 13.2 m - with a concrete portal projecting from its -Y end and one
    black mouth in the end of that portal. It is the only rounded plan outline
    in the roster: coastal_battery's drum is a true circle inside a rectangular
    berm, at a different size and with a different ring around it, and nothing
    else is anything but rectangular. Read from overhead the shelter is a soft
    olive oval with a hard grey tongue and a black slot in it, and that pair of
    shapes belongs to no other role.

    WHY IT IS A MOUND AND NOT A ROOF. The whole identity of a HAS is that it is
    thick and low - it survives what the airbase does not. The fortification
    grammar in this module's header says no roof and no walls, only earth, and
    the mound delivers that literally: three tapered elliptical lifts in olive
    era-group earth (0.219) over a deck-concrete core (0.098), so the plan
    outline and the crown outline are different sizes - 20.0 x 13.2 m at the
    toe against 7.6 x 5.0 m at the crown, four concentric ovals of soft value.
    At 8.50 m to the crown over 13.2 m of depth it is nearly as tall as it is
    deep, which is the proportion that reads as "buried" rather than "built".

    WHY berm() IS NOT USED HERE. berm() lays four straight mitred banks, i.e. a
    RECTANGULAR ring, and fixed_sam, coastal_battery and bunker all wear one.
    Using it would hand back the one thing this role owns - the rounded plan -
    in exchange for a shape three other roles already have. The mound is built
    from tapered cyl() lifts scaled 0.66 in Y instead: same earth material,
    same concentric-contour read, same "plan outline larger than crown outline"
    rule, in an oval. That is a deliberate deviation from the suggested
    construction, made to protect the stated ownership.

    WHY THE PORTAL PROJECTS instead of being a full-width headwall. An oval
    pinches: at the toe (y = -6.20) the mound is only 4.9 m wide, so an 18 m
    headwall standing there would float free of the earth on both sides. The
    real shape is a door frame narrower than the mound that plugs into it, and
    that is what is modelled - a 13.6 m portal from y = -7.0 back to y = -3.8,
    where the mound is 15.4 m wide and swallows it. Two parked door leaves
    flank it, which is where a real HAS's sliding doors go. The portal is held
    at 6.80 m against the mound's 8.50 m crown, and only 2.6 m deep. The first
    version was 7.80 m tall and 4.0 m deep, and its 14.4 x 4.0 m roof read from
    the game camera as a large flat grey TABLE standing in front of a hill
    rather than as a door frame set into a mound - 58 m2 of unbroken up-facing
    concrete against the 1.30 m of mound left showing above it. Cut to 35 m2
    with 1.70 m of mound above, the earth wins the silhouette back.

    DIMENSIONS AND WHAT THEY ARE BASED ON
        cell            24.0 m       mass 20.0 x 14.0 on the 4 m grid
        mound           20.0 x 13.2 m at the toe, crown 8.50 m
        portal          13.6 x 2.6 m, lintel to 6.80 m
        mouth           11.0 x 5.60 m clear
        rear vent       top 6.00 m   ROSTER ("mount": 6.0)
    A NATO TAB-VEE-type third-generation HAS is about 26 x 17 m on plan with
    8-9 m of internal height at the crown and a door aperture in the 22 x 7 m
    class. Compressed onto the 24 m grid cell that is 20 x 14 with an 11 x
    5.6 m mouth: span and depth come down by 23 and 18 percent, the crown is
    HELD at 8.50 m because internal height is the entire point of the role, and
    the mouth is held at 55 percent of the span against the real 60-70.

    NOT A VEHICLE: no wheels, no tracks, no turret, no barrel. It faces -Y and
    says so with a black opening, never with a taper - the mound is symmetric
    about X and widest at mid-depth, so the plan is a capsule and not an
    arrowhead.

    HUMAN SCALE WITHOUT stair(). There is no external staircase, because a HAS
    has no roof to reach and a flight of steps up a blast berm is a thing that
    does not exist. The information stair() exists to carry - "this is 8.5 m,
    not 3 m" - is carried instead by three nested human-referenced heights: a
    2.10 m personnel door in the portal jamb, inside a 6.20 m mouth, inside an
    8.50 m mound. A crown handrail was built and then REMOVED: from the game
    camera 1.05 m of steel posts on the crest read as a cage sitting on a hill,
    it is not a thing a blast mound has, and steel at 0.116 against earth at
    0.219 is a 1.9:1 step that was not paying for the noise it made.
    """
    p = []
    MY = 0.40                      # mound centre in Y, pulled back so the
                                   # portal has clear ground in front of it
    YS = 0.66                      # Y squash: 20.0 m span -> 13.2 m depth
    CROWN = 8.50

    p += apron(20.0, 14.0)         # 24 x 18 concrete slab + kerb

    # THE MOUND. Three tapered lifts; each is a cone of radius r0 -> r1
    # squashed 0.66 in Y, so every contour is an ellipse and the toe, the two
    # shoulders and the crown read from directly overhead as four nested ovals.
    use(EARTH)
    for (z0, h, r0, r1) in ((0.20, 3.00, 10.00, 8.60),
                            (3.20, 2.80, 8.60, 6.60),
                            (6.00, 2.50, 6.60, 3.80)):
        o = cyl((0, MY, z0 + h / 2), r0, h, v=24, taper=r1 / r0)
        o.scale = (1.0, YS, 1.0)
        p.append(o)

    # THE PORTAL. Concrete, because a black opening needs a light surround and
    # the fortification palette has no camo in it: void 0.012 against deck
    # 0.098 is 8:1, which holds at gameplay zoom. Plugged into the mound at
    # y = -3.0, projecting 3.2 m clear of the toe at y = -7.0.
    use(CONCRETE)
    p.append(cube((0, -5.70, 0.20 + 3.30), (13.60, 2.60, 6.60)))
    for s in (-1, 1):              # parked door leaves, flanking the jambs
        p.append(cube((s * 7.40, -5.90, 0.20 + 2.90), (1.40, 2.00, 5.80)))
    # rear blast/exhaust vent: the roster's 6.00 m mount, and a real HAS
    # feature - engine run-up exhaust leaves through the back of the mound.
    # 3.6 x 2.4 m so that it emerges from the rear slope as a HOOD; 2.2 m of it
    # stands clear of the earth. At 1.6 m deep it read as a floating slab.
    p.append(cube((0, 5.80, 0.20 + 2.90), (3.60, 2.40, 5.80)))

    # THE MOUTH. Stands 0.35 m proud of the portal face for the same reason the
    # hangar mouths do: a void buried inside a solid mass is invisible. 5.60 m
    # of black under a 1.00 m concrete lintel - the lintel band is what stops
    # the mouth reading as a black box stuck onto the front.
    p += door(0.0, -7.35, 0.20, 11.00, 5.60, facing="y", depth=1.50)
    p += door(6.85, -4.80, 0.20, 1.00, 2.10, facing="x", depth=0.40)

    p += _air_shift(team_mark(4.60, 3.00, CROWN, frac=0.30), dy=MY)

    return p, struct_meta(20.0, 14.0, roof_z=CROWN, mount_z=6.00, door_y=-7.20)


# ── helipad ────────────────────────────────────────────────────────────────
def helipad():
    """TLOF/FATO pad for a UH-60-class helicopter. MILITARY family. 16.0 m cell.

    OWNS EXCLUSIVELY: THE CIRCLE-AND-H. The only painted circle in the game, on
    a raised square plinth, with four corner light masts and a windsock.

    THE POINT OF THIS ROLE IS THAT IT IS ALMOST NOTHING. A helipad is a pad. It
    has no roof to put a read on, so the plan mark IS the read, and the model
    earns the rest of its legibility from three things that are not shape:
      - VALUE. The 12 m plinth is track asphalt at 0.048 inside a deck concrete
        apron at 0.098 - a dark square in a pale square, the crispest small
        plan available, and the same figure-ground pair as the airbase at a
        twelfth of the area.
      - RELIEF. The plinth stands 0.70 m proud of the apron, so it throws a
        0.55 m shadow at the game's 52 deg camera. That shadow does exactly the
        job parapet_roof() does for the other six military roles: it inks the
        plan outline. A 12 x 12 m paint job on flat ground would have no
        outline at all and would read as a terrain decal, which is the one
        failure mode this role has.
      - VERTICALS. Four 4.00 m light masts at the apron corners and a windsock
        lay five thin shadows across the pale apron and stop the whole thing
        reading as texture. They are also the only silhouette it has from a
        low angle.

    DIMENSIONS AND WHAT THEY ARE BASED ON
        cell            16.0 m
        TLOF plinth     12.0 x 12.0 m, surface 0.90 m
        FATO apron      16.0 x 16.0 m
        aiming circle   8.36 m diameter, 0.55 m band
        touchdown H     3.50 m tall, 0.55 m stroke
        mast head       4.00 m       ROSTER ("mount": 4.0)
    ICAO and NATO minima are expressed as multiples of D, the helicopter's
    overall length with rotors turning. For a UH-60, D = 19.8 m, giving a TLOF
    of at least 0.83 D = 16.4 m and a FATO of at least 1.0 D = 19.8 m. Both are
    larger than the 16 m cell this role can afford, so the pad is DECLARED as
    compressed: the 12 m TLOF is 0.61 D and the 16 m FATO is 0.81 D - a uniform
    0.73 of the real minimum, which keeps the TLOF/FATO ratio at 0.75, exactly
    right, even though the absolute figures are short. The markings are held at
    true proportion to the pad they sit on.

    NOT A VEHICLE: no wheels, no tracks, no turret, no barrel, and the plan is
    a 1:1 square symmetric about both axes. At 0.90 m it is also far too low
    and far too wide to be any vehicle in the game.

    HUMAN SCALE: a three-tread flight up the -Y face of the plinth at the real
    0.233 m rise, and a 2.10 m door on a 2.62 m equipment cabin. Both are under
    the 6 m threshold that mandates stair(), and both are there for the same
    reason - a 12 m square with no human reference on it could be any size.
    """
    p = []
    p += apron(12.0, 12.0)                       # 16 x 16 concrete + kerb
    A = 0.20                                     # apron top
    use(ASPHALT)                                 # THE PLINTH
    p.append(cube((0, 0, A + 0.35), (12.0, 12.0, 0.70)))
    Z = 0.90                                     # pad surface

    # three-tread access flight on the -Y face, inside the 2 m apron band
    use(CONCRETE)
    for i in range(3):
        h = 0.70 * (3 - i) / 3.0
        p.append(cube((0, -6.0 - 0.55 * (i + 0.5), A + h / 2), (4.00, 0.55, h)))

    # THE MARK. Outer edge at r = 4.18 m, which clears the team band starting at
    # y = -4.21 by 0.03 m. The two must not touch, or the circle stops reading
    # as a circle - and the band's position is fixed by team_mark(), so it is
    # the circle that has to give way.
    p += _paint_ring(0.0, 0.0, Z, 4.18, band=0.55)
    use(CONCRETE)                                # the H, on top of the infill
    for s in (-1, 1):
        p.append(cube((s * 1.40, 0, Z + 0.12), (0.55, 3.50, 0.08)))
    p.append(cube((0, 0, Z + 0.12), (2.80, 0.62, 0.08)))

    # four corner light masts. head CENTRE at the roster's 4.00 m mount.
    for sx in (-1, 1):
        for sy in (-1, 1):
            p += mast(sx * 6.90, sy * 6.90, A, 3.60, r=0.11,
                      stays=False, head=(0.45, 0.45, 0.40))
    # windsock: the aviation cue that costs three objects
    p += mast(0.0, 6.90, A, 3.40, r=0.10, stays=False)
    use("body")
    p.append(cyl((0.95, 6.90, 3.55), 0.36, 1.70, rot=(0, R(90), 0), v=8, taper=0.42))

    # equipment cabin - fuel and fire point. The only wall on the structure and
    # the only thing on it that can carry a door.
    p += _air_shift(box_building(1.90, 2.60, 2.62, z=A), dx=7.00)
    p += door(6.05, 0.0, A, 0.95, 2.10, facing="x", depth=0.40)

    p += team_mark(12.0, 12.0, Z)
    return p, struct_meta(12.0, 12.0, roof_z=Z, mount_z=4.00, door_y=-6.00)


# ═══ roster ════════════════════════════════════════════════════════════════
# Model functions land here, one per key in FOOTPRINTS, named
# bld_e<epoch>_<faction>_<key>. Empty on purpose - this module is the contract,
# and the nineteen models are built on top of it.
STRUCTURES = [
    # ── command-economy: the economic spine
    ("bld_e4_us_hq",           hq),
    ("bld_e4_us_power_plant",  power_plant),
    ("bld_e4_us_oil_derrick",  oil_derrick),
    ("bld_e4_us_refinery",     refinery),
    ("bld_e4_us_supply_depot", supply_depot),
    ("bld_e4_us_barracks",          barracks),
    ("bld_e4_us_light_factory",     light_factory),
    ("bld_e4_us_heavy_factory",     heavy_factory),
    ("bld_e4_us_research_facility", research_facility),
    ("bld_e4_us_repair_depot",      repair_depot),
    ("bld_e1_us_naval_yard",      naval_yard),
    ("bld_e2_us_coastal_battery", coastal_battery),
    ("bld_e4_us_fixed_radar", fixed_radar),
    ("bld_e4_us_fixed_sam",   fixed_sam),
    ("bld_e4_us_ew_station",  ew_station),
    ("bld_e4_us_bunker",      bunker),
    ("bld_e4_us_airbase",          airbase),
    ("bld_e4_us_hardened_shelter", hardened_shelter),
    ("bld_e4_us_helipad",          helipad),
]

# ═══ texture requests (2026-08 texture pass) ═══════════════════════════════
# ROSTER DATA, not geometry: these registrations ask hero_models.build() to
# compose per-unit albedos for the body (painted wall) and deck (concrete)
# groups. The brief, in this module's terms:
#   * concrete tonal variation      -> concrete_field + the compose mottle
#   * roof gravel vs wall tone      -> concrete_field's normal/height split;
#                                      gravel ballast on the military and
#                                      industrial roof decks, smooth pour on
#                                      the fortification family
#   * stains under vents            -> ao_grime (grime keyed on the AO bake,
#                                      which is already dark at the base of
#                                      every vent box, duct and parapet) plus
#                                      explicit soot below the named stacks
#   * faction accent on team stripe -> the team group is NOT composed; it
#                                      stays the flat team colour and nothing
#                                      here adds insignia anywhere else.
# All coordinates are build-space metres, copied from the constants in the
# model functions above (stack centres, wall heads, roof decks).
_TEX_GRAVEL = {"military": 0.16, "industrial": 0.13, "fortification": 0.0}


def _tex(name, roof_z, family="military", body_stains=None, deck_stains=None,
         track_stains=None, streaks=True, streak_strength=0.30,
         wall_panels=3.8, deck_panels=4.0):
    weather = dict(
        dust=dict(height=0.9, strength=0.24, tint=(0.34, 0.32, 0.28)),
        ao_grime=dict(strength=0.32, threshold=0.55),
        edge_wear=dict(strength=0.30))
    if streaks:
        weather["streaks"] = dict(z0=roof_z, length=max(roof_z, 3.5),
                                  density=0.30, strength=streak_strength,
                                  tint=(0.21, 0.20, 0.18))
    if body_stains:
        weather["stains"] = body_stains
    deck_weather = dict(
        ao_grime=dict(strength=0.38, threshold=0.60,
                      tint=(0.052, 0.050, 0.046)),
        edge_wear=dict(strength=0.22))
    if deck_stains:
        deck_weather["stains"] = deck_stains
    # ASPHALT (track): the largest truly flat fields left after pass 1 — the
    # airbase apron, the helipad plinth, tarred roof build-ups. Ground-level
    # tarmac stays near the ladder's 0.048 but gains patch-repair mottle;
    # up-facing asphalt above the ground line is a gravel-ballasted built-up
    # roof: lifted and grained, which is the "roof gravel" of the brief in
    # this module's terms. Panel lines are pointless at this value — off.
    track_weather = dict(edge_wear=dict(strength=0.25))
    if track_stains:
        track_weather["stains"] = track_stains
    track_ov = dict(
        panels=None,
        concrete=dict(roof_above=1.5, gravel=0.30, gravel_lift=1.55,
                      wall=0.12, apron=0.30, gravel_scale=0.35,
                      apron_lift=1.30),
        weathering=track_weather)
    # EARTH (era): berms and sandbag rings. Broad banked-soil mottle, dust
    # pooled where the AO is dark, no panel grid — soil has no plates.
    era_ov = dict(
        panels=None,
        concrete=dict(roof_above=0.6, gravel=0.0, wall=0.16, apron=0.16),
        weathering=dict(
            dust=dict(height=1.4, strength=0.30, tint=(0.36, 0.33, 0.26)),
            ao_grime=dict(strength=0.34, threshold=0.55,
                          tint=(0.11, 0.105, 0.085)),
            edge_wear=dict(strength=0.30)))
    H.texture_features(
        name,
        size_class="structure",
        # groups a model does not use are skipped by build(), so the full set
        # is safe to request roster-wide
        groups=("body", "deck", "track", "era"),
        panels=dict(spacing=wall_panels, strength=0.36, jitter=0.10,
                    seams=0.42),
        concrete=dict(roof_above=2.0, gravel=0.0, wall=0.13, apron=0.06),
        weathering=weather,
        groups_override={"deck": dict(
            panels=dict(spacing=deck_panels, strength=0.30, jitter=0.07,
                        seams=0.38),
            concrete=dict(roof_above=2.0, gravel=_TEX_GRAVEL[family],
                          wall=0.13, apron=0.13),
            weathering=deck_weather),
            "track": track_ov, "era": era_ov})


# command-economy spine
_tex("bld_e4_us_hq", 11.5)                       # wall head 11.5, decks above
_tex("bld_e4_us_power_plant", 12.0, family="industrial",
     body_stains=[dict(origin=(-5.0, 5.0, 17.5), direction=(0, 0, -1),
                       length=3.5, width=1.35, strength=0.55),
                  dict(origin=(5.0, 5.0, 17.5), direction=(0, 0, -1),
                       length=3.5, width=1.35, strength=0.55)])  # stack soot
_tex("bld_e4_us_oil_derrick", 3.2, family="industrial", streak_strength=0.24)
_tex("bld_e4_us_refinery", 7.0, family="industrial",
     body_stains=[dict(origin=(2.0, -5.0, 13.4), direction=(0, 0, -1),
                       length=3.0, width=0.95, strength=0.50)])  # heater stack
_tex("bld_e4_us_supply_depot", 5.4, family="industrial", streak_strength=0.22)
# production group
_tex("bld_e4_us_barracks", 8.0, streak_strength=0.24)
_tex("bld_e4_us_light_factory", 8.9, family="industrial",
     body_stains=[dict(origin=(-6.5, 2.0, 9.7), direction=(0, 0, -1),
                       length=2.5, width=0.62, strength=0.50)])  # its one stack
_tex("bld_e4_us_heavy_factory", 12.35, family="industrial")
_tex("bld_e4_us_research_facility", 11.1)
_tex("bld_e4_us_repair_depot", 6.4, family="industrial",
     deck_stains=[dict(origin=(0.0, -7.0, 0.25), direction=(0, -1, -0.05),
                       length=3.5, width=1.6, strength=0.38,
                       tint=(0.045, 0.043, 0.040))])  # oil on the approach
# coastal / defence
_tex("bld_e1_us_naval_yard", 9.2, family="industrial")
_tex("bld_e2_us_coastal_battery", 4.8, family="fortification",
     streak_strength=0.40)
_tex("bld_e4_us_fixed_radar", 4.2)
_tex("bld_e4_us_fixed_sam", 3.8, family="fortification", streak_strength=0.38)
_tex("bld_e4_us_ew_station", 4.2)
_tex("bld_e4_us_bunker", 2.9, family="fortification", streak_strength=0.42)
# air group
_tex("bld_e4_us_airbase", 5.4)
_tex("bld_e4_us_hardened_shelter", 8.5, family="fortification",
     streak_strength=0.38)
_tex("bld_e4_us_helipad", 0.9, streaks=False,
     # rotor-wash dust smear ON THE PAD, which is asphalt (track), not deck —
     # and LIGHTER than the 0.048 tarmac, because a dark stain on near-black
     # is unpaintable
     track_stains=[dict(origin=(0.0, 0.0, 1.05), direction=(0, 1, -0.02),
                        length=4.5, width=1.6, strength=0.45,
                        tint=(0.095, 0.092, 0.084))])


if __name__ == "__main__":
    H.set_out(os.path.join(ROOT, "art", "blockout", "e4_structures"))
    if not STRUCTURES:
        print("structure_models: helpers only, no models registered yet")
        print(f"  {len(FOOTPRINTS)} footprints declared, grid {GRID} m")
        for k, (fp, w, l, _b) in sorted(FOOTPRINTS.items(), key=lambda kv: -kv[1][0]):
            print(f"    {k:20s} {fp:5.1f} m cell   mass {w:.0f} x {l:.0f}")
    for name, fn in STRUCTURES:
        H.CAMO[name] = "camo_us"
        H.TEAM[name] = (0.06, 0.20, 0.62)
        for lod in (0, 1, 2):
            n = H.build(name, fn, lod)
            print(f"  {name:28s} LOD{lod}  {n:6d} tris")
