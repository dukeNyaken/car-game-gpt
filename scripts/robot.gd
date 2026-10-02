extends Node3D
const Geo = preload("res://scripts/geometry.gd")
var eyes: Array[MeshInstance3D] = []
var wheels: Array[MeshInstance3D] = []
var glow_shield: MeshInstance3D
var reaction := ""
var reaction_until := 0.0
var steering_angle := 0.0
var ending := ""
var brows: Array[MeshInstance3D] = []

func _ready() -> void:
	var hull := Color("#4e6973")
	var top := Color("#89a6a3")
	var dark := Color("#253a48")
	Geo.box(self, Vector3(0, 2.25, 0), Vector3(5.4, 2.1, 6.4), hull, true)
	Geo.box(self, Vector3(0, 3.32, 0), Vector3(5.35, 0.04, 6.3), top)
	# Raised head and separate arms: reaching them requires a jump.
	Geo.box(self, Vector3(0, 3.6, -4.2), Vector3(2.6, 1.2, 2.1), top, true)
	Geo.box(self, Vector3(0, 3.58, -5.28), Vector3(2.28, 0.74, 0.06), dark)
	for side in [-1.0, 1.0]:
		Geo.sphere(self, Vector3(side * 2.9, 2.7, -0.6), 0.5, dark)
		Geo.box(self, Vector3(side * 4.2, 3.1, -0.6), Vector3(2.0, 0.8, 3.0), top, true)
		Geo.box(self, Vector3(side * 4.2, 2.7, -1.7), Vector3(1.8, 0.8, 1.1), hull)
		# Front and rear running gear.
		for z in [-2.0, 2.0]:
			var wheel := Geo.cylinder(self, Vector3(side * 2.25, 0.9, z), 0.9, 0.75, dark)
			wheel.rotation.z = PI / 2.0
			wheels.append(wheel)
			var hub := Geo.cylinder(self, Vector3(side * 2.67, 0.9, z), 0.38, 0.06, Color("#e2b66f"))
			hub.rotation.z = PI / 2.0
		var eye := Geo.box(self, Vector3(side * 0.55, 3.68, -5.34), Vector3(0.42, 0.2, 0.05), Color("#7df3d3"))
		eye.material_override = Geo.material(Color("#7df3d3"), 1.0)
		eyes.append(eye)
	# A rear head display lets the girl and chase camera see the companion's response.
	Geo.box(self, Vector3(0, 3.65, -3.12), Vector3(1.65, 0.5, 0.06), dark)
	for side in [-1.0, 1.0]:
		eyes.append(Geo.box(self, Vector3(side * 0.36, 3.66, -3.075), Vector3(0.26, 0.13, 0.03), Color("#7df3d3")))
		brows.append(Geo.box(self, Vector3(side * 0.36, 3.83, -3.07), Vector3(0.3, 0.035, 0.03), Color("#7df3d3")))
	# Walking stripes and a small seat imply usable surfaces.
	for z in [-0.9, -0.25, 0.4, 1.05]:
		Geo.box(self, Vector3(0, 3.35, z), Vector3(0.6, 0.02, 0.12), Color("#d1d7bd"))
	Geo.box(self, Vector3(0, 3.6, 1.65), Vector3(0.85, 0.18, 0.5), Color("#bb7548"))
	Geo.box(self, Vector3(0, 3.88, 1.9), Vector3(0.85, 0.5, 0.15), dark)
	# Back-facing eyes keep the companion expressive from the gameplay camera.
	Geo.box(self, Vector3(0, 2.65, 3.24), Vector3(1.5, 0.55, 0.05), dark)
	for side in [-1.0, 1.0]:
		var eye := Geo.box(self, Vector3(side * 0.35, 2.69, 3.29), Vector3(0.2, 0.15, 0.04), Color("#7df3d3"))
		eyes.append(eye)
		brows.append(Geo.box(self, Vector3(side * 0.35, 2.9, 3.3), Vector3(0.3, 0.035, 0.03), Color("#7df3d3")))
	Geo.label(self, Vector3(0, 4.55, -3.0), "ГОЛОВА ↑  ·  ПРОБЕЛ", Color("#c1ddd2"), 20)
	glow_shield = Geo.sphere(self, Vector3(0, 2.7, 0), 1.0, Color("#69bafa"))
	glow_shield.scale = Vector3(5.8, 4.5, 7.0)
	var shield_mat := Geo.material(Color(0.25, 0.65, 1.0, 0.12), 0.3)
	shield_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shield_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	glow_shield.material_override = shield_mat
	glow_shield.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	glow_shield.visible = false

func animate(time: float, speed: float, danger: bool, shield: bool) -> void:
	for index in range(wheels.size()):
		var wheel := wheels[index]
		wheel.rotation.x = time * speed * 0.4
		wheel.rotation.y = steering_angle if index % 2 == 0 else 0.0
	for eye in eyes:
		eye.scale.y = 0.2 if fmod(time, 4.8) < 0.13 else (1.4 if danger else 1.0)
		if time < reaction_until:
			eye.scale.y = 0.45 if reaction == "happy" else 1.65
		if ending == "won":
			eye.scale.y = 0.4
		elif ending == "lost":
			eye.scale.y = 0.65
	for index in range(brows.size()):
		var side := -1.0 if index % 2 == 0 else 1.0
		brows[index].rotation.z = side * (0.25 if ending == "won" else (-0.3 if ending == "lost" else 0.0))
	glow_shield.visible = shield

func react(emotion: String, time: float) -> void:
	reaction = emotion
	reaction_until = time + 0.85
