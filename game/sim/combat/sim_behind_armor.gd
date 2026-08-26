class_name SimBehindArmor
extends RefCounted
## docs/03's behind-armor table: what a penetration actually HIT.
##
## "When a penetration succeeds, resolve what it hit, not a subtraction from a
## health bar." So this is the file that decides between a mobility kill, a
## firepower kill, a sensor kill, crew casualties and an ammunition fire -- and
## it decides from WHERE the round came in, because the facet is the only piece
## of information that carries real tactical meaning.
##
## docs/03 singles out one row: "Sensor kill is the most valuable row in this
## table, because it links the two big systems: a tank that survives a hit but
## loses its thermal sight is a tank that can no longer produce a fire-control
## track." That is why the weights below give optics a real share of every
## frontal hit rather than treating them as an afterthought.
##
## DETERMINISM. This is the only place in the combat subsystem that rolls, and
## it draws EXACTLY FIVE floats from the seeded stream on every call, whatever
## the outcome. Drawing a variable number would make the stream position depend
## on results, so a replay would diverge the first time a component survived a
## hit it used to lose -- the classic seeded-RNG desync, and the reason
## docs/06 wants the streams forked in the first place.
const DRAWS_PER_RESOLUTION := 5


## Probability of losing each component on a penetration THROUGH THIS FACET,
## at overmatch 0.0 and full crew efficiency. Order is
## [MOBILITY, FIREPOWER, SENSORS, CREW, CATASTROPHIC].
##
## The shape of a tank is the argument for every row:
##   FRONT  the driver, the gunner and every sight are behind it; the ammunition
##          mostly is not.
##   SIDE   the tracks, the sponsons and -- on most designs -- the ready rounds.
##          This is why flanking is not merely "thinner armour", it is a
##          qualitatively worse place to be hit.
##   REAR   the engine and the fuel. Mobility kills and fires, rarely a
##          catastrophic detonation.
##   TOP    the turret roof: crew, ammunition, and every optic on the vehicle.
##          docs/03's deliberate escape valve -- "a modern top-attack ATGM
##          carried by cheap infantry kills any MBT ever built."
##   BELLY  mines and shaped charges from below: running gear and crew.
const ARMORED_WEIGHTS := {
	SimTypes.Facet.FRONT:  [0.20, 0.30, 0.34, 0.30, 0.06],
	SimTypes.Facet.SIDE:   [0.34, 0.22, 0.14, 0.30, 0.20],
	SimTypes.Facet.REAR:   [0.55, 0.10, 0.08, 0.20, 0.10],
	SimTypes.Facet.TOP:    [0.18, 0.32, 0.40, 0.44, 0.30],
	SimTypes.Facet.BELLY:  [0.45, 0.12, 0.10, 0.38, 0.12],
}

## Aircraft and ships have components too, and they are the same three verbs:
## it cannot manoeuvre, it cannot shoot, it cannot see. Catastrophic is a
## magazine or a fuel tank. Facet is not resolved for these models -- docs/03
## says the armour matrix "does not apply to modern warships or aircraft" --
## so one weight set covers every arrival.
const AIRFRAME_WEIGHTS := [0.30, 0.20, 0.30, 0.25, 0.12]
const HULL_WEIGHTS := [0.16, 0.20, 0.26, 0.10, 0.05]
## A truck or a radar has nothing worth resolving: it works or it is wreckage.
const SOFT_WEIGHTS := [0.10, 0.10, 0.20, 0.15, 0.04]
## Buildings do not manoeuvre and have no crew to injure.
const STRUCTURE_WEIGHTS := [0.00, 0.12, 0.16, 0.00, 0.03]

## Blowout panels vent an ammunition fire upward instead of through the crew.
## docs/03 calls this "a real generational difference worth modelling", and
## docs/11 notes that a carousel autoloader structurally cannot have them.
const BLOWOUT_MULTIPLIER := 0.25

## How hard overmatch drives the whole table. At overmatch 0 -- a round that
## squeaked through -- every probability is a quarter of nominal, because a
## penetrator with nothing left behind the plate mostly rattles around. At
## overmatch 1 it is nominal.
const OVERMATCH_FLOOR := 0.25


