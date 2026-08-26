class_name SimTypes
extends RefCounted
## Shared vocabulary for the simulation core.
##
## Engine boundary (docs/06): nothing in sim/ touches the scene tree, Node,
## _process, or any Godot service. These types are plain data. GDScript cannot
## express a truly engine-free module -- RefCounted and the Packed*Array types
## are engine classes -- so the rule is applied where it actually pays: no
## nodes, no per-frame callbacks, no engine physics, no wall-clock, and hot
## state kept in flat parallel arrays rather than objects.


## Detection domains. Radar and sonar are the SAME solver with different
## constants plus one modifier (docs/02 §8), not separate code paths.
enum Domain {
	RF_ACTIVE,        ## radar. two-way, 1/R^4
	RF_PASSIVE,       ## ESM / RWR. one-way, 1/R^2, bearing-only
	IR,               ## IRST. passive, indifferent to RF stealth
	EO,               ## optical. short, daylight, weather-bound
	ACOUSTIC_ACTIVE,  ## sonar ping. two-way
	ACOUSTIC_PASSIVE, ## hydrophone. one-way, bearing-only
	MAGNETIC,         ## MAD. very short, confirms a datum
}

## Radar bands. Low bands defeat stealth shaping but resolve too coarsely to
## guide a weapon -- which is why a VHF set is capped at TRACK (docs/02 §7.5).
enum Band { VHF, UHF, L, S, C, X, KU }

## The track quality ladder (docs/02 §5). Weapons declare the rung they need;
## this is pillar 1 in its entirety.
enum TrackQuality {
	NONE = 0,          ## nothing
	CONTACT = 1,       ## bearing only, no range. cannot engage; can cue
	TRACK = 2,         ## position + velocity. unguided and command weapons
	FIRE_CONTROL = 3,  ## continuous precision track. required for guided
	TERMINAL = 4,      ## the weapon's own seeker has it. launcher may break away
}

## Classification is a SEPARATE axis from track quality (docs/02 §5.1).
## A precise fire-control solution on something you cannot name is a real and
## deliberately tense situation.
enum Classification {
	UNKNOWN = 0,   ## something is there
	CATEGORY = 1,  ## air / surface / subsurface / ground
	CLASS = 2,     ## fighter-sized, warship, vehicle...
	TYPE = 3,      ## the specific model, and therefore its armor and reach
	IDENTITY = 4,  ## friend, hostile, neutral
}

## Broad kinematic category, used for the free-but-coarse CLASS inference.
enum Category { AIR, SURFACE, SUBSURFACE, GROUND }

## Weapon guidance (docs/02 §5, weapon gating table).
enum Guidance {
	UNGUIDED,        ## gun, dumb bomb, rocket artillery
	SACLOS,          ## wire-guided ATGM, early SAM
	SARH,            ## semi-active radar homing -- illuminator must hold TQ3
	ARH,             ## active radar homing -- self-promotes at seeker range
	IR_EO,           ## heat-seeking / electro-optical. immune to RF jamming
	COMMAND_LINK,    ## guided from ANY networked track source
	GNSS_INS,        ## coordinates, not a track. useless against movers
	ANTI_RADIATION,  ## homes on the target's own emissions
}

## Emission control (docs/02 §7.1). The primary UI expression of the whole
## system, and it should be one keypress.
enum Emcon {
	SILENT,   ## passive only. invisible to enemy ESM, blind without the table
	RECEIVE,  ## passive plus intermittent. brief, hard-to-classify hits
	RADIATE,  ## everything. seen first and farther than you see
}


static func quality_name(q: int) -> String:
	match q:
		TrackQuality.NONE: return "NONE"
		TrackQuality.CONTACT: return "CONTACT"
		TrackQuality.TRACK: return "TRACK"
		TrackQuality.FIRE_CONTROL: return "FIRE_CONTROL"
		TrackQuality.TERMINAL: return "TERMINAL"
	return "?"


static func classification_name(c: int) -> String:
	match c:
		Classification.UNKNOWN: return "UNKNOWN"
		Classification.CATEGORY: return "CATEGORY"
		Classification.CLASS: return "CLASS"
		Classification.TYPE: return "TYPE"
		Classification.IDENTITY: return "IDENTITY"
	return "?"


static func guidance_name(g: int) -> String:
	match g:
		Guidance.UNGUIDED: return "UNGUIDED"
		Guidance.SACLOS: return "SACLOS"
		Guidance.SARH: return "SARH"
		Guidance.ARH: return "ARH"
		Guidance.IR_EO: return "IR_EO"
		Guidance.COMMAND_LINK: return "COMMAND_LINK"
		Guidance.GNSS_INS: return "GNSS_INS"
		Guidance.ANTI_RADIATION: return "ANTI_RADIATION"
	return "?"
