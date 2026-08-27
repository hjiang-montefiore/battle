class_name SimHarvest
extends RefCounted
## THE ORE CYCLE: find ore, fill up, drive it home, unload, go again.
##
## This is the loop Red Alert is built on, and the reason it matters here is
## not the money -- oil derricks already make money. It is that ore money
## MOVES. A harvester is an unarmed vehicle carrying several hundred credits
## across open ground, so a raid on the economy is a real operation with a real
## reward, and defending the ore line is a real cost. An economy that cannot be
## attacked is just a timer.
##
## THE STATE MACHINE, one column on the harvester, four states:
##
##   SEEKING   no load, no field -- look for the richest field in range
##   MINING    parked on a field, filling at mine_rate credits/second
##   RETURNING full (or the field is dry) -- drive to the nearest refinery
##   UNLOADING parked at the refinery, emptying at unload_rate/second
##
## Harvesters work WITHOUT ORDERS, the way they do in the genre: a player who
## builds one should not have to micromanage it. A manual move order suspends
## the cycle until the unit is idle again, so telling one to run away works and
## it goes back to work afterwards.
##
## WHAT THIS LAYER OWNS: harvest_state, harvest_load, harvest_target. It reads
## the economy for fields and dropoffs and asks SimMovement to drive. It never
## writes position, and it never grants credits except through
## SimEconomy.add_income() -- so a harvester's earnings show up in the same
## income accounting as everything else.

enum State { SEEKING, MINING, RETURNING, UNLOADING }

## How far a harvester will look for a field before giving up for this tick.
const SEARCH_RADIUS_M := 4000.0

## Close enough to count as "at" a field or a refinery.
const ARRIVE_M := 95.0

## Re-issue a drive order at most this often. Movement plans paths; asking it
## to replan every tick for a stationary goal is the expensive way to stand
## still.
const REORDER_S := 2.0

var entities: SimEntities
var economy: SimEconomy
var movement: SimMovement

## Diagnostics, and the reason the tests can prove a full cycle happened.
var loads_delivered: int = 0
var credits_delivered: float = 0.0

var _reorder := PackedFloat32Array()
## 1 while a player's own order is being carried out.
var _suspended := PackedInt32Array()


func _init(store: SimEntities, econ: SimEconomy, move: SimMovement) -> void:
	entities = store
	economy = econ
	movement = move


static func install(world: SimWorld) -> SimHarvest:
	var h := SimHarvest.new(world.entities, world.economy, world.movement)
	world.harvest_system = h
	return h


func is_implemented() -> bool:
	return true


## True for a unit this layer drives. Capacity is the marker: a def with
## ore_capacity above zero is a harvester and nothing else is, so no role-name
## string comparison leaks into the simulation.
func is_harvester(unit: int) -> bool:
	if unit < 0 or unit >= entities.count() or entities.alive[unit] == 0:
		return false
	var d := economy.def_of(unit)
	return d != null and d.ore_capacity > 0.0


func step(dt: float) -> void:
	if dt <= 0.0:
		return
	_ensure(entities.count())
	for i in range(entities.count()):
		if not is_harvester(i):
			continue
		if not entities.can_move(i):
			continue
		_reorder[i] = maxf(_reorder[i] - dt, 0.0)
		# A PLAYER ORDER WINS, and keeps winning until it is finished. Merely
		# resetting the state machine was not enough: _seek ran on the very
		# next tick and drove the unit straight back to the ore, so "get out of
		# there" lasted a fraction of a second. The cycle resumes on its own
		# once the unit is idle again, which is the behaviour that lets someone
		# pull a harvester out of a raid without adopting it for life.
		if _suspended[i] == 1:
			if entities.has_dest[i] == 1:
				continue
			_suspended[i] = 0
		match entities.harvest_state[i]:
			State.SEEKING: _seek(i)
			State.MINING: _mine(i, dt)
			State.RETURNING: _return(i)
			State.UNLOADING: _unload(i, dt)


## A player order takes precedence: a harvester told to go somewhere stops
## harvesting until it arrives. Called by SimWorld when a move lands on one.
func interrupt(unit: int) -> void:
	if not is_harvester(unit):
		return
	_ensure(entities.count())
	entities.harvest_state[unit] = State.SEEKING
	entities.harvest_target[unit] = -1
	_reorder[unit] = REORDER_S
	_suspended[unit] = 1


