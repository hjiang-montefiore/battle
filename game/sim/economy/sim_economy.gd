class_name SimEconomy
extends RefCounted
## Resources, production, upkeep, fuel and epoch advancement. docs/04, docs/05.
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
##
## ── THE RESOURCE MODEL, IN ONE PARAGRAPH ────────────────────────────────────
## docs/04: "Oil is extracted, refined into fuel, and distributed -- one
## resource, three delivery networks." So there is exactly ONE currency,
## credits, and it is refined oil. Derricks extract CRUDE; refineries convert
## crude to credits and cap how much of it you can actually use; a derrick
## without refining capacity earns you nothing. Fuel in a vehicle's tank is the
## same substance one step further down the chain, which is why supply sources
## push litres and never credits. Two numbers the player watches -- a bank
## balance and a fuel gauge -- and they are the same thing at different points
## in one pipeline.
##
## ── DETERMINISM ─────────────────────────────────────────────────────────────
## Nothing in this file draws a random number. Every iteration is over an
## ascending PackedInt32Array or an ordered Array; the two Dictionaries here
## (_purses, _queues) are only ever indexed, never iterated -- player_ids()
## sorts before handing an order out. Two runs from one seed produce identical
## credits, identical queues and identical spawns, and test_economy.gd asserts
## exactly that against the world's own state_hash().


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

	# ── added by the economy layer; all default harmlessly ───────────────────
	## docs/09 §4's optional, clearly-labelled handicap. 1.0 = none.
	var income_mult: float = 1.0
	## Optional. When present, domain restrictions (docs/09's "army only") and
	## the per-ladder ceilings are enforced on every queue and every build.
	var setup: SimPlayerSetup = null
	var faction: int = -1
	## The NATION whose researched roster (data/factions) this player fields:
	## a SimPlayerSetup.Faction value, or -1 for the baseline. DISTINCT from
	## `faction` above, which the match layer overwrites with the COALITION id
	## for track-table sharing -- two allies on one team keep their own
	## national hardware while sharing one picture.
	var nation: int = -1
	## Seconds of research left in the epoch currently being advanced to, and
	## how many it started with. 0 total means "not advancing".
	var advance_total_s: float = 0.0
	var advance_remaining_s: float = 0.0
	## Running totals, for the HUD and for post-match honesty.
	var earned_total: float = 0.0
	var spent_total: float = 0.0
	## Last tick's power supply and draw, so a HUD can show a brownout.
	var power_supply: float = 0.0
	var power_draw: float = 0.0
	## Crude extracted vs. crude the refineries can actually process.
	var extraction_per_min: float = 0.0
	var refine_capacity: float = 0.0

	## docs/12: "Radars and factories both draw on it." Under-supplied is a
	## brownout, not a blackout -- production slows rather than stopping, which
	## is legible without being punishing.
	func power_satisfaction() -> float:
		if power_draw <= 0.0:
			return 1.0
		return clampf(power_supply / power_draw, 0.0, 1.0)

	func is_advancing() -> bool:
		return advance_total_s > 0.0

	func can_advance() -> bool:
		return epoch < ceiling_epoch and not is_advancing()


## One entry in a structure's build queue.
class Job extends RefCounted:
	var def_key: String = ""
	var role: String = ""
	var epoch: int = 1
	var structure_unit: int = -1
	var cost: float = 0.0
	var total_seconds: float = 1.0
	var remaining_seconds: float = 1.0

	func progress() -> float:
		if total_seconds <= 0.0:
			return 1.0
		return clampf(1.0 - remaining_seconds / total_seconds, 0.0, 1.0)

	func _to_string() -> String:
		return "%s %.0f%%" % [def_key, progress() * 100.0]


## A structure that has been placed but is not finished. The ENTITY exists from
## the moment the order lands -- docs/12 makes every structure a role in the
## same store, and a building site you cannot bomb is not a building site.
class Site extends RefCounted:
	var unit: int = -1
	var role: String = ""
	var total_seconds: float = 1.0
	var remaining_seconds: float = 1.0

	func progress() -> float:
		if total_seconds <= 0.0:
			return 1.0
		return clampf(1.0 - remaining_seconds / total_seconds, 0.0, 1.0)


## Aggregates recomputed once per economy tick, in one ascending sweep.
class Aggregate extends RefCounted:
	var extraction: float = 0.0
	var refine: float = 0.0
	var power_supply: float = 0.0
	var power_draw: float = 0.0
	var upkeep: float = 0.0
	var units: int = 0
	var structures: int = 0
	var has_research: bool = false


# ── tunables ─────────────────────────────────────────────────────────────────
## A floor so a player who has lost every derrick can still do something. Small
## on purpose: it is a lifeline, not an income.
const HQ_TRICKLE_PER_MIN := 40.0
## docs/05: "Cost: resources plus real time. The time is the risk."
const ADVANCE_BASE_COST := 2500.0
const ADVANCE_COST_PER_EPOCH := 900.0
const ADVANCE_BASE_SECONDS := 120.0
const ADVANCE_SECONDS_PER_EPOCH := 30.0
## Per structure. A queue that can absorb the whole bank is a queue that hides
## a mistake for four minutes.
const MAX_QUEUE_PER_STRUCTURE := 9
## Hand-to-hand fuel transfer reach when neither party is a declared supply
## source. docs/04 wants the chain to be physical, so this is short.
const MANUAL_TRANSFER_RANGE_M := 120.0
## Radius inside which a placed structure blocks another.
const PLACEMENT_CLEARANCE := 1.0


