class_name SimMapFile
extends RefCounted
## Player-authorable maps: data/maps/<name>.json -> SimTerrain.
##
## Before this file the four theatres and three arenas existed only as
## procedural GDScript -- there was no way to author a map, place resource
## deposits or set start positions without editing sim code. This is the
## missing piece: a versioned, diffable map format and the loader that replays
## it into the same SimTerrain everything else already consumes.
##
## ── THE FORMAT IS OPERATIONS, NOT A HEIGHT DUMP ──────────────────────────────
## The height section is an ORDERED LIST OF SCULPTING OPS -- ridges, basins,
## plateaus, a noise seed, smoothing passes -- that replay through SimTerrain's
## own builders. Three reasons, each load-bearing:
##   * determinism: the ops are pure functions of their parameters (every op
##     that rolls dice carries its OWN seed), so one file produces a
##     byte-identical heightfield on every machine, which docs/06 demands of
##     everything the sim touches;
##   * size: a 12.8 km map is a few hundred bytes of intent instead of 128x128
##     floats of consequence -- first_light.json is ~1.5 KB;
##   * diffability: "moved the north pass 400 m east" is a one-line JSON diff
##     a human can review, where a raw dump diff is line noise.
## Hand-painted detail that no op expresses goes in a `raw_patch` op -- exact
## cell heights over a small rectangle -- so the escape hatch exists without
## making it the format.
##
## An editor's undo is ops.pop_back() + rebuild: the op list IS the edit
## history of the terrain.
##
## ── WHAT ELSE A MAP CARRIES ──────────────────────────────────────────────────
## water_level (one number the water-level tool edits; applied as a final
## uniform offset because SimTerrain defines water as height < 0), bases
## (per-player spawn + facing), deposits (oil-field positions for the economy's
## derricks), and optional decor. Validity uses the same suitability rules the
## arena uses: a base footprint is tested at SimArena.BASE_FOOTPRINT_M with the
## same nine-point dryness check, so a map the editor accepts is a map the
## match can actually start on.
##
## ── INTEGRATION (one line, documented, not yet wired) ────────────────────────
## SimArena.build() resolves arena keys; custom maps join the normal flow when
## it gains ONE line before its `match key:`:
##
##     if key.begins_with(SimMapFile.ARENA_PREFIX): return SimMapFile.arena_build(key, seed_value)
##
## arena_build() registers the loaded map against the terrain it returns, so
## SimMapFile.base_positions(terrain, count) can serve the AUTHORED spawns with
## the same signature as SimArena.base_positions() -- the companion one-liner
## for SimArena.base_positions() when authored spawns should win. Until those
## lines land, test_map_file.gd proves playability by constructing SimMatch
## over a loaded terrain directly.

const FORMAT := "battle-map"
const VERSION := 1
## An arena key of the form "map:first_light" names a custom map.
const ARENA_PREFIX := "map:"
## Repo-root data/maps/, next to data/factions/. res://../ is the same
## convention skirmish.gd uses to reach art/renders/.
const MAPS_DIR := "res://../data/maps/"

## Every op the replayer understands, with the keys each one REQUIRES.
## An unknown op, or a missing key, refuses the whole file at load -- a map
## that would silently build different ground is worse than no map.
const OP_KEYS := {
	"fill": ["h"],
	"ridge": ["x0", "z0", "x1", "z1", "peak_m", "half_width_m"],
	"basin": ["x0", "z0", "x1", "z1", "depth_m"],
	"set_depth": ["x0", "z0", "x1", "z1", "depth_m"],
	"seamount": ["x0", "z0", "x1", "z1", "crest_depth_m", "half_width_m"],
	"sea_coast": ["x0", "z0", "x1", "z1", "depth_m", "seed"],
	"plateau": ["x", "z", "radius_m", "h"],
	"raise": ["x", "z", "radius_m", "delta_m"],
	"noise": ["seed", "amplitude_m"],
	"smooth": ["passes"],
	"raw_patch": ["cx0", "cz0", "w", "h", "heights"],
}

