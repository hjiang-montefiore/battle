class_name SimSensorSolver
extends RefCounted
## The one detection solver. docs/02.
##
## There is no radar system, sonar system, jamming system and AWACS system.
## There is this, with a signature on every unit, a sensor list on every unit,
## a propagation model per domain, and a track produced per (faction, target)
## pair. An E-3 is not a special unit type -- it is a radar with a very large
## mount_height, and the horizon formula does the rest.

const P := preload("res://sim/sensing/sim_propagation.gd")

## Depth below which the thermocline shields a submarine from sensors above it.
const LAYER_DEPTH_M := 120.0

var entities: SimEntities
## The ground. Null means a featureless plane, which is what the proving ground
## and most unit tests want.
var terrain: SimTerrain = null
## faction id -> SimTrackTable
var tables: Dictionary = {}

## Counts for introspection and tests.
## Per-solve scratch. Cleared at the top of solve(); never read outside it.
var _jammers: PackedInt32Array = PackedInt32Array()
var _jnr_cache: Dictionary = {}

## Line-of-sight memo. NOT per-solve: it survives across solves and is
## invalidated by MOVEMENT rather than by time. See _has_line_of_sight.
var _los_cache: Dictionary = {}

## The current sensor's own altitude, hoisted out of the target loop.
var _alt_cache: float = 0.0

## Temporary phase timers, microseconds. Set PROFILE = true to fill them.
static var PROFILE := false
var t_reach := 0
var t_los := 0
var t_contribute := 0
var n_reach := 0
var n_los := 0

var last_pair_evaluations: int = 0
var last_detections: int = 0


func _init(store: SimEntities) -> void:
	entities = store


func table_for(faction_id: int) -> SimTrackTable:
	if not tables.has(faction_id):
		tables[faction_id] = SimTrackTable.new(faction_id)
	return tables[faction_id]


## Deterministic faction ordering.
func faction_ids() -> Array:
	var ids: Array = tables.keys()
	ids.sort()
	return ids


## One sensor solve. Run at 5-10 Hz, not the simulation rate: a radar's real
## revisit time is seconds anyway, so the slow tick is MORE realistic, not less
## (docs/02 §9). dt is the time since the previous solve.
func solve(dt: float, tick: int = 0) -> void:
	last_pair_evaluations = 0
	last_detections = 0

	# Gather the jammers ONCE. See _apply_jamming for why this matters.
	_jammers.clear()
	_jnr_cache.clear()
	for j in range(entities.count()):
		# A jammer stowed in a transport's hold jams nothing (the carried-unit
		# doctrine in sim_entities.gd: aboard = off the map).
		if entities.is_alive(j) and not entities.is_aboard(j) \
				and entities.jammer_power[j] > 0.0:
			_jammers.append(j)

	# Make sure every live faction has a table, in deterministic order.
	var seen_factions: Array = []
	for i in range(entities.count()):
		if entities.is_alive(i) and not seen_factions.has(entities.faction[i]):
			seen_factions.append(entities.faction[i])
	seen_factions.sort()
	for f in seen_factions:
		table_for(f).begin_solve()

	for observer in range(entities.count()):
		if not entities.is_alive(observer):
			continue
		# A unit aboard a transport does not sense: its sensors are stowed
		# with it. It re-joins the picture the tick after it unloads.
		if entities.is_aboard(observer):
			continue
		var obs_sensors: Array = entities.sensors.get(observer, [])
		if obs_sensors.is_empty():
			continue
		var table := table_for(entities.faction[observer])
		for s in obs_sensors:
			var sensor := s as SimSensorDef
			# Stagger sensors across ticks so cost spreads instead of spiking.
			#
			# revisit_seconds is in SECONDS, and it used to be compared against
			# the SOLVE COUNTER -- so a 4 s revisit meant "every fourth solve",
			# which at SENSOR_HZ = 5 is 0.8 s. `dt` is the elapsed time since
			# the previous solve and is already passed in, so converting here
			# costs nothing and makes the field mean what it is called. A
			# mechanically-scanned search radar really does sweep past a target
			# once a rotation and see nothing in between (docs/02 §9), so this
			# is realism and a large saving at the same time: the solve is
			# O(sensors x targets) and this is a divisor on the sensor term.
			if sensor.revisit_seconds > 0.0 and tick > 0 and dt > 0.0:
				var period := maxi(1, int(round(sensor.revisit_seconds / dt)))
				if (tick + sensor.phase_offset) % period != 0:
					continue
			_run_sensor(observer, sensor, table)

	for f in seen_factions:
		table_for(f).decay_all(dt)


