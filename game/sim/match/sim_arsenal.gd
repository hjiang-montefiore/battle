class_name SimArsenal
extends RefCounted
## What each docs/12 role actually SHOOTS WITH.
##
## The combat layer built a working weapon cycle and closed its report with the
## honest note that "nothing arms units today -- a unit produced by the economy
## is fully survivable, fully mobile and has nothing to shoot with." The roster
## gives a unit its armour, its signature, its sensors, its fuel and its price.
## This gives it its gun. Without this file the whole combat chain is reachable
## only from a test fixture.
##
## ── WHY IT IS A TABLE AND NOT A FIELD ON SimUnitDef ──────────────────────────
## docs/03 is emphatic that penetration belongs to the ROUND and not to the
## launcher: "the same 120 mm tube fired ~350 mm rounds in 1979 and ~750 mm
## rounds in 2003." docs/11 makes ammunition an independently upgradeable
## ladder that applies retroactively to units already in the field. So a weapon
## is a (tube, current ammunition) pair resolved at ARMING time from the
## owner's generation, not a number stamped on the vehicle -- and the natural
## shape for that is a function of (role, epoch), which is what this is.
##
## ── DETERMINISM ──────────────────────────────────────────────────────────────
## Nothing here draws a random number or reads a clock. loadout() is a pure
## function of (role, epoch): the same role at the same epoch produces the same
## mounts in the same order, every run. The only Dictionary is a literal that is
## indexed and never iterated.

## docs/05 runs seven epochs; docs/03's armour and gun ladder runs six
## generations. This is the mapping, and it is deliberately not linear at the
## top: the 1990s and 2000s are one generation apart in armour terms and two
## epochs apart in time.
##
## Index by epoch, 1-7. Slot 0 is unused padding so the epoch indexes directly.
const GEN_BY_EPOCH := [1, 1, 2, 3, 4, 4, 5, 6]

## Category masks, so the reader can see what a weapon is FOR.
const VS_GROUND := 1 << SimTypes.Category.GROUND
const VS_SURFACE := 1 << SimTypes.Category.SURFACE
const VS_AIR := 1 << SimTypes.Category.AIR
const VS_SUB := 1 << SimTypes.Category.SUBSURFACE
const VS_SURFACE_TARGETS := VS_GROUND | VS_SURFACE
const VS_EVERYTHING := VS_GROUND | VS_SURFACE | VS_AIR | VS_SUB


## docs/03's generation for a given epoch.
static func generation(epoch: int) -> int:
	var e: int = clampi(epoch, 1, 7)
	return GEN_BY_EPOCH[e]


## role -> bool. Memoised because the victory layer asks this of every living
## unit once a second, and loadout() BUILDS its answer -- a SimWeaponDef and a
## SimMunitionDef per mount -- so asking it in a loop allocates a few hundred
## short-lived objects a second to answer a question whose answer never
## changes. Indexed, never iterated, so it cannot affect ordering.
static var _combatant_cache: Dictionary = {}


## Does this role carry a weapon at all? The victory layer asks, because
## "the player still has a fuel truck" must not count as "the player can
## still fight."
static func is_combatant(role: String) -> bool:
	if _combatant_cache.has(role):
		return _combatant_cache[role]
	# Epoch 4 is the probe epoch: a role that carries nothing in the middle of
	# the timeline carries nothing at either end of it. Nothing in the table
	# gains or loses a weapon with the epoch -- only the round changes.
	var answer := not loadout(role, 4).is_empty()
	_combatant_cache[role] = answer
	return answer


## Give a unit everything its role carries. Returns the number of mounts added.
## Called once, at spawn, by whoever spawned the unit -- SimWorld._arm_new_units
## for production, SimMatch for the starting forces.
static func arm(weapons: SimWeaponCycle, unit: int, role: String,
		epoch: int) -> int:
	if weapons == null or role == "":
		return 0
	var mounts := loadout(role, epoch)
	for m in mounts:
		var entry := m as Dictionary
		weapons.arm(unit, entry["weapon"], entry["munition"],
			float(entry["reload"]), int(entry.get("rounds", -1)))
	return mounts.size()


