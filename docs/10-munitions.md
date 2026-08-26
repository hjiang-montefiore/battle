# 10 — Munitions in Flight

> The seventh pillar, added 2026-08-25: *"the missile, torpedo, gun bullets need to be
> modelled carefully from launch, missing/hit."*

## The governing principle

> **Probability of kill is an outcome, not an input.**

Most strategy games resolve a shot with a die roll against an accuracy stat. This one does not.
A projectile is a **simulated entity** that leaves the launcher, flies, guides, runs out of
energy, gets decoyed, gets intercepted — and then hits or misses **for a reason the player can
be told.**

That is the same philosophy as [02](02-detection.md), applied one layer down, and it completes
a three-part statement that the whole design rests on:

| Document | Question it answers |
|---|---|
| [02 — Detection](02-detection.md) | **May** I shoot? |
| **10 — Munitions** *(this document)* | **Does the shot connect?** |
| [03 — Armor](03-armor.md) | **What happens** when it does? |

Every miss should be explainable in one sentence: *fired at maximum range, target turned, the
missile had no energy left.* *The illuminator died four seconds into flight.* *The seeker took
the flare.* A player who understands why they missed will change what they do. A player who
was told "you rolled badly" will not.

---

## 1. Three fidelity tiers

Simulating every round at full fidelity is not affordable and not necessary. Three tiers, by
whether the player can perceive the difference:

| Tier | What | Model | Budget |
|---|---|---|---|
| **A — Fully simulated** | Missiles, torpedoes, ATGMs, guided bombs | Full flight, guidance loop, seeker, countermeasures, terminal geometry | Low hundreds concurrent |
| **B — Ballistic** | Tank rounds, artillery, unguided rockets, autocannon | Full trajectory with gravity and drag; no guidance loop | Thousands |
| **C — Statistical** | Small arms, CIWS bursts, machine guns | Volume-of-fire model, no entities. Tracers are a render effect | Unlimited |

Tier A is where the design lives — those are the weapons players watch, and the ones whose
failure modes are interesting. Tier C exists so nobody spends a frame budget simulating rifle
bullets.

---

## 2. The launch solution — where track quality becomes accuracy

This is the join between this document and [02](02-detection.md), and it is the most important
section here.

**A shooter aims at the track, not at the target.** It has no access to ground truth — it has a
track with a quality, an age, and an error ellipse. So:

```
time_of_flight = estimate(range, munition_profile)
aim_point      = predict(track.position, track.velocity, time_of_flight)
aim_error      = f(track.quality, track.age, target_maneuver, own_stability)
```

### Error sources

| Source | Effect |
|---|---|
| **Track quality** | TQ2 gives a coarse solution; TQ3 a precise one. The ladder is now literally an accuracy ladder |
| **Track age** | A track last refreshed four seconds ago, on a manoeuvring target, is a wide ellipse |
| **Time of flight** | The longer the flight, the more the target can deviate from the prediction |
| **Target manoeuvre** | A jinking target defeats linear prediction; a straight-flying one does not |
| **Own stabilisation** | Firing on the move — see below |

**Range degrades accuracy through prediction error, not through an accuracy-versus-range
table.** Longer shots are worse because there is more time for the world to change between the
solution and the arrival. That is physically honest, it needs no tuning curve, and it means a
long shot at a *stationary* target is still accurate — which is correct, and which most games
get wrong.

### Firing on the move is an epoch-gated capability

Gun stabilisation is one of the cleanest generational mechanics available, and it belongs to
pillar 3 as much as to this document:

| Generation | Firing on the move |
|---|---|
| Gen 1 (1950s) | Effectively impossible. Must halt to shoot |
| Gen 2 | Poor — large dispersion penalty |
| Gen 3 (two-axis stabilisation) | Viable at moderate speed |
| Gen 3.5+ (stabilised sights, ballistic computer, thermal) | Accurate on the move, first-round hit expected |

A 1950s tank that has to stop to shoot is a fundamentally different unit from a 1990s one that
does not — a difference in *behaviour*, not in a damage number, which is exactly what
[05](05-epochs.md) asks each epoch to deliver.

---

