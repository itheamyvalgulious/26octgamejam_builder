class_name LevelPlayer
extends Control

const Campaign = preload("res://scripts/core/Campaign.gd")
const UI = preload("res://scripts/ui/UIStyle.gd")
var status_label: Label
var clear_confirm: ConfirmationDialog
var edit_move_origin: Array[Vector2i] = []
var clear_button: Button
var load_button: Button

const TutorialGuideScript = preload("res://scripts/ui/TutorialGuide.gd")
const TutorialRules = preload("res://scripts/core/TutorialRules.gd")
const DialogueScript = preload("res://scripts/ui/TutorialDialogue.gd")
var tutorial_dialogue: DialogueScript
var tutorial_guide: TutorialGuideScript
const TutorialActs = preload("res://scripts/core/TutorialActs.gd")
var tutorial_root: LevelData
var tutorial_act := 0
var tutorial_transition := ""
var tutorial_transition_pending := false
var tutorial_first_ticks := 0
var tutorial_camera_tween: Tween
var tutorial_departure: GridView
var tutorial_pan_blocker: Control
var tick_generation := 0

signal back_to_menu_requested()

# Current level data & state
var current_level_data: LevelData
var current_level_index: int = 0
var all_levels: Array[LevelData] = []

var world: GridWorld
var initial_snapshot: GridWorld # For Reset functionality
var sim_engine: SimulationEngine

# Visual nodes
var camera: CameraController
var grid_view: GridView
var toolbar: Toolbar
var victory_dialog: VictoryDialog

# Top bar controls
var play_btn: Button
var step_btn: Button
var reset_btn: Button
var speed_slider: HSlider
var speed_label: Label
var goal_label: Label
var level_title_label: Label
var build_area_warning_panel: PanelContainer
var build_area_warning_label: Label

# Simulation running state
var is_simulating: bool = false
var is_animating_tick: bool = false
var has_simulated: bool = false
var sim_speed_multiplier: float = 1.0 # 0.2x ~ 20.0x
var base_tick_duration: float = 0.35 # seconds
var ui_layer: CanvasLayer

# Selection & Editing state
var selected_blocks: Array[BlockData] = []
var is_mouse_placing: bool = false
var is_mouse_erasing: bool = false
var last_player_grid: Vector2i = Vector2i(-999999, -999999)
var is_box_selecting: bool = false
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
	if is_simulating or is_animating_tick or has_simulated:
		return
	undo_stack.append(world.clone())
	if undo_stack.size() > MAX_UNDO_STACK:
		undo_stack.pop_front()
	redo_stack.clear()

func can_undo() -> bool:
	return not is_simulating and not is_animating_tick and not has_simulated and not undo_stack.is_empty()

func can_redo() -> bool:
	return not is_simulating and not is_animating_tick and not has_simulated and not redo_stack.is_empty()

func undo() -> void:
	if not can_undo():
		return
	redo_stack.append(world.clone())
	var prev_world: GridWorld = undo_stack.pop_back()
	world = prev_world.clone()
	initial_snapshot = world.clone()
	sim_engine = SimulationEngine.new(world, current_level_data.player_build_area if current_level_data else Rect2i())
	sim_engine.construction_inspection = current_level_data != null and current_level_data.tutorial.get("goal", "") == "connect"
	sim_engine.level_won.connect(_on_level_won)
	_clear_selection()
	if grid_view != null:
		grid_view.cancel_multi_ghost()
		grid_view.set_world(world)
	_update_build_area_status()

func redo() -> void:
	if not can_redo():
		return
	undo_stack.append(world.clone())
	var next_world: GridWorld = redo_stack.pop_back()
	world = next_world.clone()
	initial_snapshot = world.clone()
	sim_engine = SimulationEngine.new(world, current_level_data.player_build_area if current_level_data else Rect2i())
	sim_engine.construction_inspection = current_level_data != null and current_level_data.tutorial.get("goal", "") == "connect"
	sim_engine.level_won.connect(_on_level_won)
	_clear_selection()
	if grid_view != null:
		grid_view.cancel_multi_ghost()
		grid_view.set_world(world)
	_update_build_area_status()

func _ready() -> void:
	KeybindManager.init_keybinds()
	theme = UI.get_game_theme()
	RenderingServer.set_default_clear_color(UI.BG)
	# Let board clicks reach _unhandled_input; UI panels still consume theirs.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	SaveManager.init_directories()
	all_levels = SaveManager.get_all_levels()

	_build_ui_layout()

	# If no specific level was set externally, load the first level
	if current_level_data == null:
		if not all_levels.is_empty():
			load_level_by_index(0)
		else:
			var default_lvl := LevelData.new("default", "启蒙空间")
			load_level_data(default_lvl)

func load_level_by_index(idx: int) -> void:
	if idx >= 0 and idx < all_levels.size():
		if not Campaign.is_unlocked(all_levels[idx].level_id): return
		current_level_index = idx
		load_level_data(all_levels[idx])

func load_level_data(lvl_data: LevelData) -> void:
	_cancel_tutorial_transition()
	tutorial_root = lvl_data
	tutorial_act = 0
	tutorial_first_ticks = 0
	_apply_level_data(lvl_data)

func _apply_level_data(lvl_data: LevelData, show_intro: bool = true) -> void:
	edit_move_origin.clear()
	tick_generation += 1
	undo_stack.clear()
	redo_stack.clear()
	MusicManager.play_ambient()
	grid_view.cancel_multi_ghost()
	toolbar.deselect_tool()
	selected_blocks.clear()
	if victory_dialog != null: victory_dialog.hide()
	current_level_data = lvl_data
	Campaign.active_level = lvl_data.level_id
	if level_title_label != null:
		level_title_label.text = lvl_data.level_name

	# Build world from level blocks
	world = GridWorld.new()
	for item in lvl_data.blocks_data:
		if item is Dictionary:
			var b := BlockData.from_dict(item)
			world.add_block(b)

	# Take pristine snapshot
	initial_snapshot = world.clone()

	# Setup simulation engine
	sim_engine = SimulationEngine.new(world, lvl_data.player_build_area)
	sim_engine.construction_inspection = lvl_data.tutorial.get("goal", "") == "connect"
	sim_engine.level_won.connect(_on_level_won)

	# Setup grid view
	if grid_view != null:
		grid_view.player_build_area = lvl_data.player_build_area
		grid_view.is_level_editor_mode = false
		grid_view.set_world(world)

	# Center camera
	if camera != null:
		var bounds := world.get_bounds()
		var center := Vector2(bounds.position.x + bounds.size.x * 0.5, bounds.position.y + bounds.size.y * 0.5) * 64.0
		camera.position = center
		if not lvl_data.tutorial.is_empty():
			# Keep the small teaching board to the left of the guide panel.
			camera.position = center + Vector2(float(lvl_data.tutorial.get("camera_offset_x", 160)), 0)
			camera.zoom = Vector2.ONE * float(lvl_data.tutorial.get("camera_zoom", 1.0))

	is_simulating = false
	is_animating_tick = false
	has_simulated = false
	if tutorial_guide != null:
		tutorial_guide.configure(lvl_data.tutorial)
		if lvl_data.tutorial.has("act_title"):
			tutorial_guide.restart_button.text = "重来当前幕"
			level_title_label.text = lvl_data.level_name + " · " + str(lvl_data.tutorial.act_title)
	var types: Array = []
	for key in lvl_data.tutorial.get("equipment", {}): types.append(int(key))
	toolbar.set_allowed_types(types)
	toolbar.set_direct_placement_enabled(not lvl_data.tutorial.get("no_direct_placement", false))
	if lvl_data.tutorial.get("edit_sequence", "") == "move_then_copy": EditorClipboard.clear()
	tutorial_dialogue.hide()
	camera.set_process(true)
	if show_intro: _show_tutorial_dialogue()
	_refresh_tutorial()
	_update_sim_buttons()
	_update_goal_display()
	_update_build_area_status()

