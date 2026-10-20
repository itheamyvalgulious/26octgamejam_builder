class_name BlockView
extends Node2D

const CELL_SIZE: float = 64.0
const HALF_CELL: float = CELL_SIZE * 0.5
const BASIC_ARTWORK: PackedScene = preload("res://scenes/animation/BasicArtwork.tscn")
const DESTROYER_ARTWORK: PackedScene = preload("res://scenes/animation/DestroyerArtwork.tscn")
const PUSHER_ARTWORK: PackedScene = preload("res://scenes/animation/PusherArtwork.tscn")
const MONSTER_ARTWORK: PackedScene = preload("res://scenes/animation/MonsterArtwork.tscn")
const ROTATOR_ARTWORK: PackedScene = preload("res://scenes/animation/RotatorArtwork.tscn")
const REPLICATOR_ARTWORK: PackedScene = preload("res://scenes/animation/ReplicatorArtwork.tscn")
const ANIMATED_CELL_ARTWORK: PackedScene = preload("res://scenes/animation/AnimatedCellArtwork.tscn")
const INHIBITOR_ARTWORK: PackedScene = preload("res://scenes/animation/InhibitorArtwork.tscn")

## Disable to compare with the original SVG artwork.
@export var use_basic_idle: bool = true
var basic_artwork: Node2D
var destroyer_artwork: DestroyerArtwork
var pusher_artwork: PusherArtwork
var monster_artwork: MonsterArtwork
var rotator_artwork: RotatorArtwork
var replicator_artwork: ReplicatorArtwork
var pollution_artwork: AnimatedCellArtwork
var hard_artwork: AnimatedCellArtwork
var treasure_artwork: AnimatedCellArtwork
var inhibitor_artwork: InhibitorArtwork

var block_data: BlockData
var grid_world: GridWorld
var is_selected: bool = false

# Visual nodes
var inner_sprite: Sprite2D
var inhibited_sprite: Sprite2D
var border_node: Node2D

var _current_tween: Tween
var _pushing := false
var _inhibit_anim_time := 0.0

# Textures cache
static var _texture_cache: Dictionary = {}

func _init(p_block: BlockData, p_world: GridWorld) -> void:
	block_data = p_block
	grid_world = p_world
	position = Vector2(block_data.grid_pos.x * CELL_SIZE + HALF_CELL, block_data.grid_pos.y * CELL_SIZE + HALF_CELL)

	# 1. Custom border node
	border_node = Node2D.new()
	border_node.name = "Border"
	border_node.draw.connect(_on_border_draw)
	add_child(border_node)

	# 2. Inner organelle sprite
	inner_sprite = Sprite2D.new()
	inner_sprite.name = "Inner"
	inner_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(inner_sprite)
	# As a child of Inner, art inherits existing rotation/damage effects.
	basic_artwork = BASIC_ARTWORK.instantiate() as Node2D
	basic_artwork.visible = false
	inner_sprite.add_child(basic_artwork)
	destroyer_artwork = DESTROYER_ARTWORK.instantiate() as DestroyerArtwork
	destroyer_artwork.visible = false
	inner_sprite.add_child(destroyer_artwork)
	pusher_artwork = PUSHER_ARTWORK.instantiate() as PusherArtwork
	pusher_artwork.visible = false
	pusher_artwork.push_finished.connect(_on_pusher_push_finished)
	add_child(pusher_artwork)
	monster_artwork = MONSTER_ARTWORK.instantiate() as MonsterArtwork
	monster_artwork.visible = false
	add_child(monster_artwork)
	rotator_artwork = ROTATOR_ARTWORK.instantiate() as RotatorArtwork
	rotator_artwork.visible = false
	add_child(rotator_artwork)
	replicator_artwork = REPLICATOR_ARTWORK.instantiate() as ReplicatorArtwork
	replicator_artwork.visible = false
	add_child(replicator_artwork)
	pollution_artwork = ANIMATED_CELL_ARTWORK.instantiate() as AnimatedCellArtwork
	pollution_artwork.visible = false
	pollution_artwork.configure("res://scenes/animation/Pollution source(1).png")
	add_child(pollution_artwork)
	hard_artwork = ANIMATED_CELL_ARTWORK.instantiate() as AnimatedCellArtwork
	hard_artwork.visible = false
	hard_artwork.configure("res://scenes/animation/block(1).png")
	add_child(hard_artwork)
	treasure_artwork = ANIMATED_CELL_ARTWORK.instantiate() as AnimatedCellArtwork
	treasure_artwork.visible = false
	treasure_artwork.configure("res://scenes/animation/treasure(1).png")
	add_child(treasure_artwork)

	# 3. Inhibited overlay sprite
	inhibited_sprite = Sprite2D.new()
	inhibited_sprite.name = "Inhibited"
	inhibited_sprite.texture = load("res://scenes/animation/Invalidate_affect(1).png")
	inhibited_sprite.hframes = 2
	inhibited_sprite.frame = 0
	inhibited_sprite.z_index = 3
	inhibited_sprite.modulate = Color(1.0, 1.0, 1.0, 0.7)
	inhibited_sprite.visible = block_data.is_inhibited
	add_child(inhibited_sprite)
	inhibitor_artwork = INHIBITOR_ARTWORK.instantiate() as InhibitorArtwork
	inhibitor_artwork.visible = false
	add_child(inhibitor_artwork)

