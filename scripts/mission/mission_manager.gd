class_name MissionManager
extends Node3D
## Mission "ESCAPE THE TOWN" - runs the stages, spawns riders, connects the
## systems together and keeps every player's mission state identical.
##
## Authority: the host (multiplayer.is_server(), which is also true in solo
## play) decides every stage change, simulates the horde and the gate, and
## declares success/failure. It sends a small snapshot ~15 times a second and
## reliable messages for important events. Clients only simulate their own
## cyclist and display what the host tells them.

enum Stage { WAITING, COUNTDOWN, DEPARTURE, PURSUIT, GATE, FINAL_ESCAPE, SUCCESS, FAILED }

signal stage_changed(stage: Stage)
signal announced(title: String, subtitle: String, duration: float)
signal mission_finished(results: Dictionary)

const CYCLIST_SCENE := preload("res://scenes/cyclist/cyclist.tscn")
## Lane offsets (m) for up to 6 riders, side by side.
const LANES: Array[float] = [-1.0, 1.0, -2.4, 2.4, -3.5, 3.5]
const RIDER_COLORS: Array[Color] = [
	Color(0.9, 0.35, 0.08), Color(0.1, 0.55, 0.9), Color(0.85, 0.75, 0.1),
	Color(0.7, 0.2, 0.75), Color(0.2, 0.75, 0.35), Color(0.9, 0.9, 0.9),
]
const STAGE_NAMES := ["WAITING", "COUNTDOWN", "DEPARTURE", "PURSUIT", "GATE", "FINAL_ESCAPE", "SUCCESS", "FAILED"]

@export var mission_title: String = "ESCAPE THE TOWN"
@export var countdown_seconds: float = 3.0
@export_group("Stages")
## The horde appears after this many seconds...
@export var pursuit_start_time: float = 14.0
## ...or once the lead rider has ridden this far, whichever comes first.
@export var pursuit_start_distance: float = 150.0
## Where the locked gate stands (m along the route).
@export var gate_distance: float = 1100.0
## The gate stage begins when the lead rider is this close to the gate.
@export var gate_trigger_range: float = 70.0
## Where the extraction point is (m along the route).
@export var extraction_distance: float = 1900.0
## Seconds between the end of the mission and the results screen.
@export var results_delay: float = 2.5
@export_group("Network")
@export var snapshot_rate: float = 15.0
## If a client never reports ready, start anyway after this many seconds.
@export var ready_timeout: float = 15.0

var stage: Stage = Stage.WAITING
## Seconds since "GO".
var elapsed: float = 0.0
var countdown_left: float = 0.0
## peer_id -> CyclistController
var cyclists: Dictionary = {}
var local_cyclist: CyclistController
var results: Dictionary = {}

var _ready_peers: Dictionary = {}
var _wait_time: float = 0.0
var _snapshot_timer: float = 0.0
var _last_countdown_beep: int = -1
var _results_timer: float = -1.0

@onready var route: Route = $Route
@onready var town: TownBuilder = $Town
@onready var zombies: ZombieDirector = $Zombies
@onready var gate: GateObjective = $Gate
@onready var extraction: ExtractionZone = $Extraction
@onready var cyclists_root: Node3D = $Cyclists
@onready var camera: CameraController = $Camera
@onready var hud: HUDController = $HUD
@onready var audio: MissionAudio = $Audio


func _ready() -> void:
	add_to_group("mission")
	town.build(route, gate_distance, extraction_distance)
	gate.transform = route.get_frame(gate_distance)
	gate.distance_on_route = gate_distance
	extraction.transform = route.get_frame(extraction_distance)
	zombies.setup(route, 60.0, extraction_distance - 20.0)
	_spawn_cyclists()
	camera.target = local_cyclist
	CyclingInputManager.reset()
	hud.setup(self)
	hud.replay_requested.connect(_on_replay_requested)
	hud.menu_requested.connect(_on_menu_requested)
	MultiplayerManager.player_left.connect(_on_player_left)
	if is_host():
		zombies.surge_started.connect(_on_surge_started)
		_ready_peers[multiplayer.get_unique_id()] = true
	else:
		_net_client_ready.rpc_id(1)
	print("[Mission] Ready. Riders: %s, host: %s" % [cyclists.keys(), is_host()])


