extends Node3D
## Everything on the ground that the simulation does not know about: the sea
## surface, and the trees, scrub and boulders that make a heightfield read as
## a place rather than as a painted plane.
##
## THREE RULES GOVERN THIS FILE.
##
## 1. It is DECORATION. Nothing here is asked about by the sim, nothing here
##    is written by it, and no sim value is read except the terrain heights,
##    the base slots and the resource fields -- all read-only, all so that
##    scenery can stay OUT of the places a player has to read.
##
## 2. It is DETERMINISTIC BY CONSTRUCTION. Every placement comes from integer
##    hashing of the cell index, salted with the terrain's name. No randf(),
##    no SimRng, no engine RNG at all -- so two players on one map see the
##    same forest, a replay paints the same forest, and none of the sim's
##    random streams are advanced by a tree.
##
## 3. It is CHEAP. One MultiMesh per (tile, layer), never a node per object.
##    The tiles exist so the frustum can throw most of the map away: a single
##    map-wide MultiMesh has one AABB and is therefore drawn in full even when
##    the camera is looking at a quarter of it.

# ── Layout ──────────────────────────────────────────────────────────────────
## Side of a scatter tile, metres. One MultiMesh per tile per layer, so this
## is the granularity at which the frustum can discard scenery. 800 m at the
## opening zoom (411 m of ground on screen) means the camera holds four to six
## tiles instead of the whole 6.4 km map.
const TILE_M := 800.0

# ── Exclusions, in metres ───────────────────────────────────────────────────
## Nothing grows inside a base's BUILD AREA -- measured, not guessed. At spawn
## that area is the union of the build radii of the eight structures in
## SimMatch.BASE_LAYOUT, and the HQ's 340 m swallows all the others (the
## furthest outlying structure is a derrick at 203 m with a 90 m radius, so
## 293 m). 370 m is that 340 plus half of the widest footprint in the roster,
## which is the extra ground a building placed on the radius actually covers.
##
## It is not larger than that on purpose. Every extra metre here is a metre of
## bare ground in the view the game OPENS on, and the opening view is the one
## a player judges the map by.
##
## AND IT WAS STILL TOO LARGE. 370 m clears the whole BUILD RADIUS -- everywhere
## a player could ever put a building -- but the game opens on 411 m of ground
## centred on the base, so the exclusion swallowed the entire opening view and
## not one of eleven thousand trees was visible in it. A map judged by that
## frame is a bare green plane.
##
## 230 m clears what the base actually OCCUPIES (the furthest starting structure
## is 202 m out) rather than everywhere it might expand to. Trees stand at the
## edge of the opening view, and a building placed further out later simply
## goes up among them -- which is what the genre does, and what a player
## expects, rather than a suspiciously clean lawn the size of the screen.
const CLEAR_BASE_M := 230.0
## Ore shards spread to 74 m and a refinery has to be able to sit beside the
## field. Oil is a 46 m ring plus a derrick.
const CLEAR_ORE_M := 165.0
const CLEAR_OIL_M := 140.0

# ── Where things grow ───────────────────────────────────────────────────────
## Trees stop where the ground gets steep. Real treelines are set by soil, and
## soil does not stay on a slope; more usefully for an RTS, the steep ground
## is the ground that decides line of sight, so it is the ground that must
## stay bare enough to read.
const TREE_GRADE_LO := 0.10
const TREE_GRADE_HI := 0.24
## ...and where it gets high. Normalised over the map's own height range, so
## this works on a 100 m valley and a 2 km theatre without retuning.
const TREE_ALT_LO := 0.42
const TREE_ALT_HI := 0.68
## Trees never stand nearer the waterline than this, so the shore stays a
## clean line a player can judge a naval yard against.
const TREE_SHORE_M := 3.0
## At most this many trees in one 50 m cell. Four is one tree per 625 m^2 --
## an average spacing of 25 m, which is wide enough to drive an M1 between and
## see it the whole way.
## Thinned as the woods widened, so covering roughly twice the ground costs
## about the same to draw. Scenery already adds ~49% to the primitive count and
## an RTS spends its frame on units, not on scenery.
const TREES_PER_CELL := 3
## How far inland the water mesh is carried, in metres of terrain height. See
## the note in _build_water().
const SHORE_OVERLAP_M := 2.0
## Rocks appear where trees stop.
const ROCK_GRADE_LO := 0.16
const ROCK_GRADE_HI := 0.42

