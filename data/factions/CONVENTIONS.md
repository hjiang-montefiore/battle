# Measurement Conventions — data/factions/*.json

Adopted 2026-08 to close the systemic finding in AUDIT.md §2: the eight files were each
internally consistent but used different measurement conventions, so every shared system
"mismatched" wholesale. One convention set, one mechanical pass. Converted fields carry a
`| conv 2026-08:` (convention normalization) or `| audit 2026-08:` (audit-directed fix) note
in `basis`. Where a correct value under the convention was not confidently known, the old
value was KEPT and the field added to `estimated_fields` with the suspected convention noted
— honesty over false precision.

## The conventions

**Mass (`mass_t`)**
- Fixed-wing aircraft and helicopters: **MTOW** (maximum takeoff weight). Rationale: it is
  the most consistently published figure across Western and Soviet references; "loaded" and
  "normal takeoff" masses are loadout-dependent and were the main source of cross-file
  mismatch (us=loaded, ru=empty). The sim can derive empty/loaded fractions per class.
- Ground vehicles: **combat-loaded mass** (as fielded, with fuel and ammunition).
- Surface ships: **full-load displacement**.
- Submarines: **submerged displacement**. (Deviation from the "surfaced" recommendation,
  deliberate: seven of eight files already used submerged figures, and submerged displacement
  is the headline figure in every reference for post-1950 boats. Only fr declared submerged
  explicitly; the rest matched it in practice. Zero-risk choice; fr unchanged.)

**Range (`road_range_km`, plus `ferry_range_km`)**
- Combat aircraft (interceptor / air_superiority / multirole / strike / cas / bomber / sead /
  stealth_strike): **combat radius**, typical hi-lo-hi loadout. Where a file's researcher had
  recorded ferry range (ru, tw, kp declared or diagnosed), the attested ferry figure was
  preserved in a new **`ferry_range_km`** field (uk already used this field) and the radius
  written into `road_range_km`, flagged estimated when the radius is not well attested.
- Support aircraft (tanker / aewc / maritime_patrol / transport / standoff EW): **maximum
  unrefuelled range** — mission radius is endurance-driven and rarely published for these;
  range is. us P-3C/P-8A converted up to range to match (de was already range).
- electronic_attack: escort jammers use combat radius; standoff platforms use range, with a
  `dims_convention`-style note where an entry knowingly keeps the platform's range figure.
- Helicopters: **maximum range on internal fuel** (all files already effectively did this).
- Ground vehicles: road range on internal fuel. **Towed pieces: null** — an APU self-move
  radius (FH-70's 20 km) is not a road range; it lives in the notes.
- Ships/submarines: cruise range at economical speed (surfaced/snorkel transit for SSKs).

**Length (`dims_m.len`)**
- Tanks and fixed-gun vehicles: **gun-forward overall length** (the silhouette the game
  renders; also the majority convention already — only ru used hull length).
- Helicopters: **fuselage length** (rotors-turning length is a function of rotor diameter,
  which is its own field now). uk/de/tw and parts of fr/cn converted.
- Ships: length overall. Aircraft: fuselage length.

**Width (`dims_m.width`) and `rotor_diameter_m`**
- Helicopters: width = **maximum airframe width excluding rotors** (stub wings count, e.g.
  AH-64 = 5.23 m); the main-rotor diameter moved to a new **`rotor_diameter_m`** field.
  Files that had stored rotor diameter in `width` (uk, de, fr, ru, kp, parts of cn) had the
  value moved, with a fuselage width filled in (estimated where not attested).
- Aircraft: wingspan. Ships: beam. Vehicles: overall width.

**Height (`dims_m.height`)**
- Ground vehicles: to hull/turret roof, excluding MGs and antennae.
- Aircraft: overall height.
- Ships **and submarines**: **draught** (navigational draft, full load; hull only — sonar
  bulb noted where it differs). Deviation from the "air draft" recommendation, deliberate:
  draught is published for every class in this dataset, while "air draft excluding masts" is
  effectively unpublished; and draught is the figure the sim needs (littoral access,
  grounding, torpedo depth). The uk/ru overall-with-sail submarine heights and de/ru
  mast heights were impossible-as-drafts (AUDIT §5) and are converted; the old value is
  preserved in the basis note. Above-water silhouette height is the art pipeline's problem
  (it has the hull models), not this dataset's.

**Deviations**: an entry that knowingly keeps a non-standard measurement carries a
`dims_convention` note field stating what its numbers mean.

## Epoch-boundary policy (adopted per AUDIT §4)

**Fielded-in-numbers**: a system entering service within ~1 year of an epoch boundary is
slotted in the epoch where it was fielded in meaningful numbers, not strictly by
`entered_service` year. The AUDIT §4 one-year boundary cases (us F-106A, us Barbel, us P-3C,
uk Saladin, ru Foxtrot/November/PT-76B/Shturm-S, tw M41/M48-era items, tw Nike Hercules e1
null, us M113 ACAV) are left where they are under this policy. Tien Kung III (svc 2015, the
last year of e6) likewise stays in e7, where its deployment ramped.

Entries a full epoch off (not boundary cases) were moved — see AUDIT §4's "genuine
violations" and the `| audit 2026-08:` notes in-file: ru BMP-3 e5→e4, us PAC-3 e6→e5,
us Ticonderoga VLS e5→e4, fr Georges Leygues e4→e3, cn KJ-500 e7→e6, cn ZBD-04A e7→e6,
fr Tiger HAD e7→e6, ru Tigr-M e7→e6. In each case the vacated slot is refilled by the same
system carried over (the historical truth — these systems all served on), and the displaced
same-epoch predecessor is recorded in the mover's basis note.

## Origin-country authority

For a shared system, the origin country's file is the reference for physical figures
(ru for Soviet exports, us for MAP/FMS deliveries, etc.); importer files align to it and note
the alignment. Applied to the AUDIT UNRESOLVED list: kp BRDM-1 (crew/speed → ru), kp M1977
(road range → ru BM-21), kp S-200 launcher mass → ru, kp Whiskey range → ru, cn HQ-2 launcher
mass → ru S-75. Exception where the origin file lost: ru Scud TEL speed raised to the
better-attested MAZ-543 55 km/h (kp's value); the losing figure is flagged estimated in place.
