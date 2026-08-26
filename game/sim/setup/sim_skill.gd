class_name SimSkill
extends RefCounted
## How competently an AI handles the information it has. docs/09 §2.
##
## Difficulty is doctrine quality, NOT bonuses. The AI plays with real
## information at every level, so the only thing that scales is how well it
## uses it. A resource handicap exists (SimPlayerSetup.resource_mult) but is a
## separate, clearly labelled slider that defaults to off, because a resource
## bonus makes the AI BIGGER rather than BETTER and this game is not decided by
## size.
##
## docs/09 §2 tabulates three tiers -- Recruit, Veteran, Elite. Eight are
## exposed here so the setup screen has a usable gradient; the three published
## rows are preserved exactly at RECRUIT, VETERAN and ELITE, and the rest
## interpolate between and beyond them.
##
## A NOTE ON THE TOP TWO TIERS. docs/09 calls Elite "a competent commander" and
## treats it as the ceiling. COMMANDER and WARLORD sit above it, and the only
## headroom left above competence is TEMPO AND COORDINATION -- faster reaction,
## more simultaneous axes, tighter sensor discipline. They get no extra
## information, because §1 forbids it absolutely and a cheat at the top tier
## would make every pillar below it decorative.

enum Level {
	RECRUIT,       ## careless. radiates constantly, dies to anti-radiation
	MILITIA,
	REGULAR,
	VETERAN,       ## the docs/09 middle row
	PROFESSIONAL,
	ELITE,         ## the docs/09 top row -- a competent commander
	COMMANDER,     ## faster and better coordinated. NOT better informed
	WARLORD,       ## the ceiling of tempo and coordination
}

const LEVEL_COUNT := 8


## Seconds from a new track appearing to the AI acting on it.
const REACTION_S := {
	Level.RECRUIT: 10.0,      # docs/09: 8-12 s
	Level.MILITIA: 7.5,
	Level.REGULAR: 5.5,
	Level.VETERAN: 4.0,       # docs/09: 3-5 s
	Level.PROFESSIONAL: 2.5,
	Level.ELITE: 1.5,         # docs/09: 1-2 s
	Level.COMMANDER: 1.0,
	Level.WARLORD: 0.7,
}

## The track quality this AI insists on before it will commit force.
const COMMIT_THRESHOLD := {
	Level.RECRUIT: SimTypes.TrackQuality.FIRE_CONTROL,   # waits for TQ3
	Level.MILITIA: SimTypes.TrackQuality.FIRE_CONTROL,
	Level.REGULAR: SimTypes.TrackQuality.TRACK,
	Level.VETERAN: SimTypes.TrackQuality.TRACK,          # acts on TQ2
	Level.PROFESSIONAL: SimTypes.TrackQuality.TRACK,
	Level.ELITE: SimTypes.TrackQuality.CONTACT,          # acts on TQ1 cues
	Level.COMMANDER: SimTypes.TrackQuality.CONTACT,
	Level.WARLORD: SimTypes.TrackQuality.CONTACT,
}

## 0 = radiates constantly, 1 = silent by default and ESM-first.
const EMCON_DISCIPLINE := {
	Level.RECRUIT: 0.05, Level.MILITIA: 0.18, Level.REGULAR: 0.34,
	Level.VETERAN: 0.50, Level.PROFESSIONAL: 0.66, Level.ELITE: 0.82,
	Level.COMMANDER: 0.90, Level.WARLORD: 0.95,
}

## Quality of extrapolation along a decaying track.
const PREDICTION := {
	Level.RECRUIT: 0.15, Level.MILITIA: 0.28, Level.REGULAR: 0.42,
	Level.VETERAN: 0.55, Level.PROFESSIONAL: 0.68, Level.ELITE: 0.82,
	Level.COMMANDER: 0.90, Level.WARLORD: 0.96,
}

## Share of budget spent on sensors, AEW and EW rather than shooters.
const SENSOR_SHARE := {
	Level.RECRUIT: 0.08, Level.MILITIA: 0.14, Level.REGULAR: 0.21,
	Level.VETERAN: 0.28, Level.PROFESSIONAL: 0.36, Level.ELITE: 0.45,
	Level.COMMANDER: 0.50, Level.WARLORD: 0.55,
}

## 0 ignores jamming; 0.5 re-tasks sensors; 1 changes bands and exploits
## home-on-jam.
const COUNTER_EW := {
	Level.RECRUIT: 0.0, Level.MILITIA: 0.15, Level.REGULAR: 0.32,
	Level.VETERAN: 0.50, Level.PROFESSIONAL: 0.68, Level.ELITE: 0.85,
	Level.COMMANDER: 0.93, Level.WARLORD: 1.0,
}

## Simultaneous axes of attack it can coordinate.
const AXES := {
	Level.RECRUIT: 1, Level.MILITIA: 1, Level.REGULAR: 2,
	Level.VETERAN: 2, Level.PROFESSIONAL: 3, Level.ELITE: 3,
	Level.COMMANDER: 4, Level.WARLORD: 5,
}

const LEVEL_NAMES := {
	Level.RECRUIT: "Recruit", Level.MILITIA: "Militia",
	Level.REGULAR: "Regular", Level.VETERAN: "Veteran",
	Level.PROFESSIONAL: "Professional", Level.ELITE: "Elite",
	Level.COMMANDER: "Commander", Level.WARLORD: "Warlord",
}

## One line the setup screen can show under the slider.
const LEVEL_BLURB := {
	Level.RECRUIT: "Radiates constantly and waits for a perfect track. Dies to anti-radiation missiles.",
	Level.MILITIA: "Slow to react, still careless with emissions.",
	Level.REGULAR: "Acts on a solid track. Notices it is being jammed.",
	Level.VETERAN: "Mixed emissions, reasonable prediction, two axes at once.",
	Level.PROFESSIONAL: "Buys sensors early and re-tasks them under jamming.",
	Level.ELITE: "Silent by default, ESM-first, and will act on a bare bearing.",
	Level.COMMANDER: "Faster and better coordinated than Elite. Not better informed.",
	Level.WARLORD: "Maximum tempo: five simultaneous axes under sensor cover. Still no extra information.",
}


static func name_of(level: int) -> String:
	return LEVEL_NAMES.get(level, "?")


static func blurb(level: int) -> String:
	return LEVEL_BLURB.get(level, "")


static func reaction_seconds(level: int) -> float:
	return REACTION_S.get(level, 4.0)


static func commit_threshold(level: int) -> int:
	return COMMIT_THRESHOLD.get(level, SimTypes.TrackQuality.TRACK)


static func emcon_discipline(level: int) -> float:
	return EMCON_DISCIPLINE.get(level, 0.5)


static func prediction(level: int) -> float:
	return PREDICTION.get(level, 0.5)


static func sensor_share(level: int) -> float:
	return SENSOR_SHARE.get(level, 0.28)


static func counter_ew(level: int) -> float:
	return COUNTER_EW.get(level, 0.5)


static func simultaneous_axes(level: int) -> int:
	return AXES.get(level, 2)


## Every dial is monotonic across the ladder. If a tier is ever inserted or
## retuned, the test suite asserts this still holds -- a difficulty slider with
## a non-monotonic rung is a bug the player experiences as randomness.
static func describe(level: int) -> String:
	return ("%-13s react %4.1fs  commit %-12s  emcon %.2f  sensors %.2f  "
		+ "counter-EW %.2f  %d axes") % [
		name_of(level), reaction_seconds(level),
		SimTypes.quality_name(commit_threshold(level)),
		emcon_discipline(level), sensor_share(level),
		counter_ew(level), simultaneous_axes(level)]
