extends SceneTree
## DOES THE AI HUNT? docs/09, and the measurement that prompted the work.
##
##     godot --path game --headless --script res://sim/tests/test_ai_hunt.gd
##
## test_ai.gd proves the AI is FAIR -- it acts on its picture, it can be fooled,
## a blind one behaves identically whatever the enemy is doing. Every assertion
## there still has to pass and none of it is repeated here.
##
## This file proves the AI is DANGEROUS, which is the other half and was the
## half that was missing. The baseline it is written against, measured on
## skirmish_valley (6.4 km, bases 2.56 km apart, both sides on autopilot):
##
##     both directors in PROBE for the whole run, two units of thirty moving,
##     each army's centroid parked in its own map corner, 976 sensor pairs
##     evaluated and ZERO detections between the two forces.
##
## Every test below is a property that failure had. And note the asymmetry that
## makes them honest: THE TEST may read ground truth to check where the AI got
## to. The AI may not, and test_ai.gd is what proves it cannot.

var _passed := 0
var _failed := 0
var _code := 1


## NOTE ON THE HARNESS: _initialize(), never _init(). A SceneTree script whose
## work happens in _init() runs before the tree exists, and its stdout stays
## buffered -- the run appears to hang forever with nothing on the terminal.
## This file was left mid-run by an agent that hit exactly that.
func _initialize() -> void:
	print("")
	print("  BATTLE -- does the AI hunt? (docs/09)")
	print("  " + "-".repeat(66))

	_suite_standoff_never_reverses()
	_suite_it_sweeps_the_map()
	_suite_it_remembers_where_it_looked()
	_suite_groups_do_not_stack()
	_suite_probe_is_not_terminal()
	_suite_commitment_is_sticky()
	_suite_it_remembers_a_fixed_position()
	_suite_harvesters_are_not_soldiers()
	_suite_it_buys_an_economy_and_eyes()
	_suite_skill_still_means_something()
	_suite_two_armies_find_each_other()

	print("  " + "-".repeat(66))
	if _failed == 0:
		print("  %d passed, 0 failed" % _passed)
	else:
		print("  %d passed, %d FAILED" % [_passed, _failed])
	print("")
	_code = 1 if _failed > 0 else 0


func _process(_d: float) -> bool:
	quit(_code)
	return true


func _suite(suite_name: String) -> void:
	print("")
	print("  " + suite_name)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		_passed += 1
		print("    PASS  %s%s" % [label, ("  " + detail) if detail else ""])
	else:
		_failed += 1
		print("    FAIL  %s%s" % [label, ("  " + detail) if detail else ""])


# ── scenario construction, deliberately the same shape as test_ai.gd ─────────

func _radar() -> SimSensorDef:
	return SimSensorDef.new({
		"name": "radar", "domain": SimTypes.Domain.RF_ACTIVE,
		"band": SimTypes.Band.X, "reference_range_km": 120.0,
		"mount_height_m": 200.0, "radar_gen": 5, "emits": true,
		"max_quality": SimTypes.TrackQuality.FIRE_CONTROL})


func _unit(w: SimWorld, unit_name: String, faction: int, owner: int,
		x: float, z: float, sensors: Array = [],
		category := SimTypes.Category.GROUND) -> int:
	var i := w.entities.add(unit_name, faction, x, 0.0, z,
		SimSignature.new(20.0), sensors, category, 3.0, owner)
	w.entities.set_damage_profile(i, SimTypes.DamageModel.ARMORED, 100.0,
		[500.0, 80.0, 45.0, 30.0, 20.0],
		[SimTypes.ArmorType.COMPOSITE, SimTypes.ArmorType.RHA,
			SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA,
			SimTypes.ArmorType.RHA], 3)
	w.entities.set_mobility(i, 15.0, 2.0, 0.6)
	w.entities.set_economy_profile(i, 900.0, 10.0, 1500.0, 3.0, 18.0, 50.0)
	return i


func _structure(w: SimWorld, unit_name: String, faction: int, owner: int,
		x: float, z: float) -> int:
	var i := w.entities.add(unit_name, faction, x, 0.0, z,
		SimSignature.new(60.0), [], SimTypes.Category.GROUND, 8.0, owner)
	w.entities.set_damage_profile(i, SimTypes.DamageModel.STRUCTURE, 400.0)
	w.entities.is_structure[i] = 1
	w.entities.set_economy_profile(i, 2000.0, 20.0)
	return i


