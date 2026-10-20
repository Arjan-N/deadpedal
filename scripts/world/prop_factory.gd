class_name PropFactory
extends RefCounted
## Builds environment props from primitives. Each function returns a Node3D
## whose origin sits on the ground, facing -Z. Swap any of these for an
## imported model later without touching the rest of the game.

const CAR_COLORS: Array[Color] = [
	Color(0.35, 0.12, 0.1), Color(0.18, 0.24, 0.3), Color(0.5, 0.48, 0.42),
	Color(0.2, 0.22, 0.18), Color(0.55, 0.5, 0.35), Color(0.1, 0.1, 0.11),
	Color(0.4, 0.4, 0.42),
]


static func car(rng: RandomNumberGenerator, body_color: Color = Color.BLACK, burnt: bool = false) -> Node3D:
	var root := Node3D.new()
	var color := body_color
	if color == Color.BLACK:
		color = CAR_COLORS[rng.randi() % CAR_COLORS.size()]
	if burnt:
		color = Color(0.09, 0.08, 0.075)
	var body := MeshKit.mat(color, 0.55 if not burnt else 1.0, 0.0, 0.3 if not burnt else 0.0)
	var glass := MeshKit.mat(Color(0.05, 0.06, 0.07) if not burnt else Color(0.02, 0.02, 0.02), 0.1, 0.0, 0.5)
	var tyre := MeshKit.mat(Color(0.04, 0.04, 0.04), 0.95)
	MeshKit.box(root, Vector3(1.8, 0.65, 4.2), Vector3(0, 0.6, 0), body)
	MeshKit.box(root, Vector3(1.6, 0.55, 2.1), Vector3(0, 1.18, 0.25), body)
	MeshKit.box(root, Vector3(1.62, 0.4, 1.9), Vector3(0, 1.2, 0.25), glass)
	MeshKit.box(root, Vector3(1.5, 0.4, 2.12), Vector3(0, 1.2, 0.25), glass)
	for x: float in [-0.82, 0.82]:
		for z: float in [-1.35, 1.35]:
			MeshKit.cylinder(root, 0.34, 0.25, Vector3(x, 0.34, z), tyre, Vector3(0, 0, 90))
	if not burnt:
		var tail := MeshKit.mat(Color(0.35, 0.03, 0.02), 0.4, 0.4)
		MeshKit.box(root, Vector3(0.35, 0.12, 0.05), Vector3(-0.62, 0.75, 2.1), tail)
		MeshKit.box(root, Vector3(0.35, 0.12, 0.05), Vector3(0.62, 0.75, 2.1), tail)
		if rng.randf() < 0.35:
			# An open door left behind in a hurry.
			MeshKit.box(root, Vector3(0.06, 0.9, 1.1), Vector3(-1.25, 0.8, -0.25), body, Vector3(0, -40, 0))
	return root


## A wrecked car on fire, with flickering light and smoke.
static func burning_car(rng: RandomNumberGenerator, flicker_lights: Array) -> Node3D:
	var root := car(rng, Color.BLACK, true)
	var light := OmniLight3D.new()
	light.position = Vector3(0, 1.8, 0)
	light.light_color = Color(1.0, 0.5, 0.18)
	light.light_energy = 3.0
	light.omni_range = 14.0
	root.add_child(light)
	flicker_lights.append(light)
	root.add_child(_fire_particles())
	root.add_child(_smoke_particles())
	return root


