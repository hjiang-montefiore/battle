extends SceneTree
## Tests for the movement subsystem: orders, the path solver, steering and
## arrival.
##
##     godot --path game --headless --script res://sim/tests/test_movement.gd
##
## Its own file on purpose. Four agents are building on one spine in parallel
## and a shared test runner is a shared merge conflict; each subsystem owns
## test_<name>.gd and nothing else.
##
## What is asserted here is behaviour, not implementation: that a unit gets
## where it was sent, that it does not drive through water, that it stops
## without oscillating, that two runs from one seed are bit-identical, and that
## the layer writes velocity rather than position.

var _passed := 0
var _failed := 0


func _init() -> void:
	print("")
	print("  BATTLE -- movement tests")
	print("  " + "-".repeat(66))

	_suite_orders()
	_suite_steering()
	_suite_ownership()
	_suite_pathfinding()
	_suite_terrain_speed()
	_suite_formations()
	_suite_determinism()
	_suite_command_path()
	_suite_budget()
	_suite_terrain_follow()
	_suite_honesty()

	print("  " + "-".repeat(66))
	if _failed == 0:
		print("  %d passed, 0 failed" % _passed)
	else:
		print("  %d passed, %d FAILED" % [_passed, _failed])
	print("")
	quit(1 if _failed > 0 else 0)


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


# ── fixtures ─────────────────────────────────────────────────────────────────

## Flat ground, 64 x 64 cells of 50 m -- 3.2 km square, which is unit scale
## rather than theatre scale and keeps the tests short.
func _flat_terrain() -> SimTerrain:
	var t := SimTerrain.new(64, 64, 50.0, "flat")
	t.fill(0.0)
	return t


func _world(seed_value: int, t: SimTerrain = null) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.use_accumulator = false
	if t != null:
		w.terrain = t
		w.solver.terrain = t
		w.movement.set_terrain(t)
	return w


## A tank-shaped mover: 30 m/s, 4 m/s^2, 1.2 rad/s.
func _add_vehicle(w: SimWorld, unit_name: String, faction: int,
		x: float, z: float, p_owner := -1) -> int:
	var i := w.entities.add(unit_name, faction, x, 0.0, z,
		SimSignature.new(12.0), [], SimTypes.Category.GROUND, 2.5,
		p_owner if p_owner >= 0 else faction)
	w.entities.set_mobility(i, 30.0, 4.0, 1.2)
	w.entities.set_damage_profile(i, SimTypes.DamageModel.ARMORED, 100.0,
		[500.0, 90.0, 45.0, 40.0, 20.0],
		[SimTypes.ArmorType.COMPOSITE, SimTypes.ArmorType.RHA,
		 SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA])
	return i


func _dist(e: SimEntities, i: int, x: float, z: float) -> float:
	var dx := e.pos_x[i] - x
	var dz := e.pos_z[i] - z
	return sqrt(dx * dx + dz * dz)


## Run until the unit arrives or the tick budget runs out. Returns ticks used.
func _run_until_arrival(w: SimWorld, unit: int, max_ticks: int) -> int:
	for n in range(max_ticks):
		w.run_ticks(1)
		if w.movement.has_arrived(unit):
			return n + 1
	return -1


# ── orders ───────────────────────────────────────────────────────────────────

