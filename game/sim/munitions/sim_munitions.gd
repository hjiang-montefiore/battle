class_name SimMunitions
extends RefCounted
## Every round in flight, and what happens to it. docs/10.
##
## Projectiles are POOLED and reused. Allocation churn during a saturation
## attack is a frame-rate cliff, and saturation attacks are precisely when the
## game is at its most exciting (docs/10 §9).
##
## Countermeasures act on the ENTITY IN FLIGHT, never as a percentage reduction
## applied at impact. A flare either takes the seeker or it does not, at the
## moment it is deployed, and the round terminates with a cause that says so.

const MAX_CONCURRENT := 512

var _pool: Array = []          ## Array[SimProjectile], reused
var _active: Array = []        ## indices into _pool
var _free: Array = []

var entities: SimEntities
var solver: SimSensorSolver
var rng: SimRng

## Termination log. docs/10 §10 -- "That log is the tutorial."
var combat_log: Array = []
var max_log: int = 200

## Per-target countermeasure state, consumed by projectiles in flight.
var _flares: Dictionary = {}   ## entity index -> seconds remaining
var _chaff: Dictionary = {}
## Deployment counters. A flare either takes the seeker or it does not, at
## the moment it is deployed -- re-rolling every tick turns a 10% seeker
## defeat into a certainty over a 6-second burn.
var _flare_seq: Dictionary = {}
var _chaff_seq: Dictionary = {}
var _aps: Dictionary = {}      ## entity index -> intercepts remaining
var _noise: Dictionary = {}    ## entity index -> seconds remaining
var _noise_seq: Dictionary = {}

var launched: int = 0
var terminated: int = 0

## THE SPINE'S ADDITION. Every round that stopped flying during the MOST RECENT
## step(), snapshotted. This is the missing seam: the combat slot in
## sim_world.gd drains it into SimDamage, which is how a round arriving finally
## has a consequence.
##
## Cleared at the top of every step(), so it holds exactly one tick of arrivals.
## Snapshots rather than SimProjectile references, because the pool reuses those
## the moment somebody fires again.
var last_impacts: Array = []      ## Array[SimImpact]


func _init(store: SimEntities, sensor_solver: SimSensorSolver, seeded: SimRng) -> void:
	entities = store
	solver = sensor_solver
	rng = seeded


func active_count() -> int:
	return _active.size()


func _acquire() -> SimProjectile:
	if _free.is_empty():
		if _pool.size() >= MAX_CONCURRENT:
			return null      # queue at the caller; docs/10 §9 caps Tier A
		var p := SimProjectile.new()
		_pool.append(p)
		_free.append(_pool.size() - 1)
	var idx: int = _free.pop_back()
	_active.append(idx)
	return _pool[idx]


## Fire. The aim point comes from the TRACK, not the target -- a shooter has no
## access to ground truth, so it aims where its picture says and misses when
## that picture is wrong.
func fire(munition: SimMunitionDef, shooter: int, target: int,
		track: SimTrack) -> SimProjectile:
	var p := _acquire()
	if p == null:
		return null
	var ax := entities.pos_x[target]
	var ay := entities.pos_y[target]
	var az := entities.pos_z[target]
	if track != null and not track.bearing_only:
		# Lead the TRACK's believed position by an estimated time of flight.
		var dx := track.pos_x - entities.pos_x[shooter]
		var dy := track.pos_y - entities.pos_y[shooter]
		var dz := track.pos_z - entities.pos_z[shooter]
		var r := sqrt(dx * dx + dy * dy + dz * dz)
		var tof := r / maxf(munition.max_speed * 0.75, 1.0)
		# Stale tracks lead from stale data -- the error is the age, not a roll.
		ax = track.pos_x + track.vel_x * tof
		ay = track.pos_y + track.vel_y * tof
		az = track.pos_z + track.vel_z * tof
	var launch_y: float = entities.pos_y[shooter] + 2.0
	if munition.is_torpedo():
		launch_y = minf(entities.pos_y[shooter], -2.0)
	elif munition.tier == SimMunitionDef.Tier.B:
		# SUPERELEVATION. A gun laid flat at a target 1.2 km away puts the round
		# into the ground at 1.1 km -- gravity acts on it for the whole flight,
		# so a ballistic weapon must be aimed ABOVE what it is shooting at. Real
		# fire control does this from a ballistic table; this is the same
		# calculation. Without it Tier B rounds can never arrive at all, and the
		# entire docs/03 armour matrix never gets a chance to resolve.
		#
		# The aim point is raised rather than an angle being applied, so
		# SimProjectile.launch() keeps its single "point it at this spot" rule.
		ay = _ballistic_aim_y(entities.pos_x[shooter], launch_y,
			entities.pos_z[shooter], ax, ay, az, munition)
	p.launch(munition, entities.pos_x[shooter], launch_y,
		entities.pos_z[shooter], ax, ay, az, shooter,
		entities.faction[shooter], target,
		track.track_id if track != null else -1)
	if munition.is_torpedo():
		# docs/10 §7: firing is loud. The launch is a detectable acoustic event,
		# so shooting reveals you -- the same emitter logic as radar and active
		# sonar, one more time.
		entities.add_acoustic_transient(shooter, munition.launch_transient_db, 12.0)
		p.launcher_heading = atan2(entities.vel_x[shooter], entities.vel_z[shooter])
	launched += 1
	return p


