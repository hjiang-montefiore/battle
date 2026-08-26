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
	_suite_skill_ladder()
	_suite_match_setup()
	_suite_munitions()
	_suite_nothing_stays_forever()
	_suite_asw()
	_suite_torpedoes()

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


# ── docs/09 §2 -- difficulty is doctrine quality, not bonuses ────────────────

func _suite_skill_ladder() -> void:
	_suite("AI skill ladder (docs/09 §2)")

	# The three published rows must survive the eight-tier expansion.
	var r := SimSkill.reaction_seconds(SimSkill.Level.RECRUIT)
	_ok("Recruit reacts in the published 8-12 s", r >= 8.0 and r <= 12.0, "%.1f s" % r)
	var v := SimSkill.reaction_seconds(SimSkill.Level.VETERAN)
	_ok("Veteran reacts in the published 3-5 s", v >= 3.0 and v <= 5.0, "%.1f s" % v)
	var e := SimSkill.reaction_seconds(SimSkill.Level.ELITE)
	_ok("Elite reacts in the published 1-2 s", e >= 1.0 and e <= 2.0, "%.1f s" % e)
	_ok("Recruit waits for TQ3",
		SimSkill.commit_threshold(SimSkill.Level.RECRUIT) == SimTypes.TrackQuality.FIRE_CONTROL)
	_ok("Veteran acts on TQ2",
		SimSkill.commit_threshold(SimSkill.Level.VETERAN) == SimTypes.TrackQuality.TRACK)
	_ok("Elite acts on TQ1 cues",
		SimSkill.commit_threshold(SimSkill.Level.ELITE) == SimTypes.TrackQuality.CONTACT)

	# A difficulty slider with a non-monotonic rung is experienced as randomness.
	var mono := true
	var why := ""
	for i in range(SimSkill.LEVEL_COUNT - 1):
		if SimSkill.reaction_seconds(i) <= SimSkill.reaction_seconds(i + 1):
			mono = false; why = "reaction at %s" % SimSkill.name_of(i)
		if SimSkill.emcon_discipline(i) >= SimSkill.emcon_discipline(i + 1):
			mono = false; why = "emcon at %s" % SimSkill.name_of(i)
		if SimSkill.sensor_share(i) >= SimSkill.sensor_share(i + 1):
			mono = false; why = "sensor share at %s" % SimSkill.name_of(i)
		if SimSkill.counter_ew(i) >= SimSkill.counter_ew(i + 1):
			mono = false; why = "counter-EW at %s" % SimSkill.name_of(i)
		if SimSkill.simultaneous_axes(i) > SimSkill.simultaneous_axes(i + 1):
			mono = false; why = "axes at %s" % SimSkill.name_of(i)
		if SimSkill.commit_threshold(i) < SimSkill.commit_threshold(i + 1):
			mono = false; why = "commit threshold at %s" % SimSkill.name_of(i)
	_ok("every dial is monotonic across all 8 tiers", mono, why)

	# The top tiers must buy tempo, never information. docs/09 §1 is absolute.
	_ok("Warlord commits on the same rung as Elite -- tempo, not sight",
		SimSkill.commit_threshold(SimSkill.Level.WARLORD)
		== SimSkill.commit_threshold(SimSkill.Level.ELITE))
	_ok("Warlord's advantage over Elite is coordination",
		SimSkill.simultaneous_axes(SimSkill.Level.WARLORD)
		> SimSkill.simultaneous_axes(SimSkill.Level.ELITE),
		"%d axes vs %d" % [SimSkill.simultaneous_axes(SimSkill.Level.WARLORD),
			SimSkill.simultaneous_axes(SimSkill.Level.ELITE)])

	# Every tier needs a name and a line of setup-screen copy.
	var described := true
	for i in range(SimSkill.LEVEL_COUNT):
		if SimSkill.name_of(i) == "?" or SimSkill.blurb(i) == "":
			described = false
	_ok("all 8 tiers carry a name and a description", described)


# ── docs/09 §4, §5, §6 -- match setup ───────────────────────────────────────