## 3. Missile flight — the energy model

A missile is not a dot moving at a constant speed. It has phases, and the phases are where all
the interesting outcomes come from.

```
BOOST      high thrust, high acceleration, short  ─┐
SUSTAIN    lower thrust, some missiles only        ─┤ powered
COAST      no thrust, decelerating on drag        ─┘ ← most of a long-range flight
```

Each Tier A missile carries:

```gdscript
@export var boost_seconds: float
@export var sustain_seconds: float
@export var thrust_profile: Curve
@export var drag_coefficient: float
@export var g_available_max: float     # at optimum speed and altitude
@export var seeker: SeekerDef
@export var fuze: FuzeDef
@export var lethal_radius_m: float
```

### The consequences that matter

**Kinematic range is not the no-escape zone.** A missile fired at maximum range arrives with
almost no energy and can be defeated by a modest turn. The **no-escape zone** — the range
inside which a target cannot out-manoeuvre the missile regardless of what it does — is
typically only **25–40% of maximum kinematic range**.

> *"In range" is not "will hit."* This one fact makes air combat a game about closing to a
> range you can actually kill from, rather than a game about who has the longer stat.

**Until epoch 7.** Dual-pulse and ramjet motors ([11, §5.1](11-generations.md)) save impulse
for the terminal phase or stay powered throughout, growing the no-escape zone from roughly 30%
of kinematic range toward 70%. That is the single largest late-epoch capability in the air
game, and it lands precisely because the player has spent six epochs learning that being in
range was not enough.

**Available g decays.** `g_available` falls as airspeed bleeds off, and falls further at
altitude where there is less air to turn against. A target evades successfully when, at the
terminal moment, its own sustainable g exceeds what the missile has left. As a rule of thumb a
missile needs roughly **three times** the target's g to guarantee an intercept — so a
9 g fighter is safe from a missile down to 27 g, and a long-coasting missile at 10 g is beaten
by a simple hard turn.

**Geometry is worth more than range.** A missile fired high, fast and closing has far more
effective reach than the same missile fired low at a receding target. Altitude and closure
should be visible in the launch UI, because they are the actual decision.

**Notching.** Turning perpendicular to a pulse-Doppler seeker puts closure rate near zero,
where the seeker's own clutter filter discards the return. A real, learnable, geometry-based
defence rather than a stat check — and one that later seeker generations partially defeat.

### Guidance law

Proportional navigation: the missile turns at a rate proportional to the rotation rate of the
line of sight to the target, with a navigation constant around 3–5. It is a few lines of code,
it is what real missiles do, and it produces the correct lead-pursuit curve — which means the
*shape of the missile's flight path* tells an observant player what kind of guidance it is
using.

---

## 4. The guidance loop — checked every tick, not just at launch

This is where the promises made in [02, §5](02-detection.md) are actually kept. Every tick,
each Tier A projectile re-validates its guidance:

| Guidance | Checked in flight | Fails when |
|---|---|---|
| `SARH` | **Illuminator still holds TQ3 on the target?** | Illuminator destroyed, jammed, or loses lock → **missile goes ballistic mid-flight** |
| `ARH` | Inertial or datalink mid-course, then **seeker activates** at a range threshold → TQ4 | Notched, decoyed, or the target leaves the seeker basket before activation |
| `COMMAND_LINK` | Datalink alive; track still in the faction table | Link jammed, or the contributing sensor dies |
| `IR_EO` | Seeker holds the hottest source in its field of view | A flare is hotter — unless the seeker generation defeats flares |
| `SACLOS` | Launcher holds line of sight, **for the whole flight** | Launcher suppressed, killed, or breaks LOS; smoke |
| `GNSS_INS` | Satellite fix present | GPS jamming → degrades to inertial drift, error grows with flight time |
| `ANTI_RADIATION` | Target still radiating | **Radar switched off** — unless the seeker has memory mode |

**The SARH row is the one that pays off the most.** A Cold War SAM engagement now has a real,
watchable duration: the missile is in the air for twenty seconds, the illuminator must keep
radiating for all twenty, and an anti-radiation missile inbound on that illuminator is a race
the player can see and act on. Killing the illuminator at second fifteen makes the SAM miss —
not because a rule says so, but because the guidance check failed on that tick.