func _build_ui_layout() -> void:
	# 1. 2D World Canvas Node
	var canvas_node := Node2D.new()
	canvas_node.name = "Canvas"
	add_child(canvas_node)

	grid_view = GridView.new()
	grid_view.name = "GridView"
	canvas_node.add_child(grid_view)

	camera = CameraController.new()
	camera.name = "Camera2D"
	canvas_node.add_child(camera)

	# 2. UI Layer (Keeps UI pinned to screen, unaffected by Camera2D)
	ui_layer = CanvasLayer.new()
	ui_layer.name = "UILayer"
	add_child(ui_layer)

	var top_panel := PanelContainer.new()
	top_panel.theme = UI.get_game_theme()
	var top_style := StyleBoxFlat.new()
	top_style.bg_color = UI.PANEL
	top_style.border_color = UI.BORDER
	top_style.set_corner_radius_all(0)
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

	# --- Row 1: Navigation, Level Info, and Goal Badge ---
	var row1_hbox := HBoxContainer.new()
	row1_hbox.add_theme_constant_override("separation", 16)
	top_vbox.add_child(row1_hbox)

	var back_btn := Button.new()
	back_btn.text = "‹ 章节地图"
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.pressed.connect(func():
		back_to_menu_requested.emit()
		get_tree().change_scene_to_file("res://scenes/ui/LevelSelect.tscn")
	)
	row1_hbox.add_child(back_btn)

	level_title_label = Label.new()
	level_title_label.text = "关卡标题"
	level_title_label.add_theme_font_size_override("font_size", 15)
	level_title_label.add_theme_color_override("font_color", UI.TEXT)
	row1_hbox.add_child(level_title_label)
	var frame_btn := Button.new()
	frame_btn.text = "全景"
	frame_btn.tooltip_text = "将所有目标与建造区放回画面中心（Home）"
	frame_btn.focus_mode = Control.FOCUS_NONE
	frame_btn.pressed.connect(frame_board)
	row1_hbox.add_child(frame_btn)
	var help_btn := Button.new()
	help_btn.text = "操作手册 · F1"
	help_btn.focus_mode = Control.FOCUS_NONE
	help_btn.pressed.connect(show_help)
	row1_hbox.add_child(help_btn)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row1_hbox.add_child(spacer)

	# Goal status display (Pill badge)
	goal_label = Label.new()
	goal_label.text = "[目标] 污染源剩余: 0 | 待回收宝藏: 0"
	goal_label.add_theme_font_size_override("font_size", 14)
	goal_label.add_theme_color_override("font_color", UI.ACCENT)
	row1_hbox.add_child(goal_label)

	# --- Row 2: Blueprint Management & Simulation Controls ---
	var row2_hbox := HBoxContainer.new()
	row2_hbox.add_theme_constant_override("separation", 10)
	top_vbox.add_child(row2_hbox)

	var clear_btn := Button.new()
	clear_button = clear_btn
	clear_btn.text = "清空构装"
	clear_btn.focus_mode = Control.FOCUS_NONE
	clear_btn.custom_minimum_size = Vector2(76, 32)
	clear_btn.tooltip_text = "清空建造区内所有自建方块"
	clear_btn.pressed.connect(func(): clear_confirm.popup_centered(Vector2i(420, 180)))
	row2_hbox.add_child(clear_btn)

	var save_btn := Button.new()
	save_btn.text = "存图纸"
	save_btn.focus_mode = Control.FOCUS_NONE
	save_btn.custom_minimum_size = Vector2(64, 32)
	save_btn.tooltip_text = "将当前建造的机械保存为图纸"
	save_btn.pressed.connect(_on_save_machine_pressed)
	row2_hbox.add_child(save_btn)

	var load_btn := Button.new()
	load_button = load_btn
	load_btn.text = "读图纸"
	load_btn.focus_mode = Control.FOCUS_NONE
	load_btn.custom_minimum_size = Vector2(64, 32)
	load_btn.tooltip_text = "加载已保存的机械图纸"
	load_btn.pressed.connect(_on_load_machine_pressed)
	row2_hbox.add_child(load_btn)

	var sep_sim := VSeparator.new()
	row2_hbox.add_child(sep_sim)

	# Sim control buttons
	play_btn = Button.new()
	UI.game_primary(play_btn)
	play_btn.text = "开始 [空格]"
	play_btn.focus_mode = Control.FOCUS_NONE
	play_btn.custom_minimum_size = Vector2(96, 32)
	play_btn.pressed.connect(toggle_simulation)
	row2_hbox.add_child(play_btn)

	step_btn = Button.new()
	step_btn.text = "单步"
	step_btn.focus_mode = Control.FOCUS_NONE
	step_btn.custom_minimum_size = Vector2(56, 32)
	step_btn.pressed.connect(step_single_tick)
	row2_hbox.add_child(step_btn)

	reset_btn = Button.new()
	reset_btn.text = "重置 [R]"
	reset_btn.focus_mode = Control.FOCUS_NONE
	reset_btn.custom_minimum_size = Vector2(64, 32)
	reset_btn.tooltip_text = "恢复运行前的构装，保留你放置的方块，并恢复编辑（R）"
	reset_btn.pressed.connect(reset_simulation)
	row2_hbox.add_child(reset_btn)

	build_area_warning_panel = PanelContainer.new()
	var warn_style := StyleBoxFlat.new()
	warn_style.bg_color = Color(0.65, 0.12, 0.12, 0.88)
	warn_style.border_color = Color(1.0, 0.35, 0.35, 0.95)
	warn_style.set_border_width_all(1)
	warn_style.set_corner_radius_all(6)
	warn_style.content_margin_left = 10
	warn_style.content_margin_right = 10
	warn_style.content_margin_top = 4
	warn_style.content_margin_bottom = 4
	build_area_warning_panel.add_theme_stylebox_override("panel", warn_style)

	build_area_warning_label = Label.new()
	build_area_warning_label.text = "⚠️ 建造区外存在方块，无法启动模拟！"
	build_area_warning_label.add_theme_font_size_override("font_size", 13)
	build_area_warning_label.add_theme_color_override("font_color", Color(1.0, 0.95, 0.9))
	build_area_warning_panel.add_child(build_area_warning_label)
	build_area_warning_panel.visible = false
	row2_hbox.add_child(build_area_warning_panel)

	var sep2 := VSeparator.new()
	row2_hbox.add_child(sep2)

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
	# The primary action determines row height; secondary controls stay compact.
	for button in [clear_btn, save_btn, load_btn, step_btn, reset_btn]:
		button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	speed_hbox.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row2_hbox.move_child(play_btn, 0)
	row2_hbox.move_child(step_btn, 1)
	row2_hbox.move_child(reset_btn, 2)
	row2_hbox.move_child(sep_sim, 3)
	status_label = UI.label(top_vbox, "构装中 · 在绿色区域内放置方块", 14, UI.MUTED)
	clear_confirm = ConfirmationDialog.new()
	clear_confirm.theme = UI.get_game_theme()
	clear_confirm.title = "清空当前构装？"
	clear_confirm.dialog_text = "将移除所有自建方块，关卡预设保持不变。\n此操作无法撤销；需要保留时请先保存图纸。"
	clear_confirm.ok_button_text = "清空自建方块"
	clear_confirm.cancel_button_text = "保留构装"
	clear_confirm.confirmed.connect(clear_player_blocks)
	add_child(clear_confirm)


	# 3. Bottom Toolbar
	toolbar = Toolbar.new()
	toolbar.name = "Toolbar"
	toolbar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var btm_style := StyleBoxFlat.new()
	btm_style.bg_color = UI.PANEL
	btm_style.border_color = UI.BORDER
	btm_style.set_corner_radius_all(0)
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

	toolbar.setup(false) # Player mode
	toolbar.block_type_selected.connect(_on_toolbar_block_selected)
	toolbar.sub_mode_toggled.connect(_on_toolbar_sub_mode_toggled)
	toolbar.direction_changed.connect(_on_toolbar_direction_changed)
	toolbar.group_pressed.connect(group_selected_blocks)

	context_menu = EditorContextMenu.new()
	context_menu.item_selected.connect(_on_context_menu_action)
	ui_layer.add_child(context_menu)

	# Optional teaching panel; ordinary levels have no lesson data.
	tutorial_guide = TutorialGuideScript.new()
	ui_layer.add_child(tutorial_guide)
	tutorial_guide.set_anchors_and_offsets_preset(PRESET_TOP_RIGHT)
	tutorial_guide.offset_left = -336
	tutorial_guide.offset_right = -16
	tutorial_guide.offset_top = 170
	tutorial_guide.offset_bottom = 170
	tutorial_guide.restart_requested.connect(func():
		if not is_animating_tick and tutorial_transition.is_empty(): _apply_level_data(current_level_data)
	)

	tutorial_guide.dialogue_requested.connect(_show_tutorial_dialogue)

	# 4. Victory Dialog (Hidden initially)
	var victory_scrim := ColorRect.new()
	victory_scrim.color = Color(0.02, 0.06, 0.08, 0.72)
	victory_scrim.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	victory_scrim.visible = false
	ui_layer.add_child(victory_scrim)
	victory_dialog = VictoryDialog.new()
	victory_dialog.visible = false
	ui_layer.add_child(victory_dialog)
	victory_dialog.visibility_changed.connect(func():
		victory_scrim.visible = victory_dialog.visible
		camera.set_process(not victory_dialog.visible)
	)
	victory_dialog.set_anchors_and_offsets_preset(PRESET_CENTER)
	victory_dialog.resized.connect(_center_victory_dialog)
	victory_dialog.next_level_pressed.connect(_on_next_level_pressed)
	victory_dialog.replay_pressed.connect(reset_simulation)
	victory_dialog.level_select_pressed.connect(func():
		get_tree().change_scene_to_file("res://scenes/ui/LevelSelect.tscn")
	)

	tutorial_dialogue = DialogueScript.new()
	ui_layer.add_child(tutorial_dialogue)
	tutorial_dialogue.closed.connect(func():
		if tutorial_transition == "briefing":
			_travel_to_tutorial_followup()
			return
		camera.set_process(not victory_dialog.visible and tutorial_transition.is_empty())
		_update_sim_buttons()
	)
	tutorial_pan_blocker = Control.new()
	tutorial_pan_blocker.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	tutorial_pan_blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	tutorial_pan_blocker.hide()
	ui_layer.add_child(tutorial_pan_blocker)