## The longest reach this role has, in km. The AI's standoff logic and the HUD
## both want it, and neither should have to walk the mount list.
static func reach_km(role: String, epoch: int) -> float:
	var best := 0.0
	for m in loadout(role, epoch):
		best = maxf(best, (m["weapon"] as SimWeaponDef).max_range_km)
	return best


# ═══════════════════════════════════════════════════════════════════════════
# THE TABLE
#
# Each entry is {"weapon": SimWeaponDef, "munition": SimMunitionDef,
# "reload": seconds, "rounds": magazine (-1 = unlimited)}.
#
# Ranges are quoted in KILOMETRES and reload in SECONDS at full crew
# efficiency; SimWeaponCycle lengthens the reload for a shaken or wounded crew.
# Where a figure grows with the epoch it grows off the GENERATION, so it moves
# on docs/03's ladder rather than on a smooth per-epoch curve.
# ═══════════════════════════════════════════════════════════════════════════

static func loadout(role: String, epoch: int) -> Array:
	var g := generation(epoch)
	var e: int = clampi(epoch, 1, 7)

	match role:
		# ── armour ──────────────────────────────────────────────────────────
		"mbt":
			# docs/03's gun ladder, straight out of SimArmorScheme so the tank
			# and the round it fires can never drift apart.
			var out := [_gun("main gun", 0.0, 2.6 + 0.28 * float(g), VS_SURFACE_TARGETS,
				SimArmorScheme.make_gun_round(g), 7.5 - 0.3 * float(g))]
			if e >= 5:
				# Gun-launched ATGM: the answer to being out-ranged by a
				# missile carrier, and the reason a late MBT is not simply a
				# better version of an early one.
				out.append(_atgm_mount("gun-launched ATGM", g, 0.4, 5.0, 22.0))
			return out
		"light_tank":
			return [_gun("high-velocity gun", 0.0, 2.2 + 0.24 * float(g),
				VS_SURFACE_TARGETS, SimArmorScheme.make_gun_round(maxi(g - 1, 1)),
				6.5 - 0.25 * float(g))]
		"ifv":
			return [
				_autocannon(g, 2.0 + 0.12 * float(g)),
				_atgm_mount("vehicle ATGM", g, 0.3, 3.0 + 0.35 * float(g), 16.0),
			]
		"apc":
			return [_autocannon(maxi(g - 1, 1), 1.4 + 0.10 * float(g))]
		"recon_vehicle":
			return [_autocannon(maxi(g - 2, 1), 1.2)]
		"atgm_carrier":
			return [_atgm_mount("ATGM launcher", g, 0.3,
				3.2 + 0.45 * float(g), 14.0)]

		# ── fires ───────────────────────────────────────────────────────────
		# Indirect fire needs only TQ2 (TRACK), which is why artillery is the
		# one arm that can be fed entirely by somebody else's radar -- and why
		# firing it lights up a counter-battery plot. Long flight times are not
		# a drawback here, they are the mechanism.
		"sph":
			return [_artillery("155mm howitzer", 14.0 + 3.0 * float(g), 8.0, g)]
		"towed_artillery":
			return [_artillery("towed howitzer", 11.0 + 2.0 * float(g), 12.0, g)]
		"mortar_carrier":
			return [_artillery("120mm mortar", 5.0 + 0.6 * float(g), 5.0, g, 18.0)]
		"mortar_team":
			return [_artillery("81mm mortar", 3.2 + 0.4 * float(g), 6.0, g, 12.0)]
		"mlrs":
			# A salvo, not a shot: long reload, wide lethal radius, and it will
			# not be doing it twice in a hurry.
			return [_artillery("rocket salvo", 24.0 + 6.0 * float(g), 34.0, g, 48.0)]
		"ballistic_launcher":
			return [_ballistic(g)]
		"coastal_asm", "missile_boat":
			return [_asm(g)]
		"coastal_battery":
			return [_gun("coastal gun", 0.5, 16.0, VS_SURFACE, _he_shell(g, 26.0), 9.0)]

		# ── air defence ─────────────────────────────────────────────────────
		"spaag":
			return [_aa_gun(g)]
		"shorad_sam":
			return [_sam("SHORAD SAM", SimTypes.Guidance.IR_EO, 0.4,
				5.0 + 1.4 * float(g), 6.0, g)]
		"manpads_team":
			return [_sam("MANPADS", SimTypes.Guidance.IR_EO, 0.3,
				3.0 + 0.7 * float(g), 9.0, g)]
		"medium_sam_launcher", "fixed_sam":
			return [_sam("medium SAM", SimTypes.Guidance.SARH, 2.0,
				20.0 + 6.0 * float(g), 8.0, g)]
		"long_sam_launcher":
			return [_sam("long-range SAM",
				SimTypes.Guidance.ARH if e >= 5 else SimTypes.Guidance.SARH,
				5.0, 55.0 + 18.0 * float(g), 11.0, g)]

		# ── infantry ────────────────────────────────────────────────────────
		"rifle_squad", "special_forces", "engineer_squad", "recon_team":
			var reach := 0.5 if role != "special_forces" else 0.7
			return [_gun("small arms", 0.0, reach, VS_GROUND,
				_small_arms(), 1.2)]
		"at_team":
			return [_atgm_mount("infantry ATGM", g, 0.15,
				1.8 + 0.4 * float(g), 15.0)]

		# ── aircraft ────────────────────────────────────────────────────────
		# Air behaviour is classification only in this build: aircraft are
		# armed and can be ordered to engage, but there is no takeoff, no
		# altitude profile and no RTB. Arming them anyway is honest -- an
		# aircraft on the apron that gets strafed should be able to shoot back.
		"interceptor", "air_superiority":
			return [_aam(g, e)]
		"multirole":
			return [_aam(g, e), _agm(g)]
		"strike_aircraft", "cas", "attack_helicopter", "armed_uav", "stealth_strike", "bomber":
			return [_agm(g)]
		"sead":
			return [_harm(g)]
		"asw_helicopter", "maritime_patrol":
			return [_asw_torpedo()]

		# ── naval ───────────────────────────────────────────────────────────
		"corvette", "patrol_vessel":
			return [_gun("naval gun", 0.3, 12.0, VS_SURFACE_TARGETS,
				_he_shell(g, 18.0), 4.0)]
		"asw_frigate":
			return [_gun("naval gun", 0.3, 14.0, VS_SURFACE_TARGETS,
				_he_shell(g, 18.0), 4.0), _asw_torpedo()]
		"air_defence_destroyer":
			return [_sam("naval SAM", SimTypes.Guidance.SARH, 2.0,
				40.0 + 14.0 * float(g), 5.0, g),
				_gun("naval gun", 0.3, 16.0, VS_SURFACE_TARGETS,
					_he_shell(g, 20.0), 4.0)]
		"cruiser":
			return [_asm(g), _sam("naval SAM", SimTypes.Guidance.SARH, 2.0,
				40.0 + 14.0 * float(g), 5.0, g)]
		"ssk", "ssn", "aip_sub", "midget_sub":
			return [_heavy_torpedo(g)]

		# ── structures that shoot ───────────────────────────────────────────
		"bunker":
			return [_gun("bunker gun", 0.0, 1.6, VS_GROUND,
				_autocannon_round(maxi(g - 1, 1)), 2.6)]

	# Everything else -- trucks, radars, jammers, factories, derricks -- is
	# unarmed, and that is a design statement rather than an omission. docs/09's
	# Interdiction doctrine only means anything if the things it hunts cannot
	# shoot back.
	return []


