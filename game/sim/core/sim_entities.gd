class_name SimEntities
extends RefCounted
## Units are indices into parallel arrays, not objects. docs/06, "Data layout".
##
## The sensor solve sweeps positions, RCS and mount heights for every candidate
## pair. Kept contiguous that sweep is cache-friendly; chased through node
## pointers it is not, and the frame budget disappears at a few hundred units.

## Waypoints reserved per unit. See `path_x` below for why it is fixed.
const MAX_PATH_POINTS := 32

## Cargo slots reserved per unit, for the same reason MAX_PATH_POINTS is fixed:
## a growable hold would allocate mid-fight and need a free list. 8 covers the
## docs/12 transports (an APC carries a squad or two, a landing craft a
## platoon); a hold that genuinely needs more is a stride bump here, not a new
## data structure.
const MAX_CARGO := 8

# ── hot fields, swept every solve ────────────────────────────────────────────
var pos_x := PackedFloat32Array()
var pos_y := PackedFloat32Array()   ## metres above the surface -- drives horizon
var pos_z := PackedFloat32Array()
var vel_x := PackedFloat32Array()
var vel_y := PackedFloat32Array()
var vel_z := PackedFloat32Array()
var rcs_m2 := PackedFloat32Array()
var ir_band := PackedFloat32Array()
var acoustic_db := PackedFloat32Array()
var visual_m2 := PackedFloat32Array()
var magnetic := PackedFloat32Array()
var mount_height_m := PackedFloat32Array()

# ── cold-ish fields ──────────────────────────────────────────────────────────
var faction := PackedInt32Array()
var category := PackedInt32Array()
var emcon := PackedInt32Array()
var alive := PackedInt32Array()          ## 1/0; index reuse is not attempted
var throttle := PackedFloat32Array()     ## 0..1, scales IR hard
var depth_m := PackedFloat32Array()      ## >0 = below surface (submarines)
var below_layer := PackedInt32Array()    ## 1 when beneath the thermocline
var jammer_power := PackedFloat32Array() ## 0 = not jamming
## A loud, short-lived acoustic event -- a torpedo leaving the tube, a hatch,
## a transient. docs/10 §7: "Firing is loud. Shooting reveals you." Modelled as
## a signature bump so the ordinary passive-sonar path hears it, rather than as
## a special case bolted onto the solver.
var acoustic_transient_db := PackedFloat32Array()
var acoustic_transient_s := PackedFloat32Array()
var names := PackedStringArray()

# ── damage state (docs/03) ───────────────────────────────────────────────────
## docs/03 is explicit that a health bar is the wrong model: "resolve WHAT IT
## HIT, not a subtraction from a health bar." So `structure` is not hit points.
## It is the residual integrity pool that soft targets, airframes and hulls run
## on, and that an armoured vehicle only loses once something has already
## PENETRATED. A Gen 1 round that fails against a Gen 3.5 glacis takes nothing
## off this pool, at any range, ever -- that is the cliff, and it is subtraction
## that would flatten it into a slope.
var damage_model := PackedInt32Array()      ## SimTypes.DamageModel
var structure_max := PackedFloat32Array()
var structure := PackedFloat32Array()
## Coarse armour scheme id, for UI grouping and for the AI's *observed* class
## inference. NOT the resolution input -- resolution reads the per-facet arrays
## below. -1 means unarmoured.
var armor_class := PackedInt32Array()
## Behind-armor effects as a bitmask of SimTypes.Component. A mobility-killed
## tank is alive, immobile, and still traverses its turret.
var components := PackedInt32Array()
## 0..1. Crew casualties degrade rate of fire, accuracy and reaction time
## rather than removing the unit.
var crew_efficiency := PackedFloat32Array()
## Per-facet armour, stride SimTypes.FACET_COUNT. Flat rather than an array of
## structs for the same reason everything else here is flat: the damage
## resolver reads two floats and an int per impact and nothing else.
var armor_mm := PackedFloat32Array()        ## line-of-sight thickness AFTER slope
var armor_type := PackedInt32Array()        ## SimTypes.ArmorType, per facet

