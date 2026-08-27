extends SceneTree
## Save/load tests. The one property that matters is BEHAVIOURAL IDENTITY:
## a match saved, serialized to JSON, and restored into a fresh object graph
## must continue EXACTLY as the unbroken one would -- same tick, same kills,
## same shots, same state hash. Byte identity of the save file is NOT the
## goal; identity of what happens next is.
##
##     godot --path game --headless --script res://sim/tests/test_saveload.gd
##
## Structure:
##   1. version refusal -- a mismatched format is refused plainly, never
##      half-loaded
##   2. bare-world round trip -- spot asserts on every subsystem the bare
##      world exercises (tracks, an in-flight projectile, a cargo manifest, a
##      patrol leg, a deploy timer, RNG streams), then a behavioural run
##   3. match round trip -- spot asserts (purse balance, AI belief count,
##      track quality/age), a full save(save(restore(x))) == save(x) identity
##      check, then the behavioural test: save at t+60 s, run both sides 60 s
##      more in identical chunks, compare kills + shots + state hash

var _passed := 0
var _failed := 0


func _init() -> void:
	print("")
	print("  BATTLE -- save/load tests")
	print("  " + "-".repeat(66))

	_suite_version_refusal()
	_suite_bare_world()
	_suite_match_round_trip()

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
# 1. VERSION REFUSAL
# ═══════════════════════════════════════════════════════════════════════════

func _suite_version_refusal() -> void:
	_suite("Version refusal -- a wrong format never half-loads")

	var wrong := JSON.stringify({"save_format": SimSave.FORMAT + 1, "world": {}})
	_ok("a newer format is refused outright",
		SimSave.from_json(wrong) == null)
	var ancient := JSON.stringify({"save_format": 0, "world": {}})
	_ok("an older format is refused outright",
		SimSave.from_json(ancient) == null)
	_ok("garbage text is refused, not crashed on",
		SimSave.from_json("this is not a save") == null)
	_ok("a versionless dictionary is refused",
		SimSave.restore({"world": {}}) == null)
	_ok("a version with no world is refused",
		SimSave.restore({"save_format": SimSave.FORMAT}) == null)


# ═══════════════════════════════════════════════════════════════════════════
# 2. BARE WORLD -- every subsystem state the spine can express by hand
# ═══════════════════════════════════════════════════════════════════════════

func _radar(name: String, ref_km: float, height: float) -> SimSensorDef:
	return SimSensorDef.new({
		"name": name, "domain": SimTypes.Domain.RF_ACTIVE,
		"reference_range_km": ref_km, "mount_height_m": height,
		"max_quality": SimTypes.TrackQuality.FIRE_CONTROL,
		"radar_gen": 4, "revisit_seconds": 0.0, "eccm_rating": 2})


