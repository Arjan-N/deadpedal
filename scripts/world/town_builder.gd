class_name TownBuilder
extends Node3D
## Procedurally dresses the route: road, pavements, buildings, props, lights.
##
## Uses a fixed random seed, so every player in a multiplayer session sees the
## exact same town. Purely visual - no gameplay logic lives here.

@export var random_seed: int = 1984
@export var road_width: float = 10.0
@export var sidewalk_width: float = 2.6
## Distance between building plots along the road in the town centre.
@export var building_spacing: Vector2 = Vector2(11.0, 17.0)
## Props further than this from the camera are hidden (performance).
@export var prop_view_distance: float = 230.0

const ROAD_SHADER := preload("res://shaders/road.gdshader")
const BUILDING_SHADER := preload("res://shaders/building.gdshader")
const GROUND_SHADER := preload("res://shaders/ground.gdshader")

var _rng := RandomNumberGenerator.new()
var _route: Route
var _building_mat: ShaderMaterial
var _burnt_mat: ShaderMaterial
var _flicker_lights: Array = []
var _siren_lights: Array = []
var _time: float = 0.0
var _gate_distance: float
var _extraction_distance: float


func build(route: Route, gate_distance: float, extraction_distance: float) -> void:
	_route = route
	_gate_distance = gate_distance
	_extraction_distance = extraction_distance
	_rng.seed = random_seed
	_building_mat = ShaderMaterial.new()
	_building_mat.shader = BUILDING_SHADER
	_burnt_mat = ShaderMaterial.new()
	_burnt_mat.shader = BUILDING_SHADER
	_burnt_mat.set_shader_parameter("burnt", 0.75)
	_burnt_mat.set_shader_parameter("lit_chance", 0.0)

	_build_ground()
	_build_road()
	_build_sidewalks()
	_build_town_centre()
	_build_outskirts()
	_build_props()
	_build_signs()


func _process(delta: float) -> void:
	_time += delta
	# Flickering street lamps and fires.
	for i in _flicker_lights.size():
		var l: OmniLight3D = _flicker_lights[i]
		var n := sin(_time * (11.0 + i) + i * 7.0) * sin(_time * (3.7 + i * 0.3))
		l.light_energy = l.get_meta("base_energy", l.light_energy) * (0.75 + 0.25 * n + (0.0 if fmod(_time + i, 6.0) > 0.12 else -0.7))
	# Police lights alternate red / blue.
	for i in _siren_lights.size():
		var on := fmod(_time * 2.5 + (i % 2) * 0.5, 1.0) < 0.5
		(_siren_lights[i] as OmniLight3D).light_energy = 5.0 if on else 0.0


# --- Ground and road -------------------------------------------------------

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(3000, 3000)
	var mi := MeshInstance3D.new()
	mi.mesh = plane
	var m := ShaderMaterial.new()
	m.shader = GROUND_SHADER
	mi.material_override = m
	var mid := _route.get_point(_route.get_length() * 0.5)
	mi.position = Vector3(mid.x, -0.03, mid.z)
	add_child(mi)


## Builds a strip mesh that follows the route. Each edge is given as a
## sideways offset + height, so the same function makes flat strips (road,
## pavement) and vertical ones (curb faces). Edge A -> B runs left -> right
## (or bottom -> top), which makes the faces point up (or towards the road).
func _ribbon(lat_a: float, h_a: float, lat_b: float, h_b: float, material: Material) -> MeshInstance3D:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var length := _route.get_length()
	var d := 0.0
	var prev_a := Vector3.ZERO
	var prev_b := Vector3.ZERO
	var prev_d := 0.0
	var first := true
	while true:
		var a := _route.get_point(d, lat_a) + Vector3.UP * h_a
		var b := _route.get_point(d, lat_b) + Vector3.UP * h_b
		if not first:
			# Godot treats clockwise triangles as front faces.
			st.set_uv(Vector2(0.0, prev_d)); st.add_vertex(prev_a)
			st.set_uv(Vector2(1.0, d)); st.add_vertex(b)
			st.set_uv(Vector2(1.0, prev_d)); st.add_vertex(prev_b)
			st.set_uv(Vector2(0.0, prev_d)); st.add_vertex(prev_a)
			st.set_uv(Vector2(0.0, d)); st.add_vertex(a)
			st.set_uv(Vector2(1.0, d)); st.add_vertex(b)
		first = false
		prev_a = a
		prev_b = b
		prev_d = d
		if d >= length:
			break
		d = minf(d + 2.0, length)
	st.generate_normals()
	st.generate_tangents()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = material
	add_child(mi)
	return mi