var entities: SimEntities
var rng: SimRng
## player id -> Purse. Iterated only through player_ids(), which sorts.
var _purses: Dictionary = {}
## player id -> Array of Job, in submission order.
var _queues: Dictionary = {}
## Structures under construction, in placement order. An ARRAY because it is
## iterated every tick and docs/06 forbids relying on Dictionary order.
var _sites: Array = []
## entity index -> Site, for O(1) "is this finished?" lookups. Never iterated.
var _site_of: Dictionary = {}
## entity index -> def key. Everything this class knows about a unit beyond the
## flat arrays. A String per index, not an object per unit -- the store stays
## structure-of-arrays (docs/06).
var _def_key_of: Dictionary = {}
## player id -> Aggregate, rebuilt every step().
var _agg: Dictionary = {}
## Entity indices currently sitting at zero fuel. A membership set, indexed and
## never iterated, so that running dry is an EVENT rather than a per-tick state.
var _dry: Dictionary = {}

## Optional. Needed only for placement rules -- water, land and map extent.
var terrain: SimTerrain = null
## Optional. docs/04: "Air: destroyed. No second chance." Only SimDamage may
## kill (see the ownership table in sim_entities.gd), so running an aircraft
## dry can only be fatal when the damage layer has been handed over. Without
## it the aircraft is recorded in fuel_starvation and left alive, which is
## wrong but honest, and the wiring is one line at match setup.
var damage: SimDamage = null

## Append-only diagnostics. Cheap, ordered, and the fastest way to answer
## "why did nothing come out of the factory?"
var events: PackedStringArray = PackedStringArray()
## Entity indices that hit empty this tick, in ascending order.
var fuel_starvation: PackedInt32Array = PackedInt32Array()
var spawned_this_step: PackedInt32Array = PackedInt32Array()

var _spawn_serial: int = 0


func _init(store: SimEntities, seeded: SimRng) -> void:
	entities = store
	rng = seeded


func set_terrain(t: SimTerrain) -> void:
	terrain = t


## Hand the economy the damage layer so docs/04's "air: destroyed" rule can be
## applied through its owner rather than behind its back.
var movement: SimMovement = null

func set_movement(m: SimMovement) -> void:
	movement = m


func set_damage(d: SimDamage) -> void:
	damage = d


# ═══════════════════════════════════════════════════════════════════════════
# PLAYERS AND MONEY
# ═══════════════════════════════════════════════════════════════════════════

## Register a player. Called once at match setup from SimPlayerSetup.
func add_player(player_id: int, starting_credits: float, start_epoch: int,
		ceiling_epoch: int, advance_cost_mult: float = 1.0) -> Purse:
	var p := Purse.new()
	p.credits = starting_credits
	p.epoch = clampi(start_epoch, SimRoster.EPOCH_MIN, SimRoster.EPOCH_MAX)
	p.ceiling_epoch = clampi(maxi(ceiling_epoch, p.epoch),
		SimRoster.EPOCH_MIN, SimRoster.EPOCH_MAX)
	p.advance_cost_mult = advance_cost_mult
	_purses[player_id] = p
	_queues[player_id] = []
	_agg[player_id] = Aggregate.new()
	return p


## Register a player straight from its match setup, so the domain restrictions
## and the epoch pair cannot drift apart from what the setup screen showed.
func add_player_from_setup(player_id: int, s: SimPlayerSetup,
		starting_credits: float) -> Purse:
	var p := add_player(player_id, starting_credits, s.start_epoch,
		s.ceiling_epoch, s.advance_cost_mult)
	p.setup = s
	p.faction = s.faction
	p.nation = s.faction
	p.income_mult = s.resource_mult
	return p


## Deterministic iteration order. docs/06: never iterate an unordered container
## where order affects outcome, and income order affects who can afford what on
## a tick where two players are both at the threshold.
func player_ids() -> Array:
	var ids: Array = _purses.keys()
	ids.sort()
	return ids


func has_player(player_id: int) -> bool:
	return _purses.has(player_id)


func purse(player_id: int) -> Purse:
	return _purses.get(player_id)


func credits(player_id: int) -> float:
	var p: Purse = _purses.get(player_id)
	return p.credits if p != null else 0.0


func epoch_of(player_id: int) -> int:
	var p: Purse = _purses.get(player_id)
	return p.epoch if p != null else 1


func add_income(player_id: int, amount: float) -> void:
	var p: Purse = _purses.get(player_id)
	if p != null:
		p.credits += amount
		if amount > 0.0:
			p.earned_total += amount


## Spend if affordable. Returns false and spends nothing otherwise -- never a
## partial spend, so a caller can branch on it safely.
func try_spend(player_id: int, amount: float) -> bool:
	var p: Purse = _purses.get(player_id)
	if p == null or amount < 0.0 or p.credits < amount:
		return false
	p.credits -= amount
	p.spent_total += amount
	return true


# ═══════════════════════════════════════════════════════════════════════════
# WHAT MAY BE BUILT
# ═══════════════════════════════════════════════════════════════════════════

## The def a player would get if it queued `def_key` right now, or null. A bare
## role key resolves at the player's CURRENT epoch, which is docs/05's
## "upgrades existing production lines in place" -- the queue holds roles, not
## frozen generations.
func def_for(player_id: int, def_key: String) -> SimUnitDef:
	var p: Purse = _purses.get(player_id)
	if p == null:
		return null
	var d := SimRoster.resolve(def_key, p.epoch, p.nation)
	if d == null:
		return null
	if p.setup != null and not p.setup.allows(d.domain):
		return null
	return d


## Every role the player's EPOCH, DOMAINS and prerequisites currently allow,
## ascending. This is the tech tree, not the build menu -- it does not ask
## whether a factory that could turn the role out actually exists, because a
## menu that hides an unbuilt building's contents hides the tech tree with it.
## production_options() is the per-structure question.
func buildable(player_id: int) -> PackedStringArray:
	var p: Purse = _purses.get(player_id)
	if p == null:
		return PackedStringArray()
	var domains: int = p.setup.allowed_domains if p.setup != null \
		else SimPlayerSetup.ALL_DOMAINS
	var out := PackedStringArray()
	for role in SimRoster.available(p.epoch, domains):
		if _prerequisites_met(player_id, SimRoster.make(role, p.epoch, p.nation)):
			out.append(role)
	return out


