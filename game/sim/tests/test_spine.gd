extends SceneTree
## Tests for the spine: entity state, tick order, the command boundary and the
## AI information fence.
##
##     godot --path game --headless --script res://sim/tests/test_spine.gd
##
## Deliberately a SEPARATE file from run_sim_tests.gd. Four agents are building
## on this spine in parallel and a shared test runner is a shared merge
## conflict; each subsystem owns test_<name>.gd and nothing else.
##
## What this file does NOT test: whether damage, movement, economy or the AI
## work. They are stubs and they say so. Testing a stub's behaviour would be a
## test that has to be deleted the moment the subsystem is real. What it tests
## is the CONTRACT those subsystems are being handed -- state, ordering,
## ownership, and the fence around the AI -- because that is what has to be
## right the first time.

var _passed := 0
var _failed := 0


func _init() -> void:
	print("")
	print("  BATTLE -- spine tests")
	print("  " + "-".repeat(66))

	_suite_entity_state()
	_suite_armor_matrix()
	_suite_facet_enums_agree()
	_suite_tick_order()
	_suite_command_boundary()
	_suite_ai_fence()
	_suite_determinism()
	_suite_honesty()

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


## A tank-shaped unit, so the armour tests have something to shoot at.
func _add_tank(w: SimWorld, unit_name: String, faction: int, x: float, z: float,
		front_mm: float, front_type: int, owner_id := -1) -> int:
	var i := w.entities.add(unit_name, faction, x, 0.0, z,
		SimSignature.new(20.0), [], SimTypes.Category.GROUND, 3.0,
		owner_id if owner_id >= 0 else faction)
	w.entities.set_damage_profile(i, SimTypes.DamageModel.ARMORED, 100.0,
		[front_mm, 80.0, 45.0, 30.0, 20.0],
		[front_type, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA,
			SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA],
		3)
	w.entities.set_mobility(i, 18.0, 2.0, 0.6)
	w.entities.set_economy_profile(i, 1600.0, 12.0, 1900.0, 4.0, 22.0, 60.0)
	return i


# ── state ────────────────────────────────────────────────────────────────────

