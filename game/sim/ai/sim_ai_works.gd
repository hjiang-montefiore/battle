class_name SimAiWorks
extends RefCounted
## WHERE A BUILDING GOES. Siting only -- what to build and whether it can be
## afforded are decisions the director makes; this answers "where".
##
## ═══ WHY THIS FILE EXISTS ═══════════════════════════════════════════════
##
## The AI had never placed a structure in a live match. Not once, in any
## measured game. _build_site() handed it a ring at 600 + 250 * ordinal metres
## around home, so for the seven buildings a start already owns it asked for a
## spot 2350 m out -- against a 340 m headquarters build radius. Every single
## placement came back "outside your build radius", which meant it could never
## build a research facility, which meant SimEconomy.begin_epoch_advance()
## refused for the whole match, which meant the AI was locked at its starting
## epoch in a game whose entire pitch is epoch progression.
##
## A ring around home was the wrong SHAPE of rule, not the wrong number. The
## design here is taken from the owner's other RTS, Operation Ironfront
## (js/ai.js), whose AI sites buildings well and whose numbers are tuned by
## measurement. Four things came across:
##
##   1. THE ANCHOR IS A BUILDING, NEVER THE HOME MARKER (findSpot, :1583).
##      Home is the mean of one's own structures -- a point with no build
##      radius of its own, which may not even be on land. A build radius
##      belongs to a building, so the search starts at a building.
##   2. THE INNERMOST LEGAL RING WINS. A spiral outward from the anchor,
##      taking the first legal spot it finds, so compactness is emergent
##      rather than scripted: the base packs because near spots are tried
##      first.
##   3. ONE RULE REACHES OUTWARD, AND ONLY ONE (spotToward, :6549). Walking
##      the line from the nearest own structure toward a target and taking the
##      furthest legal point is how a base GROWS toward something -- an ore
##      field, the front -- while never leaving its own radius.
##   4. A REFINERY GOES ON THE FIELD (spotNear, :6533, and Ironfront's "THE
##      MINE" note). Exact centre first, then rings outward. A refinery sited
##      by a spiral round the yard doubles every haul.
##
## And a fifth thing, which is about failure rather than success: Ironfront
## counts siting failures per item (rq.failN) and after four gives up on that
## spot for seventy seconds (failCool). That belongs in the director, because
## it is state; the constants for it live here beside the rest.
##
## ═══ WHAT IS AND IS NOT ASKED ═══════════════════════════════════════════
##
## Ironfront's siting calls G.canPlace(), which is the engine's own global
## legality test. Ours must not: SimEconomy.placement_problem() checks
## clearance against every structure on the map whoever owns it, so an AI that
## probed it across a grid would read the enemy's base straight off the
## refusals. It is the cleanest leak in the codebase and it is not taken.
##
## So `legal()` below tests only what a player with a build cursor can see:
##   * the terrain, which docs/09 §1 makes public
##   * the build-radius rings of ITS OWN finished structures
##   * clearance against ITS OWN footprints
## An enemy structure standing in the chosen spot will still get the placement
## refused by the engine. That is correct and it is why the director counts
## failures and moves on, exactly as a player does when the cursor goes red.
##
## Scale: Ironfront works in 32-pixel tiles with a global CFG.BUILD_RADIUS of
## 11 tiles. Our headquarters projects 340 m, so one of its tiles is worth
## about 31 m here; TILE_M below is that conversion, rounded, and every tile
## figure quoted from js/ai.js is converted through it.


## Ironfront's CFG.TILE, in our metres. 11 tiles of CFG.BUILD_RADIUS against
## our 340 m headquarters ring makes a tile worth ~31 m; 30 rounds it and
## keeps every derived constant a round number.
const TILE_M := 30.0

## findSpot's spiral: `for (let r = 2; r < 26; r++)`, converted.
const SPIRAL_MIN_M := 2.0 * TILE_M      ## 60 m
const SPIRAL_MAX_M := 26.0 * TILE_M     ## 780 m
const RING_STEP_M := TILE_M

## findSpot's `attempt < 14`: how many bearings are sampled on each ring.
const BEARINGS_PER_RING := 14

