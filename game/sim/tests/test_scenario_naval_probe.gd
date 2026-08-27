extends SceneTree
## Why does north_atlantic on coastal_shelf sit at 0 shots for 90 sim minutes?
## Start it, run 600 sim s, and dump what each side owns, can build, and does.
##
##   Godot --headless --path game --script sim/tests/test_scenario_naval_probe.gd

var _exit := 1


func _initialize() -> void:
	var setup := SimMatchSetup.scenario("north_atlantic")
	var m := SimMatch.start(setup, "coastal_shelf", true)
	var probs := m.problems()
	if not probs.is_empty():
		print("START_FAIL: ", "; ".join(probs))
		_exit = 0
		return
	for pid in range(setup.players.size()):
		var p: SimPlayerSetup = setup.players[pid]
		print("player %d %s: %d entities, credits %.0f, base %s" % [
			pid, p.name, m.own_units(pid).size(), m.credits(pid),
			str(m.base_position(pid))])
		print("  production structures: %d, buildable: %s" % [
			m.production_structures(pid).size(),
			str(m.buildable_structures(pid))])
	var marks := [60.0, 300.0, 600.0]
	var next := 0
	while m.elapsed_s() < 600.0 and not m.is_finished():
		m.run_ticks(200)
		if next < marks.size() and m.elapsed_s() >= float(marks[next]):
			print("t=%4.0f  shots %d  kills %d" % [m.elapsed_s(),
				m.world.weapons.shots_fired, m.world.damage.kills])
			for pid in range(setup.players.size()):
				print("  p%d units %d  credits %7.0f  buildable %s" % [pid,
					m.own_units(pid).size(), m.credits(pid),
					str(m.buildable_structures(pid))])
			next += 1
	_exit = 0


func _process(_d: float) -> bool:
	quit(_exit)
	return true