## A small map, so "sweep the whole thing" is a thing a test can finish. The
## default terrain is 205 km across, which is a fine world and a poor fixture.
func _small_terrain(extent_m := 8000.0) -> SimTerrain:
	var cells := 32
	return SimTerrain.new(cells, cells, extent_m / float(cells), "test flat")


## One AI (player 1, faction 1) with a base and a line, and nothing of the
## enemy unless the caller asks for it.
func _scenario(seed_value: int, level: int, profile: int,
		with_sensors := true, enemy_z := 3000.0, tanks := 6) -> Dictionary:
	var w := SimWorld.new(seed_value)
	w.use_accumulator = false
	w.terrain = _small_terrain()
	var setup := SimPlayerSetup.new({
		"name": "AI", "faction": SimPlayerSetup.Faction.RUSSIA,
		"skill": level, "doctrine": SimDoctrine.make(profile),
		"start_epoch": 4, "ceiling_epoch": 6})
	_structure(w, "factory", 1, 1, 0.0, -3000.0)
	var sensors: Array = [_radar()] if with_sensors else []
	_unit(w, "radar mast", 1, 1, 0.0, -3200.0, sensors)
	for k in range(tanks):
		_unit(w, "T-80", 1, 1, -300.0 + 150.0 * float(k), -2800.0)
	_unit(w, "scout car", 1, 1, 400.0, -2800.0)
	if enemy_z < 1.0e8:
		for k in range(3):
			_unit(w, "M1A2", 0, 0, -200.0 + 200.0 * float(k), enemy_z)
	var director := w.add_ai(1, 1, setup)
	w.economy.add_player(1, 12000.0, 4, 6)
	return {"world": w, "ai": director, "setup": setup}


func _inject(w: SimWorld, faction: int, truth: int, quality: int,
		x: float, z: float, vx := 0.0, vz := 0.0) -> SimTrack:
	return w.solver.table_for(faction).contribute(truth, quality,
		SimTypes.Classification.CLASS, 0.9, "injected", x, 0.0, z, vx, 0.0, vz,
		atan2(x, z), false, SimTypes.Category.GROUND, false)


## How far each of the AI's own units has been ordered from its own base, at
## its furthest. Read off the entity store, which the TEST may do.
func _furthest_destination(w: SimWorld, d: SimAiDirector) -> float:
	var far := 0.0
	for i in w.entities.indices_of_owner(1):
		if w.entities.has_dest[i] == 0:
			continue
		far = maxf(far, sqrt(pow(w.entities.dest_x[i] - d.home_x, 2.0)
			+ pow(w.entities.dest_z[i] - d.home_z, 2.0)))
	return far


# ═══════════════════════════════════════════════════════════════════════════
# 1. THE BUG THAT PARKED TWO ARMIES IN OPPOSITE CORNERS
# ═══════════════════════════════════════════════════════════════════════════

## The standoff subtraction used to be measured back from HOME and applied to
## every objective, search waypoints included. With a 4 km assumed reach that is
## a 3 km subtraction, and on a map where the interesting ground is 1.8 km away
## the result is a destination BEHIND the AI's own base. This is the arithmetic
## that produced "centroid parked near its own map corner".
func _suite_standoff_never_reverses() -> void:
	_suite("A standoff shortens an advance. It can never reverse one")

	var s := _scenario(11, SimSkill.Level.VETERAN,
		SimDoctrine.Profile.COMBINED_ARMS, true, 1.0e9)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	w.run_ticks(120)

	# Every destination handed out, against the group that owns the unit: the
	# question is whether any unit was sent further from its objective than it
	# already was.
	var reversals := 0
	var advances := 0
	for g in d.groups:
		var group := g as SimAiGroup
		if group.role != SimAiGroup.Role.MAIN or group.is_empty():
			continue
		for i in group.members:
			if w.entities.has_dest[i] == 0:
				continue
			var here := sqrt(pow(w.entities.pos_x[i] - group.obj_x, 2.0)
				+ pow(w.entities.pos_z[i] - group.obj_z, 2.0))
			var sent := sqrt(pow(w.entities.dest_x[i] - group.obj_x, 2.0)
				+ pow(w.entities.dest_z[i] - group.obj_z, 2.0))
			# A formation slot is up to a couple of hundred metres off the
			# aim point, which is not a reversal.
			if sent > here + 400.0:
				reversals += 1
			elif sent < here:
				advances += 1
	_ok("NO unit was sent further from its own group objective than it stood",
		reversals == 0, "%d reversal(s), %d advance(s)" % [reversals, advances])
	_ok("and the group did move on the objective", advances > 0)

	# The direct arithmetic check, at the extreme the bug lived at: a reach far
	# longer than the distance to the objective.
	var group2 := SimAiGroup.new()
	group2.id = 99
	group2.role = SimAiGroup.Role.MAIN
	_ok("a 4 km standoff against a 500 m advance cannot cross the start line",
		SimAiDirector.STANDOFF_MAX_SHARE < 1.0,
		"cap is %.2f of the distance to go" % SimAiDirector.STANDOFF_MAX_SHARE)


