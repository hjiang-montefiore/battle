extends SceneTree
## Tests for the combat subsystem: docs/03's armour matrix, the penetrator
## model, behind-armor effects, death, and the weapon cycle that finally makes
## a round get fired at all.
##
##     godot --path game --headless --script res://sim/tests/test_combat.gd
##
## A separate file from run_sim_tests.gd and test_spine.gd on purpose: four
## agents are building on one spine and a shared test runner is a shared merge
## conflict.
##
## What is asserted here is docs/03's CLAIMS, not the code's own taste. Where
## the document states a figure -- "a Gen 1 gun penetrates ~180 mm", "the Gen
## 3.5 front is ~600 mm", "the roof is 30-50 mm in every generation" -- the test
## asserts the published figure. Where it states a RULE -- "not at any range,
## not ever", "defeated entirely by spaced/composite", "no subtraction on a
## defeat" -- the test asserts the rule as an absolute, because a rule that
## holds 95% of the time is a slope wearing a cliff's clothes.

var _passed := 0
var _failed := 0


func _init() -> void:
	print("")
	print("  BATTLE -- combat tests (docs/03)")
	print("  " + "-".repeat(66))

	_suite_penetrator_mechanism()
	_suite_generational_cliff()
	_suite_range_grammar()
	_suite_resolution()
	_suite_behind_armor()
	_suite_death_and_indices()
	_suite_track_decay_on_death()
	_suite_end_to_end()
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


# ── fixtures ─────────────────────────────────────────────────────────────────

## A tank of a given generation, built from docs/03's ladder.
func _tank(w: SimWorld, unit_name: String, faction: int, x: float, z: float,
		gen: int, heading := 0.0) -> int:
	# y is the hull CENTRE, ~2 m up, not the contact patch. It matters: a round
	# on a flat trajectory to a target whose centre is at ground level clips the
	# terrain a few metres short and terminates as GROUND_IMPACT, which is
	# correct physics and would make every direct-fire test a miss.
	var i := w.entities.add(unit_name, faction, x, 2.0, z,
		SimSignature.new(20.0), [], SimTypes.Category.GROUND, 3.0)
	SimArmorScheme.apply(w.entities, i, gen)
	w.entities.set_mobility(i, 18.0, 2.0, 0.6)
	w.entities.heading_rad[i] = heading
	return i


## A fire-control radar good enough to hold a tank at a few kilometres.
func _fc_radar() -> SimSensorDef:
	return SimSensorDef.new({
		"name": "FCR", "domain": SimTypes.Domain.RF_ACTIVE,
		"reference_range_km": 60.0, "mount_height_m": 3.0,
		"max_quality": SimTypes.TrackQuality.FIRE_CONTROL, "radar_gen": 4,
	})


func _gun(max_km := 4.0) -> SimWeaponDef:
	return SimWeaponDef.new({
		"name": "main gun", "guidance": SimTypes.Guidance.UNGUIDED,
		"min_range_km": 0.0, "max_range_km": max_km,
	})


# ═══════════════════════════════════════════════════════════════════════════
# 1. THE MECHANISM REFUSALS -- the part a multiplier cannot express
# ═══════════════════════════════════════════════════════════════════════════

