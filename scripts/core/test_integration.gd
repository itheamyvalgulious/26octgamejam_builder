extends SceneTree

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	print("=== RUNNING FULL CONSTRUCT A ME INTEGRATION TEST ===")
	test_save_manager_and_levels()
	test_main_menu_scene()
	test_level_select_scene()
	test_level_manager_scene()
	test_level_editor_scene()
	await test_level_player_scene()
	await process_frame
	print("=== ALL INTEGRATION TESTS PASSED! ===")
	quit(0)

func test_save_manager_and_levels() -> void:
	print("1. Testing SaveManager & Default Levels...")
	SaveManager.init_directories()
	var levels := SaveManager.get_all_levels()
	assert(levels.size() >= 4, "Should have at least 4 default levels generated!")
	print("   Found %d levels: %s, %s, %s, %s" % [levels.size(), levels[0].level_name, levels[1].level_name, levels[2].level_name, levels[3].level_name])

	# Test machine save and load
	var blocks: Array[BlockData] = [
		BlockData.new(BlockData.Type.PUSHER, Vector2i(0, 0), BlockData.Direction.RIGHT),
		BlockData.new(BlockData.Type.DESTROYER, Vector2i(1, 0), BlockData.Direction.RIGHT)
	]
	var saved := SaveManager.save_machine("test_rover", blocks)
	assert(saved, "Failed to save test machine!")
	var loaded := SaveManager.load_machine("test_rover")
	assert(loaded.size() == 2, "Loaded machine should have 2 blocks!")
	assert(loaded[0].block_type == BlockData.Type.PUSHER, "Block 0 should be PUSHER!")
	assert(loaded[1].block_type == BlockData.Type.DESTROYER, "Block 1 should be DESTROYER!")
	SaveManager.delete_machine("test_rover")
	print("   Blueprint save/load passed.")

func test_main_menu_scene() -> void:
	print("2. Testing MainMenu Scene...")
	var scene: MainMenu = load("res://scenes/ui/MainMenu.tscn").instantiate()
	root.add_child(scene)
	assert(scene.title_label != null and ProjectSettings.get_setting("application/config/name") == "构造一个我", "Title should contain 构造一个我")
	scene.queue_free()
	print("   MainMenu scene initialized successfully.")

func test_level_select_scene() -> void:
	print("3. Testing LevelSelect Scene...")
	var scene: LevelSelect = load("res://scenes/ui/LevelSelect.tscn").instantiate()
	root.add_child(scene)
	assert(scene.map != null, "Campaign map should exist")
	assert(scene.chapter_buttons.size() >= 4, "Four chapters should be available")
	assert(scene.node_buttons.size() == 1, "Teaching chapter starts with one unlocked lesson")
	scene.queue_free()
	print("   LevelSelect scene initialized successfully.")

func test_level_manager_scene() -> void:
	print("4. Testing LevelManager Scene...")
	var scene: LevelManager = load("res://scenes/ui/LevelManager.tscn").instantiate()
	root.add_child(scene)
	assert(scene.level_item_list != null, "ItemList should exist")
	assert(scene.level_item_list.item_count >= 4, "Should display levels in list")
	# Select custom_level_80400
	for i in range(scene.levels.size()):
		if scene.levels[i].level_id == "custom_level_80400": scene._select_level(i)
	assert(scene.name_edit.text == SaveManager.load_level("custom_level_80400").level_name, "Should load the selected level name into form")
	scene.queue_free()
	print("   LevelManager scene initialized successfully.")

func test_level_editor_scene() -> void:
	print("5. Testing LevelEditor Scene...")
	var scene: LevelEditor = load("res://scenes/ui/LevelEditor.tscn").instantiate()
	root.add_child(scene)
	assert(scene.grid_view != null, "GridView should exist")
	assert(scene.toolbar != null, "Toolbar should exist")
	assert(scene.toolbar.type_buttons.size() == 11, "Editor toolbar should have all 11 block types")
	
	# Place a block and test erase
	scene._place_block_editor(Vector2i(0, 0))
	assert(scene.world.has_block(Vector2i(0, 0)), "Block should be placed in editor")
	scene._erase_block_editor(Vector2i(0, 0))
	assert(not scene.world.has_block(Vector2i(0, 0)), "Block should be erased in editor")

	# Test right-drag group selection in LevelEditor
	scene._place_block_editor(Vector2i(5, 5))
	scene._place_block_editor(Vector2i(6, 5))
	var be1 := scene.world.get_block(Vector2i(5, 5))
	var be2 := scene.world.get_block(Vector2i(6, 5))
	scene.selected_blocks = [be1, be2]
	scene.right_drag_orig_positions = { be1: Vector2i(5, 5), be2: Vector2i(6, 5) }
	scene._apply_selection_drag(Vector2i(2, 3))
	assert(not scene.world.has_block(Vector2i(5, 5)), "Old pos (5, 5) should now be empty")
	assert(not scene.world.has_block(Vector2i(6, 5)), "Old pos (6, 5) should now be empty")
	assert(scene.world.has_block(Vector2i(7, 8)), "be1 should have moved to (7, 8)")
	assert(scene.world.has_block(Vector2i(8, 8)), "be2 should have moved to (8, 8)")

	scene.queue_free()
	print("   LevelEditor scene and group right-click drag verified.")

func test_level_player_scene() -> void:
	print("6. Testing LevelPlayer Scene...")
	var scene: LevelPlayer = load("res://scenes/ui/LevelPlayer.tscn").instantiate()
	root.add_child(scene)
	scene.load_level_data(SaveManager.load_level("custom_level_80400"))
	assert(scene.current_level_data != null, "Level should be loaded")
	assert(scene.sim_engine != null, "Sim engine should be active")
	
	# Place a player pusher and destroyer
	scene.toolbar.select_type(BlockData.Type.PUSHER)
	scene.toolbar.rotate_direction(0) # RIGHT
	scene._try_place_block(Vector2i(-4, -4))
	scene.toolbar.select_type(BlockData.Type.DESTROYER)
	scene._try_place_block(Vector2i(-3, -4))
	
	# Group them into a structure
	var b1 = scene.world.get_block(Vector2i(-4, -4))
	var b2 = scene.world.get_block(Vector2i(-3, -4))
	assert(b1 != null and b2 != null, "Blocks should be placed")
	scene.selected_blocks = [b1, b2]
	scene.group_selected_blocks()
	assert(b1.structure_id > 0 and b1.structure_id == b2.structure_id, "Blocks should share same structure ID!")
	
	# Check border connection logic
	var v1: BlockView = scene.grid_view.get_view(b1.block_id)
	assert(v1 != null, "BlockView should exist")
	assert(v1._is_connected_neighbor(Vector2i(1, 0)) == true, "Right neighbor should be connected and share border!")
	
	# Test step simulation
	scene.step_single_tick()
	while scene.is_animating_tick: await process_frame
	# Pusher and Destroyer should have moved forward to (-3, -4) and (-2, -4)
	assert(b1.grid_pos == Vector2i(-3, -4), "Pusher should move to (-3, -4), got %s" % [b1.grid_pos])
	assert(b2.grid_pos == Vector2i(-2, -4), "Destroyer should move to (-2, -4), got %s" % [b2.grid_pos])
	
	# Test Reset simulation
	scene.reset_simulation()
	var b1_reset = scene.world.get_block(Vector2i(-4, -4))
	assert(b1_reset != null, "Reset should restore player machine to original location (-4, -4)")
	
	scene.queue_free()
	print("   LevelPlayer mechanics, structure grouping, borders, and simulation verified.")
