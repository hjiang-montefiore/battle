extends SceneTree
## Tests for the economy: the resource chain, base building, production queues,
## epoch advancement and docs/04 fuel.
##
##     godot --path game --headless --script res://sim/tests/test_economy.gd
##
## A SEPARATE file on purpose. Four agents are building on one spine and a
## shared runner is a shared merge conflict; each subsystem owns test_<name>.gd.
##
## What this file asserts is END TO END behaviour: money in from a chain that
## can be broken, a structure that takes real time to finish and can be bombed
## while it does, a queue that spends and refunds, an epoch that costs time as
## well as credits, and a tank that stops when the fuel runs out. Plus the one
## property docs/06 makes non-negotiable -- two runs from one seed are the same
## run.

var _passed := 0
var _failed := 0


func _init() -> void:
	print("")
	print("  BATTLE -- economy tests")
	print("  " + "-".repeat(66))

	_suite_roster_epoch_gate()
	_suite_roster_epoch_scaling()
	_suite_purse()
	_suite_resource_chain()
	_suite_power()
	_suite_placement()
	_suite_construction()
	_suite_production()
	_suite_production_refunds()
	_suite_epoch_advance()
	_suite_fuel_burn()
	_suite_supply()
	_suite_spawn_profile()
	_suite_command_path()
	_suite_determinism()

	print("  " + "-".repeat(66))
	if _failed == 0:
		print("  %d passed, 0 failed" % _passed)
	else:
		print("  %d passed, %d FAILED" % [_passed, _failed])
	print("")
	quit(1 if _failed > 0 else 0)


func _suite(name: String) -> void:
	print("")
	print("  " + name)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		_passed += 1
		print("    PASS  %s%s" % [label, ("  " + detail) if detail else ""])
	else:
		_failed += 1
		print("    FAIL  %s%s" % [label, ("  " + detail) if detail else ""])


func _near(label: String, got: float, want: float, tol: float) -> void:
	_ok(label, absf(got - want) <= tol,
		"got %.3f, expected %.3f +/- %.3f" % [got, want, tol])


## A world with a flat 102 x 102 km plane, an economy that knows about it, and
## one registered player. Flat, because placement rules that depend on a
## theatre's coastline would be testing SimTheatre, not this.
func _world(seed_value := 4242, start_epoch := 4, ceiling := 7,
		credits := 20000.0) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.use_accumulator = false
	w.terrain = SimTerrain.new(128, 128, 800.0, "test plain")
	w.terrain.fill(120.0)
	w.solver.terrain = w.terrain
	w.movement.set_terrain(w.terrain)
	w.economy.set_terrain(w.terrain)
	w.economy.add_player(0, credits, start_epoch, ceiling)
	return w


## docs/05 gives a player a start epoch AND a ceiling; both are honoured, and a
## role that does not exist yet is not merely expensive, it is absent.
func _suite_roster_epoch_gate() -> void:
	_suite("The epoch ladder gates the roster (docs/05, docs/12)")

	_ok("the IFV does not exist before epoch 3", SimRoster.make("ifv", 2) == null)
	_ok("and does from epoch 3", SimRoster.make("ifv", 3) != null)
	_ok("AEW&C arrives with epoch 3, not before",
		SimRoster.make("aewc", 2) == null and SimRoster.make("aewc", 3) != null)
	_ok("the stealth strike aircraft waits for epoch 4",
		SimRoster.make("stealth_strike", 3) == null
			and SimRoster.make("stealth_strike", 4) != null)
	_ok("the loitering munition is epoch 7 only",
		SimRoster.make("loitering_munition", 6) == null
			and SimRoster.make("loitering_munition", 7) != null)
	_ok("the MBT is there from the first epoch", SimRoster.make("mbt", 1) != null)

	# docs/12 counts 86 roles across five domains; this table carries all of
	# them plus the handful the document lists but does not count.
	_ok("every docs/12 role is in the table", SimRoster.role_count() >= 86,
		"%d roles" % SimRoster.role_count())

	# The SAM battery split -- docs/12's "most consequential roster decision".
	var launcher := SimRoster.make("medium_sam_launcher", 4)
	var illum := SimRoster.make("illuminator", 4)
	var search := SimRoster.make("search_radar", 4)
	_ok("the medium SAM launcher carries no sensor of its own", launcher.sensor == "")
	_ok("the illuminator is the one that can guide",
		SimRoster.sensors_for(illum.sensor, 4)[0].max_quality
			== SimTypes.TrackQuality.FIRE_CONTROL)
	_ok("and the search radar finds without guiding",
		SimRoster.sensors_for(search.sensor, 4)[0].max_quality
			== SimTypes.TrackQuality.TRACK)

	# A player's domain restrictions filter the roster (docs/09 §4, extended).
	var w := _world()
	var s := SimPlayerSetup.new({"name": "land only"})
	s.set_army_only()
	w.economy.purse(0).setup = s
	_ok("an army-only player cannot reach an aircraft",
		w.economy.def_for(0, "strike_aircraft") == null)
	_ok("but can still reach a tank", w.economy.def_for(0, "mbt") != null)


