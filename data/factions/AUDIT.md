# Faction Data Cross-Check Audit

Adversarial cross-check of the eight files in `data/factions/` (us, uk, de, fr, cn, ru, tw, kp),
run 2026-08-26. Epoch boundaries per docs/05: e1 1950-59, e2 1960-69, e3 1970-79, e4 1980-89,
e5 1990-2004, e6 2005-15, e7 2016-present. Role epoch windows per `sim_roster.gd`
(`first_epoch`: ifv 3, shorad_sam 3, medium_sam_launcher 2, tanker 2, aewc 3, ssbn 3, ...).

## 1. Parse

All eight files parse as JSON. Entry counts (filled / explicit-null):
us 199/24 · uk 179/49 · de 159/65 · fr 113/153 · cn 183/57 · ru 232/27 · tw 150/86 · kp 78/89.
Total 1,293 filled entries.

Structural variation (harmless but worth knowing): inheritance is marked three ways —
uk uses `inherited_from_epoch` + `changes` and `cross_reference` (for the same airframe filling
two roles), cn uses `carryover_from` + `upgrade_note`, everyone else repeats the full entry with
the original `entered_service` and "(carried over)" in the designation. A loader must handle all
three.

## 2. Shared systems — the systemic finding

**The files are internally consistent but use different measurement conventions**, so the same
system fielded by two factions "mismatches" wholesale. This is the single biggest issue in the
dataset and needs one project-wide convention decision, not per-entry fixes:

| Convention | us | uk | de | fr | cn | ru | tw | kp |
|---|---|---|---|---|---|---|---|---|
| Aircraft mass | loaded | loaded/MTOW mixed | MTOW | MTOW-ish | MTOW | **empty** | **MTOW** (declared) | **MTOW** |
| Aircraft range | combat radius | mixed/absent | mixed | radius-ish | mixed | ferry | **ferry** (declared) | ferry |
| Helicopter length | fuselage | rotors-turning | rotors-turning | fuselage | mixed | fuselage | rotors-turning | rotors-turning |
| Helicopter width | fuselage | rotor diameter | rotor diameter | rotor diameter | — | rotor diameter | fuselage | rotor diameter |
| Ship/sub "height" | draft-ish | overall w/ sail | **mast height** | mixed | draft | **overall w/ sail / mast** | draft (declared) | draft |
| Tank length | mostly gun-forward | hull | gun-forward | hull | gun-forward | **hull** | gun-forward | gun-forward |

Concrete examples of the same system differing only by convention (NOT corrected — needs the
convention decision first):

- **F-16**: us F-16C mass 12.0 t / range 550 km (loaded, radius) vs tw F-16A/B 19.2 t / 4,220 km (MTOW, ferry).
- **F-4 Phantom**: us F-4B 18.8 t (loaded) vs de F-4F 28.0 t (MTOW) vs uk FG.1 25.4 t.
- **MiG-29**: ru 11.0 t (empty) vs kp 18.0 t (MTOW). Same for MiG-23 (10.9/17.8), Su-25 (9.8/17.6), MiG-21F-13 (4.87/8.6), MiG-15bis (3.68/6.1), Su-27 (ru 16.4 vs cn 23.4).
- **Il-28/H-5**: ru 12.89 t (empty) vs cn 21.2 t vs kp 23.2 t (MTOW). **Tu-16/H-6**: ru 37.2 t (empty) vs cn 76-79 t (MTOW).
- **AH-64E**: us len 15.06 (fuselage) vs tw/uk 17.73 (rotors turning); widths 5.23 / 3.66 / 14.63 are three different measurements (stub-wing span, fuselage, rotor diameter).
- **UH-1D**: us 12.77 m vs de 17.4 m (rotors); de also crew 2 vs us/tw 3.
- **T-54 family**: ru T-54 len 6.45 (hull) vs cn Type 59 9.0 / kp 9.0 (gun forward). Same for T-62/Ch'onma (6.63 vs 9.34), PT-76 (6.91 vs 7.63).
- **Submarines**: ru Kilo height 14.7 / Delta IV 24 / uk Astute 13 (overall incl. sail) vs kp Whiskey 4.9 / tw Hai Shih 5.2 (draft). de Fletcher height 30.0 and ru Sovremenny 38.0 are mast heights.

