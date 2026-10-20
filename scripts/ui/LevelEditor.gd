class_name LevelEditor
extends Control
const UI = preload("res://scripts/ui/UIStyle.gd")

var current_level_data: LevelData
var world: GridWorld
var initial_snapshot: GridWorld
var sim_engine: SimulationEngine

# Visual nodes
var camera: CameraController
var grid_view: GridView
var toolbar: Toolbar
var ui_layer: CanvasLayer

# Top Bar controls
var level_name_lbl: Label
var play_btn: Button
var step_btn: Button
var reset_btn: Button
var save_level_btn: Button
var clear_level_btn: Button
var clear_confirm: ConfirmationDialog
var save_machine_btn: Button
var load_machine_btn: Button
var speed_slider: HSlider
var speed_label: Label
var sim_speed_multiplier: float = 1.0 # 0.2x ~ 20.0x
var base_tick_duration: float = 0.35 # seconds

# Build area visual editor controls
var set_build_area_btn: Button
var reset_build_area_btn: Button
var build_area_info_lbl: Label
var is_editing_build_area: bool = false
var is_dragging_build_area: bool = false
var build_area_drag_start: Vector2i = Vector2i.ZERO

var is_simulating: bool = false
var is_animating_tick: bool = false

# Mouse interaction
var is_mouse_placing: bool = false
var is_mouse_erasing: bool = false
var last_editor_grid: Vector2i = Vector2i(-999999, -999999)
var is_box_selecting: bool = false
var selected_blocks: Array[BlockData] = []
var box_select_start_world: Vector2 = Vector2.ZERO
var is_right_dragging_selection: bool = false
var right_drag_start_grid: Vector2i = Vector2i.ZERO
var right_drag_orig_positions: Dictionary = {} # BlockData -> Vector2i

# Context menu & right-drag panning
var context_menu: EditorContextMenu
var is_right_mouse_down: bool = false
var is_right_panning: bool = false
var right_mouse_down_pos: Vector2 = Vector2.ZERO
var right_pan_drag_threshold: float = 6.0

# Undo / Redo history（至少保留最近 100 步，超出后仅丢弃更早的记录）
var undo_stack: Array[GridWorld] = []
var redo_stack: Array[GridWorld] = []
const MAX_UNDO_STACK := 100

func record_undo() -> void:
	if is_simulating or is_animating_tick:
		return
	undo_stack.append(world.clone())
	if undo_stack.size() > MAX_UNDO_STACK:
		undo_stack.pop_front()
	redo_stack.clear()

func can_undo() -> bool:
	return not is_simulating and not is_animating_tick and not undo_stack.is_empty()

func can_redo() -> bool:
	return not is_simulating and not is_animating_tick and not redo_stack.is_empty()

func undo() -> void:
	if not can_undo():
		return
	redo_stack.append(world.clone())
	var prev_world: GridWorld = undo_stack.pop_back()
	world = prev_world.clone()
	initial_snapshot = world.clone()
	sim_engine = SimulationEngine.new(world)
	_clear_selection()
	if grid_view != null:
		grid_view.cancel_multi_ghost()
		grid_view.set_world(world)

func redo() -> void:
	if not can_redo():
		return
	undo_stack.append(world.clone())
	var next_world: GridWorld = redo_stack.pop_back()
	world = next_world.clone()
	initial_snapshot = world.clone()
	sim_engine = SimulationEngine.new(world)
	_clear_selection()
	if grid_view != null:
		grid_view.cancel_multi_ghost()
		grid_view.set_world(world)

func _ready() -> void:
	theme = UI.get_game_theme()
	RenderingServer.set_default_clear_color(UI.BG)
	# Let board clicks reach _unhandled_input; UI panels still consume theirs.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()
	if current_level_data == null:
		var new_lvl := LevelData.new("custom_01", "新自定关卡")
		load_level(new_lvl)

func load_level(lvl: LevelData) -> void:
	undo_stack.clear()
	redo_stack.clear()
	current_level_data = lvl
	if level_name_lbl != null:
		level_name_lbl.text = "【关卡编辑】: %s" % lvl.level_name

	world = GridWorld.new()
	for item in lvl.blocks_data:
		if item is Dictionary:
			var b := BlockData.from_dict(item)
			world.add_block(b)

	initial_snapshot = world.clone()
	sim_engine = SimulationEngine.new(world)

	if grid_view != null:
		grid_view.is_level_editor_mode = true
		grid_view.player_build_area = lvl.player_build_area
		grid_view.set_world(world)

	if camera != null:
		var bounds := world.get_bounds()
		camera.position = Vector2(bounds.position.x + bounds.size.x * 0.5, bounds.position.y + bounds.size.y * 0.5) * 64.0

	_update_build_area_label()

func _update_build_area_label() -> void:
	if build_area_info_lbl == null or current_level_data == null:
		return
	var a := current_level_data.player_build_area
	if a.size == Vector2i.ZERO:
		build_area_info_lbl.text = "建造区: 全图允许"
	else:
		build_area_info_lbl.text = "建造区: (%d,%d) %dx%d" % [a.position.x, a.position.y, a.size.x, a.size.y]

