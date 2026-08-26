extends Node3D
## RTS camera rig: WASD / edge pan, wheel zoom, Q-E orbit.
## The rig is a Node3D; the Camera3D is a child at a fixed pitch, so panning
## moves the ground point being looked at rather than the camera itself.

@export var pan_speed := 42.0
@export var edge_margin := 6.0
@export var zoom_min := 18.0
@export var zoom_max := 140.0
@export var pitch_near := 38.0   ## shallower when zoomed in
@export var pitch_far := 58.0    ## more top-down when zoomed out
## Half-extent of the playfield. The ground plane is 400x400 m, so the rig is
## held inside it -- holding one pan key used to walk the view off the map into
## bare sky with no cue where home was.
@export var bounds_m := 200.0

var _dist := 62.0
var _yaw := 0.0
var _cam: Camera3D


func _ready() -> void:
	_cam = Camera3D.new()
	_cam.fov = 48.0
	add_child(_cam)
	_apply()


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton and e.pressed:
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
	if m.x >= 0.0 and m.y >= 0.0 and m.x <= vp.x and m.y <= vp.y:
		if m.x < edge_margin: move.x -= 1.0
		elif m.x > vp.x - edge_margin: move.x += 1.0
		if m.y < edge_margin: move.y -= 1.0
		elif m.y > vp.y - edge_margin: move.y += 1.0

	if Input.is_action_pressed(&"cam_rot_l"): _yaw += dt * 1.1; _apply()
	if Input.is_action_pressed(&"cam_rot_r"): _yaw -= dt * 1.1; _apply()

	if move != Vector2.ZERO:
		move = move.normalized()
		# pan in the camera's own ground plane, scaled by zoom so it feels
		# constant on screen at any altitude
		# camera forward is (sin, cos); move.y is screen convention (W = -1), so
		# both basis vectors are negated to cancel that sign
		var f := Vector3(-sin(_yaw), 0.0, -cos(_yaw))
		var r := Vector3(-cos(_yaw), 0.0, sin(_yaw))
		var scale := _dist / 62.0
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