var _water_mat: StandardMaterial3D
var _scroll := 0.0

## Counted at build and printed once: the honest instance budget.
var counts := {"tree": 0, "shrub": 0, "rock": 0, "water_quads": 0}
## An order-dependent hash of every placement, printed with the counts.
##
## This is the determinism claim made CHECKABLE rather than asserted. Two runs
## of the same map must print the same fingerprint; if a stray randf() or an
## RNG draw ever creeps in here, the number moves and the log says so.
var _fingerprint := 0


## Build the scenery for a match and return self, so the whole thing is one
## call at the skirmish's construction site.
func build(m) -> Node3D:
	name = "Scenery"
	var t = m.terrain
	var econ = m.world.economy
	var bases: Array = []
	for pid in range(m.setup.players.size()):
		bases.append(m.base_position(pid))
	var t0 := Time.get_ticks_usec()
	_build_water(t)
	_scatter(t, econ, bases)
	print("[scenery] %d trees, %d shrubs, %d rocks, %d water quads, %d nodes, %.0f ms, fp %x"
		% [counts.tree, counts.shrub, counts.rock, counts.water_quads,
			get_child_count(), float(Time.get_ticks_usec() - t0) / 1000.0,
			_fingerprint])
	return self


# ═══════════════════════════════════════════════════════════════════════════
# WATER
# ═══════════════════════════════════════════════════════════════════════════

