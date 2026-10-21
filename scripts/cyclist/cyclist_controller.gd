class_name CyclistController
extends Node3D
## One rider on the route.
##
## The owning player's game instance simulates this rider from the local
## CyclingInputManager and broadcasts the result. Every other instance just
## displays the received state smoothly. (Clients are authoritative over their
## own rider; the host is authoritative over everything else - see
## MissionManager.)

## How effort becomes speed. Edit the resource in the Inspector to tune.
@export var ride_model: RideModel
## Riders within this distance behind another rider get a slipstream bonus.
@export var draft_range_m: float = 10.0
## How often (per second) the owner sends its state to other players.
@export var network_send_rate: float = 20.0

# Identity (set by MissionManager before adding to the tree).
var peer_id: int = 1
var player_name: String = "Rider"
var jersey_color: Color = Color(0.85, 0.3, 0.1)
var lane_offset: float = 0.0
var route: Route

# Ride state (authoritative on the owner, mirrored elsewhere).
var distance: float = 0.0
var speed: float = 0.0
var power_watts: float = 0.0
## Power averaged over the last 3 seconds, for display. Trainers report
## power in noisy bursts; cycling apps show a 3 s average for that reason.
var power_avg: float = 0.0
var effort: float = 0.0
var cadence: float = -1.0
var max_speed_reached: float = 0.0
var is_drafting: bool = false
## Who the local rider is drafting behind (shown on the HUD).
var drafting_behind: String = ""

## Set by MissionManager: riding only starts after the countdown.
var can_ride: bool = false
## Set by MissionManager: the rider cannot pass this distance (closed gate).
var distance_limit: float = INF
## Set when the rider is caught by the horde.
var is_caught: bool = false

# Criterium (set by RaceManager):
## Computer rider: effort comes from bot_effort instead of the cycling input.
var is_bot: bool = false
var bot_effort: float = 0.0
## Shown as watts for computer riders.
var bot_ftp: float = 250.0
## Slipstream decided by the race (gap-dependent); -1 = the usual on/off
## slipstream behind other riders. With `physics` it's the fraction of air
## drag saved, otherwise a speed bonus.
var draft_bonus_override: float = -1.0
## Real-world physics instead of ride_model (the criterium).
var physics: RidePhysics
## Computer riders: extra braking (m/s^2) to avoid riding into a wheel.
var bot_brake: float = 0.0
## Criterium draft assist for your rider, like Zwift's "sticky" draft:
## 0 = off, 1 = normal, 2 = strong. When you're right behind someone and your
## power is roughly what it takes to follow, you're held on their wheel; a bit
## too much and the brakes are touched. Surge clearly to pass, ease off
## clearly to drop back.
var draft_assist: int = 0
## The wheel just ahead on the circuit and the gap to it (set by the race).
var wheel: CyclistController
var wheel_gap: float = INF
## The assist is holding you on the wheel (shown on the HUD).
var wheel_locked: bool = false

## Draft assist per level: effort (relative to what the wheel needs) that
## still counts as following [low, high]; up to this much is braked rather
## than passing; how firmly you're held (m/s^2).
const ASSIST_BAND: Array[Vector2] = [Vector2.ZERO, Vector2(0.7, 1.3), Vector2(0.55, 1.5)]
const ASSIST_BRAKE_UP_TO: Array[float] = [0.0, 1.6, 1.9]
const ASSIST_PULL: Array[float] = [0.0, 1.0, 2.0]
const ASSIST_BRAKE := 0.8
## Gaps (m) where the assist works, and the gap it holds you at.
const ASSIST_RANGE := Vector2(0.3, 4.0)
const ASSIST_HOLD_GAP := 1.0
enum AssistAction { NONE, HOLD, BRAKE }
## Sprint battery (effort-seconds above threshold). capacity 0 = no battery.
var battery_capacity: float = 0.0
var battery: float = 0.0
var battery_recharge: float = 0.5
var battery_threshold: float = RideModel.FTP_EFFORT
## Highest effort that counts (1 = 160% FTP). The criterium allows more,
## for real sprints.
var max_effort: float = 1.0
## The effort the rider asked for before the battery capped it.
var requested_effort: float = 0.0

