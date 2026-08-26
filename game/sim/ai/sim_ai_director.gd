class_name SimAiDirector
extends RefCounted
## One AI opponent. docs/09 §3: three layers at three rates.
##
## ══ THIS IS A STUB. ══
## It decides nothing yet. The signatures and, more importantly, the
## CONSTRUCTOR are final.
##
## Look at what _init() takes: a SimAiWorldView and nothing else. There is no
## overload that accepts a SimEntities, a SimWorld, or another faction's track
## table, and adding one would be the bug docs/09 §1.1 says makes every pillar
## in the design decorative. If a future behaviour seems to need ground truth,
## the answer is that it needs a better sensor, not a wider constructor.
##
## OWNERSHIP: writes NOTHING in the entity store. Its only output is commands.

## docs/09 §3 rates, mirroring the docs/06 tick budget.
const STRATEGIC_HZ := 0.3   ## economy, epoch advancement, production mix
const OPERATIONAL_HZ := 1.5 ## where to attack, sensor placement, EMCON posture
const TACTICAL_HZ := 6.0    ## target selection, weapon matching, evasion

var view: SimAiWorldView
var rng: SimRng
var skill: int = SimSkill.Level.VETERAN
var doctrine: SimDoctrine = null

var _strategic_accum: float = 0.0
var _operational_accum: float = 0.0
var _tactical_accum: float = 0.0

## Decisions taken, for the debug view docs/09 §1.6 asks to be built early:
## "Render the AI's track table beside ground truth and you can SEE what it
## believes. Most AI bugs become visually obvious."
var decision_log: Array = []
var max_log: int = 120


func _init(world_view: SimAiWorldView, seeded: SimRng) -> void:
	view = world_view
	rng = seeded
	if view != null and view.setup != null:
		skill = view.setup.skill
		doctrine = view.setup.doctrine


# ═══════════════════════════════════════════════════════════════════════════
# THE API
# ═══════════════════════════════════════════════════════════════════════════

## The tick slot. Called every simulation tick; this class does its own rate
## division into the three layers, because docs/09 §3 gives them three different
## rates and SimWorld should not have to know about that.
##
## MUST: read view.tracks and view.forces only; emit orders only through
## view.order_*(); and honour the docs/09 §2 difficulty dials -- reaction
## latency from new track to action, and the commit threshold (a Recruit waits
## for TQ3, an Elite acts on TQ1 cues).
func step(dt: float) -> void:
	_strategic_accum += dt
	_operational_accum += dt
	_tactical_accum += dt
	if _tactical_accum >= 1.0 / TACTICAL_HZ:
		tactical_tick(_tactical_accum)
		_tactical_accum = 0.0
	if _operational_accum >= 1.0 / OPERATIONAL_HZ:
		operational_tick(_operational_accum)
		_operational_accum = 0.0
	if _strategic_accum >= 1.0 / STRATEGIC_HZ:
		strategic_tick(_strategic_accum)
		_strategic_accum = 0.0


## docs/09 §3: economy, epoch advancement, production mix, theatre priorities.
## Also the adaptation band -- a doctrine sets a posture, not a script, and
## "a profile that never adapts is exploitable in one match and boring in the
## second."
func strategic_tick(dt: float) -> void:
	pass


## Where to attack, force composition, sensor and AEW placement, EMCON posture,
## supply routing.
func operational_tick(dt: float) -> void:
	pass


## Target selection, weapon-guidance matching, evasive response to threat
## warnings. MUST run the SAME SimWeaponGate the player does -- docs/09 §3:
## "It is not an approximation of the player's rules; it is those rules."
func tactical_tick(dt: float) -> void:
	pass


## docs/09 §3 threat table: what the AI does is a function of what KIND of
## knowledge it holds. Returns a priority score for one track, higher = more
## urgent. MUST weight TQ3 on a high-value emitter above a TQ1 bearing, and MUST
## weight by doctrine.target_priority -- an Interdiction AI hunts tankers, AEW
## and supply trucks instead of the army.
func threat_score(track: SimTrack) -> float:
	return 0.0


func log_decision(line: String) -> void:
	decision_log.append(line)
	if decision_log.size() > max_log:
		decision_log.pop_front()


## True once this class actually decides anything.
func is_implemented() -> bool:
	return false
