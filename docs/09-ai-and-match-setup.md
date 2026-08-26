# 09 — Opponents & Match Setup

> Confirmed 2026-08-25: **one human player against AI opponents.** Per-player epoch start,
> per-player epoch ceiling, per-player strategy.

## What this settles

Single-player is not a smaller version of multiplayer — it moves work from one place to another.

**It simplifies the simulation.** The lockstep requirement in [06](06-architecture.md) is gone:
there is no second client to desync from, so **fixed-point math becomes optional** and floats
are acceptable in the sim core. That removes the most intrusive constraint in the architecture.

**It raises the stakes on the AI enormously.** The AI is now the entire opponent experience.
Everything in [02](02-detection.md) — jamming, EMCON, stealth, cueing, the whole sensor
contest — is only ever experienced by the player if the AI is a real participant in it.

That leads directly to the single most important rule in this document.

---

## 1. The cardinal rule

> **The AI has no information the player would not have in its position.**
> Not "less cheating." **None.**

The AI's entire world model is:

```
its own units and their state
its own economy, production and epoch level
FactionTrackTable[ its own faction ]
the terrain    ← maps are public; real militaries have them
```

**That is the complete whitelist.** Anything not on it is a leak, including several that do not
look like cheating until you go looking for them.

### 1.1 Why this is absolute rather than a nicety

If the AI reads anything beyond that list, then in a single-player game *nobody* is ever on the
receiving end of the detection system. The player experiences it; the opponent does not. So
jamming does nothing, emission control does nothing, stealth does nothing, and killing the
enemy AEW aircraft accomplishes nothing.

**Every pillar in this design becomes decorative the moment the AI is allowed extra
information.** There is no partial version of this rule that preserves the game.

### 1.2 The leaks that do not look like leaks

Reading true positions is the obvious one. These are the ones that get written by accident:

| Leak | Why it is a leak | The rule |
|---|---|---|
| **Unit composition** | "How many tanks does the player have?" | Count tracks, never entities |
| **Economy and production** | Knowing the player's income, queue or stockpile | Never readable. Infer from what is fielded |
| **Epoch level** | Knowing the player teched up before meeting the new units | Inferred only from observed hardware |
| **Damage state** | Knowing a unit is at 30% | Observation gives *burning, immobile, smoking* — never a number |
| **Base layout under fog** | Knowing where the refinery is without scouting | Only what was observed, and it goes stale |
| **Production events** | Reacting the instant a unit is built | A unit does not exist to the AI until it is detected |
| **Order intent** | Reading the player's move commands or waypoints | Never. Predict from observed motion only |
| **Cross-faction knowledge** | Two hostile AIs sharing what each can see | Only *allied* factions share, via the coalition mechanic |
| **A pacing "director"** | A meta-AI reading everything to tune tension | Explicitly banned. There is no such layer |
| **Perfect classification** | A track saying "M1A2" rather than "vehicle-sized contact" | See [02, §5.1](02-detection.md) — classification is earned |

### 1.3 The architectural rule that enforces it

Access control by convention will fail. One structural decision does the work instead:

```gdscript
# WRONG — an escape hatch somebody eventually uses
class Track:
    var target_entity_id: int     # ← dereferenceable straight to ground truth

# RIGHT — a hypothesis, not a pointer
class Track:
    var track_id: int             # ← opaque; means nothing outside the track table
```

**A track is a hypothesis about a target, not a reference to one.** The mapping from track to
entity lives inside the fusion module and is never handed out. The AI module is constructed
without a reference to the entity store at all, so the query it would need cannot be written.

**And this is not only an anti-cheat measure — it is a prerequisite for electronic warfare to
work at all.** A chaff bloom, a DRFM false target, and a naval decoy are all tracks that
correspond to *no entity*. If `Track` carries an `entity_id`, those cannot be represented. The
same applies to the ordinary case of one target briefly producing two unfused tracks.

> The architecture that stops the AI cheating is the same architecture that makes decoys
> possible. Get it wrong and you lose both.

### 1.4 The obvious objection

