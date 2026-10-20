class_name SoundManager
extends Node

## 构造一个我 - 全局音效管理器
## 提供 UI 自动挂接、摄像机空间化音量衰减计算（距屏中心越近、缩放越大声音越大）
## 以及高性能多路复用音频播放池。

static var instance: SoundManager

# -------------------------------------------------------------
# 音频资产配置 (用户确认选定方案)
# -------------------------------------------------------------
const PATH_UI_CLICK := "res://assets/audio/sfx/ui_click_wood.wav"
const PATH_UI_SLIDER := "res://assets/audio/sfx/ui_slider_marimba.wav"
const PATH_CELL_PLACE := "res://assets/audio/sfx/cell_place_jelly.wav"
const PATH_CELL_DELETE := "res://assets/audio/sfx/destroyer_clamp_smash.wav"
const PATH_PUSHER := "res://assets/audio/sfx/pusher_spring.wav"
const PATH_REPLICATOR := "res://assets/audio/sfx/replicator_gentle_bubble.wav"
const PATH_MONSTER := "res://assets/audio/sfx/monster_waddle.wav"
const PATH_DESTROYER := "res://assets/audio/sfx/destroyer_clamp_smash.wav"
const PATH_ROTATOR := "res://assets/audio/sfx/rotator_spin.wav"
const PATH_INHIBITOR_ENGAGE := "res://assets/audio/sfx/inhibitor_engage_sleep.wav"
const PATH_INHIBITOR_RELEASE := "res://assets/audio/sfx/inhibitor_release_wake.wav"
const PATH_TREASURE := "res://assets/audio/sfx/treasure_chime.wav"
const PATH_VICTORY := "res://assets/audio/sfx/victory_joyful_rush.wav"

var _streams: Dictionary = {}

# -------------------------------------------------------------
# 音频播放池 (Voice Pool)
# -------------------------------------------------------------
const POOL_SIZE := 24
var _voice_pool: Array[AudioStreamPlayer] = []
var _voice_index := 0

# 专用 UI 声道（极速响应、独立通道不与方块音效争夺）
var _ui_player: AudioStreamPlayer
var _slider_player: AudioStreamPlayer

# UI 滑动条节流 (毫秒)
const SLIDER_THROTTLE_MS := 80

# UI 全局音效防抖节流 (毫秒)，防止连发与短时间密集触发
const UI_CLICK_MIN_INTERVAL_MS := 65
const CELL_ACTION_MIN_INTERVAL_MS := 50

var _last_ui_click_ms := -10000
var _last_ui_slider_ms := -10000
var _last_cell_place_ms := -10000
var _last_cell_delete_ms := -10000

# 音效主音量 (0.0 ~ 1.0)
var sfx_volume: float = 1.0:
	set(v):
		sfx_volume = clampf(v, 0.0, 1.0)

const AUDIO_SETTINGS_PATH := "user://audio_settings.json"

static func set_volume(val: float) -> void:
	if instance != null:
		instance.sfx_volume = val

static func get_volume() -> float:
	if instance != null:
		return instance.sfx_volume
	return 1.0

static func save_audio_settings() -> void:
	var data := {
		"music_volume": MusicManager.get_volume(),
		"sfx_volume": get_volume()
	}
	var file := FileAccess.open(AUDIO_SETTINGS_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(data, "  "))
		file.close()

static func load_audio_settings() -> void:
	if not FileAccess.file_exists(AUDIO_SETTINGS_PATH):
		return
	var file := FileAccess.open(AUDIO_SETTINGS_PATH, FileAccess.READ)
	if file == null:
		return
	var json = JSON.parse_string(file.get_as_text())
	file.close()
	if json is Dictionary:
		if json.has("music_volume"):
			MusicManager.set_volume(float(json["music_volume"]))
		if json.has("sfx_volume"):
			set_volume(float(json["sfx_volume"]))

# 每帧/每拍同类空间音效去重限制，避免数十个同类方块同拍爆发破音
var _frame_spatial_played: Dictionary = {} # stream_path -> Array[Vector2]

