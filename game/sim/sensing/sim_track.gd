class_name SimTrack
extends RefCounted
## One faction's hypothesis about one target. docs/02 §5, §6.
##
## A track is NOT a pointer to an entity. It is a belief, and it can be stale,
## wrong, or about something that no longer exists. That distinction is what
## makes the no-cheating AI rule in docs/09 §1 enforceable rather than aspirational:
## the AI is handed track tables, never the entity store, so it cannot read
## ground truth even by accident.

## Opaque id the owning faction uses to refer to this contact. Deliberately NOT
## the entity index -- two factions tracking the same aircraft assign different
## numbers, and neither can infer the other's.
var track_id: int = -1

## Entity index this track is actually about. Sim-internal bookkeeping for
## fusion and decay ONLY. Never exposed to an AI or to the UI layer.
var _truth_index: int = -1

var quality: int = SimTypes.TrackQuality.NONE
var classification: int = SimTypes.Classification.UNKNOWN

## Believed kinematics -- what the sensors reported, not where the target is.
var pos_x: float = 0.0
var pos_y: float = 0.0
var pos_z: float = 0.0
var vel_x: float = 0.0
var vel_y: float = 0.0
var vel_z: float = 0.0

## Bearing-only contacts carry a bearing and no usable range (docs/02 §8.1).
var bearing_rad: float = 0.0
var bearing_only: bool = false

var age_s: float = 0.0            ## seconds since last refresh
var confidence: float = 0.0       ## 0..1
var category: int = SimTypes.Category.AIR
var contributors: PackedStringArray = PackedStringArray()

## True while some sensor is actively holding it this solve. Weapons that must
## be supported through flight (SARH) re-check this every tick.
var supported_now: bool = false

## Set when the contact was seen radiating. ANTI_RADIATION weapons need it, and
## it is also what home-on-jam produces.
var emitting: bool = false


## How long a rung survives without a refresh before it decays to the one below.
## A track that stops being refreshed degrades down the ladder rather than
## vanishing, so the player sees a real tactical picture with stale contacts on
## it instead of a binary fog mask.
const DECAY_FIRE_CONTROL_S := 3.0
const DECAY_TRACK_S := 12.0
const DECAY_CONTACT_S := 45.0


func refresh(q: int, cls: int, conf: float, source: String) -> void:
	if q > quality:
		quality = q
	if cls > classification:
		classification = cls
	confidence = maxf(confidence, conf)
	age_s = 0.0
	supported_now = true
	if not contributors.has(source):
		contributors.append(source)


## Advance the track's own clock and let it fall down the ladder. Returns false
## when the contact has gone cold entirely and should be dropped.
func decay(dt: float) -> bool:
	age_s += dt
	if not supported_now:
		if quality == SimTypes.TrackQuality.FIRE_CONTROL and age_s > DECAY_FIRE_CONTROL_S:
			quality = SimTypes.TrackQuality.TRACK
		elif quality == SimTypes.TrackQuality.TRACK and age_s > DECAY_TRACK_S:
			quality = SimTypes.TrackQuality.CONTACT
			bearing_only = true
		elif quality == SimTypes.TrackQuality.CONTACT and age_s > DECAY_CONTACT_S:
			quality = SimTypes.TrackQuality.NONE
			return false
		# Confidence bleeds off with age even before a rung is lost.
		confidence = maxf(0.0, confidence - dt * 0.05)
	return quality > SimTypes.TrackQuality.NONE


## Dead-reckon the believed position while unsupported, so a stale track drifts
## the way a real one does rather than freezing in place.
func extrapolate(dt: float) -> void:
	if supported_now:
		return
	pos_x += vel_x * dt
	pos_y += vel_y * dt
	pos_z += vel_z * dt


func describe() -> String:
	var q := SimTypes.quality_name(quality)
	var c := SimTypes.classification_name(classification)
	if bearing_only:
		return "TK%d  %-12s %-8s bearing %6.1f deg  age %4.1fs" % [
			track_id, q, c, rad_to_deg(bearing_rad), age_s]
	return "TK%d  %-12s %-8s (%7.1f, %7.1f, %7.1f) age %4.1fs" % [
		track_id, q, c, pos_x, pos_y, pos_z, age_s]
