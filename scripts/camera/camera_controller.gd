class_name CameraController
extends Camera3D
## Third-person chase camera that follows a cyclist along the route.
##
## The camera is placed on the road *behind* the rider (using the route, not
## the rider's facing), so it never swings through buildings on bends.
## When danger rises it pulls back and up so the chasing horde comes into view.

@export var follow_distance: float = 5.2
@export var follow_height: float = 2.3
@export var look_ahead: float = 9.0
## Extra distance/height at maximum danger (reveals the horde behind).
@export var danger_pull_back: float = 7.0
@export var danger_raise: float = 2.2
@export var position_smoothing: float = 10.0
@export var base_fov: float = 68.0
## Extra field of view at top speed, for a subtle sense of speed.
@export var speed_fov_bonus: float = 8.0
## Small camera shake when zombies are very close. Disable if it bothers you.
@export var danger_shake_enabled: bool = true

var target: CyclistController
var danger: float = 0.0

var _time: float = 0.0
var _initialised := false
var _look_point: Vector3


func _process(delta: float) -> void:
	if target == null or target.route == null:
		return
	_time += delta
	var route := target.route
	var back := follow_distance + danger_pull_back * danger
	var height := follow_height + danger_raise * danger
	var desired := route.get_point(target.distance - back, target.lane_offset * 0.6) + Vector3.UP * height
	var look := route.get_point(target.distance + look_ahead, target.lane_offset * 0.3) + Vector3.UP * 0.8

	if not _initialised:
		global_position = desired
		_look_point = look
		_initialised = true
	var t := clampf(delta * position_smoothing, 0.0, 1.0)
	global_position = global_position.lerp(desired, t)
	_look_point = _look_point.lerp(look, t)

	var shake := Vector3.ZERO
	if danger_shake_enabled and danger > 0.9:
		var amount := (danger - 0.9) / 0.1 * 0.05
		shake = Vector3(sin(_time * 23.0), sin(_time * 31.0 + 1.3), 0.0) * amount
	look_at(_look_point + shake, Vector3.UP)

	var speed_factor := clampf(target.speed / 16.0, 0.0, 1.0)
	fov = lerpf(fov, base_fov + speed_fov_bonus * speed_factor, clampf(delta * 2.0, 0.0, 1.0))