**Recommendation**: fix the convention as *normal takeoff / combat-loaded mass, combat radius,
fuselage length + rotor diameter as width, waterline length + draft as height*, then run one
mechanical normalization pass. tw and kp declare their conventions in `source_notes`, which made
this diagnosable — every file should.

### Genuine value mismatches (same system, same convention, different numbers)

- ~~de HAWK/I-HAWK mass 0.59-0.63 t~~ — was the **missile round**, not the launcher. **CORRECTED** to us launcher figures (5.1×2.2×2.1 m, 3.5 t) in de e2-e5.
- ~~de Patriot mass 0.32-0.9 t, dims 5.31×0.41~~ — again the missile. **CORRECTED** to us M901 launcher figures (10.0×2.9×3.2 m, 24 t) in de e4-e7.
- ~~fr HAWK 6.0 t, tw HAWK 2.2 t~~ — **CORRECTED** to the us 3.5 t launcher figure (same M192 launcher).
- ~~tw Patriot PAC-3 35 t, 17 m~~ — **CORRECTED** to us launcher figures.
- ~~tw M48A1 road range 180 km~~ — us has the well-attested 113 km; **CORRECTED** (tw file had it as an estimate).
- kp BRDM-1 crew 2 / speed 90 vs ru crew 5 / speed 80 — sources genuinely disagree (2+3 scouts); needs a reference. NOT corrected.
- kp M1977 (BM-21 copy) road range 500 vs ru BM-21 750 — needs a reference (Ural-375D chassis figures vary 405-750). NOT corrected.
- kp S-200 launcher mass 10 t vs ru 16 t; kp Scud TEL speed 55 vs ru 45 (MAZ-543 does ~55-60, ru is conservative). Needs reference.
- kp Whiskey range 11,000 km vs ru 16,000 km (surfaced transit) — needs reference.
- de M109G range 390 vs us M109 350 — plausibly real (different engine/fuel), low priority.
- FH-70: de svc 1978 vs uk svc 1980 — the trinational gun entered UK service ~1978 first; uk's 1980 is late but within reason for full fielding. uk gives road_range 20 km — that is the *auxiliary power unit* self-move radius, and de leaves it null; pick one meaning for towed pieces with APUs.
- HQ-2/S-75 launcher: cn mass 2.3 t (missile) vs ru 8.0 vs kp 7.1 — cn is the missile round; same class of error as the de HAWK entries but the cn entry is already flagged low-detail. Recommend aligning cn to ru at the reference pass.
- Missing dims on cn imported systems (Tor-M1, S-300PMU, Kilo, Whiskey, Type 033, Sovremenny, S-70C, Mi-17, Gazelle, HY-6) — **CORRECTED**: filled from the origin faction's file for the identical system, marked in `estimated_fields` with basis notes.

Systems verified consistent across users: M113 family, M270 MLRS (all four users within 0.3 t),
M109 core figures, F-104G core figures, Tornado, Typhoon, E-3, E-2, P-3C, P-8A, F-84F,
BTR-60PB, ZSU-57-2, ZSU-23-4, BMP-1, Osa/Komar lineages, Nike Hercules, M42 Duster,
Knox/Gearing hulls, MIM-72 Chaparral, FH-70 core, Tiger helicopter (de/fr), M47.

## 3. Lineage sanity

- **cn**: pre-2000 entries correctly track Soviet designs (Type 59=T-54A 1959, J-5/J-6/J-7 lineage,
  H-5/H-6, Type 033/03, HQ-2), with the historically real 1980s Western window (S-70C Black Hawks
  1985, Gazelle+HOT 1988, HQ-7/Crotale) honestly marked as imports. The J-6's 1962 date (after
  Soviet MiG-19 but delayed by the Great Leap quality collapse) is right. PASS.
- **kp**: the freeze holds. Every post-e4 fighter/armor entry is either the 1984-88 Soviet package
  or indigenous parade kit (Songun-915, M2020, Bulsae, KN-series, Nongo/Amnok/Choe Hyon) at
  low confidence — no implausible acquisitions found. PASS.
