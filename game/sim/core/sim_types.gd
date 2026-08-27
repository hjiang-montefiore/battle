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


# ═══════════════════════════════════════════════════════════════════════════
# THE SPINE. Vocabulary the damage, movement, economy and AI layers share.
# Added here rather than in each subsystem because four agents have to agree
# on these integers, and an enum defined twice is an enum that will disagree.
# ═══════════════════════════════════════════════════════════════════════════

## Which armour facet a round arrives at. docs/03 lists FRONT_HULL,
## FRONT_TURRET, SIDE, REAR, TOP and BELLY; hull and turret are collapsed into
## one FRONT here because SimProjectile.impact_facet() -- which is the ONLY
## thing that decides a facet, from impact geometry and never from a roll --
## cannot distinguish them without a turret bounding volume. The ordering is
## bit-for-bit identical to SimProjectile.Facet and test_spine.gd asserts it.
enum Facet { FRONT = 0, SIDE = 1, REAR = 2, TOP = 3, BELLY = 4 }
const FACET_COUNT := 5


## docs/03 armour types, in the order of the effectiveness matrix. The index
## stored per facet in SimEntities is one of these.
enum ArmorType {
	NONE = 0,             ## unarmoured: trucks, radars, aircraft, infantry
	CAST = 1,             ## 1950s cast homogeneous
	RHA = 2,              ## 1950s rolled homogeneous -- the 1.00 baseline
	SPACED = 3,           ## 1960s
	NERA = 4,             ## 1960s-70s siliceous-cored
	COMPOSITE = 5,        ## 1970s-80s Chobham class
	COMPOSITE_HEAVY = 6,  ## late 1980s, heavy-metal mesh
	ERA_LIGHT = 7,        ## 1980s reactive
	ERA_HEAVY = 8,        ## 1990s+ reactive
	MODULAR_ERA = 9,      ## 2000s+ modular composite + ERA
}


## docs/03 damage classes. KE bleeds with range; CE does not. That asymmetry is
## the engagement grammar -- at long range an ATGM out-penetrates a tank gun,
## at short range the gun wins -- so it belongs in the shared vocabulary.
enum DamageClass {
	KE = 0,         ## AP, APCR, APDS, APFSDS. Penetration falls with range
	CE = 1,         ## HEAT, tandem, EFP, RPG. Flat with range
	HESH = 2,       ## squash head. Flat; defeated by spaced/composite
	OVERMATCH = 3,  ## very large calibre on thin plate; ignores slope
	BLAST = 4,      ## fragmentation and proximity warheads -- no penetration
}


## Two survivability models, one for each half of the game (docs/03, closing
## section). Armoured vehicles resolve penetration against a facet; ships and
## aircraft carry negligible armour and survive by defeating the weapon before
## it arrives. This selector says which one a unit uses.
enum DamageModel {
	UNARMORED = 0,  ## infantry, trucks, radars: structure pool only
	ARMORED = 1,    ## the docs/03 facet x penetrator matrix
	AIRFRAME = 2,   ## aircraft: structure pool, no facet resolution
	HULL = 3,       ## warships: structure pool plus compartment damage
	STRUCTURE = 4,  ## buildings: large structure pool, immobile
}


## Behind-armor effects, docs/03. Stored as a BITMASK per unit, not as a health
## bar: "resolve what it hit, not a subtraction". SENSOR_KILL is the row that
## links docs/03 to docs/02 -- a blind tank is alive and cannot engage.
enum Component {
	NONE = 0,
	MOBILITY = 1,      ## immobilised. The turret still traverses
	FIREPOWER = 2,     ## mobile but cannot fire
	SENSORS = 4,       ## optics/thermals/FCR gone. Alive and blind
	CREW = 8,          ## degraded rate of fire, accuracy, reaction
	CATASTROPHIC = 16, ## ammunition detonation. Total loss
}


## What a unit is doing with its engine. Drives the docs/04 fuel burn rates and
## the docs/02 acoustic/IR signature, so it is shared rather than private to
## the movement layer.
enum MoveState {
	IDLE = 0,      ## stationary, systems running -- burn_idle
	MOVING = 1,    ## economical movement -- burn_cruise
	COMBAT = 2,    ## flank speed / full military power -- burn_combat
	IMMOBILE = 3,  ## mobility-killed or out of fuel. Cannot move at all
	DEAD = 4,
}


