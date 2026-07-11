class_name PixiballAudioDirector
extends Node

var _streams: Dictionary = {}
var _players: Array[AudioStreamPlayer] = []
var _cursor := 0
var muted := false


func _ready() -> void:
	for i in range(10):
		var player := AudioStreamPlayer.new()
		player.name = "Voice%02d" % i
		add_child(player)
		_players.append(player)
	_build_streams()


func _exit_tree() -> void:
	for player in _players:
		player.stop()
		player.stream = null
	_streams.clear()
	_players.clear()


func play_event(event: String, volume_db := 0.0, pitch := 1.0) -> void:
	if muted:
		return
	if not _streams.has(event):
		return
	var player := _players[_cursor % _players.size()]
	_cursor += 1
	player.stop()
	player.stream = _streams[event]
	player.volume_db = volume_db
	player.pitch_scale = pitch
	player.play()


func _build_streams() -> void:
	_streams["pitch"] = _tone(0.12, 190.0, 640.0, 0.2, 1)
	_streams["glove"] = _tone(0.16, 92.0, 58.0, 0.56, 2)
	_streams["bat"] = _tone(0.24, 420.0, 105.0, 0.62, 3)
	_streams["strike"] = _chord([330.0, 440.0], 0.25, 0.28)
	_streams["ball"] = _chord([220.0, 277.0], 0.2, 0.22)
	_streams["out"] = _chord([196.0, 147.0], 0.3, 0.3)
	_streams["score"] = _chord([392.0, 523.0, 659.0], 0.55, 0.3)
	_streams["select"] = _chord([440.0, 554.0], 0.11, 0.18)
	_streams["crowd"] = _noise_burst(0.8, 0.2, 17)


func _tone(duration: float, start_hz: float, end_hz: float, noise: float, seed: int) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var phase := 0.0
	for i in range(frames):
		var t := float(i) / float(frames)
		var hz := lerpf(start_hz, end_hz, t)
		phase += TAU * hz / float(rate)
		var envelope := pow(1.0 - t, 2.2) * minf(1.0, t * 35.0)
		var sample := sin(phase) * (1.0 - noise) + rng.randf_range(-1.0, 1.0) * noise
		data.encode_s16(i * 2, int(clampf(sample * envelope, -1.0, 1.0) * 24000.0))
	return _wav(data, rate)


func _chord(frequencies: Array, duration: float, volume: float) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in range(frames):
		var t := float(i) / float(frames)
		var envelope := pow(1.0 - t, 1.7) * minf(1.0, t * 45.0)
		var sample := 0.0
		for hz in frequencies:
			sample += sin(TAU * float(hz) * float(i) / float(rate))
		sample /= maxf(1.0, float(frequencies.size()))
		data.encode_s16(i * 2, int(clampf(sample * envelope * volume, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)


func _noise_burst(duration: float, volume: float, seed: int) -> AudioStreamWAV:
	var rate := 22050
	var frames := int(duration * rate)
	var data := PackedByteArray()
	data.resize(frames * 2)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var filtered := 0.0
	for i in range(frames):
		var t := float(i) / float(frames)
		filtered = lerpf(filtered, rng.randf_range(-1.0, 1.0), 0.18)
		var envelope := sin(PI * t) * (0.6 + 0.4 * sin(t * 19.0) ** 2)
		data.encode_s16(i * 2, int(clampf(filtered * envelope * volume, -1.0, 1.0) * 32767.0))
	return _wav(data, rate)


func _wav(data: PackedByteArray, rate: int) -> AudioStreamWAV:
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream
