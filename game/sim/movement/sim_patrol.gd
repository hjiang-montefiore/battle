class_name SimPatrol
extends RefCounted
## Slot 3.6: ground and naval patrol loops. OrderKind.PATROL lands here.
##
## A PATROL order takes the unit's position AT ORDER TIME plus the clicked
## point list and loops through them forever: A -> B -> ... -> A -> B. Every
## leg is issued through SimMovement.order_move() -- the exact call a player's
## right-click makes -- so this layer never writes a velocity, a heading or a
## position. Its entire output is move orders and one order_stop().
##
## ── WHAT PATROL MEANS FOR COMBAT AND SENSING ────────────────────────────────
## A patrolling unit is the fire-control layer's customer. SimFireControl
## auto-assigns targets to every armed unit with no movement gating at all,
## and SimWeaponCycle fires while a unit moves -- so a patroller engages
## whatever its own faction's picture shows en route with NO help from this
## file. What this file adds is the pause: the tick after
## SimWeaponCycle.is_engaging(unit) goes true -- whether fire control set it
## or an explicit ATTACK_TRACK did -- the loop PAUSES: one order_stop(), and
## the unit halts to fight. When the engagement ends (the track went cold and
## was dropped, the target died and its track decayed, fire control released
## the unit on hold-fire, or something called disengage()), the loop RESUMES
## from the NEAREST leg point, nearest by squared distance with ties broken by
## LOWEST leg index. Sensing needs nothing from patrol: the solver reads
## positions and emissions, and a patroller is just a mover.
##
## ── AIRCRAFT ARE REJECTED, NOT CONVERTED ────────────────────────────────────
## Aircraft patrol is a SORTIE (docs/04): it needs a home base, an orbit
## radius and the RTB fuel rule, all of which belong to the sortie system.
## order_patrol() on a Category.AIR unit returns false, so the command is
## counted REJECTED -- converting silently would need a radius and a recovery
## point this order does not carry. The UI's gesture layer should issue
## SORTIE_PATROL for air units.
##
## ── HOW A PATROL ENDS ───────────────────────────────────────────────────────
## The spine's contract: a patrol "clears on any new order". Patrol issues
## exactly ONE un-queued move at a time and remembers where it sent the unit,
## so anything that disturbs that picture is a foreign order and cancels the
## loop:
##   - a foreign MOVE/ATTACK_MOVE replaces the queue: the destination no
##     longer matches the leg           -> cancelled
##   - a foreign queued move appends: order_count() > 1  -> cancelled
##   - a foreign STOP/HOLD empties the queue AWAY from the leg -> cancelled
##   - the planner abandons an unreachable leg (movement clears the queue
##     mid-route)                       -> cancelled, matching movement's own
##     "abandoning the order is the honest outcome"
##   - a new PATROL simply replaces the old loop
## The one drift that is NOT foreign: SimMovement._replan() may amend a goal
## to the nearest standable cell (last_goal_relocated). A destination within
## ADOPT_TOLERANCE_M of the issued leg is adopted as the leg; farther is a
## foreign order.
##
## ── SUSPENSION, NOT LOSS ────────────────────────────────────────────────────
## can_move() false -- carried aboard a transport, deploying, mobility-killed,
## dry tanks -- SUSPENDS the loop rather than ending it, mirroring the spine's
## "movement order queues survive boarding and resume on unload/undeploy/
## refuel". When mobility returns the loop resumes from the nearest leg.
##
## ── DETERMINISM ─────────────────────────────────────────────────────────────
## Patrolling units are stepped in ascending entity index (keys sorted every
## step, exactly like SimFireControl and SimWeaponCycle). No rng, no clock,
## no hash-order iteration. Internal cursors are derived state: every output
## lands in fields state_hash() already covers (dest_*, has_dest, path, vel).

## Movement pops a leg order within arrive_radius_m (6 m) of the point, or
## within crowd_arrive_radius_m (30 m) when neighbours block the last metres.
## A queue that emptied INSIDE this ring is an arrival; one that emptied
## farther out was stopped or abandoned, and the patrol cancels.
const ARRIVE_SLACK_M := 2.0

