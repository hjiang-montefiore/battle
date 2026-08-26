extends SceneTree
## Tests for the match layer: how a match STARTS, how units get weapons, how
## they choose targets, and how a match ENDS.
##
##     godot --path game --headless --script res://sim/tests/test_match.gd
##
## A separate file from run_sim_tests.gd and the other subsystem suites on
## purpose -- a shared test runner between agents is a shared merge conflict.
##
## What is asserted here is BEHAVIOUR through the whole stack, not the classes
## in isolation: a match is started from a real SimMatchSetup, driven through
## SimWorld's real tick loop, and the assertions are made on what a player
## would see. Where a claim in the design is at stake -- "the AI gets no
## information a human could not have", "a defeat takes nothing off the
## structure pool", "two runs of one seed are identical" -- the test asserts
## the claim rather than the implementation.

var _passed := 0
var _failed := 0


func _init() -> void:
	print("")
	print("  BATTLE -- match tests (start, victory, fire control, arsenal)")
	print("  " + "-".repeat(66))

	_suite_arsenal()
	_suite_start()
	_suite_spine_wiring()
	_suite_fire_control()
	_suite_information_fence()
	_suite_victory_condition()
	_suite_elimination()
	_suite_determinism()
	_suite_scene()

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


# ── fixtures ─────────────────────────────────────────────────────────────────

## A small, fast two-player match. GARRISON rather than ARMY keeps the tick
## cost down; nothing in these tests depends on the size of the force.
func _setup(seed_value := 4242, human := true,
		preset := SimPlayerSetup.ForcePreset.GARRISON) -> SimMatchSetup:
	var s := SimMatchSetup.new()
	s.name = "Test Skirmish"
	s.seed_value = seed_value
	s.add(SimPlayerSetup.new({
		"name": "You", "is_human": human, "team": 0,
		"faction": SimPlayerSetup.Faction.US,
		"start_epoch": 4, "ceiling_epoch": 5,
		"starting_forces": preset,
		"skill": SimSkill.Level.VETERAN}))
	s.add(SimPlayerSetup.new({
		"name": "Russia", "team": 1,
		"faction": SimPlayerSetup.Faction.RUSSIA,
		"start_epoch": 4, "ceiling_epoch": 5,
		"starting_forces": preset,
		"skill": SimSkill.Level.VETERAN}))
	return s


## Destroy every structure a player owns, through the damage layer -- which is
## the only thing permitted to kill anything.
func _raze_structures(m: SimMatch, player_id: int) -> int:
	var e := m.world.entities
	var n := 0
	for i in e.indices_of_owner(player_id):
		if e.is_structure[i] == 1:
			m.world.damage.apply_structure(i, e.structure_max[i] + 1.0, "test")
			n += 1
	return n


