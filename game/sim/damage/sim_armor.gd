class_name SimArmor
extends RefCounted
## The docs/03 armour x penetrator matrix. Pure data and pure functions, no
## state, no RNG.
##
## This file is the SPINE's half of docs/03: it fixes what an ArmorType index
## MEANS, so the damage resolver, the unit data files and the AI's threat
## assessment cannot disagree about it. The resolver itself lives in
## sim_damage.gd.
##
## docs/03's whole point is that a generational gap must be a CLIFF, not a
## slope: "If a 1955 tank physically cannot penetrate a 2015 tank from the
## front, but CAN from the side, from above, or with the right ammunition, then
## obsolescence changes how you PLAY." The comparison below is therefore a
## threshold, not a curve. There is no partial credit for nearly penetrating.
##
## Everything is in millimetres of RHA equivalent, which is a real engineering
## unit -- so the numbers stay researchable and a designer can check them
## against published figures instead of against the code's own taste.


## effectiveness[armor_type][damage_class] as a multiplier on base thickness.
## Rows are SimTypes.ArmorType, columns SimTypes.DamageClass in enum order:
## KE, CE, HESH, OVERMATCH, BLAST. The KE and CE columns are docs/03's table
## verbatim; HESH and OVERMATCH are the two extra classes docs/03 names but does
## not tabulate, filled in from the mechanism it describes for each.
const EFFECTIVENESS := {
	# type                              KE     CE    HESH   OVER  BLAST
	SimTypes.ArmorType.NONE:           [0.00, 0.00, 0.00, 0.00, 0.00],
	SimTypes.ArmorType.CAST:           [0.95, 0.95, 0.90, 0.80, 1.00],
	SimTypes.ArmorType.RHA:            [1.00, 1.00, 1.00, 0.85, 1.00],
	SimTypes.ArmorType.SPACED:         [1.10, 1.60, 3.00, 0.90, 1.20],
	SimTypes.ArmorType.NERA:           [1.15, 1.90, 3.20, 0.90, 1.30],
	SimTypes.ArmorType.COMPOSITE:      [1.30, 2.20, 4.00, 0.95, 1.50],
	SimTypes.ArmorType.COMPOSITE_HEAVY:[1.60, 2.60, 4.00, 1.00, 1.60],
	SimTypes.ArmorType.ERA_LIGHT:      [1.05, 2.50, 1.10, 0.85, 1.10],
	SimTypes.ArmorType.ERA_HEAVY:      [1.25, 2.80, 1.20, 0.90, 1.20],
	SimTypes.ArmorType.MODULAR_ERA:    [1.75, 3.00, 4.00, 1.05, 1.70],
}

## HESH is "defeated entirely by spaced/composite, brutal against RHA"
## (docs/03). The multipliers above express that: 1.00 against RHA, 3-4x against
## anything with a gap or a matrix in it.

## The reactive types. docs/03: ERA is "defeated OUTRIGHT by tandem warheads,
## whose precursor charge detonates the reactive block before the main jet
## arrives". So this is not a modifier -- it deletes the multiplier.
const REACTIVE := [
	SimTypes.ArmorType.ERA_LIGHT,
	SimTypes.ArmorType.ERA_HEAVY,
	SimTypes.ArmorType.MODULAR_ERA,
]

## The armour a reactive package falls back to once its precursor has stripped
## it. Modular composite + ERA is still composite underneath; a bolt-on light
## ERA block over a 1970s hull is not.
const REACTIVE_BASE := {
	SimTypes.ArmorType.ERA_LIGHT: SimTypes.ArmorType.RHA,
	SimTypes.ArmorType.ERA_HEAVY: SimTypes.ArmorType.RHA,
	SimTypes.ArmorType.MODULAR_ERA: SimTypes.ArmorType.COMPOSITE,
}

## docs/03: KE "falls with range -- velocity bleeds off"; CE is "flat with
## range -- chemistry, not velocity". Published penetration figures are quoted
## at 2 km, so that is the reference.
const KE_REFERENCE_RANGE_M := 2000.0
## Fraction of quoted penetration a long rod retains per kilometre beyond the
## reference. Roughly 3% per km, which is the right order for a modern APFSDS
## and steeper for the low-velocity early rounds -- see ke_retention().
const KE_LOSS_PER_KM := 0.030


