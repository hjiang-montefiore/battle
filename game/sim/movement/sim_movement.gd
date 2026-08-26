class_name SimMovement
extends RefCounted
## Orders, path planning and steering. The whole of it lives in the sim, not in
## the scene -- proving_ground.gd is a viewer and calls order_move_group()
## instead of placing units on a formation grid itself.
##
## OWNERSHIP: the only writer of vel_x/vel_y/vel_z, heading_rad, speed_ms,
## move_state, dest_*, has_dest and the path arrays. It MUST NOT write pos_* --
## SimWorld._integrate() owns position, and it runs immediately after this slot.
## Writing velocity and letting one place integrate it is what keeps the tick
## order meaningful and the replay hash stable.
##
## DETERMINISM: docs/06 forbids Godot physics and randf(). Nothing here draws
## from `rng` at all -- steering is a pure function of last tick's state -- and
## the A* open set is a binary heap whose tie-break is LOWEST CELL INDEX, never
## whichever neighbour a hash set happened to yield. The neighbour order is a
## fixed constant array. Two runs from one seed produce identical paths.
##
## SCOPE, honestly: this layer owns WHERE a unit goes and HOW it gets there. It
## does not shoot. ATTACK_MOVE is therefore half a feature here -- it advances
## at combat power and flags itself so the weapon cycle can pick it up, but the
## "stop and engage on contact" half belongs to the combat layer, which does not
## exist yet. See is_attack_moving().


## Queued orders per unit. Flat, fixed-capacity, indexed by unit -- units are
## indices (docs/06 data layout) and an Array of order objects per unit would be
## exactly the per-unit object the SoA rule exists to prevent.
const MAX_ORDERS := 8

## What a queued order is. Deliberately NOT SimTypes.OrderKind: that enum is the
## command vocabulary crossing the sim boundary, this one is the movement
## layer's internal queue, and only two of its members are destinations.
enum OrderType { NONE = 0, MOVE = 1, ATTACK_MOVE = 2 }


var entities: SimEntities
var terrain: SimTerrain = null
var rng: SimRng

## How close, in metres, counts as having reached a waypoint. Larger than it
## looks on purpose: a tight radius makes a unit oscillate around the point it
## can never exactly hit at 20 Hz.
var arrive_radius_m: float = 6.0
## Replans attempted per tick, across all units. Pathfinding is the second most
## expensive thing in an RTS after the sensor solve; budgeting it here means a
## hundred simultaneous move orders degrade into a queue rather than a stall.
var replan_budget_per_tick: int = 8

# ── mobility model ──────────────────────────────────────────────────────────
## Steepest grade (rise/run) a tracked vehicle will attempt. 0.60 is about 31
## degrees, which is the usual quoted side-slope/gradient limit for an MBT.
var max_grade: float = 0.60
## Grade at which the speed penalty starts. Below this the ground is "going".
var gentle_grade: float = 0.08
## Fraction of top speed left at the steepest passable grade.
var min_grade_speed: float = 0.25
## Ships slow in shoal water rather than being forbidden it outright.
var shoal_depth_m: float = 15.0

# ── crowding ────────────────────────────────────────────────────────────────
var separation_enabled: bool = true
var separation_radius_m: float = 14.0
## Cap on the sideways push, as a fraction of the unit's top speed. Kept small:
## separation is a nudge that stops units occupying one point, not a second
## navigator competing with the path.
var separation_strength: float = 0.35

## Ordering a whole company to one point is the commonest order in an RTS, and
## only one of them can stand on it. A unit that has loitered this close to its
## destination for this long, with neighbours pressed against it, has arrived --
## the point is occupied by its own side. Without this they orbit the objective
## for the rest of the match at walking pace, which is the single most
## recognisable pathfinding failure in the genre.
var crowd_arrive_radius_m: float = 30.0
var crowd_arrive_ticks: int = 20

## Ground and surface units are held on the surface by writing vel_y, never by
## writing pos_y -- position stays _integrate()'s alone.
var terrain_follow: bool = true

# ── planner limits ──────────────────────────────────────────────────────────
## Cells the A* may expand before it gives up and returns the best partial route
## it found. A theatre is 320x320 cells; an unbounded search across one of those
## is a frame-long stall, and a partial route that is replanned on arrival is
## what hierarchical pathfinding does anyway.
var max_search_cells: int = 4000
## Total A* expansions all plans on one tick may share between them. Set equal to
## max_search_cells on purpose: it means AT MOST one full-budget search lands in
## any one tick, whatever the replan budget allows, so the worst tick costs one
## long plan and not eight. Anything past the pool is deferred to the next tick.
##
## Do not set it BELOW max_search_cells without understanding the consequence: a
## search cut short by the pool comes back as a partial route, and a genuinely
## unreachable destination then looks like a slow one and is retried forever
## instead of being abandoned.
var expansion_budget_per_tick: int = 4000
## Ticks to wait before retrying a plan that failed, and how many failures
## before the order is abandoned as unreachable.
var replan_cooldown_ticks: int = 10
var max_plan_failures: int = 3
## Ticks a unit may spend under orders while making no progress before it is
## forced to replan.
var stall_ticks: int = 40

# ── telemetry, for tests and the debug HUD ──────────────────────────────────
var plans_run: int = 0
var plans_failed: int = 0
var plans_partial: int = 0
var plans_truncated: int = 0
var plans_deferred: int = 0
var orders_issued: int = 0
var orders_completed: int = 0
var orders_abandoned: int = 0
var last_expansions: int = 0
## Where the last plan_path() actually ended up aiming, and whether it had to be
## moved. A click in the sea becomes an order to the nearest shore, and the ORDER
## is amended to match -- otherwise the unit reaches the beach and never
## "arrives", because its recorded destination is still out in the water.
var last_goal_relocated: bool = false
var last_goal_x: float = 0.0
var last_goal_z: float = 0.0

# ── per-unit state, parallel arrays indexed by entity index ─────────────────
var _q_kind := PackedInt32Array()      ## stride MAX_ORDERS
var _q_x := PackedFloat32Array()       ## stride MAX_ORDERS
var _q_z := PackedFloat32Array()       ## stride MAX_ORDERS
var _q_len := PackedInt32Array()
var _needs_replan := PackedInt32Array()
var _cooldown := PackedInt32Array()
var _fail := PackedInt32Array()
var _stall := PackedInt32Array()
var _hold := PackedInt32Array()
var _near_dest := PackedInt32Array()   ## consecutive ticks loitering at the goal
## 1 when THIS layer put the unit into MoveState.COMBAT, so that arriving
## restores IDLE without clobbering a COMBAT the player set by hand.
var _combat_set := PackedInt32Array()

# ── terrain memo. Static ground, so one answer per cell per category ───────
var _cache_category: int = -1
var _pass_cache := PackedByteArray()     ## 0 unknown, 1 passable, 2 blocked
var _speed_cache := PackedFloat32Array() ## -1 unknown, else 0..1 going