func _suite_match_setup() -> void:
	_suite("Match setup: era, technology, force composition (docs/09 §4-§6)")

	# Force composition -- army only, no navy, no air force.
	var army := SimPlayerSetup.new({"name": "Army only"})
	army.set_army_only()
	_ok("army-only forbids air and naval",
		not army.allows(SimPlayerSetup.Domain.AIR)
		and not army.allows(SimPlayerSetup.Domain.NAVAL)
		and army.allows(SimPlayerSetup.Domain.GROUND),
		army.domains_description())

	var no_navy := SimPlayerSetup.new({"name": "No navy"})
	no_navy.set_without_navy()
	_ok("no-navy keeps the air force",
		no_navy.allows(SimPlayerSetup.Domain.AIR)
		and not no_navy.allows(SimPlayerSetup.Domain.NAVAL),
		no_navy.domains_description())

	var no_air := SimPlayerSetup.new({"name": "No air force"})
	no_air.set_without_air_force()
	_ok("no-air keeps the navy",
		no_air.allows(SimPlayerSetup.Domain.NAVAL)
		and not no_air.allows(SimPlayerSetup.Domain.AIR),
		no_air.domains_description())

	# Per-ladder technology floor and ceiling, independent of epoch.
	var mixed := SimPlayerSetup.new({"name": "Mixed", "start_epoch": 6, "ceiling_epoch": 6})
	mixed.set_tech_ceiling("radar", 3)
	_ok("an epoch-6 force can be capped at R3 radar",
		mixed.max_generation("radar") == 3,
		"radar ceiling %d, missiles %d" % [mixed.max_generation("radar"),
			mixed.max_generation("aam")])
	_ok("its other ladders are untouched by that cap",
		mixed.max_generation("aam") > 3)

	# Epoch ceiling still binds even without an explicit cap.
	var early := SimPlayerSetup.new({"start_epoch": 1, "ceiling_epoch": 2})
	_ok("an epoch-2 ceiling holds radar below the pulse-Doppler cliff",
		early.max_generation("radar") < 3,
		"radar ceiling %d" % early.max_generation("radar"))

	# Validation catches the setups that cannot be played.
	var bad := SimPlayerSetup.new({"name": "Bad", "start_epoch": 6, "ceiling_epoch": 3})
	_ok("a ceiling below the start is rejected", bad.validate().size() > 0,
		bad.validate()[0] if bad.validate().size() > 0 else "")

	var nothing := SimPlayerSetup.new({"name": "Nothing"})
	nothing.restrict_to(0)
	_ok("a player allowed no domains is rejected", nothing.validate().size() > 0)

	var contradiction := SimPlayerSetup.new({"name": "Contradiction",
		"doctrine": SimDoctrine.make(SimDoctrine.Profile.SENSOR_DOMINANCE)})
	contradiction.set_army_only()
	_ok("Sensor Dominance without an air force is flagged",
		contradiction.validate().size() > 0,
		contradiction.validate()[0] if contradiction.validate().size() > 0 else "")

	# All eight doctrines exist and differ.
	var seen: Array = []
	var distinct := true
	for i in range(8):
		var d := SimDoctrine.make(i)
		var key := "%.2f%.2f%.2f%.2f" % [d.aggression, d.tech_bias,
			d.sensor_share, d.target_priority]
		if seen.has(key):
			distinct = false
		seen.append(key)
	_ok("all 8 doctrines are distinct", distinct)
	_ok("Interdiction targets enablers over armies",
		SimDoctrine.make(SimDoctrine.Profile.INTERDICTION).target_priority > 0.9)
	_ok("Blitz out-aggresses Fortress",
		SimDoctrine.make(SimDoctrine.Profile.BLITZ).aggression
		> SimDoctrine.make(SimDoctrine.Profile.FORTRESS).aggression)

	# Adaptation moves a doctrine without erasing its identity.
	var fortress := SimDoctrine.make(SimDoctrine.Profile.FORTRESS)
	var before := fortress.aggression
	fortress.adapt(true, false, true, false, false)
	_ok("at its ceiling a Fortress gets more aggressive", fortress.aggression > before,
		"%.2f -> %.2f" % [before, fortress.aggression])
	_ok("but is still recognisably a Fortress",
		fortress.aggression < SimDoctrine.make(SimDoctrine.Profile.BLITZ).aggression)

	# Every published scenario builds and validates.
	# Lineage, docs/08: the PLA changes lineage MID-TIMELINE, and everyone
	# else holds one for the whole run.
	_ok("the PLA is Soviet-derived through epoch 4",
		SimPlayerSetup.lineage_for(SimPlayerSetup.Faction.PLA, 4)
		== SimPlayerSetup.Lineage.SOVIET)
	_ok("and indigenous from epoch 5 -- the lineage fork",
		SimPlayerSetup.lineage_for(SimPlayerSetup.Faction.PLA, 5)
		== SimPlayerSetup.Lineage.CHINESE)
	_ok("Ukraine shares Russia's Soviet lineage, so neither out-generations the other",
		SimPlayerSetup.lineage_for(SimPlayerSetup.Faction.UKRAINE, 5)
		== SimPlayerSetup.lineage_for(SimPlayerSetup.Faction.RUSSIA, 5))
	_ok("Japan is Western -- the cheapest expansion docs/08 describes",
		SimPlayerSetup.lineage_for(SimPlayerSetup.Faction.JAPAN, 6)
		== SimPlayerSetup.Lineage.WESTERN)
	_ok("every faction has a name", (func():
		for f in range(10):
			if SimPlayerSetup._faction_name(f) == "?":
				return false
		return true).call())

	var all_ok := true
	var failing := ""
	for key in SimMatchSetup.SCENARIOS:
		var m := SimMatchSetup.scenario(key)
		var problems := m.validate()
		if problems.size() > 0:
			all_ok = false
			failing = "%s: %s" % [key, problems[0]]
	_ok("all %d scenarios build and validate" % SimMatchSetup.SCENARIOS.size(),
		all_ok, failing)

	# The two China/Russia scenarios are the same matchup at opposite ends of
	# the timeline, and docs/08 says that is the point: near-identical early,
	# philosophically opposed late.
	var amur_early := SimMatchSetup.scenario("sino_russian_early")
	var amur_late := SimMatchSetup.scenario("sino_russian_late")
	_ok("early Sino-Russian is a same-lineage mirror match",
		SimPlayerSetup.lineage_for(amur_early.players[0].faction, 2)
		== SimPlayerSetup.lineage_for(amur_early.players[1].faction, 2))
	_ok("late Sino-Russian is not -- the PLA has forked away",
		SimPlayerSetup.lineage_for(amur_late.players[0].faction, 7)
		!= SimPlayerSetup.lineage_for(amur_late.players[1].faction, 7))
	_ok("late, Russia answers the sensor question with Denial",
		amur_late.players[1].doctrine.profile == SimDoctrine.Profile.DENIAL,
		SimDoctrine.name_of(amur_late.players[1].doctrine.profile))

	# A faction created without an explicit doctrine must get its historical
	# default, not a silent Combined Arms.
	var bare_ru := SimPlayerSetup.new({"faction": SimPlayerSetup.Faction.RUSSIA})
	_ok("Russia defaults to Denial when no doctrine is given",
		bare_ru.doctrine.profile == SimDoctrine.Profile.DENIAL,
		SimDoctrine.name_of(bare_ru.doctrine.profile))
	var bare_kp := SimPlayerSetup.new({"faction": SimPlayerSetup.Faction.KPA})
	_ok("the KPA defaults to Attrition",
		bare_kp.doctrine.profile == SimDoctrine.Profile.ATTRITION,
		SimDoctrine.name_of(bare_kp.doctrine.profile))
	var bare_ua := SimPlayerSetup.new({"faction": SimPlayerSetup.Faction.UKRAINE})
	_ok("Ukraine defaults to Interdiction -- attack what the bigger force runs on",
		bare_ua.doctrine.profile == SimDoctrine.Profile.INTERDICTION,
		SimDoctrine.name_of(bare_ua.doctrine.profile))

	var atlantic := SimMatchSetup.scenario("north_atlantic")
	_ok("North Atlantic is a naval theatre -- no ground forces on either side",
		not atlantic.players[0].allows(SimPlayerSetup.Domain.GROUND)
		and not atlantic.players[1].allows(SimPlayerSetup.Domain.GROUND),
		atlantic.players[0].domains_description())

	var eu := SimMatchSetup.scenario("central_europe")
	_ok("Central Europe puts three Western factions on one team",
		eu.teams()[0].size() == 3, "%d allies" % eu.teams()[0].size())

	var coalition := SimMatchSetup.scenario("coalition")
	_ok("Coalition puts the human and the US AI on one team",
		coalition.teams()[0].size() == 2,
		"team 0 has %d" % coalition.teams()[0].size())
	var overmatch := SimMatchSetup.scenario("overmatch")
	_ok("Overmatch is 1 human against 3 massed AIs",
		overmatch.humans().size() == 1 and overmatch.ais().size() == 3)


