extends Node3D
## Proving ground: verifies that the art pipeline's output actually loads, sits
## at the right scale, keeps its sockets, and can be driven with RTS controls.
## Pre-milestone-1 harness from docs/06-architecture.md — not the game, and
## not yet milestone 1: the deterministic tick loop lives in sim/, not here.

const ASSETS := "res://assets/units/"
const PLAYER_FACTION := 0
const DRAG_THRESHOLD_PX := 11.0

const CAM_ACTIONS := [
	&"cam_forward", &"cam_back", &"cam_left",
	&"cam_right", &"cam_rot_l", &"cam_rot_r",
]

const ROSTER := [
	{"file": "mbt_e4_us_m1_abrams", "label": "M1A2 ABRAMS", "faction": 0, "pos": Vector3(-24, 0, 14)},
	{"file": "mbt_e4_de_leopard2a6", "label": "LEOPARD 2A6", "faction": 0, "pos": Vector3(-8, 0, 14)},
	{"file": "afv_e4_us_ifv", "label": "IFV", "faction": 0, "pos": Vector3(8, 0, 14)},
	{"file": "rec_e4_us_recon", "label": "RECON", "faction": 0, "pos": Vector3(22, 0, 14)},
	{"file": "art_e4_us_sph", "label": "SPH", "faction": 0, "pos": Vector3(-24, 0, -2)},
	{"file": "art_e4_us_mlrs", "label": "MLRS", "faction": 0, "pos": Vector3(-8, 0, -2)},
	{"file": "rad_e4_us_search", "label": "SEARCH RADAR", "faction": 0, "pos": Vector3(8, 0, -2)},
	{"file": "rad_e4_us_illuminator", "label": "ILLUMINATOR", "faction": 0, "pos": Vector3(24, 0, -2)},
	{"file": "sam_e4_us_launcher", "label": "SAM LAUNCHER", "faction": 0, "pos": Vector3(-16, 0, -18)},
	{"file": "log_e4_us_fueltruck", "label": "FUEL TRUCK", "faction": 0, "pos": Vector3(0, 0, -18)},
	{"file": "mbt_e4_ru_t72", "label": "T-72", "faction": 1, "pos": Vector3(18, 0, -18)},
]

var _rig: Node3D
var _units: Array[Node3D] = []
var _selected: Array[Node3D] = []
var _drag_from := Vector2.ZERO
var _dragging := false
var _hud: Label
var _box: ColorRect
var _report: Array[String] = []


func _ready() -> void:
	_build_world()
	_spawn_roster()
	_build_hud()
	_run_self_test()
	var argv := OS.get_cmdline_user_args()
	# --test runs the checks and leaves. --shot additionally saves a framing
	# render, which needs a real framebuffer: headless has none, so _capture()
	# awaits a frame_post_draw that never arrives and the process hangs with
	# its stdout still buffered — which made the self-test unreadable in CI
	# even though it had already run and printed.
	if "--shot" in argv and DisplayServer.get_name() != "headless":
		_capture()
	elif "--shot" in argv or "--test" in argv:
		if "--shot" in argv:
			print("(headless: skipping the framing render, no framebuffer)")
		get_tree().quit(1 if _report.any(func(l): return l.begins_with("FAIL")) else 0)


func _capture() -> void:
	# frame the whole roster, let a few frames settle, then save and quit
	_rig.position = Vector3(0, 0, -2)
	_rig.set("_dist", 96.0)
	_rig.call("_apply")
	for u in _units:
		u.selected = true
		_selected.append(u)
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	# resolve relative to the project, not to one machine's home directory
	var out := ProjectSettings.globalize_path("res://../art/renders/game_proving_ground.png")
	var err := img.save_png(out)
	print("[shot] ", out, "  err=", err, "  ", img.get_width(), "x", img.get_height())
	get_tree().quit()