# ── A* scratch, reused between plans so a search does not allocate ──────────
##
## Flat arrays with a GENERATION STAMP rather than Dictionaries. Three reasons,
## in order of importance: a Dictionary lookup in GDScript costs several times an
## array index and the inner loop runs a quarter of a million times on a long
## plan; a stamp means a new search costs nothing to start, where clearing a
## hundred thousand cells would dominate a short one; and an array has no hash
## order to accidentally depend on, which is the determinism rule in docs/06.
var _open_f := PackedFloat64Array()
var _open_c := PackedInt32Array()
var _gen: int = 0
var _stamp := PackedInt32Array()        ## generation this cell's g was written
var _gscore := PackedFloat32Array()
var _parent := PackedInt32Array()
var _closed_stamp := PackedInt32Array()
## Expansions left in this tick's shared pool. Budgeting plan COUNT alone is not
## enough: eight cross-theatre searches on one tick is eight times the worst
## case, and a frame does not care how many plans it was.
var _pool: int = 0
var _in_step: bool = false
## True when the last plan returned nothing because the tick's expansion pool was
## already spent. That is NOT the same as "no route exists", and conflating the
## two is a real bug with a very confusing signature: forty units ordered at once
## spend the pool on the first eight, the other thirty-two get an empty route,
## count it as a failure three times over, and abandon a perfectly walkable
## order. Deferred plans are simply retried.
var _last_plan_deferred: bool = false

## Neighbour offsets in a FIXED order. The order is part of the determinism
## contract: with equal f the heap already tie-breaks on cell index, and a fixed
## expansion order means two runs push in the same sequence as well.
const NEIGHBOURS := [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
	Vector2i(-1, 0), Vector2i(1, 0),
	Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1),
]
const SQRT2 := 1.4142135623730951


func _init(store: SimEntities, terrain_ref: SimTerrain = null,
		seeded: SimRng = null) -> void:
	entities = store
	terrain = terrain_ref
	rng = seeded if seeded != null else SimRng.new(0x4D0E)


func set_terrain(t: SimTerrain) -> void:
	terrain = t
	# The memo describes the old ground. Drop it.
	_cache_category = -1
	_pass_cache.resize(0)
	_speed_cache.resize(0)


# ═══════════════════════════════════════════════════════════════════════════
# ORDERS
#
# One code path. The human player's mouse reaches these through
# SimCommandQueue -> SimWorld._command_slot() -> order_move(); the AI reaches
# them through SimAiWorldView.order_move() -> the same queue -> the same
# function. Neither can express an order the other cannot.
# ═══════════════════════════════════════════════════════════════════════════

## Order a unit to a world point, in METRES. Records the order and requests a
## replan; it does not plan inline, so a hundred units ordered on one frame
## spread their planning across the replan budget.
##
## `queued` appends behind the orders already outstanding (shift-click); the
## default replaces them, which is what a bare right-click means.
## Returns false if the unit cannot move at all (dead, mobility-killed, dry,
## or a structure), or if its order queue is full.
func order_move(unit: int, x_m: float, z_m: float, queued := false) -> bool:
	return _enqueue(unit, OrderType.MOVE, x_m, z_m, queued)


## Advance to a point at combat power, ready to fight.
##
## HONESTY: the movement half of this is real -- the unit travels in
## MoveState.COMBAT and is_attack_moving() reports it. The "halt and engage what
## you meet" half belongs to the weapon cycle, which is not built, so today an
## attack-move differs from a move only in burn rate and in the flag.
## It is also not yet reachable through SimCommandQueue: SimTypes.OrderKind has
## no ATTACK_MOVE member, and that enum is shared, not this layer's to extend.
func order_attack_move(unit: int, x_m: float, z_m: float, queued := false) -> bool:
	return _enqueue(unit, OrderType.ATTACK_MOVE, x_m, z_m, queued)


## Cancel movement. Idempotent. Does not put the unit into hold.
func order_stop(unit: int) -> void:
	if not _valid(unit):
		return
	_ensure_capacity()
	_clear_queue(unit)
	_release_combat(unit)
	entities.clear_destination(unit)
	_needs_replan[unit] = 0
	_stall[unit] = 0


## Stop, and refuse to be repositioned until ordered again. The distinction from
## STOP matters the moment there is a combat layer: a HOLDing unit shoots but
## does not chase.
func order_hold(unit: int) -> void:
	if not _valid(unit):
		return
	order_stop(unit)
	_hold[unit] = 1


func is_holding(unit: int) -> bool:
	if not _valid(unit) or unit >= _hold.size():
		return false
	return _hold[unit] == 1


## True while the unit is executing an ATTACK_MOVE. The weapon cycle reads this
## to decide whether a unit under orders may break off and engage.
func is_attack_moving(unit: int) -> bool:
	if not _valid(unit) or unit >= _q_len.size():
		return false
	return _q_len[unit] > 0 and _q_kind[unit * MAX_ORDERS] == OrderType.ATTACK_MOVE


## How many orders are outstanding, the one in progress included.
func order_count(unit: int) -> int:
	if not _valid(unit) or unit >= _q_len.size():
		return 0
	return _q_len[unit]


## Order a whole selection to one point, spread over a formation. The ONLY
## sanctioned way to move a group: it is where the pile-on-one-point problem is
## solved, and it is deterministic because formation_slots() is.
## Returns how many units accepted the order.
func order_move_group(units: PackedInt32Array, x_m: float, z_m: float,
		spacing_m: float = 14.0, queued := false,
		attack_move := false) -> int:
	var slots := formation_slots(units, x_m, z_m, spacing_m)
	var issued := 0
	for k in range(units.size()):
		var u := units[k]
		var sx := slots[k * 2]
		var sz := slots[k * 2 + 1]
		var ok := order_attack_move(u, sx, sz, queued) if attack_move \
			else order_move(u, sx, sz, queued)
		if ok:
			issued += 1
	return issued


func _enqueue(unit: int, kind: int, x_m: float, z_m: float, queued: bool) -> bool:
	if not _valid(unit):
		return false
	if not entities.can_move(unit):
		return false
	_ensure_capacity()
	_hold[unit] = 0
	if not queued:
		_clear_queue(unit)
	if _q_len[unit] >= MAX_ORDERS:
		return false
	var base := unit * MAX_ORDERS + _q_len[unit]
	_q_kind[base] = kind
	_q_x[base] = x_m
	_q_z[base] = z_m
	_q_len[unit] += 1
	orders_issued += 1
	if _q_len[unit] == 1:
		_begin_front(unit)
	return true


