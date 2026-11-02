extends Node


func test_farm_placement_requires_road_and_respects_radius() -> void:
	var grid: GridManager = GridManager.new()
	var controller: PlacementController = PlacementController.new()
	controller.grid = grid
	controller.grid_size = 20

	var road_connectivity: RoadConnectivityManager = RoadConnectivityManager.new()
	road_connectivity.configure(grid, 20)
	controller.road_connectivity = road_connectivity
	var missing_road: Dictionary = controller.attempt_build(
			GridCellData.TileType.FARMHOUSE, Vector2i(5, 5), 1000)
	assert(not bool(missing_road["ok"]), "Farmhouse without an adjacent road was accepted.")

	grid.set_tile(Vector2i(4, 5), GridCellData.new(GridCellData.TileType.ROAD))
	var farmhouse_result: Dictionary = controller.attempt_build(
			GridCellData.TileType.FARMHOUSE, Vector2i(5, 5), 1000)
	assert(bool(farmhouse_result["ok"]), "Road-connected Farmhouse was rejected.")
	assert(int(farmhouse_result["money"]) == 860, "Farmhouse cost was not deducted.")

	var in_radius: Dictionary = controller.attempt_build(
			GridCellData.TileType.FARMLAND, Vector2i(5, 8), 860)
	assert(bool(in_radius["ok"]), "Farmland within radius 3 was rejected.")
	assert(int(in_radius["money"]) == 840, "Farmland cost was not deducted.")

	var out_of_radius: Dictionary = controller.attempt_build(
			GridCellData.TileType.FARMLAND, Vector2i(5, 9), 840)
	assert(not bool(out_of_radius["ok"]), "Farmland outside radius 3 was accepted.")
	assert(str(out_of_radius["reason"]).contains("within 3 tiles"),
			"Out-of-range field rejection should explain the rule.")

	controller.free()
	road_connectivity.configure(null, 20)
	road_connectivity.free()
	grid.free()


func test_road_connected_farmhouses_assign_fields_and_scale_output() -> void:
	var grid: GridManager = GridManager.new()
	var farm_system: FarmSystem = FarmSystem.new()
	var road_connectivity: RoadConnectivityManager = RoadConnectivityManager.new()
	road_connectivity.configure(grid, 20)
	var farmhouse_pos: Vector2i = Vector2i(5, 5)
	grid.set_tile(farmhouse_pos, GridCellData.new(GridCellData.TileType.FARMHOUSE))
	var field_positions: Array[Vector2i] = [
		Vector2i(5, 6), Vector2i(5, 7), Vector2i(5, 8),
		Vector2i(6, 5), Vector2i(7, 5), Vector2i(8, 5), Vector2i(4, 5),
	]
	for field_pos: Vector2i in field_positions:
		grid.set_tile(field_pos, GridCellData.new(GridCellData.TileType.FARMLAND))

	var disconnected: Dictionary = farm_system.get_connected_farmhouse_field_counts(
			grid, road_connectivity)
	assert(disconnected.is_empty(), "Unconnected farmhouse should not operate.")

	grid.set_tile(Vector2i(4, 5), GridCellData.new(GridCellData.TileType.ROAD))
	var field_counts: Dictionary = farm_system.get_connected_farmhouse_field_counts(
			grid, road_connectivity)
	assert(int(field_counts.get(farmhouse_pos, -1)) == 6,
			"Productive field assignment should cap at six fields per Farmhouse.")
	assert(farm_system.goods_for_field_count(int(field_counts[farmhouse_pos])) == 6,
			"Each assigned field should add one good per supply tick.")
	road_connectivity.configure(null, 20)
	road_connectivity.free()
	grid.free()


func test_supply_tick_adds_farm_goods_to_shared_home_pool() -> void:
	var scene: PackedScene = load("res://node_2d.tscn") as PackedScene
	assert(scene != null, "Could not load the gameplay scene.")
	var game: Node = scene.instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame

	var grid: GridManager = game.get("_grid") as GridManager
	var road_pos: Vector2i = Vector2i(5, 9)
	var farmhouse_pos: Vector2i = Vector2i(5, 10)
	var field_a: Vector2i = Vector2i(5, 11)
	var field_b: Vector2i = Vector2i(6, 10)
	var home_road_pos: Vector2i = Vector2i(4, 9)
	var home_pos: Vector2i = Vector2i(4, 10)
	var road_connectivity: RoadConnectivityManager = game.get(
			"_road_connectivity") as RoadConnectivityManager
	grid.set_tile(road_pos, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(farmhouse_pos, GridCellData.new(GridCellData.TileType.FARMHOUSE))
	grid.set_tile(field_a, GridCellData.new(GridCellData.TileType.FARMLAND))
	grid.set_tile(field_b, GridCellData.new(GridCellData.TileType.FARMLAND))
	grid.set_tile(home_road_pos, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(home_pos, GridCellData.new(GridCellData.TileType.RESIDENTIAL_HIGH))
	game.call("refresh_road_connections", farmhouse_pos)
	game.call("refresh_road_connections", home_pos)
	game.call("_on_supply_chain_tick")

	assert(int(game.get("operating_farmhouses")) == 1,
			"A road-connected Farmhouse with a worker should operate.")
	assert(int(game.get("farm_goods_produced_last_tick")) == 2,
			"Two active fields should produce two goods.")
	assert(int(game.get("goods_consumed_last_tick")) == 1,
			"The nearby road-connected home should consume farm goods.")
	assert(int(game.get("goods_stock")) == 1,
			"Farm output should enter the shared pool before home consumption.")
	game.queue_free()
	await get_tree().process_frame
