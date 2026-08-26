# 07 — Art Pipeline

> *"use hero models for certain weapons for this country and era, but then apply the
> similarities to the hero models."*

## The scope problem

Seven epochs × eight factions × a dozen unit roles is on the order of **650 vehicles**.
Modelling each from scratch is not possible for a small team, and it is not necessary —
real military hardware within a nation and era already shares proportions, running gear,
turret geometry and detail language.

## Buckets and heroes

Content is organised into **buckets**, each keyed by `(epoch, role)`:

```
(Epoch 4 — Digital, Main Battle Tank)
   HERO:  the era-defining vehicle, modelled at full fidelity
   ├── national variant A   (turret + gun swap, retexture)
   ├── national variant B   (hull + suspension swap, retexture)
   └── late-epoch refit     (ERA blocks, sensor package added)
```

One **hero model** per bucket, built properly. Everything else in the bucket is a **derivative**
— kitbashed from the hero's parts library with turret swaps, hull changes, running-gear
variation and new textures.

Faction is deliberately the *derivative* axis rather than the hero axis. That turns
`7 epochs × 8 factions × 12 roles = 672` heroes into `7 × 12 = 84`, minus the buckets where a
role does not change every epoch. Realistic target: **70–90 hero models and roughly 600
derivatives.**

### Three lineages, eight skins

The roster in [08](08-factions.md) makes this far cheaper than the raw count suggests, because
eight factions cluster into **three equipment lineages**:

```
WESTERN            ── US · UK · Germany · France · Taiwan (early)
SOVIET / RUSSIAN   ── Russia · North Korea · PLA (epochs 1–4)
                        └── forks at epoch 5 ──►  CHINESE INDIGENOUS ── PLA (epochs 5–7)
```

Two consequences for production:

**Splitting NATO four ways is the cheapest expansion available.** The US, UK, Germany and
France share the Western parts library completely — same skeleton, same sockets, different
turrets, running gear and textures. The UK's rifled gun and France's autoloader are *turret
swaps*, not new lineages. Four Western factions cost roughly **10–15% more hero models** than
one would, and roughly double the derivative count. Derivatives are assembled, not sculpted.

**The PLA changes lineage mid-timeline**, which the bucket system handles natively: a lineage
change is just a new bucket at a new epoch. Build early PLA out of the Soviet library and late
PLA out of a new indigenous one, and the visible shift from epoch 4 to epoch 5 becomes a
storytelling asset rather than a modelling problem.

## Bucket rules

**One rig per bucket.** Every derivative inherits the hero's skeleton, attachment sockets and
animation set. A new variant costs geometry and texture work, never rigging or animation work.

**A named socket set, identical across all buckets.** `turret_mount`, `gun_mantlet`,
`sensor_mast`, `era_plate_[1..n]`, `aps_launcher_[1..n]`, `exhaust`, `track_left/right`,
`hardpoint_[1..n]`, `damage_hull/turret/track`. Consistent sockets are what make upgrades
attachable at runtime.

**A shared parts library per bucket** — turrets, guns, hulls, wheels, stowage, sensors — so
derivatives are assembled rather than sculpted.

**One material and one texture atlas per bucket**, so an entire epoch's armored force renders
in a handful of draw calls via GPU instancing. At RTS unit counts this is a rendering
requirement, not an optimisation.

## Upgrades must be visible

This is the highest-value rule in this document, and it exists to serve [03](03-armor.md).

The generational armor system is invisible unless the models show it. Every protection and
sensor upgrade the player buys **attaches a visible part at a socket**:

| Upgrade | Visible change |
|---|---|
| ERA package | Reactive blocks bolt onto the hull and turret faces |
| Composite refit | Thicker, squarer turret cheeks and applique panels |
| Hard-kill APS | Interceptor launchers and small panel radars on the turret |
| Sensor upgrade | New thermal sight housing, mast, or antenna array |
| Fuel drums | External drums at the rear — visibly extending range |

A player must be able to look at an enemy tank and read *approximately what generation it is*
before deciding to engage it frontally. **Silhouette is a gameplay-critical channel**, not
decoration.

## Readability

The Red Alert 2 inheritance is legibility, and it constrains modelling more than fidelity does.

