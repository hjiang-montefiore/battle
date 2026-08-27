extends SceneTree
## Tests for the patrol system (SimPatrol, slot 3.6).
##
##     godot --path game --headless --script res://sim/tests/test_patrol.gd
##
## A separate file on purpose: the patrol, transport and sortie systems are
## built by parallel agents, and a shared test runner is a shared merge
## conflict. What is asserted here is the patrol CONTRACT:
##   - the loop walks A -> B -> A ... through the ordinary movement layer,
##     deterministically, for full circuits;
##   - engagement PAUSES the loop (the unit halts and fights) and the end of
##     the engagement RESUMES it from the nearest leg;
##   - aircraft are rejected -- their patrol is a sortie;
##   - any foreign order (move / stop) cancels the loop;
##   - two runs from one seed are tick-identical.

var _passed := 0
var _failed := 0
var _code := 1


func _init() -> void:
	print("")
	print("  BATTLE -- patrol tests (SimPatrol, slot 3.6)")
	print("  " + "-".repeat(66))

	_suite_install_and_routing()
	_suite_loop()
	_suite_multi_leg_loop()
	_suite_rejections()
	_suite_foreign_orders_cancel()
	_suite_pause_and_resume_manual()
	_suite_pause_and_resume_auto_engage()
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


# ── fixtures ─────────────────────────────────────────────────────────────────

func _world(seed_value: int) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.use_accumulator = false
	return w


## A plain ground mover: no sensors, no weapons. 15 m/s.
func _jeep(w: SimWorld, unit_name: String, faction: int, x: float, z: float) -> int:
	var i := w.entities.add(unit_name, faction, x, 0.0, z, SimSignature.new(6.0))
	w.entities.set_mobility(i, 15.0, 3.0, 1.0)
	return i


func _fc_radar() -> SimSensorDef:
	return SimSensorDef.new({
		"name": "FCR", "domain": SimTypes.Domain.RF_ACTIVE,
		"reference_range_km": 60.0, "mount_height_m": 3.0,
		"max_quality": SimTypes.TrackQuality.FIRE_CONTROL, "radar_gen": 4,
	})


func _gun(max_km := 4.0) -> SimWeaponDef:
	return SimWeaponDef.new({
		"name": "main gun", "guidance": SimTypes.Guidance.UNGUIDED,
		"min_range_km": 0.0, "max_range_km": max_km,
	})


func _pts(coords: Array) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	for c in coords:
		out.append(float(c))
	return out


# ═══════════════════════════════════════════════════════════════════════════
# 1. INSTALL AND ROUTING
# ═══════════════════════════════════════════════════════════════════════════

func _suite_install_and_routing() -> void:
	_suite("Install and command routing")

	# A bare world honestly reports no patrol system and REJECTS the order.
	var bare := _world(1)
	var bu := _jeep(bare, "jeep", 0, 0.0, 0.0)
	_ok("a bare world reports patrol unimplemented",
		bare.subsystem_status()["patrol"] == false)
	bare.commands.patrol(0, bu, _pts([100, 0]))
	bare.run_ticks(1)
	_ok("and a PATROL order routed to the missing system is rejected",
		bare.commands.rejected == 1 and bare.commands.executed == 0)

	# One line installs the system into the slot the spine left.
	var w := _world(2)
	var u := _jeep(w, "jeep", 0, 0.0, 0.0)
	var p := SimPatrol.install(w)
	_ok("install() fills the slot", w.patrol_system == p)
	_ok("and the world reports patrol implemented",
		w.subsystem_status()["patrol"] == true)

	w.commands.patrol(0, u, _pts([300, 0]))
	w.run_ticks(1)
	_ok("a PATROL order through the queue executes", w.commands.executed == 1)
	_ok("the unit is patrolling", p.is_patrolling(u))
	_ok("the loop is origin + the clicked point",
		p.points_of(u).size() == 4
			and p.points_of(u)[0] == 0.0 and p.points_of(u)[2] == 300.0)
	_ok("and it is walking leg 1, the first clicked point", p.leg_of(u) == 1)

	# Ownership is the queue's law: another player's patrol order is rejected.
	w.commands.patrol(1, u, _pts([50, 50]))
	w.run_ticks(1)
	_ok("an enemy cannot order my unit to patrol", w.commands.rejected == 1)


