class_name EndlessMission
extends MissionManager
## ENDLESS SURVIVAL - ride as far as you can on a road that never ends.
##
## The world is generated in chunks from a seed shared by all players. A
## checkpoint gate stands every couple of kilometres (team effort opens it, and
## the horde shuffles in while you work). The horde gets faster the further
## you go. Score = distance + checkpoints + survivors rescued.
##
## Survivors wait by the road. Slow down as you pass to pick them up: they
## ride at the back of the group, help wind the gates, and if the horde grabs
## the group, one of them is taken instead of you.
##
## Builds on MissionManager (riders, networking, horde, results) by overriding
## its mode hooks.

@export_group("Endless")
## Where the first checkpoint gate stands, and the distance between them (m).
@export var first_checkpoint: float = 1500.0
@export var checkpoint_spacing: float = 2000.0
## The horde's pace (m/s) rises this much per kilometre ridden...
@export var pace_increase_per_km: float = 0.3
## ...up to this pace. 14 m/s = 50 km/h: faster than most sprints, so every
## run ends eventually - stronger sprinters last longest.
@export var max_pace: float = 14.0
## Surges come this much more often per kilometre (fraction), down to half.
@export var surge_frequency_increase_per_km: float = 0.06
## Effort-seconds per rider for the first gate, plus this much per checkpoint.
@export var gate_effort_first: float = 10.0
@export var gate_effort_per_checkpoint: float = 2.0
@export_group("Survivors")
## Chance that a 200 m stretch of road has a survivor waiting.
@export var survivor_chance: float = 0.3
## Riders must pass a survivor slower than this (m/s) to pick them up.
## 5.5 m/s = 20 km/h.
@export var pickup_speed: float = 5.5
@export var max_companions: int = 3
## Effort per second each companion adds at checkpoint gates.
@export var companion_gate_effort: float = 0.3
@export_group("Score")
@export var points_per_checkpoint: int = 500
@export var points_per_survivor: int = 250

var checkpoints_passed: int = 0
var world_seed: int = 1

var _checkpoint_dressing: Node3D
var _base_pace: float
var _base_surge_interval: Vector2
var _first_pursuit := true

const SURVIVOR_NAMES := ["Marco", "Ines", "Sven", "Aya", "Tomasz", "Lotte", "Ruben", "Mila",
	"Joris", "Fenna", "Kasper", "Noor", "Bram", "Elif", "Pieter", "Sanne"]
enum SurvivorState { WAITING, PICKED_UP, LEFT_BEHIND }
## Survivor id (chunk index) -> {distance, side, name, state, node}
var survivors: Dictionary = {}
var companions: Array[Companion] = []
var survivors_rescued: int = 0
var survivors_lost: int = 0


# --- Mode hooks -----------------------------------------------------------------

func _build_world() -> void:
	mission_title = "ENDLESS SURVIVAL"
	world_seed = MultiplayerManager.mission_seed
	(route as EndlessRoute).reset(world_seed)
	town.keep_clear = _near_checkpoint
	town.chunk_built.connect(_on_chunk_built)
	town.chunk_freed.connect(_on_chunk_freed)
	town.start_endless(route, world_seed)
	zombies.setup(route, 0.0, 0.0)  # roadside zombies come with each chunk
	_base_pace = zombies.pursuit_pace
	_base_surge_interval = zombies.surge_interval
	_place_checkpoint(0)
	# Dress the first stretch of road before the riders appear.
	for i in 6:
		town.update_streaming(0.0, 0.0)
	print("[Endless] World seed %d" % world_seed)


func _update_mode(delta: float) -> void:
	town.update_streaming(get_rearmost_distance(), get_lead_distance())
	_update_companions(delta)