# ── countermeasures, docs/10 §5 ──────────────────────────────────────────────

func deploy_flares(target: int, seconds := 3.0) -> void:
	_flares[target] = seconds
	_flare_seq[target] = _flare_seq.get(target, 0) + 1


func deploy_chaff(target: int, seconds := 4.0) -> void:
	_chaff[target] = seconds
	_chaff_seq[target] = _chaff_seq.get(target, 0) + 1


func arm_hard_kill(target: int, intercepts := 2) -> void:
	_aps[target] = intercepts


## Noisemakers -- the underwater chaff. They seduce a torpedo that is LISTENING
## or PINGING. A wake-homing weapon ignores them completely, because a
## noisemaker is not a wake (docs/10 §5, §7).
func deploy_noisemakers(target: int, seconds := 25.0) -> void:
	_noise[target] = seconds
	_noise_seq[target] = _noise_seq.get(target, 0) + 1


func _noisemaker_defeats(seeker_mode: int) -> bool:
	match seeker_mode:
		SimMunitionDef.TorpedoSeeker.WAKE:
			return false                      # a decoy leaves no wake
		SimMunitionDef.TorpedoSeeker.WIRE:
			return rng.next_float() < 0.15    # the operator can see through it
		SimMunitionDef.TorpedoSeeker.PASSIVE:
			return rng.next_float() < 0.65
		SimMunitionDef.TorpedoSeeker.ACTIVE:
			return rng.next_float() < 0.45
	return false


## Flares are a HARD counter in epochs 1-3, a coin flip in 4-5, and near
## worthless against imaging seekers from epoch 6 (docs/10 §5, docs/11 §6).
## Physical radius of a target, metres -- what "hitting it" actually means.
##
## Placeholder by CATEGORY until entities carry a real per-unit size. It is a
## placeholder on purpose and is marked as one: the honest home for this is a
## hull dimension on SimUnitDef, which does not exist yet. But leaving the fuze
## at a hard 1.5 m for everything is worse than a rough category value, because
## it makes a destroyer as hard to hit as a jeep.
##
## These are half-extents of a typical unit of each kind, deliberately modest:
## a hit should still be a hit, and the number must never grow large enough to
## turn a near miss into a kill.
func _target_extent(i: int) -> float:
	match entities.category[i]:
		SimTypes.Category.SURFACE:
			return 12.0      # a frigate is ~130 m x 15 m; this is the beam
		SimTypes.Category.SUBSURFACE:
			return 5.0       # a hull ~10 m across
		SimTypes.Category.AIR:
			return 5.0       # wingspan order, not fuselage
		_:
			return 2.0       # an armoured vehicle
	return 1.5


## Is this weapon the sort of thing a flare can seduce at all?
##
## Asking `guidance == IR_EO` directly was wrong, and wrong in a way that
## inverted a rule docs/10 states explicitly. torpedo_wake_homing() sets
## guidance = IR_EO to mean "gated by its own seeker, not the net" -- the enum
## has no value for an autonomous seeker, so IR_EO was borrowed for it. The
## flare check then read that borrowed value literally, and a SHIP POPPING
## AIRCRAFT FLARES decoyed the one weapon docs/10 §5 says cannot be decoyed.
##
## Susceptibility is a property of the munition, not of a bare enum comparison.
## A torpedo is never flare-susceptible: its countermeasure is the noisemaker,
## handled separately, and a wake-homer ignores that too.
func _flare_susceptible(def: SimMunitionDef) -> bool:
	if def.is_torpedo():
		return false
	return def.guidance == SimTypes.Guidance.IR_EO


