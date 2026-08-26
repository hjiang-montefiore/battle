# 06 — Simulation Architecture

Engine: **Godot 4**, chosen for a hand-rolled deterministic simulation, no royalties, and
fast iteration. The engine choice matters less than the separation below.

## The one rule

**The simulation must not know that Godot exists.**

Build the sim as a pure, engine-agnostic module: no `Node`, no `Vector3` from the engine, no
scene tree, no `_process`. Godot's job is to *render* the simulation's state and *submit*
player commands to it. Nothing else crosses the line.

```
┌─────────────────────────────────────────────┐
│  SIMULATION  (pure, deterministic, headless) │
│  units · sensors · tracks · weapons · fuel   │
└──────────────┬──────────────────────────────┘
   state ↓            ↑ commands
┌──────────────┴──────────────────────────────┐
│  PRESENTATION  (Godot scene tree)            │
│  meshes · animation · UI · audio · camera    │
└─────────────────────────────────────────────┘
```

This buys four things that are painful to retrofit:

- **Headless tests.** The sensor solver and the penetration matrix are unit-testable without
  launching a renderer — essential, because both are full of numbers that need verifying.
- **Replay and desync detection.** Hash the sim state every N ticks; a replay that diverges
  tells you exactly which tick broke.
- **Lockstep multiplayer**, later, without a rewrite.
- **Engine portability**, if Godot ever stops being the right answer.

## Determinism — reduced, but not abandoned

The game is **single-player** ([09](09-ai-and-match-setup.md)), so there is no second client to
desync from. That relaxes the hardest requirement:

**Fixed-point math is now optional.** Cross-platform bit-identical reproduction was a lockstep
requirement. Floats are acceptable in the sim core, which removes the most intrusive constraint
in this architecture. Keep the fixed-point type behind a compile flag if multiplayer is ever
wanted later — the engine-agnostic boundary above is what keeps that door open.

**Same-machine determinism is still worth keeping**, for three reasons that have nothing to do
with networking: replays, bug reproduction, and **AI regression testing** — you cannot tell
whether an AI change helped if the same match plays differently every run. So:

**Do not use Godot's physics for units.** `RigidBody3D`, `CharacterBody3D` and the built-in
solvers are neither deterministic nor well-suited to hundreds of units. Write your own movement,
collision and ballistics. Godot physics is fine for purely cosmetic debris.

**Never iterate an unordered container.** Dictionary and hash-set iteration order is not
guaranteed. Every loop that touches sim state iterates a sorted array or a stable index.

Also: no `randf()` outside a seeded PRNG stream; no wall-clock time; no frame-rate-dependent
logic anywhere below the presentation line.

## The AI interface

There is exactly one, and it is the same one the player's tactical display uses:

```
FactionTrackTable[ faction_id ]  →  AI
```

The AI may read its own units, its own economy, and its own faction's track table. **It may not
read ground truth.** This is enforced at the module boundary — the AI module simply is not
given a reference to the entity store. See [09, §1](09-ai-and-match-setup.md) for why this is
load-bearing rather than a nicety.

The payoff beyond fairness: with the renderer detached, **AI-versus-AI matches run headless at
many times real speed**, which makes thousands of automated matches a practical way to tune the
armor matrix, epoch costs and unit prices. Run it as a regression suite.

## Tick budget

Three separate rates. Getting this wrong is the most likely performance failure.

| Layer | Rate | Why |
|---|---|---|
| Rendering | Display rate | Interpolated between sim ticks |
| Simulation | **20–30 Hz** | Movement, weapons, projectiles, damage |
| **Sensor solve** | **5–10 Hz** | The expensive one — and imperceptibly slow to a player |
| Munitions, Tier A | Simulation rate | Guided missiles and torpedoes: full guidance loop |
| Munitions, Tier B | **10–15 Hz** | Ballistic rounds; render interpolates between |
| Logistics & AI | **1–2 Hz** | Fuel, supply dispatch, strategic decisions |

The sensor solve is `O(sensors × targets)` in the naive form and it is the single hottest
thing in the game. Running it at 5 Hz instead of 30 Hz is a 6× saving that no player will
ever notice, because a radar's real revisit time is seconds anyway — **the slow tick is more
realistic, not less.**

Stagger sensor updates across ticks (each sensor has a phase offset) so the cost spreads
evenly instead of spiking on one frame.

## Data layout

Units are **not** scene-tree nodes. They are indices into parallel arrays:

```
positions[]      velocities[]     faction[]
rcs[]            mount_height[]   fuel[]
armor_facets[]   sensor_refs[]    emcon_state[]
```

The sensor solve sweeps `positions`, `rcs` and `mount_height` for every candidate pair. Kept
contiguous, that sweep is cache-friendly and vectorisable. Chased through node pointers, it
is not, and the frame budget disappears at a few hundred units.

A `PresentationBinding` maps sim index → Godot node for rendering, and is the *only* place
the two halves touch.