## What this structure can turn out, ascending. Empty for a structure that is
## not a production building or is still under construction.
func production_options(player_id: int, structure_unit: int) -> PackedStringArray:
	var p: Purse = _purses.get(player_id)
	if p == null or not _owns_operational(player_id, structure_unit):
		return PackedStringArray()
	var role := role_of(structure_unit)
	if role == "":
		return PackedStringArray()
	var domains: int = p.setup.allowed_domains if p.setup != null \
		else SimPlayerSetup.ALL_DOMAINS
	var out := PackedStringArray()
	for r in SimRoster.produced_by(role, p.epoch, domains):
		if _prerequisites_met(player_id, SimRoster.make(r, p.epoch, p.nation)):
			out.append(r)
	return out


## The role key a unit was spawned as, or "" for anything the economy did not
## create (the proving ground's hand-placed units, for instance).
func role_of(unit: int) -> String:
	var k: String = _def_key_of.get(unit, "")
	if k == "":
		return ""
	return String(SimRoster.parse_key(k).get("role", ""))


func def_of(unit: int) -> SimUnitDef:
	var k: String = _def_key_of.get(unit, "")
	if k == "":
		return null
	var pk := SimRoster.parse_key(k)
	# The OWNER's faction def, not the baseline: a Leopard keeps the Leopard's
	# speed and name when the HUD or the supply sweep looks it up later.
	var p: Purse = _purses.get(entities.owner[unit])
	var nation: int = p.nation if p != null else -1
	return SimRoster.make(String(pk["role"]), int(pk["epoch"]), nation)


## A structure is OPERATIONAL once it is finished. Until then it is an entity
## on the map that can be shot at and does nothing else -- no income, no power,
## no production, no supply.
func is_operational(unit: int) -> bool:
	if not entities.is_alive(unit):
		return false
	if entities.is_structure[unit] == 0:
		return true
	return not _site_of.has(unit)


func construction_progress(unit: int) -> float:
	var s: Site = _site_of.get(unit)
	return 1.0 if s == null else s.progress()


func sites_of(player_id: int) -> Array:
	var out: Array = []
	for s in _sites:
		var site := s as Site
		if entities.is_alive(site.unit) and entities.owner[site.unit] == player_id:
			out.append(site)
	return out


# ═══════════════════════════════════════════════════════════════════════════
# PRODUCTION
# ═══════════════════════════════════════════════════════════════════════════

## Queue a unit for production at a structure. Verifies the structure is alive,
## owned, finished and capable of producing that def, and that the def is
## unlocked at the player's current epoch (docs/05).
##
## The full price is taken NOW and refunded if the job is cancelled or the
## factory dies. Charging in instalments would mean a queue that silently
## stalls when income dips, and "why is nothing coming out?" is the worst
## question an RTS economy can provoke.
## Rally points and the primary factory, Red Alert style. Both are PER
## STRUCTURE: set_rally() on a factory sends everything it produces to a point;
## set_primary() marks the factory a bare "produce this" order routes to, and
## the marker moves when the primary dies.
var _rally: Dictionary = {}         ## structure unit -> Vector2
var _primary: Dictionary = {}       ## player id -> structure unit


func set_rally(structure_unit: int, x: float, z: float) -> void:
	_rally[structure_unit] = Vector2(x, z)


func rally_of(structure_unit: int) -> Variant:
	return _rally.get(structure_unit)


func set_primary(player_id: int, structure_unit: int) -> void:
	_primary[player_id] = structure_unit


func primary_of(player_id: int) -> int:
	var s: int = _primary.get(player_id, -1)
	if s >= 0 and entities.is_alive(s):
		return s
	return -1


func queue_production(player_id: int, structure_unit: int, def_key: String) -> bool:
	var p: Purse = _purses.get(player_id)
	if p == null:
		return false
	if not _owns_operational(player_id, structure_unit):
		_log("produce refused: %d is not an operational structure of player %d"
			% [structure_unit, player_id])
		return false
	if entities.is_structure[structure_unit] == 0:
		return false
	var factory := role_of(structure_unit)
	if factory == "":
		return false
	var d := def_for(player_id, def_key)
	if d == null:
		_log("produce refused: '%s' is not available to player %d at epoch %d"
			% [def_key, player_id, p.epoch])
		return false
	if d.is_structure or d.built_by != factory:
		_log("produce refused: %s is not built by %s" % [d.key, factory])
		return false
	if not _prerequisites_met(player_id, d):
		_log("produce refused: %s needs %s" % [d.key, ", ".join(d.requires)])
		return false
	var q: Array = _queues[player_id]
	var at_this_structure := 0
	for j in q:
		if (j as Job).structure_unit == structure_unit:
			at_this_structure += 1
	if at_this_structure >= MAX_QUEUE_PER_STRUCTURE:
		return false
	if not try_spend(player_id, d.cost):
		_log("produce refused: %s costs %.0f, player %d holds %.0f"
			% [d.key, d.cost, player_id, p.credits])
		return false
	var job := Job.new()
	job.def_key = d.key
	job.role = d.role
	job.epoch = d.epoch
	job.structure_unit = structure_unit
	job.cost = d.cost
	job.total_seconds = d.build_seconds
	job.remaining_seconds = d.build_seconds
	q.append(job)
	return true


## What player_id has queued, in order. Own id only -- see the leak warning.
##
## NOTE for the HUD: these are Job objects, not bare def keys. A queue readout
## needs a progress bar as well as a name, and returning strings would force a
## second lookup for every row. `job.def_key` is the string.
func queue_of(player_id: int) -> Array:
	return _queues.get(player_id, [])