## S4 imaging IR is one of the eight cliffs: flares stop working.
func _flare_defeats(seeker_gen: int) -> bool:
	if seeker_gen <= 3:
		return true
	if seeker_gen <= 5:
		return rng.next_float() < 0.5
	return rng.next_float() < 0.10


func _chaff_defeats(seeker_gen: int) -> bool:
	if seeker_gen <= 2:
		return true
	if seeker_gen <= 4:
		return rng.next_float() < 0.45
	return rng.next_float() < 0.12


# ── the tick ─────────────────────────────────────────────────────────────────

func step(dt: float) -> void:
	last_impacts.clear()
	_decay_countermeasures(dt)

	var still: Array = []
	for idx in _active:
		var p: SimProjectile = _pool[idx]
		if not p.alive:
			continue
		if _pre_flight_checks(p, dt):
			_retire(idx, p)
			continue

		var track: SimTrack = null
		var table := solver.table_for(p.faction)
		if p.track_id >= 0:
			track = table.get_track(p.track_id)

		var has_guidance := _guidance_valid(p, track)
		var gx := p.x + p.vx
		var gy := p.y + p.vy
		var gz := p.z + p.vz
		var gvx := 0.0
		var gvy := 0.0
		var gvz := 0.0
		if p.seeker_active and entities.is_alive(p.target_truth):
			# The seeker has its own picture now -- TQ4, launcher free.
			gx = entities.pos_x[p.target_truth]
			gy = entities.pos_y[p.target_truth]
			gz = entities.pos_z[p.target_truth]
			gvx = entities.vel_x[p.target_truth]
			gvy = entities.vel_y[p.target_truth]
			gvz = entities.vel_z[p.target_truth]
			has_guidance = true
		elif track != null:
			gx = track.pos_x; gy = track.pos_y; gz = track.pos_z
			gvx = track.vel_x; gvy = track.vel_y; gvz = track.vel_z

		var truth_valid := entities.is_alive(p.target_truth)
		var tx := entities.pos_x[p.target_truth] if truth_valid else 0.0
		var ty := entities.pos_y[p.target_truth] if truth_valid else 0.0
		var tz := entities.pos_z[p.target_truth] if truth_valid else 0.0

		p.step(dt, gx, gy, gz, gvx, gvy, gvz, has_guidance,
			tx, ty, tz, truth_valid, 400000.0,
			_target_extent(p.target_truth) if truth_valid else 1.5)

		if not p.alive:
			_retire(idx, p)
		else:
			still.append(idx)
	_active = still