func _build_road() -> void:
	var m := ShaderMaterial.new()
	m.shader = ROAD_SHADER
	m.set_shader_parameter("road_width", road_width)
	var half := road_width * 0.5
	# Left-to-right ordering keeps the triangles facing up.
	_ribbon(-half, 0.0, half, 0.0, m)


func _build_sidewalks() -> void:
	var concrete := MeshKit.mat(Color(0.36, 0.35, 0.33), 0.95)
	var curb := MeshKit.mat(Color(0.45, 0.44, 0.42), 0.9)
	var half := road_width * 0.5
	var top := 0.16
	_ribbon(half + 0.25, top, half + sidewalk_width, top, concrete)
	_ribbon(-half - sidewalk_width, top, -half - 0.25, top, concrete)
	_ribbon(half, top + 0.01, half + 0.25, top + 0.01, curb)
	_ribbon(-half - 0.25, top + 0.01, -half, top + 0.01, curb)
	# Vertical curb faces, so the pavement reads as raised.
	_ribbon(half, 0.0, half, top + 0.01, curb)
	_ribbon(-half, top + 0.01, -half, 0.0, curb)


# --- Buildings ---------------------------------------------------------------

func _place(node: Node3D, distance: float, lateral: float, yaw_deg: float = 0.0, view_distance: float = -1.0) -> void:
	var f := _route.get_frame(distance)
	node.transform = Transform3D(f.basis.rotated(Vector3.UP, deg_to_rad(yaw_deg)), f.origin + f.basis.x * lateral)
	add_child(node)
	var vd := prop_view_distance if view_distance < 0.0 else view_distance
	_set_view_distance(node, vd)


func _set_view_distance(node: Node, vd: float) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).visibility_range_end = vd
	for c in node.get_children():
		_set_view_distance(c, vd)


## True if a rectangular footprint (half sizes across / along the road) placed
## at `distance` and `lateral` stays clear of the road and pavement.
## Matters on the inside of bends, where buildings would otherwise overlap.
func _footprint_clear(distance: float, lateral: float, half_across: float, half_along: float) -> bool:
	var f := _route.get_frame(distance)
	var limit := road_width * 0.5 + sidewalk_width - 0.3
	for sx: float in [-1.0, 1.0]:
		for sz: float in [-1.0, 1.0]:
			var corner := f.origin + f.basis.x * (lateral + sx * half_across) + f.basis.z * (sz * half_along)
			if corner.distance_to(_route.curve.get_closest_point(corner)) < limit:
				return false
	return true


