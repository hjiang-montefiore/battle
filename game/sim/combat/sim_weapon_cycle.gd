class_name SimWeaponCycle
extends RefCounted
## Slot 8c: the weapon cycle. Reload timers, the docs/02 §5 gate, and the launch.
##
## This is the half of combat that decides whether a round is ever FIRED;
## SimCombatResolver is the half that decides what happens when it arrives.
## They are separate because they answer different questions from different
## information: the weapon cycle may only look at its own faction's TRACK
## TABLE -- the same hypothesis a human player is looking at -- while the
## resolver looks at ground truth, because a projectile resolves against reality
## whatever anybody believed (docs/09 §1.4).
##
## THE ENGAGEMENT ORDER NAMES A TRACK, NOT A UNIT. SimCommandQueue.attack_track
## carries a track id, and so does everything here. That is what makes docs/09's
## no-cheating rule structural rather than aspirational: the AI issues the same
## order through the same queue as the mouse does, and neither can name an
## entity index. The track is resolved to a truth index in exactly one place --
## _truth_of() -- which is privileged sim bookkeeping the round needs in order
## to fly, and which no caller of this class can reach.
##
## WEAPON LOADOUTS LIVE HERE, NOT IN SimEntities. docs/06 keeps the entity
## arrays to the fields the sensor solve sweeps every tick; a weapon is a small
## object with a reload timer and an ammunition type, touched only when its
## owner is actually shooting. So mounts hang off a side table keyed by entity
## index, and -- because an index is a permanent identity that death never
## invalidates -- that table stays correct for the whole match.

class Mount extends RefCounted:
	var weapon: SimWeaponDef
	var munition: SimMunitionDef
	## Seconds between rounds at FULL crew efficiency. A shaken or wounded crew
	## reloads slower -- docs/03's "degraded rate of fire" -- which is applied
	## at fire time rather than baked in here.
	var reload_s: float = 8.0
	var timer: float = 0.0
	## -1 = unlimited. A finite magazine is what makes a supply line matter.
	var rounds: int = -1
	var fired: int = 0

	func ready() -> bool:
		return timer <= 0.0 and rounds != 0

	func describe() -> String:
		return "%s / %s" % [weapon.name, munition.name]


var entities: SimEntities
var munitions: SimMunitions
var solver: SimSensorSolver
var rng: SimRng

var _mounts: Dictionary = {}      ## unit -> Array[Mount]
var _engaging: Dictionary = {}    ## unit -> track id

var shots_fired: int = 0
var refusals: int = 0
var last_refusal: String = ""
## Every refusal carries a reason, because docs/02 §9 says a shot refused for
## invisible reasons reads as a bug. Capped, same shape as the other logs.
var gate_log: Array = []
var max_log: int = 120


func _init(store: SimEntities, munition_pool: SimMunitions,
		sensor_solver: SimSensorSolver, seeded: SimRng) -> void:
	entities = store
	munitions = munition_pool
	solver = sensor_solver
	rng = seeded


## Give a unit a weapon. Called at spawn, by whoever spawns the unit.
func arm(unit: int, weapon: SimWeaponDef, munition: SimMunitionDef,
		reload_s := 8.0, rounds := -1) -> Mount:
	var m := Mount.new()
	m.weapon = weapon
	m.munition = munition
	m.reload_s = reload_s
	m.rounds = rounds
	if not _mounts.has(unit):
		_mounts[unit] = []
	(_mounts[unit] as Array).append(m)
	return m


func mounts_of(unit: int) -> Array:
	return _mounts.get(unit, [])


func is_armed(unit: int) -> bool:
	return not mounts_of(unit).is_empty()


## SimTypes.OrderKind.ATTACK_TRACK. Returns false when the order cannot change
## anything, which is what SimWorld._command_slot counts as a rejection.
func engage(unit: int, track_id: int) -> bool:
	if not entities.is_alive(unit):
		return false
	if not is_armed(unit):
		return false
	if not entities.can_fire(unit):
		return false
	var table := solver.table_for(entities.faction[unit])
	if table.get_track(track_id) == null:
		# You cannot order a shot at a contact your faction does not hold. This
		# is the same refusal for the player and the AI, from the same table.
		return false
	_engaging[unit] = track_id
	return true


func disengage(unit: int) -> void:
	_engaging.erase(unit)


func is_engaging(unit: int) -> bool:
	return _engaging.has(unit)


func engagement_of(unit: int) -> int:
	return _engaging.get(unit, -1)