func _build_ui() -> void:
	# Canvas
	var canvas_node := Node2D.new()
	canvas_node.name = "Canvas"
	add_child(canvas_node)

	grid_view = GridView.new()
	grid_view.name = "GridView"
	grid_view.is_level_editor_mode = true
	canvas_node.add_child(grid_view)

	camera = CameraController.new()
	camera.name = "Camera2D"
	canvas_node.add_child(camera)

	# UI Layer (Keeps UI pinned to screen, unaffected by Camera2D)
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	add_child(ui_layer)

	# Top Bar
	var top_panel := PanelContainer.new()
	top_panel.theme = UI.get_game_theme()
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = UI.PANEL
	top_style.border_color = UI.BORDER
	top_style.set_border_width_all(1)
	top_style.content_margin_left = 16
	top_style.content_margin_right = 16
	top_style.content_margin_top = 6
	top_style.content_margin_bottom = 6
	top_panel.add_theme_stylebox_override("panel", top_style)
	ui_layer.add_child(top_panel)
	top_panel.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)

	var top_vbox := VBoxContainer.new()
	top_vbox.add_theme_constant_override("separation", 6)
	top_panel.add_child(top_vbox)

	# --- Row 1: Navigation, Level Name, and Build Area Tools ---
	var row1_hbox := HBoxContainer.new()
	row1_hbox.add_theme_constant_override("separation", 14)
	top_vbox.add_child(row1_hbox)

	var back_btn := Button.new()
	back_btn.text = "« 关卡管理"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.pressed.connect(func():
		MusicManager.play_ambient()
		get_tree().change_scene_to_file("res://scenes/ui/LevelManager.tscn")
	)
	row1_hbox.add_child(back_btn)

	level_name_lbl = Label.new()
	level_name_lbl.text = "【关卡编辑】"
	level_name_lbl.add_theme_font_size_override("font_size", 15)
	level_name_lbl.add_theme_color_override("font_color", UI.TEXT)
	row1_hbox.add_child(level_name_lbl)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1_hbox.add_child(spacer)

	build_area_info_lbl = Label.new()
	build_area_info_lbl.text = "建造区: 全图允许"
	build_area_info_lbl.add_theme_font_size_override("font_size", 14)
	build_area_info_lbl.add_theme_color_override("font_color", UI.ACCENT)
	row1_hbox.add_child(build_area_info_lbl)

	# Build area visual edit tools
	set_build_area_btn = Button.new()
	set_build_area_btn.text = "框选建造区"
	set_build_area_btn.toggle_mode = true
	set_build_area_btn.focus_mode = Control.FOCUS_NONE
	set_build_area_btn.custom_minimum_size = Vector2(90, 32)
	set_build_area_btn.tooltip_text = "点击后在网格上按住左键拖拽，直观划定玩家建造区域"
	set_build_area_btn.toggled.connect(func(pressed: bool):
		is_editing_build_area = pressed
		if pressed:
			set_build_area_btn.text = "拖拽网格以设定..."
			set_build_area_btn.modulate = UI.ACCENT
		else:
			set_build_area_btn.text = "框选建造区"
			set_build_area_btn.modulate = Color(1.0, 1.0, 1.0)
	)
	row1_hbox.add_child(set_build_area_btn)

	reset_build_area_btn = Button.new()
	reset_build_area_btn.text = "全图允许"
	reset_build_area_btn.focus_mode = Control.FOCUS_NONE
	reset_build_area_btn.custom_minimum_size = Vector2(76, 32)
	reset_build_area_btn.tooltip_text = "清除建造区限制（允许全图放置）"
	reset_build_area_btn.pressed.connect(func():
		if current_level_data:
			current_level_data.player_build_area = Rect2i()
			grid_view.player_build_area = Rect2i()
			grid_view.queue_redraw()
			_update_build_area_label()
	)
	row1_hbox.add_child(reset_build_area_btn)

	# --- Row 2: File/Blueprint and Test Simulation Controls ---
	var row2_hbox := HBoxContainer.new()
	row2_hbox.add_theme_constant_override("separation", 10)
	top_vbox.add_child(row2_hbox)

	clear_level_btn = Button.new()
	clear_level_btn.text = "清空画布"
	clear_level_btn.focus_mode = Control.FOCUS_NONE
	clear_level_btn.custom_minimum_size = Vector2(76, 32)
	clear_level_btn.tooltip_text = "清空关卡所有方块"
	clear_level_btn.pressed.connect(func():
		if not is_simulating and not is_animating_tick:
			clear_confirm.popup_centered(Vector2i(420, 180))
	)
	clear_confirm = ConfirmationDialog.new()
	clear_confirm.theme = UI.get_game_theme()
	clear_confirm.title = "清空关卡画布？"
	clear_confirm.dialog_text = "将移除画布中的全部方块。\n如需保留，请取消并先保存关卡。"
	clear_confirm.ok_button_text = "清空画布"
	clear_confirm.cancel_button_text = "保留画布"
	clear_confirm.confirmed.connect(clear_all_blocks)
	add_child(clear_confirm)
	row2_hbox.add_child(clear_level_btn)

	save_machine_btn = Button.new()
	save_machine_btn.text = "存图纸"
	save_machine_btn.focus_mode = Control.FOCUS_NONE
	save_machine_btn.custom_minimum_size = Vector2(64, 32)
	save_machine_btn.tooltip_text = "将当前机械结构保存为图纸"
	save_machine_btn.pressed.connect(_on_save_machine)
	row2_hbox.add_child(save_machine_btn)

	load_machine_btn = Button.new()
	load_machine_btn.text = "读图纸"
	load_machine_btn.focus_mode = Control.FOCUS_NONE
	load_machine_btn.custom_minimum_size = Vector2(64, 32)
	load_machine_btn.tooltip_text = "导入图纸"
	load_machine_btn.pressed.connect(_on_load_machine)
	row2_hbox.add_child(load_machine_btn)

	save_level_btn = Button.new()
	UI.game_primary(save_level_btn)
	save_level_btn.text = "保存关卡"
	save_level_btn.focus_mode = Control.FOCUS_NONE
	save_level_btn.custom_minimum_size = Vector2(80, 32)
	save_level_btn.pressed.connect(save_level_layout)
	row2_hbox.add_child(save_level_btn)

	var sep_sim := VSeparator.new()
	row2_hbox.add_child(sep_sim)

	# Test simulation buttons
	play_btn = Button.new()
	play_btn.text = "测试 [空格]"
	play_btn.focus_mode = Control.FOCUS_NONE
	play_btn.custom_minimum_size = Vector2(96, 32)
	play_btn.pressed.connect(toggle_simulation)
	row2_hbox.add_child(play_btn)

	step_btn = Button.new()
	step_btn.text = "单步"
	step_btn.focus_mode = Control.FOCUS_NONE
	step_btn.custom_minimum_size = Vector2(56, 32)
	step_btn.pressed.connect(step_tick)
	row2_hbox.add_child(step_btn)

	reset_btn = Button.new()
	reset_btn.text = "重置"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.custom_minimum_size = Vector2(56, 32)
	reset_btn.pressed.connect(reset_simulation)
	row2_hbox.add_child(reset_btn)

	var sep_speed := VSeparator.new()
	row2_hbox.add_child(sep_speed)

	# Speed slider: 0.2x to 20.0x (Logarithmic scale)
	var speed_hbox := HBoxContainer.new()
	speed_hbox.add_theme_constant_override("separation", 6)
	row2_hbox.add_child(speed_hbox)

	var speed_title := Label.new()
	speed_title.text = "速度:"
	speed_hbox.add_child(speed_title)

	speed_slider = HSlider.new()
	speed_slider.focus_mode = Control.FOCUS_NONE
	speed_slider.min_value = 0.2
	speed_slider.max_value = 20.0
	speed_slider.step = 0.05
	speed_slider.exp_edit = true
	speed_slider.value = 1.0
	speed_slider.custom_minimum_size = Vector2(80, 20)
	speed_slider.value_changed.connect(func(val: float):
		sim_speed_multiplier = val
		speed_label.text = "%.1fx" % val
	)
	speed_hbox.add_child(speed_slider)

	speed_label = Label.new()
	speed_label.text = "1.0x"
	speed_hbox.add_child(speed_label)

	# Bottom Toolbar (with all 10 blocks)
	toolbar = Toolbar.new()
	toolbar.name = "Toolbar"
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var btm_style := StyleBoxFlat.new()
	btm_style.bg_color = UI.PANEL
	btm_style.border_color = UI.BORDER
	btm_style.set_border_width_all(1)
	btm_style.set_corner_radius_all(8)
	btm_style.content_margin_left = 12
	btm_style.content_margin_right = 12
	btm_style.content_margin_top = 8
	btm_style.content_margin_bottom = 8
	toolbar.add_theme_stylebox_override("panel", btm_style)
	ui_layer.add_child(toolbar)
	toolbar.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	toolbar.offset_top = -56
	toolbar.offset_bottom = 0

	toolbar.setup(true) # Editor mode allows all 10 types
	toolbar.block_type_selected.connect(_on_toolbar_block_selected)
	toolbar.sub_mode_toggled.connect(_on_toolbar_sub_mode_toggled)
	toolbar.direction_changed.connect(_on_toolbar_direction_changed)
	toolbar.group_pressed.connect(group_selected_blocks)

	# Context Menu
	context_menu = EditorContextMenu.new()
	context_menu.item_selected.connect(_on_context_menu_action)
	ui_layer.add_child(context_menu)

