class_name SimSortie
extends RefCounted
## Aircraft sorties: the Empire Earth half of the air game. docs/04.
##
## An aircraft's natural state is GROUNDED at a base. A SORTIE_STRIKE order
## launches it, flies it out, loiters it over the point long enough for the
## fire-control layer to spend its ordnance, and brings it home on the docs/04
## fuel rule. A SORTIE_PATROL order does the same but the order STANDS: after
## recovery and turnaround the base relaunches the same aircraft onto the same
## orbit, again and again, until the player says otherwise. One click, a
## standing air patrol -- that loop is the whole point of this file.
##
## THE RTB RULE, exactly docs/04:
##
##     range_remaining = fuel_current / burn_per_km_at_cruise
##     RTB when  range_remaining < RESERVE x d_home        RESERVE = 1.10
##
## range_remaining is SimEntities.range_remaining_m() -- the same arithmetic
## the docs quote, already costed at CRUISE burn regardless of throttle.
## d_home is recomputed every step against the NEAREST currently-operational
## recovery point, so killing an airfield re-routes everything that was homed
## on it (docs/04 consequence 5), and losing the LAST one leaves the aircraft
## flying until dry -- at which point SimEconomy._run_dry() applies the
## existing rule that a dry aircraft is destroyed, not parked at altitude.
##
## WHAT THIS FILE DOES NOT DO. It never writes a position (movement +
## _integrate own that); it issues waypoints through SimMovement exactly as a
## player's move order would. It never fires a weapon (fire control and the
## weapon cycle own engagement; this file only parks the aircraft where the
## picture is). It never burns fuel (the economy owns fuel; this file only
## READS the tank). It draws no random numbers at all.
##
## SANCTIONED WRITES, mirroring the ownership table in sim_entities.gd:
##   sortie_state ... this system's own column, slot 3.7 only.
##   home_base ...... re-set when a recovery point is chosen or lost.
##   vel_y .......... SimMovement._vertical_velocity() explicitly defers the
##                    vertical channel of AIR units to "their own layer"; this
##                    is that layer. Climb and descent are written here, before
##                    the movement slot, and steering preserves them.
##   touchdown ...... on landing the aircraft is stopped through
##                    movement.order_stop(), the same call a player's STOP
##                    uses, and its vertical velocity is zeroed.
##   Mount.rounds ... rearming during turnaround at an operational base
##                    restores the loadout the aircraft first flew with.
##
## DETERMINISM. Tasks live in a Dictionary keyed by unit index, and every
## iteration sorts the keys first. No RNG calls, no wall clock, no hash-order
## anything.
##
## ONE HONEST ADDITION TO THE RULE. range_remaining prices the trip at cruise
## SPEED, but fuel burns per MINUTE, and the movement layer accelerates and
## brakes at real rates -- a 560 m/s interceptor spends a minute of full burn
## braking for the pad, which the per-km model never budgeted. Measured, that
## deficit is exactly the braking law's v^2 / (2 x decel) in metres of range.
## The trigger therefore reserves it explicitly:
##
##     RTB when  range_remaining < RESERVE x (d_home + landing_overhead)
##
## with landing_overhead = v_max^2 / (4 x accel), matching SimMovement's
## decel of 2 x accel. Without this term the rule as literally written lands
## aircraft dry -- docs/04 consequence 6 anticipates the tuning, and this is
## that tuning made kinematic instead of a fudged RESERVE.

## docs/04: the reserve factor. "1.10 is the specified default and makes the
## game tense."
const RESERVE := 1.10

## Waypoints on a patrol orbit. Eight points approximate a circle closely
## enough that the racetrack reads as an orbit on the map.
const ORBIT_POINTS := 8

## Refuel-and-rearm time on the pad between sorties (docs/04: TURNAROUND is
## "a real time cost -- sortie rate is a resource"). Fuel itself flows at the
## base's supply rate on the economy tick; this is the floor.
const TURNAROUND_S := 20.0

## How long a strike loiters over the target before turning for home. The
## fire-control layer does the shooting; this is the window it gets. A
## winchester (all finite magazines empty) ends the station early.
const STRIKE_STATION_S := 15.0
const STRIKE_ORBIT_M := 700.0

## Flight profile. Rotary aircraft fly low and climb gently; everything else
## cruises high. AGL where terrain exists, ASL over water.
const CRUISE_ALT_FIXED_M := 2000.0
const CRUISE_ALT_ROTARY_M := 150.0
const CLIMB_FIXED_MS := 60.0
const CLIMB_ROTARY_MS := 18.0

## Recovery geometry. Inside APPROACH the aircraft is RECOVERING (committed,
## not re-taskable); at TOUCHDOWN radius and pad height it is GROUNDED.
const APPROACH_RADIUS_M := 600.0
const TOUCHDOWN_RADIUS_M := 45.0
const TOUCHDOWN_ALT_M := 15.0
## Glide slope on the way home: desired height above the pad is distance x
## this. Descending EN ROUTE matters for the fuel arithmetic -- the RTB
## reserve is costed at cruise, and an aircraft that only starts down after
## arriving overhead loiters on fuel the reserve never budgeted.
const DESCENT_SLOPE := 0.1
## The apron convention: SimEconomy._spawn_altitude() parks aircraft at
## ground + 10 m, and a landing ends at the same height.
const PARK_ALT_M := 10.0

## Which structures recover which aircraft. From the roster: fixed-wing lives
## at an airbase (a carrier recovers naval air); rotary uses helipads, and may
## also put down at an HQ or a carrier. Tanker orbits as recovery points
## (docs/04 consequence 3) are NOT implemented -- see is_implemented() notes.
const PADS_FIXED: Array[String] = ["airbase", "carrier"]
const PADS_ROTARY: Array[String] = ["helipad", "hq", "carrier"]

var entities: SimEntities
var movement: SimMovement
var economy: SimEconomy
var weapons: SimWeaponCycle = null
var terrain: SimTerrain = null

## One standing order per aircraft. STRIKE is one launch -- delivered or
## driven home early, landing clears it. PATROL survives the landing and
## relaunches; only a new order, a cancel or death clears it.
class Task extends RefCounted:
	var kind: int = SimTypes.OrderKind.SORTIE_STRIKE
	var x: float = 0.0
	var z: float = 0.0
	var radius_m: float = 0.0        ## patrol orbit radius
	var leg: int = 0                 ## current orbit waypoint index
	var station_s: float = 0.0       ## strike: loiter remaining
	var turnaround_s: float = 0.0    ## grounded: pad time remaining
	var ordered_x: float = 0.0       ## last waypoint pushed to movement
	var ordered_z: float = 0.0
	var full_rounds: Array = []      ## loadout snapshot, for rearming
	var hold_x: float = 0.0          ## stranded loiter centre (no recovery)
	var hold_z: float = 0.0
	var stranded: bool = false


var _tasks: Dictionary = {}          ## unit -> Task; iterated over sorted keys

# ── counters and last-event records, for tests and the HUD ──────────────────
var sorties_flown: int = 0
var recoveries: int = 0
var diverts: int = 0                 ## recovery point changed mid-RTB
var log: PackedStringArray = PackedStringArray()

## Snapshot of the moment the RTB rule last tripped, per unit:
## {"range_m", "d_home_m", "reason"}. This is the number the docs/04 margin
## assertion in test_sortie.gd reads.
var last_rtb: Dictionary = {}


func _init(store: SimEntities, move: SimMovement, eco: SimEconomy,
		weps: SimWeaponCycle = null, terr: SimTerrain = null) -> void:
	entities = store
	movement = move
	economy = eco
	weapons = weps
	terrain = terr


## Build from a world and install into its slot 3.7. The one-line wiring a
## match layer calls, mirroring how fire_control is installed.
static func install(world: SimWorld) -> SimSortie:
	var s := SimSortie.new(world.entities, world.movement, world.economy,
		world.weapons, world.terrain)
	world.sortie_system = s
	return s


# ═══════════════════════════════════════════════════════════════════════════
# ORDER INTAKE -- called from SimWorld._execute_command(), already
# ownership-checked. Returns false to have the command counted as rejected.
# ═══════════════════════════════════════════════════════════════════════════

func order_strike(unit: int, x: float, z: float) -> bool:
	return _order(unit, SimTypes.OrderKind.SORTIE_STRIKE, x, z, 0.0)


