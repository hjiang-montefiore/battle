extends Node3D
## A unit in the proving ground. Movement is a placeholder straight-line mover;
## the real thing belongs in the engine-agnostic sim (docs/06-architecture.md).

signal arrived

@export var speed := 9.0
@export var turn_rate := 2.2
@export var unit_name := ""
@export var faction := 0

var _target: Vector3
var _moving := false
var _ring: MeshInstance3D
var selected := false: set = _set_selected


func _ready() -> void:
	_target = position
	_ring = MeshInstance3D.new()
	var t := TorusMesh.new()
	t.inner_radius = 2.5
	t.outer_radius = 2.9
	t.rings = 24
	_ring.mesh = t
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.85, 0.35)
	m.emission_enabled = true
	m.emission = Color(0.15, 0.6, 0.2)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = m
	_ring.position.y = 0.06
	_ring.visible = false
	add_child(_ring)


func _set_selected(v: bool) -> void:
	selected = v
	if is_instance_valid(_ring):
		_ring.visible = v


func order_move(to: Vector3) -> void:
	_target = Vector3(to.x, 0.0, to.z)
	_moving = true


func _physics_process(dt: float) -> void:
	if not _moving:
		return
	var to := _target - position
	to.y = 0.0
	if to.length() < 0.6:
		_moving = false
		arrived.emit()
		return
	var want := atan2(to.x, to.z)
	rotation.y = rotate_toward(rotation.y, want, turn_rate * dt)
	# only drive forward once roughly aligned — tracked vehicles turn, then go
	if absf(angle_difference(rotation.y, want)) < 0.7:
		position += Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * speed * dt