func _build_world() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	sky.sky_material = ProceduralSkyMaterial.new()
	e.sky = sky
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 0.55
	e.ssao_enabled = true
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-46, 140, 0)
	sun.light_energy = 2.4
	sun.shadow_enabled = true
	add_child(sun)

	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(400, 400)
	ground.mesh = pm
	var gm := StandardMaterial3D.new()
	gm.albedo_color = Color(0.30, 0.32, 0.24)
	gm.roughness = 0.98
	ground.material_override = gm
	add_child(ground)

	# 10 m grid so scale is verifiable by eye, not only by assertion
	var grid := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	grid.mesh = im
	var lm := StandardMaterial3D.new()
	lm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lm.albedo_color = Color(1, 1, 1, 0.10)
	lm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	grid.material_override = lm
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for i in range(-20, 21):
		im.surface_add_vertex(Vector3(i * 10, 0.02, -200))
		im.surface_add_vertex(Vector3(i * 10, 0.02, 200))
		im.surface_add_vertex(Vector3(-200, 0.02, i * 10))
		im.surface_add_vertex(Vector3(200, 0.02, i * 10))
	im.surface_end()
	add_child(grid)

	# 1.8 m reference figure — the scale check docs/07 asks for
	var ref := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.30
	cap.height = 1.80
	ref.mesh = cap
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Color(0.90, 0.25, 0.15)
	ref.material_override = rm
	ref.position = Vector3(-34, 0.90, 14)
	add_child(ref)

	_rig = preload("res://scripts/rts_camera.gd").new()
	add_child(_rig)


func _spawn_roster() -> void:
	for entry in ROSTER:
		var path: String = ASSETS + entry.file + "_LOD0.glb"
		if not ResourceLoader.exists(path):
			_report.append("MISSING  " + entry.file)
			continue
		var packed := load(path) as PackedScene
		if packed == null:
			_report.append("LOADFAIL " + entry.file)
			continue
		var unit := preload("res://scripts/unit.gd").new()
		unit.position = entry.pos
		unit.unit_name = entry.label
		unit.faction = entry.faction
		unit.name = entry.file
		add_child(unit)
		var model := packed.instantiate()
		unit.add_child(model)
		# Cache the model's real bounds once. Selection, the ring and formation
		# spacing all read it, so none of them has to guess a radius.
		unit.set_footprint(_local_aabb(unit))
		_units.append(unit)


## Model bounds expressed in the unit's own local space.
func _local_aabb(unit: Node3D) -> AABB:
	var box := AABB()
	var first := true
	var to_local := unit.global_transform.affine_inverse()
	for c in unit.find_children("*", "MeshInstance3D", true, false):
		var mi := c as MeshInstance3D
		var a: AABB = (to_local * mi.global_transform) * mi.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	if first:
		return AABB(Vector3(-3, 0, -3), Vector3(6, 2.5, 6))
	return box


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(14, 10)
	_hud.add_theme_font_size_override("font_size", 13)
	_hud.add_theme_color_override("font_color", Color(0.92, 0.94, 0.90))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)
	_box = ColorRect.new()
	_box.color = Color(0.35, 0.85, 0.45, 0.16)
	_box.visible = false
	layer.add_child(_box)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		var at: Vector2 = mb.position
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_drag_from = at
				_dragging = true
			else:
				_dragging = false
				_box.visible = false
				# 6 px was about 1.1 mm on a 265 DPI panel: an ordinary click with a
				# steady hand became a marquee that cleared the selection.
				if _drag_from.distance_to(at) < DRAG_THRESHOLD_PX:
					_pick(at, Input.is_key_pressed(KEY_SHIFT))
				else:
					_box_select(_drag_from, at, Input.is_key_pressed(KEY_SHIFT))
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_order(at)
	elif e is InputEventMouseMotion and _dragging:
		var a: Vector2 = _drag_from
		var b: Vector2 = (e as InputEventMouseMotion).position
		_box.position = Vector2(minf(a.x, b.x), minf(a.y, b.y))
		_box.size = (b - a).abs()
		_box.visible = _box.size.length() > DRAG_THRESHOLD_PX


func _ground_point(screen: Vector2) -> Vector3:
	var cam: Camera3D = _rig.camera()
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	return from + dir * (-from.y / dir.y)


## The player commands their own force. Without this the enemy T-72 could be
## box-selected and driven around, which it could.
func _selectable(u: Node3D) -> bool:
	return u.faction == PLAYER_FACTION


func _clear() -> void:
	for u in _selected:
		u.selected = false
	_selected.clear()


func _pick(screen: Vector2, additive: bool) -> void:
	if not additive:
		_clear()
	var cam: Camera3D = _rig.camera()
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	var best: Node3D = null
	var best_d := INF
	for u in _units:
		if not _selectable(u):
			continue
		var d: float = u.ray_distance(from, dir)
		if d >= 0.0 and d < best_d:
			best_d = d
			best = u
	if best == null:
		# Nothing under the cursor: fall back to the nearest hull to the ground
		# point, so a click just off a vehicle still does the obvious thing.
		var p := _ground_point(screen)
		var near := 6.0
		for u in _units:
			if not _selectable(u):
				continue
			var c: Vector3 = u.marker_point()
			var d := Vector2(c.x - p.x, c.z - p.z).length()
			if d < near:
				near = d
				best = u
	if best:
		best.selected = true
		if best not in _selected:
			_selected.append(best)


