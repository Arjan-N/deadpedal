class_name EndlessMission
extends MissionManager
## ENDLESS SURVIVAL - ride as far as you can on a road that never ends.
##
## The world is generated in chunks from a seed shared by all players. A
## checkpoint gate stands every couple of kilometres (team effort opens it, and
## the horde shuffles in while you work). The horde gets faster the further
## you go. Score = distance + checkpoints + survivors rescued.
##
## Along the road (at most one per 200 m stretch):
##  * SURVIVORS - slow down as you pass to pick them up. They take turns on
##    the front (sit in their slipstream!), help wind the gates, and when the
##    horde grabs the group, one of them is taken instead of you. Pulling tires
##    them out: an exhausted survivor fades back towards the horde until a
##    rider drops back and gives them a wheel to follow.
##  * SCREAMERS - pass them faster than 30 km/h, or they shriek and the horde
##    surges.
##  * SUPPLY CRATES - slow down to grab them. Flares drive the horde back;
##    food gives your survivors their energy back.
## From the first kilometre, RUNNERS break out of the horde now and then:
## sprint away before they reach you, or they knock you off your rhythm.
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
@export_group("Roadside")
## Chance that a 200 m stretch of road has a survivor / screamer / supply
## crate (at most one of them).
@export var survivor_chance: float = 0.3
@export var screamer_chance: float = 0.18
@export var crate_chance: float = 0.15
## No screamers before this distance (m).
@export var screamers_from: float = 1000.0
## Riders must pass survivors and crates slower than this (m/s) to pick them
## up. 5.5 m/s = 20 km/h.
@export var pickup_speed: float = 5.5
## Riders must pass screamers faster than this (m/s). 8.4 m/s = 30 km/h.
@export var screamer_speed: float = 8.4
## How long a screamer's surge lasts (s).
@export var screamer_surge_time: float = 8.0
## Flares drive the horde back to this gap (m).
@export var flare_gap: float = 42.0
@export_group("Survivors")
@export var max_companions: int = 3
## Effort per second each companion adds at checkpoint gates.
@export var companion_gate_effort: float = 0.3
## Companions can't ride faster than this (m/s) - sprint past them if you like.
@export var companion_top_speed: float = 12.0
## Energy used per second on the front at 36 km/h (more when faster).
## Each survivor's stamina varies a little around this.
@export var front_drain: float = 0.014
## Energy regained per second resting in the group at low speed (they
## recover less while the group is flying)...
@export var group_recovery: float = 0.008
## ...and per second when exhausted but following a rider's wheel.
@export var wheel_recovery: float = 0.1
## Below this energy a companion is exhausted; at this energy they're fine again.
@export var exhausted_below: float = 0.12
@export var recovered_at: float = 0.5
## A companion needs this much energy to take a turn on the front...
@export var front_min_energy: float = 0.9
## ...and swaps off when below this (if someone fresher can take over).
@export var swap_below: float = 0.25
## Exhausted companions slow to this speed (m/s)...
@export var exhausted_speed: float = 5.0
## ...this quickly (m/s per second).
@export var exhausted_slowdown: float = 0.6
## A rider within this distance (m) in front of an exhausted companion gives
## them a wheel to follow.
@export var wheel_range: float = 8.0
@export_group("Runners")
## Runners start breaking out of the horde after this distance (m)...
@export var runners_from: float = 1600.0
## ...every this many seconds (random), more often the further you go.
@export var runner_interval: Vector2 = Vector2(40.0, 70.0)
## A runner that reaches you cuts your speed to this fraction.
@export var runner_slowdown: float = 0.65
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
enum Kind { SURVIVOR, SCREAMER, CRATE }
enum ItemState { WAITING, TAKEN, PASSED }
## Roadside item id (chunk index) -> {kind, distance, side, state, node, name, content}
var items: Dictionary = {}
var companions: Array[Companion] = []
var survivors_rescued: int = 0
var survivors_lost: int = 0
var crates_collected: int = 0
var screamers_set_off: int = 0

