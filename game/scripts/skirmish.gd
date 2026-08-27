extends Node3D
## THE GAME. A playable skirmish over SimMatch.
##
## The proving ground is an art harness that owns its own units and moves them
## itself. This is the opposite: it owns NOTHING. Every unit here is an index
## into SimEntities, every order is a SimCommandQueue command, and every rule --
## what may be built, what may be shot, who has won -- is answered by the sim.
## This file reads the simulation and draws it, and that is the whole job. If a
## decision is being made in this file, it is in the wrong place.
##
## ── THE ONE THING THAT MAKES THIS GAME DIFFERENT ─────────────────────────────
## Your own units are drawn from GROUND TRUTH. The enemy is drawn from your
## COALITION'S TRACK TABLE and nothing else -- docs/02's picture, rendered.
## There is no code path in this file that can read an enemy entity, so a
## contact you hold at TQ1 is a bearing on your screen because it is a bearing
## in the simulation, and the enemy tank sitting behind the ridge is not drawn
## because you genuinely do not know it is there. The AI plays under exactly the
## same restriction (docs/09), which is what makes it a fair fight.

const RTS_CAMERA := preload("res://scripts/rts_camera.gd")
const ASSETS := "res://assets/units/"
const DRAG_THRESHOLD_PX := 11.0
## How near the cursor has to be to a contact marker to mean "that one".
const TRACK_PICK_PX := 26.0

# ── palette ──────────────────────────────────────────────────────────────────
## Hillshade sun, matching the DirectionalLight3D's azimuth 136 / elevation 48
## so the painted relief and the lit models agree about where the sun is.
const SUN_DIR := Vector3(0.465, 0.743, -0.481)
## How much to exaggerate the terrain gradient before shading it. The relief
## is real but gentle -- 340 m over 12.8 km -- and at 1.0 the hillshade is as
## invisible as the gradient it is meant to reveal.
const RELIEF_GAIN := 9.0

const COL_OWN := Color(0.42, 0.78, 1.00)
const COL_ALLY := Color(0.45, 0.95, 0.60)
const COL_SELECTED := Color(1.00, 0.95, 0.35)
const COL_HOSTILE := Color(1.00, 0.36, 0.30)
const COL_UNKNOWN := Color(0.95, 0.78, 0.30)
## An emitting hostile close to our force: our ESM is being painted. Hotter
## than plain hostile red so the tint reads as "this one is looking at you".
const COL_ILLUM := Color(1.00, 0.58, 0.10)
const COL_EMIT_RING := Color(1.00, 0.85, 0.25)
const COL_SILENT_DOT := Color(0.45, 0.55, 0.62, 0.85)
const COL_BAR_BG := Color(0.05, 0.05, 0.05, 0.75)
## The side bar. Was 0.82 alpha over a pale map, which let the terrain show
## through the build list and made every icon fight its own background.
const COL_PANEL := Color(0.055, 0.075, 0.095, 0.96)
## RA2's side bar is FRAMED. A lit inner edge is what separates a panel from
## a dark patch of ground behind it.
const COL_PANEL_EDGE := Color(0.42, 0.62, 0.76, 0.85)
const COL_PLATE := Color(0.03, 0.05, 0.07, 0.80)
const COL_PLATE_EDGE := Color(0.34, 0.52, 0.64, 0.50)
## Supply reach, painted on the ground -- the circle docs/04 reasons with.
const COL_SUPPLY := Color(0.55, 0.88, 0.50, 0.75)
## A full fuel tank. Distinct from the health greens so the two bars never
## read as one stat.
const COL_FUEL := Color(0.55, 0.75, 0.95)
## Below this fraction of tank the fuel bar goes amber. The sim's own RTB
## notion is combat_radius_m = 0.35 * range_remaining (get there, fight, get
## back); a quarter tank is the point where that math says "go home now".
## Presentation threshold only -- the sim never reads it.
const FUEL_RESERVE_FRAC := 0.25

# ── the simulation ───────────────────────────────────────────────────────────
const GameAudioScript := preload("res://scripts/audio.gd")
const GameMusicScript := preload("res://scripts/music.gd")
const MinimapScript := preload("res://scripts/minimap.gd")

var _match: SimMatch
var _audio: Node3D
var _music: Node
var _music_kills := 0
var _seen_impacts := 0
var _seen_kills := 0
var _seen_shots := 0
## Control groups. Ctrl+N assigns the selection, N recalls it, N twice in
## quick succession centres the camera on it -- the Red Alert convention, and
## the reason a player can fight on two fronts without a minimap click.
var _groups: Dictionary = {}
var _flash_msg := ""
var _flash_until := 0.0
## Which tab of the production panel is showing.
var _tab := "BUILDING"
var _tab_bar: HBoxContainer
var _last_group := -1
var _last_group_t := -9.0
var _me: int = 0
var _my_team: int = 0

# ── presentation ─────────────────────────────────────────────────────────────
var _rig: Node3D
var _proxies: Dictionary = {}          ## entity index -> Node3D
var _terrain_mesh: MeshInstance3D
## Per-cell hillshade, built once with the mesh.
var _shade := PackedFloat32Array()
var _selected: Array[int] = []
var _drag_from := Vector2.ZERO
var _dragging := false
var _paused := false
var _speed := 1.0

## Build placement. When non-empty the next left click tries to place it.
var _placing_role := ""
var _placing_problem := ""
var _cursor_ground := Vector3.ZERO

## Attack-move. A arms it; the next left click sends the selection there at
## combat power, engaging what appears. Holding A while clicking works too.
var _attack_move_armed := false
## T arms a patrol order the same way A arms attack-move. For ground and
## naval units the clicked point closes a loop with where they stand; for
## aircraft it is a standing SORTIE_PATROL the airbase keeps cycling.
var _patrol_armed := false

## Screen positions of the contacts we can currently see, rebuilt every frame
## so a right-click can be tested against them without a second projection.
var _track_screen: Array = []          ## Array[{"id": int, "at": Vector2, ...}]

## Picture MEMORY, presentation-side only: what the table said last frame, so
## a change in the table -- a new contact, a lost one, a rung climbed -- can be
## voiced and flashed. The sim keeps no such history because the sim does not
## care; the player's ear does.
var _known_tracks: Dictionary = {}     ## track id -> quality last frame
var _track_flash: Dictionary = {}      ## track id -> when it appeared/upgraded (s)
var _illuminating: Dictionary = {}     ## track id -> true while it paints us
var _picture_primed := false           ## first frame seeds memory silently
var _cue_contact_t := -10.0
var _cue_lost_t := -10.0
var _cue_rwr_t := -10.0

## An emitting hostile inside this range of any own unit trips the RWR: close
## enough that its radar almost certainly holds us, far enough to react.
const ILLUM_WARN_M := 6000.0

# ── HUD ──────────────────────────────────────────────────────────────────────
var _overlay: Control
var _stats: Label
var _selection_info: Label
var _log_label: Label
var _banner: Label
var _build_box: VBoxContainer
var _produce_box: VBoxContainer
var _minimap: Control
var _headless := false
## Economy visibility: the amber refine-bottleneck line, the red capitulation
## countdown, and the production-queue readout on the side panel.
var _bottleneck_label: Label
var _power_label: Label
var _ore_nodes: Array = []
var _repair_btn: Button
var _sell_btn: Button
var _collapse_label: Label
var _queue_label: Label
var _queue_bar: ProgressBar


# ═══════════════════════════════════════════════════════════════════════════
# BOOT
# ═══════════════════════════════════════════════════════════════════════════

func _ready() -> void:
	_headless = DisplayServer.get_name() == "headless"
	_match = SimMatch.start(_default_setup(), SimArena.SKIRMISH_VALLEY)
	if _match.phase == SimMatch.Phase.SETUP:
		push_error("match setup invalid: " + ", ".join(_match.problems()))
		return
	_me = _match.human_player_id
	_my_team = (_match.setup.players[_me] as SimPlayerSetup).team

	_build_environment()
	_build_terrain_mesh()
	_build_oil_markers()
	_build_ore_markers()
	_audio = GameAudioScript.new()
	add_child(_audio)
	if not _headless:
		_music = GameMusicScript.new()
		add_child(_music)
	_build_hud()
	_sync_proxies()
	_frame_on_base()

	var argv := OS.get_cmdline_user_args()
	if "--test" in argv:
		_run_headless_check()
	elif "--shot" in argv and not _headless:
		_capture()


## Save a framing render, so the HUD can be reviewed without a human at the
## keyboard. Needs a real framebuffer: headless has none, and awaiting a
## frame_post_draw that never arrives hangs the process with its stdout still
## buffered -- the exact failure the proving ground documents.
func _capture() -> void:
	# `--shot --at 300` runs the match forward 300 simulated seconds first and
	# sends the army at the enemy, so the render shows contacts, damage bars
	# and a live combat log rather than an untouched opening position.
	var argv := OS.get_cmdline_user_args()
	var at_s := 0.0
	var i := argv.find("--at")
	if i >= 0 and i + 1 < argv.size():
		at_s = float(argv[i + 1])
	if at_s > 0.0:
		var enemy := _match.base_position(1 - _me)
		var force := PackedInt32Array()
		for u in _match.own_units(_me):
			if _match.world.entities.is_structure[u] == 0:
				force.append(u)
		var slots := _match.world.movement.formation_slots(force, enemy.x, enemy.y)
		for k in range(force.size()):
			_match.world.commands.move(_me, force[k], slots[k * 2], slots[k * 2 + 1])
		_match.run_ticks(int(at_s * SimWorld.SIM_HZ))
		for u in _match.own_units(_me):
			if _match.world.entities.is_structure[u] == 0 and not _selected.has(u):
				_selected.append(u)
	_match.run_ticks(400)
	_frame_on_base()
	# `--shot --oil` puts the camera over the nearest oil field instead of the
	# base, which is the only way to review how the ground reads where the
	# economy actually lives.
	if "--oil" in argv or "--ore" in argv:
		var econ := _match.world.economy
		var pts: Array = econ.ore_fields if "--ore" in argv else econ.oil_fields
		if not pts.is_empty():
			var home := _match.base_position(_me)
			var best: Vector2 = pts[0]
			var bd := 1.0e18
			for f in pts:
				var d: float = (f - home).length()
				if d < bd:
					bd = d
					best = f
			_rig.position = Vector3(best.x,
				_match.terrain.ground_under(best.x, best.y), best.y)
	if at_s > 0.0 and not _selected.is_empty():
		# Follow the army rather than the empty back yard it left behind.
		var e := _match.world.entities
		var cx := 0.0
		var cz := 0.0
		for u in _selected:
			cx += e.pos_x[u]
			cz += e.pos_z[u]
		cx /= float(_selected.size())
		cz /= float(_selected.size())
		_rig.position = Vector3(cx, _match.terrain.ground_under(cx, cz), cz)
	# The render shows the game at the zoom it is PLAYED at, not a wider survey
	# framing -- a screenshot taken further out than the player ever sits is the
	# reason a scale problem can survive a review.
	_rig.set("_dist", _rig.get("zoom_start"))
	_rig.call("_apply")
	for unit in _match.own_units(_me):
		if _match.world.entities.is_structure[unit] == 0:
			_selected.append(unit)
	_sync_proxies()
	_project_tracks()
	_refresh_panels(true)
	_update_hud()
	_overlay.queue_redraw()
	await RenderingServer.frame_post_draw
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var out := ProjectSettings.globalize_path("res://../art/renders/game_skirmish.png")
	print("[shot] ", out, "  err=", img.save_png(out),
		"  ", img.get_width(), "x", img.get_height())
	get_tree().quit()


## Two players, corner to corner, epoch 4. This is the default skirmish; a
## setup screen would replace this one function and nothing else, because
## SimMatch.start() already takes any SimMatchSetup -- including every docs/09
## §4 scenario in SimMatchSetup.SCENARIOS.
func _default_setup() -> SimMatchSetup:
	var s := SimMatchSetup.new()
	s.name = "Skirmish"
	s.seed_value = 20260826
	s.add(SimPlayerSetup.new({
		"name": "You", "is_human": true, "team": 0,
		"faction": SimPlayerSetup.Faction.US,
		"start_epoch": 4, "ceiling_epoch": 6,
		"starting_forces": SimPlayerSetup.ForcePreset.ARMY}))
	s.add(SimPlayerSetup.new({
		"name": "Russia", "team": 1,
		"faction": SimPlayerSetup.Faction.RUSSIA,
		"start_epoch": 4, "ceiling_epoch": 6,
		"starting_forces": SimPlayerSetup.ForcePreset.ARMY,
		"skill": SimSkill.Level.VETERAN}))
	return s


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
	e.ambient_light_energy = 0.26
	e.fog_enabled = true
	# Fog was 0.00009 with a bright grey-blue light colour, which over a
	# 12.8 km map at the far zoom stop laid a pale wash across everything and
	# flattened the ground to a single tone. Halved, and tinted toward the
	# terrain rather than toward the sky, so distance still reads as distance
	# without bleaching the near field.
	e.fog_density = 0.000042
	e.fog_light_color = Color(0.50, 0.54, 0.55)

	# Contrast and saturation, explicitly. Ambient sky light plus a low sun
	# over gentle relief lands everything in the middle of the range, and a
	# picture with no blacks and no whites reads as haze however much detail
	# is actually in it. This is the cheapest fix for "the map has no detail"
	# that does not involve inventing detail.
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.24
	e.adjustment_saturation = 1.06
	e.adjustment_brightness = 1.02
	env.environment = e
	add_child(env)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, 136, 0)
	sun.light_energy = 2.0
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 900.0
	add_child(sun)

	var t := _match.terrain
	_rig = RTS_CAMERA.new()
	# THE SCALE THE GAME IS PLAYED AT. Ground width on screen is ~1.58x the zoom
	# distance (48 deg FOV, 16:9), so these three numbers are, in metres of
	# ground visible across the middle of the screen:
	#
	#   zoom_min    45 ->    71 m   a 9 m tank is 200 px: inspect one vehicle
	#   zoom_start 260 ->   411 m   a 9 m tank is 35 px: the RTS working view
	#   zoom_max  2400 ->  3799 m   59% of the 6.4 km map, 1.5x the base-to-base
	#
	# 260 is measured, not taste: the starting base spans 405 m corner to corner
	# (furthest structure 202 m from the base centre), so 411 m of screen is the
	# tightest view that still frames the whole base. The starting force also
	# includes recon out at 1540 m, and deliberately does NOT fit -- framing that
	# too would need zoom 1946 and put a tank back at 22 px. Forward scouts
	# belong on the minimap; the main view belongs to the base and the fight.
	#
	# zoom_start is the number that was actually wrong. The far stop was already
	# generous -- at 3799 m a player sees more of this map than the reference RTS
	# shows of its own -- but the game OPENED at 420 m of zoom, which is 665 m of
	# ground and puts a tank at 17 px. That is what "the map is too big to the
	# models" describes: not a map that is too wide, but a view that starts too
	# far out to see what is on it. The models are built at real published
	# dimensions and the sim reasons in real metres, so the view is the only
	# honest place to fix it.
	_rig.set("zoom_min", 45.0)
	_rig.set("zoom_start", 260.0)
	_rig.set("zoom_max", 2400.0)
	_rig.set("pan_speed", 260.0)
	_rig.set("bounds_m", minf(t.extent_x_m(), t.extent_z_m()) * 0.5)
	add_child(_rig)


