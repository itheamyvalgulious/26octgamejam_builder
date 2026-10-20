class_name GridView
extends Node2D

const CELL_SIZE: float = 64.0
const HALF_CELL: float = CELL_SIZE * 0.5
const SoundManager = preload("res://scripts/core/SoundManager.gd")
const BACKGROUND_VIEW: PackedScene = preload("res://scenes/animation/BackgroundView.tscn")
var background_view: BackgroundView
var grid_world: GridWorld
var player_build_area: Rect2i = Rect2i(0, 0, 0, 0)
var is_level_editor_mode: bool = false # If true, can place anywhere regardless of build area
var tutorial_target: Dictionary = {}
var blocks_outside_build_area: Array[Vector2i] = []

# BlockView mapping: block_id -> BlockView
var _views: Dictionary = {}
# Destroyer id -> last target id already used to trigger an eat animation.
# This prevents a repeated simulation refresh from rewinding the same action.
var _destroyer_eat_targets: Dictionary = {}

# Ghost preview for placing
var preview_active: bool = false
var preview_type: int = BlockData.Type.BASIC
var preview_dir: int = BlockData.Direction.RIGHT
var preview_variant: int = 0
var preview_sub_mode: int = 0
var preview_grid_pos: Vector2i = Vector2i.ZERO

# Box selection rectangle (in world coords)
var is_box_selecting: bool = false
var box_select_start: Vector2 = Vector2.ZERO
var box_select_current: Vector2 = Vector2.ZERO

var preview_block_data: BlockData
var preview_block_view: BlockView

# Multi-block Ghost preview for Paste / Load Blueprint
var multi_ghost_root: Node2D
var multi_ghost_active: bool = false
var multi_ghost_blocks: Array[Dictionary] = []
var multi_ghost_sprites: Array[BlockView] = []
var multi_ghost_mouse_pos: Vector2i = Vector2i.ZERO
var multi_ghost_has_conflict: bool = false

func _ready() -> void:
	background_view = BACKGROUND_VIEW.instantiate() as BackgroundView
	add_child(background_view)
	_ensure_preview_block_view()
	_ensure_multi_ghost_root()

func _ensure_preview_block_view() -> void:
	if preview_block_view == null:
		preview_block_data = BlockData.new(BlockData.Type.BASIC, Vector2i.ZERO)
		preview_block_view = BlockView.new(preview_block_data, null)
		preview_block_view.name = "PreviewBlockView"
		preview_block_view.z_index = 10
		preview_block_view.visible = false
		add_child(preview_block_view)

func _ensure_multi_ghost_root() -> void:
	if multi_ghost_root == null:
		multi_ghost_root = Node2D.new()
		multi_ghost_root.z_index = 10
		add_child(multi_ghost_root)

func set_world(p_world: GridWorld) -> void:
	if grid_world != null:
		grid_world.block_added.disconnect(_on_block_added)
		grid_world.block_removed.disconnect(_on_block_removed)
		grid_world.structure_changed.disconnect(_on_structure_changed)
		if grid_world.block_moved.is_connected(_on_block_moved):
			grid_world.block_moved.disconnect(_on_block_moved)

	grid_world = p_world
	if background_view != null:
		background_view.set_world(grid_world, player_build_area)
	_clear_all_views()
	_destroyer_eat_targets.clear()

	if grid_world != null:
		grid_world.block_added.connect(_on_block_added)
		grid_world.block_removed.connect(_on_block_removed)
		grid_world.structure_changed.connect(_on_structure_changed)
		grid_world.block_moved.connect(_on_block_moved)
		for b in grid_world.get_all_blocks():
			_create_view_for_block(b)

	queue_redraw()

func _on_block_moved(b: BlockData, old_pos: Vector2i, new_pos: Vector2i) -> void:
	var v := get_view(b.block_id)
	if v != null:
		v.position = grid_to_world(new_pos)
		v.update_appearance()
	_refresh_neighbor_borders(old_pos)
	_refresh_neighbor_borders(new_pos)

func _clear_all_views() -> void:
	for v in _views.values():
		if is_instance_valid(v):
			v.queue_free()
	_views.clear()
	for child in get_children():
		if child is BlockView and child != preview_block_view:
			child.queue_free()

