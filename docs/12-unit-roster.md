# 12 — Unit Roster

> Added 2026-08-25. The complete role list across all domains, with epoch availability.
> Roles are **faction-agnostic**; each faction fills a role with its own hardware per
> [08](08-factions.md), built from the bucket system in [07](07-art-pipeline.md).

## How to read this

**A role is not a unit.** `MBT` is a role; a Gen 1 Soviet MBT and a Gen 4 German MBT are
different units filling it. The content matrix is **role × epoch × faction**, which is why
[07](07-art-pipeline.md) builds one hero per `(epoch, role)` and derives factions from it.

**Epoch column** = the first epoch the role exists at all. A blank means epoch 1.
Roles that appear later are the ones that change *how the game is played*, and they map
directly onto the cliffs in [11, §8](11-generations.md).

**Totals: 24 ground · 7 infantry · 20 air · 16 naval · 19 structures = 86 roles.**

---

## Ground — 24 roles

### Manoeuvre

| Role | Epoch | Notes |
|---|---|---|
| **Main battle tank** | 1 | The armor ladder's anchor. [03](03-armor.md), [11](11-generations.md) |
| **Light tank / tank destroyer** | 1 | Fast, thin, big gun. Ambush role once the cliff bites |
| **IFV** | 3 | Carries infantry *and* fights — ATGM-armed from epoch 3 |
| **APC** | 1 | Carries infantry only. Cheap, survivable, unglamorous |
| **Reconnaissance vehicle** | 1 | Optics and ESM, light weapons. **Feeds the track table** |
| **ATGM carrier** | 2 | The CE half of the armor matrix. Wants range; tanks want to close |

### Fires

| Role | Epoch | Notes |
|---|---|---|
| **Self-propelled howitzer** | 1 | **Shoot-and-scoot**, because counter-battery radar exists — [10, §8](10-munitions.md) |
| **Towed artillery** | 1 | Cheaper, more vulnerable, cannot scoot. The KPA's bulk |
| **MLRS** | 1 | Saturation. Area-fires at **TQ0** — no track needed |
| **Mortar carrier** | 1 | Short-range indirect, organic to infantry |
| **Ballistic missile launcher** | 2 | `GNSS_INS` from epoch 5 — kills buildings, never movers |
| **Coastal anti-ship battery** | 2 | Taiwan's signature. Long-ranged, needs a maritime track |

### Air defence — note the split

| Role | Epoch | Notes |
|---|---|---|
| **SPAAG** (gun AA) | 1 | Short range, no radar dependency, immune to ARM |
| **SHORAD SAM** | 3 | IR or short-range RF. Mobile |
| **Medium SAM launcher** | 2 | **Launcher only** — needs a separate radar |
| **Long-range SAM launcher** | 3 | Ditto, further |
| **Search radar vehicle** | 1 | `max_quality = TRACK`. Finds, cannot guide |
| **Illuminator / fire-control radar** | 2 | `max_quality = FIRE_CONTROL`. **The thing to kill** |

> Splitting the SAM battery into launcher + search radar + illuminator is the single most
> important roster decision in this document. It is why real batteries are several vehicles,
> and it gives the player a target priority the game never has to explain: **kill the
> illuminator, not the launcher.** See [02, §5](02-detection.md).

### Support

| Role | Epoch | Notes |
|---|---|---|
| **Counter-battery radar** | 2 | Backtracks shells to the firing position — [10, §8](10-munitions.md) |
| **Ground EW / jammer** | 2 | Denies the enemy picture. **Also a screaming RF beacon** |
| **Command vehicle** | 4 | Datalink node. Killing it fragments the track table |
| **Fuel truck** | 1 | Pillar 4. Often better to kill than the tanks it feeds |
| **Ammunition truck** | 1 | Sustains rate of fire |
| **Engineer vehicle** | 1 | Obstacles, mines, fortifications, bridging |
| **Repair vehicle** | 1 | Recovers mobility and firepower kills |

