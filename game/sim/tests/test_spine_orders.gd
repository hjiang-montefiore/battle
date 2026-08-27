extends SceneTree
## Tests for the spine's order extension: PATROL / LOAD / UNLOAD / DEPLOY /
## SORTIE_STRIKE / SORTIE_PATROL through SimCommandQueue, and the entity state
## behind them -- deploy_state, the cargo model, home_base and sortie_state.
##
##     godot --path game --headless --script res://sim/tests/test_spine_orders.gd
##
## A SEPARATE file on purpose: three agents build the patrol, transport and
## sortie systems in parallel against this contract, and this file is the
## contract being asserted -- what the QUEUE accepts and validates, what the
## SPINE stores, and what being carried MEANS. It does not test the systems
## themselves; they do not exist yet, and the routing suite proves exactly
## that with stubs.

var _passed := 0
var _failed := 0
var _code := 1


func _init() -> void:
	print("")
	print("  BATTLE -- spine order tests (patrol / transport / deploy / sortie)")
	print("  " + "-".repeat(66))

	_suite_vocabulary()
	_suite_constructors()
	_suite_authorisation()
	_suite_routing()
	_suite_cargo_state()
	_suite_carried_invisible()
	_suite_kill_cascade()
	_suite_hash()
	_suite_determinism()

	print("  " + "-".repeat(66))
	if _failed == 0:
		print("  %d passed, 0 failed" % _passed)
	else:
		print("  %d passed, %d FAILED" % [_passed, _failed])
	print("")
	_code = 1 if _failed > 0 else 0


## The guard the other tests use: a script error in _init() leaves _code = 1
## and this still runs, so the harness gets an exit instead of a silent hang.
func _process(_delta: float) -> bool:
	quit(_code)
	return true


func _suite(name: String) -> void:
	print("")
	print("  " + name)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		_passed += 1
		print("    PASS  %s%s" % [label, ("  " + detail) if detail else ""])
	else:
		_failed += 1
		print("    FAIL  %s%s" % [label, ("  " + detail) if detail else ""])


# ── stub systems, for the routing suite ──────────────────────────────────────
## The smallest object satisfying each duck-typed contract in sim_world.gd.
## They record what reached them, which is the whole point.

class StubPatrol extends RefCounted:
	var calls: Array = []
	var steps: int = 0
	func order_patrol(unit: int, points: PackedFloat32Array) -> bool:
		calls.append(["patrol", unit, points.size()])
		return true
	func step(_dt: float) -> void:
		steps += 1
	func is_implemented() -> bool:
		return true


class StubTransport extends RefCounted:
	var calls: Array = []
	var steps: int = 0
	func order_load(unit: int, transport: int) -> bool:
		calls.append(["load", unit, transport])
		return true
	func order_unload(transport: int, passenger: int) -> bool:
		calls.append(["unload", transport, passenger])
		return true
	func order_deploy(unit: int) -> bool:
		calls.append(["deploy", unit])
		return true
	func step(_dt: float) -> void:
		steps += 1
	func is_implemented() -> bool:
		return true


class StubSortie extends RefCounted:
	var calls: Array = []
	var steps: int = 0
	func order_strike(unit: int, x: float, z: float) -> bool:
		calls.append(["strike", unit, x, z])
		return true
	func order_patrol(unit: int, x: float, z: float, radius_m: float) -> bool:
		calls.append(["patrol", unit, x, z, radius_m])
		return true
	func step(_dt: float) -> void:
		steps += 1
	func is_implemented() -> bool:
		return true


# ── scenario construction ────────────────────────────────────────────────────

func _radar() -> SimSensorDef:
	return SimSensorDef.new({
		"name": "radar", "domain": SimTypes.Domain.RF_ACTIVE,
		"band": SimTypes.Band.X, "reference_range_km": 120.0,
		"mount_height_m": 20.0, "radar_gen": 5, "emits": true,
		"max_quality": SimTypes.TrackQuality.FIRE_CONTROL})


func _unit(w: SimWorld, unit_name: String, faction: int, owner_id: int,
		x: float, z: float, sensors: Array = []) -> int:
	var i := w.entities.add(unit_name, faction, x, 0.0, z,
		SimSignature.new(20.0), sensors, SimTypes.Category.GROUND, -1.0, owner_id)
	w.entities.set_mobility(i, 10.0, 2.0, 1.0)
	return i


# ── 1. vocabulary ────────────────────────────────────────────────────────────

