class_name SimRoster
extends RefCounted
## The docs/12 role list as data, gated by the docs/05 epoch ladder.
##
## docs/12: "A role is not a unit. The content matrix is role x epoch x
## faction." This file is the ROLE axis and the EPOCH axis. Every number in
## ROLES is quoted AT EPOCH 1 and scaled on the way out by _stamp(), so
## advancing an epoch really does "upgrade existing production lines in place"
## (docs/05) without the roster carrying seven copies of every row.
##
## The FACTION axis is deliberately not here yet. docs/08 says factions cluster
## into three equipment lineages and differ by hardware filling the same role,
## which is a per-faction stat delta on top of these rows -- additive later,
## and a lie if it were faked now. faction_of() is threaded through every call
## so the seam exists; today it changes nothing but the display name prefix.
##
## DETERMINISM. Every listing function sorts. Nothing here draws a random
## number: a roster that varied per run would make the economy irreproducible
## from a seed, which docs/06 forbids.

const EPOCH_MIN := 1
const EPOCH_MAX := 7

# ── epoch scaling ────────────────────────────────────────────────────────────
## Cost climbs with capability. Roughly 2.3x from 1950 to now, which keeps a
## massed-obsolete army genuinely cheaper (docs/03's escape valve) without
## making an epoch-7 unit unaffordable.
const COST_MULT := [1.0, 1.22, 1.48, 1.80, 2.05, 2.20, 2.32]
const BUILD_TIME_MULT := [1.0, 1.08, 1.18, 1.30, 1.38, 1.44, 1.50]
const UPKEEP_MULT := [1.0, 1.15, 1.35, 1.60, 1.80, 1.95, 2.10]
## docs/04: "Gas-turbine tanks (1980s+) burn dramatically more than diesels."
## Epoch 4 is the 1980s, and the step is deliberately visible.
const BURN_MULT := [1.0, 1.05, 1.15, 1.75, 1.80, 1.78, 1.72]
const SPEED_MULT := [1.0, 1.06, 1.12, 1.18, 1.22, 1.26, 1.30]
const HP_MULT := [1.0, 1.10, 1.25, 1.45, 1.60, 1.72, 1.82]
## docs/11 §3, R1-R6: reference range against a 1 m^2 target grows with the set.
const RADAR_MULT := [0.55, 0.70, 0.85, 1.00, 1.15, 1.30, 1.45]

## Thickness ladders. docs/03's cliff is a TYPE change as much as a thickness
## change, so the two are tabulated separately and applied together.
const THICKNESS_HEAVY := [1.0, 1.30, 1.90, 2.60, 3.00, 3.30, 3.50]
const THICKNESS_LIGHT := [1.0, 1.15, 1.40, 1.80, 2.10, 2.30, 2.40]
const THICKNESS_FLAT  := [1.0, 1.05, 1.10, 1.15, 1.20, 1.25, 1.30]


static var _roles: Dictionary = {}
static var _cache: Dictionary = {}


# ═══════════════════════════════════════════════════════════════════════════
# LOOKUP
# ═══════════════════════════════════════════════════════════════════════════

## Every role key, ascending. Ascending because docs/06 forbids relying on
## Dictionary order anywhere the order can reach the outcome, and a build menu
## that reshuffles between runs is exactly that.
static func role_keys() -> PackedStringArray:
	_ensure()
	var keys: Array = _roles.keys()
	keys.sort()
	var out := PackedStringArray()
	for k in keys:
		out.append(k)
	return out


static func has_role(role: String) -> bool:
	_ensure()
	return _roles.has(role)


static func row(role: String) -> Dictionary:
	_ensure()
	return _roles.get(role, {})


## "mbt_e5" -> {"role": "mbt", "epoch": 5}. A bare "mbt" returns epoch 0,
## meaning "whatever epoch the asking player is at" -- which is how docs/05's
## "upgrades existing production lines in place" is expressed: the player
## queues a ROLE and gets the current generation of it.
static func parse_key(def_key: String) -> Dictionary:
	var at := def_key.rfind("_e")
	if at > 0:
		var tail := def_key.substr(at + 2)
		if tail.is_valid_int():
			return {"role": def_key.substr(0, at), "epoch": int(tail)}
	return {"role": def_key, "epoch": 0}


static func key_for(role: String, epoch: int) -> String:
	return "%s_e%d" % [role, clampi(epoch, EPOCH_MIN, EPOCH_MAX)]


## The def for a role at an epoch. Returns null for an unknown role or for an
## epoch the role does not exist in -- docs/12's Epoch column is a gate, not a
## suggestion. Instances are CACHED and shared: a def is immutable data, and
## handing out one instance per unit would be exactly the per-unit object the
## structure-of-arrays store exists to avoid.
static func make(role: String, epoch: int, faction := -1) -> SimUnitDef:
	_ensure()
	if not _roles.has(role):
		return null
	var e: int = clampi(epoch, EPOCH_MIN, EPOCH_MAX)
	var r: Dictionary = _roles[role]
	if e < int(r.get("first_epoch", 1)) or e > int(r.get("last_epoch", EPOCH_MAX)):
		return null
	# The faction axis (docs/08). A researched ABSENCE -- the data covering
	# this faction/role/epoch and saying "fielded nothing" -- gates the def
	# exactly like the epoch column does: Taiwan queues no bombers.
	if faction >= 0 and SimFactionData.denied(faction, role, e):
		return null
	var ck := "%s|%d|%d" % [role, e, faction]
	if _cache.has(ck):
		return _cache[ck]
	var d := _stamp(role, r, e, faction)
	_cache[ck] = d
	return d


## Resolve a def key against a player's epoch. A bare role key means "current
## generation"; an explicit "_eN" key is honoured but still refused above the
## player's epoch, which is what stops a queue entry outliving a load order.
static func resolve(def_key: String, player_epoch: int, faction := -1) -> SimUnitDef:
	var p := parse_key(def_key)
	var e: int = int(p["epoch"])
	if e <= 0:
		e = player_epoch
	if e > player_epoch:
		return null
	return make(String(p["role"]), e, faction)


## Everything a player at `epoch` with these domain bits may build. Ascending.
static func available(epoch: int, allowed_domains: int) -> PackedStringArray:
	var out := PackedStringArray()
	for role in role_keys():
		var r: Dictionary = _roles[role]
		if epoch < int(r.get("first_epoch", 1)):
			continue
		if epoch > int(r.get("last_epoch", EPOCH_MAX)):
			continue
		if (int(r.get("domain", 0)) & allowed_domains) == 0:
			continue
		out.append(role)
	return out


## What one structure role can produce at an epoch. This is derived from the
## mobile rows' `built_by` rather than listed on the structure, so a new role
## cannot be added and then silently be unbuildable anywhere.
static func produced_by(structure_role: String, epoch: int,
		allowed_domains: int) -> PackedStringArray:
	var out := PackedStringArray()
	for role in available(epoch, allowed_domains):
		if String(_roles[role].get("built_by", "")) == structure_role:
			out.append(role)
	return out


static func is_structure_role(role: String) -> bool:
	_ensure()
	return bool(_roles.get(role, {}).get("is_structure", false))


static func role_count() -> int:
	_ensure()
	return _roles.size()


# ═══════════════════════════════════════════════════════════════════════════
# STAMPING
# ═══════════════════════════════════════════════════════════════════════════

static func _stamp(role: String, r: Dictionary, e: int, faction: int) -> SimUnitDef:
	var d := SimUnitDef.new()
	var k := e - 1
	d.role = role
	d.epoch = e
	d.key = key_for(role, e)
	d.name = String(r.get("name", role))
	d.first_epoch = int(r.get("first_epoch", 1))
	d.last_epoch = int(r.get("last_epoch", EPOCH_MAX))
	d.domain = int(r.get("domain", SimPlayerSetup.Domain.GROUND))
	d.category = int(r.get("category", SimTypes.Category.GROUND))
	d.is_structure = bool(r.get("is_structure", false))

	d.cost = float(r.get("cost", 100.0)) * COST_MULT[k]
	d.build_seconds = float(r.get("build_seconds", 10.0)) * BUILD_TIME_MULT[k]
	d.upkeep = float(r.get("upkeep", 0.0)) * UPKEEP_MULT[k]
	d.built_by = String(r.get("built_by", ""))
	for req in r.get("requires", []):
		d.requires.append(String(req))

	d.speed_kmh = float(r.get("speed_kmh", 0.0)) * SPEED_MULT[k]
	d.accel_ms2 = float(r.get("accel_ms2", 1.5))
	d.turn_rate_rads = float(r.get("turn_rate_rads", 0.6))

	d.fuel_capacity = float(r.get("fuel", 0.0))
	d.burn_idle = float(r.get("burn_idle", 0.0)) * BURN_MULT[k]
	d.burn_cruise = float(r.get("burn_cruise", 0.0)) * BURN_MULT[k]
	d.burn_combat = float(r.get("burn_combat", 0.0)) * BURN_MULT[k]
	d.nuclear = bool(r.get("nuclear", false))
	d.nuclear_from_epoch = int(r.get("nuclear_from_epoch", 99))
	# docs/04: nuclear propulsion removes the constraint outright.
	if d.nuclear and e >= d.nuclear_from_epoch:
		d.fuel_capacity = 0.0
		d.burn_idle = 0.0; d.burn_cruise = 0.0; d.burn_combat = 0.0

	d.damage_model = int(r.get("damage_model", SimTypes.DamageModel.UNARMORED))
	d.structure_hp = float(r.get("hp", 100.0)) * HP_MULT[k]
	d.armor = String(r.get("armor", "none"))
	d.armor_class = int(r.get("armor_class", -1))

	d.rcs_m2 = float(r.get("rcs", 5.0))
	d.ir_band = float(r.get("ir", 1.0))
	d.acoustic_db = float(r.get("acoustic", 90.0))
	d.visual_m2 = float(r.get("visual", 10.0))
	d.magnetic = float(r.get("magnetic", 0.0))
	d.mount_height_m = float(r.get("mount", 2.0))
	d.sensor = String(r.get("sensor", ""))

	d.cargo_slots = int(r.get("cargo_slots", 0))
	d.carries_vehicles = bool(r.get("carries_vehicles", false))
	d.deploy_seconds = float(r.get("deploy_seconds", 0.0))
	d.undeploy_seconds = float(r.get("undeploy_seconds", d.deploy_seconds))
	d.fires_deployed_only = bool(r.get("fires_deployed_only",
		d.deploy_seconds > 0.0))

	d.power_draw = float(r.get("power_draw", 0.0))
	d.power_supply = float(r.get("power_supply", 0.0))
	d.extraction_per_min = float(r.get("extraction", 0.0))
	d.ore_capacity = float(r.get("ore_capacity", 0.0))
	d.mine_rate = float(r.get("mine_rate", 0.0))
	d.unload_rate = float(r.get("unload_rate", 0.0))
	d.refine_capacity = float(r.get("refine", 0.0))
	d.supply_radius_m = float(r.get("supply_radius", 0.0))
	d.supply_rate_lpm = float(r.get("supply_rate", 0.0))
	d.supply_infinite = bool(r.get("supply_infinite", false))
	d.enables_advance = bool(r.get("enables_advance", false))
	d.build_radius_m = float(r.get("build_radius", 0.0))
	d.footprint_m = float(r.get("footprint", 12.0))

	# The faction axis, last: the researched national roster overlays the
	# fully-stamped baseline (designation, speed, dims, mass, crew, range),
	# and the model stem is resolved against what is actually on disk. The
	# baseline remains the fallback for every field the data does not attest.
	d.base_name = d.name
	d.model_stem = SimFactionData.model_stem_for(role, faction, e)
	if faction >= 0:
		SimFactionData.overlay(d, faction)
	return d


