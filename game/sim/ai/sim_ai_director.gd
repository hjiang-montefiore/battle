class_name SimAiDirector
extends RefCounted
## One AI opponent. docs/09 §3: three layers at three rates.
##
## Look at what _init() takes: a SimAiWorldView and nothing else. There is no
## overload that accepts a SimEntities, a SimWorld, or another faction's track
## table, and adding one would be the bug docs/09 §1.1 says makes every pillar
## in the design decorative. If a future behaviour seems to need ground truth,
## the answer is that it needs a better sensor, not a wider constructor.
##
## OWNERSHIP: writes NOTHING in the entity store. Its only output is commands.
##
## ── HOW THE NO-CHEATING RULE IS ENFORCED HERE, in four layers ──────────────
##
##  1. THE CONSTRUCTOR. One argument, a SimAiWorldView. That bundle holds a
##     SimOwnForcesView (own units, every accessor refusing a foreign index and
##     counting the refusal), its own faction's SimTrackTable, the public
##     terrain, its own purse and the shared command queue. There is no field
##     on it that reaches SimEntities and no method that returns one.
##
##  2. THE TRACK IS THE ONLY ENEMY INPUT, and a track id is opaque. Nothing in
##     this file resolves a track to anything; it cannot, because
##     SimTrack._truth_index is written by fusion and never read here. Every
##     enemy fact this AI uses -- position, velocity, class, whether it is
##     radiating -- is copied off a track, which may be stale, degraded, or
##     about a chaff bloom.
##
##  3. THE OUTPUT IS COMMANDS. Orders leave through the same SimCommandQueue
##     the human's mouse uses and are ownership-checked in
##     SimWorld._command_slot(). An AI cannot move somebody else's army even if
##     it names the index, and ATTACK carries a track id rather than a target.
##
##  4. A SOURCE SCAN IN THE TESTS. GDScript has no private members, so
##     test_ai.gd greps every file in sim/ai/ for the identifiers that would be
##     a leak -- SimEntities, SimWorld, solver, table_for, _truth_index -- and
##     fails if any appears outside the one file that IS the fence. That is the
##     closest thing to "impossible to write" the language allows, and it fails
##     the build rather than a code review.
##
## Additionally test_ai.gd runs the docs/09 §1.5 checks: a blind AI's entire
## command stream is byte-identical whether or not an enemy army exists, its
## objectives follow a deliberately offset track table rather than the truth
## behind it, and it will spend orders on a ghost track backed by no entity.

## docs/09 §3 rates, mirroring the docs/06 tick budget.
const STRATEGIC_HZ := 0.3   ## economy, epoch advancement, production mix
const OPERATIONAL_HZ := 1.5 ## where to attack, sensor placement, EMCON posture
const TACTICAL_HZ := 6.0    ## target selection, weapon matching, evasion

## The overall stance the operational layer works within.
enum Posture {
	HOLD,      ## sit on the objective. A Fortress lives here
	DEFEND,    ## cover the base, engage what comes
	PROBE,     ## advance to standoff, do not close
	ATTACK,    ## commit
	WITHDRAW,  ## losing -- break contact and reconstitute
}

const POSTURE_NAMES := {
	Posture.HOLD: "hold", Posture.DEFEND: "defend", Posture.PROBE: "probe",
	Posture.ATTACK: "attack", Posture.WITHDRAW: "withdraw",
}

# ── tuning. Every number here is a posture, not an information advantage. ────
const FORMATION_SPACING_M := 90.0
const FORMATION_WIDTH := 5
## Re-issuing a move every operational tick would flood the queue and thrash
## the path planner, so an order is repeated only when the goal really moved.
const REORDER_MOVE_M := 250.0
const REORDER_REFRESH_S := 30.0
const REENGAGE_PERIOD_S := 3.0
## Contacts considered per tactical tick. The picture is ranked once and cut,
## so cost is bounded by the AI rather than by how noisy the battlefield is.
const RANKED_LIMIT := 24
## Fraction of its own weapon reach a group closes to when probing.
const STANDOFF_FRACTION := 0.75
## A standoff may never eat more than this share of the distance a group still
## has to cover, so "hold at gun range" can never become "drive backwards".
## See _manoeuvre() for the measurement that made this constant necessary.
const STANDOFF_MAX_SHARE := 0.5
## Structure fraction below which a unit breaks contact.
const BASE_WITHDRAW_HP := 0.40
## Group strength ratio below which the whole group pulls back.
const BASE_GROUP_BREAK := 0.55

## How much ground one of the AI's own units is credited with having COVERED by
## driving through it. Deliberately small -- a vehicle that drove past a hill
## has not searched behind it -- because an optimistic number marks the map
## swept without anybody having looked at it.
const SWEEP_RADIUS_M := 700.0

## Close enough to a search objective to call that piece of ground done and ask
## for the next one.
const SEARCH_ARRIVE_M := 500.0

## A remembered position of something that did not move. A structure does not
## drive away, so where one was seen stays worth attacking long after the track
## has decayed -- this is the AI knowing where it scouted the enemy base.
const SITE_MERGE_M := 500.0
const SITE_STATIC_SPEED_MS := 1.5
const SITE_CONFIRM_S := 12.0
const MAX_SITES := 12
## A site the army has stood on and found nothing at is gone.
const SITE_CLEAR_M := 650.0

var view: SimAiWorldView
var rng: SimRng
var skill: int = SimSkill.Level.VETERAN
var doctrine: SimDoctrine = null

var _strategic_accum: float = 0.0
var _operational_accum: float = 0.0
var _tactical_accum: float = 0.0

## Decisions taken, for the debug view docs/09 §1.6 asks to be built early:
## "Render the AI's track table beside ground truth and you can SEE what it
## believes. Most AI bugs become visually obvious."
var decision_log: Array = []
var max_log: int = 120

# ── the AI's own state. None of it is ground truth. ─────────────────────────
## Elapsed simulation seconds, accumulated from step(dt). NEVER Time.get_ticks_*
## -- docs/06 forbids wall-clock anywhere in the sim.
var elapsed_s: float = 0.0
var memory: SimAiMemory = SimAiMemory.new()
var groups: Array = []
var posture: int = Posture.DEFEND

## Where this AI considers home: the centroid of its own structures, or of its
## own army when it has none. Own information by definition.
var home_x: float = 0.0
var home_z: float = 0.0
var has_home: bool = false

## Counters the debug view and the tests read.
var orders_moved: int = 0
var orders_attacked: int = 0
var orders_emcon: int = 0
var orders_production: int = 0
var epoch_advances_requested: int = 0

## SimAiRoles.Unit -> Array[SimWeaponDef]. Overridable, see set_loadout().
var loadouts: Dictionary = {}

var _next_group_id: int = 1
var _role_cache: Dictionary = {}
var _last_move: Dictionary = {}       ## unit -> [x, z, time]
var _assigned: Dictionary = {}        ## unit -> [track_id, time]
## The coverage map: which ground this AI has already looked at, and when.
var search: SimAiSearch = SimAiSearch.new()
## Per-unit destinations for units that search ALONE rather than in formation.
## Two scouts in one formation cover one scout's worth of ground.
var _solo_obj: Dictionary = {}
## group id -> search cell it is currently sweeping, so a group finishes a
## piece of ground instead of re-choosing every 0.67 s.
var _group_cell: Dictionary = {}
## Places something was seen that did not move: [x, z, last_seen_s]. Not a
## track and not a belief -- a remembered map location, which is why it
## outlives the memory horizon. Structures do not drive away.
var _sites: Array = []
## When the current ATTACK was entered. Commitment has to be sticky or an army
## turns for home the moment a track decays.
var _attack_since_s: float = -1.0e9
## Seconds spent in PROBE while actually holding something worth attacking.
## When this runs out the AI attacks anyway -- see _choose_posture().
var _pressure_s: float = 0.0
var _peak_live_tracks: int = 0
var _prev_own_total: int = -1
var _prev_sensor_count: int = -1
var _losses_since_strategic: int = 0
var _sensor_losses_since_strategic: int = 0
var _datalink_up: bool = true
var _last_build_s: float = -1.0e9

## ── THE GROWTH BUDGET (see the block above _measure_income) ──────────────
## Credits accrued for growth and not yet spent on it.
var _growth_budget: float = 0.0
## Measured income, credits a second, over a 45 s window.
var _income_ema: float = 0.0
## The bank's slope over a 20 s window -- what tells idle money from money on
## its way out of the door.
var _cash_slope: float = 0.0
var _econ_prev_credits: float = -1.0
## The purse's own cumulative earnings at the last measurement -- what income
## is actually read off. See SimAiWorldView.own_earned_total().
var _econ_prev_earned: float = 0.0
## What THIS director chose to spend since the last measurement. Kept for the
## decision log and for the refund bookkeeping; deliberately NOT part of the
## income estimate any more.
var _econ_spent: float = 0.0
## How long the bank has been idle by Ironfront's test. Non-zero bypasses the
## budget entirely.
var _idle_s: float = 0.0
## When the growth claim was first fully met, or -1. Its age is what expires.
var _claim_since_s: float = -1.0
## The single thing growth is saving for, and its price with the cushion on.
var _growth_want_key: String = ""
var _growth_want_cost: float = 0.0
var _growth_is_advance: bool = false
## What the REST of the plan costs -- the ceiling on the bucket. See _plan_cost.
var _growth_plan_cost: float = 0.0
## role -> the time it may be attempted again (Ironfront's failCool).
var _build_cool: Dictionary = {}
## role -> consecutive refused sitings (Ironfront's rq.failN).
var _build_fail: Dictionary = {}
## THE EXPANSION IN PROGRESS. `_creep_role` is the role currently being sited
## AT `_creep_x/_creep_z` rather than beside the base -- a derrick standing on
## a field, or a relay walking toward one. Empty when growth is not expanding,
## and cleared on every _choose_growth so a stale target cannot misroute the
## siting of an ordinary shed.
var _creep_role: String = ""
var _creep_x: float = 0.0
var _creep_z: float = 0.0
## Oil field index -> the time it may be attempted again. A field the engine
## refused is a field somebody else is probably pumping, and the AI is not
## allowed to ask which -- so it does what a player does: tries the next one
## and comes back later.
var _field_cool: Dictionary = {}
## Relays bought to reach money, against SimAiWorks.CREEP_MAX_RELAYS.
var relays_built: int = 0
## HAS EXPANSION HAD ITS TURN? True from the moment a derrick lands until the
## next epoch step is taken. See _choose_growth: this is the alternation that
## stops the two halves of growth starving each other.
var _expanded_since_step: bool = false

## [role, x, z] of a build order whose structure has not appeared yet.
var _pending_build: Array = []
## Which of our own structures already stood when the pending order went in.
## Without this, confirmation cannot tell a new building from an old neighbour.
var _pending_known: Dictionary = {}

## Counters, so a test can assert the thing the fault was about: the AI must
## place structures in a live match, where it used to place none.
var structures_placed: int = 0
var structures_refused: int = 0
## Units pulled out of the line. Held there with hysteresis, because a unit
## that the tactical layer withdraws and the operational layer re-commits on
## the same second is a unit that drives back and forth under fire.
var _withdrawn: Dictionary = {}


func _init(world_view: SimAiWorldView, seeded: SimRng) -> void:
	view = world_view
	rng = seeded if seeded != null else SimRng.new(1)
	if view != null and view.setup != null:
		skill = view.setup.skill
		doctrine = view.setup.doctrine
	if doctrine == null:
		# A director with no setup still has to be a competent opponent rather
		# than an inert one, so it gets the default posture from docs/09 §5.
		doctrine = SimDoctrine.make(SimDoctrine.Profile.COMBINED_ARMS)
	for r in SimAiRoles.Unit.values():
		loadouts[r] = SimAiRoles.default_loadout(r)


## Replace what the AI believes one of its own roles carries. Exists so that
## when units gain real weapon lists, the director reads those instead of the
## defaults in SimAiRoles -- see the note there.
func set_loadout(role: int, weapons: Array) -> void:
	loadouts[role] = weapons


# ═══════════════════════════════════════════════════════════════════════════
# THE API
# ═══════════════════════════════════════════════════════════════════════════

## The tick slot. Called every simulation tick; this class does its own rate
## division into the three layers, because docs/09 §3 gives them three different
## rates and SimWorld should not have to know about that.
##
## The layers run TOP DOWN inside a tick -- strategic, then operational, then
## tactical -- so a posture decided this tick is the one the shooters act
## under. It costs nothing: each layer still fires at its own rate.
func step(dt: float) -> void:
	elapsed_s += dt
	_strategic_accum += dt
	_operational_accum += dt
	_tactical_accum += dt
	if _strategic_accum >= 1.0 / STRATEGIC_HZ:
		strategic_tick(_strategic_accum)
		_strategic_accum = 0.0
	if _operational_accum >= 1.0 / OPERATIONAL_HZ:
		operational_tick(_operational_accum)
		_operational_accum = 0.0
	if _tactical_accum >= 1.0 / TACTICAL_HZ:
		tactical_tick(_tactical_accum)
		_tactical_accum = 0.0


## docs/09 §3: economy, epoch advancement, production mix, theatre priorities.
## Also the adaptation band -- a doctrine sets a posture, not a script, and
## "a profile that never adapts is exploitable in one match and boring in the
## second."
func strategic_tick(dt: float) -> void:
	if view == null or view.forces == null:
		return
	_update_home()
	_adapt()
	_economy(dt)


## Where to attack, force composition, sensor and AEW placement, EMCON posture,
## supply routing.
func operational_tick(dt: float) -> void:
	if view == null or view.forces == null:
		return
	_ensure_search()
	_observe()
	_record_sweep(dt)
	_update_groups()
	_choose_posture(dt)
	_assign_objectives()
	_manage_emcon()
	_manoeuvre()


## Target selection, weapon-guidance matching, evasive response to threat
## warnings. Runs the SAME SimWeaponGate the player does -- docs/09 §3:
## "It is not an approximation of the player's rules; it is those rules."
func tactical_tick(dt: float) -> void:
	if view == null or view.forces == null or view.tracks == null:
		return
	_observe()
	_break_contact_if_hurt()
	_engage()


## docs/09 §3 threat table: what the AI does is a function of what KIND of
## knowledge it holds. Returns a priority score for one track, higher = more
## urgent. Weights TQ3 on a high-value emitter above a TQ1 bearing, and weights
## by doctrine.target_priority -- an Interdiction AI hunts tankers, AEW and
## supply trucks instead of the army.
##
## Everything read here is on the track. There is no lookup of what the track
## really is, because there is nothing to look it up in.
func threat_score(track: SimTrack) -> float:
	if track == null or track.quality <= SimTypes.TrackQuality.NONE:
		return 0.0

	# 1. WHAT KIND OF KNOWLEDGE. A bearing is a cue; a fire-control track is a
	#    decision. This term is the docs/09 §3 table in one line.
	var base := 0.0
	match track.quality:
		SimTypes.TrackQuality.CONTACT: base = 0.35
		SimTypes.TrackQuality.TRACK: base = 1.00
		SimTypes.TrackQuality.FIRE_CONTROL: base = 1.60
		SimTypes.TrackQuality.TERMINAL: base = 1.80
	var score: float = base * (0.55 + 0.45 * clampf(track.confidence, 0.0, 1.0))

	# 2. A STALE TRACK IS WORTH LESS. "A track decaying from TQ3: predict along
	#    last known velocity, or re-acquire -- do not fire blind."
	score *= 1.0 / (1.0 + maxf(0.0, track.age_s) / 25.0)

	# 3. ARMIES OR ENABLERS. docs/09 §5 target_priority, 0 = armies, 1 = the
	#    things the army runs on.
	var enabler := _enabler_likelihood(track)
	var tp: float = clampf(doctrine.target_priority, 0.0, 1.0)
	score *= (1.0 - tp) * (1.40 - 0.70 * enabler) + tp * (0.60 + 1.60 * enabler)

	# 4. AN EMITTER IS A GIFT, and knowing that is a skill (docs/09 §2
	#    counter-EW: "changes bands, exploits home-on-jam").
	if track.emitting:
		score *= 1.0 + 0.5 * SimSkill.counter_ew(skill)

	# 5. PROXIMITY TO HOME. Something close is a threat to me whatever it is.
	if has_home and not track.bearing_only:
		var d := sqrt(pow(track.pos_x - home_x, 2.0) + pow(track.pos_z - home_z, 2.0))
		score *= 1.0 + 0.8 * clampf(1.0 - d / _threat_radius_m(), 0.0, 1.0)

	# 6. Knowing WHAT it is makes it easier to plan against.
	score *= 1.0 + 0.10 * float(track.classification)

	# 7. A bearing-only contact is something to look at, not something to
	#    commit an army to.
	if track.bearing_only:
		score *= 0.5
	return score


func log_decision(line: String) -> void:
	decision_log.append("%7.1fs  %s" % [elapsed_s, line])
	if decision_log.size() > max_log:
		decision_log.pop_front()


## True once this class actually decides anything.
func is_implemented() -> bool:
	return true


# ═══════════════════════════════════════════════════════════════════════════
# STRATEGIC
# ═══════════════════════════════════════════════════════════════════════════

