extends SceneTree
## Tests for the map file format: authored maps as replayable op lists.
##
##     godot --path game --headless --script res://sim/tests/test_map_file.gd
##
## What is at stake here is the contract the format makes:
##   * DETERMINISM -- the same file produces a byte-identical heightfield,
##     every build, which is what lets two machines play the same map;
##   * REFUSAL -- a version or an op this build does not speak refuses the
##     whole file rather than building different ground silently;
##   * VALIDITY -- a base or a deposit the arena's own suitability rules
##     would refuse is refused by the format, with a reason;
##   * PLAYABILITY -- a SimMatch constructed over a loaded terrain runs the
##     whole stack: deployment, movement through an authored pass, the sensor
##     picture, combat, and a victory. The arena hook does not exist yet
##     (sim_arena.gd is owned elsewhere), so this suite wires the match the
##     way SimMatch._begin() does and proves the map needs nothing else.

var _passed := 0
var _failed := 0

const FIRST_LIGHT := "first_light"


func _init() -> void:
	print("")
	print("  BATTLE -- map file tests (format, determinism, validity, play)")
	print("  " + "-".repeat(66))

	_suite_format()
	_suite_determinism()
	_suite_refusal()
	_suite_ops()
	_suite_validity()
	_suite_first_light_design()
	_suite_playable()

	print("  " + "-".repeat(66))
	if _failed == 0:
		print("  %d passed, 0 failed" % _passed)
	else:
		print("  %d passed, %d FAILED" % [_passed, _failed])
	print("")
	quit(1 if _failed > 0 else 0)


func _suite(name: String) -> void:
	print("")
	print("  " + name)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		_passed += 1
		print("    PASS  %s%s" % [label, ("  " + detail) if detail else ""])
	else:
		_failed += 1
		print("    FAIL  %s%s" % [label, ("  " + detail) if detail else ""])


func _tmp(file: String) -> String:
	var dir := ProjectSettings.globalize_path("user://map_file_tests/")
	DirAccess.make_dir_recursive_absolute(dir)
	return dir + file


# ═══════════════════════════════════════════════════════════════════════════
# 1. THE FORMAT
# ═══════════════════════════════════════════════════════════════════════════

func _suite_format() -> void:
	_suite("data/maps/<name>.json loads, saves, and round-trips")

	var path := SimMapFile.path_of(FIRST_LIGHT)
	_ok("first_light.json exists at " + path, FileAccess.file_exists(path))
	var mf := SimMapFile.load_map(path)
	_ok("and loads", mf != null)
	if mf == null:
		return
	_ok("meta carries the name", mf.map_name == "First Light", mf.map_name)
	_ok("12.8 km at 100 m cells is 128 cells", mf.cells() == 128,
		"%d" % mf.cells())
	_ok("the height section is ops, not a dump -- a dozen, not 16384",
		mf.ops.size() < 20, "%d ops" % mf.ops.size())
	_ok("two bases, four deposits",
		mf.bases.size() == 2 and mf.deposits.size() == 4)

	var t := mf.build_terrain()
	_ok("the terrain is 12.8 km across",
		absf(t.extent_x_m() - 12800.0) < 0.5, "%.0f m" % t.extent_x_m())

	# Round-trip: save a copy, reload it, build it. Same bytes, same ground.
	var copy := _tmp("first_light_copy.json")
	_ok("save() writes the copy", mf.save(copy))
	var mf2 := SimMapFile.load_map(copy)
	_ok("the copy loads", mf2 != null)
	if mf2 != null:
		_ok("and builds the SAME heightfield, hash for hash",
			SimMapFile.heights_hash(mf2.build_terrain())
				== SimMapFile.heights_hash(t))
		mf2.save(copy)
		var again := SimMapFile.load_map(copy)
		_ok("saving the copy again is byte-stable (git-diffable)",
			again != null and JSON.stringify(again.to_dict(), "\t")
				== JSON.stringify(mf2.to_dict(), "\t"))


# ═══════════════════════════════════════════════════════════════════════════
# 2. DETERMINISM -- the whole point of ops over dumps
# ═══════════════════════════════════════════════════════════════════════════