func toggle_simulation() -> void:
	if is_simulating:
		is_simulating = false
		play_btn.text = "测试 [空格]"
	else:
		initial_snapshot = world.clone()
		is_simulating = true
		play_btn.text = "暂停 [空格]"
		MusicManager.play_running()
		_run_sim_loop()

func step_tick() -> void:
	if is_animating_tick:
		return
	MusicManager.play_running()
	is_animating_tick = true
	var res := sim_engine.step_tick()
	var duration := base_tick_duration / sim_speed_multiplier
	grid_view.play_tick_animation(res, duration, func():
		is_animating_tick = false
	)

func reset_simulation() -> void:
	is_simulating = false
	is_animating_tick = false
	play_btn.text = "测试 [空格]"
	MusicManager.play_ambient()

	world = initial_snapshot.clone()
	sim_engine = SimulationEngine.new(world)
	grid_view.set_world(world)

func _run_sim_loop() -> void:
	if not is_simulating or is_animating_tick:
		return
	is_animating_tick = true
	var res := sim_engine.step_tick()
	var duration := base_tick_duration / sim_speed_multiplier
	grid_view.play_tick_animation(res, duration, func():
		is_animating_tick = false
		if is_simulating:
			_run_sim_loop()
	)

func save_level_layout() -> void:
	if current_level_data == null:
		return
	var blocks_list: Array = []
	for b in world.get_all_blocks():
		blocks_list.append(b.to_dict())
	current_level_data.blocks_data = blocks_list
	SaveManager.save_level(current_level_data)
	initial_snapshot = world.clone()

	# Visual confirmation
	save_level_btn.text = "✓ 已保存！"
	var t := create_tween()
	t.tween_interval(1.5)
	t.tween_callback(func():
		save_level_btn.text = "保存关卡"
	)

