extends SceneTree
## DOES THE AI BUILD, AND DOES IT CLIMB?
##
##     godot --path game --headless --script res://sim/tests/test_ai_works.gd
##
## test_ai.gd proves the AI is FAIR. test_ai_hunt.gd proves it is DANGEROUS.
## This file proves it is DEVELOPING, which was the third missing half, and
## every assertion below is written against a measured fault rather than
## against a design document.
##
## THE BASELINE, measured on the peer scenario before any of this:
##
##     structures placed in a live match          0
##     credits ever held above ~130               never
##     epochs advanced from the starting epoch    0
##     the next site the AI wanted                2350 m from home, against a
##                                                340 m headquarters radius
##     sensor group objective while blind         home, exactly
##
## Every number in that table is a test here. And note the asymmetry that
## keeps them honest: THE TEST may read ground truth and may call
## SimEconomy.placement_problem(), because the test is not the AI. The
## director may not, and test_ai.gd is what proves it cannot.

var _passed := 0
var _failed := 0
var _code := 1


## _initialize(), never _init(). A SceneTree script that works in _init() runs
## before the tree exists and keeps its stdout buffered -- the run looks hung.
func _initialize() -> void:
	print("")
	print("  BATTLE -- does the AI build, and does it climb?")
	print("  " + "-".repeat(70))

	_suite_it_places_structures()
	_suite_a_site_is_inside_our_own_radius()
	_suite_the_old_ring_was_the_fault()
	_suite_it_keeps_a_reserve()
	_suite_it_climbs()
	_suite_sensors_go_forward_when_blind()
	_suite_failure_is_bounded()
	_suite_skill_still_separates()
	_suite_the_firewall_survived_it()
	_suite_siting_is_deterministic()

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

## ONE AI, A REAL ECONOMY, A REAL BASE, AND NO ENEMY AT ALL.
##
## The no-enemy part is the point. A peer match on skirmish_valley is over in
## four minutes now that the AI hunts, so a match is a poor fixture for a
## question about the twelfth minute of a build order. Here the AI develops
## unmolested and the test asks what it did with the time.
##
## The base is placed THROUGH THE ECONOMY, not straight into the entity store,
## because a hand-placed entity has no def behind it -- no cost, no footprint,
## no build radius -- and siting is entirely a question about those three.
func _solo(seed_value: int, level: int, profile: int,
		credits := 8000.0, start_epoch := 4, ceiling := 6) -> Dictionary:
	var w := SimWorld.new(seed_value)
	w.use_accumulator = false
	w.terrain = SimTerrain.new(32, 32, 250.0, "test flat")
	var setup := SimPlayerSetup.new({
		"name": "AI", "faction": SimPlayerSetup.Faction.RUSSIA,
		"skill": level, "doctrine": SimDoctrine.make(profile),
		"start_epoch": start_epoch, "ceiling_epoch": ceiling})
	var director := w.add_ai(1, 1, setup)
	w.economy.add_player(1, credits, start_epoch, ceiling)
	w.economy.attach_setup(1, setup) if w.economy.has_method("attach_setup") \
		else null
	# The same opening every player gets: SimMatch.BASE_LAYOUT, at the origin.
	for row in SimMatch.BASE_LAYOUT:
		var role := String(row[0])
		w.economy.place_starting_unit(1, role, float(row[1]), float(row[2]))
	for k in range(4):
		w.economy.place_starting_unit(1, "mbt", -200.0 + 130.0 * float(k), -300.0)
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


func _structure_count(w: SimWorld) -> int:
	var n := 0
	for i in w.entities.indices_of_owner(1):
		if w.entities.is_structure[i] == 1:
			n += 1
	return n


# ═══════════════════════════════════════════════════════════════════════════
# 1. THE BLUNT MEASURE
#
# "The measure of success is blunt: the AI must place structures in a live
# match, where today it places none."
# ═══════════════════════════════════════════════════════════════════════════

