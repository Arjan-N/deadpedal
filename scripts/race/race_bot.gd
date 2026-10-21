class_name RaceBot
extends RefCounted
## The brain of a computer rider in the criterium. Each frame it picks an
## effort (0..1) for its CyclistController, which then obeys exactly the same
## rules as you: the ride model, the slipstream and the battery.
##
## Personalities differ in when they go for a lap, how hard they ride on the
## front and whether they chase or attack.

enum Personality { DIESEL, SPRINTER, ATTACKER, WHEELSUCKER, OPPORTUNIST }
const PERSONALITY_NAMES := ["diesel", "sprinter", "attacker", "wheelsucker", "opportunist"]

## Per personality: [sprint distance (m), effort on the front, chance to go
## for a normal lap, chance to go for a bell lap, chance to attack in a lap,
## effort they'll chase at].
const PROFILES := {
	Personality.DIESEL: [150.0, 0.6, 0.15, 0.35, 0.1, 0.8],
	Personality.SPRINTER: [230.0, 0.45, 0.55, 0.8, 0.0, 0.7],
	Personality.ATTACKER: [180.0, 0.52, 0.3, 0.5, 0.45, 0.8],
	Personality.WHEELSUCKER: [180.0, 0.38, 0.45, 0.6, 0.0, 0.66],
	Personality.OPPORTUNIST: [200.0, 0.5, 0.2, 0.9, 0.15, 0.78],
}

var personality: Personality = Personality.DIESEL
var rider: CyclistController
var sprint_distance: float = 200.0
var front_effort: float = 0.5
var contest_chance: float = 0.3
var bell_chance: float = 0.6
var attack_chance: float = 0.0
var chase_effort: float = 0.75
## How close they like to sit on a wheel (m).
var wheel_gap: float = 1.0
## How long they take to respond when the wheel ahead speeds up (s). A quick
## attack can open a gap on a slow reactor.
var reaction_time: float = 0.8
## Effort in the sprint for the line (1 = 160% FTP).
var sprint_effort: float = 1.6
## Length of a lap (set by the race).
var lap_length: float = 560.0

## Going for the current lap.
var contesting := false
## Metres before the line where they'll attack this lap (-1 = not attacking).
var attack_at: float = -1.0
var attacking := false

var _rng := RandomNumberGenerator.new()
var _noise: float = 0.0
var _noise_target: float = 0.0
var _noise_timer: float = 0.0
var _seen_speed: float = 0.0  # the speed of the wheel ahead, as they perceive it


func setup(p_personality: Personality, p_rider: CyclistController, seed_value: int, difficulty: RaceSettings.Difficulty) -> void:
	personality = p_personality
	rider = p_rider
	_rng.seed = seed_value
	var p: Array = PROFILES[personality]
	sprint_distance = p[0] * _rng.randf_range(0.85, 1.15)
	front_effort = p[1] * _rng.randf_range(0.95, 1.05)
	contest_chance = p[2]
	bell_chance = p[3]
	attack_chance = p[4]
	chase_effort = p[5]
	wheel_gap = _rng.randf_range(0.8, 1.6)
	reaction_time = _rng.randf_range(0.6, 1.2)
	sprint_effort = (1.75 if personality == Personality.SPRINTER else 1.5) * _rng.randf_range(0.95, 1.05)
	if personality == Personality.DIESEL:
		reaction_time *= 1.4  # slow to respond, but relentless once going
	match difficulty:
		RaceSettings.Difficulty.EASIER:
			# Mistimed sprints, slower reactions and less in the tank.
			sprint_distance *= _rng.randf_range(0.7, 1.5)
			chase_effort -= 0.06
			sprint_effort -= 0.15
			reaction_time *= 1.6
		RaceSettings.Difficulty.HARDER:
			chase_effort += 0.05
			reaction_time *= 0.6
			sprint_effort += 0.1


## Called as this rider starts a new lap.
## standings: [my points, best points, points to win].
func new_lap(lap: int, bell: bool, my_points: int, best_points: int, points_to_win: int) -> void:
	var chance := bell_chance if bell else contest_chance
	# Late in the race everyone with a chance fights for every lap.
	if best_points >= points_to_win - 2:
		chance += 0.3
	if my_points >= points_to_win - 2:
		chance += 0.3
	var battery := battery_fraction()
	if battery < 0.4:
		chance *= battery / 0.4
	contesting = _rng.randf() < chance
	attacking = false
	attack_at = -1.0
	if battery > 0.6 and _rng.randf() < attack_chance * (1.5 if bell else 1.0):
		attack_at = _rng.randf_range(160.0, 380.0)
	if lap <= 1:
		attack_at = -1.0  # nobody attacks off the start


