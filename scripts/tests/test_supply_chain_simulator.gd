extends Node


func _instantiate_game() -> Node:
	var game_scene: PackedScene = load("res://node_2d.tscn") as PackedScene
	assert(game_scene != null, "Could not load the gameplay scene.")
	var game: Node = game_scene.instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame
	return game


func test_scene_owns_supply_timer_and_simulation_state() -> void:
	var game: Node = await _instantiate_game()
	var simulator: Node = game.get_node("SupplyChainSimulator")
	assert(simulator != null, "Gameplay scene should own a supply-chain component.")
	assert(simulator.get_node("SupplyChainTimer") is Timer,
			"Supply timer should belong to the simulator, not the scene root.")
	assert(game.get_node_or_null("SupplyChainTimer") == null,
			"Scene root should no longer own the supply timer.")
	assert(game.get("_supply_chain") == simulator,
			"Root should expose the component as the single source of supply state.")
	game.queue_free()
	await get_tree().process_frame


func test_factory_first_allocation_and_goods_distribution_order_is_preserved() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var simulator: Node = game.get_node("SupplyChainSimulator")
	var factory_a: Vector2i = Vector2i(5, 5)
	var factory_b: Vector2i = Vector2i(9, 5)
	var house_a: Vector2i = Vector2i(5, 8)
	var house_b: Vector2i = Vector2i(9, 8)
	var road_factory_a: Vector2i = Vector2i(5, 4)
	var road_factory_b: Vector2i = Vector2i(9, 4)
	var road_house_a: Vector2i = Vector2i(5, 9)
	var road_house_b: Vector2i = Vector2i(9, 9)

	# GridManager's occupied-position traversal order is preserved deliberately:
	# factory A precedes B; residence A precedes B in goods allocation.
	grid.set_tile(factory_a, GridCellData.new(GridCellData.TileType.INDUSTRIAL))
	grid.set_tile(factory_b, GridCellData.new(GridCellData.TileType.INDUSTRIAL))
	grid.set_tile(house_a, GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
	grid.set_tile(house_b, GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
	grid.set_tile(road_factory_a, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(road_factory_b, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(road_house_a, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(road_house_b, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(Vector2i(4, 4), GridCellData.new(GridCellData.TileType.WATER_TOWER_SMALL))
	grid.set_tile(Vector2i(8, 4), GridCellData.new(GridCellData.TileType.WATER_TOWER_SMALL))
	game.call("_on_supply_chain_tick")

	assert(int(simulator.get("worker_capacity")) == 6,
			"Two high-density homes should provide six workers.")
	assert(int(simulator.get("operating_factories")) == 2,
			"Factory allocation should remain ahead of farm and residence allocation.")
	assert(bool((game.get("_economy") as EconomyManager).staffed_factories.has(factory_a)
			and (game.get("_economy") as EconomyManager).staffed_factories.has(factory_b)),
			"The shared staffed-factory set must match factory eligibility.")
	assert(int(simulator.get("goods_produced_last_tick")) == 4,
			"Two unhooked factories should preserve the original rounded reduced output.")
	assert(int(simulator.get("goods_consumed_last_tick")) == 2,
			"Road-connected homes should consume the resulting goods in grid order.")
	assert(bool(simulator.get("goods_supplied").get(house_a, false))
			and bool(simulator.get("goods_supplied").get(house_b, false)),
			"The same homes should be marked supplied in the simulation results.")
	assert(int(game.call("residential_goods_tax_bonus_at", house_a)) == 5,
			"Economy callback should read the simulator's supplied-home result.")
	game.queue_free()
	await get_tree().process_frame


func test_save_rebuild_preserves_goods_stock_and_supply_results() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var simulator: Node = game.get_node("SupplyChainSimulator")
	var house_pos: Vector2i = Vector2i(5, 5)
	grid.set_tile(house_pos, GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
	simulator.set("goods_stock", 9)
	simulator.call("set_supplied_goods", house_pos, true)
	game.set("_is_load_rebuild", true)
	game.call("_on_supply_chain_tick")
	assert(int(simulator.get("goods_stock")) == 9,
			"Load rebuild should retain the saved stock without consuming it.")
	assert(bool(simulator.get("goods_supplied").get(house_pos, false)),
			"Load rebuild should preserve saved supply flags.")
	game.queue_free()
	await get_tree().process_frame


func test_hud_snapshot_and_goods_supplied_serialization_roundtrip() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var simulator: SupplyChainSimulator = game.get_node("SupplyChainSimulator") as SupplyChainSimulator

	var road_pos: Vector2i = Vector2i(5, 4)
	var factory_pos: Vector2i = Vector2i(5, 5)
	var house_pos: Vector2i = Vector2i(6, 4)
	grid.set_tile(road_pos, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(factory_pos, GridCellData.new(GridCellData.TileType.INDUSTRIAL))
	grid.set_tile(house_pos, GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
	grid.set_tile(Vector2i(4, 4), GridCellData.new(GridCellData.TileType.WATER_TOWER_SMALL))
	game.call("_on_supply_chain_tick")

	var snapshot: Dictionary = simulator.get_resource_hud_snapshot()
	assert(int(snapshot["worker_capacity"]) == 3,
			"Snapshot should report 3 workers from one high-density residence.")
	assert(int(snapshot["employed_workers"]) == 2 and int(snapshot["available_workers"]) == 1,
			"Snapshot should report 2 employed and 1 available worker.")
	assert(int(snapshot["staffed_factory_count"]) == 1 and int(snapshot["factory_count"]) == 1,
			"Snapshot should report 1 staffed factory out of 1 total.")
	assert(int(snapshot["supplied_homes"]) == 1 and int(snapshot["residences"]) == 1,
			"Snapshot should report 1 supplied residence out of 1 total.")
	assert(simulator.get_factory_delivered_goods(factory_pos) == 2,
			"Unhooked factory should report 2 delivered goods in simulator query.")

	var serialized: Array[Dictionary] = simulator.serialize_goods_supplied()
	assert(serialized.size() == 1, "Serialized goods_supplied should contain 1 residence entry.")
	simulator.clear_supplied_goods()
	assert(not simulator.is_home_supplied(house_pos), "Clearing supplied goods should reset home state.")
	simulator.restore_goods_supplied(serialized)
	assert(simulator.is_home_supplied(house_pos), "Restoring serialized entries should reinstate supplied status.")

	game.queue_free()
	await get_tree().process_frame


func test_hybrid_water_pool_allocation_and_unwatered_factory_penalty() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var simulator: SupplyChainSimulator = game.get_node("SupplyChainSimulator") as SupplyChainSimulator

	# Network A: Small Water Tower (+30) + Large Water Tower (+80) = 110 capacity.
	var road_a1: Vector2i = Vector2i(5, 5)
	var road_a2: Vector2i = Vector2i(6, 5)
	var tower_small: Vector2i = Vector2i(5, 4)
	var tower_large: Vector2i = Vector2i(6, 4)
	var home_a: Vector2i = Vector2i(5, 6)
	var factory_a: Vector2i = Vector2i(6, 6)

	# Network B (disconnected from A): no water tower.
	var road_b1: Vector2i = Vector2i(10, 5)
	var home_b: Vector2i = Vector2i(10, 4)
	var factory_b: Vector2i = Vector2i(10, 6)

	grid.set_tile(road_a1, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(road_a2, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(tower_small, GridCellData.new(GridCellData.TileType.WATER_TOWER_SMALL))
	grid.set_tile(tower_large, GridCellData.new(GridCellData.TileType.WATER_TOWER_LARGE))
	grid.set_tile(home_a, GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
	grid.set_tile(factory_a, GridCellData.new(GridCellData.TileType.INDUSTRIAL))

	grid.set_tile(road_b1, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(home_b, GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
	grid.set_tile(factory_b, GridCellData.new(GridCellData.TileType.INDUSTRIAL))

	game.call("_on_supply_chain_tick")

	assert(simulator.water_capacity_last_tick == 110,
			"Small (+30) and Large (+80) Water Towers should pool to 110 water capacity.")
	assert(simulator.is_water_supplied(home_a) and simulator.is_water_supplied(factory_a),
			"Buildings on the same road network as the Water Towers must receive water.")
	assert(not simulator.is_water_supplied(home_b) and not simulator.is_water_supplied(factory_b),
			"Buildings on an isolated road network without a Water Tower must not receive water.")
	assert(simulator.get_factory_delivered_goods(factory_a) == 2,
			"Watered unhooked factory should produce 2 goods.")
	assert(simulator.get_factory_delivered_goods(factory_b) == 1,
			"Unwatered unhooked factory should suffer the 50% water penalty and produce 1 good.")

	# Connect Network A and Network B with roads -> Network B now receives water from Network A's pool.
	for x: int in range(7, 10):
		grid.set_tile(Vector2i(x, 5), GridCellData.new(GridCellData.TileType.ROAD))
	game.call("_on_supply_chain_tick")

	assert(simulator.is_water_supplied(home_b) and simulator.is_water_supplied(factory_b),
			"Connecting the road networks should distribute water to Network B.")
	assert(simulator.water_demand_last_tick == 4 and simulator.water_delivered_last_tick == 4,
			"2 residences + 2 factories should demand and receive 4 water units per tick.")
	assert(simulator.get_factory_delivered_goods(factory_b) == 2,
			"Now-watered factory B should recover to full output.")

	game.queue_free()
	await get_tree().process_frame