- **tw**: mostly US-supplied or indigenous, with three historically genuine non-US exceptions a
  reviewer should not "fix": Mirage 2000-5EI (France 1997), Hai Lung SSKs (Dutch Zwaardvis
  design 1987-88), Yung Feng MHCs (German MWV-50 design 1991). These are correct history and
  should stay. One real error found: the file listed **F-104G at svc 1960** — the G model did not
  exist until 1961-63; the ROCAF's 1960 batch was F-104A/B. **CORRECTED** (e2 renamed
  F-104A, e3/e4 F-104G moved to 1964).
- **Export-precedes-origin scan**: after the F-104 fix, no faction fields an export before the
  origin country's entry (checked every shared family: HAWK, Nike, Patriot, M-series vehicles,
  F-84/100/104/4/5/16, MiG-15/17/19/21/23/29, Su-25/27, Mi-4/8/24, T-54/55/62,
  BMP/BTR/BRDM, Whiskey/Romeo/Kilo, S-75/125/200/300, Scud, Il-28, Tu-16).

## 4. Epoch sanity

Three benign classes first (NOT violations):

1. **Roster-window clamps**: systems that entered service before a role's `first_epoch` are
   clamped forward (us KC-135A 1957 → tanker e2; us Chaparral 1969 → shorad e3; uk Resolution
   1967 → ssbn e3; several de/fr e1 items). Correct behavior.
2. **Pre-1950 floor**: uk 25-pounder (1940), Sexton (1943), ru T-54 (1949), Kronshtadt (1948),
   fr Arromanches (1946) — WWII kit retained into e1. Correct.
3. **Upgrade entries carrying their variant's own year** (docs/11 ladder pattern): us M777A2 in
   e7 (svc 2006), Ticonderoga hulls in e5-e7, A-10A in e4, Barbel repeated e3-e4, etc. Correct.

**Genuine violations / off-by-ones** (flagged, not moved — moving epochs is a design decision):

| Entry | svc | placed | belongs |
|---|---|---|---|
| ru ifv e5 BMP-3 | 1987 | e5 | e4 (a full epoch off; e4 holds BMP-2 — needs designer call) |
| us long_sam e6 Patriot PAC-3 | 2003 | e6 | e5 (PAC-3 IOC 2001-03) |
| us cruiser e5 Ticonderoga VLS | 1986 | e5 | e4 (Bunker Hill 1986) |
| fr asw_frigate e4 Georges Leygues | 1979 | e4 | e3 |
| cn aewc e7 KJ-500 | 2015 | e7 | e6 |
| cn ifv e7 ZBD-04A | 2013 | e7 | e6 |
| fr attack_helicopter e7 Tiger HAD | 2013 | e7 | e6 |
| ru recon e7 Tigr-M | 2013 | e7 | e6 |
| tw medium+long_sam e7 Tien Kung III | 2015 | e7 | e6 boundary |
| us interceptor e2 F-106A | 1959 | e2 | e1 (one year) |
| us ssk e2 Barbel | 1959 | e2 | e1 (one year) |
| us recon e3 M113 ACAV | 1968 | e3 | e2 |
| us maritime_patrol e3 P-3C | 1969 | e3 | e2 (one year) |
| uk recon e2 Saladin | 1959 | e2 | e1 (one year) |
| ru ssk e2 Foxtrot | 1958 | e2 | e1 |
| ru ssn e2 November | 1959 | e2 | e1 (one year) |
| ru light_tank e2 PT-76B | 1959 | e2 | e1 (one year) |
| ru atgm e4 Shturm-S | 1979 | e4 | e3 (one year) |
| tw light_tank e2 M41 | 1958 | e2 | e1 |
| tw long_sam e2 Nike Hercules | 1959 | e2 | e1 (e1 is currently an explicit null) |

Two label oddities: ru sead e5 "Su-24M + Kh-58U" (svc 1983) *predates* the e4 sead entry
(MiG-25BM, 1988) — a ladder inversion worth a designer look; ru missile_boat e5 "Tarantul III"
carries the Tarantul-I year 1981 (the III entered ~1987).

Most one-year cases are systems that entered service in the last months of a decade and are
reasonably slotted where they were fielded *in numbers*; recommend accepting them and noting the
policy explicitly in each file's `source_notes`.

## 5. Physics smell test

Everything that looked absurd traced back to the Section-2 convention split rather than bad data:

- KC-10A 267.6 t = MTOW (correct); kp Po-2 "bomber" 1.35 t (correct, it is a biplane);
  GAZ Tigr family 140 km/h (manufacturer top speed, plausible); Wiesel 1 at 2.75 t (correct,
  air-droppable); Type 022 at ~220 t missile boat (correct).
