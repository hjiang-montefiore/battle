# 04 — Fuel & Logistics

> Pillar 4: *"vehicle, navy, aircraft should have the oil range. we should have oil tanker
> for the navy and army."*

## The risk, stated first

**This is the most dangerous pillar in the design.** Fuel that must be hand-managed will make
the game tedious, and tedium kills RTS games faster than imbalance does. Every mechanic below
is written against one constraint:

> The player's decision is **where the supply lines run and whether to defend them.**
> It is never *"click the refuel button."*

Automation is the default at every level. Manual override exists for players who want it and
is never required to play well. If a playtest produces the sentence "I spent the match
managing fuel trucks," the feature has failed and gets cut back, not tuned.

## What fuel buys the design

Three things nothing else provides:

1. **Depth becomes expensive.** Without fuel, distance is free and the map is flat. With it,
   projecting force far from your base is a real commitment — which is what makes territory
   mean something.
2. **Supply lines become targets.** Interdiction — hitting the tankers instead of the tanks —
   becomes a genuine strategy, and it rewards exactly the long-range sensor and strike play
   that [02](02-detection.md) is built for.
3. **Mass has a cost beyond price.** A huge army is a huge fuel problem. This is the natural
   counterweight to the "mass obsolete units" strategy in [03](03-armor.md), and it keeps the
   epoch decision balanced from both directions.

## The unit model

```gdscript
class_name FuelTank
@export var capacity: float
@export var burn_idle: float      # per minute, stationary, systems running
@export var burn_cruise: float    # economical movement
@export var burn_combat: float    # flank speed / full military power
@export var burn_afterburner: float   # aircraft only — 5–10× dry thrust
var current: float
```

Throttle state is a real decision, most sharply for aircraft: **afterburner burns fuel five
to ten times faster than dry thrust.** An interceptor that lights the burners to reach a
target has traded away its loiter time and possibly its trip home. That single ratio makes
"do I commit at full speed?" a recurring, meaningful question.

### Range versus radius

The number the player needs is **combat radius**, not ferry range — you have to get back, and
you need a reserve plus an allowance for fighting when you arrive.

```
combat_radius ≈ ferry_range × 0.35
```

Surface this directly: **the tactical map draws a combat-radius ring** around selected
aircraft and mobile groups, updating live as fuel burns. If the target is outside the ring,
the player can see it before committing, and the answer is visible too — move a tanker, move
a forward base, or accept a one-way trip.

## The three chains

Oil is extracted, refined into fuel, and distributed. One resource, three delivery networks.

### Army

```
Refinery → Fuel depot → Fuel truck → Forward supply point → Vehicles
```

Fuel trucks travel a **supply route** the player draws once and rarely touches again. They
auto-dispatch when a formation drops below a threshold. Forward supply points extend the
network's reach — establishing one is the ground equivalent of moving a carrier.

The truck is soft, slow and enormously valuable. Killing it is often better than killing the
tanks it feeds.

### Navy — the oil tanker

```
Refinery → Port → Fleet oiler → Underway replenishment → Warships
```

The **fleet oiler** (replenishment ship) is the pillar's centerpiece and the most interesting
logistics unit in the game, because replenishment at sea imposes real constraints:

- Both ships must hold **steady course and speed** while connected.
- Neither can manoeuvre, and the warship's own sensors are degraded while alongside.
- The pair is, for several minutes, **the softest target in the fleet.**

So refuelling a task force is a window of vulnerability the enemy can hunt for. A submarine
that finds the oiler has done more damage than one that finds a destroyer — the destroyer is
one ship, the oiler is the fleet's range. This gives the ASW game in
[02, §8](02-detection.md) a target worth all that patience.

### Air

```
Airbase → Aerial tanker → Aircraft on station
```

#### The RTB rule

Fixed-wing aircraft do **not** return to base at a fixed fuel percentage. The trigger is
computed continuously against the distance actually left to fly:

```
range_remaining = fuel_current / burn_per_km_at_cruise
d_home          = distance to the nearest recovery point
                  (friendly airfield, carrier, or tanker orbit)

RTB when:   range_remaining  <  RESERVE × d_home        RESERVE = 1.10
```

**The return leg is estimated at cruise burn, not at current throttle** — an aircraft in
afterburner is not going to come home in afterburner.

Six consequences, and they are the reason to compute it this way rather than with a fixed
threshold:

1. **The trigger is dynamic.** An aircraft orbiting over its own airfield can run down to
   almost nothing. One four hundred kilometres out must turn for home at roughly half fuel.
   Same rule, completely different behaviour.