*If the shooter does not know what it is shooting at, how does damage resolve?*

**The projectile resolves against reality; the shooter never needed to know.** A weapon flies to
an aim point derived from the track ([10, §2](10-munitions.md)), and whatever is actually there
gets hit — or does not. Truth is consulted at impact, inside the simulation, not at launch,
inside the shooter. Which is exactly how it works in reality, and why firing at a chaff cloud
is possible.

### 1.5 Verification — five tests that catch a leak

The rule is worthless if it silently erodes. These are cheap, automatable, and belong in the
regression suite from §3:

| Test | Method | Pass condition |
|---|---|---|
| **Null sensor** | Give the AI zero sensors | It **never** moves toward or fires at the player. Any targeted behaviour is a leak |
| **Offset truth** | Corrupt its track table by +500 m | **Every** AI shot misses by about 500 m |
| **Ghost track** | Inject a track backed by no entity | The AI engages it and wastes munitions — a non-cheating AI *should* be foolable |
| **Symmetry** | Replace the human with a second identical AI, mirrored start | Both play identically |
| **Blackout** | Destroy every AI sensor mid-match | Behaviour degrades to last-known-position and active search |

**The null-sensor test is the strongest and the cheapest.** A blind AI that still walks toward
your base has a leak somewhere, and the test takes minutes to write.

### 1.6 What the player gets in return

- **The whole toolkit works.** The AI can be blinded, spoofed, baited into radiating, and
  genuinely surprised. Attacking its sensors is attacking its mind.
- **Mistakes become stories.** "It fired a full salvo at a chaff cloud" is a satisfying
  outcome. "It shot me through a mountain" is a refund request.
- **Difficulty stops needing to cheat.** See §2.
- **Debugging gets dramatically easier.** Render the AI's track table beside ground truth and
  you can *see* what it believes. Most AI bugs become visually obvious.

Build that debug view early. It is the cheapest AI development tool available here — and it is
also how you spot a leak by eye, when the AI reacts to something its own picture does not
contain.

## 2. Difficulty is doctrine quality, not bonuses

Because the AI plays with real information, difficulty scales by **how competently it handles
that information** rather than by handing it resources.

| Dial | Recruit | Veteran | Elite |
|---|---|---|---|
| **Reaction latency** — new track to action | 8–12 s | 3–5 s | 1–2 s |
| **Commit threshold** — track quality needed before acting | Waits for TQ3 | Acts on TQ2 | Acts on **TQ1 cues** |
| **EMCON discipline** | Radiates constantly | Mixed | Silent by default, ESM-first |
| **Prediction quality** on a decaying track | Poor extrapolation | Reasonable | Good motion analysis |
| **Sensor share of budget** | Low | Moderate | High — buys AEW early |
| **Counter-EW response** | Ignores jamming | Re-tasks sensors | Changes bands, exploits home-on-jam |
| **Coordination** | One axis at a time | Two | Simultaneous multi-axis with sensor cover |

An Elite AI is a competent commander. A Recruit AI is a careless one. Neither is a liar, and
the difference is legible to the player: an easy opponent radiates carelessly and dies to
anti-radiation missiles, while a hard one goes quiet and shoots you on someone else's track.

**Resource handicaps exist as a separate, clearly labelled slider, off by default.** Some
players want them. They should never be the primary difficulty mechanism, because a resource
bonus makes the AI *bigger* rather than *better*, and this game is not decided by size.

---

## 3. AI architecture

Three layers at three rates, mirroring the tick budget in [06](06-architecture.md):

| Layer | Rate | Decides |
|---|---|---|
| **Strategic** | 0.2–0.5 Hz | Economy, **epoch advancement**, production mix, theatre priorities |
| **Operational** | 1–2 Hz | Where to attack, force composition, sensor and AEW placement, EMCON posture, supply routing |
| **Tactical** | 5–10 Hz | Target selection, weapon-guidance matching, evasive response to threat warnings |

The tactical layer runs **the same weapon gate the player does** — same track-quality
requirements, same guidance table from [02, §5](02-detection.md). It is not an approximation of
the player's rules; it is those rules.

