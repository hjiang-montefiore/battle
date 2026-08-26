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
	NAVAL,
	SUBMARINE,
	PRODUCTION,  ## a structure that builds things
	BASE,        ## every other structure
	UNKNOWN,
}

const NAMES := {
	Unit.ARMOR: "armor", Unit.INFANTRY: "infantry", Unit.SCOUT: "scout",
	Unit.AIR: "air", Unit.AEW: "aew", Unit.SAM: "sam", Unit.SENSOR: "sensor",
	Unit.SUPPLY: "supply", Unit.NAVAL: "naval", Unit.SUBMARINE: "submarine",
	Unit.PRODUCTION: "production", Unit.BASE: "base", Unit.UNKNOWN: "unknown",
}

## Substring -> role, tried in this order. Lower-cased match on the unit's own
## name. Order matters, so this is an Array of pairs and never a Dictionary --
## docs/06 forbids letting iteration order decide an outcome.
const KEYWORDS := [
	["aew", Unit.AEW], ["awacs", Unit.AEW], ["sentry", Unit.AEW],
	["e-3", Unit.AEW], ["e-2", Unit.AEW], ["mainstay", Unit.AEW],
	["tanker", Unit.SUPPLY], ["supply", Unit.SUPPLY], ["fuel", Unit.SUPPLY],
	["truck", Unit.SUPPLY], ["oiler", Unit.SUPPLY], ["logi", Unit.SUPPLY],
	["sam", Unit.SAM], ["patriot", Unit.SAM], ["s-300", Unit.SAM],
	["s-400", Unit.SAM], ["buk", Unit.SAM], ["tor", Unit.SAM],
	["hawk", Unit.SAM], ["aspide", Unit.SAM],
	["radar", Unit.SENSOR], ["esm", Unit.SENSOR], ["jammer", Unit.SENSOR],
	["illuminator", Unit.SENSOR], ["ewr", Unit.SENSOR],
	["scout", Unit.SCOUT], ["recon", Unit.SCOUT], ["brdm", Unit.SCOUT],
	["hmmwv", Unit.SCOUT],
	["infantry", Unit.INFANTRY], ["squad", Unit.INFANTRY],
	["rifle", Unit.INFANTRY], ["at team", Unit.INFANTRY],
	["factory", Unit.PRODUCTION], ["barracks", Unit.PRODUCTION],
	["works", Unit.PRODUCTION], ["yard", Unit.PRODUCTION],
	["hangar", Unit.PRODUCTION], ["plant", Unit.PRODUCTION],
]


static func name_of(role: int) -> String:
	return NAMES.get(role, "?")


## Classify one of the AI's OWN units. Keyword first, then kinematics, because
## a name is the strongest signal available and the category is the fallback
## that always exists.
static func classify(unit_name: String, category: int, structure: bool,
		max_speed_ms: float) -> int:
	var n := unit_name.to_lower()
	for pair in KEYWORDS:
		if n.contains(pair[0] as String):
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


## Does this role belong in a manoeuvre group?
static func is_line(role: int) -> bool:
	return role in [Unit.ARMOR, Unit.INFANTRY, Unit.NAVAL, Unit.SUBMARINE]


## Roles that are worth protecting rather than spending -- and, seen from the
## other side, exactly what an Interdiction doctrine hunts.
static func is_enabler(role: int) -> bool:
	return role in [Unit.AEW, Unit.SENSOR, Unit.SUPPLY, Unit.SAM,
		Unit.PRODUCTION]


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