func _suite_entity_state() -> void:
	_suite("Entity state is structure-of-arrays and parallel (docs/06)")

	var w := SimWorld.new(1)
	var e := w.entities
	var a := _add_tank(w, "M1A2", 0, 0.0, 0.0, 600.0, SimTypes.ArmorType.COMPOSITE_HEAVY)
	var b := _add_tank(w, "T-72", 1, 100.0, 0.0, 380.0, SimTypes.ArmorType.COMPOSITE)

	# Every parallel array must be exactly as long as the entity count, or the
	# whole index-as-identity model is already broken.
	var lengths := {
		"pos_x": e.pos_x.size(), "structure": e.structure.size(),
		"components": e.components.size(), "heading_rad": e.heading_rad.size(),
		"owner": e.owner.size(), "fuel": e.fuel.size(),
		"move_state": e.move_state.size(), "path_len": e.path_len.size(),
		"is_structure": e.is_structure.size(),
	}
	var all_match := true
	for k in ["pos_x", "structure", "components", "heading_rad", "owner",
			"fuel", "move_state", "path_len", "is_structure"]:
		if lengths[k] != e.count():
			all_match = false
	_ok("every parallel array is entity-count long", all_match,
		"count %d" % e.count())
	_ok("the facet arrays are FACET_COUNT per unit",
		e.armor_mm.size() == e.count() * SimTypes.FACET_COUNT
			and e.armor_type.size() == e.count() * SimTypes.FACET_COUNT)
	_ok("the path slots are MAX_PATH_POINTS per unit",
		e.path_x.size() == e.count() * SimEntities.MAX_PATH_POINTS)

	# Facet independence is what makes flanking mean anything.
	_ok("front and side armour are stored independently",
		e.armor_at(a, SimTypes.Facet.FRONT) > 500.0
			and e.armor_at(a, SimTypes.Facet.SIDE) < 100.0,
		"%.0f mm front, %.0f mm side" % [e.armor_at(a, SimTypes.Facet.FRONT),
			e.armor_at(a, SimTypes.Facet.SIDE)])
	_ok("one unit's armour does not disturb another's",
		e.armor_at(b, SimTypes.Facet.FRONT) == 380.0)

	# Ownership and faction are separate axes (docs/08 coalition, docs/09 §6).
	var ally := e.add("Leopard 2", 0, 20.0, 0.0, 0.0, SimSignature.new(20.0),
		[], SimTypes.Category.GROUND, 3.0, 7)
	_ok("faction and owner are independent",
		e.faction[ally] == 0 and e.owner[ally] == 7)
	_ok("indices_of_owner returns only that player's units, ascending",
		e.indices_of_owner(0) == PackedInt32Array([a]))
	_ok("indices_of_faction spans a coalition",
		e.indices_of_faction(0) == PackedInt32Array([a, ally]))

	# Component damage, docs/03: not a health bar.
	e.lose_component(a, SimTypes.Component.MOBILITY)
	_ok("a mobility kill immobilises but does not kill",
		e.is_alive(a) and not e.can_move(a)
			and e.move_state[a] == SimTypes.MoveState.IMMOBILE)
	_ok("and the turret still traverses -- it is a pillbox, not a wreck",
		e.can_fire(a))
	e.lose_component(a, SimTypes.Component.SENSORS)
	_ok("a sensor kill leaves the unit alive and blind",
		e.is_alive(a) and not e.sensors_intact(a))
	e.lose_component(a, SimTypes.Component.MOBILITY)
	_ok("losing a component twice is losing it once",
		e.components[a] == (SimTypes.Component.MOBILITY | SimTypes.Component.SENSORS))

	# Paths.
	var pts := PackedFloat32Array([10, 0, 20, 0, 30, 0])
	_ok("a path stores its waypoints", e.set_path(b, pts) == 3)
	_ok("and reads back the first one",
		e.current_waypoint(b) == PackedFloat32Array([10.0, 0.0]))
	e.advance_waypoint(b); e.advance_waypoint(b)
	_ok("advancing reaches the last waypoint",
		e.current_waypoint(b) == PackedFloat32Array([30.0, 0.0]))
	_ok("and past the end the path is finished",
		not e.advance_waypoint(b) and e.current_waypoint(b).is_empty())

	var long_path := PackedFloat32Array()
	for k in range(SimEntities.MAX_PATH_POINTS * 2):
		long_path.append(float(k)); long_path.append(0.0)
	_ok("an over-long path is capped, not allowed to corrupt a neighbour",
		e.set_path(b, long_path) == SimEntities.MAX_PATH_POINTS
			and e.path_len[a] == 0)

	# Fuel and range, docs/04.
	_ok("a full tank gives a finite range", e.range_remaining_m(b) > 0.0
			and not is_inf(e.range_remaining_m(b)))
	_ok("combat radius is about a third of it (docs/04)",
		absf(e.combat_radius_m(b) / e.range_remaining_m(b) - 0.35) < 0.001)
	var no_tank := e.add("radar", 0, 0, 0, 0, SimSignature.new(5.0))
	_ok("a unit with no tank is not range-limited",
		is_inf(e.range_remaining_m(no_tank)))
	e.move_state[b] = SimTypes.MoveState.COMBAT
	_ok("burn rate follows the move state (docs/04)",
		e.burn_rate_lpm(b) == 60.0)

	# Killing must not leave a corpse drifting.
	e.set_velocity(b, 10.0, 0.0, 5.0)
	e.kill(b)
	_ok("a dead unit stops dead", e.vel_x[b] == 0.0 and e.vel_z[b] == 0.0
			and e.move_state[b] == SimTypes.MoveState.DEAD)
	_ok("and is excluded from the owner enumeration",
		not (b in e.indices_of_owner(e.owner[b])))