func _build_town_centre() -> void:
	var town_end := _gate_distance - 8.0
	var half := road_width * 0.5 + sidewalk_width
	for side: float in [-1.0, 1.0]:
		var d := 6.0
		while d < town_end:
			var width := _rng.randf_range(building_spacing.x, building_spacing.y) - 1.0
			var depth := _rng.randf_range(10.0, 16.0)
			var height := _rng.randf_range(7.0, 19.0)
			var gap := _rng.randf() < 0.12
			if not gap:
				var lateral := side * (half + 0.3 + depth * 0.5)
				if _footprint_clear(d + width * 0.5, lateral, depth * 0.5, width * 0.5):
					var burnt := _rng.randf() < 0.1
					var facade_x := -side * depth * 0.5  # local x of the road-facing wall
					var b := Node3D.new()
					var box := MeshKit.box(b, Vector3(depth, height, width), Vector3(0, height * 0.5, 0), _burnt_mat if burnt else _building_mat)
					box.set_meta("building", true)
					# Rooftop clutter on some buildings.
					if _rng.randf() < 0.4:
						MeshKit.box(b, Vector3(2.0, 1.4, 2.0), Vector3(_rng.randf_range(-2, 2), height + 0.7, _rng.randf_range(-2, 2)), MeshKit.mat(Color(0.25, 0.25, 0.25)))
					# A collapsed roof corner and rubble on damaged buildings.
					if burnt or _rng.randf() < 0.12:
						MeshKit.box(b, Vector3(depth * 0.6, 2.0, width * 0.5), Vector3(0, height - 0.5, width * 0.2), MeshKit.mat(Color(0.12, 0.11, 0.1)), Vector3(18, 0, 0))
						var r := PropFactory.rubble(_rng)
						r.position = Vector3(facade_x - side * 1.2, 0, width * 0.2)
						b.add_child(r)
					# Overgrowth climbing the facade.
					if _rng.randf() < 0.35:
						var vine := MeshKit.mat(Color(0.12, 0.2, 0.08))
						var vh := _rng.randf_range(3.0, height * 0.8)
						MeshKit.box(b, Vector3(0.3, vh, _rng.randf_range(1.5, 4.0)), Vector3(facade_x - side * 0.1, vh * 0.5, _rng.randf_range(-width * 0.3, width * 0.3)), vine)
					_place(b, d + width * 0.5, lateral, 0.0, 450.0)
			else:
				# Alley: a fence and some rubbish.
				var fence := PropFactory.fence(width)
				_place(fence, d + width * 0.5, side * (half + 4.0))
			d += width + 1.0


func _build_outskirts() -> void:
	var start := _gate_distance + 25.0
	var end := _route.get_length() + 40.0
	var half := road_width * 0.5 + 2.0
	for side: float in [-1.0, 1.0]:
		var d := start
		while d < end:
			var roll := _rng.randf()
			if roll < 0.35:
				var lateral := side * (half + _rng.randf_range(10.0, 18.0))
				if _footprint_clear(d, lateral, 6.0, 6.0) and absf(d - _extraction_distance) > 40.0:
					var h := PropFactory.house(_rng, _building_mat)
					_place(h, d, lateral, _rng.randf_range(-10, 10), 450.0)
					var fence := PropFactory.fence(12.0)
					_place(fence, d, side * (half + 4.0))
			elif roll < 0.8:
				var t := PropFactory.tree(_rng, _rng.randf() < 0.3)
				_place(t, d, side * (half + _rng.randf_range(1.5, 9.0)))
			d += _rng.randf_range(9.0, 18.0)
	# A tree line in the distance.
	var d2 := start
	while d2 < end:
		for side: float in [-1.0, 1.0]:
			var t := PropFactory.tree(_rng)
			t.scale = Vector3.ONE * _rng.randf_range(1.2, 1.8)
			_place(t, d2, side * _rng.randf_range(38.0, 60.0), 0.0, 420.0)
		d2 += _rng.randf_range(6.0, 14.0)


# --- Props -------------------------------------------------------------------