## Bases must sit inside this fraction of the half-extent -- the same margin
## SimArena's ring search respects, so an authored spawn is never somewhere the
## procedural placer would refuse to walk.
const DEPLOY_EXTENT_FRAC := 0.48
## Two bases closer than this share an opening; the format refuses it.
const MIN_BASE_SEPARATION_M := 1000.0

var version: int = VERSION
var map_name := "unnamed"
var author := ""
var size_m := 12800.0
var cell_m := 100.0
## Metres of sea-level rise. Applied last, as a uniform offset, because
## SimTerrain defines water as height < 0 -- so ONE number is the whole tool.
var water_level := 0.0
var ops: Array = []        ## Array[Dictionary], replayed in order
var bases: Array = []      ## [{player, x, z, facing_deg?}], player-indexed
var deposits: Array = []   ## [{x, z}] oil fields for derricks to claim
var decor: Array = []      ## opaque to the sim; the editor may use it

## terrain instance id -> the SimMapFile that built it, so the authored bases
## can be recovered from nothing but the terrain (the shape of the eventual
## SimArena.base_positions hook).
static var _by_terrain: Dictionary = {}


# ═══════════════════════════════════════════════════════════════════════════
# LOAD / SAVE
# ═══════════════════════════════════════════════════════════════════════════

static func path_of(map_key: String) -> String:
	return ProjectSettings.globalize_path(MAPS_DIR + map_key + ".json")