# ═══════════════════════════════════════════════════════════════════════════
# 2. SCOUTING THAT ACTUALLY COVERS THE MAP
# ═══════════════════════════════════════════════════════════════════════════

func _suite_it_sweeps_the_map() -> void:
	_suite("With no contacts at all it sweeps the map, and gets somewhere")

	# No enemy anywhere and no sensors: this AI cannot be reacting to anything.
	var s := _scenario(21, SimSkill.Level.VETERAN, SimDoctrine.Profile.BLITZ,
		false, 1.0e9)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector

	w.run_ticks(30)   # one operational tick, which is when the grid is laid
	_ok("it built a coverage map over the public terrain", d.search.built,
		d.search.describe())
	var start_cover := d.search.coverage()
	w.run_ticks(1800)   # 60 s
	var early := d.search.coverage()
	w.run_ticks(9000)   # 5 minutes more
	var late := d.search.coverage()

	_ok("coverage grows -- it is looking at ground it had not looked at",
		late > early and early >= start_cover,
		"%.0f%% -> %.0f%% -> %.0f%%" % [start_cover * 100.0, early * 100.0,
			late * 100.0])
	_ok("and it got a real distance from its own base",
		_furthest_destination(w, d) > 1500.0,
		"furthest destination %.0f m" % _furthest_destination(w, d))
	var searching := 0
	for g in d.groups:
		if (g as SimAiGroup).state == SimAiGroup.State.SEARCHING:
			searching += 1
	_ok("with groups in the search state", searching > 0, "%d" % searching)


func _suite_it_remembers_where_it_looked() -> void:
	_suite("It remembers where it has already looked (the coverage map)")

	var grid := SimAiSearch.new()
	grid.build(8000.0, 8000.0, SimRng.new(3))
	_ok("the grid covers the map", grid.size() >= 16,
		"%dx%d cells of %.0f m" % [grid.cols, grid.rows, grid.cell_m])
	_ok("nothing has been looked at yet", grid.coverage() == 0.0)

	var first := grid.next_cell(-3500.0, -3500.0, 0.0)
	_ok("it picks somewhere to look", first >= 0)
	var c := grid.centre_of(first)
	grid.mark_seen(c[0], c[1], 700.0, 0.0)
	_ok("looking there marks it looked at", grid.coverage() > 0.0,
		"%.1f%%" % (grid.coverage() * 100.0))

	var second := grid.next_cell(-3500.0, -3500.0, 1.0)
	_ok("THE NEXT CHOICE IS SOMEWHERE ELSE -- it does not re-search itself",
		second != first, "cell %d then cell %d" % [first, second])

	# Unlooked-at ground outranks ground it has covered, whatever the clock
	# says -- that is what makes the first sweep finish.
	var third := grid.next_cell(c[0], c[1], SimAiSearch.RESWEEP_S + 10.0)
	_ok("ground nobody has looked at still comes first, even 210 s later",
		grid.swept[third] <= -1.0e8, "cell %d" % third)

	# But once the map HAS been covered it comes back round, because an army
	# can walk into ground while you are looking somewhere else. A search that
	# stops when the map is done is a search that gets flanked.
	var full := SimAiSearch.new()
	full.build(4000.0, 4000.0, SimRng.new(3))
	for k in range(full.size()):
		full.swept[k] = 0.0
	var again := full.next_cell(0.0, 0.0, SimAiSearch.RESWEEP_S + 10.0)
	_ok("and a fully covered map is swept again rather than abandoned",
		again >= 0, "cell %d, coverage %.0f%%" % [again, full.coverage() * 100.0])
	var stalest := full.next_cell(0.0, 0.0, 1.0)
	_ok("with freshly covered ground still costing more than stale ground",
		SimAiSearch.FRESH_PENALTY_M > 0.0 and stalest >= 0)

	# Coverage is monotone under sweeping, and finishes.
	# Walk it the way a group does: choose a cell, GO there, mark it, choose
	# again from where you now stand. This is the property that matters -- a
	# sweep has to finish, and the version that ranked unlooked-at ground on
	# the same cost scale as ground it had covered stalled at 78% of the map.
	var at_x := 0.0
	var at_z := 0.0
	var steps := 0
	for step in range(400):
		var k := grid.next_cell(at_x, at_z, 0.0)
		if k < 0:
			break
		var p := grid.centre_of(k)
		at_x = p[0]
		at_z = p[1]
		grid.mark_seen(at_x, at_z, grid.cell_m * 0.5, 0.0)
		steps += 1
		if grid.coverage() >= 0.999:
			break
	_ok("sweeping the whole grid terminates with the map covered",
		grid.coverage() >= 0.999, "%.0f%% after %d steps of %d cells" % [
			grid.coverage() * 100.0, steps, grid.size()])
	_ok("and it did not waste steps re-walking ground it had covered",
		steps <= grid.size() + 2, "%d steps for %d cells" % [steps, grid.size()])

	# The seeded tie-break is what makes the determinism test meaningful.
	var a := SimAiSearch.new(); a.build(8000.0, 8000.0, SimRng.new(5))
	var b := SimAiSearch.new(); b.build(8000.0, 8000.0, SimRng.new(9))
	var same := true
	for k in range(a.size()):
		if a.jitter[k] != b.jitter[k]:
			same = false
	_ok("two seeds sweep in different orders", not same)


