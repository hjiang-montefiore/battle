class_name SimTerrain
extends RefCounted
## The ground, and what it hides. docs/02 §1, §4.
##
## docs/02 lists terrain masking as a signature modifier with an absolute
## effect: "Line of sight blocked -> no RF/IR/visual detection AT ALL." Not a
## range penalty, not a probability -- nothing. It is also what makes the
## airborne sensor argument work over land as well as over water: "an airborne
## sensor sees into valleys that a hilltop radar cannot."
##
## Kept engine-agnostic per docs/06: a flat height array, no Godot terrain node,
## no collision shapes, no raycasts through the physics server.
##
## Heights are metres above sea level. Negative is water, and its magnitude is
## the depth -- which is what the acoustic layer in docs/02 §8.3 needs.

var cells_x: int = 256
var cells_z: int = 256
## Metres per cell. A theatre is hundreds of kilometres across, so cells are
## coarse; masking at this scale is about ridgelines, not about rocks.
var cell_size_m: float = 800.0
var heights := PackedFloat32Array()

var name: String = "flat"
## Geographic anchor, set when a real heightfield is loaded. Lets a test or a
## scenario ask for a place by name rather than by cell index.
var centre_lat: float = 0.0
var centre_lon: float = 0.0
var georeferenced: bool = false
## Sampling step for the line-of-sight march, in metres.
var los_step_m: float = 400.0


func _init(w := 256, h := 256, cell := 800.0, terrain_name := "flat") -> void:
	cells_x = w
	cells_z = h
	cell_size_m = cell
	name = terrain_name
	heights.resize(w * h)
	heights.fill(0.0)


func extent_x_m() -> float:
	return float(cells_x) * cell_size_m


func extent_z_m() -> float:
	return float(cells_z) * cell_size_m


## World coordinates run from -extent/2 to +extent/2, so the origin is the
## middle of the theatre.
func _to_cell(x: float, z: float) -> Vector2i:
	var cx := int(floor((x + extent_x_m() * 0.5) / cell_size_m))
	var cz := int(floor((z + extent_z_m() * 0.5) / cell_size_m))
	return Vector2i(clampi(cx, 0, cells_x - 1), clampi(cz, 0, cells_z - 1))


func height_at_cell(cx: int, cz: int) -> float:
	var i := clampi(cz, 0, cells_z - 1) * cells_x + clampi(cx, 0, cells_x - 1)
	return heights[i]


func set_height_at_cell(cx: int, cz: int, v: float) -> void:
	if cx < 0 or cz < 0 or cx >= cells_x or cz >= cells_z:
		return
	heights[cz * cells_x + cx] = v