---

## 5. Countermeasures act on the projectile, not on the damage number

Countermeasures are **events that happen to an entity in flight**, never a percentage reduction
applied at impact.

| Countermeasure | Acts on | Mechanism |
|---|---|---|
| **Chaff** | RF seekers | False return; seeker may transfer lock. Beaten by later seeker generations and by aspect |
| **Flares** | IR seekers | **Hard counter in epochs 1–3, a coin flip in 4–5, near-worthless against imaging seekers from epoch 6** — see the seeker ladder in [11, §6](11-generations.md) |
| **DRFM jamming** | RF seekers | Breaks or walks the lock off the target |
| **Naval decoys** | Anti-ship seekers | Seduce the seeker off-axis onto a false ship-sized return |
| **Noisemakers** | Torpedo sonar | Same trick, underwater |
| **Hard-kill APS / CIWS** | Anything | **Physically destroys the projectile in flight** |
| **Notching, terrain masking** | RF seekers | Breaks the guidance geometry outright |

**Hard-kill defences need their own track on the incoming round** — which means projectiles
are entities in the detection solver from [02](02-detection.md) too, with their own (very
small) radar cross-section and their own very short engagement timeline. No new system: a CIWS
is a fire-control radar with a tiny range, a fast reaction time, and a very unforgiving target.

This is also why the layered naval defence ladder in [02, §8.6](02-detection.md) works the way
it does — each rung is one more opportunity to act on an entity that is genuinely in flight for
a genuine number of seconds.

---

## 6. Terminal — miss distance, fuzing, and where it lands

**Compute the miss distance at closest approach.** Then:

| Fuze | Behaviour |
|---|---|
| **Contact** | Must physically strike. Miss distance > 0 means a clean miss |
| **Proximity** | Detonates within `lethal_radius`; **damage scales down with miss distance** |
| **Delayed / penetrating** | Strikes, penetrates, then detonates inside |
| **Airburst / programmable** | Detonates at a computed point — later epochs only |

Proximity fuzing means a **near miss is a real outcome**, not a binary. A SAM that detonates
fifteen metres from an aircraft damages it; one that detonates at three metres destroys it.
Aircraft limp home. That is far better than hit-or-nothing, and it produces the wounded-and-
withdrawing units that make a battle feel like a battle.

### Hit location is geometry, not a roll

When a projectile connects, **the impact vector against the target's orientation determines
which armor facet it hits** — and that facet goes straight into the resolution in
[03](03-armor.md).

| Approach | Facet |
|---|---|
| Frontal engagement | `FRONT_HULL` / `FRONT_TURRET` |
| Flanking shot | `SIDE` |
| Ambush from behind | `REAR` |
| Top-attack missile, plunging artillery | `TOP` |
| Mine, bomblet | `BELLY` |

So the tactical advice in [03](03-armor.md) — *the obsolete tank must flank* — is not a
suggestion the AI or the player is trusted to follow. **It is enforced by the geometry of where
the round actually arrives.** Flank successfully and you hit the side; fail and you hit the
front and bounce.

---

## 7. Torpedoes — the slow-motion case

Torpedoes are the most interesting projectiles in the game, for one reason: **they are slow.**
A torpedo run takes minutes, not seconds, and everything follows from that.

**The target can react.** There is time to turn away, deploy noisemakers, launch a
counter-torpedo, and fire back down the bearing the torpedo came from. A torpedo launch starts a
conversation, not an outcome.

**Wire guidance is an enormous commitment.** The submarine steers the torpedo down a physical
wire — but to keep the wire intact it must stay slow and hold course for the entire run. So the
launcher is **constrained and vulnerable for minutes**, exactly the same shape as `SACLOS`, at a
much greater cost. Cutting the wire (by manoeuvring, or by the submarine being forced to evade)
drops the torpedo to its own seeker.

**Firing is loud.** A torpedo launch is a detectable acoustic event. Shooting reveals you — the
same emitter logic as radar and active sonar, one more time.

