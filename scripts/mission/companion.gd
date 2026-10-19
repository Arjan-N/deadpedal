class_name Companion
extends Node3D
## A rescued survivor riding with the group (Endless Survival).
##
## Companions take turns riding on the FRONT, where riders can sit in their
## slipstream. Pulling costs energy; resting in the GROUP gets it back. A
## companion who runs out of energy is TIRED: they fade back towards the horde
## until a rider drops back and gives them a wheel to follow (riding just in
## front of them), which lets them recover. If the horde reaches a tired
## companion, they're taken.
##
## The host simulates companions (EndlessMission) and sends their state in
## its snapshot; other machines ease towards it, like the horde.

enum State { GROUP, FRONT, TIRED }
const STATE_NAMES := ["resting", "pulling", "EXHAUSTED"]

## Lanes for up to 3 companions.
const LANES: Array[float] = [0.0, -1.9, 1.9]

var id: int = 0
var companion_name: String = ""
var slot: int = 0
var distance: float = 0.0
var speed: float = 0.0
## 0..1 - pulling on the front uses it up.
var energy: float = 1.0
## How long they last on the front (1 = average). Host only.
var stamina: float = 1.0
## Seconds before they'll take another turn on the front. Host only.
var rest_time: float = 0.0
## They were passed in the middle of a turn on the front. Host only.
var mid_turn: bool = false
## Has made it past the riders on this turn at the front. Host only.
var at_front: bool = false
var state: State = State.GROUP
## A rider is riding just in front of this (tired) companion.
var on_wheel: bool = false
var route: Route
var _model: CyclistModel
var _tag: Label3D
var _fallen := false
var _net_distance: float = 0.0
var _net_age: float = 0.0


func setup(p_id: int, p_name: String, p_route: Route, start_distance: float) -> void:
	id = p_id
	companion_name = p_name
	route = p_route
	distance = start_distance
	_net_distance = start_distance
	add_to_group("draft_target")
	_model = CyclistModel.new()
	_model.headlight_enabled = false
	add_child(_model)
	# A muted jersey colour derived from the name (same on every machine).
	_model.build(Color.from_hsv(float(absi(p_name.hash()) % 360) / 360.0, 0.3, 0.5))
	_tag = Label3D.new()
	_tag.text = p_name
	_tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_tag.fixed_size = true
	_tag.pixel_size = 0.0011
	_tag.font_size = 26
	_tag.outline_size = 8
	_tag.no_depth_test = true
	_tag.position = Vector3(0, 2.1, 0)
	add_child(_tag)


func is_fallen() -> bool:
	return _fallen


## Host: rides towards `target_distance`, matching `ref_speed` (the speed of
## the rider they're positioning against), never faster than `max_speed`.
func ride_towards(delta: float, target_distance: float, ref_speed: float, max_speed: float) -> void:
	var desired := clampf(ref_speed + (target_distance - distance) * 1.5, 0.0, max_speed)
	speed = move_toward(speed, desired, 4.0 * delta)
	distance += speed * delta


## Host: rides at a speed chosen by the mission (tired companions).
func ride_at(delta: float, target_speed: float, accel: float) -> void:
	speed = move_toward(speed, target_speed, accel * delta)
	distance += speed * delta


## Other machines: the host's latest state for this companion.
func apply_net_state(p_distance: float, p_speed: float, p_energy: float, p_state: int, p_on_wheel: bool) -> void:
	_net_distance = p_distance
	_net_age = 0.0
	speed = p_speed
	energy = p_energy
	state = p_state as State
	on_wheel = p_on_wheel


## Other machines: extrapolate from the last snapshot and ease towards it.
func follow_network(delta: float) -> void:
	_net_age += delta
	var predicted := _net_distance + speed * minf(_net_age, 0.3)
	if absf(predicted - distance) > 20.0:
		distance = predicted
	else:
		distance = lerpf(distance, predicted, clampf(delta * 8.0, 0.0, 1.0))


## Every machine: places the model and updates its look.
func update_visuals(delta: float) -> void:
	if _fallen or route == null:
		return
	var f := route.get_frame(distance)
	var lane := LANES[0] if state == State.FRONT else LANES[slot % LANES.size()]
	global_transform = Transform3D(f.basis, f.origin + f.basis.x * lane)
	var tired := state == State.TIRED
	var cadence := 0.0
	if speed > 1.0:
		cadence = 55.0 if tired else 85.0
	_model.animate(delta, speed, cadence, 0.0)
	if tired:
		_tag.text = "%s - EXHAUSTED" % companion_name
		_tag.modulate = Color(1.0, 0.35, 0.25)
	else:
		_tag.text = companion_name
		_tag.modulate = Color(0.75, 0.85, 0.75).lerp(Color(1.0, 0.75, 0.3), clampf((0.4 - energy) / 0.3, 0.0, 1.0))


## Taken by the horde: topples over (and is removed after a moment).
func fall() -> void:
	_fallen = true
	remove_from_group("draft_target")
	var tween := create_tween()
	tween.tween_property(_model, "rotation:z", deg_to_rad(80.0), 0.6)
	tween.tween_interval(4.0)
	tween.tween_callback(queue_free)