func _update_stages(delta: float, rear: float, lead: float) -> void:
	match stage:
		Stage.DEPARTURE:
			if elapsed >= pursuit_start_time or lead >= pursuit_start_distance:
				zombies.set_phase(ZombieDirector.Phase.PURSUIT, rear)
				_net_set_stage.rpc(Stage.PURSUIT)
		Stage.PURSUIT:
			_apply_difficulty(lead)
			_check_survivors(rear)
			if gate.is_open:
				# Everyone is through: move the gate on to the next checkpoint.
				if rear > gate.distance_on_route + 60.0:
					_net_next_checkpoint.rpc(checkpoints_passed + 1)
			elif lead >= gate.distance_on_route - gate_trigger_range:
				zombies.set_phase(ZombieDirector.Phase.GATE, rear, gate.distance_on_route - 3.5)
				_net_set_stage.rpc(Stage.GATE)
		Stage.GATE:
			_work_gate(delta, _helper_gate_effort())
			if gate.progress >= 1.0:
				zombies.set_phase(ZombieDirector.Phase.PURSUIT, rear)
				zombies.shake_off(rear, 8.0)
				_net_checkpoint_opened.rpc()
				_net_set_stage.rpc(Stage.PURSUIT)


func _stage_announcement(new_stage: Stage) -> Array:
	match new_stage:
		Stage.COUNTDOWN:
			return [mission_title, "How far can you get?"]
		Stage.PURSUIT:
			if _first_pursuit:
				_first_pursuit = false
				return ["THEY'VE HEARD YOU", "Keep pedalling - the horde is coming!"]
			return ["", ""]
		Stage.GATE:
			return ["CHECKPOINT %d" % (checkpoints_passed + 1), "Pedal together to open the gate!"]
		Stage.FAILED:
			return ["OVERRUN", "You made it %.2f km" % (get_rearmost_distance() / 1000.0)]
	return super._stage_announcement(new_stage)


func _distance_limit() -> float:
	return 1.0e7 if gate.is_open else gate.distance_on_route - 3.5


func get_next_objective() -> Array:
	var d := local_cyclist.distance if local_cyclist else 0.0
	var survivor := _next_waiting_survivor(d)
	if not survivor.is_empty() and survivor["distance"] - d < 400.0 and stage == Stage.PURSUIT and companions.size() < max_companions:
		if survivor["distance"] - d < 40.0 and local_cyclist.speed > pickup_speed:
			return ["SLOW DOWN to %d km/h! SURVIVOR" % roundi(pickup_speed * 3.6), maxf(survivor["distance"] - d, 0.0)]
		return ["SURVIVOR - slow to %d km/h to pick up" % roundi(pickup_speed * 3.6), maxf(survivor["distance"] - d, 0.0)]
	var next := gate.distance_on_route
	if gate.is_open:
		next = _checkpoint_distance(checkpoints_passed + 1)
	return ["CHECKPOINT", maxf(next - d, 0.0)]


func get_objective_text() -> String:
	match stage:
		Stage.DEPARTURE, Stage.PURSUIT:
			var text := "Survive!   %.2f km   -   %s" % [get_lead_distance() / 1000.0, TownBuilder.BIOME_NAMES[town.biome_at(get_lead_distance())]]
			if companions.size() > 0:
				text += "   -   with " + ", ".join(companions.map(func(c: Companion) -> String: return c.companion_name))
			return text
		Stage.GATE:
			return "PEDAL TOGETHER to open checkpoint %d!" % (checkpoints_passed + 1)
		Stage.FAILED:
			return "The horde caught the group."
	return super.get_objective_text()


func get_progress_window() -> Array:
	var lead := get_lead_distance()
	var next := gate.distance_on_route if not gate.is_open else _checkpoint_distance(checkpoints_passed + 1)
	return [lead - 300.0, lead + 1200.0, next, ["", "", ""]]


## Survivors waiting ahead, for the progress bar: [distance, colour].
func get_progress_markers() -> Array:
	var list := []
	for s: Dictionary in survivors.values():
		if s["state"] == SurvivorState.WAITING:
			list.append([s["distance"], Color(0.4, 1.0, 0.5)])
	return list