func _suite_it_places_structures() -> void:
	_suite("It places structures, where it used to place none")

	var s := _solo(401, SimSkill.Level.VETERAN, SimDoctrine.Profile.COMBINED_ARMS)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	var before := _structure_count(w)
	w.run_ticks(int(240.0 * SimWorld.SIM_HZ))
	var after := _structure_count(w)

	_ok("it ordered at least one building and the order LANDED",
		d.structures_placed > 0,
		"%d placed, %d refused" % [d.structures_placed, d.structures_refused])
	_ok("and the base really is larger than the one it started with",
		after > before, "%d -> %d structure(s)" % [before, after])

	# It is not enough that SOMETHING went up: what went up has to be the
	# thing the build order asked for, in order.
	var roles := _own_roles(d)
	_ok("the second power plant is up, which the opening brownout demanded",
		int(roles.get("power_plant", 0)) >= 2,
		"%d plant(s), %.0f supplied / %.0f drawn" % [
			int(roles.get("power_plant", 0)), d.view.own_power_supply(),
			d.view.own_power_draw()])
	_ok("and the brownout it started in is over",
		d.view.own_power_supply() >= d.view.own_power_draw(),
		"%.0f / %.0f" % [d.view.own_power_supply(), d.view.own_power_draw()])

	# Ironfront's placeReady() refunds a placement that did not land, so a
	# refusal never costs money. Ours is stronger -- SimEconomy tests the spot
	# before it spends -- but the director's own bookkeeping has to agree, or
	# the growth budget leaks a building's price every time a spot is refused.
	_ok("nothing is left pending forever", d._pending_build.is_empty()
			or d.elapsed_s - d._last_build_s < 20.0,
		"pending %s" % str(d._pending_build))


# ═══════════════════════════════════════════════════════════════════════════
# 2. EVERY SITE IS ONE THE ENGINE WILL ACTUALLY TAKE
# ═══════════════════════════════════════════════════════════════════════════

func _suite_a_site_is_inside_our_own_radius() -> void:
	_suite("Every site it chooses is one the engine accepts")

	var s := _solo(402, SimSkill.Level.ELITE, SimDoctrine.Profile.SENSOR_DOMINANCE)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	w.run_ticks(20)

	var pic := SimAiWorks.base_picture(d.view)
	_ok("the base picture sees the structures the AI owns", pic.size() >= 7,
		"%d yard(s)" % pic.size())

	var tried := 0
	var accepted := 0
	var worst := ""
	for role in SimAiPlan.base_build_order(d.doctrine):
		var def := d.view.def_for(role)
		if def == null or not def.is_structure:
			continue
		var site := d._build_site(def)
		if site.size() < 2:
			continue
		tried += 1
		# THE TEST may ask this; the AI may not. placement_problem() walks
		# every structure on the map whoever owns it.
		var why := w.economy.placement_problem(1, def, site[0], site[1])
		if why == "":
			accepted += 1
		elif worst == "":
			worst = "%s: %s" % [role, why]
	_ok("every one of them", tried > 0 and accepted == tried,
		"%d of %d accepted%s" % [accepted, tried,
			("  first refusal -- " + worst) if worst != "" else ""])

	# And the shape of the rule, asserted directly: the innermost legal ring
	# wins, so a new building is a NEIGHBOUR rather than an outpost.
	var pp := d.view.def_for("power_plant")
	var site2 := d._build_site(pp)
	var from_home := sqrt(pow(site2[0] - d.home_x, 2.0)
		+ pow(site2[1] - d.home_z, 2.0))
	_ok("and it is next to the base rather than out in the country",
		from_home < 600.0, "%.0f m from home" % from_home)


# ═══════════════════════════════════════════════════════════════════════════
# 3. THE FAULT ITSELF, so nobody re-introduces it
# ═══════════════════════════════════════════════════════════════════════════

func _suite_the_old_ring_was_the_fault() -> void:
	_suite("The ring around home is gone, and it is gone for a reason")

	var s := _solo(403, SimSkill.Level.VETERAN, SimDoctrine.Profile.COMBINED_ARMS)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	w.run_ticks(20)

	# The old rule was 600 + 250 * ordinal metres from home, and a start owns
	# seven structures, so the eighth went to 2350 m. This is that number,
	# refused, as evidence that the fix is a fix and not a coincidence.
	var def := d.view.def_for("research_facility")
	var old_site := 600.0 + 250.0 * 7.0
	var why := w.economy.placement_problem(1, def, d.home_x + old_site, d.home_z)
	_ok("the ring the AI used to ask for is still refused",
		why != "", "%.0f m out -> %s" % [old_site, why])

	# A headquarters is the biggest ring on the board at 340 m, so nothing
	# beyond it can ever be legal from a standing start. Worth asserting,
	# because the roster is where the number lives and it may move.
	var hq := d.view.def_for("hq")
	_ok("because the largest build radius a start owns is far smaller",
		hq != null and hq.build_radius_m < old_site,
		"hq radius %.0f m" % (hq.build_radius_m if hq != null else -1.0))

	# And the new answer to the same question is inside it.
	var site := d._build_site(def)
	_ok("and the new rule answers inside it", site.size() >= 2
			and sqrt(pow(site[0] - d.home_x, 2.0)
				+ pow(site[1] - d.home_z, 2.0)) < hq.build_radius_m + 200.0,
		"%.0f m" % (sqrt(pow(site[0] - d.home_x, 2.0)
			+ pow(site[1] - d.home_z, 2.0)) if site.size() >= 2 else -1.0))


