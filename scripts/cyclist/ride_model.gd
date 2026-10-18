class_name RideModel
extends Resource
## Maps normalised effort (0..1) to in-game speed. Deliberately simple and
## game-like - not a physiological or aerodynamic model. All values are
## editable in the Inspector on the Cyclist scene.

## Speed (m/s) when pedalling very lightly. 1 m/s = 3.6 km/h.
@export var min_speed_mps: float = 3.0
## Speed (m/s) at full effort.
@export var max_speed_mps: float = 16.0
## Shape of the effort curve. Below 1.0 gives low efforts relatively more
## speed, which keeps less fit riders competitive.
@export_range(0.3, 2.0, 0.05) var effort_curve: float = 0.8
## Effort below this counts as "not pedalling" (bike coasts to a stop).
@export var pedalling_threshold: float = 0.02
## How strongly speed chases the target speed (per second). Higher = snappier.
@export var response: float = 1.4
## Maximum acceleration (m/s^2) at low effort...
@export var acceleration_mps2: float = 2.0
## ...plus this much extra at full effort (sprints feel punchy).
@export var sprint_acceleration_bonus_mps2: float = 2.0
## Maximum deceleration (m/s^2) when easing off. Low = more momentum.
@export var deceleration_mps2: float = 1.3
## Speed bonus (fraction) when riding in another rider's slipstream.
@export var draft_bonus: float = 0.1


func target_speed(effort: float) -> float:
	if effort < pedalling_threshold:
		return 0.0
	var shaped := pow(clampf(effort, 0.0, 1.0), effort_curve)
	return lerpf(min_speed_mps, max_speed_mps, shaped)


## Returns the new speed after `delta` seconds.
func step_speed(current: float, effort: float, delta: float, drafting: bool = false) -> float:
	var target := target_speed(effort)
	if drafting:
		target *= 1.0 + draft_bonus
	# Chase the target smoothly, limited by acceleration / deceleration.
	var max_accel := acceleration_mps2 + sprint_acceleration_bonus_mps2 * effort
	var change := clampf((target - current) * response, -deceleration_mps2, max_accel)
	return maxf(0.0, current + change * delta)