func _suite_determinism() -> void:
	_suite("Same file -> byte-identical heightfield, every time")

	var a := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT))
	var b := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT))
	var ha := SimMapFile.heights_hash(a.build_terrain())
	var hb := SimMapFile.heights_hash(b.build_terrain())
	_ok("two independent loads and replays hash identically", ha == hb, ha)

	# Every op that rolls dice carries its OWN seed, so the sea_coast wobble
	# and the noise field cannot drift when an unrelated op is edited.
	var c := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT))
	c.ops.remove_at(1)   # drop the first ridge segment
	var t := c.build_terrain()
	_ok("deleting one ridge op leaves the seeded coastline exactly in place",
		t.is_water(-6000.0, 0.0) and not t.is_water(-4000.0, 0.0))


# ═══════════════════════════════════════════════════════════════════════════
# 3. REFUSAL -- a file we do not fully speak never half-loads
# ═══════════════════════════════════════════════════════════════════════════

func _suite_refusal() -> void:
	_suite("Version and op refusal (expected ERROR lines follow)")

	var good := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT)).to_dict()

	var newer := good.duplicate(true)
	newer["version"] = 2
	_ok("a version-2 file is refused by a version-1 build",
		SimMapFile.from_dict(newer) == null)

	var wrong := good.duplicate(true)
	wrong["format"] = "battle-save"
	_ok("the wrong format magic is refused",
		SimMapFile.from_dict(wrong) == null)

	var alien := good.duplicate(true)
	(alien["height"] as Array).append({"op": "volcano", "x": 0, "z": 0})
	_ok("an unknown op refuses the whole file, not just the op",
		SimMapFile.from_dict(alien) == null)

	var partial := good.duplicate(true)
	(partial["height"] as Array).append({"op": "ridge", "x0": 0, "z0": 0})
	_ok("an op missing required keys is refused",
		SimMapFile.from_dict(partial) == null)

	var torn := good.duplicate(true)
	(torn["height"] as Array).append(
		{"op": "raw_patch", "cx0": 0, "cz0": 0, "w": 3, "h": 3,
			"heights": [1.0, 2.0]})
	_ok("a raw_patch whose size disagrees with its data is refused",
		SimMapFile.from_dict(torn) == null)

	# The same refusal through the FILE path, exactly as a player would hit it.
	var vpath := _tmp("from_the_future.json")
	var f := FileAccess.open(vpath, FileAccess.WRITE)
	f.store_string(JSON.stringify(newer, "\t") + "\n")
	f.close()
	_ok("load_map() refuses the version-2 file on disk",
		SimMapFile.load_map(vpath) == null)


# ═══════════════════════════════════════════════════════════════════════════
# 4. THE OPS THEMSELVES
# ═══════════════════════════════════════════════════════════════════════════

func _tiny(extra_ops: Array, water := 0.0) -> SimTerrain:
	var mf := SimMapFile.from_dict({
		"format": "battle-map", "version": 1,
		"meta": {"name": "tiny", "size_m": 3200, "cell_m": 100},
		"water_level": water,
		"height": [{"op": "fill", "h": 50}] + extra_ops,
	})
	return mf.build_terrain() if mf != null else null