func _suite_orders() -> void:
	_suite("Orders (one queue, one code path)")

	var w := _world(1, _flat_terrain())
	var e := w.entities
	var u := _add_vehicle(w, "tank", 0, 0.0, 0.0)

	_ok("a move order is accepted by a unit that can move",
		w.movement.order_move(u, 400.0, 0.0))
	_ok("and records the destination in the entity store",
		e.has_dest[u] == 1 and absf(e.dest_x[u] - 400.0) < 0.01)
	_ok("one outstanding order", w.movement.order_count(u) == 1)

	# Queued orders stack; an unqueued one replaces the lot.
	w.movement.order_move(u, 400.0, 400.0, true)
	w.movement.order_move(u, 0.0, 400.0, true)
	_ok("shift-queued orders stack up", w.movement.order_count(u) == 3)
	w.movement.order_move(u, 100.0, 0.0)
	_ok("an unqueued order replaces the queue", w.movement.order_count(u) == 1,
		"destination now %.0f, %.0f" % [e.dest_x[u], e.dest_z[u]])

	# ... and they execute in the order given.
	var w2 := _world(2, _flat_terrain())
	var u2 := _add_vehicle(w2, "tank", 0, 0.0, 0.0)
	w2.movement.order_move(u2, 200.0, 0.0)
	w2.movement.order_move(u2, 200.0, 200.0, true)
	var seen_first := false
	var reached_second := false
	for _t in range(3000):
		w2.run_ticks(1)
		if not seen_first and _dist(w2.entities, u2, 200.0, 0.0) < 12.0:
			seen_first = true
		if seen_first and _dist(w2.entities, u2, 200.0, 200.0) < 8.0:
			reached_second = true
			break
	_ok("a queue of two moves is executed in order and both are reached",
		seen_first and reached_second)
	var settle := _run_until_arrival(w2, u2, 200)
	_ok("and the queue is empty afterwards",
		w2.movement.order_count(u2) == 0 and settle > 0)

	# STOP and HOLD.
	var w3 := _world(3, _flat_terrain())
	var u3 := _add_vehicle(w3, "tank", 0, 0.0, 0.0)
	w3.movement.order_move(u3, 900.0, 0.0)
	w3.run_ticks(40)
	var moved := w3.entities.pos_x[u3]
	w3.movement.order_stop(u3)
	w3.run_ticks(40)
	_ok("stop halts the unit dead",
		w3.entities.speed_ms[u3] == 0.0 and absf(w3.entities.pos_x[u3] - moved) < 0.01,
		"stopped at %.1f m" % moved)
	_ok("and clears the order queue",
		w3.movement.order_count(u3) == 0 and w3.entities.has_dest[u3] == 0)
	w3.movement.order_hold(u3)
	_ok("hold is a distinct state from stop", w3.movement.is_holding(u3))
	w3.movement.order_move(u3, 400.0, 0.0)
	_ok("and a new move order releases it", not w3.movement.is_holding(u3))

	# Attack-move: the movement half is real, and it says so.
	var w4 := _world(4, _flat_terrain())
	var u4 := _add_vehicle(w4, "tank", 0, 0.0, 0.0)
	w4.movement.order_attack_move(u4, 600.0, 0.0)
	w4.run_ticks(10)
	_ok("an attack-move advances at combat power",
		w4.entities.move_state[u4] == SimTypes.MoveState.COMBAT
			and w4.movement.is_attack_moving(u4))
	_ok("and burns combat fuel rather than cruise fuel",
		w4.entities.burn_rate_lpm(u4) == w4.entities.burn_combat_lpm[u4])

	# Gating: a unit that cannot move refuses the order, through can_move().
	var w5 := _world(5, _flat_terrain())
	var u5 := _add_vehicle(w5, "tank", 0, 0.0, 0.0)
	w5.entities.lose_component(u5, SimTypes.Component.MOBILITY)
	_ok("a mobility-killed unit refuses a move order",
		not w5.movement.order_move(u5, 300.0, 0.0))
	var u6 := _add_vehicle(w5, "dry", 0, 100.0, 0.0)
	w5.entities.set_economy_profile(u6, 100.0, 1.0, 500.0, 1.0, 5.0, 12.0)
	w5.entities.fuel[u6] = 0.0
	_ok("and so does one that is out of fuel",
		not w5.movement.order_move(u6, 300.0, 0.0))
	var stat := w5.entities.add("bunker", 0, 0.0, 200.0, 0.0, SimSignature.new(80.0))
	w5.entities.is_structure[stat] = 1
	_ok("a structure cannot be ordered anywhere",
		not w5.movement.order_move(stat, 300.0, 0.0))


# ── steering ─────────────────────────────────────────────────────────────────

func _suite_steering() -> void:
	_suite("Steering and arrival")

	var w := _world(11, _flat_terrain())
	var e := w.entities
	var u := _add_vehicle(w, "tank", 0, 0.0, 0.0)
	w.movement.order_move(u, 0.0, 900.0)

	# It accelerates rather than teleporting to top speed.
	w.run_ticks(1)
	var v1 := e.speed_ms[u]
	_ok("a unit accelerates from rest at its quoted rate",
		v1 > 0.0 and v1 <= e.accel_ms2[u] / SimWorld.SIM_HZ + 0.001,
		"%.3f m/s after one tick" % v1)
	# 30 m/s at 4 m/s^2 is 7.5 seconds -- 150 ticks. Asserting the time as well
	# as the value is what makes this a test of the acceleration model rather
	# than of the top speed constant.
	w.run_ticks(160)
	_ok("and reaches top speed on open ground",
		absf(e.speed_ms[u] - e.max_speed_ms[u]) < 0.5,
		"%.1f of %.1f m/s after 8 s" % [e.speed_ms[u], e.max_speed_ms[u]])

	var ticks := _run_until_arrival(w, u, 3000)
	_ok("it arrives", ticks > 0, "%d ticks" % ticks)
	_ok("within the arrival radius", _dist(e, u, 0.0, 900.0) <= w.movement.arrive_radius_m,
		"%.2f m from the point" % _dist(e, u, 0.0, 900.0))
	_ok("and stops, rather than orbiting the point",
		e.speed_ms[u] == 0.0 and e.vel_x[u] == 0.0 and e.vel_z[u] == 0.0)

	# The classic oscillation bug: keep running and check it stays put.
	var sx := e.pos_x[u]
	var sz := e.pos_z[u]
	w.run_ticks(200)
	_ok("and stays stopped 10 seconds later",
		absf(e.pos_x[u] - sx) < 0.001 and absf(e.pos_z[u] - sz) < 0.001)
	_ok("its move state falls back to IDLE",
		e.move_state[u] == SimTypes.MoveState.IDLE)

	# Turn rate is finite: a unit ordered to reverse its course turns, it does
	# not snap. 180 degrees at 1.2 rad/s is 2.6 s -- 52 ticks.
	var w2 := _world(12, _flat_terrain())
	var e2 := w2.entities
	var u2 := _add_vehicle(w2, "tank", 0, 0.0, 0.0)
	e2.heading_rad[u2] = 0.0
	w2.movement.order_move(u2, 0.0, -800.0)
	var worst := 0.0
	var prev := e2.heading_rad[u2]
	for _t in range(80):
		w2.run_ticks(1)
		var d: float = absf(wrapf(e2.heading_rad[u2] - prev, -PI, PI))
		worst = maxf(worst, d)
		prev = e2.heading_rad[u2]
	var per_tick := 1.2 / SimWorld.SIM_HZ
	_ok("heading never changes faster than turn_rate_rads",
		worst <= per_tick + 1e-5,
		"worst %.4f rad/tick, limit %.4f" % [worst, per_tick])
	_ok("and the turn actually completes",
		absf(wrapf(e2.heading_rad[u2] - PI, -PI, PI)) < 0.05,
		"heading %.3f rad" % e2.heading_rad[u2])

	# Velocity and heading agree: a unit does not crab sideways.
	var w3 := _world(13, _flat_terrain())
	var e3 := w3.entities
	var u3 := _add_vehicle(w3, "tank", 0, 0.0, 0.0)
	w3.movement.order_move(u3, 500.0, 500.0)
	w3.run_ticks(120)
	var vh := atan2(e3.vel_x[u3], e3.vel_z[u3])
	_ok("velocity points where the hull is pointing",
		absf(wrapf(vh - e3.heading_rad[u3], -PI, PI)) < 0.02)


