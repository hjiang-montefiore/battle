extends SceneTree
## Oil fields: the thing on the map worth walking to.
##
## Asked during play: "where is oil and ore on the map". The honest answer was
## nowhere -- a derrick carried its extraction rate in its own stats and pumped
## it anywhere inside the build radius, so holding ground bought a player
## nothing at all. These are the rules that make the map matter.

var _pass := 0
var _fail := 0


func _initialize() -> void:
	print("\n  BATTLE -- oil fields")
	print("  " + "-".repeat(58))
	_suite_placement()
	_suite_layout()
	print("  " + "-".repeat(58))
	print("  %d passed, %d FAILED\n" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)


func _suite_placement() -> void:
	var w := SimWorld.new(3)
	w.use_accumulator = false
	w.terrain = SimArena.build(SimArena.SKIRMISH_VALLEY)
	w.movement.set_terrain(w.terrain)
	w.economy.add_player(0, 40000.0, 4, 5)
	w.economy.add_oil_field(400.0, 0.0)

	# A derrick needs a field, and the refusal has to SAY so.
	var d := w.economy.def_for(0, "oil_derrick")
	var why := w.economy.placement_problem(0, d, -3000.0, -3000.0)
	_ok("a derrick off the fields is refused, with a reason",
		why.contains("oil field"), why)
	_ok("and on a field it is allowed",
		w.economy.placement_problem(0, d, 400.0, 0.0) == "",
		w.economy.placement_problem(0, d, 400.0, 0.0))

	# One derrick per field: the second is refused, which is what makes a
	# field a finite thing worth taking rather than a place to stack.
	var first := w.economy.spawn_unit(0, "oil_derrick", 400.0, 0.0)
	_ok("the first derrick goes up", first >= 0)
	_ok("the field now reads as pumped", w.economy.derrick_on(0) == first)
	_ok("a second derrick on the same field is refused",
		w.economy.placement_problem(0, d, 420.0, 20.0).contains("already"),
		w.economy.placement_problem(0, d, 420.0, 20.0))

	# Killing the derrick frees the field, with no bookkeeping to fall out of
	# step: ownership is DERIVED from who is standing there.
	w.entities.kill(first)
	_ok("destroying it frees the field again", w.economy.derrick_on(0) == -1)
	_ok("and another can be built there", w.economy.placement_problem(0, d, 400.0, 0.0) == "")


func _suite_layout() -> void:
	var terrain := SimArena.build(SimArena.SKIRMISH_VALLEY)
	for count in [2, 3, 4]:
		var bases := SimArena.base_positions(terrain, count)
		var fields := SimArena.oil_fields(terrain, bases)
		_ok("%d players get fields at all" % count, fields.size() >= count,
			"%d field(s)" % fields.size())

		# Every field must be on dry land, or it is a field nobody can use.
		var wet := 0
		for f in fields:
			if terrain.is_water(f.x, f.y):
				wet += 1
		_ok("%d players: no field is under water" % count, wet == 0)

		# FAIRNESS, stated correctly. Counting fields by NEAREST base is the
		# wrong test: a contested field sits exactly equidistant between two
		# bases, so which one "gets" it is decided by a tie-break and the
		# counts come out [4,3,3,2] on a layout that is perfectly symmetric.
		#
		# What actually has to hold is that no seat has a shorter road to the
		# crude than another -- so compare each player's SORTED DISTANCES to
		# every field. Identical lists mean the map is a rotation of itself,
		# which is the only fairness that matters.
		var profiles: Array = []
		for b in range(count):
			var bp: Vector2 = bases[b]
			var ds: Array = []
			for f in fields:
				ds.append(snappedf((f - bp).length(), 25.0))
			ds.sort()
			profiles.append(ds)
		var same := true
		for b in range(1, count):
			if str(profiles[b]) != str(profiles[0]):
				same = false
		_ok("%d players: every seat has the same road to the crude" % count, same,
			"%d field(s), nearest %.0f m" % [fields.size(), profiles[0][0]])


func _ok(what: String, cond: bool, note := "") -> void:
	if cond:
		_pass += 1
		print("    PASS  %s%s" % [what, "  " + note if note != "" else ""])
	else:
		_fail += 1
		print("    FAIL  %s  %s" % [what, note])


func _process(_d: float) -> bool:
	return true
