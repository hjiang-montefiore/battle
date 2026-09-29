extends SceneTree
## CAN THE AI REACH THE MONEY?
##
##     godot --path game --headless --script res://sim/tests/test_ai_expansion.gd
##
## test_ai_works.gd proved the AI BUILDS. This file proves it EXPANDS, which
## turned out to be a different question with a different answer.
##
## THE BASELINE, measured on a peer match on skirmish_valley before any of
## this, twelve minutes a side:
##
##     oil derricks built                          0, on either side, ever
##     income                                      520 cr/min at t=0,
##                                                 520 cr/min at the end
##     epoch                                       4 at the first tick,
##                                                 4 at the last
##     structures placed in twelve minutes         1 and 2
##
## The cause was geometric, not economic. Every oil field on the arena sits
## ~500 m (own) or ~1,400 m (contested) from a base, and the whole build
## envelope of a start is the headquarters' 340 m ring. A derrick must stand
## ON a field. So there was no legal spot for one, anywhere, for the whole
## match -- and since the purse pays min(extraction, refine), income could
## never move off what two starting derricks pump.
##
## THE ASYMMETRY THAT KEEPS THESE HONEST is the same one test_ai_works states:
## THE TEST may read ground truth and may call SimEconomy.placement_problem()
## and derrick_on(), because the test is not the AI. The director may not, and
## the last suite here is what proves it did not start.

var _passed := 0
var _failed := 0
var _code := 1


func _initialize() -> void:
	print("")
	print("  BATTLE -- can the AI reach the money?")
	print("  " + "-".repeat(70))

	_suite_the_creep_gains_ground()
	_suite_a_relay_that_gains_nothing_is_refused()
	_suite_the_chain_is_bounded()
	_suite_it_stands_a_derrick_on_a_field()
	_suite_the_taps_are_kept_level()
	_suite_it_climbs_on_what_it_earned()
	_suite_a_refused_well_is_left_alone()
	_suite_expansion_survived_the_firewall()

	print("  " + "-".repeat(70))
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


# ── fixtures ────────────────────────────────────────────────────────────────

## ONE AI, A REAL ECONOMY, REAL OIL FIELDS, AND NO ENEMY.
##
## The no-enemy part is not a convenience. A peer match on skirmish_valley is
## decided at 460-490 s and both economies are rubble by the eighth minute --
## the baseline above ends with BOTH sides on the 40 cr/min headquarters
## trickle, having lost the derricks they started with. That is a fine test of
## whether the AI fights and a useless one of whether it expands. Here it
## develops unmolested and the question is what it did with the time.
##
## `oil_m` is the distance the fields are planted at. skirmish_valley's own
## numbers are ~500 m for the two a player can call its own and ~1,400 m for
## the contested ring; both are outside the 340 m headquarters ring, which is
## the entire point.
func _solo(seed_value: int, level: int, profile: int, credits := 8000.0,
		start_epoch := 4, ceiling := 6, oil_m := 500.0) -> Dictionary:
	var w := SimWorld.new(seed_value)
	w.use_accumulator = false
	w.use_terrain(SimTerrain.new(48, 48, 250.0, "test flat"))
	var setup := SimPlayerSetup.new({
		"name": "AI", "faction": SimPlayerSetup.Faction.RUSSIA,
		"skill": level, "doctrine": SimDoctrine.make(profile),
		"start_epoch": start_epoch, "ceiling_epoch": ceiling})
	var director := w.add_ai(1, 1, setup)
	w.economy.add_player(1, credits, start_epoch, ceiling)
	# Four wells on the near ring and two on a far one, so the test can tell
	# "it walked to the cheap field" from "it walked to every field".
	for k in range(4):
		var a: float = TAU * float(k) / 4.0 + 0.4
		w.economy.add_oil_field(cos(a) * oil_m, sin(a) * oil_m)
	for k in range(2):
		var a2: float = TAU * float(k) / 2.0 + 1.1
		w.economy.add_oil_field(cos(a2) * oil_m * 2.8, sin(a2) * oil_m * 2.8)
	for row in SimMatch.BASE_LAYOUT:
		w.economy.place_starting_unit(1, String(row[0]), float(row[1]),
			float(row[2]))
	return {"world": w, "ai": director, "setup": setup}


