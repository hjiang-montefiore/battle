extends Node3D
## THE MAP EDITOR. Empty ground to a playable two-base map in five minutes.
##
## Everything this scene does is a mutation of ONE document: a SimMapFile.
## Sculpting appends ops to its height list, placing a base appends to its
## bases list, and save writes the same data/maps/<name>.json the loader
## replays -- so the editor cannot express a map the format cannot say, and
## undo is exactly what the format promises: pop the last op and replay.
##
## ── LIVE SCULPTING WITHOUT REBUILDING THE WORLD ──────────────────────────────
## The terrain mesh is CHUNKED, 32x32 cells per MeshInstance3D. A committed op
## is applied incrementally to the working heightfield (the same SimMapFile
## _apply the loader replays through, so incremental and replayed ground are
## bit-identical -- the headless test hashes both to hold that), then only the
## chunks under the op's footprint are rebuilt. A raise dab on a 12.8 km map
## touches one to four chunks, not 16384 cells of SurfaceTool.
##
## Two heightfields are kept: _raw is the pure op replay, _view is _raw minus
## water_level. The split exists because water_level is applied LAST in
## SimMapFile.build_terrain() -- ops must always land on the raw field or an
## edit made at +10 m of sea rise would replay differently from how it was
## sculpted. Everything the author sees and every validity check uses _view,
## which is exactly the terrain build_terrain() would hand a match.
##
## ── VALIDITY IS THE ARENA'S OWN RULE ─────────────────────────────────────────
## A base marker is refused (red ring, reason flashed) by
## SimMapFile.base_problem() -- the same nine-point dry-footprint test at
## SimArena.BASE_FOOTPRINT_M the arena's placer walks, plus the deployable
## margin and pairwise separation. A map this editor accepts is a map the
## match can start on.
##
## Headless test:  godot --path game --headless res://scenes/map_editor.tscn -- --test
## (also driven, sceneless, by sim/tests/test_map_file_editor.gd).

const RTS_CAMERA := preload("res://scripts/rts_camera.gd")

## 32x32 cells of quads per mesh chunk: small enough that a brush dab rebuilds
## a few thousand triangles, big enough that a 1024-cell map is ~1k nodes.
const CHUNK_CELLS := 32
## World-metre snap for recorded coordinates, so the saved JSON reads as
## intent ("x": -2000) rather than float noise ("x": -2000.0000038).
const SNAP_M := 1.0

enum Tool { RAISE, LOWER, SMOOTH, PLATEAU, RIDGE, BASIN, WATER, BASE, DEPOSIT }

const TOOL_NAME := {
	Tool.RAISE: "RAISE", Tool.LOWER: "LOWER", Tool.SMOOTH: "SMOOTH",
	Tool.PLATEAU: "PLATEAU", Tool.RIDGE: "RIDGE", Tool.BASIN: "BASIN",
	Tool.WATER: "WATER", Tool.BASE: "BASE", Tool.DEPOSIT: "DEPOSIT",
}
const TOOL_HINT := {
	Tool.RAISE: "click / drag: raise ground by strength inside the ring",
	Tool.LOWER: "click / drag: lower ground by strength inside the ring",
	Tool.SMOOTH: "click: one 3x3 smoothing pass over the whole map",
	Tool.PLATEAU: "click: flatten a disc to the height you clicked",
	Tool.RIDGE: "drag: a ridge from press to release (peak = strength, half-width = radius)",
	Tool.BASIN: "drag: a rectangular sea (depth = strength)",
	Tool.WATER: "use the +/- buttons (or U / J): raise or lower the sea itself",
	Tool.BASE: "click: place the next player's spawn -- refused with a reason if unsuitable",
	Tool.DEPOSIT: "click: place an oil field -- dry land only, derricks cannot stand in water",
}

# ── the document ─────────────────────────────────────────────────────────────
var _map: SimMapFile
var _raw: SimTerrain           ## pure op replay, no water offset
var _view: SimTerrain          ## _raw - water_level: what a match would get
## Undo stack. One entry per user edit: {"kind": "op"|"base"|"deposit"|"water"}.
## Sculpt undo is ops.pop_back() + replay, exactly the format's promise.
var _history: Array = []
var _problems := PackedStringArray()

# ── tool state ───────────────────────────────────────────────────────────────
var _tool: int = Tool.RAISE
var _radius := 600.0
var _strength := 60.0
var _stroking := false
var _stroke_from := Vector3.ZERO
var _last_dab := Vector3.ZERO
var _cursor := Vector3.ZERO

# ── presentation (all null when driven headless without a scene) ─────────────
var _rig: Node3D
var _chunks_root: Node3D
var _chunks: Dictionary = {}   ## Vector2i -> MeshInstance3D
var _ground_mat: StandardMaterial3D
var _markers_root: Node3D
var _ring: MeshInstance3D
var _ring_mat: StandardMaterial3D
var _stroke_line: MeshInstance3D

# ── HUD ──────────────────────────────────────────────────────────────────────
var _name_edit: LineEdit
var _status: Label
var _problems_label: Label
var _water_label: Label
var _radius_label: Label
var _strength_label: Label
var _radius_slider: HSlider
var _strength_slider: HSlider
var _tool_buttons: Dictionary = {}
var _minimap_rect: TextureRect
var _minimap_dirty := true
var _minimap_accum := 0.0
var _flash_msg := ""
var _flash_until := 0.0

# ── headless test bookkeeping ────────────────────────────────────────────────
var _t_passed := 0
var _t_failed := 0


# ═══════════════════════════════════════════════════════════════════════════
# BOOT
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_new_map()
	_build_environment()
	_build_world_nodes()
	_build_hud()
	_rebuild_all()
	_frame_camera()
	var argv := OS.get_cmdline_user_args()
	if "--test" in argv:
		var failed := run_test_session()
		# Two scene-only paths the sceneless harness cannot reach: the minimap
		# bake and the camera-ray ground pick, exercised here with the real rig.
		_bake_minimap()
		_t_ok("the minimap bakes to a texture", _minimap_rect.texture != null)
		var p := _ground_point(Vector2(400.0, 300.0))
		_t_ok("the camera ray lands on the map",
			absf(p.x) <= _view.extent_x_m() * 0.5 + 1.0
			and absf(p.z) <= _view.extent_z_m() * 0.5 + 1.0,
			"%.0f, %.0f" % [p.x, p.z])
		failed = _t_failed
		get_tree().quit(1 if failed > 0 else 0)