func _process(_delta: float) -> void:
	if clear_level_btn != null: clear_level_btn.disabled = is_simulating or is_animating_tick
	if grid_view != null and toolbar != null:
		var mouse_world := grid_view.get_global_mouse_position()
		var grid_pos := grid_view.world_to_grid(mouse_world)
		if grid_view.is_multi_ghost_active():
			grid_view.update_multi_ghost_position(grid_pos)
			grid_view.update_preview(false, 0, 0, 0, 0, grid_pos)
		elif toolbar.is_placing and not is_simulating and not is_editing_build_area:
			grid_view.update_preview(
				true,
				toolbar.current_type,
				toolbar.current_dir,
				0,
				toolbar.current_sub_mode,
				grid_pos
			)
		else:
			grid_view.update_preview(false, 0, 0, 0, 0, grid_pos)

func _unhandled_input(event: InputEvent) -> void:
	# Build area visual drag editing mode
	if is_editing_build_area:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_world := grid_view.get_global_mouse_position()
			var grid_pos := grid_view.world_to_grid(mouse_world)
			if event.pressed:
				is_dragging_build_area = true
				build_area_drag_start = grid_pos
				grid_view.player_build_area = Rect2i(grid_pos.x, grid_pos.y, 1, 1)
				grid_view.queue_redraw()
				if build_area_info_lbl != null:
					build_area_info_lbl.text = "框选中: (%d,%d) 1x1" % [grid_pos.x, grid_pos.y]
			elif is_dragging_build_area:
				is_dragging_build_area = false
				var x1 := mini(build_area_drag_start.x, grid_pos.x)
				var y1 := mini(build_area_drag_start.y, grid_pos.y)
				var w := absi(grid_pos.x - build_area_drag_start.x) + 1
				var h := absi(grid_pos.y - build_area_drag_start.y) + 1
				var new_area := Rect2i(x1, y1, w, h)
				current_level_data.player_build_area = new_area
				grid_view.player_build_area = new_area
				grid_view.queue_redraw()
				_update_build_area_label()
				set_build_area_btn.button_pressed = false
				is_editing_build_area = false
			get_viewport().set_input_as_handled()
			return
		elif event is InputEventMouseMotion and is_dragging_build_area:
			var mouse_world := grid_view.get_global_mouse_position()
			var grid_pos := grid_view.world_to_grid(mouse_world)
			var x1 := mini(build_area_drag_start.x, grid_pos.x)
			var y1 := mini(build_area_drag_start.y, grid_pos.y)
			var w := absi(grid_pos.x - build_area_drag_start.x) + 1
			var h := absi(grid_pos.y - build_area_drag_start.y) + 1
			grid_view.player_build_area = Rect2i(x1, y1, w, h)
			grid_view.queue_redraw()
			if build_area_info_lbl != null:
				build_area_info_lbl.text = "框选中: (%d,%d) %dx%d" % [x1, y1, w, h]
			get_viewport().set_input_as_handled()
			return

	# Multi-block Ghost Preview Controls (Paste & Blueprint)
	if grid_view != null and grid_view.is_multi_ghost_active():
		var mouse_world := grid_view.get_global_mouse_position()
		var grid_pos := grid_view.world_to_grid(mouse_world)

		if KeybindManager.is_action_just_pressed(event, "rotate_ccw"):
			grid_view.rotate_multi_ghost_ccw()
			get_viewport().set_input_as_handled()
			return
		elif KeybindManager.is_action_just_pressed(event, "rotate_cw"):
			grid_view.rotate_multi_ghost_cw()
			get_viewport().set_input_as_handled()
			return
		elif KeybindManager.is_action_just_pressed(event, "flip_h"):
			grid_view.flip_multi_ghost_h()
			get_viewport().set_input_as_handled()
			return
		elif KeybindManager.is_action_just_pressed(event, "flip_v"):
			grid_view.flip_multi_ghost_v()
			get_viewport().set_input_as_handled()
			return
		elif KeybindManager.is_action_just_pressed(event, "cancel_tool") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			grid_view.cancel_multi_ghost()
			get_viewport().set_input_as_handled()
			return

		if event is InputEventMouseButton and event.pressed:
			if event.button_index == MOUSE_BUTTON_LEFT:
				if grid_view.can_place_multi_ghost():
					_try_place_ghost_blocks(grid_pos)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_RIGHT:
				grid_view.cancel_multi_ghost()
				get_viewport().set_input_as_handled()
				return

	# ESC: deselect current block tool -> enters selection state
	if toolbar != null and toolbar.is_placing:
		if KeybindManager.is_action_just_pressed(event, "cancel_tool") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			toolbar.deselect_tool()
			get_viewport().set_input_as_handled()
			return

	# Ctrl + Mouse Wheel cycles current block tool (Plain wheel zooms camera)
	if toolbar != null and event is InputEventMouseButton and event.pressed:
		var is_ctrl: bool = event.ctrl_pressed or Input.is_key_pressed(KEY_CTRL)
		if is_ctrl:
			if event.button_index == MOUSE_BUTTON_WHEEL_UP:
				toolbar.cycle_tool(-1)
				get_viewport().set_input_as_handled()
				return
			elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				toolbar.cycle_tool(1)
				get_viewport().set_input_as_handled()
				return

	# Undo / Redo Shortcuts
	if KeybindManager.is_action_just_pressed(event, "undo"):
		undo()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		return

	if KeybindManager.is_action_just_pressed(event, "redo"):
		redo()
		if get_viewport() != null:
			get_viewport().set_input_as_handled()
		return

	# Simulation Controls
	if KeybindManager.is_action_just_pressed(event, "toggle_sim"):
		toggle_simulation()
		get_viewport().set_input_as_handled()
		return

	if KeybindManager.is_action_just_pressed(event, "reset_sim"):
		reset_simulation()
		get_viewport().set_input_as_handled()
		return

	# Structure Grouping
	if KeybindManager.is_action_just_pressed(event, "group_structure"):
		group_selected_blocks()
		get_viewport().set_input_as_handled()
		return

	# Delete Selected Blocks (default key: X)
	if KeybindManager.is_action_just_pressed(event, "delete"):
		delete_selected_blocks()
		get_viewport().set_input_as_handled()
		return

	# Cut, Copy & Paste Shortcuts
	if KeybindManager.is_action_just_pressed(event, "cut"):
		if not selected_blocks.is_empty():
			cut_selected_blocks()
			get_viewport().set_input_as_handled()
			return

	if KeybindManager.is_action_just_pressed(event, "copy"):
		if not selected_blocks.is_empty():
			EditorClipboard.copy(selected_blocks)
			get_viewport().set_input_as_handled()
			return

	if KeybindManager.is_action_just_pressed(event, "paste"):
		if EditorClipboard.has_blocks():
			_start_paste_preview(EditorClipboard.get_blocks())
			get_viewport().set_input_as_handled()
			return

	# Transforms on selected blocks or placement tool
	if not selected_blocks.is_empty():
		if KeybindManager.is_action_just_pressed(event, "rotate_cw"):
			_rotate_selected_blocks_cw()
			get_viewport().set_input_as_handled()
			return
		elif KeybindManager.is_action_just_pressed(event, "rotate_ccw"):
			_rotate_selected_blocks_ccw()
			get_viewport().set_input_as_handled()
			return
		elif KeybindManager.is_action_just_pressed(event, "flip_h"):
			_flip_selected_blocks_h()
			get_viewport().set_input_as_handled()
			return
		elif KeybindManager.is_action_just_pressed(event, "flip_v"):
			_flip_selected_blocks_v()
			get_viewport().set_input_as_handled()
			return
	elif toolbar != null and toolbar.is_placing:
		if KeybindManager.is_action_just_pressed(event, "rotate_cw"):
			toolbar.rotate_direction(1)
			get_viewport().set_input_as_handled()
			return
		elif KeybindManager.is_action_just_pressed(event, "rotate_ccw"):
			toolbar.rotate_direction(-1)
			get_viewport().set_input_as_handled()
			return
		elif KeybindManager.is_action_just_pressed(event, "flip_h"):
			toolbar.toggle_sub_mode()
			get_viewport().set_input_as_handled()
			return

	# Number keys: 1..9, 0 for all blocks
	if event is InputEventKey and event.pressed and not event.echo:
		var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
		if code >= KEY_1 and code <= KEY_9:
			_clear_selection()
			toolbar.select_type(code - KEY_1)
			get_viewport().set_input_as_handled()
			return
		elif code == KEY_0:
			_clear_selection()
			toolbar.select_type(BlockData.Type.POLLUTION)
			get_viewport().set_input_as_handled()
			return
		elif code == KEY_MINUS:
			_clear_selection()
			toolbar.select_type(BlockData.Type.PROTECTED)
			get_viewport().set_input_as_handled()
			return

	# Mouse clicks
	if event is InputEventMouseButton:
		var mouse_world := grid_view.get_global_mouse_position()
		var grid_pos := grid_view.world_to_grid(mouse_world)

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if toolbar.is_placing:
					record_undo()
					is_mouse_placing = true
					last_editor_grid = grid_pos
					_place_block_editor(grid_pos)
				else:
					# Selection mode
					if Input.is_key_pressed(KEY_SHIFT):
						var b := world.get_block(grid_pos)
						if b != null:
							_toggle_select(b)
						else:
							is_box_selecting = true
							box_select_start_world = mouse_world
							grid_view.is_box_selecting = true
							grid_view.box_select_start = mouse_world
							grid_view.box_select_current = mouse_world
							grid_view.queue_redraw()
					else:
						# "当选中一个或一些方块时,左键单击会取消选择"
						var clicked_b := world.get_block(grid_pos)
						if not selected_blocks.is_empty():
							_clear_selection()
							if clicked_b != null:
								_toggle_select(clicked_b)
						else:
							if clicked_b != null:
								_toggle_select(clicked_b)
							else:
								is_box_selecting = true
								box_select_start_world = mouse_world
								grid_view.is_box_selecting = true
								grid_view.box_select_start = mouse_world
								grid_view.box_select_current = mouse_world
								grid_view.queue_redraw()
			else:
				is_mouse_placing = false
				last_editor_grid = Vector2i(-999999, -999999)
				if is_box_selecting:
					is_box_selecting = false
					grid_view.is_box_selecting = false
					_finish_box_select()
					grid_view.queue_redraw()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if toolbar.is_placing:
					record_undo()
					is_mouse_erasing = true
					last_editor_grid = grid_pos
					_erase_block_editor(grid_pos)
				else:
					# Selection Mode: Start right drag panning or context menu
					is_right_mouse_down = true
					is_right_panning = false
					right_mouse_down_pos = event.position
			else:
				if toolbar.is_placing:
					is_mouse_erasing = false
					last_editor_grid = Vector2i(-999999, -999999)
				else:
					if is_right_mouse_down:
						is_right_mouse_down = false
						if not is_right_panning:
							# Single right click without drag
							var can_copy_or_cut := not selected_blocks.is_empty()
							var can_paste := EditorClipboard.has_blocks()
							if can_copy_or_cut or can_paste or can_undo() or can_redo():
								context_menu.popup_at(event.position, can_paste, can_copy_or_cut, can_undo(), can_redo())
						is_right_panning = false

	elif event is InputEventMouseMotion:
		var mouse_world := grid_view.get_global_mouse_position()
		var grid_pos := grid_view.world_to_grid(mouse_world)

		if is_right_mouse_down and not toolbar.is_placing:
			if not is_right_panning and (event.position - right_mouse_down_pos).length() > right_pan_drag_threshold:
				is_right_panning = true
			if is_right_panning and camera != null:
				camera.pan_by_screen_delta(event.relative)
				get_viewport().set_input_as_handled()
				return

		if is_right_dragging_selection:
			var delta := grid_pos - right_drag_start_grid
			for b in selected_blocks:
				var v := grid_view.get_view(b.block_id)
				if v != null and right_drag_orig_positions.has(b):
					var preview_pos: Vector2i = right_drag_orig_positions[b] + delta
					v.position = grid_view.grid_to_world(preview_pos)
			grid_view.queue_redraw()
		elif is_mouse_placing:
			if grid_pos != last_editor_grid:
				last_editor_grid = grid_pos
				_place_block_editor(grid_pos)
		elif is_mouse_erasing:
			if grid_pos != last_editor_grid:
				last_editor_grid = grid_pos
				_erase_block_editor(grid_pos)
		elif is_box_selecting:
			grid_view.box_select_current = mouse_world
			grid_view.queue_redraw()