## Per-facet millimetres for an archetype at an epoch, AFTER slope, exactly as
## docs/03 quotes armour.
static func armor_facets(archetype: String, epoch: int) -> Array:
	var k: int = clampi(epoch, EPOCH_MIN, EPOCH_MAX) - 1
	var base: Array = _ARCHETYPE_FACETS().get(archetype, [0.0, 0.0, 0.0, 0.0, 0.0])
	var mult: float = _ARCHETYPE_THICKNESS().get(archetype, THICKNESS_FLAT)[k]
	var out: Array = []
	for v in base:
		out.append(float(v) * mult)
	return out


## The ArmorType of an archetype at an epoch. This is where docs/03's cliff
## lives: an epoch-2 SPACED glacis and an epoch-3 COMPOSITE one are not 30%
## apart against CE, they are a different problem.
static func armor_types(archetype: String, epoch: int) -> Array:
	var k: int = clampi(epoch, EPOCH_MIN, EPOCH_MAX) - 1
	var ladder: Array = _ARCHETYPE_TYPES().get(archetype, [])
	if ladder.is_empty():
		return [SimTypes.ArmorType.NONE, SimTypes.ArmorType.NONE,
			SimTypes.ArmorType.NONE, SimTypes.ArmorType.NONE,
			SimTypes.ArmorType.NONE]
	var t: int = ladder[k]
	return [t, t, t, t, t]


## Sensors a role carries at an epoch. Built fresh per unit because
## SimEntities.sensors stores the array per index and the solver mutates
## nothing on it -- but phase_offset is per unit, so sharing one instance
## across a hundred vehicles would make them all revisit on the same tick.
## REVISIT TIME, in seconds. docs/02 §9: "a radar's real revisit time is
## seconds anyway", which is why the solver runs at 5 Hz rather than the
## simulation rate. The same argument applies one level down and was not being
## made: every sensor here left revisit_seconds at 0, meaning "look at
## everything, every solve", so a mechanically-scanned search radar was
## re-detecting the whole map twenty times a second's worth of solves.
##
## These are the real numbers. A rotating S-band search set turns at about
## 15 rpm, so it sweeps past a given bearing once every four seconds and is
## looking somewhere else in between. An E-3's rotodome is slower still. An
## ILLUMINATOR is the exception and is deliberately 0: continuous illumination
## is what SARH guidance is, and a beam that looked away would break the
## missile's lock (docs/02 §5).
##
## The saving is large -- the solve is O(sensors x targets) and this divides
## the sensor term -- but the reason to do it is that it is what radars do.
## SimSensorDef.phase_offset, which SimEconomy already threads through as a
## per-unit spawn serial, is what stops a hundred vehicles all revisiting on
## the same tick.
const REVISIT := {
	"optics": 0.4,              ## a crew looking through a sight
	"recon optics": 0.4,
	"search radar": 4.0,        ## ~15 rpm
	"fixed search radar": 10.0, ## ~6 rpm, long-range L-band
	"illuminator": 0.0,         ## continuous, by definition
	"fire-control radar": 0.6,  ## electronically scanned, near-continuous
	"AEW&C radar": 10.0,        ## rotodome
	"AEW radar": 8.0,
	"ESM": 2.0,                 ## a receiver scans bands
	"air search": 4.0,
	"surface search": 3.0,
	"hull sonar": 2.0,
	"towed array": 2.0,
	"bow array": 2.0,
	"dipping sonar": 0.0,       ## pinging while it is in the water
	"MAD": 0.5,
	"counter-battery radar": 2.0,
}


## Give every sensor its revisit time from the table above, by name, and hand
## back the same array. Applied in one place so a new archetype cannot quietly
## be added with the old "look at everything, every solve" behaviour.
static func _with_revisit(sensors: Array) -> Array:
	for s in sensors:
		var sensor := s as SimSensorDef
		sensor.revisit_seconds = float(REVISIT.get(sensor.name, 1.0))
	return sensors


static func sensors_for(archetype: String, epoch: int, phase := 0) -> Array:
	return _with_revisit(_sensors_for(archetype, epoch, phase))


static func _sensors_for(archetype: String, epoch: int, phase := 0) -> Array:
	var k: int = clampi(epoch, EPOCH_MIN, EPOCH_MAX) - 1
	var rm: float = RADAR_MULT[k]
	var gen: int = clampi(int(round(float(epoch) * 6.0 / 7.0)), 1, 6)
	match archetype:
		"eo":
			return [SimSensorDef.new({"name": "optics", "domain": SimTypes.Domain.EO,
				"reference_range_km": 4.0 + 1.1 * float(epoch), "mount_height_m": 3.0,
				"emits": false, "max_quality": SimTypes.TrackQuality.FIRE_CONTROL,
				"phase_offset": phase})]
		"recon":
			return [
				SimSensorDef.new({"name": "recon optics", "domain": SimTypes.Domain.EO,
					"reference_range_km": 9.0 + 1.8 * float(epoch), "mount_height_m": 4.0,
					"emits": false, "max_quality": SimTypes.TrackQuality.FIRE_CONTROL,
					"phase_offset": phase}),
				SimSensorDef.new({"name": "ESM", "domain": SimTypes.Domain.RF_PASSIVE,
					"reference_range_km": 120.0 * rm, "mount_height_m": 5.0,
					"emits": false, "esm_gen": gen,
					"max_quality": SimTypes.TrackQuality.CONTACT,
					"phase_offset": phase})]
		"search":
			return [SimSensorDef.new({"name": "search radar",
				"domain": SimTypes.Domain.RF_ACTIVE, "band": SimTypes.Band.S,
				"reference_range_km": 130.0 * rm, "mount_height_m": 12.0,
				"radar_gen": gen, "eccm_rating": maxi(gen - 2, 0),
				"max_quality": SimTypes.TrackQuality.TRACK, "phase_offset": phase})]
		"fixed_search":
			return [SimSensorDef.new({"name": "fixed search radar",
				"domain": SimTypes.Domain.RF_ACTIVE, "band": SimTypes.Band.L,
				"reference_range_km": 200.0 * rm, "mount_height_m": 28.0,
				"radar_gen": gen, "eccm_rating": maxi(gen - 2, 0),
				"max_quality": SimTypes.TrackQuality.TRACK, "phase_offset": phase})]
		"illuminator":
			return [SimSensorDef.new({"name": "illuminator",
				"domain": SimTypes.Domain.RF_ACTIVE, "band": SimTypes.Band.X,
				"reference_range_km": 75.0 * rm, "mount_height_m": 9.0,
				"radar_gen": gen, "eccm_rating": maxi(gen - 1, 0),
				"max_quality": SimTypes.TrackQuality.FIRE_CONTROL,
				"phase_offset": phase})]
		"aew":
			# docs/12: "A radar 9 km up. Turns a 32 km horizon into 400 km."
			return [SimSensorDef.new({"name": "AEW&C radar",
				"domain": SimTypes.Domain.RF_ACTIVE, "band": SimTypes.Band.S,
				"reference_range_km": 320.0 * rm, "mount_height_m": 9000.0,
				"radar_gen": gen, "aew_gen": clampi(epoch - 2, 1, 5),
				"eccm_rating": maxi(gen - 1, 0),
				"max_quality": SimTypes.TrackQuality.FIRE_CONTROL,
				"phase_offset": phase})]
		"aew_heli":
			return [SimSensorDef.new({"name": "AEW radar",
				"domain": SimTypes.Domain.RF_ACTIVE, "band": SimTypes.Band.S,
				"reference_range_km": 180.0 * rm, "mount_height_m": 3000.0,
				"radar_gen": gen, "aew_gen": clampi(epoch - 3, 1, 5),
				"max_quality": SimTypes.TrackQuality.FIRE_CONTROL,
				"phase_offset": phase})]
		"fighter_radar":
			return [SimSensorDef.new({"name": "fire-control radar",
				"domain": SimTypes.Domain.RF_ACTIVE, "band": SimTypes.Band.X,
				"reference_range_km": 90.0 * rm, "mount_height_m": 0.0,
				"radar_gen": gen, "eccm_rating": maxi(gen - 2, 0),
				"max_quality": SimTypes.TrackQuality.FIRE_CONTROL,
				"phase_offset": phase})]
		"esm":
			return [SimSensorDef.new({"name": "ESM", "domain": SimTypes.Domain.RF_PASSIVE,
				"reference_range_km": 260.0 * rm, "mount_height_m": 6.0,
				"emits": false, "esm_gen": gen,
				"max_quality": SimTypes.TrackQuality.CONTACT, "phase_offset": phase})]
		"naval":
			return [
				SimSensorDef.new({"name": "air search",
					"domain": SimTypes.Domain.RF_ACTIVE, "band": SimTypes.Band.S,
					"reference_range_km": 210.0 * rm, "mount_height_m": 30.0,
					"radar_gen": gen, "eccm_rating": maxi(gen - 1, 0),
					"max_quality": SimTypes.TrackQuality.FIRE_CONTROL,
					"phase_offset": phase}),
				SimSensorDef.new({"name": "hull sonar",
					"domain": SimTypes.Domain.ACOUSTIC_PASSIVE,
					"reference_range_km": 35.0, "mount_height_m": -20.0,
					"emits": false,
					"max_quality": SimTypes.TrackQuality.CONTACT,
					"phase_offset": phase})]
		"asw_ship":
			return [
				SimSensorDef.new({"name": "surface search",
					"domain": SimTypes.Domain.RF_ACTIVE, "band": SimTypes.Band.X,
					"reference_range_km": 90.0 * rm, "mount_height_m": 24.0,
					"radar_gen": gen, "max_quality": SimTypes.TrackQuality.TRACK,
					"phase_offset": phase}),
				SimSensorDef.new({"name": "towed array",
					"domain": SimTypes.Domain.ACOUSTIC_PASSIVE,
					"reference_range_km": 90.0, "mount_height_m": -150.0,
					"emits": false, "max_quality": SimTypes.TrackQuality.CONTACT,
					"phase_offset": phase})]
		"submarine":
			return [SimSensorDef.new({"name": "bow array",
				"domain": SimTypes.Domain.ACOUSTIC_PASSIVE,
				"reference_range_km": 60.0, "mount_height_m": -60.0,
				"emits": false, "max_quality": SimTypes.TrackQuality.CONTACT,
				"phase_offset": phase})]
		"dipping":
			return [SimSensorDef.new({"name": "dipping sonar",
				"domain": SimTypes.Domain.ACOUSTIC_ACTIVE,
				"reference_range_km": 28.0, "mount_height_m": -60.0,
				"max_quality": SimTypes.TrackQuality.FIRE_CONTROL,
				"phase_offset": phase})]
		"mpa":
			return [
				SimSensorDef.new({"name": "search radar",
					"domain": SimTypes.Domain.RF_ACTIVE, "band": SimTypes.Band.X,
					"reference_range_km": 150.0 * rm, "mount_height_m": 0.0,
					"radar_gen": gen, "max_quality": SimTypes.TrackQuality.TRACK,
					"phase_offset": phase}),
				SimSensorDef.new({"name": "MAD", "domain": SimTypes.Domain.MAGNETIC,
					"reference_range_km": 1.2, "mount_height_m": 0.0,
					"emits": false, "max_quality": SimTypes.TrackQuality.CONTACT,
					"phase_offset": phase})]
		"counter_battery":
			return [SimSensorDef.new({"name": "counter-battery radar",
				"domain": SimTypes.Domain.RF_ACTIVE, "band": SimTypes.Band.C,
				"reference_range_km": 60.0 * rm, "mount_height_m": 8.0,
				"radar_gen": gen, "max_quality": SimTypes.TrackQuality.TRACK,
				"phase_offset": phase})]
	return []


