extends SceneTree

func _init() -> void:
	print("=== RUNNING CONSTRUCT A ME SIMULATION TESTS ===")
	test_inhibitor()
	test_rotator_sum()
	test_pusher_structure_and_diagonal()
	test_replicator_and_structure_independence()
	test_simultaneous_pusher_and_replicator()
	test_destroyer_and_hard_block_immunity()
	test_wanderer_jump_and_damage()
	test_victory_conditions()
	print("=== ALL TESTS PASSED SUCCESSFULLY! ===")
	quit(0)

func test_inhibitor() -> void:
	print("Testing Inhibitor...")
	var world := GridWorld.new()
	# Place Inhibitor at (5, 5) facing RIGHT
	var inh := BlockData.new(BlockData.Type.INHIBITOR, Vector2i(5, 5), BlockData.Direction.RIGHT)
	# Place Sensor target in front at (6, 5)
	var front_b := BlockData.new(BlockData.Type.BASIC, Vector2i(6, 5), BlockData.Direction.RIGHT)
	# Place Block in rear at (4, 5)
	var rear_b := BlockData.new(BlockData.Type.ROTATOR, Vector2i(4, 5), BlockData.Direction.RIGHT)

	world.add_block(inh)
	world.add_block(front_b)
	world.add_block(rear_b)

	var sim := SimulationEngine.new(world)
	var res := sim.step_tick()
	assert(rear_b.is_inhibited == true, "Rear block should be inhibited!")
	print("  Inhibitor successfully suppressed rear block.")

func test_rotator_sum() -> void:
	print("Testing Rotator Summation...")
	var world := GridWorld.new()
	# Target at (5, 5) facing RIGHT (0)
	var target := BlockData.new(BlockData.Type.BASIC, Vector2i(5, 5), BlockData.Direction.RIGHT)
	world.add_block(target)

	# Rotator 1 from West (4, 5) facing East (0), CW (+1)
	var r1 := BlockData.new(BlockData.Type.ROTATOR, Vector2i(4, 5), BlockData.Direction.RIGHT)
	r1.sub_mode = 0 # CW
	world.add_block(r1)

	# Rotator 2 from North (5, 4) facing South (1), CW (+1)
	var r2 := BlockData.new(BlockData.Type.ROTATOR, Vector2i(5, 4), BlockData.Direction.DOWN)
	r2.sub_mode = 0 # CW
	world.add_block(r2)

	var sim := SimulationEngine.new(world)
	sim.step_tick()
	# Target was RIGHT (0) + 1 + 1 = 2 (LEFT)
	assert(target.direction == BlockData.Direction.LEFT, "Target should have rotated 180 degrees (to LEFT)!")
	print("  Rotator angle summation verified.")

func test_pusher_structure_and_diagonal() -> void:
	print("Testing Pusher Structure & Diagonal Movement...")
	var world := GridWorld.new()
	# Create a 2-block structure at (5, 5) and (5, 6)
	var b1 := BlockData.new(BlockData.Type.BASIC, Vector2i(5, 5))
	var b2 := BlockData.new(BlockData.Type.BASIC, Vector2i(5, 6))
	world.add_block(b1)
	world.add_block(b2)
	var sid := world.group_blocks([b1, b2])

	# Pusher 1 from (4, 5) pushing RIGHT (1, 0)
	var p1 := BlockData.new(BlockData.Type.PUSHER, Vector2i(4, 5), BlockData.Direction.RIGHT)
	world.add_block(p1)

	# Pusher 2 from (5, 4) pushing DOWN (0, 1)
	var p2 := BlockData.new(BlockData.Type.PUSHER, Vector2i(5, 4), BlockData.Direction.DOWN)
	world.add_block(p2)

	var sim := SimulationEngine.new(world)
	sim.step_tick()

	# 两个方向同时受力时，随机选择单一有效方向仲裁（本回合另一方向无效）
	var d1: Vector2i = b1.grid_pos - Vector2i(5, 5)
	var d2: Vector2i = b2.grid_pos - Vector2i(5, 6)
	assert(d1 == d2, "Structure blocks must move as a rigid whole (got %s vs %s)" % [d1, d2])
	assert(d1 == Vector2i(1, 0) or d1 == Vector2i(0, 1), "Structure should move exactly one axis (RIGHT or DOWN), got %s" % [d1])
	print("  Two-axis push arbitration: single-axis movement verified (%s)." % [d1])

func test_replicator_and_structure_independence() -> void:
	print("Testing Replicator & Structure Independence...")
	var world := GridWorld.new()
	# Replicator at (5, 5) facing RIGHT
	var rep := BlockData.new(BlockData.Type.REPLICATOR, Vector2i(5, 5), BlockData.Direction.RIGHT)
	world.add_block(rep)

	# Source block in rear at (4, 5), part of structure 42
	var src := BlockData.new(BlockData.Type.BASIC, Vector2i(4, 5), BlockData.Direction.UP)
	src.structure_id = 42
	world.add_block(src)

	var sim := SimulationEngine.new(world)
	sim.step_tick()

	var replica := world.get_block(Vector2i(6, 5))
	assert(replica != null, "Replica should be placed at (6, 5)!")
	assert(replica.direction == BlockData.Direction.UP, "Replica must keep source direction!")
	assert(replica.structure_id == 0, "Replica must NOT inherit structure ID!")
	print("  Replicator verified.")