func _seek(i: int) -> void:
	var d := economy.def_of(i)
	# A load already aboard means the cycle was interrupted mid-run; take it
	# home rather than topping up, so an interrupted harvester still banks.
	if entities.harvest_load[i] >= d.ore_capacity - 0.01 \
			or (entities.harvest_load[i] > 0.0 and _no_ore_left()):
		entities.harvest_state[i] = State.RETURNING
		entities.harvest_target[i] = -1
		return
	var field := economy.ore_field_near(entities.pos_x[i], entities.pos_z[i],
		SEARCH_RADIUS_M)
	if field < 0:
		if entities.harvest_load[i] > 0.0:
			entities.harvest_state[i] = State.RETURNING
		return
	entities.harvest_target[i] = field
	var f: Vector2 = economy.ore_fields[field]
	if _dist(i, f.x, f.y) <= ARRIVE_M:
		entities.harvest_state[i] = State.MINING
		movement.stop(i)
	else:
		_drive(i, f.x, f.y)


func _mine(i: int, dt: float) -> void:
	var d := economy.def_of(i)
	var field: int = entities.harvest_target[i]
	if field < 0 or field >= economy.ore_remaining.size() \
			or economy.ore_remaining[field] <= 0.0:
		entities.harvest_state[i] = State.RETURNING if entities.harvest_load[i] > 0.0 \
			else State.SEEKING
		return
	var f: Vector2 = economy.ore_fields[field]
	if _dist(i, f.x, f.y) > ARRIVE_M * 1.5:
		entities.harvest_state[i] = State.SEEKING
		return
	var room: float = d.ore_capacity - entities.harvest_load[i]
	entities.harvest_load[i] += economy.take_ore(field, minf(d.mine_rate * dt, room))
	if entities.harvest_load[i] >= d.ore_capacity - 0.01:
		entities.harvest_state[i] = State.RETURNING
		entities.harvest_target[i] = -1


func _return(i: int) -> void:
	if entities.harvest_load[i] <= 0.0:
		entities.harvest_state[i] = State.SEEKING
		return
	var home := economy.nearest_dropoff(entities.owner[i],
		entities.pos_x[i], entities.pos_z[i])
	if home < 0:
		# Nowhere to take it. Hold the load rather than dumping it: a player
		# whose refinery was just destroyed gets their ore back when they
		# rebuild, which is fairer and reads as obviously correct.
		return
	entities.harvest_target[i] = home
	var hx := entities.pos_x[home]
	var hz := entities.pos_z[home]
	if _dist(i, hx, hz) <= ARRIVE_M:
		entities.harvest_state[i] = State.UNLOADING
		movement.stop(i)
	else:
		_drive(i, hx, hz)


func _unload(i: int, dt: float) -> void:
	var d := economy.def_of(i)
	var home: int = entities.harvest_target[i]
	if home < 0 or home >= entities.count() or entities.alive[home] == 0:
		entities.harvest_state[i] = State.RETURNING
		return
	var moved: float = minf(d.unload_rate * dt, entities.harvest_load[i])
	entities.harvest_load[i] -= moved
	economy.add_income(entities.owner[i], moved)
	credits_delivered += moved
	if entities.harvest_load[i] <= 0.01:
		entities.harvest_load[i] = 0.0
		loads_delivered += 1
		entities.harvest_state[i] = State.SEEKING
		entities.harvest_target[i] = -1


func _drive(i: int, x: float, z: float) -> void:
	if _reorder[i] > 0.0:
		return
	_reorder[i] = REORDER_S
	movement.order_move(i, x, z)


func _dist(i: int, x: float, z: float) -> float:
	var dx := entities.pos_x[i] - x
	var dz := entities.pos_z[i] - z
	return sqrt(dx * dx + dz * dz)


func _no_ore_left() -> bool:
	for k in range(economy.ore_remaining.size()):
		if economy.ore_remaining[k] > 0.0:
			return false
	return true


func _ensure(n: int) -> void:
	while _reorder.size() < n:
		_reorder.append(0.0)
	while _suspended.size() < n:
		_suspended.append(0)


func state_name(unit: int) -> String:
	match entities.harvest_state[unit]:
		State.SEEKING: return "seeking"
		State.MINING: return "mining"
		State.RETURNING: return "returning"
		State.UNLOADING: return "unloading"
	return "?"


func to_dict() -> Dictionary:
	return {
		"reorder": SimSave.b64_f32(_reorder),
		"suspended": SimSave.b64_i32(_suspended),
		"counters": [loads_delivered, SimSave.enc_float(credits_delivered)],
	}


func from_dict(d: Dictionary) -> void:
	_reorder = SimSave.un_f32(String(d["reorder"]))
	_suspended = SimSave.un_i32(String(d["suspended"]))
	var c: Array = d["counters"]
	loads_delivered = int(c[0])
	credits_delivered = SimSave.dec_float(c[1])
