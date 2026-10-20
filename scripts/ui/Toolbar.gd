class_name Toolbar
extends PanelContainer
const UI = preload("res://scripts/ui/UIStyle.gd")
const UI_ANIMATED_ICON = preload("res://scripts/ui/UIAnimatedIcon.gd")

signal block_type_selected(btype: int)
signal sub_mode_toggled(sub_mode: int)
signal direction_changed(dir: int)
signal group_pressed()
# Public hooks retained for external consumers; no toolbar buttons emit these.
@warning_ignore("unused_signal")
signal clear_pressed()
@warning_ignore("unused_signal")
signal save_machine_pressed()
@warning_ignore("unused_signal")
signal load_machine_pressed()

var is_editor_mode: bool = false
var current_type: int = BlockData.Type.BASIC
var current_dir: int = BlockData.Direction.RIGHT
var current_sub_mode: int = 0
var is_placing: bool = true # If false, select mode

# UI node references
var btn_group: ButtonGroup
var type_buttons: Dictionary = {} # type -> Button
var mode_btn: Button
var rotate_btn: Button
var pointer_btn: Button
var description_label: Label
var editing_enabled := true
var allowed_types: Array = []
var group_button: Button

func setup(p_is_editor_mode: bool) -> void:
	theme = UI.get_game_theme()
	is_editor_mode = p_is_editor_mode
	_build_ui()

