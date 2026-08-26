extends SceneTree
## Can anything in this game actually hit anything?
##
## An audit found that across the whole test suite, ZERO rounds had ever
## produced a HIT termination. Two causes, both now fixed:
##
##   1. Miss distance was sampled only at tick boundaries. A tank round leaves
##      the tube at 1700 m/s and the sim ticks at 20 Hz, so it advances 85 m
##      between samples -- a direct hit was invisible unless the target sat
##      within 1.5 m of a tick boundary. Tick rate WAS Pk. Fixed by measuring
##      against the segment the round actually swept (_segment_miss).
##
##   2. The hit threshold was a hard 1.5 m to the target's CENTRE, for every
##      target in the game. Against a warship that asks the round to pass
##      within 1.5 m of the exact middle of the hull. Fixed by giving targets a
##      physical extent (target_radius_m).
##
## docs/10 requires Pk to be an OUTCOME, not an input. That is only meaningful
## if the outcome can be "hit".
##
## This drives SimProjectile directly rather than going through SimMunitions,
## because the terminal resolution is what changed and SimMunitions needs a
## live sensor solver that has nothing to do with the question.
##
##   Godot --headless --path game --script sim/tests/test_terminal_hit.gd

# preload rather than relying on class_name globals: this test has to run in a
# throwaway project, because several Godot instances cannot share one project's
# import lock and the build agents hold it.
const MunitionDef := preload("res://sim/munitions/sim_munition_def.gd")
const Projectile := preload("res://sim/munitions/sim_projectile.gd")

const DT := 1.0 / 20.0

var _pass := 0
var _fail := 0


func _ok(what: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("    PASS  %s%s" % [what, "  " + detail if detail else ""])
	else:
		_fail += 1
		print("    FAIL  %s%s" % [what, "  " + detail if detail else ""])


## Fly one round from the origin at a stationary target, straight and true.
## `offset` throws it off axis so a miss can be produced deliberately.
func _fly(munition, range_m: float, extent_m: float,
		offset_m := 0.0) :
	# Launch from gun height, not from y=0. Terminator 2 is "the bottom, or the
	# ground", so a round that starts exactly ON the ground is under it after
	# one tick of gravity and terminates 84 m from the muzzle.
	const GUN_H := 2.4
	# SUPERELEVATION. A flat-fired round drops 0.5*g*t^2 over its flight and
	# buries itself short of the target -- at 1700 m/s over 1500 m that is 3.8 m
	# of drop against a 2.4 m gun height, so the round hits the dirt at 1190 m.
	# Real gunnery aims above the target by exactly this much, and a test that
	# does not is testing gravity rather than terminal resolution.
	# Take the muzzle speed from the round itself rather than from max_speed --
	# tank_apfsds() declares max_speed 1200 but leaves the tube at 1700, and
	# using the wrong one over-elevates by 3.8 m and misses high.
	var p = Projectile.new()
	p.launch(munition, 0.0, GUN_H, 0.0, range_m, GUN_H, offset_m, 0, 0, 1, -1)
	var muzzle := maxf(p.speed(), 1.0)
	var tof := range_m / muzzle
	var drop := 0.5 * 9.81 * tof * tof
	p.launch(munition, 0.0, GUN_H, 0.0, range_m, GUN_H + drop, offset_m, 0, 0, 1, -1)
	var t := 0.0
	while p.alive and t < 90.0:
		p.step(DT, range_m, GUN_H, offset_m, 0.0, 0.0, 0.0, true,
			range_m, GUN_H, 0.0, true, 400000.0, extent_m)
		t += DT
	return p


func _initialize() -> void:
	print("Terminal resolution: rounds must be able to hit")
	var apfsds = MunitionDef.tank_apfsds()

	# The classic case, and the one that was arithmetically impossible before:
	# 85 m of travel per tick measured against a 1.5 m threshold.
	var p = _fly(apfsds, 1500.0, 2.0)
	_ok("a direct-fire round terminates", not p.alive,
		MunitionDef.termination_name(p.termination))
	_ok("and it HITS a stationary tank at 1.5 km",
		p.termination == MunitionDef.Termination.HIT,
		"%s, miss %.2f m" % [p.termination_detail, p.miss_distance_m])

	# A ship is not a point. Passing 8 m off the centreline of a frigate is a
	# hit; the old hard 1.5 m called it a miss.
	var p2 = _fly(apfsds, 1500.0, 12.0, 8.0)
	_ok("a round inside a ship's beam counts as a hit",
		p2.termination == MunitionDef.Termination.HIT,
		"%s, miss %.2f m" % [p2.termination_detail, p2.miss_distance_m])

	# The same 8 m against a tank must NOT be a hit -- extent must discriminate,
	# not simply make everything easier.
	var p3 = _fly(apfsds, 1500.0, 2.0, 8.0)
	_ok("but the same 8 m against a TANK still misses",
		p3.termination != MunitionDef.Termination.HIT,
		"%s, miss %.2f m" % [p3.termination_detail, p3.miss_distance_m])

	# And a wild shot misses everything.
	var p4 = _fly(apfsds, 1500.0, 12.0, 120.0)
	_ok("a round thrown 120 m wide misses even a ship",
		p4.termination != MunitionDef.Termination.HIT,
		"%s, miss %.1f m" % [p4.termination_detail, p4.miss_distance_m])

	print("\n  %d passed, %d failed" % [_pass, _fail])
	print("  PASS" if _fail == 0 else "  FAIL")
	quit(0 if _fail == 0 else 1)


## Safety net. A parse or runtime error inside _initialize() skips quit() and
## leaves the SceneTree spinning with its stdout unflushed -- which looks
## exactly like a hang and hides the error that caused it. Returning true here
## guarantees the process exits after one iteration no matter what.
func _process(_delta: float) -> bool:
	return true
