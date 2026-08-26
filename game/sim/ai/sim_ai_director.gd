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
## Structure fraction below which a unit breaks contact.
const BASE_WITHDRAW_HP := 0.40
## Group strength ratio below which the whole group pulls back.
const BASE_GROUP_BREAK := 0.55

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
var _search_points: PackedFloat32Array = PackedFloat32Array()
var _search_cursor: int = 0
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
	_observe()
	_update_groups()
	_choose_posture()
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
	for i in view.forces.indices():
		var role := _role_of(i)
		if view.forces.is_structure(i):
			own_structure_names[view.forces.unit_name(i)] = true
			if role == SimAiRoles.Unit.PRODUCTION:
				factories.append(i)
			continue
		var bucket := SimAiPlan.bucket_of(role)
		if bucket != "":
			counts[bucket] = int(counts[bucket]) + 1

	# 3. THE BASE. One structure per strategic tick at most: an AI that queues
	# its whole build order in one frame is an AI with no build order.
	_build_out(credits, own_structure_names)

	# 4. PRODUCTION, at every factory that has a free slot.
	for f in factories:
		var options := view.production_options(f)
		if options.is_empty():
			continue
		var key := SimAiPlan.choose_production(view, doctrine, skill, options,
			counts, credits)
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
func _choose_posture() -> void:
	var committable := _committable_beliefs()
	var aggression: float = clampf(doctrine.aggression, 0.0, 1.0)
	var force_ratio := _force_strength_ratio()
	var previous := posture

	# COHESION, not a force comparison: _force_strength_ratio() is this army's
	# strength against its OWN peak, so 1.0 means intact and 0.5 means half
	# destroyed. Aggression therefore sets WILLINGNESS and cohesion sets
	# CAPABILITY, and the commit threshold is where the two meet.
	#
	# The previous ladder gated ATTACK on `aggression >= 0.55` alone, which made
	# four of the eight doctrines structurally incapable of ever attacking --
	# including COMBINED_ARMS at exactly 0.50, which is the DEFAULT. Two default
	# opponents therefore produced a permanent stalemate: measured, a peer match
	# ran 30 simulated minutes, made contact once at t+240 s, took two
	# casualties, withdrew to its start line and sat there while both sides
	# built units forever. The victory condition could never fire because
	# neither side ever threatened the other's production.
	#
	# Now every doctrine can attack; they differ in how intact they insist on
	# being first. Blitz commits at 0.53 cohesion (it will attack while losing),
	# Combined Arms at 0.78, Fortress at 0.99 (effectively only when untouched).
	var commit_at := 1.05 - 0.55 * aggression
	if force_ratio < BASE_GROUP_BREAK - 0.25 * aggression:
		posture = Posture.WITHDRAW
	elif committable.is_empty():
		# Nothing to shoot at is a reason to go LOOKING, not a reason to sit at
		# home. Losing contact used to drop a 0.5-aggression AI to DEFEND
		# permanently, because its beliefs expired after 240 s and nothing ever
		# refreshed them -- the AI blinded itself and then declined to scout.
		posture = Posture.PROBE if aggression >= 0.35 else Posture.DEFEND
	elif force_ratio >= commit_at:
		posture = Posture.ATTACK
	elif aggression >= 0.30:
		posture = Posture.PROBE
	else:
		posture = Posture.HOLD
	if previous != posture:
		log_decision("posture %s -> %s (cohesion %.2f, commit at %.2f, %d committable)" % [
			POSTURE_NAMES.get(previous, "?"), POSTURE_NAMES.get(posture, "?"),
			force_ratio, commit_at, committable.size()])


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
		# Nothing worth committing to. Hold the line, or go and look.
		var stale := memory.stale_beliefs(elapsed_s)
		if posture == Posture.PROBE and not stale.is_empty():
			var last_known := stale[stale.size() - 1] as SimAiMemory.Belief
			var pt2 := last_known.predicted(elapsed_s, SimSkill.prediction(skill))
			group.set_objective_point(pt2[0], pt2[1])
			group.state = SimAiGroup.State.SEARCHING
		else:
			group.set_objective_point(home_x, home_z)
			group.state = SimAiGroup.State.HOLDING


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


## Scouts answer cues. docs/09 §3: "TQ1 bearing-only contact -> cue a sensor. Do
## not commit forces to a bearing." This is that rule with legs on it, and it is
## also the blackout behaviour -- with no picture at all, scouts search.
func _task_scouts(group: SimAiGroup) -> void:
	var cue: SimAiMemory.Belief = null
	for b in _ranked_beliefs():
		var belief := b as SimAiMemory.Belief
		if belief.quality <= SimTypes.TrackQuality.CONTACT and _actionable(belief):
			cue = belief
			break
	if cue != null:
		var pt := _cue_point(cue)
		group.set_objective_point(pt[0], pt[1])
		group.state = SimAiGroup.State.SEARCHING
		return
	var stale := memory.stale_beliefs(elapsed_s)
	if not stale.is_empty():
		var b2 := stale[0] as SimAiMemory.Belief
		var p2 := b2.predicted(elapsed_s, SimSkill.prediction(skill))
		group.set_objective_point(p2[0], p2[1])
		group.state = SimAiGroup.State.SEARCHING
		return
	# Nothing at all. Sweep the map on a fixed, seeded route that owes nothing
	# to where the enemy actually is -- which is what makes the docs/09 §1.5
	# null-sensor test pass rather than merely not fail.
	if not group.has_objective or _reached(group):
		var p3 := _next_search_point()
		group.set_objective_point(p3[0], p3[1])
	group.state = SimAiGroup.State.SEARCHING


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
		if group.is_empty() or not group.has_objective:
			continue
		var gx := group.obj_x
		var gz := group.obj_z
		# Standoff: everything except a committed attack stops short of the
		# objective, at a fraction of its own weapon reach.
		if group.role == SimAiGroup.Role.MAIN \
				and group.state != SimAiGroup.State.WITHDRAWING \
				and posture != Posture.ATTACK:
			var reach := _group_reach_m(group) * STANDOFF_FRACTION
			var away := _unit_vector(gx - home_x, gz - home_z)
			gx -= away[0] * reach
			gz -= away[1] * reach
		_move_formation(group, gx, gz)


func _move_formation(group: SimAiGroup, gx: float, gz: float) -> void:
	var dir := _unit_vector(gx - home_x, gz - home_z)
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


## A search route over the PUBLIC map, shuffled from this AI's own seeded
## stream. It is a function of the seed and the terrain and of nothing else --
## which is the property the null-sensor test in test_ai.gd measures.
func _next_search_point() -> PackedFloat32Array:
	if _search_points.is_empty():
		_build_search_route()
	if _search_points.is_empty():
		return PackedFloat32Array([home_x, home_z])
	var n := _search_points.size() / 2
	var k := _search_cursor % n
	_search_cursor += 1
	return PackedFloat32Array([_search_points[k * 2], _search_points[k * 2 + 1]])


func _build_search_route() -> void:
	var half_x := 20000.0
	var half_z := 20000.0
	if view.terrain != null:
		half_x = view.terrain.extent_x_m() * 0.35
		half_z = view.terrain.extent_z_m() * 0.35
	var pts: Array = []
	for gx in range(4):
		for gz in range(4):
			pts.append(Vector2(
				lerpf(-half_x, half_x, float(gx) / 3.0),
				lerpf(-half_z, half_z, float(gz) / 3.0)))
	# Fisher-Yates from the seeded stream. docs/06 forbids randf() in the sim,
	# and a shuffle is exactly where somebody reaches for it.
	for k in range(pts.size() - 1, 0, -1):
		var j := rng.next_int(0, k)
		var tmp: Vector2 = pts[k]
		pts[k] = pts[j]
		pts[j] = tmp
	_search_points = PackedFloat32Array()
	for p in pts:
		_search_points.append((p as Vector2).x)
		_search_points.append((p as Vector2).y)


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
	for g in groups:
		lines.append("  " + (g as SimAiGroup).describe())
	return "\n".join(lines)
