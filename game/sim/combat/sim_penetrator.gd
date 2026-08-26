class_name SimPenetrator
extends RefCounted
## The PENETRATOR half of docs/03. Pure functions, no state, no RNG.
##
## SimArmor (damage/sim_armor.gd) is the spine's half: it owns the
## armour x damage-class multiplier table and the KE range curve. This file is
## the other side of the same comparison -- what a class of penetrator can and
## cannot do at all, before any arithmetic runs.
##
## The distinction matters because docs/03's whole thesis is that a generational
## gap must be a CLIFF, not a slope. A multiplier alone can only ever produce a
## slope: give a round enough penetration and it eventually beats any number.
## Three things in docs/03 are stated as ABSOLUTE and are therefore implemented
## here as refusals rather than as multipliers:
##
##   1. "HESH ... defeated ENTIRELY by spaced/composite."  A squash head works
##      by transmitting a shock through a monolithic plate. There is nothing to
##      transmit through when the plate is a sandwich, so no HESH round of any
##      size ever defeats composite. Not a x4 multiplier -- a refusal.
##   2. Fragmentation does not defeat armour. A BLAST warhead carries no
##      penetration figure at all, and against anything with a real plate on it
##      the correct answer is "nothing happened", not "a little happened".
##   3. The frontal refusal itself: if a round cannot beat a facet at point
##      blank -- where a KE round is at its strongest -- it cannot beat it at
##      any range, ever. absolute_refusal() answers that question directly so
##      the AI and the combat log can both say "not at any range" and mean it.


## What one penetrator did to one facet, as a category rather than a number.
## The combat log and the AI's threat model both want the category; the
## resolver wants the ratio behind it.
enum Verdict {
	IMPOSSIBLE = 0,   ## the mechanism cannot work here at all. Not a near miss.
	DEFEATED = 1,     ## it could have worked, and the plate won
	MARGINAL = 2,     ## through, barely -- little energy left behind the plate
	CLEAN = 3,        ## through with margin
	OVERMATCHED = 4,  ## through with more than twice what it needed
}

## Armour types a squash head cannot work against, at any thickness.
## docs/03: "Flat; defeated entirely by spaced/composite, brutal against RHA."
const HESH_PROOF := [
	SimTypes.ArmorType.SPACED,
	SimTypes.ArmorType.NERA,
	SimTypes.ArmorType.COMPOSITE,
	SimTypes.ArmorType.COMPOSITE_HEAVY,
	SimTypes.ArmorType.MODULAR_ERA,
]

## Line-of-sight thickness beyond which fragmentation is simply irrelevant.
## Below it, a large frag warhead does defeat thin plate -- which is why
## artillery kills light vehicles and does nothing to a tank's glacis.
const FRAGMENT_DEFEATS_MM := 12.0
## Thickness above which a BLAST warhead is refused outright rather than
## resolved. Deliberately close to FRAGMENT_DEFEATS_MM: the band between them is
## where a big shell "might" open a light hull, and above it there is no maybe.
const BLAST_PROOF_MM := 25.0

## Ratio boundaries between the verdicts, as penetration / effective_mm.
const MARGINAL_RATIO := 1.25
const OVERMATCH_RATIO := 2.00


## Does this penetrator's MECHANISM work against this armour at all?
##
## Returns true when the answer is no for reasons no amount of penetration
## fixes. This is checked before the threshold comparison, and it is the reason
## a 1955 gun against 1990 composite is "qualitatively unable" rather than
## "merely weak".
static func is_immune(damage_class: int, armor_type: int, base_mm: float) -> bool:
	if base_mm <= 0.0:
		return false                      # no plate: nothing to be immune with
	match damage_class:
		SimTypes.DamageClass.HESH:
			return armor_type in HESH_PROOF
		SimTypes.DamageClass.BLAST:
			return base_mm > BLAST_PROOF_MM
	return false


## Why is_immune() said no, in words. docs/02 §9's rule applies to armour just
## as much as to weapon gating: a refusal the player cannot see the reason for
## reads as a bug.
static func immunity_reason(damage_class: int, armor_type: int) -> String:
	match damage_class:
		SimTypes.DamageClass.HESH:
			return "squash head cannot transmit a shock through %s" \
				% SimTypes.armor_type_name(armor_type)
		SimTypes.DamageClass.BLAST:
			return "fragmentation does not defeat armour"
	return "no effect"


## The penetration figure a round actually arrives with, in millimetres of RHA
## equivalent, for one SimImpact. One line, but it is the line that has to be
## identical everywhere or two callers will disagree about the KE curve.
##
## NOTE the asymmetry it carries, which is docs/03's best mechanic: KE bleeds
## with range and CE does not, so a HEAT ATGM out-penetrates a tank gun at 4 km
## and loses to it at 400 m.
static func arrival_penetration_mm(im: SimImpact) -> float:
	return SimArmor.penetration_at_range_mm(
		im.penetration_mm, im.damage_class, im.range_m)


## What the round is worth against the plate, after the class-specific floor.
##
## Only BLAST has a floor: a fragmentation warhead carries penetration_mm = 0
## because it has no penetrator, yet a 155 mm shell bursting on a truck plainly
## does something. Giving fragments a nominal RHA equivalence lets the ONE
## comparison in the resolver cover every class instead of special-casing
## warheads that have no penetration figure.
static func effective_penetration_mm(damage_class: int, penetration_mm: float,
		blast_fraction: float) -> float:
	if damage_class == SimTypes.DamageClass.BLAST:
		return maxf(penetration_mm, FRAGMENT_DEFEATS_MM * clampf(blast_fraction, 0.0, 1.0))
	return penetration_mm