## Home is where this AI's own structures are, or where its army is if it has
## none. Recomputed rather than stored at setup so a base that is overrun moves
## the rally point with it.
func _update_home() -> void:
	var idx := view.forces.indices()
	if idx.is_empty():
		return
	var sx := 0.0
	var sz := 0.0
	var n := 0
	for i in idx:
		if not view.forces.is_structure(i):
			continue
		var p := view.forces.position(i)
		sx += p[0]; sz += p[2]; n += 1
	if n == 0:
		for i in idx:
			var p := view.forces.position(i)
			sx += p[0]; sz += p[2]; n += 1
	if n == 0:
		return
	home_x = sx / float(n)
	home_z = sz / float(n)
	has_home = true


## docs/09 §5 adaptation. Every signal below is measured on the AI's OWN state:
## how many contacts it holds, how many of its own units died, how much fuel it
## has left, what epoch it is at. None of it requires looking at the enemy.
func _adapt() -> void:
	var idx := view.forces.indices()
	var total := idx.size()
	var sensors := 0
	var fuel_sum := 0.0
	var fuel_n := 0
	for i in idx:
		var role := _role_of(i)
		if SimAiRoles.is_sensor_platform(role):
			sensors += 1
		if not view.forces.is_structure(i) and view.forces.max_speed_ms(i) > 0.0:
			fuel_sum += view.forces.fuel_fraction(i)
			fuel_n += 1

	if _prev_own_total >= 0:
		_losses_since_strategic = maxi(0, _prev_own_total - total)
	if _prev_sensor_count >= 0:
		_sensor_losses_since_strategic = maxi(0, _prev_sensor_count - sensors)
	_prev_own_total = total
	_prev_sensor_count = sensors

	var live := memory.live_count()
	_peak_live_tracks = maxi(_peak_live_tracks, live)

	# Losing the sensor contest looks like this from the inside: my picture has
	# collapsed, or I am taking losses while holding nothing at all. Notice that
	# neither test asks whether the enemy is jamming -- the AI infers it, which
	# is what a real commander does.
	var losing_sensor_contest := (_peak_live_tracks >= 3 and live * 3 < _peak_live_tracks) \
		or (live == 0 and _losses_since_strategic > 0)
	var ceiling: int = view.setup.ceiling_epoch if view.setup != null else 7
	var epoch := view.epoch()
	var at_ceiling := epoch >= ceiling
	var advance_cost: float = view.epoch_advance_cost()
	if advance_cost <= 0.0:
		advance_cost = SimAiPlan.TECH_RESERVE
	var behind_on_epoch := not at_ceiling and view.credits() >= advance_cost
	var fuel_starved := fuel_n > 0 and (fuel_sum / float(fuel_n)) < 0.30
	var own_aew_dying := _sensor_losses_since_strategic > 0

	doctrine.adapt(losing_sensor_contest, behind_on_epoch, at_ceiling,
		fuel_starved, own_aew_dying)

	if losing_sensor_contest:
		log_decision("losing the sensor contest -- %d track(s), peak %d"
			% [live, _peak_live_tracks])
	if fuel_starved:
		log_decision("fuel starved -- pulling in")


## Build, expand, produce. docs/09 §5 drives the mix; SimAiPlan turns the
## weights into the one thing the AI is most short of, and the economy answers
## what this player can actually afford to make of it.
##
## Every question asked here is asked about THIS player -- own credits, own
## epoch, own build menu, own factories. docs/09 §1.2 lists the other player's
## income, queue and stockpile as leaks, and none of them is reachable.
func _economy(dt: float) -> void:
	if not view.has_purse():
		return

	# THE ORDER OF THESE FIVE STEPS MATTERS.
	#
	# The confirmation comes first because it is what stands a role down after
	# a refused siting, and step 3 walks the build order looking for a role
	# that is NOT stood down. Confirming after that would spend a whole
	# strategic tick re-choosing the spot that was just refused.
	_confirm_pending_build()
	_measure_income(dt)

	# 2. THE FORCE MIX, counted off its own army; and the BASE, counted by
	#    ROLE rather than by name. By name was a latent bug of its own: a
	#    def's `name` is the name at the CURRENT epoch, so an AI that had
	#    advanced could stop recognising a building it had itself built.
	var counts := {"sensors": 0, "air_defence": 0, "supply": 0, "line": 0}
	var factories := PackedInt32Array()
	var own_roles := {}
	var harvesters := 0
	var scouts := 0
	var refineries := 0
	for i in view.forces.indices():
		var role := _role_of(i)
		if view.forces.is_structure(i):
			var sd := view.own_def(i)
			if sd != null:
				own_roles[sd.role] = int(own_roles.get(sd.role, 0)) + 1
			if role == SimAiRoles.Unit.PRODUCTION:
				factories.append(i)
			if sd != null and sd.refine_capacity > 0.0:
				refineries += 1
			continue
		if SimAiRoles.is_economic(role):
			harvesters += 1
			continue
		if role == SimAiRoles.Unit.SCOUT:
			scouts += 1
		var bucket := SimAiPlan.bucket_of(role)
		if bucket != "":
			counts[bucket] = int(counts[bucket]) + 1
	counts["economy"] = harvesters
	counts["recon"] = scouts

	# 3. WHAT GROWTH IS SAVING FOR, priced before a credit is spent, because
	#    the reserve in step 5 is a claim on exactly this and nothing else.
	var credits := view.credits()
	_choose_growth(own_roles)
	_fill_budget(dt, credits)

	# 4. TECHING UP, or THE BASE -- whichever growth chose. One at a time on
	#    purpose: two claims on one purse is how Ironfront starved its own
	#    services ("Two services racing for one reserve did exactly that",
	#    js/ai.js:1096), and it is also why the AI used to build nothing.
	if _growth_is_advance:
		_advance_epoch(credits)
	else:
		_build_out(credits, own_roles)
	credits = view.credits()

	# 5. PRODUCTION, at every factory that has a free slot -- spending only
	#    what growth has not claimed. THIS IS THE SECOND DOCUMENTED FAULT:
	#    _economy() used to hand the whole balance to the production loop
	#    every 3.3 s, so credits never rose above ~130 and nothing expensive
	#    was ever affordable. Ironfront's note is the same lesson from the
	#    other direction: "let money above the reserve be spent freely, so an
	#    army is never starved, it simply waits" (js/ai.js:1036).
	var reserve := _growth_reserve()
	var spendable := maxf(0.0, credits - reserve)
	for f in factories:
		var options := view.production_options(f)
		if options.is_empty():
			continue
		var key := SimAiPlan.choose_production(view, doctrine, skill, options,
			counts, spendable, _wanted_harvesters(refineries), _wanted_scouts())
		if key == "":
			continue
		var d := view.def_for(key)
		if d == null or d.cost > spendable:
			continue
		view.order_produce(f, key)
		orders_production += 1
		spendable -= d.cost
		_econ_spent += d.cost
		counts[SimAiPlan.bucket_of_def(d)] = \
			int(counts.get(SimAiPlan.bucket_of_def(d), 0)) + 1
		log_decision("producing %s at %d (%.0f cr, %.0f held for %s)"
			% [key, f, d.cost, reserve, _growth_want_key])


# ═══════════════════════════════════════════════════════════════════════════
# THE GROWTH BUDGET
#
# THE FAULT: the AI kept no reserve. It spent every credit on production
# every strategic tick, so it never held more than about 130 credits and a
# 1,500-credit research facility was permanently out of reach.
#
# THE SHAPE OF THE FIX is Ironfront's econTick (js/ai.js:5830) and the long
# note above it, which is a record of four failed attempts at the same
# problem. The lesson it settles on:
#
#   "So the build order is a PLAN rather than a ladder of bank balances.
#    A BUDGET, not the bank, pays for growth ... a bank-balance gate either
#    never opens or, once open, lets the works queue starve the army. Growth
#    draws on a bucket filled at 55% of income (40% below Veteran); the rest
#    is the army's."
#
# So: income is MEASURED rather than assumed, a share of it accrues into a
# growth bucket, and the army may spend everything the bucket has not
# claimed. Four numbers come straight across -- the 55/40% share, the 45 s
# income window, the 20 s slope window, and the 9,000 ceiling -- and so do
# the two clamps that Ironfront's own probes forced on it: never owe growth
# more than the bank plus 2,500, and never less than the next item plus 500.
# ═══════════════════════════════════════════════════════════════════════════

## econTick's `Math.min(1, dt / 45)`: income is what LANDED, averaged over
## forty-five seconds, because a single haul is not an income.
const INCOME_TAU_S := 45.0
## econTick's `Math.min(1, dt / 20)` on the bank's slope, which is what tells
## idle money from money on its way out.
const SLOPE_TAU_S := 20.0
## THE CEILING ON WHAT GROWTH MAY BE OWED, and the second place Ironfront's
## number does not transfer. econTick clamps with `Math.min(9000, ...)`, which
## is generous against its prices and miserly against ours: the epoch step
## alone is 6,100 credits at epoch 4 and the rest of a base is another ten
## thousand, so a 9,000 ceiling means growth can hold the step OR the base and
## never both. Measured, a commander handed 40,000 credits banked 9,000 of it,
## let its production line spend the other 31,000 on tanks inside two
## strategic ticks, and then could not pay for the epoch step it had built the
## research facility for.
##
## So the ceiling is THE PLAN rather than a constant: the next few rungs of
## this doctrine's build order that the base is actually short of, plus the
## epoch step when one is available. It is bounded by construction -- there
## are only so many rungs -- and GROWTH_ABSOLUTE_CAP is a backstop against a
## roster change making one of them absurd, not a working limit.
const GROWTH_PLAN_DEPTH := 4
const GROWTH_ABSOLUTE_CAP := 20000.0
## `Math.max(rigCost() + 500, ...)` -- never less than the next item and a
## margin, or an expensive step can never be paid for by a commander that
## spends as it earns.
const GROWTH_ITEM_MARGIN := 500.0
## `... P.cash + 2500)` -- never more owed than the bank plus this, so a purse
## spent on the army does not leave a claim on the next ten thousand.
const GROWTH_AHEAD := 2500.0
## `(D.econ || 1) >= 1 ? 0.55 : 0.4`. Ironfront's econ multiplier reaches 1.0
## at Veteran, so that is where the split sits here too -- and it is a real
## part of the difficulty ladder: a Recruit's growth is slower AND its army
## is smaller for it.
const GROWTH_SHARE_HIGH := 0.55
const GROWTH_SHARE_LOW := 0.40
## `Math.max(2500, P.storageCap() * 0.35)` and `runway > 90`: money this large
## that would take this long to run down at the rate it is falling is IDLE,
## and idle money bypasses the budget entirely.
const IDLE_FLOOR_CR := 2500.0
const IDLE_RUNWAY_S := 90.0

## THE OPENING FLOAT, and the biggest single departure from the reference.
##
## econTick seeds its bucket with `500 + Math.max(0, P.cash - 5000) * 0.35`,
## and the note beside it says why: "a Heavy purse is growth money from the
## first minute; a Light one is spent on the opening alone."
##
## Measured, that number does not transfer, and the reason is worth writing
## down because it decides whether the AI can build at all. A peer start here
## hands each player 8,000 credits against a NET income of about 5.3 credits a
## second -- 520 a minute gross from two derricks and a refinery, less about
## 200 a minute of upkeep. At epoch 4 a power plant costs 1,260, an ore
## refinery 2,520, a research facility 2,700 and the epoch step itself 6,100.
## So the opening float is not seed money on top of an income the way it is in
## Ironfront: IT IS ESSENTIALLY THE WHOLE GROWTH BUDGET OF THE MATCH. Applying
## 0.35 above 5,000 would reserve 1,550 -- one power plant, and nothing else
## ever.
##
## So the split is inverted: the ARMY gets an opening float and growth gets a
## share of the rest. 2,500 for the army is Ironfront's own GROWTH_AHEAD
## figure reused from the other side of the same trade, and the share is the
## same 55/40 skill split as the income share -- which makes it part of the
## difficulty ladder rather than a constant: an Elite opens with its power
## plant AND its refinery, a Recruit with the power plant alone.
const GROWTH_SEED_FLOOR := 500.0
const ARMY_OPENING_FLOAT := 2500.0

## An epoch step's margin is SECONDS OF INCOME, not a multiple of the price.
## Ironfront's own clamp is additive for the same reason -- `rigCost() + 500`,
## never `rigCost() * 1.4` -- and at our prices a multiplier is the difference
## between climbing and never climbing: 1.8 x 6,100 is 11,000 credits, which
## this economy does not see in a match. Thirty seconds of production money
## plus the commander's nerve is the real question, and it scales with the
## economy instead of with the sticker price.
const ADVANCE_MARGIN_BASE_S := 30.0
const ADVANCE_MARGIN_NERVE_S := 90.0
const ADVANCE_MARGIN_GRIP_S := 90.0

## Ironfront sizes industry to measured income: "at Warlord one more war
## factory for every 38 cr/s past the first 40". Ours is the same rule with
## our own first-line figure, and it is what lets the AI ever own a SECOND
## refinery or factory -- the old build order could only ever own one of each,
## because it tested presence rather than count.
## SCALED TO OUR ECONOMY, which the first version of this constant was not.
## Ironfront's 40 and 38 are right THERE, where a factory drains ~70 cr/s and
## its AI tests inc > 150. Ours earns about 9 cr/s at its peak, so a 40 cr/s
## first line is 4.6x anything the AI will ever see and silently disabled the
## entire rule it was added for -- _wanted_count() returned 1 for refinery,
## factory and barracks alike, for the whole match. Divided by the ratio of the
## two economies rather than guessed: ~9 against ~150 is a sixteenth.
const INDUSTRY_FIRST_CR_S := 2.5
const INDUSTRY_PER_CR_S := 2.4

## How much headroom the AI insists on before it buys another power plant.
## Not from Ironfront -- this one is ours, and it is a measured fault: the
## opening base draws 110 and supplies 100, so every AI in the game has been
## playing the whole match in a brownout it could see in its own sidebar and
## never acted on.
const POWER_MARGIN := 1.15

## Seconds between two build orders. Unchanged: "an AI that queues its whole
## build order in one frame is an AI with no build order."
const BUILD_PERIOD_S := 8.0

## How near the ordered spot a new structure has to appear before the AI
## believes its own order landed. Generous, because the engine places on the
## point it was given.
const BUILD_CONFIRM_M := 80.0


# ═══════════════════════════════════════════════════════════════════════════
# EXPANSION: reaching the money
#
# THE MEASUREMENT. The AI's epoch was 4 at the first tick and 4 at the last,
# on every arena, in every match. Not because it would not climb -- it wants
# to, and _choose_growth has wanted to since the research facility moved up
# the build order -- but because it could not AFFORD to. Its income was the
# 520 credits a minute its two starting derricks pump, for the whole match,
# because it never built a third derrick, because every oil field on
# skirmish_valley is ~500 m or ~1,400 m from a base and the entire build
# envelope of a start is the headquarters' 340 m ring.
#
# THE ECONOMY IS A PAIR OF TAPS, and this is the part the AI was blind to.
# SimEconomy pays out min(extraction, refine) -- crude pumped, capped by crude
# the refineries can process. A start pumps 480 a minute against 520 of
# refining, so there is 40 a minute of spare pipe and no more: a third derrick
# on its own is worth 40 credits a minute, and a second refinery on its own is
# worth nothing at all. They are only worth buying IN THE RIGHT ORDER, and the
# AI could not see the order because it sized its refineries off its income,
# which is the OUTPUT of the pair.
#
# So expansion here is one rule with two halves: buy a derrick while there is
# spare refining, buy refining while there is spare crude, and when the next
# field is out of reach, walk to it -- SimAiWorks.creep, a chain of relays
# from the rim. The human player has had that chain available the whole time.
# ═══════════════════════════════════════════════════════════════════════════

## THE RUNGS EXPANSION NEVER JUMPS -- see _econ_rung_missing, which is where
## the judgement lives. Kept as a set so the build order and this agree on the
## names, and so a roster rename breaks one place rather than two.
const ECON_FIRST := {"power_plant": true, "refinery": true}

## Crude a minute a field is worth, as the AI prices one before it walks to it.
## Read off the derrick's own card (its extraction_per_min) rather than written
## down here -- this is only the floor below which a field is not worth a walk.
const FIELD_WORTH_MIN := 1.0

## HOW LONG A WALK MAY TAKE TO PAY FOR ITSELF, in seconds.
##
## This is the number that makes expansion COMPETE rather than always win, and
## it is worth being exact about what it buys, because the first value tried
## here was 300 and it refused every field on every arena -- the AI behaved
## exactly as it had before and the probe output was byte-identical to the
## baseline, which is the most useful kind of failure.
##
## THE BILL for skirmish_valley's own field, at epoch 4: a supply depot to
## carry the ring out (1,080), the derrick (1,620), and the share of a
## refinery its crude needs to be worth anything (2,520 x 240/520 = 1,163).
## 3,863 credits. THE RETURN is the derrick's whole 240 a minute, 4 credits a
## second. It pays for itself in 966 seconds, and the second well on the same
## chain -- the relay is already standing -- in 696.
##
## So 300 s was not a strict criterion, it was an impossible one: nothing in
## this economy returns 3,863 credits in five minutes. 1,200 s admits the two
## fields a player can call its own and refuses everything else on cost, and
## it is honest about what it is -- a judgement that a well which has paid for
## itself by the twentieth minute was worth buying, against an army that would
## have had two more tanks in the eighth. It is a balance dial and it is meant
## to be turned.
##
## What it does NOT do is police the contested ring at 1,400 m. That is
## refused by SimAiWorks.CREEP_MAX_RELAYS -- seven relays' worth of walk -- and
## the cap is the right rule for it, because the objection to a seven-shed
## chain is that it dies to one raid rather than that it is expensive.
const EXPANSION_PAYBACK_S := 1200.0