## Roll the behind-armor effects for one penetrating impact.
##
## Returns a SimTypes.Component bitmask. Never returns NONE for a penetration
## that overmatched badly, and frequently returns NONE for one that barely got
## through -- which is exactly the "it went through and nothing important was in
## the way" outcome that makes armour interesting.
##
##   damage_model   SimTypes.DamageModel -- picks the weight set
##   facet          SimTypes.Facet, from impact geometry. NEVER re-rolled here
##   overmatch      SimArmor.overmatch_ratio(), 0..1
##   crew_efficiency 0..1. A shaken crew is slower to react and to plug holes
##   blowout        does this vehicle stow ammunition behind panels?
static func roll(rng: SimRng, damage_model: int, facet: int, overmatch: float,
		crew_efficiency: float, blowout: bool) -> int:
	var w := weights_for(damage_model, facet)
	var drive: float = OVERMATCH_FLOOR + (1.0 - OVERMATCH_FLOOR) * clampf(overmatch, 0.0, 1.0)
	# A degraded crew fights the damage worse: fires spread, a wounded loader
	# stops the gun. Never below 1.0, so a fresh crew is the baseline and not
	# a bonus.
	var crew_penalty: float = 1.0 + 0.6 * (1.0 - clampf(crew_efficiency, 0.0, 1.0))

	var mask := SimTypes.Component.NONE
	var components := [SimTypes.Component.MOBILITY, SimTypes.Component.FIREPOWER,
		SimTypes.Component.SENSORS, SimTypes.Component.CREW,
		SimTypes.Component.CATASTROPHIC]
	for k in range(DRAWS_PER_RESOLUTION):
		# The draw happens unconditionally, before any decision, so the stream
		# advances by exactly five whatever the weights say.
		var r := rng.next_float()
		var p: float = w[k] * drive * crew_penalty
		if components[k] == SimTypes.Component.CATASTROPHIC and blowout:
			p *= BLOWOUT_MULTIPLIER
		if r < p:
			mask |= components[k]
	return mask


static func weights_for(damage_model: int, facet: int) -> Array:
	match damage_model:
		SimTypes.DamageModel.ARMORED:
			return ARMORED_WEIGHTS.get(facet, ARMORED_WEIGHTS[SimTypes.Facet.SIDE])
		SimTypes.DamageModel.AIRFRAME:
			return AIRFRAME_WEIGHTS
		SimTypes.DamageModel.HULL:
			return HULL_WEIGHTS
		SimTypes.DamageModel.STRUCTURE:
			return STRUCTURE_WEIGHTS
	return SOFT_WEIGHTS


## Crew shock from a hit that did NOT get through. docs/03: a defeated round
## means "spall, crew shock, no kill" -- so it takes nothing off the structure
## pool and does degrade the crew, temporarily. Getting shot at is not free
## even when the armour holds, and this is the entire mechanical difference
## between suppressing fire and wasted ammunition.
##
## Returns the multiplier to apply to crew_efficiency. `nearness` is
## penetration / effective_mm clamped to 0..1: a round that nearly got through
## rattles the crew far harder than one that bounced.
static func shock_multiplier(nearness: float) -> float:
	return 1.0 - 0.10 * clampf(nearness, 0.0, 1.0)


## A penetration always shakes the crew, whether or not the CREW bit came up.
static func penetration_shock_multiplier(overmatch: float) -> float:
	return 1.0 - (0.12 + 0.18 * clampf(overmatch, 0.0, 1.0))


## Does this penetration start a fire? Deterministic, from geometry rather than
## a roll: the engine and the fuel are in the back, so a rear or belly
## penetration with energy behind it lights them. Keeping it out of the RNG
## keeps the five-draw budget above exact, and "shoot it in the engine deck and
## it burns" is a rule a player can learn.
static func starts_fire(damage_model: int, facet: int, overmatch: float) -> bool:
	if damage_model == SimTypes.DamageModel.STRUCTURE:
		return false
	if damage_model != SimTypes.DamageModel.ARMORED:
		return overmatch > 0.55
	return (facet == SimTypes.Facet.REAR or facet == SimTypes.Facet.BELLY) \
		and overmatch > 0.30