# ═══════════════════════════════════════════════════════════════════════════
# BUILDERS. One per weapon family, so a change to how (say) an ATGM ages
# happens once rather than in nine table rows.
# ═══════════════════════════════════════════════════════════════════════════

static func _mount(weapon: SimWeaponDef, munition: SimMunitionDef,
		reload_s: float, rounds := -1) -> Dictionary:
	return {"weapon": weapon, "munition": munition,
		"reload": reload_s, "rounds": rounds}


static func _gun(gun_name: String, min_km: float, max_km: float, mask: int,
		round_def: SimMunitionDef, reload_s: float) -> Dictionary:
	return _mount(SimWeaponDef.new({
		"name": gun_name, "guidance": SimTypes.Guidance.UNGUIDED,
		"min_range_km": min_km, "max_range_km": max_km,
		"target_mask": mask}), round_def, reload_s)


## An autocannon is a KE weapon that opens light armour and is refused by a
## tank's glacis at any range -- which is exactly the refusal docs/03 wants an
## IFV to run into when it meets an MBT head-on.
static func _autocannon(gen: int, max_km: float) -> Dictionary:
	return _gun("autocannon", 0.0, max_km, VS_SURFACE_TARGETS | VS_AIR,
		_autocannon_round(gen), 2.4)


static func _autocannon_round(gen: int) -> SimMunitionDef:
	return SimMunitionDef.new({
		"name": "%dmm APDS" % (20 + 5 * gen), "tier": SimMunitionDef.Tier.B,
		"guidance": SimTypes.Guidance.UNGUIDED,
		"muzzle_velocity": 1100.0 + 40.0 * float(gen),
		"dispersion_mrad": 0.9, "fuze": SimMunitionDef.Fuze.CONTACT,
		"lethal_radius_m": 0.0, "drag_coefficient": 0.00016,
		"max_flight_seconds": 10.0,
		"damage_class": SimTypes.DamageClass.KE,
		"penetration_mm": 22.0 + 12.0 * float(gen),
		"warhead_damage": 20.0})