# -------------------------------------------------------------
# Simulation Flow
# -------------------------------------------------------------
func toggle_simulation() -> void:
	if is_simulating:
		pause_simulation()
	else:
		start_simulation()

func start_simulation() -> void:
	if has_blocks_outside_build_area():
		_flash_outside_warning()
		return
	if not _tutorial_can_run(): return
	if is_simulating:
		return
	is_simulating = true
	has_simulated = true
	MusicManager.play_running()
	_update_build_area_status()
	_update_sim_buttons()
	_run_sim_loop()

func pause_simulation() -> void:
	is_simulating = false
	_update_sim_buttons()

func step_single_tick() -> void:
	if has_blocks_outside_build_area():
		_flash_outside_warning()
		return
	if not _tutorial_can_run(): return
	if is_animating_tick:
		return
	has_simulated = true
	MusicManager.play_running()
	_update_build_area_status()
	_update_sim_buttons()
	_execute_tick()

func reset_simulation() -> void:
	if not tutorial_transition.is_empty() or tutorial_transition_pending: return
	tick_generation += 1
	is_simulating = false
	is_animating_tick = false
	has_simulated = false
	victory_dialog.visible = false
	MusicManager.play_ambient()

	# Restore from initial snapshot
	world = initial_snapshot.clone()
	var b_area := current_level_data.player_build_area if current_level_data else Rect2i()
	sim_engine = SimulationEngine.new(world, b_area)
	sim_engine.construction_inspection = current_level_data != null and current_level_data.tutorial.get("goal", "") == "connect"
	sim_engine.level_won.connect(_on_level_won)
	grid_view.set_world(world)

	_update_build_area_status()
	_update_goal_display()
	_refresh_tutorial()

func _run_sim_loop() -> void:
	if not is_simulating:
		return
	if is_animating_tick:
		return
	_execute_tick()