# ── the docs/03 matrix ───────────────────────────────────────────────────────

func _suite_armor_matrix() -> void:
	_suite("Armour matrix is docs/03's table, and it is a cliff")

	_ok("RHA against KE is the 1.00 baseline",
		SimArmor.effectiveness(SimTypes.ArmorType.RHA, SimTypes.DamageClass.KE) == 1.00)
	_ok("composite is better against CE than against KE (docs/03)",
		SimArmor.effectiveness(SimTypes.ArmorType.COMPOSITE, SimTypes.DamageClass.CE)
			> SimArmor.effectiveness(SimTypes.ArmorType.COMPOSITE, SimTypes.DamageClass.KE))
	_ok("ERA nearly triples CE protection and barely touches KE",
		SimArmor.effectiveness(SimTypes.ArmorType.ERA_HEAVY, SimTypes.DamageClass.CE) >= 2.5
			and SimArmor.effectiveness(SimTypes.ArmorType.ERA_HEAVY, SimTypes.DamageClass.KE) < 1.3)
	_ok("HESH is brutal against RHA and defeated by spaced armour",
		SimArmor.effectiveness(SimTypes.ArmorType.RHA, SimTypes.DamageClass.HESH) == 1.0
			and SimArmor.effectiveness(SimTypes.ArmorType.SPACED, SimTypes.DamageClass.HESH) >= 3.0)

	# docs/03's tandem rule: the precursor strips the reactive block, so the
	# main jet meets what is underneath.
	var era_mm := SimArmor.effective_mm(500.0, SimTypes.ArmorType.ERA_HEAVY,
		SimTypes.DamageClass.CE, false)
	var era_tandem := SimArmor.effective_mm(500.0, SimTypes.ArmorType.ERA_HEAVY,
		SimTypes.DamageClass.CE, true)
	_ok("a tandem warhead defeats ERA outright", era_tandem < era_mm * 0.45,
		"%.0f mm -> %.0f mm" % [era_mm, era_tandem])
	var comp_mm := SimArmor.effective_mm(500.0, SimTypes.ArmorType.COMPOSITE,
		SimTypes.DamageClass.CE, false)
	_ok("and does nothing at all against composite",
		SimArmor.effective_mm(500.0, SimTypes.ArmorType.COMPOSITE,
			SimTypes.DamageClass.CE, true) == comp_mm)

	# THE CLIFF. docs/03's worked example: Gen 1 gun, ~180 mm, vs Gen 3.5.
	var gen1_pen := 180.0
	var front := SimArmor.penetrates(gen1_pen, 600.0,
		SimTypes.ArmorType.COMPOSITE_HEAVY, SimTypes.DamageClass.KE)
	var side := SimArmor.penetrates(gen1_pen, 90.0,
		SimTypes.ArmorType.RHA, SimTypes.DamageClass.KE)
	var rear := SimArmor.penetrates(gen1_pen, 50.0,
		SimTypes.ArmorType.RHA, SimTypes.DamageClass.KE)
	var top := SimArmor.penetrates(gen1_pen, 40.0,
		SimTypes.ArmorType.RHA, SimTypes.DamageClass.KE)
	_ok("a Gen 1 gun cannot penetrate a Gen 3.5 front -- not at any range", not front)
	_ok("but it penetrates the side", side)
	_ok("the rear easily", rear)
	_ok("and the roof easily", top)
	_ok("so the obsolete tank is positional, not useless",
		not front and side and rear and top)

	# And it must stay impossible at every range, or it is a slope again.
	var ever := false
	for r in range(0, 6000, 250):
		if SimArmor.penetrates(
				SimArmor.penetration_at_range_mm(gen1_pen, SimTypes.DamageClass.KE,
					float(r), 900.0),
				600.0, SimTypes.ArmorType.COMPOSITE_HEAVY, SimTypes.DamageClass.KE):
			ever = true
	_ok("the frontal refusal holds at every range from 0 to 6 km", not ever)

	# KE bleeds with range, CE does not (docs/03).
	# A tank gun quoted at 700 mm against an ATGM quoted at 650 mm: the gun wins
	# up close and loses at range, purely because one bleeds velocity and the
	# other is chemistry. docs/03 calls this the self-teaching grammar that
	# makes infantry AT want distance and tanks want to close.
	var ke_near := SimArmor.penetration_at_range_mm(700.0, SimTypes.DamageClass.KE, 500.0)
	var ke_far := SimArmor.penetration_at_range_mm(700.0, SimTypes.DamageClass.KE, 5000.0)
	var ce_near := SimArmor.penetration_at_range_mm(650.0, SimTypes.DamageClass.CE, 500.0)
	var ce_far := SimArmor.penetration_at_range_mm(650.0, SimTypes.DamageClass.CE, 5000.0)
	_ok("KE penetration falls with range", ke_far < ke_near,
		"%.0f mm at 500 m, %.0f mm at 5 km" % [ke_near, ke_far])
	_ok("CE penetration is flat with range", ce_near == ce_far)
	_ok("so at long range the ATGM out-penetrates the gun, and near it does not",
		ce_far > ke_far and ce_near < ke_near)


