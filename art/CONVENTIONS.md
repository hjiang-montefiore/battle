# Art Conventions

Binding rules for every model in this project, blockout or finished. The pipeline
([../docs/07-art-pipeline.md](../docs/07-art-pipeline.md)) depends on them, and
`tools/validate_sockets.py` enforces the ones that can be checked automatically.

## Axes, units, scale

| | |
|---|---|
| Axes | **+X right · +Y up · −Z forward** (glTF and Godot 4 native) |
| Units | **Metres, 1:1 with the real vehicle.** No scale factor on import |
| Origin | Centre of the hull footprint, **on the ground plane** (`Y = 0`) |
| Facing | The gun points down **−Z** at zero traverse and zero elevation |

Origin-on-ground is not cosmetic: it means a unit placed at a terrain height sits on
it, with no per-model offset. `validate_sockets.py` fails any model with geometry
below `Y = −0.02`.

## The socket contract

Every armoured vehicle carries these nine, exported as empty nodes named `SOCKET_<name>`:

```
turret_mount    gun_mantlet    sensor_mast    exhaust
track_left      track_right
damage_hull     damage_turret  damage_track
```

Plus optional numbered groups, `SOCKET_<group>_<n>`, 1-indexed:

```
era_plate_1..6      reactive armour blocks       → docs/03, docs/11
aps_launcher_1..4   active protection launchers  → docs/03
hardpoint_1..4      stowage, aerials, generic
```

**Sockets are the contract between art and simulation.** The upgrade system in
[../docs/11-generations.md](../docs/11-generations.md) attaches visible parts at them
at runtime, so a player can read a tank's generation off its silhouette before
deciding to engage it frontally. A missing socket is a build failure, not a warning.

Every derivative in a bucket inherits its hero's socket set **at the same names**.
That is what makes a variant cost geometry and texture work but never rigging work.

## Naming

```
art/blockout/<bucket>/<unit>_LOD<n>.glb

bucket   <epoch>_<role>_<lineage>     e4_mbt_western
unit     <role>_<epoch>_<faction>     mbt_e4_us
         <role>_<epoch>_<lineage>_hero  for the bucket hero
```

Faction codes: `us uk de fr cn ru tw kp`. Lineages: `western soviet chinese`.

## LODs

| Level | Use | Triangle budget | Rule |
|---|---|---|---|
| LOD0 | Close inspection, selection | 30–60 k | Hero only; derivatives inherit |
| **LOD1** | **Normal gameplay zoom** | **8–15 k** | **Budget the effort here** |
| LOD2 | Zoomed out | 2–4 k | Silhouette must survive intact |
| LOD3 | Strategic view | Impostor | Symbol legibility over form |

Blockouts sit far under budget (~100–400 triangles). That is expected — they carry
proportion, silhouette and sockets, nothing else.

## Materials

One material and one texture atlas **per bucket**, so an epoch's entire armoured force
renders in a handful of draw calls via GPU instancing. At RTS unit counts this is a
requirement, not an optimisation.

Team colour goes on a **dedicated mask channel**, on large flat areas visible from
directly above — the blockouts mark that area in orange.

## Silhouette

Read [../docs/07-art-pipeline.md](../docs/07-art-pipeline.md) first. The short version:
**design in silhouette before detailing, and check every derivative at gameplay zoom in
solid black.** If two units are confusable in silhouette, one of them is wrong no matter
how good the model is.

Two silhouette facts the blockouts already carry, both real and both readable:

- **A 1950s tank is taller than a 1980s Soviet tank** — 3.09 m against 2.22 m. Post-war
  designs inherited WWII height; everyone got low afterwards.
- **Western Gen 3.5 turrets are long, flat and angular; Soviet ones are low, small and
  domed** — a consequence of the autoloader and a three-man crew.

## Replacing a blockout

Blockouts are proxies, not art. To replace one:

1. Model the real asset to the same overall dimensions (within ~5%).
2. Keep the **origin, axes and every socket name** identical.
3. Export `.glb` to the same path.
4. Run `python3 tools/validate_sockets.py` — it must pass.

Nothing downstream changes. The simulation references ladder positions and socket
names, never geometry.

## Regenerating

```bash
python3 tools/build_assets.py      # rebuild every blockout + art/BUILD_REPORT.md
python3 tools/validate_sockets.py  # CI gate: sockets, scale, ground plane
```

Edit the `BUCKETS` manifest at the top of `tools/build_assets.py` to add units. No
Blender required — the writer is pure stdlib.