func _execute_tick() -> void:
	is_animating_tick = true
	var generation := tick_generation
	var res := sim_engine.step_tick()
	_update_goal_display()

	var duration := base_tick_duration / sim_speed_multiplier
	grid_view.play_tick_animation(res, duration, func():
		if generation != tick_generation: return
		is_animating_tick = false
		if res.is_victory:
			pause_simulation()
			if tutorial_transition_pending: _begin_tutorial_transition()
		elif is_simulating:
			_run_sim_loop()
	)

func _on_level_won() -> void:
	pause_simulation()
	if tutorial_act == 0 and current_level_data.tutorial.has("followup"):
		tutorial_transition_pending = true
		_update_sim_buttons()
		return
	SoundManager.play_level_victory()
	Campaign.mark_completed(current_level_data.level_id, tutorial_first_ticks + sim_engine.step_count)
	var has_next := Campaign.next_index(current_level_data.level_id, all_levels) >= 0
	victory_dialog.show_victory(tutorial_first_ticks + sim_engine.step_count, has_next)
	if not current_level_data.tutorial.is_empty():
		var lesson := current_level_data.tutorial
		if not lesson.get("success_dialogues", []).is_empty():
			victory_dialog.details_label.text = "教学完成 · " + current_level_data.level_name
			var completion := lesson.duplicate(true)
			completion.dialogues = lesson.success_dialogues
			completion.dialogue_portraits = lesson.get("success_portraits", [])
			completion.dialogue_label = "培养皿通讯 · 完成"
			completion.dialogue_start_text = "查看教学结果 →"
			completion.dialogue_skip_text = "结束通讯"
			tutorial_dialogue.open(completion)
		else:
			victory_dialog.details_label.text = str(lesson.get("success", "学会了！继续下一课吧。"))
	_center_victory_dialog.call_deferred()

func _cancel_tutorial_transition() -> void:
	if tutorial_camera_tween != null and tutorial_camera_tween.is_valid(): tutorial_camera_tween.kill()
	if is_instance_valid(tutorial_departure): tutorial_departure.queue_free()
	tutorial_departure = null
	tutorial_transition = ""
	tutorial_transition_pending = false
	if tutorial_pan_blocker != null: tutorial_pan_blocker.hide()
	if camera != null:
		camera.set_process_unhandled_input(true)
		camera.is_dragging = false
		camera.active_touches.clear()

func _begin_tutorial_transition() -> void:
	tutorial_transition_pending = false
	tutorial_transition = "briefing"
	tutorial_first_ticks = sim_engine.step_count
	camera.set_process(false)
	var briefing := tutorial_root.tutorial.duplicate(true)
	briefing.dialogues = tutorial_root.tutorial.get("transition_dialogues", ["练习完成。跟我去看看新的警报。"])
	briefing.dialogue_portraits = tutorial_root.tutorial.get("transition_portraits", [])
	briefing.dialogue_label = "培养皿通讯"
	briefing.dialogue_start_text = "移向另一片区域 →"
	briefing.dialogue_skip_text = "移动视角"
	tutorial_dialogue.open(briefing)
	_update_sim_buttons()

func _travel_to_tutorial_followup() -> void:
	var followup := TutorialActs.followup_level(tutorial_root)
	if followup == null:
		_cancel_tutorial_transition()
		return
	tutorial_transition = "panning"
	var previous_position := camera.position
	var previous_zoom := camera.zoom
	tutorial_departure = GridView.new()
	tutorial_departure.player_build_area = current_level_data.player_build_area
	grid_view.get_parent().add_child(tutorial_departure)
	tutorial_departure.set_world(world.clone())
	tutorial_act = 1
	_apply_level_data(followup, false)
	var destination := camera.position
	var destination_zoom := camera.zoom
	camera.position = previous_position
	camera.zoom = previous_zoom
	camera.set_process(false)
	camera.set_process_unhandled_input(false)
	tutorial_pan_blocker.show()
	var generation := tick_generation
	tutorial_camera_tween = create_tween().set_parallel(true)
	tutorial_camera_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tutorial_camera_tween.tween_property(camera, "position", destination, 1.2)
	tutorial_camera_tween.tween_property(camera, "zoom", destination_zoom, 1.2)
	tutorial_camera_tween.finished.connect(func():
		if generation != tick_generation: return
		if is_instance_valid(tutorial_departure): tutorial_departure.queue_free()
		tutorial_departure = null
		tutorial_transition = ""
		tutorial_pan_blocker.hide()
		camera.set_process_unhandled_input(true)
		_show_tutorial_dialogue()
		_update_sim_buttons()
	)

func _center_victory_dialog() -> void:
	victory_dialog.reset_size()
	victory_dialog.position = (get_viewport_rect().size - victory_dialog.size) * 0.5

func _show_tutorial_dialogue() -> void:
	if not tutorial_transition.is_empty() or tutorial_transition_pending: return
	if current_level_data == null or not current_level_data.tutorial.has("dialogues"): return
	if is_animating_tick: return
	is_simulating = false
	tutorial_dialogue.open(current_level_data.tutorial)
	camera.set_process(false)
	_update_sim_buttons()

func _tutorial_moves_allowed(moves: Array[Dictionary]) -> bool:
	if not current_level_data.tutorial.get("experiment", false): return true
	for move in moves:
		if not current_level_data.player_build_area.has_point(move.new_pos): return false
		var occupant := world.get_block(move.new_pos)
		if occupant != null and occupant.is_world_block: return false
	return true

func _tutorial_can_run() -> bool:
	if not tutorial_transition.is_empty() or tutorial_transition_pending: return false
	if tutorial_dialogue != null and tutorial_dialogue.visible: return false
	if current_level_data != null and not has_simulated:
		if not TutorialRules.check_world(world, current_level_data.tutorial, current_level_data.player_build_area).is_empty(): return false
	return tutorial_guide == null or tutorial_guide.can_run(world, sim_engine.step_count)

func _refresh_tutorial() -> void:
	if tutorial_guide == null or world == null or sim_engine == null: return
	var target: Dictionary = tutorial_guide.refresh(world, sim_engine.step_count, is_animating_tick)
	if grid_view.tutorial_target != target:
		grid_view.tutorial_target = target
		grid_view.queue_redraw()
	_update_sim_buttons()

func _on_next_level_pressed() -> void:
	var next := Campaign.next_index(current_level_data.level_id, all_levels)
	if next >= 0:
		load_level_by_index(next)

func get_blocks_outside_build_area() -> Array[BlockData]:
	var result: Array[BlockData] = []
	if has_simulated:
		return result
	if current_level_data == null or world == null:
		return result
	var area := current_level_data.player_build_area
	if area.size == Vector2i.ZERO:
		return result
	for b in world.get_all_blocks():
		if not b.is_world_block and not area.has_point(b.grid_pos):
			result.append(b)
	return result

func has_blocks_outside_build_area() -> bool:
	return not get_blocks_outside_build_area().is_empty()