| Torpedo type | Behaviour |
|---|---|
| **Wire-guided** | Best accuracy, launcher constrained for the whole run |
| **Passive homing** | Listens for the target; defeated by a quiet target and by noisemakers |
| **Active homing** | Pings — **and announces itself to the target** |
| **Wake-homing** | Follows the target's wake. Very hard to decoy. Surface ships only |

**Torpedoes have their own fuel and their own speed/range trade** — a heavyweight torpedo runs
far at low speed or much less far at high speed. Pillar 4, at projectile scale. A ship with
enough speed and enough head start can genuinely **outrun** a torpedo, which turns "torpedo in
the water" into a chase rather than a verdict.

---

## 8. Gun rounds and artillery — Tier B

**Tank rounds** fly a flat, fast arc: roughly 1.3 seconds to 2 km at typical modern muzzle
velocities. Short, but not zero — a moving target *can* be missed by a bad lead, and the lead
came from the track. Dispersion is a cone driven by stabilisation generation, barrel wear and
crew quality.

**Artillery flies for 30 to 90 seconds**, and that long flight time produces the best mechanic
in this section:

> **Counter-battery radar observes shells in flight and extrapolates the trajectory backward to
> the firing position.**

That is the detection system from [02](02-detection.md) operating on Tier B projectiles, and it
gives artillery a genuine risk/reward loop: firing produces a track *on you*, so a gun that
shoots and stays is a gun that dies. **Shoot-and-scoot becomes a real, necessary behaviour**,
and self-propelled artillery becomes meaningfully better than towed — for a reason the player
can watch happen.

It also gives the KPA of [08](08-factions.md) its central tension: massed artillery is the one
weapon system that needs no track at all, but firing it *creates* one.

---

## 9. Performance

| Tier | Tick | Notes |
|---|---|---|
| **A** | Simulation rate, 20–30 Hz | Full guidance loop. Cap concurrent count; queue launches if exceeded |
| **B** | 10–15 Hz with render interpolation | Ballistic integration only — no per-tick decisions |
| **C** | Resolved statistically | No entities at all |

Projectiles must be **inserted into the spatial grid**, because hard-kill defences query for
them exactly as sensors query for units. Tier A projectiles also need a small radar
cross-section so they are findable — a sea-skimming anti-ship missile is a legitimate target
for the entire defence ladder.

**Pool and reuse projectile entities.** Allocation churn during a saturation attack is a
frame-rate cliff, and saturation attacks are precisely when the game is at its most exciting.

---

## 10. Telling the player why

The design principle at the top only works if the reason reaches the player. Every Tier A
projectile carries a **termination cause**, surfaced in the combat log and on the unit card:

```
HIT           · penetrated SIDE, mobility kill
NEAR MISS     · proximity fuze at 14 m — damaged
DEFEATED      · seeker took a flare
DEFEATED      · intercepted by hard-kill APS
DEFEATED      · illuminator destroyed at T+15 s — went ballistic
DEFEATED      · notched, seeker lost track
MISSED        · out of energy, target out-turned it at 8 g
MISSED        · aim error — track was 6 s stale
```

**That log is the tutorial.** A player who reads *"missed — track was 6 s stale"* three times
learns, without being taught, that a fresh fire-control track is worth more than a longer-ranged
missile. Which is the entire thesis of this design, arriving through the one channel players
actually read.

## Build order impact

This slots into [06](06-architecture.md) between the weapon gate and the armor matrix:

| # | Milestone |
|---|---|
| 3 | Weapon gating by track quality |
| **3.5** | **Tier B ballistics — gun rounds fly, lead from the track, hit a facet** |
| 4 | Tactical display |
| 5 | Armor and penetration matrix |
| **5.5** | **Tier A missiles — flight phases, guidance loop, countermeasures, termination causes** |
| 6 | Jamming, EMCON, ESM |
| 9 | Naval layer — **torpedoes land here**, with wire guidance and the acoustic consequences |

Tier B comes early and cheaply, because "the shell physically travels to the target and hits a
specific facet" is what makes milestone 3 legible. Tier A comes with the armor model, because
that is the first point at which a missile's outcome has anything interesting to resolve
against.
