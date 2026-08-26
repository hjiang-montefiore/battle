class_name SimCombatOutcome
extends RefCounted
## What one impact did, and WHY -- docs/10 §10 insists the why is the point of
## the whole exercise, because the combat log is the tutorial.
##
## Deliberately a top-level class rather than SimDamage.Outcome. SimDamage is
## the spine's declared seam and SimCombatResolver is the implementation behind
## it; if the resolver returned SimDamage's inner class the two files would
## preload each other and GDScript would refuse the cycle. So the resolver
## produces this, and SimDamage copies it into the Outcome its published
## signature promises. copy_into() is that copy, in one place, so the two shapes
## cannot drift.

var resolved: bool = false          ## false only when the impact was not resolvable
var penetrated: bool = false
var facet: int = SimTypes.Facet.FRONT
var effective_mm: float = 0.0       ## what the round had to beat
var penetration_mm: float = 0.0     ## what it arrived with
var components_lost: int = SimTypes.Component.NONE
var structure_lost: float = 0.0
var killed: bool = false
var reason: String = ""

## SimPenetrator.Verdict. Carries the one distinction a float cannot: whether
## the round was DEFEATED (it could have worked) or IMPOSSIBLE (the mechanism
## cannot work here at all, at any range, ever).
var verdict: int = SimPenetrator.Verdict.DEFEATED
## True when the round started an engine or fuel fire that will keep bleeding
## the target after the impact tick.
var fire: bool = false


## Fill any object carrying the same field names -- specifically
## SimDamage.Outcome, whose signature the spine published and which this file
## must not depend on.
func copy_into(o: Object) -> Object:
	o.resolved = resolved
	o.penetrated = penetrated
	o.facet = facet
	o.effective_mm = effective_mm
	o.penetration_mm = penetration_mm
	o.components_lost = components_lost
	o.structure_lost = structure_lost
	o.killed = killed
	o.reason = reason
	return o


func _to_string() -> String:
	return reason
