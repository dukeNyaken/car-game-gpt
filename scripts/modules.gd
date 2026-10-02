extends Node3D
## Physical objects plus hardpoints. Power is derived from occupancy, never cached.
signal changed
signal feedback(message: String)
const Geo = preload("res://scripts/geometry.gd")
const POWER_LIMIT := 2
const REACH := 1.85
const DEFINITIONS := {
	"engine": {"name": "ДВИГАТЕЛЬ", "short": "Двигатель", "color": Color("#f2b74f")},
	"steering": {"name": "РУЛЬ", "short": "Руль", "color": Color("#56d3b1")},
	"flight": {"name": "ТУРБИНЫ", "short": "Турбины", "color": Color("#a3a0ff")},
	"shield": {"name": "ЩИТ", "short": "Щит", "color": Color("#69bafa")},
	"cannon": {"name": "ПУШКА", "short": "Пушка", "color": Color("#f47e78")}
}
var mounts: Array[Dictionary] = []
var objects: Dictionary = {}
var held := ""
var selected := -1
var player: CharacterBody3D
var enabled := false

func build(actor: CharacterBody3D) -> void:
	player = actor
	_add_mount("engine", Vector3(0, 3.32, 2.5), "engine")
	_add_mount("steering", Vector3(0, 4.22, -4.1), "steering")
	_add_mount("flight", Vector3(-1.85, 3.32, 1.5), "")
	_add_mount("shield", Vector3(4.2, 3.52, -0.6), "")
	_add_mount("cannon", Vector3(-4.2, 3.52, -0.6), "")
	_add_mount("storage", Vector3(-1.8, 3.32, -1.5), "flight")
	_add_mount("storage", Vector3(0, 3.32, -1.5), "shield")
	_add_mount("storage", Vector3(1.8, 3.32, -1.5), "cannon")
	_add_mount("storage", Vector3(1.8, 3.32, 1.5), "")
	for kind: String in DEFINITIONS:
		var item := Node3D.new()
		add_child(item)
		objects[kind] = item
		var color: Color = DEFINITIONS[kind].color
		Geo.box(item, Vector3.ZERO, Vector3(0.62, 0.45, 0.6), color)
		Geo.box(item, Vector3(0, -0.26, 0), Vector3(0.36, 0.1, 0.38), Color("#182232"))
		match kind:
			"engine":
				Geo.cylinder(item, Vector3(-0.22, 0.18, 0), 0.14, 0.45, Color("#273846"))
				Geo.cylinder(item, Vector3(0.22, 0.18, 0), 0.14, 0.45, Color("#273846"))
			"steering":
				var wheel := Geo.cylinder(item, Vector3(0, 0.4, 0), 0.3, 0.09, color)
				wheel.rotation.x = PI / 3.0
			"flight":
				for side in [-1, 1]:
					Geo.cylinder(item, Vector3(side * 0.35, 0, 0), 0.2, 0.65, Color("#6d6aaf"))
			"shield":
				Geo.sphere(item, Vector3(0, 0.2, 0), 0.3, color)
			"cannon":
				var barrel := Geo.cylinder(item, Vector3(0, 0.3, -0.35), 0.12, 0.75, Color("#354453"))
				barrel.rotation.x = PI / 2.0
	_sync_objects()
	_refresh_labels()

func _add_mount(kind: String, pos: Vector3, occupant: String) -> void:
	var node := Node3D.new()
	add_child(node)
	node.position = pos
	var color := Color("#607486") if kind == "storage" else Color(DEFINITIONS[kind].color)
	var pad := Geo.cylinder(node, Vector3(0, 0.06, 0), 0.56, 0.12, color)
	Geo.box(node, Vector3(0, 0.12, 0), Vector3(0.65, 0.10, 0.65), Color("#16232e"))
	var label := Geo.label(node, Vector3(0, 1.18, 0), "", color, 24)
	mounts.append({"kind": kind, "node": node, "pad": pad, "label": label, "occupant": occupant})

func has_module(kind: String) -> bool:
	for mount: Dictionary in mounts:
		if mount.kind != "storage" and mount.occupant == kind:
			return true
	return false

func active_count() -> int:
	var count := 0
	for mount: Dictionary in mounts:
		if mount.kind != "storage" and not String(mount.occupant).is_empty():
			count += 1
	return count

func active_names() -> String:
	var names := PackedStringArray()
	for kind: String in DEFINITIONS:
		if has_module(kind):
			names.append(DEFINITIONS[kind].short)
	return " + ".join(names)

func nearest_mount() -> int:
	var result := -1
	var best := REACH
	for index in range(mounts.size()):
		var target: Vector3 = mounts[index].node.global_position + Vector3(0, 0.55, 0)
		var distance := (player.global_position + Vector3(0, 0.85, 0)).distance_to(target)
		if distance < best and in_reach(index):
			result = index
			best = distance
	return result

