class_name SimSave
extends RefCounted
## Save and restore a running simulation. One Dictionary in, one Dictionary out,
## and the golden property is BEHAVIOURAL IDENTITY: a restored match must
## continue exactly as the unbroken one would -- same winner, same tick, same
## kills, same shots, same survivors. test_saveload.gd asserts that property
## end to end, so any field this file forgets shows up as a hash divergence
## rather than a mystery three saves later.
##
## ── FORMAT ───────────────────────────────────────────────────────────────────
## One Dictionary, JSON on disk, versioned by `save_format`. A mismatched
## version is REFUSED plainly (null + a stated error), never half-loaded.
##
## Two encoding decisions, both about exactness rather than taste:
##
##   * Packed numeric arrays are base64 of their raw bytes. JSON has no float32
##     and no typed arrays, and printing floats as decimal risks the one thing
##     this file exists to prevent: a position that comes back one ulp off and
##     diverges the replay ten minutes later. Raw bytes round-trip bit-exactly.
##     (var_to_str was the documented alternative; bytes were chosen because
##     their round-trip is exact BY CONSTRUCTION, not by printf precision.)
##   * Scalar floats ride JSON with full_precision=true, which Godot guarantees
##     round-trips a double. 64-bit integers do NOT survive JSON (numbers parse
##     back as doubles, exact only to 2^53), so RNG states and seeds -- the only
##     genuinely 64-bit values in the sim -- are carried as strings.
##
## After a JSON round trip every number is a float, so every decode path here
## coerces explicitly (int()/float()/bool()) against the target field's type.
##
## ── WHAT IS DELIBERATELY NOT SERIALIZED ──────────────────────────────────────
## Every drop below is justified by one of two arguments; anything that fits
## neither is serialized.
##
##   REBUILT DETERMINISTICALLY (a memo over state that IS saved):
##     * SimMovement._pass_cache/_speed_cache -- pure function of the terrain
##       heightfield (saved bit-exactly) and the unit category.
##     * SimMovement A* scratch (_stamp/_gscore/_parent/_closed_stamp/_gen,
##       heap) -- generation-stamped; a fresh generation matches no stale stamp,
##       exactly as an incremented one matches none, so the first search after
##       load expands identically.
##     * SimMovement._buckets -- rebuilt at the top of every movement step
##       before any read.
##     * SimAiDirector._role_cache -- memo of unit name/category, both
##       immutable after spawn.
##     * SimAiDirector.loadouts -- rebuilt in _init as a pure function of
##       SimAiRoles; set_loadout is test-only and never used in a match.
##     * SimArsenal/SimRoster static caches -- pure memos of static tables.
##
##   CONSUMED WITHIN THE SAME TICK it is produced (a save happens between
##   ticks, so the next tick clears it before anything reads it):
##     * SimMunitions.last_impacts (cleared at the top of every munitions step;
##       its consumers ran in the same tick it was filled).
##     * SimEconomy.spawned_this_step / fuel_starvation (read by the economy
##       slot itself, reset next economy step).
##     * SimVictory.newly_eliminated / events (drained by SimMatch immediately
##       after the victory step that filled them).
##     * SimMovement._pool/_in_step/_last_plan_deferred/last_goal_* (per plan
##       or per tick), SimSensorSolver._jammers/_jnr_cache/_alt_cache (cleared
##       at the top of every solve).
##
##   COSMETIC (never read by sim logic; affects logs and describe() only):
##     * the capped string logs: SimMunitions.combat_log, the resolver's
##       combat_log, SimWeaponCycle.gate_log/last_refusal, SimEconomy.events,
##       SimTransport.event_log, SimSortie.log, SimAiDirector.decision_log,
##       SimMatch.events, solver profiling counters and
##       last_pair_evaluations/last_detections, SimMovement.last_expansions,
##       SimOwnForcesView.denied_queries.
##
## NOTE: SimSensorSolver._los_cache is NOT dropped. It looks like a memo, but
## its entries carry the historical endpoints they were marched from (stale by
## up to LOS_CACHE_M), so a fresh empty cache can answer a boundary case
## differently from a warm one. It is state, and it is saved.

const FORMAT := 1


# ═══════════════════════════════════════════════════════════════════════════
# ENTRY POINTS
# ═══════════════════════════════════════════════════════════════════════════

## Snapshot a SimMatch or a bare SimWorld into one Dictionary.
static func save(target) -> Dictionary:
	var out := {"save_format": FORMAT}
	if target is SimMatch:
		var m := target as SimMatch
		out["match"] = m.to_dict()
		out["world"] = m.world.to_dict()
	elif target is SimWorld:
		out["world"] = (target as SimWorld).to_dict()
	else:
		push_error("SimSave.save: expected a SimMatch or a SimWorld")
		return {}
	return out


