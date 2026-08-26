class_name SimDamage
extends RefCounted
## docs/03, and the seam where docs/10 finally has consequences.
##
## ══ THIS IS A STUB. ══
## Every function below is a declared contract with a no-op or neutral body.
## Nothing in this file kills anything yet. It exists so that the tick order in
## sim_world.gd has a real slot to call, so the other three subsystems can
## compile against a stable API, and so the damage agent fills in bodies rather
## than negotiating signatures. Each stub says what it MUST do.
##
## OWNERSHIP: this class is the only writer of `structure`, `components`,
## `crew_efficiency` and `alive`. Nothing else may call entities.kill().
##
## The armour matrix it resolves against is already real -- see sim_armor.gd.


## What one impact did. Returned by resolve_impact() so the combat log can say
## WHY, which docs/10 §10 insists is the point of the whole exercise.
class Outcome extends RefCounted:
	var resolved: bool = false      ## false while SimDamage is a stub
	var penetrated: bool = false
	var facet: int = SimTypes.Facet.FRONT
	var effective_mm: float = 0.0   ## what the round had to beat
	var penetration_mm: float = 0.0 ## what it arrived with
	var components_lost: int = SimTypes.Component.NONE
	var structure_lost: float = 0.0
	var killed: bool = false
	var reason: String = "damage model not implemented"

	func _to_string() -> String:
		return reason


var entities: SimEntities
var rng: SimRng
## Append-only, capped. Same shape as SimMunitions.combat_log so the HUD can
## merge the two into one stream.
var combat_log: Array = []
var max_log: int = 200
var kills: int = 0
var penetrations: int = 0
var defeats: int = 0


## The damage layer gets the entity store because it resolves against GROUND
## TRUTH -- docs/09 §1.4: "The projectile resolves against reality; the shooter
## never needed to know." This is the one module that is SUPPOSED to see
## everything, and it is precisely why the AI is a different module.
func _init(store: SimEntities, seeded: SimRng) -> void:
	entities = store
	rng = seeded


# ═══════════════════════════════════════════════════════════════════════════
# THE API. Signatures are final; bodies are the damage agent's job.
# ═══════════════════════════════════════════════════════════════════════════

## Resolve one arriving round against one unit. THE central function.
##
## MUST: pick the facet from `facet` (which SimProjectile.impact_facet() derived
## from impact geometry -- never re-roll it); run APS first (docs/03: "APS is
## NOT an armor multiplier, it resolves BEFORE the armor calculation"); compute
## effective_mm via SimArmor; compare as a threshold; on a penetration choose a
## behind-armor effect weighted by overmatch_ratio and crew_efficiency; on a
## defeat apply crew shock and nothing else. It MUST NOT subtract structure on a
## defeat -- that is the slope docs/03 exists to avoid.
##
##   target          entity index, ground truth
##   facet           SimTypes.Facet, from impact geometry
##   damage_class    SimTypes.DamageClass
##   penetration_mm  RHA equivalent AT THE ARRIVAL RANGE, already range-adjusted
##                   by SimArmor.penetration_at_range_mm()
##   blast_fraction  0..1 from SimProjectile.damage_fraction(); 1.0 on a direct
##                   hit, tapering to 0 at the edge of the lethal radius
##   tandem          precursor charge -- strips ERA (docs/03)
func resolve_impact(target: int, facet: int, damage_class: int,
		penetration_mm: float, blast_fraction: float = 1.0,
		tandem: bool = false) -> Outcome:
	var o := Outcome.new()
	o.facet = facet
	o.penetration_mm = penetration_mm
	return o


## Take `amount` off a unit's structure pool. For AIRFRAME, HULL, UNARMORED and
## STRUCTURE targets, and for the behind-armor bleed on an ARMORED one.
## Returns true if this call killed it. MUST call entities.kill() on zero.
func apply_structure(target: int, amount: float, cause: String = "") -> bool:
	return false


## Hard-kill APS intercept attempt, docs/03. MUST consume one interceptor,
## respect the minimum reset time, and return true only when the round is
## actually destroyed -- which is what makes salvo fire the correct counter.
## Currently APS state lives in SimMunitions (`arm_hard_kill`, `_aps`); the
## damage agent owns moving it here or leaving it there, but not both.
func try_intercept(target: int, incoming_class: int, closing_speed_ms: float) -> bool:
	return false


## Soft-kill APS, docs/03: "the detection and EW system from docs/02, running at
## unit scale". Jams a SACLOS or beam-riding link. MUST do nothing against an
## unguided round.
func try_soft_kill(target: int, guidance: int) -> bool:
	return false


## The tick slot. Called every simulation tick from SimWorld._sim_step().
## MUST: bleed burning units, run crew recovery, expire wrecks, and be a no-op
## when nothing is damaged. It MUST NOT move anything or fire anything.
func step(dt: float) -> void:
	pass


## True once this class actually resolves damage. SimWorld and the tests read
## it so a half-built game reports itself honestly instead of silently doing
## nothing. The damage agent flips it to true when resolve_impact() is real.
func is_implemented() -> bool:
	return false


func log_event(line: String) -> void:
	combat_log.append(line)
	if combat_log.size() > max_log:
		combat_log.pop_front()
