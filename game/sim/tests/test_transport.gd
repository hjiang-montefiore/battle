extends SceneTree
## Tests for the transport and deploy system (slot 3.5): loading, riding,
## unloading, the cargo doctrine, and the DeployState machine.
##
##     godot --path game --headless --script res://sim/tests/test_transport.gd
##
## Its own file on purpose -- each subsystem owns test_<name>.gd, and a shared
## runner is a shared merge conflict.
##
## What is asserted is BEHAVIOUR through the real command path: a squad ordered
## LOAD walks to the APC and boards; cargo rides, is not sensed, and dies with
## the hull; a landing craft unloads onto the beach and refuses mid-ocean; a
## towed gun cannot fire limbered and cannot move deployed, and the transition
## window is real time in which it can do neither; and two runs from one seed
## are bit-identical.

var _passed := 0
var _failed := 0


func _init() -> void:
	print("")
	print("  BATTLE -- transport and deploy tests")
	print("  " + "-".repeat(66))

	_suite_roster()
	_suite_load_ride_unload()
	_suite_ownership()
	_suite_cargo_invisible()
	_suite_cargo_dies_with_hull()
	_suite_deploy_states()
	_suite_deploy_fire_gate()
	_suite_beach()
	_suite_determinism()

	print("  " + "-".repeat(66))
	if _failed == 0:
		print("  %d passed, 0 failed" % _passed)
	else:
		print("  %d passed, %d FAILED" % [_passed, _failed])
	print("")
	quit(1 if _failed > 0 else 0)


## Safety net: a script error inside _init() would skip quit() and leave the
## SceneTree spinning with stdout unflushed. One iteration, then out.
func _process(_delta: float) -> bool:
	return true


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


# ── fixtures ─────────────────────────────────────────────────────────────────

## A world with one funded player on flat dry land, transport system installed.
func _world(seed_value := 4242, epoch := 4) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.use_accumulator = false
	var t := SimTerrain.new(64, 64, 50.0, "plain")
	t.fill(5.0)
	w.use_terrain(t)
	w.economy.add_player(0, 30000.0, epoch, 7)
	SimTransport.install(w)
	return w


## A coast: x < 0 is 20 m of water, x > 0 is dry land at 5 m.
func _coast_world(seed_value := 7777) -> SimWorld:
	var w := SimWorld.new(seed_value)
	w.use_accumulator = false
	var t := SimTerrain.new(64, 64, 50.0, "coast")
	t.fill(5.0)
	t.carve_sea(-1600.0, -1600.0, 0.0, 1600.0, 20.0)
	w.use_terrain(t)
	w.economy.add_player(0, 30000.0, 4, 7)
	SimTransport.install(w)
	return w


func _fc_radar() -> SimSensorDef:
	return SimSensorDef.new({
		"name": "FCR", "domain": SimTypes.Domain.RF_ACTIVE,
		"reference_range_km": 60.0, "mount_height_m": 3.0,
		"max_quality": SimTypes.TrackQuality.FIRE_CONTROL, "radar_gen": 4,
	})


func _gun(max_km := 4.0) -> SimWeaponDef:
	return SimWeaponDef.new({
		"name": "gun", "guidance": SimTypes.Guidance.UNGUIDED,
		"min_range_km": 0.0, "max_range_km": max_km,
	})


# ═══════════════════════════════════════════════════════════════════════════
# 1. THE ROSTER CARRIES THE NUMBERS
# ═══════════════════════════════════════════════════════════════════════════

