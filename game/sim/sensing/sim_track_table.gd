class_name SimTrackTable
extends RefCounted
## One faction's picture of the world. docs/02 §6.
##
## Tracks are stored per FACTION, not per unit. Every sensor contributes
## observations; fusion merges them into one track per target at the best
## available quality; every unit consumes the result. That single decision buys
## shared situational awareness, datalink, cooperative engagement and meaningful
## EW targets with no further machinery.
##
## This class is also the AI's ONLY input (docs/06, docs/09 §1). It is handed a
## track table and never the entity store, so "the AI has no information the
## player would not have" is enforced by what it is possible to call, not by
## discipline.

var faction: int = 0

## Opaque track id -> SimTrack. Ids are per-faction and monotonic, so two
## factions holding the same aircraft assign unrelated numbers.
var _tracks: Dictionary = {}

## entity index -> track id, for fusion. Sim-internal; never handed out.
var _by_truth: Dictionary = {}

var _next_id: int = 1

## Epoch-gated: how many units may act on the shared picture at once. An A1 AEW
## aircraft vectors one or two interceptors; an A5 runs the whole air battle
## (docs/11 §4). Without this cap one AEW aircraft makes an entire air force
## omniscient in every epoch.
var controlled_engagement_cap: int = 999


func _init(faction_id := 0) -> void:
	faction = faction_id


## Deterministic ordering. Dictionary iteration order is not guaranteed and
## docs/06 forbids relying on it anywhere in the sim.
func track_ids() -> Array:
	var ids: Array = _tracks.keys()
	ids.sort()
	return ids


func get_track(track_id: int) -> SimTrack:
	return _tracks.get(track_id)


func count() -> int:
	return _tracks.size()


## Fold one sensor observation into the picture. Called by the solver; the only
## place _truth_index is ever set.
func contribute(truth_index: int, quality: int, classification: int,
		confidence: float, source: String,
		px: float, py: float, pz: float,
		vx: float, vy: float, vz: float,
		bearing: float, bearing_only: bool,
		category: int, emitting: bool) -> SimTrack:
	var t: SimTrack
	if _by_truth.has(truth_index):
		t = _tracks[_by_truth[truth_index]]
	else:
		t = SimTrack.new()
		t.track_id = _next_id
		t._truth_index = truth_index
		_next_id += 1
		_tracks[t.track_id] = t
		_by_truth[truth_index] = t.track_id

	# Position only comes from a contributor at least as good as what we hold,
	# so a bearing-only ESM hit never degrades a fire-control solution.
	var upgrades := quality >= t.quality
	if upgrades and not bearing_only:
		t.pos_x = px
		t.pos_y = py
		t.pos_z = pz
		t.vel_x = vx
		t.vel_y = vy
		t.vel_z = vz
		t.bearing_only = false
	elif bearing_only and t.quality <= SimTypes.TrackQuality.CONTACT:
		t.bearing_rad = bearing
		t.bearing_only = true
	if bearing_only:
		# A passive cut always refreshes the bearing even on a better track --
		# this is what lets ESM classify a target the radar can only locate.
		t.bearing_rad = bearing

	t.category = category
	if emitting:
		t.emitting = true
	t.refresh(quality, classification, confidence, source)
	return t


## Age every track, decay unsupported ones down the ladder, drop the cold ones.
## Run once per sensor solve, after all contributions.
func decay_all(dt: float) -> void:
	var dead: Array = []
	for id in track_ids():
		var t: SimTrack = _tracks[id]
		t.extrapolate(dt)
		if not t.decay(dt):
			dead.append(id)
	for id in dead:
		var t: SimTrack = _tracks[id]
		_by_truth.erase(t._truth_index)
		_tracks.erase(id)


## Clear the per-solve support flags. Anything not re-contributed this solve is
## then correctly treated as unsupported by decay_all().
func begin_solve() -> void:
	for id in track_ids():
		var t: SimTrack = _tracks[id]
		t.emitting = false
		# Clearing the supported FLOOR is what makes decay work. Leaving it set
		# would restore the old behaviour where any contribution froze the rung.
		t.support_q = SimTypes.TrackQuality.NONE


## Best track the faction holds on a given entity, or null. Sim-internal --
## the weapon gate uses it; the AI layer must not.
func _track_for_truth(truth_index: int) -> SimTrack:
	if not _by_truth.has(truth_index):
		return null
	return _tracks.get(_by_truth[truth_index])


## Everything at or above a rung, ordered deterministically.
func tracks_at_least(q: int) -> Array:
	var out: Array = []
	for id in track_ids():
		var t: SimTrack = _tracks[id]
		if t.quality >= q:
			out.append(t)
	return out


## Contacts seen radiating -- the target set for ANTI_RADIATION weapons, and
## what home-on-jam produces for free at very long range.
func emitters() -> Array:
	var out: Array = []
	for id in track_ids():
		var t: SimTrack = _tracks[id]
		if t.emitting:
			out.append(t)
	return out


# ── SAVE / LOAD (SimSave) ────────────────────────────────────────────────────
# Every SimTrack field rides the generic capture, _truth_index included -- it
# is sim-internal bookkeeping, and a save file is sim-internal. _by_truth is
# derived and rebuilt rather than stored twice.

func to_dict() -> Dictionary:
	var tracks: Array = []
	for id in track_ids():
		tracks.append(SimSave.enc_props(_tracks[id]))
	return {
		"faction": faction,
		"next_id": _next_id,
		"controlled_engagement_cap": controlled_engagement_cap,
		"tracks": tracks,
	}


func from_dict(d: Dictionary) -> void:
	faction = int(d["faction"])
	_next_id = int(d["next_id"])
	controlled_engagement_cap = int(d["controlled_engagement_cap"])
	_tracks.clear()
	_by_truth.clear()
	for td in (d["tracks"] as Array):
		var t := SimTrack.new()
		SimSave.dec_props(t, td)
		_tracks[t.track_id] = t
		_by_truth[t._truth_index] = t.track_id


func describe() -> String:
	var lines := PackedStringArray()
	lines.append("faction %d -- %d track(s)" % [faction, _tracks.size()])
	for id in track_ids():
		lines.append("  " + (_tracks[id] as SimTrack).describe())
	return "\n".join(lines)