enum CompanionEvent { EXHAUSTED, RECOVERED }


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
	if is_host():
		zombies.runner_started.connect(_on_runner_started)
		zombies.runner_reached.connect(_on_runner_reached)
	_place_checkpoint(0)
	# Dress the first stretch of road before the riders appear.
	for i in 6:
		town.update_streaming(0.0, 0.0)
	print("[Endless] World seed %d" % world_seed)


func _update_mode(delta: float) -> void:
	town.update_streaming(get_rearmost_distance(), get_lead_distance())
	if is_host():
		_simulate_companions(delta)
	else:
		for c in companions:
			c.follow_network(delta)
	for c in companions:
		c.update_visuals(delta)


func _update_stages(delta: float, rear: float, lead: float) -> void:
	zombies.runner_prey = _runner_prey(rear)
	match stage:
		Stage.DEPARTURE:
			if elapsed >= pursuit_start_time or lead >= pursuit_start_distance:
				zombies.set_phase(ZombieDirector.Phase.PURSUIT, rear)
				_net_set_stage.rpc(Stage.PURSUIT)
		Stage.PURSUIT:
			_apply_difficulty(lead)
			_check_items(rear)
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
	var speed := local_cyclist.speed if local_cyclist else 0.0
	if stage == Stage.PURSUIT or stage == Stage.GATE:
		var tired := _exhausted_companion()
		if tired:
			if tired.on_wheel:
				return ["%s IS ON A WHEEL - keep it steady" % tired.companion_name.to_upper(), maxf(d - tired.distance, 0.0)]
			return ["%s IS EXHAUSTED - drop back, give them your wheel" % tired.companion_name.to_upper(), maxf(d - tired.distance, 0.0)]
	var item := _next_waiting_item(d, true)
	if not item.is_empty() and item["distance"] - d < 300.0 and stage == Stage.PURSUIT:
		var to_go: float = maxf(item["distance"] - d, 0.0)
		var close := to_go < 50.0
		match item["kind"]:
			Kind.SURVIVOR:
				if close and speed > pickup_speed:
					return ["SLOW DOWN to %d km/h! SURVIVOR" % _kmh(pickup_speed), to_go]
				return ["SURVIVOR - slow to %d km/h to pick up" % _kmh(pickup_speed), to_go]
			Kind.CRATE:
				var title: String = SupplyCrate.TITLES[item["content"]]
				if close and speed > pickup_speed:
					return ["SLOW DOWN to %d km/h! %s" % [_kmh(pickup_speed), title], to_go]
				return ["%s - slow to %d km/h to grab" % [title, _kmh(pickup_speed)], to_go]
			Kind.SCREAMER:
				if close and speed < screamer_speed:
					return ["SPRINT! SCREAMER - get above %d km/h" % _kmh(screamer_speed), to_go]
				return ["SCREAMER - pass faster than %d km/h" % _kmh(screamer_speed), to_go]
	var next := gate.distance_on_route
	if gate.is_open:
		next = _checkpoint_distance(checkpoints_passed + 1)
	return ["CHECKPOINT", maxf(next - d, 0.0)]


func _kmh(mps: float) -> int:
	return roundi(mps * 3.6)


func get_objective_text() -> String:
	match stage:
		Stage.DEPARTURE, Stage.PURSUIT:
			return "Survive!   %.2f km   -   %s" % [get_lead_distance() / 1000.0, TownBuilder.BIOME_NAMES[town.biome_at(get_lead_distance())]]
		Stage.GATE:
			return "PEDAL TOGETHER to open checkpoint %d!" % (checkpoints_passed + 1)
		Stage.FAILED:
			return "The horde caught the group."
	return super.get_objective_text()


func get_progress_window() -> Array:
	var lead := get_lead_distance()
	var next := gate.distance_on_route if not gate.is_open else _checkpoint_distance(checkpoints_passed + 1)
	return [lead - 300.0, lead + 1200.0, next, ["", "", ""]]


