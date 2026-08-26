class_name SimMunitionDef
extends RefCounted
## What a round IS. docs/10.
##
## Probability of kill is an outcome, not an input. Nothing here is an accuracy
## stat -- these are the physical properties a simulated projectile flies with,
## and whether it connects falls out of them.

## docs/10 §1. Fidelity by whether the player can perceive the difference.
enum Tier {
	A,   ## missiles, torpedoes, ATGMs, guided bombs -- full guidance loop
	B,   ## tank rounds, artillery, unguided rockets -- ballistic, no guidance
	C,   ## small arms, CIWS bursts -- statistical, never an entity
}

## docs/10 §3. A missile is not a dot at constant speed.
enum Phase { BOOST, SUSTAIN, COAST, TERMINAL, DEAD }

## docs/10 §6.
enum Fuze { CONTACT, PROXIMITY, DELAYED, AIRBURST }

## docs/10 §10. Every Tier A projectile carries one of these, and it is what
## reaches the combat log. "That log is the tutorial."
enum Termination {
	NONE,
	HIT,                  ## struck the target
	NEAR_MISS,            ## proximity fuze inside lethal radius
	MISS_ENERGY,          ## out of energy, out-turned
	MISS_AIM,             ## flew to where the track said, target was not there
	DEFEATED_FLARE,
	DEFEATED_CHAFF,
	DEFEATED_DECOY,
	DEFEATED_NOTCH,
	DEFEATED_APS,         ## hard-kill intercept
	DEFEATED_GUIDANCE,    ## illuminator died / datalink cut / emitter shut down
	GROUND_IMPACT,
	SELF_DESTRUCT,        ## flight time expired
	OUT_OF_BOUNDS,
	TARGET_LOST,          ## target destroyed by something else mid-flight
}

var name: String = "munition"
var tier: int = Tier.A
var guidance: int = SimTypes.Guidance.ARH

# ── motor, docs/10 §3 ────────────────────────────────────────────────────────
var boost_seconds: float = 2.0
var sustain_seconds: float = 0.0
var boost_accel: float = 300.0      ## m/s^2 while boosting
var sustain_accel: float = 40.0
var launch_speed: float = 50.0
var max_speed: float = 1200.0
## Quadratic drag: decel = k * v^2 * air_density. At 1250 m/s this gives about
## 34 m/s^2, so a missile bleeds hard once the motor quits -- which is what
## makes the no-escape zone a fraction of kinematic range. The old 0.0016 was
## three orders of magnitude out and stopped every round dead in seconds.
var drag_coefficient: float = 0.000022

# ── manoeuvre ────────────────────────────────────────────────────────────────
## Available g at optimum speed and altitude. Decays as airspeed bleeds off,
## and further at altitude where there is less air to turn against.
var g_available_max: float = 30.0
var optimum_speed: float = 900.0
## Proportional navigation constant, 3-5 in reality. Produces the correct
## lead-pursuit curve, which means the SHAPE of the flight path tells an
## observant player what guidance it is using.
var nav_constant: float = 4.0

# ── terminal ─────────────────────────────────────────────────────────────────
var fuze: int = Fuze.PROXIMITY
var lethal_radius_m: float = 12.0
var seeker_gen: int = 3        ## S-ladder, docs/11 §6
var seeker_activation_km: float = 18.0   ## ARH goes autonomous here
var rcs_m2: float = 0.05       ## projectiles are entities in the sensor solver

# ── hard limits. NOTHING may remain on the map indefinitely. ─────────────────
## Self-destruct. Every real munition has one, and a projectile that never
## terminates is both a bug and a memory leak.
var max_flight_seconds: float = 120.0
## Below this speed it cannot manoeuvre or meaningfully damage anything.
var min_useful_speed: float = 90.0

# ── Tier B ───────────────────────────────────────────────────────────────────
var muzzle_velocity: float = 1700.0
var dispersion_mrad: float = 0.3


func _init(p: Dictionary = {}) -> void:
	for k in p.keys():
		if k in self:
			set(k, p[k])
	# Available g is scaled by (speed / optimum_speed)^2, so an optimum far
	# above what the round can ever reach silently crushes its manoeuvre
	# authority -- an ATGM with a 900 m/s optimum has ~0.1 g and lawn-darts.
	if not p.has("optimum_speed"):
		optimum_speed = max_speed * 0.72


## docs/10 §3: "In range" is not "will hit." The no-escape zone is typically
## only 25-40% of maximum kinematic range -- until dual-pulse and ramjet motors
## push it toward 70% at epoch 7, which is the single largest late-epoch
## capability in the air game.
func no_escape_fraction() -> float:
	if sustain_seconds > 0.0 and boost_seconds > 0.0:
		# dual-pulse: impulse saved for the terminal phase
		return 0.70
	if sustain_seconds > 0.0:
		return 0.45
	return 0.30


