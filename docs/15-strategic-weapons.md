# 15 — Strategic Weapons

> Added 2026-08-25. Nuclear-armed ballistic missiles in three basing modes:
> **fixed silo**, **road-mobile launcher**, and **ballistic missile submarine**.

## Why these belong in this design specifically

Most RTS superweapons are a charge bar and an explosion. That is not what is
interesting here, and it would waste the best thematic fit in the whole game.

> **The nuclear triad is three different answers to one question — the same
> question the entire game is built around: *can you be found?***

| Basing | Survival strategy | Which pillar it exercises |
|---|---|---|
| **Silo** | *Accept* detection. Its position is known from the first minute. Survives by being buried in concrete | Armour and hardening — [03](03-armor.md) |
| **Road-mobile launcher** | *Evade* detection on land. It is not hardened at all; it survives only by never being located | Detection and EW — [02](02-detection.md) |
| **Ballistic missile submarine** | *Evade* detection at sea. Survives by being acoustically invisible | Naval ASW — [02, §8](02-detection.md) |

Three units, three completely different counters, and every one of them is a
sensor problem rather than a firepower problem. That is this design's thesis
stated in hardware.

## The game is counterforce, not the explosion

The launch is the *end* of the interesting part. What the player actually plays
is the race before it:

```
build  →  [ FIND IT  ⟷  HIDE IT ]  →  launch  →  intercept?  →  impact
                  ^^^^^^^^^^^^^^^
                  this is the game
```

So the design rule is:

> **Never make the warhead the interesting decision. Make *finding the launcher*
> the interesting decision.**

Concretely: a silo you can see from turn one but must dig out; a mobile launcher
that is trivially killed *if* you can locate it, so the whole contest is
locating it; a submarine that may be anywhere in a very large ocean.

## The three units

### Fixed silo

| | |
|---|---|
| Epoch | 2 |
| Detection | **Permanently visible.** A silo field is surveyed and never moves |
| Survivability | Enormous effective armour, and only from **above** — see below |
| Counter | Sustained heavy strike, or a penetrating weapon |

A silo is a hardened structure, so it plugs straight into the armour model in
[03](03-armor.md) with an absurd `TOP` facet value and no other facets that
matter. **Ordinary bombs do nothing.** Killing one requires either a very large
penetrating weapon or repeated strikes — which means committing aircraft over a
known, defended point, and that is exactly the SEAD problem in
[02, §5](02-detection.md).

The silo's weakness is that the enemy has had the coordinates since the match
started and can plan around it. It is the *predictable* leg.

### Road-mobile launcher

| | |
|---|---|
| Epoch | 5 |
| Detection | **Very low when stationary and dispersed.** High while moving or erecting |
| Survivability | Almost none. A single hit kills it |
| Counter | Find it — persistent ISR, and striking within the window |

This is the most interesting of the three and the one that best expresses the
design. It is a soft truck carrying an enormous missile. Anything that hits it
destroys it. The entire contest is *locating* it before it fires, which makes it
a pure exercise of [02](02-detection.md):

- **Dispersal and concealment** — the KPA's mechanism from [08](08-factions.md),
  not stealth shaping.
- **The erect-and-launch window** is the vulnerability. Raising the missile is a
  large, unmistakable signature, and it takes time. A launcher that has erected
  and not yet fired is briefly a very obvious target.
- **Persistent ISR beats one-off search.** A recon UAV loitering over a suspected
  deployment area is how you find these, which finally gives the unarmed
  reconnaissance roles in [12](12-unit-roster.md) a decisive job.
- **It must return to a support vehicle to reload.** Following the logistics is a
  second way to find it — the *Interdiction* doctrine in
  [09, §5](09-ai-and-match-setup.md) applied to the strategic layer.

> The road-mobile launcher is the unit that makes an enemy's reconnaissance
> aircraft feel genuinely dangerous.

### Ballistic missile submarine

| | |
|---|---|
| Epoch | 3 |
| Detection | Acoustic only, and it is the quietest thing in the game |
| Survivability | Total, while undetected |
| Counter | The full ASW apparatus of [02, §8](02-detection.md) |