## Roadside items ahead and exhausted companions, for the progress bar.
func get_progress_markers() -> Array:
	var list := []
	for it: Dictionary in items.values():
		if it["state"] != ItemState.WAITING:
			continue
		match it["kind"]:
			Kind.SURVIVOR:
				list.append([it["distance"], Color(0.4, 1.0, 0.5)])
			Kind.CRATE:
				list.append([it["distance"], SupplyCrate.COLORS[it["content"]]])
			Kind.SCREAMER:
				list.append([it["distance"], Color(0.85, 0.4, 1.0)])
	for c in companions:
		if c.state == Companion.State.TIRED:
			list.append([c.distance, Color(1.0, 0.3, 0.2)])
	return list


func get_companion_rows() -> Array:
	var rows := []
	for c in companions:
		var status: String = Companion.STATE_NAMES[c.state]
		var color := Color(0.6, 0.9, 0.6)
		match c.state:
			Companion.State.FRONT:
				color = Color(0.5, 0.85, 1.0)
			Companion.State.TIRED:
				status = "on a wheel" if c.on_wheel else "EXHAUSTED"
				color = Color(1.0, 0.35, 0.25)
		rows.append([c.companion_name, c.energy, status, color])
	return rows


func _extra_results() -> Dictionary:
	var distance := get_rearmost_distance()
	return {
		"mode": MultiplayerManager.MODE_ENDLESS,
		"team_distance": distance,
		"checkpoints": checkpoints_passed,
		"survivors_rescued": survivors_rescued,
		"survivors_lost": survivors_lost,
		"crates": crates_collected,
		"screamers": screamers_set_off,
		"score": get_score(),
		"seed": world_seed,
	}


func get_score() -> int:
	return int(get_rearmost_distance()) + checkpoints_passed * points_per_checkpoint + survivors_rescued * points_per_survivor


## Effort per second added at gates by helpers (companions).
func _helper_gate_effort() -> float:
	return companion_gate_effort * companions.size()


## Host: the horde finished grabbing. A companion is taken instead, if any.
func _on_group_caught(rear: float) -> void:
	var victim := _victim()
	if victim == null:
		super._on_group_caught(rear)
		return
	zombies.shake_off(rear, 12.0)  # the horde stops to feed
	_net_companion_lost.rpc(victim.id)


func _mode_snapshot() -> Array:
	var data := PackedFloat32Array()
	for c in companions:
		data.append_array([c.id, c.distance, c.speed, c.energy, c.state, 1.0 if c.on_wheel else 0.0])
	return [data]


func _apply_mode_snapshot(snap: Array) -> void:
	var data: PackedFloat32Array = snap[0]
	for i in range(0, data.size(), 6):
		var c := _companion(int(data[i]))
		if c:
			c.apply_net_state(data[i + 1], data[i + 2], data[i + 3], int(data[i + 4]), data[i + 5] > 0.5)


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

## Host only: the horde gets faster, surges more often and sends more
## runners the further you go.
func _apply_difficulty(distance: float) -> void:
	var km := maxf(distance, 0.0) / 1000.0
	zombies.pursuit_pace = minf(_base_pace + pace_increase_per_km * km, max_pace)
	zombies.surge_interval = _base_surge_interval * maxf(0.5, 1.0 - surge_frequency_increase_per_km * km)
	if distance < runners_from:
		zombies.runner_interval = Vector2.ZERO
	else:
		zombies.runner_interval = runner_interval * maxf(0.6, 1.0 - 0.04 * (distance - runners_from) / 1000.0)


# --- Streaming ----------------------------------------------------------------------

func _on_chunk_built(index: int, from_d: float, to_d: float) -> void:
	# No roadside zombies right at the start line.
	zombies.spawn_wanderers(maxf(from_d, 60.0), to_d, world_seed * 13 + index)
	_maybe_place_item(index, from_d, to_d)


func _on_chunk_freed(index: int, _from_d: float, to_d: float) -> void:
	zombies.despawn_wanderers_before(to_d)
	if items.has(index):
		var node: Variant = items[index]["node"]
		if is_instance_valid(node):
			(node as Node3D).queue_free()
		items.erase(index)


# --- Roadside items -----------------------------------------------------------------

