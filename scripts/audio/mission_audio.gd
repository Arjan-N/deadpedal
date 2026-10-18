class_name MissionAudio
extends Node
## Plays the mission's procedural sound: wind that grows with speed, a horde
## drone + groans + heartbeat that grow with danger, and one-shot cues.

@export var master_volume_db: float = 0.0

var _wind: AudioStreamPlayer
var _horde: AudioStreamPlayer
var _heart: AudioStreamPlayer
var _oneshots: Array[AudioStreamPlayer] = []
var _groan_timer: float = 2.0
var _heart_timer: float = 0.0
var _ratchet_timer: float = 0.0


func _ready() -> void:
	_wind = _make_player("wind", -40.0)
	_horde = _make_player("horde", -60.0)
	_heart = _make_player("heartbeat", -6.0)
	for i in 6:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_oneshots.append(p)
	_wind.play()
	_horde.play()


func _exit_tree() -> void:
	# Stop everything so no sound is still playing while the scene is freed.
	for p in get_children():
		(p as AudioStreamPlayer).stop()


## Call every frame. danger 0..1, speed in m/s, gate_effort = team effort/s.
func update(delta: float, danger: float, speed: float, gate_effort: float) -> void:
	_wind.volume_db = master_volume_db + lerpf(-30.0, -10.0, clampf(speed / 16.0, 0.0, 1.0))
	_wind.pitch_scale = 0.8 + clampf(speed / 16.0, 0.0, 1.0) * 0.5
	_horde.volume_db = master_volume_db + (-60.0 if danger <= 0.01 else lerpf(-26.0, -2.0, danger))
	_horde.pitch_scale = 0.9 + danger * 0.25

	# Random groans, more frequent and louder as danger rises.
	if danger > 0.05:
		_groan_timer -= delta * (0.4 + danger * 2.5)
		if _groan_timer <= 0.0:
			_groan_timer = randf_range(1.5, 3.5)
			var which: String = ["groan_a", "groan_b", "groan_c"][randi() % 3]
			play(which, lerpf(-18.0, 0.0, danger), randf_range(0.85, 1.15))

	# Heartbeat when zombies are close; it speeds up with danger.
	if danger > 0.45:
		_heart_timer -= delta
		if _heart_timer <= 0.0:
			_heart_timer = lerpf(1.0, 0.45, (danger - 0.45) / 0.55)
			_heart.volume_db = master_volume_db + lerpf(-12.0, 2.0, (danger - 0.45) / 0.55)
			_heart.play()

	# Winch ratchet clicks while the team works the gate.
	if gate_effort > 0.02:
		_ratchet_timer -= delta * (2.0 + gate_effort * 10.0)
		if _ratchet_timer <= 0.0:
			_ratchet_timer = 1.0
			play("ratchet", -8.0, randf_range(0.9, 1.1))


func play(sound_name: String, volume_db: float = 0.0, pitch: float = 1.0) -> void:
	for p in _oneshots:
		if not p.playing:
			p.stream = SfxSynth.get_sound(sound_name)
			p.volume_db = master_volume_db + volume_db
			p.pitch_scale = pitch
			p.play()
			return


func _make_player(sound_name: String, volume: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = SfxSynth.get_sound(sound_name)
	p.volume_db = volume
	add_child(p)
	return p