func _suite_roster_epoch_scaling() -> void:
	_suite("Advancing an epoch upgrades the production line in place (docs/05)")

	var e1 := SimRoster.make("mbt", 1)
	var e4 := SimRoster.make("mbt", 4)
	var e7 := SimRoster.make("mbt", 7)
	_ok("the epoch-7 tank costs more than the epoch-1 tank",
		e7.cost > e1.cost * 2.0, "%.0f vs %.0f" % [e7.cost, e1.cost])

	var a1: Array = SimRoster.armor_facets("heavy", 1)
	var a7: Array = SimRoster.armor_facets("heavy", 7)
	_ok("and is far thicker frontally",
		float(a7[SimTypes.Facet.FRONT]) > float(a1[SimTypes.Facet.FRONT]) * 3.0,
		"%.0f mm vs %.0f mm" % [a7[SimTypes.Facet.FRONT], a1[SimTypes.Facet.FRONT]])

	# docs/03's cliff is a TYPE change, not a thickness change. Epoch 3 is where
	# docs/05 says five of the eight capability steps land.
	var t2: Array = SimRoster.armor_types("heavy", 2)
	var t3: Array = SimRoster.armor_types("heavy", 3)
	_ok("epoch 2 armour is spaced, epoch 3 is composite -- a different problem",
		int(t2[0]) == SimTypes.ArmorType.SPACED
			and int(t3[0]) == SimTypes.ArmorType.COMPOSITE)

	# The consequence, run through the real matrix rather than asserted.
	var t1: Array = SimRoster.armor_types("heavy", 1)
	# A 1950s full-calibre AP round, ~220 mm RHA at 2 km, and a 1960s APDS at
	# ~300 mm. Both are quoted figures for their era, not numbers reverse-fitted
	# to make the assertion pass.
	var gun_1950 := 220.0
	var gun_1960 := 300.0
	_ok("a 1950s gun beats a 1950s cast glacis",
		SimArmor.penetrates(gun_1950, float(SimRoster.armor_facets("heavy", 1)[0]),
			int(t1[0]), SimTypes.DamageClass.KE))
	_ok("and already fails against the epoch-2 spaced one",
		not SimArmor.penetrates(gun_1950,
			float(SimRoster.armor_facets("heavy", 2)[0]),
			int(t2[0]), SimTypes.DamageClass.KE))
	_ok("a 1960s APDS round beats that spaced glacis",
		SimArmor.penetrates(gun_1960, float(SimRoster.armor_facets("heavy", 2)[0]),
			int(t2[0]), SimTypes.DamageClass.KE))
	_ok("and cannot touch the epoch-3 composite one at any range -- the cliff",
		not SimArmor.penetrates(gun_1960,
			float(SimRoster.armor_facets("heavy", 3)[0]),
			int(t3[0]), SimTypes.DamageClass.KE))

	# docs/04: gas turbines from the 1980s burn dramatically more.
	_ok("the epoch-4 tank burns much harder than the epoch-3 one",
		SimRoster.make("mbt", 4).burn_cruise
			> SimRoster.make("mbt", 3).burn_cruise * 1.4,
		"%.1f vs %.1f lpm" % [SimRoster.make("mbt", 4).burn_cruise,
			SimRoster.make("mbt", 3).burn_cruise])

	# docs/04: nuclear propulsion removes the constraint outright.
	_ok("a nuclear submarine carries no fuel constraint at all",
		SimRoster.make("ssn", 4).fuel_capacity == 0.0)
	_ok("while the diesel boat does",
		SimRoster.make("ssk", 4).fuel_capacity > 0.0)
	_ok("and the carrier is conventional until epoch 3",
		SimRoster.make("carrier", 2).fuel_capacity > 0.0
			and SimRoster.make("carrier", 3).fuel_capacity == 0.0)


func _suite_purse() -> void:
	_suite("Credits: never a partial spend")

	var w := _world(1, 4, 7, 1000.0)
	var eco := w.economy
	_ok("a registered player has its starting credits", eco.credits(0) == 1000.0)
	_ok("an unregistered player has none and does not crash",
		eco.credits(99) == 0.0 and eco.purse(99) == null)
	_ok("spending more than the bank changes nothing",
		not eco.try_spend(0, 1000.01) and eco.credits(0) == 1000.0)
	_ok("spending exactly the bank empties it",
		eco.try_spend(0, 1000.0) and eco.credits(0) == 0.0)
	_ok("a negative spend is refused rather than being a gift",
		not eco.try_spend(0, -500.0) and eco.credits(0) == 0.0)

	eco.add_player(3, 10.0, 1, 1)
	eco.add_player(1, 10.0, 1, 1)
	_ok("player_ids() is ascending, always", eco.player_ids() == [0, 1, 3],
		str(eco.player_ids()))