func _suite_facet_enums_agree() -> void:
	_suite("SimTypes.Facet and SimProjectile.Facet are the same integers")
	# impact_facet() returns SimProjectile.Facet; the entity store is indexed by
	# SimTypes.Facet. If these ever drift, a hit on the roof reads the side
	# armour and nobody notices until the balance is inexplicable.
	_ok("FRONT", SimTypes.Facet.FRONT == SimProjectile.Facet.FRONT)
	_ok("SIDE", SimTypes.Facet.SIDE == SimProjectile.Facet.SIDE)
	_ok("REAR", SimTypes.Facet.REAR == SimProjectile.Facet.REAR)
	_ok("TOP", SimTypes.Facet.TOP == SimProjectile.Facet.TOP)
	_ok("BELLY", SimTypes.Facet.BELLY == SimProjectile.Facet.BELLY)
	_ok("and FACET_COUNT covers all of them", SimTypes.FACET_COUNT == 5)


# ── tick order ───────────────────────────────────────────────────────────────

## A probe that records the tick-relative order in which slots ran, by hooking
## the one thing each slot is allowed to touch.
class OrderProbe extends RefCounted:
	var seen: Array = []
	func note(slot: String) -> void:
		seen.append(slot)


func _suite_tick_order() -> void:
	_suite("Tick order (sim_world.gd)")

	var w := SimWorld.new(7)
	w.use_accumulator = false
	var e := w.entities
	var shooter := e.add("gun", 0, 0.0, 5.0, 0.0, SimSignature.new(20.0))
	var target := e.add("target", 1, 0.0, 5.0, 300.0, SimSignature.new(20.0))
	e.set_mobility(target, 100.0, 100.0, 1.0)

	# THE ordering property, stated as a measurement: a round must fly through
	# the world AFTER the world has moved. If munitions stepped before
	# integration, every round would chase last tick's position, and the miss
	# would grow with target speed -- which reads as "the missiles are
	# inaccurate", not as "the tick order is wrong".
	var order := _slot_order_source()
	var i_move := order.find("_movement_slot")
	var i_int := order.find("_integrate")
	var i_mun := order.find("munitions.step")
	var i_com := order.find("_combat_slot")
	var i_sen := order.find("solver.solve")
	var i_ai := order.find("_ai_slot")
	var i_cmd := order.find("_command_slot")
	var i_eco := order.find("_economy_slot")

	_ok("every slot has a call site in _sim_step()",
		i_ai >= 0 and i_cmd >= 0 and i_eco >= 0 and i_move >= 0
			and i_int >= 0 and i_mun >= 0 and i_com >= 0 and i_sen >= 0)
	_ok("AI decides before its commands are executed", i_ai < i_cmd)
	_ok("commands are executed before movement acts on them", i_cmd < i_move)
	_ok("the economy -- the only slot that spawns -- runs before the array sweeps",
		i_eco < i_move and i_eco < i_mun)
	_ok("movement writes velocity before integration consumes it", i_move < i_int)
	_ok("MUNITIONS FLY AFTER THE WORLD HAS MOVED", i_int < i_mun)
	_ok("damage resolves after the rounds that cause it have arrived", i_mun < i_com)
	_ok("and sensing observes the world after damage, not before", i_com < i_sen)

	# The tick still runs, with the stubs in place, and nothing regresses.
	var before := w.state_hash()
	w.run_ticks(40)
	_ok("40 ticks run with the new slots in place", w.tick == 40)
	_ok("and a world with no orders in it does not drift",
		w.state_hash() == before)

	# The economy slot is rate-limited to 1 Hz, not run every tick.
	_ok("the economy slot is on the slow tick, not the sim tick",
		SimWorld.ECONOMY_HZ <= 2.0 and SimWorld.ECONOMY_HZ < SimWorld.SIM_HZ)