func _suite_penetrator_mechanism() -> void:
	_suite("A penetrator's MECHANISM either works or it does not (docs/03)")

	# docs/03: HESH is "flat; defeated entirely by spaced/composite, brutal
	# against RHA". ENTIRELY is the operative word, so no HESH round of any size
	# ever gets through a sandwich.
	var absurd := 5000.0
	_ok("no HESH round of any size defeats composite",
		SimPenetrator.verdict(absurd, 100.0, SimTypes.ArmorType.COMPOSITE,
			SimTypes.DamageClass.HESH) == SimPenetrator.Verdict.IMPOSSIBLE,
		"%.0f mm HESH vs 100 mm composite" % absurd)
	_ok("nor spaced armour, which is what it was invented to defeat",
		SimPenetrator.verdict(absurd, 40.0, SimTypes.ArmorType.SPACED,
			SimTypes.DamageClass.HESH) == SimPenetrator.Verdict.IMPOSSIBLE)
	_ok("but it is brutal against plain RHA",
		SimPenetrator.penetrated(SimPenetrator.verdict(200.0, 100.0,
			SimTypes.ArmorType.RHA, SimTypes.DamageClass.HESH)))

	# Fragmentation does not defeat armour. Not "does less" -- does nothing.
	_ok("fragmentation is irrelevant against a tank's glacis",
		SimPenetrator.verdict(0.0, 200.0, SimTypes.ArmorType.RHA,
			SimTypes.DamageClass.BLAST) == SimPenetrator.Verdict.IMPOSSIBLE)
	# ...and yet artillery does kill light vehicles, which is the same rule
	# read from the other end.
	var frag := SimPenetrator.effective_penetration_mm(
		SimTypes.DamageClass.BLAST, 0.0, 1.0)
	_ok("but it opens a thin-skinned hull",
		SimPenetrator.penetrated(SimPenetrator.verdict(frag, 8.0,
			SimTypes.ArmorType.RHA, SimTypes.DamageClass.BLAST)),
		"%.0f mm RHAe of fragments vs 8 mm plate" % frag)

	# The tandem rule, docs/03: a precursor detonates the reactive block, so the
	# jet meets what is underneath. A specialist, not an upgrade.
	var rpg := 200.0
	_ok("an RPG is defeated by light ERA",
		not SimPenetrator.penetrated(SimPenetrator.verdict(rpg, 110.0,
			SimTypes.ArmorType.ERA_LIGHT, SimTypes.DamageClass.CE, false)))
	_ok("and the same warhead with a precursor goes through",
		SimPenetrator.penetrated(SimPenetrator.verdict(rpg, 110.0,
			SimTypes.ArmorType.ERA_LIGHT, SimTypes.DamageClass.CE, true)))
	_ok("while a precursor buys nothing at all against composite",
		SimPenetrator.verdict(rpg, 110.0, SimTypes.ArmorType.COMPOSITE,
			SimTypes.DamageClass.CE, true)
			== SimPenetrator.verdict(rpg, 110.0, SimTypes.ArmorType.COMPOSITE,
				SimTypes.DamageClass.CE, false))

	# Verdicts are ordered, and the ordering is what the AI and the log read.
	_ok("verdicts run IMPOSSIBLE < defeated < through",
		SimPenetrator.Verdict.IMPOSSIBLE < SimPenetrator.Verdict.DEFEATED
			and SimPenetrator.Verdict.DEFEATED < SimPenetrator.Verdict.MARGINAL
			and not SimPenetrator.penetrated(SimPenetrator.Verdict.DEFEATED)
			and SimPenetrator.penetrated(SimPenetrator.Verdict.MARGINAL))


# ═══════════════════════════════════════════════════════════════════════════
# 2. THE CLIFF -- docs/03's worked example, against the real ladder
# ═══════════════════════════════════════════════════════════════════════════

