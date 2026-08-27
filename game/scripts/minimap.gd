extends Control
## THE MINIMAP. A 12.8 km map cannot be played through a keyhole.
##
## Self-contained: skirmish.gd instantiates it, hands it the match and the
## camera rig, and connects two signals. Everything else lives here. It READS
## the simulation and draws it; orders leave through the `order_at` signal and
## go back through skirmish.gd's one order path, so this file never touches
## SimCommandQueue at all.
##
## The same honesty rule as the main view applies: the player's own coalition
## is drawn from the entity store, THE ENEMY IS DRAWN FROM THE TRACK TABLE AND
## NOTHING ELSE. A contact fades on the map as it ages, and a bearing-only
## contact is a short RAY, not a dot, because a bearing is not a position.

## Left-click: fly the camera to this world point (x, z).
signal fly_to(world: Vector2)
## Right-click: issue a move order for the current selection to this point.
signal order_at(world: Vector2)

const SIZE_PX := 220.0
const MARGIN_PX := 10.0
## Dynamic layers repaint at 10 Hz. The terrain layer is painted ONCE, at
## match start, into a texture -- it never changes and never repaints.
const REDRAW_S := 0.1

const COL_OWN := Color(0.42, 0.78, 1.00)
const COL_ALLY := Color(0.45, 0.95, 0.60)
const COL_HOSTILE := Color(1.00, 0.36, 0.30)
const COL_UNKNOWN := Color(0.95, 0.78, 0.30)
const COL_VIEW := Color(0.95, 0.97, 0.95, 0.85)
const COL_FRAME := Color(0.55, 0.60, 0.55, 0.9)
const COL_EMIT := Color(1.0, 0.85, 0.2)

var _match: SimMatch
var _me := 0
var _my_team := 0
var _rig: Node3D
var _terrain_tex: ImageTexture
var _accum := 0.0
var _panning := false


## Called once by skirmish.gd. Anchors itself bottom-left and bakes the
## terrain layer.
func setup(m: SimMatch, me: int, my_team: int, rig: Node3D) -> void:
	_match = m
	_me = me
	_my_team = my_team
	_rig = rig

	var ex := m.terrain.extent_x_m()
	var ez := m.terrain.extent_z_m()
	var w := SIZE_PX
	var h := SIZE_PX * ez / maxf(ex, 1.0)
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = MARGIN_PX
	offset_right = MARGIN_PX + w
	offset_top = -(MARGIN_PX + h)
	offset_bottom = -MARGIN_PX

	clip_contents = true          # bearing rays and the view quad can run off-map
	mouse_filter = Control.MOUSE_FILTER_STOP
	_terrain_tex = _bake_terrain()


func _process(dt: float) -> void:
	if _match == null:
		return
	_accum += dt
	if _accum >= REDRAW_S:
		_accum = 0.0
		queue_redraw()


# ── the terrain layer, baked once ────────────────────────────────────────────

## One pixel per terrain cell -- the same grid line of sight is walked on, so
## the ridge that blocks the picture is exactly the ridge on the map.
func _bake_terrain() -> ImageTexture:
	var t := _match.terrain
	var img := Image.create(t.cells_x, t.cells_z, false, Image.FORMAT_RGB8)
	# Written ROTATED, to agree with _to_map below. See the note there: the
	# camera's screen-right is world -X and its screen-up is world +Z, so a map
	# baked cell-for-pixel comes out upside down and back to front.
	for cz in range(t.cells_z):
		for cx in range(t.cells_x):
			img.set_pixel(t.cells_x - 1 - cx, t.cells_z - 1 - cz,
				_terrain_colour(t.height_at_cell(cx, cz)))
	return ImageTexture.create_from_image(img)


