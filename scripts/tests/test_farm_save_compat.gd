extends Node


func test_farm_tile_ids_are_accepted_by_save_validation() -> void:
	var save_manager: Node = get_node_or_null("/root/GameSave")
	assert(save_manager != null, "GameSave autoload is missing.")
	var state: Dictionary = {
		"grid_size": 20,
		"tiles": [
			{"x": 5, "y": 5, "type": GridCellData.TileType.FARMHOUSE,
				"land_value_modifier": 0.0},
			{"x": 5, "y": 6, "type": GridCellData.TileType.FARMLAND,
				"land_value_modifier": 0.0},
			{"x": 6, "y": 5, "type": GridCellData.TileType.WATER_TOWER_SMALL,
				"land_value_modifier": 0.0},
			{"x": 6, "y": 6, "type": GridCellData.TileType.WATER_TOWER_LARGE,
				"land_value_modifier": 0.0},
		],
		"goods_supplied": [],
		"tile_claimed_times": [],
		"tile_build_times": [],
		"factory_strikes": [],
		"tutorial_resolved": false,
		"money": 1000,
		"goods_stock": 0,
		"dividend_percent": 0.0,
		"assessment_time_left": 5.0,
		"supply_time_left": 3.0,
	}
	var validation_error: String = str(save_manager.call("_validate_game_state", state))
	assert(validation_error == "", "Save validation rejected farm tile IDs: %s" % validation_error)