## The heightfield, as a mesh. One vertex per terrain cell -- the same grid the
## path planner and the line-of-sight walk use, so what you see is the ground
## the simulation is actually reasoning about, not a decorative approximation.
func _build_terrain_mesh() -> void:
	var t := _match.terrain
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var hx := t.extent_x_m() * 0.5
	var hz := t.extent_z_m() * 0.5
	# Per-vertex HILLSHADE, computed once and cached. This is the single thing
	# that was missing: the map was a height gradient with contour bands, and
	# on 340 m of relief spread over 12.8 km every band came out the same
	# colour to within a few percent, so the ground rendered as a flat sage
	# wash with no readable shape at all. The sun cannot rescue it either --
	# the slopes are so gentle that direct lighting varies by almost nothing.
	#
	# A hillshade is the cartographer's answer and it is cheap: light the
	# terrain's own GRADIENT from a fixed low sun, which exaggerates relief
	# rather than reproducing it. Ridges get a lit face and a shadowed one, so
	# you can see which way the ground falls -- which in this game is not
	# decoration, because the ground decides what your radar can see.
	_shade = PackedFloat32Array()
	_shade.resize(t.cells_x * t.cells_z)
	var inv := 1.0 / (2.0 * t.cell_size_m)
	for cz in range(t.cells_z):
		for cx in range(t.cells_x):
			var x0: int = maxi(cx - 1, 0)
			var x1: int = mini(cx + 1, t.cells_x - 1)
			var z0: int = maxi(cz - 1, 0)
			var z1: int = mini(cz + 1, t.cells_z - 1)
			var dhdx: float = (t.height_at_cell(x1, cz)
					- t.height_at_cell(x0, cz)) * inv
			var dhdz: float = (t.height_at_cell(cx, z1)
					- t.height_at_cell(cx, z0)) * inv
			# RELIEF_GAIN exaggerates the gradient. At 1.0 a 3 % slope is a
			# 3 % slope and invisible; at 9.0 it is a face you can read.
			var n := Vector3(-dhdx * RELIEF_GAIN, 1.0,
					-dhdz * RELIEF_GAIN).normalized()
			_shade[cz * t.cells_x + cx] = clampf(n.dot(SUN_DIR), 0.0, 1.0)

	for cz in range(t.cells_z - 1):
		for cx in range(t.cells_x - 1):
			var quad := [Vector2i(cx, cz), Vector2i(cx + 1, cz),
				Vector2i(cx + 1, cz + 1), Vector2i(cx, cz + 1)]
			var p: Array = []
			for q in quad:
				var wx: float = float(q.x) * t.cell_size_m - hx
				var wz: float = float(q.y) * t.cell_size_m - hz
				p.append(Vector3(wx, t.height_at_cell(q.x, q.y), wz))
			_tri(st, p[0], p[1], p[2], quad)
			_tri(st, p[0], p[2], p[3], [quad[0], quad[2], quad[3]])
	st.generate_normals()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	# GROUND DETAIL. The hillshade below fixed the SHAPE of the terrain; this
	# fixes its SURFACE. Cells are 100 m across, so vertex colour alone is a
	# gradient with nothing in it above 100 m -- correct in the large, and at
	# any zoom a player actually uses it reads as smooth painted plastic.
	#
	# A tiling value-noise texture in triplanar world space gives the ground
	# grain at metres rather than hectometres, and MULTIPLIES the vertex
	# colour, so the hillshade, the contour banding and the water all survive
	# underneath it. Triplanar because the mesh carries no UVs: it is built
	# from a heightfield, and projecting from world position needs none.
	mat.albedo_texture = _ground_detail()
	mat.uv1_triplanar = true
	mat.uv1_scale = Vector3(0.11, 0.11, 0.11)   # ~9 m per tile
	# The palette below is written in sRGB, the way a colour picker gives it.
	# Left as linear it renders about two stops brighter and the whole map
	# comes out a pale sage that hides every contour on it.
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.96
	_terrain_mesh = MeshInstance3D.new()
	_terrain_mesh.mesh = st.commit()
	_terrain_mesh.material_override = mat
	add_child(_terrain_mesh)


## A tiling grain for the ground, built once at load.
##
## Deterministic by construction -- a fixed seed and integer hashing, no RNG
## draws -- because two players on the same map should see the same ground,
## and because anything that reaches for randomness at load time is one more
## thing that can desync a replay.
##
## Kept close to white (0.86-1.12) and very slightly warm: this multiplies the
## terrain palette, so a texture with colour of its own would tint the whole
## map rather than texture it.
func _ground_detail() -> ImageTexture:
	const N := 256
	var img := Image.create(N, N, true, Image.FORMAT_RGB8)
	for y in range(N):
		for x in range(N):
			var v := 0.0
			var amp := 1.0
			var total := 0.0
			# Four octaves of value noise, each wrapping on N so the tile has
			# no seam. Wrapping is why the lattice period divides N.
			for oct in [8, 16, 32, 96]:
				v += _value_noise(x, y, oct, N) * amp
				total += amp
				amp *= 0.55
			v = v / total
			# Darkens only. 8-bit cannot store above 1.0, so a range that
			# straddled white threw half its variation away as clipping.
			var g: float = 0.74 + 0.26 * v
			img.set_pixel(x, y, Color(g * 1.02, g, g * 0.94))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Value noise on a lattice of `period` cells across `n` pixels, with smooth
## interpolation and wrap-around, so the result tiles.
func _value_noise(x: int, y: int, period: int, n: int) -> float:
	var step: float = float(n) / float(period)
	var fx: float = float(x) / step
	var fy: float = float(y) / step
	var x0 := int(floor(fx))
	var y0 := int(floor(fy))
	var tx: float = fx - float(x0)
	var ty: float = fy - float(y0)
	tx = tx * tx * (3.0 - 2.0 * tx)
	ty = ty * ty * (3.0 - 2.0 * ty)
	var a := _lattice(x0, y0, period)
	var b := _lattice(x0 + 1, y0, period)
	var c := _lattice(x0, y0 + 1, period)
	var d := _lattice(x0 + 1, y0 + 1, period)
	return lerpf(lerpf(a, b, tx), lerpf(c, d, tx), ty)


func _lattice(x: int, y: int, period: int) -> float:
	var h: int = (posmod(x, period) * 73856093) ^ (posmod(y, period) * 19349663) ^ 0x5f3759
	h = (h ^ (h >> 13)) * 1274126177
	return float((h ^ (h >> 16)) & 0xFFFF) / 65535.0


## OIL FIELDS on the ground. A resource a player cannot SEE is not a resource
## -- it is a rule they have to be told about. Drawn as a low dark slick with
## a derrick-height marker so it reads from the playing camera without being
## mistaken for a unit.
## ORE on the ground: the gold a harvester drives to. Red Alert makes ore
## unmistakable and slightly gaudy on purpose, because it is the thing a player
## navigates their whole economy around.
func _build_ore_markers() -> void:
	var econ := _match.world.economy
	_ore_nodes.clear()
	for k in range(econ.ore_fields.size()):
		var f: Vector2 = econ.ore_fields[k]
		var y := _match.terrain.ground_under(f.x, f.y)
		var node := Node3D.new()
		node.position = Vector3(f.x, y, f.y)
		add_child(node)
		# A scatter of shards rather than one disc: it reads as a deposit, and
		# it lets the field visibly THIN OUT as it is worked.
		# PHYLLOTAXIS, properly: angle by the golden ANGLE and radius by
		# sqrt(j/n) fills a disc evenly. The first attempt took the fractional
		# part of j*0.618 for the radius as well, which is the same sequence
		# used twice -- radius and angle marched together and drew a sparse
		# spiral ring with a hole in the middle instead of a deposit.
		var n := 72
		for j in range(n):
			var a: float = float(j) * 2.399963
			var r: float = 74.0 * sqrt(float(j) / float(n))
			var shard := MeshInstance3D.new()
			var box := BoxMesh.new()
			var s: float = 2.2 + fposmod(float(j) * 0.371, 1.0) * 3.0
			box.size = Vector3(s, s * 1.5, s)
			shard.mesh = box
			var m := StandardMaterial3D.new()
			m.albedo_color = Color(0.82, 0.63, 0.16)
			m.metallic = 0.55
			m.roughness = 0.38
			m.emission_enabled = true
			m.emission = Color(0.62, 0.44, 0.08)
			m.emission_energy_multiplier = 0.15
			shard.material_override = m
			shard.position = Vector3(cos(a) * r, s * 0.4, sin(a) * r)
			shard.rotation.y = a
			node.add_child(shard)
		_ore_nodes.append(node)


## Thin the shards as the field is worked, so a stripped patch LOOKS stripped.
func _update_ore() -> void:
	var econ := _match.world.economy
	for k in range(mini(_ore_nodes.size(), econ.ore_remaining.size())):
		var node: Node3D = _ore_nodes[k]
		var frac: float = clampf(econ.ore_remaining[k] / 9000.0, 0.0, 1.0)
		var keep: int = int(ceil(frac * float(node.get_child_count())))
		for j in range(node.get_child_count()):
			(node.get_child(j) as MeshInstance3D).visible = j < keep


func _build_oil_markers() -> void:
	var econ := _match.world.economy
	for f in econ.oil_fields:
		var y := _match.terrain.ground_under(f.x, f.y)
		# The stained ground. Dark, but not black: at 0.10 albedo it read as a
		# hole cut in the terrain rather than oil-soaked earth, which is a
		# surprisingly strong illusion at a shallow camera angle.
		var slick := MeshInstance3D.new()
		var disc := CylinderMesh.new()
		disc.top_radius = 40.0
		disc.bottom_radius = 40.0
		disc.height = 1.0
		disc.radial_segments = 24
		slick.mesh = disc
		var m := StandardMaterial3D.new()
		m.albedo_color = Color(0.19, 0.16, 0.12)
		m.roughness = 0.5
		m.metallic = 0.35
		slick.material_override = m
		slick.position = Vector3(f.x, y + 0.5, f.y)
		add_child(slick)

		# AN AMBER RING, the same amber the minimap draws an unclaimed field
		# in. One colour meaning one thing in both places is most of what makes
		# a map legible: a player who has learnt the blip has learnt the ground.
		var ring := MeshInstance3D.new()
		var torus := TorusMesh.new()
		torus.inner_radius = 40.0
		torus.outer_radius = 46.0
		torus.rings = 28
		torus.ring_segments = 6
		ring.mesh = torus
		var rm := StandardMaterial3D.new()
		rm.albedo_color = Color(0.86, 0.62, 0.16)
		rm.emission_enabled = true
		rm.emission = Color(0.86, 0.62, 0.16)
		rm.emission_energy_multiplier = 0.35
		ring.material_override = rm
		ring.position = Vector3(f.x, y + 1.0, f.y)
		add_child(ring)

		# Three seeps and a standing mark. The seeps say "crude", the mark is
		# what you can still see once a building is standing on the disc.
		for k in range(3):
			var a := TAU * float(k) / 3.0 + 0.6
			var pool := MeshInstance3D.new()
			var pd := CylinderMesh.new()
			pd.top_radius = 7.0
			pd.bottom_radius = 7.0
			pd.height = 0.6
			pd.radial_segments = 12
			pool.mesh = pd
			var pmat := StandardMaterial3D.new()
			pmat.albedo_color = Color(0.07, 0.06, 0.05)
			pmat.metallic = 0.7
			pmat.roughness = 0.22
			pool.material_override = pmat
			pool.position = Vector3(f.x + cos(a) * 22.0, y + 1.1, f.y + sin(a) * 22.0)
			add_child(pool)

		var post := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 1.2
		cyl.bottom_radius = 3.2
		cyl.height = 18.0
		cyl.radial_segments = 8
		post.mesh = cyl
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.16, 0.14, 0.10)
		post.material_override = pm
		post.position = Vector3(f.x, y + 9.0, f.y)
		add_child(post)