func _suite_generational_cliff() -> void:
	_suite("The generational gap is a cliff, not a slope (docs/03)")

	# The ladder must reproduce the RHAe column docs/03 publishes.
	_ok("Gen 1 frontal protection is ~200 mm RHAe",
		absf(SimArmorScheme.frontal_rhae(SimArmorScheme.Gen.G1) - 200.0) < 12.0,
		"%.0f mm" % SimArmorScheme.frontal_rhae(SimArmorScheme.Gen.G1))
	_ok("Gen 3.5 frontal protection is ~600-700 mm RHAe",
		SimArmorScheme.frontal_rhae(SimArmorScheme.Gen.G3_5) > 550.0
			and SimArmorScheme.frontal_rhae(SimArmorScheme.Gen.G3_5) < 720.0,
		"%.0f mm" % SimArmorScheme.frontal_rhae(SimArmorScheme.Gen.G3_5))
	_ok("and composite is worth more against CE than against KE",
		SimArmorScheme.frontal_rhae(SimArmorScheme.Gen.G3, SimTypes.DamageClass.CE)
			> SimArmorScheme.frontal_rhae(SimArmorScheme.Gen.G3, SimTypes.DamageClass.KE),
		"%.0f mm vs HEAT, %.0f mm vs APFSDS" % [
			SimArmorScheme.frontal_rhae(SimArmorScheme.Gen.G3, SimTypes.DamageClass.CE),
			SimArmorScheme.frontal_rhae(SimArmorScheme.Gen.G3, SimTypes.DamageClass.KE)])

	# docs/03's worked table, facet by facet, using the ladder's own numbers.
	var g1 := SimArmorScheme.GUNS[SimArmorScheme.Gen.G1]
	var t := SimArmorScheme.LADDER[SimArmorScheme.Gen.G3_5]
	var results := {}
	for f in [SimTypes.Facet.FRONT, SimTypes.Facet.SIDE, SimTypes.Facet.REAR,
			SimTypes.Facet.TOP]:
		results[f] = not SimPenetrator.absolute_refusal(g1["pen"],
			SimTypes.DamageClass.KE, t["mm"][f], t["type"][f], false, g1["mv"])
	_ok("a Gen 1 gun cannot penetrate a Gen 3.5 front -- NOT AT ANY RANGE",
		not results[SimTypes.Facet.FRONT])
	_ok("but it penetrates the side", results[SimTypes.Facet.SIDE])
	_ok("the rear", results[SimTypes.Facet.REAR])
	_ok("and the roof", results[SimTypes.Facet.TOP])
	_ok("so the obsolete tank is POSITIONAL, not useless",
		not results[SimTypes.Facet.FRONT] and results[SimTypes.Facet.SIDE]
			and results[SimTypes.Facet.REAR] and results[SimTypes.Facet.TOP])

	# The refusal must hold at every range, sampled, or it is a slope again.
	var ever_through := false
	for r in range(0, 6001, 100):
		var pen := SimArmor.penetration_at_range_mm(g1["pen"],
			SimTypes.DamageClass.KE, float(r), g1["mv"])
		if SimPenetrator.penetrated(SimPenetrator.verdict(pen,
				t["mm"][SimTypes.Facet.FRONT], t["type"][SimTypes.Facet.FRONT],
				SimTypes.DamageClass.KE)):
			ever_through = true
	_ok("the frontal refusal holds at all 61 sampled ranges from 0 to 6 km",
		not ever_through)

	# The ladder must be monotonic, or "advance an epoch" stops meaning anything.
	var monotonic := true
	var prev := 0.0
	for gen in [SimArmorScheme.Gen.G1, SimArmorScheme.Gen.G2, SimArmorScheme.Gen.G3,
			SimArmorScheme.Gen.G3_5, SimArmorScheme.Gen.G4, SimArmorScheme.Gen.G5]:
		var v := SimArmorScheme.frontal_rhae(gen)
		if v <= prev:
			monotonic = false
		prev = v
	_ok("frontal protection rises monotonically across the six generations",
		monotonic, "top of the ladder %.0f mm RHAe" % prev)

	# docs/03's deliberate escape valve: "every tank's roof is thin, in every
	# generation -- the weight simply cannot go there."
	var roof_kills := true
	var atgm := SimArmorScheme.make_top_attack_atgm()
	for gen in SimArmorScheme.LADDER.keys():
		var row: Dictionary = SimArmorScheme.LADDER[gen]
		if not SimPenetrator.penetrated(SimPenetrator.verdict(
				atgm.penetration_mm, row["mm"][SimTypes.Facet.TOP],
				row["type"][SimTypes.Facet.TOP], SimTypes.DamageClass.CE, true)):
			roof_kills = false
	_ok("a top-attack tandem ATGM kills every MBT ever built, roof-on",
		roof_kills)
	_ok("and the same warhead is refused by the newest frontal arc",
		not SimPenetrator.penetrated(SimPenetrator.verdict(
			atgm.penetration_mm,
			SimArmorScheme.LADDER[SimArmorScheme.Gen.G5]["mm"][SimTypes.Facet.FRONT],
			SimArmorScheme.LADDER[SimArmorScheme.Gen.G5]["type"][SimTypes.Facet.FRONT],
			SimTypes.DamageClass.CE, true)),
		"which is why the ATGM is a TOP attack weapon")


# ═══════════════════════════════════════════════════════════════════════════
# 3. THE ENGAGEMENT GRAMMAR -- KE bleeds with range, CE does not
# ═══════════════════════════════════════════════════════════════════════════

func _suite_range_grammar() -> void:
	_suite("At range the ATGM wins; up close the gun wins (docs/03)")

	var gun := SimArmorScheme.GUNS[SimArmorScheme.Gen.G4]    # 700 mm at 2 km
	var atgm := SimArmorScheme.make_top_attack_atgm()        # 900 mm CE, flat
	var side_mm: float = SimArmorScheme.LADDER[SimArmorScheme.Gen.G3]["mm"][SimTypes.Facet.SIDE]

	var near_gun := SimArmor.penetration_at_range_mm(gun["pen"],
		SimTypes.DamageClass.KE, 300.0, gun["mv"])
	var far_gun := SimArmor.penetration_at_range_mm(gun["pen"],
		SimTypes.DamageClass.KE, 5000.0, gun["mv"])
	var near_atgm := SimArmor.penetration_at_range_mm(atgm.penetration_mm,
		SimTypes.DamageClass.CE, 300.0)
	var far_atgm := SimArmor.penetration_at_range_mm(atgm.penetration_mm,
		SimTypes.DamageClass.CE, 5000.0)

	_ok("the gun's penetration falls with range", far_gun < near_gun,
		"%.0f mm at 300 m, %.0f mm at 5 km" % [near_gun, far_gun])
	_ok("the missile's does not", is_equal_approx(near_atgm, far_atgm))
	_ok("a slow 1950s round bleeds off far faster than a modern long rod",
		SimArmor.ke_retention(SimTypes.DamageClass.KE, 5000.0, 900.0)
			< SimArmor.ke_retention(SimTypes.DamageClass.KE, 5000.0, 1750.0))
	# Both still get through a Gen 3 side; the point is the ORDER changes.
	_ok("so infantry AT wants distance and the tank wants to close",
		far_atgm > far_gun and near_atgm > near_gun - 1.0
			and SimPenetrator.penetrated(SimPenetrator.verdict(far_atgm, side_mm,
				SimTypes.ArmorType.RHA, SimTypes.DamageClass.CE)))