func _ready() -> void:
	update_appearance()

func update_appearance() -> void:
	if block_data == null:
		return

	# Load texture for inner sprite
	var tex_path := _get_texture_path()
	var tex := _get_cached_texture(tex_path)
	if tex != null:
		inner_sprite.texture = tex
		# Scale to fit cell neatly (leaving border margin)
		var scale_factor := (CELL_SIZE - 4.0) / tex.get_width()
		inner_sprite.scale = Vector2(scale_factor, scale_factor)

	# Rotation: direction * 90 degrees
	inner_sprite.rotation = block_data.direction * (PI / 2.0)
	var show_idle := use_basic_idle and block_data.block_type == BlockData.Type.BASIC
	var show_destroyer := block_data.block_type == BlockData.Type.DESTROYER
	var show_inhibitor := block_data.block_type == BlockData.Type.INHIBITOR
	# Pushers always use the PNG artwork. While idle, PusherArtwork holds
	# the first push frame; during movement it plays the full sequence.
	var show_pusher := block_data.block_type == BlockData.Type.PUSHER
	var show_monster := block_data.block_type == BlockData.Type.WANDERER
	var show_rotator := block_data.block_type == BlockData.Type.ROTATOR
	var show_replicator := block_data.block_type == BlockData.Type.REPLICATOR
	var show_pollution := block_data.block_type == BlockData.Type.POLLUTION
	var show_hard := block_data.block_type == BlockData.Type.HARD
	var show_treasure := block_data.block_type == BlockData.Type.TREASURE
	# Hide only the SVG fallback for the two PNG-driven artworks.
	# Keep the parent visible so its child artwork remains visible.
	if show_destroyer or show_inhibitor or show_monster or show_rotator or show_replicator or show_pollution or show_hard or show_treasure:
		inner_sprite.texture = null
		inner_sprite.scale = Vector2.ONE
		inner_sprite.self_modulate.a = 1.0
	else:
		inner_sprite.self_modulate.a = 0.0 if show_idle or show_pusher else 1.0
	basic_artwork.visible = show_idle
	destroyer_artwork.visible = show_destroyer
	inhibitor_artwork.visible = show_inhibitor
	inhibitor_artwork.set_direction(block_data.direction)
	_refresh_inhibitor_state()
	pusher_artwork.visible = show_pusher
	pusher_artwork.set_direction(block_data.direction)
	monster_artwork.visible = show_monster
	monster_artwork.set_direction(block_data.direction)
	rotator_artwork.visible = show_rotator
	rotator_artwork.set_direction(block_data.direction)
	rotator_artwork.set_sub_mode(block_data.sub_mode)
	replicator_artwork.visible = show_replicator
	replicator_artwork.set_direction(block_data.direction)
	pollution_artwork.visible = show_pollution
	pollution_artwork.set_direction(block_data.direction)
	hard_artwork.visible = show_hard
	hard_artwork.set_direction(block_data.direction)
	treasure_artwork.visible = show_treasure
	treasure_artwork.rotation = 0.0
	# Cancel the SVG-dependent scale so PNG pixels fit the cell consistently.
	basic_artwork.scale = Vector2.ONE * ((CELL_SIZE - 4.0) / 64.0) / inner_sprite.scale
	# DestroyerArtwork owns the one-cell/two-cell artwork scales internally.
	destroyer_artwork.scale = Vector2.ONE

	# Inhibited state
	if inhibited_sprite != null:
		inhibited_sprite.visible = block_data.is_inhibited
		inhibited_sprite.scale = Vector2.ONE

	# Redraw custom borders
	if border_node != null:
		border_node.queue_redraw()
	queue_redraw()