func _suite_roster() -> void:
	_suite("Capacity and deploy timers come from the roster (docs/12)")

	_ok("an APC lifts a squad and its attachment",
		SimRoster.make("apc", 1).cargo_slots == 2)
	_ok("an IFV lifts less -- the turret ate the troop compartment",
		SimRoster.make("ifv", 3).cargo_slots == 1)
	_ok("a transport helicopter lifts a platoon-minus",
		SimRoster.make("transport_helicopter", 2).cargo_slots == 3)
	_ok("a landing craft has a vehicle deck",
		SimRoster.make("landing_craft", 1).carries_vehicles)
	_ok("an amphib has a well deck",
		SimRoster.make("amphib", 2).carries_vehicles)
	_ok("an APC does NOT take vehicles",
		not SimRoster.make("apc", 1).carries_vehicles)
	_ok("nothing exceeds the spine's fixed hold stride",
		SimRoster.make("transport_aircraft", 1).cargo_slots <= SimEntities.MAX_CARGO
		and SimRoster.make("amphib", 2).cargo_slots <= SimEntities.MAX_CARGO)

	var gun := SimRoster.make("towed_artillery", 1)
	_ok("towed artillery is a deployable that fires only deployed",
		gun.is_deployable() and gun.fires_deployed_only)
	_ok("packing the gun up is slower than dropping its trails",
		gun.undeploy_seconds > gun.deploy_seconds,
		"%.0f s down, %.0f s up" % [gun.deploy_seconds, gun.undeploy_seconds])
	var tel := SimRoster.make("ballistic_launcher", 2)
	_ok("the TEL erects slower than the gun emplaces",
		tel.deploy_seconds > gun.deploy_seconds,
		"%.0f s vs %.0f s" % [tel.deploy_seconds, gun.deploy_seconds])
	_ok("a tank is not a deployable and fires on the move",
		not SimRoster.make("mbt", 4).is_deployable())

	var w := _world()
	var apc := w.economy.place_starting_unit(0, "apc", 0.0, 0.0)
	_ok("spawning writes the capacity into the entity store",
		w.entities.cargo_capacity[apc] == 2)
	_ok("the world reports the transport system installed",
		w.subsystem_status()["transport"] == true)


# ═══════════════════════════════════════════════════════════════════════════
# 2. LOAD -> RIDE -> UNLOAD, through the command queue
# ═══════════════════════════════════════════════════════════════════════════

func _suite_load_ride_unload() -> void:
	_suite("A squad walks to its APC, boards, rides, and disgorges")

	var w := _world()
	var e := w.entities
	var apc := w.economy.place_starting_unit(0, "apc", 0.0, 0.0)
	var squad := w.economy.place_starting_unit(0, "rifle_squad", 0.0, 150.0)

	w.commands.load_cargo(0, squad, apc)
	w.run_ticks(2)
	_ok("the LOAD order is a journey, not a teleport",
		not e.is_aboard(squad) and (w.transport_system as SimTransport)
			.is_load_pending(squad))
	w.run_ticks(900)
	_ok("the squad walked to the ramp and boarded",
		e.carried_by[squad] == apc, "carried_by=%d" % e.carried_by[squad])
	_ok("the hold counts it", e.cargo_count(apc) == 1)
	_ok("aboard, it can neither move nor fire",
		not e.can_move(squad) and not e.can_fire(squad))

	w.commands.move(0, apc, 600.0, 0.0)
	w.run_ticks(700)
	_ok("the APC went where it was told",
		absf(e.pos_x[apc] - 600.0) < 30.0, "x=%.0f" % e.pos_x[apc])
	_ok("the cargo rode along -- position snapped to the hull",
		e.pos_x[squad] == e.pos_x[apc] and e.pos_z[squad] == e.pos_z[apc])

	w.commands.unload_cargo(0, apc)
	w.run_ticks(2)
	_ok("D disgorges: the squad is back on the map",
		not e.is_aboard(squad) and e.cargo_count(apc) == 0)
	var dx := e.pos_x[squad] - e.pos_x[apc]
	var dz := e.pos_z[squad] - e.pos_z[apc]
	var d := sqrt(dx * dx + dz * dz)
	_ok("adjacent to the hull, on the deterministic ring",
		d > 5.0 and d < 140.0, "%.0f m out" % d)
	_ok("and it is a working unit again", e.can_move(squad))


# ═══════════════════════════════════════════════════════════════════════════
# 3. OWNERSHIP -- boarding the enemy's APC is structurally impossible
# ═══════════════════════════════════════════════════════════════════════════

