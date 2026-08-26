extends SceneTree
## How fast does the simulation run, independent of what else the machine is
## doing?
##
##   Godot --headless --path game --script sim/tests/bench_sim.gd
##
## WHY NORMALISED. Absolute milliseconds are worthless here. Measuring the same
## unchanged code while an art build ran in the background gave 13.5 ms and
## 69.0 ms for one sensor solve -- a factor of five, entirely from load. Every
## "speedup" measured that way is noise, and twice during this optimisation
## pass a change looked like a large regression when the machine had simply got
## busier.
##
## So this first times a fixed arithmetic workload to establish what this
## machine is worth RIGHT NOW, then reports simulation cost as a multiple of
## it. That ratio is stable under load and comparable between runs.
const CALIB_ITERS := 400000

var _code := 1


func _calibrate() -> float:
	var t0 := Time.get_ticks_usec()
	var acc := 0.0
	for i in range(CALIB_ITERS):
		acc += sqrt(float(i) * 1.000001)
	var us := float(Time.get_ticks_usec() - t0)
	if acc < 0.0:
		print("")            # keep the optimiser honest
	return us


func _initialize() -> void:
	var calib := _calibrate()
	var m := SimMatch.start(SimMatchSetup.scenario("peer"),
		SimArena.SKIRMISH_VALLEY, true)
	var w: SimWorld = m.world
	m.run_ticks(400)                       # past deployment

	var n := 600
	var t0 := Time.get_ticks_usec()
	m.run_ticks(n)
	var total := float(Time.get_ticks_usec() - t0)

	var per_tick := total / n
	var sim_seconds := n / w.SIM_HZ
	print("BENCH  %d entities, %d ticks" % [w.entities.count(), n])
	print("  calibration workload   %8.1f ms   <- what this machine is worth now" % (calib / 1000.0))
	print("  wall per tick          %8.3f ms" % (per_tick / 1000.0))
	print("  realtime factor        %8.2fx   (absolute, load-dependent)"
		% (sim_seconds / (total / 1e6)))
	print("  NORMALISED COST        %8.2f   <- ticks per calibration unit; LOWER is better"
		% (per_tick / calib * 1000.0))
	print("\n  Compare the normalised figure between runs. The realtime factor")
	print("  is what you actually feel, but only on an idle machine.")
	_code = 0


func _process(_delta: float) -> bool:
	quit(_code)
	return true