## A real sea surface at height 0.
##
## It used to be dark blue VERTEX COLOUR on the terrain mesh, which is a
## picture of a wet seabed and not of water: no surface, no specular, no
## horizon, and a coast that read as painted mud. The seabed colour is still
## there and still doing its job -- it is what you see THROUGH this.
##
## DEPTH TINT WITHOUT A SHADER. The mesh is built on the same lattice as the
## terrain mesh and carries a per-vertex colour AND ALPHA taken from the
## terrain's own depth: a pale green-blue at 90 % transparency over the
## shelf, going to a near-opaque deep blue by 20 m down. So the shelf reads
## paler than the deep exactly where it is shallower, and it does so from the
## real bathymetry rather than from a painted gradient.
##
## THE SHORELINE STAYS LEGIBLE, which is a rule and not a preference: a naval
## yard is only legal at the water's edge. Alpha goes to ZERO at zero depth,
## so the last metre of water is glass and the waterline you see is the
## terrain's own, in the terrain's own colours -- the water cannot move the
## edge because it does not paint it.
func _build_water(t) -> void:
	var hx: float = t.extent_x_m() * 0.5
	var hz: float = t.extent_z_m() * 0.5
	var cell: float = t.cell_size_m
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var quads := 0
	var edge_wet := false
	for cz in range(t.cells_z - 1):
		for cx in range(t.cells_x - 1):
			var quad := [Vector2i(cx, cz), Vector2i(cx + 1, cz),
				Vector2i(cx + 1, cz + 1), Vector2i(cx, cz + 1)]
			var wet := false
			for q in quad:
				var qh: float = t.height_at_cell(q.x, q.y)
				# A LITTLE INLAND. The quad is kept if any corner is below
				# +2 m rather than below 0, which carries the surface onto
				# the beach at alpha zero and gives the fade a whole cell to
				# work in wherever a coast RAMPS.
				#
				# Measured honestly: on coastal_shelf it changes nothing at
				# all -- carve_sea() cuts the bay as a step from +35 m to
				# -45 m, so no cell on that map lands between 0 and 2 m and
				# the quad count is identical either way. The remaining
				# staircase at that shoreline is the heightfield's own shape
				# at 50 m cells, which is the simulation's terrain and not
				# mine to smooth. This costs nothing and is right for any map
				# whose coast shelves, including a hand-authored one.
				if qh < SHORE_OVERLAP_M:
					wet = true
				if qh < 0.0 and (q.x == 0 or q.y == 0
						or q.x == t.cells_x - 1 or q.y == t.cells_z - 1):
					edge_wet = true
			if not wet:
				continue
			quads += 1
			var p: Array = []
			for q in quad:
				p.append(Vector3(float(q.x) * cell - hx, 0.0,
					float(q.y) * cell - hz))
			_wtri(st, p[0], p[1], p[2], [quad[0], quad[1], quad[2]], t)
			_wtri(st, p[0], p[2], p[3], [quad[0], quad[2], quad[3]], t)
	counts.water_quads = quads
	if quads == 0:
		# A dry map -- Skirmish Valley is one, it fills to 30 m and never goes
		# below it -- gets no water node at all rather than an invisible plane
		# buried under the ground.
		return

	# THE SKIRT. Where the sea runs off the edge of the map the detailed mesh
	# stops dead, and at 2400 m of zoom the player is looking at a rectangle
	# of sea with sky beyond it. Four big quads carry the deep colour out to
	# 20 km, which is past the fog. Eight triangles, and only built when the
	# water actually reaches an edge -- an inland lake does not get an ocean
	# around the map.
	if edge_wet:
		var far := 20000.0
		var deep := Color(0.020, 0.075, 0.150, 1.0)
		var frame := [
			[Vector3(-far, 0, -far), Vector3(far, 0, -far),
				Vector3(far, 0, -hz), Vector3(-far, 0, -hz)],
			[Vector3(-far, 0, hz), Vector3(far, 0, hz),
				Vector3(far, 0, far), Vector3(-far, 0, far)],
			[Vector3(-far, 0, -hz), Vector3(-hx, 0, -hz),
				Vector3(-hx, 0, hz), Vector3(-far, 0, hz)],
			[Vector3(hx, 0, -hz), Vector3(far, 0, -hz),
				Vector3(far, 0, hz), Vector3(hx, 0, hz)]]
		for f in frame:
			for tri in [[0, 1, 2], [0, 2, 3]]:
				for k in tri:
					var v: Vector3 = f[k]
					st.set_color(deep)
					st.set_uv(Vector2(v.x, v.z))
					st.set_normal(Vector3.UP)
					st.add_vertex(v)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# The palette below is written the way a colour picker gives it, matching
	# the terrain material's own convention.
	mat.vertex_color_is_srgb = true
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Depth WRITE off, depth TEST on: one flat translucent layer sorts against
	# the terrain correctly without occluding the seabed it is meant to show.
	mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Water is the one surface on this map that is nearly a mirror. Low
	# roughness and a real specular give the sun a glint on it; the metallic
	# term makes it take its colour from the sky, which is what tells the eye
	# it is a surface and not a blue floor. Ambient light on this scene is
	# sourced from the sky, so that reflection costs nothing extra.
	mat.metallic = 0.35
	mat.metallic_specular = 0.85
	mat.roughness = 0.075
	mat.normal_enabled = true
	mat.normal_texture = _ripple_normal(128)
	mat.normal_scale = 0.7
	# UVs are world metres, so the ripple is the same size everywhere and does
	# not stretch across a wide bay. 34 m a tile: big enough not to shimmer
	# into noise at the 2400 m zoom stop, small enough to read as chop at 45 m.
	mat.uv1_scale = Vector3(1.0 / 34.0, 1.0 / 34.0, 1.0 / 34.0)
	# A SECOND RIPPLE, scrolling the other way. One scrolling normal map reads
	# as a sheet of plastic being dragged: every wave keeps its shape and the
	# whole surface translates. Two, at different scales and crossing
	# directions, interfere, and the interference is what looks like water.
	mat.detail_enabled = true
	mat.detail_uv_layer = BaseMaterial3D.DETAIL_UV_2
	mat.detail_blend_mode = BaseMaterial3D.BLEND_MODE_MIX
	mat.detail_albedo = _flat_texture(Color(1, 1, 1, 0))
	mat.detail_normal = _ripple_normal(96)
	mat.uv2_scale = Vector3(1.0 / 17.0, 1.0 / 17.0, 1.0 / 17.0)

	# Tangents, because the ripple is a NORMAL map and a normal map without a
	# tangent frame lights as if the surface were flat.
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	# Water neither casts nor receives a shadow worth having here, and a
	# 20 km skirt in the shadow pass is pure waste.
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	_water_mat = mat