func _create_view_for_block(b: BlockData) -> BlockView:
	var view := BlockView.new(b, grid_world)
	_views[b.block_id] = view
	add_child(view)
	return view

func _on_block_added(b: BlockData) -> void:
	if not _views.has(b.block_id):
		_create_view_for_block(b)
	_refresh_neighbor_borders(b.grid_pos)

func _on_block_removed(b: BlockData) -> void:
	if _views.has(b.block_id):
		var v: BlockView = _views[b.block_id]
		_views.erase(b.block_id)
		v.queue_free()
	_refresh_neighbor_borders(b.grid_pos)

func _on_structure_changed(_sid: int) -> void:
	for v: BlockView in _views.values():
		v.update_appearance()

func _refresh_neighbor_borders(pos: Vector2i) -> void:
	for offset in BlockData.DIR_VECTORS:
		var n := grid_world.get_block(pos + offset)
		if n != null and _views.has(n.block_id):
			var nv: BlockView = _views[n.block_id]
			nv.update_appearance()

func get_view(block_id: int) -> BlockView:
	return _views.get(block_id, null)

# Coordinate conversion
func world_to_grid(world_pos: Vector2) -> Vector2i:
	return Vector2i(
		int(floor(world_pos.x / CELL_SIZE)),
		int(floor(world_pos.y / CELL_SIZE))
	)

func grid_to_world(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * CELL_SIZE + HALF_CELL, grid_pos.y * CELL_SIZE + HALF_CELL)

func is_in_build_area(grid_pos: Vector2i) -> bool:
	if is_level_editor_mode:
		return true
	if player_build_area.size == Vector2i.ZERO:
		return true # Unrestricted
	return player_build_area.has_point(grid_pos)

# -------------------------------------------------------------
# Drawing Grid & Build Area & Selection
# -------------------------------------------------------------
func _draw() -> void:
	if background_view != null:
		background_view.set_build_area(player_build_area)
	# Subtle grid lines around the visible area
	var grid_range := 40
	var line_color := Color(0.129, 0.204, 0.243, 0.7)
	var origin_color := Color(0.235, 0.357, 0.420, 0.7)

	for x in range(-grid_range, grid_range + 1):
		var start := Vector2(x * CELL_SIZE, -grid_range * CELL_SIZE)
		var end := Vector2(x * CELL_SIZE, grid_range * CELL_SIZE)
		var col := origin_color if x == 0 else line_color
		var width := 1.5 if x == 0 else 1.0
		draw_dashed_line(start, end, col, width, 8.0, true)

	for y in range(-grid_range, grid_range + 1):
		var start := Vector2(-grid_range * CELL_SIZE, y * CELL_SIZE)
		var end := Vector2(grid_range * CELL_SIZE, y * CELL_SIZE)
		var col := origin_color if y == 0 else line_color
		var width := 1.5 if y == 0 else 1.0
		draw_dashed_line(start, end, col, width, 8.0, true)

	# Draw player build area (if active)
	if player_build_area.size != Vector2i.ZERO:
		var area_rect := Rect2(
			player_build_area.position.x * CELL_SIZE,
			player_build_area.position.y * CELL_SIZE,
			player_build_area.size.x * CELL_SIZE,
			player_build_area.size.y * CELL_SIZE
		)
		# Soft green/cyan tinted zone
		draw_rect(area_rect, Color(1.0, 0.48, 0.08, 0.12), true)
		draw_rect(area_rect, Color(1.0, 0.68, 0.18, 0.9), false, 2.5)

	# Draw warning highlight for player blocks outside build area
	if not blocks_outside_build_area.is_empty():
		for pos in blocks_outside_build_area:
			var r := Rect2(Vector2(pos) * CELL_SIZE, Vector2.ONE * CELL_SIZE)
			draw_rect(r, Color(1.0, 0.2, 0.2, 0.18), true)
			draw_rect(r.grow(-2), Color(1.0, 0.3, 0.3, 0.85), false, 2.5)

	# Draw Drag Selection Box
	if not tutorial_target.is_empty():
		var target_pos := Vector2i(int(tutorial_target.x), int(tutorial_target.y))
		var target_rect := Rect2(Vector2(target_pos) * CELL_SIZE, Vector2.ONE * CELL_SIZE)
		draw_rect(target_rect.grow(-3), Color(0.4, 1.0, 0.8, 0.2), true)
		draw_rect(target_rect.grow(-3), Color("#80ffd7"), false, 3.0)
		draw_string(ThemeDB.fallback_font, target_rect.position + Vector2(8, -8),
			str(tutorial_target.get("marker", "A")), HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("#80ffd7"))

	if is_box_selecting:
		var r := Rect2(box_select_start, box_select_current - box_select_start).abs()
		draw_rect(r, Color(0.2, 0.6, 1.0, 0.2), true)
		draw_rect(r, Color(0.4, 0.8, 1.0, 0.8), false, 1.5)