func _on_context_menu_action(action: String) -> void:
	match action:
		"undo":
			undo()
		"redo":
			redo()
		"copy":
			if not selected_blocks.is_empty():
				EditorClipboard.copy(selected_blocks)
		"cut":
			cut_selected_blocks()
		"paste":
			if EditorClipboard.has_blocks():
				_start_paste_preview(EditorClipboard.get_blocks())
		"delete":
			delete_selected_blocks()
		"rotate_cw":
			_rotate_selected_blocks_cw()
		"rotate_ccw":
			_rotate_selected_blocks_ccw()
		"flip_h":
			_flip_selected_blocks_h()
		"flip_v":
			_flip_selected_blocks_v()

func _start_paste_preview(blocks: Array[BlockData]) -> void:
	if blocks.is_empty(): return
	_clear_selection()
	if toolbar != null:
		toolbar.deselect_tool()
	grid_view.start_multi_ghost(blocks)

func _try_place_ghost_blocks(mouse_grid: Vector2i) -> void:
	if not grid_view.can_place_multi_ghost():
		return
	var new_blocks := grid_view.get_multi_ghost_blocks_to_place(mouse_grid)
	if new_blocks.is_empty():
		return
	record_undo()

	var sid_map: Dictionary = {}
	for b in new_blocks:
		if b.structure_id > 0:
			if not sid_map.has(b.structure_id):
				sid_map[b.structure_id] = world.create_new_structure_id()
			b.structure_id = sid_map[b.structure_id]
		b.block_id = BlockData.generate_new_id()
		b.origin_id = b.block_id
		b.is_world_block = true
		world.add_block(b)

	grid_view.cancel_multi_ghost()
	initial_snapshot = world.clone()
	SoundManager.play_cell_place(grid_view.grid_to_world(mouse_grid))

