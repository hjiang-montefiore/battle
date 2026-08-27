class_name SimCombatResolver
extends RefCounted
## The keystone: the place a round arriving finally has a consequence.
##
## docs/03 in one function. An arriving round is resolved as
##
##     1. mechanism    can this class of penetrator work against this armour at
##                     all? (SimPenetrator.is_immune -- a refusal, not a modifier)
##     2. threshold    penetration_mm > base_mm x effectiveness[type][class]?
##                     (SimArmor -- a threshold, deliberately. No partial credit)
##     3. behind armor WHAT did it hit? (SimBehindArmor -- components, not HP)
##     4. death        structure exhausted, or an ammunition detonation
##
## and nothing anywhere in that chain is a probability-of-kill stat. docs/10
## §2 requires Pk to be an OUTCOME: the round had to survive its flight, arrive
## at a facet chosen by geometry, and beat a threshold. What comes out the far
## end is a kill or it is not, and the log says which step decided it.
##
## ═══ WHY THIS IS SAFE TO RUN OVER A STRUCTURE-OF-ARRAYS WORLD ═══
##
## Killing a unit is the classic SoA hazard: if death removed a row, every index
## every other system is holding would shift by one and quietly start referring
## to a different unit. Projectiles in flight hold target indices. Tracks hold
## _truth_index. The movement planner, the economy and the AI's own-forces view
## all hold indices across ticks.
##
## The solution is the one SimEntities was already designed for and this class
## simply honours: DEATH NEVER REMOVES A ROW. entities.kill() sets alive = 0,
## zeroes velocity and path, and leaves the row exactly where it was. `_count`
## only ever grows and add() only ever appends, so an index is a permanent
## identity for the lifetime of the match. Everything else in the sim already
## gates on is_alive(), so a dead index answers "not alive" instead of becoming
## somebody else:
##
##   * the sensor solver skips dead entities, so the target stops being
##     observed, and SimTrackTable.decay_all() walks its track down the ladder
##     and drops it when cold -- tracks decay NATURALLY, exactly as docs/02
##     wants, with no death notification anywhere;
##   * SimMunitions._pre_flight_checks terminates in-flight rounds whose target
##     died with TARGET_LOST, so a corpse cannot keep leading a missile;
##   * indices_of_owner() and indices_of_faction() filter on alive.
##
## The cost is a row per unit ever built. At a few thousand units a match that
## is a few hundred kilobytes, which is the correct trade against a whole class
## of index-invalidation bugs that would be nearly impossible to reproduce.

var entities: SimEntities
var rng: SimRng

## Shared with SimDamage so the HUD sees one stream. Append-only, capped.
var combat_log: Array = []
var max_log: int = 200

var impacts_resolved: int = 0
var penetrations: int = 0
var defeats: int = 0
var impossible: int = 0
var kills: int = 0

## Per-unit blowout-panel override, when SimArmorScheme's per-generation default
## is wrong for a particular vehicle. Read by key only -- never iterated -- so
## it cannot introduce a Dictionary-order dependency.
var _blowout: Dictionary = {}

## unit -> [structure per second, seconds remaining]. Engine and fuel fires.
## Iterated in SORTED key order every tick; docs/06 forbids anything else.
var _burning: Dictionary = {}
const FIRE_SECONDS := 9.0
const FIRE_FRACTION_PER_S := 0.035

## unit -> nothing. Units whose crew are below full efficiency and recovering.
var _shaken: Dictionary = {}
## Fraction of full efficiency a crew regains per second once nothing more
## arrives. A shaken crew comes back; a wounded one does not come all the way.
const CREW_RECOVERY_PER_S := 0.035
## Crew casualties (the CREW component bit) cap what recovery can reach.
const CREW_CASUALTY_CAP := 0.55

## unit -> seconds since it died. Wrecks are bookkeeping, not entities: the
## solver already ignores dead units, so this exists to tell the presentation
## layer when the hulk may stop being drawn.
var _wrecks: Dictionary = {}
var wreck_linger_s: float = 45.0
var wrecks_expired: int = 0
var _expired: Array = []


func _init(store: SimEntities, seeded: SimRng) -> void:
	entities = store
	rng = seeded


# ═══════════════════════════════════════════════════════════════════════════
# RESOLUTION
# ═══════════════════════════════════════════════════════════════════════════

