class_name AudioLibrary
extends RefCounted
## Procedural placeholder audio. Short cues and loops are synthesised once and
## cached, so the project has no binary audio dependency for its core mix.
##
## Announcer lines use generated Windows SAPI WAVs when they are present and
## fall back to formant-style placeholder tones on other platforms. Music loops
## are mono 22.05 kHz (replace with OGG in a shipping build if desired).

const SAMPLE_RATE := 22050
const IDS: Array[String] = [
	"engine_loop",
	"ball_light",
	"ball_medium",
	"ball_heavy",
	"shift_warning",
	"shift_whoosh",
	"crowd_loop",
	"crowd_cheer",
	"music_calm",
	"music_tense",
	"music_overtime",
	"ui_click",
	"ui_hover",
	"ui_back",
	"countdown",
	"announcer_goal",
	"announcer_overtime",
	"announcer_demolition",
	"announcer_nice_shot",
	"announcer_what_a_save",
	"announcer_gravity_shift",
]

const ANNOUNCER_FILES := {
	"announcer_goal": "res://audio/announcer/goal.wav",
	"announcer_overtime": "res://audio/announcer/overtime.wav",
	"announcer_demolition": "res://audio/announcer/demolition.wav",
	"announcer_nice_shot": "res://audio/announcer/nice_shot.wav",
	"announcer_what_a_save": "res://audio/announcer/what_a_save.wav",
	"announcer_gravity_shift": "res://audio/announcer/gravity_shift.wav",
}

static var _cache: Dictionary = {}


static func get_stream(id: String) -> AudioStream:
	if _cache.has(id):
		return _cache[id] as AudioStream
	var stream: AudioStream = null
	if ANNOUNCER_FILES.has(id):
		var path := str(ANNOUNCER_FILES[id])
		if ResourceLoader.exists(path):
			stream = load(path) as AudioStream
	if stream == null:
		stream = _build_stream(id)
	_cache[id] = stream
	return stream


static func preload_all() -> void:
	for id: String in IDS:
		get_stream(id)


static func announcer_line_for(event: String) -> String:
	match event:
		"goal":
			return "GOAL!"
		"overtime":
			return "Overtime! Next goal wins!"
		"demolition":
			return "Demolition!"
		"nice_shot":
			return "Nice shot!"
		"what_a_save":
			return "What a save!"
		"gravity_shift":
			return "Gravity shift!"
		"countdown":
			return "Three. Two. One. Go!"
	return ""


static func _build_stream(id: String) -> AudioStream:
	match id:
		"engine_loop":
			return _wav(_engine(), true)
		"ball_light":
			return _wav(_impact(0.13, 900.0, 0.38, 0.55, 34.0, 11), false)
		"ball_medium":
			return _wav(_impact(0.22, 520.0, 0.55, 0.45, 23.0, 23), false)
		"ball_heavy":
			return _wav(_impact(0.34, 250.0, 0.72, 0.42, 14.0, 47), false)
		"shift_warning":
			return _wav(_warning_rise(), false)
		"shift_whoosh":
			return _wav(_whoosh(), false)
		"crowd_loop":
			return _wav(_crowd_loop(), true)
		"crowd_cheer":
			return _wav(_crowd_cheer(), false)
		"music_calm":
			return _wav(_music_calm(), true)
		"music_tense":
			return _wav(_music_tense(), true)
		"music_overtime":
			return _wav(_music_overtime(), true)
		"ui_click":
			return _wav(_ui_tone(740.0, 0.055, 0.35, 3), false)
		"ui_hover":
			return _wav(_ui_tone(1080.0, 0.035, 0.18, 2), false)
		"ui_back":
			return _wav(_ui_tone(380.0, 0.075, 0.28, 4), false)
		"countdown":
			return _wav(_announcer_fallback(3, 240.0), false)
		"announcer_goal":
			return _wav(_announcer_fallback(2, 220.0), false)
		"announcer_overtime":
			return _wav(_announcer_fallback(4, 190.0), false)
		"announcer_demolition":
			return _wav(_announcer_fallback(3, 130.0), false)
		"announcer_nice_shot":
			return _wav(_announcer_fallback(2, 320.0), false)
		"announcer_what_a_save":
			return _wav(_announcer_fallback(3, 280.0), false)
		"announcer_gravity_shift":
			return _wav(_announcer_fallback(3, 170.0), false)
	return _wav(_ui_tone(440.0, 0.04, 0.2, 1), false)


# --- synthesis primitives ----------------------------------------------------

static func _samples(duration: float) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(maxi(int(duration * SAMPLE_RATE), 1))
	return out


static func _engine() -> PackedFloat32Array:
	var out := _samples(1.0)
	var n := out.size()
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		var v := sin(TAU * 55.0 * t) * 0.42
		v += sin(TAU * 110.0 * t) * 0.20
		v += sin(TAU * 165.0 * t) * 0.10
		v += sin(TAU * 220.0 * t) * 0.045
		out[i] = _soft_clip(v * 0.72)
	return out