## How near a field a derrick has to stand to be pumping it. SimEconomy's own
## OIL_CLAIM_M, repeated rather than imported: this is the AI's belief about
## which of ITS OWN derricks is on which field, and a belief that silently
## tracked an engine constant would be a belief nobody could test.
const OIL_CLAIM_M := 90.0

## Most refineries a base will own. Not a balance number -- a backstop, so a
## roster change that made crude cheap could not turn the AI into a refinery
## farm. The crude/refining pair is what actually decides the count.
const REFINERY_CAP := 4


## WHAT DID THE ECONOMY ACTUALLY DELIVER? Read off the purse's own cumulative
## earnings, which is the same choice Ironfront makes and for the same reason:
## "What the haulers LANDED, not what the vault credited ... stats.hauled is
## the delivery itself" (js/ai.js:5825). Its note is about a storage ceiling;
## ours is about a starting float, and the failure looked identical -- an
## estimate of "change in balance plus what I spent" read 168 credits a second
## against a true 5 while the opening 40,000 was being spent, and an industry
## sized to that put two refineries in front of the research facility.
##
## The slope is still measured off the BALANCE, because the slope's job is to
## recognise idle money, and money is only idle if it is sitting in the bank.
func _measure_income(dt: float) -> void:
	var c := view.credits()
	if _econ_prev_credits < 0.0:
		# THE SEED, once, on the first strategic tick of the match. See the
		# block above ARMY_OPENING_FLOAT: without it the AI hands its entire
		# opening float to the production line before it has thought about a
		# building, which is exactly what the measurement caught it doing --
		# 8,000 credits down to 215 in sixty seconds, and no structure ever.
		_growth_budget = maxf(GROWTH_SEED_FLOOR,
			(c - ARMY_OPENING_FLOAT) * _growth_share())
		_econ_prev_credits = c
		_econ_prev_earned = view.own_earned_total()
		_econ_spent = 0.0
		log_decision("opening float %.0f cr: %.0f to growth, %.0f to the army"
			% [c, _growth_budget, c - _growth_budget])
		return
	if dt <= 0.0:
		_econ_prev_credits = c
		_econ_prev_earned = view.own_earned_total()
		_econ_spent = 0.0
		return
	var delta := c - _econ_prev_credits
	var earned := view.own_earned_total()
	var got := maxf(0.0, (earned - _econ_prev_earned) / dt)
	_income_ema += (got - _income_ema) * minf(1.0, dt / INCOME_TAU_S)
	_cash_slope += (delta / dt - _cash_slope) * minf(1.0, dt / SLOPE_TAU_S)
	_econ_prev_credits = c
	_econ_prev_earned = earned
	_econ_spent = 0.0
	# IDLE MONEY, Ironfront's spend-down trigger. A bank this big that would
	# take this long to empty at the rate it is emptying is money doing
	# nothing, and money doing nothing is the one state a commander has no
	# excuse for.
	#
	# WHAT IDLE MONEY DOES, and it is worth being exact because getting it
	# backwards cost an afternoon. In Ironfront idle money lets GROWTH bypass
	# its own budget -- "while it idles the budget is bypassed and every
	# target grows". It does NOT hand the growth reserve to the army. Mapping
	# it to "release the reserve" looks equivalent and is not: a 40,000-credit
	# opening float is above any floor with a rising slope, so the reserve was
	# released on the first strategic tick of the match, the production line
	# spent 35,700 credits on infantry, and the epoch step the AI had just
	# built a research facility for was never affordable again.
	#
	# THE FLOOR is Ironfront's `max(2500, storageCap * 0.35)` with our own
	# second term: we have no storage ceiling, but we do have a growth plan,
	# and money above the entire remaining plan is idle by any definition.
	var floor_cr: float = maxf(IDLE_FLOOR_CR, _growth_plan_cost)
	var runway: float = (c / -_cash_slope) if _cash_slope < -1.0 else INF
	if c > floor_cr and runway > IDLE_RUNWAY_S:
		_idle_s += dt
	else:
		_idle_s = maxf(0.0, _idle_s - dt * 2.0)


## Accrue the growth bucket, and keep the claim clock. Nothing here spends.
## `(D.econ || 1) >= 1 ? 0.55 : 0.4`, and Ironfront's econ multiplier reaches
## 1.0 at Veteran -- so that is where the split sits here too.
func _growth_share() -> float:
	return GROWTH_SHARE_HIGH if skill >= SimSkill.Level.VETERAN \
		else GROWTH_SHARE_LOW


func _fill_budget(dt: float, credits: float) -> void:
	var ceiling: float = minf(GROWTH_ABSOLUTE_CAP, minf(
		maxf(_growth_want_cost, _growth_plan_cost),
		credits + GROWTH_AHEAD))
	_growth_budget = minf(ceiling,
		_growth_budget + dt * maxf(0.0, _income_ema) * _growth_share())

	# THE CLAIM, and its expiry. Ironfront: "Use it or lose it: a service
	# sitting on a met reserve for CLAIM_TTL seconds loses it" (js/ai.js:1090,
	# CLAIM_TTL = 40). A claim counts as MET only when the budget has earned
	# the price and the bank holds it -- being merely short of money is
	# waiting, not stalling, and must not expire.
	# NOT FOR AN EPOCH STEP. The claim clock exists for the one failure
	# Ironfront built it for -- a building whose spot does not exist, asked
	# for forever -- and an epoch step has no spot to fail on. Letting it
	# expire an advance claim was measured doing real damage: the clock ran
	# while the research facility was still being built, expired, and handed
	# the whole reserve to the production line.
	var met := not _growth_is_advance and _growth_want_cost > 0.0 \
		and credits >= _growth_want_cost \
		and _growth_budget >= _growth_want_cost
	if not met:
		_claim_since_s = -1.0
		return
	if _claim_since_s < 0.0:
		_claim_since_s = elapsed_s
		return
	if elapsed_s - _claim_since_s <= SimAiWorks.CLAIM_TTL_S:
		return
	# Everything was ready and nothing went up, so the want itself is the
	# problem. Release the claim AND stand the item down, or the next tick
	# simply re-latches the same claim and the army stays starved forever.
	if not _growth_is_advance and _growth_want_key != "":
		_build_cool[_growth_want_key] = elapsed_s + SimAiWorks.FAIL_COOL_S
		log_decision("released a stale claim on %s -- %.0f cr held for %.0f s"
			% [_growth_want_key, _growth_want_cost, SimAiWorks.CLAIM_TTL_S])
	_claim_since_s = -1.0


## What the army may NOT spend. Everything above it is the army's, freely.
##
## THE RESERVE IS THE WHOLE BUCKET, not the price of the next item, and that
## distinction is the difference between building and not building. Reserving
## one item's price leaves the army free to spend the rest -- so with 8,000 in
## hand and a 1,260 power plant wanted, production spent 6,740 in a single
## tick and the refinery behind it was never affordable again. Ironfront reads
## the same way when you take it at its word: "Growth draws on a bucket filled
## at 55% of income; the rest is the army's." The bucket's contents are not
## the army's, however little of it the next rung costs.
func _growth_reserve() -> float:
	if _growth_want_key == "":
		return 0.0      # nothing left to grow into: it is all the army's
	if _claim_since_s >= 0.0 \
			and elapsed_s - _claim_since_s > SimAiWorks.CLAIM_TTL_S:
		return 0.0
	# THE RESERVE IS THE BUCKET, capped only by what is actually in the bank.
	#
	# A SHARE CAP WAS TRIED HERE AND IT WAS WRONG -- worth recording, because
	# it looks like the obvious safety rail. Holding back at most 80% of the
	# balance means the army may spend a fifth of everything on every
	# strategic tick, and a strategic tick is 3.3 s: measured, a purse of
	# 40,000 credits was down to 5,287 in sixty seconds (0.8^18), the bucket
	# was clamped down with it by the `credits + 2,500` ceiling, and the epoch
	# step the AI was explicitly saving for became permanently unaffordable.
	#
	# The army is not starved by this, and the thing that stops it being
	# starved is the SHARE, not a cap: the bucket only ever fills at
	# _growth_share() of measured income, so 45% of every credit that lands is
	# the army's by construction. Ironfront says the same in one line -- "let
	# money above the reserve be spent freely, so an army is never starved, it
	# simply waits" -- and CLAIM_TTL above is what stops the waiting becoming
	# permanent.
	return minf(_growth_budget, view.credits())


## THE ONE THING GROWTH IS SAVING FOR. An epoch step or a building, never
## both at once, and priced with the cushion the commander's nerve demands.
func _choose_growth(own_roles: Dictionary) -> void:
	_growth_want_key = ""
	_growth_want_cost = 0.0
	_growth_is_advance = false
	_growth_plan_cost = 0.0
	_creep_role = ""
	if not has_home:
		return

	var next_build := _next_structure(own_roles)
	_growth_plan_cost = _plan_cost(own_roles)
	var ceiling: int = view.setup.ceiling_epoch if view.setup != null else 7

	# ═══ POWER FIRST, ALWAYS ═════════════════════════════════════════════
	# docs/12: a brownout slows work. Everything below this line is work.
	if not next_build.is_empty() and String(next_build[0]) == "power_plant":
		_growth_want_key = "power_plant"
		_growth_want_cost = float(next_build[1]) + GROWTH_ITEM_MARGIN
		return

	# ═══ THE PIPE SECOND, AND AHEAD OF THE EPOCH STEP ════════════════════
	#
	# Crude above the refining line is money on the floor: SimEconomy pays
	# min(extraction, refine), so an unrefined barrel is not deferred income,
	# it is income that never existed. Nothing else growth can buy has a
	# return that certain.
	#
	# IT IS AHEAD OF THE STEP BECAUSE IT WAS MEASURED BEHIND IT. A commander
	# with a research facility up passes _core_is_up, so the advance clause
	# below won every strategic tick from minute five onward -- and with a
	# derrick standing and only one refinery, it sat saving for epoch 5 while
	# flaring 200 credits a minute for fifteen straight minutes. It would
	# have bought the refinery out of four minutes of the money it was
	# burning.
	var pipe := _pipe_want(own_roles)
	if not pipe.is_empty():
		_growth_want_key = String(pipe[0])
		_growth_want_cost = float(pipe[1]) + GROWTH_ITEM_MARGIN
		return
	# PRESENT OR ON ITS WAY, deliberately -- a research facility takes
	# forty-five seconds to build, and what matters here is that growth stops
	# buying OTHER things the moment the enabler is paid for. Whether the
	# facility actually works yet is SimEconomy.begin_epoch_advance()'s
	# question, and it refuses cleanly without charging anything.
	#
	# Measured, requiring it to be finished was worse, not better: growth
	# went on spending during the build and put up a SAM belt, a radar
	# station and an airbase, so by the time the facility came on line the
	# 40,000-credit opening float was down to 139 credits and the 6,100
	# credit step was years of income away.
	var can_advance := view.epoch() < ceiling \
		and int(own_roles.get("research_facility", 0)) > 0
	var advance_price := 0.0
	if can_advance:
		var cost := view.epoch_advance_cost()
		if cost <= 0.0:
			cost = SimAiPlan.TECH_RESERVE
		advance_price = cost + _advance_margin()
		# IF IT IS PAID FOR, TAKE IT. This clause is ahead of expansion for one
		# reason: expansion never runs out on a map with six oil fields, so an
		# AI that always preferred the next well over the step it could already
		# afford would be the old bug wearing a new hat -- an economy that
		# grows forever and a commander that never uses it.
		if view.credits() >= advance_price:
			_growth_want_key = "epoch %d" % (view.epoch() + 1)
			_growth_want_cost = advance_price
			_growth_is_advance = true
			return

	# EXPANSION, and WHERE IT SITS IS THE WHOLE BALANCE QUESTION. It is ahead
	# of the rest of the build order -- ahead of the second factory, the SAM
	# belt, the radar -- because those are bought with income and this IS the
	# income. It is behind the two rungs in ECON_FIRST, because a derrick with
	# no refinery earns nothing and a base in a brownout builds slowly. And it
	# is behind an epoch step that is already paid for, above.
	#
	# It competes with tanks by the ordinary route: the growth bucket fills at
	# _growth_share() of income and the army spends the rest freely. A near
	# field wins that competition, a far one does not -- see
	# EXPANSION_PAYBACK_S.
	# ONE WELL PER EPOCH, and this alternation is the answer to a measured
	# failure of the version without it. Expansion outranks the build order,
	# so with four wells on the map and a relay cap of four it simply never
	# stopped: twenty-five minutes of a quiet fixture went
	# relay-derrick-refinery-relay-derrick-refinery, income climbed 520 -> 1,080
	# a minute, and the research facility -- which the AI genuinely wanted at
	# minute 13 -- was pre-empted every single strategic tick. An AI that
	# grows an economy and never spends it is the old bug with better numbers.
	#
	# So expansion takes its turn and then stands aside: from the moment a
	# derrick lands until the next epoch step is taken, growth belongs to the
	# ladder. At the ceiling epoch there is no step to wait for, so the turn
	# never ends and expansion runs freely -- which is right, because at the
	# ceiling the economy is the only thing left to improve.
	# ...and the turn ends if there is nothing for the ladder to spend on: no
	# step available and a build order with nothing left to ask for. Without
	# that clause an AI whose research facility is off its menu would stand
	# down from expansion permanently, waiting for a turn that never comes.
	var tech_has_the_turn := _expanded_since_step and view.epoch() < ceiling \
		and (can_advance or not next_build.is_empty())
	var expansion := _expansion_want(own_roles) if not tech_has_the_turn else []
	if not expansion.is_empty() and not _econ_rung_missing(own_roles, next_build):
		_growth_want_key = String(expansion[0])
		_growth_want_cost = float(expansion[1]) + GROWTH_ITEM_MARGIN
		_creep_role = String(expansion[0])
		_creep_x = float(expansion[2])
		_creep_z = float(expansion[3])
		return

	if can_advance:
		# THE EPOCH STEP WINS ONCE THE CORE IS UP. THE THIRD FAULT was that it
		# never won at all: the advance was gated on `doctrine.tech_bias >
		# 0.45`, so better than half the profiles in the game could not climb
		# a single epoch however rich they got, in a game whose entire pitch
		# is epoch progression. It is now a question of PRICE rather than of
		# permission, and the price is the cushion below.
		if next_build.is_empty() or _core_is_up(own_roles) \
				or doctrine.tech_bias >= 0.55:
			_growth_want_key = "epoch %d" % (view.epoch() + 1)
			_growth_want_cost = advance_price
			_growth_is_advance = true
			return
	if not next_build.is_empty():
		_growth_want_key = String(next_build[0])
		_growth_want_cost = float(next_build[1]) + GROWTH_ITEM_MARGIN


# ═══════════════════════════════════════════════════════════════════════════
# THE EXPANSION DECISION
# ═══════════════════════════════════════════════════════════════════════════

## IS THE BUILD ORDER ASKING FOR SOMETHING EXPANSION MUST NOT JUMP?
##
## A POWER PLANT ALWAYS IS. The opening base is already in a brownout and
## docs/12 says a brownout slows work -- including the work of putting up the
## relay expansion wants, so jumping it is not even fast.
##
## THE FIRST REFINERY IS, because a derrick with nowhere to refine earns
## nothing at all: min(extraction, refine) is zero when either is.
##
## A SECOND REFINERY IS NOT, and that distinction is worth 200 seconds. The
## second one is bought to shorten an ore haul, not to process crude -- and
## measured, testing "is the next rung an economic one" without asking "do we
## already own it" put a 2,520-credit refinery in front of the whole
## expansion, so the first relay went up at 428 s instead of at 230.
func _econ_rung_missing(own_roles: Dictionary, next_build: Array) -> bool:
	if next_build.is_empty():
		return false
	var role := String(next_build[0])
	if not ECON_FIRST.has(role):
		return false
	if role == "power_plant":
		return true
	return int(own_roles.get(role, 0)) <= 0


## A REFINERY, WHEN THERE IS CRUDE GOING UNREFINED: [role, cost], or [].
##
## Counts refining that is paid for and on its way as well as refining that
## works, for the same reason the power rule does -- see _refine_coming.
func _pipe_want(own_roles: Dictionary) -> Array:
	if not has_home:
		return []
	if view.own_refine_capacity() + _refine_coming() \
			>= view.own_extraction_per_min():
		return []
	if int(own_roles.get("refinery", 0)) >= REFINERY_CAP:
		return []
	if float(_build_cool.get("refinery", -1.0e9)) > elapsed_s:
		return []
	var d := view.def_for("refinery")
	if d == null or not d.is_structure or d.refine_capacity <= 0.0:
		return []
	var menu := view.buildable()
	var allowed := false
	for role in menu:
		if role == "refinery":
			allowed = true
	if not allowed:
		return []
	return ["refinery", d.cost]


