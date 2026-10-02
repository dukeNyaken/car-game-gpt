extends SceneTree
const Scene = preload("res://scenes/main.tscn")
var game: Node3D
var errors: Array[String] = []
var actions := 0
var capture := false
var capture_index := 0
var novice := false
var cannon := false
var window_left := 0.0

func _initialize() -> void:
	capture = "--capture-route" in OS.get_cmdline_user_args()
	novice = "--novice" in OS.get_cmdline_user_args()
	cannon = "--cannon" in OS.get_cmdline_user_args()
	run.call_deferred()

func frame() -> void:
	await physics_frame

func walk(target: Vector3, jump: bool = false) -> void:
	var actor: CharacterBody3D = game.player
	if jump:
		if novice:
			for _reaction in range(60):
				await frame()
		actor.scripted_jump = true
	for index in range(360):
		var offset := Vector2(target.x - actor.position.x, target.z - actor.position.z)
		if offset.length() < 0.16 and actor.is_on_floor() and absf(actor.position.y - target.y) < 0.25:
			actor.scripted_input = Vector2.ZERO
			for _settle in range(3):
				await frame()
			return
		actor.scripted_input = offset.normalized() if offset.length() > 0.09 else Vector2.ZERO
		await frame()
		if game.state != "running":
			break
	actor.scripted_input = Vector2.ZERO
	errors.append("Could not walk to " + str(target) + " from " + str(actor.position))
	print("ROUTE WALK FAIL: ", errors[-1])

func use_mount(index: int) -> void:
	actions += 1
	if novice:
		for _reaction in range(45):
			await frame()
	if not game.modules.interact(index):
		errors.append("Interaction rejected at mount " + str(index) + " position " + str(game.player.position))
	for _settle in range(3):
		await frame()
	if not game.modules.invariants_ok():
		errors.append("Module invariant failed")

func until_distance(value: float) -> void:
	for _index in range(20000):
		if game.distance >= value or game.state != "running":
			return
		await frame()
	errors.append("Distance wait timed out")

func snapshot(label: String) -> void:
	if not capture:
		return
	await process_frame
	await RenderingServer.frame_post_draw
	get_root().get_texture().get_image().save_png("res://tests/route-%02d-%s.png" % [capture_index, label])
	capture_index += 1

func run() -> void:
	game = Scene.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.test_mode = true
	game.player.test_mode = true
	game.start_run(false)
	var side := -1.0 if cannon else 1.0
	var source := 7 if cannon else 6
	var hardpoint := 4 if cannon else 3
	await until_distance(365.0)
	# Replace steering with turbines well before the first holes and chasm.
	await walk(Vector3(0, 3.3, -2.2))
	await walk(Vector3(0, 4.2, -3.8), true)
	await snapshot("head")
	await use_mount(1)
	await walk(Vector3(0, 3.3, -2.2))
	await walk(Vector3(1.8, 3.3, 1.45))
	await use_mount(8)
	await walk(Vector3(-1.8, 3.3, -1.4))
	await use_mount(5)
	await walk(Vector3(-1.85, 3.3, 1.4))
	await use_mount(2)
	await snapshot("turbines")
	await until_distance(978.0)
	# Cross the gap, then use the short window before the first missile.
	await use_mount(2)
	await walk(Vector3(-1.8, 3.3, -1.4))
	await use_mount(5)
	await walk(Vector3(1.8 if cannon else 0.0, 3.3, -1.4))
	await use_mount(source)
	await walk(Vector3(side * 2.1, 3.3, -0.6))
	await walk(Vector3(side * 4.2, 3.5, -0.6), true)
	await use_mount(hardpoint)
	window_left = (1160.0 - game.distance) / game.speed
	await snapshot("shield")
	print("DEFENSE CONNECTED AT: ", game.distance, " window_left=", window_left, " cannon=", cannon, " novice=", novice)
	await until_distance(1168.0)
	# Sacrifice speed for steering plus shield during the combined threats.
	await walk(Vector3(side * 2.1, 3.3, -0.6), true)
	await walk(Vector3(0, 3.3, 2.0))
	await use_mount(0)
	await walk(Vector3(1.8 if cannon else 0.0, 3.3, -1.4))
	await use_mount(source)
	await walk(Vector3(1.8, 3.3, 1.45))
	await use_mount(8)
	await walk(Vector3(0, 3.3, -2.2))
	await walk(Vector3(0, 4.2, -3.8), true)
	await use_mount(1)
	await snapshot("steering-shield")
	await until_distance(2000.0)
	if window_left < 2.0:
		errors.append("Defense window has less than two seconds spare")
	if game.state != "won":
		errors.append("Strategy did not reach victory: " + game.state)
	if game.miss_count != 0 or game.success_count != 8:
		errors.append("Threat results: success=%d missed=%d" % [game.success_count, game.miss_count])
	print("ROUTE WITH SWAPS: state=", game.state, " successes=", game.success_count, " misses=", game.miss_count, " gap=", game.chase_distance, " actions=", actions)
	await snapshot("victory")
	game.queue_free()
	await process_frame
	# Control run: leaving the initial configuration unchanged must lose.
	game = Scene.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	game.test_mode = true
	game.player.test_mode = true
	game.start_run(false)
	await until_distance(2000.0)
	if game.state != "lost":
		errors.append("No-swap control run should lose, got " + game.state)
	print("ROUTE WITHOUT SWAPS: state=", game.state, " distance=", game.distance)
	for error in errors:
		print("FAIL: ", error)
	print("FULL ROUTE: ", errors.size(), " failures")
	game.sound.stop_all()
	await process_frame
	OS.delay_msec(80) # Let the audio mix thread release stopped playback before process shutdown.
	game.queue_free()
	await process_frame
	quit(0 if errors.is_empty() else 1)
