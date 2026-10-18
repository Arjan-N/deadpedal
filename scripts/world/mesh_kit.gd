class_name MeshKit
extends RefCounted
## Helpers for building placeholder geometry from Godot's primitive meshes.
## Every model in the prototype is assembled from these, so replacing a model
## later just means swapping one builder function for an imported scene.

static var _materials: Dictionary = {}
static var _meshes: Dictionary = {}


## Frees the shared meshes/materials (called at shutdown).
static func clear_cache() -> void:
	_materials.clear()
	_meshes.clear()


## Shared material per colour/settings combination (fewer materials = faster).
static func mat(color: Color, roughness: float = 0.9, emission: float = 0.0, metallic: float = 0.0) -> StandardMaterial3D:
	var key := "%s|%.2f|%.2f|%.2f" % [color.to_html(), roughness, emission, metallic]
	if _materials.has(key):
		return _materials[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	if emission > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = emission
	if color.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_materials[key] = m
	return m


static func box(parent: Node3D, size: Vector3, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var key := "box%s" % size
	if not _meshes.has(key):
		var bm := BoxMesh.new()
		bm.size = size
		_meshes[key] = bm
	return _add(parent, _meshes[key], pos, material, rot_deg)


static func cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO, top_radius: float = -1.0) -> MeshInstance3D:
	var tr := radius if top_radius < 0.0 else top_radius
	var key := "cyl%.3f|%.3f|%.3f" % [radius, height, tr]
	if not _meshes.has(key):
		var cm := CylinderMesh.new()
		cm.bottom_radius = radius
		cm.top_radius = tr
		cm.height = height
		cm.radial_segments = 10
		cm.rings = 1
		_meshes[key] = cm
	return _add(parent, _meshes[key], pos, material, rot_deg)


static func sphere(parent: Node3D, radius: float, pos: Vector3, material: Material, scale: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var key := "sph%.3f" % radius
	if not _meshes.has(key):
		var sm := SphereMesh.new()
		sm.radius = radius
		sm.height = radius * 2.0
		sm.radial_segments = 12
		sm.rings = 6
		_meshes[key] = sm
	var mi := _add(parent, _meshes[key], pos, material, Vector3.ZERO)
	mi.scale = scale
	return mi


static func capsule(parent: Node3D, radius: float, height: float, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var key := "cap%.3f|%.3f" % [radius, height]
	if not _meshes.has(key):
		var cm := CapsuleMesh.new()
		cm.radius = radius
		cm.height = height
		cm.radial_segments = 10
		cm.rings = 3
		_meshes[key] = cm
	return _add(parent, _meshes[key], pos, material, rot_deg)


static func torus(parent: Node3D, inner: float, outer: float, pos: Vector3, material: Material, rot_deg: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var key := "tor%.3f|%.3f" % [inner, outer]
	if not _meshes.has(key):
		var tm := TorusMesh.new()
		tm.inner_radius = inner
		tm.outer_radius = outer
		tm.rings = 20
		tm.ring_segments = 6
		_meshes[key] = tm
	return _add(parent, _meshes[key], pos, material, rot_deg)


## Orients `node` (whose mesh points along local +Y, like a cylinder or
## capsule) so it spans from point a to point b, in its parent's space.
static func place_between(node: Node3D, a: Vector3, b: Vector3) -> void:
	var dir := b - a
	var length := dir.length()
	if length < 0.0001:
		return
	var y := dir / length
	var x := y.cross(Vector3.FORWARD)
	if x.length_squared() < 0.0001:
		x = y.cross(Vector3.RIGHT)
	x = x.normalized()
	var z := x.cross(y)
	node.transform = Transform3D(Basis(x, y, z), (a + b) * 0.5)


static func _add(parent: Node3D, mesh: Mesh, pos: Vector3, material: Material, rot_deg: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = pos
	mi.rotation_degrees = rot_deg
	parent.add_child(mi)
	return mi
