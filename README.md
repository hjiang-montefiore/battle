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
godot --path game                          # play a skirmish
godot --path game res://scenes/proving_ground.tscn   # the art harness
godot --path game --headless --script res://sim/tests/run_sim_tests.gd   # sim tests
godot --path game --headless res://scenes/skirmish.tscn -- --test        # play it headless
godot --path game -- --shot                # render a framed screenshot
```

The main scene is the **skirmish**: two bases at opposite corners of a 12.8 km valley
with a ridge down the middle, one human against one AI. The proving ground is still
there and still runs its own self-test; it is the art harness, not the game.

`-- --test` boots the skirmish headless and plays it — selecting, moving, building,
producing, attacking — then prints what happened:

```
[skirmish] deployed           ok    44 entities
[skirmish] armed              ok    24 of 44 entities carry a weapon
[skirmish] select             ok    14 units selected
[skirmish] move order         ok    mean range to the objective 1156 m -> 84 m
[skirmish] build              ok    power plant 49, 1083 cr spent
[skirmish] produce            ok    tank 53, armed true
[skirmish] combat             ok    747 shots, 43 kills, 134 penetrations
[skirmish] VICTORY   t+765 s
```

**Controls.** `WASD` or screen edge to pan · `Q`/`E` rotate · wheel zoom ·
left-click select · drag box-select · `shift` add · right-click move, or right-click a
contact to attack it · `S` stop · `H` hold fire · `R` radiate / go silent ·
`SPACE` pause · `TAB` speed · `F1` recentre on your base.

**What you see is what you know.** Your own units are drawn from the simulation. The
enemy is drawn from *your* faction's track table and nothing else — a hollow circle is a
contact, a diamond is a track, a filled diamond is a firing solution, and a dashed line
is a bearing with no range in it. A tank behind the ridge is not on your screen because
you do not know it is there. The AI plays under the same restriction.

**Winning.** You win by destroying the enemy's ability to make war: every production
structure and every supply source. An army with neither has two minutes to rebuild or
take ground before it capitulates. There is no mop-up phase.

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