## Read _sim_step() back out of the source. Crude on purpose: it asserts the
## order that actually exists in the file rather than an order a mock could be
## made to agree with, and it keeps working when the stubs become real.
func _slot_order_source() -> Array:
	var f := FileAccess.open("res://sim/sim_world.gd", FileAccess.READ)
	var text := f.get_as_text()
	var start := text.find("func _sim_step(")
	var end_at := text.find("\nfunc ", start + 10)
	var body := text.substr(start, end_at - start)
	var out: Array = []
	for line in body.split("\n"):
		var t: String = line.strip_edges()
		if t.begins_with("#"):
			continue
		for token in ["_ai_slot", "_command_slot", "_economy_slot",
				"_movement_slot", "_integrate", "munitions.step",
				"_combat_slot", "solver.solve"]:
			if t.contains(token + "(") and not (token in out):
				out.append(token)
	return out


# ── the command boundary ─────────────────────────────────────────────────────

func _suite_command_boundary() -> void:
	_suite("Commands are the only way in, and ownership is enforced")

	var w := SimWorld.new(11)
	w.use_accumulator = false
	var e := w.entities
	var mine := _add_tank(w, "mine", 0, 0.0, 0.0, 600.0, SimTypes.ArmorType.COMPOSITE, 0)
	var theirs := _add_tank(w, "theirs", 1, 500.0, 0.0, 380.0, SimTypes.ArmorType.COMPOSITE, 1)

	w.commands.move(0, mine, 100.0, 100.0)
	w.commands.move(0, theirs, 0.0, 0.0)          # player 0 ordering player 1's tank
	w.commands.set_emcon(0, mine, SimTypes.Emcon.SILENT)
	w.run_ticks(1)

	_ok("a legal order is executed", e.has_dest[mine] == 1
			and e.dest_x[mine] == 100.0)
	_ok("AN ORDER TO SOMEBODY ELSE'S UNIT IS REJECTED, not merely discouraged",
		e.has_dest[theirs] == 0 and w.commands.rejected == 1)
	_ok("a legal state change goes through",
		e.emcon[mine] == SimTypes.Emcon.SILENT)
	_ok("the queue is drained every tick", w.commands.size() == 0)

	# An order to a dead unit is rejected rather than crashing.
	e.kill(mine)
	w.commands.move(0, mine, 5.0, 5.0)
	w.run_ticks(1)
	_ok("an order to a dead unit is rejected", w.commands.rejected == 2)

	# An out-of-range index must not index a Packed array out of bounds.
	w.commands.move(0, 9999, 0.0, 0.0)
	w.commands.move(0, -3, 0.0, 0.0)
	w.run_ticks(1)
	_ok("an out-of-range unit index is rejected without crashing",
		w.commands.rejected == 4)


