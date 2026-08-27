extends SceneTree
## Tests for the faction roster: data/factions/<code>.json read through
## SimFactionData onto the baseline defs.
##
##     godot --path game --headless --script res://sim/tests/test_faction_roster.gd
##
## What this file asserts is the docs/08 faction axis actually reaching play:
## a German player fields a Leopard with the Leopard's numbers, a Russian
## player's tank resolves soviet-lineage art, Taiwan's researched gaps are
## real absences in the production panel, the epoch ladder still gates and
## upgrades per faction, missing data degrades to the baseline rather than to
## zero, and two runs of one seed with national rosters active are one run.

var _passed := 0
var _failed := 0


func _init() -> void:
	print("")
	print("  BATTLE -- faction roster tests")
	print("  " + "-".repeat(66))

	_suite_overlay()
	_suite_lineage_models()
	_suite_researched_absences()
	_suite_epoch_ladder()
	_suite_graceful_degradation()
	_suite_ai_reads_the_same_defs()
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


# ── fixtures ─────────────────────────────────────────────────────────────────

const DE := SimPlayerSetup.Faction.GERMANY
const RU := SimPlayerSetup.Faction.RUSSIA
const CN := SimPlayerSetup.Faction.PLA
const TW := SimPlayerSetup.Faction.ROC
const KP := SimPlayerSetup.Faction.KPA
const UA := SimPlayerSetup.Faction.UKRAINE


## A flat world with one registered player of the given faction.
func _world(faction: int, start_epoch := 4, ceiling := 7) -> SimWorld:
	var w := SimWorld.new(4242)
	w.use_accumulator = false
	w.terrain = SimTerrain.new(128, 128, 800.0, "test plain")
	w.terrain.fill(120.0)
	w.solver.terrain = w.terrain
	w.movement.set_terrain(w.terrain)
	w.economy.set_terrain(w.terrain)
	var s := SimPlayerSetup.new({"name": "P0", "faction": faction,
		"start_epoch": start_epoch, "ceiling_epoch": ceiling})
	w.economy.add_player_from_setup(0, s, 100000.0)
	return w


func _match_setup(seed_value: int, fa: int, fb: int,
		epoch := 4) -> SimMatchSetup:
	var s := SimMatchSetup.new()
	s.name = "Faction Test"
	s.seed_value = seed_value
	s.add(SimPlayerSetup.new({
		"name": "A", "team": 0, "faction": fa,
		"start_epoch": epoch, "ceiling_epoch": epoch + 1,
		"starting_forces": SimPlayerSetup.ForcePreset.GARRISON,
		"skill": SimSkill.Level.VETERAN}))
	s.add(SimPlayerSetup.new({
		"name": "B", "team": 1, "faction": fb,
		"start_epoch": epoch, "ceiling_epoch": epoch + 1,
		"starting_forces": SimPlayerSetup.ForcePreset.GARRISON,
		"skill": SimSkill.Level.VETERAN}))
	return s


# ═══════════════════════════════════════════════════════════════════════════
# 1. THE OVERLAY. Real systems with their real numbers.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_overlay() -> void:
	_suite("A German epoch-4 MBT is a Leopard 2A4, with the Leopard's numbers")

	var leo := SimRoster.make("mbt", 4, DE)
	var baseline := SimRoster.make("mbt", 4)
	_ok("the def exists", leo != null)
	_ok("it carries the designation from de.json",
		leo.designation == "Leopard 2A4", leo.designation)
	_ok("and the designation is its name", leo.name == "Leopard 2A4", leo.name)
	_ok("the baseline role name rides along for the HUD",
		leo.base_name == baseline.name, leo.base_name)
	_near("de.json's speed, unscaled -- not the baseline's", leo.speed_kmh, 68.0, 0.001)
	_ok("which is NOT the epoch-scaled baseline speed",
		absf(baseline.speed_kmh - leo.speed_kmh) > 1.0,
		"baseline %.1f" % baseline.speed_kmh)
	_near("combat-loaded mass from the data", leo.mass_t, 55.2, 0.001)
	_ok("crew of four", leo.crew == 4)
	_near("dims become the footprint (gun-forward length)", leo.footprint_m, 9.67, 0.001)

	# Road range -> fuel: the tank's endurance at cruise burn must come out at
	# the researched 550 km, whatever the litre figure had to become.
	var range_km: float = leo.fuel_capacity / leo.burn_cruise / 60.0 * leo.speed_kmh
	_near("fuel capacity re-derived so cruise endurance = 550 km road range",
		range_km, 550.0, 0.5)

	# What the data does not attest keeps the baseline: cost, build time and
	# combat stats are the game's balance numbers, not Wikipedia's.
	_near("cost stays the baseline's", leo.cost, baseline.cost, 0.001)
	_near("hitpoints stay the baseline's", leo.structure_hp, baseline.structure_hp, 0.001)

	# The def is cached and shared per (role, epoch, faction).
	_ok("two lookups share one instance", SimRoster.make("mbt", 4, DE) == leo)
	_ok("the German def and the baseline are different instances", leo != baseline)


