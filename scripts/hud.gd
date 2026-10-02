extends CanvasLayer
signal play_requested(practice: bool)
const INK := Color("#eaf1ed")
var game: Node3D
var status: Label
var power: Label
var prompt_label: Label
var notice: Label
var threat: Label
var gap_bar: ProgressBar
var progress_bar: ProgressBar
var overlay: Control
var heading: Label
var explanation: Label
var start_button: Button
var practice_button: Button
var feedback_time := 0.0
var guide_panel: Panel
var guide_label: Label
var mute_label: Label
var seat_label: Label

func build(owner_game: Node3D) -> void:
	game = owner_game
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	var top := _panel(root, Vector2(24, 20), Vector2(370, 99))
	var title := _label(top, Vector2(16, 10), Vector2(340, 24), "ТОЛЬКО САМОЕ НУЖНОЕ", 20)
	title.modulate = Color("#efc785")
	status = _label(top, Vector2(16, 42), Vector2(340, 42), "", 16)
	var chase := _panel(root, Vector2(-330, 20), Vector2(306, 99))
	chase.anchor_left = 1.0
	chase.anchor_right = 1.0
	_label(chase, Vector2(16, 10), Vector2(280, 24), "ДИСТАНЦИЯ ДО ПОГОНИ", 15)
	gap_bar = ProgressBar.new()
	gap_bar.position = Vector2(16, 43)
	gap_bar.size = Vector2(274, 20)
	gap_bar.max_value = 150
	gap_bar.show_percentage = false
	chase.add_child(gap_bar)
	progress_bar = ProgressBar.new()
	progress_bar.anchor_right = 1.0
	progress_bar.offset_top = 0
	progress_bar.offset_bottom = 5
	progress_bar.show_percentage = false
	root.add_child(progress_bar)
	threat = _label(root, Vector2(-310, 132), Vector2(620, 66), "", 23)
	threat.anchor_left = 0.5
	threat.anchor_right = 0.5
	threat.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	threat.add_theme_color_override("font_color", Color("#ffd393"))
	guide_panel = _panel(root, Vector2(-330, 135), Vector2(306, 155))
	guide_panel.anchor_left = 1.0
	guide_panel.anchor_right = 1.0
	_label(guide_panel, Vector2(16, 10), Vector2(274, 24), "ПОМОЩЬ РОБОТУ", 16)
	guide_label = _label(guide_panel, Vector2(16, 39), Vector2(274, 104), "", 16)
	guide_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	mute_label = _label(root, Vector2(-300, -42), Vector2(275, 22), "", 13)
	mute_label.anchor_left = 1.0
	mute_label.anchor_right = 1.0
	mute_label.anchor_top = 1.0
	mute_label.anchor_bottom = 1.0
	mute_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	var bottom := _panel(root, Vector2(24, -142), Vector2(430, 118))
	bottom.anchor_top = 1.0
	bottom.anchor_bottom = 1.0
	power = _label(bottom, Vector2(16, 12), Vector2(400, 96), "", 16)
	prompt_label = _label(root, Vector2(-345, -68), Vector2(690, 45), "", 20)
	prompt_label.anchor_left = 0.57
	prompt_label.anchor_right = 0.57
	prompt_label.anchor_top = 1.0
	prompt_label.anchor_bottom = 1.0
	prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice = _label(root, Vector2(-350, -119), Vector2(700, 42), "", 18)
	notice.anchor_left = 0.57
	notice.anchor_right = 0.57
	notice.anchor_top = 1.0
	notice.anchor_bottom = 1.0
	notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	notice.modulate = Color("#a3ecd1")
	seat_label = _label(root, Vector2(24, -175), Vector2(455, 25), "", 16)
	seat_label.anchor_top = 1.0
	seat_label.anchor_bottom = 1.0
	seat_label.modulate = Color("#efc785")
	var controls := _label(root, Vector2(-315, -170), Vector2(290, 77), "WASD — идти   Мышь — камера\nПробел — прыгнуть   E — модуль\nTab — крепления   Esc — пауза", 14)
	controls.anchor_left = 1.0
	controls.anchor_right = 1.0
	controls.anchor_top = 1.0
	controls.anchor_bottom = 1.0
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	overlay = Control.new()
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(overlay)
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.04, 0.07, 0.84)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(shade)
	var menu := _panel(overlay, Vector2(-330, -235), Vector2(660, 470))
	menu.anchor_left = 0.5
	menu.anchor_right = 0.5
	menu.anchor_top = 0.5
	menu.anchor_bottom = 0.5
	heading = _label(menu, Vector2(30, 24), Vector2(600, 55), "ДЕРЖИСЬ, НАПАРНИК!", 32)
	explanation = _label(menu, Vector2(30, 91), Vector2(600, 235), "", 19)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	start_button = Button.new()
	start_button.position = Vector2(30, 340)
	start_button.size = Vector2(600, 48)
	start_button.text = "ПОЕХАЛИ  •  ENTER"
	start_button.add_theme_font_size_override("font_size", 20)
	menu.add_child(start_button)
	start_button.pressed.connect(func(): play_requested.emit(false))
	practice_button = Button.new()
	practice_button.position = Vector2(30, 401)
	practice_button.size = Vector2(600, 42)
	practice_button.text = "Сначала освоиться на роботе  •  T"
	menu.add_child(practice_button)
	practice_button.pressed.connect(func(): play_requested.emit(true))
	show_menu("title")

