extends PanelContainer
const UI = preload("res://scripts/ui/UIStyle.gd")

signal restart_requested()
signal dialogue_requested()

var lesson: Dictionary = {}
var active_step := -1
var heading: Label
var dialogue: Label
var progress: Label
var task: Label
var reminder: Label
var restart_button: Button
var hint_button: Button
var hint_index := 0
var replay_button: Button
var inventory_label: Label
var edit_progress := 0

func _init() -> void:
	theme = UI.get_theme()
	var style := StyleBoxFlat.new()
	style.bg_color = UI.PANEL
	style.border_color = UI.BORDER
	style.set_border_width_all(1)
	style.set_corner_radius_all(0)
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	add_theme_stylebox_override("panel", style)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	heading = _label(box, 18, UI.ACCENT)
	dialogue = _label(box, 15, UI.TEXT)
	box.add_child(HSeparator.new())
	progress = _label(box, 13, UI.ACCENT)
	task = _label(box, 15, UI.TEXT)
	reminder = _label(box, 13, UI.MUTED)
	reminder.text = "左键放置 · 右键擦除\nQ / E 调整箭头 · 单步观察结果\n放错了可以擦除；重置保留你的构装。"
	restart_button = Button.new()
	restart_button.text = "重新教学"
	restart_button.focus_mode = Control.FOCUS_NONE
	restart_button.custom_minimum_size.y = 36
	restart_button.pressed.connect(func(): restart_requested.emit())
	box.add_child(restart_button)
	hint_button = Button.new()
	hint_button.text = "下一条提示"
	hint_button.custom_minimum_size.y = 36
	hint_button.pressed.connect(func():
		var hints: Array = lesson.get("hints", [])
		if hints.is_empty(): return
		hint_index = (hint_index + 1) % hints.size()
		_show_hint()
	)
	box.add_child(hint_button)
	replay_button = Button.new()
	replay_button.text = "重听博士讲解"
	replay_button.pressed.connect(func(): dialogue_requested.emit())
	box.add_child(replay_button)
	inventory_label = _label(box, 14, UI.ACCENT)

