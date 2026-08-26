# 14 — Animation

> Added 2026-08-25. The short version: **vehicles need almost no animation.
> Infantry need a lot. Budget accordingly.**

## The split that decides the budget

| Class | What it needs | Cost |
|---|---|---|
| **Vehicles, ships, aircraft** | Rigid transforms on named sockets. **No skeleton, no rig, no clips** | Near zero, per unit |
| **Infantry** | A real skeleton and a full clip set | **The entire animation budget** |

Everything a tank does visually is a transform on a part that already exists as a socket in
[07](07-art-pipeline.md): the turret yaws, the gun pitches, the wheels spin, the track
scrolls, the suspension travels, the barrel recoils. None of it is skeletal animation, none
of it needs an animator, and all of it is driven directly from simulation state.

## Vehicles — driven, not authored

| Motion | Driven by | Notes |
|---|---|---|
| Turret traverse | Bearing to the current track | **Watch a turret slew and you can see what a unit has a track on.** Free tactical information |
| Gun elevation | Range to the aim point | |
| Roadwheel rotation | Ground speed | |
| Track scroll | Ground speed, as a UV offset on the track material | One float. Do not animate track links individually |
| Suspension travel | Terrain slope under each wheel | Cheap, and it kills the "sliding brick" look more than anything else |
| Recoil | Weapon fire event | ~0.25 s, then return |
| Hull pitch | Acceleration and braking | Small, but it sells weight |

**Two of these carry gameplay information, not just polish:**

- **A rotating radar dish means the unit is radiating.** Ships and radar vehicles should
  spin their antenna when `EMCON = RADIATE` and stop dead when `SILENT`. That is the emission
  state from [02, §7.1](02-detection.md) made visible on the battlefield, with no UI at all —
  and it means a player can *see* which enemy vehicle to kill first.
- **A slewing turret means a track exists.** The turret pointing at something the player
  cannot see is the enemy telling you it can see you.

Aircraft add control surfaces, landing gear, weapon separation and an afterburner glow that
should be on exactly when the `STRIKE` burn rate in [04](04-logistics.md) is active. Ships add
turret traverse, VLS hatch opening, and the radar rotation above.

## Infantry — the expensive exception

Infantry cannot be faked with transforms. They need a skeleton, a skinned mesh, and a real
clip set:

```
idle · idle_alert · walk · run · crouch_walk · prone_crawl
fire_stand · fire_crouch · fire_prone · reload · throw
hit_light · hit_heavy · death (×3) · enter_vehicle · exit_vehicle
```

Roughly **18–22 clips**. That is a genuine animation production, and it does not kitbash the
way geometry does.

### The economy that makes it affordable

> **One skeleton for every infantry unit in the game.**

A 1955 rifleman and a 2025 rifleman stand, walk, run, crouch and die identically. The
skeleton is the same; only the mesh and the equipment differ. So the clip set is authored
**once** and reused across **7 epochs × 8 factions × 7 infantry roles** — turning infantry
animation from a per-unit cost into a **fixed cost**.

Consequences to hold to:
- Every infantry mesh binds to the **same joint hierarchy and the same names**, exactly as
  every vehicle derivative shares its hero's socket names.
- Weapons attach at a `hand_r` socket and are swapped freely. A rifle, an ATGM tube and a
  MANPADS launcher are attachments, not new rigs.
- Era differences are silhouette and kit — helmet, webbing, pack — never new animation.

### What the RTS camera actually demands

At gameplay zoom a soldier is 20–40 pixels tall. That sets a low bar for animation *quality*
and a high bar for animation *legibility*:

- **Stance must read instantly.** Standing, crouched and prone have to be distinguishable at
  a glance, because they carry real gameplay meaning — a prone soldier is much harder to kill.
  Exaggerate the height difference beyond life if necessary.
- **Movement type must read.** Walking, running and crawling should differ in silhouette
  rhythm, not just speed.
- **Firing must read.** A muzzle flash plus a visible recoil pose; the flash does most of it.
- **Fine detail is wasted.** Finger poses, facial work, subtle weight shifts — none of it
  survives to the screen. Spend the effort on the three reads above.

### Performance

Hundreds of skinned, animated soldiers is the only place in this game where animation is a
real cost.

- **Do not use per-instance skeletal evaluation.** At a few hundred soldiers it dominates the
  frame.
- **Bake clips to vertex animation textures** and play them on the GPU, or use an equivalent
  animation-instancing path. Every soldier in a squad of the same type in the same state
  becomes one instanced draw.
- **Offset each instance's playback phase** so a squad does not march in lockstep.
- **LOD the animation, not just the mesh** — full rate close in, reduced rate at mid distance,
  and a two-pose flipbook or a billboard at strategic zoom.

### The artifact to avoid