func _own_roles(d: SimAiDirector) -> Dictionary:
	var out := {}
	for i in d.view.forces.indices():
		if not d.view.forces.is_structure(i):
			continue
		var sd := d.view.own_def(i)
		if sd != null:
			out[sd.role] = int(out.get(sd.role, 0)) + 1
	return out


## Derricks this player owns that are actually STANDING ON a published field.
## The test may ask this of ground truth; the AI may not.
func _derricks_on_fields(w: SimWorld, pid: int) -> int:
	var n := 0
	for k in range(w.economy.oil_fields.size()):
		var i := w.economy.derrick_on(k)
		if i >= 0 and w.entities.owner[i] == pid:
			n += 1
	return n


## A hand-built base picture, so the siting rules can be asked a question with
## a known answer rather than whatever a live match happened to produce.
func _yard(unit: int, x: float, z: float, radius: float,
		footprint := 12.0) -> SimAiWorks.Yard:
	var y := SimAiWorks.Yard.new()
	y.unit = unit
	y.x = x
	y.z = z
	y.radius_m = radius
	y.footprint_m = footprint
	y.role = "hq"
	y.operational = true
	return y


# ═══════════════════════════════════════════════════════════════════════════
# 1. THE CREEP: a relay must move the frontier
# ═══════════════════════════════════════════════════════════════════════════

func _suite_the_creep_gains_ground() -> void:
	_suite("A relay at the rim carries the build envelope outward")

	var pic: Array = [_yard(0, 0.0, 0.0, 340.0, 26.0)]
	var terrain := SimTerrain.new(48, 48, 250.0, "flat")
	var depot := SimRoster.make("supply_depot", 4, -1)
	_ok("the relay the roster offers has a ring worth carrying",
		depot != null and depot.build_radius_m > 100.0,
		"%.0f m for %.0f cr" % [depot.build_radius_m, depot.cost])

	# A field 500 m out against a 340 m ring: 160 m short, which is the exact
	# shape of skirmish_valley's own fields.
	var gap := SimAiWorks.shortfall(pic, 500.0, 0.0)
	_ok("a field 500 m out is genuinely outside the envelope", gap > 100.0,
		"%.0f m short" % gap)
	_ok("and one relay is enough to cover it",
		SimAiWorks.relays_needed(pic, depot, 500.0, 0.0) == 1,
		"%d relay(s)" % SimAiWorks.relays_needed(pic, depot, 500.0, 0.0))

	var spot := SimAiWorks.creep(pic, terrain, depot, 500.0, 0.0)
	_ok("the creep found a spot for it", spot.size() >= 2)
	if spot.size() < 2:
		return
	var out_m := sqrt(spot[0] * spot[0] + spot[1] * spot[1])
	_ok("the relay stands at the RIM, not in the courtyard", out_m > 250.0,
		"%.0f m from the headquarters, inside its %.0f m ring"
			% [out_m, 340.0])
	_ok("and it is still legal -- the creep never steps outside the ring",
		SimAiWorks.legal(pic, terrain, depot, spot[0], spot[1]),
		"(%.0f, %.0f)" % [spot[0], spot[1]])

	# THE WHOLE POINT, asserted directly: with the relay standing, the field
	# is inside the envelope and a derrick has somewhere to go.
	pic.append(_yard(1, spot[0], spot[1], depot.build_radius_m, 8.0))
	_ok("with it standing, the field is inside the envelope",
		SimAiWorks.shortfall(pic, 500.0, 0.0) <= 0.0,
		"%.0f m short" % SimAiWorks.shortfall(pic, 500.0, 0.0))
	var derrick := SimRoster.make("oil_derrick", 4, -1)
	var well := SimAiWorks.near(pic, terrain, derrick, 500.0, 0.0)
	_ok("and the derrick can stand ON it, which is what the engine demands",
		well.size() >= 2 and sqrt(pow(well[0] - 500.0, 2.0)
			+ pow(well[1], 2.0)) < 90.0,
		"(%.0f, %.0f)" % [well[0], well[1]] if well.size() >= 2 else "no site")


