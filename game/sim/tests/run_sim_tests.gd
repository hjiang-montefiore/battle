extends SceneTree
## Headless test suite for the simulation core.
##
##     godot --path game --headless --script res://sim/tests/run_sim_tests.gd
##
## Exits 0 on success, 1 on any failure, so CI can gate on it. The sensor solver
## and the gating matrix are full of numbers that need verifying, and docs/06
## makes headless testability the first reason for the engine boundary -- this
## file is that reason being cashed in.
##
## Wherever docs/02 or docs/11 states a figure, the test asserts against the
## PUBLISHED figure rather than against whatever the code happens to produce.

const P := preload("res://sim/sensing/sim_propagation.gd")

var _passed := 0
var _failed := 0
var _current := ""


func _init() -> void:
	print("")
	print("  BATTLE -- simulation core tests")
	print("  " + "-".repeat(66))

	_suite_propagation()
	_suite_horizon()
	_suite_stealth_cliff()
	_suite_emission_asymmetry()
	_suite_track_ladder()
	_suite_weapon_gating()
	_suite_cooperative_engagement()
	_suite_look_down_cliff()
	_suite_jamming()
	_suite_determinism()

	print("  " + "-".repeat(66))
	if _failed == 0:
		print("  %d passed, 0 failed" % _passed)
	else:
		print("  %d passed, %d FAILED" % [_passed, _failed])
	print("")
	quit(1 if _failed > 0 else 0)


# ── assertions ───────────────────────────────────────────────────────────────

func _suite(name: String) -> void:
	_current = name
	print("")
	print("  " + name)


func _ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		_passed += 1
		print("    PASS  %s%s" % [label, ("  " + detail) if detail else ""])
	else:
		_failed += 1
		print("    FAIL  %s%s" % [label, ("  " + detail) if detail else ""])


func _near(label: String, got: float, want: float, tol: float) -> void:
	var d := absf(got - want)
	_ok(label, d <= tol, "got %.3f, expected %.3f +/- %.3f" % [got, want, tol])


# ── docs/02 §3 -- the two propagation laws ───────────────────────────────────

func _suite_propagation() -> void:
	_suite("Propagation laws (docs/02 §3)")

	# Two-way: R = ref * rcs^0.25
	_near("1 m^2 target sits at the reference range",
		P.active_range_km(100.0, 1.0), 100.0, 0.01)
	_near("16 m^2 target doubles the range (16^0.25 = 2)",
		P.active_range_km(100.0, 16.0), 200.0, 0.01)

	# The doc's own claim: halving RCS costs only ~16% of range.
	var full := P.active_range_km(100.0, 1.0)
	var half := P.active_range_km(100.0, 0.5)
	var loss := (1.0 - half / full) * 100.0
	_near("halving RCS costs ~16% of range, so incremental stealth is worthless",
		loss, 15.9, 0.3)

	# One-way: R = ref * power^0.5
	_near("quadrupling emitted power doubles passive range",
		P.passive_range_km(100.0, 4.0), 200.0, 0.01)


# ── docs/02 §4 -- the horizon table, verbatim ────────────────────────────────

func _suite_horizon() -> void:
	_suite("Radar horizon (docs/02 §4 -- every published row)")
	_near("ground radar 10 m vs sea-skimmer 5 m  = 22 km",
		P.horizon_km(10.0, 5.0), 22.0, 0.5)
	_near("destroyer mast 30 m vs sea-skimmer 5 m = 32 km",
		P.horizon_km(30.0, 5.0), 32.0, 0.5)
	_near("destroyer mast 30 m vs fighter 6000 m  = 342 km",
		P.horizon_km(30.0, 6000.0), 342.0, 1.0)
	_near("AEW&C 9000 m vs sea-skimmer 5 m        = 400 km",
		P.horizon_km(9000.0, 5.0), 400.0, 1.0)
	_near("AEW&C 9000 m vs fighter 6000 m         = 710 km",
		P.horizon_km(9000.0, 6000.0), 710.0, 1.0)

	# The consequence the doc draws: 32 km of warning against a Mach 0.9
	# sea-skimmer is about 100 seconds.
	var warning_s := (P.horizon_km(30.0, 5.0) * 1000.0) / (0.9 * 340.0)
	_near("32 km of warning against a Mach 0.9 sea-skimmer is ~100 s",
		warning_s, 104.0, 8.0)