func _suite_vocabulary() -> void:
	_suite("The shared vocabulary carries the six new order kinds")

	var kinds := [SimTypes.OrderKind.PATROL, SimTypes.OrderKind.LOAD,
		SimTypes.OrderKind.UNLOAD, SimTypes.OrderKind.DEPLOY,
		SimTypes.OrderKind.SORTIE_STRIKE, SimTypes.OrderKind.SORTIE_PATROL]
	var distinct := true
	for a in range(kinds.size()):
		for b in range(a + 1, kinds.size()):
			if kinds[a] == kinds[b]:
				distinct = false
	_ok("six new OrderKind members, all distinct", distinct)
	_ok("they collide with none of the original nine",
		not kinds.any(func(k): return k <= SimTypes.OrderKind.CANCEL))

	_ok("DeployState is the four-state machine",
		SimTypes.DeployState.MOBILE == 0
			and SimTypes.DeployState.DEPLOYING == 1
			and SimTypes.DeployState.DEPLOYED == 2
			and SimTypes.DeployState.UNDEPLOYING == 3)
	_ok("SortieState is the five-state machine",
		SimTypes.SortieState.GROUNDED == 0
			and SimTypes.SortieState.OUTBOUND == 1
			and SimTypes.SortieState.ON_STATION == 2
			and SimTypes.SortieState.RTB == 3
			and SimTypes.SortieState.RECOVERING == 4)
	_ok("both name their states",
		SimTypes.deploy_state_name(SimTypes.DeployState.DEPLOYED) == "DEPLOYED"
			and SimTypes.sortie_state_name(SimTypes.SortieState.RTB) == "RTB")


# ── 2. the queue builds the commands ─────────────────────────────────────────

func _suite_constructors() -> void:
	_suite("SimCommandQueue constructors mirror move()/attack_track()")

	var q := SimCommandQueue.new()
	var pts := PackedFloat32Array([100.0, 200.0, 300.0, 400.0])

	var c1 := q.patrol(1, 7, pts)
	_ok("patrol() builds PATROL with the point list",
		c1.kind == SimTypes.OrderKind.PATROL and c1.issuer == 1
			and c1.unit == 7 and c1.points.size() == 4)
	_ok("the first point is mirrored into x/z",
		c1.x == 100.0 and c1.z == 200.0)
	pts[0] = 999.0
	_ok("the point list is a private copy", c1.points[0] == 100.0)

	var c2 := q.load_cargo(1, 7, 9)
	_ok("load_cargo() names both units",
		c2.kind == SimTypes.OrderKind.LOAD and c2.unit == 7
			and c2.target_unit == 9)
	var c3 := q.unload_cargo(1, 9)
	_ok("unload_cargo() defaults to everything aboard",
		c3.kind == SimTypes.OrderKind.UNLOAD and c3.unit == 9
			and c3.target_unit == -1)
	var c4 := q.deploy(1, 7)
	_ok("deploy() is a bare toggle on one unit",
		c4.kind == SimTypes.OrderKind.DEPLOY and c4.unit == 7)
	var c5 := q.sortie_strike(1, 7, 1000.0, 2000.0)
	_ok("sortie_strike() carries the target point",
		c5.kind == SimTypes.OrderKind.SORTIE_STRIKE
			and c5.x == 1000.0 and c5.z == 2000.0)
	var c6 := q.sortie_patrol(1, 7, 1000.0, 2000.0, 5000.0)
	_ok("sortie_patrol() carries point and radius",
		c6.kind == SimTypes.OrderKind.SORTIE_PATROL and c6.radius_m == 5000.0)

	_ok("all six were submitted and counted", q.submitted == 6 and q.size() == 6)
	var drained := q.drain()
	var in_order := drained.size() == 6
	for k in range(drained.size()):
		if drained[k] != [c1, c2, c3, c4, c5, c6][k]:
			in_order = false
	_ok("drain() returns them in submission order", in_order)


# ── 3. ownership and honesty at the drain ────────────────────────────────────