func _suite_ownership() -> void:
	_suite("You cannot board an APC you do not own (docs/09 §1)")

	var w := _world()
	w.economy.add_player(1, 30000.0, 4, 7)
	var squad := w.economy.place_starting_unit(0, "rifle_squad", 0.0, 0.0)
	var theirs := w.economy.place_starting_unit(1, "apc", 10.0, 0.0)

	var rejected_before := w.commands.rejected
	w.commands.load_cargo(0, squad, theirs)
	w.run_ticks(2)
	_ok("the order is rejected at the command gate",
		w.commands.rejected == rejected_before + 1)
	_ok("and nothing boarded", not w.entities.is_aboard(squad))

	# The physics gate speaks too: vehicles do not fit in an APC.
	var tank := w.economy.place_starting_unit(0, "mbt", 30.0, 0.0)
	var mine := w.economy.place_starting_unit(0, "apc", 40.0, 0.0)
	var t := w.transport_system as SimTransport
	_ok("a tank is refused by an APC -- only well decks take vehicles",
		t.loading_problem(tank, mine) != "", t.loading_problem(tank, mine))


# ═══════════════════════════════════════════════════════════════════════════
# 4. THE CARGO DOCTRINE -- aboard means off the picture
# ═══════════════════════════════════════════════════════════════════════════

func _suite_cargo_invisible() -> void:
	_suite("Cargo is not sensed: its tracks age out like a unit gone silent")

	var w := _world()
	var e := w.entities
	# An enemy observer with a real radar, watching from 2 km.
	e.add("observer", 1, 0.0, 3.0, 0.0, SimSignature.new(20.0),
		[_fc_radar()], SimTypes.Category.GROUND, 3.0)
	var apc := w.economy.place_starting_unit(0, "apc", 2000.0, 0.0)
	var squad := w.economy.place_starting_unit(0, "rifle_squad", 2000.0, 30.0)

	w.run_ticks(60)
	var table := w.track_table_for(1)
	_ok("the observer holds both of them", table.count() == 2,
		"%d tracks" % table.count())

	w.commands.load_cargo(0, squad, apc)
	w.run_ticks(4)
	_ok("the squad boarded", e.carried_by[squad] == apc)
	w.run_ticks(2400)   # two minutes: no fresh observations, the track decays
	_ok("its track went cold and dropped; the APC's did not",
		table.count() == 1, "%d tracks left" % table.count())


func _suite_cargo_dies_with_hull() -> void:
	_suite("If the transport dies, the cargo dies -- and the log says so")

	var w := _coast_world()
	var e := w.entities
	# A loaded landing craft nested in an amphib's well deck: the doctrine's
	# own example, three hulls deep. The craft starts at the water's edge --
	# the bilinear waterline sits near x = +16, so -12 floats and +28 stands.
	var amphib := w.economy.place_starting_unit(0, "amphib", -400.0, 0.0)
	var craft := w.economy.place_starting_unit(0, "landing_craft", -12.0, 0.0)
	var tank := w.economy.place_starting_unit(0, "mbt", 28.0, 0.0)

	var t := w.transport_system as SimTransport
	_ok("a boat nests only in a well deck",
		t.loading_problem(craft, amphib) == "",
		t.loading_problem(craft, amphib))

	w.commands.load_cargo(0, tank, craft)
	w.run_ticks(4)
	_ok("the tank embarked on the landing craft",
		e.carried_by[tank] == craft, "carried_by=%d" % e.carried_by[tank])
	_ok("a vehicle costs 4 of the craft's 8 slots",
		t.slots_used(craft) == 4 and t.slots_free(craft) == 4)

	# LOAD is a journey for ships too: the loaded craft sails itself to the
	# amphib and nests on arrival.
	w.commands.load_cargo(0, craft, amphib)
	w.run_ticks(1600)
	_ok("the loaded craft sailed out and nested aboard the amphib",
		e.carried_by[craft] == amphib, "carried_by=%d" % e.carried_by[craft])
	_ok("the tank's outermost hull is the amphib",
		e.top_carrier(tank) == amphib)

	w.run_ticks(2)   # let the manifest watch see the loaded hold
	e.kill(amphib)   # what SimDamage would do on a catastrophic hit
	w.run_ticks(2)
	_ok("the cascade took the craft", e.alive[craft] == 0)
	_ok("and the tank inside the craft inside the amphib", e.alive[tank] == 0)
	var logged := "\n".join(PackedStringArray(w.damage.combat_log))
	_ok("the combat log states the cost", logged.contains("cargo is lost"),
		logged.get_slice("\n", maxi(w.damage.combat_log.size() - 1, 0)))


