extends SceneTree
## The golden save/load property, adversarially, ACROSS PROCESSES.
##
## Run A: seed S, autopilot peer match, chunked 10 ticks per call, to
## completion. Run B: same seed in a DIFFERENT process, save at t seconds,
## exit (the world dies with the process). Run C: a third, fresh process
## restores the file and runs to completion with the identical chunking.
## A and C must record the same winner, tick, kills, shots, survivors,
## credits and state hash. Run A never calls to_dict()/save() at all, so a
## save that mutates the world it snapshots would show up as drift.
##
## Orchestrated from the shell; each mode is one process:
##   godot --path game --headless --script res://sim/tests/test_saveload_golden.gd \
##     -- runA <seed> <record_out>
##     -- save <seed> <t_seconds> <savefile> <record_out>
##     -- resume <savefile> <record_out>
##     -- twice <savefile> <record_out>
##
## PROBE lines (state_hash at fixed ticks) and SUB lines (per-subsystem
## digests of the snapshot dicts) go to stdout for the bisect: if anything
## drifts, the first SUB line that disagrees names the subsystem.

const CHUNK := 10                 ## ticks per run_ticks call; MUST match in all paths
const CAP_TICKS := 144000         ## 120 simulated minutes; both paths cap at the same tick
const PROBE_TICKS := [6000, 6010, 12000, 12010, 18000, 24000]

var _code := 1


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		push_error("usage: -- runA|save|resume|twice ...")
		quit(2)
		return
	match args[0]:
		"runA":
			_run_a(int(args[1]), args[2])
		"save":
			_save(int(args[1]), float(args[2]), args[3], args[4])
		"resume":
			_resume(args[1], args[2])
		"twice":
			_twice(args[1], args[2])
		"bisect":
			_bisect(int(args[1]), float(args[2]))
		_:
			push_error("unknown mode " + args[0])
	quit(_code)


func _match_for(seed_value: int) -> SimMatch:
	var setup := SimMatchSetup.scenario("peer")
	setup.seed_value = seed_value
	var m := SimMatch.start(setup, SimArena.SKIRMISH_VALLEY, true)
	if m.phase != SimMatch.Phase.RUNNING:
		push_error("match failed to start: " + "; ".join(m.problems()))
	return m


## Drive to completion (or the cap) in fixed chunks, probing on the way.
func _drive_to_end(m: SimMatch) -> void:
	while not m.is_finished() and m.world.tick < CAP_TICKS:
		m.run_ticks(CHUNK)
		if m.world.tick in PROBE_TICKS:
			print("PROBE tick=%d hash=%d" % [m.world.tick, m.world.state_hash()])


func _run_a(seed_value: int, out_path: String) -> void:
	var m := _match_for(seed_value)
	_drive_to_end(m)
	_write_record(m, out_path)
	_code = 0


func _save(seed_value: int, t_s: float, save_path: String, out_path: String) -> void:
	var m := _match_for(seed_value)
	var target := int(round(t_s * SimWorld.SIM_HZ))
	while m.world.tick < target and not m.is_finished():
		m.run_ticks(CHUNK)
	print("SAVEPOINT tick=%d hash=%d" % [m.world.tick, m.world.state_hash()])
	var json := SimSave.to_json(m)
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	f.store_string(json)
	f.close()
	print("SAVED bytes=%d" % json.length())
	for line in _sub_digests(m):
		print(line)
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	out.store_string("save_tick=%d\nsave_hash=%d\n" % [m.world.tick, m.world.state_hash()])
	out.close()
	_code = 0


func _resume(save_path: String, out_path: String) -> void:
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		push_error("cannot read " + save_path)
		return
	var r = SimSave.from_json(f.get_as_text())
	f.close()
	if not (r is SimMatch):
		push_error("restore did not produce a SimMatch")
		return
	var m := r as SimMatch
	print("RESTORED tick=%d hash=%d" % [m.world.tick, m.world.state_hash()])
	for line in _sub_digests(m):
		print(line)
	# Invariants a freshly restored world must satisfy before it runs a tick.
	_invariants(m, "at-restore")
	_drive_to_end(m)
	_invariants(m, "at-end")
	_write_record(m, out_path)
	_code = 0