func _rotate_selected_blocks_cw() -> void:
	if selected_blocks.is_empty(): return
	record_undo()
	var sum := Vector2.ZERO
	for b in selected_blocks: sum += Vector2(b.grid_pos)
	var center := sum / float(selected_blocks.size())
	var anchor := Vector2i(int(round(center.x)), int(round(center.y)))

	var moves: Array[Dictionary] = []
	for b in selected_blocks:
		var rel: Vector2i = b.grid_pos - anchor
		var new_rel := Vector2i(-rel.y, rel.x)
		var new_dir: int = (b.direction + 1) % 4
		moves.append({ "block": b, "old_pos": b.grid_pos, "new_pos": anchor + new_rel, "new_dir": new_dir })

	for m in moves:
		world._cells.erase(m["old_pos"])

	for m in moves:
		var occupant = world.get_block(m["new_pos"])
		if occupant != null and occupant not in selected_blocks:
			world.remove_block_at(m["new_pos"])

	for m in moves:
		var b: BlockData = m["block"]
		b.grid_pos = m["new_pos"]
		b.direction = m["new_dir"]
		world._cells[b.grid_pos] = b
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.position = grid_view.grid_to_world(b.grid_pos)
			v.update_appearance()

	grid_view.queue_redraw()
	initial_snapshot = world.clone()

func _rotate_selected_blocks_ccw() -> void:
	if selected_blocks.is_empty(): return
	record_undo()
	var sum := Vector2.ZERO
	for b in selected_blocks: sum += Vector2(b.grid_pos)
	var center := sum / float(selected_blocks.size())
	var anchor := Vector2i(int(round(center.x)), int(round(center.y)))

	var moves: Array[Dictionary] = []
	for b in selected_blocks:
		var rel: Vector2i = b.grid_pos - anchor
		var new_rel := Vector2i(rel.y, -rel.x)
		var new_dir: int = (b.direction + 3) % 4
		moves.append({ "block": b, "old_pos": b.grid_pos, "new_pos": anchor + new_rel, "new_dir": new_dir })

	for m in moves:
		world._cells.erase(m["old_pos"])

	for m in moves:
		var occupant = world.get_block(m["new_pos"])
		if occupant != null and occupant not in selected_blocks:
			world.remove_block_at(m["new_pos"])

	for m in moves:
		var b: BlockData = m["block"]
		b.grid_pos = m["new_pos"]
		b.direction = m["new_dir"]
		world._cells[b.grid_pos] = b
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.position = grid_view.grid_to_world(b.grid_pos)
			v.update_appearance()

	grid_view.queue_redraw()
	initial_snapshot = world.clone()