## A framed dark box behind one readout, sized to the text actually in it.
func _plate(l: Label) -> void:
	if l == null or not l.visible or l.text.strip_edges() == "":
		return
	var r: Rect2 = l.get_rect().grow_individual(10.0, 6.0, 10.0, 6.0)
	_overlay.draw_rect(r, COL_PLATE)
	_overlay.draw_rect(r, COL_PLATE_EDGE, false, 1.0)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3,
		cells: Array) -> void:
	var v := [a, b, c]
	for k in range(3):
		var q: Vector2i = cells[k]
		st.set_color(_ground_colour(v[k].y, q.x, q.y))
		st.add_vertex(v[k])


## Height as colour, with a contour band every 40 m.
##
## The band is not decoration. Terrain decides line of sight in this game, and
## on a map whose relief is 340 m over 12 km a smooth gradient is invisible
## from a playing camera -- you cannot tell which way the ground falls, so you
## cannot tell what your radar can see. Banding makes the slope readable at a
## glance, the way a contour map does, without drawing anything on top of it.
func _ground_colour(h: float, cx: int, cz: int) -> Color:
	if h < 0.0:
		# Water reads as water at a glance, which matters: a naval yard can
		# only go here and nothing else can.
		return Color(0.05, 0.14, 0.26).lerp(Color(0.10, 0.26, 0.40),
			clampf(1.0 + h / 200.0, 0.0, 1.0))
	# A RAMP, not a two-colour lerp. Lerping dark green straight to tan means
	# every height between them is the same olive, and on this map almost all
	# the ground IS between them -- which is why it rendered as one flat
	# colour. Stops give lowland, meadow, scrub, dry ground and rock their own
	# hues, so height reads as terrain type the way it does on a real map and
	# the eye gets colour to separate ground by, not just brightness.
	var c := _ramp(h)

	# Contour band. Raised from 0.13 to 0.22 -- at 0.13 on a hillshaded
	# surface the band is quieter than the shading and disappears into it.
	if int(floor(h / 40.0)) % 2 == 1:
		c = c.darkened(0.22)

	# Mottle. Deterministic per cell -- no randf() below the presentation
	# line and none wanted here either, since the map must look identical on
	# a replay. Two hashed octaves at different scales, so the ground reads as
	# ground rather than as a painted surface, without implying detail that
	# the simulation does not have.
	var m := (_hash01(cx, cz) - 0.5) * 0.10 \
			+ (_hash01(cx >> 2, cz >> 2) - 0.5) * 0.09 \
			+ (_hash01(cx >> 5, cz >> 5) - 0.5) * 0.11
	c = Color(clampf(c.r + m, 0.0, 1.0), clampf(c.g + m, 0.0, 1.0),
			clampf(c.b + m * 0.7, 0.0, 1.0))

	# ...and the hillshade, which is the reason any of the above is visible.
	var idx := cz * _match.terrain.cells_x + cx
	var sh: float = _shade[idx] if idx < _shade.size() else 0.7
	var k: float = 0.46 + 0.86 * sh
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0),
			clampf(c.b * k, 0.0, 1.0))


## Height -> terrain colour, through named stops.
static func _ramp(h: float) -> Color:
	const STOPS := [
		[0.0,   Color(0.16, 0.27, 0.13)],   # valley floor, damp green
		[70.0,  Color(0.25, 0.35, 0.15)],   # meadow
		[150.0, Color(0.38, 0.39, 0.19)],   # scrub
		[250.0, Color(0.50, 0.44, 0.27)],   # dry ground
		[340.0, Color(0.58, 0.55, 0.44)],   # bare earth
		[440.0, Color(0.69, 0.68, 0.66)],   # rock
	]
	if h <= float(STOPS[0][0]):
		return STOPS[0][1]
	for k in range(STOPS.size() - 1):
		var a: float = STOPS[k][0]
		var b: float = STOPS[k + 1][0]
		if h < b:
			return (STOPS[k][1] as Color).lerp(STOPS[k + 1][1],
					(h - a) / (b - a))
	return STOPS[STOPS.size() - 1][1]


## Deterministic 0..1 hash of a cell. Integer mixing, no RNG state, so two
## runs of the same map paint the same ground -- docs/06's determinism rule
## applies to what the player sees, not only to what the sim decides.
static func _hash01(x: int, y: int) -> float:
	var n: int = (x * 73856093) ^ (y * 19349663)
	n = (n ^ (n >> 13)) * 1274126177
	return float((n ^ (n >> 16)) & 0xFFFF) / 65535.0


## Put the camera over the player's own base, ON the ground.
##
## The rig orbits its own origin, so that origin has to sit at terrain height:
## the map fills to 60 m and rises to 400 m on the ridge, and a rig left at
## y = 0 is underground -- the camera then looks out through the inside of the
## heightfield and the whole world renders as flat sky.
func _frame_on_base() -> void:
	var b := _match.base_position(_me)
	_rig.set("_dist", _rig.get("zoom_start"))
	_rig.position = Vector3(b.x, _match.terrain.ground_under(b.x, b.y), b.y)
	_rig.call("_apply")


## The rig pans in x and z only, so it has to be re-seated on the ground every
## frame or driving the view onto the ridge buries it.
func _follow_ground() -> void:
	if _rig == null:
		return
	_rig.position.y = _match.terrain.ground_under(_rig.position.x, _rig.position.z)


# ═══════════════════════════════════════════════════════════════════════════
# THE FRAME
# ═══════════════════════════════════════════════════════════════════════════

func _process(dt: float) -> void:
	if _match == null or _match.phase == SimMatch.Phase.SETUP:
		return
	if not _paused and not _match.is_finished():
		_match.step(dt * _speed)
	_follow_ground()
	_audio_tick()
	_music_tick()
	_update_ore()
	_sync_proxies()
	_prune_selection()
	_project_tracks()
	_picture_tick()
	_update_hud(dt)
	if _overlay:
		_overlay.queue_redraw()


## Sound. Reads what the simulation DID this tick and asks the mixer to voice
## it; the mixer decides what actually survives distance, coalescing and the
## voice cap. Nothing here writes simulation state, so a match sounds different
## with the camera in a different place and PLAYS identically.
##
## Everything below is driven by a counter the sim already maintains, so there
## is no parallel event bus to keep in sync -- if the sim did not record it,
## there is no sound for it.
func _audio_tick() -> void:
	if _audio == null or _match == null:
		return
	var w := _match.world

	# 1. ARRIVALS. munitions.last_impacts is exactly this tick's, already.
	for im in w.munitions.last_impacts:
		if not im.is_arrival():
			continue
		var x: float = im.x if "x" in im else 0.0
		var y: float = im.y if "y" in im else 0.0
		var z: float = im.z if "z" in im else 0.0
		_audio.at("impact_blast" if im.blast_fraction > 0.5
			else "impact_penetration", x, y, z)
	_seen_impacts = w.munitions.last_impacts.size()

	# 2. LAUNCHES. Only the DELTA since last frame, so a pause or a speed-up
	#    cannot replay the whole war.
	var shots: int = w.munitions.launched
	if shots > _seen_shots:
		var fresh := mini(shots - _seen_shots, 6)   # a frame cannot fire 200
		for k in range(fresh):
			var cam := _camera_ground()
			_audio.at("fire_gun", cam.x, cam.y, cam.z, -4.0)
		_seen_shots = shots

	# 3. DEATHS.
	var kills: int = w.damage.kills if w.damage != null else 0
	if kills > _seen_kills:
		for k in range(mini(kills - _seen_kills, 4)):
			var cam := _camera_ground()
			_audio.at("destroy_catastrophic", cam.x, cam.y, cam.z, -2.0)
		_seen_kills = kills


## Feed the score from player-knowable state only: own-side kills delta says
## combat, own standing says peril, own picture and epoch say the rest.
func _music_tick() -> void:
	if _music == null or _match == null:
		return
	var w := _match.world
	var kills: int = w.damage.kills if w.damage != null else 0
	var fighting := kills != _music_kills
	_music_kills = kills
	var s = _match.victory.standing(_me) if _match.victory != null else null
	# Standing has no in_collapse flag -- collapse is capitulation_s > 0, and
	# is_collapsing() wraps exactly that. Guessing the field name here would
	# have silently muted the peril layer forever, which is the sort of bug
	# nothing measures: the game merely feels flat at its most desperate
	# moment.
	var collapse: bool = s != null and s.is_collapsing()
	var contacts: int = _match.picture_for(_me).track_ids().size()
	var epoch: int = w.economy.epoch_of(_me) if w.economy != null else 1
	_music.set_state(fighting, collapse, contacts, epoch)


func _camera_ground() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	return cam.global_position if cam != null else Vector3.ZERO


## Create, move and retire the visible representation of the entity store.
## Only the player's OWN COALITION is represented here; everything hostile
## reaches the screen through the track table instead.
func _sync_proxies() -> void:
	var e := _match.world.entities
	for i in range(e.count()):
		var mine := e.alive[i] == 1 and e.faction[i] == _my_team
		var node: Node3D = _proxies.get(i)
		if not mine:
			if node != null:
				node.queue_free()
				_proxies.erase(i)
			continue
		if node == null:
			node = _make_proxy(i)
			_proxies[i] = node
			add_child(node)
		node.position = Vector3(e.pos_x[i], e.pos_y[i], e.pos_z[i])
		node.rotation.y = e.heading_rad[i]
		# A unit still under construction is visibly incomplete: it sinks into
		# the ground and rises as it is built. It can be bombed the whole time,
		# which is the point of placing the entity immediately.
		if e.is_structure[i] == 1:
			var p := _match.world.economy.construction_progress(i)
			node.scale = Vector3(1.0, maxf(p, 0.08), 1.0)


func _make_proxy(i: int) -> Node3D:
	var e := _match.world.entities
	var holder := Node3D.new()
	holder.name = "u%d" % i
	var glb := _model_for(_match.world.economy.def_of(i))
	if glb != "" and ResourceLoader.exists(glb):
		holder.add_child((load(glb) as PackedScene).instantiate())
		return holder
	holder.add_child(_block(_match.world.economy.role_of(i),
		e.is_structure[i] == 1, e.faction[i]))
	return holder


## A stand-in for anything with no model -- every structure, and any vehicle
## role the art pipeline has not reached. Sized off the role so a refinery does
## not look like a bunker.
func _block(role: String, is_structure: bool, faction: int) -> MeshInstance3D:
	var d := SimRoster.make(role, 4)
	var size := Vector3(7.0, 3.0, 9.0)
	if is_structure:
		var f: float = d.footprint_m if d != null else 12.0
		size = Vector3(f * 1.1, maxf(f * 0.5, 6.0), f * 1.1)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position.y = size.y * 0.5
	var mat := StandardMaterial3D.new()
	var tint := Color(0.42, 0.44, 0.38) if faction == _my_team \
		else Color(0.44, 0.34, 0.32)
	if is_structure:
		tint = tint.lerp(Color(0.66, 0.63, 0.55), 0.45)
	mat.albedo_color = tint
	mat.roughness = 0.92
	mi.material_override = mat
	return mi


## The def carries its own model now: SimFactionData resolves faction, lineage
## and epoch against what is on disk, so a Russian player's tanks come out of
## the factory as T-series hulls without the UI knowing anything about
## factions. The one hardcoded thing left here is the final fallback -- a def
## with no stem (or a stem whose GLB is missing) renders as _block().
func _model_for(def: SimUnitDef) -> String:
	if def == null or def.model_stem == "":
		return ""
	return ASSETS + def.model_stem + "_LOD0.glb"


func _prune_selection() -> void:
	var e := _match.world.entities
	var keep: Array[int] = []
	for i in _selected:
		if e.is_alive(i) and e.owner[i] == _me:
			keep.append(i)
	_selected = keep


# ═══════════════════════════════════════════════════════════════════════════
# THE PICTURE. Everything hostile on the screen comes from here and only here.
# ═══════════════════════════════════════════════════════════════════════════

func _project_tracks() -> void:
	_track_screen.clear()
	if _headless or _rig == null:
		return
	var cam: Camera3D = _rig.camera()
	var table := _match.picture_for(_me)
	for id in table.track_ids():
		var tr := table.get_track(id)
		if tr == null or tr.quality == SimTypes.TrackQuality.NONE:
			continue
		var at3 := Vector3(tr.pos_x, maxf(tr.pos_y, 0.0) + 4.0, tr.pos_z)
		if tr.bearing_only:
			# A bearing is not a position. It is drawn as a line FROM the
			# nearest thing of ours that can hear it, out along the bearing --
			# because that is literally all the sim knows.
			_track_screen.append({"id": id, "bearing": true,
				"at": Vector2.ZERO, "track": tr})
			continue
		if cam.is_position_behind(at3):
			continue
		_track_screen.append({"id": id, "bearing": false,
			"at": cam.unproject_position(at3), "track": tr})


