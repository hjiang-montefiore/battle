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


## Tracks at or above a rung, deterministically ordered. docs/09 §3's threat
## table is written in exactly these terms: what the AI does is a function of
## WHAT KIND of knowledge it has.
func tracks_at_least(quality: int) -> Array:
	return tracks.tracks_at_least(quality) if tracks != null else []


## Contacts observed radiating -- the anti-radiation target set, and what
## home-on-jam gives away for free.
func emitters() -> Array:
	return tracks.emitters() if tracks != null else []
