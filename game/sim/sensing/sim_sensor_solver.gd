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
## faction id -> SimTrackTable
var tables: Dictionary = {}

## Counts for introspection and tests.
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
		var obs_sensors: Array = entities.sensors.get(observer, [])
		if obs_sensors.is_empty():
			continue
		var table := table_for(entities.faction[observer])
		for s in obs_sensors:
			var sensor := s as SimSensorDef
			# Stagger sensors across ticks so cost spreads instead of spiking.
			if sensor.revisit_seconds > 0.0 and tick > 0:
				var period := maxi(1, int(round(sensor.revisit_seconds)))
				if (tick + sensor.phase_offset) % period != 0:
					continue
			_run_sensor(observer, sensor, table)

	for f in seen_factions:
		table_for(f).decay_all(dt)


func _run_sensor(observer: int, sensor: SimSensorDef, table: SimTrackTable) -> void:
	# A unit under EMCON SILENT will not switch on anything that transmits.
	if sensor.emits and not sensor.is_passive() \
			and entities.emcon[observer] == SimTypes.Emcon.SILENT:
		return

	var own_faction := entities.faction[observer]
	for target in range(entities.count()):
		if target == observer or not entities.is_alive(target):
			continue
		if entities.faction[target] == own_faction:
			continue   # own force is known, not detected
		last_pair_evaluations += 1

		var r_km := entities.range_km(observer, target)
		var reach := _reach_km(observer, sensor, target)
		if reach <= 0.0 or r_km > reach:
			continue

		last_detections += 1
		_contribute(observer, sensor, target, table, r_km)


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
			reach = minf(reach, P.horizon_km(sensor.mount_height_m,
					entities.pos_y[target]))

		SimTypes.Domain.RF_PASSIVE:
			var power := entities.emitted_power(target)
			if power <= 0.0:
				return 0.0   # a silent target gives ESM nothing to hear
			reach = P.passive_range_km(sensor.reference_range_km, power)
			reach *= P.esm_advantage(_target_radar_gen(target), sensor.esm_gen)
			reach = minf(reach, P.horizon_km(sensor.mount_height_m,
					entities.pos_y[target]))

		SimTypes.Domain.IR:
			reach = P.passive_range_km(sensor.reference_range_km,
					entities.effective_ir(target))
			reach = minf(reach, P.horizon_km(sensor.mount_height_m,
					entities.pos_y[target]))

		SimTypes.Domain.EO:
			reach = P.passive_range_km(sensor.reference_range_km,
					entities.visual_m2[target] / 10.0)
			reach = minf(reach, P.horizon_km(sensor.mount_height_m,
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


func _apply_jamming(observer: int, sensor: SimSensorDef,
		target: int, nominal: float) -> float:
	var total_jnr := 0.0
	for j in range(entities.count()):
		if not entities.is_alive(j) or entities.jammer_power[j] <= 0.0:
			continue
		if entities.faction[j] == entities.faction[observer]:
			continue
		var jr := entities.range_km(observer, j)
		total_jnr += P.jam_noise_ratio(entities.jammer_power[j], jr,
				sensor.eccm_rating)
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