func _box_select(a: Vector2, b: Vector2, additive: bool) -> void:
	if not additive:
		_clear()
	var r := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
	var cam: Camera3D = _rig.camera()
	for u in _units:
		if not _selectable(u):
			continue
		var mp: Vector3 = u.marker_point()
		# unproject_position mirrors points behind the camera onto the screen,
		# so without this guard a marquee selects things behind you.
		if cam.is_position_behind(mp):
			continue
		var sp := cam.unproject_position(mp)
		if r.has_point(sp) and u not in _selected:
			u.selected = true
			_selected.append(u)


func _order(screen: Vector2) -> void:
	if _selected.is_empty():
		return
	var p := _ground_point(screen)
	var n := _selected.size()
	var cols := int(ceil(sqrt(float(n))))
	var rows := int(ceil(float(n) / float(cols)))
	# Pitch from the largest thing actually selected, not a fixed 7 m. The SPH
	# is 12.2 m long, so a 7 m grid parked it inside its neighbours.
	var widest := 0.0
	var longest := 0.0
	for u in _selected:
		var fs: Vector3 = u.footprint_size
		widest = maxf(widest, fs.x)
		longest = maxf(longest, fs.z)
	var pitch_x: float = widest + 3.0
	var pitch_z: float = longest + 3.0
	for i in range(n):
		# BOTH axes centred on the click. Only ox was, so the group's centre of
		# mass landed 6.4 m past where the player pointed.
		var ox := (i % cols) * pitch_x - (cols - 1) * pitch_x * 0.5
		var oz := float(i / cols) * pitch_z - (rows - 1) * pitch_z * 0.5
		_selected[i].order_move(p + Vector3(ox, 0, oz))


func _run_self_test() -> void:
	_report.append("units spawned      %d / %d" % [_units.size(), ROSTER.size()])
	var socket_fail := 0
	var scale_fail := 0
	for u in _units:
		var aabb := _aabb_of(u)
		var L: float = maxf(aabb.size.x, aabb.size.z)
		var H: float = aabb.size.y
		if L < 3.0 or L > 16.0 or H < 1.0 or H > 6.0:
			_report.append("SCALE?   %s  %.1f x %.1f m" % [u.unit_name, L, H])
			scale_fail += 1
		var sc := _count_sockets(u)
		if sc < 9:
			_report.append("SOCKETS  %s only %d" % [u.unit_name, sc])
			socket_fail += 1
	_report.append("scale in range     %d / %d" % [_units.size() - scale_fail, _units.size()])
	_report.append("sockets >= 9       %d / %d" % [_units.size() - socket_fail, _units.size()])
	_check_input_map()
	for line in _report:
		print("[selftest] ", line)


func _check_input_map() -> void:
	## A malformed [input] block in project.godot parses without error but binds
	## nothing, so the keyboard dies silently. Fail loudly instead.
	var unbound := PackedStringArray()
	for a in CAM_ACTIONS:
		if not InputMap.has_action(a) or InputMap.action_get_events(a).is_empty():
			unbound.append(a)
	if unbound.is_empty():
		_report.append("input map          %d / %d actions bound" % [CAM_ACTIONS.size(), CAM_ACTIONS.size()])
	else:
		var msg := "INPUT MAP BROKEN   unbound: " + ", ".join(unbound)
		_report.append(msg)
		push_error(msg)


func _aabb_of(n: Node) -> AABB:
	var box := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var m := c as MeshInstance3D
		var a: AABB = m.global_transform * m.get_aabb()
		if first:
			box = a
			first = false
		else:
			box = box.merge(a)
	return box


func _count_sockets(n: Node) -> int:
	return n.find_children("SOCKET_*", "", true, false).size()


func _process(_dt: float) -> void:
	var lines := PackedStringArray()
	lines.append("BATTLE — proving ground")
	lines.append("")
	lines.append("WASD / screen edge : pan      Q E : rotate      wheel : zoom")
	lines.append("LMB : select    drag : box-select    shift : add    RMB : move order")
	lines.append("")
	lines.append("selected %d / %d      zoom %.0f m      %d fps"
		% [_selected.size(), _units.size(), _rig.zoom_distance(), Engine.get_frames_per_second()])
	if not _selected.is_empty():
		var names := PackedStringArray()
		for u in _selected:
			names.append(u.unit_name)
		lines.append("  " + ", ".join(names))
	lines.append("")
	for line in _report:
		lines.append(line)
	_hud.text = "\n".join(lines)