func _suite_ops() -> void:
	_suite("Each op replays through the terrain's own builders")

	var flat := _tiny([])
	_ok("fill covers the map", flat != null
		and absf(flat.height_at(0.0, 0.0) - 50.0) < 0.01)

	var r := _tiny([{"op": "raise", "x": 0, "z": 0,
		"radius_m": 600, "delta_m": 80}])
	# Cell CENTRES carry the heights, and (0,0) sits between four of them,
	# each ~71 m from the brush centre -- so the sampled peak reads a couple
	# of metres under fill + delta, exactly as the falloff says it should.
	_ok("raise lifts the centre by its delta",
		absf(r.height_at(0.0, 0.0) - 130.0) < 4.0,
		"%.1f m" % r.height_at(0.0, 0.0))
	_ok("and nothing outside the brush", absf(r.height_at(1200.0, 0.0) - 50.0) < 0.01)

	var p := _tiny([{"op": "raise", "x": 0, "z": 0, "radius_m": 900,
			"delta_m": 120},
		{"op": "plateau", "x": 0, "z": 0, "radius_m": 400, "h": 90,
			"blend_m": 200}])
	_ok("plateau flattens its disc to the target height",
		absf(p.height_at(0.0, 0.0) - 90.0) < 1.0
			and absf(p.height_at(300.0, 0.0) - 90.0) < 1.0)

	var rough := _tiny([{"op": "noise", "seed": 5, "amplitude_m": 40,
		"feature_cells": 2}])
	var smoothed := _tiny([{"op": "noise", "seed": 5, "amplitude_m": 40,
		"feature_cells": 2}, {"op": "smooth", "passes": 3}])
	_ok("smooth reduces the roughness noise put in",
		_roughness(smoothed) < _roughness(rough) * 0.8,
		"%.2f -> %.2f" % [_roughness(rough), _roughness(smoothed)])

	var patched := _tiny([{"op": "raw_patch", "cx0": 4, "cz0": 4, "w": 2,
		"h": 2, "heights": [7.0, 8.0, 9.0, 10.0]}])
	_ok("raw_patch writes exact cell heights -- the hand-paint escape hatch",
		absf(patched.height_at_cell(4, 4) - 7.0) < 0.001
			and absf(patched.height_at_cell(5, 5) - 10.0) < 0.001)

	var flooded := _tiny([], 55.0)
	_ok("water_level is a uniform offset: raise it past the plain and it drowns",
		flooded.is_water(0.0, 0.0)
			and absf(flooded.height_at_cell(0, 0) - (-5.0)) < 0.01)

	var sea := _tiny([{"op": "basin", "x0": -1600, "z0": -1600, "x1": -800,
		"z1": 1600, "depth_m": 30}])
	_ok("basin carves below sea level", sea.is_water(-1200.0, 0.0)
		and absf(sea.depth_at(-1200.0, 0.0) - 30.0) < 0.5)


func _roughness(t: SimTerrain) -> float:
	var sum := 0.0
	var n := 0
	for cz in range(t.cells_z - 1):
		for cx in range(t.cells_x - 1):
			sum += absf(t.height_at_cell(cx + 1, cz) - t.height_at_cell(cx, cz))
			sum += absf(t.height_at_cell(cx, cz + 1) - t.height_at_cell(cx, cz))
			n += 2
	return sum / float(n)


# ═══════════════════════════════════════════════════════════════════════════
# 5. VALIDITY -- the arena's suitability rules, enforced by the format
# ═══════════════════════════════════════════════════════════════════════════

func _suite_validity() -> void:
	_suite("A base in water is refused with a reason")

	var mf := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT))
	var t := mf.build_terrain()
	_ok("first_light validates clean", mf.validate(t).is_empty(),
		", ".join(mf.validate(t)))

	var wet := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT))
	wet.bases[0] = {"player": 0, "x": -6000, "z": 0}   # in the western sea
	var problems := wet.validate(t)
	_ok("a base moved into the sea is refused", not problems.is_empty())
	_ok("and the reason says why", problems.size() > 0
		and "water" in problems[0], problems[0] if problems.size() > 0 else "")

	# The footprint rule, not the centre rule: a dry CENTRE with a wet corner
	# is still refused, same nine-point check the arena placer uses.
	var shore_x := -6000.0
	while t.is_water(shore_x, 0.0):
		shore_x += 20.0
	var edge := SimMapFile.base_problem(t, shore_x + 40.0, 0.0)
	_ok("a base whose FOOTPRINT laps the shoreline is refused too",
		edge != "", edge)

	var off := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT))
	off.bases[1] = {"player": 1, "x": 6350, "z": 6350}
	_ok("a base outside the deployable margin is refused",
		not off.validate(t).is_empty())

	var cramped := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT))
	cramped.bases[1] = {"player": 1, "x": -3300, "z": -3300}
	_ok("two bases sharing an opening are refused",
		not cramped.validate(t).is_empty())

	var slick := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT))
	slick.deposits.append({"x": -6000, "z": 0})
	var dp := slick.validate(t)
	_ok("an oil deposit under water is refused -- no derrick could claim it",
		not dp.is_empty() and "derrick" in dp[0],
		dp[0] if dp.size() > 0 else "")


