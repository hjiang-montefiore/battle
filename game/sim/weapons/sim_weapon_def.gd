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


func _init(p: Dictionary = {}) -> void:
	for k in p.keys():
		if k in self:
			set(k, p[k])


func describe() -> String:
	return "%s [%s] %.1f-%.1f km" % [
		name, SimTypes.guidance_name(guidance), min_range_km, max_range_km]
