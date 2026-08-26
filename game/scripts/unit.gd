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

## The model's own bounds, in unit-local space. Selection, the ring and
## formation spacing all read this instead of guessing a radius: hulls run from
## 5.8 m to 12.2 m long, and one fixed disc cannot serve both.
var footprint_size := Vector3(6.0, 2.5, 6.0)
var footprint_centre := Vector3.ZERO
var _footprint_set := false


func _ready() -> void:
	_target = position
	_ring = MeshInstance3D.new()
	_ring.mesh = TorusMesh.new()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.25, 0.85, 0.35)
	m.emission_enabled = true
	m.emission = Color(0.15, 0.6, 0.2)
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_ring.material_override = m
	_ring.position.y = 0.06
	_ring.visible = false
	add_child(_ring)
	_size_ring()


## Called at spawn with the instantiated model's AABB.
func set_footprint(aabb: AABB) -> void:
	footprint_size = aabb.size
	footprint_centre = aabb.position + aabb.size * 0.5
	_footprint_set = true
	_size_ring()


## The ring should describe what is actually selectable. At a fixed 5.8 m it
## was shorter than the hull of ten of the eleven units and hung off the node
## origin rather than the hull centre, so it sat inside the silhouette.
func _size_ring() -> void:
	if not is_instance_valid(_ring):
		return
	var r: float = maxf(footprint_size.x, footprint_size.z) * 0.5 + 0.6
	var t := _ring.mesh as TorusMesh
	t.inner_radius = maxf(r - 0.35, 0.3)
	t.outer_radius = r
	t.rings = 24
	_ring.position = Vector3(footprint_centre.x, 0.06, footprint_centre.z)


## Ray against this unit's oriented bounding box. Returns the distance along
## `dir` to the entry point, or -1.0 for a miss.
##
## This replaces projecting the click to the ground plane and taking the
## nearest origin within a fixed disc, which missed 40% of on-hull clicks at
## close zoom and picked the WRONG vehicle for a third of them in a delivered
## formation -- because players click the visible hull, which is metres above
## the ground the ray was being tested against.
func ray_distance(from: Vector3, dir: Vector3) -> float:
	# Work in local space: the box is axis-aligned there.
	var inv := global_transform.affine_inverse()
	var o := inv * from
	var d := inv.basis * dir
	var half := footprint_size * 0.5
	var lo := footprint_centre - half
	var hi := footprint_centre + half
	var tmin := -1e20
	var tmax := 1e20
	for axis in range(3):
		var od: float = d[axis]
		var oo: float = o[axis]
		if absf(od) < 1e-9:
			if oo < lo[axis] or oo > hi[axis]:
				return -1.0
			continue
		var t1: float = (lo[axis] - oo) / od
		var t2: float = (hi[axis] - oo) / od
		if t1 > t2:
			var tmp := t1; t1 = t2; t2 = tmp
		tmin = maxf(tmin, t1)
		tmax = minf(tmax, t2)
		if tmin > tmax:
			return -1.0
	if tmax < 0.0:
		return -1.0
	return maxf(tmin, 0.0)


## Where the selection marker belongs on screen -- the hull centre, not the
## node origin, which on the SPH is 2.5 m out.
func marker_point() -> Vector3:
	return global_position + Vector3(footprint_centre.x,
		maxf(footprint_size.y * 0.5, 0.8), footprint_centre.z)


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
	# Clamp onto the waypoint rather than halting anywhere inside a 0.6 m
	# radius, so a unit finishes where it was actually sent.
	var step := speed * dt
	if to.length() <= step:
		position = Vector3(_target.x, position.y, _target.z)
		_moving = false
		arrived.emit()
		return
	var want := atan2(to.x, to.z)
	rotation.y = rotate_toward(rotation.y, want, turn_rate * dt)
	# only drive forward once roughly aligned — tracked vehicles turn, then go
	if absf(angle_difference(rotation.y, want)) < 0.7:
		position += Vector3(sin(rotation.y), 0.0, cos(rotation.y)) * speed * dt
