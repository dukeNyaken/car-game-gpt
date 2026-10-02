extends Node3D
const Geo = preload("res://scripts/geometry.gd")
const Girl = preload("res://scripts/player.gd")
const Robot = preload("res://scripts/robot.gd")
const Modules = preload("res://scripts/modules.gd")
const Hud = preload("res://scripts/hud.gd")
const Sound = preload("res://scripts/sound.gd")
const Effects = preload("res://scripts/effects.gd")
const ROUTE_LENGTH := 2000.0
const ROAD_STEP := 8.0
const WARN_DISTANCE := 310.0

var player: CharacterBody3D
var robot: Node3D
var modules: Node3D
var hud: CanvasLayer
var scenery: Node3D
var road_segments: Array[Dictionary] = []
var landmarks: Array[Node3D] = []
var event_markers: Array[Dictionary] = []
var pursuers: Array[Node3D] = []
var missile: Node3D
var events: Array[Dictionary] = []
var state := "title"
var practice := false
var distance := 0.0
var speed := 12.0
var chase_distance := 110.0
var elapsed := 0.0
var lift := 0.0
var lift_timer := 0.0
var shield_flash := 0.0
var success_count := 0
var miss_count := 0
var test_mode := false
var sound: Node
var effects: Node3D
var radar_timer := 0.0
var slowdown_timer := 0.0
var emergency_timer := 0.0
var launch_height := 4.0
var road_offset := 0.0
var skid_timer := 0.0

func _ready() -> void:
	_setup_input()
	get_window().min_size = Vector2i(960, 540)
	get_window().focus_exited.connect(_on_window_focus_exited)
	if "--mute" in OS.get_cmdline_user_args():
		Sound.muted = true
	sound = Sound.new()
	add_child(sound)
	_build_world()
	robot = Robot.new()
	add_child(robot)
	player = Girl.new()
	add_child(player)
	player.rescued.connect(_on_rescued)
	modules = Modules.new()
	add_child(modules)
	modules.build(player)
	effects = Effects.new()
	add_child(effects)
	effects.build(self)
	modules.handled.connect(_on_module_handled)
	modules.rejected.connect(func(): sound.play_cue("denied"))
	hud = Hud.new()
	add_child(hud)
	hud.build(self)
	hud.play_requested.connect(start_run)
	modules.feedback.connect(hud.show_feedback)
	_make_events()
	_update_scenery()
	if get_tree().get_meta("launch_chase", false):
		get_tree().remove_meta("launch_chase")
		start_run.call_deferred(false)
	if "--capture" in OS.get_cmdline_user_args():
		_capture_demo.call_deferred()

func _setup_input() -> void:
	var keys := {"forward": KEY_W, "back": KEY_S, "left": KEY_A, "right": KEY_D, "jump": KEY_SPACE, "interact": KEY_E}
	for action: String in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
			var event := InputEventKey.new()
			event.physical_keycode = keys[action]
			InputMap.action_add_event(action, event)

func _build_world() -> void:
	var env := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("#25465f")
	sky_mat.sky_horizon_color = Color("#e8af82")
	sky_mat.ground_horizon_color = Color("#e8af82")
	sky_mat.ground_bottom_color = Color("#3c3840")
	sky.sky_material = sky_mat
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color("#b5c9d3")
	environment.ambient_light_energy = 0.45
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.environment = environment
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-36, -25, 0)
	sun.light_color = Color("#ffdec0")
	sun.light_energy = 0.85
	sun.shadow_enabled = true
	add_child(sun)
	scenery = Node3D.new()
	add_child(scenery)
	Geo.box(scenery, Vector3(0, -14, -40), Vector3(700, 8, 800), Color("#463e42"))
	for index in range(66):
		var segment := Node3D.new()
		scenery.add_child(segment)
		var pavement := Geo.box(segment, Vector3(0, -0.25, 0), Vector3(14, 0.5, ROAD_STEP + 0.4), Color("#404d57"))
		var left_edge := Geo.box(segment, Vector3(-6.85, 0.04, 0), Vector3(0.16, 0.07, ROAD_STEP), Color("#e0b572"))
		var right_edge := Geo.box(segment, Vector3(6.85, 0.04, 0), Vector3(0.16, 0.07, ROAD_STEP), Color("#e0b572"))
		var stripe := Geo.box(segment, Vector3(0, 0.03, 0), Vector3(0.13, 0.04, 3.5), Color("#c6cbc0"))
		road_segments.append({"node": segment, "pavement": pavement, "stripe": stripe, "left": left_edge, "right": right_edge})
	for index in range(36):
		var rock := Node3D.new()
		scenery.add_child(rock)
		var side := -1.0 if index % 2 == 0 else 1.0
		var height := 10.0 + float((index * 17) % 29)
		Geo.box(rock, Vector3.ZERO, Vector3(11 + index % 8, height, 13), Color("#775c57"))
		rock.rotation_degrees.z = side * float(index % 9)
		rock.set_meta("side", side)
		rock.set_meta("height", height)
		landmarks.append(rock)
	for index in range(3):
		var drone := Node3D.new()
		add_child(drone)
		Geo.box(drone, Vector3.ZERO, Vector3(1.5, 0.5, 1.2), Color("#293543"))
		for side in [-1.0, 1.0]:
			Geo.cylinder(drone, Vector3(side, 0.1, 0), 0.65, 0.1, Color("#596276"))
		Geo.sphere(drone, Vector3(0, 0, -0.64), 0.18, Color("#ef5c61"))
		pursuers.append(drone)
	missile = Node3D.new()
	add_child(missile)
	Geo.box(missile, Vector3.ZERO, Vector3(0.25, 0.25, 1.25), Color("#ff9970"))
	Geo.sphere(missile, Vector3(0, 0, 0.85), 0.22, Color("#ffd080"))
	missile.visible = false