### Threat assessment reads track quality

The AI's decisions are driven by *what kind* of knowledge it has, which is the same reasoning a
human does:

| What the AI has | What it does |
|---|---|
| TQ1 bearing-only contact | **Cue a sensor.** Do not commit forces to a bearing. |
| TQ1 from home-on-jam | Something is jamming — send something to look, or fire anti-radiation down the bearing |
| TQ2 track on a formation | Position, plan an engagement, seek TQ3 |
| TQ3 on a high-value emitter | **Commit.** Illuminators and AEW aircraft are priority targets |
| A track decaying from TQ3 | Predict along last known velocity, or re-acquire — do not fire blind |
| Own RWR lit up | Something has fire control on me. Break, jam, or kill the illuminator |

### AI versus AI is the balance harness

The engine-agnostic simulation boundary in [06](06-architecture.md) pays off here: with no
renderer attached, **AI-versus-AI matches run headless at many times real speed.** Thousands of
them will tune the armor matrix, epoch costs and unit pricing far better than intuition can.

Run it as a regression suite. If a change to the composite multiplier makes Gen 2 armies stop
winning against Gen 4 in the overmatch scenario, the test catches it before a player does.

---

## 4. Match setup — start and ceiling per player

Every participant, human and AI, is configured independently:

```gdscript
class_name PlayerSetup

@export var faction: Faction              # one of the eight in doc 08
@export var start_epoch: int              # 1–7 — tech available at match start
@export var ceiling_epoch: int            # 1–7 — the highest it may ever reach
@export var advance_cost_mult: float      # 1.0 = standard; higher = slower teching
@export var starting_forces: ForcePreset  # NONE / SKIRMISH / GARRISON / ARMY
@export var strategy: StrategyProfile     # AI only — see §5
@export var difficulty: Difficulty        # AI only — see §2
@export var resource_mult: float          # optional handicap, default 1.0
```

### Rules

**Ceilings are public.** Every player can see every other player's start and ceiling on the
setup screen and in-match. A hidden ceiling is not tension, it is confusion — whereas *knowing*
the AI is capped at epoch 3 turns "survive to epoch 4" into a clear, tense objective with a
visible finish line.

**Starting epoch grants technology, not an army.** `start_epoch` unlocks that epoch's units and
upgrades; `starting_forces` separately decides what is already on the map. The two are
deliberately independent, because "advanced but tiny" and "obsolete but enormous" are the two
most interesting starting positions in the game and both need to be expressible.

**Hitting the ceiling is not a dead end.** A player at their ceiling redirects epoch spending
into retrofits (ERA packages, ECCM modules, sensor and sonar upgrades — the per-unit upgrades
in [05](05-epochs.md)) and into economy. Capped does not mean stalled.

**Fielded units never retroactively upgrade**, per [05](05-epochs.md). Advancing changes what
you can *build*, not what you already own.

### Scenarios the two settings produce

This is the campaign and scenario system. It needs no separate mechanism.

| Scenario | Human | AI | The tension |
|---|---|---|---|
| **Hold the Line** | ROC · start 5, ceiling 5, garrison | PLA · start 5, ceiling 7, army | Beat the fuel clock while they out-tech you |
| **The Gap** | US · start 1, ceiling 7, small | KPA · start 2, ceiling 2, huge | Survive the mass until the generation gap opens |
| **Peer** | Germany · start 4, ceiling 6 | Russia · start 4, ceiling 6 | Even fight. Doctrine decides it |
| **Blind** | France · start 6, ceiling 6 | PLA · start 6, ceiling 6, *Denial* | Fight with your picture under constant attack |
| **Coalition** | Germany · start 5, ceiling 6 | Russia + 2 allies | You have no organic AEW. Protect the American who does |
| **Overmatch** *(test)* | Any · start 7, ceiling 7, tiny | 3× AI · start 3, ceiling 3, massive | **The escape-valve stress test — can mass beat generation?** |