static func police_car(rng: RandomNumberGenerator, siren_lights: Array) -> Node3D:
	var root := car(rng, Color(0.85, 0.86, 0.88))
	var stripe := MeshKit.mat(Color(0.1, 0.2, 0.6), 0.5)
	MeshKit.box(root, Vector3(1.82, 0.18, 3.0), Vector3(0, 0.62, 0), stripe)
	var red := MeshKit.mat(Color(1.0, 0.05, 0.05), 0.3, 3.0)
	var blue := MeshKit.mat(Color(0.1, 0.25, 1.0), 0.3, 3.0)
	MeshKit.box(root, Vector3(0.55, 0.14, 0.3), Vector3(-0.3, 1.52, 0.25), red)
	MeshKit.box(root, Vector3(0.55, 0.14, 0.3), Vector3(0.3, 1.52, 0.25), blue)
	for i in 2:
		var l := OmniLight3D.new()
		l.position = Vector3(-0.6 + 1.2 * i, 2.0, 0.25)
		l.light_color = Color(1.0, 0.1, 0.08) if i == 0 else Color(0.15, 0.3, 1.0)
		l.light_energy = 4.0
		l.omni_range = 16.0
		root.add_child(l)
		siren_lights.append(l)
	return root


static func street_lamp(working: bool, flicker_lights: Array) -> Node3D:
	var root := Node3D.new()
	var metal := MeshKit.mat(Color(0.15, 0.16, 0.16), 0.6, 0.0, 0.5)
	MeshKit.cylinder(root, 0.09, 6.0, Vector3(0, 3.0, 0), metal, Vector3.ZERO, 0.06)
	MeshKit.box(root, Vector3(0.1, 0.1, 1.6), Vector3(0, 5.9, -0.75), metal)
	var head_mat := MeshKit.mat(Color(1.0, 0.8, 0.5), 0.3, 2.5) if working else MeshKit.mat(Color(0.1, 0.1, 0.1), 0.4)
	MeshKit.box(root, Vector3(0.35, 0.12, 0.6), Vector3(0, 5.82, -1.5), head_mat)
	if working:
		var l := OmniLight3D.new()
		l.position = Vector3(0, 5.4, -1.5)
		l.light_color = Color(1.0, 0.72, 0.4)
		l.light_energy = 2.2
		l.omni_range = 13.0
		root.add_child(l)
		flicker_lights.append(l)
	return root


static func tree(rng: RandomNumberGenerator, dead: bool = false) -> Node3D:
	var root := Node3D.new()
	var bark := MeshKit.mat(Color(0.18, 0.14, 0.11))
	var h := rng.randf_range(4.0, 7.5)
	MeshKit.cylinder(root, 0.22, h, Vector3(0, h * 0.5, 0), bark, Vector3(rng.randf_range(-4, 4), 0, rng.randf_range(-4, 4)), 0.12)
	if dead:
		for i in 3:
			var branch := MeshKit.cylinder(root, 0.06, 2.0, Vector3.ZERO, bark)
			var a := rng.randf() * TAU
			MeshKit.place_between(branch, Vector3(0, h * 0.7, 0), Vector3(cos(a) * 1.4, h + 0.4, sin(a) * 1.4))
		return root
	var leaf := MeshKit.mat(Color(0.12 + rng.randf() * 0.05, 0.17 + rng.randf() * 0.06, 0.08))
	for i in 3:
		var r := rng.randf_range(1.3, 2.2)
		MeshKit.sphere(root, 1.0, Vector3(rng.randf_range(-0.8, 0.8), h + rng.randf_range(-0.6, 0.8), rng.randf_range(-0.8, 0.8)), leaf, Vector3(r, r * 0.8, r))
	return root


