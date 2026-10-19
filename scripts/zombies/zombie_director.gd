class_name ZombieDirector
extends Node3D
## Runs the zombie threat.
##
## The real threat is a single number: how far along the route the front of
## the chasing horde is (front_distance). The host simulates it and sends it to
## everyone; each machine then positions the individual zombie models around
## that point. The danger is measured against the REARMOST rider, so the group
## is only as safe as its slowest member - stick together!
##
## Pursuit is gap-based rather than speed-based: the horde drifts towards a
## "target gap" that depends on how fast the rearmost rider is going, and the
## speed at which it can close in is capped. So the danger meter tracks your
## effort smoothly, the horde never vanishes into the distance, and slowing
## down gives a few seconds of rising warning instead of instant death.
## Reaching the rider starts a short "grab" you can still sprint out of.

enum Phase { DORMANT, PURSUIT, GATE, FINAL_ESCAPE, STOPPED, OVERRUN }

const ZOMBIE_SCENE := preload("res://scenes/zombies/zombie.tscn")

@export_group("Visuals")
@export var random_seed: int = 666
@export var max_horde_models: int = 28
@export var wanderer_spacing: Vector2 = Vector2(16.0, 34.0)

@export_group("Pursuit")
## The horde's pace (m/s) before the gate. Riding at exactly this speed keeps
## the horde at base_gap. (9.5 m/s = 34 km/h)
@export var pursuit_pace: float = 9.5
## The horde's pace after the gate opens - the final escape is harder.
@export var final_escape_pace: float = 10.2
## Gap (m) the horde settles at when you ride at its pace.
## Settled gap = base_gap + (your speed - pace) * gap_per_mps, within 0..max_gap.
@export var base_gap: float = 22.0
## How many metres of gap each m/s above (or below) the pace is worth.
@export var gap_per_mps: float = 6.0
## The horde never falls further behind than this, so it stays in view.
@export var max_gap: float = 45.0
## Gap (m) where the horde first appears.
@export var start_gap: float = 45.0
## How quickly the gap moves towards its settled value (per second).
@export var gap_response: float = 0.3
## Fastest the horde can close in (m/s). This is your warning time:
## from 30 m it takes at least 10 s to reach you.
@export var max_close_rate: float = 3.0
## Fastest you can pull away from the horde (m/s).
@export var max_open_rate: float = 1.5
## Your speed is averaged over roughly this many seconds, so brief dips
## don't instantly change the horde's behaviour.
@export var speed_smoothing_time: float = 1.5

@export_group("Surges")
## Random time between horde surges (seconds). Forces the occasional sprint.
@export var surge_interval: Vector2 = Vector2(22.0, 34.0)
@export var surge_duration: float = 6.0
## During a surge the settled gap shrinks by this many metres...
@export var surge_gap_drop: float = 18.0
## ...and the horde may close in this fast (m/s).
@export var surge_close_rate: float = 4.5

@export_group("Runners")
## Random time between runners breaking out of the horde (seconds).
## (0, 0) = no runners (the story mission); Endless Survival turns them on.
@export var runner_interval: Vector2 = Vector2.ZERO
## A runner sprints this much faster than the horde's pace (m/s)...
@export var runner_speed_bonus: float = 3.5
## ...but never faster than this (m/s), so a full sprint can always escape.
## 15.5 m/s = 56 km/h.
@export var runner_max_speed: float = 15.5
## ...for this long (s), then tires and drops back into the horde.
@export var runner_burst_time: float = 7.0
## A runner this close (m) to its prey claws at them.
@export var runner_reach: float = 1.2
@export var max_runners: int = 2

@export_group("Gate")
## While the team works the gate, the horde shuffles in to arrive after
## roughly this many seconds (clamped to gate_speed_range).
@export var gate_arrival_time: float = 38.0
@export var gate_speed_range: Vector2 = Vector2(1.2, 4.0)

@export_group("Danger")
## Danger starts rising once the horde is closer than this (m).
@export var danger_range: float = 40.0
## At this gap (m) the zombies grab the rearmost rider...
@export var catch_distance: float = 1.5
## ...who then has this many seconds to sprint free before the group is lost.
@export var escape_time: float = 3.0

signal surge_started
## Host: a runner broke out of the horde.
signal runner_started
## Host: a runner reached its prey (the distance it was chasing).
signal runner_reached(prey_distance: float)

# --- Synchronised state (host simulates, clients mirror) ---
var phase: Phase = Phase.DORMANT
var front_distance: float = -200.0
var current_speed: float = 0.0
var surging: bool = false
## 0..1 while zombies are grabbing the rearmost rider; 1 = caught.
var grab_progress: float = 0.0
## Runners chasing the riders: each is [distance, speed, seconds running].
var runners: Array = []
## Host: what runners chase (set by the mission each frame; NAN = the
## rearmost rider). Endless mode points them at exhausted survivors.
var runner_prey: float = NAN

var route: Route