var _send_timer: float = 0.0
const POWER_AVG_BUCKETS := 30  # 30 x 0.1 s = 3 s
var _power_buckets := PackedFloat32Array()
var _power_bucket_index: int = 0
var _bucket_energy: float = 0.0
var _bucket_time: float = 0.0
var _net_distance: float = 0.0
var _net_speed: float = 0.0
var _net_age: float = 0.0
@onready var model: CyclistModel = $Model
@onready var name_tag: Label3D = $NameTag


func _ready() -> void:
	if ride_model == null:
		ride_model = RideModel.new()
	model.build(jersey_color)
	name_tag.text = player_name
	name_tag.modulate = jersey_color.lightened(0.3)
	name_tag.visible = is_bot or not is_local()
	_net_distance = distance
	_apply_transform(0.0)


func is_local() -> bool:
	return is_multiplayer_authority()


## Simulated on this machine (the local player, or a computer rider).
func is_simulated_here() -> bool:
	return is_bot or is_local()


func _process(delta: float) -> void:
	if is_simulated_here():
		_simulate(delta)
		_send_timer -= delta
		if _send_timer <= 0.0 and multiplayer.has_multiplayer_peer() and can_ride and not is_bot:
			_send_timer = 1.0 / network_send_rate
			_net_state.rpc(distance, speed, power_watts, effort, cadence)
	else:
		_follow_network(delta)
	max_speed_reached = maxf(max_speed_reached, speed)
	_update_power_avg(delta)
	_apply_transform(delta)


func _update_power_avg(delta: float) -> void:
	if _power_buckets.is_empty():
		_power_buckets.resize(POWER_AVG_BUCKETS)
		_power_buckets.fill(power_watts)
	_bucket_energy += power_watts * delta
	_bucket_time += delta
	if _bucket_time >= 0.1:
		_power_buckets[_power_bucket_index] = _bucket_energy / _bucket_time
		_power_bucket_index = (_power_bucket_index + 1) % POWER_AVG_BUCKETS
		_bucket_energy = 0.0
		_bucket_time = 0.0
		var total := 0.0
		for p in _power_buckets:
			total += p
		power_avg = total / POWER_AVG_BUCKETS


func _simulate(delta: float) -> void:
	if is_bot:
		effort = bot_effort
		power_watts = bot_effort * bot_ftp * 1.6
		cadence = 88.0 + bot_effort * 12.0 if bot_effort > 0.05 else 0.0
	else:
		power_watts = CyclingInputManager.get_power_watts()
		effort = CyclingInputManager.get_effort()
		cadence = CyclingInputManager.get_cadence_rpm()
		# Input effort tops out at 1 (160% FTP); the criterium counts real
		# sprint power beyond that.
		if max_effort > 1.0 and effort >= 1.0:
			effort = power_watts / (CyclingInputManager.rider_ftp_watts * 1.6)
	requested_effort = effort
	if battery_capacity > 0.0:
		# Above max_effort is no faster, so it doesn't cost extra either.
		effort = RideModel.cap_effort(minf(effort, max_effort), battery, battery_threshold)
		if can_ride:
			battery = RideModel.step_battery(battery, effort, delta, battery_capacity, battery_recharge, battery_threshold)
	if not can_ride or is_caught:
		speed = move_toward(speed, 0.0, 6.0 * delta)
		return
	if physics:
		is_drafting = draft_bonus_override > 0.005
		speed = physics.step_speed(speed, effort, delta, maxf(draft_bonus_override, 0.0), bot_brake if is_bot else 0.0)
		_apply_draft_assist(delta)
	elif draft_bonus_override >= 0.0:
		is_drafting = draft_bonus_override > 0.005
		speed = ride_model.step_speed(speed, effort, delta, is_drafting, draft_bonus_override)
	else:
		is_drafting = _check_drafting()
		speed = ride_model.step_speed(speed, effort, delta, is_drafting)
	# Brake smoothly for a closed gate: never faster than what can stop in time.
	var remaining := distance_limit - distance
	if remaining < 60.0:
		speed = minf(speed, sqrt(2.0 * 3.0 * maxf(remaining, 0.0)))
	distance = minf(distance + speed * delta, distance_limit)


