extends CharacterBody3D

signal rescued
const Geo = preload("res://scripts/geometry.gd")
const WALK_SPEED := 4.2
const CARRY_SPEED := 3.4
const JUMP_SPEED := 7.6
const GRAVITY := 20.0
const SEAT_POINT := Vector3(0, 3.3, 1.65)
const UPPER_ARM := 0.28
const FOREARM := 0.30
var enabled := false
var carrying := false
var seated := false
var outcome := ""
var pose_time := 0.0
var yaw := 0.0
var pitch := -0.4
var model: Node3D
var head: Node3D
var hand: Node3D
var pivot: Node3D
var arm: SpringArm3D
var camera: Camera3D
var left_leg: Node3D
var right_leg: Node3D
var knees: Array[Node3D] = []
var feet: Array[Node3D] = []
var arms: Array[Dictionary] = []
var gait := 0.0
var coyote := 0.0
var spawn_point := Vector3(0, 3.35, 0.8)
var scripted_input := Vector2.ZERO
var scripted_jump := false
var test_mode := false

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	var collider := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.23
	capsule.height = 1.5
	collider.shape = capsule
	collider.position.y = 0.75
	add_child(collider)
	model = Node3D.new()
	add_child(model)
	# Articulated primitives keep the prototype cheap while making actions legible.
	Geo.box(model, Vector3(0, 0.94, 0), Vector3(0.43, 0.50, 0.28), Color("#d9773d"))
	Geo.box(model, Vector3(0, 0.69, 0), Vector3(0.36, 0.16, 0.26), Color("#263448"))
	head = Node3D.new()
	head.position.y = 1.30
	model.add_child(head)
	Geo.sphere(head, Vector3(0, 0.11, 0), 0.23, Color("#d5a17e"))
	Geo.sphere(head, Vector3(0, 0.23, 0.06), 0.23, Color("#3b2945"))
	Geo.sphere(head, Vector3(0.05, 0.07, 0.31), 0.16, Color("#3b2945"))
	for side in [-1.0, 1.0]:
		Geo.box(head, Vector3(side * 0.08, 0.12, -0.208), Vector3(0.04, 0.045, 0.025), Color("#302b37"))
	Geo.box(model, Vector3(0, 1.18, -0.05), Vector3(0.49, 0.07, 0.32), Color("#dbb960"))
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		model.add_child(leg)
		leg.position = Vector3(side * 0.13, 0.68, 0)
		Geo.box(leg, Vector3(0, -0.155, 0), Vector3(0.17, 0.31, 0.20), Color("#263448"))
		var knee := Node3D.new()
		leg.add_child(knee)
		knee.position.y = -0.31
		Geo.sphere(knee, Vector3.ZERO, 0.09, Color("#263448"))
		Geo.box(knee, Vector3(0, -0.13, 0), Vector3(0.16, 0.26, 0.18), Color("#263448"))
		var foot := Geo.box(knee, Vector3(0, -0.29, -0.06), Vector3(0.22, 0.16, 0.34), Color("#141c2a"))
		knees.append(knee)
		feet.append(foot)
		if side < 0:
			left_leg = leg
		else:
			right_leg = leg
		var upper := Geo.box(model, Vector3.ZERO, Vector3(0.14, 1.0, 0.16), Color("#d9773d"))
		var fore := Geo.box(model, Vector3.ZERO, Vector3(0.12, 1.0, 0.13), Color("#d9773d"))
		var elbow := Geo.sphere(model, Vector3.ZERO, 0.075, Color("#d9773d"))
		var palm := Geo.sphere(model, Vector3.ZERO, 0.085, Color("#d5a17e"))
		arms.append({"shoulder": Vector3(side * 0.28, 1.12, 0), "upper": upper, "fore": fore, "elbow": elbow, "palm": palm})
	hand = Node3D.new()
	model.add_child(hand)
	hand.position = Vector3(0.38, 1.02, -0.46)
	pivot = Node3D.new()
	get_parent().add_child.call_deferred(pivot)
	arm = SpringArm3D.new()
	arm.spring_length = 8.0
	arm.margin = 0.20
	var camera_shape := SphereShape3D.new()
	camera_shape.radius = 0.28
	arm.shape = camera_shape
	arm.collision_mask = 1
	pivot.add_child(arm)
	arm.add_excluded_object(get_rid())
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 450.0
	arm.add_child(camera)
	camera.current = true
	position = spawn_point
	pivot.position = position + Vector3(0, 1.25, 0)
	pivot.rotation = Vector3(pitch, yaw, 0)
	_update_pose(0.0)

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event.is_action_pressed("sit") and not event.is_echo():
		toggle_seat()
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.003
		pitch = clampf(pitch - event.relative.y * 0.003, -1.0, 0.18)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			arm.spring_length = maxf(4.0, arm.spring_length - 0.6)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			arm.spring_length = minf(12.0, arm.spring_length + 0.6)