func _extra_results() -> Dictionary:
	var distance := get_rearmost_distance()
	return {
		"mode": MultiplayerManager.MODE_ENDLESS,
		"team_distance": distance,
		"checkpoints": checkpoints_passed,
		"survivors_rescued": survivors_rescued,
		"survivors_lost": survivors_lost,
		"score": get_score(),
		"seed": world_seed,
	}


func get_score() -> int:
	return int(get_rearmost_distance()) + checkpoints_passed * points_per_checkpoint + survivors_rescued * points_per_survivor


## Effort per second added at gates by helpers (survivors, see below).
func _helper_gate_effort() -> float:
	return companion_gate_effort * companions.size()


## Host: the horde finished grabbing. A companion is taken instead, if any.
func _on_group_caught(rear: float) -> void:
	if companions.is_empty():
		super._on_group_caught(rear)
		return
	zombies.shake_off(rear, 12.0)  # the horde stops to feed
	_net_companion_lost.rpc()


# --- Checkpoints ------------------------------------------------------------------

func _checkpoint_distance(index: int) -> float:
	return first_checkpoint + checkpoint_spacing * index


## Keeps buildings and cars away from checkpoint gates.
func _near_checkpoint(d: float) -> bool:
	if d < first_checkpoint - 60.0:
		return false
	var offset := fposmod(d - first_checkpoint, checkpoint_spacing)
	return offset < 40.0 or offset > checkpoint_spacing - 60.0


func _place_checkpoint(index: int) -> void:
	var d := _checkpoint_distance(index)
	gate.reset_at(route.get_frame(d), d)
	gate.effort_seconds_per_rider = gate_effort_first + gate_effort_per_checkpoint * index
	if _checkpoint_dressing:
		_checkpoint_dressing.queue_free()
	_checkpoint_dressing = town.make_checkpoint_dressing(d)


@rpc("authority", "call_local", "reliable")
func _net_checkpoint_opened() -> void:
	gate.open_gate()
	audio.play("gate_open")
	announced.emit("CHECKPOINT %d CLEARED" % (checkpoints_passed + 1), "Keep going - it only gets harder", 3.0)


@rpc("authority", "call_local", "reliable")
func _net_next_checkpoint(index: int) -> void:
	checkpoints_passed = index
	_place_checkpoint(index)
	print("[Endless] Checkpoint %d passed at %.1fs" % [index, elapsed])


# --- Difficulty -------------------------------------------------------------------

## Host only: the horde gets faster and surges more often the further you go.
func _apply_difficulty(distance: float) -> void:
	var km := maxf(distance, 0.0) / 1000.0
	zombies.pursuit_pace = minf(_base_pace + pace_increase_per_km * km, max_pace)
	zombies.surge_interval = _base_surge_interval * maxf(0.5, 1.0 - surge_frequency_increase_per_km * km)


# --- Streaming ----------------------------------------------------------------------

func _on_chunk_built(index: int, from_d: float, to_d: float) -> void:
	# No roadside zombies right at the start line.
	zombies.spawn_wanderers(maxf(from_d, 60.0), to_d, world_seed * 13 + index)
	_maybe_place_survivor(index, from_d, to_d)


func _on_chunk_freed(index: int, _from_d: float, to_d: float) -> void:
	zombies.despawn_wanderers_before(to_d)
	if survivors.has(index):
		var node: Variant = survivors[index]["node"]
		if is_instance_valid(node):
			(node as Node3D).queue_free()
		survivors.erase(index)


# --- Survivors --------------------------------------------------------------------

## Every machine decides the same way (seeded), so survivors appear in the
## same places for everyone; only pick-ups are decided by the host.
func _maybe_place_survivor(index: int, from_d: float, to_d: float) -> void:
	if index < 3:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 17 + index * 31
	if rng.randf() > survivor_chance:
		return
	var d := rng.randf_range(from_d + 30.0, to_d - 30.0)
	if _near_checkpoint(d) or _near_checkpoint(d + 60.0):
		return
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var survivor_name: String = SURVIVOR_NAMES[(world_seed + index) % SURVIVOR_NAMES.size()]
	var node := Survivor.new()
	node.build(survivor_name, world_seed + index)
	add_child(node)
	var f := route.get_frame(d)
	# On the pavement, facing the road.
	node.global_transform = Transform3D(f.basis.rotated(Vector3.UP, side * PI * 0.5), f.origin + f.basis.x * side * 6.3)
	survivors[index] = {"distance": d, "side": side, "name": survivor_name, "state": SurvivorState.WAITING, "node": node}


