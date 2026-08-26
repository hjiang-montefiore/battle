class_name SimFireControl
extends RefCounted
## WHICH track should this unit be shooting at? Slot 8b.5.
##
## The combat layer's report closed with: "A unit engages the track it was
## ordered to engage and nothing else -- no fire-at-will, no auto-acquire, no
## target reassignment when a track dies. The AI or a fire-control layer has to
## choose." This is that layer. Without it a playable game would require the
## player to hand-assign every gun to every contact, every time a contact
## decayed, which is not an RTS.
##
## ── THE INFORMATION RULE APPLIES HERE TOO ────────────────────────────────────
## docs/09 §1 is about the AI, but the rule is really about the SIMULATION: no
## decision may be made from information a participant does not hold. So this
## class is built exactly like the weapon cycle it feeds. It reads
## solver.table_for(entities.faction[unit]) -- the shooting unit's OWN
## coalition's track table -- and nothing else. It never reads another
## faction's table, never reads SimTrack._truth_index, and never asks
## SimEntities anything about a target. A unit auto-engages a HYPOTHESIS, at
## the range the hypothesis claims, and if the picture is wrong the shot is
## wrong. Both sides get exactly this, which is what makes it fair.
##
## Its ONLY output is SimWeaponCycle.engage(unit, track_id) -- the same call an
## ATTACK_TRACK order makes. It writes nothing to the entity store.
##
## ── DETERMINISM ──────────────────────────────────────────────────────────────
## Units are visited in ascending entity index; tracks in ascending track id
## (SimTrackTable.track_ids() sorts). Scoring ties break on the lower track id.
## No random draws, no clock.

## Retargeting is a decision, not a physical process, and it happens at human
## speed. 2 Hz costs one pass over the armed units every ten simulation ticks
## and is imperceptibly different from doing it every tick.
const RETARGET_HZ := 2.0

var entities: SimEntities
var weapons: SimWeaponCycle
var solver: SimSensorSolver
## Optional. When present, a structure that is still a building site does not
## open fire -- an unfinished bunker is scaffolding.
var economy: SimEconomy = null

## Units whose crews have been told to hold fire. Indexed, never iterated.
var _hold: Dictionary = {}
## Units the PLAYER (or an AI) explicitly ordered onto a track. Their choice is
## not second-guessed while the track lives; only when it dies does the unit
## come back into the automatic pool.
var _manual: Dictionary = {}

var assignments: int = 0
var reassignments: int = 0
var _accum: float = 0.0


func _init(store: SimEntities, weapon_cycle: SimWeaponCycle,
		sensor_solver: SimSensorSolver, economy_ref: SimEconomy = null) -> void:
	entities = store
	weapons = weapon_cycle
	solver = sensor_solver
	economy = economy_ref


## Weapons tight. The unit keeps its gun and refuses to use it, which is the
## other half of EMCON -- a player who does not want a contact shot at because
## shooting reveals the shooter needs to be able to say so.
func set_hold_fire(unit: int, hold: bool) -> void:
	if hold:
		_hold[unit] = true
		_manual.erase(unit)
		weapons.disengage(unit)
	else:
		_hold.erase(unit)


func is_holding_fire(unit: int) -> bool:
	return _hold.get(unit, false)


## Record that this engagement was ordered by hand, so automatic retargeting
## leaves it alone. SimWorld calls this on an ATTACK_TRACK that stuck.
func note_manual_order(unit: int) -> void:
	_manual[unit] = true
	_hold.erase(unit)


func is_manual(unit: int) -> bool:
	return _manual.get(unit, false)


func step(dt: float) -> void:
	_accum += dt
	var period := 1.0 / RETARGET_HZ
	if _accum < period:
		return
	_accum = 0.0
	_assign_all()


func _assign_all() -> void:
	var n := entities.count()
	for i in range(n):
		if entities.alive[i] == 0:
			continue
		if not weapons.is_armed(i):
			continue
		if _hold.get(i, false):
			weapons.disengage(i)
			continue
		if not entities.can_fire(i):
			continue
		if economy != null and entities.is_structure[i] == 1 \
				and not economy.is_operational(i):
			continue

		var table := solver.table_for(entities.faction[i])
		# Hold what we already have, if it is still worth holding. Re-picking a
		# target every half second produces a unit that swings its turret
		# between two contacts and never completes a reload.
		if weapons.is_engaging(i):
			var held := table.get_track(weapons.engagement_of(i))
			if held != null and _score(i, held) > -INF:
				continue
			# The track died, decayed or left the envelope. A hand-picked
			# target that is gone releases the unit back to automatic.
			_manual.erase(i)
			if held != null:
				weapons.disengage(i)
			reassignments += 1
		elif _manual.get(i, false):
			# The weapon cycle already dropped the engagement (its track was
			# dropped from the table). Same release.
			_manual.erase(i)

		var best := -1
		var best_score := -INF
		for tid in table.track_ids():
			var track := table.get_track(tid)
			if track == null:
				continue
			var s := _score(i, track)
			# Strictly greater, so the FIRST id wins a tie -- ids are handed out
			# in ascending order, so this is "the contact we have held longest",
			# which is also the sensible tactical answer.
			if s > best_score:
				best_score = s
				best = tid
		if best >= 0:
			if weapons.engage(i, best):
				assignments += 1


## How much this unit wants to shoot at this track, or -INF for "cannot".
##
## Everything read here comes off the TRACK: its believed position, its quality,
## its category, whether it is radiating. Nothing comes from the target entity.
func _score(unit: int, track: SimTrack) -> float:
	# A bearing with no range is not a firing solution. docs/09 §2: "do not
	# commit forces to a bearing" -- and certainly do not shoot down one.
	if track.bearing_only:
		return -INF
	var r_km := _range_km(unit, track)
	var usable := false
	for m in weapons.mounts_of(unit):
		var mount := m as SimWeaponCycle.Mount
		if mount.rounds == 0:
			continue
		var w := mount.weapon
		if not w.engages_category(track.category):
			continue
		# The GATE is the authority on whether a shot is legal, and it is the
		# same gate the player's ordered shot runs. Asking it here rather than
		# re-implementing its rules is what stops automatic fire and ordered
		# fire disagreeing about what is possible.
		if not SimWeaponGate.can_launch(w, track, r_km).allowed:
			continue
		usable = true
		break
	if not usable:
		return -INF

	# Prefer the better solution, then the nearer contact. Quality dominates by
	# a wide margin on purpose: a FIRE_CONTROL track at 6 km is a far better
	# proposition than a TRACK at 2 km, and picking the near one is how a
	# battery wastes its magazine on a plot it cannot hold.
	var quality_term := float(track.quality) * 1.0e6
	var confidence_term := track.confidence * 1.0e4
	return quality_term + confidence_term - r_km * 100.0


func _range_km(unit: int, track: SimTrack) -> float:
	var dx := track.pos_x - entities.pos_x[unit]
	var dy := track.pos_y - entities.pos_y[unit]
	var dz := track.pos_z - entities.pos_z[unit]
	return sqrt(dx * dx + dy * dy + dz * dz) / 1000.0


func describe() -> String:
	return "fire control: %d assignments, %d reassignments, %d holding fire" % [
		assignments, reassignments, _hold.size()]


func is_implemented() -> bool:
	return true
