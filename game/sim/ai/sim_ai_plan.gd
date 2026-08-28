class_name SimAiPlan
extends RefCounted
## What the AI wants to BUILD, as opposed to what it wants to kill.
##
## docs/09 §5 gives seven doctrine weights and §2 gives a sensor-share skill
## dial; between them they determine a force mix. This class turns those
## weights into "the thing I am most short of right now", and then into an
## actual role key from the actual roster.
##
## NOT A LEAK. Everything here is asked through the player's own economy --
## what THIS player may build at THIS player's epoch, what THIS player's
## factory can turn out. docs/09 §1.2 lists another player's economy and queue
## as leaks; a player's own tech tree is the build menu it looks at anyway, and
## the roster is public in the same sense the terrain is.

## Credits held back before an epoch advance is attempted, so teching up does
## not empty the account in front of an attack. Used only when the economy
## cannot quote a real advance cost.
const TECH_RESERVE := 3000.0

## The four buckets a force divides into. Fixed order, never Dictionary order.
const BUCKETS := ["sensors", "air_defence", "supply", "line"]


## The mix this doctrine and skill want, as shares of the force that sum to 1.
##
##   sensors      docs/09 §2 "sensor share of budget" -- the Elite buys AEW early
##   air defence  rises with a defensive posture; a Fortress is a SAM belt
##   supply       docs/09 §5 logistics_depth -- how far it pushes supply out
##   line         everything left, which is what actually takes ground
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
	if SimAiRoles.is_economic(role):
		# Deliberately outside the four combat buckets: a harvester is not a
		# share of the force, it is what pays for the force. It gets its own
		# target count in choose_production() instead.
		return ""
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


## The bucket the AI is furthest below its desired share in. Ties break on the
## fixed BUCKETS order, never on Dictionary order.
static func biggest_deficit(counts: Dictionary, mix: Dictionary) -> String:
	var total := 0.0
	for k in BUCKETS:
		total += float(counts.get(k, 0))
	if total <= 0.0:
		# Nothing fielded at all: start with something that can shoot.
		return "line"
	var worst := ""
	var worst_gap := 0.0
	for k in BUCKETS:
		var have: float = float(counts.get(k, 0)) / total
		var gap: float = float(mix.get(k, 0.0)) - have
		if gap > worst_gap:
			worst_gap = gap
			worst = k
	return worst if worst != "" else "line"


## Which bucket a roster entry belongs in, classified from its published name
## and category exactly as the AI classifies its own units.
static func bucket_of_def(d: SimUnitDef) -> String:
	if d == null or d.is_structure:
		return ""
	return bucket_of(SimAiRoles.classify(d.name, d.category, false,
		d.max_speed_ms()))


## Pick something to produce from what this factory can actually turn out.
##
## `options` is the economy's own answer to "what can this structure build",
## already filtered to this player's epoch, domains and prerequisites. Within
## the bucket the AI is shortest of, it takes the most capable thing it can
## afford -- cost is the only capability proxy available without a second
## balance table, and a commander who buys the best he can pay for is a
## reasonable commander.
static func choose_production(view: SimAiWorldView, doctrine: SimDoctrine,
		skill: int, options: PackedStringArray, counts: Dictionary,
		credits: float, harvester_target := 0, scout_target := 0) -> String:
	if options.is_empty():
		return ""

	# TWO THINGS COME BEFORE THE MIX, and both are answers to a measurement
	# rather than to the doctrine table.
	#
	# HARVESTERS, because the mix is a mix of SHOOTERS and a share-of-force
	# rule can never ask for the thing that pays for the force. An AI with no
	# harvester has one income -- its starting trickle -- and a measured peer
	# match ended with both sides at ~100 credits producing the cheapest
	# infantry on the list. Money first.
	#
	# SCOUTS, because the mix counts a reconnaissance vehicle as "line" and it
	# is never short of line. The first job is to find the enemy, and an army
	# that buys no eyes does not get to.
	var early := _first_of_kind(view, options, credits,
		SimAiRoles.Unit.HARVESTER, int(counts.get("economy", 0)), harvester_target,
		false)
	if early != "":
		return early
	early = _first_of_kind(view, options, credits,
		SimAiRoles.Unit.SCOUT, int(counts.get("recon", 0)), scout_target, true)
	if early != "":
		return early

	var mix := desired_mix(doctrine, skill)
	var want := biggest_deficit(counts, mix)

	var best := ""
	var best_cost := -1.0
	var cheapest := ""
	var cheapest_cost := INF
	var fallback := ""
	var fallback_cost := INF
	for role in options:
		var d := view.def_for(role)
		if d == null:
			continue
		if d.cost < fallback_cost:
			fallback = role
			fallback_cost = d.cost
		if bucket_of_def(d) != want:
			continue
		if d.cost < cheapest_cost:
			cheapest = role
			cheapest_cost = d.cost
		if d.cost <= credits and d.cost > best_cost:
			best = role
			best_cost = d.cost
	if best != "":
		return best
	if cheapest != "" and cheapest_cost <= credits:
		return cheapest
	# Nothing in the bucket is affordable here; take the cheapest thing this
	# factory makes rather than stalling the line.
	return fallback if fallback_cost <= credits else ""


## The thing this factory makes that best fills a role the AI is short of.
##
## `fastest` picks the quickest rather than the cheapest, and the distinction is
## the whole difference between a scout and a harvester. A harvester is a
## harvester: pay the least. A scout is GROUND COVERED PER MINUTE, and the
## cheapest thing the classifier calls a scout is a foot recon team that cannot
## cross a 6.4 km map before the match is over. Ties break on cost, then on the
## key, so the choice is identical on every run.
static func _first_of_kind(view: SimAiWorldView, options: PackedStringArray,
		credits: float, role: int, have: int, want: int,
		fastest: bool) -> String:
	if have >= want or want <= 0:
		return ""
	var best := ""
	var best_cost := INF
	var best_speed := -1.0
	for key in options:
		var d := view.def_for(key)
		if d == null or d.is_structure or d.cost > credits:
			continue
		var speed := d.max_speed_ms()
		if SimAiRoles.classify(d.name, d.category, false, speed) != role:
			continue
		var better := false
		if fastest:
			better = speed > best_speed \
				or (speed == best_speed and d.cost < best_cost)
		else:
			better = d.cost < best_cost \
				or (d.cost == best_cost and speed > best_speed)
		if better:
			best_cost = d.cost
			best_speed = speed
			best = key
	return best


## The order a base gets built in. A doctrine changes what goes up early --
## a Sensor Dominance AI puts a radar station before a barracks, a Fortress
## puts a SAM belt in front of everything, a Tech Rush buys the research
## facility that docs/05 epoch advancement actually requires.
static func base_build_order(doctrine: SimDoctrine) -> PackedStringArray:
	var d: SimDoctrine = doctrine if doctrine != null else SimDoctrine.new()
	var out := PackedStringArray(["power_plant", "refinery", "heavy_factory"])
	if d.sensor_share >= 0.55:
		out.append("fixed_radar")
	if d.aggression <= 0.45:
		out.append("fixed_sam")
	if d.tech_bias >= 0.55:
		out.append("research_facility")
	out.append("barracks")
	if d.logistics_depth >= 0.45:
		out.append("supply_depot")
	if d.sensor_share < 0.55:
		out.append("fixed_radar")
	if d.aggression > 0.45:
		out.append("fixed_sam")
	if d.tech_bias < 0.55:
		out.append("research_facility")
	out.append("light_factory")
	out.append("airbase")
	return out