## Resolve one arriving round against one unit.
##
##   target          entity index, ground truth. docs/09 §1.4 -- "the projectile
##                   resolves against reality; the shooter never needed to know"
##   facet           SimTypes.Facet, already chosen by SimProjectile.impact_facet()
##                   from impact geometry. NEVER re-rolled here
##   damage_class    SimTypes.DamageClass
##   penetration_mm  RHA equivalent AT THE ARRIVAL RANGE, already run through
##                   SimArmor.penetration_at_range_mm() by the caller
##   blast_fraction  1.0 on a direct hit, tapering to 0 at the lethal radius
##   tandem          precursor charge: strips ERA and nothing else
func resolve(target: int, facet: int, damage_class: int, penetration_mm: float,
		blast_fraction: float = 1.0, tandem: bool = false) -> SimCombatOutcome:
	var o := SimCombatOutcome.new()
	o.facet = facet
	o.penetration_mm = penetration_mm

	if not entities.is_alive(target):
		o.reason = "target was already destroyed"
		return o

	impacts_resolved += 1
	o.resolved = true
	var model := entities.damage_model[target]
	var blast: float = clampf(blast_fraction, 0.0, 1.0)
	if blast <= 0.0:
		o.reason = "%s detonated outside its lethal radius" % \
			SimTypes.damage_class_name(damage_class)
		return o

	if model == SimTypes.DamageModel.ARMORED:
		return _resolve_armored(target, facet, damage_class, penetration_mm,
			blast, tandem, o)
	return _resolve_soft(target, facet, damage_class, penetration_mm, blast, o)


## The docs/03 facet x penetrator matrix, for the half of the game that carries
## armour. Everything that makes a generational gap a cliff happens here.
func _resolve_armored(target: int, facet: int, damage_class: int,
		penetration_mm: float, blast: float, tandem: bool,
		o: SimCombatOutcome) -> SimCombatOutcome:
	var base_mm := entities.armor_at(target, facet)
	var a_type := entities.armor_type_at(target, facet)
	# A round that arrives with no penetration figure at all still carries
	# fragments; SimPenetrator gives them a nominal RHA equivalence so one
	# comparison covers every class.
	var pen := SimPenetrator.effective_penetration_mm(damage_class, penetration_mm, blast)
	o.penetration_mm = pen
	o.verdict = SimPenetrator.verdict(pen, base_mm, a_type, damage_class, tandem)
	o.effective_mm = SimArmor.effective_mm(base_mm, a_type, damage_class, tandem)

	if o.verdict == SimPenetrator.Verdict.IMPOSSIBLE:
		impossible += 1
		o.reason = SimPenetrator.describe(pen, base_mm, a_type, damage_class, facet, tandem)
		_log(target, o.reason)
		return o

	if not SimPenetrator.penetrated(o.verdict):
		# docs/03: "defeated (spall, crew shock, no kill)". It takes NOTHING off
		# the structure pool. Subtracting here is precisely the slope docs/03
		# exists to avoid -- do it and a Gen 1 platoon eventually grinds down a
		# Gen 4 tank's glacis, and the entire epoch system collapses into
		# "newest wins by a margin".
		defeats += 1
		var nearness: float = pen / maxf(o.effective_mm, 1e-6)
		_shake_crew(target, SimBehindArmor.shock_multiplier(nearness))
		o.reason = SimPenetrator.describe(pen, base_mm, a_type, damage_class, facet, tandem)
		_log(target, o.reason)
		return o

	# ── through ──────────────────────────────────────────────────────────────
	penetrations += 1
	o.penetrated = true
	var overmatch := SimArmor.overmatch_ratio(pen, base_mm, a_type, damage_class, tandem)
	if base_mm <= 0.0:
		overmatch = 1.0
	var blowout: bool = _blowout.get(target,
		SimArmorScheme.default_blowout(entities.armor_class[target]))
	o.components_lost = SimBehindArmor.roll(rng, SimTypes.DamageModel.ARMORED,
		facet, overmatch, entities.crew_efficiency[target], blowout)
	_shake_crew(target, SimBehindArmor.penetration_shock_multiplier(overmatch))
	o.fire = SimBehindArmor.starts_fire(SimTypes.DamageModel.ARMORED, facet, overmatch)

	var bleed := entities.structure_max[target] \
		* SimPenetrator.armored_bleed_fraction(overmatch) * blast
	_apply(target, o, bleed, overmatch)
	o.reason = "%s -- %s" % [
		SimPenetrator.describe(pen, base_mm, a_type, damage_class, facet, tandem),
		_effect_phrase(o)]
	_log(target, o.reason)
	return o


