class_name ZombieDirector
extends Node3D
## Runs the zombie threat.
##
## The real threat is a single number: how far along the route the front of
## the chasing horde is (front_distance). The host simulates it and sends it to
## everyone; each machine then positions the individual zombie models around
## that point. The danger is measured against the REARMOST rider, so the group
## is only as safe as its slowest member - stick together!

enum Phase { DORMANT, PURSUIT, GATE, FINAL_ESCAPE, STOPPED, OVERRUN }

const ZOMBIE_SCENE := preload("res://scenes/zombies/zombie.tscn")

@export_group("Visuals")
@export var random_seed: int = 666
@export var max_horde_models: int = 28
@export var wanderer_spacing: Vector2 = Vector2(16.0, 34.0)

@export_group("Pursuit")
## Base horde speed (m/s) while chasing. Easy riding roughly matches it.
@export var pursuit_speed: float = 8.0
## Horde speed after the gate opens - the final escape is harder.
@export var final_escape_speed: float = 9.2
## Gap (m) behind the rearmost rider where the horde first appears.
@export var start_gap: float = 55.0
## Beyond this gap the horde speeds up, so riders can't escape completely.
## Together with catch_up_rate this sets how close the horde hangs:
## steady gap = comfortable_gap + (rider speed - horde speed) / catch_up_rate.
@export var comfortable_gap: float = 35.0
## Extra m/s per metre of gap beyond comfortable_gap.
@export var catch_up_rate: float = 0.2
## The horde is never further behind than this.
@export var max_gap: float = 70.0

@export_group("Surges")
## Random time between horde surges (seconds). Forces the occasional sprint.
@export var surge_interval: Vector2 = Vector2(22.0, 34.0)
@export var surge_duration: float = 6.0
@export var surge_bonus_speed: float = 4.5

@export_group("Gate")
## While the team works the gate, the horde shuffles in to arrive after
## roughly this many seconds (clamped to gate_speed_range).
@export var gate_arrival_time: float = 38.0
@export var gate_speed_range: Vector2 = Vector2(1.2, 4.0)

@export_group("Danger")
## Danger starts rising once the horde is closer than this (m).
@export var danger_range: float = 60.0
## The rearmost rider is caught at this gap (m).
@export var catch_distance: float = 1.2

signal surge_started

# --- Synchronised state (host simulates, clients mirror) ---
var phase: Phase = Phase.DORMANT
var front_distance: float = -200.0
var current_speed: float = 0.0
var surging: bool = false

var route: Route

var _rng := RandomNumberGenerator.new()
var _surge_left: float = 0.0
var _next_surge: float = 0.0
var _gate_speed: float = 2.0
var _horde: Array[ZombieController] = []
var _horde_offsets: Array[Vector2] = []  # x = metres behind front, y = lateral
var _wanderers: Array[ZombieController] = []
var _wanderer_info: Array[Vector2] = []  # x = route distance, y = side (-1/1)
var _time: float = 0.0


func setup(p_route: Route, wanderers_from: float, wanderers_to: float) -> void:
	route = p_route
	var vis_rng := RandomNumberGenerator.new()
	vis_rng.seed = random_seed
	for i in max_horde_models:
		var z: ZombieController = ZOMBIE_SCENE.instantiate()
		z.setup(random_seed + i, ZombieController.Behaviour.HORDE)
		add_child(z)
		z.visible = false
		_horde.append(z)
		# Packed near the front, stragglers further back.
		_horde_offsets.append(Vector2(pow(vis_rng.randf(), 1.6) * 24.0, vis_rng.randf_range(-4.2, 4.2)))
	var d := wanderers_from
	var n := 0
	while d < wanderers_to:
		var side := -1.0 if vis_rng.randf() < 0.5 else 1.0
		var z: ZombieController = ZOMBIE_SCENE.instantiate()
		z.setup(random_seed + 1000 + n, ZombieController.Behaviour.WANDERER)
		add_child(z)
		var lateral := side * vis_rng.randf_range(6.5, 12.0)
		z.global_position = route.get_point(d, lateral)
		z.rotation.y = vis_rng.randf() * TAU
		_wanderers.append(z)
		_wanderer_info.append(Vector2(d, side))
		d += vis_rng.randf_range(wanderer_spacing.x, wanderer_spacing.y)
		n += 1


# --- Host-side simulation ----------------------------------------------------

