class_name SettingsMenu
extends Control

const UI = preload("res://scripts/ui/UIStyle.gd")

signal closed()

var tab_container: TabContainer
var main_panel: PanelContainer
var key_buttons: Dictionary = {} # action_id -> Button
var listening_action: String = ""
var listening_button: Button = null
var tip_lbl: Label = null

var bgm_slider: HSlider
var sfx_slider: HSlider
var bgm_val_lbl: Label
var sfx_val_lbl: Label

func _ready() -> void:
	# 整屏弹层：自身必须先铺满视口，内部 CenterContainer 才能把设置面板真正居中，
	# 同时让半透明背板完整覆盖屏幕并拦截点击。
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	theme = UI.get_game_theme()
	_build_ui()

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and is_visible_in_tree():
		_refresh_audio_sliders()
		_refresh_button_labels()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	# Dim background
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.07, 0.1, 0.9)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)

	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)

	main_panel = PanelContainer.new()
	main_panel.custom_minimum_size = Vector2(680, 560)
	main_panel.add_theme_stylebox_override("panel", UI.box(UI.PANEL, UI.BORDER, 16, 24))
	center.add_child(main_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 16)
	main_panel.add_child(main_vbox)

	# Header
	var header_hbox := HBoxContainer.new()
	main_vbox.add_child(header_hbox)

	var title_lbl := Label.new()
	title_lbl.text = "游戏设置"
	title_lbl.add_theme_font_size_override("font_size", 22)
	title_lbl.add_theme_color_override("font_color", UI.ACCENT)
	header_hbox.add_child(title_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	header_hbox.add_child(spacer)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.focus_mode = FOCUS_NONE
	close_btn.custom_minimum_size = Vector2(36, 36)
	close_btn.pressed.connect(_on_close_pressed)
	header_hbox.add_child(close_btn)

	# Multi-tab layout
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = SIZE_EXPAND_FILL
	tab_container.custom_minimum_size.y = 400
	main_vbox.add_child(tab_container)

	# -------------------------------------------------------------
	# Tab 1: 音量设置
	# -------------------------------------------------------------
	var audio_tab := MarginContainer.new()
	audio_tab.name = "音量设置"
	audio_tab.add_theme_constant_override("margin_left", 24)
	audio_tab.add_theme_constant_override("margin_right", 24)
	audio_tab.add_theme_constant_override("margin_top", 20)
	audio_tab.add_theme_constant_override("margin_bottom", 20)
	tab_container.add_child(audio_tab)

	var audio_vbox := VBoxContainer.new()
	audio_vbox.add_theme_constant_override("separation", 22)
	audio_tab.add_child(audio_vbox)

	var audio_tip := Label.new()
	audio_tip.text = "调节背景音乐与游戏音效的音量大小。拖动滑动条即可即时试听音量变化。"
	audio_tip.add_theme_font_size_override("font_size", 13)
	audio_tip.add_theme_color_override("font_color", UI.MUTED)
	audio_vbox.add_child(audio_tip)

	# 1. 背景音乐音量 (BGM)
	var bgm_section := VBoxContainer.new()
	bgm_section.add_theme_constant_override("separation", 8)
	audio_vbox.add_child(bgm_section)

	var bgm_header := HBoxContainer.new()
	bgm_section.add_child(bgm_header)

	var bgm_title := Label.new()
	bgm_title.text = "背景音乐音量 (BGM)"
	bgm_title.add_theme_font_size_override("font_size", 15)
	bgm_title.size_flags_horizontal = SIZE_EXPAND_FILL
	bgm_header.add_child(bgm_title)

	bgm_val_lbl = Label.new()
	var cur_bgm := roundi(MusicManager.get_volume() * 100.0)
	bgm_val_lbl.text = "%d%%" % cur_bgm
	bgm_val_lbl.add_theme_font_size_override("font_size", 15)
	bgm_val_lbl.add_theme_color_override("font_color", UI.ACCENT)
	bgm_val_lbl.custom_minimum_size = Vector2(50, 0)
	bgm_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bgm_header.add_child(bgm_val_lbl)

	bgm_slider = HSlider.new()
	bgm_slider.min_value = 0
	bgm_slider.max_value = 100
	bgm_slider.step = 1
	bgm_slider.value = cur_bgm
	bgm_slider.custom_minimum_size.y = 28
	bgm_slider.value_changed.connect(func(val: float):
		if bgm_val_lbl != null:
			bgm_val_lbl.text = "%d%%" % int(val)
		MusicManager.set_volume(val / 100.0)
		SoundManager.save_audio_settings()
	)
	bgm_section.add_child(bgm_slider)

	var sep_audio_1 := HSeparator.new()
	sep_audio_1.add_theme_constant_override("separation", 16)
	audio_vbox.add_child(sep_audio_1)

	# 2. 游戏音效音量 (SFX)
	var sfx_section := VBoxContainer.new()
	sfx_section.add_theme_constant_override("separation", 8)
	audio_vbox.add_child(sfx_section)

	var sfx_header := HBoxContainer.new()
	sfx_section.add_child(sfx_header)

	var sfx_title := Label.new()
	sfx_title.text = "游戏音效音量 (SFX)"
	sfx_title.add_theme_font_size_override("font_size", 15)
	sfx_title.size_flags_horizontal = SIZE_EXPAND_FILL
	sfx_header.add_child(sfx_title)

	sfx_val_lbl = Label.new()
	var cur_sfx := roundi(SoundManager.get_volume() * 100.0)
	sfx_val_lbl.text = "%d%%" % cur_sfx
	sfx_val_lbl.add_theme_font_size_override("font_size", 15)
	sfx_val_lbl.add_theme_color_override("font_color", UI.ACCENT)
	sfx_val_lbl.custom_minimum_size = Vector2(50, 0)
	sfx_val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sfx_header.add_child(sfx_val_lbl)

	sfx_slider = HSlider.new()
	sfx_slider.min_value = 0
	sfx_slider.max_value = 100
	sfx_slider.step = 1
	sfx_slider.value = cur_sfx
	sfx_slider.custom_minimum_size.y = 28
	sfx_slider.value_changed.connect(func(val: float):
		if sfx_val_lbl != null:
			sfx_val_lbl.text = "%d%%" % int(val)
		SoundManager.set_volume(val / 100.0)
		SoundManager.save_audio_settings()
	)
	sfx_section.add_child(sfx_slider)

	var sep_audio_2 := HSeparator.new()
	sep_audio_2.add_theme_constant_override("separation", 16)
	audio_vbox.add_child(sep_audio_2)

	# 试听音效按钮
	var preview_row := HBoxContainer.new()
	preview_row.add_theme_constant_override("separation", 16)
	audio_vbox.add_child(preview_row)

	var preview_btn := Button.new()
	preview_btn.text = "♪ 试听音效"
	preview_btn.custom_minimum_size = Vector2(130, 36)
	preview_btn.focus_mode = FOCUS_NONE
	# preview_btn 由 SoundManager 自动挂接 button_down 播放音效，无需在此重复触发
	preview_row.add_child(preview_btn)

	var preview_tip := Label.new()
	preview_tip.text = "（点击试听按钮或拖动滑动条，均可实时聆听当前音效）"
	preview_tip.add_theme_font_size_override("font_size", 13)
	preview_tip.add_theme_color_override("font_color", UI.MUTED)
	preview_row.add_child(preview_tip)

	# -------------------------------------------------------------
	# Tab 2: 按键设置
	# -------------------------------------------------------------
	var keyboard_tab := VBoxContainer.new()
	keyboard_tab.name = "按键设置"
	keyboard_tab.add_theme_constant_override("separation", 10)
	tab_container.add_child(keyboard_tab)

	tip_lbl = Label.new()
	tip_lbl.text = "点击按键进行修改，按 Esc 取消修改。按键不可与其他操作冲突。"
	tip_lbl.add_theme_font_size_override("font_size", 13)
	tip_lbl.add_theme_color_override("font_color", UI.MUTED)
	keyboard_tab.add_child(tip_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	keyboard_tab.add_child(scroll)

	var list_vbox := VBoxContainer.new()
	list_vbox.size_flags_horizontal = SIZE_EXPAND_FILL
	list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(list_vbox)

	# Populate keybind rows grouped by category
	var bindings: Dictionary = KeybindManager.get_bindings()
	var categories: Array[String] = ["编辑操作", "视角与模拟", "快捷方块"]

	for cat in categories:
		var cat_lbl := Label.new()
		cat_lbl.text = "【%s】" % cat
		cat_lbl.add_theme_font_size_override("font_size", 14)
		cat_lbl.add_theme_color_override("font_color", UI.TEXT)
		list_vbox.add_child(cat_lbl)

		for act_key in bindings.keys():
			var act: String = str(act_key)
			var data: Dictionary = bindings[act]
			if data.get("category", "") != cat:
				continue

			var row := HBoxContainer.new()
			row.custom_minimum_size.y = 36
			list_vbox.add_child(row)

			var act_lbl := Label.new()
			act_lbl.text = data.get("label", act)
			act_lbl.add_theme_font_size_override("font_size", 15)
			act_lbl.size_flags_horizontal = SIZE_EXPAND_FILL
			row.add_child(act_lbl)

			var key_btn := Button.new()
			key_btn.text = KeybindManager.get_action_display_name(act)
			key_btn.custom_minimum_size = Vector2(140, 32)
			key_btn.focus_mode = FOCUS_NONE
			var target_act: String = act
			key_btn.pressed.connect(func():
				_start_listening(target_act, key_btn)
			)
			row.add_child(key_btn)

			key_buttons[act] = key_btn

		var sep := HSeparator.new()
		sep.add_theme_constant_override("separation", 10)
		list_vbox.add_child(sep)

	# Bottom actions
	var btm_hbox := HBoxContainer.new()
	btm_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(btm_hbox)

	var reset_btn := Button.new()
	reset_btn.text = "恢复默认设置"
	reset_btn.focus_mode = FOCUS_NONE
	reset_btn.custom_minimum_size = Vector2(130, 40)
	reset_btn.pressed.connect(_on_reset_defaults)
	btm_hbox.add_child(reset_btn)

	var btm_spacer := Control.new()
	btm_spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	btm_hbox.add_child(btm_spacer)

	var save_btn := Button.new()
	UI.game_primary(save_btn)
	save_btn.text = "完成并返回"
	save_btn.focus_mode = FOCUS_NONE
	save_btn.custom_minimum_size = Vector2(130, 40)
	save_btn.pressed.connect(_on_close_pressed)
	btm_hbox.add_child(save_btn)

func _start_listening(act: String, btn: Button) -> void:
	if listening_button != null and listening_action != "":
		listening_button.text = KeybindManager.get_action_display_name(listening_action)
		listening_button.modulate = Color(1.0, 1.0, 1.0)

	listening_action = act
	listening_button = btn
	btn.text = "【请按下新按键...】"
	btn.modulate = Color(0.3, 1.0, 0.7)
	if tip_lbl != null:
		var act_label: String = KeybindManager.get_binding(act).get("label", act)
		tip_lbl.text = "正在为「%s」设置快捷键，按 Esc 取消..." % act_label
		tip_lbl.add_theme_color_override("font_color", Color(0.3, 1.0, 0.7))

func _input(event: InputEvent) -> void:
	if listening_action.is_empty() or listening_button == null:
		return

	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
		# Ignore standalone modifier key presses
		if code in [KEY_CTRL, KEY_SHIFT, KEY_ALT, KEY_META]:
			return

		get_viewport().set_input_as_handled()

		if code == KEY_ESCAPE and listening_action != "cancel_tool":
			# Cancel listening
			listening_button.text = KeybindManager.get_action_display_name(listening_action)
			listening_button.modulate = Color(1.0, 1.0, 1.0)
			listening_action = ""
			listening_button = null
			if tip_lbl != null:
				tip_lbl.text = "点击按键进行修改，按 Esc 取消修改。按键不可与其他操作冲突。"
				tip_lbl.add_theme_color_override("font_color", UI.MUTED)
			return

		# Set new binding with conflict check
		var success: bool = KeybindManager.set_binding(listening_action, code, event.ctrl_pressed, event.shift_pressed, event.alt_pressed)
		if not success:
			var conflict_act: String = KeybindManager.find_conflicting_action(listening_action, code, event.ctrl_pressed, event.shift_pressed, event.alt_pressed)
			var conflict_label: String = KeybindManager.get_binding(conflict_act).get("label", conflict_act)
			if tip_lbl != null:
				tip_lbl.text = "⚠️ 设置失败：该按键与「%s」冲突！" % conflict_label
				tip_lbl.add_theme_color_override("font_color", Color(1.0, 0.4, 0.4))
			listening_button.text = "冲突: %s" % conflict_label
			listening_button.modulate = Color(1.0, 0.4, 0.4)
			var cur_btn := listening_button
			var cur_act := listening_action
			listening_action = ""
			listening_button = null
			var timer := get_tree().create_timer(1.2)
			timer.timeout.connect(func():
				if is_instance_valid(cur_btn):
					cur_btn.text = KeybindManager.get_action_display_name(cur_act)
					cur_btn.modulate = Color(1.0, 1.0, 1.0)
			)
			return

		if tip_lbl != null:
			tip_lbl.text = "✓ 按键已更新。按 Esc 可取消正在进行的修改。"
			tip_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))
		listening_button.text = KeybindManager.get_action_display_name(listening_action)
		listening_button.modulate = Color(1.0, 1.0, 1.0)
		listening_action = ""
		listening_button = null