## One water vertex: flat, at height 0, coloured and faded by the depth of the
## ground under it.
func _wtri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		cells: Array, t) -> void:
	var v := [a, b, c]
	for k in range(3):
		var q: Vector2i = cells[k]
		var d: float = maxf(-t.height_at_cell(q.x, q.y), 0.0)
		st.set_color(_water_colour(d))
		st.set_uv(Vector2(v[k].x, v[k].z))
		st.set_normal(Vector3.UP)
		st.add_vertex(v[k])


## Depth in metres -> the colour and opacity of the water over it.
##
## The alpha curve is the part that matters. It is zero at the waterline and
## only reaches a half by about 2 m of depth, so the surf zone is transparent
## and the coast is drawn by the ground, not by this. It then closes fast, so
## that by the time you are over the shelf proper you are looking at sea and
## not at a blue filter over mud.
static func _water_colour(d: float) -> Color:
	var shallow := Color(0.235, 0.560, 0.545)
	var deep := Color(0.020, 0.105, 0.215)
	var c := shallow.lerp(deep, clampf(d / 22.0, 0.0, 1.0))
	var a: float = smoothstep(0.0, 2.2, d) * 0.92
	return Color(c.r, c.g, c.b, a)


## A tiling ripple, as a normal map. Two octaves of value noise, differenced
## into a normal. Deterministic: fixed salts, integer hashing, no RNG.
func _ripple_normal(n: int) -> ImageTexture:
	var hgt := PackedFloat32Array()
	hgt.resize(n * n)
	for y in range(n):
		for x in range(n):
			var v := 0.0
			var amp := 1.0
			var tot := 0.0
			for period in [8, 19, 41]:
				# The lattice period must DIVIDE the image for the tile to
				# join; _lat wraps its coordinates, so any period tiles as
				# long as the sample step lands on the lattice.
				v += _val(float(x) * float(period) / float(n),
					float(y) * float(period) / float(n), 7 + period,
					period) * amp
				tot += amp
				amp *= 0.55
			hgt[y * n + x] = v / tot
	var img := Image.create(n, n, true, Image.FORMAT_RGB8)
	for y in range(n):
		for x in range(n):
			var l: float = hgt[y * n + posmod(x - 1, n)]
			var r: float = hgt[y * n + posmod(x + 1, n)]
			var u: float = hgt[posmod(y - 1, n) * n + x]
			var dn: float = hgt[posmod(y + 1, n) * n + x]
			var nrm := Vector3((l - r) * 6.0, (u - dn) * 6.0, 1.0).normalized()
			img.set_pixel(x, y, Color(nrm.x * 0.5 + 0.5,
				nrm.y * 0.5 + 0.5, nrm.z * 0.5 + 0.5))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _flat_texture(c: Color) -> ImageTexture:
	var img := Image.create(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)


## Drift the two ripple layers past each other. Visual only -- it reads no sim
## state and writes none, and the sim's clock is not involved.
func _process(delta: float) -> void:
	if _water_mat == null:
		return
	_scroll += delta
	_water_mat.uv1_offset = Vector3(_scroll * 0.020, _scroll * 0.012, 0.0)
	_water_mat.uv2_offset = Vector3(_scroll * -0.028, _scroll * 0.019, 0.0)


# ═══════════════════════════════════════════════════════════════════════════
# SCATTER
# ═══════════════════════════════════════════════════════════════════════════

