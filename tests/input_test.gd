extends SceneTree
const Scene = preload("res://scenes/main.tscn")
var game: Node3D
var checks := 0
var failures: Array[String] = []

func _initialize() -> void:
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ", label)

func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame

func key_event(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func tap(code: Key) -> void:
	key_event(code, true)
	await frames(3)
	key_event(code, false)
	await frames(3)

func mouse_move(relative: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = Vector2(640, 360)
	event.relative = relative
	Input.parse_input_event(event)

func wheel(button: MouseButton) -> void:
	var event := InputEventMouseButton.new()
	event.position = Vector2(640, 360)
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	await frames(2)
	event.pressed = false
	Input.parse_input_event(event)
	await frames(2)

func run() -> void:
	if "--export-check" in OS.get_cmdline_user_args():
		if ResourceLoader.exists("res://tests/smoke_test.gd") or not FileAccess.file_exists("res://project.binary"):
			failures.append("Expected exported resources, not the source project")
	game = Scene.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.test_mode = true
	# Player.test_mode stays false: all movement and actions must come through Input.
	await tap(KEY_T)
	check(game.state == "running" and game.practice, "T starts training through input dispatch")
	await frames(12)
	for code in [KEY_W, KEY_S, KEY_A, KEY_D]:
		var before: Vector3 = game.player.position
		key_event(code, true)
		await frames(12)
		key_event(code, false)
		await frames(12)
		var change: Vector3 = game.player.position - before
		var direction: Vector3 = {KEY_W: Vector3.FORWARD, KEY_S: Vector3.BACK, KEY_A: Vector3.LEFT, KEY_D: Vector3.RIGHT}[code]
		check(change.dot(direction) > 0.5, "Physical key moves girl in expected direction " + str(code))
	check(Vector2(game.player.velocity.x, game.player.velocity.z).length() < 0.1, "Releasing movement stops the girl")
	await tap(KEY_F)
	check(game.player.seated, "Physical F sits by the seat")
	await tap(KEY_SPACE)
	check(not game.player.seated and game.player.position.y > 3.5, "Physical Space leaves seat and jumps")
	await frames(60)
	check(game.player.is_on_floor(), "Jump lands on robot")
	await tap(KEY_F)
	check(game.player.seated, "Physical F can sit again")
	await tap(KEY_E)
	check(game.modules.held == "engine" and not game.player.seated, "Physical E grabs engine and stands up")
	await tap(KEY_E)
	check(game.modules.held.is_empty() and game.modules.has_module("engine"), "Physical E reinstalls engine")
	if DisplayServer.get_name() != "headless":
		var old_yaw: float = game.player.yaw
		var old_pitch: float = game.player.pitch
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		mouse_move(Vector2(50, 20))
		await frames(3)
		check(is_equal_approx(game.player.yaw, old_yaw - 0.15), "Mouse horizontal motion rotates camera")
		check(is_equal_approx(game.player.pitch, old_pitch - 0.06), "Mouse vertical motion tilts camera")
		mouse_move(Vector2(-50, -20))
		await frames(3)
	else:
		print("SKIP: captured mouse requires a window; run graphics acceptance too")
	await wheel(MOUSE_BUTTON_WHEEL_UP)
	check(is_equal_approx(game.player.arm.spring_length, 7.4), "Mouse wheel zooms in")
	await wheel(MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(game.player.arm.spring_length, 8.0), "Mouse wheel zooms out")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await tap(KEY_M)
	check(game.sound.muted, "Physical M mutes sound")
	await tap(KEY_M)
	check(not game.sound.muted, "Physical M restores sound")
	await tap(KEY_ESCAPE)
	check(game.state == "paused", "Physical Escape pauses")
	var pause_pos: Vector3 = game.player.position
	key_event(KEY_W, true)
	await frames(10)
	key_event(KEY_W, false)
	check(game.player.position.distance_to(pause_pos) < 0.01, "W cannot move during pause")
	await tap(KEY_ENTER)
	check(game.state == "running", "Physical Enter resumes")
	await tap(KEY_ENTER)
	await frames(4)
	game = current_scene
	game.test_mode = true
	check(game.state == "running" and not game.practice, "Enter from training opens fresh chase")
	check(game.modules.has_module("engine") and game.modules.has_module("steering"), "Training transition restores starting equipment")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	await tap(KEY_R)
	await frames(4)
	game = current_scene
	game.test_mode = true
	check(game.state == "title" and not game.player.enabled, "Physical R returns to title")
	await tap(KEY_ENTER)
	check(game.state == "running" and not game.practice, "Enter from title starts chase")
	check(game.modules.invariants_ok(), "Input test preserves unique modules")
	print("INPUT: ", checks, " checks, ", failures.size(), " failures")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	game.sound.stop_all()
	await process_frame
	OS.delay_msec(80)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
