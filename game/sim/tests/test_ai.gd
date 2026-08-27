extends SceneTree
## Tests for the AI. docs/09.
##
##     godot --path game --headless --script res://sim/tests/test_ai.gd
##
## A separate file from run_sim_tests.gd and test_spine.gd on purpose: four
## agents are building on one spine and a shared runner is a shared merge
## conflict.
##
## Half of this file tests that the AI DECIDES things. The other half tests that
## it decides them from the wrong information -- the uncertain, decaying,
## occasionally fictional picture its own sensors built -- because docs/09 §1
## is the whole design and an AI that quietly peeks is worth less than no AI.
##
## Note the asymmetry of privilege: THE TEST may read ground truth, inject
## tracks and corrupt the picture. That is exactly what makes it able to prove
## the AI cannot.

var _passed := 0
var _failed := 0


func _init() -> void:
	print("")
	print("  BATTLE -- AI tests (docs/09)")
	print("  " + "-".repeat(66))

	_suite_source_fence()
	_suite_threat_table()
	_suite_it_decides()
	_suite_weapon_gate()
	_suite_skill_dials()
	_suite_emcon_discipline()
	_suite_tracks_not_truth()
	_suite_ghost_track()
	_suite_null_sensor()
	_suite_blackout()
	_suite_retreat()
	_suite_economy()
	_suite_determinism()
	_suite_symmetry()

	print("  " + "-".repeat(66))
	if _failed == 0:
		print("  %d passed, 0 failed" % _passed)
	else:
		print("  %d passed, %d FAILED" % [_passed, _failed])
	print("")
	quit(1 if _failed > 0 else 0)


func _suite(suite_name: String) -> void:
	print("")
	print("  " + suite_name)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		_passed += 1
		print("    PASS  %s%s" % [label, ("  " + detail) if detail else ""])
	else:
		_failed += 1
		print("    FAIL  %s%s" % [label, ("  " + detail) if detail else ""])


# ── scenario construction ────────────────────────────────────────────────────

func _radar(mount := 200.0) -> SimSensorDef:
	return SimSensorDef.new({
		"name": "radar", "domain": SimTypes.Domain.RF_ACTIVE,
		"band": SimTypes.Band.X, "reference_range_km": 120.0,
		"mount_height_m": mount, "radar_gen": 5, "emits": true,
		"max_quality": SimTypes.TrackQuality.FIRE_CONTROL})


func _unit(w: SimWorld, unit_name: String, faction: int, owner: int,
		x: float, z: float, sensors: Array = [],
		category := SimTypes.Category.GROUND) -> int:
	var i := w.entities.add(unit_name, faction, x, 0.0, z,
		SimSignature.new(20.0), sensors, category, 3.0, owner)
	w.entities.set_damage_profile(i, SimTypes.DamageModel.ARMORED, 100.0,
		[500.0, 80.0, 45.0, 30.0, 20.0],
		[SimTypes.ArmorType.COMPOSITE, SimTypes.ArmorType.RHA,
			SimTypes.ArmorType.RHA, SimTypes.ArmorType.RHA,
			SimTypes.ArmorType.RHA], 3)
	w.entities.set_mobility(i, 15.0, 2.0, 0.6)
	w.entities.set_economy_profile(i, 900.0, 10.0, 1500.0, 3.0, 18.0, 50.0)
	return i


func _structure(w: SimWorld, unit_name: String, faction: int, owner: int,
		x: float, z: float) -> int:
	var i := w.entities.add(unit_name, faction, x, 0.0, z,
		SimSignature.new(60.0), [], SimTypes.Category.GROUND, 8.0, owner)
	w.entities.set_damage_profile(i, SimTypes.DamageModel.STRUCTURE, 400.0)
	w.entities.is_structure[i] = 1
	w.entities.set_economy_profile(i, 2000.0, 20.0)
	return i


## One AI (player 1, faction 1) with a base, a radar, four tanks and a scout,
## against a human army (player 0, faction 0) to its north.
func _scenario(seed_value: int, level: int, profile: int,
		with_sensors := true, enemy_z := 5000.0,
		enemy_x := 0.0) -> Dictionary:
	var w := SimWorld.new(seed_value)
	w.use_accumulator = false
	var setup := SimPlayerSetup.new({
		"name": "AI", "faction": SimPlayerSetup.Faction.RUSSIA,
		"skill": level, "doctrine": SimDoctrine.make(profile),
		"start_epoch": 4, "ceiling_epoch": 6})
	_structure(w, "factory", 1, 1, 0.0, -5000.0)
	var sensors: Array = [_radar()] if with_sensors else []
	_unit(w, "radar mast", 1, 1, 0.0, -5200.0, sensors)
	for k in range(4):
		_unit(w, "T-80", 1, 1, -300.0 + 200.0 * float(k), -4800.0)
	_unit(w, "scout car", 1, 1, 400.0, -4800.0)
	for k in range(3):
		_unit(w, "M1A2", 0, 0, enemy_x - 200.0 + 200.0 * float(k), enemy_z)
	# The human gets a PASSIVE receiver and nothing else: it sees exactly what
	# the AI chooses to radiate, which is what makes the EMCON dial measurable.
	_unit(w, "esm mast", 0, 0, enemy_x, enemy_z + 200.0, [SimSensorDef.new({
		"name": "ESM", "domain": SimTypes.Domain.RF_PASSIVE,
		"reference_range_km": 300.0, "mount_height_m": 200.0, "esm_gen": 4,
		"emits": false, "max_quality": SimTypes.TrackQuality.CONTACT})])
	var director := w.add_ai(1, 1, setup)
	w.economy.add_player(1, 12000.0, 4, 6)
	return {"world": w, "ai": director, "setup": setup}