**Foot sliding.** If playback rate is not tied to actual ground speed, soldiers skate, and it
is the single most noticeable animation failure at any zoom. Drive the walk/run cycle from
distance travelled, not from a timer, and blend between walk and run by speed rather than
switching.

## Build order

Animation is not on the critical path until infantry exist. From [06](06-architecture.md):

| Milestone | Animation work |
|---|---|
| 3–5 | **None.** Turret traverse and track scroll only — both are transforms |
| 7 | Suspension travel and recoil, once vehicles move over terrain properly |
| 11 (AI) | Radar rotation tied to EMCON — it is how you *see* the AI's emission state |
| 14 (Skirmish) | **The full infantry clip set.** The first point at which it is required |

So the infantry rig can be commissioned late, and it only has to be commissioned **once**.

---

## Locomotion: how it is actually built (implemented)

`tools/gait.py` builds the four upright cycles; `tools/verify_gait.py` measures
them on the rigged soldier. The construction inverts the usual authoring order.

**Contact first, joints second.** Instead of posing the hips and knees and
hoping the foot lands somewhere plausible, the weight-bearing point is placed
on the ground and the leg is solved to reach it. In body-local space that point
travels backward at exactly the body speed, so zero slip is a property of the
construction rather than something to tune.

**The sole is rigid.** A combat boot has no toe joint, and that single fact
decides which point carries the weight:

| ankle | pivot | why |
|---|---|---|
| toes down (plantarflexed) | **toe** | pivoting on the ball drives the toe through the ground |
| toes up (dorsiflexed) | **heel** | pivoting on the ball drives the heel through the ground |
| flat | either | both are on the ground; hand over here |

**Walk vaults, run compresses.** Walking is highest at mid-stance (the body
vaults over a straight leg) and lowest at double support. Running is the
opposite — lowest at mid-stance as the leg compresses, highest in flight.
Inverting that is what makes a run read as a fast walk.

**Armed infantry do not swing their arms.** Both hands stay on the weapon and
the torso absorbs the gait. Free arm swing is what civilians do, and using it
here makes a squad read as a crowd. The sole exception is the sprint, where the
weapon drops to one hand and the free arm pumps.

### The clip/game contract

Every clip publishes the speed it was authored for, in
`art/blockout/e4_infantry/clips.json`. The game plays it at

```
rate = unit_speed / clip.speed
```

Stride length is fixed in the mesh, so scaling the rate scales time only and
the no-slip property survives at any speed. **Infantry locomotion must never be
driven from a wall-clock timer** — that is the one change that reintroduces
sliding at every speed except the authored one.

### Measured

`Blender -b --python tools/verify_gait.py` walks forward kinematics through the
posed armature — the same matrices the exporter writes — and checks three
things. It deliberately shares no assumptions with `gait.py`; that independence
is the whole point, and it is what caught every bug below.

| clip | slip | sink | stance | double support | flight |
|---|---|---|---|---|---|
| walk | 1.64 mm | 0.00 mm | 66% | 31% | 0% |
| walk_crouch | 0.00 mm | 0.00 mm | 72% | 45% | 0% |
| run | 0.00 mm | 0.00 mm | 33% | 0% | 38% |
| sprint | 0.00 mm | 0.00 mm | 25% | 0% | 50% |

The stance columns are the check that catches sign errors the slip number
cannot: a walk must have double support and no flight, a run the reverse. If
both legs move together, one of those collapses to zero and the gait is a hop.

### What the verifier caught

Worth recording, because each one measured as fine somewhere else first:

1. **Clips inherited un-keyed channels.** `walk` never keyed the root rotation,
   so it kept the 84-degree face-down rotation authored by `prone` — the
   soldier walked while lying down. Fix: key every bone in every clip. The same
   hole exists in the engine whenever one clip follows another.
2. **Euler algebra was always *almost* right.** Each joint rotates about its own
   local axis, and every rotation upstream tilts that axis: the pelvis yaw tilts
   the hip, the hip abduction tilts the knee, the knee tilts the ankle. Three
   successive hand-derived corrections each left a few millimetres. Fix: read
   the matrices Blender actually computed and place each joint in world space.
3. **The planted foot tracked the pelvis sway.** `foot()` returned an ankle X
   that followed the pelvis, so the foot slid sideways under a swaying body
   instead of the body swaying over a fixed foot. Invisible because `gait.py`'s
   own slip check only compared Y and Z.
4. **The weapon inherited the elbow.** Rigid binding means the rifle inherits
   every rotation from shoulder to hand — about -95 degrees at the ready — so a
   rifle modelled horizontal at rest ships pointing at the sky. Fix: author it
   in the posed frame and invert back through the skinning transform.
5. **The arm was too short to hold a rifle.** 0.51 m shoulder-to-wrist on a
   1.8 m body against a real 0.61 m. The left arm solved to 97% extension and
   locked straight, and no amount of pose tuning would have fixed it.
