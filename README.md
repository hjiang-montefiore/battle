# Battle

A 3D real-time strategy game spanning **1950 to the present day** — Red Alert 2's legibility
and faction identity crossed with Empire Earth's epoch progression, built on **Godot 4**, and
separated from both by a simulation of how militaries actually find, identify and kill each
other.

**The one-line pitch: an RTS where winning is a sensor problem before it is a firepower problem.**

In Red Alert 2, a unit on screen and in range shoots. Here it may not, because nothing holds a
radar track good enough to guide the weapon, or a jammer broke the track, or the launcher is
under emission control, or the target is below the radar horizon. Conversely a unit may kill
something it cannot see at all, because an AWACS 150 km away is feeding it a track over
datalink. Range stops being a circle around a unit and becomes a property of the whole force's
sensor network.

---

## Status

**Pre-alpha. The art pipeline runs well ahead of the simulation, and that is deliberate.**

| Layer | State |
|---|---|
| Design documentation | 14 documents, complete enough to build against |
| Art pipeline | 186 blockouts across ground and air roles; procedural, no Blender GUI needed |
| Game assets | 126 GLBs imported, ground roles only |
| Godot proving ground | Loads the roster, RTS camera, selection, move orders |
| **Simulation** | **Not built.** `game/sim/` is empty |

What runs today is a **proving ground**, not a game: it verifies that the pipeline's output
loads, sits at the right scale, keeps its sockets, and can be driven with RTS controls. Nothing
shoots, senses, flies or floats yet.

The seven pillars in [docs/01-vision.md](docs/01-vision.md) — radar-cued weapons, jamming,
generational armor, fuel and operational range, airborne early warning, naval ASW, and
munitions simulated from launch to hit — are designed but unimplemented. Build order is in
[docs/06-architecture.md](docs/06-architecture.md).

---

## Running it

Requires **Godot 4.5**. No other dependencies.

```bash
godot --path game                          # play
godot --path game --headless --quit-after 200   # boot and run the self-test
godot --path game -- --shot                # render a framed screenshot of the roster
```

The self-test prints on every boot:

```
[selftest] units spawned      11 / 11
[selftest] scale in range     11 / 11
[selftest] sockets >= 9       11 / 11
[selftest] input map          6 / 6 actions bound
```

**Controls.** `WASD` or screen edge to pan · `Q`/`E` to rotate · wheel to zoom ·
left-click to select · drag to box-select · `shift` to add · right-click to move.

---

## Rebuilding the art

The models are **generated procedurally** — there are no hand-authored `.blend` files. The
blockout writer is pure stdlib; the hero and fleet generators run inside Blender's Python.

```bash
python3 tools/build_assets.py       # blockouts + art/BUILD_REPORT.md
python3 tools/validate_sockets.py   # CI gate: sockets, scale, ground plane
blender --background --python tools/hero_models.py   # detailed hero models
```

> **Note:** the tool scripts currently carry a hardcoded absolute `ROOT` path and will need
> editing to run outside the original author's machine. `validate_sockets.py` also computes
> bounds in local mesh space without composing node transforms, so it reports false failures
> on any model built with node transforms. Both are known and tracked.

---

## Layout

```
docs/     14 design documents — read docs/README.md first
tools/    procedural model generators, glTF writer, socket validator
art/      blockouts, textures, silhouettes, renders, and CONVENTIONS.md
game/     the Godot 4 project
```

**Start with [docs/02-detection.md](docs/02-detection.md).** Four of the seven pillars —
radar-cued weapons, jamming, airborne early warning and naval ASW — are not four systems.
They are one system with four parameter sets, and all four reduce to the same question:
*what does this unit know about that unit, and is that knowledge good enough to shoot?*
It is also the most expensive thing in the design to retrofit, so it gets built first.

Three documents form the combat spine and read as one sentence:

| Document | Question |
|---|---|
| [02 — Detection](docs/02-detection.md) | **May** I shoot? |
| [10 — Munitions](docs/10-munitions.md) | **Does the shot connect?** |
| [03 — Armor](docs/03-armor.md) | **What happens** when it does? |

None of the three resolves anything with a die roll against an accuracy stat. A shot is gated
by track quality, flown as a simulated entity, and resolved against the armor facet the
geometry says it actually hit. Probability of kill is an *outcome*, never an input.

---

## Design constraints worth knowing before contributing

- **The simulation must not know that Godot exists.** No `Node`, no scene tree, no `_process`
  below the presentation line. Godot renders sim state and submits player commands; nothing
  else crosses that boundary.
- **Do not use Godot's physics for units.** Movement, collision and ballistics are
  hand-written — the built-in solvers are neither deterministic nor suited to hundreds of units.
- **Same-machine determinism is kept**, for replays, bug reproduction and AI regression
  testing. No `randf()` outside a seeded stream, no wall-clock reads, no frame-rate-dependent
  logic in the sim.
- **The AI gets no information the player would not have in its position.** Not less cheating —
  none. Enforced architecturally: a track is a hypothesis, not a pointer to an entity.
- **Units are data, not scripts.** Unit definitions reference ladder positions
  (`radar: R3_PULSE_DOPPLER`), never raw numbers, so one tank becomes a different unit in two
  epochs and a designer can retune the game by editing a matrix file.

Art contributions must follow [art/CONVENTIONS.md](art/CONVENTIONS.md) — axes, origin on the
ground plane, metres at 1:1 with the real vehicle, and the socket contract that lets the
upgrade system attach ERA and APS at runtime.

---

## Licence

No licence has been chosen yet, so all rights are reserved by default.
