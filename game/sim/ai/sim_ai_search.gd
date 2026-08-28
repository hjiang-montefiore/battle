class_name SimAiSearch
extends RefCounted
## WHERE THIS AI HAS ALREADY LOOKED. A coverage map over the public terrain.
##
## This class exists because of a measurement. Both directors in a peer match
## on a 6.4 km map sat in PROBE for twelve simulated minutes and evaluated 976
## sensor pairs with ZERO detections: the armies never found each other. The
## old search was a sixteen-point lattice, shuffled once from the seed, walked
## by ONE scout, and every manoeuvre group was sent to the same point (0, 0) --
## so the AI re-searched ground it had already stood on and left three quarters
## of the map untouched.
##
## A search that does not remember is not a search, it is a wander. What a
## reconnaissance plan actually is:
##
##   * a division of the ground into areas,
##   * a record of which have been covered and WHEN,
##   * an assignment that gives two groups two different areas,
##   * and a preference for ground somebody has a reason to walk on.
##
## ── WHY THIS IS NOT A LEAK ────────────────────────────────────────────────
##
## Every input is on the docs/09 §1 whitelist:
##
##   THE MAP EXTENTS AND THE WATER  are terrain, and "maps are public -- real
##   militaries have them".
##
##   THE SWEPT TIMES are written by mark_seen(), which is called with the
##   positions of the AI'S OWN UNITS. "I have driven through there" is the
##   purest possible own-information: it is a fact about my army, not about
##   yours.
##
##   THE RESOURCE POINTS are ore and oil fields, which are static features of
##   the ground in the same sense a ridge is. A commander who sweeps the ore
##   because that is where an economy has to be is INFERRING, from a public
##   map, and can be wrong -- there may be nobody there. That is the difference
##   between reconnaissance and clairvoyance, and it is the whole point.
##
## What is deliberately NOT here: any mirror of this AI's own start position.
## On a symmetric map "the enemy is where I would be if I were them" finds the
## enemy base in one move without a single sensor return, and it is precisely
## the knowledge docs/09 §1.1 says makes every other pillar decorative. The
## sweep expands outward from wherever the searcher stands and finds the enemy
## because the ground runs out, not because it guessed.

## Target grid resolution. A cell is roughly the ground one vehicle covers on
## one leg of a sweep; too fine and a group spends the match crossing a car
## park, too coarse and "swept" stops meaning anything.
const TARGET_CELLS := 12
const MIN_CELL_M := 500.0

## How long a cell stays "covered" before it is worth looking at again. An army
## can cross 6 km of map in about this long, so anything older than this is
## ground the enemy could have walked into since.
const RESWEEP_S := 210.0

## What a swept cell is worth avoiding, expressed in METRES of detour: a cell
## swept this instant costs this much extra to choose, decaying to zero as it
## goes stale. Distance and freshness are therefore in the same unit and the
## trade-off is legible.
const FRESH_PENALTY_M := 3200.0

## How much nearer a resource field makes a cell look. Ore and oil are where an
## economy has to be, so they are worth walking past on the way -- but only
## worth a fraction of a cell, never enough to make the AI orbit one.
const RESOURCE_BONUS_M := 900.0

## Seeded per-cell tie-break, in metres. Two AIs on the same map with the same
## coverage would otherwise sweep in lockstep, and a search route that owes
## nothing to the seed makes the determinism test in test_ai.gd vacuous.
const JITTER_M := 260.0

var cols: int = 1
var rows: int = 1
var cell_m: float = MIN_CELL_M
var origin_x: float = 0.0   ## world x of the LOW edge of column 0
var origin_z: float = 0.0

## Per cell, parallel arrays. -1.0e9 in `swept` means never looked at.
var swept := PackedFloat32Array()
var usable := PackedInt32Array()      ## 1 when a ground unit could stand there
var resource := PackedInt32Array()    ## 1 when an ore or oil field sits in it
var jitter := PackedFloat32Array()

