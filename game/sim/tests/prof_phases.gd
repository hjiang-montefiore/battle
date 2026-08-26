extends SceneTree
var _code := 1
func _initialize() -> void:
	SimSensorSolver.PROFILE = true
	var m := SimMatch.start(SimMatchSetup.scenario("peer"), SimArena.SKIRMISH_VALLEY, true)
	var w: SimWorld = m.world
	m.run_ticks(400)
	var s := w.solver
	s.t_reach = 0; s.t_los = 0; s.t_contribute = 0; s.n_reach = 0; s.n_los = 0
	var t0 := Time.get_ticks_usec()
	for i in range(20):
		s.solve(0.2, i)
	var total := Time.get_ticks_usec() - t0
	print("total solve  %8.2f ms  (20 solves)" % (total / 1000.0))
	print("  _reach_km    %8.2f ms  %6d calls  %.1f%%  (%.1f us each)"
		% [s.t_reach / 1000.0, s.n_reach, 100.0 * s.t_reach / total, float(s.t_reach) / maxi(1, s.n_reach)])
	print("  LOS rays     %8.2f ms  %6d calls  %.1f%%" % [s.t_los / 1000.0, s.n_los, 100.0 * s.t_los / total])
	print("  _contribute  %8.2f ms                 %.1f%%" % [s.t_contribute / 1000.0, 100.0 * s.t_contribute / total])
	print("  UNACCOUNTED  %8.2f ms                 %.1f%%"
		% [(total - s.t_reach - s.t_los - s.t_contribute) / 1000.0,
		   100.0 * (total - s.t_reach - s.t_los - s.t_contribute) / total])
	_code = 0
func _process(_d: float) -> bool:
	quit(_code)
	return true