## Make the order at the head of the queue the live one.
func _begin_front(unit: int) -> void:
	if _q_len[unit] <= 0:
		_release_combat(unit)
		entities.clear_destination(unit)
		return
	var base := unit * MAX_ORDERS
	entities.set_destination(unit, _q_x[base], _q_z[base])
	entities.path_len[unit] = 0
	entities.path_cursor[unit] = 0
	_needs_replan[unit] = 1
	_cooldown[unit] = 0
	_fail[unit] = 0
	_stall[unit] = 0
	if _q_kind[base] == OrderType.ATTACK_MOVE:
		if entities.move_state[unit] != SimTypes.MoveState.COMBAT:
			entities.move_state[unit] = SimTypes.MoveState.COMBAT
			_combat_set[unit] = 1


## Retire the head order and start the next, if any.
func _pop_front(unit: int) -> void:
	if _q_len[unit] <= 0:
		return
	var base := unit * MAX_ORDERS
	for k in range(1, _q_len[unit]):
		_q_kind[base + k - 1] = _q_kind[base + k]
		_q_x[base + k - 1] = _q_x[base + k]
		_q_z[base + k - 1] = _q_z[base + k]
	_q_len[unit] -= 1
	orders_completed += 1
	if _q_len[unit] > 0:
		_begin_front(unit)
	else:
		_release_combat(unit)
		entities.clear_destination(unit)
		if entities.move_state[unit] == SimTypes.MoveState.MOVING:
			entities.move_state[unit] = SimTypes.MoveState.IDLE


func _clear_queue(unit: int) -> void:
	_q_len[unit] = 0
	_needs_replan[unit] = 0
	_cooldown[unit] = 0
	_fail[unit] = 0
	_stall[unit] = 0


func _release_combat(unit: int) -> void:
	if _combat_set[unit] == 1:
		_combat_set[unit] = 0
		if entities.move_state[unit] == SimTypes.MoveState.COMBAT:
			entities.move_state[unit] = SimTypes.MoveState.IDLE


func _valid(unit: int) -> bool:
	return unit >= 0 and unit < entities.count()


## Grow the per-unit arrays to match the entity store. The economy is the only
## slot that spawns and it runs before this one, so a unit produced this tick
## is steerable on the same tick.
func _ensure_capacity() -> void:
	var n := entities.count()
	while _q_len.size() < n:
		for _k in range(MAX_ORDERS):
			_q_kind.append(OrderType.NONE)
			_q_x.append(0.0)
			_q_z.append(0.0)
		_q_len.append(0)
		_needs_replan.append(0)
		_cooldown.append(0)
		_fail.append(0)
		_stall.append(0)
		_hold.append(0)
		_near_dest.append(0)
		_combat_set.append(0)


# ═══════════════════════════════════════════════════════════════════════════
# THE TICK SLOT
# ═══════════════════════════════════════════════════════════════════════════

## Every simulation tick, before SimWorld._integrate(). Ascending index order,
## always: two units resolving in an unstable order is a desync.
func step(dt: float) -> void:
	if dt <= 0.0:
		return
	_ensure_capacity()
	var n := entities.count()
	var budget := replan_budget_per_tick
	_pool = expansion_budget_per_tick
	_in_step = true
	if separation_enabled:
		_build_neighbour_buckets()

	for i in range(n):
		if entities.alive[i] == 0:
			continue
		# Anything with no mobility profile is not ours. Skipping it rather than
		# zeroing its velocity matters: aircraft and ships in the sensing tests
		# are given a velocity directly and never a destination, and a movement
		# layer that stopped them would be reaching outside its own remit.
		if entities.max_speed_ms[i] <= 0.0 or entities.is_structure[i] == 1:
			continue

		if not entities.can_move(i):
			# Mobility-killed or dry. Hold still, but KEEP the order: refuelling
			# a stranded vehicle should let it carry on rather than silently
			# forgetting where it was told to go.
			_halt(i)
			continue

		# Somebody set a destination without going through order_move() --
		# a test, or the spine writing intent directly. Adopt it as a MOVE.
		if entities.has_dest[i] == 1 and _q_len[i] == 0:
			_adopt_destination(i)

		if entities.has_dest[i] == 0:
			if entities.speed_ms[i] != 0.0:
				_halt(i)
			continue

		if _cooldown[i] > 0:
			_cooldown[i] -= 1

		if _needs_replan[i] == 1 and _cooldown[i] <= 0:
			if budget > 0:
				budget -= 1
				_replan(i)
			else:
				plans_deferred += 1

		_steer(i, dt)
	_in_step = false


## Stop where you stand, without losing the order.
func _halt(i: int) -> void:
	entities.speed_ms[i] = 0.0
	entities.vel_x[i] = 0.0
	entities.vel_z[i] = 0.0
	entities.vel_y[i] = 0.0
	if entities.move_state[i] == SimTypes.MoveState.MOVING:
		entities.move_state[i] = SimTypes.MoveState.IDLE


func _adopt_destination(i: int) -> void:
	var base := i * MAX_ORDERS
	_q_kind[base] = OrderType.MOVE
	_q_x[base] = entities.dest_x[i]
	_q_z[base] = entities.dest_z[i]
	_q_len[i] = 1
	_needs_replan[i] = 1
	_cooldown[i] = 0
	_fail[i] = 0
	_stall[i] = 0


func _replan(i: int) -> void:
	var route := plan_path(i, entities.dest_x[i], entities.dest_z[i])
	if route.is_empty():
		if _last_plan_deferred:
			# Ran out of tick, not out of options. Ask again next tick, and do
			# NOT count it against the unit's patience.
			_needs_replan[i] = 1
			return
		_fail[i] += 1
		_cooldown[i] = replan_cooldown_ticks
		if _fail[i] >= max_plan_failures:
			# Unreachable. Abandoning the order is the honest outcome: a unit
			# that grinds against a coastline forever is worse than one that
			# stops and tells you it cannot get there.
			orders_abandoned += 1
			_clear_queue(i)
			_release_combat(i)
			entities.clear_destination(i)
			_halt(i)
		return
	_fail[i] = 0
	if last_goal_relocated:
		# The order itself is amended, not just the route, so that arrival is
		# measured against somewhere the unit can actually stand.
		var base := i * MAX_ORDERS
		_q_x[base] = last_goal_x
		_q_z[base] = last_goal_z
		entities.set_destination(i, last_goal_x, last_goal_z)
	# set_path() keeps MAX_PATH_POINTS and discards the tail, which is exactly
	# the coarse-route-then-refine behaviour the store documents: the unit walks
	# the prefix, exhausts it short of the destination, and replans from there.
	if route.size() / 2 > SimEntities.MAX_PATH_POINTS:
		plans_truncated += 1
	entities.set_path(i, route)
	_needs_replan[i] = 0
	_stall[i] = 0


# ═══════════════════════════════════════════════════════════════════════════
# STEERING
# ═══════════════════════════════════════════════════════════════════════════