# ═══════════════════════════════════════════════════════════════════════════
# 4. RESOLUTION -- what an impact does to a real unit in a real world
# ═══════════════════════════════════════════════════════════════════════════

func _suite_resolution() -> void:
	_suite("Resolution applies the result, and a defeat applies nothing")

	var w := SimWorld.new(4242)
	w.use_accumulator = false
	var e := w.entities
	var modern := _tank(w, "Gen3.5", 1, 0.0, 0.0, SimArmorScheme.Gen.G3_5)
	var g1 := SimArmorScheme.GUNS[SimArmorScheme.Gen.G1]

	# Forty Gen 1 rounds into a Gen 3.5 glacis. docs/03: "defeated (spall, crew
	# shock, no kill)". If ANY structure comes off, the cliff is a slope and the
	# whole epoch system is a stat upgrade.
	var pen := SimArmor.penetration_at_range_mm(g1["pen"],
		SimTypes.DamageClass.KE, 1500.0, g1["mv"])
	var before := e.structure[modern]
	var any_penetrated := false
	for _i in range(40):
		var o := w.damage.resolve_impact(modern, SimTypes.Facet.FRONT,
			SimTypes.DamageClass.KE, pen)
		if o.penetrated:
			any_penetrated = true
	_ok("forty Gen 1 rounds on a Gen 3.5 front penetrate none of the time",
		not any_penetrated)
	_ok("and take NOTHING off the structure pool",
		e.structure[modern] == before, "%.1f structure" % e.structure[modern])
	_ok("the tank is still alive after all forty", e.is_alive(modern))
	_ok("but the crew have been shaken by it",
		e.crew_efficiency[modern] < 1.0,
		"crew at %.0f%%" % (e.crew_efficiency[modern] * 100.0))

	# Same gun, same tank, from behind.
	var rear_o := w.damage.resolve_impact(modern, SimTypes.Facet.REAR,
		SimTypes.DamageClass.KE, pen)
	_ok("the same round through the rear penetrates", rear_o.penetrated)
	_ok("and takes structure off", rear_o.structure_lost > 0.0,
		"%.1f lost" % rear_o.structure_lost)
	_ok("the outcome explains itself in one line", rear_o.reason.contains("REAR"),
		rear_o.reason)

	# Enough of them and it dies. Death must be reachable, or none of this
	# matters.
	var died := rear_o.killed
	for _i in range(20):
		if not e.is_alive(modern):
			died = true
			break
		var o2 := w.damage.resolve_impact(modern, SimTypes.Facet.REAR,
			SimTypes.DamageClass.KE, pen)
		died = died or o2.killed
	_ok("repeated rear penetrations kill it", died and not e.is_alive(modern))
	_ok("the resolver counted the kill", w.damage.kills >= 1)
	_ok("and the combat log said why", not w.damage.combat_log.is_empty(),
		str(w.damage.combat_log[-1]))

	# An arriving round against a resolved corpse must be a no-op, not a
	# second kill.
	var post := w.damage.resolve_impact(modern, SimTypes.Facet.REAR,
		SimTypes.DamageClass.KE, pen)
	_ok("a round arriving at an already-dead unit resolves nothing",
		not post.resolved and not post.killed)

	# Soft targets have no facets to resolve and die from the structure pool.
	var truck := e.add("truck", 1, 50.0, 0.0, 50.0, SimSignature.new(6.0))
	e.set_damage_profile(truck, SimTypes.DamageModel.UNARMORED, 40.0)
	var t_out := w.damage.resolve_impact(truck, SimTypes.Facet.SIDE,
		SimTypes.DamageClass.BLAST, 0.0, 1.0)
	_ok("a frag warhead that is useless against a tank wrecks a truck",
		t_out.penetrated and t_out.structure_lost > 0.0,
		"%.1f of %.0f" % [t_out.structure_lost, 40.0])

	# A proximity burst at the edge of the lethal radius does nothing at all.
	var edge := w.damage.resolve_impact(truck, SimTypes.Facet.SIDE,
		SimTypes.DamageClass.BLAST, 0.0, 0.0)
	_ok("and a burst outside the lethal radius does not",
		not edge.penetrated and edge.structure_lost == 0.0)


# ═══════════════════════════════════════════════════════════════════════════
# 5. BEHIND ARMOR -- components, not hit points
# ═══════════════════════════════════════════════════════════════════════════

func _suite_behind_armor() -> void:
	_suite("A penetration resolves WHAT IT HIT (docs/03)")

	# The roll must be reproducible from the seed, and must draw a fixed number
	# of floats whatever it decides -- otherwise a replay diverges the first
	# time a component survives a hit it used to lose.
	var a := SimRng.new(9001)
	var b := SimRng.new(9001)
	var same := true
	for _i in range(50):
		if SimBehindArmor.roll(a, SimTypes.DamageModel.ARMORED,
				SimTypes.Facet.SIDE, 0.8, 1.0, false) \
				!= SimBehindArmor.roll(b, SimTypes.DamageModel.ARMORED,
					SimTypes.Facet.SIDE, 0.8, 1.0, false):
			same = false
	_ok("the same seed produces the same fifty behind-armor results", same)

	var c := SimRng.new(9001)
	var d := SimRng.new(9001)
	# Different weights, same number of draws: the streams must stay in step.
	SimBehindArmor.roll(c, SimTypes.DamageModel.ARMORED, SimTypes.Facet.TOP,
		1.0, 1.0, false)
	SimBehindArmor.roll(d, SimTypes.DamageModel.ARMORED, SimTypes.Facet.FRONT,
		0.0, 0.3, true)
	_ok("and the stream advances by the same amount whatever the outcome",
		c.state() == d.state())

	# Where the round came in decides what it hits. Rear penetrations are
	# engine hits; top penetrations are crew and ammunition.
	var rear_mobility := SimBehindArmor.ARMORED_WEIGHTS[SimTypes.Facet.REAR][0]
	var front_mobility := SimBehindArmor.ARMORED_WEIGHTS[SimTypes.Facet.FRONT][0]
	_ok("a rear hit is far likelier to be a mobility kill than a frontal one",
		rear_mobility > front_mobility * 2.0,
		"%.2f vs %.2f" % [rear_mobility, front_mobility])
	_ok("a side hit is the one that finds the ready ammunition",
		SimBehindArmor.ARMORED_WEIGHTS[SimTypes.Facet.SIDE][4]
			> SimBehindArmor.ARMORED_WEIGHTS[SimTypes.Facet.REAR][4])
	_ok("blowout panels make a catastrophic loss far rarer",
		SimBehindArmor.BLOWOUT_MULTIPLIER <= 0.25)
	_ok("and docs/03's generational split puts them on Gen 3.5 and later",
		not SimArmorScheme.default_blowout(SimArmorScheme.Gen.G2)
			and SimArmorScheme.default_blowout(SimArmorScheme.Gen.G4))

	# The consequences must be real, not cosmetic.
	var w := SimWorld.new(7)
	var e := w.entities
	var t := _tank(w, "victim", 1, 0.0, 0.0, SimArmorScheme.Gen.G3)
	e.lose_component(t, SimTypes.Component.MOBILITY)
	_ok("a mobility kill immobilises the vehicle and leaves it alive",
		e.is_alive(t) and not e.can_move(t)
			and e.move_state[t] == SimTypes.MoveState.IMMOBILE)
	_ok("but the turret still traverses -- it is a pillbox now", e.can_fire(t))
	e.lose_component(t, SimTypes.Component.FIREPOWER)
	_ok("a firepower kill leaves it mobile and harmless", not e.can_fire(t))
	e.lose_component(t, SimTypes.Component.SENSORS)
	_ok("a sensor kill leaves it alive and BLIND -- docs/03's key row",
		e.is_alive(t) and not e.sensors_intact(t))

	# Crew shock recovers; crew casualties do not recover all the way.
	var w2 := SimWorld.new(11)
	w2.use_accumulator = false
	var t2 := _tank(w2, "shaken", 1, 0.0, 0.0, SimArmorScheme.Gen.G3)
	var g1 := SimArmorScheme.GUNS[SimArmorScheme.Gen.G1]
	var weak := SimArmor.penetration_at_range_mm(g1["pen"],
		SimTypes.DamageClass.KE, 2000.0, g1["mv"])
	for _i in range(6):
		w2.damage.resolve_impact(t2, SimTypes.Facet.FRONT,
			SimTypes.DamageClass.KE, weak)
	var shaken: float = w2.entities.crew_efficiency[t2]
	_ok("being shot at shakes the crew even when the armour holds", shaken < 1.0,
		"%.0f%%" % (shaken * 100.0))
	w2.run_ticks(200)
	_ok("and they recover once nothing more arrives",
		w2.entities.crew_efficiency[t2] > shaken,
		"%.0f%% after 10 s" % (w2.entities.crew_efficiency[t2] * 100.0))


