extends Node3D
## Proving ground: verifies that the art pipeline's output actually loads, sits
## at the right scale, keeps its sockets, and can be driven with RTS controls.
## Milestone 1-3 scaffolding from docs/06-architecture.md — not the game.

const ASSETS := "res://assets/units/"

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
	if "--shot" in OS.get_cmdline_user_args():
		_capture()


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
		unit.add_child(packed.instantiate())
		_units.append(unit)


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
				if _drag_from.distance_to(at) < 6.0:
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
		_box.visible = _box.size.length() > 6.0


func _ground_point(screen: Vector2) -> Vector3:
	var cam: Camera3D = _rig.camera()
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	return from + dir * (-from.y / dir.y)


func _clear() -> void:
	for u in _selected:
		u.selected = false
	_selected.clear()


func _pick(screen: Vector2, additive: bool) -> void:
	if not additive:
		_clear()
	var p := _ground_point(screen)
	var best: Node3D = null
	var best_d := 4.5
	for u in _units:
		var d := Vector2(u.position.x - p.x, u.position.z - p.z).length()
		if d < best_d:
			best_d = d
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
		var sp := cam.unproject_position(u.position + Vector3(0, 1.2, 0))
		if r.has_point(sp) and u not in _selected:
			u.selected = true
			_selected.append(u)


func _order(screen: Vector2) -> void:
	if _selected.is_empty():
		return
	var p := _ground_point(screen)
	# spread the formation so units do not stack on one point
	var n := _selected.size()
	var cols := int(ceil(sqrt(float(n))))
	for i in range(n):
		var ox := (i % cols) * 7.0 - (cols - 1) * 3.5
		var oz := float(i / cols) * 7.0
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