# ═══════════════════════════════════════════════════════════════════════════
# 2. THE LOOP -- at least two full circuits
# ═══════════════════════════════════════════════════════════════════════════

func _suite_loop() -> void:
	_suite("The loop: A -> B -> A, at least two full circuits")

	var w := _world(7)
	var p := SimPatrol.install(w)
	var u := _jeep(w, "jeep", 0, 0.0, 0.0)
	w.commands.patrol(0, u, _pts([300, 0]))

	# 300 m out and back at 15 m/s is ~40 s a circuit. 120 s is two circuits
	# with margin. Sample as we go so the test can prove the unit really
	# reached both ends rather than teleporting its counters.
	var max_x := -INF
	var min_x := INF
	var after_first_leg_min_x := INF
	for _chunk in range(240):
		w.run_ticks(10)
		max_x = maxf(max_x, w.entities.pos_x[u])
		min_x = minf(min_x, w.entities.pos_x[u])
		if p.legs_completed >= 1:
			after_first_leg_min_x = minf(after_first_leg_min_x, w.entities.pos_x[u])
	_ok("the unit reached the far point", max_x >= 290.0, "max x %.1f" % max_x)
	_ok("and came back to the origin", after_first_leg_min_x <= 10.0,
		"min x after first leg %.1f" % after_first_leg_min_x)
	_ok("at least two full circuits completed", p.circuits_completed >= 2,
		"%d circuits, %d legs" % [p.circuits_completed, p.legs_completed])
	_ok("the loop is still running -- a patrol never finishes on its own",
		p.is_patrolling(u) and w.entities.has_dest[u] == 1)
	_ok("it never wandered off the beat", min_x >= -40.0 and max_x <= 340.0,
		"x range [%.1f, %.1f]" % [min_x, max_x])


func _suite_multi_leg_loop() -> void:
	_suite("Multi-leg loop: origin -> P1 -> P2 -> origin ...")

	var w := _world(8)
	var p := SimPatrol.install(w)
	var u := _jeep(w, "boat", 0, 0.0, 0.0)
	w.commands.patrol(0, u, _pts([200, 0, 200, 200]))
	w.run_ticks(1)
	_ok("the loop holds three legs", p.points_of(u).size() == 6)

	var max_x := -INF
	var max_z := -INF
	for _chunk in range(260):
		w.run_ticks(10)
		max_x = maxf(max_x, w.entities.pos_x[u])
		max_z = maxf(max_z, w.entities.pos_z[u])
	_ok("both clicked corners were visited",
		max_x >= 190.0 and max_z >= 190.0,
		"max x %.1f, max z %.1f" % [max_x, max_z])
	_ok("two full triangles walked", p.circuits_completed >= 2,
		"%d circuits" % p.circuits_completed)


# ═══════════════════════════════════════════════════════════════════════════
# 3. REJECTIONS -- aircraft, structures, malformed loops
# ═══════════════════════════════════════════════════════════════════════════

