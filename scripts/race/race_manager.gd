class_name RaceManager
extends Node3D
## CRITERIUM - a points race on a short town circuit against computer riders.
##
## The first rider across the line on each lap scores a point; every bell lap
## (every 5th) scores two; first to the target wins. No zombies: the opponent
## is the wind. Riding close behind another rider shelters you (the closer,
## the more), and everyone has a sprint battery: effort above FTP drains it,
## easy riding refills it, and when it's empty you can't go above FTP.
##
## Solo only for now: the player plus computer riders (RaceBot), all simulated
## on this machine with exactly the same rules.

enum Stage { COUNTDOWN, RACING, FINISHED }

signal announced(title: String, subtitle: String, duration: float)
signal race_finished(results: Dictionary)

const CYCLIST_SCENE := preload("res://scenes/cyclist/cyclist.tscn")
const PLAYER_ID := 1
const BOT_NAMES := ["Dan", "Sofie", "Jens", "Lena", "Pim", "Greta", "Max", "Ilse", "Tom", "Mira", "Kees", "Noa", "Bas", "Eva"]
## The field always has a mix of personalities, in this order.
const FIELD := [RaceBot.Personality.SPRINTER, RaceBot.Personality.DIESEL, RaceBot.Personality.ATTACKER,
	RaceBot.Personality.WHEELSUCKER, RaceBot.Personality.OPPORTUNIST, RaceBot.Personality.DIESEL, RaceBot.Personality.SPRINTER]
const JERSEYS: Array[Color] = [Color(0.9, 0.35, 0.08), Color(0.1, 0.55, 0.9), Color(0.85, 0.75, 0.1),
	Color(0.7, 0.2, 0.75), Color(0.2, 0.75, 0.35), Color(0.92, 0.92, 0.92), Color(0.85, 0.15, 0.2), Color(0.1, 0.2, 0.35)]
## Sideways positions riders can take (m from the centre line).
const LANE_SLOTS: Array[float] = [0.0, -1.2, 1.2, -2.4, 2.4, -3.4, 3.4]

@export var countdown_seconds: float = 3.0
@export_group("Points")
@export var bell_every: int = 5
@export var bell_points: int = 2
@export_group("Slipstream")
## Biggest slipstream bonus (speed for the same effort), right on a wheel...
@export var max_draft_bonus: float = 0.2
## ...up to this gap (m)...
@export var full_draft_gap: float = 1.5
## ...fading to nothing at this gap.
@export var draft_range: float = 8.0
## Extra shelter when the rider ahead is sheltered too (deeper in the line).
@export var chain_bonus: float = 0.03
## More than this far behind the rider ahead = dropped (alone in the wind).
@export var dropped_gap: float = 15.0
@export_group("Battery")
## Battery size in effort-seconds above FTP (a full sprint uses ~0.375/s).
@export var battery_capacity: float = 10.0
## How fast riding below FTP refills it (fraction of the effort below FTP).
@export var battery_recharge: float = 0.5

var stage: Stage = Stage.COUNTDOWN
var elapsed: float = 0.0
var countdown_left: float = 0.0
var rules := PointsRace.new()
## rider id -> CyclistController
var riders: Dictionary = {}
var bots: Dictionary = {}  # rider id -> RaceBot
var local_cyclist: CyclistController
var lap_length: float = 1.0
var results: Dictionary = {}
## Riders ordered by distance raced, leader first (updated every frame).
var order: Array = []
## rider id -> [nearest rider ahead on the circuit (or null), gap in m]. On
## the circuit, not in the race: a lapped rider rides with the bunch.
var ahead_on_track: Dictionary = {}

var _laps_done: Dictionary = {}  # rider id -> completed laps
var _lane_target: Dictionary = {}  # rider id -> lane offset
var _last_beep: int = -1
var _results_timer: float = -1.0
var _bell_announced: int = 0
var _autopilot: RaceBot
# Player stats for the results.
var _time_in_wind: float = 0.0
var _time_racing: float = 0.0
var _max_power: float = 0.0
var _best_sprint: float = 0.0

