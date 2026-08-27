extends SceneTree
## REPAIR and SELL: the two things Red Alert lets you do to a building you own.
## Both go through the command queue like every other order, so the AI could
## use them and a replay reproduces them.

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("\n  BATTLE -- sell and repair")
	print("  " + "-".repeat(58))
	_suite_sell()
	_suite_repair()
	_suite_refusals()
	print("  " + "-".repeat(58))
	print("  %d passed, %d FAILED\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _world() -> SimWorld:
	var w := SimWorld.new(7)
	w.use_accumulator = false
	w.economy.add_player(0, 5000.0, 4, 5)
	w.economy.add_player(1, 5000.0, 4, 5)
	return w


func _plant(w: SimWorld, owner_id: int) -> int:
	return w.economy.spawn_unit(owner_id, "power_plant", 100.0 * float(owner_id), 0.0)


func _suite_sell() -> void:
	var w := _world()
	var u := _plant(w, 0)
	var cost: float = w.economy.def_of(u).cost
	var before: float = w.economy.credits(0)
	w.commands.sell(0, u)
	w.run_ticks(1)
	_ok("an intact structure sells for half its cost",
		absf((w.economy.credits(0) - before) - cost * SimEconomy.SELL_REFUND) < 0.5,
		"+%.0f cr on a %.0f cr building" % [w.economy.credits(0) - before, cost])
	_ok("and it is gone from the map", w.entities.alive[u] == 0)

	# A burning wreck must not sell for the price of an intact building, or
	# damage would cost the defender nothing.
	var w2 := _world()
	var u2 := _plant(w2, 0)
	w2.entities.structure[u2] = w2.entities.structure_max[u2] * 0.25
	var before2: float = w2.economy.credits(0)
	w2.commands.sell(0, u2)
	w2.run_ticks(1)
	var got: float = w2.economy.credits(0) - before2
	_ok("a quarter-standing wreck sells for a quarter as much",
		absf(got - cost * SimEconomy.SELL_REFUND * 0.25) < 0.5, "+%.0f cr" % got)


func _suite_repair() -> void:
	var w := _world()
	var u := _plant(w, 0)
	var whole: float = w.entities.structure_max[u]
	var cost: float = w.economy.def_of(u).cost
	w.entities.structure[u] = whole * 0.5
	var before: float = w.economy.credits(0)
	w.commands.repair(0, u)
	w.run_ticks(1)
	_ok("repair restores the structure to full",
		absf(w.entities.structure[u] - whole) < 0.01,
		"%.0f / %.0f" % [w.entities.structure[u], whole])
	var paid: float = before - w.economy.credits(0)
	_ok("and charges for the damage actually made good",
		absf(paid - cost * SimEconomy.REPAIR_COST * 0.5) < 0.5, "%.0f cr" % paid)

	# Topping up a scratch costs a scratch.
	var w2 := _world()
	var u2 := _plant(w2, 0)
	w2.entities.structure[u2] = w2.entities.structure_max[u2] * 0.95
	var before2: float = w2.economy.credits(0)
	w2.commands.repair(0, u2)
	w2.run_ticks(1)
	var paid2: float = before2 - w2.economy.credits(0)
	_ok("a scratch costs a twentieth of a wreck",
		paid2 > 0.0 and paid2 < cost * SimEconomy.REPAIR_COST * 0.1, "%.0f cr" % paid2)


func _suite_refusals() -> void:
	var w := _world()
	var mine := _plant(w, 0)
	var theirs := _plant(w, 1)

	var their_credits: float = w.economy.credits(1)
	w.commands.sell(0, theirs)
	w.run_ticks(1)
	_ok("you cannot sell someone else's building",
		w.entities.alive[theirs] == 1 and absf(w.economy.credits(1) - their_credits) < 0.01)

	var before: float = w.economy.credits(0)
	w.commands.repair(0, mine)
	w.run_ticks(1)
	_ok("repairing an undamaged building is refused and costs nothing",
		absf(w.economy.credits(0) - before) < 0.01)

	# A unit is not a building; an army is not liquidated a tank at a time.
	var tank := w.entities.add("tank", 0, 0.0, 0.0, 0.0, SimSignature.new(12.0), [],
		SimTypes.Category.GROUND, 2.5, 0)
	var before2: float = w.economy.credits(0)
	w.commands.sell(0, tank)
	w.run_ticks(1)
	_ok("and a tank cannot be sold at all",
		w.entities.alive[tank] == 1 and absf(w.economy.credits(0) - before2) < 0.01)


func _ok(what: String, cond: bool, note := "") -> void:
	if cond:
		_pass += 1
		print("    PASS  %s%s" % [what, "  " + note if note != "" else ""])
	else:
		_fail += 1
		print("    FAIL  %s  %s" % [what, note])


func _process(_d: float) -> bool:
	return true