# ── ownership of state ───────────────────────────────────────────────────────

func _suite_ownership() -> void:
	_suite("Mutation ownership (sim_entities.gd's table)")

	# The rule that makes the tick order mean anything: movement writes
	# velocity, _integrate() writes position. Stepping movement alone must not
	# move anything.
	var w := _world(21, _flat_terrain())
	var e := w.entities
	var u := _add_vehicle(w, "tank", 0, 0.0, 0.0)
	w.movement.order_move(u, 700.0, 0.0)
	w.run_ticks(30)
	var px := e.pos_x[u]
	var pz := e.pos_z[u]
	w.movement.step(1.0 / SimWorld.SIM_HZ)
	_ok("SimMovement.step() never writes a position",
		e.pos_x[u] == px and e.pos_z[u] == pz)
	_ok("but it does write a velocity", e.vel_x[u] != 0.0)

	# A unit with no mobility profile is not movement's business at all --
	# the sensing tests hand aircraft a velocity directly and never an order.
	var flyer := e.add("bogey", 1, 1000.0, 8000.0, 0.0, SimSignature.new(4.0),
		[], SimTypes.Category.AIR)
	e.set_velocity(flyer, -200.0, 0.0, 0.0)
	w.run_ticks(5)
	_ok("a unit with no mobility keeps the velocity somebody else gave it",
		e.vel_x[flyer] == -200.0)

	# Losing mobility mid-move stops the unit but keeps the order, so refuelling
	# or repair can resume it rather than silently forgetting where it was sent.
	var w2 := _world(22, _flat_terrain())
	var e2 := w2.entities
	var u2 := _add_vehicle(w2, "tank", 0, 0.0, 0.0)
	w2.movement.order_move(u2, 900.0, 0.0)
	w2.run_ticks(30)
	e2.lose_component(u2, SimTypes.Component.MOBILITY)
	w2.run_ticks(20)
	_ok("a mobility kill stops a moving unit dead",
		e2.speed_ms[u2] == 0.0 and e2.vel_x[u2] == 0.0)
	_ok("and its destination survives for a later repair",
		e2.has_dest[u2] == 1)


# ── the path solver ──────────────────────────────────────────────────────────