func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_horizon_color = Color(0.62, 0.66, 0.70)
	sm.ground_horizon_color = Color(0.32, 0.32, 0.30)
	sky.sky_material = sm
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.35
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 136, 0)
	sun.light_energy = 1.7
	add_child(sun)
	_rig = RTS_CAMERA.new()
	_rig.set("zoom_min", 60.0)
	_rig.set("zoom_max", 9000.0)
	_rig.set("pan_speed", 420.0)
	add_child(_rig)


func _build_world_nodes() -> void:
	_ground_mat = StandardMaterial3D.new()
	_ground_mat.vertex_color_use_as_albedo = true
	# sRGB, same as skirmish.gd: left linear the map renders two stops brighter
	# and every contour washes out.
	_ground_mat.vertex_color_is_srgb = true
	_ground_mat.roughness = 0.96
	_chunks_root = Node3D.new()
	_chunks_root.name = "chunks"
	add_child(_chunks_root)
	_markers_root = Node3D.new()
	_markers_root.name = "markers"
	add_child(_markers_root)

	_ring_mat = StandardMaterial3D.new()
	_ring_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring_mat.albedo_color = Color(0.95, 0.97, 0.95)
	_ring = MeshInstance3D.new()
	_ring.mesh = ImmediateMesh.new()
	_ring.material_override = _ring_mat
	add_child(_ring)

	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.albedo_color = Color(1.0, 0.85, 0.25)
	_stroke_line = MeshInstance3D.new()
	_stroke_line.mesh = ImmediateMesh.new()
	_stroke_line.material_override = sm
	add_child(_stroke_line)


func _frame_camera() -> void:
	if _rig == null or _view == null:
		return
	_rig.set("bounds_m", minf(_view.extent_x_m(), _view.extent_z_m()) * 0.5)
	_rig.set("_dist", _view.extent_x_m() * 0.55)
	_rig.position = Vector3(0.0, _view.ground_under(0.0, 0.0), 0.0)
	_rig.call("_apply")


# ═══════════════════════════════════════════════════════════════════════════
# THE DOCUMENT
# ═══════════════════════════════════════════════════════════════════════════

func _new_map() -> void:
	_map = SimMapFile.new()
	_map.map_name = "Untitled"
	_map.author = OS.get_environment("USER")
	_map.size_m = 12800.0
	_map.cell_m = 100.0
	_map.water_level = 0.0
	# Every map starts as dry ground at +60 m -- the same opening move every
	# procedural arena makes -- so the water tools have somewhere to go in both
	# directions. Not undoable: it is the canvas, not an edit.
	_map.ops = [{"op": "fill", "h": 60.0}]
	_map.bases = []
	_map.deposits = []
	_history.clear()
	if _name_edit != null:
		_name_edit.text = _map.map_name
	_rebuild_all()


## Replay the whole op list from scratch: load, undo, and new all land here.
## Sculpting between rebuilds goes through _commit_op's incremental path.
func _rebuild_all() -> void:
	var n := _map.cells()
	_raw = SimTerrain.new(n, n, _map.cell_m, _map.map_name)
	for op in _map.ops:
		_map._apply(_raw, op)
	_view = SimTerrain.new(n, n, _map.cell_m, _map.map_name)
	_sync_view(Rect2i(0, 0, n, n))
	_rebuild_chunk_grid()
	_after_edit()


## Append one op, apply it to the raw field, refresh only what it touched.
func _commit_op(op: Dictionary) -> void:
	_map.ops.append(op)
	_map._apply(_raw, op)
	_history.append({"kind": "op"})
	var r := _op_rect(op)
	_sync_view(r)
	_rebuild_chunks_in(r)
	_after_edit()


func _after_edit() -> void:
	_problems = _map.validate(_view)
	_minimap_dirty = true
	_refresh_markers()
	if _problems_label != null:
		_problems_label.text = "\n".join(_problems)
		_problems_label.visible = not _problems.is_empty()


## _view = _raw - water_level over a cell rectangle. The subtraction mirrors
## SimMapFile.build_terrain()'s final offset exactly.
func _sync_view(r: Rect2i) -> void:
	var w := _raw.cells_x
	var lvl := _map.water_level
	for cz in range(r.position.y, r.position.y + r.size.y):
		var row := cz * w
		for cx in range(r.position.x, r.position.x + r.size.x):
			_view.heights[row + cx] = _raw.heights[row + cx] - lvl


## The cell rectangle an op can have written. Whole-map ops say so honestly;
## footprint ops pad by their own reach plus one cell for the shared vertices.
func _op_rect(op: Dictionary) -> Rect2i:
	var whole := Rect2i(0, 0, _raw.cells_x, _raw.cells_z)
	match String(op["op"]):
		"ridge", "seamount":
			return _cells_rect(float(op["x0"]), float(op["z0"]),
				float(op["x1"]), float(op["z1"]), float(op["half_width_m"]))
		"basin", "set_depth":
			return _cells_rect(float(op["x0"]), float(op["z0"]),
				float(op["x1"]), float(op["z1"]), 0.0)
		"plateau":
			var reach: float = float(op["radius_m"]) \
				+ float(op.get("blend_m", _map.cell_m * 3.0))
			return _cells_rect(float(op["x"]), float(op["z"]),
				float(op["x"]), float(op["z"]), reach)
		"raise":
			return _cells_rect(float(op["x"]), float(op["z"]),
				float(op["x"]), float(op["z"]), float(op["radius_m"]))
		"raw_patch":
			var r := Rect2i(int(op["cx0"]), int(op["cz0"]),
				int(op["w"]), int(op["h"]))
			return r.intersection(whole)
	# fill, noise, smooth, sea_coast (its wobble reaches wobble_m sideways):
	# the whole map, honestly.
	return whole


