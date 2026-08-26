class_name SimAiGroup
extends RefCounted
## A task group: some of the AI's own units, one objective, one state.
##
## Groups exist because docs/09 §2 makes COORDINATION a difficulty dial --
## "one axis at a time / two / simultaneous multi-axis with sensor cover" -- and
## an axis has to be a thing before it can be counted. SimSkill.simultaneous_axes()
## caps how many manoeuvre groups a given AI may run at once, so a Recruit
## really does attack down one road while a Warlord runs five.
##
## A group holds INDICES INTO ITS OWN ARMY and a TRACK ID. It never holds an
## enemy entity index, because it is never given one.

enum Role {
	MAIN,      ## the manoeuvre force -- an axis of attack
	SCREEN,    ## covers the base
	SCOUT,     ## sent at cues, never committed
	SENSOR,    ## radar, AEW, the picture itself
	SUPPORT,   ## supply, unarmed, keeps out of the way
}

enum State {
	FORMING,
	HOLDING,      ## in position, waiting for something worth acting on
	ADVANCING,    ## moving on an objective
	ENGAGING,     ## in contact
	SEARCHING,    ## no picture -- looking (docs/09 §1.5 blackout)
	WITHDRAWING,  ## losing, and pulling back
}

const ROLE_NAMES := {
	Role.MAIN: "main", Role.SCREEN: "screen", Role.SCOUT: "scout",
	Role.SENSOR: "sensor", Role.SUPPORT: "support",
}
const STATE_NAMES := {
	State.FORMING: "forming", State.HOLDING: "holding",
	State.ADVANCING: "advancing", State.ENGAGING: "engaging",
	State.SEARCHING: "searching", State.WITHDRAWING: "withdrawing",
}

var id: int = 0
var role: int = Role.MAIN
var state: int = State.FORMING
## Own unit indices, ASCENDING. Kept sorted so every derived decision -- who is
## the leader, who takes which formation slot -- is stable across runs.
var members := PackedInt32Array()

## The contact this group is acting on, as a TRACK ID. -1 when it is moving on
## a remembered position or searching.
var objective_track: int = -1
var obj_x: float = 0.0
var obj_z: float = 0.0
var has_objective: bool = false

## Sum of member structure fractions, and the high-water mark. The ratio is the
## retreat trigger: docs/09 §5 wants a doctrine to "retreat when losing", and
## losing is measurable as strength against the strength you started with.
var strength: float = 0.0
var peak_strength: float = 0.0

var last_order_s: float = -1.0e9
var formed_s: float = 0.0


func add_member(i: int) -> void:
	if members.has(i):
		return
	members.append(i)
	members.sort()


func remove_member(i: int) -> void:
	var k := members.find(i)
	if k >= 0:
		members.remove_at(k)


func size() -> int:
	return members.size()


func is_empty() -> bool:
	return members.is_empty()


## 0 when wiped out, 1 when at the strength it formed with. Above 1 after
## reinforcement, which is why it is clamped nowhere.
func strength_ratio() -> float:
	if peak_strength <= 0.0:
		return 0.0
	return strength / peak_strength


func set_objective_track(track_id: int, x: float, z: float) -> void:
	objective_track = track_id
	obj_x = x
	obj_z = z
	has_objective = true


func set_objective_point(x: float, z: float) -> void:
	objective_track = -1
	obj_x = x
	obj_z = z
	has_objective = true


func clear_objective() -> void:
	objective_track = -1
	has_objective = false


func describe() -> String:
	return "G%d %-7s %-11s %d unit(s)  str %.2f/%.2f  obj %s" % [
		id, ROLE_NAMES.get(role, "?"), STATE_NAMES.get(state, "?"),
		members.size(), strength, peak_strength,
		("TK%d" % objective_track) if objective_track >= 0
			else ("(%.0f, %.0f)" % [obj_x, obj_z] if has_objective else "none")]
