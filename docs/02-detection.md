# 02 — Detection & Track Model

> **This is the core system.** Pillars 1 (radar-cued weapons), 2 (radar and jamming),
> 5 (airborne early warning) and 6 (naval ASW) are all this document. Build it first.

## The unifying claim

Every one of those four pillars is the same question asked in a different medium:

> What does this unit **know** about that unit, and is that knowledge **good enough to shoot**?

So the engine does not get a radar system, a sonar system, a jamming system and an AWACS
system. It gets **one** detection solver with:

- a **signature** on every unit (how observable it is, per domain),
- a **sensor** list on every unit (what it can observe, per domain),
- a **propagation model** per domain (RF, IR, acoustic, visual),
- a **track** produced per (observer faction, target) pair, carrying a **quality**,
- and a **weapon gate** that compares required quality against available quality.

Radar and sonar differ by *constants and one modifier*, not by code path. An E-3 Sentry is
not a special unit type — it is a radar with a very large `mount_height`, and the horizon
formula does the rest.

---

## 1. Signatures

Every unit carries a signature vector. These are *emissions and reflectivity*, not hit points.

```gdscript
class_name Signature

@export var rcs_m2: float        # radar cross-section, m² — log-distributed
@export var ir_band: float       # infrared intensity, relative units
@export var acoustic_db: float   # radiated noise, dB re 1 µPa (naval only)
@export var visual_m2: float     # optical/EO projected area
@export var magnetic: float      # MAD detectability (submerged hulls)
# emissions[] is NOT authored — it is computed each tick from active sensors,
# jammers, radios and datalinks that are currently radiating.
```

Signatures are **not static**. They are modified at runtime by:

| Modifier | Effect |
|---|---|
| Aspect | Front/side/rear RCS differ, often by 10× on aircraft |
| Throttle | IR scales hard with engine power; afterburner is a flare |
| Speed (naval) | Radiated noise rises steeply with shaft RPM |
| Depth (subs) | Below the thermocline, acoustic detection from above collapses |
| Terrain masking | Line of sight blocked → no RF/IR/visual detection at all |
| Weather | Rain attenuates RF at high bands; cloud kills IR and EO |
| Configuration | External stores wreck an aircraft's RCS; clean beats loaded |

### Reference RCS values

Public approximations, adequate for tuning. The exact numbers matter less than the
**spread** — five orders of magnitude between a bomber and a stealth fighter.

| Class | RCS (m²) |
|---|---|
| Large bomber / airliner | ~100 |
| 4th-gen fighter, loaded | ~10 |
| 4th-gen fighter, clean | ~1–3 |
| Cruise missile | ~0.1 |
| 5th-gen strike fighter | ~0.005 |
| 5th-gen air-superiority fighter | ~0.0001 |

---

## 2. Sensors

```gdscript
class_name Sensor

enum Domain { RF_ACTIVE, RF_PASSIVE, IR, EO, ACOUSTIC_ACTIVE, ACOUSTIC_PASSIVE, MAGNETIC }

@export var domain: Domain
@export var band: Band              # VHF / UHF / L / S / X — see counter-stealth below
@export var reference_range_km: float   # range vs. a 1 m² target, unjammed
@export var mount_height_m: float       # decisive; see the horizon section
@export var fov_deg: float
@export var revisit_seconds: float      # how often it refreshes a track
@export var eccm_rating: int            # 0–5, rises by epoch; offsets jamming
@export var emits: bool                 # if true, using it makes you detectable
@export var max_quality: TrackQuality   # a search radar caps at TRACK, not FIRE_CONTROL
```

`max_quality` is the quiet workhorse of this design. A long-range search radar can *find*
things but never *guide* a missile; that requires a separate fire-control or illuminator
radar. This is why real SAM batteries are multiple vehicles, and it gives the player a real
target priority: **kill the illuminator, not the search radar.**

---

## 3. Propagation — the asymmetry that drives everything

There are two propagation laws in the game, and the difference between them is the single
most important fact in this document.

