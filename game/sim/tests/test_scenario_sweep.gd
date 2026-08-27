extends SceneTree
## Every scenario on every arena it makes sense on, run to a result.
##
##   Godot --headless --path game --script sim/tests/test_scenario_sweep.gd
##
## One scenario ("peer") on one arena ("skirmish_valley") had been proven end
## to end; the other 12 scenarios and 2 arenas had never been RUN. This sweep
## starts every SimMatchSetup.SCENARIOS key on every SimArena.ALL arena the
## scenario's domains make sensible, drives it with autopilot on the human
## seat, and records outcome, winner, elapsed, kills and shots. The table is
## the deliverable: every cell gets a result or a named failure.
##
## WHICH ARENAS ARE SENSIBLE -- decided from the setup, not from a hand list:
## a scenario needs water when any participant is restricted away from both
## GROUND and INFANTRY (they can only fight from the sea or the air, and their
## opponents can only be reached over water); an arena has water when at least
## 2% of a 32x32 sample grid of its terrain is wet. Today that sends
## north_atlantic (both sides NAVAL|AIR|STRUCTURES) to coastal_shelf only and
## every other scenario to all three arenas.
##
## CAPS. Measured on this machine, the sim runs ~113 ticks/s of wall time on a
## peer match (2 x ARMY preset), so 90 simulated minutes is ~16 wall minutes
## for ONE stalemate. Two caps keep the sweep bounded:
##   * SIM_CAP:  5400 simulated seconds (90 min) -- the match is a stalemate.
##   * WALL_CAP: 300 wall seconds per match -- kill-and-mark, so one slow
##     match cannot sink the sweep. Rows record how far the sim got.
## Matches run SEQUENTIALLY in one process, and every row is printed AND
## flushed to user://scenario_sweep.txt the moment it finishes, so a hang is
## visible mid-run and attributable to a named match.
##
## DETERMINISM: the sim sees only its own seeded RNG (setup seed 12345, arena
## seed 20260826). Time.* is used HERE, in the harness, for the wall-clock
## kill switch only -- a WALL_CAP row is machine-dependent by nature and says
## so; sim outcomes and sim timestamps are not.
##
## THEATRE PROBES. The four SimTheatre maps are probed first, more gently: do
## they build (real DEM or procedural), do both bases of a two-player match
## land on dry ground, does a peer match START and tick there. Full
## resolution is not attempted -- at theatre scale the drive between bases
## alone is hours of sim.

const SIM_CAP_S := 5400.0          ## 90 simulated minutes
const WALL_CAP_MS := 300 * 1000    ## per match
const THEATRE_WALL_CAP_MS := 120 * 1000
const CHUNK_TICKS := 200           ## 10 s of sim between wall checks
const WATER_FRACTION_NEEDED := 0.02

var _exit := 1
var _rows: Array = []              ## for the final table
var _out: FileAccess = null


func _initialize() -> void:
	# `-- theatres_only` reruns just the theatre probes (own results file, so
	# a concurrent full sweep is not clobbered).
	var theatres_only := "theatres_only" in OS.get_cmdline_user_args()
	var out_name := "user://scenario_sweep_theatres.txt" if theatres_only \
		else "user://scenario_sweep.txt"
	_out = FileAccess.open(out_name, FileAccess.WRITE)
	_say("SCENARIO x ARENA SWEEP  (sim cap %.0f s, wall cap %d s/match)" % [
		SIM_CAP_S, WALL_CAP_MS / 1000])
	_say("results file: " + ProjectSettings.globalize_path(out_name))
	_say("")

	_probe_theatres()
	if not theatres_only:
		_sweep()
		_final_table()

	_exit = 0
	if _out != null:
		_out.close()


## Print a line and force it to the results file NOW, so a later hang cannot
## hide it behind a stdout pipe buffer.
func _say(line: String) -> void:
	print(line)
	if _out != null:
		_out.store_line(line)
		_out.flush()