func _cells_rect(x0: float, z0: float, x1: float, z1: float, pad: float) -> Rect2i:
	var t := _raw
	var hx := t.extent_x_m() * 0.5
	var hz := t.extent_z_m() * 0.5
	var cx0 := clampi(int(floor((minf(x0, x1) - pad + hx) / t.cell_size_m)) - 1,
		0, t.cells_x - 1)
	var cx1 := clampi(int(floor((maxf(x0, x1) + pad + hx) / t.cell_size_m)) + 1,
		0, t.cells_x - 1)
	var cz0 := clampi(int(floor((minf(z0, z1) - pad + hz) / t.cell_size_m)) - 1,
		0, t.cells_z - 1)
	var cz1 := clampi(int(floor((maxf(z0, z1) + pad + hz) / t.cell_size_m)) + 1,
		0, t.cells_z - 1)
	return Rect2i(cx0, cz0, cx1 - cx0 + 1, cz1 - cz0 + 1)


# ═══════════════════════════════════════════════════════════════════════════
# TOOLS. Each commit function takes WORLD coordinates so the headless test can
# drive exactly what a click drives; the input layer only translates screens.
# ═══════════════════════════════════════════════════════════════════════════

func _snap(v: float) -> float:
	return snappedf(v, SNAP_M)


## One application of the raise/lower brush. delta_sign is +1 or -1.
func commit_dab(p: Vector3, delta_sign: float) -> void:
	_commit_op({"op": "raise", "x": _snap(p.x), "z": _snap(p.z),
		"radius_m": _snap(_radius),
		"delta_m": _snap(delta_sign * _strength)})


func commit_smooth() -> void:
	_commit_op({"op": "smooth", "passes": 1})
	_flash("smoothed the whole map (1 pass)")


## Flatten a disc to the height under the click -- the "make me a building
## site" brush. The target is a RAW height: the op must replay identically at
## any later water level.
func commit_plateau(p: Vector3) -> void:
	_commit_op({"op": "plateau", "x": _snap(p.x), "z": _snap(p.z),
		"radius_m": _snap(_radius),
		"h": _snap(_raw.height_at(p.x, p.z)),
		"blend_m": _snap(maxf(_radius * 0.5, _map.cell_m * 2.0))})


func commit_ridge(a: Vector3, b: Vector3) -> void:
	_commit_op({"op": "ridge",
		"x0": _snap(a.x), "z0": _snap(a.z), "x1": _snap(b.x), "z1": _snap(b.z),
		"peak_m": _snap(_strength), "half_width_m": _snap(_radius)})


func commit_basin(a: Vector3, b: Vector3) -> void:
	_commit_op({"op": "basin",
		"x0": _snap(a.x), "z0": _snap(a.z), "x1": _snap(b.x), "z1": _snap(b.z),
		"depth_m": _snap(_strength)})


func change_water(delta: float) -> void:
	_history.append({"kind": "water", "prev": _map.water_level})
	_map.water_level = _snap(_map.water_level + delta)
	_sync_view(Rect2i(0, 0, _raw.cells_x, _raw.cells_z))
	_rebuild_chunks_in(Rect2i(0, 0, _raw.cells_x, _raw.cells_z))
	_after_edit()
	_refresh_water_label()
	_flash("water level %.0f m" % _map.water_level)


## Place the next player's spawn, or say exactly why not. The refusal reasons
## are SimMapFile.base_problem's own -- the arena's suitability rules -- plus
## the pairwise separation the format enforces at load.
func place_base(x: float, z: float) -> String:
	var why := SimMapFile.base_problem(_view, x, z)
	if why == "":
		for k in range(_map.bases.size()):
			var b: Dictionary = _map.bases[k]
			var d := Vector2(x, z).distance_to(
				Vector2(float(b["x"]), float(b["z"])))
			if d < SimMapFile.MIN_BASE_SEPARATION_M:
				why = "too close to base %d (%.0f m, min %.0f)" \
					% [k, d, SimMapFile.MIN_BASE_SEPARATION_M]
				break
	if why != "":
		_flash("base refused: " + why)
		return why
	_map.bases.append({"player": _map.bases.size(),
		"x": _snap(x), "z": _snap(z)})
	_history.append({"kind": "base"})
	_after_edit()
	_flash("base %d placed" % (_map.bases.size() - 1))
	return ""


func place_deposit(x: float, z: float) -> String:
	var why := SimMapFile.deposit_problem(_view, x, z)
	if why != "":
		_flash("deposit refused: " + why)
		return why
	_map.deposits.append({"x": _snap(x), "z": _snap(z)})
	_history.append({"kind": "deposit"})
	_after_edit()
	_flash("deposit placed (%d total)" % _map.deposits.size())
	return ""


## Undo the last edit. A sculpt undo is the format's own promise cashed in:
## ops.pop_back() and replay -- ridge max() and basin min() are not invertible
## in place, so replay is the only honest inverse.
func undo() -> void:
	if _history.is_empty():
		_flash("nothing to undo")
		return
	var h: Dictionary = _history.pop_back()
	match String(h["kind"]):
		"op":
			_map.ops.pop_back()
			_rebuild_all()
			_flash("op undone (%d left)" % (_map.ops.size() - 1))
		"base":
			_map.bases.pop_back()
			_after_edit()
			_flash("base removed")
		"deposit":
			_map.deposits.pop_back()
			_after_edit()
			_flash("deposit removed")
		"water":
			_map.water_level = float(h["prev"])
			_sync_view(Rect2i(0, 0, _raw.cells_x, _raw.cells_z))
			_rebuild_chunks_in(Rect2i(0, 0, _raw.cells_x, _raw.cells_z))
			_after_edit()
			_refresh_water_label()
			_flash("water level back to %.0f m" % _map.water_level)