func set_phase(new_phase: Phase, rearmost: float, hold_point: float = 0.0) -> void:
	if new_phase == phase:
		return
	match new_phase:
		Phase.PURSUIT:
			if phase == Phase.DORMANT:
				front_distance = rearmost - start_gap
			_schedule_surge()
		Phase.GATE:
			surging = false
			# Time the horde's arrival at the gate so the team has a fair window.
			var to_cover := hold_point - front_distance
			_gate_speed = clampf(to_cover / gate_arrival_time, gate_speed_range.x, gate_speed_range.y)
		Phase.FINAL_ESCAPE:
			_schedule_surge()
	phase = new_phase


## Host only: advance the horde. `rearmost` = distance of the slowest rider.
func simulate(delta: float, rearmost: float) -> void:
	match phase:
		Phase.DORMANT:
			current_speed = 0.0
			front_distance = rearmost - start_gap - 60.0
		Phase.PURSUIT, Phase.FINAL_ESCAPE:
			var base := pursuit_speed if phase == Phase.PURSUIT else final_escape_speed
			var gap := rearmost - front_distance
			var catch_up := maxf(0.0, gap - comfortable_gap) * catch_up_rate
			_update_surge(delta)
			current_speed = base + catch_up + (surge_bonus_speed if surging else 0.0)
			front_distance = maxf(front_distance + current_speed * delta, rearmost - max_gap)
		Phase.GATE:
			current_speed = _gate_speed
			front_distance += current_speed * delta
		Phase.STOPPED:
			current_speed = 0.0
		Phase.OVERRUN:
			current_speed = 3.0
			front_distance = minf(front_distance + current_speed * delta, rearmost + 1.5)


func _schedule_surge() -> void:
	_next_surge = _rng.randf_range(surge_interval.x, surge_interval.y)


func _update_surge(delta: float) -> void:
	if surging:
		_surge_left -= delta
		if _surge_left <= 0.0:
			surging = false
			_schedule_surge()
	else:
		_next_surge -= delta
		if _next_surge <= 0.0:
			surging = true
			_surge_left = surge_duration
			surge_started.emit()


# --- Queries -----------------------------------------------------------------

func get_gap(rearmost: float) -> float:
	return rearmost - front_distance


func get_danger(rearmost: float) -> float:
	if phase == Phase.DORMANT or phase == Phase.STOPPED:
		return 0.0
	if phase == Phase.OVERRUN:
		return 1.0
	return clampf(1.0 - (get_gap(rearmost) - catch_distance) / danger_range, 0.0, 1.0)


func is_catching(rearmost: float) -> bool:
	return phase in [Phase.PURSUIT, Phase.GATE, Phase.FINAL_ESCAPE] and get_gap(rearmost) <= catch_distance


# --- Network snapshot ----------------------------------------------------------

func get_snapshot() -> Array:
	return [phase, front_distance, current_speed, surging]


func apply_snapshot(snap: Array) -> void:
	phase = snap[0] as Phase
	current_speed = snap[2]
	surging = snap[3]
	# Ease towards the host's value to hide network jitter.
	var host_front: float = snap[1]
	if absf(host_front - front_distance) > 15.0:
		front_distance = host_front
	else:
		front_distance = lerpf(front_distance, host_front, 0.3)


## Clients: move the horde forward between snapshots.
func extrapolate(delta: float) -> void:
	front_distance += current_speed * delta


# --- Presentation (every machine) ----------------------------------------------

func update_visuals(delta: float, riders: Array) -> void:
	_time += delta
	if route == null:
		return
	var horde_visible := phase != Phase.DORMANT
	var active := max_horde_models if phase in [Phase.FINAL_ESCAPE, Phase.OVERRUN] else int(max_horde_models * 0.7)
	var squash := 0.35 if phase == Phase.OVERRUN else 1.0
	var forward := -route.get_frame(front_distance).basis.z
	for i in _horde.size():
		var z := _horde[i]
		z.visible = horde_visible and i < active
		if not z.visible:
			continue
		var off := _horde_offsets[i]
		# Small per-zombie wobble so the crowd doesn't move in lockstep.
		var wobble := sin(_time * 1.3 + i) * 0.6
		z.target_position = route.get_point(front_distance - off.x * squash + wobble, off.y * squash)
		z.target_facing = forward

	if riders.is_empty():
		return
	for i in _wanderers.size():
		var z := _wanderers[i]
		var info := _wanderer_info[i]
		var nearest: Vector3 = riders[0].global_position
		var best := INF
		for r: Node3D in riders:
			var dd := r.global_position.distance_squared_to(z.global_position)
			if dd < best:
				best = dd
				nearest = r.global_position
		# Skip far-away zombies entirely (performance).
		var far := best > 150.0 * 150.0
		z.visible = not far
		z.set_process(not far)
		if not far:
			z.update_wanderer(delta, nearest, route.get_point(info.x, info.y * 5.6))
