class_name PointsRace
extends RefCounted
## The scoring rules of the criterium, kept separate so they can be tested:
## the first rider across the line on each lap scores; every bell lap scores
## double; the first rider to reach the target wins.

var points_to_win: int = 10
## Every Nth lap is a bell lap (0 = none)...
var bell_every: int = 5
## ...worth this many points.
var bell_points: int = 2

## rider id -> points
var points: Dictionary = {}
## rider id -> laps won
var laps_won: Dictionary = {}
## Highest lap that has been won so far.
var last_scored_lap: int = 0
## Rider id of the winner, or -1 while racing.
var winner: int = -1


func setup(rider_ids: Array) -> void:
	for id: int in rider_ids:
		points[id] = 0
		laps_won[id] = 0
	last_scored_lap = 0
	winner = -1


func is_bell_lap(lap: int) -> bool:
	return bell_every > 0 and lap > 0 and lap % bell_every == 0


func points_for_lap(lap: int) -> int:
	return bell_points if is_bell_lap(lap) else 1


## A rider just completed `lap`. Returns the points they scored (0 if someone
## else already took that lap, or the race is over).
func lap_completed(rider_id: int, lap: int) -> int:
	if winner != -1 or lap <= last_scored_lap:
		return 0
	last_scored_lap = lap
	var p := points_for_lap(lap)
	points[rider_id] = int(points.get(rider_id, 0)) + p
	laps_won[rider_id] = int(laps_won.get(rider_id, 0)) + 1
	if points[rider_id] >= points_to_win:
		winner = rider_id
	return p


## Rider ids, most points first (ties: `tiebreak` value, higher first).
func standings(tiebreak: Dictionary = {}) -> Array:
	var ids := points.keys()
	ids.sort_custom(func(a: int, b: int) -> bool:
		if points[a] != points[b]:
			return points[a] > points[b]
		return float(tiebreak.get(a, 0.0)) > float(tiebreak.get(b, 0.0)))
	return ids