## Compare the table against last frame's memory and voice the DIFFERENCE.
## contact_new / track_lost / radar_warning are information, not ambience --
## they fire on transitions, never on state, so holding forty contacts is
## silent and gaining one is not. Reads the table and own-force state only.
func _picture_tick() -> void:
	if _match == null:
		return
	var table := _match.picture_for(_me)
	var now_s := Time.get_ticks_msec() / 1000.0
	var e := _match.world.entities
	var own := _match.own_units(_me)
	var seen: Dictionary = {}
	for id in table.track_ids():
		var tr := table.get_track(id)
		if tr == null or tr.quality == SimTypes.TrackQuality.NONE:
			continue
		seen[id] = tr.quality

		# ILLUMINATION. We may not read the enemy's table, but our own ESM
		# hears their radar: an EMITTING hostile track close to our force is
		# the honest RWR condition, and it is all SimTrack fields.
		var threat := false
		if tr.emitting and not tr.bearing_only:
			for u in own:
				var dx: float = e.pos_x[u] - tr.pos_x
				var dz: float = e.pos_z[u] - tr.pos_z
				if dx * dx + dz * dz < ILLUM_WARN_M * ILLUM_WARN_M:
					threat = true
					break
		if threat:
			if not _illuminating.has(id) and _picture_primed \
					and now_s - _cue_rwr_t > 5.0:
				_cue_rwr_t = now_s
				if _audio != null:
					_audio.flat("radar_warning", -3.0)
			_illuminating[id] = true
		else:
			_illuminating.erase(id)

		# TRANSITIONS. A new id is a new contact; a higher rung is an upgrade.
		# Both flash; only the new contact speaks.
		var prev: int = _known_tracks.get(id, -1)
		if prev < 0:
			_track_flash[id] = now_s
			if _picture_primed and now_s - _cue_contact_t > 1.0:
				_cue_contact_t = now_s
				if _audio != null:
					_audio.flat("contact_new", -8.0)
		elif tr.quality > prev:
			_track_flash[id] = now_s

	for id in _known_tracks.keys():
		if not seen.has(id):
			_illuminating.erase(id)
			_track_flash.erase(id)
			if _picture_primed and now_s - _cue_lost_t > 1.0:
				_cue_lost_t = now_s
				if _audio != null:
					_audio.flat("track_lost", -10.0)
	_known_tracks = seen
	_picture_primed = true


func _track_at(screen: Vector2) -> int:
	var best := -1
	var best_d := TRACK_PICK_PX
	for entry in _track_screen:
		if entry["bearing"]:
			continue
		var d: float = (entry["at"] as Vector2).distance_to(screen)
		if d < best_d:
			best_d = d
			best = int(entry["id"])
	return best


# ═══════════════════════════════════════════════════════════════════════════
# INPUT. Every branch ends in a SimCommandQueue call or in the camera.
# ═══════════════════════════════════════════════════════════════════════════

func _unhandled_input(ev: InputEvent) -> void:
	if _match == null or _match.phase == SimMatch.Phase.SETUP:
		return
	if ev is InputEventKey and ev.pressed and not ev.echo:
		_key(ev as InputEventKey)
		return
	if ev is InputEventMouseMotion:
		var mm := ev as InputEventMouseMotion
		_cursor_ground = _ground_point(mm.position)
		if _placing_role != "":
			_placing_problem = _placement_problem(_cursor_ground)
		if _dragging:
			return
		return
	if not (ev is InputEventMouseButton):
		return
	var mb := ev as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		if mb.pressed:
			if _placing_role != "":
				_try_place(_ground_point(mb.position))
				return
			# Attack-move: armed by A, or A held at the click -- the same
			# gesture either way, one formation order at combat power.
			if (_attack_move_armed or Input.is_key_pressed(KEY_A)) \
					and not _selected.is_empty():
				_attack_move_armed = false
				_order_move_to(_ground_point(mb.position), true)
				return
			if _patrol_armed and not _selected.is_empty():
				_patrol_armed = false
				_order_patrol(_ground_point(mb.position))
				return
			_attack_move_armed = false
			_patrol_armed = false
			if mb.double_click:
				# Double-click is CONTEXT-SENSITIVE, per the owner's design:
				# on a unit that can deploy or unload it means D; on anything
				# else it selects everything visible of the same role. One
				# gesture, two meanings, resolved by what was clicked -- the
				# same way Red Alert's own double-click behaves.
				_dragging = false
				var u := _own_unit_at(mb.position)
				if u >= 0 and _can_deploy_or_unload(u):
					_do_deploy(PackedInt32Array([u]))
					return
				_select_same_role(mb.position, Input.is_key_pressed(KEY_SHIFT))
				return
			_drag_from = mb.position
			_dragging = true
		elif _dragging:
			_dragging = false
			if _drag_from.distance_to(mb.position) < DRAG_THRESHOLD_PX:
				_pick(mb.position, Input.is_key_pressed(KEY_SHIFT))
			else:
				_box_select(_drag_from, mb.position, Input.is_key_pressed(KEY_SHIFT))
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		if _placing_role != "":
			_placing_role = ""
			_refresh_panels()
			return
		if _attack_move_armed or _patrol_armed:
			_attack_move_armed = false
			_patrol_armed = false
			_flash("order cancelled")
			return
		# Right-click on an OWN transport with units selected = board it.
		# The sim validates who may carry whom; the UI only offers the gesture
		# when the target visibly has empty slots.
		var boarder := _own_unit_at(mb.position)
		if boarder >= 0 and not _selected.has(boarder) and not _selected.is_empty():
			var ent := _match.world.entities
			if ent.cargo_capacity[boarder] > ent.cargo_len[boarder]:
				var asked := 0
				for i in _selected:
					if i != boarder:
						_match.world.commands.load_cargo(_me, i, boarder)
						asked += 1
				if asked > 0:
					_flash("boarding %d unit(s)" % asked)
					if _audio != null:
						_audio.flat("ui_order", -6.0)
					return
		# Right-click with a FACTORY selected sets its rally point -- the Red
		# Alert gesture. Units already in the selection still get move orders.
		var e := _match.world.entities
		var set_rally := false
		var pt := _ground_point(mb.position)
		for i in _selected:
			if e.is_alive(i) and e.is_structure[i] == 1:
				_match.world.economy.set_rally(i, pt.x, pt.z)
				set_rally = true
		if set_rally:
			_flash("rally point set")
			if _audio != null:
				_audio.flat("ui_order", -6.0)
		_order(mb.position)


func _key(k: InputEventKey) -> void:
	match k.keycode:
		KEY_ESCAPE:
			if _placing_role != "":
				_placing_role = ""
				_refresh_panels()
			elif _attack_move_armed:
				_attack_move_armed = false
				_flash("attack-move cancelled")
			else:
				_selected.clear()
		KEY_A:
			# Arm attack-move for the next left click. A also pans the camera
			# (WASD); a tap is a negligible nudge, and A+click never notices.
			if not _selected.is_empty():
				_attack_move_armed = true
				_flash("ATTACK MOVE -- click the objective")
		KEY_S:
			for i in _selected:
				_match.world.commands.stop(_me, i)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var n := k.keycode - KEY_0
			if k.ctrl_pressed or k.meta_pressed:
				# ASSIGN. Command works as well as Control because this is a
				# Mac and muscle memory there is Command.
				var g := PackedInt32Array()
				for i in _selected:
					g.append(i)
				_groups[n] = g
				_flash("group %d -- %d units" % [n, g.size()])
			elif _groups.has(n):
				# RECALL, and CENTRE if the same group is pressed twice inside
				# half a second. Two meanings on one key is what makes this
				# fast; separating them onto two keys is what makes it slow.
				_selected.clear()
				for i in (_groups[n] as PackedInt32Array):
					if _match.world.entities.is_alive(i):
						_selected.append(i)
				var now := Time.get_ticks_msec() / 1000.0
				if _last_group == n and now - _last_group_t < 0.5:
					_centre_on_selection()
				_last_group = n
				_last_group_t = now
				_refresh_panels()
		KEY_H:
			# HOME. The single most-pressed key in an RTS.
			_frame_on_base()
		KEY_D:
			_do_deploy(PackedInt32Array(_selected))
		KEY_T:
			if not _selected.is_empty():
				_patrol_armed = true
				_flash("PATROL -- click the far leg")
		KEY_P:
			# Primary factory: bare production orders route here, and the
			# panel queues to it. One factory selected = mark it.
			var ep := _match.world.entities
			for i in _selected:
				if ep.is_alive(i) and ep.is_structure[i] == 1:
					_match.world.economy.set_primary(_me, i)
					_flash("primary structure set")
					break
		KEY_X:
			# Weapons tight / weapons free. The other half of EMCON: a unit
			# that shoots announces itself. Moved off H, which is Home.
			var fc := _match.world.fire_control
			for i in _selected:
				fc.set_hold_fire(i, not fc.is_holding_fire(i))
		KEY_E:
			pass    # camera rotate, handled by the rig
		KEY_R:
			# Radiate / go silent, docs/02 §7.1's one keypress. The flash is
			# the immediate feedback; the pulse ring / dim dot in the overlay
			# is the persistent one.
			var to_silent := 0
			var to_radiate := 0
			for i in _selected:
				var cur: int = _match.world.entities.emcon[i]
				var next := SimTypes.Emcon.SILENT if cur == SimTypes.Emcon.RADIATE \
					else SimTypes.Emcon.RADIATE
				if next == SimTypes.Emcon.SILENT:
					to_silent += 1
				else:
					to_radiate += 1
				_match.world.commands.set_emcon(_me, i, next)
			if to_silent + to_radiate > 0:
				if to_radiate == 0:
					_flash("EMCON: %d unit%s going SILENT" % [to_silent,
						"" if to_silent == 1 else "s"])
				elif to_silent == 0:
					_flash("EMCON: %d unit%s RADIATING" % [to_radiate,
						"" if to_radiate == 1 else "s"])
				else:
					_flash("EMCON: %d radiating, %d silent" % [to_radiate, to_silent])
		KEY_SPACE:
			_paused = not _paused
		KEY_TAB:
			_speed = 1.0 if _speed > 1.5 else 3.0
		KEY_F1:
			_frame_on_base()
		KEY_F5:
			_quicksave()
		KEY_F9:
			_quickload()


# ── quicksave / quickload (SimSave) ─────────────────────────────────────────
# F5 writes the whole match -- every subsystem, every RNG stream -- to one
# JSON file; F9 rebuilds a match from it and swaps it in. The restored match
# is behaviourally identical to the saved one (test_saveload.gd holds that
# property), so loading mid-battle resumes the battle, not an approximation.

const QUICKSAVE_PATH := "user://quicksave.json"


func _quicksave() -> void:
	if _match == null:
		return
	var f := FileAccess.open(QUICKSAVE_PATH, FileAccess.WRITE)
	if f == null:
		_flash("quicksave FAILED -- cannot write %s" % QUICKSAVE_PATH)
		return
	f.store_string(SimSave.to_json(_match))
	f.close()
	_flash("quicksaved (t+%.0f s)" % _match.elapsed_s())


func _quickload() -> void:
	if not FileAccess.file_exists(QUICKSAVE_PATH):
		_flash("no quicksave to load")
		return
	var restored = SimSave.from_json(FileAccess.get_file_as_string(QUICKSAVE_PATH))
	if not (restored is SimMatch):
		_flash("quickload FAILED -- see the log")
		return
	_match = restored
	# The world behind every cached index just changed: drop the visual
	# proxies (sync rebuilds them from the restored entities -- indices are
	# stable, but a save older than now can hold FEWER of them), drop the
	# selection, and fast-forward the audio counters so the mixer does not
	# replay every shot since the save as one glorious chord.
	for i in _proxies:
		(_proxies[i] as Node3D).queue_free()
	_proxies.clear()
	_selected.clear()
	_attack_move_armed = false
	_patrol_armed = false
	_placing_role = ""
	_seen_shots = _match.world.munitions.launched
	_seen_kills = _match.world.damage.kills
	_seen_impacts = 0
	_music_kills = _match.world.damage.kills
	_refresh_panels()
	_flash("quickloaded (t+%.0f s)" % _match.elapsed_s())


## Put the camera over whatever is selected. Used by the double-tap on a
## control group, and by nothing else -- Home goes to the base instead.
## A short-lived line of text. Assigning a control group with no feedback is
## indistinguishable from the key not working.
func _flash(msg: String) -> void:
	_flash_msg = msg
	_flash_until = Time.get_ticks_msec() / 1000.0 + 2.0


func _centre_on_selection() -> void:
	if _selected.is_empty() or _rig == null:
		return
	var e := _match.world.entities
	var cx := 0.0
	var cz := 0.0
	var n := 0
	for i in _selected:
		if e.is_alive(i):
			cx += e.pos_x[i]
			cz += e.pos_z[i]
			n += 1
	if n == 0:
		return
	cx /= float(n)
	cz /= float(n)
	_rig.position = Vector3(cx, _match.terrain.ground_under(cx, cz), cz)
	_rig.call("_apply")


func _ground_point(screen: Vector2) -> Vector3:
	if _rig == null:
		return Vector3.ZERO
	var cam: Camera3D = _rig.camera()
	var from := cam.project_ray_origin(screen)
	var dir := cam.project_ray_normal(screen)
	# March the ray against the heightfield rather than intersecting y = 0.
	# On a map with 340 m of relief, a flat-plane hit test puts the order up to
	# a few hundred metres from where the player pointed.
	var t := _match.terrain
	var travel := 0.0
	var step := 12.0
	while travel < 12000.0:
		var p := from + dir * travel
		if p.y <= t.ground_under(p.x, p.z):
			return Vector3(p.x, t.ground_under(p.x, p.z), p.z)
		travel += step
		step = minf(step * 1.06, 90.0)
	if absf(dir.y) < 0.0001:
		return Vector3.ZERO
	return from + dir * (-from.y / dir.y)


func _pick(screen: Vector2, additive: bool) -> void:
	if not additive:
		_selected.clear()
	var cam: Camera3D = _rig.camera()
	var e := _match.world.entities
	var best := -1
	var best_d := 40.0
	for i in _match.own_units(_me):
		var at := Vector3(e.pos_x[i], e.pos_y[i] + 2.0, e.pos_z[i])
		if cam.is_position_behind(at):
			continue
		var d := cam.unproject_position(at).distance_to(screen)
		if d < best_d:
			best_d = d
			best = i
	if best >= 0 and not _selected.has(best):
		_selected.append(best)
		if _audio != null:
			_audio.flat("ui_select", -8.0)