# ── movement state ───────────────────────────────────────────────────────────
## Facing is authoritative here rather than inferred from velocity, because
## docs/03 needs it when the unit is STATIONARY -- a dug-in tank still has a
## front, and impact_facet() must be able to ask for it. Radians, 0 = +Z, and
## the same convention as bearing_rad(): atan2(dx, dz).
var heading_rad := PackedFloat32Array()
## The turret, tracked separately because docs/03's mobility kill leaves it
## working: "Immobilised. Turret still traverses -- it is now a pillbox."
var turret_rad := PackedFloat32Array()
var speed_ms := PackedFloat32Array()        ## current ground speed, m/s
var max_speed_ms := PackedFloat32Array()    ## m/s
var accel_ms2 := PackedFloat32Array()       ## m/s^2
var turn_rate_rads := PackedFloat32Array()  ## rad/s
var move_state := PackedInt32Array()        ## SimTypes.MoveState
var dest_x := PackedFloat32Array()          ## metres. Only meaningful when has_dest = 1
var dest_z := PackedFloat32Array()
var has_dest := PackedInt32Array()
## Fixed-capacity per-unit path slot. A growable arena would need a free list
## and would allocate during a fight; MAX_PATH_POINTS waypoints per unit is a
## flat 256 bytes and never allocates after add(). A route longer than that is
## a COARSE path the planner refines as the unit advances, which is what
## hierarchical pathfinding does anyway.
var path_x := PackedFloat32Array()          ## stride MAX_PATH_POINTS
var path_z := PackedFloat32Array()          ## stride MAX_PATH_POINTS
var path_len := PackedInt32Array()          ## waypoints stored, 0..MAX_PATH_POINTS
var path_cursor := PackedInt32Array()       ## index of the NEXT waypoint

# ── ownership and economy ────────────────────────────────────────────────────
## `faction` is which PICTURE this unit belongs to -- which track table its
## sensors feed and read. `owner` is which PLAYER pays for it. They are not the
## same thing: two allied players share a track table (docs/08 coalition,
## docs/09 §6) and therefore a faction, while keeping separate economies. Every
## economy and AI query is by OWNER; every sensor query is by FACTION.
var owner := PackedInt32Array()
var build_cost := PackedFloat32Array()      ## credits, one-off
var upkeep_per_min := PackedFloat32Array()  ## credits per minute of service
## docs/04. Litres and litres-per-minute. Range is not a stat -- it is fuel
## divided by burn, which is why a large modern army is a large fuel problem.
var fuel := PackedFloat32Array()
var fuel_capacity := PackedFloat32Array()
var burn_idle_lpm := PackedFloat32Array()
var burn_cruise_lpm := PackedFloat32Array()
var burn_combat_lpm := PackedFloat32Array()
## Buildings do not move and are captured or destroyed rather than killed.
var is_structure := PackedInt32Array()

# ── deployables, cargo and sorties (spine state) ─────────────────────────────
## SimTypes.DeployState. Every unit has one; only deployable roles ever leave
## MOBILE. Written by the deploy half of the transport system ONLY.
var deploy_state := PackedInt32Array()
## Seconds left in a DEPLOYING/UNDEPLOYING transition. Counted down by the
## transport/deploy system in its slot; meaningless while MOBILE or DEPLOYED.
var deploy_timer := PackedFloat32Array()
## THE CARGO MODEL, both directions in O(1) and nothing hashed:
##   carried_by[unit]  -> the transport it is aboard, -1 = on the map
##   cargo_slots[t*MAX_CARGO + k], k < cargo_len[t] -> the units aboard t,
##                                                     in boarding order
## The two are kept consistent by board()/disembark()/kill() below, which are
## the ONLY writers. See board() for what being aboard means.
var carried_by := PackedInt32Array()
var cargo_slots := PackedInt32Array()    ## stride MAX_CARGO, -1 = empty slot
var cargo_len := PackedInt32Array()
var cargo_capacity := PackedInt32Array() ## 0 = not a transport. Set at spawn
## Where an aircraft recovers: a unit index (airbase, helipad, carrier,
## amphib), -1 = none. Set at spawn by whoever spawns the aircraft; RE-set by
## the sortie system when the field is lost and d_home recomputes to the next
## nearest recovery point (docs/04, consequence 5).
var home_base := PackedInt32Array()
## SimTypes.SortieState. Written by the sortie system ONLY.
var sortie_state := PackedInt32Array()

## THE ORE CYCLE, SimHarvest's own columns and nobody else's. Kept here rather
## than in that layer for the same reason every other per-unit column is: one
## array per fact, indexed by entity, so a save is a snapshot of columns and
## not a walk of object graphs.
var harvest_state := PackedInt32Array()   ## SimHarvest.State
var harvest_load := PackedFloat32Array()  ## credits aboard
var harvest_target := PackedInt32Array()  ## ore field index, or dropoff entity

## index -> Array[SimSensorDef]
var sensors: Dictionary = {}

var _count: int = 0


func count() -> int:
	return _count