## Parse and validate a map file. Null on any refusal -- wrong magic, a
## version this build does not speak, an op it does not know -- with the
## reason on the error log. A refused file must never half-load.
static func load_map(path: String) -> SimMapFile:
	if not FileAccess.file_exists(path):
		push_error("no map file at " + path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(text)
	if not data is Dictionary:
		push_error("not valid JSON: " + path)
		return null
	return from_dict(data as Dictionary, path)


static func from_dict(d: Dictionary, label := "<dict>") -> SimMapFile:
	if String(d.get("format", "")) != FORMAT:
		push_error("%s: not a %s file" % [label, FORMAT])
		return null
	var v := int(d.get("version", -1))
	if v != VERSION:
		push_error("%s: format version %d, this build speaks only %d"
			% [label, v, VERSION])
		return null
	var meta: Dictionary = d.get("meta", {})
	var m := SimMapFile.new()
	m.version = v
	m.map_name = String(meta.get("name", "unnamed"))
	m.author = String(meta.get("author", ""))
	m.size_m = float(meta.get("size_m", 0.0))
	m.cell_m = float(meta.get("cell_m", 0.0))
	if m.cell_m <= 0.0 or m.cells() < 16 or m.cells() > 1024:
		push_error("%s: implausible dimensions %.0f m at %.0f m cells"
			% [label, m.size_m, m.cell_m])
		return null
	m.water_level = float(d.get("water_level", 0.0))
	m.ops = (d.get("height", []) as Array).duplicate(true)
	for op in m.ops:
		var why := _op_problem(op)
		if why != "":
			push_error("%s: %s" % [label, why])
			return null
	m.bases = (d.get("bases", []) as Array).duplicate(true)
	m.deposits = (d.get("deposits", []) as Array).duplicate(true)
	m.decor = (d.get("decor", []) as Array).duplicate(true)
	return m


static func _op_problem(op: Variant) -> String:
	if not op is Dictionary:
		return "height entry is not an op dictionary"
	var name := String((op as Dictionary).get("op", ""))
	if not OP_KEYS.has(name):
		return "unknown op '%s'" % name
	for k in OP_KEYS[name]:
		if not (op as Dictionary).has(k):
			return "op '%s' is missing '%s'" % [name, k]
	if name == "raw_patch":
		var w := int(op["w"])
		var h := int(op["h"])
		var hs: Array = op["heights"]
		if w <= 0 or h <= 0 or hs.size() != w * h:
			return "raw_patch is %dx%d but carries %d heights" % [w, h, hs.size()]
	return ""


## Canonical key order, tab indent, trailing newline: the same map saved twice
## is the same bytes, which is what keeps it reviewable in git.
func to_dict() -> Dictionary:
	return {
		"format": FORMAT,
		"version": version,
		"meta": {
			"name": map_name,
			"size_m": size_m,
			"cell_m": cell_m,
			"author": author,
		},
		"water_level": water_level,
		"height": ops.duplicate(true),
		"bases": bases.duplicate(true),
		"deposits": deposits.duplicate(true),
		"decor": decor.duplicate(true),
	}


func save(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("cannot write " + path)
		return false
	f.store_string(JSON.stringify(to_dict(), "\t") + "\n")
	f.close()
	return true


func cells() -> int:
	return int(round(size_m / maxf(cell_m, 1.0)))


# ═══════════════════════════════════════════════════════════════════════════
# REPLAY -> SimTerrain
# ═══════════════════════════════════════════════════════════════════════════

## Replay the op list into a fresh heightfield. Deterministic: the same file
## produces a byte-identical PackedFloat32Array every time, on every machine
## (test_map_file.gd hashes it to prove that). Registers the terrain so
## base_positions() can find the authored spawns later.
func build_terrain() -> SimTerrain:
	var n := cells()
	var t := SimTerrain.new(n, n, cell_m, map_name)
	for op in ops:
		_apply(t, op as Dictionary)
	if water_level != 0.0:
		for i in range(t.heights.size()):
			t.heights[i] -= water_level
	_by_terrain[t.get_instance_id()] = self
	return t


func _apply(t: SimTerrain, op: Dictionary) -> void:
	match String(op["op"]):
		"fill":
			t.fill(float(op["h"]))
		"ridge":
			t.add_ridge(float(op["x0"]), float(op["z0"]),
				float(op["x1"]), float(op["z1"]),
				float(op["peak_m"]), float(op["half_width_m"]))
		"basin":
			t.carve_sea(float(op["x0"]), float(op["z0"]),
				float(op["x1"]), float(op["z1"]), float(op["depth_m"]))
		"set_depth":
			t.set_depth(float(op["x0"]), float(op["z0"]),
				float(op["x1"]), float(op["z1"]), float(op["depth_m"]))
		"seamount":
			t.add_seamount(float(op["x0"]), float(op["z0"]),
				float(op["x1"]), float(op["z1"]),
				float(op["crest_depth_m"]), float(op["half_width_m"]))
		"sea_coast":
			# The wobble draws from a stream seeded BY THE OP, so inserting or
			# deleting any other op cannot move this coastline.
			t.carve_sea_coast(float(op["x0"]), float(op["z0"]),
				float(op["x1"]), float(op["z1"]), float(op["depth_m"]),
				SimRng.new(int(op["seed"])),
				float(op.get("wobble_m", 12000.0)),
				int(op.get("wavelength_cells", 22)))
		"plateau":
			_plateau(t, float(op["x"]), float(op["z"]), float(op["radius_m"]),
				float(op["h"]), float(op.get("blend_m", cell_m * 3.0)))
		"raise":
			_raise(t, float(op["x"]), float(op["z"]),
				float(op["radius_m"]), float(op["delta_m"]))
		"noise":
			t.add_noise(SimRng.new(int(op["seed"])),
				float(op["amplitude_m"]), int(op.get("feature_cells", 8)))
		"smooth":
			_smooth(t, int(op["passes"]))
		"raw_patch":
			_raw_patch(t, op)


## The plateau brush: pull the ground toward one height inside a disc, with a
## cosine blend skirt so the edge is a slope rather than a cliff.
static func _plateau(t: SimTerrain, x: float, z: float, radius_m: float,
		h: float, blend_m: float) -> void:
	var hx := t.extent_x_m() * 0.5
	var hz := t.extent_z_m() * 0.5
	var reach := radius_m + maxf(blend_m, 0.0)
	for cz in range(t.cells_z):
		for cx in range(t.cells_x):
			var wx := (float(cx) + 0.5) * t.cell_size_m - hx
			var wz := (float(cz) + 0.5) * t.cell_size_m - hz
			var d := sqrt((wx - x) * (wx - x) + (wz - z) * (wz - z))
			if d > reach:
				continue
			var f := 1.0
			if d > radius_m and blend_m > 0.0:
				f = 0.5 * (1.0 + cos(PI * (d - radius_m) / blend_m))
			var i := cz * t.cells_x + cx
			t.heights[i] = lerpf(t.heights[i], h, f)


## The raise/lower brush: a cosine bump of delta_m (negative lowers).
static func _raise(t: SimTerrain, x: float, z: float, radius_m: float,
		delta_m: float) -> void:
	if radius_m <= 0.0:
		return
	var hx := t.extent_x_m() * 0.5
	var hz := t.extent_z_m() * 0.5
	for cz in range(t.cells_z):
		for cx in range(t.cells_x):
			var wx := (float(cx) + 0.5) * t.cell_size_m - hx
			var wz := (float(cz) + 0.5) * t.cell_size_m - hz
			var d := sqrt((wx - x) * (wx - x) + (wz - z) * (wz - z))
			if d > radius_m:
				continue
			var f := 0.5 * (1.0 + cos(PI * d / radius_m))
			t.heights[cz * t.cells_x + cx] += delta_m * f


## The smoothing brush, whole-map: a 3x3 box mean per pass, edges clamped.
## Reads a copy, writes the field, so the result is order-independent within a
## pass and therefore deterministic.
static func _smooth(t: SimTerrain, passes: int) -> void:
	for _p in range(maxi(passes, 0)):
		var src := t.heights.duplicate()
		for cz in range(t.cells_z):
			for cx in range(t.cells_x):
				var sum := 0.0
				for dz in range(-1, 2):
					var rz := clampi(cz + dz, 0, t.cells_z - 1)
					for dx in range(-1, 2):
						var rx := clampi(cx + dx, 0, t.cells_x - 1)
						sum += src[rz * t.cells_x + rx]
				t.heights[cz * t.cells_x + cx] = sum / 9.0


## Hand-painted detail: exact heights over a cell rectangle. The escape hatch
## for what no op expresses, kept small so the format stays intent.
static func _raw_patch(t: SimTerrain, op: Dictionary) -> void:
	var cx0 := int(op["cx0"])
	var cz0 := int(op["cz0"])
	var w := int(op["w"])
	var h := int(op["h"])
	var hs: Array = op["heights"]
	for rz in range(h):
		for rx in range(w):
			t.set_height_at_cell(cx0 + rx, cz0 + rz, float(hs[rz * w + rx]))


# ═══════════════════════════════════════════════════════════════════════════
# BASES AND DEPOSITS
# ═══════════════════════════════════════════════════════════════════════════

func base_position(player_id: int) -> Vector2:
	for b in bases:
		if int((b as Dictionary).get("player", -1)) == player_id:
			return Vector2(float(b["x"]), float(b["z"]))
	if player_id >= 0 and player_id < bases.size():
		var b: Dictionary = bases[player_id]
		return Vector2(float(b["x"]), float(b["z"]))
	return Vector2.ZERO


## Authored facing, or SimMatch's own convention -- face the middle of the
## map -- when the file does not say.
func base_facing(player_id: int) -> float:
	for b in bases:
		if int((b as Dictionary).get("player", -1)) == player_id \
				and (b as Dictionary).has("facing_deg"):
			return deg_to_rad(float(b["facing_deg"]))
	var p := base_position(player_id)
	return atan2(-p.x, -p.y)


## Why a base cannot go here, or "" if it can -- the editor's marker validity
## check, and the same suitability rule the arena's own placer enforces: the
## WHOLE base footprint (SimArena.BASE_FOOTPRINT_M, nine points) must be dry
## and inside the deployable margin.
static func base_problem(t: SimTerrain, x: float, z: float) -> String:
	if absf(x) > t.extent_x_m() * DEPLOY_EXTENT_FRAC \
			or absf(z) > t.extent_z_m() * DEPLOY_EXTENT_FRAC:
		return "outside the deployable area"
	var m := SimArena.BASE_FOOTPRINT_M
	for off in [Vector2(0, 0), Vector2(m, 0), Vector2(-m, 0), Vector2(0, m),
			Vector2(0, -m), Vector2(m, m), Vector2(-m, -m), Vector2(m, -m),
			Vector2(-m, m)]:
		if t.is_water(x + off.x, z + off.y):
			return "a ground base cannot stand in water"
	return ""


## Why an oil deposit cannot go here. Derricks are ground structures, and the
## economy's placement rule ("cannot build on water") would strand a wet
## deposit forever, so the format refuses it up front.
static func deposit_problem(t: SimTerrain, x: float, z: float) -> String:
	if absf(x) > t.extent_x_m() * 0.5 or absf(z) > t.extent_z_m() * 0.5:
		return "off the map"
	if t.is_water(x, z):
		return "an oil derrick cannot stand in water"
	return ""


## Everything wrong with this map on this terrain, empty when it is sound.
## Strings, not booleans, for the same reason placement_problem() returns
## them: the editor has to say WHY the marker is red.
func validate(t: SimTerrain) -> PackedStringArray:
	var out := PackedStringArray()
	if bases.is_empty():
		out.append("no bases: nobody can spawn")
	for k in range(bases.size()):
		var b: Dictionary = bases[k]
		var p := Vector2(float(b.get("x", 0.0)), float(b.get("z", 0.0)))
		var why := base_problem(t, p.x, p.y)
		if why != "":
			out.append("base %d at %.0f, %.0f: %s" % [k, p.x, p.y, why])
		for j in range(k + 1, bases.size()):
			var q := Vector2(float(bases[j]["x"]), float(bases[j]["z"]))
			if p.distance_to(q) < MIN_BASE_SEPARATION_M:
				out.append("bases %d and %d are %.0f m apart (min %.0f)"
					% [k, j, p.distance_to(q), MIN_BASE_SEPARATION_M])
	for k in range(deposits.size()):
		var d: Dictionary = deposits[k]
		var why := deposit_problem(t,
			float(d.get("x", 0.0)), float(d.get("z", 0.0)))
		if why != "":
			out.append("deposit %d: %s" % [k, why])
	return out


# ═══════════════════════════════════════════════════════════════════════════
# THE ARENA-SHAPED SEAM
# ═══════════════════════════════════════════════════════════════════════════

## Same signature as SimArena.build(): resolve "map:<name>" to a terrain.
## The seed is unused -- a map file carries every seed it needs, which is what
## makes the SAME map identical across matches with different match seeds --
## but the parameter stays so the hook is a drop-in.
static func arena_build(key: String, _seed_value := 0) -> SimTerrain:
	var mf := load_map(path_of(key.trim_prefix(ARENA_PREFIX)))
	if mf == null:
		# A match must start on SOMETHING; the error is already logged.
		return SimArena.build(SimArena.SKIRMISH_VALLEY)
	return mf.build_terrain()


## Same signature as SimArena.base_positions(), serving the AUTHORED spawns
## when the terrain came from a map file with enough of them, and delegating
## to the arena's ring otherwise.
static func base_positions(terrain: SimTerrain, count: int) -> Array:
	var mf := map_of(terrain)
	if mf == null or mf.bases.size() < count:
		return SimArena.base_positions(terrain, count)
	var out: Array = []
	for i in range(count):
		out.append(mf.base_position(i))
	return out


## The map file a terrain was built from, or null for procedural terrain.
static func map_of(terrain: SimTerrain) -> SimMapFile:
	return _by_terrain.get(terrain.get_instance_id())


## SHA-256 of the raw heightfield bytes: the determinism receipt the tests
## compare and an editor can show next to "saved".
static func heights_hash(t: SimTerrain) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(t.heights.to_byte_array())
	return ctx.finish().hex_encode()