func _make_events() -> void:
	events = [
		{"at": 330.0, "kind": "turn", "title": "ПОВОРОТ • нужен руль"},
		{"at": 650.0, "kind": "hole", "title": "ЯМЫ • руль или турбины"},
		{"at": 970.0, "kind": "gap", "title": "ОБРЫВ • нужны турбины"},
		{"at": 1160.0, "kind": "missile", "title": "РАДАР: РАКЕТА • щит или пушка"},
		{"at": 1370.0, "kind": "turn", "title": "ПОВОРОТ • нужен руль"},
		{"at": 1450.0, "kind": "missile", "title": "РАДАР: РАКЕТА • щит или пушка"},
		{"at": 1740.0, "kind": "hole", "title": "ЯМЫ • руль или турбины"},
		{"at": 1830.0, "kind": "missile", "title": "РАДАР: РАКЕТА • щит или пушка"}
	]
	for event: Dictionary in events:
		event["resolved"] = false
		var marker := Node3D.new()
		scenery.add_child(marker)
		var kind := String(event.kind)
		var color := Color("#a3a0ff") if kind == "gap" else Color("#e2b66f")
		if kind != "missile":
			Geo.box(marker, Vector3(-7.5, 1.7, 0), Vector3(0.16, 3.4, 0.16), color)
			Geo.box(marker, Vector3(7.5, 1.7, 0), Vector3(0.16, 3.4, 0.16), color)
			Geo.label(marker, Vector3(0, 4.0, 0), event.title, color, 55)
		if kind == "hole":
			var hole := Geo.cylinder(marker, Vector3(-2.0, 0.04, 0), 1.55, 0.04, Color("#151b25"))
			hole.scale.z = 1.5
		event_markers.append({"node": marker, "at": event.at})

func start_run(training: bool = false) -> void:
	if state == "won" or state == "lost":
		get_tree().reload_current_scene()
		return
	if state == "title":
		practice = training
	state = "running"
	sound.set_running(true)
	player.enabled = true
	modules.enabled = true
	hud.overlay.visible = false
	if not test_mode:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	hud.show_feedback("Сними модуль клавишей E и отнеси в запас." if practice else "Держись! Впереди поворот, руль уже подключён.")

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ENTER:
				if state == "running" and practice:
					get_tree().set_meta("launch_chase", true)
					get_tree().reload_current_scene()
				elif state != "running":
					start_run()
			KEY_T:
				if state == "title":
					start_run(true)
			KEY_M:
				var muted: bool = sound.toggle_mute()
				hud.show_feedback("Звук выключен • M — включить" if muted else "Звук включён • M — выключить")
			KEY_ESCAPE:
				if state == "running":
					pause_game()
				elif state == "paused":
					start_run()
			KEY_R:
				get_tree().reload_current_scene()

func _physics_process(delta: float) -> void:
	if state != "running":
		return
	advance(delta)