# ═══════════════════════════════════════════════════════════════════════════
# 1. THE ARSENAL. Until this existed nothing in the game could shoot.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_arsenal() -> void:
	_suite("Every role that should shoot has something to shoot with")

	_ok("a main battle tank is armed", SimArsenal.is_combatant("mbt"))
	_ok("so is an ATGM carrier", SimArsenal.is_combatant("atgm_carrier"))
	_ok("and a SAM launcher", SimArsenal.is_combatant("long_sam_launcher"))
	# docs/09's Interdiction doctrine only means something if the things it
	# hunts are defenceless.
	_ok("a fuel truck is not", not SimArsenal.is_combatant("fuel_truck"))
	_ok("nor is a search radar", not SimArsenal.is_combatant("search_radar"))
	_ok("nor is a refinery", not SimArsenal.is_combatant("refinery"))

	# docs/03: the ROUND carries the penetration, and it moves up the ladder
	# with the epoch while the tube stays a tube.
	var e1 := SimArsenal.loadout("mbt", 1)[0] as Dictionary
	var e7 := SimArsenal.loadout("mbt", 7)[0] as Dictionary
	var p1: float = (e1["munition"] as SimMunitionDef).penetration_mm
	var p7: float = (e7["munition"] as SimMunitionDef).penetration_mm
	_ok("an epoch 1 tank round quotes docs/03's ~180 mm at 2 km",
		absf(p1 - 180.0) < 1.0, "%.0f mm" % p1)
	_ok("an epoch 7 tank round quotes ~750 mm",
		absf(p7 - 750.0) < 1.0, "%.0f mm" % p7)
	_ok("and the tube gets longer legs with it",
		SimArsenal.reach_km("mbt", 7) > SimArsenal.reach_km("mbt", 1),
		"%.1f km vs %.1f km" % [SimArsenal.reach_km("mbt", 7),
			SimArsenal.reach_km("mbt", 1)])

	# docs/11 §5.3: the ATGM ladder turns wire-guided into fire-and-forget.
	var early := (SimArsenal.loadout("atgm_carrier", 2)[0]["weapon"] as SimWeaponDef)
	var late := (SimArsenal.loadout("atgm_carrier", 7)[0]["weapon"] as SimWeaponDef)
	_ok("an early ATGM is wire-guided (SACLOS)",
		early.guidance == SimTypes.Guidance.SACLOS)
	_ok("a late one is fire-and-forget",
		late.guidance == SimTypes.Guidance.IR_EO)

	# Target masks: a SAM that spends its magazine on tanks is a broken SAM.
	var sam := (SimArsenal.loadout("long_sam_launcher", 5)[0]["weapon"] as SimWeaponDef)
	_ok("a long-range SAM engages aircraft",
		sam.engages_category(SimTypes.Category.AIR))
	_ok("and refuses to be pointed at a tank",
		not sam.engages_category(SimTypes.Category.GROUND))
	var gun := (SimArsenal.loadout("mbt", 4)[0]["weapon"] as SimWeaponDef)
	_ok("a tank gun engages ground and surface, not aircraft",
		gun.engages_category(SimTypes.Category.GROUND)
			and not gun.engages_category(SimTypes.Category.AIR))
	# A weapon that never sets a mask must behave exactly as it did before the
	# field existed, or every existing test fixture silently changes meaning.
	_ok("a weapon with no mask set engages everything",
		SimWeaponDef.new({"name": "x"}).engages_category(SimTypes.Category.AIR))

	# Pure function of (role, epoch): same inputs, same mounts, every time.
	var a := SimArsenal.loadout("ifv", 5)
	var b := SimArsenal.loadout("ifv", 5)
	var same := a.size() == b.size()
	for k in range(mini(a.size(), b.size())):
		same = same and (a[k]["weapon"] as SimWeaponDef).name \
			== (b[k]["weapon"] as SimWeaponDef).name
	_ok("the loadout table is a pure function of role and epoch", same)

	# docs/06 forbids randf() outside a seeded stream anywhere in the sim.
	_ok("no file in sim/match/ calls randf, randi or the wall clock",
		_scan_for_nondeterminism().is_empty(),
		", ".join(_scan_for_nondeterminism()))


func _scan_for_nondeterminism() -> PackedStringArray:
	var bad := PackedStringArray()
	var dir := DirAccess.open("res://sim/match")
	if dir == null:
		return PackedStringArray(["sim/match is missing"])
	var names := dir.get_files()
	names.sort()
	for f in names:
		if not f.ends_with(".gd"):
			continue
		var text := FileAccess.get_file_as_string("res://sim/match/" + f)
		for line in text.split("\n"):
			var code := String(line).strip_edges()
			if code.begins_with("#") or code.begins_with("##"):
				continue
			# Strip a trailing comment so prose about randf() is not a failure.
			var hash_at := code.find("#")
			if hash_at >= 0:
				code = code.substr(0, hash_at)
			for forbidden in ["randf(", "randi(", "randf_range(",
					"Time.get_ticks_msec", "Time.get_ticks_usec"]:
				if forbidden in code:
					bad.append("%s: %s" % [f, code])
	return bad


# ═══════════════════════════════════════════════════════════════════════════
# 2. STARTING A MATCH
# ═══════════════════════════════════════════════════════════════════════════