## One world with a track picture, a round in flight, cargo aboard a
## transport, a patrol loop and a deploying unit -- driven identically on
## every call, so two constructions are interchangeable.
func _build_bare_world() -> SimWorld:
	var w := SimWorld.new(20260827)
	var t := SimTerrain.new(64, 64, 200.0, "saveload test range")
	t.add_ridge(-2000.0, -6000.0, -2000.0, 6000.0, 180.0, 1200.0)
	w.use_terrain(t)
	SimPatrol.install(w)
	SimTransport.install(w)

	var e := w.entities

	# The picture: an illuminator watching raiders.
	var shooter := e.add("SAM battery", 0, 0, 25, 0, SimSignature.new(50.0),
		[_radar("illuminator", 140.0, 25.0)], SimTypes.Category.GROUND)
	for i in range(3):
		var r := e.add("raider %d" % i, 1, 20000 + i * 1500, 2000 + i * 300,
			i * 800, SimSignature.new(6.0 + float(i)), [], SimTypes.Category.AIR)
		e.set_velocity(r, -180.0 - 10.0 * float(i), 0.0, 5.0 * float(i))

	# Cargo: a squad aboard an APC.
	var apc := e.add("APC", 0, 500, 0, 500, SimSignature.new(20.0), [],
		SimTypes.Category.GROUND)
	e.set_mobility(apc, 8.0, 2.0, 1.0)
	e.set_cargo_capacity(apc, 4)
	var squad := e.add("squad", 0, 505, 0, 505, SimSignature.new(2.0), [],
		SimTypes.Category.GROUND)
	e.set_mobility(squad, 2.0, 1.0, 2.0)
	w.transport_system.order_load(squad, apc)

	# A patrol loop.
	var scout := e.add("scout", 0, 1000, 0, 1000, SimSignature.new(10.0), [],
		SimTypes.Category.GROUND)
	e.set_mobility(scout, 12.0, 3.0, 1.5)
	w.patrol_system.order_patrol(scout,
		PackedFloat32Array([2200.0, 1000.0, 2200.0, 2200.0]))

	# A deployable mid-transition.
	var gun := e.add("towed gun", 0, 800, 0, -800, SimSignature.new(15.0), [],
		SimTypes.Category.GROUND)
	e.set_mobility(gun, 5.0, 1.5, 1.0)
	w.transport_system.make_deployable(gun, 6.0, 4.0, true)
	w.transport_system.order_deploy(gun)

	# Build the picture, then put a round in the air.
	w.run_ticks(20)
	var table := w.track_table_for(0)
	var ids := table.track_ids()
	if not ids.is_empty():
		var track := table.get_track(ids[0])
		w.munitions.fire(SimMunitionDef.sam_medium(), shooter, 1, track)
	w.run_ticks(10)   # mid-flight, mid-deploy, mid-patrol
	return w


func _suite_bare_world() -> void:
	_suite("Bare world round trip -- spot asserts and behavioural identity")

	var w := _build_bare_world()
	var json := SimSave.to_json(w)
	var r = SimSave.from_json(json)
	_ok("a bare world restores", r is SimWorld)
	if not (r is SimWorld):
		return
	var w2 := r as SimWorld

	# ── the picture ─────────────────────────────────────────────────────────
	var t1 := w.track_table_for(0)
	var t2 := w2.track_table_for(0)
	_ok("track count round-trips", t1.count() == t2.count(),
		"%d vs %d" % [t1.count(), t2.count()])
	var ids := t1.track_ids()
	if not ids.is_empty():
		var a := t1.get_track(ids[0])
		var b := t2.get_track(ids[0])
		_ok("a track's quality round-trips", b != null and a.quality == b.quality,
			SimTypes.quality_name(a.quality))
		_ok("a track's age round-trips exactly", b != null and a.age_s == b.age_s,
			"%.6f s" % a.age_s)
		_ok("a track's believed position round-trips exactly",
			b != null and a.pos_x == b.pos_x and a.pos_z == b.pos_z)

	# ── the round in flight ─────────────────────────────────────────────────
	_ok("the in-flight round survives the trip",
		w.munitions.active_count() == 1 and w2.munitions.active_count() == 1,
		"%d vs %d in flight" % [w.munitions.active_count(), w2.munitions.active_count()])
	if w.munitions.active_count() == 1 and w2.munitions.active_count() == 1:
		var p1: SimProjectile = w.munitions._pool[w.munitions._active[0]]
		var p2: SimProjectile = w2.munitions._pool[w2.munitions._active[0]]
		_ok("its position round-trips exactly",
			p1.x == p2.x and p1.y == p2.y and p1.z == p2.z,
			"(%.2f, %.2f, %.2f)" % [p1.x, p1.y, p1.z])
		_ok("its velocity and clock round-trip exactly",
			p1.vx == p2.vx and p1.vy == p2.vy and p1.vz == p2.vz
			and p1.time_s == p2.time_s)
		_ok("its munition def rode with it",
			p1.def.name == p2.def.name
			and p1.def.max_speed == p2.def.max_speed)

	# ── cargo, patrol, deploy ───────────────────────────────────────────────
	var apc := 4     # entity indices are deterministic: 0 sam, 1-3 raiders, 4 apc
	var squad := 5
	var scout := 6
	var gun := 7
	_ok("the cargo manifest round-trips",
		w2.entities.cargo_of(apc) == w.entities.cargo_of(apc)
		and w2.entities.carried_by[squad] == apc,
		str(w2.entities.cargo_of(apc)))
	_ok("the patrol loop and its leg round-trip",
		w2.patrol_system.is_patrolling(scout)
		and w2.patrol_system.leg_of(scout) == w.patrol_system.leg_of(scout),
		"leg %d" % w2.patrol_system.leg_of(scout))
	_ok("the deploy transition round-trips mid-count",
		w2.entities.deploy_state[gun] == w.entities.deploy_state[gun]
		and w2.entities.deploy_timer[gun] == w.entities.deploy_timer[gun],
		"%.3f s left" % w2.entities.deploy_timer[gun])

	# ── the streams ─────────────────────────────────────────────────────────
	_ok("the world RNG stream round-trips exactly",
		w.rng.state() == w2.rng.state())
	_ok("the munitions RNG stream round-trips exactly",
		w.munitions.rng.state() == w2.munitions.rng.state())

	_ok("the state hash matches at the restore point",
		w.state_hash() == w2.state_hash(), "0x%x" % w.state_hash())

	# ── behavioural identity ────────────────────────────────────────────────
	w.run_ticks(400)
	w2.run_ticks(400)
	_ok("20 s later the two worlds are still identical",
		w.state_hash() == w2.state_hash(),
		"0x%x vs 0x%x" % [w.state_hash(), w2.state_hash()])
	_ok("the round terminated the same way on both sides",
		w.munitions.terminated == w2.munitions.terminated
		and w.munitions.launched == w2.munitions.launched)
	_ok("deploy completed identically",
		w.entities.deploy_state[gun] == w2.entities.deploy_state[gun])


