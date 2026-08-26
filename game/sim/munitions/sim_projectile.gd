class_name SimProjectile
extends RefCounted
## One round in flight. docs/10.
##
## A projectile is a simulated entity that leaves the launcher, flies, guides,
## runs out of energy, gets decoyed, gets intercepted -- and then hits or misses
## FOR A REASON THE PLAYER CAN BE TOLD. There is no accuracy roll anywhere in
## this file.
##
## THE SHOOTER AIMS AT THE TRACK, NOT AT THE TARGET. Guidance reads the faction
## track table -- a belief, with a quality and an age. Miss distance is measured
## against ground truth. A stale track therefore produces a physical miss, which
## is the join between docs/02 and this document.
##
## NOTHING STAYS ON THE MAP. Six independent terminators guarantee it:
## self-destruct at max_flight_seconds, ground impact, leaving the world bounds,
## falling below useful speed, passing closest approach, and losing the target.

const G := 9.80665
const AIR_SCALE_HEIGHT := 8500.0

var def: SimMunitionDef
var alive: bool = false

# ── state ────────────────────────────────────────────────────────────────────
var x: float = 0.0
var y: float = 0.0
var z: float = 0.0
var vx: float = 0.0
var vy: float = 0.0
var vz: float = 0.0

var phase: int = SimMunitionDef.Phase.BOOST
var time_s: float = 0.0
var termination: int = SimMunitionDef.Termination.NONE
var termination_detail: String = ""

# ── who fired it, at what ────────────────────────────────────────────────────
var shooter: int = -1
var faction: int = 0
var target_truth: int = -1     ## sim-internal, for miss distance ONLY
var track_id: int = -1         ## what it is actually guiding on
var seeker_active: bool = false
var went_ballistic: bool = false
var flare_resolved_seq: int = 0
var chaff_resolved_seq: int = 0

var _prev_range: float = INF
var _launch_range: float = 0.0


func launch(munition: SimMunitionDef, from_x: float, from_y: float, from_z: float,
		aim_x: float, aim_y: float, aim_z: float,
		shooter_index: int, faction_id: int, target_index: int,
		track: int) -> void:
	def = munition
	alive = true
	x = from_x; y = from_y; z = from_z
	shooter = shooter_index
	faction = faction_id
	target_truth = target_index
	track_id = track
	phase = SimMunitionDef.Phase.BOOST
	time_s = 0.0
	termination = SimMunitionDef.Termination.NONE
	termination_detail = ""
	seeker_active = false
	went_ballistic = false
	flare_resolved_seq = 0
	chaff_resolved_seq = 0

	var dx := aim_x - from_x
	var dy := aim_y - from_y
	var dz := aim_z - from_z
	var d := sqrt(dx * dx + dy * dy + dz * dz)
	if d < 1e-6:
		d = 1.0
		dx = 1.0
	var speed := def.launch_speed if def.tier == SimMunitionDef.Tier.A \
		else def.muzzle_velocity
	vx = dx / d * speed
	vy = dy / d * speed
	vz = dz / d * speed
	_launch_range = d
	_prev_range = INF


func speed() -> float:
	return sqrt(vx * vx + vy * vy + vz * vz)


## Available g decays as airspeed bleeds off, and falls further at altitude
## where there is less air to turn against (docs/10 §3). A long-coasting
## missile at 10 g is beaten by a simple hard turn.
func g_available() -> float:
	var v := speed()
	var speed_factor: float = clampf(v / maxf(def.optimum_speed, 1.0), 0.0, 1.0)
	var density := exp(-maxf(y, 0.0) / AIR_SCALE_HEIGHT)
	var g := def.g_available_max * speed_factor * speed_factor * density
	# Control surfaces bite from the moment it leaves the rail. Without a floor
	# a slow round cannot even hold level flight against gravity and lawn-darts
	# off the rail, which is not what any guided munition does. Anything truly
	# out of energy is caught by the min_useful_speed terminator instead.
	return maxf(g, 1.6 * density)


func terminate(cause: int, detail: String) -> void:
	alive = false
	phase = SimMunitionDef.Phase.DEAD
	termination = cause
	termination_detail = detail