func order_patrol(unit: int, x: float, z: float, radius_m: float) -> bool:
	return _order(unit, SimTypes.OrderKind.SORTIE_PATROL, x, z,
		maxf(radius_m, 200.0))


func _order(unit: int, kind: int, x: float, z: float, radius_m: float) -> bool:
	if not entities.is_alive(unit):
		return false
	if entities.category[unit] != SimTypes.Category.AIR:
		return false
	if entities.is_aboard(unit):
		return false
	if entities.max_speed_ms[unit] <= 0.0:
		return false
	# docs/04: LANDING is committed. An aircraft on the approach finishes it;
	# re-task it after the turnaround.
	if entities.sortie_state[unit] == SimTypes.SortieState.RECOVERING:
		return false

	# Feasible at all? Measured at a FULL tank from the launch point, with the
	# docs/04 reserve on the whole round trip. An order the aircraft could
	# never fly is refused now, honestly, rather than hanging forever on a
	# launch gate that cannot open.
	var d_out := _dist2d(entities.pos_x[unit], entities.pos_z[unit], x, z)
	var d_back := _recovery_dist_from(unit, x, z)
	if entities.fuel_capacity[unit] > 0.0 \
			and entities.burn_cruise_lpm[unit] > 0.0:
		var full_range: float = entities.fuel_capacity[unit] \
			/ entities.burn_cruise_lpm[unit] * 60.0 \
			* entities.max_speed_ms[unit]
		if full_range < RESERVE * (d_out + d_back) \
				+ 3.0 * _landing_overhead_m(unit):
			_note("%s: sortie refused, beyond round-trip range"
				% entities.names[unit])
			return false

	var t := Task.new()
	t.kind = kind
	t.x = x
	t.z = z
	t.radius_m = radius_m
	_snapshot_loadout(unit, t)
	_tasks[unit] = t
	_ensure_home(unit)

	if entities.sortie_state[unit] == SimTypes.SortieState.GROUNDED:
		# The launch gate in _step_grounded() decides when it actually goes,
		# so an aircraft mid-refuel waits for fuel rather than launching thin.
		t.turnaround_s = 0.0
	else:
		# Already airborne: re-task in place.
		_launch(unit, t, false)
	return true


## Withdraw a standing order. An airborne aircraft turns for home; a grounded
## one simply stands down. Exposed for the UI layer (there is no CANCEL
## routing to slot 3.7); a NEW sortie order replaces the old one implicitly.
func cancel(unit: int) -> bool:
	if not _tasks.has(unit):
		return false
	var t: Task = _tasks[unit]
	_tasks.erase(unit)
	if entities.is_alive(unit) \
			and entities.sortie_state[unit] != SimTypes.SortieState.GROUNDED \
			and entities.sortie_state[unit] != SimTypes.SortieState.RECOVERING:
		var rec := _nearest_recovery(unit)
		if rec >= 0:
			# Fly the recovery without a task: re-adopt a bare RTB task.
			var home := Task.new()
			home.kind = SimTypes.OrderKind.SORTIE_STRIKE
			home.x = entities.pos_x[unit]
			home.z = entities.pos_z[unit]
			home.full_rounds = t.full_rounds
			_tasks[unit] = home
			_begin_rtb(unit, home, rec, "ordered home")
	return true


# ═══════════════════════════════════════════════════════════════════════════
# THE TICK -- slot 3.7, after economy (this tick's fuel), before movement
# (intent issued here is steered this same tick).
# ═══════════════════════════════════════════════════════════════════════════

func step(dt: float) -> void:
	if _tasks.is_empty():
		return
	var units: Array = _tasks.keys()
	units.sort()
	for u in units:
		if not entities.is_alive(u):
			_tasks.erase(u)
			last_rtb.erase(u)
			continue
		if entities.is_aboard(u):
			continue   # stowed; the sortie resumes when it is back on the map
		var t: Task = _tasks[u]
		match entities.sortie_state[u]:
			SimTypes.SortieState.GROUNDED:
				_step_grounded(u, t, dt)
			SimTypes.SortieState.OUTBOUND:
				_step_outbound(u, t, dt)
			SimTypes.SortieState.ON_STATION:
				_step_station(u, t, dt)
			SimTypes.SortieState.RTB:
				_step_rtb(u, t, dt)
			SimTypes.SortieState.RECOVERING:
				_step_recovering(u, t, dt)