# ═══════════════════════════════════════════════════════════════════════════
# 5. DEPLOY STATES -- the transition window is the gameplay
# ═══════════════════════════════════════════════════════════════════════════

func _suite_deploy_states() -> void:
	_suite("Towed artillery: limbered moves, deployed fires, never both")

	var w := _world()
	var e := w.entities
	var gun := w.economy.place_starting_unit(0, "towed_artillery", 0.0, 0.0)
	_ok("it spawns limbered and mobile",
		e.deploy_state[gun] == SimTypes.DeployState.MOBILE and e.can_move(gun))

	w.commands.deploy(0, gun)
	w.run_ticks(2)
	_ok("D starts the emplacement",
		e.deploy_state[gun] == SimTypes.DeployState.DEPLOYING)
	_ok("in transition it cannot move", not e.can_move(gun))

	var rejected := w.commands.rejected
	w.commands.deploy(0, gun)
	w.run_ticks(2)
	_ok("a mid-transition order is refused -- the crew is committed",
		w.commands.rejected == rejected + 1)

	w.run_ticks(int(10.0 * SimWorld.SIM_HZ) + 4)
	_ok("ten seconds later it is emplaced",
		e.deploy_state[gun] == SimTypes.DeployState.DEPLOYED)

	rejected = w.commands.rejected
	w.commands.move(0, gun, 500.0, 0.0)
	w.run_ticks(2)
	_ok("deployed, a move order is refused",
		w.commands.rejected == rejected + 1 and not e.can_move(gun))

	w.commands.deploy(0, gun)
	w.run_ticks(int(15.0 * SimWorld.SIM_HZ) + 4)
	_ok("packing up takes its fifteen seconds, then it rolls again",
		e.deploy_state[gun] == SimTypes.DeployState.MOBILE and e.can_move(gun))
	w.commands.move(0, gun, 60.0, 0.0)
	w.run_ticks(400)
	_ok("and the limbered gun really moves",
		absf(e.pos_x[gun] - 60.0) < 20.0, "x=%.0f" % e.pos_x[gun])


func _suite_deploy_fire_gate() -> void:
	_suite("The weapon cycle refuses a limbered gun (docs/02 §9: with a reason)")

	var w := SimWorld.new(1234)
	w.use_accumulator = false
	var e := w.entities
	var shooter := e.add("battery", 0, 0.0, 2.0, 0.0, SimSignature.new(20.0),
		[_fc_radar()], SimTypes.Category.GROUND, 3.0)
	e.set_mobility(shooter, 5.0, 1.0, 0.6)
	var target := e.add("target", 1, 0.0, 2.0, 1500.0, SimSignature.new(25.0))
	SimArmorScheme.apply(e, target, SimArmorScheme.Gen.G1)
	w.weapons.arm(shooter, _gun(), SimArmorScheme.make_gun_round(
		SimArmorScheme.Gen.G4), 6.0)
	var t := SimTransport.install(w)
	t.make_deployable(shooter, 5.0, 5.0, true)

	w.run_ticks(10)
	var ids := w.track_table_for(0).track_ids()
	_ok("the battery holds a track on the target", not ids.is_empty())
	if ids.is_empty():
		return
	w.commands.attack_track(0, shooter, ids[0])
	w.run_ticks(200)
	_ok("limbered, the ORDER stands but no round leaves the tube",
		w.weapons.shots_fired == 0 and w.weapons.is_engaging(shooter))
	_ok("and the refusal says why", w.weapons.last_refusal.contains("limbered"),
		w.weapons.last_refusal)

	w.commands.deploy(0, shooter)
	w.run_ticks(int(2.5 * SimWorld.SIM_HZ))
	_ok("mid-transition it still holds fire", w.weapons.shots_fired == 0,
		w.weapons.last_refusal)
	w.run_ticks(int(3.0 * SimWorld.SIM_HZ))
	_ok("it finished deploying",
		e.deploy_state[shooter] == SimTypes.DeployState.DEPLOYED)
	w.run_ticks(200)
	_ok("deployed, the SAME engagement fires", w.weapons.shots_fired > 0,
		"%d shots" % w.weapons.shots_fired)