# ═══════════════════════════════════════════════════════════════════════════
# 3. THE MATCH -- the golden property, in the short form
# ═══════════════════════════════════════════════════════════════════════════

## Drive a match in fixed 10-tick chunks. Chunking matters: the victory layer
## accumulates real seconds per call, so the unbroken run and the restored run
## must be fed the same call pattern for the comparison to mean anything.
func _drive(m: SimMatch, seconds: float) -> void:
	var chunks := int(round(seconds * SimWorld.SIM_HZ / 10.0))
	for _i in range(chunks):
		m.run_ticks(10)


func _positions_digest(w: SimWorld) -> int:
	var buf := PackedFloat64Array()
	for i in range(w.entities.count()):
		buf.append(w.entities.pos_x[i])
		buf.append(w.entities.pos_y[i])
		buf.append(w.entities.pos_z[i])
	return hash(buf)


func _suite_match_round_trip() -> void:
	_suite("Match round trip -- save at t+60 s, both sides run 60 s more")

	# Two identical matches from two identical setups, both on autopilot.
	var a := SimMatch.start(SimMatchSetup.scenario("peer"),
		SimArena.SKIRMISH_VALLEY, true)
	var b := SimMatch.start(SimMatchSetup.scenario("peer"),
		SimArena.SKIRMISH_VALLEY, true)
	_ok("both matches start", a.phase == SimMatch.Phase.RUNNING
		and b.phase == SimMatch.Phase.RUNNING)

	_drive(b, 60.0)
	var json := SimSave.to_json(b)
	_ok("the save is real JSON of nontrivial size", json.length() > 10000,
		"%d bytes" % json.length())
	var r = SimSave.from_json(json)
	_ok("the match restores", r is SimMatch)
	if not (r is SimMatch):
		return
	var b2 := r as SimMatch

	# ── spot asserts at the restore point ───────────────────────────────────
	for pid in [0, 1]:
		_ok("player %d's purse balance round-trips exactly" % pid,
			b.credits(pid) == b2.credits(pid), "%.4f cr" % b2.credits(pid))
	_ok("epochs round-trip",
		b.epoch(0) == b2.epoch(0) and b.epoch(1) == b2.epoch(1))
	for pid in b.world.ai_player_ids():
		var d1 := b.world.ai[pid] as SimAiDirector
		var d2 := b2.world.ai[pid] as SimAiDirector
		_ok("AI %d's belief count round-trips" % pid,
			d1.memory.count() == d2.memory.count(),
			"%d beliefs" % d2.memory.count())
		_ok("AI %d's posture and RNG round-trip" % pid,
			d1.posture == d2.posture and d1.rng.state() == d2.rng.state())
	var table := b.picture_for(0)
	var table2 := b2.picture_for(0)
	_ok("the human coalition's picture round-trips",
		table.count() == table2.count(), "%d tracks" % table2.count())
	for id in table.track_ids():
		var tr := table.get_track(id)
		var tr2 := table2.get_track(id)
		_ok("track %d quality+age round-trip" % id,
			tr2 != null and tr.quality == tr2.quality and tr.age_s == tr2.age_s,
			"%s, %.3f s" % [SimTypes.quality_name(tr.quality), tr.age_s])
		break   # one representative is enough; the hash covers the rest
	_ok("kills and shots agree at the restore point",
		b.world.damage.kills == b2.world.damage.kills
		and b.world.weapons.shots_fired == b2.world.weapons.shots_fired,
		"%d kills, %d shots" % [b2.world.damage.kills, b2.world.weapons.shots_fired])
	_ok("the state hash matches at the restore point",
		b.world.state_hash() == b2.world.state_hash())

	# The strongest completeness check there is: saving the restored match
	# must produce the SAME dictionary. Any field the restore forgot -- or
	# invented -- shows up here by name, in the diff of two sorted JSONs.
	var json2 := SimSave.to_json(b2)
	_ok("save(restore(save(x))) == save(x)", json2 == json,
		"" if json2 == json else _first_difference(json, json2))

	# ── the behavioural test ────────────────────────────────────────────────
	_drive(a, 120.0)
	_drive(b2, 60.0)
	_ok("same tick after the same simulated time",
		a.world.tick == b2.world.tick,
		"%d vs %d" % [a.world.tick, b2.world.tick])
	_ok("same kills", a.world.damage.kills == b2.world.damage.kills,
		"%d vs %d" % [a.world.damage.kills, b2.world.damage.kills])
	_ok("same shots fired",
		a.world.weapons.shots_fired == b2.world.weapons.shots_fired,
		"%d vs %d" % [a.world.weapons.shots_fired, b2.world.weapons.shots_fired])
	_ok("same positions digest",
		_positions_digest(a.world) == _positions_digest(b2.world))
	_ok("same full state hash -- the restored match IS the match",
		a.world.state_hash() == b2.world.state_hash(),
		"0x%x vs 0x%x" % [a.world.state_hash(), b2.world.state_hash()])
	_ok("victory clocks agree",
		a.victory.elapsed_s == b2.victory.elapsed_s
		and a.victory.outcome == b2.victory.outcome)


## Point at the first place two JSON strings diverge, for a failure message
## that names the missing field instead of shrugging.
func _first_difference(x: String, y: String) -> String:
	var n: int = mini(x.length(), y.length())
	for i in range(n):
		if x.unicode_at(i) != y.unicode_at(i):
			var start: int = maxi(0, i - 60)
			return "at %d: ...%s... vs ...%s..." % [
				i, x.substr(start, 120), y.substr(start, 120)]
	return "lengths differ: %d vs %d" % [x.length(), y.length()]