## Def keys only, in order, for a caller that wants the strings.
func queue_keys(player_id: int) -> PackedStringArray:
	var out := PackedStringArray()
	for j in _queues.get(player_id, []):
		out.append((j as Job).def_key)
	return out


## Drop a queued job and refund it. `position` is the index within the player's
## whole queue as returned by queue_of(). Returns the refunded amount.
func cancel_production(player_id: int, position: int) -> float:
	var q: Array = _queues.get(player_id, [])
	if position < 0 or position >= q.size():
		return 0.0
	var job := q[position] as Job
	q.remove_at(position)
	add_income(player_id, job.cost)
	_log("cancelled %s, refunded %.0f" % [job.def_key, job.cost])
	return job.cost


# ═══════════════════════════════════════════════════════════════════════════
# SPAWNING
# ═══════════════════════════════════════════════════════════════════════════

## Create a finished unit in the world, CHARGING the player for it. This is the
## BUILD path -- placing a structure -- and the only entity-creating call that
## takes money. Production completions go through _place() directly because
## queue_production() already took the price.
##
## Returns the new entity index, or -1.
func spawn_unit(player_id: int, def_key: String, x_m: float, z_m: float,
		heading_rad: float = 0.0) -> int:
	var p: Purse = _purses.get(player_id)
	if p == null:
		return -1
	var d := def_for(player_id, def_key)
	if d == null:
		return -1
	if not _prerequisites_met(player_id, d):
		_log("build refused: %s needs %s" % [d.key, ", ".join(d.requires)])
		return -1
	if d.is_structure:
		var why := placement_problem(player_id, d, x_m, z_m)
		if why != "":
			_log("build refused: %s at %.0f,%.0f -- %s" % [d.key, x_m, z_m, why])
			return -1
	if not try_spend(player_id, d.cost):
		return -1
	var i := _place(player_id, d, x_m, z_m, heading_rad, d.is_structure)
	if i < 0:
		add_income(player_id, d.cost)   # refund a placement that fell through
	return i


## Put a unit on the map for FREE. Match setup and scenario scripts use this;
## it is not reachable from a command, so nothing in play can call it.
func place_starting_unit(player_id: int, def_key: String, x_m: float,
		z_m: float, heading_rad: float = 0.0) -> int:
	var p: Purse = _purses.get(player_id)
	if p == null:
		return -1
	var d := SimRoster.resolve(def_key, p.epoch, p.nation)
	if d == null:
		return -1
	return _place(player_id, d, x_m, z_m, heading_rad, false)


## Why this structure cannot go here, or "" if it can. A String rather than a
## bool so the HUD can say WHY the cursor is red.
func placement_problem(player_id: int, d: SimUnitDef, x: float, z: float) -> String:
	if not d.is_structure:
		return "not a structure"
	if terrain != null:
		# World coordinates are CENTRED on the origin: -extent/2 .. +extent/2.
		var hx := terrain.extent_x_m() * 0.5
		var hz := terrain.extent_z_m() * 0.5
		if x < -hx or x > hx or z < -hz or z > hz:
			return "off the map"
		var wants_water := d.role == "naval_yard"
		var wet := terrain.is_water(x, z)
		if wants_water and not wet:
			return "a naval yard needs water"
		if not wants_water and wet:
			return "cannot build on water"
	# Clearance against everything already standing, whoever owns it.
	for i in range(entities.count()):
		if entities.alive[i] == 0 or entities.is_structure[i] == 0:
			continue
		var other := def_of(i)
		var keep: float = d.footprint_m \
			+ (other.footprint_m if other != null else 12.0)
		if _dist2(x, z, entities.pos_x[i], entities.pos_z[i]) \
				< keep * keep * PLACEMENT_CLEARANCE:
			return "too close to %s" % entities.names[i]
	# RA2's build radius. The first structure a player places is free-form,
	# which is what makes an MCV-style opening possible without a special case.
	var owned := entities.indices_of_owner(player_id)
	var any_structure := false
	for i in owned:
		if entities.is_structure[i] == 1 and is_operational(i):
			any_structure = true
			var od := def_of(i)
			var r: float = od.build_radius_m if od != null else 0.0
			if r > 0.0 and _dist2(x, z, entities.pos_x[i], entities.pos_z[i]) <= r * r:
				return ""
	if not any_structure:
		return ""
	return "outside your build radius"


## The one place an entity is created after setup. Sets the FULL damage,
## mobility and economy profile before returning, so nothing ever observes a
## half-configured unit (which is why this is private and spawn_unit() is not
## allowed to shortcut it).
func _place(player_id: int, d: SimUnitDef, x: float, z: float,
		heading_rad: float, under_construction: bool) -> int:
	var p: Purse = _purses.get(player_id)
	if p == null or d == null:
		return -1
	var faction: int = p.faction if p.faction >= 0 else player_id
	var phase := _spawn_serial
	_spawn_serial += 1
	var y := _spawn_altitude(d, x, z)
	var i := entities.add(d.name, faction, x, y, z, d.signature(),
		SimRoster.sensors_for(d.sensor, d.epoch, phase), d.category,
		d.mount_height_m, player_id)

	entities.set_damage_profile(i, d.damage_model, d.structure_hp,
		SimRoster.armor_facets(d.armor, d.epoch),
		SimRoster.armor_types(d.armor, d.epoch), d.armor_class)
	if d.is_structure:
		entities.is_structure[i] = 1
		entities.set_mobility(i, 0.0, 0.0, 0.0)
	else:
		entities.set_mobility(i, d.max_speed_ms(), d.accel_ms2, d.turn_rate_rads)
	entities.heading_rad[i] = heading_rad
	entities.turret_rad[i] = heading_rad
	entities.set_economy_profile(i, d.cost, d.upkeep, d.fuel_capacity,
		d.burn_idle, d.burn_cruise, d.burn_combat)
	# cargo_capacity is "set once at spawn, by whoever spawns the unit"
	# (sim_entities.gd ownership table); the roster is where the number lives.
	if d.cargo_slots > 0:
		entities.set_cargo_capacity(i, d.cargo_slots)
	if d.category == SimTypes.Category.SUBSURFACE:
		entities.depth_m[i] = 60.0
	_def_key_of[i] = d.key

	if under_construction:
		var site := Site.new()
		site.unit = i
		site.role = d.role
		site.total_seconds = d.build_seconds
		site.remaining_seconds = d.build_seconds
		_sites.append(site)
		_site_of[i] = site
	spawned_this_step.append(i)
	return i