## Every machine decides the same way (seeded), so items appear in the same
## places for everyone; only what happens to them is decided by the host.
func _maybe_place_item(index: int, from_d: float, to_d: float) -> void:
	if index < 3:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 17 + index * 31
	var roll := rng.randf()
	var d := rng.randf_range(from_d + 30.0, to_d - 30.0)
	if _near_checkpoint(d) or _near_checkpoint(d + 60.0):
		return
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var item := {"distance": d, "side": side, "state": ItemState.WAITING, "name": "", "content": 0}
	var node: Node3D
	var lateral := 6.3
	if roll < survivor_chance:
		item["kind"] = Kind.SURVIVOR
		item["name"] = SURVIVOR_NAMES[(world_seed + index) % SURVIVOR_NAMES.size()]
		var survivor := Survivor.new()
		survivor.build(item["name"], world_seed + index)
		node = survivor
	elif roll < survivor_chance + screamer_chance and from_d >= screamers_from:
		item["kind"] = Kind.SCREAMER
		var screamer := Screamer.new()
		screamer.build(world_seed + index)
		node = screamer
		lateral = 5.8
	elif roll < survivor_chance + screamer_chance + crate_chance:
		item["kind"] = Kind.CRATE
		item["content"] = SupplyCrate.Content.FLARES if rng.randf() < 0.5 else SupplyCrate.Content.FOOD
		var crate := SupplyCrate.new()
		crate.build(item["content"])
		node = crate
	else:
		return
	add_child(node)
	var f := route.get_frame(d)
	# On the pavement, facing the road.
	node.global_transform = Transform3D(f.basis.rotated(Vector3.UP, side * PI * 0.5), f.origin + f.basis.x * side * lateral)
	item["node"] = node
	items[index] = item


## Distance to the next survivor or crate to pick up, or -1 if none (used by
## the test autopilot).
func distance_to_next_pickup(from_distance: float) -> float:
	var it := _next_waiting_item(from_distance, false, [Kind.SURVIVOR, Kind.CRATE])
	return -1.0 if it.is_empty() else it["distance"] - from_distance


## Distance to the next screamer, or -1 if none (test autopilot).
func distance_to_next_screamer(from_distance: float) -> float:
	var it := _next_waiting_item(from_distance, false, [Kind.SCREAMER])
	return -1.0 if it.is_empty() else it["distance"] - from_distance


## How far behind `from_distance` an exhausted companion is (no one is giving
## them a wheel), or -1 if none (test autopilot).
func exhausted_companion_gap(from_distance: float) -> float:
	var c := _exhausted_companion()
	return -1.0 if c == null else from_distance - c.distance


func _next_waiting_item(from_distance: float, include_screamers: bool, kinds: Array = []) -> Dictionary:
	var best := {}
	for it: Dictionary in items.values():
		if it["state"] != ItemState.WAITING or it["distance"] <= from_distance - 10.0:
			continue
		if not kinds.is_empty() and not it["kind"] in kinds:
			continue
		if not include_screamers and kinds.is_empty() and it["kind"] == Kind.SCREAMER:
			continue
		if it["kind"] == Kind.SURVIVOR and companions.size() >= max_companions:
			continue
		if best.is_empty() or it["distance"] < best["distance"]:
			best = it
	return best


## Host: picks up, screams and items left behind.
func _check_items(rear: float) -> void:
	for id: int in items:
		var it: Dictionary = items[id]
		if it["state"] != ItemState.WAITING:
			continue
		var d: float = it["distance"]
		for c: CyclistController in cyclists.values():
			match it["kind"]:
				Kind.SURVIVOR:
					if companions.size() < max_companions and absf(c.distance - d) < 10.0 and c.speed < pickup_speed:
						_net_survivor_picked_up.rpc(id)
				Kind.CRATE:
					if absf(c.distance - d) < 10.0 and c.speed < pickup_speed:
						_net_crate_collected.rpc(id)
				Kind.SCREAMER:
					if absf(c.distance - d) < 3.0 and c.speed < screamer_speed:
						_net_screamer_triggered.rpc(id)
			if it["state"] != ItemState.WAITING:
				break
		if it["state"] == ItemState.WAITING and rear > d + 15.0:
			_net_item_passed.rpc(id)