## Bilinear sample, so a ridge is a slope rather than a staircase.
func height_at(x: float, z: float) -> float:
	var fx := (x + extent_x_m() * 0.5) / cell_size_m - 0.5
	var fz := (z + extent_z_m() * 0.5) / cell_size_m - 0.5
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var tx := fx - float(x0)
	var tz := fz - float(z0)
	var h00 := height_at_cell(x0, z0)
	var h10 := height_at_cell(x0 + 1, z0)
	var h01 := height_at_cell(x0, z0 + 1)
	var h11 := height_at_cell(x0 + 1, z0 + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func is_water(x: float, z: float) -> bool:
	return height_at(x, z) < 0.0


## Positive metres of water. Zero on land.
func depth_at(x: float, z: float) -> float:
	return maxf(-height_at(x, z), 0.0)


## Does the ground block the straight line between two points?
##
## Heights are absolute, so a unit's own y is its altitude above sea level, not
## above the ground under it. Returns true when something can be seen.
##
## Earth curvature is NOT applied here: the radar horizon in SimPropagation
## already handles it, and doubling it up would hide things twice.
func has_line_of_sight(ax: float, ay: float, az: float,
		bx: float, by: float, bz: float, clearance_m := 2.0) -> bool:
	var dx := bx - ax
	var dz := bz - az
	var ground_range := sqrt(dx * dx + dz * dz)
	if ground_range < 1.0:
		return true
	var steps := int(ceil(ground_range / maxf(los_step_m, 1.0)))
	steps = clampi(steps, 1, 4096)
	for i in range(1, steps):
		var t := float(i) / float(steps)
		var px := ax + dx * t
		var pz := az + dz * t
		var ray_y := ay + (by - ay) * t
		if height_at(px, pz) > ray_y + clearance_m:
			return false
	return true


## Height of the ground under a unit, which is what "mount height" is measured
## from. docs/12: a fixed radar station gets "free range on high ground".
func ground_under(x: float, z: float) -> float:
	return maxf(height_at(x, z), 0.0)


# ── construction helpers, used by the theatre generator ─────────────────────

## A smooth ridge running between two points, with a given peak height and
## half-width. Ridgelines are what actually mask things.
func add_ridge(x0: float, z0: float, x1: float, z1: float,
		peak_m: float, half_width_m: float) -> void:
	var dx := x1 - x0
	var dz := z1 - z0
	var length := sqrt(dx * dx + dz * dz)
	if length < 1.0:
		return
	for cz in range(cells_z):
		for cx in range(cells_x):
			var wx := (float(cx) + 0.5) * cell_size_m - extent_x_m() * 0.5
			var wz := (float(cz) + 0.5) * cell_size_m - extent_z_m() * 0.5
			# distance from the segment
			var t: float = clampf(((wx - x0) * dx + (wz - z0) * dz) / (length * length), 0.0, 1.0)
			var px := x0 + dx * t
			var pz := z0 + dz * t
			var d := sqrt((wx - px) * (wx - px) + (wz - pz) * (wz - pz))
			if d > half_width_m:
				continue
			# cosine falloff: a rounded crest rather than a wall
			var f := 0.5 * (1.0 + cos(PI * d / half_width_m))
			# taper toward the ends so ridges do not stop dead
			var ends: float = clampf(minf(t, 1.0 - t) * 6.0, 0.25, 1.0)
			var v := peak_m * f * ends
			var i := cz * cells_x + cx
			if v > heights[i]:
				heights[i] = v


## Set a rectangular region to an exact depth. Use this for a shelf, where the
## seabed must come UP relative to the surrounding basin -- carve_sea() only
## ever deepens, so it silently does nothing in that case.
func set_depth(x0: float, z0: float, x1: float, z1: float, depth_m: float) -> void:
	for cz in range(cells_z):
		for cx in range(cells_x):
			var wx := (float(cx) + 0.5) * cell_size_m - extent_x_m() * 0.5
			var wz := (float(cz) + 0.5) * cell_size_m - extent_z_m() * 0.5
			if wx < minf(x0, x1) or wx > maxf(x0, x1):
				continue
			if wz < minf(z0, z1) or wz > maxf(z0, z1):
				continue
			heights[cz * cells_x + cx] = -depth_m


## A ridge on the SEABED. It raises the bottom toward `crest_depth_m` below the
## surface but never breaches it -- add_ridge() writes absolute heights, so
## using it underwater turns a seamount into an island.
func add_seamount(x0: float, z0: float, x1: float, z1: float,
		crest_depth_m: float, half_width_m: float) -> void:
	var dx := x1 - x0
	var dz := z1 - z0
	var length := sqrt(dx * dx + dz * dz)
	if length < 1.0:
		return
	for cz in range(cells_z):
		for cx in range(cells_x):
			var i := cz * cells_x + cx
			if heights[i] >= 0.0:
				continue                      # not underwater here
			var wx := (float(cx) + 0.5) * cell_size_m - extent_x_m() * 0.5
			var wz := (float(cz) + 0.5) * cell_size_m - extent_z_m() * 0.5
			var t: float = clampf(((wx - x0) * dx + (wz - z0) * dz) / (length * length), 0.0, 1.0)
			var px := x0 + dx * t
			var pz := z0 + dz * t
			var d := sqrt((wx - px) * (wx - px) + (wz - pz) * (wz - pz))
			if d > half_width_m:
				continue
			var f := 0.5 * (1.0 + cos(PI * d / half_width_m))
			var target := lerpf(heights[i], -absf(crest_depth_m), f)
			heights[i] = minf(target, -20.0)  # always stays submerged


## A rectangular basin. Only ever DEEPENS -- use set_depth() to raise a shelf.
func carve_sea(x0: float, z0: float, x1: float, z1: float, depth_m: float) -> void:
	for cz in range(cells_z):
		for cx in range(cells_x):
			var wx := (float(cx) + 0.5) * cell_size_m - extent_x_m() * 0.5
			var wz := (float(cz) + 0.5) * cell_size_m - extent_z_m() * 0.5
			if wx < minf(x0, x1) or wx > maxf(x0, x1):
				continue
			if wz < minf(z0, z1) or wz > maxf(z0, z1):
				continue
			var i := cz * cells_x + cx
			heights[i] = minf(heights[i], -depth_m)


func fill(v: float) -> void:
	heights.fill(v)


## Deterministic value noise, so a theatre is the same every time it is built.
## docs/06 forbids randf() anywhere in the sim.
func add_noise(rng: SimRng, amplitude_m: float, feature_cells := 8) -> void:
	var gw := cells_x / maxi(feature_cells, 1) + 2
	var gh := cells_z / maxi(feature_cells, 1) + 2
	var lattice := PackedFloat32Array()
	lattice.resize(gw * gh)
	for i in range(gw * gh):
		lattice[i] = float(rng.next_float()) * amplitude_m
	for cz in range(cells_z):
		for cx in range(cells_x):
			var fx := float(cx) / float(feature_cells)
			var fz := float(cz) / float(feature_cells)
			var x0 := int(fx)
			var z0 := int(fz)
			var tx := fx - float(x0)
			var tz := fz - float(z0)
			var a := lattice[clampi(z0, 0, gh - 1) * gw + clampi(x0, 0, gw - 1)]
			var b := lattice[clampi(z0, 0, gh - 1) * gw + clampi(x0 + 1, 0, gw - 1)]
			var c := lattice[clampi(z0 + 1, 0, gh - 1) * gw + clampi(x0, 0, gw - 1)]
			var d := lattice[clampi(z0 + 1, 0, gh - 1) * gw + clampi(x0 + 1, 0, gw - 1)]
			# smoothstep the interpolant so cells do not show
			var sx := tx * tx * (3.0 - 2.0 * tx)
			var sz := tz * tz * (3.0 - 2.0 * tz)
			var v := lerpf(lerpf(a, b, sx), lerpf(c, d, sx), sz)
			var i := cz * cells_x + cx
			# noise only roughens land; it does not fill in the sea
			if heights[i] >= 0.0:
				heights[i] += v


## Smooth 1-D noise, used to wobble a coastline.
func _wobble(rng: SimRng, n: int, amplitude_m: float, wavelength_cells: int) -> PackedFloat32Array:
	var gw := n / maxi(wavelength_cells, 1) + 2
	var lat := PackedFloat32Array()
	lat.resize(gw)
	for i in range(gw):
		lat[i] = (float(rng.next_float()) * 2.0 - 1.0) * amplitude_m
	var out := PackedFloat32Array()
	out.resize(n)
	for i in range(n):
		var f := float(i) / float(wavelength_cells)
		var i0 := int(f)
		var t := f - float(i0)
		var st := t * t * (3.0 - 2.0 * t)
		out[i] = lerpf(lat[clampi(i0, 0, gw - 1)], lat[clampi(i0 + 1, 0, gw - 1)], st)
	return out


## Carve a sea whose EAST and WEST edges wander. Perturbing heights near the
## shoreline instead just speckles islands across the water -- 130 m of noise
## on a 60 m strait turns it into an archipelago. Displacing the boundary gives
## bays and headlands and leaves the water a sea.
func carve_sea_coast(x0: float, z0: float, x1: float, z1: float, depth_m: float,
		rng: SimRng, wobble_m := 12000.0, wavelength_cells := 22) -> void:
	var west := _wobble(rng, cells_z, wobble_m, wavelength_cells)
	var east := _wobble(rng, cells_z, wobble_m, wavelength_cells)
	var lo_x := minf(x0, x1)
	var hi_x := maxf(x0, x1)
	for cz in range(cells_z):
		var wz := (float(cz) + 0.5) * cell_size_m - extent_z_m() * 0.5
		if wz < minf(z0, z1) or wz > maxf(z0, z1):
			continue
		var l := lo_x + west[cz]
		var r := hi_x + east[cz]
		for cx in range(cells_x):
			var wx := (float(cx) + 0.5) * cell_size_m - extent_x_m() * 0.5
			if wx < l or wx > r:
				continue
			var i := cz * cells_x + cx
			heights[i] = minf(heights[i], -depth_m)


## Load a heightfield written by tools/fetch_theatre_dem.py.
##
## Real GEBCO elevation and bathymetry: the same array masks radar and gives
## the acoustic layer its depth, which is why one dataset carrying both matters
## more here than a finer land-only one would.
##
## Format: "BTHF", u16 version, u32 cells_x, u32 cells_z, f32 cell_size_m,
## u16 name length, name, then cells_x*cells_z int16 metres, row-major from the
## NORTH edge so +z is north.
static func load_heightfield(path: String) -> SimTerrain:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	if f.get_buffer(4).get_string_from_ascii() != "BTHF":
		push_error("not a heightfield: " + path)
		return null
	var version := f.get_16()
	var w := int(f.get_32())
	var h := int(f.get_32())
	var cell := f.get_float()
	var lat := 0.0
	var lon := 0.0
	if version >= 2:
		lat = f.get_float()
		lon = f.get_float()
	var nl := f.get_16()
	var terrain_name := f.get_buffer(nl).get_string_from_utf8()
	if w <= 0 or h <= 0 or w > 8192 or h > 8192:
		push_error("implausible heightfield dimensions in " + path)
		return null
	var t := SimTerrain.new(w, h, cell, terrain_name)
	t.centre_lat = lat
	t.centre_lon = lon
	t.georeferenced = version >= 2
	# The file stores rows NORTH first, but cell row 0 sits at the most negative
	# z. Reading straight through would make +z point south, and every
	# latitude lookup would land in the sea on the wrong side of the map.
	for r in range(h):
		var dest := (h - 1 - r) * w
		for c in range(w):
			# get_16() is unsigned; these are signed metres.
			var v := f.get_16()
			if v >= 32768:
				v -= 65536
			t.heights[dest + c] = float(v)
	f.close()
	return t


## World position of a latitude/longitude, in metres from the theatre centre.
## +z is north, +x is east, which is how the fetcher lays the rows out.
func world_of(lat: float, lon: float) -> Vector2:
	if not georeferenced:
		return Vector2.ZERO
	var dz := (lat - centre_lat) * 110574.0
	var dx := (lon - centre_lon) * 111320.0 * cos(deg_to_rad(centre_lat))
	return Vector2(dx, dz)


## Elevation at a real place. Metres, negative is water.
func height_at_latlon(lat: float, lon: float) -> float:
	var w := world_of(lat, lon)
	return height_at(w.x, w.y)


func describe() -> String:
	var lo := 1e9
	var hi := -1e9
	var water := 0
	for h in heights:
		lo = minf(lo, h)
		hi = maxf(hi, h)
		if h < 0.0:
			water += 1
	return "%s  %d x %d cells @ %.0f m  (%.0f x %.0f km)  elevation %.0f..%.0f m  %.0f%% water" % [
		name, cells_x, cells_z, cell_size_m,
		extent_x_m() / 1000.0, extent_z_m() / 1000.0, lo, hi,
		float(water) / float(heights.size()) * 100.0]