func _on_reset_defaults() -> void:
	KeybindManager.reset_to_defaults()
	_refresh_button_labels()

	MusicManager.set_volume(1.0)
	SoundManager.set_volume(1.0)
	SoundManager.save_audio_settings()
	_refresh_audio_sliders()

	if tip_lbl != null:
		tip_lbl.text = "✓ 已恢复默认设置（按键与音量）。"
		tip_lbl.add_theme_color_override("font_color", Color(0.4, 1.0, 0.6))

func _refresh_audio_sliders() -> void:
	var cur_bgm := roundi(MusicManager.get_volume() * 100.0)
	if bgm_slider != null:
		bgm_slider.set_value_no_signal(cur_bgm)
	if bgm_val_lbl != null:
		bgm_val_lbl.text = "%d%%" % cur_bgm

	var cur_sfx := roundi(SoundManager.get_volume() * 100.0)
	if sfx_slider != null:
		sfx_slider.set_value_no_signal(cur_sfx)
	if sfx_val_lbl != null:
		sfx_val_lbl.text = "%d%%" % cur_sfx

func _refresh_button_labels() -> void:
	for act in key_buttons.keys():
		var btn: Button = key_buttons[act]
		btn.text = KeybindManager.get_action_display_name(act)
		btn.modulate = Color(1.0, 1.0, 1.0)
	listening_action = ""
	listening_button = null

func _on_close_pressed() -> void:
	if listening_button != null and listening_action != "":
		listening_button.text = KeybindManager.get_action_display_name(listening_action)
		listening_button.modulate = Color(1.0, 1.0, 1.0)
		listening_action = ""
		listening_button = null
	SoundManager.save_audio_settings()
	KeybindManager.save_bindings()
	hide()
	closed.emit()