func _box_select(a: Vector2, b: Vector2, additive: bool) -> void:
	if not additive:
		_selected.clear()
	var r := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
	var cam: Camera3D = _rig.camera()
	var e := _match.world.entities
	var grabbed := 0
	for i in _match.own_units(_me):
		# A marquee grabs the mobile force, not the base. Dragging a box over
		# your own town centre and then right-clicking should not try to drive
		# the refinery somewhere.
		if e.is_structure[i] == 1:
			continue
		var at := Vector3(e.pos_x[i], e.pos_y[i] + 2.0, e.pos_z[i])
		if cam.is_position_behind(at):
			continue
		if r.has_point(cam.unproject_position(at)) and not _selected.has(i):
			_selected.append(i)
			grabbed += 1
	if grabbed > 0 and _audio != null:
		_audio.flat("ui_select", -8.0)


## Double-click: select everything of the clicked unit's ROLE that is on the
## screen right now. "Visible" is literal -- in front of the camera and inside
## the viewport -- so it grabs the tanks you are looking at, not the two spares
## idling at home. Own units only, from ground truth we are entitled to.
func _select_same_role(screen: Vector2, additive: bool) -> void:
	var cam: Camera3D = _rig.camera()
	var e := _match.world.entities
	var best := -1
	var best_d := 40.0
	for i in _match.own_units(_me):
		var at := Vector3(e.pos_x[i], e.pos_y[i] + 2.0, e.pos_z[i])
		if cam.is_position_behind(at):
			continue
		var d := cam.unproject_position(at).distance_to(screen)
		if d < best_d:
			best_d = d
			best = i
	if best < 0:
		if not additive:
			_selected.clear()
		return
	var role := _match.world.economy.role_of(best)
	if not additive:
		_selected.clear()
	var view := Rect2(Vector2.ZERO, get_viewport().get_visible_rect().size)
	for j in _match.own_units(_me):
		if _match.world.economy.role_of(j) != role:
			continue
		var at2 := Vector3(e.pos_x[j], e.pos_y[j] + 2.0, e.pos_z[j])
		if cam.is_position_behind(at2):
			continue
		if view.has_point(cam.unproject_position(at2)) and not _selected.has(j):
			_selected.append(j)
	_flash("selected %d x %s" % [_selected.size(), role])
	if _audio != null:
		_audio.flat("ui_select", -8.0)
	_refresh_panels()


## Right click. On a contact it is an attack order naming that TRACK; on the
## ground it is a formation move. Both go through the same queue the AI uses.
## The unit of ours nearest the cursor, or -1. The same search
## _select_same_role runs, shared rather than duplicated.
func _own_unit_at(screen: Vector2) -> int:
	var cam: Camera3D = _rig.camera()
	var e := _match.world.entities
	var best := -1
	var best_d := 40.0
	for i in _match.own_units(_me):
		var at := Vector3(e.pos_x[i], e.pos_y[i] + 2.0, e.pos_z[i])
		if cam.is_position_behind(at):
			continue
		var d := cam.unproject_position(at).distance_to(screen)
		if d < best_d:
			best_d = d
			best = i
	return best


func _can_deploy_or_unload(u: int) -> bool:
	var e := _match.world.entities
	if e.cargo_len[u] > 0:
		return true
	var ts = _match.world.transport_system
	return ts != null and ts.is_deployable(u)


## D -- and double-click on a deployable. Unload beats deploy when both apply,
## because a loaded transport's most urgent verb is always "put them down".
func _do_deploy(units: PackedInt32Array) -> void:
	var e := _match.world.entities
	var ts = _match.world.transport_system
	var did := 0
	for i in units:
		if not e.is_alive(i):
			continue
		if e.cargo_len[i] > 0:
			_match.world.commands.unload_cargo(_me, i)
			did += 1
		elif ts != null and ts.is_deployable(i):
			_match.world.commands.deploy(_me, i)
			did += 1
	if did > 0:
		_flash("deploy/unload -- %d unit(s)" % did)
		if _audio != null:
			_audio.flat("ui_order", -6.0)
	else:
		_flash("nothing selected can deploy or unload")


## T-click. Ground and naval loop between here and there; aircraft get a
## standing orbit their base keeps cycling under the docs/04 fuel rule.
func _order_patrol(p: Vector3) -> void:
	var e := _match.world.entities
	var did := 0
	for i in _selected:
		if not e.is_alive(i):
			continue
		if e.category[i] == SimTypes.Category.AIR:
			_match.world.commands.sortie_patrol(_me, i, p.x, p.z)
		else:
			var pts := PackedFloat32Array([p.x, p.z])
			_match.world.commands.patrol(_me, i, pts)
		did += 1
	if did > 0:
		_flash("patrol -- %d unit(s)" % did)
		if _audio != null:
			_audio.flat("ui_order", -6.0)


func _order(screen: Vector2) -> void:
	if _selected.is_empty():
		return
	var tid := _track_at(screen)
	if tid >= 0:
		for i in _selected:
			_match.world.commands.attack_track(_me, i, tid)
		if _audio != null:
			_audio.flat("ui_order", -6.0)
		return
	_order_move_to(_ground_point(screen))


## The ground half of an order, shared by a right-click in the world, a
## right-click on the minimap, and the attack-move gesture: one formation
## order through the command queue. `attack` routes it as ATTACK_MOVE --
## advance at combat power, engaging what appears.
func _order_move_to(p: Vector3, attack := false) -> void:
	if _selected.is_empty():
		return
	var units := PackedInt32Array()
	for i in _selected:
		units.append(i)
	# The formation grid lives in SimMovement, where the movement layer put it.
	var slots := _match.world.movement.formation_slots(units, p.x, p.z)
	for k in range(units.size()):
		var sx: float = slots[k * 2] if slots.size() > k * 2 + 1 else p.x
		var sz: float = slots[k * 2 + 1] if slots.size() > k * 2 + 1 else p.z
		# Aircraft do not drive to a point -- they SORTIE to it and come home
		# on fuel, which is the Empire Earth half of the owner's control
		# design. The queue validates whether this unit can actually fly one.
		if _match.world.entities.category[units[k]] == SimTypes.Category.AIR:
			_match.world.commands.sortie_strike(_me, units[k], p.x, p.z)
			continue
		if attack:
			_match.world.commands.attack_move(_me, units[k], sx, sz)
		else:
			_match.world.commands.move(_me, units[k], sx, sz)
	if attack:
		_flash("attack-moving %d unit%s" % [units.size(),
			"" if units.size() == 1 else "s"])
	if _audio != null:
		_audio.flat("ui_order", -6.0)


# ── minimap ──────────────────────────────────────────────────────────────────

## Left-click on the minimap: put the camera there, seated on the ground the
## way every other camera move is.
func _fly_to(world: Vector2) -> void:
	if _rig == null:
		return
	_rig.position = Vector3(world.x,
		_match.terrain.ground_under(world.x, world.y), world.y)
	_rig.call("_apply")


## Right-click on the minimap: a move order for the selection to that world
## point, through the exact path a right-click in the world takes.
func _minimap_order(world: Vector2) -> void:
	if _selected.is_empty():
		return
	# _order_move_to voices ui_order itself.
	_order_move_to(Vector3(world.x,
		_match.terrain.ground_under(world.x, world.y), world.y))


# ═══════════════════════════════════════════════════════════════════════════
# BUILDING AND PRODUCING
# ═══════════════════════════════════════════════════════════════════════════

func _placement_problem(at: Vector3) -> String:
	var d := _match.world.economy.def_for(_me, _placing_role)
	if d == null:
		return "not available"
	if _match.credits(_me) < d.cost:
		return "cannot afford %.0f" % d.cost
	return _match.world.economy.placement_problem(_me, d, at.x, at.z)


func _try_place(at: Vector3) -> void:
	if _placement_problem(at) != "":
		return
	# The BUILD command validates all of this again inside the sim. The check
	# above is only so the cursor can be red BEFORE the click -- the sim is
	# still the authority, and it refuses the order if the ground changed.
	_match.world.commands.build(_me, _placing_role, at.x, at.z)
	if not Input.is_key_pressed(KEY_SHIFT):
		_placing_role = ""
	_refresh_panels()


func _queue(def_key: String) -> void:
	# Queue at the lowest-indexed operational structure that can turn this out
	# and has room. Lowest index is stable and predictable, which is what a
	# player needs from an implicit choice.
	for s in _match.production_structures(_me):
		if def_key in _match.world.economy.production_options(_me, s):
			_match.world.commands.produce(_me, s, def_key)
			return


# ═══════════════════════════════════════════════════════════════════════════
# HUD
# ═══════════════════════════════════════════════════════════════════════════

## Every own STRUCTURE in the selection, which is what REPAIR and SELL act on.
func _selected_structures() -> PackedInt32Array:
	var out := PackedInt32Array()
	var e := _match.world.entities
	for i in _selected:
		if e.is_alive(i) and e.is_structure[i] == 1 and e.owner[i] == _me:
			out.append(i)
	return out


func _on_repair() -> void:
	var picked := _selected_structures()
	var damaged := 0
	var e := _match.world.entities
	for i in picked:
		if e.structure[i] < e.structure_max[i] - 0.01:
			_match.world.commands.repair(_me, i)
			damaged += 1
	if damaged == 0:
		_flash("nothing selected needs repair")
	else:
		_flash("repairing %d structure(s)" % damaged)
		if _audio != null:
			_audio.flat("ui_order", -6.0)


func _on_sell() -> void:
	var picked := _selected_structures()
	if picked.is_empty():
		_flash("select one of your own structures to sell")
		return
	for i in picked:
		_match.world.commands.sell(_me, i)
	_flash("sold %d structure(s) at %d%% of cost" % [
		picked.size(), int(SimEconomy.SELL_REFUND * 100.0)])
	_selected.clear()
	if _audio != null:
		_audio.flat("ui_order", -6.0)


func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	layer.add_child(_overlay)

	_stats = _label(layer, Vector2(12, 8), 14)

	# The refine bottleneck, top centre and amber, shown only while it exists:
	# crude being pumped that no refinery can turn into credits is money on the
	# ground, and the top-bar income number alone cannot say WHY it is low.
	_bottleneck_label = _label(layer, Vector2.ZERO, 14)
	_bottleneck_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_bottleneck_label, 0.5, 0.0, -300.0, 8.0, 300.0, 30.0)
	_bottleneck_label.add_theme_color_override("font_color", COL_UNKNOWN)
	_bottleneck_label.visible = false

	# LOW POWER. The economy has slowed production under a brownout since the
	# day it was written -- power_satisfaction() scales the work done -- and
	# the HUD never said so. A player whose factories have quietly halved
	# their rate needs to be told why, in the place they are already looking.
	_power_label = _label(layer, Vector2.ZERO, 16)
	_power_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_power_label, 0.5, 0.0, -300.0, 28.0, 300.0, 52.0)
	_power_label.add_theme_color_override("font_color", COL_HOSTILE)
	_power_label.visible = false

	# The capitulation countdown. SimVictory gives a collapsed player 120 s to
	# rebuild; a countdown buried in the stats block is not a warning.
	_collapse_label = _label(layer, Vector2.ZERO, 24)
	_collapse_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_anchor(_collapse_label, 0.5, 0.0, -430.0, 40.0, 430.0, 104.0)
	_collapse_label.add_theme_color_override("font_color", COL_HOSTILE)
	_collapse_label.visible = false

	# The minimap owns the bottom-left corner; it anchors itself in setup().
	_minimap = MinimapScript.new()
	layer.add_child(_minimap)
	_minimap.setup(_match, _me, _my_team, _rig)
	_minimap.fly_to.connect(_fly_to)
	_minimap.order_at.connect(_minimap_order)

	# Anchored by hand rather than with a preset: set_anchors_preset() rewrites
	# the offsets, so a position assigned afterwards is silently discarded and
	# the panel ends up off the bottom of the screen. Shifted right of the
	# minimap's 220 px.
	_selection_info = _label(layer, Vector2.ZERO, 13)
	_anchor(_selection_info, 0.0, 1.0, 246.0, -212.0, 854.0, -10.0)

	_log_label = _label(layer, Vector2.ZERO, 12)
	_anchor(_log_label, 1.0, 1.0, -700.0, -128.0, -256.0, -10.0)

	# Build and production panels, right-hand side, RA2's side bar.
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	panel.position = Vector2(-236, 8)
	panel.custom_minimum_size = Vector2(228, 0)
	var style := StyleBoxFlat.new()
	style.bg_color = COL_PANEL
	style.set_content_margin_all(8)
	style.set_border_width_all(1)
	style.border_width_left = 2
	style.border_color = COL_PANEL_EDGE
	style.corner_radius_top_left = 3
	style.corner_radius_bottom_left = 3
	panel.add_theme_stylebox_override("panel", style)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	layer.add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(212, 720)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(col)
	# TABS, Red Alert style. One panel with categories beats two lists,
	# because a player looking for a tank should not have to know whether a
	# tank is "built" or "produced" -- that is an implementation detail of the
	# economy, not a thing anyone thinks about while playing.
	_tab_bar = HBoxContainer.new()
	_tab_bar.add_theme_constant_override("separation", 2)
	col.add_child(_tab_bar)
	for name in TABS:
		var b := Button.new()
		b.text = TAB_LABEL[name]
		b.custom_minimum_size = Vector2(0, 24)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 11)
		b.pressed.connect(_on_tab.bind(name))
		_tab_bar.add_child(b)

	# The queue readout: what the factories are doing RIGHT NOW. The tabs above
	# carry per-tab queued counts; this is the most-advanced job's progress.
	# Updated every frame in _update_hud -- text and value only, no rebuild, so
	# it cannot eat a click the way rebuilding the buttons would.
	_queue_label = Label.new()
	_queue_label.add_theme_font_size_override("font_size", 11)
	_queue_label.add_theme_color_override("font_color", Color(0.80, 0.84, 0.80))
	_queue_label.visible = false
	col.add_child(_queue_label)
	_queue_bar = ProgressBar.new()
	_queue_bar.custom_minimum_size = Vector2(0, 10)
	_queue_bar.show_percentage = false
	_queue_bar.max_value = 1.0
	_queue_bar.visible = false
	col.add_child(_queue_bar)

	_build_box = VBoxContainer.new()
	col.add_child(_build_box)
	_produce_box = VBoxContainer.new()
	col.add_child(_produce_box)

	# REPAIR and SELL, the two things Red Alert lets you do to a building you
	# already own. Both go through the command queue like every other order --
	# the economy decides the refund and the price, because a UI that computed
	# them would drift from the sim that pays them.
	var tools := HBoxContainer.new()
	tools.add_theme_constant_override("separation", 2)
	col.add_child(tools)
	_repair_btn = Button.new()
	_repair_btn.text = "REPAIR"
	_repair_btn.custom_minimum_size = Vector2(0, 26)
	_repair_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_repair_btn.add_theme_font_size_override("font_size", 11)
	_repair_btn.pressed.connect(_on_repair)
	tools.add_child(_repair_btn)
	_sell_btn = Button.new()
	_sell_btn.text = "SELL"
	_sell_btn.custom_minimum_size = Vector2(0, 26)
	_sell_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sell_btn.add_theme_font_size_override("font_size", 11)
	_sell_btn.pressed.connect(_on_sell)
	tools.add_child(_sell_btn)

	_banner = Label.new()
	_banner.set_anchors_preset(Control.PRESET_CENTER)
	_banner.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_banner.grow_vertical = Control.GROW_DIRECTION_BOTH
	_banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_banner.add_theme_font_size_override("font_size", 44)
	_banner.add_theme_constant_override("outline_size", 8)
	_banner.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_banner.visible = false
	layer.add_child(_banner)

	_refresh_panels()