func battery_fraction() -> float:
	return rider.battery / rider.battery_capacity if rider.battery_capacity > 0.0 else 1.0


## The effort for this frame. `ahead` = nearest rider ahead (or null) and
## `gap` the distance to them; `lead_gap` = distance to the race leader;
## `to_line` = metres to the finish line.
func decide(delta: float, ahead: CyclistController, gap: float, lead_gap: float, to_line: float, finished: bool) -> float:
	_update_noise(delta)
	if finished:
		return 0.3  # roll around after the race
	var battery := battery_fraction()
	var effort: float
	# The sprint for the line.
	if contesting and to_line < sprint_distance and lead_gap < 30.0 and battery > 0.02:
		return sprint_effort
	# A long-range attack.
	if attack_at > 0.0 and to_line < attack_at and not attacking:
		attacking = true
	if attacking:
		if battery < 0.2:
			attacking = false
			attack_at = -1.0
		else:
			return 0.84 + _noise
	var my_pace := rider.speed_for_effort(front_effort)
	rider.bot_brake = 0.0
	# Well below their pace (the start, after braking): get up to speed.
	var boost := 0.9 if rider.speed < my_pace - 3.0 else 0.0
	if ahead != null and gap < 30.0:
		_seen_speed = lerpf(_seen_speed, ahead.speed, clampf(delta / reaction_time, 0.0, 1.0))
		# Come through and set the pace when the wheel in front dawdles (or
		# fades in a chase) - unless saving everything for the sprint. When the
		# front of the race is far up the road, everyone takes a turn.
		var saving := personality == Personality.WHEELSUCKER or (contesting and personality == Personality.SPRINTER)
		var chasing := lead_gap > gap + 25.0
		var after_line := to_line > lap_length - 200.0
		var pace := my_pace if not chasing else rider.speed_for_effort(chase_effort)
		if gap < 5.0 and _seen_speed < pace - 1.0 and battery > 0.3 and (not saving or chasing) and (chasing or not after_line):
			return clampf((chase_effort if chasing else front_effort) + _noise, 0.03, 1.0)
		# Sit on the wheel ahead: match their speed, closing any gap.
		var desired := _seen_speed + clampf((gap - wheel_gap) * 0.6, -2.5, 3.0)
		effort = rider.effort_for_speed(desired, rider.draft_bonus_override) + 0.15 * (desired - rider.speed)
		# Touch the brakes rather than ride into the wheel ahead.
		if gap < wheel_gap * 0.6 and rider.speed > _seen_speed:
			rider.bot_brake = 1.5
		# How hard they'll chase a gap.
		var cap := chase_effort + (0.1 if contesting else 0.0)
		if gap < 4.0:
			cap = 1.0  # just following
		effort = minf(effort, cap)
		# A wheelsucker never wants to be the one closing a gap.
		if personality == Personality.WHEELSUCKER and gap > 8.0 and not contesting:
			effort = minf(effort, RideModel.FTP_EFFORT)
	elif lead_gap > 30.0:
		# Alone, or leading a group chasing the front of the race.
		effort = chase_effort if battery > 0.25 else front_effort
	else:
		# On the front, setting the pace. Just after the line the front sits
		# up for a moment, so the bunch can regroup after the sprint.
		effort = front_effort
		if to_line > lap_length - 200.0 and not attacking:
			effort -= 0.12
		if contesting and to_line < 450.0:
			effort += 0.06  # winding it up before the sprint
		if personality == Personality.WHEELSUCKER and not contesting:
			effort = 0.33  # sits up and lets someone else lead
	return clampf(maxf(effort, boost) + _noise, 0.03, 1.0)


## A slowly wandering effort offset, so riders don't move in lockstep.
func _update_noise(delta: float) -> void:
	_noise_timer -= delta
	if _noise_timer <= 0.0:
		_noise_timer = _rng.randf_range(2.0, 6.0)
		_noise_target = _rng.randf_range(-0.03, 0.03)
	_noise = move_toward(_noise, _noise_target, 0.02 * delta)
