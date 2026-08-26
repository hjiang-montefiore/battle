class_name SimAiPlan
extends RefCounted
## What the AI wants to BUILD, as opposed to what it wants to kill.
##
## docs/09 §5 gives seven doctrine weights and §2 gives a sensor-share skill
## dial; between them they determine a force mix. This class turns those
## weights into "the thing I am most short of right now", by comparing the
## desired mix against what the AI can see it owns -- which is its own army,
## and therefore no leak.
##
## HONEST LIMIT, and it is a big one. SimEconomy.queue_production() and
## spawn_unit() are still stubs, and there is no unit roster in the repo, so
## there is no authoritative list of def keys to produce. The keys below are
## the AI's REQUEST, submitted through the ordinary command queue; until the
## economy is real they are rejected there and nothing is built. When a roster
## lands, ROLE_KEYS is the one dictionary that has to agree with it.

## SimAiRoles.Unit -> the def key the AI asks for.
const ROLE_KEYS := {
	SimAiRoles.Unit.ARMOR: "mbt",
	SimAiRoles.Unit.INFANTRY: "infantry",
	SimAiRoles.Unit.SCOUT: "scout",
	SimAiRoles.Unit.AIR: "fighter",
	SimAiRoles.Unit.AEW: "aew",
	SimAiRoles.Unit.SAM: "sam",
	SimAiRoles.Unit.SENSOR: "radar",
	SimAiRoles.Unit.SUPPLY: "supply_truck",
	SimAiRoles.Unit.PRODUCTION: "factory",
}

## Nominal prices, used ONLY to decide whether to bother asking. The economy is
## the authority on cost and will refuse what cannot be afforded; this table
## exists so the AI does not fill the queue with requests it knows are hopeless.
const NOMINAL_COST := {
	SimAiRoles.Unit.ARMOR: 900.0,
	SimAiRoles.Unit.INFANTRY: 250.0,
	SimAiRoles.Unit.SCOUT: 450.0,
	SimAiRoles.Unit.AIR: 2200.0,
	SimAiRoles.Unit.AEW: 4000.0,
	SimAiRoles.Unit.SAM: 1600.0,
	SimAiRoles.Unit.SENSOR: 1100.0,
	SimAiRoles.Unit.SUPPLY: 500.0,
	SimAiRoles.Unit.PRODUCTION: 2000.0,
}

## Credits held back before an epoch advance is attempted, so teching up does
## not empty the account in front of an attack.
const TECH_RESERVE := 3000.0


## The mix this doctrine and skill want, as shares of the force that sum to 1.
##
##   sensors    docs/09 §2 "sensor share of budget" -- the Elite buys AEW early
##   air defence  rises with a defensive posture; a Fortress is a SAM belt
##   supply     docs/09 §5 logistics_depth -- how far it pushes supply out
##   line       everything left, which is what actually takes ground
##
## Deliberately a function of BOTH doctrine and skill: docs/09 §2 says
## difficulty is how competently the AI handles its information, and buying
## sensors is the clearest expression of that. A Recruit Sensor-Dominance AI
## still buys fewer sensors than an Elite one.
static func desired_mix(doctrine: SimDoctrine, skill: int) -> Dictionary:
	var d: SimDoctrine = doctrine if doctrine != null else SimDoctrine.new()
	var sensors: float = clampf(
		0.5 * (d.sensor_share + SimSkill.sensor_share(skill)), 0.03, 0.45)
	var air_defence: float = clampf(0.10 + 0.25 * (1.0 - d.aggression)
		+ 0.15 * d.ew_posture, 0.05, 0.40)
	var supply: float = clampf(0.05 + 0.20 * d.logistics_depth, 0.03, 0.25)
	var line: float = maxf(0.10, 1.0 - sensors - air_defence - supply)
	var total: float = sensors + air_defence + supply + line
	return {
		"sensors": sensors / total,
		"air_defence": air_defence / total,
		"supply": supply / total,
		"line": line / total,
	}


## Which of the four buckets a role counts toward.
static func bucket_of(role: int) -> String:
	if SimAiRoles.is_sensor_platform(role):
		return "sensors"
	if role == SimAiRoles.Unit.SAM:
		return "air_defence"
	if role == SimAiRoles.Unit.SUPPLY:
		return "supply"
	if SimAiRoles.is_line(role) or role == SimAiRoles.Unit.AIR \
			or role == SimAiRoles.Unit.SCOUT:
		return "line"
	return ""


## The bucket the AI is furthest below its desired share in. Ties break on a
## fixed bucket order, never on Dictionary order.
static func biggest_deficit(counts: Dictionary, mix: Dictionary) -> String:
	var total := 0.0
	for k in ["sensors", "air_defence", "supply", "line"]:
		total += float(counts.get(k, 0))
	if total <= 0.0:
		# Nothing fielded at all: start with something that can shoot.
		return "line"
	var worst := ""
	var worst_gap := 0.0
	for k in ["sensors", "air_defence", "supply", "line"]:
		var have: float = float(counts.get(k, 0)) / total
		var gap: float = float(mix.get(k, 0.0)) - have
		if gap > worst_gap:
			worst_gap = gap
			worst = k
	return worst if worst != "" else "line"


## The role to build for a bucket. `prefer_air` lets a doctrine that has an air
## force ask for aircraft rather than tanks for the line bucket.
static func role_for_bucket(bucket: String, prefer_air: bool) -> int:
	match bucket:
		"sensors":
			return SimAiRoles.Unit.AEW if prefer_air else SimAiRoles.Unit.SENSOR
		"air_defence":
			return SimAiRoles.Unit.SAM
		"supply":
			return SimAiRoles.Unit.SUPPLY
	return SimAiRoles.Unit.AIR if prefer_air else SimAiRoles.Unit.ARMOR


static func key_for_role(role: int) -> String:
	return ROLE_KEYS.get(role, "")


static func cost_of_role(role: int) -> float:
	return NOMINAL_COST.get(role, 1000.0)