# ═══════════════════════════════════════════════════════════════════════════
# 6. DEATH, AND THE STRUCTURE-OF-ARRAYS HAZARD
# ═══════════════════════════════════════════════════════════════════════════

func _suite_death_and_indices() -> void:
	_suite("Death never invalidates an index (the classic SoA hazard)")

	var w := SimWorld.new(31)
	w.use_accumulator = false
	var e := w.entities
	var a := _tank(w, "alpha", 0, -100.0, 0.0, SimArmorScheme.Gen.G3)
	var b := _tank(w, "bravo", 1, 0.0, 0.0, SimArmorScheme.Gen.G1)
	var c := _tank(w, "charlie", 1, 100.0, 0.0, SimArmorScheme.Gen.G3)
	var count_before := e.count()

	# Kill the MIDDLE one -- the case that would shift every later index if
	# death compacted the arrays.
	while e.is_alive(b):
		w.damage.apply_structure(b, 25.0, "test")
	_ok("the unit is dead", not e.is_alive(b))
	_ok("the array did not shrink", e.count() == count_before,
		"%d rows" % e.count())
	_ok("the indices either side still name the same units",
		e.names[a] == "alpha" and e.names[c] == "charlie")
	_ok("and still hold the same positions",
		e.pos_x[a] == -100.0 and e.pos_x[c] == 100.0)
	_ok("the corpse is no longer listed for its faction",
		not (b in Array(e.indices_of_faction(1)))
			and (c in Array(e.indices_of_faction(1))))
	_ok("a dead unit's velocity is zeroed so it cannot drift off the map",
		e.vel_x[b] == 0.0 and e.vel_z[b] == 0.0
			and e.move_state[b] == SimTypes.MoveState.DEAD)
	_ok("and it holds no destination or path any more",
		e.has_dest[b] == 0 and e.path_len[b] == 0)

	# A round already in the air when its target died must terminate, not
	# arrive at whoever now occupies that index. (Nobody does -- that is the
	# point -- but the projectile must still notice.)
	var w2 := SimWorld.new(32)
	w2.use_accumulator = false
	var e2 := w2.entities
	var shooter := _tank(w2, "shooter", 0, 0.0, 0.0, SimArmorScheme.Gen.G4)
	var doomed := _tank(w2, "doomed", 1, 0.0, 3000.0, SimArmorScheme.Gen.G1)
	w2.munitions.fire(SimArmorScheme.make_gun_round(SimArmorScheme.Gen.G4),
		shooter, doomed, null)
	w2.run_ticks(2)
	while e2.is_alive(doomed):
		w2.damage.apply_structure(doomed, 40.0, "test")
	w2.run_ticks(40)
	var lost := false
	for im in w2.munitions.last_impacts:
		if (im as SimImpact).termination == SimMunitionDef.Termination.TARGET_LOST:
			lost = true
	_ok("a round in flight terminates when its target dies to something else",
		lost or w2.munitions.active_count() == 0)
	_ok("and nothing is left flying", w2.munitions.is_balanced())

	# Wrecks expire without touching the arrays.
	var w3 := SimWorld.new(33)
	w3.use_accumulator = false
	var e3 := w3.entities
	var dead := _tank(w3, "hulk", 1, 0.0, 0.0, SimArmorScheme.Gen.G1)
	w3.damage.apply_structure(dead, 999.0, "test")
	var rows := e3.count()
	w3.run_ticks(int(w3.damage.resolver.wreck_linger_s * SimWorld.SIM_HZ) + 5)
	_ok("a wreck burns out and is reported to the presentation layer",
		w3.damage.resolver.wrecks_expired == 1)
	_ok("without removing its row", e3.count() == rows)


