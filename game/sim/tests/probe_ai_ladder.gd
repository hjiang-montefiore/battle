extends SceneTree
## MEASUREMENT ONLY -- changes nothing. Does the difficulty ladder still bite?
##
## An AI that has been made eager is worth nothing if it is equally eager at
## every rung: that is one difficulty with eight labels on it. This runs the
## same mirrored match at several skill pairings, both seats each way so the
## seat is not what decides it, and reports who was left standing.
##
##   Godot --headless --path game --script res://sim/tests/probe_ai_ladder.gd

var _code := 1

const PAIRINGS := [
	[SimSkill.Level.RECRUIT, SimSkill.Level.ELITE],
	[SimSkill.Level.RECRUIT, SimSkill.Level.VETERAN],
	[SimSkill.Level.VETERAN, SimSkill.Level.WARLORD],
	[SimSkill.Level.VETERAN, SimSkill.Level.VETERAN],
]


func _initialize() -> void:
	print("")
	print("  SKILL LADDER -- mirrored match, both seats, 8 simulated minutes")
	print("  " + "-".repeat(72))
	var wins := {}
	for pair in PAIRINGS:
		for flip in [false, true]:
			var a: int = pair[1] if flip else pair[0]
			var b: int = pair[0] if flip else pair[1]
			var r := _run(a, b)
			var line := "  %-13s vs %-13s -> %s" % [
				SimSkill.name_of(a), SimSkill.name_of(b), r["headline"]]
			print(line)
			print("      p0 %2d units / %5.0f cr / %d kills   |   p1 %2d units / %5.0f cr / %d kills   at t+%ds"
				% [r["u0"], r["c0"], r["k0"], r["u1"], r["c1"], r["k1"], r["t"]])
			var key := "%s beat %s" % [
				SimSkill.name_of(a if r["winner"] == 0 else b),
				SimSkill.name_of(b if r["winner"] == 0 else a)]
			if r["winner"] >= 0:
				wins[key] = int(wins.get(key, 0)) + 1
	print("  " + "-".repeat(72))
	var keys: Array = wins.keys()
	keys.sort()
	for k in keys:
		print("  %s  x%d" % [k, wins[k]])
	print("")
	_code = 0


func _run(skill_0: int, skill_1: int) -> Dictionary:
	var setup := SimMatchSetup.new()
	setup.name = "Ladder"
	setup.add(SimPlayerSetup.new({"name": "P0", "team": 0,
		"faction": SimPlayerSetup.Faction.GERMANY,
		"start_epoch": 4, "ceiling_epoch": 6, "skill": skill_0,
		"doctrine": SimDoctrine.make(SimDoctrine.Profile.COMBINED_ARMS)}))
	setup.add(SimPlayerSetup.new({"name": "P1", "team": 1,
		"faction": SimPlayerSetup.Faction.RUSSIA,
		"start_epoch": 4, "ceiling_epoch": 6, "skill": skill_1,
		"doctrine": SimDoctrine.make(SimDoctrine.Profile.COMBINED_ARMS)}))
	var m := SimMatch.start(setup, SimArena.SKIRMISH_VALLEY, true)
	var w: SimWorld = m.world
	var t := 0
	for pass_i in range(16):
		m.run_ticks(int(30.0 * SimWorld.SIM_HZ))
		t += 30
		if m.is_finished():
			break
	var u := [0, 0]
	var k := [0, 0]
	for pid in [0, 1]:
		for i in m.own_units(pid):
			if w.entities.is_alive(i):
				u[pid] += 1
	# Kills are not attributed per player here; strength left standing is the
	# honest measure of who was winning when the clock ran out.
	var winner := -1
	if u[0] > u[1] * 2:
		winner = 0
	elif u[1] > u[0] * 2:
		winner = 1
	return {
		"headline": m.headline() if m.is_finished() else "undecided",
		"u0": u[0], "u1": u[1], "k0": k[0], "k1": k[1],
		"c0": m.credits(0), "c1": m.credits(1),
		"winner": winner, "t": t,
	}


func _process(_d: float) -> bool:
	quit(_code)
	return true
