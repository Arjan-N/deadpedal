class_name MissionAudio
extends Node
## All mission sound. Recordings come from res://audio/ via SoundBank (see
## audio/CREDITS.md); every sound id below is a file name there.
##
## Layers:
##  * Riding (local rider, kept light): tyres on asphalt and wind grow with
##    speed, a soft drivetrain hum follows cadence, and the freewheel ticks
##    when you coast.
##  * Threat: a horde ambience loop and heartbeat grow with danger; groans are
##    played in 3D at zombies in the horde, so you hear them behind you.
##  * One-shots: gate winch, gate opening, countdown, surge roar, success, failure.

@export var master_volume_db: float = 0.0
## Overall level of the riding sounds (tyres, drivetrain, freewheel).
@export var riding_volume_db: float = -6.0

var mission: MissionManager

var _loops: Dictionary = {}  # id -> AudioStreamPlayer
var _oneshots: Array[AudioStreamPlayer] = []
var _groan_players: Array[AudioStreamPlayer3D] = []
var _groan_timer: float = 2.0
var _heart_timer: float = 0.0
var _ratchet_timer: float = 0.0
var _warned: Dictionary = {}


func setup(p_mission: MissionManager) -> void:
	mission = p_mission
	for id in ["wind_loop", "tyre_loop", "drivetrain_loop", "freewheel_loop", "horde_loop", "ambience_loop"]:
		_loops[id] = _make_loop(id)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_oneshots.append(p)
	for i in 4:
		var p3 := AudioStreamPlayer3D.new()
		p3.unit_size = 6.0
		p3.max_distance = 90.0
		p3.attenuation_filter_cutoff_hz = 6000.0
		mission.add_child.call_deferred(p3)
		_groan_players.append(p3)


func _exit_tree() -> void:
	# Stop everything so no sound is still playing while the scene is freed.
	for p in get_children():
		(p as AudioStreamPlayer).stop()


## Call every frame. danger 0..1, gate_effort = team effort per second.
func update(delta: float, danger: float, gate_effort: float) -> void:
	var me := mission.local_cyclist
	var speed := me.speed if me else 0.0
	var cadence := me.cadence if me else 0.0
	var speed01 := clampf(speed / 16.0, 0.0, 1.0)
	var moving := speed > 0.4

	# Riding layer - deliberately light.
	_set_loop("wind_loop", lerpf(-34.0, -14.0, speed01), 0.85 + speed01 * 0.35, true)
	_set_loop("tyre_loop", riding_volume_db + lerpf(-30.0, -12.0, speed01), 0.75 + speed01 * 0.6, moving)
	var pedalling := cadence > 20.0
	_set_loop("drivetrain_loop", riding_volume_db + lerpf(-26.0, -14.0, clampf(me.effort if me else 0.0, 0.0, 1.0)),
		clampf(cadence / 90.0, 0.6, 1.4), pedalling and moving)
	_set_loop("freewheel_loop", riding_volume_db - 16.0, 0.7 + speed01 * 0.8, moving and not pedalling)

	# Threat layer.
	_set_loop("ambience_loop", -20.0, 1.0, true)
	_set_loop("horde_loop", lerpf(-30.0, -4.0, danger), 0.95 + danger * 0.1, danger > 0.01)

	if danger > 0.05:
		_groan_timer -= delta * (0.4 + danger * 2.5)
		if _groan_timer <= 0.0:
			_groan_timer = randf_range(1.2, 3.0)
			_play_groan(lerpf(-6.0, 4.0, danger))

	if danger > 0.45:
		_heart_timer -= delta
		if _heart_timer <= 0.0:
			_heart_timer = lerpf(1.0, 0.45, (danger - 0.45) / 0.55)
			play("heartbeat", lerpf(-14.0, 0.0, (danger - 0.45) / 0.55))

	if gate_effort > 0.02:
		_ratchet_timer -= delta * (2.0 + gate_effort * 10.0)
		if _ratchet_timer <= 0.0:
			_ratchet_timer = 1.0
			play("gate_ratchet", -8.0, randf_range(0.9, 1.1))


## Plays a one-shot (non-positional) sound by id.
func play(sound_id: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	var stream := _stream(sound_id)
	if stream == null:
		return
	for p in _oneshots:
		if not p.playing:
			p.stream = stream
			p.volume_db = master_volume_db + volume_db
			p.pitch_scale = pitch
			p.play()
			return


func _play_groan(volume_db: float) -> void:
	var stream := _stream("groan")
	if stream == null or mission.zombies.phase == ZombieDirector.Phase.DORMANT:
		return
	for p in _groan_players:
		if not p.playing:
			p.global_position = mission.zombies.random_horde_position() + Vector3.UP * 1.6
			p.stream = stream
			p.volume_db = master_volume_db + volume_db
			p.pitch_scale = randf_range(0.85, 1.15)
			p.play()
			return


func _set_loop(id: String, volume_db: float, pitch: float, active: bool) -> void:
	var p: AudioStreamPlayer = _loops.get(id)
	if p == null or p.stream == null:
		return
	# Fade rather than cut, so layers blend in and out smoothly.
	var target := master_volume_db + volume_db if active else -60.0
	p.volume_db = move_toward(p.volume_db, target, 60.0 * get_process_delta_time())
	p.pitch_scale = pitch
	if p.volume_db > -59.0 and not p.playing:
		p.play()
	elif p.volume_db <= -59.0 and p.playing:
		p.stop()


func _make_loop(id: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = _stream(id)
	p.volume_db = -60.0
	if p.stream:
		_enable_looping(p.stream)
	add_child(p)
	return p


func _stream(id: String) -> AudioStream:
	var stream := SoundBank.pick(id)
	if stream == null and not _warned.has(id):
		_warned[id] = true
		push_warning("MissionAudio: no recording found for sound '%s' in res://audio/" % id)
	return stream


static func _enable_looping(stream: AudioStream) -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	elif stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		if wav.loop_mode == AudioStreamWAV.LOOP_DISABLED:
			wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
			wav.loop_begin = 0
			wav.loop_end = wav.data.size() / (2 * (2 if wav.stereo else 1))