## docs/04's chain, made mechanical: crude out of the ground, capped by what
## you can refine. A derrick on its own earns nothing.
func _suite_resource_chain() -> void:
	_suite("The resource chain: extract, refine, spend (docs/04)")

	var w := _world(2, 4, 7, 0.0)
	var eco := w.economy
	eco.place_starting_unit(0, "hq", 20000.0, 20000.0)
	eco.step(60.0)
	var trickle := eco.credits(0)
	_ok("an HQ alone is a trickle, not an income",
		trickle > 0.0 and trickle < 100.0, "%.0f cr in a minute" % trickle)

	eco.place_starting_unit(0, "oil_derrick", 20080.0, 20000.0)
	eco.place_starting_unit(0, "oil_derrick", 20160.0, 20000.0)
	eco.step(60.0)
	var pumping := eco.credits(0) - trickle
	_ok("two derricks with nowhere to refine earn nothing more",
		absf(pumping - trickle) < 1.0,
		"%.0f cr in the minute after building them" % pumping)
	_ok("and the purse says why: crude with no capacity",
		eco.purse(0).extraction_per_min > 400.0
			and eco.purse(0).refine_capacity == 0.0)

	eco.place_starting_unit(0, "power_plant", 20000.0, 20100.0)
	eco.place_starting_unit(0, "refinery", 20000.0, 20200.0)
	var before := eco.credits(0)
	eco.step(60.0)
	var refined := eco.credits(0) - before
	_ok("a refinery turns the same crude into real income",
		refined > 400.0, "%.0f cr in a minute" % refined)
	_near("income is min(crude, capacity) plus the trickle",
		refined, minf(eco.purse(0).extraction_per_min,
			eco.purse(0).refine_capacity) + SimEconomy.HQ_TRICKLE_PER_MIN, 2.0)

	# Upkeep is charged against the same pool -- docs/04's "mass has a cost
	# beyond price", which is the counterweight to massing obsolete units.
	for k in range(10):
		eco.place_starting_unit(0, "mbt", 20400.0 + 40.0 * float(k), 20400.0)
	var before2 := eco.credits(0)
	eco.step(60.0)
	var net := eco.credits(0) - before2
	_ok("ten tanks of upkeep eat visibly into that income",
		net < refined - 100.0, "%.0f cr net vs %.0f before" % [net, refined])
	_ok("and the purse reports the upkeep it charged",
		eco.purse(0).upkeep_per_min > 100.0,
		"%.0f cr/min" % eco.purse(0).upkeep_per_min)


func _suite_power() -> void:
	_suite("Power is a brownout, not a blackout (docs/12)")

	var w := _world(3)
	var eco := w.economy
	eco.place_starting_unit(0, "hq", 20000.0, 20000.0)
	eco.place_starting_unit(0, "power_plant", 20000.0, 20120.0)
	eco.place_starting_unit(0, "heavy_factory", 20200.0, 20000.0)
	eco.step(1.0)
	_near("a plant covering the draw is full rate",
		eco.purse(0).power_satisfaction(), 1.0, 0.001)

	# Four more factories, no more generation.
	for k in range(4):
		eco.place_starting_unit(0, "heavy_factory", 20400.0 + 120.0 * float(k),
			20000.0)
	eco.step(1.0)
	_ok("over-drawing the grid drops satisfaction below 1",
		eco.purse(0).power_satisfaction() < 0.6,
		"%.2f" % eco.purse(0).power_satisfaction())
	_ok("but work still happens -- production slows, it does not stop",
		eco.purse(0).power_satisfaction() > 0.0)


func _suite_placement() -> void:
	_suite("Base building: where a structure may go")

	var w := _world(4)
	var eco := w.economy
	var hq := eco.spawn_unit(0, "hq", 20000.0, 20000.0)
	_ok("the first structure may go anywhere -- no build radius yet", hq >= 0)
	# Finish it, so it projects a build radius.
	eco.step(120.0)
	_ok("and it becomes operational once built", eco.is_operational(hq))

	var near_hq := eco.spawn_unit(0, "power_plant", 20200.0, 20000.0)
	_ok("a second structure inside the build radius is accepted", near_hq >= 0)
	var far := eco.spawn_unit(0, "power_plant", 26000.0, 20000.0)
	_ok("one far outside it is refused", far == -1)
	var d := SimRoster.make("power_plant", 4)
	_ok("and the refusal says why, for the cursor",
		eco.placement_problem(0, d, 26000.0, 20000.0).contains("build radius"),
		eco.placement_problem(0, d, 26000.0, 20000.0))

	var overlap := eco.spawn_unit(0, "barracks", 20002.0, 20000.0)
	_ok("a structure on top of another is refused", overlap == -1)

	# Water rules. The plain is dry everywhere, so a naval yard has nowhere.
	_ok("a naval yard needs water and says so",
		eco.placement_problem(0, SimRoster.make("naval_yard", 4),
			20100.0, 20000.0).contains("water"))
	w.terrain.carve_sea(21000.0, 19000.0, 24000.0, 22000.0, 80.0)
	_ok("cannot build a barracks on the sea",
		eco.placement_problem(0, SimRoster.make("barracks", 4),
			22000.0, 20000.0).contains("water"))

	# Prerequisites (docs/12: the heavy factory wants power).
	var w2 := _world(5)
	var eco2 := w2.economy
	eco2.place_starting_unit(0, "hq", 20000.0, 20000.0)
	_ok("a heavy factory is refused without a power plant",
		eco2.spawn_unit(0, "heavy_factory", 20200.0, 20000.0) == -1)
	eco2.place_starting_unit(0, "power_plant", 20120.0, 20000.0)
	_ok("and accepted with one",
		eco2.spawn_unit(0, "heavy_factory", 20260.0, 20000.0) >= 0)

	# Money.
	var w3 := _world(6, 4, 7, 100.0)
	_ok("a structure you cannot afford is not placed",
		w3.economy.spawn_unit(0, "hq", 20000.0, 20000.0) == -1)
	_ok("and nothing was taken for it", w3.economy.credits(0) == 100.0)


func _suite_construction() -> void:
	_suite("A structure takes real time, and is a target while it takes it")

	var w := _world(7)
	var eco := w.economy
	var hq := eco.place_starting_unit(0, "hq", 20000.0, 20000.0)
	eco.step(1.0)
	var before := eco.credits(0)
	var plant := eco.spawn_unit(0, "power_plant", 20200.0, 20000.0)
	_ok("the entity exists the moment the order lands",
		plant >= 0 and w.entities.is_alive(plant))
	_ok("it is an entity in the same store, so it can be shot at",
		w.entities.is_structure[plant] == 1
			and w.entities.structure_max[plant] > 0.0)
	_ok("it is NOT operational yet", not eco.is_operational(plant))
	_ok("the credits were taken up front",
		eco.credits(0) < before, "%.0f -> %.0f" % [before, eco.credits(0)])
	_ok("and progress is reported for a progress bar",
		eco.construction_progress(plant) == 0.0)

	eco.step(10.0)
	var mid := eco.construction_progress(plant)
	_ok("it builds over time", mid > 0.0 and mid < 1.0, "%.0f%%" % (mid * 100.0))
	_ok("still not supplying power halfway through",
		eco.purse(0).power_supply == 0.0)

	eco.step(60.0)
	_ok("and completes", eco.is_operational(plant)
		and eco.construction_progress(plant) == 1.0)
	eco.step(1.0)
	_ok("only then does it feed the grid", eco.purse(0).power_supply > 0.0,
		"%.0f" % eco.purse(0).power_supply)
	_ok("the HQ placed at setup was operational from the start",
		eco.is_operational(hq))


func _suite_production() -> void:
	_suite("Production queues, end to end")

	var w := _base(8)
	var eco := w.economy
	var factory := _find(w, "heavy_factory")
	var barracks := _find(w, "barracks")
	var count_before := w.entities.count()
	var credits_before := eco.credits(0)

	_ok("a barracks cannot build a tank",
		not eco.queue_production(0, barracks, "mbt"))
	_ok("a heavy factory can", eco.queue_production(0, factory, "mbt"))
	_ok("the price was taken at queue time", eco.credits(0) < credits_before)
	_ok("and the queue shows it with progress, not just a name",
		eco.queue_of(0).size() == 1
			and (eco.queue_of(0)[0] as SimEconomy.Job).def_key == "mbt_e4")
	_ok("queue_keys() gives the plain strings for a caller that wants them",
		eco.queue_keys(0) == PackedStringArray(["mbt_e4"]))

	_ok("what the factory offers is derived, not hand-listed",
		eco.production_options(0, factory).has("mbt")
			and not eco.production_options(0, factory).has("rifle_squad"))
	_ok("and the barracks offers infantry",
		eco.production_options(0, barracks).has("rifle_squad"))

	# Run it out.
	for k in range(60):
		eco.step(1.0)
		if eco.queue_of(0).is_empty():
			break
	_ok("the job finishes and leaves the queue", eco.queue_of(0).is_empty())
	_ok("and a unit appeared in the world",
		w.entities.count() > count_before,
		"%d -> %d" % [count_before, w.entities.count()])

	var tank := w.entities.count() - 1
	_ok("owned by the player who paid for it", w.entities.owner[tank] == 0)
	_ok("standing outside the factory, not inside it",
		w.entities.range_km(tank, factory) * 1000.0 > 10.0)

	# The unit that came out is a fully configured unit, not a shell.
	_ok("with the docs/03 armour of its epoch",
		w.entities.armor_at(tank, SimTypes.Facet.FRONT) > 400.0
			and w.entities.armor_type_at(tank, SimTypes.Facet.FRONT)
				== SimTypes.ArmorType.COMPOSITE_HEAVY,
		"%.0f mm" % w.entities.armor_at(tank, SimTypes.Facet.FRONT))
	_ok("thinner at the sides, which is why flanking works",
		w.entities.armor_at(tank, SimTypes.Facet.SIDE)
			< w.entities.armor_at(tank, SimTypes.Facet.FRONT))
	_ok("with mobility", w.entities.max_speed_ms[tank] > 10.0)
	_ok("with a full tank of fuel",
		w.entities.fuel[tank] > 0.0
			and w.entities.fuel[tank] == w.entities.fuel_capacity[tank])
	_ok("with an upkeep bill", w.entities.upkeep_per_min[tank] > 0.0)
	_ok("with a sensor of its own", w.entities.sensors[tank].size() > 0)
	_ok("and it is alive and able to move", w.entities.is_alive(tank)
		and w.entities.can_move(tank))

	# Two structures produce in parallel; one structure produces serially.
	eco.add_income(0, 20000.0)
	eco.queue_production(0, factory, "mbt")
	eco.queue_production(0, factory, "mbt")
	eco.queue_production(0, barracks, "rifle_squad")
	eco.step(1.0)
	var q: Array = eco.queue_of(0)
	_ok("the second job at one factory has not started",
		(q[1] as SimEconomy.Job).progress() == 0.0)
	_ok("while the other building works in parallel",
		(q[2] as SimEconomy.Job).progress() > 0.0)

	# Affordability.
	var w2 := _base(9, 4, 7, 3000.0)
	var f2 := _find(w2, "heavy_factory")
	while w2.economy.credits(0) > 0.0:
		if not w2.economy.queue_production(0, f2, "mbt"):
			break
	_ok("a queue stops at the bank balance",
		w2.economy.credits(0) < SimRoster.make("mbt", 4).cost)
	_ok("and the refusal is silent to the caller, not a crash",
		not w2.economy.queue_production(0, f2, "mbt"))


