extends SceneTree
const Scene = preload("res://scenes/main.tscn")
var game: Node3D
var failures: Array[String] = []
var checks := 0
var capture := false

func _initialize() -> void:
	capture = "--capture-polish" in OS.get_cmdline_user_args()
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ", label)

func use(index: int) -> bool:
	game.player.position = game.modules.mounts[index].node.position + Vector3(0, 0.03, 0.65)
	game.player.velocity = Vector3.ZERO
	return game.modules.interact(index)

func snapshot(name: String) -> void:
	if not capture:
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/polish-" + name + ".png")

func run() -> void:
	game = Scene.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.test_mode = true
	game.player.test_mode = true
	game.start_run(true)
	game.set_physics_process(false)
	# Fill all storage to exercise recovery from an unexpected training configuration.
	check(use(1) and use(8), "Unexpected training: store steering")
	check(use(0), "Unexpected training: hold engine with full storage")
	check(game.modules.guidance(true).index == 0, "Full storage points held engine to its usable hardpoint")
	check(use(0), "Unexpected training: reconnect engine")
	check(game.modules.guidance(true).index == 6, "Full storage chooses shield instead of repeating engine removal")
	# Return to the initial configuration through the same physical interactions.
	check(use(8) and use(1), "Restore steering after recovery test")
	check(game.modules.guidance(true).index == 0, "Training starts at engine")
	await snapshot("training")
	check(use(0), "Training: take engine")
	check(game.modules.guidance(true).index == 8, "Training points to empty storage")
	check(game.sound.cue_counts.grab >= 1, "Grab emits its sound cue")
	check(use(8), "Training: store engine")
	check(game.modules.guidance(true).index == 6, "Training points to shield")
	check(use(6), "Training: take shield")
	check(game.modules.guidance(true).index == 3, "Training points to right arm")
	await snapshot("carry")
	check(use(3), "Training: install shield")
	check(game.modules.guidance(true).index == -1 and game.modules.tutorial_complete, "Training completes after connection")
	check(game.sound.cue_counts.install >= 1, "Installation emits its sound cue")
	check(game.modules.invariants_ok(), "Training preserves all modules")
	# Basic PCM validation: nonempty bounded samples for every original sound.
	var peak := 0
	for voice: AudioStreamPlayer in game.sound.voices.values():
		var wav := voice.stream as AudioStreamWAV
		check(wav.data.size() > 200 and wav.mix_rate == 22050, "Cue contains PCM audio")
		var nonzero := false
		for index in range(0, wav.data.size(), 2):
			var sample := absi(wav.data.decode_s16(index))
			peak = maxi(peak, sample)
			nonzero = nonzero or sample > 0
		check(nonzero, "Cue is not silent")
	check(peak < 30000, "Generated cues avoid clipping")
	print("SOUND PCM PEAK: ", peak)
	# Exercise both cues and actual temporary geometry.
	check(use(3) and use(6), "Store shield")
	check(use(7) and use(4), "Install cannon")
	game.resolve_event("missile")
	check(game.effects.shots_fired == 1 and game.effects.temporary.size() == 11, "Cannon generates beam and intercept sparks")
	check(game.sound.cue_counts.cannon == 1, "Cannon fires audio")
	game.player.position = Vector3(0, 3.35, 0.8)
	game.player.pivot.position = game.player.position + Vector3(0, 1.25, 0)
	await snapshot("intercept")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	game._unhandled_input(escape)
	check(game.sound.engine.stream_paused, "Pause suspends engine sound")
	var remaining: float = game.effects.temporary[0].left
	game.effects._process(0.1)
	check(is_equal_approx(game.effects.temporary[0].left, remaining), "Pause freezes effect lifetime")
	game._unhandled_input(escape)
	check(not game.sound.engine.stream_paused, "Resume resumes audio")
	var mute := InputEventKey.new()
	mute.physical_keycode = KEY_M
	mute.pressed = true
	game._unhandled_input(mute)
	check(game.sound.muted and game.sound.voices.radar.volume_db < -60, "Mute affects cues")
	game._unhandled_input(mute)
	check(not game.sound.muted, "Mute toggles back")
	# Real collision queries across camera rotations at each traversal platform.
	var sphere := SphereShape3D.new()
	sphere.radius = 0.10
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = sphere
	query.collision_mask = 1
	game.player.enabled = false
	var camera_samples := 0
	for pos in [Vector3(0, 3.35, 0.8), Vector3(0, 4.23, -4.0), Vector3(4.2, 3.55, -0.6)]:
		game.player.position = pos
		game.player.pivot.position = pos + Vector3(0, 1.25, 0)
		for yaw in [0.0, PI / 4, PI / 2, 3 * PI / 4, PI, 5 * PI / 4, 3 * PI / 2, 7 * PI / 4]:
			for pitch in [-0.8, -0.4, 0.1]:
				game.player.yaw = yaw
				game.player.pitch = pitch
				for _frame in range(5):
					await physics_frame
				query.transform = Transform3D(Basis.IDENTITY, game.player.camera.global_position)
				var collisions := game.get_world_3d().direct_space_state.intersect_shape(query)
				check(collisions.is_empty(), "Camera is outside hull: " + str(pos) + " yaw=" + str(yaw) + " pitch=" + str(pitch))
				camera_samples += 1
	print("CAMERA SAMPLES: ", camera_samples)
	check(use(1) and use(7), "Store steering before testing turbines")
	check(use(5) and use(2), "Connect turbines on rear mount")
	game.lift = 4.0
	game.scenery.position.y = -4.0
	game.effects._process(0.01)
	check(game.effects.flames[0].visible and game.effects.flames[1].visible, "Powered turbines show both jets")
	check(game.effects.flames[0].scale.y > 0.7, "Jets grow during lift")
	game.player.position = Vector3(0, 3.35, 1.4)
	game.player.yaw = 0.3
	game.player.pitch = -0.35
	game.player.pivot.position = game.player.position + Vector3(0, 1.25, 0)
	for _frame in range(5):
		await physics_frame
	await snapshot("turbines")
	# Training-to-chase must reset the custom training loadout.
	var enter := InputEventKey.new()
	enter.physical_keycode = KEY_ENTER
	enter.pressed = true
	game._unhandled_input(enter)
	await process_frame
	await process_frame
	await process_frame
	game = current_scene
	game.test_mode = true
	game.player.test_mode = true
	game.set_physics_process(false)
	check(game.state == "running" and not game.practice, "Enter switches training to chase")
	check(game.modules.has_module("engine") and game.modules.has_module("steering"), "Chase restarts with original loadout")
	game.distance = 850.0
	game.radar_timer = 0
	var cues: int = game.sound.cue_counts.radar
	game._tick_radar(0.02)
	check(game.sound.cue_counts.radar == cues + 1, "Radar detects approaching missile")
	game._tick_radar(0.05)
	check(game.sound.cue_counts.radar == cues + 1, "Radar does not beep every frame")
	game._tick_radar(2.5)
	check(game.sound.cue_counts.radar == cues + 2, "Radar repeats at bounded cadence")
	for event: Dictionary in game.events:
		event.resolved = true
	game._tick_radar(3.0)
	check(game.sound.cue_counts.radar == cues + 2, "Radar stops after threat resolution")
	print("POLISH: ", checks, " checks, ", failures.size(), " failures")
	game.sound.stop_all()
	await process_frame
	OS.delay_msec(80)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