## A ground unit stands on the terrain; a ship floats at zero; a submarine sits
## at zero with a depth. An aircraft is placed on its apron and stays there:
## takeoff, altitude and the docs/04 aircraft state machine are NOT modelled
## here, and pretending otherwise by spawning fighters at 6 km would hand them
## a radar horizon they have not earned.
func _spawn_altitude(d: SimUnitDef, x: float, z: float) -> float:
	if d.category == SimTypes.Category.SURFACE \
			or d.category == SimTypes.Category.SUBSURFACE:
		return 0.0
	var ground := 0.0
	if terrain != null:
		ground = maxf(terrain.ground_under(x, z), 0.0)
	if d.category == SimTypes.Category.AIR:
		return ground + 10.0
	return ground


# ═══════════════════════════════════════════════════════════════════════════
# EPOCH ADVANCEMENT (docs/05)
# ═══════════════════════════════════════════════════════════════════════════

## What the next epoch costs this player, in credits and in seconds. Public,
## because docs/05 makes ceilings public and a cost the player cannot see is a
## decision the player cannot make.
func advance_cost(player_id: int) -> float:
	var p: Purse = _purses.get(player_id)
	if p == null:
		return 0.0
	return (ADVANCE_BASE_COST + ADVANCE_COST_PER_EPOCH * float(p.epoch)) \
		* p.advance_cost_mult


func advance_seconds(player_id: int) -> float:
	var p: Purse = _purses.get(player_id)
	if p == null:
		return 0.0
	return ADVANCE_BASE_SECONDS + ADVANCE_SECONDS_PER_EPOCH * float(p.epoch)


## Begin advancing an epoch. Refuses above ceiling_epoch, which docs/09 §4
## makes public information for every player, and refuses without an
## operational research facility (docs/12).
func begin_epoch_advance(player_id: int) -> bool:
	var p: Purse = _purses.get(player_id)
	if p == null or not p.can_advance():
		return false
	if not _has_research_facility(player_id):
		_log("advance refused: player %d has no operational research facility"
			% player_id)
		return false
	var cost := advance_cost(player_id)
	if not try_spend(player_id, cost):
		return false
	p.advance_total_s = advance_seconds(player_id)
	p.advance_remaining_s = p.advance_total_s
	p.advance_progress = 0.0
	_log("player %d begins epoch %d -> %d (%.0f cr, %.0f s)"
		% [player_id, p.epoch, p.epoch + 1, cost, p.advance_total_s])
	return true


func cancel_epoch_advance(player_id: int) -> void:
	var p: Purse = _purses.get(player_id)
	if p == null or not p.is_advancing():
		return
	# Half back. Research already done is research already spent.
	add_income(player_id, advance_cost(player_id) * 0.5)
	p.advance_total_s = 0.0
	p.advance_remaining_s = 0.0
	p.advance_progress = 0.0


# ═══════════════════════════════════════════════════════════════════════════
# FUEL (docs/04)
# ═══════════════════════════════════════════════════════════════════════════

## Move fuel between two units of the same owner that are physically close
## enough for a hose to reach. docs/04 wants the chain to be a thing on the map
## -- refinery, depot, truck, forward point, vehicle -- so this refuses at
## range rather than teleporting litres across the theatre. Returns the litres
## actually moved.
func transfer_fuel(from_unit: int, to_unit: int, litres: float) -> float:
	if litres <= 0.0:
		return 0.0
	if not entities.is_alive(from_unit) or not entities.is_alive(to_unit):
		return 0.0
	if from_unit == to_unit:
		return 0.0
	if entities.owner[from_unit] != entities.owner[to_unit]:
		return 0.0
	var src := def_of(from_unit)
	var reach: float = MANUAL_TRANSFER_RANGE_M
	if src != null and src.supply_radius_m > 0.0:
		reach = src.supply_radius_m
	if _dist2(entities.pos_x[from_unit], entities.pos_z[from_unit],
			entities.pos_x[to_unit], entities.pos_z[to_unit]) > reach * reach:
		return 0.0
	var infinite: bool = src != null and src.supply_infinite \
		and is_operational(from_unit)
	var room: float = entities.fuel_capacity[to_unit] - entities.fuel[to_unit]
	if room <= 0.0:
		return 0.0
	var moved: float = minf(litres, room)
	if not infinite:
		moved = minf(moved, entities.fuel[from_unit])
		if moved <= 0.0:
			return 0.0
		entities.fuel[from_unit] -= moved
	entities.fuel[to_unit] += moved
	return moved


# ═══════════════════════════════════════════════════════════════════════════
# THE TICK
# ═══════════════════════════════════════════════════════════════════════════

