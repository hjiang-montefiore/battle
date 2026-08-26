class_name SimDamage
extends RefCounted
## docs/03, and the seam where docs/10 finally has consequences.
##
## ══ THE SEAM, NOT THE MODEL. ══
## The signatures below are the spine's published contract and are unchanged.
## The MODEL behind them lives in game/sim/combat/:
##
##   combat/sim_penetrator.gd       what a class of penetrator can and cannot
##                                  do at all -- the refusals that make a
##                                  generational gap a cliff instead of a slope
##   combat/sim_armor_scheme.gd     docs/03's generational ladder as real
##                                  per-facet numbers a unit can be built with
##   combat/sim_behind_armor.gd     what a penetration HIT: components, not HP
##   combat/sim_combat_resolver.gd  the resolution itself, and the only caller
##                                  of entities.kill() in the simulation
##   combat/sim_combat_outcome.gd   the resolver's return value
##
## Keeping this file thin is deliberate. It is the spine's declared surface --
## SimWorld calls resolve_impact() and step() through it, and test_spine.gd
## constructs it -- so it must keep its shape whatever the model behind it does.
##
## OWNERSHIP: this class and the resolver it delegates to are the only writers
## of `structure`, `components`, `crew_efficiency` and `alive`. Nothing else may
## call entities.kill().
##
## The armour matrix it resolves against is already real -- see sim_armor.gd.


## What one impact did. Returned by resolve_impact() so the combat log can say
## WHY, which docs/10 §10 insists is the point of the whole exercise.
class Outcome extends RefCounted:
	var resolved: bool = false      ## false when the impact was not resolvable
	var penetrated: bool = false
	var facet: int = SimTypes.Facet.FRONT
	var effective_mm: float = 0.0   ## what the round had to beat
	var penetration_mm: float = 0.0 ## what it arrived with
	var components_lost: int = SimTypes.Component.NONE
	var structure_lost: float = 0.0
	var killed: bool = false
	var reason: String = ""

	func _to_string() -> String:
		return reason


var entities: SimEntities
var rng: SimRng
## The model. Public so tests, the HUD and the unit-spawning code can reach
## SimArmorScheme configuration and the per-unit blowout override without
## SimDamage having to re-export every one of them.
var resolver: SimCombatResolver
## Append-only, capped. Same shape as SimMunitions.combat_log so the HUD can
## merge the two into one stream. Shared with the resolver, not copied.
var combat_log: Array = []
var max_log: int = 200


func _init(store: SimEntities, seeded: SimRng) -> void:
	entities = store
	rng = seeded
	resolver = SimCombatResolver.new(store, seeded)
	combat_log = resolver.combat_log
	resolver.max_log = max_log


# ── counters, read straight off the resolver so they cannot drift ────────────

var kills: int:
	get:
		return resolver.kills
var penetrations: int:
	get:
		return resolver.penetrations
var defeats: int:
	get:
		return resolver.defeats
var impossible: int:
	get:
		return resolver.impossible


# ═══════════════════════════════════════════════════════════════════════════
# THE API
# ═══════════════════════════════════════════════════════════════════════════

## Resolve one arriving round against one unit. THE central function.
##
## The facet comes from SimProjectile.impact_facet(), which derived it from
## impact geometry -- it is never re-rolled here. `penetration_mm` has already
## been through SimArmor.penetration_at_range_mm(), so it is what the round
## arrived with at the range it actually flew.
func resolve_impact(target: int, facet: int, damage_class: int,
		penetration_mm: float, blast_fraction: float = 1.0,
		tandem: bool = false) -> Outcome:
	var o := resolver.resolve(target, facet, damage_class, penetration_mm,
		blast_fraction, tandem)
	return o.copy_into(Outcome.new()) as Outcome


## Take `amount` off a unit's structure pool. Returns true if this call killed
## it. For AIRFRAME, HULL, UNARMORED and STRUCTURE targets, and for the
## behind-armor bleed on an ARMORED one.
func apply_structure(target: int, amount: float, cause: String = "") -> bool:
	return resolver.apply_structure(target, amount, cause)


## Hard-kill APS intercept, docs/03.
##
## NOT IMPLEMENTED HERE, ON PURPOSE. Hard-kill APS already works end to end in
## SimMunitions (`arm_hard_kill` arms it, `_pre_flight_checks` spends an
## interceptor and terminates the round with DEFEATED_APS), and that is the
## RIGHT place for it: docs/03 says "APS is not an armor multiplier, it resolves
## BEFORE the armor calculation", and a round destroyed in flight never reaches
## this file at all. The spine's note on this seam says to own it in one place
## and not both, so this entry point deliberately does nothing rather than
## becoming a second, divergent interceptor pool.
##
## Always returns false. Arm APS with SimMunitions.arm_hard_kill(unit, n).
func try_intercept(_target: int, _incoming_class: int, _closing_speed_ms: float) -> bool:
	return false


## Soft-kill APS, docs/03: "the detection and EW system from docs/02, running at
## unit scale", jamming a SACLOS or beam-riding link.
##
## STILL A STUB, and honestly so. Soft-kill must act on a round IN FLIGHT --
## it breaks the guidance link, which makes the weapon miss; it is not something
## that can be decided at the moment of impact, which is the only moment this
## class is called. The hook therefore belongs next to the flare and chaff
## checks in SimMunitions._pre_flight_checks, which this subsystem does not own.
## Nothing calls this, and it does nothing.
func try_soft_kill(_target: int, _guidance: int) -> bool:
	return false


## The tick slot, called every simulation tick from SimWorld._sim_step().
## Bleeds burning units, recovers shaken crews, expires wrecks.
func step(dt: float) -> void:
	resolver.step(dt)


## True once this class actually resolves damage.
func is_implemented() -> bool:
	return true


func log_event(line: String) -> void:
	combat_log.append(line)
	if combat_log.size() > max_log:
		combat_log.pop_front()


func describe() -> String:
	return resolver.describe()