var _rng := RandomNumberGenerator.new()
var _surge_left: float = 0.0
var _next_surge: float = 0.0
var _gate_speed: float = 2.0
var _avg_speed: float = 0.0
var _horde: Array[ZombieController] = []
var _horde_offsets: Array[Vector2] = []  # x = metres behind front, y = lateral
var _runner_models: Array[ZombieController] = []
var _next_runner: float = 0.0
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
	for i in 3:
		var r: ZombieController = ZOMBIE_SCENE.instantiate()
		r.setup(random_seed + 500 + i, ZombieController.Behaviour.RUNNER)
		add_child(r)
		r.visible = false
		_runner_models.append(r)
	spawn_wanderers(wanderers_from, wanderers_to, random_seed)


## Places roadside zombies along a stretch of road (deterministic per seed).
func spawn_wanderers(from_d: float, to_d: float, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var d := from_d + rng.randf_range(0.0, wanderer_spacing.x)
	var n := 0
	while d < to_d:
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var z: ZombieController = ZOMBIE_SCENE.instantiate()
		z.setup(seed_value + 1000 + n, ZombieController.Behaviour.WANDERER)
		add_child(z)
		var lateral := side * rng.randf_range(6.5, 12.0)
		z.global_position = route.get_point(d, lateral)
		z.rotation.y = rng.randf() * TAU
		_wanderers.append(z)
		_wanderer_info.append(Vector2(d, side))
		d += rng.randf_range(wanderer_spacing.x, wanderer_spacing.y)
		n += 1


## Removes roadside zombies placed before this distance (endless mode).
func despawn_wanderers_before(distance: float) -> void:
	for i in range(_wanderers.size() - 1, -1, -1):
		if _wanderer_info[i].x < distance:
			_wanderers[i].queue_free()
			_wanderers.remove_at(i)
			_wanderer_info.remove_at(i)


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
			runners.clear()
			# Time the horde's arrival at the gate so the team has a fair window.
			var to_cover := hold_point - front_distance
			_gate_speed = clampf(to_cover / gate_arrival_time, gate_speed_range.x, gate_speed_range.y)
		Phase.FINAL_ESCAPE:
			_schedule_surge()
			# Opening the gate in the nick of time is a save.
			shake_off(rearmost, 8.0)
	if new_phase == Phase.PURSUIT or new_phase == Phase.FINAL_ESCAPE:
		_schedule_runner()
	phase = new_phase


## Host only: the zombies let go and fall back to at least `gap` metres
## (e.g. a gate swinging open knocks them back).
func shake_off(rearmost: float, gap: float) -> void:
	grab_progress = 0.0
	front_distance = minf(front_distance, rearmost - gap)
	runners.clear()


## Host only: start a surge right now (e.g. a screamer went off).
func force_surge(duration: float) -> void:
	_surge_left = maxf(_surge_left, duration) if surging else duration
	surging = true


## Host only: advance the horde. `rearmost` / `rear_speed` = distance and
## speed of the slowest rider.
func simulate(delta: float, rearmost: float, rear_speed: float) -> void:
	_avg_speed = lerpf(_avg_speed, rear_speed, clampf(delta / speed_smoothing_time, 0.0, 1.0))
	var old_front := front_distance
	match phase:
		Phase.DORMANT:
			front_distance = rearmost - start_gap - 60.0
		Phase.PURSUIT, Phase.FINAL_ESCAPE:
			_update_surge(delta)
			var gap := rearmost - front_distance
			var target := get_target_gap(_avg_speed)
			var close_limit := surge_close_rate if surging else max_close_rate
			# How fast the gap may change, then move the horde at the rider's
			# speed minus that change (it never walks backwards).
			var change := clampf((target - gap) * gap_response, -close_limit, max_open_rate)
			front_distance += maxf(rear_speed - change, 0.0) * delta
			_apply_gap(clampf(rearmost - front_distance, 0.0, max_gap), rearmost, delta)
			_update_runners(delta, rearmost)
		Phase.GATE:
			# Riders are stuck at the gate: the horde shuffles in at a fixed pace.
			_apply_gap(rearmost - front_distance - _gate_speed * delta, rearmost, delta)
		Phase.OVERRUN:
			front_distance = minf(front_distance + 3.0 * delta, rearmost + 1.5)
			runners.clear()
	current_speed = 0.0 if phase == Phase.STOPPED else (front_distance - old_front) / maxf(delta, 0.0001)


## The gap the horde drifts towards for a given rider speed.
func get_target_gap(speed: float) -> float:
	var pace := pursuit_pace if phase == Phase.PURSUIT else final_escape_pace
	var target := base_gap + (speed - pace) * gap_per_mps
	if surging:
		target -= surge_gap_drop
	# A target below zero means "push into the riders": the horde keeps
	# closing at full rate instead of easing off as it reaches them.
	return clampf(target, -10.0, max_gap)


## Moves the horde to a new gap, handling the "grab" at the rider's wheel.
func _apply_gap(new_gap: float, rearmost: float, delta: float) -> void:
	if new_gap <= catch_distance:
		new_gap = catch_distance
		grab_progress = minf(grab_progress + delta / escape_time, 1.0)
	elif new_gap > catch_distance + 0.5:
		# Pulling away: the grip loosens (faster than it tightens).
		grab_progress = maxf(grab_progress - delta * 2.0 / escape_time, 0.0)
	front_distance = rearmost - new_gap


func _schedule_runner() -> void:
	_next_runner = _rng.randf_range(runner_interval.x, runner_interval.y)


## Runners break out of the horde, sprint at the prey for a few seconds, and
## claw at them if they get close. Outpace them and they tire and drop back.
func _update_runners(delta: float, rearmost: float) -> void:
	var prey := rearmost if is_nan(runner_prey) else runner_prey
	var pace := pursuit_pace if phase == Phase.PURSUIT else final_escape_pace
	if runner_interval.y > 0.0:
		_next_runner -= delta
		if _next_runner <= 0.0:
			_schedule_runner()
			if runners.size() < max_runners and not is_grabbing():
				runners.append([front_distance + 0.5, current_speed, 0.0])
				runner_started.emit()
	for i in range(runners.size() - 1, -1, -1):
		var r: Array = runners[i]
		r[2] += delta
		var sprinting: bool = r[2] < runner_burst_time
		var target_speed := minf(pace + runner_speed_bonus, runner_max_speed) if sprinting else maxf(current_speed - 2.5, 0.0)
		r[1] = move_toward(r[1], target_speed, 6.0 * delta)
		r[0] += r[1] * delta
		if sprinting and prey - r[0] < runner_reach:
			runners.remove_at(i)
			runner_reached.emit(prey)
		elif not sprinting and r[0] < front_distance:
			runners.remove_at(i)  # back in the horde


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
	if phase == Phase.OVERRUN or grab_progress > 0.0:
		return 1.0
	return clampf(1.0 - (get_gap(rearmost) - catch_distance) / danger_range, 0.0, 1.0)


func is_grabbing() -> bool:
	return grab_progress > 0.0 and phase in [Phase.PURSUIT, Phase.GATE, Phase.FINAL_ESCAPE]


## True once the rearmost rider failed to break free in time.
func is_catching(_rearmost: float = 0.0) -> bool:
	return phase in [Phase.PURSUIT, Phase.GATE, Phase.FINAL_ESCAPE] and grab_progress >= 1.0


## World position of a random visible zombie in the horde (for 3D sound).
func random_horde_position() -> Vector3:
	var visible_zombies := _horde.filter(func(z: ZombieController) -> bool: return z.visible)
	if visible_zombies.is_empty():
		return route.get_point(front_distance)
	return (visible_zombies[randi() % visible_zombies.size()] as ZombieController).global_position


# --- Network snapshot ----------------------------------------------------------

func get_snapshot() -> Array:
	var runner_data := PackedFloat32Array()
	for r: Array in runners:
		runner_data.append_array([r[0], r[1]])
	return [phase, front_distance, current_speed, surging, grab_progress, runner_data]


func apply_snapshot(snap: Array) -> void:
	phase = snap[0] as Phase
	current_speed = snap[2]
	surging = snap[3]
	grab_progress = snap[4]
	var runner_data: PackedFloat32Array = snap[5]
	var count := runner_data.size() / 2
	while runners.size() > count:
		runners.pop_back()
	for i in count:
		var host_d := runner_data[i * 2]
		if i >= runners.size():
			runners.append([host_d, runner_data[i * 2 + 1], 0.0])
		elif absf(host_d - float(runners[i][0])) > 10.0:
			runners[i] = [host_d, runner_data[i * 2 + 1], 0.0]
		else:
			runners[i] = [lerpf(runners[i][0], host_d, 0.3), runner_data[i * 2 + 1], 0.0]
	# Ease towards the host's value to hide network jitter.
	var host_front: float = snap[1]
	if absf(host_front - front_distance) > 15.0:
		front_distance = host_front
	else:
		front_distance = lerpf(front_distance, host_front, 0.3)


## Clients: move the horde forward between snapshots.
func extrapolate(delta: float) -> void:
	front_distance += current_speed * delta
	for r: Array in runners:
		r[0] += r[1] * delta


## Distance (m) from the nearest runner to `distance`, or INF if none.
func nearest_runner_gap(distance: float) -> float:
	var best := INF
	for r: Array in runners:
		best = minf(best, distance - float(r[0]))
	return best


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
	for i in _runner_models.size():
		var rm := _runner_models[i]
		var running := i < runners.size()
		if running and not rm.visible:
			rm.snap_to_target = true
		rm.visible = running
		if running:
			var rd: float = runners[i][0]
			rm.target_position = route.get_point(rd, -0.6 + i * 1.2)
			rm.target_facing = -route.get_frame(rd).basis.z

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
