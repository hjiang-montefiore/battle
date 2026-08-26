class_name SimMovement
extends RefCounted
## Path planning and steering. The whole of it lives in the sim, not in the
## scene -- proving_ground.gd is a viewer and must end up calling order_move()
## instead of placing units on a formation grid itself.
##
## ══ THIS IS A STUB. ══
## Nothing here plans or steers yet. The signatures are final.
##
## OWNERSHIP: the only writer of vel_x/vel_y/vel_z, heading_rad, speed_ms,
## move_state, dest_*, has_dest and the path arrays. It MUST NOT write pos_* --
## SimWorld._integrate() owns position, and it runs immediately after this slot.
## Writing velocity and letting one place integrate it is what keeps the tick
## order meaningful and the replay hash stable.
##
## DETERMINISM: docs/06 forbids Godot physics and randf(). A* tie-breaks must be
## resolved by a stable rule (lowest cell index wins), never by whichever
## neighbour a hash set happened to yield.


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


func _init(store: SimEntities, terrain_ref: SimTerrain = null,
		seeded: SimRng = null) -> void:
	entities = store
	terrain = terrain_ref
	rng = seeded if seeded != null else SimRng.new(0x4D0E)


func set_terrain(t: SimTerrain) -> void:
	terrain = t


# ═══════════════════════════════════════════════════════════════════════════
# THE API
# ═══════════════════════════════════════════════════════════════════════════

## Order a unit to a world point, in METRES. Records the destination and
## requests a replan; it does not plan inline, so a hundred units ordered on one
## frame spread their planning across the replan budget.
## Returns false if the unit cannot move at all (dead, mobility-killed, dry,
## or a structure).
func order_move(unit: int, x_m: float, z_m: float) -> bool:
	if not entities.can_move(unit):
		return false
	entities.set_destination(unit, x_m, z_m)
	return true


## Cancel movement. Idempotent.
func order_stop(unit: int) -> void:
	entities.clear_destination(unit)


## Plan a route from a unit's current position to a world point. Returns a flat
## [x0, z0, x1, z1, ...] array in metres, EMPTY if no route exists.
##
## MUST: respect terrain -- water for ground units, slope limits, and static
## obstacles; return a COARSE route when the full one exceeds
## SimEntities.MAX_PATH_POINTS, to be refined as the unit advances; be
## deterministic for a given start, goal and terrain.
func plan_path(unit: int, x_m: float, z_m: float) -> PackedFloat32Array:
	return PackedFloat32Array()


## Formation destinations for a group ordered to one point. Returns a flat
## [x0, z0, ...] array, one pair per unit, in the SAME ORDER as `units`.
## proving_ground.gd already computes a formation grid in the presentation
## layer; that code moves here, because docs/06 puts gameplay in the sim.
func formation_slots(units: PackedInt32Array, x_m: float, z_m: float,
		spacing_m: float = 14.0) -> PackedFloat32Array:
	return PackedFloat32Array()


## Can a ground unit stand at this point? Water, cliffs and footprints say no.
func is_passable(unit: int, x_m: float, z_m: float) -> bool:
	return true


## The tick slot. Every simulation tick, before SimWorld._integrate().
## MUST: spend the replan budget on units with has_dest and no path; follow the
## path by turning at turn_rate_rads and accelerating at accel_ms2 toward
## max_speed_ms; write vel_x/vel_z and heading_rad; advance the waypoint cursor
## within arrive_radius_m; clear the destination on arrival; hold vel at zero
## for anything can_move() rejects.
func step(dt: float) -> void:
	pass


func has_arrived(unit: int) -> bool:
	return entities.has_dest[unit] == 0 and entities.path_len[unit] == 0


## True once this class actually steers. Reported honestly by SimWorld.
func is_implemented() -> bool:
	return false