2. **Afterburner can trip it mid-fight.** Lighting the burners burns range fast enough to
   satisfy the condition while the aircraft is still engaged — and then it disengages. That
   is the tension the rule exists to create, not a bug to be smoothed away.
3. **Tankers move the boundary.** A tanker orbit counts as a recovery point, so placing one
   forward *literally* extends how deep aircraft can operate. Tanker placement becomes a
   strategic decision rather than a convenience.
4. **The combat-radius ring is this rule, drawn.** The ring on the tactical map is exactly
   the locus of points where the condition trips. It is a rendering of the mechanic, not a
   decoration.
5. **Killing an airfield strands aircraft.** `d_home` recomputes to the *next* nearest
   recovery point the moment a field is lost. Strike the enemy's forward airbase and their
   airborne aircraft may no longer be able to reach anywhere friendly. This is one of the
   most dramatic things in the logistics pillar and it falls out of one line.
6. **A 10% reserve is deliberately thin.** Real practice reserves 20–30% for divert and hold.
   `RESERVE` is a tunable constant; 1.10 is the specified default and makes the game tense.
   Raise it if playtests show too many aircraft lost to arithmetic rather than to enemies.

#### Aircraft states

| State | Fuel burn | Notes |
|---|---|---|
| `READY` | none | On the ground, armed and fuelled |
| `TAKEOFF` | high | Brief |
| `TRANSIT` | cruise | Outbound to the tasked area |
| **`PATROL`** | **cruise / loiter — lowest** | On station. Combat air patrol, barrier, escort. Where aircraft spend most of their airborne life |
| **`STRIKE`** | **high; afterburner spikes 5–10×** | The attack run. Also the state that trips the RTB rule unexpectedly |
| **`RTB`** | cruise | Triggered by the rule above, by damage, by winchester, or by order. **Disengages** |
| `LANDING` | low | Committed; cannot re-task |
| `TURNAROUND` | none | Refuel and rearm. A real time cost — sortie rate is a resource |

`PATROL` and `STRIKE` are the two the player commands directly; `TRANSIT`, `RTB`, `LANDING`
and `TURNAROUND` are automatic. The player should never click a refuel button — see the
interface rules below.

A tanker orbit lets fighters top off without going home, converting a 30-minute combat air
patrol into a three-hour one. The tanker itself is unarmed, enormous on radar, and the
second-most-valuable target in the sky after the AEW aircraft — which gives air superiority
a purpose beyond killing fighters.

## Running dry

Failure modes differ by domain, and that asymmetry is deliberate — it makes fuel risk feel
different in each theatre rather than being one uniform nuisance.

| Domain | Out of fuel |
|---|---|
| **Ground** | Immobilised, **still fights.** Turret traverses, weapons work. It is now a bunker — a mistake, but a survivable one. |
| **Naval** | Dead in the water. Sensors and weapons still run on auxiliary power for a time. Cannot evade, cannot close. Recoverable if an oiler reaches it. |
| **Air** | **Destroyed.** No second chance. |

Ground is forgiving, naval is recoverable, air is fatal. That is roughly true to life and it
correctly ranks how much attention each domain deserves.

## Epoch scaling

Fuel demand is not constant across the seven eras in [05](05-epochs.md):

- Gas-turbine tanks (1980s+) burn dramatically more than diesels — a real and famous
  characteristic, and a genuine strategic drawback to a technically superior vehicle.
- Nuclear-powered ships (submarines, carriers, some cruisers) **ignore fuel entirely** for
  propulsion. Unlocking nuclear propulsion is one of the most consequential epoch rewards in
  the game: it removes a whole constraint from your fleet's core.
- Aerial refuelling matures over the epochs — capacity, boom rate and how many aircraft can
  be supported at once all improve.
- Later-epoch aircraft fly farther on less, softening the constraint exactly as the maps and
  weapon ranges grow.

## Interface rules

Non-negotiable, because this is where the pillar succeeds or fails:

1. **Combat-radius rings** on the map for anything selected. Always visible, always live —
   and for aircraft the ring *is* the RTB rule above, drawn.
2. **Fuel state as a colour band on the unit card** — green / amber / red. No numbers unless
   the player asks for them.
3. **Supply routes drawn once**, then persistent and automatic.
4. **One alert, not many.** "3rd Armoured will be out of fuel in 4 minutes" — with a click
   that jumps to the formation and a second that dispatches a tanker.
5. **Never a modal prompt.** Fuel must not interrupt a fight.
