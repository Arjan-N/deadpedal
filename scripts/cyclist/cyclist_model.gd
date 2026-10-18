class_name CyclistModel
extends Node3D
## Placeholder bike + rider built from primitives, with a pedalling animation.
## Legs use simple two-bone IK so the feet stay on the pedals.
## Replace this node with an imported, animated model later; the controller
## only calls set_jersey_color() and animate().

const WHEEL_RADIUS := 0.35
const BOTTOM_BRACKET := Vector3(0.0, 0.3, 0.05)
const CRANK_LENGTH := 0.17
const HIP := Vector3(0.0, 0.98, 0.22)
const THIGH := 0.46
const SHIN := 0.46

@export var headlight_enabled: bool = true

var jersey_color: Color = Color(0.85, 0.3, 0.1)

var crank_angle: float = 0.0
var _wheels: Array[Node3D] = []
var _legs: Array = []  # [thigh, shin, foot, crank_arm, side_x]
var _rider: Node3D
var _time: float = 0.0


## Builds the model. Called once by the CyclistController.
func build(color: Color) -> void:
	jersey_color = color
	var frame_mat := MeshKit.mat(Color(0.12, 0.12, 0.13), 0.4, 0.0, 0.6)
	var tyre_mat := MeshKit.mat(Color(0.05, 0.05, 0.05), 0.95)
	var spoke_mat := MeshKit.mat(Color(0.6, 0.6, 0.62), 0.3, 0.0, 0.8)
	var skin_mat := MeshKit.mat(Color(0.78, 0.6, 0.48))
	var shorts_mat := MeshKit.mat(Color(0.08, 0.08, 0.1))
	var jersey_mat := MeshKit.mat(jersey_color, 0.7)
	var accent_mat := MeshKit.mat(jersey_color.lightened(0.35), 0.5)

	# Wheels (pivots spin around X).
	for z: float in [0.52, -0.52]:
		var pivot := Node3D.new()
		pivot.position = Vector3(0.0, WHEEL_RADIUS, z)
		add_child(pivot)
		MeshKit.torus(pivot, 0.30, 0.35, Vector3.ZERO, tyre_mat, Vector3(0, 0, 90))
		MeshKit.box(pivot, Vector3(0.015, 0.6, 0.015), Vector3.ZERO, spoke_mat)
		MeshKit.box(pivot, Vector3(0.015, 0.015, 0.6), Vector3.ZERO, spoke_mat)
		_wheels.append(pivot)

	# Frame tubes.
	var rear := Vector3(0, WHEEL_RADIUS, 0.52)
	var front := Vector3(0, WHEEL_RADIUS, -0.52)
	var seat := Vector3(0, 0.9, 0.2)
	var head_top := Vector3(0, 0.92, -0.38)
	var head_bottom := Vector3(0, 0.74, -0.42)
	for pair: Array in [[BOTTOM_BRACKET, seat], [seat, head_top], [BOTTOM_BRACKET, head_bottom],
			[head_bottom, front], [BOTTOM_BRACKET, rear], [seat, rear], [head_bottom, head_top]]:
		var tube := MeshKit.cylinder(self, 0.022, (pair[1] - pair[0]).length(), Vector3.ZERO, frame_mat)
		MeshKit.place_between(tube, pair[0], pair[1])
	MeshKit.cylinder(self, 0.018, 0.44, Vector3(0, 0.97, -0.42), frame_mat, Vector3(0, 0, 90))
	MeshKit.box(self, Vector3(0.12, 0.05, 0.26), Vector3(0, 0.94, 0.23), shorts_mat)

	# Rider upper body.
	_rider = Node3D.new()
	add_child(_rider)
	var shoulder := Vector3(0, 1.4, -0.16)
	var torso := MeshKit.capsule(_rider, 0.17, 0.62, Vector3.ZERO, jersey_mat)
	MeshKit.place_between(torso, HIP + Vector3(0, 0.05, 0), shoulder)
	MeshKit.sphere(_rider, 0.11, Vector3(0, 1.57, -0.3), skin_mat)
	MeshKit.sphere(_rider, 0.13, Vector3(0, 1.63, -0.27), accent_mat, Vector3(1.0, 0.7, 1.25))
	for side: float in [-1.0, 1.0]:
		var arm := MeshKit.capsule(_rider, 0.05, 0.55, Vector3.ZERO, jersey_mat)
		MeshKit.place_between(arm, Vector3(0.19 * side, 1.37, -0.16), Vector3(0.21 * side, 0.98, -0.42))

	# Legs (re-posed every frame by _pose_legs).
	for side: float in [-1.0, 1.0]:
		var thigh := MeshKit.cylinder(self, 0.06, THIGH, Vector3.ZERO, shorts_mat)
		var shin := MeshKit.cylinder(self, 0.045, SHIN, Vector3.ZERO, skin_mat)
		var foot := MeshKit.box(self, Vector3(0.08, 0.06, 0.2), Vector3.ZERO, frame_mat)
		var crank := MeshKit.box(self, Vector3(0.02, 0.02, CRANK_LENGTH), Vector3.ZERO, spoke_mat)
		_legs.append([thigh, shin, foot, crank, side * 0.11])

	if headlight_enabled:
		var lamp := SpotLight3D.new()
		lamp.position = Vector3(0, 1.0, -0.5)
		lamp.light_color = Color(1.0, 0.92, 0.75)
		lamp.light_energy = 3.0
		lamp.spot_range = 28.0
		lamp.spot_angle = 28.0
		lamp.rotation_degrees = Vector3(-6, 0, 0)
		add_child(lamp)
		MeshKit.sphere(self, 0.04, Vector3(0, 0.97, -0.5), MeshKit.mat(Color(1, 0.95, 0.8), 0.2, 4.0))

	# Soft fill light so riders stay readable in dark streets.
	var fill := OmniLight3D.new()
	fill.position = Vector3(0, 2.4, 1.6)
	fill.light_energy = 0.6
	fill.omni_range = 4.5
	fill.light_color = Color(0.85, 0.9, 1.0)
	add_child(fill)

	_pose_legs()