func _suite_pathfinding() -> void:
	_suite("Path solver (grid A* over the docs/02 heightfield)")

	# Open ground: the straight line IS the route. No cell staircase.
	var w := _world(31, _flat_terrain())
	var u := _add_vehicle(w, "tank", 0, -1000.0, 0.0)
	var direct := w.movement.plan_path(u, 1000.0, 0.0)
	_ok("open ground plans a single straight leg", direct.size() == 2,
		"%d waypoints" % (direct.size() / 2))

	# A lake across the route. The unit must go round it and every waypoint
	# must be on land -- this is the same heightfield docs/02 masks radar with.
	var lake := _flat_terrain()
	lake.carve_sea(-300.0, -500.0, 300.0, 500.0, 40.0)
	var w2 := _world(32, lake)
	var e2 := w2.entities
	var u2 := _add_vehicle(w2, "tank", 0, -1200.0, 0.0)
	var route := w2.movement.plan_path(u2, 1200.0, 0.0)
	_ok("a route across water is not a straight line", route.size() > 2,
		"%d waypoints" % (route.size() / 2))
	var all_dry := true
	for k in range(route.size() / 2):
		if lake.is_water(route[k * 2], route[k * 2 + 1]):
			all_dry = false
	_ok("and no waypoint of it is in the water", all_dry)

	# ... and no LEG of it crosses water either. Checked at CELL resolution,
	# which is the standard the sim itself uses: the heightfield is the terrain,
	# and height_at()'s bilinear filter bleeds a metre of interpolated "water" up
	# to half a cell inland of the last wet cell. A route that grazes that
	# interpolated shoreline is dry ground; a route that enters a wet CELL is not.
	var legs_dry := true
	var ax := e2.pos_x[u2]
	var az := e2.pos_z[u2]
	for k in range(route.size() / 2):
		var bx := route[k * 2]
		var bz := route[k * 2 + 1]
		for s in range(0, 601):
			var t := float(s) / 600.0
			var c := lake._to_cell(ax + (bx - ax) * t, az + (bz - az) * t)
			if lake.height_at_cell(c.x, c.y) < 0.0:
				legs_dry = false
		ax = bx
		az = bz
	_ok("nor does any LEG of it cross water", legs_dry)

	w2.movement.order_move(u2, 1200.0, 0.0)
	var ticks := -1
	var got_wet := false
	for n in range(4000):
		w2.run_ticks(1)
		var c := lake._to_cell(e2.pos_x[u2], e2.pos_z[u2])
		if lake.height_at_cell(c.x, c.y) < 0.0:
			got_wet = true
		if w2.movement.has_arrived(u2):
			ticks = n + 1
			break
	_ok("and the unit drives the route to the far shore", ticks > 0,
		"%d ticks" % ticks)
	_ok("without at any point driving into the lake", not got_wet)
	_ok("arriving on the far side of the lake",
		e2.pos_x[u2] > 1100.0 and _dist(e2, u2, 1200.0, 0.0) <= 6.0)

	# Genuinely unreachable: an island destination for a ground unit.
	var sea := SimTerrain.new(64, 64, 50.0, "sea")
	sea.fill(0.0)
	sea.carve_sea(-1600.0, -400.0, 1600.0, 400.0, 60.0)   # a strait, wall to wall
	var w3 := _world(33, sea)
	var u3 := _add_vehicle(w3, "tank", 0, 0.0, -900.0)
	var none := w3.movement.plan_path(u3, 0.0, 900.0)
	_ok("a destination on the far side of open water has no ground route",
		none.is_empty())
	w3.movement.order_move(u3, 0.0, 900.0)
	w3.run_ticks(200)
	_ok("the order is abandoned rather than ground against forever",
		w3.entities.has_dest[u3] == 0 and w3.movement.orders_abandoned >= 1)
	_ok("and the unit never entered the water",
		not sea.is_water(w3.entities.pos_x[u3], w3.entities.pos_z[u3]))

	# A destination inside the water is relocated to the nearest legal ground
	# rather than refused outright -- clicking the shoreline should work.
	var w4 := _world(34, lake)
	var u4 := _add_vehicle(w4, "tank", 0, -1200.0, 0.0)
	var shore := w4.movement.plan_path(u4, 0.0, 0.0)   # dead centre of the lake
	_ok("a click in the water plans to the nearest dry ground", not shore.is_empty())
	var last_dry := true
	if not shore.is_empty():
		var c := lake._to_cell(shore[shore.size() - 2], shore[shore.size() - 1])
		last_dry = lake.height_at_cell(c.x, c.y) >= 0.0
	_ok("and that ground is dry", last_dry)
	_ok("and the order is amended to it, so the unit can actually arrive",
		w4.movement.last_goal_relocated)
	w4.movement.order_move(u4, 0.0, 0.0)
	var wet_ticks := _run_until_arrival(w4, u4, 4000)
	_ok("a unit sent into the lake stops at the water's edge and reports arrival",
		wet_ticks > 0, "%d ticks" % wet_ticks)
	var cend := lake._to_cell(w4.entities.pos_x[u4], w4.entities.pos_z[u4])
	_ok("standing on dry land", lake.height_at_cell(cend.x, cend.y) >= 0.0)

	# A ship is the mirror image: water is passable, land is not.
	var boat := w4.entities.add("boat", 0, -1200.0, 0.0, 0.0,
		SimSignature.new(300.0), [], SimTypes.Category.SURFACE)
	w4.entities.set_mobility(boat, 12.0, 1.0, 0.3)
	_ok("a ship cannot stand on dry land",
		not w4.movement.is_passable(boat, -1200.0, 0.0))
	_ok("but the lake is passable to it",
		w4.movement.is_passable(boat, 0.0, 0.0))
	_ok("and the tank is the other way round",
		w4.movement.is_passable(u4, -1200.0, 0.0)
			and not w4.movement.is_passable(u4, 0.0, 0.0))

	# A cliff is impassable to a tank on grade alone, with no water involved.
	var cliff := SimTerrain.new(64, 64, 50.0, "cliff")
	cliff.fill(0.0)
	cliff.add_ridge(0.0, -1600.0, 0.0, 1600.0, 2000.0, 300.0)
	var w5 := _world(35, cliff)
	var u5 := _add_vehicle(w5, "tank", 0, -800.0, 0.0)
	# The CREST of a ridge is flat; it is the FLANK that stops a tank, which is
	# why this samples 150 m off the centreline and not on it.
	_ok("the flank of a 2000 m ridge is impassable on gradient alone",
		not w5.movement.is_passable(u5, -150.0, 0.0),
		"grade %.2f" % w5.movement.grade_at(-150.0, 0.0))
	_ok("and the flat ground beside it is not",
		w5.movement.is_passable(u5, -800.0, 0.0))
	_ok("so there is no route over it for a tracked vehicle",
		w5.movement.plan_path(u5, 800.0, 0.0).is_empty())

	# Aircraft ignore the ground entirely.
	var flyer := w5.entities.add("jet", 0, -800.0, 9000.0, 0.0,
		SimSignature.new(4.0), [], SimTypes.Category.AIR)
	w5.entities.set_mobility(flyer, 250.0, 8.0, 0.15)
	_ok("an aircraft flies over the ridge without planning round it",
		w5.movement.plan_path(flyer, 800.0, 0.0).size() == 2)