## Infantry — 7 roles

| Role | Epoch | Notes |
|---|---|---|
| **Rifle squad** | 1 | Holds ground, takes buildings |
| **Anti-tank team** | 1 | ATGM from epoch 2, **top-attack from epoch 6** — kills any MBT ever built |
| **MANPADS team** | 3 | Cheap, passive, invisible until it fires |
| **Recon / forward observer** | 1 | Eyes for artillery. **Passive — contributes tracks without radiating** |
| **Engineer / sapper** | 1 | Mines, demolition, fortification |
| **Special forces** | 1 | Infiltration, designation, sabotage of radars and fuel |
| **Mortar team** | 1 | Organic indirect fire |

---

## Air — 20 roles

### Combat

| Role | Epoch | Notes |
|---|---|---|
| **Interceptor** | 1 | Fast, short-legged, climbs. Point defence |
| **Air superiority fighter** | 2 | Owns the air. The M-ladder's anchor — [11, §5.1](11-generations.md) |
| **Multirole fighter** | 4 | Flexible, never best at anything |
| **Strike aircraft** | 1 | Deep targets, ordnance-heavy — and **RCS-heavy when loaded** |
| **Close air support** | 1 | Slow, armoured, gun-and-rocket |
| **Bomber** | 1 | Large RCS, long reach, needs escort |
| **SEAD / defence suppression** | 2 | `ANTI_RADIATION`. **The SAM must radiate to kill; the HARM needs it to** |
| **Stealth strike aircraft** | 4 | The fourth-root cliff arrives — [02, §3](02-detection.md) |

### Enablers — the ones this game is about

| Role | Epoch | Notes |
|---|---|---|
| **AEW&C aircraft** | 3 | **Pillar 5.** A radar 9 km up. Turns a 32 km horizon into 400 km |
| **AEW helicopter** | 3 | ~3 km up → ~235 km. **The UK's compromise** — [08](08-factions.md) |
| **Electronic attack aircraft** | 2 | Airborne jamming. Escorts strike packages |
| **Aerial tanker** | 2 | **Pillar 4.** Turns a 30-minute CAP into a 3-hour one |
| **ISR / reconnaissance aircraft** | 1 | Contributes tracks, carries nothing |
| **Maritime patrol / ASW aircraft** | 1 | **Pillar 6.** Sonobuoys, MAD, torpedoes |
| **Transport aircraft** | 1 | Airlift, paradrop, resupply |

### Rotary and unmanned

| Role | Epoch | Notes |
|---|---|---|
| **Attack helicopter** | 3 | ATGM platform. Terrain-masks below the radar horizon |
| **Transport helicopter** | 2 | Air assault |
| **ASW helicopter** | 2 | **Dipping sonar** — mobile, no own-noise, leapfrogs the ship |
| **Reconnaissance UAV** | 5 | Cheap, persistent, low signature |
| **Armed UAV** | 6 | Strike without risking a pilot |
| **Loitering munition** | 7 | Cheap and expendable — **spend them to make the enemy radiate** |

---

## Naval — 16 roles

### Surface combatants

| Role | Epoch | Notes |
|---|---|---|
| **Air-defence destroyer** | 4 | Arleigh Burke, Type 055, Type 45. **The layered ladder** — [02, §8.6](02-detection.md) |
| **ASW frigate** | 1 | Towed array, helicopter, torpedoes |
| **Cruiser** | 1 | Heavy surface combatant; area air defence from epoch 4 |
| **Corvette / fast attack craft** | 1 | Cheap, fast, anti-ship missiles, no endurance |
| **Missile boat** | 2 | Coastal denial. Taiwan and the KPA lean on these |
| **Patrol vessel** | 1 | Presence, escort, cheap eyes |

### Submarines