func advance(delta: float) -> void:
	elapsed += delta
	_tick_radar(delta)
	sound.update_engine(modules.has_module("engine"), speed)
	slowdown_timer = maxf(0.0, slowdown_timer - delta)
	emergency_timer = maxf(0.0, emergency_timer - delta)
	skid_timer = maxf(0.0, skid_timer - delta)
	var target_speed := 17.0 if modules.has_module("engine") else 10.0
	if slowdown_timer > 0:
		target_speed *= 0.48
	speed = move_toward(speed, target_speed, delta * (9.0 if slowdown_timer > 0 else 3.0))
	if not practice:
		distance += speed * delta
		var chase_gain := 0.45 if modules.has_module("engine") else -0.72
		if slowdown_timer > 0:
			chase_gain -= 1.2
		chase_distance = clampf(chase_distance + chase_gain * delta, 0, 150)
		for event: Dictionary in events:
			if not event.resolved and distance >= float(event.at):
				event.resolved = true
				resolve_event(String(event.kind))
		if chase_distance <= 0:
			finish(false)
		elif distance >= ROUTE_LENGTH:
			finish(true)
	lift_timer = maxf(0, lift_timer - delta)
	shield_flash = maxf(0, shield_flash - delta)
	_update_motion(delta)
	robot.animate(elapsed, speed, chase_distance < 40, shield_flash > 0)
	_update_scenery()

func resolve_event(kind: String) -> bool:
	var success := false
	match kind:
		"turn":
			success = modules.has_module("steering")
		"hole":
			success = modules.has_module("steering") or modules.has_module("flight")
			if modules.has_module("flight"):
				lift_timer = 0.65
				launch_height = 1.8
		"gap":
			success = modules.has_module("flight")
			if success:
				lift_timer = 2.0
				launch_height = 4.0
		"missile":
			success = modules.has_module("shield") or modules.has_module("cannon")
			if modules.has_module("cannon"):
				effects.fire(modules.mounts[4].node.global_position + Vector3(0, 0.9, 0), Vector3(0, 5.8, 4.0))
				sound.play_cue("cannon")
			elif modules.has_module("shield"):
				shield_flash = 1.2
				sound.play_cue("shield")
	if success:
		robot.react("happy", elapsed)
		if kind != "missile":
			sound.play_cue("happy")
		success_count += 1
		chase_distance = minf(150.0, chase_distance + 7.0)
		var message := "Пронесло! Отличная работа."
		if kind == "missile":
			message = "Пушка сбила ракету!" if modules.has_module("cannon") else "Щит выдержал удар!"
		hud.show_feedback(message)
	else:
		robot.react("hurt", elapsed)
		slowdown_timer = 3.2
		if kind == "turn":
			skid_timer = 2.0
		if kind == "gap":
			emergency_timer = 1.6
			lift_timer = 1.6
			launch_height = 3.2
			sound.play_cue("rescue")
		sound.play_cue("hurt")
		effects.burst(Vector3(0, 3.7, 2.5), Color("#f4a576"))
		miss_count += 1
		chase_distance = maxf(0, chase_distance - (65.0 if kind == "gap" else (42.0 if kind == "missile" else 32.0)))
		hud.show_feedback("Аварийный рывок спас от падения. Погоня совсем близко!" if kind == "gap" else "Удар! Робот замедлился, погоня приблизилась.")
	return success

func warning_text() -> String:
	if state != "running":
		return ""
	if practice:
		return "ОСВОЙСЯ НА КОРПУСЕ"
	var messages := PackedStringArray()
	for event: Dictionary in events:
		var remaining := float(event.at) - distance
		if not event.resolved and remaining <= WARN_DISTANCE and remaining > 0:
			messages.append(String(event.title) + "  ·  %d с" % ceili(remaining / maxf(speed, 1.0)))
			if messages.size() == 2:
				break
	return "\n".join(messages)

func road_x(s: float) -> float:
	return sin(s / 150.0) * 17.0 + sin(s / 73.0) * 4.0

func _update_scenery() -> void:
	var travel := elapsed * 10.0 if practice else distance
	var base := floorf(travel / ROAD_STEP) * ROAD_STEP - 80.0
	var center := road_x(travel)
	for index in range(road_segments.size()):
		var s := base + index * ROAD_STEP
		var segment: Node3D = road_segments[index].node
		segment.position = Vector3(road_x(s) - center, 0, travel - s)
		segment.rotation.y = atan2(road_x(s + 2.0) - road_x(s - 2.0), -4.0) - PI
		var gap := not practice and s > 958.0 and s < 982.0
		segment.visible = not gap
	for index in range(landmarks.size()):
		var s := floorf(travel / 540.0) * 540.0 + index * 30.0 - 90.0
		if s < travel - 90:
			s += 1080.0
		var rock: Node3D = landmarks[index]
		rock.position = Vector3(float(rock.get_meta("side")) * (28 + index % 17) + road_x(s) - center, float(rock.get_meta("height")) * 0.5 - 12, travel - s)
	for marker: Dictionary in event_markers:
		var s := float(marker.at)
		marker.node.position = Vector3(road_x(s) - center, 0, distance - s)
		marker.node.visible = not practice and absf(distance - s) < 340
	for index in range(pursuers.size()):
		pursuers[index].position = Vector3((index - 1) * 5.0, 4.0 + sin(elapsed * 2 + index), 15.0 + chase_distance * 0.32 + index * 4)
		pursuers[index].visible = not practice
	missile.visible = false
	if not practice:
		for event: Dictionary in events:
			if event.kind == "missile" and not event.resolved:
				var remaining := float(event.at) - distance
				if remaining > 0 and remaining < WARN_DISTANCE:
					missile.visible = true
					missile.position = Vector3(sin(elapsed) * 0.5, 4.5, 4.0 + remaining * 0.24)
					break