# ── terrain and speed ────────────────────────────────────────────────────────

func _suite_terrain_speed() -> void:
	_suite("Terrain affects speed (docs/02's heightfield, reused)")

	var flat := _flat_terrain()
	var hilly := _flat_terrain()
	# A rolling ridge: passable, but slow going.
	hilly.add_ridge(-1600.0, 0.0, 1600.0, 0.0, 260.0, 900.0)

	var wf := _world(41, flat)
	var wh := _world(41, hilly)
	var uf := _add_vehicle(wf, "tank", 0, 0.0, -900.0)
	var uh := _add_vehicle(wh, "tank", 0, 0.0, -900.0)

	_ok("flat ground costs nothing", wf.movement.speed_multiplier(uf, 0.0, 0.0) == 1.0)
	var slope_mult := wh.movement.speed_multiplier(uh, 0.0, -450.0)
	_ok("a slope costs speed", slope_mult < 1.0 and slope_mult > 0.0,
		"%.2f of top speed at grade %.2f" % [slope_mult, wh.movement.grade_at(0.0, -450.0)])

	wf.movement.order_move(uf, 0.0, 900.0)
	wh.movement.order_move(uh, 0.0, 900.0)
	var tf := _run_until_arrival(wf, uf, 4000)
	var th := _run_until_arrival(wh, uh, 4000)
	_ok("both units complete the same 1.8 km", tf > 0 and th > 0)
	_ok("but crossing a ridge takes longer than crossing a plain", th > tf,
		"%d ticks over the ridge vs %d on the flat" % [th, tf])

	# Slope is read from the same array the sensor solver masks with. If those
	# two ever disagreed, the ridge you cannot see over would not be the ridge
	# you cannot drive over.
	_ok("mobility and masking read one terrain, not two",
		wh.movement.terrain == wh.solver.terrain)


# ── formations ───────────────────────────────────────────────────────────────