func _suite_start() -> void:
	_suite("A SimMatchSetup becomes two bases on a map")

	var m := SimMatch.start(_setup())
	_ok("the setup validates", m.problems().is_empty(), ", ".join(m.problems()))
	_ok("the match is running", m.phase == SimMatch.Phase.RUNNING)
	_ok("on a skirmish-scale map, not a 500 km theatre",
		m.terrain.extent_x_m() < 40000.0,
		"%.1f km" % (m.terrain.extent_x_m() / 1000.0))

	var e := m.world.entities
	var mine := e.indices_of_owner(0)
	var theirs := e.indices_of_owner(1)
	_ok("both players have a force", mine.size() > 8 and theirs.size() > 8,
		"%d vs %d" % [mine.size(), theirs.size()])
	_ok("the two bases are far apart",
		m.base_position(0).distance_to(m.base_position(1)) > 4000.0,
		"%.0f m" % m.base_position(0).distance_to(m.base_position(1)))

	# A base that spawns unable to build anything is a dead match.
	var has_hq := false
	var has_factory := false
	for i in mine:
		var role := m.world.economy.role_of(i)
		has_hq = has_hq or role == "hq"
		has_factory = has_factory or role == "heavy_factory"
	_ok("with a headquarters", has_hq)
	_ok("and a factory", has_factory)
	_ok("and money to spend", m.credits(0) > 1000.0, "%.0f cr" % m.credits(0))
	_ok("the player can name something to build",
		not m.buildable_structures(0).is_empty(),
		"%d structures" % m.buildable_structures(0).size())
	_ok("and something to produce",
		not m.production_structures(0).is_empty(),
		"%d factories" % m.production_structures(0).size())

	# THE SEAM THAT WAS OPEN: nothing armed anything.
	var armed := 0
	var tanks := 0
	for i in mine:
		if m.world.weapons.is_armed(i):
			armed += 1
		if m.world.economy.role_of(i) == "mbt":
			tanks += 1
			if tanks == 1:
				_ok("a deployed tank has its gun", m.world.weapons.is_armed(i))
	_ok("the deployed force is armed", armed > 0, "%d of %d units" % [armed, mine.size()])

	# docs/08's coalition mechanic is "allies share a track table", and the
	# solver keys tables by faction -- so the sim's faction must be the team.
	_ok("the sim's faction id is the coalition, so allies share a picture",
		e.faction[mine[0]] == 0 and e.faction[theirs[0]] == 1)

	# Production must arm the units it turns out, or the seam is only half shut.
	var factory := m.production_structures(0)[0]
	var options := m.world.economy.production_options(0, factory)
	var want := ""
	for o in options:
		if SimArsenal.is_combatant(o):
			want = o
			break
	_ok("the factory can turn out something that shoots", want != "", want)
	if want != "":
		var before := e.count()
		m.world.commands.produce(0, factory, want)
		m.run_ticks(1200)
		var new_armed := 0
		for i in range(before, e.count()):
			if e.owner[i] == 0 and m.world.weapons.is_armed(i):
				new_armed += 1
		_ok("and a unit that rolls off the line comes out armed",
			new_armed > 0, "%d new units armed" % new_armed)