# ── the AI fence: docs/09 §1 ─────────────────────────────────────────────────

func _suite_ai_fence() -> void:
	_suite("The AI cannot see what a player could not (docs/09 §1)")

	var w := SimWorld.new(13)
	w.use_accumulator = false
	var e := w.entities
	var ai_tank := _add_tank(w, "ai tank", 1, 0.0, 0.0, 380.0,
		SimTypes.ArmorType.COMPOSITE, 1)
	var human_tank := _add_tank(w, "human tank", 0, 400.0, 0.0, 600.0,
		SimTypes.ArmorType.COMPOSITE_HEAVY, 0)
	e.structure[human_tank] = 30.0     # the "unit is at 30%" leak from docs/09 §1.2
	e.lose_component(human_tank, SimTypes.Component.MOBILITY)

	var setup := SimPlayerSetup.new({"name": "AI", "faction": SimPlayerSetup.Faction.RUSSIA})
	var director := w.add_ai(1, 1, setup)
	var view := director.view

	_ok("the director is constructed from a world view and nothing else",
		view is SimAiWorldView)

	# THE structural test. Enumerate everything in the world, feed each index to
	# the AI's own-forces view, and require that only its own units answer.
	var leaked := 0
	var denied_before := view.forces.denied_queries
	for i in range(e.count()):
		var owned: bool = e.owner[i] == 1
		if owned:
			continue
		# Every accessor, against a unit it does not own.
		if view.forces.owns(i): leaked += 1
		if view.forces.structure_fraction(i) != 0.0: leaked += 1
		if view.forces.position(i) != PackedFloat32Array([0.0, 0.0, 0.0]): leaked += 1
		if view.forces.components_lost(i) != 0: leaked += 1
		if view.forces.can_fire(i): leaked += 1
		if view.forces.unit_name(i) != "": leaked += 1
		if view.forces.category(i) != -1: leaked += 1
	_ok("NO accessor returns anything for a unit the AI does not own", leaked == 0,
		"%d leak(s)" % leaked)
	_ok("and every refusal is counted rather than silently swallowed",
		view.forces.denied_queries > denied_before,
		"%d refused" % (view.forces.denied_queries - denied_before))

	_ok("its own units answer normally",
		view.forces.owns(ai_tank) and view.forces.unit_name(ai_tank) == "ai tank")
	_ok("and the enumeration contains only its own",
		view.forces.indices() == PackedInt32Array([ai_tank]))

	# There must be no route from the view back to ground truth.
	var reachable := true
	for m in ["entities", "world", "store", "all_units", "enemy_units",
			"unit_at", "ground_truth"]:
		if view.has_method(m) or m in view:
			reachable = false
	_ok("SimAiWorldView exposes no entity store and no all-units query", reachable)

	# The one legitimate input, and it is opaque.
	_ok("it is handed its own faction's track table",
		view.tracks != null and view.tracks.faction == 1)
	_ok("a track carries an opaque id, not a pointer to an entity (docs/09 §1.3)",
		not ("target_entity_id" in SimTrack.new()))

	# The null-sensor test from docs/09 §1.5, in its cheapest form: an AI with
	# no sensors holds no tracks, so it has nothing to act on.
	w.run_ticks(20)
	_ok("an AI with no sensors holds no tracks at all",
		view.tracks.count() == 0, "%d track(s)" % view.tracks.count())

	# And it cannot order the human's army even if it names it.
	view.order_move(human_tank, 0.0, 0.0)
	w.run_ticks(1)
	_ok("an AI ordering a human unit is rejected at the command boundary",
		e.has_dest[human_tank] == 0 and w.commands.rejected >= 1)


# ── determinism, docs/06 ─────────────────────────────────────────────────────