static func bush(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var leaf := MeshKit.mat(Color(0.13, 0.19 + rng.randf() * 0.05, 0.08))
	for i in rng.randi_range(1, 3):
		var r := rng.randf_range(0.5, 1.1)
		MeshKit.sphere(root, 1.0, Vector3(rng.randf_range(-0.7, 0.7), r * 0.5, rng.randf_range(-0.7, 0.7)), leaf, Vector3(r, r * 0.7, r))
	return root


static func grass_tuft(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var leaf := MeshKit.mat(Color(0.2, 0.25, 0.1))
	for i in 4:
		MeshKit.cylinder(root, 0.05, 0.6, Vector3(rng.randf_range(-0.25, 0.25), 0.3, rng.randf_range(-0.25, 0.25)), leaf,
			Vector3(rng.randf_range(-20, 20), 0, rng.randf_range(-20, 20)), 0.0)
	return root


## Concrete road barrier.
static func barrier() -> Node3D:
	var root := Node3D.new()
	var concrete := MeshKit.mat(Color(0.5, 0.49, 0.46))
	MeshKit.box(root, Vector3(0.7, 0.35, 2.8), Vector3(0, 0.18, 0), concrete)
	MeshKit.box(root, Vector3(0.3, 0.6, 2.8), Vector3(0, 0.65, 0), concrete)
	var stripe := MeshKit.mat(Color(0.7, 0.55, 0.1))
	MeshKit.box(root, Vector3(0.32, 0.12, 2.82), Vector3(0, 0.8, 0), stripe)
	return root


static func sandbags() -> Node3D:
	var root := Node3D.new()
	var bag := MeshKit.mat(Color(0.38, 0.34, 0.24))
	for row in 3:
		for i in 5:
			MeshKit.capsule(root, 0.18, 0.75, Vector3(-1.6 + i * 0.75 + (row % 2) * 0.35, 0.18 + row * 0.3, 0), bag, Vector3(0, 0, 90))
	return root


static func rubble(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var stone := MeshKit.mat(Color(0.35, 0.33, 0.31))
	var brick := MeshKit.mat(Color(0.4, 0.24, 0.18))
	for i in rng.randi_range(4, 9):
		var s := rng.randf_range(0.3, 1.1)
		MeshKit.box(root, Vector3(s, s * 0.6, s * 0.8), Vector3(rng.randf_range(-1.5, 1.5), s * 0.2, rng.randf_range(-1.5, 1.5)),
			stone if rng.randf() < 0.6 else brick, Vector3(rng.randf() * 40, rng.randf() * 360, rng.randf() * 40))
	return root


static func dumpster() -> Node3D:
	var root := Node3D.new()
	var green := MeshKit.mat(Color(0.12, 0.22, 0.15), 0.7, 0.0, 0.3)
	MeshKit.box(root, Vector3(1.8, 1.2, 1.2), Vector3(0, 0.65, 0), green)
	MeshKit.box(root, Vector3(1.85, 0.08, 1.25), Vector3(0, 1.3, 0.1), green, Vector3(-15, 0, 0))
	return root


static func fence(length: float) -> Node3D:
	var root := Node3D.new()
	var wood := MeshKit.mat(Color(0.3, 0.24, 0.18))
	var posts := int(length / 2.5)
	for i in posts + 1:
		MeshKit.box(root, Vector3(0.12, 1.2, 0.12), Vector3(0, 0.6, -length * 0.5 + i * length / posts), wood)
	MeshKit.box(root, Vector3(0.05, 0.12, length), Vector3(0, 0.95, 0), wood)
	MeshKit.box(root, Vector3(0.05, 0.12, length), Vector3(0, 0.45, 0), wood)
	return root


## Small house with a pitched roof (outskirts).
static func house(rng: RandomNumberGenerator, building_mat: Material) -> Node3D:
	var root := Node3D.new()
	var w := rng.randf_range(7.0, 10.0)
	var d := rng.randf_range(7.0, 9.0)
	var h := rng.randf_range(4.0, 6.5)
	var wall := MeshKit.box(root, Vector3(w, h, d), Vector3(0, h * 0.5, 0), building_mat)
	wall.set_meta("building", true)
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(w + 0.6, 2.4, d + 0.6)
	var roof := MeshInstance3D.new()
	roof.mesh = roof_mesh
	roof.material_override = MeshKit.mat(Color(0.3, 0.14, 0.1) if rng.randf() < 0.6 else Color(0.18, 0.18, 0.2))
	roof.position = Vector3(0, h + 1.2, 0)
	root.add_child(roof)
	return root


static func sign_label(text: String, color: Color, size: int = 64) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.pixel_size = 0.01
	l.modulate = color
	l.outline_size = 0
	l.shaded = true
	l.double_sided = false
	return l


static func _fire_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.local_coords = true
	p.amount = 28
	p.lifetime = 0.9
	p.position = Vector3(0, 1.0, 0)
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(0.8, 0.2, 1.6)
	p.direction = Vector3.UP
	p.spread = 15.0
	p.gravity = Vector3(0, 2.0, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 2.5
	p.scale_amount_min = 0.5
	p.scale_amount_max = 1.0
	var curve := Curve.new()
	curve.add_point(Vector2(0, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var mesh := SphereMesh.new()
	mesh.radius = 0.35
	mesh.height = 0.7
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.45, 0.1)
	m.vertex_color_use_as_albedo = true
	mesh.material = m
	p.mesh = mesh
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.3))
	ramp.set_color(1, Color(0.8, 0.15, 0.02))
	p.color_ramp = ramp
	return p


static func _smoke_particles() -> CPUParticles3D:
	var p := CPUParticles3D.new()
	p.local_coords = true
	p.amount = 16
	p.lifetime = 4.0
	p.position = Vector3(0, 2.0, 0)
	p.direction = Vector3.UP
	p.spread = 12.0
	p.gravity = Vector3(0.4, 0.8, 0)
	p.initial_velocity_min = 1.0
	p.initial_velocity_max = 1.8
	p.scale_amount_min = 1.0
	p.scale_amount_max = 2.0
	var mesh := SphereMesh.new()
	mesh.radius = 0.8
	mesh.height = 1.6
	mesh.radial_segments = 6
	mesh.rings = 3
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.albedo_color = Color(1, 1, 1, 1)
	mesh.material = m
	p.mesh = mesh
	var ramp := Gradient.new()
	ramp.set_color(0, Color(0.1, 0.1, 0.1, 0.55))
	ramp.set_color(1, Color(0.2, 0.2, 0.2, 0.0))
	p.color_ramp = ramp
	return p


## Coloured signal smoke (supply crates).
static func signal_smoke(color: Color) -> CPUParticles3D:
	var p := _smoke_particles()
	p.position = Vector3(0, 0.8, 0)
	p.amount = 20
	var ramp := Gradient.new()
	ramp.set_color(0, Color(color, 0.75))
	ramp.set_color(1, Color(color.darkened(0.3), 0.0))
	p.color_ramp = ramp
	return p


# --- Criterium (a living town on race day) -------------------------------------

## Crowd barriers: metal fence panels, `length` metres long along -Z.
static func crowd_barrier(length: float) -> Node3D:
	var root := Node3D.new()
	var metal := MeshKit.mat(Color(0.75, 0.77, 0.78), 0.5, 0.0, 0.6)
	var panels := maxi(1, int(length / 2.4))
	var panel_len := length / panels
	for i in panels:
		var z := -length * 0.5 + panel_len * (i + 0.5)
		MeshKit.box(root, Vector3(0.05, 0.05, panel_len - 0.1), Vector3(0, 1.05, z), metal)
		MeshKit.box(root, Vector3(0.05, 0.05, panel_len - 0.1), Vector3(0, 0.2, z), metal)
		for b in 5:
			MeshKit.box(root, Vector3(0.03, 0.85, 0.03), Vector3(0, 0.62, z - panel_len * 0.4 + b * panel_len * 0.2), metal)
		MeshKit.box(root, Vector3(0.6, 0.04, 0.08), Vector3(0, 0.02, z - panel_len * 0.5 + 0.1), metal)
	return root


## A spectator (stands facing -Z, towards the road when placed sideways).
static func spectator(rng: RandomNumberGenerator) -> Node3D:
	var root := Node3D.new()
	var shirts := [Color(0.85, 0.2, 0.15), Color(0.15, 0.4, 0.8), Color(0.95, 0.8, 0.2), Color(0.2, 0.65, 0.3),
		Color(0.9, 0.9, 0.9), Color(0.6, 0.25, 0.65), Color(0.95, 0.5, 0.15)]
	var skin := [Color(0.85, 0.66, 0.52), Color(0.62, 0.45, 0.33), Color(0.42, 0.3, 0.22), Color(0.9, 0.75, 0.62)]
	var shirt := MeshKit.mat(shirts[rng.randi() % shirts.size()])
	var trousers := MeshKit.mat(Color(0.15, 0.17, 0.25) if rng.randf() < 0.6 else Color(0.35, 0.3, 0.25))
	var s := rng.randf_range(0.88, 1.08)
	for side: float in [-1.0, 1.0]:
		MeshKit.capsule(root, 0.08 * s, 0.85 * s, Vector3(0.11 * side, 0.43 * s, 0), trousers)
	MeshKit.capsule(root, 0.19 * s, 0.7 * s, Vector3(0, 1.2 * s, 0), shirt)
	MeshKit.sphere(root, 0.12 * s, Vector3(0, 1.7 * s, 0), MeshKit.mat(skin[rng.randi() % skin.size()]))
	if rng.randf() < 0.5:
		# Arms up, cheering.
		for side: float in [-1.0, 1.0]:
			MeshKit.capsule(root, 0.05 * s, 0.6 * s, Vector3(0.27 * side * s, 1.65 * s, 0), shirt, Vector3(0, 0, -25.0 * side))
	return root


## Start/finish gantry over the road (road_width wide), facing -Z.
static func finish_arch(road_width: float, text: String) -> Node3D:
	var root := Node3D.new()
	var post := MeshKit.mat(Color(0.12, 0.12, 0.14), 0.4, 0.0, 0.6)
	var half := road_width * 0.5 + 1.0
	for side: float in [-1.0, 1.0]:
		MeshKit.box(root, Vector3(0.5, 6.5, 0.5), Vector3(side * half, 3.25, 0), post)
	MeshKit.box(root, Vector3(half * 2.0 + 0.5, 1.6, 0.5), Vector3(0, 6.2, 0), MeshKit.mat(Color(0.85, 0.1, 0.12), 0.5))
	for face: float in [-1.0, 1.0]:
		var label := sign_label(text, Color(1, 1, 1), 110)
		label.position = Vector3(0, 6.2, face * 0.27)
		label.rotation.y = 0.0 if face > 0.0 else PI  # readable from both sides
		root.add_child(label)
	return root


## Checkered finish line painted across the road (lies flat, centred).
static func finish_line(road_width: float) -> Node3D:
	var root := Node3D.new()
	var white := MeshKit.mat(Color(0.95, 0.95, 0.95), 0.6)
	var black := MeshKit.mat(Color(0.05, 0.05, 0.05), 0.6)
	var squares := int(road_width / 0.5)
	for row in 2:
		for i in squares:
			var x := -road_width * 0.5 + 0.25 + i * 0.5
			MeshKit.box(root, Vector3(0.5, 0.02, 0.5), Vector3(x, 0.01, -0.25 + row * 0.5), white if (i + row) % 2 == 0 else black)
	return root


## A string of little triangular flags (bunting), `length` metres along -Z.
static func bunting(rng: RandomNumberGenerator, length: float, height: float) -> Node3D:
	var root := Node3D.new()
	var cols := [Color(0.9, 0.15, 0.1), Color(0.95, 0.85, 0.2), Color(0.15, 0.45, 0.9), Color(0.95, 0.95, 0.95), Color(0.2, 0.7, 0.3)]
	var n := int(length / 0.7)
	for i in n:
		var z := -length * 0.5 + i * 0.7
		var sag := sin(float(i) / float(maxi(n - 1, 1)) * PI) * 0.6
		var flag := MeshKit.box(root, Vector3(0.02, 0.35, 0.4), Vector3(0, height - sag - 0.2, z), MeshKit.mat(cols[rng.randi() % cols.size()], 0.8), Vector3(0, 0, 0))
		flag.rotation.x = deg_to_rad(45)
	return root