# ═══════════════════════════════════════════════════════════════════════════
# 3. THE TWO WIRES THE SPINE WAS MISSING
#
# The economy agent's report named these exactly: SimWorld never called
# economy.set_terrain() or economy.set_damage(), so in a real match every
# placement rule except prerequisites and affordability was silently skipped.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_spine_wiring() -> void:
	_suite("The economy can actually see the map it is building on")

	var m := SimMatch.start(_setup())
	_ok("the economy has the terrain", m.world.economy.terrain != null)
	_ok("and the damage layer", m.world.economy.damage != null)

	var d := m.world.economy.def_for(0, "power_plant")
	var far := m.terrain.extent_x_m()      # well outside the map
	_ok("so a structure cannot be placed off the map",
		m.world.economy.placement_problem(0, d, far, far) != "",
		m.world.economy.placement_problem(0, d, far, far))
	var base := m.base_position(0)
	_ok("and one placed inside the build radius is legal",
		m.world.economy.placement_problem(0, d, base.x + 60.0, base.y + 40.0) == "",
		m.world.economy.placement_problem(0, d, base.x + 60.0, base.y + 40.0))
	_ok("but one placed across the map is not",
		m.world.economy.placement_problem(0, d, -base.x, -base.y) != "")

	# The BUILD order, end to end, through the queue the player's mouse uses.
	var before := m.world.entities.count()
	var credits_before := m.credits(0)
	m.world.commands.build(0, "power_plant", base.x + 60.0, base.y + 40.0)
	m.run_ticks(2)
	_ok("a BUILD order puts a building site on the map immediately",
		m.world.entities.count() == before + 1)
	_ok("and charges for it", m.credits(0) < credits_before)
	var site := m.world.entities.count() - 1
	_ok("the site is not operational until it is finished",
		not m.world.economy.is_operational(site))
	_ok("but it is already an entity that can be shot at",
		m.world.entities.is_alive(site) and m.world.entities.is_structure[site] == 1)


# ═══════════════════════════════════════════════════════════════════════════
# 4. FIRE CONTROL. Which track, and on whose information.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_fire_control() -> void:
	_suite("Units pick their own targets, from their own picture, through the gate")

	# Nobody is ordered to attack anything. A modern tank and an obsolete one
	# in the open, and the modern one gets on with it.
	var kill := _engage(7, 1)
	var km := kill["match"] as SimMatch
	_ok("with no attack order given, a unit still engages what it can see",
		km.world.weapons.shots_fired > 0,
		"%d shots" % km.world.weapons.shots_fired)
	_ok("the fire control layer is what assigned the target",
		km.world.fire_control.assignments > 0, km.world.fire_control.describe())
	_ok("and the obsolete tank dies without anybody typing an order",
		not km.world.entities.is_alive(kill["b"]), km.world.damage.describe())

	# Weapons tight has to be a complete refusal, not a delay.
	var held := _engage(7, 1, 0.0, true, true)
	_ok("a unit told to hold fire does not fire",
		(held["match"] as SimMatch).world.weapons.shots_fired == 0)

	# ── docs/03's cliff, reached through the ARSENAL rather than a fixture ──
	# Only the old tank is armed, so every impact in this match is its own and
	# the counters mean what they say.
	var cliff := _engage(1, 7, 0.0, false, false)
	var cm := cliff["match"] as SimMatch
	var modern: int = cliff["b"]
	_ok("an epoch 1 gun does get its rounds onto an epoch 7 tank's front",
		cm.world.damage.resolver.impacts_resolved > 0,
		"%d impacts" % cm.world.damage.resolver.impacts_resolved)
	_ok("and not one of them penetrates", cm.world.damage.penetrations == 0,
		cm.world.damage.describe())
	_ok("a defeat takes NOTHING off the structure pool",
		absf(cm.world.entities.structure[modern]
			- cm.world.entities.structure_max[modern]) < 1e-4,
		"%.4f of %.4f" % [cm.world.entities.structure[modern],
			cm.world.entities.structure_max[modern]])

	# ── the property that makes this game about manoeuvre ──────────────────
	# docs/03's ladder quotes every generation's frontal RHAe ABOVE its own
	# generation's gun (620 mm of front against a 550 mm round at gen 3.5), so
	# two peer tanks nose to nose cannot resolve the fight. This is not a
	# balance accident -- it is the reason flanking, artillery and top attack
	# exist -- and it is asserted here so it cannot be tuned away by accident.
	var peer := _engage(4, 4)
	var pm := peer["match"] as SimMatch
	_ok("two peer tanks nose to nose shoot each other repeatedly",
		pm.world.damage.resolver.impacts_resolved >= 4,
		"%d impacts" % pm.world.damage.resolver.impacts_resolved)
	_ok("and neither can penetrate the other's frontal arc",
		pm.world.damage.penetrations == 0, pm.world.damage.describe())
	_ok("so both are still alive",
		pm.world.entities.is_alive(peer["a"]) and pm.world.entities.is_alive(peer["b"]))

	# The same two tanks, one of them caught side on.
	var flank := _engage(4, 4, PI * 0.5, false, false)
	var fm := flank["match"] as SimMatch
	_ok("the identical gun goes straight through the same tank's side",
		fm.world.damage.penetrations > 0, fm.world.damage.describe())
	_ok("and kills it", not fm.world.entities.is_alive(flank["b"]))