# ═══════════════════════════════════════════════════════════════════════════
# 6. FIRST LIGHT -- the design intent, asserted
# ═══════════════════════════════════════════════════════════════════════════

func _suite_first_light_design() -> void:
	_suite("First Light: a ridge with two passes, an oil basin each, a wet flank")

	var mf := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT))
	var t := mf.build_terrain()

	var crest := t.height_at(0.0, 0.0)
	_ok("the central ridge crests above 220 m", crest > 220.0, "%.0f m" % crest)
	var pass_n := t.height_at(0.0, -1550.0)
	var pass_s := t.height_at(0.0, 1550.0)
	_ok("the north pass is a genuine gap", pass_n < 140.0, "%.0f m" % pass_n)
	_ok("so is the south pass", pass_s < 140.0, "%.0f m" % pass_s)

	# The ridge does its docs/02 job: the two bases cannot see each other at
	# mast height, and the passes are where the map opens up.
	var b0 := mf.base_position(0)
	var b1 := mf.base_position(1)
	var y0 := t.ground_under(b0.x, b0.y) + 30.0
	var y1 := t.ground_under(b1.x, b1.y) + 30.0
	_ok("base-to-base line of sight is blocked by the ridge",
		not t.has_line_of_sight(b0.x, y0, b0.y, b1.x, y1, b1.y))

	_ok("the west flank is wet", t.is_water(-6100.0, 0.0)
		and t.is_water(-6100.0, -4000.0) and t.is_water(-6100.0, 4000.0))
	_ok("and it is a flank, not a moat -- the map centre is dry",
		not t.is_water(0.0, 0.0) and not t.is_water(3000.0, 0.0))

	for k in range(mf.deposits.size()):
		var d: Dictionary = mf.deposits[k]
		_ok("deposit %d sits on dry, low basin ground" % k,
			not t.is_water(float(d["x"]), float(d["z"]))
				and t.height_at(float(d["x"]), float(d["z"])) < crest * 0.35,
			"%.0f m" % t.height_at(float(d["x"]), float(d["z"])))

	_ok("the bases are a proper march apart", b0.distance_to(b1) > 8000.0,
		"%.0f m" % b0.distance_to(b1))
	_ok("the registry serves the AUTHORED spawns through the arena-shaped seam",
		SimMapFile.base_positions(t, 2)[0] == b0
			and SimMapFile.base_positions(t, 2)[1] == b1)


# ═══════════════════════════════════════════════════════════════════════════
# 7. PLAYABILITY -- SimMatch over a loaded terrain, directly
# ═══════════════════════════════════════════════════════════════════════════

func _setup(seed_value := 4242) -> SimMatchSetup:
	var s := SimMatchSetup.new()
	s.name = "First Light Test"
	s.seed_value = seed_value
	s.add(SimPlayerSetup.new({
		"name": "You", "is_human": true, "team": 0,
		"faction": SimPlayerSetup.Faction.US,
		"start_epoch": 4, "ceiling_epoch": 5,
		"starting_forces": SimPlayerSetup.ForcePreset.GARRISON,
		"skill": SimSkill.Level.VETERAN}))
	s.add(SimPlayerSetup.new({
		"name": "Russia", "team": 1,
		"faction": SimPlayerSetup.Faction.RUSSIA,
		"start_epoch": 4, "ceiling_epoch": 5,
		"starting_forces": SimPlayerSetup.ForcePreset.GARRISON,
		"skill": SimSkill.Level.VETERAN}))
	return s


