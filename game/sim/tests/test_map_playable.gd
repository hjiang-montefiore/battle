extends SceneTree
## THE REAL PROOF that an authored map is a playable map, not scenery.
##
##     godot --path game --headless --script res://sim/tests/test_map_playable.gd
##
## Loads data/maps/first_light.json through SimMapFile, constructs a SimMatch
## over the loaded terrain DIRECTLY (the arena hook is documented but not yet
## landed -- sim_arena.gd is owned by another workflow), puts an AI on BOTH
## seats, and runs until SimVictory declares a winner. Then does it again with
## the same seed and demands the identical result, tick for tick and kill for
## kill -- an authored map must not cost the sim its determinism.
##
## Finally: load-edit-save-load. Append one op through the loader, save,
## reload, and verify the op list grew by exactly one and the heightfield
## changed only where that op says it may.

const FIRST_LIGHT := "first_light"
const SEED := 4242
## Hard stop: 100 simulated minutes. gate_playable.gd uses the same guard.
const GUARD_PASSES := 200
const PASS_TICKS := 600   # 30 s of sim at 20 Hz per pass

var _passed := 0
var _failed := 0


func _init() -> void:
	print("")
	print("  BATTLE -- authored map playability (SimMatch to a winner)")
	print("  " + "-".repeat(66))

	var a := _play(SEED)
	_suite("first_light.json plays to a winner, both sides autopilot")
	_ok("the match ends", bool(a["finished"]), String(a["headline"]))
	_ok("with a decisive result, not a draw",
		int(a["outcome"]) != SimVictory.Outcome.DRAW
			and int(a["outcome"]) != SimVictory.Outcome.UNDECIDED,
		"outcome " + String(a["outcome_name"]))
	_ok("a winning team is named", int(a["winning_team"]) >= 0,
		"team %d (%s)" % [int(a["winning_team"]), String(a["winner"])])
	_ok("blood was actually shed on the way", int(a["kills"]) > 0,
		"%d kills, %d shots" % [int(a["kills"]), int(a["shots"])])
	print("    REPORT winner=%s team=%d tick=%d elapsed=%.0fs kills=%d shots=%d"
		% [String(a["winner"]), int(a["winning_team"]), int(a["tick"]),
			float(a["elapsed_s"]), int(a["kills"]), int(a["shots"])])

	_suite("Same seed, same map file -> the identical match")
	var b := _play(SEED)
	_ok("same terrain, hash for hash",
		String(a["terrain_hash"]) == String(b["terrain_hash"]),
		String(a["terrain_hash"]).left(16))
	_ok("same winner", int(a["winning_team"]) == int(b["winning_team"])
			and String(a["winner"]) == String(b["winner"]))
	_ok("same final tick", int(a["tick"]) == int(b["tick"]),
		"%d vs %d" % [int(a["tick"]), int(b["tick"])])
	_ok("same kill count", int(a["kills"]) == int(b["kills"]),
		"%d vs %d" % [int(a["kills"]), int(b["kills"])])
	_ok("same end-state entity fingerprint",
		String(a["fingerprint"]) == String(b["fingerprint"]),
		String(a["fingerprint"]).left(16))

	_suite_roundtrip()

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


# ═══════════════════════════════════════════════════════════════════════════
# THE MATCH
# ═══════════════════════════════════════════════════════════════════════════

func _setup(seed_value: int) -> SimMatchSetup:
	var s := SimMatchSetup.new()
	s.name = "First Light Playable"
	s.seed_value = seed_value
	s.add(SimPlayerSetup.new({
		"name": "West", "is_human": true, "team": 0,
		"faction": SimPlayerSetup.Faction.US,
		"start_epoch": 4, "ceiling_epoch": 5,
		"starting_forces": SimPlayerSetup.ForcePreset.GARRISON,
		"skill": SimSkill.Level.VETERAN}))
	s.add(SimPlayerSetup.new({
		"name": "East", "team": 1,
		"faction": SimPlayerSetup.Faction.RUSSIA,
		"start_epoch": 4, "ceiling_epoch": 5,
		"starting_forces": SimPlayerSetup.ForcePreset.GARRISON,
		"skill": SimSkill.Level.VETERAN}))
	return s


## Exactly SimMatch._begin() with autopilot_human = true, except that the
## terrain and the bases come from the map file instead of SimArena -- the
## wiring the documented one-line hook in SimArena.build() will make
## automatic. Both seats get an AI director: nobody is at the keyboard.
func _start_on_map(mf: SimMapFile, setup: SimMatchSetup) -> SimMatch:
	var m := SimMatch.new()
	m.setup = setup
	m.arena_key = SimMapFile.ARENA_PREFIX + FIRST_LIGHT
	m.autopilot_human = true
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
		m.world.add_ai(pid, p.team, p)
		m._deploy(pid, p, mf.base_position(pid))
	m.phase = SimMatch.Phase.RUNNING
	return m


