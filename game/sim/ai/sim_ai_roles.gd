class_name SimAiRoles
extends RefCounted
## What the AI believes its OWN units are for, and what they carry.
##
## Every input to this file comes from the docs/09 §1 whitelist -- a unit's own
## name, its category, whether it is a structure, and how fast it can go. That
## is information a commander has about his own army by definition. Nothing
## here is ever asked about an enemy: an enemy is a track, and a track has no
## name, no loadout and no owner.
##
## WHY THE AI NEEDS A LOADOUT TABLE AT ALL. docs/09 §3 requires the tactical
## layer to run "the same weapon gate the player does -- not an approximation of
## the player's rules; it is those rules". SimWeaponGate.can_launch() takes a
## SimWeaponDef, and the entity store does not yet carry a per-unit weapon list
## (the weapon cycle at sim_world.gd slot 8c is still a call site). So the AI
## needs some SimWeaponDef to hand the gate. This table is that, and it is
## deliberately overridable: SimAiDirector.set_loadout() replaces any row, so
## when units gain real weapon lists the director reads those instead and the
## defaults below become dead weight rather than a second source of truth.

enum Unit {
	ARMOR,       ## the line: tanks, IFVs, anything that closes
	INFANTRY,
	SCOUT,       ## fast, cheap eyes -- what gets sent at a TQ1 cue
	AIR,
	AEW,         ## airborne sensor. docs/09 §5: the thing worth killing
	SAM,
	SENSOR,      ## ground radar, ESM mast, jammer
	SUPPLY,      ## the interdiction target set (docs/04, docs/09 §5)
	HARVESTER,   ## unarmed, drives itself, and must never be given an order
	NAVAL,
	SUBMARINE,
	PRODUCTION,  ## a structure that builds things
	BASE,        ## every other structure
	UNKNOWN,
}

const NAMES := {
	Unit.ARMOR: "armor", Unit.INFANTRY: "infantry", Unit.SCOUT: "scout",
	Unit.AIR: "air", Unit.AEW: "aew", Unit.SAM: "sam", Unit.SENSOR: "sensor",
	Unit.SUPPLY: "supply", Unit.HARVESTER: "harvester",
	Unit.NAVAL: "naval", Unit.SUBMARINE: "submarine",
	Unit.PRODUCTION: "production", Unit.BASE: "base", Unit.UNKNOWN: "unknown",
}

## Keyword -> role, tried IN THIS ORDER against the WORDS of the unit's own
## name. Order matters, so this is an Array of pairs and never a Dictionary --
## docs/06 forbids letting iteration order decide an outcome.
##
## Matched per WORD rather than as a substring, which is not fussiness: the
## substring version classified "factory" as a SAM battery, because "factory"
## contains "tor". It then handed the building a 40 km missile and let it
## shoot. A classifier that is wrong in that direction hands the AI a weapon it
## does not have, which looks exactly like cheating from the other side.
const KEYWORDS := [
	# HARVESTERS FIRST, and they are first for a reason that cost a match.
	# "Ore Miner" fell through every rule below to the kinematic fallback and
	# came out ARMOR, so the director put the AI's own harvesters in a
	# manoeuvre group and drove them at the enemy -- which also SUSPENDS the
	# ore cycle (SimHarvest.interrupt), because a move order is a player order.
	# Measured on skirmish_valley: both AIs finished a six-minute match with
	# zero harvesters, an idle refinery and about 100 credits, producing rifle
	# squads because nothing else was affordable. The classifier was the bug.
	["harvester", Unit.HARVESTER], ["harvest", Unit.HARVESTER],
	["miner", Unit.HARVESTER], ["mining", Unit.HARVESTER],
	["aew", Unit.AEW], ["awacs", Unit.AEW], ["sentry", Unit.AEW],
	["mainstay", Unit.AEW],
	["tanker", Unit.SUPPLY], ["supply", Unit.SUPPLY], ["fuel", Unit.SUPPLY],
	["truck", Unit.SUPPLY], ["oiler", Unit.SUPPLY], ["logistics", Unit.SUPPLY],
	["ammunition", Unit.SUPPLY], ["engineer", Unit.SUPPLY],
	["repair", Unit.SUPPLY], ["sapper", Unit.SUPPLY],
	["sam", Unit.SAM], ["manpads", Unit.SAM], ["spaag", Unit.SAM],
	["shorad", Unit.SAM], ["patriot", Unit.SAM],
	["radar", Unit.SENSOR], ["esm", Unit.SENSOR], ["jammer", Unit.SENSOR],
	["illuminator", Unit.SENSOR], ["ew", Unit.SENSOR],
	["command", Unit.SENSOR],
	["scout", Unit.SCOUT], ["recon", Unit.SCOUT], ["brdm", Unit.SCOUT],
	["hmmwv", Unit.SCOUT],
	["infantry", Unit.INFANTRY], ["squad", Unit.INFANTRY],
	["rifle", Unit.INFANTRY], ["team", Unit.INFANTRY],
	["factory", Unit.PRODUCTION], ["barracks", Unit.PRODUCTION],
	["works", Unit.PRODUCTION], ["yard", Unit.PRODUCTION],
	["hangar", Unit.PRODUCTION], ["airbase", Unit.PRODUCTION],
	["helipad", Unit.PRODUCTION], ["plant", Unit.PRODUCTION],
]


