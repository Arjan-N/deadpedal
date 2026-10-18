class_name Route
extends Path3D
## The predefined road everything moves along.
##
## Gameplay positions are stored as "distance along the route" (metres) plus a
## sideways lane offset. This keeps riders and zombies on the road without any
## physics, and makes multiplayer sync trivial (one float per rider).
## Branching routes can later be added as several Route nodes with junctions.

## Points the road passes through (x/z on flat ground). Edit these to reshape
## the road; tangents are generated automatically for smooth curves.
@export var control_points: PackedVector3Array = PackedVector3Array([
	Vector3(0, 0, 0), Vector3(0, 0, -53.3), Vector3(0, 0, -106.7), Vector3(0, 0, -160),
	Vector3(2.6, 0, -209.9), Vector3(10.4, 0, -259.3), Vector3(23.4, 0, -307.6), Vector3(41.9, 0, -364.7),
	Vector3(60.5, 0, -421.7), Vector3(72.8, 0, -473.6), Vector3(76.5, 0, -526.8), Vector3(71.5, 0, -579.9),
	Vector3(62.8, 0, -629.2), Vector3(54.2, 0, -678.4), Vector3(48.7, 0, -724.8), Vector3(48.7, 0, -771.4),
	Vector3(54.2, 0, -817.8), Vector3(62.8, 0, -867), Vector3(71.5, 0, -916.3), Vector3(80.2, 0, -965.5),
	Vector3(87, 0, -1025.1), Vector3(86.5, 0, -1085.1), Vector3(83.7, 0, -1125), Vector3(80.9, 0, -1164.9),
	Vector3(80.9, 0, -1218.3), Vector3(88.3, 0, -1271.1), Vector3(103, 0, -1322.3), Vector3(119, 0, -1366.2),
	Vector3(134.9, 0, -1410), Vector3(150.9, 0, -1453.9), Vector3(163.8, 0, -1502.2), Vector3(168.2, 0, -1552),
	Vector3(163.8, 0, -1601.8), Vector3(153.4, 0, -1660.9), Vector3(143, 0, -1720), Vector3(137, 0, -1762.9),
	Vector3(134, 0, -1806.1), Vector3(134, 0, -1849.5), Vector3(135.7, 0, -1899.4), Vector3(137.4, 0, -1949.4),
	Vector3(139.2, 0, -1999.4),
])
## How rounded the corners are (0 = sharp, 0.5 = very round).
@export_range(0.0, 0.5) var smoothness: float = 0.33

var _length: float = 0.0
var _built := false


func _enter_tree() -> void:
	ensure_built()


func ensure_built() -> void:
	if _built:
		return
	_built = true
	var c := Curve3D.new()
	c.bake_interval = 0.5
	var n := control_points.size()
	for i in n:
		var p := control_points[i]
		var prev := control_points[maxi(i - 1, 0)]
		var next := control_points[mini(i + 1, n - 1)]
		# Catmull-Rom style tangent: direction from previous to next point.
		var tangent := (next - prev) * smoothness * 0.5
		c.add_point(p, -tangent, tangent)
	curve = c
	_length = c.get_baked_length()


func get_length() -> float:
	ensure_built()
	return _length


## Transform at a distance along the road. Basis: -Z = forward, +X = right.
func get_frame(distance: float) -> Transform3D:
	ensure_built()
	var d := clampf(distance, 0.0, _length)
	var a := curve.sample_baked(maxf(d - 0.5, 0.0), true)
	var b := curve.sample_baked(minf(d + 0.5, _length), true)
	var pos := curve.sample_baked(d, true)
	var forward := (b - a)
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		forward = Vector3.FORWARD
	var frame_basis := Basis.looking_at(forward.normalized(), Vector3.UP)
	# The Route node is expected to sit at the world origin.
	return Transform3D(frame_basis, pos)


## World position at a distance along the road, shifted sideways by `lateral`
## metres (positive = right).
func get_point(distance: float, lateral: float = 0.0) -> Vector3:
	var f := get_frame(distance)
	return f.origin + f.basis.x * lateral


## Signed heading change (radians per metre) - used to lean riders into bends.
func get_curvature(distance: float) -> float:
	var f1 := get_frame(distance - 4.0).basis.z
	var f2 := get_frame(distance + 4.0).basis.z
	return f1.signed_angle_to(f2, Vector3.UP) / 8.0