func _panel(parent: Control, pos: Vector2, dimensions: Vector2) -> Panel:
	var panel := Panel.new()
	parent.add_child(panel)
	panel.position = pos
	panel.size = dimensions
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color("#13242e")
	style.border_color = Color("#466370")
	style.set_border_width_all(1)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _label(parent: Control, pos: Vector2, dimensions: Vector2, text: String, font_size: int) -> Label:
	var label := Label.new()
	parent.add_child(label)
	label.position = pos
	label.size = dimensions
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", INK)
	label.add_theme_color_override("font_shadow_color", Color("#101920"))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 2)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func show_menu(state: String) -> void:
	overlay.visible = true
	practice_button.visible = state == "title"
	start_button.text = "ПРОДОЛЖИТЬ  •  ENTER" if state == "paused" else "ПОЕХАЛИ  •  ENTER"
	match state:
		"title":
			heading.text = "ДЕРЖИСЬ, НАПАРНИК!"
			explanation.text = "Ты на спине своего робота. Он бежит сам — помоги ему уйти от погони.\n\nWASD и мышь — доберись до головы или рук.\nПробел — перепрыгни. E — возьми или поставь модуль.\n\nРаботают только два модуля. Сними один, отнеси в запас и подключи нужный. Руль уже на голове, двигатель сзади. Остальные ждут на спине."
		"paused":
			heading.text = "ПЕРЕДЫШКА"
			explanation.text = "WASD — движение по корпусу\nМышь — обзор; колесо — расстояние камеры\nПробел — прыжок между площадками\nE — взять / установить ближайший модуль\n\nРобот сам применяет подключённые функции.\nF — сесть / встать рядом с сиденьем.\nTab — все крепления; M — звук; R — заново."
		"won":
			heading.text = "ОТОРВАЛИСЬ!"
			explanation.text = "Вы добрались до укрытия вместе.\n\nДевушка машет напарнику. Робот щурится от радости — мы справились вместе.\n\nЭто первый маршрут. Можно попробовать другой набор модулей."
			start_button.text = "ЕЩЁ РАЗ  •  ENTER"
		"lost":
			heading.text = "ПОГОНЯ ДОГНАЛА"
			explanation.text = "Робот успел прикрыть тебя, но оторваться не вышло.\n\nСледи за предупреждением заранее. При полном питании сначала убери работающий модуль в запас.\n\nРакету можно встретить щитом или сбить пушкой."
			start_button.text = "ПОПРОБОВАТЬ СНОВА  •  ENTER"

func show_feedback(message: String) -> void:
	notice.text = message
	feedback_time = 4.0

func _process(delta: float) -> void:
	if not is_instance_valid(game):
		return
	feedback_time = maxf(0.0, feedback_time - delta)
	notice.visible = feedback_time > 0
	var modules: Node3D = game.modules
	var carried := "ничего" if modules.held.is_empty() else String(modules.DEFINITIONS[modules.held].short)
	power.text = "ПИТАНИЕ  %d / 2\n%s\nВ руках: %s" % [modules.active_count(), modules.active_names(), carried]
	status.text = ("ТРЕНИРОВКА • без давления" if game.practice else "Путь %d / %d м   •   %d км/ч" % [game.distance, game.ROUTE_LENGTH, game.speed * 3.6])
	if not game.practice and game.slowdown_timer > 0:
		status.text += "\nПосле удара: %.1f с" % game.slowdown_timer
	gap_bar.value = game.chase_distance
	progress_bar.value = game.distance / game.ROUTE_LENGTH * 100.0
	prompt_label.text = modules.prompt() if game.state == "running" else ""
	seat_label.text = game.player.seat_prompt() if game.state == "running" else ""
	threat.text = game.warning_text()
	var hint: Dictionary = modules.guidance(game.practice)
	modules.focus_index = int(hint.index) if game.state == "running" else -1
	guide_panel.visible = game.state == "running" and not String(hint.text).is_empty()
	guide_label.text = hint.text
	mute_label.text = "M — звук: выкл." if game.sound.muted else "M — звук: вкл."
	var seconds: float = game.nearest_missile_seconds()
	threat.modulate = Color("#ffb097") if seconds > 0 and seconds < 6.0 else Color.WHITE