## Create a unit. Every new field defaults to something harmless -- an
## unarmoured, immobile, free unit owned by its own faction -- so the 161
## existing callers keep working untouched and a caller that cares configures
## it afterwards with the setters below.
func add(unit_name: String, p_faction: int, x: float, y: float, z: float,
		sig: SimSignature, unit_sensors: Array = [],
		p_category := SimTypes.Category.GROUND,
		p_mount_height := -1.0, p_owner := -1) -> int:
	var i := _count
	pos_x.append(x); pos_y.append(y); pos_z.append(z)
	vel_x.append(0.0); vel_y.append(0.0); vel_z.append(0.0)
	rcs_m2.append(sig.rcs_m2)
	ir_band.append(sig.ir_band)
	acoustic_db.append(sig.acoustic_db)
	visual_m2.append(sig.visual_m2)
	magnetic.append(sig.magnetic)
	# A unit's own mount height defaults to the tallest sensor it carries.
	var mh := p_mount_height
	if mh < 0.0:
		mh = 0.0
		for s in unit_sensors:
			mh = maxf(mh, (s as SimSensorDef).mount_height_m)
	mount_height_m.append(mh)
	faction.append(p_faction)
	category.append(p_category)
	emcon.append(SimTypes.Emcon.RADIATE)
	alive.append(1)
	throttle.append(0.5)
	depth_m.append(0.0)
	below_layer.append(0)
	jammer_power.append(0.0)
	acoustic_transient_db.append(0.0)
	acoustic_transient_s.append(0.0)
	names.append(unit_name)

	# damage
	damage_model.append(SimTypes.DamageModel.UNARMORED)
	structure_max.append(100.0)
	structure.append(100.0)
	armor_class.append(-1)
	components.append(SimTypes.Component.NONE)
	crew_efficiency.append(1.0)
	for _f in range(SimTypes.FACET_COUNT):
		armor_mm.append(0.0)
		armor_type.append(SimTypes.ArmorType.NONE)

	# movement
	heading_rad.append(0.0)
	turret_rad.append(0.0)
	speed_ms.append(0.0)
	max_speed_ms.append(0.0)
	accel_ms2.append(0.0)
	turn_rate_rads.append(0.0)
	move_state.append(SimTypes.MoveState.IDLE)
	dest_x.append(0.0)
	dest_z.append(0.0)
	has_dest.append(0)
	for _k in range(MAX_PATH_POINTS):
		path_x.append(0.0)
		path_z.append(0.0)
	path_len.append(0)
	path_cursor.append(0)

	# ownership and economy
	owner.append(p_owner if p_owner >= 0 else p_faction)
	build_cost.append(0.0)
	upkeep_per_min.append(0.0)
	fuel.append(0.0)
	fuel_capacity.append(0.0)
	burn_idle_lpm.append(0.0)
	burn_cruise_lpm.append(0.0)
	burn_combat_lpm.append(0.0)
	is_structure.append(0)

	# deployables, cargo and sorties
	deploy_state.append(SimTypes.DeployState.MOBILE)
	deploy_timer.append(0.0)
	carried_by.append(-1)
	for _c in range(MAX_CARGO):
		cargo_slots.append(-1)
	cargo_len.append(0)
	cargo_capacity.append(0)
	home_base.append(-1)
	sortie_state.append(SimTypes.SortieState.GROUNDED)
	harvest_state.append(0)
	harvest_load.append(0.0)
	harvest_target.append(-1)

	sensors[i] = unit_sensors
	_count += 1
	return i


func set_velocity(i: int, vx: float, vy: float, vz: float) -> void:
	vel_x[i] = vx; vel_y[i] = vy; vel_z[i] = vz


func set_position(i: int, x: float, y: float, z: float) -> void:
	pos_x[i] = x; pos_y[i] = y; pos_z[i] = z


## Remove a unit from the world. SimDamage owns the decision to call this;
## nothing else should. Zeroing velocity matters -- a dead unit that keeps its
## last velocity is still integrated by _integrate() and drifts off the map,
## and its corpse would keep leading a projectile that is chasing it.
func kill(i: int) -> void:
	alive[i] = 0
	structure[i] = 0.0
	move_state[i] = SimTypes.MoveState.DEAD
	speed_ms[i] = 0.0
	vel_x[i] = 0.0; vel_y[i] = 0.0; vel_z[i] = 0.0
	has_dest[i] = 0
	path_len[i] = 0
	path_cursor[i] = 0
	# THE CARGO DIES WITH THE HULL. A carried unit is off the map with nowhere
	# to bail out to, so a transport kill is a cargo kill -- recursively, for a
	# loaded landing craft aboard an amphib. The hold is emptied FIRST so the
	# recursion cannot re-enter it, and so a passenger's own kill() does not
	# mutate a manifest that is mid-iteration.
	if cargo_len[i] > 0:
		var base := i * MAX_CARGO
		var n := cargo_len[i]
		cargo_len[i] = 0
		for k in range(n):
			var c := cargo_slots[base + k]
			cargo_slots[base + k] = -1
			if c >= 0 and alive[c] == 1:
				kill(c)
	# A dying passenger leaves its carrier's manifest; a passenger dying
	# because the carrier is dying finds the manifest already emptied above.
	if carried_by[i] >= 0:
		_remove_cargo(carried_by[i], i)
		carried_by[i] = -1


