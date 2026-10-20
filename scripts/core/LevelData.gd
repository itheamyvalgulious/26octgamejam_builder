class_name LevelData
extends RefCounted

var level_id: String = ""
var level_name: String = "新关卡"
var description: String = "完成关卡任务：摧毁所有污染源，将所有宝藏回收至建造区。"
var author: String = "构造一个我工匠"
var cg_theme: String = "cyan_core"
var order_index: int = 0
var tutorial: Dictionary = {} # Optional guided lesson; preserved by the level editor.

# Allowed player build area (Rect2i). If size is ZERO, anywhere is allowed.
var player_build_area: Rect2i = Rect2i(0, 0, 0, 0)

# Array of serialized BlockData dictionaries
var blocks_data: Array = []

func _init(p_id: String = "", p_name: String = "新关卡") -> void:
	level_id = p_id if not p_id.is_empty() else "level_%d" % [Time.get_unix_time_from_system()]
	level_name = p_name

func to_dict() -> Dictionary:
	return {
		"level_id": level_id,
		"level_name": level_name,
		"description": description,
		"author": author,
		"cg_theme": cg_theme,
		"order_index": order_index,
		"tutorial": tutorial.duplicate(true),
		"player_build_area": {
			"x": player_build_area.position.x,
			"y": player_build_area.position.y,
			"w": player_build_area.size.x,
			"h": player_build_area.size.y
		},
		"blocks": blocks_data
	}

static func from_dict(dict: Dictionary) -> LevelData:
	var lvl := LevelData.new(
		str(dict.get("level_id", "")),
		str(dict.get("level_name", "未命名关卡"))
	)
	lvl.description = str(dict.get("description", ""))
	lvl.author = str(dict.get("author", ""))
	lvl.cg_theme = str(dict.get("cg_theme", "cyan_core"))
	lvl.order_index = int(dict.get("order_index", 0))
	var lesson = dict.get("tutorial", {})
	if lesson is Dictionary:
		lvl.tutorial = lesson.duplicate(true)

	var area_dict = dict.get("player_build_area", {})
	if area_dict is Dictionary and not area_dict.is_empty():
		lvl.player_build_area = Rect2i(
			int(area_dict.get("x", 0)),
			int(area_dict.get("y", 0)),
			int(area_dict.get("w", 0)),
			int(area_dict.get("h", 0))
		)

	lvl.blocks_data = dict.get("blocks", [])
	return lvl