func _on_rescued() -> void:
	sound.play_cue("rescue")
	robot.react("hurt", elapsed)
	if not practice:
		chase_distance = maxf(0, chase_distance - 12.0)
	hud.show_feedback("Робот подхватил тебя! Модуль остался в руках.")

func finish(won: bool) -> void:
	state = "won" if won else "lost"
	sound.stop_engine()
	sound.play_cue("win" if won else "hurt")
	player.enabled = false
	modules.enabled = false
	if not test_mode:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_menu(state)

func _capture_demo() -> void:
	test_mode = true
	start_run(true)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var shot := get_viewport().get_texture().get_image()
	shot.save_png("res://tests/prototype-overview.png")
	print("CAPTURE: tests/prototype-overview.png")
	get_tree().quit()

func _on_module_handled(action: String, _kind: String, _index: int) -> void:
	var cue := "grab" if action == "take" else action
	sound.play_cue(cue)

func nearest_missile_seconds() -> float:
	if practice:
		return -1.0
	var result := INF
	for event: Dictionary in events:
		if event.kind == "missile" and not event.resolved:
			var remaining := float(event.at) - distance
			if remaining > 0 and remaining <= WARN_DISTANCE:
				result = minf(result, remaining / maxf(speed, 1.0))
	return -1.0 if is_inf(result) else result

func _tick_radar(delta: float) -> void:
	var seconds := nearest_missile_seconds()
	if seconds < 0:
		radar_timer = 0.0
		return
	radar_timer -= delta
	if radar_timer <= 0:
		sound.play_cue("radar")
		radar_timer = clampf(seconds / 6.0, 0.65, 2.3)

func _process(delta: float) -> void:
	if state == "won" or state == "lost":
		elapsed += delta
		robot.animate(elapsed, 0.0, state == "lost", false)


func pause_game() -> void:
	if state != "running":
		return
	state = "paused"
	sound.set_running(false)
	player.enabled = false
	modules.enabled = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	hud.show_menu("paused")

func _on_window_focus_exited() -> void:
	if test_mode or state != "running":
		return
	# Releasing actions prevents a key held during Alt-Tab from sticking on return.
	for action: String in ["forward", "back", "left", "right", "jump", "interact"]:
		Input.action_release(action)
	pause_game()

func _update_motion(delta: float) -> void:
	var target_offset := 0.0
	var target_lift := launch_height if lift_timer > 0 else 0.0
	var flight: bool = modules.has_module("flight")
	var steering: bool = modules.has_module("steering")
	if not practice:
		for event: Dictionary in events:
			var remaining := float(event.at) - distance
			if event.kind == "hole":
				if steering and not flight and absf(remaining) < 50.0:
					target_offset = 3.25 * smoothstep(0.0, 1.0, 1.0 - absf(remaining) / 50.0)
				if flight and remaining > 0 and remaining < 35.0:
					target_lift = maxf(target_lift, 1.8 * smoothstep(0.0, 1.0, 1.0 - remaining / 35.0))
			elif event.kind == "turn" and steering and absf(remaining) < 65.0:
				target_offset = maxf(target_offset, 1.3 * smoothstep(0.0, 1.0, 1.0 - absf(remaining) / 65.0))
			elif event.kind == "gap" and flight and remaining > 0 and remaining < 70.0:
				target_lift = maxf(target_lift, 4.0 * smoothstep(0.0, 1.0, 1.0 - remaining / 70.0))
	if skid_timer > 0:
		target_offset -= 1.8 * sin((2.0 - skid_timer) * PI / 2.0)
	road_offset = move_toward(road_offset, target_offset, delta * 3.8)
	lift = move_toward(lift, target_lift, delta * 5.0)
	scenery.position = Vector3(-road_offset, -lift, 0)
	# The world moves relative to the stable riding platform, as in the existing chase.
	# Only the cosmetic wheel steering changes; walking colliders remain stable.
	var tangent := atan2(road_x(distance + 4.0) - road_x(distance - 4.0), 8.0)
	robot.steering_angle = clampf(tangent, -0.35, 0.35) if steering else 0.0
