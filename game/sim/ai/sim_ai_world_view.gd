class_name SimAiWorldView
extends RefCounted
## Everything one AI player is allowed to know, bundled. docs/09 §1 whitelist,
## and nothing outside it.
##
## The bundle exists so the AI's constructor takes ONE argument and that
## argument physically cannot reach ground truth. There is no field here that
## holds a SimEntities, no method that returns one, and no way to get from a
## track to an entity: SimTrack carries an opaque track_id, which docs/09 §1.3
## calls "a hypothesis, not a pointer" -- and which is also what makes a chaff
## bloom, a DRFM false target and a naval decoy representable at all.
##
## Commands go out the same way a human player's do, through SimCommandQueue,
## stamped with this player's id. An AI cannot issue an order as somebody else
## and cannot write an entity field directly.

var forces: SimOwnForcesView
## FactionTrackTable[ its own faction ]. The AI's entire picture of the enemy.
var tracks: SimTrackTable
## Maps are public -- docs/09: "real militaries have them".
var terrain: SimTerrain
## The AI's own economy. SimEconomy refuses a foreign player id.
var economy: SimEconomy
## Where orders go.
var commands: SimCommandQueue
## Skill and doctrine, which are the AI's difficulty dials rather than any kind
## of information advantage. docs/09 §2: difficulty is doctrine quality, not
## bonuses.
var setup: SimPlayerSetup

var player_id: int = 0


func _init(own_forces: SimOwnForcesView, own_tracks: SimTrackTable,
		public_terrain: SimTerrain, own_economy: SimEconomy,
		command_queue: SimCommandQueue, player_setup: SimPlayerSetup,
		p_player_id: int) -> void:
	forces = own_forces
	tracks = own_tracks
	terrain = public_terrain
	economy = own_economy
	commands = command_queue
	setup = player_setup
	player_id = p_player_id


func credits() -> float:
	return economy.credits(player_id) if economy != null else 0.0


func epoch() -> int:
	if economy == null:
		return setup.start_epoch if setup != null else 1
	var p := economy.purse(player_id)
	return p.epoch if p != null else 1


## Order one of this player's units to a world point. Convenience over
## SimCommandQueue so an AI never has to build a Command by hand and never has
## to name an issuer other than itself.
func order_move(unit: int, x_m: float, z_m: float) -> void:
	commands.move(player_id, unit, x_m, z_m)


func order_stop(unit: int) -> void:
	commands.stop(player_id, unit)


## Engage a TRACK. Note the argument: a track id from this player's own table.
## There is no order_attack(entity_index) and there must never be one -- that
## signature is the leak, not the implementation behind it.
func order_attack(unit: int, track_id: int) -> void:
	commands.attack_track(player_id, unit, track_id)


func order_emcon(unit: int, emcon_state: int) -> void:
	commands.set_emcon(player_id, unit, emcon_state)


## Ask a structure this player owns to build something. Same queue, same
## ownership check in SimWorld._command_slot(); the AI never names an issuer
## other than itself, because it is not given the chance to.
##
## Added alongside order_move/order_attack for one reason: docs/09 §3 puts
## "economy, epoch advancement, production mix" on the strategic layer, and a
## director that had to construct its own Command to express that would be a
## director that could put somebody else's id on it.
func order_produce(structure_unit: int, def_key: String) -> void:
	commands.produce(player_id, structure_unit, def_key)


func order_build(def_key: String, x_m: float, z_m: float) -> void:
	commands.build(player_id, def_key, x_m, z_m)


## docs/05 epoch advancement, own purse only. SimEconomy refuses a foreign id,
## and this is the only id the AI can supply.
func begin_epoch_advance() -> bool:
	return economy.begin_epoch_advance(player_id) if economy != null else false


## Everything this player may build or produce right now, ascending. The
## economy answers for THIS id only -- another player's tech tree is not
## reachable from here, and docs/09 §1.2 lists it as a leak if it were.
func buildable() -> PackedStringArray:
	return economy.buildable(player_id) if economy != null else PackedStringArray()


## What one of this player's structures can turn out, ascending.
func production_options(structure_unit: int) -> PackedStringArray:
	if economy == null:
		return PackedStringArray()
	return economy.production_options(player_id, structure_unit)


## The def behind a key, at THIS player's epoch. Cost, name, category -- the
## same card the human's build menu shows.
func def_for(def_key: String) -> SimUnitDef:
	return economy.def_for(player_id, def_key) if economy != null else null


## What the next epoch costs this player. docs/09 §4 makes ceilings public;
## the price of the step is the player's own business either way.
func epoch_advance_cost() -> float:
	return economy.advance_cost(player_id) if economy != null else 0.0


## False when this AI has no purse at all, which is a legitimate setup (a
## scenario with fixed forces and no economy).
func has_purse() -> bool:
	return economy != null and economy.purse(player_id) != null


## What this player has queued. docs/09 §1.2 lists another player's queue as a
## leak, which is why the id is not a parameter.
func production_queue() -> Array:
	return economy.queue_of(player_id) if economy != null else []


## Tracks at or above a rung, deterministically ordered. docs/09 §3's threat
## table is written in exactly these terms: what the AI does is a function of
## WHAT KIND of knowledge it has.
func tracks_at_least(quality: int) -> Array:
	return tracks.tracks_at_least(quality) if tracks != null else []


## WHERE THE GROUND IS WORTH SOMETHING: ore and oil field positions, merged
## and in a fixed order.
##
## These are MAP FEATURES on exactly the footing docs/09 §1 gives the terrain:
## holes in the ground at published coordinates, the same ones the player's
## minimap draws. Positions ONLY -- nothing here says who is working a field,
## who has a derrick on one, or whether anybody is standing there, because
## those are facts about the other player and are not reachable from this
## bundle. What the AI does with them is inference: an economy has to be where
## the resources are, so that is ground worth sweeping and ground worth taking.
## It can be wrong about it, which is what makes it reconnaissance.
func resource_points() -> Array:
	var out: Array = []
	if economy == null:
		return out
	for p in economy.ore_fields:
		out.append(p)
	for p in economy.oil_fields:
		out.append(p)
	return out


## Oil field positions alone, in a fixed order -- the ones a derrick can stand
## on. Same footing as above: coordinates, and nothing about who holds them.
func oil_points() -> Array:
	var out: Array = []
	if economy == null:
		return out
	for p in economy.oil_fields:
		out.append(p)
	return out


## Contacts observed radiating -- the anti-radiation target set, and what
## home-on-jam gives away for free.
func emitters() -> Array:
	return tracks.emitters() if tracks != null else []
