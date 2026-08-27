class_name SimArena
extends RefCounted
## Compact maps for a skirmish, and where the bases go on them.
##
## SimTheatre builds docs/08's four theatres at real geography: 346 to 768 km
## across. Those are the right size for the fight they model -- an AEW orbit and
## a 400 km horizon mean nothing on a small map -- and completely the wrong size
## for a twenty-minute skirmish, where a tank at 60 km/h would spend an hour
## crossing the board.
##
## So a skirmish gets its own scale. These maps are 12 to 20 km across, which
## puts base-to-base at roughly eight minutes of driving, keeps a tank gun's
## 3-4 km reach meaningful against the size of the board, and still leaves room
## for terrain to matter. Everything else about them is a real SimTerrain
## heightfield, so line of sight, gradients, water and the path planner all
## behave exactly as they do in a theatre.
##
## Deterministic: same key, same seed, same terrain, every time (docs/06).

const SKIRMISH_VALLEY := "skirmish_valley"
const OPEN_STEPPE := "open_steppe"
const COASTAL_SHELF := "coastal_shelf"

const ALL := [SKIRMISH_VALLEY, OPEN_STEPPE, COASTAL_SHELF]

const DESCRIPTIONS := {
	SKIRMISH_VALLEY: "12.8 km. A ridge down the middle: the picture is broken "
		+ "by terrain, and whoever takes the high ground sees first.",
	OPEN_STEPPE: "16 km of almost nothing. Nowhere to hide from a radar, so "
		+ "the fight is about emissions and reach rather than cover.",
	COASTAL_SHELF: "16 km with one connected sea round the west and south "
		+ "edges. Land war with a naval flank, and a shoreline in reach of "
		+ "every base.",
}


static func build(key: String, seed_value := 20260826) -> SimTerrain:
	# A theatre key is a legal arena key. SimMatch.start() takes an arena KEY,
	# not a terrain, and resolves it here -- so this delegation is what lets a
	# match start on docs/08's real-geography theatres without the match layer
	# knowing theatres exist. Same determinism contract either way.
	if key in SimTheatre.ALL:
		return SimTheatre.build(key, seed_value)
	# An AUTHORED map is a legal arena key too, by the same reasoning: the match
	# layer asks for a key and gets terrain, and does not need to know whether a
	# person sculpted it or a generator did. The map file carries every seed it
	# needs, which is why seed_value is not threaded into it.
	if key.begins_with(SimMapFile.ARENA_PREFIX):
		return SimMapFile.arena_build(key, seed_value)
	var rng := SimRng.new(seed_value)
	match key:
		OPEN_STEPPE: return _open_steppe(rng)
		COASTAL_SHELF: return _coastal_shelf(rng)
	return _skirmish_valley(rng)


static func description(key: String) -> String:
	return DESCRIPTIONS.get(key, "")


## A ridge down the middle of a shallow bowl. The ridge is deliberately
## CROSSABLE -- about a 1-in-3 grade against SimMovement's 0.6 limit -- so it
## slows an advance and blocks line of sight without turning the map into two
## rooms joined by a corridor. That distinction matters: an impassable ridge
## makes pathfinding the game, a slow one makes the DECISION the game.
static func _skirmish_valley(rng: SimRng) -> SimTerrain:
	var t := SimTerrain.new(128, 128, 100.0, "Skirmish Valley")   # 12.8 km
	t.fill(60.0)
	# THE RIDGE IS 6.8 km LONG ON A 12.8 km MAP, AND THAT RATIO IS THE DESIGN.
	#
	# docs/02 makes blocked line of sight ABSOLUTE -- not a range penalty, a
	# refusal. Any ridge taller than the sensor masts either side of it hides
	# everything behind it completely, so the length of the ridge is what
	# decides how much of the map is dark, and it is a far more sensitive dial
	# than its height.
	#
	# It was first built spanning almost the whole map. That sealed the two
	# bases off from each other entirely: neither side could detect anything
	# for the first seven minutes, both armies sat at home with nothing to
	# react to, and the opening was dead. Ending it well short of the map edge
	# leaves two open flanks, so a force that manoeuvres is seen and a force
	# that sits behind the hill is not. That is the trade the map is for.
	t.add_ridge(0.0, -3400.0, 0.0, 3400.0, 250.0, 1100.0)
	# Isolated high ground near each flank route -- the obvious, contested spot
	# to put a radar, because mount height is measured from the ground under it.
	t.add_ridge(-2600.0, 4600.0, -1500.0, 5000.0, 260.0, 700.0)
	t.add_ridge(2600.0, -4600.0, 1500.0, -5000.0, 260.0, 700.0)
	t.add_noise(rng, 22.0, 9)
	return t


## Almost flat. docs/08 calls the North German Plain "the theatre where the
## NATO split shows" precisely because low relief means nowhere to hide from a
## ground radar; this is that property at skirmish scale.
static func _open_steppe(rng: SimRng) -> SimTerrain:
	var t := SimTerrain.new(160, 160, 100.0, "Open Steppe")       # 16 km
	t.fill(120.0)
	t.add_ridge(-1500.0, 1000.0, 2000.0, -600.0, 90.0, 2600.0)
	t.add_noise(rng, 16.0, 14)
	return t


