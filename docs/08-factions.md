# 08 — Factions

> Roster confirmed 2026-08-25. **Eight factions**, after splitting NATO into its four principal
> national arsenals:
>
> **United States · United Kingdom · Germany · France · China (PLA) · Russia · Taiwan (ROC) · North Korea (KPA)**

## Why split NATO

NATO shares standards — 120 mm smoothbore, STANAG, Link-16 — but the four principal members
field genuinely different hardware built to different doctrines. A single "NATO" faction would
have to average away a rifled gun, an autoloader, a gas turbine, a diesel, four different air
defence philosophies and two different attitudes to depending on somebody else's radar picture.

Splitting them costs almost nothing in art (see [07](07-art-pipeline.md) — they share one parts
library) and buys four distinct playstyles.

It also creates the game's best coalition mechanic, below.

## The eight, in one table

| Faction | Identity | Answer to the sensor question |
|---|---|---|
| **United States** | Full-spectrum, expensive, carrier-centric | *See first, shoot from outside their range* |
| **United Kingdom** | Small, high-quality, escort-and-submarine navy | *Own the air above the fleet, and the water beneath it* |
| **Germany** | Best armor, best fuel economy, no strategic sensors | *Win the ground fight; borrow someone else's picture* |
| **France** | Independent, EW-forward, agile | *Keep my own picture when the coalition's is jammed* |
| **China (PLA)** | Mass with a modern network | *Match their picture, then out-mass them* |
| **Russia** | Denial over discovery | *Don't outsee them — blind them* |
| **Taiwan (ROC)** | Fortified, sensor-rich, no depth | *See everything, survive being seen, beat the clock* |
| **North Korea (KPA)** | Mass, artillery, concealment | *Fight where track quality doesn't matter* |

---

## The Western four

### United States — the benchmark

**Strong epochs 3–6.** Everything, at a price.

| Pillar | Position |
|---|---|
| Radar-cued weapons | Best fire control; earliest active-radar-homing missiles |
| Jamming | Strong offensive EW and anti-radiation weapons — the SEAD specialist |
| Armor | Composite plus heavy-metal mesh, highest frontal protection in the game |
| **Fuel** | **Worst consumption in the game** — gas-turbine MBTs — and the **best aerial refuelling** |
| AEW&C | E-3 and E-2D. First to field it, and keeps a lead through epoch 6 |
| Naval ASW | Best in the game — carrier air wing, Arleigh Burke, nuclear attack submarines |

The US is the reference faction every other one is defined against. Its interesting weakness is
pillar 4: gas-turbine armor plus the longest supply lines make it the thirstiest force in the
game, so a US player who overextends is punished by a mechanic no other Western faction feels
as sharply.

### United Kingdom — quality, and two specialisms

**Strong epochs 2–5.** Small army, exceptional navy.

| Pillar | Position |
|---|---|
| Radar-cued weapons | **Best area air-defence radar in the game** — Sampson-class on the Type 45 |
| Jamming | Moderate |
| Armor | Chobham originated here — and the **only modern rifled main gun**, firing HESH |
| Fuel | Moderate; a dedicated fleet auxiliary for the oiler role |
| AEW&C | **Helicopter-borne, not aircraft-borne** — see below |
| Naval ASW | Excellent — nuclear attack submarines, ASW helicopters, towed arrays |

**The rifled gun is a real trade.** HESH is devastating against rolled homogeneous armor and
structures, and close to useless against composite or spaced arrays — check the HESH row in
[03](03-armor.md). A British tank is exceptional against everything up to Gen 2 and against
buildings and fortifications, and needs its APFSDS rounds against anything modern. That is a
genuinely different ammunition decision from every other Western faction.

**Helicopter AEW is a computable weakness.** British carrier AEW flies at roughly 3 000 m
rather than 9 000 m. Straight into the horizon formula from [02, §4](02-detection.md):

```
4.12 × ( √3000 + √5 )  ≈  235 km      vs.  4.12 × ( √9000 + √5 )  ≈  400 km
```

So the UK gets AEW *anywhere its ships go*, at roughly 60% of the range. Deployable but
shorter-legged — and the difference is derived from the same equation as everything else, not
assigned by a designer.

### Germany — the ground power

**Strong epoch 4.** Superb at the land fight, blind above it.

| Pillar | Position |
|---|---|
| Radar-cued weapons | Strong short-range ground air defence |
| Jamming | Modest |
| Armor | **The Leopard line — the benchmark MBT.** Rheinmetall smoothbore, excellent mobility |
| **Fuel** | **Best efficiency in the game** — diesel powerpacks, short interior lines |
| AEW&C | **None organic.** Depends entirely on the coalition |
| Naval ASW | **Type 212-class AIP submarines** — near-silent, non-nuclear |

Germany is the deliberate inverse of the United States on pillar 4: the Leopard's diesel
powerpack sustains an offensive on a fraction of the fuel an Abrams needs, which makes Germany
the faction that can push furthest from its supply head. Set against that, it has **no organic
AEW at all** — the coalition mechanic below is not a bonus for Germany, it is a dependency.