# ═══════════════════════════════════════════════════════════════════════════
# 2. THE REFUSAL. Ironfront's rimYardSpot exists because its first version
#    "swept from the home marker, found nothing, and left a 3,000-credit rig
#    idle all match". Ours has the mirror failure available: a relay that
#    lands beside the last one and moves the frontier by nothing.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_a_relay_that_gains_nothing_is_refused() -> void:
	_suite("A relay that would not move the frontier is not bought")

	var terrain := SimTerrain.new(48, 48, 250.0, "flat")
	var depot := SimRoster.make("supply_depot", 4, -1)

	# Already in reach: there is nothing for a relay to do.
	var near_pic: Array = [_yard(0, 0.0, 0.0, 340.0, 26.0)]
	_ok("a target already inside the envelope buys no relay at all",
		SimAiWorks.creep(near_pic, terrain, depot, 200.0, 0.0).is_empty(),
		"200 m out, %.0f m short"
			% SimAiWorks.shortfall(near_pic, 200.0, 0.0))

	# A relay with no build radius of its own carries nothing, whatever it
	# costs -- so the rule is about the RING, not about the building.
	var barracks := SimRoster.make("barracks", 4, -1)
	var ringless := SimUnitDef.new()
	ringless.is_structure = true
	ringless.footprint_m = 10.0
	ringless.build_radius_m = 0.0
	_ok("a building with no ring is never a relay",
		SimAiWorks.creep(near_pic, terrain, ringless, 900.0, 0.0).is_empty())
	_ok("while one with a ring is", barracks.build_radius_m > 0.0
			and not SimAiWorks.creep(near_pic, terrain, barracks, 900.0,
				0.0).is_empty(),
		"barracks ring %.0f m" % barracks.build_radius_m)

	# THE GAIN TEST ITSELF. A well 4 km away is still 3.4 km away after one
	# relay, so demanding more ground than a relay can cover comes back empty:
	# the frontier moved, but not far enough to be worth the money.
	_ok("a gain smaller than the threshold is reported as NO SITE",
		SimAiWorks.creep(near_pic, terrain, depot, 4000.0, 0.0,
			10000.0).is_empty(),
		"4 km out, with a 10,000 m gain demanded")
	# AND THE EXCEPTION THAT COST AN AFTERNOON: the hop that ARRIVES is always
	# worth taking, however little was left. The AI had walked a refinery out
	# to 283 m, which left the well 20 m outside the envelope, and then
	# refused every relay that would have covered those 20 m because 20 is
	# less than 45. It stood the supply depot down, tried a barracks, stood
	# that down, tried a helipad, and cycled like that for the whole match.
	var short_pic: Array = [_yard(0, 0.0, 0.0, 340.0, 26.0)]
	_ok("but the hop that ARRIVES is taken however little was left",
		not SimAiWorks.creep(short_pic, terrain, depot, 360.0, 0.0,
			10000.0).is_empty(),
		"20 m short, with a 10,000 m gain demanded")

	# A base of nothing but unfinished buildings projects no envelope, so
	# there is nothing to creep FROM. This is the case that would otherwise
	# site every relay of a chain on top of the first one.
	var building: Array = [_yard(0, 0.0, 0.0, 340.0, 26.0)]
	(building[0] as SimAiWorks.Yard).operational = false
	_ok("an unfinished base projects no envelope and creeps nowhere",
		SimAiWorks.shortfall(building, 500.0, 0.0) == INF
			and SimAiWorks.creep(building, terrain, depot, 500.0, 0.0).is_empty())


