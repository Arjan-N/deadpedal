class_name GateObjective
extends Node3D
## The locked quarantine gate: a shared team objective.
##
## Riders who have reached the gate pedal to drive a winch. Each rider adds
## their NORMALISED effort (0..1, relative to their own FTP) every second, and
## the team's combined total opens the gate. A strong rider can carry more of
## the load, but everyone's effort counts equally per unit of personal effort.
##
## The host does the counting (add_effort); everyone else just receives
## progress via MissionManager and animates the gate.

## Effort-seconds needed for a solo rider (effort 1.0 for 1 s = 1 point).
## e.g. 14 = 14 s all-out, or ~23 s at a steady 60% effort.
@export var effort_seconds_per_rider: float = 14.0
## How much each extra rider raises the target (0.75 = +75% per rider).
## Below 1.0 so teams finish faster than solo riders - teamwork pays.
@export var extra_rider_scaling: float = 0.75
## Riders within this distance of the gate can work the winch.
@export var work_range: float = 30.0
@export var gate_width: float = 10.6

signal opened

var progress: float = 0.0
var is_open: bool = false
## peer_id -> effort-seconds contributed (for the HUD and results).
var contributions: Dictionary = {}
## Team effort per second right now (drives the winch animation).
var team_effort_rate: float = 0.0
var distance_on_route: float = 0.0

var _doors: Array[Node3D] = []
var _winch: Node3D
var _lamps: Array[MeshInstance3D] = []
var _beacon: OmniLight3D
var _lamp_off: StandardMaterial3D
var _lamp_on: StandardMaterial3D
var _open_amount: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	_build()


func get_target(rider_count: int) -> float:
	return effort_seconds_per_rider * (1.0 + extra_rider_scaling * maxf(rider_count - 1, 0))


## Host only. `efforts` maps peer_id -> current effort for riders at the gate.
func add_effort(efforts: Dictionary, delta: float, rider_count: int) -> void:
	if is_open:
		return
	var target := get_target(rider_count)
	team_effort_rate = 0.0
	for peer_id: int in efforts:
		var e: float = efforts[peer_id]
		team_effort_rate += e
		contributions[peer_id] = contributions.get(peer_id, 0.0) + e * delta
	progress = clampf(progress + team_effort_rate * delta / target, 0.0, 1.0)


func open_gate() -> void:
	if is_open:
		return
	is_open = true
	progress = 1.0
	opened.emit()


func _process(delta: float) -> void:
	_time += delta
	# Doors rattle and creep open as progress builds, then swing wide.
	var target_open := 1.0 if is_open else progress * 0.08
	_open_amount = move_toward(_open_amount, target_open, delta * (0.7 if is_open else 0.2))
	var rattle := 0.0 if is_open else sin(_time * 40.0) * 0.012 * clampf(team_effort_rate, 0.0, 1.0)
	for i in _doors.size():
		var side := -1.0 if i == 0 else 1.0
		_doors[i].position.x = side * (gate_width * 0.25 + _open_amount * gate_width * 0.5) + rattle
	if _winch:
		_winch.rotation.x -= delta * (0.5 + team_effort_rate * 3.0) * (0.0 if is_open else 1.0)
	var lit := int(round(progress * _lamps.size()))
	for i in _lamps.size():
		_lamps[i].material_override = _lamp_on if i < lit else _lamp_off
	if _beacon:
		var pulse := 0.5 + 0.5 * sin(_time * 8.0)
		_beacon.light_color = Color(0.3, 1.0, 0.4) if is_open else Color(1.0, 0.55, 0.1)
		_beacon.light_energy = 3.0 if is_open else (1.0 + 3.0 * pulse * clampf(team_effort_rate + 0.2, 0.0, 1.0))


func _build() -> void:
	var steel := MeshKit.mat(Color(0.28, 0.29, 0.3), 0.5, 0.0, 0.7)
	var bars := MeshKit.mat(Color(0.4, 0.4, 0.4), 0.45, 0.0, 0.8)
	var hazard := MeshKit.mat(Color(0.8, 0.62, 0.08), 0.6)
	var half := gate_width * 0.5
	# Posts and top beam.
	for side: float in [-1.0, 1.0]:
		MeshKit.box(self, Vector3(0.6, 6.0, 0.6), Vector3(side * (half + 0.3), 3.0, 0), steel)
	MeshKit.box(self, Vector3(gate_width + 1.2, 0.7, 0.7), Vector3(0, 6.2, 0), steel)
	MeshKit.box(self, Vector3(gate_width + 1.2, 0.2, 0.72), Vector3(0, 5.95, 0), hazard)
	# Two sliding doors made of bars.
	for side: float in [-1.0, 1.0]:
		var door := Node3D.new()
		door.position = Vector3(side * gate_width * 0.25, 0, 0)
		add_child(door)
		var w := gate_width * 0.5
		MeshKit.box(door, Vector3(w, 0.15, 0.15), Vector3(0, 0.25, 0), steel)
		MeshKit.box(door, Vector3(w, 0.15, 0.15), Vector3(0, 4.6, 0), steel)
		MeshKit.box(door, Vector3(w, 0.4, 0.12), Vector3(0, 2.3, 0), hazard)
		var n := 12
		for i in n:
			MeshKit.box(door, Vector3(0.06, 4.4, 0.06), Vector3(-w * 0.5 + (i + 0.5) * w / n, 2.4, 0), bars)
		_doors.append(door)
	# Winch wheel on the right post: spins as the team pedals.
	_winch = Node3D.new()
	_winch.position = Vector3(half + 1.3, 1.6, 0.6)
	add_child(_winch)
	MeshKit.torus(_winch, 0.6, 0.8, Vector3.ZERO, hazard, Vector3(0, 0, 90))
	MeshKit.box(_winch, Vector3(0.1, 1.4, 0.12), Vector3.ZERO, steel)
	MeshKit.box(_winch, Vector3(0.1, 0.12, 1.4), Vector3.ZERO, steel)
	# Progress lamps along the beam (light up green as the team pedals).
	_lamp_off = MeshKit.mat(Color(0.15, 0.05, 0.03), 0.4, 0.3)
	_lamp_on = MeshKit.mat(Color(0.3, 1.0, 0.35), 0.3, 3.0)
	var count := 10
	for i in count:
		var lamp := MeshKit.box(self, Vector3(0.6, 0.35, 0.1), Vector3(-gate_width * 0.45 + i * gate_width * 0.9 / (count - 1), 6.25, 0.38), _lamp_off)
		_lamps.append(lamp)
	# Warning beacon.
	MeshKit.sphere(self, 0.3, Vector3(half + 0.3, 6.4, 0), MeshKit.mat(Color(1.0, 0.6, 0.1), 0.3, 2.0))
	_beacon = OmniLight3D.new()
	_beacon.position = Vector3(half + 0.3, 6.6, 1.0)
	_beacon.omni_range = 18.0
	add_child(_beacon)
