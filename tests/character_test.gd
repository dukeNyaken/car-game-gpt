extends SceneTree
const Scene = preload("res://scenes/main.tscn")
var game: Node3D
var checks := 0
var failures: Array[String] = []
var capture := false

func _initialize() -> void:
	capture = "--capture-character" in OS.get_cmdline_user_args()
	run.call_deferred()

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures.append(label)
		print("FAIL: ", label)

func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame

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
	root.get_texture().get_image().save_png("res://tests/character-" + name + ".png")

func check_grips(label: String) -> void:
	var item: Node3D = game.modules.objects[game.modules.held]
	for index in range(2):
		var side := -1.0 if index == 0 else 1.0
		var grip := item.to_global(Vector3(side * 0.31, -0.06, 0.15))
		var palm: Node3D = game.player.arms[index].palm
		check(palm.global_position.distance_to(grip) < 0.015, label + ": palm stays on module " + str(index))

func run() -> void:
	game = Scene.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.test_mode = true
	game.player.test_mode = true
	game.start_run(true)
	game.set_physics_process(false)
	await frames(15)
	check(game.player.can_sit(), "Seat available near spawn")
	var sit := InputEventAction.new()
	sit.action = "sit"
	sit.pressed = true
	game.player._unhandled_input(sit)
	check(game.player.seated, "Sit action enters seat")
	await frames(10)
	check(game.player.is_on_floor(), "Seating retains collision support")
	for foot: Node3D in game.player.feet:
		check(foot.global_position.y - 0.08 >= 3.3, "Seated boot remains above robot deck")
	game.player.yaw = 1.1
	game.player.pitch = -0.2
	game.player.arm.spring_length = 4.8
	await frames(10)
	await snapshot("seated")
	game.pause_game()
	var pose_time: float = game.player.pose_time
	check(not game.player.toggle_seat(), "Pause cannot change seat state")
	await frames(8)
	check(is_equal_approx(game.player.pose_time, pose_time), "Pause freezes pose animation")
	game.start_run()
	game.player.scripted_input = Vector2(0, -1)
	await frames(12)
	check(not game.player.seated and game.player.velocity.length() > 0.1, "WASD immediately leaves seat")
	game.player.scripted_input = Vector2.ZERO
	game.player.reset_position()
	game.player.yaw = 0
	await frames(10)
	check(game.player.toggle_seat(), "Can sit again after walking")
	game.player.scripted_jump = true
	await frames(4)
	check(not game.player.seated and game.player.position.y > 3.5, "Jump leaves seat and launches girl")
	check(not game.player.toggle_seat(), "Cannot sit in mid-air")
	await frames(60)
	game.player.position = Vector3(0, 4.23, -4.1)
	await frames(10)
	check(not game.player.toggle_seat(), "Cannot teleport from head into seat")
	game.player.reset_position()
	await frames(10)
	check(game.player.toggle_seat(), "Return to seat physically")
	check(game.modules.interact(0), "Can take nearby engine from seat")
	check(not game.player.seated and game.player.carrying, "Taking a module stands up before carrying")
	check(not game.player.toggle_seat(), "Cannot sit with a module in hands")
	check(game.modules.interact(0), "Engine returns without power/inventory change")
	for index in [0, 1, 5, 6, 7]:
		check(use(index), "Take each module for grip check " + str(index))
		await frames(4)
		for angle in [0.0, PI / 2.0, PI]:
			game.player.model.rotation.y = angle
			await frames(2)
			check_grips("Rotated carry " + str(index))
		if index == 6:
			game.player.reset_position()
			game.player.model.rotation.y = -0.45
			game.player.yaw = 0.65
			game.player.pitch = -0.2
			game.player.arm.spring_length = 4.6
			await frames(8)
			await snapshot("carry")
			game.player.scripted_jump = true
			await frames(6)
			check_grips("Airborne carry")
		check(use(index), "Return each module " + str(index))
	check(game.modules.invariants_ok(), "All posing keeps inventory intact")
	game.player.reset_position()
	game.player.yaw = 0
	await frames(12)
	game.player.scripted_jump = true
	await frames(6)
	check(not game.player.is_on_floor(), "Finish test begins during actual jump")
	game.practice = false
	game.distance = game.ROUTE_LENGTH - 0.05
	for event: Dictionary in game.events:
		event.resolved = true
	game.advance(1.0 / 60.0)
	var ending_distance: float = game.distance
	check(not game.pursuers[0].visible and not game.missile.visible, "Route finish removes pursuit even after final scenery update")
	check(game.state == "won" and game.player.outcome == "won", "Victory starts character reaction")
	check(not game.hud.overlay.visible, "Reaction visible before result panel")
	await frames(90)
	check(game.player.is_on_floor(), "Ending allows airborne girl to land")
	check(is_equal_approx(game.distance, ending_distance), "Ending cannot advance route")
	check(game.robot.eyes[0].scale.y < 0.5, "Robot shows happy eyes at victory")
	await snapshot("victory")
	await frames(90)
	check(game.hud.overlay.visible, "Result panel appears after short reaction")
	await snapshot("result")
	game.finish(false)
	await frames(30)
	check(game.player.outcome == "lost" and game.robot.ending == "lost", "Defeat has distinct reaction")
	check(game.player.head.rotation.x > 0.15, "Defeat lowers girl's head")
	await snapshot("defeat")
	var restart := InputEventKey.new()
	restart.physical_keycode = KEY_R
	restart.pressed = true
	game._unhandled_input(restart)
	await process_frame
	await process_frame
	game = current_scene
	game.test_mode = true
	check(game.player.outcome.is_empty() and not game.player.seated and game.robot.ending.is_empty(), "Restart clears all character states")
	print("CHARACTER: ", checks, " checks, ", failures.size(), " failures")
	game.sound.stop_all()
	await process_frame
	OS.delay_msec(80)
	game.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)