## Everything that can kill a round before it even integrates this tick.
## Returns true when the projectile has been terminated.
func _pre_flight_checks(p: SimProjectile, _dt: float) -> bool:
	# The thing it was fired at died to something else.
	if not entities.is_alive(p.target_truth):
		p.terminate(SimMunitionDef.Termination.TARGET_LOST,
			"target destroyed before arrival")
		return true

	var r := _range_to_target(p)

	# Hard-kill APS physically destroys the round in flight.
	if _aps.get(p.target_truth, 0) > 0 and r < 400.0:
		_aps[p.target_truth] = _aps[p.target_truth] - 1
		p.terminate(SimMunitionDef.Termination.DEFEATED_APS,
			"intercepted by hard-kill APS at %.0f m" % r)
		return true

	# Expendables only work on a seeker that is actually looking.
	if p.def.tier == SimMunitionDef.Tier.A and r < 6000.0:
		var g := p.def.guidance
		var fseq: int = _flare_seq.get(p.target_truth, 0)
		if _flare_susceptible(p.def) and _flares.get(p.target_truth, 0.0) > 0.0 \
				and p.flare_resolved_seq < fseq:
			p.flare_resolved_seq = fseq
			if _flare_defeats(p.def.seeker_gen):
				p.terminate(SimMunitionDef.Termination.DEFEATED_FLARE,
					"seeker took a flare at %.0f m" % r)
				return true
		var cseq: int = _chaff_seq.get(p.target_truth, 0)
		if (g == SimTypes.Guidance.ARH or g == SimTypes.Guidance.SARH) \
				and _chaff.get(p.target_truth, 0.0) > 0.0 \
				and p.chaff_resolved_seq < cseq:
			p.chaff_resolved_seq = cseq
			if _chaff_defeats(p.def.seeker_gen):
				p.terminate(SimMunitionDef.Termination.DEFEATED_CHAFF,
					"seeker transferred to chaff at %.0f m" % r)
				return true

	# ── torpedoes ───────────────────────────────────────────────────────────
	if p.def.is_torpedo():
		# Wire guidance is an enormous commitment: to keep the wire intact the
		# launcher must stay slow and hold course for the ENTIRE run, which
		# leaves it constrained and vulnerable for minutes. Cutting the wire
		# does not kill the weapon -- it drops it to its own seeker.
		if p.def.torpedo_seeker == SimMunitionDef.TorpedoSeeker.WIRE and p.wire_intact:
			if not entities.is_alive(p.shooter):
				p.wire_intact = false
			else:
				var lv := sqrt(entities.vel_x[p.shooter] * entities.vel_x[p.shooter]
					+ entities.vel_z[p.shooter] * entities.vel_z[p.shooter])
				var lh := atan2(entities.vel_x[p.shooter], entities.vel_z[p.shooter])
				if lv > p.def.wire_max_launcher_speed_ms \
						or (lv > 0.5 and absf(angle_difference(lh, p.launcher_heading))
							> p.def.wire_max_launcher_turn_rad):
					p.wire_intact = false
		# A wake-homer needs a wake, and a submerged submarine leaves none.
		if p.def.torpedo_seeker == SimMunitionDef.TorpedoSeeker.WAKE \
				and entities.depth_m[p.target_truth] > 5.0:
			p.terminate(SimMunitionDef.Termination.DEFEATED_DECOY,
				"wake-homer lost the wake -- the target submerged")
			return true
		var nseq: int = _noise_seq.get(p.target_truth, 0)
		if _noise.get(p.target_truth, 0.0) > 0.0 and p.noisemaker_resolved_seq < nseq:
			p.noisemaker_resolved_seq = nseq
			var mode: int = p.def.torpedo_seeker
			if p.wire_intact and mode == SimMunitionDef.TorpedoSeeker.WIRE:
				mode = SimMunitionDef.TorpedoSeeker.WIRE
			elif mode == SimMunitionDef.TorpedoSeeker.WIRE:
				mode = SimMunitionDef.TorpedoSeeker.PASSIVE
			if _noisemaker_defeats(mode):
				p.terminate(SimMunitionDef.Termination.DEFEATED_DECOY,
					"seduced by a noisemaker at %.0f m" % r)
				return true
		return false

	# Notching: turning perpendicular to a pulse-Doppler seeker puts closure
	# near zero, where its own clutter filter discards the return. Geometry,
	# not a stat check -- and later seeker generations partially defeat it.
	if p.seeker_active and p.def.seeker_gen <= 4 and _is_notching(p):
		p.terminate(SimMunitionDef.Termination.DEFEATED_NOTCH,
			"notched -- seeker lost the return in clutter")
		return true
	return false


func _range_to_target(p: SimProjectile) -> float:
	if not entities.is_alive(p.target_truth):
		return INF
	var dx := entities.pos_x[p.target_truth] - p.x
	var dy := entities.pos_y[p.target_truth] - p.y
	var dz := entities.pos_z[p.target_truth] - p.z
	return sqrt(dx * dx + dy * dy + dz * dz)


## Closure rate near zero relative to the seeker's line of sight.
func _is_notching(p: SimProjectile) -> bool:
	var t := p.target_truth
	var dx := entities.pos_x[t] - p.x
	var dz := entities.pos_z[t] - p.z
	var d := sqrt(dx * dx + dz * dz)
	if d < 1.0:
		return false
	var closure := ((entities.vel_x[t] - p.vx) * dx
			+ (entities.vel_z[t] - p.vz) * dz) / d
	return absf(closure) < 25.0


## docs/10 §4. The guidance loop, re-validated every tick. This is where the
## promises made in docs/02 §5 are actually kept.
func _guidance_valid(p: SimProjectile, track: SimTrack) -> bool:
	match p.def.guidance:
		SimTypes.Guidance.SARH:
			# The illuminator must hold TQ3 for the WHOLE flight. Kill it at
			# second fifteen and the SAM misses -- not because a rule says so,
			# but because this check failed on that tick.
			return track != null and track.quality >= SimTypes.TrackQuality.FIRE_CONTROL
		SimTypes.Guidance.SACLOS:
			return track != null and track.quality >= SimTypes.TrackQuality.TRACK
		SimTypes.Guidance.COMMAND_LINK:
			return track != null and track.quality >= SimTypes.TrackQuality.TRACK
		SimTypes.Guidance.ANTI_RADIATION:
			# Memory mode: it keeps flying at the last known position, so a
			# mobile emitter that shuts down AND moves defeats it.
			return track != null
		SimTypes.Guidance.ARH:
			return p.seeker_active or (track != null
				and track.quality >= SimTypes.TrackQuality.TRACK)
		SimTypes.Guidance.IR_EO:
			return true      # the seeker holds it independently of the network
		SimTypes.Guidance.GNSS_INS:
			return true      # coordinates, not a track
	return track != null