# ── docs/02 §3 -- the stealth cliff, with the doc's own worked example ───────

func _suite_stealth_cliff() -> void:
	_suite("The stealth cliff (docs/02 §3 worked example)")

	# "A radar that sees the first at 200 km sees the second at 11 km."
	var ref := 200.0 / pow(10.0, 0.25)          # calibrate to a 10 m^2 fighter
	var loaded := P.active_range_km(ref, 10.0)
	var stealth := P.active_range_km(ref, 0.0001)
	_near("10 m^2 fighter detected at 200 km", loaded, 200.0, 0.5)
	_near("0.0001 m^2 fighter detected at 11 km", stealth, 11.25, 0.5)
	_near("100000x RCS reduction is a 17.8x range factor",
		loaded / stealth, 17.78, 0.1)


# ── docs/02 §3, §7.1 -- radiating is dangerous ───────────────────────────────

func _suite_emission_asymmetry() -> void:
	_suite("Emission asymmetry -- why EMCON is agonising (docs/02 §3, §7.1)")

	var adv := P.esm_advantage(3, 3)
	_ok("a Gen 3 radar is heard at 1.5-3x its own detection range",
		adv >= 1.5 and adv <= 3.0, "advantage %.2f" % adv)

	# R5 AESA/LPI partially defeats the asymmetry; P5 ESM re-closes it.
	var lpi := P.esm_advantage(5, 3)
	var lpi_vs_p5 := P.esm_advantage(5, 5)
	_ok("R5 LPI shrinks the ESM advantage", lpi < adv,
		"%.2f -> %.2f" % [adv, lpi])
	_ok("P5 ESM claws it back against LPI", lpi_vs_p5 > lpi,
		"%.2f -> %.2f" % [lpi, lpi_vs_p5])

	# A SILENT unit gives ESM nothing at all.
	var w := SimWorld.new()
	var quiet := w.entities.add("quiet ship", 1, 0, 10, 0,
		SimSignature.new(500.0), [_radar("hull radar", 60.0, 30.0)],
		SimTypes.Category.SURFACE)
	w.entities.emcon[quiet] = SimTypes.Emcon.SILENT
	_near("a SILENT unit emits nothing for ESM to hear",
		w.entities.emitted_power(quiet), 0.0, 1e-9)
	w.entities.emcon[quiet] = SimTypes.Emcon.RADIATE
	_ok("the same unit radiating is audible",
		w.entities.emitted_power(quiet) > 0.0)


# ── docs/02 §5 -- the ladder, and decay down it ──────────────────────────────

func _suite_track_ladder() -> void:
	_suite("Track quality ladder and decay (docs/02 §5)")

	var t := SimTrack.new()
	t.refresh(SimTypes.TrackQuality.FIRE_CONTROL, SimTypes.Classification.TYPE, 1.0, "illuminator")
	_ok("a fresh illuminator contact is FIRE_CONTROL",
		t.quality == SimTypes.TrackQuality.FIRE_CONTROL)

	# Unsupported, it degrades a rung at a time rather than vanishing.
	t.supported_now = false
	t.decay(4.0)
	_ok("unsupported FIRE_CONTROL decays to TRACK",
		t.quality == SimTypes.TrackQuality.TRACK,
		SimTypes.quality_name(t.quality))
	t.decay(13.0)
	_ok("TRACK then decays to CONTACT",
		t.quality == SimTypes.TrackQuality.CONTACT,
		SimTypes.quality_name(t.quality))
	var alive := t.decay(50.0)
	_ok("and finally goes cold", not alive and t.quality == SimTypes.TrackQuality.NONE)

	# Classification is a SEPARATE axis: a precise solution on an unknown.
	var u := SimTrack.new()
	u.refresh(SimTypes.TrackQuality.FIRE_CONTROL, SimTypes.Classification.UNKNOWN, 1.0, "fc radar")
	_ok("TQ3 on an UNKNOWN contact is representable -- and should be tense",
		u.quality == SimTypes.TrackQuality.FIRE_CONTROL
		and u.classification == SimTypes.Classification.UNKNOWN)


