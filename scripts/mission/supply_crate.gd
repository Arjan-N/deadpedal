class_name SupplyCrate
extends Node3D
## A supply drop by the roadside in Endless Survival, marked with coloured
## smoke. Slow down as you pass to grab it (like survivors).
##   FLARES (red smoke): the horde is driven back.
##   FOOD (yellow smoke): your survivors get their energy back.

enum Content { FLARES, FOOD }
const TITLES := ["FLARES", "FOOD"]
const COLORS: Array[Color] = [Color(1.0, 0.25, 0.15), Color(1.0, 0.85, 0.2)]

var content: Content = Content.FLARES
var _label: Label3D
var _smoke: CPUParticles3D


func build(p_content: Content) -> void:
	content = p_content
	var color := COLORS[content]
	var wood := MeshKit.mat(Color(0.42, 0.3, 0.18))
	MeshKit.box(self, Vector3(1.1, 0.8, 0.8), Vector3(0, 0.4, 0), wood)
	MeshKit.box(self, Vector3(1.14, 0.08, 0.84), Vector3(0, 0.72, 0), MeshKit.mat(Color(0.3, 0.22, 0.13)))
	# A painted band so the content reads from a distance.
	MeshKit.box(self, Vector3(1.12, 0.18, 0.82), Vector3(0, 0.4, 0), MeshKit.mat(color, 0.6, 0.8))
	# Parachute left draped over the crate.
	MeshKit.sphere(self, 0.7, Vector3(0.3, 0.75, 0.4), MeshKit.mat(Color(0.85, 0.85, 0.8)), Vector3(1.0, 0.25, 0.8))
	_smoke = PropFactory.signal_smoke(color)
	add_child(_smoke)
	var glow := OmniLight3D.new()
	glow.light_color = color
	glow.light_energy = 1.5
	glow.omni_range = 7.0
	glow.position = Vector3(0, 1.2, 0)
	add_child(glow)
	_label = Label3D.new()
	_label.text = TITLES[content]
	_label.font_size = 44
	_label.outline_size = 10
	_label.modulate = color.lightened(0.3)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.2, 0)
	add_child(_label)


func left_behind() -> void:
	_label.visible = false
	_smoke.emitting = false