## THE BEARING WALK, and a deliberate departure. Ironfront draws each bearing
## from G.rng(). We do not: docs/06 forbids an unsequenced draw, and spending
## the director's stream on siting would couple where a building goes to how
## many contacts were ranked earlier in the same tick. The golden angle walks
## the same ring just as evenly, is identical on every run, and costs nothing.
const GOLDEN_ANGLE := 2.399963229728653

## spotToward's `s -= 1.5` and its lateral offsets `[0, 1.5, -1.5, 3, -3]`,
## in metres.
const TOWARD_STEP_M := 1.5 * TILE_M     ## 45 m
const TOWARD_MIN_M := 2.0 * TILE_M      ## 60 m
const TOWARD_LATERAL_M: Array[float] = [0.0, 45.0, -45.0, 90.0, -90.0]

## spotNear's `r <= R` with `6 + r * 2` bearings a ring. Ironfront passes R = 7
## for a refinery on an ore field.
const NEAR_RINGS := 7

## yardAnchor's neighbour window, `U.dist2(b.tx, b.ty, y.tx, y.ty) > 169`
## -- 13 tiles.
const CROWD_R_M := 13.0 * TILE_M        ## 390 m

## yardAnchor's "a yard nearer the trouble than home by more than six tiles
## is last choice", and the weights it penalises with.
const TROUBLE_MARGIN_M := 6.0 * TILE_M  ## 180 m
const TROUBLE_PENALTY_PROD := 9.0
const TROUBLE_PENALTY_OTHER := 3.0

## yardAnchor's neighbour weights: production 4, anything else 0.2.
const CROWD_W_PROD := 4.0
const CROWD_W_OTHER := 0.2

## placeReady()'s rq.failN ceiling and its failCool. Four tries at siting one
## thing, then leave that spot alone for seventy seconds -- because a spot
## that does not exist does not start existing when you ask again immediately.
const FAIL_LIMIT := 4
## Ironfront allows a derrick twelve, because an oil pad is a spot that may be
## being cleared rather than a spot that is not there.
const FAIL_LIMIT_FIELD := 12
const FAIL_COOL_S := 70.0

## CLAIM_TTL: "seconds a met reserve may sit unspent" (js/ai.js:1113). A claim
## on money that is never converted into a building is a starved army.
const CLAIM_TTL_S := 40.0

## Roles whose whole point is to stand somewhere other than the middle of the
## base -- they are sited with toward() rather than the spiral.
const FORWARD_ROLES := {
	"fixed_radar": true, "fixed_sam": true, "ew_station": true,
	"bunker": true, "coastal_battery": true,
}

## Roles sited ON a resource field rather than beside a building.
const FIELD_ROLES := {"refinery": true, "oil_derrick": true}


# ═══════════════════════════════════════════════════════════════════════════
# THE BASE PICTURE
#
# One flat snapshot of this AI's own base, taken once per siting decision so
# the spiral does not re-walk the forces view a few hundred times. Every row
# is a structure THIS PLAYER OWNS; there is no row here for anybody else's
# building, because there is no way to get one.
# ═══════════════════════════════════════════════════════════════════════════

class Yard extends RefCounted:
	var unit: int = -1
	var x: float = 0.0
	var z: float = 0.0
	var radius_m: float = 0.0     ## its own build ring, 0 if it projects none
	var footprint_m: float = 12.0
	var role: String = ""
	var production: bool = false
	var operational: bool = false


## Snapshot the AI's own structures. `production_roles` names the roles that
## count as industry for the anchor weighting -- the director passes what its
## own role classifier calls production, so the two agree.
static func base_picture(view: SimAiWorldView) -> Array:
	var out: Array = []
	if view == null or view.forces == null:
		return out
	for i in view.forces.indices():
		if not view.forces.is_structure(i):
			continue
		var d := view.own_def(i)
		if d == null:
			continue
		var y := Yard.new()
		y.unit = i
		var p := view.forces.position(i)
		y.x = p[0]
		y.z = p[2]
		y.radius_m = d.build_radius_m
		y.footprint_m = d.footprint_m
		y.role = d.role
		y.production = is_industry(d.role)
		y.operational = view.own_is_operational(i)
		out.append(y)
	return out