**Active sensing is two-way.** Energy travels out, reflects, and comes back. Received power
falls as `1/R⁴`. Inverting for range:

```
R_detect  =  reference_range_km × (rcs / 1.0 m²) ^ 0.25
```

**Passive sensing is one-way.** The target's own emission travels to you once. Received
power falls as `1/R²`. Inverting:

```
R_detect  =  reference_range_km × (source_power / reference_power) ^ 0.5
```

### Why this matters

**The fourth root makes stealth dramatic but not magical.** Halving RCS cuts detection range
by only 16% — so incremental stealth is worthless, and only order-of-magnitude reductions
count. Going from a 10 m² fighter to a 0.0001 m² one is a 100,000× reduction, which is a
range factor of `100000^0.25 ≈ 17.8`. A radar that sees the first at 200 km sees the second
at **11 km**. That enormous, physically-derived cliff is exactly the feel stealth should have,
and it arrives for free from one line of math.

**The square root makes radiating dangerous.** Because your own radar's transmission reaches
a passive receiver one-way while its reflection reaches you two-way, **anyone with an ESM
receiver detects your radar long before your radar detects them.** Typically 1.5–3× the range.
This is not a scripted rule or a special ability. It is arithmetic, and it makes emission
control (§7) an agonizing decision without any designer intervention.

---

## 4. The radar horizon — where AEW&C comes from

Radar does not bend around the Earth. Using the standard 4/3-earth approximation, with
heights in metres and range in kilometres:

```
R_horizon  =  4.12 × ( √h_sensor + √h_target )

Effective detection range = min( R_horizon , R_propagation )
```

Run the numbers:

| Sensor | Height | Target | Target ht | Horizon |
|---|---|---|---|---|
| Ground/vehicle radar | 10 m | Sea-skimming missile | 5 m | **22 km** |
| Destroyer mast radar | 30 m | Sea-skimming missile | 5 m | **32 km** |
| Destroyer mast radar | 30 m | Fighter at medium altitude | 6 000 m | **342 km** |
| **E-3 / KJ-500 AEW&C** | **9 000 m** | Sea-skimming missile | 5 m | **400 km** |
| **E-3 / KJ-500 AEW&C** | **9 000 m** | Fighter at medium altitude | 6 000 m | **710 km** |

A ship has **32 kilometres** of warning against a sea-skimming anti-ship missile — at Mach
0.9, about **100 seconds**. Put an AEW aircraft up and that becomes 400 km and 20 minutes.

That is the entire justification for pillar 5, and **it is emergent.** The AEW aircraft gets
no special rule, no "reveals map" ability, no bespoke code. It is a radar mounted 9 km up.
Terrain masking makes the same thing true over land: an airborne sensor sees into valleys
that a hilltop radar cannot.

The corollary is that AEW aircraft become the most valuable targets on the map — which is
historically correct, and which creates the escort/intercept metagame for free.

---

## 5. The track quality ladder

A track is not a boolean. It is a rung on a five-step ladder, and **weapons declare which
rung they need.** This is pillar 1.

| # | Quality | What you have | Typical source |
|---|---|---|---|
| 0 | `NONE` | Nothing | — |
| 1 | `CONTACT` | *Something is there.* Bearing only, no range. Cannot engage; can cue other sensors. | ESM/RWR, passive sonar, VHF radar, MAD |
| 2 | `TRACK` | Position and velocity, refreshed. Can engage with unguided and command weapons. | Search radar, TMA solution, EO |
| 3 | `FIRE_CONTROL` | Continuous high-precision track. Required to launch a guided missile. | Fire-control radar, illuminator, laser designator |
| 4 | `TERMINAL` | The weapon's own seeker has acquired. Launcher is free to break away. | Active seeker in the missile |

Tracks also carry `age`, `confidence`, and `contributing_sources[]`. A track that stops
being refreshed **decays down the ladder** rather than vanishing — FIRE_CONTROL degrades to
TRACK, TRACK to a fading last-known-position marker. Players see a real tactical picture
with stale and uncertain contacts on it, not a binary fog mask.

