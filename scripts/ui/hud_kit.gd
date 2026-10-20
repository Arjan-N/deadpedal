class_name HudKit
extends RefCounted
## Shared building blocks for the in-game HUDs: large, high-contrast labels,
## translucent panels and progress bars that read at a glance while riding.

const COL_TEXT := Color(0.95, 0.95, 0.92)
const COL_DIM := Color(0.7, 0.72, 0.7)
const COL_WARN := Color(1.0, 0.7, 0.15)
const COL_DANGER := Color(1.0, 0.25, 0.18)
const COL_GOOD := Color(0.4, 1.0, 0.45)


static func settings(font_size: int, color: Color = COL_TEXT) -> LabelSettings:
	var s := LabelSettings.new()
	s.font_size = font_size
	s.font_color = color
	s.outline_size = maxi(4, font_size / 8)
	s.outline_color = Color(0, 0, 0, 0.85)
	s.shadow_size = 2
	s.shadow_color = Color(0, 0, 0, 0.4)
	return s


static func label(parent: Node, text: String, font_size: int, color: Color = COL_TEXT, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = text
	l.label_settings = settings(font_size, color)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


static func panel(parent: Node, alpha: float = 0.45) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.04, 0.04, alpha)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(16)
	sb.border_color = Color(1, 1, 1, 0.08)
	sb.set_border_width_all(1)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(p)
	return p


static func bar(parent: Node, min_size: Vector2, fill: Color) -> ProgressBar:
	var b := ProgressBar.new()
	b.custom_minimum_size = min_size
	b.show_percentage = false
	b.max_value = 1.0
	b.step = 0.0
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0, 0, 0, 0.6)
	bg.set_corner_radius_all(6)
	bg.border_color = Color(1, 1, 1, 0.35)
	bg.set_border_width_all(2)
	var fg := StyleBoxFlat.new()
	fg.bg_color = fill
	fg.set_corner_radius_all(6)
	b.add_theme_stylebox_override("background", bg)
	b.add_theme_stylebox_override("fill", fg)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(b)
	return b