static func is_industry(role: String) -> bool:
	return role == "hq" or role == "light_factory" or role == "heavy_factory" \
		or role == "barracks" or role == "airbase" or role == "naval_yard" \
		or role == "helipad"


# ═══════════════════════════════════════════════════════════════════════════
# LEGALITY, as far as the AI is entitled to judge it
# ═══════════════════════════════════════════════════════════════════════════

## Can this structure stand here, as far as its own eyes can tell? Mirrors
## SimEconomy.placement_problem() clause for clause, MINUS the clause that
## walks other players' structures -- see the note at the top of the file.
static func legal(pic: Array, terrain: SimTerrain, d: SimUnitDef,
		x: float, z: float) -> bool:
	if d == null or not d.is_structure:
		return false
	if terrain != null:
		var hx := terrain.extent_x_m() * 0.5
		var hz := terrain.extent_z_m() * 0.5
		if x < -hx or x > hx or z < -hz or z > hz:
			return false
		var wants_water := d.role == "naval_yard"
		var wet := terrain.is_water(x, z)
		if wants_water != wet:
			return false
	# Clearance against our own footprints, and the build ring in one pass.
	var inside := false
	var any_ring := false
	for row in pic:
		var y := row as Yard
		var dx := x - y.x
		var dz := z - y.z
		var d2 := dx * dx + dz * dz
		var keep := d.footprint_m + y.footprint_m
		if d2 < keep * keep:
			return false
		if y.operational and y.radius_m > 0.0:
			any_ring = true
			if d2 <= y.radius_m * y.radius_m:
				inside = true
	# The first structure a player places is free-form -- SimEconomy says so
	# in the same words, and it is what makes an MCV opening possible.
	return inside or not any_ring


# ═══════════════════════════════════════════════════════════════════════════
# THE THREE SITING RULES
# ═══════════════════════════════════════════════════════════════════════════

## WHICH BUILDING THE NEXT ONE GOES BESIDE. Ironfront's yardAnchor (:6573).
##
## Production goes beside the anchor holding the LEAST production, so losing
## one factory is not losing the war; everything else beside the least crowded
## anchor, which is simply where there is still ground. An anchor closer to
## trouble than home is pushed down the list, because a new factory belongs
## behind the fighting rather than in front of it.
##
## `trouble_x/z` is the AI's own belief about where the fighting is -- its
## front, off its own track picture. Passing home for it is the no-belief case
## and makes the penalty inert, which is the right behaviour: with nothing
## known, every side of the base is as safe as every other.
static func anchor(pic: Array, production: bool, home_x: float, home_z: float,
		trouble_x: float, trouble_z: float) -> Yard:
	var rings: Array = []
	for row in pic:
		var y := row as Yard
		if y.operational and y.radius_m > 0.0:
			rings.append(y)
	if rings.size() <= 1:
		return rings[0] if rings.size() == 1 else null
	var home_to_trouble := sqrt(pow(trouble_x - home_x, 2.0)
		+ pow(trouble_z - home_z, 2.0))
	var has_trouble := home_to_trouble > 1.0
	var best: Yard = null
	var best_score := INF
	for row in rings:
		var y := row as Yard
		var score := 0.0
		for other_row in pic:
			var o := other_row as Yard
			if o.unit == y.unit:
				continue
			if pow(o.x - y.x, 2.0) + pow(o.z - y.z, 2.0) > CROWD_R_M * CROWD_R_M:
				continue
			if production:
				score += CROWD_W_PROD if o.production else CROWD_W_OTHER
			else:
				score += 1.0
		if has_trouble:
			var d := sqrt(pow(trouble_x - y.x, 2.0) + pow(trouble_z - y.z, 2.0))
			if d < home_to_trouble - TROUBLE_MARGIN_M:
				score += TROUBLE_PENALTY_PROD if production \
					else TROUBLE_PENALTY_OTHER
		# Ties break on the unit index, which is creation order -- the rows
		# arrive in ascending index order, so a strict < keeps the earliest.
		if score < best_score:
			best_score = score
			best = y
	return best