- The only class-norm violations are the "height" fields on ru/uk submarines (13-24 m = overall
  incl. sail), de Fletcher (30 m = mast) and ru Sovremenny (38 m = mast) — impossible as drafts,
  fine as overall heights. Normalize per Section 2.
- No 70 t IFVs, no impossible-epoch speeds (fastest e1 aircraft: uk Hunter 1,150 km/h, us
  F-100 family 1,390 — both real; every 2,300+ km/h airframe is e2+).

## 6. Honesty ledger

Confidence across 1,293 filled entries: **high 544 · medium 580 · low 169**.

Per file (high/medium/low): us 126/65/8 · uk 115/55/9 · de 61/82/16 · fr 42/60/11 ·
cn 41/114/28 · ru 104/104/24 · tw 44/62/44 · kp 11/38/29.

kp and tw are the weakest files, exactly where the source base is weakest (parade analysis,
transfer records) — the uncertainty is honestly distributed.

**Top 20 entries most needing a reference pass** (low confidence, most estimated fields):

1. kp air_defence_destroyer e7 — Choe Hyon-class (8 estimated fields; 2025 unveiling)
2. kp shorad_sam e7 — M2020 gun/missile system (7)
3. kp long_sam e7 — Pon'gae-5 / KN-06 battery (7)
4. kp missile_boat e6 — Nongo-class VSV (7)
5. kp ssbn e7 — Hero Kim Kun Ok (Sinpo-C) (7)
6. tw ssk e7 — Hai Kun class IDS (6; commissioning still settling)
7. kp mbt e7 — M2020 MBT (6)
8. kp atgm_carrier e5 — Bulsae-2 truck carrier (6)
9. kp atgm_carrier e7 — Bulsae-4 M2018 NLOS (6)
10. kp sph e7 — M2018 152mm SPH (6)
11. kp spaag e5 — M1992 twin 30mm (6)
12. kp shorad_sam e4 — Igla/HN-5 vehicle mounts (6)
13. kp corvette e7 — Amnok-class (6)
14. uk mbt e7 — Challenger 3 (5; programme figures, ISD ~2027)
15. de spaag e7 — Skyranger 30 (5; entering service)
16. tw mlrs e4/e5 — Kung Feng VI (5)
17. tw shorad_sam e7 — Land Sword II (5)
18. kp mbt e6 — Songun-915 (5)
19. kp light_tank e4 — M1981 Shin'heung (5)
20. kp apc e6 — M2010 8x8 (5)

(Honourable mentions: the entire kp parade layer, tw early-epoch ex-US transfers — M8 Greyhound,
M3A1 half-track, V-150 — which tw itself calls its weakest entries, and cn recon vehicles.)

## 7. Corrections written in this pass (30 entries)

All marked in-file with `estimated_fields` additions and an `| audit 2026-08:` basis note.

- **cn** (10): dims (and mass where missing) filled from origin-faction files for identical
  imported systems — Tor-M1, S-300PMU TEL, Kilo, Whiskey/Type 03, Type 033, Sovremenny,
  S-70C, Mi-17, Gazelle, HY-6 (Tu-16 airframe).
- **de** (8): HAWK e2-e5 and Patriot e4-e7 had *missile-round* dims/mass in a *launcher* role;
  replaced with us.json launcher figures.
- **fr** (2) / **tw** (6): HAWK and Patriot launcher figures aligned to us.json (same launcher
  hardware; shared-system rule).
- **tw** (4): M48A1 road range 180→113 km (us benchmark value); F-104 "G-in-1960"
  impossibility fixed (e2 → F-104A, e3/e4 svc → 1964).

## 8. What still needs a decision (not fixable by an auditor)

1. The **measurement-convention normalization** (Section 2) — one decision, one mechanical pass.
2. The **BMP-3 epoch slot** and the other ladder off-by-ones (Section 4) — epoch placement is a
   design lever (docs/05: entry epoch gates availability), so a designer should move them.
3. The kp/ru **BRDM-1, BM-21, S-200, Scud, Whiskey** stat disagreements — need references.
4. Whether tw long_sam e1 should hold Nike Hercules (svc 1959) instead of the current null.
