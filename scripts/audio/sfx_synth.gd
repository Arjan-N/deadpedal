class_name SfxSynth
extends RefCounted
## Generates placeholder sound effects procedurally (no audio files needed).
## Each sound is synthesised once and cached. Replace any of these with a real
## recording later by loading an AudioStream instead.

const RATE := 22050

static var _cache: Dictionary = {}


static func clear_cache() -> void:
	_cache.clear()


static func get_sound(sound_name: String) -> AudioStreamWAV:
	if _cache.has(sound_name):
		return _cache[sound_name]
	var s: AudioStreamWAV
	match sound_name:
		"wind": s = _wind()
		"horde": s = _horde_drone()
		"groan_a": s = _groan(1, 150.0, 85.0)
		"groan_b": s = _groan(2, 120.0, 70.0)
		"groan_c": s = _groan(3, 180.0, 100.0)
		"heartbeat": s = _heartbeat()
		"ratchet": s = _ratchet()
		"gate_open": s = _gate_open()
		"success": s = _arpeggio([523.25, 659.25, 783.99, 1046.5], false)
		"failure": s = _arpeggio([392.0, 311.13, 261.63, 196.0], true)
		"beep": s = _beep(660.0, 0.15)
		"beep_go": s = _beep(1320.0, 0.4)
		"alarm": s = _alarm()
		_:
			push_warning("Unknown sound: %s" % sound_name)
			s = _beep(440.0, 0.1)
	_cache[sound_name] = s
	return s


static func _to_wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in samples.size():
		bytes.encode_s16(i * 2, int(clampf(samples[i], -1.0, 1.0) * 32000.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = RATE
	wav.stereo = false
	wav.data = bytes
	if loop:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		wav.loop_end = samples.size()
	return wav


## Fades the ends of a loop together so it repeats without a click.
static func _crossfade_loop(s: PackedFloat32Array, fade: int) -> PackedFloat32Array:
	var n := s.size()
	var out := PackedFloat32Array()
	out.resize(n - fade)
	for i in n - fade:
		out[i] = s[i]
	for i in fade:
		var t := float(i) / fade
		out[i] = s[i] * t + s[n - fade + i] * (1.0 - t)
	return out


static func _wind() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var n := RATE * 4
	var s := PackedFloat32Array()
	s.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	for i in n:
		var t := float(i) / RATE
		var gust := 0.6 + 0.4 * sin(t * TAU * 0.25) * sin(t * TAU * 0.11 + 1.0)
		lp += (rng.randf_range(-1, 1) - lp) * 0.05
		lp2 += (lp - lp2) * 0.1
		s[i] = lp2 * 2.2 * gust
	return _to_wav(_crossfade_loop(s, RATE / 2), true)


static func _horde_drone() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 13
	var n := RATE * 4
	var s := PackedFloat32Array()
	s.resize(n)
	var freqs := [55.0, 61.0, 73.0, 82.0, 97.0]
	var phases := [0.0, 0.0, 0.0, 0.0, 0.0]
	var lp := 0.0
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in freqs.size():
			var f: float = freqs[k] * (1.0 + 0.03 * sin(t * (0.7 + k * 0.3) + k))
			phases[k] = fmod(phases[k] + f / RATE, 1.0)
			# Sawtooth with a slow per-voice swell.
			v += (phases[k] * 2.0 - 1.0) * (0.5 + 0.5 * sin(t * TAU * (0.2 + k * 0.07) + k * 2.0))
		lp += (rng.randf_range(-1, 1) * 0.6 + v * 0.25 - lp) * 0.08
		s[i] = lp * 1.4
	return _to_wav(_crossfade_loop(s, RATE / 2), true)


static func _groan(seed_value: int, f_start: float, f_end: float) -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var dur := 1.3
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	var lp := 0.0
	for i in n:
		var t := float(i) / n
		var f := lerpf(f_start, f_end, t) * (1.0 + 0.06 * sin(t * 40.0))
		phase = fmod(phase + f / RATE, 1.0)
		var raw := (phase * 2.0 - 1.0) + rng.randf_range(-0.4, 0.4)
		lp += (raw - lp) * 0.12
		var env := sin(t * PI) * (0.7 + 0.3 * sin(t * 23.0))
		s[i] = lp * env * 0.9
	return _to_wav(s, false)


static func _heartbeat() -> AudioStreamWAV:
	var n := int(RATE * 0.75)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for beat_t: float in [0.0, 0.22]:
			var bt: float = t - beat_t
			if bt >= 0.0:
				v += sin(bt * TAU * 52.0) * exp(-bt * 18.0)
		s[i] = v * 0.9
	return _to_wav(s, false)


static func _ratchet() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var n := int(RATE * 0.07)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = (rng.randf_range(-1, 1) * 0.5 + sin(t * TAU * 1800.0) * 0.5) * exp(-t * 70.0)
	return _to_wav(s, false)


static func _gate_open() -> AudioStreamWAV:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var n := int(RATE * 2.2)
	var s := PackedFloat32Array()
	s.resize(n)
	var partials := [[180.0, 1.0], [287.0, 0.7], [463.0, 0.5], [721.0, 0.35], [1093.0, 0.2]]
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for p: Array in partials:
			v += sin(t * TAU * p[0]) * p[1] * exp(-t * (2.0 + p[0] / 400.0))
		v += rng.randf_range(-1, 1) * exp(-t * 25.0) * 0.6
		v += sin(t * TAU * 50.0) * exp(-t * 5.0) * 0.6
		s[i] = v * 0.4
	return _to_wav(s, false)


static func _arpeggio(notes: Array, sad: bool) -> AudioStreamWAV:
	var note_len := 0.22 if not sad else 0.32
	var n := int(RATE * (note_len * notes.size() + 0.8))
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		var v := 0.0
		for k in notes.size():
			var nt: float = t - k * note_len
			if nt < 0.0:
				continue
			var f: float = notes[k]
			var tri := absf(fmod(nt * f, 1.0) * 4.0 - 2.0) - 1.0
			var saw := fmod(nt * f, 1.0) * 2.0 - 1.0
			v += (saw * 0.5 if sad else tri) * exp(-nt * (3.0 if k == notes.size() - 1 else 6.0))
		s[i] = v * 0.35
	return _to_wav(s, false)


static func _beep(freq: float, dur: float) -> AudioStreamWAV:
	var n := int(RATE * dur)
	var s := PackedFloat32Array()
	s.resize(n)
	for i in n:
		var t := float(i) / RATE
		s[i] = sin(t * TAU * freq) * minf(1.0, (dur - t) * 30.0) * minf(1.0, t * 200.0) * 0.5
	return _to_wav(s, false)


static func _alarm() -> AudioStreamWAV:
	var n := int(RATE * 1.2)
	var s := PackedFloat32Array()
	s.resize(n)
	var phase := 0.0
	for i in n:
		var t := float(i) / RATE
		var f := 520.0 + 260.0 * (0.5 + 0.5 * sin(t * TAU * 2.5))
		phase = fmod(phase + f / RATE, 1.0)
		s[i] = (phase * 2.0 - 1.0) * 0.25 * minf(1.0, (1.2 - t) * 5.0)
	return _to_wav(s, false)