# ═══════════════════════════════════════════════════════════════════════════
# 3. THE CHAIN TERMINATES
# ═══════════════════════════════════════════════════════════════════════════

func _suite_the_chain_is_bounded() -> void:
	_suite("A chain of relays ends, and it ends where it was told to")

	var terrain := SimTerrain.new(48, 48, 250.0, "flat")
	var depot := SimRoster.make("supply_depot", 4, -1)
	var pic: Array = [_yard(0, 0.0, 0.0, 340.0, 26.0)]

	var hops := 0
	var reach := 0.0
	while hops < 40:
		var spot := SimAiWorks.creep(pic, terrain, depot, 4000.0, 0.0)
		if spot.size() < 2:
			break
		hops += 1
		pic.append(_yard(hops, spot[0], spot[1], depot.build_radius_m, 8.0))
		reach = maxf(reach, sqrt(spot[0] * spot[0] + spot[1] * spot[1]))
	_ok("each relay really does extend the reach", hops > 3 and reach > 800.0,
		"%d relay(s), furthest %.0f m out" % [hops, reach])
	_ok("and the walk terminates rather than looping",
		hops < 40, "%d relay(s) to walk 4 km" % hops)

	# The cap the director enforces is on the COUNT, and it is quoted here so
	# a roster change that shrank every build radius cannot silently turn a
	# four-shed walk into a twenty-shed one.
	var fresh: Array = [_yard(0, 0.0, 0.0, 340.0, 26.0)]
	_ok("a field 4 km out is priced as more relays than the cap allows",
		SimAiWorks.relays_needed(fresh, depot, 4000.0, 0.0)
			> SimAiWorks.CREEP_MAX_RELAYS,
		"%d needed against a cap of %d"
			% [SimAiWorks.relays_needed(fresh, depot, 4000.0, 0.0),
				SimAiWorks.CREEP_MAX_RELAYS])
	_ok("while the 500 m field the arena actually has is within it",
		SimAiWorks.relays_needed(fresh, depot, 500.0, 0.0)
			<= SimAiWorks.CREEP_MAX_RELAYS)


# ═══════════════════════════════════════════════════════════════════════════
# 4. THE BLUNT MEASURE: a derrick on a field, in a live world
#
# "its income is capped at what its two starting derricks pump, and it cannot
# build more derricks because the oil sits at 576 m and 1034 m from base while
# its whole build envelope is the HQ's 340 m ring."
# ═══════════════════════════════════════════════════════════════════════════

func _suite_it_stands_a_derrick_on_a_field() -> void:
	_suite("It walks out of its own base and stands a derrick on a well")

	var s := _solo(501, SimSkill.Level.VETERAN, SimDoctrine.Profile.COMBINED_ARMS)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector

	# The fault, stated as a fact about the world before the AI is given a
	# chance: not one field is inside the envelope it starts with.
	var reachable_at_start := 0
	var derrick_def := d.view.def_for("oil_derrick")
	for f in w.economy.oil_fields:
		if w.economy.placement_problem(1, derrick_def, f.x, f.y) == "":
			reachable_at_start += 1
	_ok("not one well is inside the envelope a start owns",
		reachable_at_start == 0,
		"%d of %d reachable at t=0" % [reachable_at_start,
			w.economy.oil_fields.size()])

	var before := _derricks_on_fields(w, 1)
	w.run_ticks(int(450.0 * SimWorld.SIM_HZ))
	var after := _derricks_on_fields(w, 1)

	_ok("it built a relay to reach past its own ring", d.relays_built > 0,
		"%d relay(s), %d structure(s) placed, %d refused"
			% [d.relays_built, d.structures_placed, d.structures_refused])
	_ok("AND A DERRICK IS STANDING ON A WELL, where none ever was",
		after > before, "%d -> %d derrick(s) on fields" % [before, after])

	# And it is a well it did NOT start next to: the starting derricks sit at
	# (+-170, 110) and every field is 500 m out or further.
	var furthest := 0.0
	for k in range(w.economy.oil_fields.size()):
		var i := w.economy.derrick_on(k)
		if i >= 0 and w.entities.owner[i] == 1:
			furthest = maxf(furthest, sqrt(pow(w.entities.pos_x[i]
				- d.home_x, 2.0) + pow(w.entities.pos_z[i] - d.home_z, 2.0)))
	_ok("on ground outside the ring it was born with", furthest > 340.0,
		"furthest derrick %.0f m from home, hq ring 340 m" % furthest)


