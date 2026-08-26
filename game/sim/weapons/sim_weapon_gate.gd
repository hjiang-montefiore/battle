class_name SimWeaponGate
extends RefCounted
## "May I shoot?" -- docs/02 §5, weapon gating. This is pillar 1 entire.
##
## Every refusal carries a human-readable reason. docs/02 §9 is blunt about why:
## "If the player cannot see why a shot was refused, the whole design reads as
## a bug." The reason string is a feature, not debug output.


class Result extends RefCounted:
	var allowed: bool = false
	var reason: String = ""
	var required_quality: int = SimTypes.TrackQuality.NONE
	var available_quality: int = SimTypes.TrackQuality.NONE

	func _init(ok: bool, why: String, req := 0, have := 0) -> void:
		allowed = ok
		reason = why
		required_quality = req
		available_quality = have

	func _to_string() -> String:
		return ("%s -- %s (need %s, have %s)" % [
			"CLEAR" if allowed else "REFUSED", reason,
			SimTypes.quality_name(required_quality),
			SimTypes.quality_name(available_quality)])


## The rung each guidance mode needs before it may leave the rail.
static func required_quality(guidance: int) -> int:
	match guidance:
		SimTypes.Guidance.UNGUIDED:
			return SimTypes.TrackQuality.TRACK
		SimTypes.Guidance.SACLOS:
			return SimTypes.TrackQuality.TRACK
		SimTypes.Guidance.SARH:
			return SimTypes.TrackQuality.FIRE_CONTROL
		SimTypes.Guidance.ARH:
			return SimTypes.TrackQuality.FIRE_CONTROL
		SimTypes.Guidance.IR_EO:
			return SimTypes.TrackQuality.TRACK
		SimTypes.Guidance.COMMAND_LINK:
			return SimTypes.TrackQuality.TRACK
		SimTypes.Guidance.GNSS_INS:
			return SimTypes.TrackQuality.NONE
		SimTypes.Guidance.ANTI_RADIATION:
			return SimTypes.TrackQuality.CONTACT
	return SimTypes.TrackQuality.FIRE_CONTROL


## May this weapon be launched at this track, right now?
static func can_launch(weapon: SimWeaponDef, track: SimTrack,
		range_km: float, datalink_up := true) -> Result:
	var req := required_quality(weapon.guidance)

	# Coordinate-guided munitions need no track at all -- which is exactly why
	# they always work against buildings and never against a moving formation.
	if weapon.guidance == SimTypes.Guidance.GNSS_INS:
		return Result.new(true, "coordinate strike -- no track required", req,
				track.quality if track else 0)

	if track == null or track.quality == SimTypes.TrackQuality.NONE:
		return Result.new(false, "no track on this target", req, 0)

	var have := track.quality

	if range_km > weapon.max_range_km:
		return Result.new(false, "target beyond %.0f km launch range" % weapon.max_range_km, req, have)
	if range_km < weapon.min_range_km:
		return Result.new(false, "inside %.1f km minimum range" % weapon.min_range_km, req, have)

	match weapon.guidance:
		SimTypes.Guidance.ANTI_RADIATION:
			# Homes on the target's own emissions. Switching the radar off is
			# the counter, and it is a complete one.
			if not track.emitting:
				return Result.new(false, "target is not radiating", req, have)
			return Result.new(true, "riding the emission", req, have)

		SimTypes.Guidance.IR_EO:
			if have < req:
				return Result.new(false, "need %s, holding %s" % [
					SimTypes.quality_name(req), SimTypes.quality_name(have)], req, have)
			if weapon.seeker_range_km > 0.0 and range_km > weapon.seeker_range_km:
				return Result.new(false, "outside %.1f km seeker acquisition range"
						% weapon.seeker_range_km, req, have)
			return Result.new(true, "seeker acquired -- immune to RF jamming", req, have)

		SimTypes.Guidance.COMMAND_LINK:
			if not datalink_up:
				return Result.new(false, "datalink down", req, have)
			if have < req:
				return Result.new(false, "need %s from any source, holding %s" % [
					SimTypes.quality_name(req), SimTypes.quality_name(have)], req, have)
			# The shooter and the sensor need not be the same unit.
			return Result.new(true, "firing on a networked track", req, have)

		SimTypes.Guidance.SARH:
			if have < req:
				return Result.new(false, "illuminator not holding %s"
						% SimTypes.quality_name(req), req, have)
			return Result.new(true, "illuminator locked -- must hold to impact", req, have)

	if have < req:
		return Result.new(false, "need %s, holding %s" % [
			SimTypes.quality_name(req), SimTypes.quality_name(have)], req, have)
	return Result.new(true, "clear to engage", req, have)


## Re-checked EVERY tick by the guidance loop, not just at launch. A SARH round
## whose illuminator dies or is jammed mid-flight goes stupid -- which is the
## whole SEAD duel: the SAM must radiate to kill the aircraft, and the HARM
## needs it to keep radiating. Whoever blinks first loses.
static func still_supported(guidance: int, track: SimTrack, datalink_up := true) -> Result:
	match guidance:
		SimTypes.Guidance.SARH:
			if track == null or track.quality < SimTypes.TrackQuality.FIRE_CONTROL:
				return Result.new(false, "illuminator lost the target -- round goes ballistic",
						SimTypes.TrackQuality.FIRE_CONTROL,
						track.quality if track else 0)
			return Result.new(true, "illumination held", SimTypes.TrackQuality.FIRE_CONTROL, track.quality)

		SimTypes.Guidance.SACLOS:
			if track == null or track.quality < SimTypes.TrackQuality.TRACK:
				return Result.new(false, "operator lost line of sight",
						SimTypes.TrackQuality.TRACK, track.quality if track else 0)
			return Result.new(true, "crosshair held", SimTypes.TrackQuality.TRACK, track.quality)

		SimTypes.Guidance.COMMAND_LINK:
			if not datalink_up:
				return Result.new(false, "datalink cut mid-flight",
						SimTypes.TrackQuality.TRACK, track.quality if track else 0)
			if track == null or track.quality < SimTypes.TrackQuality.TRACK:
				return Result.new(false, "network lost the track",
						SimTypes.TrackQuality.TRACK, track.quality if track else 0)
			return Result.new(true, "datalink holding", SimTypes.TrackQuality.TRACK, track.quality)

		SimTypes.Guidance.ANTI_RADIATION:
			if track != null and not track.emitting:
				# Memory mode: it keeps flying at the last known position, but
				# a mobile emitter that shuts down and moves defeats it.
				return Result.new(true, "emitter shut down -- flying on memory",
						SimTypes.TrackQuality.CONTACT, track.quality)
			return Result.new(true, "emission held", SimTypes.TrackQuality.CONTACT,
					track.quality if track else 0)

		SimTypes.Guidance.ARH:
			# Self-promotes to TERMINAL at seeker range; the launcher is then
			# free to break away. This is the M5 fire-and-forget cliff.
			return Result.new(true, "seeker active -- launcher free to break away",
					SimTypes.TrackQuality.TERMINAL,
					track.quality if track else 0)

	return Result.new(true, "no mid-course support required",
			SimTypes.TrackQuality.NONE, track.quality if track else 0)