# ── which arenas fit which scenario ──────────────────────────────────────────

func _scenario_needs_water(setup: SimMatchSetup) -> bool:
	for p in setup.players:
		var land := SimPlayerSetup.Domain.GROUND | SimPlayerSetup.Domain.INFANTRY
		if not (p as SimPlayerSetup).allows(land):
			return true
	return false


func _arena_has_water(key: String) -> bool:
	var t := SimArena.build(key)
	var wet := 0
	var n := 32
	for iz in range(n):
		for ix in range(n):
			var x := (float(ix) / float(n - 1) - 0.5) * t.extent_x_m() * 0.96
			var z := (float(iz) / float(n - 1) - 0.5) * t.extent_z_m() * 0.96
			if t.is_water(x, z):
				wet += 1
	return float(wet) / float(n * n) >= WATER_FRACTION_NEEDED


# ── the sweep ────────────────────────────────────────────────────────────────

func _sweep() -> void:
	var water_of: Dictionary = {}
	for a in SimArena.ALL:
		water_of[a] = _arena_has_water(a)
	_say("arena water: %s" % str(water_of))
	_say("")
	_say("%-20s %-16s %-9s %-22s %7s %6s %6s %7s" % [
		"SCENARIO", "ARENA", "OUTCOME", "WINNER", "sim_s", "kills", "shots", "wall_s"])
	_say("-".repeat(100))

	for key in SimMatchSetup.SCENARIOS:
		var probe_setup := SimMatchSetup.scenario(key)
		var needs_water := _scenario_needs_water(probe_setup)
		for arena in SimArena.ALL:
			if needs_water and not water_of[arena]:
				_row(key, arena, "SKIPPED", "needs water, arena has none",
					0.0, 0, 0, 0.0)
				continue
			_run_match(key, arena)


func _run_match(key: String, arena: String) -> void:
	var t0 := Time.get_ticks_msec()
	# A fresh setup per match: SimMatch.start mutates player state downstream.
	var setup := SimMatchSetup.scenario(key)
	var m := SimMatch.start(setup, arena, true)
	var probs := m.problems()
	if not probs.is_empty():
		_row(key, arena, "START_FAIL", "; ".join(probs), 0.0, 0, 0,
			float(Time.get_ticks_msec() - t0) / 1000.0)
		return

	var capped := ""
	while not m.is_finished():
		if m.elapsed_s() >= SIM_CAP_S:
			capped = "SIM_CAP"
			break
		if Time.get_ticks_msec() - t0 > WALL_CAP_MS:
			capped = "WALL_CAP"
			break
		m.run_ticks(CHUNK_TICKS)

	var wall_s := float(Time.get_ticks_msec() - t0) / 1000.0
	var outcome := capped if capped != "" else m.victory.outcome_name()
	var winner := _winner_of(m)
	_row(key, arena, outcome, winner, m.elapsed_s(),
		m.world.damage.kills, m.world.weapons.shots_fired, wall_s)


## "team N: name, name" when decided, else who is still standing.
func _winner_of(m: SimMatch) -> String:
	var v := m.victory
	if v.winning_team >= 0:
		var names := PackedStringArray()
		for p in m.setup.players:
			if (p as SimPlayerSetup).team == v.winning_team:
				names.append((p as SimPlayerSetup).name)
		return "team %d: %s" % [v.winning_team, ", ".join(names)]
	if not m.is_finished():
		var alive := PackedStringArray()
		for pid in v.player_ids():
			if not v.standing(pid).eliminated:
				alive.append(v.standing(pid).name)
		return "undecided (%s up)" % ", ".join(alive)
	return "-"