## Acoustic sensing happens underwater and is not masked by hills; everything
## that travels through air is.
## MEASURED: this was 58.7% of the entire sensor solve.
##
## The range test in front of it culls almost nothing, and cannot: a search
## radar reaches well over 100 km and the skirmish arena is 12.8 km across, so
## every pair is "in range" and every pair pays a full ray march across the
## heightfield to discover that the ridge in the middle blocks it.
##
## Terrain does not move and units do not move far between solves -- at 5 Hz a
## 20 m/s vehicle travels 4 m -- so the answer is stable for many solves in a
## row. This caches it per (observer, target, mount height band) and re-marches
## only when an endpoint has actually moved enough to matter.
##
## THE TRADE, stated plainly: a unit cresting a ridge can be seen up to
## LOS_CACHE_M / speed later than it truly appeared. At 60 m and 20 m/s that is
## 3 s. That is a real fidelity cost, and it is bounded by distance rather than
## by time, so a fast mover invalidates its own entry sooner -- which is the
## right shape, because a fast mover is exactly what you must not miss.
const LOS_CACHE_M := 60.0

func _has_line_of_sight(observer: int, sensor: SimSensorDef, target: int) -> bool:
	if terrain == null:
		return true
	match sensor.domain:
		SimTypes.Domain.ACOUSTIC_ACTIVE, SimTypes.Domain.ACOUSTIC_PASSIVE, \
		SimTypes.Domain.MAGNETIC:
			return true

	# Mount height changes the answer, so it is part of the key -- banded,
	# because a 2 m difference in mast height does not change what a ridge hides.
	var band := int(maxf(sensor.mount_height_m, 0.0) / 5.0)
	var key := (observer * 4096 + target) * 64 + band
	var hit = _los_cache.get(key)
	var ox: float = entities.pos_x[observer]
	var oz: float = entities.pos_z[observer]
	var tx: float = entities.pos_x[target]
	var tz: float = entities.pos_z[target]
	if hit != null:
		if absf(hit[1] - ox) + absf(hit[2] - oz) \
				+ absf(hit[3] - tx) + absf(hit[4] - tz) < LOS_CACHE_M:
			return hit[0]

	# The sensor sits mount_height above the GROUND it is standing on, which is
	# where high ground pays (docs/12: "free range on high ground").
	var oy := entities.pos_y[observer]
	if entities.category[observer] != SimTypes.Category.AIR:
		oy = terrain.ground_under(ox, oz) + maxf(sensor.mount_height_m, 0.0)
	var clear := terrain.has_line_of_sight(
		ox, oy, oz, tx, entities.pos_y[target], tz)
	_los_cache[key] = [clear, ox, oz, tx, tz]
	return clear


## Effective sensor altitude: an airborne unit flies at its own y, a ground one
## stands on whatever the terrain gives it.
func _sensor_altitude(observer: int, sensor: SimSensorDef) -> float:
	if terrain == null or entities.category[observer] == SimTypes.Category.AIR:
		return maxf(sensor.mount_height_m, 0.0) \
			if entities.category[observer] != SimTypes.Category.AIR \
			else entities.pos_y[observer]
	return terrain.ground_under(entities.pos_x[observer],
		entities.pos_z[observer]) + maxf(sensor.mount_height_m, 0.0)


func _run_sensor(observer: int, sensor: SimSensorDef, table: SimTrackTable) -> void:
	# A unit under EMCON SILENT will not switch on anything that transmits.
	if sensor.emits and not sensor.is_passive() \
			and entities.emcon[observer] == SimTypes.Emcon.SILENT:
		return

	var own_faction := entities.faction[observer]
	# Hoisted out of the target loop. This samples the heightfield, and it is a
	# function of the OBSERVER and the sensor only -- computing it per target
	# resampled identical terrain up to N times per sensor. Measured at 30% of
	# _reach_km, which was itself 56% of the whole solve.
	_alt_cache = _sensor_altitude(observer, sensor)
	for target in range(entities.count()):
		if target == observer or not entities.is_alive(target):
			continue
		# A unit aboard a transport is not sensed -- it is off the map. Its
		# existing tracks age out exactly as if it had gone silent.
		if entities.is_aboard(target):
			continue
		if entities.faction[target] == own_faction:
			continue   # own force is known, not detected
		last_pair_evaluations += 1

		var r_km := entities.range_km(observer, target)
		var _t0 := Time.get_ticks_usec() if PROFILE else 0
		var reach := _reach_km(observer, sensor, target)
		if PROFILE:
			t_reach += Time.get_ticks_usec() - _t0
			n_reach += 1
		if reach <= 0.0 or r_km > reach:
			continue

		# Terrain masking, docs/02 §1: "Line of sight blocked -> no RF/IR/visual
		# detection AT ALL." Not a range penalty and not a probability. Checked
		# only after the range test, because marching a ray across a theatre is
		# far more expensive than comparing two numbers.
		var _t1 := Time.get_ticks_usec() if PROFILE else 0
		var clear := _has_line_of_sight(observer, sensor, target)
		if PROFILE:
			t_los += Time.get_ticks_usec() - _t1
			n_los += 1
		if not clear:
			continue

		last_detections += 1
		var _t2 := Time.get_ticks_usec() if PROFILE else 0
		_contribute(observer, sensor, target, table, r_km)
		if PROFILE:
			t_contribute += Time.get_ticks_usec() - _t2