# ═══════════════════════════════════════════════════════════════════════════
# 5. THE PAIR OF TAPS
#
# SimEconomy pays min(extraction, refine). The AI used to size its refineries
# off its INCOME, which is the output of that pair -- so at 480 crude against
# 520 of refining its income said "fine" at the exact moment another derrick
# would have earned 40 credits a minute instead of 240.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_the_taps_are_kept_level() -> void:
	_suite("It buys pipe for its crude and crude for its pipe")

	var s := _solo(502, SimSkill.Level.ELITE, SimDoctrine.Profile.COMBINED_ARMS,
		14000.0)
	# FIFTEEN MINUTES, and the length is a measurement rather than a
	# convenience: the growth bucket fills at 55% of income, so a 2,520-credit
	# refinery is about nine minutes of saving on a starting economy. Ten
	# minutes catches the derrick and not the pipe behind it.
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector

	w.run_ticks(20)          # the purse's aggregates are recomputed on a tick
	var p0 := w.economy.purse(1)
	var crude0 := p0.extraction_per_min
	var pipe0 := p0.refine_capacity
	var income0 := p0.income_per_min
	_ok("a start pumps almost exactly what it can refine, and no more",
		crude0 > 0.0 and pipe0 > 0.0 and absf(crude0 - pipe0) < pipe0 * 0.2,
		"%.0f crude/min against %.0f of refining" % [crude0, pipe0])

	w.run_ticks(int(900.0 * SimWorld.SIM_HZ))
	var p1 := w.economy.purse(1)
	_ok("fifteen minutes later it is pumping more", p1.extraction_per_min > crude0,
		"%.0f -> %.0f crude/min" % [crude0, p1.extraction_per_min])
	_ok("and it bought the pipe to process it rather than flaring it off",
		p1.refine_capacity >= p1.extraction_per_min * 0.75,
		"%.0f of refining against %.0f of crude"
			% [p1.refine_capacity, p1.extraction_per_min])
	_ok("SO THE INCOME ROSE, which it never did before",
		p1.income_per_min > income0 * 1.3,
		"%.0f -> %.0f cr/min" % [income0, p1.income_per_min])
	_ok("and the AI measured the rise on its own bank statement",
		d._income_ema > income0 / 60.0,
		"%.1f cr/s measured" % d._income_ema)

	# The refinery farm, which is the failure this rule can produce if it
	# forgets what is under construction -- the same trap the power rule fell
	# into and documents.
	var roles := _own_roles(d)
	_ok("it did not become a refinery farm",
		int(roles.get("refinery", 0)) <= SimAiDirector.REFINERY_CAP,
		"%d refiner(y/ies), cap %d" % [int(roles.get("refinery", 0)),
			SimAiDirector.REFINERY_CAP])


# ═══════════════════════════════════════════════════════════════════════════
# 6. THE CLIMB, paid for out of income rather than out of a handout
#
# test_ai_works.gd proves the AI climbs when it is GIVEN 40,000 credits. This
# asks the harder question: does it climb on a peer opening float, because it
# grew the economy that pays for the step?
# ═══════════════════════════════════════════════════════════════════════════