## Aircraft, ships, trucks, radars and buildings. docs/03's closing section:
## the armour matrix "does not apply to modern warships or aircraft, which carry
## negligible armor. Their survivability is the layered soft-kill/hard-kill
## ladder in docs/02 §8.6 -- a sequence of chances to defeat the weapon BEFORE
## it arrives, rather than a chance to survive it on impact."
##
## So there is no facet resolution and no threshold to beat: by the time control
## reaches here the weapon has already beaten flares, chaff, notching, hard-kill
## APS and its own kinematics. What is left is how much of the airframe or the
## hull the warhead took out.
func _resolve_soft(target: int, facet: int, damage_class: int,
		penetration_mm: float, blast: float, o: SimCombatOutcome) -> SimCombatOutcome:
	var model := entities.damage_model[target]
	o.penetrated = true
	o.verdict = SimPenetrator.Verdict.OVERMATCHED
	o.effective_mm = 0.0
	o.penetration_mm = penetration_mm
	penetrations += 1

	# Nearness of the burst stands in for overmatch: a contact hit wrecks
	# something, a detonation at the edge of the lethal radius peppers it.
	var severity := blast
	var blowout: bool = _blowout.get(target, false)
	o.components_lost = SimBehindArmor.roll(rng, model, facet, severity,
		entities.crew_efficiency[target], blowout)
	_shake_crew(target, SimBehindArmor.penetration_shock_multiplier(severity))
	o.fire = SimBehindArmor.starts_fire(model, facet, severity)

	var bleed := entities.structure_max[target] \
		* SimPenetrator.soft_bleed_fraction(model, damage_class) * blast
	_apply(target, o, bleed, severity)
	o.reason = "%s %s on %s -- %s" % [
		SimTypes.damage_class_name(damage_class),
		"hit" if blast > 0.95 else "burst (%.0f%%)" % (blast * 100.0),
		entities.names[target], _effect_phrase(o)]
	_log(target, o.reason)
	return o


## Commit the behind-armor result: components, structure, fire, death.
func _apply(target: int, o: SimCombatOutcome, bleed: float, overmatch: float) -> void:
	# Catastrophic first. docs/03: "Ammunition detonation. Total loss." There is
	# no structure arithmetic to do -- the vehicle is gone.
	if o.components_lost & SimTypes.Component.CATASTROPHIC:
		entities.lose_component(target, SimTypes.Component.CATASTROPHIC)
		o.structure_lost = entities.structure[target]
		o.killed = true
		_kill(target, "ammunition detonation")
		return

	for c in [SimTypes.Component.MOBILITY, SimTypes.Component.FIREPOWER,
			SimTypes.Component.SENSORS, SimTypes.Component.CREW]:
		if o.components_lost & c:
			entities.lose_component(target, c)
	if o.components_lost & SimTypes.Component.CREW:
		# Crew casualties are permanent in a way shock is not: recovery can
		# never climb back past the cap.
		entities.crew_efficiency[target] = minf(entities.crew_efficiency[target],
			CREW_CASUALTY_CAP)

	if o.fire:
		_ignite(target)

	var before := entities.structure[target]
	o.killed = apply_structure(target, bleed, "penetration")
	o.structure_lost = before - entities.structure[target]


## Take `amount` off a unit's structure pool. The ONLY path to death that is not
## an ammunition detonation. Returns true if this call killed it.
func apply_structure(target: int, amount: float, cause: String = "") -> bool:
	if not entities.is_alive(target):
		return false
	if amount <= 0.0:
		return false
	entities.structure[target] = maxf(0.0, entities.structure[target] - amount)
	if entities.structure[target] <= 0.0:
		_kill(target, cause if cause != "" else "structural failure")
		return true
	return false


## Death. The single writer of entities.kill() in the whole simulation.
func _kill(target: int, cause: String) -> void:
	if not entities.is_alive(target):
		return
	entities.kill(target)
	kills += 1
	_burning.erase(target)
	_shaken.erase(target)
	# The row stays; only the liveness flag changes. See the class comment for
	# why that is what keeps every index in the rest of the sim valid.
	_wrecks[target] = 0.0
	_log(target, "%s DESTROYED (%s)" % [entities.names[target], cause])


func _ignite(target: int) -> void:
	_burning[target] = [entities.structure_max[target] * FIRE_FRACTION_PER_S,
		FIRE_SECONDS]


func _shake_crew(target: int, multiplier: float) -> void:
	if multiplier >= 1.0:
		return
	entities.crew_efficiency[target] = clampf(
		entities.crew_efficiency[target] * multiplier, 0.05, 1.0)
	_shaken[target] = true


func _effect_phrase(o: SimCombatOutcome) -> String:
	if o.killed:
		return "DESTROYED"
	var parts := PackedStringArray()
	if o.components_lost != SimTypes.Component.NONE:
		parts.append(SimTypes.component_names(o.components_lost) + " lost")
	if o.fire:
		parts.append("burning")
	if parts.is_empty():
		return "through, nothing vital in the way"
	return ", ".join(parts)


# ═══════════════════════════════════════════════════════════════════════════
# THE TICK
# ═══════════════════════════════════════════════════════════════════════════