## WHAT EXPANSION WANTS NEXT: [role, cost, target_x, target_z], or [].
##
## Three answers are possible and only three. A derrick, when a field is in
## reach and there is spare refining to pay for its crude. A refinery, when
## there is crude going unrefined -- which is the OTHER half of the same tap
## and is why this function owns both. A relay, when the nearest field worth
## having is outside the build envelope and a chain can be walked to it.
##
## Every fact read here is this player's own: its purse's crude and refining
## lines, its own structures' positions and rings, and the published
## coordinates of the fields. Nothing says who holds a field -- the engine
## answers that by refusing the placement, and _confirm_pending_build turns
## the refusal into a cooldown on that field. That IS the fog: the AI finds
## out a well is taken by walking to it, exactly as a player does.
func _expansion_want(own_roles: Dictionary) -> Array:
	if not has_home:
		return []
	var fields := view.oil_points()
	if fields.is_empty():
		return []
	var derrick := view.def_for("oil_derrick")
	if derrick == null or not derrick.is_structure \
			or derrick.extraction_per_min < FIELD_WORTH_MIN:
		return []

	# THE PIPE BEFORE THE WELL. A derrick whose crude cannot be refined earns
	# nothing, so when the taps are level there is no point walking to another
	# well -- _pipe_want above has already asked for the refinery.
	var crude := view.own_extraction_per_min()
	var pipe := view.own_refine_capacity() + _refine_coming()
	if crude >= pipe:
		return []

	if float(_build_cool.get("oil_derrick", -1.0e9)) > elapsed_s:
		return []
	var pic := SimAiWorks.base_picture(view)
	if pic.is_empty():
		return []

	# ONE BUILDING AT A TIME WHILE A RING IS STILL GOING UP. An unfinished
	# structure projects no build radius -- SimEconomy only counts operational
	# ones -- so a second relay sited now would be measured against the
	# envelope the first one has not yet extended, land on top of it, and be
	# refused. Four of those refusals stand the whole chain down for seventy
	# seconds, which is how a chain that was working stops working.
	for row in pic:
		var y := row as SimAiWorks.Yard
		if not y.operational and y.radius_m > 0.0:
			return []

	var relay := _relay_def()
	# What a well's worth of crude costs in refining, at list price.
	var pipe_share := 0.0
	var refinery_def := view.def_for("refinery")
	if refinery_def != null and refinery_def.refine_capacity > 0.0:
		pipe_share = refinery_def.cost \
			* derrick.extraction_per_min / refinery_def.refine_capacity
	var best: Vector2 = Vector2.ZERO
	var best_d := INF
	var best_hops := 0x7FFFFFFF
	for k in range(fields.size()):
		if float(_field_cool.get(k, -1.0e9)) > elapsed_s:
			continue
		var f: Vector2 = fields[k]
		if _own_derrick_near(f):
			continue
		var hops := SimAiWorks.relays_needed(pic, relay, f.x, f.y) \
			if relay != null else 9999
		if SimAiWorks.shortfall(pic, f.x, f.y) <= 0.0:
			hops = 0
		if relays_built + hops > SimAiWorks.CREEP_MAX_RELAYS:
			continue
		# IS THE WALK WORTH IT? The bill is the relays, the derrick, AND the
		# share of a refinery the crude will need -- pricing the walk without
		# the pipe is how you talk yourself into a well you cannot sell from.
		# The return is the well's whole output, because by the time it is
		# pumping the pipe for it is bought.
		var bill := derrick.cost + float(hops) \
			* (relay.cost if relay != null else 0.0) + pipe_share
		var per_s := derrick.extraction_per_min / 60.0
		if per_s <= 0.0 or bill / per_s > EXPANSION_PAYBACK_S:
			continue
		# FEWEST RELAYS FIRST, then nearest, then field order -- a total
		# order, so the walk is identical on every run. Hops before distance
		# because a well already inside the envelope costs a derrick and
		# nothing else: taking that one before buying a shed to reach a
		# slightly nearer one is free money.
		var d2 := pow(f.x - home_x, 2.0) + pow(f.y - home_z, 2.0)
		if hops < best_hops or (hops == best_hops and d2 < best_d):
			best_d = d2
			best = f
			best_hops = hops
	if best_d == INF:
		return []
	if best_hops <= 0:
		return ["oil_derrick", derrick.cost, best.x, best.y]
	return [relay.role, relay.cost, best.x, best.y]


## THE CHEAPEST METRE OF REACH. A relay is bought for its build radius and for
## nothing else, so it is chosen on credits per metre of that radius -- which
## is what makes a supply depot win it (600 credits for 200 m) over a power
## plant (700 for 140) or a barracks (500 for 120), and it means the roster
## rather than a hardcoded role name decides. A depot is a fair thing to buy
## twice over anyway: it pushes supply out along the same line.
##
## Roles that cannot be sited freely are out: a derrick must stand on a field
## and a naval yard must stand in water, so neither can carry a chain overland.
func _relay_def() -> SimUnitDef:
	var best: SimUnitDef = null
	var best_score := INF
	for role in view.buildable():
		if SimAiWorks.FIELD_ROLES.has(role) or role == "naval_yard":
			continue
		var d := view.def_for(role)
		if d == null or not d.is_structure or d.build_radius_m <= 0.0:
			continue
		if float(_build_cool.get(role, -1.0e9)) > elapsed_s:
			continue
		var score := d.cost / d.build_radius_m
		if score < best_score:
			best_score = score
			best = d
	return best


## Do we already have a derrick standing on this field? Our OWN derricks only.
## Whether anybody else has one is not a question this bundle can answer, and
## must not become one -- SimEconomy.derrick_on() walks every structure on the
## map whoever owns it.
func _own_derrick_near(f: Vector2) -> bool:
	for i in view.forces.indices():
		if not view.forces.is_structure(i):
			continue
		var d := view.own_def(i)
		if d == null or d.role != "oil_derrick":
			continue
		var p := view.forces.position(i)
		if pow(p[0] - f.x, 2.0) + pow(p[2] - f.y, 2.0) \
				<= OIL_CLAIM_M * OIL_CLAIM_M:
			return true
	return false


## Refining that is paid for and on its way. The same trap as _power_coming():
## a refinery under construction processes nothing but IS one of our
## structures, so without this the AI asks for another one every eight seconds
## until it owns four and is pumping into three empty pipes.
func _refine_coming() -> float:
	var coming := 0.0
	for i in view.forces.indices():
		if not view.forces.is_structure(i) or view.own_is_operational(i):
			continue
		var d := view.own_def(i)
		if d != null:
			coming += d.refine_capacity
	if not _pending_build.is_empty():
		var pd := view.def_for(String(_pending_build[0]))
		if pd != null:
			coming += pd.refine_capacity
	return coming


## HOW MUCH MORE THAN THE PRICE A COMMANDER WANTS BANKED BEFORE IT SPENDS
## FORTY-FIVE SECONDS ON RESEARCH, in credits.
##
## docs/05 makes the TIME the risk, not the money, so this is a nerve dial and
## not an information one -- exactly what docs/09 §2 says a difficulty dial
## has to be. Measured in SECONDS OF ITS OWN INCOME rather than as a multiple
## of the price: a Recruit wants about three and a half minutes of production
## money still in hand, a Warlord about half a minute, and a Tech Rush
## doctrine shortens it further. Multiplying the price instead put the epoch
## step out of reach of this economy altogether.
func _advance_margin() -> float:
	var seconds := ADVANCE_MARGIN_BASE_S \
		+ ADVANCE_MARGIN_NERVE_S * (1.0 - doctrine.tech_bias) \
		+ ADVANCE_MARGIN_GRIP_S * (1.0 - _econ_grip())
	return maxf(GROWTH_ITEM_MARGIN, maxf(0.0, _income_ema) * seconds)


## Skill as a 0..1 grip on its own economy, the same shape as Ironfront's
## D.econ ladder (0.7 at Recruit to 1.45 at Warlord).
func _econ_grip() -> float:
	return float(clampi(skill, 0, SimSkill.LEVEL_COUNT - 1)) \
		/ float(SimSkill.LEVEL_COUNT - 1)


## Power, money and a way to spend both. Until these four are standing, an
## epoch step is a commander teching up with no economy behind it.
func _core_is_up(own_roles: Dictionary) -> bool:
	for role in ["power_plant", "refinery", "heavy_factory", "research_facility"]:
		if int(own_roles.get(role, 0)) <= 0:
			return false
	return true


## HOW MANY OF THIS ROLE THE BASE SHOULD HOLD. The old rule was presence: it
## asked whether it owned one, so it could never own two of anything, and a
## base is not a list of one of each.
func _wanted_count(role: String, own_roles: Dictionary) -> int:
	if role == "power_plant":
		# Not a count at all -- a headroom question. The opening base is
		# already in brownout, so this asks for the second plant in the first
		# strategic tick of the match.
		#
		# AND IT COUNTS WHAT IS COMING. A plant under construction supplies
		# nothing (SimEconomy only aggregates operational structures) but it
		# IS one of our own structures, so the naive version counted it in
		# `have`, saw the supply unchanged, and asked for have + 1 again --
		# a plant every eight seconds until the draw was met three times
		# over. Measured: three plants supplying 300 against a 110 draw, and
		# the research facility behind them never reached.
		var supply := view.own_power_supply() + _power_coming()
		var draw := view.own_power_draw()
		var have := int(own_roles.get(role, 0))
		return have + 1 if supply < draw * POWER_MARGIN else have
	var allowance := 1 + int(floor(maxf(0.0,
		_income_ema - INDUSTRY_FIRST_CR_S) / INDUSTRY_PER_CR_S))
	match role:
		"refinery":
			# SIZED TO THE CRUDE, not to the income, and the difference is
			# the reason the AI could never grow an economy. SimEconomy pays
			# min(extraction, refine): income is the OUTPUT of that pair, so
			# sizing refineries by income is reading the answer to decide the
			# question. A start pumps 480 a minute against 520 of refining,
			# so income says "you are fine" at the exact moment the next
			# derrick would earn 40 credits a minute instead of 240.
			#
			# COUNTS WHAT IS COMING, for the same reason the power rule does:
			# a refinery under construction refines nothing but IS one of our
			# structures, so the naive version asks for another every eight
			# seconds until the base is a refinery farm.
			var have_ref := int(own_roles.get(role, 0))
			if view.own_refine_capacity() + _refine_coming() \
					< view.own_extraction_per_min():
				return mini(REFINERY_CAP, have_ref + 1)
			# Crude is covered. A SECOND refinery is still worth something --
			# it is also where ore harvesters unload, and a second drop-off
			# halves a haul -- and that is the thing the income allowance was
			# always really measuring. It is capped at two, because beyond
			# that a refinery is neither pipe nor a shorter drive.
			return mini(REFINERY_CAP, maxi(1, mini(2, allowance)))
		"heavy_factory", "light_factory":
			return mini(3, allowance)
		"barracks":
			return mini(2, allowance)
		"oil_derrick":
			# One per field it can legally reach; siting refuses the rest.
			return maxi(1, view.oil_points().size())
	return 1


## WHAT THE REST OF THE BASE COSTS, to the next few rungs. This is the number
## the growth bucket is allowed to hold, so that an opening float can be split
## between an army and a PLAN rather than between an army and one shed.
func _plan_cost(own_roles: Dictionary) -> float:
	var total := 0.0
	var counted := 0
	for role in SimAiPlan.base_build_order(doctrine):
		if counted >= GROWTH_PLAN_DEPTH:
			break
		if int(own_roles.get(role, 0)) >= _wanted_count(role, own_roles):
			continue
		if float(_build_cool.get(role, -1.0e9)) > elapsed_s:
			continue
		var d := view.def_for(role)
		if d == null or not d.is_structure:
			continue
		total += d.cost
		counted += 1
	# THE EPOCH STEP IS IN THE PLAN FROM THE FIRST TICK, not from the moment a
	# research facility exists, and the difference is the whole ball game.
	#
	# This ceiling is what clamps the bucket, and the bucket is seeded from
	# the opening float. Pricing the plan without the step means the ceiling
	# on tick one is the cost of two or three sheds -- measured, 8,100 against
	# a 20,625 seed -- so the clamp threw 12,500 credits of the float back to
	# the production line before the AI had built the facility that would have
	# put the step INTO the plan. By the time it had one the money was tanks.
	#
	# Every doctrine's build order contains a research facility, so an AI that
	# has not reached its ceiling epoch intends to climb, and a plan is what
	# you intend rather than what you already own.
	var ceiling: int = view.setup.ceiling_epoch if view.setup != null else 7
	if view.epoch() < ceiling:
		var cost := view.epoch_advance_cost()
		total += (cost if cost > 0.0 else SimAiPlan.TECH_RESERVE) \
			+ _advance_margin()
	return total


## Power that is paid for and on its way: plants standing unfinished, plus one
## whose build order has been given and has not appeared yet.
func _power_coming() -> float:
	var coming := 0.0
	for i in view.forces.indices():
		if not view.forces.is_structure(i) or view.own_is_operational(i):
			continue
		var d := view.own_def(i)
		if d != null:
			coming += d.power_supply
	if not _pending_build.is_empty():
		var pd := view.def_for(String(_pending_build[0]))
		if pd != null:
			coming += pd.power_supply
	return coming


## The next thing in this doctrine's build order that the base is short of and
## is not standing down from. Returns [role, cost] or [].
func _next_structure(own_roles: Dictionary) -> Array:
	var menu := view.buildable()
	if menu.is_empty():
		return []
	var menu_set := {}
	for role in menu:
		menu_set[role] = true
	for role in SimAiPlan.base_build_order(doctrine):
		if not menu_set.has(role):
			continue
		if int(own_roles.get(role, 0)) >= _wanted_count(role, own_roles):
			continue
		if float(_build_cool.get(role, -1.0e9)) > elapsed_s:
			continue
		var d := view.def_for(role)
		if d == null or not d.is_structure:
			continue
		return [role, d.cost]
	return []


## Take the epoch step growth has been saving for. docs/05: it costs resources
## AND time, and the time is the risk.
func _advance_epoch(credits: float) -> void:
	if credits < _growth_want_cost:
		return
	if _idle_s <= 0.0 and _growth_budget < _growth_want_cost:
		return
	var cost := view.epoch_advance_cost()
	if not view.begin_epoch_advance():
		return
	epoch_advances_requested += 1
	_expanded_since_step = false        # expansion's turn comes round again
	_econ_spent += cost
	_growth_budget = maxf(0.0, _growth_budget - cost)
	_claim_since_s = -1.0
	log_decision("advancing to epoch %d (%.0f cr, margin %.0f, tech bias %.2f)"
		% [view.epoch() + 1, cost, _advance_margin(), doctrine.tech_bias])


## Put up the next building growth has chosen, if there is a legal spot for
## it and the budget has earned it.
func _build_out(credits: float, own_roles: Dictionary) -> void:
	if not has_home or _growth_want_key == "":
		return
	if elapsed_s - _last_build_s < BUILD_PERIOD_S:
		return
	if not _pending_build.is_empty():
		return                      # one order at a time; it has not landed yet
	var role := _growth_want_key
	var d := view.def_for(role)
	if d == null or not d.is_structure:
		return
	if d.cost > credits:
		return
	# The money has to have been EARNED by the growth bucket rather than
	# merely be lying in the account -- unless the account is idling, which is
	# the one case Ironfront lets bypass the budget.
	if _idle_s <= 0.0 and _growth_budget < d.cost:
		return
	var site := _build_site(d)
	if site.size() < 2:
		# Counted, because "I failed to build" and "the engine refused the spot
		# I chose" are the same fact to anyone reading this later, and a base
		# with nowhere legal left reporting refused 0 forever is the exact
		# silence that hid the original fault for this whole project.
		structures_refused += 1
		_note_build_failure(role, "nowhere legal inside our own radius")
		return
	view.order_build(role, site[0], site[1])
	if _creep_role == role and role != "oil_derrick" and role != "refinery":
		relays_built += 1
	orders_production += 1
	_last_build_s = elapsed_s
	_econ_spent += d.cost
	_growth_budget = maxf(0.0, _growth_budget - d.cost)
	_pending_build = [role, site[0], site[1]]
	_pending_known.clear()
	for i in view.forces.indices():
		if view.forces.is_structure(i):
			_pending_known[i] = true
	log_decision("building %s at %.0f, %.0f (%.0f cr, %d of a wanted %d)"
		% [role, site[0], site[1], d.cost, int(own_roles.get(role, 0)),
			_wanted_count(role, own_roles)])