func can_sit() -> bool:
	return enabled and not carrying and is_on_floor() and absf(position.y - SEAT_POINT.y) < 0.2 and Vector2(position.x, position.z).distance_to(Vector2(SEAT_POINT.x, SEAT_POINT.z)) < 1.05

func toggle_seat() -> bool:
	if not enabled:
		return false
	if seated:
		stand_up()
		return true
	if not can_sit():
		return false
	seated = true
	position.x = SEAT_POINT.x
	position.z = SEAT_POINT.z
	velocity = Vector3.ZERO
	model.rotation.y = 0.0
	_update_pose(0.0)
	return true

func stand_up() -> void:
	seated = false
	if is_instance_valid(model):
		_update_pose(0.0)

func seat_prompt() -> String:
	if seated:
		return "F / WASD — встать    Пробел — прыгнуть"
	return "F — сесть рядом с сиденьем" if can_sit() else ""

func _physics_process(delta: float) -> void:
	if not enabled:
		# Let a jump finish naturally when the route ends.
		if not outcome.is_empty() and not seated:
			velocity.x = 0
			velocity.z = 0
			velocity.y -= GRAVITY * delta
			move_and_slide()
			_rescue_if_needed()
		return
	var axis := scripted_input if test_mode else Input.get_vector("left", "right", "forward", "back")
	var jump := scripted_jump if test_mode else Input.is_action_just_pressed("jump")
	scripted_jump = false
	if seated and (axis.length_squared() > 0.01 or jump or carrying):
		stand_up()
	var direction := Vector3(axis.x, 0, axis.y).rotated(Vector3.UP, yaw)
	var speed := CARRY_SPEED if carrying else WALK_SPEED
	velocity.x = move_toward(velocity.x, direction.x * speed, 28.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 28.0 * delta)
	coyote = 0.12 if is_on_floor() else maxf(0.0, coyote - delta)
	if jump and coyote > 0.0:
		velocity.y = JUMP_SPEED
		coyote = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if direction.length_squared() > 0.01:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-direction.x, -direction.z), delta * 14.0)
	_rescue_if_needed()

func _rescue_if_needed() -> void:
	if position.y < -2.0 or absf(position.x) > 12.0 or absf(position.z) > 15.0:
		reset_position()
		rescued.emit()

func _process(delta: float) -> void:
	if enabled or not outcome.is_empty():
		pose_time += delta
		_update_pose(delta)
	if not is_instance_valid(pivot) or not pivot.is_inside_tree():
		return
	if not outcome.is_empty():
		if outcome == "won" and not seated:
			model.rotation.y = lerp_angle(model.rotation.y, PI + 0.55, 1.0 - exp(-delta * 3.0))
		yaw = lerp_angle(yaw, 0.55, 1.0 - exp(-delta * 2.0))
		pitch = lerpf(pitch, -0.25, 1.0 - exp(-delta * 2.0))
		arm.spring_length = move_toward(arm.spring_length, 5.0, delta * 2.0)
	var target := global_position + Vector3(0, 1.05 if seated else 1.25, 0)
	pivot.global_position = pivot.global_position.lerp(target, 1.0 - exp(-delta * 12.0))
	pivot.rotation = Vector3(pitch, yaw, 0)