func _update_build_area_status() -> void:
	var outside_blocks := get_blocks_outside_build_area()
	var outside_count := outside_blocks.size()
	var has_outside := (outside_count > 0)

	if build_area_warning_panel != null:
		build_area_warning_panel.visible = has_outside
		if has_outside:
			build_area_warning_label.text = "⚠️ 建造区外存在 %d 处方块，无法启动模拟！" % outside_count

	if grid_view != null:
		var outside_positions: Array[Vector2i] = []
		for b in outside_blocks:
			outside_positions.append(b.grid_pos)
		grid_view.blocks_outside_build_area = outside_positions
		grid_view.queue_redraw()

	_update_sim_buttons()

func _flash_outside_warning() -> void:
	if build_area_warning_panel == null:
		return
	var tween := create_tween()
	tween.tween_property(build_area_warning_panel, "modulate", Color(1.8, 1.8, 1.8, 1.0), 0.1)
	tween.tween_property(build_area_warning_panel, "modulate", Color(1.0, 1.0, 1.0, 1.0), 0.25)

func _update_sim_buttons() -> void:
	var transitioning := not tutorial_transition.is_empty() or tutorial_transition_pending
	if toolbar != null: toolbar.set_editable(not has_simulated and not is_simulating and not transitioning)
	if reset_btn != null: reset_btn.disabled = transitioning
	if clear_button != null: clear_button.disabled = is_simulating or is_animating_tick or transitioning
	if load_button != null: load_button.disabled = has_simulated or is_simulating or current_level_data.tutorial.get("experiment", false)
	if status_label != null and sim_engine != null:
		if transitioning:
			status_label.text = "收到塔洛斯的通讯" if tutorial_transition != "panning" else "视角正在移向培养皿另一片区域…"
		elif is_simulating:
			status_label.text = "运行中 · 第 %d 步 · 空格暂停观察" % sim_engine.step_count
		elif has_simulated:
			status_label.text = "已暂停 · 第 %d 步 · 点击「重置」恢复编辑，构装会保留" % sim_engine.step_count
		else:
			status_label.text = "构装中 · 在绿色区域内放置方块 · 单步可逐拍验证"
	var outside_blocked := has_blocks_outside_build_area()
	var tutorial_ready := _tutorial_can_run()
	var can_start := not outside_blocked and tutorial_ready

	if play_btn != null:
		play_btn.text = "暂停 [空格]" if is_simulating else ("继续 [空格]" if has_simulated else "开始 [空格]")
		if not is_simulating:
			play_btn.disabled = not can_start
			if outside_blocked:
				play_btn.tooltip_text = "建造区外存在方块，无法启动模拟"
			elif not tutorial_ready:
				play_btn.tooltip_text = "请先完成右侧操作练习、结束讲解，并检查实验器材"
			else:
				play_btn.tooltip_text = ""
		else:
			play_btn.disabled = false
			play_btn.tooltip_text = ""

	if step_btn != null:
		step_btn.disabled = not can_start
		if outside_blocked:
			step_btn.tooltip_text = "建造区外存在方块，无法启动模拟"
		elif not tutorial_ready:
			step_btn.tooltip_text = "请先完成右侧操作练习、结束讲解，并检查实验器材"
		else:
			step_btn.tooltip_text = ""

	if reset_btn != null:
		reset_btn.text = "重置 [R]"

func _update_goal_display() -> void:
	if goal_label != null and sim_engine != null:
		if sim_engine.construction_inspection:
			goal_label.text = "搭建检查：用普通方块连通所有晶胚端点，再单步验收"
			return
		var parts: Array[String] = []
		var p := sim_engine.get_remaining_pollution()
		var tr_col := sim_engine.get_collected_treasure_lineage_count()
		var tr_total := sim_engine.get_total_treasure_lineages()
		var prot_cur := sim_engine.get_remaining_protected()
		var prot_init := sim_engine.initial_protected_count

		if sim_engine.initial_pollution_count > 0 or p > 0:
			parts.append("污染源: %d" % p)
		if tr_total > 0:
			parts.append("宝藏回收: %d/%d" % [tr_col, tr_total])
		if prot_init > 0:
			var prot_lost := prot_init - prot_cur
			if prot_lost > 0 or sim_engine.destroyed_protected_count > 0:
				parts.append("保护目标: 失败(已损毁)")
			else:
				parts.append("保护目标: 完好(%d/%d)" % [prot_cur, prot_init])

		if parts.is_empty():
			goal_label.text = "目标: 自由实验"
		else:
			goal_label.text = "目标: " + " | ".join(parts)