func is_alive(i: int) -> bool:
	return i >= 0 and i < _count and alive[i] == 1


## Ground range in kilometres. The sim works in metres; sensor ranges are quoted
## in kilometres because that is how the source material quotes them.
func range_km(a: int, b: int) -> float:
	var dx := pos_x[b] - pos_x[a]
	var dy := pos_y[b] - pos_y[a]
	var dz := pos_z[b] - pos_z[a]
	return sqrt(dx * dx + dy * dy + dz * dz) / 1000.0


func bearing_rad(a: int, b: int) -> float:
	return atan2(pos_x[b] - pos_x[a], pos_z[b] - pos_z[a])


## Aspect-corrected RCS. Front/side/rear differ, often by 10x on aircraft
## (docs/02 §1). Cheap approximation: nose-on and tail-on are smaller.
func effective_rcs(target: int, observer: int) -> float:
	var base := rcs_m2[target]
	var vx := vel_x[target]
	var vz := vel_z[target]
	var speed := sqrt(vx * vx + vz * vz)
	if speed < 0.5:
		return base
	# angle between the target's heading and the line to the observer
	var tx := pos_x[observer] - pos_x[target]
	var tz := pos_z[observer] - pos_z[target]
	var tl := sqrt(tx * tx + tz * tz)
	if tl < 1e-6:
		return base
	var cos_aspect: float = clampf((vx * tx + vz * tz) / (speed * tl), -1.0, 1.0)
	# |cos| near 1 means nose-on or tail-on: smallest return. Beam-on is largest.
	var beam := 1.0 - absf(cos_aspect)
	return base * (0.35 + 1.30 * beam)


## IR scales hard with engine power; afterburner is a flare.
func effective_ir(target: int) -> float:
	var t: float = clampf(throttle[target], 0.0, 1.2)
	return ir_band[target] * (0.15 + 2.4 * t * t)


## Radiated noise rises steeply with shaft RPM. A ship at flank speed is deaf;
## a submarine at flank speed is loud (docs/02 §8.4).
func effective_acoustic_db(target: int) -> float:
	var v := sqrt(vel_x[target] * vel_x[target] + vel_z[target] * vel_z[target])
	var knots := v * 1.94384
	var db := acoustic_db[target] + 12.0 * log(maxf(knots, 1.0)) / log(10.0)
	if acoustic_transient_s[target] > 0.0:
		db = maxf(db, acoustic_transient_db[target])
	return db


## Raise a transient. The loudest wins; they do not stack.
func add_acoustic_transient(i: int, db: float, seconds: float) -> void:
	if db >= acoustic_transient_db[i] or acoustic_transient_s[i] <= 0.0:
		acoustic_transient_db[i] = db
	acoustic_transient_s[i] = maxf(acoustic_transient_s[i], seconds)


func decay_transients(dt: float) -> void:
	for i in range(_count):
		if acoustic_transient_s[i] > 0.0:
			acoustic_transient_s[i] -= dt
			if acoustic_transient_s[i] <= 0.0:
				acoustic_transient_db[i] = 0.0


## Is this unit radiating anything an ESM receiver could hear? A unit aboard a
## transport is not: its sensors are stowed with it (see board()).
func is_emitting(i: int) -> bool:
	if emcon[i] == SimTypes.Emcon.SILENT or carried_by[i] >= 0:
		return false
	if jammer_power[i] > 0.0:
		return true
	for s in sensors.get(i, []):
		var sd := s as SimSensorDef
		if sd.emits and not sd.is_passive():
			return true
	return false


## Total radiated power an ESM receiver sees, used for the one-way law.
func emitted_power(i: int) -> float:
	if emcon[i] == SimTypes.Emcon.SILENT or carried_by[i] >= 0:
		return 0.0
	var p := 0.0
	for s in sensors.get(i, []):
		var sd := s as SimSensorDef
		if sd.emits and not sd.is_passive():
			# Reference range is a decent proxy for transmitted power.
			p += sd.reference_range_km / 100.0
	p += jammer_power[i]
	if emcon[i] == SimTypes.Emcon.RECEIVE:
		p *= 0.25   # intermittent: brief, hard-to-classify hits
	return p