func _label(parent: Node, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func configure(data: Dictionary) -> void:
	lesson = data.duplicate(true)
	edit_progress = 0
	hint_button.disabled = false
	active_step = -999
	task.text = ""
	visible = not lesson.is_empty()
	heading.text = str(lesson.get("title", "母巢教学"))
	dialogue.text = str(lesson.get("intro", ""))
	hint_index = -1 if lesson.get("experiment", false) else 0
	replay_button.visible = lesson.has("dialogues")
	inventory_label.visible = lesson.get("experiment", false)
	reminder.visible = not lesson.get("experiment", false)
	reminder.text = "先运行观察，再重置调整。\n器材配额不会因复制品而扣减。" if lesson.get("experiment", false) else "左键放置 · 右键擦除\nQ / E 调整箭头 · 单步观察结果\n放错了可以擦除；重置保留你的构装。"
	hint_button.visible = lesson.has("hints")
	restart_button.text = "还原预设" if lesson.has("hints") else "重新教学"
	_fit_height.call_deferred()

func _fit_height() -> void:
	# Wrapped labels settle after the panel receives its fixed width.
	size.y = get_combined_minimum_size().y

func _matches(world: GridWorld, step: Dictionary) -> bool:
	var block := world.get_block(Vector2i(int(step.get("x", 0)), int(step.get("y", 0))))
	if block == null or block.block_type != int(step.get("type", -1)):
		return false
	if step.has("dir") and block.direction != int(step.dir):
		return false
	if step.has("sub_mode") and block.sub_mode != int(step.sub_mode):
		return false
	return true

func next_step(world: GridWorld, ticks: int) -> int:
	var steps: Array = lesson.get("steps", [])
	if ticks == 0:
		for i in range(steps.size()):
			if not _matches(world, steps[i]): return i
	return steps.size()

func can_run(world: GridWorld, ticks: int) -> bool:
	if lesson.get("edit_practice", false) and edit_progress < 3: return false
	if lesson.get("experiment", false): return true
	return lesson.is_empty() or next_step(world, ticks) == lesson.get("steps", []).size()

func refresh(world: GridWorld, ticks: int, animating: bool) -> Dictionary:
	if lesson.is_empty(): return {}
	restart_button.disabled = animating
	if lesson.get("experiment", false):
		if ticks == 0:
			inventory_label.text = preload("res://scripts/core/TutorialRules.gd").inventory(world, lesson).replace("本关器材 · 已用 / 配额", "可布置细胞 · 已用 / 上限")
		else:
			inventory_label.text = "培养皿观察 · 第 %d 步\n重置后可继续布置细胞。" % ticks
	if lesson.get("edit_practice", false) and edit_progress < 3:
		_show_edit_practice()
		if lesson.get("edit_sequence", "") == "move_then_copy":
			var target: Array = lesson.get("edit_move_target", [0, 1])
			return {"x": int(target[0]), "y": int(target[1]), "type": 0}
		return {}
	if lesson.has("hints"):
		_show_hint()
		return {}
	var index := next_step(world, ticks)
	var steps: Array = lesson.get("steps", [])
	if index != active_step:
		active_step = index
		progress.text = "塔洛斯的通讯 · %d / %d" % [index + 1, steps.size() + 1]
		if index < steps.size():
			task.text = str(steps[index].get("text", ""))
		else:
			task.text = str(lesson.get("run_text", "点击单步，观察方块的行动。"))
		_fit_height.call_deferred()
	if index < steps.size(): return steps[index]
	return {}

func _show_hint() -> void:
	if lesson.get("edit_practice", false) and edit_progress < 3:
		_show_edit_practice()
		return
	var hints: Array = lesson.get("hints", [])
	if hints.is_empty(): return
	if active_step == hint_index and not task.text.is_empty(): return
	active_step = hint_index
	if hint_index < 0:
		progress.text = "当前目标 · 可以先试，再看提示"
		task.text = str(lesson.get("run_text", "观察目标，尝试构装。"))
		_fit_height.call_deferred()
		return
	progress.text = "可选提示 · %d / %d" % [hint_index + 1, hints.size()]
	task.text = str(hints[hint_index])
	_fit_height.call_deferred()

func record_edit_action(action: String) -> void:
	if not lesson.get("edit_practice", false) or edit_progress >= 3: return
	var sequence := ["move", "copy", "paste"] if lesson.get("edit_sequence", "") == "move_then_copy" else ["copy", "paste", "move"]
	if action == sequence[edit_progress]:
		edit_progress += 1
		active_step = -999
		if edit_progress == 3:
			hint_index = -1
			hint_button.disabled = false
			lesson.run_text = str(lesson.get("edit_complete_text", "操作练习完成！现在把三个晶胚端点连接起来，再单步验收。需要复习时按 F1。"))

func _show_edit_practice() -> void:
	hint_button.disabled = true
	progress.text = "调配自己的细胞 · %d / 3" % (edit_progress + 1)
	var copy_key := KeybindManager.get_action_display_name("copy")
	var paste_key := KeybindManager.get_action_display_name("paste")
	var cut_key := KeybindManager.get_action_display_name("cut")
	var cancel_key := KeybindManager.get_action_display_name("cancel_tool")
	var messages := [
		"先放一枚普通细胞（普通方块）。按 %s 退出放置，左键选中它，再按 %s 复制。" % [cancel_key, copy_key],
		"样本已记下。按 %s，把预览移到绿色区域的空格，左键确认。原件会保留，副本也属于你的身体。" % paste_key,
		"试着移动一小片身体：从空白处拖框选中至少两枚自建细胞，按 %s 剪切，再移动鼠标，左键放到另一处空位。无需再次粘贴。" % cut_key
	]
	if lesson.get("edit_sequence", "") == "move_then_copy":
		var target: Array = lesson.get("edit_move_target", [0, 1])
		var coordinate := "(%d,%d)" % [int(target[0]), int(target[1])]
		messages = [
			"左键选中散落的普通细胞，按 %s 剪切，移到高亮格 %s，左键确认。剪切后无需再按粘贴；本幕不能直接放置新细胞。" % [cut_key, coordinate],
			"细胞已到位。左键选中 %s 的这枚普通细胞，按 %s 复制，原件会保留。" % [coordinate, copy_key],
			"按 %s，把副本放在晶胚之间的空格。随后可再次按 %s 继续粘贴，直到三枚晶胚上下左右连通。" % [paste_key, paste_key]
		]
	task.text = messages[edit_progress]
	_fit_height.call_deferred()