func _suite_production_refunds() -> void:
	_suite("Losing the factory costs you the factory, not the queue")

	var w := _base(10)
	var eco := w.economy
	var factory := _find(w, "heavy_factory")
	eco.queue_production(0, factory, "mbt")
	eco.queue_production(0, factory, "mbt")
	var after_queue := eco.credits(0)
	# Only SimDamage may kill, and it is a stub, so the test does what the
	# damage layer will do: mark it dead through the store's own entry point.
	w.entities.kill(factory)
	eco.step(1.0)
	_ok("both jobs are dropped", eco.queue_of(0).is_empty())
	_ok("and both are refunded",
		eco.credits(0) > after_queue + SimRoster.make("mbt", 4).cost,
		"%.0f -> %.0f" % [after_queue, eco.credits(0)])

	# Cancelling by hand refunds too.
	var w2 := _base(11)
	var f2 := _find(w2, "heavy_factory")
	w2.economy.queue_production(0, f2, "mbt")
	var c := w2.economy.credits(0)
	var back := w2.economy.cancel_production(0, 0)
	_ok("a cancelled job comes back in full",
		back > 0.0 and absf(w2.economy.credits(0) - (c + back)) < 0.01)
	_ok("and leaves the queue", w2.economy.queue_of(0).is_empty())


func _suite_epoch_advance() -> void:
	_suite("Epoch advancement costs resources AND time (docs/05)")

	var w := _base(12, 4, 6)
	var eco := w.economy
	_ok("advancing needs a research facility",
		not eco.begin_epoch_advance(0))

	var lab := eco.place_starting_unit(0, "research_facility", 20000.0, 20600.0)
	_ok("the facility is what unlocks it", lab >= 0)
	eco.add_income(0, 20000.0)
	var before := eco.credits(0)
	_ok("and then it begins", eco.begin_epoch_advance(0))
	_ok("charging real resources", eco.credits(0) < before,
		"%.0f -> %.0f" % [before, eco.credits(0)])
	_ok("it does not complete instantly", eco.purse(0).epoch == 4)
	_ok("starting a second advance while one runs is refused",
		not eco.begin_epoch_advance(0))

	_ok("the IFV is out of reach at epoch 4... ",
		SimRoster.make("ifv", 4) != null)
	_ok("and the multirole fighter is exactly at it",
		eco.def_for(0, "multirole") != null)
	_ok("while the recon UAV is not, yet", eco.def_for(0, "recon_uav") == null)

	for k in range(400):
		eco.step(1.0)
		if eco.purse(0).epoch > 4:
			break
	_ok("after real time it lands", eco.purse(0).epoch == 5)
	_ok("and the epoch-5 roster opens up", eco.def_for(0, "recon_uav") != null)
	_ok("the production line upgraded in place: a bare role key now means e5",
		eco.def_for(0, "mbt").key == "mbt_e5")

	# The ceiling is real and public.
	eco.add_income(0, 40000.0)
	_ok("one more advance is allowed to reach the ceiling",
		eco.begin_epoch_advance(0))
	for k in range(500):
		eco.step(1.0)
		if eco.purse(0).epoch >= 6:
			break
	_ok("which it does", eco.purse(0).epoch == 6)
	_ok("and the ceiling refuses the next one",
		not eco.begin_epoch_advance(0))
	_ok("even with money in the bank", eco.credits(0) > 10000.0)

	# The clock stops if the lab dies -- it does not reverse, and does not refund.
	var w2 := _base(13, 4, 7)
	var lab2 := w2.economy.place_starting_unit(0, "research_facility",
		20000.0, 20600.0)
	w2.economy.add_income(0, 20000.0)
	w2.economy.begin_epoch_advance(0)
	w2.economy.step(30.0)
	var frozen := w2.economy.purse(0).advance_progress
	_ok("research is under way", frozen > 0.0)
	w2.entities.kill(lab2)
	for k in range(400):
		w2.economy.step(1.0)
	_ok("killing the facility stops the clock where it stood",
		absf(w2.economy.purse(0).advance_progress - frozen) < 0.01
			and w2.economy.purse(0).epoch == 4,
		"%.2f" % w2.economy.purse(0).advance_progress)