# ── docs/02 §5 -- weapon gating, the whole table ─────────────────────────────

func _suite_weapon_gating() -> void:
	_suite("Weapon gating (docs/02 §5) -- pillar 1")

	var contact := _track(SimTypes.TrackQuality.CONTACT)
	var track := _track(SimTypes.TrackQuality.TRACK)
	var fc := _track(SimTypes.TrackQuality.FIRE_CONTROL)

	var sarh := SimWeaponDef.new({"name": "SARH SAM",
		"guidance": SimTypes.Guidance.SARH, "max_range_km": 40.0})
	_ok("SARH refused on a TRACK",
		not SimWeaponGate.can_launch(sarh, track, 20.0).allowed,
		SimWeaponGate.can_launch(sarh, track, 20.0).reason)
	_ok("SARH clear on FIRE_CONTROL",
		SimWeaponGate.can_launch(sarh, fc, 20.0).allowed)

	# The SEAD duel: the illuminator dying mid-flight sends the round stupid.
	fc.quality = SimTypes.TrackQuality.TRACK
	_ok("SARH round goes ballistic when the illuminator is killed mid-flight",
		not SimWeaponGate.still_supported(SimTypes.Guidance.SARH, fc).allowed,
		SimWeaponGate.still_supported(SimTypes.Guidance.SARH, fc).reason)

	# GNSS_INS needs no track at all -- and is useless against movers.
	var jdam := SimWeaponDef.new({"name": "GPS bomb",
		"guidance": SimTypes.Guidance.GNSS_INS, "max_range_km": 60.0})
	_ok("GNSS_INS launches with no track whatsoever",
		SimWeaponGate.can_launch(jdam, null, 30.0).allowed,
		SimWeaponGate.can_launch(jdam, null, 30.0).reason)

	# ANTI_RADIATION is gated on the target radiating, not on track quality.
	var harm := SimWeaponDef.new({"name": "HARM",
		"guidance": SimTypes.Guidance.ANTI_RADIATION, "max_range_km": 150.0})
	contact.emitting = false
	_ok("HARM refused against a silent emitter",
		not SimWeaponGate.can_launch(harm, contact, 50.0).allowed,
		SimWeaponGate.can_launch(harm, contact, 50.0).reason)
	contact.emitting = true
	_ok("HARM clear against a radiating one, on a mere CONTACT",
		SimWeaponGate.can_launch(harm, contact, 50.0).allowed)
	contact.emitting = false
	_ok("switching the radar off puts the HARM into memory mode",
		SimWeaponGate.still_supported(SimTypes.Guidance.ANTI_RADIATION, contact).reason
			.contains("memory"))

	# Every refusal must explain itself (docs/02 §9).
	var r := SimWeaponGate.can_launch(sarh, contact, 20.0)
	_ok("a refusal carries a reason the player can be shown",
		not r.allowed and r.reason.length() > 0, "\"%s\"" % r.reason)


# ── the scenario the whole design exists for ─────────────────────────────────