## DID THE ORDER LAND? Ironfront's placeReady()/failN in our own terms.
##
## The AI cannot ask why a placement was refused -- SimEconomy.placement_problem()
## walks every structure on the map whoever owns it, so a probe against it
## would read the enemy's base off the refusals. What it CAN do is look at its
## own base and see whether the building it ordered is standing there, which
## is precisely what a player does when the cursor goes red.
func _confirm_pending_build() -> void:
	if _pending_build.is_empty():
		return
	var role := String(_pending_build[0])
	var x := float(_pending_build[1])
	var z := float(_pending_build[2])
	# A MATCH MUST BE A BUILDING WE DID NOT ALREADY HAVE. Proximity alone
	# false-confirms: a power plant's footprint is 12 m so two may legally
	# stand 25 m apart, the spiral's innermost ring is 60 m, and 80 m of
	# confirmation radius therefore accepts the plant that was ALREADY there.
	# The bite is not the counter -- it is that a refused build is recorded as
	# spent, so the credits are never refunded and the AI quietly pays for
	# buildings it does not get. Recording which structures existed when the
	# order went in is the only way to tell "it went up" from "one was near".
	for i in view.forces.indices():
		if not view.forces.is_structure(i):
			continue
		var d := view.own_def(i)
		if d == null or d.role != role:
			continue
		if _pending_known.has(i):
			continue                      # stood there before we ordered
		var p := view.forces.position(i)
		if pow(p[0] - x, 2.0) + pow(p[2] - z, 2.0) \
				<= BUILD_CONFIRM_M * BUILD_CONFIRM_M:
			structures_placed += 1
			if role == "oil_derrick":
				_expanded_since_step = true
			_build_fail.erase(role)
			_claim_since_s = -1.0
			_pending_build = []
			_pending_known.clear()
			log_decision("%s is up at %.0f, %.0f" % [role, x, z])
			return
	# It never appeared. Nothing was charged for it -- SimEconomy tests the
	# placement before it spends -- so the growth bucket gets its money back.
	# Ironfront has to refund explicitly here (placeReady, rq.failN); ours
	# only has to stop pretending it spent.
	var d2 := view.def_for(role)
	if d2 != null:
		_growth_budget += d2.cost
		_econ_spent -= d2.cost
	structures_refused += 1
	if role != "oil_derrick" and role != "refinery" \
			and _creep_role == role and relays_built > 0:
		relays_built -= 1               # it never went up; it is not a relay
	# A DERRICK REFUSED IS A FIELD SOMEBODY ELSE IS PROBABLY PUMPING -- or one
	# whose ground is occupied -- and the AI is not allowed to ask which. So
	# it does what a player with a red cursor does: leaves that well alone for
	# a while and walks to the next one. Without this the nearest field is
	# re-chosen every eight seconds until the role itself stands down, and the
	# second field is never even tried.
	if role == "oil_derrick":
		var k := _nearest_field_index(x, z)
		if k >= 0:
			_field_cool[k] = elapsed_s + SimAiWorks.FAIL_COOL_S
			log_decision("the well at %.0f, %.0f will not take a derrick -- leaving it %.0f s"
				% [x, z, SimAiWorks.FAIL_COOL_S])
	_pending_build = []
	_note_build_failure(role, "the engine refused the spot")


## Which published oil field a point was aimed at, or -1. Coordinates only.
func _nearest_field_index(x: float, z: float) -> int:
	var fields := view.oil_points()
	var best := -1
	var best_d := OIL_CLAIM_M * OIL_CLAIM_M
	for k in range(fields.size()):
		var f: Vector2 = fields[k]
		var d := pow(f.x - x, 2.0) + pow(f.y - z, 2.0)
		if d < best_d:
			best_d = d
			best = k
	return best


func _note_build_failure(role: String, why: String) -> void:
	var n := int(_build_fail.get(role, 0)) + 1
	_build_fail[role] = n
	var limit: int = SimAiWorks.FAIL_LIMIT_FIELD \
		if SimAiWorks.FIELD_ROLES.has(role) else SimAiWorks.FAIL_LIMIT
	if n < limit:
		log_decision("%s refused (%d/%d) -- %s" % [role, n, limit, why])
		return
	_build_cool[role] = elapsed_s + SimAiWorks.FAIL_COOL_S
	_build_fail[role] = 0
	log_decision("standing down on %s for %.0f s -- %d refused sitings"
		% [role, SimAiWorks.FAIL_COOL_S, limit])


## HOW MANY HARVESTERS. Measured, the AI built none at all: "Ore Miner" fell
## through the role classifier to ARMOR, and once it was line it was never the
## bucket it was shortest of. Both sides finished a six-minute peer match with
## an idle refinery and about a hundred credits, producing the cheapest
## infantry squad on the list because nothing else was affordable, while a
## 9,000-credit ore field sat 400 m from the base untouched.
##
## Two per refinery is the genre's answer and it is the right one here: a
## harvester costs 900 and carries 700 a load, so the second load is profit and
## the refinery is the thing that throttles.
func _wanted_harvesters(refineries: int) -> int:
	if refineries <= 0:
		return 0
	return mini(6, 2 * refineries)


## HOW MANY SCOUTS. The first job of an army that cannot see is to buy eyes,
## and one reconnaissance vehicle in a thirty-unit force -- which is what a
## peer match actually fielded -- cannot sweep a 6.4 km map before the match is
## decided.
##
## THE LADDER IS IRONFRONT'S, and it is a measured table rather than a
## formula: DIFF gives scouts 1 / 1 / 2 / 2 / 3 / 3 from Recruit to Warlord
## (js/ai.js:629-650). Ours was `2 + round(2 * sensor_share)`, which gave a
## Recruit 2 and an Elite 3 -- a rung and a half across the whole ladder. A
## Recruit that runs ONE car can genuinely be sneaked past, which is what
## makes Recruit beatable and Elite hard rather than both of them the same
## opponent at different speeds.
const SCOUTS_BY_SKILL: Array[int] = [1, 1, 2, 2, 3, 3, 3, 4]

## "The third waits for the three-minute mark or a fat bank -- the land
## theatres are decided by ~460-490 s and the opening money is the army's."
const SCOUT_THIRD_AFTER_S := 180.0
const SCOUT_THIRD_CASH := 2500.0


func _wanted_scouts() -> int:
	var want: int = SCOUTS_BY_SKILL[clampi(skill, 0, SCOUTS_BY_SKILL.size() - 1)]
	if want > 2 and elapsed_s < SCOUT_THIRD_AFTER_S \
			and view.credits() < SCOUT_THIRD_CASH:
		want = 2
	return want


## WHERE THIS BUILDING GOES. The rules are SimAiWorks'; the choice of which
## rule applies to which building is here, because it is a judgement about
## what the building is FOR.
##
## Returns an empty array when there is nowhere legal, and an empty answer is
## a real answer: the caller counts it as a failure rather than building at
## home and hoping, which is what the old ring did.
func _build_site(d: SimUnitDef) -> PackedFloat32Array:
	var pic := SimAiWorks.base_picture(view)
	if pic.is_empty():
		return PackedFloat32Array()

	# EXPANSION HAS ALREADY CHOSEN A POINT, and it is a specific field rather
	# than "the nearest one". A derrick goes ON it; anything else going there
	# is a relay, and a relay is sited by the creep -- the only rule that is
	# allowed to come back empty because the spot it found would not have
	# moved the frontier.
	if _creep_role != "" and d.role == _creep_role and d.role != "refinery":
		if d.role == "oil_derrick":
			return SimAiWorks.near(pic, view.terrain, d, _creep_x, _creep_z)
		return SimAiWorks.creep(pic, view.terrain, d, _creep_x, _creep_z)

	# A DERRICK STANDS ON A WELL and nowhere else -- the engine says so in
	# those words -- so there is no fallback for it.
	if d.role == "oil_derrick":
		return _site_on_field(pic, d, view.oil_points(), false)

	# A REFINERY GOES ON THE FIELD. Ironfront's "THE MINE": "a refinery ...
	# is sited AT a seen ore field rather than wherever a random spiral round
	# the yard lands - init() records the nearest ore at 19-26 tiles from an
	# AI start, so a yard-side refinery doubles every trip."
	if d.refine_capacity > 0.0:
		var on_field := _site_on_field(pic, d, view.resource_points(), true)
		if on_field.size() >= 2:
			return on_field

	# ANYTHING WHOSE JOB IS TO LOOK OR TO SHOOT OUTWARD reaches toward the
	# front -- Ironfront's spotToward, the only rule in its file that grows
	# the base outward at all.
	if SimAiWorks.FORWARD_ROLES.has(d.role):
		var axis := _sensor_axis()
		if absf(axis[0] - home_x) > 1.0 or absf(axis[1] - home_z) > 1.0:
			var out := SimAiWorks.toward(pic, view.terrain, d, axis[0], axis[1])
			if out.size() >= 2:
				return out

	var at := SimAiWorks.anchor(pic, SimAiWorks.is_industry(d.role),
		home_x, home_z, _front_x(), _front_z())
	return SimAiWorks.spiral(pic, view.terrain, d, at, home_x, home_z)


## Nearest field to our own base first, then outward: a refinery on the field
## we can already reach beats one on the richest field we cannot.
##
## The field coordinates are map features on exactly the footing docs/09 §1
## gives the terrain -- holes in the ground at published positions, the same
## ones the player's minimap draws. Nothing here says who is working one.
func _site_on_field(pic: Array, d: SimUnitDef, points: Array,
		allow_toward: bool) -> PackedFloat32Array:
	var ranked: Array = []
	for k in range(points.size()):
		var p: Vector2 = points[k]
		ranked.append([pow(p.x - home_x, 2.0) + pow(p.y - home_z, 2.0), k])
	ranked.sort_custom(_field_sort)
	for row in ranked:
		var p: Vector2 = points[int(row[1])]
		var s := SimAiWorks.near(pic, view.terrain, d, p.x, p.y)
		if s.size() >= 2:
			return s
		if allow_toward:
			s = SimAiWorks.toward(pic, view.terrain, d, p.x, p.y)
			if s.size() >= 2:
				return s
	return PackedFloat32Array()


## Distance, then index. A total order, so the walk is identical every run.
static func _field_sort(a: Array, b: Array) -> bool:
	if a[0] != b[0]:
		return a[0] < b[0]
	return a[1] < b[1]


# ═══════════════════════════════════════════════════════════════════════════
# OPERATIONAL
# ═══════════════════════════════════════════════════════════════════════════

func _observe() -> void:
	memory.observe(view.tracks_at_least(SimTypes.TrackQuality.CONTACT), elapsed_s)
	memory.forget_expired(elapsed_s)
	_remember_sites()


## Lay the coverage map over the public terrain, once, the first time this AI
## thinks. Deferred rather than done in _init because the terrain and the
## resource fields are attached to the view by the match layer, and an AI
## constructed before either exists would grid an empty world.
func _ensure_search() -> void:
	if search.built:
		return
	var ex := 40000.0
	var ez := 40000.0
	var water := Callable()
	if view.terrain != null:
		ex = view.terrain.extent_x_m()
		ez = view.terrain.extent_z_m()
		water = Callable(view.terrain, "is_water")
	search.build(ex, ez, rng, water)
	search.mark_resources(view.resource_points())
	log_decision(search.describe())


## "I have looked there." Written from the positions of THIS AI'S OWN UNITS and
## from nothing else -- the purest own-information there is, and the record
## that stops the army re-searching the ground it is standing on.
func _record_sweep(_dt: float) -> void:
	if not search.built:
		return
	for i in view.forces.indices():
		if view.forces.is_structure(i):
			continue
		var p := view.forces.position(i)
		search.mark_seen(p[0], p[2], SWEEP_RADIUS_M, elapsed_s)


## SOMETHING THAT DOES NOT MOVE IS SOMEWHERE, not something. A contact held for
## a while at effectively zero speed is a building, an emplacement or a parked
## army -- and where it stands stays true after the track has decayed, because
## buildings do not drive away.
##
## This is the AI knowing where it scouted your base, and it is earned: every
## site here was observed by its own sensors, at the position its own track
## table reported, which may be wrong. Nothing creates a site except an
## observation, and a site the army walks onto and finds empty is deleted.
func _remember_sites() -> void:
	for b in memory.live_beliefs():
		var belief := b as SimAiMemory.Belief
		if belief.bearing_only or belief.known_for(elapsed_s) < SITE_CONFIRM_S:
			continue
		if sqrt(belief.vx * belief.vx + belief.vz * belief.vz) > SITE_STATIC_SPEED_MS:
			continue
		var merged := false
		for row in _sites:
			if sqrt(pow(float(row[0]) - belief.x, 2.0)
					+ pow(float(row[1]) - belief.z, 2.0)) <= SITE_MERGE_M:
				row[2] = elapsed_s
				merged = true
				break
		if merged:
			continue
		if _sites.size() >= MAX_SITES:
			continue
		_sites.append([belief.x, belief.z, elapsed_s])
		log_decision("remembering a fixed position at %.0f, %.0f" % [belief.x, belief.z])


## Drop a site the army has stood on and found nothing at. Without this the AI
## drives at a razed base forever; with it, "I cleared that" is a fact it can
## learn the same way it learned the site existed.
func _forget_cleared_sites() -> void:
	if _sites.is_empty():
		return
	var live := memory.live_beliefs()
	var keep: Array = []
	for row in _sites:
		var occupied := false
		for b in live:
			var belief := b as SimAiMemory.Belief
			if belief.bearing_only:
				continue
			if sqrt(pow(belief.x - float(row[0]), 2.0)
					+ pow(belief.z - float(row[1]), 2.0)) <= SITE_CLEAR_M:
				occupied = true
				break
		if occupied:
			keep.append(row)
			continue
		var stood_on := false
		for g in groups:
			var group := g as SimAiGroup
			if group.role != SimAiGroup.Role.MAIN or group.is_empty():
				continue
			var c := _group_centre(group)
			if sqrt(pow(c[0] - float(row[0]), 2.0)
					+ pow(c[1] - float(row[1]), 2.0)) <= SITE_CLEAR_M:
				stood_on = true
				break
		if stood_on:
			log_decision("%.0f, %.0f is clear -- nothing there any more"
				% [float(row[0]), float(row[1])])
			continue
		keep.append(row)
	_sites = keep


## The remembered fixed position most worth going at from here: nearest first,
## which is how a force rolls up a position rather than crossing the map twice.
func _nearest_site(from_x: float, from_z: float) -> Array:
	var best: Array = []
	var best_d := INF
	for row in _sites:
		var d := sqrt(pow(float(row[0]) - from_x, 2.0) + pow(float(row[1]) - from_z, 2.0))
		if d < best_d:
			best_d = d
			best = row
	return best


## Membership. Units are assigned to groups and stay there: a group that is
## rebuilt from scratch every tick has no history, and without history there is
## no "we are losing".
func _update_groups() -> void:
	var idx := view.forces.indices()
	var assigned := {}
	for g in groups:
		var group := g as SimAiGroup
		var keep := PackedInt32Array()
		for i in group.members:
			if view.forces.owns(i):
				keep.append(i)
				assigned[i] = true
		group.members = keep
	# Drop the empties, preserving order.
	var live_groups: Array = []
	for g in groups:
		if not (g as SimAiGroup).is_empty():
			live_groups.append(g)
	groups = live_groups

	var axes: int = SimSkill.simultaneous_axes(skill)
	var unassigned_line := PackedInt32Array()
	for i in idx:
		if assigned.has(i):
			continue
		var role := _role_of(i)
		if role == SimAiRoles.Unit.BASE or role == SimAiRoles.Unit.PRODUCTION:
			continue
		# A HARVESTER IS NEVER IN A GROUP, because a group gets move orders and
		# a move order is a player order: SimHarvest.interrupt() suspends the
		# ore cycle until the unit is idle again. An AI that put its harvesters
		# in the line stopped its own economy AND sent unarmed vehicles at the
		# enemy. They earn; they do not manoeuvre.
		if SimAiRoles.is_economic(role):
			continue
		var target_role := SimAiGroup.Role.MAIN
		if role == SimAiRoles.Unit.SCOUT:
			target_role = SimAiGroup.Role.SCOUT
		elif SimAiRoles.is_sensor_platform(role):
			target_role = SimAiGroup.Role.SENSOR
		elif role == SimAiRoles.Unit.SUPPLY:
			target_role = SimAiGroup.Role.SUPPORT
		elif role == SimAiRoles.Unit.SAM:
			target_role = SimAiGroup.Role.SCREEN
		if target_role == SimAiGroup.Role.MAIN:
			unassigned_line.append(i)
			continue
		_group_for_role(target_role).add_member(i)

	if unassigned_line.is_empty():
		_refresh_strength()
		return

	# Manoeuvre groups, capped by the docs/09 §2 coordination dial. A Recruit
	# gets one axis; a Warlord gets five.
	var mains: Array = []
	for g in groups:
		if (g as SimAiGroup).role == SimAiGroup.Role.MAIN:
			mains.append(g)
	while mains.size() < axes and mains.size() < unassigned_line.size():
		var ng := _new_group(SimAiGroup.Role.MAIN)
		mains.append(ng)
	if mains.is_empty():
		mains.append(_new_group(SimAiGroup.Role.MAIN))
	# Fill the smallest group first, ties broken by group id, so the assignment
	# is identical on every run.
	for i in unassigned_line:
		var best: SimAiGroup = mains[0]
		for g in mains:
			var group := g as SimAiGroup
			if group.size() < best.size() \
					or (group.size() == best.size() and group.id < best.id):
				best = group
		best.add_member(i)
	_refresh_strength()