func _suite_authorisation() -> void:
	_suite("The command slot validates the new kinds like the old ones")

	var w := SimWorld.new(2)
	var mine := _unit(w, "mine", 0, 0, 0.0, 0.0)
	var theirs := _unit(w, "theirs", 1, 1, 50.0, 0.0)
	var apc := _unit(w, "apc", 0, 0, 5.0, 0.0)
	w.entities.set_cargo_capacity(apc, 4)
	var pts := PackedFloat32Array([10.0, 10.0, 20.0, 20.0])

	w.commands.patrol(0, theirs, pts)
	w.run_ticks(1)
	_ok("PATROL on an enemy unit is rejected",
		w.commands.rejected == 1 and w.commands.executed == 0)

	w.commands.load_cargo(0, mine, theirs)
	w.run_ticks(1)
	_ok("LOAD into an ENEMY transport is rejected -- the second index is "
		+ "gated too", w.commands.rejected == 2 and w.commands.executed == 0)

	w.commands.load_cargo(0, mine, 9999)
	w.run_ticks(1)
	_ok("LOAD into a transport that does not exist is rejected",
		w.commands.rejected == 3)

	w.commands.load_cargo(1, theirs, apc)
	w.run_ticks(1)
	_ok("an enemy cannot board MY transport either", w.commands.rejected == 4)

	# Authorised but impossible: no system is installed yet. The honest answer
	# is rejection, counted, so the counters never claim the sim did something
	# it has no code for.
	w.commands.patrol(0, mine, pts)
	w.commands.load_cargo(0, mine, apc)
	w.commands.unload_cargo(0, apc)
	w.commands.deploy(0, mine)
	w.commands.sortie_strike(0, mine, 100.0, 100.0)
	w.commands.sortie_patrol(0, mine, 100.0, 100.0, 3000.0)
	w.run_ticks(1)
	_ok("with no systems installed, all six kinds are honestly REJECTED",
		w.commands.rejected == 10 and w.commands.executed == 0,
		"rejected %d executed %d" % [w.commands.rejected, w.commands.executed])
	var st := w.subsystem_status()
	_ok("and subsystem_status() reports all three systems absent",
		st["transport"] == false and st["patrol"] == false
			and st["sortie"] == false)


# ── 4. routing into installed systems ────────────────────────────────────────

func _suite_routing() -> void:
	_suite("Installed systems receive the orders, verbatim, and are stepped")

	var w := SimWorld.new(3)
	var a := _unit(w, "unit", 0, 0, 0.0, 0.0)
	var t := _unit(w, "transport", 0, 0, 10.0, 0.0)
	w.entities.set_cargo_capacity(t, 4)
	var stp := StubPatrol.new()
	var stt := StubTransport.new()
	var sts := StubSortie.new()
	w.patrol_system = stp
	w.transport_system = stt
	w.sortie_system = sts

	w.commands.patrol(0, a, PackedFloat32Array([1.0, 2.0, 3.0, 4.0]))
	w.commands.load_cargo(0, a, t)
	w.commands.unload_cargo(0, t)
	w.commands.deploy(0, a)
	w.commands.sortie_strike(0, a, 500.0, 600.0)
	w.commands.sortie_patrol(0, a, 700.0, 800.0, 2500.0)
	w.run_ticks(1)

	_ok("all six executed", w.commands.executed == 6 and w.commands.rejected == 0,
		"executed %d rejected %d" % [w.commands.executed, w.commands.rejected])
	_ok("PATROL reached the patrol system with its point list",
		stp.calls == [["patrol", a, 4]])
	_ok("LOAD, UNLOAD and DEPLOY reached the transport system, in order",
		stt.calls == [["load", a, t], ["unload", t, -1], ["deploy", a]])
	_ok("both sortie kinds reached the sortie system with their geometry",
		sts.calls == [["strike", a, 500.0, 600.0],
			["patrol", a, 700.0, 800.0, 2500.0]])

	w.run_ticks(3)
	_ok("the tick slots step every installed system every tick",
		stp.steps == 4 and stt.steps == 4 and sts.steps == 4,
		"steps %d/%d/%d" % [stp.steps, stt.steps, sts.steps])
	var st := w.subsystem_status()
	_ok("subsystem_status() now reports all three present",
		st["transport"] == true and st["patrol"] == true
			and st["sortie"] == true)


# ── 5. the cargo model ───────────────────────────────────────────────────────

