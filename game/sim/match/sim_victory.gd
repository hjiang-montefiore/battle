class_name SimVictory
extends RefCounted
## How a match ENDS. The condition, why it is this condition, and the
## bookkeeping that makes losing legible.
##
## ═══════════════════════════════════════════════════════════════════════════
## THE CONDITION, AND THE ARGUMENT FOR IT
##
## Two obvious rules, and what is wrong with each:
##
##   "eliminate every enemy unit"  -- correct and unplayable. The last ten
##       minutes of every match are spent driving a tank across 150 km of map
##       hunting one surviving fuel truck that the enemy AI parked in a valley.
##       The decision was made twenty minutes earlier; the game just refuses to
##       admit it.
##
##   "destroy the enemy headquarters"  -- fast, legible, and it throws away the
##       entire game. Whoever gets one raid through wins regardless of the
##       campaign around it, and the correct play becomes hiding the HQ in the
##       far corner rather than fighting.
##
## What this game actually models is a WAR MACHINE: docs/04 makes fuel a real
## constraint, refineries a real bottleneck and supply radius a real geometry.
## So the condition is written in those terms:
##
##   A player is DEFEATED when they can no longer replace what they lose and
##   can no longer keep what they have fed.
##
## Concretely, in two stages:
##
##   1. COLLAPSE. The player holds no PRODUCTION structure (an HQ, barracks,
##      factory, airbase or naval yard, finished or still being built) and no
##      operational SUPPLY SOURCE (the docs/04 set: HQ, refinery, depot, repair
##      depot, airbase, helipad). Both halves matter: production is how you
##      replace losses, supply is how the army you still have keeps moving.
##
##   2. CAPITULATION. Collapse alone does not end it -- an army in the field is
##      still an army, and it gets CAPITULATION_SECONDS to change the situation
##      by taking ground, rebuilding, or killing whoever did this. If the
##      player rebuilds either half, the clock cancels outright. If it runs
##      out, the remaining force is lost: out of fuel, out of ammunition, out
##      of a chain of command.
##
## That last step is a fast-forward, not a fiction. The sim already burns fuel
## per docs/04 and already auto-resupplies only from operational sources; a
## force with no source genuinely grinds to IMMOBILE over the following twenty
## minutes. The timer plays that out in two, so the player is not made to watch
## it. And it is the whole answer to the drag problem: there is never a mop-up
## phase, because the mop-up is what the timer replaces.
##
## A player with nothing alive at all is eliminated immediately -- no clock.
##
## VICTORY is then a team question: the match ends when exactly one TEAM has a
## surviving player. The human wins if it is theirs. Allied AI on the human's
## team can be knocked out without ending the match, and an eliminated player
## stops thinking and stops being an obstacle without any index in the entity
## store moving (docs/06's SoA rule: death never removes a row).
## ═══════════════════════════════════════════════════════════════════════════

enum Outcome { UNDECIDED, VICTORY, DEFEAT, DRAW }

## docs/12's structures that turn credits into entities. Sorted, and iterated
## as an Array so nothing here depends on Dictionary order.
const PRODUCTION_ROLES := [
	"airbase", "barracks", "heavy_factory", "hq", "light_factory", "naval_yard",
]

## docs/04's forward supply points. A player holding one of these can still
## refuel the army it has.
const SUPPLY_ROLES := [
	"airbase", "helipad", "hq", "refinery", "repair_depot", "supply_depot",
]

## Two minutes to answer a collapse. Long enough that a counter-attack already
## rolling can still decide the game; short enough that nobody is made to watch
## an outcome that is settled.
const CAPITULATION_SECONDS := 120.0


## One player's position in the match. Recomputed every evaluation from a
## single ascending sweep of the entity store -- there is no incremental
## bookkeeping to get out of step with reality.
class Standing extends RefCounted:
	var player_id: int = -1
	var team: int = 0
	var name: String = "Player"
	var is_human: bool = false

	var eliminated: bool = false
	var eliminated_at_s: float = -1.0
	var reason: String = ""

	## Live counts, for the HUD.
	var production: int = 0
	var supply: int = 0
	var combat_units: int = 0
	var other_units: int = 0
	var structures: int = 0

	## Seconds spent in collapse. 0 when not collapsed.
	var capitulation_s: float = 0.0

	func total_alive() -> int:
		return combat_units + other_units + structures

	func is_collapsing() -> bool:
		return capitulation_s > 0.0 and not eliminated

	func seconds_left() -> float:
		return maxf(0.0, CAPITULATION_SECONDS - capitulation_s)

	func describe() -> String:
		if eliminated:
			return "%-12s ELIMINATED at %.0f s -- %s" % [name, eliminated_at_s, reason]
		var bits := "%-12s team %d  %d units  %d structures  prod %d  supply %d" % [
			name, team, combat_units + other_units, structures, production, supply]
		if is_collapsing():
			bits += "  CAPITULATING in %.0f s" % seconds_left()
		return bits