func is_host() -> bool:
	return multiplayer.is_server()


func _spawn_cyclists() -> void:
	var roster := MultiplayerManager.get_roster()
	if roster.is_empty():
		# Scene launched directly from the editor (F6): play solo.
		MultiplayerManager.players = {1: {"name": CyclingInputManager.rider_name}}
		roster = [1]
	for i in roster.size():
		var id: int = roster[i]
		_add_cyclist(id, i)
	local_cyclist = cyclists.get(multiplayer.get_unique_id())
	if local_cyclist == null:
		# Should not happen, but never leave the camera without a target.
		local_cyclist = cyclists.values()[0]


func _add_cyclist(id: int, index: int) -> void:
	var c: CyclistController = CYCLIST_SCENE.instantiate()
	c.name = str(id)  # same node name on every machine so RPCs find it
	c.peer_id = id
	c.player_name = MultiplayerManager.get_player_name(id)
	c.jersey_color = RIDER_COLORS[index % RIDER_COLORS.size()]
	c.lane_offset = LANES[index % LANES.size()]
	c.route = route
	c.distance = 4.0
	c.set_multiplayer_authority(id)
	cyclists_root.add_child(c)
	cyclists[id] = c


# --- Queries ------------------------------------------------------------------

func get_riders() -> Array:
	return cyclists.values()


func get_rearmost_distance() -> float:
	var d := INF
	for c: CyclistController in cyclists.values():
		d = minf(d, c.distance)
	return 0.0 if d == INF else d


func get_rearmost_speed() -> float:
	var d := INF
	var v := 0.0
	for c: CyclistController in cyclists.values():
		if c.distance < d:
			d = c.distance
			v = c.speed
	return v


func get_lead_distance() -> float:
	var d := 0.0
	for c: CyclistController in cyclists.values():
		d = maxf(d, c.distance)
	return d


func get_danger() -> float:
	return zombies.get_danger(get_rearmost_distance())


func get_horde_gap() -> float:
	return zombies.get_gap(get_rearmost_distance())


func is_riding_stage() -> bool:
	return stage in [Stage.DEPARTURE, Stage.PURSUIT, Stage.GATE, Stage.FINAL_ESCAPE]


## Name and distance of the next objective for the local rider.
func get_next_objective() -> Array:
	var d := local_cyclist.distance if local_cyclist else 0.0
	if not gate.is_open:
		return ["GATE", maxf(gate_distance - d, 0.0)]
	return ["EXTRACTION", maxf(extraction_distance - d, 0.0)]


func get_objective_text() -> String:
	match stage:
		Stage.WAITING:
			return "Waiting for all riders..."
		Stage.COUNTDOWN:
			return "Get ready to ride"
		Stage.DEPARTURE:
			return "Ride out of town. Stay together."
		Stage.PURSUIT:
			return "Outrun the horde! Reach the gate."
		Stage.GATE:
			return "PEDAL TOGETHER to open the gate!"
		Stage.FINAL_ESCAPE:
			return "Reach the extraction point!"
		Stage.SUCCESS:
			return "You escaped!"
		Stage.FAILED:
			return "The horde caught the group."
	return ""


# --- Main loop ----------------------------------------------------------------