func test_destroyer_and_hard_block_immunity() -> void:
	print("Testing Destroyer & Hard Block Immunity...")
	var world := GridWorld.new()
	# Destroyer 1 facing Hard Block
	var d1 := BlockData.new(BlockData.Type.DESTROYER, Vector2i(2, 2), BlockData.Direction.RIGHT)
	var hard := BlockData.new(BlockData.Type.HARD, Vector2i(3, 2), BlockData.Direction.RIGHT)
	world.add_block(d1)
	world.add_block(hard)

	var sim := SimulationEngine.new(world)
	sim.step_tick()
	assert(world.has_block(Vector2i(3, 2)), "Uninhibited Hard block must survive Destroyer!")

	# Now inhibit the hard block
	hard.is_inhibited = true
	var snap := world.clone()
	snap.get_block(hard.grid_pos).is_inhibited = true
	sim._simulate_destroyers(snap, SimulationEngine.TickResult.new())
	assert(not world.has_block(Vector2i(3, 2)), "Inhibited Hard block must be destroyed!")
	print("  Hard block immunity and inhibition verified.")

func test_simultaneous_pusher_and_replicator() -> void:
	print("Testing Simultaneous Pusher & Replicator Execution...")
	var world := GridWorld.new()
	# At t0:
	# Downward Pusher at (0, 0)
	var pusher := BlockData.new(BlockData.Type.PUSHER, Vector2i(0, 0), BlockData.Direction.DOWN)
	# Rightward Replicator at (1, 0) - immediately to the right of Pusher
	# Behind replicator is (0, 0), in front is (2, 0)
	var rep := BlockData.new(BlockData.Type.REPLICATOR, Vector2i(1, 0), BlockData.Direction.RIGHT)

	world.add_block(pusher)
	world.add_block(rep)

	var sim := SimulationEngine.new(world)
	var res := sim.step_tick()

	# Pusher moved down to (0, 1)
	assert(pusher.grid_pos == Vector2i(0, 1), "Pusher should have moved down to (0, 1)!")
	assert(world.get_block(Vector2i(0, 1)) == pusher, "Pusher cell at (0, 1) should be pusher!")

	# Replicator stayed at (1, 0)
	assert(rep.grid_pos == Vector2i(1, 0), "Replicator should remain at (1, 0)!")

	# Replicator simultaneously copied the pusher at t0 to (2, 0)!
	var replica := world.get_block(Vector2i(2, 0))
	assert(replica != null, "Replicator MUST simultaneously replicate the pusher that was behind it at t0!")
	assert(replica.block_type == BlockData.Type.PUSHER, "Replicated block must be a Pusher!")
	assert(replica.direction == BlockData.Direction.DOWN, "Replicated pusher must face DOWN!")

	print("  Simultaneous Pusher + Replicator test passed successfully!")

func test_wanderer_jump_and_damage() -> void:
	print("Testing Wanderer Jump and Step...")
	var world := GridWorld.new()
	# Wanderer at (2, 2) on floor (2, 3) facing RIGHT
	var w := BlockData.new(BlockData.Type.WANDERER, Vector2i(2, 2), BlockData.Direction.RIGHT)
	var floor1 := BlockData.new(BlockData.Type.BASIC, Vector2i(2, 3))
	var step_obstacle := BlockData.new(BlockData.Type.BASIC, Vector2i(3, 2))
	var floor2 := BlockData.new(BlockData.Type.BASIC, Vector2i(3, 3))
	world.add_block(w)
	world.add_block(floor1)
	world.add_block(step_obstacle)
	world.add_block(floor2)

	var sim := SimulationEngine.new(world)
	sim.step_tick()
	# Obstacle should take 1 damage (HP was 2 -> now 1)
	assert(step_obstacle.hp == 1, "Obstacle should take contact damage from Wanderer!")
	# Wanderer should jump up onto the step (3, 1)
	assert(w.grid_pos == Vector2i(3, 1), "Wanderer should jump up onto step at (3, 1), got %s" % [w.grid_pos])
	print("  Wanderer jump and damage verified.")

func test_victory_conditions() -> void:
	print("Testing Victory Conditions & Treasure Return...")
	var world := GridWorld.new()
	# Player build area: Rect2i(0, 0, 5, 5)
	var build_area := Rect2i(0, 0, 5, 5)

	# Destroyer at (3, 2) facing RIGHT, Pollution at (4, 2)
	var des := BlockData.new(BlockData.Type.DESTROYER, Vector2i(3, 2), BlockData.Direction.RIGHT)
	var pol := BlockData.new(BlockData.Type.POLLUTION, Vector2i(4, 2))
	# Treasure at (10, 2) - outside build area!
	var tr := BlockData.new(BlockData.Type.TREASURE, Vector2i(10, 2))

	world.add_block(pol)
	world.add_block(des)
	world.add_block(tr)

	var sim := SimulationEngine.new(world)
	sim.player_build_area = build_area
	var res := sim.step_tick()
	# Pollution was destroyed, but treasure is at (10, 2) outside build area -> NOT victory yet
	assert(res.is_victory == false, "Level should NOT be won while treasure is outside player build area!")
	assert(world.has_block(Vector2i(10, 2)), "Treasure should still be on grid outside build area")

	# Now simulate pusher bringing treasure into build area at (2, 2)
	world.move_block(Vector2i(10, 2), Vector2i(2, 2))

	var res2 := sim.step_tick()
	# Now treasure is inside build area -> should be collected and victory achieved!
	assert(res2.is_victory == true, "Level should be won when treasure is returned into player build area!")
	# 当前设计：宝藏记为已回收但保留方块本身，避免回收动作改变场面
	assert(world.has_block(Vector2i(2, 2)), "Treasure block is kept on grid after collection (by design)")
	print("  Victory condition and treasure return to build area verified.")
