extends SceneTree
var _code := 1

func _t(label: String, mv, dt: float, n: int) -> float:
	var t0 := Time.get_ticks_usec()
	for i in range(n):
		mv.step(dt)
	var us := float(Time.get_ticks_usec() - t0) / n
	print("  %-34s %8.3f ms/tick" % [label, us / 1000.0])
	return us

func _initialize() -> void:
	var m := SimMatch.start(SimMatchSetup.scenario("peer"), SimArena.SKIRMISH_VALLEY, true)
	var w: SimWorld = m.world
	m.run_ticks(400)
	var mv = w.movement
	var dt := 1.0 / w.SIM_HZ
	print("entities %d\n" % w.entities.count())

	var base := _t("as shipped", mv, dt, 300)
	var sep: bool = mv.separation_enabled
	mv.separation_enabled = false
	var no_sep := _t("separation OFF", mv, dt, 300)
	mv.separation_enabled = sep

	var eb: int = mv.expansion_budget_per_tick
	mv.expansion_budget_per_tick = 400
	var small := _t("A* budget 4000 -> 400", mv, dt, 300)
	mv.expansion_budget_per_tick = eb

	var rb: int = mv.replan_budget_per_tick
	mv.replan_budget_per_tick = 0
	var no_plan := _t("replans OFF (steering only)", mv, dt, 300)
	mv.replan_budget_per_tick = rb

	print("\n  pathfinding is %.0f%% of movement; separation is %.0f%%"
		% [100.0 * (base - no_plan) / base, 100.0 * (base - no_sep) / base])
	_code = 0

func _process(_d: float) -> bool:
	quit(_code)
	return true