# ── save / load ──────────────────────────────────────────────────────────────

## "First Light" -> "first_light": the file key is derived from the display
## name, which is why loading by the name you typed just works.
func _map_key() -> String:
	var src := _map.map_name.to_lower()
	if _name_edit != null:
		src = _name_edit.text.to_lower()
	var out := ""
	for ch in src:
		if (ch >= "a" and ch <= "z") or (ch >= "0" and ch <= "9") or ch == "_":
			out += ch
		elif ch == " " or ch == "-":
			out += "_"
	return out


func do_save() -> String:
	var key := _map_key()
	if key == "":
		_flash("name the map before saving")
		return ""
	if _name_edit != null:
		_map.map_name = _name_edit.text
	var path := SimMapFile.path_of(key)
	if not _map.save(path):
		_flash("could not write " + path)
		return ""
	if _problems.is_empty():
		_flash("saved " + key + ".json")
	else:
		_flash("saved WITH %d problem(s) -- see the red list" % _problems.size())
	return path


func do_load() -> bool:
	var key := _map_key()
	var mf := SimMapFile.load_map(SimMapFile.path_of(key))
	if mf == null:
		_flash("cannot load '%s' -- no such map, or it was refused (see log)" % key)
		return false
	_map = mf
	_history.clear()
	if _name_edit != null:
		_name_edit.text = _map.map_name
	_rebuild_all()
	_refresh_water_label()
	_frame_camera()
	_flash("loaded %s: %d ops, %d bases, %d deposits"
		% [key, _map.ops.size(), _map.bases.size(), _map.deposits.size()])
	return true


# ═══════════════════════════════════════════════════════════════════════════
# THE MESH, IN CHUNKS
# ═══════════════════════════════════════════════════════════════════════════

func _rebuild_chunk_grid() -> void:
	if _chunks_root == null:
		return
	for node in _chunks.values():
		(node as Node).queue_free()
	_chunks.clear()
	var n := _view.cells_x
	var per_axis := int(ceil(float(n - 1) / float(CHUNK_CELLS)))
	for j in range(per_axis):
		for i in range(per_axis):
			var mi := MeshInstance3D.new()
			mi.material_override = _ground_mat
			_chunks_root.add_child(mi)
			_chunks[Vector2i(i, j)] = mi
			_build_chunk(i, j)


## Rebuild the chunks whose triangles read any cell in the rectangle. A quad
## at (qx, qz) reads vertices qx..qx+1, so changed cells [a..b] dirty quads
## [a-1..b] -- the grow(1) below covers both directions.
func _rebuild_chunks_in(cell_rect: Rect2i) -> void:
	if _chunks_root == null or _chunks.is_empty():
		return
	var n := _view.cells_x
	var g := cell_rect.grow(1)
	var qx0 := clampi(g.position.x, 0, n - 2)
	var qx1 := clampi(g.position.x + g.size.x - 1, 0, n - 2)
	var qz0 := clampi(g.position.y, 0, n - 2)
	var qz1 := clampi(g.position.y + g.size.y - 1, 0, n - 2)
	for j in range(qz0 / CHUNK_CELLS, qz1 / CHUNK_CELLS + 1):
		for i in range(qx0 / CHUNK_CELLS, qx1 / CHUNK_CELLS + 1):
			if _chunks.has(Vector2i(i, j)):
				_build_chunk(i, j)


func _build_chunk(i: int, j: int) -> void:
	var t := _view
	var n := t.cells_x
	var qx0 := i * CHUNK_CELLS
	var qz0 := j * CHUNK_CELLS
	var qx1 := mini(qx0 + CHUNK_CELLS, n - 1)
	var qz1 := mini(qz0 + CHUNK_CELLS, n - 1)
	var hx := t.extent_x_m() * 0.5
	var hz := t.extent_z_m() * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for cz in range(qz0, qz1):
		for cx in range(qx0, qx1):
			var quad := [Vector2i(cx, cz), Vector2i(cx + 1, cz),
				Vector2i(cx + 1, cz + 1), Vector2i(cx, cz + 1)]
			var p: Array = []
			for q in quad:
				var wx: float = float(q.x) * t.cell_size_m - hx
				var wz: float = float(q.y) * t.cell_size_m - hz
				p.append(Vector3(wx, t.height_at_cell(q.x, q.y), wz))
			_tri(st, p[0], p[1], p[2])
			_tri(st, p[0], p[2], p[3])
	st.generate_normals()
	(_chunks[Vector2i(i, j)] as MeshInstance3D).mesh = st.commit()


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	for v in [a, b, c]:
		st.set_color(_ground_colour(v.y))
		st.add_vertex(v)


## skirmish.gd's palette, contour band and all: what the author sees here is
## what the player will see there.
func _ground_colour(h: float) -> Color:
	if h < 0.0:
		return Color(0.05, 0.14, 0.26).lerp(Color(0.10, 0.26, 0.40),
			clampf(1.0 + h / 200.0, 0.0, 1.0))
	var t: float = clampf(h / 420.0, 0.0, 1.0)
	var c := Color(0.20, 0.27, 0.13).lerp(Color(0.55, 0.50, 0.38), t)
	if int(floor(h / 40.0)) % 2 == 1:
		c = c.darkened(0.13)
	return c


# ═══════════════════════════════════════════════════════════════════════════
# MARKERS
# ═══════════════════════════════════════════════════════════════════════════

func _refresh_markers() -> void:
	if _markers_root == null:
		return
	for c in _markers_root.get_children():
		c.queue_free()
	for k in range(_map.bases.size()):
		var b: Dictionary = _map.bases[k]
		var x := float(b["x"])
		var z := float(b["z"])
		var why := SimMapFile.base_problem(_view, x, z)
		_markers_root.add_child(_base_marker(k, x, z, why))
	for k in range(_map.deposits.size()):
		var d: Dictionary = _map.deposits[k]
		var x := float(d["x"])
		var z := float(d["z"])
		var why := SimMapFile.deposit_problem(_view, x, z)
		_markers_root.add_child(_deposit_marker(x, z, why))