## Effective detection range of one sensor against one target, in km.
## Returns 0 when the target is undetectable by this sensor at any range.
func _reach_km(observer: int, sensor: SimSensorDef, target: int) -> float:
	var reach := 0.0

	match sensor.domain:
		SimTypes.Domain.RF_ACTIVE:
			var rcs := entities.effective_rcs(target, observer)
			reach = P.active_range_km(sensor.reference_range_km, rcs)
			# R3 cliff: before pulse-Doppler a radar looking down sees clutter
			# and nothing else, so terrain-following flight is a COMPLETE
			# defence in epochs 1-2 (docs/11 §3).
			if not P.has_look_down(sensor.radar_gen,
					sensor.mount_height_m, entities.pos_y[target]):
				return 0.0
			reach = _apply_jamming(observer, sensor, target, reach)
			reach = minf(reach, P.horizon_km(_alt_cache,
					entities.pos_y[target]))

		SimTypes.Domain.RF_PASSIVE:
			var power := entities.emitted_power(target)
			if power <= 0.0:
				return 0.0   # a silent target gives ESM nothing to hear
			reach = P.passive_range_km(sensor.reference_range_km, power)
			reach *= P.esm_advantage(_target_radar_gen(target), sensor.esm_gen)
			reach = minf(reach, P.horizon_km(_alt_cache,
					entities.pos_y[target]))

		SimTypes.Domain.IR:
			reach = P.passive_range_km(sensor.reference_range_km,
					entities.effective_ir(target))
			reach = minf(reach, P.horizon_km(_alt_cache,
					entities.pos_y[target]))

		SimTypes.Domain.EO:
			reach = P.passive_range_km(sensor.reference_range_km,
					entities.visual_m2[target] / 10.0)
			reach = minf(reach, P.horizon_km(_alt_cache,
					entities.pos_y[target]))

		SimTypes.Domain.ACOUSTIC_ACTIVE:
			if not _acoustically_visible(observer, sensor, target):
				return 0.0
			reach = P.active_range_km(sensor.reference_range_km, 1.0)
			reach *= _own_noise_penalty(observer)

		SimTypes.Domain.ACOUSTIC_PASSIVE:
			if not _acoustically_visible(observer, sensor, target):
				return 0.0
			# dB above a 100 dB reference, converted to a power ratio.
			var db := entities.effective_acoustic_db(target)
			var pw: float = pow(10.0, (db - 100.0) / 20.0)
			reach = P.passive_range_km(sensor.reference_range_km, pw)
			reach *= _own_noise_penalty(observer)

		SimTypes.Domain.MAGNETIC:
			if entities.magnetic[target] <= 0.0:
				return 0.0
			reach = sensor.reference_range_km   # MAD confirms a datum, no more

	return maxf(reach, 0.0)


## The thermocline. Below it a submarine is close to undetectable from above --
## an ABSOLUTE shield before towed arrays (N3), merely a strong advantage after
## (docs/02 §8.3, docs/11 §7).
func _acoustically_visible(observer: int, sensor: SimSensorDef, target: int) -> bool:
	var target_deep := entities.below_layer[target] == 1 \
			or entities.depth_m[target] > LAYER_DEPTH_M
	if not target_deep:
		return true
	# A sensor streamed below the layer -- towed array, VDS, dipping sonar --
	# is modelled by giving it a negative mount height.
	var sensor_deep := sensor.mount_height_m < 0.0
	return sensor_deep