func _steer(i: int, dt: float) -> void:
	var px := entities.pos_x[i]
	var pz := entities.pos_z[i]
	var speed := entities.speed_ms[i]

	# ── waypoint cursor. A waypoint counts as reached at whichever is larger,
	# the arrival radius or the distance covered in a tick and a half -- at
	# speed a fixed radius is smaller than the step and the unit circles it.
	var reach := maxf(arrive_radius_m, speed * dt * 1.5)
	while entities.has_path(i) and entities.path_cursor[i] < entities.path_len[i] - 1:
		var k := entities.path_cursor[i]
		var wx := entities.path_point_x(i, k)
		var wz := entities.path_point_z(i, k)
		if _dist(px, pz, wx, wz) <= reach:
			entities.advance_waypoint(i)
		else:
			break

	var dest_dist := _dist(px, pz, entities.dest_x[i], entities.dest_z[i])

	# ── arrival, either on the point or as close to it as the crowd allows
	var crowded_in := false
	if dest_dist <= crowd_arrive_radius_m and separation_enabled:
		if _neighbour_count(i, px, pz) > 0:
			_near_dest[i] += 1
			crowded_in = _near_dest[i] >= crowd_arrive_ticks
		else:
			_near_dest[i] = 0
	else:
		_near_dest[i] = 0

	if dest_dist <= arrive_radius_m or crowded_in:
		entities.speed_ms[i] = 0.0
		entities.vel_x[i] = 0.0
		entities.vel_z[i] = 0.0
		entities.vel_y[i] = 0.0
		entities.path_len[i] = 0
		entities.path_cursor[i] = 0
		_near_dest[i] = 0
		_pop_front(i)
		return

	# ── the point being steered at
	var tx := entities.dest_x[i]
	var tz := entities.dest_z[i]
	var on_path := entities.has_path(i)
	if on_path:
		var k2 := entities.path_cursor[i]
		tx = entities.path_point_x(i, k2)
		tz = entities.path_point_z(i, k2)
		if _dist(px, pz, tx, tz) <= arrive_radius_m:
			# Last waypoint reached but the destination is still ahead: the
			# stored route was a coarse prefix. Steer at the destination and ask
			# for the next leg.
			entities.advance_waypoint(i)
			_needs_replan[i] = 1
			tx = entities.dest_x[i]
			tz = entities.dest_z[i]
	else:
		_needs_replan[i] = 1

	# ── turn at a finite rate
	var desired := atan2(tx - px, tz - pz)
	var heading := entities.heading_rad[i]
	var err := wrapf(desired - heading, -PI, PI)
	var max_turn := maxf(entities.turn_rate_rads[i], 0.05) * dt
	if absf(err) <= max_turn:
		heading = desired
		err = 0.0
	else:
		heading += max_turn * signf(err)
		heading = wrapf(heading, -PI, PI)
		err = wrapf(desired - heading, -PI, PI)
	entities.heading_rad[i] = heading

	# ── how fast the ground allows
	var top := entities.max_speed_ms[i] * speed_multiplier(i, px, pz)
	# A unit that is badly misaligned crawls until it has turned. Without this a
	# tank drives a long arc sideways past its destination and comes back --
	# which reads as oscillation and is really a steering bug.
	var align: float = clampf(1.0 - absf(err) / (PI * 0.5), 0.0, 1.0)
	var turn_cap := top * (0.15 + 0.85 * align)
	# ── and how fast arriving allows: brake so that v^2 = 2*a*d lands on the
	# destination. This is what stops the oscillation at the end of a move.
	var decel := maxf(entities.accel_ms2[i], 0.1) * 2.0
	var brake_dist := maxf(dest_dist - arrive_radius_m * 0.5, 0.0)
	var arrive_cap := sqrt(2.0 * decel * brake_dist)
	var target := minf(minf(top, turn_cap), arrive_cap)

	var rate := entities.accel_ms2[i] if target > speed else decel
	speed = move_toward(speed, target, maxf(rate, 0.1) * dt)
	speed = clampf(speed, 0.0, top)
	entities.speed_ms[i] = speed

	var vx := sin(heading) * speed
	var vz := cos(heading) * speed

	# ── crowding. A lateral nudge only; it never rewrites the heading, so the
	# unit still follows its path and simply does not stand where a neighbour
	# is already standing.
	if separation_enabled and speed > 0.05:
		var sep := _separation(i, px, pz, top)
		vx += sep.x
		vz += sep.y
		var mag := sqrt(vx * vx + vz * vz)
		if mag > top and mag > 0.0:
			vx = vx / mag * top
			vz = vz / mag * top

	entities.vel_x[i] = vx
	entities.vel_z[i] = vz
	entities.vel_y[i] = _vertical_velocity(i, px + vx * dt, pz + vz * dt, dt)

	if entities.move_state[i] == SimTypes.MoveState.IDLE:
		entities.move_state[i] = SimTypes.MoveState.MOVING

	# ── stall watchdog. Something is in the way, or the route was nonsense.
	if speed < 0.25 * top:
		_stall[i] += 1
		if _stall[i] >= stall_ticks:
			_stall[i] = 0
			_needs_replan[i] = 1
	else:
		_stall[i] = 0


## Hold ground and surface units on the surface by writing VELOCITY, so that
## _integrate() remains the only thing that ever moves a unit. Aircraft and
## submarines keep whatever vertical velocity their own layer gave them.
func _vertical_velocity(i: int, next_x: float, next_z: float, dt: float) -> float:
	if not terrain_follow or terrain == null:
		return 0.0
	match entities.category[i]:
		SimTypes.Category.GROUND:
			return (terrain.ground_under(next_x, next_z) - entities.pos_y[i]) / dt
		SimTypes.Category.SURFACE:
			return (0.0 - entities.pos_y[i]) / dt
	return entities.vel_y[i]


# ═══════════════════════════════════════════════════════════════════════════
# CROWDING
#
# A uniform bucket grid, rebuilt once per tick. Dictionary LOOKUPS are fine for
# determinism; Dictionary ITERATION is not, so this never iterates the buckets
# -- it indexes nine of them in a fixed offset order, and each bucket's contents
# are appended in ascending index order.
# ═══════════════════════════════════════════════════════════════════════════

var _buckets: Dictionary = {}


func _bucket_key(cx: int, cz: int) -> int:
	return (cx + 1048576) * 4194304 + (cz + 1048576)


func _build_neighbour_buckets() -> void:
	_buckets.clear()
	var r := maxf(separation_radius_m, 1.0)
	for i in range(entities.count()):
		if entities.alive[i] == 0 or entities.max_speed_ms[i] <= 0.0:
			continue
		var cat := entities.category[i]
		if cat != SimTypes.Category.GROUND and cat != SimTypes.Category.SURFACE:
			continue
		var key := _bucket_key(int(floor(entities.pos_x[i] / r)),
			int(floor(entities.pos_z[i] / r)))
		if not _buckets.has(key):
			_buckets[key] = PackedInt32Array()
		var arr: PackedInt32Array = _buckets[key]
		arr.append(i)
		_buckets[key] = arr