func _inject(w: SimWorld, faction: int, truth: int, quality: int,
		x: float, z: float, emitting := false, bearing_only := false,
		category := SimTypes.Category.GROUND, vx := 0.0, vz := 0.0,
		cls := SimTypes.Classification.CLASS) -> SimTrack:
	return w.solver.table_for(faction).contribute(truth, quality, cls, 0.9,
		"injected", x, 0.0, z, vx, 0.0, vz, atan2(x, z), bearing_only,
		category, emitting)


# ═══════════════════════════════════════════════════════════════════════════
# 1. THE FENCE, ENFORCED BY THE BUILD RATHER THAN BY REVIEW
# ═══════════════════════════════════════════════════════════════════════════

## GDScript has no private members, so "the AI module is constructed without a
## reference to the entity store" (docs/09 §1.3) is enforced by the constructor
## AND by this: a scan of every line of code in sim/ai/ for the identifiers that
## would constitute a leak. One file is exempt -- the own-forces view IS the
## fence, and has to hold the store to refuse queries against it.
func _suite_source_fence() -> void:
	_suite("The leak cannot be written: sim/ai/ is scanned for it (docs/09 §1.3)")

	const FORBIDDEN := ["SimEntities", "SimWorld", "_truth_index", "table_for",
		"indices_of_faction", "solver", "ground_truth", "SimSensorSolver"]
	const EXEMPT := "sim_own_forces_view.gd"

	var files: Array = []
	for f in DirAccess.get_files_at("res://sim/ai"):
		if (f as String).ends_with(".gd"):
			files.append(f)
	files.sort()
	_ok("the AI package has files to scan", files.size() >= 4,
		"%d file(s)" % files.size())

	var offences := PackedStringArray()
	var scanned := 0
	for f in files:
		if f == EXEMPT:
			continue
		scanned += 1
		var fa := FileAccess.open("res://sim/ai/" + f, FileAccess.READ)
		var line_no := 0
		for raw in fa.get_as_text().split("\n"):
			line_no += 1
			var line: String = raw
			var hash_at := line.find("#")
			if hash_at >= 0:
				line = line.substr(0, hash_at)
			for token in FORBIDDEN:
				if line.contains(token):
					offences.append("%s:%d %s" % [f, line_no, token])
	_ok("NO file in sim/ai/ names the entity store, the world or the solver",
		offences.is_empty(),
		"; ".join(offences) if not offences.is_empty() else "%d file(s) clean" % scanned)

	# And the exemption is exactly one file, so a new file cannot quietly join
	# the list of things allowed to touch ground truth.
	var fence := FileAccess.open("res://sim/ai/" + EXEMPT, FileAccess.READ)
	_ok("the one exempt file is the fence itself, and it does hold the store",
		fence != null and fence.get_as_text().contains("var _e: SimEntities"))

	# The constructor is the other half. Anything wider is the docs/09 §1.1 bug.
	var src := FileAccess.open("res://sim/ai/sim_ai_director.gd", FileAccess.READ)
	var text := src.get_as_text()
	var ctor := text.substr(text.find("func _init("), 90)
	_ok("SimAiDirector._init takes a world view and a seeded stream, nothing else",
		ctor.contains("world_view: SimAiWorldView") and ctor.contains("seeded: SimRng")
			and not ctor.contains("store"))


# ═══════════════════════════════════════════════════════════════════════════
# 2. THE THREAT TABLE, docs/09 §3
# ═══════════════════════════════════════════════════════════════════════════

func _track(quality: int, x: float, z: float, emitting := false,
		bearing_only := false, category := SimTypes.Category.GROUND,
		vx := 0.0, vz := 0.0, age := 0.0,
		cls := SimTypes.Classification.CLASS) -> SimTrack:
	var t := SimTrack.new()
	t.track_id = 1
	t.quality = quality
	t.classification = cls
	t.pos_x = x
	t.pos_z = z
	t.vel_x = vx
	t.vel_z = vz
	t.emitting = emitting
	t.bearing_only = bearing_only
	t.category = category
	t.confidence = 0.9
	t.age_s = age
	return t


func _lone_director(profile: int, level := SimSkill.Level.VETERAN) -> SimAiDirector:
	var s := _scenario(5, level, profile)
	return s["ai"] as SimAiDirector


