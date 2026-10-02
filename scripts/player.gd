extends CharacterBody3D

signal rescued
const Geo = preload("res://scripts/geometry.gd")
const WALK_SPEED := 4.2
const CARRY_SPEED := 3.4
const JUMP_SPEED := 7.6
const GRAVITY := 20.0
var enabled := false
var carrying := false
var yaw := 0.0
var pitch := -0.4
var model: Node3D
var hand: Node3D
var pivot: Node3D
var arm: SpringArm3D
var camera: Camera3D
var left_leg: Node3D
var right_leg: Node3D
var left_hand: Node3D
var right_hand: Node3D
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
	# Simple readable girl silhouette: orange jacket, dark trousers, ponytail.
	Geo.box(model, Vector3(0, 0.94, 0), Vector3(0.47, 0.52, 0.28), Color("#ef9652"))
	Geo.sphere(model, Vector3(0, 1.41, 0), 0.23, Color("#e9b897"))
	Geo.sphere(model, Vector3(0, 1.52, 0.07), 0.23, Color("#3b2945"))
	Geo.sphere(model, Vector3(0.05, 1.37, 0.31), 0.16, Color("#3b2945"))
	Geo.box(model, Vector3(0, 1.18, -0.05), Vector3(0.55, 0.08, 0.32), Color("#f4d776"))
	for side in [-1.0, 1.0]:
		var leg := Node3D.new()
		model.add_child(leg)
		leg.position = Vector3(side * 0.13, 0.68, 0)
		Geo.box(leg, Vector3(0, -0.25, 0), Vector3(0.18, 0.49, 0.21), Color("#263448"))
		Geo.box(leg, Vector3(0, -0.58, -0.06), Vector3(0.22, 0.16, 0.37), Color("#141c2a"))
		var limb := Node3D.new()
		model.add_child(limb)
		limb.position = Vector3(side * 0.30, 1.12, 0)
		Geo.box(limb, Vector3(0, -0.19, 0), Vector3(0.14, 0.39, 0.16), Color("#ef9652"))
		Geo.sphere(limb, Vector3(0, -0.42, 0), 0.09, Color("#e9b897"))
		if side < 0:
			left_leg = leg
			left_hand = limb
		else:
			right_leg = leg
			right_hand = limb
	hand = Node3D.new()
	model.add_child(hand)
	hand.position = Vector3(0.46, 1.04, -0.38)
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

func _unhandled_input(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * 0.003
		pitch = clampf(pitch - event.relative.y * 0.003, -1.0, 0.18)
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			arm.spring_length = maxf(4.0, arm.spring_length - 0.6)
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			arm.spring_length = minf(12.0, arm.spring_length + 0.6)

func _physics_process(delta: float) -> void:
	if not enabled:
		return
	var axis := scripted_input if test_mode else Input.get_vector("left", "right", "forward", "back")
	var direction := Vector3(axis.x, 0, axis.y).rotated(Vector3.UP, yaw)
	var speed := CARRY_SPEED if carrying else WALK_SPEED
	velocity.x = move_toward(velocity.x, direction.x * speed, 28.0 * delta)
	velocity.z = move_toward(velocity.z, direction.z * speed, 28.0 * delta)
	coyote = 0.12 if is_on_floor() else maxf(0.0, coyote - delta)
	var jump := scripted_jump if test_mode else Input.is_action_just_pressed("jump")
	scripted_jump = false
	if jump and coyote > 0.0:
		velocity.y = JUMP_SPEED
		coyote = 0.0
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()
	if direction.length_squared() > 0.01:
		model.rotation.y = lerp_angle(model.rotation.y, atan2(-direction.x, -direction.z), delta * 14.0)
	gait += delta * Vector2(velocity.x, velocity.z).length() * 2.8
	var stride := sin(gait) * minf(Vector2(velocity.x, velocity.z).length() * 0.12, 0.48)
	left_leg.rotation.x = stride
	right_leg.rotation.x = -stride
	left_hand.rotation.x = -1.2 if carrying else -stride * 0.7
	left_hand.rotation.z = 0.9 if carrying else 0.0
	right_hand.rotation.x = -1.2 if carrying else stride * 0.7
	if position.y < -2.0 or absf(position.x) > 12.0 or absf(position.z) > 15.0:
		reset_position()
		rescued.emit()

func _process(delta: float) -> void:
	if not is_instance_valid(pivot) or not pivot.is_inside_tree():
		return
	var target := global_position + Vector3(0, 1.25, 0)
	pivot.global_position = pivot.global_position.lerp(target, 1.0 - exp(-delta * 12.0))
	pivot.rotation = Vector3(pitch, yaw, 0)

func reset_position() -> void:
	position = spawn_point
	velocity = Vector3.ZERO
	if is_instance_valid(pivot) and pivot.is_inside_tree():
		pivot.global_position = global_position + Vector3(0, 1.25, 0)