# ═══════════════════════════════════════════════════════════════════════════
# THE TABLES
# ═══════════════════════════════════════════════════════════════════════════

static func _ARCHETYPE_FACETS() -> Dictionary:
	return {
		"none":     [0.0, 0.0, 0.0, 0.0, 0.0],
		"soft":     [8.0, 6.0, 6.0, 4.0, 4.0],
		"light":    [35.0, 18.0, 14.0, 10.0, 8.0],
		"medium":   [90.0, 45.0, 32.0, 22.0, 16.0],
		"heavy":    [200.0, 90.0, 55.0, 40.0, 30.0],
		"building": [70.0, 70.0, 70.0, 35.0, 25.0],
		"bunker":   [420.0, 420.0, 420.0, 260.0, 130.0],
	}


static func _ARCHETYPE_THICKNESS() -> Dictionary:
	return {
		"none": THICKNESS_FLAT, "soft": THICKNESS_FLAT,
		"light": THICKNESS_LIGHT, "medium": THICKNESS_HEAVY,
		"heavy": THICKNESS_HEAVY, "building": THICKNESS_FLAT,
		"bunker": THICKNESS_FLAT,
	}


static func _ARCHETYPE_TYPES() -> Dictionary:
	return {
		"none": [SimTypes.ArmorType.NONE, SimTypes.ArmorType.NONE, SimTypes.ArmorType.NONE, SimTypes.ArmorType.NONE, SimTypes.ArmorType.NONE, SimTypes.ArmorType.NONE, SimTypes.ArmorType.NONE],
		"soft": [SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA],
		"light": [SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.SPACED, SimTypes.ArmorType.ERA_LIGHT, SimTypes.ArmorType.ERA_LIGHT,
			SimTypes.ArmorType.MODULAR_ERA],
		"medium": [SimTypes.ArmorType.CAST, SimTypes.ArmorType.SPACED, SimTypes.ArmorType.NERA, SimTypes.ArmorType.COMPOSITE, SimTypes.ArmorType.COMPOSITE_HEAVY,
			SimTypes.ArmorType.ERA_HEAVY, SimTypes.ArmorType.MODULAR_ERA],
		# docs/03's generational cliff, as a type ladder. Epoch 3 is where a
		# 1950s gun stops working at all, which docs/05 calls the most dramatic
		# transition in the game.
		"heavy": [SimTypes.ArmorType.CAST, SimTypes.ArmorType.SPACED, SimTypes.ArmorType.COMPOSITE, SimTypes.ArmorType.COMPOSITE_HEAVY, SimTypes.ArmorType.ERA_HEAVY,
			SimTypes.ArmorType.MODULAR_ERA, SimTypes.ArmorType.MODULAR_ERA],
		"building": [SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA],
		"bunker": [SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA],
	}