# ═══════════════════════════════════════════════════════════════════════════
# ACCESSORS FOR THE MISSING SYSTEMS
#
# MUTATION OWNERSHIP. Every field above has exactly one writer during a tick,
# and the tick order in sim_world.gd is what makes that safe. Writing outside
# your slot is the bug class this table exists to prevent:
#
#   pos_x/pos_y/pos_z ........ SimWorld._integrate() ONLY
#   vel_*, heading_rad, speed_ms, move_state, path_*, dest_*, has_dest
#                              SimMovement ONLY
#   turret_rad ............... SimWeapons (turret traverse) ONLY
#   structure, components, crew_efficiency, alive
#                              SimDamage ONLY
#   armor_mm, armor_type, armor_class, damage_model, structure_max,
#   build_cost, upkeep_per_min, fuel_capacity, burn_*, max_speed_ms,
#   accel_ms2, turn_rate_rads
#                              set once at spawn, by whoever spawns the unit
#   fuel ..................... SimEconomy (logistics) ONLY
#   owner .................... set at spawn; changed only on capture
#   emcon, throttle, jammer_power, depth_m
#                              orders / EW layer, as today
#   deploy_state, deploy_timer
#                              the transport/deploy system ONLY, in slot 3.5
#   carried_by, cargo_slots, cargo_len
#                              board() / disembark() / kill() ONLY -- called
#                              from the transport slot, and kill() by SimDamage
#   cargo_capacity ........... set once at spawn, by whoever spawns the unit
#   home_base ................ set at spawn; re-set by the sortie system when
#                              a recovery point is lost (docs/04)
#   sortie_state ............. the sortie system ONLY, in slot 3.7
#
# Anything reading a field it does not own reads LAST TICK's value if it runs
# before that owner's slot, and THIS tick's if it runs after. That is the whole
# reason the slot order in sim_world.gd is written down and justified.
# ═══════════════════════════════════════════════════════════════════════════

# ── damage state ─────────────────────────────────────────────────────────────

## Configure a unit's survivability. `facet_mm` and `facet_types` are indexed by
## SimTypes.Facet and must be FACET_COUNT long; pass empty arrays for anything
## that is not an armoured vehicle. Thickness is line-of-sight RHA-equivalent
## millimetres AFTER slope, exactly as docs/03 quotes it.
func set_damage_profile(i: int, model: int, max_structure: float,
		facet_mm: Array = [], facet_types: Array = [],
		p_armor_class := -1) -> void:
	damage_model[i] = model
	structure_max[i] = max_structure
	structure[i] = max_structure
	armor_class[i] = p_armor_class
	var base := i * SimTypes.FACET_COUNT
	for f in range(SimTypes.FACET_COUNT):
		armor_mm[base + f] = float(facet_mm[f]) if f < facet_mm.size() else 0.0
		armor_type[base + f] = int(facet_types[f]) if f < facet_types.size() \
			else SimTypes.ArmorType.NONE


## Base line-of-sight thickness of one facet, in millimetres of RHA equivalent.
## This is the RAW number; run it through SimArmor.effective_mm() with the
## incoming damage class to get what the round actually has to beat.
func armor_at(i: int, facet: int) -> float:
	return armor_mm[i * SimTypes.FACET_COUNT + facet]


## SimTypes.ArmorType of one facet. Different facets legitimately carry
## different types -- composite front, plain RHA sides -- which is precisely
## why flanking works.
func armor_type_at(i: int, facet: int) -> int:
	return armor_type[i * SimTypes.FACET_COUNT + facet]


func set_armor_facet(i: int, facet: int, base_mm: float, a_type: int) -> void:
	var k := i * SimTypes.FACET_COUNT + facet
	armor_mm[k] = base_mm
	armor_type[k] = a_type


## Health as a 0..1 fraction. For the HUD and for the AI's *own* forces only --
## docs/09 §1.2 lists "knowing a unit is at 30%" as a leak, so this must never
## be reachable through a track.
func structure_fraction(i: int) -> float:
	if structure_max[i] <= 0.0:
		return 0.0
	return clampf(structure[i] / structure_max[i], 0.0, 1.0)


func has_component_loss(i: int, component: int) -> bool:
	return (components[i] & component) != 0


## Record a behind-armor effect. Idempotent: losing mobility twice is losing it
## once, which keeps the outcome independent of how many rounds arrive.
func lose_component(i: int, component: int) -> void:
	components[i] |= component
	if component & SimTypes.Component.MOBILITY:
		move_state[i] = SimTypes.MoveState.IMMOBILE
		speed_ms[i] = 0.0
		vel_x[i] = 0.0; vel_z[i] = 0.0


## Can this unit shoot at all? A firepower kill and a catastrophic kill both
## say no, and so does being aboard a transport -- cargo does not fight from
## the hold. Whether a DEPLOYABLE may fire in its current deploy_state is the
## deploy system's per-role knowledge and is deliberately NOT gated here: a
## tank fires while MOBILE, towed artillery only while DEPLOYED.
## Weapons must consult this before the docs/02 track-quality gate --
## "may I shoot?" has a mechanical half as well as an informational one.
func can_fire(i: int) -> bool:
	return alive[i] == 1 \
		and carried_by[i] < 0 \
		and not has_component_loss(i, SimTypes.Component.FIREPOWER) \
		and not has_component_loss(i, SimTypes.Component.CATASTROPHIC)