func _retire(idx: int, p: SimProjectile) -> void:
	terminated += 1
	last_impacts.append(_snapshot(p))
	if p.def.tier == SimMunitionDef.Tier.A or p.termination == SimMunitionDef.Termination.HIT:
		combat_log.append("%-9s %s" % [p.def.name, p.log_line()])
		if combat_log.size() > max_log:
			combat_log.pop_front()
	_free.append(idx)


func _decay_countermeasures(dt: float) -> void:
	for d in [_flares, _chaff, _noise]:
		var keys: Array = d.keys()
		keys.sort()
		for k in keys:
			var v: float = d[k] - dt
			if v <= 0.0:
				d.erase(k)
			else:
				d[k] = v


## Every projectile ever fired is either in flight or accounted for. If this
## is ever false, something is leaking onto the map.
func is_balanced() -> bool:
	return launched == terminated + _active.size()


func recent_log(n := 12) -> String:
	var start: int = maxi(0, combat_log.size() - n)
	return "\n".join(combat_log.slice(start))


## Copy out everything the damage layer needs before the projectile goes back
## into the pool. The FACET is computed here, from the round's own velocity
## against the target's heading -- docs/10 §6 and docs/03: hit location is
## geometry, never a roll, and this is where that geometry is still available.
func _snapshot(p: SimProjectile) -> SimImpact:
	var im := SimImpact.new()
	im.target = p.target_truth
	im.shooter = p.shooter
	im.faction = p.faction
	im.termination = p.termination
	im.termination_detail = p.termination_detail
	im.miss_distance_m = p.miss_distance_m if p.miss_distance_m < INF else 0.0
	im.blast_fraction = p.damage_fraction(im.miss_distance_m)
	im.range_m = p.distance_flown_m()
	im.impact_speed_ms = p.speed()
	im.time_s = p.time_s
	im.munition_name = p.def.name
	im.damage_class = p.def.damage_class
	im.penetration_mm = p.def.penetration_mm
	im.tandem = p.def.tandem
	var heading := 0.0
	if entities.is_alive(p.target_truth):
		heading = entities.heading_rad[p.target_truth]
	im.facet = p.impact_facet(heading)
	return im


## Arrivals only -- direct hits and proximity detonations inside the lethal
## radius. Everything else on last_impacts is a round that did not get there,
## which the combat log still wants to report and the damage layer does not.
func arrivals() -> Array:
	var out: Array = []
	for im in last_impacts:
		if (im as SimImpact).is_arrival():
			out.append(im)
	return out


## Where to aim a ballistic round so it ARRIVES at (tx, ty, tz).
##
## The low-arc solution to the vacuum trajectory, then a drag correction. The
## vacuum answer is
##
##     tan(theta) = (v^2 - sqrt(v^4 - g(g R^2 + 2 h v^2))) / (g R)
##
## with R the horizontal range and h the height difference. Quadratic drag then
## bleeds speed over the flight, so the round falls shorter than the vacuum
## solution predicts; the correction below scales the elevation by the ratio of
## the vacuum time of flight to the drag-slowed one, which is accurate enough
## inside direct-fire range and degrades gracefully beyond it.
##
## A target beyond the weapon's maximum ballistic range returns a 45-degree aim
## -- the round then falls short, which is the correct outcome and is visible in
## the combat log rather than being silently clamped into a hit.
func _ballistic_aim_y(sx: float, sy: float, sz: float,
		tx: float, ty: float, tz: float, munition: SimMunitionDef) -> float:
	var dx := tx - sx
	var dz := tz - sz
	var r := sqrt(dx * dx + dz * dz)
	if r < 1.0:
		return ty
	var v := munition.muzzle_velocity
	var h := ty - sy
	var g := SimProjectile.G

	# Drag correction: average speed over the flight, from the quadratic law
	# integrated crudely over the vacuum time of flight.
	var t_vac := r / maxf(v, 1.0)
	var v_avg: float = maxf(v - 0.5 * munition.drag_coefficient * v * v * t_vac, v * 0.35)
	var ve := (v + v_avg) * 0.5

	var v2 := ve * ve
	var disc := v2 * v2 - g * (g * r * r + 2.0 * h * v2)
	if disc < 0.0:
		# Out of ballistic range. Aim at 45 degrees and let it fall short.
		return sy + r
	var tan_theta := (v2 - sqrt(disc)) / (g * r)
	return sy + r * tan_theta
