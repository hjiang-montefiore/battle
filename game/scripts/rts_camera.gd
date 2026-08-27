extends Node3D
## RTS camera rig: WASD / edge pan, wheel zoom, Q-E orbit.
## The rig is a Node3D; the Camera3D is a child at a fixed pitch, so panning
## moves the ground point being looked at rather than the camera itself.

@export var pan_speed := 42.0
## Screen-edge pan band, pixels. Red Alert 2 is played with the POINTER, not
## with WASD -- the keyboard is for groups and orders. At 6 px this band was
## effectively unhittable and the camera felt keyboard-only, which is the first
## thing that made the controls feel wrong.
@export var edge_margin := 28.0
## The outer few pixels of that band pan faster, so a deliberate shove at the
## screen edge crosses the map while a drifting pointer only nudges it.
@export var edge_boost := 2.6

## Screen rectangles the pointer must not pan from. The RTS sidebar occupies
## the ENTIRE right edge, which is exactly where the edge-pan band lives -- so
## without this, reaching for a build button scrolls the map out from under the
## player. The scene that owns the panel registers its rect here; the rig knows
## nothing about what the rectangles are for.
var ui_blockers: Array[Rect2] = []


func pointer_over_ui() -> bool:
	var m := get_viewport().get_mouse_position()
	for r in ui_blockers:
		if r.has_point(m):
			return true
	return false
## ZOOM IS IN METRES OF CAMERA-TO-GROUND DISTANCE, and the useful range depends
## entirely on the scene. THE DEFAULTS BELOW ARE THE MODEL VIEWER'S, not a
## skirmish's: proving_ground.gd adds this rig with no overrides at all onto a
## 400x400 m pad, where 18-140 m is the right range and 200 m of bounds is the
## pad. A skirmish map is 6.4-8 km and overrides all four. Do not "fix" these to
## skirmish numbers -- that silently breaks the only scene that relies on them.
##
## Useful conversion, because every judgement about scale needs it: with a 48
## deg vertical FOV at 16:9, the ground width across the middle of the screen is
## almost exactly 1.58 x the zoom distance. So 200 m of zoom shows ~317 m of
## ground, and a 9 m tank is then ~45 px wide on a 1600 px screen.
@export var zoom_min := 18.0
@export var zoom_max := 140.0
## Where the view OPENS. This is the single number that decides whether the
## game reads as an RTS or as a map with specks on it, and it matters far more
## than zoom_max: a player forms their impression of scale before they ever
## touch the wheel. Kept as an export so the scene that knows its own map size
## sets it, rather than callers poking the private _dist.
@export var zoom_start := 62.0
@export var pitch_near := 38.0   ## shallower when zoomed in
@export var pitch_far := 58.0    ## more top-down when zoomed out
## Half-extent of the playfield, so the rig is held inside it -- holding one pan
## key used to walk the view off the map into bare sky with no cue where home
## was. 200 m is the model viewer's pad; a skirmish passes half its map extent.
@export var bounds_m := 200.0

var _dist := 62.0
var _yaw := 0.0
var _cam: Camera3D


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 48.0
	add_child(_cam)
	# Exports are assigned before add_child(), so the opening zoom is honoured
	# and is clamped into whatever range this scene declared.
	_dist = clampf(zoom_start, zoom_min, zoom_max)
	_apply()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
		if pointer_over_ui():
			return
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_dist = clampf(_dist * 0.90, zoom_min, zoom_max)
			_apply()
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_dist = clampf(_dist * 1.11, zoom_min, zoom_max)
			_apply()


func _process(dt: float) -> void:
	var move := Vector2.ZERO
	if Input.is_action_pressed(&"cam_forward"): move.y -= 1.0
	if Input.is_action_pressed(&"cam_back"):    move.y += 1.0
	if Input.is_action_pressed(&"cam_left"):    move.x -= 1.0
	if Input.is_action_pressed(&"cam_right"):   move.x += 1.0

	# screen-edge pan, the RTS convention
	var vp := get_viewport().get_visible_rect().size
	var m := get_viewport().get_mouse_position()
	var boost := 1.0
	if m.x >= 0.0 and m.y >= 0.0 and m.x <= vp.x and m.y <= vp.y \
			and not pointer_over_ui():
		# Depth INTO the band scales speed: brushing the edge drifts, pinning
		# the pointer against it moves properly.
		if m.x < edge_margin:
			move.x -= 1.0
			boost = maxf(boost, lerpf(1.0, edge_boost, 1.0 - m.x / edge_margin))
		elif m.x > vp.x - edge_margin:
			move.x += 1.0
			boost = maxf(boost, lerpf(1.0, edge_boost, 1.0 - (vp.x - m.x) / edge_margin))
		if m.y < edge_margin:
			move.y -= 1.0
			boost = maxf(boost, lerpf(1.0, edge_boost, 1.0 - m.y / edge_margin))
		elif m.y > vp.y - edge_margin:
			move.y += 1.0
			boost = maxf(boost, lerpf(1.0, edge_boost, 1.0 - (vp.y - m.y) / edge_margin))

	if Input.is_action_pressed(&"cam_rot_l"): _yaw += dt * 1.1; _apply()
	if Input.is_action_pressed(&"cam_rot_r"): _yaw -= dt * 1.1; _apply()

	if move != Vector2.ZERO:
		move = move.normalized() * boost
		# pan in the camera's own ground plane, scaled by zoom so it feels
		# constant on screen at any altitude
		# camera forward is (sin, cos); move.y is screen convention (W = -1), so
		# both basis vectors are negated to cancel that sign
		var f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var r := Vector3(-cos(_yaw), 0.0, sin(_yaw))
		# Scaling by zoom makes pan_speed mean SCREENS PER SECOND rather than
		# metres per second, which is what a player actually feels. The
		# reference is the opening zoom, so pan_speed is calibrated against the
		# view the scene opens on; it used to be a bare 62.0, which was the old
		# hardcoded opening distance and silently meant "metres per second" for
		# any scene that opened anywhere else.
		var scale := _dist / maxf(zoom_start, 1.0)
		position += (r * move.x + f * move.y) * pan_speed * scale * dt
		_clamp_to_bounds()


## Keep the aim point on the map. The limit shrinks as you zoom out, so the
## map edge stops at the frame edge instead of sliding into the middle.
func _clamp_to_bounds() -> void:
	var margin: float = maxf(bounds_m - _dist * 0.45, 20.0)
	position.x = clampf(position.x, -margin, margin)
	position.z = clampf(position.z, -margin, margin)


func _apply() -> void:
	var t := inverse_lerp(zoom_min, zoom_max, _dist)
	var pitch := deg_to_rad(lerp(pitch_near, pitch_far, t))
	var back := Vector3(-sin(_yaw), 0.0, -cos(_yaw)) * cos(pitch) * _dist
	_cam.position = back + Vector3(0.0, sin(pitch) * _dist, 0.0)
	# _cam.position is local to the rig; look_at works in global space and the
	# rig's own origin is the ground point we orbit
	_cam.look_at(global_position, Vector3.UP)


func camera() -> Camera3D:
	return _cam


func zoom_distance() -> float:
	return _dist