@onready var route: LoopRoute = $Route
@onready var town: TownBuilder = $Town
@onready var riders_root: Node3D = $Riders
@onready var camera: CameraController = $Camera
@onready var hud: RaceHUD = $HUD
@onready var audio: MissionAudio = $Audio
@onready var lap_board: Label3D = $LapBoard


func _ready() -> void:
	add_to_group("race")
	RaceSettings.load_settings()
	_apply_dev_options()
	rules.points_to_win = RaceSettings.points_to_win
	rules.bell_every = bell_every
	rules.bell_points = bell_points
	lap_length = route.get_length()
	town.build_circuit(route)
	_spawn_riders()
	rules.setup(riders.keys())
	camera.target = local_cyclist
	CyclingInputManager.reset()
	audio.ambience_id = "crowd_loop"
	audio.setup(self)
	hud.setup(self)
	hud.replay_requested.connect(func() -> void: MultiplayerManager.start_solo(MultiplayerManager.MODE_RACE))
	hud.menu_requested.connect(func() -> void: MultiplayerManager.return_to_menu())
	var f := route.get_frame(2.0)
	lap_board.global_transform = Transform3D(f.basis, f.origin + f.basis.x * (route_half_width() + 2.5) + Vector3.UP * 3.0)
	countdown_left = countdown_seconds
	announced.emit("CRITERIUM", "First to %d points - every 5th lap is a bell lap worth %d" % [rules.points_to_win, bell_points], countdown_seconds + 1.0)
	print("[Race] %d riders, first to %d points, lap %.0f m" % [riders.size(), rules.points_to_win, lap_length])


func route_half_width() -> float:
	return town.road_width * 0.5


## Command-line overrides for automated tests (see DevTools).
func _apply_dev_options() -> void:
	var o := DevTools.options
	if o.has("race-points"):
		RaceSettings.points_to_win = int(o["race-points"])
	if o.has("race-opponents"):
		RaceSettings.opponents = int(o["race-opponents"])
	if o.has("race-difficulty"):
		RaceSettings.difficulty = clampi(int(o["race-difficulty"]), 0, 2) as RaceSettings.Difficulty


func _spawn_riders() -> void:
	var seed_value := MultiplayerManager.mission_seed
	var count := RaceSettings.opponents + 1
	# The player starts in the middle of the grid.
	var player_slot := count / 2
	var bot_index := 0
	for slot in count:
		var c: CyclistController = CYCLIST_SCENE.instantiate()
		var id := PLAYER_ID if slot == player_slot else 100 + bot_index
		c.name = "Rider%d" % id
		c.peer_id = id
		c.route = route
		c.distance = -2.0 - (slot / 2) * 2.6
		c.lane_offset = -1.2 if slot % 2 == 0 else 1.2
		c.battery_capacity = battery_capacity
		c.battery = battery_capacity
		c.battery_recharge = battery_recharge
		c.draft_bonus_override = 0.0
		if id == PLAYER_ID:
			c.player_name = CyclingInputManager.rider_name
			c.jersey_color = JERSEYS[0]
			local_cyclist = c
		else:
			var personality: RaceBot.Personality = FIELD[bot_index % FIELD.size()]
			c.is_bot = true
			c.player_name = BOT_NAMES[(seed_value + bot_index * 5) % BOT_NAMES.size()]
			c.jersey_color = JERSEYS[(bot_index + 1) % JERSEYS.size()]
			var bot := RaceBot.new()
			bot.setup(personality, c, seed_value * 31 + bot_index, RaceSettings.difficulty)
			bot.lap_length = lap_length
			match RaceSettings.difficulty:
				RaceSettings.Difficulty.EASIER:
					c.battery_capacity = battery_capacity * 0.75
					c.battery_threshold = RideModel.FTP_EFFORT * 0.95
				RaceSettings.Difficulty.HARDER:
					c.battery_capacity = battery_capacity * 1.25
					c.battery_threshold = RideModel.FTP_EFFORT * 1.04
			c.battery = c.battery_capacity
			bots[id] = bot
			bot_index += 1
		c.set_multiplayer_authority(1)
		riders_root.add_child(c)
		riders[id] = c
		_laps_done[id] = 0
		_lane_target[id] = c.lane_offset
	# Automated tests: --autopilot-race=<personality> races you like a computer
	# rider (through the scripted input, so the battery etc. apply as usual).
	if DevTools.options.has("autopilot-race") and CyclingInputManager.source is ScriptedCyclingInput:
		_autopilot = RaceBot.new()
		_autopilot.setup(RaceBot.PERSONALITY_NAMES.find(DevTools.options["autopilot-race"]) as RaceBot.Personality,
			local_cyclist, seed_value * 7, RaceSettings.Difficulty.EQUAL)
		_autopilot.lap_length = lap_length