func _suite_rejections() -> void:
	_suite("Rejections: aircraft patrol is a sortie, not a ground loop")

	var w := _world(9)
	var p := SimPatrol.install(w)

	var jet := w.entities.add("jet", 0, 0.0, 6000.0, 0.0,
		SimSignature.new(5.0), [], SimTypes.Category.AIR)
	w.entities.set_mobility(jet, 250.0, 10.0, 0.5)
	_ok("an aircraft PATROL order is refused at intake",
		p.order_patrol(jet, _pts([5000, 0])) == false)
	var rejected_before := w.commands.rejected
	w.commands.patrol(0, jet, _pts([5000, 0]))
	w.run_ticks(1)
	_ok("and counted rejected through the queue -- the UI should send SORTIE_PATROL",
		w.commands.rejected == rejected_before + 1)

	var ground := _jeep(w, "jeep", 0, 0.0, 0.0)
	_ok("a malformed point list is refused",
		p.order_patrol(ground, _pts([1])) == false
			and p.order_patrol(ground, PackedFloat32Array()) == false)
	_ok("a dead unit is refused", (func() -> bool:
		var v := _jeep(w, "victim", 0, 10.0, 10.0)
		w.entities.kill(v)
		return p.order_patrol(v, _pts([50, 0])) == false).call())
	_ok("naval and ground use the identical path -- SURFACE is accepted",
		(func() -> bool:
			var s := w.entities.add("cutter", 0, 400.0, 0.0, 400.0,
				SimSignature.new(80.0), [], SimTypes.Category.SURFACE)
			w.entities.set_mobility(s, 10.0, 1.0, 0.3)
			return p.order_patrol(s, _pts([600, 400]))).call())


# ═══════════════════════════════════════════════════════════════════════════
# 4. ANY NEW ORDER CANCELS THE LOOP
# ═══════════════════════════════════════════════════════════════════════════

func _suite_foreign_orders_cancel() -> void:
	_suite("Any new order cancels the loop")

	# A plain MOVE replaces the patrol.
	var w := _world(10)
	var p := SimPatrol.install(w)
	var u := _jeep(w, "jeep", 0, 0.0, 0.0)
	w.commands.patrol(0, u, _pts([300, 0]))
	w.run_ticks(100)   # 5 s: mid-leg, ~75 m out
	_ok("(setup) the unit is mid-leg", w.entities.pos_x[u] > 30.0
		and p.is_patrolling(u))
	w.commands.move(0, u, 100.0, 250.0)
	w.run_ticks(5)
	_ok("a foreign MOVE cancels the patrol", not p.is_patrolling(u))
	_ok("and the foreign order stands untouched",
		w.entities.has_dest[u] == 1
			and absf(w.entities.dest_x[u] - 100.0) < 1.0
			and absf(w.entities.dest_z[u] - 250.0) < 1.0)
	w.run_ticks(600)
	_ok("the unit ends at the ordered point and STAYS -- no ghost legs",
		absf(w.entities.pos_x[u] - 100.0) < 40.0
			and absf(w.entities.pos_z[u] - 250.0) < 40.0
			and w.entities.has_dest[u] == 0,
		"at %.0f,%.0f" % [w.entities.pos_x[u], w.entities.pos_z[u]])

	# A STOP mid-leg ends the patrol too.
	var w2 := _world(11)
	var p2 := SimPatrol.install(w2)
	var u2 := _jeep(w2, "jeep", 0, 0.0, 0.0)
	w2.commands.patrol(0, u2, _pts([300, 0]))
	w2.run_ticks(100)
	w2.commands.stop(0, u2)
	w2.run_ticks(5)
	_ok("a STOP mid-leg cancels the patrol", not p2.is_patrolling(u2))
	var x_at_stop := w2.entities.pos_x[u2]
	w2.run_ticks(200)
	_ok("and the unit stays put",
		absf(w2.entities.pos_x[u2] - x_at_stop) < 1.0
			and w2.entities.speed_ms[u2] == 0.0)

	# A fresh PATROL simply replaces the loop.
	var w3 := _world(12)
	var p3 := SimPatrol.install(w3)
	var u3 := _jeep(w3, "jeep", 0, 0.0, 0.0)
	w3.commands.patrol(0, u3, _pts([300, 0]))
	w3.run_ticks(40)
	w3.commands.patrol(0, u3, _pts([0, 200]))
	w3.run_ticks(5)
	_ok("a new PATROL replaces the old loop",
		p3.is_patrolling(u3) and absf(p3.points_of(u3)[3] - 200.0) < 0.1)


# ═══════════════════════════════════════════════════════════════════════════
# 5. ENGAGEMENT PAUSES THE LOOP; ITS END RESUMES IT (manual engagement)
# ═══════════════════════════════════════════════════════════════════════════