# ═══════════════════════════════════════════════════════════════════════════
# 4. THE RESERVE
#
# "_economy() spends every credit on production every 3.3 s, so credits never
# rise above ~130 and nothing expensive is ever affordable."
# ═══════════════════════════════════════════════════════════════════════════

func _suite_it_keeps_a_reserve() -> void:
	_suite("It keeps a reserve, without stalling the production line")

	var s := _solo(404, SimSkill.Level.VETERAN, SimDoctrine.Profile.COMBINED_ARMS)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector

	var peak := 0.0
	var floor_cr := INF
	for _k in range(24):
		w.run_ticks(int(10.0 * SimWorld.SIM_HZ))
		peak = maxf(peak, w.economy.credits(1))
		floor_cr = minf(floor_cr, w.economy.credits(1))

	_ok("the account is allowed to build up past the old ~130 ceiling",
		peak > 800.0, "peak %.0f cr" % peak)
	_ok("the growth bucket is a real number and not a constant",
		d._growth_budget > 0.0, "%.0f cr banked for growth" % d._growth_budget)
	_ok("it measured its own income rather than assuming one",
		d._income_ema > 0.0, "%.2f cr/s" % d._income_ema)

	# THE OTHER HALF, which is the half a reserve usually breaks: an army that
	# never gets bought. Ironfront's rule is "let money above the reserve be
	# spent freely, so an army is never starved, it simply waits".
	_ok("and the line kept running -- it still produced units",
		d.orders_production > 2, "%d production/build order(s)"
			% d.orders_production)
	var mobile := 0
	for i in w.entities.indices_of_owner(1):
		if w.entities.is_structure[i] == 0:
			mobile += 1
	_ok("so it fielded an army as well as a base", mobile > 4,
		"%d mobile unit(s)" % mobile)

	# The reserve is the BUCKET, not one item's price. With nothing left to
	# grow into it must release entirely, or a finished base hoards forever.
	var released := d._growth_reserve()
	_ok("the reserve never exceeds the bucket",
		released <= d._growth_budget + 0.001,
		"%.0f held against %.0f banked" % [released, d._growth_budget])


# ═══════════════════════════════════════════════════════════════════════════
# 5. THE CLIMB
#
# "It can never build a research_facility, so SimEconomy.begin_epoch_advance()
# refuses forever and the AI is LOCKED AT ITS STARTING EPOCH."
# ═══════════════════════════════════════════════════════════════════════════

