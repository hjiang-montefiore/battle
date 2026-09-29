extends SceneTree
## MEASUREMENT ONLY -- changes nothing. Runs a peer match on skirmish_valley
## with both sides on autopilot and reports, per 60 simulated seconds:
##   * each director's posture, groups, group objective, and the point
##     _manoeuvre() ACTUALLY sends the group to after the standoff subtraction
##   * how many own units have ever been given a destination, and how far that
##     destination is from that AI's own home
##   * the furthest any own unit has actually got from its own home
##   * closest approach between the two armies (harness ground truth, the AI
##     never sees this)
##   * memory: live / remembered / peak
##
##   Godot --headless --path game --script res://sim/tests/probe_ai_search.gd

var _code := 1

func _initialize() -> void:
	var minutes := 12
	var setup := SimMatchSetup.scenario("peer")
	var m := SimMatch.start(setup, SimArena.SKIRMISH_VALLEY, true)
	var w: SimWorld = m.world
	var e: SimEntities = w.entities

	print("MOTION_TEMPO = %.2f   SENSOR_HZ = %.2f" % [SimTypes.MOTION_TEMPO, SimWorld.SENSOR_HZ])
	print("arena %s  %.0f x %.0f m" % [m.arena_key,
		m.terrain.extent_x_m(), m.terrain.extent_z_m()])
	for pid in range(setup.players.size()):
		var b := m.base_position(pid)
		print("  player %d base (%.0f, %.0f)  |base| = %.0f m" % [pid, b.x, b.y, b.length()])
	var b0 := m.base_position(0)
	var b1 := m.base_position(1)
	print("  base separation %.0f m" % b0.distance_to(b1))

	# One-off static report of what each director thinks it can reach, because
	# the standoff in _manoeuvre() is a function of exactly this.
	for pid in w.ai.keys():
		var d: SimAiDirector = w.ai[pid]
		if d == null:
			continue
		d.step(0.0001)   # let it build groups without advancing anything
	print("")

	var furthest_ever := {0: 0.0, 1: 0.0}
	var ever_ordered := {0: {}, 1: {}}

	for pass_i in range(minutes):
		m.run_ticks(int(60.0 * SimWorld.SIM_HZ))
		var t := (pass_i + 1) * 60
		print("── t+%ds ─────────────────────────────────────────────" % t)
		# ground truth, harness only
		var closest := 1e12
		for i in range(e.count()):
			if not e.is_alive(i) or e.faction[i] != 0:
				continue
			for j in range(e.count()):
				if not e.is_alive(j) or e.faction[j] == 0:
					continue
				var d2: float = pow(e.pos_x[i] - e.pos_x[j], 2) + pow(e.pos_z[i] - e.pos_z[j], 2)
				closest = minf(closest, d2)
		var shots := w.munitions.launched if w.munitions != null else -1
		var kills := w.damage.kills if w.damage != null else -1
		print("   closest approach %.0f m   shots %d   kills %d" % [sqrt(closest), shots, kills])

		for pid in [0, 1]:
			var d: SimAiDirector = w.ai.get(pid)
			if d == null:
				continue
			var own := m.own_units(pid)
			var hx: float = d.home_x
			var hz: float = d.home_z
			# how far has anything actually got from its own home
			var far := 0.0
			var moving := 0
			for i in own:
				if not e.is_alive(i):
					continue
				var dist := sqrt(pow(e.pos_x[i] - hx, 2) + pow(e.pos_z[i] - hz, 2))
				far = maxf(far, dist)
				if sqrt(e.vel_x[i] * e.vel_x[i] + e.vel_z[i] * e.vel_z[i]) > 0.5:
					moving += 1
			furthest_ever[pid] = maxf(furthest_ever[pid], far)

			# what destinations has it ever handed out, and how far from home
			var lm: Dictionary = d._last_move
			var dest_far := 0.0
			var dest_beyond := 0    # destinations FURTHER from map centre than home
			for u in lm.keys():
				ever_ordered[pid][u] = true
				var row: Array = lm[u]
				var dd := sqrt(pow(float(row[0]) - hx, 2) + pow(float(row[1]) - hz, 2))
				dest_far = maxf(dest_far, dd)
				var r_home := sqrt(hx * hx + hz * hz)
				var r_dest := sqrt(float(row[0]) * float(row[0]) + float(row[1]) * float(row[1]))
				if r_dest > r_home + 50.0:
					dest_beyond += 1

			print("   AI %d  %-8s  %s / %s  home (%.0f, %.0f)" % [pid,
				SimAiDirector.POSTURE_NAMES.get(d.posture, "?"),
				SimSkill.name_of(d.skill), SimDoctrine.name_of(d.doctrine.profile),
				hx, hz])
			print("        units %d alive, %d moving; furthest from home now %.0f m (ever %.0f m)"
				% [own.size(), moving, far, furthest_ever[pid]])
			print("        ordered somewhere: %d of %d units; furthest destination %.0f m from home; %d destinations further from map centre than home"
				% [ever_ordered[pid].size(), own.size(), dest_far, dest_beyond])
			print("        memory live %d / remembered %d / peak %d   orders: %d move %d attack %d prod"
				% [d.memory.live_count(), d.memory.count(), d._peak_live_tracks,
					d.orders_moved, d.orders_attacked, d.orders_production])
			print("        %s   %d remembered fixed position(s)"
				% [d.search.describe(), d._sites.size()])
			for g in d.groups:
				var grp: SimAiGroup = g
				var line := "        " + grp.describe()
				if grp.role == SimAiGroup.Role.MAIN:
					var reach: float = d._group_reach_m(grp)
					var gx: float = grp.obj_x
					var gz: float = grp.obj_z
					var sent_x := gx
					var sent_z := gz
					var c: PackedFloat32Array = d._group_centre(grp)
					# Mirrors _manoeuvre(): a standoff applies only to a LIVE
					# CONTACT, is measured back from the group rather than from
					# home, and can never eat more than half the distance still
					# to cover. Reading this off the old rule was what made the
					# instrument agree with the bug.
					if grp.objective_track >= 0 \
							and grp.state != SimAiGroup.State.WITHDRAWING \
							and d.posture != SimAiDirector.Posture.ATTACK:
						var dx: float = gx - c[0]
						var dz: float = gz - c[1]
						var to_go: float = sqrt(dx * dx + dz * dz)
						if to_go > 1.0:
							var so: float = minf(
								reach * SimAiDirector.STANDOFF_FRACTION,
								to_go * SimAiDirector.STANDOFF_MAX_SHARE)
							sent_x = gx - dx / to_go * so
							sent_z = gz - dz / to_go * so
							line += "  | reach %.0f m standoff %.0f m -> SENT TO (%.0f, %.0f)" % [
								reach, so, sent_x, sent_z]
					else:
						line += "  | SENT TO (%.0f, %.0f)" % [sent_x, sent_z]
					line += "  centre (%.0f, %.0f) r=%.0f" % [c[0], c[1],
						sqrt(c[0] * c[0] + c[1] * c[1])]
				print(line)
		if m.is_finished():
			print("FINISHED at t+%ds -- %s" % [t, m.headline()])
			break

	print("")
	for pid in [0, 1]:
		var dd: SimAiDirector = w.ai.get(pid)
		if dd == null:
			print("=== AI %d eliminated, no log ===" % pid)
			continue
		print("=== decision log, AI %d (last 30) ===" % pid)
		var dl: Array = dd.decision_log
		for i in range(maxi(0, dl.size() - 30), dl.size()):
			print("  " + str(dl[i]))
	_code = 0


func _process(_d: float) -> bool:
	quit(_code)
	return true