@rpc("authority", "call_local", "reliable")
func _net_survivor_picked_up(id: int) -> void:
	var it: Dictionary = items.get(id, {})
	if it.is_empty() or it["state"] != ItemState.WAITING:
		return
	it["state"] = ItemState.TAKEN
	if is_instance_valid(it["node"]):
		(it["node"] as Node3D).queue_free()
	var companion := Companion.new()
	add_child(companion)
	companion.setup(id, it["name"], route, it["distance"])
	var rng := RandomNumberGenerator.new()
	rng.seed = world_seed * 7 + id
	companion.stamina = rng.randf_range(0.8, 1.2)
	companions.append(companion)
	_assign_slots()
	survivors_rescued += 1
	print("[Endless] Picked up %s at %.0f m" % [it["name"], it["distance"]])
	audio.play("countdown_beep", -2.0, 1.4)
	announced.emit("%s JOINS YOU" % it["name"].to_upper(), "Survivors take turns on the front - ride in their slipstream", 2.5)


@rpc("authority", "call_local", "reliable")
func _net_crate_collected(id: int) -> void:
	var it: Dictionary = items.get(id, {})
	if it.is_empty() or it["state"] != ItemState.WAITING:
		return
	it["state"] = ItemState.TAKEN
	if is_instance_valid(it["node"]):
		(it["node"] as Node3D).queue_free()
	crates_collected += 1
	audio.play("gate_ratchet", 0.0, 1.3)
	if it["content"] == SupplyCrate.Content.FLARES:
		print("[Endless] Grabbed flares at %.0f m" % it["distance"])
		if is_host():
			zombies.shake_off(get_rearmost_distance(), flare_gap)
			zombies.surging = false
		audio.play("horde_roar", -4.0, 0.7)
		announced.emit("FLARES!", "The horde falls back from the light", 2.5)
	else:
		print("[Endless] Grabbed food at %.0f m" % it["distance"])
		if is_host():
			for c in companions:
				c.energy = 1.0
				c.state = Companion.State.GROUP
		announced.emit("FOOD!", "Your survivors are fresh again" if companions.size() > 0 else "Nobody to share it with...", 2.5)


@rpc("authority", "call_local", "reliable")
func _net_screamer_triggered(id: int) -> void:
	var it: Dictionary = items.get(id, {})
	if it.is_empty() or it["state"] != ItemState.WAITING:
		return
	it["state"] = ItemState.TAKEN
	screamers_set_off += 1
	if is_instance_valid(it["node"]):
		(it["node"] as Screamer).scream()
	print("[Endless] A screamer went off at %.0f m" % it["distance"])
	if is_host():
		zombies.force_surge(screamer_surge_time)
	audio.play("horde_roar", 4.0, 1.5)
	announced.emit("IT SCREAMED!", "The horde surges - SPRINT!", 2.5)


@rpc("authority", "call_local", "reliable")
func _net_item_passed(id: int) -> void:
	var it: Dictionary = items.get(id, {})
	if it.is_empty() or it["state"] != ItemState.WAITING:
		return
	it["state"] = ItemState.PASSED
	var node: Variant = it["node"]
	match it["kind"]:
		Kind.SURVIVOR:
			print("[Endless] Left %s behind at %.0f m" % [it["name"], it["distance"]])
			if is_instance_valid(node):
				(node as Survivor).left_behind()
		Kind.SCREAMER:
			print("[Endless] Sprinted past a screamer at %.0f m" % it["distance"])
			if is_instance_valid(node):
				(node as Screamer).silence()
		Kind.CRATE:
			print("[Endless] Missed a crate at %.0f m" % it["distance"])
			if is_instance_valid(node):
				(node as SupplyCrate).left_behind()


# --- Runners --------------------------------------------------------------------------

## Host: runners go for an exhausted companion lagging behind the group, or
## the rearmost rider.
func _runner_prey(rear: float) -> float:
	var prey := rear
	for c in companions:
		if c.state == Companion.State.TIRED and c.distance > zombies.front_distance:
			prey = minf(prey, c.distance)
	return prey


func _on_runner_started() -> void:
	_net_runner_started.rpc()