## Can this unit move under its own power? False when mobility-killed or dry,
## when aboard a transport (the transport moves, the cargo rides), and in any
## deploy state but MOBILE -- an emplaced battery must undeploy before it can
## take a move order. SimMovement _halt()s a unit that fails this but KEEPS its
## orders, so undeploying / unloading / refuelling lets the order resume.
func can_move(i: int) -> bool:
	return alive[i] == 1 and is_structure[i] == 0 \
		and carried_by[i] < 0 \
		and deploy_state[i] == SimTypes.DeployState.MOBILE \
		and not has_component_loss(i, SimTypes.Component.MOBILITY) \
		and max_speed_ms[i] > 0.0 \
		and (fuel_capacity[i] <= 0.0 or fuel[i] > 0.0)


## Can this unit still produce a fire-control track of its own? docs/03 calls
## sensor kill "the most valuable row in this table" because it is the join
## between armour and detection: the unit is alive, and blind.
func sensors_intact(i: int) -> bool:
	return alive[i] == 1 and not has_component_loss(i, SimTypes.Component.SENSORS)


# ── movement state ───────────────────────────────────────────────────────────

## Set a destination in world metres. This only records the ORDER -- it does not
## plan a route and does not move anything. SimMovement reads it in the movement
## slot, plans, and writes the path.
func set_destination(i: int, x: float, z: float) -> void:
	dest_x[i] = x
	dest_z[i] = z
	has_dest[i] = 1


func clear_destination(i: int) -> void:
	has_dest[i] = 0
	path_len[i] = 0
	path_cursor[i] = 0
	speed_ms[i] = 0.0
	vel_x[i] = 0.0; vel_z[i] = 0.0
	if move_state[i] == SimTypes.MoveState.MOVING:
		move_state[i] = SimTypes.MoveState.IDLE


## Store a planned route. `points` is a flat [x0, z0, x1, z1, ...] array in
## metres. Anything past MAX_PATH_POINTS waypoints is DISCARDED, not clamped
## silently into nonsense -- the planner is expected to store a coarse route and
## re-plan as the unit advances. Returns how many waypoints were stored.
func set_path(i: int, points: PackedFloat32Array) -> int:
	var n: int = mini(points.size() / 2, MAX_PATH_POINTS)
	var base := i * MAX_PATH_POINTS
	for k in range(n):
		path_x[base + k] = points[k * 2]
		path_z[base + k] = points[k * 2 + 1]
	path_len[i] = n
	path_cursor[i] = 0
	return n


func path_point_x(i: int, k: int) -> float:
	return path_x[i * MAX_PATH_POINTS + k]


func path_point_z(i: int, k: int) -> float:
	return path_z[i * MAX_PATH_POINTS + k]


## The waypoint the unit is currently steering at, as [x, z], or an empty array
## when the path is finished or absent.
func current_waypoint(i: int) -> PackedFloat32Array:
	if path_cursor[i] >= path_len[i]:
		return PackedFloat32Array()
	var k := i * MAX_PATH_POINTS + path_cursor[i]
	return PackedFloat32Array([path_x[k], path_z[k]])


## Consume the current waypoint. Returns true while waypoints remain.
func advance_waypoint(i: int) -> bool:
	path_cursor[i] += 1
	return path_cursor[i] < path_len[i]


func has_path(i: int) -> bool:
	return path_cursor[i] < path_len[i]


## Configure the mobility a unit was built with. Speeds in m/s, turn rate in
## rad/s -- the sim is metric and per-second throughout; km/h belongs in the
## unit data files and the HUD, not here.
func set_mobility(i: int, p_max_speed_ms: float, p_accel_ms2: float,
		p_turn_rate_rads: float) -> void:
	max_speed_ms[i] = p_max_speed_ms
	accel_ms2[i] = p_accel_ms2
	turn_rate_rads[i] = p_turn_rate_rads


## Heading toward a world point, in the same convention as bearing_rad():
## atan2(dx, dz), 0 = +Z. Provided here so movement and damage cannot disagree
## about which way a unit is facing.
func heading_toward(i: int, x: float, z: float) -> float:
	return atan2(x - pos_x[i], z - pos_z[i])


