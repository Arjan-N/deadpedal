class_name RaceMap
extends Control
## Top-down map of the circuit with every rider as a dot (you're the big one
## with the white ring). North is up; the chequered mark is the finish line.

var route: LoopRoute
## Array of [world x/z position (Vector2), Color, is_you]
var riders: Array = []

var _outline: PackedVector2Array
var _min: Vector2
var _scale: float = 1.0
var _offset: Vector2
var _fitted_size := Vector2.ZERO


func setup(p_route: LoopRoute) -> void:
	route = p_route
	_outline = route.get_outline(4.0)
	_outline.append(_outline[0])


## Scales the circuit to fill the control (again whenever its size changes).
func _fit() -> void:
	_fitted_size = size
	_min = Vector2(INF, INF)
	var max_p := Vector2(-INF, -INF)
	for p in _outline:
		_min = _min.min(p)
		max_p = max_p.max(p)
	var span := max_p - _min
	var margin := 14.0
	_scale = minf((size.x - margin * 2.0) / span.x, (size.y - margin * 2.0) / span.y)
	_offset = (size - span * _scale) * 0.5


func to_map(world: Vector2) -> Vector2:
	return _offset + (world - _min) * _scale


func _draw() -> void:
	if route == null:
		return
	if size != _fitted_size:
		_fit()
	var pts := PackedVector2Array()
	for p in _outline:
		pts.append(to_map(p))
	draw_polyline(pts, Color(0, 0, 0, 0.6), 9.0, true)
	draw_polyline(pts, Color(0.55, 0.57, 0.6), 5.0, true)
	# Finish line: a short black/white bar across the road.
	var f := route.get_frame(0.0)
	var a := to_map(Vector2(f.origin.x, f.origin.z) + Vector2(f.basis.x.x, f.basis.x.z) * 9.0)
	var b := to_map(Vector2(f.origin.x, f.origin.z) - Vector2(f.basis.x.x, f.basis.x.z) * 9.0)
	draw_line(a, b, Color.WHITE, 4.0)
	draw_line(a.lerp(b, 0.25), a.lerp(b, 0.75), Color.BLACK, 4.0)
	# Others first, you on top.
	for pass_you: bool in [false, true]:
		for r: Array in riders:
			if bool(r[2]) != pass_you:
				continue
			var p := to_map(r[0])
			var radius := 7.0 if pass_you else 5.0
			draw_circle(p, radius + 2.0, Color.WHITE if pass_you else Color.BLACK)
			draw_circle(p, radius, r[1])