func _suite_threat_table() -> void:
	_suite("Threat assessment reads track QUALITY, not the truth behind it")

	var d := _lone_director(SimDoctrine.Profile.COMBINED_ARMS)
	d.has_home = false     # isolate the quality terms from the proximity term

	var tq1 := _track(SimTypes.TrackQuality.CONTACT, 0.0, 4000.0, false, true)
	var tq2 := _track(SimTypes.TrackQuality.TRACK, 0.0, 4000.0)
	var tq3 := _track(SimTypes.TrackQuality.FIRE_CONTROL, 0.0, 4000.0)
	_ok("a fire-control track outranks a track outranks a bearing",
		d.threat_score(tq3) > d.threat_score(tq2)
			and d.threat_score(tq2) > d.threat_score(tq1),
		"%.2f > %.2f > %.2f" % [d.threat_score(tq3), d.threat_score(tq2),
			d.threat_score(tq1)])
	_ok("nothing at all scores nothing",
		d.threat_score(null) == 0.0
			and d.threat_score(_track(SimTypes.TrackQuality.NONE, 0, 0)) == 0.0)

	var fresh := _track(SimTypes.TrackQuality.TRACK, 0.0, 4000.0, false, false,
		SimTypes.Category.GROUND, 0.0, 0.0, 0.0)
	var stale := _track(SimTypes.TrackQuality.TRACK, 0.0, 4000.0, false, false,
		SimTypes.Category.GROUND, 0.0, 0.0, 40.0)
	_ok("a decaying track is worth less than a fresh one",
		d.threat_score(stale) < d.threat_score(fresh) * 0.6,
		"%.2f vs %.2f" % [d.threat_score(stale), d.threat_score(fresh)])

	# docs/09 §3: "TQ3 on a high-value emitter -- COMMIT. Illuminators and AEW
	# aircraft are priority targets."
	var emitter := _track(SimTypes.TrackQuality.FIRE_CONTROL, 0.0, 4000.0, true)
	_ok("an emitter outranks a silent contact at the same quality",
		d.threat_score(emitter) > d.threat_score(tq3),
		"%.2f vs %.2f" % [d.threat_score(emitter), d.threat_score(tq3)])

	# docs/09 §5: Interdiction "hunts your tankers, oilers, AEW and supply
	# trucks instead of your army". The only thing that gives an enabler away
	# on a track is emitting, or orbiting slowly at altitude.
	var slow_air := _track(SimTypes.TrackQuality.FIRE_CONTROL, 0.0, 9000.0,
		false, false, SimTypes.Category.AIR, 0.0, 180.0)
	var fast_air := _track(SimTypes.TrackQuality.FIRE_CONTROL, 0.0, 9000.0,
		false, false, SimTypes.Category.AIR, 0.0, 420.0)
	var interdictor := _lone_director(SimDoctrine.Profile.INTERDICTION)
	interdictor.has_home = false
	var blitz := _lone_director(SimDoctrine.Profile.BLITZ)
	blitz.has_home = false
	_ok("INTERDICTION puts the slow, orbiting contact above the fighter",
		interdictor.threat_score(slow_air) > interdictor.threat_score(fast_air),
		"%.2f vs %.2f" % [interdictor.threat_score(slow_air),
			interdictor.threat_score(fast_air)])
	_ok("BLITZ puts the army first and ignores the enabler",
		blitz.threat_score(fast_air) > blitz.threat_score(slow_air),
		"%.2f vs %.2f" % [blitz.threat_score(fast_air),
			blitz.threat_score(slow_air)])
	_ok("the same two contacts, two doctrines, opposite answers",
		(interdictor.threat_score(slow_air) > interdictor.threat_score(fast_air))
			!= (blitz.threat_score(slow_air) > blitz.threat_score(fast_air)))

	# Proximity: something near the base is a threat whatever it is.
	d.has_home = true
	d.home_x = 0.0
	d.home_z = 0.0
	var near := _track(SimTypes.TrackQuality.TRACK, 0.0, 1000.0)
	var far := _track(SimTypes.TrackQuality.TRACK, 0.0, 100000.0)
	_ok("a contact near home outranks the same contact far away",
		d.threat_score(near) > d.threat_score(far))


# ═══════════════════════════════════════════════════════════════════════════
# 3. IT ACTUALLY DECIDES SOMETHING
# ═══════════════════════════════════════════════════════════════════════════

func _suite_it_decides() -> void:
	_suite("The AI forms groups, picks objectives and issues orders")

	# The contact is inside the tanks' own gun envelope, so the engagement half
	# of the decision loop has something it is allowed to do.
	var s := _scenario(31, SimSkill.Level.ELITE, SimDoctrine.Profile.BLITZ,
		true, -2000.0)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	_ok("and it says it is implemented", d.is_implemented())
	_ok("the spine's status agrees", w.subsystem_status()["ai"] == true)

	w.run_ticks(400)     # 20 s

	_ok("it holds tracks on the enemy it can actually see",
		d.memory.live_count() > 0, "%d contact(s)" % d.memory.live_count())
	_ok("it formed task groups", d.groups.size() > 0,
		"%d group(s)" % d.groups.size())
	var has_objective := false
	for g in d.groups:
		if (g as SimAiGroup).has_objective:
			has_objective = true
	_ok("with objectives on them", has_objective)
	_ok("it issued move orders", d.orders_moved > 0, "%d" % d.orders_moved)
	_ok("it issued engagement orders", d.orders_attacked > 0,
		"%d" % d.orders_attacked)
	_ok("and it logged why", d.decision_log.size() > 0,
		"%d entries" % d.decision_log.size())

	# The orders reached the sim through the ordinary command boundary.
	var moved := 0
	for i in w.entities.indices_of_owner(1):
		if w.entities.has_dest[i] == 1:
			moved += 1
	_ok("its units have real destinations, set through the command queue",
		moved > 0, "%d of %d" % [moved, w.entities.indices_of_owner(1).size()])

	# A Blitz AI attacks: its manoeuvre groups head TOWARD the contact, which
	# is north of it.
	var advanced := 0
	for i in w.entities.indices_of_owner(1):
		if w.entities.has_dest[i] == 1 and w.entities.dest_z[i] > -4500.0:
			advanced += 1
	_ok("a Blitz doctrine moves on the contact rather than sitting on its base",
		advanced > 0, "%d unit(s) ordered forward" % advanced)

	# docs/09 §1.6 asks for the debug view early: "render the AI's track table
	# beside ground truth and you can SEE what it believes".
	var shown := d.describe()
	_ok("it can show what it believes, for the docs/09 §1.6 debug view",
		shown.contains("posture") and shown.contains("live contact")
			and shown.contains("orders:"))

	# THE fence measurement, taken after a real match rather than in isolation:
	# the director never once asked about an index it does not own.
	_ok("it never groped at a unit it does not own",
		d.view.forces.denied_queries == 0,
		"%d denied" % d.view.forces.denied_queries)