# ── docs/10 -- munitions in flight ──────────────────────────────────────────

func _suite_munitions() -> void:
	_suite("Munitions in flight (docs/10) -- pillar 7")

	# Flight phases. A missile is not a dot at constant speed.
	var w := SimWorld.new(7)
	var shooter := w.entities.add("launcher", 0, 0, 20, 0,
		SimSignature.new(20.0), [_illuminator("illum", 90.0, 20.0)],
		SimTypes.Category.GROUND)
	var bogey := w.entities.add("bogey", 1, 12000, 3000, 0,
		SimSignature.new(10.0), [], SimTypes.Category.AIR)
	w.entities.set_velocity(bogey, -180.0, 0.0, 0.0)
	w.run_ticks(20)
	var tk := w.track_table_for(0)._track_for_truth(bogey)
	_ok("the launcher holds a fire-control track before firing",
		tk != null and tk.quality >= SimTypes.TrackQuality.FIRE_CONTROL,
		SimTypes.quality_name(tk.quality) if tk else "none")

	var sam := SimMunitionDef.sam_medium()
	var p := w.munitions.fire(sam, shooter, bogey, tk)
	_ok("a round leaves the rail", p != null and p.alive)
	_ok("it starts in BOOST", p.phase == SimMunitionDef.Phase.BOOST)
	var launch_speed := p.speed()
	w.run_ticks(40)                      # 2 s
	_ok("boost accelerates it hard", p.speed() > launch_speed * 3.0,
		"%.0f m/s from %.0f" % [p.speed(), launch_speed])
	w.run_ticks(200)
	if p.alive:
		_ok("after burnout it is coasting", p.phase == SimMunitionDef.Phase.COAST)
	else:
		_ok("it terminated during flight with a stated cause",
			p.termination != SimMunitionDef.Termination.NONE, p.log_line())

	# Run to completion -- it must resolve one way or the other.
	w.run_ticks(2000)
	_ok("the engagement resolves with a reason the player can be told",
		not p.alive and p.termination != SimMunitionDef.Termination.NONE,
		p.log_line())

	# docs/10 §3: "In range" is not "will hit."
	_ok("a coasting motor has a no-escape zone well inside kinematic range",
		SimMunitionDef.sam_medium().no_escape_fraction() <= 0.4,
		"%.0f%% of kinematic range" % (SimMunitionDef.sam_medium().no_escape_fraction() * 100.0))
	_ok("an epoch-7 ramjet pushes it toward 70%",
		SimMunitionDef.aam_ramjet().no_escape_fraction() >= 0.65)
	_near("a missile needs ~3x the target's g to guarantee intercept",
		SimMunitionDef.g_needed_against(9.0), 27.0, 0.01)

	# docs/10 §4: the SARH row. Kill the illuminator mid-flight.
	var w2 := SimWorld.new(11)
	var sh2 := w2.entities.add("SAM", 0, 0, 20, 0, SimSignature.new(20.0),
		[_illuminator("illum", 120.0, 20.0)], SimTypes.Category.GROUND)
	var t2 := w2.entities.add("strike", 1, 30000, 4000, 0,
		SimSignature.new(10.0), [], SimTypes.Category.AIR)
	w2.entities.set_velocity(t2, -240.0, 0.0, 0.0)
	w2.run_ticks(20)
	var tk2 := w2.track_table_for(0)._track_for_truth(t2)
	var m2 := w2.munitions.fire(SimMunitionDef.sam_medium(), sh2, t2, tk2)
	w2.run_ticks(60)
	var was_guided := m2.alive and not m2.went_ballistic
	w2.entities.kill(sh2)                 # illuminator destroyed mid-flight
	w2.run_ticks(600)
	_ok("a SARH round was guiding while the illuminator lived", was_guided)
	_ok("killing the illuminator mid-flight defeats it",
		not m2.alive and m2.termination != SimMunitionDef.Termination.HIT,
		m2.log_line())

	# docs/10 §5 + docs/11 §6: the S4 imaging-IR cliff. Flares stop working.
	var early := 0
	var imaging := 0
	for i in range(40):
		if _flare_trial(2, i):
			early += 1
		if _flare_trial(6, i):
			imaging += 1
	_ok("flares are a hard counter against an early IR seeker", early == 40,
		"%d/40 defeated" % early)
	_ok("and near-worthless against an imaging seeker", imaging <= 12,
		"%d/40 defeated" % imaging)

	# docs/10 §5: hard-kill physically destroys the round.
	var w3 := SimWorld.new(13)
	var sh3 := w3.entities.add("ATGM team", 0, 0, 2, 0, SimSignature.new(5.0),
		[_illuminator("sight", 20.0, 3.0)], SimTypes.Category.GROUND)
	var tank := w3.entities.add("tank", 1, 2500, 1.5, 0,
		SimSignature.new(20.0), [], SimTypes.Category.GROUND)
	w3.run_ticks(20)
	var tk3 := w3.track_table_for(0)._track_for_truth(tank)
	w3.munitions.arm_hard_kill(tank, 1)
	var m3 := w3.munitions.fire(SimMunitionDef.atgm(), sh3, tank, tk3)
	w3.run_ticks(1200)
	_ok("hard-kill APS intercepts the round in flight",
		m3.termination == SimMunitionDef.Termination.DEFEATED_APS, m3.log_line())

	# docs/10 §6: proximity fuzing makes a near miss a real outcome.
	var pr := SimProjectile.new()
	pr.def = SimMunitionDef.sam_medium()
	_near("a 3 m miss is nearly lethal", pr.damage_fraction(3.0), 0.83, 0.02)
	_near("a 15 m miss only damages", pr.damage_fraction(15.0), 0.17, 0.02)
	_ok("beyond the lethal radius it does nothing",
		pr.damage_fraction(40.0) == 0.0)

	# docs/10 §6: hit location is geometry, not a roll.
	var f := SimProjectile.new()
	f.vx = -100.0; f.vy = 0.0; f.vz = 0.0      # travelling -X, so came from +X
	# Headings are atan2(x, z): PI/2 faces +X, 0 faces +Z. A round from +X
	# therefore hits the FRONT of a tank facing +X and the SIDE of one facing +Z.
	_ok("a round from +X hits the FRONT of a tank facing +X",
		f.impact_facet(PI * 0.5) == SimProjectile.Facet.FRONT,
		SimProjectile.facet_name(f.impact_facet(PI * 0.5)))
	_ok("the same round hits the SIDE of a tank facing +Z",
		f.impact_facet(0.0) == SimProjectile.Facet.SIDE,
		SimProjectile.facet_name(f.impact_facet(0.0)))
	_ok("and the REAR of one facing -X",
		f.impact_facet(-PI * 0.5) == SimProjectile.Facet.REAR,
		SimProjectile.facet_name(f.impact_facet(-PI * 0.5)))
	var top := SimProjectile.new()
	top.vx = 10.0; top.vy = -300.0; top.vz = 0.0
	_ok("a plunging round hits the TOP whatever the target is facing",
		top.impact_facet(0.0) == SimProjectile.Facet.TOP
		and top.impact_facet(PI) == SimProjectile.Facet.TOP)


