extends SceneTree
## The arena-side contract that lets naval scenarios work on coastal_shelf.
##
##   Godot --headless --path game --script sim/tests/test_scenario_coastal_water.gd
##
## The 39-cell scenario sweep found north_atlantic:coastal_shelf dead at zero
## shots partly because the +X base of a two-player match sat ~8 km from the
## nearest shoreline: even an AI that builds naval yards has no water to put
## one on from that side. sim_arena.gd now carves a southern arm connected to
## the western bay. This test pins the geometry so a later terrain tweak
## cannot silently re-break it:
##
##   1. every base slot for 2-4 players is DRY, including the ~170 m
##      BASE_LAYOUT footprint around it;
##   2. every base slot of the two-player match has water INSIDE its own build
##      radius (the HQ's 340 m is the roster's largest) -- the build-radius
##      rule in SimEconomy.placement_problem makes a naval yard, which must
##      stand ON water, legal only there. Water further away might as well
##      not exist;
##   3. the wet cells form ONE connected body, so fleets from the two shores
##      can meet (two disconnected ponds would be a new failure mode);
##   4. the north_atlantic scenario still STARTS on coastal_shelf, and a
##      naval yard actually GOES UP for both players when ordered at a legal
##      site -- the full command -> economy -> placement path, everything
##      short of the AI deciding to order it.
##
## Deterministic: fixed seeds only (arena default 20260826, setup default),
## no randf, no Time.*.

var _exit := 1
var _fails := 0


func _initialize() -> void:
	var t := SimArena.build("coastal_shelf")
	_check(t != null, "coastal_shelf builds")
	if t == null:
		return

	# 1. Base slots dry, footprint included.
	for count in [2, 3, 4]:
		var bases := SimArena.base_positions(t, count)
		_check(bases.size() == count, "%d base slots for %d players" % [
			bases.size(), count])
		for i in range(bases.size()):
			var b: Vector2 = bases[i]
			var wet := 0
			for off in [Vector2(0, 0), Vector2(170, 0), Vector2(-170, 0),
					Vector2(0, 170), Vector2(0, -170), Vector2(170, 170),
					Vector2(-170, -170), Vector2(170, -170), Vector2(-170, 170)]:
				if t.is_water(b.x + off.x, b.y + off.y):
					wet += 1
			_check(wet == 0,
				"players=%d base %d at (%.0f, %.0f) dry incl. footprint (%d/9 wet)" % [
					count, i, b.x, b.y, wet])

	# 2. Both two-player bases have water inside the HQ's 340 m build radius.
	var bases2 := SimArena.base_positions(t, 2)
	for i in range(bases2.size()):
		var b: Vector2 = bases2[i]
		var d := _water_distance(t, b, 340.0)
		_check(d >= 0.0,
			"base %d at (%.0f, %.0f): water inside the 340 m build radius (%s m)" % [
				i, b.x, b.y, ("%.0f" % d) if d >= 0.0 else ">340"])

	# 3. One connected sea.
	var parts := _wet_components(t)
	_check(parts.size() >= 1, "arena has water (%d wet regions)" % parts.size())
	_check(parts.size() == 1,
		"all water is ONE connected body (found %d regions, sizes %s)" % [
			parts.size(), str(parts)])

	# 4. The naval scenario starts here, and a naval yard can actually be
	# built by both players. This proves the whole non-AI half of the naval
	# stall fix: command -> authorisation -> economy -> placement -> entity.
	var setup := SimMatchSetup.scenario("north_atlantic")
	var m := SimMatch.start(setup, "coastal_shelf", true)
	var probs := m.problems()
	_check(probs.is_empty(), "north_atlantic starts on coastal_shelf (%s)" % [
		"; ".join(probs) if not probs.is_empty() else "no problems"])
	if probs.is_empty():
		for pid in range(setup.players.size()):
			_check_yard_goes_up(m, pid)

	if _fails == 0:
		print("test_scenario_coastal_water: ALL OK")
		_exit = 0
	else:
		print("test_scenario_coastal_water: %d FAILED" % _fails)