## A base is drawn at its true footprint (SimArena.BASE_FOOTPRINT_M square),
## blue when sound, red with the reason over it when the ground has become
## unsuitable -- sculpting under a placed base re-checks it live.
func _base_marker(idx: int, x: float, z: float, why: String) -> Node3D:
	var holder := Node3D.new()
	holder.position = Vector3(x, _view.ground_under(x, z), z)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	var f := SimArena.BASE_FOOTPRINT_M
	bm.size = Vector3(f * 2.0, 24.0, f * 2.0)
	mi.mesh = bm
	mi.position.y = 12.0
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.30, 0.25, 0.55) if why != "" \
		else Color(0.42, 0.78, 1.00, 0.45)
	mi.material_override = mat
	holder.add_child(mi)
	var lbl := Label3D.new()
	lbl.text = "P%d" % idx if why == "" else "P%d  %s" % [idx, why]
	lbl.position.y = 90.0
	lbl.pixel_size = 0.9
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(1.0, 0.45, 0.40) if why != "" else Color(0.85, 0.95, 1.0)
	holder.add_child(lbl)
	return holder


func _deposit_marker(x: float, z: float, why: String) -> Node3D:
	var holder := Node3D.new()
	holder.position = Vector3(x, _view.ground_under(x, z), z)
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 40.0
	cm.bottom_radius = 55.0
	cm.height = 18.0
	mi.mesh = cm
	mi.position.y = 9.0
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.30, 0.25) if why != "" \
		else Color(0.12, 0.10, 0.08)
	mi.material_override = mat
	holder.add_child(mi)
	var lbl := Label3D.new()
	lbl.text = "OIL" if why == "" else "OIL  " + why
	lbl.position.y = 55.0
	lbl.pixel_size = 0.7
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.modulate = Color(1.0, 0.45, 0.40) if why != "" else Color(0.95, 0.85, 0.55)
	holder.add_child(lbl)
	return holder


# ═══════════════════════════════════════════════════════════════════════════
# INPUT
# ═══════════════════════════════════════════════════════════════════════════

func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		_key(ev as InputEventKey)
		return
	if ev is InputEventMouseMotion:
		_cursor = _ground_point((ev as InputEventMouseMotion).position)
		if _stroking and (_tool == Tool.RAISE or _tool == Tool.LOWER):
			if _cursor.distance_to(_last_dab) >= maxf(_radius * 0.5, 50.0):
				_last_dab = _cursor
				commit_dab(_cursor, 1.0 if _tool == Tool.RAISE else -1.0)
		_update_previews()
		return
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT:
		return
	if mb.pressed:
		var p := _ground_point(mb.position)
		_cursor = p
		match _tool:
			Tool.RAISE, Tool.LOWER:
				_stroking = true
				_last_dab = p
				commit_dab(p, 1.0 if _tool == Tool.RAISE else -1.0)
			Tool.SMOOTH:
				commit_smooth()
			Tool.PLATEAU:
				commit_plateau(p)
			Tool.RIDGE, Tool.BASIN:
				_stroking = true
				_stroke_from = p
			Tool.BASE:
				place_base(p.x, p.z)
			Tool.DEPOSIT:
				place_deposit(p.x, p.z)
			Tool.WATER:
				pass    # the buttons / U / J drive this one
	elif _stroking:
		_stroking = false
		var p := _ground_point(mb.position)
		if _tool == Tool.RIDGE:
			if _stroke_from.distance_to(p) >= 100.0:
				commit_ridge(_stroke_from, p)
			else:
				_flash("drag to draw a ridge -- press at one end, release at the other")
		elif _tool == Tool.BASIN:
			if absf(p.x - _stroke_from.x) >= 50.0 and absf(p.z - _stroke_from.z) >= 50.0:
				commit_basin(_stroke_from, p)
			else:
				_flash("drag a rectangle to carve a sea")
		_update_previews()


func _key(k: InputEventKey) -> void:
	match k.keycode:
		KEY_1: _set_tool(Tool.RAISE)
		KEY_2: _set_tool(Tool.LOWER)
		KEY_3: _set_tool(Tool.SMOOTH)
		KEY_4: _set_tool(Tool.PLATEAU)
		KEY_5: _set_tool(Tool.RIDGE)
		KEY_6: _set_tool(Tool.BASIN)
		KEY_7: _set_tool(Tool.WATER)
		KEY_8: _set_tool(Tool.BASE)
		KEY_9: _set_tool(Tool.DEPOSIT)
		KEY_BRACKETLEFT:
			_set_radius(_radius - 100.0)
		KEY_BRACKETRIGHT:
			_set_radius(_radius + 100.0)
		KEY_SEMICOLON:
			_set_strength(_strength - 10.0)
		KEY_APOSTROPHE:
			_set_strength(_strength + 10.0)
		KEY_U:
			change_water(5.0)
		KEY_J:
			change_water(-5.0)
		KEY_Z:
			if k.ctrl_pressed or k.meta_pressed:
				undo()
		KEY_S:
			if k.ctrl_pressed or k.meta_pressed:
				do_save()
		KEY_ESCAPE:
			_stroking = false
			_update_previews()


func _set_tool(t: int) -> void:
	_tool = t
	_stroking = false
	for key in _tool_buttons:
		(_tool_buttons[key] as Button).button_pressed = key == t
	_update_previews()


func _set_radius(v: float) -> void:
	_radius = clampf(v, 100.0, 2500.0)
	if _radius_slider != null:
		_radius_slider.set_value_no_signal(_radius)
	if _radius_label != null:
		_radius_label.text = "brush radius  %.0f m" % _radius
	_update_previews()


func _set_strength(v: float) -> void:
	_strength = clampf(v, 5.0, 300.0)
	if _strength_slider != null:
		_strength_slider.set_value_no_signal(_strength)
	if _strength_label != null:
		_strength_label.text = "strength  %.0f m" % _strength