## Rebuild a SimMatch (when the save carries one) or a bare SimWorld.
## Returns null, with a stated error, on a version mismatch or a broken dict.
static func restore(d: Dictionary):
	var version := int(d.get("save_format", -1))
	if version != FORMAT:
		push_error("SimSave: refusing to load save format %d (this build reads %d)"
			% [version, FORMAT])
		return null
	if not d.has("world"):
		push_error("SimSave: save carries no world")
		return null
	if d.has("match"):
		return SimMatch.from_save(d)
	return _restore_bare_world(d["world"] as Dictionary)


## The file format: JSON, full float precision. See the class comment.
static func to_json(target) -> String:
	return JSON.stringify(save(target), "", true, true)


static func from_json(text: String):
	var parsed = JSON.parse_string(text)
	if not (parsed is Dictionary):
		push_error("SimSave: not a save file (JSON did not parse to a dictionary)")
		return null
	return restore(parsed as Dictionary)


static func _restore_bare_world(wd: Dictionary) -> SimWorld:
	var w := SimWorld.new(1)
	if wd.get("terrain") != null:
		w.use_terrain(terrain_from_dict(wd["terrain"] as Dictionary))
	# Optional layers exist in the save only if they existed in the world.
	if wd.has("fire_control"):
		w.fire_control = SimFireControl.new(w.entities, w.weapons, w.solver, w.economy)
	if wd.has("sortie"):
		SimSortie.install(w)
	if wd.has("patrol"):
		SimPatrol.install(w)
	if wd.has("transport"):
		SimTransport.install(w)
	w.apply_dict(wd)
	return w


# ═══════════════════════════════════════════════════════════════════════════
# TERRAIN
# All SimTerrain fields are public, so this lives here rather than adding a
# to_dict inside the terrain workflow's files. The heightfield is saved
# bit-exactly: the movement memo and every LOS answer derive from it.
# ═══════════════════════════════════════════════════════════════════════════

static func terrain_to_dict(t: SimTerrain) -> Dictionary:
	return {
		"cells_x": t.cells_x, "cells_z": t.cells_z,
		"cell_size_m": enc_float(t.cell_size_m),
		"heights": b64_f32(t.heights),
		"name": t.name,
		"centre_lat": enc_float(t.centre_lat),
		"centre_lon": enc_float(t.centre_lon),
		"georeferenced": t.georeferenced,
		"los_step_m": enc_float(t.los_step_m),
	}


static func terrain_from_dict(d: Dictionary) -> SimTerrain:
	var t := SimTerrain.new(int(d["cells_x"]), int(d["cells_z"]),
		dec_float(d["cell_size_m"]), String(d["name"]))
	t.heights = un_f32(String(d["heights"]))
	t.centre_lat = dec_float(d["centre_lat"])
	t.centre_lon = dec_float(d["centre_lon"])
	t.georeferenced = bool(d["georeferenced"])
	t.los_step_m = dec_float(d["los_step_m"])
	return t


# ═══════════════════════════════════════════════════════════════════════════
# VALUE ENCODING -- JSON-safe and bit-exact
# ═══════════════════════════════════════════════════════════════════════════

static func b64_f32(a: PackedFloat32Array) -> String:
	return Marshalls.raw_to_base64(a.to_byte_array())


static func un_f32(s: String) -> PackedFloat32Array:
	return Marshalls.base64_to_raw(s).to_float32_array()


static func b64_i32(a: PackedInt32Array) -> String:
	return Marshalls.raw_to_base64(a.to_byte_array())


static func un_i32(s: String) -> PackedInt32Array:
	return Marshalls.base64_to_raw(s).to_int32_array()


static func b64_f64(a: PackedFloat64Array) -> String:
	return Marshalls.raw_to_base64(a.to_byte_array())


static func un_f64(s: String) -> PackedFloat64Array:
	return Marshalls.base64_to_raw(s).to_float64_array()


## Scalar float, EXACT BY CONSTRUCTION. Godot's JSON number parsing is not
## correctly rounded, so a double printed at full precision can come back one
## ulp off -- which is precisely the divergence this whole file exists to
## prevent. Any float that is not a small whole number therefore rides as its
## raw IEEE-754 bit pattern (a decimal int64, as a string, because JSON
## numbers only carry 53 bits). Small whole numbers stay readable: their
## decimal forms parse exactly even through a sloppy parser. The whole-number
## fast path also covers inf/nan and a negative zero by falling through to
## the bits, so every float, without exception, round-trips bit for bit.
static func enc_float(v: float):
	if is_finite(v) and v == floor(v) and absf(v) <= 9007199254740992.0 \
			and (v != 0.0 or 1.0 / v > 0.0):
		return v
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, v)
	return {"__f": str(b.decode_s64(0))}


static func dec_float(v) -> float:
	if v is Dictionary:
		var b := PackedByteArray()
		b.resize(8)
		b.encode_s64(0, int(String(v["__f"])))
		return b.decode_double(0)
	return float(v)


static func enc_v2(v: Vector2) -> Dictionary:
	return {"__v2": [enc_float(v.x), enc_float(v.y)]}


