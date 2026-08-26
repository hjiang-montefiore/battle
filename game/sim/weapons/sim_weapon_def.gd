class_name SimWeaponDef
extends RefCounted
## One weapon. The guidance field is what the gate reads; everything else is
## envelope. docs/02 §5.

var name: String = "weapon"
var guidance: int = SimTypes.Guidance.UNGUIDED
var min_range_km: float = 0.0
var max_range_km: float = 10.0
## IR_EO must be inside this to launch at all -- the seeker has to see it.
var seeker_range_km: float = 0.0
## COMMAND_LINK rounds die if the network does.
var needs_datalink: bool = false
## Which SimTypes.Category this weapon may be pointed at, as a bit per category
## (1 << Category). The GATE deliberately does not read this -- a track's
## quality and a weapon's envelope are what decide whether a shot is legal, and
## an operator who insists on firing a tank gun at an aircraft is allowed to.
## Automatic target SELECTION reads it, so a SAM battery does not sit there
## holding fire because the nearest contact is a tank. Defaults to everything,
## so a weapon that never sets it behaves exactly as it did before.
var target_mask: int = 0xF


## Category bit helper, so callers do not open-code the shift.
static func mask_of(categories: Array) -> int:
	var m := 0
	for c in categories:
		m |= 1 << int(c)
	return m


func engages_category(category: int) -> bool:
	return (target_mask & (1 << category)) != 0


func _init(p: Dictionary = {}) -> void:
	for k in p.keys():
		if k in self:
			set(k, p[k])


func describe() -> String:
	return "%s [%s] %.1f-%.1f km" % [
		name, SimTypes.guidance_name(guidance), min_range_km, max_range_km]
