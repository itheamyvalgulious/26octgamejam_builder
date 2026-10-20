class_name EditorContextMenu
extends PanelContainer

const UI = preload("res://scripts/ui/UIStyle.gd")

signal item_selected(action: String)

var menu_vbox: VBoxContainer
var action_buttons: Dictionary = {}

func _init() -> void:
	visible = false
	z_index = 100
	custom_minimum_size = Vector2(230, 0)
	theme = UI.get_theme()

	var style := StyleBoxFlat.new()
	style.bg_color = UI.PANEL
	style.border_color = UI.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 8
	style.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", style)

	menu_vbox = VBoxContainer.new()
	menu_vbox.add_theme_constant_override("separation", 2)
	add_child(menu_vbox)

	_build_items()

func _build_items() -> void:
	for c in menu_vbox.get_children():
		c.queue_free()
	action_buttons.clear()

	var items: Array[Dictionary] = [
		{ "action": "undo", "label": "撤销", "key_action": "undo" },
		{ "action": "redo", "label": "重做", "key_action": "redo" },
		{ "type": "sep" },
		{ "action": "copy", "label": "复制", "key_action": "copy" },
		{ "action": "cut", "label": "剪切", "key_action": "cut" },
		{ "action": "paste", "label": "粘贴", "key_action": "paste" },
		{ "action": "delete", "label": "删除", "key_action": "delete" },
		{ "type": "sep" },
		{ "action": "rotate_cw", "label": "旋转90(顺时针)", "key_action": "rotate_cw" },
		{ "action": "rotate_ccw", "label": "旋转90(逆时针)", "key_action": "rotate_ccw" },
		{ "action": "flip_h", "label": "水平翻转", "key_action": "flip_h" },
		{ "action": "flip_v", "label": "垂直翻转", "key_action": "flip_v" },
	]

	for item in items:
		if item.get("type", "") == "sep":
			var sep := HSeparator.new()
			sep.add_theme_constant_override("separation", 6)
			menu_vbox.add_child(sep)
			continue

		var act: String = item["action"]
		var btn := Button.new()
		btn.name = act
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(218, 32)
		btn.flat = true

		# Button layout: HBox with Action label and lower-contrast Shortcut label
		var hbox := HBoxContainer.new()
		hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.set_anchors_preset(PRESET_FULL_RECT)
		hbox.offset_left = 8
		hbox.offset_right = -8
		btn.add_child(hbox)

		var lbl_text := Label.new()
		lbl_text.text = item["label"]
		lbl_text.add_theme_font_size_override("font_size", 14)
		lbl_text.add_theme_color_override("font_color", UI.TEXT) # High contrast
		hbox.add_child(lbl_text)

		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hbox.add_child(spacer)

		var lbl_shortcut := Label.new()
		lbl_shortcut.name = "ShortcutLabel"
		lbl_shortcut.add_theme_font_size_override("font_size", 13)
		# 快捷键部分相比文字部分对比度更低一点
		lbl_shortcut.add_theme_color_override("font_color", UI.MUTED)
		hbox.add_child(lbl_shortcut)

		btn.pressed.connect(func():
			visible = false
			item_selected.emit(act)
		)

		action_buttons[act] = {
			"button": btn,
			"key_action": item["key_action"],
			"shortcut_label": lbl_shortcut
		}
		menu_vbox.add_child(btn)

func update_shortcuts() -> void:
	for act in action_buttons.keys():
		var data: Dictionary = action_buttons[act]
		var key_act: String = data["key_action"]
		var lbl: Label = data["shortcut_label"]
		lbl.text = KeybindManager.get_action_display_name(key_act)

func popup_at(screen_pos: Vector2, can_paste: bool = true, can_copy_or_cut: bool = true, can_undo: bool = false, can_redo: bool = false) -> void:
	update_shortcuts()
	if action_buttons.has("undo"):
		action_buttons["undo"]["button"].disabled = not can_undo
	if action_buttons.has("redo"):
		action_buttons["redo"]["button"].disabled = not can_redo
	if action_buttons.has("paste"):
		var btn: Button = action_buttons["paste"]["button"]
		btn.disabled = not can_paste
	if action_buttons.has("copy"):
		var btn: Button = action_buttons["copy"]["button"]
		btn.disabled = not can_copy_or_cut
	if action_buttons.has("cut"):
		var btn: Button = action_buttons["cut"]["button"]
		btn.disabled = not can_copy_or_cut

	visible = true
	# Measure size
	reset_size()
	var menu_size := get_combined_minimum_size()

	var vp_size: Vector2 = get_viewport_rect().size if is_inside_tree() else Vector2(1280, 720)
	var target_x: float = screen_pos.x
	var target_y: float = screen_pos.y

	if target_x + menu_size.x > vp_size.x - 8.0:
		target_x = vp_size.x - menu_size.x - 8.0
	if target_y + menu_size.y > vp_size.y - 8.0:
		target_y = vp_size.y - menu_size.y - 8.0
	if target_x < 8.0: target_x = 8.0
	if target_y < 8.0: target_y = 8.0

	position = Vector2(target_x, target_y)

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed:
		var local_mouse := get_local_mouse_position()
		if not get_rect().has_point(position + local_mouse):
			visible = false
			get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed:
		if event.keycode == KEY_ESCAPE:
			visible = false
			get_viewport().set_input_as_handled()