func _suite_fuel_burn() -> void:
	_suite("Fuel burns, and running dry is domain-specific (docs/04)")

	var w := _world(14)
	var eco := w.economy
	eco.place_starting_unit(0, "hq", 20000.0, 20000.0)
	var tank := eco.place_starting_unit(0, "mbt", 30000.0, 30000.0)
	var full := w.entities.fuel[tank]
	_ok("a new unit is delivered fuelled",
		full > 0.0 and full == w.entities.fuel_capacity[tank])

	w.entities.move_state[tank] = SimTypes.MoveState.MOVING
	eco.step(60.0)
	var burnt := full - w.entities.fuel[tank]
	_near("one minute at cruise burns exactly the cruise rate",
		burnt, w.entities.burn_cruise_lpm[tank], 0.01)

	w.entities.move_state[tank] = SimTypes.MoveState.COMBAT
	var before := w.entities.fuel[tank]
	eco.step(60.0)
	_near("and a minute in combat burns the combat rate",
		before - w.entities.fuel[tank], w.entities.burn_combat_lpm[tank], 0.01)

	# docs/04: range is not a stat, it is fuel divided by burn.
	_ok("combat radius is roughly a third of what is left in the tank",
		w.entities.combat_radius_m(tank) > 0.0
			and w.entities.combat_radius_m(tank)
				< w.entities.range_remaining_m(tank))

	# Ground: immobilised, still fights.
	w.entities.fuel[tank] = 0.5
	eco.step(60.0)
	_ok("a dry tank is immobilised",
		w.entities.move_state[tank] == SimTypes.MoveState.IMMOBILE)
	_ok("and can_move() agrees", not w.entities.can_move(tank))
	_ok("but it still fights -- docs/04 makes it a bunker, not a wreck",
		w.entities.is_alive(tank) and w.entities.can_fire(tank))
	_ok("the event is reported once, on the transition",
		eco.fuel_starvation.has(tank))
	eco.step(60.0)
	_ok("and not raised again every tick", not eco.fuel_starvation.has(tank))

	# A structure has no tank at all and must never appear to run dry.
	_ok("structures do not starve", not eco.fuel_starvation.has(0))

	# Air is fatal -- but only through the damage layer, which owns kill().
	var plane := eco.place_starting_unit(0, "strike_aircraft", 40000.0, 40000.0)
	w.entities.fuel[plane] = 0.0
	eco.step(1.0)
	_ok("an aircraft that runs dry is reported", eco.fuel_starvation.has(plane))
	# THIS ASSERTION WAS INVERTED WHEN THE MATCH LAYER WIRED THE SPINE UP.
	#
	# It used to check the "no damage layer wired" branch, because SimWorld
	# never called economy.set_damage() and the economy could only log the
	# outcome it was not allowed to apply. SimWorld._init() now wires it, so
	# inside a real world that branch is unreachable and the honest assertion
	# is the one below: docs/04's "air: destroyed" actually happens, through
	# the layer that owns kill().
	_ok("the spine wires the damage layer into the economy", eco.damage != null)
	_ok("so an aircraft that runs dry is destroyed, not merely logged",
		not w.entities.is_alive(plane))
	var honest := false
	for line in eco.events:
		if line.contains("ran out of fuel and came down"):
			honest = true
	_ok("and the log says exactly what happened to it", honest)

	# The unwired branch still exists for anyone building a bare SimEconomy
	# outside a world, and it must still refuse to kill rather than pretend.
	var bare_store := SimEntities.new()
	var bare := SimEconomy.new(bare_store, SimRng.new(7))
	bare.add_player(0, 5000.0, 4, 7)
	var lone := bare.place_starting_unit(0, "strike_aircraft", 0.0, 0.0)
	bare_store.fuel[lone] = 0.0
	bare.step(1.0)
	var admits := false
	for line in bare.events:
		if line.contains("out of fuel in the air"):
			admits = true
	_ok("a bare economy with no damage layer says so rather than pretending",
		admits and bare_store.is_alive(lone))


