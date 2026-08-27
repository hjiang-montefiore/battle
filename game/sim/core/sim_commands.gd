class_name SimCommandQueue
extends RefCounted
## The ONE way anything outside the simulation changes it. docs/06: "Godot's job
## is to render this and submit commands to it; that is the whole contract."
##
## Both the human player's mouse and every AI director push commands here. That
## symmetry is not tidiness -- it is docs/09 §1 being enforced structurally. An
## AI that can only express itself as a SimCommand cannot reach past the queue
## and write an entity, and cannot issue an order it could not have issued from
## the same information a player has.
##
## Note what an ATTACK order carries: a TRACK ID, never an entity index
## (docs/09 §1.3). A track is a hypothesis, not a pointer. This is also what
## makes ordering an attack on a chaff bloom expressible, for the player and the
## AI alike.
##
## DETERMINISM. Commands execute in submission order, and submission order is a
## plain Array -- never a Dictionary. Two runs that submit the same commands in
## the same order execute them identically.


class Command extends RefCounted:
	var kind: int = SimTypes.OrderKind.NONE
	var issuer: int = -1        ## player id that issued it
	var unit: int = -1          ## the unit being ordered. Must be owned by issuer
	var x: float = 0.0          ## world metres
	var z: float = 0.0
	var track_id: int = -1      ## ATTACK_TRACK: opaque, issuer's own table only
	var value: int = 0          ## SET_EMCON / SET_MOVE_STATE / CANCEL slot
	var key: String = ""        ## PRODUCE / BUILD: unit or structure def key
	var queued: bool = false    ## true = append to the unit's order queue
	## LOAD: the transport being boarded. UNLOAD: one passenger, -1 = all.
	## A SECOND unit index on the command; the ownership gate in
	## SimWorld._command_is_authorised() checks it too -- boarding an enemy
	## APC must be as impossible as ordering an enemy tank.
	var target_unit: int = -1
	## PATROL: the loop, as flat [x0, z0, x1, z1, ...] world metres.
	## Duplicated at submit so a caller mutating its own array afterwards
	## cannot change a command already sitting in the queue.
	var points := PackedFloat32Array()
	var radius_m: float = 0.0   ## SORTIE_PATROL: orbit radius, metres

	func _to_string() -> String:
		return "cmd(kind=%d issuer=%d unit=%d at %.0f,%.0f track=%d %s)" % [
			kind, issuer, unit, x, z, track_id, key]


var _pending: Array = []        ## Array[Command], submission order
var submitted: int = 0
var executed: int = 0
var rejected: int = 0


## Push a command. Returns it so a caller can inspect what it built. The queue
## does NOT validate ownership here -- validation happens at drain time, against
## the entity store, because only the sim knows who owns what.
func submit(c: Command) -> Command:
	_pending.append(c)
	submitted += 1
	return c


func move(issuer: int, unit: int, x: float, z: float, queued := false) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.MOVE
	c.issuer = issuer; c.unit = unit; c.x = x; c.z = z; c.queued = queued
	return submit(c)


## Advance to a world point ready to fight: SimMovement's ATTACK_MOVE order,
## reached through the queue exactly the way a plain MOVE is.
func attack_move(issuer: int, unit: int, x: float, z: float, queued := false) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.ATTACK_MOVE
	c.issuer = issuer; c.unit = unit; c.x = x; c.z = z; c.queued = queued
	return submit(c)


func stop(issuer: int, unit: int) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.STOP
	c.issuer = issuer; c.unit = unit
	return submit(c)


## Engage a track the issuer's own faction holds. The sim resolves the track to
## an aim point at fire time; the issuer never learns what is really there.
func attack_track(issuer: int, unit: int, track_id: int) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.ATTACK_TRACK
	c.issuer = issuer; c.unit = unit; c.track_id = track_id
	return submit(c)


func set_emcon(issuer: int, unit: int, emcon_state: int) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.SET_EMCON
	c.issuer = issuer; c.unit = unit; c.value = emcon_state
	return submit(c)


func set_move_state(issuer: int, unit: int, state: int) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.SET_MOVE_STATE
	c.issuer = issuer; c.unit = unit; c.value = state
	return submit(c)