## Cells taken by a group THIS tick, so two groups never sweep one square.
var _claimed: Dictionary = {}

var built: bool = false


## Lay the grid over the map. `water` is called per candidate cell centre; pass
## a callable that answers from the public terrain, or an empty Callable for a
## map with no water model.
func build(extent_x_m: float, extent_z_m: float, seeded: SimRng,
		water: Callable = Callable()) -> void:
	var ex: float = maxf(extent_x_m, MIN_CELL_M)
	var ez: float = maxf(extent_z_m, MIN_CELL_M)
	cell_m = maxf(MIN_CELL_M, maxf(ex, ez) / float(TARGET_CELLS))
	cols = maxi(1, int(ceil(ex / cell_m)))
	rows = maxi(1, int(ceil(ez / cell_m)))
	# World coordinates are centred on the origin, so the grid is too.
	origin_x = -ex * 0.5
	origin_z = -ez * 0.5
	var n := cols * rows
	swept = PackedFloat32Array(); swept.resize(n); swept.fill(-1.0e9)
	usable = PackedInt32Array(); usable.resize(n); usable.fill(1)
	resource = PackedInt32Array(); resource.resize(n); resource.fill(0)
	jitter = PackedFloat32Array(); jitter.resize(n)
	for k in range(n):
		# One draw per cell, in index order, so the route is a pure function of
		# the seed. docs/06 forbids randf() anywhere in the sim.
		jitter[k] = float(seeded.next_int(0, 1000)) / 1000.0 * JITTER_M
		if water.is_valid():
			var c := centre_of(k)
			if bool(water.call(c[0], c[1])):
				usable[k] = 0
	built = true


## Mark the cells holding a static map feature worth sweeping. Positions only;
## nothing here asks who owns anything, because nobody does -- these are holes
## in the ground.
func mark_resources(points: Array) -> void:
	for p in points:
		var v: Vector2 = p
		var k := cell_at(v.x, v.y)
		if k >= 0:
			resource[k] = 1


func size() -> int:
	return cols * rows


func cell_at(x: float, z: float) -> int:
	var cx := int(floor((x - origin_x) / cell_m))
	var cz := int(floor((z - origin_z) / cell_m))
	if cx < 0 or cx >= cols or cz < 0 or cz >= rows:
		return -1
	return cz * cols + cx


func centre_of(k: int) -> PackedFloat32Array:
	if k < 0 or k >= size():
		return PackedFloat32Array([0.0, 0.0])
	var cx := k % cols
	var cz := k / cols
	return PackedFloat32Array([
		origin_x + (float(cx) + 0.5) * cell_m,
		origin_z + (float(cz) + 0.5) * cell_m])


## "One of my units has been here." Called with own positions only. `radius` is
## how much ground that unit is credited with having covered -- deliberately
## modest, because a vehicle that drove past a hill has not searched behind it.
func mark_seen(x: float, z: float, radius: float, now: float) -> void:
	if not built:
		return
	var span := maxi(0, int(ceil(radius / cell_m)))
	var cx := int(floor((x - origin_x) / cell_m))
	var cz := int(floor((z - origin_z) / cell_m))
	for dz in range(-span, span + 1):
		for dx in range(-span, span + 1):
			var ax := cx + dx
			var az := cz + dz
			if ax < 0 or ax >= cols or az < 0 or az >= rows:
				continue
			var k := az * cols + ax
			var c := centre_of(k)
			if sqrt(pow(c[0] - x, 2.0) + pow(c[1] - z, 2.0)) > radius + cell_m * 0.5:
				continue
			if now > swept[k]:
				swept[k] = now


func clear_claims() -> void:
	_claimed.clear()


func claim(k: int) -> void:
	if k >= 0:
		_claimed[k] = true


func is_claimed(k: int) -> bool:
	return _claimed.has(k)