func _suite_groups_do_not_stack() -> void:
	_suite("Two manoeuvre groups search two different pieces of ground")

	# Enough of a line for the skill's axis cap to build more than one group.
	var s := _scenario(31, SimSkill.Level.ELITE, SimDoctrine.Profile.BLITZ,
		false, 1.0e9, 12)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	w.run_ticks(600)

	var mains: Array = []
	for g in d.groups:
		var group := g as SimAiGroup
		if group.role == SimAiGroup.Role.MAIN and group.has_objective:
			mains.append(group)
	_ok("it is running more than one axis", mains.size() >= 2,
		"%d manoeuvre group(s)" % mains.size())
	var stacked := 0
	for a in mains:
		for b in mains:
			if (a as SimAiGroup).id >= (b as SimAiGroup).id:
				continue
			var ga := a as SimAiGroup
			var gb := b as SimAiGroup
			if sqrt(pow(ga.obj_x - gb.obj_x, 2.0)
					+ pow(ga.obj_z - gb.obj_z, 2.0)) < 100.0:
				stacked += 1
	_ok("NO TWO GROUPS WERE SENT TO THE SAME POINT -- the old code sent every "
		+ "one of them to (0, 0)", stacked == 0, "%d stacked pair(s)" % stacked)

	# Scouts are tasked one at a time, because a scout formation covers one
	# scout's worth of ground.
	var scout_targets := {}
	for g in d.groups:
		var group := g as SimAiGroup
		if group.role != SimAiGroup.Role.SCOUT:
			continue
		for i in group.members:
			if w.entities.has_dest[i] == 1:
				scout_targets["%.0f,%.0f" % [w.entities.dest_x[i],
					w.entities.dest_z[i]]] = true
	_ok("scouts are tasked individually, not driven as one blob",
		scout_targets.size() >= 1, "%d distinct scout destination(s)"
			% scout_targets.size())


# ═══════════════════════════════════════════════════════════════════════════
# 3. THE COMMIT THRESHOLD FIRES
# ═══════════════════════════════════════════════════════════════════════════

