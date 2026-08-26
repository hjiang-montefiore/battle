# Reference Images

Downloaded for modelling reference only. Used to correct proportions and identify
silhouette features; **no geometry is traced or derived from the pixels.**

Dimensions used for the models come from published specifications (facts, not
copyrightable), cross-checked against these photographs. See `tools/hero_models.py`,
`tools/fleet_models.py`, `tools/army_models.py` and `tools/air_models.py` for the numbers
actually applied.

## Why most of these are free to redistribute

Works produced by U.S. Government employees as part of their official duties are not
subject to copyright in the United States — **17 U.S.C. § 105**. Every U.S. military
public-affairs photograph below falls under that provision. Several carry an explicit
`Copyright: Public Domain` EXIF tag as well, and the DoD-released ones are marked
`(Released)` in their caption.

---

## Verified — attribution recorded in the file's own metadata

| File | Subject | Credit | Basis |
|---|---|---|---|
| `ref_apache.jpg` | AH-64D Longbow Apache, 1-101st Aviation Regt., over FOB Speicher, Iraq, 21 Oct 2005 | Tech. Sgt. Andy Dunaway, U.S. Air Force | DoD photo `051021-F-2828D-284`, caption marked *(Released)* |
| `ref_bradley.jpg` | M2 Bradley, 1st ABCT / 1st Infantry Div., Żagań, Poland | Sgt. Joseph Aleman, U.S. Army | EXIF `Copyright: Public Domain` |
| `ref_hemtt.jpg` | M978 HEMTT refuelling a CH-47, 1-214th Aviation Regt., Kajaani Airfield, Finland | 1st Sgt. Austin Berner, U.S. Army Reserve | EXIF `Copyright: Public Domain` |
| `ref_m270.jpg` | M270 MLRS, C Btry. 6-37 FA / 210th FA Bde. / 2nd Infantry Div., near Cheorwon, South Korea | U.S. Army (photographer not named in metadata) | EXIF `Copyright: Public Domain` |
| `ref_stryker.jpg` | Stryker ICV, 4th Sqn. 2nd Cavalry Regt., Dresden Military Museum, Germany, 31 May 2016, Dragoon Ride II | Staff Sgt. Ricardo Hernandez-Arocho, U.S. Army | Caption marked *(Released)* |

## Verified — sourced from Wikimedia Commons

| File | Subject | Source | Licence |
|---|---|---|---|
| `m1a2_side.jpg` | M1A2 SEPv3, side | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Cav._M1A2_SEPv3.jpg) | Public domain |
| `t72_side.jpg` | T-72A on parade | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:T-72A_tank_on_parade.jpg) | Public domain |
| `leo2a6_side.jpg` | Leopard 2A6M, left side | [Wikimedia Commons](https://commons.wikimedia.org/wiki/File:Leo2A6M_li.jpg) | Public domain |

## Unverified — provenance not recorded

These four carry **no EXIF, IPTC or XMP metadata at all**, so their origin cannot be
confirmed from the files themselves. They are very probably U.S. military public-affairs
photographs like the rest, but that is an assumption, not a verified fact.

| File | Subject | Status |
|---|---|---|
| `ref_a10.jpg` | A-10 Thunderbolt II | Source unconfirmed |
| `ref_e3.jpg` | E-3 Sentry AWACS | Source unconfirmed |
| `ref_f16.jpg` | F-16 Fighting Falcon | Source unconfirmed |
| `ref_m109.jpg` | M109 self-propelled howitzer | Source unconfirmed |

**Before relying on these**, trace each back to its origin and record it here — or replace
it with an equivalent from Wikimedia Commons or a DoD public-affairs site, where the
licence is stated at the source. This repository is public and MIT-licensed, so an image
of unknown provenance in it is a liability that the modelling work does not need: these
are proportion references, and a confirmed-free substitute serves exactly as well.

---

## Adding a reference

1. Prefer a source that states its licence — Wikimedia Commons, `defense.gov`, or a
   service public-affairs site.
2. Keep the original file's metadata. It is the attribution, and stripping it is what
   turns a usable photograph into one of the four rows above.
3. Add a row here with the credit and the basis for reuse, before committing the image.