var entities: SimEntities
var economy: SimEconomy
var damage: SimDamage

## player id -> Standing. Indexed, never iterated; player_ids() sorts.
var _standings: Dictionary = {}
var _order: PackedInt32Array = PackedInt32Array()

var outcome: int = Outcome.UNDECIDED
var human_player_id: int = -1
var winning_team: int = -1
var elapsed_s: float = 0.0
## Optional hard stop. <= 0 means no limit. A time limit is a DRAW, not a win
## on points -- there is no points system, and inventing one to break a tie
## would be a bigger design decision than a draw.
var time_limit_s: float = 0.0

## Players knocked out on the most recent evaluation, ascending. The match
## layer drains this to shut their AI down.
var newly_eliminated: PackedInt32Array = PackedInt32Array()
var events: PackedStringArray = PackedStringArray()

## Evaluated on the economy's tier rather than every tick -- a victory
## condition is not a physical process and 1 Hz is four times finer than the
## fastest thing it can observe.
const EVALUATE_HZ := 1.0
var _accum: float = 0.0


func _init(store: SimEntities, economy_ref: SimEconomy,
		damage_ref: SimDamage) -> void:
	entities = store
	economy = economy_ref
	damage = damage_ref


## Register a participant. Call once per player at match start, in ascending
## player-id order.
func add_player(player_id: int, team: int, player_name: String,
		is_human: bool) -> Standing:
	var s := Standing.new()
	s.player_id = player_id
	s.team = team
	s.name = player_name
	s.is_human = is_human
	_standings[player_id] = s
	if is_human:
		human_player_id = player_id
	_order.append(player_id)
	_order.sort()
	return s


func player_ids() -> PackedInt32Array:
	return _order


func standing(player_id: int) -> Standing:
	return _standings.get(player_id)


func is_finished() -> bool:
	return outcome != Outcome.UNDECIDED


func step(dt: float) -> void:
	elapsed_s += dt
	if is_finished():
		return
	_accum += dt
	var period := 1.0 / EVALUATE_HZ
	if _accum < period:
		return
	var slice := _accum
	_accum = 0.0
	evaluate(slice)


## One ascending sweep, then the rules. Public so a test can drive it directly.
func evaluate(dt: float) -> void:
	newly_eliminated = PackedInt32Array()
	_recount()

	for pid in _order:
		var s := _standings[pid] as Standing
		if s.eliminated:
			continue
		# Nothing left at all: no clock, no ceremony.
		if s.total_alive() == 0:
			_eliminate(s, "every unit and structure destroyed")
			continue
		var collapsed := s.production == 0 and s.supply == 0
		if not collapsed:
			if s.capitulation_s > 0.0:
				_note("%s has rebuilt -- capitulation cancelled" % s.name)
			s.capitulation_s = 0.0
			continue
		if s.capitulation_s == 0.0:
			_note(("%s has lost every production structure and every supply "
				+ "source -- %.0f s to recover") % [s.name, CAPITULATION_SECONDS])
		s.capitulation_s += dt
		if s.capitulation_s >= CAPITULATION_SECONDS:
			_eliminate(s, "war machine destroyed -- the remaining force "
				+ "capitulated without fuel, ammunition or orders")

	_decide()


## An eliminated player's remaining force is lost. It goes through SimDamage,
## because the ownership table is absolute: nothing may call entities.kill()
## except SimDamage, and a victory condition is not an exception to that.
func _eliminate(s: Standing, why: String) -> void:
	s.eliminated = true
	s.eliminated_at_s = elapsed_s
	s.reason = why
	s.capitulation_s = 0.0
	newly_eliminated.append(s.player_id)
	_note("%s is ELIMINATED -- %s" % [s.name, why])
	if damage == null:
		return
	for i in entities.indices_of_owner(s.player_id):
		damage.apply_structure(i, entities.structure_max[i] + 1.0, "capitulation")