## Find a legal naval yard site near this player's base (wet, clear of the
## base structures, inside the build radius) and order it built through the
## real command queue; the yard must exist as an entity afterwards.
func _check_yard_goes_up(m: SimMatch, pid: int) -> void:
	var eco := m.world.economy
	var d := eco.def_for(pid, "naval_yard")
	_check(d != null, "p%d resolves a naval_yard def" % pid)
	if d == null:
		return
	var base: Vector2 = m.base_position(pid)
	var t: SimTerrain = m.world.terrain
	var site := Vector2(INF, INF)
	var r := 180.0
	while r <= 340.0 and not is_finite(site.x):
		for k in range(32):
			var a := TAU * float(k) / 32.0
			var x := base.x + cos(a) * r
			var z := base.y + sin(a) * r
			if not t.is_water(x, z):
				continue
			if eco.placement_problem(pid, d, x, z) == "":
				site = Vector2(x, z)
				break
		r += 20.0
	_check(is_finite(site.x),
		"p%d has a LEGAL naval yard site inside the build radius" % pid)
	if not is_finite(site.x):
		return
	var before: int = m.own_units(pid).size()
	m.world.commands.build(pid, "naval_yard", site.x, site.y)
	m.run_ticks(1)
	var after: int = m.own_units(pid).size()
	_check(after == before + 1,
		"p%d naval yard GOES UP at (%.0f, %.0f): %d -> %d entities" % [
			pid, site.x, site.y, before, after])


func _check(ok: bool, what: String) -> void:
	print("  %s  %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		_fails += 1


## Distance from `from` to the nearest water within `max_r` metres, or -1.
## Fixed 100 m ring steps and a fixed 32-point compass: deterministic.
func _water_distance(t: SimTerrain, from: Vector2, max_r: float) -> float:
	if t.is_water(from.x, from.y):
		return 0.0
	var r := 100.0
	while r <= max_r:
		for k in range(32):
			var a := TAU * float(k) / 32.0
			if t.is_water(from.x + cos(a) * r, from.y + sin(a) * r):
				return r
		r += 100.0
	return -1.0


## Sizes of the 4-connected components of wet cells, sampled at cell centres.
func _wet_components(t: SimTerrain) -> Array:
	var w := t.cells_x
	var h := t.cells_z
	var wet := PackedByteArray()
	wet.resize(w * h)
	for cz in range(h):
		for cx in range(w):
			var x := (float(cx) + 0.5) * t.cell_size_m - t.extent_x_m() * 0.5
			var z := (float(cz) + 0.5) * t.cell_size_m - t.extent_z_m() * 0.5
			wet[cz * w + cx] = 1 if t.is_water(x, z) else 0
	var seen := PackedByteArray()
	seen.resize(w * h)
	var sizes: Array = []
	for start in range(w * h):
		if wet[start] == 0 or seen[start] == 1:
			continue
		var size := 0
		var queue := [start]
		seen[start] = 1
		while not queue.is_empty():
			var i: int = queue.pop_back()
			size += 1
			var cx := i % w
			var cz := i / w
			for n in [[cx - 1, cz], [cx + 1, cz], [cx, cz - 1], [cx, cz + 1]]:
				var nx: int = n[0]
				var nz: int = n[1]
				if nx < 0 or nx >= w or nz < 0 or nz >= h:
					continue
				var j := nz * w + nx
				if wet[j] == 1 and seen[j] == 0:
					seen[j] = 1
					queue.append(j)
		sizes.append(size)
	return sizes


## A parse or runtime error inside _initialize() would otherwise leave the
## SceneTree idle with stdout buffered; this guarantees an exit either way.
func _process(_d: float) -> bool:
	quit(_exit)
	return true