static func _small_arms() -> SimMunitionDef:
	return SimMunitionDef.new({
		"name": "rifle fire", "tier": SimMunitionDef.Tier.B,
		"guidance": SimTypes.Guidance.UNGUIDED,
		"muzzle_velocity": 900.0, "dispersion_mrad": 2.0,
		"fuze": SimMunitionDef.Fuze.CONTACT, "lethal_radius_m": 0.0,
		"drag_coefficient": 0.0003, "max_flight_seconds": 6.0,
		"damage_class": SimTypes.DamageClass.KE,
		"penetration_mm": 10.0, "warhead_damage": 8.0})


## docs/03's escape valve, aged. CE does not bleed with range, so an ATGM is
## the one weapon that hits as hard at 4 km as at 400 m -- and tandem from
## generation 4 is what stops ERA being a free answer to it.
static func _atgm_mount(atgm_name: String, gen: int, min_km: float,
		max_km: float, reload_s: float) -> Dictionary:
	var m := SimMunitionDef.atgm()
	m.name = "%s round" % atgm_name
	m.damage_class = SimTypes.DamageClass.CE
	m.penetration_mm = 320.0 + 115.0 * float(gen)
	m.tandem = gen >= 4
	m.warhead_damage = 90.0
	# Generation 4 onward is fire-and-forget rather than wire-guided, which is
	# docs/11 §5.3's ATGM ladder in one line.
	var guidance := SimTypes.Guidance.IR_EO if gen >= 4 else SimTypes.Guidance.SACLOS
	m.guidance = guidance
	m.max_speed = 240.0 + 30.0 * float(gen)
	return _mount(SimWeaponDef.new({
		"name": atgm_name, "guidance": guidance,
		"min_range_km": min_km, "max_range_km": max_km,
		"seeker_range_km": max_km if guidance == SimTypes.Guidance.IR_EO else 0.0,
		"target_mask": VS_SURFACE_TARGETS}), m, reload_s)