### 5.1 Classification — a separate axis from track quality

**Knowing where something is and knowing what it is are different problems.** Track quality
answers the first. Classification answers the second, and it has its own ladder:

| Level | You know |
|---|---|
| `UNKNOWN` | Something is there |
| `CATEGORY` | Air / surface / subsurface / ground |
| `CLASS` | Fighter-sized, bomber-sized, vehicle, warship, submarine |
| `TYPE` | The specific model — and therefore its armor, its weapons, its range |
| `IDENTITY` | Friend, hostile, or neutral |

A TQ3 fire-control track on an `UNKNOWN` contact is a perfectly precise solution on something
you cannot name. That is a real situation, and it should be a tense one.

**Classification comes from different sources than position:**

| Source | Gives | Cost |
|---|---|---|
| **IFF interrogation** | `IDENTITY`, instantly | **You must transmit** — see §7.1. Interrogating reveals you |
| **Visual / EO** | Up to `TYPE` | Short range, daylight, weather-dependent |
| **Signature matching** | `CLASS`, sometimes `TYPE` | Needs a good radar and a signature library — a late-epoch capability |
| **Kinematics** | `CLASS` | Free, but coarse. Speed and altitude narrow the possibilities |
| **ESM** | Often straight to **`TYPE`** | Passive, free, long-ranged — see below |

**ESM classification is the inversion worth building the system for.** If you detect a specific
radar emission, you know exactly what platform is carrying it, because only one aircraft in the
world carries that radar. So a *passive* sensor with a poor position solution can deliver
**better classification** than an active one with a perfect solution:

> Your radar says: *precise track, 84 km, bearing 270, unknown.*
> Your ESM says: *bearing 270 ± 4°, and it is an E-3.*

Combine them and you have a fire-control track on a named, prioritised target. That is sensor
fusion earning its keep, and it is another reason radiating is dangerous — **your radar
identifies you to anyone listening.**

**Consequences worth having:**

- **The tactical display shows what is actually known.** `UNKNOWN AIR CONTACT` until classified,
  not a helpfully-labelled enemy unit. This is a UX decision that has to be made deliberately,
  and made the same way for the player and the AI.
- **Decoys work by presenting the right signature.** A decoy that matches a warship's radar
  return classifies as a warship. That is exactly what decoys are for.
- **Engagement rules become a real decision.** *Weapons tight* (engage only `IDENTITY: hostile`)
  is safe and slow. *Weapons free* (engage anything unclassified in a sector) is fast and risks
  fratricide. Giving the player that toggle turns an information problem into a command decision.
- **Classification improves by epoch.** Early epochs have crude IFF, no signature libraries, and
  a great deal of `UNKNOWN`. Late epochs classify automatically and quickly. **The fog gets
  thinner as the timeline advances** — which is a far better epoch reward than a damage bonus,
  and historically exactly right.

Classification is symmetric. The AI gets no more of it than the player does — see
[09, §1](09-ai-and-match-setup.md).

### Weapon gating

```gdscript
enum Guidance {
    UNGUIDED,        # gun, dumb bomb, rocket artillery
    SACLOS,          # wire-guided ATGM, early SAM — operator holds the crosshair
    SARH,            # semi-active radar homing
    ARH,             # active radar homing
    IR_EO,           # heat-seeking or electro-optical
    COMMAND_LINK,    # guided from any networked track source
    GNSS_INS,        # coordinates, not a track
    ANTI_RADIATION,  # homes on the target's own emissions
}
```

| Guidance | To launch | Through flight | Defeated by |
|---|---|---|---|
| `UNGUIDED` | TQ2 vs. a unit; TQ0 to area-fire at a map point | — | Movement, dispersion |
| `SACLOS` | TQ2 | Launcher must hold line of sight | Killing or suppressing the launcher; smoke |
| `SARH` | TQ3 | **Illuminator must hold TQ3 the whole way** | Killing or jamming the illuminator mid-flight |
| `ARH` | TQ3 | Self-promotes to TQ4 at seeker range | Notching, DRFM deception, decoys |
| `IR_EO` | TQ2 + inside seeker range | Seeker holds it | Flares, DIRCM, cloud — **immune to RF jamming** |
| `COMMAND_LINK` | TQ2–3 **from any friendly source** | Datalink must survive | Cutting the datalink; jamming the source |
| `GNSS_INS` | A **location**, no track at all | — | Nothing — but **useless against anything that moves** |
| `ANTI_RADIATION` | Target must be **radiating** | Target must keep radiating (or memory mode) | **Switching the radar off** |