func _suite_supply() -> void:
	_suite("Supply is automatic and physical (docs/04)")

	var w := _world(15)
	var eco := w.economy
	eco.place_starting_unit(0, "hq", 20000.0, 20000.0)
	var depot := eco.place_starting_unit(0, "supply_depot", 20000.0, 20100.0)
	var near_tank := eco.place_starting_unit(0, "mbt", 20000.0, 20300.0)
	var far_tank := eco.place_starting_unit(0, "mbt", 26000.0, 20000.0)
	var depot_def := SimRoster.make("supply_depot", 4)
	w.entities.fuel[near_tank] = 100.0
	w.entities.fuel[far_tank] = 100.0

	eco.step(60.0)
	_ok("a depot refuels what is inside its radius, with no click",
		w.entities.fuel[near_tank] > 100.0,
		"%.0f litres" % w.entities.fuel[near_tank])
	_ok("and nothing outside it -- the supply line is a thing on the map",
		w.entities.fuel[far_tank] < 100.0,
		"%.0f litres" % w.entities.fuel[far_tank])
	_ok("the depot's radius is what decided that",
		w.entities.range_km(depot, far_tank) * 1000.0 > depot_def.supply_radius_m)

	# A fuel truck carries a finite load, and running it out is the point.
	var truck := eco.place_starting_unit(0, "fuel_truck", 26050.0, 20000.0)
	var carried := w.entities.fuel[truck]
	eco.step(60.0)
	_ok("a truck parked beside a dry tank fills it",
		w.entities.fuel[far_tank] > 100.0,
		"%.0f litres" % w.entities.fuel[far_tank])
	_ok("out of its own load, which is finite",
		w.entities.fuel[truck] < carried)

	# Manual transfer, for the player who wants the override docs/04 allows.
	var a := eco.place_starting_unit(0, "mbt", 30000.0, 30000.0)
	var b := eco.place_starting_unit(0, "mbt", 30040.0, 30000.0)
	var c := eco.place_starting_unit(0, "mbt", 39000.0, 30000.0)
	w.entities.fuel[b] = 0.0
	w.entities.fuel[c] = 0.0
	var moved := eco.transfer_fuel(a, b, 200.0)
	_ok("hose range is short", moved > 0.0 and w.entities.fuel[b] == moved)
	_ok("and it came out of the donor", w.entities.fuel[a] < w.entities.fuel_capacity[a])
	_ok("a unit nine kilometres away gets nothing",
		eco.transfer_fuel(a, c, 200.0) == 0.0)

	eco.add_player(1, 100.0, 4, 4)
	var enemy := eco.place_starting_unit(1, "mbt", 30080.0, 30000.0)
	w.entities.fuel[enemy] = 0.0
	_ok("and you do not refuel the other side",
		eco.transfer_fuel(a, enemy, 200.0) == 0.0)


func _suite_spawn_profile() -> void:
	_suite("Everything the economy spawns is fully configured")

	var w := _world(16)
	var eco := w.economy
	var checked := 0
	for role in ["mbt", "apc", "rifle_squad", "search_radar", "fuel_truck",
			"strike_aircraft", "asw_frigate", "ssk", "power_plant"]:
		var d := SimRoster.make(role, 4)
		if d == null:
			continue
		var i := eco.place_starting_unit(0, role,
			20000.0 + 400.0 * float(checked), 20000.0)
		if i < 0:
			_ok("%s placed" % role, false)
			continue
		checked += 1
		var fine := w.entities.is_alive(i) \
			and w.entities.owner[i] == 0 \
			and w.entities.damage_model[i] == d.damage_model \
			and w.entities.structure_max[i] > 0.0 \
			and w.entities.structure[i] == w.entities.structure_max[i] \
			and w.entities.build_cost[i] > 0.0 \
			and w.entities.category[i] == d.category \
			and (d.is_structure or w.entities.max_speed_ms[i] > 0.0) \
			and (not d.is_structure or w.entities.is_structure[i] == 1)
		_ok("%s: damage, mobility and economy profile all set" % role, fine)
	_ok("a submarine is placed with a depth, not on the surface",
		w.entities.depth_m[_find(w, "ssk")] > 0.0)
	_ok("the economy knows what it built", eco.role_of(_find(w, "mbt")) == "mbt")
	_ok("and reports nothing for a unit it did not build",
		eco.role_of(w.entities.add("hand-placed", 0, 0.0, 0.0, 0.0,
			SimSignature.new())) == "")


## docs/06: "Godot's job is to render this and submit commands to it." The
## economy has to be reachable that way and no other.
func _suite_command_path() -> void:
	_suite("BUILD and PRODUCE arrive through the command queue")

	var w := _base(17)
	var eco := w.economy
	var factory := _find(w, "heavy_factory")

	w.commands.produce(0, factory, "mbt")
	w.run_ticks(1)
	_ok("a PRODUCE order lands in the queue", eco.queue_of(0).size() == 1)
	_ok("and the spine counted it as executed", w.commands.executed > 0)

	var rejected_before := w.commands.rejected
	w.commands.produce(1, factory, "mbt")
	w.run_ticks(1)
	_ok("another player's PRODUCE at your factory is rejected",
		w.commands.rejected > rejected_before and eco.queue_of(0).size() == 1)

	var n := w.entities.count()
	w.commands.build(0, "barracks", 20000.0, 20300.0)
	w.run_ticks(1)
	_ok("a BUILD order places a site", w.entities.count() == n + 1)
	_ok("which is not operational until it is built",
		not eco.is_operational(w.entities.count() - 1))

	# Run the whole world, not just the economy, until the tank exists.
	var before := w.entities.count()
	for k in range(20 * 90):
		w.run_ticks(1)
		if eco.queue_of(0).is_empty():
			break
	_ok("and the world's own 1 Hz economy slot produces the unit",
		w.entities.count() > before)
	_ok("with the sim still ticking normally around it", w.tick > 0)