## Water dark blue by depth; land dark green rising to a pale tan, with the
## same 40 m contour banding as the world mesh so the ridge line is a hard
## edge on the map, not a smear.
func _terrain_colour(h: float) -> Color:
	if h < 0.0:
		return Color(0.03, 0.09, 0.20).lerp(Color(0.08, 0.22, 0.38),
			clampf(1.0 + h / 200.0, 0.0, 1.0))
	var t: float = clampf(h / 420.0, 0.0, 1.0)
	var c := Color(0.13, 0.20, 0.09).lerp(Color(0.60, 0.55, 0.40), t)
	if int(floor(h / 40.0)) % 2 == 1:
		c = c.darkened(0.15)
	return c


# ── coordinates ──────────────────────────────────────────────────────────────

## World metres -> minimap pixels, MATCHING WHAT THE SCREEN SHOWS.
##
## The mapping is inverted on both axes, and that is not arbitrary. The rig
## parks the camera at target + (-sin(yaw), 0, -cos(yaw)) * dist, so at the
## default yaw it sits at negative Z looking toward POSITIVE Z: the far
## distance up the screen is +Z, and screen-right works out to -X. A minimap
## drawn the obvious way -- +X rightward, +Z downward -- is therefore rotated
## a half turn from the battle the player is looking at, and every drag of the
## view sends the marker the wrong way. Both axes flip here, in one place,
## and the terrain bake and _to_world follow.
func _to_map(x: float, z: float) -> Vector2:
	var t := _match.terrain
	return Vector2((0.5 - x / t.extent_x_m()) * size.x,
		(0.5 - z / t.extent_z_m()) * size.y)


func _to_world(p: Vector2) -> Vector2:
	var t := _match.terrain
	var wx := (0.5 - clampf(p.x / size.x, 0.0, 1.0)) * t.extent_x_m()
	var wz := (0.5 - clampf(p.y / size.y, 0.0, 1.0)) * t.extent_z_m()
	return Vector2(wx, wz)


## Oil fields, drawn under everything else: they never move, and a player
## planning an expansion is reading the map for exactly this.
## Ore, in the gold it is drawn on the ground in. Sized by what is LEFT, so
## the map shows a worked-out patch shrinking away.
func _draw_ore() -> void:
	var econ := _match.world.economy
	if econ == null:
		return
	for k in range(mini(econ.ore_fields.size(), econ.ore_remaining.size())):
		if econ.ore_remaining[k] <= 0.0:
			continue
		var f: Vector2 = econ.ore_fields[k]
		var frac: float = clampf(econ.ore_remaining[k] / 12000.0, 0.15, 1.0)
		draw_circle(_to_map(f.x, f.y), 2.5 + 4.0 * frac, Color(0.82, 0.63, 0.16))


func _draw_oil() -> void:
	var econ := _match.world.economy
	if econ == null:
		return
	for k in range(econ.oil_fields.size()):
		var f: Vector2 = econ.oil_fields[k]
		var p := _to_map(f.x, f.y)
		var held := econ.derrick_on(k)
		# Amber when nobody is pumping it, dim when somebody already is --
		# the map should show what is still worth taking.
		var col := Color(0.86, 0.62, 0.16) if held < 0 else Color(0.40, 0.33, 0.18)
		draw_circle(p, 3.0, col)
		if held < 0:
			draw_arc(p, 5.0, 0.0, TAU, 12, col, 1.0)


# ── the dynamic layers ───────────────────────────────────────────────────────

func _draw() -> void:
	if _match == null:
		return
	if _terrain_tex != null:
		draw_texture_rect(_terrain_tex, Rect2(Vector2.ZERO, size), false)
	_draw_ore()
	_draw_oil()

	# OWN FORCES, from ground truth: dots for units, squares for structures.
	var e := _match.world.entities
	for i in e.indices_of_faction(_my_team):
		var p := _to_map(e.pos_x[i], e.pos_z[i])
		var col := COL_OWN if e.owner[i] == _me else COL_ALLY
		if e.is_structure[i] == 1:
			draw_rect(Rect2(p - Vector2(2.5, 2.5), Vector2(5.0, 5.0)), col)
		else:
			draw_circle(p, 1.8, col)

	_draw_picture()
	_draw_view_quad()
	draw_rect(Rect2(Vector2.ZERO, size), COL_FRAME, false, 1.0)