func _init() -> void:
	instance = self

func _ready() -> void:
	process_mode = PROCESS_MODE_ALWAYS
	_preload_streams()
	_init_voice_pool()
	load_audio_settings()
	
	# 自动监听场景树新挂载的所有 UI 按钮与滑动条
	get_tree().node_added.connect(_on_node_added)
	_hook_existing_ui(get_tree().root)

func _process(_delta: float) -> void:
	_frame_spatial_played.clear()

func _preload_streams() -> void:
	var paths := [
		PATH_UI_CLICK, PATH_UI_SLIDER, PATH_CELL_PLACE, PATH_CELL_DELETE,
		PATH_PUSHER, PATH_REPLICATOR, PATH_MONSTER, PATH_DESTROYER, PATH_ROTATOR,
		PATH_INHIBITOR_ENGAGE, PATH_INHIBITOR_RELEASE, PATH_TREASURE, PATH_VICTORY
	]
	for p in paths:
		if ResourceLoader.exists(p):
			_streams[p] = load(p)
		else:
			push_warning("SoundManager: 未找到音效文件: " + p)

func _init_voice_pool() -> void:
	# 1. 专用 UI 点击播放器（常驻预热）
	_ui_player = AudioStreamPlayer.new()
	_ui_player.name = "UI_Click_Voice"
	_ui_player.bus = "Master"
	_ui_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	if _streams.has(PATH_UI_CLICK):
		_ui_player.stream = _streams[PATH_UI_CLICK]
	add_child(_ui_player)

	# 2. 专用 UI 滑动条播放器（常驻预热）
	_slider_player = AudioStreamPlayer.new()
	_slider_player.name = "UI_Slider_Voice"
	_slider_player.bus = "Master"
	_slider_player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	if _streams.has(PATH_UI_SLIDER):
		_slider_player.stream = _streams[PATH_UI_SLIDER]
	add_child(_slider_player)

	# 3. 方块多路复用空间音频池
	for i in range(POOL_SIZE):
		var player := AudioStreamPlayer.new()
		player.name = "Voice_%d" % i
		player.bus = "Master"
		player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
		add_child(player)
		_voice_pool.append(player)

func _get_free_voice() -> AudioStreamPlayer:
	# 优先寻找未在播放的声道
	for i in range(POOL_SIZE):
		var idx := (_voice_index + i) % POOL_SIZE
		var p: AudioStreamPlayer = _voice_pool[idx]
		if not p.playing:
			_voice_index = (idx + 1) % POOL_SIZE
			return p
	# 全部在播放时轮转复用最老的声道
	var p: AudioStreamPlayer = _voice_pool[_voice_index]
	_voice_index = (_voice_index + 1) % POOL_SIZE
	return p