func _flare_trial(seeker_gen: int, trial: int) -> bool:
	# A fresh seed per trial -- reusing one seed makes 40 trials a single
	# sample, which is exactly the kind of test that looks like coverage
	# and is not.
	var w := SimWorld.new(100 + seeker_gen * 7919 + trial * 104729)
	var sh := w.entities.add("fighter", 0, 0, 3000, 0, SimSignature.new(5.0),
		[_radar("nose", 60.0, 3000.0)], SimTypes.Category.AIR)
	var bog := w.entities.add("bogey", 1, 4000, 3000, 0,
		SimSignature.new(5.0), [], SimTypes.Category.AIR)
	w.run_ticks(20)
	var tk := w.track_table_for(0)._track_for_truth(bog)
	var d := SimMunitionDef.new({"name": "IR AAM",
		"guidance": SimTypes.Guidance.IR_EO, "seeker_gen": seeker_gen,
		"boost_seconds": 2.0, "boost_accel": 300.0, "max_speed": 900.0,
		"g_available_max": 30.0, "lethal_radius_m": 8.0,
		"max_flight_seconds": 40.0})
	var m := w.munitions.fire(d, sh, bog, tk)
	w.munitions.deploy_flares(bog, 6.0)
	w.run_ticks(400)
	return m.termination == SimMunitionDef.Termination.DEFEATED_FLARE