## THE PICTURE, NOT THE TRUTH. Same table, same fade, same shapes-by-quality
## logic as the main view: a decaying contact visibly dims and a lost one is
## simply gone from the map, because it is gone from the table.
func _draw_picture() -> void:
	var table := _match.picture_for(_me)
	for id in table.track_ids():
		var tr := table.get_track(id)
		if tr == null or tr.quality == SimTypes.TrackQuality.NONE:
			continue
		var col := COL_HOSTILE if tr.classification >= SimTypes.Classification.CATEGORY \
			else COL_UNKNOWN
		col.a = clampf(1.0 - tr.age_s / 40.0, 0.30, 1.0)
		if tr.bearing_only:
			_draw_bearing(tr, col)
			continue
		var p := _to_map(tr.pos_x, tr.pos_z)
		match tr.quality:
			SimTypes.TrackQuality.FIRE_CONTROL, SimTypes.TrackQuality.TERMINAL:
				draw_circle(p, 3.0, col)                       # filled: shootable
			SimTypes.TrackQuality.TRACK:
				draw_arc(p, 2.8, 0.0, TAU, 12, col, 1.3)       # hollow: position only
			_:
				col.a *= 0.6
				draw_arc(p, 2.2, 0.0, TAU, 10, col, 1.0)       # dim: something there
		if tr.emitting:
			draw_arc(p, 5.0, 0.0, TAU, 14, Color(COL_EMIT, col.a), 1.0)


## A bearing has no range, so it has no dot. A short dashed ray out along the
## bearing from our own force -- the same origin convention the main view uses.
func _draw_bearing(tr: SimTrack, col: Color) -> void:
	var own := _match.own_units(_me)
	if own.is_empty():
		return
	var e := _match.world.entities
	var ox := e.pos_x[own[0]]
	var oz := e.pos_z[own[0]]
	var from := _to_map(ox, oz)
	var to := _to_map(ox + sin(tr.bearing_rad) * 2500.0,
		oz + cos(tr.bearing_rad) * 2500.0)
	draw_dashed_line(from, to, col, 1.0, 4.0)


## The camera frustum's four corner rays, dropped onto the ground plane and
## joined up -- the trapezoid every RTS player steers by.
func _draw_view_quad() -> void:
	if _rig == null:
		return
	var cam: Camera3D = _rig.call("camera")
	if cam == null or not cam.is_inside_tree():
		return
	var vp := cam.get_viewport().get_visible_rect().size
	if vp.x <= 0.0 or vp.y <= 0.0:
		return
	var ground_y: float = _rig.position.y
	var pts := PackedVector2Array()
	for c in [Vector2.ZERO, Vector2(vp.x, 0.0), vp, Vector2(0.0, vp.y)]:
		var from := cam.project_ray_origin(c)
		var dir := cam.project_ray_normal(c)
		# A corner ray looking above the horizon never lands; cap it so the
		# quad's far edge sits a sane distance out instead of at infinity.
		var travel := 6000.0
		if dir.y < -0.001:
			travel = minf((ground_y - from.y) / dir.y, 20000.0)
		var w := from + dir * travel
		pts.append(_to_map(w.x, w.z))
	pts.append(pts[0])
	draw_polyline(pts, COL_VIEW, 1.2)


# ── input ────────────────────────────────────────────────────────────────────

## Left click (or drag) flies the camera; right click orders the selection
## there. Both leave as signals carrying a WORLD point -- this Control knows
## nothing about the rig's internals or the command queue.
func _gui_input(ev: InputEvent) -> void:
	if ev is InputEventMouseButton:
		var mb := ev as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			_panning = mb.pressed
			if mb.pressed:
				fly_to.emit(_to_world(mb.position))
			accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			order_at.emit(_to_world(mb.position))
			accept_event()
	elif ev is InputEventMouseMotion and _panning:
		fly_to.emit(_to_world((ev as InputEventMouseMotion).position))
		accept_event()