## Sonar performance scales inversely with your own speed: a ship at flank speed
## is deaf (docs/02 §8.4).
func _own_noise_penalty(observer: int) -> float:
	var v := sqrt(entities.vel_x[observer] * entities.vel_x[observer]
			+ entities.vel_z[observer] * entities.vel_z[observer])
	var knots := v * 1.94384
	return clampf(1.0 - (knots / 40.0), 0.15, 1.0)


## Jamming reduces a sensor's reach. The KEY OBSERVATION is that the amount
## does not depend on the TARGET at all -- it is a function of the observer's
## position and the sensor's ECCM rating -- yet the original scanned every
## entity in the game for every (observer, sensor, TARGET) triple, recomputing
## an identical answer once per target.
##
## Measured on a 46-entity peer match: 173 ms per solve for 322 pair
## evaluations and zero detections, i.e. 537 us per pair, on a map with no
## jammers deployed at all. The scan ran regardless.
##
## Now the jammer list is gathered once per solve and the noise total is
## memoised per (observer, eccm). With no jammers present the inner loop does
## not execute at all.
func _apply_jamming(observer: int, sensor: SimSensorDef,
		_target: int, nominal: float) -> float:
	if _jammers.is_empty():
		return nominal
	var key := observer * 64 + sensor.eccm_rating
	var total_jnr: float = _jnr_cache.get(key, -1.0)
	if total_jnr < 0.0:
		total_jnr = 0.0
		var own := entities.faction[observer]
		for j in _jammers:
			if entities.faction[j] == own:
				continue
			total_jnr += P.jam_noise_ratio(entities.jammer_power[j],
				entities.range_km(observer, j), sensor.eccm_rating)
		_jnr_cache[key] = total_jnr
	if total_jnr <= 0.0:
		return nominal
	return P.jammed_range_km(nominal, total_jnr)


func _target_radar_gen(target: int) -> int:
	var g := 1
	for s in entities.sensors.get(target, []):
		var sd := s as SimSensorDef
		if not sd.is_passive():
			g = maxi(g, sd.radar_gen)
	return g


func _contribute(observer: int, sensor: SimSensorDef, target: int,
		table: SimTrackTable, r_km: float) -> void:
	var quality: int = sensor.max_quality
	if sensor.is_bearing_only():
		quality = mini(quality, SimTypes.TrackQuality.CONTACT)

	var cls := _classify(sensor, target, r_km)

	# Confidence falls off toward the edge of the envelope.
	var reach := maxf(_reach_km(observer, sensor, target), 0.001)
	var conf: float = clampf(1.0 - (r_km / reach) * 0.6, 0.15, 1.0)

	table.contribute(
		target, quality, cls, conf, sensor.name,
		entities.pos_x[target], entities.pos_y[target], entities.pos_z[target],
		entities.vel_x[target], entities.vel_y[target], entities.vel_z[target],
		entities.bearing_rad(observer, target),
		sensor.is_bearing_only(),
		entities.category[target],
		entities.is_emitting(target))


## Classification comes from different sources than position (docs/02 §5.1).
## The inversion worth building the system for: a PASSIVE sensor with a poor
## position solution delivers BETTER classification than an active one with a
## perfect solution, because a specific radar emission names the platform
## carrying it.
func _classify(sensor: SimSensorDef, target: int, r_km: float) -> int:
	match sensor.domain:
		SimTypes.Domain.RF_PASSIVE:
			# P3+ carries an emitter library: bearing plus a name.
			if sensor.esm_gen >= 3:
				return SimTypes.Classification.TYPE
			if sensor.esm_gen >= 2:
				return SimTypes.Classification.CLASS
			return SimTypes.Classification.CATEGORY
		SimTypes.Domain.EO:
			# Visual identification, but only close in.
			if r_km < sensor.reference_range_km * 0.3:
				return SimTypes.Classification.TYPE
			return SimTypes.Classification.CLASS
		SimTypes.Domain.IR:
			return SimTypes.Classification.CLASS
		SimTypes.Domain.RF_ACTIVE:
			# Signature matching is a late-epoch capability; before it a radar
			# gives you kinematics, which is free but coarse.
			if sensor.radar_gen >= 5:
				return SimTypes.Classification.CLASS
			return SimTypes.Classification.CATEGORY
		SimTypes.Domain.ACOUSTIC_PASSIVE:
			return SimTypes.Classification.CLASS   # blade rate names the boat
		SimTypes.Domain.ACOUSTIC_ACTIVE:
			return SimTypes.Classification.CATEGORY
		SimTypes.Domain.MAGNETIC:
			return SimTypes.Classification.CATEGORY
	return SimTypes.Classification.UNKNOWN