func is_implemented() -> bool:
	return true


# ── grounded: turnaround, rearm, and the launch gate ─────────────────────────

func _step_grounded(u: int, t: Task, dt: float) -> void:
	if t.turnaround_s > 0.0:
		t.turnaround_s -= dt
		if t.turnaround_s <= 0.0:
			_rearm(u, t)
		return
	if not entities.can_move(u):
		return   # dry or mobility-killed on the pad; the economy refuels it

	# THE LAUNCH GATE: the RTB rule run forward. Launch only when the tank
	# covers the whole round trip -- out, back from the point to the nearest
	# recovery, both under the reserve -- so a sortie never launches into an
	# immediate RTB. An aircraft mid-refuel simply waits here; the base's
	# supply rate is what a rising sortie rate actually costs.
	var d_out := _dist2d(entities.pos_x[u], entities.pos_z[u], t.x, t.z)
	var d_back := _recovery_dist_from(u, t.x, t.z)
	var rr := entities.range_remaining_m(u)
	# 3x the landing overhead: accelerating off the pad costs twice what
	# braking does (accel is half decel), and the landing costs one more.
	if rr < RESERVE * (d_out + d_back) + 3.0 * _landing_overhead_m(u):
		# A full tank that still fails the gate can never pass it: the world
		# changed under the order (the far recovery died). Stand down.
		if entities.fuel[u] >= entities.fuel_capacity[u] - 0.001:
			_note("%s: standing down, task out of reach from here"
				% entities.names[u])
			_tasks.erase(u)
		return
	_launch(u, t, true)


func _launch(u: int, t: Task, from_ground: bool) -> void:
	entities.sortie_state[u] = SimTypes.SortieState.OUTBOUND
	if from_ground:
		sorties_flown += 1
	t.stranded = false
	if t.kind == SimTypes.OrderKind.SORTIE_PATROL:
		t.leg = _nearest_orbit_leg(u, t.x, t.z, t.radius_m)
		var p := _orbit_point(t.x, t.z, t.radius_m, t.leg)
		_send(u, t, p.x, p.y)
	else:
		t.station_s = STRIKE_STATION_S
		t.leg = 0
		_send(u, t, t.x, t.z)


# ── outbound: transit at cruise, watching the fuel ───────────────────────────

func _step_outbound(u: int, t: Task, dt: float) -> void:
	_fly_altitude(u, _cruise_alt_for(u), dt)
	if _check_rtb(u, t):
		return
	var entry := Vector2(t.x, t.z)
	if t.kind == SimTypes.OrderKind.SORTIE_PATROL:
		entry = _orbit_point(t.x, t.z, t.radius_m, t.leg)
	var d := _dist2d(entities.pos_x[u], entities.pos_z[u], entry.x, entry.y)
	if d <= _arrive_reach(u, t):
		entities.sortie_state[u] = SimTypes.SortieState.ON_STATION
		return
	# The move order vanished under us (a stray STOP, an abandoned plan):
	# re-issue rather than hang in the air.
	if entities.has_dest[u] == 0:
		_send(u, t, entry.x, entry.y)


# ── on station: orbit, let fire control work, come home on the rule ──────────

func _step_station(u: int, t: Task, dt: float) -> void:
	_fly_altitude(u, _cruise_alt_for(u), dt)
	if _check_rtb(u, t):
		return
	if _winchester(u):
		var rec := _nearest_recovery(u)
		if rec >= 0:
			_begin_rtb(u, t, rec, "winchester")
			return
	if t.kind == SimTypes.OrderKind.SORTIE_STRIKE:
		t.station_s -= dt
		if t.station_s <= 0.0:
			var rec := _nearest_recovery(u)
			if rec >= 0:
				_begin_rtb(u, t, rec, "delivered")
				return
			# Nowhere to land: keep orbiting the target until fuel decides.
	var r := t.radius_m if t.kind == SimTypes.OrderKind.SORTIE_PATROL \
		else STRIKE_ORBIT_M
	var p := _orbit_point(t.x, t.z, r, t.leg)
	var d := _dist2d(entities.pos_x[u], entities.pos_z[u], p.x, p.y)
	if d <= _arrive_reach(u, t) or entities.has_dest[u] == 0:
		t.leg = (t.leg + 1) % ORBIT_POINTS
		var nxt := _orbit_point(t.x, t.z, r, t.leg)
		_send(u, t, nxt.x, nxt.y)