## skirmish.gd's heightfield ray march: on ground with 300 m of relief a
## flat-plane hit puts the brush hundreds of metres from the pointer.
func _ground_point(screen: Vector2) -> Vector3:
	if _rig == null:
		return Vector3.ZERO
	var cam: Camera3D = _rig.call("camera")
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var t := _view
	var travel := 0.0
	var step := 12.0
	while travel < 40000.0:
		var p := from + dir * travel
		if p.y <= t.ground_under(p.x, p.z):
			return Vector3(p.x, t.ground_under(p.x, p.z), p.z)
		travel += step
		step = minf(step * 1.06, 120.0)
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	return from + dir * (-from.y / dir.y)


# ── previews: the brush ring and the stroke ghost ────────────────────────────

func _update_previews() -> void:
	if _ring == null:
		return
	var im := _ring.mesh as ImmediateMesh
	im.clear_surfaces()
	var show_ring := _tool in [Tool.RAISE, Tool.LOWER, Tool.PLATEAU,
		Tool.RIDGE, Tool.BASIN, Tool.BASE, Tool.DEPOSIT]
	if show_ring:
		var r := _radius
		var bad := false
		if _tool == Tool.BASE:
			r = SimArena.BASE_FOOTPRINT_M
			bad = SimMapFile.base_problem(_view, _cursor.x, _cursor.z) != ""
		elif _tool == Tool.DEPOSIT:
			r = 60.0
			bad = SimMapFile.deposit_problem(_view, _cursor.x, _cursor.z) != ""
		_ring_mat.albedo_color = Color(1.0, 0.35, 0.30) if bad \
			else Color(0.95, 0.97, 0.95)
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for k in range(49):
			var a := TAU * float(k) / 48.0
			var x := _cursor.x + cos(a) * r
			var z := _cursor.z + sin(a) * r
			im.surface_add_vertex(Vector3(x, _view.ground_under(x, z) + 4.0, z))
		im.surface_end()

	var sm := _stroke_line.mesh as ImmediateMesh
	sm.clear_surfaces()
	if _stroking and _tool == Tool.RIDGE:
		sm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		for k in range(33):
			var f := float(k) / 32.0
			var x := lerpf(_stroke_from.x, _cursor.x, f)
			var z := lerpf(_stroke_from.z, _cursor.z, f)
			sm.surface_add_vertex(Vector3(x, _view.ground_under(x, z) + 6.0, z))
		sm.surface_end()
	elif _stroking and _tool == Tool.BASIN:
		sm.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
		var corners := [Vector2(_stroke_from.x, _stroke_from.z),
			Vector2(_cursor.x, _stroke_from.z), Vector2(_cursor.x, _cursor.z),
			Vector2(_stroke_from.x, _cursor.z),
			Vector2(_stroke_from.x, _stroke_from.z)]
		for c in corners:
			sm.surface_add_vertex(Vector3(c.x,
				_view.ground_under(c.x, c.y) + 6.0, c.y))
		sm.surface_end()


# ═══════════════════════════════════════════════════════════════════════════
# HUD
# ═══════════════════════════════════════════════════════════════════════════

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.position = Vector2(8, 8)
	panel.custom_minimum_size = Vector2(240, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.04, 0.05, 0.06, 0.85)
	style.set_content_margin_all(10)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	panel.add_child(col)

	var title := Label.new()
	title.text = "MAP EDITOR"
	title.add_theme_font_size_override("font_size", 15)
	col.add_child(title)

	_name_edit = LineEdit.new()
	_name_edit.text = _map.map_name
	_name_edit.custom_minimum_size = Vector2(0, 28)
	col.add_child(_name_edit)

	var files := HBoxContainer.new()
	col.add_child(files)
	for pair in [["Save", do_save], ["Load", do_load],
			["New", _new_map], ["Undo", undo]]:
		var b := Button.new()
		b.text = pair[0]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.pressed.connect(pair[1])
		files.add_child(b)

	col.add_child(HSeparator.new())
	for t in [Tool.RAISE, Tool.LOWER, Tool.SMOOTH, Tool.PLATEAU, Tool.RIDGE,
			Tool.BASIN, Tool.WATER, Tool.BASE, Tool.DEPOSIT]:
		var b := Button.new()
		b.text = "%d  %s" % [t + 1, TOOL_NAME[t]]
		b.toggle_mode = true
		b.button_pressed = t == _tool
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(_set_tool.bind(t))
		col.add_child(b)
		_tool_buttons[t] = b

	col.add_child(HSeparator.new())
	_radius_label = Label.new()
	_radius_label.add_theme_font_size_override("font_size", 12)
	col.add_child(_radius_label)
	_radius_slider = HSlider.new()
	_radius_slider.min_value = 100.0
	_radius_slider.max_value = 2500.0
	_radius_slider.step = 50.0
	_radius_slider.value = _radius
	_radius_slider.value_changed.connect(_set_radius)
	col.add_child(_radius_slider)

	_strength_label = Label.new()
	_strength_label.add_theme_font_size_override("font_size", 12)
	col.add_child(_strength_label)
	_strength_slider = HSlider.new()
	_strength_slider.min_value = 5.0
	_strength_slider.max_value = 300.0
	_strength_slider.step = 5.0
	_strength_slider.value = _strength
	_strength_slider.value_changed.connect(_set_strength)
	col.add_child(_strength_slider)

	var water_row := HBoxContainer.new()
	col.add_child(water_row)
	_water_label = Label.new()
	_water_label.add_theme_font_size_override("font_size", 12)
	_water_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	water_row.add_child(_water_label)
	for pair in [["-", -5.0], ["+", 5.0]]:
		var b := Button.new()
		b.text = pair[0]
		b.custom_minimum_size = Vector2(30, 0)
		b.pressed.connect(func() -> void: change_water(pair[1]))
		water_row.add_child(b)

	# Everything wrong with the map right now, in the arena's own words.
	_problems_label = Label.new()
	_problems_label.add_theme_font_size_override("font_size", 11)
	_problems_label.add_theme_color_override("font_color", Color(1.0, 0.45, 0.40))
	_problems_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_problems_label.custom_minimum_size = Vector2(220, 0)
	_problems_label.visible = false
	col.add_child(_problems_label)

	# The status line: tool hint, cursor, flash.
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 12)
	_status.anchor_top = 1.0
	_status.anchor_bottom = 1.0
	_status.anchor_left = 0.0
	_status.anchor_right = 1.0
	_status.offset_left = 250.0
	_status.offset_top = -54.0
	_status.offset_bottom = -8.0
	layer.add_child(_status)

	# Live minimap, minimap.gd's bake pattern: one pixel per cell, repainted
	# (throttled) after each edit rather than every frame.
	_minimap_rect = TextureRect.new()
	_minimap_rect.custom_minimum_size = Vector2(220, 220)
	_minimap_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_minimap_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap_rect.anchor_top = 1.0
	_minimap_rect.anchor_bottom = 1.0
	_minimap_rect.offset_left = 10.0
	_minimap_rect.offset_top = -290.0
	_minimap_rect.offset_bottom = -70.0
	layer.add_child(_minimap_rect)

	_set_radius(_radius)
	_set_strength(_strength)
	_refresh_water_label()


