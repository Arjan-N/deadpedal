class_name CyclingInputSource
extends Node
## Base class for anything that can drive a cyclist.
##
## Gameplay code never reads the keyboard or a trainer directly. It asks the
## CyclingInputManager autoload, which forwards to whichever CyclingInputSource
## is active. To add a real smart trainer later, create a new subclass (e.g.
## FTMSTrainerInput) that overrides the methods below, and pass it to
## CyclingInputManager.set_source(). Movement, zombies and missions will not
## need to change.

enum SourceType { SIMULATED, SCRIPTED, SMART_TRAINER }

## Power (watts) at which normalised effort reaches 1.0.
## Set by CyclingInputManager from the rider's FTP so that effort is relative
## to each rider's own fitness, not absolute watts.
var full_effort_watts: float = 320.0


## Current power output in watts.
func get_power_watts() -> float:
	return 0.0


## Cadence in RPM, or -1.0 if this source cannot measure cadence.
func get_cadence_rpm() -> float:
	return -1.0


## Current virtual gear (1..get_gear_count()), or 0 if this source has no
## gears (e.g. no Zwift Click connected). Gears change how the trainer feels,
## not the in-game speed - power still decides that.
func get_gear() -> int:
	return 0


func get_gear_count() -> int:
	return 0


func has_cadence() -> bool:
	return get_cadence_rpm() >= 0.0


## False when the source is disconnected or has no fresh data.
func is_input_valid() -> bool:
	return false


func get_source_type() -> SourceType:
	return SourceType.SIMULATED


## Human-readable name shown on the HUD, e.g. "SIMULATED (keyboard)".
func get_source_name() -> String:
	return "NONE"


## Normalised effort 0.0 - 1.0 relative to this rider's full effort power.
func get_effort() -> float:
	if not is_input_valid() or full_effort_watts <= 0.0:
		return 0.0
	return clampf(get_power_watts() / full_effort_watts, 0.0, 1.0)


## Called at the start of every mission so stale values don't carry over.
func reset() -> void:
	pass