# ── RTB: home on the nearest surviving recovery, re-checked every step ───────

func _step_rtb(u: int, t: Task, dt: float) -> void:
	var rec := _nearest_recovery(u)
	if rec >= 0:
		_fly_altitude(u, _approach_alt(u, rec), dt)
	else:
		_fly_altitude(u, _cruise_alt_for(u), dt)
	if rec < 0:
		# docs/04 consequence 5, the dramatic half: every recovery point is
		# gone. Orbit here at cruise until the tank runs out; the economy's
		# run-dry rule then destroys the aircraft. No parking at altitude.
		if not t.stranded:
			t.stranded = true
			t.hold_x = entities.pos_x[u]
			t.hold_z = entities.pos_z[u]
			_note("%s: no recovery point survives -- stranded"
				% entities.names[u])
		var p := _orbit_point(t.hold_x, t.hold_z, 1000.0, t.leg)
		if _dist2d(entities.pos_x[u], entities.pos_z[u], p.x, p.y) \
				<= _arrive_reach(u, t) or entities.has_dest[u] == 0:
			t.leg = (t.leg + 1) % ORBIT_POINTS
			var nxt := _orbit_point(t.hold_x, t.hold_z, 1000.0, t.leg)
			_send(u, t, nxt.x, nxt.y)
		return
	if t.stranded:
		t.stranded = false
		_note("%s: recovery restored" % entities.names[u])
	if rec != entities.home_base[u]:
		# d_home recomputed to the NEXT nearest field the moment one is lost
		# -- or a nearer one appeared. Divert.
		if entities.home_base[u] >= 0:
			diverts += 1
			_note("%s: diverting to %s" % [entities.names[u],
				entities.names[rec]])
		entities.set_home_base(u, rec)
		_send(u, t, entities.pos_x[rec], entities.pos_z[rec])
	var d := _dist2d(entities.pos_x[u], entities.pos_z[u],
		entities.pos_x[rec], entities.pos_z[rec])
	if d <= APPROACH_RADIUS_M:
		entities.sortie_state[u] = SimTypes.SortieState.RECOVERING
		return
	# A moving recovery (a carrier) walks away from the point we ordered;
	# re-aim when the error grows past the touchdown radius.
	if entities.has_dest[u] == 0 or _dist2d(t.ordered_x, t.ordered_z,
			entities.pos_x[rec], entities.pos_z[rec]) > 200.0:
		_send(u, t, entities.pos_x[rec], entities.pos_z[rec])


# ── recovering: committed to the approach, descending ────────────────────────

func _step_recovering(u: int, t: Task, dt: float) -> void:
	var rec := entities.home_base[u]
	if rec < 0 or not _recovery_ok(u, rec):
		# The pad died on final. Back to RTB; the next step finds another
		# field or strands honestly.
		entities.sortie_state[u] = SimTypes.SortieState.RTB
		return
	var pad_y: float = entities.pos_y[rec] + PARK_ALT_M
	_fly_altitude(u, _approach_alt(u, rec), dt)
	var d := _dist2d(entities.pos_x[u], entities.pos_z[u],
		entities.pos_x[rec], entities.pos_z[rec])
	if d <= TOUCHDOWN_RADIUS_M \
			and absf(entities.pos_y[u] - pad_y) <= TOUCHDOWN_ALT_M:
		_touch_down(u, t, rec)
		return
	if entities.has_dest[u] == 0 and d > TOUCHDOWN_RADIUS_M:
		_send(u, t, entities.pos_x[rec], entities.pos_z[rec])


