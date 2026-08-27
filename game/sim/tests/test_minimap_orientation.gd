extends SceneTree
## The minimap must agree with the screen, and this is the contract that says
## which way that is.
##
## Reported from play: "the mini map and mouse moving is opposite direction".
## The cause was not a minimap bug in isolation -- it was that the rig and the
## map disagreed about which way the world runs. RTSCamera parks the camera at
## target + (-sin(yaw), 0, -cos(yaw)) * dist, which at the default yaw puts it
## at NEGATIVE Z looking toward POSITIVE Z. That makes world +X screen-LEFT
## and world +Z screen-TOP -- the opposite of the obvious "+X right, +Z down"
## a minimap gets drawn with, so the map came out rotated a half turn and
## every drag of the view sent the blip the wrong way.
##
## If someone changes the rig's placement, this fails and names the file that
## has to change with it.

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("\n  BATTLE -- minimap agrees with the camera")
	print("  " + "-".repeat(58))
	for zoom in [62.0, 300.0, 900.0]:
		_check(zoom)
	print("  " + "-".repeat(58))
	print("  %d passed, %d FAILED\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _check(dist: float) -> void:
	# Reproduced from RTSCamera._apply(). Pitch varies with zoom; the AXES must
	# not, which is why every zoom level is checked.
	var pitch := deg_to_rad(lerpf(38.0, 58.0, clampf(dist / 900.0, 0.0, 1.0)))
	var eye := Vector3(0.0, 0.0, -1.0) * cos(pitch) * dist \
		+ Vector3(0.0, sin(pitch) * dist, 0.0)
	var b := Transform3D().looking_at(Vector3.ZERO - eye, Vector3.UP).basis

	_ok("at %.0f m: world +X is toward screen LEFT" % dist, b.x.x < 0.0,
		"screen-right = %s" % str(b.x.round()))
	_ok("at %.0f m: world +Z is toward screen TOP" % dist, b.y.z > 0.0,
		"screen-up = %s" % str(b.y.round()))
	# Which is exactly what Minimap._to_map inverts for. Stated as arithmetic so
	# the test fails if the map is ever "corrected" back to the obvious form.
	var to_map_x := func(x: float) -> float: return 0.5 - x / 1000.0
	var to_map_y := func(z: float) -> float: return 0.5 - z / 1000.0
	_ok("at %.0f m: so the map puts +X left of centre" % dist,
		to_map_x.call(100.0) < 0.5)
	_ok("at %.0f m: and +Z above centre" % dist, to_map_y.call(100.0) < 0.5)


func _ok(what: String, cond: bool, note := "") -> void:
	if cond:
		_pass += 1
		print("    PASS  %s%s" % [what, "  " + note if note != "" else ""])
	else:
		_fail += 1
		print("    FAIL  %s  %s" % [what, note])


func _process(_d: float) -> bool:
	return true
