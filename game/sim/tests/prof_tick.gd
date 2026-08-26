extends SceneTree
## Where does a tick actually go? Measure before optimising.
##   Godot --headless --path game --script sim/tests/prof_tick.gd
var _code := 1

func _initialize() -> void:
	var setup := SimMatchSetup.scenario("peer")
	var m := SimMatch.start(setup, SimArena.SKIRMISH_VALLEY, true)
	var w: SimWorld = m.world
	m.run_ticks(400)                      # warm up past deployment
	print("entities: %d   SIM_HZ: %s   SENSOR_HZ: %s"
		% [w.entities.count(), w.SIM_HZ, w.SENSOR_HZ])

	var N := 600
	var t0 := Time.get_ticks_usec()
	m.run_ticks(N)
	var total := Time.get_ticks_usec() - t0
	print("\n  %d ticks in %.2f s  ->  %.3f ms/tick, %.1fx realtime"
		% [N, total / 1e6, total / 1000.0 / N, (N / float(w.SIM_HZ)) / (total / 1e6)])

	# isolate the sensor solve: run the same span with the solver stubbed out
	var solver := w.solver
	var t1 := Time.get_ticks_usec()
	for i in range(N):
		w.entities.decay_transients(1.0 / w.SIM_HZ)
		w.munitions.step(1.0 / w.SIM_HZ)
	var without := Time.get_ticks_usec() - t1
	print("  munitions + transients alone: %.3f ms/tick" % (without / 1000.0 / N))

	var t2 := Time.get_ticks_usec()
	for i in range(20):
		solver.solve(1.0 / 4.0, i)
	var solve := Time.get_ticks_usec() - t2
	print("  ONE sensor solve: %.2f ms  (x%s per second = %.1f ms/s)"
		% [solve / 1000.0 / 20.0, w.SENSOR_HZ, solve / 1000.0 / 20.0 * float(w.SENSOR_HZ)])
	_code = 0

func _process(_d: float) -> bool:
	quit(_code)
	return true