func _suite_cargo_state() -> void:
	_suite("Cargo: aboard means alive, off the map, riding the hull")

	var w := SimWorld.new(4)
	var e := w.entities
	var t := _unit(w, "apc", 0, 0, 0.0, 0.0)
	e.set_cargo_capacity(t, 2)
	var a := _unit(w, "sq a", 0, 0, 2.0, 0.0, [_radar()])
	var b := _unit(w, "sq b", 0, 0, 4.0, 0.0)
	var c := _unit(w, "sq c", 0, 0, 6.0, 0.0)

	_ok("an emitting unit emits before boarding", e.is_emitting(a))
	_ok("board() takes the unit aboard",
		e.board(t, a) and e.is_aboard(a) and e.carried_by[a] == t
			and e.cargo_count(t) == 1)
	_ok("a unit cannot board twice", not e.board(t, a))
	_ok("a transport cannot board itself", not e.board(t, t))
	_ok("capacity is enforced at MAX %d" % e.cargo_capacity[t],
		e.board(t, b) and not e.board(t, c))
	_ok("a carrier cannot board its own cargo (no cycles)", not e.board(a, t))
	_ok("a unit with no cargo_capacity is not a transport",
		not e.board(c, b))

	_ok("carried: cannot move", not e.can_move(a))
	_ok("carried: cannot fire", not e.can_fire(a))
	_ok("carried: does not emit", not e.is_emitting(a))
	_ok("carried: a move order through the movement layer is refused",
		not w.movement.order_move(a, 500.0, 500.0))
	_ok("the manifest reads back in boarding order",
		e.cargo_of(t) == PackedInt32Array([a, b])
			and e.cargo_at(t, 0) == a and e.cargo_at(t, 1) == b
			and e.cargo_space(t) == 0)

	# The ride. The transport is given a velocity directly (it has no
	# destination, so the movement layer leaves it alone) and integrated.
	e.set_velocity(t, 5.0, 0.0, 0.0)
	w.run_ticks(10)   # 0.5 s at 20 Hz -> 2.5 m
	_ok("cargo position rides the transport",
		e.pos_x[t] > 2.0 and absf(e.pos_x[a] - e.pos_x[t]) < 0.001
			and absf(e.pos_z[a] - e.pos_z[t]) < 0.001,
		"hull at %.2f, cargo at %.2f" % [e.pos_x[t], e.pos_x[a]])

	e.set_velocity(t, 0.0, 0.0, 0.0)
	var door_x := e.pos_x[t] + 20.0
	_ok("disembark() refuses a unit that is not aboard",
		not e.disembark(t, c, door_x, 0.0))
	_ok("disembark() places the unit where the caller says",
		e.disembark(t, b, door_x, 0.0) and not e.is_aboard(b)
			and absf(e.pos_x[b] - door_x) < 0.001)
	_ok("and it is a unit again: moves, fires, holds one slot open",
		e.can_move(b) and e.can_fire(b) and e.cargo_space(t) == 1
			and e.cargo_of(t) == PackedInt32Array([a]))

	# Deploy gates movement exactly like being carried does.
	e.deploy_state[c] = SimTypes.DeployState.DEPLOYED
	_ok("a DEPLOYED unit cannot take a move order", not e.can_move(c))
	e.deploy_state[c] = SimTypes.DeployState.DEPLOYING
	_ok("nor can one mid-transition", not e.can_move(c))
	e.deploy_state[c] = SimTypes.DeployState.MOBILE
	_ok("MOBILE again, it moves again", e.can_move(c))

	_ok("home_base defaults to none", e.home_base_of(a) == -1)
	e.set_home_base(a, t)
	_ok("and stores what it is given", e.home_base_of(a) == t)


# ── 6. carried units and the picture ─────────────────────────────────────────

func _suite_carried_invisible() -> void:
	_suite("A carried unit is not sensed and does not sense (docs/02 boundary)")

	var w := SimWorld.new(5)
	var e := w.entities
	# Faction 0: a radar picket. Faction 1: a transport with a radar-equipped
	# passenger aboard BEFORE the first solve.
	_unit(w, "picket", 0, 0, 0.0, 0.0, [_radar()])
	var t := _unit(w, "truck", 1, 1, 5000.0, 0.0)
	e.set_cargo_capacity(t, 1)
	var pax := _unit(w, "pax radar", 1, 1, 5000.0, 0.0, [_radar()])
	e.board(t, pax)

	w.run_ticks(30)   # 1.5 s -> several sensor solves

	var table0: SimTrackTable = w.track_table_for(0)
	_ok("the picket tracks the TRANSPORT and nothing else",
		table0.track_ids().size() == 1,
		"%d track(s)" % table0.track_ids().size())
	var table1: SimTrackTable = w.track_table_for(1)
	_ok("the passenger's own radar, stowed, builds NO picture",
		table1.track_ids().size() == 0,
		"%d track(s)" % table1.track_ids().size())

	# Unload, and the passenger re-joins the world on both sides of the seam.
	e.disembark(t, pax, 5010.0, 0.0)
	w.run_ticks(30)
	_ok("once disembarked it is sensed again",
		w.track_table_for(0).track_ids().size() == 2,
		"%d track(s)" % w.track_table_for(0).track_ids().size())
	_ok("and senses again",
		w.track_table_for(1).track_ids().size() == 1,
		"%d track(s)" % w.track_table_for(1).track_ids().size())


# ── 7. the transport dies ────────────────────────────────────────────────────

