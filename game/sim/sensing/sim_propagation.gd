class_name SimPropagation
extends RefCounted
## Detection physics. docs/02 §3, §4, §7.
##
## The whole design rests on ONE asymmetry: active sensing is two-way and falls
## as 1/R^4, passive sensing is one-way and falls as 1/R^2. Everything else --
## stealth feeling dramatic, radiating feeling dangerous, EMCON being an
## agonising choice, AEW&C mattering -- is a consequence of those two lines and
## the horizon formula. None of it is scripted.

const T := preload("res://sim/core/sim_types.gd")

## 4/3-earth approximation. Heights in metres, result in kilometres.
const HORIZON_K := 4.12

## An ESM receiver hears a radar well before that radar sees the ESM's platform,
## because the emission reaches it one-way while the skin return is two-way.
## docs/02 §3 puts the ratio at 1.5-3x; this is the mid-band figure that the
## radar/ESM generation ladders then modulate.
const ESM_BASE_ADVANTAGE := 2.2


## Two-way (active) detection range.
##     R = reference_range * (rcs / 1 m^2)^0.25
##
## The fourth root is why incremental stealth is worthless and only
## order-of-magnitude reductions count: halving RCS costs only 16% of range.
static func active_range_km(reference_range_km: float, rcs_m2: float) -> float:
	if rcs_m2 <= 0.0 or reference_range_km <= 0.0:
		return 0.0
	return reference_range_km * pow(rcs_m2, 0.25)


## One-way (passive) detection range.
##     R = reference_range * (source_power / reference_power)^0.5
static func passive_range_km(reference_range_km: float, source_power: float,
		reference_power := 1.0) -> float:
	if source_power <= 0.0 or reference_range_km <= 0.0 or reference_power <= 0.0:
		return 0.0
	return reference_range_km * sqrt(source_power / reference_power)


## Radar horizon. Both heights in metres, result in kilometres.
##     R = 4.12 * (sqrt(h_sensor) + sqrt(h_target))
##
## This single formula is the entire justification for pillar 5. An AEW aircraft
## gets no special rule and no "reveal map" ability -- it is a radar mounted
## 9 km up, and the arithmetic does the rest.
static func horizon_km(sensor_height_m: float, target_height_m: float) -> float:
	var hs := maxf(sensor_height_m, 0.0)
	var ht := maxf(target_height_m, 0.0)
	return HORIZON_K * (sqrt(hs) + sqrt(ht))


## Effective range is whichever limit bites first. Terrain masking and the
## acoustic layer are applied by the solver as hard cutoffs before this.
static func effective_range_km(propagation_km: float, horizon_km_: float) -> float:
	return minf(propagation_km, horizon_km_)


# ── Jamming (docs/02 §7.2) ───────────────────────────────────────────────────

## Jammer-to-noise ratio at the victim radar.
##
## The jammer's signal reaches the radar one-way, so it falls as 1/R^2 while the
## target's skin return falls as 1/R^4. That difference IS burn-through: closing
## the range always favours the radar. Jamming buys distance, never immunity.
static func jam_noise_ratio(jammer_power: float, jammer_range_km: float,
		eccm_rating: int, band_match := 1.0) -> float:
	if jammer_power <= 0.0 or band_match <= 0.0:
		return 0.0
	var r := maxf(jammer_range_km, 0.05)   # avoid a singularity at zero range
	var jnr := (jammer_power * band_match) / (r * r)
	# Each ECCM generation roughly halves the effective jamming.
	return jnr / pow(2.0, float(clampi(eccm_rating, 0, 5)))


## Detection range against a jammed background.
##     R_eff = R_nominal * (1 / (1 + JNR))^0.25
##
## The quarter power falls out of the radar equation: the radar needs the skin
## return to beat noise+jamming, and the skin return is a 1/R^4 quantity.
static func jammed_range_km(nominal_range_km: float, jam_noise_ratio_: float) -> float:
	if jam_noise_ratio_ <= 0.0:
		return nominal_range_km
	return nominal_range_km * pow(1.0 / (1.0 + jam_noise_ratio_), 0.25)


## Range at which a self-protection jammer's target becomes visible anyway.
## Skin return ~ rcs/R^4, jammer ~ P/R^2, so they cross where R^2 = rcs*k/P.
static func burn_through_km(nominal_range_km: float, rcs_m2: float,
		jammer_power: float, eccm_rating: int) -> float:
	if jammer_power <= 0.0:
		return INF
	var eccm := pow(2.0, float(clampi(eccm_rating, 0, 5)))
	var k := nominal_range_km * nominal_range_km * sqrt(maxf(rcs_m2, 1e-9))
	return sqrt(k * eccm / jammer_power)


## How far away an ESM receiver hears a radiating radar, expressed as a multiple
## of that radar's own detection range against the ESM platform.
##
## R5 AESA/LPI spreads emitted energy and partially defeats the asymmetry;
## P5 ESM re-closes the loop. The two ladders chase each other across epochs
## 5-7, which is what the real contest looks like (docs/11 §3, §7).
static func esm_advantage(radar_gen: int, esm_gen: int) -> float:
	var adv := ESM_BASE_ADVANTAGE
	# LPI waveforms from R5 onward
	if radar_gen >= 5:
		adv *= 0.45
	if radar_gen >= 6:
		adv *= 0.85
	# A matching ESM generation claws it back
	if esm_gen >= 5:
		adv *= 2.0
	if esm_gen <= 1:
		adv *= 0.6   # bare warning: "something is illuminating me"
	return maxf(adv, 0.35)


## Whether a pre-pulse-Doppler radar can see a low-flying target at all.
##
## Before R3, a radar looking down sees ground clutter and nothing else, which
## makes terrain-following flight a COMPLETE defence in epochs 1-2 and merely a
## good idea afterwards. docs/11 §3 calls this one of the eight cliffs.
static func has_look_down(radar_gen: int, sensor_height_m: float,
		target_height_m: float) -> bool:
	if radar_gen >= 3:
		return true
	# Looking level or up is fine even for a conical-scan set.
	return target_height_m >= sensor_height_m


## Early AEW cannot see over land: ground clutter swamps a pre-pulse-Doppler
## radar looking down. Makes AEW a maritime-only asset in epochs 1-2 and the
## epoch 3 unlock feel enormous (docs/11 §4).
static func aew_works_overland(aew_gen: int) -> bool:
	return aew_gen >= 3