## The role table. One row per docs/12 role; every figure is AT EPOCH 1.
## Built lazily in a static so the enum names above can be spelled out --
## a `const` Dictionary in GDScript cannot reference SimTypes at all, and
## eighty-eight rows of bare integers is a table nobody can check against
## the document it came from.
static func _ensure() -> void:
	if not _roles.is_empty():
		return
	var S := SimPlayerSetup.Domain.STRUCTURES
	var G := SimPlayerSetup.Domain.GROUND
	var I := SimPlayerSetup.Domain.INFANTRY
	var A := SimPlayerSetup.Domain.AIR
	var N := SimPlayerSetup.Domain.NAVAL

	_roles = {

	# ══ STRUCTURES — docs/12, 19 roles ══════════════════════════════════════
	# Placed with the BUILD order, inside the build radius of something you
	# already own. Every one of them is an ENTITY in the same store, so every
	# one of them can be shot at.
	"hq": {"name": "Headquarters", "domain": S, "category": SimTypes.Category.GROUND,
		"is_structure": true, "cost": 1500.0, "build_seconds": 40.0,
		"upkeep": 0.0, "damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 900.0,
		"armor": "building", "build_radius": 340.0, "footprint": 26.0,
		"supply_radius": 260.0, "supply_rate": 60.0, "supply_infinite": true,
		"rcs": 400.0, "visual": 900.0, "mount": 14.0},
	"power_plant": {"name": "Power Plant", "domain": S, "category": SimTypes.Category.GROUND,
		"is_structure": true, "cost": 700.0, "build_seconds": 25.0,
		"damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 500.0, "armor": "building",
		"power_supply": 100.0, "build_radius": 140.0,
		"rcs": 300.0, "visual": 600.0, "mount": 18.0, "ir": 6.0},
	# THE HARVESTER. Unarmed on purpose: it is the piece whose loss hurts, and
	# a harvester that could defend itself would not be a target worth raiding.
	# 700 credits a load against a 900 credit vehicle means a raid that kills
	# one loaded harvester has taken more than the vehicle cost its owner.
	"ore_miner": {"name": "Ore Miner", "domain": G, "category": SimTypes.Category.GROUND,
		"cost": 900.0, "build_seconds": 16.0, "built_by": "light_factory",
		"damage_model": SimTypes.DamageModel.ARMORED, "hp": 260.0, "armor": "light_vehicle",
		"speed_kmh": 46.0, "accel": 2.2, "turn": 1.0, "footprint": 9.0,
		"ore_capacity": 700.0, "mine_rate": 62.0, "unload_rate": 260.0,
		"upkeep": 6.0, "fuel": 320.0, "burn_cruise": 1.0,
		"rcs": 90.0, "visual": 260.0, "ir": 4.0, "mount": 3.0},
	"oil_derrick": {"name": "Oil Derrick", "domain": S, "category": SimTypes.Category.GROUND,
		"is_structure": true, "cost": 900.0, "build_seconds": 20.0,
		"damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 350.0, "armor": "building",
		"extraction": 240.0, "build_radius": 90.0,
		"rcs": 220.0, "visual": 400.0, "mount": 20.0},
	"refinery": {"name": "Refinery", "domain": S, "category": SimTypes.Category.GROUND,
		"is_structure": true, "cost": 1400.0, "build_seconds": 35.0,
		"damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 600.0, "armor": "building",
		"refine": 520.0, "power_draw": 30.0, "build_radius": 160.0,
		"supply_radius": 220.0, "supply_rate": 120.0, "supply_infinite": true,
		"rcs": 500.0, "visual": 1100.0, "mount": 22.0, "ir": 5.0},
	"supply_depot": {"name": "Supply Depot", "domain": S, "category": SimTypes.Category.GROUND,
		"is_structure": true, "cost": 600.0, "build_seconds": 18.0,
		"damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 400.0, "armor": "building",
		"supply_radius": 340.0, "supply_rate": 160.0, "supply_infinite": true,
		"build_radius": 200.0, "rcs": 180.0, "visual": 380.0, "mount": 8.0},
	"barracks": {"name": "Barracks", "domain": S, "category": SimTypes.Category.GROUND,
		"is_structure": true, "cost": 500.0, "build_seconds": 20.0,
		"damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 400.0, "armor": "building",
		"power_draw": 10.0, "build_radius": 120.0,
		"rcs": 150.0, "visual": 350.0, "mount": 8.0},
	"light_factory": {"name": "Light Vehicle Factory", "domain": S,
		"category": SimTypes.Category.GROUND, "is_structure": true, "cost": 900.0,
		"build_seconds": 28.0, "damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 500.0,
		"armor": "building", "power_draw": 25.0, "build_radius": 140.0,
		"rcs": 260.0, "visual": 520.0, "mount": 10.0},
	"heavy_factory": {"name": "Heavy Vehicle Factory", "domain": S,
		"category": SimTypes.Category.GROUND, "is_structure": true, "cost": 1600.0,
		"build_seconds": 40.0, "damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 700.0,
		"armor": "building", "power_draw": 45.0, "build_radius": 160.0,
		"requires": ["power_plant"], "footprint": 20.0,
		"rcs": 380.0, "visual": 780.0, "mount": 12.0},
	"airbase": {"name": "Airbase", "domain": S, "category": SimTypes.Category.GROUND,
		"is_structure": true, "cost": 2000.0, "build_seconds": 50.0,
		"damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 800.0, "armor": "building",
		"power_draw": 40.0, "build_radius": 180.0, "footprint": 48.0,
		"supply_radius": 240.0, "supply_rate": 900.0, "supply_infinite": true,
		"requires": ["power_plant"], "rcs": 600.0, "visual": 2400.0, "mount": 6.0},
	"hardened_shelter": {"name": "Hardened Aircraft Shelter", "domain": S,
		"category": SimTypes.Category.GROUND, "is_structure": true, "first_epoch": 2,
		"cost": 800.0, "build_seconds": 25.0, "damage_model": SimTypes.DamageModel.STRUCTURE,
		"hp": 900.0, "armor": "bunker", "requires": ["airbase"],
		"build_radius": 60.0, "rcs": 120.0, "visual": 300.0, "mount": 6.0},
	"helipad": {"name": "Helipad", "domain": S, "category": SimTypes.Category.GROUND,
		"is_structure": true, "first_epoch": 2, "cost": 500.0,
		"build_seconds": 18.0, "damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 350.0,
		"armor": "building", "power_draw": 8.0, "build_radius": 120.0,
		"supply_radius": 140.0, "supply_rate": 300.0, "supply_infinite": true,
		"rcs": 90.0, "visual": 260.0, "mount": 4.0},
	"naval_yard": {"name": "Naval Yard", "domain": S, "category": SimTypes.Category.GROUND,
		"is_structure": true, "cost": 1800.0, "build_seconds": 45.0,
		"damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 700.0, "armor": "building",
		"power_draw": 40.0, "build_radius": 180.0, "footprint": 36.0,
		"rcs": 520.0, "visual": 1400.0, "mount": 16.0},
	"fixed_radar": {"name": "Fixed Radar Station", "domain": S,
		"category": SimTypes.Category.GROUND, "is_structure": true, "cost": 1100.0,
		"build_seconds": 30.0, "damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 400.0,
		"armor": "building", "power_draw": 55.0, "sensor": "fixed_search",
		"mount": 28.0, "build_radius": 80.0,
		"rcs": 240.0, "visual": 300.0},
	"fixed_sam": {"name": "Fixed SAM Site", "domain": S, "category": SimTypes.Category.GROUND,
		"is_structure": true, "first_epoch": 2, "cost": 1200.0,
		"build_seconds": 30.0, "damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 500.0,
		"armor": "bunker", "power_draw": 35.0, "sensor": "illuminator",
		"build_radius": 60.0, "rcs": 160.0, "visual": 280.0, "mount": 9.0},
	"coastal_battery": {"name": "Coastal Battery", "domain": S,
		"category": SimTypes.Category.GROUND, "is_structure": true, "first_epoch": 2,
		"cost": 1000.0, "build_seconds": 28.0, "damage_model": SimTypes.DamageModel.STRUCTURE,
		"hp": 600.0, "armor": "bunker", "build_radius": 60.0,
		"rcs": 120.0, "visual": 260.0, "mount": 8.0},
	"ew_station": {"name": "EW Station", "domain": S, "category": SimTypes.Category.GROUND,
		"is_structure": true, "first_epoch": 2, "cost": 1300.0,
		"build_seconds": 32.0, "damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 400.0,
		"armor": "building", "power_draw": 70.0, "sensor": "esm",
		"build_radius": 80.0, "rcs": 200.0, "visual": 320.0, "mount": 20.0},
	"research_facility": {"name": "Research Facility", "domain": S,
		"category": SimTypes.Category.GROUND, "is_structure": true, "cost": 1500.0,
		"build_seconds": 45.0, "damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 550.0,
		"armor": "building", "power_draw": 50.0, "enables_advance": true,
		"build_radius": 140.0, "requires": ["power_plant"],
		"rcs": 300.0, "visual": 640.0, "mount": 12.0},
	"repair_depot": {"name": "Repair Depot", "domain": S, "category": SimTypes.Category.GROUND,
		"is_structure": true, "cost": 900.0, "build_seconds": 25.0,
		"damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 450.0, "armor": "building",
		"power_draw": 20.0, "build_radius": 140.0,
		"supply_radius": 200.0, "supply_rate": 140.0, "supply_infinite": true,
		"rcs": 220.0, "visual": 480.0, "mount": 10.0},
	"bunker": {"name": "Bunker", "domain": S, "category": SimTypes.Category.GROUND,
		"is_structure": true, "cost": 400.0, "build_seconds": 15.0,
		"damage_model": SimTypes.DamageModel.STRUCTURE, "hp": 800.0, "armor": "bunker",
		"build_radius": 0.0, "footprint": 10.0,
		"rcs": 40.0, "visual": 90.0, "mount": 3.0},

	# ══ GROUND — manoeuvre ══════════════════════════════════════════════════
	"mbt": {"name": "Main Battle Tank", "domain": G, "category": SimTypes.Category.GROUND,
		"built_by": "heavy_factory", "cost": 900.0, "build_seconds": 22.0,
		"upkeep": 14.0, "speed_kmh": 60.0, "accel_ms2": 1.8,
		"turn_rate_rads": 0.55, "fuel": 1600.0, "burn_idle": 4.0,
		"burn_cruise": 22.0, "burn_combat": 60.0,
		"damage_model": SimTypes.DamageModel.ARMORED, "hp": 120.0, "armor": "heavy",
		"armor_class": 3, "sensor": "eo", "rcs": 25.0, "ir": 2.2,
		"visual": 26.0, "mount": 3.0},
	"light_tank": {"name": "Light Tank / Tank Destroyer", "domain": G,
		"category": SimTypes.Category.GROUND, "built_by": "heavy_factory", "cost": 620.0,
		"build_seconds": 16.0, "upkeep": 9.0, "speed_kmh": 70.0,
		"fuel": 900.0, "burn_idle": 3.0, "burn_cruise": 16.0,
		"burn_combat": 42.0, "damage_model": SimTypes.DamageModel.ARMORED, "hp": 90.0,
		"armor": "medium", "armor_class": 2, "sensor": "eo",
		"rcs": 18.0, "ir": 1.6, "visual": 18.0, "mount": 2.8},
	"ifv": {"name": "IFV", "domain": G, "category": SimTypes.Category.GROUND, "first_epoch": 3,
		"built_by": "heavy_factory", "cost": 560.0, "build_seconds": 15.0,
		"upkeep": 8.0, "speed_kmh": 70.0, "fuel": 800.0, "burn_idle": 3.0,
		"burn_cruise": 14.0, "burn_combat": 36.0, "damage_model": SimTypes.DamageModel.ARMORED,
		"hp": 85.0, "armor": "light", "armor_class": 1, "sensor": "eo",
		# One squad. A Bradley/BMP seats 6-7 dismounts -- less lift than an
		# APC, because the turret ate the troop compartment.
		"cargo_slots": 1,
		"rcs": 14.0, "ir": 1.4, "visual": 16.0, "mount": 3.0},
	"apc": {"name": "APC", "domain": G, "category": SimTypes.Category.GROUND,
		"built_by": "light_factory", "cost": 340.0, "build_seconds": 10.0,
		"upkeep": 5.0, "speed_kmh": 75.0, "fuel": 600.0, "burn_idle": 2.0,
		"burn_cruise": 11.0, "burn_combat": 26.0, "damage_model": SimTypes.DamageModel.ARMORED,
		"hp": 70.0, "armor": "light", "armor_class": 1, "sensor": "eo",
		# An M113/BTR lifts one 11-man squad; the second slot is the attached
		# weapons team it habitually carries. Infantry units cost 1 slot each.
		"cargo_slots": 2,
		"rcs": 12.0, "ir": 1.1, "visual": 14.0, "mount": 2.6},
	"recon_vehicle": {"name": "Reconnaissance Vehicle", "domain": G,
		"category": SimTypes.Category.GROUND, "built_by": "light_factory", "cost": 380.0,
		"build_seconds": 11.0, "upkeep": 6.0, "speed_kmh": 95.0,
		"fuel": 500.0, "burn_idle": 2.0, "burn_cruise": 10.0,
		"burn_combat": 22.0, "damage_model": SimTypes.DamageModel.ARMORED, "hp": 60.0,
		"armor": "light", "armor_class": 1, "sensor": "recon",
		"rcs": 9.0, "ir": 0.9, "visual": 11.0, "mount": 4.0},
	"atgm_carrier": {"name": "ATGM Carrier", "domain": G, "category": SimTypes.Category.GROUND,
		"first_epoch": 2, "built_by": "light_factory", "cost": 480.0,
		"build_seconds": 13.0, "upkeep": 7.0, "speed_kmh": 70.0,
		"fuel": 550.0, "burn_idle": 2.0, "burn_cruise": 11.0,
		"burn_combat": 26.0, "damage_model": SimTypes.DamageModel.ARMORED, "hp": 65.0,
		"armor": "light", "armor_class": 1, "sensor": "eo",
		"rcs": 11.0, "ir": 1.0, "visual": 13.0, "mount": 3.0},

	# ══ GROUND — fires ══════════════════════════════════════════════════════
	"sph": {"name": "Self-Propelled Howitzer", "domain": G, "category": SimTypes.Category.GROUND,
		"built_by": "heavy_factory", "cost": 780.0, "build_seconds": 20.0,
		"upkeep": 11.0, "speed_kmh": 55.0, "fuel": 1100.0, "burn_idle": 3.0,
		"burn_cruise": 16.0, "burn_combat": 40.0, "damage_model": SimTypes.DamageModel.ARMORED,
		"hp": 95.0, "armor": "medium", "armor_class": 2, "sensor": "eo",
		"rcs": 20.0, "ir": 1.8, "visual": 22.0, "mount": 3.0},
	"towed_artillery": {"name": "Towed Artillery", "domain": G,
		"category": SimTypes.Category.GROUND, "built_by": "light_factory", "cost": 260.0,
		"build_seconds": 9.0, "upkeep": 3.0, "speed_kmh": 14.0,
		"fuel": 160.0, "burn_idle": 0.5, "burn_cruise": 4.0,
		"burn_combat": 8.0, "damage_model": SimTypes.DamageModel.UNARMORED, "hp": 55.0,
		"armor": "soft", "sensor": "", "rcs": 6.0, "ir": 0.3,
		# Limbered <-> deployed. A real gun emplaces in 2-6 minutes; ~10x RTS
		# time compression. Packing up is slower than dropping trails, so
		# displacing under counter-battery fire costs real exposure.
		"deploy_seconds": 10.0, "undeploy_seconds": 15.0,
		"visual": 9.0, "mount": 2.0},
	"mlrs": {"name": "MLRS", "domain": G, "category": SimTypes.Category.GROUND,
		"built_by": "heavy_factory", "cost": 820.0, "build_seconds": 21.0,
		"upkeep": 12.0, "speed_kmh": 60.0, "fuel": 900.0, "burn_idle": 3.0,
		"burn_cruise": 15.0, "burn_combat": 34.0, "damage_model": SimTypes.DamageModel.UNARMORED,
		"hp": 80.0, "armor": "soft", "sensor": "", "rcs": 16.0, "ir": 1.2,
		"visual": 20.0, "mount": 3.0},
	"mortar_carrier": {"name": "Mortar Carrier", "domain": G,
		"category": SimTypes.Category.GROUND, "built_by": "light_factory", "cost": 300.0,
		"build_seconds": 9.0, "upkeep": 4.0, "speed_kmh": 65.0,
		"fuel": 450.0, "burn_idle": 2.0, "burn_cruise": 10.0,
		"burn_combat": 22.0, "damage_model": SimTypes.DamageModel.ARMORED, "hp": 60.0,
		"armor": "light", "armor_class": 1, "sensor": "eo",
		"rcs": 10.0, "ir": 0.9, "visual": 12.0, "mount": 2.6},
	"ballistic_launcher": {"name": "Ballistic Missile Launcher", "domain": G,
		"category": SimTypes.Category.GROUND, "first_epoch": 2, "built_by": "heavy_factory",
		"cost": 1500.0, "build_seconds": 35.0, "upkeep": 20.0,
		"speed_kmh": 45.0, "fuel": 900.0, "burn_idle": 3.0,
		"burn_cruise": 16.0, "burn_combat": 30.0, "damage_model": SimTypes.DamageModel.UNARMORED,
		"hp": 90.0, "armor": "soft", "requires": ["research_facility"],
		# Erect-to-fire. A TEL's real launch sequence runs to an hour; the same
		# ~10x compression as the guns, but clearly slower than them -- the
		# erection window IS the counter-battery gameplay.
		"deploy_seconds": 25.0, "undeploy_seconds": 20.0,
		"rcs": 30.0, "ir": 1.4, "visual": 30.0, "mount": 3.4},
	"coastal_asm": {"name": "Coastal Anti-Ship Battery", "domain": G,
		"category": SimTypes.Category.GROUND, "first_epoch": 2, "built_by": "heavy_factory",
		"cost": 1100.0, "build_seconds": 26.0, "upkeep": 15.0,
		"speed_kmh": 40.0, "fuel": 700.0, "burn_idle": 2.0,
		"burn_cruise": 13.0, "burn_combat": 26.0, "damage_model": SimTypes.DamageModel.UNARMORED,
		"hp": 85.0, "armor": "soft", "sensor": "esm",
		"rcs": 24.0, "ir": 1.1, "visual": 26.0, "mount": 3.4},

	# ══ GROUND — air defence. docs/12's most consequential split: a battery
	# is a launcher PLUS a search radar PLUS an illuminator, three entities.
	"spaag": {"name": "SPAAG", "domain": G, "category": SimTypes.Category.GROUND,
		"built_by": "heavy_factory", "cost": 560.0, "build_seconds": 15.0,
		"upkeep": 8.0, "speed_kmh": 65.0, "fuel": 700.0, "burn_idle": 3.0,
		"burn_cruise": 13.0, "burn_combat": 30.0, "damage_model": SimTypes.DamageModel.ARMORED,
		"hp": 75.0, "armor": "light", "armor_class": 1, "sensor": "eo",
		"rcs": 13.0, "ir": 1.2, "visual": 15.0, "mount": 3.0},
	"shorad_sam": {"name": "SHORAD SAM", "domain": G, "category": SimTypes.Category.GROUND,
		"first_epoch": 3, "built_by": "heavy_factory", "cost": 700.0,
		"build_seconds": 18.0, "upkeep": 10.0, "speed_kmh": 65.0,
		"fuel": 700.0, "burn_idle": 3.0, "burn_cruise": 13.0,
		"burn_combat": 30.0, "damage_model": SimTypes.DamageModel.ARMORED, "hp": 75.0,
		"armor": "light", "armor_class": 1, "sensor": "eo",
		"rcs": 13.0, "ir": 1.2, "visual": 15.0, "mount": 3.2},
	"medium_sam_launcher": {"name": "Medium SAM Launcher", "domain": G,
		"category": SimTypes.Category.GROUND, "first_epoch": 2, "built_by": "heavy_factory",
		"cost": 900.0, "build_seconds": 22.0, "upkeep": 13.0,
		"speed_kmh": 55.0, "fuel": 800.0, "burn_idle": 3.0,
		"burn_cruise": 14.0, "burn_combat": 28.0, "damage_model": SimTypes.DamageModel.UNARMORED,
		"hp": 80.0, "armor": "soft", "sensor": "",
		"rcs": 22.0, "ir": 1.0, "visual": 24.0, "mount": 3.4},
	"long_sam_launcher": {"name": "Long-Range SAM Launcher", "domain": G,
		"category": SimTypes.Category.GROUND, "first_epoch": 3, "built_by": "heavy_factory",
		"cost": 1300.0, "build_seconds": 30.0, "upkeep": 18.0,
		"speed_kmh": 50.0, "fuel": 900.0, "burn_idle": 3.0,
		"burn_cruise": 15.0, "burn_combat": 28.0, "damage_model": SimTypes.DamageModel.UNARMORED,
		"hp": 90.0, "armor": "soft", "sensor": "",
		"rcs": 30.0, "ir": 1.0, "visual": 30.0, "mount": 3.6},
	"search_radar": {"name": "Search Radar Vehicle", "domain": G,
		"category": SimTypes.Category.GROUND, "built_by": "light_factory", "cost": 700.0,
		"build_seconds": 20.0, "upkeep": 12.0, "speed_kmh": 55.0,
		"fuel": 700.0, "burn_idle": 4.0, "burn_cruise": 13.0,
		"burn_combat": 20.0, "damage_model": SimTypes.DamageModel.UNARMORED, "hp": 60.0,
		"armor": "soft", "sensor": "search", "mount": 12.0,
		"rcs": 20.0, "ir": 0.9, "visual": 22.0},
	"illuminator": {"name": "Illuminator / Fire-Control Radar", "domain": G,
		"category": SimTypes.Category.GROUND, "first_epoch": 2, "built_by": "light_factory",
		"cost": 850.0, "build_seconds": 22.0, "upkeep": 14.0,
		"speed_kmh": 55.0, "fuel": 700.0, "burn_idle": 4.0,
		"burn_cruise": 13.0, "burn_combat": 20.0, "damage_model": SimTypes.DamageModel.UNARMORED,
		"hp": 60.0, "armor": "soft", "sensor": "illuminator", "mount": 9.0,
		"rcs": 18.0, "ir": 0.9, "visual": 20.0},

	# ══ GROUND — support ════════════════════════════════════════════════════
	"counter_battery_radar": {"name": "Counter-Battery Radar", "domain": G,
		"category": SimTypes.Category.GROUND, "first_epoch": 2, "built_by": "light_factory",
		"cost": 800.0, "build_seconds": 22.0, "upkeep": 13.0,
		"speed_kmh": 55.0, "fuel": 700.0, "burn_idle": 4.0,
		"burn_cruise": 13.0, "burn_combat": 20.0, "damage_model": SimTypes.DamageModel.UNARMORED,
		"hp": 60.0, "armor": "soft", "sensor": "counter_battery", "mount": 8.0,
		"rcs": 16.0, "ir": 0.9, "visual": 18.0},
	"ground_ew": {"name": "Ground EW / Jammer", "domain": G,
		"category": SimTypes.Category.GROUND, "first_epoch": 2, "built_by": "light_factory",
		"cost": 1000.0, "build_seconds": 25.0, "upkeep": 16.0,
		"speed_kmh": 55.0, "fuel": 700.0, "burn_idle": 5.0,
		"burn_cruise": 14.0, "burn_combat": 22.0, "damage_model": SimTypes.DamageModel.UNARMORED,
		"hp": 60.0, "armor": "soft", "sensor": "esm", "mount": 10.0,
		"rcs": 20.0, "ir": 1.0, "visual": 22.0},
	"command_vehicle": {"name": "Command Vehicle", "domain": G,
		"category": SimTypes.Category.GROUND, "first_epoch": 4, "built_by": "light_factory",
		"cost": 1100.0, "build_seconds": 26.0, "upkeep": 16.0,
		"speed_kmh": 60.0, "fuel": 700.0, "burn_idle": 4.0,
		"burn_cruise": 13.0, "burn_combat": 24.0, "damage_model": SimTypes.DamageModel.ARMORED,
		"hp": 70.0, "armor": "light", "armor_class": 1, "sensor": "esm",
		"rcs": 14.0, "ir": 1.1, "visual": 16.0, "mount": 5.0},
	# docs/12: "Often better to kill than the tanks it feeds." Most of the tank
	# it carries is cargo, which is why its own burn rate is tiny beside it.
	"fuel_truck": {"name": "Fuel Truck", "domain": G, "category": SimTypes.Category.GROUND,
		"built_by": "light_factory", "cost": 250.0, "build_seconds": 8.0,
		"upkeep": 3.0, "speed_kmh": 70.0, "fuel": 3200.0, "burn_idle": 1.0,
		"burn_cruise": 6.0, "burn_combat": 12.0, "damage_model": SimTypes.DamageModel.UNARMORED,
		"hp": 45.0, "armor": "soft", "supply_radius": 110.0,
		"supply_rate": 260.0, "rcs": 9.0, "ir": 0.8, "visual": 14.0,
		"mount": 3.0},
	"ammo_truck": {"name": "Ammunition Truck", "domain": G,
		"category": SimTypes.Category.GROUND, "built_by": "light_factory", "cost": 240.0,
		"build_seconds": 8.0, "upkeep": 3.0, "speed_kmh": 70.0,
		"fuel": 400.0, "burn_idle": 1.0, "burn_cruise": 6.0,
		"burn_combat": 12.0, "damage_model": SimTypes.DamageModel.UNARMORED, "hp": 45.0,
		"armor": "soft", "rcs": 9.0, "ir": 0.8, "visual": 14.0, "mount": 3.0},
	"engineer_vehicle": {"name": "Engineer Vehicle", "domain": G,
		"category": SimTypes.Category.GROUND, "built_by": "light_factory", "cost": 400.0,
		"build_seconds": 12.0, "upkeep": 5.0, "speed_kmh": 55.0,
		"fuel": 700.0, "burn_idle": 2.0, "burn_cruise": 12.0,
		"burn_combat": 24.0, "damage_model": SimTypes.DamageModel.ARMORED, "hp": 70.0,
		"armor": "light", "armor_class": 1, "rcs": 12.0, "ir": 1.0,
		"visual": 16.0, "mount": 3.0},
	"repair_vehicle": {"name": "Repair Vehicle", "domain": G,
		"category": SimTypes.Category.GROUND, "built_by": "light_factory", "cost": 450.0,
		"build_seconds": 13.0, "upkeep": 6.0, "speed_kmh": 55.0,
		"fuel": 700.0, "burn_idle": 2.0, "burn_cruise": 12.0,
		"burn_combat": 24.0, "damage_model": SimTypes.DamageModel.ARMORED, "hp": 70.0,
		"armor": "light", "armor_class": 1, "rcs": 12.0, "ir": 1.0,
		"visual": 16.0, "mount": 3.0},

	# ══ INFANTRY — docs/12, 7 roles ═════════════════════════════════════════
	"rifle_squad": {"name": "Rifle Squad", "domain": I, "category": SimTypes.Category.GROUND,
		"built_by": "barracks", "cost": 120.0, "build_seconds": 6.0,
		"upkeep": 1.5, "speed_kmh": 18.0, "accel_ms2": 2.5,
		"turn_rate_rads": 2.0, "damage_model": SimTypes.DamageModel.UNARMORED, "hp": 55.0,
		"armor": "none", "sensor": "eo", "rcs": 0.6, "ir": 0.3,
		"visual": 3.0, "mount": 1.8},
	"at_team": {"name": "Anti-Tank Team", "domain": I, "category": SimTypes.Category.GROUND,
		"built_by": "barracks", "cost": 160.0, "build_seconds": 7.0,
		"upkeep": 2.0, "speed_kmh": 16.0, "accel_ms2": 2.5,
		"turn_rate_rads": 2.0, "damage_model": SimTypes.DamageModel.UNARMORED, "hp": 50.0,
		"armor": "none", "sensor": "eo", "rcs": 0.6, "ir": 0.3,
		"visual": 3.0, "mount": 1.8},
	"manpads_team": {"name": "MANPADS Team", "domain": I, "category": SimTypes.Category.GROUND,
		"first_epoch": 3, "built_by": "barracks", "cost": 180.0,
		"build_seconds": 7.0, "upkeep": 2.0, "speed_kmh": 16.0,
		"accel_ms2": 2.5, "turn_rate_rads": 2.0, "damage_model": SimTypes.DamageModel.UNARMORED,
		"hp": 50.0, "armor": "none", "sensor": "eo", "rcs": 0.5, "ir": 0.3,
		"visual": 3.0, "mount": 1.8},
	"recon_team": {"name": "Recon / Forward Observer", "domain": I,
		"category": SimTypes.Category.GROUND, "built_by": "barracks", "cost": 140.0,
		"build_seconds": 7.0, "upkeep": 2.0, "speed_kmh": 17.0,
		"accel_ms2": 2.5, "turn_rate_rads": 2.0, "damage_model": SimTypes.DamageModel.UNARMORED,
		"hp": 45.0, "armor": "none", "sensor": "recon", "rcs": 0.4,
		"ir": 0.25, "visual": 2.5, "mount": 2.0},
	"engineer_squad": {"name": "Engineer / Sapper", "domain": I,
		"category": SimTypes.Category.GROUND, "built_by": "barracks", "cost": 150.0,
		"build_seconds": 7.0, "upkeep": 2.0, "speed_kmh": 16.0,
		"accel_ms2": 2.5, "turn_rate_rads": 2.0, "damage_model": SimTypes.DamageModel.UNARMORED,
		"hp": 50.0, "armor": "none", "sensor": "eo", "rcs": 0.6, "ir": 0.3,
		"visual": 3.0, "mount": 1.8},
	"special_forces": {"name": "Special Forces", "domain": I,
		"category": SimTypes.Category.GROUND, "built_by": "barracks", "cost": 320.0,
		"build_seconds": 12.0, "upkeep": 4.0, "speed_kmh": 19.0,
		"accel_ms2": 2.5, "turn_rate_rads": 2.0, "damage_model": SimTypes.DamageModel.UNARMORED,
		"hp": 60.0, "armor": "none", "sensor": "recon", "rcs": 0.3,
		"ir": 0.2, "visual": 2.0, "mount": 1.8},
	"mortar_team": {"name": "Mortar Team", "domain": I, "category": SimTypes.Category.GROUND,
		"built_by": "barracks", "cost": 170.0, "build_seconds": 8.0,
		"upkeep": 2.0, "speed_kmh": 14.0, "accel_ms2": 2.5,
		"turn_rate_rads": 2.0, "damage_model": SimTypes.DamageModel.UNARMORED, "hp": 50.0,
		"armor": "none", "sensor": "eo", "rcs": 0.6, "ir": 0.3,
		"visual": 3.0, "mount": 1.8},

	# ══ AIR — combat ════════════════════════════════════════════════════════
	"interceptor": {"name": "Interceptor", "domain": A, "category": SimTypes.Category.AIR,
		"built_by": "airbase", "cost": 1100.0, "build_seconds": 26.0,
		"upkeep": 22.0, "speed_kmh": 1800.0, "accel_ms2": 9.0,
		"turn_rate_rads": 0.30, "fuel": 5200.0, "burn_idle": 20.0,
		"burn_cruise": 140.0, "burn_combat": 900.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 90.0, "armor": "none",
		"sensor": "fighter_radar", "rcs": 8.0, "ir": 6.0, "visual": 30.0,
		"mount": 0.0},
	"air_superiority": {"name": "Air Superiority Fighter", "domain": A,
		"category": SimTypes.Category.AIR, "first_epoch": 2, "built_by": "airbase",
		"cost": 1600.0, "build_seconds": 34.0, "upkeep": 30.0,
		"speed_kmh": 2100.0, "accel_ms2": 10.0, "turn_rate_rads": 0.32,
		"fuel": 7500.0, "burn_idle": 22.0, "burn_cruise": 160.0,
		"burn_combat": 1050.0, "damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 100.0,
		"armor": "none", "sensor": "fighter_radar", "rcs": 6.0, "ir": 7.0,
		"visual": 34.0, "mount": 0.0},
	"multirole": {"name": "Multirole Fighter", "domain": A, "category": SimTypes.Category.AIR,
		"first_epoch": 4, "built_by": "airbase", "cost": 1500.0,
		"build_seconds": 32.0, "upkeep": 28.0, "speed_kmh": 1900.0,
		"accel_ms2": 9.0, "turn_rate_rads": 0.30, "fuel": 7000.0,
		"burn_idle": 22.0, "burn_cruise": 150.0, "burn_combat": 980.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 95.0, "armor": "none",
		"sensor": "fighter_radar", "rcs": 7.0, "ir": 6.0, "visual": 32.0,
		"mount": 0.0},
	"strike_aircraft": {"name": "Strike Aircraft", "domain": A,
		"category": SimTypes.Category.AIR, "built_by": "airbase", "cost": 1300.0,
		"build_seconds": 30.0, "upkeep": 25.0, "speed_kmh": 1400.0,
		"accel_ms2": 7.0, "turn_rate_rads": 0.22, "fuel": 8000.0,
		"burn_idle": 20.0, "burn_cruise": 150.0, "burn_combat": 820.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 110.0, "armor": "none",
		"sensor": "fighter_radar", "rcs": 14.0, "ir": 5.0, "visual": 36.0,
		"mount": 0.0},
	"cas": {"name": "Close Air Support", "domain": A, "category": SimTypes.Category.AIR,
		"built_by": "airbase", "cost": 900.0, "build_seconds": 24.0,
		"upkeep": 18.0, "speed_kmh": 700.0, "accel_ms2": 5.0,
		"turn_rate_rads": 0.26, "fuel": 4500.0, "burn_idle": 14.0,
		"burn_cruise": 90.0, "burn_combat": 340.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 170.0, "armor": "none",
		"sensor": "eo", "rcs": 12.0, "ir": 4.0, "visual": 30.0, "mount": 0.0},
	"bomber": {"name": "Bomber", "domain": A, "category": SimTypes.Category.AIR,
		"built_by": "airbase", "cost": 2600.0, "build_seconds": 55.0,
		"upkeep": 45.0, "speed_kmh": 900.0, "accel_ms2": 3.0,
		"turn_rate_rads": 0.10, "fuel": 40000.0, "burn_idle": 40.0,
		"burn_cruise": 420.0, "burn_combat": 900.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 260.0, "armor": "none",
		"sensor": "esm", "rcs": 100.0, "ir": 9.0, "visual": 120.0,
		"mount": 0.0},
	"sead": {"name": "SEAD Aircraft", "domain": A, "category": SimTypes.Category.AIR,
		"first_epoch": 2, "built_by": "airbase", "cost": 1700.0,
		"build_seconds": 36.0, "upkeep": 30.0, "speed_kmh": 1600.0,
		"accel_ms2": 8.0, "turn_rate_rads": 0.28, "fuel": 7000.0,
		"burn_idle": 20.0, "burn_cruise": 150.0, "burn_combat": 880.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 95.0, "armor": "none",
		"sensor": "esm", "rcs": 10.0, "ir": 5.0, "visual": 32.0, "mount": 0.0},
	"stealth_strike": {"name": "Stealth Strike Aircraft", "domain": A,
		"category": SimTypes.Category.AIR, "first_epoch": 4, "built_by": "airbase",
		"cost": 3000.0, "build_seconds": 60.0, "upkeep": 50.0,
		"speed_kmh": 1600.0, "accel_ms2": 7.0, "turn_rate_rads": 0.24,
		"fuel": 9000.0, "burn_idle": 22.0, "burn_cruise": 170.0,
		"burn_combat": 900.0, "damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 100.0,
		"armor": "none", "sensor": "esm", "rcs": 0.005, "ir": 3.0,
		"visual": 34.0, "mount": 0.0, "requires": ["research_facility"]},

	# ══ AIR — enablers. docs/12: these outnumber the glamorous ones, and
	# they are the most valuable targets on the map.
	"aewc": {"name": "AEW&C Aircraft", "domain": A, "category": SimTypes.Category.AIR,
		"first_epoch": 3, "built_by": "airbase", "cost": 3600.0,
		"build_seconds": 70.0, "upkeep": 60.0, "speed_kmh": 800.0,
		"accel_ms2": 2.5, "turn_rate_rads": 0.09, "fuel": 60000.0,
		"burn_idle": 40.0, "burn_cruise": 400.0, "burn_combat": 700.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 160.0, "armor": "none",
		"sensor": "aew", "rcs": 90.0, "ir": 7.0, "visual": 110.0,
		"mount": 0.0, "requires": ["research_facility"]},
	"aew_helicopter": {"name": "AEW Helicopter", "domain": A, "category": SimTypes.Category.AIR,
		"first_epoch": 3, "built_by": "helipad", "cost": 1800.0,
		"build_seconds": 40.0, "upkeep": 30.0, "speed_kmh": 250.0,
		"accel_ms2": 3.0, "turn_rate_rads": 0.55, "fuel": 2500.0,
		"burn_idle": 18.0, "burn_cruise": 110.0, "burn_combat": 180.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 90.0, "armor": "none",
		"sensor": "aew_heli", "rcs": 20.0, "ir": 4.0, "visual": 40.0,
		"mount": 0.0},
	"electronic_attack": {"name": "Electronic Attack Aircraft", "domain": A,
		"category": SimTypes.Category.AIR, "first_epoch": 2, "built_by": "airbase",
		"cost": 2200.0, "build_seconds": 46.0, "upkeep": 38.0,
		"speed_kmh": 1400.0, "accel_ms2": 6.0, "turn_rate_rads": 0.22,
		"fuel": 9000.0, "burn_idle": 22.0, "burn_cruise": 180.0,
		"burn_combat": 700.0, "damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 110.0,
		"armor": "none", "sensor": "esm", "rcs": 18.0, "ir": 5.0,
		"visual": 40.0, "mount": 0.0},
	"tanker": {"name": "Aerial Tanker", "domain": A, "category": SimTypes.Category.AIR,
		"first_epoch": 2, "built_by": "airbase", "cost": 2400.0,
		"build_seconds": 50.0, "upkeep": 40.0, "speed_kmh": 850.0,
		"accel_ms2": 2.5, "turn_rate_rads": 0.09, "fuel": 90000.0,
		"burn_idle": 40.0, "burn_cruise": 380.0, "burn_combat": 600.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 180.0, "armor": "none",
		"supply_radius": 4000.0, "supply_rate": 1800.0,
		"rcs": 110.0, "ir": 8.0, "visual": 130.0, "mount": 0.0},
	"isr_aircraft": {"name": "ISR Aircraft", "domain": A, "category": SimTypes.Category.AIR,
		"built_by": "airbase", "cost": 1500.0, "build_seconds": 34.0,
		"upkeep": 26.0, "speed_kmh": 800.0, "accel_ms2": 2.5,
		"turn_rate_rads": 0.10, "fuel": 30000.0, "burn_idle": 30.0,
		"burn_cruise": 300.0, "burn_combat": 500.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 130.0, "armor": "none",
		"sensor": "esm", "rcs": 60.0, "ir": 6.0, "visual": 90.0,
		"mount": 0.0},
	"maritime_patrol": {"name": "Maritime Patrol / ASW Aircraft", "domain": A,
		"category": SimTypes.Category.AIR, "built_by": "airbase", "cost": 1900.0,
		"build_seconds": 40.0, "upkeep": 32.0, "speed_kmh": 700.0,
		"accel_ms2": 2.5, "turn_rate_rads": 0.11, "fuel": 30000.0,
		"burn_idle": 30.0, "burn_cruise": 300.0, "burn_combat": 520.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 140.0, "armor": "none",
		"sensor": "mpa", "rcs": 70.0, "ir": 6.0, "visual": 95.0,
		"mount": 0.0},
	"transport_aircraft": {"name": "Transport Aircraft", "domain": A,
		"category": SimTypes.Category.AIR, "built_by": "airbase", "cost": 1200.0,
		"build_seconds": 30.0, "upkeep": 20.0, "speed_kmh": 750.0,
		"accel_ms2": 2.5, "turn_rate_rads": 0.10, "fuel": 30000.0,
		"burn_idle": 30.0, "burn_cruise": 320.0, "burn_combat": 560.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 160.0, "armor": "none",
		# A C-130 lifts a company-minus of infantry. 8 is SimEntities.MAX_CARGO,
		# the spine's per-unit stride -- the honest cap, not a realism claim.
		"cargo_slots": 8,
		"rcs": 90.0, "ir": 7.0, "visual": 110.0, "mount": 0.0},

	# ══ AIR — rotary and unmanned ═══════════════════════════════════════════
	"attack_helicopter": {"name": "Attack Helicopter", "domain": A,
		"category": SimTypes.Category.AIR, "first_epoch": 3, "built_by": "helipad",
		"cost": 1400.0, "build_seconds": 30.0, "upkeep": 24.0,
		"speed_kmh": 280.0, "accel_ms2": 4.0, "turn_rate_rads": 0.7,
		"fuel": 1800.0, "burn_idle": 16.0, "burn_cruise": 90.0,
		"burn_combat": 150.0, "damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 120.0,
		"armor": "none", "sensor": "eo", "rcs": 9.0, "ir": 3.5,
		"visual": 26.0, "mount": 0.0},
	"transport_helicopter": {"name": "Transport Helicopter", "domain": A,
		"category": SimTypes.Category.AIR, "first_epoch": 2, "built_by": "helipad",
		"cost": 800.0, "build_seconds": 22.0, "upkeep": 14.0,
		"speed_kmh": 260.0, "accel_ms2": 3.5, "turn_rate_rads": 0.6,
		"fuel": 2000.0, "burn_idle": 16.0, "burn_cruise": 95.0,
		"burn_combat": 150.0, "damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 110.0,
		# A medium-lift cabin (Mi-8 / CH-46 class): a platoon-minus, three
		# squads. Infantry only -- sling-loading vehicles is not modelled.
		"cargo_slots": 3,
		"armor": "none", "rcs": 14.0, "ir": 3.5, "visual": 32.0,
		"mount": 0.0},
	"asw_helicopter": {"name": "ASW Helicopter", "domain": A, "category": SimTypes.Category.AIR,
		"first_epoch": 2, "built_by": "helipad", "cost": 1000.0,
		"build_seconds": 26.0, "upkeep": 18.0, "speed_kmh": 250.0,
		"accel_ms2": 3.5, "turn_rate_rads": 0.6, "fuel": 2000.0,
		"burn_idle": 16.0, "burn_cruise": 95.0, "burn_combat": 150.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 100.0, "armor": "none",
		"sensor": "dipping", "rcs": 12.0, "ir": 3.2, "visual": 28.0,
		"mount": 0.0},
	"recon_uav": {"name": "Reconnaissance UAV", "domain": A, "category": SimTypes.Category.AIR,
		"first_epoch": 5, "built_by": "airbase", "cost": 500.0,
		"build_seconds": 16.0, "upkeep": 6.0, "speed_kmh": 200.0,
		"accel_ms2": 2.0, "turn_rate_rads": 0.20, "fuel": 900.0,
		"burn_idle": 3.0, "burn_cruise": 14.0, "burn_combat": 22.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 35.0, "armor": "none",
		"sensor": "recon", "rcs": 0.4, "ir": 0.5, "visual": 8.0,
		"mount": 0.0},
	"armed_uav": {"name": "Armed UAV", "domain": A, "category": SimTypes.Category.AIR,
		"first_epoch": 6, "built_by": "airbase", "cost": 900.0,
		"build_seconds": 22.0, "upkeep": 10.0, "speed_kmh": 240.0,
		"accel_ms2": 2.0, "turn_rate_rads": 0.22, "fuel": 1200.0,
		"burn_idle": 4.0, "burn_cruise": 18.0, "burn_combat": 30.0,
		"damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 40.0, "armor": "none",
		"sensor": "recon", "rcs": 0.5, "ir": 0.6, "visual": 9.0,
		"mount": 0.0},
	"loitering_munition": {"name": "Loitering Munition", "domain": A,
		"category": SimTypes.Category.AIR, "first_epoch": 7, "built_by": "light_factory",
		"cost": 180.0, "build_seconds": 6.0, "upkeep": 1.0,
		"speed_kmh": 160.0, "accel_ms2": 2.0, "turn_rate_rads": 0.30,
		"fuel": 60.0, "burn_idle": 1.0, "burn_cruise": 2.0,
		"burn_combat": 3.0, "damage_model": SimTypes.DamageModel.AIRFRAME, "hp": 18.0,
		"armor": "none", "sensor": "eo", "rcs": 0.05, "ir": 0.3,
		"visual": 1.5, "mount": 0.0},

	# ══ NAVAL — surface combatants ══════════════════════════════════════════
	"air_defence_destroyer": {"name": "Air-Defence Destroyer", "domain": N,
		"category": SimTypes.Category.SURFACE, "first_epoch": 4, "built_by": "naval_yard",
		"cost": 4200.0, "build_seconds": 90.0, "upkeep": 70.0,
		"speed_kmh": 55.0, "accel_ms2": 0.3, "turn_rate_rads": 0.05,
		"fuel": 120000.0, "burn_idle": 60.0, "burn_cruise": 900.0,
		"burn_combat": 2600.0, "damage_model": SimTypes.DamageModel.HULL, "hp": 900.0,
		"armor": "soft", "sensor": "naval", "rcs": 3000.0, "ir": 12.0,
		"acoustic": 130.0, "visual": 2400.0, "mount": 30.0},
	"asw_frigate": {"name": "ASW Frigate", "domain": N, "category": SimTypes.Category.SURFACE,
		"built_by": "naval_yard", "cost": 2600.0, "build_seconds": 65.0,
		"upkeep": 48.0, "speed_kmh": 52.0, "accel_ms2": 0.3,
		"turn_rate_rads": 0.05, "fuel": 80000.0, "burn_idle": 45.0,
		"burn_cruise": 700.0, "burn_combat": 1900.0,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 620.0, "armor": "soft",
		"sensor": "asw_ship", "rcs": 2000.0, "ir": 10.0,
		"acoustic": 122.0, "visual": 1700.0, "mount": 24.0},
	"cruiser": {"name": "Cruiser", "domain": N, "category": SimTypes.Category.SURFACE,
		"built_by": "naval_yard", "cost": 3800.0, "build_seconds": 85.0,
		"upkeep": 65.0, "speed_kmh": 55.0, "accel_ms2": 0.25,
		"turn_rate_rads": 0.04, "fuel": 140000.0, "burn_idle": 70.0,
		"burn_cruise": 1000.0, "burn_combat": 2800.0,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 850.0, "armor": "soft",
		"sensor": "naval", "rcs": 4000.0, "ir": 13.0,
		"acoustic": 132.0, "visual": 2800.0, "mount": 32.0},
	"corvette": {"name": "Corvette / Fast Attack Craft", "domain": N,
		"category": SimTypes.Category.SURFACE, "built_by": "naval_yard", "cost": 1100.0,
		"build_seconds": 32.0, "upkeep": 20.0, "speed_kmh": 70.0,
		"accel_ms2": 0.5, "turn_rate_rads": 0.10, "fuel": 20000.0,
		"burn_idle": 20.0, "burn_cruise": 320.0, "burn_combat": 900.0,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 300.0, "armor": "soft",
		"sensor": "asw_ship", "rcs": 600.0, "ir": 6.0,
		"acoustic": 118.0, "visual": 600.0, "mount": 14.0},
	"missile_boat": {"name": "Missile Boat", "domain": N, "category": SimTypes.Category.SURFACE,
		"first_epoch": 2, "built_by": "naval_yard", "cost": 800.0,
		"build_seconds": 24.0, "upkeep": 14.0, "speed_kmh": 80.0,
		"accel_ms2": 0.6, "turn_rate_rads": 0.14, "fuel": 9000.0,
		"burn_idle": 12.0, "burn_cruise": 220.0, "burn_combat": 700.0,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 200.0, "armor": "soft",
		"sensor": "esm", "rcs": 300.0, "ir": 5.0, "acoustic": 116.0,
		"visual": 340.0, "mount": 10.0},
	"patrol_vessel": {"name": "Patrol Vessel", "domain": N,
		"category": SimTypes.Category.SURFACE, "built_by": "naval_yard", "cost": 600.0,
		"build_seconds": 20.0, "upkeep": 10.0, "speed_kmh": 55.0,
		"accel_ms2": 0.4, "turn_rate_rads": 0.10, "fuel": 12000.0,
		"burn_idle": 10.0, "burn_cruise": 180.0, "burn_combat": 480.0,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 220.0, "armor": "soft",
		"sensor": "asw_ship", "rcs": 260.0, "ir": 4.0, "acoustic": 112.0,
		"visual": 300.0, "mount": 10.0},

	# ══ NAVAL — submarines ══════════════════════════════════════════════════
	"ssk": {"name": "Diesel-Electric Submarine", "domain": N,
		"category": SimTypes.Category.SUBSURFACE, "built_by": "naval_yard", "cost": 2200.0,
		"build_seconds": 60.0, "upkeep": 40.0, "speed_kmh": 37.0,
		"accel_ms2": 0.2, "turn_rate_rads": 0.05, "fuel": 40000.0,
		"burn_idle": 8.0, "burn_cruise": 200.0, "burn_combat": 700.0,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 380.0, "armor": "soft",
		"sensor": "submarine", "rcs": 0.5, "ir": 0.2, "acoustic": 95.0,
		"visual": 40.0, "magnetic": 1.0, "mount": 2.0},
	"ssn": {"name": "Nuclear Attack Submarine", "domain": N,
		"category": SimTypes.Category.SUBSURFACE, "first_epoch": 2, "built_by": "naval_yard",
		"cost": 4800.0, "build_seconds": 100.0, "upkeep": 85.0,
		"speed_kmh": 60.0, "accel_ms2": 0.25, "turn_rate_rads": 0.05,
		"nuclear": true, "nuclear_from_epoch": 2,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 480.0, "armor": "soft",
		"sensor": "submarine", "rcs": 0.6, "ir": 0.2,
		# docs/12: in epoch 2 the nuclear boat is NOISIER than the diesel.
		"acoustic": 108.0, "visual": 50.0, "magnetic": 1.6, "mount": 2.0},
	"aip_sub": {"name": "AIP Submarine", "domain": N, "category": SimTypes.Category.SUBSURFACE,
		"first_epoch": 7, "built_by": "naval_yard", "cost": 3600.0,
		"build_seconds": 80.0, "upkeep": 60.0, "speed_kmh": 38.0,
		"accel_ms2": 0.2, "turn_rate_rads": 0.05, "fuel": 60000.0,
		"burn_idle": 5.0, "burn_cruise": 150.0, "burn_combat": 600.0,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 420.0, "armor": "soft",
		"sensor": "submarine", "rcs": 0.4, "ir": 0.15, "acoustic": 86.0,
		"visual": 38.0, "magnetic": 0.9, "mount": 2.0},
	"midget_sub": {"name": "Midget Submarine", "domain": N,
		"category": SimTypes.Category.SUBSURFACE, "built_by": "naval_yard", "cost": 700.0,
		"build_seconds": 22.0, "upkeep": 10.0, "speed_kmh": 20.0,
		"accel_ms2": 0.2, "turn_rate_rads": 0.08, "fuel": 4000.0,
		"burn_idle": 3.0, "burn_cruise": 60.0, "burn_combat": 180.0,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 120.0, "armor": "soft",
		"sensor": "submarine", "rcs": 0.2, "ir": 0.1, "acoustic": 92.0,
		"visual": 12.0, "magnetic": 0.4, "mount": 1.5},
	"ssbn": {"name": "Ballistic Missile Submarine", "domain": N,
		"category": SimTypes.Category.SUBSURFACE, "first_epoch": 3, "built_by": "naval_yard",
		"cost": 6000.0, "build_seconds": 120.0, "upkeep": 100.0,
		"speed_kmh": 45.0, "accel_ms2": 0.2, "turn_rate_rads": 0.04,
		"nuclear": true, "nuclear_from_epoch": 3,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 620.0, "armor": "soft",
		"sensor": "submarine", "rcs": 0.8, "ir": 0.2, "acoustic": 100.0,
		"visual": 70.0, "magnetic": 2.2, "mount": 2.0,
		"requires": ["research_facility"]},

	# ══ NAVAL — aviation, amphibious, and the one that matters ══════════════
	"carrier": {"name": "Aircraft Carrier", "domain": N, "category": SimTypes.Category.SURFACE,
		"built_by": "naval_yard", "cost": 9000.0, "build_seconds": 160.0,
		"upkeep": 140.0, "speed_kmh": 55.0, "accel_ms2": 0.15,
		"turn_rate_rads": 0.03, "fuel": 400000.0, "burn_idle": 200.0,
		"burn_cruise": 2600.0, "burn_combat": 6000.0,
		"nuclear": true, "nuclear_from_epoch": 3,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 2000.0, "armor": "soft",
		"sensor": "naval", "rcs": 20000.0, "ir": 20.0, "acoustic": 138.0,
		"visual": 9000.0, "mount": 40.0,
		"supply_radius": 900.0, "supply_rate": 1400.0,
		"requires": ["research_facility"], "footprint": 40.0},
	"amphib": {"name": "Amphibious Assault Ship", "domain": N,
		"category": SimTypes.Category.SURFACE, "first_epoch": 2, "built_by": "naval_yard",
		"cost": 3400.0, "build_seconds": 80.0, "upkeep": 55.0,
		"speed_kmh": 42.0, "accel_ms2": 0.2, "turn_rate_rads": 0.04,
		"fuel": 160000.0, "burn_idle": 70.0, "burn_cruise": 1000.0,
		"burn_combat": 2200.0, "damage_model": SimTypes.DamageModel.HULL, "hp": 900.0,
		"armor": "soft", "sensor": "asw_ship",
		# Well deck: loaded landing craft nest aboard (the doctrine's example).
		# A real LHD lifts a battalion; 8 is SimEntities.MAX_CARGO, the spine's
		# fixed stride, so the rest of the battalion sails in a second hull.
		"cargo_slots": 8, "carries_vehicles": true,
		"rcs": 6000.0, "ir": 12.0,
		"acoustic": 130.0, "visual": 4000.0, "mount": 26.0},
	"landing_craft": {"name": "Landing Craft", "domain": N,
		"category": SimTypes.Category.SURFACE, "built_by": "naval_yard", "cost": 400.0,
		"build_seconds": 14.0, "upkeep": 6.0, "speed_kmh": 40.0,
		"accel_ms2": 0.5, "turn_rate_rads": 0.12, "fuel": 6000.0,
		"burn_idle": 6.0, "burn_cruise": 110.0, "burn_combat": 260.0,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 120.0, "armor": "soft",
		# An LCU beaches two vehicles (4 slots each) or eight squads or a mix.
		# The only small hull that takes vehicles -- that is its whole job.
		"cargo_slots": 8, "carries_vehicles": true,
		"rcs": 120.0, "ir": 3.0, "acoustic": 110.0, "visual": 160.0,
		"mount": 5.0},
	# docs/04's centrepiece: "a submarine that finds the oiler has taken the
	# fleet's RANGE."
	"oiler": {"name": "Fleet Oiler", "domain": N, "category": SimTypes.Category.SURFACE,
		"built_by": "naval_yard", "cost": 2400.0, "build_seconds": 60.0,
		"upkeep": 40.0, "speed_kmh": 40.0, "accel_ms2": 0.2,
		"turn_rate_rads": 0.04, "fuel": 400000.0, "burn_idle": 40.0,
		"burn_cruise": 500.0, "burn_combat": 1000.0,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 700.0, "armor": "soft",
		"supply_radius": 1400.0, "supply_rate": 3000.0,
		"rcs": 5000.0, "ir": 9.0, "acoustic": 128.0, "visual": 3600.0,
		"mount": 22.0},
	"mine_warfare": {"name": "Mine Warfare Vessel", "domain": N,
		"category": SimTypes.Category.SURFACE, "built_by": "naval_yard", "cost": 900.0,
		"build_seconds": 26.0, "upkeep": 14.0, "speed_kmh": 30.0,
		"accel_ms2": 0.3, "turn_rate_rads": 0.10, "fuel": 10000.0,
		"burn_idle": 8.0, "burn_cruise": 140.0, "burn_combat": 300.0,
		"damage_model": SimTypes.DamageModel.HULL, "hp": 220.0, "armor": "soft",
		"sensor": "asw_ship", "rcs": 200.0, "ir": 3.0, "acoustic": 108.0,
		"visual": 280.0, "mount": 10.0},
	}