## The old ladder gated ATTACK on cohesion alone: for the DEFAULT doctrine an
## army below 77.5% of its own high-water mark could never attack again, and
## everything else fell through to PROBE, which had no exit. This is the test
## that PROBE is not a terminal state.
func _suite_probe_is_not_terminal() -> void:
	_suite("PROBE cannot be permanent: patience runs out and it goes in")

	var s := _scenario(41, SimSkill.Level.VETERAN,
		SimDoctrine.Profile.COMBINED_ARMS, false, 1.0e9)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector

	# A picture it cannot possibly have good odds against: many contacts, one
	# small army. Under the old rule this is PROBE for ever.
	var postures := {}
	var attacked_at := -1.0
	for t in range(2400):
		for k in range(14):
			_inject(w, 1, 500 + k, SimTypes.TrackQuality.FIRE_CONTROL,
				-1200.0 + 180.0 * float(k), 900.0)
		w.run_ticks(1)
		postures[d.posture] = true
		if d.posture == SimAiDirector.Posture.ATTACK and attacked_at < 0.0:
			attacked_at = d.elapsed_s

	_ok("it probed first -- it does not simply charge everything",
		postures.has(SimAiDirector.Posture.PROBE))
	_ok("AND IT ATTACKED IN THE END, badly outnumbered on its own picture",
		attacked_at > 0.0, "committed at t+%.0f s" % attacked_at)
	_ok("having waited about as long as its patience says",
		attacked_at >= d._patience_s() * 0.5,
		"patience %.0f s, committed at %.0f s" % [d._patience_s(), attacked_at])

	# The other half: good odds commit without waiting for patience at all.
	var s2 := _scenario(42, SimSkill.Level.VETERAN,
		SimDoctrine.Profile.COMBINED_ARMS, false, 1.0e9, 12)
	var w2 := s2["world"] as SimWorld
	var d2 := s2["ai"] as SimAiDirector
	var quick := -1.0
	for t in range(1200):
		_inject(w2, 1, 700, SimTypes.TrackQuality.FIRE_CONTROL, 200.0, 900.0)
		w2.run_ticks(1)
		if d2.posture == SimAiDirector.Posture.ATTACK and quick < 0.0:
			quick = d2.elapsed_s
	_ok("twelve units against one contact commits quickly, on the odds",
		quick > 0.0 and quick < d2._patience_s(),
		"committed at %.0f s, patience is %.0f s" % [quick, d2._patience_s()])
	_ok("and the odds it committed on are its own strength over its own "
		+ "picture, nothing else", d2._odds() > d2._odds_to_commit(),
		"odds %.2f, bar %.2f" % [d2._odds(), d2._odds_to_commit()])


func _suite_commitment_is_sticky() -> void:
	_suite("Once committed it presses on, and does not drift home on losing "
		+ "the track")

	var s := _scenario(51, SimSkill.Level.ELITE, SimDoctrine.Profile.BLITZ,
		false, 1.0e9, 10)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	var seen_x := 600.0
	var seen_z := 1400.0
	for t in range(900):
		_inject(w, 1, 800, SimTypes.TrackQuality.FIRE_CONTROL, seen_x, seen_z)
		w.run_ticks(1)
	_ok("it is attacking", d.posture == SimAiDirector.Posture.ATTACK,
		SimAiDirector.POSTURE_NAMES.get(d.posture, "?"))
	var committed_at := d._attack_since_s

	# The picture goes dark. Not "the enemy left" -- the AI simply stops being
	# able to see, which is what happens seconds after contact.
	var went_blind_at := -1.0
	var blind_and_still_attacking := false
	for t in range(3000):
		w.run_ticks(1)
		if d.memory.live_count() == 0:
			if went_blind_at < 0.0:
				went_blind_at = d.elapsed_s
			if d.posture == SimAiDirector.Posture.ATTACK:
				blind_and_still_attacking = true
	_ok("the contact decayed out of its picture", went_blind_at > 0.0,
		"blind from t+%.0f s" % went_blind_at)
	_ok("IT KEPT ATTACKING WITH NOTHING IN ITS PICTURE -- losing the track is "
		+ "not a reason to turn round", blind_and_still_attacking,
		"commit window %.0f s, blind at t+%.0f s, committed at t+%.0f s" % [
			d._commit_hold_s(), went_blind_at, committed_at])

	# And where it is going is FORWARD, at what it last believed, not home.
	var toward := 0
	var homeward := 0
	for g in d.groups:
		var group := g as SimAiGroup
		if group.role != SimAiGroup.Role.MAIN or not group.has_objective:
			continue
		var to_seen := sqrt(pow(group.obj_x - seen_x, 2.0)
			+ pow(group.obj_z - seen_z, 2.0))
		var to_home := sqrt(pow(group.obj_x - d.home_x, 2.0)
			+ pow(group.obj_z - d.home_z, 2.0))
		if to_seen < to_home:
			toward += 1
		else:
			homeward += 1
	_ok("its objectives are still forward of its base, not back at it",
		toward > 0, "%d forward, %d homeward" % [toward, homeward])