# ═══════════════════════════════════════════════════════════════════════════
# 4. THE PLAYER'S WEAPON GATE, docs/09 §3
# ═══════════════════════════════════════════════════════════════════════════

func _suite_weapon_gate() -> void:
	_suite("It runs the same SimWeaponGate the player does")

	# No sensors at all: every contact below is one the test puts in its head.
	var s := _scenario(37, SimSkill.Level.ELITE, SimDoctrine.Profile.BLITZ, false)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector

	# A bearing-only cue on something that is not radiating. docs/09 §3:
	# "do not commit forces to a bearing" -- and there is no range to shoot at.
	for _t in range(120):
		_inject(w, 1, 900, SimTypes.TrackQuality.CONTACT, 0.0, -3000.0,
			false, true)
		w.run_ticks(1)
	_ok("a bearing-only contact produces no shot", d.orders_attacked == 0,
		"%d attack order(s)" % d.orders_attacked)
	var scout_tasked := false
	for g in d.groups:
		var group := g as SimAiGroup
		if group.role == SimAiGroup.Role.SCOUT and group.has_objective:
			scout_tasked = true
	_ok("but it cues a scout at the bearing instead", scout_tasked)

	# Now a real track, inside the tank's 4 km gun envelope. UNGUIDED needs TQ2.
	for _t in range(120):
		_inject(w, 1, 901, SimTypes.TrackQuality.TRACK, 0.0, -2000.0)
		w.run_ticks(1)
	_ok("a TQ2 track inside gun range clears the gate and is engaged",
		d.orders_attacked > 0, "%d attack order(s)" % d.orders_attacked)

	# The gate is the player's, not a copy: the AI's own reasoning is logged
	# with the gate's own reason string.
	var logged := false
	for line in d.decision_log:
		if (line as String).contains("engages TK") and (line as String).contains("clear to engage"):
			logged = true
	_ok("and the refusal/permission reason is the gate's own", logged)

	# Out of range: a contact 40 km away is never shot at by a tank.
	var s2 := _scenario(39, SimSkill.Level.ELITE, SimDoctrine.Profile.BLITZ, false)
	var w2 := s2["world"] as SimWorld
	var d2 := s2["ai"] as SimAiDirector
	for _t in range(120):
		_inject(w2, 1, 902, SimTypes.TrackQuality.FIRE_CONTROL, 0.0, 35000.0)
		w2.run_ticks(1)
	_ok("a perfect track 40 km away still gets no shot from a 4 km gun",
		d2.orders_attacked == 0, "%d attack order(s)" % d2.orders_attacked)


# ═══════════════════════════════════════════════════════════════════════════
# 5. DIFFICULTY IS DOCTRINE QUALITY, docs/09 §2
# ═══════════════════════════════════════════════════════════════════════════

## Ticks until this AI first acts on a contact that appears at t=0.
func _ticks_to_first_engagement(level: int) -> int:
	var s := _scenario(41, level, SimDoctrine.Profile.COMBINED_ARMS, false)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	for t in range(400):
		_inject(w, 1, 950, SimTypes.TrackQuality.FIRE_CONTROL, 0.0, -3000.0)
		w.run_ticks(1)
		if d.orders_attacked > 0:
			return t
	return -1


func _suite_skill_dials() -> void:
	_suite("Skill is reaction latency and commit threshold, never information")

	var recruit := _ticks_to_first_engagement(SimSkill.Level.RECRUIT)
	var veteran := _ticks_to_first_engagement(SimSkill.Level.VETERAN)
	var elite := _ticks_to_first_engagement(SimSkill.Level.ELITE)
	_ok("every tier eventually acts",
		recruit > 0 and veteran > 0 and elite > 0,
		"recruit %d, veteran %d, elite %d ticks" % [recruit, veteran, elite])
	_ok("ELITE reacts faster than VETERAN reacts faster than RECRUIT",
		elite < veteran and veteran < recruit,
		"%.1fs < %.1fs < %.1fs" % [elite / 20.0, veteran / 20.0, recruit / 20.0])
	_ok("and the delays are the docs/09 §2 numbers, not invented ones",
		absf(recruit / 20.0 - SimSkill.reaction_seconds(SimSkill.Level.RECRUIT)) < 1.0
			and absf(elite / 20.0 - SimSkill.reaction_seconds(SimSkill.Level.ELITE)) < 1.0)

	# The commit threshold: a Recruit waits for TQ3, an Elite acts on a TQ1 cue.
	# Given nothing better than a TQ2 track, the Recruit will not commit a
	# manoeuvre group to it and the Elite will.
	var committed := {}
	for level in [SimSkill.Level.RECRUIT, SimSkill.Level.ELITE]:
		var s := _scenario(43, level, SimDoctrine.Profile.BLITZ, false)
		var w := s["world"] as SimWorld
		var d := s["ai"] as SimAiDirector
		for _t in range(300):
			_inject(w, 1, 951, SimTypes.TrackQuality.TRACK, 0.0, 2000.0)
			w.run_ticks(1)
		var on_track := false
		for g in d.groups:
			var group := g as SimAiGroup
			if group.role == SimAiGroup.Role.MAIN and group.objective_track >= 0:
				on_track = true
		committed[level] = on_track
	_ok("a RECRUIT will not commit an army to a TQ2 track (it waits for TQ3)",
		committed[SimSkill.Level.RECRUIT] == false)
	_ok("an ELITE commits on it", committed[SimSkill.Level.ELITE] == true)