## How far the live destination may drift from the issued leg before it stops
## being "the planner relocated my goal to standable ground" and becomes "a
## foreign order replaced it". Comfortably above a cell-snap, comfortably
## below any deliberate move.
const ADOPT_TOLERANCE_M := 64.0

enum State {
	ACTIVE = 0,     ## walking the loop
	ENGAGED = 1,    ## halted; the weapon cycle is fighting. Loop paused
	SUSPENDED = 2,  ## cannot move (carried / deploying / m-kill / dry). Loop kept
}


var entities: SimEntities
var movement: SimMovement
## The pause trigger. Optional so a bare movement-only world still patrols;
## with no weapon cycle there is nothing to pause for.
var weapons: SimWeaponCycle = null

# Parallel per-unit records, keyed by entity index. Dictionaries, not arrays:
# a handful of units patrol at a time, and this is the same shape the weapon
# cycle and fire control already use for their side tables. Iteration is
# ALWAYS over sorted keys.
var _points: Dictionary = {}   ## unit -> PackedFloat32Array [x0,z0,...]; [0]=origin
var _cursor: Dictionary = {}   ## unit -> leg index currently being walked
var _state: Dictionary = {}    ## unit -> State
var _tx: Dictionary = {}       ## unit -> x the live leg order steers at
var _tz: Dictionary = {}       ## unit -> z
var _live: Dictionary = {}     ## unit -> bool: our order stands in the queue

var patrols_started: int = 0
var patrols_cancelled: int = 0
var legs_completed: int = 0
## A circuit completes on ARRIVAL back at leg 0, the point the unit stood on
## when the order was given.
var circuits_completed: int = 0
var pauses: int = 0
var resumes: int = 0


func _init(store: SimEntities, movement_ref: SimMovement,
		weapon_cycle: SimWeaponCycle = null) -> void:
	entities = store
	movement = movement_ref
	weapons = weapon_cycle


## Build a patrol system from a world's own parts and install it in the slot
## the spine left. The one-line wiring a match or a test calls:
##     SimPatrol.install(world)
static func install(world: SimWorld) -> SimPatrol:
	var p := SimPatrol.new(world.entities, world.movement, world.weapons)
	world.patrol_system = p
	return p


# ═══════════════════════════════════════════════════════════════════════════
# ORDER INTAKE -- SimWorld._execute_command() routes OrderKind.PATROL here
# ═══════════════════════════════════════════════════════════════════════════

## Start a patrol loop: the unit's current position, then every clicked point,
## looped forever. `p_points` is flat [x0, z0, x1, z1, ...] world metres; one
## point is the minimal A->B->A loop. Returns false -- which SimWorld counts
## as a REJECTED order -- for a dead unit, a structure, an aircraft (sortie
## territory, see the header), an immobile-by-design unit, or a malformed
## point list. A unit that cannot move RIGHT NOW (carried, deployed, dry) is
## accepted and suspended: the loop begins when mobility returns.
func order_patrol(unit: int, p_points: PackedFloat32Array) -> bool:
	if unit < 0 or unit >= entities.count():
		return false
	if entities.alive[unit] == 0:
		return false
	if entities.is_structure[unit] == 1:
		return false
	if entities.category[unit] == SimTypes.Category.AIR:
		return false
	if entities.max_speed_ms[unit] <= 0.0:
		return false
	if p_points.size() < 2 or p_points.size() % 2 != 0:
		return false

	var route := PackedFloat32Array()
	route.append(entities.pos_x[unit])
	route.append(entities.pos_z[unit])
	route.append_array(p_points)

	_points[unit] = route
	_cursor[unit] = 0
	_state[unit] = State.ACTIVE
	_tx[unit] = route[0]
	_tz[unit] = route[1]
	_live[unit] = false
	patrols_started += 1
	# Head for the first CLICKED point; leg 0 is the origin the loop closes on.
	_begin_leg(unit, 1)
	return true


## End a unit's patrol. `halt` also cancels the leg order patrol itself put in
## the movement queue (a UI "stop patrolling" gesture wants that); internal
## cancellation on a foreign order never halts, because the foreign order now
## owns the queue. Returns false if the unit was not patrolling.
func cancel(unit: int, halt := true) -> bool:
	if not _points.has(unit):
		return false
	var was_live: bool = _live.get(unit, false)
	_drop(unit)
	if halt and was_live and entities.is_alive(unit):
		movement.order_stop(unit)
	return true