func _build_props() -> void:
	var length := _route.get_length()
	var half := road_width * 0.5
	# Street lamps along the pavement; a few still (barely) work.
	var d := 12.0
	var side := 1.0
	while d < _gate_distance - 10.0:
		var working := _rng.randf() < 0.3
		var lamp := PropFactory.street_lamp(working, _flicker_lights)
		_place(lamp, d, side * (half + 0.6), 90.0 * side, 260.0)
		side = -side
		d += _rng.randf_range(22.0, 32.0)

	# Abandoned cars at the road edges (never in the riding lanes).
	d = 35.0
	while d < length - 30.0:
		if absf(d - _gate_distance) > 30.0 and absf(d - _extraction_distance) > 30.0:
			var s := -1.0 if _rng.randf() < 0.5 else 1.0
			var c: Node3D
			var r := _rng.randf()
			if r < 0.1:
				c = PropFactory.burning_car(_rng, _flicker_lights)
			else:
				c = PropFactory.car(_rng)
			_place(c, d, s * (half + 0.9), _rng.randf_range(-25, 25) + (180.0 if _rng.randf() < 0.3 else 0.0))
		d += _rng.randf_range(28.0, 55.0)

	# Overgrowth, rubble and clutter on the pavements.
	d = 4.0
	while d < length:
		var s := -1.0 if _rng.randf() < 0.5 else 1.0
		var r := _rng.randf()
		var prop: Node3D
		if r < 0.45:
			prop = PropFactory.grass_tuft(_rng)
			_place(prop, d, s * (half + _rng.randf_range(0.1, 2.0)))
		elif r < 0.7:
			prop = PropFactory.bush(_rng)
			_place(prop, d, s * (half + _rng.randf_range(1.5, 3.0)))
		elif r < 0.82 and d < _gate_distance:
			prop = PropFactory.rubble(_rng)
			_place(prop, d, s * (half + 1.8))
		elif r < 0.9 and d < _gate_distance:
			prop = PropFactory.dumpster()
			_place(prop, d, s * (half + 1.6), 90.0)
		elif r < 0.95:
			prop = PropFactory.barrier()
			_place(prop, d, s * (half + 0.6), _rng.randf_range(-15, 15))
		d += _rng.randf_range(4.0, 9.0)

	# Emergency scene just before the gate: police cars and barriers.
	var pc := PropFactory.police_car(_rng, _siren_lights)
	_place(pc, _gate_distance - 22.0, half + 1.2, 155.0, 400.0)
	var pc2 := PropFactory.police_car(_rng, _siren_lights)
	_place(pc2, _gate_distance - 34.0, -half - 1.0, -20.0, 400.0)
	var amb := PropFactory.burning_car(_rng, _flicker_lights)
	_place(amb, _gate_distance * 0.55, -half - 1.0, 30.0, 400.0)

	# Quarantine walls either side of the gate so it can't be ridden around.
	var wall_mat := MeshKit.mat(Color(0.48, 0.47, 0.44))
	for s2: float in [-1.0, 1.0]:
		var wall := Node3D.new()
		MeshKit.box(wall, Vector3(60.0, 4.5, 0.6), Vector3(0, 2.25, 0), wall_mat)
		MeshKit.box(wall, Vector3(60.0, 0.4, 0.8), Vector3(0, 4.6, 0), MeshKit.mat(Color(0.3, 0.3, 0.3)))
		var stripe := MeshKit.mat(Color(0.75, 0.6, 0.1))
		MeshKit.box(wall, Vector3(60.0, 0.3, 0.62), Vector3(0, 1.0, 0), stripe)
		_place(wall, _gate_distance, s2 * (half + 30.6), 0.0, 600.0)
		for i in 3:
			var sb := PropFactory.sandbags()
			_place(sb, _gate_distance - 3.0, s2 * (half + 2.5 + i * 3.2), 0.0, 400.0)


func _build_signs() -> void:
	var half := road_width * 0.5
	var red := Color(0.65, 0.08, 0.06)
	var graffiti := [["THEY HEAR YOU", 140.0, -1.0], ["DON'T STOP", 420.0, 1.0],
		["EVACUATE ->", 700.0, -1.0], ["NO WAY BACK", 930.0, 1.0]]
	for g: Array in graffiti:
		var label := PropFactory.sign_label(g[0], red, 160)
		var dist: float = g[1]
		var side: float = g[2]
		var lateral := side * (half + sidewalk_width + 0.35)
		var f := _route.get_frame(dist)
		# Face the road.
		label.transform = Transform3D(f.basis.rotated(Vector3.UP, -side * PI * 0.5), f.origin + f.basis.x * lateral + Vector3.UP * 3.2)
		add_child(label)
	var sign_text := PropFactory.sign_label("QUARANTINE ZONE - NO ENTRY", Color(0.9, 0.85, 0.2), 60)
	var gf := _route.get_frame(_gate_distance - 0.5)
	sign_text.transform = Transform3D(gf.basis, gf.origin + Vector3.UP * 7.3)
	add_child(sign_text)


func _ready() -> void:
	# Remember each light's base energy for flickering.
	await get_tree().process_frame
	for l: OmniLight3D in _flicker_lights:
		l.set_meta("base_energy", l.light_energy)