func _process(delta: float) -> void:
	if is_host():
		_host_update(delta)
	else:
		if is_riding_stage():
			elapsed += delta
			zombies.extrapolate(delta)
	if stage == Stage.COUNTDOWN:
		countdown_left = maxf(countdown_left - delta, 0.0)
		var beep := int(ceil(countdown_left))
		if beep != _last_countdown_beep and beep > 0:
			_last_countdown_beep = beep
			audio.play("beep", -4.0)
	_update_local_limits()
	zombies.update_visuals(delta, get_riders())
	var danger := get_danger()
	camera.danger = lerpf(camera.danger, danger, clampf(delta * 2.0, 0.0, 1.0))
	audio.update(delta, danger, local_cyclist.speed if local_cyclist else 0.0,
		gate.team_effort_rate if stage == Stage.GATE else 0.0)
	if _results_timer > 0.0:
		_results_timer -= delta
		if _results_timer <= 0.0:
			hud.show_results(results)
			mission_finished.emit(results)


func _host_update(delta: float) -> void:
	var rear := get_rearmost_distance()
	var lead := get_lead_distance()
	match stage:
		Stage.WAITING:
			_wait_time += delta
			var all_ready := true
			for id in cyclists.keys():
				if not _ready_peers.has(id):
					all_ready = false
			if all_ready or _wait_time > ready_timeout:
				_net_set_stage.rpc(Stage.COUNTDOWN)
		Stage.COUNTDOWN:
			if countdown_left <= 0.0:
				_net_set_stage.rpc(Stage.DEPARTURE)
		Stage.DEPARTURE:
			if elapsed >= pursuit_start_time or lead >= pursuit_start_distance:
				zombies.set_phase(ZombieDirector.Phase.PURSUIT, rear)
				_net_set_stage.rpc(Stage.PURSUIT)
		Stage.PURSUIT:
			if lead >= gate_distance - gate_trigger_range:
				zombies.set_phase(ZombieDirector.Phase.GATE, rear, gate_distance - 3.5)
				_net_set_stage.rpc(Stage.GATE)
		Stage.GATE:
			var efforts := {}
			for id: int in cyclists:
				var c: CyclistController = cyclists[id]
				if c.distance >= gate_distance - gate.work_range:
					efforts[id] = c.effort
			gate.add_effort(efforts, delta, cyclists.size())
			if gate.progress >= 1.0:
				zombies.set_phase(ZombieDirector.Phase.FINAL_ESCAPE, rear)
				_net_set_stage.rpc(Stage.FINAL_ESCAPE)
		Stage.FINAL_ESCAPE:
			if rear >= extraction_distance:
				zombies.set_phase(ZombieDirector.Phase.STOPPED, rear)
				_finish(true)

	if is_riding_stage():
		elapsed += delta
		zombies.simulate(delta, rear, get_rearmost_speed())
		if zombies.is_catching():
			zombies.set_phase(ZombieDirector.Phase.OVERRUN, rear)
			_finish(false)
	elif stage == Stage.FAILED:
		zombies.simulate(delta, rear, 0.0)

	_snapshot_timer -= delta
	if _snapshot_timer <= 0.0 and stage != Stage.WAITING:
		_snapshot_timer = 1.0 / snapshot_rate
		_net_snapshot.rpc(elapsed, zombies.get_snapshot(), gate.progress, gate.team_effort_rate, gate.contributions)


## Each machine limits its own rider: the closed gate blocks the road.
func _update_local_limits() -> void:
	if local_cyclist == null:
		return
	local_cyclist.can_ride = stage in [Stage.DEPARTURE, Stage.PURSUIT, Stage.GATE, Stage.FINAL_ESCAPE, Stage.SUCCESS]
	local_cyclist.is_caught = stage == Stage.FAILED
	if gate.is_open:
		local_cyclist.distance_limit = minf(extraction_distance + 30.0, route.get_length() - 2.0)
	else:
		local_cyclist.distance_limit = gate_distance - 3.5