static func _impact(duration: float, freq: float, noise_mix: float, tone_mix: float, decay: float, seed_value: int) -> PackedFloat32Array:
	var out := _samples(duration)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var low := 0.0
	for i in out.size():
		var t := float(i) / float(SAMPLE_RATE)
		var attack: float = minf(t / 0.004, 1.0)
		var env: float = attack * exp(-t * decay)
		var noise: float = rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.22
		var body: float = sin(TAU * freq * t + sin(TAU * freq * 0.43 * t) * 0.6)
		var sub: float = sin(TAU * (freq * 0.32) * t) * 0.28
		out[i] = _soft_clip((low * noise_mix + body * tone_mix + sub) * env * 0.92)
	return out


static func _warning_rise() -> PackedFloat32Array:
	var out := _samples(4.0)
	var n := out.size()
	for i in n:
		var t := float(i) / float(SAMPLE_RATE)
		var p := clampf(t / 4.0, 0.0, 1.0)
		var freq: float = lerpf(180.0, 1100.0, p * p)
		var env: float = smoothstep(0.0, 0.18, t) * (1.0 - smoothstep(0.82, 1.0, p))
		var vibrato: float = sin(TAU * 7.0 * t) * 0.012
		var body: float = sin(TAU * freq * (t + vibrato))
		body += sin(TAU * freq * 2.0 * t) * 0.22
		out[i] = _soft_clip(body * env * 0.38)
	return out


static func _whoosh() -> PackedFloat32Array:
	var out := _samples(0.95)
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	var low := 0.0
	var high := 0.0
	for i in out.size():
		var t := float(i) / float(SAMPLE_RATE)
		var p := clampf(t / 0.95, 0.0, 1.0)
		var env: float = pow(sin(p * PI), 1.6)
		var noise: float = rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.08
		high += (noise - high) * 0.55
		var sweep: float = sin(TAU * lerpf(90.0, 420.0, p) * t)
		out[i] = _soft_clip((low * 0.8 + high * 0.25 + sweep * 0.12) * env * 0.62)
	return out


static func _crowd_loop() -> PackedFloat32Array:
	var out := _samples(4.0)
	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	var low := 0.0
	var low2 := 0.0
	for i in out.size():
		var t := float(i) / float(SAMPLE_RATE)
		var noise: float = rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.05
		low2 += (low - low2) * 0.08
		var swell: float = 0.62 + 0.18 * sin(TAU * 0.25 * t) + 0.10 * sin(TAU * 0.75 * t + 1.2)
		var voices: float = sin(TAU * 136.0 * t) * 0.02 + sin(TAU * 187.0 * t + 0.7) * 0.015
		out[i] = _soft_clip((low2 * 0.7 + voices) * swell * 0.42)
	_force_loop_boundary(out, 0.12)
	return out


static func _crowd_cheer() -> PackedFloat32Array:
	var out := _samples(1.45)
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	var low := 0.0
	for i in out.size():
		var t := float(i) / float(SAMPLE_RATE)
		var env: float = smoothstep(0.0, 0.05, t) * (1.0 - smoothstep(0.65, 1.45, t))
		var noise: float = rng.randf_range(-1.0, 1.0)
		low += (noise - low) * 0.06
		var roar: float = low * 0.55 + sin(TAU * 170.0 * t) * 0.12
		out[i] = _soft_clip(roar * env * 0.78)
	return out


static func _music_calm() -> PackedFloat32Array:
	var out := _samples(4.0)
	var chords := [
		[48, 55, 60, 64],
		[45, 52, 57, 60],
		[41, 48, 53, 57],
		[43, 50, 55, 59],
	]
	for i in chords.size():
		for note: int in chords[i]:
			_add_note(out, float(i), 0.95, _midi(note), 0.075, 0.10, 0.55, 1)
			_add_note(out, float(i), 0.95, _midi(note + 12), 0.025, 0.18, 0.55, 2)
	return out


static func _music_tense() -> PackedFloat32Array:
	var out := _samples(4.0)
	var bass := [45, 45, 41, 43]
	for i in 4:
		for beat in 4:
			var start: float = float(i) + float(beat) * 0.25
			_add_note(out, start, 0.20, _midi(bass[i]), 0.12, 0.01, 0.12, 2)
		_add_note(out, float(i), 0.95, _midi(bass[i] + 12), 0.055, 0.08, 0.4, 1)
		_add_note(out, float(i) + 0.5, 0.42, _midi(bass[i] + 19), 0.040, 0.02, 0.22, 2)
		_add_note(out, float(i), 0.10, 62.0, 0.10, 0.005, 0.08, 3)
	return out