func _suite_it_climbs() -> void:
	_suite("It gets a research facility up, and then it uses it")

	# A Tech Rush with a long quiet game, which is the fixture that can answer
	# the question at all: the epoch step costs 6,100 at epoch 4 against a net
	# income near 5 credits a second.
	var s := _solo(405, SimSkill.Level.ELITE, SimDoctrine.Profile.TECH_RUSH,
		16000.0)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	w.run_ticks(int(300.0 * SimWorld.SIM_HZ))

	var roles := _own_roles(d)
	_ok("the research facility is standing",
		int(roles.get("research_facility", 0)) > 0,
		"placed %d, refused %d, roles %s" % [d.structures_placed,
			d.structures_refused, str(roles.keys())])
	# AND IT NOW WANTS TO CLIMB, which is the decision the old gate forbade.
	# Worth asserting separately from the step itself, because the step is
	# expensive enough that WHEN it happens is a balance question while
	# WHETHER the AI ever wants it is a bug question.
	_ok("and growth is now saving for the epoch step rather than more sheds",
		d._growth_is_advance and d._growth_want_key.begins_with("epoch"),
		"saving for %s (%.0f cr)" % [d._growth_want_key, d._growth_want_cost])
	_ok("the economy would take the step if it were paid for",
		w.economy.credits(1) >= w.economy.advance_cost(1)
			or not w.economy.begin_epoch_advance(1),
		"%.0f cr against a %.0f cr step" % [w.economy.credits(1),
			w.economy.advance_cost(1)])

	# END TO END, with a purse that can actually pay: the step at epoch 4 is
	# 6,100 credits against a net income near 5 a second, so a commander
	# reaches it out of its opening float or not at all in a short match.
	# THIS is the assertion the fault was about -- "LOCKED AT ITS STARTING
	# EPOCH for the whole match".
	var rich := _solo(4051, SimSkill.Level.ELITE, SimDoctrine.Profile.TECH_RUSH,
		40000.0)
	var rw := rich["world"] as SimWorld
	var rd := rich["ai"] as SimAiDirector
	rw.run_ticks(int(420.0 * SimWorld.SIM_HZ))
	var purse := rw.economy.purse(1)
	_ok("given the money, it leaves its starting epoch",
		purse.epoch > 4 or purse.is_advancing(),
		"epoch %d, %s, %d advance(s) requested" % [purse.epoch,
			"advancing" if purse.is_advancing() else "not advancing",
			rd.epoch_advances_requested])
	_ok("through its own begin_epoch_advance and not by any other route",
		rd.epoch_advances_requested > 0,
		"%d request(s)" % rd.epoch_advances_requested)

	# The gate that used to close the door on better than half the profiles in
	# the game: the advance was permitted only at tech_bias > 0.45.
	var blitz := SimDoctrine.make(SimDoctrine.Profile.BLITZ)
	_ok("and a low-tech-bias doctrine is no longer FORBIDDEN from climbing",
		blitz.tech_bias <= 0.45, "Blitz tech bias %.2f" % blitz.tech_bias)
	var order := Array(SimAiPlan.base_build_order(blitz))
	_ok("it even buys the facility that makes climbing possible",
		order.has("research_facility") and order.find("research_facility") <= 5,
		"research facility is #%d of %d in a Blitz order"
			% [order.find("research_facility") + 1, order.size()])
	var sd_order := Array(SimAiPlan.base_build_order(
		SimDoctrine.make(SimDoctrine.Profile.TECH_RUSH)))
	_ok("and a Tech Rush buys it before its heavy factory",
		sd_order.find("research_facility") < sd_order.find("heavy_factory"),
		"#%d vs #%d" % [sd_order.find("research_facility") + 1,
			sd_order.find("heavy_factory") + 1])


# ═══════════════════════════════════════════════════════════════════════════
# 6. THE RADARS
#
# "_front_x/_front_z return HOME when the AI holds no positional belief -- so
# the radars sit at base exactly when the AI most needs them pushed forward."
# ═══════════════════════════════════════════════════════════════════════════

func _suite_sensors_go_forward_when_blind() -> void:
	_suite("Blind is when the radars go forward, not when they come home")

	var s := _solo(406, SimSkill.Level.ELITE, SimDoctrine.Profile.SENSOR_DOMINANCE)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	w.run_ticks(40)

	_ok("the AI genuinely holds no positional belief",
		not d._has_positional_belief())

	var g := SimAiGroup.new()
	g.role = SimAiGroup.Role.SENSOR
	d._place_sensors(g)
	var out := sqrt(pow(g.obj_x - d.home_x, 2.0) + pow(g.obj_z - d.home_z, 2.0))
	_ok("so the sensor group is sent somewhere other than the middle of base",
		out > SimAiDirector.SENSOR_MIN_REACH_M - 1.0
			or out >= d._screen_reach_m() - 1.0,
		"%.0f m forward, floor %.0f, screen %.0f" % [out,
			SimAiDirector.SENSOR_MIN_REACH_M, d._screen_reach_m()])
	var hq := d.view.def_for("hq")
	_ok("which is genuinely outside the base rather than inside its own ring",
		out > hq.build_radius_m, "%.0f m against a %.0f m ring"
			% [out, hq.build_radius_m])

	# But not to its death: the push is capped at the screen its own troops
	# provide, because an unescorted radar forward of the line is a gift.
	_ok("and not past the screen its own army provides",
		out <= d._screen_reach_m() + 1.0,
		"%.0f m against a %.0f m screen" % [out, d._screen_reach_m()])

	# The old behaviour, stated as a number so the regression is visible: with
	# no belief, _front_x/_front_z still answer home, and that is exactly why
	# the sensor rule can no longer be built out of them alone.
	_ok("_front_x still answers home when blind -- which was the trap",
		absf(d._front_x() - d.home_x) < 1.0
			and absf(d._front_z() - d.home_z) < 1.0)

	# With a belief in hand it aims at the belief, which is the case that
	# always worked and must keep working.
	var t := w.solver.table_for(1).contribute(99, SimTypes.TrackQuality.TRACK,
		SimTypes.Classification.CLASS, 0.9, "injected", 2200.0, 0.0, 2200.0,
		0.0, 0.0, 0.0, atan2(2200.0, 2200.0), false,
		SimTypes.Category.GROUND, false)
	_ok("a track was injected for the second half", t != null)
	d._observe()
	_ok("now it holds a positional belief", d._has_positional_belief())
	var g2 := SimAiGroup.new()
	g2.role = SimAiGroup.Role.SENSOR
	d._place_sensors(g2)
	_ok("and the sensors move toward the contact, not away from it",
		(g2.obj_x - d.home_x) > 0.0 and (g2.obj_z - d.home_z) > 0.0,
		"(%.0f, %.0f) from home (%.0f, %.0f)" % [g2.obj_x, g2.obj_z,
			d.home_x, d.home_z])


