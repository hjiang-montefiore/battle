extends SceneTree
## Tests for the sortie system: docs/04's aircraft half, wired by
## sim/air/sim_sortie.gd into the spine's slot 3.7.
##
##     godot --path game --headless --script res://sim/tests/test_sortie.gd
##
## A separate file from run_sim_tests.gd on purpose: parallel agents build the
## order systems against one spine, and a shared runner is a shared merge
## conflict.
##
## What is asserted is docs/04's CLAIMS. The RTB rule is asserted AT the
## turn-around -- range_remaining against d_home, inside the published 1.10
## reserve -- not merely "it came home". The Empire Earth loop is asserted as
## a loop: one patrol order, two launches, zero extra commands. And the
## dramatic consequence -- kill the airfield, strand the aircraft -- is
## asserted both ways: divert when a field survives, crash dry when none does.

var _passed := 0
var _failed := 0
var _code := 1


func _init() -> void:
	print("")
	print("  BATTLE -- sortie tests (docs/04)")
	print("  " + "-".repeat(66))

	_suite_install()
	_suite_strike_round_trip()
	_suite_rtb_rule_margin()
	_suite_patrol_standing_loop()
	_suite_divert()
	_suite_stranded_crash()
	_suite_refusals()
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

## A bare world with one player at epoch 3 (attack helicopters exist from 3)
## and the sortie system installed the way a match installs it.
func _world(seed_value := 11) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.use_accumulator = false
	w.economy.add_player(0, 100000.0, 3, 7)
	SimSortie.install(w)
	return w


func _dist(w: SimWorld, u: int, x: float, z: float) -> float:
	var dx := w.entities.pos_x[u] - x
	var dz := w.entities.pos_z[u] - z
	return sqrt(dx * dx + dz * dz)


## Run until the predicate holds, in `stride`-tick bites. Returns ticks run,
## or -1 when the cap was hit first.
func _until(w: SimWorld, cap: int, stride: int, pred: Callable) -> int:
	var n := 0
	while n < cap:
		w.run_ticks(stride)
		n += stride
		if pred.call():
			return n
	return -1


# ── 1. installation ──────────────────────────────────────────────────────────

func _suite_install() -> void:
	_suite("Installed: slot 3.7 has a real system behind it")
	var w := _world()
	_ok("subsystem_status reports the sortie system present",
		w.subsystem_status()["sortie"] == true)
	_ok("a bare world without it reports absent",
		SimWorld.new(1).subsystem_status()["sortie"] == false)


# ── 2. the full strike round trip ────────────────────────────────────────────

func _suite_strike_round_trip() -> void:
	_suite("Strike: launch, transit, deliver, come home, park")

	var w := _world()
	var base := w.economy.place_starting_unit(0, "airbase", 0.0, 0.0)
	var jet := w.economy.place_starting_unit(0, "interceptor", 60.0, 0.0)
	_ok("fixture: base and aircraft on the map", base >= 0 and jet >= 0)
	_ok("an aircraft spawns GROUNDED",
		w.entities.sortie_state[jet] == SimTypes.SortieState.GROUNDED)

	var s: SimSortie = w.sortie_system
	w.commands.sortie_strike(0, jet, 20000.0, 0.0)
	w.run_ticks(1)
	_ok("the order is executed through the queue, not rejected",
		w.commands.executed == 1 and w.commands.rejected == 0)
	_ok("and the aircraft launches the same tick",
		w.entities.sortie_state[jet] == SimTypes.SortieState.OUTBOUND
			and s.sorties_flown == 1)
	_ok("home base was adopted at order time",
		w.entities.home_base[jet] == base)

	var cond1 := func(): return w.entities.sortie_state[jet] == SimTypes.SortieState.ON_STATION
	var t := _until(w, 3000, 10, cond1)
	_ok("it arrives on station", t > 0, "after %d ticks" % t)
	_ok("near the tasked point",
		_dist(w, jet, 20000.0, 0.0) < 1800.0,
		"%.0f m out" % _dist(w, jet, 20000.0, 0.0))
	_ok("and it climbed on the way", w.entities.pos_y[jet] > 400.0,
		"altitude %.0f m" % w.entities.pos_y[jet])

	var cond2 := func(): return (
		w.entities.sortie_state[jet] == SimTypes.SortieState.RTB
		or w.entities.sortie_state[jet] == SimTypes.SortieState.RECOVERING
		or w.entities.sortie_state[jet] == SimTypes.SortieState.GROUNDED)
	t = _until(w, 2000, 10, cond2)
	_ok("the station ends and it turns for home", t > 0)
	_ok("because it delivered, not because of fuel",
		String(s.last_rtb.get(jet, {}).get("reason", "")) == "delivered")

	var cond3 := func(): return w.entities.sortie_state[jet] == SimTypes.SortieState.GROUNDED
	t = _until(w, 12000, 10, cond3)
	_ok("it recovers", t > 0, "after %d more ticks" % t)
	_ok("alive, at its base", w.entities.is_alive(jet)
		and _dist(w, jet, 0.0, 0.0) < 120.0,
		"%.0f m from base" % _dist(w, jet, 0.0, 0.0))
	_ok("with fuel still in the tank", w.entities.fuel[jet] > 0.0,
		"%.0f L" % w.entities.fuel[jet])
	_ok("back on the deck", w.entities.pos_y[jet] < 30.0,
		"altitude %.1f m" % w.entities.pos_y[jet])
	_ok("a strike is one launch: the task is cleared by the landing",
		not s.has_task(jet))
	_ok("one sortie, one recovery", s.sorties_flown == 1 and s.recoveries == 1)