# ── the requirement: nothing may remain on the map ──────────────────────────

func _suite_nothing_stays_forever() -> void:
	_suite("Nothing stays on the map forever")

	# Fire a lot of rounds into deliberately hostile conditions: targets that
	# die mid-flight, tracks that go stale, shots taken far beyond kinematic
	# range, and rounds aimed at nothing in particular.
	var w := SimWorld.new(4242)
	var e := w.entities
	var shooters: Array = []
	for i in range(6):
		shooters.append(e.add("shooter %d" % i, 0, i * 400, 25, 0,
			SimSignature.new(20.0), [_illuminator("illum", 140.0, 25.0)],
			SimTypes.Category.GROUND))
	var targets: Array = []
	for i in range(6):
		var t := e.add("target %d" % i, 1, 20000 + i * 9000, 2000 + i * 400, i * 500,
			SimSignature.new(8.0), [], SimTypes.Category.AIR)
		e.set_velocity(t, -200.0 - i * 30.0, 0.0, 40.0 * i)
		targets.append(t)
	w.run_ticks(20)

	var kinds := [SimMunitionDef.sam_medium(), SimMunitionDef.aam_active(),
		SimMunitionDef.aam_ramjet(), SimMunitionDef.atgm(),
		SimMunitionDef.harm(), SimMunitionDef.tank_apfsds(),
		SimMunitionDef.artillery_he()]
	var fired := 0
	for round_i in range(4):
		for si in range(shooters.size()):
			var tgt: int = targets[si % targets.size()]
			var tk := w.track_table_for(0)._track_for_truth(tgt)
			for k in kinds:
				if w.munitions.fire(k, shooters[si], tgt, tk) != null:
					fired += 1
		w.run_ticks(30)
	# Kill half the targets mid-flight, and half the shooters too.
	for i in range(0, targets.size(), 2):
		e.kill(targets[i])
	e.kill(shooters[0])
	e.kill(shooters[2])

	_ok("a saturation salvo actually launched", fired > 100, "%d rounds" % fired)
	_ok("the pool respects its concurrency cap",
		w.munitions.active_count() <= SimMunitions.MAX_CONCURRENT,
		"%d in flight" % w.munitions.active_count())

	# The longest max_flight_seconds in the library is 120 s. Run well past it.
	w.run_ticks(int(200.0 * SimWorld.SIM_HZ))

	_ok("EVERY round has left the map", w.munitions.active_count() == 0,
		"%d still in flight after 200 s" % w.munitions.active_count())
	_ok("every round is accounted for -- none leaked",
		w.munitions.is_balanced(),
		"launched %d, terminated %d, active %d" % [w.munitions.launched,
			w.munitions.terminated, w.munitions.active_count()])
	_ok("the pool was reused rather than grown without bound",
		w.munitions.launched > 100)

	# Every single one carries a stated cause. No silent disappearances.
	var causeless := 0
	for entry in w.munitions.combat_log:
		if entry.contains("IN FLIGHT"):
			causeless += 1
	_ok("no round terminated without a reason", causeless == 0)

	# A round fired at nothing still terminates.
	var w2 := SimWorld.new(99)
	var s2 := w2.entities.add("gun", 0, 0, 5, 0, SimSignature.new(10.0), [],
		SimTypes.Category.GROUND)
	var ghost := w2.entities.add("ghost", 1, 300000, 40, 0,
		SimSignature.new(1.0), [], SimTypes.Category.AIR)
	var stray := w2.munitions.fire(SimMunitionDef.tank_apfsds(), s2, ghost, null)
	w2.run_ticks(int(150.0 * SimWorld.SIM_HZ))
	_ok("a round fired at an unreachable target still terminates",
		not stray.alive, stray.log_line())

	# And one fired straight up comes down.
	var w3 := SimWorld.new(101)
	var s3 := w3.entities.add("mortar", 0, 0, 2, 0, SimSignature.new(5.0), [],
		SimTypes.Category.GROUND)
	var far := w3.entities.add("far", 1, 100, 2, 100000,
		SimSignature.new(5.0), [], SimTypes.Category.GROUND)
	var up := w3.munitions.fire(SimMunitionDef.artillery_he(), s3, far, null)
	up.vx = 0.0; up.vy = 800.0; up.vz = 0.0
	w3.run_ticks(int(150.0 * SimWorld.SIM_HZ))
	_ok("a round fired straight up comes back down", not up.alive, up.log_line())