func _suite_formations() -> void:
	_suite("Formation moves (proving_ground.gd's grid, moved into the sim)")

	var w := _world(51, _flat_terrain())
	var units := PackedInt32Array()
	for k in range(9):
		units.append(_add_vehicle(w, "tank%d" % k, 0, -600.0 + float(k) * 30.0, -600.0))

	var slots := w.movement.formation_slots(units, 400.0, 400.0, 20.0)
	_ok("one slot per unit, in the order given", slots.size() == units.size() * 2)

	var distinct := true
	for a in range(9):
		for b in range(a + 1, 9):
			if absf(slots[a * 2] - slots[b * 2]) < 0.01 \
					and absf(slots[a * 2 + 1] - slots[b * 2 + 1]) < 0.01:
				distinct = false
	_ok("no two units are sent to the same point", distinct)

	var cx := 0.0
	var cz := 0.0
	for k in range(9):
		cx += slots[k * 2]
		cz += slots[k * 2 + 1]
	cx /= 9.0
	cz /= 9.0
	_ok("the formation is centred on the point that was clicked",
		absf(cx - 400.0) < 0.51 and absf(cz - 400.0) < 0.51,
		"centre of mass %.2f, %.2f" % [cx, cz])

	# And it is the same every time.
	var again := w.movement.formation_slots(units, 400.0, 400.0, 20.0)
	_ok("formation slots are deterministic", again == slots)

	# End to end: nine units ordered to one point do not end up in one place.
	w.movement.order_move_group(units, 400.0, 400.0, 20.0)
	w.run_ticks(1600)
	var piled := 0
	var arrived := 0
	for a in range(9):
		if w.movement.has_arrived(units[a]):
			arrived += 1
		for b in range(a + 1, 9):
			var dx := w.entities.pos_x[units[a]] - w.entities.pos_x[units[b]]
			var dz := w.entities.pos_z[units[a]] - w.entities.pos_z[units[b]]
			if sqrt(dx * dx + dz * dz) < 6.0:
				piled += 1
	_ok("a nine-unit group move ends with nine units arrived", arrived == 9,
		"%d of 9" % arrived)
	_ok("and none of them stacked on top of another", piled == 0,
		"%d overlapping pairs" % piled)

	# Slots that land in water are moved to ground the unit can occupy.
	var lake := _flat_terrain()
	lake.carve_sea(-200.0, -200.0, 200.0, 200.0, 30.0)
	var w2 := _world(52, lake)
	var group := PackedInt32Array()
	for k in range(4):
		group.append(_add_vehicle(w2, "t%d" % k, 0, -900.0 + float(k) * 30.0, -900.0))
	var wet := w2.movement.formation_slots(group, 0.0, 0.0, 60.0)
	var any_wet := false
	for k in range(4):
		var c := lake._to_cell(wet[k * 2], wet[k * 2 + 1])
		if lake.height_at_cell(c.x, c.y) < 0.0:
			any_wet = true
	_ok("no formation slot is placed in water", not any_wet)
	var all_reachable := true
	for k in range(4):
		if not w2.movement.is_passable(group[k], wet[k * 2], wet[k * 2 + 1]):
			all_reachable = false
	_ok("and every slot is somewhere the unit could actually stand", all_reachable)


# ── determinism ──────────────────────────────────────────────────────────────

func _suite_determinism() -> void:
	_suite("Determinism (docs/06)")

	# Same seed, same orders, same terrain -> bit-identical world.
	var h1 := _movement_scenario(4242)
	var h2 := _movement_scenario(4242)
	_ok("two runs from one seed produce the same state hash", h1 == h2,
		"%d vs %d" % [h1, h2])
	# NOT asserted: that a different seed gives a different world. It does not,
	# and that is deliberate -- movement draws from its RNG stream ZERO times.
	# Steering and A* are pure functions of last tick's state, so the only thing
	# that changes the outcome is a different ORDER.
	var h3 := _movement_scenario_alt(4242)
	_ok("a different order is a different world", h3 != h1)
	_ok("but a different seed alone is not: movement rolls no dice",
		_movement_scenario(9991) == h1)

	# The A* itself, twice over, on two independently built terrains: the
	# tie-break must be the cell index rule and never hash order.
	var pa := _plan_in_maze(7)
	var pb := _plan_in_maze(7)
	_ok("the path solver returns an identical route on an identical problem",
		pa == pb, "%d waypoints" % (pa.size() / 2))
	_ok("and that route is not trivial", pa.size() > 2)

	# The same problem posed from a differently-seeded world is still the same
	# route: nothing in the planner may depend on the RNG stream at all.
	var pc := _plan_in_maze(999)
	_ok("planning does not depend on the RNG stream", pc == pa)

	# Positions, not just the hash: replay the whole thing and compare tracks.
	var t1 := _movement_trace(88)
	var t2 := _movement_trace(88)
	_ok("every logged position matches, tick for tick", t1 == t2,
		"%d samples" % t1.size())


func _movement_scenario(seed_value: int) -> int:
	var t := _flat_terrain()
	t.carve_sea(-300.0, -500.0, 300.0, 500.0, 40.0)
	var w := _world(seed_value, t)
	var a := _add_vehicle(w, "a", 0, -1200.0, -200.0, 0)
	var b := _add_vehicle(w, "b", 1, 1200.0, 200.0, 1)
	var c := _add_vehicle(w, "c", 0, -1200.0, 300.0, 0)
	w.commands.move(0, a, 1200.0, 0.0)
	w.commands.move(1, b, -1200.0, 0.0)
	w.commands.move(0, c, 900.0, -700.0)
	w.run_ticks(900)
	return w.state_hash()


## The same scenario with one order changed.
func _movement_scenario_alt(seed_value: int) -> int:
	var t := _flat_terrain()
	t.carve_sea(-300.0, -500.0, 300.0, 500.0, 40.0)
	var w := _world(seed_value, t)
	var a := _add_vehicle(w, "a", 0, -1200.0, -200.0, 0)
	var b := _add_vehicle(w, "b", 1, 1200.0, 200.0, 1)
	var c := _add_vehicle(w, "c", 0, -1200.0, 300.0, 0)
	w.commands.move(0, a, 1200.0, 0.0)
	w.commands.move(1, b, -1200.0, 0.0)
	w.commands.move(0, c, 900.0, -690.0)      # ten metres to the north
	w.run_ticks(900)
	return w.state_hash()