func _suite_track_decay_on_death() -> void:
	_suite("A dead unit's tracks decay naturally -- no death notification")

	var w := SimWorld.new(41)
	w.use_accumulator = false
	var e := w.entities
	var observer := e.add("observer", 0, 0.0, 0.0, 0.0, SimSignature.new(20.0),
		[_fc_radar()], SimTypes.Category.GROUND, 3.0)
	var target := _tank(w, "target", 1, 0.0, 1500.0, SimArmorScheme.Gen.G1)
	w.run_ticks(20)
	var table := w.track_table_for(0)
	_ok("the observer holds a track on it", table.count() >= 1,
		"%d tracks" % table.count())
	var q_before := 0
	for id in table.track_ids():
		q_before = maxi(q_before, table.get_track(id).quality)

	while e.is_alive(target):
		w.damage.apply_structure(target, 40.0, "test")
	# Long enough for the WHOLE ladder: FIRE_CONTROL -> TRACK -> CONTACT ->
	# dropped, each rung's clock restarting as it falls.
	var ladder_s := SimTrack.DECAY_FIRE_CONTROL_S + SimTrack.DECAY_TRACK_S \
		+ SimTrack.DECAY_CONTACT_S
	w.run_ticks(int((ladder_s + 10.0) * SimWorld.SIM_HZ))
	var q_after := 0
	for id in table.track_ids():
		q_after = maxi(q_after, table.get_track(id).quality)
	_ok("it was a real track while the target lived",
		q_before >= SimTypes.TrackQuality.TRACK,
		SimTypes.quality_name(q_before))
	_ok("and after the target dies the track goes cold and is dropped",
		table.count() == 0, "%d tracks left" % table.count())


# ═══════════════════════════════════════════════════════════════════════════
# 7. END TO END -- order, gate, launch, flight, impact, armour, death
# ═══════════════════════════════════════════════════════════════════════════

## One-sided engagement, driven entirely through the command queue and the tick
## loop. Nothing in here calls resolve_impact directly.
func _engagement(seed_value: int, shooter_gen: int, target_gen: int,
		ticks := 900) -> Dictionary:
	var w := SimWorld.new(seed_value)
	w.use_accumulator = false
	var e := w.entities
	var shooter := e.add("shooter", 0, 0.0, 2.0, 0.0, SimSignature.new(20.0),
		[_fc_radar()], SimTypes.Category.GROUND, 3.0)
	SimArmorScheme.apply(e, shooter, shooter_gen)
	e.set_mobility(shooter, 18.0, 2.0, 0.6)
	# Facing the shooter, so impact geometry chooses the FRONT facet -- the one
	# docs/03 says is the hard case.
	var target := _tank(w, "target", 1, 0.0, 1500.0, target_gen, PI)
	w.weapons.arm(shooter, _gun(), SimArmorScheme.make_gun_round(shooter_gen), 6.0)

	w.run_ticks(10)                       # let the picture form
	var table := w.track_table_for(0)
	var ids := table.track_ids()
	var tid: int = ids[0] if not ids.is_empty() else -1
	if tid >= 0:
		w.commands.attack_track(0, shooter, tid)
	w.run_ticks(ticks)
	return {
		"world": w, "shooter": shooter, "target": target, "track": tid,
		"shots": w.weapons.shots_fired, "kills": w.damage.kills,
		"alive": e.is_alive(target), "hash": w.state_hash(),
		"structure": e.structure[target],
	}