static func dec_v2(v: Dictionary) -> Vector2:
	var a: Array = v["__v2"]
	return Vector2(dec_float(a[0]), dec_float(a[1]))


static func enc_v3(v: Vector3) -> Dictionary:
	return {"__v3": [enc_float(v.x), enc_float(v.y), enc_float(v.z)]}


static func dec_v3(v: Dictionary) -> Vector3:
	var a: Array = v["__v3"]
	return Vector3(dec_float(a[0]), dec_float(a[1]), dec_float(a[2]))


# ── int-keyed dictionaries. JSON keys are strings, so keys go through str()
# and come back through int(). Values are coerced by the named type. ─────────

static func enc_ii(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = int(d[k])
	return out


static func dec_ii(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[int(String(k))] = int(d[k])
	return out


static func enc_if(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = enc_float(float(d[k]))
	return out


static func dec_if(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[int(String(k))] = dec_float(d[k])
	return out


static func enc_ib(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[str(k)] = bool(d[k])
	return out


static func dec_ib(d: Dictionary) -> Dictionary:
	var out := {}
	for k in d:
		out[int(String(k))] = bool(d[k])
	return out


# ═══════════════════════════════════════════════════════════════════════════
# GENERIC PROPERTY CAPTURE
#
# Serializes every script variable an object carries, by the value's own type.
# This is what the coordination note asks for on the economy: a Purse field
# added by the parallel workflow is captured the moment it exists, with no
# field list here to go stale. Objects, Dictionaries and object-bearing Arrays
# are skipped BY POLICY -- references do not serialize -- and every owner's
# to_dict handles those few fields explicitly.
# ═══════════════════════════════════════════════════════════════════════════

static func enc_props(obj: Object, skip: Array = []) -> Dictionary:
	var out := {}
	for p in obj.get_property_list():
		if not (p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE):
			continue
		var n: String = p["name"]
		if n in skip:
			continue
		var v = obj.get(n)
		match typeof(v):
			TYPE_INT, TYPE_BOOL, TYPE_STRING:
				out[n] = v
			TYPE_FLOAT:
				out[n] = enc_float(v)
			TYPE_PACKED_FLOAT32_ARRAY:
				out[n] = {"__pf32": b64_f32(v)}
			TYPE_PACKED_INT32_ARRAY:
				out[n] = {"__pi32": b64_i32(v)}
			TYPE_PACKED_FLOAT64_ARRAY:
				out[n] = {"__pf64": b64_f64(v)}
			TYPE_PACKED_STRING_ARRAY:
				out[n] = {"__psa": Array(v)}
			TYPE_VECTOR2:
				out[n] = enc_v2(v)
			TYPE_VECTOR3:
				out[n] = enc_v3(v)
			TYPE_ARRAY:
				var enc = _enc_scalar_array(v)
				if enc != null:
					out[n] = enc
			_:
				pass   # objects, dictionaries: the owner's to_dict's job
	return out


## Apply a captured property dict back onto an object, coercing every value to
## the type the field currently holds -- which is what makes the JSON round
## trip (where every number is a double) safe against typed GDScript members.
static func dec_props(obj: Object, d: Dictionary) -> void:
	for n in d:
		if not (n in obj):
			continue
		var cur = obj.get(n)
		var v = d[n]
		match typeof(cur):
			TYPE_INT:
				obj.set(n, int(v))
			TYPE_FLOAT:
				obj.set(n, dec_float(v))
			TYPE_BOOL:
				obj.set(n, bool(v))
			TYPE_STRING:
				obj.set(n, String(v))
			TYPE_PACKED_FLOAT32_ARRAY:
				obj.set(n, un_f32(String(v["__pf32"])))
			TYPE_PACKED_INT32_ARRAY:
				obj.set(n, un_i32(String(v["__pi32"])))
			TYPE_PACKED_FLOAT64_ARRAY:
				obj.set(n, un_f64(String(v["__pf64"])))
			TYPE_PACKED_STRING_ARRAY:
				obj.set(n, PackedStringArray(v["__psa"]))
			TYPE_VECTOR2:
				obj.set(n, dec_v2(v))
			TYPE_VECTOR3:
				obj.set(n, dec_v3(v))
			TYPE_ARRAY:
				obj.set(n, _dec_scalar_array(v))
			_:
				pass


## Scalar-only arrays (a torpedo loadout snapshot, for instance). Anything
## holding an object is refused here and must be handled by the owner.
static func _enc_scalar_array(a: Array):
	var out := []
	for v in a:
		match typeof(v):
			TYPE_INT, TYPE_BOOL, TYPE_STRING:
				out.append(v)
			TYPE_FLOAT:
				out.append(enc_float(v))
			_:
				return null
	return {"__arr": out}


static func _dec_scalar_array(v) -> Array:
	var out := []
	if not (v is Dictionary) or not v.has("__arr"):
		return out
	for e in (v["__arr"] as Array):
		if e is Dictionary:
			out.append(dec_float(e))
		else:
			out.append(e)
	return out