## Exactly what SimMatch._begin() does, with the terrain and bases taken from
## the map file instead of SimArena -- the wiring the documented one-line hook
## will make automatic. No AIs: the suite drives player 0 by hand so every
## observed behaviour is an ordered one.
func _start_on_map(mf: SimMapFile, setup: SimMatchSetup) -> SimMatch:
	var m := SimMatch.new()
	m.setup = setup
	m.arena_key = SimMapFile.ARENA_PREFIX + FIRST_LIGHT
	m.world = SimWorld.new(setup.seed_value)
	m.terrain = mf.build_terrain()
	m.world.use_terrain(m.terrain)
	m.world.movement.prime_terrain(SimTypes.Category.GROUND)
	m.world.arm_on_spawn = true
	m.world.fire_control = SimFireControl.new(
		m.world.entities, m.world.weapons, m.world.solver, m.world.economy)
	SimSortie.install(m.world)
	SimPatrol.install(m.world)
	SimTransport.install(m.world)
	m.victory = SimVictory.new(m.world.entities, m.world.economy, m.world.damage)
	for pid in range(setup.players.size()):
		var p := setup.players[pid] as SimPlayerSetup
		var purse := m.world.economy.add_player_from_setup(
			pid, p, SimMatch.DEFAULT_START_CREDITS)
		purse.faction = p.team
		m._base_of[pid] = mf.base_position(pid)
		m.victory.add_player(pid, p.team, p.name, p.is_human)
		if p.is_human:
			m.human_player_id = pid
		m._deploy(pid, p, mf.base_position(pid))
	m.phase = SimMatch.Phase.RUNNING
	return m


func _suite_playable() -> void:
	_suite("A SimMatch constructed on the loaded terrain plays to a result")

	var mf := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT))
	var m := _start_on_map(mf, _setup())
	var e := m.world.entities

	var structures := [0, 0]
	var units := [0, 0]
	var wet := 0
	for pid in [0, 1]:
		for i in e.indices_of_owner(pid):
			if e.is_structure[i] == 1:
				structures[pid] += 1
			else:
				units[pid] += 1
			if m.terrain.is_water(e.pos_x[i], e.pos_z[i]):
				wet += 1
	_ok("both bases deploy on the authored spawns",
		structures[0] >= 6 and structures[1] >= 6,
		"%d and %d structures" % [structures[0], structures[1]])
	_ok("with their garrisons", units[0] > 0 and units[1] > 0)
	_ok("and nothing standing in the sea", wet == 0, "%d wet" % wet)

	# March player 0's force at the enemy base. The route crosses the map --
	# the planner must find a way past the authored ridge.
	var enemy := m.base_position(1)
	var force := PackedInt32Array()
	for i in m.own_units(0):
		if e.is_structure[i] == 0:
			force.append(i)
	var slots := m.world.movement.formation_slots(force, enemy.x, enemy.y)
	for k in range(force.size()):
		m.world.commands.move(0, force[k], slots[k * 2], slots[k * 2 + 1])

	var crossed := false
	var seen := false
	var shot := false
	for _chunk in range(40):                       # up to 10 simulated minutes
		m.run_ticks(int(15.0 * SimWorld.SIM_HZ))
		for i in force:
			if e.alive[i] == 1 and e.pos_x[i] > 500.0:
				crossed = true
		if m.picture_for(0).track_ids().size() > 0:
			seen = true
		if m.world.weapons.shots_fired > 0:
			shot = true
		if crossed and seen and shot:
			break
	_ok("the force crosses to the enemy side -- the passes are traversable",
		crossed)
	_ok("the sensor picture works on this terrain -- the enemy is detected",
		seen)
	_ok("and combat happens", shot,
		"%d shots" % m.world.weapons.shots_fired)

	# The end: raze what is left of the enemy base and run out the clock.
	for i in e.indices_of_owner(1):
		if e.alive[i] == 1 and e.is_structure[i] == 1:
			m.world.damage.apply_structure(i, e.structure_max[i] + 1.0, "test")
	m.run_ticks(int((SimVictory.CAPITULATION_SECONDS + 6.0) * SimWorld.SIM_HZ))
	_ok("the match ends in a victory on the authored map",
		m.is_finished() and m.outcome() == SimVictory.Outcome.VICTORY,
		m.headline())
