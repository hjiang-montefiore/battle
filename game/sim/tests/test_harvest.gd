extends SceneTree
## The ore cycle, end to end: find ore, fill up, drive it home, get paid.
##
## Asked during play: "we need ore and ore miner as well right". Yes -- and the
## reason is not the money. Oil derricks already make money, safely, forever.
## Ore money has to be DRIVEN, which is what makes a harvester a target and
## raiding an economy a real operation instead of a euphemism for attacking.

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("\n  BATTLE -- the ore cycle")
	print("  " + "-".repeat(58))
	_suite_cycle()
	_suite_depletion()
	_suite_rules()
	print("  " + "-".repeat(58))
	print("  %d passed, %d FAILED\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _world() -> SimWorld:
	var w := SimWorld.new(11)
	w.use_accumulator = false
	var flat := SimTerrain.new(64, 64, 50.0, "flat")
	flat.fill(20.0)
	w.terrain = flat
	w.movement.set_terrain(flat)
	SimHarvest.install(w)
	w.economy.add_player(0, 20000.0, 4, 5)
	return w


## A refinery at the origin, ore 600 m east, one miner parked at the refinery.
func _rig(w: SimWorld) -> int:
	w.economy.spawn_unit(0, "refinery", 0.0, 0.0)
	w.economy.add_ore_field(600.0, 0.0, 9000.0)
	return w.economy.spawn_unit(0, "ore_miner", 40.0, 0.0)


func _suite_cycle() -> void:
	var w := _world()
	var m := _rig(w)
	_ok("a miner exists and the layer claims it", m >= 0 and w.harvest_system.is_harvester(m))
	_ok("a tank is not a harvester",
		not w.harvest_system.is_harvester(w.economy.spawn_unit(0, "mbt", -60.0, 60.0)))

	# It should need no orders at all. That is the whole point of the unit.
	w.run_ticks(60)
	_ok("it sets off on its own, unordered",
		w.entities.speed_ms[m] > 0.1 or w.harvest_system.state_name(m) == "mining",
		w.harvest_system.state_name(m))

	var before: float = w.economy.credits(0)
	var ore_before: float = w.economy.ore_remaining[0]
	# 4 minutes is comfortably a full round trip at 46 km/h over 600 m.
	w.run_ticks(4800)
	_ok("ore came out of the ground", w.economy.ore_remaining[0] < ore_before,
		"%.0f -> %.0f" % [ore_before, w.economy.ore_remaining[0]])
	_ok("at least one full load was delivered",
		w.harvest_system.loads_delivered >= 1,
		"%d load(s), %.0f cr" % [w.harvest_system.loads_delivered,
			w.harvest_system.credits_delivered])
	_ok("and the player was actually paid", w.economy.credits(0) > before,
		"+%.0f cr" % (w.economy.credits(0) - before))
	# Conservation: what left the ground must equal what was banked plus what
	# is still riding on the miner. A cycle that minted credits would be worse
	# than one that lost them.
	var mined: float = ore_before - w.economy.ore_remaining[0]
	var accounted: float = w.harvest_system.credits_delivered + w.entities.harvest_load[m]
	_ok("nothing is minted or lost in transit", absf(mined - accounted) < 1.0,
		"mined %.1f, banked+aboard %.1f" % [mined, accounted])


func _suite_depletion() -> void:
	var w := _world()
	w.economy.spawn_unit(0, "refinery", 0.0, 0.0)
	w.economy.add_ore_field(400.0, 0.0, 800.0)   # less than one full load
	var m := w.economy.spawn_unit(0, "ore_miner", 40.0, 0.0)
	w.run_ticks(6000)
	_ok("a small field is worked until it is empty",
		w.economy.ore_remaining[0] <= 0.01, "%.1f left" % w.economy.ore_remaining[0])
	_ok("and the last partial load is still banked",
		w.harvest_system.credits_delivered > 700.0,
		"%.0f cr delivered" % w.harvest_system.credits_delivered)
	_ok("the miner does not sit in an empty field forever",
		w.harvest_system.state_name(m) != "mining", w.harvest_system.state_name(m))


func _suite_rules() -> void:
	# No refinery: the load is HELD, not dumped. A player who just lost their
	# refinery gets their ore when they rebuild.
	var w := _world()
	w.economy.add_ore_field(300.0, 0.0, 9000.0)
	var m := w.economy.spawn_unit(0, "ore_miner", 40.0, 0.0)
	w.run_ticks(3000)
	_ok("with nowhere to unload it fills up and waits",
		w.entities.harvest_load[m] > 0.0 and w.harvest_system.loads_delivered == 0,
		"%.0f aboard" % w.entities.harvest_load[m])

	# Build the refinery late; the held load must arrive.
	w.economy.spawn_unit(0, "refinery", 0.0, 0.0)
	w.run_ticks(2400)
	_ok("and delivers once a refinery exists", w.harvest_system.loads_delivered >= 1,
		"%d load(s)" % w.harvest_system.loads_delivered)

	# A player order must win: a harvester told to run does so.
	var w2 := _world()
	var m2 := _rig(w2)
	w2.run_ticks(600)
	w2.harvest_system.interrupt(m2)
	w2.movement.order_move(m2, -900.0, -900.0)
	# 1600 ticks is 80 s; the drive is about 1.5 km at 46 km/h. The first
	# version allowed 20 s and failed on a unit that was obeying perfectly --
	# the assertion was measuring the clock, not the behaviour.
	w2.run_ticks(1600)
	_ok("a manual order takes it off the ore line",
		w2.entities.pos_x[m2] < 0.0, "x=%.0f" % w2.entities.pos_x[m2])
	# And it goes back to work once the errand is done, rather than needing to
	# be re-adopted.
	w2.run_ticks(3000)
	_ok("then returns to the cycle unprompted",
		w2.harvest_system.state_name(m2) != "seeking"
			or w2.entities.harvest_load[m2] > 0.0,
		w2.harvest_system.state_name(m2))


func _ok(what: String, cond: bool, note := "") -> void:
	if cond:
		_pass += 1
		print("    PASS  %s%s" % [what, "  " + note if note != "" else ""])
	else:
		_fail += 1
		print("    FAIL  %s  %s" % [what, note])


func _process(_d: float) -> bool:
	return true