@rpc("authority", "call_local", "reliable")
func _net_runner_started() -> void:
	print("[Endless] A runner breaks from the horde")
	audio.play("horde_roar", 0.0, 1.3)
	announced.emit("RUNNER!", "One's breaking from the horde - sprint away!", 2.0)


## Host: a runner reached what it was chasing.
func _on_runner_reached(prey: float) -> void:
	for c in companions:
		if c.state == Companion.State.TIRED and absf(c.distance - prey) < 2.0:
			_net_companion_lost.rpc(c.id)
			return
	var rear_id := -1
	var rear := INF
	for id: int in cyclists:
		if cyclists[id].distance < rear:
			rear = cyclists[id].distance
			rear_id = id
	if rear_id != -1:
		_net_runner_hit.rpc(rear_id)


@rpc("authority", "call_local", "reliable")
func _net_runner_hit(peer_id: int) -> void:
	var c: CyclistController = cyclists.get(peer_id)
	if c == null:
		return
	print("[Endless] A runner caught %s" % c.player_name)
	audio.play("groan", 4.0, 1.3)
	if c == local_cyclist:
		c.stagger(runner_slowdown)
		announced.emit("A RUNNER GOT YOU!", "Shake it off - keep pedalling!", 2.0)
	else:
		announced.emit("A RUNNER CAUGHT %s" % c.player_name.to_upper(), "Stay with them!", 2.0)


# --- Companions -----------------------------------------------------------------------

func _companion(id: int) -> Companion:
	for c in companions:
		if c.id == id:
			return c
	return null


## The companion fading back towards the horde without a wheel (or on one).
func _exhausted_companion() -> Companion:
	var worst: Companion = null
	for c in companions:
		if c.state == Companion.State.TIRED and (worst == null or c.distance < worst.distance):
			worst = c
	return worst


## Who the horde takes when it catches the group: an exhausted companion
## first, otherwise the last one in the line.
func _victim() -> Companion:
	var tired := _exhausted_companion()
	if tired:
		return tired
	return companions.back() if companions.size() > 0 else null


## The best rested companion ready for a turn on the front. `allow_mid_turn`
## also accepts someone who was passed halfway through their turn.
func _freshest_resting(allow_mid_turn: bool) -> Companion:
	var best: Companion = null
	for c in companions:
		var ready := c.energy >= front_min_energy or (allow_mid_turn and c.mid_turn and c.energy > swap_below)
		if c.state == Companion.State.GROUP and ready and c.rest_time <= 0.0 and (best == null or c.energy > best.energy):
			best = c
	return best