func _process(delta: float) -> void:
	if block_data == null or inhibited_sprite == null:
		return
	if block_data.is_inhibited:
		_inhibit_anim_time += delta
		inhibited_sprite.frame = int(_inhibit_anim_time * 8.0) % 2
	else:
		_inhibit_anim_time = 0.0
		inhibited_sprite.frame = 0

func _refresh_inhibitor_state() -> void:
	if inhibitor_artwork == null or block_data.block_type != BlockData.Type.INHIBITOR or grid_world == null:
		return
	# The block direction is the sensing (detector) direction; the inhibitor
	# suppresses the block on the opposite side. The artwork is rotated 180°
	# so it visually faces the suppression (rear) side.
	var sensing_vec := block_data.get_forward_vec()
	var has_sensed_block := grid_world.get_block(block_data.grid_pos + sensing_vec) != null
	var has_suppressed_block := grid_world.get_block(block_data.grid_pos - sensing_vec) != null
	inhibitor_artwork.refresh_state(has_suppressed_block, has_sensed_block, block_data.is_inhibited)

func _get_texture_path() -> String:
	var btype := block_data.block_type
	# 所有砖块只有一种外观变体；忽略历史数据中的 texture_variant。
	var var_idx := 0

	match btype:
		BlockData.Type.BASIC:
			return "res://assets/textures/blocks/basic_%d.svg" % var_idx
		BlockData.Type.INHIBITOR:
			return "res://assets/textures/blocks/inhibitor_%d.svg" % var_idx
		BlockData.Type.PUSHER:
			return "res://assets/textures/blocks/pusher_%d.svg" % var_idx
		BlockData.Type.REPLICATOR:
			return "res://assets/textures/blocks/replicator_%d.svg" % var_idx
		BlockData.Type.DESTROYER:
			return "res://assets/textures/blocks/destroyer_%d.svg" % var_idx
		BlockData.Type.ROTATOR:
			var rot_type := "rotator_cw" if block_data.sub_mode == 0 else "rotator_ccw"
			return "res://assets/textures/blocks/%s_%d.svg" % [rot_type, var_idx]
		BlockData.Type.HARD:
			return "res://assets/textures/blocks/hard_%d.svg" % var_idx
		BlockData.Type.WANDERER:
			return "res://assets/textures/blocks/wanderer_%d.svg" % var_idx
		BlockData.Type.TREASURE:
			return "res://assets/textures/blocks/treasure_%d.svg" % var_idx
		BlockData.Type.POLLUTION:
			return "res://assets/textures/blocks/pollution_%d.svg" % var_idx
		BlockData.Type.PROTECTED:
			return "res://assets/textures/blocks/protected_%d.svg" % var_idx
		_:
			return "res://assets/textures/blocks/basic_0.svg"

static func _get_cached_texture(path: String) -> Texture2D:
	if not _texture_cache.has(path):
		if ResourceLoader.exists(path):
			_texture_cache[path] = load(path)
		else:
			return null
	return _texture_cache[path]

# -------------------------------------------------------------
# Neighbor-Aware Cellular Border Drawing:
# Erases borders between connected blocks in the same structure!
# -------------------------------------------------------------
func _on_border_draw() -> void:
	if block_data == null:
		return

	var sid := block_data.structure_id
	var half := HALF_CELL - 2.0
	# 结构编组边框为橙色（未编组保持灰色细线）
	var border_color := Color(1.0, 0.55, 0.1, 0.85) if sid > 0 else Color(0.3, 0.4, 0.5, 0.6)
	var width := 3.0 if sid > 0 else 2.0

	# Check 4 neighbors
	var right_connected := _is_connected_neighbor(Vector2i(1, 0))
	var down_connected := _is_connected_neighbor(Vector2i(0, 1))
	var left_connected := _is_connected_neighbor(Vector2i(-1, 0))
	var up_connected := _is_connected_neighbor(Vector2i(0, -1))

	# Draw Top border if not connected to up neighbor
	if not up_connected:
		border_node.draw_line(Vector2(-half, -half), Vector2(half, -half), border_color, width)
	# Draw Bottom border if not connected to down neighbor
	if not down_connected:
		border_node.draw_line(Vector2(-half, half), Vector2(half, half), border_color, width)
	# Draw Left border if not connected to left neighbor
	if not left_connected:
		border_node.draw_line(Vector2(-half, -half), Vector2(-half, half), border_color, width)
	# Draw Right border if not connected to right neighbor
	if not right_connected:
		border_node.draw_line(Vector2(half, -half), Vector2(half, half), border_color, width)

func _is_connected_neighbor(offset: Vector2i) -> bool:
	if block_data.structure_id <= 0 or grid_world == null:
		return false
	var neighbor := grid_world.get_block(block_data.grid_pos + offset)
	return neighbor != null and neighbor.structure_id == block_data.structure_id