# ── 3. the docs/04 rule, at the moment it fires ──────────────────────────────

func _suite_rtb_rule_margin() -> void:
	_suite("RTB rule: range_remaining < 1.10 x d_home, asserted at turn-around")

	var w := _world()
	var base := w.economy.place_starting_unit(0, "airbase", 0.0, 0.0)
	var jet := w.economy.place_starting_unit(0, "interceptor", 60.0, 0.0)
	var s: SimSortie = w.sortie_system
	w.commands.sortie_strike(0, jet, 20000.0, 0.0)

	var t := _until(w, 2000, 5, func(): return w.entities.pos_x[jet] > 4000.0)
	_ok("fixture: outbound and well clear of the base", t > 0)
	# THE TEST'S PRIVILEGE: drain the tank mid-flight. ~120 L at epoch-3
	# cruise burn is ~26 km of range -- enough to guarantee coming home from
	# where it is, not enough to reach the target 20 km out and return.
	w.entities.fuel[jet] = 120.0

	var cond4 := func(): return w.entities.sortie_state[jet] == SimTypes.SortieState.RTB
	t = _until(w, 3000, 1, cond4)
	_ok("the rule trips while still outbound", t > 0
		and w.entities.pos_x[jet] < 19000.0,
		"at x=%.0f m" % w.entities.pos_x[jet])
	var rec: Dictionary = s.last_rtb.get(jet, {})
	_ok("for fuel, not delivery", String(rec.get("reason", "")) == "fuel")
	var rr := float(rec.get("range_m", 0.0))
	var dh := float(rec.get("d_home_m", 1.0))
	var oh := float(rec.get("overhead_m", 0.0))
	_ok("margin at turn-around: the tank still covers the trip home",
		rr >= dh + oh,
		"range %.0f m vs d_home %.0f + landing %.0f m" % [rr, dh, oh])
	_ok("and it did not turn early: the 1.10 reserve was only just breached",
		rr < 1.1001 * (dh + oh), "ratio %.4f" % (rr / (dh + oh)))

	var cond5 := func(): return (
		w.entities.sortie_state[jet] == SimTypes.SortieState.GROUNDED
		or not w.entities.is_alive(jet))
	t = _until(w, 6000, 1, cond5)
	_ok("it comes home BEFORE dry: alive and grounded",
		t > 0 and w.entities.is_alive(jet)
			and w.entities.sortie_state[jet] == SimTypes.SortieState.GROUNDED)
	_ok("the thin reserve was enough", w.entities.fuel[jet] > 0.0,
		"%.1f L left" % w.entities.fuel[jet])
	_ok("an undelivered strike does not relaunch itself", not s.has_task(jet))
	_ok("home base is the airbase it came from",
		w.entities.home_base[jet] == base)


# ── 4. the Empire Earth loop ─────────────────────────────────────────────────