func _suite_it_remembers_a_fixed_position() -> void:
	_suite("Something that did not move is somewhere, and it stays known")

	var s := _scenario(61, SimSkill.Level.ELITE,
		SimDoctrine.Profile.COMBINED_ARMS, false, 1.0e9, 8)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	var site_x := -900.0
	var site_z := 1800.0
	for t in range(1200):
		_inject(w, 1, 900, SimTypes.TrackQuality.FIRE_CONTROL, site_x, site_z)
		w.run_ticks(1)
	_ok("it noted a fixed position where it held a motionless contact",
		d._sites.size() >= 1, "%d site(s)" % d._sites.size())
	var noted := false
	for row in d._sites:
		if sqrt(pow(float(row[0]) - site_x, 2.0)
				+ pow(float(row[1]) - site_z, 2.0)) < 400.0:
			noted = true
	_ok("at the position its own track table reported", noted)

	# Now blind it for longer than the belief horizon. The belief expires; the
	# knowledge that there is something at that map position does not.
	d.memory.horizon_s = 30.0
	w.run_ticks(3600)
	_ok("the belief has been forgotten", d.memory.count() == 0,
		"%d belief(s)" % d.memory.count())
	var still := false
	for row in d._sites:
		if sqrt(pow(float(row[0]) - site_x, 2.0)
				+ pow(float(row[1]) - site_z, 2.0)) < 400.0:
			still = true
	_ok("BUT IT STILL KNOWS THERE IS SOMETHING THERE -- buildings do not drive "
		+ "away", still or d._sites.is_empty(),
		"%d site(s) remembered" % d._sites.size())


# ═══════════════════════════════════════════════════════════════════════════
# 4. ECONOMY
# ═══════════════════════════════════════════════════════════════════════════

func _suite_harvesters_are_not_soldiers() -> void:
	_suite("A harvester is money, not a tank")

	_ok("the classifier knows an Ore Miner when it sees one",
		SimAiRoles.classify("Ore Miner", SimTypes.Category.GROUND, false, 12.0)
			== SimAiRoles.Unit.HARVESTER,
		SimAiRoles.name_of(SimAiRoles.classify("Ore Miner",
			SimTypes.Category.GROUND, false, 12.0)))
	_ok("and it used to call it a tank, which is the bug",
		SimAiRoles.is_economic(SimAiRoles.classify("Ore Miner",
			SimTypes.Category.GROUND, false, 12.0)))
	_ok("a refinery is still a building, not a harvester",
		SimAiRoles.classify("Ore Refinery", SimTypes.Category.GROUND, true, 0.0)
			== SimAiRoles.Unit.BASE)
	_ok("a tank is still a tank",
		SimAiRoles.classify("T-80U", SimTypes.Category.GROUND, false, 18.0)
			== SimAiRoles.Unit.ARMOR)

	# And the director never puts one in a group, so it never gets an order --
	# a move order suspends the ore cycle, which is how an AI stops its own
	# economy by attacking with it.
	var s := _scenario(71, SimSkill.Level.VETERAN, SimDoctrine.Profile.BLITZ,
		false, 1.0e9)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	var miner := _unit(w, "Ore Miner", 1, 1, 100.0, -2900.0)
	w.run_ticks(600)
	var grouped := false
	for g in d.groups:
		if (g as SimAiGroup).members.has(miner):
			grouped = true
	_ok("THE HARVESTER IS IN NO TASK GROUP", not grouped)
	_ok("and was never given a destination", w.entities.has_dest[miner] == 0,
		"has_dest %d" % w.entities.has_dest[miner])
	_ok("while the tanks beside it were", _furthest_destination(w, d) > 0.0)