func _flip_selected_blocks_h() -> void:
	if selected_blocks.is_empty(): return
	record_undo()
	var sum := Vector2.ZERO
	for b in selected_blocks: sum += Vector2(b.grid_pos)
	var center := sum / float(selected_blocks.size())
	var anchor := Vector2i(int(round(center.x)), int(round(center.y)))

	var moves: Array[Dictionary] = []
	for b in selected_blocks:
		var rel: Vector2i = b.grid_pos - anchor
		var new_rel := Vector2i(-rel.x, rel.y)
		var new_dir: int = b.direction
		match b.direction:
			BlockData.Direction.RIGHT: new_dir = BlockData.Direction.LEFT
			BlockData.Direction.LEFT: new_dir = BlockData.Direction.RIGHT
		var new_sub: int = b.sub_mode
		if b.block_type == BlockData.Type.ROTATOR:
			new_sub = 1 - b.sub_mode
		moves.append({ "block": b, "old_pos": b.grid_pos, "new_pos": anchor + new_rel, "new_dir": new_dir, "new_sub": new_sub })

	for m in moves:
		world._cells.erase(m["old_pos"])

	for m in moves:
		var occupant = world.get_block(m["new_pos"])
		if occupant != null and occupant not in selected_blocks:
			world.remove_block_at(m["new_pos"])

	for m in moves:
		var b: BlockData = m["block"]
		b.grid_pos = m["new_pos"]
		b.direction = m["new_dir"]
		b.sub_mode = m["new_sub"]
		world._cells[b.grid_pos] = b
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.position = grid_view.grid_to_world(b.grid_pos)
			v.update_appearance()

	grid_view.queue_redraw()
	initial_snapshot = world.clone()

func _flip_selected_blocks_v() -> void:
	if selected_blocks.is_empty(): return
	record_undo()
	var sum := Vector2.ZERO
	for b in selected_blocks: sum += Vector2(b.grid_pos)
	var center := sum / float(selected_blocks.size())
	var anchor := Vector2i(int(round(center.x)), int(round(center.y)))

	var moves: Array[Dictionary] = []
	for b in selected_blocks:
		var rel: Vector2i = b.grid_pos - anchor
		var new_rel := Vector2i(rel.x, -rel.y)
		var new_dir: int = b.direction
		match b.direction:
			BlockData.Direction.DOWN: new_dir = BlockData.Direction.UP
			BlockData.Direction.UP: new_dir = BlockData.Direction.DOWN
		var new_sub: int = b.sub_mode
		if b.block_type == BlockData.Type.ROTATOR:
			new_sub = 1 - b.sub_mode
		moves.append({ "block": b, "old_pos": b.grid_pos, "new_pos": anchor + new_rel, "new_dir": new_dir, "new_sub": new_sub })

	for m in moves:
		world._cells.erase(m["old_pos"])

	for m in moves:
		var occupant = world.get_block(m["new_pos"])
		if occupant != null and occupant not in selected_blocks:
			world.remove_block_at(m["new_pos"])

	for m in moves:
		var b: BlockData = m["block"]
		b.grid_pos = m["new_pos"]
		b.direction = m["new_dir"]
		b.sub_mode = m["new_sub"]
		world._cells[b.grid_pos] = b
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.position = grid_view.grid_to_world(b.grid_pos)
			v.update_appearance()

	grid_view.queue_redraw()
	initial_snapshot = world.clone()

func _place_block_editor(grid_pos: Vector2i) -> void:
	if is_simulating:
		return
	if world.has_block(grid_pos):
		var existing := world.get_block(grid_pos)
		if existing.block_type == toolbar.current_type and existing.direction == toolbar.current_dir and existing.sub_mode == toolbar.current_sub_mode:
			return
	world.remove_block_at(grid_pos)
	var new_block := BlockData.new(toolbar.current_type, grid_pos, toolbar.current_dir)
	new_block.sub_mode = toolbar.current_sub_mode
	new_block.is_world_block = true
	world.add_block(new_block)
	SoundManager.play_cell_place(grid_view.grid_to_world(grid_pos))
	initial_snapshot = world.clone()

func _erase_block_editor(grid_pos: Vector2i) -> void:
	if is_simulating:
		return
	if not world.has_block(grid_pos):
		return
	world.remove_block_at(grid_pos)
	SoundManager.play_cell_delete(grid_view.grid_to_world(grid_pos))
	initial_snapshot = world.clone()

func _clear_selection() -> void:
	for b in selected_blocks:
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.is_selected = false
			v.queue_redraw()
	selected_blocks.clear()

func _toggle_select(b: BlockData) -> void:
	if b in selected_blocks:
		selected_blocks.erase(b)
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.is_selected = false
			v.queue_redraw()
	else:
		selected_blocks.append(b)
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.is_selected = true
			v.queue_redraw()