func _suite_cooperative_engagement() -> void:
	_suite("Cooperative engagement -- AEW feeds a blind SAM (docs/02 §4, §6)")

	var w := SimWorld.new()
	var e := w.entities

	# A SAM battery with a short-range illuminator, 10 m up.
	var sam := e.add("SAM battery", 0, 0, 10, 0,
		SimSignature.new(50.0),
		[_illuminator("illuminator", 40.0, 10.0)], SimTypes.Category.GROUND)

	# An AEW aircraft orbiting overhead at 9 km.
	var aew := e.add("E-3 Sentry", 0, 0, 9000, 0,
		SimSignature.new(100.0),
		[_radar("rotodome", 400.0, 9000.0, 3)], SimTypes.Category.AIR)

	# A low-flying strike aircraft 60 km out at 5 m.
	var raider := e.add("low raider", 1, 60000, 5, 0,
		SimSignature.new(10.0), [], SimTypes.Category.AIR)
	e.set_velocity(raider, -200.0, 0.0, 0.0)

	w.run_ticks(8)
	var table := w.track_table_for(0)
	var t := table._track_for_truth(raider)

	_ok("the AEW holds the low raider at 60 km", t != null and t.quality >= SimTypes.TrackQuality.TRACK,
		"quality %s" % (SimTypes.quality_name(t.quality) if t else "none"))

	# The SAM's own illuminator cannot possibly see it: horizon 10 m vs 5 m
	# is 22 km, and the raider is at 60 km.
	var sam_horizon := P.horizon_km(10.0, 5.0)
	_ok("the SAM's own radar horizon (%.0f km) falls far short of 60 km" % sam_horizon,
		sam_horizon < 60.0)

	# COMMAND_LINK reads the faction table, so the shooter and the sensor need
	# not be the same unit. This is the single most satisfying thing in the
	# design and it required no new system.
	var cmd := SimWeaponDef.new({"name": "networked SAM",
		"guidance": SimTypes.Guidance.COMMAND_LINK, "max_range_km": 100.0})
	var shot := SimWeaponGate.can_launch(cmd, t, 60.0)
	_ok("a blind SAM fires on the AEW's picture", shot.allowed, shot.reason)

	# A SARH round cannot: the AEW's search radar is capped at TRACK and
	# cannot guide. Kill the illuminator, not the search radar.
	var sarh := SimWeaponDef.new({"name": "SARH SAM",
		"guidance": SimTypes.Guidance.SARH, "max_range_km": 100.0})
	var sarh_shot := SimWeaponGate.can_launch(sarh, t, 60.0)
	_ok("but SARH cannot -- a search radar finds, it does not guide",
		not sarh_shot.allowed, sarh_shot.reason)

	# Now shoot down the AEW and watch the shot become impossible.
	e.kill(aew)
	w.run_ticks(400)   # 20 s at 20 Hz -- past the TRACK decay threshold
	var after := table._track_for_truth(raider)
	var after_q: int = after.quality if after else SimTypes.TrackQuality.NONE
	_ok("killing the AEW collapses the picture back down the ladder",
		after_q < SimTypes.TrackQuality.TRACK,
		"quality is now %s" % SimTypes.quality_name(after_q))
	var denied := SimWeaponGate.can_launch(cmd, after, 60.0)
	_ok("and the networked shot is refused", not denied.allowed, denied.reason)


# ── docs/11 §3 -- the pulse-Doppler cliff ────────────────────────────────────

func _suite_look_down_cliff() -> void:
	_suite("The R3 pulse-Doppler cliff (docs/11 §3)")
	_ok("a Gen 2 radar 100 m up cannot see a target at 20 m -- clutter",
		not P.has_look_down(2, 100.0, 20.0))
	_ok("the same geometry is fine for Gen 3 pulse-Doppler",
		P.has_look_down(3, 100.0, 20.0))
	_ok("even a Gen 1 set can see a target above it",
		P.has_look_down(1, 100.0, 6000.0))
	_ok("early AEW is a maritime-only asset", not P.aew_works_overland(2))
	_ok("A3 rotodomes work overland", P.aew_works_overland(3))


# ── docs/02 §7.2 -- jamming buys distance, not immunity ──────────────────────