func update_preview(active: bool, btype: int, dir: int, variant: int, sub_mode: int, grid_pos: Vector2i) -> void:
	preview_active = active
	preview_type = btype
	preview_dir = dir
	preview_variant = variant
	preview_sub_mode = sub_mode
	preview_grid_pos = grid_pos

	_ensure_preview_block_view()

	if not active:
		preview_block_view.visible = false
		return

	preview_block_view.visible = true
	preview_block_data.block_type = btype
	preview_block_data.direction = dir
	preview_block_data.texture_variant = variant
	preview_block_data.sub_mode = sub_mode
	preview_block_data.grid_pos = grid_pos
	preview_block_view.position = grid_to_world(grid_pos)
	preview_block_view.update_appearance()

	var existing := grid_world.get_block(grid_pos) if grid_world != null else null
	if existing != null and existing.is_world_block and not is_level_editor_mode:
		# Protected world block: red
		preview_block_view.modulate = Color(1.0, 0.25, 0.25, 0.65)
	elif not is_in_build_area(grid_pos):
		# Outside build area (allowed to place, but will require moving before sim): amber
		preview_block_view.modulate = Color(1.0, 0.82, 0.3, 0.65)
	else:
		preview_block_view.modulate = Color(1.0, 1.0, 1.0, 0.65)

# -------------------------------------------------------------
# Multi-block Ghost Preview (Paste & Load Blueprint)
# -------------------------------------------------------------
func start_multi_ghost(blocks: Array[BlockData]) -> void:
	cancel_multi_ghost()
	if blocks.is_empty():
		return

	# Calculate center of mass
	var sum := Vector2.ZERO
	for b in blocks:
		sum += Vector2(b.grid_pos)
	var center := sum / float(blocks.size())
	var anchor := Vector2i(int(round(center.x)), int(round(center.y)))

	multi_ghost_blocks.clear()
	for b in blocks:
		multi_ghost_blocks.append({
			"offset": b.grid_pos - anchor,
			"type": b.block_type,
			"dir": b.direction,
			"variant": b.texture_variant,
			"sub_mode": b.sub_mode,
			"structure_id": b.structure_id
		})

	multi_ghost_active = true
	_create_multi_ghost_sprites()
	if is_inside_tree():
		multi_ghost_mouse_pos = world_to_grid(get_global_mouse_position())
	update_multi_ghost_position(multi_ghost_mouse_pos)

func _create_multi_ghost_sprites() -> void:
	_ensure_multi_ghost_root()
	for s in multi_ghost_sprites:
		if is_instance_valid(s):
			s.queue_free()
	multi_ghost_sprites.clear()

	for d in multi_ghost_blocks:
		var b := BlockData.new(d["type"], d["offset"], d["dir"])
		b.texture_variant = d["variant"]
		b.sub_mode = d["sub_mode"]
		b.structure_id = d.get("structure_id", 0)
		var view := BlockView.new(b, null)
		view.modulate = Color(1.0, 1.0, 1.0, 0.65)
		multi_ghost_root.add_child(view)
		multi_ghost_sprites.append(view)

	_refresh_multi_ghost_sprites()

func _refresh_multi_ghost_sprites() -> void:
	for i in range(multi_ghost_blocks.size()):
		if i >= multi_ghost_sprites.size():
			break
		var d: Dictionary = multi_ghost_blocks[i]
		var view: BlockView = multi_ghost_sprites[i]
		if view != null:
			view.block_data.block_type = d["type"]
			view.block_data.direction = d["dir"]
			view.block_data.texture_variant = d["variant"]
			view.block_data.sub_mode = d["sub_mode"]
			view.block_data.structure_id = d.get("structure_id", 0)
			view.update_appearance()

	update_multi_ghost_position(multi_ghost_mouse_pos)