func _suite_it_climbs_on_what_it_earned() -> void:
	_suite("It climbs an epoch on money it went out and earned")

	# THE FIXTURE IS RICH ON PURPOSE, and saying why is the honest half of
	# this result. A 26,000-credit start is not a peer opening (that is
	# 8,000); it is the smallest float that fits the whole arc inside a test,
	# because the arc itself is long. Measured on a peer float at epoch 4:
	# relay at 40 s, derrick at 241 s, the refinery its crude needs at 620 s,
	# the research facility at 1,200 s, and the 6,100-credit step past
	# 2,000 s. The growth bucket fills at 55% of income and a start earns 8.7
	# credits a second, so even with the economy up 46% the saving alone is
	# fifteen minutes.
	#
	# What is asserted here is the ORDER and the DESTINATION -- that the AI
	# walks the economy up, then buys the enabler, then takes the step -- and
	# every one of those was a thing it never did. How long the step takes at
	# a peer float is a PRICE question, and it belongs in the report.
	var s := _solo(503, SimSkill.Level.ELITE, SimDoctrine.Profile.TECH_RUSH,
		26000.0)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	var start_epoch := w.economy.purse(1).epoch
	var start_income := 0.0
	w.run_ticks(20)
	start_income = w.economy.purse(1).income_per_min

	w.run_ticks(int(900.0 * SimWorld.SIM_HZ))
	var purse := w.economy.purse(1)

	_ok("it grew the economy rather than living off the float",
		purse.income_per_min > start_income,
		"%.0f -> %.0f cr/min" % [start_income, purse.income_per_min])
	_ok("and it walked out to do it", d.relays_built > 0,
		"%d relay(s)" % d.relays_built)
	_ok("the enabler is standing",
		int(_own_roles(d).get("research_facility", 0)) > 0,
		"%d structure(s) placed" % d.structures_placed)
	_ok("IT LEFT ITS STARTING EPOCH, which it never did in a measured match",
		purse.epoch > start_epoch or purse.is_advancing(),
		"epoch %d -> %d%s, %d request(s)" % [start_epoch, purse.epoch,
			" (advancing)" if purse.is_advancing() else "",
			d.epoch_advances_requested])
	_ok("through its own begin_epoch_advance and no other route",
		d.epoch_advances_requested > 0,
		"%d request(s)" % d.epoch_advances_requested)
	_ok("and it still fielded an army while doing it",
		d.orders_production > 6, "%d order(s)" % d.orders_production)


# ═══════════════════════════════════════════════════════════════════════════
# 7. A WELL IT CANNOT HAVE
#
# The AI may not ask who holds a field -- SimEconomy.derrick_on() walks every
# structure on the map whoever owns it. So it finds out by walking there and
# being refused, and the refusal has to send it to the NEXT well rather than
# back to the same one every eight seconds.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_a_refused_well_is_left_alone() -> void:
	_suite("A well that will not take a derrick is left alone for a while")

	var s := _solo(504, SimSkill.Level.VETERAN, SimDoctrine.Profile.COMBINED_ARMS)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	w.run_ticks(20)

	_ok("the AI can see the wells as map features", d.view.oil_points().size() > 0,
		"%d well(s)" % d.view.oil_points().size())
	_ok("and it holds none of them yet",
		not d._own_derrick_near(d.view.oil_points()[0]))

	# Drive the refusal by hand: pretend the order for well 0 went in and came
	# back refused, which is exactly what the engine does when somebody else
	# is already pumping it.
	var f: Vector2 = d.view.oil_points()[0]
	d._pending_build = ["oil_derrick", f.x, f.y]
	d._pending_known.clear()
	for i in d.view.forces.indices():
		if d.view.forces.is_structure(i):
			d._pending_known[i] = true
	var cooled_before: int = d._field_cool.size()
	d._confirm_pending_build()
	_ok("a refused derrick cools THAT well rather than the whole role",
		d._field_cool.size() > cooled_before,
		"%d well(s) on cooldown" % d._field_cool.size())
	_ok("for Ironfront's seventy seconds",
		absf(float(d._field_cool.values()[0]) - d.elapsed_s
			- SimAiWorks.FAIL_COOL_S) < 0.01,
		"%.0f s" % SimAiWorks.FAIL_COOL_S)

	# And expansion now aims somewhere else, which is the behaviour the
	# cooldown exists for.
	var want := d._expansion_want(_own_roles(d))
	if want.is_empty():
		_ok("expansion had nothing else to aim at, which is a legal answer",
			true)
	else:
		_ok("and expansion now aims at a different well",
			absf(float(want[2]) - f.x) > 1.0 or absf(float(want[3]) - f.y) > 1.0,
			"aiming at (%.0f, %.0f) instead of (%.0f, %.0f)"
				% [float(want[2]), float(want[3]), f.x, f.y])