func _finish_box_select() -> void:
	var r := Rect2(box_select_start_world, grid_view.box_select_current - box_select_start_world).abs()
	var min_grid := grid_view.world_to_grid(r.position)
	var max_grid := grid_view.world_to_grid(r.position + r.size)

	for y in range(min_grid.y, max_grid.y + 1):
		for x in range(min_grid.x, max_grid.x + 1):
			var b := world.get_block(Vector2i(x, y))
			if b != null and b not in selected_blocks:
				selected_blocks.append(b)
				var v := grid_view.get_view(b.block_id)
				if v != null:
					v.is_selected = true
					v.queue_redraw()

func group_selected_blocks() -> void:
	if selected_blocks.is_empty():
		return
	record_undo()
	world.group_blocks(selected_blocks)
	for b in selected_blocks:
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.update_appearance()
	initial_snapshot = world.clone()

func cut_selected_blocks() -> void:
	if selected_blocks.is_empty():
		return
	EditorClipboard.copy(selected_blocks)
	var blocks_to_paste := EditorClipboard.get_blocks()
	delete_selected_blocks()
	_start_paste_preview(blocks_to_paste)

func delete_selected_blocks() -> void:
	if selected_blocks.is_empty():
		return
	record_undo()
	var delete_pos := grid_view.grid_to_world(selected_blocks[0].grid_pos)
	for b in selected_blocks:
		world.remove_block_at(b.grid_pos)
	selected_blocks.clear()
	SoundManager.play_cell_delete(delete_pos)
	initial_snapshot = world.clone()

func _get_selection_bounds() -> Rect2i:
	if selected_blocks.is_empty():
		return Rect2i()
	var min_p := Vector2i(999999, 999999)
	var max_p := Vector2i(-999999, -999999)
	for b in selected_blocks:
		min_p.x = mini(min_p.x, b.grid_pos.x)
		min_p.y = mini(min_p.y, b.grid_pos.y)
		max_p.x = maxi(max_p.x, b.grid_pos.x)
		max_p.y = maxi(max_p.y, b.grid_pos.y)
	return Rect2i(min_p.x, min_p.y, max_p.x - min_p.x + 1, max_p.y - min_p.y + 1)

func _apply_selection_drag(delta: Vector2i) -> void:
	if selected_blocks.is_empty() or delta == Vector2i.ZERO:
		return
	record_undo()

	var new_positions: Dictionary = {}
	for b in selected_blocks:
		if right_drag_orig_positions.has(b):
			new_positions[b] = right_drag_orig_positions[b] + delta
		else:
			new_positions[b] = b.grid_pos + delta

	# 1. Remove unselected blocks colliding with new target positions
	for b in selected_blocks:
		var target_p: Vector2i = new_positions[b]
		var occupant := world.get_block(target_p)
		if occupant != null and occupant not in selected_blocks:
			world.remove_block_at(target_p)

	# 2. Batch move selected blocks
	var move_entries: Array[Dictionary] = []
	for b in selected_blocks:
		move_entries.append({
			"block": b,
			"old_pos": b.grid_pos,
			"new_pos": new_positions[b]
		})
	world.batch_move_blocks(move_entries)

	# 3. Synchronize views and visual appearance
	for b in selected_blocks:
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.position = grid_view.grid_to_world(b.grid_pos)
			v.update_appearance()

	initial_snapshot = world.clone()

func clear_all_blocks() -> void:
	record_undo()
	world.clear()
	selected_blocks.clear()
	initial_snapshot = world.clone()
	sim_engine = SimulationEngine.new(world)

func _on_save_machine() -> void:
	var has_sel := not selected_blocks.is_empty()
	var target_parent: Node = self
	if ui_layer != null:
		target_parent = ui_layer
	BlueprintDialogs.show_save_dialog(target_parent, has_sel, func(m_name: String, only_selected: bool):
		var target_blocks: Array[BlockData] = []
		if only_selected and not selected_blocks.is_empty():
			target_blocks = selected_blocks.duplicate()
		else:
			target_blocks = world.get_all_blocks().duplicate()
		SaveManager.save_machine(m_name, target_blocks)
	)

func _on_load_machine() -> void:
	var target_parent: Node = self
	if ui_layer != null:
		target_parent = ui_layer
	BlueprintDialogs.show_load_dialog(target_parent, func(m_name: String):
		var blocks := SaveManager.load_machine(m_name)
		if blocks.is_empty():
			return
		_start_paste_preview(blocks)
	)

# -------------------------------------------------------------
# Toolbar signal handlers
# -------------------------------------------------------------
func _on_toolbar_block_selected(btype: int) -> void:
	if btype >= 0:
		_clear_selection()
		if grid_view != null and grid_view.is_multi_ghost_active():
			grid_view.cancel_multi_ghost()

func _on_toolbar_sub_mode_toggled(mode: int) -> void:
	if selected_blocks.is_empty():
		return
	var any_changed := false
	for b in selected_blocks:
		if b.sub_mode != mode:
			any_changed = true
			break
	if not any_changed:
		return
	record_undo()
	for b in selected_blocks:
		b.sub_mode = mode
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.update_appearance()
	initial_snapshot = world.clone()

func _on_toolbar_direction_changed(dir: int) -> void:
	if selected_blocks.is_empty():
		return
	var any_changed := false
	for b in selected_blocks:
		if b.direction != dir:
			any_changed = true
			break
	if not any_changed:
		return
	record_undo()
	for b in selected_blocks:
		b.direction = dir
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.update_appearance()
	initial_snapshot = world.clone()