# --- Queries (HUD, tests) -------------------------------------------------------

func get_riders() -> Array:
	return riders.values()


func is_racing() -> bool:
	return stage == Stage.RACING


## The lap being raced for (the next one to score).
func current_lap() -> int:
	return rules.last_scored_lap + 1


func metres_to_line(c: CyclistController) -> float:
	if c.distance < 0.0:
		return lap_length - c.distance  # on the grid: a full lap to go
	return lap_length - fposmod(c.distance, lap_length)


func personality_of(id: int) -> String:
	return RaceBot.PERSONALITY_NAMES[(bots[id] as RaceBot).personality] if bots.has(id) else "you"


## "IN THE WIND", "SHELTERED 18%" or "DROPPED" for a rider.
func shelter_state(c: CyclistController) -> String:
	if c.draft_bonus_override > 0.005:
		return "SHELTERED"
	var i := order.find(c)
	if i > 0 and float(ahead_on_track[c.peer_id][1]) > dropped_gap:
		return "DROPPED"
	return "IN THE WIND"


# --- Main loop ----------------------------------------------------------------

func _process(delta: float) -> void:
	match stage:
		Stage.COUNTDOWN:
			countdown_left = maxf(countdown_left - delta, 0.0)
			var beep := int(ceil(countdown_left))
			if beep != _last_beep and beep > 0:
				_last_beep = beep
				audio.play("countdown_beep", -4.0)
			if countdown_left <= 0.0:
				stage = Stage.RACING
				audio.play("go", -2.0)
				announced.emit("GO!", "Find a wheel - save your battery for the sprints", 2.0)
		Stage.RACING, Stage.FINISHED:
			elapsed += delta
	for c: CyclistController in riders.values():
		c.can_ride = stage != Stage.COUNTDOWN
	_update_order()
	_update_slipstream()
	_update_lanes(delta)
	_update_bots(delta)
	if stage == Stage.RACING:
		_update_laps()
		_update_stats(delta)
	_update_lap_board()
	_update_name_tags()
	# The crowd is loudest along the finish straight.
	var from_line := _track_distance_to_line(local_cyclist)
	audio.ambience_volume_db = lerpf(-8.0, -26.0, clampf(from_line / 160.0, 0.0, 1.0))
	audio.update(delta, 0.0, 0.0)
	if _results_timer > 0.0:
		_results_timer -= delta
		if _results_timer <= 0.0:
			hud.show_results(results)
			race_finished.emit(results)


func _update_order() -> void:
	order = riders.values()
	order.sort_custom(func(a: CyclistController, b: CyclistController) -> bool: return a.distance > b.distance)
	for c: CyclistController in order:
		var best: CyclistController = null
		var best_gap := INF
		for a: CyclistController in order:
			if a == c:
				continue
			var gap := track_gap(a, c)
			if gap > 0.0 and gap < best_gap:
				best_gap = gap
				best = a
		ahead_on_track[c.peer_id] = [best, best_gap]


## How far `a` is ahead of `b` on the circuit (0..lap length).
func track_gap(a: CyclistController, b: CyclistController) -> float:
	var g := fposmod(a.distance - b.distance, lap_length)
	return g if g > 0.001 else lap_length


## Gap-based slipstream: full right on a wheel, fading out by draft_range.
static func draft_bonus_for_gap(gap: float, max_bonus: float, full_gap: float, range_m: float) -> float:
	if gap < 0.4 or gap > range_m:
		return 0.0  # side by side, or too far back
	return max_bonus * clampf(1.0 - (gap - full_gap) / (range_m - full_gap), 0.0, 1.0)


