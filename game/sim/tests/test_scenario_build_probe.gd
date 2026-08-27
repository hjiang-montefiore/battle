extends SceneTree
## Diagnosis probe: does the AI ever successfully BUILD a structure?
##
##   Godot --headless --path game --script sim/tests/test_scenario_build_probe.gd
##
## Suspicion from reading sim_ai_director.gd: _build_site() offers candidate
## sites on a ring starting at 600 m from home, but the largest build radius
## in the roster is the HQ's 340 m -- so SimEconomy.placement_problem should
## refuse EVERY AI structure build as "outside your build radius", in every
## scenario. This probe runs peer on skirmish_valley for 180 sim s and counts
## structures per player, command executed/rejected totals, and the economy's
## own refusal log. Read-only with respect to ai/: it changes nothing.

var _exit := 1


func _initialize() -> void:
	var setup := SimMatchSetup.scenario("peer")
	var m := SimMatch.start(setup, "skirmish_valley", true)
	if not m.problems().is_empty():
		print("START_FAIL: ", "; ".join(m.problems()))
		return
	var structures_at_start := _structures_per_player(m, setup.players.size())
	print("structures at start: ", structures_at_start)
	while m.elapsed_s() < 180.0 and not m.is_finished():
		m.run_ticks(200)
	print("t=%.0f  commands executed %d  rejected %d" % [m.elapsed_s(),
		m.world.commands.executed, m.world.commands.rejected])
	print("structures at t=180: ", _structures_per_player(m, setup.players.size()))
	var refusals := {}
	for e in m.world.economy.events:
		var line := String(e)
		if "refused" in line:
			# Fold coordinates out so identical mechanisms group.
			var key := line.get_slice(" -- ", 1) if " -- " in line else line
			refusals[key] = int(refusals.get(key, 0)) + 1
	print("economy refusal log (grouped): ", refusals)
	_exit = 0


func _structures_per_player(m: SimMatch, n_players: int) -> Array:
	var out := []
	for pid in range(n_players):
		var c := 0
		for i in m.own_units(pid):
			if m.world.entities.is_structure[i] == 1:
				c += 1
		out.append(c)
	return out


func _process(_d: float) -> bool:
	quit(_exit)
	return true