## The tick slot, 1 Hz (docs/06: "Logistics & AI, 1-2 Hz"). `dt` is the elapsed
## seconds since this slot last ran, NOT the simulation tick -- burn rates are
## per minute.
##
## Order inside the slot matters as much as the slot order in sim_world.gd:
##   1 aggregate   one ascending sweep; everything below reads it
##   2 money       income minus upkeep
##   3 construction  a site finishing this tick is operational for step 4
##   4 production  the ONLY place entities appear
##   5 research    epoch advancement
##   6 fuel        burn, then resupply, then run-dry -- in that order, so a
##                 truck parked next to a tank tops it back up on the same
##                 tick it emptied and never trips the dry rule spuriously
func step(dt: float) -> void:
	if dt <= 0.0:
		return
	fuel_starvation = PackedInt32Array()
	spawned_this_step = PackedInt32Array()
	var dt_min := dt / 60.0

	_recompute_aggregates()
	_step_money(dt_min)
	_step_construction(dt)
	_step_production(dt)
	_step_research(dt)
	_step_fuel(dt_min)


func _recompute_aggregates() -> void:
	for pid in player_ids():
		var a := _agg[pid] as Aggregate
		a.extraction = 0.0; a.refine = 0.0
		a.power_supply = 0.0; a.power_draw = 0.0
		a.upkeep = 0.0; a.units = 0; a.structures = 0
		a.has_research = false
	var n := entities.count()
	for i in range(n):
		if entities.alive[i] == 0:
			continue
		var pid: int = entities.owner[i]
		if not _agg.has(pid):
			continue
		var a := _agg[pid] as Aggregate
		a.upkeep += entities.upkeep_per_min[i]
		if entities.is_structure[i] == 1:
			a.structures += 1
		else:
			a.units += 1
		var d := def_of(i)
		if d == null or not is_operational(i):
			continue
		a.extraction += d.extraction_per_min
		a.refine += d.refine_capacity
		a.power_supply += d.power_supply
		a.power_draw += d.power_draw
		if d.enables_advance:
			a.has_research = true
	for pid in player_ids():
		var p := _purses[pid] as Purse
		var a := _agg[pid] as Aggregate
		p.power_supply = a.power_supply
		p.power_draw = a.power_draw
		p.extraction_per_min = a.extraction
		p.refine_capacity = a.refine
		p.upkeep_per_min = a.upkeep
		# The chain, in one line: crude you pumped, capped by crude you can
		# refine. A derrick without a refinery earns nothing.
		var refined: float = minf(a.extraction, a.refine)
		var trickle: float = HQ_TRICKLE_PER_MIN if a.structures > 0 else 0.0
		p.income_per_min = (refined + trickle) * p.income_mult


func _step_money(dt_min: float) -> void:
	for pid in player_ids():
		var p := _purses[pid] as Purse
		var gained: float = p.income_per_min * dt_min
		p.credits += gained
		p.earned_total += gained
		var owed: float = p.upkeep_per_min * dt_min
		var paid: float = minf(owed, p.credits)
		p.credits -= paid
		p.spent_total += paid
		if p.credits < 0.0:
			p.credits = 0.0


func _step_construction(dt: float) -> void:
	if _sites.is_empty():
		return
	var finished: Array = []
	var gone: Array = []
	for s in _sites:
		var site := s as Site
		if not entities.is_alive(site.unit):
			gone.append(site)
			continue
		var pid: int = entities.owner[site.unit]
		site.remaining_seconds -= dt * _work_rate(pid)
		if site.remaining_seconds <= 0.0:
			site.remaining_seconds = 0.0
			finished.append(site)
	for s in gone:
		_forget_site(s as Site)
	for s in finished:
		var site := s as Site
		_forget_site(site)
		_log("player %d completed %s" % [entities.owner[site.unit], site.role])


func _forget_site(site: Site) -> void:
	_sites.erase(site)
	_site_of.erase(site.unit)


## docs/12: "Radars and factories both draw on it." A brownout slows work; it
## never stops it, so a player who loses a power plant is behind rather than
## paralysed.
func _work_rate(player_id: int) -> float:
	var p: Purse = _purses.get(player_id)
	if p == null:
		return 1.0
	return 0.35 + 0.65 * p.power_satisfaction()


func _step_production(dt: float) -> void:
	for pid in player_ids():
		var q: Array = _queues[pid]
		if q.is_empty():
			continue
		var rate := _work_rate(pid)
		var busy: Dictionary = {}    ## structure -> true. Indexed, never iterated
		var done: Array = []
		var orphaned: Array = []
		for j in q:
			var job := j as Job
			if not _owns_operational(pid, job.structure_unit):
				orphaned.append(job)
				continue
			if busy.has(job.structure_unit):
				continue
			busy[job.structure_unit] = true
			job.remaining_seconds -= dt * rate
			if job.remaining_seconds <= 0.0:
				done.append(job)
		# A factory that died refunds what it was holding. Losing the building
		# should cost you the building, not the building plus the queue.
		for j in orphaned:
			var job := j as Job
			q.erase(job)
			add_income(pid, job.cost)
			_log("player %d lost the line building %s, refunded %.0f"
				% [pid, job.def_key, job.cost])
		for j in done:
			var job := j as Job
			q.erase(job)
			_complete(pid, job)


func _complete(player_id: int, job: Job) -> void:
	var d := SimRoster.make(job.role, job.epoch,
		(_purses[player_id] as Purse).nation)
	if d == null:
		add_income(player_id, job.cost)
		return
	var spot := _exit_point(job.structure_unit, d)
	var heading: float = entities.heading_rad[job.structure_unit] \
		if entities.is_alive(job.structure_unit) else 0.0
	var i := _place(player_id, d, spot.x, spot.y, heading, false)
	if i < 0:
		add_income(player_id, job.cost)
		_log("player %d could not place %s, refunded" % [player_id, job.key])
		return
	_log("player %d produced %s" % [player_id, d.key])
	# Rally: a fresh unit walks to its factory's rally point rather than
	# blocking the door. Issued through the same movement layer as any order.
	var rally = _rally.get(job.structure_unit)
	if rally != null and movement != null:
		movement.order_move(i, rally.x, rally.y)