# ═══════════════════════════════════════════════════════════════════════════
# 6. EMCON, docs/09 §2 -- the most visible difficulty dial there is
# ═══════════════════════════════════════════════════════════════════════════

func _emcon_census(w: SimWorld, owner: int) -> Dictionary:
	var out := {"silent": 0, "receive": 0, "radiate": 0}
	for i in w.entities.indices_of_owner(owner):
		match w.entities.emcon[i]:
			SimTypes.Emcon.SILENT: out["silent"] += 1
			SimTypes.Emcon.RECEIVE: out["receive"] += 1
			SimTypes.Emcon.RADIATE: out["radiate"] += 1
	return out


func _suite_emcon_discipline() -> void:
	_suite("EMCON discipline is a skill dial and it reaches the entity store")

	var careless := _scenario(51, SimSkill.Level.RECRUIT,
		SimDoctrine.Profile.ATTRITION)
	var disciplined := _scenario(51, SimSkill.Level.ELITE,
		SimDoctrine.Profile.SENSOR_DOMINANCE)
	(careless["world"] as SimWorld).run_ticks(300)
	(disciplined["world"] as SimWorld).run_ticks(300)

	var c := _emcon_census(careless["world"] as SimWorld, 1)
	var e := _emcon_census(disciplined["world"] as SimWorld, 1)
	_ok("a RECRUIT radiates with everything it owns", c["radiate"] >= 6,
		str(c))
	_ok("an ELITE runs its shooters silent", e["silent"] >= 4, str(e))
	_ok("and its emissions are strictly fewer", e["radiate"] < c["radiate"],
		"%d vs %d radiating" % [e["radiate"], c["radiate"]])
	_ok("the AI issued those as ordinary EMCON orders through the queue",
		(disciplined["ai"] as SimAiDirector).orders_emcon > 0)

	# The point of the dial: the careless one is visible to the other side.
	var seen_by_human := (careless["world"] as SimWorld).solver.table_for(0).count()
	_ok("which is why the careless AI is the one the player can see",
		seen_by_human > 0, "%d track(s) on it" % seen_by_human)


# ═══════════════════════════════════════════════════════════════════════════
# 7. IT ACTS ON THE PICTURE, NOT ON THE WORLD (docs/09 §1.5 offset truth)
# ═══════════════════════════════════════════════════════════════════════════

func _suite_tracks_not_truth() -> void:
	_suite("It moves on the TRACK, not on the thing the track is about")

	# The enemy is due north at (0, 5000). The AI has no sensors, and the test
	# tells it -- falsely -- that the contact is 6 km to the east of that.
	var s := _scenario(61, SimSkill.Level.ELITE, SimDoctrine.Profile.BLITZ, false,
		5000.0, 0.0)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	var lie_x := 6000.0
	var lie_z := 5000.0
	for _t in range(300):
		_inject(w, 1, 970, SimTypes.TrackQuality.FIRE_CONTROL, lie_x, lie_z)
		w.run_ticks(1)

	# Only the manoeuvre groups: a sensor picket deliberately sits between home
	# and the contact, so measuring it would measure nothing.
	var committed := PackedInt32Array()
	for g in d.groups:
		var group := g as SimAiGroup
		if group.role == SimAiGroup.Role.MAIN and group.objective_track >= 0:
			for m in group.members:
				committed.append(m)
	var toward_lie := 0
	var toward_truth := 0
	for i in committed:
		if w.entities.has_dest[i] == 0:
			continue
		var dx := w.entities.dest_x[i]
		var dz := w.entities.dest_z[i]
		var to_lie := sqrt(pow(dx - lie_x, 2.0) + pow(dz - lie_z, 2.0))
		var to_truth := sqrt(pow(dx - 0.0, 2.0) + pow(dz - 5000.0, 2.0))
		if to_lie < to_truth:
			toward_lie += 1
		elif to_truth < to_lie:
			toward_truth += 1
	_ok("EVERY unit it committed went at the believed position",
		toward_lie > 0 and toward_truth == 0,
		"%d toward the track, %d toward the truth" % [toward_lie, toward_truth])


# ═══════════════════════════════════════════════════════════════════════════
# 8. THE GHOST TRACK -- a non-cheating AI must be foolable (docs/09 §1.5)
# ═══════════════════════════════════════════════════════════════════════════

func _suite_ghost_track() -> void:
	_suite("It can be fooled by a contact backed by no entity at all")

	var s := _scenario(71, SimSkill.Level.ELITE, SimDoctrine.Profile.BLITZ, false,
		40000.0)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector

	# Truth index -12345 is not an entity and never will be. This is a chaff
	# bloom, a DRFM false target, or a decoy: docs/09 §1.3 says the track model
	# has to be able to express it, and this is the proof.
	var ghost_x := 1500.0
	var ghost_z := -3000.0
	var ghost_id := -1
	for _t in range(200):
		var t := _inject(w, 1, -12345, SimTypes.TrackQuality.FIRE_CONTROL,
			ghost_x, ghost_z, true)
		ghost_id = t.track_id
		w.run_ticks(1)

	_ok("the ghost is a real track in its picture", ghost_id > 0)
	var engaged := false
	for line in d.decision_log:
		if (line as String).contains("engages TK%d" % ghost_id):
			engaged = true
	_ok("IT SHOOTS AT THE GHOST -- and spending munitions on a decoy is the "
		+ "feature", engaged and d.orders_attacked > 0,
		"%d attack order(s)" % d.orders_attacked)
	var committed := false
	for g in d.groups:
		if (g as SimAiGroup).objective_track == ghost_id:
			committed = true
	_ok("and it committed a battlegroup to it", committed)


