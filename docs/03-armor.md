# 03 — Armor & Penetration

> Pillar 3: *"the tank and gun also should have generation like 1950s armour is different
> composite armour right now."*

## The design goal

A generational gap must be a **cliff, not a slope.** If a 1955 tank simply does 30% less
damage to a 2015 tank, advancing an epoch is a stat upgrade and nothing more. If a 1955 tank
**physically cannot penetrate** a 2015 tank from the front, but *can* from the side, from
above, or with the right ammunition, then obsolescence changes how you *play* rather than
how much damage you deal.

That is the target: **obsolete units are not weak, they are constrained.** They must flank,
ambush, mass, or fight combined-arms. And flanking requires knowing where the enemy is —
which routes the player straight back into [02](02-detection.md).

## Two numbers, not one

Armor is never a single value. Every armored unit carries a per-facing armor block:

```gdscript
class_name ArmorFacet
@export var armor_type: ArmorType
@export var base_thickness_mm: float   # line-of-sight thickness, after slope
```

with facets for `FRONT_HULL`, `FRONT_TURRET`, `SIDE`, `REAR`, `TOP`, `BELLY`. **Which facet a
round strikes is decided by the impact geometry in [10, §6](10-munitions.md)**, never by a
roll — so the flanking advice below is enforced by where the projectile actually arrives. Penetrators
carry a penetration value expressed in **millimetres of RHA equivalent** — a real engineering
unit, which keeps the numbers meaningful and researchable.

Resolution:

```
effective_mm = base_thickness_mm × effectiveness[armor_type][damage_class]

if penetration_mm > effective_mm → penetrated, apply behind-armor effects
else                             → defeated (spall, crew shock, no kill)
```

## The matrix

The whole system lives in one table. Armor types are not uniformly better — **they are
better against specific threats**, which is what makes ammunition choice matter.

`effectiveness[armor_type][damage_class]`, as a multiplier on base thickness:

| Armor type | Era | vs. **KE** (kinetic) | vs. **CE** (shaped charge) |
|---|---|---|---|
| Cast homogeneous | 1950s | 0.95 | 0.95 |
| RHA (rolled) | 1950s | **1.00** *(baseline)* | **1.00** |
| Spaced | 1960s | 1.10 | 1.60 |
| Siliceous-cored / NERA | 1960s–70s | 1.15 | 1.90 |
| Composite (Chobham class) | 1970s–80s | 1.30 | 2.20 |
| Composite + heavy-metal mesh | late 1980s | 1.60 | 2.60 |
| Light ERA | 1980s | 1.05 | 2.50 *(single-charge only)* |
| Heavy ERA | 1990s+ | 1.25 | 2.80 *(single-charge only)* |
| Modular composite + ERA | 2000s+ | 1.75 | 3.00 |

Read the two columns against each other and the tactical grammar appears:

- **ERA is a specialist.** It nearly triples protection against a shaped charge and does
  almost nothing against a long-rod penetrator. It is also **defeated outright by tandem
  warheads**, whose precursor charge detonates the reactive block before the main jet arrives.
  So ERA is a hard counter to one thing and a hard counter to nothing else.
- **Composite is a generalist**, and it is *better against chemical energy than kinetic*.
  That is why a 1980s MBT's frontal protection is often quoted as ~600 mm against APFSDS but
  ~1300 mm against HEAT.
- **Spaced armor** works by making a shaped charge detonate at the wrong standoff. It barely
  helps against a solid rod.

## Damage classes

| Class | Penetrator | Range behaviour |
|---|---|---|
| **KE** | AP, APCR, APDS, APFSDS | **Falls with range** — velocity bleeds off |
| **CE** | HEAT, tandem HEAT, EFP, RPG | **Flat with range** — chemistry, not velocity |
| **HESH** | Squash head | Flat; defeated entirely by spaced/composite, brutal against RHA |
| **Overmatch** | Very large caliber vs. thin plate | Ignores slope benefits |

The KE/CE range asymmetry is quietly one of the best mechanics available here: **at long
range a HEAT ATGM out-penetrates a tank gun; at short range the tank gun wins decisively.**
Infantry anti-tank teams and missile carriers therefore want distance, and tanks want to
close. That is a real, self-teaching engagement grammar, and it costs one line in the
penetration curve.

## Active protection systems

APS is **not** an armor multiplier. It resolves *before* the armor calculation, as an
intercept roll:

| Type | Epoch | Mechanism | Works against |
|---|---|---|---|
| **Soft-kill** | 1980s+ | Detects the incoming missile, jams its guidance or fires decoys | SACLOS and beam-riding ATGMs. **Nothing unguided.** |
| **Hard-kill** | 2000s+ | Radar detects the round, launches an interceptor | ATGMs, RPGs, some HEAT rounds. **Not APFSDS** — too fast. |