func _refresh_strength() -> void:
	for g in groups:
		var group := g as SimAiGroup
		var s := 0.0
		for i in group.members:
			s += view.forces.structure_fraction(i)
		group.strength = s
		group.peak_strength = maxf(group.peak_strength, s)
		if group.state == SimAiGroup.State.FORMING and not group.is_empty():
			group.formed_s = elapsed_s


func _group_for_role(role: int) -> SimAiGroup:
	for g in groups:
		if (g as SimAiGroup).role == role:
			return g
	return _new_group(role)


func _new_group(role: int) -> SimAiGroup:
	var g := SimAiGroup.new()
	g.id = _next_group_id
	_next_group_id += 1
	g.role = role
	g.formed_s = elapsed_s
	groups.append(g)
	return g


## The stance the whole force fights under this tick.
##
## ── WHY THIS LADDER WAS REBUILT ────────────────────────────────────────────
##
## The previous one was decided by two numbers, NEITHER OF WHICH WAS ABOUT THE
## ENEMY: whether any belief cleared the skill's commit threshold, and this
## army's cohesion against its own high-water mark. ATTACK required cohesion
## above 1.05 - 0.55*aggression, which for the DEFAULT Combined Arms doctrine
## is 0.775 -- so an army that had taken a quarter of a casualty could never
## attack again for the rest of the match, whatever it could see. Everything
## else fell through to PROBE, and PROBE had no exit. Measured on a peer match:
## both directors sat in PROBE for twelve simulated minutes.
##
## What replaces it is the thing an RTS commander actually asks: DO I HAVE
## ENOUGH FOR WHAT I CAN SEE? That question needs an estimate of the enemy, and
## the only honest one available is the size of its own picture -- how many
## distinct contacts it is holding. That number is earned (it is what its
## sensors built), it is wrong in interesting ways (a decoy inflates it, EMCON
## deflates it), and it costs nothing to fetch.
##
## Three ways into ATTACK, and the second and third are why PROBE can no longer
## be permanent:
##
##   ODDS      own committed strength per contact held, over the doctrine's bar
##   COMMITMENT once attacking, keep attacking for a fixed window. An army that
##             turns round the instant a track decays never arrives anywhere,
##             and tracks decay seconds after contact
##   PATIENCE  time spent in PROBE while holding something worth attacking.
##             When it runs out, go in on the odds available. This is the
##             stalemate breaker, and its length is the skill dial: about 90 s
##             for a Recruit, 25 s for an Elite, off the docs/09 §2 reaction row
func _choose_posture(dt: float) -> void:
	var committable := _committable_beliefs()
	var aggression: float = clampf(doctrine.aggression, 0.0, 1.0)
	var force_ratio := _force_strength_ratio()
	var previous := posture

	# PRESSURE. Only accumulates while it is looking at something it could go
	# and attack; a blind AI is not being patient, it is being blind.
	if posture == Posture.PROBE and not committable.is_empty():
		_pressure_s += dt
	elif posture != Posture.PROBE or committable.is_empty():
		_pressure_s = 0.0

	var odds := _odds()
	var bar := _odds_to_commit()
	var patience := _patience_s()
	var out_of_patience := _pressure_s >= patience
	var reason := ""

	if force_ratio < BASE_GROUP_BREAK - 0.25 * aggression:
		posture = Posture.WITHDRAW
		reason = "cohesion %.2f" % force_ratio
	elif posture == Posture.ATTACK and elapsed_s - _attack_since_s < _commit_hold_s():
		# COMMITMENT. Deliberately ABOVE the "nothing to shoot at" branch: an
		# attack that has already started does not stop because the picture
		# went dark, it presses on to the last known position. Losing contact
		# and driving home is the failure this project has fixed once already.
		posture = Posture.ATTACK
		reason = "committed for another %.0f s" % (_commit_hold_s() - (elapsed_s - _attack_since_s))
	elif committable.is_empty():
		# Nothing to shoot at is a reason to go LOOKING, not a reason to sit at
		# home -- and PROBE now means a systematic sweep of ground this AI has
		# not covered, not a drive to the middle and back.
		posture = Posture.PROBE if aggression >= 0.25 else Posture.DEFEND
		reason = "nothing committable"
	elif odds >= bar or out_of_patience:
		posture = Posture.ATTACK
		reason = ("odds %.2f over %.2f" % [odds, bar]) if odds >= bar \
			else "out of patience after %.0f s of probing" % _pressure_s
	elif aggression >= 0.30:
		posture = Posture.PROBE
		reason = "odds %.2f under %.2f, %.0f/%.0f s of patience left" % [
			odds, bar, _pressure_s, patience]
	else:
		posture = Posture.HOLD
		reason = "odds %.2f under %.2f" % [odds, bar]

	if posture == Posture.ATTACK and previous != Posture.ATTACK:
		_attack_since_s = elapsed_s
		_pressure_s = 0.0
	if previous != posture:
		log_decision("posture %s -> %s (%s; cohesion %.2f, %d committable)" % [
			POSTURE_NAMES.get(previous, "?"), POSTURE_NAMES.get(posture, "?"),
			reason, force_ratio, committable.size()])


## HOW MUCH ARMY THERE IS PER THING IT CAN SEE.
##
## The numerator is its own manoeuvre strength, which it knows exactly. The
## denominator is the size of its own PICTURE -- the count of live contacts --
## which is an estimate and a poor one: it counts a decoy, it misses everything
## under EMCON, and it says nothing about what any of those contacts is. That
## is the correct amount of information to attack on, and being wrong about it
## is how a commander loses a battle rather than how an AI cheats.
func _odds() -> float:
	var mine := 0.0
	for g in groups:
		var group := g as SimAiGroup
		if group.role == SimAiGroup.Role.MAIN:
			mine += group.strength
	var seen := 0
	for b in memory.live_beliefs():
		if not (b as SimAiMemory.Belief).bearing_only:
			seen += 1
	return mine / maxf(1.0, float(seen))


## Own units wanted per contact held before committing. Doctrine sets the
## appetite -- Blitz goes in level, a Fortress wants to be two to one -- and
## skill sharpens it, because judging when you have enough IS competence and
## docs/09 §2 puts competence, not information, on the difficulty slider.
func _odds_to_commit() -> float:
	var aggression: float = clampf(doctrine.aggression, 0.0, 1.0)
	var caution: float = clampf(
		SimSkill.reaction_seconds(skill) / 10.0, 0.0, 1.0)
	return (1.55 - 0.85 * aggression) * (0.88 + 0.32 * caution)


## How long an attack stays an attack whatever the picture does. Long enough to
## cross the ground between the two armies at least once.
func _commit_hold_s() -> float:
	return 30.0 + 45.0 * clampf(doctrine.aggression, 0.0, 1.0)


## How long this AI will look at something it could attack before attacking it
## anyway. THE STALEMATE BREAKER: with a finite patience, PROBE cannot be a
## terminal state, which is the property the old ladder lacked.
##
## Scaled off the published docs/09 §2 reaction row so the difficulty ladder
## keeps its shape: Recruit 10 s reaction -> ~92 s of dithering, Elite 1.5 s ->
## ~25 s, and an aggressive doctrine shortens both.
func _patience_s() -> float:
	var base := 12.0 + 8.0 * SimSkill.reaction_seconds(skill)
	return base * (1.35 - 0.7 * clampf(doctrine.aggression, 0.0, 1.0))


func _force_strength_ratio() -> float:
	var s := 0.0
	var p := 0.0
	for g in groups:
		var group := g as SimAiGroup
		if group.role != SimAiGroup.Role.MAIN:
			continue
		s += group.strength
		p += group.peak_strength
	if p <= 0.0:
		return 1.0
	return s / p


## Contacts good enough to move an army at. The commit threshold IS the
## difficulty dial from docs/09 §2 -- a Recruit waits for TQ3, an Elite acts on
## a TQ1 cue -- and the reaction latency is the other half of it.
func _committable_beliefs() -> Array:
	var threshold: int = SimSkill.commit_threshold(skill)
	var out: Array = []
	for b in _ranked_beliefs():
		var belief := b as SimAiMemory.Belief
		if belief.quality >= threshold and _actionable(belief):
			out.append(belief)
	return out


## Reaction latency, docs/09 §2: 8-12 s for a Recruit, 1-2 s for an Elite,
## measured from when the contact FIRST APPEARED in this AI's own picture.
func _actionable(belief: SimAiMemory.Belief) -> bool:
	return belief.known_for(elapsed_s) >= SimSkill.reaction_seconds(skill)


## Every live contact, most urgent first. Ties break on track id so two runs
## with the same seed rank an identical picture identically -- Array.sort_custom
## is not a stable sort, so the tie-break has to be explicit.
func _ranked_beliefs() -> Array:
	var live := memory.live_beliefs()
	var scored: Array = []
	for b in live:
		var belief := b as SimAiMemory.Belief
		var track := view.tracks.get_track(belief.track_id)
		if track == null:
			continue
		scored.append([threat_score(track), belief.track_id, belief])
	scored.sort_custom(_threat_sort)
	var out: Array = []
	for row in scored:
		out.append(row[2])
		if out.size() >= RANKED_LIMIT:
			break
	return out


## Most urgent first; equal scores fall back to the track id. Not a lambda,
## because a named comparator is the one a stack trace can point at.
func _threat_sort(a: Array, b: Array) -> bool:
	if a[0] == b[0]:
		return a[1] < b[1]
	return a[0] > b[0]


## Objectives, one per manoeuvre group, deconflicted. docs/09 §6: team AIs must
## at minimum not stack on one axis -- the same rule applies between one AI's
## own groups, and it is what makes multi-axis attack look like multi-axis
## attack rather than one column.
func _assign_objectives() -> void:
	memory.clear_claims()
	search.clear_claims()
	_forget_cleared_sites()
	_solo_obj.clear()
	var committable := _committable_beliefs()
	var cursor := 0

	for g in groups:
		var group := g as SimAiGroup
		if group.role == SimAiGroup.Role.SUPPORT:
			# Supply stays home. docs/09 §5 logistics_depth decides how far
			# forward "home" is allowed to creep.
			var depth: float = clampf(doctrine.logistics_depth, 0.0, 1.0)
			group.set_objective_point(
				lerpf(home_x, _front_x(), depth * 0.5),
				lerpf(home_z, _front_z(), depth * 0.5))
			group.state = SimAiGroup.State.HOLDING
			continue
		if group.role == SimAiGroup.Role.SCREEN:
			group.set_objective_point(home_x, home_z)
			group.state = SimAiGroup.State.HOLDING
			continue
		if group.role == SimAiGroup.Role.SENSOR:
			_place_sensors(group)
			continue
		if group.role == SimAiGroup.Role.SCOUT:
			_task_scouts(group)
			continue

		# MAIN.
		if posture == Posture.WITHDRAW \
				or group.strength_ratio() < _group_break_threshold():
			group.state = SimAiGroup.State.WITHDRAWING
			group.set_objective_point(home_x, home_z)
			continue
		if not committable.is_empty():
			# One contact per group while there are enough to go round, so the
			# axes really are separate axes. When there are fewer contacts than
			# groups the later ones double up on the most urgent rather than
			# sitting at home -- massing on one axis is right when there is only
			# one thing to mass on.
			var belief := committable[cursor % committable.size()] as SimAiMemory.Belief
			belief.claimed_by = group.id
			cursor += 1
			var pt := belief.predicted(elapsed_s, SimSkill.prediction(skill))
			group.set_objective_track(belief.track_id, pt[0], pt[1])
			group.state = SimAiGroup.State.ENGAGING if posture == Posture.ATTACK \
				else SimAiGroup.State.ADVANCING
			continue
		# Nothing worth committing to. What a force does now depends on what it
		# was TRYING to do, and getting that wrong was the single reason no
		# match in this game could ever end.
		#
		# The old rule offered the last-known-position fallback to a PROBE and
		# sent everything else home. So an army in ATTACK posture that lost its
		# tracks -- which happens seconds after contact, because tracks decay --
		# turned around and drove back to base. Measured: two AI opponents made
		# contact once at t+240 s, exchanged 28 rounds, withdrew, and spent the
		# next 25 simulated minutes building units at opposite corners of a
		# 12.8 km map. Two kills, and the victory condition could never fire
		# because neither side ever came near the other's production again.
		var pressing := posture == Posture.ATTACK or posture == Posture.PROBE
		if pressing:
			_press_on(group)
		else:
			group.set_objective_point(home_x, home_z)
			group.state = SimAiGroup.State.HOLDING


## AN ADVANCE WITH NOTHING LIVE TO ADVANCE ON. Getting this wrong is the single
## reason no match in this game could ever end, so the order of the four
## fallbacks is the whole behaviour:
##
##  1. THE LAST PLACE SOMETHING WAS. A track decays seconds after contact; an
##     axis of advance does not. Press to where it was last believed to be.
##  2. A REMEMBERED FIXED POSITION. Something that was seen and did not move is
##     still there, and it is the closest thing to "their base" this AI is
##     allowed to know -- because it scouted it.
##  3. GROUND IT HAS NOT LOOKED AT. The systematic sweep: nearest cell of the
##     coverage map that is unswept or has gone stale, CLAIMED so a second
##     group takes a different one. Three groups sent to the same waypoint are
##     one group with extra steps, and that is what the old code did -- every
##     manoeuvre group was sent to (0, 0).
##  4. Failing all of that, the middle, which assumes nothing about anybody.
##
## Note what is absent: any use of this AI's own start position to guess where
## the enemy started. On a symmetric map that finds the enemy base with no
## sensors at all, and it is exactly the knowledge docs/09 §1.1 forbids.
func _press_on(group: SimAiGroup) -> void:
	group.state = SimAiGroup.State.SEARCHING
	var stale := memory.stale_beliefs(elapsed_s)
	if not stale.is_empty() and not _at_objective(group):
		var last_known := stale[stale.size() - 1] as SimAiMemory.Belief
		var pt := last_known.predicted(elapsed_s, SimSkill.prediction(skill))
		group.set_objective_point(pt[0], pt[1])
		return
	var c := _group_centre(group)
	if not stale.is_empty():
		# Arrived where it was last seen and found nothing. Take the newest
		# memory that is not the one just walked onto, else fall through to the
		# sweep -- which starts from HERE, so the search continues forward
		# rather than restarting from home.
		var last_known2 := stale[stale.size() - 1] as SimAiMemory.Belief
		var pt2 := last_known2.predicted(elapsed_s, SimSkill.prediction(skill))
		if sqrt(pow(pt2[0] - c[0], 2.0) + pow(pt2[1] - c[1], 2.0)) > 900.0:
			group.set_objective_point(pt2[0], pt2[1])
			return
	var site := _nearest_site(c[0], c[1])
	if not site.is_empty():
		group.set_objective_point(float(site[0]), float(site[1]))
		return
	var cell := _sweep_cell_for(group, c[0], c[1])
	if cell >= 0:
		var p := search.centre_of(cell)
		group.set_objective_point(p[0], p[1])
		return
	group.set_objective_point(0.0, 0.0)


## The piece of ground this group is sweeping. A group KEEPS its cell until it
## gets there, so an army does not re-plan its search every two thirds of a
## second and stand still doing it; and cells are claimed, so two groups sweep
## two different squares.
func _sweep_cell_for(group: SimAiGroup, x: float, z: float) -> int:
	var held: int = int(_group_cell.get(group.id, -1))
	if held >= 0 and held < search.size() and not search.is_claimed(held):
		var c := search.centre_of(held)
		var arrived: bool = sqrt(pow(c[0] - x, 2.0) + pow(c[1] - z, 2.0)) \
			<= SEARCH_ARRIVE_M
		# Somebody else may have driven through it in the meantime, in which
		# case that ground is done and this group should be somewhere else.
		var already_covered: bool = elapsed_s - search.swept[held] \
			< SimAiSearch.RESWEEP_S
		if not arrived and not already_covered:
			search.claim(held)
			return held
	var next_cell := search.next_cell(x, z, elapsed_s)
	if next_cell < 0:
		_group_cell.erase(group.id)
		return -1
	search.claim(next_cell)
	_group_cell[group.id] = next_cell
	return next_cell


## Where a group actually is, from its OWN units. Uses the whitelisted forces
## view, never the entity store -- docs/09 §1.3.
func _group_centre(group: SimAiGroup) -> PackedFloat32Array:
	var sx := 0.0
	var sz := 0.0
	var n := 0
	for i in group.members:
		if not view.forces.owns(i):
			continue
		var pos := view.forces.position(i)
		sx += pos[0]
		sz += pos[2]
		n += 1
	if n == 0:
		return PackedFloat32Array([home_x, home_z])
	return PackedFloat32Array([sx / float(n), sz / float(n)])


## Has this group arrived where it was sent?
func _at_objective(group: SimAiGroup, tol := 700.0) -> bool:
	if not group.has_objective:
		return true
	var c := _group_centre(group)
	return sqrt(pow(c[0] - group.obj_x, 2.0) + pow(c[1] - group.obj_z, 2.0)) < tol