func _label(parent: Node, at: Vector2, size: int) -> Label:
	var l := Label.new()
	l.position = at
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(0.93, 0.95, 0.92))
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 4)
	parent.add_child(l)
	return l


## Anchor a Control to a corner explicitly, in pixels from that corner.
static func _anchor(c: Control, ax: float, ay: float,
		left: float, top: float, right: float, bottom: float) -> void:
	c.anchor_left = ax
	c.anchor_right = ax
	c.anchor_top = ay
	c.anchor_bottom = ay
	c.offset_left = left
	c.offset_top = top
	c.offset_right = right
	c.offset_bottom = bottom


func _heading(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 11)
	l.add_theme_color_override("font_color", Color(0.66, 0.72, 0.78))
	return l


## Rebuilt when the tech tree changes -- an epoch advance, a new factory, a
## factory lost. Not every frame: these are Buttons, and rebuilding them under
## the cursor would eat the click.
var _panel_signature := ""


## The six tabs, in the order Red Alert puts them: what you build first, what
## defends it, then the three arms, then the sea.
const TABS := ["BUILDING", "DEFENSE", "INFANTRY", "VEHICLE", "AIR", "NAVY"]
const TAB_LABEL := {
	"BUILDING": "BLD", "DEFENSE": "DEF", "INFANTRY": "INF",
	"VEHICLE": "VEH", "AIR": "AIR", "NAVY": "SEA",
}

## Which tab a role belongs in. Structures split by PURPOSE rather than by
## being structures: a player thinks "I need defence", not "I need a building".
const DEFENSIVE := ["fixed_sam", "coastal_battery", "bunker", "fixed_radar",
	"ew_station"]


func _tab_of(role: String, is_structure: bool) -> String:
	if is_structure:
		return "DEFENSE" if role in DEFENSIVE else "BUILDING"
	var d := _match.world.economy.def_for(_me, role)
	if d == null:
		return "VEHICLE"
	# domain is a SimPlayerSetup.Domain BIT, not an enum value, so test the bit.
	if d.domain & SimPlayerSetup.Domain.AIR:
		return "AIR"
	if d.domain & SimPlayerSetup.Domain.NAVAL:
		return "NAVY"
	if d.domain & SimPlayerSetup.Domain.INFANTRY:
		return "INFANTRY"
	return "VEHICLE"


func _on_tab(name: String) -> void:
	_tab = name
	_refresh_panels(true)


func _refresh_panels(force := false) -> void:
	if _build_box == null:
		return
	var structures := _match.buildable_structures(_me)
	var units := _production_menu()
	var sig := "%s|%s|%s|%s" % [",".join(structures), ",".join(units),
		_placing_role, _tab]
	if sig == _panel_signature and not force:
		return
	_panel_signature = sig

	if _tab_bar != null:
		for i in range(_tab_bar.get_child_count()):
			var b := _tab_bar.get_child(i) as Button
			b.modulate = Color(1, 1, 1) if TABS[i] == _tab else Color(0.55, 0.58, 0.55)

	for c in _build_box.get_children():
		c.queue_free()
	for c in _produce_box.get_children():
		c.queue_free()

	var shown := 0
	for role in structures:
		if _tab_of(role, true) == _tab:
			_build_box.add_child(_role_button(role, true))
			shown += 1
	for role in units:
		if _tab_of(role, false) == _tab:
			_produce_box.add_child(_role_button(role, false))
			shown += 1
	if shown == 0:
		var l := Label.new()
		l.text = "nothing available\n(build the right structure first)"
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", Color(0.6, 0.62, 0.6))
		_produce_box.add_child(l)


## Everything any factory this player owns could currently turn out, ascending
## and de-duplicated. Asking per-structure would mean the menu changed
## depending on what happened to be selected, which hides the tech tree.
func _production_menu() -> PackedStringArray:
	var seen: Array = []
	for s in _match.production_structures(_me):
		for role in _match.world.economy.production_options(_me, s):
			if not seen.has(role):
				seen.append(role)
	seen.sort()
	var out := PackedStringArray()
	for r in seen:
		out.append(String(r))
	return out


## The picture on a build card. Rendered from the SAME model the game spawns
## (tools/icon_render.py), so the card and the thing that appears on the
## ground are recognisably one object -- a sidebar of names alone makes a
## player read six words to find a shape they already know.
##
## Cached: a Button holds its own reference, but the same role appears on
## every panel rebuild and load_icon is called on each one.
static var _icon_cache: Dictionary = {}


func _role_icon(role: String) -> Texture2D:
	if _icon_cache.has(role):
		return _icon_cache[role]
	var tex: Texture2D = null
	var stem := SimFactionData.model_stem_for(role,
		(_match.setup.players[_me] as SimPlayerSetup).faction, _match.epoch(_me))
	if stem != "":
		var path := "res://assets/icons/%s.png" % stem
		if ResourceLoader.exists(path):
			tex = load(path) as Texture2D
	_icon_cache[role] = tex
	return tex


func _role_button(role: String, is_build: bool) -> Button:
	var d := _match.world.economy.def_for(_me, role)
	var b := Button.new()
	b.text = "%s   %.0f" % [d.name if d else role, d.cost if d else 0.0]
	b.add_theme_font_size_override("font_size", 12)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	var ico := _role_icon(role)
	if ico != null:
		b.icon = ico
		b.expand_icon = true
		b.custom_minimum_size = Vector2(0, 44)
		b.add_theme_constant_override("h_separation", 8)
	b.tooltip_text = "%s\n%.0f credits, %.0f s%s" % [
		d.name if d else role, d.cost if d else 0.0,
		d.build_seconds if d else 0.0,
		"\nreach %.1f km" % SimArsenal.reach_km(role, _match.epoch(_me)) \
			if SimArsenal.is_combatant(role) else ""]
	if is_build:
		b.pressed.connect(func():
			_placing_role = role
			_refresh_panels(true))
		if _placing_role == role:
			b.modulate = COL_SELECTED
	else:
		b.pressed.connect(func(): _queue(role))
	return b


var _panel_accum := 0.0


func _update_hud(dt := 0.0) -> void:
	if _stats == null:
		return
	# The build menu is derived by scanning the roster against every structure
	# the player owns, which is far too much work to redo sixty times a second
	# for a list that changes when a factory is built or an epoch turns over.
	_panel_accum += dt
	if _panel_accum >= 0.5:
		_panel_accum = 0.0
		_refresh_panels()
	var p := _match.purse(_me)
	var st := _match.standing(_me)
	var e := _match.world.entities
	var lines := PackedStringArray()
	lines.append("BATTLE -- %s      t+%s%s" % [
		_match.terrain.name, _clock(_match.world.elapsed_s),
		"   [PAUSED]" if _paused else ("   x%.0f" % _speed if _speed > 1.5 else "")])
	# The docs/04 chain made visible: crude pumped, capped by refine capacity.
	# When the cap binds, the line says so and the amber marker appears.
	var choked := p.refine_capacity < p.extraction_per_min - 0.01
	var econ := "%.0f cr    +%.0f/min  -%.0f upkeep    power %.0f/%.0f    epoch %d%s" % [
		p.credits, p.income_per_min, p.upkeep_per_min,
		p.power_supply, p.power_draw, p.epoch,
		"  (advancing %.0f%%)" % (p.advance_progress * 100.0) if p.is_advancing() else ""]
	if choked:
		econ += "    refining %.0f/%.0f" % [p.refine_capacity, p.extraction_per_min]
	lines.append(econ)
	if _repair_btn != null and _sell_btn != null:
		var mine := _selected_structures()
		var e2 := _match.world.entities
		var hurt := false
		for i in mine:
			if e2.structure[i] < e2.structure_max[i] - 0.01:
				hurt = true
				break
		_repair_btn.disabled = not hurt
		_sell_btn.disabled = mine.is_empty()
	if _power_label != null:
		var sat := p.power_satisfaction()
		_power_label.visible = sat < 0.999
		if _power_label.visible:
			_power_label.text = "LOW POWER -- PRODUCTION AT %.0f%%  (%.0f/%.0f MW)" % [
				sat * 100.0, p.power_supply, p.power_draw]
	if _bottleneck_label != null:
		_bottleneck_label.visible = choked
		if choked:
			_bottleneck_label.text = ("REFINING %.0f/%.0f cr/min -- crude exceeds "
				+ "refinery capacity") % [p.refine_capacity, p.extraction_per_min]
	lines.append("%d units   %d structures   %d contacts held" % [
		st.combat_units + st.other_units if st else 0,
		st.structures if st else 0, _match.picture_for(_me).count()])
	# The player's OWN collapse is their truth and gets the red banner below.
	# The ENEMY's collapse state is deliberately NOT shown: SimVictory.standing()
	# counts the enemy's live production and supply structures from ground truth,
	# which is exactly the information the track table exists to withhold. When
	# they actually capitulate, the victory banner announces it -- that event is
	# public; the countdown to it is not.
	var collapsing := st != null and st.is_collapsing() and not _match.is_finished()
	if collapsing:
		lines.append("!! YOUR WAR MACHINE IS DESTROYED -- %.0f s to rebuild "
			% st.seconds_left() + "production or supply")
	if _collapse_label != null:
		_collapse_label.visible = collapsing
		if collapsing:
			_collapse_label.text = ("WAR MACHINE DESTROYED -- CAPITULATION IN %d s\n"
				+ "rebuild a production or supply structure") \
				% int(ceil(st.seconds_left()))
	if _placing_role != "":
		lines.append("PLACING %s -- left click to site it, right click to cancel%s"
			% [_placing_role, ("   [" + _placing_problem + "]") if _placing_problem else "   [clear]"])
	if _attack_move_armed:
		lines.append("ATTACK MOVE -- left click the objective; right click or ESC cancels")
	lines.append("")
	lines.append("WASD or arrows/edge pan · QE rotate · wheel zoom · LMB select · double-click same type "
		+ "· drag box · RMB move or attack a contact")
	lines.append("A attack-move · S stop · X hold fire · R radiate/silent "
		+ "· SPACE pause · TAB speed · H home")
	_stats.text = "\n".join(lines)

	# Production queue, made visible: each tab wears its queued count, and the
	# most-advanced job gets a live progress bar under the tab row. queue_of()
	# returns Job objects (def_key, role, progress()) for exactly this reason.
	var jobs: Array = _match.world.economy.queue_of(_me)
	var tab_count: Dictionary = {}
	var top_job: SimEconomy.Job = null
	for jv in jobs:
		var j := jv as SimEconomy.Job
		var jt: String = _tab_of(j.role, false)
		tab_count[jt] = int(tab_count.get(jt, 0)) + 1
		if top_job == null or j.progress() > top_job.progress():
			top_job = j
	if _tab_bar != null:
		for ti in range(_tab_bar.get_child_count()):
			var tb := _tab_bar.get_child(ti) as Button
			var tc: int = int(tab_count.get(TABS[ti], 0))
			tb.text = TAB_LABEL[TABS[ti]] + ((" %d" % tc) if tc > 0 else "")
	if _queue_label != null:
		_queue_label.visible = top_job != null
		_queue_bar.visible = top_job != null
		if top_job != null:
			_queue_label.text = "producing %s  %d%%   (%d queued)" % [
				top_job.role, int(top_job.progress() * 100.0), jobs.size()]
			_queue_bar.value = top_job.progress()

	var sel := PackedStringArray()
	if _selected.is_empty():
		sel.append("nothing selected")
	else:
		sel.append("SELECTED  %d" % _selected.size())
		for i in _selected.slice(0, 7):
			sel.append("  " + _describe_unit(i))
		if _selected.size() > 7:
			sel.append("  ... and %d more" % (_selected.size() - 7))
	_selection_info.text = "\n".join(sel)

	var log_lines := PackedStringArray()
	log_lines.append("COMBAT LOG")
	var cl: Array = _match.world.damage.combat_log
	for l in cl.slice(maxi(0, cl.size() - 6)):
		log_lines.append("  " + str(l))
	_log_label.text = "\n".join(log_lines)

	if _match.is_finished() and not _banner.visible:
		_banner.visible = true
		_banner.text = _match.victory.headline()
		_banner.add_theme_color_override("font_color",
			COL_ALLY if _match.outcome() == SimVictory.Outcome.VICTORY else COL_HOSTILE)