Note what soft-kill APS actually is: **the detection and EW system from [02](02-detection.md),
running at unit scale.** It has a sensor, it produces a track, it jams a guidance link. Same
code, smaller radius. That is the architectural payoff of building the detection solver
generically.

Hard-kill APS carries a **finite interceptor count** and a minimum reset time between
engagements, which makes salvo fire the correct counter — an answer the player can discover
without being told.

## Behind-armor effects — component damage, not hit points

When a penetration succeeds, resolve *what it hit*, not a subtraction from a health bar.
This is more interesting than HP and it feeds directly back into the sensor game:

| Result | Effect |
|---|---|
| **Mobility kill** | Immobilised. Turret still traverses — it is now a pillbox. |
| **Firepower kill** | Mobile but cannot fire. Must withdraw or ram. |
| **Sensor kill** | Optics, thermals or fire-control radar destroyed. **The unit is alive and blind** — it drops to TQ1 and can no longer engage anything at range. |
| **Crew casualties** | Degraded rate of fire, accuracy and reaction time. |
| **Catastrophic** | Ammunition detonation. Total loss. Far likelier without blowout panels — a real generational difference worth modelling. |

**Sensor kill is the most valuable row in this table**, because it links the two big systems:
a tank that survives a hit but loses its thermal sight is a tank that can no longer produce a
fire-control track. Armor and detection stop being separate concerns.

## Guns are launchers; ammunition is the weapon

The table below lists a *representative* gun per generation, but **penetration is a property of
the round, not the tank.** The same 120 mm tube fired ~350 mm rounds in 1979 and ~750 mm rounds
in 2003. Ammunition is an independently upgradeable tech that applies to units already in the
field — see [11, §2](11-generations.md) for the full ladders, and for the reason a carousel
autoloader structurally caps how much penetration a Russian or Chinese tank can ever gain.

## The generational ladder

| Gen | Era | Typical armor | Typical gun & ammunition | Frontal RHAe (KE) | Penetration at 2 km |
|---|---|---|---|---|---|
| **1** | 1950s | Cast / RHA | 90–100 mm, AP / APCR | ~200 mm | ~150–200 mm |
| **2** | 1960s | RHA + spaced, siliceous core | 105 mm rifled, APDS + HEAT | ~250–390 mm | ~250–300 mm |
| **3** | 1970s–80s | Composite | 105 / 120 / 125 mm, early APFSDS | ~350–450 mm | ~350–450 mm |
| **3.5** | late 80s–90s | Composite + heavy metal, ERA | 120 / 125 mm, DU & tungsten long rod | ~550–700 mm | ~500–600 mm |
| **4** | 2000s–10s | Modular composite, heavy ERA, soft-kill APS | Advanced APFSDS, tandem ATGM | ~700–900 mm | ~650–750 mm |
| **5** | 2020s+ | Modular + hard-kill APS, unmanned turret | Programmable ammunition, top-attack | ~900 mm + intercept | ~750 mm + top attack |

## The cliff, worked through

Take a **Gen 1** tank against a **Gen 3.5** tank. The Gen 1 gun penetrates ~180 mm.

| Facing | Gen 3.5 effective armor | Result |
|---|---|---|
| Front turret | ~600 mm | **Cannot penetrate. Not at any range, not ever.** |
| Side hull | ~80–100 mm | **Penetrates** |
| Rear | ~50 mm | **Penetrates easily** |
| Top | ~30–50 mm | **Penetrates easily** |

Because hit location comes from geometry rather than a die roll, that table is not a set of
odds — it is a set of instructions. The Gen 1 tank is not useless; it is *positional*. It must ambush from a flank, or fight
where the modern tank cannot bring its frontal arc to bear, or spot for something that can
kill from above. That is a genuinely different way to play, which is exactly what an epoch
system should deliver.

## Keeping old and cheap units relevant

Two deliberate escape valves stop the generational cliff from collapsing the game into
"newest wins":

**Top attack.** Every tank's roof is thin, in every generation — the weight simply cannot go
there. A modern top-attack ATGM carried by cheap infantry kills any MBT ever built. So
infantry anti-tank remains relevant across all seven epochs, and the enormous investment in
frontal composite is bypassable by design.

**Cost curves.** A Gen 4 MBT should cost several times a Gen 2 one. Massing obsolete armor
must remain a *viable* strategy against a small advanced force, particularly when combined
with the fuel constraints in [04](04-logistics.md) — because a large modern army is also a
large modern fuel problem.

## Ships and aircraft

This model applies to armored vehicles. It does **not** apply to modern warships or aircraft,
which carry negligible armor. Their survivability is the layered soft-kill/hard-kill ladder
in [02, §8.6](02-detection.md) — a sequence of chances to defeat the weapon *before* it
arrives, rather than a chance to survive it on impact. Two different survivability models,
one for each half of the game, and both of them read from the same track table.