func _touch_down(u: int, t: Task, rec: int) -> void:
	entities.sortie_state[u] = SimTypes.SortieState.GROUNDED
	movement.order_stop(u)
	entities.vel_y[u] = 0.0
	recoveries += 1
	_note("%s: recovered at %s" % [entities.names[u], entities.names[rec]])
	if t.kind == SimTypes.OrderKind.SORTIE_STRIKE:
		# A strike is one launch. Delivered or driven home, landing ends it.
		_tasks.erase(u)
		return
	# A PATROL stands: refuel, rearm, and the launch gate relaunches the same
	# orbit. This is the Empire Earth loop.
	t.turnaround_s = TURNAROUND_S


# ═══════════════════════════════════════════════════════════════════════════
# THE RULE, AND RECOVERY GEOGRAPHY
# ═══════════════════════════════════════════════════════════════════════════

## The docs/04 trigger, verbatim. True when it fired (state is now RTB).
func _check_rtb(u: int, t: Task) -> bool:
	var rr := entities.range_remaining_m(u)
	if is_inf(rr):
		return false   # no tank modelled; nothing to ration
	var rec := _nearest_recovery(u)
	if rec < 0:
		return false   # nowhere to go; fly the task until dry
	var d := _dist2d(entities.pos_x[u], entities.pos_z[u],
		entities.pos_x[rec], entities.pos_z[rec])
	var overhead := _landing_overhead_m(u)
	if rr < RESERVE * (d + overhead):
		last_rtb[u] = {"range_m": rr, "d_home_m": d,
			"overhead_m": overhead, "reason": "fuel"}
		_begin_rtb(u, t, rec, "fuel")
		return true
	return false


## The kinematic allowance, in metres of cruise range: what coming home
## really costs beyond the straight-line distance. Two terms, both measured
## against SimMovement's real steering: braking for the pad at 2 x accel
## costs v^2 / (4 x accel), and the turn-around is a half-circle of radius
## v / turn_rate flown at speed. See the header.
func _landing_overhead_m(u: int) -> float:
	var a := maxf(entities.accel_ms2[u], 0.1)
	var v := entities.max_speed_ms[u]
	var w := maxf(entities.turn_rate_rads[u], 0.05)
	return v * v / (4.0 * a) + PI * v / w


func _begin_rtb(u: int, t: Task, rec: int, reason: String) -> void:
	entities.sortie_state[u] = SimTypes.SortieState.RTB
	entities.set_home_base(u, rec)
	if reason != "fuel":
		last_rtb[u] = {"range_m": entities.range_remaining_m(u),
			"d_home_m": _dist2d(entities.pos_x[u], entities.pos_z[u],
				entities.pos_x[rec], entities.pos_z[rec]),
			"reason": reason}
	_note("%s: RTB (%s) -> %s" % [entities.names[u], reason,
		entities.names[rec]])
	_send(u, t, entities.pos_x[rec], entities.pos_z[rec])


## Nearest operational friendly recovery unit for this aircraft, or -1.
## Ascending index scan with strict <, so ties break low -- deterministic.
func _nearest_recovery(u: int) -> int:
	var pads := _pads_for(u)
	var best := -1
	var best_d2 := INF
	var ux := entities.pos_x[u]
	var uz := entities.pos_z[u]
	for j in range(entities.count()):
		if entities.alive[j] == 0 or j == u:
			continue
		if entities.owner[j] != entities.owner[u]:
			continue
		var d := economy.def_of(j)
		if d == null or not pads.has(d.role):
			continue
		if not economy.is_operational(j):
			continue
		var dx := entities.pos_x[j] - ux
		var dz := entities.pos_z[j] - uz
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = j
	return best


## Distance from a POINT to that point's nearest recovery -- the return leg
## the launch gate and the feasibility check cost. 0.0 when none survives
## (the trip is then one-way and the caller knows it).
func _recovery_dist_from(u: int, x: float, z: float) -> float:
	var pads := _pads_for(u)
	var best := INF
	for j in range(entities.count()):
		if entities.alive[j] == 0 or j == u:
			continue
		if entities.owner[j] != entities.owner[u]:
			continue
		var d := economy.def_of(j)
		if d == null or not pads.has(d.role):
			continue
		if not economy.is_operational(j):
			continue
		best = minf(best, _dist2d(x, z, entities.pos_x[j], entities.pos_z[j]))
	return 0.0 if is_inf(best) else best