func _describe_unit(i: int) -> String:
	var e := _match.world.entities
	var bits := PackedStringArray()
	bits.append("%-22s %3.0f%%" % [e.names[i], e.structure_fraction(i) * 100.0])
	if e.fuel_capacity[i] > 0.0:
		bits.append("fuel %2.0f%%" % (e.fuel[i] / e.fuel_capacity[i] * 100.0))
	if e.components[i] != SimTypes.Component.NONE:
		bits.append("LOST: " + SimTypes.component_names(e.components[i]))
	if e.is_structure[i] == 1 and not _match.world.economy.is_operational(i):
		bits.append("building %.0f%%" % (_match.world.economy.construction_progress(i) * 100.0))
	if _match.world.fire_control.is_holding_fire(i):
		bits.append("HOLDING FIRE")
	elif _match.world.weapons.is_engaging(i):
		bits.append("engaging track %d" % _match.world.weapons.engagement_of(i))
	if _match.world.movement.is_attack_moving(i):
		bits.append("attack-moving")
	# The EMCON stance, so R has a consequence you can READ as well as the
	# pulse ring you can see. Only units with something to radiate get one.
	if _could_emit(i):
		bits.append("RADIATING" if e.emcon[i] == SimTypes.Emcon.RADIATE
			else "EMCON SILENT")
	return "  ".join(bits)


static func _clock(s: float) -> String:
	return "%d:%02d" % [int(s) / 60, int(s) % 60]


# ═══════════════════════════════════════════════════════════════════════════
# THE OVERLAY. Selection, health, and the picture.
# ═══════════════════════════════════════════════════════════════════════════

func _draw_overlay() -> void:
	if _rig == null or _match == null:
		return
	var cam: Camera3D = _rig.camera()
	var e := _match.world.entities

	# A PLATE behind every floating readout. Red Alert 2 never puts text
	# straight onto the battlefield -- every number it shows you sits in a
	# framed box -- and the reason is not decoration: outlined text over a
	# moving, mottled map is still text over a moving, mottled map, and the
	# eye has to do work to separate them. These are drawn here rather than
	# built as PanelContainers because the labels are positioned in absolute
	# pixels against screen corners, and the overlay sits behind them in the
	# same CanvasLayer, so a rect drawn here lands exactly underneath.
	for l: Label in [_stats, _selection_info, _log_label, _power_label,
			_bottleneck_label, _queue_label]:
		_plate(l)

	if _dragging:
		var a := _drag_from
		var b := _overlay.get_local_mouse_position()
		var r := Rect2(Vector2(minf(a.x, b.x), minf(a.y, b.y)), (b - a).abs())
		_overlay.draw_rect(r, Color(0.35, 0.85, 0.45, 0.14))
		_overlay.draw_rect(r, Color(0.5, 0.95, 0.6, 0.9), false, 1.0)

	# Own force: a bracket under everything selected, a damage bar over
	# everything hurt, and the unit's EMCON state -- because R with no visible
	# consequence is a key that does not exist. A unit actually RADIATING gets
	# an animated pulse ring (it is shouting, and everyone's ESM can hear it);
	# an emitter-capable unit held SILENT gets a small dim dot. Units with
	# nothing to radiate get neither, so the marks mean something.
	var now_s := Time.get_ticks_msec() / 1000.0
	for i in _match.world.entities.indices_of_faction(_my_team):
		var at := Vector3(e.pos_x[i], e.pos_y[i], e.pos_z[i])
		if cam.is_position_behind(at):
			continue
		var sp := cam.unproject_position(at)
		var mine := e.owner[i] == _me
		if _selected.has(i):
			_ring(sp, 13.0, COL_SELECTED)
		if _could_emit(i):
			if e.is_emitting(i):
				var phase := fmod(now_s * 0.8 + float(i) * 0.213, 1.0)
				var pc := COL_EMIT_RING
				pc.a = (1.0 - phase) * 0.55
				_overlay.draw_arc(sp, 9.0 + phase * 17.0, 0.0, TAU, 20, pc, 1.5)
			elif e.emcon[i] == SimTypes.Emcon.SILENT:
				_overlay.draw_circle(sp + Vector2(0, -14), 2.2, COL_SILENT_DOT)
		var frac := e.structure_fraction(i)
		if frac < 0.999:
			_bar(sp + Vector2(0, -22), 30.0, frac, COL_ALLY if mine else COL_OWN)
		elif not mine:
			_overlay.draw_circle(sp, 2.5, COL_ALLY)
		# Fuel, on everything SELECTED that carries a tank. Units genuinely
		# strand dry in this game, so the tank is combat information: blue is
		# fine, amber is "turn for home", red is a vehicle that no longer moves.
		if _selected.has(i) and e.fuel_capacity[i] > 0.0:
			_fuel_bar(sp + Vector2(0, -28), 30.0, e.fuel[i] / e.fuel_capacity[i])

	# Supply reach, for anything selected that HAS one -- the invisible circle
	# that decides docs/04, painted on the ground it applies to. A structure
	# still under construction shows it dimmed: that is where the reach WILL be.
	for i in _selected:
		if not e.is_alive(i):
			continue
		var sup := _match.world.economy.def_of(i)
		if sup == null or sup.supply_radius_m <= 0.0:
			continue
		var scol := COL_SUPPLY
		if e.is_structure[i] == 1 and not _match.world.economy.is_operational(i):
			scol.a *= 0.4
		_ground_ring(cam, e.pos_x[i], e.pos_z[i], sup.supply_radius_m, scol)

	_draw_picture(cam)

	# The flash line: two seconds of feedback for a keyboard action.
	if _flash_msg != "" and now_s < _flash_until:
		var vp := _overlay.get_rect().size
		_overlay.draw_string(ThemeDB.fallback_font,
			Vector2(vp.x * 0.5 - 160.0, vp.y - 64.0), _flash_msg,
			HORIZONTAL_ALIGNMENT_CENTER, 320.0, 15, Color(1, 1, 1, 0.92))

	if _placing_role != "" and not _headless:
		var sp := cam.unproject_position(_cursor_ground + Vector3(0, 3, 0))
		var ok := _placing_problem == ""
		_ring(sp, 22.0, COL_ALLY if ok else COL_HOSTILE)
		# Siting a supply structure IS choosing what that circle covers, so the
		# circle rides the cursor. Dim while the spot is invalid.
		var pd := _match.world.economy.def_for(_me, _placing_role)
		if pd != null and pd.supply_radius_m > 0.0:
			var prc := COL_SUPPLY
			if not ok:
				prc.a *= 0.35
			_ground_ring(cam, _cursor_ground.x, _cursor_ground.z,
				pd.supply_radius_m, prc)

	# Attack-move armed: the cursor wears a red reticle so the mode is visible
	# at the point of decision, not just in the status text.
	if _attack_move_armed and not _headless:
		var mp := _overlay.get_local_mouse_position()
		_ring(mp, 14.0, COL_HOSTILE)
		for k in range(4):
			var ang := TAU * 0.25 * float(k) + TAU * 0.125
			var dir := Vector2(cos(ang), sin(ang))
			_overlay.draw_line(mp + dir * 9.0, mp + dir * 19.0, COL_HOSTILE, 1.6)
		_overlay.draw_string(ThemeDB.fallback_font, mp + Vector2(18, -12),
			"ATTACK MOVE", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, COL_HOSTILE)


## THE ENEMY, exactly as the simulation says you know it -- NATO symbology.
##
##   SHAPE is the believed domain, and you only get one when classification
##   has reached CATEGORY -- before that, everything is a diamond:
##     air         semicircle arc, open at the bottom
##     surface     rectangle           ground   rectangle
##     subsurface  U-shape, open at the top
##     unknown     diamond
##   FILL is track quality: CONTACT hollow, TRACK half, FIRE_CONTROL+ solid.
##   ALPHA is age: a 30 s old plot is a memory and looks like one.
##   A short leader points along the believed velocity, length by speed.
##   A track that appeared or climbed a rung this frame flashes once.
##   An EMITTING hostile close to our force is tinted COL_ILLUM: our ESM says
##   that radar is painting us. All of it is SimTrack fields; nothing here
##   reads an enemy entity.
func _draw_picture(cam: Camera3D) -> void:
	var now_s := Time.get_ticks_msec() / 1000.0
	for entry in _track_screen:
		var tr := entry["track"] as SimTrack
		var id := int(entry["id"])
		var col := COL_HOSTILE if tr.classification >= SimTypes.Classification.CATEGORY \
			else COL_UNKNOWN
		if _illuminating.has(id):
			col = COL_ILLUM
		# Age fades a plot: a 30 s old contact is a memory, and it should look
		# like one rather than like a live target.
		col.a = clampf(1.0 - tr.age_s / 40.0, 0.30, 1.0)
		if entry["bearing"]:
			_draw_bearing(cam, tr, col)
			continue
		var at := entry["at"] as Vector2
		var r := 9.0
		var fill := _fill_of(tr.quality)
		if tr.classification < SimTypes.Classification.CATEGORY:
			_symbol_poly(_diamond_points(at, r), at, col, fill)
		else:
			match tr.category:
				SimTypes.Category.AIR:
					# Screen y grows downward, so PI..TAU is the TOP arc.
					_symbol_arc(at, r, col, fill, PI, TAU)
				SimTypes.Category.SUBSURFACE:
					_symbol_arc(at, r, col, fill, 0.0, PI)
				_:
					_symbol_poly(_rect_points(at, r), at, col, fill)
		_draw_leader(cam, tr, at, col)
		if tr.emitting:
			# Radiating: it can be seen a long way off and it can be shot at
			# with an anti-radiation missile. Worth marking.
			_overlay.draw_arc(at, r + 5.0, 0.0, TAU, 22,
				Color(COL_EMIT_RING, col.a), 1.0)
		var flashed: float = _track_flash.get(id, -10.0)
		var since := now_s - flashed
		if since < 0.6:
			var k := since / 0.6
			_overlay.draw_arc(at, r + 3.0 + k * 14.0, 0.0, TAU, 24,
				Color(1, 1, 1, (1.0 - k) * 0.9), 2.0)


## CONTACT is a shape you cannot shoot, TRACK half-earns the fill, and
## FIRE_CONTROL is solid -- the ladder, painted.
func _fill_of(quality: int) -> int:
	if quality >= SimTypes.TrackQuality.FIRE_CONTROL:
		return 2
	if quality == SimTypes.TrackQuality.TRACK:
		return 1
	return 0


## A short line from the symbol along the BELIEVED velocity -- the track's
## vel fields, which is what the sensors reported, not where the target went.
## Length scales with speed. A picture without vectors is a photo.
func _draw_leader(cam: Camera3D, tr: SimTrack, at: Vector2, col: Color) -> void:
	var speed := Vector2(tr.vel_x, tr.vel_z).length()
	if speed < 0.5:
		return
	# Project one second ahead with the same +4 m lift the plot itself uses,
	# so the screen direction is the true projected direction on any slope.
	var ahead := Vector3(tr.pos_x + tr.vel_x,
		maxf(tr.pos_y + tr.vel_y, 0.0) + 4.0, tr.pos_z + tr.vel_z)
	if cam.is_position_behind(ahead):
		return
	var dir := cam.unproject_position(ahead) - at
	if dir.length_squared() < 0.01:
		return
	dir = dir.normalized()
	var len_px := clampf(10.0 + speed * 0.55, 12.0, 40.0)
	_overlay.draw_line(at + dir * 10.0, at + dir * (10.0 + len_px), col, 1.6)


func _draw_bearing(cam: Camera3D, tr: SimTrack, col: Color) -> void:
	# Drawn FROM the own unit that is actually carrying a passive sensor named
	# in the track's contributors -- the thing that heard it -- dashed, with no
	# far end, because the data has no range in it at all.
	var e := _match.world.entities
	var hearer := _hearing_unit(tr)
	if hearer < 0:
		return
	var from3 := Vector3(e.pos_x[hearer], e.pos_y[hearer] + 3.0, e.pos_z[hearer])
	var out3 := from3 + Vector3(sin(tr.bearing_rad), 0.0, cos(tr.bearing_rad)) * 3000.0
	if cam.is_position_behind(from3) or cam.is_position_behind(out3):
		return
	var a := cam.unproject_position(from3)
	var b := cam.unproject_position(out3)
	_overlay.draw_dashed_line(a, b, col, 1.0, 9.0)
	# The classification guess rides the ray: passive sensors are BAD at
	# position and GOOD at naming things, and the label is where that shows.
	var what := _category_name(tr.category) \
		if tr.classification >= SimTypes.Classification.CATEGORY else "unknown"
	var label := "%s  brg %03d" % [what,
		wrapi(int(round(rad_to_deg(tr.bearing_rad))), 0, 360)]
	_overlay.draw_string(ThemeDB.fallback_font, a.lerp(b, 0.45) + Vector2(4, -4),
		label, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, col)