## Slipstream behind another rider, or behind anything in the
## "draft_target" group (Endless Survival companions on the front).
func _check_drafting() -> bool:
	for other in get_parent().get_children():
		if other == self or not other is CyclistController:
			continue
		var gap: float = (other as CyclistController).distance - distance
		if gap > 1.5 and gap < draft_range_m:
			drafting_behind = (other as CyclistController).player_name
			return true
	for target in get_tree().get_nodes_in_group("draft_target"):
		var gap: float = float(target.get("distance")) - distance
		if gap > 1.5 and gap < draft_range_m:
			drafting_behind = String(target.get("companion_name"))
			return true
	drafting_behind = ""
	return false


## What the draft assist does at a given level, effort ratio (your effort /
## the effort the wheel needs) and gap.
static func draft_assist_action(level: int, effort_ratio: float, gap: float) -> AssistAction:
	if level <= 0 or gap < ASSIST_RANGE.x or gap > ASSIST_RANGE.y:
		return AssistAction.NONE
	var band := ASSIST_BAND[level]
	if effort_ratio >= band.x and effort_ratio <= band.y:
		return AssistAction.HOLD
	if effort_ratio > band.y and effort_ratio <= ASSIST_BRAKE_UP_TO[level] and gap < 1.5:
		return AssistAction.BRAKE
	return AssistAction.NONE


func _apply_draft_assist(delta: float) -> void:
	wheel_locked = false
	if draft_assist <= 0 or wheel == null or wheel.speed < 2.0:
		return
	var need := physics.effort_for_speed(wheel.speed, maxf(draft_bonus_override, 0.0))
	match draft_assist_action(draft_assist, effort / maxf(need, 0.05), wheel_gap):
		AssistAction.HOLD:
			var target := wheel.speed + clampf((wheel_gap - ASSIST_HOLD_GAP) * 0.5, -1.0, 1.0)
			speed = move_toward(speed, target, ASSIST_PULL[draft_assist] * delta)
			wheel_locked = true
		AssistAction.BRAKE:
			if speed > wheel.speed:
				speed = move_toward(speed, wheel.speed, ASSIST_BRAKE * delta)


## The effort that holds `speed` with this much slipstream.
func effort_for_speed(target_speed: float, slipstream: float = 0.0) -> float:
	if physics:
		return physics.effort_for_speed(target_speed, slipstream)
	return ride_model.effort_for_speed(target_speed, slipstream)


## Extra effort needed to accelerate at `accel` (m/s^2) at the current speed
## (0 for the arcade model, where speed follows effort directly).
func effort_to_accelerate(accel: float) -> float:
	if physics == null:
		return 0.0
	return physics.mass_kg * accel * maxf(speed, physics.min_drive_speed) / (1.6 * physics.reference_ftp)


## The steady speed an effort gives, riding alone.
func speed_for_effort(e: float) -> float:
	return physics.speed_for_effort(e) if physics else ride_model.target_speed(e)


## Owner only: knocked off your rhythm (a runner clawed at you).
func stagger(speed_factor: float) -> void:
	speed *= speed_factor


## Remote riders: extrapolate from the last packet and ease towards it.
func _follow_network(delta: float) -> void:
	_net_age += delta
	var predicted := _net_distance + _net_speed * minf(_net_age, 0.25)
	distance = lerpf(distance, predicted, clampf(delta * 10.0, 0.0, 1.0))
	speed = lerpf(speed, _net_speed, clampf(delta * 10.0, 0.0, 1.0))


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_state(p_distance: float, p_speed: float, p_power: float, p_effort: float, p_cadence: float) -> void:
	_net_distance = p_distance
	_net_speed = p_speed
	_net_age = 0.0
	power_watts = p_power
	effort = p_effort
	cadence = p_cadence


func _apply_transform(delta: float) -> void:
	if route == null:
		return
	var frame := route.get_frame(distance)
	global_transform = Transform3D(frame.basis, frame.origin + frame.basis.x * lane_offset)
	# Lean into bends like a real bike (exaggerated x3 so it reads on screen).
	var lean := clampf(atan(speed * speed * route.get_curvature(distance) / 9.81) * 3.0, -0.35, 0.35)
	model.animate(delta, speed, cadence, lean)