func _suite_kill_cascade() -> void:
	_suite("If the transport dies, the cargo dies -- nested holds included")

	var w := SimWorld.new(6)
	var e := w.entities
	var amphib := _unit(w, "amphib", 0, 0, 0.0, 0.0)
	e.set_cargo_capacity(amphib, 2)
	var craft := _unit(w, "landing craft", 0, 0, 1.0, 0.0)
	e.set_cargo_capacity(craft, 2)
	var tank := _unit(w, "tank", 0, 0, 2.0, 0.0)
	var squad := _unit(w, "squad", 0, 0, 3.0, 0.0)

	_ok("nesting is legal: a loaded craft boards the amphib",
		e.board(craft, tank) and e.board(amphib, craft)
			and e.board(amphib, squad))
	_ok("top_carrier() resolves the hull actually on the map",
		e.top_carrier(tank) == amphib and e.top_carrier(squad) == amphib)

	# Nested ride: everything follows the one moving hull.
	e.set_velocity(amphib, 4.0, 0.0, 0.0)
	w.run_ticks(5)
	_ok("nested cargo rides the outermost hull",
		absf(e.pos_x[tank] - e.pos_x[amphib]) < 0.001
			and absf(e.pos_x[craft] - e.pos_x[amphib]) < 0.001)

	# A passenger dying alone leaves the manifest clean.
	e.kill(squad)
	_ok("a dead passenger leaves the manifest",
		e.cargo_count(amphib) == 1 and e.cargo_of(amphib)[0] == craft)

	# The hull dying takes the hold with it, recursively.
	e.kill(amphib)
	_ok("killing the amphib kills the craft AND the tank inside it",
		e.alive[amphib] == 0 and e.alive[craft] == 0 and e.alive[tank] == 0)
	_ok("the manifests are empty afterwards",
		e.cargo_count(amphib) == 0 and e.cargo_count(craft) == 0)


# ── 8. the hash sees the new state ───────────────────────────────────────────

func _hash_world() -> SimWorld:
	var w := SimWorld.new(7)
	var t := _unit(w, "apc", 0, 0, 10.0, 10.0)
	w.entities.set_cargo_capacity(t, 2)
	_unit(w, "inf", 0, 0, 12.0, 10.0)
	return w


func _suite_hash() -> void:
	_suite("state_hash() covers deploy, cargo, home_base and sortie state")

	var w1 := _hash_world()
	var w2 := _hash_world()
	_ok("two identically built worlds hash identically",
		w1.state_hash() == w2.state_hash())

	w2.entities.deploy_state[1] = SimTypes.DeployState.DEPLOYED
	_ok("a deploy_state difference is a desync", w1.state_hash() != w2.state_hash())
	w2.entities.deploy_state[1] = SimTypes.DeployState.MOBILE
	w2.entities.deploy_timer[1] = 3.0
	_ok("a deploy_timer difference is a desync", w1.state_hash() != w2.state_hash())
	w2.entities.deploy_timer[1] = 0.0
	w2.entities.sortie_state[1] = SimTypes.SortieState.RTB
	_ok("a sortie_state difference is a desync", w1.state_hash() != w2.state_hash())
	w2.entities.sortie_state[1] = SimTypes.SortieState.GROUNDED
	w2.entities.set_home_base(1, 0)
	_ok("a home_base difference is a desync", w1.state_hash() != w2.state_hash())
	w2.entities.set_home_base(1, -1)
	_ok("restored, they agree again", w1.state_hash() == w2.state_hash())
	w2.entities.board(0, 1)
	_ok("who is aboard what is a desync", w1.state_hash() != w2.state_hash())


# ── 9. determinism ───────────────────────────────────────────────────────────

func _det_run() -> int:
	var w := SimWorld.new(99)
	w.use_terrain(SimTerrain.new(64, 64, 200.0, "flat"))
	var e := w.entities
	var t := _unit(w, "lc", 0, 0, 100.0, 100.0)
	e.set_cargo_capacity(t, 2)
	var a := _unit(w, "tank", 0, 0, 105.0, 100.0)
	var b := _unit(w, "mover", 0, 0, 200.0, 200.0)
	e.board(t, a)
	e.set_velocity(t, 3.0, 0.0, 1.0)
	w.movement.order_move(b, 900.0, 900.0)
	w.run_ticks(60)
	return w.state_hash()


func _suite_determinism() -> void:
	_suite("Same seed, same ride, same hash (docs/06)")

	var h1 := _det_run()
	var h2 := _det_run()
	_ok("two runs with cargo aboard a moving hull hash identically",
		h1 == h2, "%d vs %d" % [h1, h2])
