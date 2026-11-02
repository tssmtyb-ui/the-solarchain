extends Node

const SAVE_PATH: String = "user://solarchain_save.json"


func test_valid_save_roundtrip_and_invalid_save_rejection() -> void:
	var manager: Node = get_node_or_null("/root/GameSave")
	assert(manager != null, "GameSave autoload is missing.")
	var test_state: Dictionary = {
		"grid_size": 20,
		"tiles": [
			{"x": 3, "y": 4, "type": 1, "land_value_modifier": 0.0}
		],
		"goods_supplied": [{"x": 3, "y": 4, "supplied": true}],
		"tile_claimed_times": [{"x": 3, "y": 4, "time_delta": -500}],
		"tile_build_times": [],
		"factory_strikes": [],
		"tutorial_resolved": false,
		"money": 1200,
		"goods_stock": 8,
		"dividend_percent": 15.0,
		"assessment_time_left": 4.5,
		"supply_time_left": 2.5,
	}
	var save_method: Callable = Callable(manager, "save_game")
	var load_method: Callable = Callable(manager, "load_game")
	var prior_save_existed: bool = FileAccess.file_exists(SAVE_PATH)
	var prior_save_text: String = ""
	if prior_save_existed:
		var prior_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
		assert(prior_file != null, "Could not back up the existing user save.")
		prior_save_text = prior_file.get_as_text()
		prior_file.close()
	assert(bool(save_method.call(test_state)), "Could not write the fixture save.")
	var loaded: Dictionary = load_method.call()
	assert(not loaded.is_empty(), "Valid save did not load: %s" % manager.get("last_error"))
	var loaded_tiles: Array = loaded.get("tiles", []) as Array
	var loaded_tile: Dictionary = loaded_tiles[0] as Dictionary
	var expected_tile: Dictionary = (test_state["tiles"] as Array)[0] as Dictionary
	assert(int(loaded_tile.get("x", -1)) == int(expected_tile["x"]) \
			and int(loaded_tile.get("y", -1)) == int(expected_tile["y"]) \
			and int(loaded_tile.get("type", -1)) == int(expected_tile["type"]) \
			and is_equal_approx(float(loaded_tile.get("land_value_modifier", -1.0)), \
				float(expected_tile["land_value_modifier"])), \
			"Tile records changed during JSON round-trip.")
	var loaded_goods: Array = loaded.get("goods_supplied", []) as Array
	var loaded_good: Dictionary = loaded_goods[0] as Dictionary
	assert(int(loaded_good.get("x", -1)) == 3 and int(loaded_good.get("y", -1)) == 4 \
			and bool(loaded_good.get("supplied", false)), \
			"Goods state changed during JSON round-trip.")
	assert(int(loaded.get("save_version", -1)) == 1, "Save version was not written.")
	print("VALID_SAVE_ROUNDTRIP_OK")

	var data_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.READ)
	assert(data_file != null, "Could not reopen fixture save.")
	var raw_text: String = data_file.get_as_text()
	data_file.close()
	var json: JSON = JSON.new()
	assert(json.parse(raw_text) == OK and json.data is Dictionary, "Save file is not valid JSON.")
	var corrupted: Dictionary = json.data as Dictionary
	var corrupted_tiles: Array = corrupted["tiles"] as Array
	var bad_tile: Dictionary = (corrupted_tiles[0] as Dictionary).duplicate(true)
	bad_tile["x"] = 999
	corrupted_tiles[0] = bad_tile
	corrupted["tiles"] = corrupted_tiles
	var write_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	assert(write_file != null, "Could not write malformed fixture save.")
	write_file.store_string(JSON.stringify(corrupted))
	write_file.close()
	loaded = load_method.call()
	assert(loaded.is_empty(), "Malformed tile position was accepted.")
	assert(str(manager.get("last_error")) != "", "Malformed save did not expose a readable error.")
	print("INVALID_SAVE_REJECTED_OK")
	if prior_save_existed:
		var restore_file: FileAccess = FileAccess.open(SAVE_PATH, FileAccess.WRITE)
		assert(restore_file != null, "Could not restore the user's previous save file.")
		restore_file.store_string(prior_save_text)
		restore_file.close()
	else:
		var remove_error: Error = DirAccess.remove_absolute(
				ProjectSettings.globalize_path(SAVE_PATH))
		assert(remove_error == OK, "Could not remove test fixture save file.")