## Which of our units heard this bearing-only contact: the first own unit
## whose passive sensor is named in the track's contributors. If several ESM
## sets contributed the table does not record which cut is current, so the
## first carrier is the honest best guess; own_units[0] is the fallback.
func _hearing_unit(tr: SimTrack) -> int:
	var e := _match.world.entities
	var own := _match.own_units(_me)
	if own.is_empty():
		return -1
	for u in own:
		for s in e.sensors.get(u, []):
			var sd := s as SimSensorDef
			if sd.is_passive() and tr.contributors.has(sd.name):
				return u
	return own[0]


## Does this unit have anything that COULD radiate? Only these units get an
## EMCON mark at all, so the mark carries information instead of clutter.
func _could_emit(i: int) -> bool:
	var e := _match.world.entities
	if e.jammer_power[i] > 0.0:
		return true
	for s in e.sensors.get(i, []):
		var sd := s as SimSensorDef
		if sd.emits and not sd.is_passive():
			return true
	return false


static func _category_name(c: int) -> String:
	match c:
		SimTypes.Category.AIR: return "AIR"
		SimTypes.Category.SURFACE: return "SURFACE"
		SimTypes.Category.SUBSURFACE: return "SUB"
	return "GROUND"


func _ring(at: Vector2, r: float, col: Color) -> void:
	_overlay.draw_arc(at, r, 0.0, TAU, 24, col, 1.6)


# ── symbol geometry ──────────────────────────────────────────────────────────

func _diamond_points(at: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([
		at + Vector2(0, -r), at + Vector2(r, 0),
		at + Vector2(0, r), at + Vector2(-r, 0)])


func _rect_points(at: Vector2, r: float) -> PackedVector2Array:
	var hw := r * 1.15
	var hh := r * 0.72
	return PackedVector2Array([
		at + Vector2(-hw, -hh), at + Vector2(hw, -hh),
		at + Vector2(hw, hh), at + Vector2(-hw, hh)])


## A closed symbol: fill per the quality ladder, then the outline.
func _symbol_poly(pts: PackedVector2Array, at: Vector2, col: Color, fill: int) -> void:
	_fill_symbol(pts, at, col, fill)
	_overlay.draw_polyline(pts + PackedVector2Array([pts[0]]), col, 1.6)


## An arc symbol -- air and subsurface. The NATO glyph is OPEN (no chord), so
## the outline is just the arc; the fill closes across the chord implicitly.
func _symbol_arc(at: Vector2, r: float, col: Color, fill: int,
		a0: float, a1: float) -> void:
	var pts := PackedVector2Array()
	var n := 14
	for k in range(n + 1):
		var ang := a0 + (a1 - a0) * float(k) / float(n)
		pts.append(at + Vector2(cos(ang), sin(ang)) * r)
	_fill_symbol(pts, at, col, fill)
	_overlay.draw_polyline(pts, col, 1.6)


## fill 0 = hollow, 1 = the LEFT half (every symbol is symmetric about the
## vertical axis, so a half-plane clip reads as exactly half), 2 = solid.
func _fill_symbol(pts: PackedVector2Array, at: Vector2, col: Color, fill: int) -> void:
	if fill <= 0:
		return
	var p := pts if fill >= 2 else _clip_left_of(pts, at.x)
	if p.size() >= 3:
		_overlay.draw_colored_polygon(p, col)


## Sutherland-Hodgman against the half-plane x <= cx, treating pts as closed.
func _clip_left_of(pts: PackedVector2Array, cx: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for k in range(n):
		var a := pts[k]
		var b := pts[(k + 1) % n]
		var a_in := a.x <= cx
		var b_in := b.x <= cx
		if a_in:
			out.append(a)
		if a_in != b_in and absf(b.x - a.x) > 0.0001:
			out.append(a + (b - a) * ((cx - a.x) / (b.x - a.x)))
	return out


func _bar(at: Vector2, width: float, frac: float, full: Color) -> void:
	var r := Rect2(at - Vector2(width * 0.5, 2.0), Vector2(width, 4.0))
	_overlay.draw_rect(r, COL_BAR_BG)
	var col := full if frac > 0.6 else (COL_UNKNOWN if frac > 0.3 else COL_HOSTILE)
	_overlay.draw_rect(Rect2(r.position, Vector2(width * frac, 4.0)), col)


## The fuel gauge: thinner than the health bar so the pair never read as one
## stat. Blue while comfortable, amber under the RTB reserve, red when dry --
## and a dry tank still draws a sliver, because an empty bar looks like no bar.
func _fuel_bar(at: Vector2, width: float, frac: float) -> void:
	var r := Rect2(at - Vector2(width * 0.5, 1.5), Vector2(width, 3.0))
	_overlay.draw_rect(r, COL_BAR_BG)
	var col := COL_FUEL
	if frac <= 0.001:
		col = COL_HOSTILE
	elif frac < FUEL_RESERVE_FRAC:
		col = COL_UNKNOWN
	_overlay.draw_rect(Rect2(r.position,
		Vector2(width * clampf(maxf(frac, 0.03), 0.0, 1.0), 3.0)), col)


## A circle painted ON the terrain -- supply reach follows the ground, not a
## screen-space ellipse. Segments whose endpoints fall behind the camera are
## simply skipped; the ring can be kilometres across and partly off screen.
func _ground_ring(cam: Camera3D, cx: float, cz: float, radius: float,
		col: Color) -> void:
	var t := _match.terrain
	var prev := Vector2.ZERO
	var prev_ok := false
	var n := 64
	for k in range(n + 1):
		var ang := TAU * float(k) / float(n)
		var wx := cx + sin(ang) * radius
		var wz := cz + cos(ang) * radius
		var p3 := Vector3(wx, t.ground_under(wx, wz) + 2.0, wz)
		if cam.is_position_behind(p3):
			prev_ok = false
			continue
		var sp := cam.unproject_position(p3)
		if prev_ok:
			_overlay.draw_line(prev, sp, col, 1.4)
		prev = sp
		prev_ok = true


# ═══════════════════════════════════════════════════════════════════════════
# HEADLESS SELF-CHECK. Boots the game, runs it, and reports -- so CI can prove
# the scene is not merely constructible but actually playable.
# ═══════════════════════════════════════════════════════════════════════════

## Every check below is one thing a PLAYER does with the mouse, driven through
## exactly the code path the mouse drives. "It boots" is not the claim being
## made -- the claim is that selecting, moving, building, producing and killing
## all work, and this is what backs it.
func _run_headless_check() -> void:
	var e := _match.world.entities

	print("[skirmish] map                %s  %.1f x %.1f km" % [
		_match.terrain.name, _match.terrain.extent_x_m() / 1000.0,
		_match.terrain.extent_z_m() / 1000.0])
	_check("deployed", e.count() >= 20, "%d entities" % e.count())

	var armed := 0
	for i in range(e.count()):
		if _match.world.weapons.is_armed(i):
			armed += 1
	_check("armed", armed > 0, "%d of %d entities carry a weapon"
		% [armed, e.count()])

	# 1. SELECT. The same call the marquee makes, over the whole screen.
	for i in _match.own_units(_me):
		if e.is_structure[i] == 0 and not _selected.has(i):
			_selected.append(i)
	_check("select", _selected.size() >= 6, "%d units selected" % _selected.size())

	# 2. MOVE. Issued through SimCommandQueue, positioned by SimMovement's own
	#    formation grid, and checked by whether the units actually got there.
	var home := _match.base_position(_me)
	var goal := home + (Vector2(0, 0) - home).normalized() * 900.0
	var units := PackedInt32Array()
	for i in _selected:
		units.append(i)
	var start_d := _mean_distance_to(units, goal)
	var slots := _match.world.movement.formation_slots(units, goal.x, goal.y)
	for k in range(units.size()):
		_match.world.commands.move(_me, units[k], slots[k * 2], slots[k * 2 + 1])
	_match.run_ticks(1200)
	var end_d := _mean_distance_to(units, goal)
	_check("move order", end_d < start_d * 0.5,
		"mean range to the objective %.0f m -> %.0f m" % [start_d, end_d])

	# 3. BUILD. Place a structure, wait for it, and check it went operational.
	var before := e.count()
	var credits_before := _match.credits(_me)
	_placing_role = "power_plant"
	_try_place(Vector3(home.x + 70.0, 0.0, home.y + 30.0))
	_match.run_ticks(700)
	var built := -1
	for i in range(before, e.count()):
		if e.owner[i] == _me and _match.world.economy.role_of(i) == "power_plant":
			built = i
	_check("build", built >= 0 and _match.world.economy.is_operational(built),
		"power plant %d, %.0f cr spent" % [built, credits_before - _match.credits(_me)])

	# 4. PRODUCE. Queue a unit at a factory and wait for it to roll out armed.
	var have := e.count()
	_queue("mbt")
	# The order is a COMMAND, not a direct call: it sits in the queue until
	# SimWorld's command slot drains it on the next tick. Checking before that
	# tick would be checking the mailbox rather than the factory.
	_match.run_ticks(2)
	_check("queue", _match.world.economy.queue_of(_me).size() > 0,
		"%d jobs" % _match.world.economy.queue_of(_me).size())
	_match.run_ticks(1400)
	var produced := -1
	for i in range(have, e.count()):
		if e.owner[i] == _me and _match.world.economy.role_of(i) == "mbt":
			produced = i
	_check("produce", produced >= 0 and _match.world.weapons.is_armed(produced),
		"tank %d, armed %s" % [produced,
			str(produced >= 0 and _match.world.weapons.is_armed(produced))])

	# 5. THE PICTURE. Hostiles reach the screen as tracks or not at all.
	print("[skirmish] picture            %d contacts held at t+%.0f s"
		% [_match.picture_for(_me).count(), _match.world.elapsed_s])

	# 6. SOMETHING DIES. Rather than wait for the AI to come to us, send the
	#    force at the enemy base and let automatic fire control do the rest.
	var enemy := _match.base_position(1 - _me)
	var force := PackedInt32Array()
	for i in _match.own_units(_me):
		if e.is_structure[i] == 0:
			force.append(i)
	var attack := _match.world.movement.formation_slots(force, enemy.x, enemy.y)
	for k in range(force.size()):
		_match.world.commands.move(_me, force[k], attack[k * 2], attack[k * 2 + 1])
	_match.run_ticks(12000)
	_check("combat", _match.world.weapons.shots_fired > 0
			and _match.world.damage.kills > 0,
		"%d shots, %d kills, %d penetrations" % [
			_match.world.weapons.shots_fired, _match.world.damage.kills,
			_match.world.damage.penetrations])
	var cl: Array = _match.world.damage.combat_log
	if not cl.is_empty():
		print("[skirmish] last kill          " + str(cl[-1]))

	print("[skirmish] " + _match.victory.describe().replace("\n", "\n[skirmish] "))
	_check_audio()
	get_tree().quit(1 if _headless_failures > 0 else 0)


## Audio can be verified WITHOUT a sound device: the interesting thing is not
## whether a speaker moved but whether the mixing POLICY held -- that a battle
## firing over a thousand rounds did not commit a thousand voices.
func _check_audio() -> void:
	if _audio == null:
		_check("audio", false, "no mixer")
		return
	_check("audio bank", _audio.clip_count() >= 20,
		"%d clips loaded" % _audio.clip_count())

	# Drive a burst far louder than any real frame and confirm it is filtered.
	#
	# Place it AT THE CAMERA. Putting it at the origin made this assertion pass
	# for the wrong reason: the camera sits over the player's base 4.9 km away,
	# so every request was distance-culled and "400 requests -> 0 voices"
	# proved only that the distance filter worked. A cap that is never reached
	# is not a cap that has been tested.
	var cam := _camera_ground()
	var before: int = _audio.played
	var coal_before: int = _audio.coalesced
	for k in range(400):
		# spread them past the coalesce radius so this exercises the CAP
		_audio.at("fire_gun", cam.x + k * 30.0, cam.y, cam.z)
	var committed: int = _audio.played - before
	_check("audio voice cap", committed > 0 and committed <= _audio.max_voices,
		"400 requests at the camera -> %d voices, %d coalesced"
			% [committed, _audio.coalesced - coal_before])

	# And that something 40 km away is silent rather than merely quiet.
	var far_before: int = _audio.culled_distance
	_audio.at("impact_blast", cam.x + 40000.0, cam.y, cam.z + 40000.0)
	_check("audio distance cull", _audio.culled_distance > far_before,
		"a blast 40 km away is not voiced")

	# Priority cues must survive a saturated mixer.
	var p_before: int = _audio.played
	_audio.at("missile_warning", cam.x, cam.y, cam.z)
	_check("audio priority", _audio.played > p_before,
		"a launch warning is voiced even with every voice busy")
	print("[skirmish] audio            %s" % _audio.stats())


func _check(label: String, ok: bool, detail := "") -> void:
	print("[skirmish] %-18s %s  %s" % [label, "ok  " if ok else "FAIL", detail])
	if not ok:
		_headless_failures += 1


var _headless_failures := 0


func _mean_distance_to(units: PackedInt32Array, at: Vector2) -> float:
	if units.is_empty():
		return 0.0
	var e := _match.world.entities
	var total := 0.0
	for i in units:
		total += Vector2(e.pos_x[i], e.pos_z[i]).distance_to(at)
	return total / float(units.size())