func _group_break_threshold() -> float:
	# An aggressive doctrine accepts losses (docs/09 §5, Attrition: "relentless,
	# cheap, endless"); a cautious one breaks off early.
	return BASE_GROUP_BREAK - 0.30 * clampf(doctrine.aggression, 0.0, 1.0)


## Sensors and AEW. docs/09 §2 makes this a skill dial and §5 makes it a
## doctrine one: a disciplined AI pushes the picture forward but not into the
## teeth of what it can see, and stops flying AEW forward when AEW keeps dying.
## WHERE THE RADARS STAND.
##
## THE FAULT: this used to be lerp(home, _front(), forwardness) and nothing
## else -- and _front_x/_front_z return HOME when the AI holds no positional
## belief. So the sensor group sat in the middle of the base at precisely the
## moment the AI could not see anything, which is the one moment a radar is
## worth moving. A blind commander whose radars are parked at home stays
## blind: that is not a cautious posture, it is a deadlock.
##
## THE FIX has three parts, and the third is what keeps it honest:
##   * with no belief, the sensors aim down the SEARCH AXIS instead of at
##     home -- where this AI's own army is going, or where it has not looked;
##   * the floor under forwardness RISES when blind rather than collapsing to
##     zero, because looking is then the whole job;
##   * but never past the screen its own army provides. An unescorted radar
##     forward of the line is an anti-radiation kill and a gift, so the push
##     is capped at what its own troops actually cover.
func _place_sensors(group: SimAiGroup) -> void:
	var forwardness: float = clampf(
		0.35 + 0.45 * doctrine.sensor_share - 0.35 * float(_sensor_losses_since_strategic), 0.0, 0.8)
	var axis := _sensor_axis()
	if not _has_positional_belief():
		forwardness = maxf(forwardness,
			BLIND_FORWARDNESS + 0.35 * SimSkill.sensor_share(skill))
	var fx := lerpf(home_x, axis[0], forwardness)
	var fz := lerpf(home_z, axis[1], forwardness)
	var dx := fx - home_x
	var dz := fz - home_z
	var out := sqrt(dx * dx + dz * dz)
	var screen := _screen_reach_m()
	var want := out
	if want > screen:
		want = screen
	# AND A FLOOR WHEN BLIND, which is the part that actually fixes the fault.
	# A ceiling alone still left the radars in the base: the search axis is
	# often the nearest unswept cell, a few hundred metres away, and 0.6 of a
	# few hundred metres is inside the headquarters' own build radius.
	# Measured at 273 m -- technically "forward", practically still at home.
	if not _has_positional_belief():
		want = maxf(want, minf(screen, SENSOR_MIN_REACH_M))
	if out > 1.0 and absf(want - out) > 1.0:
		fx = home_x + dx / out * want
		fz = home_z + dz / out * want
	group.set_objective_point(fx, fz)
	group.state = SimAiGroup.State.HOLDING


## The floor under forwardness when the AI holds no positional belief at all.
## Skill adds to it through sensor_share, so an Elite pushes its eyes out
## further than a Recruit -- a doctrine difference, not an information one.
const BLIND_FORWARDNESS := 0.45

## How far forward a sensor may be pushed with no army in front of it. Enough
## to clear the base and its own terrain mask; not enough to be a free kill.
const SENSOR_MIN_REACH_M := 900.0
const SENSOR_SCREEN_MARGIN_M := 400.0


## Does the AI hold a belief with a POSITION in it, as opposed to a bearing?
## The same test _front_x uses, asked separately so the sensor rule can act on
## the answer instead of silently receiving home.
func _has_positional_belief() -> bool:
	for b in memory.live_beliefs():
		var belief := b as SimAiMemory.Belief
		if belief.bearing_only \
				and belief.best_quality < SimTypes.TrackQuality.TRACK:
			continue
		return true
	return false


## WHERE TO POINT THE SENSORS WHEN THERE IS NOTHING TO POINT THEM AT. In
## descending order of how much it is actually worth knowing:
##   1. the front, when the AI holds a positional belief -- unchanged;
##   2. where its own manoeuvre groups are going, because eyes belong on the
##      axis the army is committed to;
##   3. the next unswept cell of its own coverage map, because that is the
##      ground it has decided it does not know about;
##   4. the middle of the map, which is at least not behind us.
## Every one of the four is the AI's own information.
func _sensor_axis() -> PackedFloat32Array:
	if _has_positional_belief():
		return PackedFloat32Array([_front_x(), _front_z()])
	var sx := 0.0
	var sz := 0.0
	var n := 0
	for g in groups:
		var group := g as SimAiGroup
		if group.role != SimAiGroup.Role.MAIN or group.is_empty():
			continue
		if absf(group.obj_x - home_x) < 1.0 and absf(group.obj_z - home_z) < 1.0:
			continue
		sx += group.obj_x
		sz += group.obj_z
		n += 1
	if n > 0:
		return PackedFloat32Array([sx / float(n), sz / float(n)])
	if search.built:
		var cell := search.next_cell(home_x, home_z, elapsed_s, false)
		if cell >= 0:
			return search.centre_of(cell)
	return PackedFloat32Array([0.0, 0.0])


## How far out its own troops actually reach. The sensor push is capped at
## this, so the radars advance BEHIND the screen rather than ahead of it.
func _screen_reach_m() -> float:
	var best := 0.0
	for i in view.forces.indices():
		if view.forces.is_structure(i):
			continue
		var role := _role_of(i)
		if SimAiRoles.is_sensor_platform(role) or SimAiRoles.is_economic(role):
			continue
		var p := view.forces.position(i)
		best = maxf(best, sqrt(pow(p[0] - home_x, 2.0) + pow(p[2] - home_z, 2.0)))
	return maxf(SENSOR_MIN_REACH_M, best + SENSOR_SCREEN_MARGIN_M)


## SCOUTS. docs/09 §3: "TQ1 bearing-only contact -> cue a sensor. Do not commit
## forces to a bearing." This is that rule with legs on it, and it is also the
## blackout behaviour -- with no picture at all, scouts search.
##
## THE CHANGE THAT MATTERS: scouts are tasked ONE AT A TIME, each to its own
## cell of the coverage map. They used to be driven as a formation, which meant
## that however many an AI built, they covered exactly one scout's worth of
## ground in a five-vehicle diamond. Reconnaissance is the one job where
## spreading out IS the job.
func _task_scouts(group: SimAiGroup) -> void:
	group.state = SimAiGroup.State.SEARCHING
	var cue: SimAiMemory.Belief = null
	for b in _ranked_beliefs():
		var belief := b as SimAiMemory.Belief
		if belief.quality <= SimTypes.TrackQuality.CONTACT and _actionable(belief):
			cue = belief
			break
	var first := true
	for i in group.members:
		if not view.forces.owns(i):
			continue
		var p := view.forces.position(i)
		var target: PackedFloat32Array
		if first and cue != null:
			# The nearest scout answers the cue; the rest keep sweeping, because
			# an army that stops searching the moment it holds one contact is an
			# army that gets flanked.
			target = _cue_point(cue)
		else:
			var cell := search.next_cell(p[0], p[2], elapsed_s)
			if cell < 0:
				target = PackedFloat32Array([home_x, home_z])
			else:
				search.claim(cell)
				target = search.centre_of(cell)
		_solo_obj[i] = target
		if first:
			group.set_objective_point(target[0], target[1])
			first = false
	if first:
		group.set_objective_point(home_x, home_z)


## Where to look for a bearing-only contact: down the bearing from home, or at
## the believed position if the contact ever had one.
func _cue_point(belief: SimAiMemory.Belief) -> PackedFloat32Array:
	if belief.best_quality >= SimTypes.TrackQuality.TRACK:
		return belief.predicted(elapsed_s, SimSkill.prediction(skill))
	var reach := _threat_radius_m()
	return PackedFloat32Array([
		home_x + sin(belief.bearing_rad) * reach,
		home_z + cos(belief.bearing_rad) * reach])


func _reached(group: SimAiGroup) -> bool:
	if group.is_empty():
		return true
	var p := view.forces.position(group.members[0])
	return sqrt(pow(p[0] - group.obj_x, 2.0) + pow(p[2] - group.obj_z, 2.0)) < 400.0


## EMCON. docs/09 §2 makes this the most legible difficulty dial there is: an
## easy opponent radiates carelessly and dies to anti-radiation missiles, a hard
## one goes quiet and shoots you on somebody else's track.
##
## Note what the "go loud" trigger is: the AI's own picture being empty, or its
## own objective being held at too low a rung to shoot at. Both are facts about
## itself.
func _manage_emcon() -> void:
	var discipline: float = clampf(
		0.5 * (SimSkill.emcon_discipline(skill)
			+ clampf(doctrine.emcon_discipline, 0.0, 1.0)), 0.0, 1.0)
	var blind := memory.live_count() == 0
	var needs_better := false
	for g in groups:
		var group := g as SimAiGroup
		if group.role != SimAiGroup.Role.MAIN or group.objective_track < 0:
			continue
		var t := view.tracks.get_track(group.objective_track)
		if t != null and t.quality < SimTypes.TrackQuality.FIRE_CONTROL:
			needs_better = true
	var go_loud := blind or needs_better or posture == Posture.ATTACK

	for i in view.forces.indices():
		var role := _role_of(i)
		var wanted := SimTypes.Emcon.RADIATE
		if discipline >= 0.25:
			if SimAiRoles.is_sensor_platform(role) or role == SimAiRoles.Unit.SAM:
				if go_loud:
					wanted = SimTypes.Emcon.RADIATE
				elif discipline >= 0.70:
					wanted = SimTypes.Emcon.SILENT
				else:
					wanted = SimTypes.Emcon.RECEIVE
			elif discipline >= 0.50:
				wanted = SimTypes.Emcon.SILENT
			else:
				wanted = SimTypes.Emcon.RECEIVE
		if view.forces.emcon(i) != wanted:
			view.order_emcon(i, wanted)
			orders_emcon += 1


## Turn each group's objective into per-unit move orders, in a formation rather
## than a stack.
func _manoeuvre() -> void:
	for g in groups:
		var group := g as SimAiGroup
		if group.is_empty():
			continue
		# Units searching alone -- scouts -- each have their own destination.
		if group.role == SimAiGroup.Role.SCOUT:
			for i in group.members:
				if not view.forces.can_move(i) or _withdrawn.has(i):
					continue
				var t: PackedFloat32Array = _solo_obj.get(i,
					PackedFloat32Array([group.obj_x, group.obj_z]))
				_order_move_if_needed(i, t[0], t[1])
			group.last_order_s = elapsed_s
			continue
		if not group.has_objective:
			continue
		var gx := group.obj_x
		var gz := group.obj_z
		# ── STANDOFF, and the bug that lived here ──────────────────────────
		#
		# "Stop short of the objective at a fraction of my own weapon reach"
		# was measured back from HOME, and applied to every objective including
		# a search waypoint. On skirmish_valley the bases are 2.56 km apart, a
		# tank's assumed reach is 4 km, so the standoff was 3 km: a group told
		# to sweep the map centre 1.8 km away had 3 km subtracted along the
		# outward axis and was sent to a point 1.2 km BEHIND ITS OWN BASE.
		# Measured, both armies drove into opposite corners and stayed there --
		# 976 sensor pairs evaluated over twelve simulated minutes and zero
		# detections between them. The AI was not failing to find the enemy; it
		# was ordered away from him.
		#
		# Two rules fix it and both are about what standoff MEANS. It is a
		# distance from a THING YOU CAN SEE, so it applies only to a live
		# contact and never to a piece of empty ground you are going to look
		# at. And it is measured back along the axis FROM THE GROUP, capped at
		# half the distance still to cover, so it can shorten an advance and
		# can never reverse one.
		if group.role == SimAiGroup.Role.MAIN \
				and group.objective_track >= 0 \
				and group.state != SimAiGroup.State.WITHDRAWING \
				and posture != Posture.ATTACK:
			var c := _group_centre(group)
			var dx := gx - c[0]
			var dz := gz - c[1]
			var to_go := sqrt(dx * dx + dz * dz)
			if to_go > 1.0:
				var standoff: float = minf(
					_group_reach_m(group) * STANDOFF_FRACTION,
					to_go * STANDOFF_MAX_SHARE)
				gx -= dx / to_go * standoff
				gz -= dz / to_go * standoff
		_move_formation(group, gx, gz)


func _move_formation(group: SimAiGroup, gx: float, gz: float) -> void:
	# The formation faces the way the group is actually going. Taking the axis
	# from home instead put the ranks side-on to the advance as soon as an
	# objective was anywhere but straight out from base.
	var c := _group_centre(group)
	var dir := _unit_vector(gx - c[0], gz - c[1])
	var px := -dir[1]
	var pz := dir[0]
	for k in range(group.members.size()):
		var i: int = group.members[k]
		if not view.forces.can_move(i) or _withdrawn.has(i):
			continue
		var lane := float(k % FORMATION_WIDTH) - float(FORMATION_WIDTH - 1) * 0.5
		var rank := float(k / FORMATION_WIDTH)
		var tx := gx + px * lane * FORMATION_SPACING_M - dir[0] * rank * FORMATION_SPACING_M
		var tz := gz + pz * lane * FORMATION_SPACING_M - dir[1] * rank * FORMATION_SPACING_M
		_order_move_if_needed(i, tx, tz)
	group.last_order_s = elapsed_s


func _order_move_if_needed(i: int, x: float, z: float) -> void:
	var prev: Array = _last_move.get(i, [])
	if not prev.is_empty():
		var moved := sqrt(pow(x - float(prev[0]), 2.0) + pow(z - float(prev[1]), 2.0))
		if moved < REORDER_MOVE_M and elapsed_s - float(prev[2]) < REORDER_REFRESH_S:
			return
	view.order_move(i, x, z)
	orders_moved += 1
	_last_move[i] = [x, z, elapsed_s]


# ═══════════════════════════════════════════════════════════════════════════
# TACTICAL
# ═══════════════════════════════════════════════════════════════════════════

## Break contact when hurt. docs/03 makes damage componentwise rather than a
## health bar, so "hurt" here means structure gone OR something important shot
## off -- a mobility-killed unit cannot run and is not asked to.
func _break_contact_if_hurt() -> void:
	var withdraw_at: float = BASE_WITHDRAW_HP - 0.20 * clampf(doctrine.aggression, 0.0, 1.0)
	for i in view.forces.indices():
		if view.forces.is_structure(i) or not view.forces.can_move(i):
			continue
		if SimAiRoles.is_economic(_role_of(i)):
			# Harvesters run themselves. Ordering one home would suspend the
			# ore cycle, which is the opposite of protecting the economy.
			continue
		var hp := view.forces.structure_fraction(i)
		var lost_firepower := (view.forces.components_lost(i)
			& SimTypes.Component.FIREPOWER) != 0
		if hp > withdraw_at + 0.15 and not lost_firepower:
			# Recovered, and a component does not grow back -- so this only ever
			# releases a unit that was pulled out for structure damage.
			_withdrawn.erase(i)
			continue
		if hp > withdraw_at and not lost_firepower:
			continue
		if not has_home:
			continue
		_withdrawn[i] = true
		_order_move_if_needed(i, home_x, home_z)


## Target selection and weapon-guidance matching, through the player's gate.
func _engage() -> void:
	var ranked := _ranked_beliefs()
	if ranked.is_empty():
		return
	_datalink_up = _network_alive()
	for i in view.forces.indices():
		if not view.forces.can_fire(i) or not view.forces.sensors_intact(i):
			continue
		var role := _role_of(i)
		var weapons: Array = loadouts.get(role, [])
		if weapons.is_empty():
			continue
		var p := view.forces.position(i)
		# Longest thing this unit carries, so a contact nothing could reach is
		# skipped before the gate is ever called.
		var reach_km := 0.0
		for wd0 in weapons:
			reach_km = maxf(reach_km, (wd0 as SimWeaponDef).max_range_km)
		var chosen := -1
		var chosen_weapon := ""
		var chosen_reason := ""
		for b in ranked:
			var belief := b as SimAiMemory.Belief
			if not _actionable(belief):
				continue
			var track := view.tracks.get_track(belief.track_id)
			if track == null:
				continue
			if not belief.bearing_only:
				var pt0 := belief.predicted(elapsed_s, SimSkill.prediction(skill))
				if sqrt(pow(p[0] - pt0[0], 2.0) + pow(p[2] - pt0[1], 2.0)) \
						> reach_km * 1000.0:
					continue
			for wd in weapons:
				var weapon := wd as SimWeaponDef
				var rk := _range_km_for(p, belief, weapon)
				if rk < 0.0:
					continue
				var res := SimWeaponGate.can_launch(weapon, track, rk, _datalink_up)
				if res.allowed:
					chosen = belief.track_id
					chosen_weapon = weapon.name
					chosen_reason = res.reason
					break
			if chosen >= 0:
				break
		if chosen < 0:
			continue
		var prev: Array = _assigned.get(i, [])
		if not prev.is_empty() and int(prev[0]) == chosen \
				and elapsed_s - float(prev[1]) < REENGAGE_PERIOD_S:
			continue
		view.order_attack(i, chosen)
		orders_attacked += 1
		_assigned[i] = [chosen, elapsed_s]
		var belief2 := memory.get_belief(chosen)
		if belief2 != null:
			belief2.orders_issued += 1
			belief2.last_order_s = elapsed_s
		log_decision("unit %d engages TK%d with %s -- %s"
			% [i, chosen, chosen_weapon, chosen_reason])