## One tick. `guide_to` is where the projectile currently believes the target
## is -- taken from the track table, never from ground truth. `truth` is the
## real position, used only to measure what actually happened.
func step(dt: float, guide_x: float, guide_y: float, guide_z: float,
		guide_vx: float, guide_vy: float, guide_vz: float,
		has_guidance: bool,
		truth_x: float, truth_y: float, truth_z: float, truth_valid: bool,
		world_radius_m: float = 400000.0) -> void:
	if not alive:
		return
	time_s += dt

	# ── terminator 1: self-destruct ─────────────────────────────────────────
	if time_s >= def.max_flight_seconds:
		terminate(SimMunitionDef.Termination.SELF_DESTRUCT,
			"flight time expired at T+%.0f s" % time_s)
		return

	_update_phase()
	_apply_motor(dt)
	_apply_drag(dt)

	# ── guidance, re-validated EVERY tick, not just at launch ───────────────
	if def.tier == SimMunitionDef.Tier.A:
		if not has_guidance and not seeker_active:
			if not went_ballistic:
				went_ballistic = true
				# It does not vanish -- it keeps flying, unguided, and will
				# terminate on the ground or on its self-destruct timer. That
				# is what "the missile goes ballistic mid-flight" means.
				termination_detail = "guidance lost at T+%.0f s" % time_s
		elif has_guidance:
			went_ballistic = false
			_guide(dt, guide_x, guide_y, guide_z, guide_vx, guide_vy, guide_vz)

	# gravity acts on everything
	vy -= G * dt

	x += vx * dt
	y += vy * dt
	z += vz * dt

	# ── terminator 2: ground ────────────────────────────────────────────────
	if y <= 0.0:
		y = 0.0
		if went_ballistic:
			terminate(SimMunitionDef.Termination.DEFEATED_GUIDANCE,
				termination_detail + " -- went ballistic and struck the ground")
		else:
			terminate(SimMunitionDef.Termination.GROUND_IMPACT,
				"impacted the ground at T+%.1f s" % time_s)
		return

	# ── terminator 3: world bounds ──────────────────────────────────────────
	if absf(x) > world_radius_m or absf(z) > world_radius_m or y > 60000.0:
		terminate(SimMunitionDef.Termination.OUT_OF_BOUNDS,
			"left the engagement area")
		return

	# ── terminator 4: energy ────────────────────────────────────────────────
	# Only once the motor has burned out. A missile leaves the rail slowly and
	# accelerates; checking during boost kills it on the first tick.
	if time_s > def.boost_seconds + def.sustain_seconds \
			and speed() < def.min_useful_speed:
		terminate(SimMunitionDef.Termination.MISS_ENERGY,
			"out of energy at T+%.0f s, %.0f m/s" % [time_s, speed()])
		return

	# ── terminator 5: closest approach ──────────────────────────────────────
	if truth_valid:
		var dx := truth_x - x
		var dy := truth_y - y
		var dz := truth_z - z
		var r := sqrt(dx * dx + dy * dy + dz * dz)
		if r > _prev_range and _prev_range < INF:
			_resolve_terminal(_prev_range)
			return
		_prev_range = r
		if def.tier == SimMunitionDef.Tier.A and not seeker_active \
				and r <= def.seeker_activation_km * 1000.0:
			if def.guidance == SimTypes.Guidance.ARH:
				# Self-promotes to TQ4; the launcher is free to break away.
				seeker_active = true


func _update_phase() -> void:
	if time_s <= def.boost_seconds:
		phase = SimMunitionDef.Phase.BOOST
	elif time_s <= def.boost_seconds + def.sustain_seconds:
		phase = SimMunitionDef.Phase.SUSTAIN
	else:
		phase = SimMunitionDef.Phase.COAST


func _apply_motor(dt: float) -> void:
	var a := 0.0
	if phase == SimMunitionDef.Phase.BOOST:
		a = def.boost_accel
	elif phase == SimMunitionDef.Phase.SUSTAIN:
		a = def.sustain_accel
	if a <= 0.0:
		return
	var v := speed()
	if v < 1e-6 or v >= def.max_speed:
		return
	var s := (v + a * dt) / v
	vx *= s; vy *= s; vz *= s
	var nv := speed()
	if nv > def.max_speed:
		var c := def.max_speed / nv
		vx *= c; vy *= c; vz *= c


func _apply_drag(dt: float) -> void:
	var v := speed()
	if v < 1e-6:
		return
	var density := exp(-maxf(y, 0.0) / AIR_SCALE_HEIGHT)
	var decel := def.drag_coefficient * v * v * density
	var nv := maxf(v - decel * dt, 0.0)
	var s := nv / v
	vx *= s; vy *= s; vz *= s