func _suite_patrol_standing_loop() -> void:
	_suite("Patrol: one order, RTB on fuel, refuel, relaunch -- a standing loop")

	var w := _world()
	w.economy.place_starting_unit(0, "helipad", 0.0, 0.0)
	var heli := w.economy.place_starting_unit(0, "attack_helicopter", 40.0, 0.0)
	var s: SimSortie = w.sortie_system
	# A small tank, set at spawn, so the loop turns over in test time. ~400 L
	# at epoch-3 rotary burn is ~20 km of range.
	w.entities.fuel_capacity[heli] = 400.0
	w.entities.fuel[heli] = 400.0

	w.commands.sortie_patrol(0, heli, 3000.0, 0.0, 1000.0)
	w.run_ticks(1)
	_ok("the order is executed", w.commands.executed == 1)
	_ok("and the helicopter launches", s.sorties_flown == 1)

	var cond6 := func(): return w.entities.sortie_state[heli] == SimTypes.SortieState.ON_STATION
	var t := _until(w, 2000, 10, cond6)
	_ok("it takes station", t > 0)
	_ok("on the ordered orbit", _dist(w, heli, 3000.0, 0.0) < 1900.0,
		"%.0f m from centre" % _dist(w, heli, 3000.0, 0.0))
	_ok("flying low, as rotary does",
		w.entities.pos_y[heli] > 50.0 and w.entities.pos_y[heli] < 400.0,
		"altitude %.0f m" % w.entities.pos_y[heli])

	var cond7 := func(): return (
		w.entities.sortie_state[heli] == SimTypes.SortieState.GROUNDED
		or not w.entities.is_alive(heli))
	t = _until(w, 12000, 10, cond7)
	_ok("fuel brings it home without any new order",
		t > 0 and w.entities.is_alive(heli)
			and w.entities.sortie_state[heli] == SimTypes.SortieState.GROUNDED)
	_ok("the fuel rule is what sent it back",
		String(s.last_rtb.get(heli, {}).get("reason", "")) == "fuel")
	_ok("the patrol order STANDS across the landing", s.has_task(heli))
	var flown_before: int = s.sorties_flown

	t = _until(w, 8000, 10, func(): return s.sorties_flown > flown_before)
	_ok("after turnaround and refuel the base relaunches it -- no new order",
		t > 0, "relaunch after %d ticks on the pad" % t)
	_ok("still exactly one command was ever issued",
		w.commands.submitted == 1 and w.commands.executed == 1)

	var cond8 := func(): return w.entities.sortie_state[heli] == SimTypes.SortieState.ON_STATION
	t = _until(w, 2000, 10, cond8)
	_ok("and it resumes the SAME patrol", t > 0
		and _dist(w, heli, 3000.0, 0.0) < 1900.0)


# ── 5. losing a field mid-sortie: divert ─────────────────────────────────────

func _suite_divert() -> void:
	_suite("Recovery lost mid-sortie: d_home recomputes, the aircraft diverts")

	var w := _world()
	var base_a := w.economy.place_starting_unit(0, "airbase", 0.0, 0.0)
	var base_b := w.economy.place_starting_unit(0, "airbase", 6000.0, 0.0)
	var jet := w.economy.place_starting_unit(0, "interceptor", 60.0, 0.0)
	var s: SimSortie = w.sortie_system
	w.commands.sortie_strike(0, jet, 20000.0, 0.0)

	var cond9 := func(): return w.entities.sortie_state[jet] == SimTypes.SortieState.RTB
	var t := _until(w, 4000, 5, cond9)
	_ok("fixture: delivered and homing", t > 0)
	_ok("on the NEAREST field, which is the forward one",
		w.entities.home_base[jet] == base_b)

	w.entities.kill(base_b)
	w.run_ticks(5)
	_ok("the forward field dies; it diverts to the survivor",
		w.entities.home_base[jet] == base_a and s.diverts >= 1)

	var cond10 := func(): return w.entities.sortie_state[jet] == SimTypes.SortieState.GROUNDED
	t = _until(w, 12000, 10, cond10)
	_ok("and recovers there", t > 0 and w.entities.is_alive(jet)
		and _dist(w, jet, 0.0, 0.0) < 120.0,
		"%.0f m from the surviving base" % _dist(w, jet, 0.0, 0.0))


# ── 6. losing EVERY field: fly until dry, then crash ─────────────────────────