## Restore the SAME file twice and run both 120 s: restore itself must be
## deterministic, with no shared state bleeding between the two objects.
func _twice(save_path: String, out_path: String) -> void:
	var f := FileAccess.open(save_path, FileAccess.READ)
	var text := f.get_as_text()
	f.close()
	var m1 = SimSave.from_json(text)
	var m2 = SimSave.from_json(text)
	if not (m1 is SimMatch and m2 is SimMatch):
		push_error("double restore failed")
		return
	var a := m1 as SimMatch
	var b := m2 as SimMatch
	var same: bool = a.world.state_hash() == b.world.state_hash()
	print("TWICE at-restore equal=%s" % same)
	var identical := same
	for step in range(24):                       # 24 x 5 s = 120 s
		a.run_ticks(100)
		b.run_ticks(100)
		if a.world.state_hash() != b.world.state_hash():
			identical = false
			print("TWICE DIVERGED at tick=%d" % a.world.tick)
			break
	print("TWICE after-120s equal=%s h1=%d h2=%d"
		% [identical, a.world.state_hash(), b.world.state_hash()])
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	out.store_string("twice_identical=%s\n" % identical)
	out.close()
	if identical:
		_code = 0


# ── the record both end-paths must agree on, byte for byte ──────────────────

func _write_record(m: SimMatch, out_path: String) -> void:
	var w := m.world
	var e := w.entities
	var survivors := {}
	var total := 0
	for i in range(e.count()):
		if e.alive[i] == 0:
			continue
		total += 1
		var pid: int = e.owner[i]
		survivors[pid] = int(survivors.get(pid, 0)) + 1
	var lines := PackedStringArray()
	lines.append("finished=%s" % m.is_finished())
	lines.append("outcome=%d" % m.outcome())
	lines.append("headline=%s" % m.headline())
	lines.append("final_tick=%d" % w.tick)
	lines.append("elapsed_s=%s" % var_to_str(w.elapsed_s))
	lines.append("victory_elapsed=%s" % var_to_str(m.victory.elapsed_s))
	lines.append("kills=%d" % w.damage.kills)
	lines.append("shots=%d" % w.weapons.shots_fired)
	lines.append("launched=%d" % w.munitions.launched)
	lines.append("terminated=%d" % w.munitions.terminated)
	lines.append("survivors_total=%d" % total)
	for pid in [0, 1]:
		lines.append("survivors_p%d=%d" % [pid, int(survivors.get(pid, 0))])
		lines.append("credits_p%d=%s" % [pid, var_to_str(w.economy.credits(pid))])
		lines.append("epoch_p%d=%d" % [pid, w.economy.epoch_of(pid)])
	lines.append("state_hash=%d" % w.state_hash())
	lines.append("positions=%d" % _positions_digest(w))
	lines.append("rng=%s" % str(w.rng.state()))
	var out := FileAccess.open(out_path, FileAccess.WRITE)
	out.store_string("\n".join(lines) + "\n")
	out.close()
	print("RECORD written to " + out_path)


func _positions_digest(w: SimWorld) -> int:
	var buf := PackedFloat64Array()
	for i in range(w.entities.count()):
		buf.append(w.entities.pos_x[i])
		buf.append(w.entities.pos_y[i])
		buf.append(w.entities.pos_z[i])
	return hash(buf)


## Digest of every subsystem's own snapshot, one line each, so a divergence
## names its subsystem. JSON.stringify of a dict built by the same code path
## is deterministic, and hash() of a String is content-based in Godot 4.
func _sub_digests(m: SimMatch) -> PackedStringArray:
	var out := PackedStringArray()
	var parts := _sub_parts(m)
	var keys := parts.keys()
	keys.sort()
	for k in keys:
		out.append("SUB %s %d" % [k, hash(JSON.stringify(parts[k], "", true, true))])
	return out