# ── deployables, cargo and sorties ───────────────────────────────────────────
#
# WHAT BEING CARRIED MEANS -- the doctrine, in one place, implemented across
# exactly four seams:
#
#   ALIVE, OFF THE MAP. carried_by[i] >= 0. The unit keeps its structure,
#   components, fuel and orders; it is not a ghost, it is stowed.
#
#   NOT SENSED, AND NOT SENSING. The sensor solver skips a carried unit both
#   as observer and as target, and is_emitting()/emitted_power() report
#   nothing, so it feeds no track table and appears in none. Its OLD tracks
#   age out exactly as if it had gone silent behind a hill.
#
#   NOT TARGETABLE. It produces no fresh tracks, so nothing can be ordered
#   against it; a round already in flight toward it wastes itself
#   (SimWorld._combat_slot discards arrivals on carried units). Killing the
#   cargo means killing the transport.
#
#   NOT MOVING. can_move() and can_fire() are false; velocity is zeroed at
#   boarding; its POSITION RIDES THE TRANSPORT -- SimWorld._integrate() snaps
#   it to the carrier every tick, so an unload disgorges where the hull is.
#
#   IF THE TRANSPORT DIES, THE CARGO DIES. kill() cascades through the hold,
#   nested holds included. No bail-out is modelled.
#
# board() and disembark() are STATE CHANGES, not orders: range checks, ramp
# times and where the disgorged unit may legally stand belong to the transport
# system that calls them from slot 3.5.

## How many units a transport can hold. Clamped to the reserved stride; 0
## (the default) means "not a transport".
func set_cargo_capacity(i: int, capacity: int) -> void:
	cargo_capacity[i] = clampi(capacity, 0, MAX_CARGO)


func cargo_count(i: int) -> int:
	return cargo_len[i]


func cargo_space(i: int) -> int:
	return cargo_capacity[i] - cargo_len[i]


## The k-th unit aboard, in boarding order. -1 past the end.
func cargo_at(i: int, k: int) -> int:
	if k < 0 or k >= cargo_len[i]:
		return -1
	return cargo_slots[i * MAX_CARGO + k]