func _suite_end_to_end() -> void:
	_suite("An order becomes a dead tank, through every layer in between")

	var kill := _engagement(1234, SimArmorScheme.Gen.G4, SimArmorScheme.Gen.G1)
	_ok("the shooter built a track on the target without being told about it",
		kill["track"] >= 0, "track id %d" % kill["track"])
	_ok("the gate cleared the shot and the weapon cycle fired",
		kill["shots"] > 0, "%d rounds" % kill["shots"])
	_ok("rounds arrived and the armour matrix resolved them",
		(kill["world"] as SimWorld).damage.resolver.impacts_resolved > 0,
		(kill["world"] as SimWorld).damage.describe())
	_ok("a Gen 4 gun kills a Gen 1 tank frontally",
		not kill["alive"] and kill["kills"] >= 1)
	var kill_log: Array = (kill["world"] as SimWorld).damage.combat_log
	_ok("and the log says exactly why", not kill_log.is_empty(),
		str(kill_log[-1]) if not kill_log.is_empty() else "empty")

	# THE CLIFF, fought rather than computed. Same scenario, reversed
	# generations: the rounds arrive, and nothing happens. Ever.
	var refused := _engagement(1234, SimArmorScheme.Gen.G1, SimArmorScheme.Gen.G3_5)
	var rw := refused["world"] as SimWorld
	_ok("the obsolete tank fires just as often", refused["shots"] > 0,
		"%d rounds" % refused["shots"])
	_ok("its rounds arrive on the target's front",
		rw.damage.resolver.impacts_resolved > 0,
		rw.damage.describe())
	_ok("not one of them penetrates", rw.damage.penetrations == 0)
	_ok("the modern tank loses no structure whatsoever",
		is_equal_approx(refused["structure"],
			rw.entities.structure_max[refused["target"]]),
		"%.1f structure" % refused["structure"])
	_ok("and it is alive at the end of it", refused["alive"])

	# A blinded shooter cannot produce a firing solution -- docs/03's sensor
	# kill, joined to docs/02's track ladder.
	var blind := _engagement(1234, SimArmorScheme.Gen.G4, SimArmorScheme.Gen.G1, 20)
	var bw := blind["world"] as SimWorld
	var shots_before: int = bw.weapons.shots_fired
	bw.entities.lose_component(blind["shooter"], SimTypes.Component.SENSORS)
	bw.run_ticks(400)
	_ok("a shooter whose optics are destroyed stops shooting",
		bw.weapons.shots_fired == shots_before, "%d shots" % bw.weapons.shots_fired)
	_ok("and says why rather than failing silently",
		bw.weapons.last_refusal.contains("optics"), bw.weapons.last_refusal)

	# An engagement order naming a track the faction does not hold is refused.
	var w := SimWorld.new(55)
	w.use_accumulator = false
	var lone := w.entities.add("lone", 0, 0.0, 0.0, 0.0, SimSignature.new(10.0))
	w.weapons.arm(lone, _gun(), SimArmorScheme.make_gun_round(SimArmorScheme.Gen.G1))
	_ok("you cannot engage a track your faction does not hold",
		not w.weapons.engage(lone, 9999))


# ═══════════════════════════════════════════════════════════════════════════
# 8. DETERMINISM -- docs/06's non-negotiable
# ═══════════════════════════════════════════════════════════════════════════

func _suite_determinism() -> void:
	_suite("Same seed, same battle, same result (docs/06)")

	var a := _engagement(2026, SimArmorScheme.Gen.G4, SimArmorScheme.Gen.G1)
	var b := _engagement(2026, SimArmorScheme.Gen.G4, SimArmorScheme.Gen.G1)
	_ok("two runs of the same seeded engagement hash identically",
		a["hash"] == b["hash"], "%d vs %d" % [a["hash"], b["hash"]])
	_ok("with the same number of shots fired", a["shots"] == b["shots"])
	_ok("the same number of kills", a["kills"] == b["kills"])
	_ok("and the same combat log, line for line",
		(a["world"] as SimWorld).damage.combat_log
			== (b["world"] as SimWorld).damage.combat_log,
		"%d lines" % (a["world"] as SimWorld).damage.combat_log.size())

	# The battle must actually have exercised the RNG, or this proves nothing.
	var fresh := SimWorld.new(2026)
	_ok("and the combat resolution really did draw from the seeded stream",
		(a["world"] as SimWorld).damage.rng.state() != fresh.damage.rng.state())

	# A different seed must be ABLE to produce a different battle, or the seed is
	# decorative. Two seeds could coincide on one short engagement, so this
	# samples several -- what is being asserted is that the seed reaches the
	# behind-armor roll at all, not that every pair of seeds differs.
	var differs := false
	for other_seed in [777, 31337, 4, 90210]:
		var other := _engagement(other_seed, SimArmorScheme.Gen.G4,
			SimArmorScheme.Gen.G1)
		if (other["world"] as SimWorld).damage.combat_log \
				!= (a["world"] as SimWorld).damage.combat_log:
			differs = true
	_ok("a different seed can be a different battle", differs)

	# Nothing in the sim may reach for wall-clock time or the global RNG.
	var src := FileAccess.get_file_as_string("res://sim/combat/sim_combat_resolver.gd") \
		+ FileAccess.get_file_as_string("res://sim/combat/sim_behind_armor.gd") \
		+ FileAccess.get_file_as_string("res://sim/combat/sim_weapon_cycle.gd") \
		+ FileAccess.get_file_as_string("res://sim/combat/sim_penetrator.gd") \
		+ FileAccess.get_file_as_string("res://sim/combat/sim_armor_scheme.gd")
	var banned := ["randf(", "randi(", "randf_range(", "Time.get_ticks"]
	var found := PackedStringArray()
	for token in banned:
		if src.contains(token):
			found.append(token)
	_ok("no combat file calls randf(), randi() or the wall clock",
		found.is_empty(), "found " + ", ".join(found) if not found.is_empty() else "")
