# 11 — Generations: The Data Spine

> Added 2026-08-25. [05](05-epochs.md) says every epoch must change how something is *played*.
> **This document says what specifically changes.**

## What was missing

The armor ladder in [03](03-armor.md) was built properly. Everything else was prose. That gap
matters, because a design that says "radar improves over time" without a ladder produces a
game where radar is a single number that goes up — which is the thing [05](05-epochs.md)
explicitly forbids.

Every major system family gets its own ladder here: **guns and ammunition, radar, AEW&C,
missiles, seekers, sonar, and submarine quieting.**

---

## 1. The principle: caliber is not power

> **The gun is a launcher. The ammunition is the weapon.**

A 120 mm L/44 smoothbore fired **M829 in 1985 at roughly 500 mm** of penetration, and
**M829A3 in 2003 at roughly 750 mm.** Same tube, same tank, same nominal caliber —
**50% more penetration**, from the round alone.

So the data model separates them:

```gdscript
class_name GunDef
@export var caliber_mm: float
@export var barrel_calibers: int        # L/44 vs L/55 — muzzle velocity
@export var chamber_pressure_class: int
@export var rifled: bool
@export var autoloader: bool
@export var max_projectile_length_mm: float   # ← the sleeper stat; see §2.3
@export var compatible_ammo_families: Array

class_name AmmoDef                       # an INDEPENDENTLY UPGRADEABLE tech item
@export var family: AmmoFamily           # APFSDS_120_NATO, APFSDS_125_SOVIET, …
@export var generation: int
@export var damage_class: DamageClass    # KE / CE / HESH — see 03
@export var penetration_mm_at_2km: float
@export var velocity_decay: Curve        # KE only; CE is flat with range
@export var epoch_available: int
```

**Penetration is a property of the round, modified by the tube** — barrel length and chamber
pressure scale muzzle velocity, which scales kinetic penetration. It is never a property of
"the tank."

### Why this is the most important mechanic in the document

**Ammunition is cheap to upgrade and does not require an epoch advance.** It is the concrete
form of the retrofit pressure valve promised in [05](05-epochs.md):

- A Gen 3 tank firing Gen 5 ammunition is genuinely competitive with a Gen 4 tank firing Gen 3
  ammunition.
- **A unit's combat power is the product of its ladder positions, not its epoch label.**
- Keeping an old platform alive by feeding it new rounds is a real, viable, historically
  accurate strategy — and it is exactly what keeps North Korea ([08](08-factions.md)) playable.

It also means **the same tank in two different epochs is a different unit**, without a single
polygon changing. That is a very large amount of gameplay for very little content.

---

## 2. Guns and ammunition

### 2.1 Tube generations

| Gen | Representative tubes | Era | What changed |
|---|---|---|---|
| **G1** | 90 mm rifled, 100 mm rifled, 20-pounder | 1950s | Baseline. Moderate pressure, rifled |
| **G2** | 105 mm L7 / M68 · 115 mm smoothbore | 1960s | The L7 becomes the Western standard; first smoothbores |
| **G3** | 125 mm autoloaded · 120 mm L/44 · 120 mm rifled | 1970s–80s | Smoothbore dominance; the autoloader/manual split |
| **G4** | 120 mm L/55 · improved 125 mm | 1990s–2000s | Longer tubes, higher velocity |
| **G5** | 120 mm L/55A1 · 130 mm · 140 mm class | 2010s+ | Much higher chamber pressure |

### 2.2 Ammunition ladders — the real numbers

These are the lineages that make the point. All figures are public approximations at ~2 km,
adequate for tuning; the **spread within a single caliber** is what matters.

**120 mm NATO smoothbore APFSDS — one tube, six generations**

| Gen | Round era | Penetration | Note |
|---|---|---|---|
| 1 | 1979 | ~350 mm | First-generation long rod |
| 2 | 1983 | ~430 mm | |
| 3 | 1985–87 | ~470–500 mm | Depleted-uranium variants appear |
| 4 | 1993 | ~560–650 mm | |
| 5 | 1999–2003 | ~700–750 mm | L/55 tube exploits the longer rod |
| 6 | 2015+ | ~800 mm+ | Temperature-independent propellant |

**105 mm NATO rifled — the caliber that refuses to die**

| Gen | Era | Penetration |
|---|---|---|
| 1 | 1960 (APDS) | ~250 mm |
| 2 | 1978 (first APFSDS) | ~350 mm |
| 3 | 1983 (DU) | ~420 mm |
| 4 | 1990 (DU, long rod) | ~500 mm |