func produce(issuer: int, structure_unit: int, def_key: String) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.PRODUCE
	c.issuer = issuer; c.unit = structure_unit; c.key = def_key
	return submit(c)


func build(issuer: int, def_key: String, x: float, z: float) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.BUILD
	c.issuer = issuer; c.key = def_key; c.x = x; c.z = z
	return submit(c)


## Loop a list of world points until told otherwise. `p_points` is flat
## [x0, z0, x1, z1, ...] metres; one point is a legal loiter-here. The first
## point is mirrored into x/z so anything that renders or logs a command's
## destination keeps working without knowing about point lists.
func patrol(issuer: int, unit: int, p_points: PackedFloat32Array,
		queued := false) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.PATROL
	c.issuer = issuer; c.unit = unit; c.queued = queued
	c.points = p_points.duplicate()
	if c.points.size() >= 2:
		c.x = c.points[0]; c.z = c.points[1]
	return submit(c)


## `unit` boards `transport`. BOTH must belong to the issuer -- the second
## index is validated at drain time exactly like the first.
func load_cargo(issuer: int, unit: int, transport: int) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.LOAD
	c.issuer = issuer; c.unit = unit; c.target_unit = transport
	return submit(c)


## `transport` disgorges where it stands. `passenger` = one specific unit
## aboard, or -1 for everything. There is no destination on this order on
## purpose: "unload over there" is a MOVE then an UNLOAD, which the UI can
## queue; the sim keeps the primitive atomic.
func unload_cargo(issuer: int, transport: int, passenger := -1) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.UNLOAD
	c.issuer = issuer; c.unit = transport; c.target_unit = passenger
	return submit(c)


## Toggle a deployable in place: MOBILE begins deploying, DEPLOYED begins
## undeploying, and a mid-transition order is the deploy system's to accept or
## refuse. One order kind for both directions because the player's gesture is
## one key.
func deploy(issuer: int, unit: int) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.DEPLOY
	c.issuer = issuer; c.unit = unit
	return submit(c)


## Aircraft: sortie from home_base, deliver at the point, and come home on the
## docs/04 RTB rule. The sim flies the whole loop; the player owns one click.
func sortie_strike(issuer: int, unit: int, x: float, z: float) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.SORTIE_STRIKE
	c.issuer = issuer; c.unit = unit; c.x = x; c.z = z
	return submit(c)


## Aircraft: sortie and orbit the point at `radius_m` until fuel, damage or a
## new order ends the station. The RTB rule, not a duration, decides when the
## orbit is over -- that is the docs/04 contract.
func sortie_patrol(issuer: int, unit: int, x: float, z: float,
		radius_m := 4000.0) -> Command:
	var c := Command.new()
	c.kind = SimTypes.OrderKind.SORTIE_PATROL
	c.issuer = issuer; c.unit = unit; c.x = x; c.z = z; c.radius_m = radius_m
	return submit(c)


func size() -> int:
	return _pending.size()


## Take everything pending, in submission order, and empty the queue. Called
## once per tick by SimWorld, at the start of the movement slot.
func drain() -> Array:
	var out := _pending
	_pending = []
	return out


func note_executed() -> void:
	executed += 1


func note_rejected() -> void:
	rejected += 1


func clear() -> void:
	_pending.clear()


# ── SAVE / LOAD (SimSave). The queue is drained every tick, so a between-tick
# save normally finds it empty -- but a save taken after the UI submitted and
# before the tick executed must not eat those orders.

func to_dict() -> Dictionary:
	var pending: Array = []
	for c in _pending:
		pending.append(SimSave.enc_props(c))
	return {
		"pending": pending,
		"submitted": submitted,
		"executed": executed,
		"rejected": rejected,
	}


func from_dict(d: Dictionary) -> void:
	_pending.clear()
	for cd in (d["pending"] as Array):
		var c := Command.new()
		SimSave.dec_props(c, cd)
		_pending.append(c)
	submitted = int(d["submitted"])
	executed = int(d["executed"])
	rejected = int(d["rejected"])
