extends RefCounted

# Laboratory blue / cell green. Keep text dark on the light instrument panels.
const BG := Color("60b3e5")
const PANEL := Color("c9eafa")
const BORDER := Color("20577b")
const TEXT := Color("12344b")
const MUTED := Color("375e73")
const ACCENT := Color("205a25")
const INPUT := Color("eff9fe")
static var shared_theme: Theme

static func box(fill: Color, border := BORDER, _radius := 0, padding := 10) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.content_margin_left = padding
	style.content_margin_right = padding
	style.content_margin_top = 8
	style.content_margin_bottom = 8
	return style

static func flat(fill: Color, _radius := 0, padding := 10) -> StyleBoxFlat:
	var style := box(fill, BORDER, 0, padding)
	style.border_width_bottom = 3
	return style

static func cell_button(tint := Color.WHITE) -> StyleBoxTexture:
	var style := StyleBoxTexture.new()
	style.texture = load("res://scenes/animation/button_clean.png")
	style.modulate_color = tint
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, 28)
		style.set_content_margin(side, 22 if side in [SIDE_TOP, SIDE_BOTTOM] else 18)
	style.axis_stretch_horizontal = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	style.axis_stretch_vertical = StyleBoxTexture.AXIS_STRETCH_MODE_TILE_FIT
	return style

static func get_theme() -> Theme:
	if shared_theme != null: return shared_theme
	shared_theme = Theme.new()
	shared_theme.default_font = load("res://assets/fonts/font.ttf")
	shared_theme.default_font_size = 16
	for type in ["Label", "Button", "LineEdit", "TextEdit", "RichTextLabel", "CheckButton", "CheckBox", "ItemList", "OptionButton", "SpinBox"]:
		shared_theme.set_color("font_color", type, TEXT)
	shared_theme.set_color("default_color", "RichTextLabel", TEXT)
	for type in ["Button", "OptionButton"]:
		shared_theme.set_stylebox("normal", type, flat(Color("a8daf3")))
		shared_theme.set_stylebox("hover", type, flat(Color("e5f6ff")))
		shared_theme.set_stylebox("pressed", type, flat(Color("a4e766")))
		shared_theme.set_stylebox("hover_pressed", type, flat(Color("bcf48a")))
		shared_theme.set_stylebox("disabled", type, flat(Color("b8cdd4")))
		for state in ["font_hover_color", "font_pressed_color", "font_hover_pressed_color"]:
			shared_theme.set_color(state, type, TEXT)
		shared_theme.set_color("font_disabled_color", type, Color("506775"))
	var focus := box(Color.TRANSPARENT, Color("174566"))
	focus.set_border_width_all(3)
	shared_theme.set_stylebox("focus", "Button", focus)
	for type in ["PanelContainer", "PopupPanel", "PopupMenu", "AcceptDialog"]:
		shared_theme.set_stylebox("panel", type, box(PANEL))
	for type in ["LineEdit", "TextEdit", "ItemList"]:
		shared_theme.set_stylebox("normal", type, box(INPUT))
		shared_theme.set_stylebox("focus", type, box(INPUT, ACCENT))
		shared_theme.set_color("font_selected_color", type, TEXT)
		shared_theme.set_color("selection_color", type, Color("b2e783"))
	for type in ["LineEdit", "TextEdit"]:
		shared_theme.set_stylebox("read_only", type, box(Color("d4e3eb")))
		shared_theme.set_color("font_uneditable_color", type, MUTED)
		shared_theme.set_color("font_readonly_color", type, MUTED)
	shared_theme.set_stylebox("panel", "ItemList", box(INPUT))
	shared_theme.set_stylebox("selected", "ItemList", box(Color("b2e783"), ACCENT))
	shared_theme.set_stylebox("selected_focus", "ItemList", box(Color("b2e783"), ACCENT))
	shared_theme.set_stylebox("panel", "TooltipPanel", box(INPUT))
	shared_theme.set_color("font_color", "TooltipLabel", TEXT)
	shared_theme.set_font_size("font_size", "TooltipLabel", 15)
	shared_theme.set_color("font_color", "PopupMenu", TEXT)
	shared_theme.set_color("font_hover_color", "PopupMenu", TEXT)
	shared_theme.set_stylebox("hover", "PopupMenu", flat(Color("b2e783")))
	for type in ["TabBar", "TabContainer"]:
		shared_theme.set_color("font_selected_color", type, ACCENT)
		shared_theme.set_color("font_unselected_color", type, MUTED)
		shared_theme.set_color("font_hovered_color", type, TEXT)
		shared_theme.set_stylebox("tab_selected", type, flat(Color("b2e783"),0,16))
		shared_theme.set_stylebox("tab_unselected", type, flat(Color("99cfe9"),0,16))
		shared_theme.set_stylebox("tab_hovered", type, flat(INPUT,0,16))
	shared_theme.set_stylebox("panel", "TabContainer", box(PANEL,BORDER,0,16))
	return shared_theme

static func get_game_theme() -> Theme:
	return get_theme()

static func primary(button: Button) -> void:
	button.custom_minimum_size.y = maxf(button.custom_minimum_size.y, 60.0)
	button.add_theme_stylebox_override("normal", cell_button())
	button.add_theme_stylebox_override("hover", cell_button(Color(1.08,1.08,1.02)))
	button.add_theme_stylebox_override("pressed", cell_button(Color(0.82,0.92,0.75)))
	button.add_theme_stylebox_override("disabled", cell_button(Color(0.68,0.76,0.66)))
	for state in ["font_color", "font_hover_color", "font_pressed_color"]:
		button.add_theme_color_override(state, Color("18340d"))

static func game_primary(button: Button) -> void:
	primary(button)

static func label(parent: Node, text: String, size := 16, color := TEXT) -> Label:
	var node := Label.new()
	node.text = text
	node.add_theme_font_size_override("font_size", size)
	node.add_theme_color_override("font_color", color)
	parent.add_child(node)
	return node

static func add_lab_background(parent: Control) -> void:
	var bg := TextureRect.new()
	bg.name = "LabBackground"
	bg.texture = load("res://scenes/animation/background/mid.png")
	bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg.stretch_mode = TextureRect.STRETCH_TILE
	bg.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	bg.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
	# Same corner and edge artwork as the title screen.
	var pieces = [
		["left_up",0,0,0,0,0,0,128,128],
		["right_up",1,0,1,0,-128,0,0,128],
		["left_low",0,1,0,1,0,-128,128,0],
		["right_low",1,1,1,1,-128,-128,0,0],
		["horizontal edge_up",0,0,1,0,128,0,-128,128],
		["horizontal edge_low",0,1,1,1,128,-128,-128,0],
		["Vertical edge_left",0,0,0,1,0,128,128,-128],
		["Vertical edge_right",1,0,1,1,-128,128,0,-128]]
	for data in pieces:
		var piece := TextureRect.new()
		piece.texture = load("res://scenes/animation/background/%s.png" % data[0])
		piece.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		piece.stretch_mode = TextureRect.STRETCH_TILE
		piece.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		piece.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		piece.mouse_filter = Control.MOUSE_FILTER_IGNORE
		piece.anchor_left = data[1]
		piece.anchor_top = data[2]
		piece.anchor_right = data[3]
		piece.anchor_bottom = data[4]
		piece.offset_left = data[5]
		piece.offset_top = data[6]
		piece.offset_right = data[7]
		piece.offset_bottom = data[8]
		bg.add_child(piece)
