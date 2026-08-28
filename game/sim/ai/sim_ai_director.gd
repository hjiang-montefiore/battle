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
	_economy()


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
func _economy() -> void:
	if not view.has_purse():
		return
	var credits := view.credits()

	# 1. TECHING UP. docs/05: it costs resources AND time, and the time is the
	# risk -- so a tech-biased doctrine spends earlier and a cautious one keeps
	# a cushion. The economy also requires a research facility, which is why
	# the build order below buys one.
	var ceiling: int = view.setup.ceiling_epoch if view.setup != null else 7
	if view.epoch() < ceiling and doctrine.tech_bias > 0.45:
		var cost := view.epoch_advance_cost()
		if cost <= 0.0:
			cost = SimAiPlan.TECH_RESERVE
		if credits >= cost * (1.0 + 0.8 * (1.0 - doctrine.tech_bias)):
			if view.begin_epoch_advance():
				epoch_advances_requested += 1
				credits = view.credits()
				log_decision("advancing epoch (tech bias %.2f, %.0f cr)"
					% [doctrine.tech_bias, cost])

	# 2. THE FORCE MIX, counted off its own army.
	var counts := {"sensors": 0, "air_defence": 0, "supply": 0, "line": 0}
	var factories := PackedInt32Array()
	var own_structure_names := {}
	var harvesters := 0
	var scouts := 0
	var refineries := 0
	for i in view.forces.indices():
		var role := _role_of(i)
		if view.forces.is_structure(i):
			own_structure_names[view.forces.unit_name(i)] = true
			if role == SimAiRoles.Unit.PRODUCTION:
				factories.append(i)
			if view.forces.unit_name(i).to_lower().contains("refinery"):
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

	# 3. THE BASE. One structure per strategic tick at most: an AI that queues
	# its whole build order in one frame is an AI with no build order.
	_build_out(credits, own_structure_names)

	# 4. PRODUCTION, at every factory that has a free slot.
	for f in factories:
		var options := view.production_options(f)
		if options.is_empty():
			continue
		var key := SimAiPlan.choose_production(view, doctrine, skill, options,
			counts, credits, _wanted_harvesters(refineries), _wanted_scouts())
		if key == "":
			continue
		var d := view.def_for(key)
		if d == null or d.cost > credits:
			continue
		view.order_produce(f, key)
		orders_production += 1
		credits -= d.cost
		counts[SimAiPlan.bucket_of_def(d)] = \
			int(counts.get(SimAiPlan.bucket_of_def(d), 0)) + 1
		log_decision("producing %s at %d (%.0f cr)" % [key, f, d.cost])


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
## decided. Skill buys more of them, because docs/09 §2 makes sensor share the
## clearest expression of competence there is.
func _wanted_scouts() -> int:
	return 2 + int(round(2.0 * SimSkill.sensor_share(skill)))


## Put up the next building in this doctrine's order that it does not already
## have. Own structures are recognised by their own names against its own build
## menu -- the AI knows what it built.
func _build_out(credits: float, own_structure_names: Dictionary) -> void:
	if not has_home or elapsed_s - _last_build_s < 8.0:
		return
	var menu := view.buildable()
	if menu.is_empty():
		return
	var have := {}
	for role in menu:
		var d := view.def_for(role)
		if d != null and own_structure_names.has(d.name):
			have[role] = true
	for role in SimAiPlan.base_build_order(doctrine):
		if have.has(role) or not menu.has(role):
			continue
		var d := view.def_for(role)
		if d == null or not d.is_structure or d.cost > credits:
			continue
		var site := _build_site(have.size())
		view.order_build(role, site[0], site[1])
		orders_production += 1
		_last_build_s = elapsed_s
		log_decision("building %s at %.0f, %.0f (%.0f cr)"
			% [role, site[0], site[1], d.cost])
		return


## A deterministic ring of candidate sites around home, skipping water. The
## terrain is public information (docs/09 §1), so consulting it is not a leak.
func _build_site(ordinal: int) -> PackedFloat32Array:
	var radius := 600.0 + 250.0 * float(ordinal)
	for k in range(8):
		var a := TAU * (float((ordinal * 3 + k) % 8) / 8.0)
		var x := home_x + cos(a) * radius
		var z := home_z + sin(a) * radius
		if view.terrain == null:
			return PackedFloat32Array([x, z])
		if not view.terrain.is_water(x, z):
			return PackedFloat32Array([x, z])
	return PackedFloat32Array([home_x, home_z])


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
func _place_sensors(group: SimAiGroup) -> void:
	var forwardness: float = clampf(
		0.35 + 0.45 * doctrine.sensor_share - 0.35 * float(_sensor_losses_since_strategic), 0.0, 0.8)
	var fx := lerpf(home_x, _front_x(), forwardness)
	var fz := lerpf(home_z, _front_z(), forwardness)
	group.set_objective_point(fx, fz)
	group.state = SimAiGroup.State.HOLDING


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
	for g in groups:
		lines.append("  " + (g as SimAiGroup).describe())
	return "\n".join(lines)