## How many friendly movers are pressed against this one. Same buckets, same
## fixed offset order, so it is as deterministic as the separation itself.
func _neighbour_count(i: int, px: float, pz: float) -> int:
	var r := maxf(separation_radius_m, 1.0)
	var cx := int(floor(px / r))
	var cz := int(floor(pz / r))
	var n := 0
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var key := _bucket_key(cx + ox, cz + oz)
			if not _buckets.has(key):
				continue
			for j in (_buckets[key] as PackedInt32Array):
				if j == i:
					continue
				var dx := px - entities.pos_x[j]
				var dz := pz - entities.pos_z[j]
				if dx * dx + dz * dz < r * r:
					n += 1
	return n


func _separation(i: int, px: float, pz: float, top: float) -> Vector2:
	var r := maxf(separation_radius_m, 1.0)
	var cx := int(floor(px / r))
	var cz := int(floor(pz / r))
	var ax := 0.0
	var az := 0.0
	var hits := 0
	for oz in range(-1, 2):
		for ox in range(-1, 2):
			var key := _bucket_key(cx + ox, cz + oz)
			if not _buckets.has(key):
				continue
			for j in (_buckets[key] as PackedInt32Array):
				if j == i:
					continue
				var dx := px - entities.pos_x[j]
				var dz := pz - entities.pos_z[j]
				var d := sqrt(dx * dx + dz * dz)
				if d >= r:
					continue
				if d < 0.001:
					# Exactly coincident. Push apart along a rule, not a roll:
					# the lower index holds, the higher steps to +x.
					if i > j:
						ax += 1.0
						hits += 1
					continue
				var w := (r - d) / r
				ax += dx / d * w
				az += dz / d * w
				hits += 1
	if hits == 0:
		return Vector2.ZERO
	var mag := sqrt(ax * ax + az * az)
	if mag < 0.0001:
		return Vector2.ZERO
	var push := top * separation_strength
	return Vector2(ax / mag * push, az / mag * push)


# ═══════════════════════════════════════════════════════════════════════════
# TERRAIN
#
# One representation, not two. docs/02 already models the ground as a
# heightfield for masking; mobility reads the SAME array, so a ridge that hides
# a tank is the same ridge that slows it down.
# ═══════════════════════════════════════════════════════════════════════════

## Can this unit stand at this point? Water, cliffs and the map edge say no.
##
## RESOLUTION: this is a CELL question, answered from height_at_cell(), not from
## the bilinear height_at(). The heightfield IS the terrain, at whatever cell
## size the theatre was built with, and the bilinear filter is an interpolation
## on top of it for line of sight and for drawing. Mixing the two produces a
## specific, maddening bug: the A* walks dry cell centres, and a straight leg
## between two of them grazes the interpolated shoreline where the filter bleeds
## a metre of "water" up to half a cell inland. One representation, one answer.
func is_passable(unit: int, x_m: float, z_m: float) -> bool:
	if terrain == null:
		return true
	if not _in_bounds(x_m, z_m):
		return false
	var cat := entities.category[unit] if _valid(unit) else SimTypes.Category.GROUND
	if cat == SimTypes.Category.AIR:
		return true
	var c := _cell_at(x_m, z_m)
	return _cell_ok(cat, c % terrain.cells_x, c / terrain.cells_x)


## Passability of one cell, by category. The single definition; everything else
## routes through it.
##
## MEMOISED, and that is not a micro-optimisation. An A* expansion asks this
## about eight neighbours plus two orthogonals per diagonal -- two dozen times
## per expansion -- and the GROUND answer costs four height samples to work out a
## gradient. Uncached, one 300 km cross-theatre plan spends a third of a second
## recomputing the same slopes. The memo is a flat byte per cell (0 unknown,
## 1 passable, 2 blocked) for whichever category is being asked about; terrain is
## static, so an answer once computed is good for the whole match.
func _cell_ok(category: int, cx: int, cz: int) -> bool:
	if cx < 0 or cz < 0 or cx >= terrain.cells_x or cz >= terrain.cells_z:
		return false
	if category == SimTypes.Category.AIR:
		return true
	_prime_cache(category)
	return _pass_cache[cz * terrain.cells_x + cx] == 1


## The memo is for ONE category at a time. A mixed force replans a ship and then
## a tank and pays a rebuild between them; keeping four live caches is not worth
## it, because a Packed array held inside an Array is copy-on-write and every
## write would copy the whole grid.
##
## Built in ONE tight pass over terrain.heights rather than lazily per cell. The
## reason is GDScript's call overhead, which is what actually costs here: a
## per-cell version spends a microsecond or two crossing function boundaries for
## every neighbour the search looks at, and a long plan looks at a quarter of a
## million. Paid once per terrain per category, it is a few milliseconds on a
## test map and a fraction of a second on a 320 x 320 theatre -- and the search
## afterwards is two array reads per neighbour.
func _prime_cache(category: int) -> void:
	var n := terrain.cells_x * terrain.cells_z
	if _cache_category == category and _pass_cache.size() == n:
		return
	_build_cache(category)


## Pre-compute the going for a category, so the first move order of a match does
## not pay for it. A loading screen should call this.
func prime_terrain(category := SimTypes.Category.GROUND) -> void:
	if terrain != null:
		_prime_cache(category)


func _build_cache(category: int) -> void:
	var w := terrain.cells_x
	var h := terrain.cells_z
	var n := w * h
	var heights := terrain.heights
	var inv_2s := 1.0 / (2.0 * terrain.cell_size_m)
	var span := maxf(max_grade - gentle_grade, 0.0001)
	var pass_out := PackedByteArray()
	pass_out.resize(n)
	var going_out := PackedFloat32Array()
	going_out.resize(n)
	for cz in range(h):
		var row := cz * w
		var row_up := (cz + 1 if cz + 1 < h else cz) * w
		var row_dn := (cz - 1 if cz > 0 else cz) * w
		for cx in range(w):
			var k := row + cx
			var e := heights[k]
			var blocked := false
			var going := 1.0
			match category:
				SimTypes.Category.SURFACE:
					blocked = e >= 0.0
					var d := -e
					if d < shoal_depth_m:
						going = clampf(0.35 + 0.65 * (d / maxf(shoal_depth_m, 0.001)),
							0.35, 1.0)
				SimTypes.Category.SUBSURFACE:
					blocked = e >= -shoal_depth_m
				_:
					# GROUND: water and gradient both stop a vehicle, and the
					# gradient is the same central difference grade_at() reports.
					if e < 0.0:
						blocked = true
					else:
						var xr := cx + 1 if cx + 1 < w else cx
						var xl := cx - 1 if cx > 0 else cx
						var gx := (heights[row + xr] - heights[row + xl]) * inv_2s
						var gz := (heights[row_up + cx] - heights[row_dn + cx]) * inv_2s
						var g := sqrt(gx * gx + gz * gz)
						if g > max_grade:
							blocked = true
						elif g > gentle_grade:
							going = lerpf(1.0, min_grade_speed, (g - gentle_grade) / span)
			pass_out[k] = 2 if blocked else 1
			going_out[k] = going
	_pass_cache = pass_out
	_speed_cache = going_out
	_cache_category = category