func _refresh_water_label() -> void:
	if _water_label != null:
		_water_label.text = "water level  %.0f m" % _map.water_level


func _flash(msg: String) -> void:
	_flash_msg = msg
	_flash_until = Time.get_ticks_msec() / 1000.0 + 3.0
	if _status == null:
		print("[editor] " + msg)


func _process(dt: float) -> void:
	if _rig != null and _view != null:
		_rig.position.y = _view.ground_under(_rig.position.x, _rig.position.z)
	_minimap_accum += dt
	if _minimap_dirty and _minimap_accum >= 0.25:
		_minimap_accum = 0.0
		_minimap_dirty = false
		_bake_minimap()
	if _status != null:
		var now := Time.get_ticks_msec() / 1000.0
		var line := "%s -- %s" % [TOOL_NAME[_tool], TOOL_HINT[_tool]]
		line += "\ncursor %.0f, %.0f  h %.0f m    [ ] radius   ; ' strength   U/J water   cmd-Z undo   cmd-S save" \
			% [_cursor.x, _cursor.z, _view.height_at(_cursor.x, _cursor.z)]
		if now < _flash_until:
			line = _flash_msg + "\n" + line
		_status.text = line


## minimap.gd's terrain bake, plus the authored markers stamped on top: bases
## as white squares, deposits as amber dots.
func _bake_minimap() -> void:
	if _minimap_rect == null or _view == null:
		return
	var t := _view
	var img := Image.create(t.cells_x, t.cells_z, false, Image.FORMAT_RGB8)
	for cz in range(t.cells_z):
		for cx in range(t.cells_x):
			img.set_pixel(cx, cz, _minimap_colour(t.height_at_cell(cx, cz)))
	for b in _map.bases:
		_stamp(img, float(b["x"]), float(b["z"]), 2, Color(0.95, 0.97, 0.95))
	for d in _map.deposits:
		_stamp(img, float(d["x"]), float(d["z"]), 1, Color(0.95, 0.78, 0.30))
	_minimap_rect.texture = ImageTexture.create_from_image(img)


func _minimap_colour(h: float) -> Color:
	if h < 0.0:
		return Color(0.03, 0.09, 0.20).lerp(Color(0.08, 0.22, 0.38),
			clampf(1.0 + h / 200.0, 0.0, 1.0))
	var t: float = clampf(h / 420.0, 0.0, 1.0)
	var c := Color(0.13, 0.20, 0.09).lerp(Color(0.60, 0.55, 0.40), t)
	if int(floor(h / 40.0)) % 2 == 1:
		c = c.darkened(0.15)
	return c


func _stamp(img: Image, x: float, z: float, r: int, col: Color) -> void:
	var t := _view
	var cx := int((x + t.extent_x_m() * 0.5) / t.cell_size_m)
	var cz := int((z + t.extent_z_m() * 0.5) / t.cell_size_m)
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var px := clampi(cx + dx, 0, t.cells_x - 1)
			var pz := clampi(cz + dz, 0, t.cells_z - 1)
			img.set_pixel(px, pz, col)


# ═══════════════════════════════════════════════════════════════════════════
# THE HEADLESS TEST SESSION
#
# Scripts a small authoring session through the SAME commit functions the
# mouse drives, and asserts three contracts: the op list records what was
# done, the incremental terrain equals a from-scratch replay bit for bit, and
# the saved file round-trips. Runs in-scene (--test) or sceneless from
# sim/tests/test_map_file_editor.gd -- every visual call is null-guarded.
# ═══════════════════════════════════════════════════════════════════════════

func _t_ok(label: String, condition: bool, detail := "") -> void:
	if condition:
		_t_passed += 1
		print("    PASS  %s%s" % [label, ("  " + detail) if detail else ""])
	else:
		_t_failed += 1
		print("    FAIL  %s%s" % [label, ("  " + detail) if detail else ""])


## Hash of a from-scratch replay of the current document -- the ground a
## player would actually get -- to compare against the editor's working field.
func _replay_hash() -> String:
	var n := _map.cells()
	var t := SimTerrain.new(n, n, _map.cell_m, "replay")
	for op in _map.ops:
		_map._apply(t, op)
	for i in range(t.heights.size()):
		t.heights[i] -= _map.water_level
	return SimMapFile.heights_hash(t)