**Spatially partition.** A uniform grid sized to the largest detection radius reduces the
candidate set enormously. Most sensor–target pairs are trivially out of range and should never
be evaluated.

## Language

| Layer | Recommendation |
|---|---|
| Presentation, UI, glue | **GDScript** — fast to iterate, and none of it is hot |
| Simulation core | **C#** to start; **GDExtension (C++ or Rust)** for the sensor solver when profiling says so |

Prototype the whole sim in GDScript first. It will be too slow at scale, and that is fine —
the engine-agnostic boundary above is exactly what makes replacing it a contained job rather
than a rewrite.

## Data-driven content

Seven epochs × several nations × a dozen roles is hundreds of unit definitions. None of them
may be code.

Author units as Godot `Resource` files (`.tres`) or JSON, composed of the building blocks the
other documents define:

```
UnitDef
  ├─ Signature       (rcs, ir, acoustic, visual)      → 02
  ├─ Sensor[]        (domain, band, range, height)    → 02
  ├─ Weapon[]        (guidance, penetration, class)   → 02, 03
  ├─ ArmorFacet[]    (type, thickness, per facing)    → 03
  ├─ FuelTank        (capacity, burn rates)           → 04
  ├─ EpochTag        (generation, availability)       → 05
  └─ LadderRefs      (gun, ammo, radar, seeker, sonar) → 11
```

Unit definitions reference **ladder positions**, never raw numbers — `radar: R3_PULSE_DOPPLER`
rather than `radar_range: 120`. That is what makes the same tank a different unit in two
epochs, and what lets a designer retune the whole game by editing a matrix file.

A designer must be able to add a new tank, ship or aircraft without touching a script. Every
number in documents 02 through 05 lives in these files.

## Module breakdown

```
sim/
  core/         fixed-point math, spatial grid, entity storage, RNG
  sensing/      signatures, propagation, horizon, fusion, track table   ← build first
  ew/           jamming, EMCON, expendables, ECCM
  weapons/      guidance gating, launch solutions, lead computation
  munitions/    projectile entities, flight phases, guidance loop, seekers,
                countermeasures, fuzing, terminal geometry           → 10
  damage/       armor resolution, component damage, APS
  logistics/    fuel, supply routing, tankers
  economy/      resources, production, epoch advancement
  ai/           strategic · operational · tactical layers, doctrine profiles
  setup/        player configuration, epoch start/ceiling, scenario presets
present/
  render/  ui/  audio/  input/  binding/
data/
  units/  epochs/  factions/
  matrices/     armor × penetrator, plus one file per generation ladder → 11
```

## Build order

Deliberately sequenced so the riskiest, most expensive-to-retrofit system is validated first
and the game is playable as early as possible.

| # | Milestone | Proves |
|---|---|---|
| 1 | Deterministic tick loop, fixed-point math, replay hashing | The foundation is sound |
| 2 | **Signatures, sensors, propagation, radar horizon, track table** | **The core system works** |
| 3 | Weapon gating by track quality — two tanks and one radar | Pillar 1 is *legible* to a player |
| 3.5 | **Tier B ballistics** — rounds fly, lead comes from the track, hit a facet | Pillar 7, cheaply — and it makes milestone 3 visible |
| 4 | Tactical display: track symbols, quality, age, emissions | The player can *see* the system |
| 5 | Armor and penetration matrix | Pillar 3 |
| 5.5 | **Tier A missiles** — flight phases, guidance loop, countermeasures, termination causes | Pillar 7 in full |
| 6 | Jamming, EMCON, ESM | Pillar 2 |
| 7 | Fuel and supply, ground only | Pillar 4 |
| 8 | Air layer, AEW&C | Pillar 5 — mostly free once §4 exists |
| 9 | Naval layer, sonar, submarines, oilers, **torpedoes** | Pillars 6 and 7 underwater |
| 10 | Epoch advancement, production, economy | The strategic layer |
| 11 | **AI: tactical layer reading the track table** + the debug view | The opponent is a real participant in the sensor game |
| 12 | AI: operational and strategic layers, doctrine profiles | Opponents that play differently |
| 13 | Match setup — per-player epoch start, ceiling, strategy | The scenario system |
| 14 | Single-epoch **Skirmish** — the real playtest | Whether any of this is fun |
| 15 | Headless AI-vs-AI harness | Balance is testable, not guessed |

**Milestone 4 is the one to be strict about.** A shot refused for a reason the player cannot
see is indistinguishable from a bug. The tactical display is not polish; it is the feature.

**Milestone 11 carries the whole single-player experience.** Build the AI debug view — the AI's
track table rendered beside ground truth — at the same time. It is the cheapest AI development
tool available, and most AI bugs become visually obvious in it.

**Milestone 14 is the honest checkpoint.** If a single-epoch skirmish against a competent AI is
not fun, the epoch system will not save it.