func _movement_trace(seed_value: int) -> PackedFloat64Array:
	var t := _flat_terrain()
	t.add_ridge(-1600.0, 0.0, 1600.0, 0.0, 300.0, 700.0)
	var w := _world(seed_value, t)
	var u := _add_vehicle(w, "tank", 0, 0.0, -1200.0)
	w.movement.order_move(u, 200.0, 1200.0)
	var out := PackedFloat64Array()
	for _t in range(400):
		w.run_ticks(1)
		out.append(w.entities.pos_x[u])
		out.append(w.entities.pos_z[u])
		out.append(w.entities.heading_rad[u])
		out.append(w.entities.speed_ms[u])
	return out


func _plan_in_maze(seed_value: int) -> PackedFloat32Array:
	var t := SimTerrain.new(64, 64, 50.0, "maze")
	t.fill(0.0)
	# Two walls with a gap: the route has to find the gap, and there are two
	# symmetric ways round the second wall, which is exactly the tie the
	# determinism rule has to break the same way every time.
	t.carve_sea(-400.0, -1400.0, -400.0 + 100.0, 400.0, 40.0)
	t.carve_sea(400.0, -400.0, 400.0 + 100.0, 1400.0, 40.0)
	var w := _world(seed_value, t)
	var u := _add_vehicle(w, "tank", 0, -1200.0, 0.0)
	return w.movement.plan_path(u, 1200.0, 0.0)


# ── the command boundary ─────────────────────────────────────────────────────

func _suite_command_path() -> void:
	_suite("One code path: the player and the AI issue the same order")

	var w := _world(61, _flat_terrain())
	var e := w.entities
	var mine := _add_vehicle(w, "mine", 0, 0.0, 0.0, 0)
	var theirs := _add_vehicle(w, "theirs", 1, 300.0, 0.0, 1)

	w.commands.move(0, mine, 600.0, 0.0)
	w.run_ticks(60)
	# Three seconds at 4 m/s^2 from rest is 18 m. Asserting the number rather
	# than "it moved" is what makes this a test of the command path AND of the
	# acceleration reaching it intact.
	_ok("a MOVE command through the queue actually moves the unit",
		absf(e.pos_x[mine] - 18.0) < 1.5, "%.1f m travelled in 3 s" % e.pos_x[mine])

	# Ownership is validated in the spine, not trusted; movement must not
	# provide a way round it.
	var before := e.pos_x[theirs]
	w.commands.move(0, theirs, -600.0, 0.0)
	w.run_ticks(60)
	_ok("and player 0 cannot move player 1's unit",
		absf(e.pos_x[theirs] - before) < 0.001 and e.has_dest[theirs] == 0)

	# The AI reaches exactly the same function through its view.
	var view := w.ai_view_for(1, 1, SimPlayerSetup.new())
	view.order_move(theirs, 500.0, 200.0)
	w.run_ticks(60)
	_ok("the AI's order_move() lands in the same movement layer",
		e.has_dest[theirs] == 1 and e.speed_ms[theirs] > 0.0)
	_ok("and the AI cannot order a unit it does not own",
		not view.forces.owns(mine))

	# A STOP through the queue.
	w.commands.stop(0, mine)
	w.run_ticks(2)
	_ok("a STOP command through the queue halts the unit",
		e.speed_ms[mine] == 0.0 and e.has_dest[mine] == 0)

	# ATTACK_MOVE through the queue: the same path the A-then-click gesture
	# takes, landing in order_attack_move() with the flag and burn rate set.
	w.commands.attack_move(0, mine, 900.0, 0.0)
	w.run_ticks(10)
	_ok("an ATTACK_MOVE command through the queue advances at combat power",
		w.movement.is_attack_moving(mine)
			and e.move_state[mine] == SimTypes.MoveState.COMBAT)


# ── work budgeting and terrain following ─────────────────────────────────────