# ═══════════════════════════════════════════════════════════════════════════
# 9. THE NULL-SENSOR TEST, docs/09 §1.5 -- "the strongest and the cheapest"
# ═══════════════════════════════════════════════════════════════════════════

## Everything this AI does, tick by tick, reduced to one number: where each of
## its own units was told to go, what emission state it was put in, and how many
## orders of each kind it has issued.
func _behaviour_signature(w: SimWorld, d: SimAiDirector, ticks: int) -> int:
	var buf := PackedFloat64Array()
	for _t in range(ticks):
		w.run_ticks(1)
		for i in w.entities.indices_of_owner(1):
			buf.append(float(w.entities.has_dest[i]))
			buf.append(snappedf(w.entities.dest_x[i], 0.01))
			buf.append(snappedf(w.entities.dest_z[i], 0.01))
			buf.append(float(w.entities.emcon[i]))
		buf.append(float(d.orders_moved))
		buf.append(float(d.orders_attacked))
		buf.append(float(d.orders_emcon))
	return hash(buf)


func _suite_null_sensor() -> void:
	_suite("A blind AI behaves identically whatever the enemy is doing (§1.5)")

	# Two worlds, same seed, same AI, same own army. The ONLY difference is
	# where the enemy is -- and the AI has no sensors, so it cannot know.
	# If a single leak existed anywhere in the decision path, these two numbers
	# would differ.
	var a := _scenario(81, SimSkill.Level.WARLORD, SimDoctrine.Profile.BLITZ,
		false, 6000.0, 0.0)
	var b := _scenario(81, SimSkill.Level.WARLORD, SimDoctrine.Profile.BLITZ,
		false, -9000.0, 12000.0)
	var sig_a := _behaviour_signature(a["world"] as SimWorld,
		a["ai"] as SimAiDirector, 600)
	var sig_b := _behaviour_signature(b["world"] as SimWorld,
		b["ai"] as SimAiDirector, 600)

	_ok("THE ENTIRE BEHAVIOUR STREAM IS IDENTICAL", sig_a == sig_b,
		"%d vs %d" % [sig_a, sig_b])
	_ok("it never fires at anything",
		(a["ai"] as SimAiDirector).orders_attacked == 0
			and (b["ai"] as SimAiDirector).orders_attacked == 0)
	_ok("it holds no contacts at all",
		(a["ai"] as SimAiDirector).memory.count() == 0)
	# It is blind, not paralysed: docs/09 §1.5 wants active search, and a blind
	# AI that stands still is as wrong as one that walks to your base.
	_ok("but it does search -- blind is not paralysed",
		(a["ai"] as SimAiDirector).orders_moved > 0,
		"%d move order(s)" % (a["ai"] as SimAiDirector).orders_moved)
	var searching := false
	for g in (a["ai"] as SimAiDirector).groups:
		if (g as SimAiGroup).state == SimAiGroup.State.SEARCHING:
			searching = true
	_ok("with a group actually in the search state", searching)


# ═══════════════════════════════════════════════════════════════════════════
# 10. BLACKOUT, docs/09 §1.5 -- degrade to last known position
# ═══════════════════════════════════════════════════════════════════════════

func _suite_blackout() -> void:
	_suite("Lose the contact and it goes to where the contact WAS")

	var s := _scenario(91, SimSkill.Level.ELITE, SimDoctrine.Profile.SENSOR_DOMINANCE,
		false)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	var seen_x := 4000.0
	var seen_z := 3000.0
	for _t in range(200):
		_inject(w, 1, 980, SimTypes.TrackQuality.FIRE_CONTROL, seen_x, seen_z,
			false, false, SimTypes.Category.GROUND, 0.0, 0.0)
		w.run_ticks(1)
	_ok("it held the contact while it could see it", d.memory.live_count() == 1)

	# The picture goes dark. The track decays out of the table entirely.
	w.run_ticks(1400)
	_ok("the track is gone from the picture", d.memory.live_count() == 0,
		"%d live" % d.memory.live_count())
	_ok("but the AI still remembers there was something there",
		d.memory.stale_beliefs(d.elapsed_s).size() == 1)
	var b := d.memory.stale_beliefs(d.elapsed_s)[0] as SimAiMemory.Belief
	_ok("with the last position it actually observed",
		absf(b.x - seen_x) < 1.0 and absf(b.z - seen_z) < 1.0,
		"(%.0f, %.0f)" % [b.x, b.z])
	_ok("and it stops shooting at it once it is gone",
		not d.view.tracks.get_track(b.track_id))


# ═══════════════════════════════════════════════════════════════════════════
# 11. RETREAT WHEN LOSING
# ═══════════════════════════════════════════════════════════════════════════