## speed in m/s, cadence in rpm (<0 = unknown), lean in radians.
func animate(delta: float, speed: float, cadence: float, lean: float) -> void:
	if _rider == null:
		return
	_time += delta
	for w in _wheels:
		w.rotation.x -= speed / WHEEL_RADIUS * delta
	# Pedal from cadence if we have it (so you still see pedalling while
	# standing at the gate), otherwise derive it from wheel speed.
	var rpm := cadence if cadence >= 0.0 else speed * 9.0
	crank_angle += rpm / 60.0 * TAU * delta
	_pose_legs()
	# Gentle body rock while pedalling hard + lean into bends.
	var effort_rock := clampf(rpm / 110.0, 0.0, 1.0)
	_rider.rotation.z = sin(crank_angle) * 0.04 * effort_rock
	rotation.z = lerp_angle(rotation.z, lean, clampf(delta * 4.0, 0.0, 1.0))


func _pose_legs() -> void:
	for i in _legs.size():
		var leg: Array = _legs[i]
		var side_x: float = leg[4]
		var angle := crank_angle + PI * i
		# Crank turns top -> front -> bottom -> back (bike faces -Z).
		var pedal := BOTTOM_BRACKET + Vector3(side_x * 1.3, CRANK_LENGTH * cos(angle), -CRANK_LENGTH * sin(angle))
		var hip := HIP + Vector3(side_x, 0, 0)
		var knee := _solve_knee(hip, pedal)
		MeshKit.place_between(leg[0], hip, knee)
		MeshKit.place_between(leg[1], knee, pedal)
		(leg[2] as Node3D).position = pedal + Vector3(0, 0.02, -0.03)
		var crank_mid := (BOTTOM_BRACKET + Vector3(side_x * 1.4, 0, 0) + pedal) * 0.5
		(leg[3] as Node3D).position = crank_mid
		(leg[3] as Node3D).rotation = Vector3(angle - PI * 0.5, 0, 0)


## Two-bone IK in the Y/Z plane: knee always bends forwards (-Z).
func _solve_knee(hip: Vector3, foot: Vector3) -> Vector3:
	var to_foot := foot - hip
	var d := clampf(to_foot.length(), 0.05, THIGH + SHIN - 0.001)
	var dir := to_foot.normalized()
	var a := (THIGH * THIGH - SHIN * SHIN + d * d) / (2.0 * d)
	var h := sqrt(maxf(THIGH * THIGH - a * a, 0.0))
	var perp := Vector3(0, -dir.z, dir.y)
	if perp.z > 0.0:
		perp = -perp
	return hip + dir * a + perp * h
