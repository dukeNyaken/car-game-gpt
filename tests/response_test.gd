extends SceneTree
const Scene = preload("res://scenes/main.tscn")
var game: Node3D
var checks := 0
var failures: Array[String] = []
var capture := false

func _initialize() -> void:
	capture = "--capture-response" in OS.get_cmdline_user_args()
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

func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame

func snapshot(name: String) -> void:
	if not capture:
		return
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/response-" + name + ".png")

func node_count(node: Node) -> int:
	var count := 1
	for child in node.get_children():
		count += node_count(child)
	return count

func run() -> void:
	game = Scene.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.test_mode = true
	game.player.test_mode = true
	game.start_run(false)
	game.set_physics_process(false)
	for event: Dictionary in game.events:
		event.resolved = true
	await frames(20)
	var initial_feet: Vector3 = game.player.position
	game.distance = 648.0
	for _index in range(30):
		game._update_motion(1.0 / 30.0)
		await physics_frame
	check(game.road_offset > 3.1, "Steering produces a visible lane change near the pothole")
	check(game.scenery.position.x < -3.1, "Road moves relative to riding platform during dodge")
	check(game.player.position.distance_to(initial_feet) < 0.03 and game.player.is_on_floor(), "Dodge does not slide girl off the robot")
	await snapshot("dodge")
	game.distance = 800.0
	for _index in range(30):
		game._update_motion(1.0 / 30.0)
	check(absf(game.road_offset) < 0.01, "Lane change recenters after obstacle")
	check(use(1) and use(8), "Store steering for flight")
	check(use(5) and use(2), "Install flight")
	game.player.reset_position()
	game.distance = 940.0
	for _index in range(30):
		game._update_motion(1.0 / 30.0)
	check(game.lift > 2.0, "Turbines lift before reaching the chasm")
	check(game.resolve_event("gap") and game.lift_timer > 0, "Flight keeps momentum after takeoff")
	check(use(2) and use(5), "Remove turbines to test emergency response")
	game.player.reset_position()
	game.lift = 0
	game.chase_distance = 120.0
	game.speed = 17.0
	check(not game.resolve_event("gap"), "Unprepared chasm still counts as a mistake")
	check(game.chase_distance <= 55.0, "Emergency does not erase chase penalty")
	check(game.emergency_timer > 0 and game.slowdown_timer > 0, "Unprepared chasm triggers emergency and slowdown")
	game.advance(0.5)
	game.effects._process(0.01)
	check(game.speed < 14.0, "Mistake visibly lowers travel speed")
	check(game.lift > 2.0, "Emergency gives a visible upward recovery")
	check(game.effects.flames[0].visible, "Emergency shows reserve thrust without flight module")
	await frames(10)
	check(game.player.is_on_floor(), "Emergency keeps riding platform stable")
	await snapshot("emergency")
	game.advance(4.0)
	game.effects._process(0.01)
	check(game.emergency_timer == 0 and game.slowdown_timer == 0, "Recovery timers expire")
	check(game.speed > 16.0, "Engine restores speed after recovery")
	check(not game.effects.flames[0].visible, "Reserve thrust turns off after recovery")
	# Exercise the actual focus callback with held actions.
	Input.action_press("forward")
	Input.action_press("interact")
	game.test_mode = false
	game._on_window_focus_exited()
	game.test_mode = true
	check(game.state == "paused", "Losing window focus pauses running chase")
	check(not Input.is_action_pressed("forward") and not Input.is_action_pressed("interact"), "Focus loss releases held actions")
	check(game.sound.engine.stream_paused and not game.player.enabled, "Focus pause suspends sound and movement")
	var paused_distance: float = game.distance
	await frames(8)
	check(is_equal_approx(game.distance, paused_distance), "Focus pause does not advance route")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "Focus pause releases mouse")
	# The minimum supported window must keep the full pause screen visible.
	root.size = Vector2i(960, 540)
	await frames(4)
	check(root.min_size == Vector2i(960, 540), "Window has the supported minimum size")
	var menu: Control = game.hud.heading.get_parent()
	var bounds: Rect2 = game.hud.overlay.get_global_rect()
	check(bounds.encloses(menu.get_global_rect()), "Pause panel fits the UI canvas")
	await snapshot("small-pause")
	game.start_run()
	check(game.state == "running" and game.player.enabled, "Resume from focus pause works")
	# Repeated real scene reloads must not accumulate cameras or nodes.
	var restart := InputEventKey.new()
	restart.physical_keycode = KEY_R
	restart.pressed = true
	var baseline := -1
	for index in range(4):
		game._unhandled_input(restart)
		await process_frame
		await process_frame
		await frames(2)
		game = current_scene
		game.test_mode = true
		var total := node_count(game)
		if baseline < 0:
			baseline = total
		check(total == baseline, "Restart has stable scene node count " + str(index))
		check(game.state == "title" and game.modules.invariants_ok(), "Restart restores a clean loadout " + str(index))
		print("RESTART ", index, ": ", total, " nodes")
	print("RESPONSE: ", checks, " checks, ", failures.size(), " failures")
	game.sound.stop_all()
	await process_frame
	OS.delay_msec(80)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
