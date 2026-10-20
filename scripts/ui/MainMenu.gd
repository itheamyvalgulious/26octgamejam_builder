class_name MainMenu
extends Control

const UI = preload("res://scripts/ui/UIStyle.gd")
const Campaign = preload("res://scripts/core/Campaign.gd")
const UI_ANIMATED_ICON = preload("res://scripts/ui/UIAnimatedIcon.gd")
const MAIN_MENU_FONT = preload("res://assets/fonts/font.ttf")

var title_label: Node
var settings_menu: SettingsMenu

func _ready() -> void:
	if title_label != null:
		return
	KeybindManager.init_keybinds()
	SaveManager.init_directories()
	theme = UI.get_theme()
	MusicManager.play_ambient()
	_build_ui()

func _build_ui() -> void:
	UI.add_lab_background(self)

	# Keep the title and the three primary actions centered as one group.
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.offset_top = 60.0
	add_child(center)
	var content := VBoxContainer.new()
	content.custom_minimum_size = Vector2(360, 0)
	content.add_theme_constant_override("separation", 16)
	content.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(content)

	var animated_title := UI_ANIMATED_ICON.new()
	animated_title.name = "TitleAnimation"
	animated_title.configure("res://scenes/animation/title.png", 8, 8.0, Color.WHITE, 2)
	animated_title.custom_minimum_size = Vector2(900, 250)
	animated_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label = animated_title
	content.add_child(animated_title)

	var play := _button(content, "探索章节地图  →")
	UI.primary(play)
	_apply_button_skin(play)
	play.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/LevelSelect.tscn"))

	var learn := _button(content, "第一次来？从基础开始")
	learn.pressed.connect(func():
		_open_tutorial()
	)
	var common_button_width: float = maxf(play.get_combined_minimum_size().x, learn.get_combined_minimum_size().x)
	play.custom_minimum_size = Vector2(common_button_width, 46)
	learn.custom_minimum_size = Vector2(common_button_width, 46)

	var editor := _button(content, "创作工坊")
	editor.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/LevelManager.tscn"))

	# Utility actions stay in the upper-right corner as large icon buttons.
	var top_right := MarginContainer.new()
	top_right.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	top_right.offset_left = -348.0
	top_right.offset_top = 24.0
	top_right.offset_right = -152.0
	top_right.offset_bottom = 88.0
	add_child(top_right)
	var utilities := HBoxContainer.new()
	utilities.alignment = BoxContainer.ALIGNMENT_END
	utilities.add_theme_constant_override("separation", 12)
	top_right.add_child(utilities)

	var settings_button := _icon_button(utilities, "res://assets/ui/icon_settings.png", "系统设置")
	settings_button.pressed.connect(func(): settings_menu.visible = true)
	var manual_button := _icon_button(utilities, "res://assets/ui/icon_manual.png", "操作手册 · F1")
	manual_button.pressed.connect(func(): get_node("/root/OperationManual").open())
	var quit_button := _icon_button(utilities, "res://assets/ui/icon_exit.png", "退出游戏")
	quit_button.pressed.connect(func(): get_tree().quit())

	settings_menu = SettingsMenu.new()
	settings_menu.visible = false
	add_child(settings_menu)

func _button(parent: Node, text: String) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, 46)
	button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	button.add_theme_font_override("font", MAIN_MENU_FONT)
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color("#17232b"))
	button.add_theme_color_override("font_hover_color", Color("#0b151c"))
	button.add_theme_color_override("font_pressed_color", Color("#071017"))
	button.add_theme_color_override("font_outline_color", Color("#b9f06a"))
	button.add_theme_constant_override("outline_size", 2)
	button.resized.connect(func(): button.pivot_offset = button.size * 0.5)
	button.button_down.connect(func(): _animate_button_press(button, true))
	button.button_up.connect(func(): _animate_button_press(button, false))
	button.mouse_exited.connect(func():
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_animate_button_press(button, false)
	)
	_apply_button_skin(button)
	parent.add_child(button)
	return button

func _apply_button_skin(button: Button) -> void:
	var texture: Texture2D = load("res://scenes/animation/button_clean.png")
	for state in ["normal", "hover", "pressed", "disabled"]:
		var style := StyleBoxTexture.new()
		style.texture = texture
		style.texture_margin_left = 28.0
		style.texture_margin_right = 28.0
		style.texture_margin_top = 28.0
		style.texture_margin_bottom = 28.0
		style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
		button.add_theme_stylebox_override(state, style)

func _animate_button_press(button: Button, pressed: bool) -> void:
	var target_scale := Vector2(0.96, 0.96) if pressed else Vector2.ONE
	var target_modulate := Color(0.78, 0.78, 0.78, 1.0) if pressed else Color.WHITE
	var tween := button.create_tween().set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(button, "scale", target_scale, 0.07 if pressed else 0.12)
	tween.tween_property(button, "modulate", target_modulate, 0.07 if pressed else 0.12)

func _open_tutorial() -> void:
	if Campaign.TUTORIAL_ORDER.is_empty():
		get_tree().change_scene_to_file("res://scenes/ui/LevelSelect.tscn")
		return
	var tutorial_id: String = Campaign.TUTORIAL_ORDER[0]
	var player: LevelPlayer = load("res://scenes/ui/LevelPlayer.tscn").instantiate()
	get_tree().root.add_child(player)
	for i in range(player.all_levels.size()):
		if player.all_levels[i].level_id == tutorial_id:
			player.load_level_by_index(i)
			get_tree().current_scene = player
			queue_free()
			return
	player.queue_free()
	get_tree().change_scene_to_file("res://scenes/ui/LevelSelect.tscn")

func _icon_button(parent: Node, icon_path: String, tooltip: String) -> Button:
	var button := Button.new()
	button.icon = load(icon_path)
	button.expand_icon = true
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	button.add_theme_constant_override("icon_max_width", 42)
	button.custom_minimum_size = Vector2(60, 60)
	button.tooltip_text = tooltip
	button.focus_mode = Control.FOCUS_NONE
	var clear_style := StyleBoxFlat.new()
	clear_style.bg_color = Color.TRANSPARENT
	clear_style.set_border_width_all(0)
	clear_style.content_margin_left = 0
	clear_style.content_margin_right = 0
	clear_style.content_margin_top = 0
	clear_style.content_margin_bottom = 0
	button.add_theme_stylebox_override("normal", clear_style)
	button.add_theme_stylebox_override("pressed", clear_style)
	button.add_theme_stylebox_override("disabled", clear_style)
	var hover_style := clear_style.duplicate()
	hover_style.bg_color = Color(1.0, 1.0, 1.0, 0.12)
	button.add_theme_stylebox_override("hover", hover_style)
	parent.add_child(button)
	return button