# -------------------------------------------------------------
# Input & Placement Handling
# -------------------------------------------------------------
func _process(_delta: float) -> void:
	_refresh_tutorial()
	# Update ghost preview under mouse
	if grid_view != null and toolbar != null:
		var mouse_world := grid_view.get_global_mouse_position()
		var grid_pos := grid_view.world_to_grid(mouse_world)
		if grid_view.is_multi_ghost_active():
			grid_view.update_multi_ghost_position(grid_pos)
			grid_view.update_preview(false, 0, 0, 0, 0, grid_pos)
		elif toolbar.is_placing and not is_simulating and not has_simulated and not _mouse_over_interface():
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
	if not tutorial_transition.is_empty() or tutorial_transition_pending: return
	if tutorial_dialogue != null and tutorial_dialogue.visible: return
	if victory_dialog.visible: return
	if event is InputEventKey and event.pressed:
		var key: int = event.keycode if event.keycode != 0 else event.physical_keycode
		if key == KEY_HOME:
			frame_board()
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

	# ESC: Deselect current block tool when building
	if toolbar != null and toolbar.is_placing:
		if KeybindManager.is_action_just_pressed(event, "cancel_tool") or (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE):
			toolbar.deselect_tool()
			get_viewport().set_input_as_handled()
			return

	# Ctrl + Mouse Wheel cycles current block tool (Plain wheel zooms camera)
	if toolbar != null and not is_simulating and event is InputEventMouseButton and event.pressed:
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

	# ESC: pause simulation if running
	if event is InputEventKey and event.pressed and (event.keycode == KEY_ESCAPE or event.physical_keycode == KEY_ESCAPE):
		if is_simulating:
			pause_simulation()
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

	# Number keys: 1..6 for player blocks
	if not has_simulated and not is_simulating:
		if event is InputEventKey and event.pressed and not event.echo:
			var code: int = event.keycode if event.keycode != 0 else event.physical_keycode
			if code >= KEY_1 and code <= KEY_6:
				_clear_selection()
				toolbar.select_type(code - KEY_1)
				get_viewport().set_input_as_handled()
				return

	# Undo / Redo Shortcuts
	if KeybindManager.is_action_just_pressed(event, "undo"):
		undo()
		get_viewport().set_input_as_handled()
		return

	if KeybindManager.is_action_just_pressed(event, "redo"):
		redo()
		get_viewport().set_input_as_handled()
		return

	# Structure Grouping
	if KeybindManager.is_action_just_pressed(event, "group_structure"):
		group_selected_blocks()
		get_viewport().set_input_as_handled()
		return

	# Delete Selected (default key: X)
	if KeybindManager.is_action_just_pressed(event, "delete"):
		delete_selected_blocks()
		get_viewport().set_input_as_handled()
		return

	# Cut, Copy & Paste Shortcuts
	if KeybindManager.is_action_just_pressed(event, "cut"):
		if not is_simulating and not has_simulated:
			var player_blocks := selected_blocks.filter(func(b): return not b.is_world_block)
			if not player_blocks.is_empty():
				cut_selected_blocks()
				get_viewport().set_input_as_handled()
				return

	if KeybindManager.is_action_just_pressed(event, "copy"):
		var player_blocks := selected_blocks.filter(func(b): return not b.is_world_block)
		if not player_blocks.is_empty():
			EditorClipboard.copy(player_blocks)
			_note_edit_action("copy")
			get_viewport().set_input_as_handled()
			return

	if KeybindManager.is_action_just_pressed(event, "paste"):
		if EditorClipboard.has_blocks() and not is_simulating and not has_simulated:
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

	# Mouse clicks for placement, erasure, and box-selection
	if event is InputEventMouseButton:
		var mouse_world := grid_view.get_global_mouse_position()
		var grid_pos := grid_view.world_to_grid(mouse_world)

		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				if toolbar.is_placing:
					if not is_simulating and not has_simulated:
						record_undo()
						is_mouse_placing = true
						last_player_grid = grid_pos
						_try_place_block(grid_pos)
				else:
					# Selection tool
					if Input.is_key_pressed(KEY_SHIFT):
						var clicked_block := world.get_block(grid_pos)
						if clicked_block != null:
							if not clicked_block.is_world_block:
								_toggle_select_block(clicked_block)
						else:
							is_box_selecting = true
							box_select_start_world = mouse_world
							grid_view.is_box_selecting = true
							grid_view.box_select_start = mouse_world
							grid_view.box_select_current = mouse_world
							grid_view.queue_redraw()
					else:
						# "当选中一个或一些方块时,左键单击会取消选择"
						var clicked_block := world.get_block(grid_pos)
						if not selected_blocks.is_empty():
							_clear_selection()
							if clicked_block != null and not clicked_block.is_world_block:
								_toggle_select_block(clicked_block)
						else:
							if clicked_block != null and not clicked_block.is_world_block:
								_toggle_select_block(clicked_block)
							else:
								is_box_selecting = true
								box_select_start_world = mouse_world
								grid_view.is_box_selecting = true
								grid_view.box_select_start = mouse_world
								grid_view.box_select_current = mouse_world
								grid_view.queue_redraw()
			else:
				is_mouse_placing = false
				last_player_grid = Vector2i(-999999, -999999)
				if is_box_selecting:
					is_box_selecting = false
					grid_view.is_box_selecting = false
					_finish_box_select()
					grid_view.queue_redraw()

		elif event.button_index == MOUSE_BUTTON_RIGHT:
			if event.pressed:
				if toolbar.is_placing:
					if not is_simulating and not has_simulated:
						record_undo()
						is_mouse_erasing = true
						last_player_grid = grid_pos
						_try_erase_block(grid_pos)
				else:
					# Selection Mode: Start right drag panning or context menu
					is_right_mouse_down = true
					is_right_panning = false
					right_mouse_down_pos = event.position
			else:
				if toolbar.is_placing:
					is_mouse_erasing = false
					last_player_grid = Vector2i(-999999, -999999)
				else:
					if is_right_mouse_down:
						is_right_mouse_down = false
						if not is_right_panning:
							# Single right click without drag
							var can_act := not selected_blocks.is_empty() and selected_blocks.any(func(b): return not b.is_world_block) and not is_simulating and not has_simulated
							var can_paste := EditorClipboard.has_blocks() and not is_simulating and not has_simulated
							if can_act or can_paste or can_undo() or can_redo():
								context_menu.popup_at(event.position, can_paste, can_act, can_undo(), can_redo())
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
			if grid_pos != last_player_grid:
				last_player_grid = grid_pos
				_try_place_block(grid_pos)
		elif is_mouse_erasing:
			if grid_pos != last_player_grid:
				last_player_grid = grid_pos
				_try_erase_block(grid_pos)
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
			var player_blocks := selected_blocks.filter(func(b): return not b.is_world_block)
			if not player_blocks.is_empty():
				EditorClipboard.copy(player_blocks)
				_note_edit_action("copy")
		"cut":
			cut_selected_blocks()
		"paste":
			if EditorClipboard.has_blocks() and not is_simulating and not has_simulated:
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
	edit_move_origin.clear()
	if blocks.is_empty() or is_simulating or has_simulated: return
	_clear_selection()
	if toolbar != null:
		toolbar.deselect_tool()
	grid_view.start_multi_ghost(blocks)

func _try_place_ghost_blocks(mouse_grid: Vector2i) -> void:
	if is_simulating or has_simulated: return
	if not grid_view.can_place_multi_ghost():
		return
	var new_blocks := grid_view.get_multi_ghost_blocks_to_place(mouse_grid)
	if new_blocks.is_empty():
		return
	if current_level_data.tutorial.get("edit_sequence", "") == "move_then_copy":
		# No imported clipboard or premature copies before the seed is moved.
		if tutorial_guide.edit_progress == 0 and edit_move_origin.is_empty(): return
		if tutorial_guide.edit_progress == 1 and edit_move_origin.is_empty(): return
	record_undo()

	var candidate := world.clone()
	for b in new_blocks:
		var copy := b.duplicate_block(false)
		copy.is_world_block = false
		candidate.add_block(copy)
	if not TutorialRules.check_world(candidate, current_level_data.tutorial, current_level_data.player_build_area).is_empty(): return
	var sid_map: Dictionary = {}
	for b in new_blocks:
		if b.structure_id > 0:
			if not sid_map.has(b.structure_id):
				sid_map[b.structure_id] = world.create_new_structure_id()
			b.structure_id = sid_map[b.structure_id]
		b.block_id = BlockData.generate_new_id()
		b.origin_id = b.block_id
		b.is_world_block = false
		world.add_block(b)

	if edit_move_origin.is_empty():
		_note_edit_action("paste")
	elif current_level_data.tutorial.get("edit_sequence", "") == "move_then_copy":
		var target: Array = current_level_data.tutorial.get("edit_move_target", [0, 1])
		if new_blocks.size() == 1 and new_blocks[0].grid_pos == Vector2i(int(target[0]), int(target[1])) and new_blocks[0].grid_pos not in edit_move_origin:
			_note_edit_action("move")
	elif edit_move_origin.size() >= 2 and new_blocks.any(func(b): return b.grid_pos not in edit_move_origin):
		_note_edit_action("move")
	edit_move_origin.clear()
	grid_view.cancel_multi_ghost()
	initial_snapshot = world.clone()
	SoundManager.play_cell_place(grid_view.grid_to_world(mouse_grid))
	_update_build_area_status()
	_refresh_tutorial()