# ═══════════════════════════════════════════════════════════════════════════
# QUERIES -- the UI hooks (loop overlay, patrol badge)
# ═══════════════════════════════════════════════════════════════════════════

func is_patrolling(unit: int) -> bool:
	return _points.has(unit)


## State.* for a patroller, -1 otherwise.
func patrol_state(unit: int) -> int:
	return _state.get(unit, -1)


## Index of the leg being walked (0 = the origin point), -1 if not patrolling.
func leg_of(unit: int) -> int:
	return _cursor.get(unit, -1)


## The loop as flat [x0, z0, ...], origin first. A copy; safe to hand to a
## renderer.
func points_of(unit: int) -> PackedFloat32Array:
	if not _points.has(unit):
		return PackedFloat32Array()
	return (_points[unit] as PackedFloat32Array).duplicate()


func patrol_count() -> int:
	return _points.size()


func is_implemented() -> bool:
	return true


func describe() -> String:
	return "patrol: %d looping, %d started, %d cancelled, %d legs, %d circuits, %d pauses" % [
		_points.size(), patrols_started, patrols_cancelled,
		legs_completed, circuits_completed, pauses]


# ── SAVE / LOAD (SimSave) ────────────────────────────────────────────────────
# The loops, the cursors, the pause states, and which leg order is live. All
# keyed by entity index; the leg's live destination itself rides SimEntities.

func to_dict() -> Dictionary:
	var pts := {}
	for u in _points:
		pts[str(u)] = {"__pf32": SimSave.b64_f32(_points[u])}
	return {
		"points": pts,
		"cursor": SimSave.enc_ii(_cursor),
		"state": SimSave.enc_ii(_state),
		"tx": SimSave.enc_if(_tx),
		"tz": SimSave.enc_if(_tz),
		"live": SimSave.enc_ib(_live),
		"counters": [patrols_started, patrols_cancelled, legs_completed,
			circuits_completed, pauses, resumes],
	}


func from_dict(d: Dictionary) -> void:
	_points.clear()
	for k in (d["points"] as Dictionary):
		_points[int(String(k))] = SimSave.un_f32(String(d["points"][k]["__pf32"]))
	_cursor = SimSave.dec_ii(d["cursor"])
	_state = SimSave.dec_ii(d["state"])
	_tx = SimSave.dec_if(d["tx"])
	_tz = SimSave.dec_if(d["tz"])
	_live = SimSave.dec_ib(d["live"])
	var c: Array = d["counters"]
	patrols_started = int(c[0]); patrols_cancelled = int(c[1])
	legs_completed = int(c[2]); circuits_completed = int(c[3])
	pauses = int(c[4]); resumes = int(c[5])


# ═══════════════════════════════════════════════════════════════════════════
# THE TICK SLOT -- SimWorld._patrol_slot(), between transport and sortie
# ═══════════════════════════════════════════════════════════════════════════

func step(_dt: float) -> void:
	if _points.is_empty():
		return
	var units: Array = _points.keys()
	units.sort()
	for u in units:
		_step_unit(u)