func _build_ui() -> void:
	for c in get_children():
		c.queue_free()

	mouse_filter = Control.MOUSE_FILTER_IGNORE

	var main_hbox := HBoxContainer.new()
	main_hbox.name = "MainHBox"
	main_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	main_hbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_hbox.add_theme_constant_override("separation", 10)
	main_hbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(main_hbox)

	btn_group = ButtonGroup.new()

	# Keep pointer_btn reference as hidden button for compatibility
	pointer_btn = Button.new()
	pointer_btn.toggle_mode = true
	pointer_btn.button_group = btn_group

	# 1. Left container: Description Label (说明文字)
	var left_box := HBoxContainer.new()
	left_box.name = "LeftBox"
	left_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	left_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_hbox.add_child(left_box)

	description_label = UI.label(left_box, "", 14, UI.TEXT)
	description_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	description_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	description_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	# Separator between description and block buttons
	var sep_left := VSeparator.new()
	sep_left.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_hbox.add_child(sep_left)

	# 2. Center container: Block buttons (6 in player mode, 11 in editor mode)
	var center_box := HBoxContainer.new()
	center_box.name = "CenterBox"
	center_box.alignment = BoxContainer.ALIGNMENT_CENTER
	center_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_box.add_theme_constant_override("separation", 6)
	main_hbox.add_child(center_box)

	var max_type := BlockData.Type.PROTECTED if is_editor_mode else BlockData.Type.ROTATOR
	var shortcuts_labels := ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "-"]
	var btn_height := 34

	for t in range(0, max_type + 1):
		var btn := Button.new()
		var short_lbl = shortcuts_labels[t] if t < shortcuts_labels.size() else ""
		var bname = BlockData.SHORT_NAMES.get(t, "方块")
		var full_bname = BlockData.TYPE_NAMES.get(t, "方块")
		# 编辑器（创意工坊）模式：11 个方块按钮 + 动画图标空间紧张，不显示快捷键数字。
		btn.text = bname if is_editor_mode else "%s %s" % [bname, short_lbl]
		var icon_name: String = ["basic_0", "inhibitor_0", "pusher_0", "replicator_0", "destroyer_0", "rotator_cw_0", "hard_0", "wanderer_0", "treasure_0", "pollution_0", "protected_0"][t]
		var icon_path: String
		if t == BlockData.Type.DESTROYER:
			icon_path = "res://assets/textures/blocks/destroyer_ui.svg"
		elif t == BlockData.Type.BASIC:
			icon_path = "res://assets/textures/blocks/basic_ui.tres"
		elif t == BlockData.Type.PUSHER:
			icon_path = "res://assets/textures/blocks/pusher_ui.svg"
		else:
			icon_path = "res://assets/textures/blocks/" + icon_name + ".svg"
		var animated_icon_data: Dictionary = _get_animated_icon(t)
		if animated_icon_data.is_empty():
			btn.icon = load(icon_path)
			btn.expand_icon = true
			btn.add_theme_constant_override("icon_max_width", 20 if is_editor_mode else 22)
		else:
			btn.icon = null
			if is_editor_mode:
				# 编辑器 11 按钮空间紧张：不带快捷键数字，改用样式盒左边距给动画图标留位。
				var game_theme: Theme = UI.get_game_theme()
				for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
					var base_sb: StyleBox = game_theme.get_stylebox(state, "Button")
					if base_sb == null: continue
					var sb: StyleBoxFlat = base_sb.duplicate()
					sb.content_margin_left = 34.0
					btn.add_theme_stylebox_override(state, sb)
			else:
				btn.text = "   " + btn.text
			var animated_icon := UI_ANIMATED_ICON.new()
			animated_icon.configure(animated_icon_data["path"], animated_icon_data["frames"], 8.0, animated_icon_data.get("tint", Color.WHITE))
			animated_icon.position = Vector2(6, 5) if is_editor_mode else Vector2(4, 5)
			animated_icon.size = Vector2(24, 24)
			animated_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
			btn.add_child(animated_icon)
		btn.toggle_mode = true
		btn.button_group = btn_group
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(76 if is_editor_mode else 88, btn_height)
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER

		# Set tooltip
		btn.tooltip_text = "【%s】\n点击选中方块进行放置。\n%s快捷键: %s" % [full_bname, "" if is_editor_mode else "右键切换外观；重复左键保持选择。\n", short_lbl]

		var type_val := t
		btn.pressed.connect(func():
			is_placing = true
			select_type(type_val)
		)

		type_buttons[t] = btn
		center_box.add_child(btn)

	# Separator between block buttons and control buttons
	var sep_right := VSeparator.new()
	sep_right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	main_hbox.add_child(sep_right)

	# 3. Right container: remaining controls (朝向, 编组 - plus rotator mode when rotator selected)
	var right_box := HBoxContainer.new()
	right_box.name = "RightBox"
	right_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_box.alignment = BoxContainer.ALIGNMENT_END
	right_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_box.add_theme_constant_override("separation", 6)
	main_hbox.add_child(right_box)

	# Submode toggle (for Rotator CW / CCW)
	mode_btn = Button.new()
	mode_btn.text = "旋转: 顺时针"
	mode_btn.focus_mode = Control.FOCUS_NONE
	mode_btn.custom_minimum_size = Vector2(80, btn_height)
	mode_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	mode_btn.tooltip_text = "按 [F] 切换转向器顺逆时针模式 (CW 顺时针 / CCW 逆时针)"
	mode_btn.pressed.connect(toggle_sub_mode)
	right_box.add_child(mode_btn)

	# Direction Indicator / Rotate button
	rotate_btn = Button.new()
	rotate_btn.text = "朝向: →"
	rotate_btn.focus_mode = Control.FOCUS_NONE
	rotate_btn.custom_minimum_size = Vector2(68, btn_height)
	rotate_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rotate_btn.tooltip_text = "当前放置朝向。按 [Q]/[E] 逆时针/顺时针旋转"
	rotate_btn.pressed.connect(func():
		rotate_direction(1)
	)
	right_box.add_child(rotate_btn)

	var sep3 := VSeparator.new()
	sep3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	right_box.add_child(sep3)

	# Group / Structure button
	var group_btn := Button.new()
	group_button = group_btn
	group_btn.text = "编组 [G]"
	group_btn.focus_mode = Control.FOCUS_NONE
	group_btn.custom_minimum_size = Vector2(76, btn_height)
	group_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	group_btn.tooltip_text = "将选中的方块绑定为刚性整体结构（快捷键 G）"
	group_btn.pressed.connect(func():
		group_pressed.emit()
	)
	right_box.add_child(group_btn)

	# Default to selection mode (no tool selected)
	deselect_tool()

func _get_animated_icon(type_val: int) -> Dictionary:
	match type_val:
		BlockData.Type.INHIBITOR:
			return {"path": "res://scenes/animation/Invalidate_idle(1).png", "frames": 8}
		BlockData.Type.PUSHER:
			return {"path": "res://scenes/animation/push(2).png", "frames": 15, "tint": Color(1.0, 0.82, 0.035, 1.0)}
		BlockData.Type.REPLICATOR:
			return {"path": "res://scenes/animation/breed.png", "frames": 12, "tint": Color(0.86, 0.89, 0.93, 1.0)}
		BlockData.Type.DESTROYER:
			return {"path": "res://scenes/animation/eating(1).png", "frames": 16, "tint": Color(1.0, 0.035, 0.035, 1.0)}
		BlockData.Type.ROTATOR:
			return {"path": "res://scenes/animation/turn_around_CW.png", "frames": 16, "tint": Color(0.72, 0.34, 0.12, 1.0)}
		BlockData.Type.HARD:
			return {"path": "res://scenes/animation/block(1).png", "frames": 8}
		BlockData.Type.WANDERER:
			return {"path": "res://scenes/animation/monster_idle(2).png", "frames": 8}
		BlockData.Type.TREASURE:
			return {"path": "res://scenes/animation/treasure(1).png", "frames": 8}
		BlockData.Type.POLLUTION:
			return {"path": "res://scenes/animation/Pollution source(1).png", "frames": 8}
		_:
			return {}

