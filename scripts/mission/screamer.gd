class_name Screamer
extends Node3D
## A screamer by the roadside in Endless Survival: a tall, pale zombie with a
## gaping mouth. Ride past it slowly and it shrieks - the horde surges. Fly
## past fast enough and it doesn't react in time.

var _body: Node3D
var _mouth_light: OmniLight3D
var _label: Label3D
var _time: float = 0.0
var _screaming := false
var _silenced := false


func build(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var skin := MeshKit.mat(Color(0.72, 0.74, 0.66))
	var rags := MeshKit.mat(Color(0.25, 0.22, 0.24))
	var glow := MeshKit.mat(Color(0.9, 0.2, 0.9), 0.4, 4.0)
	for side: float in [-1.0, 1.0]:
		MeshKit.capsule(self, 0.07, 1.1, Vector3(0.12 * side, 0.55, 0), rags)
	_body = Node3D.new()
	_body.position = Vector3(0, 1.1, 0)
	add_child(_body)
	MeshKit.capsule(_body, 0.17, 0.95, Vector3(0, 0.45, 0), rags)
	MeshKit.sphere(_body, 0.15, Vector3(0, 1.08, 0), skin, Vector3(1.0, 1.25, 1.0))
	MeshKit.sphere(_body, 0.07, Vector3(0, 1.0, -0.12), glow, Vector3(1.0, 1.4, 0.5))  # gaping mouth
	for side: float in [-1.0, 1.0]:
		# Arms raised to the sky.
		MeshKit.capsule(_body, 0.05, 0.85, Vector3(0.28 * side, 1.15, 0), skin, Vector3(0, 0, -20.0 * side))
	_mouth_light = OmniLight3D.new()
	_mouth_light.light_color = Color(0.9, 0.3, 1.0)
	_mouth_light.omni_range = 8.0
	_mouth_light.position = Vector3(0, 2.1, -0.4)
	add_child(_mouth_light)
	_label = Label3D.new()
	_label.text = "SCREAMER"
	_label.font_size = 40
	_label.outline_size = 10
	_label.modulate = Color(0.95, 0.5, 1.0)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.position = Vector3(0, 3.0, 0)
	add_child(_label)
	_time = rng.randf() * 10.0


func scream() -> void:
	_screaming = true
	_label.text = "!!!"


## Passed fast enough: it never got its scream out.
func silence() -> void:
	_silenced = true
	_label.visible = false


func _process(delta: float) -> void:
	_time += delta
	if _silenced:
		_mouth_light.light_energy = 0.0
		_body.rotation.x = lerpf(_body.rotation.x, 0.5, delta * 2.0)  # slumps
		return
	if _screaming:
		_body.rotation.x = -0.35 + sin(_time * 30.0) * 0.05
		_mouth_light.light_energy = 6.0 + sin(_time * 25.0) * 2.0
	else:
		_body.rotation.z = sin(_time * 1.7) * 0.15
		_mouth_light.light_energy = 1.5 + sin(_time * 3.0) * 0.8