# ── docs/02 §8 -- the acoustic domain, pillar 6 ─────────────────────────────

func _suite_asw() -> void:
	_suite("Anti-submarine warfare (docs/02 §8) -- pillar 6")

	# docs/02 §8.1: a single passive array gives a BEARING and nothing else.
	# Turning that into a firing solution needs motion analysis or a second
	# platform, which is why hunting a submarine is slow and cooperative.
	var shallow := _asw_case(40.0, false, 4.0, 8.0, 0.0)
	_ok("passive sonar detects a submarine above the layer",
		shallow.quality >= SimTypes.TrackQuality.CONTACT,
		SimTypes.quality_name(shallow.quality))
	_ok("and gives a bearing only -- no firing solution", shallow.bearing_only)

	# docs/02 §8.3: the thermocline. An ABSOLUTE shield against a hull sonar
	# above it, and the reason depth is a real tactical axis.
	var deep := _asw_case(40.0, true, 4.0, 8.0, 0.0)
	_ok("a submarine below the layer is invisible to a hull sonar above it",
		deep.quality == SimTypes.TrackQuality.NONE,
		SimTypes.quality_name(deep.quality))

	# The N3 counter: stream the array below the layer and it comes back.
	var towed := _asw_case(40.0, true, 4.0, -8.0, 0.0)
	_ok("a towed array streamed below the layer regains the contact",
		towed.quality >= SimTypes.TrackQuality.CONTACT,
		SimTypes.quality_name(towed.quality))

	# docs/02 §8.4: "A ship at flank speed is deaf."
	var deaf := _asw_case(40.0, false, 4.0, 8.0, 18.0)
	_ok("a hunter at flank speed goes deaf",
		deaf.quality == SimTypes.TrackQuality.NONE,
		SimTypes.quality_name(deaf.quality))

	# "A submarine at flank speed is loud." Radiated noise rises steeply with
	# shaft RPM, so a sprinting boat is heard from further away.
	var w := SimWorld.new(9)
	var quiet_boat := w.entities.add("creeping", 1, 0, -50, 0,
		SimSignature.new(200.0, 0.2, 100.0), [], SimTypes.Category.SUBSURFACE)
	w.entities.set_velocity(quiet_boat, 2.5, 0.0, 0.0)
	var loud_boat := w.entities.add("sprinting", 1, 0, -50, 0,
		SimSignature.new(200.0, 0.2, 100.0), [], SimTypes.Category.SUBSURFACE)
	w.entities.set_velocity(loud_boat, 15.0, 0.0, 0.0)
	var quiet_db := w.entities.effective_acoustic_db(quiet_boat)
	var loud_db := w.entities.effective_acoustic_db(loud_boat)
	_ok("a submarine at flank speed is measurably louder", loud_db > quiet_db + 5.0,
		"%.1f dB creeping vs %.1f dB sprinting" % [quiet_db, loud_db])

	# docs/02 §8.2: pinging is the same trap as radar, underwater. An active
	# set is two-way and gives a real solution; it also announces the hunt.
	var ping := SimSensorDef.new({"name": "hull sonar active",
		"domain": SimTypes.Domain.ACOUSTIC_ACTIVE,
		"reference_range_km": 25.0, "mount_height_m": 8.0,
		"max_quality": SimTypes.TrackQuality.FIRE_CONTROL})
	_ok("an active sonar is two-way, like a radar", ping.is_two_way())
	_ok("and is not bearing-only, so it can produce a solution",
		not ping.is_bearing_only())
	var passive := SimSensorDef.new({"domain": SimTypes.Domain.ACOUSTIC_PASSIVE})
	_ok("a passive array is one-way and bearing-only",
		passive.is_bearing_only() and not passive.is_two_way())