# -------------------------------------------------------------
# Selection & HP pip drawing
# -------------------------------------------------------------
func _draw() -> void:
	var half := HALF_CELL - 1.0

	# Draw selection highlight
	if is_selected:
		var sel_color := Color(1.0, 0.85, 0.2, 0.9)
		draw_rect(Rect2(-half - 2, -half - 2, (half + 2) * 2, (half + 2) * 2), sel_color, false, 2.5)

	# Draw HP pips if damaged
	if block_data != null and block_data.hp < block_data.max_hp and block_data.hp > 0:
		var pip_radius := 3.0
		var pip_color := Color(0.9, 0.2, 0.2, 0.9)
		draw_circle(Vector2(0, half - 6), pip_radius, pip_color)

# -------------------------------------------------------------
# Smooth Tween Animations for Ticks
# -------------------------------------------------------------
func animate_to_pos(new_grid_pos: Vector2i, duration: float) -> void:
	var target_pos := Vector2(new_grid_pos.x * CELL_SIZE + HALF_CELL, new_grid_pos.y * CELL_SIZE + HALF_CELL)
	if _current_tween != null and _current_tween.is_valid():
		_current_tween.kill()
	_current_tween = create_tween()
	_current_tween.tween_property(self, "position", target_pos, duration).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func animate_rotation(new_dir: int, duration: float) -> void:
	var target_angle := new_dir * (PI / 2.0)
	var current_angle := inner_sprite.rotation
	# Handle wrap-around gracefully
	var diff := wrapf(target_angle - current_angle, -PI, PI)
	var end_angle := current_angle + diff

	var t := create_tween()
	t.tween_property(inner_sprite, "rotation", end_angle, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for artwork in [pusher_artwork, monster_artwork, rotator_artwork, replicator_artwork, pollution_artwork, hard_artwork]:
		if artwork != null and artwork.visible:
			var artwork_angle := end_angle
			if artwork == monster_artwork:
				artwork_angle = monster_artwork.get_direction_rotation(new_dir)
			t.tween_property(artwork, "rotation", artwork_angle, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_callback(func():
		var final_angle := posmod(new_dir, 4) * (PI / 2.0)
		inner_sprite.rotation = final_angle
		pusher_artwork.rotation = final_angle
		monster_artwork.set_direction(new_dir)
		rotator_artwork.rotation = final_angle
		replicator_artwork.rotation = final_angle
		pollution_artwork.rotation = final_angle
		hard_artwork.rotation = final_angle
		treasure_artwork.rotation = 0.0
	)

func animate_spawn(duration: float) -> void:
	scale = Vector2(0.1, 0.1)
	modulate = Color(1.5, 2.0, 2.5, 0.0) # Holographic cyan flash
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "scale", Vector2.ONE, duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(self, "modulate", Color.WHITE, duration * 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)

func animate_destroy(duration: float, on_complete: Callable) -> void:
	var t := create_tween()
	t.set_parallel(true)
	t.tween_property(self, "scale", Vector2(0.1, 0.1), duration).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	t.tween_property(self, "modulate", Color(2.5, 0.4, 0.4, 0.0), duration)
	t.chain().tween_callback(on_complete)

func play_destroyer_eat() -> void:
	if block_data == null or block_data.block_type != BlockData.Type.DESTROYER:
		return
	destroyer_artwork.play_eat()

func play_pusher_push() -> void:
	if block_data == null or block_data.block_type != BlockData.Type.PUSHER:
		return
	_pushing = true
	pusher_artwork.set_direction(block_data.direction)
	update_appearance()
	pusher_artwork.play_push()

func play_replicator_breed(duration: float = 0.0) -> void:
	if block_data == null or block_data.block_type != BlockData.Type.REPLICATOR:
		return
	replicator_artwork.play_breed(duration)

func play_rotator_turn(duration: float = 1.0) -> void:
	if block_data == null or block_data.block_type != BlockData.Type.ROTATOR:
		return
	rotator_artwork.set_direction(block_data.direction)
	rotator_artwork.set_sub_mode(block_data.sub_mode)
	rotator_artwork.play_turn(duration)

func _on_pusher_push_finished() -> void:
	_pushing = false
	update_appearance()

func animate_damage(duration: float) -> void:
	var t := create_tween()
	t.tween_property(inner_sprite, "modulate", Color(2.5, 0.3, 0.3, 1.0), duration * 0.3)
	t.tween_property(inner_sprite, "modulate", Color.WHITE, duration * 0.7)
	queue_redraw()
