class_name RouteProgressBar
extends Control
## Horizontal strip showing a stretch of the route: the next gate, the end
## point (story mode), every rider (coloured dots) and how far the horde has
## advanced (red). In story mode the stretch is the whole route; in endless
## mode it's a window that scrolls with the riders.

var from_d: float = 0.0
var to_d: float = 1900.0
var gate_at: float = 1100.0
var gate_open: bool = false
var show_end_marker: bool = true
var horde_at: float = -INF  # -INF = no horde yet
## Array of [distance, Color, is_local]
var riders: Array = []
## Optional extra markers: Array of [distance, Color] (e.g. survivors).
var markers: Array = []


func _x(distance: float) -> float:
	return clampf((distance - from_d) / maxf(to_d - from_d, 1.0), 0.0, 1.0) * size.x


func _draw() -> void:
	var w := size.x
	var h := size.y
	var bar := Rect2(0, h * 0.35, w, h * 0.3)
	draw_rect(bar, Color(0, 0, 0, 0.55))
	if horde_at > -INF and horde_at > from_d:
		draw_rect(Rect2(0, bar.position.y, _x(horde_at), bar.size.y), Color(0.75, 0.05, 0.03, 0.85))
	draw_rect(bar, Color(1, 1, 1, 0.5), false, 2.0)
	# Gate marker (only if it's within the window).
	if gate_at >= from_d and gate_at <= to_d:
		var gate_col := Color(0.3, 1.0, 0.4) if gate_open else Color(1.0, 0.7, 0.1)
		draw_rect(Rect2(_x(gate_at) - 4, 0, 8, h), gate_col)
	if show_end_marker:
		draw_rect(Rect2(w - 8, 0, 8, h), Color(0.3, 1.0, 0.4))
	for m: Array in markers:
		var mx := _x(float(m[0]))
		draw_rect(Rect2(mx - 3, h * 0.05, 6, h * 0.3), m[1])
	# Riders.
	for r: Array in riders:
		var x := _x(float(r[0]))
		var radius := h * (0.42 if r[2] else 0.3)
		draw_circle(Vector2(x, h * 0.5), radius + 2.0, Color.BLACK)
		draw_circle(Vector2(x, h * 0.5), radius, r[1])
