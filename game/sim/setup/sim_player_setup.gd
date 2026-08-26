class_name SimPlayerSetup
extends RefCounted
## Per-participant match configuration. docs/09 §4, extended.
##
## Every participant, human and AI, is configured independently. Two of the
## axes below are NOT in docs/09 and are noted as such, because they change what
## the setup screen has to express:
##
##   * per-ladder technology floor and ceiling (docs/09 has epoch only)
##   * force composition restrictions -- army only, no navy, no air force
##
## Both fit the existing spine rather than fighting it: the ladders are the ones
## docs/11 already defines, and a force restriction is a filter on the roster
## docs/12 already enumerates by domain.

# ── the eight factions, docs/08 ──────────────────────────────────────────────
enum Faction { US, UK, GERMANY, FRANCE, PLA, RUSSIA, ROC, KPA }

## What is already on the map at match start. Deliberately independent of
## start_epoch: "advanced but tiny" and "obsolete but enormous" are the two most
## interesting starting positions in the game and both must be expressible.
enum ForcePreset { NONE, SKIRMISH, GARRISON, ARMY, MASSED }

## Domains a player may build in at all. docs/12 groups the 86 roles this way.
enum Domain { GROUND = 1, AIR = 2, NAVAL = 4, INFANTRY = 8, STRUCTURES = 16 }

const ALL_DOMAINS := Domain.GROUND | Domain.AIR | Domain.NAVAL \
	| Domain.INFANTRY | Domain.STRUCTURES

## Generation ladders, docs/11. Each is independently floored and capped, so an
## opponent can be modern in one dimension and obsolete in another -- a PLA
## force with epoch-6 missiles behind an epoch-3 radar is a real and specific
## fight, and it is not expressible with an epoch setting alone.
const LADDERS := {
	"gun":      6,   ## tube generations, docs/11 §2.1
	"ammo":     6,   ## ammunition, decoupled from caliber, §2.2
	"armor":    6,   ## G-ladder, §2 / docs/03
	"radar":    6,   ## R1-R6, §3
	"aew":      5,   ## A1-A5, §4
	"aam":      7,   ## M1-M7, §5.1
	"sam":      6,   ## surface-to-air, §5.2
	"atgm":     5,   ## §5.3
	"seeker":   6,   ## S1-S6, §6
	"esm":      5,   ## P1-P5, §7
	"sonar":    6,   ## N1-N6, §7
	"quieting": 5,   ## Q1-Q5, §7
}

const EPOCH_MIN := 1
const EPOCH_MAX := 7

# ── identity ─────────────────────────────────────────────────────────────────
var name: String = "Player"
var faction: int = Faction.US
var is_human: bool = false
var team: int = 0                 ## same team = allied = shared track table

# ── epoch, docs/09 §4 ────────────────────────────────────────────────────────
## Grants TECHNOLOGY, not an army.
var start_epoch: int = 4
## The highest it may ever reach. Public: every player can see every other
## player's start and ceiling. A hidden ceiling is not tension, it is confusion.
var ceiling_epoch: int = 7
var advance_cost_mult: float = 1.0

# ── technology, per ladder (NOT in docs/09) ──────────────────────────────────
## ladder name -> generation. Empty means "whatever the epoch grants".
var tech_floor: Dictionary = {}
var tech_ceiling: Dictionary = {}

# ── force composition (NOT in docs/09) ───────────────────────────────────────
var allowed_domains: int = ALL_DOMAINS
var starting_forces: int = ForcePreset.ARMY

# ── AI only ──────────────────────────────────────────────────────────────────
var skill: int = SimSkill.Level.VETERAN
var doctrine: SimDoctrine = null
## Optional handicap, clearly labelled, 1.0 = none. docs/09 is explicit that
## this must never be the primary difficulty mechanism.
var resource_mult: float = 1.0