## A missile needs roughly three times the target's sustainable g to guarantee
## an intercept (docs/10 §3).
static func g_needed_against(target_g: float) -> float:
	return target_g * 3.0


static func termination_name(t: int) -> String:
	match t:
		Termination.HIT: return "HIT"
		Termination.NEAR_MISS: return "NEAR MISS"
		Termination.MISS_ENERGY, Termination.MISS_AIM: return "MISSED"
		Termination.NONE: return "IN FLIGHT"
		Termination.GROUND_IMPACT: return "IMPACT"
		Termination.SELF_DESTRUCT: return "SELF-DESTRUCT"
		Termination.OUT_OF_BOUNDS: return "LOST"
		Termination.TARGET_LOST: return "ABORTED"
	return "DEFEATED"


# ── a small library, so tests and scenarios share real numbers ───────────────

static func aam_medium() -> SimMunitionDef:
	## Semi-active medium-range AAM, roughly an early Sparrow.
	return SimMunitionDef.new({
		"name": "SARH AAM", "guidance": SimTypes.Guidance.SARH,
		"boost_seconds": 2.5, "boost_accel": 340.0, "max_speed": 1250.0,
		"g_available_max": 25.0, "lethal_radius_m": 11.0,
		"max_flight_seconds": 60.0})


static func aam_active() -> SimMunitionDef:
	## Active radar homing -- self-promotes to TQ4 at seeker range and frees
	## the launcher to break away. The M5 fire-and-forget cliff.
	return SimMunitionDef.new({
		"name": "ARH AAM", "guidance": SimTypes.Guidance.ARH,
		"boost_seconds": 3.0, "boost_accel": 380.0, "max_speed": 1400.0,
		"g_available_max": 30.0, "seeker_gen": 4, "seeker_activation_km": 18.0,
		"lethal_radius_m": 12.0, "max_flight_seconds": 80.0})


static func aam_ramjet() -> SimMunitionDef:
	## Epoch 7 dual-pulse/ramjet: stays powered, no-escape zone approaches
	## kinematic range.
	return SimMunitionDef.new({
		"name": "Ramjet AAM", "guidance": SimTypes.Guidance.ARH,
		"boost_seconds": 3.0, "sustain_seconds": 22.0, "boost_accel": 380.0,
		"sustain_accel": 55.0, "max_speed": 1500.0, "g_available_max": 35.0,
		"seeker_gen": 6, "lethal_radius_m": 12.0, "max_flight_seconds": 90.0})


static func sam_medium() -> SimMunitionDef:
	return SimMunitionDef.new({
		"name": "SARH SAM", "guidance": SimTypes.Guidance.SARH,
		"boost_seconds": 4.0, "boost_accel": 260.0, "max_speed": 1100.0,
		"g_available_max": 22.0, "lethal_radius_m": 18.0,
		"max_flight_seconds": 70.0})


static func atgm() -> SimMunitionDef:
	return SimMunitionDef.new({
		"name": "ATGM", "guidance": SimTypes.Guidance.SACLOS,
		"boost_seconds": 1.5, "boost_accel": 120.0,
		"sustain_seconds": 14.0, "sustain_accel": 6.0,
		"max_speed": 320.0,
		"g_available_max": 8.0, "fuze": Fuze.CONTACT, "lethal_radius_m": 0.0,
		"launch_speed": 75.0,
		"max_flight_seconds": 30.0, "min_useful_speed": 40.0})


static func harm() -> SimMunitionDef:
	return SimMunitionDef.new({
		"name": "ARM", "guidance": SimTypes.Guidance.ANTI_RADIATION,
		"boost_seconds": 5.0, "boost_accel": 300.0, "max_speed": 1000.0,
		"g_available_max": 18.0, "lethal_radius_m": 14.0,
		"max_flight_seconds": 120.0})


static func tank_apfsds() -> SimMunitionDef:
	## Tier B. Roughly 1.3 s to 2 km. Short, but not zero -- a moving target
	## CAN be missed by a bad lead, and the lead came from the track.
	return SimMunitionDef.new({
		"name": "APFSDS", "tier": Tier.B,
		"guidance": SimTypes.Guidance.UNGUIDED,
		"muzzle_velocity": 1700.0, "dispersion_mrad": 0.3,
		"fuze": Fuze.CONTACT, "lethal_radius_m": 0.0,
		"drag_coefficient": 0.00008, "max_flight_seconds": 12.0})


static func artillery_he() -> SimMunitionDef:
	## Tier B, 30-90 s of flight. That long flight time is what lets
	## counter-battery radar extrapolate the trajectory back to the gun.
	return SimMunitionDef.new({
		"name": "155mm HE", "tier": Tier.B,
		"guidance": SimTypes.Guidance.UNGUIDED,
		"muzzle_velocity": 820.0, "dispersion_mrad": 4.0,
		"fuze": Fuze.PROXIMITY, "lethal_radius_m": 30.0,
		"drag_coefficient": 0.00012, "max_flight_seconds": 120.0})
