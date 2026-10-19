class_name Survivor
extends Node3D
## A survivor waiting by the roadside in Endless Survival: waves a red flare
## and shouts for help. Slow down as you pass to pick them up.
## Placeholder model built from primitives, like the riders and zombies.

const JACKETS: Array[Color] = [Color(0.2, 0.3, 0.45), Color(0.45, 0.32, 0.15), Color(0.3, 0.38, 0.22), Color(0.5, 0.15, 0.12)]

var survivor_name: String = ""
var _arm: Node3D
var _flare: OmniLight3D
var _label: Label3D
var _time: float = 0.0


func build(p_name: String, seed_value: int) -> void:
	survivor_name = p_name
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var jacket := MeshKit.mat(JACKETS[rng.randi() % JACKETS.size()])
	var trousers := MeshKit.mat(Color(0.12, 0.12, 0.14))
	var skin := MeshKit.mat(Color(0.75, 0.58, 0.46))
	for side: float in [-1.0, 1.0]:
		MeshKit.capsule(self, 0.08, 0.9, Vector3(0.11 * side, 0.45, 0), trousers)
	MeshKit.capsule(self, 0.2, 0.75, Vector3(0, 1.25, 0), jacket)
	MeshKit.sphere(self, 0.12, Vector3(0, 1.78, 0), skin)
	MeshKit.capsule(self, 0.055, 0.6, Vector3(-0.27, 1.2, 0), jacket, Vector3(0, 0, -12))
	# Waving arm holding a red flare.
	_arm = Node3D.new()
	_arm.position = Vector3(0.25, 1.55, 0)
	add_child(_arm)
	MeshKit.capsule(_arm, 0.055, 0.6, Vector3(0, 0.3, 0), jacket)
	MeshKit.cylinder(_arm, 0.03, 0.25, Vector3(0, 0.68, 0), MeshKit.mat(Color(1.0, 0.15, 0.08), 0.3, 6.0))
	_flare = OmniLight3D.new()
	_flare.position = Vector3(0, 0.8, 0)
	_flare.light_color = Color(1.0, 0.25, 0.15)
	_flare.omni_range = 12.0
	_arm.add_child(_flare)
	_label = Label3D.new()
	_label.text = "HELP!"
	_label.font_size = 48
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.45, 0.35)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 2.6, 0)
	add_child(_label)


func left_behind() -> void:
	_label.text = "..."
	_label.modulate = Color(0.6, 0.6, 0.6)


func _process(delta: float) -> void:
	_time += delta
	if _arm:
		_arm.rotation.z = -0.6 + sin(_time * 6.0) * 0.5
	if _flare:
		_flare.light_energy = 3.0 + sin(_time * 17.0) * 0.8 + sin(_time * 7.3) * 0.6