## Cached going, 0..1, for one cell.
func _cell_going(category: int, cx: int, cz: int) -> float:
	if category == SimTypes.Category.AIR:
		return 1.0
	_prime_cache(category)
	return _speed_cache[cz * terrain.cells_x + cx]



## Fraction of top speed the ground here allows, 0..1. Read from the same memo
## the planner costs its cells with, so the route a unit picks and the speed it
## then makes are answers to the same question.
func speed_multiplier(unit: int, x_m: float, z_m: float) -> float:
	if terrain == null:
		return 1.0
	var cat := entities.category[unit] if _valid(unit) else SimTypes.Category.GROUND
	if cat == SimTypes.Category.AIR or cat == SimTypes.Category.SUBSURFACE:
		return 1.0
	if not _in_bounds(x_m, z_m):
		return 1.0
	var c := _cell_at(x_m, z_m)
	return _cell_going(cat, c % terrain.cells_x, c / terrain.cells_x)


## Rise over run at a point: a central difference across the neighbouring CELLS,
## so the answer is the slope of the landform and not of the bilinear filter.
func grade_at(x_m: float, z_m: float) -> float:
	if terrain == null:
		return 0.0
	var c := _cell_at(x_m, z_m)
	return _cell_grade(c % terrain.cells_x, c / terrain.cells_x)


func _cell_grade(cx: int, cz: int) -> float:
	var s := terrain.cell_size_m
	var hx := (terrain.height_at_cell(cx + 1, cz)
		- terrain.height_at_cell(cx - 1, cz)) / (2.0 * s)
	var hz := (terrain.height_at_cell(cx, cz + 1)
		- terrain.height_at_cell(cx, cz - 1)) / (2.0 * s)
	return sqrt(hx * hx + hz * hz)


func _in_bounds(x_m: float, z_m: float) -> bool:
	if terrain == null:
		return true
	var hx := terrain.extent_x_m() * 0.5
	var hz := terrain.extent_z_m() * 0.5
	return x_m >= -hx and x_m <= hx and z_m >= -hz and z_m <= hz


# ═══════════════════════════════════════════════════════════════════════════
# THE PATH SOLVER
#
# Grid A* over the terrain's own cells, 8-connected, no corner cutting.
# DETERMINISM: the open set is a binary heap ordered by (f, cell index). The
# second key is what makes two equal-cost routes resolve the same way on every
# machine and every run -- an f-only comparison leaves the choice to the order
# the heap happened to be built in.
# ═══════════════════════════════════════════════════════════════════════════

## Plan a route from a unit's current position to a world point. Returns a flat
## [x0, z0, x1, z1, ...] array in metres, EMPTY if no route exists.
##
## The returned route may be longer than SimEntities.MAX_PATH_POINTS; storing it
## keeps the first MAX_PATH_POINTS as a coarse prefix and the unit replans when
## it runs off the end. That is deliberate, and it is what hierarchical
## pathfinding does anyway.
func plan_path(unit: int, x_m: float, z_m: float) -> PackedFloat32Array:
	if not _valid(unit):
		return PackedFloat32Array()
	plans_run += 1
	_last_plan_deferred = false
	last_goal_relocated = false
	last_goal_x = x_m
	last_goal_z = z_m
	var sx := entities.pos_x[unit]
	var sz := entities.pos_z[unit]

	# No terrain, or a unit that ignores it: the straight line IS the route.
	if terrain == null or entities.category[unit] == SimTypes.Category.AIR:
		return PackedFloat32Array([x_m, z_m])

	if not _in_bounds(x_m, z_m):
		plans_failed += 1
		return PackedFloat32Array()

	# The overwhelmingly common case, and worth the check: open ground.
	if _segment_passable(unit, sx, sz, x_m, z_m):
		return PackedFloat32Array([x_m, z_m])

	var goal_cell := _cell_at(x_m, z_m)
	var relocated := false
	if not _cell_passable(unit, goal_cell):
		# Clicking the middle of a lake should still send a tank to the shore.
		goal_cell = _nearest_passable_cell(unit, goal_cell)
		if goal_cell < 0:
			plans_failed += 1
			return PackedFloat32Array()
		relocated = true
		last_goal_relocated = true
		last_goal_x = _cell_centre_x(goal_cell % terrain.cells_x)
		last_goal_z = _cell_centre_z(goal_cell / terrain.cells_x)
	var start_cell := _cell_at(sx, sz)
	if not _cell_passable(unit, start_cell):
		# Standing somewhere it should not be -- spawned on a cliff, or the
		# ground changed underneath it. Walk out to the nearest legal cell.
		start_cell = _nearest_passable_cell(unit, start_cell)
		if start_cell < 0:
			plans_failed += 1
			return PackedFloat32Array()

	var cells := _astar(unit, start_cell, goal_cell)
	if cells.is_empty():
		if _last_plan_deferred:
			plans_deferred += 1
		else:
			plans_failed += 1
		return PackedFloat32Array()

	var exact := cells[cells.size() - 1] == goal_cell
	if not exact:
		plans_partial += 1
	# Finish on the exact point that was clicked only when that point is where
	# the route actually ends. A goal that had to be moved out of the water ends
	# at the relocated cell, and pretending otherwise puts the last waypoint back
	# in the lake.
	return _smooth(unit, sx, sz, cells, x_m, z_m, exact and not relocated)


