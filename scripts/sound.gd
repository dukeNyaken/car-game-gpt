extends Node
## Small original synthesized cues; no downloaded audio or external dependencies.
const RATE := 22050
static var muted := false
var voices: Dictionary = {}
var cue_counts: Dictionary = {}
var engine: AudioStreamPlayer

func _ready() -> void:
	var specs := {
		"grab": [0.13, 440.0, 250.0, 0.05, -14.0],
		"install": [0.26, 430.0, 860.0, 0.03, -13.0],
		"store": [0.14, 330.0, 290.0, 0.1, -16.0],
		"denied": [0.18, 160.0, 120.0, 0.05, -18.0],
		"radar": [0.25, 900.0, 1100.0, 0.0, -17.0],
		"cannon": [0.22, 600.0, 100.0, 0.3, -14.0],
		"shield": [0.4, 230.0, 650.0, 0.1, -15.0],
		"hurt": [0.32, 110.0, 65.0, 0.55, -17.0],
		"happy": [0.3, 520.0, 780.0, 0.0, -18.0],
		"rescue": [0.28, 270.0, 510.0, 0.03, -17.0],
		"win": [0.65, 440.0, 880.0, 0.0, -15.0]
	}
	for key: String in specs:
		var spec: Array = specs[key]
		var voice := AudioStreamPlayer.new()
		voice.stream = make_tone(spec[0], spec[1], spec[2], spec[3], key == "radar")
		voice.volume_db = -80.0 if muted else float(spec[4])
		voice.max_polyphony = 2
		voice.set_meta("level", spec[4])
		add_child(voice)
		voices[key] = voice
		cue_counts[key] = 0
	engine = AudioStreamPlayer.new()
	engine.stream = make_engine()
	engine.volume_db = -80.0 if muted else -27.0
	add_child(engine)

func make_tone(duration: float, start_hz: float, end_hz: float, noise: float, double_ping: bool = false) -> AudioStreamWAV:
	var count := int(duration * RATE)
	var data := PackedByteArray()
	data.resize(count * 2)
	var phase := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 8042
	for index in range(count):
		var t := float(index) / RATE
		var u := float(index) / count
		phase += TAU * lerpf(start_hz, end_hz, u) / RATE
		var envelope := minf(t / 0.012, 1.0) * pow(1.0 - u, 1.5)
		if double_ping:
			var pulse := fmod(t, duration * 0.5)
			envelope *= clampf((0.095 - pulse) / 0.016, 0, 1)
		var sample := (sin(phase) * (1.0 - noise) + rng.randf_range(-1, 1) * noise) * envelope * 0.65
		data.encode_s16(index * 2, int(clampf(sample, -1, 1) * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	return stream

func make_engine() -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(RATE * 2)
	for index in range(RATE):
		var t := float(index) / RATE
		var sample := (sin(TAU * 80 * t) * 0.4 + sin(TAU * 160 * t) * 0.14) * (0.8 + sin(TAU * 8 * t) * 0.2)
		data.encode_s16(index * 2, int(sample * 32767))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = data
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_end = RATE
	return stream

func play_cue(key: String) -> void:
	if not voices.has(key):
		return
	cue_counts[key] += 1
	if not muted:
		voices[key].play()

func set_running(running: bool) -> void:
	for voice: AudioStreamPlayer in voices.values():
		voice.stream_paused = not running
	if running:
		if not engine.playing:
			engine.play()
		engine.stream_paused = false
	else:
		engine.stream_paused = true

func stop_engine() -> void:
	engine.stop()

func update_engine(powered: bool, speed: float) -> void:
	engine.volume_db = -80.0 if muted else (-27.0 if powered else -35.0)
	engine.pitch_scale = clampf(speed / 15.0, 0.65, 1.35)

func toggle_mute() -> bool:
	muted = not muted
	for voice: AudioStreamPlayer in voices.values():
		voice.volume_db = -80.0 if muted else float(voice.get_meta("level"))
	engine.volume_db = -80.0 if muted else -27.0
	return muted

func stop_all() -> void:
	for voice: AudioStreamPlayer in voices.values():
		voice.stop()
	engine.stop()

func _exit_tree() -> void:
	stop_all()
	for voice: AudioStreamPlayer in voices.values():
		voice.stream = null
	engine.stream = null
