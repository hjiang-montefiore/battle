class_name SimOwnForcesView
extends RefCounted
## The AI's window onto its OWN army, and nothing else. docs/09 §1.
##
## This class is the structural half of the cardinal rule. docs/09 is explicit
## that access control by convention will fail -- so the AI module is never
## handed a SimEntities at all. It is handed one of these, bound to one owner
## id at construction, and EVERY accessor refuses an index that owner does not
## hold. There is no method here that takes an enemy index and returns anything.
##
## docs/09 §1 whitelist, in full:
##     its own units and their state          <- this class
##     its own economy, production, epoch      <- SimEconomy, own id only
##     FactionTrackTable[ its own faction ]    <- SimAiWorldView.tracks
##     the terrain                             <- maps are public
## That is the complete list. Nothing else is reachable from here.
##
## Note the deliberate asymmetry: structure_fraction() works on your own units
## and cannot be asked about anyone else's, because docs/09 §1.2 lists "knowing
## a unit is at 30%" as a leak. Against an enemy the AI gets what observation
## gives -- burning, immobile, smoking -- through the track table, never a
## number.

var _e: SimEntities
var _owner: int
var _faction: int

## Every refused query is counted rather than silently swallowed. A leak test
## that watches this number can prove the fence is load-bearing; a spike in a
## real match means an AI is groping at indices it should not have.
var denied_queries: int = 0


func _init(store: SimEntities, owner_id: int, faction_id: int) -> void:
	_e = store
	_owner = owner_id
	_faction = faction_id


func owner_id() -> int:
	return _owner


## Which picture this AI reads. Allied players share one.
func faction_id() -> int:
	return _faction


## True only for a living unit this player owns.
func owns(i: int) -> bool:
	if i < 0 or i >= _e.count():
		return false
	return _e.alive[i] == 1 and _e.owner[i] == _owner


func _allow(i: int) -> bool:
	if owns(i):
		return true
	denied_queries += 1
	return false


## Own units, alive, ascending. The AI's only enumeration -- there is no
## all_units() and there must never be one.
func indices() -> PackedInt32Array:
	return _e.indices_of_owner(_owner)


func count() -> int:
	return indices().size()


# ── own-unit state. Every one refuses a foreign index. ──────────────────────

func position(i: int) -> PackedFloat32Array:
	if not _allow(i):
		return PackedFloat32Array([0.0, 0.0, 0.0])
	return PackedFloat32Array([_e.pos_x[i], _e.pos_y[i], _e.pos_z[i]])


func velocity(i: int) -> PackedFloat32Array:
	if not _allow(i):
		return PackedFloat32Array([0.0, 0.0, 0.0])
	return PackedFloat32Array([_e.vel_x[i], _e.vel_y[i], _e.vel_z[i]])


func heading(i: int) -> float:
	return _e.heading_rad[i] if _allow(i) else 0.0


func category(i: int) -> int:
	return _e.category[i] if _allow(i) else -1


func unit_name(i: int) -> String:
	return _e.names[i] if _allow(i) else ""


func structure_fraction(i: int) -> float:
	return _e.structure_fraction(i) if _allow(i) else 0.0


func components_lost(i: int) -> int:
	return _e.components[i] if _allow(i) else 0


func can_fire(i: int) -> bool:
	return _e.can_fire(i) if _allow(i) else false


func can_move(i: int) -> bool:
	return _e.can_move(i) if _allow(i) else false


func sensors_intact(i: int) -> bool:
	return _e.sensors_intact(i) if _allow(i) else false


func move_state(i: int) -> int:
	return _e.move_state[i] if _allow(i) else SimTypes.MoveState.DEAD


func emcon(i: int) -> int:
	return _e.emcon[i] if _allow(i) else SimTypes.Emcon.SILENT


func max_speed_ms(i: int) -> float:
	return _e.max_speed_ms[i] if _allow(i) else 0.0


func is_structure(i: int) -> bool:
	return _e.is_structure[i] == 1 if _allow(i) else false


## docs/04: the number a commander actually needs is combat radius, and it
## updates live as fuel burns. The AI gets the same number the player's
## tactical map draws a ring with.
func combat_radius_m(i: int) -> float:
	return _e.combat_radius_m(i) if _allow(i) else 0.0


func fuel_fraction(i: int) -> float:
	if not _allow(i) or _e.fuel_capacity[i] <= 0.0:
		return 1.0
	return clampf(_e.fuel[i] / _e.fuel_capacity[i], 0.0, 1.0)


## Is this unit radiating? Own EMCON discipline is a decision the AI has to
## make (docs/09 §2), so it must be able to see what it is currently doing.
func is_emitting(i: int) -> bool:
	return _e.is_emitting(i) if _allow(i) else false


## Range in kilometres between two of the AI's OWN units. Deliberately not a
## range-to-anything: measuring to an enemy entity is exactly the query docs/09
## forbids, and range to a TRACK is computed from the track's own position.
func own_range_km(a: int, b: int) -> float:
	if not _allow(a) or not _allow(b):
		return INF
	return _e.range_km(a, b)
