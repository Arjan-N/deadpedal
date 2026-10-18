class_name ScriptedCyclingInput
extends CyclingInputSource
## Plays back a fixed power profile. Used by automated tests and the
## --autopilot command-line option. Demonstrates that the game runs from any
## CyclingInputSource without touching gameplay code.

## Power in watts used when no profile is given.
var constant_watts: float = 200.0
## Optional profile: Array of [time_seconds, watts] pairs, sorted by time.
## The latest entry whose time has passed is used.
var profile: Array = []

var _time: float = 0.0


func get_power_watts() -> float:
	var watts := constant_watts
	for entry: Array in profile:
		if _time >= float(entry[0]):
			watts = float(entry[1])
	return watts


func get_cadence_rpm() -> float:
	return 0.0 if get_power_watts() < 5.0 else 85.0


func is_input_valid() -> bool:
	return true


func get_source_type() -> SourceType:
	return SourceType.SCRIPTED


func get_source_name() -> String:
	return "SCRIPTED (autopilot)"


func reset() -> void:
	_time = 0.0


func _process(delta: float) -> void:
	_time += delta
