class_name SimWorld
extends RefCounted
## The simulation. docs/06.
##
## Three rates, because getting this wrong is the most likely performance
## failure: movement at the simulation rate, sensing on a slow tick, logistics
## and AI slower still. The sensor solve is O(sensors x targets) and is the
## single hottest thing in the game -- running it at 5 Hz instead of 30 Hz is a
## 6x saving no player can perceive, because a radar's real revisit time is
## seconds anyway. The slow tick is MORE realistic, not less.
##
## Nothing here touches the scene tree. Godot's job is to render this and submit
## commands to it; that is the whole contract.

const SIM_HZ := 20.0        ## docs/06 tick budget: simulation 20-30 Hz
const SENSOR_HZ := 5.0      ## docs/06 tick budget: sensor solve 5-10 Hz

var entities: SimEntities
var solver: SimSensorSolver
var munitions: SimMunitions
var rng: SimRng

var tick: int = 0
var sensor_tick: int = 0
var elapsed_s: float = 0.0

var _sim_accum: float = 0.0
var _sensor_accum: float = 0.0

## Set false to drive the sim by exact ticks in tests.
var use_accumulator: bool = true


func _init(seed_value: int = 12345) -> void:
	entities = SimEntities.new()
	solver = SimSensorSolver.new(entities)
	rng = SimRng.new(seed_value)
	munitions = SimMunitions.new(entities, solver, rng.fork(0x4D))


## Advance by wall-clock dt. Presentation calls this; it is the only entry point.
func step(dt: float) -> void:
	if not use_accumulator:
		_sim_step(1.0 / SIM_HZ)
		return
	_sim_accum += dt
	var sim_dt := 1.0 / SIM_HZ
	# Bound catch-up so a stall cannot spiral.
	var guard := 0
	while _sim_accum >= sim_dt and guard < 8:
		_sim_accum -= sim_dt
		_sim_step(sim_dt)
		guard += 1


func _sim_step(dt: float) -> void:
	tick += 1
	elapsed_s += dt
	_integrate(dt)
	# Tier A runs at the full simulation rate: the guidance loop is
	# re-validated every tick, not just at launch (docs/10 §4, §9).
	munitions.step(dt)

	_sensor_accum += dt
	var sensor_dt := 1.0 / SENSOR_HZ
	if _sensor_accum >= sensor_dt:
		solver.solve(_sensor_accum, sensor_tick)
		sensor_tick += 1
		_sensor_accum = 0.0


## Hand-written movement. docs/06 forbids Godot physics for units: RigidBody3D
## and CharacterBody3D are neither deterministic nor suited to hundreds of units.
func _integrate(dt: float) -> void:
	for i in range(entities.count()):
		if entities.alive[i] == 0:
			continue
		entities.pos_x[i] += entities.vel_x[i] * dt
		entities.pos_y[i] += entities.vel_y[i] * dt
		entities.pos_z[i] += entities.vel_z[i] * dt


## Run exactly n simulation ticks, ignoring the accumulator. For tests and for
## the headless AI-vs-AI harness, which needs to run many times real speed.
func run_ticks(n: int) -> void:
	var sim_dt := 1.0 / SIM_HZ
	for _i in range(n):
		_sim_step(sim_dt)


## The AI's entire interface (docs/06, docs/09 §1). It is handed this and never
## the entity store, so it cannot read ground truth even by accident.
func track_table_for(faction_id: int) -> SimTrackTable:
	return solver.table_for(faction_id)


## Hash of sim state for replay verification and desync detection. docs/06
## milestone 1: "Hash the sim state every N ticks; a replay that diverges tells
## you exactly which tick broke."
func state_hash() -> int:
	var buf := PackedFloat64Array()
	for i in range(entities.count()):
		buf.append(entities.pos_x[i])
		buf.append(entities.pos_y[i])
		buf.append(entities.pos_z[i])
		buf.append(entities.vel_x[i])
		buf.append(entities.vel_z[i])
		buf.append(float(entities.alive[i]))
		buf.append(float(entities.emcon[i]))
	# Track state matters too -- a desync in the picture is still a desync.
	for f in solver.faction_ids():
		var table: SimTrackTable = solver.tables[f]
		for id in table.track_ids():
			var t := table.get_track(id)
			buf.append(float(t.quality))
			buf.append(float(t.classification))
			buf.append(snappedf(t.age_s, 0.0001))
	# PackedByteArray has no .hash() in Godot 4; the global hash() takes the
	# array directly and is stable for a given byte sequence.
	return hash(buf)


func describe() -> String:
	var lines := PackedStringArray()
	lines.append("tick %d  (%.2f s)  sensor solves %d" % [tick, elapsed_s, sensor_tick])
	for f in solver.faction_ids():
		lines.append((solver.tables[f] as SimTrackTable).describe())
	return "\n".join(lines)
