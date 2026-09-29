extends SceneTree
## MEASUREMENT ONLY -- the expansion question, answered in numbers.
##
##   Godot --headless --path game --script res://sim/tests/probe_ai_expansion.gd
##
## Three numbers per side, once a minute: DERRICKS held, INCOME earned, and the
## EPOCH reached. Plus, once at the start, where the oil actually is relative to
## the build envelope, because that distance is the whole problem.

const MINUTES := 12

var _code := 1

func _initialize() -> void:
	for arena in [SimArena.SKIRMISH_VALLEY, SimArena.OPEN_STEPPE]:
		_run(arena)
	_code = 0
	quit(_code)


func _run(arena: String) -> void:
	var setup := SimMatchSetup.scenario("peer")
	var m := SimMatch.start(setup, arena, true)
	var w: SimWorld = m.world
	var e: SimEntities = w.entities
	print("\n══ arena %s ═══════════════════════════════════════════" % arena)

	# WHERE THE OIL IS, against the envelope that has to reach it.
	for pid in [0, 1]:
		var d: SimAiDirector = w.ai.get(pid)
		if d == null:
			continue
		var ds := PackedStringArray()
		for p in w.economy.oil_fields:
			ds.append("%.0f" % sqrt(pow(p.x - d.home_x, 2.0)
				+ pow(p.y - d.home_z, 2.0)))
		print("AI %d home (%.0f, %.0f)  oil at %s m" % [pid, d.home_x, d.home_z,
			", ".join(ds)])

	for minute in range(MINUTES):
		m.run_ticks(int(60.0 * SimWorld.SIM_HZ))
		var row := PackedStringArray()
		for pid in [0, 1]:
			var d: SimAiDirector = w.ai.get(pid)
			if d == null:
				continue
			var derricks := 0
			var relays := 0
			var refineries := 0
			for i in m.own_units(pid):
				if not e.is_alive(i) or e.is_structure[i] == 0:
					continue
				var ud := w.economy.def_of(i)
				if ud == null:
					continue
				if ud.role == "oil_derrick":
					derricks += 1
				elif ud.role == "supply_depot":
					relays += 1
				elif ud.refine_capacity > 0.0:
					refineries += 1
			var p := w.economy.purse(pid)
			row.append("AI%d ep%d der%d ref%d dep%d  %.0f cr/min  earned %.0f" % [
				pid, m.epoch(pid), derricks, refineries, relays,
				p.income_per_min if p != null else 0.0,
				p.earned_total if p != null else 0.0])
		print("t+%2d min   %s" % [minute + 1, "   |   ".join(row)])

	for pid in [0, 1]:
		var d: SimAiDirector = w.ai.get(pid)
		if d == null:
			continue
		print("AI %d: placed %d, refused %d, saving for %s (%.0f cr), income %.1f cr/s, advances %d"
			% [pid, d.structures_placed, d.structures_refused,
				d._growth_want_key if d._growth_want_key != "" else "nothing",
				d._growth_want_cost, d._income_ema, d.epoch_advances_requested])
		var tail: Array = d.decision_log.slice(maxi(0, d.decision_log.size() - 24))
		for line in tail:
			print("      " + String(line))


func _process(_d: float) -> bool:
	return true