## Range from one of the AI's own units to what it BELIEVES is out there. Never
## to what is actually there: the aim point comes off the track.
##
## A bearing-only contact that has never had a position has no range at all,
## which is exactly why docs/09 §3 says do not commit to a bearing. The one
## exception is the anti-radiation shot, which is fired down the bearing at an
## assumed range and is allowed to miss -- and that is the intended behaviour,
## not a hole.
func _range_km_for(p: PackedFloat32Array, belief: SimAiMemory.Belief,
		weapon: SimWeaponDef) -> float:
	if belief.bearing_only and belief.best_quality < SimTypes.TrackQuality.TRACK:
		if weapon.guidance == SimTypes.Guidance.ANTI_RADIATION and belief.emitting:
			return weapon.max_range_km * 0.6
		return -1.0
	var pt := belief.predicted(elapsed_s, SimSkill.prediction(skill))
	return sqrt(pow(p[0] - pt[0], 2.0) + pow(p[2] - pt[1], 2.0)) / 1000.0


## Is there anything left to run a datalink over? Own units only.
func _network_alive() -> bool:
	for i in view.forces.indices():
		if view.forces.sensors_intact(i) and not view.forces.is_structure(i):
			return true
	return false


# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

## Cached because a unit's name and category never change, and because
## classifying a hundred units six times a second otherwise costs more than
## every decision above it.
func _role_of(i: int) -> int:
	if _role_cache.has(i):
		return _role_cache[i]
	var role := SimAiRoles.classify(view.forces.unit_name(i),
		view.forces.category(i), view.forces.is_structure(i),
		view.forces.max_speed_ms(i))
	_role_cache[i] = role
	return role


## The longest reach in a group, in metres, from what the AI believes its own
## units carry.
func _group_reach_m(group: SimAiGroup) -> float:
	var best := 1000.0
	for i in group.members:
		for wd in loadouts.get(_role_of(i), []):
			best = maxf(best, (wd as SimWeaponDef).max_range_km * 1000.0)
	return best


## The AI's own idea of where the fighting is: the mean of the contacts it
## currently holds, or home when it holds none. Used to place sensors and
## supply, so a blind AI keeps both at home rather than wandering forward.
func _front_x() -> float:
	var live := memory.live_beliefs()
	if live.is_empty():
		return home_x
	var s := 0.0
	var n := 0
	for b in live:
		var belief := b as SimAiMemory.Belief
		if belief.bearing_only and belief.best_quality < SimTypes.TrackQuality.TRACK:
			continue
		s += belief.x
		n += 1
	return home_x if n == 0 else s / float(n)


func _front_z() -> float:
	var live := memory.live_beliefs()
	if live.is_empty():
		return home_z
	var s := 0.0
	var n := 0
	for b in live:
		var belief := b as SimAiMemory.Belief
		if belief.bearing_only and belief.best_quality < SimTypes.TrackQuality.TRACK:
			continue
		s += belief.z
		n += 1
	return home_z if n == 0 else s / float(n)


func _threat_radius_m() -> float:
	if view.terrain != null:
		return maxf(view.terrain.extent_x_m(), view.terrain.extent_z_m()) * 0.25
	return 30000.0


func _unit_vector(dx: float, dz: float) -> PackedFloat32Array:
	var m := sqrt(dx * dx + dz * dz)
	if m < 0.0001:
		return PackedFloat32Array([0.0, 1.0])
	return PackedFloat32Array([dx / m, dz / m])


## THE NEXT POINT ON THIS AI'S SEARCH ROUTE, off the coverage map, marking it
## covered as it goes so successive calls walk a route rather than returning one
## answer forever.
##
## It used to be a sixteen-point lattice shuffled once from the seed, which had
## two problems: the route owed nothing to what the AI had already looked at,
## and it was a SECOND search implementation that only the determinism test in
## test_ai.gd ever exercised. Now the test and the AI walk the same ground, so
## "a different seed produces a different search route" measures the thing the
## army actually does. The seed enters through SimAiSearch's per-cell jitter,
## drawn once per cell in index order from this AI's own stream -- docs/06
## forbids randf() anywhere in the sim.
func _next_search_point() -> PackedFloat32Array:
	_ensure_search()
	var cell := search.next_cell(home_x, home_z, elapsed_s, false)
	if cell < 0:
		return PackedFloat32Array([home_x, home_z])
	var p := search.centre_of(cell)
	search.mark_seen(p[0], p[1], SWEEP_RADIUS_M, elapsed_s)
	return p


## How likely this contact is an ENABLER rather than part of the army, judged
## only from what a track carries. docs/09 §5 Interdiction hunts these.
##
## The honest limit is worth stating: a supply truck and a tank look identical
## on a radar track. What gives an enabler away is RADIATING, or orbiting slowly
## at altitude -- which is why killing the AI's AEW is possible and why the AI
## can return the favour. It cannot simply look up "that one is a fuel truck".
func _enabler_likelihood(track: SimTrack) -> float:
	var e := 0.0
	if track.emitting:
		e = maxf(e, 0.70)
	var speed := sqrt(track.vel_x * track.vel_x + track.vel_y * track.vel_y
		+ track.vel_z * track.vel_z)
	if track.category == SimTypes.Category.AIR and speed > 1.0 and speed < 230.0:
		# Slow and airborne: an AEW orbit, a tanker track, a transport.
		e = maxf(e, 0.65)
	if track.category == SimTypes.Category.GROUND and track.emitting and speed < 20.0:
		e = maxf(e, 0.90)
	if track.classification >= SimTypes.Classification.TYPE:
		# Knowing the type sharpens whatever the kinematics suggested; it does
		# not invent knowledge the track does not have.
		e = clampf(e * 1.15, 0.0, 1.0)
	return e


# ═══════════════════════════════════════════════════════════════════════════
# SAVE / LOAD (SimSave)
#
# Everything the director accumulates between ticks: the layer accumulators,
# the posture, home, the group roster, the belief memory, the adaptation
# counters, the per-unit order/assignment memories, the seeded search route
# and the rng stream. The doctrine's dials are saved too -- adapt() moves them
# during play, and the doctrine OBJECT is shared with the player's setup, so
# restoring writes the saved dials back into that same instance.
#
# NOT saved, and why it is safe: `loadouts` is rebuilt in _init as a pure
# function of SimAiRoles (set_loadout is a test-only hook no match calls);
# _role_cache memoises unit name/category, both immutable after spawn;
# decision_log is cosmetic.
# ═══════════════════════════════════════════════════════════════════════════

func to_dict() -> Dictionary:
	var groups_out: Array = []
	for g in groups:
		groups_out.append(SimSave.enc_props(g))
	var last_move := {}
	for u in _last_move:
		var e: Array = _last_move[u]
		last_move[str(u)] = [SimSave.enc_float(e[0]), SimSave.enc_float(e[1]),
			SimSave.enc_float(e[2])]
	var assigned := {}
	for u in _assigned:
		var e: Array = _assigned[u]
		assigned[str(u)] = [int(e[0]), SimSave.enc_float(e[1])]
	return {
		"player_id": view.player_id if view != null else -1,
		"faction": view.tracks.faction if view != null and view.tracks != null else 0,
		"rng": str(rng.state()),
		"skill": skill,
		"doctrine": SimSave.enc_props(doctrine),
		"accums": [SimSave.enc_float(_strategic_accum),
			SimSave.enc_float(_operational_accum), SimSave.enc_float(_tactical_accum)],
		"elapsed_s": SimSave.enc_float(elapsed_s),
		"memory": memory.to_dict(),
		"groups": groups_out,
		"posture": posture,
		"home": [SimSave.enc_float(home_x), SimSave.enc_float(home_z), has_home],
		"orders": [orders_moved, orders_attacked, orders_emcon,
			orders_production, epoch_advances_requested],
		"next_group_id": _next_group_id,
		"last_move": last_move,
		"assigned": assigned,
		"coverage": search.to_dict(),
		"group_cell_v": _group_cell_values(),
		"sites": _sites_out(),
		"attack_since_s": SimSave.enc_float(_attack_since_s),
		"pressure_s": SimSave.enc_float(_pressure_s),
		"adapt": [_peak_live_tracks, _prev_own_total, _prev_sensor_count,
			_losses_since_strategic, _sensor_losses_since_strategic],
		"datalink_up": _datalink_up,
		"last_build_s": SimSave.enc_float(_last_build_s),
		"withdrawn": SimSave.enc_ib(_withdrawn),
		# THE WORKS. All of it ordinary own-state: how much this AI has
		# earned, what it is saving for, and which building it has given up
		# on siting for the moment.
		"works": [SimSave.enc_float(_growth_budget),
			SimSave.enc_float(_income_ema), SimSave.enc_float(_cash_slope),
			SimSave.enc_float(_econ_prev_credits),
			SimSave.enc_float(_econ_spent), SimSave.enc_float(_idle_s),
			SimSave.enc_float(_claim_since_s),
			_growth_want_key, SimSave.enc_float(_growth_want_cost),
			_growth_is_advance, structures_placed, structures_refused,
			SimSave.enc_float(_growth_plan_cost),
			SimSave.enc_float(_econ_prev_earned)],
		"build_cool": _sf_out(_build_cool),
		"build_fail": _si_out(_build_fail),
		"pending_build": _pending_out(),
		# THE EXPANSION. Where the base is walking to, which wells it has
		# given up on for the moment, and how many relays it has spent doing
		# it -- all of it own state, and all of it needed or a restored AI
		# re-walks a chain it already paid for.
		"creep": [_creep_role, SimSave.enc_float(_creep_x),
			SimSave.enc_float(_creep_z), relays_built, _expanded_since_step],
		"field_cool": _sf_out(_field_cool),
	}


func from_dict(d: Dictionary) -> void:
	rng.restore_state(int(String(d["rng"])))
	skill = int(d["skill"])
	SimSave.dec_props(doctrine, d["doctrine"])
	var a: Array = d["accums"]
	_strategic_accum = SimSave.dec_float(a[0])
	_operational_accum = SimSave.dec_float(a[1])
	_tactical_accum = SimSave.dec_float(a[2])
	elapsed_s = SimSave.dec_float(d["elapsed_s"])
	memory.from_dict(d["memory"])
	groups.clear()
	for gd in (d["groups"] as Array):
		var g := SimAiGroup.new()
		SimSave.dec_props(g, gd)
		groups.append(g)
	posture = int(d["posture"])
	var h: Array = d["home"]
	home_x = SimSave.dec_float(h[0]); home_z = SimSave.dec_float(h[1])
	has_home = bool(h[2])
	var o: Array = d["orders"]
	orders_moved = int(o[0]); orders_attacked = int(o[1])
	orders_emcon = int(o[2]); orders_production = int(o[3])
	epoch_advances_requested = int(o[4])
	_next_group_id = int(d["next_group_id"])
	_last_move.clear()
	for k in (d["last_move"] as Dictionary):
		var e: Array = d["last_move"][k]
		_last_move[int(String(k))] = [SimSave.dec_float(e[0]),
			SimSave.dec_float(e[1]), SimSave.dec_float(e[2])]
	_assigned.clear()
	for k in (d["assigned"] as Dictionary):
		var e: Array = d["assigned"][k]
		_assigned[int(String(k))] = [int(e[0]), SimSave.dec_float(e[1])]
	search = SimAiSearch.new()
	if d.has("coverage"):
		search.from_dict(d["coverage"])
	_group_cell.clear()
	for k in (d.get("group_cell_v", {}) as Dictionary):
		_group_cell[int(String(k))] = int(d["group_cell_v"][k])
	_sites.clear()
	for row in (d.get("sites", []) as Array):
		var r: Array = row
		_sites.append([SimSave.dec_float(r[0]), SimSave.dec_float(r[1]),
			SimSave.dec_float(r[2])])
	_attack_since_s = SimSave.dec_float(d.get("attack_since_s", -1.0e9))
	_pressure_s = SimSave.dec_float(d.get("pressure_s", 0.0))
	_solo_obj.clear()
	var ad: Array = d["adapt"]
	_peak_live_tracks = int(ad[0]); _prev_own_total = int(ad[1])
	_prev_sensor_count = int(ad[2]); _losses_since_strategic = int(ad[3])
	_sensor_losses_since_strategic = int(ad[4])
	_datalink_up = bool(d["datalink_up"])
	_last_build_s = SimSave.dec_float(d["last_build_s"])
	_withdrawn = SimSave.dec_ib(d["withdrawn"])
	var wk: Array = d.get("works", [])
	if wk.size() >= 12:
		_growth_budget = SimSave.dec_float(wk[0])
		_income_ema = SimSave.dec_float(wk[1])
		_cash_slope = SimSave.dec_float(wk[2])
		_econ_prev_credits = SimSave.dec_float(wk[3])
		_econ_spent = SimSave.dec_float(wk[4])
		_idle_s = SimSave.dec_float(wk[5])
		_claim_since_s = SimSave.dec_float(wk[6])
		_growth_want_key = String(wk[7])
		_growth_want_cost = SimSave.dec_float(wk[8])
		_growth_is_advance = bool(wk[9])
		structures_placed = int(wk[10])
		structures_refused = int(wk[11])
	if wk.size() >= 14:
		_growth_plan_cost = SimSave.dec_float(wk[12])
		_econ_prev_earned = SimSave.dec_float(wk[13])
	_build_cool.clear()
	for k in (d.get("build_cool", {}) as Dictionary):
		_build_cool[String(k)] = SimSave.dec_float(d["build_cool"][k])
	_build_fail.clear()
	for k in (d.get("build_fail", {}) as Dictionary):
		_build_fail[String(k)] = int(d["build_fail"][k])
	_pending_build = []
	var pb: Array = d.get("pending_build", [])
	if pb.size() >= 3:
		_pending_build = [String(pb[0]), SimSave.dec_float(pb[1]),
			SimSave.dec_float(pb[2])]
	_creep_role = ""
	_creep_x = 0.0
	_creep_z = 0.0
	relays_built = 0
	var cr: Array = d.get("creep", [])
	if cr.size() >= 4:
		_creep_role = String(cr[0])
		_creep_x = SimSave.dec_float(cr[1])
		_creep_z = SimSave.dec_float(cr[2])
		relays_built = int(cr[3])
	_expanded_since_step = bool(cr[4]) if cr.size() >= 5 else false
	_field_cool.clear()
	for k in (d.get("field_cool", {}) as Dictionary):
		_field_cool[int(String(k))] = SimSave.dec_float(d["field_cool"][k])


## Group-cell assignments and remembered sites, in the encodings SimSave takes.
## Both are ordinary AI state: which square a group is sweeping, and where it
## saw something that did not move.
func _group_cell_values() -> Dictionary:
	var out := {}
	var keys: Array = _group_cell.keys()
	keys.sort()
	for k in keys:
		out[str(k)] = int(_group_cell[k])
	return out


## role -> float and role -> int, in a fixed key order so two saves of the
## same state are byte-identical.
func _sf_out(src: Dictionary) -> Dictionary:
	var out := {}
	var keys: Array = src.keys()
	keys.sort()
	for k in keys:
		out[String(k)] = SimSave.enc_float(float(src[k]))
	return out


func _si_out(src: Dictionary) -> Dictionary:
	var out := {}
	var keys: Array = src.keys()
	keys.sort()
	for k in keys:
		out[String(k)] = int(src[k])
	return out


func _pending_out() -> Array:
	if _pending_build.size() < 3:
		return []
	return [String(_pending_build[0]),
		SimSave.enc_float(float(_pending_build[1])),
		SimSave.enc_float(float(_pending_build[2]))]


func _sites_out() -> Array:
	var out: Array = []
	for row in _sites:
		out.append([SimSave.enc_float(float(row[0])),
			SimSave.enc_float(float(row[1])), SimSave.enc_float(float(row[2]))])
	return out


## The debug view docs/09 §1.6 asks for: what this AI believes, beside what it
## has decided. Print it next to ground truth and a leak is visible by eye.
func describe() -> String:
	var lines := PackedStringArray()
	lines.append("AI player %d  %s  %s" % [
		view.player_id if view != null else -1,
		SimSkill.name_of(skill), SimDoctrine.name_of(doctrine.profile)])
	lines.append("  posture %s   home (%.0f, %.0f)   %d live contact(s), %d remembered"
		% [POSTURE_NAMES.get(posture, "?"), home_x, home_z,
			memory.live_count(), memory.count()])
	lines.append("  orders: %d move, %d attack, %d emcon, %d production"
		% [orders_moved, orders_attacked, orders_emcon, orders_production])
	lines.append("  " + search.describe()
		+ "   %d remembered fixed position(s)" % _sites.size())
	lines.append(("  works: %.0f cr banked for %s, budget %.0f, income %.1f cr/s,"
		+ " %d placed, %d refused") % [view.credits() if view != null else 0.0,
		_growth_want_key if _growth_want_key != "" else "nothing",
		_growth_budget, _income_ema, structures_placed, structures_refused])
	for g in groups:
		lines.append("  " + (g as SimAiGroup).describe())
	return "\n".join(lines)