func _suite_jamming() -> void:
	_suite("Jamming and burn-through (docs/02 §7.2)")

	var nominal := 100.0
	var far := P.jam_noise_ratio(50.0, 80.0, 0)
	var near := P.jam_noise_ratio(50.0, 20.0, 0)
	_ok("a closer jammer raises the noise floor more", near > far,
		"JNR %.3f at 20 km vs %.3f at 80 km" % [near, far])

	var jammed := P.jammed_range_km(nominal, near)
	_ok("jamming shrinks detection range but never to zero",
		jammed < nominal and jammed > 0.0,
		"%.1f km down from %.1f km" % [jammed, nominal])

	# ECCM offsets it, which is what the R-ladder buys.
	var with_eccm := P.jammed_range_km(nominal, P.jam_noise_ratio(50.0, 20.0, 4))
	_ok("ECCM 4 restores most of the loss", with_eccm > jammed,
		"%.1f km vs %.1f km" % [with_eccm, jammed])

	# Burn-through: closing the range always favours the radar.
	var bt := P.burn_through_km(nominal, 10.0, 50.0, 0)
	_ok("a burn-through range exists -- jamming buys distance, not immunity",
		bt > 0.0 and bt < INF, "burn-through at %.1f km" % bt)


# ── docs/06 -- determinism is non-negotiable ─────────────────────────────────

func _suite_determinism() -> void:
	_suite("Determinism (docs/06)")

	var h1 := _scenario_hash(4242)
	var h2 := _scenario_hash(4242)
	_ok("the same seed and inputs produce an identical state hash", h1 == h2,
		"0x%x" % h1)

	# The seed deliberately does NOT change this scenario: nothing in it draws
	# from the RNG. That is the property worth locking in -- a sim whose replay
	# shifts when an unrelated seed changes is a sim whose replays cannot be
	# trusted. The seed matters only where something actually rolls, which the
	# stream tests below cover.
	var h3 := _scenario_hash(9999)
	_ok("a scenario with no stochastic input is seed-independent", h1 == h3,
		"0x%x both ways" % h1)

	# And distinct seeds must give distinct streams, or seeding is decorative.
	var s1 := SimRng.new(4242)
	var s2 := SimRng.new(9999)
	var diverged := false
	for _i in range(16):
		if s1.next_float() != s2.next_float():
			diverged = true
			break
	_ok("distinct seeds give distinct streams", diverged)

	# The PRNG must be reproducible independently of Godot's global RNG.
	var a := SimRng.new(777)
	var b := SimRng.new(777)
	var same := true
	for _i in range(500):
		if a.next_float() != b.next_float():
			same = false
			break
	_ok("the seeded stream replays exactly", same)

	var c := SimRng.new(777)
	var d := c.fork(3)
	_ok("a forked stream is independent", d.next_float() != SimRng.new(777).next_float())


func _scenario_hash(seed_value: int) -> int:
	var w := SimWorld.new(seed_value)
	var e := w.entities
	e.add("radar", 0, 0, 30, 0, SimSignature.new(200.0),
		[_radar("air search", 150.0, 30.0)], SimTypes.Category.SURFACE)
	for i in range(6):
		var idx := e.add("raider %d" % i, 1, 40000 + i * 900,
			500 + i * 120, i * 700,
			SimSignature.new(2.0 + float(i)), [], SimTypes.Category.AIR)
		e.set_velocity(idx, -150.0 - float(i) * 7.0, 0.0, float(i) * 3.0)
	w.run_ticks(300)
	return w.state_hash()


# ── fixtures ─────────────────────────────────────────────────────────────────

func _radar(name: String, ref_km: float, height: float, gen := 4) -> SimSensorDef:
	return SimSensorDef.new({
		"name": name, "domain": SimTypes.Domain.RF_ACTIVE,
		"reference_range_km": ref_km, "mount_height_m": height,
		"max_quality": SimTypes.TrackQuality.TRACK,
		"radar_gen": gen, "revisit_seconds": 0.0, "eccm_rating": 2})


func _illuminator(name: String, ref_km: float, height: float) -> SimSensorDef:
	return SimSensorDef.new({
		"name": name, "domain": SimTypes.Domain.RF_ACTIVE,
		"reference_range_km": ref_km, "mount_height_m": height,
		"max_quality": SimTypes.TrackQuality.FIRE_CONTROL,
		"radar_gen": 4, "revisit_seconds": 0.0, "eccm_rating": 2})


func _track(quality: int) -> SimTrack:
	var t := SimTrack.new()
	t.refresh(quality, SimTypes.Classification.CLASS, 1.0, "test")
	return t
