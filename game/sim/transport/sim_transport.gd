class_name SimTransport
extends RefCounted
## Slot 3.5: loading, unloading and the DeployState machine. docs/12's
## transports and deployables, docs/04's amphibious lift.
##
## WHAT THIS SYSTEM OWNS (per the ownership table in sim_entities.gd):
## deploy_state and deploy_timer are written here and nowhere else; carried_by /
## cargo_slots / cargo_len change only through SimEntities.board() and
## disembark(), which this system calls after doing the checks that are ITS
## job -- proximity, capacity in SLOTS, who may carry whom, and where a
## disgorged unit may legally stand. SimEntities.kill() owns the cargo-dies-
## with-the-hull cascade; this system only reports the loss afterwards.
##
## THE SLOT MODEL. SimEntities.cargo_capacity is a per-transport slot budget,
## set at spawn from the roster's cargo_slots and capped by the spine's fixed
## MAX_CARGO stride of 8. Infantry cost 1 slot; anything else costs
## VEHICLE_SLOT_COST (4), and only the well-deck hulls -- landing craft and
## amphibs, carries_vehicles in the roster -- take vehicles at all. Boats
## (SURFACE cargo, i.e. a loaded landing craft) nest only in a well deck.
## Aircraft never board: they RECOVER, which is the sortie system's business.
##
## LOAD is a JOURNEY, not a teleport: the ordered unit walks to the transport
## through the ordinary movement layer and boards on arrival within
## BOARD_RADIUS_M. The pending load chases a transport that moves, and is
## cancelled the moment the unit is ordered anywhere else -- a new order means
## the player changed their mind.
##
## UNLOAD disgorges adjacent on a deterministic ring, the same pattern as
## SimEconomy._exit_point(): a landing craft therefore unloads onto the BEACH,
## the nearest ground that suits the passenger, and refuses mid-ocean.
##
## DEPLOY is one order for both directions (the player's key is one key):
## MOBILE begins DEPLOYING, DEPLOYED begins UNDEPLOYING, and a mid-transition
## order is REFUSED -- the crew is committed, and that vulnerable, immobile
## window is the gameplay, not a cosmetic animation. While any state but
## MOBILE, SimEntities.can_move() is false and the movement layer halts the
## unit WITHOUT dropping its orders. Whether the unit may FIRE in its current
## posture is answered by may_fire() below, which SimWeaponCycle consults
## through its duck-typed deploy_gate hook (installed by install()).
##
## DETERMINISM: every Dictionary iterated here is iterated in sorted key
## order, and nothing draws a random number.

const BOARD_RADIUS_M := 40.0        ## close enough for the ramp
const RETARGET_M := 15.0            ## transport drifted this far -> re-approach
const INFANTRY_SLOT_COST := 1
const VEHICLE_SLOT_COST := 4
const UNLOAD_RING_BASE_M := 20.0    ## first ring, clear of the hull
const UNLOAD_RING_STEP_M := 22.0    ## same step the factory exit uses
const UNLOAD_RINGS := 6
const UNLOAD_SPOT_CLEARANCE_M := 8.0

var entities: SimEntities
var movement: SimMovement = null
var economy: SimEconomy = null
var terrain: SimTerrain = null
var damage: SimDamage = null
## Kept so step() can pick up a theatre installed after this system was.
var _world = null

# ── pending loads: unit -> transport it was ordered aboard ───────────────────
var _pending_load: Dictionary = {}
## unit -> Vector2 of the approach point last handed to the movement layer.
## Divergence between this and the unit's live destination means somebody
## re-ordered the unit, which cancels the load.
var _pending_dest: Dictionary = {}

# ── per-unit overrides, for units built without a roster def (tests, setup) ──
var _slot_cost_override: Dictionary = {}
var _vehicle_deck_override: Dictionary = {}
## unit -> Vector3(deploy_s, undeploy_s, fires_deployed_only ? 1.0 : 0.0)
var _deploy_override: Dictionary = {}

# ── the cargo-loss watch: transport -> units aboard last step ────────────────
## The kill cascade happens inside SimEntities.kill() during the damage slot;
## by the time this system runs again the hold is already empty. So the
## manifest is snapshotted each step, and a watched transport found dead is
## reported to the combat log -- docs/10 §10, the log is the tutorial, and
## "the APC died with the squad inside" is the lesson.
var _manifest_watch: Dictionary = {}