**Silhouette first.** Units are seen small, from a fixed high angle, often in motion. Design
every hero in silhouette before detailing it, and check every derivative at gameplay zoom in
solid black — `tools/hero_silhouette.py` renders exactly that test.

### What the silhouette rule can and cannot deliver

Tested 2026-08-25 with three reference-corrected heroes — M1A2, T-72, Leopard 2A6 — and the
result corrects the rule as originally written:

| View | Verdict |
|---|---|
| **Side profile** | **Passes decisively.** The three are unmistakable: the M1's long low turret tapering to the front, the T-72's small domed turret and proportionally huge gun overhang, the Leopard's height and forward wedge prow |
| **RTS three-quarter, gameplay zoom** | **Marginal.** M1 and Leopard 2 stay confusable |

The cause is not bad modelling. At a fixed high camera angle the dominant read is the hull's
rectangular slab, which is close to identical on any modern MBT — **because in reality it is.**
Turret detail is a small fraction of the pixels at that scale.

So the rule needs splitting:

- **Across roles** — MBT vs. IFV vs. SPG vs. radar vehicle vs. SAM launcher — silhouette
  distinction is achievable and **mandatory**. A player must never mistake a radar vehicle for
  a tank.
- **Across same-role, same-generation national variants** — M1 vs. Leopard 2 vs. Challenger —
  silhouette distinction is **not achievable**, and chasing it will distort the models away
  from their real shapes.

For that second case the game must use a **non-silhouette channel**: team colour on the
mask area, faction insignia, a selection-outline hue, or a UI marker. Which is what every
RTS actually does, and what this design should plan for rather than discover late.

**A useful consequence:** the generational read still works. A Gen 1 tank against a Gen 3.5
one differs by 0.87 m of height and an entirely different turret form, and that *is* legible
at gameplay zoom. So *"can I tell what generation that is before I engage it frontally"* —
the question [03](03-armor.md) actually needs answered — is satisfied. *"Can I tell whose it
is"* is a colour problem, not a modelling problem.

**Roles read as shapes.** MBT, IFV, SPG, SAM launcher and radar vehicle should each have an
unmistakable profile that stays recognisable across all seven epochs. A player should identify
*what a thing does* instantly and *what generation it is* on a second look.

**Team color on a dedicated mask channel**, on large flat areas visible from above.

**Exaggerate where it helps.** Radar dishes, missile canisters and gun barrels can run
oversized. Real proportions lose to readability every time.

## LOD

| Level | Distance | Budget | Notes |
|---|---|---|---|
| LOD0 | Cinematic, close inspection | 30–60k tris | Hero only; derivatives inherit |
| LOD1 | Normal gameplay zoom | 8–15k tris | **The one that matters** |
| LOD2 | Zoomed out | 2–4k tris | Silhouette must survive intact |
| LOD3 | Strategic view | Impostor / billboard | Symbol legibility over form |

Budget the effort at **LOD1** — that is where players spend their time. LOD0 exists for
selection close-ups and marketing.

## Naval and air

Same bucket system, different axes:

- **Ships** are large and few, so they justify higher individual budgets and modular
  superstructures. Sensor fits and VLS blocks are socketed parts, which lets an Arleigh Burke
  Flight I, IIA and III share one hull — and the same trick covers a Type 45's distinctive
  radar tower and a Type 055's integrated mast as socketed superstructure variants.
- **Aircraft** are small on screen and read almost entirely by planform. Silhouette discipline
  matters more here than anywhere else. External stores are socketed — and, per
  [02, §1](02-detection.md), **a loaded aircraft's visibly hung ordnance corresponds to its
  degraded RCS.** The art and the simulation agree, and the player can see it.

## Production order

Build in the order the game needs them, not chronologically:

1. **One complete bucket**, end to end — hero, three derivatives, all sockets, all LODs, all
   upgrade attachments. This is the pipeline test, and it should be Epoch 4 MBTs, since that
   bucket exercises every rule above.
2. The rest of that epoch's ground roles — enough to playtest a single-epoch Skirmish
   ([06, milestone 11](06-architecture.md)).
3. Adjacent epochs of the same roles, so the generational cliff can be felt.
4. Air, then naval.
5. Remaining epochs outward from the middle.