## Commands crossing the presentation/AI boundary into the sim. Both the human
## player's mouse and the AI director push these; neither writes entity state
## directly. docs/06: "Godot's job is to render this and submit commands to it."
enum OrderKind {
	NONE = 0,
	MOVE = 1,          ## go to a world point
	STOP = 2,
	ATTACK_TRACK = 3,  ## engage a TRACK ID, never an entity index (docs/09 §1.3)
	SET_EMCON = 4,
	SET_MOVE_STATE = 5,
	PRODUCE = 6,       ## queue a unit at a structure
	BUILD = 7,         ## place a structure at a world point
	CANCEL = 8,
	PATROL = 9,        ## loop a list of world points until reordered
	LOAD = 10,         ## unit boards a transport (Command.target_unit names it)
	UNLOAD = 11,       ## transport disgorges (target_unit = one passenger, -1 = all)
	DEPLOY = 12,       ## toggle a deployable's state in place (towed guns, launchers)
	SORTIE_STRIKE = 13, ## aircraft: fly to x/z, deliver, come home on fuel (docs/04)
	SORTIE_PATROL = 14, ## aircraft: orbit x/z until the RTB rule says otherwise
	ATTACK_MOVE = 15,  ## advance to a world point at combat power, engaging en route
	SELL = 16,         ## refund part of a structure's cost and remove it
	REPAIR = 17,       ## pay to restore a damaged structure
}


## Deployable state machine, shared because SimEntities stores it per unit and
## the transport/deploy, movement and combat layers all read it. The
## TRANSITIONS take time -- deploy_timer in SimEntities counts them down --
## which is what makes catching a battery limbered a real reward rather than a
## cosmetic animation. SimEntities.can_move() is false in every state but
## MOBILE; whether a role may FIRE while deployed (towed artillery: only then)
## is the deploy system's per-role knowledge, not encoded here.
enum DeployState {
	MOBILE = 0,       ## travelling configuration. Can move, typically cannot fire
	DEPLOYING = 1,    ## in transition, vulnerable: cannot move, cannot fire
	DEPLOYED = 2,     ## emplaced. The role's deployed capability is live
	UNDEPLOYING = 3,  ## packing up: cannot move, cannot fire
}


## Where an aircraft is in its sortie. docs/04's eight aircraft states folded
## to the five the sim needs -- TAKEOFF, LANDING and TURNAROUND are timers the
## sortie system runs inside GROUNDED and RECOVERING, not distinct states the
## rest of the sim ever branches on. Stored per unit in SimEntities; written by
## the sortie system ONLY.
enum SortieState {
	GROUNDED = 0,    ## at home_base: ready, arming, or refuelling
	OUTBOUND = 1,    ## transiting to the tasked point at cruise
	ON_STATION = 2,  ## orbiting (SORTIE_PATROL) or attacking (SORTIE_STRIKE)
	RTB = 3,         ## returning: fuel rule, winchester, damage, or order
	RECOVERING = 4,  ## committed to the approach; cannot be re-tasked
}


static func deploy_state_name(s: int) -> String:
	match s:
		DeployState.MOBILE: return "MOBILE"
		DeployState.DEPLOYING: return "DEPLOYING"
		DeployState.DEPLOYED: return "DEPLOYED"
		DeployState.UNDEPLOYING: return "UNDEPLOYING"
	return "?"


static func sortie_state_name(s: int) -> String:
	match s:
		SortieState.GROUNDED: return "GROUNDED"
		SortieState.OUTBOUND: return "OUTBOUND"
		SortieState.ON_STATION: return "ON_STATION"
		SortieState.RTB: return "RTB"
		SortieState.RECOVERING: return "RECOVERING"
	return "?"


static func facet_name(f: int) -> String:
	match f:
		Facet.FRONT: return "FRONT"
		Facet.SIDE: return "SIDE"
		Facet.REAR: return "REAR"
		Facet.TOP: return "TOP"
		Facet.BELLY: return "BELLY"
	return "?"


static func armor_type_name(a: int) -> String:
	match a:
		ArmorType.NONE: return "NONE"
		ArmorType.CAST: return "CAST"
		ArmorType.RHA: return "RHA"
		ArmorType.SPACED: return "SPACED"
		ArmorType.NERA: return "NERA"
		ArmorType.COMPOSITE: return "COMPOSITE"
		ArmorType.COMPOSITE_HEAVY: return "COMPOSITE_HEAVY"
		ArmorType.ERA_LIGHT: return "ERA_LIGHT"
		ArmorType.ERA_HEAVY: return "ERA_HEAVY"
		ArmorType.MODULAR_ERA: return "MODULAR_ERA"
	return "?"


static func damage_class_name(d: int) -> String:
	match d:
		DamageClass.KE: return "KE"
		DamageClass.CE: return "CE"
		DamageClass.HESH: return "HESH"
		DamageClass.OVERMATCH: return "OVERMATCH"
		DamageClass.BLAST: return "BLAST"
	return "?"


## The components a unit has lost, as a readable list. Feeds the combat log,
## which docs/10 §10 calls "the tutorial".
static func component_names(mask: int) -> String:
	if mask == 0:
		return "intact"
	var out := PackedStringArray()
	if mask & Component.MOBILITY: out.append("mobility")
	if mask & Component.FIREPOWER: out.append("firepower")
	if mask & Component.SENSORS: out.append("sensors")
	if mask & Component.CREW: out.append("crew")
	if mask & Component.CATASTROPHIC: out.append("catastrophic")
	return ", ".join(out)
