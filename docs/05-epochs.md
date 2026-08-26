# 05 — Epochs

> Era span **1950 → present**, confirmed 2026-08-25. Seven epochs.

## The Empire Earth inheritance

Advancing an epoch costs time and resources that could have been spent on units *right now*.
That is the whole strategic spine of the game, and it only works if the reward is large
enough to be tempting and slow enough to be dangerous.

The generational cliff in [03](03-armor.md) supplies the temptation: a Gen 3.5 tank is not
20% better than a Gen 1 tank, it is *invulnerable to it frontally*. The cost supplies the
danger: an opponent who spent that time on Gen 2 units instead can be at your base before
your first Gen 3 rolls out.

**Design rule: every epoch must change how something is *played*, not just what its numbers
are.** An epoch that only raises stats is a wasted epoch. Each one below names the mechanic
it introduces.

[11, §8](11-generations.md) tabulates the eight points across all system ladders where a
generational step is a *capability change* rather than an increment. **Five of the eight land
in epoch 3** — flying low stops being a complete defence, a head-on merge stops being safe,
below the thermocline stops being a shield, AEW works overland for the first time, and old
guns stop penetrating composite armor at all. Epoch 3 should be the most dramatic transition
in the game, and the campaign and tutorial should be paced around that.

## The seven epochs

### 1 — Early Cold War · 1950–1959

*Guns, gravity and line of sight.*

Subsonic jets, the first surface-to-air missiles, tanks with cast armor and full-caliber AP.
Radar is enormous, fixed, and easily saturated. Almost no electronic warfare. Submarines are
diesel-electric and must surface or snorkel to charge.

**Introduces:** the baseline. Most weapons are `UNGUIDED`, so track quality barely gates
anything — which is exactly the point. The player learns the game at its simplest, then
watches sensors take over.

### 2 — Missile Age · 1960–1969

*The first time a shot can be refused.*

SARH missiles, layered SAM belts, nuclear submarines, the first jamming pods, APDS and spaced
armor.

**Introduces:** `SARH` guidance, and with it the whole point of [02](02-detection.md). Suddenly
a missile requires a fire-control track *held for the entire flight*, and the SEAD duel begins:
the SAM must radiate to kill, and radiating is what gets it killed. This is the epoch where
the game reveals what it actually is.

### 3 — Precision Dawn · 1970–1979

*Sensors leave the ground.*

Laser-guided bombs, ATGMs, composite armor, look-down/shoot-down radar, and — in 1977 — the
E-3 Sentry.

**Introduces:** **airborne early warning.** The radar horizon in [02, §4](02-detection.md)
stops being a ceiling and becomes something you can buy your way over. Detection ranges jump
by an order of magnitude the moment the first AEW aircraft takes off, and the metagame of
escorting and hunting it begins.

### 4 — Digital · 1980–1989

*Everything gets a computer.*

Pulse-Doppler radar, Aegis-class integrated air defence, APFSDS against composite armor,
soft-kill APS, and the first stealth aircraft.

**Introduces:** **low observability**, and the fourth-root cliff from [02, §3](02-detection.md)
lands with full force. A radar that saw a fighter at 200 km sees the new aircraft at 11 km.
Every air defence the player has built becomes suddenly, alarmingly permeable.

### 5 — Networked · 1990–2004

*The force stops being a collection of units.*

GPS and coordinate-guided munitions, tactical datalink, active radar homing, thermal imaging
everywhere, heavy ERA.

**Introduces:** **the shared picture.** The faction track table in
[02, §6](02-detection.md) goes fully live: cooperative engagement becomes possible, and a
silent destroyer can shoot on an AEW aircraft's track. `ARH` missiles arrive, freeing the
launcher from holding a lock. `GNSS_INS` munitions arrive, making static targets killable
with no sensor at all. **Networking is the epoch reward** — a far better prize than +10% damage.

### 6 — Sensor Fusion · 2005–2015

*Detection becomes the whole contest.*

Fifth-generation stealth aircraft, AESA radar, DRFM deception jamming, hard-kill APS, modern
guided-missile destroyers (Arleigh Burke Flight IIA, Type 052D).

**Introduces:** **deception over denial.** Noise jamming shrinks detection range; DRFM
corrupts track *quality* while remaining hard to detect and immune to home-on-jam. The
counter-stealth toolkit — low-band radar, IRST — arrives alongside, so stealth is contested
rather than dominant.

### 7 — Contested · 2016–present

*Nobody's picture is safe.*

Drones and loitering munitions, hypersonic weapons, Type 055 and modern AEW&C such as the
KJ-500, multistatic radar, heavy electronic attack, top-attack anti-armor everywhere.

**Introduces:** **attrition of the network itself.** Datalinks are jammed, satellites and
nodes are targets, and cheap expendable drones can be spent to make the enemy radiate. The
most advanced epoch is also the least certain — which is a good place for the ladder to end.

## Advancement

| | |
|---|---|
| **Cost** | Resources plus real time. The time is the risk. |
| **Effect** | Unlocks new units; **upgrades existing production lines** in place, Empire Earth style. |
| **Fielded units** | Do **not** retroactively upgrade. Your existing army stays what it was — so the decision has a lasting consequence rather than a temporary one. |
| **Retrofit** | Some upgrades (ERA blocks, ECCM modules, sonar refits) can be bought individually for existing units at a discount. This is the pressure valve that stops an epoch behind from being unrecoverable. |

## Match pacing — a real tension to resolve

**Empire Earth matches are long. Red Alert 2 matches are 15–25 minutes.** Seven epochs will
not fit inside a RA2-length game, and pretending otherwise will produce a game that is neither.

Three modes, rather than one compromise that satisfies nobody:

| Mode | Epochs | Length | Feel |
|---|---|---|---|
| **Skirmish** | Locked to one chosen epoch | 15–25 min | Red Alert 2 pacing, full sensor game, no teching |
| **Campaign / Standard** | Start epoch → +3 | 40–60 min | The intended experience |
| **Epic** | All seven | 90 min+ | The Empire Earth experience |

Skirmish is the important one: it proves the detection model is fun **on its own**, without
the epoch system carrying it. If a single-epoch match is not fun, no amount of teching will
fix it — and that makes Skirmish the first mode to build and the first thing to playtest.

## Modes are just per-player settings

None of the three modes above needs its own code path. Every participant — human and AI — is
configured with a `start_epoch` and a `ceiling_epoch` in
[09, §4](09-ai-and-match-setup.md), and the modes are presets over those two numbers:

| Mode | Expressed as |
|---|---|
| **Skirmish** | Everyone `start = ceiling = N` |
| **Standard** | Everyone `start = N`, `ceiling = N + 3` |
| **Epic** | Everyone `start = 1`, `ceiling = 7` |

Setting them **per player** rather than per match is what turns a mode list into a scenario
system: an obsolete faction with a huge army fighting an advanced one with almost none is just
two different pairs of numbers, not a special case.

Ceilings are **public** — knowing an opponent is capped at epoch 3 turns "survive to epoch 4"
into a legible objective with a visible finish line.