| Role | Epoch | Notes |
|---|---|---|
| **Diesel-electric submarine** | 1 | Quiet on battery, loud snorkelling |
| **Nuclear attack submarine** | 2 | Fast and long-legged — **and, in epoch 2, noisier than the diesels** |
| **AIP submarine** | 7 | Near-silent at creep. **Best ambusher, worst pursuer** |
| **Midget submarine** | 1 | The KPA's asymmetric tool. Tiny signature, tiny range |
| **Ballistic missile submarine** | 3 | Strategic. Rarely fights |

### Aviation, amphibious, and the one that matters

| Role | Epoch | Notes |
|---|---|---|
| **Aircraft carrier** | 1 | Moves the air force. Nuclear from epoch 3 — no fuel constraint |
| **Amphibious assault ship** | 2 | Landing force + helicopters |
| **Landing craft** | 1 | Ship-to-shore |
| **Fleet oiler / replenishment** | 1 | **Pillar 4's centrepiece.** Underway replenishment is a window of vulnerability — a submarine that finds the oiler has taken the fleet's *range* |
| **Mine warfare vessel** | 1 | Laying and sweeping. Taiwan's force multiplier |

---

## Structures — 19 roles

| Role | Epoch | Notes |
|---|---|---|
| **Headquarters** | 1 | Command, and the datalink root |
| **Power plant** | 1 | Radars and factories both draw on it |
| **Oil derrick** | 1 | Extraction. **Taiwan cannot build these** — [08](08-factions.md) |
| **Refinery** | 1 | Crude → fuel |
| **Supply depot** | 1 | Forward node; extends the network's reach |
| **Barracks** | 1 | Infantry |
| **Light vehicle factory** | 1 | Wheeled, support, trucks |
| **Heavy vehicle factory** | 1 | Tracked, armoured |
| **Airbase** | 1 | Runway, hangars, rearm and refuel |
| **Hardened aircraft shelter** | 2 | Survives what the airbase does not |
| **Helipad** | 2 | Rotary basing, forward |
| **Naval yard** | 1 | Ship construction and repair |
| **Fixed radar station** | 1 | **Mount height from terrain — free range on high ground.** Also pre-surveyed |
| **Fixed SAM site** | 2 | Cheaper and tougher than mobile; cannot relocate |
| **Coastal battery** | 2 | Hardened anti-ship |
| **EW station** | 2 | Area jamming |
| **Research facility** | 1 | **Epoch advancement and ladder retrofits** — [11, §9](11-generations.md) |
| **Repair depot** | 1 | Restores component damage |
| **Bunker / fortification** | 1 | Very high effective armor. Taiwan's mountains |

---

## What the roster is shaped by

Three observations, each of which is the roster reflecting a pillar rather than a genre habit:

**The SAM battery is three vehicles, not one.** Search radar, illuminator, launcher. That
single split creates target priority, makes SEAD a real mission, and gives
`ANTI_RADIATION` something to home on. It is the roster's most consequential decision.

**Enabler aircraft outnumber the glamorous ones.** AEW&C, AEW helicopter, electronic attack,
tanker, ISR, maritime patrol — six of twenty air roles carry no meaningful air-to-air
armament and are the most valuable targets on the map. In most RTS games the fighter is the
prize; here the aircraft that lets the fighters *see* is.

**Logistics has four roles across three domains** — fuel truck, ammunition truck, aerial
tanker, fleet oiler. That is deliberate: pillar 4 only produces interesting decisions if
supply is a *thing on the map that can be attacked*, and the *Interdiction* doctrine in
[09, §5](09-ai-and-match-setup.md) exists to teach exactly that.

## Build order for content

Follow [06](06-architecture.md)'s milestones, not this list top to bottom. The minimum
roster for a playable single-epoch Skirmish is **fourteen roles**:

> MBT · IFV · recon vehicle · SPH · MLRS · search radar · illuminator · medium SAM launcher
> · fuel truck · rifle squad · AT team · air superiority fighter · strike aircraft · AEW&C

That set exercises all seven pillars — armor generations, radar-cued fire, the SEAD duel,
jamming, fuel, AEW horizon, and munition flight — in one 20-minute match. Everything else
is breadth.