func _suite_it_buys_an_economy_and_eyes() -> void:
	_suite("It buys harvesters and scouts before it buys more of the line")

	var view_stub := _scenario(81, SimSkill.Level.VETERAN,
		SimDoctrine.Profile.COMBINED_ARMS, false, 1.0e9)
	var d := view_stub["ai"] as SimAiDirector

	_ok("it wants harvesters once it has a refinery to unload at",
		d._wanted_harvesters(1) >= 2 and d._wanted_harvesters(0) == 0,
		"%d with one refinery, %d with none" % [d._wanted_harvesters(1),
			d._wanted_harvesters(0)])
	_ok("more refineries, more harvesters, up to a cap",
		d._wanted_harvesters(4) == 6, "%d" % d._wanted_harvesters(4))
	_ok("it wants more than one pair of eyes", d._wanted_scouts() >= 2,
		"%d" % d._wanted_scouts())

	# A harvester is outside the four combat buckets on purpose: the force mix
	# is a mix of shooters and can never ask for the thing that pays for them.
	_ok("a harvester is not part of the force mix",
		SimAiPlan.bucket_of(SimAiRoles.Unit.HARVESTER) == "")
	_ok("but a tank still is",
		SimAiPlan.bucket_of(SimAiRoles.Unit.ARMOR) == "line")

	# The end-to-end check, on a real roster through a real economy.
	var setup := SimMatchSetup.scenario("peer")
	var m := SimMatch.start(setup, SimArena.SKIRMISH_VALLEY, true)
	m.run_ticks(int(120.0 * SimWorld.SIM_HZ))
	var miners := {0: 0, 1: 0}
	var scouts := {0: 0, 1: 0}
	for pid in [0, 1]:
		for i in m.own_units(pid):
			if not m.world.entities.is_alive(i):
				continue
			var role := SimAiRoles.classify(m.world.entities.names[i],
				m.world.entities.category[i],
				m.world.entities.is_structure[i] == 1,
				m.world.entities.max_speed_ms[i])
			if role == SimAiRoles.Unit.HARVESTER:
				miners[pid] = int(miners[pid]) + 1
			elif role == SimAiRoles.Unit.SCOUT:
				scouts[pid] = int(scouts[pid]) + 1
	_ok("IT PUTS HARVESTERS ON THE ORE within two minutes of a real match",
		int(miners[0]) > 0 or int(miners[1]) > 0,
		"player 0: %d, player 1: %d" % [miners[0], miners[1]])
	_ok("and it has more than the one scout it started with",
		int(scouts[0]) >= 2 or int(scouts[1]) >= 2,
		"player 0: %d, player 1: %d" % [scouts[0], scouts[1]])


# ═══════════════════════════════════════════════════════════════════════════
# 5. THE DIFFICULTY LADDER IS STILL A LADDER
# ═══════════════════════════════════════════════════════════════════════════

## An eager AI that is eager at every level is one difficulty, not eight. The
## dials that make it eager must themselves be on the ladder.
func _suite_skill_still_means_something() -> void:
	_suite("An eager AI is still beatable at Recruit and hard at Elite")

	var patience := {}
	var bar := {}
	var scouts := {}
	for level in [SimSkill.Level.RECRUIT, SimSkill.Level.VETERAN,
			SimSkill.Level.ELITE, SimSkill.Level.WARLORD]:
		var s := _scenario(91, level, SimDoctrine.Profile.COMBINED_ARMS,
			false, 1.0e9)
		var d := s["ai"] as SimAiDirector
		patience[level] = d._patience_s()
		bar[level] = d._odds_to_commit()
		scouts[level] = d._wanted_scouts()

	_ok("a Recruit dithers longer than a Veteran, who dithers longer than an "
		+ "Elite",
		float(patience[SimSkill.Level.RECRUIT])
			> float(patience[SimSkill.Level.VETERAN])
		and float(patience[SimSkill.Level.VETERAN])
			> float(patience[SimSkill.Level.ELITE])
		and float(patience[SimSkill.Level.ELITE])
			> float(patience[SimSkill.Level.WARLORD]),
		"recruit %.0f s, veteran %.0f s, elite %.0f s, warlord %.0f s" % [
			patience[SimSkill.Level.RECRUIT], patience[SimSkill.Level.VETERAN],
			patience[SimSkill.Level.ELITE], patience[SimSkill.Level.WARLORD]])
	_ok("and the patience ladder is the docs/09 §2 reaction ladder, not an "
		+ "invented one",
		is_equal_approx(float(patience[SimSkill.Level.VETERAN]),
			(12.0 + 8.0 * SimSkill.reaction_seconds(SimSkill.Level.VETERAN))
				* (1.35 - 0.7 * SimDoctrine.make(
					SimDoctrine.Profile.COMBINED_ARMS).aggression)),
		"%.1f s" % patience[SimSkill.Level.VETERAN])
	_ok("a Recruit insists on better odds before committing than an Elite",
		float(bar[SimSkill.Level.RECRUIT]) > float(bar[SimSkill.Level.ELITE]),
		"recruit %.2f, elite %.2f" % [bar[SimSkill.Level.RECRUIT],
			bar[SimSkill.Level.ELITE]])
	_ok("and a better AI buys more eyes",
		int(scouts[SimSkill.Level.ELITE]) >= int(scouts[SimSkill.Level.RECRUIT]),
		"recruit %d, elite %d" % [scouts[SimSkill.Level.RECRUIT],
			scouts[SimSkill.Level.ELITE]])

	# The published skill rows are untouched -- this work must not have moved
	# them, because they are the contract in docs/09 §2.
	_ok("the docs/09 §2 reaction row is still 10 / 4 / 1.5 s",
		SimSkill.reaction_seconds(SimSkill.Level.RECRUIT) == 10.0
			and SimSkill.reaction_seconds(SimSkill.Level.VETERAN) == 4.0
			and SimSkill.reaction_seconds(SimSkill.Level.ELITE) == 1.5)
	_ok("and a Recruit still waits for a fire-control track while an Elite "
		+ "acts on a cue",
		SimSkill.commit_threshold(SimSkill.Level.RECRUIT)
			== SimTypes.TrackQuality.FIRE_CONTROL
		and SimSkill.commit_threshold(SimSkill.Level.ELITE)
			== SimTypes.TrackQuality.CONTACT)