> **A 105 mm firing 1990s ammunition out-penetrates a 120 mm firing 1979 ammunition.**
> Caliber is not the ranking. That single fact makes ammunition upgrades feel meaningful and
> makes obsolete platforms worth keeping.

**125 mm Soviet/Russian autoloaded APFSDS**

| Gen | Era | Penetration |
|---|---|---|
| 1 | 1972 | ~350 mm |
| 2 | 1976 | ~400 mm |
| 3 | 1986 | ~450–500 mm |
| 4 | 1991 | ~600 mm |
| 5 | 2005 | ~700 mm |

### 2.3 The autoloader trap — a faction mechanic hiding in a stat

`GunDef.max_projectile_length_mm` looks like bookkeeping. It is not.

**A carousel autoloader physically limits how long a penetrator rod can be**, and kinetic
penetration scales strongly with rod length. So the autoloader that gives Russia and the PLA
their **fast, crew-light, low-profile tanks also caps their penetration growth** — while
manually-loaded Western tanks can keep lengthening the rod.

That is historically accurate, it is a genuine trade rather than a nerf, and it emerges from
one field rather than a special-case rule. It also pairs with the catastrophic-kill exposure
already noted in [03](03-armor.md): the autoloader is fast, compact, length-limited, and
prone to detonating. Four consequences, one design choice.

### 2.4 Shaped-charge and missile warhead generations

| Gen | Era | Penetration (RHA) | Defeated by |
|---|---|---|---|
| **C1** | 1950s–60s | 300–400 mm | Spaced armor |
| **C2** | 1970s | 400–600 mm | Composite |
| **C3** | 1980s | 600–800 mm | **ERA** |
| **C3T** | 1990s | 800–1200 mm | **Tandem — defeats ERA** |
| **C4** | 2000s+ | Top-attack, EFP | Hard-kill APS only |

C3T is the generational answer to the ERA row in [03](03-armor.md)'s matrix, and C4 bypasses
the frontal-armor race entirely by attacking the roof.

---

## 3. Radar generations

| Gen | Era | Technology | Capability | ECCM |
|---|---|---|---|---|
| **R1** | 1950s | Conical scan, mechanical | Range and bearing. **No look-down.** Trivially jammed | 0 |
| **R2** | 1960s | Monopulse | Better angle accuracy; resists conical-scan deception | 1 |
| **R3** | 1970s | **Pulse-Doppler** | **Look-down / shoot-down.** Clutter rejection | 2 |
| **R4** | 1980s | PD + track-while-scan, passive arrays | Many simultaneous tracks | 3 |
| **R5** | 1990s–2000s | **AESA** | Frequency agility, **LPI**, simultaneous modes | 4 |
| **R6** | 2010s+ | GaN AESA, multistatic-capable | Counter-stealth modes, very high resistance | 5 |

### The two cliffs

**R3 — pulse-Doppler and look-down.** Before it, a radar looking down at a low-flying target
sees only ground clutter and nothing else. Which means:

> **Against Gen 1–2 radar, terrain-following flight is effectively invulnerable.**

Flying low is a *complete* defence in epochs 1–2 and merely a good idea from epoch 3 onward.
That is the radar equivalent of the composite-armor cliff, and it is why epoch 3 feels like a
different game in the air.

**R5 — AESA and LPI.** Low-probability-of-intercept waveforms spread emitted energy so that a
passive receiver struggles to detect them. This **partially defeats the one-way/two-way
asymmetry** in [02, §3](02-detection.md): a Gen 5 radar can radiate without lighting up every
ESM receiver in the theatre the way a Gen 3 one does.

That is a genuinely large late-epoch reward, because it changes the EMCON calculus rather than
raising a number. The counter is a matching ESM generation — the ladder in §7 below.

---

## 4. AEW&C generations

| Gen | Era | Class | Horizon | Overland | Controlled engagements |
|---|---|---|---|---|---|
| **A1** | 1950s | Early propeller AEW | Low altitude | **No — clutter** | 1–2 |
| **A2** | 1960s | Improved propeller | Moderate | Poor | 2–4 |
| **A3** | 1977+ | Pulse-Doppler rotodome | ~400 km | **Yes** | ~20 |
| **A4** | 1990s | Upgraded processing + datalink | ~400 km | Yes | ~100 |
| **A5** | 2000s+ | **Fixed AESA arrays** | ~450 km | Yes, with counter-stealth modes | Hundreds |

### Two mechanics worth having

**Early AEW cannot see over land.** Ground clutter swamps a pre-pulse-Doppler radar looking
down. So in epochs 1–2, AEW is a *maritime-only* asset — which makes the epoch 3 unlock feel
enormous, and correctly explains why AEW aircraft became central to air warfare exactly when
they did.

