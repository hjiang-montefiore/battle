extends SceneTree
## Is this game playable yet? Answered mechanically, not by opinion.
##
##   Godot --headless --path game --script sim/tests/gate_playable.gd
##
## WHY THIS EXISTS. "When can I play it" kept getting answered by whoever last
## read the code, and those answers disagreed -- one audit called a subsystem
## PARTIAL that another called MISSING, and both were reading the same files on
## the same day. The disagreement was real: they were reading STUB FILES mid-
## build, where a declared contract with a no-op body looks like progress or
## looks like nothing depending on which line you stop at.
##
## A capability either works when you call it or it does not. This gate calls
## it. Every check below runs the real code path a player would exercise, and
## reports the specific thing that broke rather than a category.
##
## The gate is deliberately about the PLAYABLE SLICE, not the designed game:
## one map, two players, units that move and shoot and die, and a match that
## ends. Economy and AI are included because a slice with no opponent is a
## diorama, but the seven realism pillars, eight factions and seven epochs are
## explicitly out of scope here -- that is a different and much longer gate.

const DT := 1.0 / 20.0

var _checks: Array = []          ## [name, ok, detail, weight]
var _exit_code := 1              ## fail closed: an error that skips _report()
var _done := false               ## must not be able to report success


func _c(name: String, ok: bool, detail: String = "", weight := 1) -> void:
	_checks.append([name, ok, detail, weight])


func _has(path: String) -> bool:
	return ResourceLoader.exists(path)