Three of these rows carry most of the game's tactical texture:

**`SARH` punishes commitment.** A 1960s–80s SAM battery must keep its illuminator locked
for the missile's entire flight — a condition re-checked *every tick* by the guidance loop in
[10, §4](10-munitions.md), not just at launch. That illuminator is loudly radiating, which makes it a
beacon for `ANTI_RADIATION` weapons. The classic SEAD duel falls straight out of two table
rows: the SAM must radiate to kill the aircraft, the aircraft's HARM needs it to radiate.
Whoever blinks first loses.

**`COMMAND_LINK` enables cooperative engagement.** A destroyer with every radar switched
off — emitting nothing, invisible to ESM — fires on a track supplied by an E-3 200 km
away. This is real doctrine, it is the single most satisfying thing in this design, and it
requires no new system: it is the faction track database (§6) plus one guidance row.

**`GNSS_INS` is the answer to "what do I do without sensors?"** Coordinate-guided munitions
need no track at all, so they always work against buildings and static defences — and never
against a moving formation. That is a clean, real, easily-taught distinction between striking
infrastructure and fighting an army.

---

## 6. The faction track database

Tracks are stored **per faction, not per unit.**

```
FactionTrackTable
  └─ Track { target_id, quality, position, velocity, age,
             confidence, contributors[], classification }
```

Every sensor on every unit *contributes* observations; the fusion step merges them into one
track per target and takes the best available quality. Every unit *consumes* the table.

This one decision buys, with no further work:

- **Shared situational awareness** — the whole force sees what any one unit sees.
- **Datalink and cooperative engagement** — `COMMAND_LINK` reads the table, so the shooter
  and the sensor need not be the same unit.
- **Sensor fusion by epoch** — early epochs restrict which units can read the table
  (voice reporting, degraded and delayed); later epochs unlock Link-16-style networks where
  everything reads everything instantly. **Networking itself becomes a tech upgrade**, which
  is a far more interesting epoch reward than +10% damage.
- **Meaningful EW targets** — killing the datalink node or jamming the network is an attack
  on the table itself.

Fusion also handles the cueing chain, which is how real air defence works and how the
ladder is meant to be climbed:

```
VHF search radar    →  TQ1 CONTACT   "something low-observable, bearing 270"
        ↓ cues
S-band acquisition  →  TQ2 TRACK     position and velocity
        ↓ cues
X-band illuminator  →  TQ3 FIRE_CTL  weapon release authorised
```

---

## 7. Electronic warfare

### 7.1 Emission control (EMCON)

A per-unit, per-group, player-facing toggle. **This is the primary UI expression of the
whole system** and should be one keypress.

| Mode | Own sensors | ESM detectability | Depends on |
|---|---|---|---|
| `SILENT` | Passive only | Invisible to enemy ESM | The faction track table |
| `RECEIVE` | Passive + intermittent | Brief, hard-to-classify hits | Mixed |
| `RADIATE` | Everything | **Visible at 1.5–3× your own detection range** | Nothing |

The trade is exact and self-explaining: radiate and you see, but you are seen first and
farther. Go silent and you are invisible, but you are blind and dependent on someone else's
picture — which the enemy can attack.

### 7.2 Noise jamming

Raises the victim radar's noise floor, shrinking its detection range against everything in
that sector.

```
R_effective = R_nominal × jam_factor(jammer_power, range, eccm_rating, band_match)
```

Two rules keep it from being an "invulnerability" button:

**Burn-through.** The target's skin return falls as `1/R⁴`; the jammer's signal falls only
as `1/R²`. Closing range therefore favours the radar, and inside the burn-through range the
radar sees straight through the jamming. **Jamming buys distance, not immunity.**

**Home-on-jam.** A noise jammer is a screaming RF beacon. You lose *range* on the target but
gain a *bearing* to it — TQ1, for free, at very long range — and `ANTI_RADIATION` weapons
will fly down that bearing. Jamming announces that you exist while hiding where you are.

### 7.3 Deception jamming (DRFM)

Later-epoch. Instead of noise, it replays modified copies of the radar's own pulse: false
targets, range-gate pull-off, velocity-gate stealing. Effect is on **track quality, not
detection range** — it knocks TQ3 down to TQ2 and breaks missile locks. Harder to detect
than noise jamming and immune to home-on-jam. Countered by high `eccm_rating`, frequency
agility, or by cross-checking against a second sensor in a different domain.

### 7.4 Expendables

One-shot, defeat a track already in progress: **chaff** (RF), **flares** (IR), **towed and
off-board decoys**, **naval soft-kill launchers**, **smoke** (EO/laser, also breaks SACLOS).

These act on **projectiles in flight**, not on a damage number at impact — see
[10, §5](10-munitions.md). And because hard-kill defences must *track* the incoming round,
projectiles are entities in this solver too, with their own small radar cross-sections. A CIWS
is a fire-control radar with a tiny range and a very unforgiving target.

### 7.5 Counter-stealth

Stealth must not be a dead end. Three answers, all epoch-gated:

- **Low-band (VHF/UHF) radar.** Stealth shaping is tuned against centimetric fire-control
  bands and works poorly at metric wavelengths. A VHF radar *detects* a stealth aircraft at
  useful range — but its resolution is far too coarse to guide a missile, so it is capped at
  `max_quality = TRACK`. It tells you something is coming; it cannot shoot it. Exactly the
  right shape for a counter, because it creates a problem rather than solving one.
- **IRST.** Passive infrared. Entirely indifferent to RF stealth, defeats EMCON games,
  but short-ranged and weather-dependent.
- **Multistatic** (late epochs). Transmitter and receiver on separate units. Stealth shaping
  deflects energy *away from the transmitter* — a receiver somewhere else catches it. High
  setup cost, requires an intact datalink, rewards prepared positions.

---

## 8. The acoustic domain — pillar 6

Same solver, same ladder, different constants plus one modifier. Everything below is the
underwater restatement of §3–§7.

| Radar concept | Sonar equivalent |
|---|---|
| Radiating with radar | Active pinging |
| ESM / RWR | Passive sonar |
| Radar horizon | The thermocline / layer |
| Chaff | Acoustic decoy, noisemaker |
| RCS | Radiated noise level |
| EMCON | Ultra-quiet running |

### 8.1 Passive sonar is bearing-only

A single hydrophone array gives **TQ1 — a bearing and nothing else.** Converting that into a
firing solution requires either **target motion analysis** (manoeuvre your own ship and watch
the bearing rate change over minutes) or **two platforms triangulating**. This is why hunting
a submarine is slow, tense, and cooperative, and why a lone destroyer is a poor ASW asset
while a destroyer plus a helicopter is a good one.

### 8.2 Active pinging is the same trap as radar, underwater

Pinging returns TQ2–3 instantly. It also broadcasts your exact position to every submarine
within roughly **twice** your own detection radius — the identical one-way/two-way asymmetry
from §3. A destroyer that pings has announced the hunt. A submarine that hears a ping knows
where the hunter is before the hunter knows anything.

### 8.3 The layer

The thermocline reflects sound. A submarine below the layer is close to undetectable by a
hull-mounted sonar above it. Counters: a **variable-depth sonar** or **towed array** streamed
*below* the layer, or a **dipping sonar** from a helicopter that can place its transducer at
any depth it likes. Depth becomes a real tactical axis rather than a cosmetic one.

### 8.4 Own-noise — the submarine's whole game

Sonar performance scales *inversely* with your own speed, and radiated noise scales *steeply*
with it. Both sides of every underwater engagement therefore face the same dilemma:

> **A ship at flank speed is deaf. A submarine at flank speed is loud.**

A submarine creeping at 5 knots is nearly invisible and nearly immobile. Sprinting to an
intercept makes it detectable. The entire submarine gameplay loop — sprint-and-drift, patience,
positioning hours before the engagement — falls out of one speed-to-noise curve. Towed arrays
add their own constraint: excellent passive range, but only below a speed threshold and not
through hard turns.

### 8.5 ASW toolkit

| Asset | Role | Track quality |
|---|---|---|
| Hull-mounted sonar | Always on, blocked by the layer, own-noise limited | TQ2–3 active |
| Towed array | Long-range passive, below the layer, speed-limited | TQ1–2 |
| Variable-depth sonar | Active below the layer | TQ2–3 |
| Helicopter dipping sonar | Mobile, no own-noise, leapfrogs ahead of the ship | TQ2–3 |
| Sonobuoy field | Cheap wide-area passive barrier, expendable | TQ1 |
| MAD boom | Confirms a datum at very short range | TQ3 |

*Optional flavour, late epochs:* convergence zones — sound refracting back to the surface in
rings at roughly 30–35 nmi intervals, giving occasional long-range contacts. Adds texture;
cut it if it confuses more than it rewards.

### 8.6 The layered naval defence ladder

Modern warships carry almost no armour, so [03](03-armor.md)'s penetration model does not
apply to them. Their survivability is a *sequence of chances to defeat the incoming missile*,
and every rung reads from the detection system:

```
ESM detects the seeker  →  jam / decoy  →  chaff  →  long-range SAM
      →  point-defence SAM  →  CIWS  →  hit
```

Each rung has a probability and a minimum reaction time. **This is why the 32 km horizon in
§4 matters so much:** a sea-skimmer detected at 32 km leaves time for perhaps three rungs; the
same missile detected at 400 km by an AEW aircraft leaves time for all six. An Arleigh Burke
or a Type 055 is expensive precisely because it has more rungs and better ones — and an
AEW aircraft overhead is what converts those rungs into actual engagements.

---

## 9. Implementation notes

**Run the sensor solve on a slow tick.** Detection does not need 60 Hz. **5–10 Hz** is
imperceptible to the player and cuts the cost by an order of magnitude. Movement and
projectiles run at full simulation rate; sensing does not.

**Spatially partition.** The naive solve is `O(sensors × targets)`. A uniform grid or loose
quadtree sized to the largest detection radius makes it near-linear in practice.

**Store hot fields in parallel arrays.** Positions, RCS values and mount heights get swept
every solve; keep them contiguous rather than chasing pointers through scene-tree nodes.

**Radar, ESM and sonar all have generation ladders** in [11](11-generations.md), and two of
their steps are capability cliffs rather than increments: **pulse-Doppler (R3)**, before which
flying low is a *complete* defence against look-down, and **AESA/LPI (R5)**, which partially
defeats the one-way/two-way asymmetry in §3 by letting a radar radiate without lighting up
every ESM receiver in the theatre. The counter is a matching ESM generation, and the two
ladders chase each other across epochs 5–7.

**Precompute per epoch what does not change.** `reference_range × rcs^0.25` for common
(sensor, target-class) pairs is a lookup, not a `pow()` call, and `4.12 × √h_sensor` is
constant per sensor.

**Determinism is non-negotiable.** No `randf()` in the solve without a seeded, replicated
stream; no iteration over unordered containers. See [06](06-architecture.md).

**Make the picture visible.** The entire system is worthless if the player cannot read it.
The tactical display must show: track quality as symbol fill (hollow = CONTACT, solid =
TRACK, boxed = FIRE_CONTROL), **classification as the symbol itself** (§5.1 — an unclassified
contact gets a neutral marker, never a helpfully-labelled enemy unit), track age as fade, own
emissions as a visible radiating ring, and detected enemy emitters as bearing lines. **If the player cannot see why a shot was
refused, the whole design reads as a bug.**