func _row(scen: String, arena: String, outcome: String, winner: String,
		sim_s: float, kills: int, shots: int, wall_s: float) -> void:
	_rows.append([scen, arena, outcome, winner, sim_s, kills, shots, wall_s])
	_say("%-20s %-16s %-9s %-22s %7.0f %6d %6d %7.1f" % [
		scen, arena, outcome, winner.substr(0, 22), sim_s, kills, shots, wall_s])


func _final_table() -> void:
	_say("")
	_say("FINAL TABLE (%d cells)" % _rows.size())
	_say("%-20s %-16s %-9s %-30s %7s %6s %6s %7s" % [
		"SCENARIO", "ARENA", "OUTCOME", "WINNER", "sim_s", "kills", "shots", "wall_s"])
	_say("-".repeat(110))
	for r in _rows:
		_say("%-20s %-16s %-9s %-30s %7.0f %6d %6d %7.1f" % [
			r[0], r[1], r[2], String(r[3]).substr(0, 30), r[4], r[5], r[6], r[7]])
	var bad := 0
	for r in _rows:
		if r[2] in ["START_FAIL"]:
			bad += 1
	_say("")
	_say("%d cells, %d START_FAIL" % [_rows.size(), bad])


# ── theatres ─────────────────────────────────────────────────────────────────

func _probe_theatres() -> void:
	_say("THEATRE PROBES (peer scenario, start + 30 s of sim, no resolution)")
	for key in SimTheatre.ALL:
		_probe_theatre(key)
	_say("")


func _probe_theatre(key: String) -> void:
	var t0 := Time.get_ticks_msec()
	var src := "real DEM" if SimTheatre.has_real_dem(key) else "procedural"
	var t := SimTheatre.build(key)
	if t == null:
		_say("  %-18s BUILD FAILED (%s)" % [key, src])
		return
	_say("  %-18s builds (%s): %dx%d cells, %.0f m/cell, %.0f x %.0f km" % [
		key, src, t.cells_x, t.cells_z, t.cell_size_m,
		t.extent_x_m() / 1000.0, t.extent_z_m() / 1000.0])

	# Two-player base placement: dry at the centre and at the corners of the
	# base footprint (BASE_LAYOUT spans about +/-170 m).
	var bases := SimArena.base_positions(t, 2)
	for i in range(bases.size()):
		var b: Vector2 = bases[i]
		var wet := 0
		for off in [Vector2(0, 0), Vector2(200, 0), Vector2(-200, 0),
				Vector2(0, 200), Vector2(0, -200)]:
			if t.is_water(b.x + off.x, b.y + off.y):
				wet += 1
		_say("    base %d at %8.0f, %8.0f  h=%6.0f m  %s" % [
			i, b.x, b.y, t.height_at(b.x, b.y),
			"DRY" if wet == 0 else "IN/NEAR WATER (%d/5 samples wet)" % wet])

	# Does a peer match START here? SimArena.build delegates theatre keys, so
	# the unmodified match layer can be pointed at a theatre.
	var setup := SimMatchSetup.scenario("peer")
	var m := SimMatch.start(setup, key, true)
	var probs := m.problems()
	if not probs.is_empty():
		_say("    peer match START_FAIL: %s" % "; ".join(probs))
		return
	var deployed := m.world.entities.count()
	var per_player := []
	for pid in range(setup.players.size()):
		per_player.append(m.world.entities.indices_of_owner(pid).size())
	while m.elapsed_s() < 30.0 and not m.is_finished() \
			and Time.get_ticks_msec() - t0 < THEATRE_WALL_CAP_MS:
		m.run_ticks(CHUNK_TICKS)
	_say("    peer match starts: %d entities (%s per player), 30 s ticked in %.1f wall s, shots %d" % [
		deployed, str(per_player), float(Time.get_ticks_msec() - t0) / 1000.0,
		m.world.weapons.shots_fired])


## A parse or runtime error inside _initialize() would otherwise leave the
## SceneTree idle with stdout buffered; this guarantees an exit either way.
func _process(_d: float) -> bool:
	quit(_exit)
	return true
