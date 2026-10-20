class_name LevelManager
extends Control
const UI = preload("res://scripts/ui/UIStyle.gd")

var levels: Array[LevelData] = []
var selected_index: int = -1

# UI Nodes
var level_item_list: ItemList
var move_up_btn: Button
var move_down_btn: Button
var new_level_btn: Button
var delete_level_btn: Button
var delete_confirm: ConfirmationDialog

# Right-hand Property inputs
var prop_panel: PanelContainer
var id_edit: LineEdit
var name_edit: LineEdit
var desc_edit: TextEdit
var author_edit: LineEdit
var save_prop_btn: Button
var open_editor_btn: Button

# Level file import / export
var export_level_btn: Button
var import_level_btn: Button
var export_file_dialog: FileDialog
var import_file_dialog: FileDialog
var io_status_lbl: Label
var _web_import_cb: JavaScriptObject

func _ready() -> void:
	theme = UI.get_game_theme()
	MusicManager.play_ambient()
	SaveManager.init_directories()
	levels = SaveManager.get_all_levels()
	_build_ui()
	if not levels.is_empty():
		_select_level(0)

func _build_ui() -> void:
	# Background
	UI.add_lab_background(self)

	var main_vbox := VBoxContainer.new()
	add_child(main_vbox)
	main_vbox.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	main_vbox.offset_left = 32
	main_vbox.offset_right = -32
	main_vbox.offset_top = 24
	main_vbox.offset_bottom = -24
	main_vbox.add_theme_constant_override("separation", 16)

	# Header
	var header_hbox := HBoxContainer.new()
	header_hbox.add_theme_constant_override("separation", 16)
	main_vbox.add_child(header_hbox)

	var back_btn := Button.new()
	back_btn.text = "« 返回主菜单"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.custom_minimum_size = Vector2(130, 40)
	back_btn.pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn")
	)
	header_hbox.add_child(back_btn)

	var title_lbl := Label.new()
	title_lbl.text = "创作工坊 / 关卡管理"
	title_lbl.add_theme_font_size_override("font_size", 24)
	title_lbl.add_theme_color_override("font_color", UI.TEXT)
	header_hbox.add_child(title_lbl)

	# Split view: Left = Level list with reordering; Right = Level properties
	var split_hbox := HBoxContainer.new()
	split_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split_hbox.add_theme_constant_override("separation", 24)
	main_vbox.add_child(split_hbox)

	# ----------------- LEFT PANEL (List & Order) -----------------
	var left_vbox := VBoxContainer.new()
	left_vbox.custom_minimum_size = Vector2(360, 0)
	left_vbox.add_theme_constant_override("separation", 10)
	split_hbox.add_child(left_vbox)

	var list_header := Label.new()
	list_header.text = "关卡列表 (可上下调整顺序)"
	list_header.add_theme_font_size_override("font_size", 16)
	list_header.add_theme_color_override("font_color", UI.TEXT)
	left_vbox.add_child(list_header)

	level_item_list = ItemList.new()
	level_item_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	level_item_list.item_selected.connect(_select_level)
	level_item_list.item_activated.connect(func(idx: int):
		_select_level(idx)
		_on_open_level_editor()
	)
	left_vbox.add_child(level_item_list)

	# Buttons for reorder & create / delete
	var reorder_hbox := HBoxContainer.new()
	reorder_hbox.add_theme_constant_override("separation", 8)
	left_vbox.add_child(reorder_hbox)

	move_up_btn = Button.new()
	move_up_btn.text = "▲ 上移"
	move_up_btn.focus_mode = Control.FOCUS_NONE
	move_up_btn.pressed.connect(_on_move_up)
	reorder_hbox.add_child(move_up_btn)

	move_down_btn = Button.new()
	move_down_btn.text = "▼ 下移"
	move_down_btn.focus_mode = Control.FOCUS_NONE
	move_down_btn.pressed.connect(_on_move_down)
	reorder_hbox.add_child(move_down_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	reorder_hbox.add_child(spacer)

	new_level_btn = Button.new()
	new_level_btn.text = "＋ 新建关卡"
	new_level_btn.focus_mode = Control.FOCUS_NONE
	new_level_btn.pressed.connect(_on_create_level)
	reorder_hbox.add_child(new_level_btn)

	delete_level_btn = Button.new()
	delete_level_btn.text = "删除关卡"
	delete_level_btn.focus_mode = Control.FOCUS_NONE
	delete_level_btn.pressed.connect(func():
		if selected_index < 0 or selected_index >= levels.size(): return
		delete_confirm.dialog_text = "确定删除「%s」？\n关卡会从地图与本地关卡库中移除。" % levels[selected_index].level_name
		delete_confirm.popup_centered(Vector2i(480, 180))
	)
	delete_confirm = ConfirmationDialog.new()
	delete_confirm.theme = UI.get_game_theme()
	delete_confirm.title = "删除关卡"
	delete_confirm.ok_button_text = "删除此关卡"
	delete_confirm.cancel_button_text = "保留关卡"
	delete_confirm.confirmed.connect(_on_delete_level)
	add_child(delete_confirm)
	reorder_hbox.add_child(delete_level_btn)

	# Import / Export level files (JSON)
	var io_hbox := HBoxContainer.new()
	io_hbox.add_theme_constant_override("separation", 8)
	left_vbox.add_child(io_hbox)

	export_level_btn = Button.new()
	export_level_btn.text = "⤓ 导出关卡"
	export_level_btn.focus_mode = Control.FOCUS_NONE
	export_level_btn.pressed.connect(_on_export_level)
	io_hbox.add_child(export_level_btn)

	import_level_btn = Button.new()
	import_level_btn.text = "⤒ 导入关卡"
	import_level_btn.focus_mode = Control.FOCUS_NONE
	import_level_btn.pressed.connect(_on_import_level)
	io_hbox.add_child(import_level_btn)

	io_status_lbl = Label.new()
	io_status_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	io_status_lbl.add_theme_color_override("font_color", UI.ACCENT)
	left_vbox.add_child(io_status_lbl)

	_build_file_dialogs()

	# ----------------- RIGHT PANEL (Properties Form) -----------------
	prop_panel = PanelContainer.new()
	prop_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	prop_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var p_style := StyleBoxFlat.new()
	p_style.bg_color = UI.PANEL
	p_style.border_color = UI.BORDER
	p_style.set_border_width_all(2)
	p_style.set_corner_radius_all(0)
	p_style.content_margin_left = 28
	p_style.content_margin_right = 28
	p_style.content_margin_top = 20
	p_style.content_margin_bottom = 20
	prop_panel.add_theme_stylebox_override("panel", p_style)
	split_hbox.add_child(prop_panel)

	var form_vbox := VBoxContainer.new()
	form_vbox.add_theme_constant_override("separation", 14)
	prop_panel.add_child(form_vbox)

	var form_title := Label.new()
	form_title.text = "关卡详细属性设置"
	form_title.add_theme_font_size_override("font_size", 18)
	form_title.add_theme_color_override("font_color", UI.ACCENT)
	form_vbox.add_child(form_title)

	# Level ID
	var id_box := HBoxContainer.new()
	var id_lbl := Label.new()
	id_lbl.text = "关卡标识 ID: "
	id_lbl.custom_minimum_size = Vector2(120, 0)
	id_box.add_child(id_lbl)
	id_edit = LineEdit.new()
	id_edit.editable = false # immutable primary key
	id_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	id_box.add_child(id_edit)
	form_vbox.add_child(id_box)

	# Level Name
	var name_box := HBoxContainer.new()
	var name_lbl := Label.new()
	name_lbl.text = "关卡名称: "
	name_lbl.custom_minimum_size = Vector2(120, 0)
	name_box.add_child(name_lbl)
	name_edit = LineEdit.new()
	name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_box.add_child(name_edit)
	form_vbox.add_child(name_box)

	# Level Author
	var auth_box := HBoxContainer.new()
	var auth_lbl := Label.new()
	auth_lbl.text = "设计作者: "
	auth_lbl.custom_minimum_size = Vector2(120, 0)
	auth_box.add_child(auth_lbl)
	author_edit = LineEdit.new()
	author_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	auth_box.add_child(author_edit)
	form_vbox.add_child(auth_box)

	# Description
	var desc_lbl := Label.new()
	desc_lbl.text = "关卡任务描述与提示:"
	form_vbox.add_child(desc_lbl)
	desc_edit = TextEdit.new()
	desc_edit.custom_minimum_size = Vector2(0, 70)
	form_vbox.add_child(desc_edit)

	var btn_spacer := Control.new()
	btn_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	form_vbox.add_child(btn_spacer)

	# Bottom Actions HBox
	var action_hbox := HBoxContainer.new()
	action_hbox.alignment = BoxContainer.ALIGNMENT_END
	action_hbox.add_theme_constant_override("separation", 16)
	form_vbox.add_child(action_hbox)

	save_prop_btn = Button.new()
	save_prop_btn.text = "保存关卡属性"
	save_prop_btn.focus_mode = Control.FOCUS_NONE
	save_prop_btn.custom_minimum_size = Vector2(130, 42)
	save_prop_btn.pressed.connect(_on_save_properties)
	action_hbox.add_child(save_prop_btn)

	open_editor_btn = Button.new()
	open_editor_btn.text = "进入关卡方块编辑 >>"
	open_editor_btn.focus_mode = Control.FOCUS_NONE
	open_editor_btn.custom_minimum_size = Vector2(160, 42)
	open_editor_btn.pressed.connect(_on_open_level_editor)
	action_hbox.add_child(open_editor_btn)

	_refresh_list()

func _refresh_list() -> void:
	level_item_list.clear()
	for i in range(levels.size()):
		var lvl := levels[i]
		level_item_list.add_item("%d. %s [%s]" % [i + 1, lvl.level_name, lvl.level_id])

	if selected_index >= 0 and selected_index < levels.size():
		level_item_list.select(selected_index)
	elif not levels.is_empty():
		_select_level(0)

func _select_level(idx: int) -> void:
	if idx < 0 or idx >= levels.size():
		return
	selected_index = idx
	level_item_list.select(idx)

	var lvl := levels[idx]
	id_edit.text = lvl.level_id
	name_edit.text = lvl.level_name
	desc_edit.text = lvl.description
	author_edit.text = lvl.author

func _on_save_properties() -> void:
	if selected_index < 0 or selected_index >= levels.size():
		return
	var lvl := levels[selected_index]
	lvl.level_name = name_edit.text.strip_edges()
	lvl.description = desc_edit.text.strip_edges()
	lvl.author = author_edit.text.strip_edges()

	SaveManager.save_level(lvl)
	_refresh_list()

func _on_create_level() -> void:
	var new_id := "custom_level_%d" % [int(Time.get_unix_time_from_system()) % 100000]
	var new_lvl := LevelData.new(new_id, "新建自定关卡")
	new_lvl.order_index = levels.size()
	new_lvl.author = "造物主"
	new_lvl.player_build_area = Rect2i(-5, -4, 5, 8)
	SaveManager.save_level(new_lvl)

	levels = SaveManager.get_all_levels()
	_refresh_list()
	_select_level(levels.size() - 1)

func _on_delete_level() -> void:
	if selected_index < 0 or selected_index >= levels.size():
		return
	var lvl := levels[selected_index]
	SaveManager.delete_level(lvl.level_id)
	levels = SaveManager.get_all_levels()
	selected_index = mini(selected_index, levels.size() - 1)
	_refresh_list()

func _on_move_up() -> void:
	if selected_index <= 0:
		return
	var item = levels[selected_index]
	levels.remove_at(selected_index)
	levels.insert(selected_index - 1, item)
	selected_index -= 1

	var ids := []
	for l in levels:
		ids.append(l.level_id)
	SaveManager.reorder_levels(ids)
	_refresh_list()

func _on_move_down() -> void:
	if selected_index >= levels.size() - 1 or selected_index < 0:
		return
	var item = levels[selected_index]
	levels.remove_at(selected_index)
	levels.insert(selected_index + 1, item)
	selected_index += 1

	var ids := []
	for l in levels:
		ids.append(l.level_id)
	SaveManager.reorder_levels(ids)
	_refresh_list()

func _on_open_level_editor() -> void:
	if selected_index < 0 or selected_index >= levels.size():
		return
	_on_save_properties()
	var lvl := levels[selected_index]

	var editor_scene = load("res://scenes/ui/LevelEditor.tscn")
	var editor_instance: LevelEditor = editor_scene.instantiate()
	get_tree().root.add_child(editor_instance)
	editor_instance.load_level(lvl)
	get_tree().current_scene = editor_instance
	queue_free()

# -------------------------------------------------------------
# Level Import / Export (JSON)
# -------------------------------------------------------------

func _build_file_dialogs() -> void:
	export_file_dialog = FileDialog.new()
	export_file_dialog.theme = UI.get_game_theme()
	export_file_dialog.title = "导出关卡文件 (JSON)"
	export_file_dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	export_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	export_file_dialog.filters = PackedStringArray(["*.json ; 关卡文件 (JSON)"])
	export_file_dialog.use_native_dialog = false
	export_file_dialog.file_selected.connect(_on_export_path_selected)
	add_child(export_file_dialog)

	import_file_dialog = FileDialog.new()
	import_file_dialog.theme = UI.get_game_theme()
	import_file_dialog.title = "导入关卡文件 (JSON)"
	import_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	import_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	import_file_dialog.filters = PackedStringArray(["*.json ; 关卡文件 (JSON)"])
	import_file_dialog.use_native_dialog = false
	import_file_dialog.file_selected.connect(_on_import_path_selected)
	add_child(import_file_dialog)

func _set_io_status(text: String, is_error := false) -> void:
	if io_status_lbl == null:
		return
	io_status_lbl.text = text
	io_status_lbl.add_theme_color_override("font_color", Color("962929") if is_error else UI.ACCENT)

func _on_export_level() -> void:
	if selected_index < 0 or selected_index >= levels.size():
		_set_io_status("请先选择一个关卡。", true)
		return
	var lvl := levels[selected_index]
	var filename := "%s.json" % lvl.level_id
	if OS.has_feature("web"):
		_download_in_browser(filename, SaveManager.export_level_text(lvl))
	else:
		export_file_dialog.current_file = filename
		export_file_dialog.popup_centered(Vector2i(760, 520))

func _on_export_path_selected(path: String) -> void:
	if selected_index < 0 or selected_index >= levels.size():
		return
	var lvl := levels[selected_index]
	if SaveManager.export_level_file(lvl, path):
		_set_io_status("已导出「%s」→ %s" % [lvl.level_name, path])
	else:
		_set_io_status("导出失败，请检查目标路径是否可写。", true)

func _on_import_level() -> void:
	if OS.has_feature("web"):
		_pick_file_in_browser()
	else:
		import_file_dialog.popup_centered(Vector2i(760, 520))

func _on_import_path_selected(path: String) -> void:
	var lvl := SaveManager.import_level_file(path)
	_apply_imported_level(lvl)

func _apply_imported_level(lvl: LevelData) -> void:
	if lvl == null:
		_set_io_status("导入失败：文件不是有效的关卡 JSON。", true)
		return
	var existing_ids := []
	for l in levels:
		existing_ids.append(l.level_id)
	var original_id := lvl.level_id
	lvl.level_id = SaveManager.make_unique_level_id(lvl.level_id, existing_ids)
	if lvl.level_name.strip_edges().is_empty():
		lvl.level_name = "导入关卡"
	lvl.order_index = levels.size()
	if not SaveManager.save_level(lvl):
		_set_io_status("导入失败：无法保存到本地关卡库。", true)
		return
	levels = SaveManager.get_all_levels()
	var note := "" if lvl.level_id == original_id else "（标识 %s 已存在，改用 %s）" % [original_id, lvl.level_id]
	_refresh_list()
	for i in range(levels.size()):
		if levels[i].level_id == lvl.level_id:
			_select_level(i)
			break
	_set_io_status("已导入关卡「%s」%s" % [lvl.level_name, note])

# -------------------------------------------------------------
# Browser (Web export) file exchange via JavaScriptBridge
# -------------------------------------------------------------

func _download_in_browser(filename: String, text: String) -> void:
	var js := """
	(function() {
		try {
			var data = %s;
			var blob = new Blob([data], {type: 'application/json'});
			var url = URL.createObjectURL(blob);
			var a = document.createElement('a');
			a.href = url;
			a.download = %s;
			document.body.appendChild(a);
			a.click();
			setTimeout(function() { document.body.removeChild(a); URL.revokeObjectURL(url); }, 200);
		} catch (e) {
			console.warn('[LevelExport] failed:', e);
		}
	})();
	""" % [JSON.stringify(text), JSON.stringify(filename)]
	JavaScriptBridge.eval(js)
	_set_io_status("已开始下载关卡文件：%s" % filename)

func _pick_file_in_browser() -> void:
	if _web_import_cb == null:
		_web_import_cb = JavaScriptBridge.create_callback(_on_web_file_read)
	JavaScriptBridge.get_interface("window").__gestalt_level_import_cb = _web_import_cb
	var js := """
	(function() {
		var input = document.createElement('input');
		input.type = 'file';
		input.accept = '.json,application/json';
		input.style.display = 'none';
		document.body.appendChild(input);
		input.addEventListener('change', function() {
			var file = input.files && input.files[0];
			if (!file) { document.body.removeChild(input); return; }
			var reader = new FileReader();
			reader.onload = function() {
				try { window.__gestalt_level_import_cb(String(reader.result)); }
				finally { document.body.removeChild(input); }
			};
			reader.onerror = function() { document.body.removeChild(input); };
			reader.readAsText(file);
		});
		input.click();
	})();
	"""
	JavaScriptBridge.eval(js)

func _on_web_file_read(args: Array) -> void:
	if args.is_empty():
		return
	_apply_imported_level(SaveManager.parse_level_text(str(args[0])))