# ═══════════════════════════════════════════════════════════════════════════
# 2. MODELS. Faction variant if on disk, lineage fallback, US baseline.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_lineage_models() -> void:
	_suite("Model stems resolve faction, then lineage, then the US baseline")

	var ru_tank := SimRoster.make("mbt", 4, RU)
	_ok("a Russian MBT resolves a T-series designation",
		ru_tank.designation.begins_with("T-"), ru_tank.designation)
	_ok("and a _ru model stem", ru_tank.model_stem.contains("_ru"),
		ru_tank.model_stem)

	var us_tank := SimRoster.make("mbt", 4)
	_ok("the baseline MBT keeps the US stem",
		us_tank.model_stem.begins_with("mbt_e4_us"), us_tank.model_stem)

	# North Korea has no e4 tank model; the soviet lineage covers it. What
	# matters is that it did NOT fall through to the Abrams.
	var kp_tank := SimRoster.make("mbt", 4, KP)
	_ok("a KPA tank borrows soviet-lineage art, not the Abrams",
		not kp_tank.model_stem.contains("_us"), kp_tank.model_stem)

	# A role with no art row at all resolves to "", the UI's blockout case.
	#
	# This used to use the oiler as its example, which stopped working the day
	# the oiler got a model: every one of the 88 roles now resolves, so there
	# is no longer a real role that demonstrates the fallback. Asserting it
	# through an unknown key tests the same branch and cannot go stale the
	# next time a gap is filled -- which is the point, because filling gaps is
	# supposed to be a thing that keeps happening.
	_ok("an unknown role resolves to the blockout",
		SimFactionData.model_stem_for("not_a_real_role", RU, 4) == "")
	var oiler := SimRoster.make("oiler", 4, RU)
	_ok("and the oiler, which used to be that example, now has art",
		oiler.model_stem != "", oiler.model_stem)

	# The stem must be a GLB actually on disk (resolution is checked against
	# the directory listing, never assumed).
	_ok("the resolved Russian stem exists on disk",
		FileAccess.file_exists("res://assets/units/%s_LOD0.glb" % ru_tank.model_stem),
		ru_tank.model_stem)


# ═══════════════════════════════════════════════════════════════════════════
# 3. RESEARCHED ABSENCES. Taiwan fields no bombers -- at the production panel.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_researched_absences() -> void:
	_suite("A researched absence is not buildable; a data hole stays baseline")

	var tw_bomber_any := false
	var kp_aewc_any := false
	for e in range(1, 8):
		if SimRoster.make("bomber", e, TW) != null:
			tw_bomber_any = true
		if SimRoster.make("aewc", e, KP) != null:
			kp_aewc_any = true
	_ok("the ROC bomber does not exist at any epoch", not tw_bomber_any)
	_ok("the KPA AEW&C does not exist at any epoch", not kp_aewc_any)

	var w := _world(TW, 4)
	_ok("the economy refuses the ROC bomber outright",
		w.economy.def_for(0, "bomber") == null)
	_ok("and it is absent from the build menu",
		not ("bomber" in Array(w.economy.buildable(0))))
	_ok("while the same player still gets a fighter",
		w.economy.def_for(0, "interceptor") != null)

	# Partial absence: the US retired the interceptor line after epoch 5.
	_ok("the US interceptor exists in epoch 5",
		SimRoster.make("interceptor", 5, SimPlayerSetup.Faction.US) != null)
	_ok("and is gone by epoch 6 -- absences can begin mid-timeline",
		SimRoster.make("interceptor", 6, SimPlayerSetup.Faction.US) == null)

	# A faction with NO data file at all is a hole, not an absence.
	var ua := SimRoster.make("mbt", 4, UA)
	_ok("Ukraine (no data file yet) keeps the baseline def", ua != null)
	_ok("with the baseline name", ua.designation == "", ua.name)