func _rotate_selected_blocks_cw() -> void:
	var player_blocks := selected_blocks.filter(func(b): return not b.is_world_block)
	if player_blocks.is_empty() or is_simulating or has_simulated: return
	record_undo()
	var sum := Vector2.ZERO
	for b in player_blocks: sum += Vector2(b.grid_pos)
	var center := sum / float(player_blocks.size())
	var anchor := Vector2i(int(round(center.x)), int(round(center.y)))

	var moves: Array[Dictionary] = []
	for b in player_blocks:
		var rel: Vector2i = b.grid_pos - anchor
		var new_rel := Vector2i(-rel.y, rel.x)
		moves.append({ "block": b, "old_pos": b.grid_pos, "new_pos": anchor + new_rel, "new_dir": (b.direction + 1) % 4 })

	if not _tutorial_moves_allowed(moves): return
	for m in moves:
		world._cells.erase(m["old_pos"])

	for m in moves:
		var occupant = world.get_block(m["new_pos"])
		if occupant != null and occupant not in player_blocks:
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
	_update_build_area_status()

func _rotate_selected_blocks_ccw() -> void:
	var player_blocks := selected_blocks.filter(func(b): return not b.is_world_block)
	if player_blocks.is_empty() or is_simulating or has_simulated: return
	record_undo()
	var sum := Vector2.ZERO
	for b in player_blocks: sum += Vector2(b.grid_pos)
	var center := sum / float(player_blocks.size())
	var anchor := Vector2i(int(round(center.x)), int(round(center.y)))

	var moves: Array[Dictionary] = []
	for b in player_blocks:
		var rel: Vector2i = b.grid_pos - anchor
		var new_rel := Vector2i(rel.y, -rel.x)
		moves.append({ "block": b, "old_pos": b.grid_pos, "new_pos": anchor + new_rel, "new_dir": (b.direction + 3) % 4 })

	if not _tutorial_moves_allowed(moves): return
	for m in moves:
		world._cells.erase(m["old_pos"])

	for m in moves:
		var occupant = world.get_block(m["new_pos"])
		if occupant != null and occupant not in player_blocks:
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
	_update_build_area_status()

func _flip_selected_blocks_h() -> void:
	var player_blocks := selected_blocks.filter(func(b): return not b.is_world_block)
	if player_blocks.is_empty() or is_simulating or has_simulated: return
	record_undo()
	var sum := Vector2.ZERO
	for b in player_blocks: sum += Vector2(b.grid_pos)
	var center := sum / float(player_blocks.size())
	var anchor := Vector2i(int(round(center.x)), int(round(center.y)))

	var moves: Array[Dictionary] = []
	for b in player_blocks:
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

	if not _tutorial_moves_allowed(moves): return
	for m in moves:
		world._cells.erase(m["old_pos"])

	for m in moves:
		var occupant = world.get_block(m["new_pos"])
		if occupant != null and occupant not in player_blocks:
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
	_update_build_area_status()

func _flip_selected_blocks_v() -> void:
	var player_blocks := selected_blocks.filter(func(b): return not b.is_world_block)
	if player_blocks.is_empty() or is_simulating or has_simulated: return
	record_undo()
	var sum := Vector2.ZERO
	for b in player_blocks: sum += Vector2(b.grid_pos)
	var center := sum / float(player_blocks.size())
	var anchor := Vector2i(int(round(center.x)), int(round(center.y)))

	var moves: Array[Dictionary] = []
	for b in player_blocks:
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

	if not _tutorial_moves_allowed(moves): return
	for m in moves:
		world._cells.erase(m["old_pos"])

	for m in moves:
		var occupant = world.get_block(m["new_pos"])
		if occupant != null and occupant not in player_blocks:
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
	_update_build_area_status()

# -------------------------------------------------------------
# Block Placement & Erasure
# -------------------------------------------------------------
func _try_place_block(grid_pos: Vector2i) -> void:
	if not TutorialRules.can_place(world, current_level_data.tutorial, current_level_data.player_build_area, toolbar.current_type, grid_pos): return
	if is_simulating or has_simulated:
		return

	var existing := world.get_block(grid_pos)
	if existing != null:
		if existing.is_world_block:
			return # Cannot overwrite level terrain in play mode
		world.remove_block_at(grid_pos)

	var new_block := BlockData.new(toolbar.current_type, grid_pos, toolbar.current_dir)
	new_block.sub_mode = toolbar.current_sub_mode
	new_block.is_world_block = false
	world.add_block(new_block)
	SoundManager.play_cell_place(grid_view.grid_to_world(grid_pos))

	# Update initial snapshot so Reset keeps player's current design
	_update_initial_snapshot()
	_update_build_area_status()

func _try_erase_block(grid_pos: Vector2i) -> void:
	if is_simulating or has_simulated:
		return
	var b := world.get_block(grid_pos)
	if b != null:
		if b.is_world_block:
			return # Protected world blocks
		world.remove_block_at(grid_pos)
		SoundManager.play_cell_delete(grid_view.grid_to_world(grid_pos))
		_update_initial_snapshot()
		_update_build_area_status()

func _update_initial_snapshot() -> void:
	if not is_simulating and not has_simulated:
		initial_snapshot = world.clone()

# -------------------------------------------------------------
# Selection & Grouping
# -------------------------------------------------------------
func _clear_selection() -> void:
	for b in selected_blocks:
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.is_selected = false
			v.queue_redraw()
	selected_blocks.clear()

func _toggle_select_block(b: BlockData) -> void:
	if b == null or b.is_world_block:
		return
	var idx := selected_blocks.find(b)
	if idx >= 0:
		selected_blocks.remove_at(idx)
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
			if b != null and not b.is_world_block and b not in selected_blocks:
				selected_blocks.append(b)
				var v := grid_view.get_view(b.block_id)
				if v != null:
					v.is_selected = true
					v.queue_redraw()

func group_selected_blocks() -> void:
	if is_simulating or has_simulated:
		return
	selected_blocks = selected_blocks.filter(func(b): return not b.is_world_block)
	if selected_blocks.is_empty():
		return
	record_undo()
	world.group_blocks(selected_blocks)
	for b in selected_blocks:
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.update_appearance()
	_update_initial_snapshot()