func _step_unit(u: int) -> void:
	if entities.alive[u] == 0:
		_drop(u)
		return

	# ── suspension: carried / deploying / mobility-killed / dry ─────────────
	# The loop survives; the movement layer likewise keeps its orders through
	# mobility loss. Note the check comes BEFORE the engagement check: a unit
	# that is aboard a transport cannot be halted or resumed, whatever its
	# weapon cycle thinks.
	if not entities.can_move(u):
		_state[u] = State.SUSPENDED
		return

	# ── the pause: the weapon cycle is fighting ─────────────────────────────
	if weapons != null and weapons.is_engaging(u):
		if int(_state[u]) != State.ENGAGED:
			_state[u] = State.ENGAGED
			_live[u] = false
			pauses += 1
			# Halt where we stand; the turret does the rest. This is the one
			# non-move order patrol ever issues.
			movement.order_stop(u)
		elif movement.order_count(u) > 0 or entities.has_dest[u] == 1:
			# Paused units hold no movement orders -- one appearing now can
			# only be foreign. The player retasked a fighting unit; the
			# patrol is over.
			_drop(u)
		return

	# ── the resume: engagement over, or mobility back ───────────────────────
	if int(_state[u]) != State.ACTIVE:
		if int(_state[u]) == State.ENGAGED \
				and (movement.order_count(u) > 0 or entities.has_dest[u] == 1):
			# A foreign order arrived on the same tick the engagement ended.
			# It wins; see the cancellation contract in the header.
			_drop(u)
			return
		_resume(u)
		return

	# ── ACTIVE: is the live order still ours, and did a leg complete? ───────
	var oc := movement.order_count(u)
	if oc == 0:
		if entities.has_dest[u] == 1:
			# A destination with no order behind it: something outside the
			# order path wrote intent directly. Not ours; not a patrol.
			_drop(u)
			return
		if not bool(_live[u]):
			# Our issue attempt never took (it cannot, while can_move holds,
			# but stay defensive rather than wedge). Try again.
			_resume(u)
			return
		# The leg order was consumed. Inside the arrival ring it is a
		# completed leg; outside, a foreign STOP or an abandoned unreachable
		# route ended it, and the patrol ends with it.
		if _near_leg(u):
			_advance(u)
		else:
			_drop(u)
		return
	if oc != 1:
		# Patrol issues exactly one un-queued order; a second in the queue is
		# a foreign shift-click.
		_drop(u)
		return
	var dx := float(entities.dest_x[u]) - float(_tx[u])
	var dz := float(entities.dest_z[u]) - float(_tz[u])
	if dx * dx + dz * dz > ADOPT_TOLERANCE_M * ADOPT_TOLERANCE_M:
		# The queue's one order no longer points at our leg: a foreign MOVE
		# replaced it.
		_drop(u)
		return
	# Small drift is the planner relocating the goal to standable ground.
	# Adopt it so arrival is measured against where the unit can actually
	# stand; the ORIGINAL leg point stays in the loop for later circuits.
	_tx[u] = entities.dest_x[u]
	_tz[u] = entities.dest_z[u]


# ═══════════════════════════════════════════════════════════════════════════
# INTERNALS
# ═══════════════════════════════════════════════════════════════════════════

func _begin_leg(u: int, leg: int) -> void:
	var route := _points[u] as PackedFloat32Array
	var n := route.size() / 2
	leg = leg % n
	_cursor[u] = leg
	_tx[u] = route[leg * 2]
	_tz[u] = route[leg * 2 + 1]
	_state[u] = State.ACTIVE
	if movement.order_move(u, float(_tx[u]), float(_tz[u])):
		_live[u] = true
	else:
		# Cannot take a move order right now; hold the loop and retry from
		# _resume() next slot.
		_live[u] = false
		_state[u] = State.SUSPENDED


## Arrival at the current leg: count it, and walk on to the next.
func _advance(u: int) -> void:
	legs_completed += 1
	if int(_cursor[u]) == 0:
		circuits_completed += 1
	_begin_leg(u, int(_cursor[u]) + 1)


## Rejoin the loop at the NEAREST leg point -- squared distance, ties to the
## LOWEST index. Deterministic, and tactically right: a unit dragged half a
## leg away by a fight walks back to the closest part of its beat rather than
## retracing the whole loop.
func _resume(u: int) -> void:
	var route := _points[u] as PackedFloat32Array
	var n := route.size() / 2
	var px := entities.pos_x[u]
	var pz := entities.pos_z[u]
	var best := 0
	var best_d2 := INF
	for k in range(n):
		var dx := route[k * 2] - px
		var dz := route[k * 2 + 1] - pz
		var d2 := dx * dx + dz * dz
		if d2 < best_d2:
			best_d2 = d2
			best = k
	resumes += 1
	_begin_leg(u, best)


func _near_leg(u: int) -> bool:
	var dx := entities.pos_x[u] - float(_tx[u])
	var dz := entities.pos_z[u] - float(_tz[u])
	var tol := movement.crowd_arrive_radius_m + movement.arrive_radius_m \
		+ ARRIVE_SLACK_M
	return dx * dx + dz * dz <= tol * tol


func _drop(u: int) -> void:
	_points.erase(u)
	_cursor.erase(u)
	_state.erase(u)
	_tx.erase(u)
	_tz.erase(u)
	_live.erase(u)
	patrols_cancelled += 1