func _suite_retreat() -> void:
	_suite("It pulls back when a group is being taken apart")

	var s := _scenario(101, SimSkill.Level.ELITE, SimDoctrine.Profile.BLITZ, false)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	for _t in range(200):
		_inject(w, 1, 990, SimTypes.TrackQuality.FIRE_CONTROL, 0.0, 3000.0)
		w.run_ticks(1)
	var advancing := false
	for g in d.groups:
		var group := g as SimAiGroup
		if group.role == SimAiGroup.Role.MAIN \
				and group.state in [SimAiGroup.State.ADVANCING,
					SimAiGroup.State.ENGAGING]:
			advancing = true
	_ok("it is on the attack to begin with", advancing)

	# Take the group apart. Structure is SimDamage's to write, but this is a
	# test standing in for it until the damage agent lands.
	for i in w.entities.indices_of_owner(1):
		if not w.entities.is_structure[i] == 1:
			w.entities.structure[i] = w.entities.structure_max[i] * 0.15
	for _t in range(60):
		_inject(w, 1, 990, SimTypes.TrackQuality.FIRE_CONTROL, 0.0, 3000.0)
		w.run_ticks(1)

	var withdrawing := false
	for g in d.groups:
		var group := g as SimAiGroup
		if group.role == SimAiGroup.Role.MAIN \
				and group.state == SimAiGroup.State.WITHDRAWING:
			withdrawing = true
	_ok("and it breaks off when its strength collapses", withdrawing,
		"posture %s" % SimAiDirector.POSTURE_NAMES.get(d.posture, "?"))

	var heading_home := 0
	for i in w.entities.indices_of_owner(1):
		if w.entities.has_dest[i] == 1 and w.entities.dest_z[i] < -3000.0:
			heading_home += 1
	_ok("with its units ordered back toward its own base", heading_home > 0,
		"%d unit(s)" % heading_home)


# ═══════════════════════════════════════════════════════════════════════════
# 12. ECONOMY BEHAVIOUR
# ═══════════════════════════════════════════════════════════════════════════

func _suite_economy() -> void:
	_suite("It spends: production mix from doctrine, expansion, epoch")

	# The mix is doctrine, not a constant.
	var sensor_heavy := SimAiPlan.desired_mix(
		SimDoctrine.make(SimDoctrine.Profile.SENSOR_DOMINANCE),
		SimSkill.Level.ELITE)
	var blitz := SimAiPlan.desired_mix(
		SimDoctrine.make(SimDoctrine.Profile.BLITZ), SimSkill.Level.RECRUIT)
	_ok("Sensor Dominance wants far more sensors than Blitz",
		sensor_heavy["sensors"] > blitz["sensors"] * 2.0,
		"%.2f vs %.2f" % [sensor_heavy["sensors"], blitz["sensors"]])
	_ok("Blitz wants more of the line", blitz["line"] > sensor_heavy["line"])
	_ok("and every mix is a distribution",
		absf(sensor_heavy["sensors"] + sensor_heavy["air_defence"]
			+ sensor_heavy["supply"] + sensor_heavy["line"] - 1.0) < 0.001)

	# The deficit rule picks what is missing, deterministically.
	var counts := {"sensors": 0, "air_defence": 0, "supply": 0, "line": 10}
	_ok("with no sensors at all, sensors are what it asks for",
		SimAiPlan.biggest_deficit(counts, sensor_heavy) == "sensors")

	# End to end, against the real economy: an AI with credits builds a base
	# and puts things in a production queue.
	var s := _scenario(111, SimSkill.Level.ELITE,
		SimDoctrine.Profile.SENSOR_DOMINANCE)
	var w := s["world"] as SimWorld
	var d := s["ai"] as SimAiDirector
	# A factory the ECONOMY placed, so it knows what the building is. The
	# hand-placed one in the scenario is scenery as far as production goes.
	w.economy.place_starting_unit(1, "power_plant", -900.0, -5200.0)
	w.economy.place_starting_unit(1, "heavy_factory", -900.0, -4900.0)
	var before := w.commands.submitted
	var units_before := w.entities.indices_of_owner(1).size()
	w.run_ticks(1200)

	_ok("it issues production and construction requests", d.orders_production > 0,
		"%d request(s)" % d.orders_production)
	_ok("through the same command queue as everything else",
		w.commands.submitted > before)
	_ok("and the economy accepted them: something is queued or being built",
		w.economy.queue_of(1).size() > 0
			or w.entities.indices_of_owner(1).size() > units_before,
		"%d queued, %d -> %d unit(s)" % [w.economy.queue_of(1).size(),
			units_before, w.entities.indices_of_owner(1).size()])
	_ok("it spent real credits doing it", w.economy.credits(1) < 12000.0,
		"%.0f cr left" % w.economy.credits(1))

	# The build ORDER is the doctrine's, not a constant.
	var sensor_first := SimAiPlan.base_build_order(
		SimDoctrine.make(SimDoctrine.Profile.SENSOR_DOMINANCE))
	var blitz_first := SimAiPlan.base_build_order(
		SimDoctrine.make(SimDoctrine.Profile.BLITZ))
	_ok("Sensor Dominance puts its radar station up before Blitz does",
		Array(sensor_first).find("fixed_radar")
			< Array(blitz_first).find("fixed_radar"))
	_ok("and a Fortress puts its SAM belt up early",
		Array(SimAiPlan.base_build_order(
			SimDoctrine.make(SimDoctrine.Profile.FORTRESS))).find("fixed_sam") <= 4)


# ═══════════════════════════════════════════════════════════════════════════
# 13. DETERMINISM, docs/06
# ═══════════════════════════════════════════════════════════════════════════