func _sub_parts(m: SimMatch) -> Dictionary:
	var w := m.world
	var parts := {
		"entities": w.entities.to_dict(),
		"solver": w.solver.to_dict(),
		"munitions": w.munitions.to_dict(),
		"movement": w.movement.to_dict(),
		"damage": w.damage.to_dict(),
		"economy": w.economy.to_dict(),
		"weapons": w.weapons.to_dict(),
		"commands": w.commands.to_dict(),
		"match": m.to_dict(),
	}
	if w.fire_control != null:
		parts["fire_control"] = w.fire_control.to_dict()
	if w.transport_system != null:
		parts["transport"] = w.transport_system.to_dict()
	if w.patrol_system != null:
		parts["patrol"] = w.patrol_system.to_dict()
	if w.sortie_system != null:
		parts["sortie"] = w.sortie_system.to_dict()
	for pid in w.ai_player_ids():
		parts["ai_%d" % pid] = (w.ai[pid] as SimAiDirector).to_dict()
	return parts


## What a restored world must satisfy regardless of history.
func _invariants(m: SimMatch, tag: String) -> void:
	var w := m.world
	var e := w.entities
	var bad := 0
	for i in range(e.count()):
		if is_nan(e.pos_x[i]) or is_nan(e.pos_y[i]) or is_nan(e.pos_z[i]) \
				or is_nan(e.vel_x[i]) or is_nan(e.vel_z[i]):
			bad += 1
	var purse_ok := is_finite(w.economy.credits(0)) and is_finite(w.economy.credits(1))
	var tracks_ok := true
	for fid in w.solver.faction_ids():
		var table: SimTrackTable = w.solver.tables[fid]
		for id in table.track_ids():
			var t := table.get_track(id)
			if t == null or is_nan(t.pos_x) or is_nan(t.pos_z) or t.age_s < 0.0:
				tracks_ok = false
	print("INVARIANTS %s nan_entities=%d purses_finite=%s tracks_ok=%s"
		% [tag, bad, purse_ok, tracks_ok])


# ── the bisect: run the continuing world and the restored world side by side
# one chunk past the save, and name what diverges ───────────────────────────

func _bisect(seed_value: int, t_s: float) -> void:
	var m := _match_for(seed_value)
	var target := int(round(t_s * SimWorld.SIM_HZ))
	while m.world.tick < target and not m.is_finished():
		m.run_ticks(CHUNK)
	var json := SimSave.to_json(m)
	var r = SimSave.from_json(json)
	if not (r is SimMatch):
		push_error("bisect: restore failed")
		return
	var m2 := r as SimMatch
	print("BISECT at save: equal=%s" % (m.world.state_hash() == m2.world.state_hash()))
	for step in range(40):
		m.run_ticks(1)
		m2.run_ticks(1)
		var same: bool = m.world.state_hash() == m2.world.state_hash()
		var subs_same := _diff_subs(m, m2, false)
		print("BISECT tick=%d hash_equal=%s subs_equal=%s" % [m.world.tick, same, subs_same])
		if not same or not subs_same:
			_diff_subs(m, m2, true)
			_dump_parts(m, "/tmp/golden_unbroken")
			_dump_parts(m2, "/tmp/golden_restored")
			_diff_report(m, m2)
			return
	print("BISECT no divergence within 40 ticks (in-process)")
	_code = 0


## Compare the raw snapshot JSON of every subsystem; when verbose, print the
## first byte where each diverging pair differs, which names the field.
func _diff_subs(m: SimMatch, m2: SimMatch, verbose: bool) -> bool:
	var p1 := _sub_parts(m)
	var p2 := _sub_parts(m2)
	var all_same := true
	for k in p1:
		var j1 := JSON.stringify(p1[k], "", true, true)
		var j2 := JSON.stringify(p2[k], "", true, true)
		if j1 == j2:
			continue
		all_same = false
		if verbose:
			print("SUBDIFF %s: %s" % [k, _first_diff(j1, j2)])
	return all_same


func _first_diff(x: String, y: String) -> String:
	var n: int = mini(x.length(), y.length())
	for i in range(n):
		if x.unicode_at(i) != y.unicode_at(i):
			var start: int = maxi(0, i - 120)
			return "at %d: ...%s...  VS  ...%s..." % [
				i, x.substr(start, 200), y.substr(start, 200)]
	return "lengths differ: %d vs %d" % [x.length(), y.length()]