# -------------------------------------------------------------
# 空间化音量衰减计算
# 核心机制：根据当前范围和摄像机缩放倍数计算，越大且越在屏幕中央声音越大
# -------------------------------------------------------------
static func calculate_spatial_volume(world_pos: Vector2, camera: Camera2D = null) -> float:
	if camera == null:
		var main_loop := Engine.get_main_loop() as SceneTree
		if main_loop != null and main_loop.root != null:
			var vp := main_loop.root.get_viewport()
			if vp != null:
				camera = vp.get_camera_2d()
	
	if camera == null or not is_instance_valid(camera):
		return 1.0
	
	var cam_pos := camera.global_position
	var cam_zoom := camera.zoom.x
	var vp_size := camera.get_viewport_rect().size
	
	# 摄像机当前视野在世界坐标下的半宽高
	var half_extents := (vp_size * 0.5) / maxf(cam_zoom, 0.05)
	
	# 方块相对于摄像机中心的世界坐标偏移
	var delta := world_pos - cam_pos
	
	# 归一化屏幕相对距离 (中心为0.0，视野边缘为1.0，视野外>1.0)
	var nx := absf(delta.x) / maxf(half_extents.x, 1.0)
	var ny := absf(delta.y) / maxf(half_extents.y, 1.0)
	var norm_dist := maxf(nx, ny)
	
	# 1. 屏幕中央衰减因子: 越在屏幕中央声音越大，边缘衰减至 0.35，出屏衰减至 0
	var center_factor := 0.0
	if norm_dist <= 1.0:
		# 二次平滑衰减: 中心 1.0 -> 边缘 0.35
		center_factor = lerpf(1.0, 0.35, norm_dist * norm_dist)
	elif norm_dist <= 2.2:
		# 屏幕外衰减: 1.0~2.2倍视野区间衰减至 0
		var off_t := (norm_dist - 1.0) / 1.2
		center_factor = lerpf(0.35, 0.0, off_t)
	else:
		return 0.0 # 远离屏幕完全静音，节约音频通道
	
	# 2. 缩放倍数因子: 缩放倍数越大（拉近观察，方块显得越大），音量越大；缩放倍数小（鸟瞰全局），音量平滑减弱
	# 缩放 1.0 时基准系数为 1.0；拉近(>1.0)微增，缩小(<1.0)平滑衰减
	var zoom_factor: float
	if cam_zoom <= 1.0:
		zoom_factor = clampf(remap(cam_zoom, 0.25, 1.0, 0.35, 1.0), 0.2, 1.0)
	else:
		zoom_factor = clampf(remap(cam_zoom, 1.0, 2.5, 1.0, 1.2), 1.0, 1.25)
	
	return center_factor * zoom_factor

# -------------------------------------------------------------
# 播放接口实现
# -------------------------------------------------------------
func play_stream(stream_path: String, volume_mult: float = 1.0, pitch_scale: float = 1.0) -> void:
	if not _streams.has(stream_path):
		return
	var stream: AudioStream = _streams[stream_path]
	if stream == null:
		return
	
	var final_vol := clampf(volume_mult * sfx_volume, 0.0001, 2.0)
	if final_vol <= 0.005:
		return
	
	var player := _get_free_voice()
	player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM
	player.stream = stream
	player.volume_db = linear_to_db(final_vol)
	player.pitch_scale = pitch_scale
	player.play()

func play_spatial_stream(stream_path: String, world_pos: Vector2, base_volume: float = 1.0, pitch_scale: float = 1.0) -> void:
	var spatial_mult := calculate_spatial_volume(world_pos)
	if spatial_mult <= 0.01:
		return
	
	# 同拍去重平滑：同拍内若已经有极近距离的同类音效播放，适当减弱或跳过避免相位干涉
	var played_list: Array = _frame_spatial_played.get(stream_path, [])
	for prev_pos in played_list:
		if (prev_pos as Vector2).distance_squared_to(world_pos) < 64.0 * 64.0:
			spatial_mult *= 0.6
			break
	if played_list.size() >= 3:
		# 同一拍内同类音效最多并发3路最显著的声音
		return
	played_list.append(world_pos)
	_frame_spatial_played[stream_path] = played_list
	
	play_stream(stream_path, base_volume * spatial_mult, pitch_scale)

# -------------------------------------------------------------
# 细胞动作专用接口 (带空间化计算)
# -------------------------------------------------------------
static func play_cell_place(world_pos: Vector2) -> void:
	if instance != null:
		var now := Time.get_ticks_msec()
		if now - instance._last_cell_place_ms < CELL_ACTION_MIN_INTERVAL_MS:
			return
		instance._last_cell_place_ms = now
		instance.play_spatial_stream(PATH_CELL_PLACE, world_pos, 1.0, randf_range(0.96, 1.04))

static func play_cell_delete(world_pos: Vector2) -> void:
	if instance != null:
		var now := Time.get_ticks_msec()
		if now - instance._last_cell_delete_ms < CELL_ACTION_MIN_INTERVAL_MS:
			return
		instance._last_cell_delete_ms = now
		instance.play_spatial_stream(PATH_CELL_DELETE, world_pos, 0.95, randf_range(0.96, 1.04))

static func play_block_pusher(world_pos: Vector2) -> void:
	if instance != null:
		instance.play_spatial_stream(PATH_PUSHER, world_pos, 1.0, randf_range(0.97, 1.03))