static func _music_overtime() -> PackedFloat32Array:
	var out := _samples(2.0)
	var notes := [45, 48, 52, 55, 52, 48, 45, 43]
	for i in notes.size():
		var start: float = float(i) * 0.25
		_add_note(out, start, 0.20, _midi(notes[i]), 0.10, 0.005, 0.10, 2)
		_add_note(out, start, 0.18, _midi(notes[i] + 12), 0.055, 0.005, 0.08, 1)
		_add_note(out, start, 0.09, 58.0, 0.12, 0.004, 0.06, 3)
	_add_note(out, 1.0, 0.8, _midi(57), 0.06, 0.02, 0.5, 2)
	return out


static func _announcer_fallback(syllables: int, base_freq: float) -> PackedFloat32Array:
	var duration: float = 0.18 * float(syllables) + 0.12
	var out := _samples(duration)
	for s in syllables:
		var start: float = float(s) * 0.18
		var freq: float = base_freq * (1.0 + 0.16 * float(s))
		var count: int = int(0.16 * SAMPLE_RATE)
		for i in count:
			var t: float = float(i) / float(SAMPLE_RATE)
			var global_t: float = start + t
			var env: float = smoothstep(0.0, 0.02, t) * (1.0 - smoothstep(0.10, 0.16, t))
			var formant: float = sin(TAU * freq * global_t) * 0.38
			formant += sin(TAU * freq * 2.0 * global_t) * 0.20
			formant += sin(TAU * freq * 3.0 * global_t) * 0.10
			var index: int = int(global_t * SAMPLE_RATE)
			if index >= 0 and index < out.size():
				out[index] = _soft_clip(out[index] + formant * env)
	return out


static func _ui_tone(freq: float, duration: float, volume: float, harmonic: int) -> PackedFloat32Array:
	var out := _samples(duration)
	for i in out.size():
		var t := float(i) / float(SAMPLE_RATE)
		var env: float = minf(t / 0.003, 1.0) * (1.0 - t / duration)
		var v: float = sin(TAU * freq * t) * 0.65 + sin(TAU * freq * float(harmonic) * t) * 0.18
		out[i] = _soft_clip(v * env * volume)
	return out


static func _add_note(
		out: PackedFloat32Array,
		start: float,
		duration: float,
		freq: float,
		volume: float,
		attack: float,
		release: float,
		shape: int
) -> void:
	var begin: int = maxi(int(start * SAMPLE_RATE), 0)
	var count: int = maxi(int(duration * SAMPLE_RATE), 1)
	for i in count:
		var index: int = begin + i
		if index >= out.size():
			break
		var t: float = float(i) / float(SAMPLE_RATE)
		var env: float = smoothstep(0.0, maxf(attack, 0.001), t) * (1.0 - smoothstep(maxf(duration - release, 0.0), duration, t))
		var phase := TAU * freq * t
		var v: float = sin(phase)
		if shape == 2:
			v = 0.65 * sin(phase) + 0.25 * sin(phase * 2.0) + 0.10 * sin(phase * 3.0)
		elif shape == 3:
			v = sin(phase) * sin(phase * 0.5)
		out[index] = _soft_clip(out[index] + v * env * volume)


static func _force_loop_boundary(out: PackedFloat32Array, seconds: float) -> void:
	var fade: int = maxi(int(seconds * SAMPLE_RATE), 1)
	var n := out.size()
	for i in fade:
		var w: float = float(i) / float(fade)
		var tail: float = out[n - fade + i]
		out[i] = lerpf(out[i], tail, 1.0 - w) * smoothstep(0.0, 1.0, w)
		out[n - 1 - i] = lerpf(out[n - 1 - i], out[fade - 1 - i], 1.0 - w) * smoothstep(0.0, 1.0, w)


static func _midi(note: int) -> float:
	return 440.0 * pow(2.0, float(note - 69) / 12.0)


static func _soft_clip(value: float) -> float:
	return tanh(value * 1.15) * 0.92


static func _wav(samples: PackedFloat32Array, loop: bool) -> AudioStreamWAV:
	var data_size: int = samples.size() * 2
	var bytes := PackedByteArray()
	bytes.resize(44 + data_size)
	_write_ascii(bytes, 0, "RIFF")
	bytes.encode_u32(4, 36 + data_size)
	_write_ascii(bytes, 8, "WAVE")
	_write_ascii(bytes, 12, "fmt ")
	bytes.encode_u32(16, 16)
	bytes.encode_u16(20, 1)
	bytes.encode_u16(22, 1)
	bytes.encode_u32(24, SAMPLE_RATE)
	bytes.encode_u32(28, SAMPLE_RATE * 2)
	bytes.encode_u16(32, 2)
	bytes.encode_u16(34, 16)
	_write_ascii(bytes, 36, "data")
	bytes.encode_u32(40, data_size)
	for i in samples.size():
		var v: int = int(round(clampf(samples[i], -1.0, 1.0) * 32767.0))
		bytes.encode_s16(44 + i * 2, v)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = bytes
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = samples.size()
	return stream


static func _write_ascii(bytes: PackedByteArray, offset: int, text: String) -> void:
	for i in text.length():
		bytes[offset + i] = text.unicode_at(i)