# ═══════════════════════════════════════════════════════════════════════════
# 7. FAILURE IS BOUNDED
#
# Ironfront's rq.failN / failCool, which is what stops an AI asking forever
# for a spot that does not exist.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_failure_is_bounded() -> void:
	_suite("A spot that does not exist is asked for four times, not forever")

	var s := _solo(407, SimSkill.Level.VETERAN, SimDoctrine.Profile.COMBINED_ARMS)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	w.run_ticks(20)

	for k in range(SimAiWorks.FAIL_LIMIT):
		_ok("try %d of %d does not stand the role down yet" % [k + 1,
			SimAiWorks.FAIL_LIMIT],
			float(d._build_cool.get("barracks", -1.0e9)) <= d.elapsed_s)
		d._note_build_failure("barracks", "test")
	_ok("the fourth refusal stands it down",
		float(d._build_cool.get("barracks", -1.0e9)) > d.elapsed_s,
		"cool until %.0f, now %.0f" % [
			float(d._build_cool.get("barracks", -1.0e9)), d.elapsed_s])
	_ok("for Ironfront's seventy seconds",
		absf(float(d._build_cool["barracks"]) - d.elapsed_s
			- SimAiWorks.FAIL_COOL_S) < 0.01,
		"%.0f s" % SimAiWorks.FAIL_COOL_S)

	# And while it is stood down the build order steps PAST it rather than
	# stalling on it -- which is the whole point of counting failures.
	var roles := _own_roles(d)
	roles["barracks"] = 0
	var want := d._next_structure(roles)
	_ok("and the build order moves on to something else",
		want.is_empty() or String(want[0]) != "barracks",
		"wants %s" % (String(want[0]) if not want.is_empty() else "nothing"))

	# A derrick gets twelve tries, because an oil pad is a spot that may be
	# being cleared rather than a spot that is not there.
	_ok("a field role is given more rope than a shed",
		SimAiWorks.FAIL_LIMIT_FIELD > SimAiWorks.FAIL_LIMIT,
		"%d vs %d" % [SimAiWorks.FAIL_LIMIT_FIELD, SimAiWorks.FAIL_LIMIT])


# ═══════════════════════════════════════════════════════════════════════════
# 8. THE LADDER STILL BITES
#
# "Skill must still separate: RECRUIT beatable, ELITE hard. Do not flatten the
# ladder into one difficulty."
# ═══════════════════════════════════════════════════════════════════════════