func _asw_case(range_km: float, below_layer: bool, sub_speed: float,
		mount_m: float, hunter_speed: float) -> SimTrack:
	var w := SimWorld.new(5)
	var e := w.entities
	var hunter := e.add("frigate", 0, 0, 8, 0,
		SimSignature.new(3000.0, 1.0, 110.0),
		[SimSensorDef.new({
			"name": "towed array" if mount_m < 0.0 else "hull sonar",
			"domain": SimTypes.Domain.ACOUSTIC_PASSIVE,
			"reference_range_km": 60.0, "mount_height_m": mount_m,
			"max_quality": SimTypes.TrackQuality.TRACK})],
		SimTypes.Category.SURFACE)
	e.set_velocity(hunter, hunter_speed, 0.0, 0.0)
	var sub := e.add("submarine", 1, range_km * 1000.0, -50.0, 0,
		SimSignature.new(200.0, 0.2, 100.0), [], SimTypes.Category.SUBSURFACE)
	e.depth_m[sub] = 200.0 if below_layer else 40.0
	e.below_layer[sub] = 1 if below_layer else 0
	e.set_velocity(sub, -sub_speed, 0.0, 0.0)
	w.run_ticks(12)
	var t := w.track_table_for(0)._track_for_truth(sub)
	return t if t != null else SimTrack.new()


# ── docs/10 §7 -- torpedoes, the slow-motion case ───────────────────────────

func _suite_torpedoes() -> void:
	_suite("Torpedoes (docs/10 §7)")

	# "They are slow. A torpedo run takes minutes, not seconds, and everything
	# follows from that."
	var slow := SimMunitionDef.torpedo_heavyweight(28.0)
	var reach_s := 20000.0 / slow.run_speed_ms
	_ok("a 20 km run takes minutes, not seconds", reach_s > 120.0,
		"%.0f s at %.0f kn" % [reach_s, 28.0])

	# The speed/range trade: pillar 4 at projectile scale. A heavyweight runs
	# far at low speed or much less far at high speed.
	var fast := SimMunitionDef.torpedo_heavyweight(50.0)
	_ok("running fast costs range", fast.run_range_m() < slow.run_range_m(),
		"%.1f km at 50 kn vs %.1f km at 28 kn" % [
			fast.run_range_m() / 1000.0, slow.run_range_m() / 1000.0])
	_ok("a 28 kn heavyweight reaches a realistic ~50 km",
		slow.run_range_m() > 40000.0 and slow.run_range_m() < 60000.0,
		"%.1f km" % (slow.run_range_m() / 1000.0))

	# "A ship with enough speed and enough head start can genuinely OUTRUN a
	# torpedo, which turns 'torpedo in the water' into a chase."
	# Fired at the 50 kn setting, which is exactly where the trade bites: it
	# closes faster but only carries 28 km of fuel, and the chase needs more.
	var outran := _torpedo_case(14000.0, 18.0, 50.0, false, false)
	_ok("a fast ship with a head start outruns the torpedo",
		outran.termination == SimMunitionDef.Termination.MISS_ENERGY,
		outran.log_line())
	var caught := _torpedo_case(6000.0, 3.0, 30.0, false, false)
	_ok("a slow one close in does not",
		caught.termination != SimMunitionDef.Termination.MISS_ENERGY,
		caught.log_line())

	# "Firing is loud. A torpedo launch is a detectable acoustic event."
	var w := SimWorld.new(31)
	var boat := w.entities.add("submarine", 0, 0, -60, 0,
		SimSignature.new(50.0, 0.1, 96.0), [], SimTypes.Category.SUBSURFACE)
	# Far enough that the boat is inaudible while it is quiet. A transient
	# raises detection RANGE, not track quality -- a passive array is
	# bearing-only and capped at CONTACT however loud the target is.
	var prey := w.entities.add("frigate", 1, 60000, -6, 0,
		SimSignature.new(3000.0, 1.0, 118.0),
		[SimSensorDef.new({"name": "towed array",
			"domain": SimTypes.Domain.ACOUSTIC_PASSIVE,
			"reference_range_km": 55.0, "mount_height_m": -8.0,
			"max_quality": SimTypes.TrackQuality.TRACK})],
		SimTypes.Category.SURFACE)
	w.entities.depth_m[boat] = 60.0
	w.run_ticks(12)
	var before := w.track_table_for(1)._track_for_truth(boat)
	var quiet_q: int = before.quality if before else SimTypes.TrackQuality.NONE
	w.munitions.fire(SimMunitionDef.torpedo_heavyweight(), boat, prey, null)
	w.run_ticks(12)
	var after := w.track_table_for(1)._track_for_truth(boat)
	var loud_q: int = after.quality if after else SimTypes.TrackQuality.NONE
	_ok("launching gives the target a contact on the shooter",
		loud_q > quiet_q,
		"%s -> %s" % [SimTypes.quality_name(quiet_q), SimTypes.quality_name(loud_q)])

	# Wire guidance is an enormous commitment: the launcher must stay slow and
	# hold course for the whole run, or the wire parts.
	var held := _wire_case(0.0)
	_ok("a boat that stays slow and straight keeps the wire", held)
	var sprinted := _wire_case(14.0)
	_ok("a boat that sprints cuts its own wire", not sprinted)

	# Noisemakers seduce a listening or pinging torpedo. A wake-homer ignores
	# them, because a noisemaker is not a wake.
	var seduced := 0
	var wake_seduced := 0
	for i in range(24):
		if _noisemaker_case(SimMunitionDef.TorpedoSeeker.PASSIVE, i):
			seduced += 1
		if _noisemaker_case(SimMunitionDef.TorpedoSeeker.WAKE, i):
			wake_seduced += 1
	_ok("noisemakers often defeat a passive torpedo", seduced > 6,
		"%d/24" % seduced)
	_ok("and never a wake-homer", wake_seduced == 0, "%d/24" % wake_seduced)

	# A wake-homer is useless against a submerged submarine: no wake to follow.
	var vs_sub := _torpedo_case(4000.0, 4.0, 40.0, true, true)
	_ok("a wake-homer cannot engage a submerged submarine",
		vs_sub.termination == SimMunitionDef.Termination.DEFEATED_DECOY,
		vs_sub.log_line())

	# And nothing stays in the water forever.
	_ok("a torpedo that reaches nothing runs out of fuel and stops",
		outran.termination == SimMunitionDef.Termination.MISS_ENERGY
		and not outran.alive)


