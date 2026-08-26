class_name SimSignature
extends RefCounted
## How observable a unit is, per domain. docs/02 §1.
##
## These are emissions and reflectivity, NOT hit points. Signatures are not
## static either -- aspect, throttle, speed, depth, terrain and configuration
## all modify them at runtime, which is why SimEntities computes effective
## values each solve rather than reading these directly.
##
## The `emissions` field other designs would put here is deliberately absent:
## what a unit radiates is derived every tick from whatever sensors, jammers and
## datalinks are actually switched on.

var rcs_m2: float = 1.0         ## radar cross-section, m^2. log-distributed
var ir_band: float = 1.0        ## infrared intensity, relative units
var acoustic_db: float = 100.0  ## radiated noise, dB re 1 uPa (naval only)
var visual_m2: float = 10.0     ## optical / EO projected area
var magnetic: float = 0.0       ## MAD detectability (submerged hulls)


func _init(rcs := 1.0, ir := 1.0, acoustic := 100.0, visual := 10.0, mag := 0.0) -> void:
	rcs_m2 = rcs
	ir_band = ir
	acoustic_db = acoustic
	visual_m2 = visual
	magnetic = mag


func clone() -> SimSignature:
	return SimSignature.new(rcs_m2, ir_band, acoustic_db, visual_m2, magnetic)


## Reference RCS values from docs/02 §1. The exact numbers matter less than the
## spread -- five orders of magnitude between a bomber and a stealth fighter is
## what makes the fourth-root law produce a real cliff.
const RCS_BOMBER := 100.0
const RCS_FIGHTER_LOADED := 10.0
const RCS_FIGHTER_CLEAN := 2.0
const RCS_CRUISE_MISSILE := 0.1
const RCS_STRIKE_STEALTH := 0.005
const RCS_AIR_SUPERIORITY_STEALTH := 0.0001