## Distance to the next waiting survivor ahead, or -1 if none (also used by
## the test autopilot).
func distance_to_next_survivor(from_distance: float) -> float:
	var s := _next_waiting_survivor(from_distance)
	return -1.0 if s.is_empty() else s["distance"] - from_distance


func _next_waiting_survivor(from_distance: float) -> Dictionary:
	var best := {}
	for s: Dictionary in survivors.values():
		if s["state"] == SurvivorState.WAITING and s["distance"] > from_distance - 10.0:
			if best.is_empty() or s["distance"] < best["distance"]:
				best = s
	return best


## Host: pick up survivors that a slow rider passes; leave the rest behind.
func _check_survivors(rear: float) -> void:
	for id: int in survivors:
		var s: Dictionary = survivors[id]
		if s["state"] != SurvivorState.WAITING:
			continue
		if companions.size() >= max_companions:
			continue
		for c: CyclistController in cyclists.values():
			if absf(c.distance - s["distance"]) < 10.0 and c.speed < pickup_speed:
				_net_survivor_picked_up.rpc(id)
				break
		if s["state"] == SurvivorState.WAITING and rear > s["distance"] + 15.0:
			_net_survivor_left.rpc(id)


@rpc("authority", "call_local", "reliable")
func _net_survivor_picked_up(id: int) -> void:
	var s: Dictionary = survivors.get(id, {})
	if s.is_empty() or s["state"] != SurvivorState.WAITING:
		return
	s["state"] = SurvivorState.PICKED_UP
	if is_instance_valid(s["node"]):
		(s["node"] as Node3D).queue_free()
	var companion := Companion.new()
	add_child(companion)
	companion.setup(s["name"], route, s["distance"])
	companions.append(companion)
	_assign_slots()
	survivors_rescued += 1
	print("[Endless] Picked up %s at %.0f m" % [s["name"], s["distance"]])
	audio.play("countdown_beep", -2.0, 1.4)
	announced.emit("%s JOINS YOU" % s["name"].to_upper(), "Survivors ride at the back - they'll buy you time", 2.5)


@rpc("authority", "call_local", "reliable")
func _net_survivor_left(id: int) -> void:
	var s: Dictionary = survivors.get(id, {})
	if s.is_empty() or s["state"] != SurvivorState.WAITING:
		return
	s["state"] = SurvivorState.LEFT_BEHIND
	print("[Endless] Left %s behind at %.0f m" % [s["name"], s["distance"]])
	if is_instance_valid(s["node"]):
		(s["node"] as Survivor).left_behind()


## The horde takes the last companion in the line.
@rpc("authority", "call_local", "reliable")
func _net_companion_lost() -> void:
	if companions.is_empty():
		return
	var c: Companion = companions.pop_back()
	c.fall()
	survivors_lost += 1
	print("[Endless] %s was taken by the horde" % c.companion_name)
	_assign_slots()
	audio.play("horde_roar", 2.0, 0.85)
	announced.emit("THEY GOT %s" % c.companion_name.to_upper(), "The horde stops to feed - get away!", 3.0)


func _assign_slots() -> void:
	for i in companions.size():
		companions[i].slot = i


## Companions ride just behind the rearmost rider. While the horde is grabbing,
## the last one drops back into it.
func _update_companions(delta: float) -> void:
	var rear := get_rearmost_distance()
	var grabbing := zombies.is_grabbing()
	for i in companions.size():
		var c := companions[i]
		var target := rear - 3.0 - i * 2.2
		if grabbing and i == companions.size() - 1:
			target = zombies.front_distance + 0.5
		c.ride(delta, target)
