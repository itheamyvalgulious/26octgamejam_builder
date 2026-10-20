class_name LevelSelect
extends Control
const UI = preload("res://scripts/ui/UIStyle.gd")

const Campaign = preload("res://scripts/core/Campaign.gd")

const FOLDER_DEFAULT = preload("res://assets/textures/ui/level_folder_default.png")
const FOLDER_OPEN = preload("res://assets/textures/ui/level_folder_open.png")

const MapScript = preload("res://scripts/ui/CampaignMap.gd")
var levels: Array[LevelData] = []
var chapter_buttons: Array[Button] = []
var node_buttons: Dictionary = {}
var chapter := 0
var selected_index := -1
var map: Control
var chapter_title: Label
var chapter_description: Label
var detail_title: Label
var detail_body: RichTextLabel
var enter_button: Button
var map_scroll: ScrollContainer

func _ready() -> void:
	theme = UI.get_game_theme()
	MusicManager.play_ambient()
	if map != null: return
	levels = SaveManager.get_all_levels()
	_build_ui()
	var previous := -1
	for i in range(levels.size()):
		if levels[i].level_id == Campaign.active_level: previous = i
	_show_chapter(Campaign.info(levels[previous].level_id)[0] if previous >= 0 else 0)
	if previous >= 0: _select_level(previous)