func _update_slipstream() -> void:
	for c: CyclistController in order:
		var bonus := 0.0
		var behind_name := ""
		# The nearest rider far enough ahead to shelter behind (someone right
		# beside you doesn't count).
		var best_gap := INF
		for a: CyclistController in order:
			var gap := track_gap(a, c)
			if gap >= 0.4 and gap < best_gap and gap <= draft_range:
				best_gap = gap
				bonus = draft_bonus_for_gap(gap, max_draft_bonus, full_draft_gap, draft_range) \
					+ (chain_bonus if a.draft_bonus_override > 0.005 else 0.0)
				behind_name = a.player_name
		c.draft_bonus_override = bonus
		c.drafting_behind = behind_name


## Riders line up behind the wheel they follow and move out to pass.
func _update_lanes(delta: float) -> void:
	# Front to back on the circuit, so each rider sees the lanes the riders
	# just ahead have taken.
	var on_track := order.duplicate()
	on_track.sort_custom(func(a: CyclistController, b: CyclistController) -> bool:
		return fposmod(a.distance, lap_length) > fposmod(b.distance, lap_length))
	for c: CyclistController in on_track:
		var id := c.peer_id
		var occupied: Array[float] = []
		var follow_lane := NAN
		var nearest := INF
		for a: CyclistController in on_track:
			if a == c:
				continue
			var gap := track_gap(a, c)
			if gap <= 2.4:
				occupied.append(_lane_target[a.peer_id])
			elif gap < draft_range and gap < nearest:
				nearest = gap
				follow_lane = _lane_target[a.peer_id]
		var current: float = _lane_target[id]
		var wanted := follow_lane if not is_nan(follow_lane) else current
		_lane_target[id] = _free_lane(wanted, current, occupied)
		c.lane_offset = move_toward(c.lane_offset, _lane_target[id], 1.6 * delta)


func _free_lane(wanted: float, current: float, occupied: Array[float]) -> float:
	var candidates: Array[float] = [wanted, current]
	var slots := LANE_SLOTS.duplicate()
	slots.sort_custom(func(a: float, b: float) -> bool: return absf(a - current) < absf(b - current))
	candidates.append_array(slots)
	for lane in candidates:
		var free := true
		for o in occupied:
			if absf(o - lane) < 0.95:
				free = false
				break
		if free:
			return lane
	return current


func _update_bots(delta: float) -> void:
	if order.is_empty():
		return
	var leader: CyclistController = order[0]
	for c: CyclistController in order:
		var brain: RaceBot = bots.get(c.peer_id, _autopilot if c == local_cyclist else null)
		if brain == null:
			continue
		var near: Array = ahead_on_track[c.peer_id]
		# How far the front of the race is up the road from here, on the
		# circuit (a lapped rider back in the bunch is "with" the leaders).
		var lead_gap := fposmod(leader.distance - c.distance, lap_length) if c != leader else 0.0
		if lead_gap > lap_length - 30.0:
			lead_gap = 0.0  # just ahead of the leader on the road
		var e := brain.decide(delta, near[0], near[1], lead_gap, metres_to_line(c), stage == Stage.FINISHED)
		if c.is_bot:
			c.bot_effort = e
		else:
			(CyclingInputManager.source as ScriptedCyclingInput).constant_watts = e * CyclingInputManager.rider_ftp_watts * 1.6


func _update_laps() -> void:
	for id: int in riders:
		var c: CyclistController = riders[id]
		var lap := floori(c.distance / lap_length)
		if lap <= _laps_done[id]:
			continue
		_laps_done[id] = lap
		var scored := rules.lap_completed(id, lap)
		if scored > 0:
			_on_lap_won(c, lap, scored)
		var brain: RaceBot = bots.get(id, _autopilot if id == PLAYER_ID else null)
		if brain:
			var best := 0
			for p: int in rules.points.values():
				best = maxi(best, p)
			brain.new_lap(lap + 1, rules.is_bell_lap(lap + 1), rules.points[id], best, rules.points_to_win)
		if stage != Stage.RACING:
			return


