extends Node


func _instantiate_game() -> Node:
	var game_scene: PackedScene = load("res://node_2d.tscn") as PackedScene
	assert(game_scene != null, "Could not load the gameplay scene.")
	var game: Node = game_scene.instantiate()
	get_tree().root.add_child(game)
	await get_tree().process_frame
	return game


func test_grid_edits_drive_supply_eligibility_and_road_objective() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var connectivity: RoadConnectivityManager = game.get_node(
			"RoadConnectivityManager") as RoadConnectivityManager
	var home_a: Vector2i = Vector2i(6, 10)
	var home_b: Vector2i = Vector2i(8, 10)
	var factory: Vector2i = Vector2i(10, 10)
	var home_road_a: Vector2i = Vector2i(6, 9)
	var home_road_b: Vector2i = Vector2i(8, 9)
	var factory_road: Vector2i = Vector2i(10, 9)

	game.set("_foundations_complete", true)
	grid.set_tile(home_a, GridCellData.new(GridCellData.TileType.RESIDENTIAL_LOW))
	grid.set_tile(home_b, GridCellData.new(GridCellData.TileType.RESIDENTIAL_LOW))
	grid.set_tile(factory, GridCellData.new(GridCellData.TileType.INDUSTRIAL))
	game.call("_update_objectives")
	game.call("_on_supply_chain_tick")
	assert(not bool(game.get("_obj_road_connected")),
			"Road objective must remain pending while buildings are disconnected.")
	assert(int(game.get("operating_factories")) == 0,
			"A disconnected factory must not enter the supply simulation.")
	assert(int(game.get("road_connected_homes_last_tick")) == 0,
			"Disconnected homes must not count as road-connected.")

	grid.set_tile(home_road_a, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(home_road_b, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(factory_road, GridCellData.new(GridCellData.TileType.ROAD))
	game.call("_update_objectives")
	game.call("_on_supply_chain_tick")
	assert(connectivity.is_road_connected(home_a)
			and connectivity.is_road_connected(home_b)
			and connectivity.is_road_connected(factory),
			"Connectivity service must refresh when a neighboring road is added.")
	assert(bool(game.get("_obj_road_connected")),
			"Road objective must complete once all required buildings touch a road.")
	assert(int(game.get("operating_factories")) == 1,
			"Adding the factory's road must make it simulation-eligible.")
	assert(int(game.get("road_connected_homes_last_tick")) == 2,
			"Both connected homes must be counted by the supply simulation.")

	grid.set_tile(factory_road, GridCellData.new(GridCellData.TileType.GRASS))
	game.call("_update_objectives")
	game.call("_on_supply_chain_tick")
	assert(not connectivity.is_road_connected(factory),
			"Connectivity service must refresh when a neighboring road is removed.")
	assert(not bool(game.get("_obj_road_connected")),
			"Road objective must return to pending when a required road is removed.")
	assert(int(game.get("operating_factories")) == 0,
			"Removing the factory's road must remove it from supply eligibility.")

	grid.set_tile(home_road_a, GridCellData.new(GridCellData.TileType.GRASS))
	game.call("_update_objectives")
	game.call("_on_supply_chain_tick")
	assert(int(game.get("road_connected_homes_last_tick")) == 1,
			"Removing a home road must update connected-home telemetry immediately.")
	assert(not bool(game.get("_obj_road_connected")),
			"Objective must stay pending while any required building lacks a road.")

	game.queue_free()
	await get_tree().process_frame


func test_road_network_components_and_water_tower_connectivity() -> void:
	var game: Node = await _instantiate_game()
	var grid: GridManager = game.get_node("GridManager") as GridManager
	var connectivity: RoadConnectivityManager = game.get_node(
			"RoadConnectivityManager") as RoadConnectivityManager

	var road_net_a1: Vector2i = Vector2i(4, 4)
	var road_net_a2: Vector2i = Vector2i(5, 4)
	var tower_a: Vector2i = Vector2i(4, 5)
	var home_a: Vector2i = Vector2i(5, 5)

	var road_net_b1: Vector2i = Vector2i(7, 4)
	var home_b: Vector2i = Vector2i(7, 5)
	var bridge_road: Vector2i = Vector2i(6, 4)

	grid.set_tile(road_net_a1, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(road_net_a2, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(tower_a, GridCellData.new(GridCellData.TileType.WATER_TOWER_SMALL))
	grid.set_tile(home_a, GridCellData.new(GridCellData.TileType.RESIDENTIAL_LOW))
	grid.set_tile(road_net_b1, GridCellData.new(GridCellData.TileType.ROAD))
	grid.set_tile(home_b, GridCellData.new(GridCellData.TileType.RESIDENTIAL_LOW))

	assert(connectivity.is_road_connected(tower_a),
			"Water Tower adjacent to a road must register as road-connected.")
	assert(connectivity.are_on_same_road_network(tower_a, home_a),
			"Water Tower and home on the same contiguous road must share a network.")
	assert(not connectivity.are_on_same_road_network(tower_a, home_b),
			"Buildings on separate road clusters must not share a road network.")

	# Merge the two road networks with a connecting road tile.
	grid.set_tile(bridge_road, GridCellData.new(GridCellData.TileType.ROAD))
	assert(connectivity.are_on_same_road_network(tower_a, home_b),
			"Bridging two road clusters must merge them into one road network.")

	# Split the road networks again.
	grid.set_tile(bridge_road, GridCellData.new(GridCellData.TileType.GRASS))
	assert(not connectivity.are_on_same_road_network(tower_a, home_b),
			"Removing the bridge road must split the road networks again.")

	game.queue_free()
	await get_tree().process_frame