func _finish(success: bool) -> void:
	var riders := []
	for id: int in MultiplayerManager.get_roster():
		var c: CyclistController = cyclists.get(id)
		if c == null:
			continue
		riders.append({
			"name": c.player_name,
			"distance": c.distance,
			"max_speed": c.max_speed_reached,
			"gate_effort": gate.contributions.get(id, 0.0),
			"color": c.jersey_color,
		})
	var r := {
		"success": success,
		"time": elapsed,
		"gate_progress": gate.progress,
		"gate_opened": gate.is_open,
		"riders": riders,
	}
	_net_results.rpc(r)
	_net_set_stage.rpc(Stage.SUCCESS if success else Stage.FAILED)


# --- Networking ---------------------------------------------------------------

## Client -> host: "my scene is loaded".
@rpc("any_peer", "call_remote", "reliable")
func _net_client_ready() -> void:
	if is_host():
		_ready_peers[multiplayer.get_remote_sender_id()] = true


@rpc("authority", "call_local", "reliable")
func _net_set_stage(new_stage: Stage) -> void:
	if new_stage == stage:
		return
	stage = new_stage
	print("[Mission] Stage -> %s at %.1fs (lead %.0fm, rear %.0fm)" % [STAGE_NAMES[stage], elapsed, get_lead_distance(), get_rearmost_distance()])
	match stage:
		Stage.COUNTDOWN:
			countdown_left = countdown_seconds
			announced.emit(mission_title, "Escape the town before the dead find you", countdown_seconds + 1.0)
		Stage.DEPARTURE:
			audio.play("beep_go", -2.0)
			announced.emit("GO!", "Ride out of town - stay together", 2.0)
		Stage.PURSUIT:
			audio.play("alarm", -6.0)
			announced.emit("THEY'VE HEARD YOU", "Keep pedalling - the horde is coming!", 3.0)
		Stage.GATE:
			announced.emit("LOCKED GATE", "Pedal together to wind it open!", 3.0)
		Stage.FINAL_ESCAPE:
			gate.open_gate()
			audio.play("gate_open")
			announced.emit("GATE OPEN!", "Sprint for the extraction point!", 3.0)
		Stage.SUCCESS:
			audio.play("success")
			announced.emit("EXTRACTED!", "You made it out alive", results_delay)
			_results_timer = results_delay
		Stage.FAILED:
			audio.play("failure")
			announced.emit("OVERRUN", "The horde caught the group", results_delay)
			_results_timer = results_delay
	stage_changed.emit(stage)


@rpc("authority", "call_remote", "unreliable_ordered")
func _net_snapshot(p_elapsed: float, zombie_snap: Array, gate_progress: float, gate_rate: float, contributions: Dictionary) -> void:
	elapsed = p_elapsed
	zombies.apply_snapshot(zombie_snap)
	if not gate.is_open:
		gate.progress = gate_progress
	gate.team_effort_rate = gate_rate
	gate.contributions = contributions


@rpc("authority", "call_local", "reliable")
func _net_results(r: Dictionary) -> void:
	results = r
	# Add this player's own exact stats.
	if local_cyclist:
		results["my_distance"] = local_cyclist.distance
		results["my_max_speed"] = local_cyclist.max_speed_reached


@rpc("authority", "call_local", "reliable")
func _net_announce(title: String, subtitle: String, duration: float) -> void:
	audio.play("alarm", -8.0, 1.2)
	announced.emit(title, subtitle, duration)


func _on_surge_started() -> void:
	_net_announce.rpc("HORDE SURGE!", "They're speeding up - SPRINT!", 2.5)


func _on_player_left(peer_id: int) -> void:
	var c: CyclistController = cyclists.get(peer_id)
	if c:
		cyclists.erase(peer_id)
		c.queue_free()
		announced.emit("RIDER LOST", "%s disconnected" % c.player_name, 2.5)


func _on_replay_requested() -> void:
	if is_host():
		MultiplayerManager.start_mission()


func _on_menu_requested() -> void:
	MultiplayerManager.return_to_menu()
