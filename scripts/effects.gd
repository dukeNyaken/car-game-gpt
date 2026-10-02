extends Node3D
const Geo = preload("res://scripts/geometry.gd")
var game: Node3D
var flames: Array[MeshInstance3D] = []
var temporary: Array[Dictionary] = []
var shots_fired := 0

func build(owner_game: Node3D) -> void:
	game = owner_game
	for side in [-1.0, 1.0]:
		var port := Geo.cylinder(self, Vector3(side * 1.85, 1.6, 3.6), 0.3, 0.5, Color("#354651"))
		var flame := Geo.cylinder(self, port.position + Vector3(0, -0.8, 0), 0.22, 1.4, Color("#aeafff"))
		var mesh := flame.mesh as CylinderMesh
		mesh.bottom_radius = 0.025
		flame.material_override = Geo.material(Color("#aaaaff"), 1.0)
		flame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		flame.visible = false
		flames.append(flame)

func fire(origin: Vector3, target: Vector3) -> void:
	shots_fired += 1
	var offset := target - origin
	var beam := Geo.cylinder(self, (origin + target) * 0.5, 0.055, offset.length(), Color("#fff0b4"))
	beam.quaternion = Quaternion(Vector3.UP, offset.normalized())
	beam.material_override = Geo.material(Color("#fff0b4"), 1.0)
	temporary.append({"node": beam, "left": 0.22, "total": 0.22, "velocity": Vector3.ZERO, "grow": false})
	burst(target, Color("#ffd3a0"))

func burst(center: Vector3, color: Color) -> void:
	for index in range(10):
		var angle := TAU * index / 10
		var spark := Geo.sphere(self, center, 0.14, color)
		spark.material_override = Geo.material(color, 0.6)
		var direction := Vector3(sin(angle), 0.35 + float(index % 3) * 0.3, cos(angle)).normalized()
		temporary.append({"node": spark, "left": 0.65, "total": 0.65, "velocity": direction * 3.2, "grow": false})

func _process(delta: float) -> void:
	if not is_instance_valid(game) or game.state == "paused":
		return
	for index in range(flames.size()):
		var flame := flames[index]
		flame.visible = game.state == "running" and game.modules.has_module("flight")
		flame.scale.y = (1.0 if game.lift > 0.15 else 0.22) * (0.86 + 0.14 * sin(game.elapsed * 35 + index))
	for index in range(temporary.size() - 1, -1, -1):
		var effect: Dictionary = temporary[index]
		effect.left -= delta
		if effect.left <= 0:
			effect.node.queue_free()
			temporary.remove_at(index)
			continue
		effect.node.position += effect.velocity * delta
		effect.node.scale = Vector3.ONE * maxf(0.05, float(effect.left) / float(effect.total))