# ═══════════════════════════════════════════════════════════════════════════
# 6. THE BEACH -- terrain decides where the ramp drops
# ═══════════════════════════════════════════════════════════════════════════

func _suite_beach() -> void:
	_suite("A landing craft unloads onto the beach, and refuses mid-ocean")

	var w := _coast_world()
	var e := w.entities
	# The bilinear waterline sits near x = +16: -10 floats, +28 stands dry.
	var craft := w.economy.place_starting_unit(0, "landing_craft", -10.0, 0.0)
	var tank := w.economy.place_starting_unit(0, "mbt", 28.0, 0.0)
	_ok("the craft floats and the tank stands on land",
		w.terrain.is_water(e.pos_x[craft], e.pos_z[craft])
		and not w.terrain.is_water(e.pos_x[tank], e.pos_z[tank]))

	w.commands.load_cargo(0, tank, craft)
	w.run_ticks(4)
	_ok("the tank embarked over the ramp", e.carried_by[tank] == craft)

	w.commands.unload_cargo(0, craft)
	w.run_ticks(2)
	_ok("the tank came off ONTO LAND, not into the sea",
		not e.is_aboard(tank)
		and not w.terrain.is_water(e.pos_x[tank], e.pos_z[tank]),
		"at %.0f, %.0f" % [e.pos_x[tank], e.pos_z[tank]])

	# Mid-ocean: a craft with a squad aboard and no beach in reach.
	var far := w.economy.place_starting_unit(0, "landing_craft", -800.0, 0.0)
	var squad := w.economy.place_starting_unit(0, "rifle_squad", -805.0, 0.0)
	w.commands.load_cargo(0, squad, far)
	w.run_ticks(4)
	_ok("the squad is aboard the far craft", e.carried_by[squad] == far)
	var rejected := w.commands.rejected
	w.commands.unload_cargo(0, far)
	w.run_ticks(2)
	_ok("mid-ocean, UNLOAD is refused and the squad stays aboard",
		w.commands.rejected == rejected + 1 and e.carried_by[squad] == far)


# ═══════════════════════════════════════════════════════════════════════════
# 7. DETERMINISM -- docs/06's non-negotiable
# ═══════════════════════════════════════════════════════════════════════════

func _scripted(seed_value: int) -> int:
	var w := _world(seed_value)
	var apc := w.economy.place_starting_unit(0, "apc", 0.0, 0.0)
	var s1 := w.economy.place_starting_unit(0, "rifle_squad", 0.0, 120.0)
	var s2 := w.economy.place_starting_unit(0, "rifle_squad", 60.0, 120.0)
	var gun := w.economy.place_starting_unit(0, "towed_artillery", -80.0, 0.0)
	w.commands.load_cargo(0, s1, apc)
	w.commands.load_cargo(0, s2, apc)
	w.commands.deploy(0, gun)
	w.run_ticks(600)
	w.commands.move(0, apc, 700.0, 200.0)
	w.commands.deploy(0, gun)
	w.run_ticks(500)
	w.commands.unload_cargo(0, apc)
	w.run_ticks(200)
	return w.state_hash()


func _suite_determinism() -> void:
	_suite("Two runs from one seed are the same run (docs/06)")

	var a := _scripted(2026)
	var b := _scripted(2026)
	_ok("the full load/deploy/ride/unload script hashes identically",
		a == b, "%d vs %d" % [a, b])
	var c := _scripted(9091)
	_ok("a different seed is allowed to differ (not asserted equal)",
		true, "hash %d" % c)