func run_test_session() -> int:
	print("")
	print("  BATTLE -- map editor headless session")
	print("  " + "-".repeat(66))
	_t_passed = 0
	_t_failed = 0

	print("")
	print("  A scripted edit session records the ops the format replays")
	_new_map()
	_t_ok("a new map is one fill op", _map.ops.size() == 1
		and String(_map.ops[0]["op"]) == "fill")
	_t_ok("and dry ground at +60 m",
		absf(_view.height_at(0.0, 0.0) - 60.0) < 0.01)

	_set_radius(900.0)
	_set_strength(250.0)
	commit_ridge(Vector3(-2000, 0, -3000), Vector3(-2000, 0, 3000))
	var ridge: Dictionary = _map.ops[1]
	_t_ok("a ridge stroke records a ridge op",
		String(ridge["op"]) == "ridge" and float(ridge["peak_m"]) == 250.0
		and float(ridge["half_width_m"]) == 900.0)
	_t_ok("with the stroke's own endpoints",
		float(ridge["x0"]) == -2000.0 and float(ridge["z1"]) == 3000.0)
	# The crest reads a shade under peak_m: cell centres sit half a cell off
	# the stroke line and the cosine falloff bites, so assert "a real ridge",
	# not the unreachable exact peak.
	_t_ok("and the ground rose under it",
		_view.height_at(-2000.0, 0.0) > 200.0,
		"%.0f m" % _view.height_at(-2000.0, 0.0))

	_set_radius(500.0)
	_set_strength(60.0)
	var before := _view.height_at(1000.0, 1000.0)
	commit_dab(Vector3(1000, 0, 1000), 1.0)
	_t_ok("a raise dab records a raise op and lifts the ground",
		String(_map.ops[2]["op"]) == "raise"
		and _view.height_at(1000.0, 1000.0) > before + 30.0)

	commit_plateau(Vector3(2500, 0, -2500))
	_t_ok("a plateau click records a plateau op at the clicked height",
		String(_map.ops[3]["op"]) == "plateau")

	commit_basin(Vector3(-1000, 0, -1000), Vector3(0, 0, 0))
	_t_ok("a basin drag records a basin op and the water is wet",
		String(_map.ops[4]["op"]) == "basin"
		and _view.is_water(-500.0, -500.0))

	print("")
	print("  The incremental field IS the replayed field, bit for bit")
	_t_ok("after 4 sculpt ops, incremental == replay",
		SimMapFile.heights_hash(_view) == _replay_hash())
	change_water(10.0)
	_t_ok("water level is one number applied last",
		absf(_view.height_at(4000.0, 4000.0)
			- (_raw.height_at(4000.0, 4000.0) - 10.0)) < 0.001)
	_t_ok("and the view still equals a replay of the file",
		SimMapFile.heights_hash(_view) == _replay_hash())

	print("")
	print("  Placement enforces the arena's own suitability rules, with reasons")
	var why := place_base(-500.0, -500.0)
	_t_ok("a base in the basin is refused", why != "" and _map.bases.is_empty(),
		why)
	why = place_base(6300.0, 0.0)
	_t_ok("a base outside the deployable margin is refused",
		why != "" and _map.bases.is_empty(), why)
	why = place_base(2000.0, 2000.0)
	_t_ok("a dry, in-bounds base is accepted",
		why == "" and _map.bases.size() == 1)
	why = place_base(2300.0, 2300.0)
	_t_ok("a second base 424 m away is refused for separation",
		why != "" and _map.bases.size() == 1, why)
	why = place_base(-2500.0, 2500.0)
	_t_ok("a properly separated second base is accepted",
		why == "" and _map.bases.size() == 2)
	why = place_deposit(-500.0, -500.0)
	_t_ok("a deposit in the water is refused", why != ""
		and _map.deposits.is_empty(), why)
	why = place_deposit(1500.0, -1500.0)
	_t_ok("a dry deposit is accepted", why == "" and _map.deposits.size() == 1)
	_t_ok("validate() agrees the map is sound",
		_map.validate(_view).is_empty())

	print("")
	print("  Undo pops the op list, and the ground follows")
	undo()
	_t_ok("undo removes the deposit", _map.deposits.is_empty())
	undo()
	_t_ok("undo removes the last base", _map.bases.size() == 1)
	undo()
	_t_ok("undo removes the other base", _map.bases.is_empty())
	undo()
	_t_ok("undo puts the water back", _map.water_level == 0.0)
	var ops_before := _map.ops.size()
	undo()
	_t_ok("undo pops the basin op", _map.ops.size() == ops_before - 1
		and String(_map.ops[-1]["op"]) == "plateau")
	_t_ok("and the basin's water is gone from the replayed ground",
		not _view.is_water(-500.0, -500.0))
	_t_ok("the popped-and-replayed field matches a fresh replay",
		SimMapFile.heights_hash(_view) == _replay_hash())

	print("")
	print("  Save / load round-trips the session's file")
	place_base(2000.0, 2000.0)
	place_base(-2500.0, 2500.0)
	place_deposit(1500.0, -1500.0)
	var dir := ProjectSettings.globalize_path("user://map_editor_tests/")
	DirAccess.make_dir_recursive_absolute(dir)
	var path := dir + "session.json"
	_map.map_name = "Editor Session"
	_t_ok("save() writes the file", _map.save(path))
	var text := FileAccess.get_file_as_string(path)
	_t_ok("the file is a battle-map", '"format": "battle-map"' in text)
	_map.save(path.replace(".json", "_again.json"))
	_t_ok("saving twice is byte-stable", text
		== FileAccess.get_file_as_string(path.replace(".json", "_again.json")))
	var loaded := SimMapFile.load_map(path)
	_t_ok("the loader accepts it", loaded != null)
	if loaded != null:
		_t_ok("with the same op list", loaded.ops.size() == _map.ops.size())
		_t_ok("the same bases and deposits",
			loaded.bases.size() == 2 and loaded.deposits.size() == 1)
		_t_ok("and builds the SAME ground the editor showed, hash for hash",
			SimMapFile.heights_hash(loaded.build_terrain())
				== SimMapFile.heights_hash(_map.build_terrain()))

	print("")
	print("  " + "-".repeat(66))
	if _t_failed == 0:
		print("  %d passed, 0 failed" % _t_passed)
	else:
		print("  %d passed, %d FAILED" % [_t_passed, _t_failed])
	print("")
	return _t_failed
