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


# ═══════════════════════════════════════════════════════════════════════════
# OWN BASE. Everything below is a fact about a unit THIS PLAYER OWNS, and
# every one of them refuses an index it does not hold -- the same fence
# SimOwnForcesView puts around position() and fuel_fraction().
#
# They exist because siting a building is a decision about one's own base:
# a player looks at the build-radius rings the HUD draws, at the footprints
# already on the ground, and at the map. docs/09 §1 allows all three. What is
# NOT here, and must never be, is SimEconomy.placement_problem(): that call
# tests clearance against EVERY structure on the map whoever owns it, so an
# AI that probed it on a grid would read the enemy's base off the refusals.
# The AI checks its own clearance and accepts that a refused placement is
# something it has to notice and retry -- which is exactly what a player
# with a red cursor does.
# ═══════════════════════════════════════════════════════════════════════════

## The def behind one of this player's own units: its cost, footprint, build
## radius and role. The same card its own build menu showed when it bought it.
## Note `_allow` rather than `owns`: SimOwnForcesView counts every refused
## query, and a fence nobody can count is a fence nobody can test. Its own
## accessors all go through the same call for the same reason.
func own_def(unit: int) -> SimUnitDef:
	if economy == null or forces == null or not forces._allow(unit):
		return null
	return economy.def_of(unit)


## Is one of this player's own structures FINISHED? An unfinished building
## projects no build radius (SimEconomy.placement_problem tests
## is_operational), so an AI that did not ask this would site against a ring
## that is not there yet.
func own_is_operational(unit: int) -> bool:
	if economy == null or forces == null or not forces._allow(unit):
		return false
	return economy.is_operational(unit)


## Own power supply and draw, the two numbers the player's sidebar shows.
## docs/12: "a brownout slows work" -- so an AI that cannot see its own
## brownout cannot fix it, and ours starts in one.
func own_power_supply() -> float:
	if economy == null:
		return 0.0
	var p := economy.purse(player_id)
	return p.power_supply if p != null else 0.0


func own_power_draw() -> float:
	if economy == null:
		return 0.0
	var p := economy.purse(player_id)
	return p.power_draw if p != null else 0.0


## THE CRUDE LINE OFF ITS OWN SIDEBAR: how much crude this player pumps a
## minute, and how much of it its refineries can actually turn into money.
##
## SimEconomy pays out `min(extraction, refine) + trickle`, so these two
## numbers are the whole shape of an oil economy: crude above the refining
## line earns NOTHING, and refining above the crude line earns nothing either.
## An AI that cannot see them has no way to tell "buy another derrick" from
## "buy another refinery", and the measured consequence was that it did
## neither -- it sized its refineries off its income, which is the OUTPUT of
## this pair, and so could never notice it was pumping into a full pipe.
##
## docs/09 §1.2 lists another player's income as a leak. This is the player's
## own, and SimEconomy prints it on its own status line in these same words:
## "crude %.0f/min, refining %.0f/min".
func own_extraction_per_min() -> float:
	if economy == null:
		return 0.0
	var p := economy.purse(player_id)
	return p.extraction_per_min if p != null else 0.0


func own_refine_capacity() -> float:
	if economy == null:
		return 0.0
	var p := economy.purse(player_id)
	return p.refine_capacity if p != null else 0.0


## WHAT THIS PLAYER HAS ACTUALLY EARNED, cumulative. Its own bank statement.
##
## The AI used to estimate its income as "the change in my balance plus what I
## chose to spend", which is exact only if every order it gives is charged for
## at the price it expected. It is not: a production order can be refused, and
## in the opening seconds a commander spending a large starting float looks
## like a commander earning one. Measured, that put the income estimate at 168
## credits a second against a true 5, which sized the industry to a fantasy
## and put two refineries in front of the research facility.
##
## docs/09 §1.2 lists ANOTHER player's income as a leak; this is the player's
## own, which is the number its own sidebar shows.
func own_earned_total() -> float:
	if economy == null:
		return 0.0
	var p := economy.purse(player_id)
	return p.earned_total if p != null else 0.0