That last row is a balance harness disguised as a scenario. If the Gen 3 mass cannot win it,
the cost curves and top-attack valves in [03](03-armor.md) need work.

---

## 5. Strategy profiles

Each AI is assigned a doctrine — a set of weights that shapes every layer of its decisions.

```gdscript
class_name StrategyProfile

@export var aggression: float        # 0–1 · timing and commitment of attacks
@export var tech_bias: float         # 0–1 · epoch advancement vs. more units now
@export var emcon_discipline: float  # 0–1 · willingness to stay silent and go blind
@export var sensor_share: float      # 0–1 · budget on sensors, AEW and EW vs. shooters
@export var ew_posture: float        # 0–1 · proactive jamming
@export var logistics_depth: float   # 0–1 · how far it pushes supply from its base
@export var target_priority: float   # 0 = armies … 1 = enablers (sensors, tankers, supply)
```

### The eight doctrines

| Doctrine | Shape | What it feels like to play against |
|---|---|---|
| **Blitz** | High aggression, low tech, poor EMCON | Early pressure, constant. Punishes a slow opening, collapses if you survive to a generation ahead |
| **Tech Rush** | Low early aggression, max tech, small army | Quiet, then terrifying. A window to punish early, then a cliff |
| **Sensor Dominance** | High sensor share, high EMCON, fights at maximum range | You keep dying to things you never saw. Kill its AEW or lose |
| **Denial** | Max EW posture, defensive, SAM belts, counter-stealth | Your picture is never reliable. Advancing means fighting half-blind |
| **Attrition** | Mass, artillery, low tech, accepts losses | Relentless, cheap, endless. Tests whether your quality actually scales |
| **Fortress** | Turtle, fixed defences, high sensor share | Nothing comes to you. You have to go in, and it sees you coming |
| **Interdiction** | `target_priority` on enablers, deep logistics | **It hunts your tankers, oilers, AEW and supply trucks instead of your army** |
| **Combined Arms** | Balanced, adaptive | The default. Reads what you are doing and answers it |

**Interdiction is the standout**, and worth building early. It is the only opponent that
attacks the logistics pillar directly — and therefore the only one that teaches a player *why*
[04](04-logistics.md) exists. An AI that ignores your tanks and kills every fuel truck you own
is a memorable, specific, and entirely fair opponent.

**Strategy is independent of faction.** Each faction has a default doctrine that matches its
historical shape — Russia to *Denial*, the KPA to *Attrition*, the ROC to *Fortress*, the US
and PLA to *Sensor Dominance* — but any doctrine can be assigned to any faction. "Russia playing
Sensor Dominance" is ahistorical and a genuinely different fight, and the setup screen should
allow it.

### Adaptation

Doctrines set a *posture*, not a script. Every AI, regardless of profile, re-evaluates on the
strategic tick and shifts within a band around its profile:

- Losing the sensor contest badly → raise `emcon_discipline` and `sensor_share`
- Behind on epochs with a ceiling still above it → raise `tech_bias`
- At its ceiling → dump everything into retrofits and mass
- Fuel-starved → raise `logistics_depth`, pull back the offensive
- Its own AEW keeps dying → stop flying it forward

A profile that never adapts is exploitable in one match and boring in the second.

---

## 6. Multiple AI opponents

"One human versus AIs" is plural, so matches support **1 human + N AI**, free-for-all or teamed.

**Allied AIs share a track table**, which is exactly the coalition mechanic in
[08](08-factions.md) — no new system, just fusion spanning more than one player. Two allied
Western AIs get the Link-16 benefit and the shared vulnerability that comes with it.

**Team AIs must deconflict**, at minimum by not stacking on one axis and by not both flying AEW
to the same orbit. A light coordination layer on the strategic tick — claim an axis, claim a
sensor sector — is enough, and is much cheaper than genuine cooperative planning.

**A human plus AI allies** should work with the same machinery. If the player is allied to a US
AI, that AI provides the AEW picture the player's Germany cannot generate — which makes the
coalition mechanic something the player *feels* rather than reads about.