func _suite_determinism() -> void:
	_suite("Determinism survives the new state (docs/06)")

	var h1 := _spine_scenario(2024)
	var h2 := _spine_scenario(2024)
	_ok("the same seed replays to an identical hash", h1 == h2, "0x%x" % h1)

	# The hash must actually WATCH the new state, or it certifies nothing.
	var w := SimWorld.new(5)
	w.use_accumulator = false
	var t := _add_tank(w, "tank", 0, 0.0, 0.0, 600.0, SimTypes.ArmorType.COMPOSITE)
	var base := w.state_hash()
	w.entities.structure[t] = 40.0
	_ok("the state hash notices a change in structure", w.state_hash() != base)
	w.entities.structure[t] = 100.0
	w.entities.lose_component(t, SimTypes.Component.FIREPOWER)
	_ok("and a component loss", w.state_hash() != base)

	var w2 := SimWorld.new(5)
	w2.use_accumulator = false
	var t2 := _add_tank(w2, "tank", 0, 0.0, 0.0, 600.0, SimTypes.ArmorType.COMPOSITE)
	w2.entities.set_destination(t2, 90.0, 12.0)
	_ok("and an outstanding move order", w2.state_hash() != base)

	# Subsystem RNG streams must be independent, or a change in one system's
	# roll count reshuffles every other system's replay.
	var w3 := SimWorld.new(99)
	var streams := [w3.movement.rng.state(), w3.damage.rng.state(),
		w3.economy.rng.state(), w3.munitions.rng.state()]
	var unique := true
	for i in range(streams.size()):
		for j in range(i + 1, streams.size()):
			if streams[i] == streams[j]:
				unique = false
	_ok("each subsystem draws from its own forked stream", unique)

	# Ordered iteration everywhere the order could matter.
	var w4 := SimWorld.new(3)
	for pid in [5, 1, 9, 3]:
		w4.add_ai(pid, pid, SimPlayerSetup.new())
	_ok("AI players are iterated in ascending id order, never Dictionary order",
		w4.ai_player_ids() == [1, 3, 5, 9])


func _spine_scenario(seed_value: int) -> int:
	var w := SimWorld.new(seed_value)
	w.use_accumulator = false
	var e := w.entities
	var a := _add_tank(w, "a", 0, 0.0, 0.0, 600.0, SimTypes.ArmorType.COMPOSITE_HEAVY, 0)
	var b := _add_tank(w, "b", 1, 900.0, 0.0, 380.0, SimTypes.ArmorType.COMPOSITE, 1)
	e.set_velocity(b, -4.0, 0.0, 0.0)
	w.commands.move(0, a, 300.0, 40.0)
	w.commands.set_emcon(1, b, SimTypes.Emcon.SILENT)
	w.run_ticks(60)
	return w.state_hash()


# ── honesty ──────────────────────────────────────────────────────────────────