## Two lone tanks 1500 m apart on open ground, no bases and no AI: the smallest
## thing that proves automatic target selection reaches a kill.
##
##   target_heading  0 puts the target nose-on to the shooter; PI/2 puts it
##                   side on, so impact geometry chooses a different facet
##   arm_b           false leaves the target unarmed, so every counter in the
##                   match belongs to the shooter and means what it says
func _engage(epoch_a: int, epoch_b: int, target_heading := 0.0,
		hold_fire := false, arm_b := true, ticks := 900) -> Dictionary:
	var s := SimMatchSetup.new()
	s.seed_value = 991
	s.name = "Duel"
	s.add(SimPlayerSetup.new({"name": "A", "is_human": true, "team": 0,
		"faction": SimPlayerSetup.Faction.US, "start_epoch": epoch_a,
		"ceiling_epoch": epoch_a,
		"starting_forces": SimPlayerSetup.ForcePreset.NONE}))
	s.add(SimPlayerSetup.new({"name": "B", "team": 1,
		"faction": SimPlayerSetup.Faction.RUSSIA, "start_epoch": epoch_b,
		"ceiling_epoch": epoch_b,
		"starting_forces": SimPlayerSetup.ForcePreset.NONE}))
	var m := SimMatch.start(s, SimArena.OPEN_STEPPE)
	# No director on either side: this measures automatic fire control, and an
	# AI issuing move orders would be a second variable.
	m.world.remove_ai(1)
	var a := m.world.economy.place_starting_unit(0, "mbt", 0.0, 0.0, 0.0)
	# PI faces the shooter, so heading 0 here means "nose on".
	var b := m.world.economy.place_starting_unit(
		1, "mbt", 0.0, 1500.0, PI + target_heading)
	SimArsenal.arm(m.world.weapons, a, "mbt", epoch_a)
	if arm_b:
		SimArsenal.arm(m.world.weapons, b, "mbt", epoch_b)
	if hold_fire:
		m.world.fire_control.set_hold_fire(a, true)
		m.world.fire_control.set_hold_fire(b, true)
	m.run_ticks(ticks)
	return {"match": m, "a": a, "b": b}