# ═══════════════════════════════════════════════════════════════════════════
# 8. NONE OF THIS REACHED FOR ANYTHING IT DOES NOT OWN (docs/09 §1)
# ═══════════════════════════════════════════════════════════════════════════

func _suite_expansion_survived_the_firewall() -> void:
	_suite("Expansion is inference from public ground, not a peek")

	var s := _solo(505, SimSkill.Level.ELITE, SimDoctrine.Profile.COMBINED_ARMS)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector

	# A SECOND PLAYER, holding a well the first one wants. The AI must not be
	# able to tell that well from an empty one until the engine refuses it.
	w.economy.add_player(2, 5000.0, 4, 6)
	var f: Vector2 = w.economy.oil_fields[0]
	w.economy.place_starting_unit(2, "hq", f.x, f.y - 120.0)
	w.economy.place_starting_unit(2, "oil_derrick", f.x, f.y)
	w.run_ticks(40)

	_ok("the well really is held by somebody else",
		w.economy.derrick_on(0) >= 0
			and w.entities.owner[w.economy.derrick_on(0)] == 2,
		"derrick_on(0) -> player %d"
			% w.entities.owner[w.economy.derrick_on(0)])
	_ok("and the AI's own answer is still NO, I do not hold it",
		not d._own_derrick_near(f),
		"which is the only question it is allowed to ask")

	var denied_before: int = d.view.forces.denied_queries
	d._expansion_want(_own_roles(d))
	d._build_site(d.view.def_for("oil_derrick"))
	d._relay_def()
	_ok("deciding to expand reached for nothing it does not own",
		d.view.forces.denied_queries == denied_before,
		"%d denied quer(y/ies)" % (d.view.forces.denied_queries - denied_before))

	# The static half, which is the one that survives a refactor: the whole
	# expansion path is in sim/ai/, and nothing in sim/ai/ names the calls
	# that would answer "who holds that well".
	var offences := PackedStringArray()
	# The one exemption test_ai.gd already makes: the own-forces view IS the
	# fence, and a fence has to hold the thing it fences off.
	for fname in DirAccess.get_files_at("res://sim/ai"):
		if not (fname as String).ends_with(".gd"):
			continue
		if fname == "sim_own_forces_view.gd":
			continue
		var fa := FileAccess.open("res://sim/ai/" + fname, FileAccess.READ)
		var line_no := 0
		for raw in fa.get_as_text().split("\n"):
			line_no += 1
			var line: String = raw
			var hash_at := line.find("#")
			if hash_at >= 0:
				line = line.substr(0, hash_at)
			for token in ["placement_problem", "derrick_on", "oil_field_at",
					"indices_of_owner"]:
				if line.contains(token):
					offences.append("%s:%d %s" % [fname, line_no, token])
	_ok("and no line of sim/ai/ calls the engine's own who-holds-what tests",
		offences.is_empty(),
		"; ".join(offences) if not offences.is_empty() else "clean")

	# The fields themselves are TERRAIN. Positions, in a fixed order, and
	# nothing else -- no owner, no derrick, no occupancy.
	var pts := d.view.oil_points()
	var all_vec := true
	for p in pts:
		if typeof(p) != TYPE_VECTOR2:
			all_vec = false
	_ok("the view hands out coordinates and nothing else",
		all_vec and pts.size() == w.economy.oil_fields.size(),
		"%d Vector2(s)" % pts.size())
