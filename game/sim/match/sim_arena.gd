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
	COASTAL_SHELF: "16 km with a bay along one edge. Land war with a naval "
		+ "flank and somewhere a naval yard can actually stand.",
}


static func build(key: String, seed_value := 20260826) -> SimTerrain:
	# A theatre key is a legal arena key. SimMatch.start() takes an arena KEY,
	# not a terrain, and resolves it here -- so this delegation is what lets a
	# match start on docs/08's real-geography theatres without the match layer
	# knowing theatres exist. Same determinism contract either way.
	if key in SimTheatre.ALL:
		return SimTheatre.build(key, seed_value)
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


## Land with a flank on the water. The bay is on the negative-X edge and is
## carved rather than filled, so it shelves properly and a naval yard has legal
## ground to stand on at the shoreline.
static func _coastal_shelf(rng: SimRng) -> SimTerrain:
	var t := SimTerrain.new(160, 160, 100.0, "Coastal Shelf")     # 16 km
	t.fill(70.0)
	t.carve_sea_coast(-8000.0, -8000.0, -4200.0, 8000.0, 90.0, rng, 900.0, 12)
	t.add_ridge(3000.0, -6000.0, 4200.0, 6000.0, 260.0, 1400.0)
	t.add_noise(rng, 20.0, 11)
	return t


## Where each participant's base goes. Evenly spaced on a circle inset from the
## edge, starting at the "south-west" and going clockwise, so a two-player match
## is always corner-to-corner across the longest diagonal on the map.
##
## Deterministic and index-ordered: player 0 always gets the first slot.
static func base_positions(terrain: SimTerrain, count: int) -> Array:
	var out: Array = []
	if count <= 0:
		return out
	var radius: float = minf(terrain.extent_x_m(), terrain.extent_z_m()) * 0.36
	# A two-player match sits on the diagonal rather than on an axis: on the
	# valley map that puts the ridge squarely between the two bases, which is
	# the whole point of the map.
	var start := PI * 0.75 if count == 2 else PI * 0.5
	for i in range(count):
		var a: float = start + TAU * float(i) / float(count)
		var x := cos(a) * radius
		var z := sin(a) * radius
		out.append(_nearest_dry(terrain, x, z))
	return out


## Nudge a base position off water by a deterministic outward ring search. A
## base that spawns in the bay would put every structure in an illegal place
## and the player would start the match unable to build anything.
static func _nearest_dry(terrain: SimTerrain, x: float, z: float) -> Vector2:
	if not terrain.is_water(x, z):
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
			if not terrain.is_water(px, pz):
				return Vector2(px, pz)
	return Vector2(x, z)