func _suite_honesty() -> void:
	## THIS SUITE WAS INVERTED, DELIBERATELY, AND HERE IS WHY.
	##
	## It used to assert that damage, movement, economy and the AI were STUBS
	## and said so -- which was the correct assertion for a spine whose four
	## subsystems had not been written yet. They have been written. The old
	## assertions did not fail because something broke; they failed because
	## the thing they were guarding against stopped being true, and a test
	## that asserts a stub is a stub is a test that must be rewritten the day
	## the stub is filled in.
	##
	## What is worth keeping is the PROPERTY, not the polarity:
	## subsystem_status() and describe() must tell the truth about what is
	## wired, whichever way the truth currently runs. So the suite now asserts
	## that the four report themselves as real AND that each one actually does
	## the thing it claims -- which is a strictly stronger check than the one
	## it replaces, because a subsystem cannot pass it by lying.
	_suite("The spine reports accurately what is and is not built")

	var w := SimWorld.new(1)
	var st := w.subsystem_status()
	_ok("damage reports itself implemented", st["damage"] == true)
	_ok("movement reports itself implemented", st["movement"] == true)
	_ok("economy reports itself implemented", st["economy"] == true)
	# There is no AI in a bare world, so the honest answer is still false --
	# subsystem_status() asks whether any registered director is real.
	_ok("a world with no AI registered says so", st["ai"] == false)
	_ok("and describe() no longer lists the three as missing",
		not w.describe().contains("NOT IMPLEMENTED: movement, damage, economy"))

	# And each claim is cashed. A subsystem that reports true and does nothing
	# is worse than one that reports false.
	var e := w.entities
	var t := _add_tank(w, "tank", 0, 0.0, 0.0, 600.0, SimTypes.ArmorType.COMPOSITE)
	var before := e.structure[t]
	var outcome := w.damage.resolve_impact(t, SimTypes.Facet.FRONT,
		SimTypes.DamageClass.KE, 2400.0)
	_ok("the damage layer resolves an impact and takes structure off",
		outcome.resolved and e.structure[t] < before,
		"%.1f -> %.1f" % [before, e.structure[t]])
	w.use_terrain(SimTerrain.new(64, 64, 200.0, "flat"))
	e.set_mobility(t, 12.0, 2.0, 0.6)
	_ok("the movement layer plans a real path",
		not w.movement.plan_path(t, 900.0, 900.0).is_empty())
	# The economy still refuses to spawn for a player who does not exist --
	# that was never a stub, it is the ownership rule.
	_ok("the economy refuses to spawn for an unregistered player",
		w.economy.spawn_unit(0, "mbt", 0.0, 0.0) == -1)
	w.economy.add_player(0, 5000.0, 4, 6)
	_ok("and spawns a fully configured unit for one that does",
		w.economy.spawn_unit(0, "mbt", 400.0, 400.0) >= 0)

	# But the seam they plug into is real: a round that arrives must produce an
	# impact record with a facet derived from geometry, ready for the resolver.
	var w2 := SimWorld.new(21)
	w2.use_accumulator = false
	var e2 := w2.entities
	var gun := e2.add("gun", 0, 0.0, 2.0, 0.0, SimSignature.new(20.0))
	var tgt := e2.add("tgt", 1, 0.0, 2.0, 1200.0, SimSignature.new(20.0))
	e2.heading_rad[tgt] = PI          # facing back down the line of fire
	var round_def := SimMunitionDef.new({
		"name": "APFSDS", "tier": SimMunitionDef.Tier.B,
		"guidance": SimTypes.Guidance.UNGUIDED,
		"fuze": SimMunitionDef.Fuze.CONTACT,
		"muzzle_velocity": 1700.0, "max_flight_seconds": 20.0,
		"damage_class": SimTypes.DamageClass.KE, "penetration_mm": 540.0,
	})
	w2.munitions.fire(round_def, gun, tgt, null)
	var arrivals: Array = []
	for _i in range(60):
		w2.run_ticks(1)
		arrivals = w2.munitions.arrivals()
		if not arrivals.is_empty():
			break
	_ok("a round that arrives produces an impact record", not arrivals.is_empty())
	if not arrivals.is_empty():
		var im := arrivals[0] as SimImpact
		_ok("carrying the facet impact geometry chose, not a roll",
			im.facet == SimTypes.Facet.FRONT,
			SimTypes.facet_name(im.facet))
		_ok("the range it actually flew, for the KE curve",
			im.range_m > 1000.0, "%.0f m" % im.range_m)
		_ok("and the round's own penetration figure",
			im.penetration_mm == 540.0
				and im.damage_class == SimTypes.DamageClass.KE)
		_ok("which is exactly what SimArmor needs to answer the question",
			SimArmor.penetrates(
				SimArmor.penetration_at_range_mm(im.penetration_mm,
					im.damage_class, im.range_m),
				380.0, SimTypes.ArmorType.COMPOSITE, im.damage_class))