func _recount() -> void:
	for pid in _order:
		var s := _standings[pid] as Standing
		s.production = 0
		s.supply = 0
		s.combat_units = 0
		s.other_units = 0
		s.structures = 0
	var n := entities.count()
	for i in range(n):
		if entities.alive[i] == 0:
			continue
		var owner_id: int = entities.owner[i]
		var s: Standing = _standings.get(owner_id)
		if s == null:
			continue
		var role := "" if economy == null else economy.role_of(i)
		if entities.is_structure[i] == 1:
			s.structures += 1
			# A building SITE counts for production: it is money already spent
			# and a real attempt to recover, and refusing it would make the
			# capitulation clock impossible to beat.
			if role in PRODUCTION_ROLES:
				s.production += 1
			# Supply, unlike production, must actually be FINISHED. An
			# unfinished refinery refuels nothing, and the sim already agrees:
			# SimEconomy's auto-resupply skips non-operational sources.
			if role in SUPPLY_ROLES and economy != null and economy.is_operational(i):
				s.supply += 1
			continue
		if role != "" and SimArsenal.is_combatant(role):
			s.combat_units += 1
		else:
			s.other_units += 1


func _decide() -> void:
	var live_teams: Array = []
	var human_alive := false
	for pid in _order:
		var s := _standings[pid] as Standing
		if s.eliminated:
			continue
		if not live_teams.has(s.team):
			live_teams.append(s.team)
		if s.is_human:
			human_alive = true
	live_teams.sort()

	if live_teams.is_empty():
		winning_team = -1
		outcome = Outcome.DRAW
		_note("every participant has been eliminated -- draw")
		return
	if live_teams.size() == 1:
		winning_team = int(live_teams[0])
		# There is no human in an AI-vs-AI harness run, so "the human's team
		# won" cannot be the only way to finish.
		if human_player_id < 0:
			outcome = Outcome.VICTORY
		elif human_alive:
			outcome = Outcome.VICTORY
		else:
			outcome = Outcome.DEFEAT
		_note("team %d wins at %.0f s" % [winning_team, elapsed_s])
		return
	# Still more than one team standing. The human may nonetheless be out.
	if human_player_id >= 0 and not human_alive:
		outcome = Outcome.DEFEAT
		winning_team = -1
		_note("you have been eliminated at %.0f s" % elapsed_s)
		return
	if time_limit_s > 0.0 and elapsed_s >= time_limit_s:
		outcome = Outcome.DRAW
		winning_team = -1
		_note("time limit reached -- draw")


func _note(line: String) -> void:
	events.append(line)
	if events.size() > 120:
		events.remove_at(0)


# ── SAVE / LOAD (SimSave) ────────────────────────────────────────────────────
# The standings ARE the match's fates: capitulation clocks included, because a
# player saved sixty seconds into a collapse must still have sixty to go.
# newly_eliminated and events are drained by the match layer in the same tick
# they are filled, and are dropped.

func to_dict() -> Dictionary:
	var standings := {}
	for pid in _order:
		standings[str(pid)] = SimSave.enc_props(_standings[pid])
	return {
		"standings": standings,
		"outcome": outcome,
		"winning_team": winning_team,
		"elapsed_s": SimSave.enc_float(elapsed_s),
		"time_limit_s": SimSave.enc_float(time_limit_s),
		"accum": SimSave.enc_float(_accum),
	}


func from_dict(d: Dictionary) -> void:
	for pk in (d["standings"] as Dictionary):
		var pid := int(String(pk))
		var s: Standing = _standings.get(pid)
		if s == null:
			s = add_player(pid, 0, "Player", false)
		SimSave.dec_props(s, d["standings"][pk])
	outcome = int(d["outcome"])
	winning_team = int(d["winning_team"])
	elapsed_s = SimSave.dec_float(d["elapsed_s"])
	time_limit_s = SimSave.dec_float(d["time_limit_s"])
	_accum = SimSave.dec_float(d["accum"])


func outcome_name() -> String:
	match outcome:
		Outcome.VICTORY: return "VICTORY"
		Outcome.DEFEAT: return "DEFEAT"
		Outcome.DRAW: return "DRAW"
	return "IN PROGRESS"


## What the losing or winning player should be told, in one line.
func headline() -> String:
	match outcome:
		Outcome.VICTORY:
			return "VICTORY -- the enemy war machine is destroyed"
		Outcome.DEFEAT:
			var s: Standing = _standings.get(human_player_id)
			if s != null and s.reason != "":
				return "DEFEAT -- " + s.reason
			return "DEFEAT"
		Outcome.DRAW:
			return "DRAW"
	return ""


func describe() -> String:
	var lines := PackedStringArray()
	lines.append("%s   t+%.0f s" % [outcome_name(), elapsed_s])
	for pid in _order:
		lines.append("  " + (_standings[pid] as Standing).describe())
	return "\n".join(lines)