**AIP submarines are a distinct underwater playstyle.** Air-independent propulsion gives
radiated noise low enough to be nearly undetectable while creeping, with none of a nuclear
boat's reactor pumps — but limited submerged endurance and no sustained high speed. Against the
speed-to-noise curve in [02, §8.4](02-detection.md), a Type 212 is the best ambusher in the game
and the worst pursuer.

### France — the independent

**Strong epochs 5–6.** The faction that does not need the network.

| Pillar | Position |
|---|---|
| Radar-cued weapons | Own AESA radar and own surface-to-air family |
| **Jamming** | **Best integrated self-protection EW suite in the West** |
| Armor | Leclerc-class — **autoloader**, lighter, faster, modular armor blocks |
| Fuel | Moderate, with fully independent logistics |
| AEW&C | **Has its own.** Does not borrow |
| Naval ASW | Nuclear carrier, nuclear attack submarines, potent anti-ship missiles |

France's hook is structural rather than statistical: **it maintains its own datalink and its own
AEW**, so when the coalition's shared track table is jammed or its AEW aircraft is shot down,
France degrades far less than its allies. It is also the only Western faction with an
autoloader — faster sustained fire, smaller crew, and the catastrophic-kill exposure that comes
with carrying ready rounds in the turret.

### The coalition mechanic

When two or more Western factions are allied, they **share one track table** — the Link-16
inheritance, and mechanically just the fusion system in [02, §6](02-detection.md) spanning two
players instead of one.

The interesting part is that they do not benefit equally, and they do not *suffer* equally when
it breaks:

| Faction | Gains from the shared picture | Loses if it is cut |
|---|---|---|
| **Germany** | Enormous — it has no AEW of its own | **Catastrophic** — blind above the treeline |
| **United Kingdom** | Large — extends its 235 km helicopter AEW to 400 km | Significant |
| **United States** | Moderate — it is usually the one *providing* the picture | Moderate |
| **France** | Small — it already has its own | **Minimal** |

So attacking the coalition network is a targeted weapon: kill the American AEW aircraft and the
German player goes blind while the French player barely notices. That asymmetry is not authored
anywhere — it falls out of four factions with different organic sensors sharing one table.

---

## China and Russia — allies until 2000, opposites after

Before roughly 2000, Chinese equipment is Soviet-derived: the same tank lineage, the same
fighters, the same submarines. From the mid-2000s the two diverge, and by epoch 7 they answer
the sensor question in **opposite** ways.

| | **Epochs 1–4** | **Epochs 5–7** |
|---|---|---|
| **PLA** | Soviet-derived hardware, small numbers of it | **Indigenous and networked** — AESA, AEW&C, sensor fusion, long-range fires |
| **Russia** | The originator; strong, modern for its era | **Denial-focused** — jamming, SAM belts, counter-stealth radar, submarines |

That is a genuinely interesting relationship for an epoch-based game: **the two factions are
near-identical early and philosophically opposed late.** A player who has learned to fight one
in epoch 2 has learned almost nothing about fighting the other in epoch 7.

### China (PLA) — the peer

**Strong epochs 6–7. Genuinely weak in 1–3.**

| Pillar | Position |
|---|---|
| Radar-cued weapons | Peer-level from epoch 6; very long-range missile inventory |
| Jamming | Heavy and modern; strong deception jamming from epoch 6 |
| Armor | Composite plus heavy ERA plus hard-kill active protection |
| Fuel | Continental logistics, a growing fleet-oiler force |
| AEW&C | **KJ-2000 and KJ-500.** Arrives late, arrives strong |
| Naval ASW | **Type 055.** Improving steeply through epochs 6–7 |

**Signature mechanic — fires that outrange their own sensors.** The PLA's long-range missiles
reach further than anything it carries organically can see, which makes it the game's premier
`COMMAND_LINK` faction: it must keep an AEW aircraft or forward sensor alive to shoot at maximum
range. That is a real dependency an opponent can attack, and it gives PLA play a distinctive
shape — *protect the sensor, and the missiles reach anywhere.*

### Russia — the denial force

**Strong epochs 2–4.**

| Pillar | Position |
|---|---|
| Radar-cued weapons | Adequate organic sensors; **outstanding ground-based air defence** |
| **Jamming** | **Best in the game.** Heavy ground-based EW; earliest counter-stealth VHF radar |
| Armor | **ERA doctrine** — and autoloaders, so fast fire and a much higher catastrophic-kill rate |
| Fuel | Diesel and continental — noticeably less thirsty than the US |
| AEW&C | Present, consistently a step behind |
| Naval ASW | Submarine-heavy rather than escort-heavy: the hunter, not the hunter-killer |

Russia's answer is inverted from the American one. Rather than building a better picture, it
destroys the enemy's — layered SAM belts that force the anti-radiation-versus-SARH exchange in
[02, §5](02-detection.md), the heaviest jamming in the game, and the only early access to
low-band counter-stealth radar. Its armor matrix row is the ERA one: brilliant against shaped
charges, nearly useless against long rods, defeated by tandem warheads.

