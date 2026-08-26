class_name SimImpact
extends RefCounted
## What a round did when it stopped flying. The seam between docs/10 and
## docs/03 -- and the thing that was missing: rounds flew, guided, arrived, and
## nothing happened, because nothing recorded the arrival.
##
## A SNAPSHOT, not a reference. Projectiles are pooled and reused (docs/10 §9),
## so handing the damage layer a live SimProjectile would hand it an object that
## a launch later in the same tick may already have overwritten. Every field the
## damage resolver needs is copied out at retirement instead.
##
## Note what is NOT here: any notion of how much damage to do. docs/10 requires
## Pk to be an OUTCOME. This carries geometry and penetrator physics; docs/03
## decides what that does to the target.

var target: int = -1              ## entity index, ground truth
var shooter: int = -1
var faction: int = 0
var termination: int = SimMunitionDef.Termination.NONE
var termination_detail: String = ""
## SimTypes.Facet, from SimProjectile.impact_facet() -- impact geometry against
## the target's heading. NEVER a roll. docs/03: "Because hit location comes from
## geometry rather than a die roll, that table is not a set of odds -- it is a
## set of instructions."
var facet: int = SimTypes.Facet.FRONT
var miss_distance_m: float = 0.0
## 1.0 on contact, tapering to 0 at the edge of the lethal radius. From
## SimProjectile.damage_fraction(); this is what makes a near miss a real
## outcome instead of a binary.
var blast_fraction: float = 0.0
## Straight-line range from launch point to arrival, metres. KE penetration
## falls with this; CE does not (docs/03).
var range_m: float = 0.0
var impact_speed_ms: float = 0.0
var munition_name: String = ""
var damage_class: int = SimTypes.DamageClass.BLAST
var penetration_mm: float = 0.0   ## quoted figure, BEFORE range adjustment
var tandem: bool = false
var time_s: float = 0.0


## True when something actually arrived at the target -- a direct hit or a
## proximity detonation inside the lethal radius. Everything else on the
## termination list is a round that did not get there, and the damage layer
## should ignore it while the combat log still reports it.
func is_arrival() -> bool:
	return termination == SimMunitionDef.Termination.HIT \
		or termination == SimMunitionDef.Termination.NEAR_MISS


func _to_string() -> String:
	return "%s -> unit %d %s at %.1f m (%.0f m range)" % [
		munition_name, target, SimTypes.facet_name(facet),
		miss_distance_m, range_m]