func _suite_stranded_crash() -> void:
	_suite("No recovery survives: the aircraft flies on and crashes dry")

	var w := _world()
	var base := w.economy.place_starting_unit(0, "airbase", 0.0, 0.0)
	var jet := w.economy.place_starting_unit(0, "interceptor", 60.0, 0.0)
	var s: SimSortie = w.sortie_system
	w.commands.sortie_strike(0, jet, 20000.0, 0.0)

	var cond11 := func(): return w.entities.sortie_state[jet] == SimTypes.SortieState.RTB
	var t := _until(w, 4000, 5, cond11)
	_ok("fixture: homing on the only field", t > 0)

	w.entities.kill(base)
	w.run_ticks(20)
	_ok("with no field left it is stranded, still flying",
		w.entities.is_alive(jet)
			and bool(s.task_of(jet).get("stranded", false)))
	_ok("it does not pretend to land",
		w.entities.sortie_state[jet] != SimTypes.SortieState.GROUNDED)

	# Shrink the wait: a near-empty tank, and the existing economy rule --
	# "air is destroyed" on running dry -- does the rest. Nothing in the
	# sortie system kills anything.
	w.entities.fuel[jet] = 15.0
	t = _until(w, 1200, 5, func(): return not w.entities.is_alive(jet))
	_ok("it runs dry in the air and comes down destroyed", t > 0)


# ── 7. honest refusals ───────────────────────────────────────────────────────

func _suite_refusals() -> void:
	_suite("Refusals: not an aircraft, out of reach -- rejected, counted")

	var w := _world()
	w.economy.place_starting_unit(0, "airbase", 0.0, 0.0)
	var tank := w.economy.place_starting_unit(0, "mbt", 100.0, 0.0)
	var jet := w.economy.place_starting_unit(0, "interceptor", 60.0, 0.0)

	w.commands.sortie_strike(0, tank, 5000.0, 0.0)
	w.run_ticks(1)
	_ok("a tank cannot fly a sortie", w.commands.rejected == 1)

	# A tank too small for the round trip, set at spawn: ~50 L is ~10 km of
	# range against a 40 km round trip.
	w.entities.fuel_capacity[jet] = 50.0
	w.entities.fuel[jet] = 50.0
	w.commands.sortie_strike(0, jet, 20000.0, 0.0)
	w.run_ticks(1)
	_ok("a strike beyond round-trip range is refused at order time",
		w.commands.rejected == 2)
	_ok("and the aircraft never launched",
		w.entities.sortie_state[jet] == SimTypes.SortieState.GROUNDED
			and (w.sortie_system as SimSortie).sorties_flown == 0)


# ── 8. determinism ───────────────────────────────────────────────────────────

func _run_patrol_scenario(seed_value: int, ticks: int) -> Dictionary:
	var w := _world(seed_value)
	w.economy.place_starting_unit(0, "helipad", 0.0, 0.0)
	var heli := w.economy.place_starting_unit(0, "attack_helicopter", 40.0, 0.0)
	w.entities.fuel_capacity[heli] = 400.0
	w.entities.fuel[heli] = 400.0
	w.commands.sortie_patrol(0, heli, 3000.0, 0.0, 1000.0)
	w.run_ticks(ticks)
	var s: SimSortie = w.sortie_system
	return {"hash": w.state_hash(), "flown": s.sorties_flown,
		"recovered": s.recoveries, "x": w.entities.pos_x[heli],
		"state": w.entities.sortie_state[heli]}


func _suite_determinism() -> void:
	_suite("Determinism: same seed, same sortie, to the tick")

	# Long enough to cover launch, station, RTB, landing, turnaround and the
	# relaunch -- the whole loop, twice over.
	var a := _run_patrol_scenario(2027, 9000)
	var b := _run_patrol_scenario(2027, 9000)
	_ok("two runs hash identically", a["hash"] == b["hash"],
		"%d vs %d" % [a["hash"], b["hash"]])
	_ok("same sorties flown, same recoveries",
		a["flown"] == b["flown"] and a["recovered"] == b["recovered"],
		"flown %d recovered %d" % [a["flown"], a["recovered"]])
	_ok("same position, same state",
		is_equal_approx(float(a["x"]), float(b["x"])) and a["state"] == b["state"])
	_ok("and the loop actually turned over", int(a["flown"]) >= 2,
		"flown %d" % a["flown"])

	# Nothing in the sortie file may reach for the global RNG or the clock.
	var src := FileAccess.get_file_as_string("res://sim/air/sim_sortie.gd")
	var banned: Array[String] = ["randf" + "(", "randi" + "(",
		"randf_range" + "(", "Time." + "get_ticks"]
	var found := PackedStringArray()
	for token in banned:
		if src.contains(token):
			found.append(token)
	_ok("sim_sortie.gd never calls the RNG or the wall clock",
		found.is_empty(),
		"found " + ", ".join(found) if not found.is_empty() else "")