## The multiplier this armour type applies to a given damage class.
static func effectiveness(armor_type: int, damage_class: int) -> float:
	var row: Array = EFFECTIVENESS.get(armor_type, EFFECTIVENESS[SimTypes.ArmorType.NONE])
	if damage_class < 0 or damage_class >= row.size():
		return 1.0
	return row[damage_class]


static func is_reactive(armor_type: int) -> bool:
	return armor_type in REACTIVE


## What the round actually has to beat, in millimetres of RHA equivalent.
##
##   effective_mm = base_thickness_mm x effectiveness[armor_type][damage_class]
##
## `tandem` is the docs/03 ERA counter: a precursor charge detonates the
## reactive block, so the main jet meets whatever is underneath instead. It has
## no effect on non-reactive armour, which is why a tandem warhead is a
## specialist rather than a straight upgrade.
static func effective_mm(base_mm: float, armor_type: int, damage_class: int,
		tandem := false) -> float:
	var a := armor_type
	if tandem and is_reactive(a):
		a = REACTIVE_BASE.get(a, SimTypes.ArmorType.RHA)
	return base_mm * effectiveness(a, damage_class)


## Fraction of quoted penetration a KE round still has at a given range. CE,
## HESH and OVERMATCH return 1.0 -- flat with range, by mechanism.
##
## `muzzle_velocity_ms` steepens the curve for the slow early rounds: a 1950s
## APCR shot loses its advantage in a few hundred metres, while a modern long
## rod barely notices two kilometres. That is the same asymmetry docs/03 calls
## "quietly one of the best mechanics available here".
static func ke_retention(damage_class: int, range_m: float,
		muzzle_velocity_ms := 1500.0) -> float:
	if damage_class != SimTypes.DamageClass.KE:
		return 1.0
	var steepness: float = clampf(1500.0 / maxf(muzzle_velocity_ms, 200.0), 0.6, 3.0)
	var km_beyond := (range_m - KE_REFERENCE_RANGE_M) / 1000.0
	return clampf(1.0 - KE_LOSS_PER_KM * steepness * km_beyond, 0.25, 1.60)


## Penetration in millimetres of RHA equivalent, at the range the round
## actually arrived at. `quoted_mm` is the published figure at 2 km.
static func penetration_at_range_mm(quoted_mm: float, damage_class: int,
		range_m: float, muzzle_velocity_ms := 1500.0) -> float:
	return quoted_mm * ke_retention(damage_class, range_m, muzzle_velocity_ms)


## THE comparison. docs/03: "if penetration_mm > effective_mm -> penetrated,
## apply behind-armor effects; else -> defeated (spall, crew shock, no kill)."
## A threshold, deliberately. No roll, no partial credit.
static func penetrates(penetration_mm: float, base_mm: float, armor_type: int,
		damage_class: int, tandem := false) -> bool:
	return penetration_mm > effective_mm(base_mm, armor_type, damage_class, tandem)


## How far past the plate the penetrator got, as a fraction of what it needed.
## 0.0 = exactly defeated, 1.0 = twice the armour it faced. Behind-armor
## severity scales with this, so overmatching a thin side gives a worse result
## for the target than squeaking through a thick front.
static func overmatch_ratio(penetration_mm: float, base_mm: float,
		armor_type: int, damage_class: int, tandem := false) -> float:
	var need := effective_mm(base_mm, armor_type, damage_class, tandem)
	if need <= 0.0:
		return 1.0
	return clampf((penetration_mm - need) / need, 0.0, 1.0)


## Readable one-liner for the combat log, which docs/10 §10 calls "the
## tutorial". A player who is told "180 mm APFSDS vs 624 mm composite FRONT --
## defeated" learns the armour matrix without a manual.
static func describe_impact(penetration_mm: float, base_mm: float,
		armor_type: int, damage_class: int, facet: int, tandem := false) -> String:
	var need := effective_mm(base_mm, armor_type, damage_class, tandem)
	var verdict := "PENETRATED" if penetration_mm > need else "defeated"
	return "%.0f mm %s vs %.0f mm %s %s%s -- %s" % [
		penetration_mm, SimTypes.damage_class_name(damage_class),
		need, SimTypes.armor_type_name(armor_type), SimTypes.facet_name(facet),
		" (tandem)" if tandem else "", verdict]