func rotate_multi_ghost_cw() -> void:
	if not multi_ghost_active: return
	for d in multi_ghost_blocks:
		var old_offset: Vector2i = d["offset"]
		d["offset"] = Vector2i(-old_offset.y, old_offset.x)
		d["dir"] = (d["dir"] + 1) % 4
	_refresh_multi_ghost_sprites()

func rotate_multi_ghost_ccw() -> void:
	if not multi_ghost_active: return
	for d in multi_ghost_blocks:
		var old_offset: Vector2i = d["offset"]
		d["offset"] = Vector2i(old_offset.y, -old_offset.x)
		d["dir"] = (d["dir"] + 3) % 4
	_refresh_multi_ghost_sprites()

func flip_multi_ghost_h() -> void:
	if not multi_ghost_active: return
	for d in multi_ghost_blocks:
		var old_offset: Vector2i = d["offset"]
		d["offset"] = Vector2i(-old_offset.x, old_offset.y)
		match d["dir"]:
			BlockData.Direction.RIGHT: d["dir"] = BlockData.Direction.LEFT
			BlockData.Direction.LEFT: d["dir"] = BlockData.Direction.RIGHT
		if d["type"] == BlockData.Type.ROTATOR:
			d["sub_mode"] = 1 - d["sub_mode"]
	_refresh_multi_ghost_sprites()

func flip_multi_ghost_v() -> void:
	if not multi_ghost_active: return
	for d in multi_ghost_blocks:
		var old_offset: Vector2i = d["offset"]
		d["offset"] = Vector2i(old_offset.x, -old_offset.y)
		match d["dir"]:
			BlockData.Direction.DOWN: d["dir"] = BlockData.Direction.UP
			BlockData.Direction.UP: d["dir"] = BlockData.Direction.DOWN
		if d["type"] == BlockData.Type.ROTATOR:
			d["sub_mode"] = 1 - d["sub_mode"]
	_refresh_multi_ghost_sprites()

func update_multi_ghost_position(mouse_grid: Vector2i) -> void:
	multi_ghost_mouse_pos = mouse_grid
	if not multi_ghost_active:
		return

	multi_ghost_has_conflict = false

	for i in range(multi_ghost_blocks.size()):
		if i >= multi_ghost_sprites.size():
			break
		var d: Dictionary = multi_ghost_blocks[i]
		var view: BlockView = multi_ghost_sprites[i]
		if view == null:
			continue

		var target_pos: Vector2i = mouse_grid + d["offset"]
		view.position = grid_to_world(target_pos)

		var conflict := false
		if grid_world != null and grid_world.has_block(target_pos):
			conflict = true
		if not is_level_editor_mode and not is_in_build_area(target_pos):
			conflict = true

		if conflict:
			multi_ghost_has_conflict = true
			view.modulate = Color(1.0, 0.25, 0.25, 0.75)
		else:
			view.modulate = Color(1.0, 1.0, 1.0, 0.65)

func can_place_multi_ghost() -> bool:
	return multi_ghost_active and not multi_ghost_has_conflict

func cancel_multi_ghost() -> void:
	multi_ghost_active = false
	for s in multi_ghost_sprites:
		if is_instance_valid(s):
			s.queue_free()
	multi_ghost_sprites.clear()
	multi_ghost_blocks.clear()

func is_multi_ghost_active() -> bool:
	return multi_ghost_active

func get_multi_ghost_blocks_to_place(mouse_grid: Vector2i) -> Array[BlockData]:
	var result: Array[BlockData] = []
	for d in multi_ghost_blocks:
		var target_pos: Vector2i = mouse_grid + d["offset"]
		var b := BlockData.new(d["type"], target_pos, d["dir"])
		b.texture_variant = d["variant"]
		b.sub_mode = d["sub_mode"]
		b.structure_id = d["structure_id"]
		result.append(b)
	return result