## The verdict for one impact against one facet.
static func verdict(penetration_mm: float, base_mm: float, armor_type: int,
		damage_class: int, tandem := false) -> int:
	if is_immune(damage_class, armor_type, base_mm):
		return Verdict.IMPOSSIBLE
	var need := SimArmor.effective_mm(base_mm, armor_type, damage_class, tandem)
	if need <= 0.0:
		return Verdict.OVERMATCHED       # unarmoured facet: nothing to defeat
	var ratio := penetration_mm / need
	if ratio <= 1.0:
		return Verdict.DEFEATED
	if ratio <= MARGINAL_RATIO:
		return Verdict.MARGINAL
	if ratio <= OVERMATCH_RATIO:
		return Verdict.CLEAN
	return Verdict.OVERMATCHED


static func penetrated(v: int) -> bool:
	return v >= Verdict.MARGINAL


static func verdict_name(v: int) -> String:
	match v:
		Verdict.IMPOSSIBLE: return "IMPOSSIBLE"
		Verdict.DEFEATED: return "defeated"
		Verdict.MARGINAL: return "MARGINAL"
		Verdict.CLEAN: return "PENETRATED"
		Verdict.OVERMATCHED: return "OVERMATCHED"
	return "?"


## THE CLIFF QUESTION, asked directly: can this round beat this facet at ANY
## range whatsoever?
##
## KE penetration is monotonically decreasing in range, so point blank is the
## best case a kinetic round will ever have. If it fails there it fails
## everywhere, and the answer is not "unlikely" -- it is "no". CE and HESH are
## flat with range, so for them the question is range-independent by mechanism.
##
## `quoted_mm` is the published figure at 2 km, as SimMunitionDef stores it.
static func absolute_refusal(quoted_mm: float, damage_class: int,
		base_mm: float, armor_type: int, tandem := false,
		muzzle_velocity_ms := 1500.0) -> bool:
	if is_immune(damage_class, armor_type, base_mm):
		return true
	var best := SimArmor.penetration_at_range_mm(
		quoted_mm, damage_class, 0.0, muzzle_velocity_ms)
	return not SimArmor.penetrates(best, base_mm, armor_type, damage_class, tandem)


## How much of the target's structure one PENETRATING hit is worth, as a
## fraction of structure_max, before the blast falloff is applied.
##
## docs/03 is explicit that this is the small half of the model: "resolve what
## it hit, not a subtraction from a health bar." A penetration's real output is
## the component loss; this bleed exists so that repeated penetrations
## eventually finish a vehicle whose crew keep getting lucky, and so that
## unarmoured targets -- which have no components worth rolling for -- have a
## death mechanism at all.
##
## `overmatch` is SimArmor.overmatch_ratio(): 0.0 = squeaked through,
## 1.0 = arrived with twice what it needed.
static func armored_bleed_fraction(overmatch: float) -> float:
	return 0.15 + 0.50 * clampf(overmatch, 0.0, 1.0)


## The same number for the models that carry no facets. Ships are large and
## compartmented and take many hits; aircraft and trucks do not.
static func soft_bleed_fraction(damage_model: int, damage_class: int) -> float:
	var base := 0.85
	match damage_model:
		SimTypes.DamageModel.AIRFRAME: base = 0.75
		SimTypes.DamageModel.HULL: base = 0.22
		SimTypes.DamageModel.STRUCTURE: base = 0.18
	return base * class_factor(damage_class)


## Class behaviour against a target with no meaningful armour. A long rod
## punches a clean hole through a truck and keeps going; a squash head or a
## frag warhead wrecks it. This is the inversion that keeps ammunition choice
## meaningful in both directions.
static func class_factor(damage_class: int) -> float:
	match damage_class:
		SimTypes.DamageClass.KE: return 0.60
		SimTypes.DamageClass.CE: return 0.90
		SimTypes.DamageClass.HESH: return 1.00
		SimTypes.DamageClass.OVERMATCH: return 1.20
		SimTypes.DamageClass.BLAST: return 1.00
	return 1.0


## One line for the combat log, which docs/10 §10 calls "the tutorial". A
## player told "180 mm KE vs 621 mm COMPOSITE_HEAVY FRONT -- defeated" has just
## been taught the armour matrix without reading a manual.
static func describe(penetration_mm: float, base_mm: float, armor_type: int,
		damage_class: int, facet: int, tandem := false) -> String:
	var v := verdict(penetration_mm, base_mm, armor_type, damage_class, tandem)
	if v == Verdict.IMPOSSIBLE:
		return "%.0f mm %s vs %s %s -- IMPOSSIBLE (%s)" % [
			penetration_mm, SimTypes.damage_class_name(damage_class),
			SimTypes.armor_type_name(armor_type), SimTypes.facet_name(facet),
			immunity_reason(damage_class, armor_type)]
	var need := SimArmor.effective_mm(base_mm, armor_type, damage_class, tandem)
	return "%.0f mm %s vs %.0f mm %s %s%s -- %s" % [
		penetration_mm, SimTypes.damage_class_name(damage_class),
		need, SimTypes.armor_type_name(armor_type), SimTypes.facet_name(facet),
		" (tandem)" if tandem else "", verdict_name(v)]