func _suite_pause_and_resume_manual() -> void:
	_suite("Engagement pauses the loop; disengagement resumes at the nearest leg")

	var w := _world(21)
	var p := SimPatrol.install(w)
	var e := w.entities
	# Armed patroller with a fire-control radar. The gun's reach is SHORT so
	# the engagement never actually kills: what is under test is the pause,
	# not the shot.
	var u := e.add("patroller", 0, 0.0, 2.0, 0.0, SimSignature.new(20.0),
		[_fc_radar()], SimTypes.Category.GROUND, 3.0)
	e.set_mobility(u, 15.0, 3.0, 1.0)
	w.weapons.arm(u, _gun(1.0), SimArmorScheme.make_gun_round(SimArmorScheme.Gen.G1), 6.0)
	# A contact well outside the gun but square in the radar.
	var far := e.add("spotter", 1, 0.0, 2.0, 3000.0, SimSignature.new(10.0))

	w.commands.patrol(0, u, _pts([400, 0]))
	# Let the picture form and the unit get PAST the midpoint, so "nearest
	# leg" is unambiguous later.
	while e.pos_x[u] < 260.0 and w.tick < 2000:
		w.run_ticks(10)
	_ok("(setup) mid-leg past the midpoint, track held",
		e.pos_x[u] >= 260.0 and not w.track_table_for(0).track_ids().is_empty())

	# The same engagement an ATTACK_TRACK order sets.
	var tid: int = w.track_table_for(0).track_ids()[0]
	w.commands.attack_track(0, u, tid)
	w.run_ticks(3)
	_ok("the unit is engaging", w.weapons.is_engaging(u))
	_ok("and the loop PAUSED: halted, no movement orders",
		p.patrol_state(u) == SimPatrol.State.ENGAGED
			and w.movement.order_count(u) == 0
			and e.has_dest[u] == 0)
	var x_paused := e.pos_x[u]
	w.run_ticks(100)
	_ok("it holds its ground while the engagement lasts",
		absf(e.pos_x[u] - x_paused) < 2.0 and e.speed_ms[u] == 0.0,
		"drift %.2f m" % absf(e.pos_x[u] - x_paused))
	_ok("and is still patrolling -- paused is not cancelled", p.is_patrolling(u))

	# End the engagement (weapons hold / released). The far target and its
	# track still exist; only the engagement ended.
	w.weapons.disengage(u)
	w.run_ticks(3)
	_ok("the loop RESUMES", p.patrol_state(u) == SimPatrol.State.ACTIVE)
	_ok("from the NEAREST leg -- the far point, since it stopped past midway",
		absf(e.dest_x[u] - 400.0) < 1.0 and absf(e.dest_z[u]) < 1.0,
		"resumed toward %.0f,%.0f" % [e.dest_x[u], e.dest_z[u]])
	var circuits_before: int = p.circuits_completed
	w.run_ticks(1600)   # 80 s: to the far point and a full lap
	_ok("and keeps looping afterwards", p.circuits_completed > circuits_before,
		"%d -> %d circuits" % [circuits_before, p.circuits_completed])

	# The engagement never became a kill -- proving the pause came from the
	# ENGAGEMENT, not from the target dying.
	_ok("(guard) the far contact was never killed", e.is_alive(far))


# ═══════════════════════════════════════════════════════════════════════════
# 6. THE FULL LIFE CYCLE: auto-engage en route, kill, track decay, resume
# ═══════════════════════════════════════════════════════════════════════════