func _recovery_ok(u: int, j: int) -> bool:
	if not entities.is_alive(j):
		return false
	if entities.owner[j] != entities.owner[u]:
		return false
	var d := economy.def_of(j)
	if d == null or not _pads_for(u).has(d.role):
		return false
	return economy.is_operational(j)


## Which pad set this aircraft uses. The roster's built_by column already says
## who is rotary: everything a helipad produces recovers at one.
func _pads_for(u: int) -> Array[String]:
	return PADS_ROTARY if _is_rotary(u) else PADS_FIXED


func _is_rotary(u: int) -> bool:
	var d := economy.def_of(u)
	return d != null and d.built_by == "helipad"


## Pick (or repair) home_base: nearest recovery now. -1 when none exists.
func _ensure_home(u: int) -> void:
	var h := entities.home_base[u]
	if h >= 0 and _recovery_ok(u, h):
		return
	entities.set_home_base(u, _nearest_recovery(u))


# ═══════════════════════════════════════════════════════════════════════════
# FLIGHT MECHANICS
# ═══════════════════════════════════════════════════════════════════════════

## Vertical channel. Movement's _vertical_velocity() hands AIR units their own
## vel_y back untouched, so writing it here -- before the movement slot -- is
## the sanctioned way an aircraft climbs. Position itself still changes only
## in _integrate().
func _fly_altitude(u: int, desired_y: float, dt: float) -> void:
	var climb := CLIMB_ROTARY_MS if _is_rotary(u) else CLIMB_FIXED_MS
	entities.vel_y[u] = clampf((desired_y - entities.pos_y[u]) / maxf(dt, 0.001),
		-climb, climb)


## Desired altitude on the way in to a recovery: the glide slope, capped at
## cruise. At the touchdown radius it meets the pad.
func _approach_alt(u: int, rec: int) -> float:
	var d := _dist2d(entities.pos_x[u], entities.pos_z[u],
		entities.pos_x[rec], entities.pos_z[rec])
	var above := maxf(d - TOUCHDOWN_RADIUS_M, 0.0) * DESCENT_SLOPE
	return minf(entities.pos_y[rec] + PARK_ALT_M + above, _cruise_alt_for(u))


func _cruise_alt_for(u: int) -> float:
	var ground := 0.0
	if terrain != null:
		ground = maxf(terrain.ground_under(entities.pos_x[u],
			entities.pos_z[u]), 0.0)
	var alt := CRUISE_ALT_ROTARY_M if _is_rotary(u) else CRUISE_ALT_FIXED_M
	return ground + alt


## Push a waypoint through the same movement layer a player's click uses.
func _send(u: int, t: Task, x: float, z: float) -> void:
	t.ordered_x = x
	t.ordered_z = z
	movement.order_move(u, x, z)


## Waypoint k of an orbit. sin/cos of fixed fractions of TAU -- deterministic.
func _orbit_point(cx: float, cz: float, r: float, k: int) -> Vector2:
	var a := TAU * float(k) / float(ORBIT_POINTS)
	return Vector2(cx + sin(a) * r, cz + cos(a) * r)


func _nearest_orbit_leg(u: int, cx: float, cz: float, r: float) -> int:
	var best := 0
	var best_d := INF
	for k in range(ORBIT_POINTS):
		var p := _orbit_point(cx, cz, r, k)
		var d := _dist2d(entities.pos_x[u], entities.pos_z[u], p.x, p.y)
		if d < best_d:
			best_d = d
			best = k
	return best


## "Close enough" to a waypoint. Generous with speed and with orbit size, so a
## 500 m/s fighter does not orbit its own overshoot; never below the movement
## layer's own arrive radius.
func _arrive_reach(u: int, t: Task) -> float:
	var r := t.radius_m if t.kind == SimTypes.OrderKind.SORTIE_PATROL \
		else STRIKE_ORBIT_M
	return maxf(maxf(50.0, r * 0.12), entities.max_speed_ms[u] * 0.15)


# ── loadout ──────────────────────────────────────────────────────────────────

