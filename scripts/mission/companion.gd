class_name Companion
extends Node3D
## A rescued survivor riding with the group (Endless Survival).
##
## Companions ride at the back. If the horde grabs the group, the last
## companion drops back into it - sprint free and they catch up again, or
## they're taken instead of a player. Pure presentation: every machine
## positions companions from the riders' positions, so nothing needs syncing
## except "picked up" and "taken" events (see EndlessMission).

## Lanes for up to 3 companions.
const LANES: Array[float] = [0.0, -1.9, 1.9]

var companion_name: String = ""
var slot: int = 0
var distance: float = 0.0
var speed: float = 0.0
var route: Route
var _model: CyclistModel
var _fallen := false


func setup(p_name: String, p_route: Route, start_distance: float) -> void:
	companion_name = p_name
	route = p_route
	distance = start_distance
	_model = CyclistModel.new()
	_model.headlight_enabled = false
	add_child(_model)
	# A muted jersey colour derived from the name (same on every machine).
	_model.build(Color.from_hsv(float(absi(p_name.hash()) % 360) / 360.0, 0.3, 0.5))
	var tag := Label3D.new()
	tag.text = p_name
	tag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	tag.fixed_size = true
	tag.pixel_size = 0.0011
	tag.font_size = 26
	tag.outline_size = 8
	tag.no_depth_test = true
	tag.modulate = Color(0.75, 0.85, 0.75)
	tag.position = Vector3(0, 2.1, 0)
	add_child(tag)


## Moves towards the target distance (behind the riders, or into the horde).
func ride(delta: float, target_distance: float) -> void:
	if _fallen or route == null:
		return
	var before := distance
	# Ease towards the target, but never faster than a strong sprint.
	var step := clampf((target_distance - distance) * 2.5, -8.0, 18.0) * delta
	distance += step
	speed = lerpf(speed, maxf((distance - before) / maxf(delta, 0.0001), 0.0), 0.2)
	var f := route.get_frame(distance)
	global_transform = Transform3D(f.basis, f.origin + f.basis.x * LANES[slot % LANES.size()])
	_model.animate(delta, speed, 80.0 if speed > 1.0 else 0.0, 0.0)


## Taken by the horde: topples over (and is removed after a moment).
func fall() -> void:
	_fallen = true
	var tween := create_tween()
	tween.tween_property(_model, "rotation:z", deg_to_rad(80.0), 0.6)
	tween.tween_interval(4.0)
	tween.tween_callback(queue_free)
