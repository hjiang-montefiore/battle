class_name SimEntities
extends RefCounted
## Units are indices into parallel arrays, not objects. docs/06, "Data layout".
##
## The sensor solve sweeps positions, RCS and mount heights for every candidate
## pair. Kept contiguous that sweep is cache-friendly; chased through node
## pointers it is not, and the frame budget disappears at a few hundred units.

# ── hot fields, swept every solve ────────────────────────────────────────────
var pos_x := PackedFloat32Array()
var pos_y := PackedFloat32Array()   ## metres above the surface -- drives horizon
var pos_z := PackedFloat32Array()
var vel_x := PackedFloat32Array()
var vel_y := PackedFloat32Array()
var vel_z := PackedFloat32Array()
var rcs_m2 := PackedFloat32Array()
var ir_band := PackedFloat32Array()
var acoustic_db := PackedFloat32Array()
var visual_m2 := PackedFloat32Array()
var magnetic := PackedFloat32Array()
var mount_height_m := PackedFloat32Array()

# ── cold-ish fields ──────────────────────────────────────────────────────────
var faction := PackedInt32Array()
var category := PackedInt32Array()
var emcon := PackedInt32Array()
var alive := PackedInt32Array()          ## 1/0; index reuse is not attempted
var throttle := PackedFloat32Array()     ## 0..1, scales IR hard
var depth_m := PackedFloat32Array()      ## >0 = below surface (submarines)
var below_layer := PackedInt32Array()    ## 1 when beneath the thermocline
var jammer_power := PackedFloat32Array() ## 0 = not jamming
## A loud, short-lived acoustic event -- a torpedo leaving the tube, a hatch,
## a transient. docs/10 §7: "Firing is loud. Shooting reveals you." Modelled as
## a signature bump so the ordinary passive-sonar path hears it, rather than as
## a special case bolted onto the solver.
var acoustic_transient_db := PackedFloat32Array()
var acoustic_transient_s := PackedFloat32Array()
var names := PackedStringArray()

## index -> Array[SimSensorDef]
var sensors: Dictionary = {}

var _count: int = 0


func count() -> int:
	return _count


func add(unit_name: String, p_faction: int, x: float, y: float, z: float,
		sig: SimSignature, unit_sensors: Array = [],
		p_category := SimTypes.Category.GROUND,
		p_mount_height := -1.0) -> int:
	var i := _count
	pos_x.append(x); pos_y.append(y); pos_z.append(z)
	vel_x.append(0.0); vel_y.append(0.0); vel_z.append(0.0)
	rcs_m2.append(sig.rcs_m2)
	ir_band.append(sig.ir_band)
	acoustic_db.append(sig.acoustic_db)
	visual_m2.append(sig.visual_m2)
	magnetic.append(sig.magnetic)
	# A unit's own mount height defaults to the tallest sensor it carries.
	var mh := p_mount_height
	if mh < 0.0:
		mh = 0.0
		for s in unit_sensors:
			mh = maxf(mh, (s as SimSensorDef).mount_height_m)
	mount_height_m.append(mh)
	faction.append(p_faction)
	category.append(p_category)
	emcon.append(SimTypes.Emcon.RADIATE)
	alive.append(1)
	throttle.append(0.5)
	depth_m.append(0.0)
	below_layer.append(0)
	jammer_power.append(0.0)
	acoustic_transient_db.append(0.0)
	acoustic_transient_s.append(0.0)
	names.append(unit_name)
	sensors[i] = unit_sensors
	_count += 1
	return i


func set_velocity(i: int, vx: float, vy: float, vz: float) -> void:
	vel_x[i] = vx; vel_y[i] = vy; vel_z[i] = vz


func set_position(i: int, x: float, y: float, z: float) -> void:
	pos_x[i] = x; pos_y[i] = y; pos_z[i] = z


func kill(i: int) -> void:
	alive[i] = 0


func is_alive(i: int) -> bool:
	return i >= 0 and i < _count and alive[i] == 1