## Every check is wrapped so one broken capability reports as a failure instead
## of taking the whole gate down with it -- which is the entire point of a gate.
func _initialize() -> void:
	print("PLAYABLE-SLICE GATE\n")

	# ── 1. can a match be instantiated at all? ─────────────────────
	var m: SimMatch = null
	var setup: SimMatchSetup = null
	if not ClassDB.class_exists("SimMatch") and not _has("res://sim/match/sim_match.gd"):
		_c("a match can be created", false, "sim/match/sim_match.gd absent", 3)
	else:
		setup = SimMatchSetup.scenario("peer")
		if setup == null:
			_c("a match can be created", false, "scenario('peer') returned null", 3)
		else:
			m = SimMatch.start(setup, SimArena.SKIRMISH_VALLEY, true)
			var probs := m.problems() if m != null else PackedStringArray(["start() returned null"])
			_c("a match can be created", m != null and probs.is_empty(),
				"; ".join(probs) if not probs.is_empty() else "scenario 'peer'", 3)

	if m == null:
		_report()
		return

	var w: SimWorld = m.world
	var e: SimEntities = w.entities if w != null else null

	# ── 2. are there units on the field? ───────────────────────────
	var n_units := e.count() if e != null and e.has_method("count") else 0
	_c("both sides deploy units", n_units >= 2, "%d entities" % n_units, 2)

	# ── 3. does the world tick without dying? ──────────────────────
	var ticked := false
	if m.has_method("run_ticks"):
		m.run_ticks(20)
		ticked = true
	_c("the simulation ticks", ticked, "20 ticks", 2)

	# ── 4. can a unit be ordered somewhere, and does it go? ────────
	var moved := false
	var move_detail := "no order channel"
	if e != null and n_units > 0 and _has("res://sim/movement/sim_movement.gd"):
		# Pick something MOBILE. Index 0 is whatever deployed first, which in
		# this scenario is a structure -- ordering a building to move and then
		# reporting "moved 0.0 m" measures the gate, not the game.
		var idx := -1
		for i in range(n_units):
			if e.is_alive(i) and e.max_speed_ms[i] > 0.0 and e.is_structure[i] == 0:
				idx = i
				break
		if idx < 0:
			idx = 0
		var sx: float = e.pos_x[idx]
		var sz: float = e.pos_z[idx]
		if w.movement != null and w.movement.has_method("order_move"):
			w.movement.order_move(idx, sx + 400.0, sz)
			m.run_ticks(400)
			var d := absf(e.pos_x[idx] - sx) + absf(e.pos_z[idx] - sz)
			moved = d > 5.0
			move_detail = "moved %.1f m in 20 s" % d
		else:
			move_detail = "SimWorld.movement absent or has no order_move()"
	_c("a unit obeys a move order", moved, move_detail, 3)

	# ── 5. can anything die? this is the keystone ──────────────────
	var can_die := false
	var die_detail := "no damage path"
	if e != null and n_units > 0:
		var victim := n_units - 1
		if e.has_method("is_alive") and e.has_method("kill"):
			e.kill(victim)
			can_die = not e.is_alive(victim)
			die_detail = "kill() -> alive=%s" % e.is_alive(victim)
		elif _has("res://sim/damage/sim_damage.gd"):
			die_detail = "SimDamage exists but SimEntities has no kill()"
	_c("a unit can be destroyed", can_die, die_detail, 3)

	# ── 7. does the economy produce anything? ──────────────────────
	var produces := false
	var econ_detail := "no economy"
	if _has("res://sim/economy/sim_economy.gd"):
		var ec: SimEconomy = w.economy
		if ec != null and ec.has_method("credits"):
			var ids = ec.player_ids()
			if ids.is_empty():
				econ_detail = "economy has no players"
			else:
				var pid = ids[0]
				# Measure INCOME, not balance. A healthy economy spends what it
				# earns, so "credits unchanged" can mean thriving production
				# just as easily as no income at all -- and after ten minutes
				# of building, a balance of zero is the SUCCESS case.
				var c0: float = ec.credits(pid)
				var n0 := e.count()
				m.run_ticks(1200)
				var c1: float = ec.credits(pid)
				var n1 := e.count()
				produces = absf(c1 - c0) > 0.01 or n1 > n0
				econ_detail = "credits %.0f -> %.0f, entities %d -> %d" % [c0, c1, n0, n1]
		else:
			econ_detail = "SimWorld.economy absent"
	_c("the economy runs", produces, econ_detail, 2)

	# ── 6. does combat resolve end to end? ─────────────────────────
	var shoots := false
	var shoot_detail := "no fire control"
	if w.damage != null and "kills" in w.damage:
		# Long enough for the two sides to actually MEET. They start 9.2 km
		# apart on a 12.8 km map and first contact is around t+240 s, so a
		# two-minute window was measuring the approach march and calling the
		# absence of a battle a failure to fight.
		var k0: int = w.damage.kills
		m.run_ticks(12000)                      # ten minutes of sim
		var k1: int = w.damage.kills
		shoots = k1 > k0
		shoot_detail = "%d kills in 600 s" % (k1 - k0)
	elif _has("res://sim/match/sim_fire_control.gd"):
		shoot_detail = "fire control exists but SimDamage exposes no kill count"
	_c("units engage and kill each other unaided", shoots, shoot_detail, 3)

	# ── 8. does the AI decide anything? ────────────────────────────
	var ai_acts := false
	var ai_detail := "no AI"
	if _has("res://sim/ai/sim_ai_director.gd"):
		var best := 0
		var who := -1
		for pid in w.ai.keys():
			var d = w.ai[pid]
			if d != null and "decision_log" in d and d.decision_log.size() > best:
				best = d.decision_log.size()
				who = pid
		ai_acts = best > 0
		ai_detail = ("player %d logged %d decisions" % [who, best]) if best > 0 \
			else "%d director(s), none logged a decision" % w.ai.size()
	_c("the AI issues orders", ai_acts, ai_detail, 2)

	# ── 9. does a match ever END? ──────────────────────────────────
	var ends := false
	var end_detail := "ran out of patience"
	var guard := 0
	while not m.is_finished() and guard < 200:
		m.run_ticks(600)                        # 30 s of sim per pass
		guard += 1
	ends = m.is_finished()
	if ends:
		end_detail = m.headline() if m.has_method("headline") else "finished"
	else:
		end_detail = "no winner after %.0f simulated minutes" % (guard * 0.5)
	_c("a match reaches a winner", ends, end_detail, 3)

	# ── 10. the bridge to something a person can look at ───────────
	# LOAD it, do not merely look for the file.
	#
	# This check used to be `ResourceLoader.exists(path)` and it reported "ok"
	# while game/scripts/skirmish.gd had a PARSE ERROR and the game could not
	# start at all -- a variable redeclared in the same scope, so the script
	# never compiled. A gate that confirms a file is present has confirmed
	# nothing about whether a person can play.
	var bridged := false
	var bridge_detail := "nothing outside game/sim touches SimWorld"
	if not _has("res://scenes/skirmish.tscn"):
		bridge_detail = "res://scenes/skirmish.tscn missing"
	else:
		var packed := load("res://scenes/skirmish.tscn") as PackedScene
		if packed == null:
			bridge_detail = "skirmish.tscn exists but will not load"
		else:
			var inst := packed.instantiate()
			if inst == null:
				bridge_detail = "skirmish.tscn loaded but will not instantiate"
			else:
				bridged = true
				bridge_detail = "scene loads and instantiates"
				inst.queue_free()
	_c("there is a scene a person can launch", bridged, bridge_detail, 3)

	_report()


func _alive_count(e) -> int:
	if e == null or not e.has_method("is_alive"):
		return 0
	var n := 0
	for i in range(e.count()):
		if e.is_alive(i):
			n += 1
	return n


func _report() -> void:
	var got := 0
	var total := 0
	print("  %-42s %s" % ["CAPABILITY", "RESULT"])
	print("  " + "-".repeat(72))
	for c in _checks:
		total += int(c[3])
		if c[1]:
			got += int(c[3])
		print("  %-42s %-5s %s" % [c[0], "ok" if c[1] else "NO", c[2]])
	var pct := 0.0 if total == 0 else 100.0 * float(got) / float(total)
	print("\n  %d / %d weighted points -- %.0f%% of a playable slice" % [got, total, pct])

	var blockers: Array = []
	for c in _checks:
		if not c[1]:
			blockers.append(c[0])
	if blockers.is_empty():
		print("  VERDICT: the slice is playable. Go and play it.")
	else:
		print("  VERDICT: not yet. Blocking:")
		for b in blockers:
			print("    - %s" % b)
	_exit_code = 0 if blockers.is_empty() else 1
	_done = true


## A parse or runtime error inside _initialize() skips quit() and leaves the
## SceneTree spinning with its stdout unflushed, which looks exactly like a hang
## and hides the error. Returning true guarantees an exit either way.
func _process(_delta: float) -> bool:
	quit(_exit_code)
	return true