func _init(p: Dictionary = {}) -> void:
	doctrine = SimDoctrine.make(SimDoctrine.Profile.COMBINED_ARMS)
	for k in p.keys():
		if k in self:
			set(k, p[k])
	if doctrine == null:
		doctrine = SimDoctrine.make(default_doctrine_for(faction))


## Historical defaults, docs/09 §5. Any doctrine may still be assigned to any
## faction; these are only what the setup screen starts on.
static func default_doctrine_for(faction_id: int) -> int:
	match faction_id:
		Faction.RUSSIA: return SimDoctrine.Profile.DENIAL
		Faction.KPA: return SimDoctrine.Profile.ATTRITION
		Faction.ROC: return SimDoctrine.Profile.FORTRESS
		Faction.US, Faction.PLA: return SimDoctrine.Profile.SENSOR_DOMINANCE
	return SimDoctrine.Profile.COMBINED_ARMS


# ── domain restrictions ──────────────────────────────────────────────────────

func allows(domain: int) -> bool:
	return (allowed_domains & domain) != 0


func restrict_to(domains: int) -> void:
	allowed_domains = domains


## "Army only" -- ground, infantry and structures, no air force, no navy.
func set_army_only() -> void:
	allowed_domains = Domain.GROUND | Domain.INFANTRY | Domain.STRUCTURES


func set_without_navy() -> void:
	allowed_domains = ALL_DOMAINS & ~Domain.NAVAL


func set_without_air_force() -> void:
	allowed_domains = ALL_DOMAINS & ~Domain.AIR


func domains_description() -> String:
	if allowed_domains == ALL_DOMAINS:
		return "combined arms"
	var parts := PackedStringArray()
	if allows(Domain.GROUND): parts.append("ground")
	if allows(Domain.INFANTRY): parts.append("infantry")
	if allows(Domain.AIR): parts.append("air")
	if allows(Domain.NAVAL): parts.append("naval")
	if allows(Domain.STRUCTURES): parts.append("structures")
	if parts.is_empty():
		return "NOTHING"
	return ", ".join(parts)


# ── technology ───────────────────────────────────────────────────────────────

## Highest generation of a ladder this player may ever field, taking both the
## epoch ceiling and any explicit per-ladder cap into account.
func max_generation(ladder: String) -> int:
	var ladder_max: int = LADDERS.get(ladder, 6)
	var from_epoch: int = _epoch_to_generation(ceiling_epoch, ladder_max)
	var explicit: int = tech_ceiling.get(ladder, ladder_max)
	return mini(mini(from_epoch, explicit), ladder_max)


## Lowest generation this player starts with.
func min_generation(ladder: String) -> int:
	var ladder_max: int = LADDERS.get(ladder, 6)
	var from_epoch: int = _epoch_to_generation(start_epoch, ladder_max)
	var explicit: int = tech_floor.get(ladder, from_epoch)
	return clampi(maxi(explicit, 1), 1, max_generation(ladder))


## Epochs run 1-7; ladders have their own lengths. docs/11 §9 relates them, and
## a proportional mapping is close enough until the per-ladder epoch table in
## that section is authored as data.
func _epoch_to_generation(epoch: int, ladder_max: int) -> int:
	var e: int = clampi(epoch, EPOCH_MIN, EPOCH_MAX)
	var g := int(round(float(e - 1) / float(EPOCH_MAX - 1) * float(ladder_max - 1))) + 1
	return clampi(g, 1, ladder_max)


func set_tech_ceiling(ladder: String, generation: int) -> void:
	tech_ceiling[ladder] = clampi(generation, 1, LADDERS.get(ladder, 6))


func set_tech_floor(ladder: String, generation: int) -> void:
	tech_floor[ladder] = clampi(generation, 1, LADDERS.get(ladder, 6))


# ── validation ───────────────────────────────────────────────────────────────