## Everything aboard, in boarding order. A copy; mutating it changes nothing.
func cargo_of(i: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	var base := i * MAX_CARGO
	for k in range(cargo_len[i]):
		out.append(cargo_slots[base + k])
	return out


func is_aboard(i: int) -> bool:
	return i >= 0 and i < _count and carried_by[i] >= 0


## The hull actually on the map: a unit's outermost carrier, itself when it is
## not aboard anything. Bounded walk, so a corrupted chain cannot hang a tick.
func top_carrier(i: int) -> int:
	var t := i
	var guard := 0
	while carried_by[t] >= 0 and guard < MAX_CARGO * 2:
		t = carried_by[t]
		guard += 1
	return t


## Put `unit` aboard `transport`. Validates STATE only -- both alive, the hold
## has room, no self-load, no cycle (a transport cannot end up aboard its own
## cargo). Proximity and boarding time are the transport system's to enforce
## BEFORE calling this. Nesting is legal: a loaded landing craft may board an
## amphib. Returns false when the state does not allow it.
func board(transport: int, unit: int) -> bool:
	if not is_alive(transport) or not is_alive(unit):
		return false
	if transport == unit or carried_by[unit] >= 0:
		return false
	if cargo_len[transport] >= cargo_capacity[transport]:
		return false
	# No cycles: walk up from the transport; finding `unit` above it means
	# this load would swallow the carrier into its own cargo.
	var t := transport
	var guard := 0
	while t >= 0 and guard < MAX_CARGO * 2:
		if t == unit:
			return false
		t = carried_by[t]
		guard += 1
	cargo_slots[transport * MAX_CARGO + cargo_len[transport]] = unit
	cargo_len[transport] += 1
	carried_by[unit] = transport
	# Off the map: stationary, destination and path dropped (the ORDER queue in
	# SimMovement survives -- a queued move resumes after unloading). Writing
	# these movement-owned fields here is sanctioned because slot 3.5 runs
	# before the movement slot, which then sees a unit with nothing to do.
	speed_ms[unit] = 0.0
	vel_x[unit] = 0.0; vel_y[unit] = 0.0; vel_z[unit] = 0.0
	clear_destination(unit)
	return true


## Take `unit` out of `transport` and place it at x/z. The caller chooses the
## spot and is responsible for it being sane (passable, adjacent to the hull);
## y is copied from the transport and the caller corrects it to the ground.
## This position write is spawn-like placement, the same sanction
## SimEconomy._place() has. Returns false when `unit` is not aboard `transport`.
func disembark(transport: int, unit: int, x: float, z: float) -> bool:
	if unit < 0 or unit >= _count or carried_by[unit] != transport:
		return false
	_remove_cargo(transport, unit)
	carried_by[unit] = -1
	set_position(unit, x, pos_y[transport], z)
	return true


## Drop one unit from a hold's manifest, preserving boarding order. Tolerant of
## absence, because kill() empties a dying hold before its passengers die.
func _remove_cargo(transport: int, unit: int) -> void:
	var base := transport * MAX_CARGO
	var n := cargo_len[transport]
	var found := false
	for k in range(n):
		if found:
			cargo_slots[base + k - 1] = cargo_slots[base + k]
		elif cargo_slots[base + k] == unit:
			found = true
	if found:
		cargo_slots[base + n - 1] = -1
		cargo_len[transport] = n - 1


## Where this aircraft recovers. -1 clears it -- a stranded aircraft is one
## whose home_base is -1 or dead, and re-homing it is the sortie system's job.
func set_home_base(i: int, base_unit: int) -> void:
	home_base[i] = base_unit


func home_base_of(i: int) -> int:
	return home_base[i]


# ── ownership and economy ────────────────────────────────────────────────────

## Every index owned by a player, alive, ascending. ASCENDING MATTERS: docs/06
## forbids iterating an unordered container anywhere the order affects outcome,
## and this array is what the AI and the economy both loop over.
func indices_of_owner(p_owner: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(_count):
		if alive[i] == 1 and owner[i] == p_owner:
			out.append(i)
	return out


## Every index in a faction -- i.e. sharing one track table. A coalition of two
## players is two owners and one faction.
func indices_of_faction(p_faction: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in range(_count):
		if alive[i] == 1 and faction[i] == p_faction:
			out.append(i)
	return out


func set_economy_profile(i: int, cost: float, upkeep: float,
		p_fuel_capacity := 0.0,
		p_burn_idle_lpm := 0.0, p_burn_cruise_lpm := 0.0,
		p_burn_combat_lpm := 0.0) -> void:
	build_cost[i] = cost
	upkeep_per_min[i] = upkeep
	fuel_capacity[i] = p_fuel_capacity
	fuel[i] = p_fuel_capacity
	burn_idle_lpm[i] = p_burn_idle_lpm
	burn_cruise_lpm[i] = p_burn_cruise_lpm
	burn_combat_lpm[i] = p_burn_combat_lpm


## Litres per minute at the unit's current move state. docs/04's four rates
## collapse to three on the ground; afterburner is the AIRFRAME case and is
## handled by scaling burn_combat with throttle.
func burn_rate_lpm(i: int) -> float:
	match move_state[i]:
		SimTypes.MoveState.MOVING:
			return burn_cruise_lpm[i]
		SimTypes.MoveState.COMBAT:
			if category[i] == SimTypes.Category.AIR and throttle[i] > 0.95:
				# docs/04: afterburner is five to ten times dry thrust. That
				# single ratio is what makes "do I commit at full speed?" a
				# recurring question.
				return burn_combat_lpm[i] * 7.0
			return burn_combat_lpm[i]
		SimTypes.MoveState.DEAD:
			return 0.0
	return burn_idle_lpm[i]


## docs/04: "range_remaining = fuel_current / burn_per_km_at_cruise". Metres.
## Returns INF for a unit that carries no fuel tank at all, so callers that do
## not care about logistics are not forced to special-case it.
func range_remaining_m(i: int) -> float:
	if fuel_capacity[i] <= 0.0:
		return INF
	if burn_cruise_lpm[i] <= 0.0 or max_speed_ms[i] <= 0.0:
		return INF
	var minutes := fuel[i] / burn_cruise_lpm[i]
	return minutes * 60.0 * max_speed_ms[i]


## docs/04: combat radius is roughly a third of ferry range, because you have to
## get back, with a reserve and an allowance for fighting when you arrive. This
## is the number the tactical map draws a ring with.
func combat_radius_m(i: int) -> float:
	var r := range_remaining_m(i)
	return r if is_inf(r) else r * 0.35


# ═══════════════════════════════════════════════════════════════════════════
# SAVE / LOAD (SimSave). Every parallel array, bit-exact, plus the per-unit
# sensor lists. The generic property capture in SimSave picks up every packed
# array declared above -- a new column added to this store is saved the moment
# it exists, with no field list here to go stale.
# ═══════════════════════════════════════════════════════════════════════════

func to_dict() -> Dictionary:
	var d := SimSave.enc_props(self, ["sensors"])
	d["_count"] = _count
	var sens := {}
	for i in sensors:
		var defs: Array = []
		for s in sensors[i]:
			defs.append(SimSave.enc_props(s))
		sens[str(i)] = defs
	d["sensors"] = sens
	return d


func from_dict(d: Dictionary) -> void:
	SimSave.dec_props(self, d)
	_count = int(d["_count"])
	sensors.clear()
	var sens: Dictionary = d.get("sensors", {})
	for k in sens:
		var defs: Array = []
		for sd in (sens[k] as Array):
			var def := SimSensorDef.new()
			SimSave.dec_props(def, sd)
			defs.append(def)
		sensors[int(String(k))] = defs