# ── bookkeeping ──────────────────────────────────────────────────────────────
var loads_completed: int = 0
var loads_cancelled: int = 0
var unloads_completed: int = 0
var event_log: Array = []
var max_log: int = 120


func _init(store: SimEntities, p_movement: SimMovement = null,
		p_economy: SimEconomy = null, p_terrain: SimTerrain = null,
		p_damage: SimDamage = null) -> void:
	entities = store
	movement = p_movement
	economy = p_economy
	terrain = p_terrain
	damage = p_damage


## Build the system from a world and wire BOTH seams the spine left open:
## SimWorld.transport_system (orders and the slot-3.5 step) and
## SimWeaponCycle.deploy_gate (the posture half of "may I shoot?").
static func install(world: SimWorld) -> SimTransport:
	var t := SimTransport.new(world.entities, world.movement, world.economy,
		world.terrain, world.damage)
	t._world = world
	world.transport_system = t
	world.weapons.deploy_gate = t
	return t


func is_implemented() -> bool:
	return true


# ═══════════════════════════════════════════════════════════════════════════
# ORDERS (routed here by SimWorld._execute_command)
# ═══════════════════════════════════════════════════════════════════════════

## LOAD: `unit` walks to `transport` and boards on arrival. Ownership of both
## indices was already enforced at the command gate; this validates the
## PHYSICS -- capacity, cargo type, posture -- and returns false when the
## order cannot change anything.
func order_load(unit: int, transport: int) -> bool:
	var why := loading_problem(unit, transport)
	if why != "":
		_log("load refused: %s -> %s -- %s" % [
			_name(unit), _name(transport), why])
		return false
	if _within_boarding_range(unit, transport):
		return _complete_board(unit, transport)
	if movement == null:
		return false
	var tx := entities.pos_x[transport]
	var tz := entities.pos_z[transport]
	if not movement.order_move(unit, tx, tz):
		return false
	_pending_load[unit] = transport
	_pending_dest[unit] = Vector2(tx, tz)
	return true


## UNLOAD: disgorge where the hull stands, onto the deterministic ring.
## `passenger` -1 = everything aboard, in boarding order. Returns true when at
## least one unit actually reached the ground -- a landing craft mid-ocean
## finds no legal spot and the order is honestly rejected.
func order_unload(transport: int, passenger: int = -1) -> bool:
	if not entities.is_alive(transport):
		return false
	if entities.is_aboard(transport):
		return false   # a hold stowed inside another hold cannot open its ramp
	if entities.cargo_count(transport) == 0:
		return false
	var manifest := PackedInt32Array()
	if passenger >= 0:
		if passenger >= entities.count() \
				or entities.carried_by[passenger] != transport:
			return false
		manifest.append(passenger)
	else:
		manifest = entities.cargo_of(transport)
	var placed: Array = []   # Vector2 spots already handed out this ramp cycle
	var out := 0
	for u in manifest:
		var spot := _unload_spot(transport, u, placed)
		if spot.size() < 2:
			_log("%s cannot disgorge %s -- no ground fits" % [
				_name(transport), _name(u)])
			continue
		if entities.disembark(transport, u, spot[0], spot[1]):
			_settle_altitude(u)
			placed.append(Vector2(spot[0], spot[1]))
			unloads_completed += 1
			out += 1
	if out > 0:
		_log("%s unloads %d unit(s)" % [_name(transport), out])
	return out > 0


## DEPLOY: one order, both directions. Refused mid-transition -- the crew is
## committed -- and refused outright for anything the roster does not call a
## deployable.
func order_deploy(unit: int) -> bool:
	if not entities.is_alive(unit) or entities.is_aboard(unit):
		return false
	if not is_deployable(unit):
		return false
	match entities.deploy_state[unit]:
		SimTypes.DeployState.MOBILE:
			entities.deploy_state[unit] = SimTypes.DeployState.DEPLOYING
			entities.deploy_timer[unit] = deploy_seconds_of(unit)
			_log("%s deploying (%.0f s)" % [_name(unit),
				entities.deploy_timer[unit]])
			return true
		SimTypes.DeployState.DEPLOYED:
			entities.deploy_state[unit] = SimTypes.DeployState.UNDEPLOYING
			entities.deploy_timer[unit] = undeploy_seconds_of(unit)
			_log("%s packing up (%.0f s)" % [_name(unit),
				entities.deploy_timer[unit]])
			return true
	return false