# ═══════════════════════════════════════════════════════════════════════════
# 4. THE EPOCH LADDER, per faction.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_epoch_ladder() -> void:
	_suite("The epoch ladder gates and upgrades the national roster (docs/05)")

	var w := _world(DE, 2)

	var d2 := w.economy.def_for(0, "mbt")
	_ok("at epoch 2 Germany fields the Leopard 1",
		d2 != null and d2.name == "Leopard 1", d2.name if d2 != null else "null")
	_ok("an explicit epoch-4 key is refused at epoch 2",
		w.economy.def_for(0, "mbt_e4") == null)

	# Produce one now, advance, produce another: the LINE upgrades in place.
	var f := w.economy.place_starting_unit(0, "heavy_factory", 0.0, 0.0)
	_ok("factory placed", f >= 0)
	_ok("an MBT is queued", w.economy.queue_production(0, f, "mbt"))
	for _i in range(140):
		w.economy.step(1.0)
	var first := -1
	for i in w.entities.indices_of_owner(0):
		if w.entities.is_structure[i] == 0:
			first = i
	_ok("the epoch-2 line turns out a Leopard 1",
		first >= 0 and w.entities.names[first] == "Leopard 1",
		w.entities.names[first] if first >= 0 else "nothing produced")
	_near("at the Leopard 1's 65 km/h",
		w.entities.max_speed_ms[first] * 3.6, 65.0, 0.01)

	w.economy.purse(0).epoch = 4
	var d4 := w.economy.def_for(0, "mbt")
	_ok("after advancing, the same order means a Leopard 2A4",
		d4 != null and d4.name == "Leopard 2A4", d4.name if d4 != null else "null")
	_ok("another MBT is queued", w.economy.queue_production(0, f, "mbt"))
	for _i in range(140):
		w.economy.step(1.0)
	var second := -1
	for i in w.entities.indices_of_owner(0):
		if w.entities.is_structure[i] == 0 and i != first:
			second = i
	_ok("and the next tank off the line is the Leopard 2A4",
		second >= 0 and w.entities.names[second] == "Leopard 2A4",
		w.entities.names[second] if second >= 0 else "nothing produced")

	# Inheritance: an entry serves until the data replaces it. North Korea's
	# APC line records nothing between epochs 3 and 6, so epoch 5 still
	# fields the epoch-3 vehicle.
	var kp5 := SimRoster.make("apc", 5, KP)
	var kp3 := SimRoster.make("apc", 3, KP)
	_ok("a gap in the data inherits the newest earlier system",
		kp5 != null and kp3 != null and kp5.designation == kp3.designation,
		kp5.designation if kp5 != null else "null")


# ═══════════════════════════════════════════════════════════════════════════
# 5. GRACEFUL DEGRADATION. Missing fields never zero a stat.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_graceful_degradation() -> void:
	_suite("Missing data falls back to the baseline, field by field")

	# cn.json's epoch-2 MBT ("Type 59") is a name-only entry: no dims, no
	# speed, no mass. Everything but the name must stay baseline.
	var cn2 := SimRoster.make("mbt", 2, CN)
	var base2 := SimRoster.make("mbt", 2)
	_ok("the PLA epoch-2 tank is the Type 59",
		cn2 != null and cn2.designation == "Type 59",
		cn2.designation if cn2 != null else "null")
	_near("missing dims leave the baseline footprint",
		cn2.footprint_m, base2.footprint_m, 0.001)
	_near("missing speed leaves the baseline (epoch-scaled) speed",
		cn2.speed_kmh, base2.speed_kmh, 0.001)
	_near("missing range leaves the baseline fuel tank",
		cn2.fuel_capacity, base2.fuel_capacity, 0.001)
	_ok("no stat was zeroed",
		cn2.speed_kmh > 0.0 and cn2.fuel_capacity > 0.0
			and cn2.footprint_m > 0.0 and cn2.structure_hp > 0.0)

	# Every def of every faction at every epoch: nothing crashes, nothing
	# comes out with a zeroed mobility or health stat.
	var factions := [SimPlayerSetup.Faction.US, SimPlayerSetup.Faction.UK,
		DE, SimPlayerSetup.Faction.FRANCE, CN, RU, TW, KP, UA]
	var bad := ""
	var checked := 0
	for f in factions:
		for role in SimRoster.role_keys():
			for e in range(1, 8):
				var d := SimRoster.make(role, e, f)
				if d == null:
					continue
				checked += 1
				var mobile_ok: bool = d.is_structure or d.speed_kmh > 0.0
				if not (d.structure_hp > 0.0 and mobile_ok \
						and d.cost > 0.0 and d.footprint_m > 0.0):
					bad = "%s e%d f%d" % [role, e, f]
	_ok("every resolvable def of all nine factions is sane", bad == "",
		bad if bad != "" else "%d defs checked" % checked)


