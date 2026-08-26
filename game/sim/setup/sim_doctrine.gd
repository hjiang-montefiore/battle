class_name SimDoctrine
extends RefCounted
## Strategy profiles. docs/09 §5.
##
## A doctrine is a set of weights that shapes every layer of an AI's decisions.
## It sets a POSTURE, not a script: every AI re-evaluates on the strategic tick
## and shifts within a band around its profile, because a profile that never
## adapts is exploitable in one match and boring in the second.
##
## Doctrine is independent of faction. Each faction has a historical default,
## but any doctrine can be assigned to any faction -- "Russia playing Sensor
## Dominance" is ahistorical and a genuinely different fight, and the setup
## screen should allow it.

enum Profile {
	BLITZ,
	TECH_RUSH,
	SENSOR_DOMINANCE,
	DENIAL,
	ATTRITION,
	FORTRESS,
	INTERDICTION,
	COMBINED_ARMS,
}

## The seven weights from docs/09 §5, each 0-1.
var aggression: float = 0.5        ## timing and commitment of attacks
var tech_bias: float = 0.5         ## epoch advancement vs more units now
var emcon_discipline: float = 0.5  ## willingness to stay silent and go blind
var sensor_share: float = 0.5      ## budget on sensors/AEW/EW vs shooters
var ew_posture: float = 0.5        ## proactive jamming
var logistics_depth: float = 0.5   ## how far it pushes supply from base
var target_priority: float = 0.5   ## 0 = armies ... 1 = enablers
var profile: int = Profile.COMBINED_ARMS


func _init(p: Dictionary = {}) -> void:
	for k in p.keys():
		if k in self:
			set(k, p[k])


## aggression, tech, emcon, sensors, ew, logistics, target_priority
const WEIGHTS := {
	Profile.BLITZ:            [0.95, 0.15, 0.10, 0.15, 0.25, 0.30, 0.15],
	Profile.TECH_RUSH:        [0.20, 0.95, 0.55, 0.45, 0.30, 0.40, 0.35],
	Profile.SENSOR_DOMINANCE: [0.55, 0.65, 0.85, 0.95, 0.60, 0.55, 0.70],
	Profile.DENIAL:           [0.30, 0.55, 0.75, 0.70, 0.95, 0.45, 0.60],
	Profile.ATTRITION:        [0.80, 0.15, 0.15, 0.15, 0.20, 0.60, 0.10],
	Profile.FORTRESS:         [0.10, 0.50, 0.70, 0.80, 0.50, 0.25, 0.40],
	Profile.INTERDICTION:     [0.60, 0.45, 0.70, 0.65, 0.55, 0.90, 0.95],
	Profile.COMBINED_ARMS:    [0.50, 0.50, 0.50, 0.50, 0.50, 0.50, 0.50],
}

const NAMES := {
	Profile.BLITZ: "Blitz",
	Profile.TECH_RUSH: "Tech Rush",
	Profile.SENSOR_DOMINANCE: "Sensor Dominance",
	Profile.DENIAL: "Denial",
	Profile.ATTRITION: "Attrition",
	Profile.FORTRESS: "Fortress",
	Profile.INTERDICTION: "Interdiction",
	Profile.COMBINED_ARMS: "Combined Arms",
}

## What it feels like to play against -- docs/09 §5, for the setup screen.
const BLURB := {
	Profile.BLITZ: "Early pressure, constant. Punishes a slow opening and collapses if you survive to a generation ahead.",
	Profile.TECH_RUSH: "Quiet, then terrifying. A window to punish early, then a cliff.",
	Profile.SENSOR_DOMINANCE: "You keep dying to things you never saw. Kill its AEW or lose.",
	Profile.DENIAL: "Your picture is never reliable. Advancing means fighting half-blind.",
	Profile.ATTRITION: "Relentless, cheap, endless. Tests whether your quality actually scales.",
	Profile.FORTRESS: "Nothing comes to you. You have to go in, and it sees you coming.",
	Profile.INTERDICTION: "It hunts your tankers, oilers, AEW and supply trucks instead of your army.",
	Profile.COMBINED_ARMS: "Balanced and adaptive. Reads what you are doing and answers it.",
}


static func make(profile: int) -> SimDoctrine:
	var w: Array = WEIGHTS.get(profile, WEIGHTS[Profile.COMBINED_ARMS])
	return SimDoctrine.new({
		"profile": profile,
		"aggression": w[0], "tech_bias": w[1], "emcon_discipline": w[2],
		"sensor_share": w[3], "ew_posture": w[4], "logistics_depth": w[5],
		"target_priority": w[6]})


static func name_of(profile: int) -> String:
	return NAMES.get(profile, "?")


static func blurb(profile: int) -> String:
	return BLURB.get(profile, "")


## Doctrines set a posture, not a script. These are the adaptations docs/09
## lists; each nudges a weight within a band rather than replacing the profile.
const ADAPT_BAND := 0.25


func adapt(losing_sensor_contest: bool, behind_on_epoch: bool,
		at_ceiling: bool, fuel_starved: bool, own_aew_dying: bool) -> void:
	var base := SimDoctrine.make(profile)
	if losing_sensor_contest:
		emcon_discipline = _nudge(emcon_discipline, base.emcon_discipline, 1.0)
		sensor_share = _nudge(sensor_share, base.sensor_share, 1.0)
	if behind_on_epoch and not at_ceiling:
		tech_bias = _nudge(tech_bias, base.tech_bias, 1.0)
	if at_ceiling:
		# Capped does not mean stalled: everything goes into retrofits and mass.
		tech_bias = _nudge(tech_bias, base.tech_bias, 0.0)
		aggression = _nudge(aggression, base.aggression, 1.0)
	if fuel_starved:
		logistics_depth = _nudge(logistics_depth, base.logistics_depth, 1.0)
		aggression = _nudge(aggression, base.aggression, 0.0)
	if own_aew_dying:
		# Stop flying it forward.
		sensor_share = _nudge(sensor_share, base.sensor_share, 0.0)
		emcon_discipline = _nudge(emcon_discipline, base.emcon_discipline, 1.0)


## Move toward `toward` but never further than ADAPT_BAND from the profile's
## own value, so an adapted Fortress is still recognisably a Fortress.
func _nudge(current: float, anchor: float, toward: float) -> float:
	var moved: float = lerpf(current, toward, 0.35)
	return clampf(moved, maxf(0.0, anchor - ADAPT_BAND),
			minf(1.0, anchor + ADAPT_BAND))


func describe() -> String:
	return ("%-17s aggr %.2f  tech %.2f  emcon %.2f  sensors %.2f  "
		+ "ew %.2f  logi %.2f  targets %.2f") % [
		name_of(profile), aggression, tech_bias, emcon_discipline,
		sensor_share, ew_posture, logistics_depth, target_priority]
