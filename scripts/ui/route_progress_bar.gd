class_name RouteProgressBar
extends Control
## Horizontal strip showing the whole route: the gate, the extraction point,
## every rider (coloured dots) and how far the horde has advanced (red).

var total: float = 1900.0
var gate_at: float = 1100.0
var gate_open: bool = false
var horde_at: float = -1.0  # < 0 = no horde yet
## Array of [distance, Color, is_local]
var riders: Array = []


func _draw() -> void:
	var w := size.x
	var h := size.y
	var bar := Rect2(0, h * 0.35, w, h * 0.3)
	draw_rect(bar, Color(0, 0, 0, 0.55))
	if horde_at > 0.0:
		var hx := clampf(horde_at / total, 0.0, 1.0) * w
		draw_rect(Rect2(0, bar.position.y, hx, bar.size.y), Color(0.75, 0.05, 0.03, 0.85))
	draw_rect(bar, Color(1, 1, 1, 0.5), false, 2.0)
	# Gate marker.
	var gx := gate_at / total * w
	var gate_col := Color(0.3, 1.0, 0.4) if gate_open else Color(1.0, 0.7, 0.1)
	draw_rect(Rect2(gx - 4, 0, 8, h), gate_col)
	# Extraction marker.
	draw_rect(Rect2(w - 8, 0, 8, h), Color(0.3, 1.0, 0.4))
	# Riders.
	for r: Array in riders:
		var x := clampf(float(r[0]) / total, 0.0, 1.0) * w
		var radius := h * (0.42 if r[2] else 0.3)
		draw_circle(Vector2(x, h * 0.5), radius + 2.0, Color.BLACK)
		draw_circle(Vector2(x, h * 0.5), radius, r[1])
