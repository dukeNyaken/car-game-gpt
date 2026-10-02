extends SceneTree
const Main = preload("res://scenes/main.tscn")
var game: Node3D
var failures: Array[String] = []
var checks := 0

func _initialize() -> void:
	run.call_deferred()

func check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		print("FAIL: " + message)

func frames(count: int) -> void:
	for _index in range(count):
		await physics_frame

func at_mount(index: int) -> void:
	game.player.position = game.modules.mounts[index].node.position + Vector3(0, 0.03, 0.65)
	game.player.velocity = Vector3.ZERO

func transfer(source: int, destination: int) -> bool:
	at_mount(source)
	var picked: bool = game.modules.interact(source)
	at_mount(destination)
	var placed: bool = game.modules.interact(destination)
	return picked and placed

func run() -> void:
	game = Main.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.test_mode = true
	game.player.test_mode = true
	game.start_run(true)
	game.set_physics_process(false)
	await frames(30)
	check(game.player.is_on_floor(), "Girl stands on the back")
	check(absf(game.player.position.y - 3.3) < 0.1, "Girl feet meet the deck")
	check(game.modules.invariants_ok(), "Initial module ownership and power")
	check(game.modules.active_count() == 2, "Two initial active modules")
	# Remote interactions must be rejected even if UI selection is stale.
	game.player.position = Vector3(0, 3.35, 2)
	check(not game.modules.interact(1), "Cannot remove steering remotely")
	check(game.modules.has_module("steering"), "Remote action has no effect")
	# The visible hardpoint cannot be operated while remaining on the main deck.
	game.player.position = Vector3(0, 3.3, -2.8)
	check(not game.modules.in_reach(1), "Head interaction requires reaching head height")
	game.player.position = Vector3(2.65, 3.3, -0.6)
	check(not game.modules.in_reach(3), "Arm interaction requires crossing the gap")

	# Cannot plug in a third function; mismatch retains the held item.
	at_mount(5)
	check(game.modules.interact(5), "Pick up flight module")
	check(game.player.carrying and game.modules.held == "flight", "Carry state follows the object")
	at_mount(3)
	check(not game.modules.interact(3), "Wrong hardpoint rejects flight module")
	at_mount(2)
	check(not game.modules.interact(2), "Power limit rejects third active module")
	check(game.modules.held == "flight", "Rejected installation preserves held module")
	at_mount(5)
	check(game.modules.interact(5), "Return flight module to storage")
	check(transfer(0, 8), "Physically remove engine and store it")
	check(not game.modules.has_module("engine"), "Removing engine disables its function")
	check(transfer(5, 2), "Connect flight after freeing power")
	check(game.modules.has_module("flight"), "Flight capability is enabled by installation")
	check(game.modules.invariants_ok(), "No duplicated or missing modules after swaps")
	at_mount(2)
	game.modules.interact(2)
	game.player.position = Vector3(9, -3, 0)
	await frames(4)
	check(game.player.position.distance_to(game.player.spawn_point) < 0.4, "Fall safely returns girl to back")
	check(game.modules.held == "flight" and game.player.carrying, "Rescue preserves carried module")
	at_mount(5)
	game.modules.interact(5)
	# Traverse actual colliders with the same movement code as WASD + Space.
	game.player.reset_position()
	await frames(20)
	game.player.scripted_input = Vector2(0, -1)
	await frames(44)
	game.player.scripted_jump = true
	await frames(27)
	game.player.scripted_input = Vector2.ZERO
	await frames(38)
	print("HEAD POSITION: ", game.player.position)
	check(game.player.position.z < -3.3 and game.player.position.y > 4.15 and game.player.is_on_floor(), "Jump from back onto raised head")
	for side in [-1.0, 1.0]:
		game.player.position = Vector3(0, 3.36, -0.6)
		game.player.velocity = Vector3.ZERO
		await frames(10)
		game.player.scripted_input = Vector2(side, 0)
		await frames(27)
		game.player.scripted_jump = true
		await frames(29)
		game.player.scripted_input = Vector2.ZERO
		await frames(36)
		print("ARM POSITION: ", game.player.position)
		check(absf(game.player.position.x) > 3.2 and game.player.position.y > 3.45 and game.player.is_on_floor(), "Jump onto arm " + str(side))
	# Encounter rules, route failure and route completion.
	check(game.resolve_event("turn"), "Steering handles turn")
	check(not game.resolve_event("gap"), "Gap has a cost without turbines")
	check(transfer(1, 8) == false, "Occupied storage does not silently swap modules")
	# Steering is now held. Put it into free storage slot 6 after freeing shield.
	# Reset to a fresh scene for deterministic encounter checks.
	game.queue_free()
	await process_frame
	game = Main.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.test_mode = true
	game.player.test_mode = true
	game.start_run(true)
	game.set_physics_process(false)
	check(transfer(0, 8), "Free engine hardpoint on fresh run")
	check(transfer(6, 3), "Connect shield on right arm")
	check(game.resolve_event("missile"), "Shield counters missile")
	check(transfer(3, 6), "Store shield")
	check(transfer(7, 4), "Connect cannon on left arm")
	check(game.resolve_event("missile"), "Cannon counters missile")
	check(game.modules.invariants_ok(), "Shield/cannon swaps preserve invariants")
	game.practice = false
	game.chase_distance = 0.01
	game.advance(0.1)
	check(game.state == "lost", "Chase catches robot when distance reaches zero")
	check(not game.player.enabled and not game.modules.enabled, "Defeat freezes interaction")
	game.state = "running"
	game.player.enabled = true
	game.modules.enabled = true
	game.chase_distance = 120
	game.distance = game.ROUTE_LENGTH - 0.1
	for event: Dictionary in game.events:
		event.resolved = true
	game.advance(0.1)
	check(game.state == "won", "Route completion reaches win screen")
	var restart_key := InputEventKey.new()
	restart_key.physical_keycode = KEY_ENTER
	restart_key.pressed = true
	game._unhandled_input(restart_key)
	await process_frame
	await process_frame
	game = current_scene
	check(game.state == "title", "Victory restart returns to fresh start screen")
	check(game.modules.active_count() == 2 and game.modules.held.is_empty(), "Restart resets module configuration")
	game.test_mode = true
	game.start_run()
	var pause_key := InputEventKey.new()
	pause_key.physical_keycode = KEY_ESCAPE
	pause_key.pressed = true
	game._unhandled_input(pause_key)
	var paused_distance: float = game.distance
	await frames(5)
	check(game.state == "paused" and is_equal_approx(game.distance, paused_distance), "Pause freezes the chase")
	check(not game.player.enabled and not game.modules.enabled, "Pause freezes the girl and interactions")
	game._unhandled_input(pause_key)
	check(game.state == "running" and game.player.enabled and game.modules.enabled, "Escape resumes play")

	print("PROTOTYPE: ", checks, " checks, ", failures.size(), " failures")
	quit(0 if failures.is_empty() else 1)