## Returns the cell route, start EXCLUDED, goal included. Empty on failure.
## On exhausting the expansion budget it returns the route to the expanded cell
## closest to the goal, so the unit makes progress and replans later.
func _astar(unit: int, start_cell: int, goal_cell: int) -> PackedInt32Array:
	_open_f.clear()
	_open_c.clear()
	_new_generation()
	last_expansions = 0
	var cap := max_search_cells
	if _in_step:
		cap = mini(cap, _pool)
	if cap <= 0:
		_last_plan_deferred = true
		return PackedInt32Array()

	var w := terrain.cells_x
	var h := terrain.cells_z
	var cell := terrain.cell_size_m
	var gx := goal_cell % w
	var gz := goal_cell / w

	_stamp[start_cell] = _gen
	_gscore[start_cell] = 0.0
	_parent[start_cell] = -1
	_heap_push(_octile(start_cell % w, start_cell / w, gx, gz) * cell, start_cell)

	# Local handles on the memo. The inner loop below runs a quarter of a million
	# times on a long plan, and two array reads per neighbour is the difference
	# between a plan and a frame drop.
	var cat := entities.category[unit] if _valid(unit) else SimTypes.Category.GROUND
	_prime_cache(cat)
	var going := _speed_cache
	var passable := _pass_cache

	var best := start_cell
	var best_h := _octile(start_cell % w, start_cell / w, gx, gz)
	## The distinction that decides whether an order is retried or abandoned: an
	## exhausted OPEN SET means there is no route and there never will be, while
	## an exhausted BUDGET means the search was cut short and the partial route
	## is worth walking. Collapsing the two makes a tank grind against a coastline
	## forever, replanning the same impossible route every ten ticks.
	var budget_exhausted := false

	while _open_c.size() > 0:
		var cur := _heap_pop()
		if _closed_stamp[cur] == _gen:
			continue
		_closed_stamp[cur] = _gen
		if cur == goal_cell:
			_spend(last_expansions)
			return _reconstruct(start_cell, goal_cell)
		last_expansions += 1
		if last_expansions >= cap:
			budget_exhausted = true
			break

		var cx := cur % w
		var cz := cur / w
		var cur_g := _gscore[cur]
		for d in NEIGHBOURS:
			var nx: int = cx + d.x
			var nz: int = cz + d.y
			if nx < 0 or nz < 0 or nx >= w or nz >= h:
				continue
			var ncell := nz * w + nx
			if _closed_stamp[ncell] == _gen:
				continue
			if passable[ncell] != 1:
				continue
			var diagonal: bool = d.x != 0 and d.y != 0
			if diagonal:
				# No corner cutting: a tank does not squeeze between two cliffs
				# through the point where they touch.
				if passable[cz * w + nx] != 1 or passable[nz * w + cx] != 1:
					continue
			var step_m: float = cell * (SQRT2 if diagonal else 1.0)
			# Cost is TIME, not distance: slow ground is expensive ground, so a
			# route round a hill beats a route over it exactly when it is
			# quicker. The heuristic uses the cheapest possible cost per metre
			# (1.0) and stays admissible.
			var ng: float = cur_g + step_m / maxf(going[ncell], 0.01)
			if _stamp[ncell] == _gen and _gscore[ncell] <= ng:
				continue
			_stamp[ncell] = _gen
			_gscore[ncell] = ng
			_parent[ncell] = cur
			var hh := _octile(nx, nz, gx, gz)
			if hh < best_h:
				best_h = hh
				best = ncell
			_heap_push(ng + hh * cell, ncell)

	_spend(last_expansions)
	if not budget_exhausted:
		return PackedInt32Array()      # unreachable: there is no route at all
	if best == start_cell:
		return PackedInt32Array()
	return _reconstruct(start_cell, best)


## Reset the search without clearing a hundred thousand cells: bump the
## generation, and every stale stamp stops matching.
func _new_generation() -> void:
	var n := terrain.cells_x * terrain.cells_z
	if _stamp.size() != n:
		_stamp.resize(n); _stamp.fill(0)
		_gscore.resize(n); _gscore.fill(0.0)
		_parent.resize(n); _parent.fill(-1)
		_closed_stamp.resize(n); _closed_stamp.fill(0)
		_gen = 0
	_gen += 1


func _spend(expansions: int) -> void:
	if _in_step:
		_pool -= expansions


func _reconstruct(start_cell: int, end_cell: int) -> PackedInt32Array:
	var rev := PackedInt32Array()
	var c := end_cell
	var guard := 0
	while c != start_cell and _parent[c] >= 0 and guard < 100000:
		rev.append(c)
		c = _parent[c]
		guard += 1
	var out := PackedInt32Array()
	for k in range(rev.size() - 1, -1, -1):
		out.append(rev[k])
	return out


## String-pull the cell route: keep a waypoint only where the straight line to
## the one after it stops being legal. A raw cell route makes a unit stagger
## from cell centre to cell centre; this turns it back into a line.
func _smooth(unit: int, sx: float, sz: float, cells: PackedInt32Array,
		goal_x: float, goal_z: float, exact: bool) -> PackedFloat32Array:
	var w := terrain.cells_x
	var pts_x := PackedFloat32Array()
	var pts_z := PackedFloat32Array()
	for c in cells:
		pts_x.append(_cell_centre_x(c % w))
		pts_z.append(_cell_centre_z(c / w))
	if exact:
		# Finish at the point the player actually clicked, not at a cell centre.
		pts_x[pts_x.size() - 1] = goal_x
		pts_z[pts_z.size() - 1] = goal_z

	var out := PackedFloat32Array()
	var ax := sx
	var az := sz
	var k := 0
	var guard := 0
	while k < pts_x.size() and guard < 4096:
		guard += 1
		# Reach as far along the route as the ground allows.
		var far := k
		for j in range(pts_x.size() - 1, k - 1, -1):
			if _segment_passable(unit, ax, az, pts_x[j], pts_z[j]):
				far = j
				break
		out.append(pts_x[far])
		out.append(pts_z[far])
		ax = pts_x[far]
		az = pts_z[far]
		k = far + 1
	return out


## Is the straight line between two points legal for this unit?
##
## Walked cell by cell (Amanatides-Woo grid traversal) rather than sampled at a
## stride. Sampling is what lets a leg clip the corner of an impassable cell and
## produce a unit that drives through a lake for twenty metres; the traversal is
## exact at the resolution the terrain actually has. It is also cheaper, because
## it visits each crossed cell exactly once.
func _segment_passable(unit: int, ax: float, az: float, bx: float, bz: float) -> bool:
	if terrain == null:
		return true
	var cat := entities.category[unit] if _valid(unit) else SimTypes.Category.GROUND
	if cat == SimTypes.Category.AIR:
		return true
	if not _in_bounds(ax, az) or not _in_bounds(bx, bz):
		return false
	var cs := terrain.cell_size_m
	var fx0 := (ax + terrain.extent_x_m() * 0.5) / cs
	var fz0 := (az + terrain.extent_z_m() * 0.5) / cs
	var fx1 := (bx + terrain.extent_x_m() * 0.5) / cs
	var fz1 := (bz + terrain.extent_z_m() * 0.5) / cs
	var cx := clampi(int(floor(fx0)), 0, terrain.cells_x - 1)
	var cz := clampi(int(floor(fz0)), 0, terrain.cells_z - 1)
	var ex := clampi(int(floor(fx1)), 0, terrain.cells_x - 1)
	var ez := clampi(int(floor(fz1)), 0, terrain.cells_z - 1)
	var dx := fx1 - fx0
	var dz := fz1 - fz0
	var step_x := 0
	var step_z := 0
	var t_max_x := INF
	var t_max_z := INF
	var t_delta_x := INF
	var t_delta_z := INF
	if dx > 0.0:
		step_x = 1
		t_delta_x = 1.0 / dx
		t_max_x = (float(cx + 1) - fx0) / dx
	elif dx < 0.0:
		step_x = -1
		t_delta_x = -1.0 / dx
		t_max_x = (float(cx) - fx0) / dx
	if dz > 0.0:
		step_z = 1
		t_delta_z = 1.0 / dz
		t_max_z = (float(cz + 1) - fz0) / dz
	elif dz < 0.0:
		step_z = -1
		t_delta_z = -1.0 / dz
		t_max_z = (float(cz) - fz0) / dz
	var guard := 0
	while guard < 8192:
		guard += 1
		if not _cell_ok(cat, cx, cz):
			return false
		if cx == ex and cz == ez:
			return true
		# The tie -- a line through an exact cell corner -- is broken toward x by
		# a fixed rule, so the answer never depends on floating-point luck.
		if t_max_x <= t_max_z:
			cx += step_x
			t_max_x += t_delta_x
		else:
			cz += step_z
			t_max_z += t_delta_z
		if cx < 0 or cz < 0 or cx >= terrain.cells_x or cz >= terrain.cells_z:
			return false
	return false