## Land with a flank on the water. The sea is carved rather than filled, so it
## shelves properly and a naval yard has legal ground to stand on at the
## shoreline. It has two CONNECTED arms: the wobbled bay down the negative-X
## edge, and a straight southern shore that joins it around the corner.
##
## The southern arm exists because the scenario sweep found the +X base of a
## two-player match ~8 km from the nearest water -- a naval yard on that side
## was geometrically impossible, and north_atlantic (both sides naval/air only)
## sat at zero shots for 90 simulated minutes. With the arm, every base slot
## for 2-4 players is 0.6-2.4 km from a shoreline, and the two shores are one
## body of water so fleets from either side can actually meet.
##
## Two implementation constraints that are easy to lose:
##  * The arm is carved AFTER the ridge. add_ridge() raises any cell under its
##    footprint, sea included, and the ridge's southern tail (endpoint
##    z=-6000, half-width 1400 m) would otherwise dam the arm with a land
##    bridge to the map edge.
##  * The arm uses carve_sea(), which draws nothing from the rng -- so the rng
##    stream feeding add_noise() is unchanged and the map OUTSIDE the arm is
##    bit-identical to the pre-arm terrain the sweep recorded.
##  * The arm's north shore stops at z=-6400: the 4-player base slot at
##    (0, -5760) needs its ~170 m base footprint on dry land, and 640 m of
##    clearance keeps it dry through the bilinear shoreline blend.
static func _coastal_shelf(rng: SimRng) -> SimTerrain:
	var t := SimTerrain.new(160, 160, 100.0, "Coastal Shelf")     # 16 km
	t.fill(70.0)
	t.carve_sea_coast(-8000.0, -8000.0, -4200.0, 8000.0, 90.0, rng, 900.0, 12)
	t.add_ridge(3000.0, -6000.0, 4200.0, 6000.0, 260.0, 1400.0)
	t.carve_sea(-8000.0, -8000.0, 8000.0, -6400.0, 90.0)
	t.add_noise(rng, 20.0, 11)
	return t


## Where each participant's base goes. Evenly spaced on a circle inset from the
## edge, starting at the "south-west" and going clockwise, so a two-player match
## is always corner-to-corner across the longest diagonal on the map.
##
## Deterministic and index-ordered: player 0 always gets the first slot.
## WHERE THE CRUDE IS. Two fields inside each player's own reach, and a
## contested ring between them that nobody starts near.
##
## The split is the whole design. Fields at home mean a player is never
## starved by bad luck; fields in the middle mean the fastest economy belongs
## to whoever is willing to hold ground they do not start on. All of it is
## derived from the base ring, so it is symmetric for any player count -- an
## economy that favoured seat 0 would be a fairness bug, not a map.
static func oil_fields(terrain: SimTerrain, bases: Array) -> Array:
	var out: Array = []
	var hx := terrain.extent_x_m() * 0.5
	var hz := terrain.extent_z_m() * 0.5
	for b in bases:
		var home: Vector2 = b
		var away := -home.normalized() if home.length() > 1.0 else Vector2(1, 0)
		var side := Vector2(-away.y, away.x)
		for s in [-1.0, 1.0]:
			var pt: Vector2 = home + away * 520.0 + side * (s * 620.0)
			if _dry(terrain, pt, hx, hz):
				out.append(pt)
	# The contested ring: as many fields as there are players, on the same
	# circle, rotated half a step so they sit BETWEEN the bases rather than in
	# front of them.
	var n: int = maxi(bases.size(), 2)
	var radius: float = minf(hx, hz) * 0.30
	for k in range(n):
		var a: float = TAU * (float(k) + 0.5) / float(n)
		var pt := Vector2(cos(a), sin(a)) * radius
		if _dry(terrain, pt, hx, hz):
			out.append(pt)
	return out


static func _dry(terrain: SimTerrain, p: Vector2, hx: float, hz: float) -> bool:
	return (absf(p.x) < hx - 200.0 and absf(p.y) < hz - 200.0
		and not terrain.is_water(p.x, p.y))


