extends SceneTree
## Why does a match never end? Watch one and report what actually happens.
##   Godot --headless --path game --script sim/tests/diag_match.gd

var _code := 1

func _initialize() -> void:
	var setup := SimMatchSetup.scenario("peer")
	var m := SimMatch.start(setup, SimArena.SKIRMISH_VALLEY, true)
	var w: SimWorld = m.world
	var e: SimEntities = w.entities
	print("match: %d entities, arena %s" % [e.count(), m.arena_key])

	# where are the two sides, and how far apart?
	var by_faction := {}
	for i in range(e.count()):
		var f: int = e.faction[i]
		if not by_faction.has(f):
			by_faction[f] = []
		by_faction[f].append(i)
	for f in by_faction.keys():
		var ids = by_faction[f]
		var cx := 0.0
		var cz := 0.0
		for i in ids:
			cx += e.pos_x[i]; cz += e.pos_z[i]
		cx /= ids.size(); cz /= ids.size()
		print("  faction %s: %d units, centroid (%.0f, %.0f)" % [f, ids.size(), cx, cz])
	var fs = by_faction.keys()
	if fs.size() >= 2:
		var a = by_faction[fs[0]][0]
		var b = by_faction[fs[1]][0]
		var sep := sqrt(pow(e.pos_x[a] - e.pos_x[b], 2) + pow(e.pos_z[a] - e.pos_z[b], 2))
		print("  separation between first units: %.0f m" % sep)

	print("\n  t      alive  kills  moving  orders  ai_dec  finished")
	var t := 0.0
	for pass_i in range(14):
		m.run_ticks(1200)                     # 60 s per pass -> 30 min total
		t += 60.0
		if m.is_finished():
			print("  FINISHED at t+%.0fs" % t)
			break
		var alive := 0
		var moving := 0
		var orders := 0
		for i in range(e.count()):
			if not e.is_alive(i):
				continue
			alive += 1
			var sp := sqrt(e.vel_x[i] * e.vel_x[i] + e.vel_z[i] * e.vel_z[i])
			if sp > 0.5:
				moving += 1
			if w.movement != null and w.movement.has_method("order_count"):
				orders += w.movement.order_count(i)
		var kills: int = w.damage.kills if w.damage != null and "kills" in w.damage else -1
		var shot := 0
		var term := 0
		if w.munitions != null:
			shot = w.munitions.launched
			term = w.munitions.terminated
		var dec := 0
		var post := ""
		var live := ""
		for pid in w.ai.keys():
			var d = w.ai[pid]
			if d == null:
				continue
			if "decision_log" in d:
				dec += d.decision_log.size()
			if "posture" in d:
				post += "%s " % d.POSTURE_NAMES.get(d.posture, "?")
			if "memory" in d and d.memory != null:
				live += "%d/%d " % [d.memory.live_count(), d.memory.count()]
		# closest approach between the two sides tells us whether contact ever
		# happens at all -- the whole question is "never meet" vs "meet but
		# nothing decisive"
		var closest := 1e12
		for i in range(e.count()):
			if not e.is_alive(i) or e.faction[i] != 0:
				continue
			for j in range(e.count()):
				if not e.is_alive(j) or e.faction[j] == 0:
					continue
				var d2: float = pow(e.pos_x[i] - e.pos_x[j], 2) + pow(e.pos_z[i] - e.pos_z[j], 2)
				if d2 < closest:
					closest = d2
		print("  %5.0fs alive %3d  kills %3d  shots %4d  closest %6.0f m  posture %-14s"
			% [t, alive, kills, shot, sqrt(closest), post])

	if w.munitions != null:
		print("\n  munitions: %d launched, %d terminated" % [w.munitions.launched, w.munitions.terminated])
		var tail = w.munitions.combat_log
		for i in range(maxi(0, tail.size() - 12), tail.size()):
			print("    " + str(tail[i]))
	print("\n  victory view:")
	if m.victory != null and m.victory.has_method("describe"):
		print("    " + str(m.victory.describe()).replace("\n", "\n    "))
	for pid in m.victory.player_ids():
		var s = m.victory.standing(pid)
		print("    player %s: %s" % [pid, s.describe() if s != null and s.has_method("describe") else s])
	_code = 0

func _process(_d: float) -> bool:
	quit(_code)
	return true