static func play_block_replicator(world_pos: Vector2) -> void:
	if instance != null:
		instance.play_spatial_stream(PATH_REPLICATOR, world_pos, 1.0, randf_range(0.98, 1.02))

static func play_block_monster(world_pos: Vector2) -> void:
	if instance != null:
		instance.play_spatial_stream(PATH_MONSTER, world_pos, 1.0, randf_range(0.95, 1.05))

static func play_block_destroyer(world_pos: Vector2) -> void:
	if instance != null:
		instance.play_spatial_stream(PATH_DESTROYER, world_pos, 1.05, randf_range(0.95, 1.03))

static func play_block_rotator(world_pos: Vector2) -> void:
	if instance != null:
		instance.play_spatial_stream(PATH_ROTATOR, world_pos, 1.0, randf_range(0.97, 1.03))

static func play_block_inhibitor_engage(world_pos: Vector2) -> void:
	if instance != null:
		instance.play_spatial_stream(PATH_INHIBITOR_ENGAGE, world_pos, 0.9, 1.0)

static func play_block_inhibitor_release(world_pos: Vector2) -> void:
	if instance != null:
		instance.play_spatial_stream(PATH_INHIBITOR_RELEASE, world_pos, 0.9, 1.0)

static func play_treasure_collect(world_pos: Vector2) -> void:
	if instance != null:
		instance.play_spatial_stream(PATH_TREASURE, world_pos, 1.1, 1.0)

static func play_level_victory() -> void:
	if instance != null:
		instance.play_stream(PATH_VICTORY, 1.1, 1.0)

# -------------------------------------------------------------
# UI 声音接口（低延迟直出）
# -------------------------------------------------------------
func _play_ui_click_internal() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_ui_click_ms < UI_CLICK_MIN_INTERVAL_MS:
		return
	_last_ui_click_ms = now

	var final_vol := clampf(0.95 * sfx_volume, 0.0001, 2.0)
	if final_vol <= 0.005:
		return
	if _ui_player != null:
		if _ui_player.stream == null and _streams.has(PATH_UI_CLICK):
			_ui_player.stream = _streams[PATH_UI_CLICK]
		_ui_player.volume_db = linear_to_db(final_vol)
		_ui_player.pitch_scale = randf_range(0.97, 1.03)
		_ui_player.play(0.0)
	else:
		play_stream(PATH_UI_CLICK, 0.95, randf_range(0.97, 1.03))

func _play_ui_slider_internal() -> void:
	var now := Time.get_ticks_msec()
	if now - _last_ui_slider_ms < SLIDER_THROTTLE_MS:
		return
	_last_ui_slider_ms = now

	var final_vol := clampf(0.7 * sfx_volume, 0.0001, 2.0)
	if final_vol <= 0.005:
		return
	if _slider_player != null:
		if _slider_player.stream == null and _streams.has(PATH_UI_SLIDER):
			_slider_player.stream = _streams[PATH_UI_SLIDER]
		_slider_player.volume_db = linear_to_db(final_vol)
		_slider_player.pitch_scale = randf_range(0.98, 1.02)
		_slider_player.play(0.0)
	else:
		play_stream(PATH_UI_SLIDER, 0.7, randf_range(0.98, 1.02))

static func play_ui_click() -> void:
	if instance != null:
		instance._play_ui_click_internal()

static func play_ui_slider() -> void:
	if instance != null:
		instance._play_ui_slider_internal()

# -------------------------------------------------------------
# 全局 UI 自动挂接机制 (BaseButton, Slider, TabContainer, TabBar, ItemList, PopupMenu)
# -------------------------------------------------------------
func _on_node_added(node: Node) -> void:
	_hook_node(node)
	if node.get_child_count() > 0:
		for c in node.get_children():
			_hook_existing_ui(c)

func _hook_existing_ui(root_node: Node) -> void:
	_hook_node(root_node)
	for child in root_node.get_children():
		_hook_existing_ui(child)

