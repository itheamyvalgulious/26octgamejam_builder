class_name BlueprintDialogs
extends Node
const UI = preload("res://scripts/ui/UIStyle.gd")

# -------------------------------------------------------------
# Modal Wrapper with centered dialog and full-screen backdrop
# -------------------------------------------------------------
class ModalWrapper extends Control:
	var center_container: CenterContainer
	var content_node: Control

	func _init(content: Control) -> void:
		theme = UI.get_theme()
		content_node = content
		name = "BlueprintModalWrapper"
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP

		# Semi-transparent dark background (blocks clicks through to the board)
		var backdrop := ColorRect.new()
		backdrop.name = "Backdrop"
		backdrop.color = Color(0.04, 0.06, 0.09, 0.65)
		backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
		add_child(backdrop)

		# CenterContainer guarantees dead-center positioning in browser and all resolutions
		center_container = CenterContainer.new()
		center_container.name = "CenterContainer"
		center_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		center_container.mouse_filter = Control.MOUSE_FILTER_PASS
		add_child(center_container)

		center_container.add_child(content)

	func _unhandled_input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			if event.keycode == KEY_ESCAPE:
				close()
				get_viewport().set_input_as_handled()

	func close() -> void:
		queue_free()

static func show_save_dialog(parent: Node, has_selection: bool, on_confirmed: Callable) -> ModalWrapper:
	var dlg := SaveDialog.new(has_selection)
	var modal := ModalWrapper.new(dlg)
	dlg.confirmed.connect(func(machine_name: String, only_sel: bool):
		on_confirmed.call(machine_name, only_sel)
		modal.close()
	)
	dlg.cancelled.connect(func():
		modal.close()
	)
	parent.add_child(modal)
	return modal

static func show_load_dialog(parent: Node, on_selected: Callable) -> ModalWrapper:
	var dlg := LoadDialog.new()
	var modal := ModalWrapper.new(dlg)
	dlg.blueprint_selected.connect(func(machine_name: String):
		on_selected.call(machine_name)
		modal.close()
	)
	dlg.cancelled.connect(func():
		modal.close()
	)
	parent.add_child(modal)
	return modal

# -------------------------------------------------------------
# Blueprint Save Dialog
# -------------------------------------------------------------
class SaveDialog extends PanelContainer:
	signal confirmed(machine_name: String, save_only_selected: bool)
	signal cancelled()

	var line_edit: LineEdit
	var check_box: CheckBox

	func _init(has_selection: bool) -> void:
		custom_minimum_size = Vector2(420, 240)
		var style := StyleBoxFlat.new()
		style.bg_color = UI.PANEL
		style.border_color = UI.BORDER
		style.set_border_width_all(2)
		style.set_corner_radius_all(0)
		style.content_margin_left = 24
		style.content_margin_right = 24
		style.content_margin_top = 20
		style.content_margin_bottom = 20
		add_theme_stylebox_override("panel", style)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 14)
		add_child(vbox)

		var title := Label.new()
		title.text = "保存构装图纸 (Blueprint)"
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", UI.TEXT)
		vbox.add_child(title)

		var hint := Label.new()
		hint.text = "请输入图纸名称："
		vbox.add_child(hint)

		line_edit = LineEdit.new()
		line_edit.placeholder_text = "例如: 飞虫先锋机甲"
		line_edit.text = "机甲_%d" % [int(Time.get_unix_time_from_system()) % 10000]
		vbox.add_child(line_edit)

		check_box = CheckBox.new()
		check_box.text = "仅保存当前选中的方块"
		check_box.button_pressed = has_selection
		check_box.disabled = not has_selection
		vbox.add_child(check_box)

		var btn_hbox := HBoxContainer.new()
		btn_hbox.alignment = BoxContainer.ALIGNMENT_END
		btn_hbox.add_theme_constant_override("separation", 12)
		vbox.add_child(btn_hbox)

		var cancel_btn := Button.new()
		cancel_btn.text = "取消"
		cancel_btn.pressed.connect(func():
			cancelled.emit()
		)
		btn_hbox.add_child(cancel_btn)

		var ok_btn := Button.new()
		ok_btn.text = "保存"
		ok_btn.pressed.connect(func():
			var name_str := line_edit.text.strip_edges()
			if name_str.is_empty():
				name_str = "未命名图纸"
			confirmed.emit(name_str, check_box.button_pressed)
		)
		btn_hbox.add_child(ok_btn)

# -------------------------------------------------------------
# Blueprint Load Dialog
# -------------------------------------------------------------
class LoadDialog extends PanelContainer:
	signal blueprint_selected(machine_name: String)
	signal cancelled()

	var item_list: ItemList
	var load_btn: Button
	var del_btn: Button

	func _init() -> void:
		custom_minimum_size = Vector2(460, 380)
		var style := StyleBoxFlat.new()
		style.bg_color = UI.PANEL
		style.border_color = UI.BORDER
		style.set_border_width_all(2)
		style.set_corner_radius_all(0)
		style.content_margin_left = 24
		style.content_margin_right = 24
		style.content_margin_top = 20
		style.content_margin_bottom = 20
		add_theme_stylebox_override("panel", style)

		var vbox := VBoxContainer.new()
		vbox.add_theme_constant_override("separation", 12)
		add_child(vbox)

		var title := Label.new()
		title.text = "读取构装图纸 (Load Blueprint)"
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", UI.ACCENT)
		vbox.add_child(title)

		item_list = ItemList.new()
		item_list.custom_minimum_size = Vector2(400, 200)
		item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		vbox.add_child(item_list)

		_refresh_list()

		var btn_hbox := HBoxContainer.new()
		btn_hbox.alignment = BoxContainer.ALIGNMENT_END
		btn_hbox.add_theme_constant_override("separation", 12)
		vbox.add_child(btn_hbox)

		del_btn = Button.new()
		del_btn.text = "删除图纸"
		del_btn.pressed.connect(_on_delete)
		btn_hbox.add_child(del_btn)

		var cancel_btn := Button.new()
		cancel_btn.text = "关闭"
		cancel_btn.pressed.connect(func():
			cancelled.emit()
		)
		btn_hbox.add_child(cancel_btn)

		load_btn = Button.new()
		load_btn.text = "加载到画布"
		load_btn.pressed.connect(_on_load)
		btn_hbox.add_child(load_btn)

	func _refresh_list() -> void:
		item_list.clear()
		var names := SaveManager.get_saved_machines()
		for name_str in names:
			item_list.add_item(name_str)

	func _on_load() -> void:
		var selected := item_list.get_selected_items()
		if selected.is_empty():
			return
		var name_str := item_list.get_item_text(selected[0])
		blueprint_selected.emit(name_str)

	func _on_delete() -> void:
		var selected := item_list.get_selected_items()
		if selected.is_empty():
			return
		var name_str := item_list.get_item_text(selected[0])
		SaveManager.delete_machine(name_str)
		_refresh_list()