static func base_positions(terrain: SimTerrain, count: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	# An authored map places its OWN starts. Without this the map loads and
	# plays, but on the generator's ring slots -- so the passes and knolls the
	# author put between the bases would sit somewhere else entirely.
	if SimMapFile.map_of(terrain) != null:
		return SimMapFile.base_positions(terrain, count)
	var radius: float = minf(terrain.extent_x_m(), terrain.extent_z_m()) * 0.36
	# A two-player match sits on the diagonal rather than on an axis: on the
	# valley map that puts the ridge squarely between the two bases, which is
	# the whole point of the map.
	var start := PI * 0.75 if count == 2 else PI * 0.5
	for i in range(count):
		var a: float = start + TAU * float(i) / float(count)
		var x := cos(a) * radius
		var z := sin(a) * radius
		out.append(_pull_to_shore(terrain, _nearest_dry(terrain, x, z)))
	return out


## How far _pull_to_shore() will drag a slot toward the nearest shoreline, its
## walking step, and the cell-size proxy that scopes the pull to SKIRMISH maps.
## Theatre DEMs are 900+ m per cell, and dragging a theatre base slot toward a
## coast that may be a hundred kilometres away is a different design decision
## -- their recorded probe results stay valid because they are exempt here.
const SHORE_PULL_RANGE_M := 3000.0
const SHORE_PULL_STEP_M := 50.0
const SKIRMISH_CELL_MAX_M := 200.0


## On a coastal skirmish map, walk a base slot toward the nearest water and
## stop with the base footprint one step short of the shoreline.
##
## WHY: the build-radius rule (SimEconomy.placement_problem) makes a structure
## legal only inside the build radius of one the player already owns, and the
## largest radius in the roster is the HQ's 340 m. A naval yard must stand ON
## water, so naval play is only possible when water lies inside the base's own
## build radius -- a bay two kilometres away might as well not exist. The
## scenario sweep found exactly that: north_atlantic on coastal_shelf sat at
## zero shots partly because neither base had water anywhere near its build
## radius. The walk keeps the footprint dry, so the pulled slot is as close to
## the water as a base can legally be (~230-280 m, inside the HQ's 340).
##
## Deterministic: fixed ring search, fixed step, no rng. A slot with no water
## within SHORE_PULL_RANGE_M (or any slot on a dry map) is returned unchanged.
static func _pull_to_shore(terrain: SimTerrain, p: Vector2) -> Vector2:
	if terrain.cell_size_m > SKIRMISH_CELL_MAX_M:
		return p
	var w := _nearest_water(terrain, p, SHORE_PULL_RANGE_M)
	if not is_finite(w.x):
		return p
	var dist := p.distance_to(w)
	if dist <= SHORE_PULL_STEP_M:
		return p
	var dir := (w - p) / dist
	var best := p
	var s := SHORE_PULL_STEP_M
	while s <= dist:
		var q := p + dir * s
		if absf(q.x) > terrain.extent_x_m() * 0.48:
			break
		if absf(q.y) > terrain.extent_z_m() * 0.48:
			break
		if not _footprint_dry(terrain, q.x, q.y):
			break
		best = q
		s += SHORE_PULL_STEP_M
	return best


## The nearest wet point by a deterministic outward ring search, or
## (INF, INF) when there is none within max_r. Fixed 100 m rings and a fixed
## 16-point compass, same shape as _nearest_dry()'s search.
static func _nearest_water(terrain: SimTerrain, p: Vector2,
		max_r: float) -> Vector2:
	var step := 100.0
	var r := step
	while r <= max_r:
		for k in range(16):
			var a: float = TAU * float(k) / 16.0
			var x := p.x + cos(a) * r
			var z := p.y + sin(a) * r
			if terrain.is_water(x, z):
				return Vector2(x, z)
		r += step
	return Vector2(INF, INF)


## BASE_LAYOUT spans about +/-170 m around the base position; the extra 10 m
## covers the bilinear shoreline blend between terrain cells.
const BASE_FOOTPRINT_M := 180.0


## Dry at the position AND at the corners/edges of the base footprint. A dry
## CENTRE is not enough: on coastal_shelf the 4-player slot at (-5760, 0) used
## to be nudged to the first dry centre, right on the waterline, which left a
## third of the base structures standing in the bay.
static func _footprint_dry(terrain: SimTerrain, x: float, z: float) -> bool:
	var m := BASE_FOOTPRINT_M
	for off in [Vector2(0, 0), Vector2(m, 0), Vector2(-m, 0), Vector2(0, m),
			Vector2(0, -m), Vector2(m, m), Vector2(-m, -m), Vector2(m, -m),
			Vector2(-m, m)]:
		if terrain.is_water(x + off.x, z + off.y):
			return false
	return true


## Nudge a base position off water by a deterministic outward ring search. A
## base that spawns in the bay would put every structure in an illegal place
## and the player would start the match unable to build anything.
static func _nearest_dry(terrain: SimTerrain, x: float, z: float) -> Vector2:
	if _footprint_dry(terrain, x, z):
		return Vector2(x, z)
	var step := terrain.cell_size_m * 2.0
	# Ring count scales with the map: a fixed 40 rings was 120 km on the North
	# Atlantic theatre, and a base slot in the middle of a 768 km ocean box
	# stayed at -1000 m because no land was that close. Reaching 45% of the
	# shorter extent means the search can always get from the slot circle
	# (36% inset) to the map edge before giving up.
	var max_ring := maxi(40, int(minf(terrain.extent_x_m(),
		terrain.extent_z_m()) * 0.45 / step))
	for ring in range(1, max_ring):
		var r := step * float(ring)
		# Fixed 16-point compass, in a fixed order.
		for k in range(16):
			var a: float = TAU * float(k) / 16.0
			var px := x + cos(a) * r
			var pz := z + sin(a) * r
			if absf(px) > terrain.extent_x_m() * 0.48:
				continue
			if absf(pz) > terrain.extent_z_m() * 0.48:
				continue
			if _footprint_dry(terrain, px, pz):
				return Vector2(px, pz)
	return Vector2(x, z)
