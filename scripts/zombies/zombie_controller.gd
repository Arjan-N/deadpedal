class_name ZombieController
extends Node3D
## A single zombie: placeholder model, shambling animation and simple
## behaviours. Zombies are presentation only - the actual threat (how close
## the horde is) is simulated by ZombieDirector on the host, so every player
## sees the same danger even if individual zombies wobble differently.
##
## New behaviours (road blockers, runners, building ambushes...) can be added
## to the Behaviour enum and handled in _process.

enum Behaviour {
	HORDE,     ## Placed each frame by ZombieDirector at the chasing horde.
	WANDERER,  ## Idles by the roadside, lurches at riders who pass close by.
	RUNNER,    ## Sprints ahead of the horde (placed by ZombieDirector).
}

const SKIN_TONES: Array[Color] = [Color(0.45, 0.5, 0.4), Color(0.5, 0.48, 0.42), Color(0.38, 0.42, 0.36), Color(0.55, 0.5, 0.45)]
const CLOTHES: Array[Color] = [Color(0.25, 0.22, 0.2), Color(0.2, 0.25, 0.3), Color(0.35, 0.3, 0.22), Color(0.3, 0.15, 0.12), Color(0.4, 0.4, 0.38), Color(0.15, 0.18, 0.15)]

@export var behaviour: Behaviour = Behaviour.HORDE
## Walking speed used by wanderers when lurching at a rider (m/s).
@export var lurch_speed: float = 2.6
## Wanderers notice riders within this distance.
@export var notice_range: float = 30.0

## Movement speed used to drive the animation (m/s).
var move_speed: float = 0.0
## Horde targets (set by ZombieDirector).
var target_position: Vector3
var target_facing: Vector3 = Vector3.FORWARD
## Jump straight to target_position next frame (e.g. a runner reappearing).
var snap_to_target := false

var _rng := RandomNumberGenerator.new()
var _phase: float = 0.0
var _body: Node3D
var _legs: Array[Node3D] = []
var _arms: Array[Node3D] = []
var _head: Node3D
var _lurching := false
var _gave_up := false
var _initialised := false


## Builds the model. `seed_value` makes each zombie look different but
## identical on every player's machine.
func setup(seed_value: int, p_behaviour: Behaviour) -> void:
	behaviour = p_behaviour
	_rng.seed = seed_value
	_phase = _rng.randf() * TAU
	_build()


func _build() -> void:
	var skin := MeshKit.mat(SKIN_TONES[_rng.randi() % SKIN_TONES.size()])
	var shirt := MeshKit.mat(CLOTHES[_rng.randi() % CLOTHES.size()])
	var trousers := MeshKit.mat(CLOTHES[_rng.randi() % CLOTHES.size()].darkened(0.3))
	var blood := MeshKit.mat(Color(0.3, 0.03, 0.02), 0.6)
	var eye := MeshKit.mat(Color(0.95, 0.85, 0.5), 0.4, 1.5)
	var s := _rng.randf_range(0.9, 1.08)
	scale = Vector3.ONE * s

	for side: float in [-1.0, 1.0]:
		var hip := Node3D.new()
		hip.position = Vector3(0.12 * side, 0.9, 0)
		add_child(hip)
		MeshKit.capsule(hip, 0.08, 0.9, Vector3(0, -0.45, 0), trousers)
		_legs.append(hip)

	_body = Node3D.new()
	_body.position = Vector3(0, 0.9, 0)
	add_child(_body)
	MeshKit.capsule(_body, 0.2, 0.75, Vector3(0, 0.35, 0), shirt)
	if _rng.randf() < 0.6:
		MeshKit.box(_body, Vector3(0.25, 0.2, 0.05), Vector3(0.05, 0.35, -0.19), blood)
	_head = Node3D.new()
	_head.position = Vector3(0, 0.85, -0.04)
	_body.add_child(_head)
	MeshKit.sphere(_head, 0.13, Vector3(0, 0.08, 0), skin)
	MeshKit.sphere(_head, 0.022, Vector3(-0.05, 0.1, -0.12), eye)
	MeshKit.sphere(_head, 0.022, Vector3(0.05, 0.1, -0.12), eye)

	for side: float in [-1.0, 1.0]:
		var shoulder := Node3D.new()
		shoulder.position = Vector3(0.25 * side, 0.65, 0)
		_body.add_child(shoulder)
		# Arms stretched forwards (-Z), the classic zombie reach.
		MeshKit.capsule(shoulder, 0.06, 0.7, Vector3(0, 0, -0.3), skin, Vector3(90, 0, 0))
		_arms.append(shoulder)
	_body.rotation.x = deg_to_rad(_rng.randf_range(-22, -8))
	if behaviour == Behaviour.RUNNER:
		# Leaner and leaning hard into the sprint.
		scale = Vector3(0.95, 1.05, 0.95)
		_body.rotation.x = deg_to_rad(-35)


func _process(delta: float) -> void:
	match behaviour:
		Behaviour.HORDE, Behaviour.RUNNER:
			_update_horde(delta)
		Behaviour.WANDERER:
			pass  # driven by update_wanderer() from ZombieDirector
	_animate(delta)


func _update_horde(delta: float) -> void:
	if not _initialised or snap_to_target:
		global_position = target_position
		_initialised = true
		snap_to_target = false
	var before := global_position
	global_position = global_position.lerp(target_position, clampf(delta * 6.0, 0.0, 1.0))
	if target_facing.length_squared() > 0.001:
		var look := global_position + target_facing
		look.y = global_position.y
		look_at(look, Vector3.UP)
	move_speed = lerpf(move_speed, before.distance_to(global_position) / maxf(delta, 0.0001), 0.2)


## Wanderer behaviour. `nearest_rider` is the closest rider's position.
func update_wanderer(delta: float, nearest_rider: Vector3, road_point: Vector3) -> void:
	var to_rider := nearest_rider - global_position
	to_rider.y = 0.0
	var dist := to_rider.length()
	if not _lurching and not _gave_up and dist < notice_range:
		_lurching = true
	if _lurching:
		# Stagger to the edge of the road and reach for passing riders.
		# (Wanderers are scenery; only the horde can catch the group.)
		var dir := road_point - global_position
		dir.y = 0.0
		if dir.length() > 0.5:
			global_position += dir.normalized() * lurch_speed * delta
			look_at(global_position + dir, Vector3.UP)
			move_speed = lurch_speed
		else:
			move_speed = 0.0
		if dist > notice_range * 1.6:
			_lurching = false
			_gave_up = true
	else:
		move_speed = 0.0


func _animate(delta: float) -> void:
	if _body == null:
		return
	var walk := clampf(move_speed / 3.0, 0.0, 2.0)
	_phase += delta * (2.0 + walk * 4.5)
	var swing := sin(_phase) * (0.15 + 0.45 * walk)
	_legs[0].rotation.x = swing
	_legs[1].rotation.x = -swing
	_body.rotation.z = sin(_phase) * 0.12
	_body.position.y = 0.9 + absf(sin(_phase)) * 0.05 * walk
	if behaviour == Behaviour.RUNNER:
		# Arms pumping instead of reaching.
		_arms[0].rotation.x = -1.0 + swing * 0.8
		_arms[1].rotation.x = -1.0 - swing * 0.8
		return
	_arms[0].rotation.x = sin(_phase * 0.7) * 0.25 + 0.1
	_arms[1].rotation.x = sin(_phase * 0.7 + 1.5) * 0.25 + 0.1
	_head.rotation.z = sin(_phase * 0.5) * 0.3