---

## Taiwan (ROC) — the fortified defender

**Strong epochs 4–6, always outnumbered.**

| Pillar | Position |
|---|---|
| Radar-cued weapons | **Excellent, and partly free** — mountains give fixed radar sites enormous mount height at no cost. But a fixed site is a pre-surveyed target |
| Jamming | Defensive, modest |
| Armor | Mixed generations in one army — Gen 2 alongside Gen 4, in small numbers |
| **Fuel** | **Imported and finite. This is the faction mechanic** |
| AEW&C | A handful of aircraft; losing one hurts disproportionately |
| Naval ASW | Coastal, mine-heavy, submarine-poor |

### The fuel clock

Taiwan is an island with no domestic oil. In this game that is not flavour, it is a rule:

> **Taiwan begins with a finite fuel stockpile that does not regenerate from territory.**
> It regenerates only from sea lanes, which the enemy can cut.

Every other faction treats fuel as a logistics problem. Taiwan treats it as a *clock*. A ROC
player who turtles indefinitely runs out; a ROC player who protects the sea lanes has committed
naval force away from the coast. That dilemma exists only because pillar 4 exists — the
strongest argument in this design for keeping fuel in the game despite the risk in
[04](04-logistics.md).

**Compensations:** hardened mountain bunkers and hangars, dense coastal anti-ship batteries,
extensive minefields, and the terrain-derived sensor advantage above. Extremely hard to kill
quickly, impossible to sustain forever — a defender's faction with a real deadline.

---

## North Korea (KPA) — the design's stress test

**Strong epochs 1–2, with asymmetric tools in every epoch.**

| Pillar | Position |
|---|---|
| Radar-cued weapons | **Worst in the game.** Obsolete radar, heavy reliance on passive and visual |
| Jamming | Crude but constant — denying the enemy's picture is cheaper than building one |
| Armor | **Gen 1–2 in enormous numbers**, with a thin layer of modern types |
| Fuel | **Chronically short.** Lowest reserves, shortest operational reach |
| AEW&C | Effectively none |
| Naval ASW | Midget submarines — very quiet, very short-ranged, cheap and numerous |

The KPA cannot win the contest this game is built around, so it is designed to **operate where
track quality does not matter**:

- **Massed unguided artillery** — area-fires at a map point at **TQ0**, the one weapon system
  that needs no track at all.
- **Tunnels and hardened underground facilities** — no line of sight means no RF, IR or visual
  detection. The signature model already handles this.
- **Concealment rather than stealth** — dispersal, camouflage, night operations. Different
  mechanism, same column in the signature vector.
- **Midget submarines** — a perfect fit for the speed-to-noise curve, nearly undetectable
  creeping in coastal water.
- **Mass obsolete armor** — exactly what the cost curves and top-attack escape valves in
  [03](03-armor.md) exist to keep viable.

**If North Korea is not viable, the design has a hole.** Every escape valve that stops the game
collapsing into *newest equipment wins* gets exercised at once by this faction. Build it early:
if the KPA cannot win a game, the problem is in [03](03-armor.md), not in the faction.

---

## Theatres

| Theatre | Matchup | Stresses |
|---|---|---|
| **Taiwan Strait** | PLA vs. ROC, US, Japan-adjacent | Naval ASW, AEW&C, anti-ship, the ROC fuel clock — **the only theatre that exercises all six pillars at once** |
| **Korean Peninsula** | KPA vs. US, ROC | Massed artillery, the generational cliff, tunnels, terrain masking |
| **Central Europe** | Russia vs. Germany, US, UK, France | SEAD duels, jamming, ERA vs. APFSDS, the coalition mechanic, ground logistics |
| **North Atlantic** | Russia vs. UK, US, France | Submarine warfare, convoy escort, oiler protection |

Build the **Taiwan Strait** first, for the reason in that first row. **Central Europe** is the
theatre that showcases the NATO split, because all four Western factions appear side by side
with visibly different armor, different fuel behaviour and different dependence on the shared
picture.

---

## Impact on art scope

Eight factions cluster into **three equipment lineages**, not eight national ones:

```
WESTERN            ── US · UK · Germany · France · Taiwan (early, US-derived)
                        └─ shared parts library; UK's rifled gun and France's
                           autoloader are turret swaps, not new lineages

SOVIET / RUSSIAN   ── Russia · North Korea · PLA (epochs 1–4)
                        │
                        └── forks at epoch 5 ──►  CHINESE INDIGENOUS ── PLA (epochs 5–7)
                                                   Taiwan (late, indigenous) sits
                                                   nearer Western
```

The fork is the important structural point: **the PLA changes lineage mid-timeline**, which the
bucket system in [07](07-art-pipeline.md) handles natively — a lineage change is just a new
bucket at a new epoch.

Adding the three extra Western factions is the cheapest possible expansion, because they share
the Western parts library completely: different turrets, different running gear, different
textures, same skeleton and same sockets. Splitting NATO four ways costs roughly **10–15% more
hero models** and roughly doubles the derivative count — and derivatives are assembled, not
sculpted.
