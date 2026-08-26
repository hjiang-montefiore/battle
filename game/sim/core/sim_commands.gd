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