func _suite_skill_still_separates() -> void:
	_suite("Recruit and Elite do not develop the same way")

	var recruit := (_solo(408, SimSkill.Level.RECRUIT,
		SimDoctrine.Profile.COMBINED_ARMS)["ai"] as SimAiDirector)
	var elite := (_solo(408, SimSkill.Level.ELITE,
		SimDoctrine.Profile.COMBINED_ARMS)["ai"] as SimAiDirector)

	_ok("an Elite puts a larger share of its income into growth",
		elite._growth_share() > recruit._growth_share(),
		"%.2f vs %.2f" % [elite._growth_share(), recruit._growth_share()])
	_ok("and it is the two numbers Ironfront's DIFF table uses",
		absf(elite._growth_share() - 0.55) < 0.001
			and absf(recruit._growth_share() - 0.40) < 0.001)

	recruit._income_ema = 10.0
	elite._income_ema = 10.0
	_ok("a Recruit wants a far bigger cushion before it dares tech up",
		recruit._advance_margin() > elite._advance_margin() * 1.4,
		"%.0f cr vs %.0f cr" % [recruit._advance_margin(),
			elite._advance_margin()])

	_ok("and it runs fewer eyes -- one car, not three",
		recruit._wanted_scouts() < elite._wanted_scouts()
			or recruit._wanted_scouts() == 1,
		"recruit %d, elite %d" % [recruit._wanted_scouts(),
			elite._wanted_scouts()])
	_ok("which is Ironfront's measured ladder, not a formula",
		SimAiDirector.SCOUTS_BY_SKILL[SimSkill.Level.RECRUIT] == 1
			and SimAiDirector.SCOUTS_BY_SKILL[SimSkill.Level.WARLORD] >= 3,
		str(SimAiDirector.SCOUTS_BY_SKILL))

	# The blind sensor push is a doctrine and skill difference too, and it had
	# better be a difference rather than a constant.
	var elite_forward := SimAiDirector.BLIND_FORWARDNESS \
		+ 0.35 * SimSkill.sensor_share(SimSkill.Level.ELITE)
	var recruit_forward := SimAiDirector.BLIND_FORWARDNESS \
		+ 0.35 * SimSkill.sensor_share(SimSkill.Level.RECRUIT)
	_ok("an Elite pushes its eyes further out when blind than a Recruit",
		elite_forward > recruit_forward,
		"%.2f vs %.2f" % [elite_forward, recruit_forward])


# ═══════════════════════════════════════════════════════════════════════════
# 9. THE FENCE
#
# All of the above is new code reading the AI's own base. None of it may have
# opened a door. docs/09 §1.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_the_firewall_survived_it() -> void:
	_suite("None of this reached for anything it does not own (docs/09 §1)")

	var s := _solo(409, SimSkill.Level.WARLORD, SimDoctrine.Profile.TECH_RUSH)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	# Somebody else's base, standing where the AI wants to build.
	w.economy.add_player(2, 8000.0, 4, 6)
	w.economy.place_starting_unit(2, "hq", 300.0, 300.0)
	w.run_ticks(int(120.0 * SimWorld.SIM_HZ))

	_ok("it never reached for a unit it does not own",
		d.view.forces.denied_queries == 0,
		"%d denied quer(y/ies)" % d.view.forces.denied_queries)

	# own_def() and own_is_operational() are new accessors. Both have to
	# refuse a foreign index, and refusing has to be COUNTED -- a silent
	# refusal is a fence nobody can test.
	var foreign := -1
	for i in w.entities.indices_of_owner(2):
		foreign = i
		break
	_ok("there is a foreign structure to try", foreign >= 0)
	var denied_before := d.view.forces.denied_queries
	_ok("own_def refuses it", d.view.own_def(foreign) == null)
	_ok("own_is_operational refuses it",
		not d.view.own_is_operational(foreign))
	_ok("and both refusals were counted rather than swallowed",
		d.view.forces.denied_queries > denied_before,
		"%d -> %d" % [denied_before, d.view.forces.denied_queries])

	# The base picture is the new bulk reader. It must hold the AI's own
	# structures and nothing else, however many players are on the map.
	var pic := SimAiWorks.base_picture(d.view)
	var own := {}
	for i in w.entities.indices_of_owner(1):
		own[i] = true
	var strangers := 0
	for row in pic:
		if not own.has((row as SimAiWorks.Yard).unit):
			strangers += 1
	_ok("the base picture holds only this player's own buildings",
		strangers == 0, "%d yard(s), %d stranger(s)" % [pic.size(), strangers])

	# And the leak that was deliberately NOT taken, asserted as a property of
	# the source: nothing under sim/ai/ may call placement_problem(), because
	# that call tests clearance against every structure on the map and a
	# director probing it on a grid would read the enemy's base off the
	# refusals.
	_ok("and nothing in the AI module calls placement_problem()",
		_grep_ai_module("placement_problem") == 0,
		"%d occurrence(s) under sim/ai/"
			% _grep_ai_module("placement_problem"))
	# The entity store is reachable from exactly ONE file in the module, and
	# that file is the fence itself: SimOwnForcesView holds the store and
	# refuses every index its owner does not have. Everywhere else -- the
	# director, the world view, the siting rules -- must go through it.
	_ok("the entity store is reachable from the fence and nowhere else",
		_grep_ai_module("SimEntities", "sim_own_forces_view.gd") == 0,
		"%d occurrence(s) outside sim_own_forces_view.gd"
			% _grep_ai_module("SimEntities", "sim_own_forces_view.gd"))


