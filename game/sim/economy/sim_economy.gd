class_name SimEconomy
extends RefCounted
## Resources, production, upkeep, fuel and epoch advancement. docs/04, docs/05.
##
## ══ THIS IS A STUB. ══
## Signatures are final; bodies are the economy agent's job.
##
## OWNERSHIP: the only writer of the credit pools, the production queues, the
## per-unit `fuel` array, and the only place entities are CREATED after match
## setup. That last one is deliberate -- if spawning happens in exactly one slot
## then no other loop can be iterating range(count()) while the count changes.
##
## PER PLAYER, NOT PER FACTION. docs/09 §6 allows allied AIs to share a track
## table (one faction, one picture) while keeping separate economies. Everything
## here is indexed by SimEntities.owner.
##
## LEAK WARNING (docs/09 §1.2): "Economy and production -- knowing the player's
## income, queue or stockpile" is listed as a leak. credits() and queue_of() are
## therefore callable only for a player's OWN id. SimAiWorldView passes its own
## id and nothing else, which is what makes that structural rather than polite.


## docs/04: one resource, three delivery networks. Oil is extracted, refined
## into fuel, and distributed -- so credits and fuel are the SAME substance at
## different points in the chain, not two currencies.
class Purse extends RefCounted:
	var credits: float = 0.0
	var income_per_min: float = 0.0
	var upkeep_per_min: float = 0.0
	var epoch: int = 4
	var ceiling_epoch: int = 7
	var advance_progress: float = 0.0   ## 0..1 toward the next epoch
	var advance_cost_mult: float = 1.0


var entities: SimEntities
var rng: SimRng
## player id -> Purse. Iterated only through player_ids(), which sorts.
var _purses: Dictionary = {}
## player id -> Array of queued def keys, in submission order.
var _queues: Dictionary = {}


func _init(store: SimEntities, seeded: SimRng) -> void:
	entities = store
	rng = seeded


# ═══════════════════════════════════════════════════════════════════════════
# THE API
# ═══════════════════════════════════════════════════════════════════════════

## Register a player. Called once at match setup from SimPlayerSetup.
func add_player(player_id: int, starting_credits: float, start_epoch: int,
		ceiling_epoch: int, advance_cost_mult: float = 1.0) -> Purse:
	var p := Purse.new()
	p.credits = starting_credits
	p.epoch = start_epoch
	p.ceiling_epoch = ceiling_epoch
	p.advance_cost_mult = advance_cost_mult
	_purses[player_id] = p
	_queues[player_id] = []
	return p


## Deterministic iteration order. docs/06: never iterate an unordered container
## where order affects outcome, and income order affects who can afford what on
## a tick where two players are both at the threshold.
func player_ids() -> Array:
	var ids: Array = _purses.keys()
	ids.sort()
	return ids


func purse(player_id: int) -> Purse:
	return _purses.get(player_id)


func credits(player_id: int) -> float:
	var p: Purse = _purses.get(player_id)
	return p.credits if p != null else 0.0


func add_income(player_id: int, amount: float) -> void:
	var p: Purse = _purses.get(player_id)
	if p != null:
		p.credits += amount


## Spend if affordable. Returns false and spends nothing otherwise -- never a
## partial spend, so a caller can branch on it safely.
func try_spend(player_id: int, amount: float) -> bool:
	var p: Purse = _purses.get(player_id)
	if p == null or p.credits < amount:
		return false
	p.credits -= amount
	return true


## Queue a unit for production at a structure. MUST verify the structure is
## alive, owned by player_id, and capable of producing that def, and that the
## def is unlocked at the player's current epoch (docs/05: advancing "unlocks
## new units; upgrades existing production lines in place").
func queue_production(player_id: int, structure_unit: int, def_key: String) -> bool:
	return false


## What player_id has queued, in order. Own id only -- see the leak warning.
func queue_of(player_id: int) -> Array:
	return _queues.get(player_id, [])


## Create a finished unit in the world. THE ONLY PLACE entities are added after
## match setup. MUST set the full damage, mobility and economy profile from the
## unit def before returning, so nothing ever observes a half-configured unit.
## Returns the new entity index, or -1.
func spawn_unit(player_id: int, def_key: String, x_m: float, z_m: float,
		heading_rad: float = 0.0) -> int:
	return -1


## Begin advancing an epoch. docs/05: costs resources PLUS real time, and the
## time is the risk. MUST refuse above ceiling_epoch, which docs/09 §4 makes
## public information for every player.
func begin_epoch_advance(player_id: int) -> bool:
	return false


## docs/04's supply chain: refinery -> depot -> truck -> forward point ->
## vehicles. MUST move fuel along it rather than teleporting it, because
## interdiction -- "hitting the tankers instead of the tanks" -- is only a
## strategy if the trucks are real.
func transfer_fuel(from_unit: int, to_unit: int, litres: float) -> float:
	return 0.0


## The tick slot, 1 Hz (docs/06: "Logistics & AI, 1-2 Hz"). MUST: accrue income,
## charge upkeep, advance production timers and spawn finished units, burn fuel
## at entities.burn_rate_lpm(), and force MoveState.IMMOBILE on anything that
## runs dry. `dt` is the elapsed seconds since this slot last ran, NOT the
## simulation tick -- burn rates are per minute.
func step(dt: float) -> void:
	pass


## True once this class actually earns, spends and produces.
func is_implemented() -> bool:
	return false