## Auto-engage + patrol, end to end. Shared with the determinism suite.
func _hunt(seed_value: int, total_ticks: int) -> Dictionary:
	var w := _world(seed_value)
	var p := SimPatrol.install(w)
	var e := w.entities
	var u := e.add("patroller", 0, 0.0, 2.0, 0.0, SimSignature.new(20.0),
		[_fc_radar()], SimTypes.Category.GROUND, 3.0)
	e.set_mobility(u, 15.0, 3.0, 1.0)
	w.weapons.arm(u, _gun(4.0), SimArmorScheme.make_gun_round(SimArmorScheme.Gen.G1), 3.0)
	# The fire-control layer, exactly as a match wires it: automatic target
	# selection from the faction's own table. Patrol itself never engages.
	w.fire_control = SimFireControl.new(e, w.weapons, w.solver)
	var truck := e.add("truck", 1, 500.0, 2.0, 300.0, SimSignature.new(8.0))

	w.commands.patrol(0, u, _pts([1000, 0]))
	var saw_engaged_pause := false
	var halted_x := 0.0
	var ticks_run := 0
	while ticks_run < total_ticks:
		w.run_ticks(5)
		ticks_run += 5
		if not saw_engaged_pause and w.weapons.is_engaging(u) \
				and p.patrol_state(u) == SimPatrol.State.ENGAGED \
				and w.movement.order_count(u) == 0:
			saw_engaged_pause = true
			halted_x = e.pos_x[u]
	return {
		"world": w, "patrol": p, "unit": u, "truck": truck,
		"paused": saw_engaged_pause, "halted_x": halted_x,
		"hash": w.state_hash(), "shots": w.weapons.shots_fired,
		"circuits": p.circuits_completed, "legs": p.legs_completed,
	}


func _suite_pause_and_resume_auto_engage() -> void:
	_suite("Auto-engage en route: fire control engages, patrol pauses, kill, resume")

	# 260 s: engage in the first seconds, a short shoot, the full 60 s track
	# decay ladder after the kill, then time to prove the loop restarted.
	var r := _hunt(99, 5200)
	var w := r["world"] as SimWorld
	var p := r["patrol"] as SimPatrol
	var u: int = r["unit"]

	_ok("fire control engaged the patroller en route -- no order was given",
		r["paused"], "auto-engage pause observed")
	_ok("the pause happened on the way out, not at the far point",
		r["halted_x"] > 0.0 and r["halted_x"] < 900.0,
		"halted at x=%.0f" % r["halted_x"])
	_ok("the contact was killed", not w.entities.is_alive(r["truck"]))
	_ok("the dead contact's track decayed away",
		w.track_table_for(0).count() == 0)
	_ok("the engagement ended with it", not w.weapons.is_engaging(u))
	_ok("the patrol resumed", p.is_patrolling(u)
		and p.patrol_state(u) == SimPatrol.State.ACTIVE)
	_ok("and walked full circuits afterwards", p.circuits_completed >= 1,
		"%d circuits, %d legs" % [p.circuits_completed, p.legs_completed])


# ═══════════════════════════════════════════════════════════════════════════
# 7. DETERMINISM
# ═══════════════════════════════════════════════════════════════════════════

func _suite_determinism() -> void:
	_suite("Determinism: same seed, same patrol war, to the tick")

	var a := _hunt(2026, 2600)
	var b := _hunt(2026, 2600)
	_ok("two runs of the same seeded patrol+engagement hash identically",
		a["hash"] == b["hash"], "%d vs %d" % [a["hash"], b["hash"]])
	_ok("same shots fired", a["shots"] == b["shots"],
		"%d vs %d" % [a["shots"], b["shots"]])
	_ok("same legs and circuits",
		a["legs"] == b["legs"] and a["circuits"] == b["circuits"])
	_ok("same pause point, to the metre",
		absf(float(a["halted_x"]) - float(b["halted_x"])) < 0.0001)

	# The ban list, same as the other subsystem suites: no wall clock, no
	# global RNG anywhere in the patrol file.
	var src := FileAccess.get_file_as_string("res://sim/movement/sim_patrol.gd")
	var banned := ["randf(", "randi(", "randf_range(", "Time.get_ticks"]
	var found := PackedStringArray()
	for token in banned:
		if src.contains(token):
			found.append(token)
	_ok("sim_patrol.gd never touches randf(), randi() or the wall clock",
		found.is_empty(), ", ".join(found))