# ═══════════════════════════════════════════════════════════════════════════
# 5. THE INFORMATION FENCE, extended to the new layer.
#
# docs/09 §1 is written about the AI, but the rule is about the SIMULATION:
# nothing decides from information the decider does not hold. The fire control
# layer is a decider, so it is fenced the same way and tested the same way.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_information_fence() -> void:
	_suite("Automatic fire decides from the track table and nothing else")

	var text := FileAccess.get_file_as_string("res://sim/match/sim_fire_control.gd")
	var offences := PackedStringArray()
	for line in text.split("\n"):
		var code := String(line).strip_edges()
		if code.begins_with("#"):
			continue
		var hash_at := code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		# _truth_index is the one field that turns a hypothesis into a pointer.
		# SimWeaponCycle is allowed to touch it (a round in flight needs an
		# index); a target SELECTOR never is.
		for forbidden in ["_truth_index", "indices_of_faction", "table_for(1"]:
			if forbidden in code:
				offences.append(code)
	_ok("it never resolves a track to an entity index",
		offences.is_empty(), ", ".join(offences))

	# Behavioural proof: an ally standing in the open is never engaged, and it
	# is never engaged because it is not IN the table -- not because a filter
	# caught it.
	var s := SimMatchSetup.new()
	s.seed_value = 55
	s.name = "Coalition"
	s.add(SimPlayerSetup.new({"name": "You", "is_human": true, "team": 0,
		"faction": SimPlayerSetup.Faction.US, "start_epoch": 4,
		"starting_forces": SimPlayerSetup.ForcePreset.NONE}))
	s.add(SimPlayerSetup.new({"name": "Ally", "team": 0,
		"faction": SimPlayerSetup.Faction.UK, "start_epoch": 4,
		"starting_forces": SimPlayerSetup.ForcePreset.NONE}))
	s.add(SimPlayerSetup.new({"name": "Enemy", "team": 1,
		"faction": SimPlayerSetup.Faction.RUSSIA, "start_epoch": 4,
		"starting_forces": SimPlayerSetup.ForcePreset.NONE}))
	var m := SimMatch.start(s, SimArena.OPEN_STEPPE)
	var mine := m.world.economy.place_starting_unit(0, "mbt", 0.0, 0.0, 0.0)
	var ally := m.world.economy.place_starting_unit(1, "mbt", 400.0, 0.0, 0.0)
	SimArsenal.arm(m.world.weapons, mine, "mbt", 4)
	m.run_ticks(400)
	_ok("an allied unit 400 m away is not in my track table at all",
		m.picture_for(0)._track_for_truth(ally) == null)
	_ok("so nothing of mine ever shoots it",
		m.world.entities.is_alive(ally)
			and absf(m.world.entities.structure[ally]
				- m.world.entities.structure_max[ally]) < 1e-4)
	_ok("and my own gun held its fire rather than firing at a friend",
		m.world.weapons.shots_fired == 0,
		"%d shots" % m.world.weapons.shots_fired)


# ═══════════════════════════════════════════════════════════════════════════
# 6. THE VICTORY CONDITION
# ═══════════════════════════════════════════════════════════════════════════

func _suite_victory_condition() -> void:
	_suite("A match ends when a war machine is destroyed, not when the map is empty")

	var m := SimMatch.start(_setup())
	# The opponent's director is removed for this suite only. The rule under
	# test is "a collapse that is not answered ends the match"; leaving the AI
	# in would be testing whether the AI happens to rebuild in time, which is a
	# different and much less stable question (it is tested on purpose below).
	m.world.remove_ai(1)
	m.run_ticks(40)
	_ok("nobody has won at the start",
		m.outcome() == SimVictory.Outcome.UNDECIDED)
	var them := m.standing(1)
	_ok("both sides hold production", them.production > 0, "%d" % them.production)
	_ok("and supply", them.supply > 0, "%d" % them.supply)

	# Take the enemy's base apart and leave their army completely intact.
	var razed := _raze_structures(m, 1)
	var army_before := m.world.entities.indices_of_owner(1).size()
	m.run_ticks(40)
	_ok("razing the base takes down %d structures" % razed, razed > 0)
	_ok("but the army is still standing",
		m.world.entities.indices_of_owner(1).size() > 0,
		"%d units left" % m.world.entities.indices_of_owner(1).size())
	_ok("and the match is NOT over -- an army in the field is still an army",
		m.outcome() == SimVictory.Outcome.UNDECIDED)
	_ok("the capitulation clock has started",
		m.standing(1).is_collapsing(),
		"%.0f s left" % m.standing(1).seconds_left())

	# Run past the clock. Everything they had left is lost with it.
	m.run_ticks(int((SimVictory.CAPITULATION_SECONDS + 6.0) * SimWorld.SIM_HZ))
	_ok("when the clock expires the player is eliminated",
		m.standing(1).eliminated, m.standing(1).reason)
	_ok("their remaining force goes with them",
		m.world.entities.indices_of_owner(1).size() == 0,
		"%d of %d left" % [m.world.entities.indices_of_owner(1).size(), army_before])
	_ok("and the human wins", m.outcome() == SimVictory.Outcome.VICTORY,
		m.victory.headline())
	_ok("the match reports itself finished", m.is_finished())
	_ok("SoA is intact -- death removed no rows",
		m.world.entities.count() >= army_before,
		"%d rows" % m.world.entities.count())

	# The clock is a chance, not a sentence.
	var r := SimMatch.start(_setup(77))
	r.world.remove_ai(1)
	r.run_ticks(40)
	_raze_structures(r, 1)
	# Rebuilding costs money, and a player who has just lost their whole base
	# will not have any. Fund the recovery so the test measures the RULE.
	r.world.economy.add_income(1, 6000.0)
	r.run_ticks(int(30.0 * SimWorld.SIM_HZ))
	_ok("a collapsed player is counting down", r.standing(1).is_collapsing())
	var base := r.base_position(1)
	# Rebuilding is possible because the first structure a player places is
	# free-form (RA2's MCV opening), which is what makes the clock beatable.
	r.world.commands.build(1, "hq", base.x, base.y)
	r.run_ticks(40)
	_ok("rebuilding a headquarters cancels the countdown",
		not r.standing(1).is_collapsing(),
		"production %d" % r.standing(1).production)
	_ok("and the match carries on",
		r.outcome() == SimVictory.Outcome.UNDECIDED)


