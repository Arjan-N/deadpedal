class_name LoopRoute
extends Route
## A closed circuit (the criterium course).
##
## Defined by the corners of a polygon; every corner is rounded with its own
## radius, so the road is made of exact straights and circular arcs. Distance
## 0 is the start/finish line and distances wrap around the lap, so riders'
## distances can just keep counting up (lap = distance / length).

## Corners of the course (x, z on flat ground), in riding order. The default
## is a town block with one corner cut off. Riding is clockwise (right turns).
@export var corners: PackedVector2Array = PackedVector2Array([
	Vector2(0, 30), Vector2(0, -150), Vector2(90, -150), Vector2(122, -118), Vector2(122, 30),
])
## Corner radii (m), one per corner (missing entries use the last one).
@export var corner_radii: PackedFloat32Array = PackedFloat32Array([16.0, 16.0, 22.0, 22.0, 16.0])
## Where the finish line is: this many metres along the first straight
## (the one leaving the first corner).
@export var finish_along_first_straight: float = 150.0

# One entry per segment (straights and arcs), starting at the first corner.
var _start_s: PackedFloat64Array = []
var _seg_length: PackedFloat64Array = []
var _curvature: PackedFloat64Array = []  # 1/m, + = turning right
var _start_pos: PackedVector2Array = []
var _start_heading: PackedFloat64Array = []  # radians, 0 = -Z, + = towards +X
var _loop_length: float = 0.0
var _finish_offset: float = 0.0


func ensure_built() -> void:
	if _built:
		return
	_built = true
	var n := corners.size()
	# Where each rounded corner starts and ends.
	var arc_in: Array[Vector2] = []
	var arc_out: Array[Vector2] = []
	var turn: Array[float] = []
	var radius: Array[float] = []
	for i in n:
		var p := corners[i]
		var d_in := (p - corners[(i - 1 + n) % n]).normalized()
		var d_out := (corners[(i + 1) % n] - p).normalized()
		var angle := wrapf(_heading(d_out) - _heading(d_in), -PI, PI)
		var r: float = corner_radii[mini(i, corner_radii.size() - 1)]
		var t := r * tan(absf(angle) * 0.5)
		arc_in.append(p - d_in * t)
		arc_out.append(p + d_out * t)
		turn.append(angle)
		radius.append(r)
	# Segments: straight from corner i's arc end to corner i+1's arc start,
	# then corner i+1's arc. Starting at the end of corner 0.
	var s := 0.0
	for i in n:
		var j := (i + 1) % n
		var a := arc_out[i]
		var b := arc_in[j]
		_add(s, a.distance_to(b), 0.0, a, _heading(b - a))
		s += a.distance_to(b)
		var arc_len := radius[j] * absf(turn[j])
		_add(s, arc_len, signf(turn[j]) / radius[j], b, _heading(b - a))
		s += arc_len
	_loop_length = s
	_finish_offset = finish_along_first_straight
	_length = _loop_length


func _add(start: float, length: float, k: float, pos: Vector2, heading: float) -> void:
	_start_s.append(start)
	_seg_length.append(length)
	_curvature.append(k)
	_start_pos.append(pos)
	_start_heading.append(heading)


static func _heading(dir: Vector2) -> float:
	return atan2(dir.x, -dir.y)


static func _forward(h: float) -> Vector3:
	return Vector3(sin(h), 0.0, -cos(h))


func get_length() -> float:
	ensure_built()
	return _loop_length


func get_frame(distance: float) -> Transform3D:
	ensure_built()
	var s := fposmod(distance + _finish_offset, _loop_length)
	var i := _segment_at(s)
	var into := s - _start_s[i]
	var h := _start_heading[i] + _curvature[i] * into
	return Transform3D(Basis.looking_at(_forward(h), Vector3.UP), _position_on(i, into))


func get_curvature(distance: float) -> float:
	ensure_built()
	return _curvature[_segment_at(fposmod(distance + _finish_offset, _loop_length))]


func _position_on(i: int, into: float) -> Vector3:
	var p0 := Vector3(_start_pos[i].x, 0.0, _start_pos[i].y)
	var h0 := _start_heading[i]
	var k := _curvature[i]
	if absf(k) < 1e-7:
		return p0 + _forward(h0) * into
	var h := h0 + k * into
	return p0 + Vector3((cos(h0) - cos(h)) / k, 0.0, -(sin(h) - sin(h0)) / k)


func _segment_at(s: float) -> int:
	# Few segments: a linear search is plenty.
	for i in range(_start_s.size() - 1, -1, -1):
		if s >= _start_s[i]:
			return i
	return 0


## Points around the whole lap (x, z), for the HUD map.
func get_outline(step: float = 5.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var d := 0.0
	while d < get_length():
		var p := get_point(d)
		pts.append(Vector2(p.x, p.z))
		d += step
	return pts