func _update_pose(delta: float) -> void:
	var speed := Vector2(velocity.x, velocity.z).length() if enabled and is_on_floor() else 0.0
	gait += delta * speed * 2.8
	var stride := sin(gait) * minf(speed * 0.12, 0.48)
	model.position.y = -0.23 if seated else 0.0
	left_leg.rotation.x = PI / 2.0 if seated else stride
	right_leg.rotation.x = PI / 2.0 if seated else -stride
	for index in range(2):
		knees[index].rotation.x = -PI / 2.0 if seated else -maxf(0.0, (stride if index == 0 else -stride)) * 0.6
	head.rotation.x = sin(pose_time * 5.0) * 0.08 if outcome == "won" else (0.22 if outcome == "lost" else 0.0)
	var targets := [Vector3(-0.28, 0.57, stride * 0.28), Vector3(0.28, 0.57, -stride * 0.28)]
	if seated:
		targets = [Vector3(-0.26, 0.78, -0.39), Vector3(0.26, 0.78, -0.39)]
	if not is_on_floor() and enabled:
		targets = [Vector3(-0.56, 0.98, -0.1), Vector3(0.56, 0.98, -0.1)]
	if outcome == "won" and not carrying:
		# A brief wave settles into a raised, relaxed hand.
		var wave := sin(pose_time * 9.0) * maxf(0.0, 1.0 - pose_time / 2.6)
		targets[1] = Vector3(0.55 + wave * 0.10, 1.52, -0.12)
	if carrying:
		targets = [hand.position + Vector3(-0.31, -0.06, 0.15), hand.position + Vector3(0.31, -0.06, 0.15)]
	for index in range(2):
		_pose_arm(arms[index], targets[index])

func _pose_arm(limb: Dictionary, target: Vector3) -> void:
	var shoulder: Vector3 = limb.shoulder
	var direction := (target - shoulder).normalized()
	var reach := clampf(shoulder.distance_to(target), 0.025, UPPER_ARM + FOREARM - 0.001)
	var along := (UPPER_ARM * UPPER_ARM - FOREARM * FOREARM + reach * reach) / (2.0 * reach)
	var bend := Vector3.DOWN - direction * Vector3.DOWN.dot(direction)
	if bend.length_squared() < 0.001:
		bend = Vector3.BACK
	bend = bend.normalized()
	var elbow := shoulder + direction * along + bend * sqrt(maxf(0.0, UPPER_ARM * UPPER_ARM - along * along))
	var palm := shoulder + direction * reach
	_set_segment(limb.upper, shoulder, elbow)
	_set_segment(limb.fore, elbow, palm)
	limb.elbow.position = elbow
	limb.palm.position = palm

func _set_segment(segment: Node3D, from: Vector3, to: Vector3) -> void:
	var axis := (to - from).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized()
	if side.length_squared() < 0.001:
		side = Vector3.RIGHT
	segment.transform = Transform3D(Basis(side, axis, side.cross(axis)).scaled_local(Vector3(1, from.distance_to(to), 1)), (from + to) * 0.5)

func play_outcome(won: bool) -> void:
	outcome = "won" if won else "lost"
	pose_time = 0.0
	velocity.x = 0.0
	velocity.z = 0.0
	_update_pose(0.0)

func reset_position() -> void:
	stand_up()
	position = spawn_point
	velocity = Vector3.ZERO
	if is_instance_valid(pivot) and pivot.is_inside_tree():
		pivot.global_position = global_position + Vector3(0, 1.25, 0)