# -------------------------------------------------------------
# Tick Animation Player
# -------------------------------------------------------------
func play_tick_animation(result: SimulationEngine.TickResult, duration: float, on_finish: Callable) -> void:
	# 步长一致修复：无论本步是否发生旋转，移动与各特效动画都从 tick 起点开始、
	# 恰好铺满整个步时长；旋转动画与移动并行、只占 tick 的前 40%（方块先转完、
	# 再保持新朝向继续滑行）。这样每一步的可见移动时长与移动速度完全一致，
	# 节拍恒定，不再出现"有旋转的那步移动被压短"的步长不均。
	var has_rotation := not result.rotated_blocks.is_empty()
	var rotation_duration := duration * 0.4 if has_rotation else 0.0

	# 1. Rotations: only targets actually affected by a rotator are animated.
	for rot in result.rotated_blocks:
		var v := get_view(rot["id"])
		if v != null:
			v.animate_rotation(rot["new_dir"], rotation_duration)
			SoundManager.play_block_rotator(v.global_position)
	for action in result.rotator_actions:
		var source_view := get_view(action["id"])
		if source_view != null:
			source_view.play_rotator_turn(rotation_duration)

	# 2. Movement & effects span the FULL tick duration on every step
	#    (no gating delay), so each step's stride takes exactly equal time.
	_play_movement_and_effects(result, duration)

	# Wait duration then call on_finish
	var t := create_tween()
	t.tween_interval(duration)
	t.tween_callback(func():
		# Refresh borders after animations complete
		for v: BlockView in _views.values():
			v.border_node.queue_redraw()
		on_finish.call()
	)

func _play_movement_and_effects(result: SimulationEngine.TickResult, duration: float) -> void:
	# 2. Movements
	for mov in result.moved_blocks:
		var v := get_view(mov["id"])
		if v != null:
			if v.block_data.block_type == BlockData.Type.PUSHER:
				v.play_pusher_push()
				SoundManager.play_block_pusher(v.global_position)
			elif v.block_data.block_type == BlockData.Type.WANDERER:
				SoundManager.play_block_monster(v.global_position)
			v.animate_to_pos(mov["new_pos"], duration)

	# 3. Damages
	for dmg in result.damaged_blocks:
		var v := get_view(dmg["id"])
		if v != null:
			v.animate_damage(duration)

	# 4. Inhibitions: refreshed before spawns/destructions, matching the
	# simulation order where inhibition resolves first, before other machines.
	for v in _views.values():
		var was_inhibited: bool = v.inhibited_sprite.visible
		var is_now_inhibited: bool = v.block_data.is_inhibited
		v.inhibited_sprite.visible = is_now_inhibited
		v._refresh_inhibitor_state()
		if not was_inhibited and is_now_inhibited:
			SoundManager.play_block_inhibitor_engage(v.global_position)
		elif was_inhibited and not is_now_inhibited:
			SoundManager.play_block_inhibitor_release(v.global_position)

	# 5. Spawns
	for spawned_block in result.spawned_blocks:
		var v := get_view(spawned_block.block_id)
		if v == null:
			v = _create_view_for_block(spawned_block)
		v.animate_spawn(duration)
		SoundManager.play_block_replicator(v.global_position)
		for source in grid_world.get_all_blocks():
			if source.block_type == BlockData.Type.REPLICATOR and source.grid_pos + source.get_forward_vec() == spawned_block.grid_pos:
				var source_view := get_view(source.block_id)
				if source_view != null:
					source_view.play_replicator_breed(duration)

	# 6. Destructions & Collections
	for action in result.destroyer_actions:
		var destroyer_id: int = action["id"]
		var target_id: int = action["target_id"]
		if _destroyer_eat_targets.get(destroyer_id, -1) == target_id:
			continue
		_destroyer_eat_targets[destroyer_id] = target_id
		var destroyer_view := get_view(destroyer_id)
		if destroyer_view != null:
			destroyer_view.play_destroyer_eat()
			SoundManager.play_block_destroyer(destroyer_view.global_position)

	for dest_block in result.destroyed_blocks:
		var v := get_view(dest_block.block_id)
		if v != null:
			v.animate_destroy(duration * 0.8, func():
				if is_instance_valid(v):
					v.queue_free()
			)
			_views.erase(dest_block.block_id)

	for tr_block in result.collected_treasures:
		var v := get_view(tr_block.block_id)
		if v != null:
			SoundManager.play_treasure_collect(v.global_position)
			v.animate_destroy(duration * 0.8, func():
				if is_instance_valid(v):
					v.queue_free()
			)
			_views.erase(tr_block.block_id)