## All finite magazines empty. Unlimited mounts (-1) never winchester, and an
## unarmed aircraft has nothing to run out of.
func _winchester(u: int) -> bool:
	if weapons == null:
		return false
	var mounts := weapons.mounts_of(u)
	if mounts.is_empty():
		return false
	var any_finite := false
	for m in mounts:
		if m.rounds < 0:
			return false
		if m.rounds > 0:
			return false
		any_finite = true
	return any_finite


func _snapshot_loadout(u: int, t: Task) -> void:
	if weapons == null or not t.full_rounds.is_empty():
		return
	for m in weapons.mounts_of(u):
		t.full_rounds.append(int(m.rounds))


## Turnaround rearm: restore the loadout the aircraft first flew with,
## provided it is actually sitting at an operational pad.
func _rearm(u: int, t: Task) -> void:
	if weapons == null or t.full_rounds.is_empty():
		return
	var rec := entities.home_base[u]
	if rec < 0 or not _recovery_ok(u, rec):
		return
	if _dist2d(entities.pos_x[u], entities.pos_z[u],
			entities.pos_x[rec], entities.pos_z[rec]) > APPROACH_RADIUS_M:
		return
	var mounts := weapons.mounts_of(u)
	for k in range(mini(mounts.size(), t.full_rounds.size())):
		mounts[k].rounds = int(t.full_rounds[k])


# ═══════════════════════════════════════════════════════════════════════════
# INTROSPECTION -- for the HUD and the tests. Read-only.
# ═══════════════════════════════════════════════════════════════════════════

func has_task(unit: int) -> bool:
	return _tasks.has(unit)


## A copy of the standing order, or {} -- nothing here can mutate the task.
func task_of(unit: int) -> Dictionary:
	if not _tasks.has(unit):
		return {}
	var t: Task = _tasks[unit]
	return {"kind": t.kind, "x": t.x, "z": t.z, "radius_m": t.radius_m,
		"turnaround_s": t.turnaround_s, "stranded": t.stranded}


func state_name(unit: int) -> String:
	return SimTypes.sortie_state_name(entities.sortie_state[unit])


func _dist2d(ax: float, az: float, bx: float, bz: float) -> float:
	var dx := bx - ax
	var dz := bz - az
	return sqrt(dx * dx + dz * dz)


func _note(line: String) -> void:
	log.append(line)
	if log.size() > 200:
		log = log.slice(log.size() - 200)


func describe() -> String:
	return "sorties %d  recoveries %d  diverts %d  standing %d" % [
		sorties_flown, recoveries, diverts, _tasks.size()]


# ── SAVE / LOAD (SimSave) ────────────────────────────────────────────────────
# The standing orders (with their orbit legs, station clocks, turnaround
# timers and loadout snapshots), last_rtb (the docs/04 margin evidence the
# tests read), and the counters. The aircraft's own sortie_state and home_base
# ride SimEntities. The text log is cosmetic and dropped.

func to_dict() -> Dictionary:
	var tasks := {}
	var units: Array = _tasks.keys()
	units.sort()
	for u in units:
		tasks[str(u)] = SimSave.enc_props(_tasks[u])
	var rtb := {}
	for u in last_rtb:
		var e: Dictionary = last_rtb[u]
		var row := {}
		for k in e:
			row[String(k)] = SimSave.enc_float(e[k]) if e[k] is float else e[k]
		rtb[str(u)] = row
	return {
		"tasks": tasks,
		"last_rtb": rtb,
		"counters": [sorties_flown, recoveries, diverts],
	}


func from_dict(d: Dictionary) -> void:
	_tasks.clear()
	for k in (d["tasks"] as Dictionary):
		var t := Task.new()
		SimSave.dec_props(t, d["tasks"][k])
		_tasks[int(String(k))] = t
	last_rtb.clear()
	for k in (d["last_rtb"] as Dictionary):
		var row := {}
		var e: Dictionary = d["last_rtb"][k]
		for rk in e:
			row[String(rk)] = SimSave.dec_float(e[rk]) if not (e[rk] is String) \
				else String(e[rk])
		last_rtb[int(String(k))] = row
	var c: Array = d["counters"]
	sorties_flown = int(c[0])
	recoveries = int(c[1])
	diverts = int(c[2])