func _diff_report(m: SimMatch, m2: SimMatch) -> void:
	var d1 := _sub_digests(m)
	var d2 := _sub_digests(m2)
	for i in range(d1.size()):
		if d1[i] != d2[i]:
			print("DIVERGED SUBSYSTEM: %s | %s" % [d1[i], d2[i]])
	var e1 := m.world.entities
	var e2 := m2.world.entities
	for i in range(e1.count()):
		if e1.pos_x[i] != e2.pos_x[i] or e1.pos_z[i] != e2.pos_z[i] \
				or e1.vel_x[i] != e2.vel_x[i] or e1.vel_z[i] != e2.vel_z[i] \
				or e1.alive[i] != e2.alive[i] or e1.structure[i] != e2.structure[i] \
				or e1.heading_rad[i] != e2.heading_rad[i] \
				or e1.speed_ms[i] != e2.speed_ms[i] \
				or e1.move_state[i] != e2.move_state[i] \
				or e1.has_dest[i] != e2.has_dest[i] \
				or e1.emcon[i] != e2.emcon[i] \
				or e1.fuel[i] != e2.fuel[i]:
			print("ENT %d '%s' owner=%d cat=%d  pos(%f,%f)vs(%f,%f) vel(%f,%f)vs(%f,%f) alive %d/%d hp %f/%f emcon %d/%d fuel %f/%f move %d/%d dest %d/%d spd %f/%f hdg %f/%f"
				% [i, e1.names[i], e1.owner[i], e1.category[i],
				e1.pos_x[i], e1.pos_z[i], e2.pos_x[i], e2.pos_z[i],
				e1.vel_x[i], e1.vel_z[i], e2.vel_x[i], e2.vel_z[i],
				e1.alive[i], e2.alive[i], e1.structure[i], e2.structure[i],
				e1.emcon[i], e2.emcon[i], e1.fuel[i], e2.fuel[i],
				e1.move_state[i], e2.move_state[i], e1.has_dest[i], e2.has_dest[i],
				e1.speed_ms[i], e2.speed_ms[i], e1.heading_rad[i], e2.heading_rad[i]])
	print("RNG world %d vs %d  munitions %d vs %d" % [
		m.world.rng.state(), m2.world.rng.state(),
		m.world.munitions.rng.state(), m2.world.munitions.rng.state()])
	for pid in m.world.ai_player_ids():
		var a1 := m.world.ai[pid] as SimAiDirector
		var a2 := m2.world.ai[pid] as SimAiDirector
		print("AI %d rng %d vs %d posture %d vs %d" % [pid,
			a1.rng.state(), a2.rng.state(), a1.posture, a2.posture])
	print("shots %d vs %d  launched %d vs %d  active %d vs %d  kills %d vs %d" % [
		m.world.weapons.shots_fired, m2.world.weapons.shots_fired,
		m.world.munitions.launched, m2.world.munitions.launched,
		m.world.munitions.active_count(), m2.world.munitions.active_count(),
		m.world.damage.kills, m2.world.damage.kills])
	# Track pictures, per faction: count and per-track fields.
	for f in m.world.solver.faction_ids():
		var t1: SimTrackTable = m.world.solver.tables[f]
		var t2: SimTrackTable = m2.world.solver.tables[f]
		if t1.count() != t2.count():
			print("TRACKS faction %d count %d vs %d" % [f, t1.count(), t2.count()])
		for id in t1.track_ids():
			var a = t1.get_track(id)
			var b = t2.get_track(id)
			if b == null:
				print("TRACK %d missing on restore side" % id)
				continue
			if a.quality != b.quality or a.age_s != b.age_s \
					or a.pos_x != b.pos_x or a.pos_z != b.pos_z:
				print("TRACK f%d id%d q %d/%d age %f/%f pos (%f,%f)vs(%f,%f)"
					% [f, id, a.quality, b.quality, a.age_s, b.age_s,
					a.pos_x, a.pos_z, b.pos_x, b.pos_z])


func _dump_parts(m: SimMatch, prefix: String) -> void:
	var parts := _sub_parts(m)
	for k in parts:
		var f := FileAccess.open("%s_%s.json" % [prefix, k], FileAccess.WRITE)
		f.store_string(JSON.stringify(parts[k], "  ", true, true))
		f.close()
