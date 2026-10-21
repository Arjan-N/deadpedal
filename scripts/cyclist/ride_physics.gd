class_name RidePhysics
extends Resource
## Real-world cycling physics, used by the criterium (the zombie modes use the
## simpler, snappier RideModel).
##
## Your pedalling power pushes against rolling resistance and air drag, and
## speed changes according to your mass - so speed builds up gradually and
## you coast when you stop pedalling. Riding in someone's slipstream reduces
## your air drag. On the flat with the defaults: 100 W ~ 26 km/h,
## 200 W ~ 33 km/h, 300 W ~ 38 km/h (riding alone).
##
## Power comes from effort (power / (FTP * 1.6)) times `reference_ftp`, which
## the race sets to your FTP - so you ride at your real watts, and computer
## riders of "equal" strength ride at the same percentages of your FTP.

## Rider + bike (kg).
@export var mass_kg: float = 84.0
## Drag area (m^2): 0.32 = riding on the hoods.
@export var cda: float = 0.32
## Rolling resistance coefficient (road tyres on good asphalt).
@export var crr: float = 0.004
@export var air_density: float = 1.2
## Below this speed (m/s) the pedalling force is capped, as if at this
## speed - stops the force becoming infinite when standing still.
@export var min_drive_speed: float = 2.0
## Watts per unit of effort / 1.6 (set to the player's FTP by the race).
@export var reference_ftp: float = 200.0

const GRAVITY := 9.81


func power_for_effort(effort: float) -> float:
	return maxf(effort, 0.0) * 1.6 * reference_ftp


## Resistance (N) at a speed. `drag_reduction` 0..1 = slipstream shelter.
func resistance(speed: float, drag_reduction: float = 0.0) -> float:
	return 0.5 * air_density * cda * (1.0 - drag_reduction) * speed * speed + crr * mass_kg * GRAVITY


## New speed after `delta` seconds. `brake` = extra deceleration (m/s^2).
func step_speed(speed: float, effort: float, delta: float, drag_reduction: float = 0.0, brake: float = 0.0) -> float:
	var drive := power_for_effort(effort) / maxf(speed, min_drive_speed)
	var accel := (drive - resistance(speed, drag_reduction)) / mass_kg - brake
	return maxf(speed + accel * delta, 0.0)


## The effort needed to hold `speed` (computer riders use this).
func effort_for_speed(speed: float, drag_reduction: float = 0.0) -> float:
	return resistance(speed, drag_reduction) * speed / (1.6 * reference_ftp)


## The steady speed a given effort gives.
func speed_for_effort(effort: float, drag_reduction: float = 0.0) -> float:
	var power := power_for_effort(effort)
	var lo := 0.0
	var hi := 30.0
	for i in 30:  # bisection: resistance * speed only goes up with speed
		var mid := (lo + hi) * 0.5
		if resistance(mid, drag_reduction) * mid > power:
			hi = mid
		else:
			lo = mid
	return lo