func _suite_budget() -> void:
	_suite("Bounded work per tick")

	# The pool bounds the WORK, not just the number of plans. Eight
	# cross-theatre searches on one tick is eight times the worst case, and a
	# frame does not care how many plans it was.
	var maze := SimTerrain.new(96, 96, 50.0, "maze")
	maze.fill(0.0)
	for k in range(5):
		var x := -1600.0 + float(k) * 700.0
		var z0 := -2300.0 if k % 2 == 0 else -900.0
		maze.carve_sea(x, z0, x + 80.0, z0 + 3200.0, 40.0)
	var w := _world(81, maze)
	var group := PackedInt32Array()
	for k in range(40):
		var u := _add_vehicle(w, "t%d" % k, 0, -2300.0, -800.0 + float(k) * 40.0)
		w.entities.set_mobility(u, 60.0, 6.0, 1.2)   # keep the test short
		group.append(u)
	for u in group:
		w.movement.order_move(u, 2300.0, 0.0)
	var worst := 0
	for _t in range(60):
		var before := w.movement.plans_run
		w.run_ticks(1)
		worst = maxi(worst, w.movement.plans_run - before)
	_ok("no tick ever runs more plans than the replan budget",
		worst <= w.movement.replan_budget_per_tick, "worst tick ran %d" % worst)
	_ok("and the expansion pool is never set below the per-plan cap, "
		+ "or unreachable would be indistinguishable from slow",
		w.movement.expansion_budget_per_tick >= w.movement.max_search_cells)

	# Forty units through a slalom, all ordered to the SAME point rather than to
	# a formation. That is deliberate: only one of them can stand on it, and a
	# unit that circles its objective forever because its own side is in the way
	# is the most recognisable pathfinding failure in the genre.
	var arrived := 0
	for _t in range(6000):
		w.run_ticks(1)
		arrived = 0
		for u in group:
			if w.movement.has_arrived(u):
				arrived += 1
		if arrived == 40:
			break
	_ok("forty units cross a five-wall slalom and all report arrival",
		arrived == 40, "%d of 40" % arrived)
	_ok("no order was abandoned as unreachable along the way",
		w.movement.orders_abandoned == 0)
	_ok("and running out of tick was never mistaken for running out of route",
		w.movement.plans_failed == 0,
		"%d deferred, %d failed" % [w.movement.plans_deferred, w.movement.plans_failed])
	var spread := 0.0
	for u in group:
		spread = maxf(spread, _dist(w.entities, u, 2300.0, 0.0))
	_ok("they stack up around the objective rather than on it",
		spread > 6.0 and spread < 120.0, "furthest %.0f m from the point" % spread)
	_ok("and none of them ended up in the water",
		_none_in_water(w, group, maze))


func _none_in_water(w: SimWorld, units: PackedInt32Array, t: SimTerrain) -> bool:
	for u in units:
		var c := t._to_cell(w.entities.pos_x[u], w.entities.pos_z[u])
		if t.height_at_cell(c.x, c.y) < 0.0:
			return false
	return true


func _suite_terrain_follow() -> void:
	_suite("Ground units stay on the ground")

	var hills := _flat_terrain()
	hills.add_ridge(-1600.0, 0.0, 1600.0, 0.0, 240.0, 800.0)
	var w := _world(91, hills)
	var e := w.entities
	var u := _add_vehicle(w, "tank", 0, 0.0, -1200.0)
	w.movement.order_move(u, 0.0, 1200.0)
	w.run_ticks(600)
	var ground := hills.ground_under(e.pos_x[u], e.pos_z[u])
	_ok("a moving vehicle rides the terrain it is crossing",
		absf(e.pos_y[u] - ground) < 1.0,
		"y %.1f, ground %.1f" % [e.pos_y[u], ground])
	_ok("and it climbed, rather than starting there", e.pos_y[u] > 5.0)

	# It is done by writing VELOCITY. Position is _integrate()'s alone.
	var before := e.pos_y[u]
	w.movement.step(1.0 / SimWorld.SIM_HZ)
	_ok("the climb is a vertical velocity, never a position write",
		e.pos_y[u] == before and e.vel_y[u] != 0.0)

	# An aircraft is left alone: its altitude is not movement's business.
	var jet := e.add("jet", 0, 0.0, 9000.0, 0.0, SimSignature.new(4.0), [],
		SimTypes.Category.AIR)
	e.set_mobility(jet, 250.0, 8.0, 0.2)
	e.vel_y[jet] = 3.0
	w.movement.order_move(jet, 1200.0, 0.0)
	w.run_ticks(10)
	_ok("an aircraft keeps its own vertical velocity", e.vel_y[jet] == 3.0)


# ── honesty ──────────────────────────────────────────────────────────────────

func _suite_honesty() -> void:
	_suite("The layer reports what it is")

	var w := _world(71, _flat_terrain())
	_ok("movement declares itself implemented", w.movement.is_implemented())
	_ok("and the world agrees", w.subsystem_status()["movement"] == true)

	# Budgeting is real, not a comment: fifty units ordered at once must not all
	# plan on the same tick.
	var w2 := _world(72, _flat_terrain())
	var lake := _flat_terrain()
	lake.carve_sea(-300.0, -500.0, 300.0, 500.0, 40.0)
	w2.terrain = lake
	w2.movement.set_terrain(lake)
	var many := PackedInt32Array()
	for k in range(50):
		many.append(_add_vehicle(w2, "t%d" % k, 0, -1400.0, -600.0 + float(k) * 24.0))
	for u in many:
		w2.movement.order_move(u, 1400.0, 0.0)
	var before_plans := w2.movement.plans_run
	w2.run_ticks(1)
	_ok("planning is budgeted across ticks, not done all at once",
		w2.movement.plans_run - before_plans <= w2.movement.replan_budget_per_tick,
		"%d plans on the first tick, budget %d" % [
			w2.movement.plans_run - before_plans, w2.movement.replan_budget_per_tick])
	_ok("and the overflow is counted rather than dropped",
		w2.movement.plans_deferred > 0, "%d deferred" % w2.movement.plans_deferred)