# ═══════════════════════════════════════════════════════════════════════════
# THE STEP -- slot 3.5, every simulation tick
# ═══════════════════════════════════════════════════════════════════════════

func step(dt: float) -> void:
	if _world != null and _world.terrain != null:
		terrain = _world.terrain
	_step_pending_loads()
	_step_deploy_transitions(dt)
	_step_cargo_watch()


## Walk the pending boardings, ascending unit index (docs/06: never iterate an
## unordered container where order can reach the outcome -- two squads racing
## for the last slot must resolve identically every run).
func _step_pending_loads() -> void:
	if _pending_load.is_empty():
		return
	var units: Array = _pending_load.keys()
	units.sort()
	for u in units:
		var t: int = _pending_load[u]
		if not entities.is_alive(u) or not entities.is_alive(t) \
				or entities.is_aboard(u) or entities.is_aboard(t):
			_drop_pending(u)
			continue
		# Re-validate: the hold may have filled, the unit may have deployed.
		if loading_problem(u, t) != "":
			_cancel_pending(u, loading_problem(u, t))
			continue
		if _within_boarding_range(u, t):
			_complete_board(u, t)
			_drop_pending(u)
			continue
		var want := Vector2(entities.pos_x[t], entities.pos_z[t])
		var last: Vector2 = _pending_dest[u]
		if entities.has_dest[u] == 1:
			var cur := Vector2(entities.dest_x[u], entities.dest_z[u])
			if cur.distance_squared_to(last) > 4.0:
				# The unit is going somewhere this system did not send it: the
				# player (or its AI) re-ordered it, and a load order does not
				# outrank the newer order.
				_cancel_pending(u, "re-ordered elsewhere")
				continue
			# Still en route. Chase a transport that has moved on.
			if want.distance_squared_to(last) > RETARGET_M * RETARGET_M \
					and movement != null and movement.order_move(u, want.x, want.y):
				_pending_dest[u] = want
			continue
		# No destination: the approach ended short of the ramp (arrived,
		# stopped, or path failed). Chase a transport that moved; a transport
		# that did not is simply unreachable from here.
		if want.distance_squared_to(last) > RETARGET_M * RETARGET_M \
				and movement != null and movement.order_move(u, want.x, want.y):
			_pending_dest[u] = want
		else:
			_cancel_pending(u, "could not reach the transport")


## Count the transitions down. deploy_state/deploy_timer belong to this slot
## and are written nowhere else.
func _step_deploy_transitions(dt: float) -> void:
	for i in range(entities.count()):
		if entities.alive[i] == 0:
			continue
		var s := entities.deploy_state[i]
		if s != SimTypes.DeployState.DEPLOYING \
				and s != SimTypes.DeployState.UNDEPLOYING:
			continue
		entities.deploy_timer[i] = maxf(0.0, entities.deploy_timer[i] - dt)
		if entities.deploy_timer[i] > 0.0:
			continue
		if s == SimTypes.DeployState.DEPLOYING:
			entities.deploy_state[i] = SimTypes.DeployState.DEPLOYED
			_log("%s deployed" % _name(i))
		else:
			entities.deploy_state[i] = SimTypes.DeployState.MOBILE
			_log("%s limbered and mobile" % _name(i))


## Report holds that died since last step. The cascade itself already happened
## inside SimEntities.kill(); this puts the COST in the combat log, because a
## player who loses eight squads inside one amphib must be told so in words.
func _step_cargo_watch() -> void:
	if not _manifest_watch.is_empty():
		var watched: Array = _manifest_watch.keys()
		watched.sort()
		for t in watched:
			if entities.alive[t] == 0:
				var n: int = _manifest_watch[t]
				var line := "%s destroyed with %d unit(s) aboard -- the cargo is lost" \
					% [_name(t), n]
				_log(line)
				if damage != null:
					damage.log_event(line)
	_manifest_watch.clear()
	for i in range(entities.count()):
		if entities.alive[i] == 1 and entities.cargo_len[i] > 0:
			_manifest_watch[i] = entities.cargo_len[i]


# ═══════════════════════════════════════════════════════════════════════════
# THE DEPLOY FIRE GATE (SimWeaponCycle.deploy_gate)
# ═══════════════════════════════════════════════════════════════════════════

## The posture half of "may I shoot?". A transition never fires; MOBILE fires
## unless the role is a fires-only-deployed deployable (towed guns, TELs);
## DEPLOYED always may -- that is what deploying is for.
func may_fire(unit: int) -> bool:
	match entities.deploy_state[unit]:
		SimTypes.DeployState.DEPLOYING, SimTypes.DeployState.UNDEPLOYING:
			return false
		SimTypes.DeployState.MOBILE:
			return not fires_deployed_only(unit)
	return true