static func _he_shell(gen: int, lethal_m: float) -> SimMunitionDef:
	var m := SimMunitionDef.artillery_he()
	m.name = "HE shell"
	m.lethal_radius_m = lethal_m
	m.damage_class = SimTypes.DamageClass.BLAST
	# A high-explosive shell is not a penetrator. It carries a nominal RHA
	# equivalence so it can still hurt a truck or a radar, and it will bounce
	# off a tank's front all day -- which is why artillery suppresses armour
	# and does not defeat it.
	m.penetration_mm = 20.0 + 4.0 * float(gen)
	m.warhead_damage = 120.0
	return m


static func _artillery(gun_name: String, max_km: float, reload_s: float,
		gen: int, lethal_m := 30.0) -> Dictionary:
	return _gun(gun_name, maxf(max_km * 0.06, 0.4), max_km,
		VS_SURFACE_TARGETS, _he_shell(gen, lethal_m), reload_s)


static func _aa_gun(gen: int) -> Dictionary:
	var m := _autocannon_round(gen)
	m.name = "%dmm AA burst" % (23 + 4 * gen)
	m.fuze = SimMunitionDef.Fuze.PROXIMITY
	m.lethal_radius_m = 8.0
	m.damage_class = SimTypes.DamageClass.BLAST
	m.warhead_damage = 45.0
	return _gun("AA cannon", 0.0, 2.0 + 0.35 * float(gen),
		VS_AIR | VS_GROUND, m, 1.8)


static func _sam(sam_name: String, guidance: int, min_km: float, max_km: float,
		reload_s: float, gen: int) -> Dictionary:
	var m := SimMunitionDef.sam_medium()
	m.name = "%s round" % sam_name
	m.guidance = guidance
	m.seeker_gen = clampi(gen, 1, 6)
	m.max_speed = 700.0 + 90.0 * float(gen)
	m.g_available_max = 14.0 + 3.0 * float(gen)
	m.lethal_radius_m = 14.0 + 1.5 * float(gen)
	m.damage_class = SimTypes.DamageClass.BLAST
	m.penetration_mm = 0.0
	m.warhead_damage = 160.0
	m.max_flight_seconds = 30.0 + max_km * 1.2
	return _mount(SimWeaponDef.new({
		"name": sam_name, "guidance": guidance,
		"min_range_km": min_km, "max_range_km": max_km,
		"seeker_range_km": max_km if guidance == SimTypes.Guidance.IR_EO else 0.0,
		"target_mask": VS_AIR}), m, reload_s)


static func _aam(gen: int, epoch: int) -> Dictionary:
	var m: SimMunitionDef
	if epoch >= 7:
		m = SimMunitionDef.aam_ramjet()
	elif gen >= 4:
		m = SimMunitionDef.aam_active()
	else:
		m = SimMunitionDef.aam_medium()
	m.damage_class = SimTypes.DamageClass.BLAST
	m.warhead_damage = 140.0
	return _mount(SimWeaponDef.new({
		"name": "air-to-air missile", "guidance": m.guidance,
		"min_range_km": 0.5, "max_range_km": 18.0 + 12.0 * float(gen),
		"target_mask": VS_AIR}), m, 4.0)


## Air-to-ground: a guided weapon rather than a gun, because everything that
## carries one in docs/12 fires it from outside a SHORAD envelope.
static func _agm(gen: int) -> Dictionary:
	var m := SimMunitionDef.atgm()
	m.name = "air-to-ground missile"
	m.guidance = SimTypes.Guidance.IR_EO
	m.max_speed = 320.0 + 40.0 * float(gen)
	m.g_available_max = 12.0
	m.damage_class = SimTypes.DamageClass.CE
	m.penetration_mm = 500.0 + 90.0 * float(gen)
	m.tandem = gen >= 4
	m.warhead_damage = 150.0
	return _mount(SimWeaponDef.new({
		"name": "air-to-ground missile", "guidance": SimTypes.Guidance.IR_EO,
		"min_range_km": 0.4, "max_range_km": 5.0 + 1.6 * float(gen),
		"seeker_range_km": 5.0 + 1.6 * float(gen),
		"target_mask": VS_SURFACE_TARGETS}), m, 9.0)


