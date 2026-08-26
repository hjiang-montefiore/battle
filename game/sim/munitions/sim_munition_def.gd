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

## Air or water. A torpedo is not a slow missile: no gravity, no air drag, a
## fuel budget instead of a motor burn, and a speed/range trade that is pillar 4
## at projectile scale (docs/10 §7).
enum Medium { AIR, WATER }

## docs/10 §7. How a torpedo finds the target, and what defeats it.
enum TorpedoSeeker {
	WIRE,      ## steered from the launcher. Best accuracy, huge commitment
	PASSIVE,   ## listens. Defeated by a quiet target and by noisemakers
	ACTIVE,    ## pings -- and announces itself to the target
	WAKE,      ## follows the wake. Very hard to decoy. Surface ships only
}

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

# ── warhead, docs/03 ─────────────────────────────────────────────────────────
## THE SPINE'S ADDITION. Everything above describes how a round FLIES. These
## four describe what it does when it arrives, and without them docs/10 and
## docs/03 never meet: rounds flew and nothing could be hurt by them.
##
## docs/03: "penetration is a property of THE ROUND, not the tank. The same
## 120 mm tube fired ~350 mm rounds in 1979 and ~750 mm rounds in 2003."
## Ammunition is therefore an independently upgradeable ladder that applies to
## units already in the field -- so the number lives here, on the munition, and
## never on the launcher.
var damage_class: int = SimTypes.DamageClass.BLAST
## Millimetres of RHA equivalent, QUOTED AT 2 km. SimArmor.penetration_at_range_mm()
## adjusts it for the range the round actually arrived at: KE bleeds, CE does not.
var penetration_mm: float = 0.0
## Tandem warhead: a precursor charge detonates the reactive block before the
## main jet arrives, which docs/03 says defeats ERA outright. Worthless against
## composite, which is what keeps it a specialist rather than a straight upgrade.
var tandem: bool = false
## Structure damage on a penetration or against an unarmoured target, before
## the blast falloff in SimProjectile.damage_fraction() is applied.
var warhead_damage: float = 100.0

# ── hard limits. NOTHING may remain on the map indefinitely. ─────────────────
## Self-destruct. Every real munition has one, and a projectile that never
## terminates is both a bug and a memory leak.
var max_flight_seconds: float = 120.0
## Below this speed it cannot manoeuvre or meaningfully damage anything.
var min_useful_speed: float = 90.0

# ── Tier B ───────────────────────────────────────────────────────────────────
var muzzle_velocity: float = 1700.0
var dispersion_mrad: float = 0.3

# ── torpedoes, docs/10 §7 ────────────────────────────────────────────────────
var medium: int = Medium.AIR
var torpedo_seeker: int = TorpedoSeeker.PASSIVE
## Selected at launch. The whole point of the trade: run far and slow, or
## fast and much less far.
var run_speed_ms: float = 14.4          ## ~28 kn
var reference_speed_ms: float = 14.4
var endurance_at_reference_s: float = 3470.0
## A wire-guided torpedo constrains its launcher for the ENTIRE run: the boat
## must stay below this speed and hold course, or the wire parts.
var wire_max_launcher_speed_ms: float = 8.0
var wire_max_launcher_turn_rad: float = 0.35
## Launching is a loud, detectable acoustic event. Shooting reveals you.
var launch_transient_db: float = 150.0
var acoustic_db: float = 130.0          ## its own radiated noise while running


func is_torpedo() -> bool:
	return medium == Medium.WATER


## Endurance falls with the square of speed, so range = v * endurance falls
## with speed. A heavyweight runs ~50 km at 28 kn or ~35 km at 40 kn, which is
## what turns "torpedo in the water" into a chase rather than a verdict.
func endurance_s() -> float:
	if run_speed_ms <= 0.0:
		return 0.0
	var r := reference_speed_ms / run_speed_ms
	return endurance_at_reference_s * r * r


func run_range_m() -> float:
	return run_speed_ms * endurance_s()


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


# ── torpedoes ────────────────────────────────────────────────────────────────

static func torpedo_heavyweight(speed_kn := 28.0,
		seeker := TorpedoSeeker.WIRE) -> SimMunitionDef:
	## Submarine-launched heavyweight. Wire-guided by default, which is the
	## best accuracy available and the largest commitment in the game: the boat
	## is slow, straight and vulnerable for the whole run.
	return SimMunitionDef.new({
		"name": "heavyweight torpedo", "medium": Medium.WATER,
		"guidance": SimTypes.Guidance.SACLOS, "torpedo_seeker": seeker,
		"run_speed_ms": speed_kn * 0.514444,
		"reference_speed_ms": 14.4, "endurance_at_reference_s": 3470.0,
		"boost_seconds": 6.0, "boost_accel": 4.0, "launch_speed": 6.0,
		"max_speed": speed_kn * 0.514444, "g_available_max": 4.0,
		"optimum_speed": speed_kn * 0.514444,
		"fuze": Fuze.PROXIMITY, "lethal_radius_m": 15.0,
		"min_useful_speed": 3.0, "max_flight_seconds": 3600.0,
		"drag_coefficient": 0.0, "nav_constant": 3.5,
		"rcs_m2": 0.0, "acoustic_db": 132.0})


static func torpedo_lightweight_asw() -> SimMunitionDef:
	## Helicopter- or ship-dropped ASW weapon. Short-legged and fast, dropped
	## onto a datum rather than run out to one.
	return SimMunitionDef.new({
		"name": "lightweight torpedo", "medium": Medium.WATER,
		"guidance": SimTypes.Guidance.ARH, "torpedo_seeker": TorpedoSeeker.ACTIVE,
		"run_speed_ms": 23.2, "reference_speed_ms": 23.2,
		"endurance_at_reference_s": 480.0,
		"boost_seconds": 4.0, "boost_accel": 6.0, "launch_speed": 4.0,
		"max_speed": 23.2, "g_available_max": 6.0, "optimum_speed": 23.2,
		"fuze": Fuze.PROXIMITY, "lethal_radius_m": 9.0,
		"min_useful_speed": 3.0, "max_flight_seconds": 900.0,
		"drag_coefficient": 0.0, "seeker_activation_km": 2.0,
		"rcs_m2": 0.0, "acoustic_db": 128.0})


static func torpedo_wake_homing() -> SimMunitionDef:
	## Follows the target's wake. Very hard to decoy -- a noisemaker is not a
	## wake -- and useless against a submerged submarine, which leaves none.
	var t := torpedo_heavyweight(30.0, TorpedoSeeker.WAKE)
	t.name = "wake-homing torpedo"
	t.guidance = SimTypes.Guidance.IR_EO   # gated by its own seeker, not the net
	return t


static func artillery_he() -> SimMunitionDef:
	## Tier B, 30-90 s of flight. That long flight time is what lets
	## counter-battery radar extrapolate the trajectory back to the gun.
	return SimMunitionDef.new({
		"name": "155mm HE", "tier": Tier.B,
		"guidance": SimTypes.Guidance.UNGUIDED,
		"muzzle_velocity": 820.0, "dispersion_mrad": 4.0,
		"fuze": Fuze.PROXIMITY, "lethal_radius_m": 30.0,
		"drag_coefficient": 0.00012, "max_flight_seconds": 120.0})