## Where a finished unit appears. Deterministic spiral outward from the
## structure until the ground suits the unit -- a ship must come out into
## water, a vehicle must not.
func _exit_point(structure_unit: int, d: SimUnitDef) -> Vector2:
	var sx: float = entities.pos_x[structure_unit] \
		if entities.is_alive(structure_unit) else 0.0
	var sz: float = entities.pos_z[structure_unit] \
		if entities.is_alive(structure_unit) else 0.0
	var sd := def_of(structure_unit)
	var base: float = (sd.footprint_m if sd != null else 12.0) + 10.0
	var wants_water: bool = d.category == SimTypes.Category.SURFACE \
		or d.category == SimTypes.Category.SUBSURFACE
	for ring in range(6):
		var r: float = base + float(ring) * 22.0
		for k in range(8):
			var a: float = float(k) * PI * 0.25
			var x: float = sx + sin(a) * r
			var z: float = sz + cos(a) * r
			if terrain == null:
				return Vector2(x, z)
			if absf(x) > terrain.extent_x_m() * 0.5 \
					or absf(z) > terrain.extent_z_m() * 0.5:
				continue
			if terrain.is_water(x, z) == wants_water:
				return Vector2(x, z)
	return Vector2(sx + base, sz)


func _step_research(dt: float) -> void:
	for pid in player_ids():
		var p := _purses[pid] as Purse
		if not p.is_advancing():
			continue
		# docs/12: the research facility is what advances you. Lose it mid-way
		# and the clock stops -- it does not reverse, and it does not refund.
		if not _has_research_facility(pid):
			continue
		p.advance_remaining_s -= dt * _work_rate(pid)
		p.advance_progress = clampf(
			1.0 - p.advance_remaining_s / p.advance_total_s, 0.0, 1.0)
		if p.advance_remaining_s <= 0.0:
			p.epoch = mini(p.epoch + 1, p.ceiling_epoch)
			p.advance_total_s = 0.0
			p.advance_remaining_s = 0.0
			p.advance_progress = 0.0
			_log("player %d reached epoch %d" % [pid, p.epoch])


## Burn, resupply, then run dry -- in that order. docs/04's failure modes are
## deliberately asymmetric: ground is immobilised and still fights, naval is
## dead in the water and recoverable, air is destroyed.
func _step_fuel(dt_min: float) -> void:
	var n := entities.count()
	for i in range(n):
		if entities.alive[i] == 0:
			continue
		if entities.fuel_capacity[i] <= 0.0:
			continue
		var lpm := entities.burn_rate_lpm(i)
		if lpm <= 0.0:
			continue
		entities.fuel[i] = maxf(entities.fuel[i] - lpm * dt_min, 0.0)

	_auto_resupply(dt_min)

	for i in range(n):
		if entities.alive[i] == 0:
			continue
		if entities.fuel_capacity[i] <= 0.0:
			continue
		if entities.fuel[i] > 0.0:
			_dry.erase(i)
			continue
		if entities.move_state[i] == SimTypes.MoveState.DEAD:
			continue
		# Only the TRANSITION into empty is an event. A tank that has been dry
		# for four minutes must not re-raise it every tick, or the log and the
		# alert the HUD hangs off it are both useless.
		if _dry.has(i):
			continue
		_dry[i] = true
		fuel_starvation.append(i)
		_run_dry(i)


## docs/04, "Running dry". The one place this file writes move_state, and it
## does so only on the transition into empty: the ownership table gives
## move_state to SimMovement, and SimEntities.can_move() already refuses a dry
## unit, so this is a flag being raised rather than a control loop being
## fought. Slot 3 runs before slot 4 precisely so movement sees it this tick.
func _run_dry(i: int) -> void:
	if entities.category[i] == SimTypes.Category.AIR:
		if damage != null:
			damage.apply_structure(i, entities.structure_max[i] * 2.0,
				"out of fuel")
			_log("%s ran out of fuel and came down" % entities.names[i])
		else:
			_log("%s is out of fuel in the air and the damage layer is not "
				% entities.names[i] + "wired -- it should have been destroyed")
		return
	if entities.move_state[i] != SimTypes.MoveState.IMMOBILE:
		entities.move_state[i] = SimTypes.MoveState.IMMOBILE
		var what := "dead in the water" if entities.category[i] \
			== SimTypes.Category.SURFACE else "immobilised"
		_log("%s is out of fuel -- %s" % [entities.names[i], what])


## docs/04: "Automation is the default at every level... The player should
## never click a refuel button." Every operational supply source tops up
## everything of its owner inside its radius, ascending, every tick.
func _auto_resupply(dt_min: float) -> void:
	for pid in player_ids():
		var owned := entities.indices_of_owner(pid)
		var sources := PackedInt32Array()
		for i in owned:
			var d := def_of(i)
			if d == null or not d.is_supply_source():
				continue
			if not is_operational(i):
				continue
			sources.append(i)
		if sources.is_empty():
			continue
		for s in sources:
			var sd := def_of(s)
			var budget: float = sd.supply_rate_lpm * dt_min
			for t in owned:
				if budget <= 0.0:
					break
				if t == s:
					continue
				if entities.fuel_capacity[t] <= 0.0:
					continue
				if entities.fuel[t] >= entities.fuel_capacity[t]:
					continue
				var moved := transfer_fuel(s, t, budget)
				budget -= moved


# ═══════════════════════════════════════════════════════════════════════════
# HELPERS
# ═══════════════════════════════════════════════════════════════════════════

func _owns_operational(player_id: int, unit: int) -> bool:
	if not entities.is_alive(unit):
		return false
	if entities.owner[unit] != player_id:
		return false
	return is_operational(unit)


