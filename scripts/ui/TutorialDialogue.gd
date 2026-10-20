extends Control

signal closed()
const UI = preload("res://scripts/ui/UIStyle.gd")
var pages: Array = []
var page := 0
var reveal := 0.0
var speaker: Label
var counter: Label
var body: RichTextLabel
var portrait: TextureRect
var next_button: Button
var skip_button: Button
var dialogue_label := "实验简报"
var start_text := "开始实验 →"
var page_portraits: Array = []
var default_portrait := ""

func _init() -> void:
	theme = UI.get_theme()
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.color = Color(0.02, 0.05, 0.08, 0.65)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = MOUSE_FILTER_IGNORE
	portrait.set_anchors_and_offsets_preset(PRESET_BOTTOM_LEFT)
	portrait.offset_left = 0
	portrait.offset_right = 330
	portrait.offset_top = -684
	portrait.offset_bottom = -24
	add_child(portrait)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(PRESET_BOTTOM_WIDE)
	panel.offset_left = 330
	panel.offset_right = -32
	panel.offset_top = -350
	panel.offset_bottom = -84
	panel.add_theme_stylebox_override("panel", UI.box(UI.PANEL, UI.BORDER, 0, 26))
	add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	panel.add_child(box)
	var header := HBoxContainer.new()
	box.add_child(header)
	var nameplate := PanelContainer.new()
	nameplate.add_theme_stylebox_override("panel", UI.box(UI.BORDER, UI.BORDER, 0, 14))
	header.add_child(nameplate)
	speaker = UI.label(nameplate, "塔洛斯", 22, Color("f1ffcc"))
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	header.add_child(spacer)
	counter = UI.label(header, "", 14, UI.MUTED)
	body = RichTextLabel.new()
	body.add_theme_font_size_override("normal_font_size", 21)
	body.add_theme_color_override("default_color", UI.TEXT)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	body.custom_minimum_size.y = 110
	body.gui_input.connect(func(event):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			advance()
			body.accept_event()
	)
	box.add_child(body)
	var actions := HBoxContainer.new()
	box.add_child(actions)
	var hint := UI.label(actions, "点击文字展开 · Enter 继续", 14, UI.MUTED)
	hint.size_flags_horizontal = SIZE_EXPAND_FILL
	var skip := Button.new()
	skip_button = skip
	skip.text = "直接实验"
	skip.size_flags_vertical = SIZE_SHRINK_CENTER
	skip.pressed.connect(close)
	actions.add_child(skip)
	next_button = Button.new()
	UI.primary(next_button)
	next_button.custom_minimum_size.x = 130
	next_button.pressed.connect(advance)
	actions.add_child(next_button)
	hide()

func open(lesson: Dictionary) -> void:
	pages = lesson.get("dialogues", [])
	if pages.is_empty(): return
	dialogue_label = str(lesson.get("dialogue_label", "实验简报"))
	start_text = str(lesson.get("dialogue_start_text", "开始实验 →"))
	skip_button.text = str(lesson.get("dialogue_skip_text", "直接实验"))
	speaker.text = str(lesson.get("speaker", "塔洛斯"))
	default_portrait = str(lesson.get("portrait", ""))
	page_portraits = lesson.get("dialogue_portraits", [])
	page = 0
	show()
	_display_page()

func _display_page() -> void:
	var path := str(page_portraits[page]) if page < page_portraits.size() else default_portrait
	if path.is_empty() or not ResourceLoader.exists(path): path = default_portrait
	portrait.texture = load(path) if not path.is_empty() and ResourceLoader.exists(path) else null
	body.text = str(pages[page])
	body.visible_characters = 0
	reveal = 0
	counter.text = "%s  %d / %d" % [dialogue_label, page + 1, pages.size()]
	next_button.text = start_text if page == pages.size() - 1 else "继续 →"

func _process(delta: float) -> void:
	if not visible: return
	reveal += delta * 35.0
	body.visible_characters = mini(int(reveal), body.get_total_character_count())

func advance() -> void:
	if body.visible_characters < body.get_total_character_count():
		reveal = body.get_total_character_count()
		body.visible_characters = int(reveal)
	elif page + 1 < pages.size():
		page += 1
		_display_page()
	else:
		close()

func close() -> void:
	hide()
	closed.emit()

func _input(event: InputEvent) -> void:
	if not visible: return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode in [KEY_ENTER, KEY_SPACE]:
			advance()
			get_viewport().set_input_as_handled()
		elif event.keycode == KEY_ESCAPE:
			close()
			get_viewport().set_input_as_handled()