func _hook_node(node: Node) -> void:
	if node is BaseButton:
		_hook_button(node)
	elif node is Slider:
		# 仅挂接真正可交互的滑动条（如音量、模拟速度），坚决不挂接 ScrollBar/ProgressBar，杜绝滚动时连发
		_hook_slider(node)
	elif node is TabContainer:
		_hook_tab_container(node)
	elif node is TabBar:
		_hook_tab_bar(node)
	elif node is ItemList:
		_hook_item_list(node)
	elif node is PopupMenu:
		_hook_popup_menu(node)

## 按钮挂接：button_down（按下瞬间零延迟发声）+ pressed（键盘/快捷键兜底）。
## 防连发：每个按钮自带冷却窗口（BUTTON_SFX_COOLDOWN_MS），同一按钮在窗口内
## 无论收到多少信号（button_down / pressed / 重复的输入事件循环 / 触摸+鼠标
## 合成事件 / 远程桌面重复派发），最多只发声一次。
const BUTTON_SFX_COOLDOWN_MS := 200

func _hook_button(btn: BaseButton) -> void:
	if btn.has_meta(&"sfx_hooked"):
		return
	btn.set_meta(&"sfx_hooked", true)
	btn.set_meta(&"sfx_last_ms", -100000)
	btn.button_down.connect(_on_button_down.bind(btn))
	btn.pressed.connect(_on_button_pressed.bind(btn))

func _button_try_play(btn: BaseButton) -> void:
	var now := Time.get_ticks_msec()
	if now - int(btn.get_meta(&"sfx_last_ms", -100000)) < BUTTON_SFX_COOLDOWN_MS:
		return
	btn.set_meta(&"sfx_last_ms", now)
	play_ui_click()

func _on_button_down(btn: BaseButton) -> void:
	_button_try_play(btn)

func _on_button_pressed(btn: BaseButton) -> void:
	# 正常物理点击时 pressed 紧随 button_down 到达（冷却窗口内，自动去重）；
	# 键盘聚焦回车 / 快捷键 / 代码触发时没有 button_down，此处兜底发声。
	_button_try_play(btn)

func _hook_slider(slider: Range) -> void:
	if slider.has_meta(&"sfx_hooked"):
		return
	slider.set_meta(&"sfx_hooked", true)
	slider.value_changed.connect(_on_slider_value_changed.bind(slider))

func _on_slider_value_changed(_new_val: float, slider: Range) -> void:
	var now := Time.get_ticks_msec()
	var last_tick: int = slider.get_meta(&"sfx_last_tick", 0)
	if now - last_tick >= SLIDER_THROTTLE_MS:
		slider.set_meta(&"sfx_last_tick", now)
		play_ui_slider()

func _hook_tab_container(tc: TabContainer) -> void:
	if tc.has_meta(&"sfx_hooked"):
		return
	tc.set_meta(&"sfx_hooked", true)
	# TabContainer 内部的 TabBar 是实际接收点击的控件，委托给 TabBar 处理，自身不重复监听
	var internal_tb := tc.get_tab_bar()
	if internal_tb != null:
		_hook_tab_bar(internal_tb)

func _hook_tab_bar(tab_bar: TabBar) -> void:
	if tab_bar.has_meta(&"sfx_hooked"):
		return
	# 如果是 TabContainer 内部的 TabBar，直接标记避免被双重挂接
	if tab_bar.get_parent() is TabContainer:
		tab_bar.set_meta(&"sfx_hooked", true)
		return
	tab_bar.set_meta(&"sfx_hooked", true)
	tab_bar.tab_clicked.connect(func(_idx: int): play_ui_click())

func _hook_item_list(item_list: ItemList) -> void:
	if item_list.has_meta(&"sfx_hooked"):
		return
	item_list.set_meta(&"sfx_hooked", true)
	item_list.item_selected.connect(func(_idx: int): play_ui_click())

func _hook_popup_menu(menu: PopupMenu) -> void:
	if menu.has_meta(&"sfx_hooked"):
		return
	menu.set_meta(&"sfx_hooked", true)
	menu.index_pressed.connect(func(_idx: int): play_ui_click())