func _cell_at(x_m: float, z_m: float) -> int:
	var cx := int(floor((x_m + terrain.extent_x_m() * 0.5) / terrain.cell_size_m))
	var cz := int(floor((z_m + terrain.extent_z_m() * 0.5) / terrain.cell_size_m))
	cx = clampi(cx, 0, terrain.cells_x - 1)
	cz = clampi(cz, 0, terrain.cells_z - 1)
	return cz * terrain.cells_x + cx


func _cell_centre_x(cx: int) -> float:
	return (float(cx) + 0.5) * terrain.cell_size_m - terrain.extent_x_m() * 0.5


func _cell_centre_z(cz: int) -> float:
	return (float(cz) + 0.5) * terrain.cell_size_m - terrain.extent_z_m() * 0.5


func _cell_passable(unit: int, cell: int) -> bool:
	var w := terrain.cells_x
	var cat := entities.category[unit] if _valid(unit) else SimTypes.Category.GROUND
	return _cell_ok(cat, cell % w, cell / w)


## Rebuild the memo if a tunable that feeds it is changed after the fact.
func invalidate_terrain_cache() -> void:
	_cache_category = -1
	_pass_cache.resize(0)
	_speed_cache.resize(0)


## Expanding ring search for somewhere legal to stand. Deterministic: rings
## outward, and within a ring the LOWEST CELL INDEX wins.
func _nearest_passable_cell(unit: int, cell: int) -> int:
	var w := terrain.cells_x
	var h := terrain.cells_z
	var cx := cell % w
	var cz := cell / w
	for r in range(1, 17):
		var best := -1
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var nx := cx + dx
				var nz := cz + dz
				if nx < 0 or nz < 0 or nx >= w or nz >= h:
					continue
				var nc := nz * w + nx
				if not _cell_passable(unit, nc):
					continue
				if best < 0 or nc < best:
					best = nc
		if best >= 0:
			return best
	return -1


func _octile(ax: int, az: int, bx: int, bz: int) -> float:
	var dx := absi(ax - bx)
	var dz := absi(az - bz)
	return float(maxi(dx, dz)) + (SQRT2 - 1.0) * float(mini(dx, dz))


# ── the open set ────────────────────────────────────────────────────────────

func _heap_push(f: float, c: int) -> void:
	_open_f.append(f)
	_open_c.append(c)
	var i := _open_f.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if _heap_less(i, p):
			_heap_swap(i, p)
			i = p
		else:
			break


func _heap_pop() -> int:
	var last := _open_c.size() - 1
	var top := _open_c[0]
	_open_f[0] = _open_f[last]
	_open_c[0] = _open_c[last]
	_open_f.resize(last)
	_open_c.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < last and _heap_less(l, m):
			m = l
		if r < last and _heap_less(r, m):
			m = r
		if m == i:
			break
		_heap_swap(i, m)
		i = m
	return top


## (f, cell index). The second key is the determinism guarantee.
func _heap_less(a: int, b: int) -> bool:
	if _open_f[a] < _open_f[b]:
		return true
	if _open_f[a] > _open_f[b]:
		return false
	return _open_c[a] < _open_c[b]


func _heap_swap(a: int, b: int) -> void:
	var tf := _open_f[a]
	_open_f[a] = _open_f[b]
	_open_f[b] = tf
	var tc := _open_c[a]
	_open_c[a] = _open_c[b]
	_open_c[b] = tc


# ═══════════════════════════════════════════════════════════════════════════
# FORMATIONS
# ═══════════════════════════════════════════════════════════════════════════

## Formation destinations for a group ordered to one point. Returns a flat
## [x0, z0, ...] array, one pair per unit, in the SAME ORDER as `units`.
## This is proving_ground.gd's formation grid, moved into the sim where docs/06
## says gameplay lives, and given the two things it was missing: slots that land
## on ground the unit can actually occupy, and a pitch taken from the units in
## the group rather than from their rendered bounding boxes.
func formation_slots(units: PackedInt32Array, x_m: float, z_m: float,
		spacing_m: float = 14.0) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	var n := units.size()
	if n == 0:
		return out
	if n == 1:
		out.append(x_m)
		out.append(z_m)
		return out
	var cols := int(ceil(sqrt(float(n))))
	var rows := int(ceil(float(n) / float(cols)))
	var pitch := maxf(spacing_m, 1.0)
	for k in range(n):
		# BOTH axes centred on the ordered point, so the group's centre of mass
		# lands where the player pointed.
		var ox := float(k % cols) * pitch - float(cols - 1) * pitch * 0.5
		var oz := float(k / cols) * pitch - float(rows - 1) * pitch * 0.5
		var sx := x_m + ox
		var sz := z_m + oz
		var u := units[k]
		if terrain != null and _valid(u) and not is_passable(u, sx, sz):
			var fixed := _nudge_to_passable(u, sx, sz, pitch)
			sx = fixed.x
			sz = fixed.y
		out.append(sx)
		out.append(sz)
	return out


## Spiral outward in fixed steps for somewhere the unit can stand. Deterministic
## by construction -- a fixed ring order, first legal point wins.
func _nudge_to_passable(unit: int, x_m: float, z_m: float, pitch: float) -> Vector2:
	for r in range(1, 5):
		var radius := pitch * float(r)
		for a in range(8):
			var ang := float(a) * PI * 0.25
			var nx := x_m + sin(ang) * radius
			var nz := z_m + cos(ang) * radius
			if is_passable(unit, nx, nz):
				return Vector2(nx, nz)
	return Vector2(x_m, z_m)


# ═══════════════════════════════════════════════════════════════════════════

func has_arrived(unit: int) -> bool:
	return entities.has_dest[unit] == 0 and entities.path_len[unit] == 0


func _dist(ax: float, az: float, bx: float, bz: float) -> float:
	var dx := bx - ax
	var dz := bz - az
	return sqrt(dx * dx + dz * dz)


## True once this class actually steers. Reported honestly by SimWorld.
func is_implemented() -> bool:
	return true


func describe() -> String:
	return "movement: %d plans (%d failed, %d partial, %d truncated, %d deferred), %d orders issued, %d completed, %d abandoned" % [
		plans_run, plans_failed, plans_partial, plans_truncated, plans_deferred,
		orders_issued, orders_completed, orders_abandoned]