func in_reach(index: int) -> bool:
	var mount: Dictionary = mounts[index]
	var target: Vector3 = mount.node.global_position + Vector3(0, 0.55, 0)
	if (player.global_position + Vector3(0, 0.85, 0)).distance_to(target) > REACH:
		return false
	# You must actually reach the head/arm, not operate it from the main deck.
	if player.position.y < mount.node.position.y - 0.35:
		return false
	if mount.kind == "steering" and player.position.z > -3.25:
		return false
	if mount.kind == "shield" and player.position.x < 3.15:
		return false
	if mount.kind == "cannon" and player.position.x > -3.15:
		return false
	return true

func _process(_delta: float) -> void:
	if not is_instance_valid(player):
		return
	selected = nearest_mount() if enabled else -1
	for index in range(mounts.size()):
		var pad: MeshInstance3D = mounts[index].pad
		pad.scale = Vector3.ONE * (1.18 if index == selected else 1.0)
		var label: Label3D = mounts[index].label
		label.modulate.a = 1.0 if index == selected else 0.7
	if enabled and Input.is_action_just_pressed("interact"):
		interact(selected)
	if not held.is_empty():
		var item: Node3D = objects[held]
		item.global_transform = player.hand.global_transform

func prompt() -> String:
	if selected < 0:
		return "Подойди к креплению • E — взять / установить"
	var mount: Dictionary = mounts[selected]
	if held.is_empty():
		if String(mount.occupant).is_empty():
			return "Пустое крепление • принеси модуль"
		return "E  Взять: " + String(DEFINITIONS[mount.occupant].short)
	if not String(mount.occupant).is_empty():
		return "Крепление занято • сначала убери модуль"
	if mount.kind == "storage":
		return "E  Оставить в запасе: " + String(DEFINITIONS[held].short)
	if mount.kind != held:
		return "Это крепление для: " + String(DEFINITIONS[mount.kind].short)
	if active_count() >= POWER_LIMIT:
		return "Питание 2 / 2 • сначала сними один активный модуль"
	return "E  Подключить: " + String(DEFINITIONS[held].short)

func interact(index: int) -> bool:
	# Range is checked here too, not only when the prompt is selected.
	if index < 0 or index >= mounts.size():
		return false
	var mount: Dictionary = mounts[index]
	var target: Vector3 = mount.node.global_position + Vector3(0, 0.55, 0)
	if not in_reach(index):
		feedback.emit("Нужно подойти ближе.")
		return false
	if held.is_empty():
		if String(mount.occupant).is_empty():
			return false
		held = mount.occupant
		mounts[index].occupant = ""
		player.carrying = true
		feedback.emit("В руках: " + String(DEFINITIONS[held].short))
	else:
		if not String(mount.occupant).is_empty():
			feedback.emit("Крепление занято. Отнеси предмет в свободный запас.")
			return false
		if mount.kind != "storage" and mount.kind != held:
			feedback.emit("Модуль не подходит к этому креплению.")
			return false
		if mount.kind != "storage" and active_count() >= POWER_LIMIT:
			feedback.emit("Оба подключения заняты. Сначала сними активный модуль.")
			return false
		mounts[index].occupant = held
		feedback.emit(("В запасе: " if mount.kind == "storage" else "Подключено: ") + String(DEFINITIONS[held].short))
		held = ""
		player.carrying = false
	_sync_objects()
	_refresh_labels()
	changed.emit()
	return true

func _sync_objects() -> void:
	for mount: Dictionary in mounts:
		if not String(mount.occupant).is_empty():
			var item: Node3D = objects[mount.occupant]
			item.global_transform = mount.node.global_transform
			item.position.y += 0.49
	if not held.is_empty():
		objects[held].global_transform = player.hand.global_transform

func _refresh_labels() -> void:
	for mount: Dictionary in mounts:
		var label: Label3D = mount.label
		if mount.kind == "storage":
			label.text = "ЗАПАС" if String(mount.occupant).is_empty() else String(DEFINITIONS[mount.occupant].name) + "\nзапас"
		else:
			label.text = String(DEFINITIONS[mount.kind].name) + ("\n● ВКЛ" if not String(mount.occupant).is_empty() else "\n○")

func invariants_ok() -> bool:
	var counts: Dictionary = {}
	for kind: String in DEFINITIONS:
		counts[kind] = 0
	for mount: Dictionary in mounts:
		var occupant := String(mount.occupant)
		if not occupant.is_empty():
			counts[occupant] += 1
			if mount.kind != "storage" and mount.kind != occupant:
				return false
	if not held.is_empty():
		counts[held] += 1
	for kind: String in counts:
		if counts[kind] != 1:
			return false
	return active_count() <= POWER_LIMIT