## Returns a list of problems. Empty means the setup is playable.
func validate() -> PackedStringArray:
	var problems := PackedStringArray()

	if start_epoch < EPOCH_MIN or start_epoch > EPOCH_MAX:
		problems.append("%s: start epoch %d outside 1-7" % [name, start_epoch])
	if ceiling_epoch < EPOCH_MIN or ceiling_epoch > EPOCH_MAX:
		problems.append("%s: ceiling epoch %d outside 1-7" % [name, ceiling_epoch])
	if ceiling_epoch < start_epoch:
		problems.append("%s: ceiling epoch %d is below start epoch %d"
			% [name, ceiling_epoch, start_epoch])

	if allowed_domains == 0:
		problems.append("%s: no domains allowed -- nothing can be built" % name)
	# Naval-capable without ground or air is legal but worth flagging on a land
	# map; the scenario layer decides, not this class.

	for ladder in tech_ceiling.keys():
		if not LADDERS.has(ladder):
			problems.append("%s: unknown ladder '%s'" % [name, ladder])
			continue
		var cap: int = tech_ceiling[ladder]
		if cap < 1 or cap > LADDERS[ladder]:
			problems.append("%s: %s ceiling %d outside 1-%d"
				% [name, ladder, cap, LADDERS[ladder]])
	for ladder in tech_floor.keys():
		if not LADDERS.has(ladder):
			problems.append("%s: unknown ladder '%s'" % [name, ladder])
			continue
		var floor_: int = tech_floor[ladder]
		var cap: int = tech_ceiling.get(ladder, LADDERS[ladder])
		if floor_ > cap:
			problems.append("%s: %s floor %d exceeds its ceiling %d"
				% [name, ladder, floor_, cap])

	if skill < 0 or skill >= SimSkill.LEVEL_COUNT:
		problems.append("%s: skill level %d outside the ladder" % [name, skill])
	if resource_mult <= 0.0:
		problems.append("%s: resource multiplier must be positive" % name)

	# An AI that cannot build air units should not be assigned a doctrine whose
	# whole identity is airborne sensing -- it would read as a broken opponent.
	if doctrine != null and not is_human:
		if doctrine.profile == SimDoctrine.Profile.SENSOR_DOMINANCE \
				and not allows(Domain.AIR):
			problems.append("%s: Sensor Dominance without an air force -- it "
				% name + "cannot fly the AEW the doctrine is built around")

	return problems


func describe() -> String:
	var lines := PackedStringArray()
	var kind := "human" if is_human else SimSkill.name_of(skill)
	lines.append("%-14s %-8s team %d   %s" % [
		name, _faction_name(faction), team, kind])
	lines.append("    epoch %d -> %d      forces: %s      domains: %s" % [
		start_epoch, ceiling_epoch, _preset_name(starting_forces),
		domains_description()])
	if not is_human and doctrine != null:
		lines.append("    " + doctrine.describe())
	if not tech_ceiling.is_empty() or not tech_floor.is_empty():
		var caps := PackedStringArray()
		var keys: Array = LADDERS.keys()
		keys.sort()
		for l in keys:
			if tech_ceiling.has(l) or tech_floor.has(l):
				caps.append("%s %d-%d" % [l, min_generation(l), max_generation(l)])
		lines.append("    tech: " + ", ".join(caps))
	return "\n".join(lines)


static func _faction_name(f: int) -> String:
	match f:
		Faction.US: return "US"
		Faction.UK: return "UK"
		Faction.GERMANY: return "Germany"
		Faction.FRANCE: return "France"
		Faction.PLA: return "PLA"
		Faction.RUSSIA: return "Russia"
		Faction.ROC: return "ROC"
		Faction.KPA: return "KPA"
	return "?"


static func _preset_name(p: int) -> String:
	match p:
		ForcePreset.NONE: return "none"
		ForcePreset.SKIRMISH: return "skirmish"
		ForcePreset.GARRISON: return "garrison"
		ForcePreset.ARMY: return "army"
		ForcePreset.MASSED: return "massed"
	return "?"
