class_name SimUnitDef
extends RefCounted
## One buildable thing, fully specified. docs/12 roles x docs/05 epochs.
##
## A ROLE IS NOT A UNIT (docs/12). "mbt" is a role; the epoch-3 mbt and the
## epoch-6 mbt are different units filling it. SimRoster holds one row per role
## and stamps out a SimUnitDef per (role, epoch), which is why every cost,
## thickness and burn rate below is quoted AT EPOCH 1 and scaled on the way out.
##
## This is plain data with no behaviour beyond describing itself. It exists so
## that SimEconomy.spawn_unit() has exactly one source for the damage, mobility
## and economy profile it is required to set before returning -- a unit that is
## half-configured because two call sites disagreed is the bug this prevents.

# ── identity ─────────────────────────────────────────────────────────────────
var role: String = "unit"           ## docs/12 role key, epoch-free
var key: String = "unit_e1"         ## role + epoch, the def key the queue uses
var name: String = "Unit"
var epoch: int = 1                  ## the epoch this instance was stamped at
var first_epoch: int = 1            ## docs/12 "Epoch" column
var last_epoch: int = 7             ## roles that fall out of use
var domain: int = 0                 ## SimPlayerSetup.Domain bit
var category: int = SimTypes.Category.GROUND
var is_structure: bool = false

# ── construction ─────────────────────────────────────────────────────────────
var cost: float = 100.0             ## credits, AT EPOCH 1
var build_seconds: float = 10.0
var upkeep: float = 0.0             ## credits per minute of service
## Role key of the structure that builds it. "" means it is a structure itself
## (placed with BUILD) or is not buildable at all.
var built_by: String = ""
## Structure roles that must already exist, operational, before this is legal.
var requires: PackedStringArray = PackedStringArray()

# ── mobility (docs/04 units: m/s, m/s^2, rad/s) ──────────────────────────────
var speed_kmh: float = 0.0
var accel_ms2: float = 1.5
var turn_rate_rads: float = 0.6

# ── fuel (docs/04) ───────────────────────────────────────────────────────────
var fuel_capacity: float = 0.0      ## litres
var burn_idle: float = 0.0          ## litres per minute
var burn_cruise: float = 0.0
var burn_combat: float = 0.0
## docs/04: "Nuclear-powered ships ignore fuel entirely for propulsion."
## Expressed as a flag rather than a zero tank so the roster can say WHY.
var nuclear: bool = false
var nuclear_from_epoch: int = 99

# ── survivability (docs/03) ──────────────────────────────────────────────────
var damage_model: int = SimTypes.DamageModel.UNARMORED
var structure_hp: float = 100.0
## Armour archetype key -- see SimRoster.ARMOR_LADDER. The per-facet millimetres
## and the ArmorType are BOTH functions of epoch, because docs/03's cliff is a
## type change as much as a thickness change.
var armor: String = "none"
var armor_class: int = -1

# ── signature (docs/02 §1) ───────────────────────────────────────────────────
var rcs_m2: float = 5.0
var ir_band: float = 1.0
var acoustic_db: float = 90.0
var visual_m2: float = 10.0
var magnetic: float = 0.0
var mount_height_m: float = 2.0
## SimRoster sensor archetype key, or "" for a unit that carries nothing.
var sensor: String = ""

# ── economy roles (structures, mostly) ───────────────────────────────────────
var power_draw: float = 0.0
var power_supply: float = 0.0
var extraction_per_min: float = 0.0   ## oil derricks. Crude, not credits yet
var refine_capacity: float = 0.0      ## refineries. Crude -> credits per min
var supply_radius_m: float = 0.0      ## docs/04 forward supply point reach
var supply_rate_lpm: float = 0.0      ## litres per minute it can push
var supply_infinite: bool = false     ## a refinery does not run itself dry
var enables_advance: bool = false     ## docs/12 research facility
var build_radius_m: float = 0.0       ## structures may be placed near this one
var footprint_m: float = 12.0         ## keep-out radius for placement


func signature() -> SimSignature:
	return SimSignature.new(rcs_m2, ir_band, acoustic_db, visual_m2, magnetic)


func max_speed_ms() -> float:
	return speed_kmh / 3.6


## docs/04: a nuclear plant removes the fuel constraint from epoch N onward.
func uses_fuel_at(e: int) -> bool:
	if nuclear and e >= nuclear_from_epoch:
		return false
	return fuel_capacity > 0.0


func is_supply_source() -> bool:
	return supply_radius_m > 0.0 and supply_rate_lpm > 0.0


func describe() -> String:
	var bits := PackedStringArray()
	bits.append("%-22s  %5.0f cr  %4.0f s" % [key, cost, build_seconds])
	if built_by != "":
		bits.append("from %s" % built_by)
	if is_structure:
		bits.append("structure")
	return "  ".join(bits)
