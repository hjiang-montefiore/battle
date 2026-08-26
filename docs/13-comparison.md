# 13 — How This Compares

> Added 2026-08-25. An honest positioning pass: what has been done before, what has
> been done *better* before, and what is actually new here.

## The short version

> **Command: Modern Operations' sensor model, inside a base-building RTS, spanning
> Empire Earth's epochs.**

That is the pitch, and every third of it already exists separately. The claim is the
combination, not the parts.

## The comparison

| | Base building | Economy | Epoch / tech | **Sensor model** | **EW / jamming** | Armor penetration | Projectile sim | Fuel logistics |
|---|---|---|---|---|---|---|---|---|
| **Red Alert 2** | ✔✔ | ✔✔ | light tree | ✘ | ✘ | rock-paper-scissors | partial | ✘ |
| **Empire Earth** | ✔✔ | ✔✔ | **✔✔✔ 14 epochs** | ✘ | ✘ | ✘ | partial | ✘ |
| **Total Annihilation / BAR** | ✔✔ | ✔✔ | tiers | ✔ coverage circle | ✔ fake blips | HP only | **✔✔** | ✘ |
| **Supreme Commander** | ✔✔ | ✔✔ | ✔ T1–T4 | ✔ radar + sonar + omni | ✔ stealth + jam | HP only | **✔✔** | ✔ aircraft only |
| **Company of Heroes** | light | ✔ | light | ✘ | ✘ | **✔✔ facing + pen** | ✔ | ✘ |
| **Men of War / Gates of Hell** | ✘ | light | ✘ | ✘ | ✘ | **✔✔✔ best in class** | **✔✔✔** | ✔ |
| **Wargame / WARNO** | ✘ deck | points | ✘ | ✔ optics + stealth stat | minimal | ✔✔ AP vs armor | ✔✔ | **✔✔ ammo + fuel** |
| **Command: Modern Operations** | ✘ | ✘ | scenario-set | **✔✔✔ best in class** | **✔✔✔** | n/a | **✔✔✔** | **✔✔✔** |
| **This design** | ✔✔ | ✔✔ | **✔✔ 7 epochs** | **✔✔✔** | **✔✔✔** | ✔✔ | ✔✔ | ✔✔ |

## Where this design is not original

Stated plainly, because pretending otherwise leads to building the wrong things.

**Radar and jamming in an RTS is not new.** *Total Annihilation* had radar coverage and
radar jammers in 1997; *Supreme Commander* had radar, sonar, radar stealth and jamming in
2007. Both are abstract — radar is a circle on the minimap, jamming spawns fake blips —
but the idea is thirty years old and players already understand it.

**Armor penetration is done better elsewhere.** *Men of War* and *Gates of Hell* simulate
individual shells, impact angle, module damage and crew casualties at a fidelity beyond
what [03](03-armor.md) proposes. *Company of Heroes* has had facing-based penetration for
fifteen years. This design's matrix is good; it is not the state of the art.

**Projectile simulation is standard.** *Supreme Commander* and *Total Annihilation*
simulate ballistics fully — shots physically travel and physically miss. [10](10-munitions.md)
is not breaking ground on the concept, only on what the projectile *checks* mid-flight.

**Epoch progression is Empire Earth's, openly.** *Rise of Nations* did it too. Seven epochs
is fewer than Empire Earth's fourteen.

**Fuel logistics exists.** The *Wargame* series has supply trucks carrying both ammunition
and fuel, and forward supply points. [04](04-logistics.md) is a deepening, not an invention.

## Where it is actually new

Five things, and they are all in the same place — the join between the sensor model and
everything else.

**1. Track quality gates weapon release.** No RTS does this. *Command: Modern Operations*
does, and it is not an RTS. In every RTS listed above, a unit in range shoots; the sensor
layer decides *whether you can see the enemy on the minimap*, never *whether your missile
can be guided.* Making the ladder in [02, §5](02-detection.md) the firing condition is
the design's actual contribution.

**2. The propagation asymmetry makes emission control a decision.** Active sensing is
two-way and passive is one-way, so anyone with an ESM receiver detects your radar well
before your radar detects them. No RTS models this. It turns "turn the radar on" into a
real, recurring, agonising choice rather than a passive stat.

**3. Guidance is re-validated in flight.** Kill the illuminator at T+15 s and the missile
in the air goes ballistic ([10, §4](10-munitions.md)). Other RTS games resolve guidance at
launch. This makes the SEAD duel a watchable event rather than a damage exchange.

**4. Epoch steps are capability cliffs, not stat bumps.** The eight cliffs in
[11, §8](11-generations.md) — before pulse-Doppler, flying low is a *complete* defence;
before all-aspect IR, a head-on merge is *safe*; before towed arrays, below the thermocline
is a *shield*. Empire Earth's epochs mostly raised numbers.

**5. An AI held to the player's information in a sensor-heavy game.** Most RTS AI reads
ground truth and is balanced with resource handicaps. [09, §1](09-ai-and-match-setup.md)
forbids both. In a game whose entire subject is *what each side knows*, an omniscient
opponent would make every pillar decorative — so this is a requirement, not a virtue.

## The nearest neighbours, precisely

**Wargame / WARNO** is the closest *playable* comparison — Cold War, real equipment,
line-of-sight combat, supply. The differences: no base building, no tech progression
within a match, and sensors reduced to an optics-versus-stealth stat comparison with no
radar, no track quality, and essentially no electronic warfare. It is also
multiplayer-first, where this is single-player-first.

**Command: Modern Operations** is the closest *simulation* comparison, and it is better at
sensors than this design will ever need to be. The differences: it is a top-down operational
wargame with no base building, no economy, no epoch progression, and a learning curve that
has kept it firmly niche.

**This design sits between them**, which is the opportunity and the risk.

## The risk, named

> **Uncanny valley: too complex for Red Alert 2 players, too simplified for Command players.**

That is the single most likely way this fails, and no amount of feature work fixes it.
Three mitigations, all already in the design:

- **Skirmish mode** ([05](05-epochs.md)) — one epoch, 15–25 minutes, no teching. It exists
  to prove the sensor game is fun *on its own*, at Red Alert 2 pacing.
- **Milestone 4, the tactical display** ([06](06-architecture.md)) — a shot refused for a
  reason the player cannot see is indistinguishable from a bug. Legibility is the feature.
- **The combat log as tutorial** ([10, §10](10-munitions.md)) — *"missed: track was 6 s
  stale"* teaches the thesis through the one channel players actually read.

If those three land, the complexity is *legible* rather than *hidden*, which is the whole
difference between deep and obtuse.
