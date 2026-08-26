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

var launched: int = 0
var terminated: int = 0


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
	p.launch(munition, entities.pos_x[shooter], entities.pos_y[shooter] + 2.0,
		entities.pos_z[shooter], ax, ay, az, shooter,
		entities.faction[shooter], target,
		track.track_id if track != null else -1)
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


## Flares are a HARD counter in epochs 1-3, a coin flip in 4-5, and near
## worthless against imaging seekers from epoch 6 (docs/10 §5, docs/11 §6).
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
			tx, ty, tz, truth_valid)

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
		if (g == SimTypes.Guidance.IR_EO) and _flares.get(p.target_truth, 0.0) > 0.0 \
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
	if p.def.tier == SimMunitionDef.Tier.A or p.termination == SimMunitionDef.Termination.HIT:
		combat_log.append("%-9s %s" % [p.def.name, p.log_line()])
		if combat_log.size() > max_log:
			combat_log.pop_front()
	_free.append(idx)


func _decay_countermeasures(dt: float) -> void:
	for d in [_flares, _chaff]:
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