## Host: who's on the front, where everyone rides, energy, exhaustion, and
## exhausted companions caught by the horde.
func _simulate_companions(delta: float) -> void:
	if companions.is_empty() or cyclists.is_empty():
		return
	var lead_c: CyclistController = null
	var rear_c: CyclistController = null
	for c: CyclistController in cyclists.values():
		if lead_c == null or c.distance > lead_c.distance:
			lead_c = c
		if rear_c == null or c.distance < rear_c.distance:
			rear_c = c
	var limit := INF if gate.is_open else gate.distance_on_route - 4.5
	var riding := stage == Stage.DEPARTURE or stage == Stage.PURSUIT
	var horde_active := zombies.phase in [ZombieDirector.Phase.PURSUIT, ZombieDirector.Phase.GATE, ZombieDirector.Phase.FINAL_ESCAPE]

	# Rotate the front: the freshest companion takes over a tiring one.
	var front: Companion = null
	for c in companions:
		if c.state == Companion.State.FRONT:
			front = c
	if front and (not riding or front.energy < swap_below):
		var fresh: Companion = _freshest_resting(false) if riding else null
		if fresh or not riding:
			front.state = Companion.State.GROUP
			front = null
	if front == null and riding:
		var fresh := _freshest_resting(true)
		if fresh:
			fresh.state = Companion.State.FRONT
			fresh.mid_turn = false
			fresh.at_front = false

	# Sprint past whoever's on the front and they tuck into the group for a
	# while instead of burning out behind you.
	for c in companions:
		c.rest_time = maxf(c.rest_time - delta, 0.0)
		if c.state == Companion.State.FRONT and c.at_front and c.distance < lead_c.distance - 3.0:
			c.state = Companion.State.GROUP
			c.rest_time = 6.0
			c.mid_turn = true  # they'll come back to finish their turn

	var victim := _victim() if zombies.is_grabbing() else null
	var group_index := 0
	var lost: Array[int] = []
	for c in companions:
		match c.state:
			Companion.State.FRONT:
				c.on_wheel = false
				# Moving up past the riders, then setting the pace.
				if c.distance > lead_c.distance:
					c.at_front = true
				var top := companion_top_speed if c.at_front else maxf(companion_top_speed, lead_c.speed + 2.0)
				c.ride_towards(delta, minf(lead_c.distance + 4.5, limit), lead_c.speed, top)
				c.energy -= front_drain / c.stamina * pow(c.speed / 10.0, 2.0) * delta
				if c.energy <= exhausted_below:
					c.state = Companion.State.TIRED
					_net_companion_event.rpc(c.id, CompanionEvent.EXHAUSTED)
			Companion.State.GROUP:
				c.on_wheel = false
				var target := rear_c.distance - 2.5 - group_index * 2.2
				if c == victim:
					target = zombies.front_distance + 0.5  # dragged back into the horde
				c.ride_towards(delta, minf(target, limit - group_index * 2.2), rear_c.speed, 18.0)
				c.energy = minf(c.energy + group_recovery * clampf(1.6 - c.speed / 10.0, 0.2, 1.0) * delta, 1.0)
				group_index += 1
			Companion.State.TIRED:
				var wheel := _wheel_for(c)
				c.on_wheel = wheel != null
				if wheel:
					# Hang on about 3 m behind the rider and recover.
					var follow := clampf(wheel.speed + (wheel.distance - 3.0 - c.distance) * 0.8, 0.0, companion_top_speed)
					c.ride_at(delta, follow, 4.0)
					c.energy += wheel_recovery * delta
					if c.energy >= recovered_at:
						c.state = Companion.State.GROUP
						_net_companion_event.rpc(c.id, CompanionEvent.RECOVERED)
				else:
					c.ride_at(delta, exhausted_speed, exhausted_slowdown)
				if horde_active and c.distance <= zombies.front_distance + 0.5:
					lost.append(c.id)
		c.distance = minf(c.distance, limit)
	for id in lost:
		_net_companion_lost.rpc(id)


## A rider just in front of this companion, giving them a wheel to follow.
func _wheel_for(c: Companion) -> CyclistController:
	var best: CyclistController = null
	for r: CyclistController in cyclists.values():
		var gap := r.distance - c.distance
		if gap > 0.5 and gap < wheel_range and (best == null or r.distance < best.distance):
			best = r
	return best


@rpc("authority", "call_local", "reliable")
func _net_companion_event(id: int, event: CompanionEvent) -> void:
	var c := _companion(id)
	if c == null:
		return
	var who := c.companion_name.to_upper()
	match event:
		CompanionEvent.EXHAUSTED:
			c.state = Companion.State.TIRED
			print("[Endless] %s is exhausted" % c.companion_name)
			audio.play("heartbeat", 0.0, 0.8)
			announced.emit("%s IS EXHAUSTED" % who, "Drop back and give them your wheel!", 3.0)
		CompanionEvent.RECOVERED:
			c.state = Companion.State.GROUP
			print("[Endless] %s is back with the group" % c.companion_name)
			audio.play("countdown_beep", -2.0, 1.6)
			announced.emit("%s IS BACK" % who, "Thanks for the tow!", 2.0)


## The horde takes a companion.
@rpc("authority", "call_local", "reliable")
func _net_companion_lost(id: int) -> void:
	var c := _companion(id)
	if c == null:
		return
	companions.erase(c)
	c.fall()
	survivors_lost += 1
	print("[Endless] %s was taken by the horde" % c.companion_name)
	_assign_slots()
	audio.play("horde_roar", 2.0, 0.85)
	announced.emit("THEY GOT %s" % c.companion_name.to_upper(), "Don't look back - keep riding!", 3.0)


func _assign_slots() -> void:
	for i in companions.size():
		companions[i].slot = i