func _suite_determinism() -> void:
	_suite("Same seed, same match, same result (docs/06)")

	var hashes := []
	var logs := []
	var counters := []
	for run in range(2):
		# Close enough that shooting, moving, producing and adapting all happen
		# inside the window -- a determinism test over an idle match proves
		# nothing.
		var s := _scenario(121, SimSkill.Level.PROFESSIONAL,
			SimDoctrine.Profile.COMBINED_ARMS, true, -2000.0)
		var w := s["world"] as SimWorld
		var d := s["ai"] as SimAiDirector
		w.run_ticks(600)
		hashes.append(w.state_hash())
		logs.append("\n".join(PackedStringArray(d.decision_log)))
		counters.append([d.orders_moved, d.orders_attacked, d.orders_emcon,
			d.orders_production, d.posture, d.groups.size()])

	_ok("the world state hash is identical", hashes[0] == hashes[1],
		"%d vs %d" % [hashes[0], hashes[1]])
	_ok("the AI's decision log is identical, line for line",
		logs[0] == logs[1])
	_ok("and so is every order counter", counters[0] == counters[1],
		str(counters[0]))
	_ok("the log is not empty, so that comparison means something",
		(logs[0] as String).length() > 0)

	# A different seed must actually change the seeded decisions -- otherwise
	# the stream is not being used and the determinism above is vacuous.
	var route_a := _search_route(7)
	var route_b := _search_route(9)
	_ok("a different seed produces a different search route",
		route_a != route_b)
	_ok("the same seed reproduces the same one", _search_route(7) == route_a)


func _search_route(seed_value: int) -> String:
	var s := _scenario(seed_value, SimSkill.Level.ELITE,
		SimDoctrine.Profile.BLITZ, false)
	var d := s["ai"] as SimAiDirector
	d.home_x = 0.0
	d.home_z = 0.0
	d.has_home = true
	var out := PackedStringArray()
	for k in range(6):
		var p := d._next_search_point()
		out.append("%.0f,%.0f" % [p[0], p[1]])
	return "|".join(out)


# ═══════════════════════════════════════════════════════════════════════════
# 14. SYMMETRY, docs/09 §1.5 -- two identical AIs must play identically
# ═══════════════════════════════════════════════════════════════════════════

func _suite_symmetry() -> void:
	_suite("Two identical AIs, mirrored, play the same game (§1.5)")

	var w := SimWorld.new(131)
	w.use_accumulator = false
	var directors := []
	for side in range(2):
		var sign_ := 1.0 if side == 0 else -1.0
		var reach := 2000.0
		var pid := side
		var setup := SimPlayerSetup.new({
			"name": "AI %d" % side, "faction": SimPlayerSetup.Faction.US if side == 0
				else SimPlayerSetup.Faction.RUSSIA,
			"skill": SimSkill.Level.VETERAN,
			"doctrine": SimDoctrine.make(SimDoctrine.Profile.COMBINED_ARMS),
			"start_epoch": 4, "ceiling_epoch": 5})
		_structure(w, "factory", side, pid, 0.0, reach * 1.15 * sign_)
		_unit(w, "radar mast", side, pid, 0.0, reach * 1.2 * sign_, [_radar()])
		for k in range(4):
			_unit(w, "tank", side, pid, (-300.0 + 200.0 * float(k)) * sign_,
				reach * sign_)
		_unit(w, "scout car", side, pid, 400.0 * sign_, reach * sign_)
		directors.append(w.add_ai(pid, side, setup))
		w.economy.add_player(pid, 8000.0, 4, 5)

	w.run_ticks(800)
	var a := directors[0] as SimAiDirector
	var b := directors[1] as SimAiDirector
	_ok("both AIs found the other side", a.memory.count() > 0 and b.memory.count() > 0,
		"%d vs %d contact(s)" % [a.memory.count(), b.memory.count()])
	_ok("both reached the same posture", a.posture == b.posture,
		"%s vs %s" % [SimAiDirector.POSTURE_NAMES.get(a.posture, "?"),
			SimAiDirector.POSTURE_NAMES.get(b.posture, "?")])
	_ok("both formed the same number of groups",
		a.groups.size() == b.groups.size())
	# HONEST TOLERANCE, and it is worth saying why exact equality is the wrong
	# assertion here. The two sides are mirrored in POSITION but not in every
	# input: each AI gets its own forked RNG stream (by design -- two opponents
	# that roll the same numbers are one opponent), and every unit the economy
	# spawns gets a sensor phase offset from a world-wide serial, so the two
	# radars revisit on different ticks. Both are properties of the simulation
	# rather than of the AI. What must hold is that neither side is playing a
	# different game: same posture, same group count, engagement volume within a
	# few orders of each other. A leak on one side would not look like this; it
	# would look like one side shooting before it had a track.
	var attack_gap: int = absi(a.orders_attacked - b.orders_attacked)
	var move_gap: int = absi(a.orders_moved - b.orders_moved)
	_ok("both actually fought", a.orders_attacked > 0 and b.orders_attacked > 0,
		"%d vs %d engagement order(s)" % [a.orders_attacked, b.orders_attacked])
	_ok("and neither out-fought the other by more than the sensor stagger",
		attack_gap <= maxi(2, int(0.1 * float(a.orders_attacked))),
		"gap %d (%d vs %d)" % [attack_gap, a.orders_attacked, b.orders_attacked])
	_ok("with the same manoeuvre volume", move_gap <= 3,
		"gap %d (%d vs %d)" % [move_gap, a.orders_moved, b.orders_moved])
	_ok("and neither could see the other's picture",
		a.view.tracks.faction == 0 and b.view.tracks.faction == 1)
	_ok("nor reached for a unit it does not own",
		a.view.forces.denied_queries == 0 and b.view.forces.denied_queries == 0)