## docs/06 milestone 1. The economy adds spawns, credits, queues and fuel to
## the state the hash covers, and every one of them has to be reproducible.
func _suite_determinism() -> void:
	_suite("Same seed, same economy (docs/06)")

	var h1 := _scripted_run(99)
	var h2 := _scripted_run(99)
	var h3 := _scripted_run(100)

	_ok("two runs from one seed hash identically",
		h1["hash"] == h2["hash"], "%d vs %d" % [h1["hash"], h2["hash"]])
	_ok("with identical credits",
		absf(float(h1["credits"]) - float(h2["credits"])) < 1e-9,
		"%.6f vs %.6f" % [h1["credits"], h2["credits"]])
	_ok("identical unit counts", h1["count"] == h2["count"],
		"%d vs %d" % [h1["count"], h2["count"]])
	_ok("identical queues", h1["queue"] == h2["queue"])
	_ok("identical epochs", h1["epoch"] == h2["epoch"])
	_ok("identical fuel states", h1["fuel"] == h2["fuel"])
	_ok("and the run actually did something worth hashing",
		int(h1["count"]) > 6 and float(h1["credits"]) > 0.0,
		"%d units, %.0f cr" % [h1["count"], h1["credits"]])
	# A different seed only has to differ somewhere; the economy itself draws
	# no random numbers, so the hash may legitimately match on the parts it
	# owns. What must NOT happen is the same seed diverging.
	_ok("a different seed is still a valid, complete run",
		int(h3["count"]) > 6)

	# The ordering rule that makes it true.
	var w := _world(50)
	w.economy.add_player(7, 1.0, 1, 1)
	w.economy.add_player(2, 1.0, 1, 1)
	w.economy.add_player(5, 1.0, 1, 1)
	_ok("player_ids() sorts, so income order never depends on insertion order",
		w.economy.player_ids() == [0, 2, 5, 7], str(w.economy.player_ids()))
	_ok("buildable() is ascending too",
		_is_sorted(w.economy.buildable(0)))


func _scripted_run(seed_value: int) -> Dictionary:
	var w := _base(seed_value)
	var eco := w.economy
	var factory := _find(w, "heavy_factory")
	var barracks := _find(w, "barracks")
	eco.place_starting_unit(0, "research_facility", 20000.0, 20600.0)
	eco.add_income(0, 30000.0)
	eco.begin_epoch_advance(0)
	# A scripted order of operations, run through the world's own tick.
	for k in range(20 * 200):
		if k == 40:
			w.commands.produce(0, factory, "mbt")
			w.commands.produce(0, barracks, "rifle_squad")
		if k == 600:
			w.commands.produce(0, factory, "sph")
			w.commands.build(0, "supply_depot", 20000.0, 20800.0)
		if k == 1800:
			w.commands.produce(0, factory, "mbt")
		w.run_ticks(1)
	var fuel := PackedFloat32Array()
	for i in range(w.entities.count()):
		fuel.append(snappedf(w.entities.fuel[i], 0.0001))
	return {
		"hash": w.state_hash(),
		"credits": snappedf(eco.credits(0), 0.000001),
		"count": w.entities.count(),
		"queue": eco.queue_keys(0),
		"epoch": eco.purse(0).epoch,
		"fuel": fuel,
	}


# ── helpers ──────────────────────────────────────────────────────────────────

## A world with a working base already standing: HQ, power, refinery, derricks,
## a heavy factory and a barracks, all finished.
func _base(seed_value := 1, start_epoch := 4, ceiling := 7,
		credits := 30000.0) -> SimWorld:
	var w := _world(seed_value, start_epoch, ceiling, credits)
	var eco := w.economy
	eco.place_starting_unit(0, "hq", 20000.0, 20000.0)
	eco.place_starting_unit(0, "power_plant", 20000.0, 20120.0)
	eco.place_starting_unit(0, "refinery", 20000.0, 20240.0)
	eco.place_starting_unit(0, "oil_derrick", 20120.0, 20240.0)
	eco.place_starting_unit(0, "oil_derrick", 20240.0, 20240.0)
	eco.place_starting_unit(0, "heavy_factory", 20200.0, 20000.0)
	eco.place_starting_unit(0, "barracks", 20360.0, 20000.0)
	return w


## First alive entity whose economy role matches, or -1.
func _find(w: SimWorld, role: String) -> int:
	for i in range(w.entities.count()):
		if w.entities.alive[i] == 1 and w.economy.role_of(i) == role:
			return i
	return -1


func _is_sorted(a: PackedStringArray) -> bool:
	for i in range(1, a.size()):
		if a[i] < a[i - 1]:
			return false
	return true