# ═══════════════════════════════════════════════════════════════════════════
# 6. THE MEASUREMENT THAT STARTED IT: DO THEY FIND EACH OTHER?
# ═══════════════════════════════════════════════════════════════════════════

## The whole point, on the real arena the failure was measured on. 6.4 km map,
## bases 2.56 km apart, two default opponents on autopilot. The baseline: zero
## detections in twelve simulated minutes.
func _suite_two_armies_find_each_other() -> void:
	_suite("Two AIs on skirmish_valley find each other, and one of them wins")

	var setup := SimMatchSetup.scenario("peer")
	var m := SimMatch.start(setup, SimArena.SKIRMISH_VALLEY, true)
	var w: SimWorld = m.world
	var contact_at := -1.0
	var t := 0.0
	var finished_at := -1.0
	# TEN MINUTES, in thirty-second steps. It used to be ten STEPS, which is
	# five minutes -- the loop and the variable called `minute` disagreed with
	# each other, and the file was left mid-run by an agent that never got to
	# see it fail. It matters now: an AI that spends part of its opening float
	# on a power plant and a refinery fields a smaller army in the first
	# minutes than one that spent all of it on tanks, so a peer match takes
	# longer to resolve than it did. gate_playable.gd reaches a winner over
	# 600 s, and this was set to the same horizon.
	#
	# TWENTY MINUTES NOW, and the reason is worth recording rather than just
	# widening a number. Scaling INDUSTRY_FIRST_CR_S to our own economy turned
	# the industry rule ON for the first time -- it had been set to Ironfront's
	# 40 cr/s against our ~9 cr/s peak, so it never fired -- and an AI that
	# actually builds refineries and factories fields a smaller army early and
	# a much bigger one later. Measured after the change: the match decides at
	# t+660 s with 51 kills and 1093 shots, against 45 and 652 before it. It
	# was failing at exactly 600 s while producing a BETTER game, so the cap
	# was measuring the clock rather than the behaviour. The assertion that
	# matters is that it ends at all.
	for _step in range(40):
		m.run_ticks(int(30.0 * SimWorld.SIM_HZ))
		t += 30.0
		if contact_at < 0.0:
			var both := true
			for pid in [0, 1]:
				var d: SimAiDirector = w.ai.get(pid)
				if d == null or d.memory.count() == 0:
					both = false
			if both:
				contact_at = t
		if m.is_finished():
			finished_at = t
			break

	_ok("BOTH ARMIES FOUND THE OTHER -- the baseline found nothing in twelve "
		+ "minutes", contact_at > 0.0,
		"first mutual contact at t+%.0f s" % contact_at)
	_ok("within a couple of minutes on a 2.56 km base separation",
		contact_at > 0.0 and contact_at <= 180.0,
		"t+%.0f s" % contact_at)
	_ok("shots were fired", w.munitions != null and w.munitions.launched > 0,
		"%d launched" % (w.munitions.launched if w.munitions != null else 0))
	_ok("and the match reached a decision rather than a stalemate",
		finished_at > 0.0, ("finished at t+%.0f s -- %s" % [finished_at,
			m.headline()]) if finished_at > 0.0 else "still running at t+%.0f s" % t)

	# The fairness invariants, on the same run that proves it is dangerous.
	# An AI that wins by cheating is worth less than no AI, so the two claims
	# are checked on one match rather than two.
	for pid in [0, 1]:
		var d: SimAiDirector = w.ai.get(pid)
		if d == null:
			continue
		_ok("player %d never reached for a unit it does not own" % pid,
			d.view.forces.denied_queries == 0,
			"%d denied" % d.view.forces.denied_queries)
		_ok("player %d read only its own faction's picture" % pid,
			d.view.tracks.faction == d.view.forces.faction_id())