**Controlled engagements scale with generation.** An A1 aircraft can vector one or two
interceptors; an A5 manages the entire air battle. So **AEW generation caps how much of your
air force can act on the shared picture at once** — a hard limit on the cooperative-engagement
play in [02, §6](02-detection.md), rather than an unlimited force multiplier.

That cap is important for balance. Without it, one AEW aircraft makes an entire air force
omniscient in every epoch.

---

## 5. Missile generations

### 5.1 Air-to-air

| Gen | Era | Guidance | Envelope | Typical Pk |
|---|---|---|---|---|
| **M1** | 1950s | Beam-rider, primitive IR | **Rear aspect only**, tiny | ~10% |
| **M2** | 1960s | Early SARH, improved IR | Still rear-aspect IR | ~15–20% |
| **M3** | 1970s | **All-aspect IR**, better SARH | Frontal shots become possible | ~25–35% |
| **M4** | 1980s | Look-down-capable SARH, high-off-boresight IR | Low-altitude targets engageable | ~40–50% |
| **M5** | 1990s | **ARH — fire and forget** | Launcher free to turn away; multi-target | ~50–60% |
| **M6** | 2000s | **Imaging IR** + helmet cueing | Flares stop working; enormous off-boresight | ~60–70% |
| **M7** | 2010s+ | **Dual-pulse / ramjet motors** | **NEZ approaches kinematic range** | ~70%+ |

Three cliffs in that ladder, each of which changes behaviour rather than numbers:

**M3 — all-aspect IR.** Before it, an IR missile can only be fired from behind, so a head-on
merge is *safe*. After it, it is not. That single change rewrites how air combat is flown.

**M5 — active radar homing.** Before it, the launcher is committed for the missile's entire
flight ([10, §4](10-munitions.md)). After it, it fires and leaves. The whole shape of an
engagement changes.

**M7 — dual-pulse and ramjet motors.** This is the direct generational answer to the
no-escape-zone problem in [10, §3](10-munitions.md). A dual-pulse motor saves impulse for the
terminal phase and a ramjet is powered throughout, so the missile arrives with energy instead
of coasting. **The NEZ grows from ~30% of kinematic range toward ~70%**, and "in range" starts
meaning "will hit" again. An enormous late-epoch capability, and entirely legible.

### 5.1b Air-launched weapons — and why the B-52 is the whole argument

Aircraft weapons have their own ladder, and the step that matters is not
penetration or seeker quality. **It is release range** — how far from the target
the aircraft can let go and turn away.

| Gen | Era | Weapon | Release range | What it means tactically |
|---|---|---|---|---|
| **W1** | 1950s | Gravity bombs | **0 km — must overfly** | Enters the *entire* air-defence envelope. Every rung of the layered ladder in [02, §8.6](02-detection.md) gets a shot |
| **W2** | 1960s | Unguided rockets, early guided bombs | ~5 km | Still well inside short-range air defence |
| **W3** | 1970s | Laser-guided bombs | ~10 km | And the aircraft must **hold designation** through the fall — a SACLOS-shaped commitment |
| **W4** | 1980s | Early cruise missiles | ~200 km | The first true standoff. The bomber stops entering the envelope at all |
| **W5** | 1990s | **GNSS/INS glide bombs** | ~28 km | Cheap, all-weather, many per sortie — but needs a *location*, so it is useless against movers ([10](10-munitions.md)) |
| **W6** | 2000s | Standoff cruise missiles | ~370 km | Outside most integrated air defence |
| **W7** | 2010s+ | Extended-range standoff | ~900 km | Outside effectively everything |

**The B-52 spans W1 to W7 on one airframe.** Designed in the early 1950s, still
flying, and its combat power across seven decades came almost entirely from the
weapon ladder rather than the aircraft. In the 1960s it flew over the target and
died to surface-to-air missiles. Today it launches from eight hundred kilometres
away and never enters the threat envelope at all.

That is this document's thesis in its purest form:

