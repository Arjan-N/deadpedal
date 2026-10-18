class_name ExtractionZone
extends Node3D
## The safe zone at the end of the mission: a military checkpoint with a
## waiting helicopter and green flares. Visual only; MissionManager decides
## when the team has arrived.

var _rotor: Node3D
var _flare: OmniLight3D
var _time: float = 0.0


func _ready() -> void:
	_build()


func _process(delta: float) -> void:
	_time += delta
	if _rotor:
		_rotor.rotation.y += delta * 14.0
	if _flare:
		_flare.light_energy = 3.5 + sin(_time * 13.0) * 0.6 + sin(_time * 5.3) * 0.5


func _build() -> void:
	var olive := MeshKit.mat(Color(0.24, 0.27, 0.18), 0.8)
	var dark := MeshKit.mat(Color(0.08, 0.09, 0.08), 0.6)
	var green_glow := MeshKit.mat(Color(0.25, 1.0, 0.35, 0.5), 0.5, 2.5)

	# Glowing finish line across the road.
	MeshKit.box(self, Vector3(10.0, 0.03, 0.8), Vector3(0, 0.02, 0), green_glow)

	# Helicopter on a pad to the right.
	var heli := Node3D.new()
	heli.position = Vector3(16, 0, -14)
	heli.rotation_degrees.y = -30
	add_child(heli)
	MeshKit.cylinder(heli, 7.0, 0.1, Vector3(0, 0.05, 0), MeshKit.mat(Color(0.25, 0.25, 0.24)))
	MeshKit.capsule(heli, 1.3, 5.5, Vector3(0, 1.8, 0), olive, Vector3(90, 0, 0))
	MeshKit.box(heli, Vector3(1.8, 0.8, 1.2), Vector3(0, 2.2, -2.0), dark)
	MeshKit.cylinder(heli, 0.35, 5.0, Vector3(0, 2.2, 4.5), olive, Vector3(90, 0, 0), 0.2)
	MeshKit.box(heli, Vector3(0.1, 1.6, 0.8), Vector3(0.2, 2.8, 6.8), olive)
	for side: float in [-1.0, 1.0]:
		MeshKit.box(heli, Vector3(0.12, 0.12, 4.0), Vector3(side * 1.2, 0.3, 0), dark)
	_rotor = Node3D.new()
	_rotor.position = Vector3(0, 3.4, 0)
	heli.add_child(_rotor)
	MeshKit.box(_rotor, Vector3(13.0, 0.06, 0.4), Vector3.ZERO, dark)
	MeshKit.box(_rotor, Vector3(0.4, 0.06, 13.0), Vector3.ZERO, dark)

	# Trucks, sandbags and floodlights on the left.
	for i in 2:
		var truck := Node3D.new()
		truck.position = Vector3(-12, 0, -6 - i * 9)
		truck.rotation_degrees.y = 10 - i * 25
		add_child(truck)
		MeshKit.box(truck, Vector3(2.4, 1.6, 6.5), Vector3(0, 1.6, 0), olive)
		MeshKit.box(truck, Vector3(2.4, 1.4, 2.0), Vector3(0, 1.5, -4.1), olive)
		for x: float in [-1.1, 1.1]:
			for z: float in [-4.0, -1.5, 2.2]:
				MeshKit.cylinder(truck, 0.5, 0.35, Vector3(x, 0.5, z), dark, Vector3(0, 0, 90))
	for side: float in [-1.0, 1.0]:
		var sb := PropFactory.sandbags()
		sb.position = Vector3(side * 7.0, 0, 3)
		add_child(sb)
		var pole := Node3D.new()
		pole.position = Vector3(side * 8.5, 0, -2)
		add_child(pole)
		MeshKit.cylinder(pole, 0.1, 5.0, Vector3(0, 2.5, 0), dark)
		MeshKit.box(pole, Vector3(0.8, 0.5, 0.4), Vector3(0, 5.0, 0), MeshKit.mat(Color(1, 1, 0.9), 0.3, 3.0))
		var spot := SpotLight3D.new()
		spot.position = Vector3(0, 5.0, 0)
		spot.rotation_degrees = Vector3(-35, side * 150.0, 0)
		spot.spot_range = 40.0
		spot.spot_angle = 35.0
		spot.light_energy = 4.0
		spot.light_color = Color(1.0, 0.97, 0.88)
		pole.add_child(spot)

	# Green flare + smoke on the road ahead.
	_flare = OmniLight3D.new()
	_flare.position = Vector3(3, 1.0, -8)
	_flare.light_color = Color(0.3, 1.0, 0.35)
	_flare.omni_range = 22.0
	add_child(_flare)
	var smoke := CPUParticles3D.new()
	smoke.position = Vector3(3, 0.3, -8)
	smoke.amount = 24
	smoke.lifetime = 5.0
	smoke.direction = Vector3.UP
	smoke.spread = 20.0
	smoke.gravity = Vector3(0.6, 0.6, 0)
	smoke.initial_velocity_min = 0.8
	smoke.initial_velocity_max = 1.6
	smoke.scale_amount_min = 1.2
	smoke.scale_amount_max = 2.6
	var mesh := SphereMesh.new()
	mesh.radius = 0.8
	mesh.height = 1.6
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	smoke.mesh = mesh
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.35, 0.9, 0.4, 0.5))
	ramp.set_color(1, Color(0.3, 0.5, 0.3, 0.0))
	smoke.color_ramp = ramp
	add_child(smoke)

	var sign_label := PropFactory.sign_label("EXTRACTION", Color(0.4, 1.0, 0.45), 200)
	sign_label.position = Vector3(0, 7.5, -4)
	sign_label.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sign_label.shaded = false
	add_child(sign_label)
