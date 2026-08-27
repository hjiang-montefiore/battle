class_name SimAiMemory
extends RefCounted
## What the AI remembers about contacts, between ticks.
##
## The track table is the AI's picture RIGHT NOW. This is the difference
## between that picture and the last one, which is where three things in
## docs/09 live that a snapshot cannot express:
##
##   * REACTION LATENCY (§2). "8-12 s from new track to action" only means
##     something if the AI knows when a track first appeared. That is a fact
##     about its own observation history, not about the enemy.
##   * LAST KNOWN POSITION (§1.5 blackout test). "Behaviour degrades to
##     last-known-position and active search." A track that decays out of the
##     table stops existing; the belief about where it was does not.
##   * THE DECOY BEING A FEATURE (§1.6). A belief keyed by track id survives
##     the track being wrong. When the AI drives a battlegroup at a chaff
##     bloom, it is because it remembered a contact, not because it was lied
##     to by a system that should have known better.
##
## NO GROUND TRUTH PASSES THROUGH HERE. Everything stored is copied off a
## SimTrack the AI's own faction already holds. Track ids are opaque and never
## reused (SimTrackTable hands out a monotonic counter), so a belief can be
## keyed by one safely.

class Belief extends RefCounted:
	var track_id: int = -1
	var first_seen_s: float = 0.0
	var last_seen_s: float = 0.0
	## Still present in the table as of the last observe().
	var live: bool = true
	var quality: int = SimTypes.TrackQuality.NONE
	var best_quality: int = SimTypes.TrackQuality.NONE
	var classification: int = SimTypes.Classification.UNKNOWN
	var category: int = SimTypes.Category.GROUND
	var x: float = 0.0
	var y: float = 0.0
	var z: float = 0.0
	var vx: float = 0.0
	var vz: float = 0.0
	var bearing_rad: float = 0.0
	var bearing_only: bool = false
	var emitting: bool = false
	var ever_emitted: bool = false
	var confidence: float = 0.0
	var age_s: float = 0.0
	## Group that has claimed this contact, for deconfliction. -1 = unclaimed.
	var claimed_by: int = -1
	## Engagement bookkeeping -- the AI's own fire discipline, not enemy state.
	var orders_issued: int = 0
	var last_order_s: float = -1.0e9

	## Seconds this contact has been known about, which is what the docs/09 §2
	## reaction dial is measured against.
	func known_for(now: float) -> float:
		return now - first_seen_s

	## Where the AI thinks it is now: the believed position, dead-reckoned on
	## from the last observation while the contact is cold. Prediction quality
	## is a SKILL dial (docs/09 §2, "prediction quality on a decaying track"),
	## so a Recruit extrapolates badly and a Warlord extrapolates well -- and
	## neither is told the answer.
	func predicted(now: float, prediction_skill: float) -> PackedFloat32Array:
		if live and bearing_only:
			return PackedFloat32Array([x, z])
		var dt: float = maxf(0.0, now - last_seen_s)
		var k: float = clampf(prediction_skill, 0.0, 1.0)
		# A poor commander barely extrapolates at all; a good one runs the
		# whole elapsed interval out along the last observed velocity.
		return PackedFloat32Array([x + vx * dt * k, z + vz * dt * k])


var _beliefs: Dictionary = {}
## How long a contact that has left the table is still remembered and searched
## for. Beyond this the AI has genuinely lost it.
var horizon_s: float = 240.0
var max_beliefs: int = 512
var forgotten: int = 0


## Fold this tick's picture in. `tracks` is whatever the AI's own table handed
## back; nothing else is read.
func observe(tracks: Array, now: float) -> void:
	for id in ids():
		(_beliefs[id] as Belief).live = false
	for t in tracks:
		var track := t as SimTrack
		if track == null:
			continue
		var b: Belief = _beliefs.get(track.track_id)
		if b == null:
			b = Belief.new()
			b.track_id = track.track_id
			b.first_seen_s = now
			_beliefs[track.track_id] = b
		b.live = true
		b.last_seen_s = now
		b.quality = track.quality
		b.best_quality = maxi(b.best_quality, track.quality)
		b.classification = maxi(b.classification, track.classification)
		b.category = track.category
		b.confidence = track.confidence
		b.age_s = track.age_s
		b.bearing_rad = track.bearing_rad
		b.bearing_only = track.bearing_only
		b.emitting = track.emitting
		if track.emitting:
			b.ever_emitted = true
		if not track.bearing_only:
			b.x = track.pos_x
			b.y = track.pos_y
			b.z = track.pos_z
			b.vx = track.vel_x
			b.vz = track.vel_z


## Ascending track ids. The ONLY way this dictionary is ever iterated --
## docs/06 forbids letting Dictionary order decide an outcome, and which
## contact a battlegroup drives at is very much an outcome.
func ids() -> Array:
	var out: Array = _beliefs.keys()
	out.sort()
	return out


func get_belief(track_id: int) -> Belief:
	return _beliefs.get(track_id)


func count() -> int:
	return _beliefs.size()


## Contacts the AI holds right now, ascending by id.
func live_beliefs() -> Array:
	var out: Array = []
	for id in ids():
		var b: Belief = _beliefs[id]
		if b.live:
			out.append(b)
	return out


## Contacts it held recently and has lost. These are the search objectives in
## the docs/09 §1.5 blackout case -- "degrade to last-known-position and active
## search" is exactly this list, driven at.
func stale_beliefs(now: float) -> Array:
	var out: Array = []
	for id in ids():
		var b: Belief = _beliefs[id]
		if not b.live and (now - b.last_seen_s) <= horizon_s:
			out.append(b)
	return out


func live_count() -> int:
	var n := 0
	for id in ids():
		if (_beliefs[id] as Belief).live:
			n += 1
	return n


## Drop what has gone cold, oldest first, and cap the table so a long match
## cannot grow it without bound.
func forget_expired(now: float) -> void:
	var doomed: Array = []
	for id in ids():
		var b: Belief = _beliefs[id]
		if not b.live and (now - b.last_seen_s) > horizon_s:
			doomed.append(id)
	for id in doomed:
		_beliefs.erase(id)
		forgotten += 1
	if _beliefs.size() <= max_beliefs:
		return
	# Over the cap: shed the oldest ids, which are the oldest contacts, because
	# ids are handed out monotonically.
	var ordered := ids()
	var excess := _beliefs.size() - max_beliefs
	for k in range(excess):
		_beliefs.erase(ordered[k])
		forgotten += 1


func clear_claims() -> void:
	for id in ids():
		(_beliefs[id] as Belief).claimed_by = -1


# ── SAVE / LOAD (SimSave). Beliefs are the AI's memory BETWEEN ticks -- the
# reaction clock, the last known positions, the blackout search objectives --
# so they are state in the fullest sense and every field rides the capture.

func to_dict() -> Dictionary:
	var beliefs: Array = []
	for id in ids():
		beliefs.append(SimSave.enc_props(_beliefs[id]))
	return {
		"horizon_s": SimSave.enc_float(horizon_s),
		"max_beliefs": max_beliefs,
		"forgotten": forgotten,
		"beliefs": beliefs,
	}


func from_dict(d: Dictionary) -> void:
	horizon_s = SimSave.dec_float(d["horizon_s"])
	max_beliefs = int(d["max_beliefs"])
	forgotten = int(d["forgotten"])
	_beliefs.clear()
	for bd in (d["beliefs"] as Array):
		var b := Belief.new()
		SimSave.dec_props(b, bd)
		_beliefs[b.track_id] = b