> **The aircraft is a launcher. The weapon is the weapon.**
> Exactly as [§1](#1-the-principle-caliber-is-not-power) says of tank guns.

Three consequences the game should take directly:

1. **A bomber's survivability is set by its weapon generation, not its stealth.**
   A W1 bomber must fly into the SAM envelope and will be engaged by every rung.
   A W6 bomber launches from outside and the defender only ever gets to shoot at
   the *missiles*. Same airframe, same radar cross-section, completely different
   outcome — and the player upgrades weapons far more cheaply than airframes.
2. **This makes the non-stealth bomber viable in late epochs**, which matters
   because otherwise stealth trivially obsoletes it. The B-52 and the B-2 solve
   the same problem two different ways: one refuses to enter the envelope, the
   other survives inside it. Both should stay useful to epoch 7.
3. **W5 versus W6 is a real economic choice.** Glide bombs are cheap and carried
   in bulk but require closing to ~28 km; standoff missiles are expensive and
   few but are fired from safety. Cheap-and-close against dear-and-distant is a
   genuine decision every sortie.

**Modelling note:** release range belongs on the *weapon*, and the aircraft
carries a weapon-generation slot like any other ladder position in [§9](#9-how-ladders-relate-to-epochs).
Visually the change is a pylon load — gravity bombs in a bay, or large missiles
hung externally — which is exactly the socketed-attachment pattern in
[07](07-art-pipeline.md).

### 5.2 Surface-to-air

| Gen | Era | Guidance | Simultaneous targets | Mobility |
|---|---|---|---|---|
| **V1** | 1950s | Command / beam-rider | 1 | Fixed site |
| **V2** | 1960s | SARH, continuous illumination | 1 | Relocatable |
| **V3** | 1970s | Improved SARH, some TVM | 2–4 | Mobile |
| **V4** | 1980s | TVM, phased-array cueing | 6–8 | Shoot-on-the-halt |
| **V5** | 1990s–2000s | **ARH terminal** | 12+ | **Shoot on the move** |
| **V6** | 2010s+ | ARH + networked launch | Many, on remote tracks | Fully networked |

The V-ladder is where the SEAD duel of [02, §5](02-detection.md) gets its teeth. **V1–V3 must
illuminate continuously and are therefore anti-radiation bait.** V5 onward can launch on a
remote track and go silent — which is when SEAD stops being a matter of finding the emitter.

### 5.3 Anti-tank guided missiles

| Gen | Era | Guidance | Warhead | Launcher exposure |
|---|---|---|---|---|
| **T1** | 1950s–60s | MCLOS — manual | C1 | **Whole flight, operator flying it** |
| **T2** | 1970s | SACLOS — hold the crosshair | C2 | Whole flight |
| **T3** | 1980s | SACLOS + thermal sight | C3 | Whole flight |
| **T4** | 1990s | Beam-riding / laser | C3T tandem | Whole flight |
| **T5** | 2000s+ | **Fire-and-forget IIR, top attack** | C4 | **None — launch and move** |

T5 is the escape valve that keeps infantry relevant in every epoch, per [03](03-armor.md).

---

## 6. Seekers and countermeasures — the arms race

The flare and chaff rows in [10, §5](10-munitions.md) need parameterising. This is that.

| Gen | IR seeker | Defeated by |
|---|---|---|
| **S1** | Uncooled, rear-aspect | Any flare — also the sun, and clouds |
| **S2** | Cooled, all-aspect | Flares, reliably |
| **S3** | Two-colour / reticle logic | Good flares, well timed |
| **S4** | **Imaging infrared** | Almost nothing short of DIRCM |
| **S5** | IIR + multi-band | DIRCM only |

| Gen | RF seeker / ECCM | Defeated by |
|---|---|---|
| **E1** | Fixed frequency | Any noise jamming |
| **E2** | Frequency-agile | Barrage jamming; DRFM works |
| **E3** | Monopulse + home-on-jam | DRFM |
| **E4** | Anti-DRFM processing | Coordinated multi-axis EW |
| **E5** | Multi-mode (RF + IIR) | Very little |

**The gameplay consequence:** flares are a hard counter in epochs 1–3, a coin flip in 4–5, and
nearly worthless against S4+ seekers from epoch 6. So **countermeasure loadouts have to be
chosen against the era you expect to fight**, and a Gen 2 aircraft's flare dispenser is a
different item from a Gen 6 aircraft's DIRCM turret.

---

## 7. ESM, jamming and sonar

**ESM ladder** (the counter to the R-ladder above):

| Gen | Era | Capability |
|---|---|---|
| **P1** | 1950s | Bare warning — "something is illuminating me" |
| **P2** | 1960s | Bearing and rough band |
| **P3** | 1970s | Bearing + emitter classification against a library |
| **P4** | 1980s–90s | Precise bearing, type ID, threat prioritisation |
| **P5** | 2000s+ | **Detects LPI emissions**; multi-platform triangulation to a firing solution |

P5 is what re-closes the loop after R5's LPI radar opens it. The two ladders chase each other
across epochs 5–7, which is exactly what the real EW contest looks like.

**Sonar ladder:**

| Gen | Era | Capability |
|---|---|---|
| **N1** | 1950s | Hull-mounted active, short range. No towed array |
| **N2** | 1960s | Improved active, first passive arrays |
| **N3** | 1970s | **Towed arrays** — long-range passive, streamed below the layer |
| **N4** | 1980s | Digital processing, better motion analysis, variable-depth sonar |
| **N5** | 1990s–2000s | Multistatic and low-frequency active |
| **N6** | 2010s+ | Distributed and unmanned sensor networks |

**N3 is the cliff.** Before towed arrays, the thermocline in [02, §8.3](02-detection.md) is
close to an *absolute* shield: a submarine below the layer is essentially undetectable. From
epoch 3 it becomes merely a strong advantage.

**Submarine quieting ladder** — the other half of the arms race:

| Gen | Era | Radiated noise |
|---|---|---|
| **Q1** | 1950s | Diesel-electric: quiet on battery, loud snorkelling. **Early nuclear is loud** — reactor pumps |
| **Q2** | 1960s–70s | Raft-mounted machinery |
| **Q3** | 1980s | Anechoic coatings, natural-circulation reactors |
| **Q4** | 1990s+ | Pump-jet propulsors, extensive isolation |
| **Q5** | 2000s+ | **AIP** — near-silent at creep, non-nuclear |

The Q1 row is a genuinely counterintuitive and historically true detail worth keeping: **the
first nuclear submarines were noisier than the diesel boats they replaced.** Faster, longer-
legged, and easier to hear. A real trade in epochs 2–3, and a good lesson in what "newer" buys.

Pair the two ladders and ASW across the timeline is an arms race with real swings, rather than
a slowly rising detection stat.

---

## 8. The cliffs, in one table

Every entry below is a point where a ladder step is **not incremental** — something that was
impossible or safe becomes possible or lethal. These are what an epoch advance actually buys,
and they are the eight moments the game should be built around.

| Ladder | Step | Epoch | Before it | After it |
|---|---|---|---|---|
| Armor | **G3 composite** | 3 | Kinetic rounds penetrate frontally | Old guns cannot penetrate at all |
| Radar | **R3 pulse-Doppler** | 3 | **Flying low is a complete defence** | Look-down / shoot-down |
| AEW&C | **A3 rotodome PD** | 3 | AEW is maritime-only | Overland early warning, ~400 km |
| AAM | **M3 all-aspect IR** | 3 | **A head-on merge is safe** | You can be killed from the front |
| Sonar | **N3 towed array** | 3 | **Below the layer is a shield** | Below the layer is an advantage |
| AAM | **M5 active homing** | 5 | The launcher is committed for the whole flight | Fire and forget |
| Seeker | **S4 imaging IR** | 6 | Flares work | Flares stop working |
| AAM | **M7 dual-pulse / ramjet** | 7 | "In range" is not "will hit" | The NEZ approaches kinematic range |

**Five of the eight land in epoch 3.** That is not an accident of tabulation — the 1970s
genuinely were when sensors took over warfare, and it means **epoch 3 should be the most
dramatic transition in the game.** Plan the pacing, the campaign, and the tutorial around that.

---

## 9. How ladders relate to epochs

Ladders advance **semi-independently**. An epoch advance unlocks a set of steps across many
ladders at once; **retrofits buy a single step on a single ladder** without advancing the epoch.

| Purchase | Cost | Effect |
|---|---|---|
| **Epoch advance** | High, plus time | Unlocks new steps across every ladder; upgrades production lines |
| **Ammunition upgrade** | **Low** | One step on one ammo ladder. **Applies to units already fielded** |
| **Sensor / ECCM retrofit** | Moderate | One step on the radar, ESM or sonar ladder for a unit type |
| **Armor package** | Moderate | ERA or applique on an existing hull — visible on the model, per [07](07-art-pipeline.md) |
| **Seeker upgrade** | Moderate | One step on the seeker ladder for a missile type |

**Ammunition is deliberately the cheapest, and the only one that applies retroactively to units
already in the field.** That is the design's main defence against *newest wins*: a player who
cannot afford to advance an epoch can still afford to keep their guns lethal, and a player one
epoch behind with current ammunition is dangerous rather than helpless.

### Authoring

All of this is data, not code — one file per ladder under `data/matrices/`, and unit definitions
reference *ladder positions* rather than raw numbers:

```
UnitDef "MBT_Gen3_Western"
  gun:        G3_120_L44
  ammo:       ← not fixed. Whatever the owning player has unlocked
  armor:      A_G3_COMPOSITE
  radar:      R3_PULSE_DOPPLER
  fire_ctrl:  F3_TWO_AXIS_STABILISED
```

Which is what makes the same tank a different unit in two different epochs, and what lets a
designer retune the entire game's balance by editing a table.