func _has_research_facility(player_id: int) -> bool:
	var a: Aggregate = _agg.get(player_id)
	if a != null and a.has_research:
		return true
	# The aggregate is a tick old at worst; check directly so begin_epoch_
	# advance() works on the same tick a facility finishes.
	for i in entities.indices_of_owner(player_id):
		var d := def_of(i)
		if d != null and d.enables_advance and is_operational(i):
			return true
	return false


func _prerequisites_met(player_id: int, d: SimUnitDef) -> bool:
	if d == null:
		return false
	if d.requires.is_empty():
		return true
	var have: Dictionary = {}
	for i in entities.indices_of_owner(player_id):
		if entities.is_structure[i] == 1 and is_operational(i):
			have[role_of(i)] = true
	for req in d.requires:
		if not have.has(req):
			return false
	return true


func _dist2(ax: float, az: float, bx: float, bz: float) -> float:
	var dx := bx - ax
	var dz := bz - az
	return dx * dx + dz * dz


func _log(line: String) -> void:
	events.append(line)
	if events.size() > 512:
		events = events.slice(events.size() - 256)


## True once this class actually earns, spends and produces.
func is_implemented() -> bool:
	return true


# ═══════════════════════════════════════════════════════════════════════════
# SAVE / LOAD (SimSave)
#
# Purses, jobs, sites and aggregates are captured GENERICALLY -- every scalar
# field the object carries at save time, no hardcoded list -- so a field added
# to Purse by a parallel workflow is serialized the moment it exists.
# purse.setup is an object reference and is re-wired by whoever rebuilds the
# players (add_player_from_setup), not stored.
#
# _agg is saved even though it is recomputed every economy step: it is READ
# between economy steps (the AI's begin_epoch_advance consults has_research on
# the AI slot), so a zeroed aggregate could answer differently than the warm
# one for up to a second. spawned_this_step and fuel_starvation ARE dropped --
# both are produced and consumed inside the same economy slot. events is a
# cosmetic log and is dropped.
# ═══════════════════════════════════════════════════════════════════════════

func to_dict() -> Dictionary:
	var purses := {}
	var queues := {}
	var aggs := {}
	for pid in player_ids():
		purses[str(pid)] = SimSave.enc_props(_purses[pid], ["setup"])
		var jobs: Array = []
		for j in _queues[pid]:
			jobs.append(SimSave.enc_props(j))
		queues[str(pid)] = jobs
		aggs[str(pid)] = SimSave.enc_props(_agg[pid])
	var sites: Array = []
	for s in _sites:
		sites.append(SimSave.enc_props(s))
	var keys := {}
	for i in _def_key_of:
		keys[str(i)] = String(_def_key_of[i])
	var rally := {}
	for i in _rally:
		rally[str(i)] = SimSave.enc_v2(_rally[i])
	return {
		"purses": purses,
		"queues": queues,
		"aggregates": aggs,
		"sites": sites,
		"def_key_of": keys,
		"dry": SimSave.enc_ib(_dry),
		"rally": rally,
		"primary": SimSave.enc_ii(_primary),
		"spawn_serial": _spawn_serial,
		"rng": str(rng.state()),
	}


func from_dict(d: Dictionary) -> void:
	for pk in (d["purses"] as Dictionary):
		var pid := int(String(pk))
		if not _purses.has(pid):
			# A bare-world save with players nobody re-registered. Defaults are
			# immediately overwritten by the captured fields.
			add_player(pid, 0.0, EPOCH_FALLBACK, EPOCH_FALLBACK)
		SimSave.dec_props(_purses[pid], d["purses"][pk])
		var q: Array = []
		for jd in (d["queues"].get(pk, []) as Array):
			var job := Job.new()
			SimSave.dec_props(job, jd)
			q.append(job)
		_queues[pid] = q
		if d.has("aggregates") and (d["aggregates"] as Dictionary).has(pk):
			SimSave.dec_props(_agg[pid], d["aggregates"][pk])
	_sites.clear()
	_site_of.clear()
	for sd in (d["sites"] as Array):
		var site := Site.new()
		SimSave.dec_props(site, sd)
		_sites.append(site)
		_site_of[site.unit] = site
	_def_key_of.clear()
	for k in (d["def_key_of"] as Dictionary):
		_def_key_of[int(String(k))] = String(d["def_key_of"][k])
	_dry = SimSave.dec_ib(d["dry"])
	_rally.clear()
	for k in (d["rally"] as Dictionary):
		_rally[int(String(k))] = SimSave.dec_v2(d["rally"][k])
	_primary = SimSave.dec_ii(d["primary"])
	_spawn_serial = int(d["spawn_serial"])
	rng.restore_state(int(String(d["rng"])))


## Epoch a purse is created at when a save is restored with no setup to
## re-register it -- immediately overwritten by the captured purse fields.
const EPOCH_FALLBACK := 1


func describe(player_id: int) -> String:
	var p: Purse = _purses.get(player_id)
	if p == null:
		return "player %d has no purse" % player_id
	var lines := PackedStringArray()
	lines.append("player %d  epoch %d/%d  %.0f cr  (+%.0f/-%.0f per min)" % [
		player_id, p.epoch, p.ceiling_epoch, p.credits,
		p.income_per_min, p.upkeep_per_min])
	lines.append("  crude %.0f/min, refining %.0f/min   power %.0f/%.0f" % [
		p.extraction_per_min, p.refine_capacity, p.power_supply, p.power_draw])
	if p.is_advancing():
		lines.append("  advancing to epoch %d: %.0f%%"
			% [p.epoch + 1, p.advance_progress * 100.0])
	var q: Array = _queues.get(player_id, [])
	if not q.is_empty():
		var bits := PackedStringArray()
		for j in q:
			bits.append(str(j))
		lines.append("  queue: " + ", ".join(bits))
	return "\n".join(lines)