func cut_selected_blocks() -> void:
	if is_simulating or has_simulated:
		return
	var player_blocks := selected_blocks.filter(func(b): return not b.is_world_block)
	if player_blocks.is_empty():
		return
	EditorClipboard.copy(player_blocks)
	var blocks_to_paste := EditorClipboard.get_blocks()
	delete_selected_blocks()
	_start_paste_preview(blocks_to_paste)
	for block in player_blocks: edit_move_origin.append(block.grid_pos)

func delete_selected_blocks() -> void:
	if is_simulating or has_simulated:
		return
	var delete_pos := Vector2.ZERO
	var player_blocks := selected_blocks.filter(func(b): return not b.is_world_block)
	if player_blocks.is_empty():
		return
	record_undo()
	delete_pos = grid_view.grid_to_world(player_blocks[0].grid_pos)
	for b in selected_blocks:
		if not b.is_world_block:
			world.remove_block_at(b.grid_pos)
	selected_blocks.clear()
	if delete_pos != Vector2.ZERO:
		SoundManager.play_cell_delete(delete_pos)
	_update_initial_snapshot()
	_update_build_area_status()

func _get_selection_bounds() -> Rect2i:
	selected_blocks = selected_blocks.filter(func(b): return not b.is_world_block)
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
	if is_simulating or has_simulated:
		return
	if selected_blocks.is_empty() or delta == Vector2i.ZERO:
		return

	selected_blocks = selected_blocks.filter(func(b): return not b.is_world_block)
	if selected_blocks.is_empty():
		return

	var new_positions: Dictionary = {}
	for b in selected_blocks:
		if right_drag_orig_positions.has(b):
			new_positions[b] = right_drag_orig_positions[b] + delta
		else:
			new_positions[b] = b.grid_pos + delta

	# Check world blocks protection (cannot move onto any level world block)
	var can_move := true
	for b in selected_blocks:
		var target_p: Vector2i = new_positions[b]
		var occ := world.get_block(target_p)
		if (occ != null and occ.is_world_block) or (current_level_data.tutorial.get("experiment", false) and not current_level_data.player_build_area.has_point(target_p)):
			can_move = false
			break

	if not can_move:
		# Reset visual positions
		for b in selected_blocks:
			var v := grid_view.get_view(b.block_id)
			if v != null:
				v.position = grid_view.grid_to_world(b.grid_pos)
		return

	record_undo()

	# 1. Remove non-selected player blocks at target positions
	for b in selected_blocks:
		var target_p: Vector2i = new_positions[b]
		var occ := world.get_block(target_p)
		if occ != null and occ not in selected_blocks and not occ.is_world_block:
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

	# 3. Synchronize views
	for b in selected_blocks:
		var v := grid_view.get_view(b.block_id)
		if v != null:
			v.position = grid_view.grid_to_world(b.grid_pos)
			v.update_appearance()

	_update_initial_snapshot()
	_update_build_area_status()

func clear_player_blocks() -> void:
	if is_simulating:
		return
	if has_simulated:
		reset_simulation()
	record_undo()
	var all_b := world.get_all_blocks()
	for b in all_b:
		if not b.is_world_block:
			world.remove_block_at(b.grid_pos)
	selected_blocks.clear()
	_update_initial_snapshot()
	_update_build_area_status()

# -------------------------------------------------------------
# Blueprint Save / Load Modals
# -------------------------------------------------------------
func _on_save_machine_pressed() -> void:
	if is_simulating:
		return
	var has_sel := not selected_blocks.is_empty()
	var target_parent: Node = self
	if ui_layer != null:
		target_parent = ui_layer
	BlueprintDialogs.show_save_dialog(target_parent, has_sel, func(m_name: String, only_selected: bool):
		var target_blocks: Array[BlockData] = []
		if only_selected and not selected_blocks.is_empty():
			for b in selected_blocks:
				if not b.is_world_block:
					target_blocks.append(b)
		else:
			var source_blocks = initial_snapshot.get_all_blocks() if has_simulated else world.get_all_blocks()
			for b in source_blocks:
				if not b.is_world_block:
					target_blocks.append(b)

		SaveManager.save_machine(m_name, target_blocks)
	)

func _on_load_machine_pressed() -> void:
	if current_level_data.tutorial.get("experiment", false): return
	if is_simulating:
		return
	var target_parent: Node = self
	if ui_layer != null:
		target_parent = ui_layer
	BlueprintDialogs.show_load_dialog(target_parent, func(m_name: String):
		if has_simulated:
			reset_simulation()
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

func _on_toolbar_sub_mode_toggled(sub_mode: int) -> void:
	var any_changed := false
	for b in selected_blocks:
		if not b.is_world_block and b.block_type == BlockData.Type.ROTATOR and b.sub_mode != sub_mode:
			any_changed = true
			break
	if not any_changed:
		return
	record_undo()
	for b in selected_blocks:
		if not b.is_world_block and b.block_type == BlockData.Type.ROTATOR:
			b.sub_mode = sub_mode
			var v := grid_view.get_view(b.block_id)
			if v != null:
				v.update_appearance()
	_update_initial_snapshot()

func _on_toolbar_direction_changed(_dir: int) -> void:
	pass

func show_help() -> void:
	get_node("/root/OperationManual").open()

func _mouse_over_interface() -> bool:
	if get_node("/root/OperationManual").dialog.visible: return true
	if clear_confirm != null and clear_confirm.visible: return true
	var point := get_viewport().get_mouse_position()
	for child in ui_layer.get_children():
		if child is Control and child.visible and child.get_global_rect().has_point(point):
			return true
	return false

func frame_board() -> void:
	if world == null: return
	var bounds := Rect2(world.get_bounds())
	if current_level_data.player_build_area.size != Vector2i.ZERO:
		bounds = bounds.merge(Rect2(current_level_data.player_build_area))
	var available := get_viewport_rect().size - Vector2(100, 300)
	var side := 340.0 if tutorial_guide != null and tutorial_guide.visible else 0.0
	available.x -= side
	var scale_value := clampf(minf(available.x / maxf(64, bounds.size.x * 64 + 128), available.y / maxf(64, bounds.size.y * 64 + 128)), 0.25, 1.0)
	camera.zoom = Vector2.ONE * scale_value
	camera.position = (bounds.position + bounds.size * 0.5) * 64 + Vector2(side / (2 * scale_value), 0)

func _note_edit_action(action: String) -> void:
	if tutorial_guide != null:
		if current_level_data.tutorial.get("edit_sequence", "") == "move_then_copy" and action == "copy" and tutorial_guide.edit_progress == 1:
			var target: Array = current_level_data.tutorial.get("edit_move_target", [0, 1])
			if selected_blocks.size() != 1 or selected_blocks[0].grid_pos != Vector2i(int(target[0]), int(target[1])): return
		tutorial_guide.record_edit_action(action)
		_refresh_tutorial()
