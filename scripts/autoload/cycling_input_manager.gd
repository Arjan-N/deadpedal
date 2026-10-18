extends Node
## Autoload "CyclingInputManager".
##
## The single place gameplay code reads the local rider's effort from.
## Owns the active CyclingInputSource and the rider's profile (name, FTP).

signal source_changed(source: CyclingInputSource)

const SETTINGS_PATH := "user://rider_settings.cfg"

## Effort reaches 1.0 at this multiple of FTP (an all-out effort).
## Using FTP-relative effort means riders of different fitness get the same
## in-game speed for the same *relative* effort.
@export var full_effort_ftp_ratio: float = 1.6

enum InputMode { KEYBOARD, TRAINER }

var rider_name: String = "Rider"
## Which input to use; saved with the rider settings.
var input_mode: InputMode = InputMode.KEYBOARD
var rider_ftp_watts: float = 200.0:
	set(value):
		rider_ftp_watts = clampf(value, 50.0, 600.0)
		_apply_ftp()

var source: CyclingInputSource


func _ready() -> void:
	_load_settings()
	set_input_mode(input_mode)


## Switches between the keyboard simulation and a real smart trainer
## (via the trainer bridge, see tools/trainer_bridge).
func set_input_mode(mode: InputMode) -> void:
	input_mode = mode
	if mode == InputMode.TRAINER:
		set_source(TrainerBridgeInput.new())
	else:
		set_source(SimulatedCyclingInput.new())


## Replaces the active input source (e.g. simulated -> smart trainer).
func set_source(new_source: CyclingInputSource) -> void:
	if source:
		# Free immediately (not queue_free) so a trainer source releases its
		# network port before a new one tries to open it.
		remove_child(source)
		source.free()
	source = new_source
	source.name = "ActiveSource"
	add_child(source)
	_apply_ftp()
	source_changed.emit(source)


func get_power_watts() -> float:
	return source.get_power_watts() if source else 0.0


func get_effort() -> float:
	return source.get_effort() if source else 0.0


func get_cadence_rpm() -> float:
	return source.get_cadence_rpm() if source else -1.0


func has_cadence() -> bool:
	return source != null and source.has_cadence()


func is_input_valid() -> bool:
	return source != null and source.is_input_valid()


func get_source_name() -> String:
	return source.get_source_name() if source else "NONE"


func get_source_type() -> CyclingInputSource.SourceType:
	return source.get_source_type() if source else CyclingInputSource.SourceType.SIMULATED


func reset() -> void:
	if source:
		source.reset()


func save_settings() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("rider", "name", rider_name)
	cfg.set_value("rider", "ftp_watts", rider_ftp_watts)
	cfg.set_value("rider", "input_mode", input_mode)
	cfg.save(SETTINGS_PATH)


func _load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		rider_name = str(cfg.get_value("rider", "name", rider_name))
		rider_ftp_watts = float(cfg.get_value("rider", "ftp_watts", rider_ftp_watts))
		input_mode = int(cfg.get_value("rider", "input_mode", input_mode)) as InputMode


func _apply_ftp() -> void:
	if source == null:
		return
	source.full_effort_watts = rider_ftp_watts * full_effort_ftp_ratio
	if source is SimulatedCyclingInput:
		(source as SimulatedCyclingInput).ftp_watts = rider_ftp_watts