# ═══════════════════════════════════════════════════════════════════════════
# 6. AI FAIRNESS. The AI reads the same defs and still functions.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_ai_reads_the_same_defs() -> void:
	_suite("The AI reads the national roster through the same economy path")

	# The classifier guard: a designation must not change what the AI
	# believes its own unit is FOR. "S-400 Triumf" carries no keyword, so the
	# baseline role name rides along and the launcher still reads as a SAM.
	var s400 := SimRoster.make("long_sam_launcher", 6, RU)
	_ok("the Russian long-range SAM carries its designation",
		s400.designation.begins_with("S-400"), s400.designation)
	_ok("and its name still classifies as a SAM for the AI",
		SimAiRoles.classify(s400.name, s400.category, false,
			s400.max_speed_ms()) == SimAiRoles.Unit.SAM, s400.name)
	var leo := SimRoster.make("mbt", 4, DE)
	_ok("while a tank's bare designation suffices",
		leo.name == "Leopard 2A4" and SimAiRoles.classify(leo.name,
			leo.category, false, leo.max_speed_ms()) == SimAiRoles.Unit.ARMOR)

	# A KPA AI has no AEW to build -- it must keep producing, not spin.
	var m := SimMatch.start(_match_setup(777, KP, SimPlayerSetup.Faction.US))
	_ok("the KPA match starts", m.phase == SimMatch.Phase.RUNNING)
	_ok("aewc is not in the KPA build set",
		not ("aewc" in Array(m.world.economy.buildable(0))))
	m.run_ticks(1200)   # 60 simulated seconds, ~18 strategic AI ticks
	var kp_ai: SimAiDirector = m.world.ai[0]
	var us_ai: SimAiDirector = m.world.ai[1]
	_ok("the KPA AI still issues production orders",
		kp_ai.orders_production > 0, "%d orders" % kp_ai.orders_production)
	_ok("so does its US opponent",
		us_ai.orders_production > 0, "%d orders" % us_ai.orders_production)


# ═══════════════════════════════════════════════════════════════════════════
# 7. DETERMINISM. docs/06's first requirement, with the faction axis live.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_determinism() -> void:
	_suite("One seed, two runs, national rosters active: the same run")

	var a := SimMatch.start(_match_setup(31337, DE, RU))
	var b := SimMatch.start(_match_setup(31337, DE, RU))
	a.run_ticks(600)
	b.run_ticks(600)
	_ok("identical state hash after 30 s of AI-vs-AI play",
		a.world.state_hash() == b.world.state_hash(),
		"%d vs %d" % [a.world.state_hash(), b.world.state_hash()])
	_ok("identical credits to the cent",
		absf(a.world.economy.credits(0) - b.world.economy.credits(0)) < 1e-6
			and absf(a.world.economy.credits(1) - b.world.economy.credits(1)) < 1e-6)
	_ok("the German side actually fielded German hardware",
		_owns_named(a, 0, "Leopard"), "no Leopard found")
	_ok("and the Russian side fielded Russian hardware",
		_owns_named(a, 1, "T-"), "no T-series found")


func _owns_named(m: SimMatch, player_id: int, prefix: String) -> bool:
	var e := m.world.entities
	for i in e.indices_of_owner(player_id):
		if String(e.names[i]).begins_with(prefix):
			return true
	return false