## Why may_fire said no, for the gate log -- docs/02 §9, a shot refused for
## invisible reasons reads as a bug.
func fire_refusal(unit: int) -> String:
	match entities.deploy_state[unit]:
		SimTypes.DeployState.DEPLOYING:
			return "deploying -- not yet emplaced"
		SimTypes.DeployState.UNDEPLOYING:
			return "packing up -- weapon out of action"
	return "limbered -- deploy to fire"


# ═══════════════════════════════════════════════════════════════════════════
# RULES AND QUERIES (public: the HUD wants the same answers the sim uses)
# ═══════════════════════════════════════════════════════════════════════════

## Why `unit` may not board `transport`, or "" when it may. String rather than
## bool for the same reason SimEconomy.placement_problem() is: the cursor
## should say WHY it is red.
func loading_problem(unit: int, transport: int) -> String:
	if not entities.is_alive(unit) or not entities.is_alive(transport):
		return "dead"
	if unit == transport:
		return "cannot board itself"
	if entities.is_structure[unit] == 1:
		return "structures do not board"
	if entities.cargo_capacity[transport] <= 0:
		return "not a transport"
	if entities.is_aboard(unit):
		return "already aboard something"
	if entities.is_aboard(transport):
		return "the transport is itself stowed"
	if entities.deploy_state[unit] != SimTypes.DeployState.MOBILE:
		return "must pack up before boarding"
	match entities.category[unit]:
		SimTypes.Category.AIR:
			return "aircraft recover at a base, they do not board"
		SimTypes.Category.SUBSURFACE:
			return "a submarine cannot be carried"
		SimTypes.Category.SURFACE:
			if not deck_takes_vehicles(transport):
				return "a boat nests only in a well deck"
	var cost := slot_cost(unit)
	if cost > INFANTRY_SLOT_COST and not deck_takes_vehicles(transport):
		return "only a landing craft or amphib takes vehicles"
	if slots_free(transport) < cost:
		return "no room aboard"
	return ""


## Slots this unit occupies as cargo: infantry 1, everything else 4. Reads the
## roster def's domain; set_slot_cost() overrides for def-less units.
func slot_cost(unit: int) -> int:
	if _slot_cost_override.has(unit):
		return _slot_cost_override[unit]
	var d := _def(unit)
	if d != null and (d.domain & SimPlayerSetup.Domain.INFANTRY) != 0:
		return INFANTRY_SLOT_COST
	if d != null:
		return VEHICLE_SLOT_COST
	# No def at all (hand-built test unit): assume the cheap case.
	return INFANTRY_SLOT_COST


## May this hull take vehicles (and nested boats) aboard?
func deck_takes_vehicles(transport: int) -> bool:
	if _vehicle_deck_override.has(transport):
		return _vehicle_deck_override[transport]
	var d := _def(transport)
	return d != null and d.carries_vehicles


## Slots consumed by what is aboard right now. Recomputed on demand from the
## manifest -- no cached counter to drift out of sync with kill()'s cascade.
func slots_used(transport: int) -> int:
	var used := 0
	for u in entities.cargo_of(transport):
		used += slot_cost(u)
	return used


func slots_free(transport: int) -> int:
	return entities.cargo_capacity[transport] - slots_used(transport)


func is_deployable(unit: int) -> bool:
	if _deploy_override.has(unit):
		return true
	var d := _def(unit)
	return d != null and d.is_deployable()


func deploy_seconds_of(unit: int) -> float:
	if _deploy_override.has(unit):
		return (_deploy_override[unit] as Vector3).x
	var d := _def(unit)
	return d.deploy_seconds if d != null else 0.0


func undeploy_seconds_of(unit: int) -> float:
	if _deploy_override.has(unit):
		return (_deploy_override[unit] as Vector3).y
	var d := _def(unit)
	return d.undeploy_seconds if d != null else 0.0


func fires_deployed_only(unit: int) -> bool:
	if _deploy_override.has(unit):
		return (_deploy_override[unit] as Vector3).z > 0.5
	var d := _def(unit)
	return d != null and d.fires_deployed_only


## True while a LOAD order is still walking `unit` to its transport.
func is_load_pending(unit: int) -> bool:
	return _pending_load.has(unit)


