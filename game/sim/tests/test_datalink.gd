extends SceneTree
## The claim on the front page of the README, run end to end.
##
##     "a unit may kill something it cannot see at all, because an AWACS
##      150 km away is feeding it a track over datalink"
##
## That sentence is the project's headline pitch and, until the air roster was
## wired into the game, nothing in the repository demonstrated it. The track
## table has been per-FACTION rather than per-unit from the start, so datalink
## is architecturally free -- but "free" and "true" are different claims, and
## only one of them can be asserted.
##
## The scenario is cooperative engagement, which is the real-world form of the
## README's sentence. docs/02's radar horizon is
##
##     R = 4.12 x (sqrt(h_sensor) + sqrt(h_target))       kilometres, metres
##
## so a launcher with a 10 m mast cannot see a 20 m target past about 31 km,
## no matter how good its radar is or how long its missiles fly. An AEW&C
## aircraft at 9 km can see the same target from 400 km. Put the target at
## 60 km -- twice the launcher's horizon, well inside its missile's reach --
## and the shot is possible if and only if somebody else is looking.
##
##   Godot --headless --path game --script sim/tests/test_datalink.gd

const BLUE := 1
const RED := 2

var _pass := 0
var _fail := 0


func _ok(what: String, cond: bool, detail: String = "") -> void:
	if cond:
		_pass += 1
		print("    PASS  %s%s" % [what, "  " + detail if detail else ""])
	else:
		_fail += 1
		print("    FAIL  %s%s" % [what, "  " + detail if detail else ""])


func _horizon_km(h_sensor: float, h_target: float) -> float:
	return 4.12 * (sqrt(h_sensor) + sqrt(h_target))


func _settle(w: SimWorld, seconds: float) -> void:
	var dt := 0.2
	var n := int(seconds / dt)
	for k in range(n):
		w.solver.solve(dt, k)


## The best track this faction holds on ANYTHING.
##
## It cannot be "the track on entity N", because SimTrackTable keeps its
## entity mapping private on purpose -- docs/09 §1.3, a track is a hypothesis
## and never a pointer, which is what makes "the AI gets no information the
## player would not have" enforceable by the API rather than by discipline.
## A test is not entitled to an exemption from that, so the scenario is built
## with exactly ONE hostile entity in the world: any track blue holds is a
## track on the intruder, and no lookup is needed.
func _best_track(w: SimWorld, faction: int) -> SimTrack:
	var table := w.solver.table_for(faction)
	var best: SimTrack = null
	for id in table.track_ids():
		var t := table.get_track(id)
		if t != null and (best == null or t.quality > best.quality):
			best = t
	return best


