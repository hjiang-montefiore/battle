# Design Documentation

A 3D real-time strategy game: **Red Alert 2**'s faction identity and readability crossed with
**Empire Earth**'s epoch progression, from the **1950s to the present day**, built on
**Godot 4** — and separated from both by a simulation that models how militaries
actually find, identify, and kill each other.

**One human player against AI opponents**, across **eight factions**, with per-player epoch
start, epoch ceiling and doctrine.

| # | Document | What it settles |
|---|----------|-----------------|
| 01 | [Vision & Pillars](01-vision.md) | What the game is, what it is not, the six pillars |
| 02 | [Detection & Track Model](02-detection.md) | **The core system.** Signatures, sensors, tracks, jamming, EMCON, sonar |
| 03 | [Armor & Penetration](03-armor.md) | Generational armor vs. generational penetrators |
| 04 | [Fuel & Logistics](04-logistics.md) | Operational range, tankers, supply networks |
| 05 | [Epochs](05-epochs.md) | The seven eras and what each unlocks |
| 06 | [Simulation Architecture](06-architecture.md) | Godot 4, determinism, data layout, tick budget |
| 07 | [Art Pipeline](07-art-pipeline.md) | Hero models and derivatives |
| 08 | [Factions](08-factions.md) | Eight factions — US, UK, Germany, France, PLA, Russia, ROC, KPA |
| 09 | [Opponents & Match Setup](09-ai-and-match-setup.md) | AI design, difficulty, epoch start/ceiling, strategy profiles |
| 10 | [Munitions in Flight](10-munitions.md) | Missiles, torpedoes and shells from launch to hit or miss |
| 11 | [Generations](11-generations.md) | **The data spine** — ladders for guns, ammo, radar, AEW, missiles, seekers, sonar |
| 12 | [Unit Roster](12-unit-roster.md) | 86 roles across ground, infantry, air, naval and structures |
| 13 | [How This Compares](13-comparison.md) | Honest positioning against RA2, Empire Earth, Wargame, Command, SupCom |
| 14 | [Animation](14-animation.md) | Vehicles need transforms; infantry need a rig — and one skeleton serves all |

## Read this first

Four of the six realism pillars — radar-cued weapons, jamming, airborne early warning,
and naval anti-submarine warfare — are not four systems. They are one system with four
parameter sets. All four reduce to the same question:

> **What does this unit know about that unit, and is that knowledge good enough to shoot?**

[02-detection.md](02-detection.md) answers that question once. Everything else in this
folder is either an input to it, a consumer of it, or scaffolding around it. Build it
first; it is the most expensive thing here to retrofit.

Three documents form the combat spine, and they read as one sentence:

| Document | Question |
|---|---|
| [02 — Detection](02-detection.md) | **May** I shoot? |
| [10 — Munitions](10-munitions.md) | **Does the shot connect?** |
| [03 — Armor](03-armor.md) | **What happens** when it does? |

None of the three resolves anything with a die roll against an accuracy stat. A shot is gated
by track quality, flown as a simulated entity, and resolved against the armor facet the
geometry says it actually hit.

And because this is a single-player game, one rule in [09](09-ai-and-match-setup.md) is
load-bearing for all of it:

> **The AI has no information the player would not have in its position. Not "less
> cheating" — none.**

An AI with extra information makes every pillar decorative, because nothing the player does to
the enemy's picture would matter. [09, §1](09-ai-and-match-setup.md) sets out the complete
whitelist, the leaks that do not look like leaks, the one architectural rule that enforces it —
**a track is a hypothesis, not a pointer to an entity** — and five tests that catch a leak.