The SSBN is the *survivable* leg, and it is survivable because of the
speed-to-noise curve. Its entire doctrine is to go slow, stay deep, stay below
the layer, and be patient — the same mechanics as the attack submarine, with
the stakes raised.

Everything already built for ASW applies unchanged: towed arrays, passive
bearing-only contacts requiring motion analysis, dipping sonar from helicopters,
sonobuoy barriers, and the fact that **an active ping announces the hunter long
before it locates the hunted**.

Two consequences worth having:

- **A boat that launches reveals itself.** The launch is unmistakable and
  instantly localises a submarine that may have been untrackable for the whole
  match. Firing costs it the thing that kept it alive.
- **This is why nuclear propulsion matters.** [04](04-logistics.md) already
  removes the fuel constraint for nuclear boats; here it means an SSBN can stay
  on station indefinitely, so there is no logistics tail to follow. Against a
  diesel boat there is.

## Launch, warning, and interception

**A launch is always detected.** A ballistic missile leaving the atmosphere is
the largest signature in the game — there is no stealth version of this, at any
epoch. So the defender always gets warning, and the warning always includes the
launch point.

That produces the sequence:

```
launch detected  →  origin localised  →  flight time  →  intercept window  →  impact
                    ^^^^^^^^^^^^^^^^                     ^^^^^^^^^^^^^^^^
                    the mobile launcher                  only from epoch 6
                    has just given itself away
```

**Flight time is long enough to matter** — minutes, not seconds — so the
defender has a real decision window. And the localisation is what makes
counterforce work: a mobile launcher that fires has told you where it was, and
it now has to move before the return strike arrives.

**Ballistic missile defence arrives at epoch 6**, not before, and it is
deliberately imperfect: a limited number of interceptors, each with a
probability of kill, against a target that may carry multiple warheads. It
raises the cost of a strike; it does not nullify one.

## Generations

Following the ladder pattern of [11](11-generations.md):

| Gen | Era | Change | Why it matters in play |
|---|---|---|---|
| **N1** | 1950s | Liquid fuel, fixed pad | Hours to fuel and launch. **Trivially destroyed on the ground** |
| **N2** | 1960s | Solid fuel, silo | Minutes to launch. Silo hardening arrives |
| **N3** | 1970s | First SSBNs on patrol | The survivable leg appears |
| **N4** | 1980s | MIRV | One missile, several aim points — defence arithmetic gets much worse |
| **N5** | 1990s | Road-mobile launchers | Survival by concealment rather than hardening |
| **N6** | 2000s | Quieter boats, better mobility | The detection contest tightens on both sides |
| **N7** | 2010s+ | Manoeuvring re-entry, hypersonic glide | Defeats the epoch-6 interceptor |

**N1 is worth building for the contrast.** An early-epoch strategic missile takes
so long to prepare that finding it is genuinely achievable, which teaches the
counterforce game at a difficulty the player can win. By N5 the same game is
much harder.

## Guardrails

These exist so the strategic layer does not eat the game.

**Off by default, and a match setting.** Strategic weapons are enabled per match
in the setup of [09, §4](09-ai-and-match-setup.md), alongside epoch start and
ceiling. Most matches should not include them.

**Expensive in time, not just resources.** The cost is the *window* it creates —
a long, visible build during which the opponent knows what is coming and can
act. A superweapon that arrives without warning is a feel-bad; one that arrives
after a race the loser could see coming is a story.

**Never an instant win.** A strike should remove a position, an industrial base,
or a force concentration — not the match. If the correct response to seeing an
enemy silo is to concede, the mechanic has failed.

**The AI plays counterforce with the same information.** Per
[09, §1](09-ai-and-match-setup.md), it does not know where a mobile launcher is
unless it has found it. It must fly reconnaissance, follow logistics and hunt
submarines exactly as the player does — and it can be deceived by dispersal and
by decoys, because a decoy launcher is a track backed by no entity, which the
architecture already represents.

**Tone.** Matter-of-fact. These are units with detection profiles, reload times
and counters. The game has nothing to say about their use beyond the mechanics,
and should not pretend otherwise.