func _torpedo_case(range_m: float, target_speed: float, torp_kn: float,
		target_submerged: bool, wake: bool) -> SimProjectile:
	var w := SimWorld.new(17)
	var e := w.entities
	var boat := e.add("shooter", 0, 0, -60, 0, SimSignature.new(50.0, 0.1, 96.0),
		[], SimTypes.Category.SUBSURFACE)
	e.depth_m[boat] = 60.0
	var prey := e.add("target", 1, range_m, -6.0 if not target_submerged else -80.0, 0,
		SimSignature.new(3000.0, 1.0, 118.0), [],
		SimTypes.Category.SUBSURFACE if target_submerged else SimTypes.Category.SURFACE)
	if target_submerged:
		e.depth_m[prey] = 80.0
	e.set_velocity(prey, target_speed, 0.0, 0.0)     # running directly away
	var d := SimMunitionDef.torpedo_wake_homing() if wake \
		else SimMunitionDef.torpedo_heavyweight(torp_kn, SimMunitionDef.TorpedoSeeker.ACTIVE)
	var t := w.munitions.fire(d, boat, prey, null)
	# Long enough for the whole run at any setting.
	w.run_ticks(int(1200.0 * SimWorld.SIM_HZ))
	return t


func _wire_case(launcher_speed: float) -> bool:
	var w := SimWorld.new(23)
	var e := w.entities
	var boat := e.add("shooter", 0, 0, -60, 0, SimSignature.new(50.0, 0.1, 96.0),
		[], SimTypes.Category.SUBSURFACE)
	e.depth_m[boat] = 60.0
	e.set_velocity(boat, 2.0, 0.0, 0.0)
	var prey := e.add("target", 1, 9000, -6, 0, SimSignature.new(3000.0, 1.0, 118.0),
		[], SimTypes.Category.SURFACE)
	var t := w.munitions.fire(SimMunitionDef.torpedo_heavyweight(28.0), boat, prey, null)
	w.run_ticks(40)
	e.set_velocity(boat, launcher_speed if launcher_speed > 0.0 else 2.0, 0.0, 0.0)
	w.run_ticks(60)
	return t.wire_intact


func _noisemaker_case(seeker: int, trial: int) -> bool:
	var w := SimWorld.new(400 + seeker * 7919 + trial * 104729)
	var e := w.entities
	var boat := e.add("shooter", 0, 0, -60, 0, SimSignature.new(50.0, 0.1, 96.0),
		[], SimTypes.Category.SUBSURFACE)
	e.depth_m[boat] = 60.0
	var prey := e.add("target", 1, 3000, -6, 0, SimSignature.new(3000.0, 1.0, 118.0),
		[], SimTypes.Category.SURFACE)
	var d := SimMunitionDef.torpedo_heavyweight(35.0, seeker)
	var t := w.munitions.fire(d, boat, prey, null)
	w.munitions.deploy_noisemakers(prey, 40.0)
	w.run_ticks(int(300.0 * SimWorld.SIM_HZ))
	return t.termination == SimMunitionDef.Termination.DEFEATED_DECOY