## Trees, scrub and boulders.
##
## The whole scatter is a single pass over the terrain cells. Each cell asks
## four questions -- how steep, how high, how far from anything a player has
## to read, and how deep into a clump -- and turns the answers into a count.
## Positions inside a cell come from the cell's own hash, so the field is a
## pure function of the heightfield and the map's name.
func _scatter(t, econ, bases: Array) -> void:
	var hx: float = t.extent_x_m() * 0.5
	var hz: float = t.extent_z_m() * 0.5
	var cell: float = t.cell_size_m
	var salt: int = abs(hash(t.name)) & 0xFFFFFF

	var lo := 1.0e18
	var hi := -1.0e18
	for i in range(t.cells_x * t.cells_z):
		var h: float = t.heights[i]
		lo = minf(lo, h)
		hi = maxf(hi, h)
	var span: float = maxf(hi - lo, 1.0)

	# tile -> layer -> Array of [Transform3D, Color]
	var tiles := {}
	for cz in range(1, t.cells_z - 1):
		for cx in range(1, t.cells_x - 1):
			var h: float = t.height_at_cell(cx, cz)
			if h < TREE_SHORE_M:
				continue
			var grade := _grade(t, cx, cz)
			var alt: float = (h - lo) / span
			# Two clump fields with different salts, so where the woods are is
			# not simply where the rocks are not.
			var wood: float = _fbm(cx, cz, salt)
			var scree: float = _fbm(cx, cz, salt + 991)

			var tree_w: float = (1.0 - smoothstep(TREE_GRADE_LO,
					TREE_GRADE_HI, grade)) \
				* (1.0 - smoothstep(TREE_ALT_LO, TREE_ALT_HI, alt)) \
				# WIDER WOODS. At 0.52 the clump field put trees on well under a
				# fifth of the map, and where the woods fell was pure luck of the
				# noise -- on Skirmish Valley it left the entire opening view,
				# the 411 m a player judges the map by, without a single tree in
				# it. Clumping is right; this much of it was not.
				* smoothstep(0.36, 0.66, wood)
			var rock_w: float = smoothstep(ROCK_GRADE_LO, ROCK_GRADE_HI,
					grade) * smoothstep(0.30, 0.66, scree)
			# Scrub takes the ground the trees did not: the edge of a clump
			# and the open between them. It is deliberately WIDE AND LOW --
			# 5 m across and a metre high -- because a waist-high dark blob at
			# tank scale is the one shape that could be mistaken for infantry,
			# and a flat patch of it cannot be.
			var shrub_w: float = (1.0 - smoothstep(0.12, 0.30, grade)) \
				* smoothstep(0.34, 0.62, wood) * 0.22

			_place(tiles, t, econ, bases, cx, cz, salt, hx, hz, cell,
				"tree", tree_w, TREES_PER_CELL, alt)
			_place(tiles, t, econ, bases, cx, cz, salt + 313, hx, hz, cell,
				"shrub", shrub_w, 3, alt)
			_place(tiles, t, econ, bases, cx, cz, salt + 577, hx, hz, cell,
				"rock", rock_w, 3, alt)

	var meshes := {
		"tree": _tree_mesh(false), "conifer": _tree_mesh(true),
		"shrub": _shrub_mesh(), "rock": _rock_mesh()}
	for key in tiles:
		var layers: Dictionary = tiles[key]
		for layer in layers:
			var items: Array = layers[layer]
			if items.is_empty():
				continue
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = meshes[layer]
			mm.instance_count = items.size()
			for k in range(items.size()):
				mm.set_instance_transform(k, items[k][0])
				mm.set_instance_color(k, items[k][1])
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			# Scenery casts shadows -- a wood with no shadow under it reads as
			# a decal -- but the sun's shadow range is 900 m, so this is only
			# ever paid for the tiles near the camera.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
			add_child(mi)