func _initialize() -> void:
	print("")
	print("  BATTLE -- datalink: shooting what you cannot see")
	print("  " + "-".repeat(66))

	# ── geometry, stated before anything is built ────────────────────────
	var launcher_mast := 10.0
	var target_alt := 20.0
	var aew_alt := 9000.0
	var range_m := 60_000.0
	var h_launcher := _horizon_km(launcher_mast, target_alt)
	var h_aew := _horizon_km(aew_alt, target_alt)
	print("    the launcher's radar horizon on this target:  %6.1f km" % h_launcher)
	print("    the AEW aircraft's horizon on the same target: %6.1f km" % h_aew)
	print("    the target is placed at                        %6.1f km" % (range_m / 1000.0))
	_ok("the target is beyond the launcher's own horizon",
		range_m / 1000.0 > h_launcher, "%.1f > %.1f km" % [range_m / 1000.0, h_launcher])
	_ok("but well inside the AEW aircraft's",
		range_m / 1000.0 < h_aew, "%.1f < %.1f km" % [range_m / 1000.0, h_aew])

	# ── the world: a blue SAM battery, a red low-level intruder ──────────
	var w := SimWorld.new(9001)
	w.use_accumulator = false
	var e := w.entities

	var launcher := e.add("SAM battery", BLUE, 0.0, launcher_mast, 0.0,
		SimSignature.new(14.0), SimRoster.sensors_for("search", 4),
		SimTypes.Category.GROUND, launcher_mast)
	var intruder := e.add("low intruder", RED, 0.0, target_alt, range_m,
		SimSignature.new(6.0), [], SimTypes.Category.AIR, target_alt)

	# COMMAND_LINK, not ARH. docs/02 §5 is explicit that FIRE_CONTROL is
	# "required to launch a guided missile", and an AEW radar 120 km away
	# contributes TRACK, not FIRE_CONTROL -- so an active-homing missile is
	# correctly refused here and the first version of this test asserted the
	# wrong thing. COMMAND_LINK is the guidance docs/02 defines as "guided from
	# any networked track source", which IS the datalink weapon, and the gate
	# already requires only TRACK for it. The pillar was implemented; nothing
	# had ever exercised it.
	var sam := SimWeaponDef.new({
		"name": "long-range SAM",
		"guidance": SimTypes.Guidance.COMMAND_LINK,
		"max_range_km": 100.0,
	})
	var amraam := SimWeaponDef.new({
		"name": "active-homing missile",
		"guidance": SimTypes.Guidance.ARH,
		"max_range_km": 100.0,
	})

	# ── 1. alone, the battery has nothing ────────────────────────────────
	_settle(w, 20.0)
	var solo := _best_track(w, BLUE)
	_ok("alone, the battery holds NO track on the intruder", solo == null,
		"" if solo == null else "quality=%s" % SimTypes.quality_name(solo.quality))
	var r := SimWeaponGate.can_launch(sam, solo, range_m / 1000.0)
	_ok("and the missile is refused", not r.allowed, r.reason)

	# ── 2. put an AEW&C aircraft up, 120 km behind the battery ───────────
	var awacs := e.add("AEW&C", BLUE, 0.0, aew_alt, -120_000.0,
		SimSignature.new(90.0), SimRoster.sensors_for("aew", 4),
		SimTypes.Category.AIR, aew_alt)
	_settle(w, 20.0)
	var fused := _best_track(w, BLUE)
	_ok("with the AEW aircraft up, the FACTION holds a track", fused != null,
		"" if fused == null else "quality=%s, contributed by %s"
			% [SimTypes.quality_name(fused.quality),
			   ", ".join(fused.contributors)])
	if fused != null:
		r = SimWeaponGate.can_launch(sam, fused, range_m / 1000.0)
		_ok("and the battery -- which still cannot see it -- may shoot",
			r.allowed, r.reason)

		# The ladder must DISCRIMINATE, or "datalink" is just a global permit.
		# An active-homing missile needs its own fire-control solution and a
		# 120 km AEW cut does not provide one, so the same track that
		# authorises the networked shot must refuse this one.
		r = SimWeaponGate.can_launch(amraam, fused, range_m / 1000.0)
		_ok("but an ACTIVE-HOMING missile is still refused on the same track",
			not r.allowed, r.reason)

		# Cut the link and the shot goes with it -- this is what makes the
		# datalink a target rather than a background assumption (docs/02
		# pillar 2: jamming has to be able to break something).
		r = SimWeaponGate.can_launch(sam, fused, range_m / 1000.0, false)
		_ok("and jamming the datalink refuses it too", not r.allowed, r.reason)

	# ── 3. the part that stops this being a rubber stamp ─────────────────
	# Kill the AEW aircraft. The picture must go away again, or the test is
	# only asserting that adding a sensor adds a track.
	e.kill(awacs)
	_settle(w, 30.0)
	var after := _best_track(w, BLUE)
	var gone: bool = after == null or after.quality < SimTypes.TrackQuality.FIRE_CONTROL
	_ok("shoot the AEW aircraft down and the picture goes with it", gone,
		"no track" if after == null
			else "quality=%s" % SimTypes.quality_name(after.quality))
	r = SimWeaponGate.can_launch(sam, after, range_m / 1000.0)
	_ok("the same missile is refused again", not r.allowed, r.reason)

	print("  " + "-".repeat(66))
	print("  %d passed, %d failed" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
