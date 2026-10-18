class_name SimulatedCyclingInput
extends CyclingInputSource
## DEVELOPMENT ONLY - simulates a rider with the keyboard.
##
## This is clearly labelled as simulated on the HUD and is never presented as
## real hardware data.
##
##   1-5          set a steady "cruise" effort (recovery .. all-out)
##   0 / `        stop pedalling (cruise = 0 W)
##   W / Up       hold to push harder; release and power falls back to cruise
##   Space        hold to sprint (fast ramp to maximum power)
##   S / Down     hold to stop pedalling immediately
##
## Presets are fractions of the rider's FTP so they scale with fitness.

## Cruise presets for keys 1-5, as a fraction of FTP.
@export var cruise_presets_ftp: PackedFloat32Array = PackedFloat32Array([0.45, 0.65, 0.85, 1.15, 1.6])
## Highest power reachable by holding W/Space, as a fraction of FTP.
@export var max_power_ftp: float = 2.0
## How fast power rises while W/Up is held (FTP fraction per second).
@export var push_rate_ftp: float = 0.9
## How fast power rises while Space is held (FTP fraction per second).
@export var sprint_rate_ftp: float = 4.0
## How fast power falls back towards cruise when keys are released.
@export var release_rate_ftp: float = 1.1
## How quickly power settles on a newly chosen cruise level.
@export var settle_rate_ftp: float = 1.5

## Set by CyclingInputManager.
var ftp_watts: float = 200.0

var cruise_level: int = 0  # 0 = not pedalling, 1..5 = presets
var _power: float = 0.0
var _cadence: float = 0.0
var _time: float = 0.0


func _ready() -> void:
	_ensure_actions()


func get_power_watts() -> float:
	# Small natural wobble so the number looks like a living rider. Clearly
	# simulated - this is not trainer data.
	if _power < 1.0:
		return 0.0
	return maxf(0.0, _power * (1.0 + 0.015 * sin(_time * 7.3) + 0.01 * sin(_time * 2.1)))


func get_cadence_rpm() -> float:
	return _cadence


func is_input_valid() -> bool:
	return true


func get_source_type() -> SourceType:
	return SourceType.SIMULATED


func get_source_name() -> String:
	return "SIMULATED (keyboard)"


func reset() -> void:
	cruise_level = 0
	_power = 0.0
	_cadence = 0.0


func get_cruise_watts() -> float:
	if cruise_level <= 0:
		return 0.0
	return cruise_presets_ftp[cruise_level - 1] * ftp_watts


func _unhandled_input(event: InputEvent) -> void:
	# Ignore keys while a text box (e.g. the name field in the menu) has focus.
	if get_viewport().gui_get_focus_owner() is LineEdit:
		return
	for i in range(6):
		if event.is_action_pressed("sim_cruise_%d" % i):
			cruise_level = i


func _process(delta: float) -> void:
	_time += delta
	var typing := get_viewport().gui_get_focus_owner() is LineEdit
	step(delta,
		not typing and Input.is_action_pressed("sim_push_harder"),
		not typing and Input.is_action_pressed("sim_sprint"),
		not typing and Input.is_action_pressed("sim_stop_pedalling"))


## Advances the simulation. Separated from _process so tests can drive it.
func step(delta: float, push: bool, sprint: bool, stop: bool) -> void:
	var cruise := get_cruise_watts()
	var max_power := max_power_ftp * ftp_watts
	if stop:
		_power = move_toward(_power, 0.0, release_rate_ftp * 3.0 * ftp_watts * delta)
	elif sprint:
		_power = move_toward(_power, max_power, sprint_rate_ftp * ftp_watts * delta)
	elif push:
		_power = move_toward(_power, max_power, push_rate_ftp * ftp_watts * delta)
	elif _power > cruise:
		_power = move_toward(_power, cruise, release_rate_ftp * ftp_watts * delta)
	else:
		_power = move_toward(_power, cruise, settle_rate_ftp * ftp_watts * delta)

	# Cadence follows power loosely: ~75 rpm easy, ~110 rpm sprinting.
	var target_cadence := 0.0
	if _power > 5.0:
		target_cadence = 72.0 + 38.0 * clampf(_power / max_power, 0.0, 1.0)
	_cadence = move_toward(_cadence, target_cadence, 60.0 * delta)


## Registers default key bindings unless they already exist in the project's
## Input Map (so you can rebind them in Project Settings > Input Map).
static func _ensure_actions() -> void:
	var bindings := {
		"sim_push_harder": [KEY_W, KEY_UP],
		"sim_sprint": [KEY_SPACE],
		"sim_stop_pedalling": [KEY_S, KEY_DOWN],
		"sim_cruise_0": [KEY_0, KEY_QUOTELEFT],
		"sim_cruise_1": [KEY_1],
		"sim_cruise_2": [KEY_2],
		"sim_cruise_3": [KEY_3],
		"sim_cruise_4": [KEY_4],
		"sim_cruise_5": [KEY_5],
	}
	for action: String in bindings:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action)
		for key: int in bindings[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key as Key
			InputMap.action_add_event(action, ev)
