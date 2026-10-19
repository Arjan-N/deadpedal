class_name EndlessRoute
extends Route
## A road that never ends, for Endless Survival.
##
## Built from straights and gentle arcs generated one after another from a
## seed, so every player's game produces exactly the same road. Positions are
## computed analytically (no spline baking), so querying any distance is exact
## and cheap, however far the riders get. Same API as Route.

## Same seed = same road. Set by the mission before the road is used.
var seed_value: int = 1
## Turns are steered back towards the main direction (-Z) once the road has
## drifted more than this far off it, so it never loops back on itself.
@export var max_heading_drift_deg: float = 40.0

# One entry per segment.
var _start_d: PackedFloat64Array = []
var _seg_length: PackedFloat64Array = []
var _curvature: PackedFloat64Array = []  # 1/m, + = turning right
var _start_pos: PackedVector3Array = []
var _start_heading: PackedFloat64Array = []  # radians, 0 = -Z, + = towards +X


func ensure_built() -> void:
	pass  # generated on demand instead of from control points


## Restarts the road with a new seed.
func reset(p_seed: int) -> void:
	seed_value = p_seed
	_start_d.clear()
	_seg_length.clear()
	_curvature.clear()
	_start_pos.clear()
	_start_heading.clear()


func get_length() -> float:
	return 1.0e7  # effectively endless


func get_frame(distance: float) -> Transform3D:
	_generate_to(distance + 50.0)
	if distance < 0.0:
		# Behind the start: carry straight on backwards.
		var fwd0 := _forward(_start_heading[0])
		return Transform3D(Basis.looking_at(fwd0, Vector3.UP), _start_pos[0] + fwd0 * distance)
	var i := _segment_at(distance)
	var s := distance - _start_d[i]
	var h := _start_heading[i] + _curvature[i] * s
	return Transform3D(Basis.looking_at(_forward(h), Vector3.UP), _position_on(i, s))


## Position s metres into segment i.
func _position_on(i: int, s: float) -> Vector3:
	var h0 := _start_heading[i]
	var k := _curvature[i]
	if absf(k) < 1e-7:
		return _start_pos[i] + _forward(h0) * s
	# Exact position on a circular arc.
	var h := h0 + k * s
	return _start_pos[i] + Vector3((cos(h0) - cos(h)) / k, 0.0, -(sin(h) - sin(h0)) / k)


static func _forward(heading: float) -> Vector3:
	return Vector3(sin(heading), 0.0, -cos(heading))


func _segment_at(distance: float) -> int:
	# Binary search for the segment containing this distance.
	var lo := 0
	var hi := _start_d.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if _start_d[mid] <= distance:
			lo = mid
		else:
			hi = mid - 1
	return lo


func _generate_to(distance: float) -> void:
	while _start_d.is_empty() or _start_d[_start_d.size() - 1] + _seg_length[_seg_length.size() - 1] < distance:
		_add_segment()


func _add_segment() -> void:
	var i := _start_d.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 1000003 + i * 7919  # same on every machine
	var start_d := 0.0
	var start_pos := Vector3.ZERO
	var heading := 0.0
	if i > 0:
		start_d = _start_d[i - 1] + _seg_length[i - 1]
		start_pos = _position_on(i - 1, _seg_length[i - 1])
		heading = _start_heading[i - 1] + _curvature[i - 1] * _seg_length[i - 1]
	var length: float
	var curvature := 0.0
	if i < 2 or i % 2 == 0:
		length = rng.randf_range(90.0, 220.0)  # straight (the start is straight)
	else:
		length = rng.randf_range(70.0, 160.0)
		var turn := deg_to_rad(rng.randf_range(10.0, 32.0))
		var direction := -1.0 if rng.randf() < 0.5 else 1.0
		# Steer back towards the main direction if the road has drifted off it.
		if absf(heading) > deg_to_rad(max_heading_drift_deg):
			direction = -signf(heading)
		curvature = direction * turn / length
	_start_d.append(start_d)
	_seg_length.append(length)
	_curvature.append(curvature)
	_start_pos.append(start_pos)
	_start_heading.append(heading)