# ═══════════════════════════════════════════════════════════════════════════
# 7. ELIMINATION MID-MATCH
# ═══════════════════════════════════════════════════════════════════════════

func _suite_elimination() -> void:
	_suite("A player knocked out mid-match stops being a participant")

	var m := SimMatch.start(_setup())
	m.run_ticks(20)
	_ok("the AI is thinking at the start", m.world.ai.has(1))

	# Destroy literally everything player 1 owns: immediate, no clock.
	var e := m.world.entities
	for i in e.indices_of_owner(1):
		m.world.damage.apply_structure(i, e.structure_max[i] + 1.0, "test")
	m.run_ticks(40)
	_ok("a player with nothing left is eliminated at once, no countdown",
		m.standing(1).eliminated, m.standing(1).reason)
	_ok("its AI is removed, so it stops issuing orders",
		not m.world.ai.has(1))
	_ok("the human wins", m.outcome() == SimVictory.Outcome.VICTORY)

	# Running on after the end must be safe and must change nothing.
	var hash_at_end := m.world.state_hash()
	m.run_ticks(60)
	_ok("stepping a finished match does nothing",
		m.world.state_hash() == hash_at_end)

	# The human losing is a DEFEAT, and the same condition read the other way.
	var d := SimMatch.start(_setup(31))
	d.run_ticks(20)
	for i in d.world.entities.indices_of_owner(0):
		d.world.damage.apply_structure(i,
			d.world.entities.structure_max[i] + 1.0, "test")
	d.run_ticks(40)
	_ok("losing everything is a defeat, not a draw",
		d.outcome() == SimVictory.Outcome.DEFEAT, d.victory.headline())

	# An AI-vs-AI match still resolves -- the harness has no human to lose.
	var ai := SimMatch.start(_setup(19, false))
	ai.run_ticks(20)
	for i in ai.world.entities.indices_of_owner(1):
		ai.world.damage.apply_structure(i,
			ai.world.entities.structure_max[i] + 1.0, "test")
	ai.run_ticks(40)
	_ok("with no human in the match the survivor still wins",
		ai.outcome() == SimVictory.Outcome.VICTORY
			and ai.victory.winning_team == 0,
		ai.victory.outcome_name())


