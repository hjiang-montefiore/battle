extends SceneTree
## Which TICK SLOT costs the time? Times each subsystem by running it alone.
var _code := 1

func _bench(label: String, n: int, f: Callable) -> float:
	var t0 := Time.get_ticks_usec()
	for i in range(n):
		f.call()
	var us := float(Time.get_ticks_usec() - t0) / n
	print("  %-22s %8.3f ms/call" % [label, us / 1000.0])
	return us

func _initialize() -> void:
	var m := SimMatch.start(SimMatchSetup.scenario("peer"), SimArena.SKIRMISH_VALLEY, true)
	var w: SimWorld = m.world
	m.run_ticks(400)
	var dt := 1.0 / w.SIM_HZ
	print("entities %d\n" % w.entities.count())

	var t0 := Time.get_ticks_usec()
	m.run_ticks(400)
	var per_tick := float(Time.get_ticks_usec() - t0) / 400.0
	print("  %-22s %8.3f ms/tick  <- the whole thing\n" % ["full tick", per_tick / 1000.0])

	_bench("solver.solve", 20, func(): w.solver.solve(0.2, 0))
	_bench("munitions.step", 200, func(): w.munitions.step(dt))
	_bench("entities.decay", 200, func(): w.entities.decay_transients(dt))
	if w.movement != null:
		_bench("movement.step", 200, func(): w.movement.step(dt))
	if w.economy != null:
		_bench("economy.step", 200, func(): w.economy.step(1.0))
	if w.damage != null:
		_bench("damage.step", 200, func(): w.damage.step(dt))
	if w.weapons != null:
		_bench("weapons.step", 200, func(): w.weapons.step(dt))
	for pid in w.ai.keys():
		var d = w.ai[pid]
		_bench("ai[%s].step" % pid, 50, func(): d.step(dt))
		break
	_code = 0

func _process(_d: float) -> bool:
	quit(_code)
	return true
