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

var _send_timer: float = 0.0
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
	name_tag.visible = not is_local()
	_net_distance = distance
	_apply_transform(0.0)


func is_local() -> bool:
	return is_multiplayer_authority()


func _process(delta: float) -> void:
	if is_local():
		_simulate(delta)
		_send_timer -= delta
		if _send_timer <= 0.0 and multiplayer.has_multiplayer_peer() and can_ride:
			_send_timer = 1.0 / network_send_rate
			_net_state.rpc(distance, speed, power_watts, effort, cadence)
	else:
		_follow_network(delta)
	max_speed_reached = maxf(max_speed_reached, speed)
	_apply_transform(delta)


func _simulate(delta: float) -> void:
	power_watts = CyclingInputManager.get_power_watts()
	effort = CyclingInputManager.get_effort()
	cadence = CyclingInputManager.get_cadence_rpm()
	if not can_ride or is_caught:
		speed = move_toward(speed, 0.0, 6.0 * delta)
		return
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
