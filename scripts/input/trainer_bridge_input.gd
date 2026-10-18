class_name TrainerBridgeInput
extends CyclingInputSource
## Real smart-trainer input (e.g. Zwift Hub One), received from the DEAD PEDAL
## trainer bridge (tools/trainer_bridge). The bridge talks Bluetooth to the
## trainer and sends small JSON packets to this computer over UDP:
##   {"power": 212.0, "cadence": 88.0, "device": "Zwift Hub", "simulated": false}
## Godot has no built-in Bluetooth, which is why the bridge exists.

const PORT := 47800
## Data older than this counts as "no signal".
const TIMEOUT_SECONDS := 2.0

var _udp := PacketPeerUDP.new()
var _power: float = 0.0
var _cadence: float = -1.0
var _device: String = ""
var _simulated: bool = false
var _last_packet_time: float = -INF
var _bound := false


func _ready() -> void:
	# Only accept packets from this computer.
	_bound = _udp.bind(PORT, "127.0.0.1") == OK
	if not _bound:
		push_warning("TrainerBridgeInput: could not listen on UDP port %d (is the game running twice?)" % PORT)


func _exit_tree() -> void:
	_udp.close()


func _process(_delta: float) -> void:
	while _udp.get_available_packet_count() > 0:
		var data: Variant = JSON.parse_string(_udp.get_packet().get_string_from_utf8())
		if data is Dictionary:
			_power = maxf(float(data.get("power", 0.0)), 0.0)
			_cadence = float(data.get("cadence", -1.0))
			_device = str(data.get("device", "trainer"))
			_simulated = bool(data.get("simulated", false))
			_last_packet_time = Time.get_ticks_msec() / 1000.0


func get_power_watts() -> float:
	return _power if is_input_valid() else 0.0


func get_cadence_rpm() -> float:
	return _cadence if is_input_valid() else -1.0


func is_input_valid() -> bool:
	return Time.get_ticks_msec() / 1000.0 - _last_packet_time < TIMEOUT_SECONDS


func get_source_type() -> SourceType:
	# The bridge's --simulate test mode is reported honestly as simulated.
	return SourceType.SIMULATED if _simulated else SourceType.SMART_TRAINER


func get_source_name() -> String:
	if not _bound:
		return "SMART TRAINER - port %d busy" % PORT
	if not is_input_valid():
		return "SMART TRAINER - no signal (is the bridge running?)"
	if _simulated:
		return "SIMULATED (bridge test mode)"
	return "SMART TRAINER (%s)" % _device


## Is the bridge listening port open? (false if another copy of the game has it)
func is_listening() -> bool:
	return _bound