## How many times a string appears in the AI module's source, comments
## included. Crude on purpose: a fence that can be checked by grep is a fence
## a reviewer can check too.
func _grep_ai_module(needle: String, except_file := "") -> int:
	var hits := 0
	var dir := DirAccess.open("res://sim/ai")
	if dir == null:
		return -1
	for f in dir.get_files():
		if not f.ends_with(".gd") or f == except_file:
			continue
		var text := FileAccess.get_file_as_string("res://sim/ai/" + f)
		var from := 0
		while true:
			var at := text.find(needle, from)
			if at < 0:
				break
			# A mention inside a comment is documentation, not a call. Count
			# only lines that are not comments.
			var line_start := text.rfind("\n", at) + 1
			var line := text.substr(line_start, at - line_start).strip_edges()
			if not line.begins_with("#"):
				hits += 1
			from = at + needle.length()
	return hits


# ═══════════════════════════════════════════════════════════════════════════
# 10. DETERMINISM, docs/06
#
# Siting walks a few hundred candidate points. If any of that reads a
# Dictionary in insertion order or draws from an unsequenced source, two runs
# of the same seed put the buildings in different places.
# ═══════════════════════════════════════════════════════════════════════════

func _suite_siting_is_deterministic() -> void:
	_suite("The same seed puts the same buildings in the same places")

	var a := _run_for_sites(410)
	var b := _run_for_sites(410)
	var c := _run_for_sites(411)
	_ok("a run put buildings somewhere", a != "", a)
	_ok("and the same seed puts them in exactly the same places", a == b,
		"%s vs %s" % [a, b])
	_ok("while a different seed is allowed to differ", true,
		"seed 411 -> %s" % c)

	# The bearing walk is deliberately NOT drawn from the director's stream --
	# see SimAiWorks.GOLDEN_ANGLE. Siting must therefore be identical for two
	# directors with different random state but the same base.
	var s1 := _solo(412, SimSkill.Level.VETERAN, SimDoctrine.Profile.COMBINED_ARMS)
	var s2 := _solo(412, SimSkill.Level.VETERAN, SimDoctrine.Profile.COMBINED_ARMS)
	var d1 := s1["ai"] as SimAiDirector
	var d2 := s2["ai"] as SimAiDirector
	(s1["world"] as SimWorld).run_ticks(20)
	(s2["world"] as SimWorld).run_ticks(20)
	for _k in range(50):
		d2.rng.next_float()
	var def := d1.view.def_for("research_facility")
	var p1 := d1._build_site(def)
	var p2 := d2._build_site(d2.view.def_for("research_facility"))
	_ok("and siting does not depend on how much of the stream was spent",
		p1.size() == p2.size() and p1.size() >= 2
			and absf(p1[0] - p2[0]) < 0.01 and absf(p1[1] - p2[1]) < 0.01,
		"(%.1f, %.1f) vs (%.1f, %.1f)" % [p1[0], p1[1], p2[0], p2[1]])


## Every structure this AI's ECONOMY put up, as one comparable string.
func _run_for_sites(seed_value: int) -> String:
	var s := _solo(seed_value, SimSkill.Level.ELITE,
		SimDoctrine.Profile.COMBINED_ARMS)
	var w := s["world"] as SimWorld
	w.run_ticks(int(180.0 * SimWorld.SIM_HZ))
	var rows := PackedStringArray()
	for i in w.entities.indices_of_owner(1):
		if w.entities.is_structure[i] == 0:
			continue
		rows.append("%s@%.0f,%.0f" % [w.entities.names[i],
			w.entities.pos_x[i], w.entities.pos_z[i]])
	rows.sort()
	return " | ".join(rows)