## The SEAD duel in one mount. It is refused against anything not radiating,
## which is the gate doing its job, not a bug.
static func _harm(gen: int) -> Dictionary:
	var m := SimMunitionDef.harm()
	m.damage_class = SimTypes.DamageClass.BLAST
	m.warhead_damage = 150.0
	return _mount(SimWeaponDef.new({
		"name": "anti-radiation missile",
		"guidance": SimTypes.Guidance.ANTI_RADIATION,
		"min_range_km": 2.0, "max_range_km": 40.0 + 12.0 * float(gen),
		"target_mask": VS_SURFACE_TARGETS}), m, 12.0)


static func _asm(gen: int) -> Dictionary:
	var m := SimMunitionDef.new({
		"name": "anti-ship missile", "guidance": SimTypes.Guidance.ARH,
		"boost_seconds": 4.0, "boost_accel": 120.0,
		"sustain_seconds": 90.0, "sustain_accel": 3.0,
		"launch_speed": 60.0, "max_speed": 300.0 + 40.0 * float(gen),
		"g_available_max": 10.0, "seeker_gen": clampi(gen, 1, 6),
		"seeker_activation_km": 20.0, "fuze": SimMunitionDef.Fuze.CONTACT,
		"lethal_radius_m": 6.0, "max_flight_seconds": 400.0,
		"damage_class": SimTypes.DamageClass.BLAST,
		"penetration_mm": 0.0, "warhead_damage": 320.0})
	return _mount(SimWeaponDef.new({
		"name": "anti-ship missile", "guidance": SimTypes.Guidance.ARH,
		"min_range_km": 3.0, "max_range_km": 60.0 + 25.0 * float(gen),
		"target_mask": VS_SURFACE}), m, 30.0)


static func _ballistic(gen: int) -> Dictionary:
	# GNSS_INS: coordinates, not a track. The gate lets it fly with no track at
	# all, and it is correspondingly useless against anything that moves.
	var m := SimMunitionDef.new({
		"name": "ballistic missile", "guidance": SimTypes.Guidance.GNSS_INS,
		"boost_seconds": 40.0, "boost_accel": 45.0,
		"launch_speed": 30.0, "max_speed": 1600.0 + 200.0 * float(gen),
		"g_available_max": 3.0, "fuze": SimMunitionDef.Fuze.CONTACT,
		"lethal_radius_m": 40.0, "max_flight_seconds": 600.0,
		"drag_coefficient": 0.00002,
		"damage_class": SimTypes.DamageClass.BLAST,
		"penetration_mm": 0.0, "warhead_damage": 500.0})
	return _mount(SimWeaponDef.new({
		"name": "ballistic missile", "guidance": SimTypes.Guidance.GNSS_INS,
		"min_range_km": 30.0, "max_range_km": 150.0 + 60.0 * float(gen),
		"target_mask": VS_SURFACE_TARGETS}), m, 120.0)


static func _heavy_torpedo(gen: int) -> Dictionary:
	var m := SimMunitionDef.torpedo_heavyweight(26.0 + float(gen))
	m.damage_class = SimTypes.DamageClass.BLAST
	m.warhead_damage = 420.0
	return _mount(SimWeaponDef.new({
		"name": "heavyweight torpedo", "guidance": SimTypes.Guidance.SACLOS,
		"min_range_km": 1.0, "max_range_km": 22.0 + 4.0 * float(gen),
		"target_mask": VS_SURFACE | VS_SUB}), m, 90.0)


static func _asw_torpedo() -> Dictionary:
	var m := SimMunitionDef.torpedo_lightweight_asw()
	m.damage_class = SimTypes.DamageClass.BLAST
	m.warhead_damage = 200.0
	return _mount(SimWeaponDef.new({
		"name": "lightweight torpedo", "guidance": SimTypes.Guidance.ARH,
		"min_range_km": 0.3, "max_range_km": 8.0,
		"target_mask": VS_SUB}), m, 45.0)