## Slot 8b. Bleed burning units, recover shaken crews, expire wrecks. A no-op
## when nothing is damaged: every loop below is over a dictionary that is empty
## in peacetime, not over the whole entity array.
##
## Every one of those dictionaries is iterated in SORTED KEY ORDER. docs/06
## forbids relying on Dictionary order anywhere the order affects outcome, and
## the order two burning tanks die in absolutely does -- it decides which of
## them gets to fire one last round in slot 8c.
func step(dt: float) -> void:
	_expired.clear()
	if not _burning.is_empty():
		var burning: Array = _burning.keys()
		burning.sort()
		for u in burning:
			var s: Array = _burning[u]
			if not entities.is_alive(u):
				_burning.erase(u)
				continue
			apply_structure(u, s[0] * dt, "burned out")
			s[1] -= dt
			if s[1] <= 0.0:
				_burning.erase(u)

	if not _shaken.is_empty():
		var shaken: Array = _shaken.keys()
		shaken.sort()
		for u in shaken:
			if not entities.is_alive(u):
				_shaken.erase(u)
				continue
			var cap := 1.0
			if entities.has_component_loss(u, SimTypes.Component.CREW):
				cap = CREW_CASUALTY_CAP
			var e: float = minf(entities.crew_efficiency[u] + CREW_RECOVERY_PER_S * dt, cap)
			entities.crew_efficiency[u] = e
			if e >= cap - 1e-6:
				_shaken.erase(u)

	if not _wrecks.is_empty():
		var wrecks: Array = _wrecks.keys()
		wrecks.sort()
		for u in wrecks:
			var age: float = _wrecks[u] + dt
			if age >= wreck_linger_s:
				_wrecks.erase(u)
				wrecks_expired += 1
				_expired.append(u)
			else:
				_wrecks[u] = age


## Wrecks that finished burning out during the most recent step(). The
## presentation layer drains this to stop drawing a hulk. It is NOT a signal
## that the index became free -- indices are never reused.
func expired_wrecks() -> Array:
	return _expired


func is_burning(unit: int) -> bool:
	return _burning.has(unit)


func is_wreck(unit: int) -> bool:
	return _wrecks.has(unit)


# ═══════════════════════════════════════════════════════════════════════════
# CONFIGURATION
# ═══════════════════════════════════════════════════════════════════════════

## Override the per-generation blowout-panel default for one vehicle. docs/11:
## a carousel autoloader structurally cannot have blowout panels however modern
## the tank around it is, so the default from armor_class is a starting point
## and not a law.
func set_blowout_panels(unit: int, has_panels: bool) -> void:
	_blowout[unit] = has_panels


func has_blowout_panels(unit: int) -> bool:
	return _blowout.get(unit,
		SimArmorScheme.default_blowout(entities.armor_class[unit]))


# ── SAVE / LOAD (SimSave) ────────────────────────────────────────────────────
# Fires, shaken crews, wreck clocks, blowout overrides, counters and the rng
# stream. combat_log is cosmetic and dropped; _expired lives within one step.

func to_dict() -> Dictionary:
	var burning := {}
	var keys: Array = _burning.keys()
	keys.sort()
	for u in keys:
		var s: Array = _burning[u]
		burning[str(u)] = [SimSave.enc_float(s[0]), SimSave.enc_float(s[1])]
	return {
		"burning": burning,
		"shaken": SimSave.enc_ib(_shaken),
		"wrecks": SimSave.enc_if(_wrecks),
		"blowout": SimSave.enc_ib(_blowout),
		"wreck_linger_s": SimSave.enc_float(wreck_linger_s),
		"wrecks_expired": wrecks_expired,
		"counters": [impacts_resolved, penetrations, defeats, impossible, kills],
		"rng": str(rng.state()),
	}


func from_dict(d: Dictionary) -> void:
	_burning.clear()
	for k in (d["burning"] as Dictionary):
		var s: Array = d["burning"][k]
		_burning[int(String(k))] = [SimSave.dec_float(s[0]), SimSave.dec_float(s[1])]
	_shaken = SimSave.dec_ib(d["shaken"])
	_wrecks = SimSave.dec_if(d["wrecks"])
	_blowout = SimSave.dec_ib(d["blowout"])
	wreck_linger_s = SimSave.dec_float(d["wreck_linger_s"])
	wrecks_expired = int(d["wrecks_expired"])
	var c: Array = d["counters"]
	impacts_resolved = int(c[0]); penetrations = int(c[1]); defeats = int(c[2])
	impossible = int(c[3]); kills = int(c[4])
	rng.restore_state(int(String(d["rng"])))


func _log(target: int, line: String) -> void:
	combat_log.append("%-12s %s" % [entities.names[target], line])
	if combat_log.size() > max_log:
		combat_log.pop_front()


func recent_log(n := 12) -> String:
	var start: int = maxi(0, combat_log.size() - n)
	return "\n".join(combat_log.slice(start))


func describe() -> String:
	return "impacts %d: %d penetrated, %d defeated, %d impossible, %d killed" % [
		impacts_resolved, penetrations, defeats, impossible, kills]