## The next piece of ground worth looking at, from where the searcher stands.
##
## Cost is in METRES: how far to walk, plus a penalty for ground already
## covered that decays to nothing as the cover goes stale, minus a discount for
## ground with a reason to be occupied. Nearest-unswept-first, which is a
## coverage algorithm rather than a guess about the enemy -- it expands outward
## from the searcher and stops only when the map is done.
##
## Ties break on cell index, so the same coverage always yields the same
## answer; docs/06 forbids letting iteration order pick an outcome and which
## way an army drives is very much an outcome.
func next_cell(from_x: float, from_z: float, now: float,
		skip_claimed := true) -> int:
	if not built:
		return -1
	# GROUND NOBODY HAS LOOKED AT WINS OUTRIGHT, whatever it costs to get to.
	# Ranking never-swept ground against swept ground on one cost scale lets a
	# cheap re-sweep next door beat an expensive unknown across the map, and a
	# search that can prefer ground it has already covered is a search that
	# never finishes -- measured, it stalled at 78% of the map. Only once the
	# first full sweep is done does the cost function below decide anything.
	var best := -1
	var best_cost := INF
	var virgin := false
	for k in range(size()):
		if usable[k] == 0:
			continue
		if skip_claimed and _claimed.has(k):
			continue
		var unlooked: bool = swept[k] <= -1.0e8
		if virgin and not unlooked:
			continue
		var c := centre_of(k)
		var cost := sqrt(pow(c[0] - from_x, 2.0) + pow(c[1] - from_z, 2.0))
		if not unlooked:
			var age: float = now - swept[k]
			if age < RESWEEP_S:
				cost += FRESH_PENALTY_M * (1.0 - clampf(age / RESWEEP_S, 0.0, 1.0))
		if resource[k] == 1:
			cost -= RESOURCE_BONUS_M
		cost += jitter[k]
		if unlooked and not virgin:
			# The first piece of ground nobody has looked at displaces
			# everything considered so far, whatever it cost.
			virgin = true
			best_cost = cost
			best = k
			continue
		if cost < best_cost:
			best_cost = cost
			best = k
	return best


## Fraction of the usable map looked at at least once. The number a test can
## assert on, and the number that says whether "it is searching" is true.
func coverage() -> float:
	if not built:
		return 0.0
	var seen := 0
	var total := 0
	for k in range(size()):
		if usable[k] == 0:
			continue
		total += 1
		if swept[k] > -1.0e8:
			seen += 1
	return 0.0 if total == 0 else float(seen) / float(total)


func never_swept() -> int:
	if not built:
		return 0
	var n := 0
	for k in range(size()):
		if usable[k] == 1 and swept[k] <= -1.0e8:
			n += 1
	return n


# ── SAVE / LOAD. The coverage map IS state: an AI restored without it would
# re-search ground it had already cleared, which is the bug this class exists
# to fix.

func to_dict() -> Dictionary:
	return {
		"cols": cols, "rows": rows,
		"cell_m": SimSave.enc_float(cell_m),
		"origin": [SimSave.enc_float(origin_x), SimSave.enc_float(origin_z)],
		"swept": SimSave.b64_f32(swept),
		"usable": SimSave.b64_i32(usable),
		"resource": SimSave.b64_i32(resource),
		"jitter": SimSave.b64_f32(jitter),
		"built": built,
	}


func from_dict(d: Dictionary) -> void:
	cols = int(d["cols"])
	rows = int(d["rows"])
	cell_m = SimSave.dec_float(d["cell_m"])
	var o: Array = d["origin"]
	origin_x = SimSave.dec_float(o[0])
	origin_z = SimSave.dec_float(o[1])
	swept = SimSave.un_f32(String(d["swept"]))
	usable = SimSave.un_i32(String(d["usable"]))
	resource = SimSave.un_i32(String(d["resource"]))
	jitter = SimSave.un_f32(String(d["jitter"]))
	built = bool(d["built"])
	_claimed.clear()


func describe() -> String:
	return "search %dx%d @ %.0f m -- %.0f%% covered, %d cell(s) never looked at" % [
		cols, rows, cell_m, coverage() * 100.0, never_swept()]