## THE SPIRAL. Ironfront's findSpot (:1583): rings outward from the anchor,
## fourteen bearings each, first legal spot wins. The innermost legal ring is
## what packs the base.
##
## Returns [x, z] or an empty array when there is nowhere legal at all -- and
## an empty answer is a real answer, which is why the caller counts it as a
## failure rather than building at home and hoping.
static func spiral(pic: Array, terrain: SimTerrain, d: SimUnitDef,
		at: Yard, fallback_x: float, fallback_z: float) -> PackedFloat32Array:
	var ax := at.x if at != null else fallback_x
	var az := at.z if at != null else fallback_z
	# The bearing walk is seeded off the anchor's own unit index, so two
	# buildings sited against the same anchor in the same tick do not both
	# start at due north and collide on the clearance test.
	var phase := float(at.unit if at != null else 0) * GOLDEN_ANGLE
	var ring := 0
	var r := SPIRAL_MIN_M
	while r <= SPIRAL_MAX_M:
		for k in range(BEARINGS_PER_RING):
			var a := phase + GOLDEN_ANGLE * float(ring * BEARINGS_PER_RING + k)
			var x := ax + cos(a) * r
			var z := az + sin(a) * r
			if legal(pic, terrain, d, x, z):
				return PackedFloat32Array([x, z])
		ring += 1
		r += RING_STEP_M
	return PackedFloat32Array()


## THE ONE RULE THAT REACHES OUTWARD. Ironfront's spotToward (:6549): walk the
## line from our nearest own structure toward a point and take the FURTHEST
## legal spot on it, so the new building drags the build radius that way.
##
## This is how a base grows toward an ore field or toward the front without
## ever stepping outside its own radius, and it is why there is no separate
## "expansion" rule: expansion is this, applied to a target worth reaching.
static func toward(pic: Array, terrain: SimTerrain, d: SimUnitDef,
		fx: float, fz: float) -> PackedFloat32Array:
	var src: Yard = null
	var sd := INF
	for row in pic:
		var y := row as Yard
		if not y.operational or y.radius_m <= 0.0:
			continue
		var d2 := pow(y.x - fx, 2.0) + pow(y.z - fz, 2.0)
		if d2 < sd or (d2 == sd and src != null and y.unit < src.unit):
			sd = d2
			src = y
	if src == null:
		return PackedFloat32Array()
	var l := maxf(sqrt(sd), 1.0)
	var ux := (fx - src.x) / l
	var uz := (fz - src.z) / l
	# Ironfront caps the walk at CFG.BUILD_RADIUS - 1; ours is per-building, so
	# the cap is this anchor's own ring less the footprint that has to fit
	# inside it.
	var reach := maxf(TOWARD_MIN_M, src.radius_m - d.footprint_m)
	var s := minf(l, reach)
	while s >= TOWARD_MIN_M:
		for off in TOWARD_LATERAL_M:
			var x := src.x + ux * s - uz * off
			var z := src.z + uz * s + ux * off
			if legal(pic, terrain, d, x, z):
				return PackedFloat32Array([x, z])
		s -= TOWARD_STEP_M
	return PackedFloat32Array()


## ON THE FIELD. Ironfront's spotNear (:6533): the exact point first, then
## rings of 6 + 2r bearings outward. A refinery on an ore field halves every
## haul, and Ironfront's measurement of the alternative -- "a random spiral
## round the yard" against ore 19-26 tiles out -- is why it is worth a rule of
## its own.
static func near(pic: Array, terrain: SimTerrain, d: SimUnitDef,
		fx: float, fz: float, rings := NEAR_RINGS) -> PackedFloat32Array:
	if legal(pic, terrain, d, fx, fz):
		return PackedFloat32Array([fx, fz])
	for r in range(1, rings + 1):
		var n := 6 + r * 2
		var radius := float(r) * TILE_M
		for k in range(n):
			var a := GOLDEN_ANGLE * float(r * 32 + k) + TAU * float(k) / float(n)
			var x := fx + cos(a) * radius
			var z := fz + sin(a) * radius
			if legal(pic, terrain, d, x, z):
				return PackedFloat32Array([x, z])
	return PackedFloat32Array()