func _label(parent: Node, text: String, font_size: int, color := UI.TEXT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _style(color: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(0)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	return style

func _build_ui() -> void:
	UI.add_lab_background(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 32)
	margin.add_theme_constant_override("margin_left", 96)
	add_child(margin)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	margin.add_child(layout)
	var header := HBoxContainer.new()
	layout.add_child(header)
	var heading := _label(header, "构造一个我", 30, UI.ACCENT)
	heading.name = "GameName"
	var rounded_font := SystemFont.new()
	rounded_font.font_names = PackedStringArray(["YouYuan", "幼圆", "Yuanti SC", "Hiragino Maru Gothic ProN"])
	rounded_font.fallbacks = [UI.get_theme().default_font]
	heading.add_theme_font_override("font", rounded_font)
	heading.add_theme_color_override("font_outline_color", UI.ACCENT)
	heading.add_theme_constant_override("outline_size", 1)
	var subtitle := _label(header, "  /  章节地图", 24, UI.TEXT)
	subtitle.size_flags_horizontal = SIZE_EXPAND_FILL
	var manual := Button.new()
	manual.text = "操作手册 · F1"
	manual.pressed.connect(func(): get_node("/root/OperationManual").open())
	header.add_child(manual)
	var back := Button.new()
	back.text = "返回主菜单"
	back.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/ui/MainMenu.tscn"))
	header.add_child(back)
	var chapter_scroll := ScrollContainer.new()
	chapter_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(chapter_scroll)
	var chapter_bar := HBoxContainer.new()
	chapter_bar.add_theme_constant_override("separation", 10)
	chapter_scroll.add_child(chapter_bar)
	for i in range(Campaign.CHAPTERS.size() + 1):
		if i == Campaign.CHAPTERS.size() and not _has_custom_levels(): continue
		var button := Button.new()
		button.text = ("%02d  %s" % [i + 1, Campaign.CHAPTERS[i][0]]) if i < Campaign.CHAPTERS.size() else "自由工坊"
		button.custom_minimum_size = Vector2(170, 46)
		button.pressed.connect(_show_chapter.bind(i))
		chapter_bar.add_child(button)
		chapter_buttons.append(button)
	var body := HBoxContainer.new()
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 20)
	layout.add_child(body)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(left)
	chapter_title = _label(left, "", 24)
	chapter_description = _label(left, "", 15, UI.MUTED)
	chapter_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	map_scroll = ScrollContainer.new()
	map_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	left.add_child(map_scroll)
	map = MapScript.new()
	map.custom_minimum_size = Vector2(750, 350)
	map_scroll.add_child(map)
	_label(left, "实线：主线    虚线：可选支线    ✓：已通关\n点击节点查看详情 · 地图可滚动", 14, UI.MUTED)
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 330
	panel.add_theme_stylebox_override("panel", _style(UI.PANEL, UI.BORDER))
	body.add_child(panel)
	var details := VBoxContainer.new()
	details.add_theme_constant_override("separation", 18)
	panel.add_child(details)
	_label(details, "关卡档案", 14, UI.ACCENT)
	detail_title = _label(details, "选择一个节点", 24)
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_body = RichTextLabel.new()
	detail_body.size_flags_vertical = SIZE_EXPAND_FILL
	detail_body.bbcode_enabled = false
	detail_body.add_theme_color_override("default_color", UI.TEXT)
	detail_body.add_theme_font_size_override("normal_font_size", 16)
	details.add_child(detail_body)
	enter_button = Button.new()
	enter_button.text = "进入关卡 →"
	UI.game_primary(enter_button)
	enter_button.custom_minimum_size.y = 52
	enter_button.disabled = true
	enter_button.text = "进入关卡 →"
	enter_button.text = "进入关卡 →"
	enter_button.pressed.connect(func(): _enter_level(selected_index))
	details.add_child(enter_button)

func _has_custom_levels() -> bool:
	for level in levels:
		if not Campaign.NODES.has(level.level_id): return true
	return false

func _show_chapter(index: int) -> void:
	chapter = index
	selected_index = -1
	enter_button.disabled = true
	detail_title.text = "选择一个节点"
	detail_body.clear()
	detail_body.add_text("点击地图上的关卡，查看目标与核心机制。\n\n主线帮助你逐步掌握构装，支线可以随时尝试。")
	chapter_title.text = Campaign.CHAPTERS[index][1] if index < Campaign.CHAPTERS.size() else "自由工坊"
	chapter_description.text = Campaign.CHAPTERS[index][2] if index < Campaign.CHAPTERS.size() else "未编入章节的自制关卡也会保留在这里。"
	for i in range(chapter_buttons.size()):
		chapter_buttons[i].toggle_mode = true
		chapter_buttons[i].set_pressed_no_signal(i == index)
	for child in map.get_children():
		map.remove_child(child)
		child.queue_free()
	node_buttons.clear()
	map.routes.clear()
	var positions := {}
	var progress := Campaign.completed()
	var count := 0
	var completed_count := 0
	var tutorial_ids := Campaign.visible_tutorial_ids(levels)
	var display_indices: Array[int] = []
	if index == 0:
		for id in tutorial_ids:
			for i in range(levels.size()):
				if levels[i].level_id == id: display_indices.append(i)
	else:
		for i in range(levels.size()): display_indices.append(i)
	for i in display_indices:
		var level := levels[i]
		var data := Campaign.info(level.level_id)
		if data[0] != index: continue
		if progress.has(level.level_id): completed_count += 1
		var column: int = data[2] if index < Campaign.CHAPTERS.size() else count % 4
		var row: int = data[3] if index < Campaign.CHAPTERS.size() else floori(count / 4.0)
		var node_position := Vector2(20 + column * 145, 60 + row * 170)
		if index == 0:
			row = floori(count / 3.0)
			column = count % 3 if row % 2 == 0 else 2 - count % 3
			node_position = Vector2(60 + column * 220, 40 + row * 140)
		var button := Button.new()
		button.toggle_mode = true
		button.position = node_position
		button.size = Vector2(130, 130)
		if index == 0: button.size = Vector2(160, 130)
		var unlocked := Campaign.is_unlocked(level.level_id)
		var label := "%s · %s" % [data[1], Campaign.title(level)] if index == 0 else Campaign.title(level)
		var caption := "%s %s" % [label, ("✓" if progress.has(level.level_id) else "") if unlocked else "未开放"]
		if not unlocked: button.modulate = Color("809398")
		button.tooltip_text = caption + "\n" + Campaign.unlock_description(level.level_id)
		_configure_folder_node(button, caption)
		button.pressed.connect(_select_level.bind(i))
		map.add_child(button)
		node_buttons[level.level_id] = button
		positions[level.level_id] = node_position + Vector2(button.size.x * 0.5, 44)
		count += 1
	map.custom_minimum_size = Vector2(750, maxf(350.0, ceilf(count / 4.0) * 170 + 100.0) if index >= Campaign.CHAPTERS.size() else 350.0)
	if index == 0: map.custom_minimum_size.y = maxf(350, ceilf(count / 3.0) * 140 + 10)
	if index == 0:
		for i in range(tutorial_ids.size() - 1):
			var a: Vector2 = positions[tutorial_ids[i]]
			var b: Vector2 = positions[tutorial_ids[i + 1]]
			var turn := (1 if a.x > 300 else -1) if a.y != b.y else 0
			map.routes.append([a, b, false, turn])
	for id in positions:
		if index == 0: break
		var next: String = Campaign.info(id)[7]
		if positions.has(next): map.routes.append([positions[id], positions[next]])
	if count == 0: detail_body.text = "此章节暂无可用关卡。可切换章节或在关卡管理中添加内容。"
	chapter_description.text += "   ·   已完成 %d / %d" % [completed_count, count]
	map.queue_redraw()
	map_scroll.scroll_horizontal = 0
	map_scroll.scroll_vertical = 0

func _select_level(index: int) -> void:
	if index < 0 or index >= levels.size(): return
	if not node_buttons.has(levels[index].level_id) or not Campaign.is_unlocked(levels[index].level_id): return
	selected_index = index
	var level := levels[index]
	for id in node_buttons:
		node_buttons[id].set_pressed_no_signal(id == level.level_id)
		node_buttons[id].get_node("FolderLabel").add_theme_color_override("font_color", UI.ACCENT if id == level.level_id else UI.TEXT)
	var data := Campaign.info(level.level_id)
	var level_title := Campaign.title(level)
	detail_title.text = level_title if not level_title.is_empty() else data[1]
	var status := "已通关" if Campaign.completed().has(level.level_id) else "未通关"
	var goal := level.description
	if level.level_id in ["level_04", "custom_level_81605"]: goal = "清除所有污染源。怪物是障碍，不要求全部消灭。"
	detail_body.clear()
	detail_body.add_text("%s  ·  %s\n\n" % ["支线" if data[4] else "主线", status])
	if level.level_id in Campaign.TUTORIAL_ORDER:
		detail_body.add_text(Campaign.unlock_description(level.level_id) + "\n\n")
	for section in [["目标", goal], ["核心机制", data[6]]]:
		detail_body.push_font_size(18)
		detail_body.push_color(UI.ACCENT)
		detail_body.add_text(str(section[0]))
		detail_body.pop()
		detail_body.pop()
		detail_body.add_text("\n" + str(section[1]) + "\n\n")
	enter_button.disabled = not Campaign.is_unlocked(level.level_id)
	enter_button.text = "进入关卡 →" if not enter_button.disabled else "暂未开放"
	node_buttons[level.level_id].grab_focus()

func _enter_level(index: int) -> void:
	if index < 0 or index >= levels.size(): return
	var selected_id := levels[index].level_id
	if not Campaign.is_unlocked(selected_id): return
	var player: LevelPlayer = load("res://scenes/ui/LevelPlayer.tscn").instantiate()
	get_tree().root.add_child(player)
	for i in range(player.all_levels.size()):
		if player.all_levels[i].level_id == selected_id:
			player.load_level_by_index(i)
			get_tree().current_scene = player
			queue_free()
			return
	player.queue_free()
	levels = SaveManager.get_all_levels()
	_show_chapter(chapter)

func _configure_folder_node(button: Button, caption: String) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.border_color = UI.ACCENT
	focus.set_border_width_all(2)
	focus.set_corner_radius_all(8)
	button.add_theme_stylebox_override("focus", focus)
	var closed_texture := AtlasTexture.new()
	closed_texture.atlas = FOLDER_DEFAULT
	closed_texture.region = Rect2(235, 310, 790, 645)
	var open_texture := AtlasTexture.new()
	open_texture.atlas = FOLDER_OPEN
	open_texture.region = closed_texture.region
	var icon := TextureRect.new()
	icon.name = "FolderIcon"
	icon.texture = closed_texture
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(10, 0)
	icon.size = Vector2(button.size.x - 20, 88)
	button.add_child(icon)
	var label := Label.new()
	label.name = "FolderLabel"
	label.text = caption
	label.position = Vector2(0, 90)
	label.size = Vector2(button.size.x, 40)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", UI.TEXT)
	button.add_child(label)
	button.mouse_entered.connect(func(): icon.texture = open_texture)
	button.mouse_exited.connect(func(): icon.texture = closed_texture)
	button.toggled.connect(func(selected: bool):
		label.add_theme_color_override("font_color", UI.ACCENT if selected else UI.TEXT)
	)