func select_type(type_val: int) -> void:
	if not direct_placement_enabled: return
	if not editing_enabled: return
	if not allowed_types.is_empty() and type_val not in allowed_types: return
	current_type = type_val
	is_placing = true
	if type_buttons.has(type_val):
		type_buttons[type_val].button_pressed = true
	block_type_selected.emit(type_val)
	_update_mode_visibility()

func deselect_tool() -> void:
	is_placing = false
	current_type = -1
	for b in type_buttons.values():
		b.button_pressed = false
	block_type_selected.emit(-1)
	_update_mode_visibility()

func select_pointer() -> void:
	deselect_tool()

func cycle_tool(step: int) -> void:
	if not direct_placement_enabled: return
	if not editing_enabled: return
	if not allowed_types.is_empty():
		var index := allowed_types.find(current_type)
		if index < 0: index = -1 if step > 0 else 0
		select_type(int(allowed_types[posmod(index + step, allowed_types.size())]))
		return
	var max_type := BlockData.Type.PROTECTED if is_editor_mode else BlockData.Type.ROTATOR
	var next_type: int
	if not is_placing or current_type < 0:
		next_type = 0 if step > 0 else max_type
	else:
		next_type = posmod(current_type + step, max_type + 1)
	select_type(next_type)

func toggle_sub_mode() -> void:
	current_sub_mode = 1 if current_sub_mode == 0 else 0
	mode_btn.text = "转向: " + ("顺时针" if current_sub_mode == 0 else "逆时针")
	sub_mode_toggled.emit(current_sub_mode)

func rotate_direction(step: int) -> void:
	current_dir = posmod(current_dir + step, 4)
	var arrows := ["→", "↓", "←", "↑"]
	rotate_btn.text = "朝向: %s [Q/E]" % arrows[current_dir]
	direction_changed.emit(current_dir)

func _update_mode_visibility() -> void:
	_describe_selection()
	if mode_btn != null:
		mode_btn.visible = (current_type == BlockData.Type.ROTATOR)

func _describe_selection() -> void:
	if description_label == null: return
	if not editing_enabled:
		description_label.text = "模拟后暂停也不能编辑 · 点击「重置」恢复构装"
	elif not direct_placement_enabled:
		description_label.text = "本幕只使用场上细胞 · 单选 / 框选 · 右键菜单 · F1 操作手册"
	elif not is_placing or current_type < 0:
		description_label.text = "选择模式 · 框选/单选方块 · 右键菜单 · 按 1~6 建造"
	else:
		var descriptions := ["连接并承载其他模块", "前方有方块时后方方块视为普通", "推动前方方块并一起前进", "读取后方，复制到前方", "清除前方的目标", "旋转前方模块", "抵挡攻击，可被沉默", "按规则游荡的敌人", "带回建造区完成回收", "清除全部污染源", "保持完整，不能损毁"]
		var desc = descriptions[current_type] if current_type >= 0 and current_type < descriptions.size() else ""
		description_label.text = "%s · %s · 按 ESC 退出建造" % [BlockData.SHORT_NAMES.get(current_type, "方块"), desc]

func set_editable(enabled: bool) -> void:
	if editing_enabled == enabled: return
	editing_enabled = enabled
	for type in type_buttons: type_buttons[type].disabled = not enabled or not direct_placement_enabled or (not allowed_types.is_empty() and type not in allowed_types)
	for button in [pointer_btn, mode_btn, rotate_btn, group_button]: button.disabled = not enabled
	_describe_selection()

func set_allowed_types(types: Array) -> void:
	allowed_types = types
	for type in type_buttons:
		type_buttons[type].visible = types.is_empty() or type in types
		type_buttons[type].disabled = not editing_enabled or not direct_placement_enabled or (not types.is_empty() and type not in types)
	if not types.is_empty() and current_type not in types: deselect_tool()

var direct_placement_enabled := true
var placement_tooltips: Dictionary = {}

func set_direct_placement_enabled(enabled: bool) -> void:
	direct_placement_enabled = enabled
	if not enabled: deselect_tool()
	set_allowed_types(allowed_types)
	for button in type_buttons.values():
		if not placement_tooltips.has(button): placement_tooltips[button] = button.tooltip_text
		button.tooltip_text = "本幕请移动或复制场上的细胞，不能直接放置。" if not enabled else placement_tooltips[button]
	_describe_selection()