## Proportional navigation. The missile turns at a rate proportional to the
## rotation rate of the line of sight, with a navigation constant around 3-5.
## A few lines of code, what real missiles do, and it produces the correct
## lead-pursuit curve.
func _guide(dt: float, tx: float, ty: float, tz: float,
		tvx: float, tvy: float, tvz: float) -> void:
	var rx := tx - x
	var ry := ty - y
	var rz := tz - z
	var r2 := rx * rx + ry * ry + rz * rz
	if r2 < 1.0:
		return
	var rvx := tvx - vx
	var rvy := tvy - vy
	var rvz := tvz - vz

	# LOS rotation vector omega = (r x v_rel) / |r|^2
	var ox := (ry * rvz - rz * rvy) / r2
	var oy := (rz * rvx - rx * rvz) / r2
	var oz := (rx * rvy - ry * rvx) / r2

	# a_cmd = N * (omega x v_missile), perpendicular to velocity by construction
	var ax := def.nav_constant * (oy * vz - oz * vy)
	var ay := def.nav_constant * (oz * vx - ox * vz)
	var az := def.nav_constant * (ox * vy - oy * vx)

	# Real autopilots add a gravity bias so the round flies the guidance
	# solution rather than a ballistic arc under it. Without this an ATGM
	# lawn-darts short of its target.
	ay += G

	# Clamp to what the airframe actually has left.
	var amag := sqrt(ax * ax + ay * ay + az * az)
	var amax := g_available() * G
	if amag > amax and amag > 1e-9:
		var c := amax / amag
		ax *= c; ay *= c; az *= c

	vx += ax * dt
	vy += ay * dt
	vz += az * dt


## docs/10 §6. Compute the miss distance at closest approach, then let the fuze
## decide. Proximity fuzing means a NEAR MISS is a real outcome, not a binary --
## which is what produces the wounded-and-withdrawing units that make a battle
## feel like a battle.
func _resolve_terminal(miss_distance: float) -> void:
	match def.fuze:
		SimMunitionDef.Fuze.CONTACT:
			if miss_distance <= 1.5:
				terminate(SimMunitionDef.Termination.HIT,
					"direct hit at T+%.1f s" % time_s)
			else:
				terminate(SimMunitionDef.Termination.MISS_AIM,
					"missed by %.1f m -- aim error" % miss_distance)
		SimMunitionDef.Fuze.PROXIMITY, SimMunitionDef.Fuze.AIRBURST:
			if miss_distance <= 1.5:
				terminate(SimMunitionDef.Termination.HIT,
					"direct hit at T+%.1f s" % time_s)
			elif miss_distance <= def.lethal_radius_m:
				terminate(SimMunitionDef.Termination.NEAR_MISS,
					"proximity fuze at %.0f m" % miss_distance)
			else:
				terminate(SimMunitionDef.Termination.MISS_AIM,
					"missed by %.0f m" % miss_distance)
		_:
			if miss_distance <= 2.0:
				terminate(SimMunitionDef.Termination.HIT,
					"struck and penetrated at T+%.1f s" % time_s)
			else:
				terminate(SimMunitionDef.Termination.MISS_AIM,
					"missed by %.1f m" % miss_distance)


## Damage falls off with miss distance -- a SAM detonating 15 m from an
## aircraft damages it; one at 3 m destroys it. 1.0 at contact, 0 at the edge
## of the lethal radius.
func damage_fraction(miss_distance: float) -> float:
	if def.fuze == SimMunitionDef.Fuze.CONTACT:
		return 1.0 if miss_distance <= 1.5 else 0.0
	if def.lethal_radius_m <= 0.0:
		return 1.0 if miss_distance <= 1.5 else 0.0
	return clampf(1.0 - (miss_distance / def.lethal_radius_m), 0.0, 1.0)


## docs/10 §6. Hit location is geometry, not a roll: the impact vector against
## the target's orientation decides which armor facet is struck, and that facet
## goes straight into docs/03. "The obsolete tank must flank" is not advice the
## AI is trusted to follow -- it is enforced by where the round arrives.
enum Facet { FRONT, SIDE, REAR, TOP, BELLY }

func impact_facet(target_heading_rad: float) -> int:
	# A steeply descending round hits the roof regardless of heading.
	var v := speed()
	if v > 1e-6 and (-vy / v) > 0.60:
		return Facet.TOP
	if vy > 0.0 and absf(vy) / maxf(v, 1e-6) > 0.60:
		return Facet.BELLY
	# Approach direction relative to where the target is facing.
	var approach := atan2(-vx, -vz)          # direction the round came FROM
	var rel := angle_difference(approach, target_heading_rad)
	var a := absf(rel)
	if a <= PI * 0.25:
		return Facet.FRONT
	if a >= PI * 0.75:
		return Facet.REAR
	return Facet.SIDE


static func facet_name(f: int) -> String:
	match f:
		Facet.FRONT: return "FRONT"
		Facet.SIDE: return "SIDE"
		Facet.REAR: return "REAR"
		Facet.TOP: return "TOP"
		Facet.BELLY: return "BELLY"
	return "?"


## One line for the combat log. docs/10 §10: "That log is the tutorial."
func log_line() -> String:
	return "%-13s %s %s" % [
		SimMunitionDef.termination_name(termination),
		"·", termination_detail]