# ── overrides for units built without a roster def (tests, scenario setup) ───

func set_slot_cost(unit: int, cost: int) -> void:
	_slot_cost_override[unit] = maxi(cost, 1)


func set_vehicle_deck(unit: int, takes_vehicles: bool) -> void:
	_vehicle_deck_override[unit] = takes_vehicles


func make_deployable(unit: int, deploy_s: float, undeploy_s: float,
		p_fires_deployed_only := true) -> void:
	_deploy_override[unit] = Vector3(maxf(deploy_s, 0.05),
		maxf(undeploy_s, 0.05), 1.0 if p_fires_deployed_only else 0.0)


# ═══════════════════════════════════════════════════════════════════════════
# INTERNALS
# ═══════════════════════════════════════════════════════════════════════════

func _within_boarding_range(unit: int, transport: int) -> bool:
	var dx := entities.pos_x[transport] - entities.pos_x[unit]
	var dz := entities.pos_z[transport] - entities.pos_z[unit]
	return dx * dx + dz * dz <= BOARD_RADIUS_M * BOARD_RADIUS_M


func _complete_board(unit: int, transport: int) -> bool:
	if not entities.board(transport, unit):
		return false
	loads_completed += 1
	_log("%s boards %s (%d/%d slots)" % [_name(unit), _name(transport),
		slots_used(transport), entities.cargo_capacity[transport]])
	return true


## Where one disgorged unit stands. Deterministic ring outward from the hull,
## the SimEconomy._exit_point() pattern: 8 bearings per ring, nearer rings
## first, first spot whose ground suits the passenger and is clear of spots
## already handed out this ramp cycle. Empty when nothing within the search
## fits -- which is the mid-ocean refusal.
func _unload_spot(transport: int, unit: int, taken: Array) -> PackedFloat32Array:
	var tx := entities.pos_x[transport]
	var tz := entities.pos_z[transport]
	var wants_water: bool = entities.category[unit] == SimTypes.Category.SURFACE \
		or entities.category[unit] == SimTypes.Category.SUBSURFACE
	for ring in range(UNLOAD_RINGS):
		var r := UNLOAD_RING_BASE_M + float(ring) * UNLOAD_RING_STEP_M
		for k in range(8):
			var a := float(k) * PI * 0.25
			var x := tx + sin(a) * r
			var z := tz + cos(a) * r
			if terrain != null:
				if absf(x) > terrain.extent_x_m() * 0.5 \
						or absf(z) > terrain.extent_z_m() * 0.5:
					continue
				if terrain.is_water(x, z) != wants_water:
					continue
			var clash := false
			for s in taken:
				var v := s as Vector2
				var ddx := v.x - x
				var ddz := v.y - z
				if ddx * ddx + ddz * ddz \
						< UNLOAD_SPOT_CLEARANCE_M * UNLOAD_SPOT_CLEARANCE_M:
					clash = true
					break
			if not clash:
				return PackedFloat32Array([x, z])
	return PackedFloat32Array()


## disembark() copied the hull's y; put the unit on ITS OWN medium. The same
## spawn-like placement sanction disembark() itself has.
func _settle_altitude(unit: int) -> void:
	var cat := entities.category[unit]
	if cat == SimTypes.Category.SURFACE or cat == SimTypes.Category.SUBSURFACE:
		entities.pos_y[unit] = 0.0
	elif cat == SimTypes.Category.GROUND and terrain != null:
		entities.pos_y[unit] = maxf(
			terrain.ground_under(entities.pos_x[unit], entities.pos_z[unit]), 0.0)


func _drop_pending(unit: int) -> void:
	_pending_load.erase(unit)
	_pending_dest.erase(unit)


func _cancel_pending(unit: int, why: String) -> void:
	loads_cancelled += 1
	_log("load cancelled: %s -- %s" % [_name(unit), why])
	_drop_pending(unit)


func _def(unit: int) -> SimUnitDef:
	return economy.def_of(unit) if economy != null else null


func _name(unit: int) -> String:
	if unit < 0 or unit >= entities.count():
		return "unit %d" % unit
	return entities.names[unit]


func _log(line: String) -> void:
	event_log.append(line)
	if event_log.size() > max_log:
		event_log.pop_front()


func describe() -> String:
	return "transport: %d loaded, %d unloaded, %d cancelled, %d pending" % [
		loads_completed, unloads_completed, loads_cancelled,
		_pending_load.size()]