## Slot 8c, every simulation tick. AFTER damage, so a unit killed this tick does
## not get to fire; AFTER munitions, so a round fired now begins its flight on
## the next tick with a full dt rather than a partial one.
##
## Units are stepped in ASCENDING INDEX ORDER. Two units racing for the last
## interceptor in a target's APS must resolve in a defined order or the replay
## desyncs, and Dictionary key order is not one (docs/06).
func step(dt: float) -> void:
	if _mounts.is_empty():
		return
	var units: Array = _mounts.keys()
	units.sort()
	for u in units:
		var mounts: Array = _mounts[u]
		for m in mounts:
			var mount := m as Mount
			if mount.timer > 0.0:
				mount.timer = maxf(0.0, mount.timer - dt)
		if not entities.is_alive(u):
			_engaging.erase(u)
			continue
		if not _engaging.has(u):
			continue
		_service(u, mounts)


func _service(unit: int, mounts: Array) -> void:
	var track_id: int = _engaging[unit]
	var table := solver.table_for(entities.faction[unit])
	var track := table.get_track(track_id)
	if track == null:
		# The track went cold and was dropped. The order dies with it -- the
		# unit does not fall back on ground truth, because it never had any.
		_engaging.erase(unit)
		return

	# The mechanical half of "may I shoot?" -- docs/03's firepower kill.
	if not entities.can_fire(unit):
		_refuse(unit, "firepower disabled")
		return

	# docs/03's most valuable row: "the unit is alive and blind. It drops to TQ1
	# and can no longer engage anything at range." A blinded vehicle can still
	# shoot at what somebody else is holding for it -- that is what a datalink
	# is for -- but it can no longer produce a firing solution of its own.
	var blind := not entities.sensors_intact(unit)

	for m in mounts:
		var mount := m as Mount
		if not mount.ready():
			continue
		if blind and not _network_guided(mount.weapon.guidance):
			_refuse(unit, "optics destroyed -- no fire-control solution")
			continue
		# Range comes from the TRACK's believed position, not from the target's
		# real one. A stale track is engaged at the wrong range and the round
		# is aimed at where the picture said -- which is how a bad picture
		# becomes a miss instead of a hidden accuracy penalty.
		var r_km := _track_range_km(unit, track)
		var gate := SimWeaponGate.can_launch(mount.weapon, track, r_km)
		if not gate.allowed:
			_refuse(unit, gate.reason)
			continue
		var truth := _truth_of(track)
		if truth < 0:
			# The picture holds a track on something that no longer exists. The
			# order is left standing; the track will decay on its own.
			_refuse(unit, "contact no longer present")
			continue
		if munitions.fire(mount.munition, unit, truth, track) == null:
			_refuse(unit, "no projectile slot available")
			continue
		mount.timer = _reload_seconds(unit, mount)
		mount.fired += 1
		if mount.rounds > 0:
			mount.rounds -= 1
		shots_fired += 1
		_note("%s fires %s at track %d (%.1f km) -- %s" % [
			entities.names[unit], mount.munition.name, track.track_id,
			r_km, gate.reason])


## docs/03: crew casualties degrade rate of fire. A crew at half efficiency
## takes twice as long between rounds, which is a real and legible consequence
## of surviving a hit rather than a hidden stat.
func _reload_seconds(unit: int, mount: Mount) -> float:
	var eff: float = clampf(entities.crew_efficiency[unit], 0.2, 1.0)
	return mount.reload_s / eff


## Guidance modes that fly on somebody else's picture, and therefore still work
## when the shooter's own optics are gone.
func _network_guided(guidance: int) -> bool:
	return guidance == SimTypes.Guidance.COMMAND_LINK \
		or guidance == SimTypes.Guidance.GNSS_INS


func _track_range_km(unit: int, track: SimTrack) -> float:
	var dx := track.pos_x - entities.pos_x[unit]
	var dy := track.pos_y - entities.pos_y[unit]
	var dz := track.pos_z - entities.pos_z[unit]
	return sqrt(dx * dx + dy * dy + dz * dz) / 1000.0


## The ONE place a track becomes an entity index, and it is deliberately
## private. SimTrack._truth_index is sim-internal bookkeeping (see its comment
## in sim_track.gd); the projectile needs it because a round in flight resolves
## against reality. Nothing that decides anything -- not this class's gate, not
## the AI, not the UI -- may call it.
func _truth_of(track: SimTrack) -> int:
	var t: int = track._truth_index
	if t < 0 or not entities.is_alive(t):
		return -1
	return t


func _refuse(unit: int, why: String) -> void:
	refusals += 1
	last_refusal = why
	_note("%s holds fire -- %s" % [entities.names[unit], why])


func _note(line: String) -> void:
	gate_log.append(line)
	if gate_log.size() > max_log:
		gate_log.pop_front()


func recent_log(n := 12) -> String:
	var start: int = maxi(0, gate_log.size() - n)
	return "\n".join(gate_log.slice(start))


func is_implemented() -> bool:
	return true
