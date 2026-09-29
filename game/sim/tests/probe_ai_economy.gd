extends SceneTree
## MEASUREMENT ONLY. What does the AI's economy actually do in the first six
## minutes -- what it builds, what it produces, what it refuses, and how much
## money piles up unspent.
##
##   Godot --headless --path game --script res://sim/tests/probe_ai_economy.gd

var _code := 1

func _initialize() -> void:
	var setup := SimMatchSetup.scenario("peer")
	var m := SimMatch.start(setup, SimArena.SKIRMISH_VALLEY, true)
	var w: SimWorld = m.world
	var e: SimEntities = w.entities
	print("MOTION_TEMPO = %.2f" % SimTypes.MOTION_TEMPO)

	# What does the build order want, and where would the AI put it?
	for pid in [0, 1]:
		var d: SimAiDirector = w.ai[pid]
		print("AI %d build order: %s" % [pid,
			", ".join(SimAiPlan.base_build_order(d.doctrine))])

	for pass_i in range(6):
		m.run_ticks(int(60.0 * SimWorld.SIM_HZ))
		print("── t+%ds ──────────────────────────────" % ((pass_i + 1) * 60))
		for pid in [0, 1]:
			var d: SimAiDirector = w.ai.get(pid)
			if d == null:
				continue
			var names := {}
			var mobile := {}
			for i in m.own_units(pid):
				if not e.is_alive(i):
					continue
				if e.is_structure[i] == 1:
					names[e.names[i]] = int(names.get(e.names[i], 0)) + 1
				else:
					mobile[e.names[i]] = int(mobile.get(e.names[i], 0)) + 1
			var sn: Array = names.keys(); sn.sort()
			var mn: Array = mobile.keys(); mn.sort()
			var sline := PackedStringArray()
			for k in sn:
				sline.append("%s x%d" % [k, names[k]])
			var mline := PackedStringArray()
			for k in mn:
				mline.append("%s x%d" % [k, mobile[k]])
			print("   AI %d  %.0f credits  epoch %d  queue %d" % [pid,
				m.credits(pid), m.epoch(pid), w.economy.queue_of(pid).size()])
			print("        structures: " + ", ".join(sline))
			print("        units:      " + ", ".join(mline))

	# WHERE WOULD THE NEXT ONE GO, and would the engine take it? The probe is
	# allowed to ask placement_problem() because the probe is not the AI --
	# that call reads every structure on the map and the director must never
	# touch it.
	print("")
	for pid in [0, 1]:
		var d: SimAiDirector = w.ai.get(pid)
		if d == null:
			continue
		print("AI %d  %s" % [pid, d.describe().split("\n")[0]])
		print("   placed %d, refused %d, budget %.0f, income %.1f cr/s, saving for %s (%.0f cr)"
			% [d.structures_placed, d.structures_refused, d._growth_budget,
				d._income_ema,
				d._growth_want_key if d._growth_want_key != "" else "nothing",
				d._growth_want_cost])
		print("   power %.0f supplied / %.0f drawn" % [
			d.view.own_power_supply(), d.view.own_power_draw()])
		var want: Array = d._next_structure(_own_roles(d))
		if want.is_empty():
			print("   nothing wanted")
			continue
		var bdef: SimUnitDef = d.view.def_for(String(want[0]))
		var site: PackedFloat32Array = d._build_site(bdef)
		if site.size() < 2:
			print("   %s -- NO LEGAL SITE" % want[0])
			continue
		var reason: String = w.economy.placement_problem(
			pid, bdef, site[0], site[1])
		print("   %s at (%.0f, %.0f)  %.0f m from home  -> %s" % [
			want[0], site[0], site[1],
			sqrt(pow(site[0] - d.home_x, 2.0) + pow(site[1] - d.home_z, 2.0)),
			reason if reason != "" else "ALLOWED"])

	print("")
	for pid in [0, 1]:
		var d: SimAiDirector = w.ai.get(pid)
		if d == null:
			continue
		print("=== AI %d decision log (all) ===" % pid)
		for l in d.decision_log:
			print("  " + str(l))
	_code = 0


func _process(_d: float) -> bool:
	quit(_code)
	return true


## The AI's own role census, the same one _economy() takes.
func _own_roles(d: SimAiDirector) -> Dictionary:
	var out := {}
	for i in d.view.forces.indices():
		if not d.view.forces.is_structure(i):
			continue
		var sd := d.view.own_def(i)
		if sd != null:
			out[sd.role] = int(out.get(sd.role, 0)) + 1
	return out