## Turn a weight into instances, and put them somewhere legal.
func _place(tiles: Dictionary, t, econ, bases: Array, cx: int, cz: int,
		salt: int, hx: float, hz: float, cell: float, layer: String,
		w: float, cap: int, alt: float) -> void:
	if w <= 0.001:
		return
	var want: float = w * float(cap)
	var n: int = int(want)
	# The fractional part is spent as a per-cell coin, so a weight of 0.3 is
	# three cells in ten rather than a silent zero. Hashed, so it is the same
	# coin every run.
	if _h01(cx, cz, salt + 4409) < want - float(n):
		n += 1
	for j in range(n):
		var jx: float = _h01(cx * 3 + j, cz, salt + 17 + j * 101)
		var jz: float = _h01(cx, cz * 3 + j, salt + 53 + j * 211)
		var x: float = (float(cx) + jx - 0.5) * cell - hx
		var z: float = (float(cz) + jz - 0.5) * cell - hz
		if not _legal(t, econ, bases, x, z):
			continue
		# Sit on the DRAWN ground. The terrain mesh puts cell (cx,cz) at
		# x = cx*cell - hx; SimTerrain.height_at() puts the same cell's centre
		# half a cell further on, so sampling the sim's bilinear here would
		# float a tree by up to the local relief over 25 m. This interpolates
		# the same lattice the mesh is built from, which is why nothing hovers.
		var y: float = _mesh_height(t, x, z, hx, hz, cell)
		if y < TREE_SHORE_M and layer != "rock":
			continue
		var key := Vector2i(int(floor((x + hx) / TILE_M)),
			int(floor((z + hz) / TILE_M)))
		if not tiles.has(key):
			tiles[key] = {}
		var use := layer
		if layer == "tree":
			# Conifers take the high ground, broadleaf the low, with a wide
			# band of both between -- a treeline that is a gradient, the way
			# one looks from the air.
			use = "conifer" if _h01(cx, cz, salt + 71) < clampf(
				alt * 1.6 + 0.05, 0.0, 1.0) else "tree"
		if not tiles[key].has(use):
			tiles[key][use] = []
		tiles[key][use].append(_instance(use, x, y, z, cx, cz, j, salt, alt))
		_fingerprint = ((_fingerprint * 1000003) ^ (int(x * 8.0) * 73856093)
			^ (int(z * 8.0) * 19349663) ^ use.hash()) & 0xFFFFFFFFFFFF
		counts[layer] += 1


## One instance: where it stands, how big, which way round, and what shade.
func _instance(layer: String, x: float, y: float, z: float, cx: int, cz: int,
		j: int, salt: int, alt: float) -> Array:
	var r1: float = _h01(cx + j * 7, cz - j * 5, salt + 881)
	var r2: float = _h01(cx - j * 11, cz + j * 3, salt + 1327)
	var r3: float = _h01(cx + j * 13, cz + j * 17, salt + 2003)
	var b := Basis.IDENTITY.rotated(Vector3.UP, r1 * TAU)
	var c: Color
	match layer:
		"rock":
			# Boulders get non-uniform scale and a tip off vertical: a field
			# of upright ellipsoids reads as eggs, not as scree.
			b = b.rotated(Vector3.RIGHT, (r2 - 0.5) * 0.9)
			b = b.scaled(Vector3(0.7 + r2 * 1.3, 0.55 + r3 * 0.9,
				0.7 + r3 * 1.2))
			# The same grey-brown the terrain's scree blend uses, lightening
			# with altitude, so a boulder belongs to the slope it sits on.
			var g: float = 0.34 + alt * 0.16 + (r1 - 0.5) * 0.09
			c = Color(g * 1.04, g, g * 0.93)
			y -= 0.35 * (0.55 + r3 * 0.9)
		"shrub":
			b = b.scaled(Vector3(0.7 + r2 * 0.7, 0.6 + r3 * 0.7,
				0.7 + r3 * 0.7))
			var d: float = 0.130 + r1 * 0.085
			c = Color(d * 0.70, d * 1.06, d * 0.38)
			y -= 0.25
		_:
			var s: float = 0.72 + r2 * 0.66
			b = b.scaled(Vector3(s, s * (0.85 + r3 * 0.42), s))
			# Canopy colour. GREEN DOMINATES, which sounds obvious and was
			# the first version's bug: it weighted red equal to green and
			# every tree on the map came out the same khaki as the grass
			# under it, so a wood read as gravel. The swing is olive (dry,
			# yellower, on high ground) to a deep blue-green (damp, low), and
			# it is DARKER than the ground it stands on -- a canopy seen from
			# above is in its own shade, and that contrast is the only reason
			# a wood reads as a wood on the minimap-scale zoom.
			var v: float = 0.135 + r1 * 0.085
			c = Color(v * (0.62 + alt * 0.30), v * (1.15 + r3 * 0.10),
				v * (0.38 + r2 * 0.26))
			y -= 0.4
	return [Transform3D(b, Vector3(x, y, z)), c]