# ═══════════════════════════════════════════════════════════════════════════
# 8. DETERMINISM. docs/06's first requirement.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_determinism() -> void:
	_suite("Two runs of one seed are identical, all the way to the winner")

	var a := _scripted(12345)
	var b := _scripted(12345)
	_ok("identical state hash after a full engagement",
		a["hash"] == b["hash"], "%d vs %d" % [a["hash"], b["hash"]])
	_ok("identical shots fired", a["shots"] == b["shots"],
		"%d vs %d" % [a["shots"], b["shots"]])
	_ok("identical kills", a["kills"] == b["kills"],
		"%d vs %d" % [a["kills"], b["kills"]])
	_ok("identical target assignments",
		a["assignments"] == b["assignments"],
		"%d vs %d" % [a["assignments"], b["assignments"]])
	_ok("identical combat log, line for line", a["log"] == b["log"])
	_ok("identical outcome", a["outcome"] == b["outcome"])
	_ok("identical credits to the cent",
		absf(a["credits"] - b["credits"]) < 1e-6,
		"%.6f vs %.6f" % [a["credits"], b["credits"]])

	var c := _scripted(999)
	_ok("a different seed produces a different match",
		c["hash"] != a["hash"], "%d vs %d" % [c["hash"], a["hash"]])


## A full match with shooting, moving, producing and an AI deciding, driven
## through SimWorld's real tick loop.
func _scripted(seed_value: int) -> Dictionary:
	var m := SimMatch.start(_setup(seed_value))
	# Put a hostile detachment inside weapon range of the player's base. The
	# two start positions are 9 km apart, and driving that far would make this
	# test a five-minute march before anything interesting happened.
	var home := m.base_position(0)
	for k in range(3):
		var i := m.world.economy.place_starting_unit(
			1, "mbt", home.x + 900.0 + 40.0 * float(k), home.y + 700.0, 0.0)
		SimArsenal.arm(m.world.weapons, i, "mbt", 4)
	var factory := m.production_structures(0)[0]
	m.world.commands.produce(0, factory, "mbt")
	# Send the whole force at the enemy base, through the same command queue
	# and the same formation code the mouse uses.
	var target := m.base_position(1)
	var units := PackedInt32Array()
	for i in m.world.entities.indices_of_owner(0):
		if m.world.entities.is_structure[i] == 0:
			units.append(i)
	var slots := m.world.movement.formation_slots(units, target.x, target.y)
	for k in range(units.size()):
		m.world.commands.move(0, units[k], slots[k * 2], slots[k * 2 + 1])
	m.run_ticks(1600)
	return {
		"hash": m.world.state_hash(),
		"shots": m.world.weapons.shots_fired,
		"kills": m.world.damage.kills,
		"assignments": m.world.fire_control.assignments,
		"log": "\n".join(PackedStringArray(
			m.world.damage.combat_log.map(func(x): return str(x)))),
		"outcome": m.outcome(),
		"credits": m.credits(0),
	}


# ═══════════════════════════════════════════════════════════════════════════
# 9. THE SCENE. The game has to be the thing that launches.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_scene() -> void:
	_suite("The skirmish is the game, and the proving ground is still the harness")

	_ok("game/scenes/skirmish.tscn exists",
		ResourceLoader.exists("res://scenes/skirmish.tscn"))
	_ok("game/scripts/skirmish.gd exists",
		ResourceLoader.exists("res://scripts/skirmish.gd"))
	_ok("the main scene is the skirmish",
		String(ProjectSettings.get_setting("application/run/main_scene"))
			== "res://scenes/skirmish.tscn",
		String(ProjectSettings.get_setting("application/run/main_scene")))
	_ok("the proving ground is still there as an art harness",
		ResourceLoader.exists("res://scenes/proving_ground.tscn"))

	# The scene may only READ the simulation. A gameplay decision in the viewer
	# is a rule that the headless harness and the AI never see.
	var text := FileAccess.get_file_as_string("res://scripts/skirmish.gd")
	var offences := PackedStringArray()
	for line in text.split("\n"):
		var code := String(line).strip_edges()
		if code.begins_with("#"):
			continue
		var hash_at := code.find("#")
		if hash_at >= 0:
			code = code.substr(0, hash_at)
		for forbidden in ["entities.kill(", "_truth_index",
				"indices_of_faction(1", "entities.structure[",
				"table_for("]:
			if forbidden in code:
				offences.append(code)
	_ok("the viewer never kills anything or reads ground truth about the enemy",
		offences.is_empty(), " | ".join(offences))
