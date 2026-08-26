# 01 — Vision & Pillars

## The pitch

Red Alert 2 taught a generation what an RTS should *feel* like: legible silhouettes, snappy
counters, a base you can read at a glance. Empire Earth taught the same generation that a
strategy game can span *time* — that the army you build in minute five should look obsolete
by minute forty, and that deciding when to advance is itself the game.

This project takes both, sets them between **1950 and the present day**, and replaces the
arcade combat resolution underneath with a simulation of how modern militaries actually
find, identify, and destroy each other.

It is a **single-player game**: one human against configurable AI opponents, each with its own
faction, epoch start, epoch ceiling and doctrine — see [09](09-ai-and-match-setup.md).

The one-line pitch: **an RTS where winning is a sensor problem before it is a firepower problem.**

## What separates it

In Red Alert 2, if a unit is on screen and in range, it shoots. Fog of war is a binary
visibility mask. That is the assumption this game discards.

Here, a unit that is *within weapons range* may still be unable to fire, because:

- nothing has a **radar track** on the target good enough to guide the weapon;
- the track existed and a **jammer** broke it;
- the launching platform is under **emission control** and refuses to radiate;
- the target is below the **radar horizon** and no airborne sensor is up;
- the contact is a **bearing only** from passive sonar, with no range solution.

Conversely, a unit may kill something it cannot see at all, because a friendly AWACS
150 km away is feeding it a track over datalink. Range stops being a circle around a unit
and becomes a property of the whole force's sensor network.

## The six pillars

These came from the project brief. They are load-bearing, not garnish.

| # | Pillar | Doc |
|---|--------|-----|
| 1 | Missiles, bombs and guns are **cued by radar** — no track, no shot | [02](02-detection.md) |
| 2 | **Radar and jamming** as a first-class electronic-warfare layer | [02](02-detection.md) |
| 3 | **Generational armor and guns** — 1950s steel is not modern composite | [03](03-armor.md) |
| 4 | **Fuel and operational range** for vehicles, ships and aircraft, with oil tankers | [04](04-logistics.md) |
| 5 | **Airborne early warning and jamming** — E-3 Sentry, KJ-500 | [02](02-detection.md) |
| 6 | **Naval ASW** — Arleigh Burke, Type 055, sonar against submarines | [02](02-detection.md) |
| 7 | **Munitions modelled from launch to hit or miss** — missiles, torpedoes, gun rounds | [10](10-munitions.md) |

Eight factions carry them: **US, UK, Germany, France, China (PLA), Russia, Taiwan (ROC), North
Korea (KPA)** — see [08](08-factions.md).

Note what that table shows: **four of the seven pillars resolve to one document.** Pillars 1,
2, 5 and 6 are the same detection-and-track system seen from four angles. That is the
central architectural finding of this design pass, and the reason [02](02-detection.md) is
the longest thing in this folder.

## What this is not

Naming the anti-goals early is cheaper than discovering them in playtest.

**Not a wargame.** No hex grids, no orders phase, no supply-point accounting on a spreadsheet.
The realism buys *interesting decisions*, and any realism that does not buy a decision gets cut.

**Not a fuel-logistics management game.** Pillar 4 is the single highest risk in this design.
Fuel that must be hand-micromanaged will make the game miserable. Fuel is automated by
default (units RTB at bingo, tankers auto-dispatch along a supply network) and the player's
decision is *where the supply lines run and whether to defend them* — not clicking refuel
buttons. See [04](04-logistics.md).

**Not a game of dice.** Probability of kill is an *outcome*, not an input. Every miss has a
reason the player can be told — the missile ran out of energy, the illuminator died mid-flight,
the seeker took a flare, the track was six seconds stale. See [10](10-munitions.md).

**Not a documentary.** Real equipment names and real physics where they make the game better;
invented equipment and abstracted physics wherever the real thing is boring. The radar
equation is in because its fourth-root scaling produces good gameplay. Detailed radar
sidelobe modelling is out because no player will ever perceive it.

**Not asymmetric-by-nation-only.** Nations differ, but the *epoch* is the dominant axis of
difference. A 1965 tank and a 2015 tank should feel like different games. A 1965 American
tank and a 1965 Soviet tank should feel like different flavors.

**Not an AI that cheats.** The opponent has *no information the player would not have in its
position* — not less cheating, none. No unit counts, no economy, no epoch level, no damage
numbers, no production events, no classification it has not earned. Difficulty comes from
doctrine quality alone. See [09, §1](09-ai-and-match-setup.md).

## The core loop

1. **Sense** — decide what to radiate and what to leave silent; place sensors; put an
   AEW aircraft up or don't.
2. **Deny** — jam, kill emitters, stay below the horizon, run quiet.
3. **Engage** — convert a track into a kill, with a weapon whose guidance the track
   actually supports.
4. **Sustain** — keep fuel flowing to the units doing the above.
5. **Advance** — spend time and resources on the next epoch, or spend them on more of
   what you already have.

Step 5 is the Empire Earth inheritance and the strategic spine: **teching up is always in
tension with massing now**, and the generational armor cliff in [03](03-armor.md) is what
gives that tension teeth.