func _on_lap_won(c: CyclistController, lap: int, scored: int) -> void:
	var you := c == local_cyclist
	print("[Race] Lap %d won by %s (+%d, %d points)" % [lap, c.player_name, scored, rules.points[c.peer_id]])
	audio.play("cheer", 0.0 if you else -6.0)
	if rules.winner != -1:
		_finish()
		return
	var title := "YOU TAKE LAP %d!" % lap if you else "%s TAKES LAP %d" % [c.player_name.to_upper(), lap]
	var sub := "+%d point%s  -  %d to win" % [scored, "s" if scored > 1 else "", rules.points_to_win - rules.points[c.peer_id]]
	announced.emit(title, sub, 2.5)
	if rules.is_bell_lap(lap + 1) and _bell_announced < lap + 1:
		_bell_announced = lap + 1
		await get_tree().create_timer(2.6 * Engine.time_scale).timeout
		if stage == Stage.RACING:
			audio.play("bell", 0.0)
			announced.emit("BELL LAP!", "This lap is worth %d points" % rules.points_for_lap(lap + 1), 3.0)


func _finish() -> void:
	stage = Stage.FINISHED
	var winner: CyclistController = riders[rules.winner]
	var you := winner == local_cyclist
	print("[Race] WINNER %s with %d points after %d laps (%.1fs)" % [winner.player_name, rules.points[rules.winner], rules.last_scored_lap, elapsed])
	audio.play("success" if you else "failure")
	announced.emit("YOU WIN!" if you else "%s WINS" % winner.player_name.to_upper(),
		"%d points in %d laps" % [rules.points[rules.winner], rules.last_scored_lap], 4.0)
	var distances := {}
	for id: int in riders:
		distances[id] = (riders[id] as CyclistController).distance
	var standings := []
	for id: int in rules.standings(distances):
		var c: CyclistController = riders[id]
		standings.append({
			"name": c.player_name,
			"points": rules.points[id],
			"laps_won": rules.laps_won[id],
			"color": c.jersey_color,
			"is_player": c == local_cyclist,
			"personality": personality_of(id),
		})
	results = {
		"mode": MultiplayerManager.MODE_RACE,
		"success": you,
		"winner": winner.player_name,
		"standings": standings,
		"laps": rules.last_scored_lap,
		"time": elapsed,
		"my_points": rules.points[PLAYER_ID],
		"my_laps_won": rules.laps_won[PLAYER_ID],
		"my_max_speed": local_cyclist.max_speed_reached,
		"my_max_power": _max_power,
		"my_best_sprint": _best_sprint,
		"time_in_wind": _time_in_wind / maxf(_time_racing, 0.001),
	}
	_results_timer = 4.0


func _update_stats(delta: float) -> void:
	var me := local_cyclist
	_time_racing += delta
	if me.draft_bonus_override <= 0.005:
		_time_in_wind += delta
	_max_power = maxf(_max_power, me.power_watts)
	if metres_to_line(me) < 200.0:
		_best_sprint = maxf(_best_sprint, me.speed)


## Only the riders nearest to you show their names (a whole bunch of name
## tags would just overlap).
func _update_name_tags() -> void:
	var others := order.filter(func(c: CyclistController) -> bool: return c != local_cyclist)
	others.sort_custom(func(a: CyclistController, b: CyclistController) -> bool:
		return _track_distance(a, local_cyclist) < _track_distance(b, local_cyclist))
	for i in others.size():
		var c: CyclistController = others[i]
		c.name_tag.visible = i < 3 and _track_distance(c, local_cyclist) < 30.0


func _track_distance_to_line(c: CyclistController) -> float:
	var d := fposmod(c.distance, lap_length)
	return minf(d, lap_length - d)


func _track_distance(a: CyclistController, b: CyclistController) -> float:
	var g := fposmod(a.distance - b.distance, lap_length)
	return minf(g, lap_length - g)


func _update_lap_board() -> void:
	if stage == Stage.FINISHED:
		lap_board.text = "FINISHED"
	elif rules.is_bell_lap(current_lap()):
		lap_board.text = "LAP %d\nBELL - %d PTS" % [current_lap(), rules.points_for_lap(current_lap())]
	else:
		lap_board.text = "LAP %d" % current_lap()