## Nothing may stand where it would mislead: not in the water, not in a base,
## not on the ore or the oil.
func _legal(t, econ, bases: Array, x: float, z: float) -> bool:
	if t.is_water(x, z):
		return false
	for b in bases:
		if Vector2(x, z).distance_squared_to(b) < CLEAR_BASE_M * CLEAR_BASE_M:
			return false
	for f in econ.ore_fields:
		if Vector2(x, z).distance_squared_to(f) < CLEAR_ORE_M * CLEAR_ORE_M:
			return false
	for f in econ.oil_fields:
		if Vector2(x, z).distance_squared_to(f) < CLEAR_OIL_M * CLEAR_OIL_M:
			return false
	return true


## Bilinear height on the lattice the terrain MESH is built from -- vertices
## at cell corners, not at cell centres. See the note in _place().
static func _mesh_height(t, x: float, z: float, hx: float, hz: float,
		cell: float) -> float:
	var fx: float = (x + hx) / cell
	var fz: float = (z + hz) / cell
	var x0 := int(floor(fx))
	var z0 := int(floor(fz))
	var tx: float = fx - float(x0)
	var tz: float = fz - float(z0)
	var h00: float = t.height_at_cell(x0, z0)
	var h10: float = t.height_at_cell(x0 + 1, z0)
	var h01: float = t.height_at_cell(x0, z0 + 1)
	var h11: float = t.height_at_cell(x0 + 1, z0 + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


## Gradient in metres per metre, by the same central difference the terrain
## shading uses, divided by the span actually sampled so a map edge does not
## read as half its true grade.
static func _grade(t, cx: int, cz: int) -> float:
	var x0: int = maxi(cx - 1, 0)
	var x1: int = mini(cx + 1, t.cells_x - 1)
	var z0: int = maxi(cz - 1, 0)
	var z1: int = mini(cz + 1, t.cells_z - 1)
	var dhdx: float = (t.height_at_cell(x1, cz) - t.height_at_cell(x0, cz)) \
		/ maxf(float(x1 - x0) * t.cell_size_m, 1.0)
	var dhdz: float = (t.height_at_cell(cx, z1) - t.height_at_cell(cx, z0)) \
		/ maxf(float(z1 - z0) * t.cell_size_m, 1.0)
	return sqrt(dhdx * dhdx + dhdz * dhdz)


# ═══════════════════════════════════════════════════════════════════════════
# MESHES
# ═══════════════════════════════════════════════════════════════════════════

## A tree, as ONE mesh with TWO surfaces: trunk and crown.
##
## Two surfaces rather than two MultiMeshes because the crown's material takes
## the per-instance colour and the trunk's does not -- a MultiMesh colour
## reaches every surface, and a green trunk is worse than no variation. One
## MultiMesh per tile per species either way.
func _tree_mesh(conifer: bool) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.30
	trunk.bottom_radius = 0.62
	trunk.height = 5.4 if conifer else 4.6
	trunk.radial_segments = 6
	trunk.rings = 1
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(trunk, 0, Transform3D(Basis.IDENTITY,
		Vector3(0, trunk.height * 0.5, 0)))
	st.generate_normals()
	st.commit(mesh)
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.24, 0.185, 0.135)
	bark.roughness = 0.95
	mesh.surface_set_material(0, bark)

	var st2 := SurfaceTool.new()
	st2.begin(Mesh.PRIMITIVE_TRIANGLES)
	if conifer:
		# Three stacked cones. A cone is a CylinderMesh with no top; seven
		# segments is enough at the zoom a player sits at and is 21 triangles.
		var y := 3.4
		var r := 3.5
		var hgt := 5.0
		for k in range(3):
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = r
			cone.height = hgt
			cone.radial_segments = 7
			cone.rings = 1
			st2.append_from(cone, 0, Transform3D(Basis.IDENTITY,
				Vector3(0, y + hgt * 0.5, 0)))
			y += hgt * 0.42
			r *= 0.68
			hgt *= 0.78
	else:
		# Two overlapping lobes, offset, so the crown is not a ball.
		for o in [[Vector3(0, 7.4, 0), 4.3], [Vector3(1.5, 9.4, -1.1), 2.9]]:
			var blob := SphereMesh.new()
			blob.radius = o[1]
			blob.height = float(o[1]) * 1.75
			blob.radial_segments = 7
			blob.rings = 4
			st2.append_from(blob, 0, Transform3D(Basis.IDENTITY, o[0]))
	st2.generate_normals()
	st2.commit(mesh)
	var leaf := StandardMaterial3D.new()
	leaf.vertex_color_use_as_albedo = true
	leaf.vertex_color_is_srgb = true
	leaf.roughness = 0.98
	mesh.surface_set_material(1, leaf)
	return mesh