func _play(seed_value: int) -> Dictionary:
	var mf := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT))
	if mf == null:
		return {"finished": false, "headline": "map refused to load",
			"outcome": SimVictory.Outcome.UNDECIDED, "outcome_name": "NONE",
			"winning_team": -1, "winner": "", "kills": 0, "shots": 0,
			"tick": 0, "elapsed_s": 0.0, "terrain_hash": "", "fingerprint": ""}
	var m := _start_on_map(mf, _setup(seed_value))
	var terrain_hash := SimMapFile.heights_hash(m.terrain)
	var guard := 0
	while not m.is_finished() and guard < GUARD_PASSES:
		m.run_ticks(PASS_TICKS)
		guard += 1
	var winner := ""
	for pid in m.victory.player_ids():
		var s := m.victory.standing(pid)
		if s != null and s.team == m.victory.winning_team and not s.eliminated:
			winner += ("" if winner == "" else "+") + s.name
	return {
		"finished": m.is_finished(),
		"headline": m.headline(),
		"outcome": m.outcome(),
		"outcome_name": m.victory.outcome_name(),
		"winning_team": m.victory.winning_team,
		"winner": winner,
		"kills": m.world.damage.kills,
		"shots": m.world.weapons.shots_fired,
		"tick": m.world.tick,
		"elapsed_s": m.world.elapsed_s,
		"terrain_hash": terrain_hash,
		"fingerprint": _fingerprint(m.world),
	}


## SHA-256 over the entity state a desync would corrupt first.
func _fingerprint(w: SimWorld) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(w.entities.pos_x.to_byte_array())
	ctx.update(w.entities.pos_z.to_byte_array())
	ctx.update(w.entities.alive.to_byte_array())
	return ctx.finish().hex_encode()


# ═══════════════════════════════════════════════════════════════════════════
# LOAD-EDIT-SAVE-LOAD
# ═══════════════════════════════════════════════════════════════════════════

func _suite_roundtrip() -> void:
	_suite("Load-edit-save-load: one appended op, one local change")

	var before := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT))
	var t0 := before.build_terrain()
	var n_ops := before.ops.size()

	var edited := SimMapFile.load_map(SimMapFile.path_of(FIRST_LIGHT))
	var op := {"op": "raise", "x": 2000.0, "z": -2600.0,
		"radius_m": 500.0, "delta_m": 30.0}
	edited.ops.append(op)

	var dir := ProjectSettings.globalize_path("user://map_file_tests/")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "first_light_edited.json"
	_ok("save() after the edit", edited.save(path))

	var reloaded := SimMapFile.load_map(path)
	_ok("the edited file reloads", reloaded != null)
	if reloaded == null:
		return
	_ok("the op list grew by exactly one",
		reloaded.ops.size() == n_ops + 1,
		"%d -> %d" % [n_ops, reloaded.ops.size()])
	var last: Dictionary = reloaded.ops[reloaded.ops.size() - 1]
	_ok("and the last op is the one appended",
		String(last["op"]) == "raise" and absf(float(last["x"]) - 2000.0) < 0.001
			and absf(float(last["delta_m"]) - 30.0) < 0.001)

	var t1 := reloaded.build_terrain()
	var outside_changed := 0
	var inside_changed := 0
	var hx := t0.extent_x_m() * 0.5
	var hz := t0.extent_z_m() * 0.5
	for cz in range(t0.cells_z):
		for cx in range(t0.cells_x):
			var i := cz * t0.cells_x + cx
			if t0.heights[i] == t1.heights[i]:
				continue
			var wx := (float(cx) + 0.5) * t0.cell_size_m - hx
			var wz := (float(cz) + 0.5) * t0.cell_size_m - hz
			var d := Vector2(wx - 2000.0, wz - (-2600.0)).length()
			if d <= 500.0:
				inside_changed += 1
			else:
				outside_changed += 1
	_ok("the heightfield changed inside the op's brush", inside_changed > 0,
		"%d cells" % inside_changed)
	_ok("and NOWHERE else -- bit-identical outside the radius",
		outside_changed == 0, "%d stray cells" % outside_changed)
	var centre_delta: float = t1.height_at(2000.0, -2600.0) \
		- t0.height_at(2000.0, -2600.0)
	_ok("the centre rose by roughly the op's delta",
		centre_delta > 20.0 and centre_delta < 32.0, "%.1f m" % centre_delta)