## Ground range in kilometres. The sim works in metres; sensor ranges are quoted
## in kilometres because that is how the source material quotes them.
func range_km(a: int, b: int) -> float:
	var dx := pos_x[b] - pos_x[a]
	var dy := pos_y[b] - pos_y[a]
	var dz := pos_z[b] - pos_z[a]
	return sqrt(dx * dx + dy * dy + dz * dz) / 1000.0


func bearing_rad(a: int, b: int) -> float:
	return atan2(pos_x[b] - pos_x[a], pos_z[b] - pos_z[a])


## Aspect-corrected RCS. Front/side/rear differ, often by 10x on aircraft
## (docs/02 §1). Cheap approximation: nose-on and tail-on are smaller.
func effective_rcs(target: int, observer: int) -> float:
	var base := rcs_m2[target]
	var vx := vel_x[target]
	var vz := vel_z[target]
	var speed := sqrt(vx * vx + vz * vz)
	if speed < 0.5:
		return base
	# angle between the target's heading and the line to the observer
	var tx := pos_x[observer] - pos_x[target]
	var tz := pos_z[observer] - pos_z[target]
	var tl := sqrt(tx * tx + tz * tz)
	if tl < 1e-6:
		return base
	var cos_aspect: float = clampf((vx * tx + vz * tz) / (speed * tl), -1.0, 1.0)
	# |cos| near 1 means nose-on or tail-on: smallest return. Beam-on is largest.
	var beam := 1.0 - absf(cos_aspect)
	return base * (0.35 + 1.30 * beam)


## IR scales hard with engine power; afterburner is a flare.
func effective_ir(target: int) -> float:
	var t: float = clampf(throttle[target], 0.0, 1.2)
	return ir_band[target] * (0.15 + 2.4 * t * t)


## Radiated noise rises steeply with shaft RPM. A ship at flank speed is deaf;
## a submarine at flank speed is loud (docs/02 §8.4).
func effective_acoustic_db(target: int) -> float:
	var v := sqrt(vel_x[target] * vel_x[target] + vel_z[target] * vel_z[target])
	var knots := v * 1.94384
	var db := acoustic_db[target] + 12.0 * log(maxf(knots, 1.0)) / log(10.0)
	if acoustic_transient_s[target] > 0.0:
		db = maxf(db, acoustic_transient_db[target])
	return db


## Raise a transient. The loudest wins; they do not stack.
func add_acoustic_transient(i: int, db: float, seconds: float) -> void:
	if db >= acoustic_transient_db[i] or acoustic_transient_s[i] <= 0.0:
		acoustic_transient_db[i] = db
	acoustic_transient_s[i] = maxf(acoustic_transient_s[i], seconds)


func decay_transients(dt: float) -> void:
	for i in range(_count):
		if acoustic_transient_s[i] > 0.0:
			acoustic_transient_s[i] -= dt
			if acoustic_transient_s[i] <= 0.0:
				acoustic_transient_db[i] = 0.0


## Is this unit radiating anything an ESM receiver could hear?
func is_emitting(i: int) -> bool:
	if emcon[i] == SimTypes.Emcon.SILENT:
		return false
	if jammer_power[i] > 0.0:
		return true
	for s in sensors.get(i, []):
		var sd := s as SimSensorDef
		if sd.emits and not sd.is_passive():
			return true
	return false


## Total radiated power an ESM receiver sees, used for the one-way law.
func emitted_power(i: int) -> float:
	if emcon[i] == SimTypes.Emcon.SILENT:
		return 0.0
	var p := 0.0
	for s in sensors.get(i, []):
		var sd := s as SimSensorDef
		if sd.emits and not sd.is_passive():
			# Reference range is a decent proxy for transmitted power.
			p += sd.reference_range_km / 100.0
	p += jammer_power[i]
	if emcon[i] == SimTypes.Emcon.RECEIVE:
		p *= 0.25   # intermittent: brief, hard-to-classify hits
	return p