## Scrub: two low lobes, about 3 m across and 1.6 m high.
##
## The first version was ONE dome squashed to 0.42 and cut with six segments,
## and at the playing zoom a six-sided disc lying on the ground does not read
## as a bush -- it reads as litter, or as a puddle. Two rounder lobes at
## eight segments cost thirty more triangles each and read as vegetation.
## Still deliberately LOW: a waist-high dark blob at tank scale is the one
## silhouette that could be mistaken for infantry, and a sprawling one cannot.
func _shrub_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for o in [[Vector3(0, 0.62, 0), 1.55, 1.0], [Vector3(1.0, 0.42, 0.7), 1.0, 0.9]]:
		var blob := SphereMesh.new()
		blob.radius = o[1]
		blob.height = float(o[1]) * 2.0
		blob.radial_segments = 8
		blob.rings = 4
		st.append_from(blob, 0, Transform3D(
			Basis.IDENTITY.scaled(Vector3(1.0, float(o[2]) * 0.62, 1.0)),
			o[0]))
	st.generate_normals()
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 1.0
	mesh.surface_set_material(0, m)
	return mesh


## A boulder: a coarse sphere, DEINDEXED so every face keeps its own normal.
## Smooth normals on a six-segment sphere give a soft grey pebble; flat ones
## give something with facets that catch the sun, which is what rock does.
func _rock_mesh() -> ArrayMesh:
	var blob := SphereMesh.new()
	blob.radius = 2.1
	blob.height = 3.4
	blob.radial_segments = 6
	blob.rings = 3
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.append_from(blob, 0, Transform3D(Basis.IDENTITY, Vector3(0, 1.0, 0)))
	st.deindex()
	st.generate_normals()
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.roughness = 0.92
	mesh.surface_set_material(0, m)
	return mesh


# ═══════════════════════════════════════════════════════════════════════════
# DETERMINISTIC NOISE
# ═══════════════════════════════════════════════════════════════════════════

## 0..1 from three integers. Integer mixing only: no RNG object, no engine
## state, nothing that a replay or a second player could disagree about.
static func _h01(x: int, y: int, salt: int) -> float:
	var n: int = (x * 73856093) ^ (y * 19349663) ^ (salt * 83492791)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0


## Smoothed value noise sampled at a real position on an integer lattice.
static func _val(fx: float, fz: float, salt: int, period: int) -> float:
	var ix := int(floor(fx))
	var iz := int(floor(fz))
	var tx: float = fx - float(ix)
	var tz: float = fz - float(iz)
	tx = tx * tx * (3.0 - 2.0 * tx)
	tz = tz * tz * (3.0 - 2.0 * tz)
	var n0 := lerpf(_h01(posmod(ix, period), posmod(iz, period), salt),
		_h01(posmod(ix + 1, period), posmod(iz, period), salt), tx)
	var n1 := lerpf(_h01(posmod(ix, period), posmod(iz + 1, period), salt),
		_h01(posmod(ix + 1, period), posmod(iz + 1, period), salt), tx)
	return lerpf(n0, n1, tz)


## Two octaves of clump noise on the cell lattice.
##
## THE FEATURE SIZE IS SET BY THE SCREEN, not by taste. Cells are 50 m and the
## camera opens on 411 m of ground, so a 700 m wood -- what the first version
## had -- is BIGGER THAN THE VIEW: every screen came out uniformly wooded or
## uniformly bare, and a forest with no visible edge is just a texture. At 350
## and 150 m the player sees the wood, its edge, and the open ground beside it
## at the zoom the game is played at, which is what makes it terrain rather
## than decoration.
static func _fbm(cx: int, cz: int, salt: int) -> float:
	var v := 0.0
	var amp := 1.0
	var tot := 0.0
	for period in [7, 3]:
		v += _val(float(cx) / float(period), float(cz) / float(period),
			salt + period, 1 << 20) * amp
		tot += amp
		amp *= 0.55
	return v / tot