static func name_of(role: int) -> String:
	return NAMES.get(role, "?")


## Classify one of the AI's OWN units. Keyword first, then kinematics, because
## a name is the strongest signal available and the category is the fallback
## that always exists.
static func classify(unit_name: String, category: int, structure: bool,
		max_speed_ms: float) -> int:
	var words := _words(unit_name)
	for pair in KEYWORDS:
		if not _matches(words, pair[0] as String):
			continue
		var r: int = pair[1]
		# A structure never becomes a mobile role, and vice versa.
		if structure:
			if r == Unit.PRODUCTION or r == Unit.SENSOR or r == Unit.SAM:
				return r
			return Unit.BASE
		if r == Unit.PRODUCTION:
			continue
		return r
	if structure:
		return Unit.BASE
	match category:
		SimTypes.Category.AIR:
			return Unit.AIR
		SimTypes.Category.SUBSURFACE:
			return Unit.SUBMARINE
		SimTypes.Category.SURFACE:
			return Unit.NAVAL
	if max_speed_ms <= 0.01:
		# Immobile and not a structure: a towed or emplaced set.
		return Unit.SENSOR
	return Unit.ARMOR


## Lower-cased words of a name, split on anything that is not a letter or a
## digit, so "AEW&C Aircraft", "Anti-Tank Team" and "T-80" all tokenise sanely.
static func _words(unit_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	var current := ""
	for ch in unit_name.to_lower():
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9"):
			current += ch
		else:
			if current != "":
				out.append(current)
			current = ""
	if current != "":
		out.append(current)
	return out


static func _matches(words: PackedStringArray, keyword: String) -> bool:
	for w in words:
		if w == keyword or (w as String).begins_with(keyword):
			return true
	return false


## Does this role belong in a manoeuvre group?
static func is_line(role: int) -> bool:
	return role in [Unit.ARMOR, Unit.INFANTRY, Unit.NAVAL, Unit.SUBMARINE]


## Roles that are worth protecting rather than spending -- and, seen from the
## other side, exactly what an Interdiction doctrine hunts.
static func is_enabler(role: int) -> bool:
	return role in [Unit.AEW, Unit.SENSOR, Unit.SUPPLY, Unit.SAM,
		Unit.PRODUCTION, Unit.HARVESTER]


## Roles that earn money rather than fight. The director never puts one in a
## manoeuvre group and never gives it a destination: a harvester runs its own
## cycle in SimHarvest and any order at all stops it working.
static func is_economic(role: int) -> bool:
	return role == Unit.HARVESTER


static func is_sensor_platform(role: int) -> bool:
	return role in [Unit.AEW, Unit.SENSOR]


static func can_scout(role: int) -> bool:
	return role in [Unit.SCOUT, Unit.AIR]


## The weapon(s) a role is assumed to carry, in the order the tactical layer
## should try them. Trying an anti-radiation round FIRST and falling back to a
## radar missile is the docs/09 §3 line "weapon-guidance matching" in its
## cheapest honest form: the gate refuses the ARM against a target that is not
## radiating, so the fallback happens by itself.
static func default_loadout(role: int) -> Array:
	match role:
		Unit.ARMOR:
			return [SimWeaponDef.new({"name": "main gun",
				"guidance": SimTypes.Guidance.UNGUIDED,
				"min_range_km": 0.0, "max_range_km": 4.0})]
		Unit.INFANTRY:
			return [SimWeaponDef.new({"name": "ATGM",
				"guidance": SimTypes.Guidance.SACLOS,
				"min_range_km": 0.05, "max_range_km": 3.0})]
		Unit.SCOUT:
			return [SimWeaponDef.new({"name": "autocannon",
				"guidance": SimTypes.Guidance.UNGUIDED,
				"min_range_km": 0.0, "max_range_km": 2.5})]
		Unit.AIR:
			return [
				SimWeaponDef.new({"name": "ARM",
					"guidance": SimTypes.Guidance.ANTI_RADIATION,
					"min_range_km": 2.0, "max_range_km": 80.0}),
				SimWeaponDef.new({"name": "AAM",
					"guidance": SimTypes.Guidance.ARH,
					"min_range_km": 1.0, "max_range_km": 60.0}),
			]
		Unit.SAM:
			return [SimWeaponDef.new({"name": "SAM",
				"guidance": SimTypes.Guidance.SARH,
				"min_range_km": 3.0, "max_range_km": 40.0})]
		Unit.NAVAL:
			return [SimWeaponDef.new({"name": "SSM",
				"guidance": SimTypes.Guidance.COMMAND_LINK,
				"min_range_km": 2.0, "max_range_km": 120.0,
				"needs_datalink": true})]
		Unit.SUBMARINE:
			return [SimWeaponDef.new({"name": "torpedo",
				"guidance": SimTypes.Guidance.COMMAND_LINK,
				"min_range_km": 1.0, "max_range_km": 35.0,
				"needs_datalink": true})]
	# AEW, SENSOR, SUPPLY, PRODUCTION, BASE, UNKNOWN: unarmed. An unarmed unit
	# is never given an engagement order, which is why this returns empty rather
	# than a token weapon.
	return []
